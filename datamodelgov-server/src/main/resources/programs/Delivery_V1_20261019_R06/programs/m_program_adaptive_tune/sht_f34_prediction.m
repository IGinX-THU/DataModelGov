function result=sht_f34_prediction(prepared,likelihood,methodD,methodC,userOptions)
%SHT_F34_PREDICTION 独立任务的固定传递和下一架次分层预测。
%
% 当前首轮在独立验证任务的稳态窗口上给出三层区间：显式参数、物理
% 预测（含曲线形状、输入误差和模型差异）、可观测预测（再加输出测量
% 误差）。固定传递不增加Q；下一架次先传播Q再预测。验证输出只在后验
% 冻结后读取，不参与方法C/D的先验、似然或停止条件。

if ischar(prepared)&&strcmpi(prepared,'mixtureInterval')
    % 独立新工况复用同一加权混合分位数，不改变原验证路径的数学定义。
    result=local_mixture_interval(likelihood,methodD,methodC);return;
end
if ischar(prepared)&&strcmpi(prepared,'validationEvidence')
    % 只核Excel/选段，不建立热会话，也不打开DLL。
    result=local_validation_evidence(likelihood,methodD);return;
end
if nargin<5||isempty(userOptions),userOptions=struct();end
options=prepared.options;
names=fieldnames(userOptions);
for i=1:numel(names),options.(names{i})=userOptions.(names{i});end
if ~isfield(likelihood,'preparedContractSha256')|| ...
        ~strcmp(likelihood.preparedContractSha256,sht_f33_model_adapt_v2( ...
        'structHash',prepared.contract))
    error('SHT:F34Prediction:PreparedLineage', ...
        '似然与当前准备合同不一致，禁止使用历史合同进行预测。');
end
hasC=~isempty(methodC);
if ~isfield(methodD,'likelihoodContractHash')|| ...
        ~strcmp(methodD.likelihoodContractHash,likelihood.contractHash)|| ...
        (hasC && (~isfield(methodC,'likelihoodContractHash')|| ...
        ~strcmp(methodC.likelihoodContractHash,likelihood.contractHash)))
    error('SHT:F34Prediction:Lineage', ...
        '方法C/D与当前似然合同不一致，禁止混用历史结果预测。');
end
if isfield(likelihood,'cacheFile')
    cacheFile=likelihood.cacheFile;
else
    cacheFile=fullfile(prepared.paths.runDir,'f34_exact_physics_cache.mat');
end
sht_f34_likelihood('loadCache',likelihood,cacheFile);
cacheCleanup=onCleanup(@()sht_f34_likelihood( ...
    'saveCache',likelihood,cacheFile)); %#ok<NASGU>
thisDir=prepared.paths.thisDir;
validationWorkbook=fullfile(thisDir,'TestData', ...
    'flight_data_3p1_independent_validation_history.xlsx');
if options.modelMode==0,p=sht_f3_current_contract('paths');validationWorkbook=p.test;end
if isfield(userOptions,'validationWorkbook')
    validationWorkbook=userOptions.validationWorkbook;
end
if ~isfile(validationWorkbook)
    error('SHT:F34Prediction:Workbook','独立验证Excel不存在：%s。',validationWorkbook);
end

fprintf('\n3.4.9 构造独立任务两类分层预测……\n');started=tic;
[testContext,testData,testSource,testMeta]=local_test_context( ...
    prepared,validationWorkbook,userOptions);
cleanup=onCleanup(@()sht_f33_model_adapt_v2('closeUqContext',testContext)); %#ok<NASGU>
observation=[testData.Np_mean,testData.Ng_mean,testData.Pt3_mean,testData.Tt45_mean];
observationVector=observation(:);
[inputCovariance,outputCovariance,modelCovariance,inputAudit]= ...
    local_prediction_covariance(testContext,prepared.prior,methodD, ...
    likelihood,options,testSource);

methodDPrediction=local_method_d_prediction(prepared.context,testContext, ...
    prepared.prior,methodD,likelihood,inputCovariance,outputCovariance, ...
    modelCovariance,options);
methodCPrediction=[];
% 对照仅在后验冻结后计算；相同测试点、热平衡模型和输入驱动选根，
% 区分原2.4确定性基准、R020辨识及当前含条件形状更新的D中心预测。
baselineTheta=[zeros(height(prepared.prior.parameterTable),1), ...
    prepared.context.uqReferenceResult.estimatedTheta(:)];
baselineModels=sht_f33_model_adapt_v2('thetaToModels',testContext,baselineTheta);
baselineValue=local_evaluate_schedule_batch(testContext,baselineModels.schedules,baselineModels.recoveries);
baselineLabels={'TC24_deterministic','current_deterministic','D_local_center'};
baselineValue=[baselineValue,methodDPrediction.fixed_transfer.observable.mean];
baselineComparison=table();
for k=1:3
    for j=1:4
        idx=(j-1)*height(testData)+(1:height(testData));
        names={'Np','Ng','Pt3_eq','Tt45'};units={'rpm','rpm','Pa','K'};
        e=baselineValue(idx,k)-observationVector(idx);
        baselineComparison=[baselineComparison;table(string(baselineLabels{k}), ...
            string(names{j}),string(units{j}),sqrt(mean(e.^2)),mean(e),max(abs(e)), ...
            'VariableNames',{'model','channel','unit','rmse','mean_error','max_abs_error'})]; %#ok<AGROW>
    end
end
summary=local_prediction_summary('D',methodDPrediction,observationVector);
detail=local_prediction_detail('D',methodDPrediction,testData);
if hasC
    methodCPrediction=local_method_c_prediction(testContext,prepared.prior, ...
        methodC,likelihood,inputCovariance,outputCovariance,modelCovariance,options);
    summary=[summary;local_prediction_summary('C',methodCPrediction,observationVector)];
    detail=[detail;local_prediction_detail('C',methodCPrediction,testData)];
