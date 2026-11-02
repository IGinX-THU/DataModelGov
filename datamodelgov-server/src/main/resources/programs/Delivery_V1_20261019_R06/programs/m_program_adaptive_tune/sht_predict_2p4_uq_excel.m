function result=sht_predict_2p4_uq_excel(model,prediction,options)
%SHT_PREDICT_2P4_UQ_EXCEL Excel联合参数的条件模型输出传播。
% 传播已交付样本及C/D的附加参数条件矩，输入视为精确给定；
% 不叠加未由用户指定的测量/模型误差。该区间不是完整可观测量区间。
timer=tic;
assert(isfield(options,'workbookFile') && prediction.passed, ...
    'SHT:UQDelivery:MissingPredictionInput', ...
    '需提供posteriorOptions.workbookFile，且确定性预测必须有有效气路解。');
d=sht_load_2p4_uq_delivery(options.workbookFile);
schedules=cell(d.sampleCount,1);
for j=1:d.sampleCount
    schedules{j}=sht_2p4_uq_delivery_schedule(d,model,d.theta(:,j));
end
replayModel=model;
replayModel.options.fuelInputSemantics='physical_model';
conditionalIncluded=isfield(d,'conditionalNuisance');
if conditionalIncluded
    nc=d.conditionalNuisance;etaMean=nc.parameterTable.prior_actual_mean;
    for j=1:d.sampleCount
        schedules{j}.designHealth(nc.parameterTable.c_index+1)=etaMean;
    end
end
batchOptions=struct('routeOverride','steady','steadyLoadBoundaryMode','torque', ...
    'inputDriven',true, ...
    'inletBoundaryMode',prediction.inputContract.inletBoundaryMode, ...
    'initialSeedMatrices',prediction.corrected.diagnostic.solutionSeed);
batchOptions.uqSteadyContinuation=isfield(model.options,'modelMode') && model.options.modelMode==0;
replay=sht_steady_model_adapt_v2_common('evaluateschedulebatchdataset', ...
    replayModel,prediction.internalData,schedules,batchOptions);
