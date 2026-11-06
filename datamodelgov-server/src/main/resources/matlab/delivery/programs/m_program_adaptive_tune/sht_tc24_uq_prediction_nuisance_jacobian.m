function [G,audit]=sht_tc24_uq_prediction_nuisance_jacobian( ...
        contract,data,posterior,conditional,opts,referenceExact)
% C/D稳态预测的附加参数导数。均值不可解时，选已有可解后验代表点。
% 只改变输出传播的局部线性化位置，不删粒子、不改权重、不放宽选根范围。
center=conditional.priorMean;tbl=conditional.parameterTable;n=numel(center);
initialStep=min(tbl.difference_step,.2*min(center-tbl.lower_bound,tbl.upper_bound-center));
assert(all(initialStep>0),'TC24:Prediction:NuisanceStep','差分步长必须为正。');
w=posterior.weights(:)/sum(posterior.weights);meanTheta=posterior.theta*w;
valid=referenceExact.valid(:) & all(isfinite(referenceExact.residual),1).';
if isfield(conditional,'trainingValid'),valid=valid & conditional.trainingValid(:);end
available=find(valid);
distance=sum(((posterior.theta(:,available)-meanTheta)./contract.priorSigma).^2,1).';
[~,order]=sortrows([distance,-w(available)],[1,2]);
indices=[0;available(order(1:min(3,numel(order))))];
checks=false(numel(indices),1);retries=zeros(numel(indices),1);G=[];
for r=1:numel(indices)
    index=indices(r);
    if index==0,theta=meanTheta;else,theta=posterior.theta(:,index);end
    % 必须先确认参考本身可解。参考无解时，缩小差分步长没有依据。
    base=sht_steady_model_uq_c_common('evaluatenuisance',contract,theta,center,data,opts);
    checks(r)=all(base.valid) && all(isfinite(base.residual(:)));
    if ~checks(r),continue;end
    step=initialStep;
    for retry=0:7
        candidate=repmat(center,1,2*n);
        for j=1:n
            candidate(j,2*j-1)=center(j)+step(j);
            candidate(j,2*j)=center(j)-step(j);
        end
        evaluated=sht_steady_model_uq_c_common('evaluatenuisance', ...
            contract,theta,candidate,data,opts);
        failed=~(evaluated.valid(1:2:end) & evaluated.valid(2:2:end));
        retries(r)=retry;
        if ~any(failed),break;end
        step(failed)=step(failed)/2;
    end
    if any(failed),continue;end
    G=(evaluated.residual(:,1:2:end)-evaluated.residual(:,2:2:end))./(2*step.');
    if all(isfinite(G(:))),break;else,G=[];end
end
assert(~isempty(G),'TC24:Prediction:NuisanceDifference', ...
    '均值及最多3个可解后验代表点均未形成有效附加参数导数；保留参数后验，不放宽物理分支。');
audit=struct('posteriorMeanValid',checks(1),'usedPosteriorRepresentative',index~=0, ...
    'referenceParticleIndex',index,'referenceTheta',theta,'referencePriorMean',center, ...
    'normalizedDistanceToMean',sqrt(sum(((theta-meanTheta)./contract.priorSigma).^2)), ...
    'candidateIndices',indices(1:r),'candidateBaseValid',checks(1:r), ...
    'differenceRetries',retries(1:r),'differenceStep',step, ...
    'jointValidCandidateCount',numel(available),'posteriorWeightsChanged',false,'truthRead',false, ...
    'approximation','single_valid_reference_conditional_nuisance_linearization');
if index~=0
    fprintf('TC24预测导数参考改用后验粒子%d，距均值的先验尺度距离%.4g；后验与选根限制不变。\n', ...
        index,audit.normalizedDistanceToMean);
end
end
