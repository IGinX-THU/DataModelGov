function result = Start_SteadyModelPredict_01_InputDrivenPrediction( ...
        modelInput, estimationResultFile, posteriorOptions, executionOptions)
%START_STEADYMODELPREDICT_01_INPUTDRIVENPREDICTION 输入驱动稳态预测入口。
%
% modelInput可为标量结构体或表，环境边界支持互斥输入方式：
%   模式1：可测Pt1、Tt1、Pamb、Wf_model、Mkp、Mkg（三部件TC24）；
%   模式2：Pamb、Tamb、Mach、Wf_model、Mkp、Mkg；
%   模式3：Altitude、Tamb、Mach、Wf_model、Mkp、Mkg。
% 所有模式另需Mach、Tamb环境字段，模式1也不以Tt1替代静温Tamb。
% 可选字段为point_id、Np_initial、Ng_initial和inletBoundaryMode。若同时
% 提供Pamb和Altitude，必须显式指定模式。省略modelInput时使用模式2
% 的六部件模型设计点输入。模式3由DLL标准大气模型根据高度计算Pamb。
%
% 本入口不使用目标工况测量输出，不经过总距角或控制闭环，也不对目标
% Wf_model重复应用测量偏置。默认读取正式Excel中的调度和Np选根模型，
% 不读取原训练表或内部MAT。显式指定.mat仅供内部回归对照。
% 省略posteriorOptions时只计算确定性预测。正式Excel后验传播显式提供
% struct('workbookFile',后验Excel路径)，支持B/C/D，仅传播参数条件模型输出。
% 旧method/runId加载方式只保留给显式MAT输入的内部历史回归。
% 第四参数executionOptions只控制本次执行，不改变Excel生成身份：
%   runtimeSelection='auto'：仅已声明TC24参数字典的Excel使用TC24所选包；
%   'model_default'：保留模型原有目录；'tc24_selected'：明确选择TC24包。
%   runtimeDirectory：显式隔离/历史包，与非auto选择互斥。
%   writeOutputs=false：短回归不更新任何预测latest或输出文件。

entry=struct('timer',tic,'startedAt',datestr(now,30), ...
    'entryPoint',mfilename,'displayName','独立稳态预测入口耗时');
if nargin<4,executionOptions=struct();end
explicitOutput=isfield(executionOptions,'outputDirectory') && ~isempty(executionOptions.outputDirectory);
if ~isfield(executionOptions,'runId') || isempty(executionOptions.runId)
    executionOptions.runId=['prediction_',datestr(now,'yyyymmdd_HHMMSS'),'_', ...
        strrep(char(java.util.UUID.randomUUID()),'-','')];
end
session=sht_tc24_execution(executionOptions,'independent_steady_prediction',entry);
try
if explicitOutput
    paths.middleDataDir=fullfile(session.directory,'MiddleData');
    paths.reportOutputDir=fullfile(session.directory,'report_outputs');
    mkdir(paths.middleDataDir);mkdir(paths.reportOutputDir);
else
    paths=sht_steady_model_adapt_v2_common('paths');
end
if nargin < 1
    modelInput = [];
end
if nargin < 2
    estimationResultFile = '';
end
if nargin < 3
    posteriorOptions = [];
end
assert(isstruct(executionOptions) && isscalar(executionOptions), ...
    'SHT:SteadyPrediction:ExecutionOptions','executionOptions必须是标量结构体。');
if ischar(posteriorOptions) || ...
        (isstring(posteriorOptions) && isscalar(posteriorOptions))
    posteriorOptions = struct('method', char(posteriorOptions));
end
posteriorPredictionRequested = ~isempty(posteriorOptions);
if posteriorPredictionRequested && ...
        (~isstruct(posteriorOptions) || ~isscalar(posteriorOptions))
    error('SHT:SteadyPrediction:BadPosteriorOptions', ...
        'posteriorOptions必须为空、方法字符或标量结构体。');
end
defaultResultFile = fullfile(paths.middleDataDir, ...
    'steady_model_2p4_delivery','2p4_deterministic_transient_instant.xlsx');
estimationResultFile = sht_resolve_delivery_input_file( ...
    estimationResultFile, defaultResultFile);
if exist(estimationResultFile,'file') ~= 2
    error('SHT:SteadyPrediction:MissingEstimationResult', ...
        '辨识结果文件不存在：%s。',estimationResultFile);
