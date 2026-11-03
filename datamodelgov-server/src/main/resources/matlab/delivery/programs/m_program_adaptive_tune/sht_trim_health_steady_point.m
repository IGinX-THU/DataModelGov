function trim = sht_trim_health_steady_point(cfg, targetNpRpm, loadPowerW, health)
%SHT_TRIM_HEALTH_STEADY_POINT 配平给定健康/修正系数的发动机稳态初始点。
%
% 2.6 过渡态试车数据的 0 s 初值必须同时满足：
%   1) Np = targetNpRpm；
%   2) 负载功率 = loadPowerW；
%   3) 三部件6个或六部件9个共同工作残差收敛；
%   4) 全部 DLL 稳态调用使用调用方给定的同一组健康/修正系数。
%
% 本函数沿用 Start_TestDataGen_01 的外层牛顿配平方法。未知量为
% DLL当前模式的全部共同工作猜值和燃油Wf；残差为对应共同工作残差及
% Np误差。因而mode=0自动形成7变量问题，mode=1自动形成10变量问题。
% 该函数只求稳态气路初值，不打开热浸和动态间隙状态方程。因而
% hlthparas[58:76] 虽随接口传入，但不会改变传统稳态方程；稳态健康
% 参数 hlthparas[0:57] 则按原部件模型定义参与配平。

if nargin ~= 4 || ~isstruct(cfg) || ~isscalar(targetNpRpm) || ...
        ~isfinite(targetNpRpm) || targetNpRpm <= 0 || ...
        ~isscalar(loadPowerW) || ~isfinite(loadPowerW) || loadPowerW < 0 || ...
        ~isnumeric(health) || isempty(health) || numel(health) > 159 || ...
        any(~isfinite(health(:)))
    error('SHT:TrimHealth:BadInput', ...
        ['需要 cfg、正的目标 Np、非负目标负载功率，以及不超过159维的' ...
         '有限修正向量；旧100维向量仍按尾部补零兼容。']);
end

settings = local_settings(cfg, health);
engine = sht_engine_open(cfg.engine);
cleanup = onCleanup(@() sht_engine_close(engine));

% 对已知困难区域优先使用经过严格残差验收的固化初值。模型修正会使真实
% 解相对固化值发生偏移，因此仍执行完整Newton求解；固化值若失效，后续
% 自动回到设计点延拓路径，不会把历史初值当成新的物理约束。
reusableSeed = sht_get_steady_trim_initial_guess( ...
    cfg, targetNpRpm, loadPowerW, 'auto');
reusableSeedAttempted = reusableSeed.available && reusableSeed.isSpecialized;
if reusableSeedAttempted
    settings = local_set_variable_scale( ...
        settings, cfg, numel(reusableSeed.varIte));
    seedTrim = local_trim_stage(engine, cfg, settings, ...
        targetNpRpm, loadPowerW, reusableSeed.z);
    if ~seedTrim.converged
        seedTrim = local_trim_stage_nested(engine, cfg, settings, ...
            targetNpRpm, loadPowerW, reusableSeed.z);
    end
    if seedTrim.converged
        trim = local_attach_seed_diagnostics( ...
            seedTrim, reusableSeed, true, false);
        trim.targetNpRpm = targetNpRpm;
        trim.loadPowerW = loadPowerW;
        trim.health = settings.health;
        trim.method = sprintf( ...
            '%d-variable Newton trim from reusable seed', ...
            numel(reusableSeed.z));
        clear cleanup;
        return;
    end
end

% 固化初值不适用或局部求解失败时，由设计点 RunOnePoint 获取当前 DLL
% 对应的共同工作初值，再以设计点为起点逐步改变负载和转速。
design = local_run_onepoint(engine, cfg, settings, ...
    cfg.engine.initial.Wf0, cfg.engine.initial.power0, []);
z = [design.varIte(:); cfg.engine.initial.Wf0];
designZ = z;
settings = local_set_variable_scale(settings, cfg, numel(design.varIte));

% 负载或转速跨度较大时自动加密延拓路径。先沿负载方向延拓，再沿转速
% 方向延拓；极低负载采用几何级数，避免最后一级相对跨度过大。
[stageNpList, stagePowerList] = local_continuation_targets( ...
    cfg, targetNpRpm, loadPowerW);
