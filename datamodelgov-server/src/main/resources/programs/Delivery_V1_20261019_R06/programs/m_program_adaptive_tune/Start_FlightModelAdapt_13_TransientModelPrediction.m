function replay=Start_FlightModelAdapt_13_TransientModelPrediction(deliveryFile,measurementFile,options)
% 用正式瞬态Excel、其绑定稳态Excel和公共运行包独立预测，不读取辨识MAT。
% 输入是真实可测历程。Np/Ng仅首点初始化使用，其后两轴状态自行积分；
% Pt3_eq/Tt45仅用于误差报告，不反馈到发动机。原始测量Excel用sheet='Data'。
% 新动作：capabilities/checkData/estimateData/runInput/read/compare。
% 动作配置见local_input_config；旧(deliveryFile,measurementFile,options)调用不变。
if (ischar(deliveryFile)||(isstring(deliveryFile)&&isscalar(deliveryFile)))&&ismember(lower(char(deliveryFile)), ...
        {'capabilities','checkdata','estimatedata','runinput','read','compare'})
    if nargin<2,measurementFile=struct();end
    replay=local_action(lower(char(deliveryFile)),measurementFile);return;
end
if nargin<3,options=struct();end
defaults=struct('sheet','Data','integrationStep_s',.1,'cacheDirectory','','outputRoot','', ...
    'plotEnabled',false,'inputMode','measured_record','initialState',struct(), ...
    'fuelDefinition','measured','parentRoute','transient_instant','parentRuntimeBinding',struct());
fields=fieldnames(options);assert(all(ismember(fields,fieldnames(defaults))),'未知预测配置。');
fields=fieldnames(defaults);for j=1:numel(fields),if ~isfield(options,fields{j}),options.(fields{j})=defaults.(fields{j});end,end
assert(~isempty(options.outputRoot),'F3:TransientPrediction:Output','必须明确独立新输出目录。');
assert(java.io.File(options.outputRoot).isAbsolute(),'预测输出须为绝对路径。');
assert(~isfolder(options.outputRoot)||numel(dir(options.outputRoot))<=2, ...
    'F3:TransientPrediction:Existing','预测目录必须为空，不覆盖已有结果。');
if isempty(options.cacheDirectory),options.cacheDirectory=fullfile(options.outputRoot,'physical_cache');end
assert(ismember(options.integrationStep_s,[.1,.025]),'积分步长只允许0.1/0.025秒。');
timer=tic;
binding={};
if ~isempty(fieldnames(options.parentRuntimeBinding))
    binding={struct('priorRoute',options.parentRoute,'priorRuntimeBinding',options.parentRuntimeBinding)};
end
selected=sht_f33_transient_delivery('inspect',[],deliveryFile,binding{:});
local_boundary_contract(selected.steady.metadata);
if istable(measurementFile),h=measurementFile;hash=sht_f33_model_adapt_v2('structHash',h);
else,h=readtable(measurementFile,'Sheet',options.sheet);hash=sht_tc27_file_identity(measurementFile);end
names={'sample_id','time_s','Ps0','Tt1','Pt3_eq','Ng','Np','Mkp','Wf','Tt45','Altitude','Mach','Ts_amb'};
inputOnly=strcmp(options.inputMode,'input_only');
if inputOnly,names={'time_s','Ps0','Tt1','Ts_amb','Altitude','Mach','Mkp','Wf'};end
assert(all(ismember(names,h.Properties.VariableNames)),'飞参测量列不完整。');h=h(:,names);
if inputOnly,h.sample_id=(1:height(h))';end
assert(all(isfinite(h{:,:}),'all')&&height(h)>=3,'预测需要完整有限测量记录。');
dt=median(diff(h.time_s));
assert(dt>0&&max(abs(diff(h.time_s)-dt))<1e-8&&numel(unique(h.sample_id))==height(h), ...
    '预测记录必须编号唯一、时间等间隔且无缺口。');
plan=table(h.time_s(end),h.time_s(1),0,height(h),'VariableNames', ...
    {'fit_end_s','initialization_start_s','warmup_s','fit_sample_count'});