end
[~,~,extension]=fileparts(estimationResultFile);
generation=struct('file',estimationResultFile, ...
    'fileSha256',sht_steady_model_uq_common('filehash',estimationResultFile), ...
    'manifest',table(),'runId','');
if strcmpi(extension,'.xlsx')
    manifest=readtable(estimationResultFile,'Sheet','Manifest');
    delivery=sht_load_2p4_deterministic_delivery( ...
        char(string(manifest.route(1))),estimationResultFile,'formal');
    loaded=struct('result',delivery.model);
    generation.manifest=delivery.manifest;
    generation.runId=delivery.runId;
else
    loaded = load(estimationResultFile,'result');
end
if ~isfield(loaded,'result') || ~isstruct(loaded.result)
    error('SHT:SteadyPrediction:BadEstimationResult', ...
        '文件不包含有效辨识结果变量result：%s。',estimationResultFile);
end
[loaded.result,execution]=local_select_runtime( ...
    loaded.result,generation.manifest,executionOptions);
if isempty(generation.runId) && isfield(loaded.result,'runId')
    generation.runId=loaded.result.runId;
end
if isfield(loaded.result,'truthWasRead') && loaded.result.truthWasRead
    error('SHT:SteadyPrediction:TruthContaminatedResult', ...
        '所选辨识结果读取过隐藏真值，不能用于实际交付预测。');
end
% 三部件结果必须留在独立路径，不覆盖旧六部件单点预测latest。
if loaded.result.options.modelMode==0 && ~explicitOutput
    paths=sht_steady_model_adapt_v2_common('paths',struct('modelMode',0));
end

usedDefaultDesignInput = isempty(modelInput);
% 初始化与气路回放从相同options取得运行目录，避免两次加载不同DLL。
engineConfig=struct('modelMode',loaded.result.options.modelMode);
if isfield(loaded.result.options,'runtimeDirectory')
    engineConfig.runtimeDirectory=loaded.result.options.runtimeDirectory;
end
cfg = sht_default_config(struct('engine',engineConfig));
execution.runtimeDirectory=cfg.engine.interface.controlDir;
execution.artifacts=sht_engine_artifact_identity(cfg.engine);
execution.modelMode=cfg.engine.modelMode;
execution.generationIdentityRewritten=false;
if usedDefaultDesignInput
    modelInput = struct('point_id',"DESIGN_POINT", ...
        'inletBoundaryMode',2,'Altitude',0, ...
        'Pamb',101325,'Tamb',288.15,'Mach',0, ...
        'Wf_model',cfg.engine.initial.Wf0, ...
        'Mkp',cfg.engine.initial.Mkp,'Mkg',cfg.engine.initial.Mkg, ...
        'Np_initial',cfg.engine.initial.Np0, ...
        'Ng_initial',cfg.engine.initial.Ng0);
    if loaded.result.options.modelMode==0
        modelInput.inletBoundaryMode=1;modelInput.Pt1=101325;modelInput.Tt1=288.15;
    end
end

session.notify(struct('phase','steady_prediction','status','running','message','按输入边界求稳态平衡；不读取目标测量输出。'));
result = sht_steady_model_adapt_v2_common( ...
    'predictsavedschedule',loaded.result,modelInput);
result.program = mfilename;
result.estimationResultFile = estimationResultFile;
result.sourceGenerationIdentity=generation;
result.executionIdentity=execution;
result.usedDefaultDesignInput = usedDefaultDesignInput;
result.posteriorPredictionPerformed = posteriorPredictionRequested;
if posteriorPredictionRequested
    if isfield(posteriorOptions,'workbookFile')
        result.posteriorCompatibility=sht_tc24_posterior_match( ...
            posteriorOptions.workbookFile,generation,execution);
        result.posteriorPrediction=sht_predict_2p4_uq_excel( ...
            loaded.result,result,posteriorOptions);
    elseif strcmpi(extension,'.mat')
        result.posteriorPrediction = sht_steady_model_predict_posterior( ...
            loaded.result, estimationResultFile, result, posteriorOptions);
    else
        error('SHT:SteadyPrediction:MissingPosteriorWorkbook', ...
            '正式Excel预测请显式提供posteriorOptions.workbookFile；method/runId仅供内部MAT回归。');
    end
else
    result.posteriorPrediction = struct();
