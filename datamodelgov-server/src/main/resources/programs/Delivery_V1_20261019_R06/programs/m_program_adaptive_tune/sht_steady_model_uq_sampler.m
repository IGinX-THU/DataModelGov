function varargout = sht_steady_model_uq_sampler(action, varargin)
%SHT_STEADY_MODEL_UQ_SAMPLER 精确贝叶斯采样与诊断公共函数。
%
% 本函数同时提供相关截断先验、先验潜变量变换、防御性提议及加权样本
% 诊断。点估计只改善提议效率，不会通过提议改变贝叶斯目标。

switch lower(char(action))
    case 'buildprior'
        varargout{1} = local_build_prior(varargin{:});
    case 'sampleprior'
        varargout{1} = local_sample_prior(varargin{:});
    case 'logprior'
        varargout{1} = local_log_prior(varargin{:});
    case 'thetatolatent'
        varargout{1} = local_theta_to_latent(varargin{:});
    case 'latenttotheta'
        varargout{1} = local_latent_to_theta(varargin{:});
    case 'buildinitialproposal'
        varargout{1} = local_build_initial_proposal(varargin{:});
    case 'adaptproposal'
        varargout{1} = local_adapt_proposal(varargin{:});
    case 'sampleproposal'
        varargout{1} = local_sample_proposal(varargin{:});
    case 'logproposal'
        varargout{1} = local_log_proposal(varargin{:});
    case 'importanceweights'
        [varargout{1:nargout}] = local_importance_weights(varargin{:});
    case 'diagnostics'
        varargout{1} = local_diagnostics(varargin{:});
    case 'summary'
        varargout{1} = local_summary(varargin{:});
    case 'resample'
        varargout{1} = local_resample(varargin{:});
    case 'weightedquantile'
        varargout{1} = local_weighted_quantile(varargin{:});
    case 'selftest'
        varargout{1} = local_self_test(varargin{:});
    otherwise
        error('SHT:SteadyUQ:UnknownSamplerAction', ...
            '未知采样器动作：%s。', action);
end
end

function prior = local_build_prior(contract, priorType)
if nargin < 2 || isempty(priorType)
    priorType = contract.priorType;
end
prior = struct('type', char(priorType), 'dimension', contract.parameterCount, ...
    'lower', contract.lowerBound(:), 'upper', contract.upperBound(:), ...
    'mean', contract.priorMean(:), 'sigma', contract.priorSigma(:));