stageTrim = struct();
for i = 1:numel(stageNpList)
    stageNp = stageNpList(i);
    stagePower = stagePowerList(i);
    stageTrim = local_trim_stage(engine, cfg, settings, stageNp, stagePower, z);
    if ~stageTrim.converged
        stageTrim = local_trim_stage_nested( ...
            engine, cfg, settings, stageNp, stagePower, z);
    end
    % 延拓点只是数值辅助点，不是必须经过的物理解。若某个中间点落在
    % 特性图分支切换附近，直接复核最终目标，避免把“路径不连续”误判
    % 成“最终目标不可达”。
    if ~stageTrim.converged && i < numel(stageNpList)
        finalTrim = local_trim_stage( ...
            engine, cfg, settings, targetNpRpm, loadPowerW, z);
        if ~finalTrim.converged
            finalTrim = local_trim_stage_nested( ...
                engine, cfg, settings, targetNpRpm, loadPowerW, z);
        end
        if finalTrim.converged
            stageTrim = finalTrim;
            z = stageTrim.z;
            break;
        end

        anchorTrim = local_try_low_load_anchor_path( ...
            engine, cfg, settings, targetNpRpm, loadPowerW, designZ);
        if anchorTrim.converged
            stageTrim = anchorTrim;
            z = stageTrim.z;
            break;
        end
    end
    if ~stageTrim.converged
        error('SHT:TrimHealth:NotConverged', ...
            ['给定修正系数的稳态配平在延拓阶段 %d/%d 失败：' ...
             'Np=%.9g rpm，power=%.9g W，残差无穷范数=%.3e。'], ...
            i, numel(stageNpList), stageNp, stagePower, ...
            stageTrim.residualInfinityNorm);
    end
    z = stageTrim.z;
end

trim = stageTrim;
trim.targetNpRpm = targetNpRpm;
trim.loadPowerW = loadPowerW;
trim.health = settings.health;
trim.method = sprintf('%d-variable Newton trim with continuation', numel(z));
trim = local_attach_seed_diagnostics( ...
    trim, reusableSeed, false, reusableSeedAttempted);
clear cleanup;
end

function trim = local_attach_seed_diagnostics( ...
        trim, seed, seedAccepted, fallbackToContinuation)
% 保存初值选择过程，便于参数估计批量回放时区分数值初值和物理解。
trim.initialGuessId = seed.id;
trim.initialGuessSource = seed.source;
trim.initialGuessAccepted = logical(seedAccepted);
trim.initialGuessFallbackToContinuation = logical(fallbackToContinuation);
trim.initialGuessDistance = seed.distance;
end

function [npList, powerList] = local_continuation_targets( ...
        cfg, targetNp, targetPower)
% 先改变负载、再改变转速，避免两个强耦合边界同时大幅跨越特性图区域。
% 对正功率采用几何级数，使相邻阶段的相对负载跨度基本均匀；这对1%
% 等极低负载尤其重要。转速阶段每步不超过设计转速的约5%。
np0 = cfg.engine.initial.Np0;
power0 = cfg.engine.initial.power0;

if targetPower > 0 && power0 > 0 && targetPower ~= power0
    logarithmicSpan = abs(log(targetPower / power0));
    powerStageCount = max(3, ceil(logarithmicSpan / abs(log(0.65))));
    powerFraction = (1:powerStageCount) / powerStageCount;
    powerStages = power0 * exp(powerFraction * log(targetPower / power0));
elseif targetPower ~= power0
    powerStageCount = max(3, ceil(abs(targetPower - power0) / ...
        max(0.1 * abs(power0), eps)));
    powerStages = linspace(power0, targetPower, powerStageCount + 1);
    powerStages = powerStages(2:end);
else
    powerStages = [];
end

npList = repmat(np0, 1, numel(powerStages));
powerList = powerStages;

if targetNp ~= np0
    speedStageCount = max(1, ceil(abs(targetNp - np0) / ...
        max(0.05 * abs(np0), eps)));
    speedStages = linspace(np0, targetNp, speedStageCount + 1);
    speedStages = speedStages(2:end);
    npList = [npList, speedStages];
    powerList = [powerList, ...
        repmat(targetPower, 1, numel(speedStages))];
end

if isempty(npList)
    npList = targetNp;
    powerList = targetPower;
end
end

function trim = local_try_low_load_anchor_path( ...
        engine, cfg, settings, targetNp, targetPower, designZ)