end
result=struct('schemaVersion','SHT_F34_R1_PREDICTION_V1', ...
    'createdAt',datestr(now,31),'validationWorkbook',validationWorkbook, ...
    'validationWorkbookSha256',sht_f33_model_adapt_v2( ...
    'fileHash',validationWorkbook),'testData',testData,'testSource',testSource, ...
    'testContextMetadata',testMeta,'observation',observationVector, ...
    'inputCovariance',inputCovariance,'outputCovariance',outputCovariance, ...
    'modelDiscrepancyCovariance',modelCovariance,'inputAudit',inputAudit, ...
    'methodD',methodDPrediction,'methodC',methodCPrediction, ...
    'summary',summary,'detail',detail,'runtime_s',toc(started), ...
    'inferenceTestDataUsed',false,'predictionTestDataUsed',true, ...
    'truthDataUsed',false,'scope','independent_task_steady_windows', ...
    'likelihoodContractHash',likelihood.contractHash, ...
    'physicsContractHash',likelihood.physicsContractHash, ...
    'processCovarianceCalibrated',false, ...
    'processCovarianceStatus', ...
        'ENGINEERING_ASSUMPTION_REQUIRES_FUTURE_LONGITUDINAL_STUDY');
fprintf('预测完成：独立任务%d个稳态窗口，耗时 %.1f s。\n', ...
    height(testData),result.runtime_s);
result.posteriorPredictionIdentity=sht_f34_prediction_identity(likelihood,methodD,methodC);
result.baselineComparison=baselineComparison;
% 该包只供独立测试进程给定工况和比较结果，不是正式Excel隐藏依赖。
result.excelVerificationInputs=struct('points',testData,'branch',testContext.uqThermalBranch);
disp(summary);
end

function [context,points,source,metadata]=local_test_context(prepared,fileName,userOptions)
userOptions.validationWorkbook=fileName;
e=local_validation_evidence(prepared,userOptions);
history=e.history;segments=e.segments;segmentLineage=e.lineage;
required={'Ps0','Tt1','Pt3_eq','Ng','Np','Mkp','Mkg','Wf','Tt45', ...
    'Altitude','Mach','Ts_amb','time_s'};
if prepared.options.modelMode==0
    required(strcmp(required,'Mkg'))=[];
    history.Mkg=zeros(height(history),1); % 内部给定的零附件负载，不声明为测量。
end
if ~all(ismember(required,history.Properties.VariableNames))
    error('SHT:F34Prediction:Schema','独立任务缺少正式可测字段。');
end
row=find(string(segments.segment_class)=="steady_window");
if ismember('usable',segments.Properties.VariableNames),row=row(logical(segments.usable(row)));end
if isempty(row),error('SHT:F34Prediction:Segments','独立任务没有稳态窗口。');end
n=numel(row);point_id=strings(n,1);sample_count=zeros(n,1);
start_s=zeros(n,1);end_s=zeros(n,1);
Np_mean=zeros(n,1);Ng_mean=zeros(n,1);Wf_mean=zeros(n,1);Tt45_mean=zeros(n,1);
Mkp_mean=zeros(n,1);Mkg_mean=zeros(n,1);Tt1_mean=zeros(n,1);Pt3_mean=zeros(n,1);
Pamb_mean=zeros(n,1);Tamb_mean=zeros(n,1);Altitude_mean=zeros(n,1);Mach_mean=zeros(n,1);
for i=1:n
    index=round(segments.first(row(i))):round(segments.last(row(i)));
    point_id(i)=string(segments.segment_id(row(i)));sample_count(i)=numel(index);
    start_s(i)=segments.start_s(row(i));end_s(i)=segments.end_s(row(i));
    Np_mean(i)=mean(history.Np(index));Ng_mean(i)=mean(history.Ng(index));
    Wf_mean(i)=mean(history.Wf(index));Tt45_mean(i)=mean(history.Tt45(index));
    Mkp_mean(i)=mean(history.Mkp(index));Mkg_mean(i)=mean(history.Mkg(index));
    Tt1_mean(i)=mean(history.Tt1(index));Pt3_mean(i)=mean(history.Pt3_eq(index));
    Pamb_mean(i)=mean(history.Ps0(index));Tamb_mean(i)=mean(history.Ts_amb(index));
    Altitude_mean(i)=mean(history.Altitude(index));Mach_mean(i)=mean(history.Mach(index));
end
Pt45_mean=101325*ones(n,1);Pt2_mean=101325*ones(n,1);Tt3_mean=500*ones(n,1);
inlet_pressure_recovery_mean=0.995*ones(n,1);
points=table(point_id,Np_mean,Ng_mean,Wf_mean,Tt45_mean,Pt45_mean, ...
    Mkp_mean,Mkg_mean,Pt2_mean,Tt1_mean,Pt3_mean,Tt3_mean,Pamb_mean, ...
    Tamb_mean,Altitude_mean,Mach_mean,inlet_pressure_recovery_mean);
source=table(point_id,start_s,end_s,sample_count);

replayOptions=struct('cacheDirectory',fullfile(prepared.paths.runDir, ...
    'prediction_root_cache'),'sourceSha256',sht_f33_model_adapt_v2( ...
    'fileHash',fileName),'integrationMethod','euler2', ...
    'sensorDynamicsEnabled',true,'progressIntervalSamples',8000, ...
    'inletMeanRecovery',0.995);
% 选根前史是输入驱动的预测，不把测量Np作为稳态选根依据。
% 沿用确定性结果明确指定的积分设置，避免记录周期隐式改变求值身份。
if isfield(prepared.context.options,'historyIntegrationStep_s')
    replayOptions.integrationStep_s=prepared.context.options.historyIntegrationStep_s;
