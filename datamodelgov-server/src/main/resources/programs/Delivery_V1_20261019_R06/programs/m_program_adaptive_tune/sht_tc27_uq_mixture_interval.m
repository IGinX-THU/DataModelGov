function [average,lower,upper,validMass]=sht_tc27_uq_mixture_interval(means,variance,weights)
%SHT_TC27_UQ_MIXTURE_INTERVAL 逐输出有权高斯混合的均值和95%点态区间。
% 主参数保留经验联合样本；条件高斯附加误差解析积分，不再引入有限
% 次随机抽样的端点波动。方差为零时退化为有权经验分布。
w=weights(:)/sum(weights);v=variance(:);
assert(size(means,2)==numel(w)&&size(means,1)==numel(v));
assert(all(isfinite(v))&&all(v>=0)&&all(isfinite(w))&&all(w>=0));
finite=isfinite(means);validMass=double(finite)*w;
if ~all(finite,'all')
    % 各工况仅在自身物理有效域内计算条件区间，并返回丢失的后验质量。
    % 不按整组工况联合删样本；全无效行保留NaN，不伪造零宽区间。
    average=nan(size(v));lower=average;upper=average;
    [patterns,~,membership]=unique(finite,'rows');
    for g=1:size(patterns,1)
        rows=membership==g;columns=patterns(g,:)&w.'>0;
        if ~any(columns),continue;end
        [average(rows),lower(rows),upper(rows)]=sht_tc27_uq_mixture_interval( ...
            means(rows,columns),v(rows),w(columns));
    end
    return;
end
average=means*w;sd=sqrt(v);left=min(means,[],2)-9*sd;right=max(means,[],2)+9*sd;
limits=zeros(size(means,1),2);p=[.025,.975];
for j=1:2
    lo=left;hi=right;
    for iteration=1:48
        mid=(lo+hi)/2;z=(mid-means)./max(sd,realmin);
        probability=.5*erfc(-z/sqrt(2));
        deterministic=sd==0;
        probability(deterministic,:)=double(means(deterministic,:)<=mid(deterministic));
        below=probability*w<p(j);lo(below)=mid(below);hi(~below)=mid(~below);
    end
    limits(:,j)=(lo+hi)/2;
end
lower=limits(:,1);upper=limits(:,2);
end