% 极低负载可能在若干中间比例处发生求解分支切换。此处以线性降载
% 路径作为与几何路径互补的第二条数值路径，再直达目标并改变转速。
trim = local_pack_trim(designZ, ...
    local_run_onepoint(engine, cfg, settings, designZ(end), ...
        cfg.engine.initial.power0, designZ(1:end-1)), ...
    inf(numel(designZ), 1), 0, false, NaN);
power0 = cfg.engine.initial.power0;
if ~(targetPower >= 0 && targetPower < 0.1 * power0)
    return;
end

anchor = struct('converged', false);
anchorZ = designZ;
for fraction = 0.1:0.1:0.9
    anchorPower = power0 + fraction * (targetPower - power0);
    anchor = local_trim_stage(engine, cfg, settings, ...
        cfg.engine.initial.Np0, anchorPower, anchorZ);
    if ~anchor.converged
        anchor = local_trim_stage_nested(engine, cfg, settings, ...
            cfg.engine.initial.Np0, anchorPower, anchorZ);
    end
    if ~anchor.converged
        return;
    end
    anchorZ = anchor.z;
end

targetPowerTrim = local_trim_stage(engine, cfg, settings, ...
    cfg.engine.initial.Np0, targetPower, anchor.z);
if ~targetPowerTrim.converged
    targetPowerTrim = local_trim_stage_nested(engine, cfg, settings, ...
        cfg.engine.initial.Np0, targetPower, anchor.z);
end
if ~targetPowerTrim.converged
    return;
end

if targetNp == cfg.engine.initial.Np0
    trim = targetPowerTrim;
    return;
end
trim = local_trim_stage( ...
    engine, cfg, settings, targetNp, targetPower, targetPowerTrim.z);
if ~trim.converged
    trim = local_trim_stage_nested( ...
        engine, cfg, settings, targetNp, targetPower, targetPowerTrim.z);
end
end

function settings = local_settings(cfg, health)
% 数值尺度与 2.3 稳态替代数据程序一致，保持两类数据生成初值口径统一。
settings = struct();
settings.maxNewtonIteration = 25;
settings.residualTolerance = 1e-7;
settings.npToleranceRpm = 0.5;
settings.normalizedPerturbation = 1e-4;
settings.scale = [];
settings.wfMin = cfg.actuator.wfMin;
settings.wfMax = cfg.actuator.wfMax;
settings.A8 = cfg.engine.initial.A80;
% 附件功率必须与时域仿真使用同一边界。旧入口均显式或缺省给出 0，
% 因而此处的缺省回退不会改变第 2 阶段配平结果；飞行模式则可传入
% 正的燃气发生器轴附件功率提取量。
settings.hpsPower = 0;
if isfield(cfg.engine, 'boundary') && isstruct(cfg.engine.boundary) && ...
        isfield(cfg.engine.boundary, 'hpsPower') && ...
        ~isempty(cfg.engine.boundary.hpsPower)
    settings.hpsPower = cfg.engine.boundary.hpsPower;
end
if ~isscalar(settings.hpsPower) || ~isfinite(settings.hpsPower) || ...
        settings.hpsPower < 0
    error('SHT:TrimHealth:BadHpsPower', ...
        'cfg.engine.boundary.hpsPower 必须是有限非负标量。');
end
settings.hpcAlpha = 0;
settings.health = health(:);
end

function settings = local_set_variable_scale(settings, cfg, variableCount)
% 与C端共同工作变量顺序一致设置归一化尺度。最后一项始终对应Wf。
if variableCount == 6
    variableScale = [10; 1; 5; 5; ...
        cfg.engine.initial.Np0; cfg.engine.initial.Ng0];
elseif variableCount == 9
    variableScale = [10; 1; 1; 5; 5; 5; 5; ...
        cfg.engine.initial.Np0; cfg.engine.initial.Ng0];
else
    error('SHT:TrimHealth:UnsupportedVariableCount', ...
        '只支持三部件6维或六部件9维共同工作变量，当前为%d维。', ...
        variableCount);
end
settings.variableCount = variableCount;
settings.scale = [variableScale; 0.3];
end

function trim = local_trim_stage(engine, cfg, settings, targetNp, power, z0)
% 每个延拓阶段求解七维非线性方程，不对六个共同工作猜值进行限幅。
% 燃油是有明确物理上下限的执行量，因此仅对 Wf 使用执行机构边界。
z = z0(:);
z(end) = min(max(z(end), settings.wfMin), settings.wfMax);

