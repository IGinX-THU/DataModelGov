function result = sht_f32_preprocess_and_replay(userOptions,varargin)
%SHT_F32_PREPROCESS_AND_REPLAY 第3.2阶段第二轮主实现。
%
% 本程序从两个独立Excel读取3.1飞参，完成数据合同检查、无标签自动分段、
% 当前三部件Visser16（六部件显式可选）连续回放、正向传感器动态和独立验证。
% 训练与验证使用完全相同且事先冻结的处理规则，验证数据不参与门限调节。
%
% 正式原则：
%   1) 不读取3.1隐藏真值；
%   2) 不做传感器逆动态补偿；
%   3) 三部件读取编号、时间及11个物理测量量；六部件另有Mkg；
%   4) 实测Wf/Mkp/Mkg/环境量作为开环边界，Mkp/Mkg不是模型输出；
%   5) Pt3_eq只作为输出观测；Ps0/Mach/Tt1/Ts_amb经模式5送入C端，
%      由C统一重构Pt0/Pt1，MATLAB不读取或复制不可测Pt1真值；
%   6) 默认基线继承2.4瞬态时刻路径调度，不继承旧试车的
%      瞬态个体修正；2.7基线仅在用户显式选择时使用；
%   7) 零修正六部件模型只作对照，不替代正式个性化基线。

% 人工确认沿用同一Excel写出，不重复自动分段或打开DLL。
if nargin>0 && (ischar(userOptions)||isstring(userOptions))
    assert(strcmpi(char(userOptions),'exportConfirmed')&&numel(varargin)==1, ...
        'SHT:F32:Action','仅支持exportConfirmed及一个已确认对象。');
    result=local_export_confirmed(varargin{1});
    return;
end
if nargin<1 || isempty(userOptions), userOptions=struct(); end
options=local_options(userOptions);
thisDir=fileparts(mfilename('fullpath'));
addpath(thisDir);
paths=local_paths(thisDir,options);
% 固定批次可能已被辨识/UQ引用，禁止重复运行静默重写其Excel或latest MAT。
% 只读分析可设saveEnabled=false；需要重新交付时须指定新的runTag。
if options.saveEnabled
    existingOutput=local_output_paths(paths);
    assert(~isfile(existingOutput.latestMatFile)&& ...
        ~isfile(existingOutput.identificationExcel)&&~isfile(existingOutput.validationExcel), ...
        'SHT:F32:ExistingBatch','该预处理批次已有结果，请指定新的runTag：%s', ...
        existingOutput.latestMatFile);
end

fprintf('\n=== 第3.2阶段第二轮：飞参预处理与个性化模型等效回放 ===\n');
fprintf('  训练Excel：%s\n',paths.identificationFile);
fprintf('  验证Excel：%s\n',paths.validationFile);
fprintf('  传感器逆补偿：关闭；模型输出正向FOH动态：%d\n', ...
    options.sensorDynamicsEnabled);
    fprintf(['  稀疏飞参合同：F31_FLIGHT_EXCEL_V3；入口模式：5' ...
        '（C端由可测Ps0/Mach/Tt1重构入口边界）。\n']);

measurementModel=sht_f31_flight_measurement( ...
    'model',3201001,'F32-MEASUREMENT-PRIOR',false);
measurementAssumptions=sht_f31_flight_measurement( ...
    'publicAssumptions',measurementModel);
measurementObject=local_measurement_contract(measurementAssumptions);

if options.replayEnabled
    assetOptions=struct('priorSource',options.priorSource, ...
        'priorRoute',options.priorRoute, ...
        'priorWorkbook',options.priorWorkbook,'modelMode',options.modelMode);
    assets=sht_f32_replay_history('loadAssets',thisDir,assetOptions);
else
    assets=struct('contract',struct('truthDataAccessed',false));
end

definitions=struct( ...
    'role',{'identification','independent_validation'}, ...
    'file',{paths.identificationFile,paths.validationFile});
if ~options.validationEnabled,definitions=definitions(1);end
datasets=repmat(local_empty_dataset(),numel(definitions),1);
for i=1:numel(definitions)
    datasets(i)=local_process_dataset(definitions(i),assets, ...
        measurementAssumptions,paths,options);
end

summary=local_summary_tables(datasets,options);
summary=local_preview_status(summary,options);
validation=local_validation(datasets,assets,options);
output=local_output_paths(paths);
result=struct();
result.schemaVersion='SHT_FLIGHT_MODEL_ADAPT_3P2_MODEL_ISOLATED_V5';
result.modelMode=options.modelMode;
result.program=mfilename;
result.createdAt=datestr(now,31);
result.description=[ ...
    'F31_FLIGHT_EXCEL_V3稀疏飞参质量检查、自动分段、装机边界重构、' ...
    sprintf('%s/%s先验调度下的Visser连续等效回放及独立验证', ...
    options.priorSource,options.priorRoute)];
if ~options.replayEnabled
    result.description='测量合同检查与窗口提取；尚未执行物理回放、传感器动态或参数辨识';
end
result.shaftLoadInterfaceVersion='Mkp_Mkg_external_torque_inputs_v2';
result.formalInputContract='F31_FLIGHT_EXCEL_V3';
if options.modelMode==0,result.formalInputContract='F31_THREE_COMPONENT_R011';end
result.inletBoundaryMode=5;
result.options=options;
result.options.inputData=struct(); % 大测量表仅保留在datasets中。
result.measurementObjectParameters=measurementObject;
result.modelAssetContract=assets.contract;
result.datasets=datasets;
result.qualitySummary=summary.quality;
result.metricSummary=summary.metrics;
result.segmentMetricSummary=summary.segmentMetrics;
result.baselineComparison=summary.comparison;
result.validation=validation;
result.output=output;

result=local_publish(result,options);
if options.plotEnabled
    result.output.figureFiles=local_plot_results(result,paths,options);
    if options.saveEnabled
        flightModelAdaptData=result;
        save(result.output.stampedMatFile,'flightModelAdaptData','-v7.3');
        save(result.output.latestMatFile,'flightModelAdaptData','-v7.3');
    end
end
if options.saveEnabled
    local_write_summary(result,result.output.summaryMarkdown);
end
local_print_summary(result);
if ~result.validation.passed
    error('SHT:F32:ValidationFailed', ...
        '3.2第二轮没有通过计算完整性验收，详见result.validation。');
end
end

function result=local_publish(result,options)
if ~options.saveEnabled,return;end
local_write_delivery(result,options);
flightModelAdaptData=result;
save(result.output.stampedMatFile,'flightModelAdaptData','-v7.3');
save(result.output.latestMatFile,'flightModelAdaptData','-v7.3');
writetable(result.qualitySummary,result.output.qualityCsv);
writetable(result.metricSummary,result.output.metricCsv);
writetable(result.segmentMetricSummary,result.output.segmentMetricCsv);
writetable(result.baselineComparison,result.output.comparisonCsv);
end

function summary=local_preview_status(summary,options)
if ~strcmp(options.validationPolicy,'steady_task_preview'),return;end
for name={'personalized_computationally_accepted','zero_computationally_accepted'}
    if ismember(name{1},summary.quality.Properties.VariableNames)
        summary.quality.(name{1})(:)=false;
    end
