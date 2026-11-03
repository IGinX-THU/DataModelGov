function result=sht_tc24_uq_validation_and_delivery(result)
% 三部件UQ独立验证。不得读取六部件历史真值或对历史后验作混合。
% B输出传播全部显式联合参数；C/D补充同一矩边缘化目标的条件附加参数。
% 独立新试车重新产生传感器偏置，不能扣除训练试车的Wf_bias。
method=result.method;timer=tic;
if isfield(result,'validationRuntime_s') && ~isfield(result,'firstValidationRuntime_s')
    result.firstValidationRuntime_s=result.validationRuntime_s;
end
if strcmp(method,'B'),io=@sht_steady_model_uq_b_io;common=@sht_steady_model_uq_b_common;last=9;
else,io=@sht_steady_model_uq_c_io;common=@sht_steady_model_uq_c_common;last=5;end
if strcmp(method,'D'),last=3;end
resolveCfg=struct('runId',result.runId);
if isfield(result,'config'),resolveCfg=result.config;end
manifest=io('resolve',resolveCfg);
for k=1:last,result.steps{k}=io('loadstep',manifest,k);end
contract=result.steps{1}.contract;
plotEnabled=~isfield(contract.config,'plotEnabled')||contract.config.plotEnabled;
if strcmp(method,'B')
    posterior=result.steps{8}.formal;diagnostic=result.steps{9};base=contract;
else
    posterior=result.steps{last}.formal;diagnostic=result.steps{last};base=contract.baseContract;
end
assert(contract.modelMode==0,'TC24:UQ:Mode','后验必须来自本次三部件合同。');
out=io('reportfile',manifest,'TC24_validation_marker.txt');out=fileparts(out);
root=fileparts(mfilename('fullpath'));middle=fullfile(root,'MiddleData','three_component');
if isfield(contract.config,'outputDirectory') && ~isempty(contract.config.outputDirectory)
    middle=fullfile(contract.config.outputDirectory,result.runId,'MiddleData');
    if ~exist(middle,'dir'),mkdir(middle);end
end
previousFile=fullfile(middle,['tc24_uq_',lower(method),'_latest.mat']);
if isfile(previousFile) && ~isfield(result,'firstValidationRuntime_s')
    previous=load(previousFile,'result');previous=previous.result;
    if strcmp(previous.runId,result.runId) && isfield(previous,'validationRuntime_s')
        result.firstValidationRuntime_s=previous.validationRuntime_s;
        if isfield(previous,'firstValidationRuntime_s')
            result.firstValidationRuntime_s=previous.firstValidationRuntime_s;
        end
    end
end
result.posterior=posterior;result.posteriorDiagnostic=diagnostic;
fast=strcmp(method,'D') && isfield(result,'predictionMode') && strcmp(result.predictionMode,'linearized');
conditional=[];
if ~strcmp(method,'B')
    if fast
        conditional=sht_tc24_uq_d_fast_prediction('conditional',contract,result.steps{2},diagnostic,posterior.theta);
    else
        conditional=sht_tc24_uq_conditional_nuisance(contract,result.steps{2},posterior.theta);
    end
    result.conditionalNuisance=conditional;
end
summary=sht_steady_model_uq_sampler('summary',posterior.theta,posterior.weights,contract);
if isfield(contract,'deterministicEstimate')
    % B的thetaHat是零中心参考点，不是确定性辨识结果；附加参数未辨识记NaN。
    summary.deterministic_estimate=contract.deterministicEstimate(:);
end
% 此时后验已冻结，才允许读隐藏真值进行独立评价；不能反向修改后验权重。
bench=[];truth=nan(height(summary),1);
if isfield(contract.config,'syntheticValidationFile') && ~isempty(contract.config.syntheticValidationFile)
    loaded=load(contract.config.syntheticValidationFile,'result');bench=loaded.result;
    truth=local_parameter_truth(contract,bench);
end
result.syntheticTruthValidationPerformed=~isempty(bench);
comparison=summary;comparison.truth=truth;
comparison.mean_error=summary.posterior_mean-truth;
comparison.truth_covered=truth>=summary.q025 & truth<=summary.q975;
writetable(comparison,fullfile(out,'TC24_parameter_intervals_and_truth.csv'));
if plotEnabled
    try,local_plot_intervals(comparison,method,out);
    catch e,warning('TC24:UQ:OptionalPlot','参数图失败但结果保留：%s',e.message);end
