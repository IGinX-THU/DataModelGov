function varargout = sht_steady_model_uq_b_common(action, varargin)
%SHT_STEADY_MODEL_UQ_B_COMMON 2.4稳态UQ方法B公共内核。
%
% 方法B在方法A的可变节点总体参数合同上，独立增加12个六部件局部常值和
% 20个物理引气常值（10路流量与10路总温）。K_PRec在当前C程序中不
% 参与计算，因此不进入概率参数空间。方法B不读取方法A后验；两者只共享训练数据、
% 测量误差合同、DLL回放接口和总体调度节点坐标。

switch lower(char(action))
    case 'defaultconfig'
        varargout{1} = local_default_config(varargin{:});
    case 'buildcontract'
        varargout{1} = local_build_contract(varargin{:});
    case 'samplinggeometry'
        varargout{1} = local_sampling_geometry(varargin{:});
    case 'loaddata'
        varargout{1} = local_load_data(varargin{:});
    case 'observation'
        [varargout{1:nargout}] = sht_steady_model_uq_common( ...
            'observation', varargin{:});
    case 'predictionvector'
        [varargout{1:nargout}] = sht_steady_model_uq_common( ...
            'predictionvector', varargin{:});
    case 'evaluate'
        varargout{1} = local_evaluate(varargin{:});
    case 'vectortoschedule'
        varargout{1} = local_vector_to_schedule(varargin{:});
    case 'scheduletovector'
        varargout{1} = local_schedule_to_vector(varargin{:});
    case 'routecontract'
        varargout{1} = sht_steady_model_uq_common( ...
            'routecontract', varargin{:});
    case 'inputcovariance'
        varargout{1} = local_input_covariance(varargin{:});
    case 'measurementcovariance'
        varargout{1} = sht_steady_model_uq_common( ...
            'measurementcovariance', varargin{:});
    case 'filehash'
        varargout{1} = sht_steady_model_uq_common('filehash', varargin{:});
    case 'flightuqfingerprint'
        varargout{1} = sht_steady_model_uq_common( ...
            'flightuqfingerprint', varargin{:});
    otherwise
        error('SHT:SteadyUQB:UnknownAction', ...
            '未知方法B公共动作：%s。', action);
end
end

function cfg = local_default_config(userCfg)
if nargin < 1 || isempty(userCfg), userCfg = struct(); end
cfg = sht_steady_model_uq_common('defaultconfig', userCfg);
% 通用配置只识别D运行标识；B还须保留显式目录及步骤SHA，避免重建配置后
% 误走旧目录。此处仅原样转发，完整性和身份仍由D辅助读取函数统一校核。
dProposalFields = {'dProposalOutputDirectory','dProposalStepSHA256', ...
    'dProposalMode','dProposalMaxIterations'};
for k = 1:numel(dProposalFields)
    name = dProposalFields{k};
    if isfield(userCfg, name), cfg.(name) = userCfg.(name); end
end
cfg.randomSeed = local_option(userCfg, 'randomSeed', 20260822);
cfg.pilotSampleCount = local_option(userCfg, 'pilotSampleCount', 64);
cfg.pilotReplicateCount = local_option(userCfg, 'pilotReplicateCount', 3);
% 方法B只开放512和1024两档正式粒子数。particleCount是面向用户的统一
% 配置入口；formalSampleCount保留为旧程序兼容字段。正式粒子和后验预测
% 样本必须使用同一规模，避免合同记录与实际传播规模不一致。
cfg.particleCount = local_particle_count(userCfg);
cfg.formalSampleCount = cfg.particleCount;
% 正式SMC初始粒子中，局部似然引导提议所占的目标比例。其余粒子
% 直接来自原始先验；两类粒子统一通过p/q重要性权重恢复目标先验。
cfg.proposalLocalFraction = local_option( ...
    userCfg, 'proposalLocalFraction', 0.45);
cfg.proposalInformedScaleInflation=local_option(userCfg,'proposalInformedScaleInflation',.75);
validateattributes(cfg.proposalInformedScaleInflation,{'numeric'},{'scalar','finite','positive'});
cfg.posteriorPredictiveSampleCount = cfg.particleCount;
cfg.minimumEffectiveSampleSize = local_option( ...
    userCfg, 'minimumEffectiveSampleSize', 64);
cfg.minimumEffectiveSampleFraction = local_option( ...
    userCfg, 'minimumEffectiveSampleFraction', 0.30);
cfg.maximumNormalizedWeight = local_option( ...
    userCfg, 'maximumNormalizedWeight', 0.08);
cfg.smcPilotTargetEssFraction = local_option( ...
    userCfg, 'smcPilotTargetEssFraction', 0.55);
cfg.smcFormalTargetEssFraction = local_option( ...
    userCfg, 'smcFormalTargetEssFraction', 0.50);
cfg.methodARunId = char(local_option(userCfg, 'methodARunId', ''));
cfg.pilotMoveSweeps = local_option(userCfg, 'pilotMoveSweeps', 1);
cfg.pilotFinalMoveSweeps = local_option( ...
    userCfg, 'pilotFinalMoveSweeps', 2);
cfg.formalMoveSweeps = local_option(userCfg, 'formalMoveSweeps', 1);
cfg.formalFinalMoveSweeps = local_option( ...
    userCfg, 'formalFinalMoveSweeps', 4);
cfg.maximumStageCount = local_option(userCfg, 'maximumStageCount', 70);
cfg.kernelWeights = local_option(userCfg, 'kernelWeights', ...
    local_option(userCfg, 'blockKernelWeights', ...
    [0.23, 0.17, 0.25, 0.10, 0.25]));
cfg.initialPcnScale = local_option(userCfg, 'initialPcnScale', ...
    local_option(userCfg, 'blockInitialPcnScale', ...
    [0.08, 0.05, 0.08, 0.20, 0.035]));
cfg.minimumPcnScale = local_option(userCfg, 'minimumPcnScale', ...
    [0.015, 0.010, 0.015, 0.030, 0.008]);
cfg.maximumPcnScale = local_option(userCfg, 'maximumPcnScale', ...
    [0.25, 0.18, 0.30, 0.50, 0.15]);
cfg.targetAcceptance = local_option(userCfg, 'targetAcceptance', ...
    [0.28, 0.32, 0.25, 0.35, 0.18]);
