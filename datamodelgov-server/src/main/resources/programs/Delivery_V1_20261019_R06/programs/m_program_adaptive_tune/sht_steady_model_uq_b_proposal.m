function varargout = sht_steady_model_uq_b_proposal(action,varargin)
%SHT_STEADY_MODEL_UQ_B_PROPOSAL 方法B的先验潜空间防御混合提议。
%
% 提议在独立标准正态先验潜变量z中定义。全局分量严格等于N(0,I)；
% 局部分量只沿局部雅可比识别出的信息方向移动均值并缩小方差，局部
% 弱信息方向和结构无关方向仍保持N(0,1)。所有样本通过既有先验映射
% 转回物理参数，重要性权重中的变量变换Jacobian自动相消。

switch lower(char(action))
    case 'build'
        varargout{1} = local_build(varargin{:});
    case 'sample'
        [varargout{1:nargout}] = local_sample(varargin{:});
    case 'samplecomponent'
        [varargout{1:nargout}] = local_sample_component(varargin{:});
    case 'logdensity'
        varargout{1} = local_log_density(varargin{:});
    case 'logcomponentdensity'
        varargout{1} = local_log_component_density(varargin{:});
    case 'allocation'
        varargout{1} = local_balanced_allocation(varargin{:});
    case 'logpriorlatent'
        varargout{1} = local_standard_normal_log_density(varargin{:});
    case 'selftest'
        varargout{1} = local_self_test(varargin{:});
    otherwise
        error('SHT:SteadyUQB:UnknownLatentProposalAction', ...
            '未知方法B潜空间提议动作：%s。',action);
end
end

function proposal = local_build(prior,step5,user)
if nargin < 3 || isempty(user), user = struct(); end
activeIndex = step5.activeParameterIndex(:);
priorOnlyIndex = step5.structuralPriorOnlyParameterIndex(:);
if numel(activeIndex)+numel(priorOnlyIndex) ~= prior.dimension || ...
        ~isempty(intersect(activeIndex,priorOnlyIndex))
    error('SHT:SteadyUQB:LatentProposalPartition', ...
        '活动方向与解析先验方向没有构成完整且互斥的参数划分。');
end
basis = step5.activeLatentPcnBasis;
rankValue = step5.activeLatentInformedRank;
singularValue = step5.activeLatentSingularValues(:);
if numel(singularValue) < rankValue
    error('SHT:SteadyUQB:LatentProposalSingularValues', ...
        '活动潜空间奇异值数量小于信息秩。');
end

% 默认全局先验分量略高于SMC默认的50% ESS门限。用户可在正式入口
% 配置两类初始粒子的比例；全部样本仍通过p/q重要性权重恢复为原始
% 先验，局部参考点不会被偷换成贝叶斯先验。
priorWeight = local_option(user,'priorWeight',0.55);
% 1.50倍尺度在本问题42个信息方向上过宽，有限样本仍无法到达已知
% 高后验区。0.75倍局部曲率尺度经独立精确DLL预审可将参考差值压到
% 门限内；默认保留55%的原先验分量负责全局和潜在多峰覆盖。
inflation = local_option(user,'informedScaleInflation',0.75);
minimumScale = local_option(user,'minimumInformedScale',0.02);
if priorWeight <= 0 || priorWeight >= 1 || inflation <= 0 || ...
        minimumScale <= 0 || minimumScale > 1
    error('SHT:SteadyUQB:BadLatentProposalConfiguration', ...
        '潜空间提议权重、尺度膨胀或最小尺度配置无效。');
end

localLatent = sht_steady_model_uq_sampler( ...
    'thetatolatent',prior,step5.thetaLocal);
localCoordinate = basis.'*localLatent(activeIndex);
meanCoordinate = zeros(numel(activeIndex),1);
meanCoordinate(1:rankValue) = localCoordinate(1:rankValue);
scaleCoordinate = ones(numel(activeIndex),1);
laplaceScale = 1./sqrt(1+singularValue(1:rankValue).^2);
scaleCoordinate(1:rankValue) = min(1,max(minimumScale, ...
    inflation*laplaceScale));

