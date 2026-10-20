function q=sht_tc24_uq_mixture_quantile(mu,variance,weights,probability)
% 带权高斯混合的边际分位数。积分测量噪声，不按每粒子只抽一次噪声。
% 零方差时退化为原经验分布；混合中的离散原子采用左连续分位定义。
mu=mu(:);variance=variance(:);weights=weights(:)/sum(weights);
if isscalar(variance),variance=repmat(variance,size(mu));end
assert(numel(mu)==numel(weights) && numel(mu)==numel(variance) && ...
    all(isfinite(mu)) && all(isfinite(variance)) && all(variance>=0), ...
    'TC24:Mixture:Invalid','混合分布参数无效。');
if all(variance==0)
    [x,order]=sort(mu);w=weights(order);keep=w>0;x=x(keep);w=w(keep);
    cdf=cumsum(w)/sum(w);cdf(end)=1;q=zeros(size(probability));
    for k=1:numel(probability),q(k)=x(find(cdf>=probability(k),1));end
    return;
end
sd=sqrt(variance);lo=min(mu-12*sd);hi=max(mu+12*sd);q=zeros(size(probability));
for k=1:numel(probability)
    left=lo;right=hi;
    for iteration=1:80
        mid=(left+right)/2;cdf=double(mid>=mu);positive=sd>0;
        cdf(positive)=.5*erfc(-(mid-mu(positive))./(sqrt(2)*sd(positive)));
        if weights.'*cdf<probability(k),left=mid;else,right=mid;end
    end
    q(k)=(left+right)/2;
end
end