end
summary.quality.replay_evaluated=false(height(summary.quality),1);
end

function result=local_export_confirmed(result)
assert(isstruct(result)&&isfield(result,'taskContract')&& ...
    isfield(result.taskContract,'selectionIdentity'), ...
    'SHT:F32:Confirmation','缺少已确认的任务身份。');
options=local_options(result.options);
assert(~options.replayEnabled&&strcmp(options.validationPolicy,'steady_task_preview'), ...
    'SHT:F32:Confirmation','确认写出限于无DLL预览。');
paths=local_paths(fileparts(mfilename('fullpath')),options);
result.output=local_output_paths(paths);
assert(~isfile(result.output.latestMatFile)&&~isfile(result.output.identificationExcel)&& ...
    ~isfile(result.output.validationExcel),'SHT:F32:ExistingBatch','确认批次已存在。');
summary=local_summary_tables(result.datasets,options);
summary=local_preview_status(summary,options);
result.qualitySummary=summary.quality;result.metricSummary=summary.metrics;
result.segmentMetricSummary=summary.segmentMetrics;result.baselineComparison=summary.comparison;
result.validation=local_validation(result.datasets, ...
    struct('contract',result.modelAssetContract),options);
assert(result.validation.passed,'SHT:F32:Confirmation','确认数据合同未通过。');
if ~options.validationEnabled,result.output.validationExcel='';end
result=local_publish(result,options);
local_write_summary(result,result.output.summaryMarkdown);
end

function options=local_options(user)
options=struct();
options.modelMode=0;
options.runTag='R020';
options.identificationFile='';
options.validationFile='';
options.validationEnabled=true; % 单架次没有独立测试集时显式关闭，不复制训练数据。
options.outputRoot='';options.reportRoot='';
options.inputData=struct(); % 按数据角色提供映射后的表，原Excel仍绑定SHA。
options.validationPolicy='historical_full';
options.replayEnabled=true;
options.baselineVariants={'personalized','zero'};
options.priorSource='2p4';
options.priorRoute='transient_instant';
options.priorWorkbook='';
options.integrationMethod='euler2';
options.integrationStep_s=0.1; % 回放积分；不改变造数步长与Excel记录。
options.localThermalWarmup_s=60; % 前史计划，不作为热初始化精度已验证的结论。
options.sensorDynamicsEnabled=true;
options.forceRecompute=false;
options.maximumSamples=Inf;
options.maximumCommonWorkResidual=1e-5;
options.progressIntervalSamples=2000;
options.inletMeanRecovery=0.995;
options.exhaustBackPressureDesignRise_Pa=1500;
options.reynoldsEffectScale=1;
options.segmentation=struct();
options.transientEpisodes=struct('identification',struct(), ...
    'independent_validation',struct());
options.plotEnabled=true;
options.saveEnabled=true;
options.figureVisible='off';
options.maximumPlotSamples=5000;
names=fieldnames(user);
for i=1:numel(names)
    if ~isfield(options,names{i})
        error('SHT:F32:UnknownOption','未知3.2选项：%s。',names{i});
    end
    if isstruct(options.(names{i})) && isstruct(user.(names{i}))
        options.(names{i})=local_merge_struct(options.(names{i}),user.(names{i}));
    else
        options.(names{i})=user.(names{i});
    end
end
assert(isstruct(options.inputData)&&isscalar(options.inputData), ...
    'SHT:F32:InputData','inputData必须为按数据角色配置的结构体。');
assert(ismember(options.validationPolicy,{'historical_full','steady_task_preview'}), ...
    'SHT:F32:Policy','未知预处理验收策略。');
assert(~strcmp(options.validationPolicy,'steady_task_preview')||~options.replayEnabled, ...
    'SHT:F32:Policy','只读预览策略不得打开DLL回放。');
options.baselineVariants=cellstr(string(options.baselineVariants));
if options.modelMode~=0 && ~isfield(user,'integrationStep_s')
    options.integrationStep_s=0.025; % 六部件历史默认保持。
end
validateattributes(options.integrationStep_s,{'numeric'},{'scalar','real','finite','positive'});
assert(ismember(options.integrationStep_s,[0.025,0.1]), ...
    'SHT:F32:IntegrationStep','积分步长只允许0.025或0.1秒。');
options.priorSource=char(lower(string(options.priorSource)));
options.priorRoute=char(lower(string(options.priorRoute)));
options.priorWorkbook=char(string(options.priorWorkbook));
dataOnly=~options.replayEnabled&&strcmp(options.validationPolicy,'steady_task_preview')&&options.modelMode==0;
supported={'2p4','2p7'};
if dataOnly,supported=[supported,{'unbound','flight','combined'}];end
if ~ismember(options.priorSource,supported) || ...
        ~ismember(options.priorRoute,{'steady','transient_instant'})
    error('SHT:F32:PriorSelection', ...
        '先验来源不支持；unbound/flight/combined仅允许三部件无回放数据预览，不放开旧物理回放。');
end
if strcmp(options.priorSource,'2p7') && ...
        ~strcmp(options.priorRoute,'transient_instant')
    error('SHT:F32:PriorSelection', ...
        '当前2.7冻结交付只支持transient_instant路径。');
end
if options.replayEnabled && ~any(strcmp(options.baselineVariants,'personalized'))
    error('SHT:F32:MissingPrimaryBaseline', ...
        '正式回放必须包含personalized基线。');
end
if ~isscalar(options.maximumSamples) || ...
        ~(isinf(options.maximumSamples) || ...
        (isfinite(options.maximumSamples) && options.maximumSamples>=3 && ...
        options.maximumSamples==round(options.maximumSamples)))
    error('SHT:F32:MaximumSamples','maximumSamples必须为Inf或不小于3的整数。');
end
if ~isscalar(options.inletMeanRecovery) || ...
        ~isfinite(options.inletMeanRecovery) || ...
        options.inletMeanRecovery<=0 || options.inletMeanRecovery>1
    error('SHT:F32:InletRecovery','inletMeanRecovery必须为(0,1]内有限标量。');
end
if ~isscalar(options.exhaustBackPressureDesignRise_Pa) || ...
        ~isfinite(options.exhaustBackPressureDesignRise_Pa) || ...
        options.exhaustBackPressureDesignRise_Pa<0
    error('SHT:F32:BackPressure','排气设计背压升高量必须为有限非负标量。');
end
if ~isscalar(options.reynoldsEffectScale) || ...
        ~isfinite(options.reynoldsEffectScale) || ...
        options.reynoldsEffectScale<0 || options.reynoldsEffectScale>2
    error('SHT:F32:ReynoldsScale','reynoldsEffectScale必须为[0,2]内有限标量。');
end
end

