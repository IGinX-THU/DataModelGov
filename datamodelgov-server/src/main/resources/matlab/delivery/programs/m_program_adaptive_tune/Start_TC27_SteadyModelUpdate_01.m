function result=Start_TC27_SteadyModelUpdate_01(request)
%START_TC27_STEADYMODELUPDATE_01 用新增试车记录更新已有三部件稳态模型。
% request中的四个必需文件/位置均由使用者显式指定。execute=false先检查
% 输入和形成运行方案；execute=true依次调用现行05与06，不启动瞬态07。
% 测试点和测试历程分别传cell路径列表；缺省为空，不参与训练或分组。
requestTimer=tic;
assert(nargin==1&&isstruct(request)&&isscalar(request), ...
    'TC27:UI:Request','请输入一个配置结构体。');
required={'upstreamModelFile','steadyTrainingFile','trainingHistoryFile','outputDirectory'};
for j=1:numel(required)
    name=required{j};assert(isfield(request,name)&&~isempty(request.(name)), ...
        'TC27:UI:Required','缺少必需配置%s。',name);
end
route=local_value(request,'route','transient_instant');
method=local_value(request,'method','II');
assert(ismember(route,{'steady','transient_instant'})&&ismember(method,{'I','II'}), ...
    'TC27:UI:Choice','只支持steady/transient_instant及I/II四种组合。');
testPointFiles=local_value(request,'testPointFiles',{});
testHistoryFiles=local_value(request,'testHistoryFiles',{});
assert(iscell(testPointFiles)&&iscell(testHistoryFiles),'TC27:UI:TestType', ...
    '可选测试文件须用cell路径列表，未提供时使用空cell。');
for j=1:numel(required)-1
    name=required{j};request.(name)=local_existing_file(request.(name),name);
end
for j=1:numel(testPointFiles),testPointFiles{j}=local_existing_file(testPointFiles{j},'testPointFiles');end
for j=1:numel(testHistoryFiles),testHistoryFiles{j}=local_existing_file(testHistoryFiles{j},'testHistoryFiles');end
outputDirectory=sht_tc27_canonical_path(request.outputDirectory);
assert(isfolder(fileparts(outputDirectory)),'TC27:UI:OutputParent', ...
    '独立输出位置的父目录不存在：%s',fileparts(outputDirectory));
execute=local_value(request,'execute',false);
assert(isscalar(execute)&&(islogical(execute)||ismember(execute,[0,1])), ...
    'TC27:UI:Execute','execute只能为true或false。');
preview=local_value(request,'preview',false);
resume=local_value(request,'resume',false);
assert((islogical(preview)||ismember(preview,[0,1]))&& ...
    (islogical(resume)||ismember(resume,[0,1]))&&isscalar(preview)&&isscalar(resume)&& ...
    ~(preview&&execute)&&~(preview&&resume)&&(~resume||execute), ...
    'TC27:UI:Mode','preview、execute、resume的组合不合法。');
previewFile=fullfile(outputDirectory,'MiddleData','tc27_preview_identity.mat');
existing=isfolder(outputDirectory);
assert(~isfile(outputDirectory)&& ...
    (~existing||((execute||resume)&&isfile(previewFile)))&& ...
    (~resume||existing)&&(~preview||~existing), ...
    'TC27:UI:OutputExists','只允许全新任务目录或带匹配05预览的原目录。');
opts=local_value(request,'estimationOptions',struct());
assert(isstruct(opts)&&isscalar(opts),'TC27:UI:Options','estimationOptions须为标量结构体。');
% 输入与输出身份由独立入口唯一指定，不容许高级配置暗中改写。
reserved={'explicitInputs','upstreamModelFile','steadyTrainingFile','trainingHistoryFile', ...
    'testPointFiles','testHistoryFiles','outputDirectory','resume','reusePointFitFile'};
