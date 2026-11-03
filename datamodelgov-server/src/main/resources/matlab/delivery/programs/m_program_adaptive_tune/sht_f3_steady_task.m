function out=sht_f3_steady_task(action,user,selection)
%SHT_F3_STEADY_TASK 飞参导入、窗口预览与确认；界面和离线共用此函数。
% check/preview/confirm/read处理自动候选；estimate/run接收已确认的证据。
% status/readResult只读保存状态/完整结果，不打开DLL，不产生参数区间。
% 所有正式路径和父模型必须显式提供；没有测试集就保持空，不取样例。
if nargin<2,user=struct();end
if nargin<3,selection=struct();end
action=char(lower(string(action)));
if strcmp(action,'capabilities')
    out=struct('schema','F3_BUSINESS_CAPABILITIES_B23', ...
        'actions',{{'checkData','estimateData','previewData','confirmData','bindParent', ...
        'estimate','run','resume','status','requestPause','readResult', ...
        'uqCheck','uqEstimate','uqRun','uqResume','uqStatus','uqRequestPause','uqRead'}}, ...
        'parentSources',{{'2p4','2p7','flight','combined'}}, ...
        'modelRoutes',{{'steady','transient_instant'}}, ...
        'dataMethods',{{'steady_only','steady_plus_small_history'}}, ...
        'fixedTransientCount',13,'fixedTransientEstimated',false, ...
        'implementationStatus','candidate_source_pending_runtime_verification', ...
        'noDll',true,'uqDataMethods',{{'steady_only'}});
    return;
end
if ismember(action,{'checkdata','estimatedata'})
    c=local_config(user,true);out=local_check(c,true);
    if strcmp(action,'estimatedata')
        out.estimate=sht_f3_runtime_estimate('unboundData',out.inputData,c);
    end
    return;
end
if ismember(action,{'previewdata','confirmdata','bindparent'})
    out=local_data_task(action,user,selection);return;
end
if ismember(action,{'uqcheck','uqestimate','uqrun','uqresume','uqstatus','uqrequestpause','uqread'})
    out=local_uq(action,user);return;
end
if ismember(action,{'estimate','run','status','readresult','requestpause','resume'})
    out=local_execution(action,user);return;
end
assert(ismember(action,{'check','preview','confirm','read'}), ...
    'SHT:F3Task:Action','A批仅支持check、preview、confirm和read。');
cfg=local_config(user);
previewFile=fullfile(cfg.outputRoot,'f3_task_preview.mat');
if strcmp(action,'read')
    assert(isfile(previewFile),'SHT:F3Task:PreviewMissing','任务预览不存在。');
    saved=load(previewFile,'task');out=saved.task;
    assert(strcmp(out.taskId,cfg.taskId),'SHT:F3Task:TaskId','查看任务编号不匹配。');
    local_verify_payload(out);
    % 查看冻结记录不要求重新计算，也不替旧身份签名。
    out.currentSourceCompatible=false;out.currentCompatibilityReason='';
    try
        check=local_check(cfg);
        out.currentSourceCompatible=strcmp(check.identity,out.identity);
        if ~out.currentSourceCompatible,out.currentCompatibilityReason='当前身份与冻结预览不同。';end
    catch failure
        out.currentCompatibilityReason=failure.message;
    end
    return;
end
check=local_check(cfg); % 所有文件、父参数与数据先核验，再创建目录。
if strcmp(action,'check'),out=check;return;end
local_own_roots(cfg);
if isfile(previewFile)
    saved=load(previewFile,'task');task=saved.task;local_verify_payload(task);
    assert(strcmp(task.identity,check.identity),'SHT:F3Task:StalePreview', ...
        '测量、父模型、配置、运行资产或源码已改变；请使用新任务目录建立预览。');
elseif strcmp(action,'confirm')
    error('SHT:F3Task:PreviewMissing','请先对同一配置执行preview，再确认窗口。');
else
    task=local_make_preview(cfg,check);
    save(previewFile,'task','-v7.3');
    writetable(task.parameterStatus,fullfile(cfg.reportRoot,'parameter_source_status.csv'));
end
if strcmp(action,'preview'),out=task;return;end
out=local_confirm(task,selection,cfg);
end

function c=local_config(u,dataOnly)
if nargin<2,dataOnly=false;end
assert(isstruct(u)&&isscalar(u),'SHT:F3Task:Config','配置必须为标量结构体。');
c=struct('taskId','','taskPurpose','model_build','identificationFile','','validationFile','', ...
    'parentSource','','parentRoute','','parentWorkbook','','parentRuntimeBinding',struct(), ...
    'parentDefinition',struct(),'parentRelation',struct(),'businessIdentity',struct(), ...
    'modelId','','dataIntent',struct(), ...
    'outputRoot','','reportRoot','', ...
    'engineId','','sortieId','','modelRoute','transient_instant','dataMethod','steady_only', ...
    'parameterSetId','set1','scheduleParameterization','independent_nodes', ...
    'regularizationStrength',.05,'integrationStep_s',.1,'segmentation',struct(), ...
    'channelMap',struct(),'sourceUnits',struct());
names=fieldnames(u);
for k=1:numel(names)
    assert(isfield(c,names{k}),'SHT:F3Task:UnknownOption','未知配置：%s。',names{k});
    c.(names{k})=u.(names{k});
end
assert(ismember(c.taskPurpose,{'model_build','uq_assessment'}), ...
    'SHT:F3Task:Purpose','taskPurpose必须为model_build或uq_assessment。');
assessment=strcmp(c.taskPurpose,'uq_assessment');
if assessment
    assert(isempty(c.modelId),'SHT:F3Task:AssessmentModelId', ...
        '独立评估不生成子模型，modelId必须留空；所评估现有模型由parentRelation/parentModelId绑定。');
end
required={'taskId','identificationFile','parentSource','parentRoute','parentWorkbook','outputRoot','reportRoot'};
if dataOnly
    assert(isempty(c.parentWorkbook)&&isempty(fieldnames(c.parentRuntimeBinding))&& ...
        isempty(fieldnames(c.parentDefinition))&&isempty(fieldnames(c.dataIntent)), ...
        'SHT:F3Task:Unbound','数据意图阶段不得携带真实父文件、运行包关联或旧执行确认。');
    local_relation(c.parentRelation);
    assert(isempty(c.parentSource)||strcmp(c.parentSource,'unbound'), ...
        'SHT:F3Task:Unbound','父未绑定时parentSource须为空或unbound。');
    c.parentSource='unbound';c.parentRoute=c.parentRelation.route;
    required={'taskId','identificationFile','outputRoot','reportRoot','engineId','sortieId'};
    if ~assessment,required{end+1}='modelId';end
end
for k=1:numel(required)
    v=c.(required{k});assert((ischar(v)||isstring(v))&&isscalar(string(v))&&strlength(string(v))>0, ...
        'SHT:F3Task:Required','必须显式提供%s。',required{k});
    c.(required{k})=char(v);
end
assert(~isempty(regexp(c.taskId,'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$','once')), ...
    'SHT:F3Task:TaskId','taskId只用字母、数字、下划线或短横线，最长64字符。');
c.validationFile=char(string(c.validationFile));
for f={'identificationFile','parentWorkbook','outputRoot','reportRoot','validationFile'}
    if ~isempty(c.(f{1})),c.(f{1})=local_absolute(c.(f{1}));end
end
sources={'2p4','2p7','flight','combined'};if dataOnly,sources={'unbound'};end
assert(ismember(c.parentSource,sources)&& ...
    ismember(c.parentRoute,{'steady','transient_instant'}), ...
    'SHT:F3Task:ParentSelection','父模型来源为2p4/2p7/flight，路径为steady/transient_instant。');
assert(ismember(c.modelRoute,{'steady','transient_instant'})&& ...
    ismember(c.dataMethod,{'steady_only','steady_plus_small_history'})&& ...
    ismember(c.parameterSetId,{'set1','set2'})&& ...
    ismember(c.scheduleParameterization,{'independent_nodes','family_amplitude'}), ...
    'SHT:F3Task:Route','辨识路线或参数配置不支持。');
validateattributes(c.regularizationStrength,{'numeric'},{'scalar','real','finite','nonnegative'});
assert(isscalar(c.integrationStep_s)&&ismember(c.integrationStep_s,[.1,.025]), ...
    'SHT:F3Task:Step','积分配置只允许0.1或0.025秒，不改变原Excel记录。');
assert(isstruct(c.channelMap)&&isscalar(c.channelMap)&&isstruct(c.sourceUnits)&& ...
    isscalar(c.sourceUnits)&&isstruct(c.segmentation)&&isscalar(c.segmentation), ...
    'SHT:F3Task:Mapping','通道、单位及分段配置必须为标量结构体。');
for f={'parentDefinition','parentRelation','parentRuntimeBinding','businessIdentity','dataIntent'}
    assert(isstruct(c.(f{1}))&&isscalar(c.(f{1})), ...
        'SHT:F3Task:Config','%s必须为标量结构体。',f{1});
end
local_safe_roots(c);
end

function out=local_check(c,dataOnly)
if nargin<2,dataOnly=false;end
files={c.identificationFile,c.validationFile,c.parentWorkbook};
for k=1:numel(files)
    assert(isempty(files{k})||isfile(files{k}),'SHT:F3Task:MissingFile','输入文件不存在：%s',files{k});
end
if dataOnly,parent=struct('source','unbound','status','waiting_parent');
else,parent=local_parent(c);end
data=struct();hashes=struct();maps=struct();
roles={'identification','independent_validation'};
for k=1:2
    if isempty(files{k}),continue;end
    hashes.(roles{k})=local_hash(files{k});
    [data.(roles{k}),maps.(roles{k})]=local_measurement(files{k},c);
end
assert(~isfield(hashes,'independent_validation')|| ...
    ~strcmp(hashes.identification,hashes.independent_validation), ...
    'SHT:F3Task:SameData','训练和测试文件内容相同，不能声明独立测试。');
runtimeManifest='';parentHash='';
if ~dataOnly
    a=sht_f3_three_component_assets('verifyRuntime');
    release=sht_f3_three_component_assets('manifest',a.runtime);runtimeManifest=release.sha256;
    parentHash=parent.sha256;
end
if ~isempty(fieldnames(c.dataIntent))
    assert(all(isfield(c.dataIntent,{'file','sha256'}))&&isfile(c.dataIntent.file)&& ...
        strcmp(local_hash(c.dataIntent.file),c.dataIntent.sha256), ...
        'SHT:F3Task:IntentChanged','原数据意图缺失或改变，不能给旧确认重签。');
end
dependency=local_dependencies();
contract=struct('configuration',c,'sourceHashes',hashes,'channelMapping',maps, ...
    'parentSha256',parentHash,'runtimeManifestSha256',runtimeManifest, ...
    'sourceIdentity',dependency,'modelMode',0,'thermalMode','Visser16', ...
    'benchFuelBiasInherited',false,'individualTransientSource','nominal_zero');
if ~dataOnly&&isfield(parent,'executionContract')
    % 同一已校核父/执行热资产绑定进入确认身份，不只签默认运行包的SHA。
    contract.parentRuntimeAssociation=parent.runtimeAssociation;
    contract.executionContract=parent.executionContract;
end
out=struct('identity',local_digest(contract),'contract',contract,'parent',parent, ...
    'inputData',data,'noDll',true,'status','input_contract_checked');
if ~dataOnly&&isfield(parent.schedule,'fixedTransient')
    out.contract.individualTransientSource='selected_parent_fixed_13';
    out.contract.fixedTransient=parent.schedule.fixedTransient;
    out.identity=local_digest(out.contract);
end
if dataOnly,out.status='data_checked_parent_not_bound';end
if ~dataOnly && (~isempty(fieldnames(c.businessIdentity))||ismember(c.parentSource,{'flight','combined'}))
    out.businessIdentity=local_business(c,parent);
end
end

function p=local_parent(c)
% 预览与辨识共用现行正式Excel恢复，避免选择TC27却暗读TC24。
p=sht_f3_current_contract('parent',struct('priorSource',c.parentSource, ...
    'priorRoute',c.parentRoute,'priorWorkbook',c.parentWorkbook, ...
    'priorRuntimeBinding',c.parentRuntimeBinding,'priorDefinition',c.parentDefinition));
p=rmfield(p,'baseResult');
end

function [data,map]=local_measurement(file,c)
data=readtable(file,'Sheet','Data');
targets={'sample_id','time_s','Ps0','Tt1','Pt3_eq','Ng','Np','Mkp','Wf','Tt45','Altitude','Mach','Ts_amb'};
units={'1','s','Pa','K','Pa','rpm','rpm','Nm','kg/s','K','m','1','K'};
assert(all(ismember(fieldnames(c.channelMap),targets))&&all(ismember(fieldnames(c.sourceUnits),targets)), ...
    'SHT:F3Task:Mapping','映射或单位含未知目标通道。');
