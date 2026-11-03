function out=sht_f3_transient_task(action,user,selection)
% 过渡态飞参业务薄层：数据/事件/身份/安全控制，不另实现求解器。
% check、preview、confirm、estimate均不打开DLL；preview不写文件。
% confirm冻结大事件及实际有限前史；仅run/resume/validate启动物理计算。
if nargin<2,user=struct();end
if nargin<3,selection=struct();end
action=lower(char(action));
switch action
    case 'config',out=local_config();return;
    case {'read','status','requestpause'}
        root=local_path(user.resultDirectory);
        if strcmp(action,'read'),out=local_read(root);return;end
        if strcmp(action,'requestpause')
            if ~isfile(fullfile(root,'run_control','identity.mat'))
                out=struct('status','not_running','safeStopConfirmed',false, ...
                    'message','尚未开始物理计算，无需暂停。');return;
            end
            out=sht_tc24_run_control('requeststop',root);return;
        end
        out=local_json_read(fullfile(root,'task_status.json'));
        if isfile(fullfile(root,'run_control','state.mat'))
            out.control=sht_tc24_run_control('state',root);
            out.status=out.control.status;
            out.safeStopConfirmed=strcmp(out.status,'stopped');
        end
        out.processLivenessChecked=false;return;
    case 'validate',out=local_validate(user);return;
end
assert(ismember(action,{'check','preview','confirm','estimate','run','resume'}), ...
    'F3:TF:Action','未知任务动作：%s。',action);
cfg=local_config(user);check=local_check(cfg);
if strcmp(action,'check'),out=check;return;end
if strcmp(action,'preview')
    out=local_preview(cfg,check);return;
end
confirmation=fullfile(cfg.outputRoot,'confirmation.mat');
if strcmp(action,'confirm')
    assert(~isfile(confirmation),'F3:TF:Existing','确认已冻结；更改数据/选择请使用新目录。');
    out=local_preview(cfg,check,selection);
    assert(height(out.plan)>0,'F3:TF:NoEvents','没有已选择且有效的大幅事件，不回退全历程。');
    local_assert_empty(cfg.outputRoot);local_assert_empty(cfg.reportRoot);
    local_new_root(cfg.outputRoot);local_new_root(cfg.reportRoot);
    out.confirmationIdentity=local_hash(struct('input',check.identity,'events',table2struct(out.events), ...
        'windows',table2struct(out.windows),'plan',table2struct(out.plan)));
    task=out;save(confirmation,'task','-v7.3');
    local_json(fullfile(cfg.outputRoot,'configuration.json'),cfg);
    writetable(out.events,fullfile(cfg.outputRoot,'confirmed_data.xlsx'),'Sheet','events');
    writetable(out.windows,fullfile(cfg.outputRoot,'confirmed_data.xlsx'),'Sheet','transient_windows');
    writetable(check.history,fullfile(cfg.outputRoot,'confirmed_data.xlsx'),'Sheet','history');
    writetable(out.segmentation.segments,fullfile(cfg.outputRoot,'confirmed_data.xlsx'),'Sheet','segments');
    writetable(out.plan,fullfile(cfg.outputRoot,'confirmed_data.xlsx'),'Sheet','actual_local_plan');
    task.confirmedDataSha256=sht_tc27_file_identity(fullfile(cfg.outputRoot,'confirmed_data.xlsx'));
    save(confirmation,'task','-v7.3');out=task;
    local_json(fullfile(cfg.outputRoot,'task_status.json'),struct('status','confirmed', ...
        'runId',cfg.runId,'identity',out.confirmationIdentity,'resultAvailable',false));
    return;
end
assert(isfile(confirmation),'F3:TF:NotConfirmed','请先preview并confirm本任务事件。');
z=load(confirmation,'task');task=z.task;
assert(strcmp(task.check.identity,check.identity),'F3:TF:Stale', ...
    '数据、父模型、配置、源码或物理包已变化；旧确认/检查点不可续用，请使用全新目录。');
