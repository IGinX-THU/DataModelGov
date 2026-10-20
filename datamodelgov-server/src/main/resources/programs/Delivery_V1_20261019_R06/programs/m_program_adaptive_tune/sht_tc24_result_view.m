function view=sht_tc24_result_view(input,plotEnabled)
% 已保存数值结果的独立消费接口；不重新求解、不要求GUI或原工作区。
% 正式Excel用于跨阶段模型恢复；result_view.mat用于本次任务完整结果浏览。
if nargin<2,plotEnabled=false;end
if ischar(input)||(isstring(input)&&isscalar(input))
    file=sht_tc24_absolute_path(input);[~,~,ext]=fileparts(file);
    if strcmpi(ext,'.xlsx')
        manifest=readtable(file,'Sheet','Manifest','PreserveVariableNames',true);
        kind=local_excel_kind(manifest);
        if strcmp(kind,'uncertainty_delivery')
            % 只读Excel恢复联合后验；不重算、不搜索latest、不更新历史身份。
            delivery=sht_load_2p4_uq_delivery(file);
            view=struct('kind','uncertainty_delivery','delivery',delivery, ...
                'parameterTable',delivery.parameterTable,'fuelBiasUnit','kg/s', ...
                'message','Excel恢复联合后验；训练/测试预测与耗时请读取本任务result.mat及执行记录。');
            if plotEnabled,disp(delivery.parameterTable);end
            return;
        end
        delivery=sht_load_2p4_deterministic_delivery(char(string(manifest.route(1))),file,'formal');
        view=struct('kind','delivery_model','delivery',delivery, ...
            'message','正式Excel仅恢复下游模型；训练/测试明细请读取result_view.mat。');return;
    end
    saved=load(file);
    if isfield(saved,'preview'),view=saved.preview;view.kind='preprocessing_preview';
    elseif isfield(saved,'presentation'),view=saved.presentation;
    elseif isfield(saved,'result'),view=sht_tc24_result_view(saved.result,false);
    else,error('TC24:Result:Format','文件中没有presentation或result。');end
    if isfield(saved,'execution'),view=local_execution(view,saved.execution);end
    % 新结果只读取自身明确引用的最终执行记录，不搜索latest或其他任务目录。
    if isfield(view,'execution') && isfield(view.execution,'recordRelativePath')
        relative=char(view.execution.recordRelativePath);
        allowed={'execution.json',fullfile('..','execution.json'), ...
            'steady_model_input_prediction_execution.json'};
        assert(ismember(relative,allowed),'TC24:Result:ExecutionReference', ...
            '执行记录相对引用不属于当前结果包的约定位置。');
        record=fullfile(fileparts(file),relative);
        if isfile(record)
            fid=fopen(record,'r','n','UTF-8');assert(fid>=0,'无法读取执行记录。');
            guard=onCleanup(@()fclose(fid));text=fread(fid,Inf,'*char').';clear guard;
            view=local_execution(view,jsondecode(text),true);
        end
    end
else
    r=input;
    if isfield(r,'status') && ismember(r.status,{'stopped','partial','failed'})
        view=r;view.kind='incomplete_run';return;
    end
    if isfield(r,'method') && isfield(r,'steps')
        view=r;view.kind='uncertainty_assessment';return;
    elseif isfield(r,'predictionTable')
        view=r;view.kind='independent_prediction';return;
    end
    view=struct('schemaVersion','TC24_RESULT_VIEW_V1','kind','identification');
    fields={'runId','route','options','input','groups','parameterDefinition', ...
        'parameterClassTable','groupEstimateTable','scheduleNodeTable','finalSchedule', ...
        'predictionTrainingTable','predictionTestTable','baseline','final','acceptance', ...
        'stageA','stageB','groupResults','stageRefine','stageRefinePass1','stageRefinePass2', ...
        'steadyTestFromTransient','timing','output','resultContractHash', ...
        'identity','deterministicContractHash','nodeContractHash', ...
        'residualScales','residualWeighting','residualStatistics','execution'};
    for k=1:numel(fields),if isfield(r,fields{k}),view.(fields{k})=r.(fields{k});end,end
    if isfield(view,'options'),view.options.progressCallback=[];end
    view.fuelBiasUnit='kg/s';
    view.convergenceDoesNotBlockDelivery=true;
    view.status='completed';
    if isfield(r,'acceptance') && ~r.acceptance.deliveryEligible,view.status='completed_diagnostic';end