estimate=sht_f3_runtime_estimate('transientReplay',plan,options);
fprintf('记录驱动预测预计 %.1f--%.1f min，Np/Ng仅首点初始化。\n',estimate.totalRange_s/60);
d=sht_f33_transient_delivery('read',[],deliveryFile,binding{:});
mkdir(options.outputRoot);
sensor=sht_f31_flight_measurement('publicAssumptions', ...
    sht_f31_flight_measurement('model',3201001,'F32-MEASUREMENT-PRIOR',false));
meta=d.steady.metadata;
ro=struct('integrationStep_s',options.integrationStep_s,'integrationMethod','euler2', ...
    'inletMeanRecovery',meta.mean_inlet_recovery-d.steady.KdistEq, ...
    'exhaustBackPressureDesignRise_Pa',meta.backpressure_design_Pa, ...
    'sourceSha256',hash,'cacheDirectory',options.cacheDirectory,'progressIntervalSamples',10000);
ro.inputMode=options.inputMode;ro.initialState=options.initialState;
ro.fuelDefinition=options.fuelDefinition;
replay=sht_f32_replay_history('run',h,d.assets,'personalized',sensor,ro);
assert(replay.computationallyAccepted,'F3:TransientPrediction:Invalid','独立预测存在未通过的物理状态。');
% 正式输出将物理量、传感器预期输出和测量严格分列，不导出虚构区间。
t=table(h.sample_id,replay.time_s,'VariableNames',{'sample_id','time_s'});
for j=1:4
    n=replay.outputNames{j};t.([n '_physical'])=replay.trueModelOutput(:,j);
    t.([n '_sensor'])=replay.sensorExpectedOutput(:,j);
    if ~inputOnly,t.([n '_measured'])=replay.measuredOutput(:,j);end
end
file=fullfile(options.outputRoot,'prediction.xlsx');writetable(t,file,'Sheet','History');
if ~isempty(replay.metrics),writetable(replay.metrics,file,'Sheet','Metrics');end
meta=table(string(sht_tc27_file_identity(deliveryFile)),string(hash), ...
    options.integrationStep_s,string('measured_first_Np_Ng_only_then_open_loop'), ...
    string('not_evaluated'),toc(timer),'VariableNames', ...
    {'model_sha256','data_sha256','integration_step_s','initialization','uq_status','active_seconds'});
writetable(meta,file,'Sheet','Manifest');
meta.input_mode=string(options.inputMode);meta.fuel_definition=string(options.fuelDefinition);
if inputOnly,meta.initialization="explicit_initial_speeds_then_open_loop";end
writetable(meta,file,'Sheet','Manifest');
replay.deliveryFile=file;replay.estimate=estimate;replay.endToEnd_s=toc(timer);
association=struct();
if isfield(d,'sourceSchema')
    association=d.metadata;replay.parentRuntimeAssociation=association;
    writetable(table(string(jsonencode(d.metadata)), ...
        'VariableNames',{'source_and_execution_json'}),file,'Sheet','RuntimeBinding');
end
fid=fopen(fullfile(options.outputRoot,'prediction_runtime.json'),'w','n','UTF-8');
assert(fid>=0);cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',jsonencode(struct('estimate',estimate,'actualSeconds',replay.endToEnd_s, ...
    'dllCalls',replay.executedEvaluationCount,'modelSha256',char(meta.model_sha256), ...
    'dataSha256',hash,'sourceSha256',sht_tc27_file_identity([mfilename('fullpath') '.m']), ...
    'predictionFile','prediction.xlsx','predictionSha256',sht_tc27_file_identity(file), ...
    'inputMode',options.inputMode,'initialState',options.initialState, ...
    'fuelDefinition',options.fuelDefinition,'intervalsAvailable',false, ...
    'parentRuntimeAssociation',association)));
if options.plotEnabled
    figure('Name','测量首点初始化的独立历程回放');
    for j=1:4
        subplot(2,2,j);
        if inputOnly,plot(replay.time_s,replay.sensorExpectedOutput(:,j));legend('预测测量');
        else,plot(replay.time_s,[replay.measuredOutput(:,j),replay.sensorExpectedOutput(:,j)]);legend('测量','预测测量');end
        title(replay.outputNames{j});
    end
end
end