function paths=local_paths(thisDir,options)
programRoot=fileparts(thisDir);
paths=struct();
if options.modelMode==0
    current=sht_f3_current_contract('paths');
    paths.identificationFile=options.identificationFile;
    if isempty(paths.identificationFile),paths.identificationFile=current.training;end
    paths.validationFile=options.validationFile;
    if isempty(paths.validationFile),paths.validationFile=current.test;end
    if ~options.validationEnabled,paths.validationFile='';end
    paths.middleDir=fullfile(current.middle,'preprocess',options.runTag);
    if ~isempty(options.outputRoot),paths.middleDir=options.outputRoot;end
    paths.deliveryDir=fullfile(paths.middleDir,'delivery');
    paths.cacheDir=fullfile(paths.middleDir,'replay_cache');
    paths.reportDir=fullfile(current.report,'F3_3',options.runTag);
    if ~isempty(options.reportRoot),paths.reportDir=options.reportRoot;end
    for f={paths.middleDir,paths.deliveryDir,paths.cacheDir,paths.reportDir}
        if ~isfolder(f{1}),mkdir(f{1});end
    end
    assert(isfile(paths.identificationFile)&&(~options.validationEnabled||isfile(paths.validationFile)), ...
        '缺少本轮三部件测量Excel。');
    return;
end
paths.identificationFile=options.identificationFile;
if isempty(paths.identificationFile)
    paths.identificationFile=fullfile(thisDir,'TestData', ...
        'flight_data_3p1_identification_history.xlsx');
end
paths.validationFile=options.validationFile;
if isempty(paths.validationFile)
    paths.validationFile=fullfile(thisDir,'TestData', ...
        'flight_data_3p1_independent_validation_history.xlsx');
end
if ~isfile(paths.identificationFile) || ~isfile(paths.validationFile)
    error('SHT:F32:MissingExcel','3.1训练或独立验证Excel不存在。');
end
paths.middleDir=fullfile(thisDir,'MiddleData','flight_model_adapt_3p2');
paths.deliveryDir=fullfile(paths.middleDir,'delivery');
paths.cacheDir=fullfile(paths.middleDir,'replay_cache');
paths.reportDir=fullfile(programRoot,'report_outputs','flight_model_adapt_3p2');
for directory={paths.middleDir,paths.deliveryDir,paths.cacheDir,paths.reportDir}
    if ~isfolder(directory{1}),mkdir(directory{1});end
end
end

function object=local_measurement_contract(assumptions)
object=struct();
object.schemaVersion='SHT_F32_MEASUREMENT_OBJECT_PRIOR_V2';
object.configurationSource='3.2 independent engineering prior from 3.1/2.6 sensor dictionary';
object.sensorSequence='model truth -> exact FOH first-order dynamics';
object.inverseDynamicsApplied=false;
object.actualBiasRealizationKnown=false;
object.actualNoiseRealizationKnown=false;
object.delay_s=0;
object.biasDistribution='uniform_symmetric_prior';
object.noiseDistribution='zero_mean_gaussian_prior';
object.channelTable=assumptions;
object.formalChannelNames=cellstr(string(assumptions.name));
end

function dataset=local_process_dataset(definition,assets,assumptions,paths,options)
fprintf('\n  读取%s数据 ...\n',definition.role);
sourceHash=local_file_hash(definition.file);
if isfield(options.inputData,definition.role)
    data=options.inputData.(definition.role);
else
    data=readtable(definition.file,'Sheet','Data');
end
if isfinite(options.maximumSamples) && height(data)>options.maximumSamples
    data=data(1:options.maximumSamples,:);
end
local_validate_input_table(data,definition.role,options.modelMode);
segmentation=sht_f32_segment_history(data,options.segmentation);
fprintf('    样本数：全部=%d，稳态=%d，小幅变化=%d，大幅过渡=%d，热恢复=%d\n', ...
    height(data),nnz(segmentation.labels.is_steady), ...
    nnz(segmentation.labels.is_small_change), ...
    nnz(segmentation.labels.is_large_transition), ...
    nnz(segmentation.labels.is_thermal_recovery));
fprintf('    有效片段：稳态=%d段，小幅变化=%d段。\n', ...
    nnz(segmentation.segments.segment_class=="steady_window"), ...
    nnz(segmentation.segments.segment_class=="small_change"));

replays=struct();
if options.replayEnabled
    for i=1:numel(options.baselineVariants)
        variant=options.baselineVariants{i};
        runOptions=struct('cacheDirectory',paths.cacheDir, ...
            'sourceSha256',sourceHash,'integrationMethod',options.integrationMethod, ...
            'integrationStep_s',options.integrationStep_s, ...
            'sensorDynamicsEnabled',options.sensorDynamicsEnabled, ...
            'forceRecompute',options.forceRecompute, ...
            'maximumCommonWorkResidual',options.maximumCommonWorkResidual, ...
            'progressIntervalSamples',options.progressIntervalSamples, ...
            'inletMeanRecovery',options.inletMeanRecovery, ...
            'exhaustBackPressureDesignRise_Pa', ...
            options.exhaustBackPressureDesignRise_Pa, ...
            'reynoldsEffectScale',options.reynoldsEffectScale);
        replays.(variant)=sht_f32_replay_history( ...
            'run',data,assets,variant,assumptions,runOptions);
    end
end

dataset=local_empty_dataset();
dataset.role=definition.role;
dataset.sourceFile=char(java.io.File(definition.file).getCanonicalPath());
dataset.sourceSha256=sourceHash;
dataset.sampleCount=height(data);
dataset.sampleTime_s=segmentation.sampleTime_s;
dataset.measurement=data;
dataset.segmentation=segmentation;
if options.modelMode==0
    % 瞬态辨识数据准备独立于原稳态/小幅标签，不读取金属温度真值。
    episodeIdentity=struct('sourceSha256',sourceHash, ...
        'role',definition.role,'modelMode',options.modelMode);
    episodeOptions=options.transientEpisodes.(definition.role);
    % 计划中的积分步长必须与本次实际回放相同，不再写死0.025秒。
    episodeOptions.integrationStep_s=options.integrationStep_s;
    dataset.transientEpisodes=sht_f32_transient_episodes(data,segmentation, ...
        episodeIdentity,episodeOptions);
    selected=segmentation.segments.segment_class=="small_change";
    dataset.localSmallThermalPlan=sht_f33_local_thermal_plan(data.time_s, ...
        segmentation.segments(selected,:),options.localThermalWarmup_s);
    dataset.localTransientThermalPlan=sht_f33_local_thermal_plan(data.time_s, ...
        dataset.transientEpisodes.windows,options.localThermalWarmup_s);
    q=dataset.transientEpisodes.summary;
    fprintf(['    瞬态事件：候选%d/选定%d，拟合窗口%.1f秒，' ...
        '保留热历史后需积分%.1f秒（完整%.1f秒）。\n'], ...
        q.candidateCount,q.selectedCount,q.fitDuration_s, ...
        q.simulationDuration_s,q.fullDuration_s);
end
dataset.replays=replays;
if isfield(replays,'personalized')
    dataset.boundaryReconstruction=replays.personalized.boundaryReconstruction;
elseif isfield(replays,'zero')
    dataset.boundaryReconstruction=replays.zero.boundaryReconstruction;
