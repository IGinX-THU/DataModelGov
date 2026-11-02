function varargout = sht_steady_model_uq_common(action, varargin)
%SHT_STEADY_MODEL_UQ_COMMON 2.4稳态修正参数贝叶斯UQ公共内核。
%
% 本文件只服务steady_model_uq_v2命名空间。正式推断直接以阶段D的
% DLL执行节点为随机变量；测试集、替代数据真值只允许在步骤10显式读取。

switch lower(char(action))
    case 'optionalplot'
        varargout{1}=local_optional_plot(varargin{:});
    case 'defaultconfig'
        varargout{1} = local_default_config(varargin{:});
    case 'buildcontract'
        varargout{1} = local_build_contract(varargin{:});
    case 'replaymodel'
        varargout{1} = local_replay_model(varargin{:});
    case 'evaluationidentity'
        varargout{1} = local_evaluation_identity(varargin{:});
    case 'loaddata'
        varargout{1} = local_load_data(varargin{:});
    case 'observation'
        [varargout{1:nargout}] = local_observation(varargin{:});
    case 'predictionvector'
        [varargout{1:nargout}] = local_prediction_vector(varargin{:});
    case 'evaluate'
        varargout{1} = local_evaluate(varargin{:});
    case 'preparebranchdata'
        [varargout{1:nargout}] = local_prepare_branch_data(varargin{:});
    case 'vectortoschedule'
        varargout{1} = local_vector_to_schedule(varargin{:});
    case 'scheduletovector'
        varargout{1} = local_schedule_to_vector(varargin{:});
    case 'routecontract'
        varargout{1} = local_route_contract(varargin{:});
    case 'inputcovariance'
        varargout{1} = local_input_covariance(varargin{:});
    case 'measurementcovariance'
        varargout{1} = local_measurement_covariance(varargin{:});
    case 'filehash'
        varargout{1} = local_file_hash(varargin{:});
    case 'flightuqfingerprint'
        varargout{1} = local_flight_uq_fingerprint();
    otherwise
        error('SHT:SteadyUQ:UnknownCommonAction', ...
            '未知2.4 UQ公共动作：%s。', action);
end
end

function audit=local_optional_plot(cfg,plotter)
% 仅包纯绘图函数；数据读写、协方差和后验判断由调用者在此函数之外完成。
audit=struct('enabled',local_option(cfg,'plotEnabled',true),'created',false, ...
    'errorIdentifier','','errorMessage','');
if ~audit.enabled,return;end
before=findall(groot,'Type','figure');
try
    plotter();audit.created=true;
catch err
    audit.errorIdentifier=err.identifier;audit.errorMessage=err.message;
    warning('TC24:UQ:OptionalPlot','可选绘图失败 [%s]：%s',err.identifier,err.message);
end
% 不碰用户或其他任务预先打开的图窗，也不使用close all。
after=findall(groot,'Type','figure');created=setdiff(after,before);
for k=1:numel(created),if isgraphics(created(k)),delete(created(k));end,end
end

function cfg = local_default_config(userCfg)
if nargin < 1 || isempty(userCfg)
    userCfg = struct();
end
cfg = struct();
cfg.modelMode=local_option(userCfg,'modelMode',1);
cfg.runtimeDirectory=char(local_option(userCfg,'runtimeDirectory',''));
cfg.outputDirectory=char(local_option(userCfg,'outputDirectory',''));
cfg.trainingFile=char(local_option(userCfg,'trainingFile',''));
cfg.testFile=char(local_option(userCfg,'testFile',''));
cfg.explicitTestFile=isfield(userCfg,'testFile');
if isfield(userCfg,'explicitTestFile'),cfg.explicitTestFile=userCfg.explicitTestFile;end
cfg.plotEnabled=logical(local_option(userCfg,'plotEnabled',true));
cfg.syntheticValidationFile=char(local_option(userCfg,'syntheticValidationFile',''));
cfg.dProposalRunId=char(local_option(userCfg,'dProposalRunId',''));
cfg.runId = char(local_option(userCfg, 'runId', ''));
cfg.route = char(local_option(userCfg, 'route', 'transient_instant'));
cfg.deterministicWorkbookFile = char(local_option( ...
    userCfg, 'deterministicWorkbookFile', ''));
cfg.randomSeed = local_option(userCfg, 'randomSeed', 20260821);
% TC24从Excel逐行读取sample_count，不设统一计数。旧六部件无该列的
% 历史合同保留明确的201兼容值；有该列时始终以实际数据为准。
defaultWindowCount=201;
if cfg.modelMode==0
    defaultWindowCount=[];
end
cfg.steadyWindowSampleCount = local_option( ...
    userCfg, 'steadyWindowSampleCount', defaultWindowCount);
cfg.priorScale = local_option(userCfg, 'priorScale', 1.0);
cfg.covarianceScenario = char(local_option( ...
    userCfg, 'covarianceScenario', 'engineering'));
cfg.pilotSampleCount = local_option(userCfg, 'pilotSampleCount', 64);
cfg.pilotReplicateCount = local_option(userCfg, 'pilotReplicateCount', 3);
cfg.formalSampleCount = local_option(userCfg, 'formalSampleCount', 256);
cfg.minimumEffectiveSampleSize = local_option(userCfg, ...
    'minimumEffectiveSampleSize',local_option(userCfg, ...
    'minimumImportanceEss',96));
cfg.minimumEffectiveSampleFraction = local_option(userCfg, ...
    'minimumEffectiveSampleFraction',local_option(userCfg, ...
    'minimumImportanceEssFraction',0.40));
cfg.maximumNormalizedWeight = local_option( ...
    userCfg, 'maximumNormalizedWeight', 0.05);
cfg.posteriorPredictiveSampleCount = local_option( ...
    userCfg, 'posteriorPredictiveSampleCount', 256);
cfg.figureVisible = char(local_option(userCfg, 'figureVisible', 'off'));
cfg.verbose = logical(local_option(userCfg, 'verbose', true));
cfg.useCache = logical(local_option(userCfg, 'useCache', true));
cfg.modelDiscrepancyScale = local_option( ...
    userCfg, 'modelDiscrepancyScale', 1.0);
cfg.smcPilotTargetEssFraction = local_option( ...
    userCfg,'smcPilotTargetEssFraction',0.60);
cfg.smcFormalTargetEssFraction = local_option( ...
    userCfg,'smcFormalTargetEssFraction',0.55);
cfg.nodePriorCommonCorrelation = local_option( ...
    userCfg, 'nodePriorCommonCorrelation', 0.60);
cfg.nodePriorCorrelationLength = local_option( ...
    userCfg, 'nodePriorCorrelationLength', 0.35);
cfg.nodePriorIndependentFraction = local_option( ...
    userCfg,'nodePriorIndependentFraction',0.05);
cfg.fuelPriorCommonCorrelation = local_option( ...
    userCfg, 'fuelPriorCommonCorrelation', 0.80);
cfg.fuelPriorCorrelationLength = local_option( ...
    userCfg, 'fuelPriorCorrelationLength', 0.40);
cfg.fuelPriorIndependentFraction = local_option( ...
    userCfg,'fuelPriorIndependentFraction',0.05);

validRoutes = {'transient_instant','steady'};
if ~ismember(cfg.route, validRoutes)
    error('SHT:SteadyUQ:BadRoute', 'route必须为transient_instant或steady。');
end
if ~isempty(cfg.steadyWindowSampleCount)
    validateattributes(cfg.steadyWindowSampleCount,{'numeric'}, ...
        {'scalar','real','finite','integer','positive'},mfilename,'steadyWindowSampleCount');
end
if cfg.pilotReplicateCount < 1 || cfg.pilotReplicateCount ~= floor(cfg.pilotReplicateCount)
    error('SHT:SteadyUQ:BadPilotReplicateCount', ...
        'pilotReplicateCount必须为正整数。');
end
if cfg.nodePriorIndependentFraction <= 0 || ...
        cfg.nodePriorIndependentFraction >= 1 || ...
        cfg.fuelPriorIndependentFraction <= 0 || ...
        cfg.fuelPriorIndependentFraction >= 1
    error('SHT:SteadyUQ:BadPriorIndependentFraction', ...
        '节点独立变差比例必须严格位于(0,1)。');
end
end

function contract = local_build_contract(cfg)
paths = sht_steady_model_uq_io('paths',cfg);
usage='internal_audit';
if cfg.modelMode==0,usage='formal';end
delivery = sht_load_2p4_deterministic_delivery( ...
    cfg.route, cfg.deterministicWorkbookFile,usage);
if cfg.modelMode==0
    % 正式UQ只恢复Excel公开载荷；不把历史求解MAT作为必要依赖。
    delivery.result=delivery.model;
    delivery.replaySidecarFile='';delivery.replaySidecarSha256='';
    delivery.semanticPayloadSha256=char(string(delivery.manifest.semantic_payload_sha256(1)));
    delivery.deterministicContractSha256=char(string(delivery.manifest.deterministic_contract_sha256(1)));
end
resultFile = delivery.replaySidecarFile;
deterministicWorkbookFile = delivery.workbookFile;
deterministic = delivery.result;
if ~isempty(cfg.runtimeDirectory)
    % 只为本次新合同指定回放包，不改Excel生成身份，不重签旧检查点。
    deterministic.options.runtimeDirectory=cfg.runtimeDirectory;
end
assert(deterministic.options.modelMode==cfg.modelMode, ...
    'TC24:UQ:ModelMismatch','确定性Excel与UQ请求的部件模式不一致。');

