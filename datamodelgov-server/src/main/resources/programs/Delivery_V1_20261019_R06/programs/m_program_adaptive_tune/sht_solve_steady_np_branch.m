function result = sht_solve_steady_np_branch( ...
        engine, cfg, stepInValue, baseSeed, ptLoadTorqueNm, ...
        gtLoadTorqueNm, branch, userOptions)
%SHT_SOLVE_STEADY_NP_BRANCH 在数据驱动的Np合理范围内选择稳态共同工作根。
%
% 不对预测Np作事后裁剪。verified_nearest策略比较中心和邻近Np/Ng
% 初值得到的根，防止宽范围内“第一个收敛根”随微扰跳变；求导时使用
% 中心模型根附近的局部区间。first_inside仅用于保持旧调用合同兼容。
%
% branch必须给出：
%   centerRpm          Np合理分支中心，rpm；
%   lowerRpm/upperRpm  Np合理范围上下界，rpm；
%   relativeHalfWidth  相对半宽，用于构造分层Np初值。
%
% torque模式按候选Np/Ng与外部扭矩实时换算功率；fixed_power模式
% 使用stepIn(6:7)中独立给定的功率，不使用测试Np换算或裁剪预测Np。

if nargin < 8 || isempty(userOptions), userOptions = struct(); end
options = local_options(userOptions);
npIndex=numel(baseSeed)-1;
local_validate_input(cfg, baseSeed, ptLoadTorqueNm, ...
    gtLoadTorqueNm, branch, options);
nativeTorque=stepInValue(8)==1;
if nativeTorque
    assert(strcmp(options.loadBoundary,'torque') && ...
        isequal(stepInValue(6:7),[ptLoadTorqueNm;gtLoadTorqueNm]), ...
        'SHT:SteadyNpBranchSolve:TorqueContract', ...
        '原生扭矩模式必须传递一致的Mkp/Mkg，不能混用功率边界。');
end

phaseName = ["center", "near", "extended", "far"];
phaseMultiplier = {0, [-0.75, 0.75], ...
    [-1, 1, -1.5, 1.5, -2, 2, -2.5, 2.5, -3.15, 3.15], ...
    [-4, 4, -5, 5, -6.3, 6.3]};
verified=strcmp(options.selectionPolicy,'verified_nearest');
ngOffsets=cellfun(@(x)zeros(size(x)),phaseMultiplier,'UniformOutput',false);
if verified
    % 有效Np带内搜索；Ng只作为数值初值变化，不形成新输入或新残差。
    phaseName=["center","near","extended"];
    phaseMultiplier={0,[-.5,.5,0,0],[-.95,.95,0,0]};
    ngOffsets={0,[0,0,-.03,.03],[0,0,-.06,.06]};
end
if ~options.enableAdaptiveRetry
    phaseName = phaseName(1);
    phaseMultiplier = phaseMultiplier(1);
    ngOffsets=ngOffsets(1);
end

attempt = repmat(local_empty_attempt(), 0, 1);
selectedIndex = NaN;
nearestStrictIndex = NaN;
nearestStrictDistance = Inf;
bestFallbackIndex = NaN;
bestFallbackResidual = Inf;

