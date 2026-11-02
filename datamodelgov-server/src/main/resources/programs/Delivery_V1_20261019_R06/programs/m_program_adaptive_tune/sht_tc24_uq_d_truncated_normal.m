function value=sht_tc24_uq_d_truncated_normal(left,right)
% 标准正态在[left,right]的精确条件抽样；尾部用生存函数避免1-CDF抵消。
assert(left<right && ~isnan(left) && ~isnan(right),'TC24:D:TruncatedBounds','正态截断区间无效。');
if right<0
    value=-sht_tc24_uq_d_truncated_normal(-right,-left);return;
end
if left>0
    a=.5*erfc(left/sqrt(2));b=.5*erfc(right/sqrt(2));
    if a>b && a>realmin
        u=b+(a-b)*rand;value=sqrt(2)*erfcinv(2*u);return;
    end
    % 极远尾部采用截断指数提议及拒绝校正，不裁剪到边界。
    alpha=.5*(left+hypot(left,2));mass=-expm1(-alpha*(right-left));
    for trial=1:10000
        proposal=left-log1p(-rand*mass)/alpha;
        if log(rand)<=-.5*(proposal-alpha)^2,value=proposal;return;end
    end
    error('TC24:D:TruncatedTail','极端截断正态抽样未完成，不能静默返回端点。');
end
a=.5*erfc(-left/sqrt(2));b=.5*erfc(-right/sqrt(2));
assert(b>a,'TC24:D:TruncatedResolution','截断质量低于数值分辨率。');
u=a+(b-a)*rand;value=-sqrt(2)*erfcinv(2*u);
end
