function varargout = sht_steady_model_uq_likelihood(action, varargin)
%SHT_STEADY_MODEL_UQ_LIKELIHOOD 固定协方差精确高斯似然。
% 使用Cholesky白化计算，不显式求逆。无效DLL候选返回-logLik=Inf。

switch lower(char(action))
    case 'build'
        varargout{1} = local_build(varargin{:});
    case 'evaluate'
        [varargout{1:nargout}] = local_evaluate(varargin{:});
    otherwise
        error('SHT:SteadyUQ:UnknownLikelihoodAction', ...
            '未知似然动作：%s。', action);
end
end

function model = local_build(covarianceResult)
selected = covarianceResult.selected;
dimension = size(selected.covariance, 1);
model = struct();
model.schemaVersion = 'steady_uq_likelihood_v1';
model.covarianceScenario = selected.name;
model.dimension = dimension;
model.covariance = selected.covariance;
model.cholLower = selected.cholLower;
model.logDeterminant = selected.logDeterminant;
model.jitter = selected.jitter;
model.logNormalizingConstant = -0.5 * ...
    (selected.logDeterminant + dimension * log(2*pi));
end

function [logLikelihood, detail] = local_evaluate(model, residual, valid)
if size(residual, 1) ~= model.dimension
    error('SHT:SteadyUQ:LikelihoodDimension', ...
        '残差维数%d与似然维数%d不一致。', size(residual, 1), model.dimension);
end
n = size(residual, 2);
if nargin < 3 || isempty(valid)
    valid = all(isfinite(residual), 1);
end
valid = logical(valid(:).');
logLikelihood = -inf(1, n);
mahalanobisSquared = inf(1, n);
whitened = nan(size(residual));
idx = find(valid & all(isfinite(residual), 1));
if ~isempty(idx)
    centered=residual(:,idx);
    if isfield(model,'additiveResidualShift')
        centered=centered+model.additiveResidualShift;
    end
    whitened(:, idx) = model.cholLower \ centered;
    mahalanobisSquared(idx) = sum(whitened(:, idx).^2, 1);
    logLikelihood(idx) = model.logNormalizingConstant - ...
        0.5 * mahalanobisSquared(idx);
end
detail = struct('mahalanobisSquared', mahalanobisSquared, ...
    'whitenedResidual', whitened, 'valid', isfinite(logLikelihood));
end
