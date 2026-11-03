function result = sht_steady_model_predict_posterior( ...
        estimationResult, estimationResultFile, deterministicPrediction, ...
        userOptions)
%SHT_STEADY_MODEL_PREDICT_POSTERIOR 任意输入工况的稳态后验传播内核。
%
% 本函数不读取测试集和测量输出。它复用方法B固定测试集传播中已经验证
% 的稳态分支约束、失败粒子补算和测量误差传播方法，并同时兼容方法A、
% 方法B正式后验。冻结个体模型的稳态解只用于确定合理共同工作分支，
% 不参与后验重加权。

if nargin < 4 || isempty(userOptions)
    userOptions = struct();
end
options = local_options(userOptions);
timer = tic;

local_validate_deterministic_input( ...
    estimationResult, estimationResultFile, deterministicPrediction);
[posterior, contract, manifest] = local_load_posterior(options);
local_validate_posterior_source( ...
    posterior, contract, estimationResultFile, options.method);

theta = posterior.theta;
formalWeight = posterior.weights(:);
formalWeight = formalWeight / sum(formalWeight);
[thetaUnique, uniqueWeight, originalToUnique] = ...
    local_merge_duplicate_particles(theta, formalWeight);

schedules = local_vector_to_schedules( ...
    options.method, contract, thetaUnique);
data = local_uncertainty_data(deterministicPrediction.internalData, ...
    deterministicPrediction.corrected.prediction);
nPoint = height(data);
seed = deterministicPrediction.corrected.diagnostic.solutionSeed;
baseSeed = repmat({seed}, size(thetaUnique, 2), 1);
branchPrior = local_deterministic_branch_prior( ...
    deterministicPrediction, options.branchRelativeHalfWidth);

branchReplay = sht_steady_model_uq_b_adaptive_branch_replay( ...
    estimationResult, data, schedules, baseSeed, branchPrior, ...
    options.branchReplayOptions);
valid = logical(branchReplay.valid(:));
validPosteriorMass = sum(uniqueWeight(valid));
if nnz(valid) < options.minimumValidParticleCount
    error('SHT:SteadyPrediction:InsufficientPosteriorReplay', ...
        ['后验稳态传播只有%d个有效唯一粒子，少于要求的%d个。' ...
         '请检查输入工况、冻结模型和共同工作分支。'], ...
        nnz(valid), options.minimumValidParticleCount);
end

conditionalWeight = uniqueWeight(valid);
conditionalWeight = conditionalWeight / sum(conditionalWeight);
validCandidate = branchReplay.candidate(valid);
[modelPrediction, finiteColumn] = local_prediction_matrix( ...
    validCandidate, nPoint);
if ~all(finiteColumn)
    error('SHT:SteadyPrediction:NonfinitePosteriorPrediction', ...
        '通过稳态共同工作判据的粒子仍包含非有限预测输出。');
end

% 对任意指定工况，环境和负载量是用户给定的模型输入，不把估计阶段
% Pt2/Tt1/Np/Ng测量误差再次作为输入不确定性传播。可观测量区间只在
% 模型输出区间上叠加冻结的输出测量误差和模型差异合同。
uncertaintyData = data;
nOutput = numel(local_output_names());
zeroInputCovariance = struct( ...
    'covariance', zeros(nOutput * nPoint), 'route', 'steady');
measurementOptions = struct('routeOverride', 'steady');
if strcmp(options.method, 'A')
    measurement = sht_steady_model_uq_common( ...
        'measurementcovariance', contract, zeroInputCovariance, ...
        uncertaintyData, measurementOptions);
else
    measurement = sht_steady_model_uq_b_common( ...
        'measurementcovariance', contract, zeroInputCovariance, ...
        uncertaintyData, measurementOptions);
end
if size(measurement.selected.cholLower, 1) ~= size(modelPrediction, 1)
    error('SHT:SteadyPrediction:PosteriorCovarianceDimensionMismatch', ...
        '可观测量协方差维数与后验模型预测维数不一致。');
