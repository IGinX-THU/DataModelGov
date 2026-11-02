function result = sht_startstop_evaluate_low_speed_matrix( ...
    alias, engPtr, cfg, mapDirectory, design, options)
%SHT_STARTSTOP_EVALUATE_LOW_SPEED_MATRIX 评价三/六部件低速共同工作矩阵。
%
% 本函数固定 Ng、Np 和能量状态，只求解四/七维气路共同工作变量。它不是
% 连续起动仿真，也不以人工指定的轴转速替代阶段六轴系积分。每个活动点
% 依次尝试延续初值、邻近成功点、设计点缩放初值和低速工程初值，并把
% 求解失败、物理失败和轻微特性图越界分别记录。

if nargin < 6
    options = struct();
end
options = local_options(cfg, options);
assert(libisloaded(alias), 'DLL别名尚未加载：%s。', alias);
assert(isfolder(mapDirectory), '特性图目录不存在：%s。', mapDirectory);
assert(isfield(design, 'commonVariables') && ...
    numel(design.commonVariables) >= cfg.topology.gasCount, '缺少当前拓扑设计点初值。');

maps = local_read_maps(cfg, mapDirectory);
designSeed = design.commonVariables(1:cfg.topology.gasCount);
cases = local_build_cases(cfg, options);
pointTemplate = local_point_template(cfg);
points = repmat(pointTemplate, numel(cases), 1);

globalSeeds = zeros(0, cfg.topology.gasCount);
globalRatios = zeros(0, 1);
pointIndex = 0;
for branchIndex = 1:numel(options.branchNames)
    for stateIndex = 1:numel(options.stateNames)
        previousSeed = [];
        for ratioIndex = numel(options.ngRatio):-1:1
            ngRatio = options.ngRatio(ratioIndex);
            caseIndex = local_find_case(cases, branchIndex, stateIndex, ngRatio);
            if isempty(caseIndex)
                continue;
            end
            pointIndex = pointIndex + 1;
            current = cases(caseIndex);
            if ~current.applicable
                points(pointIndex) = local_not_applicable_point(current,cfg);
                continue;
            end

            seeds = local_candidate_seeds(previousSeed, globalSeeds, ...
                globalRatios, current, designSeed, cfg);
            point = local_evaluate_case(alias, engPtr, cfg, maps, ...
                current, seeds);
            local_assert_point_schema(pointTemplate, point);
            points(pointIndex) = point;
            if point.solverConverged && all(isfinite(point.variable))
                previousSeed = point.variable(:);
                globalSeeds(end + 1, :) = point.variable(:).'; %#ok<AGROW>
                globalRatios(end + 1, 1) = current.ngRatio; %#ok<AGROW>
            end
        end
    end
end
points = points(1:pointIndex);

tableOut = local_points_to_table(points,cfg);
summary = local_summarize(points, cfg);
result = struct('generatedAt', datestr(now, 31), ...
    'label', options.label, 'options', options, 'points', points, ...
    'table', tableOut, 'summary', summary, 'accepted', summary.accepted);
% 只补充诊断口径，不改变任何接受条件。历史结果没有此字段，不能将
% 历史AttemptCount（最佳初猜序号）解释成实际尝试总数。
result.attemptCountMeaning = 'executed_seed_attempts_v1';
result.acceptanceCriteria = struct( ...
    'solverAccuracyRequired', cfg.lowSpeedSolver.accuracyRequired, ...
    'matrixResidualRmsTolerance', cfg.stage5.matrixResidualRmsTolerance, ...
    'matrixMaximumResidualTolerance', cfg.stage5.matrixMaximumResidualTolerance, ...
    'requiredRank', cfg.stage5.requiredRank);
for i = reshape(find([points.applicable] & ~[points.accepted]),1,[])
    p = points(i);
    fprintf(2,'低速矩阵未通过：%s，Ng=%.6g rpm，Np=%.6g rpm；%s\n', ...
        p.caseId,p.ngRpm,p.npRpm,p.statusText);
end

if options.writeEvidence
    assert(~isempty(options.outputDir), ...
        'writeEvidence=true时必须给定outputDir。');
    local_write_evidence(result, options.outputDir);
end
end