defaultTrainingFile = fullfile(paths.programRoot, 'TestData', ...
    'steady_bench_2p4_training_means.xlsx');
if cfg.modelMode==0
    defaultTrainingFile=fullfile(paths.programRoot,'TestData','three_component','tc24_training_means.xlsx');
end
trainingFile = defaultTrainingFile;
if ~isempty(cfg.trainingFile)
    trainingFile=sht_tc24_absolute_path(cfg.trainingFile);
elseif isfield(deterministic,'input') && ...
        isfield(deterministic.input,'trainingFile') && ...
        ~isempty(deterministic.input.trainingFile)
    % 确定性latest可能由另一Worktree生成并保存旧绝对路径。新合同必须
    % 固定读取当前代码根下的正式TestData；历史字段只用于身份一致性核验。
    historicalTrainingFile = sht_steady_model_uq_io( ...
        'decodepaths', char(deterministic.input.trainingFile));
    if exist(historicalTrainingFile, 'file') ~= 2
        error('SHT:SteadyUQ:HistoricalTrainingFileMissing', ...
            '确定性结果记录的训练输入无法在当前Worktree重定位：%s。', ...
            historicalTrainingFile);
    end
    if ~strcmp(local_file_hash(historicalTrainingFile), ...
            local_file_hash(defaultTrainingFile))
        error('SHT:SteadyUQ:TrainingFileIdentityMismatch', ...
            '当前Worktree正式训练输入与确定性结果记录的输入不一致。');
    end
end
testFile = fullfile(paths.programRoot, 'TestData', ...
    'steady_bench_2p4_test_means.xlsx');
if cfg.modelMode==0
    testFile=fullfile(paths.programRoot,'TestData','three_component','tc24_test_means.xlsx');
end
if cfg.explicitTestFile
    testFile=cfg.testFile;
    if ~isempty(testFile),testFile=sht_tc24_absolute_path(testFile);end
end
trainingData = local_read_input_table(trainingFile, '训练集');
if ~strcmp(local_file_hash(trainingFile),char(string(delivery.manifest.training_data_sha256(1))))
    error('TC24:UQ:TrainingIdentity','训练Excel与确定性结果记录的输入不一致。');
end
legacyCount=cfg.steadyWindowSampleCount;
if cfg.modelMode==0,legacyCount=[];end
meanSampleCount=sht_measurement_mean_sample_count(trainingData,legacyCount);
if cfg.modelMode~=0 && height(trainingData) ~= 7
    warning('SHT:SteadyUQ:TrainingPointCount', ...
        '当前训练点数为%d，程序将按实际点数构造观测。', height(trainingData));
end

[thetaHat, parameterTable] = local_node_parameter_table(deterministic);
priorSigma = parameterTable.prior_sigma .* cfg.priorScale;
[priorCorrelation, groupTable] = local_prior_correlation( ...
    parameterTable, cfg);
