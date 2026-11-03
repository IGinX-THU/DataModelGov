function session=sht_tc24_execution(options,task,entry)
% 可选回调只消费实际事件；回调/绘图失败不改变计算目标或中止求解。
% 每次调用独立计时与记录，不使用base workspace或全局持久状态。
timer=tic;sessionStartDatenum=now;callback=[];directory='';resume=false;
sessionToken=strrep(char(java.util.UUID.randomUUID()),'-','');finalSummary=[];
% entry只通过独立实参传递，不混入求解配置、概率合同或保存的函数闭包。
if nargin<3,entry=[];end
if isfield(options,'progressCallback'),callback=options.progressCallback;end
runId=options.runId;
assert(~isempty(regexp(runId,'^[A-Za-z0-9_-]+$','once')), ...
    'TC24:RunId:Invalid','runId仅允许英文字母、数字、下划线与短横线。');
if isfield(options,'outputDirectory') && ~isempty(options.outputDirectory)
    directory=fullfile(sht_tc24_absolute_path(options.outputDirectory),runId);
    resume=(isfield(options,'firstStep') && options.firstStep>1)|| ...
        (isfield(options,'resume')&&logical(options.resume));
    assert(~exist(directory,'dir')||resume,'TC24:Output:Exists', ...
        '任务目录已存在，请使用新的runId；不得覆盖其他任务。');
    if ~exist(directory,'dir'),mkdir(directory);end
end
estimate=struct('available',false,'seconds',NaN,'basis', ...
    '当前入口未提供工作量估时模型；不提供虚假倒计时。');
if isfield(options,'runtimeEstimate')&&~isempty(options.runtimeEstimate)
    % 正式业务优先使用冻结工作量模型；其他入口仍可沿用原历史计时接口。
    estimate=options.runtimeEstimate;
elseif isfield(options,'timingQuery')&&~isempty(options.timingQuery)
    try
        estimate=sht_tc24_runtime_estimate('estimate',options.timingQuery);
    catch err
        estimate.basis=['估时记录不可用：',err.message];
    end
end
% 首次估计文件保持原样；恢复时将本次修订估计与首次估计分开记录。
initialFile=fullfile(directory,'initial_estimate.mat');
if ~isempty(directory)
    if resume && isfile(initialFile)
        saved=load(initialFile,'estimate');
        if isfield(options,'runtimeEstimate')&&~isempty(options.runtimeEstimate)
            estimate.initialEstimate=saved.estimate;
            estimate.revised=true;
        else
            estimate=saved.estimate;
        end
    elseif ~resume
        save(initialFile,'estimate');
    end
end
validationPending=resume&&isfield(options,'enableRunControl')&&options.enableRunControl;
session=struct('notify',@notify,'snapshot',@snapshot,'finish',@finish, ...
    'directory',directory,'estimate',estimate,'timer',timer,'sessionStartDatenum',sessionStartDatenum, ...
    'sessionToken',sessionToken);