cfg.blockNullScaleMultiplier = local_option(userCfg, ...
    'blockNullScaleMultiplier', [2.0, 2.0, 2.0, 2.0]);
cfg.maximumBlockNullScale = local_option(userCfg, ...
    'maximumBlockNullScale', [0.55, 0.45, 0.60, 0.75]);
cfg.globalNullScaleMultiplier = local_option(userCfg, ...
    'globalNullScaleMultiplier', 4.0);
cfg.maximumGlobalNullScale = local_option(userCfg, ...
    'maximumGlobalNullScale', 0.55);
cfg.globalPcnFraction = local_option(userCfg, 'globalPcnFraction', 0.80);
cfg.globalNullOnlyFraction=local_option(userCfg,'globalNullOnlyFraction',0);
cfg.globalNullOnlyScale=local_option(userCfg,'globalNullOnlyScale',.35);
% 新几何只改变提议步长，不改变参数先验、边界或精确似然。
cfg.pcnGeometry=char(local_option(userCfg,'pcnGeometry','rank_split'));
cfg.freezeFinalPcnScale=logical(local_option(userCfg,'freezeFinalPcnScale',false));
% profile只影响提议和SMC预算，不进入B的物理先验/似然定义。
cfg.bSamplerProfile=char(local_option(userCfg,'bSamplerProfile','legacy_reference'));
% 可选重算仅影响提议分布；零参考尺度用于受控对照。
cfg.bProposalGeometryMode=char(local_option(userCfg,'bProposalGeometryMode','selected_location'));
assert(ismember(cfg.bProposalGeometryMode,{'selected_location','zero_reference'}), ...
    'TC24:B:ProposalGeometryMode','尺度来源须为selected_location或zero_reference。');
% final复现旧B；configured_start只用于隔离单项对照，不把末端步幅用于起点。
cfg.pilotInitialScaleSource=char(local_option(userCfg,'pilotInitialScaleSource','final'));
assert(ismember(cfg.pilotInitialScaleSource,{'final','configured_start'}), ...
    'TC24:B:PilotScaleSource','pilotInitialScaleSource须为final或configured_start。');
cfg.conditionalEssFraction=local_option(userCfg,'conditionalEssFraction',.8);
cfg.resampleEssFraction=local_option(userCfg,'resampleEssFraction',.55);
cfg.referenceShrinkage=local_option(userCfg,'referenceShrinkage',.15);
cfg.referenceEigenvalueFloor=local_option(userCfg,'referenceEigenvalueFloor',.05);
cfg.finalReferenceMove=local_option(userCfg,'finalReferenceMove',false);
validateattributes(cfg.finalReferenceMove,{'logical','numeric'},{'scalar','finite'});
assert(ismember(cfg.finalReferenceMove,[0 1]),'TC24:B:FinalReferenceFlag', ...
    'finalReferenceMove必须为0或1。');
cfg.finalReferenceMove=logical(cfg.finalReferenceMove);
cfg.bSamplingSeed=local_option(userCfg,'bSamplingSeed',cfg.randomSeed+8001);
assert(ismember(cfg.bSamplerProfile,{'quality','legacy_reference'}),'未知B采样配置。');
validateattributes(cfg.bSamplingSeed,{'numeric'},{'scalar','integer','nonnegative','finite'});
assert(ismember(cfg.pcnGeometry,{'rank_split','spectral'}), ...
    'SHT:SteadyUQB:GeometryMode','pcnGeometry须为rank_split或spectral。');
assert(isscalar(cfg.freezeFinalPcnScale),'freezeFinalPcnScale须为标量。');
validateattributes(cfg.globalNullOnlyFraction,{'numeric'},{'scalar','>=',0,'<',1});
validateattributes(cfg.globalNullOnlyScale,{'numeric'},{'scalar','>',0,'<',1});
if ~isscalar(cfg.proposalLocalFraction) || ...
        ~isnumeric(cfg.proposalLocalFraction) || ...
        ~isfinite(cfg.proposalLocalFraction) || ...
        cfg.proposalLocalFraction <= 0 || cfg.proposalLocalFraction >= 1
    error('SHT:SteadyUQB:BadProposalLocalFraction', ...
        'proposalLocalFraction必须严格位于(0,1)。');
end
cfg.proposalLocalFraction = double(cfg.proposalLocalFraction);
integerName = {'pilotMoveSweeps','pilotFinalMoveSweeps', ...
    'formalMoveSweeps','formalFinalMoveSweeps','maximumStageCount'};
for i = 1:numel(integerName)
    value = cfg.(integerName{i});
    if ~isscalar(value) || ~isfinite(value) || value < 1 || ...
            value ~= floor(value)
        error('SHT:SteadyUQB:BadIntegerConfiguration', ...
            '%s必须为正整数。', integerName{i});
    end
end
fiveName = {'kernelWeights','initialPcnScale','minimumPcnScale', ...
    'maximumPcnScale','targetAcceptance'};
for i = 1:numel(fiveName)
    cfg.(fiveName{i}) = cfg.(fiveName{i})(:).';
    if numel(cfg.(fiveName{i})) ~= 5 || ...
            any(~isfinite(cfg.(fiveName{i})))
        error('SHT:SteadyUQB:BadFiveKernelConfiguration', ...
            '%s必须包含5个有限数。', fiveName{i});
    end
end
if any(cfg.kernelWeights <= 0) || ...
        any(cfg.minimumPcnScale <= 0) || ...
        any(cfg.maximumPcnScale >= 1) || ...
        any(cfg.minimumPcnScale > cfg.initialPcnScale) || ...
        any(cfg.initialPcnScale > cfg.maximumPcnScale)
    error('SHT:SteadyUQB:BadBlockConfiguration', ...
        '五核权重或pCN最小、初始、最大步长配置无效。');
end
if numel(cfg.blockNullScaleMultiplier) ~= 4 || ...
        numel(cfg.maximumBlockNullScale) ~= 4 || ...
        any(cfg.blockNullScaleMultiplier < 1) || ...
        any(cfg.maximumBlockNullScale <= 0) || ...
        any(cfg.maximumBlockNullScale >= 1) || ...
        cfg.globalNullScaleMultiplier < 1 || ...
        cfg.maximumGlobalNullScale <= 0 || ...
        cfg.maximumGlobalNullScale >= 1 || ...
        cfg.globalPcnFraction <= 0 || cfg.globalPcnFraction >= 1
    error('SHT:SteadyUQB:BadNullDirectionConfiguration', ...
        '物理块或全局核的弱信息方向配置无效。');