assert(strcmp(task.confirmationIdentity,local_hash(struct('input',check.identity, ...
    'events',table2struct(task.events),'windows',table2struct(task.windows),'plan',table2struct(task.plan))))&& ...
    strcmpi(task.confirmedDataSha256,sht_tc27_file_identity(fullfile(cfg.outputRoot,'confirmed_data.xlsx'))), ...
    'F3:TF:Stale','已确认的选段或计算数据改变，禁止恢复。');
estimate=sht_f3_runtime_estimate('transient',task.plan,cfg.solver);
if strcmp(action,'estimate'),out=estimate;return;end
out=local_run(cfg,task,estimate,strcmp(action,'resume'));
end

function cfg=local_config(user)
cfg=struct('runId','','modelId','','trainingFile','','testFile','','parentWorkbook','', ...
    'trainingSheet','Data','testSheet','Data','outputRoot','','reportRoot','', ...
    'businessIdentity',struct(),'channelMap',struct(),'segmentation',struct(), ...
    'eventOptions',struct(),'solver',struct(),'plotEnabled',false);
if nargin==0,return;end
assert(isstruct(user)&&isscalar(user)&&all(ismember(fieldnames(user),fieldnames(cfg))), ...
    'F3:TF:Config','未知任务配置字段。');
for f=fieldnames(user).',cfg.(f{1})=user.(f{1});end
for f={'runId','modelId'}
    v=cfg.(f{1});assert(ischar(v)&&~isempty(strtrim(v)),'F3:TF:Identity','必须明确%s。',f{1});
end
assert(~isempty(regexp(cfg.runId,'^[A-Za-z0-9_]+$','once')),'runId仅字母数字下划线。');
for f={'trainingFile','parentWorkbook','outputRoot','reportRoot'}
    cfg.(f{1})=local_path(cfg.(f{1}));
end
if ~isempty(cfg.testFile),cfg.testFile=local_path(cfg.testFile);end
assert(~strcmpi(cfg.outputRoot,cfg.reportRoot),'业务输出和报告目录不能相同。');
assert(~startsWith(lower(cfg.outputRoot),lower([cfg.reportRoot filesep]))&& ...
    ~startsWith(lower(cfg.reportRoot),lower([cfg.outputRoot filesep])), ...
    'F3:TF:Path','输出目录与报告目录不能互相包含。');
for f={'trainingFile','testFile','parentWorkbook'}
    p=cfg.(f{1});if isempty(p),continue;end
    assert(isfile(p),'F3:TF:Missing','文件不存在：%s。',p);
    assert(~startsWith(lower(p),lower([cfg.outputRoot filesep]))&& ...
        ~startsWith(lower(p),lower([cfg.reportRoot filesep])), ...
        'F3:TF:Path','输入不能位于本轮输出目录内。');
end
% 只让调用者配置算法本身，不允许借solver注入旧目录、旧文件或活跃指针。
allowed={'integrationStep_s','warmup_s','lambda','maximumIterations','parameterScale', ...
    'lowerBound','upperBound','initial','differenceStep','gradientTolerance', ...
    'stepTolerance','objectiveTolerance','objectiveImprovementTolerance','historyScale'};
assert(all(ismember(fieldnames(cfg.solver),allowed)),'F3:TF:Solver','未知数值配置。');
o=sht_f33_transient_identification('options',cfg.solver);
cfg.solver=struct();for f=allowed,cfg.solver.(f{1})=o.(f{1});end
assert(islogical(cfg.plotEnabled)&&isscalar(cfg.plotEnabled),'plotEnabled必须为逻辑值。');
end

function c=local_check(cfg)
% 不构造运行上下文；仅核文件与数值合同，绝不loadlibrary。
parent=sht_f33_excel_delivery('inspect',cfg.parentWorkbook);
m=parent.metadata;
assert(all(ismember({'mean_inlet_recovery','backpressure_design_Pa','design_power_W'},m.Properties.VariableNames)), ...
    'F3:TF:Boundary','父模型缺少入口恢复/背压/设计功率。');