function out=local_action(action,u)
% 只读动作在恢复资产之前返回，不能隐式执行物理初始化。
if strcmp(action,'capabilities')
    out=struct('schema','F3_INPUT_HISTORY_CAPABILITIES_B23','noDll',true, ...
        'inputColumns',{{'time_s','Ps0','Tt1','Ts_amb','Altitude','Mach','Mkp','Wf'}}, ...
        'requiredInitialFields',{{'Np0','Ng0','thermalStrategy'}}, ...
        'thermalStrategies',{{'equilibrium','explicit'}},'thermalStateCount',14, ...
        'fuelDefinitions',{{'measured','physical'}},'intervalsAvailable',false, ...
        'implementationStatus','candidate_source_pending_runtime_verification');return;
end
if ismember(action,{'read','compare'})
    assert(isfield(u,'resultDirectory'),'F3:TransientPrediction:Directory','须给resultDirectory。');
    root=char(java.io.File(u.resultDirectory).getCanonicalPath());
    log=jsondecode(fileread(fullfile(root,'prediction_runtime.json')));
    file=fullfile(root,'prediction.xlsx');
    assert(isfield(log,'predictionSha256')&&strcmpi(sht_tc27_file_identity(file),log.predictionSha256), ...
        'F3:TransientPrediction:Identity','保存预测Excel身份不符或旧结果缺少只读身份。');
    out=struct('history',readtable(file,'Sheet','History'),'manifest',readtable(file,'Sheet','Manifest'), ...
        'runtime',log,'metrics',table(),'noDll',true,'intervalsAvailable',false);
    [~,sheets]=xlsfinfo(file);
    if ismember('Metrics',sheets),out.metrics=readtable(file,'Sheet','Metrics');end
    if strcmp(action,'compare')
        assert(isfield(u,'observationFile'),'F3:TransientPrediction:Observation','须明确补充观测文件。');
        y=readtable(u.observationFile,'Sheet','Data');names={'Np','Ng','Pt3_eq','Tt45'};
        assert(all(ismember([{'time_s'},names],y.Properties.VariableNames))&& ...
            height(y)==height(out.history)&&all(abs(y.time_s-out.history.time_s)<1e-8), ...
            'F3:TransientPrediction:ObservationGrid','补充观测必须与已保存预测时间逐点一致。');
        rmse=zeros(4,1);bias=rmse;
        for j=1:4
            v=y.(names{j});assert(isnumeric(v)&&all(isfinite(v)),'补充观测非有限。');
            e=out.history.([names{j} '_sensor'])-v;rmse(j)=sqrt(mean(e.^2));bias(j)=mean(e);
        end
        out.metrics=table(string(names(:)),rmse,bias,'VariableNames',{'channel','RMSE','mean_error'});
        out.observationSha256=sht_tc27_file_identity(u.observationFile);
        out.comparisonOnly=true;out.modelRecomputed=false;
    end
    return;
end
c=local_input_config(u);
if istable(c.inputFile),h=c.inputFile;dataSha=sht_f33_model_adapt_v2('structHash',h);
else,h=readtable(c.inputFile,'Sheet',c.sheet);dataSha=sht_tc27_file_identity(c.inputFile);end
names={'time_s','Ps0','Tt1','Ts_amb','Altitude','Mach','Mkp','Wf'};
assert(all(ismember(names,h.Properties.VariableNames)),'F3:TransientPrediction:Inputs','缺少八个输入通道。');
h=h(:,names);values=h{:,:};dt=median(diff(h.time_s));
assert(isnumeric(values)&&height(h)>=3&&all(isfinite(values(:)))&&dt>0&& ...
    max(abs(diff(h.time_s)-dt))<1e-8,'F3:TransientPrediction:Inputs','输入须完整、有限、时间等间隔。');
assert(all(h.Ps0>0&h.Tt1>0&h.Ts_amb>0&h.Wf>0&h.Mach>=0), ...
    'F3:TransientPrediction:InputRange','静压、绝对温度、燃油或马赫数超出物理范围。');
ratio=round(dt/c.integrationStep_s);
assert(ratio>=1&&abs(dt-ratio*c.integrationStep_s)<1e-9, ...
    'F3:TransientPrediction:Grid','积分步长必须整除记录间隔。');
binding={};
if ~isempty(fieldnames(c.parentRuntimeBinding))
    binding={struct('priorRoute',c.parentRoute,'priorRuntimeBinding',c.parentRuntimeBinding)};