end
replay=sht_f32_replay_history('run',history,prepared.context.replayAssets, ...
    'personalized',prepared.context.sensorAssumptions,replayOptions);
if ~replay.computationallyAccepted
    error('SHT:F34Prediction:RootReplay','独立任务先验连续回放未通过计算检查。');
end
speedSeed=zeros(n,2);
for i=1:n
    index=round(segments.first(row(i))):round(segments.last(row(i)));
    speedSeed(i,:)=mean(replay.state(index,1:2),1);
end
width=prepared.context.baseResult.options.steadyNpTrainingBranchRelativeHalfWidth;
if ~isscalar(width)||~isfinite(width)||width<=0||width>=1
    error('SHT:F34Prediction:BranchWidth', ...
        '稳态Np物理解选根相对半宽无效：%.6g。',width);
end
branch=struct('pointIds',point_id,'speedSeed',speedSeed, ...
    'relativeHalfWidth',width,'lowerNp',speedSeed(:,1)*(1-width), ...
    'upperNp',speedSeed(:,1)*(1+width), ...
    'source','independent_task_prior_continuous_prediction', ...
    'pointMeasuredSpeedUsed',false,'thermalHistoryUsed',false, ...
    'sourceHash',replay.contractHash,'replayCache',replay.cacheFile, ...
    'assetContract',prepared.context.replayAssets.contract);
context=prepared.context;context.steadyData=points;context.steadySource=source;
% 参数即使来自瞬态时刻辨识，独立输出预测也必须放开两轴转速求解。
context.options.modelRoute='steady';
context.uqThermalBranch=branch;
context.thermalSession=sht_f33_thermal_equilibrium('open', ...
    context.replayAssets,branch,points,context.options.modelRoute);
metadata=struct('rootSelection','prior_continuous_prediction', ...
    'measuredOutputUsedForRoot',false,'hiddenTruthUsedForRoot',false, ...
    'priorReplayCache',replay.cacheFile,'windowCount',n, ...
    'segmentLineage',segmentLineage);
end

function out=local_validation_evidence(prepared,o)
assert(isfield(o,'validationWorkbook')&&isfile(o.validationWorkbook), ...
    'SHT:F34Prediction:Workbook','必须显式指定独立测试Excel。');
file=o.validationWorkbook;[~,sheets]=xlsfinfo(file);
if ismember('Data',sheets)
    history=readtable(file,'Sheet','Data');
    [segments,lineage]=local_validation_segments(prepared,file,height(history));
else
    assert(all(ismember({'history','segments'},sheets))&&isfield(o,'confirmationFile'), ...
        'SHT:F34Prediction:ConfirmedTest','映射后测试需要history/segments及A确认文件。');
    s=load(o.confirmationFile,'receipt');r=s.receipt;
    assert(strcmp(r.receiptIdentity,sht_f33_model_adapt_v2('structHash',rmfield(r,'receiptIdentity'))), ...
        'SHT:F34Prediction:Receipt','确认载荷身份改变。');
    sha=sht_f33_model_adapt_v2('fileHash',file);
    assert(isfield(r.deliveryHashes,'validationWorkbook')&&strcmp(sha,r.deliveryHashes.validationWorkbook), ...
        'SHT:F34Prediction:Payload','映射后测试Excel与A确认不一致。');
    stage32=prepared.contextMetadata.stage32File;
    assert(strcmp(sht_f33_model_adapt_v2('fileHash',stage32),r.deliveryHashes.stage32File), ...
        'SHT:F34Prediction:Stage32Lineage','测试片段与已确认3.2载荷不一致。');
    q=load(stage32,'flightModelAdaptData');datasets=q.flightModelAdaptData.datasets;
    ids=find(arrayfun(@(x)strcmp(x.role,'independent_validation'),datasets));
    assert(numel(ids)==1,'SHT:F34Prediction:ValidationDataset','须有一个独立测试数据集。');
    d=datasets(ids);history=readtable(file,'Sheet','history');segments=readtable(file,'Sheet','segments');
    fields={'sample_id','time_s','Ps0','Tt1','Pt3_eq','Ng','Np','Mkp','Wf','Tt45','Altitude','Mach','Ts_amb'};
    assert(height(history)==d.sampleCount&&all(ismember(fields,history.Properties.VariableNames)), ...
        'SHT:F34Prediction:Schema','测试历程缺少测量量或样本数量不符。');
    for j=1:numel(fields)
        a=history.(fields{j});b=d.measurement.(fields{j});
        assert(numel(a)==numel(b)&&all(isfinite(a))&&max(abs(a-b))<1e-11*max(1,max(abs(b))), ...
            'SHT:F34Prediction:MappedValues','映射测量列%s与3.2不一致。',fields{j});
    end
    expected=d.segmentation.segments;
    for field={'first','last','sample_count','usable'}
        assert(isequal(double(segments.(field{1})),double(expected.(field{1}))), ...
            'SHT:F34Prediction:Selection','测试窗口索引/选择/完整样本数发生变化。');
    end
    for field={'segment_id','segment_class'}
        assert(isequal(string(segments.(field{1})),string(expected.(field{1}))), ...
            'SHT:F34Prediction:Selection','测试窗口身份或分类改变。');
    end
    assert(isequal(sort(string(segments.segment_id(logical(segments.usable)))), ...
        sort(string(r.selection.independent_validation(:)))), ...
        'SHT:F34Prediction:Selection','测试选择未按A确认执行。');
    lineage=struct('stage32File',stage32,'stage32FileSha256',r.deliveryHashes.stage32File, ...
        'sourceWorkbook',d.sourceFile,'sourceWorkbookSha256',d.sourceSha256, ...
        'mappedWorkbook',file,'mappedWorkbookSha256',sha,'confirmationIdentity',r.receiptIdentity, ...
        'datasetRole','independent_validation','segmentCount',height(segments), ...
        'originalSourceIsNotMappedWorkbook',true);