else
    dataset.boundaryReconstruction=sht_f32_replay_history( ...
        'reconstructBoundary',data,struct( ...
        'inletMeanRecovery',options.inletMeanRecovery, ...
        'exhaustBackPressureDesignRise_Pa', ...
        options.exhaustBackPressureDesignRise_Pa, ...
        'reynoldsEffectScale',options.reynoldsEffectScale));
end
dataset.truthDataAccessed=false;
end

function local_validate_input_table(data,role,modelMode)
required={'sample_id','time_s','Ps0','Tt1','Pt3_eq','Ng','Np', ...
    'Mkp','Mkg','Wf','Tt45','Altitude','Mach','Ts_amb'};
if modelMode==0,required(strcmp(required,'Mkg'))=[];end
missing=required(~ismember(required,data.Properties.VariableNames));
if ~isempty(missing)
    error('SHT:F32:InputSchema','%s缺少字段：%s。',role,strjoin(missing,', '));
end
if ~isequal(data.Properties.VariableNames,required)
    error('SHT:F32:InputSchemaOrder', ...
        '%s字段必须严格符合F31_FLIGHT_EXCEL_V3且不得夹带隐藏量。',role);
end
if height(data)<3 || numel(unique(data.sample_id))~=height(data) || ...
        any(data.sample_id(:)~=(1:height(data))')
    error('SHT:F32:SampleId','%s的sample_id必须从1连续递增。',role);
end
numeric=data{:,required(2:end)};
if any(~isfinite(numeric(:))) || any(diff(data.time_s)<=0)
    error('SHT:F32:InputValue','%s含非有限值或非递增时间。',role);
end
end

function summary=local_summary_tables(datasets,options)
qualityRows=cell(numel(datasets),1);
metricRows={}; segmentRows={}; comparisonRows={};
for i=1:numel(datasets)
    d=datasets(i);
    labels=d.segmentation.labels;
    variants=fieldnames(d.replays);
    primaryAccepted=~options.replayEnabled;
    maxResidual=NaN; nonzeroTag=NaN; maxEnergyResidual=NaN;
    evaluationCount=NaN; runtime_s=0;
    if isfield(d.replays,'personalized')
        p=d.replays.personalized;
        primaryAccepted=p.computationallyAccepted;
        maxResidual=p.maximumCommonWorkResidual;
        nonzeroTag=p.nonzeroConvergeTagCount;
        maxEnergyResidual=p.maximumNormalizedEnergyResidual;
        evaluationCount=p.evaluationCount;
        runtime_s=p.runtime_s;
    end
    zeroMaxResidual=NaN; zeroNonzeroTag=NaN; zeroMaxEnergyResidual=NaN;
    zeroEvaluationCount=NaN; zeroRuntime_s=0; zeroAccepted=true;
    if isfield(d.replays,'zero')
        z=d.replays.zero;
        zeroMaxResidual=z.maximumCommonWorkResidual;
        zeroNonzeroTag=z.nonzeroConvergeTagCount;
        zeroMaxEnergyResidual=z.maximumNormalizedEnergyResidual;
        zeroEvaluationCount=z.evaluationCount;
        zeroRuntime_s=z.runtime_s;
        zeroAccepted=z.computationallyAccepted;
    end
    qualityRows{i}=table(string(d.role),d.sampleCount,d.sampleTime_s, ...
        nnz(labels.usable),nnz(labels.is_steady),nnz(labels.is_small_change), ...
        nnz(labels.is_large_transition),nnz(labels.is_thermal_recovery), ...
        maxResidual,nonzeroTag,maxEnergyResidual,evaluationCount,runtime_s, ...
        primaryAccepted,zeroMaxResidual,zeroNonzeroTag,zeroMaxEnergyResidual, ...
        zeroEvaluationCount,zeroRuntime_s,zeroAccepted, ...
        'VariableNames',{'dataset','sample_count','sample_time_s', ...
        'usable_count','steady_count','small_change_count', ...
        'large_transition_count','thermal_recovery_count', ...
        'personalized_maximum_residual','personalized_nonzero_tag_count', ...
        'personalized_maximum_energy_residual','personalized_evaluation_count', ...
        'personalized_runtime_s','personalized_computationally_accepted', ...
        'zero_maximum_residual','zero_nonzero_tag_count', ...
        'zero_maximum_energy_residual','zero_evaluation_count', ...
        'zero_runtime_s','zero_computationally_accepted'});
    for j=1:numel(variants)
        variant=variants{j}; replay=d.replays.(variant);
        tbl=replay.metrics;
        tbl.dataset=repmat(string(d.role),height(tbl),1);
        tbl.variant=repmat(string(variant),height(tbl),1);
        tbl=movevars(tbl,{'dataset','variant'},'Before',1);
        metricRows{end+1,1}=tbl; %#ok<AGROW>
        segmentRows{end+1,1}=local_segment_metrics(d,variant); %#ok<AGROW>
    end
    if isfield(d.replays,'personalized') && isfield(d.replays,'zero')
        p=d.replays.personalized.metrics;
        z=d.replays.zero.metrics;
        improvement=100*(z.rmse-p.rmse)./max(z.rmse,eps);
        comparisonRows{end+1,1}=table(repmat(string(d.role),height(p),1), ...
            p.channel,p.unit,z.rmse,p.rmse,improvement, ...
            'VariableNames',{'dataset','channel','unit','zero_rmse', ...
            'personalized_rmse','personalized_improvement_pct'}); %#ok<AGROW>
    end
end
summary=struct();
summary.quality=vertcat(qualityRows{:});
summary.metrics=local_vertcat_or_empty(metricRows);
summary.segmentMetrics=local_vertcat_or_empty(segmentRows);
summary.comparison=local_vertcat_or_empty(comparisonRows);
end

function tbl=local_segment_metrics(dataset,variant)
replay=dataset.replays.(variant);
classes=unique(dataset.segmentation.labels.segment_class,'stable');
rows={};
for i=1:numel(classes)
    mask=dataset.segmentation.labels.segment_class==classes(i) & ...
        dataset.segmentation.labels.usable;
    if ~any(mask),continue;end
    for j=1:numel(replay.outputNames)
        e=replay.residual(mask,j);
        rows{end+1,1}=table(string(dataset.role),string(variant),classes(i), ...
            string(replay.outputNames{j}),string(replay.outputUnits{j}), ...
            nnz(mask),sqrt(mean(e.^2)),mean(e),max(abs(e)), ...
            'VariableNames',{'dataset','variant','segment_class','channel', ...
            'unit','sample_count','rmse','mean_error', ...
            'maximum_absolute_error'}); %#ok<AGROW>
    end
end
tbl=local_vertcat_or_empty(rows);
end

function validation=local_validation(datasets,assets,options)
inputPassed=all(arrayfun(@(d)d.sampleCount>=3 && ...
    all(d.segmentation.labels.usable),datasets));
segmentationPassed=all(arrayfun(@(d) ...
    any(d.segmentation.labels.is_steady) && ...
    any(d.segmentation.labels.is_large_transition | ...
        d.segmentation.labels.is_small_change),datasets));
coverageObserved=segmentationPassed;
if strcmp(options.validationPolicy,'steady_task_preview')
    % 真实任务可以没有某类片段；预览只报告覆盖，确认另核所选证据。
    segmentationPassed=true;
end
primaryReplayPassed=true;
if options.replayEnabled
    primaryReplayPassed=all(arrayfun(@(d) ...
        isfield(d.replays,'personalized') && ...
        d.replays.personalized.computationallyAccepted,datasets));
end
validation=struct();
validation.truthIsolationPassed=all(arrayfun(@(d)~d.truthDataAccessed,datasets)) && ...
    (~isfield(assets,'contract') || ~assets.contract.truthDataAccessed);
validation.independentValidationAvailable=numel(datasets)>1;
validation.trainingValidationSeparated=~validation.independentValidationAvailable || ...
    ~strcmp(datasets(1).sourceSha256,datasets(2).sourceSha256);
validation.inputDataPassed=inputPassed;
validation.segmentationCoveragePassed=segmentationPassed;
validation.segmentationCoverageObserved=coverageObserved;
validation.validationPolicy=options.validationPolicy;
validation.inverseSensorCompensationDisabled=true;
validation.forwardSensorDynamicsApplied=options.replayEnabled&&options.sensorDynamicsEnabled;
required={'sample_id','time_s','Ps0','Tt1','Pt3_eq','Ng','Np', ...
    'Mkp','Mkg','Wf','Tt45','Altitude','Mach','Ts_amb'};
if options.modelMode==0,required(strcmp(required,'Mkg'))=[];end
validation.sparseMeasurementContractPassed=all(arrayfun(@(d) ...
    isequal(d.measurement.Properties.VariableNames, ...
    required),datasets));
validation.inletBoundaryMode5=all(arrayfun(@(d) ...
    d.boundaryReconstruction.contract.inletBoundaryMode==5,datasets));
validation.pt3EqOutputOnlyPassed=all(arrayfun(@(d) ...
    strcmp(d.boundaryReconstruction.contract.pt3EqRole, ...
    'output_observation_only'),datasets));
validation.exhaustBackPressureReconstructed=all(arrayfun(@(d) ...
    isfield(d.boundaryReconstruction,'exhaustBackPressureModel'),datasets));
if options.replayEnabled
    validation.exhaustBackPressureReconstructed= ...
        validation.exhaustBackPressureReconstructed && all(arrayfun(@(d) ...
        all(d.replays.personalized.boundaryReconstruction.Pback_Pa>= ...
        d.measurement.Ps0),datasets));
end
validation.reynoldsCorrectionApplied=options.replayEnabled && ...
    all(arrayfun(@(d)isfield(d.replays,'personalized') && ...
    all(isfinite(d.replays.personalized.reynoldsIndex(:))),datasets));
validation.primaryReplayPassed=options.replayEnabled&&primaryReplayPassed;
validation.primaryReplayEvaluated=options.replayEnabled;
validation.zeroBaselineIsComparisonOnly=true;
validation.passed=validation.truthIsolationPassed && ...
    validation.trainingValidationSeparated && inputPassed && ...
    segmentationPassed && validation.sparseMeasurementContractPassed && ...
    validation.inletBoundaryMode5 && validation.pt3EqOutputOnlyPassed && ...
    validation.exhaustBackPressureReconstructed && ...
    (~options.replayEnabled||validation.reynoldsCorrectionApplied) && primaryReplayPassed;
end

function output=local_output_paths(paths)
stamp=datestr(now,'yyyymmdd_HHMMSS');
output=struct();
output.stampedMatFile=fullfile(paths.middleDir, ...
    ['flight_model_adapt_3p2_second_round_' stamp '.mat']);
output.latestMatFile=fullfile(paths.middleDir, ...
    'flight_model_adapt_3p2_second_round_latest.mat');
output.identificationExcel=fullfile(paths.deliveryDir, ...
    'flight_model_adapt_3p2_identification.xlsx');
output.validationExcel=fullfile(paths.deliveryDir, ...
    'flight_model_adapt_3p2_independent_validation.xlsx');
output.qualityCsv=fullfile(paths.reportDir, ...
    ['F32_quality_' stamp '.csv']);
output.metricCsv=fullfile(paths.reportDir, ...
    ['F32_metrics_' stamp '.csv']);
output.segmentMetricCsv=fullfile(paths.reportDir, ...
    ['F32_segment_metrics_' stamp '.csv']);
output.comparisonCsv=fullfile(paths.reportDir, ...
    ['F32_baseline_comparison_' stamp '.csv']);
output.summaryMarkdown=fullfile(paths.reportDir, ...
    ['F32_execution_summary_' stamp '.md']);
output.figureFiles={};
end

function local_write_delivery(result,options)
for i=1:numel(result.datasets)
    d=result.datasets(i);
    if strcmp(d.role,'identification')
        filePath=result.output.identificationExcel;
    else
        filePath=result.output.validationExcel;
    end
    if isfile(filePath),delete(filePath);end
    history=d.measurement;
    labels=d.segmentation.labels(:,{'segment_id','segment_class','usable', ...
        'is_steady','is_small_change','is_large_transition', ...
        'is_thermal_recovery','selection_reason','possible_thermal_recovery'});
    history=[history,labels]; %#ok<AGROW>
    if ismember('fit_selected',d.segmentation.labels.Properties.VariableNames)
        history.fit_selected=d.segmentation.labels.fit_selected;
    end
    boundary=d.boundaryReconstruction;
    % 正式Excel不写入不可测Pt1或内部截面真值。下列派生量均只由
    % 可测飞参和公开模型参数计算，用于复现实验边界与审计。
    history.model_input_Pamb=boundary.Pamb_Pa;
    history.model_input_inlet_pressure_recovery= ...
        boundary.inletTotalPressureRecovery;
    % 不可测背压及模型轴功率不进入正式测量输入列。
    variants=fieldnames(d.replays);
    for j=1:numel(variants)
        variant=variants{j}; replay=d.replays.(variant);
        for k=1:numel(replay.outputNames)
            name=replay.outputNames{k};
            history.([variant '_' name])=replay.sensorExpectedOutput(:,k);
            history.([variant '_residual_' name])=replay.residual(:,k);
        end
        history.([variant '_Wf_physical'])=replay.physicalFuelInput_kgps;
    end
    writetable(history,filePath,'Sheet','history');
    writetable(d.segmentation.segments,filePath,'Sheet','segments');
    if ~isempty(d.localSmallThermalPlan)
        writetable(d.localSmallThermalPlan,filePath,'Sheet','local_small_thermal_plan');
    end
    if ~isempty(d.localTransientThermalPlan)
        writetable(d.localTransientThermalPlan,filePath,'Sheet','local_transient_thermal_plan');
    end
    if ~isempty(fieldnames(d.transientEpisodes))
        p=d.transientEpisodes;
        writetable(p.events,filePath,'Sheet','transient_events');
        writetable(p.windows,filePath,'Sheet','transient_windows');
        writetable(p.blocks,filePath,'Sheet','transient_blocks');
        writetable(p.samplePlan,filePath,'Sheet','transient_sample_plan');
        contract=table(["schema";"status";"source_sha256";"role"; ...
            "model_mode";"integration_step_s";"record_step_s"; ...
            "initial_states_are_not_measurements";"record_start_equilibrium_assumed"; ...
            "full_history_identification";"initial_state_nuisance_implemented"; ...
            "lead_in_s";"recovery_tail_s";"Ng_minimum_span_rpm"; ...
            "Wf_minimum_span_kgps";"Mkp_minimum_span_Nm"], ...
            [string(p.schemaVersion);string(p.status);string(d.sourceSha256); ...
            string(d.role);string(options.modelMode);string(p.integrationStep_s); ...
            string(p.recordStep_s);"true";string(p.options.recordStartEquilibriumAssumed); ...
            "false";"false";string(p.options.leadIn_s);string(p.options.recoveryTail_s); ...
            string(p.options.minimumNgSpan_rpm);string(p.options.minimumWfSpan_kgps); ...
            string(p.options.minimumMkpSpan_Nm)],'VariableNames',{'item','value'});
        writetable(contract,filePath,'Sheet','transient_contract');
    end
    if ~isempty(result.metricSummary)
        metric=result.metricSummary(result.metricSummary.dataset==string(d.role),:);
        writetable(metric,filePath,'Sheet','metrics');
    end
    if ~isempty(result.segmentMetricSummary)
        segmentMetric=result.segmentMetricSummary(result.segmentMetricSummary.dataset==string(d.role),:);
        writetable(segmentMetric,filePath,'Sheet','segment_metrics');
    end
    metadata=table( ...
        ["schema_version";"dataset_role";"source_file";"source_sha256"; ...
         "source_contract";"sample_count";"sample_time_s"; ...
         "inlet_boundary_mode";"pt3_eq_role"; ...
         "task_distortion_applied";"inlet_mean_recovery"; ...
         "exhaust_backpressure_model";"reynolds_correction"; ...
         "inverse_dynamic_compensation";"forward_sensor_dynamics"; ...
         "truth_data_accessed"], ...
        [string(result.schemaVersion);string(d.role);string(d.sourceFile); ...
         string(d.sourceSha256);string(result.formalInputContract); ...
         string(d.sampleCount);string(d.sampleTime_s);"5"; ...
         "output_observation_only";"false"; ...
         string(options.inletMeanRecovery); ...
         "power_squared_from_measured_Mkp_and_predicted_Np"; ...
         string(options.reynoldsEffectScale);"false"; ...
         string(options.sensorDynamicsEnabled);"false"], ...
        'VariableNames',{'item','value'});
    % 记录处理规则与先验来源，不传递生成端热参数、偏置实现或健康真值。
    metadata=[metadata;table( ...
        ["prior_source";"prior_route";"segmentation_schema"; ...
         "steady_minimum_duration_s";"steady_guard_s"; ...
         "small_change_minimum_duration_s";"small_change_maximum_duration_s"; ...
         "segmentation_order";"steady_bridge_gap_s"; ...
         "effective_altitude_rate_limit_mps";"effective_mach_rate_limit_per_s"; ...
         "segment_metric_definition"], ...
        [string(options.priorSource);string(options.priorRoute); ...
         string(d.segmentation.schemaVersion); ...
         string(d.segmentation.options.steadyMinimumDuration_s); ...
         string(d.segmentation.options.steadyGuard_s); ...
         string(d.segmentation.options.smallChangeMinimumDuration_s); ...
         string(d.segmentation.options.smallChangeMaximumDuration_s); ...
         string(d.segmentation.diagnostics.classificationOrder); ...
         string(d.segmentation.options.steadyBridgeGap_s); ...
         string(d.segmentation.diagnostics.effectiveAltitudeRateLimit_mps); ...
         string(d.segmentation.diagnostics.effectiveMachRateLimit_per_s); ...
         "continuous_replay_subset_not_independent_window_prediction"], ...
        'VariableNames',{'item','value'})]; %#ok<AGROW>
    diag=d.segmentation.diagnostics;
    limitNames=string(diag.signalNames(:))+"_small_span_limit";
    metadata=[metadata;table(["minimum_excitation_required"; ...
        "thermal_hint_excludes_small";"secondary_partition";limitNames], ...
        ["false";"false";"both_sides_of_rate_boundaries_same_eligibility"; ...
        string(diag.effectiveSpanLimits(:))], ...
        'VariableNames',{'item','value'})]; %#ok<AGROW>
    metadata=[metadata;table("temperature_pressure_span_role", ...
        "diagnostic_only_not_a_rejection_gate",'VariableNames',{'item','value'})]; %#ok<AGROW>
    metadata=[metadata;table(["secondary_boundary_rate_per_s"; ...
        "secondary_boundary_bridge_s";"secondary_boundary_expansion_s"], ...
        string([d.segmentation.options.secondaryBoundaryRate_per_s; ...
        d.segmentation.options.secondaryBoundaryBridge_s; ...
        d.segmentation.options.secondaryBoundaryExpansion_s]), ...
        'VariableNames',{'item','value'})]; %#ok<AGROW>
    if isfield(result,'taskContract')
        c=result.taskContract;
        metadata=[metadata;table( ...
            ["task_id";"task_identity";"selection_identity";"parent_source_sha256"; ...
             "no_dll_preview";"bench_fuel_bias_inherited"], ...
            [string(c.taskId);string(c.identity);string(c.selectionIdentity); ...
             string(c.parentSha256);"true";"false"], ...
            'VariableNames',{'item','value'})];
    end
    writetable(metadata,filePath,'Sheet','metadata');
    if isfield(result,'parameterSourceStatus')
        writetable(result.parameterSourceStatus,filePath,'Sheet','parameter_source_status');
    end
    fprintf('  写出3.2 %s正式Excel：%s\n',d.role,filePath);
end
end

function files=local_plot_results(result,paths,options)
files={};
for i=1:numel(result.datasets)
    d=result.datasets(i);
    sample=round(linspace(1,d.sampleCount, ...
        min(d.sampleCount,options.maximumPlotSamples)));
    if isfield(d.replays,'personalized')
        p=d.replays.personalized;
        hasZero=isfield(d.replays,'zero');
        fig=figure('Visible',options.figureVisible,'Color','w', ...
            'Position',[80,80,1250,850]);
        for j=1:numel(p.outputNames)
            subplot(2,2,j);
            plot(d.measurement.time_s(sample),p.measuredOutput(sample,j),'k-', ...
                'LineWidth',0.8,'DisplayName','测量'); hold on;
            priorLabel=sprintf('%s/%s个性化基线', ...
                result.options.priorSource,result.options.priorRoute);
            plot(d.measurement.time_s(sample),p.sensorExpectedOutput(sample,j), ...
                'r-','LineWidth',1.0,'DisplayName',priorLabel);
            if hasZero
                z=d.replays.zero;
                plot(d.measurement.time_s(sample),z.sensorExpectedOutput(sample,j), ...
                    'b--','LineWidth',0.8,'DisplayName','零修正对照');
            end
            grid on; xlabel('时间 / s');
            ylabel(sprintf('%s / %s',p.outputNames{j},p.outputUnits{j}), ...
                'Interpreter','none');
            if j==1,legend('Location','best');end
        end
        sgtitle(sprintf('3.2 %s：测量与等效回放',d.role), ...
            'Interpreter','none');
        file=fullfile(paths.reportDir,sprintf('F32_%s_replay.png',d.role));
        print(fig,file,'-dpng','-r170'); close(fig); files{end+1,1}=file; %#ok<AGROW>

        fig=figure('Visible',options.figureVisible,'Color','w', ...
            'Position',[80,80,1250,850]);
        names=p.componentCoordinateNames;
        for j=1:numel(names)
            subplot(ceil(numel(names)/2),2,j);
            plot(d.measurement.time_s(sample),p.componentCoordinate(sample,j), ...
                'LineWidth',0.9); grid on; xlabel('时间 / s');
            ylabel([names{j} ' / 1'],'Interpreter','none');
        end
        sgtitle(sprintf('3.2 %s：部件相对换算转速',d.role), ...
            'Interpreter','none');
        file=fullfile(paths.reportDir,sprintf('F32_%s_component_Ncr.png',d.role));
        print(fig,file,'-dpng','-r170'); close(fig); files{end+1,1}=file; %#ok<AGROW>

        boundary=p.boundaryReconstruction;
        fig=figure('Visible',options.figureVisible,'Color','w', ...
            'Position',[80,80,1250,760]);
        subplot(3,1,1);
        plot(d.measurement.time_s(sample),d.measurement.Ps0(sample)/1000, ...
            'k-','DisplayName','Ps0测量'); hold on;
        plot(d.measurement.time_s(sample),p.inletPt1_Pa(sample)/1000, ...
            'r-','DisplayName','C端重构Pt1（仅诊断）');
        grid on; ylabel('压力 / kPa'); legend('Location','best');
        subplot(3,1,2);
        plot(d.measurement.time_s(sample), ...
            (boundary.Pback_Pa(sample)-boundary.Pamb_Pa(sample))/1000, ...
            'm-','LineWidth',0.9);
        grid on; ylabel('排气背压增量 / kPa');
        subplot(3,1,3);
        yyaxis left;
        plot(d.measurement.time_s(sample),boundary.loadPower_W(sample)/1e6, ...
            'Color',[0.1,0.45,0.1],'LineWidth',0.9);
        ylabel('估计负载功率 / MW');
        yyaxis right;
        plot(d.measurement.time_s(sample),d.measurement.Mach(sample), ...
            'Color',[0.2,0.2,0.7],'LineWidth',0.9);
        ylabel('Mach / 1'); grid on; xlabel('时间 / s');
        sgtitle(sprintf('3.2 %s：装机边界重构',d.role), ...
            'Interpreter','none');
        file=fullfile(paths.reportDir, ...
            sprintf('F32_%s_boundary_reconstruction.png',d.role));
        print(fig,file,'-dpng','-r170');
        close(fig);
        files{end+1,1}=file; %#ok<AGROW>
    end

    fig=figure('Visible',options.figureVisible,'Color','w', ...
        'Position',[80,80,1250,850]);
    fields={'Wf','Mkp','Altitude','Mach'}; units={'kg/s','N*m','m','1'};
    for j=1:4
        subplot(5,1,j);
        plot(d.measurement.time_s(sample),d.measurement.(fields{j})(sample), ...
            'k-','LineWidth',0.8); grid on;
        ylabel(sprintf('%s / %s',fields{j},units{j}),'Interpreter','none');
    end
    subplot(5,1,5);
    classCode=local_class_code(d.segmentation.labels.segment_class);
    stairs(d.measurement.time_s(sample),classCode(sample),'LineWidth',0.9);
    grid on; xlabel('时间 / s'); ylabel('片段类别');
    yticks(0:6); yticklabels({'无效','初始化','其他','稳态','小幅','大幅','热恢复'});
    sgtitle(sprintf('3.2 %s：自动分段结果',d.role),'Interpreter','none');
    file=fullfile(paths.reportDir,sprintf('F32_%s_segmentation.png',d.role));
    print(fig,file,'-dpng','-r170'); close(fig); files{end+1,1}=file; %#ok<AGROW>
end
end

function code=local_class_code(value)
code=2*ones(numel(value),1);
names={'invalid','initialization','other','steady_window','small_change', ...
    'large_transition','thermal_recovery'};
for i=1:numel(names), code(value==names{i})=i-1; end
end

function local_write_summary(result,filePath)
fid=fopen(filePath,'w','n','UTF-8');
if fid<0,error('SHT:F32:SummaryWrite','无法写入%s。',filePath);end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'# 3.2第二轮执行摘要\n\n');
fprintf(fid,'- 生成时间：%s\n',result.createdAt);
fprintf(fid,'- 输入合同：%s。\n',result.formalInputContract);
fprintf(fid,['- 模型：modelMode=%d；进口边界模式5，C端由可测' ...
    'Ps0/Mach/Tt1/Ts_amb统一重构入口边界。\n'],result.modelMode);
