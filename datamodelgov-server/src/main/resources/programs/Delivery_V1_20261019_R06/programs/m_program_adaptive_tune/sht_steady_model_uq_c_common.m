function varargout = sht_steady_model_uq_c_common(action, varargin)
%SHT_STEADY_MODEL_UQ_C_COMMON 方法C的问题合同、回放和公共计算。
%
% 方法C按当前Excel的实际节点数确定显式变量，不固定参数维数。
% 附加发动机参数用于局部边缘化：三部件24维，六部件32维。
% 发动机精确回放直接委托给方法A/B已验证内核，避免参数字典、
% 调度函数或DLL接口在新路线中出现第二份实现。

switch lower(char(action))
    case 'defaultconfig'
        varargout{1} = local_default_config(varargin{:});
    case 'buildcontract'
        varargout{1} = local_build_contract(varargin{:});
    case 'evaluate'
        varargout{1} = local_evaluate(varargin{:});
    case 'evaluatenuisance'
        varargout{1} = local_evaluate_nuisance(varargin{:});
    case 'truncatedmoments'
        [varargout{1:nargout}] = local_truncated_moments(varargin{:});
    case 'factorcovariance'
        varargout{1} = local_factor_covariance(varargin{:});
    otherwise
        error('SHT:SteadyUQC:UnknownCommonAction', ...
            '未知方法C公共动作：%s。', action);
end
end

function cfg = local_default_config(userCfg)
if nargin < 1 || isempty(userCfg), userCfg = struct(); end
baseInput = userCfg;
baseInput.route = 'steady';
if local_option(userCfg,'modelMode',1)==0
    baseInput.route=char(local_option(userCfg,'route','transient_instant'));
end
cfg = sht_steady_model_uq_common('defaultconfig', baseInput);
cfg.route = baseInput.route;
cfg.randomSeed = local_option(userCfg, 'randomSeed', 20260902);
cfg.pilotSampleCount = local_option(userCfg, 'pilotSampleCount', 64);
cfg.pilotReplicateCount = local_option(userCfg, 'pilotReplicateCount', 3);
cfg.formalSampleCount = local_option(userCfg, 'formalSampleCount', 512);
cfg.proposalLocalFraction = local_option( ...
    userCfg, 'proposalLocalFraction', 0.45);
cfg.smcPilotTargetEssFraction = local_option( ...
    userCfg,'smcPilotTargetEssFraction',0.60);
cfg.smcFormalTargetEssFraction = local_option( ...
    userCfg,'smcFormalTargetEssFraction',0.55);
cfg.pilotMoveSweeps = local_option(userCfg, 'pilotMoveSweeps', 1);
cfg.pilotFinalMoveSweeps = local_option( ...
    userCfg, 'pilotFinalMoveSweeps', 2);
cfg.formalMoveSweeps = local_option(userCfg, 'formalMoveSweeps', 1);
cfg.formalFinalMoveSweeps = local_option( ...
    userCfg, 'formalFinalMoveSweeps', 4);
cfg.maximumStageCount = local_option(userCfg, 'maximumStageCount', 70);
cfg.kernelWeights = local_option( ...
    userCfg, 'kernelWeights', [0.23, 0.17, 0.25, 0.10, 0.25]);
cfg.kernelWeights = cfg.kernelWeights(:).';
if numel(cfg.kernelWeights)==5 && all(isfinite(cfg.kernelWeights)) && ...
        all(cfg.kernelWeights>0)
    cfg.kernelWeights = cfg.kernelWeights/sum(cfg.kernelWeights);
end
cfg.initialPcnScale = local_option( ...
    userCfg, 'initialPcnScale', [0.08, 0.05, 0.08, 0.20, 0.035]);
cfg.minimumPcnScale = local_option( ...
    userCfg, 'minimumPcnScale', [0.015, 0.010, 0.015, 0.030, 0.008]);
cfg.maximumPcnScale = local_option( ...
    userCfg, 'maximumPcnScale', [0.25, 0.18, 0.30, 0.50, 0.15]);
cfg.targetAcceptance = local_option( ...
    userCfg, 'targetAcceptance', [0.28, 0.32, 0.25, 0.35, 0.18]);
cfg.blockNullScaleMultiplier = local_option( ...
    userCfg, 'blockNullScaleMultiplier', [2.0, 2.0, 2.0, 2.0]);
cfg.maximumBlockNullScale = local_option( ...
    userCfg, 'maximumBlockNullScale', [0.55, 0.45, 0.60, 0.75]);
cfg.globalNullScaleMultiplier = local_option( ...
    userCfg, 'globalNullScaleMultiplier', 4.0);