names=targets;sourceUnits=units;
for k=1:numel(targets)
    if isfield(c.channelMap,targets{k}),names{k}=char(string(c.channelMap.(targets{k})));end
    if isfield(c.sourceUnits,targets{k}),sourceUnits{k}=char(string(c.sourceUnits.(targets{k})));end
end
assert(numel(unique(names))==numel(names),'SHT:F3Task:Mapping','不同目标不能重复使用同一源列。');
assert(all(ismember(names,data.Properties.VariableNames)),'SHT:F3Task:MissingChannel', ...
    'Data缺少映射后的必需列：%s',strjoin(setdiff(names,data.Properties.VariableNames),', '));
extras=setdiff(data.Properties.VariableNames,names,'stable');
data=data(:,names);data.Properties.VariableNames=targets;
for k=1:numel(targets)
    assert(isnumeric(data.(targets{k}))&&isreal(data.(targets{k})), ...
        'SHT:F3Task:ChannelType','测量列%s必须为实数。',targets{k});
    [gain,offset]=local_unit(sourceUnits{k},units{k});
    data.(targets{k})=double(data.(targets{k}))*gain+offset;
end
assert(height(data)>=3&&all(isfinite(table2array(data)),'all')&& ...
    isequal(data.sample_id,(1:height(data)).')&&all(diff(data.time_s)>0), ...
    'SHT:F3Task:Measurement','编号、时间或数值无效。');
map=struct('targets',{targets},'sources',{names},'sourceUnits',{sourceUnits}, ...
    'targetUnits',{units},'ignoredColumns',{extras});
end

function [g,b]=local_unit(source,target)
g=1;b=0;if strcmp(source,target),return;end
switch [source '->' target]
    case 'kPa->Pa',g=1000;
    case 'bar->Pa',g=1e5;
    case 'C->K',b=273.15;
    case 'rad/s->rpm',g=60/(2*pi);
    case 'g/s->kg/s',g=.001;
    case 'kg/h->kg/s',g=1/3600;
    case 'ft->m',g=.3048;
    case 'ms->s',g=.001;
    otherwise,error('SHT:F3Task:Unit','不支持单位%s转换到%s，不能自动猜测。',source,target);
end
end

function out=local_confirm(task,selection,c)
[r,chosen]=local_select(task.result,selection,c);
selectionIdentity=local_digest(struct('taskIdentity',task.identity,'selection',chosen));
directory=fullfile(c.outputRoot,'confirmations',selectionIdentity(1:16));
receiptFile=fullfile(directory,'confirmation_receipt.mat');
if isfile(receiptFile)
    saved=load(receiptFile,'receipt');out=saved.receipt;
    identity=out.receiptIdentity;payload=rmfield(out,'receiptIdentity');
    assert(strcmp(out.identity,task.identity)&&strcmp(out.selectionIdentity,selectionIdentity)&& ...
        strcmp(identity,local_digest(payload)), ...
        'SHT:F3Task:ConfirmationIdentity','确认载荷或身份冲突。');
    local_verify_delivery(out);return;
end
assert(~isfolder(directory),'SHT:F3Task:ExistingOutput','已有未完成确认目录，不能覆盖：%s',directory);
r.options.outputRoot=directory;
r.options.reportRoot=fullfile(c.reportRoot,'confirmations',selectionIdentity(1:16));
r.options.saveEnabled=true;r.options.plotEnabled=false;
r.parameterSourceStatus=local_parameter_status(task.parent.schedule,c,r.datasets(1),true);
r.taskContract=struct('taskId',c.taskId,'identity',task.identity, ...
    'selectionIdentity',selectionIdentity,'parentSha256',task.parent.sha256);
r=sht_f32_preprocess_and_replay('exportConfirmed',r);
out=struct('schemaVersion','F3_STEADY_TASK_CONFIRMATION_R041','taskId',c.taskId, ...
    'identity',task.identity,'selectionIdentity',selectionIdentity,'selection',chosen, ...
    'configuration',c,'parent',task.parent,'stage32File',r.output.latestMatFile, ...
    'parameterStatus',r.parameterSourceStatus, ...
    'trainingWorkbook',r.output.identificationExcel,'validationWorkbook',r.output.validationExcel, ...
    'status','confirmed_preprocessing_only_no_identification_no_uq');
names={'stage32File','trainingWorkbook','validationWorkbook'};out.deliveryHashes=struct();
for k=1:numel(names)
    if ~isempty(out.(names{k})),out.deliveryHashes.(names{k})=local_hash(out.(names{k}));end
end
if ~isempty(fieldnames(c.businessIdentity))||ismember(c.parentSource,{'flight','combined'})
    out.businessIdentity=local_business(c,task.parent);
end
out.receiptIdentity=local_digest(out);
receipt=out;save(receiptFile,'receipt','-v7.3');
end

function [r,chosen]=local_select(r,selection,c)
% 两种确认复用同一选择规则；不把未来父的存在性引入分段。
assert(isstruct(selection)&&isscalar(selection)&& ...
    all(ismember(fieldnames(selection),{'identification','independent_validation'})), ...
    'SHT:F3Task:Selection','选择按identification/independent_validation提供segment_id列表。');
chosen=struct();
for k=1:numel(r.datasets)
    d=r.datasets(k);ids=strings(0,1);
    if isfield(selection,d.role),ids=string(selection.(d.role)(:));end
    seg=d.segmentation.segments;
    allowed=ismember(string(seg.segment_class),{'steady_window','small_change'}) & seg.usable_fraction==1;
    assert(numel(unique(ids))==numel(ids)&&all(ismember(ids,string(seg.segment_id(allowed)))), ...
        'SHT:F3Task:Selection','%s含未知、重复或不可选窗口。',d.role);
    seg.usable=ismember(string(seg.segment_id),ids);
    if strcmp(d.role,'identification')
        assert(any(seg.usable & string(seg.segment_class)=="steady_window"), ...
            'SHT:F3Task:NoSteady','训练至少选择一个有效稳态窗口。');
        assert(~strcmp(c.dataMethod,'steady_plus_small_history')|| ...
            any(seg.usable & string(seg.segment_class)=="small_change"), ...
            'SHT:F3Task:NoSmall','混合模式至少选择一个有效小幅窗口。');
    end
    chosen.(d.role)=sort(ids);
    r.datasets(k).segmentation.segments=seg;
    r.datasets(k).segmentation.labels.fit_selected=ismember(string(d.segmentation.labels.segment_id),ids);
    small=seg(seg.usable & string(seg.segment_class)=="small_change",:);
    r.datasets(k).localSmallThermalPlan=sht_f33_local_thermal_plan(d.measurement.time_s,small,60);
end
% 用户提供过测试文件但没有确认任何测试窗口时，不输出空证据测试表。
% 原自动测试候选仍在预览中；不能让下游把它误认为已选的独立测试。
if numel(r.datasets)>1 && ~any(r.datasets(2).segmentation.segments.usable)
    r.datasets=r.datasets(1);r.options.validationEnabled=false;
end
end

function status=local_parameter_status(s,c,d,confirmed)
if nargin<4,confirmed=false;end
dict=sht_health_parameter_dictionary(0);rows=cell(0,1);
if strcmp(c.parameterSetId,'set1'),active=[1,2,7,8,10,11,12];else,active=[1,2,6,7,8,10,11,12,14,15];end
for k=1:height(dict)
    h=dict.c_index(k);found=find([s.healthEntries.cIndex]==h,1);
    x=NaN;v=s.designHealth(k);state='held_parent_constant';
    if ~dict.active(k),state='reserved_no_effect';end
    if h>=58&&h<=70
        state='held_nominal_zero_transient';
        if isfield(s,'fixedTransient'),state='held_selected_parent_transient';end
    end
    if ~isempty(found)
        e=s.healthEntries(found);x=e.xNodes(:);v=e.kNodes(:);state='held_parent_nodes';
    end
    for j=1:numel(x)
        st=state;
        if ismember(h,active),st='pending_model_evaluation';end
        if ~isempty(found)&&e.pressureLoss&&x(j)==0,st='fixed_zero_flow_node';end
        rows{end+1,1}=table(h,string(dict.name(k)),j,x(j),v(j),"parent_excel",string(st),NaN,NaN,NaN, ...
            'VariableNames',{'c_index','name','node_index','coordinate','prior_value','source','participation','estimate','lower','upper'}); %#ok<AGROW>
    end
end
f=s.fuelBias;q=d.measurement.Wf/f.wfDesign;
if confirmed
    % 燃油调度坐标来自可测Wf，覆盖只使用实际参与辨识的窗口。
    seg=d.segmentation.segments;q=zeros(0,1);
    for k=1:height(seg)
        if ~seg.usable(k),continue;end
        row=round(seg.first(k)):round(seg.last(k));
        if string(seg.segment_class(k))=="steady_window"
            q(end+1,1)=mean(d.measurement.Wf(row))/f.wfDesign; %#ok<AGROW>
        elseif strcmp(c.dataMethod,'steady_plus_small_history')
            t=d.measurement.time_s(row);fit=t>=t(1)+1 & t<=t(end)-1;
            q=[q;d.measurement.Wf(row(fit))/f.wfDesign]; %#ok<AGROW>
        end
    end
end
cover=sht_f33_schedule_parameterization('coverage',f.xNodes,q,.02,false);
for j=1:numel(f.xNodes)
    st='potential_input_support_not_yet_confirmed';
    if ~cover.activeNode(j),st='no_input_support';end
    if confirmed
        st='selected_input_support_only';
        if ~cover.activeNode(j),st='held_no_selected_input_support';end
    end
    rows{end+1,1}=table(-1,"Wf_bias",j,f.xNodes(j),0,"flight_zero_prior",string(st),NaN,NaN,NaN, ...
        'VariableNames',rows{1}.Properties.VariableNames); %#ok<AGROW>
end
rows{end+1,1}=table(-2,"K_dist_eq",1,NaN,0,"flight_zero_prior","constant_planned_release",NaN,NaN,NaN, ...
    'VariableNames',rows{1}.Properties.VariableNames);
status=vertcat(rows{:});
status.unit=repmat("1",height(status),1);status.unit(status.c_index==-1)="kg/s";
status.node_support=NaN(height(status),1);
status.node_support(status.c_index==-1)=cover.support;
end

function identity=local_payload_hash(t)
payload=struct('identity',t.identity,'configuration',t.configuration, ...
    'sourceContract',t.sourceContract,'parent',t.parent,'result',t.result, ...
    'parameterStatus',t.parameterStatus);
identity=local_digest(payload);
end

function local_verify_payload(t)
assert(strcmp(t.payloadIdentity,local_payload_hash(t)), ...
    'SHT:F3Task:PreviewPayload','预览载荷已改变，不能重签后继续。');
end

function local_verify_delivery(r)
names=fieldnames(r.deliveryHashes);
for k=1:numel(names)
    assert(isfile(r.(names{k}))&&strcmp(r.deliveryHashes.(names{k}),local_hash(r.(names{k}))), ...
        'SHT:F3Task:DeliveryChanged','确认交付物缺失或改变：%s',r.(names{k}));
end
end

function local_own_roots(c)
% 两个根目录均只能由同一任务使用，不能把已有目录当作可覆盖的空容器。
for root={c.outputRoot,c.reportRoot}
    file=fullfile(root{1},'f3_task_owner.mat');
    owner=struct('taskId',c.taskId,'outputRoot',c.outputRoot,'reportRoot',c.reportRoot);
    if isfolder(root{1})
        assert(isfile(file),'SHT:F3Task:RootOwned','目录已存在且不属于本任务：%s',root{1});
        saved=load(file,'owner');
        assert(isequal(saved.owner,owner),'SHT:F3Task:RootOwned','目录属于其他任务：%s',root{1});
    end
end
for root={c.outputRoot,c.reportRoot}
    if ~isfolder(root{1}),mkdir(root{1});save(fullfile(root{1},'f3_task_owner.mat'),'owner');end
end
end

function local_safe_roots(c)
assert(~local_overlap(c.outputRoot,c.reportRoot),'SHT:F3Task:PathIsolation','业务和报告目录不得重叠。');
tune=fileparts(mfilename('fullpath'));current=sht_f3_current_contract('paths');
assets=sht_f3_three_component_assets('paths');
protected={fullfile(tune,'TestData'),fullfile(tune,'MiddleData','three_component','steady_model_2p4_delivery'), ...
    fullfile(tune,'MiddleData','three_component','tc27'),fullfile(current.middle,'uncertainty'), ...
    fullfile(current.middle,'deterministic'),fullfile(current.middle,'identification'), ...
    fullfile(current.middle,'transient_identification'), ...
    fullfile(current.middle,'preprocess'),fullfile(current.middle,'F3_1B_R011'), ...
    fullfile(current.middle,'F3_1A_R010'),fullfile(current.middle,'F3_2_R011'), ...
    assets.runtime};
for r={c.outputRoot,c.reportRoot}
    for k=1:numel(protected)
        assert(~local_overlap(r{1},local_absolute(protected{k})), ...
            'SHT:F3Task:ProtectedRoot','不得写入或包含现行受保护目录：%s',r{1});
    end
    inputs={c.identificationFile,c.validationFile,c.parentWorkbook};
    if isfield(c.parentDefinition,'workbook'),inputs{end+1}=local_absolute(c.parentDefinition.workbook);end
    if isfield(c.dataIntent,'file'),inputs{end+1}=local_absolute(c.dataIntent.file);end
    for f=inputs
        if isempty(f{1}),continue;end
        assert(~local_overlap(r{1},fileparts(f{1})), ...
            'SHT:F3Task:InputOutputOverlap','输出目录不得与输入/父模型目录重叠。');
    end
end
end

function yes=local_overlap(a,b)
a=lower(a);b=lower(b);
yes=strcmp(a,b)||startsWith(a,[b filesep])||startsWith(b,[a filesep]);
end

function p=local_absolute(p)
p=char(string(p));assert(~isempty(regexp(p,'^([A-Za-z]:[\\/]|\\\\)','once')), ...
    'SHT:F3Task:AbsolutePath','必须给出绝对路径：%s',p);
p=char(java.io.File(p).getCanonicalPath());
end

function out=local_dependencies()
names={'sht_f3_steady_task','Start_FlightModelAdapt_14_SteadyTask', ...
    'sht_f32_preprocess_and_replay','sht_f32_segment_history','sht_f32_replay_history', ...
    'sht_f31_flight_measurement','sht_f33_local_thermal_plan','sht_f32_transient_episodes', ...
    'sht_f3_three_component_assets','sht_f3_current_contract', ...
    'sht_f33_model_adapt_v2','sht_f33_schedule_parameterization', ...
    'sht_health_parameter_dictionary','sht_load_2p4_deterministic_delivery', ...
    'sht_steady_model_adapt_v2_common','sht_tc27_delivery','sht_tc27_schedule', ...
    'sht_resolve_delivery_input_file','sht_tc27_file_identity', ...
    'sht_transient_model_adapt_common','sht_reynolds_correction_config'};
names=[names,{'sht_tc27_transient_combined_delivery','sht_tc27_runtime_package'}];
names=[names,{'sht_f33_excel_delivery','sht_f33_independent_evidence_validation', ...
    'sht_f3_runtime_estimate','sht_tc24_run_control','sht_f3_business_identity'}];
out=struct();
for k=1:numel(names)
    file=which(names{k});assert(~isempty(file),'SHT:F3Task:Dependency','缺少依赖%s。',names{k});
    out.(names{k})=local_hash(file);
end
end

function h=local_hash(file)
h=sht_f33_model_adapt_v2('fileHash',file);
end

function task=local_make_preview(c,check)
o=struct('modelMode',0,'runTag',c.taskId, ...
    'identificationFile',c.identificationFile,'validationFile',c.validationFile, ...
    'validationEnabled',~isempty(c.validationFile),'outputRoot',c.outputRoot, ...
    'reportRoot',c.reportRoot,'replayEnabled',false,'saveEnabled',false, ...
    'plotEnabled',false,'inputData',check.inputData,'validationPolicy','steady_task_preview', ...
    'segmentation',c.segmentation,'priorSource',c.parentSource,'priorRoute',c.parentRoute, ...
    'priorWorkbook',c.parentWorkbook,'integrationStep_s',c.integrationStep_s);
r=sht_f32_preprocess_and_replay(o);
task=struct('schemaVersion','F3_STEADY_TASK_A_R041','taskId',c.taskId, ...
    'identity',check.identity,'configuration',c,'sourceContract',check.contract, ...
    'parent',check.parent,'result',r,'createdAt',datestr(now,31), ...
    'status','preview_only_no_identification_no_uq');
task.parameterStatus=table();
if ~strcmp(c.parentSource,'unbound')
    task.parameterStatus=local_parameter_status(check.parent.schedule,c,r.datasets(1));
else
    task.status='data_preview_waiting_parent';
end
task.payloadIdentity=local_payload_hash(task);
end

function out=local_data_task(action,u,selection)
if strcmp(action,'bindparent'),out=local_bind_parent(u);return;end
c=local_config(u,true);local_intent_identity(c);
check=local_check(c,true);local_own_roots(c);
file=fullfile(c.outputRoot,'f3_data_preview.mat');
if isfile(file)
    saved=load(file,'task');task=saved.task;local_verify_payload(task);
    assert(strcmp(task.identity,check.identity),'SHT:F3Task:StaleData', ...
        '数据、映射、筛选或源码改变；请使用新数据任务目录，不能重签。');
else
    assert(strcmp(action,'previewdata'),'SHT:F3Task:PreviewMissing','先执行previewData。');
    task=local_make_preview(c,check);save(file,'task','-v7.3');
end
if strcmp(action,'previewdata'),out=task;return;end
[~,chosen]=local_select(task.result,selection,c);
intent=struct('schemaVersion','F3_DATA_INTENT_B1_V1','task',task,'selection',chosen, ...
    'parentRelation',c.parentRelation,'status','confirmed_data_waiting_parent', ...
    'executable',false,'businessIdentity',local_intent_identity(c));
intent.identity=local_digest(intent);
directory=fullfile(c.outputRoot,'intents',intent.identity(1:16));
file=fullfile(directory,'data_intent.mat');
if isfile(file)
    prior=load(file,'intent');assert(isequaln(prior.intent,intent), ...
        'SHT:F3Task:IntentChanged','意图载荷冲突，不能覆盖。');
else
    assert(~isfolder(directory),'SHT:F3Task:ExistingOutput','已有未完成意图目录。');
    mkdir(directory);save(file,'intent','-v7.3');
end
out=struct('intentFile',file,'intentSha256',local_hash(file),'identity',intent.identity, ...
    'status',intent.status,'executable',false,'parameterCount',[], ...
    'parameterStatus','waiting_for_actual_parent_and_physical_coverage', ...
    'estimate',local_unbound_estimate(task,chosen,c));
end

function local_relation(r)
assert(isstruct(r)&&isscalar(r)&&all(isfield(r,{'source','route','modelId','sortieId','basis'}))&& ...
    all(ismember(fieldnames(r),{'source','route','modelId','sortieId','basis'}))&& ...
    ismember(r.source,{'flight','combined','2p4','2p7'})&&ismember(r.route,{'steady','transient_instant'})&& ...
    ~isempty(strtrim(char(r.modelId)))&&~isempty(strtrim(char(r.basis))), ...
    'SHT:F3Task:ParentRelation','父意图须明确source、route、modelId、sortieId和依据basis。');
if strcmp(r.source,'flight')
    assert(~isempty(strtrim(char(r.sortieId))),'SHT:F3Task:ParentRelation','飞行父须声明父架次编号。');
end
end

function b=local_intent_identity(c)
local_relation(c.parentRelation);
if strcmp(c.taskPurpose,'uq_assessment')
    b=sht_f3_business_identity('resolve',struct([]),c.businessIdentity,'uq');
    assert(strcmp(b.engineId,c.engineId)&&strcmp(b.sortieId,c.sortieId)&& ...
        strcmp(b.parentModelId,c.parentRelation.modelId)&&isempty(c.modelId), ...
        'SHT:F3Task:BusinessConflict','评估发动机/架次/现有模型与明确业务身份冲突。');
    return;
end
b=sht_f3_business_identity('resolve',struct([]),c.businessIdentity,'deterministic');
assert(strcmp(b.engineId,c.engineId)&&strcmp(b.sortieId,c.sortieId)&&strcmp(b.modelId,c.modelId)&& ...
    strcmp(b.parentModelId,c.parentRelation.modelId)&&~strcmp(b.modelId,b.parentModelId), ...
    'SHT:F3Task:BusinessConflict','当前发动机/架次/模型或已批准父关系与businessIdentity冲突。');
end

function b=local_business(c,p)
facts=sht_f3_business_identity('workbook',p.file);values=struct();
if isfield(facts,'engine_id'),values.engineId=facts.engine_id;end
if isfield(facts,'model_id'),values.parentModelId=facts.model_id;end
e=struct('source',p.file,'sha256',p.sha256,'values',values);
scope='deterministic';fields={'engineId','sortieId','modelId'};
if strcmp(c.taskPurpose,'uq_assessment'),scope='uq';fields={'engineId','sortieId'};end
b=sht_f3_business_identity('resolve',e,c.businessIdentity,scope);
for f=fields
    if ~isempty(c.(f{1}))
        assert(strcmp(c.(f{1}),b.(f{1})),'SHT:F3Task:BusinessConflict','配置%s与证据冲突。',f{1});
    end
end
if strcmp(c.taskPurpose,'model_build')
    assert(~strcmp(b.modelId,b.parentModelId),'SHT:F3Task:ParentRelation','模型不能以自己作为父。');
end
if ~isempty(fieldnames(c.parentRelation))
    r=c.parentRelation;local_relation(r);
    assert(strcmp(r.source,p.source)&&strcmp(r.route,p.route)&&strcmp(r.modelId,b.parentModelId), ...
        'SHT:F3Task:ParentRelation','实际父不符合已确认关系。');
    if isfield(facts,'sortie_id')
        assert(strcmp(r.sortieId,facts.sortie_id),'SHT:F3Task:ParentRelation','实际父架次与声明冲突。');
    end
    % 旧父无架次字段时仍保留明确声明依据，不把当前架次写成父架次。
    b.parentRelation=r;
end
end

function out=local_bind_parent(u)
required={'intentFile','parentSource','parentRoute','parentWorkbook','outputRoot','reportRoot'};
allowed=[required,{'parentRuntimeBinding','parentDefinition','businessIdentity'}];
assert(isstruct(u)&&isscalar(u)&&all(isfield(u,required))&&all(ismember(fieldnames(u),allowed)), ...
    'SHT:F3Task:BindConfig','bindParent须提供意图文件、真实父选择及独立新输出/报告根。');
file=local_absolute(u.intentFile);saved=load(file,'intent');intent=saved.intent;
assert(strcmp(intent.schemaVersion,'F3_DATA_INTENT_B1_V1')&& ...
    strcmp(intent.identity,local_digest(rmfield(intent,'identity'))), ...
    'SHT:F3Task:IntentChanged','意图载荷身份不符。');
task=intent.task;local_verify_payload(task);old=task.configuration;
check=local_check(old,true);
assert(strcmp(check.identity,task.identity),'SHT:F3Task:StaleData', ...
    '原数据、映射、算法设置或来源源码已经改变，必须重新确认数据意图。');
c=old;
for key={'parentSource','parentRoute','parentWorkbook','outputRoot','reportRoot', ...
        'parentRuntimeBinding','parentDefinition','businessIdentity'}
    if isfield(u,key{1}),c.(key{1})=u.(key{1});end
end
assert(strcmp(c.parentSource,intent.parentRelation.source)&&strcmp(c.parentRoute,intent.parentRelation.route), ...
    'SHT:F3Task:ParentRelation','实际父来源/路线不同于原意图。');
c.dataIntent=struct('file',file,'sha256',local_hash(file));c=local_config(c);
for r={c.outputRoot,c.reportRoot}
    assert(~local_overlap(r{1},old.outputRoot)&&~local_overlap(r{1},old.reportRoot)&& ...
        ~isfolder(r{1})&&~isfile(r{1}),'SHT:F3Task:BindingRoot', ...
        '绑定必须使用独立新目录，不覆盖意图或之前的绑定。');
end
check=local_check(c);b=local_business(c,check.parent);
fields={'engineId','sortieId','parentModelId','modelId'};
if strcmp(c.taskPurpose,'uq_assessment'),fields{4}='parentPosteriorId';end
for f=fields
    assert(strcmp(b.(f{1}),intent.businessIdentity.(f{1})), ...
        'SHT:F3Task:BusinessConflict','绑定的%s与原意图不同。',f{1});
end
% 复用已确认原窗口及完整测量，不重新选段；只补真实父及执行身份。
task.configuration=c;task.identity=check.identity;task.sourceContract=check.contract;task.parent=check.parent;
task.result.options.priorSource=c.parentSource;task.result.options.priorRoute=c.parentRoute;
task.result.options.priorWorkbook=c.parentWorkbook;
task.parameterStatus=local_parameter_status(check.parent.schedule,c,task.result.datasets(1));
task.payloadIdentity=local_payload_hash(task);local_own_roots(c);
out=local_confirm(task,intent.selection,c);
out.confirmationFile=fullfile(c.outputRoot,'confirmations',out.selectionIdentity(1:16),'confirmation_receipt.mat');
out.dataIntentSha256=c.dataIntent.sha256;out.dataIntentFile=file;
end

function e=local_unbound_estimate(task,selection,c)
% 未知父节点不能套17/30维。只用合同容量给宽工程界，不作为可执行估时。
[r,~]=local_select(task.result,selection,c);d=r.datasets(1);seg=d.segmentation.segments;
points=nnz(seg.usable & string(seg.segment_class)=="steady_window");
path=fullfile(fileparts(mfilename('fullpath')),'TestData','runtime_cost_baselines','F3_R2019b_cost_v1.json');
b=jsondecode(fileread(path));unit=b.referenceJacobianSeconds(:)'/(b.referencePointCount*(b.referenceParameterCount+1));
unit=[min(unit),max(unit)].*b.loadAllowance(:)';mult=[1,1];
if strcmp(c.modelRoute,'steady'),mult=b.routes.steadyPointMultiplier(:)';end
cap=257;if strcmp(c.parameterSetId,'set2'),cap=322;end
if strcmp(c.scheduleParameterization,'family_amplitude')
    cap=9;if strcmp(c.parameterSetId,'set2'),cap=12;end
end
steps=0;segments=0;
if strcmp(c.dataMethod,'steady_plus_small_history')
    plan=d.localSmallThermalPlan;segments=height(plan);
    steps=sum(ceil((plan.fit_end_s-plan.initialization_start_s)/c.integrationStep_s));
end
one=points*unit.*mult+steps*b.routes.historyStepSeconds(:)'+segments*unit.*b.routes.steadyPointMultiplier(:)';
vectors=[(1+1)*(1+1)+4+4,(10+1)*(cap+1)+4*10+4];
e=struct('status','unbound_capacity_envelope_not_executable','parameterCount',[], ...
    'parameterCapacityUpperBound',cap,'iterationAssumption',[1,10], ...
    'trainingComputeRange_s',one.*vectors+b.setupAllowance_s(:)'+b.exportAllowance_s(:)', ...
    'baselineSha256',local_hash(path),'baselineVersion',b.version, ...
    'assumptions','尚无真实父；按最多32节点合同及1至10轮给宽范围。绑定后必须重新estimate。', ...
    'exclusions','不含独立测试、R1初猜连续回放、冷启动或暂停；不是执行时间承诺');
end

function h=local_digest(value)
h=sht_f33_model_adapt_v2('structHash',value);
end

function out=local_execution(action,u)
% 结果查看只消费自包含结果目录；不重新要求训练、父文件、MAT或DLL。
if ismember(action,{'status','readresult','requestpause'})
    assert(isstruct(u)&&isscalar(u)&&isequal(fieldnames(u),{'resultDirectory'}), ...
        'SHT:F3Task:ReadConfig','只读动作只需resultDirectory。');
    directory=local_absolute(u.resultDirectory);
    if strcmp(action,'requestpause')
        assert(isfile(fullfile(directory,'run_control','identity.mat')), ...
            'SHT:F3Task:OldCheckpoint','该旧任务没有当前安全停续协议。');
        out=sht_tc24_run_control('requeststop',directory);return;
    elseif strcmp(action,'status')
        file=fullfile(directory,'f3_status.json');
        assert(isfile(file),'SHT:F3Task:StatusMissing','尚无本任务状态文件。');
        out=local_normalize_status(local_read_json(file),directory);
        out.processLivenessChecked=false; % 最后保存状态，不把旧running当作活进程。
    else
        out=local_read_result(directory);
    end
    return;
end
clock=tic;startedAt=now;
resuming=strcmp(action,'resume');
[c,receipt,check]=local_execution_config(u,resuming);
history=readtable(receipt.trainingWorkbook,'Sheet','history');
segments=readtable(receipt.trainingWorkbook,'Sheet','segments');
if ~ismember('Mkg',history.Properties.VariableNames),history.Mkg=zeros(height(history),1);end
options=struct('modelMode',0,'modelRoute',receipt.configuration.modelRoute, ...
    'dataMethod',receipt.configuration.dataMethod, ...
    'parameterSet',receipt.configuration.parameterSetId, ...
    'scheduleParameterization',receipt.configuration.scheduleParameterization, ...
    'regularizationWeight',receipt.configuration.regularizationStrength, ...
    'historyIntegrationStep_s',receipt.configuration.integrationStep_s, ...
    'priorSource',receipt.parent.source,'priorRoute',receipt.parent.route, ...
    'priorWorkbook',receipt.parent.file,'priorRuntimeBinding',receipt.configuration.parentRuntimeBinding, ...
    'priorDefinition',check.contract.configuration.parentDefinition, ...
    'trainingWorkbook',receipt.trainingWorkbook, ...
    'stage32File',receipt.stage32File,'resultTag',c.runId, ...
    'outputRoot',c.outputRoot,'reportRoot',c.reportRoot, ...
    'comparisonCacheDirectory',fullfile(c.outputRoot,'history_cache'), ...
    'maximumIterations',c.maximumIterations,'plotEnabled',c.plotEnabled,'saveEnabled',true, ...
    'progressFile',fullfile(c.outputRoot,'f3_status.json'),'outputNaming','compact');
if isfield(check,'businessIdentity')
    options.businessIdentity=check.businessIdentity;options.businessRunId=c.runId;
end
planned=sht_f33_model_adapt_v2('outputPaths',options);
local_output_path_check(planned,c);
evidence=sht_f33_model_adapt_v2('prepareEvidence',history,segments,options);
testCount=0;testWork=struct('historyStepCount',0,'historySegmentCount',0);
if ~isempty(receipt.validationWorkbook)
    seg=readtable(receipt.validationWorkbook,'Sheet','segments');
    testCount=nnz(string(seg.segment_class)=="steady_window" & logical(seg.usable));
    htest=readtable(receipt.validationWorkbook,'Sheet','history');
    if ~ismember('Mkg',htest.Properties.VariableNames),htest.Mkg=zeros(height(htest),1);end
    etest=sht_f33_model_adapt_v2('prepareEvidence',htest,seg,options);
    testWork=local_history_work(etest,options);
end
options.runtimeEstimateTestWork=testWork;
options.runtimeEstimateTrainingReplay_s=history.time_s(end)-history.time_s(1);
estimate=sht_f3_runtime_estimate(receipt.parent.schedule,evidence,c.maximumIterations,testCount,[],options);
options.runtimeEstimateTestPoints=testCount;
out=struct('schemaVersion','F3_STEADY_EXECUTION_PLAN_R042','runId',c.runId, ...
    'options',options,'estimate',estimate,'confirmationIdentity',receipt.receiptIdentity, ...
    'sourceIdentity',check.contract.sourceIdentity,'noDll',true, ...
    'validationProvided',~isempty(receipt.validationWorkbook), ...
    'pauseSupported',true,'resumeSupported',true,'plannedOutputs',planned);
identity=local_execution_identity(c,receipt,check,options);
out.executionIdentity=identity;
if strcmp(action,'estimate'),return;end
options.progressStartedAt=startedAt;out.options=options;
% 新建与恢复明确分开；恢复必须保持数据、先验、数值配置及真实源码身份。
if ~resuming,mkdir(c.outputRoot);mkdir(c.reportRoot);end
local_write_probe(c.outputRoot);local_write_probe(c.reportRoot);
if ~resuming,local_json(fullfile(c.outputRoot,'f3_execution_plan.json'),out);end
control=sht_tc24_run_control('open',struct('directory',c.outputRoot,'runId',c.runId, ...
    'resume',resuming,'timer',clock,'sessionStartDatenum',startedAt),identity);
cleanup=onCleanup(@()local_abandoned_session(control)); %#ok<NASGU>
options.runControl=control;
fprintf('预计计算及导出 %.1f 至 %.1f 分钟；实际维数将在覆盖检查后确定。\n', ...
    estimate.totalRange_s/60);
try
    local_status(c,'running','preparing',false,struct(),'正在准备或恢复已核验的安全状态');
    result=sht_f33_model_adapt_v2('runroute',options);
    revisedEstimate=sht_f3_runtime_estimate(receipt.parent.schedule,evidence, ...
        c.maximumIterations,testCount,height(result.parameterContract),options);
    validationClock=tic;
    try
        validation=sht_f33_independent_evidence_validation('confirmedPoints', ...
            struct('result',result,'validationWorkbook',receipt.validationWorkbook));
    catch failure
        % 测试失败不抹去已经完成的辨识，也不把失败当成通过。
        validation=struct('status','failed','message',failure.message, ...
            'identifier',failure.identifier,'metricTable',table(),'pointTable',table(), ...
            'valid',false,'fitRepeated',false);
    end
    validationTime=toc(validationClock);
    exportClock=tic;
    file=result.output.workbook;
    states=local_final_states(receipt.parameterStatus,result);
    writetable(states,file,'Sheet','all_parameter_states');
    points=local_point_results(result);
    writetable(points,file,'Sheet','training_predictions');
    if ~isempty(validation.metricTable),writetable(validation.metricTable,file,'Sheet','validation_metrics');end
    if ~isempty(validation.pointTable),writetable(validation.pointTable,file,'Sheet','validation_predictions');end
    if isfield(validation,'historyTable')&&~isempty(validation.historyTable)
        writetable(validation.historyTable,file,'Sheet','validation_small_history');
    end
    timings=struct('coreCompute_s',result.timing.coreCompute_s, ...
        'coreExport_s',result.timing.coreExport_s,'validation_s',validationTime, ...
        'taskExport_s',toc(exportClock),'endToEnd_s',toc(clock));
    files=struct('role',{},'path',{},'sha256',{});
    for role={'model','results'}
        if strcmp(role{1},'model'),p=result.output.formalWorkbook;else,p=file;end
        assert(startsWith(lower(p),lower([c.outputRoot filesep])),'SHT:F3Task:OutputEscape','导出路径越界。');
        files(end+1)=struct('role',role{1},'path',p(numel(c.outputRoot)+2:end), ...
            'sha256',local_hash(p)); %#ok<AGROW>
    end
    manifestOptions=options;manifestOptions.runControl=[];
    combined=fullfile(fileparts(result.output.formalWorkbook),'combined_model.xlsx');
    if isfile(combined)
        combo=sht_f33_transient_delivery('inspect',[],combined);
        for item={{'combinedModel',combined},{'combinedSteady',combo.steadyFile}}
            z=item{1};p=z{2};
            assert(startsWith(lower(p),lower([c.outputRoot filesep])),'SHT:F3Task:OutputEscape','组合导出越界。');
            files(end+1)=struct('role',z{1},'path',p(numel(c.outputRoot)+2:end),'sha256',local_hash(p)); %#ok<AGROW>
        end
    end
    manifest=struct('schemaVersion','F3_STEADY_RESULT_R042','runId',c.runId, ...
        'resultAvailable',true,'converged',result.converged,'stopReason',result.stopReason, ...
        'iterationCount',height(result.iterationTable),'parameterCount',height(result.parameterTable), ...
        'priorObjective',result.priorObjective,'finalObjective',result.finalObjective, ...
        'maximumProjectedScaledGradient',result.finalLinearization.maximumProjectedScaledGradient, ...
        'estimate',estimate,'revisedEstimate',revisedEstimate,'timing',timings,'files',files,'createdAt',datestr(now,31), ...
        'configuration',manifestOptions,'sourceIdentity',check.contract.sourceIdentity, ...
        'executionIdentityHash',control.identityHash, ...
        'confirmationIdentity',receipt.receiptIdentity,'parentSha256',receipt.parent.sha256, ...
        'validationStatus',validation.status,'validationValid',validation.valid, ...
        'uqAvailable',false,'truthUsed',false,'testDataUsedForFit',false, ...
        'parameterMeaning','parameters表为节点改变量，all_parameter_states为完整物理系数', ...
        'channelMeaning',local_channel_meaning(options));
    if isfield(check,'businessIdentity'),manifest.businessIdentity=check.businessIdentity;end
    if isfield(receipt.parent,'definitionAssociation')
        manifest.parentDefinitionAssociation=receipt.parent.definitionAssociation;
    end
    if isfield(validation,'message'),manifest.validationMessage=validation.message;end
    local_json(fullfile(c.outputRoot,'f3_result_manifest.json'),manifest);
    out=local_read_result(c.outputRoot);
    timings.taskExport_s=toc(exportClock);timings.endToEnd_s=toc(clock);
    timings.boundary='截至结果Excel回读核验；不含最后计时/状态JSON刷写、MATLAB启动及界面渲染';
    timings.currentSession_s=toc(clock);
    timings.activeSeconds=control.priorActiveSeconds+toc(clock);
    timings.pausedSeconds=control.priorPausedSeconds;
    manifest.timing=timings;local_json(fullfile(c.outputRoot,'f3_result_manifest.json'),manifest);
    sht_tc24_run_control('finish',control,'completed');
    local_status(c,'completed','saved',true,timings,result.stopReason);
    out.manifest=manifest;
catch failure
    if strcmp(failure.identifier,'TC24:Control:Stopped')
        saved=sht_tc24_run_control('state',c.outputRoot);
        local_status(c,'safePaused','safe_checkpoint',false, ...
            struct('activeSeconds',saved.activeSeconds,'pausedSeconds',saved.pausedSeconds),failure.message);
        out=local_normalize_status(local_read_json(fullfile(c.outputRoot,'f3_status.json')),c.outputRoot);
        return;
    end
    sht_tc24_run_control('finish',control,'failed');
    local_status(c,'failed','failed',false,struct('endToEnd_s',toc(clock)),failure.message);
    rethrow(failure);
end
end

function [c,r,check]=local_execution_config(u,resuming)
c=struct('confirmationFile','','runId','','outputRoot','','reportRoot','', ...
    'maximumIterations',10,'plotEnabled',false);
assert(isstruct(u)&&isscalar(u)&&all(ismember(fieldnames(u),fieldnames(c))), ...
    'SHT:F3Task:ExecutionConfig','辨识配置含未知字段。');
for name=fieldnames(u).',c.(name{1})=u.(name{1});end
assert(~isempty(regexp(char(c.runId),'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$','once')), ...
    'SHT:F3Task:RunId','runId必须是显式的新批次编号。');
validateattributes(c.maximumIterations,{'numeric'},{'scalar','integer','>=',1,'<=',10});
validateattributes(c.plotEnabled,{'logical'},{'scalar'});
for name={'confirmationFile','outputRoot','reportRoot'},c.(name{1})=local_absolute(c.(name{1}));end
assert(isfile(c.confirmationFile),'SHT:F3Task:ConfirmationMissing','请先完成A数据确认。');
s=load(c.confirmationFile,'receipt');assert(isfield(s,'receipt'),'SHT:F3Task:Receipt','确认文件内容无效。');r=s.receipt;
assert(strcmp(r.schemaVersion,'F3_STEADY_TASK_CONFIRMATION_R041')&& ...
    strcmp(r.receiptIdentity,local_digest(rmfield(r,'receiptIdentity'))), ...
    'SHT:F3Task:Receipt','确认载荷或身份无效，禁止重签旧确认文件。');
local_verify_delivery(r);
a=local_config(r.configuration);
assert(strcmp(a.taskPurpose,'model_build'),'SHT:F3Task:AssessmentNotEstimation', ...
    '该确认仅用于现有模型不确定性评估，不能送入确定性辨识；不会创建伪子模型。');
assert(ismember(a.modelRoute,{'steady','transient_instant'})&& ...
    ismember(a.dataMethod,{'steady_only','steady_plus_small_history'})&& ...
    ismember(a.parameterSetId,{'set1','set2'})&& ...
    ismember(a.scheduleParameterization,{'independent_nodes','family_amplitude'}), ...
    'SHT:F3Task:BRoute','确认的路线或参数化不受支持；不得静默改为R2。');
check=local_check(a);
assert(strcmp(check.identity,r.identity),'SHT:F3Task:StaleConfirmation', ...
    '输入、父模型、资产或源码已改变，请在新目录重新预览确认，不能反复运行旧批次。');
b=a;b.outputRoot=c.outputRoot;b.reportRoot=c.reportRoot;
b.identificationFile=r.trainingWorkbook;b.validationFile=r.validationWorkbook;local_safe_roots(b);
for root={c.outputRoot,c.reportRoot}
    assert(~local_overlap(root{1},a.outputRoot)&&~local_overlap(root{1},a.reportRoot), ...
        'SHT:F3Task:InputOutputOverlap','辨识输出不得覆盖预处理目录。');
    if resuming
        assert(isfolder(root{1}),'SHT:F3Task:ResumeDirectory','恢复目录不存在。');
    else
        assert(~isfolder(root{1})&&~isfile(root{1}),'SHT:F3Task:ExistingRun', ...
            '辨识目录已存在；查看结果、显式resume同一安全状态或使用新批次。');
    end
end
if resuming
    assert(isfile(fullfile(c.outputRoot,'run_control','identity.mat')), ...
        'SHT:F3Task:OldCheckpoint','该目录没有当前停续协议；旧确认/检查点不能重签。');
    assert(~isfile(fullfile(c.outputRoot,'f3_result_manifest.json')), ...
        'SHT:F3Task:AlreadyCompleted','结果已经发布，请使用readResult，不重复恢复。');
    for name={'result.mat','delivery/model.xlsx','delivery/results.xlsx'}
        assert(~isfile(fullfile(c.outputRoot,name{1})),'SHT:F3Task:PartialPublication', ...
            '发现已开始发布的结果；保留原文件进行诊断，不自动覆盖或重算。');
    end
end
end

function w=local_history_work(e,o)
w=struct('historyStepCount',0,'historySegmentCount',e.historyMeta.segmentCount);
for j=1:numel(e.historyData.experiments)
    t=e.historyData.experiments(j).replayData.time_s;
    w.historyStepCount=w.historyStepCount+ceil((t(end)-t(1))/o.historyIntegrationStep_s);
end
end

function text=local_channel_meaning(o)
if strcmp(o.modelRoute,'steady')
    text='平均点Np/Ng、Pt3/Tt45为输出；独立测试点只用可测输入及模型名义初猜选根';
else
    text='平均点Np/Ng为瞬态时刻输入；Pt3/Tt45为输出；dNp/dt,dNg/dt为零加速度约束';
end
if strcmp(o.dataMethod,'steady_plus_small_history')
    text=[text,'；小幅历程逐状态积分，首条实测转速仅为动态初始条件，输出Np/Ng/Pt3/Tt45'];
end
end

function identity=local_execution_identity(c,r,check,options)
% 显式与静态调用依赖共同登记，仅核本项目M，不把未使用根DLL绑入隔离包。
entry={which('sht_f33_model_adapt_v2'),which('sht_f3_steady_task'), ...
    which('sht_f33_independent_evidence_validation')};
files=matlab.codetools.requiredFilesAndProducts(entry);
root=[fileparts(mfilename('fullpath')),filesep];
files=sort(unique(files(startsWith(lower(string(files)),lower(root)))));
sources=struct('file',{},'sha256',{});
for j=1:numel(files)
    [~,~,ext]=fileparts(files{j});if ~strcmpi(ext,'.m'),continue;end
    sources(end+1)=struct('file',files{j}(numel(root)+1:end),'sha256',local_hash(files{j})); %#ok<AGROW>
end
assert(~isempty(sources),'SHT:F3Task:ExecutionSources','执行源码依赖分析为空。');
identity=struct('schemaVersion','F3_B2_EXECUTION_R042','configuration',c, ...
    'confirmationIdentity',r.receiptIdentity,'inputContract',check.contract, ...
    'coreOptions',sht_f33_model_adapt_v2('options',options),'executionSources',sources, ...
    'trainingHash',local_hash(r.trainingWorkbook),'stage32Hash',local_hash(r.stage32File), ...
    'validationHash','','matlabRelease',version('-release'));
if ~isempty(r.validationWorkbook),identity.validationHash=local_hash(r.validationWorkbook);end
end

function local_abandoned_session(control)
% 只释放本会话持有的锁；不因另一个窗口查看状态而改变其运行。
try
    s=sht_tc24_run_control('state',control.directory);
    if strcmp(s.sessionToken,control.sessionToken)&&strcmp(s.status,'running')
        sht_tc24_run_control('finishsession',control.directory,control.sessionToken,'failed',control.timer);
    end
catch
    % 不让清理异常替换最初的业务错误；锁保留时必须人工核原进程。
end
end

function states=local_final_states(states,r)
% 完整父字典仍可查看；只把实际释放节点标为estimated，区间保持缺失。
for i=1:height(states)
    h=states.c_index(i);node=states.node_index(i);v=states.prior_value(i);
    if h>=0
        e=find([r.finalSchedule.healthEntries.cIndex]==h,1);
        if isempty(e),v=r.finalSchedule.designHealth(h+1);else,v=r.finalSchedule.healthEntries(e).kNodes(node);end
        match=r.parameterContract.c_index==h & r.parameterContract.node_index==node;
        if strcmp(r.scheduleParameterization,'family_amplitude')
            match=r.coverageTable.c_index==h & r.coverageTable.node_index==node & r.coverageTable.active;
        end
    elseif h==-1
        v=r.finalSchedule.fuelBias.biasNodes(node);
        match=startsWith(r.parameterContract.kind,'fuel_bias_') & r.parameterContract.node_index==node;
        if strcmp(r.scheduleParameterization,'family_amplitude')
            match=r.fuelBiasCoverageTable.node_index==node & r.fuelBiasCoverageTable.active;
        end
    else
        v=r.estimatedKdistEq;match=r.parameterContract.kind=="sortie_nuisance";
    end
    states.estimate(i)=v;
    if any(match),states.participation(i)="estimated";
    elseif startsWith(states.participation(i),'pending')||contains(states.participation(i),'input_support')
        states.participation(i)="held_no_released_support";
    end
end
end

function t=local_point_results(r)
rows=cell(2,1);
for k=1:2
    if k==1,e=r.priorEvaluation.candidate;name="prior";else,e=r.finalEvaluation.candidate;name="estimated";end
    t=e.steadyPrediction;t.model=repmat(name,height(t),1);
    t.point_id=r.training.steadyWindowTable.point_id;
    rows{k}=t;
end
t=vertcat(rows{:});
end

function out=local_read_result(directory,readValidation)
if nargin<2,readValidation=true;end
file=fullfile(directory,'f3_result_manifest.json');
assert(isfile(file),'SHT:F3Task:ResultMissing','无完整辨识结果清单，不能把预处理结果当辨识结果。');
m=local_read_json(file);
assert(strcmp(m.schemaVersion,'F3_STEADY_RESULT_R042')&&m.resultAvailable, ...
    'SHT:F3Task:ResultSchema','保存结果合同不支持或无有效结果。');
paths=struct();
for k=1:numel(m.files)
    f=m.files(k);p=char(java.io.File(fullfile(directory,f.path)).getCanonicalPath());
    assert(startsWith(lower(p),lower([directory filesep])),'SHT:F3Task:ResultEscape','结果相对路径越界。');
    assert(isfile(p)&&strcmpi(local_hash(p),f.sha256),'SHT:F3Task:ResultChanged','结果缺失或SHA不符：%s',f.path);
    assert(ismember(f.role,{'model','results','combinedModel','combinedSteady'})&&~isfield(paths,f.role), ...
        'SHT:F3Task:ResultSchema','结果角色重复或无效。');
    paths.(f.role)=p;
end
assert(isfield(paths,'model')&&isfield(paths,'results'),'SHT:F3Task:ResultSchema','缺少模型或完整结果Excel。');
out=struct('manifest',m,'paths',paths,'model',sht_f33_excel_delivery('inspect',paths.model), ...
    'parameters',readtable(paths.results,'Sheet','parameters'), ...
    'parameterStates',readtable(paths.results,'Sheet','all_parameter_states'), ...
    'trainingMetrics',readtable(paths.results,'Sheet','fit_metrics'), ...
    'trainingPredictions',readtable(paths.results,'Sheet','training_predictions'), ...
    'iterations',readtable(paths.results,'Sheet','iterations'), ...
    'validationMetrics',table(),'validationPredictions',table(),'validationSmallHistory',table(), ...
    'noDll',true,'runtimeCompatibilityChecked',false,'uqAvailable',false);
assert(height(out.parameters)==m.parameterCount&&any(string(out.parameters.unit)=="kg/s"), ...
    'SHT:F3Task:Parameters','完整参数结果缺失或没有燃油偏置。');
out.combinedModel=[];
if isfield(paths,'combinedModel')
    out.combinedModel=sht_f33_transient_delivery('inspect',[],paths.combinedModel);
end
[~,sheets]=xlsfinfo(paths.results);
if readValidation&&ismember('validation_metrics',sheets),out.validationMetrics=readtable(paths.results,'Sheet','validation_metrics');end
if readValidation&&ismember('validation_predictions',sheets),out.validationPredictions=readtable(paths.results,'Sheet','validation_predictions');end
if readValidation&&ismember('validation_small_history',sheets)
    out.validationSmallHistory=readtable(paths.results,'Sheet','validation_small_history');
end
end

function local_status(c,state,phase,available,timing,message)
v=struct('schemaVersion','F3_STEADY_PROGRESS_R042','runId',c.runId,'status',state, ...
    'phase',phase,'resultAvailable',available,'timing',timing,'message',message, ...
    'updatedAt',datestr(now,31),'pauseSupported',false,'resumeSupported',false);
previousFile=fullfile(c.outputRoot,'f3_status.json');
if isfile(previousFile)
    previous=local_read_json(previousFile);
    for f={'iteration','maximumIterations','objective','estimate','revisedEstimate'}
        if isfield(previous,f{1}),v.(f{1})=previous.(f{1});end
    end
end
v=local_normalize_status(v,c.outputRoot);
local_json(fullfile(c.outputRoot,'f3_status.json'),v);
end

function v=local_normalize_status(v,directory)
% 稳定返回合同；未知不是0，最后记录的running也不是进程存活证明。
defaults=struct('iteration',NaN,'maximumIterations',NaN,'objective',NaN, ...
    'estimate',struct(),'revisedEstimate',struct(),'timing',struct(), ...
    'pauseSupported',false,'resumeSupported',false,'resultAvailable',false);
for f=fieldnames(defaults).'
    if ~isfield(v,f{1})||isempty(v.(f{1})),v.(f{1})=defaults.(f{1});end
end
file=fullfile(directory,'f3_execution_plan.json');
if isfile(file)
    plan=local_read_json(file);
    v.estimate=plan.estimate;
    v.maximumIterations=plan.options.maximumIterations;
end
v.elapsedAtLastUpdate_s=NaN;
if isfield(v.timing,'endToEnd_s'),v.elapsedAtLastUpdate_s=v.timing.endToEnd_s;
elseif isfield(v.timing,'elapsedAtUpdate_s'),v.elapsedAtLastUpdate_s=v.timing.elapsedAtUpdate_s;end
if isfile(fullfile(directory,'run_control','state.mat'))
    s=sht_tc24_run_control('state',directory);
    v.pauseSupported=true;v.resumeSupported=true;
    v.safeStopConfirmed=strcmp(s.status,'stopped');
    v.checkpointAvailable=s.checkpointAvailable;v.safePoint=s.safePoint;
    v.controlStatus=s.status;v.elapsedAtLastUpdate_s=s.activeSeconds;
    v.timing.activeSeconds=s.activeSeconds;v.timing.pausedSeconds=s.pausedSeconds;
    v.timing.currentSessionSeconds=s.currentSessionSeconds;
    v.resumeAvailable=ismember(s.status,{'stopped','failed','partial'})&&s.checkpointAvailable&& ...
        ~isfile(fullfile(directory,'run_control','session.lock'))&&~v.resultAvailable;
    for n={'result.mat','delivery/model.xlsx','delivery/results.xlsx'}
        if isfile(fullfile(directory,n{1})),v.resumeAvailable=false;end
    end
    if isfield(s.progress,'iteration'),v.iteration=s.progress.iteration;end
    if v.safeStopConfirmed,v.status='safePaused';end
end
v.processLivenessChecked=false;
end

function local_output_path_check(planned,c)
% 留出原子临时文件的余量，不依赖系统或Excel对长路径的非一致支持。
files={fullfile(c.outputRoot,'f3_execution_plan.json'), ...
    fullfile(c.outputRoot,'f3_result_manifest.json'),fullfile(c.outputRoot,'f3_status.json')};
for key=fieldnames(planned).'
    value=planned.(key{1});if ischar(value)&&~isempty(value),files{end+1}=value;end %#ok<AGROW>
end
for i=1:numel(files)
    assert(numel(files{i})<=240,'SHT:F3Task:OutputPathLength', ...
        '计划输出路径%d字符，超过本R2019b接口240字符安全限制：%s。请选择较短输出根目录。', ...
        numel(files{i}),files{i});
end
end

function local_write_probe(directory)
% 只在run已新建的本批目录中核实可写，不在estimate中暗写或调用DLL。
file=[tempname(directory),'.probe'];fid=fopen(file,'w');
assert(fid>=0,'SHT:F3Task:OutputNotWritable','输出目录不可写：%s。',directory);
fclose(fid);delete(file);
end

function out=local_uq(action,u)
% 新推断使用当前源码；查看冻结Excel不依赖原训练MAT，也不打开DLL。
if ismember(action,{'uqstatus','uqrequestpause'})
    assert(isstruct(u)&&isfield(u,'outputRoot'),'SHT:F3UQ:ControlPath','需提供本次outputRoot。');
    directory=local_absolute(u.outputRoot);
    assert(isfile(fullfile(directory,'f3_uq_execution_plan.json')), ...
        'SHT:F3UQ:ControlIdentity','该目录不是本入口登记的UQ任务。');
    if strcmp(action,'uqrequestpause')
        out=sht_tc24_run_control('requeststop',directory);
    else
        out=sht_tc24_run_control('state',directory);
        out.processLivenessVerified=false;
        out.statusMeaning='持久化状态不等于实时进程存活；暂停以安全点确认为准';
    end
    return;
end
if strcmp(action,'uqread')
    assert(isfield(u,'workbook')&&isfile(u.workbook),'SHT:F3UQ:Workbook','需指定正式Excel。');
    out=sht_f34_deployment('inspect',u.workbook);return;
end
if isfield(u,'modelWorkbook')
    out=local_independent_uq(action,u);return;
end
resuming=strcmp(action,'uqresume');
c=struct('resultDirectory','','confirmationFile','','sourceStage','2p4', ...
    'sourceWorkbook','','method','D','runTag','','outputRoot','','reportRoot','', ...
    'options',struct(),'businessIdentity',struct());
assert(isstruct(u)&&isscalar(u)&&all(ismember(fieldnames(u),fieldnames(c))), ...
    'SHT:F3UQ:Config','UQ任务包含未知配置。');
for f=fieldnames(u).',c.(f{1})=u.(f{1});end
assert(ismember(c.method,{'C','D'})&&ismember(c.sourceStage,{'2p4','2p7'}), ...
    'SHT:F3UQ:Method','本入口只支持台架到飞行的C或D。');
assert(~isempty(regexp(char(c.runTag),'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$','once')), ...
    'SHT:F3UQ:RunTag','需给出新的runTag。');
for f={'resultDirectory','confirmationFile','sourceWorkbook','outputRoot','reportRoot'}
    assert(~isempty(c.(f{1})),'SHT:F3UQ:Required','必须提供%s。',f{1});
    c.(f{1})=local_absolute(c.(f{1}));
end
b=local_read_result(c.resultDirectory,false);
q=load(c.confirmationFile,'receipt');r=q.receipt;
assert(strcmp(r.receiptIdentity,local_digest(rmfield(r,'receiptIdentity')))&& ...
    strcmp(r.receiptIdentity,b.manifest.confirmationIdentity), ...
    'SHT:F3UQ:Confirmation','A确认载荷与B不是同一份证据，禁止重签。');
local_verify_delivery(r);
assert(strcmp(b.manifest.parentSha256,r.parent.sha256), ...
    'SHT:F3UQ:Parent','确定性父模型身份不一致。');
file=fullfile(c.resultDirectory,'result.mat');q=load(file,'result');v=q.result;
assert(v.options.modelMode==0&&strcmp(v.options.dataMethod,'steady_only')&& ...
    strcmp(v.options.parameterSet,'set1')&&strcmp(v.options.scheduleParameterization,'independent_nodes'), ...
    'SHT:F3UQ:Route','当前任务支持三部件set1独立节点的平均点C/D，混合模式仅预留。');
assert(strcmp(local_hash(r.trainingWorkbook),v.training.sourceSha256), ...
    'SHT:F3UQ:Training','B冻结训练与A交付不一致。');
assert(isequal(string(v.parameterTable.parameter_id),string(b.parameters.parameter_id))&& ...
    max(abs(v.parameterTable.estimate-b.parameters.estimate))<1e-12&& ...
    height(v.parameterContract)==b.manifest.parameterCount, ...
    'SHT:F3UQ:Parameters','MAT与已核Excel参数结果不一致。');
% Excel只保留可执行模型；逐项比较数值而非文件生成日期。
comparisonSchedule=b.model.schedule;
if ~isempty(b.combinedModel),comparisonSchedule.designHealth(59:71)=b.combinedModel.parameters.value;end
assert(local_uq_schedule_equal(v.finalSchedule,comparisonSchedule)&& ...
    abs(v.estimatedKdistEq-b.model.KdistEq)<1e-12, ...
    'SHT:F3UQ:Model','MAT最终模型与正式Excel不一致。');
plan=local_read_json(fullfile(c.resultDirectory,'f3_execution_plan.json'));
% 包装器允许演进，旧B的物理/数值依赖仍须逐项一致，不能笼统忽略源码。
permitted={'sht_f3_steady_task.m','Start_FlightModelAdapt_14_SteadyTask.m', ...
    'sht_f3_runtime_estimate.m'};
sources=plan.executionIdentity.executionSources;
for j=1:numel(sources)
    if ismember(sources(j).file,permitted),continue;end
    current=fullfile(fileparts(mfilename('fullpath')),sources(j).file);
    assert(isfile(current)&&strcmpi(local_hash(current),sources(j).sha256), ...
        'SHT:F3UQ:ReferenceSource','原B物理或数值源码改变：%s。需显式兼容验证，不可直接复用旧B。',sources(j).file);
end
a=sht_f3_three_component_assets('verifyRuntime');
release=sht_f3_three_component_assets('manifest',a.runtime);
assert(strcmp(release.sha256, ...
    plan.executionIdentity.inputContract.runtimeManifestSha256), ...
    'SHT:F3UQ:Runtime','当前运行包与原B物理合同不同。');
assert(strcmp(local_hash(r.stage32File),plan.executionIdentity.stage32Hash), ...
    'SHT:F3UQ:Preprocessing','B所用测量误差先验或预处理载荷发生变化。');
roots=r.configuration;roots.outputRoot=c.outputRoot;roots.reportRoot=c.reportRoot;
roots.identificationFile=r.trainingWorkbook;roots.validationFile=r.validationWorkbook;
local_safe_roots(roots);
for destination={c.outputRoot,c.reportRoot}
    for old={c.resultDirectory,r.configuration.outputRoot,r.configuration.reportRoot, ...
            fileparts(c.sourceWorkbook),fileparts(c.confirmationFile)}
        assert(~local_overlap(destination{1},old{1}),'SHT:F3UQ:PathOverlap','新目录不能覆盖输入或旧结果。');
    end
    if resuming
        assert(isfolder(destination{1}),'SHT:F3UQ:ResumeMissing','同批恢复目录缺失。');
    else
        assert(~isfolder(destination{1})&&~isfile(destination{1}), ...
            'SHT:F3UQ:ExistingRun','该UQ目录已存在；请read或显式resume，不能包装成新任务。');
    end
end
o=c.options;
assert(isstruct(o)&&isscalar(o),'SHT:F3UQ:Options','options必须为标量结构体。');
if strcmp(c.method,'C')
    % 保持现行C入口的正式默认；有限验证预算须由用户显式给出。
    defaults=struct('methodCParticleCount',512,'methodCRepeatParticleCount',512, ...
        'methodCMoveSweeps',2,'methodCFinalMoveSweeps',4,'methodCIndependentMoveFraction',.2);
    for f=fieldnames(defaults).'
        if ~isfield(o,f{1}),o.(f{1})=defaults.(f{1});end
    end
end
locked={'referenceResultFile','modelMode','dataMethod','sourceStage','sourceWorkbook', ...
    'transitionMode','runTag','outputRoot','reportRoot','taskSourceIdentity', ...
    'runPrediction','runIndependentPrediction','runExport','runIndependentRepeat', ...
    'businessIdentity','parentModelId'};
assert(~any(ismember(fieldnames(o),locked)),'SHT:F3UQ:LockedOption','受控输入不能通过options覆盖。');
binding=local_uq_business_identity(c,r,b,o);
o.engineId=binding.engineId;o.sortieId=binding.sortieId;
o.parentModelId=binding.parentModelId;o.parentPosteriorId=binding.parentPosteriorId;
o.businessIdentity=binding;
o.referenceResultFile=file;o.modelMode=0;o.dataMethod='steady_only';
o.sourceStage=c.sourceStage;o.sourceWorkbook=c.sourceWorkbook;o.transitionMode='bench_to_flight';
o.runTag=c.runTag;o.outputRoot=c.outputRoot;o.reportRoot=c.reportRoot;
o.runPrediction=false;o.runIndependentPrediction=false;o.runExport=true;o.runIndependentRepeat=true;
o=sht_f34_contract('defaultOptions',o);
o.taskMethod=c.method;
% 从B实际覆盖表恢复数值坐标，仅用于无DLL合同/先验检查，不替代物理重建。
context=local_uq_numeric_context(v);
prior=sht_f34_prior('build',context,o);
identity=struct('schemaVersion','F3_UI_UQ_SOURCE_C1', ...
    'referenceMatSha256',local_hash(file),'bManifestSha256',local_hash(fullfile(c.resultDirectory,'f3_result_manifest.json')), ...
    'bModelSha256',local_hash(b.paths.model),'bResultsSha256',local_hash(b.paths.results), ...
    'confirmationIdentity',r.receiptIdentity,'confirmationFileSha256',local_hash(c.confirmationFile), ...
    'trainingSha256',local_hash(r.trainingWorkbook),'stage32Sha256',local_hash(r.stage32File), ...
    'sourcePosteriorSha256',local_hash(c.sourceWorkbook), ...
    'frozenBExecutionIdentity',b.manifest.executionIdentityHash, ...
    'runtimeManifestSha256',plan.executionIdentity.inputContract.runtimeManifestSha256, ...
    'currentUqImplementationSha256',sht_f34_contract('implementationHash'), ...
    'taskWrapperSha256',local_hash([mfilename('fullpath'),'.m']), ...
    'businessIdentityImplementationSha256',local_hash(which('sht_f3_business_identity')), ...
    'businessIdentity',binding, ...
    'physicalCoverageRebuilt',false,'benchFuelInherited',false,'testUsedInInference',false);
o.taskSourceIdentity=identity;
% 控制身份绑定实际数值与入口源码；不把控制对象混入概率options。
executionSources={'Start_FlightModelAdapt_15_UncertaintyTask.m', ...
    'Start_FlightModelUQ_R1_02_MethodD.m','Start_FlightModelUQ_R1_03_MethodC.m', ...
    'sht_f34_method_d.m','sht_f34_method_c.m','sht_f34_likelihood.m', ...
    'sht_tc24_run_control.m'};
executionHashes=cellfun(@(f)local_hash(which(f)),executionSources,'UniformOutput',false);
controlIdentity=struct('schema','F3_UQ_SAFE_CONTROL_C4','source',identity, ...
    'options',o,'method',c.method,'runTag',c.runTag, ...
    'outputRoot',c.outputRoot,'reportRoot',c.reportRoot, ...
    'files',{executionSources},'hashes',{executionHashes}, ...
    'matlabRelease',version('-release'),'architecture',computer('arch'));
if resuming
    assert(isfile(fullfile(c.outputRoot,'f3_uq_execution_plan.json'))&& ...
        isfile(fullfile(c.outputRoot,'run_control','identity.mat')), ...
        'SHT:F3UQ:ResumeProtocol','目录缺少本轮完整安全停续协议；旧结果可read，不能重签恢复。');
    old=local_read_json(fullfile(c.outputRoot,'f3_uq_execution_plan.json'));
    assert(strcmp(old.identityHash,local_digest(controlIdentity)), ...
        'SHT:F3UQ:ResumeIdentity','UQ数据/数值/随机/源码/路径身份改变；禁止续用或重签旧检查点。');
end
dimensions=struct('main',height(prior.parameterTable),'conditional',prior.shape.retainedRank, ...
    'steadyPoints',height(v.training.steadyWindowTable),'source','frozen_B_numeric_contract_no_DLL');
estimate=sht_f3_runtime_estimate('uq',dimensions,o);
out=struct('configuration',c,'options',o,'sourceIdentity',identity, ...
    'dimensions',dimensions,'estimate',estimate,'noDll',true, ...
    'deterministicConverged',b.manifest.converged,'validationAvailable',~isempty(r.validationWorkbook), ...
    'inferenceUsesTest',false,'physicalCoverageRebuilt',false,'prior',prior);
if ~ismember(action,{'uqrun','uqresume'}),return;end
out=local_uq_execute(c,o,controlIdentity,identity,binding,estimate,dimensions,resuming);
end

function out=local_uq_execute(c,o,controlIdentity,identity,binding,estimate,dimensions,resuming)
% 只有显式run进入现有物理算法；不会因check或estimate而创建桥接/缓存。
if isfield(dimensions,'isActual')&&~dimensions.isActual
    disp('以下维数是准备前容量上界；实际释放维数由物理准备阶段记录。');
end
fprintf('UQ粗估 %.1f 至 %.1f 分钟，%d主参数、%d条件参数；不包含独立预测。\n', ...
    estimate.totalRange_s/60,dimensions.main,dimensions.conditional);
timer=tic;
sht_f34_contract('reserve',o);
control=sht_tc24_run_control('open',struct('directory',c.outputRoot,'runId',c.runTag, ...
    'resume',resuming,'timer',timer),controlIdentity);
cleanup=onCleanup(@()local_abandoned_session(control)); %#ok<NASGU>
if ~resuming
    local_json(fullfile(c.outputRoot,'f3_uq_execution_plan.json'), ...
        struct('configuration',c,'identityHash',local_digest(controlIdentity), ...
        'identity',controlIdentity,'estimate',estimate));
end
try
    if strcmp(c.method,'D'),result=Start_FlightModelUQ_R1_02_MethodD(o,control);
    else,result=Start_FlightModelUQ_R1_03_MethodC(o,control);end
    if strcmp(c.method,'D'),workbook=result.artifacts.workbook;else,workbook=result.delivery.workbookFile;end
    record=struct('schemaVersion','F3_UI_UQ_RESULT_C1','method',c.method, ...
        'runTag',c.runTag,'sourceIdentity',identity,'resultAvailable',true, ...
        'workbook',workbook,'sha256',local_hash(workbook),'elapsed_s',toc(timer), ...
        'businessIdentity',binding, ...
        'newPosteriorStatisticallyCalibrated',false,'independentPredictionComputed',false);
    record.controlTiming=sht_tc24_run_control('finish',control,'completed');
    local_json(fullfile(c.outputRoot,'f3_uq_result_manifest.json'),record);
    out=result;
catch failure
    if strcmp(failure.identifier,'TC24:Control:Stopped')
        out=struct('status','paused','resultAvailable',false, ...
            'control',sht_tc24_run_control('state',c.outputRoot), ...
            'message',failure.message,'outputRoot',c.outputRoot);
        fprintf('%s\n',failure.message);return;
    end
    sht_tc24_run_control('finish',control,'failed');
    if isfolder(c.outputRoot)
        local_json(fullfile(c.outputRoot,'f3_uq_failure.json'), ...
            struct('message',failure.message,'identifier',failure.identifier,'elapsed_s',toc(timer)));
    end
    rethrow(failure);
end
end

function out=local_independent_uq(action,u)
% 与原同次辨识UQ共用运行控制和C/D核心；不要求result.mat或先重跑一次辨识。
c=struct('modelWorkbook','','confirmationFile','','sourceStage','2p4', ...
    'sourceWorkbook','','method','D','runTag','','outputRoot','','reportRoot','', ...
    'options',struct(),'businessIdentity',struct());
assert(isstruct(u)&&isscalar(u)&&all(ismember(fieldnames(u),fieldnames(c))), ...
    'SHT:F3UQ:Config','独立评估配置含未知字段。');
for f=fieldnames(u)',c.(f{1})=u.(f{1});end
assert(ismember(c.method,{'C','D'})&&ismember(c.sourceStage,{'2p4','2p7'}), ...
    'SHT:F3UQ:Method','保持当前台架到飞行C/D概率合同。');
assert(~isempty(regexp(c.runTag,'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$','once')), ...
    'SHT:F3UQ:RunTag','必须指定新runTag。');
for f={'modelWorkbook','confirmationFile','sourceWorkbook','outputRoot','reportRoot'}
    assert(~isempty(c.(f{1})),'SHT:F3UQ:Required','缺少%s。',f{1});c.(f{1})=local_absolute(c.(f{1}));
end
assert(isfile(c.modelWorkbook)&&isfile(c.confirmationFile)&&isfile(c.sourceWorkbook), ...
    'SHT:F3UQ:InputFile','模型、观测确认或概率先验Excel缺失。');
q=load(c.confirmationFile,'receipt');r=q.receipt;
assert(strcmp(r.receiptIdentity,local_digest(rmfield(r,'receiptIdentity'))), ...
    'SHT:F3UQ:Confirmation','观测确认载荷身份错误。');
local_verify_delivery(r);
assert(isfield(r.configuration,'taskPurpose')&&strcmp(r.configuration.taskPurpose,'uq_assessment'), ...
    'SHT:F3UQ:AssessmentPurpose', ...
    '独立评估须新建uq_assessment确认，不能把原确定性确认改签或冒充评估确认。');
assert(strcmpi(local_hash(c.modelWorkbook),r.parent.sha256)&& ...
    ismember(r.parent.source,{'flight','combined'}), ...
    'SHT:F3UQ:ModelBinding','选定Excel必须与观测确认绑定的flight/combined父一致；请显式重新绑定。');
v=r.configuration;
assert(strcmp(v.dataMethod,'steady_only')&&strcmp(v.parameterSetId,'set1')&& ...
    strcmp(v.scheduleParameterization,'independent_nodes'), ...
    'SHT:F3UQ:Route','独立C/D仅支持set1、独立节点、完整平均点。');
parent=sht_f3_current_contract('parent',struct('priorSource',r.parent.source, ...
    'priorRoute',r.parent.route,'priorWorkbook',c.modelWorkbook, ...
    'priorDefinition',v.parentDefinition,'priorRuntimeBinding',v.parentRuntimeBinding));
roots=v;roots.outputRoot=c.outputRoot;roots.reportRoot=c.reportRoot;
local_safe_roots(roots);resuming=strcmp(action,'uqresume');
for destination={c.outputRoot,c.reportRoot}
    for old={v.outputRoot,v.reportRoot,fileparts(c.modelWorkbook),fileparts(c.confirmationFile),fileparts(c.sourceWorkbook)}
        assert(~local_overlap(destination{1},old{1}),'SHT:F3UQ:PathOverlap','新输出不得覆盖输入或旧任务。');
    end
    if resuming,assert(isfolder(destination{1}),'SHT:F3UQ:ResumeMissing','恢复目录不存在。');
    else,assert(~isfolder(destination{1})&&~isfile(destination{1}),'SHT:F3UQ:ExistingRun','新计算目录已存在。');end
end
% 检查已声明的证据沿袭。上游未提供完整沿袭时明确记录限制，而非宣称已排除全部重复。
known=string(local_hash(r.trainingWorkbook));
if isfile(v.identificationFile),known(end+1,1)=string(local_hash(v.identificationFile));end
[~,sheets]=xlsfinfo(c.sourceWorkbook);lineageChecked=false;
if ismember('EvidenceLineage',sheets)
    lineage=readtable(c.sourceWorkbook,'Sheet','EvidenceLineage');
    assert(ismember('evidence_sha256',lineage.Properties.VariableNames),'SHT:F3UQ:Lineage','沿袭表缺证据SHA。');
    assert(~any(ismember(lower(string(lineage.evidence_sha256)),lower(known))), ...
        'SHT:F3UQ:DuplicateEvidence','当前观测已用于所选概率先验，禁止重复计入。');
    lineageChecked=true;
end
binding=local_model_uq_identity(c,r);
o=c.options;
assert(isstruct(o)&&isscalar(o),'SHT:F3UQ:Options','options必须为标量结构体。');
locked={'referenceKind','referenceResultFile','modelObservationOptions','modelMode','dataMethod', ...
    'sourceStage','sourceWorkbook','transitionMode','runTag','outputRoot','reportRoot', ...
    'taskSourceIdentity','runPrediction','runIndependentPrediction','runExport','runIndependentRepeat', ...
    'businessIdentity','engineId','sortieId','parentModelId','parentPosteriorId'};
assert(~any(ismember(fieldnames(o),locked)),'SHT:F3UQ:LockedOption','受控身份/统计目标不能由options覆盖。');
if strcmp(c.method,'C')
    def=struct('methodCParticleCount',512,'methodCRepeatParticleCount',512, ...
        'methodCMoveSweeps',2,'methodCFinalMoveSweeps',4,'methodCIndependentMoveFraction',.2);
    for f=fieldnames(def)',if ~isfield(o,f{1}),o.(f{1})=def.(f{1});end,end
end
q=struct('modelMode',0,'modelRoute',v.modelRoute,'dataMethod','steady_only', ...
    'parameterSet','set1','scheduleParameterization','independent_nodes', ...
    'priorSource',r.parent.source,'priorRoute',r.parent.route,'priorWorkbook',c.modelWorkbook, ...
    'priorDefinition',v.parentDefinition,'priorRuntimeBinding',v.parentRuntimeBinding, ...
    'trainingWorkbook',r.trainingWorkbook,'stage32File',r.stage32File, ...
    'historyIntegrationStep_s',v.integrationStep_s,'saveEnabled',false,'plotEnabled',false);
o.referenceKind='model_excel_and_observations';o.referenceResultFile=c.modelWorkbook;
o.modelObservationOptions=q;o.modelMode=0;o.dataMethod='steady_only';
o.sourceStage=c.sourceStage;o.sourceWorkbook=c.sourceWorkbook;o.transitionMode='bench_to_flight';
o.runTag=c.runTag;o.outputRoot=c.outputRoot;o.reportRoot=c.reportRoot;
o.engineId=binding.engineId;o.sortieId=binding.sortieId;o.parentModelId=binding.parentModelId;
o.parentPosteriorId=binding.parentPosteriorId;o.businessIdentity=binding;
o.runPrediction=false;o.runIndependentPrediction=false;o.runExport=true;o.runIndependentRepeat=true;
% 概率中心来自所选上游，不来自确定性Excel。非原参考曲线须显式允许同节点平移。
assert(isfield(o,'allowReferenceRebase')&&o.allowReferenceRebase, ...
    'SHT:F3UQ:RebaseDeclaration','独立模型评估须显式设置options.allowReferenceRebase=true，保留原物理先验。');
o=sht_f34_contract('defaultOptions',o);o.taskMethod=c.method;
a=sht_f3_three_component_assets('verifyRuntime');
release=sht_f3_three_component_assets('manifest',a.runtime);
identity=struct('schemaVersion','F3_MODEL_OBSERVATION_UQ_B23', ...
    'modelSha256',local_hash(c.modelWorkbook),'confirmationSha256',local_hash(c.confirmationFile), ...
    'confirmationIdentity',r.receiptIdentity,'trainingSha256',local_hash(r.trainingWorkbook), ...
    'stage32Sha256',local_hash(r.stage32File),'sourcePosteriorSha256',local_hash(c.sourceWorkbook), ...
    'runtimeManifestSha256',release.sha256, ...
    'implementationSha256',sht_f34_contract('implementationHash'), ...
    'taskWrapperSha256',local_hash([mfilename('fullpath') '.m']), ...
    'businessIdentity',binding,'lineageAvailable',lineageChecked,'observedEvidenceHashes',known, ...
    'selectedModelIsProbabilityPrior',false,'deterministicFitRequired',false);
if isfield(parent.schedule,'fixedTransient'),identity.fixedTransient=parent.schedule.fixedTransient;end
o.taskSourceIdentity=identity;
executionSources={'Start_FlightModelAdapt_15_UncertaintyTask.m', ...
    'Start_FlightModelUQ_R1_02_MethodD.m','Start_FlightModelUQ_R1_03_MethodC.m', ...
    'sht_f34_method_d.m','sht_f34_method_c.m','sht_f34_likelihood.m', ...
    'sht_tc24_run_control.m'};
executionHashes=cellfun(@(f)local_hash(which(f)),executionSources,'UniformOutput',false);
controlIdentity=struct('schema','F3_UQ_SAFE_CONTROL_B23','source',identity,'options',o, ...
    'method',c.method,'runTag',c.runTag,'outputRoot',c.outputRoot,'reportRoot',c.reportRoot, ...
    'files',{executionSources},'hashes',{executionHashes}, ...
    'matlabRelease',version('-release'),'architecture',computer('arch'));
if resuming
    old=local_read_json(fullfile(c.outputRoot,'f3_uq_execution_plan.json'));
    assert(strcmp(old.identityHash,local_digest(controlIdentity)), ...
        'SHT:F3UQ:ResumeIdentity','源码、模型、数据、配置或随机身份改变，不能重签旧状态。');
end
h=readtable(r.trainingWorkbook,'Sheet','history');s=readtable(r.trainingWorkbook,'Sheet','segments');
if ~ismember('Mkg',h.Properties.VariableNames),h.Mkg=zeros(height(h),1);end
e=sht_f33_model_adapt_v2('prepareEvidence',h,s,q);
rough=sht_f3_runtime_estimate(parent.schedule,e,1,0,[],struct('modelRoute',v.modelRoute,'parameterSet','set1'));
% 节点C/D保留未覆盖节点的完整条件方向，不能用旧幅值低秩上限冒充节点维数。
conditionalUpper=numel(parent.schedule.fuelBias.xNodes);
for id=[1,2,7,8,10,11,12]
    entry=parent.schedule.healthEntries([parent.schedule.healthEntries.cIndex]==id);
    conditionalUpper=conditionalUpper+numel(entry.xNodes)-nnz(entry.pressureLoss&entry.xNodes==0);
end
dimensions=struct('main',rough.parameterUpperBound,'conditional',conditionalUpper, ...
    'steadyPoints',height(e.steadyData),'source','pre_coverage_engineering_upper_bound','isActual',false);
dimensions.boundMeaning='分别保守取上界，不代表两上界能同时成为实际主/条件划分。';
estimate=sht_f3_runtime_estimate('uq',dimensions,o);
out=struct('configuration',c,'options',o,'sourceIdentity',identity,'dimensions',dimensions, ...
    'estimate',estimate,'noDll',true,'physicalCoverageRebuilt',false, ...
    'deterministicFitRequired',false,'statisticalCalibrationEstablished',false, ...
    'lineageAvailable',lineageChecked,'warning','实际主/条件维数须经物理覆盖和先验重建；沿袭未完整时不能证明无未知数据重复。');
if ~ismember(action,{'uqrun','uqresume'}),return;end
out=local_uq_execute(c,o,controlIdentity,identity,binding,estimate,dimensions,resuming);
end

function binding=local_model_uq_identity(c,r)
model=sht_f3_business_identity('workbook',c.modelWorkbook);
up=sht_f3_business_identity('workbook',c.sourceWorkbook);
e=struct('source',{},'sha256',{},'values',{});
e(1)=struct('source',c.confirmationFile,'sha256',local_hash(c.confirmationFile), ...
    'values',struct('engineId',r.configuration.engineId,'sortieId',r.configuration.sortieId, ...
    'parentModelId',r.businessIdentity.parentModelId,'parentPosteriorId',r.businessIdentity.parentPosteriorId));
values=struct();
if isfield(model,'engine_id'),values.engineId=model.engine_id;end
if isfield(model,'model_id'),values.parentModelId=model.model_id;
elseif isfield(model,'run_id'),values.parentModelId=model.run_id;end
e(2)=struct('source',c.modelWorkbook,'sha256',local_hash(c.modelWorkbook),'values',values);
values=struct();
if isfield(up,'engine_id'),values.engineId=up.engine_id;end
if isfield(up,'posterior_id'),values.parentPosteriorId=up.posterior_id;
elseif isfield(up,'run_id'),values.parentPosteriorId=up.run_id;end
e(3)=struct('source',c.sourceWorkbook,'sha256',local_hash(c.sourceWorkbook),'values',values);
binding=sht_f3_business_identity('resolve',e,c.businessIdentity);
binding.currentModelId=binding.parentModelId;binding.currentModelSha256=local_hash(c.modelWorkbook);
end

function binding=local_uq_business_identity(c,r,b,options)
% 发动机/本架次取A和本次B；父文件只核发动机及各自模型编号，不继承父架次。
% 缺失事实值可由调用者显式声明，但必须保留依据，绝不采用defaultOptions示例号。
user=c.businessIdentity;
assert(isstruct(user)&&isscalar(user),'SHT:F3Identity:Configuration','businessIdentity必须为标量结构体。');
for name={'engineId','sortieId','parentPosteriorId'}
    f=name{1};
    if isfield(options,f)
        assert(~isfield(user,f)||isequal(string(user.(f)),string(options.(f))), ...
            'SHT:F3Identity:Conflict','options.%s与businessIdentity.%s冲突。',f,f);
        user.(f)=options.(f);
    end
end
e=struct('source',{},'sha256',{},'values',{},'sourceFields',{});
e(end+1)=entry(c.confirmationFile,local_hash(c.confirmationFile),pick(r.configuration,{'engineId','sortieId'}), ...
    struct('engineId','receipt.configuration.engineId','sortieId','receipt.configuration.sortieId'));
e(end+1)=entry(fullfile(c.resultDirectory,'f3_result_manifest.json'), ...
    local_hash(fullfile(c.resultDirectory,'f3_result_manifest.json')),pick(b.manifest,{'engineId','sortieId'}));
if isfield(b.manifest,'configuration')
    e(end+1)=entry(e(end).source,e(end).sha256,pick(b.manifest.configuration,{'engineId','sortieId'}), ...
        struct('engineId','configuration.engineId','sortieId','configuration.sortieId'));
end
bm=sht_f3_business_identity('workbook',b.paths.model);
e(end+1)=entry(b.paths.model,local_hash(b.paths.model),rename(bm,{'engine_id','sortie_id'},{'engineId','sortieId'}), ...
    struct('engineId','Model/Manifest.engine_id','sortieId','Model/Manifest.sortie_id'));
parentFile=r.configuration.parentWorkbook;
assert(isfile(parentFile)&&strcmpi(local_hash(parentFile),r.parent.sha256), ...
    'SHT:F3Identity:ParentChanged','所选确定性父Excel缺失或已改变，不能绑定错误编号。');
pm=sht_f3_business_identity('workbook',parentFile);
e(end+1)=entry(parentFile,r.parent.sha256,rename(pm,{'engine_id'},{'engineId'}), ...
    struct('engineId','Manifest.engine_id'));
if isfield(r.parent,'runId')
    e(end+1)=entry(c.confirmationFile,local_hash(c.confirmationFile),struct('parentModelId',r.parent.runId), ...
        struct('parentModelId','receipt.parent.runId'));
end
e(end+1)=entry(parentFile,r.parent.sha256,rename(pm,{'run_id'},{'parentModelId'}), ...
    struct('parentModelId','Manifest.run_id'));
up=sht_f3_business_identity('workbook',c.sourceWorkbook);
values=rename(up,{'engine_id','run_id'},{'engineId','parentPosteriorId'});
e(end+1)=entry(c.sourceWorkbook,local_hash(c.sourceWorkbook),values, ...
    struct('engineId','Manifest.engine_id','parentPosteriorId','Manifest.run_id'));
binding=sht_f3_business_identity('resolve',e,user);
binding.currentModelId=char(string(b.manifest.runId));
binding.currentModelSha256=local_hash(b.paths.model);
    function v=entry(source,hash,values,fields)
        if nargin<4,fields=struct();end
        v=struct('source',source,'sha256',hash,'values',values,'sourceFields',fields);
    end
    function v=pick(s,names)
        v=struct();for z=1:numel(names),if isfield(s,names{z}),v.(names{z})=s.(names{z});end,end
    end
    function v=rename(s,from,to)
        v=struct();for z=1:numel(from),if isfield(s,from{z}),v.(to{z})=s.(from{z});end,end
    end
end

function c=local_uq_numeric_context(v)
c=struct('options',v.options,'priorSchedule',v.priorSchedule, ...
    'parameterContract',v.parameterContract,'uqReferenceResult',v);
t=v.coverageTable;p=v.parameterDefinition;
map=repmat(struct('cIndex',0,'name','','scheduled',false,'axisName','', ...
    'entryIndex',0,'basis',[],'support',[],'activeNode',[]),height(p),1);
for j=1:height(p)
    h=p.c_index(j);r=t(t.c_index==h,:);[~,order]=sort(r.node_index);r=r(order,:);
    map(j).cIndex=h;map(j).name=char(p.name(j));map(j).scheduled=logical(p.scheduled(j));
    map(j).axisName=char(p.axis_name(j));map(j).entryIndex=find([v.priorSchedule.healthEntries.cIndex]==h,1);
    map(j).basis=r.update_basis;map(j).support=r.maximum_basis_support;map(j).activeNode=logical(r.active);
end
f=v.fuelBiasCoverageTable;
c.familyMap=map;c.fuelMap=struct('axisName','measured_wf_ratio','xNodes',f.x_node, ...
    'basis',f.update_basis,'support',f.maximum_basis_support,'activeNode',logical(f.active));
end

function yes=local_uq_schedule_equal(a,b)
yes=max(abs(a.designHealth(:)-b.designHealth(:)))<1e-12&& ...
    max(abs(a.fuelBias.biasNodes(:)-b.fuelBias.biasNodes(:)))<1e-12&& ...
    numel(a.fuelBias.xNodes)==numel(b.fuelBias.xNodes)&& ...
    max(abs(a.fuelBias.xNodes(:)-b.fuelBias.xNodes(:)))<1e-12;
for j=1:numel(a.healthEntries)
    k=find([b.healthEntries.cIndex]==a.healthEntries(j).cIndex,1);
    if isempty(k),yes=false;return;end
    yes=yes&&numel(a.healthEntries(j).xNodes)==numel(b.healthEntries(k).xNodes)&& ...
        max(abs(a.healthEntries(j).xNodes(:)-b.healthEntries(k).xNodes(:)))<1e-12&& ...
        max(abs(a.healthEntries(j).kNodes(:)-b.healthEntries(k).kNodes(:)))<1e-12;
end
% 正式五表把未调度的压比常值显式展开为平线；这不是新增待估节点。
extra=setdiff([b.healthEntries.cIndex],[a.healthEntries.cIndex]);
for h=extra
    k=find([b.healthEntries.cIndex]==h,1);
    yes=yes&&max(abs(b.healthEntries(k).kNodes(:)-a.designHealth(h+1)))<1e-12;
end
end

function value=local_read_json(file)
fid=fopen(file,'r','n','UTF-8');assert(fid>=0,'SHT:F3Task:Read','无法读取任务文件：%s。',file);
closer=onCleanup(@()fclose(fid)); %#ok<NASGU>
value=jsondecode(fscanf(fid,'%c'));
end

function local_json(file,value)
temporary=[tempname(fileparts(file)),'.json'];fid=fopen(temporary,'w','n','UTF-8');
assert(fid>=0,'SHT:F3Task:Write','无法写入任务文件。');closer=onCleanup(@()fclose(fid));
fprintf(fid,'%s',jsonencode(value));clear closer;
[ok,msg]=movefile(temporary,file,'f');assert(ok,'SHT:F3Task:Write','%s',msg);
end