for p = 1:numel(phaseMultiplier)
    currentPhaseIndex = zeros(0, 1);
    multiplier = phaseMultiplier{p};
    for k = 1:numel(multiplier)
        relativeOffset = multiplier(k) * branch.relativeHalfWidth;
        if 1 + relativeOffset <= 0
            continue;
        end
        seed = baseSeed(:);
        seed(npIndex) = branch.centerRpm * ...
            (1 + relativeOffset);
        seed(end)=baseSeed(end)*(1+ngOffsets{p}(k));
        if strcmp(options.loadBoundary,'fixed_power') || nativeTorque
            solve=local_native_solve(engine,cfg,stepInValue,seed,branch,options);
        else
            solve = sht_solve_steady_components_from_seed( ...
                engine, cfg, stepInValue, seed, struct( ...
                'ptLoadTorqueNm', ptLoadTorqueNm, ...
                'gtLoadTorqueNm', gtLoadTorqueNm, ...
                'exhaustBackPressureModel',options.exhaustBackPressureModel));
        end

        item = local_empty_attempt();
        item.phase = phaseName(p);
        item.multiplier = multiplier(k);
        item.relativeOffset = relativeOffset;
        item.initialNpRpm = seed(npIndex);
        item.initialNgRpm = seed(end);
        item.solutionNpRpm = double(solve.engOut.eng.LPS_Nmech);
        item.solutionNgRpm = double(solve.engOut.eng.HPS_Nmech);
        item.maxModelResidual = double(solve.maxModelResidual);
        item.residualInfinityNorm = double(solve.residualInfinityNorm);
        item.returnCode = double(solve.ret);
        item.converged = logical(solve.converged);
        item.strict = item.converged && item.returnCode == 0 && ...
            isfinite(item.solutionNpRpm) && item.solutionNpRpm>0 && ...
            isfinite(item.maxModelResidual) && ...
            item.maxModelResidual <= options.strictResidual;
        item.insideGate = item.strict && ...
            item.solutionNpRpm >= branch.lowerRpm && ...
            item.solutionNpRpm <= branch.upperRpm;
        item.relativeDistance = abs(item.solutionNpRpm - ...
            branch.centerRpm) / branch.centerRpm;
        item.seed = seed;
        item.solve = solve;
        if isfield(solve,'solverBackend')
            item.solverBackend=string(solve.solverBackend);
            item.dllCalls=double(solve.dllAttempted);
            item.matlabCalls=double(~strcmp(solve.solverBackend,'DLL_RunOnePoint'));
        else
            item.solverBackend="MATLAB_torque";item.matlabCalls=1;
        end
        attempt(end + 1, 1) = item; %#ok<AGROW>
        index = numel(attempt);
        currentPhaseIndex(end + 1, 1) = index; %#ok<AGROW>

        if item.strict && item.relativeDistance < nearestStrictDistance
            nearestStrictDistance = item.relativeDistance;
            nearestStrictIndex = index;
        end
        fallbackScore = max(item.maxModelResidual, ...
            item.residualInfinityNorm);
        if isfinite(fallbackScore) && fallbackScore < bestFallbackResidual
            bestFallbackResidual = fallbackScore;
            bestFallbackIndex = index;
        end
    end

    if verified
        inside=find([attempt.insideGate]);
    else
        inside=currentPhaseIndex([attempt(currentPhaseIndex).insideGate]);
    end
    if ~isempty(inside)
        [~, localIndex] = min([attempt(inside).relativeDistance]);
        selectedIndex = inside(localIndex);
        % 默认至少完成near层再选根；局部求导例外，由外层已验证中心根
        % 限定窄区间，只需沿该根追踪。更远的全局种子仅在无有效根时用。
        localContinuation=isfield(branch,'localContinuation') && branch.localContinuation;
        closeToVerifiedCenter=localContinuation && ...
            attempt(selectedIndex).relativeDistance<=min(.005,branch.relativeHalfWidth);
        if ~verified || p>=min(2,numel(phaseMultiplier)) || closeToVerifiedCenter
            break;
        end
    end
    if ~verified && options.allowOutsidePreference && p>=min(2,numel(phaseMultiplier)) && ...
            isfinite(nearestStrictIndex)
        % 训练时Np本来就是待拟合输出。零修正模型可能没有落在测量
        % 附近的根；先尝试中心及邻近初值，再保留最近的严格正转速根，
        % 让真实Np残差驱动辨识，不能以20%偏差在A开始前截断优化。
        selectedIndex=nearestStrictIndex;
        break;
    end
end