end

rng(contract.config.randomSeed + options.randomSeedOffset, 'twister');
observableCenter = repelem( ...
    modelPrediction, 1, options.observableReplicateCount);
observablePrediction = observableCenter + ...
    measurement.selected.cholLower * randn(size(observableCenter));
observableWeight = repelem( ...
    conditionalWeight / options.observableReplicateCount, ...
    options.observableReplicateCount);

intervalTable = local_interval_table( ...
    uncertaintyData, deterministicPrediction.corrected.prediction, ...
    modelPrediction, conditionalWeight, observablePrediction, ...
    observableWeight, options.credibleProbability);
intervalsOrdered = all(intervalTable.model_lower <= ...
    intervalTable.model_median & ...
    intervalTable.model_median <= intervalTable.model_upper & ...
    intervalTable.observable_lower <= intervalTable.observable_median & ...
    intervalTable.observable_median <= intervalTable.observable_upper);

result = struct();
result.schemaVersion = 'SHT_STEADY_INPUT_POSTERIOR_PREDICTION_V1';
result.createdAt = datestr(now, 31);
result.method = options.method;
result.runId = manifest.runId;
result.contractHash = contract.contractHash;
result.sourcePosteriorParticleCount = size(theta, 2);
result.uniquePosteriorParticleCount = size(thetaUnique, 2);
result.duplicateParticleCount = size(theta, 2) - size(thetaUnique, 2);
result.originalToUniqueParticle = originalToUnique;
result.validUniqueParticleCount = nnz(valid);
result.validPosteriorMass = validPosteriorMass;
result.minimumValidPosteriorMass = options.minimumValidPosteriorMass;
result.posteriorWeightsModified = false;
result.invalidParticlesConditionedOutForPrediction = any(~valid);
result.modelPrediction = modelPrediction;
result.modelPredictionWeight = conditionalWeight;
result.observablePrediction = observablePrediction;
result.observablePredictionWeight = observableWeight;
result.observableReplicateCountPerParticle = ...
    options.observableReplicateCount;
result.intervalTable = intervalTable;
result.branchPrior = branchPrior;
result.branchReplay = branchReplay;
result.measurementUncertainty = measurement;
result.inputUncertaintyPropagated = false;
result.measurementDataUsed = false;
result.testDataUsed = false;
result.truthWasRead = false;
result.intervalsOrdered = intervalsOrdered;
result.passed = posterior.passed && ...
    validPosteriorMass >= options.minimumValidPosteriorMass && ...
    intervalsOrdered;
result.options = options;
result.runtime_s = toc(timer);
end

function options = local_options(userOptions)
if ~isstruct(userOptions) || ~isscalar(userOptions)
    error('SHT:SteadyPrediction:BadPosteriorOptions', ...
        '后验预测配置必须为标量结构体。');
end
options = struct();
options.method = upper(char(local_option(userOptions, 'method', 'B')));
options.runId = char(local_option(userOptions, 'runId', ''));
options.observableReplicateCount = local_option( ...
    userOptions, 'observableReplicateCount', 32);
options.credibleProbability = local_option( ...
    userOptions, 'credibleProbability', 0.95);
options.branchRelativeHalfWidth = local_option( ...
    userOptions, 'branchRelativeHalfWidth', 0.08);
options.minimumValidPosteriorMass = local_option( ...
    userOptions, 'minimumValidPosteriorMass', 0.95);
options.minimumValidParticleCount = local_option( ...
    userOptions, 'minimumValidParticleCount', 8);
options.randomSeedOffset = local_option( ...
    userOptions, 'randomSeedOffset', 12001);
options.branchReplayOptions = local_option( ...
    userOptions, 'branchReplayOptions', struct());

if ~ismember(options.method, {'A','B'})
    error('SHT:SteadyPrediction:BadPosteriorMethod', ...
        '后验方法必须为A或B。');
