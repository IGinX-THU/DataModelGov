function z=sht_tc27_uq_base_transform(model,x,inverse)
%SHT_TC27_UQ_BASE_TRANSFORM 分块基础协方差的白化及逆变换。
% inverse=false计算L\x，inverse=true计算L*x；不加入残差均值。
% 无baseBlocks时严格退化为旧对角实现，供历史合同兼容使用。
if nargin<3,inverse=false;end
if inverse,z=sqrt(model.variance).*x;else,z=x./sqrt(model.variance);end
if ~isfield(model,'baseBlocks'),return;end
for k=1:numel(model.baseBlocks)
    b=model.baseBlocks(k);
    if inverse,z(b.rows,:)=b.cholLower*x(b.rows,:);
    else,z(b.rows,:)=b.cholLower\x(b.rows,:);end
end
end