if ~isfinite(selectedIndex) && options.allowOutsidePreference && isfinite(nearestStrictIndex)
    % 仅由调用者显式批准的常值初始化诊断。不能把该结果标成分支通过。
    selectedIndex=nearestStrictIndex;
end

passed = isfinite(selectedIndex);
if ~passed
    if isfinite(nearestStrictIndex)
        selectedIndex = nearestStrictIndex;
        reason = "strict_roots_outside_branch_gate";
    elseif isfinite(bestFallbackIndex)
        selectedIndex = bestFallbackIndex;
        reason = "no_strict_converged_root";
    else
        error('SHT:SteadyNpBranchSolve:NoFiniteAttempt', ...
            '所有Np分支初值均未返回可用于诊断的有限共同工作结果。');
    end
else
    reason = "strict_root_inside_branch_gate";
end

selected = attempt(selectedIndex);
if passed && ~selected.insideGate,reason="strict_root_outside_training_preference";end
rootTable = local_root_table(attempt, selectedIndex, branch);
result = struct( ...
    'schemaVersion', 'steady_np_branch_solve_v1', ...
    'passed', passed, 'reason', reason, ...
    'selectedAttempt', selectedIndex, ...
    'attemptCount', numel(attempt), ...
    'selectedSeed', selected.seed, ...
    'selectedSolve', selected.solve, ...
    'selectedNpRpm', selected.solutionNpRpm, ...
    'selectedRelativeDistance', selected.relativeDistance, ...
    'branch', branch, 'strictResidual', options.strictResidual, ...
    'rootTable', rootTable, ...
    'testNpUsedForBranchSelection', false, ...
    'testNpUsedForLoadPower', false, ...
    'dllCallCount',sum([attempt.dllCalls]), ...
    'matlabCallCount',sum([attempt.matlabCalls]));
result.outsidePreferenceAdmitted=passed && ~selected.insideGate;
result.selectionPolicy=options.selectionPolicy;
result.branchConstraintPassed=passed && selected.insideGate;
end

function options = local_options(userOptions)
if ~isstruct(userOptions) || ~isscalar(userOptions)
    error('SHT:SteadyNpBranchSolve:BadOptions', ...
        'userOptions必须为标量结构体。');
end
options = struct('strictResidual', 1e-7, ...
    'enableAdaptiveRetry', true,'exhaustBackPressureModel',[], ...
    'loadBoundary','torque','solver','matlab','allowOutsidePreference',false, ...
    'selectionPolicy','first_inside');
names = fieldnames(options);
for i = 1:numel(names)
    if isfield(userOptions, names{i}) && ~isempty(userOptions.(names{i}))
        options.(names{i}) = userOptions.(names{i});
    end
end
if ~isnumeric(options.strictResidual) || ...
        ~isscalar(options.strictResidual) || ...
        ~isfinite(options.strictResidual) || options.strictResidual <= 0
    error('SHT:SteadyNpBranchSolve:BadResidualThreshold', ...
        'strictResidual必须为有限正标量。');
end
if ~islogical(options.enableAdaptiveRetry) || ...
        ~isscalar(options.enableAdaptiveRetry)
    error('SHT:SteadyNpBranchSolve:BadRetrySwitch', ...
        'enableAdaptiveRetry必须为逻辑标量。');
end
assert(ismember(string(options.loadBoundary),["torque","fixed_power"]), ...
    'SHT:SteadyNpBranchSolve:Boundary','负载边界应为torque或fixed_power。');
assert(ismember(string(options.solver),["matlab","dll_first"]), ...
    'SHT:SteadyNpBranchSolve:Solver','稳态求解器应为matlab或dll_first。');
assert(islogical(options.allowOutsidePreference) && isscalar(options.allowOutsidePreference), ...
    'SHT:SteadyNpBranchSolve:Preference','训练分支偏好开关必须为逻辑标量。');
