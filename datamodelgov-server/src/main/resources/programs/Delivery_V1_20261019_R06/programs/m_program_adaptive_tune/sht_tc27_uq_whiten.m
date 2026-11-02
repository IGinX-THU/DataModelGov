function z=sht_tc27_uq_whiten(model,residual,center)
%SHT_TC27_UQ_WHITEN 对角加低秩协方差的对称白化；导数白化不加均值。
if nargin<3,center=true;end
if center,residual=residual+model.shift;end
z=sht_tc27_uq_base_transform(model,residual,false);
z=z-model.U*(model.shrink.*(model.U.'*z));
end
