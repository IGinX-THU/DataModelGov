function tableValue=sht_f34_q_sensitivity(prepared,methodC)
%SHT_F34_Q_SENSITIVITY 计算工程Q倍率对下一架次显式参数区间的影响。
%
% 当前后验由方法C带权样本表示。逐架次传播核是在每个后验样本中心
% 叠加有界截断高斯，因此下一架次每个显式参数的边缘分布是一维截断
% 高斯混合。本函数直接对该混合CDF求分位数，不用“方差相加后乘1.96”
% 代替非高斯区间，也不进行随机抽样。倍率乘在协方差Q上，所以传播
% 标准差乘sqrt(multiplier)。曲线形状Q不在本表中，它在预测传播中另算。

multiplier=prepared.options.processCovarianceSensitivityMultiplier(:);
if isfield(prepared.prior,'nodePrior')
    tableValue=sht_f34_node_c('qsensitivity',prepared,methodC);
    return;
end
if any(multiplier<=0)||~any(abs(multiplier-1)<eps)
    error('SHT:F34Q:Multiplier','Q倍率必须为正并包含1。');
end
parameter=prepared.prior.parameterTable;
dimension=height(parameter);
if size(methodC.samples,1)~=dimension||numel(methodC.weights)~=size(methodC.samples,2)
    error('SHT:F34Q:Posterior','方法C样本维数或权重无效。');
end
baseSigma=[prepared.options.flightToFlightHealthSigma(:); ...
    prepared.options.flightToFlightKdistSigma; ...
    prepared.options.flightToFlightFuelSigma_kgps];
if numel(baseSigma)~=dimension
    error('SHT:F34Q:Dimension','逐架次显式Q与参数维数不一致。');
end
weights=methodC.weights(:)/sum(methodC.weights);
rowCount=dimension*numel(multiplier);
parameterId=strings(rowCount,1);unit=strings(rowCount,1);
qMultiplier=zeros(rowCount,1);currentQ025=zeros(rowCount,1);
currentQ975=zeros(rowCount,1);currentWidth=zeros(rowCount,1);
nextMean=zeros(rowCount,1);nextStd=zeros(rowCount,1);
nextQ025=zeros(rowCount,1);nextQ975=zeros(rowCount,1);
nextWidth=zeros(rowCount,1);widthRatio=zeros(rowCount,1);
row=0;
for k=1:numel(multiplier)
    for j=1:dimension
        row=row+1;
        center=methodC.samples(j,:).';
        sigma=sqrt(multiplier(k))*baseSigma(j);
        lower=parameter.lower_bound(j);upper=parameter.upper_bound(j);
        [componentMean,componentVariance]=local_truncated_moments( ...
            center,sigma,lower,upper);
        mixtureMean=sum(weights.*componentMean);
        mixtureVariance=sum(weights.*(componentVariance+ ...
            (componentMean-mixtureMean).^2));
        qLower=local_mixture_quantile(center,sigma,lower,upper,weights,0.025);
        qUpper=local_mixture_quantile(center,sigma,lower,upper,weights,0.975);
        baseWidth=methodC.interval95(j,2)-methodC.interval95(j,1);
        parameterId(row)=string(parameter.parameter_id(j));
        unit(row)=string(parameter.unit(j));qMultiplier(row)=multiplier(k);
        currentQ025(row)=methodC.interval95(j,1);
        currentQ975(row)=methodC.interval95(j,2);currentWidth(row)=baseWidth;
        nextMean(row)=mixtureMean;nextStd(row)=sqrt(max(mixtureVariance,0));
        nextQ025(row)=qLower;nextQ975(row)=qUpper;nextWidth(row)=qUpper-qLower;
        widthRatio(row)=nextWidth(row)/max(baseWidth,eps);
    end
end
tableValue=table(parameterId,unit,qMultiplier,currentQ025,currentQ975, ...
    currentWidth,nextMean,nextStd,nextQ025,nextQ975,nextWidth,widthRatio, ...
    false(rowCount,1),repmat("engineering_Q_pending_longitudinal_calibration", ...
    rowCount,1),'VariableNames',{'parameter_id','unit','q_covariance_multiplier', ...
    'current_q025','current_q975','current_interval_width','next_mean', ...
    'next_std','next_q025','next_q975','next_interval_width', ...
    'next_to_current_width_ratio','q_calibrated','q_basis'});
end

function value=local_mixture_quantile(center,sigma,lower,upper,weights,p)
lo=lower;hi=upper;
for i=1:90
    middle=(lo+hi)/2;
    cdf=local_mixture_cdf(middle,center,sigma,lower,upper,weights);
    if cdf<p,lo=middle;else,hi=middle;end
end
value=(lo+hi)/2;
end

function value=local_mixture_cdf(x,center,sigma,lower,upper,weights)
alpha=(lower-center)/sigma;beta=(upper-center)/sigma;
mass=local_normcdf(beta)-local_normcdf(alpha);
component=(local_normcdf((x-center)/sigma)-local_normcdf(alpha))./mass;
component=min(max(component,0),1);
value=sum(weights.*component);
end

function [meanValue,variance]=local_truncated_moments(center,sigma,lower,upper)
alpha=(lower-center)/sigma;beta=(upper-center)/sigma;
mass=local_normcdf(beta)-local_normcdf(alpha);
phiAlpha=local_normpdf(alpha);phiBeta=local_normpdf(beta);
ratio=(phiAlpha-phiBeta)./mass;
meanValue=center+sigma*ratio;
variance=sigma^2*(1+(alpha.*phiAlpha-beta.*phiBeta)./mass-ratio.^2);
variance=max(variance,0);
end

function value=local_normcdf(x)
value=0.5*erfc(-x/sqrt(2));
end

function value=local_normpdf(x)
value=exp(-0.5*x.^2)/sqrt(2*pi);
end