end
result.status = 'completed';
if ~result.passed,result.status='completed_diagnostic';end
result.executionOptions=executionOptions;
if isfield(result.executionOptions,'progressCallback'),result.executionOptions.progressCallback=[];end
assert(strcmp(generation.fileSha256, ...
    sht_steady_model_uq_common('filehash',estimationResultFile)), ...
    'SHT:SteadyPrediction:SourceChanged','预测过程中上游结果文件发生变化。');
result.outputsWritten=logical(local_option(executionOptions,'writeOutputs',true));
if ~result.outputsWritten
    result.output=struct();
    result.execution=session.finish(result.status,'prediction_finished',[],'in_memory');
    fprintf('输入驱动预测：执行包%s；历史run=%s；不写预测输出。\n', ...
        execution.runtimeDirectory,generation.runId);
    return;
end

stamp = datestr(now,'yyyymmdd_HHMMSS');
latestFile = fullfile(paths.middleDataDir, ...
    'steady_model_input_prediction_latest.mat');
excelFile = fullfile(paths.reportOutputDir, ...
    ['steady_model_input_prediction_' stamp '.xlsx']);
summaryFile = fullfile(paths.reportOutputDir, ...
    ['steady_model_input_prediction_' stamp '_summary.md']);
posteriorFigureFile = '';
if posteriorPredictionRequested
    posteriorFigureFile = fullfile(paths.reportOutputDir, ...
        ['steady_model_input_prediction_' stamp ...
        '_posterior_intervals.png']);
end
if exist(excelFile,'file') == 2
    delete(excelFile);
end
writetable(result.predictionTable,excelFile,'Sheet','prediction');
if posteriorPredictionRequested
    writetable(result.posteriorPrediction.intervalTable, excelFile, ...
        'Sheet', 'posterior_intervals');
    if local_option(executionOptions,'plotEnabled',true)
        try,local_plot_posterior_intervals(result.posteriorPrediction.intervalTable,posteriorFigureFile);
        catch e,warning('SHT:SteadyPrediction:OptionalPlot','绘图失败但预测结果保留：%s',e.message);end
    else
        posteriorFigureFile='';
    end
end
result.output = struct('latestMatFile',latestFile, ...
    'excelFile',excelFile,'summaryFile',summaryFile, ...
    'posteriorFigureFile',posteriorFigureFile);
local_write_summary(summaryFile,result);
result.execution=session.snapshot(result.status,'prediction_finished');
% 新独立目录中MAT位于MiddleData子目录，最终执行记录以相对引用支持搬迁。
recordFile='';
if explicitOutput
    result.execution.recordRelativePath=fullfile('..','execution.json');
else
    result.execution.recordRelativePath='steady_model_input_prediction_execution.json';
    recordFile=fullfile(paths.middleDataDir,result.execution.recordRelativePath);
end
save(latestFile,'result','-v7.3');
result.execution=session.finish(result.status,'prediction_finished',result.execution,'saved_outputs',recordFile);
if ~explicitOutput,assignin('base','SteadyModelInputPredictionResult',result);end

fprintf('\n=== 输入驱动稳态预测完成 ===\n');
fprintf('预测点：%d；使用设计点缺省输入：%d；全部有效：%d。\n', ...
    height(result.predictionTable),usedDefaultDesignInput,result.passed);
fprintf('进口模式：%d；控制闭环：0；测量输出：0；参数真值：0。\n', ...
    result.inputContract.inletBoundaryMode);
fprintf('Np分支使用目标Np：%d；训练工况分支先验：%d。\n', ...
    result.targetNpUsedForBranchSelection, ...
    result.trainingMeasurementDataUsedForBranchPrior);
disp(result.predictionTable);
if posteriorPredictionRequested
    fprintf(['后验传播：方法%s，run=%s，有效后验质量=%.3f，' ...
        '区间验收=%d。\n'],result.posteriorPrediction.method, ...
        result.posteriorPrediction.runId, ...
        result.posteriorPrediction.validPosteriorMass, ...
        result.posteriorPrediction.passed);
    disp(result.posteriorPrediction.intervalTable);
end
fprintf('结果：\n  %s\n  %s\n  %s\n',latestFile,excelFile,summaryFile);
if posteriorPredictionRequested
    fprintf('  %s\n',posteriorFigureFile);
end
catch err
    session.finish('failed',[err.identifier,': ',err.message]);rethrow(err);
end
end