notify(struct('phase','preflight','status','running','message',estimate.basis));
    function notify(event)
        event.runId=runId;event.task=task;event.elapsedSeconds=toc(timer);
        if ~isempty(entry),event.entryElapsedSeconds=toc(entry.timer);end
        event.timestamp=datestr(now,30);
        if ~isempty(directory)&&isfile(fullfile(directory,'run_control','state.mat'))
            event.control=sht_tc24_run_control('state',directory);
            if validationPending&&isfield(event.control,'sessionToken')&&strcmp(event.control.sessionToken,sessionToken)
                validationPending=false;
            end
        end
        if ~isfield(event,'message'),event.message='';end
        fprintf('[%s] %s %.1fs %s\n',runId,event.phase,event.elapsedSeconds,event.message);
        if ~isempty(directory)&&~validationPending
            writeJson(fullfile(directory,'status.json'),event,'w');
            writeJson(fullfile(directory,'progress.jsonl'),event,'a');
        end
        if ~isempty(callback)
            try,callback(event);catch e,warning('TC24:Callback:Failure','回调失败，计算继续：%s',e.message);end
        end
    end
    function summary=snapshot(status,reason)
        % 保持原elapsedSeconds的快照边界；先不发布完成事件，大MAT只保存一次。
        summary=struct('runId',runId,'task',task,'status',status, ...
            'stopReason',reason,'elapsedSeconds',toc(timer),'estimate',estimate, ...
            'outputDirectory',directory);
        summary.status='finalizing';
        if ~isempty(entry)
            summary.entryTiming=entryTiming(NaN,'pending_result_save','not_ready');
        end
        if ~isempty(directory),summary.recordRelativePath='execution.json';end
    end
    function summary=finish(status,reason,summary,outputScope,recordFile)
        if ~isempty(finalSummary),summary=finalSummary;return;end
        if nargin<3 || isempty(summary),summary=snapshot(status,reason);end
        if nargin<4
            if isempty(directory),outputScope='in_memory';else,outputScope='saved_outputs';end
        end
        if nargin<5,recordFile='';end
        summary.status=status;summary.stopReason=reason;
        if validationPending
            % 拒绝恢复属于本次尝试，不把原安全停止记录改成failed。
            summary.attemptOnly=true;
            writeJson(fullfile(directory,['resume_attempt_',sessionToken,'.json']),summary,'w');
            finalSummary=summary;return;
        end
        if ~isempty(directory)&&isfile(fullfile(directory,'run_control','state.mat'))
            summary.control=sht_tc24_run_control('state',directory);
            if strcmp(summary.control.sessionToken,sessionToken)
                summary.control=sht_tc24_run_control('finishsession',directory,sessionToken,status,timer);
            end
        end
        summary.currentSessionSeconds=toc(timer);
        summary.actualActiveSeconds=summary.currentSessionSeconds;
        if isfield(summary,'control')
            summary.actualActiveSeconds=summary.control.priorActiveSeconds+summary.currentSessionSeconds;
            summary.pausedSeconds=summary.control.pausedSeconds;
        end
        if ~isempty(entry)
            seconds=toc(entry.timer);state='result_ready';
            if strcmp(status,'partial'),state='partial_result_ready';end
            if strcmp(status,'failed'),seconds=NaN;state='failed';end
            if strcmp(status,'stopped'),state='safe_stop_checkpoint_ready';end
            summary.entryTiming=entryTiming(seconds,state,outputScope);
        end
        % 到此数值结果已就绪。只写一次最终元数据，不把自身写入耗时回填大MAT。
        if ~isempty(directory)
            writeJson(fullfile(directory,'execution.json'),summary,'w');
        elseif ~isempty(recordFile)
            % 兼容通用预测的旧默认目录，只写本次入口明确给出的配套记录。
            writeJson(recordFile,summary,'w');
        end
        if ismember(status,{'completed','completed_diagnostic'})&& ...
                isfield(options,'timingQuery')&&~isempty(options.timingQuery)
            seconds=toc(timer);
            if isfield(summary,'control'),seconds=summary.control.priorActiveSeconds+toc(timer);end
            initialComparisonEstimate=estimate;
            if isfield(estimate,'initialEstimate'),initialComparisonEstimate=estimate.initialEstimate;end
            summary.initialEstimateComparison=struct('actualActiveSeconds',seconds, ...
                'initialEstimate',initialComparisonEstimate, ...
                'scope','本次会话及已恢复有效计算；排除用户暂停');
            if isfield(estimate,'revised')
                summary.initialEstimateComparison.revisedEstimate=estimate;
            end
            try
                sht_tc24_runtime_estimate('record',options.timingQuery, ...
                    struct('runId',runId,'status',status,'activeSeconds',seconds));
            catch err
                summary.timingHistoryWarning=err.message;
                warning('TC24:ETA:RecordFailure','计时样本未记录，数值结果保持有效：%s',err.message);
            end
            if ~isempty(directory),writeJson(fullfile(directory,'execution.json'),summary,'w');end
        end
        notify(struct('phase','finished','status',status,'message',reason));
        finalSummary=summary;
    end
    function value=entryTiming(seconds,state,outputScope)
        value=struct('entryPoint',entry.entryPoint,'displayName',entry.displayName, ...
            'startedAt',entry.startedAt,'secondsToResultReady',seconds, ...
            'resultState',state,'outputScope',outputScope, ...
            'scope',['从所标入口开始，含该入口内配置、预检、计算及已请求的大结果保存；', ...
            '不含外层入口开销、最终execution.json及状态事件落盘尾部、函数返回。']);
    end
end
function writeJson(file,value,mode)
fid=fopen(file,mode,'n','UTF-8');assert(fid>=0,'TC24:Log:Open','无法写日志%s。',file);
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(value));
end