evaluation = local_eval_steady(engine, cfg, settings, power, z);
residual = local_residual(evaluation, targetNp);
bestNorm = norm(residual, inf);
conditionNumber = Inf;

for iteration = 1:settings.maxNewtonIteration
    if local_is_converged(evaluation, residual, settings, targetNp)
        finalEvaluation = local_run_onepoint(engine, cfg, settings, ...
            z(end), power, z(1:end-1));
        trim = local_pack_trim(z, finalEvaluation, residual, ...
            iteration - 1, true, conditionNumber);
        return;
    end

    [jacobian, conditionNumber] = local_jacobian( ...
        engine, cfg, settings, targetNp, power, z, residual);
    if ~all(isfinite(jacobian(:))) || rcond(jacobian) < 1e-14
        trim = local_pack_trim(z, evaluation, residual, ...
            iteration - 1, false, conditionNumber);
        return;
    end

    % 雅可比列对应归一化参数扰动，先求归一化步长，再恢复物理量步长。
    normalizedStep = -(jacobian \ residual);
    physicalStep = normalizedStep(:) .* settings.scale(:);
    [candidate, candidateEvaluation, candidateResidual, accepted] = ...
        local_line_search(engine, cfg, settings, targetNp, power, ...
        z, physicalStep, bestNorm);
    if ~accepted
        trim = local_pack_trim(z, evaluation, residual, ...
            iteration - 1, false, conditionNumber);
        return;
    end

    z = candidate;
    evaluation = candidateEvaluation;
    residual = candidateResidual;
    bestNorm = norm(residual, inf);
end

converged = local_is_converged(evaluation, residual, settings, targetNp);
if converged
    evaluation = local_run_onepoint(engine, cfg, settings, ...
        z(end), power, z(1:end-1));
end
trim = local_pack_trim(z, evaluation, residual, ...
    settings.maxNewtonIteration, converged, conditionNumber);
end

function trim = local_trim_stage_nested( ...
        engine, cfg, settings, targetNp, power, z0)
% 联合Newton在低负载病态区失败时，改用两层求解：DLL RunOnePoint负责
% 收敛全部共同工作变量，外层仅调整Wf使Np命中。这样保留完整气路方程，
% 同时把病态的多变量问题降为物理上单调的一维燃油配平问题。
wf = min(max(z0(end), settings.wfMin), settings.wfMax);
seed = z0(1:end-1);
evaluation = local_run_onepoint(engine, cfg, settings, wf, power, seed);
bestError = abs(evaluation.output.Np - targetNp);
bestWf = wf;
bestEvaluation = evaluation;

for iteration = 1:settings.maxNewtonIteration
    if local_nested_is_converged(evaluation, targetNp, settings)
        residual = local_nested_residual(evaluation, targetNp);
        trim = local_pack_trim([evaluation.varIte(:); wf], evaluation, ...
            residual, iteration - 1, true, NaN);
        return;
    end

    deltaWf = max(1e-6, 1e-3 * max(abs(wf), 0.02));
    wfMinus = max(settings.wfMin, wf - deltaWf);
    wfPlus = min(settings.wfMax, wf + deltaWf);
    if wfPlus <= wfMinus
        break;
    end
    minusEval = local_run_onepoint( ...
        engine, cfg, settings, wfMinus, power, evaluation.varIte);
    plusEval = local_run_onepoint( ...
        engine, cfg, settings, wfPlus, power, evaluation.varIte);
    slope = (plusEval.output.Np - minusEval.output.Np) / ...
        (wfPlus - wfMinus);
    if ~isfinite(slope) || abs(slope) < 1e-9
        break;
    end

    fullStep = -(evaluation.output.Np - targetNp) / slope;
    accepted = false;
    for alpha = [1, 0.5, 0.25, 0.125, 0.0625]
        trialWf = min(max(wf + alpha * fullStep, ...
            settings.wfMin), settings.wfMax);
        if trialWf == wf
            continue;
        end
        trialEvaluation = local_run_onepoint( ...
            engine, cfg, settings, trialWf, power, evaluation.varIte);
        trialError = abs(trialEvaluation.output.Np - targetNp);
        if local_nested_evaluation_is_valid(trialEvaluation) && ...
                isfinite(trialError) && trialError < bestError
            wf = trialWf;
            evaluation = trialEvaluation;
            bestError = trialError;
            bestWf = trialWf;
            bestEvaluation = trialEvaluation;
            accepted = true;
            break;
        end
    end
    if ~accepted
        break;
    end