assert(isfinite(m.mean_inlet_recovery)&&m.mean_inlet_recovery>parent.KdistEq&&m.mean_inlet_recovery<=1&& ...
    isfinite(m.backpressure_design_Pa)&&m.backpressure_design_Pa>=0&& ...
    isfinite(m.design_power_W)&&m.design_power_W>0,'F3:TF:Boundary','父边界非法。');
runtime=sht_f3_current_contract('runtimeidentity');
names=[string(runtime.contract.runtimeFiles(:));"VisserAsset"];
sha=[string(runtime.contract.runtimeHashes(:));string(runtime.contract.runtimeVisserAssetSha256)];
assert(isequal(string(parent.runtime.asset),names),'F3:TF:Runtime','父模型物理资产字典不一致。');
parent.runtimeAssociation=sht_f3_three_component_assets('association', ...
    parent.runtime.asset,parent.runtime.sha256);
assert(all(strcmpi(string(parent.runtimeAssociation.executionHashes),sha)), ...
    'F3:TF:Runtime','父模型未明确关联到所选执行包。');
% 当前回放的功率归一化来自隔离配置；不同功率不能静默套用。
assert(abs(m.design_power_W-2176600)<1e-6,'F3:TF:Boundary', ...
    '本运行包只验证设计功率2176600W；父模型为%.12gW，不静默覆盖。',m.design_power_W);
h=local_history(cfg.trainingFile,cfg.trainingSheet,cfg.channelMap);
test=[];testHash='';
if ~isempty(cfg.testFile)
    test=local_history(cfg.testFile,cfg.testSheet,cfg.channelMap);
    testHash=sht_tc27_file_identity(cfg.testFile);
    assert(~strcmpi(testHash,sht_tc27_file_identity(cfg.trainingFile))&&~isequaln(h,test), ...
        'F3:TF:TestNotIndependent','测试与训练相同，不能声称独立验证。');
end
business=local_business(cfg);
source=local_sources();
identity=struct('schema','F3_TRANSIENT_TASK_R002','configuration',cfg, ...
    'training',sht_tc27_file_identity(cfg.trainingFile),'test',testHash, ...
    'parent',sht_tc27_file_identity(cfg.parentWorkbook),'runtime',runtime.contract, ...
    'source',source,'business',business,'matlabRelease',version('-release'));
c=struct('identity',local_hash(identity),'contract',identity,'parent',parent, ...
    'history',h,'testHistory',test,'business',business,'source',source, ...
    'physicalCalculationExecuted',false,'testStatus','not_provided');
if ~isempty(test),c.testStatus='provided_not_evaluated';end
end

function b=local_business(cfg)
% 此任务无后验，不要求凭空填写parentPosteriorId。复用已有Excel取证读取器。
b=cfg.businessIdentity;required={'engineId','sortieId','parentModelId','basis','purpose'};
assert(isstruct(b)&&isscalar(b)&&all(isfield(b,required)), ...
    'F3:TF:Business','businessIdentity须给engineId/sortieId/parentModelId/basis/purpose。');
assert(ismember(b.purpose,{'production','test_fixture'}),'业务用途无效。');
if strcmp(b.purpose,'production')
    assert(~startsWith(upper(cfg.modelId),'TEST_FIXTURE')&& ...
        ~ismember(cfg.modelId,{'SHT_PERSONALIZED_ENGINE_001','F31-CAL-01'}), ...
        'F3:TF:Business','开发标签不能用作生产模型编号。');