assert(ismember(string(options.selectionPolicy),["first_inside","verified_nearest"]), ...
    'SHT:SteadyNpBranchSolve:Selection','未知Np选根策略。');
end

function solve=local_native_solve(engine,cfg,input,seed,branch,options)
% RunOnePoint与备用MATLAB求解器使用同一输入模式和同一负载。
% 扭矩模式在DLL的每次残差求值内部换算，不冻结为初值处功率。
% 选根范围只筛选数学根，不固定或裁剪预测转速。
dllAttempted=false;
if strcmp(options.solver,'dll_first') && isempty(options.exhaustBackPressureModel)
    dllAttempted=true;
    seedInput=zeros(cfg.engine.interface.stepInLength,1);
    seedInput(21:20+numel(seed))=seed;
    ptr=libstruct(engine.enginePointerName,struct('eng',libstruct(engine.engineStructName)));
    out=libpointer('doublePtr',zeros(cfg.engine.interface.stepOutLength,1));
    status=calllib(engine.libraryName,'DLL_SHT_varIteInit', ...
        libpointer('doublePtr',seedInput),out,ptr);
    assert(status==0,'SHT:SteadyPower:Seed','RunOnePoint初值写入失败。');
    [ret,~,stepOut,engOut]=calllib(engine.libraryName,'DLL_SHT_RunOnePoint', ...
        libpointer('doublePtr',input),out,ptr);
    e=engOut.eng; residual=max(abs([double(e.errOut(:));double(e.Nozzle.y(end))]));
    np=double(e.LPS_Nmech);
    if ret==0 && e.convergeTag==0 && isfinite(residual) && ...
            residual<=options.strictResidual && np>0 && ...
            ((np>=branch.lowerRpm && np<=branch.upperRpm) || options.allowOutsidePreference)
        solve=struct('ret',ret,'engOut',engOut,'stepOut',stepOut, ...
            'converged',true,'maxModelResidual',residual, ...
            'residualInfinityNorm',residual,'solverBackend','DLL_RunOnePoint', ...
            'dllAttempted',true,'matlabFallbackUsed',false, ...
            'ptLoadPowerW',double(e.LPS_Power),'gtLoadPowerW',double(e.HPS_Power));
        return;
    end
end
fallbackOptions=struct('exhaustBackPressureModel',options.exhaustBackPressureModel);
if strcmp(options.selectionPolicy,'verified_nearest') && ~options.allowOutsidePreference
    fallbackOptions.npBoundsRpm=[branch.lowerRpm,branch.upperRpm];
end
solve=sht_solve_steady_components_from_seed(engine,cfg,input,seed,fallbackOptions);
solve.solverBackend='MATLAB_fixed_power';
if input(8)==1,solve.solverBackend='MATLAB_native_torque';end
solve.dllAttempted=dllAttempted;solve.matlabFallbackUsed=dllAttempted;
end

function local_validate_input(cfg, seed, ptTorque, gtTorque, branch, options)
if ~isstruct(cfg) || ~isfield(cfg, 'engine') || ~ismember(cfg.engine.modelMode,[0,1])
    error('SHT:SteadyNpBranchSolve:BadConfig', ...
        'Np分支求解器要求三部件modelMode=0或六部件modelMode=1。');
end
if ~isnumeric(seed) || numel(seed) ~= 6+3*double(cfg.engine.modelMode==1) || any(~isfinite(seed(:)))
    error('SHT:SteadyNpBranchSolve:BadSeed', ...
        'baseSeed必须为与模型匹配的有限6维或9维共同工作初值。');
end
if ~isnumeric(ptTorque) || ~isscalar(ptTorque) || ...
        ~isfinite(ptTorque) || ...
        ~isnumeric(gtTorque) || ~isscalar(gtTorque) || ...
        ~isfinite(gtTorque)
    error('SHT:SteadyNpBranchSolve:BadTorque', ...
        'PT和GT负载扭矩必须为有限标量；正负号遵循现有DLL功率约定。');