assert(~any(isfield(opts,reserved)),'TC27:UI:Reserved','输入、输出及续算选项必须在本入口明确配置。');
opts.explicitInputs=true;opts.upstreamModelFile=request.upstreamModelFile;
opts.steadyTrainingFile=request.steadyTrainingFile;
opts.trainingHistoryFile=request.trainingHistoryFile;
opts.testPointFiles=testPointFiles;opts.testHistoryFiles=testHistoryFiles;
opts.outputDirectory=outputDirectory;opts.resume=false;opts.reusePointFitFile='';
opts.includeSmallHistory=local_value(request,'includeSmallHistory',true);
opts.plot=local_value(request,'plot',false);
opts.tag=local_value(request,'runTag','UI_R051');
opts.resume=logical(resume);opts.runControlEnabled=logical(execute);
% 入口和内部求值使用同一包；默认仍遵守当前正式选择。
if isfield(request,'runtimeDirectory')&&~isempty(request.runtimeDirectory)
    if isfield(opts,'runtimeDirectory')&&~isempty(opts.runtimeDirectory)
        assert(strcmpi(sht_tc27_canonical_path(opts.runtimeDirectory), ...
            sht_tc27_canonical_path(request.runtimeDirectory)), ...
            'TC27:UI:Runtime','入口与estimationOptions的运行目录不一致。');
    end
    opts.runtimeDirectory=request.runtimeDirectory;
end
opts=sht_tc27_estimation_options(route,method,opts);
model=sht_load_2p4_deterministic_delivery(route,request.upstreamModelFile,'formal');
selection='selected';
if isfield(opts,'runtimeDirectory')&&~isempty(opts.runtimeDirectory),selection=opts.runtimeDirectory;end
package=sht_tc27_runtime_package(selection);
input=struct('upstreamModelFile',request.upstreamModelFile, ...
    'upstreamSHA256',sht_tc27_file_identity(request.upstreamModelFile), ...
    'steadyTrainingFile',request.steadyTrainingFile, ...
    'steadyTrainingSHA256',sht_tc27_file_identity(request.steadyTrainingFile), ...
    'trainingHistoryFile',request.trainingHistoryFile, ...
    'trainingHistorySHA256',sht_tc27_file_identity(request.trainingHistoryFile), ...
    'testPointFiles',{testPointFiles},'testHistoryFiles',{testHistoryFiles});
runId=sprintf('tc27_%s_%s_%s',opts.tag,route,method);
estimate=sht_tc27_runtime_estimate('steady_update',opts, ...
    struct('route',route,'resume',resume));
% 新计时从公开入口开始；旧elapsed_s仍保留其原有的06结束前口径。
timing=struct('schema','TC27_UI_TIMING_V1','clock','tic/toc elapsed seconds', ...
    'startBoundary','public_function_entry_before_preflight', ...
    'modelReadyBoundary','after_formal_excel_and_identity_json_before_ui_mat', ...
    'modelReadyElapsed_s',NaN,'preflightElapsed_s',NaN, ...
    'excludes','ui_result_mat_save,completed_progress_write,final_log_and_return', ...
    'status','preflight_only');
result=struct('status','ready','executed',false,'runId',runId, ...
    'route',route,'method',method,'effectiveOptions',opts,'inputs',input, ...
    'runtimePackage',package.id,'runtimeDirectory',package.directory, ...
    'upstreamRunId',model.runId,'outputDirectory',outputDirectory, ...
    'estimatedTime',estimate,'estimatedBefore',estimate,'estimatedAfter',[], ...
    'elapsed_s',0,'timing',timing, ...
    'uqStatus','not_run_for_this_updated_model');
fprintf('TC27更新准备完成：%s；粗估不作为迭代停止条件。\n',runId);
result.timing.preflightElapsed_s=toc(requestTimer);
if ~execute&&~preview,return;end
timer=tic;p=sht_tc27_paths(opts);
logFile=fullfile(p.report,[runId,'_console.log']);clean=[];
if ~existing,diary(logFile);clean=onCleanup(@()diary('off'));end
workflowProgress=fullfile(p.report,[runId,'_workflow_progress.csv']);
preparedFile=fullfile(p.middle,'tc27_prepared_data.mat');
if existing
    assert(isfile(preparedFile),'TC27:UI:PreparedMissing','预览目录缺少05准备结果。');
    saved=load(previewFile,'identity');
    preparedIdentity=sht_tc27_prepared_identity(route,method,opts,preparedFile);
    assert(isequaln(saved.identity,preparedIdentity),'TC27:UI:PreviewIdentity', ...
        '输入、筛选配置、模型或源码已改变，不能复用原05预览。');
    loaded=load(preparedFile,'result');prepared=loaded.result;
    fprintf('复用经身份验证的05预览：%s\n',preparedFile);
else
    fprintf('开始05预处理：%s\n',datestr(now,31));
    prepared=Start_TC27_05_DataPreparation(opts);
    preparedIdentity=sht_tc27_prepared_identity(route,method,opts,preparedFile);
    identity=preparedIdentity;save(previewFile,'identity','-v7.3');
