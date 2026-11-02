function result=sht_tc24_run_estimation(route,user)
% 两种调用方式共用此编排层及原A/B/C/D求解内核，不读取造数真值。
entry=struct('timer',tic,'startedAt',datestr(now,30), ...
    'entryPoint',mfilename,'displayName','辨识核心入口耗时');
if nargin<2,user=struct();end
o=sht_tc24_estimation_options(route,user);
if isfield(user,'trainingFile') && ~isempty(user.trainingFile)
    assert(isfield(user,'outputDirectory') && ~isempty(user.outputDirectory), ...
        'TC24:Output:Required','指定业务训练文件时必须指定独立outputDirectory。');
end
if isfield(user,'testFile'),o.evaluateTestSet=~isempty(user.testFile);end
o.trainingFile=sht_tc24_absolute_path(o.trainingFile);
if ~isempty(o.testFile),o.testFile=sht_tc24_absolute_path(o.testFile);end
data=sht_tc24_validate_measurements(o.trainingFile);
testCount=0;
if o.evaluateTestSet
    testData=sht_tc24_validate_measurements(o.testFile);
    testCount=height(testData);
end
assert(isempty(o.pt1TruthFile),'TC24:Input:Truth','业务辨识不得使用真值边界。');
if isempty(o.runId),o.runId=['tc24_',route,'_',datestr(now,'yyyymmdd_HHMMSS'),'_', ...
        strrep(char(java.util.UUID.randomUUID()),'-','')];end
if o.enableRunControl
    assert(~isempty(o.outputDirectory),'TC24:Control:Output','安全停止需独立输出目录。');
    o.runControlOptions=struct('directory',fullfile(sht_tc24_absolute_path(o.outputDirectory),o.runId), ...
        'runId',o.runId,'resume',logical(o.resume));
end
if ~isempty(o.timingHistoryDirectory)
    o.timingQuery=sht_tc24_runtime_estimate('query',o,['identification_',route]);
end
eventOptions=o;
eventOptions.runtimeEstimate=sht_tc24_fixed_runtime_estimate( ...
    ['identification_',route],o,height(data),testCount);
session=sht_tc24_execution(eventOptions,['identification_',route],entry);
if o.enableRunControl
    o.runControlOptions.timer=session.timer;
    o.runControlOptions.sessionStartDatenum=session.sessionStartDatenum;
    o.runControlOptions.sessionToken=session.sessionToken;
end
o.progressCallback=session.notify;
try
    session.notify(struct('phase','preparation','status','running','message', ...
        sprintf('训练%d点，实际均值样本数%d..%d。',height(data),min(data.sample_count),max(data.sample_count))));
    if strcmp(o.nodeReferencePolicy,'fixed_engineering') && isempty(fieldnames(o.nodeEngineeringReference))
        if ~isempty(o.preparedInput)
            saved=load(o.preparedInput,'preview');
            % 完整内容校验由同一内核在基准回放前执行，未通过不能进入辨识。
            o.nodeEngineeringReference=saved.preview.identity.options.nodeEngineeringReference;
            o.nodeEngineeringReferenceSource=saved.preview.identity.options.nodeEngineeringReferenceSource;
        else
            reference=sht_tc24_node_engineering_reference(false,o);
            o.nodeEngineeringReference=reference.axes;
            o.nodeEngineeringReferenceSource=reference.signature;
        end
    end
    result=sht_steady_model_adapt_v2_common('run',route,o);
    if isfield(result.options,'runControl')
        result.control=sht_tc24_run_control('finish',result.options.runControl,'completed');
    end
    assert(height(result.parameterDefinition)+1==12,'应为11项发动机修正及燃油偏置。');
    result.execution=session.snapshot('completed',result.stageRefine.stopReason);
    result.presentation=sht_tc24_result_view(result,false);
    if ~isempty(session.directory)
        presentation=result.presentation;execution=result.execution; %#ok<NASGU>
        save(fullfile(session.directory,'result_view.mat'),'presentation','execution');
    end
    result.execution=session.finish('completed',result.stageRefine.stopReason,result.execution);
    result.presentation.execution=result.execution;
catch err
    if strcmp(err.identifier,'TC24:Control:Stopped')
        result=struct('runId',o.runId,'route',route,'status','stopped', ...
            'control',sht_tc24_run_control('state',session.directory));
        result.execution=session.finish('stopped',err.message,[],'safe_checkpoint_only');return;
    end
    session.finish('failed',[err.identifier,': ',err.message]);rethrow(err);
end
end