proposal = struct( ...
    'schemaVersion','steady_uq_b_prior_latent_defensive_v1', ...
    'prior',prior,'dimension',prior.dimension, ...
    'activeIndex',activeIndex,'priorOnlyIndex',priorOnlyIndex, ...
    'activeBasis',basis,'informedRank',rankValue, ...
    'meanCoordinate',meanCoordinate,'scaleCoordinate',scaleCoordinate, ...
    'priorWeight',priorWeight,'localWeight',1-priorWeight, ...
    'informedScaleInflation',inflation, ...
    'minimumInformedScale',minimumScale,'componentCount',2, ...
    'modeCount',1,'createdAt',datestr(now,30));
end

function [theta,latent,component,audit] = local_sample( ...
        proposal,count,seed,samplingMode)
if nargin >= 3 && ~isempty(seed), rng(seed,'twister'); end
if nargin < 4 || isempty(samplingMode), samplingMode = 'bernoulli'; end
if count < 1 || count ~= floor(count)
    error('SHT:SteadyUQB:BadLatentProposalSampleCount', ...
        '潜空间提议样本数必须为正整数。');
end
d = proposal.dimension;
switch lower(char(samplingMode))
    case 'bernoulli'
        % 兼容历史方法：每个粒子独立选择混合分量。
        latent = randn(d,count);
        component = ones(1,count);
        useLocal = rand(1,count) > proposal.priorWeight;
        component(useLocal) = 2;
        if any(useLocal)
            coordinate = proposal.meanCoordinate + ...
                proposal.scaleCoordinate.*randn( ...
                numel(proposal.activeIndex),nnz(useLocal));
            latent(proposal.activeIndex,useLocal) = ...
                proposal.activeBasis*coordinate;
        end
        densityWeight = [proposal.priorWeight,proposal.localWeight];
        allocation = local_allocation_from_labels( ...
            component,densityWeight,'bernoulli');
        useAntithetic = false;
    case {'fixed_count','deterministic_mixture'}
        % 固定各分量的整数配额，并按实际配额n_k/N计算混合密度。
        % deterministic_mixture还在每个分量内使用成对反向样本，
        % 降低有限粒子的一阶矩随机波动。
        allocation = local_balanced_allocation( ...
            [proposal.priorWeight,proposal.localWeight],count,0);
        component = allocation.component;
        useAntithetic = strcmpi(samplingMode,'deterministic_mixture');
        latent = zeros(d,count);
        for k = 1:proposal.componentCount
            index = find(component==k);
            [~,latent(:,index)] = local_sample_component( ...
                proposal,k,numel(index),[],useAntithetic);
        end
        densityWeight = allocation.actualWeight;
    otherwise
        error('SHT:SteadyUQB:BadProposalSamplingMode', ...
            '未知防御混合提议采样模式：%s。',char(samplingMode));
end
theta = sht_steady_model_uq_sampler( ...
    'latenttotheta',proposal.prior,latent);
audit = struct('samplingMode',lower(char(samplingMode)), ...
    'requestedWeight',[proposal.priorWeight,proposal.localWeight], ...
    'densityWeight',densityWeight,'componentCount', ...
    [nnz(component==1),nnz(component==2)], ...
    'actualWeight',[nnz(component==1),nnz(component==2)]/count, ...
    'antitheticWithinComponent',useAntithetic,'allocation',allocation);
end

function [theta,latent] = local_sample_component( ...
        proposal,component,count,seed,useAntithetic)
if nargin >= 4 && ~isempty(seed), rng(seed,'twister'); end
if nargin < 5 || isempty(useAntithetic), useAntithetic = false; end
if ~isscalar(component) || ~ismember(component,1:proposal.componentCount)
    error('SHT:SteadyUQB:BadProposalComponent', ...
        '提议分量编号必须为1至%d。',proposal.componentCount);
end
if count < 0 || count ~= floor(count)
    error('SHT:SteadyUQB:BadComponentSampleCount', ...
        '分量样本数必须为非负整数。');