end
result.preparation=prepared;
result.previewIdentityFile=previewFile;
result.selectedRangesFile=prepared.rangeIndexFile;
result.estimatedAfter=local_estimate(request,opts,package,prepared,outputDirectory,toc(requestTimer));
result.estimatedTime=result.estimatedAfter;
fprintf('05完成：原稳态点%d个、新历程稳态窗口%d个、小幅段%d个、训练分组%d组；已用%.1fs。\n', ...
    height(prepared.steady23),height(prepared.train.means),numel(prepared.train.small), ...
    prepared.groupCount,toc(timer));
if preview
    result.status='preview_ready';result.timing.status='preprocessed_preview';
    result.previewElapsed_s=toc(requestTimer);
    clear clean;return;
end

runIdentity=local_run_identity(route,method,opts,preparedIdentity,package,p.root);
control=sht_tc24_run_control('open',struct('directory',outputDirectory, ...
    'runId',runId,'resume',logical(resume),'timer',requestTimer),runIdentity);
opts.runControl=control;result.effectiveOptions=opts;
result.progressFile=fullfile(p.report,[runId,'_progress.csv']);
result.workflowProgressFile=workflowProgress;result.logFile=logFile;
try
    firstEstimateFile=fullfile(p.middle,'tc27_initial_estimate.mat');
    if isfile(firstEstimateFile)
        savedEstimate=load(firstEstimateFile,'firstEstimate');
        result.originalEstimatedTime=savedEstimate.firstEstimate;
    else
        assert(~resume,'TC27:UI:InitialEstimateMissing','恢复时缺少首次预计值记录。');
        firstEstimate=result.estimatedTime;
        save(firstEstimateFile,'firstEstimate');
    end
    result.initialEstimateFile=firstEstimateFile;
    if resume
        assert(isfile(workflowProgress),'TC27:UI:ResumeProgress', ...
            '恢复时缺少原任务进度日志。');
        local_workflow(workflowProgress,'resumed',toc(timer),true);
        [savedPrepared,found]=sht_tc24_run_control('load',control,'Prepared');
        assert(found&&strcmpi(savedPrepared.preparedSHA256,preparedIdentity.preparedSHA256), ...
            'TC27:UI:ResumePrepared','停止点的05准备结果与当前文件不一致。');
    else
        local_workflow(workflowProgress,'05_completed',toc(timer),false);
        sht_tc24_run_control('boundary',control,'Prepared', ...
            struct('preparedSHA256',preparedIdentity.preparedSHA256, ...
            'progress',struct('stage','05_completed','groups',prepared.groupCount)));
    end
    if existing,diary(logFile);clean=onCleanup(@()diary('off'));end
    local_workflow(workflowProgress,'06_started',toc(timer),true);
    fprintf('开始06稳态系数辨识：%s/%s。\n',route,method);
    fit=Start_TC27_06_SteadyScheduleEstimation(route,method,opts);
catch failure
    if strcmp(failure.identifier,'TC24:Control:Stopped')
        result.status='stopped';result.executed=true;result.stopReason='user_requested_safe_stop';
        result.elapsed_s=toc(timer);result.timing.status='stopped_at_safe_boundary';
        stoppedState=sht_tc24_run_control('state',outputDirectory);
        result.timing.totalActiveElapsed_s=stoppedState.activeSeconds;
        result.timing.pausedElapsed_s=stoppedState.pausedSeconds;
        local_workflow(workflowProgress,'stopped',toc(timer),true);
        fprintf('TC27已在完整安全单元保存后停止；目录：%s\n',outputDirectory);
        clear clean;return;
    end
    try
        sht_tc24_run_control('finishsession',outputDirectory,control.sessionToken,'failed',requestTimer);
    catch controlFailure
        warning('TC27:UI:ControlFinish','异常会话状态记录失败：%s',controlFailure.message);
    end
    rethrow(failure);