end
cfg.kernelWeights = cfg.kernelWeights / sum(cfg.kernelWeights);
% 保留旧字段，仅用于历史入口读取；新采样器统一使用五核字段。
cfg.blockKernelWeights = cfg.kernelWeights;
cfg.blockInitialPcnScale = cfg.initialPcnScale;
end

function particleCount = local_particle_count(userCfg)
% 新入口优先；仅配置旧字段时继续兼容历史调用。两者同时出现必须一致。
hasPublic = local_has_option(userCfg,'particleCount');
hasLegacy = local_has_option(userCfg,'formalSampleCount');
hasPredictive = local_has_option(userCfg,'posteriorPredictiveSampleCount');

if hasPublic
    particleCount = userCfg.particleCount;
elseif hasLegacy
    particleCount = userCfg.formalSampleCount;
else
    particleCount = 1024;
end
local_validate_particle_count(particleCount,'particleCount');

if hasPublic
    publicCount = double(userCfg.particleCount);
else
    publicCount = double(particleCount);
end
if hasLegacy
    local_validate_particle_count( ...
        userCfg.formalSampleCount,'formalSampleCount');
    if double(userCfg.formalSampleCount) ~= publicCount
        error('SHT:SteadyUQB:ParticleCountConflict', ...
            ['particleCount与兼容字段formalSampleCount不一致；' ...
             '方法B一次运行只能选择512或1024中的一档。']);
    end
end
if hasPredictive
    local_validate_particle_count( ...
        userCfg.posteriorPredictiveSampleCount, ...
        'posteriorPredictiveSampleCount');
    if double(userCfg.posteriorPredictiveSampleCount) ~= publicCount
        error('SHT:SteadyUQB:PredictiveParticleCountConflict', ...
            ['posteriorPredictiveSampleCount必须与正式粒子数一致；' ...
             '请只设置particleCount选择512或1024。']);
    end
end
particleCount = double(particleCount);
end

function local_validate_particle_count(value,name)
if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
        ~isfinite(value) || value ~= floor(value) || ...
        ~ismember(double(value),[512,1024])
    error('SHT:SteadyUQB:BadParticleCount', ...
        '%s只允许取512或1024。',name);
end
end

function yes = local_has_option(options,name)
yes = isstruct(options) && isfield(options,name) && ...
    ~isempty(options.(name));
end

function contract = local_build_contract(cfg)
% 复用上游可变节点参数的坐标和工程先验结构，但不保留其确定性估计值。
baseCfg = sht_steady_model_uq_common('defaultconfig', cfg);
base = sht_steady_model_uq_common('buildcontract', baseCfg);
if base.parameterCount < 11
    error('SHT:SteadyUQB:BaseContractDimension', ...
        '公共总体参数合同只有%d维，未形成完整11组参数对象。', ...
        base.parameterCount);
end

baseTable = base.parameterTable;
deterministicEstimate = baseTable.point_estimate(:);
baseTable.point_estimate(:) = 0;
baseTable.block_name = repmat("aggregate", height(baseTable), 1);
newTable = local_new_parameter_table(baseTable,cfg.modelMode);
parameterTable = [baseTable; newTable];
parameterTable.index = (1:height(parameterTable)).';