end
fuel=contract.parameterTable.unit=="kg/s";
metrics=struct('dimensionlessMeanRMSE',sqrt(mean(comparison.mean_error(~fuel).^2)), ...
    'fuelBiasMeanRMSE_kgps',sqrt(mean(comparison.mean_error(fuel).^2)), ...
    'truthCoverageCount',nnz(comparison.truth_covered),'parameterCount',height(comparison));
result.parameterTruthComparison=comparison;result.parameterTruthMetrics=metrics;
validation=struct('posteriorInferenceRoute',contract.route,'outputPredictionRoute','steady', ...
    'transientInstantOutputUncertaintyAnalyzed',false,'testDataUsedForInference',false, ...
    'measurementUncertaintyIncluded',true,'modelDiscrepancyIncluded',true, ...
    'predictionErrorRealization','independent_repeated_measurement_engineering_scenario', ...
    'sameBatchBiasConditionedOnTraining',false,'marginalizedNuisancePredictionIncluded',false, ...
    'uncertaintyScope','joint_explicit_parameters_and_independent_measurement_model_discrepancy', ...
    'testPosteriorWeightsUpdated',false);
validation.trainingFuelBiasAppliedToNewTrial=false;
validation.newFuelBiasIncluded=true;
validation.newTrialCommonBiasSharedAcrossPoints=true;
if ~strcmp(method,'B')
    validation.uncertaintyScope='explicit_posterior_conditional_nuisance_moment_approximation_and_new_trial_errors';
    if isfield(conditional,'quadratureSamples')
        validation.uncertaintyScope='explicit_posterior_bounded_conditional_nuisance_affine_propagation_and_new_trial_errors';
    end
    validation.marginalizedNuisancePredictionIncluded=true;
    validation.maximumNuisanceMarginalOutsideSupportProbability=max(conditional.marginalOutsideSupportProbability(:));
end
% D可选预算仅作用于预测云；上面的参数统计和正式Excel仍保存全部后验。
predictionCount=size(posterior.theta,2);predictionSeed=20261031;
if strcmp(method,'D') && ~fast && isfield(result,'predictionSampleCount'),predictionCount=result.predictionSampleCount;end
if strcmp(method,'D') && isfield(result,'predictionRandomSeed'),predictionSeed=result.predictionRandomSeed;end
[posterior,predictionSampling]=sht_tc24_uq_prediction_sample(posterior,predictionCount,predictionSeed);
validation.predictionSampling=predictionSampling;
if predictionSampling.enabled && ~strcmp(method,'B')
    conditional=sht_tc24_uq_conditional_nuisance(contract,result.steps{2},posterior.theta);
end
sets={'training','test'};mass=nan(2,1);
control=[];if isfield(resolveCfg,'runControl'),control=resolveCfg.runControl;end
firstSet=1;
if ~isempty(control)
    [savedPrediction,foundPrediction]=sht_tc24_run_control('load',control,'uq_prediction');
    if foundPrediction
        validation=savedPrediction.validation;mass=savedPrediction.mass;firstSet=savedPrediction.nextSet;
    end