priorCovariance = diag(priorSigma) * priorCorrelation * diag(priorSigma);
priorCovariance = 0.5 * (priorCovariance + priorCovariance.');
lower = parameterTable.lower_bound;
upper = parameterTable.upper_bound;
if any(thetaHat <= lower) || any(thetaHat >= upper)
    bad = find(thetaHat <= lower | thetaHat >= upper, 1);
    error('SHT:SteadyUQ:PointEstimateOutsideBounds', ...
        '阶段D节点%s不在硬边界内部。', parameterTable.name(bad));
end

engineCfg = sht_default_config(struct('engine', struct('modelMode', cfg.modelMode, ...
    'runtimeDirectory',cfg.runtimeDirectory)));
artifacts = local_engine_artifacts(engineCfg.engine);
contractCore = struct();
contractCore.schemaVersion = ...
    'steady_model_uq_contract_v6_per_point_mean_counts';
contractCore.route = cfg.route;
routeContract = local_route_contract(cfg.route,cfg.modelMode);
contractCore.measurementRoleContract = routeContract;
contractCore.outputPredictionRoute = routeContract.outputPredictionRoute;
contractCore.trainingDataHash = local_file_hash(trainingFile);
contractCore.deterministicWorkbookHash = delivery.workbookSha256;
contractCore.deterministicWorkbookSemanticHash = ...
    delivery.semanticPayloadSha256;
contractCore.deterministicContractHash = ...
    delivery.deterministicContractSha256;
contractCore.deterministicReplaySidecarHash = ...
    delivery.replaySidecarSha256;
contractCore.engineArtifactHash = {artifacts.sha256};
contractCore.replayPhysics=struct('modelMode',engineCfg.engine.modelMode, ...
    'inletBoundaryMode',deterministic.options.inletBoundaryMode,'enhancedThermalEnabled',false,'rniEnabled',false, ...
    'loadBoundary','external_torque_power_from_candidate_shaft_speed', ...
    'exhaustBackpressure','ambient','boundaryDefaults',engineCfg.engine.boundary);
contractCore.pointIds = cellstr(trainingData.point_id);
contractCore.parameterNames = cellstr(parameterTable.name);
contractCore.parameterCoordinates = parameterTable.coordinate(:).';
contractCore.lower = lower(:).';
contractCore.upper = upper(:).';
contractCore.priorSigma = priorSigma(:).';
contractCore.priorCorrelation = priorCorrelation;
contractCore.priorType = 'gaussian_copula_truncated_normal';
contractCore.covarianceScenario = cfg.covarianceScenario;
contractCore.modelDiscrepancyScale = cfg.modelDiscrepancyScale;
contractCore.steadyWindowSampleCount = meanSampleCount(:).';
contractCore.runtimeCodeHash = local_runtime_code_hash();

contract = struct();
contract.modelMode=cfg.modelMode;
contract.schemaVersion = contractCore.schemaVersion;
contract.createdAt = datestr(now, 30);
contract.route = cfg.route;
contract.measurementRoleContract = routeContract;
contract.outputPredictionRoute = routeContract.outputPredictionRoute;
contract.config = cfg;
contract.trainingFile = trainingFile;
contract.testFile = testFile;
contract.deterministicWorkbookFile = deterministicWorkbookFile;
contract.deterministicWorkbookSha256 = delivery.workbookSha256;
contract.deterministicWorkbookSemanticSha256 = ...
    delivery.semanticPayloadSha256;
contract.deterministicRunId = delivery.runId;
contract.deterministicResultFile = resultFile;
if cfg.modelMode==0,contract.replayModel=deterministic;end
contract.deterministicReplaySidecarSha256 = ...
    delivery.replaySidecarSha256;
contract.deterministicFormalInterface = delivery.formalInterface;
contract.trainingData = trainingData;
contract.trainingPointIds = string(trainingData.point_id);
contract.trainingPointCount = height(trainingData);
contract.residualPerPoint = numel(routeContract.residualOrder);
contract.observationDimension = contract.residualPerPoint * height(trainingData);
contract.residualOrder = routeContract.residualOrder;
contract.parameterCount = height(parameterTable);
contract.aggregateParameterCount = height(parameterTable);
contract.parameterTable = parameterTable;
contract.parameterGroupTable = groupTable;
contract.thetaHat = thetaHat(:);
contract.lowerBound = lower(:);
contract.upperBound = upper(:);
contract.priorMean = zeros(contract.parameterCount, 1);
contract.priorSigma = priorSigma(:);
contract.priorCorrelation = priorCorrelation;
contract.priorCovariance = priorCovariance;
contract.priorType = 'gaussian_copula_truncated_normal';
contract.scheduleTemplate = deterministic.finalSchedule;
contract.deterministicOffsetParameterCount = ...
    height(deterministic.parameterDefinition) + 1;
contract.scheduleConditioning = ...
    'variable_dll_execution_node_values_inferred_coordinates_frozen';
contract.fixedPressureLossZeroAnchorCount = 3;
if cfg.modelMode==0,contract.fixedPressureLossZeroAnchorCount=4;end
contract.trainingOnlyUntilStep10 = true;
contract.truthAccessAllowedBeforeStep10 = false;
contract.testAccessAllowedBeforeStep10 = false;
contract.steadyWindowSampleCount = meanSampleCount;
if ~ismember('sample_count',trainingData.Properties.VariableNames)
    % 旧文件无计数列时，保留调用者明确给定的标量，供任意大小的
    % 历史测试集使用；不能将其扩展为训练向量后误套到另一批数据。
    contract.steadyWindowSampleCount = legacyCount;
end
contract.engineArtifacts = artifacts;
contract.flightUqFingerprintBefore = local_flight_uq_fingerprint();
contract.contractHash = local_text_hash(jsonencode(contractCore));
contract.cacheFile = fullfile(paths.middleRoot, 'cache', ...
    ['exact_training_cache_' contract.contractHash(1:16) '.mat']);
end

function data = local_load_data(contract, role)
role = lower(char(role));
switch role
    case 'training'
        data = contract.trainingData;
    case 'test'
        if isempty(contract.testFile),data=contract.trainingData([],:);
        else,data = local_read_input_table(contract.testFile, '测试集');end
    otherwise
        error('SHT:SteadyUQ:BadDataRole', '数据角色必须为training或test。');
end
end

function [vector, labels, units] = local_observation(contract, data, routeOverride)
if nargin < 3 || isempty(routeOverride)
    route = contract.route;
else
    route = char(routeOverride);
end
n = height(data);
names = local_route_contract(route,local_contract_mode(contract)).residualOrder;
vector = zeros(n * numel(names), 1);
labels = strings(size(vector));
units = strings(size(vector));
cursor = 0;
for i = 1:n
    for j = 1:numel(names)
        cursor = cursor + 1;
        name = names{j};
        vector(cursor) = local_observed_value(data, i, name);
        labels(cursor) = string(data.point_id(i)) + "/" + string(name);
        units(cursor) = string(local_residual_unit(name));
    end
end
end

function [vector, labels, units] = local_prediction_vector(route, prediction, contract)
n = height(prediction);
if nargin<3,contract=struct();end
names = local_route_contract(route,local_contract_mode(contract)).residualOrder;
vector = zeros(n * numel(names), 1);
labels = strings(size(vector));
units = strings(size(vector));
cursor = 0;
for i = 1:n
    for j = 1:numel(names)
        cursor = cursor + 1;
        name = names{j};
        vector(cursor) = prediction.(name)(i);
        labels(cursor) = string(prediction.point_id(i)) + "/" + string(name);
        units(cursor) = string(local_residual_unit(name));
    end
end
end

function output = local_evaluate(contract, thetaMatrix, data, options)
if nargin < 3 || isempty(data)
    data = contract.trainingData;
end
if nargin < 4 || isempty(options)
    options = struct();
end
if size(thetaMatrix, 1) ~= contract.parameterCount
    error('SHT:SteadyUQ:BadThetaMatrix', ...
        '候选矩阵必须为%d行。', contract.parameterCount);
end
needPredictions = logical(local_option(options, 'returnPredictions', false));
evaluationRoute = char(local_option(options, 'routeOverride', contract.route));
routeContract = local_route_contract(evaluationRoute,local_contract_mode(contract));
useCache = logical(local_option(options, 'useCache', contract.config.useCache));
defaultCacheFile = contract.cacheFile;
if ~strcmp(evaluationRoute, contract.route)
    cacheFolder = fileparts(defaultCacheFile);
    defaultCacheFile = fullfile(cacheFolder, ...
        ['exact_output_' evaluationRoute '_cache_' ...
        contract.contractHash(1:16) '.mat']);
end
cacheFile = sht_steady_model_uq_io('decodepaths', char(local_option( ...
    options, 'cacheFile', defaultCacheFile)));
if useCache
    sht_steady_model_uq_io('assertcachefile', cacheFile,contract.config);
end
[observation, ~, ~] = local_observation(contract, data, evaluationRoute);
nCandidate = size(thetaMatrix, 2);
residual = nan(numel(observation), nCandidate);
valid = false(1, nCandidate);
prediction = cell(1, nCandidate);
inside = all(thetaMatrix >= contract.lowerBound & ...
    thetaMatrix <= contract.upperBound, 1) & all(isfinite(thetaMatrix), 1);

cache = local_empty_cache(contract, numel(observation), evaluationRoute);
evaluationIdentity=local_evaluation_identity(contract,data,options,evaluationRoute);
cache.evaluationIdentity=evaluationIdentity;
if useCache && ~needPredictions && exist(cacheFile, 'file') == 2
    loaded = load(cacheFile, 'cache');
    if isfield(loaded, 'cache') && ...
            strcmp(loaded.cache.contractHash, contract.contractHash) && ...
            isfield(loaded.cache, 'evaluationRoute') && ...
            strcmp(loaded.cache.evaluationRoute, evaluationRoute) && ...
            loaded.cache.residualDimension == numel(observation) && ...
            isfield(loaded.cache,'evaluationIdentity') && ...
            strcmp(loaded.cache.evaluationIdentity,evaluationIdentity)
        cache = loaded.cache;
    end
end

hitCount = 0;
newIndex = [];
newKeys = {};
duplicateOf=zeros(1,nCandidate);
for i = 1:nCandidate
    if ~inside(i)
        continue;
    end
    key = local_theta_key(thetaMatrix(:, i));
    if useCache && ~needPredictions
        idx = find(strcmp(cache.keys, key), 1);
    else
        idx = [];
    end
    if ~isempty(idx)
        residual(:, i) = cache.residual(:, idx);
        valid(i) = cache.valid(idx);
        hitCount = hitCount + 1;
    else
        duplicate=find(strcmp(newKeys,key),1);
        if ~isempty(duplicate)
            duplicateOf(i)=newIndex(duplicate);hitCount=hitCount+1;continue;
        end
        newIndex(end + 1) = i; %#ok<AGROW>
        newKeys{end + 1} = key; %#ok<AGROW>
    end
end

dllTimer = tic;
branchMeta = struct('enabled', false, 'role', "not_applicable", ...
    'testNpUsed', false, 'prior', struct());
if ~isempty(newIndex)
    deterministic.result=local_replay_model(contract);
    if local_option(options,'independentRemeasurement',false)
        deterministic.result.options.fuelInputSemantics='physical_model';
    end
    [replayData, branchMeta] = local_prepare_branch_data( ...
        contract, data, deterministic.result, evaluationRoute,local_option(options,'independentRemeasurement',false));
    schedule = cell(1, numel(newIndex));
    for k = 1:numel(newIndex)
        schedule{k} = local_vector_to_schedule( ...
            contract, thetaMatrix(:, newIndex(k)));
    end
    batchOptions = struct('steadyNpBranchEnabled', branchMeta.enabled, ...
        'routeOverride', evaluationRoute);
    batchOptions.uqSteadyContinuation=local_contract_mode(contract)==0 && ...
        strcmp(evaluationRoute,'steady') && local_option(options,'independentRemeasurement',false) && ...
        local_option(options,'uqSteadyContinuation',true);
    if isfield(options,'uqContinuationOptions'),batchOptions.uqContinuationOptions=options.uqContinuationOptions;end
    if isfield(options, 'useRobustTransientFallback') && ...
            ~isempty(options.useRobustTransientFallback)
        batchOptions.useRobustTransientFallback = ...
            logical(options.useRobustTransientFallback);
    end
    batch = sht_steady_model_adapt_v2_common( ...
        'evaluateschedulebatchdataset', deterministic.result, replayData, ...
        schedule, batchOptions);
    for k = 1:numel(newIndex)
        i = newIndex(k);
        item = batch.candidate(k);
        if item.valid
            predicted = local_prediction_vector(evaluationRoute, item.prediction,contract);
            residual(:, i) = predicted - observation;
            valid(i) = all(isfinite(residual(:, i)));
        end
        if needPredictions
            prediction{i} = item.prediction;
        end
        if useCache && ~needPredictions
            cache.keys{end + 1} = newKeys{k};
            cache.theta(:, end + 1) = thetaMatrix(:, i);
            cache.residual(:, end + 1) = residual(:, i);
            cache.valid(end + 1) = valid(i);
        end
    end
end
dllRuntime = toc(dllTimer);
for i=find(duplicateOf)
    j=duplicateOf(i);residual(:,i)=residual(:,j);valid(i)=valid(j);prediction{i}=prediction{j};
end
if useCache && ~needPredictions && ~isempty(newIndex)
    cache.physicalPrediction=cache.residual+observation;
    cache.updatedAt = datestr(now, 30);
    cache.evaluationCount = size(cache.theta, 2);
    [folder, ~, ~] = fileparts(cacheFile);
    if exist(folder, 'dir') ~= 7, mkdir(folder); end
    save(cacheFile, 'cache', '-v7.3');
end

output = struct();
output.theta = thetaMatrix;
output.residual = residual;
output.valid = valid;
output.prediction = prediction;
output.insideBounds = inside;
output.candidateCount = nCandidate;
output.cacheHitCount = hitCount;
output.dllEvaluationCount = numel(newIndex);
output.dllRuntime_s = dllRuntime;
output.cacheFile = cacheFile;
output.npBranch = branchMeta;
output.route = evaluationRoute;
output.residualOrder = routeContract.residualOrder;
end

function [data, meta] = local_prepare_branch_data( ...
        contract, data, deterministicResult, routeOverride,forceTarget)
% 稳态共同工作方程可能存在多个数学根。训练回放允许使用训练点实测Np
% 识别物理解；独立目标回放只能由冻结训练功率曲线预测Np分支。
meta = struct('enabled', false, 'role', "not_applicable", ...
    'testNpUsed', false, 'prior', struct());
if nargin < 4 || isempty(routeOverride)
    route = contract.route;
else
    route = char(routeOverride);
end
local_route_contract(route);
if ~strcmp(route, 'steady')
    return;
end
training = contract.trainingData;
isTraining=all(ismember(string(data.point_id),string(training.point_id)));
if nargin>=5 && forceTarget,isTraining=false;end
if ~isTraining && isfield(deterministicResult,'npBranchModel') && ...
        ~isempty(deterministicResult.npBranchModel)
    [data,prior]=sht_np_branch_delivery('query', ...
        deterministicResult.npBranchModel,data,deterministicResult.options.inletBoundaryMode);
    % 输出测量不能通过初值回流进独立预测；适用域外仍用工程初值求平衡。
    runtimeDirectory='';
    if isfield(contract.config,'runtimeDirectory'),runtimeDirectory=contract.config.runtimeDirectory;end
    cfg=sht_default_config(struct('engine',struct('modelMode',contract.modelMode, ...
        'runtimeDirectory',runtimeDirectory)));
    data.Np_mean(:)=cfg.engine.initial.Np0;
    data.Np_mean(prior.available)=data.Np_branch_center_rpm(prior.available);
    data.Ng_mean(:)=cfg.engine.initial.Ng0;
    if ismember('Pshaft_mean',data.Properties.VariableNames)
        data.Pshaft_mean=data.Mkp_mean.*data.Np_mean*pi/30;
    end
    meta.enabled=true;meta.role="target";meta.prior=prior;
    return;
end
trainingReference = table(string(training.point_id), ...
    double(training.Np_mean), ...
    'VariableNames', {'point_id','Np_ref_rpm'});
branchOptions = struct();
trainingHalfWidth = 0.20;
if nargin >= 3 && isstruct(deterministicResult) && ...
        isfield(deterministicResult, 'options')
    resultOptions = deterministicResult.options;
    if isfield(resultOptions, 'steadyNpBranchPriorOptions') && ...
            ~isempty(resultOptions.steadyNpBranchPriorOptions)
        branchOptions = resultOptions.steadyNpBranchPriorOptions;
    end
    if isfield(resultOptions, ...
            'steadyNpTrainingBranchRelativeHalfWidth') && ...
            ~isempty(resultOptions.steadyNpTrainingBranchRelativeHalfWidth)
        trainingHalfWidth = ...
            resultOptions.steadyNpTrainingBranchRelativeHalfWidth;
    end
end
if isTraining
    prior=struct('allTestPointsAvailable',true, ...
        'testTable',table(string(data.point_id),true(height(data),1), ...
        'VariableNames',{'point_id','available'}));
else
    prior = sht_steady_np_branch_prior(training, data, trainingReference, branchOptions);
end
if ~prior.allTestPointsAvailable
    unavailable = prior.testTable.point_id(~prior.testTable.available);
    error('SHT:SteadyUQ:NpBranchTargetOutOfRange', ...
        ['以下UQ回放工况超出训练功率曲线覆盖域：%s。为避免测试' ...
         '分支外插，程序拒绝继续。'], ...
        strjoin(cellstr(unavailable), ', '));
end
if isTraining
    center = double(data.Np_mean);
    lower = center .* (1 - trainingHalfWidth);
    upper = center .* (1 + trainingHalfWidth);
    relativeHalfWidth = repmat(trainingHalfWidth, height(data), 1);
    source = "training_observed_np_root_selector";
    referenceUsesPointNp = true;
    role = "training";
else
    center = prior.testTable.Np_branch_center_rpm;
    lower = prior.testTable.Np_lower_rpm;
    upper = prior.testTable.Np_upper_rpm;
    relativeHalfWidth = prior.testTable.relative_half_width;
    source = "training_power_curve";
    referenceUsesPointNp = false;
    role = "target";
end
data.Np_branch_center_rpm = center;
data.Np_branch_lower_rpm = lower;
data.Np_branch_upper_rpm = upper;
data.Np_branch_relative_half_width = relativeHalfWidth;
data.Np_branch_available = prior.testTable.available;
data.Np_branch_source = repmat(source, height(data), 1);
data.Np_branch_reference_uses_point_Np = ...
    repmat(referenceUsesPointNp, height(data), 1);
meta.enabled = true;
meta.role = role;
meta.testNpUsed = false;
meta.prior = prior;
end

function result = local_input_covariance(contract, data, options)
% 用精确DLL中心差分传播测量输入误差。公共偏置和逐点白噪声分开建模。
if nargin < 2 || isempty(data)
    data = contract.trainingData;
end
if nargin < 3 || isempty(options)
    options = struct();
end
if ~isstruct(options) || ~isscalar(options)
    error('SHT:SteadyUQ:BadInputCovarianceOptions', ...
        '输入误差传播配置必须为标量结构体。');
end
evaluationRoute = char(local_option(options, 'routeOverride', contract.route));
routeContract = local_route_contract(evaluationRoute,local_contract_mode(contract));
residualOrder = routeContract.residualOrder;
if numel(residualOrder) ~= contract.residualPerPoint
    error('SHT:SteadyUQ:ResidualDimensionMismatch', ...
        '路径%s每点输出数与概率合同不一致。', evaluationRoute);
end
nPoint = height(data);
nObservation = nPoint * numel(residualOrder);
input = routeContract.propagatedInputDefinition;
sensorNames = {input.sensor};
sensorCfg = sht_measurement_bias_generator('channelConfig', sensorNames);
if local_contract_mode(contract)==0
    sensorCfg=sht_tc24_uq_measurement('sensors',sensorNames);
end
if any(~sensorCfg.supported)
    error('SHT:SteadyUQ:UnsupportedInputSensor', ...
        '输入误差传播包含未配置传感器。');
end
deterministic.result=local_replay_model(contract);
if local_option(options,'independentRemeasurement',false)
    deterministic.result.options.fuelInputSemantics='physical_model';
end
[replayData, branchMeta] = local_prepare_branch_data( ...
    contract, data, deterministic.result, evaluationRoute,local_option(options,'independentRemeasurement',false));

variant = {};
meta = repmat(struct('kind','','channel',0,'point',0,'delta',NaN), 0, 1);
% 公共偏置：Wf公共偏置已由第11参数显式估计，严禁重复传播。
for c = 1:numel(input)
    if strcmp(input(c).sensor, 'Wf') && ~local_option(options,'independentRemeasurement',false)
        continue;
    end
    delta = max(sensorCfg.noiseStd(c), 0.10 * sensorCfg.totalBiasHalfWidth(c));
    [variant, meta] = local_add_data_derivative_pair( ...
        variant, meta, replayData, input(c).field, 0, delta, 'common', c);
end
% 白噪声均值按工况独立，每个输入通道逐点传播。
for c = 1:numel(input)
    delta = max(sensorCfg.noiseStd(c), 0.05 * sensorCfg.totalBiasHalfWidth(c));
    for p = 1:nPoint
        [variant, meta] = local_add_data_derivative_pair( ...
            variant, meta, replayData, input(c).field, p, delta, 'point', c);
    end
end

variantOptions = struct('routeOverride', evaluationRoute, ...
    'steadyNpBranchEnabled', branchMeta.enabled);
variantOptions.useRobustTransientFallback=logical(local_option(options,'useRobustTransientFallback',true));
compact=local_contract_mode(contract)==0 && logical(local_option(options,'compactPointVariants',true));
if compact
    % 单点输入噪声只影响本点方程，公共扰动仍保留全表。
    for v=1:numel(variant)
        if meta(v).point>0,variant{v}=variant{v}(meta(v).point,:);end
    end
end
if isfield(options, 'initialSeedMatrix') && ...
        ~isempty(options.initialSeedMatrix)
    variantOptions.initialSeedMatrix = options.initialSeedMatrix;
    if compact
        variantOptions.initialSeedMatrices=cell(numel(variant),1);
        for v=1:numel(variant)
            rows=1:nPoint;if meta(v).point>0,rows=meta(v).point;end
            variantOptions.initialSeedMatrices{v}=options.initialSeedMatrix(rows,:);
        end
        variantOptions=rmfield(variantOptions,'initialSeedMatrix');
    end
end
if isfield(options, 'maxModelResidual') && ...
        ~isempty(options.maxModelResidual)
    variantOptions.maxModelResidual = options.maxModelResidual;
end
if isfield(options, 'steadyLoadBoundaryMode') && ...
        ~isempty(options.steadyLoadBoundaryMode)
    variantOptions.steadyLoadBoundaryMode = ...
        options.steadyLoadBoundaryMode;
end
inputTimer=tic;
batch = sht_steady_model_adapt_v2_common('evaluatedatasetvariants', ...
    deterministic.result, variant, ...
    zeros(contract.deterministicOffsetParameterCount, 1), variantOptions);
nDerivative = numel(meta) / 2;
Gcommon = zeros(nObservation, numel(input));
Gpoint = zeros(nObservation, numel(input) * nPoint);
commonUsed = false(numel(input), 1);
pointCursor = zeros(numel(input), 1);
for d = 1:nDerivative
    plus = batch.variant(2*d - 1);
    minus = batch.variant(2*d);
    if ~(plus.valid && minus.valid)
        error('SHT:SteadyUQ:InputDerivativeReplayFailed', ...
            '输入误差差分第%d组回放无效。', d);
    end
    vp = local_prediction_vector(evaluationRoute, plus.prediction,contract);
    vm = local_prediction_vector(evaluationRoute, minus.prediction,contract);
    info = meta(2*d - 1);
    derivative = (vp - vm) / (2 * info.delta);
    if compact && info.point>0
        fullDerivative=zeros(nObservation,1);
        rows=(info.point-1)*numel(residualOrder)+(1:numel(residualOrder));
        fullDerivative(rows)=derivative;derivative=fullDerivative;
    end
    if local_contract_mode(contract)==0
        % 同一Pt1/Tt1误差既进入模型输入，也进入间接Wa1观测；残差取两者之差。
        flowPosition=find(strcmp(residualOrder,'Wa2'),1);
        flowDerivative=sht_tc24_meter_input_sensitivity(data,input(info.channel).sensor);
        points=(1:nPoint).';if info.point>0,points=info.point;end
        indices=(points-1)*numel(residualOrder)+flowPosition;
        derivative(indices)=derivative(indices)-flowDerivative(points);
    end
    if strcmp(info.kind, 'common')
        Gcommon(:, info.channel) = derivative;
        commonUsed(info.channel) = true;
    else
        pointCursor(info.channel) = pointCursor(info.channel) + 1;
        column = (info.channel - 1) * nPoint + pointCursor(info.channel);
        Gpoint(:, column) = derivative;
    end
end

% 2.4首轮不传播输入通道随流量变化的偏置漂移，只传播一次试车内
% 冻结的公共偏置及稳态窗口均值白噪声。总半宽中属于漂移的额度必须
% 扣除，不能把它误当成另一份独立公共偏置。
commonBiasHalfWidth = max(sensorCfg.totalBiasHalfWidth(:)- ...
    sensorCfg.maxFlowDrift(:),0);
sigmaCommon = commonBiasHalfWidth / sqrt(3);
sigmaCommon(~commonUsed) = 0;
Rcommon = Gcommon * diag(sigmaCommon .^ 2) * Gcommon.';
legacyCount=contract.steadyWindowSampleCount;
if local_contract_mode(contract)==0,legacyCount=[];end
meanSampleCount=sht_measurement_mean_sample_count(data,legacyCount);
% Gpoint按通道、通道内按工况排列；不能把训练计数用于另一批测试点。
sigmaByPoint=sensorCfg.noiseStd(:).'./sqrt(meanSampleCount(:));
sigmaPoint=sigmaByPoint(:);
Rwhite = Gpoint * diag(sigmaPoint .^ 2) * Gpoint.';
result = struct('covariance', Rcommon + Rwhite, ...
    'compactPointVariants',compact,'pointSolveCount',sum(cellfun(@height,variant)), ...
    'runtime_s',toc(inputTimer), ...
    'commonBiasCovariance', Rcommon, 'whiteNoiseMeanCovariance', Rwhite, ...
    'commonSensitivity', Gcommon, 'pointSensitivity', Gpoint, ...
    'inputDefinition', {input}, 'sensorConfig', sensorCfg, ...
    'sigmaCommon', sigmaCommon, 'sigmaPoint', sigmaPoint, ...
    'meanSampleCount',meanSampleCount, ...
    'commonUsed', commonUsed, 'route', evaluationRoute, ...
    'residualOrder', {residualOrder}, 'variantCount', numel(variant), ...
    'stateInputSensors', {routeContract.stateInputSensors}, ...
    'inputFlowDriftPropagated', false, ...
    'npBranch', branchMeta, ...
    'roleContractVersion', routeContract.schemaVersion);
end

function result = local_measurement_covariance( ...
        contract, inputResult, data, options)
% 构造直接输出测量、输入传播、稳态判定及预冻结模型差异协方差。
if nargin < 3 || isempty(data)
    data = contract.trainingData;
end
if nargin < 4 || isempty(options)
    options = struct();
end
if ~isstruct(options) || ~isscalar(options)
    error('SHT:SteadyUQ:BadMeasurementCovarianceOptions', ...
        '测量协方差配置必须为标量结构体。');
end
evaluationRoute = char(local_option(options, 'routeOverride', contract.route));
routeContract = local_route_contract(evaluationRoute,local_contract_mode(contract));
residualOrder = routeContract.residualOrder;
if numel(residualOrder) ~= contract.residualPerPoint
    error('SHT:SteadyUQ:ResidualDimensionMismatch', ...
        '路径%s每点输出数与概率合同不一致。', evaluationRoute);
end
if isfield(inputResult, 'route') && ...
        ~strcmp(inputResult.route, evaluationRoute)
    error('SHT:SteadyUQ:InputCovarianceRouteMismatch', ...
        '输入协方差路径%s与测量协方差路径%s不一致。', ...
        inputResult.route, evaluationRoute);
end
nPoint = height(data);
nResidual = numel(residualOrder);
nObs = nPoint * nResidual;
Routput = zeros(nObs);
legacyCount=contract.steadyWindowSampleCount;
if local_contract_mode(contract)==0,legacyCount=[];end
meanSampleCount=sht_measurement_mean_sample_count(data,legacyCount);
outputSensors = routeContract.directOutputSensors;
outputPositions = zeros(size(outputSensors));
for i = 1:numel(outputSensors)
    outputPositions(i) = find(strcmp(residualOrder, outputSensors{i}), 1);
end
sensorCfg = sht_measurement_bias_generator('channelConfig', outputSensors);
if local_contract_mode(contract)==0
    sensorCfg=sht_tc24_uq_measurement('sensors',outputSensors);
end
if any(~sensorCfg.supported)
    error('SHT:SteadyUQ:UnsupportedOutputSensor', ...
        '输出测量误差传播包含未配置传感器：%s。', ...
        strjoin(outputSensors(~sensorCfg.supported), ', '));
end
flowModel = sht_measurement_bias_generator('model');
if local_contract_mode(contract)==0
    flowModel=sht_tc24_uq_measurement('model',[]);
end
flow = local_estimated_inlet_flow(data);
flowFactor = min(max((flowModel.designFlow_kgps - flow) ./ ...
    (flowModel.designFlow_kgps - flowModel.idleFlow_kgps), 0), 1);
for c = 1:numel(outputSensors)
    idx = outputPositions(c):nResidual:nObs;
    commonVector = zeros(nObs, 1);
    commonHalfWidth = max(sensorCfg.totalBiasHalfWidth(c)- ...
        sensorCfg.maxFlowDrift(c),0);
    commonVector(idx) = commonHalfWidth / sqrt(3);
    Routput = Routput + commonVector * commonVector.';
    noiseVariance=sensorCfg.noiseStd(c)^2./meanSampleCount;
    Routput(idx, idx) = Routput(idx, idx) + diag(noiseVariance);
    if sensorCfg.flowDriftEnabled(c)
        driftVector = zeros(nObs, 1);
        driftVector(idx) = sensorCfg.maxFlowDrift(c) / sqrt(3) * flowFactor;
        Routput = Routput + driftVector * driftVector.';
    end
end

Rstationarity = zeros(nObs);
npDerivativePosition = find(strcmp(residualOrder, 'dNp_dt'), 1);
ngDerivativePosition = find(strcmp(residualOrder, 'dNg_dt'), 1);
if ~isempty(npDerivativePosition)
    idx = npDerivativePosition:nResidual:nObs;
    Rstationarity(idx, idx) = eye(nPoint) * 5^2;
end
if ~isempty(ngDerivativePosition)
    idx = ngDerivativePosition:nResidual:nObs;
    Rstationarity(idx, idx) = eye(nPoint) * 15^2;
end

reference = flowModel.specification.designReference;
referenceName = string(flowModel.specification.name);
modelStd = zeros(numel(outputSensors), 1);
for c = 1:numel(outputSensors)
    sensorName = outputSensors{c};
    lookupName = sensorName;
    if strcmp(lookupName, 'Tt45') && local_contract_mode(contract)~=0, lookupName = 'T45'; end
    referenceIndex = referenceName == string(lookupName);
    if nnz(referenceIndex) ~= 1
        error('SHT:SteadyUQ:MissingModelReference', ...
            '输出%s没有唯一的设计参考值。', sensorName);
    end
    if strcmp(sensorName, 'Tt45')
        fraction = 0.0015;
    else
        fraction = 0.0010;
    end
    modelStd(c) = fraction * reference(referenceIndex);
end
trend = linspace(-1, 1, nPoint).';
trendDegenerate=false;
if local_contract_mode(contract)==0
    % 固定工程换算转速坐标，不依赖Excel行序，也不随采样候选改变。
    referenceData=contract.trainingData;
    coordinate=double(data.Ng_mean)./sqrt(double(data.Tt1_mean));
    referenceCoordinate=double(referenceData.Ng_mean)./sqrt(double(referenceData.Tt1_mean));
    span=max(referenceCoordinate)-min(referenceCoordinate);
    trendDegenerate=span<=1e-10*max(1,max(abs(referenceCoordinate)));
    if trendDegenerate,trend=zeros(nPoint,1);
    else,trend=2*(coordinate-min(referenceCoordinate))/span-1;end
end
Rmodel = zeros(nObs);
for c = 1:numel(outputSensors)
    idx = outputPositions(c):nResidual:nObs;
    constantBasis = zeros(nObs, 1);
    trendBasis = zeros(nObs, 1);
    constantBasis(idx) = 0.70 * modelStd(c);
    trendBasis(idx) = 0.50 * modelStd(c) * trend;
    Rmodel = Rmodel + constantBasis * constantBasis.' + ...
        trendBasis * trendBasis.';
    Rmodel(idx, idx) = Rmodel(idx, idx) + ...
        eye(nPoint) * (0.50 * modelStd(c))^2*(1+double(trendDegenerate));
end
Rmodel = contract.config.modelDiscrepancyScale^2*Rmodel;
modelStd = contract.config.modelDiscrepancyScale*modelStd;

Rbase = Routput + inputResult.covariance + Rstationarity;
scenario = struct();
scenario.measurement_only = local_factor_covariance(Rbase, 'measurement_only');
scenario.model_half = local_factor_covariance( ...
    Rbase + 0.25 * Rmodel, 'model_half');
scenario.engineering = local_factor_covariance( ...
    Rbase + Rmodel, 'engineering');
scenario.model_double = local_factor_covariance( ...
    Rbase + 4 * Rmodel, 'model_double');
if ~isfield(scenario, contract.config.covarianceScenario)
    error('SHT:SteadyUQ:BadCovarianceScenario', ...
        '未知协方差情景：%s。', contract.config.covarianceScenario);
end
result = struct('outputCovariance', Routput, ...
    'inputCovariance', inputResult.covariance, ...
    'stationarityCovariance', Rstationarity, ...
    'modelDiscrepancyCovariance', Rmodel, 'scenario', scenario, ...
    'selectedName', contract.config.covarianceScenario, ...
    'selected', scenario.(contract.config.covarianceScenario), ...
    'modelStd', modelStd, 'flowFactor', flowFactor, ...
    'meanSampleCount',meanSampleCount, ...
    'route', evaluationRoute, 'residualOrder', {residualOrder}, ...
    'directOutputSensors', {outputSensors}, ...
    'stateInputSensors', {routeContract.stateInputSensors}, ...
    'inputOutputSensorOverlap', ...
        {intersect(routeContract.stateInputSensors, outputSensors)}, ...
    'roleContractVersion', routeContract.schemaVersion, ...
    'assumption', [sprintf('公共偏置采用对称区间等方差高斯化；各工况按实际%d～%d条记录计算均值白噪声；',min(meanSampleCount),max(meanSampleCount)) ...
        '输入通道流量漂移不传播；模型差异尺度在推断前冻结，未使用训练残差或隐藏真值反调。']);
end

function factor = local_factor_covariance(R, name)
R = 0.5 * (R + R.');
base = max(mean(diag(R)), eps);
jitter = 0;
for k = 1:10
    [L, flag] = chol(R + jitter * eye(size(R)), 'lower');
    if flag == 0
        factor = struct('name', name, 'covariance', R + jitter * eye(size(R)), ...
            'cholLower', L, 'jitter', jitter, ...
            'logDeterminant', 2 * sum(log(diag(L))));
        return;
    end
    if jitter == 0
        jitter = 1e-12 * base;
    else
        jitter = 10 * jitter;
    end
end
error('SHT:SteadyUQ:CovarianceNotPositiveDefinite', ...
    '协方差%s经有限jitter后仍非正定。', name);
end

function [variant, meta] = local_add_data_derivative_pair( ...
        variant, meta, data, field, point, delta, kind, channel)
plus = data;
minus = data;
if point == 0
    plus.(field) = plus.(field) + delta;
    minus.(field) = minus.(field) - delta;
else
    plus.(field)(point) = plus.(field)(point) + delta;
    minus.(field)(point) = minus.(field)(point) - delta;
end
variant{end + 1} = plus;
variant{end + 1} = minus;
record = struct('kind', kind, 'channel', channel, 'point', point, 'delta', delta);
meta(end + 1) = record;
meta(end + 1) = record;
end

function flow = local_estimated_inlet_flow(data)
if ismember('Wa2_mean',data.Properties.VariableNames)
    flow=data.Wa2_mean;return;
end
% 输入Excel没有入口流量；用已冻结的设计/慢车锚点按燃油流量归一化插值，
% 仅用于流量相关偏置基，不参与发动机回放。
model = sht_measurement_bias_generator('model');
wfDesign = model.specification.designReference( ...
    strcmp(model.specification.name, 'Wf'));
ratio = min(max(data.Wf_mean / wfDesign, 0), 1);
flow = model.idleFlow_kgps + ratio .* ...
    (model.designFlow_kgps - model.idleFlow_kgps);
end

function [thetaHat, tbl] = local_node_parameter_table(result)
% 将阶段D最终调度在DLL实际执行节点上展开。每条调度曲线保留其原始
% 有效节点数，不再把近邻节点重新采样为固定6点。
parameters = result.parameterDefinition;
schedule = result.finalSchedule;

index = zeros(0, 1);
name = strings(0, 1);
baseName = strings(0, 1);
cIndex = zeros(0, 1);
unit = strings(0, 1);
groupIndex = zeros(0, 1);
groupKind = strings(0, 1);
scheduleEntryIndex = zeros(0, 1);
dllNodeIndex = zeros(0, 1);
nodeIndex = zeros(0, 1);
coordinate = zeros(0, 1);
normalizedCoordinate = zeros(0, 1);
pointEstimate = zeros(0, 1);
lowerBound = zeros(0, 1);
upperBound = zeros(0, 1);
priorSigma = zeros(0, 1);
differenceStep = zeros(0, 1);
axisName = strings(0, 1);
pressureLoss = false(0, 1);

counter = 0;
group = 0;
for p = 1:height(parameters)
    if ~parameters.scheduled(p)
        continue;
    end
    entryIndex = find([schedule.healthEntries.cIndex] == ...
        parameters.c_index(p), 1);
    if isempty(entryIndex)
        error('SHT:SteadyUQ:ScheduleEntryMissing', ...
            '阶段D调度缺少%s。', parameters.name(p));
    end
    entry = schedule.healthEntries(entryIndex);
    active = (1:numel(entry.xNodesDll)).';
    if entry.pressureLoss
        if entry.xNodesDll(1) ~= 0 || entry.kNodesDll(1) ~= 0
            error('SHT:SteadyUQ:PressureLossAnchorMismatch', ...
                '%s的零流量锚点不是(0,0)。', entry.name);
        end
        active = active(2:end);
    end
    if isempty(active)
        error('SHT:SteadyUQ:UnexpectedDllNodeCount', ...
            '%s只有%d个活动DLL节点，至少需要1个。', ...
            entry.name, numel(active));
    end
    group = group + 1;
    for q = 1:numel(active)
        counter = counter + 1;
        j = active(q);
        index(counter, 1) = counter;
        name(counter, 1) = sprintf('%s_node%02d', char(parameters.name(p)), q);
        baseName(counter, 1) = string(parameters.name(p));
        cIndex(counter, 1) = parameters.c_index(p);
        unit(counter, 1) = "1";
        groupIndex(counter, 1) = group;
        groupKind(counter, 1) = "health_schedule";
        scheduleEntryIndex(counter, 1) = entryIndex;
        dllNodeIndex(counter, 1) = j;
        nodeIndex(counter, 1) = q;
        coordinate(counter, 1) = entry.xNodesDll(j);
        pointEstimate(counter, 1) = entry.kNodesDll(j);
        lowerBound(counter, 1) = parameters.lower_bound(p);
        upperBound(counter, 1) = parameters.upper_bound(p);
        priorSigma(counter, 1) = parameters.prior_sigma_global(p);
        differenceStep(counter, 1) = parameters.difference_step(p);
        axisName(counter, 1) = string(entry.axisName);
        pressureLoss(counter, 1) = entry.pressureLoss;
    end
end

fuel = schedule.fuelBias;
fuelNodeCount = numel(fuel.xNodes);
if fuelNodeCount < 1 || numel(fuel.biasNodes) ~= fuelNodeCount
    error('SHT:SteadyUQ:UnexpectedFuelNodeCount', ...
        '阶段D燃油偏置调度至少需要1个坐标和值一一对应的节点。');
end
group = group + 1;
fuelLimit = 0.02 * fuel.wfDesign;
for q = 1:fuelNodeCount
    counter = counter + 1;
    index(counter, 1) = counter;
    name(counter, 1) = sprintf('Wf_bias_node%02d', q);
    baseName(counter, 1) = "Wf_bias";
    cIndex(counter, 1) = -1;
    unit(counter, 1) = "kg/s";
    groupIndex(counter, 1) = group;
    groupKind(counter, 1) = "fuel_bias";
    scheduleEntryIndex(counter, 1) = 0;
    dllNodeIndex(counter, 1) = q;
    nodeIndex(counter, 1) = q;
    coordinate(counter, 1) = fuel.xNodes(q);
    pointEstimate(counter, 1) = fuel.biasNodes(q);
    lowerBound(counter, 1) = -fuelLimit;
    upperBound(counter, 1) = fuelLimit;
    priorSigma(counter, 1) = 0.003 * fuel.wfDesign;
    differenceStep(counter, 1) = max(1e-6, 5e-5 * fuel.wfDesign);
    axisName(counter, 1) = "measured_wf_ratio";
    pressureLoss(counter, 1) = false;
end

nozzleRow = find(parameters.c_index == 15, 1);
if isempty(nozzleRow)
    error('SHT:SteadyUQ:NozzleParameterMissing', ...
        '参数定义缺少Nozzle_K_A8。');
end
group = group + 1;
counter = counter + 1;
index(counter, 1) = counter;
name(counter, 1) = "Nozzle_K_A8";
baseName(counter, 1) = "Nozzle_K_A8";
cIndex(counter, 1) = 15;
unit(counter, 1) = "1";
groupIndex(counter, 1) = group;
groupKind(counter, 1) = "constant";
scheduleEntryIndex(counter, 1) = 0;
dllNodeIndex(counter, 1) = 0;
nodeIndex(counter, 1) = 1;
coordinate(counter, 1) = 0;
pointEstimate(counter, 1) = schedule.h15;
lowerBound(counter, 1) = parameters.lower_bound(nozzleRow);
upperBound(counter, 1) = parameters.upper_bound(nozzleRow);
priorSigma(counter, 1) = parameters.prior_sigma_global(nozzleRow);
differenceStep(counter, 1) = parameters.difference_step(nozzleRow);
axisName(counter, 1) = "constant";
pressureLoss(counter, 1) = false;

for g = 1:group
    use = groupIndex == g;
    x = coordinate(use);
    if numel(x) == 1 || max(x) == min(x)
        normalizedCoordinate(use) = 0;
    else
        normalizedCoordinate(use) = (x - min(x)) / (max(x) - min(x));
    end
end

tbl = table(index, name, baseName, cIndex, unit, groupIndex, groupKind, ...
    scheduleEntryIndex, dllNodeIndex, nodeIndex, coordinate, ...
    normalizedCoordinate, pointEstimate, lowerBound, upperBound, ...
    priorSigma, differenceStep, axisName, pressureLoss, ...
    'VariableNames', {'index','name','base_name','c_index','unit', ...
    'group_index','group_kind','schedule_entry_index','dll_node_index', ...
    'node_index','coordinate','normalized_coordinate','point_estimate', ...
    'lower_bound','upper_bound','prior_sigma','difference_step', ...
    'axis_name','pressure_loss'});
thetaHat = pointEstimate;
expectedGroupCount = nnz(parameters.scheduled) + 2;
if group ~= expectedGroupCount || height(tbl) <= group
    error('SHT:SteadyUQ:NodeContractDimension', ...
        ['节点合同得到%d个参数、%d组，预期%d组且至少有一个调度组' ...
         '包含多个节点。'], height(tbl), group, expectedGroupCount);
end
end

function [R, groupTable] = local_prior_correlation(tbl, cfg)
% 同一调度函数节点采用平滑相关先验，不同函数先验块保持独立。
d = height(tbl);
R = zeros(d);
groups = unique(tbl.group_index, 'stable');
groupIndex = zeros(numel(groups), 1);
name = strings(numel(groups), 1);
kind = strings(numel(groups), 1);
firstParameter = zeros(numel(groups), 1);
lastParameter = zeros(numel(groups), 1);
nodeCount = zeros(numel(groups), 1);
omegaValue = zeros(numel(groups), 1);
lengthValue = zeros(numel(groups), 1);
independentFraction = zeros(numel(groups),1);
for k = 1:numel(groups)
    g = groups(k);
    idx = find(tbl.group_index == g);
    n = numel(idx);
    if tbl.group_kind(idx(1)) == "fuel_bias"
        omega = cfg.fuelPriorCommonCorrelation;
        ell = cfg.fuelPriorCorrelationLength;
        eta = cfg.fuelPriorIndependentFraction;
    elseif n > 1
        omega = cfg.nodePriorCommonCorrelation;
        ell = cfg.nodePriorCorrelationLength;
        eta = cfg.nodePriorIndependentFraction;
    else
        omega = 0;
        ell = 1;
        eta = 0;
    end
    if n == 1
        block = 1;
    else
        z = tbl.normalized_coordinate(idx);
        distance = z - z.';
        smoothBlock = omega * ones(n) + (1 - omega) * ...
            exp(-0.5 * (distance / ell).^2);
        block = (1-eta)*smoothBlock+eta*eye(n);
        block = 0.5 * (block + block.');
        [~, flag] = chol(block);
        if flag ~= 0
            block = block + 1e-10 * eye(n);
            scale = sqrt(diag(block));
            block = block ./ (scale * scale.');
        end
    end
    R(idx, idx) = block;
    groupIndex(k) = g;
    name(k) = tbl.base_name(idx(1));
    kind(k) = tbl.group_kind(idx(1));
    firstParameter(k) = idx(1);
    lastParameter(k) = idx(end);
    nodeCount(k) = n;
    omegaValue(k) = omega;
    lengthValue(k) = ell;
    independentFraction(k) = eta;
end
[~, flag] = chol(R);
if flag ~= 0
    error('SHT:SteadyUQ:PriorCorrelationNotPositiveDefinite', ...
        '节点相关先验矩阵不是正定矩阵。');
end
groupTable = table(groupIndex, name, kind, firstParameter, lastParameter, ...
    nodeCount, omegaValue, lengthValue, independentFraction, ...
    'VariableNames', {'group_index','name','kind','first_parameter', ...
    'last_parameter','node_count','omega','correlation_length', ...
    'independent_fraction'});
end

function schedule = local_vector_to_schedule(contract, theta)
theta = theta(:);
if numel(theta) ~= contract.parameterCount || any(~isfinite(theta))
    error('SHT:SteadyUQ:BadScheduleVector', ...
        '调度节点向量必须为%d维有限向量。', contract.parameterCount);
end
if any(theta < contract.lowerBound) || any(theta > contract.upperBound)
    error('SHT:SteadyUQ:ScheduleVectorOutsideBounds', ...
        '调度节点向量超出硬边界。');
end
schedule = contract.scheduleTemplate;
tbl = contract.parameterTable;
groupIds = unique(tbl.group_index, 'stable');
for g = groupIds(:).'
    rows = find(tbl.group_index == g);
    kind = tbl.group_kind(rows(1));
    switch char(kind)
        case 'health_schedule'
            cIndex = tbl.c_index(rows(1));
            entryIndex = find([schedule.healthEntries.cIndex] == cIndex, 1);
            if isempty(entryIndex)
                error('SHT:SteadyUQ:TemplateScheduleEntryMissing', ...
                    '模板调度缺少h%d。', cIndex);
            end
            entry = schedule.healthEntries(entryIndex);
            xActive = tbl.coordinate(rows);
            kActive = theta(rows);
            if entry.pressureLoss
                entry.xNodes = [0; xActive(:)];
                entry.kNodes = [0; kActive(:)];
            else
                entry.xNodes = xActive(:);
                entry.kNodes = kActive(:);
            end
            entry.xNodesDll = entry.xNodes;
            entry.kNodesDll = entry.kNodes;
            entry.designValue = local_interp_clamp( ...
                entry.xNodesDll, entry.kNodesDll, entry.designCoordinate);
            entry.deltaNodesDll = entry.kNodesDll - entry.designValue;
            if entry.pressureLoss
                entry.kNodesDll(1) = 0;
                entry.deltaNodesDll(1) = -entry.designValue;
            end
            entry.dllResamplingUsed = false;
            schedule.healthEntries(entryIndex) = entry;
        case 'fuel_bias'
            schedule.fuelBias.xNodes = tbl.coordinate(rows);
            schedule.fuelBias.biasNodes = theta(rows);
        case 'constant'
            schedule.h15 = theta(rows(1));
        otherwise
            error('SHT:SteadyUQ:UnknownParameterGroupKind', ...
                '未知节点组类型%s。', kind);
    end
end
schedule.designHealth = local_schedule_design_health(schedule);
end

function theta = local_schedule_to_vector(contract, schedule)
if ~isstruct(schedule) || ~isfield(schedule, 'healthEntries') || ...
        ~isfield(schedule, 'fuelBias') || ~isfield(schedule, 'h15')
    error('SHT:SteadyUQ:BadScheduleForVector', ...
        '输入不是完整调度结构。');
end
tbl = contract.parameterTable;
theta = nan(contract.parameterCount, 1);
for i = 1:contract.parameterCount
    switch char(tbl.group_kind(i))
        case 'health_schedule'
            entryIndex = find([schedule.healthEntries.cIndex] == ...
                tbl.c_index(i), 1);
            if isempty(entryIndex)
                error('SHT:SteadyUQ:ScheduleEntryMissingForVector', ...
                    '输入调度缺少h%d。', tbl.c_index(i));
            end
            entry = schedule.healthEntries(entryIndex);
            theta(i) = entry.kNodesDll(tbl.dll_node_index(i));
        case 'fuel_bias'
            theta(i) = schedule.fuelBias.biasNodes(tbl.dll_node_index(i));
        case 'constant'
            theta(i) = schedule.h15;
    end
end
if any(~isfinite(theta))
    error('SHT:SteadyUQ:NonfiniteScheduleVector', ...
        '从调度结构提取的节点向量存在非有限值。');
end
end

function health = local_schedule_design_health(schedule)
health = zeros(159, 1);
for i = 1:numel(schedule.healthEntries)
    entry = schedule.healthEntries(i);
    health(entry.cIndex + 1) = entry.designValue;
end
health(16) = schedule.h15;
end

function artifacts = local_engine_artifacts(engineCfg)
artifacts = sht_engine_artifact_identity(engineCfg);
end

function record = local_runtime_code_hash()
root = fileparts(mfilename('fullpath'));
name = {'sht_steady_model_uq_common.m'; ...
    'sht_tc24_uq_external_io.m'; ...
    'sht_tc24_absolute_path.m'; ...
    'sht_measurement_mean_sample_count.m'; ...
    'sht_engine_artifact_identity.m'; ...
    'sht_uq_physical_blocks.m'; ...
    'sht_steady_model_uq_io.m'; ...
    'sht_load_2p4_deterministic_delivery.m'; ...
    'sht_steady_model_adapt_v2_common.m'; ...
    'sht_steady_np_branch_prior.m'; ...
    'sht_solve_steady_np_branch.m'; ...
    'sht_measurement_bias_generator.m'; ...
    'sht_default_config.m'; ...
    'sht_engine_open.m'; ...
    'sht_engine_close.m'; ...
    'sht_engine_derivative.m'; ...
    'sht_apply_inlet_boundary_stepin.m'; ...
    'sht_solve_steady_components_from_seed.m'; ...
    'sht_get_steady_trim_initial_guess.m'};
record = strings(numel(name),1);
for i = 1:numel(name)
    file = fullfile(root,name{i});
    if exist(file,'file') ~= 2
        error('SHT:SteadyUQ:RuntimeCodeMissing', ...
            '合同哈希所需运行代码不存在：%s。',file);
    end
    record(i) = string(name{i})+":"+string(local_file_hash(file));
end
end

function fingerprint = local_flight_uq_fingerprint()
root = fileparts(mfilename('fullpath'));
listing = [dir(fullfile(root, 'Start_FlightModelUQ*.m')); ...
    dir(fullfile(root, 'sht_flight_uq*.m'))];
[~, order] = sort({listing.name});
listing = listing(order);
record = strings(numel(listing), 1);
for i = 1:numel(listing)
    file = fullfile(root, listing(i).name);
    record(i) = string(listing(i).name) + ":" + string(local_file_hash(file));
end
fingerprint = struct('fileCount', numel(listing), 'records', record, ...
    'aggregateHash', local_text_hash(strjoin(cellstr(record), '|')));
end

function hash = local_file_hash(file)
% exist对MDL/SLX返回4；按文件存在性检查，不把模型文件误判为缺失。
if ~isfile(file)
    error('SHT:SteadyUQ:HashFileMissing', '哈希文件不存在：%s。', file);
end
fileId = fopen(file, 'r');
if fileId < 0
    error('SHT:SteadyUQ:HashReadFailed', '无法读取文件并计算SHA-256：%s。', file);
end
cleanupObject = onCleanup(@() fclose(fileId));
md = java.security.MessageDigest.getInstance('SHA-256');
while true
    % MATLAB R2020a不会把Java FileInputStream.read写回MATLAB数值数组；
    % 那种写法实际会按同长度全零数据计算哈希。统一使用项目内已验证的
    % fread字节流模式，确保合同冻结的是文件内容而不是文件长度。
    value = fread(fileId, 1024 * 1024, '*uint8');
    if isempty(value), break; end
    md.update(typecast(value(:), 'int8'));
end
clear cleanupObject;
digest = typecast(int8(md.digest()), 'uint8');
hash = lower(reshape(dec2hex(digest, 2).', 1, []));
end

function hash = local_text_hash(text)
md = java.security.MessageDigest.getInstance('SHA-256');
bytes = unicode2native(char(text), 'UTF-8');
% 独立交付包不包含飞参UQ程序时，待汇总记录允许为空。R2020a 对
% MessageDigest.update([]) 的Java重载解析不稳定，因此空文本直接计算
% SHA-256；非空文本统一转为列向量，避免行列形状触发不同重载。
if ~isempty(bytes)
    md.update(typecast(uint8(bytes(:)), 'int8'));
end
digest = typecast(int8(md.digest()), 'uint8');
hash = lower(reshape(dec2hex(digest, 2).', 1, []));
end

function data = local_read_input_table(file, label)
candidate=sht_steady_model_adapt_v2_common('readmeasurementtable',file,label);
if ismember('Ptb3_mean',candidate.Properties.VariableNames)
    data=candidate;return;
end
if exist(file, 'file') ~= 2
    error('SHT:SteadyUQ:InputFileMissing', '%s文件不存在：%s。', label, file);
end
try
    data = readtable(file, 'FileType', 'spreadsheet', 'TextType', 'string');
catch
    data = readtable(file, 'FileType', 'spreadsheet');
end
required = {'point_id','Np_mean','Ng_mean','Wf_mean','Tt45_mean', ...
    'Pt45_mean','Mkp_mean','Mkg_mean','Pt2_mean','Tt1_mean', ...
    'Pt3_mean','Tt3_mean','Pamb_mean','Tamb_mean','Altitude_mean','Mach_mean'};
missing = setdiff(required, data.Properties.VariableNames);
if ~isempty(missing)
    error('SHT:SteadyUQ:BadInputSchema', '%s缺少字段：%s。', ...
        label, strjoin(missing, ', '));
end
data.point_id = string(data.point_id);
if numel(unique(data.point_id)) ~= height(data)
    error('SHT:SteadyUQ:DuplicatePointId', '%s工况编号重复。', label);
end
end

function role = local_route_contract(route,modelMode)
if nargin>=2 && modelMode==0
    role=sht_tc24_uq_measurement('role',route);return;
end
% 显式冻结两条2.4路线中“物理输入、直接测量输出和派生约束”的角色。
% 数值求解初值或稳态Np选根参考不属于物理输入，严禁据此重复传播误差。
route = char(route);
commonInput = struct( ...
    'field', {'Wf_mean','Mkp_mean','Mkg_mean','Pt2_mean','Tt1_mean', ...
        'Pamb_mean','Tamb_mean'}, ...
    'sensor', {'Wf','Mkp','Mkg','Pt2','Tt1','Pamb','Tamb'});
switch route
    case 'steady'
        residualOrder = {'Np','Ng','Pt3','Tt3','Tt45','Pt45'};
        directOutputSensors = residualOrder;
        stateInputSensors = {};
        propagatedInputDefinition = commonInput;
        derivedConstraintOutputs = {};
    case 'transient_instant'
        residualOrder = {'Pt3','Tt3','Tt45','Pt45','dNp_dt','dNg_dt'};
        directOutputSensors = {'Pt3','Tt3','Tt45','Pt45'};
        stateInputSensors = {'Np','Ng'};
        stateInput = struct('field', {'Np_mean','Ng_mean'}, ...
            'sensor', {'Np','Ng'});
        propagatedInputDefinition = [stateInput, commonInput];
        derivedConstraintOutputs = {'dNp_dt','dNg_dt'};
    otherwise
        error('SHT:SteadyUQ:BadRoute', ...
            '路线必须为steady或transient_instant。');
end
if ~isempty(intersect(stateInputSensors, directOutputSensors))
    error('SHT:SteadyUQ:InputOutputRoleOverlap', ...
        '同一路线中状态输入和直接测量输出不得重复计入。');
end
role = struct('schemaVersion','SHT_2P4_UQ_MEASUREMENT_ROLE_V1', ...
    'route',route,'residualOrder',{residualOrder}, ...
    'stateInputSensors',{stateInputSensors}, ...
    'directOutputSensors',{directOutputSensors}, ...
    'derivedConstraintOutputs',{derivedConstraintOutputs}, ...
    'propagatedInputDefinition',{propagatedInputDefinition}, ...
    'outputPredictionRoute','steady', ...
    'inputFlowDriftPropagated',false, ...
    'npNgNumericalSeedIsPhysicalInput',strcmp(route,'transient_instant'));
end

function names = local_residual_names(route)
names = local_route_contract(route).residualOrder;
end

function value = local_observed_value(data, row, name)
if ismember(name,{'Ptb3','Ttb3','Pt6','Tt6','Wa2'})
    value=data.([name,'_mean'])(row);return;
end
switch name
    case 'Np', value = data.Np_mean(row);
    case 'Ng', value = data.Ng_mean(row);
    case 'Pt3', value = data.Pt3_mean(row);
    case 'Tt3', value = data.Tt3_mean(row);
    case 'Tt45', value = data.Tt45_mean(row);
    case 'Pt45', value = data.Pt45_mean(row);
    case {'dNp_dt','dNg_dt'}, value = 0;
    otherwise, error('SHT:SteadyUQ:BadResidualName', '未知残差%s。', name);
end
end

function unit = local_residual_unit(name)
switch name
    case {'Np','Ng'}, unit = 'rpm';
    case {'Pt3','Ptb3','Pt45','Pt6'}, unit = 'Pa';
    case {'Tt3','Ttb3','Tt45','Tt6'}, unit = 'K';
    case 'Wa2',unit='kg/s';
    case {'dNp_dt','dNg_dt'}, unit = 'rpm/s';
    otherwise, unit = '-';
end
end

function cache = local_empty_cache(contract, dimension, evaluationRoute)
if nargin < 3 || isempty(evaluationRoute)
    evaluationRoute = contract.route;
end
cache = struct('schemaVersion', ...
    'steady_uq_exact_cache_v4_route_explicit', ...
    'contractHash', contract.contractHash, 'residualDimension', dimension, ...
    'evaluationRoute', char(evaluationRoute), ...
    'keys', {{}}, 'theta', zeros(contract.parameterCount, 0), ...
    'residual', zeros(dimension, 0), 'valid', false(1, 0), ...
    'evaluationCount', 0, 'updatedAt', '');
end

function key = local_theta_key(theta)
key = sprintf('%.17g,', theta);
end

function value = local_interp_clamp(x, y, query)
x = x(:); y = y(:);
if numel(x)==1,value=repmat(y,size(query));return;end
query = min(max(query, min(x)), max(x));
value = interp1(x, y, query, 'linear');
end

function value = local_option(options, name, defaultValue)
if isstruct(options) && isfield(options, name) && ~isempty(options.(name))
    value = options.(name);
else
    value = defaultValue;
end
end

function mode=local_contract_mode(contract)
mode=1;
if isfield(contract,'modelMode'),mode=contract.modelMode;
elseif isfield(contract,'config') && isfield(contract.config,'modelMode'),mode=contract.config.modelMode;
end
end

function model=local_replay_model(contract)
% 新TC24合同直接携带由Excel恢复的最小模型，旧六部件保留历史入口。
if isfield(contract,'replayModel')
    model=contract.replayModel;
else
    loaded=load(contract.deterministicResultFile,'result');model=loaded.result;
end
end

function identity=local_evaluation_identity(contract,data,options,route)
% 缓存包括全部实际数据与影响物理解的配置，不再只比较点数和theta。
model=local_replay_model(contract);
root=fileparts(mfilename('fullpath'));
replayCodeIdentity={local_file_hash([mfilename('fullpath'),'.m']), ...
    local_file_hash(fullfile(root,'sht_steady_model_uq_b_common.m')), ...
    local_file_hash(fullfile(root,'sht_steady_model_adapt_v2_common.m')), ...
    local_file_hash(fullfile(root,'sht_uq_steady_root_continuation.m')), ...
    local_file_hash(fullfile(root,'sht_solve_steady_np_branch.m')), ...
    local_file_hash(fullfile(root,'sht_solve_steady_components_from_seed.m')), ...
    local_file_hash(fullfile(root,'sht_np_branch_delivery.m'))};
ignored={'cacheFile','useCache','returnPredictions','returnDiagnostics'};
for i=1:numel(ignored)
    if isfield(options,ignored{i}),options=rmfield(options,ignored{i});end
end
payload=struct('contract',contract.contractHash,'route',route, ...
    'data',table2struct(data),'options',options,'modelOptions',model.options);
payload.replayCodeIdentity=replayCodeIdentity;
identity=local_text_hash(jsonencode(payload));
end