if strcmp(prior.type, 'independent_truncated_normal') || ...
        strcmp(prior.type, 'gaussian_copula_truncated_normal')
    a = (prior.lower - prior.mean) ./ prior.sigma;
    b = (prior.upper - prior.mean) ./ prior.sigma;
    prior.standardizedLower = a;
    prior.standardizedUpper = b;
    prior.normalization = local_normcdf(b) - local_normcdf(a);
    if any(prior.normalization <= 0)
        error('SHT:SteadyUQ:BadPriorNormalization', '截断正态先验归一化失败。');
    end
    if strcmp(prior.type, 'gaussian_copula_truncated_normal')
        R = contract.priorCorrelation;
        if any(size(R) ~= prior.dimension) || ...
                max(max(abs(R - R.'))) > 1e-10
            error('SHT:SteadyUQ:BadPriorCorrelation', ...
                '相关先验矩阵尺寸或对称性错误。');
        end
        [L, flag] = chol(R, 'lower');
        if flag ~= 0
            error('SHT:SteadyUQ:BadPriorCorrelation', ...
                '相关先验矩阵不是正定矩阵。');
        end
        prior.correlation = R;
        prior.cholCorrelation = L;
        prior.inverseCorrelation = R \ eye(prior.dimension);
        prior.logDetCorrelation = 2 * sum(log(diag(L)));
        prior.covariance = contract.priorCovariance;
    else
        prior.correlation = eye(prior.dimension);
        prior.cholCorrelation = eye(prior.dimension);
        prior.inverseCorrelation = eye(prior.dimension);
        prior.logDetCorrelation = 0;
        prior.covariance = diag(prior.sigma.^2);
    end
elseif strcmp(prior.type, 'independent_uniform')
    prior.normalization = prior.upper - prior.lower;
    prior.correlation = eye(prior.dimension);
    prior.cholCorrelation = eye(prior.dimension);
    prior.inverseCorrelation = eye(prior.dimension);
    prior.logDetCorrelation = 0;
    prior.covariance = diag((prior.upper-prior.lower).^2/12);
else
    error('SHT:SteadyUQ:BadPriorType', '不支持先验类型%s。', prior.type);
end
end

function theta = local_sample_prior(prior, count, seed)
if nargin >= 3 && ~isempty(seed), rng(seed, 'twister'); end
d = prior.dimension;
if strcmp(prior.type, 'independent_uniform')
    theta = prior.lower + (prior.upper - prior.lower) .* rand(d, count);
    return;
end
if strcmp(prior.type, 'gaussian_copula_truncated_normal')
    latent = prior.cholCorrelation * randn(d, count);
    probability = min(max(local_normcdf(latent), 1e-14), 1-1e-14);
else
    probability = rand(d, count);
end
theta = zeros(d, count);
for j = 1:d
    a = local_normcdf((prior.lower(j) - prior.mean(j)) / prior.sigma(j));
    b = local_normcdf((prior.upper(j) - prior.mean(j)) / prior.sigma(j));
    u = a + (b - a) * probability(j, :);
    theta(j, :) = prior.mean(j) + prior.sigma(j) * local_norminv(u);
end
end

function value = local_log_prior(prior, theta)
inside = all(theta >= prior.lower & theta <= prior.upper, 1) & ...
    all(isfinite(theta), 1);
value = -inf(1, size(theta, 2));
if strcmp(prior.type, 'independent_uniform')
    value(inside) = -sum(log(prior.upper - prior.lower));
else
    zMarginal = (theta(:, inside) - prior.mean) ./ prior.sigma;
    value(inside) = sum(-0.5*zMarginal.^2 - log(prior.sigma) ...
        - 0.5*log(2*pi) - log(prior.normalization), 1);
    if strcmp(prior.type, 'gaussian_copula_truncated_normal')
        marginalProbability = (local_normcdf(zMarginal) - ...
            local_normcdf(prior.standardizedLower)) ./ prior.normalization;
        marginalProbability = min(max(marginalProbability, 1e-14), 1-1e-14);
        zCopula = local_norminv(marginalProbability);
        quadratic = sum(zCopula .* ...
            ((prior.inverseCorrelation-eye(prior.dimension))*zCopula), 1);
        value(inside) = value(inside) - 0.5*quadratic ...
            - 0.5*prior.logDetCorrelation;
    end
end
end

function latent = local_theta_to_latent(prior, theta)
% 将有界相关先验样本映射到独立标准正态坐标，供pCN先验保持移动使用。
if size(theta,1) ~= prior.dimension || ...
        any(~isfinite(theta(:))) || ...
        any(any(theta <= prior.lower | theta >= prior.upper))
    error('SHT:SteadyUQ:BadThetaForLatentTransform', ...
        'theta必须为严格位于边界内的%d行有限矩阵。',prior.dimension);
end
if strcmp(prior.type,'independent_uniform')
    probability = (theta-prior.lower)./(prior.upper-prior.lower);
else
    zMarginal = (theta-prior.mean)./prior.sigma;
    probability = (local_normcdf(zMarginal)- ...
        local_normcdf(prior.standardizedLower))./prior.normalization;
end
probability = min(max(probability,1e-14),1-1e-14);
correlatedLatent = local_norminv(probability);
latent = prior.cholCorrelation \ correlatedLatent;
end

function theta = local_latent_to_theta(prior, latent)
% 独立标准正态坐标到有界相关先验参数的严格逆映射。
if size(latent,1) ~= prior.dimension || any(~isfinite(latent(:)))
    error('SHT:SteadyUQ:BadLatentForThetaTransform', ...
        'latent必须为%d行有限矩阵。',prior.dimension);
end
correlatedLatent = prior.cholCorrelation*latent;
probability = min(max(local_normcdf(correlatedLatent),1e-14),1-1e-14);
if strcmp(prior.type,'independent_uniform')
    theta = prior.lower+(prior.upper-prior.lower).*probability;
else
    marginalProbability = local_normcdf(prior.standardizedLower)+ ...
        prior.normalization.*probability;
    theta = prior.mean+prior.sigma.*local_norminv(marginalProbability);
end
end

function proposal = local_build_initial_proposal(prior, thetaHat, localCovariance)
range = prior.upper - prior.lower;
thetaHat = min(max(thetaHat(:), prior.lower + 1e-9*range), ...
    prior.upper - 1e-9*range);
[zHat, derivative] = local_to_logit(thetaHat, prior);
if nargin < 3 || isempty(localCovariance) || ...
        any(size(localCovariance) ~= prior.dimension)
    localCovariance = diag((2 * prior.sigma).^2);
end
covZ = diag(derivative) * localCovariance * diag(derivative);
% 高维窄后验中，直接按两倍局部标准差抽样会使典型样本同时在多个
% 可辨识方向偏离高概率区。局部协方差仅作为提议，首轮取0.4倍标准差；
% 原先验、均匀和宽logit高斯仍保留30%权重，继续承担全局/多峰搜索。
covZ = local_regularize_covariance(0.16 * covZ, 1e-8);
zeroTheta = min(max(prior.mean, prior.lower + 1e-6*range), ...
    prior.upper - 1e-6*range);
boundaryCenter=prior.mean<=prior.lower | prior.mean>=prior.upper;
if any(boundaryCenter)
    a=local_normcdf((prior.lower-prior.mean)./prior.sigma);
    b=local_normcdf((prior.upper-prior.mean)./prior.sigma);
    medianTheta=prior.mean+prior.sigma.*local_norminv((a+b)/2);
    zeroTheta(boundaryCenter)=medianTheta(boundaryCenter);
end
zGlobal = local_to_logit(zeroTheta, prior);

component = repmat(local_empty_component(), 4, 1);
component(1) = struct('type','prior','weight',0.15, ...
    'meanZ',[],'covarianceZ',[],'cholZ',[],'logDetZ',NaN);
component(2) = struct('type','uniform','weight',0.05, ...
    'meanZ',[],'covarianceZ',[],'cholZ',[],'logDetZ',NaN);
component(3) = local_gaussian_component(zGlobal, 2.75^2*eye(prior.dimension), 0.10);
component(4) = local_gaussian_component(zHat, covZ, 0.70);
proposal = local_finalize_proposal(component, prior, 'initial_defensive');
end

function proposal = local_adapt_proposal( ...
        prior, theta, weights, thetaHat, localCovariance)
weights = weights(:) / sum(weights);
[z, ~] = local_to_logit(theta, prior);
[modeIndex, modeCount, modeMass] = local_weighted_modes(z, weights, 3);

component = repmat(local_empty_component(), 0, 1);
component(end + 1) = struct('type','prior','weight',0.12, ...
    'meanZ',[],'covarianceZ',[],'cholZ',[],'logDetZ',NaN);
component(end + 1) = struct('type','uniform','weight',0.03, ...
    'meanZ',[],'covarianceZ',[],'cholZ',[],'logDetZ',NaN);
globalMean = sum(z .* weights.', 2);
component(end + 1) = local_gaussian_component( ...
    globalMean, 2.0^2*eye(prior.dimension), 0.05);

range = prior.upper - prior.lower;
thetaHat = min(max(thetaHat(:), prior.lower + 1e-9*range), ...
    prior.upper - 1e-9*range);
[zHat, derivative] = local_to_logit(thetaHat, prior);
if isempty(localCovariance)
    localCovariance = diag(prior.sigma.^2);
end
laplaceCovZ = diag(derivative) * localCovariance * diag(derivative);
component(end + 1) = local_gaussian_component( ...
    zHat, local_regularize_covariance(0.25*laplaceCovZ, 1e-8), 0.30);

remainingWeight = 0.50;
for k = 1:modeCount
    member = modeIndex == k;
    wk = weights(member);
    wk = wk / sum(wk);
    zk = z(:, member);
    center = sum(zk .* wk.', 2);
    centered = zk - center;
    covariance = centered * (centered .* wk.').';
    % 精确先导ESS较小时，纯样本协方差会退化为低秩。以局部曲率协方差
    % 补足未被少量高权重点覆盖的方向，同时保留样本识别出的相关结构。
    covariance = 1.25*covariance + 0.20*laplaceCovZ;
    covariance = local_regularize_covariance(covariance, 1e-7);
    component(end + 1) = local_gaussian_component( ...
        center, covariance, remainingWeight * modeMass(k));
end
proposal = local_finalize_proposal(component, prior, ...
    sprintf('adapted_%d_mode_defensive', modeCount));
proposal.modeCount = modeCount;
proposal.modeMass = modeMass;
end

function theta = local_sample_proposal(proposal, count, seed)
if nargin >= 3 && ~isempty(seed), rng(seed, 'twister'); end
weights = [proposal.component.weight];
edges = cumsum(weights);
selector = rand(1, count);
theta = zeros(proposal.prior.dimension, count);
for c = 1:numel(proposal.component)
    if c == 1
        selected = selector <= edges(c);
    else
        selected = selector <= edges(c) & selector > edges(c-1);
    end
    idx = find(selected);
    if isempty(idx), continue; end
    item = proposal.component(c);
    switch item.type
        case 'prior'
            theta(:, idx) = local_sample_prior(proposal.prior, numel(idx), []);
        case 'uniform'
            theta(:, idx) = proposal.prior.lower + ...
                (proposal.prior.upper - proposal.prior.lower) .* ...
                rand(proposal.prior.dimension, numel(idx));
        case 'logit_gaussian'
            z = item.meanZ + item.cholZ * randn(proposal.prior.dimension, numel(idx));
            theta(:, idx) = local_from_logit(z, proposal.prior);
        otherwise
            error('SHT:SteadyUQ:BadProposalComponent', ...
                '未知提议分量%s。', item.type);
    end
end
end

function value = local_log_proposal(proposal, theta)
n = size(theta, 2);
logComponent = -inf(numel(proposal.component), n);
for c = 1:numel(proposal.component)
    item = proposal.component(c);
    switch item.type
        case 'prior'
            density = local_log_prior(proposal.prior, theta);
        case 'uniform'
            inside = all(theta >= proposal.prior.lower & ...
                theta <= proposal.prior.upper, 1);
            density = -inf(1, n);
            density(inside) = -sum(log(proposal.prior.upper - proposal.prior.lower));
        case 'logit_gaussian'
            [z, derivative] = local_to_logit(theta, proposal.prior);
            delta = item.cholZ \ (z - item.meanZ);
            logZ = -0.5*sum(delta.^2, 1) - 0.5*item.logDetZ ...
                - 0.5*proposal.prior.dimension*log(2*pi);
            logJacobian = sum(log(derivative), 1);
            density = logZ + logJacobian;
            density(~all(isfinite(z), 1)) = -inf;
        otherwise
            error('SHT:SteadyUQ:BadProposalComponent', ...
                '未知提议分量%s。', item.type);
    end
    logComponent(c, :) = log(item.weight) + density;
end
value = local_logsumexp(logComponent, 1);
end

function [weights, logNormalizer, logRawWeight] = local_importance_weights( ...
        logPrior, logLikelihood, logProposal)
logRawWeight = logPrior + logLikelihood - logProposal;
finite = isfinite(logRawWeight);
if ~any(finite)
    error('SHT:SteadyUQ:AllImportanceWeightsInvalid', ...
        '全部重要性权重无效。');
end
maximum = max(logRawWeight(finite));
raw = zeros(size(logRawWeight));
raw(finite) = exp(logRawWeight(finite) - maximum);
weights = raw / sum(raw);
logNormalizer = maximum + log(sum(raw)) - log(numel(logRawWeight));
end

function diagnostic = local_diagnostics(theta, weights, logRawWeight, prior)
weights = weights(:) / sum(weights);
n = numel(weights);
ess = 1 / sum(weights.^2);
maximumWeight = max(weights);
paretoK = local_pareto_k(logRawWeight);
meanValue = theta * weights;
centered = theta - meanValue;
variance = sum(centered.^2 .* weights.', 2);
mcseMean = sqrt(max(variance, 0) / max(ess, 1));
mcseRatio = mcseMean ./ max(sqrt(variance), eps);

batchCount = min(4, floor(n/20));
batchMean = nan(prior.dimension, batchCount);
for b = 1:batchCount
    idx = b:batchCount:n;
    wb = weights(idx);
    if sum(wb) > 0
        wb = wb / sum(wb);
        batchMean(:, b) = theta(:, idx) * wb;
    end
end
batchSpread = max(batchMean, [], 2) - min(batchMean, [], 2);
batchSpreadRatio = batchSpread ./ max(sqrt(variance), eps);
[modeIndex, modeCount, modeMass] = local_weighted_modes( ...
    local_to_logit(theta, prior), weights, 3);

diagnostic = struct();
diagnostic.sampleCount = n;
diagnostic.effectiveSampleSize = ess;
diagnostic.effectiveSampleFraction = ess / n;
diagnostic.importanceEss = ess;
diagnostic.importanceEssFraction = ess / n;
diagnostic.maximumNormalizedWeight = maximumWeight;
diagnostic.paretoKApprox = paretoK;
diagnostic.meanMcse = mcseMean;
diagnostic.maximumMeanMcseToSd = max(mcseRatio);
diagnostic.batchMean = batchMean;
diagnostic.maximumBatchSpreadToSd = max(batchSpreadRatio);
diagnostic.modeIndex = modeIndex;
diagnostic.modeCount = modeCount;
diagnostic.modeMass = modeMass;
end

function tbl = local_summary(theta, weights, contract)
weights = weights(:) / sum(weights);
meanValue = theta * weights;
medianValue = zeros(contract.parameterCount, 1);
lowerValue = zeros(contract.parameterCount, 1);
upperValue = zeros(contract.parameterCount, 1);
stdValue = zeros(contract.parameterCount, 1);
priorLower = zeros(contract.parameterCount, 1);
priorUpper = zeros(contract.parameterCount, 1);
prior = local_build_prior(contract, contract.priorType);
priorSample = local_sample_prior(prior, 50000, 8137);
for j = 1:contract.parameterCount
    posteriorQuantile = local_weighted_quantile( ...
        theta(j, :), weights, [0.025,0.5,0.975]);
    lowerValue(j) = posteriorQuantile(1);
    medianValue(j) = posteriorQuantile(2);
    upperValue(j) = posteriorQuantile(3);
    stdValue(j) = sqrt(sum(weights.' .* (theta(j, :) - meanValue(j)).^2));
    pq = sht_quantile_vector(priorSample(j, :), [0.025,0.975]);
    priorLower(j) = pq(1);
    priorUpper(j) = pq(2);
end
intervalWidth = upperValue - lowerValue;
priorWidth = priorUpper - priorLower;
shrinkagePct = 100 * (1 - intervalWidth ./ priorWidth);
pointEstimate = contract.thetaHat;
tbl = table(contract.parameterTable.index, contract.parameterTable.name, ...
    contract.parameterTable.unit, pointEstimate, meanValue, medianValue, ...
    stdValue, lowerValue, upperValue, priorLower, priorUpper, ...
    intervalWidth, shrinkagePct, ...
    'VariableNames', {'index','name','unit','deterministic_estimate', ...
    'posterior_mean','posterior_median','posterior_std','q025','q975', ...
    'prior_q025','prior_q975','credible_width','interval_shrinkage_pct'});
end

function sample = local_resample(theta, weights, count, seed)
if nargin >= 4 && ~isempty(seed), rng(seed, 'twister'); end
weights = weights(:) / sum(weights);
edges = cumsum(weights);
u0 = rand / count;
u = u0 + (0:(count-1)) / count;
index = zeros(1, count);
j = 1;
for i = 1:count
    while u(i) > edges(j), j = j + 1; end
    index(i) = j;
end
sample = theta(:, index);
end

function q = local_weighted_quantile(value, weights, probability)
value = value(:);
weights = weights(:);
[validValue, validWeight] = deal(isfinite(value), isfinite(weights));
valid = validValue & validWeight & weights > 0;
value = value(valid);
weights = weights(valid);
if isempty(value)
    error('SHT:SteadyUQ:InvalidWeightedSample', ...
        '加权分位数计算没有可用的有限正权重样本。');
end
[value, order] = sort(value);
weights = weights(order);
weights = weights / sum(weights);
cumulative = cumsum(weights);

% 极小权重可能因浮点舍入而不改变累计概率。保留每个累计概率的
% 最后一个样本，使 interp1 的横坐标严格递增，同时保留分布右端点。
keep = [diff(cumulative) > 0; true];
cumulative = cumulative(keep);
value = value(keep);
cumulative(end) = 1;
probability = min(max(probability(:), 0), 1);
q = interp1([0; cumulative], [value(1); value], probability, ...
    'linear', 'extrap').';
end

function test = local_self_test(contract)
prior = local_build_prior(contract, contract.priorType);
theta = local_sample_prior(prior, 2000, 7171);
inside = all(theta > prior.lower & theta < prior.upper, 1);
logP = local_log_prior(prior, theta);
correlationError = NaN;
correlationPassed = true;
if strcmp(prior.type, 'gaussian_copula_truncated_normal')
    zMarginal = (theta-prior.mean)./prior.sigma;
    probability = (local_normcdf(zMarginal)- ...
        local_normcdf(prior.standardizedLower))./prior.normalization;
    probability = min(max(probability,1e-14),1-1e-14);
    latent = local_norminv(probability);
    empirical = corrcoef(latent.');
    correlationError = max(max(abs(empirical-prior.correlation)));
    correlationPassed = correlationError < 0.16;
end
proposal = local_build_initial_proposal(prior, contract.thetaHat, ...
    contract.priorCovariance);
candidate = local_sample_proposal(proposal, 2000, 7172);
logQ = local_log_proposal(proposal, candidate);
test = struct('priorSamplesInsideBounds', all(inside), ...
    'priorLogDensityFinite', all(isfinite(logP)), ...
    'priorCorrelationPassed',correlationPassed, ...
    'proposalSamplesInsideBounds', all(all(candidate > prior.lower & ...
        candidate < prior.upper, 1)), ...
    'proposalLogDensityFinite', all(isfinite(logQ)));
test.passed = all(structfun(@(x) logical(x), test));
test.maximumPriorCorrelationError = correlationError;
end

function component = local_gaussian_component(meanZ, covarianceZ, weight)
covarianceZ = local_regularize_covariance(covarianceZ, 1e-6);
[cholZ, flag] = chol(covarianceZ, 'lower');
if flag ~= 0
    error('SHT:SteadyUQ:ProposalCovariance', '提议协方差无法Cholesky分解。');
end
component = struct('type','logit_gaussian','weight',weight, ...
    'meanZ',meanZ(:),'covarianceZ',covarianceZ,'cholZ',cholZ, ...
    'logDetZ',2*sum(log(diag(cholZ))));
end

function component = local_empty_component()
component = struct('type','','weight',NaN,'meanZ',[],'covarianceZ',[], ...
    'cholZ',[],'logDetZ',NaN);
end

function proposal = local_finalize_proposal(component, prior, label)
weights = [component.weight];
if any(weights <= 0) || ~all(isfinite(weights))
    error('SHT:SteadyUQ:ProposalWeights', '提议权重必须为有限正数。');
end
weights = weights / sum(weights);
for i = 1:numel(component), component(i).weight = weights(i); end
proposal = struct('schemaVersion','steady_uq_proposal_v1', ...
    'label',label,'prior',prior,'component',component, ...
    'createdAt',datestr(now,30));
end

function covariance = local_regularize_covariance(covariance, floorFraction)
covariance = 0.5 * (covariance + covariance.');
[vector, value] = eig(covariance);
eigenvalue = real(diag(value));
finitePositive = eigenvalue(isfinite(eigenvalue) & eigenvalue > 0);
if isempty(finitePositive), reference = 1; else, reference = max(finitePositive); end
% floorFraction是相对最大谱值的比例，不是物理量绝对下限。使用绝对下限
% 会把真实窄方向错误放宽，是高维重要性权重退化的直接原因。
minimum = max(realmin('double'), floorFraction * reference);
eigenvalue(~isfinite(eigenvalue)) = minimum;
eigenvalue = max(eigenvalue, minimum);
covariance = real(vector * diag(eigenvalue) * vector.');
covariance = 0.5 * (covariance + covariance.');
end

function [z, derivative] = local_to_logit(theta, prior)
range = prior.upper - prior.lower;
u = (theta - prior.lower) ./ range;
inside = u > 0 & u < 1 & isfinite(u);
uSafe = min(max(u, realmin('double')), 1-realmin('double'));
z = log(uSafe ./ (1-uSafe));
z(~inside) = NaN;
derivative = 1 ./ (range .* uSafe .* (1-uSafe));
derivative(~inside) = NaN;
end

function theta = local_from_logit(z, prior)
u = zeros(size(z));
positive = z >= 0;
u(positive) = 1 ./ (1 + exp(-z(positive)));
ez = exp(z(~positive));
u(~positive) = ez ./ (1 + ez);
theta = prior.lower + (prior.upper-prior.lower) .* u;
end

function [index, count, mass] = local_weighted_modes(z, weights, maximumCount)
weights = weights(:) / sum(weights);
n = numel(weights);
if n < 20
    index = ones(n,1); count = 1; mass = 1; return;
end
bestIndex = ones(n, 1);
bestSse = local_weighted_sse(z, weights, bestIndex, 1);
count = 1;
for k = 2:maximumCount
    candidate = local_weighted_kmeans(z, weights, k);
    candidateMass = accumarray(candidate, weights, [k,1], @sum, 0);
    sse = local_weighted_sse(z, weights, candidate, k);
    improvement = (bestSse - sse) / max(bestSse, eps);
    if improvement < 0.30 || any(candidateMass < 0.05)
        break;
    end
    bestIndex = candidate;
    bestSse = sse;
    count = k;
end
index = bestIndex;
mass = accumarray(index, weights, [count,1], @sum, 0);
mass = mass / sum(mass);
end

function index = local_weighted_kmeans(z, weights, k)
n = size(z, 2);
[~, first] = max(weights);
center = zeros(size(z,1), k);
center(:,1) = z(:,first);
distance = sum((z-center(:,1)).^2,1);
for j = 2:k
    [~, next] = max(distance .* weights.');
    center(:,j) = z(:,next);
    distance = min(distance, sum((z-center(:,j)).^2,1));
end
index = ones(n,1);
for iteration = 1:40
    old = index;
    distance = zeros(n,k);
    for j = 1:k, distance(:,j) = sum((z-center(:,j)).^2,1).'; end
    [~,index] = min(distance,[],2);
    for j = 1:k
        member = index == j;
        if any(member)
            w = weights(member); w = w/sum(w);
            center(:,j) = z(:,member)*w;
        end
    end
    if isequal(index,old), break; end
end
end

function sse = local_weighted_sse(z, weights, index, count)
sse = 0;
for k = 1:count
    member = index == k;
    w = weights(member);
    if isempty(w), continue; end
    w = w/sum(w);
    center = z(:,member)*w;
    distance = sum((z(:,member)-center).^2,1).';
    sse = sse + sum(weights(member).*distance);
end
end

function k = local_pareto_k(logRawWeight)
value = logRawWeight(isfinite(logRawWeight));
n = numel(value);
tailCount = min(max(20, ceil(3*sqrt(n))), floor(0.20*n));
if tailCount < 5
    k = NaN; return;
end
value = sort(value, 'descend');
threshold = value(tailCount);
logRatio = value(1:tailCount-1) - threshold;
% Hill尾指数是PSIS Pareto-k的保守近似；正式报告显式保留“近似”标签。
k = mean(max(logRatio, 0));
end

function y = local_logsumexp(x, dimension)
maximum = max(x, [], dimension);
shifted = x - maximum;
shifted(~isfinite(shifted)) = -inf;
y = maximum + log(sum(exp(shifted), dimension));
y(~isfinite(maximum)) = -inf;
end

function p = local_normcdf(x)
p = 0.5 * erfc(-x / sqrt(2));
end

function x = local_norminv(p)
p = min(max(p, realmin('double')), 1-realmin('double'));
x = -sqrt(2) * erfcinv(2*p);
end