end

residual = local_nested_residual(bestEvaluation, targetNp);
trim = local_pack_trim([bestEvaluation.varIte(:); bestWf], ...
    bestEvaluation, residual, settings.maxNewtonIteration, ...
    local_nested_is_converged(bestEvaluation, targetNp, settings), NaN);
end

function tf = local_nested_evaluation_is_valid(evaluation)
tf = evaluation.ret == 0 && evaluation.convergeTag == 0 && ...
    isfinite(evaluation.maxErr) && evaluation.maxErr <= 1e-5 && ...
    isfinite(evaluation.output.Np) && all(isfinite(evaluation.varIte));
end

function tf = local_nested_is_converged(evaluation, targetNp, settings)
tf = local_nested_evaluation_is_valid(evaluation) && ...
    abs(evaluation.output.Np - targetNp) <= settings.npToleranceRpm;
end

function residual = local_nested_residual(evaluation, targetNp)
variableCount = numel(evaluation.varIte);
residual = zeros(variableCount + 1, 1);
residual(1) = evaluation.maxErr;
residual(end) = (evaluation.output.Np - targetNp) / targetNp;
end

function [jacobian, conditionNumber] = local_jacobian( ...
    engine, cfg, settings, targetNp, power, z, residual0)
% 中心差分点不做参数限幅，避免人为制造重复列；只有 Wf 遵守物理边界。
n = numel(z);
jacobian = zeros(n, n);
for j = 1:n
    delta = settings.normalizedPerturbation * settings.scale(j);
    plus = z;
    minus = z;
    plus(j) = plus(j) + delta;
    minus(j) = minus(j) - delta;
    plus(end) = min(max(plus(end), settings.wfMin), settings.wfMax);
    minus(end) = min(max(minus(end), settings.wfMin), settings.wfMax);

    if plus(j) ~= z(j) && minus(j) ~= z(j)
        plusResidual = local_residual(local_eval_steady( ...
            engine, cfg, settings, power, plus), targetNp);
        minusResidual = local_residual(local_eval_steady( ...
            engine, cfg, settings, power, minus), targetNp);
        jacobian(:, j) = (plusResidual - minusResidual) / ...
            (2 * settings.normalizedPerturbation);
    elseif plus(j) ~= z(j)
        plusResidual = local_residual(local_eval_steady( ...
            engine, cfg, settings, power, plus), targetNp);
        jacobian(:, j) = (plusResidual - residual0) / ...
            settings.normalizedPerturbation;
    elseif minus(j) ~= z(j)
        minusResidual = local_residual(local_eval_steady( ...
            engine, cfg, settings, power, minus), targetNp);
        jacobian(:, j) = (residual0 - minusResidual) / ...
            settings.normalizedPerturbation;
    else
        jacobian(:, j) = NaN;
    end
end

singularValues = svd(jacobian);
if isempty(singularValues) || singularValues(end) == 0
    conditionNumber = Inf;
else
    conditionNumber = singularValues(1) / singularValues(end);
end
end

function [candidate, evaluation, residual, accepted] = local_line_search( ...
    engine, cfg, settings, targetNp, power, z, step, currentNorm)
% 固定候选步长序列保证每个阶段的行为可重复，并只接受残差严格下降的步。
candidate = z;
evaluation = local_eval_steady(engine, cfg, settings, power, z);
residual = local_residual(evaluation, targetNp);
accepted = false;

for alpha = [1, 0.5, 0.25, 0.125, 0.0625, 0.03125]
    trial = z + alpha * step;
    trial(end) = min(max(trial(end), settings.wfMin), settings.wfMax);
    trialEvaluation = local_eval_steady( ...
        engine, cfg, settings, power, trial);
    trialResidual = local_residual(trialEvaluation, targetNp);
    trialNorm = norm(trialResidual, inf);
    if isfinite(trialNorm) && trialNorm < currentNorm
        candidate = trial;
        evaluation = trialEvaluation;
        residual = trialResidual;
        accepted = true;
        return;
    end
end
end

