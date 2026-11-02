function q=sht_quantile_vector(x,p)
%SHT_QUANTILE_VECTOR 无工具箱向量分位数，保持旧quantile的半样本插值约定。
% 排序样本x(k)对应概率(k-0.5)/n；区间外取端点，NaN样本不参与。
% 本接口只承担已有先验样本汇总，不替换后验的加权分位数定义。
assert(isnumeric(x) && isreal(x) && (isvector(x) || isempty(x)));
validateattributes(p,{'numeric'},{'real','>=',0,'<=',1});
x=sort(double(x(~isnan(x))));n=numel(x);q=nan(size(p));
if n==0,return;end
position=min(max(n*double(p)+.5,1),n);
left=floor(position);right=ceil(position);fraction=position-left;
q(:)=x(left);use=right>left & fraction>0;
q(use)=(1-fraction(use)).*reshape(x(left(use)),size(fraction(use)))+ ...
    fraction(use).*reshape(x(right(use)),size(fraction(use)));
end