fprintf(fid,'- 正式基线：%s / %s稳态调度；Visser热模型采用标称参数。\n', ...
    result.options.priorSource,result.options.priorRoute);
fprintf(fid,'- 传感器处理：不做逆补偿；模型输出经过名义FOH正向动态。\n');
fprintf(fid,['- 可测量约束：Pt3_eq只作输出观测；正式回放不读取Pt1、Pt2' ...
    '或其他仿真内部截面真值。\n']);
fprintf(fid,['- 装机边界：平均入口恢复率%.6f；排气背压按负载功率平方' ...
    '重构；RNI幅值%.3f。\n'],result.options.inletMeanRecovery, ...
    result.options.reynoldsEffectScale);
if isfield(result.modelAssetContract,'runtimeMigrationDetected')
    fprintf(fid,'- 2.7参数至当前运行基线的显式迁移：%s。\n', ...
        local_yes_no(result.modelAssetContract.runtimeMigrationDetected));
end
fprintf(fid,'- 隐藏真值访问：否。\n\n');
s=result.datasets(1).segmentation.options;
fprintf(fid,['- 分段规则：稳态优先确认，两端各保留%g s保护区，剔除后最短%g s；' ...
    '小幅变化仅在剩余数据内识别，最短%g s；两类均无时长上限。\n'], ...
    s.steadyGuard_s,s.steadyMinimumDuration_s,s.smallChangeMinimumDuration_s);