end
latent = local_normal_draw(proposal.dimension,count,useAntithetic);
if component == 2 && count > 0
    coordinateNoise = local_normal_draw( ...
        numel(proposal.activeIndex),count,useAntithetic);
    coordinate = proposal.meanCoordinate + ...
        proposal.scaleCoordinate.*coordinateNoise;
    latent(proposal.activeIndex,:) = proposal.activeBasis*coordinate;
end
theta = sht_steady_model_uq_sampler( ...
    'latenttotheta',proposal.prior,latent);
end

function value = local_log_density(proposal,latent,mixtureWeight)
if size(latent,1) ~= proposal.dimension
    error('SHT:SteadyUQB:LatentProposalDimension', ...
        '潜变量矩阵必须为%d行。',proposal.dimension);
end
if nargin < 3 || isempty(mixtureWeight)
    mixtureWeight = [proposal.priorWeight,proposal.localWeight];
end
mixtureWeight = local_validate_mixture_weight( ...
    mixtureWeight,proposal.componentCount);
componentLogDensity = zeros(proposal.componentCount,size(latent,2));
for k = 1:proposal.componentCount
    componentLogDensity(k,:) = ...
        local_log_component_density(proposal,k,latent);
end
value = local_logsumexp(log(mixtureWeight(:))+componentLogDensity,1);
end

function value = local_log_component_density(proposal,component,latent)
if size(latent,1) ~= proposal.dimension
    error('SHT:SteadyUQB:LatentProposalDimension', ...
        '潜变量矩阵必须为%d行。',proposal.dimension);
end
switch component
    case 1
        value = local_standard_normal_log_density(latent);
    case 2
        coordinate = proposal.activeBasis.'*latent(proposal.activeIndex,:);
        standardized = (coordinate-proposal.meanCoordinate) ./ ...
            proposal.scaleCoordinate;
        logLocalActive = -0.5*sum(standardized.^2,1) - ...
            sum(log(proposal.scaleCoordinate)) - ...
            0.5*numel(proposal.activeIndex)*log(2*pi);
        if isempty(proposal.priorOnlyIndex)
            logLocalPriorOnly = zeros(1,size(latent,2));
        else
            zPriorOnly = latent(proposal.priorOnlyIndex,:);
            logLocalPriorOnly = -0.5*sum(zPriorOnly.^2,1) - ...
                0.5*numel(proposal.priorOnlyIndex)*log(2*pi);
        end
        value = logLocalActive+logLocalPriorOnly;
    otherwise
        error('SHT:SteadyUQB:BadProposalComponent', ...
            '提议分量编号必须为1或2。');
end
end

function value = local_standard_normal_log_density(latent)
value = -0.5*sum(latent.^2,1)-0.5*size(latent,1)*log(2*pi);
end

function audit = local_self_test(proposal,count,seed,samplingMode)
if nargin < 2 || isempty(count), count = 3000; end
if nargin < 3 || isempty(seed), seed = 20260822; end
if nargin < 4 || isempty(samplingMode), samplingMode = 'bernoulli'; end
[theta,latent,component,samplingAudit] = local_sample( ...
    proposal,count,seed,samplingMode);
logQ = local_log_density(proposal,latent,samplingAudit.densityWeight);
logPrior = local_standard_normal_log_density(latent);
logWeight = logPrior-logQ;
[weight,logMeanWeight] = local_normalize_log_weight(logWeight);
inside = all(theta>proposal.prior.lower & theta<proposal.prior.upper,1);
audit = struct('sampleCount',count,'allInsideBounds',all(inside), ...
    'allFinite',all(isfinite(theta(:))) && all(isfinite(logQ)), ...
    'priorComponentCount',nnz(component==1), ...
    'localComponentCount',nnz(component==2), ...
    'samplingMode',samplingAudit.samplingMode, ...
    'requestedMixtureWeight',samplingAudit.requestedWeight, ...
    'actualMixtureWeight',samplingAudit.actualWeight, ...
    'densityMixtureWeight',samplingAudit.densityWeight, ...
    'antitheticWithinComponent',samplingAudit.antitheticWithinComponent, ...
    'initialImportanceEss',1/sum(weight.^2), ...
    'initialImportanceEssFraction',1/(sum(weight.^2)*count), ...
    'logMeanPriorToProposalWeight',logMeanWeight, ...
    'passed',all(inside) && all(isfinite(logQ)) && ...
    nnz(component==1)>0 && nnz(component==2)>0);
