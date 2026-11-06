function result = sht_steady_model_uq_b_branch_constrained_replay( ...
        deterministicResult, testData, schedules, baseSeed, ...
        branchPrior, userOptions)
%SHT_STEADY_MODEL_UQ_B_BRANCH_CONSTRAINED_REPLAY
% 在不读取测试Np的条件下，对方法B后验粒子执行稳态合理分支回放。
%
% testData.Np_mean只保留供最终验证。本函数复制测试表，并用训练功率
% 曲线给出的Np分支中心构造DLL功率边界和稳态初值。每个粒子从分支
% 中心附近的多个Np初值启动，保留严格共同工作残差且位于数据驱动
% 容许带内的根；若多个根合格，选择离分支中心最近者。

if nargin < 6 || isempty(userOptions), userOptions = struct(); end
options = local_options(branchPrior, userOptions);
local_validate_input(deterministicResult, testData, schedules, ...
    baseSeed, branchPrior);

scheduleCell = schedules(:);
seedCell = baseSeed(:);
nCandidate = numel(scheduleCell);
nPoint = height(testData);
priorTable = branchPrior.testTable;
center = priorTable.Np_branch_center_rpm(:);
lower = priorTable.Np_lower_rpm(:);
upper = priorTable.Np_upper_rpm(:);

% 局部副本用训练数据估计的分支中心替换Np，只用于共同工作初值。
% 稳态求解器在每次Newton残差计算中按候选转速和实测Mkp/Mkg实时
% 换算轴功率，因此不需要也不会读取测试Np来构造负载边界。
replayData = testData;
replayData.Np_mean = center;

nPass = numel(options.seedRelativeOffsets);
passOutput = cell(nPass, 1);
passSeed = cell(nPass, 1);
seedTransferMaxAbsError = 0;
for k = 1:nPass
    currentSeed = seedCell;
    for c = 1:nCandidate
        currentSeed{c}(:, 8) = center .* ...
            (1 + options.seedRelativeOffsets(k));
    end
    % 外层已经逐初值选根，禁止公共内核再次执行多初值补算。
    batchOptions = struct( ...
        'routeOverride', 'steady', ...
        'initialSeedMatrices', {currentSeed}, ...
        'maxModelResidual', options.strictResidual, ...
        'steadyLoadBoundaryMode', 'torque', ...
        'steadyNpBranchEnabled', false);
    passOutput{k} = sht_steady_model_adapt_v2_common( ...
        'evaluateschedulebatchdataset', deterministicResult, ...
        replayData, scheduleCell, batchOptions);
    passSeed{k} = currentSeed;
    seedTransferMaxAbsError = max(seedTransferMaxAbsError, ...
        local_seed_transfer_error(passOutput{k}.candidate, currentSeed));
end

candidateTemplate = struct('schedule', struct(), 'prediction', table(), ...
    'valid', false, 'diagnostic', struct(), 'selectedPass', [], ...
    'selectedRelativeDistance', []);
candidate = repmat(candidateTemplate, nCandidate, 1);
recordCount = nCandidate * nPoint;
particleIndex = zeros(recordCount, 1);
pointId = strings(recordCount, 1);
selected = false(recordCount, 1);
selectedPass = nan(recordCount, 1);
selectedNp = nan(recordCount, 1);
selectedResidual = nan(recordCount, 1);
selectedRelativeDistance = nan(recordCount, 1);
nearestStrictNp = nan(recordCount, 1);
nearestStrictRelativeDistance = nan(recordCount, 1);
reason = strings(recordCount, 1);
cursor = 0;