end
if plotEnabled && isfield(view,'scheduleNodeTable')
    % 通用浏览只显示表；完整原有曲线图由求解入口plotEnabled控制。
    disp(view.scheduleNodeTable);
end
end

function kind=local_excel_kind(manifest)
% method_id是两类合同共有字段，不能用于分派；其余完整性由原读取器核查。
assert(height(manifest)==1,'TC24:Result:ManifestRows', ...
    'Excel的Manifest必须且只能有一行。');
names=manifest.Properties.VariableNames;
assert(all(ismember({'schema_version','route'},names)), ...
    'TC24:Result:MissingContract','Manifest缺少schema_version或route，无法确定结果类型。');
schema=string(manifest.schema_version(1));route=string(manifest.route(1));
assert(~ismissing(schema)&&strlength(strtrim(schema))>0 && ...
    ~ismissing(route)&&strlength(strtrim(route))>0, ...
    'TC24:Result:MissingContract','Manifest的合同版本或路径为空。');
deterministic=all(ismember({'correction_schedule_row_count','measurement_bias_row_count'},names));
uncertainty=all(ismember({'parameter_count','sample_count','formal_status'},names));
assert(~(deterministic&&uncertainty),'TC24:Result:AmbiguousContract', ...
    'Manifest同时包含确定性与UQ类型标记，不能猜测或尝试另一读取器。');
if ismember(schema,["SHT_2P4_DETERMINISTIC_EXCEL_DELIVERY_V2", ...
        "SHT_2P4_DETERMINISTIC_EXCEL_DELIVERY_V3"])
    assert(~uncertainty,'TC24:Result:AmbiguousContract','确定性合同版本与UQ类型标记冲突。');
    assert(deterministic,'TC24:Result:MissingContract','确定性Manifest缺少调度或偏置行数标记。');
    kind='delivery_model';
elseif schema=="SHT_2P4_UQ_EXCEL_DELIVERY_V1"
    assert(~deterministic,'TC24:Result:AmbiguousContract','UQ合同版本与确定性类型标记冲突。');
    assert(uncertainty,'TC24:Result:MissingContract','UQ Manifest缺少参数数、样本数或状态标记。');
    kind='uncertainty_delivery';
else
    error('TC24:Result:UnsupportedContract','不支持的Excel结果合同：%s。',char(schema));
end
end

function view=local_execution(view,execution,finalRecord)
% 只透传已保存字段；不推算旧资产身份或缺失耗时。跨任务侧车必须拒绝。
if nargin<3,finalRecord=false;end
assert(isstruct(execution)&&isscalar(execution)&&isfield(execution,'runId'), ...
    'TC24:Result:ExecutionFormat','执行记录缺少明确runId。');
if isfield(view,'runId')
    assert(strcmp(char(view.runId),char(execution.runId)), ...
        'TC24:Result:ExecutionMismatch','结果与执行记录的runId不一致。');
end
if isfield(view,'execution')
    old=view.execution;
    assert(isfield(old,'runId') && strcmp(char(old.runId),char(execution.runId)), ...
        'TC24:Result:ExecutionMismatch','两个执行记录的runId不一致。');
    if isfield(old,'task')
        assert(isfield(execution,'task')&&strcmp(char(old.task),char(execution.task)), ...
            'TC24:Result:ExecutionMismatch','两个执行记录的任务类型不一致。');
    end
end
if finalRecord
    % 大MAT中冻结的旧字段保持原类型（JSON会将未知预计时间NaN写成null）。
    % 侧车只更新明确的最终状态和新增计时，不覆盖估计依据及原elapsed。
    names={'status','stopReason','entryTiming','control','actualActiveSeconds', ...
        'currentSessionSeconds','pausedSeconds','initialEstimateComparison','timingHistoryWarning'};
    for k=1:numel(names)
        if isfield(execution,names{k}),view.execution.(names{k})=execution.(names{k});end
    end
    if isfield(view.execution,'entryTiming')
        t=view.execution.entryTiming;
        if isempty(t.secondsToResultReady) && strcmp(t.resultState,'failed')
            view.execution.entryTiming.secondsToResultReady=NaN;
        end
    end
else
    view.execution=execution;
end
end