end
if ~isscalar(options.observableReplicateCount) || ...
        options.observableReplicateCount < 2 || ...
        options.observableReplicateCount ~= ...
        round(options.observableReplicateCount)
    error('SHT:SteadyPrediction:BadObservableReplicateCount', ...
        'observableReplicateCount必须为不小于2的整数。');
end
local_probability(options.credibleProbability, 'credibleProbability');
local_probability(options.minimumValidPosteriorMass, ...
    'minimumValidPosteriorMass');
if ~isscalar(options.branchRelativeHalfWidth) || ...
        ~isfinite(options.branchRelativeHalfWidth) || ...
        options.branchRelativeHalfWidth <= 0 || ...
        options.branchRelativeHalfWidth >= 0.5
    error('SHT:SteadyPrediction:BadBranchHalfWidth', ...
        'branchRelativeHalfWidth必须位于(0,0.5)内。');
end
if ~isscalar(options.minimumValidParticleCount) || ...
        options.minimumValidParticleCount < 1 || ...
        options.minimumValidParticleCount ~= ...
        round(options.minimumValidParticleCount)
    error('SHT:SteadyPrediction:BadMinimumParticleCount', ...
        'minimumValidParticleCount必须为正整数。');
end
if ~isstruct(options.branchReplayOptions) || ...
        ~isscalar(options.branchReplayOptions)
    error('SHT:SteadyPrediction:BadBranchReplayOptions', ...
        'branchReplayOptions必须为标量结构体。');
end
end

function local_probability(value, name)
if ~isscalar(value) || ~isfinite(value) || value <= 0 || value >= 1
    error('SHT:SteadyPrediction:BadProbability', ...
        '%s必须位于(0,1)内。', name);
end
end

function [formal, contract, manifest] = local_load_posterior(options)
resolveOptions = struct();
if ~isempty(options.runId)
    resolveOptions.runId = options.runId;
end
if strcmp(options.method, 'A')
    manifest = sht_steady_model_uq_io('resolve', resolveOptions);
    step1 = sht_steady_model_uq_io('loadstep', manifest, 1);
    step8 = sht_steady_model_uq_io('loadstep', manifest, 8);
else
    manifest = sht_steady_model_uq_b_io('resolve', resolveOptions);
    step1 = sht_steady_model_uq_b_io('loadstep', manifest, 1);
    step8 = sht_steady_model_uq_b_io('loadstep', manifest, 8);
end
contract = step1.contract;
formal = step8.formal;
formal.passed = logical(step8.passed) && logical(formal.passed);
end

function local_validate_deterministic_input( ...
        estimationResult, estimationResultFile, prediction)
requiredResult = {'route','options','parameterDefinition','finalSchedule'};
if ~isstruct(estimationResult) || any(~isfield(estimationResult, requiredResult))
    error('SHT:SteadyPrediction:BadEstimationForPosterior', ...
        '冻结辨识结果缺少后验稳态传播所需字段。');
end
if exist(estimationResultFile, 'file') ~= 2
    error('SHT:SteadyPrediction:MissingEstimationForPosterior', ...
        '冻结辨识结果文件不存在：%s。', estimationResultFile);
end
requiredPrediction = {'internalData','corrected','passed'};
if ~isstruct(prediction) || any(~isfield(prediction, requiredPrediction)) || ...
        ~prediction.passed
    error('SHT:SteadyPrediction:InvalidDeterministicAnchor', ...
        '冻结模型确定性预测未通过，不能作为后验分支锚点。');
end
if ~isfield(prediction.corrected, 'diagnostic') || ...
        ~isfield(prediction.corrected.diagnostic, 'solutionSeed') || ...
        ~isfield(prediction.corrected, 'prediction')
    error('SHT:SteadyPrediction:MissingDeterministicSeed', ...
        '确定性预测缺少稳态共同工作解或输出。');