fprintf(fid,['- 分段误差口径：从同一次完整连续开环回放中按标签取样统计，' ...
    '不是独立稳态点求解，也不是小幅变化片段单独初始化回放。\n\n']);
fprintf(fid,'## 数据与计算质量\n\n');
for i=1:height(result.qualitySummary)
    q=result.qualitySummary(i,:);
    fprintf(fid,'- %s：%d点，稳态%d，小幅%d，大幅%d，热恢复%d；', ...
        q.dataset,q.sample_count,q.steady_count,q.small_change_count, ...
        q.large_transition_count,q.thermal_recovery_count);
    fprintf(fid,'个性化最大共同工作残差 %.6e，最大能量残差 %.6e，', ...
        q.personalized_maximum_residual, ...
        q.personalized_maximum_energy_residual);
    fprintf(fid,'非零标志%d，运行%.1f s；',q.personalized_nonzero_tag_count, ...
        q.personalized_runtime_s);
    fprintf(fid,'零修正最大共同工作残差 %.6e，最大能量残差 %.6e，', ...
        q.zero_maximum_residual,q.zero_maximum_energy_residual);
    fprintf(fid,'非零标志%d，运行%.1f s。\n',q.zero_nonzero_tag_count, ...
        q.zero_runtime_s);
end

fprintf(fid,'\n## 自动分段\n\n');
fprintf(fid,'|数据集|类别|连续段数|样本数|累计持续时间/s|持续时间中位数/s|最长持续时间/s|\n');
fprintf(fid,'|---|---|---:|---:|---:|---:|---:|\n');
for i=1:numel(result.datasets)
    d=result.datasets(i);
    classes=unique(d.segmentation.segments.segment_class,'stable');
    for j=1:numel(classes)
        mask=d.segmentation.segments.segment_class==classes(j);
        duration=d.segmentation.segments.duration_s(mask);
        fprintf(fid,'|%s|%s|%d|%d|%.3f|%.3f|%.3f|\n',d.role,classes(j), ...
            nnz(mask),sum(d.segmentation.segments.sample_count(mask)), ...
            sum(duration),median(duration),max(duration));
    end