function evaluation = local_eval_steady(engine, cfg, settings, power, z)
stepInValue = local_step_in(cfg, settings, z(end), power);
stepInValue(21:(20 + settings.variableCount)) = z(1:end-1);
evaluation = local_call_engine(engine, 'DLL_SHT_RunSteadyComponents', ...
    stepInValue, z(end), power);
end

function evaluation = local_run_onepoint(engine, cfg, settings, wf, power, seed)
if ~isempty(seed)
    local_set_seed(engine, seed);
end
stepInValue = local_step_in(cfg, settings, wf, power);
evaluation = local_call_engine( ...
    engine, 'DLL_SHT_RunOnePoint', stepInValue, wf, power);
end

function evaluation = local_call_engine(engine, functionName, stepInValue, wf, power)
engPtrInit.eng = libstruct(engine.engineStructName);
engPtr = libstruct(engine.enginePointerName, engPtrInit);
stepIn = libpointer('doublePtr', stepInValue);
stepOut = libpointer('doublePtr', zeros(128, 1));
[ret, ~, stepOutValue, engOut] = calllib( ...
    engine.libraryName, functionName, stepIn, stepOut, engPtr);

eng = engOut.eng;
np = double(eng.LPS_Nmech);
ng = double(eng.HPS_Nmech);
ptLoadPower = double(stepInValue(6));
gtAccessoryPower = double(stepInValue(7));
evaluation = struct();
evaluation.ret = ret;
evaluation.stepOut = stepOutValue(:);
evaluation.varIte = double(eng.varIte(1:eng.varVecDime)).';
evaluation.convergeTag = eng.convergeTag;
evaluation.maxErr = max(abs([double(eng.errOut(:)); double(eng.Nozzle.y(end))]));
evaluation.scheduleCoordinates = local_schedule_coordinates(eng, engine.modelMode);
evaluation.output = struct( ...
    'Np', np, ...
    'Ng', ng, ...
    'Wf', wf, ...
    'power', power, ...
    'T45', local_gt_out_value(eng, engine.modelMode, 3), ...
    'Pt45', local_gt_out_value(eng, engine.modelMode, 4), ...
    'Mkp', ptLoadPower / max(pi*np/30, eps), ...
    'Mkg', gtAccessoryPower / max(pi*ng/30, eps), ...
    'PTLoadPower', ptLoadPower, ...
    'GTAccessoryPower', gtAccessoryPower, ...
    'PTDriveTorque', double(eng.LPS_Trq), ...
    'GTInternalNetTorque', double(eng.HPS_Trq), ...
    'LPSNdot', double(eng.LPS.nDot), ...
    'HPSNdot', double(eng.HPS.nDot));
end

function stepInValue = local_step_in(cfg, settings, wf, power)
stepInValue = zeros(512, 1);
stepInValue(1:10) = [ ...
    cfg.engine.initial.Np0; cfg.engine.initial.Ng0; wf; settings.A8; ...
    0; power; settings.hpsPower; 0; settings.hpcAlpha; 0];

% 四种进口边界模式统一经显式字典写入。Pt2始终是Inlet输出，不能
% 作为Pt1输入；这也保证本公共配平器与数据生成/辨识主程序口径一致。
[stepInValue, ~] = sht_apply_inlet_boundary_stepin( ...
    stepInValue, cfg.engine.boundary);
scheduleEnabled = false;
if isfield(cfg.engine.boundary, 'healthScheduleEnabled') && ...
        ~isempty(cfg.engine.boundary.healthScheduleEnabled)
    scheduleEnabled = logical(cfg.engine.boundary.healthScheduleEnabled);
end
stepInValue(cfg.engine.interface.healthScheduleEnableIndex) = ...
    double(scheduleEnabled);
healthEnd = 40 + numel(settings.health);
stepInValue(41:healthEnd) = settings.health;
end

function local_set_seed(engine, seed)
stepInValue = zeros(512, 1);
stepInValue(21:(20 + numel(seed))) = seed(:);
engPtrInit.eng = libstruct(engine.engineStructName);
engPtr = libstruct(engine.enginePointerName, engPtrInit);
stepIn = libpointer('doublePtr', stepInValue);
stepOut = libpointer('doublePtr', zeros(128, 1));
calllib(engine.libraryName, 'DLL_SHT_varIteInit', stepIn, stepOut, engPtr);
end

