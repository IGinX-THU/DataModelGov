function result=Start_TC27_UQ_ModelAssessment_01(request)
%START_TC27_UQ_MODELASSESSMENT_01 界面和离线共用的模型匹配UQ入口。
% request.options必须显式列出模型、上游Excel、两类训练Excel及独立输出目录。
% execute=false仅准备合同；停止只在D完整迭代或C完整温度层生效。
assert(nargin==1&&isstruct(request)&&isscalar(request), ...
    'TC27:UQ:Request','请输入标量任务配置。');
assert(isfield(request,'options')&&isstruct(request.options), ...
    'TC27:UQ:Options','缺少显式UQ配置。');
options=request.options;method=local_value(request,'method','D');
assert(ismember(upper(method),{'D','C','CD'}),'TC27:UQ:Method','只允许D/C/CD。');
execute=logical(local_value(request,'execute',false));
resume=logical(local_value(request,'resume',false));
publish=logical(local_value(request,'publish',true));
assert(~resume||execute,'TC27:UQ:Resume','恢复必须同时执行。');
timer=tic;
if strcmpi(method,'D'),options=sht_tc27_uq_d_options(options);
else,options=sht_tc27_uq_c_options(options);end
local_preflight(options,method,resume,execute);
estimateBefore=sht_tc27_runtime_estimate(['uq_',upper(method)],options, ...
    struct('publish',publish,'resume',resume));
c=sht_tc27_uq_contract(options);
% 05只准备一次；09复用本合同已校验的准备资产，避免重复写范围索引。
options.preparedFile=c.inputContract.preparedFile;
historyDirectory=local_value(request,'timingHistoryDirectory', ...
    fullfile(fileparts(char(options.outputDirectory)),'uq_timing_history'));
timingQuery=struct('directory',historyDirectory,'workUnits',1, ...
    'cohort',struct('schema','TC27_UQ_TIME_V2','contractHash',c.contractHash, ...
    'method',upper(method),'route',c.route,'modelMethod',c.method, ...
    'parameterCount',c.parameterCount,'observationCount',numel(c.observed), ...
    'backend',c.options.steadyCBackend,'publish',publish, ...
    'testIdentity',{arrayfun(@(x)x.sourceSHA256,c.testSets,'UniformOutput',false)}, ...
    'matlabRelease',version('-release')));
history=sht_tc24_runtime_estimate('estimate',timingQuery);
prepared=load(c.inputContract.preparedFile,'result');
model=struct('route',c.route,'finalSchedule',c.scheduleTemplate);
estimate=sht_tc27_runtime_estimate(['uq_',upper(method)],c.options, ...
    struct('publish',publish,'resume',resume,'prepared',prepared.result,'model',model, ...
    'preparationElapsed_s',toc(timer),'historyEstimate',history));
result=struct('status','prepared','method',upper(method),'route',c.route, ...
    'modelMethod',c.method,'contractHash',c.contractHash, ...
    'parameterCount',c.parameterCount,'observationCount',numel(c.observed), ...
    'directory',c.directory,'outputDirectory',char(string(options.outputDirectory)), ...
    'selectedModelFile',c.formalInputFile,'estimatedTime',estimate, ...
    'estimatedBefore',estimateBefore,'estimatedAfter',estimate);
if ~execute
    result.elapsed_s=toc(timer);return;
end
codeRoot=fileparts(mfilename('fullpath'));
sources={'Start_TC27_UQ_ModelAssessment_01.m','Start_TC27_09_UncertaintyAssessment.m', ...
    'sht_tc27_uq_direct_c.m','sht_tc27_uq_smc.m','sht_tc27_uq_move_reference.m','sht_tc27_uq_method_c.m', ...
    'sht_tc27_uq_delivery.m','Start_TC27_10_UncertaintyPrediction.m'};
sourceHashes=cellfun(@(name)sht_tc27_file_identity(fullfile(codeRoot,name)), ...
    sources,'UniformOutput',false);
identity=struct('schema','TC27_UQ_RUN_V1','contractHash',c.contractHash, ...
    'method',upper(method),'sourceNames',{sources},'sourceHashes',{sourceHashes}, ...
    'modelSHA256',c.identity.delivery,'runtime',c.runtimeIdentity, ...
    'randomSeed',c.options.randomSeed,'particleCount',c.options.particleCount, ...
    'matlabRelease',version('-release'),'architecture',computer('arch'));
runId=sprintf('TC27_UQ_%s_%s',c.contractHash(1:12),upper(method));
control=sht_tc24_run_control('open',struct('directory',options.outputDirectory, ...
    'runId',runId,'resume',resume,'timer',timer),identity);