end

fprintf(fid,'\n## 部件工作范围\n\n');
fprintf(fid,'|数据集|部件|最小相对换算转速|最大相对换算转速|跨度|\n');
fprintf(fid,'|---|---|---:|---:|---:|\n');
for i=1:numel(result.datasets)
    d=result.datasets(i);
    if ~isfield(d.replays,'personalized'),continue;end
    p=d.replays.personalized;
    for j=1:numel(p.componentCoordinateNames)
        lower=min(p.componentCoordinate(:,j));
        upper=max(p.componentCoordinate(:,j));
        fprintf(fid,'|%s|%s|%.8f|%.8f|%.8f|\n',d.role, ...
            p.componentCoordinateNames{j},lower,upper,upper-lower);
    end
end
fprintf(fid,'\n## 雷诺数指数范围\n\n');
fprintf(fid,['|数据集|部件|RNI最小值|RNI最大值|' ...
    '效率乘子最小值|效率乘子最大值|\n']);
fprintf(fid,'|---|---|---:|---:|---:|---:|\n');
for i=1:numel(result.datasets)
    d=result.datasets(i);
    if ~isfield(d.replays,'personalized'),continue;end
    p=d.replays.personalized;
    for j=1:numel(p.reynoldsComponentNames)
        fprintf(fid,'|%s|%s|%.8f|%.8f|%.8f|%.8f|\n',d.role, ...
            p.reynoldsComponentNames{j},min(p.reynoldsIndex(:,j)), ...
            max(p.reynoldsIndex(:,j)), ...
            min(p.reynoldsEfficiencyMultiplier(:,j)), ...
            max(p.reynoldsEfficiencyMultiplier(:,j)));
    end