end
e=sht_f3_business_identity('workbook',cfg.parentWorkbook);
t=sht_f3_business_identity('workbook',cfg.trainingFile);
fields={'engineId','sortieId','parentModelId'};aliases={'engine_id','sortie_id','model_id'};
for j=1:3
    f=fields{j};v=b.(f);
    assert(ischar(v)&&~isempty(strtrim(v)),'F3:TF:Business','缺少%s。',f);
    found=false;
    if j~=2&&isfield(e,aliases{j})
        assert(strcmp(v,e.(aliases{j})),'F3:TF:BusinessConflict','父模型%s冲突。',f);found=true;
    end
    if j<3&&isfield(t,aliases{j})
        assert(strcmp(v,t.(aliases{j})),'F3:TF:BusinessConflict','训练文件%s冲突。',f);found=true;
    end
    if ~found
        assert(isfield(b.basis,f)&&ischar(b.basis.(f))&&~isempty(strtrim(b.basis.(f))), ...
            'F3:TF:BusinessBasis','所选证据缺少%s，必须显式记录编号依据。',f);
    end
    if strcmp(b.purpose,'production')
        assert(~startsWith(upper(v),'TEST_FIXTURE')&& ...
            ~ismember(v,{'SHT_PERSONALIZED_ENGINE_001','F31-CAL-01'}), ...
            'F3:TF:Business','开发标签不能用作生产编号。');
    end
end
b.modelId=cfg.modelId;b.parentSha256=sht_tc27_file_identity(cfg.parentWorkbook);
b.trainingSha256=sht_tc27_file_identity(cfg.trainingFile);
b.fuelPolicy='fixed_selected_sortie_parent_bias_subtracted_once';
end

function h=local_history(file,sheet,mapping)
h=readtable(file,'Sheet',sheet,'PreserveVariableNames',true);
names={'sample_id','time_s','Ps0','Tt1','Pt3_eq','Ng','Np','Mkp','Wf','Tt45','Altitude','Mach','Ts_amb'};
assert(all(ismember(fieldnames(mapping),names)),'未知通道映射目标。');
% 同时映射必须从原表取值，不能让先写入的目标覆盖后续映射源。
original=h;
for f=fieldnames(mapping).'
    src=char(mapping.(f{1}));assert(ismember(src,original.Properties.VariableNames),'映射源字段不存在：%s。',src);
    h.(f{1})=original.(src);
end
assert(all(ismember(names,h.Properties.VariableNames)),'F3:TF:Columns','飞参必须提供正式13列，不能补造输出。');
h=h(:,names);
for f=names,assert(isnumeric(h.(f{1}))&&all(isfinite(h.(f{1}))), ...
    'F3:TF:MissingValues','%s缺测/非数值，当前不跨缺测插值。',f{1});end
assert(height(h)>=3&&numel(unique(h.sample_id))==height(h)&&all(diff(h.sample_id)>0), ...
    'F3:TF:Records','记录编号须唯一递增且至少3条。');
dt=median(diff(h.time_s));
assert(dt>0&&max(abs(diff(h.time_s)-dt))<1e-8,'F3:TF:Cadence','时间必须连续等间隔，无重复/缺口。');
assert(all(h.Ps0>0&h.Tt1>0&h.Pt3_eq>0&h.Np>0&h.Ng>0&h.Wf>=0&h.Tt45>0&h.Mach>=0&h.Ts_amb>0), ...
    'F3:TF:Units','测量物理范围非法，请核对Pa/K/rpm/kg/s单位。');
end

function task=local_preview(cfg,c,selection)
seg=sht_f32_segment_history(c.history,cfg.segmentation);
o=cfg.eventOptions;o.integrationStep_s=cfg.solver.integrationStep_s;
identity=struct('sourceSha256',c.contract.training,'role','identification','modelMode',0);
episodes=sht_f32_transient_episodes(c.history,seg,identity,o);
if nargin>=3
    assert(isequal(fieldnames(selection),{'sourceSegmentIds'}),'F3:TF:Selection','确认须提供sourceSegmentIds。');
    ids=string(selection.sourceSegmentIds(:));
    assert(~isempty(ids)&&numel(unique(ids))==numel(ids)&& ...
        all(ismember(ids,episodes.events.source_segment_id(episodes.events.selected))), ...
        'F3:TF:Selection','请选择至少一个有效候选事件，不得选入被拒绝的事件。');
    o.selectedSourceSegmentIds=ids;episodes=sht_f32_transient_episodes(c.history,seg,identity,o);