end
try
result.status='delivered';result.executed=true;
result.elapsed_s=toc(timer);result.fit=fit;
result.stopReason=char(string(fit.D1.stopReason));
result.converged=fit.D1.converged;result.deliveryFile=fit.deliveryFile;
result.deliverySHA256=fit.deliverySha256;
result.trainingMetrics=fit.validation.trainingPointMetrics;
result.testMetrics=fit.validation.steadyMetrics;
result.smallHistoryTestMetrics=fit.validation.historyMetrics;
result.finalSchedule=fit.finalSchedule;result.nodeContract=fit.nodeContract;
result.fuelBias=fit.finalSchedule.fuelBias;result.fuelBiasUnit='kg/s';
result.trainingPredictions=fit.validation.trainingPointReplays;
result.testPredictions=fit.validation.steady;
result.smallHistoryTestPredictions=fit.validation.smallHistories;
result.modelIdentityFile=local_identity_sidecar(fit,p,package);
% 此刻正式Excel及其身份JSON均已存在；MAT保存和最终日志另见进度文件。
result.timing.modelReadyElapsed_s=toc(requestTimer);
result.timing.status='formal_model_ready';
priorState=sht_tc24_run_control('state',outputDirectory);
result.timing.totalActiveElapsed_s=priorState.priorActiveSeconds+toc(requestTimer);
result.timing.pausedElapsed_s=priorState.pausedSeconds;
save(fullfile(p.middle,[runId,'_ui_result.mat']),'result','-v7.3');
local_workflow(workflowProgress,'completed',toc(timer),true);
state=sht_tc24_run_control('finishsession',outputDirectory,control.sessionToken,'completed',requestTimer);
local_record_time(request,opts,package,prepared,outputDirectory,runId,state.activeSeconds);
fprintf('06完成：%s；停止原因%s；耗时%.1fs；模型%s。\n', ...
    result.status,result.stopReason,result.elapsed_s,result.deliveryFile);
fprintf('正式模型就绪用时%.1fs（入口至Excel/身份JSON）；末端I/O完成时刻见%s。\n', ...
    result.timing.modelReadyElapsed_s,workflowProgress);
catch failure
    state=sht_tc24_run_control('state',outputDirectory);
    if strcmp(state.status,'running')
        sht_tc24_run_control('finishsession',outputDirectory,control.sessionToken,'failed',requestTimer);
    end
    rethrow(failure);
end
clear clean;
end

function value=local_value(s,name,fallback)
value=fallback;if isfield(s,name)&&~isempty(s.(name)),value=s.(name);end
end

function file=local_existing_file(value,label)
assert((ischar(value)||isstring(value))&&isscalar(string(value)), ...
    'TC27:UI:FileType','%s应为单个本地文件路径。',label);
file=char(string(value));assert(isfile(file),'TC27:UI:MissingFile','%s不存在：%s',label,file);
[ok,info]=fileattrib(file);assert(ok,'TC27:UI:FileAccess','不能读取%s：%s',label,file);
file=info.Name;
end

function file=local_identity_sidecar(fit,p,package)
% 只给本次新模型记录资产身份；不更改正式Excel的最小下游合同。
[~,name]=fileparts(fit.deliveryFile);file=fullfile(p.middle,[name,'_identity.json']);
id=struct('schema','TC27_MODEL_IDENTITY_V1','runId',fit.runId, ...
    'modelSHA256',fit.deliverySha256,'upstreamSHA256',fit.identity.upstream, ...
    'runtimePackageId',package.id,'runtimeDirectory',package.directory, ...
    'dllSHA256',fit.identity.dll,'thermalSHA256',fit.identity.thermal, ...
    'route',fit.route,'method',fit.method,'modelMode',fit.modelMode, ...
    'thermalMode',fit.thermalMode);
if isfile(file)
    old=jsondecode(fileread(file));
    assert(strcmpi(old.modelSHA256,id.modelSHA256)&&strcmp(old.runId,id.runId), ...
        'TC27:UI:IdentityExists','已有模型身份文件与当前结果不一致：%s',file);
    return;
end
fid=fopen(file,'w','n','UTF-8');assert(fid>0,'TC27:UI:IdentityWrite','不能写入模型身份。');
fprintf(fid,'%s',jsonencode(id));fclose(fid);
end

function local_workflow(file,stage,elapsed,append)
mode='w';if append,mode='a';end
fid=fopen(file,mode,'n','UTF-8');assert(fid>0,'TC27:UI:ProgressWrite', ...
    '无法记录任务进度：%s',file);
if ~append,fprintf(fid,'stage,elapsed_s\n');end
fprintf(fid,'%s,%.6f\n',stage,elapsed);fclose(fid);
end

