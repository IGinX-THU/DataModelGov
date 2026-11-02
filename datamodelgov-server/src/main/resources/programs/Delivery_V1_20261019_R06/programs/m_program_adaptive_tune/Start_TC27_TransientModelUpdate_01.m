function result=Start_TC27_TransientModelUpdate_01(request)
%START_TC27_TRANSIENTMODELUPDATE_01 新试车记录更新已有三部件瞬态模型。
% 无GUI依赖：inspect仅校核，preview生成选段草稿，execute执行同一07算法。
clock=tic;
assert(nargin==1&&isstruct(request)&&isscalar(request), ...
    'TC27:TransientUI:Request','请提供单个配置结构体。');
preview=local_option(request,'preview',false);
execute=local_option(request,'execute',false);
resume=local_option(request,'resume',false);
assert(isscalar(preview)&&isscalar(execute)&&isscalar(resume)&& ...
    ~(preview&&execute)&&(~resume||execute), ...
    'TC27:TransientUI:Mode','preview/execute/resume组合无效。');
scope=sht_tc27_transient_prepare('inspect',request);
model=scope.model;directory=scope.outputDirectory;
% 首次核对后固定实际目录，后续准备/复验不再重新解释selected别名。
request.runtimeDirectory=scope.package.directory;
tag=char(local_option(request,'runTag','UI_R068'));
assert(~isempty(regexp(tag,'^[A-Za-z0-9_]+$','once')), ...
    'TC27:TransientUI:Tag','runTag只能包含字母、数字和下划线。');
route=model.route;method=model.method;
if isfield(request,'route'),assert(strcmp(request.route,route), ...
        'TC27:TransientUI:Route','辨识路径必须与父稳态模型一致。');end
if isfield(request,'method'),assert(strcmp(request.method,method), ...
        'TC27:TransientUI:Method','方法必须与父稳态模型一致。');end
runId=sprintf('tc27_transient_%s_%s_%s_event_windows',tag,route,method);
result=struct('status','ready','executed',false,'runId',runId, ...
    'route',route,'method',method,'outputDirectory',directory, ...
    'inputs',scope.input,'runtimePackage',scope.package.id, ...
    'runtimeDirectory',scope.package.directory, ...
    'estimatedBefore',scope.estimatedBefore,'estimatedAfter',[], ...
    'estimatedTime',scope.estimatedBefore,'actualElapsed_s',toc(clock), ...
    'safeStopPolicy','prepared_or_accepted_iteration_boundary', ...
    'uqStatus','not_available_for_nonzero_transient_coefficients');
fprintf('TC27瞬态任务粗估：%.0f~%.0f分钟（R021实测单位工作量，未选段）。\n', ...
    result.estimatedTime.lower_s/60,result.estimatedTime.upper_s/60);
if ~preview&&~execute,return;end
if isfile(scope.preparedFile)
    prepared=sht_tc27_transient_prepare('verify',request);
else
    assert(~resume,'TC27:TransientUI:Resume','缺少相同身份的选段准备，不得续算。');
    if isfolder(directory)
        entries=dir(directory);entries=entries(~ismember({entries.name},{'.','..'}));
        assert(isempty(entries),'TC27:TransientUI:OutputExists','新任务输出目录非空。');
    end
    prepared=sht_tc27_transient_prepare('prepare',request);
end
result.status='preview_ready';result.selection=prepared.selection;
result.preparedFile=prepared.preparedFile;
result.selectionFile=prepared.selectionFile;
result.estimatedAfter=prepared.estimatedAfter;
result.estimatedTime=prepared.estimatedAfter;
result.actualElapsed_s=toc(clock);
fprintf('事件选段%d段，拟合%d记录，积分%d记录；修正后粗估%.0f~%.0f分钟。\n', ...
    height(result.selection),sum(result.selection.fitSamples), ...
    sum(result.selection.integrationSamples),result.estimatedTime.lower_s/60, ...
    result.estimatedTime.upper_s/60);
if preview,return;end
% 限定可调数值选项；来源、范围和输出目录不可被高级字段暗中覆盖。
fitOptions=local_option(request,'estimationOptions',struct());
assert(isstruct(fitOptions)&&isscalar(fitOptions), ...
    'TC27:TransientUI:Options','estimationOptions须为标量结构体。');
allowed={'lambda','priorScale','maxIterations','differenceStep', ...
    'integrationStep_s','validationIntegrationStep_s', ...
    'objectiveImprovementTolerance','reusePreparationForJacobian'};
assert(all(ismember(fieldnames(fitOptions),allowed)), ...
    'TC27:TransientUI:Options','估计配置包含禁止覆盖的字段。');
opts=fitOptions;
opts.steadyFile=scope.input.steadyModelFile;
opts.trainingHistoryFile=scope.input.trainingHistoryFile;
opts.testHistoryFiles=scope.input.testHistoryFiles;
opts.preparedFile=prepared.preparedFile;
opts.runtimeDirectory=scope.package.directory;
opts.outputDirectory=directory;opts.dataScope='event_windows';
opts.localWarmup_s=scope.input.localWarmup_s;
opts.tag=tag;opts.resume=logical(resume);opts.plot=false;
opts.validateTruth=false;opts.saveTrainingPrediction=true;
opts.reusePreparationForJacobian=local_option(opts,'reusePreparationForJacobian',true);
opts.integrationStep_s=local_option(opts,'integrationStep_s',.1);
opts.validationIntegrationStep_s=local_option(opts,'validationIntegrationStep_s',.025);
opts.maxIterations=local_option(opts,'maxIterations',6);
assert(ismember(opts.integrationStep_s,[.1,.025])&& ...
    ismember(opts.validationIntegrationStep_s,[.1,.025]), ...
    'TC27:TransientUI:Step','积分步长只允许0.1或0.025秒。');
