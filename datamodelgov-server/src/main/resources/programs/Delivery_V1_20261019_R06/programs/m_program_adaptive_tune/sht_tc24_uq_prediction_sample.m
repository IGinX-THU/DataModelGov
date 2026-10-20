function [cloud,audit]=sht_tc24_uq_prediction_sample(posterior,count,seed)
% 按原后验权重分层抽取预测代表；仅缩减物理回放，不替换参数后验。
% 重复抽中的原粒子合并为频数权重，所有原粒子均有被选择的机会。
n=size(posterior.theta,2);w=posterior.weights(:);w=w/sum(w);
validateattributes(count,{'numeric'},{'scalar','integer','positive','finite'});
cloud=posterior;
if count>=n
    ids=(1:n).';weights=w;requested=n;used=false;
else
    old=rng;cleanup=onCleanup(@()rng(old));rng(seed,'twister');
    u=((0:count-1).'+rand(count,1))/count;cdf=cumsum(w);cdf(end)=1;
    draw=zeros(count,1);j=1;
    for i=1:count
        while u(i)>cdf(j),j=j+1;end
        draw(i)=j;
    end
    [ids,~,group]=unique(draw);weights=accumarray(group,1)/count;requested=count;used=true;
    clear cleanup;
end
cloud.theta=posterior.theta(:,ids);cloud.weights=weights;
for field={'logLikelihood','logPrior'}
    name=field{1};if isfield(cloud,name) && numel(cloud.(name))==n,cloud.(name)=cloud.(name)(ids);end
end
audit=struct('enabled',used,'sourceCount',n,'requestedCount',requested, ...
    'uniquePredictionCount',numel(ids),'selectedIndex',ids,'weights',weights, ...
    'randomSeed',seed,'method','posterior_weighted_stratified_resampling', ...
    'originalParameterPosteriorUnchanged',true,'truthUsed',false, ...
    'predictionFailuresUsedForSelection',false);
end