end
selected=string(segments.segment_class)=="steady_window";
if ismember('usable',segments.Properties.VariableNames),selected=selected&logical(segments.usable);end
assert(any(selected),'SHT:F34Prediction:NoSelectedWindows','没有已确认的独立稳态测试窗口。');
out=struct('history',history,'segments',segments,'lineage',lineage, ...
    'selectedSteadyCount',nnz(selected),'actualSamples',sum(segments.last(selected)-segments.first(selected)+1), ...
    'noDll',true,'testUsedInInference',false);
end

function [segments,lineage]=local_validation_segments(prepared,fileName,sampleCount)
if ~isfield(prepared,'contextMetadata')|| ...
        ~isfield(prepared.contextMetadata,'stage32File')
    error('SHT:F34Prediction:Stage32Lineage', ...
        '准备结果没有冻结3.2预处理文件，无法取得独立验证片段。');
end
stage32File=prepared.contextMetadata.stage32File;
if ~isfile(stage32File)
    error('SHT:F34Prediction:Stage32File', ...
        '冻结的3.2预处理文件不存在：%s。',stage32File);
end
loaded=load(stage32File,'flightModelAdaptData');
if ~isfield(loaded,'flightModelAdaptData')|| ...
        ~isfield(loaded.flightModelAdaptData,'datasets')
    error('SHT:F34Prediction:Stage32Schema', ...
        '3.2预处理文件不含正式数据集结构。');
end
datasets=loaded.flightModelAdaptData.datasets;
role=arrayfun(@(value)string(value.role),datasets);
index=find(role=="independent_validation");
if numel(index)~=1
    error('SHT:F34Prediction:ValidationDataset', ...
        '3.2预处理文件中独立验证数据集数量为%d，要求恰好为1。',numel(index));
end
dataset=datasets(index);
sourceHash=sht_f33_model_adapt_v2('fileHash',fileName);
if ~isfield(dataset,'sourceSha256')||~strcmp(dataset.sourceSha256,sourceHash)
    error('SHT:F34Prediction:ValidationLineage', ...
        '独立验证Excel与3.2预处理片段不是同一份冻结证据。');
end
if ~isfield(dataset,'sampleCount')||dataset.sampleCount~=sampleCount
    error('SHT:F34Prediction:ValidationSampleCount', ...
        '独立验证Excel为%d点，3.2预处理记录为%d点。', ...
        sampleCount,dataset.sampleCount);
end
if ~isfield(dataset,'segmentation')|| ...
        ~isfield(dataset.segmentation,'segments')|| ...
        ~istable(dataset.segmentation.segments)
    error('SHT:F34Prediction:SegmentSchema', ...
        '3.2独立验证数据集不含正式片段表。');
end
segments=dataset.segmentation.segments;
required={'segment_id','segment_class','first','last','start_s','end_s'};
if ~all(ismember(required,segments.Properties.VariableNames))
    error('SHT:F34Prediction:SegmentSchema', ...
        '3.2独立验证片段表缺少必需字段。');
end
lineage=struct('stage32File',stage32File, ...
    'stage32FileSha256',sht_f33_model_adapt_v2('fileHash',stage32File), ...
    'sourceWorkbook',fileName,'sourceWorkbookSha256',sourceHash, ...
    'datasetRole','independent_validation', ...
    'segmentationSchemaVersion',dataset.segmentation.schemaVersion, ...
    'segmentCount',height(segments));
end

function [inputCov,outputCov,modelCov,audit]=local_prediction_covariance( ...
        context,prior,methodD,likelihood,options,source)
n=height(context.steadyData);m=4*n;sensor=context.sensorAssumptions;
inputCov=zeros(m);outputCov=zeros(m);modelCov=zeros(m);audit=table();
outputNames={'Np','Ng','Pt3_eq','Tt45'};
for j=1:4
    row=local_sensor_row(sensor,outputNames{j});index=(j-1)*n+(1:n);
    biasStd=sensor.totalBiasHalfWidth(row)/sqrt(3);
    outputCov(index,index)=biasStd^2*ones(n)+ ...
        diag(sensor.noiseStd(row)^2./source.sample_count);
    stdValue=options.modelDiscrepancyFraction(j)*sensor.designReference(row);
    rho=options.modelDiscrepancyCorrelation;
    modelCov(index,index)=stdValue^2*((1-rho)*eye(n)+rho*ones(n));
end

% 输入灵敏度在独立任务的实际稳态窗口重新计算，不能直接套用训练窗口。
[shapeMean,~]=sht_f34_likelihood('conditionalPosterior',likelihood,prior, ...
    methodD.map,methodD.physicalOutputAtMap);
modelSet=sht_f33_model_adapt_v2('thetaToModels',context,methodD.map);
baseSchedule=sht_f34_prior('applyShape',modelSet.schedules{1},prior,shapeMean);
base=local_evaluate_schedule_batch(context,{baseSchedule},modelSet.recoveries);
inputNames={'Wf','Mkp','Mkg','Tt1','Altitude','Mach','Ps0','Ts_amb'};
columns={'Wf_mean','Mkp_mean','Mkg_mean','Tt1_mean', ...
    'Altitude_mean','Mach_mean','Pamb_mean','Tamb_mean'};