function local_write_summary(filePath,result)
fid = fopen(filePath,'w','n','UTF-8');
if fid < 0
    error('SHT:SteadyPrediction:SummaryOpenFailure', ...
        '无法写入预测摘要：%s。',filePath);
end
cleanupObject = onCleanup(@() fclose(fid));
fprintf(fid,'# 输入驱动稳态预测摘要\n\n');
fprintf(fid,'- 冻结辨识结果：`%s`\n',result.estimationResultFile);
fprintf(fid,'- 历史生成run：`%s`；源文件SHA256：`%s`\n', ...
    result.sourceGenerationIdentity.runId,result.sourceGenerationIdentity.fileSha256);
fprintf(fid,'- 本次执行选择：`%s`；运行目录：`%s`\n', ...
    result.executionIdentity.selection,result.executionIdentity.runtimeDirectory);
for i=1:numel(result.executionIdentity.artifacts)
    a=result.executionIdentity.artifacts(i);
    fprintf(fid,'- 执行资产 `%s`：`%s`\n',a.file,a.sha256);
end
fprintf(fid,'- 历史生成身份未改写；本次预测不重签旧Excel或旧后验。\n');
fprintf(fid,'- 预测点数：%d\n',height(result.predictionTable));
fprintf(fid,'- 使用设计点缺省输入：%d\n',result.usedDefaultDesignInput);
fprintf(fid,'- 进口边界模式：%d\n',result.inputContract.inletBoundaryMode);
fprintf(fid,'- 高度参与环境反算：%d\n', ...
    result.inputContract.altitudeUsedForAtmosphere);
fprintf(fid,'- 控制闭环参与：%d\n',result.inputContract.controlLoopUsed);
fprintf(fid,'- 目标工况测量输出参与：%d\n', ...
    result.targetMeasurementDataUsed);
fprintf(fid,'- 原辨识训练数据用于Np分支先验：%d\n', ...
    result.trainingMeasurementDataUsedForBranchPrior);
fprintf(fid,'- 目标Np用于分支选择/负载功率：%d / %d\n', ...
    result.targetNpUsedForBranchSelection, ...
    result.targetNpUsedForLoadPower);
fprintf(fid,'- 参数真值被读取：%d\n',result.truthWasRead);
fprintf(fid,'- 全部预测有效：%d\n',result.passed);
fprintf(fid,'- 执行后验传播：%d\n',result.posteriorPredictionPerformed);
if result.posteriorPredictionPerformed
    posterior = result.posteriorPrediction;
    fprintf(fid,'- 后验方法：%s\n',posterior.method);
    fprintf(fid,'- 后验运行：`%s`\n',posterior.runId);
    fprintf(fid,'- 正式粒子数：%d\n',posterior.sourcePosteriorParticleCount);
    fprintf(fid,'- 唯一粒子数：%d\n',posterior.uniquePosteriorParticleCount);
    fprintf(fid,'- 有效后验质量：%.6f\n',posterior.validPosteriorMass);
    fprintf(fid,'- 模型输入不确定性传播：%d\n', ...
        posterior.inputUncertaintyPropagated);
    fprintf(fid,'- 后验区间验收：%d\n',posterior.passed);
    fprintf(fid,'- 后验传播耗时：%.3f s\n',posterior.runtime_s);
    if isfield(posterior,'scope')
        fprintf(fid,'- 传播范围：`%s`。这是条件模型输出区间，不是独立再测量区间。\n',posterior.scope);
    end
    if isfield(posterior,'marginalizedNuisancePropagated')
        fprintf(fid,'- 已边缘化附加参数的条件不确定性已传播：%d\n', ...
            posterior.marginalizedNuisancePropagated);
    end
    fprintf(fid,'- 后验区间图：`%s`\n', ...
        result.output.posteriorFigureFile);
end
clear cleanupObject;
end

function [model,execution]=local_select_runtime(model,manifest,options)
% 按Excel的TC24字典声明识别业务合同，不仅凭modelMode=0切换其他模型。
selection=char(local_option(options,'runtimeSelection','auto'));
assert(ismember(selection,{'auto','model_default','tc24_selected'}), ...
    'SHT:SteadyPrediction:RuntimeSelection','未知运行包选择。');
directory=char(local_option(options,'runtimeDirectory',''));
isTc24=~isempty(manifest) && ...
    ismember('parameter_dictionary_id',manifest.Properties.VariableNames) && ...
    strcmp(string(manifest.parameter_dictionary_id(1)), ...
    "TC24_11_ESTIMATED_HEALTH_PLUS_WF_BIAS_V1") && model.options.modelMode==0;