end
seed = prediction.corrected.diagnostic.solutionSeed;
if ~isequal(size(seed), [height(prediction.internalData), 9]) || ...
        any(~isfinite(seed(:)))
    error('SHT:SteadyPrediction:BadDeterministicSeed', ...
        '冻结模型稳态初值必须为工况数x9的有限矩阵。');
end
end

function local_validate_posterior_source( ...
        formal, contract, estimationResultFile, method)
if ~isstruct(formal) || ~isfield(formal, 'theta') || ...
        ~isfield(formal, 'weights') || ~isfield(formal, 'passed') || ...
        ~formal.passed
    error('SHT:SteadyPrediction:PosteriorNotFormal', ...
        '方法%s结果不是已通过验收的正式后验。', method);
end
if size(formal.theta, 1) ~= contract.parameterCount || ...
        numel(formal.weights) ~= size(formal.theta, 2) || ...
        any(~isfinite(formal.theta(:))) || ...
        any(~isfinite(formal.weights(:))) || any(formal.weights(:) < 0) || ...
        sum(formal.weights) <= 0
    error('SHT:SteadyPrediction:BadFormalPosterior', ...
        '正式后验粒子、权重或参数维数不合法。');
end
if exist(contract.deterministicResultFile, 'file') ~= 2
    error('SHT:SteadyPrediction:MissingPosteriorDeterministicResult', ...
        '后验合同引用的冻结辨识结果不存在。');
end
expectedHash = sht_steady_model_uq_common( ...
    'filehash', contract.deterministicResultFile);
actualHash = sht_steady_model_uq_common('filehash', estimationResultFile);
if ~strcmp(expectedHash, actualHash)
    error('SHT:SteadyPrediction:PosteriorModelMismatch', ...
        ['后验使用的冻结辨识结果与当前预测选择的结果不一致。' ...
         '禁止混用模型和后验。']);
end
end

function [uniqueTheta, uniqueWeight, originalToUnique] = ...
        local_merge_duplicate_particles(theta, weight)