cfg.maximumGlobalNullScale = local_option( ...
    userCfg, 'maximumGlobalNullScale', 0.55);
cfg.globalPcnFraction = local_option(userCfg, 'globalPcnFraction', 0.80);
% 采样配置必须随step1合同保存，分阶段/冷恢复不能悄然回到默认值。
profile='legacy_reference';if cfg.modelMode==0,profile='quality';end
cfg.cSamplerProfile=char(local_option(userCfg,'cSamplerProfile',profile));
assert(ismember(cfg.cSamplerProfile,{'quality','legacy_reference'}), ...
    'TC24:C:SamplerProfile','未知C采样配置。');
cfg.cConditionalEssFraction=local_option(userCfg,'cConditionalEssFraction',.8);
cfg.cResampleEssFraction=local_option(userCfg,'cResampleEssFraction',.55);
cfg.cReferenceShrinkage=local_option(userCfg,'cReferenceShrinkage',.15);
cfg.cReferenceEigenvalueFloor=local_option(userCfg,'cReferenceEigenvalueFloor',.05);
cfg.cSamplingSeed=local_option(userCfg,'cSamplingSeed',cfg.randomSeed+5001);
validateattributes(cfg.cConditionalEssFraction,{'numeric'},{'scalar','finite','>',0,'<',1});
validateattributes(cfg.cResampleEssFraction,{'numeric'},{'scalar','finite','>',0,'<',1});
validateattributes(cfg.cReferenceShrinkage,{'numeric'},{'scalar','finite','>=',0,'<=',1});
validateattributes(cfg.cReferenceEigenvalueFloor,{'numeric'},{'scalar','finite','positive'});
validateattributes(cfg.cSamplingSeed,{'numeric'},{'scalar','finite','integer','>=',0,'<=',2^32-1});
cfg.cMoveReferenceHash='';
if strcmp(cfg.cSamplerProfile,'quality')
    reference=which('sht_tc27_uq_move_reference');
    assert(~isempty(reference),'TC24:C:MissingMoveReference','缺少采样参考函数。');
    cfg.cMoveReferenceHash=sht_steady_model_uq_common('filehash',reference);
end
if isfield(userCfg,'cMoveReferenceHash')
    assert(strcmpi(char(userCfg.cMoveReferenceHash),cfg.cMoveReferenceHash), ...
        'TC24:C:MoveReferenceIdentity','共享参考函数与已冻结配置不一致，须新建运行，不能改签旧结果。');
end
cfg.nuisanceDifferenceSigmaFraction = local_option( ...
    userCfg, 'nuisanceDifferenceSigmaFraction', 0.25);
% R042：分离附加参数尺度，仅用于有身份的敏感性分析；默认不收紧先验。
cfg.nuisancePriorScale = local_option(userCfg,'nuisancePriorScale',1);
cfg.nuisanceAnchorMode = char(local_option(userCfg,'nuisanceAnchorMode','two_anchor'));
validateattributes(cfg.nuisancePriorScale,{'numeric'},{'scalar','finite','positive'});
assert(ismember(cfg.nuisanceAnchorMode,{'two_anchor','map_checked'}), ...
    'TC24:C:AnchorMode','未知附加参数线性化方式。');
cfg.methodAReferenceRunId = char(local_option(userCfg, ...
    'methodAReferenceRunId', 'uq_A_steady_current_contract_20260901_v2'));
cfg.methodBHistoricalRunId = char(local_option(userCfg, ...
    'methodBHistoricalRunId', ...
    'steady_uq_v3_variable_nodes_B_20260826_142928'));
cfg.methodABComparisonCsv = char(local_option(userCfg, ...
    'methodABComparisonCsv', fullfile(fileparts(fileparts( ...
    mfilename('fullpath'))), 'report_outputs', 'steady_model_uq_method_b', ...
    'A_current_steady_vs_B_historical_best_shared50_20260902_v1', ...
    'AB01_shared50_interval_comparison.csv')));
local_validate_config(cfg);
end

function local_validate_config(cfg)
if cfg.modelMode~=0 && ~strcmp(cfg.route, 'steady')
    error('SHT:SteadyUQC:RouteMustBeSteady', ...
        '方法C本轮合同只允许steady路径。');
end
integerNames = {'pilotSampleCount','pilotReplicateCount', ...
    'formalSampleCount','pilotMoveSweeps','pilotFinalMoveSweeps', ...
    'formalMoveSweeps','formalFinalMoveSweeps','maximumStageCount'};
