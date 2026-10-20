function [proposal,scale]=sht_tc24_uq_spectral_pcn(current,basis,singularValue,gain)
% 逐方向pCN：强信息方向小步，弱信息方向大步；严格保持标准正态参考。
% basis固定且正交，s来自白化、先验尺度化Jacobian，只用于提议几何。
% 与把后验假定为高斯不同，接受概率仍使用原非线性似然。
n=size(current,1);s=zeros(n,1);s(1:numel(singularValue))=singularValue(:);
assert(isequal(size(basis),[n,n]) && norm(basis.'*basis-eye(n),'fro')<1e-8, ...
    'TC24:C:SpectralBasis','pCN方向矩阵必须正交。');
validateattributes(gain,{'numeric'},{'scalar','positive','finite'});
scale=min(.8,gain./sqrt(1+s.^2));
coordinate=basis.'*current;
proposal=basis*(sqrt(1-scale.^2).*coordinate+scale.*randn(size(coordinate)));
end