end
plan=sht_f33_local_thermal_plan(c.history.time_s,episodes.windows,cfg.solver.warmup_s);
plan.sensor_preparation_first=plan.initialization_first;
plan.sensor_preparation_last=plan.fit_first;
plan.actual_replay_count=plan.fit_last-plan.initialization_first+1;
plan.prehistory_short=plan.warmup_s<cfg.solver.warmup_s-1e-8;
plan.warning=repmat("起点热平衡为模型假设；传感器从模型首点初始化",height(plan),1);
plan.warning(plan.prehistory_short)=plan.warning(plan.prehistory_short)+"；可用前史不足配置长度";
task=struct('schema','F3_TRANSIENT_CONFIRM_R002','configuration',cfg,'check',c, ...
    'events',episodes.events,'windows',episodes.windows,'plan',plan,'segmentation',seg, ...
    'physicalCalculationExecuted',false,'selectedEventCount',nnz(episodes.events.selected), ...
    'fitRecordCount',sum(plan.fit_sample_count),'replayRecordCount',sum(plan.actual_replay_count));
end

function out=local_run(cfg,task,estimate,resume)
root=cfg.outputRoot;
assert(~isfile(fullfile(root,'delivery','results.xlsx')),'F3:TF:Completed','已有完整结果请read，不重新辨识。');
timer=tic;control=sht_tc24_run_control('open',struct('directory',root,'runId',cfg.runId,'resume',resume,'timer',timer), ...
    struct('task',task.check.contract,'confirmation',task.confirmationIdentity));
diary(fullfile(root,['session_' datestr(now,'yyyymmdd_HHMMSS') '.log']));clean=onCleanup(@()diary('off')); %#ok<NASGU>
fprintf('F3瞬态：13参数，%d窗口，%d拟合记录；粗估 %.1f--%.1f min，非收敛承诺。\n', ...
    height(task.plan),sum(task.plan.fit_sample_count),estimate.totalRange_s/60);
local_json(fullfile(root,'runtime_estimate.json'),estimate);
local_status('running','initialization',false);
try
    o=cfg.solver;o.runTag=cfg.runId;o.trainingWorkbook=fullfile(root,'confirmed_data.xlsx');
    o.testWorkbook='';o.steadyWorkbook=cfg.parentWorkbook;o.outputRoot=fullfile(root,'internal');
    o.reportRoot=cfg.reportRoot;o.resume=resume;o.runControl=control;
    o.taskIdentity=struct('contract',task.check.contract,'confirmation',task.confirmationIdentity);
    o.businessIdentity=task.check.business;
    r=sht_f33_transient_identification('run',o);
    delivery=fullfile(root,'delivery');if ~isfolder(delivery),mkdir(delivery);end
    model=fullfile(delivery,'flight_transient_model.xlsx');
    sht_f33_transient_delivery('write',r,model);
    resultFile=fullfile(delivery,'results.xlsx');
    local_export_result(resultFile,r,task);
    elapsed=toc(timer);
    manifest=struct('schema','F3_TRANSIENT_RUN_R002','runId',cfg.runId,'modelId',cfg.modelId, ...
        'businessIdentity',task.check.business,'sourceIdentity',r.identityHash, ...
        'confirmationIdentity',task.confirmationIdentity,'converged',r.converged, ...
        'stopReason',char(r.stopReason),'modelFile','flight_transient_model.xlsx', ...
        'modelSha256',sht_tc27_file_identity(model),'resultsFile','results.xlsx', ...
        'resultsSha256',sht_tc27_file_identity(resultFile),'testStatus',task.check.testStatus, ...
        'estimate',estimate,'timing',struct('currentSession_s',elapsed, ...
        'activeTotal_s',control.priorActiveSeconds+elapsed,'paused_s',control.priorPausedSeconds, ...
        'scope','check-after-invocation through model and results export; excludes MATLAB launch'), ...
        'uqStatus','not_evaluated_for_transient_combination','truthUsed',false);
    local_json(fullfile(delivery,'run_manifest.json'),manifest);
    sht_tc24_run_control('finish',control,'completed');
    local_status('completed',char(r.stopReason),true);
    out=local_read(root);
    if cfg.plotEnabled,local_plot(out);end
