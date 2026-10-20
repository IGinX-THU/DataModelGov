function [values,weights]=sht_tc24_uq_nuisance_output_cloud(atMean,G,nc,index,mainWeights)
% 从已保存的有界条件节点形成线性输出云；不重新采样、不改变主后验。
% atMean已经包含条件附加均值，故此处只加围绕该均值的有界变化。
q=size(nc.quadratureSamples,2);d=size(nc.mean,1);m=numel(index);
samples=reshape(nc.quadratureSamples(:,:,index),d,[]);
shift=reshape(G*samples,q,m)-G*nc.mean(:,index);
values=reshape(atMean,1,[])+shift;
weights=nc.quadratureWeights(:,index).*reshape(mainWeights,1,[]);
values=values(:);weights=weights(:)/sum(weights(:));
end
