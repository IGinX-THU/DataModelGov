function value=sht_f34_prediction_identity(likelihood,methodD,methodC)
%SHT_F34_PREDICTION_IDENTITY 绑定实际样本/权重、条件形状和局部响应。
% 时间戳和报告路径不参与数学身份；代码变化及概率对象变化必须失效。
state=struct('likelihood',likelihood.contractHash,'physics',likelihood.physicsContractHash, ...
    'DPoint',methodD.map, ...
    'DCovariance',methodD.covariance,'DConditionalMean',methodD.conditionalShapeMean, ...
    'DConditionalCovariance',methodD.conditionalShapeCovariance, ...
    'DJacobian',methodD.predictionJacobian);
state.methodCIncluded=~isempty(methodC);
if ~isempty(methodC)
    state.samples=methodC.samples;state.weights=methodC.weights;
    state.conditionalMean=methodC.conditionalShapeMean;
    state.conditionalCovariance=methodC.conditionalShapeCovariance;
    state.CPhysicalOutput=methodC.physicalOutput;
    if isfield(methodC,'physicalSupport')
        state.physicalSupport=methodC.physicalSupport;
        state.rawConditionalMean=methodC.conditionalGaussianMean;
        state.rawConditionalCovariance=methodC.conditionalGaussianCovariance;
        state.quadratureCount=methodC.conditionalQuadratureCount;
        state.quadratureSeed=methodC.conditionalQuadratureSeed;
    end
end
folder=fileparts(mfilename('fullpath'));
names={'sht_f34_prediction.m','sht_f34_prediction_identity.m','sht_f34_likelihood.m', ...
    'sht_f34_prior.m','sht_f33_thermal_equilibrium.m','sht_f34_bounded_condition.m'};
if ~isempty(methodC)&&isfield(methodC,'parameterization')&& ...
        strcmp(methodC.parameterization,'independent_nodes')
    names{end+1}='sht_f34_node_c.m';
end
for i=1:numel(names),state.source.(sprintf('f%d',i))= ...
        sht_f33_model_adapt_v2('fileHash',fullfile(folder,names{i}));end
value=sht_f33_model_adapt_v2('structHash',state);
end