for i = 1:numel(integerNames)
    value = cfg.(integerNames{i});
    if ~isscalar(value) || ~isfinite(value) || value < 1 || value ~= floor(value)
        error('SHT:SteadyUQC:BadIntegerConfiguration', ...
            '%s必须为正整数。', integerNames{i});
    end
end
fractionNames = {'proposalLocalFraction','smcPilotTargetEssFraction', ...
    'smcFormalTargetEssFraction','globalPcnFraction', ...
    'nuisanceDifferenceSigmaFraction'};
for i = 1:numel(fractionNames)
    value = cfg.(fractionNames{i});
    if ~isscalar(value) || ~isfinite(value) || value <= 0 || value >= 1
        error('SHT:SteadyUQC:BadFractionConfiguration', ...
            '%s必须严格位于(0,1)。', fractionNames{i});
    end
end
fiveNames = {'kernelWeights','initialPcnScale','minimumPcnScale', ...
    'maximumPcnScale','targetAcceptance'};
for i = 1:numel(fiveNames)
    value = cfg.(fiveNames{i});
    if numel(value) ~= 5 || any(~isfinite(value))
        error('SHT:SteadyUQC:BadFiveKernelConfiguration', ...
            '%s必须包含5个有限数。', fiveNames{i});
    end
end
if any(cfg.kernelWeights <= 0) || ...
        any(cfg.minimumPcnScale <= 0) || any(cfg.maximumPcnScale >= 1) || ...
        any(cfg.minimumPcnScale > cfg.initialPcnScale) || ...
        any(cfg.initialPcnScale > cfg.maximumPcnScale)
    error('SHT:SteadyUQC:BadKernelScaleConfiguration', ...
        '五核权重或pCN最小/初始/最大步长配置无效。');
end
if numel(cfg.blockNullScaleMultiplier) ~= 4 || ...
        numel(cfg.maximumBlockNullScale) ~= 4 || ...
        any(cfg.blockNullScaleMultiplier < 1) || ...
        any(cfg.maximumBlockNullScale <= 0) || ...
        any(cfg.maximumBlockNullScale >= 1)
    error('SHT:SteadyUQC:BadBlockNullConfiguration', ...
        '四个物理块的弱信息方向步长配置无效。');
end
end

function contract = local_build_contract(cfg)
baseCfg = sht_steady_model_uq_common('defaultconfig', cfg);
baseCfg.route = cfg.route;
base = sht_steady_model_uq_common('buildcontract', baseCfg);
% 方法C只借用方法B的模式相关参数字典构造干扰参数合同，并不执行
% 方法B采样。这里使用固定的合法占位数通过B公开配置入口，随后恢复
% C自身的采样规模；这样B的512/1024规则不会错误限制方法C。同时删除
% B新增的用户别名，避免该别名污染已冻结的方法C统计合同。
auxInput = cfg;
auxInput.particleCount = 512;
auxInput.formalSampleCount = 512;
auxInput.posteriorPredictiveSampleCount = 512;
auxCfg = sht_steady_model_uq_b_common('defaultconfig', auxInput);
auxCfg.formalSampleCount = cfg.formalSampleCount;
auxCfg.posteriorPredictiveSampleCount = cfg.posteriorPredictiveSampleCount;
if isfield(auxCfg,'particleCount')
    auxCfg = rmfield(auxCfg,'particleCount');
end
auxCfg.route = cfg.route;
auxiliary = sht_steady_model_uq_b_common('buildcontract', auxCfg);

nBase = base.parameterCount;
nuisanceIndex = (nBase+1:auxiliary.parameterCount).';
expectedNuisance=32;if cfg.modelMode==0,expectedNuisance=24;end
if numel(nuisanceIndex) ~= expectedNuisance || ...
        auxiliary.aggregateParameterCount ~= base.parameterCount
    error('SHT:SteadyUQC:ContractDimensionMismatch', ...
        '当前方法C要求可变节点显式参数和%d维干扰参数。',expectedNuisance);
end
if ~strcmp(base.contractHash, auxiliary.baseContractHash) || ...
        ~isequal(string(base.parameterTable.name), ...
        string(auxiliary.parameterTable.name(1:nBase))) || ...
        max(abs(base.parameterTable.coordinate - ...
        auxiliary.parameterTable.coordinate(1:nBase))) > 1e-14
    error('SHT:SteadyUQC:BaseAuxiliaryContractMismatch', ...
        '公共合同与B的总体参数合同不一致，禁止边缘化。');
end