conditionalCorrection=[];conditionalVariance=[];
conditionalReferenceAudit=struct();
if conditionalIncluded
    [G,conditionalReferenceAudit]=local_nuisance_derivative( ...
        d,model,replayModel,prediction.internalData,batchOptions,nc,replay);
    conditionalCorrection=G*(nc.mean-etaMean);
    conditionalVariance=max(diag(G*nc.covariance*G.'),0);
end
pointValid=false(height(prediction.internalData),d.sampleCount);
for j=1:d.sampleCount,pointValid(:,j)=replay.candidate(j).prediction.valid;end
if conditionalIncluded,pointValid=pointValid & local_training_eligibility(nc).';end
valid=all(pointValid,1).';mass=sum(d.weights(valid));pointMass=pointValid*d.weights;
assert(all(pointMass>0),'SHT:UQDelivery:NoValidPrediction','某个预测工况没有有效后验质量。');
names={'Np','Ng','Pt3','Tt3','Pt45','Tt45'};
units={'rpm','rpm','Pa','K','Pa','K'};
if isfield(model.options,'modelMode') && model.options.modelMode==0
    names={'Np','Ng','Ptb3','Ttb3','Pt45','Tt45','Pt6','Tt6','Wa2'};
    units={'rpm','rpm','Pa','K','Pa','K','Pa','K','kg/s'};
end
rows=height(prediction.internalData)*numel(names); row=0;
point_id=strings(rows,1); output_name=point_id; unit=point_id;
model_lower=zeros(rows,1); model_median=model_lower; model_upper=model_lower;
deterministic_frozen_model=model_lower;
for i=1:height(prediction.internalData)
    indices=find(pointValid(i,:));weight=d.weights(indices)/pointMass(i);
    for c=1:numel(names)
        row=row+1;
        values=arrayfun(@(j) replay.candidate(j).prediction.(names{c})(i),indices);
        if conditionalIncluded
            values=values(:)+conditionalCorrection(row,indices).';
            if isfield(nc,'quadratureSamples')
                [values,cloudWeights]=sht_tc24_uq_nuisance_output_cloud(values,G(row,:),nc,indices,weight);
                q=sht_tc24_uq_mixture_quantile(values,0,cloudWeights,[.025,.5,.975]);
            else
                q=sht_tc24_uq_mixture_quantile(values,conditionalVariance(row),weight,[.025,.5,.975]);
            end
        else
            q=local_quantile(values,weight,[0.025,0.5,0.975]);
        end
        point_id(row)=prediction.internalData.point_id(i);
        output_name(row)=names{c}; unit(row)=units{c};
        model_lower(row)=q(1); model_median(row)=q(2); model_upper(row)=q(3);
        deterministic_frozen_model(row)=prediction.corrected.prediction.(names{c})(i);
    end
end
intervalTable=table(point_id,output_name,unit,model_lower,model_median,model_upper, ...
    deterministic_frozen_model);
% 单点时repelem(标量,n)返回行向量，表字段必须显式保持逐输出的列向量。
intervalTable.valid_posterior_mass=reshape(repelem(pointMass,numel(names)),[],1);
% 保留旧绘图表的字段名，但未计算的可观测量区间明确为NaN。
intervalTable.observable_lower=nan(rows,1); intervalTable.observable_upper=nan(rows,1);
result=struct('method',d.method,'runId',d.runId, ...
    'sourcePosteriorParticleCount',d.sampleCount,'uniquePosteriorParticleCount', ...
    size(unique(d.theta.','rows'),1),'validPosteriorMass',mass, ...
    'passed',all(valid),'intervalTable',intervalTable,'runtime_s',toc(timer), ...
    'inputUncertaintyPropagated',false,'measurementUncertaintyPropagated',false, ...
    'marginalizedNuisancePropagated',conditionalIncluded,'internalDataRead',false, ...
    'conditionalNuisanceReferenceAudit',conditionalReferenceAudit, ...
    'scope','conditional_model_output_from_delivered_joint_parameters', ...
    'pointwiseValidPosteriorMass',pointMass, ...
    'invalidParticlesConditionedOutForPrediction',any(~valid));
fprintf('Excel参数条件传播：%s，%d粒子，有效质量%.6f；不含额外测量/模型差异。\n', ...
    d.method,d.sampleCount,mass);
end

function allowed=local_training_eligibility(nc)
% D快速Excel不声称逐样本验证过训练物理根；未知不当成失败或成功。
% 本次独立预测仍由上方真实稳态回放判定各点的有效性。
allowed=nc.trainingValid(:);
if isfield(nc,'trainingValidityKnown'),allowed=allowed | ~nc.trainingValidityKnown(:);end
end

function [G,audit]=local_nuisance_derivative(d,model,replayModel,data,options,nc,replay)
% Excel独立传播同样先检查参考本身，不能在无解均值处反复缩小步长。
etaMean=nc.parameterTable.prior_actual_mean;nEta=numel(etaMean);
initialStep=min(nc.parameterTable.difference_step, ...
    .2*min(etaMean-nc.parameterTable.lower_bound,nc.parameterTable.upper_bound-etaMean));
assert(all(initialStep>0),'SHT:UQDelivery:NuisanceStep','条件附加参数差分步长必须为正。');
valid=[replay.candidate.valid].' & local_training_eligibility(nc);available=find(valid);
% 此处尺度只用于选近邻，不是新先验，也不改变参数区间。
scale=sqrt(max(sum((d.theta-d.mean).^2.*d.weights.',2),eps));
distance=sum(((d.theta(:,available)-d.mean)./scale).^2,1).';
[~,order]=sortrows([distance,-d.weights(available)],[1,2]);
indices=[0;available(order(1:min(3,numel(order))))];
checks=false(numel(indices),1);G=[];
for r=1:numel(indices)
    index=indices(r);
    if index==0,theta=d.mean;else,theta=d.theta(:,index);end
    center=sht_2p4_uq_delivery_schedule(d,model,theta);
    center.designHealth(nc.parameterTable.c_index+1)=etaMean;
    base=sht_steady_model_adapt_v2_common('evaluateschedulebatchdataset', ...
        replayModel,data,{center},options);
    checks(r)=all([base.candidate.valid]);
    if ~checks(r),continue;end
    step=initialStep;
    for retry=0:7
        perturbation=cell(2*nEta,1);
        for j=1:nEta
            for signIndex=1:2
                schedule=center;eta=etaMean;eta(j)=eta(j)+(3-2*signIndex)*step(j);
                schedule.designHealth(nc.parameterTable.c_index+1)=eta;
                perturbation{2*j-2+signIndex}=schedule;
            end
        end
        derivative=sht_steady_model_adapt_v2_common('evaluateschedulebatchdataset', ...
            replayModel,data,perturbation,options);
        ok=[derivative.candidate.valid];failed=~(ok(1:2:end) & ok(2:2:end));
        if ~any(failed),break;end
        step(failed)=step(failed)/2;
    end
    if any(failed),continue;end
    % 固定物理输入，不应用训练燃油偏置；输出行序与正式表一致。
    names={'Np','Ng','Ptb3','Ttb3','Pt45','Tt45','Pt6','Tt6','Wa2'};
    G=zeros(height(data)*numel(names),nEta);
    for j=1:nEta
        a=derivative.candidate(2*j-1).prediction;b=derivative.candidate(2*j).prediction;
        block=zeros(height(data),numel(names));
        for k=1:numel(names),block(:,k)=(a.(names{k})-b.(names{k}))/(2*step(j));end
        G(:,j)=reshape(block.',[],1);
    end
    if all(isfinite(G(:))),break;else,G=[];end
end
assert(~isempty(G),'SHT:UQDelivery:NuisanceDerivative', ...
    '均值及最多3个可解后验代表点均未形成有效条件附加参数导数。');
audit=struct('posteriorMeanValid',checks(1),'referenceParticleIndex',index, ...
    'referenceTheta',theta,'usedPosteriorRepresentative',index~=0,'differenceRetries',retry, ...
    'differenceStep',step,'posteriorWeightsChanged',false,'truthRead',false);
end

function q=local_quantile(x,w,p)
[x,order]=sort(x(:)); w=w(order); keep=w>0; x=x(keep); w=w(keep);
f=cumsum(w)/sum(w); q=zeros(size(p));
for k=1:numel(p), q(k)=x(find(f>=p(k),1)); end
end