function residual = local_residual(evaluation, targetNp)
variableCount = numel(evaluation.varIte);
residual = zeros(variableCount + 1, 1);
residual(1:variableCount) = evaluation.stepOut(1:variableCount);
residual(end) = (evaluation.output.Np - targetNp) / targetNp;
end

function converged = local_is_converged(evaluation, residual, settings, targetNp)
% RunSteadyComponents 不更新 convergeTag；因此阶段收敛由方程残差和 Np
% 误差判定。最终 RunOnePoint 的 convergeTag/maxErr 在入口测试中另行检查。
converged = evaluation.ret == 0 && ...
    max(abs(residual(1:end-1))) <= settings.residualTolerance && ...
    abs(evaluation.output.Np - targetNp) <= settings.npToleranceRpm;
end

function trim = local_pack_trim(z, evaluation, residual, iteration, converged, conditionNumber)
trim = struct();
trim.converged = converged;
trim.iteration = iteration;
trim.z = z(:);
trim.varIte = z(1:end-1);
trim.Wf = z(end);
trim.Np = evaluation.output.Np;
trim.Ng = evaluation.output.Ng;
trim.T45 = evaluation.output.T45;
trim.Pt45 = evaluation.output.Pt45;
trim.Mkp = evaluation.output.Mkp;
trim.Mkg = evaluation.output.Mkg;
trim.LPSNdot = evaluation.output.LPSNdot;
trim.HPSNdot = evaluation.output.HPSNdot;
trim.ret = evaluation.ret;
trim.convergeTag = evaluation.convergeTag;
trim.maxErr = evaluation.maxErr;
trim.residual = residual(:);
trim.residualInfinityNorm = norm(residual, inf);
trim.jacobianConditionNumber = conditionNumber;
trim.scheduleCoordinates = evaluation.scheduleCoordinates;
end

function value = local_gt_out_value(eng, modelMode, outputIndex)
if modelMode == 1
    value = double(eng.HPT2.y(outputIndex));
else
    value = double(eng.HPT.y(outputIndex));
end
end

function coordinates = local_schedule_coordinates(eng, modelMode)
% 调度横坐标直接取本次完整稳态回放的局部物理状态。三部件HPC的图上
% 换算转速与C端SHT_GetCompressorMapCorrectedSpeed结果一致，为y(16)。
coordinates = struct();
coordinates.inlet_corrected_mass_flow = ...
    local_corrected_mass_flow(local_read_gas_path(eng.Inlet.gasPathIn));
coordinates.burner_inlet_corrected_mass_flow = ...
    local_corrected_mass_flow(local_read_gas_path(eng.Burner.gasPathIn));
coordinates.gt_pt_duct_corrected_mass_flow = ...
    local_corrected_mass_flow(local_read_gas_path(eng.Duct2.gasPathIn));
coordinates.pt_nozzle_duct_corrected_mass_flow = ...
    local_corrected_mass_flow(local_read_gas_path(eng.Duct3.gasPathIn));
if modelMode == 0
    coordinates.hpc_corrected_speed = double(eng.HPC.y(16));
    coordinates.gt_total_pressure_ratio = double(eng.HPT_PRin);
    coordinates.pt_total_pressure_ratio = double(eng.LPT_PRin);
else
    coordinates.ac_corrected_speed = double(eng.HPC.y(16));
    coordinates.cc_corrected_speed = double(eng.HPC2.y(16));
    coordinates.gt_total_pressure_ratio = ...
        double(eng.HPT_PRin) * double(eng.HPT2_PRin);
    coordinates.pt_total_pressure_ratio = ...
        double(eng.LPT_PRin) * double(eng.LPT2_PRin);
end
end

function gasPath = local_read_gas_path(pointer)
% C结构中的gasPathIn是无定长double指针，读取前必须显式声明4元素。
pointerView = pointer;
setdatatype(pointerView,'doublePtr',1,4);
gasPath = double(pointerView.Value(:));
end

function correctedFlow = local_corrected_mass_flow(gasPath)
assert(numel(gasPath) >= 4 && all(isfinite(gasPath(1:4))) && ...
    gasPath(1) >= 0 && gasPath(3) > 0 && gasPath(4) > 0, ...
    '稳态回放产生了无效气路状态，无法形成调度横坐标。');
correctedFlow = gasPath(1) * sqrt(gasPath(3) / 288.15) * ...
    101325 / gasPath(4);
end