function options = local_options(cfg, options)
defaults = struct('ngRatio', cfg.stage5.ngRatio, ...
    'branchNames', {cfg.stage5.npBranchNames}, ...
    'branchFactors', cfg.stage5.npBranchFactors, ...
    'stateNames', {cfg.stage5.energyStateNames}, ...
    'label', 'matrix', 'outputDir', '', 'writeEvidence', false);
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(options, names{i}) || isempty(options.(names{i}))
        options.(names{i}) = defaults.(names{i});
    end
end
assert(numel(options.branchNames) == numel(options.branchFactors), ...
    'Np分支名称和倍率数量不一致。');
options.ngRatio = unique(options.ngRatio(:).', 'stable');
end

function maps = local_read_maps(cfg, mapDirectory)
names = cfg.topology.componentNames;
maps = struct();
for i = 1:numel(names)
    name = names{i};
    definition = cfg.maps.(name);
    path = fullfile(mapDirectory, definition.outputName);
    assert(isfile(path), '缺少阶段五运行特性图：%s。', path);
    action = ['read', upper(definition.kind(1)), definition.kind(2:end)];
    maps.(name) = sht_tmats_map_io(action, path);
end
end

function cases = local_build_cases(cfg, options)
template = struct('caseId', '', 'branchIndex', 0, 'branchName', '', ...
    'stateIndex', 0, 'stateName', '', 'ngRatio', 0, 'npRatio', 0, ...
    'ngRpm', 0, 'npRpm', 0, 'rotorRpm', 0, 'commandedFuel', 0, ...
    'ignitionEnabled', 0, 'applicable', true);
cases = repmat(template, numel(options.branchNames) * ...
    numel(options.stateNames) * numel(options.ngRatio), 1);
k = 0;
for i = 1:numel(options.branchNames)
    for j = 1:numel(options.stateNames)
        for r = options.ngRatio
            k = k + 1;
            npRatio = options.branchFactors(i) * r;
            state = options.stateNames{j};
            fuel = local_fuel_schedule(r, cfg);
            ignition = 0;
            applicable = true;
            if strcmp(state, 'no_fuel')
                fuel = 0;
            elseif strcmp(state, 'pre_ignition')
                ignition = 0;
            elseif strcmp(state, 'fired_low_fuel')
                ignition = 1;
                applicable = r + 16 * eps >= ...
                    cfg.stage5.firedMinimumNgRatio;
            else
                error('未知能量状态：%s。', state);
            end
            cases(k) = template;
            cases(k).caseId = sprintf('%s__%s__Ng%05.1f', ...
                options.branchNames{i}, state, 100 * r);
            cases(k).branchIndex = i;
            cases(k).branchName = options.branchNames{i};
            cases(k).stateIndex = j;
            cases(k).stateName = state;
            cases(k).ngRatio = r;
            cases(k).npRatio = npRatio;
            cases(k).ngRpm = r * cfg.startStop.designNgRpm;
            cases(k).npRpm = npRatio * cfg.startStop.designNpRpm;
            cases(k).rotorRpm = cases(k).npRpm;
            cases(k).commandedFuel = fuel;
            cases(k).ignitionEnabled = ignition;
            cases(k).applicable = applicable;
        end
    end
end
end

function index = local_find_case(cases, branchIndex, stateIndex, ngRatio)
mask = [cases.branchIndex] == branchIndex & ...
    [cases.stateIndex] == stateIndex & ...
    abs([cases.ngRatio] - ngRatio) <= 32 * eps(max(1, abs(ngRatio)));
index = find(mask, 1, 'first');
end

function fuel = local_fuel_schedule(ngRatio, cfg)
x = cfg.stage5.fuelScheduleNgRatio;
y = cfg.stage5.fuelScheduleKgPerS;
fuel = interp1(x, y, min(max(ngRatio, x(1)), x(end)), 'linear');
end

function seeds = local_candidate_seeds(previousSeed, globalSeeds, ...
    globalRatios, current, designSeed, cfg)
candidate = zeros(0, cfg.topology.gasCount);
if ~isempty(previousSeed)
    candidate(end + 1, :) = previousSeed(:).';
end
if ~isempty(globalSeeds)
    [~, nearest] = min(abs(globalRatios - current.ngRatio));
    candidate(end + 1, :) = globalSeeds(nearest, :);
end
candidate(end + 1, :) = designSeed(:).';

scale = max(current.ngRatio, 0.01);
scaled = designSeed(:).';
scaled(1) = max(0.005, scale * designSeed(1));
scaled(cfg.topology.compressorIndices) = min(max(scaled(cfg.topology.compressorIndices), 0.2), 1.2);
scaled(cfg.topology.turbineIndices) = 1 + scale * (designSeed(cfg.topology.turbineIndices).' - 1);
candidate(end + 1, :) = scaled;

heuristic = cfg.stage5.lowSpeedHeuristicSeed(:).';
heuristic(1) = max(0.005, heuristic(1) * ...
    max(1, current.ngRatio / 0.02));
candidate(end + 1, :) = heuristic;
for rline = [0.25, 0.55, 0.90, 1.20]
    trial = scaled;
    trial(cfg.topology.compressorIndices) = rline;
    candidate(end + 1, :) = trial; %#ok<AGROW>
end

% 冷转/点火前通常需要压气机位于高流量低压比侧、涡轮接近单位压比；
% 点火后则允许更高的涡轮压比和AC近喘振侧。这里使用少量确定性组合，
% 不引入随机种子，保证矩阵评价和候选校准完全可复现。
flowBase = max(0.005, scale * designSeed(1));
if strcmp(current.stateName, 'fired_low_fuel')
    directed = [ ...
        0.45, 1.35, 0.80, 1.25, 1.15, 1.55, 1.45; ...
        0.70, 1.45, 0.30, 1.50, 1.25, 1.80, 1.65; ...
        1.00, 1.10, 0.00, 1.20, 1.10, 1.40, 1.30; ...
        0.30, 1.50, 1.00, 1.70, 1.40, 2.00, 1.80];
else
    directed = [ ...
        0.30, 1.10, -0.35, 1.02, 1.02, 1.02, 1.02; ...
        0.50, 1.30, -0.25, 1.08, 1.05, 1.08, 1.05; ...
        0.70, 0.90, -0.10, 1.20, 1.10, 1.15, 1.08; ...
        1.00, 0.50,  0.00, 1.40, 1.20, 1.30, 1.15; ...
        0.20, 1.45, -0.40, 1.05, 1.02, 1.50, 1.35; ...
        1.20, 1.00,  0.40, 1.60, 1.40, 1.60, 1.40];
end
if cfg.modelMode == 0
    if strcmp(current.stateName,'fired_low_fuel')
        directed=[0.45,1.35,1.5,1.8; 0.7,1.45,2,2.5; ...
            1,1.1,1.3,1.5; 0.3,1.5,2.5,3];
    else
        directed=[0.3,1.1,1.02,1.02;0.5,1.3,1.1,1.1; ...
            0.7,0.9,1.2,1.1;1,0.5,1.4,1.3;0.2,1.45,1.05,1.2];
    end
end
for i = 1:size(directed, 1)
    trial = directed(i, :);
    trial(1) = flowBase * trial(1);
    candidate(end + 1, :) = trial; %#ok<AGROW>
end

lower = cfg.stage5.gasVariableMinimum;
upper = cfg.stage5.gasVariableMaximum;
candidate = min(max(candidate, lower), upper);
candidate = unique(round(candidate * 1e11) / 1e11, 'rows', 'stable');
seeds = candidate(1:min(size(candidate, 1), ...
    cfg.stage5.maximumRetryCount), :);
end

function point = local_evaluate_case(alias, engPtr, cfg, maps, current, seeds)
bestScore = [Inf, Inf, Inf, Inf];
best = [];
attemptCount = 0;
for i = 1:size(seeds, 1)
    local_prepare_state(alias, cfg, current);
    input = local_step_input(cfg, current, seeds(i, :).');
    inputPointer = libpointer('doublePtr', input);
    outputPointer = libpointer('doublePtr', zeros(128, 1));
    callStatus = -999;
    output = nan(128, 1);
    diagnostics = nan(97, 1);
    snapshot = local_empty_snapshot(cfg);
    attemptCount = attemptCount + 1;
    try
        [callStatus, ~, output, engOut] = calllib(alias, ...
            'DLL_SHT_RunStartStopStep', inputPointer, outputPointer, engPtr);
        diagnostics = local_read_diagnostics(alias);
        if callStatus == 0 && current.ngRatio > 0
            snapshot = local_capture_engine(engOut.eng, maps,cfg);
        elseif callStatus == 0
            snapshot.physicalValid = all(isfinite(output(1:24)));
        end
    catch errorObject
        snapshot.errorMessage = errorObject.message;
    end
    converged = callStatus == 0 && ...
        ((diagnostics(1) == 0 && diagnostics(2) == 1) || ...
        diagnostics(1) == 6);
    score = local_attempt_score(callStatus, diagnostics, converged);
    attempt = struct('callStatus', callStatus, 'output', output, ...
        'diagnostics', diagnostics, 'snapshot', snapshot, ...
        'seed', seeds(i, :).', 'seedIndex', i, 'converged', converged);
    if local_lexicographic_less(score, bestScore)
        bestScore = score;
        best = attempt;
    end
    if converged && diagnostics(13) <= ...
            cfg.stage5.matrixResidualRmsTolerance && ...
            diagnostics(14) <= cfg.stage5.matrixMaximumResidualTolerance
        break;
    end
end
point = local_pack_point(current, best, cfg);
point.attemptCount = attemptCount;
end

function score = local_attempt_score(callStatus, diagnostics, converged)
% 多初值排序必须先区分“未收敛”和“模型根本不可评价”。模型错误时
% 低速求解器尚未形成残差，诊断数组中的零不是优良残差，不能据此胜出。
solverStatus = diagnostics(1);
if converged
    quality = 0;
    residualMetric = diagnostics(13);
elseif callStatus == 0 && any(solverStatus == [1, 2, 4])
    quality = 1;
    residualMetric = diagnostics(15); % 未收敛时采用搜索期间达到的最好RMSE。
elseif callStatus == 0 && solverStatus == 3
    quality = 2;
    residualMetric = Inf;
else
    quality = 3;
    residualMetric = Inf;
end
score = [quality, local_finite_or_inf(residualMetric), ...
    local_finite_or_inf(diagnostics(14)), ...
    local_finite_or_inf(diagnostics(17))];
end

function local_prepare_state(alias, cfg, current)
status = calllib(alias, 'DLL_SHT_StartStopReset', current.ngRpm, ...
    current.npRpm, current.rotorRpm, 1);
assert(status == 0, '工况%s状态复位失败，状态码=%d。', ...
    current.caseId, status);
if ~strcmp(current.stateName, 'fired_low_fuel')
    return;
end
count = ceil(cfg.stage5.firedPreconditionTimeS / ...
    cfg.startStop.timeStepS);
for k = 1:count
    input = [cfg.startStop.timeStepS; 1; current.ngRpm; ...
        current.npRpm; current.rotorRpm; 0; 0; current.commandedFuel; ...
        cfg.startStop.collectivePitchDeg; 1; 900; ...
        cfg.startStop.gtAccessoryPowerW];
    inputPointer = libpointer('doublePtr', input);
    outputPointer = libpointer('doublePtr', zeros(24, 1));
    status = calllib(alias, 'DLL_SHT_StartStopPhysicsStep', ...
        inputPointer, numel(input), outputPointer, 24);
    assert(status == 0, '工况%s燃烧状态预置失败，状态码=%d。', ...
        current.caseId, status);
end
end

function input = local_step_input(cfg, current, seed)
input = zeros(512, 1);
input(1) = current.npRpm;
input(2) = current.ngRpm;
input(3) = current.commandedFuel;
input(4) = cfg.startStop.nozzleAreaM2;
input(5) = 0;
input(7) = cfg.startStop.gtAccessoryPowerW;
input(17) = 0;
input(18) = 0;
input(20+(1:cfg.topology.gasCount)) = seed;
input(30) = cfg.startStop.timeStepS;
input(31) = 1;
input(32) = current.rotorRpm;
input(33) = cfg.startStop.collectivePitchDeg;
input(34) = current.ignitionEnabled;
input(35) = 900;
input(36) = 1;
input(341) = 0;
end

function diagnostics = local_read_diagnostics(alias)
pointer = libpointer('doublePtr', zeros(97, 1));
status = calllib(alias, 'DLL_SHT_LowSpeedSolverGetDiagnostics', pointer, 97);
assert(status == 0, '读取低速求解诊断失败，状态码=%d。', status);
diagnostics = pointer.Value;
end

function snapshot = local_capture_engine(eng,maps,cfg)
snapshot = sht_startstop_engine_snapshot(eng,maps,cfg);
end

function snapshot = local_empty_snapshot(cfg)
snapshot = sht_startstop_engine_snapshot([],struct(),cfg);
end

function point = local_pack_point(current, best, cfg)
point = local_point_template(cfg);
point = local_copy_case(point, current);
point.seedSourceIndex = best.seedIndex;
point.seed = best.seed;
point.callStatus = best.callStatus;
point.output = best.output;
point.diagnostics = best.diagnostics;
point.solverStatus = best.diagnostics(1);
point.solverConverged = best.converged;
point.residualRms = best.diagnostics(13);
point.maximumResidual = best.diagnostics(14);
point.conditionNumber = best.diagnostics(17);
point.rank = best.diagnostics(9);
point.boundaryCount = best.diagnostics(11);
point.variable = best.diagnostics(17+(1:cfg.topology.gasCount));
point.residual = best.diagnostics(33+(1:cfg.topology.gasCount));
point.weakestDirection = best.diagnostics(65+(1:cfg.topology.gasCount));
point.boundaryFlags = best.diagnostics(81+(1:cfg.topology.gasCount));
point.snapshot = best.snapshot;
point.physicalValid = best.snapshot.physicalValid;
point.mapExtrapolated = best.snapshot.mapExtrapolated;
point.minimumMapMargin = best.snapshot.minimumMapMargin;
point.effectiveFuel = best.output(6);
point.npDot = best.output(1);
point.ngDot = best.output(2);
point.accepted = best.callStatus == 0 && best.converged && ...
    best.diagnostics(13) <= cfg.stage5.matrixResidualRmsTolerance && ...
    best.diagnostics(14) <= cfg.stage5.matrixMaximumResidualTolerance && ...
    (best.diagnostics(1) == 6 || ...
    best.diagnostics(9) >= cfg.stage5.requiredRank) && ...
    best.snapshot.physicalValid;
point.statusText = local_failure_reason(point,cfg);
end

function text = local_failure_reason(p,cfg)
% 逐项解释已有接受条件；NaN与有限超限同样不能通过原有<=或>=判断。
reasons = {};
if p.callStatus ~= 0
    reasons{end+1} = sprintf('调用状态=%g',p.callStatus);
end
if ~p.solverConverged
    reasons{end+1} = sprintf( ...
        '求解未收敛：solverStatus=%g（%s），底层RMS精度=%.6e，实际RMS=%.6e', ...
        p.solverStatus,local_solver_status_text(p.solverStatus), ...
        cfg.lowSpeedSolver.accuracyRequired,p.residualRms);
end
if ~(p.residualRms <= cfg.stage5.matrixResidualRmsTolerance)
    reasons{end+1} = sprintf('矩阵RMS=%.6e，限值=%.6e', ...
        p.residualRms,cfg.stage5.matrixResidualRmsTolerance);
end
if ~(p.maximumResidual <= cfg.stage5.matrixMaximumResidualTolerance)
    reasons{end+1} = sprintf('最大残差=%.6e，限值=%.6e', ...
        p.maximumResidual,cfg.stage5.matrixMaximumResidualTolerance);
end
if ~(p.solverStatus == 6 || p.rank >= cfg.stage5.requiredRank)
    reasons{end+1} = sprintf('有效秩=%g，要求=%g',p.rank,cfg.stage5.requiredRank);
end
if ~p.physicalValid
    reasons{end+1} = sprintf( ...
        '物理检查未通过：modelErrorCode=%g，configurationValid=%g，evaluationValid=%g', ...
        p.snapshot.modelErrorCode,p.snapshot.configurationValid,p.snapshot.evaluationValid);
end
if ~isempty(p.snapshot.errorMessage)
    reasons{end+1} = ['已有异常：',p.snapshot.errorMessage];
end
text = strjoin(reasons,'；');
end

function text = local_solver_status_text(code)
% 与配套shtLowSpeedSolver.h的现有枚举一致，仅翻译诊断码。
labels = {'已收敛','达到最大迭代次数','迭代停滞','模型评价错误', ...
    'Jacobian奇异','输入无效','零转速保持'};
if isfinite(code) && code == fix(code) && code >= 0 && code < numel(labels)
    text = labels{code + 1};
else
    text = '未知状态码';
end
end

function point = local_not_applicable_point(current,cfg)
point = local_point_template(cfg);
point = local_copy_case(point, current);
point.applicable = false;
point.statusText = 'N/A：低于最低点火转速';
end

function point = local_copy_case(point, current)
fields = {'caseId', 'branchName', 'stateName', 'ngRatio', 'npRatio', ...
    'ngRpm', 'npRpm', 'rotorRpm', 'commandedFuel', ...
    'ignitionEnabled', 'applicable'};
for i = 1:numel(fields)
    point.(fields{i}) = current.(fields{i});
end
end

function point = local_point_template(cfg)
point = struct('caseId', '', 'branchName', '', 'stateName', '', ...
    'ngRatio', NaN, 'npRatio', NaN, 'ngRpm', NaN, 'npRpm', NaN, ...
    'rotorRpm', NaN, 'commandedFuel', NaN, 'effectiveFuel', NaN, ...
    'ignitionEnabled', 0, 'applicable', false, 'attemptCount', 0, ...
    'seedSourceIndex', 0, 'seed', nan(cfg.topology.gasCount, 1), 'callStatus', NaN, ...
    'solverStatus', NaN, 'solverConverged', false, ...
    'residualRms', NaN, 'maximumResidual', NaN, ...
    'conditionNumber', NaN, 'rank', NaN, 'boundaryCount', NaN, ...
    'variable', nan(cfg.topology.gasCount, 1), 'residual', nan(cfg.topology.gasCount, 1), ...
    'weakestDirection', nan(cfg.topology.gasCount, 1), 'boundaryFlags', nan(cfg.topology.gasCount, 1), ...
    'output', nan(128, 1), 'diagnostics', nan(97, 1), ...
    'snapshot', local_empty_snapshot(cfg), ...
    'physicalValid', false, 'mapExtrapolated', false, ...
    'minimumMapMargin', NaN, 'npDot', NaN, 'ngDot', NaN, ...
    'accepted', false, 'statusText', '');
end

function local_assert_point_schema(template, point)
templateFields = fieldnames(template);
pointFields = fieldnames(point);
if ~isequal(sort(templateFields), sort(pointFields))
    missing = setdiff(templateFields, pointFields);
    extra = setdiff(pointFields, templateFields);
    error('sht:startStop:pointSchema', ...
        '矩阵点结构不一致。缺少字段：%s；多余字段：%s。', ...
        strjoin(missing, ', '), strjoin(extra, ', '));
end
end

function tableOut = local_points_to_table(points,cfg)
n = numel(points);
row = repmat(struct(), n, 1);
for i = 1:n
    p = points(i);
    row(i).CaseId = p.caseId;
    row(i).NpBranch = p.branchName;
    row(i).EnergyState = p.stateName;
    row(i).Applicable = p.applicable;
    row(i).NgRatio = p.ngRatio;
    row(i).NpRatio = p.npRatio;
    row(i).NgRpm = p.ngRpm;
    row(i).NpRpm = p.npRpm;
    row(i).CommandedFuel = p.commandedFuel;
    row(i).EffectiveFuel = p.effectiveFuel;
    row(i).AttemptCount = p.attemptCount;
    row(i).BestSeedIndex = p.seedSourceIndex;
    row(i).CallStatus = p.callStatus;
    row(i).SolverStatus = p.solverStatus;
    row(i).SolverConverged = p.solverConverged;
    row(i).ResidualRms = p.residualRms;
    row(i).MaximumResidual = p.maximumResidual;
    row(i).ScaledJacobianCondition = p.conditionNumber;
    row(i).EffectiveRank = p.rank;
    row(i).BoundaryCount = p.boundaryCount;
    row(i).PhysicalValid = p.physicalValid;
    row(i).ModelErrorCode = p.snapshot.modelErrorCode;
    row(i).ConfigurationValid = p.snapshot.configurationValid;
    row(i).EvaluationValid = p.snapshot.evaluationValid;
    row(i).OffendingStepInIndex = p.snapshot.offendingStepInIndex;
    row(i).OffendingValue = p.snapshot.offendingValue;
    row(i).MapExtrapolated = p.mapExtrapolated;
    row(i).MinimumMapMargin = p.minimumMapMargin;
    row(i).Accepted = p.accepted;
    row(i).FailureReason = p.statusText;
    row(i).NpDot = p.npDot;
    row(i).NgDot = p.ngDot;
    row(i).HpsGasTorqueNm = p.snapshot.hpsGasTorqueNm;
    row(i).PtGasTorqueNm = p.snapshot.ptGasTorqueNm;
    for j = 1:cfg.topology.gasCount
        row(i).(sprintf('x%d', j)) = p.variable(j);
        row(i).(sprintf('r%d', j)) = p.residual(j);
    end
    component = cfg.topology.componentNames;
    for j = 1:numel(component)
        row(i).([component{j}, '_NcMap']) = p.snapshot.mapCoordinate(j, 1);
        row(i).([component{j}, '_Path']) = p.snapshot.mapCoordinate(j, 2);
        row(i).([component{j}, '_Margin']) = min(p.snapshot.mapMargin(j, :));
        row(i).([component{j}, '_ActualWc']) = ...
            p.snapshot.actualCorrectedFlow(j);
        row(i).([component{j}, '_MapWc']) = p.snapshot.mapCorrectedFlow(j);
        row(i).([component{j}, '_RequiredMapWc']) = ...
            p.snapshot.requiredMapCorrectedFlow(j);
        row(i).([component{j}, '_RequiredFlowRatio']) = ...
            p.snapshot.requiredFlowRatio(j);
    end
    station = cfg.topology.stationNames;
    for j = 1:numel(station)
        row(i).([station{j}, '_W']) = p.snapshot.stationWTP(j, 1);
        row(i).([station{j}, '_Tt']) = p.snapshot.stationWTP(j, 2);
        row(i).([station{j}, '_Pt']) = p.snapshot.stationWTP(j, 3);
    end
end
tableOut = struct2table(row);
end

function summary = local_summarize(points, cfg)
applicable = [points.applicable];
active = applicable & [points.ngRatio] > 0;
accepted = [points.accepted];
physical = [points.physicalValid];
converged = [points.solverConverged];
rmsValue = [points.residualRms];
condition = [points.conditionNumber];
rankValue = [points.rank];
boundary = [points.boundaryCount];
finiteRms = rmsValue(applicable & isfinite(rmsValue));
finiteCondition = condition(active & isfinite(condition));
if isempty(finiteRms)
    maximumRms = Inf;
    logResidualSum = Inf;
else
    maximumRms = max(finiteRms);
    logResidualSum = sum(log10(max(finiteRms, 1e-14)));
end
if isempty(finiteCondition)
    maximumCondition = Inf;
else
    maximumCondition = max(finiteCondition);
end
summary = struct();
summary.totalCount = numel(points);
summary.applicableCount = nnz(applicable);
summary.activeCount = nnz(active);
summary.acceptedCount = nnz(accepted & applicable);
summary.failedCount = nnz(applicable & ~accepted);
summary.nonconvergedCount = nnz(applicable & ~converged);
summary.physicalFailureCount = nnz(applicable & ~physical);
modelCode = reshape(arrayfun(@(p) p.snapshot.modelErrorCode, points), 1, []);
summary.transientDiagnosticErrorCount = nnz(applicable & ...
    isfinite(modelCode) & modelCode ~= 0);
summary.transientDiagnosticErrorCodes = unique(modelCode(applicable & ...
    isfinite(modelCode) & modelCode ~= 0));
summary.mapExtrapolationCount = nnz(applicable & [points.mapExtrapolated]);
summary.rankDeficit = sum(max(0, cfg.stage5.requiredRank - ...
    rankValue(active & isfinite(rankValue))));
summary.boundaryHitTotal = sum(boundary(active & isfinite(boundary)));
summary.maximumResidualRms = maximumRms;
summary.logResidualSum = logResidualSum;
summary.maximumCondition = maximumCondition;
summary.objectiveVector = [summary.failedCount, ...
    summary.physicalFailureCount, log10(max(maximumRms, 1e-14)), ...
    logResidualSum, summary.rankDeficit, summary.boundaryHitTotal, ...
    log10(max(maximumCondition, 1))];
summary.accepted = summary.failedCount == 0;
end

function local_write_evidence(result, outputDir)
if ~isfolder(outputDir)
    mkdir(outputDir);
end
writetable(result.table, fullfile(outputDir, 'matching_matrix.csv'));
save(fullfile(outputDir, 'matching_matrix_result.mat'), 'result', '-v7');
local_write_summary(fullfile(outputDir, 'matching_matrix_summary.md'), result);
local_plot_matrix(result, outputDir);
end

function local_write_summary(path, result)
s = result.summary;
fid = fopen(path, 'w', 'n', 'UTF-8');
assert(fid >= 0, '无法写入低速矩阵摘要：%s。', path);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# %s 低速共同工作矩阵摘要\n\n', result.label);
fprintf(fid, '- 生成时间：%s\n', result.generatedAt);
fprintf(fid, '- 总体结果：**%s**\n', local_pass(s.accepted));
fprintf(fid, '- 适用点/通过点/失败点：%d / %d / %d\n', ...
    s.applicableCount, s.acceptedCount, s.failedCount);
fprintf(fid, '- 不收敛点：%d\n', s.nonconvergedCount);
fprintf(fid, '- 物理无效点：%d\n', s.physicalFailureCount);
fprintf(fid, '- 轻微或明显图外点：%d（只作风险记录）\n', ...
    s.mapExtrapolationCount);
fprintf(fid, '- 瞬态接口诊断错误点：%d；错误码：%s\n', ...
    s.transientDiagnosticErrorCount, ...
    mat2str(s.transientDiagnosticErrorCodes));
fprintf(fid, '- 最大残差RMSE：%.6e\n', s.maximumResidualRms);
fprintf(fid, '- 最大尺度化Jacobian条件数：%.6e\n', s.maximumCondition);
fprintf(fid, '- 累计秩亏/边界命中：%.0f / %.0f\n\n', ...
    s.rankDeficit, s.boundaryHitTotal);
fprintf(fid, '- AttemptCount为实际候选初猜尝试数，BestSeedIndex为最佳初猜序号；均非内部函数评估次数。\n');
fprintf(fid, '- 底层RMS精度：%.6e；矩阵RMS/最大残差限值：%.6e / %.6e。\n\n', ...
    result.acceptanceCriteria.solverAccuracyRequired, ...
    result.acceptanceCriteria.matrixResidualRmsTolerance, ...
    result.acceptanceCriteria.matrixMaximumResidualTolerance);
fprintf(fid, '|工况|Np分支|能量状态|Ng%%|Np%%|状态|求解器码|模型错误码|RMSE|最大残差|秩|条件数|最小图裕度|尝试数|最佳初猜|未通过原因|\n');
fprintf(fid, '|---|---|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|\n');
for i = 1:numel(result.points)
    p = result.points(i);
    if ~p.applicable
        status = 'N/A';
    else
        status = local_pass(p.accepted);
    end
    reason = strrep(strrep(strrep(p.statusText,'|','/'),newline,' '),char(13),' ');
    fprintf(fid, '|%s|%s|%s|%.1f|%.1f|%s|%.0f|%.0f|%.3e|%.3e|%.0f|%.3e|%.3e|%d|%d|%s|\n', ...
        p.caseId, p.branchName, p.stateName, 100 * p.ngRatio, ...
        100 * p.npRatio, status, p.solverStatus, ...
        p.snapshot.modelErrorCode, p.residualRms, p.maximumResidual, ...
        p.rank, p.conditionNumber, p.minimumMapMargin, ...
        p.attemptCount,p.seedSourceIndex,reason);
end
end

function local_plot_matrix(result, outputDir)
branch = result.options.branchNames;
state = result.options.stateNames;
figureHandle = figure('Visible', 'off', 'Color', 'w', ...
    'Position', [80, 80, 1380, 900]);
cleanup = onCleanup(@() close(figureHandle));
for i = 1:numel(branch)
    for j = 1:numel(state)
        subplot(numel(branch), numel(state), (i - 1) * numel(state) + j);
        mask = strcmp({result.points.branchName}, branch{i}) & ...
            strcmp({result.points.stateName}, state{j}) & ...
            [result.points.applicable];
        x = 100 * [result.points(mask).ngRatio];
        y = [result.points(mask).residualRms];
        [x, order] = sort(x);
        y = y(order);
        semilogy(x, max(y, 1e-14), 'o-', 'LineWidth', 1.1);
        grid on; xlabel('N_g / N_{g,des}, %'); ylabel('残差 RMSE');
        title([branch{i}, ' / ', state{j}], 'Interpreter', 'none');
    end
end
sgtitle([result.label, ' 低速共同工作残差矩阵'], 'Interpreter', 'none');
print(figureHandle, fullfile(outputDir, 'matching_matrix_residual.png'), ...
    '-dpng', '-r160');
end

function value = local_finite_or_inf(value)
if ~isfinite(value)
    value = Inf;
end
end

function tf = local_lexicographic_less(a, b)
tf = false;
for i = 1:numel(a)
    if isequaln(a(i), b(i))
        continue;
    end
    if isfinite(a(i)) && ~isfinite(b(i))
        tf = true;
        return;
    elseif ~isfinite(a(i))
        return;
    end
    scale = max([1, abs(a(i)), abs(b(i))]);
    if a(i) < b(i) - 1e-12 * scale
        tf = true;
        return;
    elseif a(i) > b(i) + 1e-12 * scale
        return;
    end
end
end

function value = local_pass(tf)
if tf
    value = 'PASS';
else
    value = 'FAIL';
end
end