[blockIndex, blockName] = sht_uq_physical_blocks(base.parameterTable);
blockCount = cellfun(@numel, blockIndex).';
physicalUnion = sort(vertcat(blockIndex{1:4}));
if ~isequal(physicalUnion, (1:nBase).') || ...
        sum(blockCount(1:4)) ~= nBase
    error('SHT:SteadyUQC:PhysicalBlockPartition', ...
        '四个物理参数块没有互斥且完整地覆盖实际参数字典。');
end
for i = 1:4
    for j = i+1:4
        cross = base.priorCorrelation(blockIndex{i}, blockIndex{j});
        if any(abs(cross(:)) > 1e-14)
            error('SHT:SteadyUQC:CrossBlockPriorCorrelation', ...
                '物理块%d与%d存在跨块先验相关，当前块pCN不适用。', i, j);
        end
    end
end

core = struct('schemaVersion','steady_model_uq_method_c_contract_v5', ...
    'baseContractHash',base.contractHash, ...
    'auxiliaryContractHash',auxiliary.contractHash, ...
    'parameterNames',{cellstr(base.parameterTable.name)}, ...
    'nuisanceNames',{cellstr(auxiliary.parameterTable.name(nuisanceIndex))}, ...
    'blockIndex',{blockIndex},'kernelWeights',cfg.kernelWeights, ...
    'pilotTargetEssFraction',cfg.smcPilotTargetEssFraction, ...
    'formalTargetEssFraction',cfg.smcFormalTargetEssFraction, ...
    'samplerDesign','proposal_to_posterior_geometric_bridge_smc', ...
    'marginalization','two_anchor_moment_linearized_gaussian');
if cfg.modelMode==0
    % 新合同还绑定边缘化与移动算法源码，避免仅字典相同便复用旧目标。
    files={'sht_steady_model_uq_c_common.m','sht_steady_model_uq_c_smc.m', ...
        'Start_SteadyModelUQ_C_02_NuisanceMarginalization.m', ...
        'Start_SteadyModelUQ_C_03_ProposalGeometry.m', ...
        'Start_SteadyModelUQ_C_04_BlockPilot.m', ...
        'Start_SteadyModelUQ_C_05_FormalPosterior.m','sht_uq_physical_blocks.m'};
    hashes=cell(size(files));root=fileparts(mfilename('fullpath'));
    for j=1:numel(files)
        hashes{j}=sht_steady_model_uq_common('filehash',fullfile(root,files{j}));
    end
    core.runtimeCodeHashes=hashes;
    core.nuisancePriorScale=cfg.nuisancePriorScale;
    core.nuisanceAnchorMode=cfg.nuisanceAnchorMode;
    extraFiles={'sht_tc24_uq_method_d.m','sht_tc24_uq_anchor_check.m', ...
        'sht_tc24_uq_d_correction.m'};
    for j=1:numel(extraFiles)
        core.r042CodeHashes{j}=sht_steady_model_uq_common('filehash',fullfile(root,extraFiles{j}));
    end
end
methodHash = local_text_hash(jsonencode(core));

contract = base;
contract.schemaVersion = core.schemaVersion;
contract.config = cfg;
contract.contractHash = methodHash;
contract.baseContractHash = base.contractHash;
contract.auxiliaryContractHash = auxiliary.contractHash;
contract.baseContract = base;
contract.auxiliaryContract = auxiliary;
contract.nuisanceParameterIndex = nuisanceIndex;
contract.nuisanceParameterTable = auxiliary.parameterTable(nuisanceIndex,:);
contract.parameterBlockIndex = blockIndex;
contract.parameterBlockTable = table((1:5).', blockName, blockCount, ...
    cfg.kernelWeights(:), 'VariableNames', ...
    {'kernel_index','kernel_name','parameter_count','proposal_fraction'});
contract.methodName = ...
    ['method_c_',cfg.route,'_marginalized_nuisance_proposal_bridge_block_pcn_smc'];
contract.nuisanceMarginalization = ...
    'two_anchor_moment_linearized_gaussian_covariance';
contract.explicitPosteriorDimension = nBase;
contract.marginalizedNuisanceDimension = numel(nuisanceIndex);
contract.priorMeanIsZero = all(abs(contract.priorMean) < 1e-14);
contract.deterministicEstimateRole = ...
    'proposal_and_linearization_anchor_only_not_prior_center';
contract.sharedExactResidualCache = base.cacheFile;
contract.truthAccessAllowedBeforeStep6 = false;
contract.testAccessAllowedBeforeStep6 = false;
end

function output = local_evaluate(contract, thetaMatrix, data, options)
if nargin < 3 || isempty(data), data = contract.trainingData; end
if nargin < 4 || isempty(options), options = struct(); end
% 缓存按方法A物理合同哈希绑定。方法C只改变似然协方差，
% 不改变给定显式参数时的DLL残差，因此复用该缓存不会混用后验。
output = sht_steady_model_uq_common('evaluate', ...
    contract.baseContract, thetaMatrix, data, options);
output.methodCContractHash = contract.contractHash;
end

function output = local_evaluate_nuisance( ...
        contract, baseTheta, nuisanceMatrix, data, options)
if nargin < 4 || isempty(data), data = contract.trainingData; end
if nargin < 5 || isempty(options), options = struct(); end
baseTheta = baseTheta(:);
if numel(baseTheta) ~= contract.parameterCount
    error('SHT:SteadyUQC:BadBaseTheta', ...
        '干扰参数回放的显式参数必须为%d维。',contract.parameterCount);
end
if size(nuisanceMatrix, 1) ~= contract.marginalizedNuisanceDimension
    error('SHT:SteadyUQC:BadNuisanceMatrix', ...
        '干扰参数候选矩阵必须为%d行。',contract.marginalizedNuisanceDimension);
end
n = size(nuisanceMatrix, 2);
joint = [repmat(baseTheta, 1, n); nuisanceMatrix];
output = sht_steady_model_uq_b_common('evaluate', ...
    contract.auxiliaryContract, joint, data, options);
output.baseTheta = baseTheta;
output.nuisanceTheta = nuisanceMatrix;
end

function [meanValue, varianceValue] = local_truncated_moments( ...
        meanInput, sigma, lower, upper)
meanInput = meanInput(:);
sigma = sigma(:);
lower = lower(:);
upper = upper(:);
if any(sigma <= 0) || ~isequal(size(meanInput),size(sigma), ...
        size(lower),size(upper))
    error('SHT:SteadyUQC:BadTruncatedNormalDefinition', ...
        '截断正态分布参数维度不一致或标准差非正。');
end
alpha = (lower-meanInput)./sigma;
beta = (upper-meanInput)./sigma;
phiAlpha = exp(-0.5*alpha.^2)/sqrt(2*pi);
phiBeta = exp(-0.5*beta.^2)/sqrt(2*pi);
normalizer = 0.5*erfc(-beta/sqrt(2)) - ...
    0.5*erfc(-alpha/sqrt(2));
if any(normalizer <= 0)
    error('SHT:SteadyUQC:TruncatedNormalMass', ...
        '截断正态分布在硬边界内没有有效概率质量。');
end
standardMean = (phiAlpha-phiBeta)./normalizer;
alphaPhi=alpha.*phiAlpha;betaPhi=beta.*phiBeta;
alphaPhi(~isfinite(alpha))=0;betaPhi(~isfinite(beta))=0;
standardVariance = 1 + ...
    (alphaPhi-betaPhi)./normalizer - standardMean.^2;
meanValue = meanInput + sigma.*standardMean;
varianceValue = sigma.^2.*max(standardVariance,0);
end

function factor = local_factor_covariance(covariance, name)
covariance = 0.5*(covariance+covariance.');
dimension = size(covariance,1);
if size(covariance,2) ~= dimension || any(~isfinite(covariance(:)))
    error('SHT:SteadyUQC:BadCovariance', ...
        '协方差%s必须为有限对称方阵。', name);
end
reference = max(mean(diag(covariance)), eps);
jitter = 0;
for attempt = 1:12
    [cholLower, flag] = chol(covariance+jitter*eye(dimension), 'lower');
    if flag == 0, break; end
    if jitter == 0
        jitter = 1e-12*reference;
    else
        jitter = 10*jitter;
    end
end
if flag ~= 0
    error('SHT:SteadyUQC:CovarianceCholeskyFailed', ...
        '协方差%s经适度jitter后仍无法Cholesky分解。', name);
end
factor = struct('name',char(name), ...
    'covariance',covariance+jitter*eye(dimension), ...
    'cholLower',cholLower,'jitter',jitter, ...
    'logDeterminant',2*sum(log(diag(cholLower))));
end

function hash = local_text_hash(text)
digest = java.security.MessageDigest.getInstance('SHA-256');
digest.update(uint8(unicode2native(char(text), 'UTF-8')));
raw = typecast(digest.digest(), 'uint8');
hash = lower(reshape(dec2hex(raw,2).',1,[]));
end

function value = local_option(options, name, defaultValue)
if isstruct(options) && isfield(options, name) && ~isempty(options.(name))
    value = options.(name);
else
    value = defaultValue;
end
end
