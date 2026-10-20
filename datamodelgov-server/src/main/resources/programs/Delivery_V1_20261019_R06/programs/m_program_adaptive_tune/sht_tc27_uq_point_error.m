function out=sht_tc27_uq_point_error(c)
%SHT_TC27_UQ_POINT_ERROR 直接复用TC24的稳态判定与工程模型差异规则。
% 这里只调用代数协方差构造，不启动TC24辨识，不读取TC24后验或真值。
% TC24按点排列7个气路输出+2个导数；TC27按通道排列，必须显式置换。
n=height(c.trainingData);order=[8,9,1,2,3,4,5,6,7];
index=reshape(((0:n-1)'*9+order),[],1);
base=struct('modelMode',0,'route',c.route,'residualPerPoint',9, ...
    'steadyWindowSampleCount',c.sampleCount,'trainingData',c.trainingData, ...
    'config',struct('modelDiscrepancyScale',1,'covarianceScenario','engineering'));
input=struct('route',c.route,'covariance',zeros(9*n));
m=sht_steady_model_uq_common('measurementcovariance',base,input);
out=struct('stationarityCovariance',m.stationarityCovariance(index,index), ...
    'modelCovariance',m.modelDiscrepancyCovariance(index,index), ...
    'modelStd',m.modelStd,'permutation',index,'source','TC24_engineering_scale_1', ...
    'truthUsed',false,'residualFitted',false);
out.factor=chol(out.stationarityCovariance+out.modelCovariance,'lower');
end