for c = 1:nCandidate
    selectedPrediction = passOutput{1}.candidate(c).prediction;
    selectedSeed = nan(nPoint, 9);
    passByPoint = nan(nPoint, 1);
    distanceByPoint = nan(nPoint, 1);
    pointSelected = false(nPoint, 1);
    for p = 1:nPoint
        cursor = cursor + 1;
        particleIndex(cursor) = c;
        pointId(cursor) = string(testData.point_id(p));
        bestScore = Inf;
        nearestScore = Inf;
        for k = 1:nPass
            current = passOutput{k}.candidate(c);
            row = current.prediction(p, :);
            if string(row.point_id) ~= string(testData.point_id(p))
                error('SHT:SteadyUQBBranch:PointOrderMismatch', ...
                    '批量回放工况顺序与测试表不一致。');
            end
            np = row.Np;
            residual = row.max_model_residual;
            strict = row.valid && isfinite(np) && ...
                isfinite(residual) && residual <= options.strictResidual;
            if ~strict
                continue;
            end
            score = abs(np - center(p)) / center(p);
            if score < nearestScore
                nearestScore = score;
                nearestStrictNp(cursor) = np;
                nearestStrictRelativeDistance(cursor) = score;
            end
            insideGate = np >= lower(p) && np <= upper(p);
            if insideGate && score < bestScore
                bestScore = score;
                pointSelected(p) = true;
                selectedPrediction(p, :) = row;
                selectedSeed(p, :) = current.diagnostic.solutionSeed(p, :);
                passByPoint(p) = k;
                distanceByPoint(p) = score;
                selected(cursor) = true;
                selectedPass(cursor) = k;
                selectedNp(cursor) = np;
                selectedResidual(cursor) = residual;
                selectedRelativeDistance(cursor) = score;
            end
        end
        if pointSelected(p)
            reason(cursor) = "strict_root_inside_branch_gate";
        elseif isfinite(nearestStrictNp(cursor))
            reason(cursor) = "strict_roots_outside_branch_gate";
            selectedPrediction.valid(p) = false;
            selectedPrediction.error_message(p) = reason(cursor);
        else
            reason(cursor) = "no_strict_converged_root";
            selectedPrediction.valid(p) = false;
            selectedPrediction.error_message(p) = reason(cursor);
        end
    end
    candidate(c).schedule = scheduleCell{c};
    candidate(c).prediction = selectedPrediction;
    candidate(c).valid = all(pointSelected);
    candidate(c).diagnostic = struct( ...
        'solutionSeed', selectedSeed, ...
        'solutionAvailable', pointSelected, ...
        'branchCenterRpm', center, ...
        'branchLowerRpm', lower, ...
        'branchUpperRpm', upper);
    candidate(c).selectedPass = passByPoint;
    candidate(c).selectedRelativeDistance = distanceByPoint;
end

rootTable = table(particleIndex, pointId, selected, selectedPass, ...
    selectedNp, selectedResidual, selectedRelativeDistance, ...
    repmat(center, nCandidate, 1), repmat(lower, nCandidate, 1), ...
    repmat(upper, nCandidate, 1), nearestStrictNp, ...
    nearestStrictRelativeDistance, reason, ...
    'VariableNames', {'particle_local_index','point_id','selected', ...
    'selected_pass','selected_Np_rpm','selected_max_residual', ...
    'selected_relative_distance','branch_center_rpm', ...
    'branch_lower_rpm','branch_upper_rpm','nearest_strict_Np_rpm', ...
    'nearest_strict_relative_distance','reason'});

passIndex = (1:nPass).';
relativeOffset = options.seedRelativeOffsets(:);
strictPointRootCount = zeros(nPass, 1);
insideGatePointRootCount = zeros(nPass, 1);
allPointCandidateCount = zeros(nPass, 1);
for k = 1:nPass
    for c = 1:nCandidate
        pointPass = passOutput{k}.candidate(c).prediction;
        strict = pointPass.valid & ...
            pointPass.max_model_residual <= options.strictResidual;
        strictPointRootCount(k) = strictPointRootCount(k) + nnz(strict);
        inside = strict & pointPass.Np >= lower & pointPass.Np <= upper;
        insideGatePointRootCount(k) = ...
            insideGatePointRootCount(k) + nnz(inside);
        allPointCandidateCount(k) = ...
            allPointCandidateCount(k) + all(inside);
    end
end
passSummary = table(passIndex, relativeOffset, strictPointRootCount, ...
    insideGatePointRootCount, allPointCandidateCount, ...
    'VariableNames', {'pass_index','seed_relative_offset', ...
    'strict_point_root_count','inside_gate_point_root_count', ...
    'all_point_candidate_count'});