catch err
    if strcmp(err.identifier,'TC24:Control:Stopped')
        local_status('stopped','safe_iteration_boundary',false);
        out=struct('status','stopped','safeStopConfirmed',true,'resultDirectory',root);return;
    end
    sht_tc24_run_control('finish',control,'failed');local_status('failed',err.message,false);
    fid=fopen(fullfile(root,'failure.log'),'a');if fid>=0,fprintf(fid,'%s\n',getReport(err,'extended','hyperlinks','off'));fclose(fid);end
    rethrow(err);
end
    function local_status(status,message,available)
        local_json(fullfile(root,'task_status.json'),struct('runId',cfg.runId,'status',status, ...
            'message',message,'resultAvailable',available,'updatedAt',datestr(now,31)));
    end
end

function local_export_result(file,r,task)
assert(~isfile(file),'结果Excel已存在。');
temp=[tempname(fileparts(file)) '.xlsx'];
writetable(r.parameters,temp,'Sheet','Parameters');writetable(r.trainingPlan,temp,'Sheet','LocalPlan');
writetable(task.events,temp,'Sheet','Events');writetable(r.solve.history,temp,'Sheet','Iterations');
metrics=[local_metrics(r.initial,"initial");local_metrics(r.final,"estimated")];
writetable(metrics,temp,'Sheet','Metrics');
curves=[local_curves(r.initial,"initial");local_curves(r.final,"estimated")];
writetable(curves,temp,'Sheet','TrainingCurves');
for name={'HealthDesign','HealthNodes','FuelBias','Runtime','Model'}
    t=readtable(r.options.steadyWorkbook,'Sheet',name{1});
    writetable(t,temp,'Sheet',['Fixed_' name{1}]);
end
movefile(temp,file);
end

function t=local_metrics(e,label)
t=table(repmat(string(label),4,1),["Np";"Ng";"Pt3_eq";"Tt45"],["rpm";"rpm";"Pa";"K"], ...
    sqrt(mean(e.raw.^2,1))',max(abs(e.raw),[],1)',repmat(size(e.raw,1),4,1), ...
    'VariableNames',{'model','channel','unit','RMSE','max_abs_error','sample_count'});
end
function t=local_curves(e,label)
t=table(repmat(string(label),numel(e.time_s),1),e.time_s,e.window, ...
    'VariableNames',{'model','time_s','window_id'});
names={'Np','Ng','Pt3_eq','Tt45'};
for j=1:4
    t.([names{j} '_measured'])=e.measured(:,j);
    t.([names{j} '_sensor'])=e.prediction(:,j);
    t.([names{j} '_physical'])=e.physicalOutput(:,j);
end
end

function out=local_read(root)
folder=fullfile(root,'delivery');
if isfile(fullfile(root,'run_manifest.json')),folder=root;end
m=local_json_read(fullfile(folder,'run_manifest.json'));
for pair={'model','results'}
    f=pair{1};leaf=m.([f 'File']);[~,n,e]=fileparts(leaf);
    assert(strcmp(leaf,[n e]),'交付路径必须为相邻文件。');
    assert(strcmpi(sht_tc27_file_identity(fullfile(folder,leaf)),m.([f 'Sha256'])), ...
        'F3:TF:ResultIdentity','交付%s身份不符。',f);
end
d=sht_f33_transient_delivery('inspect',[],fullfile(folder,m.modelFile));
out=struct('manifest',m,'model',d,'resultFile',fullfile(folder,m.resultsFile), ...
    'physicalCalculationExecuted',false,'internalMatRequired',false);
