function proposal=sht_tc27_uq_spectral_pcn(current,basis,singular,rho,beta,floorScale,inflation,maximum)
%SHT_TC27_UQ_SPECTRAL_PCN 按各灵敏度方向分别选步长的先验可逆pCN。
% 只改变提议分布，不把真实目标替换成高斯。正交基中每个分量使用
% z'=sqrt(1-a^2)*z+a*xi，所以任意固定0<a<1都保留标准正态先验。
% 桥接前期兼顾局部提议宽度，后期兼顾似然宽度，避免短数据的统一
% 最小步长在长历程高信息方向上过大，也避免弱方向被一起冻结。
singular=singular(:);assert(numel(singular)==size(current,1)&&all(isfinite(singular))&&all(singular>=0));
assert(beta>=0&&beta<=1&&floorScale>0&&inflation>0&&rho>0&&maximum<1);
localWidth=max(floorScale,inflation./sqrt(1+singular.^2));
precision=(1-beta)./localWidth.^2+beta*(1+singular.^2);
step=min(maximum,max(1e-12,rho./sqrt(precision)));
coordinate=basis.'*current;
proposal=basis*(sqrt(1-step.^2).*coordinate+step.*randn(size(coordinate)));
end