end
required = {'centerRpm','lowerRpm','upperRpm','relativeHalfWidth'};
if ~isstruct(branch) || ~isscalar(branch) || any(~isfield(branch, required))
    error('SHT:SteadyNpBranchSolve:BadBranch', ...
        'branch缺少Np分支中心、上下界或相对半宽。');
end
value = [branch.centerRpm, branch.lowerRpm, branch.upperRpm, ...
    branch.relativeHalfWidth, options.strictResidual];
if any(~isfinite(value)) || branch.centerRpm <= 0 || ...
        branch.lowerRpm <= 0 || branch.upperRpm <= branch.lowerRpm || ...
        branch.centerRpm < branch.lowerRpm || ...
        branch.centerRpm > branch.upperRpm || ...
        branch.relativeHalfWidth <= 0
    error('SHT:SteadyNpBranchSolve:BadBranchValue', ...
        'Np分支中心、上下界或相对半宽不合法。');
end
end

function item = local_empty_attempt()
item = struct('phase', "", 'multiplier', NaN, ...
    'relativeOffset', NaN, 'initialNpRpm', NaN, ...
    'initialNgRpm',NaN,'solutionNgRpm',NaN, ...
    'solutionNpRpm', NaN, 'maxModelResidual', NaN, ...
    'residualInfinityNorm', NaN, 'returnCode', NaN, ...
    'converged', false, 'strict', false, 'insideGate', false, ...
    'relativeDistance', Inf, 'seed', nan(9, 1), 'solve', struct(), ...
    'solverBackend',"",'dllCalls',0,'matlabCalls',0);
end

function tbl = local_root_table(attempt, selectedIndex, branch)
n = numel(attempt);
phase = strings(n, 1);
multiplier = nan(n, 1);
relativeOffset = nan(n, 1);
initialNp = nan(n, 1);
solutionNp = nan(n, 1);
maxResidual = nan(n, 1);
residualInfinityNorm = nan(n, 1);
returnCode = nan(n, 1);
converged = false(n, 1);
strict = false(n, 1);
insideGate = false(n, 1);
relativeDistance = nan(n, 1);
for i = 1:n
    phase(i) = attempt(i).phase;
    multiplier(i) = attempt(i).multiplier;
    relativeOffset(i) = attempt(i).relativeOffset;
    initialNp(i) = attempt(i).initialNpRpm;
    solutionNp(i) = attempt(i).solutionNpRpm;
    maxResidual(i) = attempt(i).maxModelResidual;
    residualInfinityNorm(i) = attempt(i).residualInfinityNorm;
    returnCode(i) = attempt(i).returnCode;
    converged(i) = attempt(i).converged;
    strict(i) = attempt(i).strict;
    insideGate(i) = attempt(i).insideGate;
    relativeDistance(i) = attempt(i).relativeDistance;
end
selected = false(n, 1);
selected(selectedIndex) = true;
tbl = table((1:n).', phase, multiplier, relativeOffset, initialNp, ...
    solutionNp, maxResidual, residualInfinityNorm, returnCode, ...
    converged, strict, insideGate, relativeDistance, selected, ...
    repmat(branch.centerRpm, n, 1), repmat(branch.lowerRpm, n, 1), ...
    repmat(branch.upperRpm, n, 1), ...
    'VariableNames', {'attempt_index','phase','seed_multiplier', ...
    'seed_relative_offset','initial_Np_rpm','solution_Np_rpm', ...
    'max_model_residual','residual_inf_norm','return_code', ...
    'converged','strict','inside_gate','relative_distance', ...
    'selected','branch_center_rpm','branch_lower_rpm', ...
    'branch_upper_rpm'});
tbl.initial_Ng_rpm=[attempt.initialNgRpm].';
tbl.solution_Ng_rpm=[attempt.solutionNgRpm].';
end