execution=struct('selection',selection,'packageId','', ...
    'tc24ContractDetected',isTc24);
if ~isempty(directory)
    assert(strcmp(selection,'auto'),'SHT:SteadyPrediction:RuntimeConflict', ...
        '显式runtimeDirectory不能与非auto的runtimeSelection同时指定。');
    [ok,attribute]=fileattrib(directory);
    assert(ok && isscalar(attribute) && attribute.directory, ...
        'SHT:SteadyPrediction:RuntimeMissing','显式运行目录不存在。');
    model.options.runtimeDirectory=char(java.io.File(attribute.Name).getCanonicalPath());
    execution.selection='explicit_directory';
elseif strcmp(selection,'tc24_selected') || (strcmp(selection,'auto') && isTc24)
    assert(model.options.modelMode==0,'SHT:SteadyPrediction:RuntimeMode', ...
        'TC24运行包仅用于明确的三部件模型。');
    package=sht_tc24_runtime_package();
    model.options.runtimeDirectory=package.directory;
    execution.selection='tc24_selected';execution.packageId=package.id;
else
    execution.selection='model_default';
end
end

function value=local_option(options,name,fallback)
if isfield(options,name),value=options.(name);else,value=fallback;end
end

function local_plot_posterior_intervals(tbl, filePath)
names = unique(tbl.output_name, 'stable');
figureHandle = figure('Visible','off','Color','w', ...
    'Name','任意输入工况后验预测区间', ...
    'Position',[80,80,1380,820]);
layout = tiledlayout(ceil(numel(names)/3),3,'TileSpacing','compact','Padding','compact');
modelColor = [0.13,0.45,0.70];
observableColor = [0.90,0.45,0.12];
medianColor = [0.00,0.25,0.52];
frozenColor = [0.15,0.15,0.15];
for i = 1:numel(names)
    ax = nexttile(layout);
    use = tbl.output_name == names(i);
    current = tbl(use,:);
    x = (1:height(current)).';
    hold(ax,'on');
    % 四项结果采用独立横向位置，单工况时也不会相互遮挡。
    modelX = x - 0.24;
    observableX = x + 0.24;
    medianX = x - 0.07;
    frozenX = x + 0.07;
    hModel = local_interval_bar(ax,modelX,current.model_lower, ...
        current.model_upper,modelColor);
    hasObservable=any(isfinite(current.observable_lower));
    if hasObservable
        hObservable = local_interval_bar(ax,observableX, ...
            current.observable_lower,current.observable_upper,observableColor);
    end
    hMedian = plot(ax,medianX,current.model_median,'d', ...
        'LineStyle','none','Color',medianColor, ...
        'MarkerFaceColor',medianColor,'MarkerSize',7,'LineWidth',1.2);
    hFrozen = plot(ax,frozenX,current.deterministic_frozen_model,'x', ...
        'LineStyle','none','Color',frozenColor, ...
        'MarkerSize',9,'LineWidth',1.8);
    hold(ax,'off');
    grid(ax,'on');
    title(ax,char(names(i)),'Interpreter','none');
    xlabel(ax,'预测工况');
    ylabel(ax,char(current.unit(1)),'Interpreter','none');
    xticks(ax,x);
    xticklabels(ax,cellstr(current.point_id));
    ax.TickLabelInterpreter = 'none';
    xlim(ax,[0.55,height(current)+0.45]);
    if i == 1
        if hasObservable
            legend(ax,[hModel,hObservable,hMedian,hFrozen], ...
                {'模型输出95%区间','可观测量95%区间','后验中位数', ...
                '冻结个体模型'},'Location','best');
        else
            legend(ax,[hModel,hMedian,hFrozen], ...
                {'参数条件模型输出95%区间','后验中位数','冻结个体模型'},'Location','best');
        end
    end
end
title(layout,'任意指定工况的后验预测区间');
sht_export_figure(figureHandle,filePath,'Resolution',160);
close(figureHandle);
end

function handle = local_interval_bar(ax,x,lower,upper,color)
center = 0.5*(lower+upper);
handle = errorbar(ax,x,center,center-lower,upper-center, ...
    'LineStyle','none','Marker','none','Color',color, ...
    'LineWidth',2.2,'CapSize',12);
end
