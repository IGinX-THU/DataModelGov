function t=sht_tc27_uq_empirical_summary(theta,weights,t)
%SHT_TC27_UQ_EMPIRICAL_SUMMARY 联合加权样本的经验逆CDF分位数。
% 保留原摘要中的先验范围和参数字典，重算后验统计。不能对累计概率
% 作线性插值：当几乎全部质量集中于一个样本时，插值会制造区间宽度。
w=weights(:);assert(numel(w)==size(theta,2)&&height(t)==size(theta,1));
assert(all(isfinite(theta),'all')&&all(isfinite(w))&&all(w>=0)&&sum(w)>0);
keep=w>0;theta=theta(:,keep);w=w(keep)/sum(w(keep));
average=theta*w;limits=zeros(size(theta,1),3);p=[.025,.5,.975];
for j=1:size(theta,1)
    [value,order]=sort(theta(j,:));cumulative=cumsum(w(order));cumulative(end)=1;
    for k=1:3,limits(j,k)=value(find(cumulative>=p(k),1,'first'));end
end
t.posterior_mean=average;t.posterior_median=limits(:,2);
t.posterior_std=sqrt(((theta-average).^2)*w);
t.q025=limits(:,1);t.q975=limits(:,3);t.credible_width=t.q975-t.q025;
t.interval_shrinkage_pct=100*(1-t.credible_width./(t.prior_q975-t.prior_q025));
t.quantileRepresentation=repmat("weighted_empirical_inverse_CDF",height(t),1);
end