end

function allocation = local_balanced_allocation(weight,count,phase)
if nargin < 3 || isempty(phase), phase = 0; end
weight = local_validate_mixture_weight(weight,numel(weight));
if count < numel(weight) || count ~= floor(count)
    error('SHT:SteadyUQB:BadAllocationCount', ...
        '固定配额样本数必须是不小于分量数的整数。');
end
target = count*weight;
componentCount = floor(target);
remainder = count-sum(componentCount);
fraction = target-componentCount;
[~,order] = sortrows([-fraction(:),(1:numel(weight)).'],[1,2]);
componentCount(order(1:remainder)) = componentCount(order(1:remainder))+1;
if any(componentCount==0)
    zeroIndex = find(componentCount==0);
    for i = 1:numel(zeroIndex)
        [~,donor] = max(componentCount);
        componentCount(donor) = componentCount(donor)-1;
        componentCount(zeroIndex(i)) = 1;
    end
end
component = local_balanced_component_sequence(componentCount);
if ~isempty(component)
    phase = mod(round(phase),numel(component));
    component = circshift(component,[0,phase]);
end
allocation = struct('requestedWeight',weight, ...
    'componentCount',componentCount,'actualWeight', ...
    componentCount/count,'component',component,'phase',phase);
end

function allocation = local_allocation_from_labels(component,weight,mode)
count = numel(component);
componentCount = zeros(1,numel(weight));
for k = 1:numel(weight)
    componentCount(k) = nnz(component==k);
end
allocation = struct('requestedWeight',weight, ...
    'componentCount',componentCount,'actualWeight', ...
    componentCount/max(count,1),'component',component, ...
    'phase',NaN,'mode',mode);
end

function component = local_balanced_component_sequence(componentCount)
count = sum(componentCount);
position = zeros(1,count);
label = zeros(1,count);
cursor = 0;
for k = 1:numel(componentCount)
    nk = componentCount(k);
    index = cursor+(1:nk);
    position(index) = ((1:nk)-0.5)/nk;
    label(index) = k;
    cursor = cursor+nk;
end
[~,order] = sortrows([position(:),label(:)],[1,2]);
component = label(order).';
end

function value = local_normal_draw(dimension,count,useAntithetic)
if count == 0
    value = zeros(dimension,0);
elseif ~useAntithetic
    value = randn(dimension,count);
elseif mod(count,2)==0
    half = randn(dimension,count/2);
    value = [half,-half];
else
    half = randn(dimension,(count-1)/2);
    value = [zeros(dimension,1),half,-half];
end
end

function weight = local_validate_mixture_weight(weight,componentCount)
weight = weight(:).';
if numel(weight) ~= componentCount || any(~isfinite(weight)) || ...
        any(weight<=0) || sum(weight)<=0
    error('SHT:SteadyUQB:BadMixtureWeight', ...
        '混合权重必须包含%d个有限正数。',componentCount);
end
weight = weight/sum(weight);
end

function [weight,logMeanWeight] = local_normalize_log_weight(logWeight)
maximum = max(logWeight);
raw = exp(logWeight-maximum);
weight = raw/sum(raw);
logMeanWeight = maximum+log(sum(raw))-log(numel(raw));
end

function value = local_logsumexp(input,dimension)
maximum = max(input,[],dimension);
value = maximum+log(sum(exp(input-maximum),dimension));
end

function value = local_option(options,name,defaultValue)
if isstruct(options) && isfield(options,name) && ~isempty(options.(name))
    value = options.(name);
else
    value = defaultValue;
end
end