[rows, ~, originalToUnique] = unique(theta.', 'rows');
uniqueTheta = rows.';
uniqueWeight = accumarray(originalToUnique, weight, ...
    [size(rows, 1), 1], @sum, 0);
uniqueWeight = uniqueWeight / sum(uniqueWeight);
end

function schedules = local_vector_to_schedules(method, contract, theta)
schedules = cell(size(theta, 2), 1);
for i = 1:size(theta, 2)
    if strcmp(method, 'A')
        schedules{i} = sht_steady_model_uq_common( ...
            'vectortoschedule', contract, theta(:, i));
    else
        schedules{i} = sht_steady_model_uq_b_common( ...
            'vectortoschedule', contract, theta(:, i));
    end
end
end

function prior = local_deterministic_branch_prior(prediction, halfWidth)
center = prediction.corrected.prediction.Np(:);
pointId = string(prediction.corrected.prediction.point_id);
if any(~isfinite(center)) || any(center <= 0)
    error('SHT:SteadyPrediction:BadBranchCenter', ...
        '冻结模型没有提供有限正值的Np合理分支中心。');
end
lower = center .* (1 - halfWidth);
upper = center .* (1 + halfWidth);
priorTable = table(pointId, center, lower, upper, ...
    'VariableNames', {'point_id','Np_branch_center_rpm', ...
    'Np_lower_rpm','Np_upper_rpm'});
prior = struct('schemaVersion', ...
    'steady_prediction_deterministic_branch_prior_v1', ...
    'method', 'frozen_deterministic_model_center', ...
    'relativeHalfWidth', halfWidth, 'testTable', priorTable, ...
    'allTestPointsAvailable', true, 'testNpUsed', false, ...
    'measurementNpUsed', false, 'truthUsed', false);
end

function data = local_uncertainty_data(data, prediction)
mapping = { ...
    'Np_mean','Np'; 'Ng_mean','Ng'; 'Pt3_mean','Pt3'; ...
    'Tt3_mean','Tt3'; 'Tt45_mean','Tt45'; 'Pt45_mean','Pt45'; ...
    'Pt2_mean','Pt2'; 'Tt1_mean','Tt1'; ...
    'Pamb_mean','Pamb'; 'Tamb_mean','Tamb'};
for i = 1:size(mapping, 1)
    data.(mapping{i, 1}) = prediction.(mapping{i, 2});
end
end

function [matrix, finiteColumn] = local_prediction_matrix(candidate, nPoint)
names = local_output_names();
matrix = nan(numel(names) * nPoint, numel(candidate));
for i = 1:numel(candidate)
    for p = 1:nPoint
        rows = (p - 1) * numel(names) + (1:numel(names));
        for f = 1:numel(names)
            matrix(rows(f), i) = candidate(i).prediction.(names{f})(p);
        end
    end
end
finiteColumn = all(isfinite(matrix), 1);
end

function tbl = local_interval_table( ...
        data, deterministicPrediction, modelPrediction, modelWeight, ...
        observablePrediction, observableWeight, credibleProbability)
names = local_output_names();
units = local_output_units();
nPoint = height(data);
nRow = nPoint * numel(names);
pointId = strings(nRow, 1);
outputName = strings(nRow, 1);
unit = strings(nRow, 1);
deterministic = nan(nRow, 1);
modelMean = nan(nRow, 1);
modelLower = nan(nRow, 1);
modelMedian = nan(nRow, 1);
modelUpper = nan(nRow, 1);
observableLower = nan(nRow, 1);
observableMedian = nan(nRow, 1);
observableUpper = nan(nRow, 1);
alpha = 0.5 * (1 - credibleProbability);
probability = [alpha, 0.5, 1 - alpha];
cursor = 0;
for p = 1:nPoint
    for f = 1:numel(names)
        cursor = cursor + 1;
        row = (p - 1) * numel(names) + f;
        pointId(cursor) = string(data.point_id(p));
        outputName(cursor) = string(names{f});
        unit(cursor) = string(units{f});
        deterministic(cursor) = deterministicPrediction.(names{f})(p);
        modelMean(cursor) = sum(modelPrediction(row, :) .* modelWeight.');
        q = local_weighted_quantile( ...
            modelPrediction(row, :), modelWeight, probability);
        modelLower(cursor) = q(1);
        modelMedian(cursor) = q(2);
        modelUpper(cursor) = q(3);
        q = local_weighted_quantile( ...
            observablePrediction(row, :), observableWeight, probability);
        observableLower(cursor) = q(1);
        observableMedian(cursor) = q(2);
        observableUpper(cursor) = q(3);
    end
end
tbl = table(pointId, outputName, unit, deterministic, modelMean, ...
    modelLower, modelMedian, modelUpper, observableLower, ...
    observableMedian, observableUpper, ...
    'VariableNames', {'point_id','output_name','unit', ...
    'deterministic_frozen_model','posterior_model_mean', ...
    'model_lower','model_median','model_upper', ...
    'observable_lower','observable_median','observable_upper'});
end

function q = local_weighted_quantile(x, w, p)
x = x(:);
w = w(:);
valid = isfinite(x) & isfinite(w) & w >= 0;
x = x(valid);
w = w(valid);
if isempty(x) || sum(w) <= 0
    q = nan(size(p));
    return;
end
[x, order] = sort(x);
w = w(order) / sum(w);
cdf = cumsum(w);
q = nan(size(p));
for i = 1:numel(p)
    index = find(cdf >= p(i), 1, 'first');
    if isempty(index)
        index = numel(x);
    end
    q(i) = x(index);
end
end

function names = local_output_names()
names = {'Np','Ng','Pt3','Tt3','Tt45','Pt45'};
end

function units = local_output_units()
units = {'rpm','rpm','Pa','K','K','Pa'};
end

function value = local_option(options, name, defaultValue)
value = defaultValue;
if isfield(options, name) && ~isempty(options.(name))
    value = options.(name);
end
end