end
for s=firstSet:2
    skipPrediction=fast && s==1 && isfield(result,'predictionTrainingEnabled') && ~result.predictionTrainingEnabled;
    if s==1,data=contract.trainingData;else,data=sht_steady_model_uq_common('loaddata',base,'test');end
    if isempty(data)
        validation.([sets{s},'Table'])=table();
        validation.([sets{s},'OutputPredictionComputed'])=false;continue;
    end
    [observation,labels,units]=sht_steady_model_uq_common('observation',base,data,'steady');
    cacheRoot=fileparts(base.cacheFile);
    if ~strcmp(method,'B'),cacheRoot=fileparts(contract.auxiliaryContract.cacheFile);end
    cache=fullfile(cacheRoot,['exact_output_',sets{s},'_steady_cache_',contract.contractHash,'.mat']);
    opts=struct('routeOverride','steady','useCache',true, ...
        'useRobustTransientFallback',true,'cacheFile',cache,'independentRemeasurement',true);
    nuisancePredictionVariance=zeros(numel(observation),1);
    if skipPrediction
        exact=struct('residual',nan(numel(observation),size(posterior.theta,2)), ...
            'valid',false(1,size(posterior.theta,2)));
        nuisancePredictionVariance(:)=NaN;
    elseif fast
        [exact,nuisancePredictionVariance,fastAudit,Gprediction]=sht_tc24_uq_d_fast_prediction( ...
            'predict',contract,data,posterior,conditional,diagnostic,opts);
        validation.([sets{s},'FastPredictionAudit'])=fastAudit;
        validation.([sets{s},'NuisancePredictionJacobian'])=Gprediction;
        writetable(fastAudit.spotChecks,fullfile(out,['TC24_D_',sets{s},'_linear_spot_checks.csv']));
    elseif ~strcmp(method,'B')
        % 在实际截断先验均值处作物理回放，再叠加条件均值修正。
        joint=[posterior.theta;repmat(conditional.priorMean,1,size(posterior.theta,2))];
        exact=sht_steady_model_uq_b_common('evaluate',contract.auxiliaryContract,joint,data,opts);
        exact=local_complete_pointwise(contract.auxiliaryContract,joint,data,opts,exact);
        [Gprediction,referenceAudit]=sht_tc24_uq_prediction_nuisance_jacobian( ...
            contract,data,posterior,conditional,opts,exact);
        validation.([sets{s},'NuisanceReferenceAudit'])=referenceAudit;
        exact.residual=exact.residual+Gprediction*(conditional.mean-conditional.priorMean);
        exact.valid=exact.valid & conditional.trainingValid;
        nuisancePredictionVariance=max(diag(Gprediction*conditional.covariance*Gprediction.'),0);
        validation.([sets{s},'NuisancePredictionJacobian'])=Gprediction;
    else
        exact=common('evaluate',contract,posterior.theta,data,opts);
        exact=local_complete_pointwise(contract,posterior.theta,data,opts,exact);
    end
    valid=logical(exact.valid);w=posterior.weights(:);w=w/sum(w);
    mass(s)=sum(w(valid));
    if ~fast,assert(mass(s)>0,'TC24:UQ:NoValidPrediction','稳态预测无有效粒子。');end
    prediction=observation+exact.residual;
    pointValid=reshape(all(reshape(isfinite(prediction),numel(observation)/height(data),height(data),[]),1),height(data),[]);
    if ~strcmp(method,'B'),pointValid=pointValid & conditional.trainingValid;end
    pointMass=pointValid*w;
    if ~fast,assert(all(pointMass>0),'TC24:UQ:EmptyPoint','某个预测工况没有有效概率质量。');end
    weights=(pointValid.*w.')./max(pointMass,eps);
    if fast,mass(s)=NaN;pointMass(:)=NaN;end
    if strcmp(method,'B'),covCommon=@sht_steady_model_uq_b_common;covContract=contract;
    else,covCommon=@sht_steady_model_uq_common;covContract=base;end
    covarianceOptions=struct('routeOverride','steady','useRobustTransientFallback',true, ...
        'independentRemeasurement',true);
    if skipPrediction
        measurement=struct('selected',struct('covariance',nan(numel(observation))),'notComputed',true);
    else
        inputCov=covCommon('inputcovariance',covContract,data,covarianceOptions);
        measurement=covCommon('measurementcovariance',covContract,inputCov,data,covarianceOptions);
    end
    if ~strcmp(method,'B') && isfield(conditional,'quadratureSamples')
        tableValue=local_prediction_table(data,observation,labels,units,prediction, ...
            nuisancePredictionVariance,diag(measurement.selected.covariance),weights,conditional,Gprediction);
    else
        tableValue=local_prediction_table(data,observation,labels,units,prediction, ...
            nuisancePredictionVariance,diag(measurement.selected.covariance),weights);
    end
    tableValue.valid_posterior_mass=repelem(pointMass,numel(observation)/height(data));
    deterministicTheta=contract.thetaHat;
    if isfield(contract,'deterministicEstimate')
        deterministicTheta=contract.deterministicEstimate;
        deterministicTheta(~isfinite(deterministicTheta))=0;
    end
    deterministicOptions=opts;
    if ~strcmp(method,'B')
        deterministicOptions.cacheFile=fullfile(fileparts(base.cacheFile), ...
            ['exact_output_',sets{s},'_steady_cache_',contract.contractHash,'.mat']);
    end
    if skipPrediction,deterministic=struct('residual',nan(numel(observation),1));
    else,deterministic=common('evaluate',contract,deterministicTheta,data,deterministicOptions);end
    tableValue.deterministic_model_mean=observation+deterministic.residual(:,1);
    tableValue.deterministic_absolute_relative_error_pct= ...
        100*abs(deterministic.residual(:,1))./max(abs(observation),eps);
    % 物理真值只用于图与报告，正式Excel导出器会删去truth列。
    tableValue.truth=nan(height(tableValue),1);
    if ~isempty(bench),tableValue.truth=local_output_truth(bench,tableValue.point_id,tableValue.output);end
    tableValue.model_truth_covered=tableValue.truth>=tableValue.model_q025 & tableValue.truth<=tableValue.model_q975;
    validation.([sets{s},'Table'])=tableValue;
    validation.([sets{s},'Covariance'])=measurement;
    validation.([sets{s},'Prediction'])=prediction;
    validation.([sets{s},'ValidMask'])=valid;
    validation.([sets{s},'PointValidMask'])=pointValid;
    validation.([sets{s},'PointValidMass'])=pointMass;
    validation.([sets{s},'ConditionalNuisanceVariance'])=nuisancePredictionVariance;
    writetable(tableValue,fullfile(out,['TC24_',sets{s},'_steady_prediction_intervals.csv']));
    if ~skipPrediction && plotEnabled
        try,local_plot_prediction(tableValue,method,sets{s},out);
        catch e,warning('TC24:UQ:OptionalPlot','预测图失败但结果保留：%s',e.message);end
    end
    fprintf('TC24 UQ-%s %s: valid posterior mass %.3f%%, model mean relative MAE %.5f%%.\n', ...
        method,sets{s},100*mass(s),mean(tableValue.absolute_relative_error_pct));
    if ~isempty(control)
        % 每套数据的完整预测及误差传播是安全单元；中途停止请求不破坏概率权重。
        sht_tc24_run_control('boundary',control,'uq_prediction', ...
            struct('validation',validation,'mass',mass,'nextSet',s+1));
    end
end
validation.acceptance=struct('posteriorSamplerPassed',posterior.passed, ...
    'trainingValidMass',mass(1),'testValidMass',mass(2),'minimumValidMass',.95, ...
    'truthUsedAsGate',false,'passed',posterior.passed && all(mass(isfinite(mass))>=.95));
validation.passed=validation.acceptance.passed;
% 预测选根诊断不反向否定已冻结的参数后验，不据此删改后验粒子或权重。
% 每点区间独立使用该点有效质量；不足95%仍明确保留警告和条件区间身份。
validation.posteriorDeliveryReady=posterior.passed;
validation.predictionConditioning='per_point_valid_root_domain';
if fast
    validation.predictionConditioning='local_linearized_at_valid_reference_not_global_root_conditioned';
    validation.uncertaintyScope='local_linearized_joint_parameters_and_independent_new_trial_errors';
    validation.acceptance=struct('posteriorSamplerPassed',posterior.passed, ...
        'exactRootMassEvaluated',false,'truthUsedAsGate',false,'passed',posterior.passed);
    validation.passed=posterior.passed;
    validation.trainingOutputPredictionComputed=~isfield(result,'predictionTrainingEnabled') || result.predictionTrainingEnabled;
end
validation.posteriorWeightsChangedForPrediction=predictionSampling.enabled;
validation.originalParameterPosteriorUnchanged=true;
validation.formalGlobalPosterior=~strcmp(method,'D') && posterior.passed;
if strcmp(method,'D'),validation.localApproximationQuality=diagnostic.quality;end
result.validation=validation;result.passed=posterior.passed;
result.deliveryTag='pointwise_v4';
if fast,result.deliveryTag='linearized_R047';end
if predictionSampling.enabled
    result.deliveryTag=sprintf('pointwise_v4_p%d_s%d',predictionCount,predictionSeed);
end
result.steps{last+1}=validation;
[manifest,~]=io('savestep',manifest,last+1,'tc24_independent_validation',validation,toc(timer));
result.manifest=manifest;result.reportDirectory=out;
if result.passed
    result.delivery=sht_export_2p4_uq_delivery(method,result);
else
    result.delivery=struct('passed',false,'workbookFile','');
    warning('TC24:UQ:DiagnosticOnly','采样或有效预测质量未通过，保存诊断结果，不伪称正式后验。');
end
result.validationRuntime_s=toc(timer);
save(fullfile(middle,['tc24_uq_',lower(method),'_latest.mat']),'result','-v7.3');
fprintf('TC24 UQ-%s: parameter RMSE %.6g; fuel RMSE %.6g kg/s; coverage %d/%d; passed=%d.\n', ...
    method,metrics.dimensionlessMeanRMSE,metrics.fuelBiasMeanRMSE_kgps, ...
    metrics.truthCoverageCount,metrics.parameterCount,result.passed);
end

function exact=local_complete_pointwise(contract,theta,data,opts,exact)
% 联合似然要求全部工况有效；预测则不能因一个工况失败而丢弃其他工况。
% 仅补算原联合缓存中无效的候选，每点独立缓存。未收敛值始终保持NaN。
bad=find(~exact.valid);if isempty(bad),return;end
m=size(exact.residual,1)/height(data);[folder,stem]=fileparts(opts.cacheFile);
for j=1:height(data)
    one=opts;one.cacheFile=fullfile(folder,sprintf('pointwise_%03d',j),[stem,'.mat']);
    q=sht_steady_model_uq_b_common('evaluate',contract,theta(:,bad),data(j,:),one);
    rows=(j-1)*m+(1:m);exact.residual(rows,bad)=q.residual;
    fprintf('TC24 pointwise prediction %s: %d/%d formerly joint-invalid candidates have a valid root.\n', ...
        string(data.point_id(j)),nnz(q.valid),numel(bad));
end
exact.valid=all(isfinite(exact.residual),1);
end

function truth=local_parameter_truth(contract,bench)
tbl=contract.parameterTable;truth=zeros(height(tbl),1);
for i=1:height(tbl)
    h=tbl.c_index(i);x=tbl.coordinate(i);
    if h<0
        measured=bench.measurement.Wf_mean;
        b=cellfun(@(a)mean(a.bias.Wf(a.windowMask)),bench.histories);
        [measured,order]=sort(measured);b=b(order);
        wf=x*contract.scheduleTemplate.fuelBias.wfDesign;
        truth(i)=interp1(measured,b,min(max(wf,measured(1)),measured(end)),'linear');
    else
        p=bench.profile.parameters([bench.profile.parameters.cIndex]==h);
        if strcmp(p.mode,'constant'),truth(i)=p.designValue;
        else,truth(i)=p.designValue+interp1(p.xNodes,p.deltaNodes,min(max(x,p.xNodes(1)),p.xNodes(end)),'linear');end
    end
end
end

function value=local_output_truth(bench,ids,names)
value=nan(numel(ids),1);
for i=1:numel(ids)
    row=find(bench.truth.point_id==ids(i));name=char(names(i));
    if strcmp(name,'Wa2'),value(i)=bench.truth.Wa1_mean(row)-bench.truth.Wb_mean(row);
    else,value(i)=bench.truth.([name,'_mean'])(row);end
end
end

function t=local_prediction_table(data,obs,labels,units,pred,modelVariance,errorVariance,w,nc,G)
names=sht_tc24_uq_measurement('role','steady');names=names.residualOrder;
modelLow=zeros(size(obs));modelHigh=modelLow;obsLow=modelLow;obsHigh=modelLow;modelMean=modelLow;
for j=1:numel(obs)
    row=ceil(j/numel(names));valid=w(row,:)>0 & isfinite(pred(j,:));weight=w(row,valid).';
    values=pred(j,valid);variance=modelVariance(j);
    if isempty(values) || ~isfinite(variance)
        modelMean(j)=NaN;modelLow(j)=NaN;modelHigh(j)=NaN;obsLow(j)=NaN;obsHigh(j)=NaN;continue;
    end
    if nargin>=9 && isfield(nc,'quadratureSamples')
        [values,weight]=sht_tc24_uq_nuisance_output_cloud(values,G(j,:),nc,find(valid),weight);
        variance=0;
    end
    modelMean(j)=values(:).'*weight;
    q=sht_tc24_uq_mixture_quantile(values,variance,weight,[.025,.975]);
    modelLow(j)=q(1);modelHigh(j)=q(2);
    q=sht_tc24_uq_mixture_quantile(values,variance+errorVariance(j),weight,[.025,.975]);
    obsLow(j)=q(1);obsHigh(j)=q(2);
end
ids=repelem(string(data.point_id),numel(names));output=repmat(string(names(:)),height(data),1);
errorPct=100*abs(modelMean-obs)./max(abs(obs),eps);
t=table(ids,output,string(labels(:)),string(units(:)),obs,modelMean,modelLow,modelHigh,obsLow,obsHigh,errorPct, ...
    'VariableNames',{'point_id','output','label','unit','measured','model_mean', ...
    'model_q025','model_q975','observable_q025','observable_q975','absolute_relative_error_pct'});
end

function local_plot_intervals(t,method,out)
f=figure('Visible','off','Position',[80,40,1550,950]);
% 燃油偏置有kg/s单位，不能与无量纲健康系数共用纵坐标。
fuel=find(t.unit=="kg/s");health=find(t.unit~="kg/s");groups={};
for first=1:20:numel(health),groups{end+1}=health(first:min(first+19,numel(health)));end
if ~isempty(fuel),groups{end+1}=fuel;end
panels=numel(groups);
for k=1:panels
    subplot(ceil(panels/2),2,k);idx=groups{k};x=1:numel(idx);
    % 偏斜分布的均值未必位于等尾区间内，直接画端点，不以负误差棒表示。
    interval=plot([x;x],[t.q025(idx).';t.q975(idx).'],'b-');hold on;
    meanHandle=plot(x,t.posterior_mean(idx),'bo','MarkerSize',3);
    truthHandle=plot(x,t.truth(idx),'rx');grid on;xticks(x);xticklabels(t.name(idx));xtickangle(60);
    set(gca,'TickLabelInterpreter','none');
    xlim([.5,numel(idx)+.5]);
    local_interval_limits([t.q025(idx);t.q975(idx);t.posterior_mean(idx);t.truth(idx)]);
    ylabel(char(t.unit(idx(1))));
    if k==1
        handles=[interval(1),meanHandle];labels={'Posterior 95%','Posterior mean'};
        if any(isfinite(t.truth)),handles(end+1)=truthHandle;labels{end+1}='Truth';end
        legend(handles,labels,'Location','northoutside','Orientation','horizontal','FontSize',8);
    end
end
sgtitle(['TC24 ',method,': parameter intervals']);
print(f,fullfile(out,'TC24_parameter_intervals.png'),'-dpng','-r160');close(f);
end

function local_plot_prediction(t,method,setName,out)
names=unique(t.output,'stable');f=figure('Visible','off','Position',[80,40,1450,850]);
axesHandles=gobjects(numel(names),1);
for k=1:numel(names)
    axesHandles(k)=subplot(3,3,k);s=t(t.output==names(k),:);x=1:height(s);
    observableHandle=plot([x;x],[s.observable_q025.';s.observable_q975.'], ...
        'Color',[.75,.75,.75],'LineWidth',3);hold on;
    interval=plot([x;x],[s.model_q025.';s.model_q975.'],'b-');
    meanHandle=plot(x,s.model_mean,'bo-');
    measuredHandle=plot(x,s.measured,'kx');truthHandle=plot(x,s.truth,'r+');grid on;
    title(char(names(k)));ylabel(char(s.unit(1)));xticks(x);xticklabels(s.point_id);xtickangle(45);
    xlim([.7,height(s)+.3]);
    local_interval_limits([s.observable_q025;s.observable_q975;s.model_q025; ...
        s.model_q975;s.model_mean;s.measured;s.truth]);
    if k==1
        legendHandles=[observableHandle(1),interval(1),meanHandle,measuredHandle,truthHandle];
    end
end
% 统一固定三列网格；标题、图例各占独立上边栏，避免legend挤压首图。
legendLabels={'Observable 95% (engineering)','Parameter 95%','Model mean','Measured','Truth'};
if ~any(isfinite(t.truth)),legendHandles(end)=[];legendLabels(end)=[];end
sharedLegend=legend(axesHandles(1),legendHandles,legendLabels, ...
    'Orientation','horizontal','FontSize',9,'Box','off');
set(sharedLegend,'Units','normalized','Position',[.08,.937,.84,.028]);
for k=1:numel(names)
    row=floor((k-1)/3);col=mod(k-1,3);
    set(axesHandles(k),'Units','normalized','Position',[.09+.305*col,.70-.30*row,.245,.20]);
end
annotation(f,'textbox',[.1,.972,.8,.024],'String', ...
    ['TC24 ',method,': ',setName,' steady prediction'], ...
    'EdgeColor','none','HorizontalAlignment','center','VerticalAlignment','middle','FontSize',13);
print(f,fullfile(out,['TC24_',setName,'_prediction_intervals.png']),'-dpng','-r150');close(f);
end

function local_interval_limits(values)
% 显式包含全部区间端点与对照点，避免自动坐标把边缘标记裁掉。
values=values(isfinite(values));
if isempty(values),return;end
lo=min(values);hi=max(values);span=max(hi-lo,max(abs(values))*1e-4);
pad=max(.08*span,eps(max(1,max(abs(values)))));
ylim([lo-pad,hi+pad]);
end