for name={'Parameters','LocalPlan','Events','Iterations','Metrics','TrainingCurves', ...
        'Fixed_HealthDesign','Fixed_HealthNodes','Fixed_FuelBias','Fixed_Model'}
    out.(name{1})=readtable(out.resultFile,'Sheet',name{1});
end
assert(isequal(out.Parameters.c_index,(58:70)'),'缺少瞬态参数。');
end

function out=local_validate(u)
% 独立验证只消费冻结双Excel；不用原辨识MAT或原训练目录。
required={'modelFile','measurementFile','sheet','outputRoot','scope'};
assert(all(isfield(u,required)),'验证须显式提供模型、测量、sheet、输出目录和scope。');
assert(ismember(u.scope,{'local','full','initialization'}),'scope仅local/full/initialization。');
if ~isfield(u,'integrationStep_s'),u.integrationStep_s=.1;end
if ~isfield(u,'warmup_s'),u.warmup_s=60;end
if ~isfield(u,'segmentation'),u.segmentation=struct();end
if ~isfield(u,'eventOptions'),u.eventOptions=struct();end
binding={};
if isfield(u,'parentRuntimeBinding')&&~isempty(fieldnames(u.parentRuntimeBinding))
    assert(isfield(u,'parentRoute'),'F3:TF:ParentRoute','显式组合父绑定必须同时提供parentRoute。');
    binding={struct('priorRoute',u.parentRoute,'priorRuntimeBinding',u.parentRuntimeBinding)};
end
h=local_history(u.measurementFile,u.sheet,struct());
if strcmp(u.scope,'full')
    opts=struct('sheet',u.sheet,'integrationStep_s',u.integrationStep_s,'outputRoot',u.outputRoot);
    if ~isempty(binding),opts.parentRoute=u.parentRoute;opts.parentRuntimeBinding=u.parentRuntimeBinding;end
    out=Start_FlightModelAdapt_13_TransientModelPrediction(u.modelFile,u.measurementFile, ...
        opts);return;
end
seg=sht_f32_segment_history(h,u.segmentation);
eps=sht_f32_transient_episodes(h,seg,struct('sourceSha256',sht_tc27_file_identity(u.measurementFile), ...
    'role','independent_validation','modelMode',0),u.eventOptions);
plan=sht_f33_local_thermal_plan(h.time_s,eps.windows,u.warmup_s);
assert(height(plan)>0,'验证记录无有效大幅窗口，不回退完整历程。');
local_new_root(local_path(u.outputRoot));
d=sht_f33_transient_delivery('read',[],u.modelFile,binding{:});
c=struct('assets',d.assets,'steady',d.steady,'history',h,'windows',eps.windows, ...
    'folder',u.outputRoot,'report',u.outputRoot,'identity',struct('trainingSha256',sht_tc27_file_identity(u.measurementFile)), ...
    'options',struct('integrationStep_s',u.integrationStep_s,'warmup_s',u.warmup_s,'historyScale',[63,114,7863,5.72]));
c.sensor=sht_f31_flight_measurement('publicAssumptions',sht_f31_flight_measurement('model',3201001,'F32-MEASUREMENT-PRIOR',false));
timer=tic;prior=sht_f33_transient_identification('evaluate',c,zeros(13,1));
final=sht_f33_transient_identification('evaluate',c,d.parameters.value);
assert(prior.valid&&final.valid,'独立局部验证求值失败，见失败日志。');
out=struct('metrics',[local_metrics(prior,"initial");local_metrics(final,"estimated")], ...
    'curves',[local_curves(prior,"initial");local_curves(final,"estimated")],'plan',plan,'elapsed_s',toc(timer));
if strcmp(u.scope,'initialization')
    % 此额外计算只响应显式请求，不与查看已保存结果捆绑。
    cases=[120,0;240,0;60,-20;60,20];
    if isfield(u,'initializationCases'),cases=u.initializationCases;end
    assert(isnumeric(cases)&&size(cases,2)==2&&all(isfinite(cases),'all')&&all(cases(:,1)>=0), ...
        '初始化对照每行为准备秒数和金属初温偏移K。');
    out.initializationSensitivity=table();
    for j=1:size(cases,1)
        e=sht_f33_transient_identification('evaluate',c,d.parameters.value, ...
            u.integrationStep_s,cases(j,1),cases(j,2));
        assert(e.valid,'初始化对照求值失败：%s',e.error);
        difference=e;difference.raw=e.prediction-final.prediction;
        label=sprintf('warmup_%g_offset_%gK',cases(j,1),cases(j,2));
        out.initializationSensitivity=[out.initializationSensitivity;local_metrics(difference,label)]; %#ok<AGROW>
    end
    out.elapsed_s=toc(timer);
end
file=fullfile(u.outputRoot,'validation.xlsx');
writetable(out.metrics,file,'Sheet','Metrics');writetable(out.curves,file,'Sheet','Curves');writetable(plan,file,'Sheet','Plan');
if isfield(out,'initializationSensitivity'),writetable(out.initializationSensitivity,file,'Sheet','InitializationSensitivity');end
local_json(fullfile(u.outputRoot,'validation_identity.json'),struct('modelSHA',sht_tc27_file_identity(u.modelFile), ...
    'dataSHA',sht_tc27_file_identity(u.measurementFile),'configuration',u,'elapsed_s',out.elapsed_s));
end

function names=local_sources()
% 静态依赖递归加显式动态入口，不依赖创建时间；只取当前tune源码身份。
root=fileparts(mfilename('fullpath'));
entry={'sht_f33_transient_identification','sht_f32_replay_history', ...
    'sht_f3_transient_task','Start_FlightModelAdapt_11_TransientCoefficientEstimation', ...
    'Start_FlightModelAdapt_12_TransientCoefficientValidation','Start_FlightModelAdapt_13_TransientModelPrediction'};
files=cellfun(@(n)fullfile(root,[n '.m']),entry,'UniformOutput',false);
list=matlab.codetools.requiredFilesAndProducts(files);list=unique([files(:);list(:)]);
names=struct();
for k=1:numel(list)
    [folder,n,e]=fileparts(list{k});
    if strcmpi(folder,root)&&strcmpi(e,'.m'),names.(n)=sht_tc27_file_identity(list{k});end
end
names.runtimeCost=sht_tc27_file_identity(fullfile(root,'TestData','runtime_cost_baselines','F3_R2019b_cost_v1.json'));
end
function p=local_path(p)
p=char(p);assert(~isempty(regexp(p,'^([A-Za-z]:[\\/]|\\\\)','once')), ...
    'F3:TF:Path','必须明确绝对路径：%s。',p);p=char(java.io.File(p).getCanonicalPath());
end
function local_new_root(root)
local_assert_empty(root);
if ~isfolder(root),mkdir(root);end
end
function local_assert_empty(root)
if ~isfolder(root),assert(~isfile(root),'输出路径已被文件占用。');return;end
items=dir(root);items=items(~ismember({items.name},{'.','..'}));
assert(isempty(items),'F3:TF:Existing','必须使用空的新输出目录：%s。',root);
end
function h=local_hash(v),h=sht_tc24_run_control('hash',v);end
function local_json(file,v)
fid=fopen(file,'w','n','UTF-8');assert(fid>=0,'JSON无法写入。');c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',jsonencode(v));
end
function v=local_json_read(file)
assert(isfile(file),'F3:TF:MissingResult','尚无已保存结果：%s。',file);v=jsondecode(fileread(file));
end
function local_plot(r)
t=r.TrainingCurves;figure('Name','过渡态拟合结果');
names={'Np','Ng','Pt3_eq','Tt45'};a=string(t.model)=="estimated";
for j=1:4,subplot(2,2,j);plot(t.time_s(a),[t.([names{j} '_measured'])(a),t.([names{j} '_sensor'])(a)]);title(names{j});legend('测量','预测测量');end
end
