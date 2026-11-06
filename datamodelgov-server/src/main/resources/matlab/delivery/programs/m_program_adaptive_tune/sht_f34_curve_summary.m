function tableValue=sht_f34_curve_summary(prepared,methodC)
%SHT_F34_CURVE_SUMMARY 将R1联合后验恢复为实际曲线节点可信区间。
%
% 对每个方法C显式样本，先恢复其条件形状后验均值，再利用逐样本条件
% 协方差计算每个实际节点的高斯分量方差。最终节点分布是带权一维高斯
% 混合，95%区间由混合CDF求解，不用“均值加减1.96倍标准差”替代。

prior=prepared.prior;map=prior.shape.nodeMap;
if ~isfield(methodC,'conditionalShapeMean')|| ...
        ~isfield(methodC,'conditionalShapeCovariance')
    error('SHT:F34Curve:ConditionalShape','方法C缺少逐样本条件形状分布。');
end
n=size(methodC.samples,2);nodeCount=height(map);
if size(methodC.conditionalShapeMean,2)~=n|| ...
        size(methodC.conditionalShapeCovariance,3)~=n
    error('SHT:F34Curve:SampleCount','显式样本与条件形状样本数不一致。');
end
weights=methodC.weights(:)/sum(methodC.weights);
modelSet=sht_f33_model_adapt_v2( ...
    'thetaToModels',prepared.context,methodC.samples);
center=zeros(nodeCount,n);componentVariance=zeros(nodeCount,n);
for i=1:n
    schedule=sht_f34_prior('applyShape',modelSet.schedules{i},prior, ...
        methodC.conditionalShapeMean(:,i));
    center(:,i)=local_extract_nodes(schedule,map);
    covariance=methodC.conditionalShapeCovariance(:,:,i);
    componentVariance(:,i)=sum((prior.shape.basis*covariance).* ...
        prior.shape.basis,2);
end
posteriorMean=center*weights;
posteriorVariance=(componentVariance+(center-posteriorMean).^2)*weights;
q025=zeros(nodeCount,1);q975=q025;
cloud=[];cloudWeight=[];
if isfield(methodC,'physicalSupport')
    % 有界条件分布不再当作无界高斯画区间；主节点仍来自真实SMC样本。
    count=16;cloud=zeros(nodeCount,n*count);cloudWeight=zeros(n*count,1);
    stream=RandStream('mt19937ar','Seed',93811);
    for j=1:n
        b=sht_f34_bounded_condition('evaluate',methodC.conditionalGaussianMean(:,j), ...
            methodC.conditionalGaussianCovariance(:,:,j),methodC.physicalSupport, ...
            methodC.conditionalQuadratureCount,methodC.conditionalQuadratureSeed,stream,count);
        index=(j-1)*count+(1:count);
        cloud(:,index)=center(:,j)+prior.shape.basis*(b.draw-methodC.conditionalShapeMean(:,j));
        cloudWeight(index)=weights(j)/count;
    end
end
for i=1:nodeCount
    if ~isempty(cloud)
        [x,order]=sort(cloud(i,:));w=cloudWeight(order);cdf=cumsum(w)/sum(w);
        q025(i)=x(find(cdf>=.025,1));q975(i)=x(find(cdf>=.975,1));continue;
    end
    q025(i)=local_mixture_quantile(center(i,:),weights, ...
        componentVariance(i,:),0.025);
    q975(i)=local_mixture_quantile(center(i,:),weights, ...
        componentVariance(i,:),0.975);
end
kind=string(map.kind);unit=repmat("1",nodeCount,1);
unit(kind=="fuel_bias")="kg/s";
curveId=strings(nodeCount,1);
for i=1:nodeCount
    if kind(i)=="fuel_bias"
        curveId(i)="Wf_bias";
    else
        curveId(i)="h"+string(round(map.c_index(i)));
    end
end
tableValue=table(curveId,kind,double(map.c_index),double(map.node_index), ...
    double(map.coordinate),unit,double(map.reference_value),posteriorMean, ...
    sqrt(max(posteriorVariance,0)),q025,q975, ...
    double(map.family_index)>0,'VariableNames',{'curve_id','kind','c_index', ...
    'node_index','coordinate','unit','reference_value','posterior_mean', ...
    'posterior_std','q025','q975','explicit_family'});
end

function value=local_extract_nodes(schedule,map)
value=zeros(height(map),1);kind=string(map.kind);
for i=1:height(map)
    if kind(i)=="health"
        entry=find([schedule.healthEntries.cIndex]==map.c_index(i),1);
        if isempty(entry)||map.node_index(i)>numel(schedule.healthEntries(entry).kNodes)
            error('SHT:F34Curve:HealthNode','无法恢复h%d第%d个节点。', ...
                map.c_index(i),map.node_index(i));
        end
        value(i)=schedule.healthEntries(entry).kNodes(map.node_index(i));
    elseif kind(i)=="health_constant"
        if map.c_index(i)==15,value(i)=schedule.h15;
        else,value(i)=schedule.designHealth(map.c_index(i)+1);end
    elseif kind(i)=="fuel_bias"
        value(i)=schedule.fuelBias.biasNodes(map.node_index(i));
    else
        error('SHT:F34Curve:NodeKind','未知节点类型%s。',char(kind(i)));
    end
end
end

function value=local_mixture_quantile(center,weight,variance,probability)
center=center(:);weight=weight(:)/sum(weight);sigma=sqrt(max(variance(:),0));
lower=min(center-9*sigma);upper=max(center+9*sigma);
if upper-lower<=eps*max(1,max(abs(center))),value=sum(weight.*center);return;end
for i=1:80
    middle=(lower+upper)/2;
    cdf=local_mixture_cdf(middle,center,sigma,weight);
    if cdf<probability,lower=middle;else,upper=middle;end
end
value=(lower+upper)/2;
end

function value=local_mixture_cdf(x,center,sigma,weight)
positive=sigma>eps;component=zeros(size(center));
component(positive)=0.5*erfc(-(x-center(positive))./(sqrt(2)*sigma(positive)));
component(~positive)=double(x>=center(~positive));
value=sum(weight.*component);
end
