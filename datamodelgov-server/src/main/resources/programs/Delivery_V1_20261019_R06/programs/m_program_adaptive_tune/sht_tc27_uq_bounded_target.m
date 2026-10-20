function out=sht_tc27_uq_bounded_target(action,varargin)
%SHT_TC27_UQ_BOUNDED_TARGET 有界附加参数的C似然，不改变D近似。
% 原始独立截断正态先验经局部仿射响应积分。不能用截断先验的均值、
% 方差代替整个分布后再宣称物理边界仍被严格满足。
switch action
    case 'build',out=build(varargin{:});
    case 'evaluate',out=evaluate(varargin{:});
    otherwise,error('未知有界似然动作。');
end
end

function t=build(c,model)
assert(strcmp(c.options.nuisanceAnchorMode,'reference'),'有界C要求单个明确的附加参数线性化参考点。');
t=model;G=model.nuisanceJacobian;V=diag(c.nuisance.sigma.^2);
factor=model.factor;factor(:,model.nuisanceFactorColumns)=[];
other=refactor(model,factor);
G0=sht_tc27_uq_whiten(other,G,false);
precision=diag(1./c.nuisance.sigma.^2)+G0.'*G0;
R=chol((precision+precision.')/2);S=R\(R.'\eye(size(R)));
t=refactor(t,[factor,G.*c.nuisance.sigma.']);
t.shift=model.shift-G*c.nuisance.mean;
Gw=sht_tc27_uq_whiten(t,G,false);
t.conditionalGain=-V*Gw.';t.conditionalCovariance=(S+S.')/2;
t.lower=c.nuisance.lower;t.upper=c.nuisance.upper;
a=t.lower./c.nuisance.sigma;b=t.upper./c.nuisance.sigma;
t.logPriorBox=sum(log(.5*erfc(-b/sqrt(2))-.5*erfc(-a/sqrt(2))));
t.integrationCount=c.options.cBoxIntegrationCount;t.integrationSeed=c.options.randomSeed+701;
t.drawCount=c.options.cConditionalDrawCount;
t.targetDefinition='original_bounded_nuisance_prior_local_affine_marginal';
end
function model=refactor(model,factor)
old=sht_tc27_uq_base_transform(model,model.factor,false);s=svd(old,'econ');
baseLogDet=model.logDet-sum(log1p(s.^2));
f=sht_tc27_uq_base_transform(model,factor,false);[U,S,~]=svd(f,'econ');s=diag(S);s=s(:);keep=s>1e-10;
model.factor=factor;model.U=U(:,keep);model.shrink=1-1./sqrt(1+s(keep).^2);
model.logDet=baseLogDet+sum(log1p(s.^2));
end
function out=evaluate(t,residual,withDraws)
if nargin<3,withDraws=false;end
w=sht_tc27_uq_whiten(t,residual);count=size(w,2);
out=struct('logLikelihood',-Inf(1,count),'logBoxProbability',nan(1,count), ...
    'integrationDeltaLog',nan(1,count),'integrationESS',nan(1,count));
out.gaussianLogLikelihood=-.5*sum(w.^2,1);out.conditionalMean=zeros(numel(t.lower),count);
if withDraws,out.nuisanceDraws=zeros(numel(t.lower),t.drawCount,count);end
for k=1:count
    if ~all(isfinite(w(:,k))),continue;end
    m=t.conditionalGain*w(:,k);draws=0;if withDraws,draws=t.drawCount;end
    % 512点序列是1024点的同种子前缀；一次高精度积分同时保留原精度对照。
    % 不减少积分点数、不改变有界先验，也不把矩高斯近似移入C目标。
    high=sht_tc27_normal_box(m,t.conditionalCovariance,t.lower,t.upper, ...
        2*t.integrationCount,t.integrationSeed,draws,t.integrationCount);
    out.logBoxProbability(k)=high.logProbability;
    out.logLikelihood(k)=out.gaussianLogLikelihood(k)+high.logProbability-t.logPriorBox;
    out.integrationDeltaLog(k)=high.logProbability-high.coarseLogProbability;
    out.integrationESS(k)=high.integrationESS;out.conditionalMean(:,k)=high.mean;
    if withDraws,out.nuisanceDraws(:,:,k)=high.draws;end
end
end
