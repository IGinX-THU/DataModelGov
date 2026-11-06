function result = sht_startstop_calibrate_low_speed_maps( ...
    alias, cfg, runtime, design, outputDir, runtimeInitiallyInitialized)
%SHT_STARTSTOP_CALIBRATE_LOW_SPEED_MAPS 受约束校准低速扩展区参数。
%
% 校准采用“硬约束 -> 单参数灵敏度 -> 少量参数释放 -> 有界坐标搜索”。
% 正常图区、零速边界或连接连续性不通过的候选不会调用DLL。阶段五只
% 使用静态低速矩阵，不把起动机、轴摩擦或旋翼负载误吸收到特性图中。

if nargin < 6
    runtimeInitiallyInitialized = false;
end
if ~isfolder(outputDir)
    mkdir(outputDir);
end
assert(libisloaded(alias), 'DLL别名尚未加载：%s。', alias);

theta0 = sht_startstop_map_parameters(cfg);
cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
history = repmat(local_history_template(), 0, 1);
evaluationCount = 0;
runtimeInitialized = runtimeInitiallyInitialized;

baseline = evaluate(theta0, 'baseline');
best = baseline;

if baseline.matrix.summary.accepted
    released = zeros(0, 1);
    sensitivity = repmat(local_sensitivity_template(), 0, 1);
else
    sensitivity = repmat(local_sensitivity_template(), numel(theta0), 1);
    for i = 1:numel(theta0)
        span = cfg.stage5.calibrationUpperBound(i) - ...
            cfg.stage5.calibrationLowerBound(i);
        delta = cfg.stage5.sensitivityRelativeStep * span;
        minusTheta = theta0;
        plusTheta = theta0;
        minusTheta(i) = max(cfg.stage5.calibrationLowerBound(i), ...
            theta0(i) - delta);
        plusTheta(i) = min(cfg.stage5.calibrationUpperBound(i), ...
            theta0(i) + delta);
        minus = evaluate(minusTheta, sprintf('sensitivity_%02d_minus', i));
        plus = evaluate(plusTheta, sprintf('sensitivity_%02d_plus', i));
        localBest = minus;
        direction = -1;
        if local_is_better(plus.objectiveVector, minus.objectiveVector)
            localBest = plus;
            direction = 1;
        end
        sensitivity(i).parameterIndex = i;
        sensitivity(i).parameterName = ...
            cfg.stage5.calibrationParameterNames{i};
        sensitivity(i).minusMerit = minus.merit;
        sensitivity(i).plusMerit = plus.merit;
        sensitivity(i).bestDirection = direction;
        sensitivity(i).improvement = baseline.merit - localBest.merit;
        sensitivity(i).improvesLexicographically = local_is_better( ...
            localBest.objectiveVector, baseline.objectiveVector);
        sensitivity(i).bestTheta = localBest.theta;
        if local_is_better(localBest.objectiveVector, best.objectiveVector)
            best = localBest;
        end
    end

    improves = find([sensitivity.improvesLexicographically]);
    if isempty(improves)
        % 即使没有单参数跨越首要字典序层级，也选择标量罚函数改善最大的
        % 少量方向继续检查组合效应；若所有方向均恶化则不盲目调图。
        [~, order] = sort([sensitivity.improvement], 'descend');
        improves = order([sensitivity(order).improvement] > 0);
    else
        [~, order] = sort([sensitivity(improves).improvement], 'descend');
        improves = improves(order);
    end
    released = improves(1:min(numel(improves), ...
        cfg.stage5.maximumReleasedParameters));

    stepFraction = cfg.stage5.coordinateInitialStepFraction;
    for roundIndex = 1:cfg.stage5.coordinateSearchRounds
        improvedThisRound = false;
        for parameterIndex = released(:).'
            span = cfg.stage5.calibrationUpperBound(parameterIndex) - ...
                cfg.stage5.calibrationLowerBound(parameterIndex);
            step = stepFraction * span;
            for direction = [-1, 1]
                candidateTheta = best.theta;
                candidateTheta(parameterIndex) = min(max( ...
                    candidateTheta(parameterIndex) + direction * step, ...
                    cfg.stage5.calibrationLowerBound(parameterIndex)), ...
                    cfg.stage5.calibrationUpperBound(parameterIndex));
                candidate = evaluate(candidateTheta, sprintf( ...
                    'coordinate_r%d_p%d_d%+d', roundIndex, ...
                    parameterIndex, direction));
                if local_is_better(candidate.objectiveVector, ...
                        best.objectiveVector)
                    best = candidate;
                    improvedThisRound = true;
                end
            end
        end
        if ~improvedThisRound
            stepFraction = stepFraction * ...
                cfg.stage5.coordinateStepReduction;
        end
    end
end

if runtimeInitialized
    calllib(alias, 'DLL_SHT_Free');
    runtimeInitialized = false;
end