end
d=sht_f33_transient_delivery('inspect',[],c.modelWorkbook,binding{:});
local_boundary_contract(d.steady.metadata);
out=struct('configuration',c,'recordCount',height(h),'recordStep_s',dt, ...
    'modelSha256',d.sha256,'steadySha256',d.steadySha256,'dataSha256',dataSha, ...
    'fixedTransient',d.fixedTransient,'noDll',true,'measuredOutputsRequired',false);
plan=table(h.time_s(end),h.time_s(1),0,height(h),'VariableNames', ...
    {'fit_end_s','initialization_start_s','warmup_s','fit_sample_count'});
out.estimate=sht_f3_runtime_estimate('transientReplay',plan,c);
if ismember(action,{'checkdata','estimatedata'}),return;end
o=rmfield(c,{'modelWorkbook','inputFile'});o.inputMode='input_only';
out=Start_FlightModelAdapt_13_TransientModelPrediction(c.modelWorkbook,c.inputFile,o);
end

function local_boundary_contract(m)
% 当前物理包采用固定设计功率和边界模型；不允许把别的父边界悄悄替换为默认。
assert(all(abs([m.mean_inlet_recovery-.995,m.backpressure_design_Pa-1500, ...
    m.design_power_W-2176600])<1e-10),'F3:TransientPrediction:ParentBoundary', ...
    '所选父模型的入口恢复、设计背压或功率与当前F3物理包不一致。');
end

function c=local_input_config(u)
c=struct('modelWorkbook','','inputFile','','sheet','Data','integrationStep_s',.1, ...
    'cacheDirectory','','outputRoot','','plotEnabled',false,'fuelDefinition','measured','initialState',struct(), ...
    'parentRoute','transient_instant','parentRuntimeBinding',struct());
assert(isstruct(u)&&isscalar(u)&&all(ismember(fieldnames(u),fieldnames(c))), ...
    'F3:TransientPrediction:Option','输入-only配置含未知字段。');
for f=fieldnames(u)',c.(f{1})=u.(f{1});end
% 新输入预测的所有写入收在同一明确新根，防止只改run标签却覆盖历史缓存。
assert(~isempty(c.outputRoot)&&java.io.File(c.outputRoot).isAbsolute(), ...
    'F3:TransientPrediction:Output','输入预测必须给独立绝对输出目录。');
c.outputRoot=char(java.io.File(c.outputRoot).getCanonicalPath());
if isempty(c.cacheDirectory),c.cacheDirectory=fullfile(c.outputRoot,'physical_cache');end
c.cacheDirectory=char(java.io.File(c.cacheDirectory).getCanonicalPath());
assert(startsWith(lower(c.cacheDirectory),lower([c.outputRoot,filesep])), ...
    'F3:TransientPrediction:CacheRoot','新预测缓存必须位于本次输出根内部。');
assert(isfile(c.modelWorkbook)&&(istable(c.inputFile)||isfile(c.inputFile)), ...
    'F3:TransientPrediction:InputFile','须明确组合模型Excel与输入记录。');
for source={c.modelWorkbook,c.inputFile}
    if istable(source{1}),continue;end
    path=char(java.io.File(source{1}).getCanonicalPath());
    assert(~startsWith(lower(path),lower([c.outputRoot,filesep])), ...
        'F3:TransientPrediction:Output','新输出目录不能包含所选源文件。');
end
assert(ismember(c.integrationStep_s,[.1,.025])&&ismember(c.fuelDefinition,{'measured','physical'}), ...
    'F3:TransientPrediction:Option','积分步长或燃油定义不支持。');
s=c.initialState;
assert(isstruct(s)&&isscalar(s)&&all(isfield(s,{'Np0','Ng0','thermalStrategy'})), ...
    'F3:TransientPrediction:InitialState','必须明确两轴初始转速和热初始化策略。');
validateattributes([s.Np0,s.Ng0],{'numeric'},{'finite','real','positive','numel',2});
assert(ismember(s.thermalStrategy,{'explicit','equilibrium'}),'热策略无效。');
if strcmp(s.thermalStrategy,'explicit')
    assert(isfield(s,'temperature_K'),'须明确14个热状态。');
    validateattributes(s.temperature_K,{'numeric'},{'finite','real','positive','numel',14});
end
if isfield(s,'sensorState'),validateattributes(s.sensorState,{'numeric'},{'finite','real','numel',4});end
if isfield(s,'commonWorkingSeed'),validateattributes(s.commonWorkingSeed,{'numeric'},{'finite','real','numel',6});end
end