result = struct( ...
    'schemaVersion', 'steady_uq_b_branch_constrained_replay_v1', ...
    'route', 'steady', ...
    'candidate', candidate, ...
    'valid', [candidate.valid], ...
    'candidateCount', nCandidate, ...
    'pointCount', nPoint, ...
    'strictResidual', options.strictResidual, ...
    'seedRelativeOffsets', options.seedRelativeOffsets, ...
    'initialSeedTransferMaxAbsError', seedTransferMaxAbsError, ...
    'branchPrior', branchPrior, ...
    'replayData', replayData, ...
    'rootTable', rootTable, ...
    'passSummary', passSummary, ...
    'testNpUsedForBranchCenter', false, ...
    'testNpUsedForLoadPower', false, ...
    'steadyLoadBoundaryMode', 'torque', ...
    'formalPosteriorWeightsModified', false);
end

function options = local_options(branchPrior, userOptions)
halfWidth = branchPrior.relativeHalfWidth;
options = struct( ...
    'strictResidual', 1e-7, ...
    'seedRelativeOffsets', [0, -0.75 * halfWidth, 0.75 * halfWidth]);
names = fieldnames(options);
for i = 1:numel(names)
    if isfield(userOptions, names{i}) && ~isempty(userOptions.(names{i}))
        options.(names{i}) = userOptions.(names{i});
    end
end
if ~isnumeric(options.strictResidual) || ...
        ~isscalar(options.strictResidual) || ...
        ~isfinite(options.strictResidual) || options.strictResidual <= 0
    error('SHT:SteadyUQBBranch:BadResidualThreshold', ...
        'strictResidual必须为有限正标量。');
end
if ~isnumeric(options.seedRelativeOffsets) || ...
        isempty(options.seedRelativeOffsets) || ...
        any(~isfinite(options.seedRelativeOffsets(:))) || ...
        any(1 + options.seedRelativeOffsets(:) <= 0)
    error('SHT:SteadyUQBBranch:BadSeedOffsets', ...
        'seedRelativeOffsets必须是使1+offset保持正值的有限向量。');
end
options.seedRelativeOffsets = unique(options.seedRelativeOffsets(:).', ...
    'stable');
end

function local_validate_input(result, data, schedules, seed, prior)
requiredResult = {'route','options','parameterDefinition','finalSchedule'};
if ~isstruct(result) || any(~isfield(result, requiredResult))
    error('SHT:SteadyUQBBranch:BadDeterministicResult', ...
        '确定性结果缺少完整调度批量回放字段。');
end
if ~istable(data) || height(data) < 1 || ...
        ~ismember('Np_mean', data.Properties.VariableNames)
    error('SHT:SteadyUQBBranch:BadTestData', ...
        '测试数据必须包含Np_mean且至少有一个工况。');
end
if ~iscell(schedules) || isempty(schedules) || ...
        ~all(cellfun(@isstruct, schedules))
    error('SHT:SteadyUQBBranch:BadSchedules', ...
        'schedules必须为非空结构元胞数组。');
end
if ~iscell(seed) || numel(seed) ~= numel(schedules)
    error('SHT:SteadyUQBBranch:BadSeedContainer', ...
        'baseSeed必须与schedules具有相同元素数。');
end
for i = 1:numel(seed)
    if ~isnumeric(seed{i}) || ~isequal(size(seed{i}), [height(data), 9]) || ...
            any(~isfinite(seed{i}(:)))
        error('SHT:SteadyUQBBranch:BadSeedMatrix', ...
            '第%d个baseSeed必须是测试点数x9的有限矩阵。', i);
    end
end
if ~isstruct(prior) || ~isfield(prior, 'testTable') || ...
        height(prior.testTable) ~= height(data) || ...
        ~prior.allTestPointsAvailable || prior.testNpUsed
    error('SHT:SteadyUQBBranch:BadBranchPrior', ...
        'Np分支先验不可用、点数不匹配或错误使用了测试Np。');
end
if any(string(prior.testTable.point_id) ~= string(data.point_id))
    error('SHT:SteadyUQBBranch:BranchPointMismatch', ...
        'Np分支先验的工况顺序与测试数据不一致。');
end
end

function maximum = local_seed_transfer_error(candidate, expected)
maximum = 0;
for i = 1:numel(candidate)
    actual = candidate(i).diagnostic.initialSeed;
    if ~isequal(size(actual), size(expected{i})) || ...
            any(~isfinite(actual(:)))
        maximum = Inf;
        return;
    end
    maximum = max(maximum, max(abs(actual(:) - expected{i}(:))));
end
end