historyTable = local_history_table(history, cfg);
sensitivityTable = local_sensitivity_table(sensitivity);
result = struct('generatedAt', datestr(now, 31), 'thetaInitial', theta0, ...
    'thetaBest', best.theta, 'baseline', baseline, 'best', best, ...
    'releasedParameterIndex', released, 'sensitivity', sensitivity, ...
    'sensitivityTable', sensitivityTable, 'history', history, ...
    'historyTable', historyTable, 'evaluationCount', evaluationCount, ...
    'improved', local_is_better(best.objectiveVector, ...
    baseline.objectiveVector), 'accepted', best.mapAudit.accepted);
save(fullfile(outputDir, 'calibration_result.mat'), 'result', '-v7');
writetable(historyTable, fullfile(outputDir, 'calibration_history.csv'));
writetable(sensitivityTable, fullfile(outputDir, 'sensitivity_scan.csv'));
local_write_summary(fullfile(outputDir, 'calibration_summary.md'), ...
    result, cfg);

    function evaluation = evaluate(theta, label)
        key = local_theta_key(theta);
        if isKey(cache, key)
            evaluation = cache(key);
            return;
        end
        evaluationCount = evaluationCount + 1;
        if runtimeInitialized
            calllib(alias, 'DLL_SHT_Free');
            runtimeInitialized = false;
        end
        mapAudit = sht_startstop_write_candidate_maps( ...
            cfg, theta, runtime.controlDir);
        if ~mapAudit.accepted
            matrix = local_failed_matrix_result('候选特性图硬约束未通过');
            objective = [Inf(1, 7), mapAudit.smoothnessPenalty, Inf];
            merit = Inf;
        else
            engPtr = local_initialize_runtime(alias, cfg);
            runtimeInitialized = true;
            matrixOptions = struct('ngRatio', ...
                cfg.stage5.calibrationSubsetNgRatio, ...
                'branchNames', {cfg.stage5.calibrationSubsetBranches}, ...
                'branchFactors', local_branch_factors(cfg, ...
                cfg.stage5.calibrationSubsetBranches), ...
                'stateNames', {cfg.stage5.calibrationSubsetStates}, ...
                'label', label, 'writeEvidence', false);
            matrix = sht_startstop_evaluate_low_speed_matrix( ...
                alias, engPtr, cfg, runtime.controlDir, design, matrixOptions);
            priorPenalty = mean(((theta - theta0) ./ max( ...
                cfg.stage5.calibrationUpperBound - ...
                cfg.stage5.calibrationLowerBound, eps)) .^ 2);
            objective = [matrix.summary.objectiveVector, ...
                mapAudit.smoothnessPenalty, priorPenalty];
            merit = local_scalar_merit(matrix, mapAudit, priorPenalty, cfg);
        end
        evaluation = struct('label', label, 'theta', theta(:).', ...
            'mapAudit', mapAudit, 'matrix', matrix, ...
            'objectiveVector', objective, 'merit', merit);
        cache(key) = evaluation;
        history(end + 1, 1) = local_history_row( ...
            evaluationCount, evaluation);
    end
end

function engPtr = local_initialize_runtime(alias, cfg)
status = calllib(alias, 'DLL_SHT_InitialMode', cfg.modelMode);
assert(status == 0, '候选图运行配置初始化失败，状态码=%d。', status);
sht_startstop_configure_dll(alias, cfg);
engPtrInit.eng = libstruct('EngineTurboshaft');
engPtr = libstruct('EngineSHTPointer', engPtrInit);
stepIn = libpointer('doublePtr', zeros(512, 1));
stepOut = libpointer('doublePtr', zeros(128, 1));
status = calllib(alias, 'DLL_SHT_ConditionsInit', stepIn, stepOut, engPtr);
assert(status == 0, '候选图环境条件初始化失败，状态码=%d。', status);
end

function factor = local_branch_factors(cfg, selected)
factor = zeros(1, numel(selected));
for i = 1:numel(selected)
    index = find(strcmp(cfg.stage5.npBranchNames, selected{i}), 1, 'first');
    assert(~isempty(index), '未知阶段五Np分支：%s。', selected{i});
    factor(i) = cfg.stage5.npBranchFactors(index);
end
end

function merit = local_scalar_merit(matrix, mapAudit, priorPenalty, cfg)
s = matrix.summary;
applicable = [matrix.points.applicable];
rmsValue = [matrix.points.residualRms];
finite = applicable & isfinite(rmsValue);
residualPenalty = sum(log10(1 + rmsValue(finite) ./ ...
    cfg.stage5.matrixResidualRmsTolerance));
conditionPenalty = log10(1 + max(1, s.maximumCondition));
merit = 1e9 * s.failedCount + 1e8 * s.physicalFailureCount + ...
    1e7 * s.nonconvergedCount + 1e4 * residualPenalty + ...
    1e3 * s.rankDeficit + 1e2 * s.boundaryHitTotal + ...
    conditionPenalty + mapAudit.smoothnessPenalty + priorPenalty;
end

function matrix = local_failed_matrix_result(message)
summary = struct('accepted', false, 'failedCount', Inf, ...
    'physicalFailureCount', Inf, 'nonconvergedCount', Inf, ...
    'rankDeficit', Inf, 'boundaryHitTotal', Inf, ...
    'maximumResidualRms', Inf, 'maximumCondition', Inf, ...
    'objectiveVector', Inf(1, 7));