try
    if ~resume
        sht_tc24_run_control('save',control,'InitialEstimate',estimate);
    else
        [initialEstimate,found]=sht_tc24_run_control('load',control,'InitialEstimate');
        if found,result.originalEstimatedTime=initialEstimate;end
    end
    result.assessment=Start_TC27_09_UncertaintyAssessment(method,options,control);
    result.inferenceReady_s=toc(timer);
    if publish
        result.prediction=Start_TC27_10_UncertaintyPrediction(result.assessment.directory);
        result.deliveryReady_s=toc(timer);
    else
        result.deliveryReady_s=NaN;
    end
    result.status='completed';
    state=sht_tc24_run_control('finish',control,'completed');
    result.activeElapsed_s=state.activeSeconds;
    result.pausedElapsed_s=state.pausedSeconds;
    timingId=sht_tc24_run_control('hash',struct( ...
        'directory',sht_tc24_absolute_path(options.outputDirectory)));
    try
        result.timingRecord=sht_tc24_runtime_estimate('record',timingQuery,struct( ...
            'status','completed','activeSeconds',state.activeSeconds, ...
            'runId',[runId,'_',timingId(1:12)]));
    catch timingFailure
        result.timingRecord='unavailable';
        result.timingWarning=timingFailure.message;
        warning('TC27:UQ:TimingRecord','UQ已完成，但计时记录未能保存：%s',timingFailure.message);
    end
catch failure
    if strcmp(failure.identifier,'TC24:Control:Stopped')
        state=sht_tc24_run_control('state',options.outputDirectory);
        result.status='stopped';result.safePoint=state.safePoint;
        result.activeElapsed_s=state.activeSeconds;
        result.pausedElapsed_s=state.pausedSeconds;
        result.elapsed_s=toc(timer);return;
    end
    sht_tc24_run_control('finish',control,'failed');
    rethrow(failure);
end
result.elapsed_s=toc(timer);
end

function value=local_value(s,name,fallback)
value=fallback;if isfield(s,name),value=s.(name);end
end

function local_preflight(options,method,resume,execute)
assert(isfield(options,'outputDirectory')&&~isempty(options.outputDirectory)&& ...
    isfield(options,'modelFile')&&isfile(char(options.modelFile)), ...
    'TC27:UQ:Preflight','运行前必须指定有效模型Excel和独立输出目录。');
modelFile=char(options.modelFile);
model=sht_tc27_delivery('read',[],modelFile);
assert(ismember(model.route,{'steady','transient_instant'})&& ...
    ismember(model.method,{'I','II'}),'TC27:UQ:Preflight', ...
    '模型路由或方法不在当前UQ消费范围。');
identityFile=fullfile(fileparts(modelFile), ...
    ['tc27_deterministic_',model.route,'_',model.method,'_identity.json']);
if isfield(options,'modelIdentityFile')&&~isempty(options.modelIdentityFile)
    identityFile=char(options.modelIdentityFile);
end
assert(isfile(identityFile),'TC27:UQ:Preflight','模型身份JSON不存在。');
modelIdentity=jsondecode(fileread(identityFile));
assert(strcmp(modelIdentity.schema,'TC27_MODEL_IDENTITY_V1')&& ...
    strcmpi(modelIdentity.modelSHA256,sht_tc27_file_identity(modelFile))&& ...
    strcmp(modelIdentity.route,model.route)&&strcmp(modelIdentity.method,model.method), ...
    'TC27:UQ:Preflight','模型Excel及身份JSON不匹配。');
package=sht_tc27_runtime_package();
sht_tc27_uq_input_contract(options,model,struct('runtime',package.directory),true);
if ~execute,return;end
controlDirectory=fullfile(char(options.outputDirectory),'run_control');
if ~isfolder(controlDirectory)
    assert(~resume,'TC27:UQ:Preflight','输出目录没有旧运行，不允许恢复。');
    return;
end
assert(resume,'TC27:UQ:Preflight','输出目录已有运行，只能核验身份后恢复。');
assert(~isfile(fullfile(controlDirectory,'session.lock')), ...
    'TC27:UQ:Preflight','已有运行锁，不能并行恢复。');
state=sht_tc24_run_control('state',options.outputDirectory);
assert(ismember(state.status,{'stopped','failed','partial'})&&state.checkpointAvailable, ...
    'TC27:UQ:Preflight','旧运行不是可恢复的安全停止点。');
saved=load(fullfile(controlDirectory,'identity.mat'),'record');
assert(strcmpi(saved.record.identity.modelSHA256,modelIdentity.modelSHA256)&& ...
    strcmp(saved.record.identity.method,upper(method)), ...
    'TC27:UQ:Preflight','旧运行的模型或UQ方法不同，不能复用目录。');
contracts=dir(fullfile(char(options.outputDirectory),'MiddleData','uq_*','contract.mat'));
assert(numel(contracts)==1&& ...
    isfolder(fullfile(char(options.outputDirectory),'report_outputs')), ...
    'TC27:UQ:Preflight','旧运行缺少唯一合同或报告目录，不能在原目录恢复。');
old=load(fullfile(contracts(1).folder,contracts(1).name),'c');
assert(strcmp(old.c.contractHash,saved.record.identity.contractHash)&& ...
    isfile(old.c.inputContract.preparedFile), ...
    'TC27:UQ:Preflight','旧运行合同与控制记录或准备数据不一致。');
if isfield(options,'preparedFile')&&~isempty(options.preparedFile)
    assert(strcmpi(sht_tc27_file_identity(options.preparedFile), ...
        old.c.inputContract.preparedSHA256), ...
        'TC27:UQ:Preflight','显式准备数据与旧运行不同。');
end
probe=options;probe.preparedFile=old.c.inputContract.preparedFile;
current=sht_tc27_uq_contract(probe,true);
assert(strcmp(current.contractHash,saved.record.identity.contractHash), ...
    'TC27:UQ:Preflight','数值配置、源文件或输入身份已变化；请使用新输出目录。');
end
