function out=sht_tc27_uq_surrogate(action,varargin)
%SHT_TC27_UQ_SURROGATE 全维线性基线+白化残差POD+LIS/ARD-GP非线性补偿。
% POD仅压缩输出，主参数没有冻结。低维LIS仅供非线性补偿输入，完整
% 节点向量仍进入线性项。对数似然盲测和精确校正负责揭示截断误差。
switch action
    case 'fit',out=fitModel(varargin{:});
    case 'predict',out=predictModel(varargin{:});
    otherwise,error('未知代理动作。');
end
end

function s=fitModel(c,theta,white,D)
assert(size(theta,2)>30&&all(isfinite(white),'all'),'代理有效样本不足。');
center=D.map;linear=D.physicalJacobian;base=D.finalExact.residual;
% 先验潜空间的局部Jacobian用于选择最有似然信息的非线性坐标。
latentCenter=sht_steady_model_uq_sampler('thetatolatent',c.prior, ...
    min(max(center,c.lowerBound+1e-10*c.priorSigma),c.upperBound-1e-10*c.priorSigma));
dtdz=zeros(c.parameterCount);
for j=1:c.parameterCount
    zp=latentCenter;zm=zp;zp(j)=zp(j)+1e-4;zm(j)=zm(j)-1e-4;
    dtdz(:,j)=(sht_steady_model_uq_sampler('latenttotheta',c.prior,zp)- ...
        sht_steady_model_uq_sampler('latenttotheta',c.prior,zm))/2e-4;
end
[~,S,V]=svd(linear*dtdz,'econ');singular=diag(S);rankInput=min(16,c.parameterCount);
shared=strcmp(c.options.cSurrogateMode,'full_latent_shared_matern');
if shared,rankInput=c.parameterCount;end
nonlinear=white-base-linear*(theta-center);meanResidual=mean(nonlinear,2);
[U,S,~]=svd(nonlinear-meanResidual,'econ');values=diag(S).^2;
rankOutput=find(cumsum(values)>=.9999*sum(values),1);if isempty(rankOutput),rankOutput=1;end
if shared
    rankOutput=find(cumsum(values)>=(1-1e-8)*sum(values),1);
    if isempty(rankOutput),rankOutput=1;end
else,rankOutput=min([rankOutput,32,size(U,2)]);end
U=U(:,1:rankOutput);
latent=sht_steady_model_uq_sampler('thetatolatent',c.prior,theta);
X=(V(:,1:rankInput).'*latent).';Y=(U.'*(nonlinear-meanResidual)).';
gp=cell(rankOutput,1);mu=mean(Y,1);sigma=max(std(Y,0,1),1e-8);
if shared
    % 与局部提议相同的各向异性尺度。保留全部方向，不把弱方向冻结。
    inputScale=max(.02,1./sqrt(1+singular.^2)).';
    if isfield(c.options,'steadyCBackend')&&strcmp(c.options.steadyCBackend,'surrogate_bridge')
        % 保留全部输出模态，但按实际白化能量拟合核，避免小模态等权主导。
        sharedGP=sht_tc27_uq_energy_gp(X,(Y-mu)./sigma,inputScale,sigma.^2);
    else
        sharedGP=sht_tc27_uq_shared_gp('fit',X,(Y-mu)./sigma,inputScale);
    end
else
assert(exist('fitrgp','file')==2,'旧ARD-GP需要Statistics and Machine Learning Toolbox。');
for j=1:rankOutput
    gp{j}=fitrgp(X,(Y(:,j)-mu(j))/sigma(j),'KernelFunction','ardsquaredexponential', ...
        'BasisFunction','constant','Standardize',true,'FitMethod','exact','PredictMethod','exact', ...
        'Sigma',.01,'ConstantSigma',false);
end
end
% 在固定张成空间内计算似然，避免SMC每次重建数万行历程。
[Q,~]=qr([base+meanResidual,linear,U],0);
s=struct('prior',c.prior,'center',center,'basis',Q,'base',Q.'*(base+meanResidual), ...
    'linear',Q.'*linear,'pod',Q.'*U,'gp',{gp},'gpMean',mu,'gpScale',sigma, ...
    'inputBasis',V(:,1:rankInput),'inputRank',rankInput,'outputRank',rankOutput, ...
    'fullObservationCount',size(white,1),'trainingCount',size(theta,2), ...
    'latentJacobian',linear*dtdz,'globalBasis',V,'globalSingular',singular, ...
    'outputPODDiscardedEnergy',sum(values(rankOutput+1:end))/max(sum(values),eps));
if shared,s.sharedGP=sharedGP;end
end

function out=predictModel(s,theta)
latent=sht_steady_model_uq_sampler('thetatolatent',s.prior,theta);
X=(s.inputBasis.'*latent).';coeff=zeros(numel(s.gp),size(theta,2));
if isfield(s,'sharedGP')
    coeff=(s.gpMean+s.gpScale.*sht_tc27_uq_shared_gp('predict',s.sharedGP,X)).';
else
    for j=1:numel(s.gp),coeff(j,:)=s.gpMean(j)+s.gpScale(j)*predict(s.gp{j},X).';end
end
r=s.base+s.linear*(theta-s.center)+s.pod*coeff;
if isfield(s,'boxGain')
    % 一级代理只用便宜的边际矩形概率近似。最终校正使用完整相关
    % 条件分布的矩形概率，因此这里不把独立近似冒充精确似然。
    m=s.boxGain*r;a=(s.boxLower-m)./s.boxStd;b=(s.boxUpper-m)./s.boxStd;
    positive=a>0;t=a(positive);a(positive)=-b(positive);b(positive)=-t;
    la=log(.5*erfc(-a/sqrt(2)));lb=log(.5*erfc(-b/sqrt(2)));
    q=a<-10;la(q)=log(.5)+log(erfcx(-a(q)/sqrt(2)))-a(q).^2/2;
    q=b<-10;lb(q)=log(.5)+log(erfcx(-b(q)/sqrt(2)))-b(q).^2/2;
    lp=sum(lb+log(-expm1(min(la-lb,-eps))),1);
    r=[r;sqrt(max(0,-2*lp))];
end
out=struct('residual',r,'valid',all(isfinite(r),1),'dllEvaluationCount',0,'dllRuntime_s',0);
end
