function proposal=sht_uq_null_pcn(current,basis,informedRank,scale)
% 只改变固定正交基中的弱信息坐标。白化潜变量先验为独立标准正态。
% 强信息坐标严格不动；弱坐标的pCN转移保持先验，仍须外层精确MH验收。
% 此函数不重采样后验、不用局部高斯替代目标，也不直接扩大样本区间。
validateattributes(scale,{'numeric'},{'scalar','>',0,'<',1});
assert(size(basis,1)==size(current,1) && size(basis,2)==size(current,1));
assert(informedRank>=0 && informedRank<=size(current,1) && informedRank==floor(informedRank));
proposal=current;
if informedRank==size(current,1),return;end
weak=basis(:,informedRank+1:end);coordinate=weak.'*current;
next=sqrt(1-scale^2)*coordinate+scale*randn(size(coordinate));
proposal=current+weak*(next-coordinate);
end