matrix = struct('summary', summary, 'points', repmat(struct(), 0, 1), ...
    'failureMessage', message, 'accepted', false);
end

function key = local_theta_key(theta)
key = sprintf('%.12g_', theta);
end

function tf = local_is_better(a, b)
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

function row = local_history_template()
row = struct('evaluation', 0, 'label', '', 'theta', nan(1, 12), ...
    'mapAccepted', false, 'failedCount', Inf, ...
    'physicalFailureCount', Inf, 'nonconvergedCount', Inf, ...
    'maximumResidualRms', Inf, 'maximumCondition', Inf, ...
    'rankDeficit', Inf, 'boundaryHitTotal', Inf, ...
    'smoothnessPenalty', Inf, 'merit', Inf);
end

function row = local_history_row(index, evaluation)
row = local_history_template();
row.evaluation = index;
row.label = evaluation.label;
row.theta = evaluation.theta;
row.mapAccepted = evaluation.mapAudit.accepted;
row.smoothnessPenalty = evaluation.mapAudit.smoothnessPenalty;
row.merit = evaluation.merit;
if isfield(evaluation.matrix, 'summary') && ...
        isfield(evaluation.matrix.summary, 'maximumResidualRms')
    s = evaluation.matrix.summary;
    row.failedCount = s.failedCount;
    row.physicalFailureCount = s.physicalFailureCount;
    row.nonconvergedCount = s.nonconvergedCount;
    row.maximumResidualRms = s.maximumResidualRms;
    row.maximumCondition = s.maximumCondition;
    row.rankDeficit = s.rankDeficit;
    row.boundaryHitTotal = s.boundaryHitTotal;
end
end

function tableOut = local_history_table(history, cfg)
n = numel(history);
row = repmat(struct(), n, 1);
for i = 1:n
    h = history(i);
    row(i).Evaluation = h.evaluation;
    row(i).Label = h.label;
    for j = 1:numel(cfg.stage5.calibrationParameterNames)
        row(i).(cfg.stage5.calibrationParameterNames{j}) = h.theta(j);
    end
    row(i).MapAccepted = h.mapAccepted;
    row(i).FailedCount = h.failedCount;
    row(i).PhysicalFailureCount = h.physicalFailureCount;
    row(i).NonconvergedCount = h.nonconvergedCount;
    row(i).MaximumResidualRms = h.maximumResidualRms;
    row(i).MaximumCondition = h.maximumCondition;
    row(i).RankDeficit = h.rankDeficit;
    row(i).BoundaryHitTotal = h.boundaryHitTotal;
    row(i).SmoothnessPenalty = h.smoothnessPenalty;
    row(i).Merit = h.merit;
end
tableOut = struct2table(row);
end

function item = local_sensitivity_template()
item = struct('parameterIndex', 0, 'parameterName', '', ...
    'minusMerit', Inf, 'plusMerit', Inf, 'bestDirection', 0, ...
    'improvement', -Inf, 'improvesLexicographically', false, ...
    'bestTheta', nan(1, 12));
end

function tableOut = local_sensitivity_table(sensitivity)
tableOut = struct2table(sensitivity);
end

function local_write_summary(path, result, cfg)
fid = fopen(path, 'w', 'n', 'UTF-8');
assert(fid >= 0, '无法写入阶段五校准摘要：%s。', path);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# 阶段五低速特性图受约束校准摘要\n\n');
fprintf(fid, '- 生成时间：%s\n', result.generatedAt);
fprintf(fid, '- 实际DLL评价次数：%d\n', result.evaluationCount);
fprintf(fid, '- 相对初值是否改善：%s\n', local_pass(result.improved));
fprintf(fid, '- 最佳候选特性图硬检查：%s\n', ...
    local_pass(result.best.mapAudit.accepted));
fprintf(fid, '- 校准子集初始/最佳失败点：%.0f / %.0f\n', ...
    result.baseline.matrix.summary.failedCount, ...
    result.best.matrix.summary.failedCount);
fprintf(fid, '- 校准子集初始/最佳最大RMSE：%.6e / %.6e\n\n', ...
    result.baseline.matrix.summary.maximumResidualRms, ...
    result.best.matrix.summary.maximumResidualRms);
fprintf(fid, '|参数|初值|最佳值|下界|上界|是否释放|\n');
fprintf(fid, '|---|---:|---:|---:|---:|---|\n');
for i = 1:numel(cfg.stage5.calibrationParameterNames)
    fprintf(fid, '|%s|%.8g|%.8g|%.8g|%.8g|%s|\n', ...
        cfg.stage5.calibrationParameterNames{i}, result.thetaInitial(i), ...
        result.thetaBest(i), cfg.stage5.calibrationLowerBound(i), ...
        cfg.stage5.calibrationUpperBound(i), ...
        local_yes(any(result.releasedParameterIndex == i)));
end
end

function value = local_pass(tf)
if tf
    value = 'PASS';
else
    value = 'FAIL';
end
end

function value = local_yes(tf)
if tf
    value = '是';
else
    value = '否';
end
end