end
fprintf(fid,'\n## 四通道观测误差\n\n');
fprintf(fid,'|数据集|基线|通道|单位|RMSE|均值误差|最大绝对误差|RMSE/设计参考(%%)|\n');
fprintf(fid,'|---|---|---|---:|---:|---:|---:|---:|\n');
for i=1:height(result.metricSummary)
    r=result.metricSummary(i,:);
    fprintf(fid,'|%s|%s|%s|%s|%.8g|%.8g|%.8g|%.5f|\n', ...
        r.dataset,r.variant,r.channel,r.unit,r.rmse,r.mean_error, ...
        r.maximum_absolute_error,r.rmse_pct_design);
end
fprintf(fid,'\n## 个性化基线相对零修正的RMSE变化\n\n');
fprintf(fid,'|数据集|通道|单位|零修正RMSE|个性化RMSE|改善率/%%|\n');
fprintf(fid,'|---|---|---:|---:|---:|---:|\n');
for i=1:height(result.baselineComparison)
    r=result.baselineComparison(i,:);
    fprintf(fid,'|%s|%s|%s|%.8g|%.8g|%.5f|\n',r.dataset,r.channel, ...
        r.unit,r.zero_rmse,r.personalized_rmse,r.personalized_improvement_pct);
end
fprintf(fid,'\n## 计算结论\n\n');
if result.options.replayEnabled
    fprintf(fid,'- 总体验收：%s。\n',local_pass(result.validation.passed));
else
    fprintf(fid,'- 数据合同检查：%s；物理回放未执行，不能解释为模型验证通过。\n',local_pass(result.validation.passed));
end
fprintf(fid,'- 训练与独立验证严格分离：%s。\n', ...
    local_pass(result.validation.trainingValidationSeparated));
if result.options.replayEnabled
    fprintf(fid,'- 个性化回放计算完整性：%s。\n',local_pass(result.validation.primaryReplayPassed));
else
    fprintf(fid,'- 个性化回放：NOT_EXECUTED，本次仅执行数据预处理。\n');
end
end

function local_print_summary(result)
fprintf('\n3.2第二轮完成：\n');
disp(result.qualitySummary);
fprintf('四通道观测误差：\n');
disp(result.metricSummary);
if ~isempty(result.baselineComparison)
    fprintf('%s/%s个性化基线相对零修正的RMSE改善：\n', ...
        result.options.priorSource,result.options.priorRoute);
    disp(result.baselineComparison);
end
if result.options.replayEnabled
    fprintf('总体验收：%s\n',local_pass(result.validation.passed));
else
    fprintf('数据合同检查：%s；物理回放未执行。\n',local_pass(result.validation.passed));
end
if result.options.saveEnabled
    fprintf('内部MAT：%s\n',result.output.latestMatFile);
    fprintf('训练Excel：%s\n',result.output.identificationExcel);
    fprintf('验证Excel：%s\n',result.output.validationExcel);
end
end

function value=local_pass(flag)
if flag,value='PASS';else,value='FAIL';end
end

function value=local_yes_no(flag)
if flag,value='是';else,value='否';end
end

function value=local_vertcat_or_empty(rows)
if isempty(rows),value=table();else,value=vertcat(rows{:});end
end

function dataset=local_empty_dataset()
dataset=struct('role','','sourceFile','','sourceSha256','', ...
    'sampleCount',0,'sampleTime_s',NaN,'measurement',table(), ...
    'segmentation',struct(),'transientEpisodes',struct(),'replays',struct(), ...
    'localSmallThermalPlan',table(),'localTransientThermalPlan',table(), ...
    'boundaryReconstruction',struct(),'truthDataAccessed',false);
end

function merged=local_merge_struct(base,override)
merged=base;
names=fieldnames(override);
for i=1:numel(names),merged.(names{i})=override.(names{i});end
end

function hash=local_file_hash(fileName)
hash=sht_transient_model_adapt_common('fileHash',fileName);
end
