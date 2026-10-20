function varargout=sht_tc24_uq_c_bounded_likelihood(action,varargin)
% 原始截断正态附加先验的线性边缘化：高斯似然乘条件物理域概率。
% 主要健康参数仍通过完整DLL给出残差；不是把主后验改成高斯。
switch action
    case 'build',varargout{1}=local_build(varargin{:});
    case 'evaluate',[varargout{1:nargout}]=local_evaluate(varargin{:});
    otherwise,error('TC24:BoundedLikelihood:Action','未知动作%s。',action);
end
end

function model=local_build(step2,count,seed)
G=(step2.nuisanceJacobian{1}+step2.nuisanceJacobian{2})/2;
dg=step2.nuisanceJacobian{1}-step2.nuisanceJacobian{2};
V=diag(step2.nuisanceVariance);t=step2.nuisanceAuditTable;
V0=diag(t.nominal_prior_sigma.^2);
E=.25*dg*V*dg.';R=step2.baseMeasurement.selected.covariance+E;
S=R+G*V0*G.';factor=sht_steady_model_uq_c_common('factorcovariance',S,'bounded_linear_nuisance');
model=sht_steady_model_uq_likelihood('build',struct('selected',factor));
model.additiveResidualShift=step2.likelihood.additiveResidualShift-G*step2.nuisanceMean;
model.gain=(V0*G.')/S;Vc=V0-model.gain*G*V0;
model.conditionalCovariance=(Vc+Vc.')/2;
model.lower=t.lower_bound;model.upper=t.upper_bound;
model.logPriorSupport=sum(log(sht_normal_probability('cdf',t.upper_bound./t.nominal_prior_sigma)- ...
    sht_normal_probability('cdf',t.lower_bound./t.nominal_prior_sigma)));
model.nodeCount=count;model.seed=seed;model.nuisanceJacobian=G;
model.priorActualMean=step2.nuisanceMean;model.anchorVariationCovariance=E;
model.representation='original_truncated_prior_affine_nuisance_fixed_QMC';
end

function [ll,detail]=local_evaluate(model,residual,valid,returnSamples)
if nargin<3,valid=all(isfinite(residual),1);end
if nargin<4,returnSamples=false;end
[gaussian,detail]=sht_steady_model_uq_likelihood('evaluate',model,residual,valid);
idx=find(isfinite(gaussian));ll=gaussian;
detail.box=[];detail.validIndex=idx;
if isempty(idx),return;end
mu=-model.gain*(residual(:,idx)+model.additiveResidualShift);
box=sht_tc24_uq_box_normal(mu,model.conditionalCovariance, ...
    model.lower,model.upper,model.nodeCount,model.seed,returnSamples);
ll(idx)=gaussian(idx)+box.logProbability-model.logPriorSupport;
detail.box=box;detail.gaussianLogLikelihood=gaussian;
end