function identity=local_run_identity(route,method,options,prepared,package,root)
% 只剔除恢复会话自身的易变字段，物理/数据/数学配置全数锁定。
fixed=options;
fixed.resume=false;fixed.runControl=[];
names={'Start_TC27_SteadyModelUpdate_01.m','Start_TC27_05_DataPreparation.m', ...
    'Start_TC27_06_SteadyScheduleEstimation.m','sht_tc27_steady_estimation.m', ...
    'sht_tc27_regularized_solve.m','sht_tc27_condition_diagnostics.m', ...
    'sht_tc27_objective.m','sht_tc27_schedule.m','sht_tc27_replay.m', ...
    'sht_tc27_config.m','sht_tc27_estimation_options.m', ...
    'sht_tc27_replay_histories.m','sht_tc27_segment_history.m', ...
    'sht_tc27_paths.m','sht_tc27_validate_steady.m', ...
    'sht_tc27_local_history_plan.m','sht_tc27_local_history_objective.m', ...
    'sht_tc27_prepared_history_objective.m','sht_tc27_final_jacobian_audit.m', ...
    'sht_steady_model_adapt_v2_common.m','sht_bounded_least_squares.m', ...
    'sht_thermal_equilibrium_solve.m','sht_load_engine_library.m', ...
    'sht_tc27_export_range_index.m','sht_tc27_prepared_identity.m', ...
    'sht_tc24_run_control.m','sht_tc24_runtime_estimate.m'};
source=cellfun(@(name)sht_tc27_file_identity(fullfile(root,name)),names,'UniformOutput',false);
identity=struct('schema','TC27_UI_RUN_V1','route',route,'method',method, ...
    'options',fixed,'prepared',prepared,'runtime',package.identity, ...
    'sourceFiles',{names},'sourceSHA256',{source}, ...
    'matlabRelease',version('-release'),'architecture',computer('arch'));
end

function query=local_timing_query(request,options,package,prepared,outputDirectory)
history=local_value(request,'timingHistoryDirectory', ...
    fullfile(fileparts(outputDirectory),'TC27_timing_history'));
history=sht_tc27_canonical_path(history);
assert(~strcmpi(history,outputDirectory),'TC27:UI:TimingDirectory', ...
    '计时记录目录不能与任务输出目录相同。');
count=0;
for j=1:numel(prepared.train.small)
    count=count+height(prepared.train.small(j).data);
end
workUnits=max(1,height(prepared.combinedSteady)+count/100);
cohort=struct('task','TC27_steady_update', ...
    'route',local_value(request,'route','transient_instant'), ...
    'method',local_value(request,'method','II'),'thermalMode',options.thermalMode, ...
    'regularizationB',options.regularizationB,'regularizationD',options.regularizationD, ...
    'lambdaD',options.lambdaD,'maxIterationB',options.maxIterationB, ...
    'maxIterationD0',options.maxIterationD0,'maxIterationD1',options.maxIterationD1, ...
    'integrationStep_s',options.integrationStep_s, ...
    'includeSmallHistory',options.includeSmallHistory, ...
    'runtimePackageId',package.id,'runtimeIdentity',package.identity, ...
    'algorithmSourceSHA256',sht_tc27_file_identity( ...
        fullfile(fileparts(mfilename('fullpath')),'sht_tc27_steady_estimation.m')), ...
    'solverSourceSHA256',sht_tc27_file_identity( ...
        fullfile(fileparts(mfilename('fullpath')),'sht_tc27_regularized_solve.m')), ...
    'host',getenv('COMPUTERNAME'),'matlabRelease',version('-release'), ...
    'scope','entry_active_seconds_without_user_pause');
query=struct('directory',history,'cohort',cohort,'workUnits',workUnits);
end

function estimate=local_estimate(request,options,package,prepared,outputDirectory,preparationElapsed)
query=local_timing_query(request,options,package,prepared,outputDirectory);
history=sht_tc24_runtime_estimate('estimate',query);
estimate=sht_tc27_runtime_estimate('steady_update',options, ...
    struct('route',local_value(request,'route','transient_instant'), ...
    'prepared',prepared,'preparationElapsed_s',preparationElapsed, ...
    'resume',local_value(request,'resume',false),'historyEstimate',history));
end

function local_record_time(request,options,package,prepared,outputDirectory,runId,activeSeconds)
query=local_timing_query(request,options,package,prepared,outputDirectory);
suffix=sht_tc24_run_control('hash',outputDirectory);
record=struct('status','completed','activeSeconds',activeSeconds, ...
    'runId',[runId,'_',suffix(1:8)]);
try
    sht_tc24_runtime_estimate('record',query,record);
catch failure
    warning('TC27:UI:TimingRecord','运行完成，但可比计时记录写入失败：%s',failure.message);
end
end