priorSigma = parameterTable.prior_sigma .* cfg.priorScale;
priorCorrelation = blkdiag(base.priorCorrelation, eye(height(newTable)));
priorCovariance = diag(priorSigma) * priorCorrelation * diag(priorSigma);
priorCovariance = 0.5 * (priorCovariance + priorCovariance.');
lower = parameterTable.lower_bound;
upper = parameterTable.upper_bound;
priorMean = zeros(height(parameterTable), 1);
if any(priorMean < lower) || any(priorMean > upper)
    error('SHT:SteadyUQB:PriorMeanOutsideBounds', ...
        '方法B零中心先验均值没有严格位于全部硬边界内部。');
end

scheduleTemplate = local_zero_parameter_template( ...
    base.scheduleTemplate, baseTable);
blockNames = ["aggregate"; "local"; "bleed"; "cross"];
blockIndex = {find(parameterTable.block_name == "aggregate"), ...
    find(parameterTable.block_name == "local"), ...
    find(parameterTable.block_name == "bleed"), ...
    (1:height(parameterTable)).'};
blockCount = cellfun(@numel, blockIndex).';
parameterBlockTable = table((1:4).', blockNames, blockCount, ...
    'VariableNames', {'block_index','block_name','parameter_count'});
parameterGroupTable = local_parameter_group_table(parameterTable);

% 参数分类用于结果解释；采样核另按发动机物理耦合关系划分。前四个物理
% 核互斥覆盖实际字典，第五个核负责跨部件联合移动。
[samplingKernelIndex, samplingKernelName] = ...
    sht_uq_physical_blocks(parameterTable);
samplingKernelCount = cellfun(@numel,samplingKernelIndex).';
samplingPhysicalUnion = sort(vertcat(samplingKernelIndex{1:4}));
if ~isequal(samplingPhysicalUnion,(1:height(parameterTable)).') || ...
        sum(samplingKernelCount(1:4)) ~= height(parameterTable)
    error('SHT:SteadyUQB:SamplingKernelPartition', ...
        '四个物理采样核没有互斥且完整地覆盖实际参数字典。');
end
for i = 1:4
    for j = i+1:4
        crossCorrelation = priorCorrelation( ...
            samplingKernelIndex{i},samplingKernelIndex{j});
        if any(abs(crossCorrelation(:)) > 1e-14)
            error('SHT:SteadyUQB:CrossKernelPriorCorrelation', ...
                ['物理核%d与%d存在跨核先验相关，按参数下标执行的块pCN' ...
                 '不再保持先验，必须先调整分块。'],i,j);
        end
    end
end
samplingKernelTable = table((1:5).',samplingKernelName, ...
    samplingKernelCount,cfg.kernelWeights(:), ...
    'VariableNames',{'kernel_index','kernel_name','parameter_count', ...
    'proposal_fraction'});

paths = sht_steady_model_uq_b_io('paths',cfg);
contractCore = struct();
contractCore.schemaVersion = ...
    'steady_model_uq_method_b_contract_v5_geometric_bridge';
contractCore.route = cfg.route;
contractCore.baseContractHash = base.contractHash;
contractCore.measurementRoleContract = base.measurementRoleContract;
contractCore.outputPredictionRoute = base.outputPredictionRoute;
contractCore.trainingDataHash = sht_steady_model_uq_common( ...
    'filehash', base.trainingFile);
contractCore.engineArtifactHash = {base.engineArtifacts.sha256};
contractCore.parameterNames = cellstr(parameterTable.name);
contractCore.parameterCIndex = parameterTable.c_index(:).';
contractCore.parameterCoordinates = parameterTable.coordinate(:).';
contractCore.lower = lower(:).';
contractCore.upper = upper(:).';
contractCore.priorSigma = priorSigma(:).';
contractCore.priorCorrelation = priorCorrelation;
contractCore.samplingKernelIndex = samplingKernelIndex;
contractCore.samplingKernelWeights = cfg.kernelWeights;
contractCore.globalNullOnlyFraction=cfg.globalNullOnlyFraction;
contractCore.globalNullOnlyScale=cfg.globalNullOnlyScale;
contractCore.samplerDesign = ...
    'proposal_to_posterior_geometric_bridge_five_kernel_smc';
contractCore.covarianceScenario = cfg.covarianceScenario;
contractCore.modelDiscrepancyScale = cfg.modelDiscrepancyScale;
contractCore.codeHash = local_runtime_code_hash();
contractHash = local_text_hash(jsonencode(contractCore));

contract = struct();
contract.modelMode=cfg.modelMode;
contract.schemaVersion = contractCore.schemaVersion;
contract.createdAt = datestr(now, 30);
contract.route = cfg.route;
contract.measurementRoleContract = base.measurementRoleContract;
contract.outputPredictionRoute = base.outputPredictionRoute;
contract.config = cfg;
contract.baseContractHash = base.contractHash;
contract.trainingFile = base.trainingFile;
contract.testFile = base.testFile;
contract.deterministicWorkbookFile = base.deterministicWorkbookFile;
contract.deterministicWorkbookSha256 = ...
    base.deterministicWorkbookSha256;
contract.deterministicWorkbookSemanticSha256 = ...
    base.deterministicWorkbookSemanticSha256;
contract.deterministicRunId = base.deterministicRunId;
contract.deterministicResultFile = base.deterministicResultFile;
if isfield(base,'replayModel'),contract.replayModel=base.replayModel;end
contract.deterministicReplaySidecarSha256 = ...
    base.deterministicReplaySidecarSha256;
contract.deterministicFormalInterface = base.deterministicFormalInterface;
contract.trainingData = base.trainingData;
contract.trainingPointIds = base.trainingPointIds;
contract.trainingPointCount = base.trainingPointCount;
contract.residualPerPoint = base.residualPerPoint;
contract.observationDimension = base.observationDimension;
contract.residualOrder = base.residualOrder;
contract.parameterCount = height(parameterTable);
contract.aggregateParameterCount = base.parameterCount;
contract.localParameterCount = numel(blockIndex{2});
contract.bleedParameterCount = numel(blockIndex{3});
contract.parameterTable = parameterTable;
contract.parameterGroupTable = parameterGroupTable;
contract.parameterBlockTable = parameterBlockTable;
contract.parameterBlockIndex = blockIndex;
contract.samplingKernelTable = samplingKernelTable;
contract.samplingKernelIndex = samplingKernelIndex;
contract.thetaHat = priorMean; % 仅供通用采样器显示；含义是零先验参考点。
contract.referencePoint = priorMean;
contract.referencePointSource = 'independent_zero_prior_center';
if cfg.modelMode==0
    % 出口引气焓位置的正修正不可行。先验仍是零中心高斯截断，
    % 数值线性化点取截断后的矩均值，避免在硬边界上作中心差分。
    boundaryReference = priorMean==lower | priorMean==upper;
    boundedMean=sht_steady_model_uq_c_common('truncatedmoments', ...
        priorMean,priorSigma,lower,upper);
    contract.referencePoint(boundaryReference)=boundedMean(boundaryReference);
    contract.referencePointSource='zero_center_truncated_prior_interior_reference';
    contract.thetaHat=contract.referencePoint;
end
% 2.4 D阶段确定性辨识结果只用于最终对照展示，不参与方法B先验、提议或似然。
contract.deterministicEstimate = [deterministicEstimate; ...
    nan(height(newTable),1)];
contract.deterministicEstimateParameterCount = numel(deterministicEstimate);
contract.deterministicEstimateUsedByInference = false;
contract.lowerBound = lower;
contract.upperBound = upper;
contract.priorMean = priorMean;
contract.priorSigma = priorSigma;
contract.priorCorrelation = priorCorrelation;
contract.priorCovariance = priorCovariance;
contract.priorType = 'gaussian_copula_truncated_normal';
contract.scheduleTemplate = scheduleTemplate;
contract.deterministicOffsetParameterCount = ...
    base.deterministicOffsetParameterCount;
contract.scheduleConditioning = ...
    ['variable_aggregate_node_coordinates_frozen_' ...
     'new_physical_parameters_constant'];
contract.fixedDirectInletScheduleCIndex = 0;
if cfg.modelMode==0,contract.fixedDirectInletScheduleCIndex=[];end
contract.methodAPosteriorUsed = false;
contract.methodADeterministicValuesUsed = false;
contract.commonMeasurementLinearization = ...
    'upstream_deterministic_schedule_only_no_method_a_uq_posterior';
contract.trainingOnlyUntilStep10 = true;
contract.truthAccessAllowedBeforeStep10 = false;
contract.testAccessAllowedBeforeStep10 = false;
contract.steadyWindowSampleCount = base.steadyWindowSampleCount;
contract.engineArtifacts = base.engineArtifacts;
contract.flightUqFingerprintBefore = base.flightUqFingerprintBefore;
contract.contractHash = contractHash;
contract.cacheFile = fullfile(paths.middleRoot, ...
    ['exact_training_cache_' contractHash(1:16) '.mat']);
expectedLocal=12;if cfg.modelMode==0,expectedLocal=4;end
if contract.parameterCount ~= base.parameterCount + expectedLocal + 20 || ...
        numel(blockIndex{1}) ~= base.parameterCount || ...
        numel(blockIndex{2}) ~= expectedLocal || ...
        numel(blockIndex{3}) ~= 20
    error('SHT:SteadyUQB:ParameterContractDimension', ...
        '方法B合同没有形成动态主要参数+%d个部件参数+20个引气参数。',expectedLocal);
end
end

function geometry = local_sampling_geometry(contract,step5)
% 以测量协方差白化、再按先验潜变量缩放后的Jacobian构造提议几何。
% 奇异值大于1表示数据曲率强于单位标准正态先验曲率，只用于区分pCN
% 的信息方向与弱信息方向，不改变82维后验目标。
if ~isstruct(contract) || ~isfield(contract,'samplingKernelIndex') || ...
        numel(contract.samplingKernelIndex) ~= 5
    error('SHT:SteadyUQB:MissingSamplingKernelContract', ...
        '方法B合同缺少五核采样索引。');
end
if ~isstruct(step5) || ~isfield(step5,'latentWhitenedJacobian') || ...
        size(step5.latentWhitenedJacobian,2) ~= contract.parameterCount
    error('SHT:SteadyUQB:MissingLatentJacobian', ...
        'B05结果缺少与82维合同一致的潜空间白化Jacobian。');
end
latentJacobian = step5.latentWhitenedJacobian;
[~,globalS,globalBasis] = svd(latentJacobian);
globalSingularValue = diag(globalS);
globalInformedRank = nnz(globalSingularValue > 1);
blockBasis = cell(4,1);
blockSingularValue = cell(4,1);
blockInformedRank = zeros(4,1);
blockEnergyFraction = zeros(4,1);
globalEnergy = sum(globalSingularValue.^2);
for k = 1:4
    index = contract.samplingKernelIndex{k};
    [~,blockS,blockBasis{k}] = svd(latentJacobian(:,index));
    blockSingularValue{k} = diag(blockS);
    blockInformedRank(k) = nnz(blockSingularValue{k} > 1);
    blockEnergyFraction(k) = sum(blockSingularValue{k}.^2) / ...
        max(globalEnergy,eps);
end
geometry = struct('schemaVersion', ...
    'steady_model_uq_method_b_sampling_geometry_v1', ...
    'latentWhitenedJacobian',latentJacobian, ...
    'globalBasis',globalBasis, ...
    'globalSingularValue',globalSingularValue, ...
    'globalInformedRank',globalInformedRank, ...
    'blockBasis',{blockBasis}, ...
    'blockSingularValue',{blockSingularValue}, ...
    'blockInformedRank',blockInformedRank, ...
    'blockEnergyFraction',blockEnergyFraction, ...
    'activeParameterIndex',(1:contract.parameterCount).', ...
    'structuralPriorOnlyParameterIndex', ...
    step5.structuralPriorOnlyParameterIndex(:), ...
    'activeLatentPcnBasis',globalBasis, ...
    'activeLatentInformedRank',globalInformedRank, ...
    'activeLatentSingularValues',globalSingularValue, ...
    'thetaLocal',step5.thetaLocal(:));
end

function tbl = local_new_parameter_table(baseTable,modelMode)
dictionary = sht_health_parameter_dictionary(modelMode);
localIndex = [71,72,74,75,77,78,80,81,83,84,86,87].';
if modelMode==0,localIndex=[3;5;9;13];end
bleedFlow = (30:39).';
bleedTemperature = (44:53).';
cIndex = [localIndex; bleedFlow; bleedTemperature];
n = numel(cIndex);
tbl = repmat(baseTable(1,:), n, 1);
tbl.index = zeros(n,1);
tbl.name = strings(n,1);
tbl.base_name = strings(n,1);
tbl.c_index = cIndex;
tbl.unit = repmat("1",n,1);
tbl.group_index = max(baseTable.group_index) + (1:n).';
tbl.group_kind = repmat("health_constant",n,1);
tbl.schedule_entry_index = zeros(n,1);
tbl.dll_node_index = zeros(n,1);
tbl.node_index = ones(n,1);
tbl.coordinate = zeros(n,1);
tbl.normalized_coordinate = zeros(n,1);
tbl.point_estimate = zeros(n,1);
tbl.lower_bound = zeros(n,1);
tbl.upper_bound = zeros(n,1);
tbl.prior_sigma = zeros(n,1);
tbl.difference_step = zeros(n,1);
tbl.axis_name = repmat("constant",n,1);
tbl.pressure_loss = false(n,1);
tbl.block_name = strings(n,1);

for i = 1:n
    row = dictionary(dictionary.c_index == cIndex(i),:);
    if height(row) ~= 1 || ~row.active
        error('SHT:SteadyUQB:DictionaryMismatch', ...
            'h%d未在六部件健康参数字典中唯一启用。', cIndex(i));
    end
    tbl.name(i) = row.name;
    tbl.base_name(i) = row.name;
    if ismember(cIndex(i), localIndex)
        tbl.lower_bound(i) = -0.025;
        tbl.upper_bound(i) = 0.025;
        tbl.prior_sigma(i) = 0.006;
        tbl.difference_step(i) = 5e-4;
        tbl.block_name(i) = "local";
    elseif ismember(cIndex(i), bleedFlow)
        tbl.lower_bound(i) = -0.0028;
        tbl.upper_bound(i) = 0.0028;
        tbl.prior_sigma(i) = 0.0010;
        tbl.difference_step(i) = 1e-4;
        tbl.block_name(i) = "bleed";
    else
        bound=.015;sigma=.004;
        if modelMode==0,bound=.05;sigma=.015;end
        tbl.lower_bound(i) = -bound;
        tbl.upper_bound(i) = bound;
        tbl.prior_sigma(i) = sigma;
        tbl.difference_step(i) = 2.5e-4;
        tbl.block_name(i) = "bleed";
    end
end
if modelMode==0
    mdl=fileread(fullfile(fileparts(mfilename('fullpath')),'Turboshaft-TS.mdl'));
    effToken=regexp(mdl,'(?m)^\s*burnerEfficiency\s*=\s*([^\r\n]+)','tokens','once');
    assert(~isempty(effToken),'TC24:UQ:BurnerEfficiency','MDL缺少燃烧效率。');
    eff=str2double(strtrim(effToken{1}));assert(eff>0 && eff<=1);
    efficiencyRow=find(cIndex==5);
    tbl.upper_bound(efficiencyRow)=min(tbl.upper_bound(efficiencyRow),1/eff-1);
    token=regexp(mdl,'(?m)^\s*fractionalBleedsEnthalpyVec\s*=([^\r\n]+)','tokens','once');
    assert(~isempty(token),'TC24:UQ:MissingBleedPositions','MDL缺少引气焓提取位置。');
    z=sscanf(token{1},'%f');
    assert(numel(z)==14,'TC24:UQ:BleedPositions','三部件MDL应有14个内部焓位置。');
    physical=[1,2,3,2,3,4,5,6,7,6,7,8,9,10];
    for branch=1:10
        row=find(cIndex==43+branch);selected=z(physical==branch);
        tbl.lower_bound(row)=max(tbl.lower_bound(row),-min(selected));
        tbl.upper_bound(row)=min(tbl.upper_bound(row),1-max(selected));
    end
end
end

function groupTable = local_parameter_group_table(tbl)
groups = unique(tbl.group_index, 'stable');
groupName = strings(numel(groups),1);
groupKind = strings(numel(groups),1);
blockName = strings(numel(groups),1);
parameterCount = zeros(numel(groups),1);
for i = 1:numel(groups)
    use = tbl.group_index == groups(i);
    groupName(i) = tbl.base_name(find(use,1));
    groupKind(i) = tbl.group_kind(find(use,1));
    blockName(i) = tbl.block_name(find(use,1));
    parameterCount(i) = nnz(use);
end
groupTable = table(groups, groupName, groupKind, blockName, ...
    parameterCount, 'VariableNames', {'group_index','group_name', ...
    'group_kind','block_name','parameter_count'});
end

function schedule = local_zero_parameter_template(schedule, baseTable)
% h0由Pt1/Pt2直接计算形成，不属于节点级联合参数，保留上游数据推导值。
estimatedCIndex = unique(baseTable.c_index(baseTable.c_index >= 0));
for i = 1:numel(schedule.healthEntries)
    entry = schedule.healthEntries(i);
    if ismember(entry.cIndex, estimatedCIndex)
        entry.kNodes(:) = 0;
        entry.kNodesDll(:) = 0;
        if isfield(entry,'deltaNodes'), entry.deltaNodes(:) = 0; end
        entry.designValue = 0;
        entry.deltaNodesDll(:) = 0;
        schedule.healthEntries(i) = entry;
    end
end
schedule.fuelBias.biasNodes(:) = 0;
schedule.h15 = 0;
schedule.designHealth = local_schedule_design_health(schedule);
end

function data = local_load_data(contract, role)
data = sht_steady_model_uq_common('loaddata', contract, role);
end

function output = local_evaluate(contract, thetaMatrix, data, options)
if nargin < 3 || isempty(data), data = contract.trainingData; end
if nargin < 4 || isempty(options), options = struct(); end
if size(thetaMatrix,1) ~= contract.parameterCount
    error('SHT:SteadyUQB:BadThetaMatrix', ...
        '方法B候选矩阵必须为%d行。', contract.parameterCount);
end
needPredictions = logical(local_option(options,'returnPredictions',false));
needDiagnostics = logical(local_option(options,'returnDiagnostics',false));
evaluationRoute = char(local_option(options,'routeOverride',contract.route));
routeContract = sht_steady_model_uq_common( ...
    'routecontract',evaluationRoute,contract.config.modelMode);
robustTransientFallback = logical(local_option( ...
    options,'useRobustTransientFallback',false));
useCache = logical(local_option(options,'useCache',contract.config.useCache));
defaultCacheFile = contract.cacheFile;
if ~strcmp(evaluationRoute,contract.route)
    cacheFolder = fileparts(defaultCacheFile);
    defaultCacheFile = fullfile(cacheFolder, ...
        ['exact_output_' evaluationRoute '_cache_' ...
        contract.contractHash(1:16) '.mat']);
end
cacheFile = sht_steady_model_uq_b_io('decodepaths', ...
    char(local_option(options,'cacheFile',defaultCacheFile)));
if useCache
    sht_steady_model_uq_b_io('assertcachefile',cacheFile,contract.config);
end
[observation,~,~] = sht_steady_model_uq_common( ...
    'observation',contract,data,evaluationRoute);
nCandidate = size(thetaMatrix,2);
residual = nan(numel(observation),nCandidate);
valid = false(1,nCandidate);
prediction = cell(1,nCandidate);
diagnostic = cell(1,nCandidate);
inside = all(thetaMatrix >= contract.lowerBound & ...
    thetaMatrix <= contract.upperBound,1) & all(isfinite(thetaMatrix),1);

cache = local_empty_cache(contract,numel(observation),evaluationRoute);
evaluationIdentity=sht_steady_model_uq_common('evaluationidentity', ...
    contract,data,options,evaluationRoute);
cache.evaluationIdentity=evaluationIdentity;
if useCache && ~needPredictions && exist(cacheFile,'file') == 2
    loaded = load(cacheFile,'cache');
    if isfield(loaded,'cache') && ...
            strcmp(loaded.cache.contractHash,contract.contractHash) && ...
            isfield(loaded.cache,'evaluationRoute') && ...
            strcmp(loaded.cache.evaluationRoute,evaluationRoute) && ...
            loaded.cache.residualDimension == numel(observation) && ...
            isfield(loaded.cache,'evaluationIdentity') && ...
            strcmp(loaded.cache.evaluationIdentity,evaluationIdentity)
        cache = loaded.cache;
    end
end
hitCount = 0;
newIndex = zeros(0,1);
newKeys = cell(0,1);
duplicateOf=zeros(1,nCandidate);
% 批量查询与原逐候选strcmp的键值、首个匹配语义一致，不改变回放顺序。
% 仍保留原缓存身份和逐批落盘，先不引入常驻缓存或新的断点格式。
candidateKeys=cell(1,nCandidate);cachedIndex=zeros(1,nCandidate);
insideIndex=find(inside);
for i=insideIndex,candidateKeys{i}=local_theta_key(thetaMatrix(:,i));end
if useCache && ~needPredictions && ~isempty(cache.keys) && ~isempty(insideIndex)
    [~,cachedIndex(insideIndex)]=ismember(candidateKeys(insideIndex),cache.keys);
end
for i = 1:nCandidate
    if ~inside(i), continue; end
    key=candidateKeys{i};index=cachedIndex(i);
    if index==0
        duplicate=find(strcmp(newKeys,key),1);
        if ~isempty(duplicate)
            duplicateOf(i)=newIndex(duplicate);hitCount=hitCount+1;continue;
        end
        newIndex(end+1,1) = i; %#ok<AGROW>
        newKeys{end+1,1} = key; %#ok<AGROW>
    else
        residual(:,i) = cache.residual(:,index);
        valid(i) = cache.valid(index);
        hitCount = hitCount+1;
    end
end

dllTimer = tic;
branchMeta = struct('enabled',false,'role',"not_applicable", ...
    'testNpUsed',false,'prior',struct());
if ~isempty(newIndex)
    deterministic.result=sht_steady_model_uq_common('replaymodel',contract);
    if local_option(options,'independentRemeasurement',false)
        deterministic.result.options.fuelInputSemantics='physical_model';
    end
    [replayData,branchMeta] = sht_steady_model_uq_common( ...
        'preparebranchdata',contract,data,deterministic.result, ...
        evaluationRoute,local_option(options,'independentRemeasurement',false));
    schedules = cell(numel(newIndex),1);
    for k = 1:numel(newIndex)
        schedules{k} = local_vector_to_schedule( ...
            contract,thetaMatrix(:,newIndex(k)));
    end
    batchOptions = struct('useRobustTransientFallback', ...
        robustTransientFallback,'steadyNpBranchEnabled',branchMeta.enabled, ...
        'routeOverride',evaluationRoute);
    batchOptions.uqSteadyContinuation=contract.config.modelMode==0 && ...
        strcmp(evaluationRoute,'steady') && local_option(options,'independentRemeasurement',false) && ...
        local_option(options,'uqSteadyContinuation',true);
    if isfield(options,'uqContinuationOptions'),batchOptions.uqContinuationOptions=options.uqContinuationOptions;end
    initialSeedMatrices = local_option(options,'initialSeedMatrices',[]);
    if ~isempty(initialSeedMatrices)
        batchOptions.initialSeedMatrices = initialSeedMatrices;
    end
    batch = sht_steady_model_adapt_v2_common( ...
        'evaluateschedulebatchdataset',deterministic.result,replayData, ...
        schedules,batchOptions);
    for k = 1:numel(newIndex)
        i = newIndex(k);
        item = batch.candidate(k);
        if item.valid
            predicted = sht_steady_model_uq_common( ...
                'predictionvector',evaluationRoute,item.prediction,contract);
            residual(:,i) = predicted-observation;
            valid(i) = all(isfinite(residual(:,i)));
        end
        if needPredictions, prediction{i} = item.prediction; end
        if needDiagnostics, diagnostic{i} = item.diagnostic; end
        if useCache && ~needPredictions
            cache.keys{end+1} = newKeys{k};
            cache.theta(:,end+1) = thetaMatrix(:,i);
            cache.residual(:,end+1) = residual(:,i);
            cache.valid(end+1) = valid(i);
        end
    end
end
dllRuntime = toc(dllTimer);
for i=find(duplicateOf)
    j=duplicateOf(i);residual(:,i)=residual(:,j);valid(i)=valid(j);
    prediction{i}=prediction{j};diagnostic{i}=diagnostic{j};
end
if useCache && ~needPredictions && ~isempty(newIndex)
    cache.physicalPrediction=cache.residual+observation;
    cache.updatedAt = datestr(now,30);
    cache.evaluationCount = size(cache.theta,2);
    [folder,~,~] = fileparts(cacheFile);
    if exist(folder,'dir') ~= 7, mkdir(folder); end
    save(cacheFile,'cache','-v7.3');
end
output = struct('theta',thetaMatrix,'residual',residual,'valid',valid, ...
    'prediction',{prediction},'diagnostic',{diagnostic}, ...
    'insideBounds',inside, ...
    'candidateCount',nCandidate,'cacheHitCount',hitCount, ...
    'dllEvaluationCount',numel(newIndex),'dllRuntime_s',dllRuntime, ...
    'cacheFile',cacheFile, ...
    'robustTransientFallbackEnabled',robustTransientFallback, ...
    'npBranch',branchMeta,'route',evaluationRoute, ...
    'residualOrder',{routeContract.residualOrder});
end

function schedule = local_vector_to_schedule(contract, theta)
theta = theta(:);
if numel(theta) ~= contract.parameterCount || any(~isfinite(theta))
    error('SHT:SteadyUQB:BadScheduleVector', ...
        '方法B参数向量必须为%d维有限向量。',contract.parameterCount);
end
if any(theta < contract.lowerBound) || any(theta > contract.upperBound)
    error('SHT:SteadyUQB:ScheduleVectorOutsideBounds', ...
        '方法B参数向量超出硬边界。');
end
schedule = contract.scheduleTemplate;
tbl = contract.parameterTable;
groupIds = unique(tbl.group_index,'stable');
constantHealth = zeros(159,1);
for g = groupIds(:).'
    rows = find(tbl.group_index == g);
    kind = char(tbl.group_kind(rows(1)));
    switch kind
        case 'health_schedule'
            cIndex = tbl.c_index(rows(1));
            entryIndex = find([schedule.healthEntries.cIndex] == cIndex,1);
            if isempty(entryIndex)
                error('SHT:SteadyUQB:TemplateScheduleEntryMissing', ...
                    '方法B模板调度缺少h%d。',cIndex);
            end
            entry = schedule.healthEntries(entryIndex);
            x = tbl.coordinate(rows);
            k = theta(rows);
            if entry.pressureLoss
                entry.xNodes = [0;x(:)];
                entry.kNodes = [0;k(:)];
            else
                entry.xNodes = x(:);
                entry.kNodes = k(:);
            end
            entry.xNodesDll = entry.xNodes;
            entry.kNodesDll = entry.kNodes;
            entry.designValue = local_interp_clamp( ...
                entry.xNodesDll,entry.kNodesDll,entry.designCoordinate);
            entry.deltaNodesDll = entry.kNodesDll-entry.designValue;
            if entry.pressureLoss
                entry.kNodesDll(1) = 0;
                entry.deltaNodesDll(1) = -entry.designValue;
            end
            if isfield(entry,'dllResamplingUsed')
                entry.dllResamplingUsed = false;
            end
            schedule.healthEntries(entryIndex) = entry;
        case 'fuel_bias'
            schedule.fuelBias.xNodes = tbl.coordinate(rows);
            schedule.fuelBias.biasNodes = theta(rows);
        case 'constant'
            schedule.h15 = theta(rows(1));
        case 'health_constant'
            cIndex = tbl.c_index(rows(1));
            constantHealth(cIndex+1) = theta(rows(1));
        otherwise
            error('SHT:SteadyUQB:UnknownParameterGroupKind', ...
                '方法B未知参数组类型%s。',kind);
    end
end
schedule.designHealth = local_schedule_design_health(schedule);
activeConstant = find(constantHealth ~= 0);
schedule.designHealth(activeConstant) = constantHealth(activeConstant);
end

function theta = local_schedule_to_vector(contract, schedule)
if ~isstruct(schedule) || ~isfield(schedule,'healthEntries') || ...
        ~isfield(schedule,'fuelBias') || ~isfield(schedule,'h15') || ...
        ~isfield(schedule,'designHealth')
    error('SHT:SteadyUQB:BadScheduleForVector', ...
        '输入不是方法B完整调度结构。');
end
tbl = contract.parameterTable;
theta = nan(contract.parameterCount,1);
for i = 1:contract.parameterCount
    kind = char(tbl.group_kind(i));
    switch kind
        case 'health_schedule'
            entryIndex = find([schedule.healthEntries.cIndex] == ...
                tbl.c_index(i),1);
            if isempty(entryIndex)
                error('SHT:SteadyUQB:ScheduleEntryMissingForVector', ...
                    '输入调度缺少h%d。',tbl.c_index(i));
            end
            entry = schedule.healthEntries(entryIndex);
            theta(i) = entry.kNodesDll(tbl.dll_node_index(i));
        case 'fuel_bias'
            theta(i) = schedule.fuelBias.biasNodes(tbl.dll_node_index(i));
        case 'constant'
            theta(i) = schedule.h15;
        case 'health_constant'
            theta(i) = schedule.designHealth(tbl.c_index(i)+1);
    end
end
if any(~isfinite(theta))
    error('SHT:SteadyUQB:NonfiniteScheduleVector', ...
        '从方法B调度结构提取的参数存在非有限值。');
end
end

function health = local_schedule_design_health(schedule)
health = zeros(159,1);
for i = 1:numel(schedule.healthEntries)
    entry = schedule.healthEntries(i);
    health(entry.cIndex+1) = entry.designValue;
end
health(16) = schedule.h15;
end

function result = local_input_covariance(contract, data, options)
% 输入误差传播是A/B共用的物理测量合同，不读取方法A UQ后验。
if nargin < 2 || isempty(data), data = contract.trainingData; end
if nargin < 3 || isempty(options), options = struct(); end
baseCfg = sht_steady_model_uq_common('defaultconfig',contract.config);
baseContract = sht_steady_model_uq_common('buildcontract',baseCfg);
result = sht_steady_model_uq_common( ...
    'inputcovariance',baseContract,data,options);
result.linearizationSource = ...
    'common_upstream_deterministic_schedule_no_method_a_uq_posterior';
result.methodAPosteriorUsed = false;
end

function cache = local_empty_cache(contract, dimension, evaluationRoute)
if nargin < 3 || isempty(evaluationRoute)
    evaluationRoute = contract.route;
end
cache = struct('schemaVersion', ...
    'steady_model_uq_method_b_cache_v3_route_explicit', ...
    'contractHash',contract.contractHash,'residualDimension',dimension, ...
    'evaluationRoute',char(evaluationRoute), ...
    'keys',{{}},'theta',zeros(contract.parameterCount,0), ...
    'residual',zeros(dimension,0),'valid',false(1,0), ...
    'evaluationCount',0,'updatedAt','');
end

function key = local_theta_key(theta)
key = sprintf('%.17g,',theta(:));
end

function value = local_interp_clamp(x,y,query)
x = x(:); y = y(:);
if numel(x)==1,value=repmat(y,size(query));return;end
query = min(max(query,x(1)),x(end));
value = interp1(x,y,query,'linear');
end

function hash = local_runtime_code_hash()
root = fileparts(mfilename('fullpath'));
files = {'sht_steady_model_uq_b_common.m', ...
    'sht_steady_model_uq_b_io.m', ...
    'sht_steady_model_uq_io.m', ...
    'sht_steady_model_uq_b_proposal.m', ...
    'sht_steady_model_uq_b_smc.m', ...
    'sht_tc24_uq_spectral_pcn.m', ...
    'sht_uq_null_pcn.m', ...
    'sht_steady_model_uq_sampler.m', ...
    'sht_steady_model_uq_likelihood.m', ...
    'sht_steady_model_adapt_v2_common.m', ...
    'sht_steady_np_branch_prior.m', ...
    'sht_solve_steady_np_branch.m', ...
    'sht_quantile_vector.m','sht_normal_probability.m', ...
    'sht_bounded_least_squares.m','sht_load_engine_library.m', ...
    'sht_sobol_points.m','sht_tc24_uq_box_normal.m', ...
    fullfile('TestData','compatibility','joe-kuo-old.1111')};
% 数值后端和运行版本属于检查点身份，不改变先验/似然定义。
% 禁止把历史检查点重新签名后在新后端继续运行。
textValue = ['MATLAB:',version,';arch:',computer('arch'),';backend:base_matlab_v1;'];
for i = 1:numel(files)
    file = fullfile(root,files{i});
    if exist(file,'file') == 2
        textValue = [textValue files{i} ':' ...
            sht_steady_model_uq_common('filehash',file) ';']; %#ok<AGROW>
    else
        textValue = [textValue files{i} ':missing;']; %#ok<AGROW>
    end
end
hash = local_text_hash(textValue);
end

function hash = local_text_hash(textValue)
digest = java.security.MessageDigest.getInstance('SHA-256');
bytes = unicode2native(char(textValue),'UTF-8');
% 空合同文本在独立交付场景下是合法输入；同时固定为列向量，避免
% MATLAB R2020a 对Java update重载的行列形状差异。
if ~isempty(bytes)
    digest.update(typecast(uint8(bytes(:)),'int8'));
end
digestBytes = typecast(int8(digest.digest()),'uint8');
hash = lower(reshape(dec2hex(digestBytes,2).',1,[]));
end

function value = local_option(options,name,defaultValue)
if isstruct(options) && isfield(options,name) && ~isempty(options.(name))
    value = options.(name);
else
    value = defaultValue;
end
end