p=sht_tc27_paths(opts);
identity=struct('input',scope.input,'preparedSHA256', ...
    sht_tc27_file_identity(prepared.preparedFile), ...
    'runtimeManifestSHA256',scope.input.runtimeManifestSHA256, ...
    'route',route,'method',method,'options',opts, ...
    'sourceIdentity',{local_sources(p.root)});
identity.options.resume=[];
control=sht_tc24_run_control('open',struct('directory',directory, ...
    'runId',runId,'resume',logical(resume),'timer',tic),identity);
opts.runControl=control;
logFile=fullfile(p.report,[runId,'_console.log']);
diary(logFile);logCleanup=onCleanup(@()diary('off'));
try
    fprintf('开始13维瞬态系数辨识；训练选段%d段，参数差分=forward，积分步长=%g秒。\n', ...
        height(result.selection),opts.integrationStep_s);
    fit=Start_TC27_07_TransientParameterEstimation(route,method,opts);
    combinedFile=fullfile(p.middle,'tc27_combined_transient_model.xlsx');
    combined=sht_tc27_transient_combined_delivery('write', ...
        struct('steadyFile',opts.steadyFile,'transientCoefficients',fit.estimate, ...
        'runId',runId),combinedFile,struct('runtimeDirectory',scope.package.directory));
    result.status='model_ready';result.executed=true;
    if strcmp(fit.testValidationStatus,'invalid_prediction')
        result.status='model_ready_test_invalid';
    end
    result.testValidationStatus=fit.testValidationStatus;
    result.stopReason=char(string(fit.solve.stopReason));
    result.converged=logical(fit.solve.converged);
    result.iterationCount=fit.solve.iterationCount;
    result.fitDllEvaluationCount=fit.fitDllEvaluationCount;
    result.fitHistoryReplayCount=fit.fitHistoryReplayCount;
    result.baselineDllEvaluationCount=fit.baselineDllEvaluationCount;
    result.estimatedTrainingDllEvaluationCount=fit.estimatedTrainingDllEvaluationCount;
    result.fitElapsed_s=fit.fitWallTime_s;
    result.stationarityPassed=NaN;
    if isfield(fit.solve,'exactJacobianAudit')
        result.stationarityPassed=logical(fit.solve.exactJacobianAudit.firstOrderStationarityPassed);
    end
    result.parameters=table((58:70).',fit.names,fit.estimate, ...
        'VariableNames',{'hIndex','parameter','estimate'});
    result.inheritedFuelBias=combined.fuelBias;
    result.inheritedSteadySchedule=combined.steadySchedule;
    result.trainingMetrics=fit.trainingMetrics;
    result.trainingBaselineMetrics=fit.trainingBaselineMetrics;
    result.testMetrics=fit.testMetrics;
    result.trainingCurveDirectory=fullfile(p.report,runId);
    result.modelFile=combinedFile;result.modelSHA256=combined.sha256;
    result.internalResultFile=fullfile(p.middle,[runId,'_result.mat']);
    result.actualElapsed_s=toc(clock);
    result.logFile=logFile;
    summaryFile=fullfile(p.middle,'tc27_transient_ui_result.mat');
    result.summaryFile=summaryFile;save(summaryFile,'result','-v7.3');
    manifest=struct('schema','TC27_TRANSIENT_MODEL_PROVENANCE_V1', ...
        'runId',runId,'modelFile',combinedFile,'modelSHA256',combined.sha256, ...
        'parentSteadySHA256',model.sha256,'preparedSHA256',identity.preparedSHA256, ...
        'runtimePackage',scope.package.id,'runtimeManifestSHA256', ...
        scope.input.runtimeManifestSHA256,'trainingSHA256', ...
        scope.input.trainingHistorySHA256,'testSHA256',{scope.input.testSHA256}, ...
        'integrationStep_s',opts.integrationStep_s,'status',result.status);
    fid=fopen(fullfile(p.middle,'tc27_combined_transient_model_identity.json'),'w','n','UTF-8');
    assert(fid>=0,'TC27:TransientUI:Manifest','组合模型身份JSON无法写入。');
    cleanup=onCleanup(@()fclose(fid));fprintf(fid,'%s\n',jsonencode(manifest));clear cleanup;
    sht_tc24_run_control('finish',control,'completed');
    fprintf('模型已交付：%s；总耗时%.1f秒，停止原因%s。\n', ...
        combinedFile,result.actualElapsed_s,result.stopReason);
catch failure
    if strcmp(failure.identifier,'TC24:Control:Stopped')
        result.status='stopped_at_safe_boundary';result.actualElapsed_s=toc(clock);
        result.stopReason=failure.message;
        fprintf('%s\n',failure.message);
        return;
    end
    try
        sht_tc24_run_control('finish',control,'failed');
    catch cleanupFailure
        warning('TC27:TransientUI:ControlCleanup','失败状态写入未完成：%s',cleanupFailure.message);
    end
    rethrow(failure);
end
end

function value=local_option(s,name,fallback)
value=fallback;if isfield(s,name)&&~isempty(s.(name)),value=s.(name);end
end
function sources=local_sources(root)
names={'Start_TC27_TransientModelUpdate_01.m', ...
    'Start_TC27_07_TransientParameterEstimation.m', ...
    'sht_tc27_transient_prepare.m','sht_tc27_transient_combined_delivery.m', ...
    'sht_tc27_regularized_solve.m','sht_tc27_prepared_history_objective.m'};
sources=cell(numel(names),2);
for j=1:numel(names)
    sources{j,1}=names{j};
    sources{j,2}=sht_tc27_file_identity(fullfile(root,names{j}));
end
end