if options.modelMode==0,inputNames(3)=[];columns(3)=[];end
for j=1:numel(inputNames)
    row=local_sensor_row(sensor,inputNames{j});
    step=max(options.inputDifferenceScale*sensor.totalBiasHalfWidth(row), ...
        2*sensor.noiseStd(row));
    modified=context;modified.steadyData=context.steadyData;
    modified.steadyData.(columns{j})=modified.steadyData.(columns{j})+step;
    modified.thermalSession=sht_f33_thermal_equilibrium('open', ...
        modified.replayAssets,modified.uqThermalBranch,modified.steadyData, ...
        modified.options.modelRoute);
    cleanup=onCleanup(@()sht_f33_model_adapt_v2('closeUqContext',modified)); %#ok<NASGU>
    value=local_evaluate_schedule_batch(modified,{baseSchedule},modelSet.recoveries);
    derivative=reshape((value-base)/step,n,4);globalVector=derivative(:);
    common=~strcmp(inputNames{j},'Wf');
    if common
        biasStd=sensor.totalBiasHalfWidth(row)/sqrt(3);
        inputCov=inputCov+biasStd^2*(globalVector*globalVector.');
    end
    for k=1:n
        localVector=zeros(m,1);localVector(k+(0:3)*n)=derivative(k,:);
        inputCov=inputCov+(sensor.noiseStd(row)^2/source.sample_count(k))* ...
            (localVector*localVector.');
    end
    audit=[audit;table(string(inputNames{j}),string(sensor.unit(row)),step,common, ...
        'VariableNames',{'channel','unit','difference_step','common_bias_propagated'})]; %#ok<AGROW>
end
inputCov=(inputCov+inputCov.')/2;outputCov=(outputCov+outputCov.')/2;
end

function output=local_method_d_prediction(trainingContext,context,prior, ...
        methodD,likelihood,inputCov,outputCov,modelCov,options)
theta=methodD.map;parameter=prior.parameterTable;d=numel(theta);
shapeMean=methodD.conditionalShapeMean;shapeCov=methodD.conditionalShapeCovariance;
modelSet=sht_f33_model_adapt_v2('thetaToModels',context,theta);
baseSchedule=sht_f34_prior('applyShape',modelSet.schedules{1},prior,shapeMean);
schedules={baseSchedule};recoveries=modelSet.recoveries;
thetaStep=zeros(d,1);shapeSlope=zeros(prior.shape.retainedRank,d);
for i=1:d
    if isfield(methodD,'differenceStep'),magnitude=abs(methodD.differenceStep(i));
    else,magnitude=parameter.difference_step(i);end
    if theta(i)+magnitude<=parameter.upper_bound(i),direction=1;else,direction=-1;end
    accepted=false;
    for directionAttempt=1:2
        trialDirection=direction*(-1)^(directionAttempt-1);
        trialMagnitude=magnitude;
        for attempt=1:8
            thetaStep(i)=trialDirection*trialMagnitude;trial=theta;
            trial(i)=trial(i)+thetaStep(i);
            if trial(i)<parameter.lower_bound(i)||trial(i)>parameter.upper_bound(i)
                trialMagnitude=0.5*trialMagnitude;continue;
            end
            [trainingEval,~,trainingPhysical]=sht_f34_likelihood( ...
                'evaluate',likelihood,trainingContext,prior,trial);
            if trainingEval.valid
                trialShape=sht_f34_likelihood('conditionalPosterior', ...
                    likelihood,prior,trial,trainingPhysical(:,1));
                shapeSlope(:,i)=(trialShape-shapeMean)/thetaStep(i);
                q=sht_f33_model_adapt_v2('thetaToModels',context,trial);
                schedules{end+1}=sht_f34_prior( ...
                    'applyShape',q.schedules{1},prior,trialShape); %#ok<AGROW>
                recoveries(end+1)=q.recoveries; %#ok<AGROW>
                accepted=true;break;
            end
            trialMagnitude=0.5*trialMagnitude;
        end
        if accepted,break;end
    end
    if ~accepted
        error('SHT:F34Prediction:MethodDJacobian', ...
            '参数%s无法得到有效条件形状预测差分点。', ...
            char(parameter.parameter_id(i)));
    end
end
shapeStep=zeros(prior.shape.retainedRank,1);
for i=1:prior.shape.retainedRank
    shapeStep(i)=max(0.35*sqrt(max(prior.shape.coordinateSecondMoment(i),eps)),1e-7);
    if isfield(prior,'physicalSupport')
        bounds=prior.physicalSupport;j=find(bounds.index==i);
        if ~isempty(j)
            above=bounds.upper(j)-shapeMean(i);below=shapeMean(i)-bounds.lower(j);
            assert(min(above,below)>=-1e-12,'D条件均值越过物理边界。');
            if above>=shapeStep(i)
                % 保留前向差分；只能在合法物理域内求响应。
            elseif below>=shapeStep(i),shapeStep(i)=-shapeStep(i);
            elseif above>=below,shapeStep(i)=0.5*above;
            else,shapeStep(i)=-0.5*below;end
            assert(abs(shapeStep(i))>eps,'边界内无可用物理差分步。');
        end
    end
    z=shapeMean;z(i)=z(i)+shapeStep(i);
    schedules{end+1}=sht_f34_prior('applyShape',modelSet.schedules{1},prior,z); %#ok<AGROW>
    recoveries(end+1)=modelSet.recoveries; %#ok<AGROW>
end
value=local_evaluate_schedule_batch(context,schedules,recoveries);
meanValue=value(:,1);Jtheta=zeros(numel(meanValue),d);
for i=1:d,Jtheta(:,i)=(value(:,1+i)-meanValue)/thetaStep(i);end
Jshape=zeros(numel(meanValue),prior.shape.retainedRank);offset=1+d;
for i=1:prior.shape.retainedRank
    Jshape(:,i)=(value(:,offset+i)-meanValue)/shapeStep(i);
end
explicitCov=Jtheta*methodD.covariance*Jtheta.';
physicalCov=explicitCov+Jshape*shapeCov*Jshape.'+inputCov+modelCov;
observableCov=physicalCov+outputCov;
fixed=local_gaussian_layers(meanValue,explicitCov,physicalCov,observableCov);

if isfield(prior,'nodePrior')
    % Jtheta含本架次条件均值导数。跨架次独立变化必须使用固定干扰量
    % 的偏导，并保留显式节点与未覆盖节点过程变化的交叉协方差。
    directJ=Jtheta-Jshape*shapeSlope;
    nextQ=prior.nodePrior.jointNextFlightCovariance;
    response=[directJ,Jshape];
    nextExplicit=explicitCov+directJ*nextQ(1:d,1:d)*directJ.';
    nextPhysical=physicalCov+response*nextQ*response.';
else
    qSigma=local_flight_explicit_sigma(options);
    nextThetaCov=methodD.covariance+diag(qSigma.^2);
    nextShapeCov=shapeCov+local_flight_shape_q(prior,options);
    nextExplicit=Jtheta*nextThetaCov*Jtheta.';
    nextPhysical=nextExplicit+Jshape*nextShapeCov*Jshape.'+inputCov+modelCov;
end
nextObservable=nextPhysical+outputCov;
next=local_gaussian_layers(meanValue,nextExplicit,nextPhysical,nextObservable);
output=struct('fixed_transfer',fixed,'next_sortie',next, ...
    'meanSchedule',baseSchedule,'Jtheta',Jtheta,'Jshape',Jshape,'shapeSlope',shapeSlope, ...
    'shapeDifferenceStep',shapeStep, ...
    'approximation','local_delta_method','testDataUsedAfterPosteriorFreeze',true);
end

function output=local_method_c_prediction(context,prior,methodC,likelihood, ...
        inputCov,outputCov,modelCov,options)
n=min(options.predictionRepresentativeCount,methodC.particleCount);
stream=RandStream('mt19937ar','Seed',methodC.seed+9000);
poolCount=min(methodC.particleCount,max(n+16,ceil(4*n/3)));
fixedPool=local_fixed_prediction_pool(context,prior,methodC,likelihood, ...
    poolCount,stream);
if nnz(fixedPool.valid)<n && poolCount<methodC.particleCount
    poolCount=methodC.particleCount;
    stream=RandStream('mt19937ar','Seed',methodC.seed+9000);
    fixedPool=local_fixed_prediction_pool(context,prior,methodC,likelihood, ...
        poolCount,stream);
end
if nnz(fixedPool.valid)<n
    error('SHT:F34Prediction:FixedPhysicalSupport', ...
        '后验%d个代表候选中只有%d个能在独立任务上形成有效物理解，少于目标%d个。', ...
        poolCount,nnz(fixedPool.valid),n);
end
% 分层抽样池按累计权重排序，不能只取前n个，否则系统性偏向前部概率质量。
% 使用全部物理有效代表点，并明确报告失效点导致的条件化。
selected=find(fixedPool.valid);
index=fixedPool.index(selected);theta=fixedPool.theta(:,selected);
explicit=fixedPool.explicit(:,selected);physical=fixedPool.physical(:,selected);
weights=ones(numel(selected),1)/numel(selected);
fixed=local_mixture_layers(explicit,physical,weights,inputCov,modelCov,outputCov);

if isfield(prior,'nodePrior')
    nextPrior=prior;nextPrior.nodePosteriorForPrediction=methodC;
else
    nextPrior=sht_f34_prior('transition',prior,methodC,options);
end
nextPoolCount=max(n+16,ceil(4*n/3));
nextPool=local_next_prediction_pool(context,nextPrior,nextPoolCount, ...
    methodC.seed+9100,stream);
if nnz(nextPool.valid)<n
    nextPoolCount=4*n;
    stream=RandStream('mt19937ar','Seed',methodC.seed+9000);
    nextPool=local_next_prediction_pool(context,nextPrior,nextPoolCount, ...
        methodC.seed+9100,stream);
end
if nnz(nextPool.valid)<n
    error('SHT:F34Prediction:NextPhysicalSupport', ...
        '下一架次%d个传播候选中只有%d个能在独立任务上形成有效物理解，少于目标%d个。', ...
        nextPoolCount,nnz(nextPool.valid),n);
end
nextSelected=find(nextPool.valid);
nextTheta=nextPool.theta(:,nextSelected);
nextExplicit=nextPool.explicit(:,nextSelected);
nextPhysical=nextPool.physical(:,nextSelected);
nextWeights=ones(numel(nextSelected),1)/numel(nextSelected);
next=local_mixture_layers(nextExplicit,nextPhysical,nextWeights, ...
    inputCov,modelCov,outputCov);
output=struct('fixed_transfer',fixed,'next_sortie',next, ...
    'representativeIndex',index,'representativeCount',numel(selected), ...
    'nextRepresentativeCount',numel(nextSelected), ...
    'representativeTheta',theta,'nextSortieRepresentativeTheta',nextTheta, ...
    'physicalValidityAudit',struct( ...
        'conditioning','independent_task_physical_solvability', ...
        'fixedCandidateCount',poolCount, ...
        'fixedValidCount',nnz(fixedPool.valid), ...
        'fixedInvalidExplicitCount',nnz(~fixedPool.explicitValid), ...
        'fixedInvalidPhysicalCount',nnz(~fixedPool.physicalValid), ...
        'nextCandidateCount',nextPoolCount, ...
        'nextValidCount',nnz(nextPool.valid), ...
        'nextInvalidExplicitCount',nnz(~nextPool.explicitValid), ...
        'nextInvalidPhysicalCount',nnz(~nextPool.physicalValid)), ...
    'approximation',['weighted_stratified_exact_DLL_with_conditional_shape_' ...
    'and_analytic_measurement_covariance'], ...
    'testDataUsedAfterPosteriorFreeze',true);
% 内部审计保存所有候选及原因，不能只保留成功样本而丢掉失败证据。
output.candidateAudit=struct('fixed',fixedPool,'next',nextPool);
if any(~fixedPool.valid)||any(~nextPool.valid)
    warning('SHT:F34Prediction:IncompletePhysicalMass', ...
        '部分预测候选无效：固定%d/%d，下一架次%d/%d；区间仅代表有效子集，见candidateAudit。', ...
        nnz(fixedPool.valid),poolCount,nnz(nextPool.valid),nextPoolCount);
end
end

function pool=local_fixed_prediction_pool(context,prior,methodC,likelihood, ...
        poolCount,stream)
index=local_representative_index(methodC.weights,poolCount);
theta=methodC.samples(:,index);
meanZ=zeros(prior.shape.retainedRank,poolCount);physicalZ=meanZ;
for i=1:poolCount
    [meanZ(:,i),covZ,detail]=sht_f34_likelihood('conditionalPosterior', ...
        likelihood,prior,theta(:,i),methodC.physicalOutput(:,index(i)));
    if isfield(likelihood,'physicalSupport')
        box=sht_f34_bounded_condition('evaluate',detail.gaussianMean,detail.gaussianCovariance, ...
            likelihood.physicalSupport,likelihood.supportQuadratureCount,likelihood.supportQuadratureSeed,stream);
        physicalZ(:,i)=box.draw;
    else,physicalZ(:,i)=meanZ(:,i)+local_covariance_sample(covZ,stream);end
end
[explicit,explicitValid,explicitMessage]= ...
    local_exact_prediction(context,prior,theta,meanZ);
[physical,physicalValid,physicalMessage]= ...
    local_exact_prediction(context,prior,theta,physicalZ);
pool=struct('index',index,'theta',theta,'explicit',explicit, ...
    'conditionalMean',meanZ,'conditionalDraw',physicalZ, ...
    'physical',physical,'explicitValid',explicitValid, ...
    'physicalValid',physicalValid,'valid',explicitValid&physicalValid, ...
    'explicitMessage',explicitMessage,'physicalMessage',physicalMessage);
end

function pool=local_next_prediction_pool(context,nextPrior,poolCount,seed,stream)
if isfield(nextPrior,'nodePosteriorForPrediction')
    sample=sht_f34_node_c('propagate',nextPrior,nextPrior.nodePosteriorForPrediction,poolCount,seed,1);
    theta=sample.theta;meanZ=sample.conditionalMean;physicalZ=sample.z;
else
theta=sht_f34_prior('draw',nextPrior,poolCount,seed);
meanZ=zeros(nextPrior.shape.retainedRank,poolCount);physicalZ=meanZ;
for i=1:poolCount
    [meanZ(:,i),covZ]=sht_f34_prior('conditionalShape',nextPrior,theta(:,i));
    physicalZ(:,i)=meanZ(:,i)+local_covariance_sample(covZ,stream);
end
end
[explicit,explicitValid,explicitMessage]= ...
    local_exact_prediction(context,nextPrior,theta,meanZ);
% 节点路径的条件均值与样本已经由联合Q生成，不能再叠加一次Q。
[physical,physicalValid,physicalMessage]= ...
    local_exact_prediction(context,nextPrior,theta,physicalZ);
pool=struct('theta',theta,'explicit',explicit,'physical',physical, ...
    'conditionalMean',meanZ,'conditionalDraw',physicalZ, ...
    'explicitValid',explicitValid,'physicalValid',physicalValid, ...
    'valid',explicitValid&physicalValid, ...
    'explicitMessage',explicitMessage,'physicalMessage',physicalMessage);
end

function [value,valid,message]=local_exact_prediction(context,prior,theta,z)
try
    evaluation=sht_f34_likelihood('evaluatePhysicalShape',context,prior,theta,z);
    value=evaluation.output;
    valid=logical(evaluation.valid(:).');
    message=string(evaluation.message(:).');
catch exception
    % 条件高斯方向可能产生无效部件入口状态；不修改后验，不截断参数。
    % 只隔离这个已知物理状态异常，配置/接口等未知错误仍原样抛出。
    if ~strcmp(exception.identifier,'SHT:ReynoldsCorrection:EvaluationState')
        rethrow(exception);
    end
    count=size(theta,2);
    if count==1
        value=nan(4*height(context.steadyData),1);valid=false;
        message=string([exception.identifier,': ',exception.message]);
    else
        % 按二分批次定位失败样本，避免每个正常样本均重新冷加载DLL。
        middle=floor(count/2);
        [a,va,ma]=local_exact_prediction(context,prior,theta(:,1:middle),z(:,1:middle));
        [b,vb,mb]=local_exact_prediction(context,prior,theta(:,middle+1:end),z(:,middle+1:end));
        value=[a,b];valid=[va,vb];message=[ma,mb];
    end
end
end

function value=local_evaluate_schedule_batch(context,schedules,recoveries)
batch=sht_f33_thermal_equilibrium('batch',context.thermalSession,schedules,recoveries);
n=height(context.steadyData);value=nan(4*n,numel(schedules));
for i=1:numel(schedules)
    if ~batch.candidate(i).valid
        error('SHT:F34Prediction:Physical','独立预测候选%d物理解无效。',i);
    end
    q=batch.candidate(i).prediction;
    matrix=[q.Np,q.Ng,q.Pt3,q.Tt45];
    value(:,i)=matrix(:);
end
end

function layer=local_gaussian_layers(meanValue,explicitCov,physicalCov,observableCov)
layer=struct('explicit',local_normal_interval(meanValue,explicitCov), ...
    'physical',local_normal_interval(meanValue,physicalCov), ...
    'observable',local_normal_interval(meanValue,observableCov));
end

function layer=local_mixture_layers(explicitSample,physicalSample,weights, ...
        inputCov,modelCov,outputCov)
zero=zeros(size(inputCov));
layer=struct('explicit',local_mixture_interval(explicitSample,weights,zero), ...
    'physical',local_mixture_interval(physicalSample,weights,inputCov+modelCov), ...
    'observable',local_mixture_interval(physicalSample,weights, ...
    inputCov+modelCov+outputCov));
end

function value=local_normal_interval(meanValue,covariance)
sigma=sqrt(max(diag(covariance),0));
value=struct('mean',meanValue,'covariance',covariance, ...
    'lower95',meanValue-1.95996398454*sigma, ...
    'upper95',meanValue+1.95996398454*sigma);
end

function value=local_mixture_interval(sample,weights,addedCovariance)
weights=weights(:)/sum(weights);meanValue=sample*weights;
centered=sample-meanValue;covariance=(centered.*weights.')*centered.'+addedCovariance;
lower=zeros(size(meanValue));upper=lower;
variance=max(diag(addedCovariance),0);
for i=1:numel(meanValue)
    lower(i)=local_mixture_quantile(sample(i,:),weights,variance(i),0.025);
    upper(i)=local_mixture_quantile(sample(i,:),weights,variance(i),0.975);
end
value=struct('mean',meanValue,'covariance',covariance, ...
    'lower95',lower,'upper95',upper,'sample',sample,'sampleWeights',weights);
end

function q=local_mixture_quantile(center,weights,variance,probability)
sigma=sqrt(max(variance,0));
if sigma<=eps
    [center,order]=sort(center(:));cdf=cumsum(weights(order));
    q=center(find(cdf>=probability,1));return;
end
lower=min(center)-8*sigma;upper=max(center)+8*sigma;
for i=1:70
    middle=(lower+upper)/2;
    cdf=sum(weights(:).*local_normcdf((middle-center(:))/sigma));
    if cdf<probability,lower=middle;else,upper=middle;end
end
q=(lower+upper)/2;
end

function summary=local_prediction_summary(method,prediction,observation)
modes={'fixed_transfer','next_sortie'};layers={'explicit','physical','observable'};
channels={'Np','Ng','Pt3_eq','Tt45'};units={'rpm','rpm','Pa','K'};
n=numel(observation)/4;summary=table();
for a=1:numel(modes)
    for b=1:numel(layers)
        q=prediction.(modes{a}).(layers{b});
        for c=1:4
            index=(c-1)*n+(1:n);residual=q.mean(index)-observation(index);
            row=table(string(method),string(modes{a}),string(layers{b}), ...
                string(channels{c}),string(units{c}),sqrt(mean(residual.^2)), ...
                mean(residual),mean(q.upper95(index)-q.lower95(index)), ...
                mean(observation(index)>=q.lower95(index)&observation(index)<=q.upper95(index)), ...
                'VariableNames',{'method','prediction_mode','interval_layer', ...
                'channel','unit','rmse','mean_error','mean_interval_width','coverage95'});
            summary=[summary;row]; %#ok<AGROW>
        end
    end
end
end

function detail=local_prediction_detail(method,prediction,data)
modes={'fixed_transfer','next_sortie'};layers={'explicit','physical','observable'};
channels={'Np','Ng','Pt3_eq','Tt45'};n=height(data);detail=table();
for a=1:numel(modes)
    for b=1:numel(layers)
        q=prediction.(modes{a}).(layers{b});
        for c=1:4
            index=(c-1)*n+(1:n);
            row=table(repmat(string(method),n,1),repmat(string(modes{a}),n,1), ...
                repmat(string(layers{b}),n,1),data.point_id, ...
                repmat(string(channels{c}),n,1),q.mean(index),q.lower95(index), ...
                q.upper95(index),'VariableNames',{'method','prediction_mode', ...
                'interval_layer','point_id','channel','mean','lower95','upper95'});
            detail=[detail;row]; %#ok<AGROW>
        end
    end
end
end

function index=local_representative_index(weight,n)
cdf=cumsum(weight(:)/sum(weight));target=((1:n)'-0.5)/n;index=zeros(n,1);
for i=1:n,index(i)=find(cdf>=target(i),1);end
end

function sample=local_covariance_sample(covariance,stream)
[vector,value]=eig((covariance+covariance.')/2,'vector');
value=max(real(value),0);
sample=real(vector)*(sqrt(value).*randn(stream,numel(value),1));
end

function sigma=local_flight_explicit_sigma(options)
sigma=[options.flightToFlightHealthSigma(:);options.flightToFlightKdistSigma; ...
    options.flightToFlightFuelSigma_kgps];
end

function covariance=local_flight_shape_q(prior,options)
full=prior.shape.fullProcessCovariance;n=prior.shape.healthNodeCount;
healthRatio=median(options.flightToFlightShapeSigma(:))/ ...
    median(options.benchToFlightShapeSigma(:));
fuelRatio=options.flightToFlightFuelShapeSigma_kgps/ ...
    options.firstFlightFuelShapeSigma_kgps;
full(1:n,1:n)=healthRatio^2*full(1:n,1:n);
full(n+1:end,n+1:end)=fuelRatio^2*full(n+1:end,n+1:end);
full(1:n,n+1:end)=0;full(n+1:end,1:n)=0;
covariance=prior.shape.basis.'*full*prior.shape.basis;
end

function row=local_sensor_row(sensor,name)
row=find(strcmp(cellstr(string(sensor.name)),name),1);
if isempty(row),error('SHT:F34Prediction:Sensor','缺少%s测量误差先验。',name);end
end

function value=local_normcdf(x)
value=0.5*erfc(-x/sqrt(2));
end
