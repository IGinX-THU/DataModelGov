function out = sht_stage4_evolution_task(action, user, selection)
%SHT_STAGE4_EVOLUTION_TASK 仅负责编排；辨识、数据处理及Excel模型仍由F3负责。
% 数据确认、运行状态和正式模型分开保存。只读结果不执行运行身份检查，
% 恢复计算则必须重核输入、配置、运行包和源码；不重签已有确认或检查点。
if nargin < 1, action = 'configuration'; end
if nargin < 2, user = struct(); end
if nargin < 3, selection = struct(); end
action = lower(char(action));
if strcmp(action,'configuration'), out = template(); return; end
if strcmp(action,'capabilities'), out = capabilities(); return; end
if strcmp(action,'loadconfiguration')
    assert(isstruct(user)&&isscalar(user)&&isequal(fieldnames(user),{'configurationFile'}), ...
        'SHT:T4:ConfigRead','加载配置需明确configurationFile。');
    out=configuration(read_json(absolute(user.configurationFile)));return;
end
if startsWith(action,'uq')
    out=uq_action(action,user,selection);return;
end
if ismember(action,{'predictionconfiguration','predictioncheck','predictionestimatetime', ...
        'predictionrun','predictionresume','predictionoutputstatus','readpredictionoutput', ...
        'predictionrequestpause','predictionevaluate','readpredictionevaluation'})
    out=prediction_action(action,user);return;
end
if ismember(action,{'parameters','trend','freezeprediction','predictionstatus','readprediction','exportindex'})
    out=result_action(action,user,selection);return;
end
if ismember(action,{'status','readresult','requestpause'})
    out = read_action(action,user); return;
end
c = configuration(user);
if strcmp(action,'exportconfiguration')
    assert(isfield(selection,'file'),'SHT:T4:ConfigExport','必须明确配置文件路径。');
    write_new_json(absolute(selection.file),c); out=c; return;
end
assert(ismember(action,{'check','estimatetime','preview','confirm','bindparent','run','resume'}), ...
    'SHT:T4:Action','不支持的操作：%s。',action);
checked = check_inputs(c);
if strcmp(action,'check'), out=checked; return; end
if strcmp(action,'estimatetime'), out=estimate_time(c,checked); return; end
own_plan(c,checked); % 先检查全批身份，再写自己的状态；不会创建子任务成功记录。
if ismember(action,{'preview','confirm','bindparent'})
    assert(~isfile(fullfile(c.outputRoot,'evolution.lock')), ...
        'SHT:T4:SelectionLocked','任务被执行进程占用，不能改动预览/确认状态。');
    assert(isfield(selection,'sortieId'),'SHT:T4:Selection','请明确选择架次。');
    i = find(strcmp({c.sorties.sortieId},char(selection.sortieId)));
    assert(isscalar(i),'SHT:T4:Selection','选择的架次不存在或不唯一。');
    previous=read_json(state_path(c,i));
    assert(~previous.resultAvailable&&ismember(previous.status, ...
        {'registered','waiting_parent','awaiting_confirmation','confirmed_data','confirmed'}), ...
        'SHT:T4:SelectionLocked','该架次已开始执行或已有结果；查看结果或使用新批次，不重置确认。');
    if strcmp(action,'bindparent')
        out=bind_parent(c,i,previous);return;
    end
    u = child_config(c,i,true);
    if strcmp(action,'preview')
        prepareClock=tic;out = sht_f3_steady_task('previewData',u);
        state=previous;
        if ~ismember(state.status,{'confirmed_data','confirmed'})
            state.status='awaiting_confirmation';
        end
        state.previewActive_s=toc(prepareClock);
    else
        assert(isfield(selection,'windows'),'SHT:T4:Selection','必须明确确认完整窗口。');
        out = sht_f3_steady_task('confirmData',u,selection.windows);
        state=previous;
        if ~ismember(state.status,{'confirmed_data','confirmed'})
            state.status='confirmed_data';
        end
        if ~isempty(state.intentFile)
            assert(strcmp(state.intentSha256,out.intentSha256),'SHT:T4:IntentChanged', ...
                '原数据确认不得改签；更改选段应使用新批次。');
        end
        state.intentFile=out.intentFile;state.intentSha256=out.intentSha256;
        state.unboundEstimate=out.estimate;
    end
    state.updatedAt=datestr(now,31);write_json(state_path(c,i),state);return;
end
out = execute(c,checked,strcmp(action,'resume'));
end

function c=template()
% 空的业务身份和路径是有意设计，避免新用户无意运行合成验证案例。
root=struct('source','','route','transient_instant','workbook','', ...
    'modelId','','identityBasis','','runtimeBinding',struct(),'definition',struct());
sortie=struct('sortieId','','order',1,'observationTime','', ...
    'measurementFile','','validationFile','','parentRef','root', ...
    'role','normal','selected',true,'identityBasis','', ...
    'measurementSystemId','','channelMap',struct(),'sourceUnits',struct());
c=struct('schemaVersion','T4_EVOLUTION_V2','projectId','','engineId','', ...
    'runId','','purpose','production','outputRoot','','reportRoot','', ...
    'root',root,'sorties',sortie,'segmentation',struct(), ...
    'modelRoute','transient_instant','dataMethod','steady_only', ...
    'parameterSetId','set1','scheduleParameterization','independent_nodes', ...
    'regularizationStrength',.05,'maximumIterations',10,'integrationStep_s',.1, ...
    'plotEnabled',false,'uqMethod','none','maximumSortiesPerSession',0);
end

function p=capabilities()
p=struct('schemaVersion','T4_CAPABILITIES_V2','businessName','发动机个性化模型自演化', ...
    'arbitrarySortieRegistration',true,'existingBenchParent',true, ...
    'futureParentPreview',true,'flightParentExecution',true, ...
    'nonzeroFixedTransient',true,'independentUQ',true, ...
    'parameterQuery',true,'physicalCoordinateTrend',true, ...
    'trendForecast',true,'inputOnlyHistoryPrediction',true, ...
    'sharedInterfaceRequired','F3_B23_ASSESSMENT_AND_COMBINED_V03', ...
    'currentBatchVerification','B1_limited_evidence_B23_new_source_pending_validation', ...
    'modelModes',0,'release','R2019b','defaultRequiresOptimizationToolbox',false, ...
    'defaultRequiresStatisticsToolbox',false,'noConfigurationNoCompute',true, ...
    'limitations',{{'通用业务候选；有限物理验证与完整参数校准分开', ...
    '上述开关表示当前源码接口，不能替代本批计算证据', ...
    '组合模型限F3已支持Visser16固定13参数与相同物理运行包', ...
    '独立UQ只调度原Owner C/D，D局部非驻点不称统计校准后验', ...
    '预测暂停只在双方法边界；没有单历程内部检查点恢复'}});
end

function c=configuration(u)
c=template();assert(isstruct(u)&&isscalar(u),'SHT:T4:Config','配置必须为标量结构体。');
assert(all(ismember(fieldnames(u),fieldnames(c))),'SHT:T4:Config','配置包含未知字段。');
for f=fieldnames(u).',c.(f{1})=u.(f{1});end
assert(strcmp(c.schemaVersion,'T4_EVOLUTION_V2'),'SHT:T4:Schema','配置版本不支持；旧结果可只读。');
for f={'projectId','engineId','runId','outputRoot','reportRoot'}
    c.(f{1})=text_value(c.(f{1}),f{1},false);
end
assert(~isempty(regexp(c.runId,'^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$','once')), ...
    'SHT:T4:RunId','runId为1至32个ASCII字母数字、横线或下划线。架次编号可为中文。');
assert(ismember(c.purpose,{'production','test_fixture'}),'SHT:T4:Purpose','用途必须明确。');
c.outputRoot=absolute(c.outputRoot);c.reportRoot=absolute(c.reportRoot);
assert(~overlap(c.outputRoot,c.reportRoot),'SHT:T4:Path','结果目录和报告目录不可重叠。');
t=template();
assert(isstruct(c.root)&&isscalar(c.root)&&isequal(sort(fieldnames(c.root)),sort(fieldnames(t.root))), ...
    'SHT:T4:Root','请明确选择完整的试车根配置，不自动补零模型。');
for f={'source','route','workbook','modelId','identityBasis'}
    c.root.(f{1})=text_value(c.root.(f{1}),['root.' f{1}],false);
end
assert(ismember(c.root.source,{'2p4','2p7','flight','combined'}),'SHT:T4:Root', ...
    '根来源为兼容试车Excel或明确选择的现有飞行模型，不自动补零。');
assert(ismember(c.root.route,{'steady','transient_instant'}),'SHT:T4:Route','根路径不支持。');
c.root.workbook=absolute(c.root.workbook);
assert(isstruct(c.root.definition)&&isscalar(c.root.definition), ...
    'SHT:T4:Definition','显式模型定义须为标量结构体；不从默认TC24隐式补齐。');
assert(isstruct(c.sorties)&&~isempty(c.sorties)&& ...
    isequal(sort(fieldnames(c.sorties)),sort(fieldnames(t.sorties))), ...
    'SHT:T4:Sorties','架次列表必须使用配置模板字段。');
for i=1:numel(c.sorties)
    s=c.sorties(i);
    for f={'sortieId','parentRef','identityBasis','measurementFile','measurementSystemId'}
        s.(f{1})=text_value(s.(f{1}),f{1},false);
    end
    assert(~strcmp(s.sortieId,'root'),'SHT:T4:SortieId','root保留为试车起点引用。');
    validateattributes(s.order,{'numeric'},{'real','finite','scalar','positive','integer'});
    validateattributes(s.selected,{'logical'},{'scalar'});
    assert(ismember(s.role,{'normal','validation'}),'SHT:T4:Role','架次角色须为normal/validation。');
    s.observationTime=text_value(s.observationTime,'observationTime',true);
    s.measurementFile=absolute(s.measurementFile);
    s.validationFile=text_value(s.validationFile,'validationFile',true);
    if ~isempty(s.validationFile),s.validationFile=absolute(s.validationFile);end
    assert(isstruct(s.channelMap)&&isscalar(s.channelMap)&&isstruct(s.sourceUnits)&&isscalar(s.sourceUnits), ...
        'SHT:T4:Mapping','字段映射和单位必须为结构体。');
    c.sorties(i)=s;
end
assert(numel(unique({c.sorties.sortieId}))==numel(c.sorties)&& ...
    numel(unique([c.sorties.order]))==numel(c.sorties),'SHT:T4:Duplicate','架次编号和顺序不得重复。');
[~,order]=sort([c.sorties.order]);c.sorties=c.sorties(order);
for i=1:numel(c.sorties)
    s=c.sorties(i);if strcmp(s.parentRef,'root'),continue;end
    j=find(strcmp({c.sorties.sortieId},s.parentRef));
    assert(isscalar(j)&&j<i,'SHT:T4:ParentOrder','父架次必须存在且先于子架次，禁止环和自引用。');
    assert(~strcmp(s.role,'normal')||strcmp(c.sorties(j).role,'normal'), ...
        'SHT:T4:ParentRole','正常链不能自动承接验证分支；请明确另建业务链。');
end
assert(ismember(c.modelRoute,{'steady','transient_instant'})&&strcmp(c.dataMethod,'steady_only')&& ...
    strcmp(c.parameterSetId,'set1')&&strcmp(c.scheduleParameterization,'independent_nodes'), ...
    'SHT:T4:Route','当前开放稳态或瞬态时刻/稳态窗口/set1/独立节点组合。');
assert(strcmp(c.uqMethod,'none'),'SHT:T4:UQUnsupported','UQ使用独立uq操作，不由逐架次流程自动执行。');
validateattributes(c.maximumIterations,{'numeric'},{'scalar','integer','>=',1,'<=',10});
% 0表示不限制；正整数允许离线在真实模型交付后的架次边界主动暂停。
validateattributes(c.maximumSortiesPerSession,{'numeric'}, ...
    {'scalar','real','finite','integer','nonnegative'});
validateattributes(c.regularizationStrength,{'numeric'},{'scalar','real','finite','nonnegative'});
assert(ismember(c.integrationStep_s,[.1,.025]),'SHT:T4:Step','不支持的积分步长。');
validateattributes(c.plotEnabled,{'logical'},{'scalar'});
assert(isstruct(c.segmentation)&&isscalar(c.segmentation),'SHT:T4:Segmentation','分段配置必须为结构体。');
end

function out=check_inputs(c)
% 先核明确的试车父，固定瞬态不支持时由原读者报错，不删字段/清零。
parent=sht_f3_current_contract('parent',struct('priorSource',c.root.source, ...
    'priorRoute',c.root.route,'priorWorkbook',c.root.workbook, ...
    'priorRuntimeBinding',c.root.runtimeBinding,'priorDefinition',c.root.definition));
check_business(c.root.workbook,c.engineId,'',c.root.identityBasis);
rows=struct([]);allFiles={c.root.workbook};
for i=1:numel(c.sorties)
    s=c.sorties(i);files=struct('measurement',file_identity(s.measurementFile),'validation',struct());
    check_business(s.measurementFile,c.engineId,s.sortieId,s.identityBasis);
    if ~isempty(s.validationFile)
        files.validation=file_identity(s.validationFile);
        check_business(s.validationFile,c.engineId,s.sortieId,s.identityBasis);
        assert(~strcmp(files.measurement.sha256,files.validation.sha256),'SHT:T4:SameData','独立测试不能与训练同内容。');
    end
    allFiles=[allFiles,{s.measurementFile,s.validationFile}]; %#ok<AGROW>
    supported=strcmp(s.parentRef,'root');reason='';
    if supported
        f3=sht_f3_steady_task('check',child_config(c,i));
    else
        reason=['待实际父架次' s.parentRef '形成模型后绑定；可先预览并确认完整数据段。'];
        f3=sht_f3_steady_task('checkData',child_config(c,i,true));
    end
    f3id=f3.identity;
    row=struct('sortieId',s.sortieId,'parentRef',s.parentRef,'selected',s.selected, ...
        'executableContract',supported,'limitation',reason,'files',files,'f3Identity',f3id,'f3',f3);
    if isempty(rows),rows=row;else,rows(end+1)=row;end %#ok<AGROW>
end
for r={c.outputRoot,c.reportRoot}
    for k=1:numel(allFiles)
        if isempty(allFiles{k}),continue;end
        assert(~overlap(r{1},fileparts(allFiles{k})),'SHT:T4:Path','输出不得与输入/父模型目录重叠。');
    end
end
source=struct();
for n={'Start_Stage4_02_EvolutionTask','sht_stage4_evolution_task'}
    source.(n{1})=file_identity(which(n{1}));
end
out=struct('schemaVersion','T4_CHECK_V2','configuration',c,'rootSha256',parent.sha256, ...
    'rootModelId',c.root.modelId,'rootIdentityBasis',c.root.identityBasis, ...
    'sourceIdentity',source,'sorties',rows,'capabilities',capabilities(), ...
    'noDll',true,'allSelectedSupported',all([rows([rows.selected]).executableContract]));
out.identity=digest(plan_payload(out));
end

function u=child_config(c,i,dataOnly)
if nargin<3,dataOnly=false;end
s=c.sorties(i);slot=sprintf('s%03d',i);
u=struct('taskId',[c.runId '_' slot],'engineId',c.engineId,'sortieId',s.sortieId, ...
    'identificationFile',s.measurementFile,'validationFile',s.validationFile, ...
    'parentSource',c.root.source,'parentRoute',c.root.route,'parentWorkbook',c.root.workbook, ...
    'parentRuntimeBinding',c.root.runtimeBinding,'parentDefinition',c.root.definition, ...
    'modelId',[c.runId '_' slot], ...
    'outputRoot',fullfile(c.outputRoot,slot,'data'),'reportRoot',fullfile(c.reportRoot,slot,'data'), ...
    'modelRoute',c.modelRoute,'dataMethod',c.dataMethod,'parameterSetId',c.parameterSetId, ...
    'scheduleParameterization',c.scheduleParameterization, ...
    'regularizationStrength',c.regularizationStrength,'integrationStep_s',c.integrationStep_s, ...
    'segmentation',c.segmentation,'channelMap',s.channelMap,'sourceUnits',s.sourceUnits);
relation=parent_relation(c,i);
u.parentRelation=relation;
u.businessIdentity=struct('purpose',c.purpose,'engineId',c.engineId, ...
    'sortieId',s.sortieId,'modelId',u.modelId,'parentModelId',relation.modelId, ...
    'basis',struct('engineId',s.identityBasis,'sortieId',s.identityBasis, ...
    'modelId','本批登记的唯一架次模型编号','parentModelId',relation.basis));
if dataOnly
    u.parentSource='unbound';u.parentWorkbook='';u.parentRoute=relation.route;
    u.parentRuntimeBinding=struct();u.parentDefinition=struct();
end
end

function r=parent_relation(c,i)
s=c.sorties(i);
if strcmp(s.parentRef,'root')
    r=struct('source',c.root.source,'route',c.root.route,'modelId',c.root.modelId, ...
        'sortieId','','basis',c.root.identityBasis);
    if ismember(c.root.source,{'flight','combined'})
        m=sht_f3_business_identity('workbook',c.root.workbook);
        if strcmp(c.root.source,'flight')
            assert(isfield(m,'sortie_id'),'SHT:T4:RootFlightIdentity', ...
                '飞行根Excel必须明确架次身份，不能用当前架次编号代替。');
        end
        if isfield(m,'sortie_id'),r.sortieId=m.sortie_id;end
    end
else
    j=find(strcmp({c.sorties.sortieId},s.parentRef));
    kind='flight';
    if strcmp(c.root.source,'combined')
        % 由统一父合同分派TC27/F33格式，显式保留试车根的路线与运行包绑定。
        parent=sht_f3_current_contract('parent',struct('priorSource','combined', ...
            'priorRoute',c.root.route,'priorWorkbook',c.root.workbook, ...
            'priorRuntimeBinding',c.root.runtimeBinding,'priorDefinition',c.root.definition));
        fixed=parent.schedule.fixedTransient;
        % 固定参数不逐架次重估。非零组合根的后代也必须是组合模型；
        % 全零组合根由Owner导出普通稳态载体，不强迫把零值包装成非零能力。
        if any(fixed.value~=0),kind='combined';end
    end
    r=struct('source',kind,'route',c.modelRoute,'modelId',sprintf('%s_s%03d',c.runId,j), ...
        'sortieId',c.sorties(j).sortieId,'basis','用户登记的同一发动机架次父关系');
end
end

function out=bind_parent(c,i,s)
% 意图文件永不改签。新的绑定载荷写在独立目录，且使用真实Excel身份。
assert(~isempty(s.intentFile)&&isfile(s.intentFile)&& ...
    strcmpi(file_hash(s.intentFile),s.intentSha256),'SHT:T4:Confirmation', ...
    '%s缺少合法的数据确认意图。',s.sortieId);
[file,sha]=actual_parent(c,i);
if ~isempty(s.confirmationFile)
    assert(strcmpi(s.parentSha256,sha)&&isfile(s.confirmationFile)&& ...
        strcmpi(file_hash(s.confirmationFile),s.confirmationSha256), ...
        'SHT:T4:ParentChanged','已有实际父或确认改变；新批次重新绑定，不重签。');
    saved=load(s.confirmationFile,'receipt');out=saved.receipt;return;
end
relation=parent_relation(c,i);slot=sprintf('s%03d',i);
u=child_config(c,i,true);
binding=struct('intentFile',s.intentFile,'parentSource',relation.source, ...
    'parentRoute',relation.route,'parentWorkbook',file, ...
    'parentRuntimeBinding',c.root.runtimeBinding,'parentDefinition',struct(), ...
    'businessIdentity',u.businessIdentity, ...
    'outputRoot',fullfile(c.outputRoot,slot,['binding_' sha(1:16)]), ...
    'reportRoot',fullfile(c.reportRoot,slot,['binding_' sha(1:16)]));
if strcmp(s.parentRef,'root')
    binding.parentDefinition=c.root.definition;
else
    % 新飞行Excel已写入实际F3包身份，不把试车根的外部映射套到它上面。
    binding.parentRuntimeBinding=struct();
end
clock=tic;out=sht_f3_steady_task('bindParent',binding);
assert(strcmpi(out.parent.sha256,sha),'SHT:T4:Binding','Owner绑定与实际所选父不一致。');
s.status='confirmed';s.parentWorkbook=file;s.parentSha256=sha;
s.confirmationFile=out.confirmationFile;s.confirmationSha256=file_hash(s.confirmationFile);
s.bindingActive_s=toc(clock);s.updatedAt=datestr(now,31);
write_json(state_path(c,i),s);
end

function [file,sha]=actual_parent(c,i)
if strcmp(c.sorties(i).parentRef,'root')
    plan=read_json(fullfile(c.outputRoot,'evolution_plan.json'));
    file=c.root.workbook;sha=file_hash(file);
    assert(strcmpi(sha,plan.rootSha256),'SHT:T4:ParentChanged','所选根模型内容改变。');
else
    parentId=c.sorties(i).parentRef;
    p=read_action('readresult',struct('resultDirectory',c.outputRoot,'sortieId',parentId));
    file=p.paths.model;sha=file_hash(file);
    assert(strcmp(p.evolution.engineId,c.engineId),'SHT:T4:ParentEngine','父模型发动机不同。');
end
end

function own_plan(c,checked)
file=fullfile(c.outputRoot,'evolution_plan.json');
if isfile(file)
    old=read_json(file);
    assert(strcmp(old.identity,digest(plan_payload(old))),'SHT:T4:PlanChanged','旧计划载荷被改动。');
    assert(strcmp(old.identity,checked.identity),'SHT:T4:ChangedIdentity', ...
        '输入、配置、父、源文件或运行包改变；请使用新批次，禁止重签旧计划。');
    return;
end
assert(~isfolder(c.outputRoot)&&~isfile(c.outputRoot)&&~isfolder(c.reportRoot)&&~isfile(c.reportRoot), ...
    'SHT:T4:ExistingDirectory','新计划目录必须不存在；已有无主目录保留诊断，不覆盖。');
mkdir(c.outputRoot);mkdir(c.reportRoot);
saved=checked;
% 完整测量仍只在原Excel和F3产物中保存，队列不复制万行数据表。
for i=1:numel(saved.sorties),saved.sorties(i).f3=struct();end
write_new_json(file,saved);
for i=1:numel(c.sorties),write_json(state_path(c,i),base_state(c,i));end
fprintf('[Stage4] 登记 %d 架次，运行 %s。无自动造数，无自动UQ。\n',numel(c.sorties),c.runId);
end

function s=base_state(c,i)
r=c.sorties(i);status='registered';if ~strcmp(r.parentRef,'root'),status='waiting_parent';end
s=struct('sortieId',r.sortieId,'order',r.order,'parentRef',r.parentRef, ...
    'role',r.role,'status',status,'resultAvailable',false,'parentSha256','', ...
    'parentWorkbook','','confirmationFile','','confirmationSha256','', ...
    'intentFile','','intentSha256','', ...
    'resultDirectory',sprintf('s%03d/model',i),'stopReason','','errorIdentifier','', ...
    'uqStatus','not_executed','updatedAt',datestr(now,31));
end

function out=estimate_time(c,checked)
% 首次粗估采用Owner版本化实测成本，不执行预处理或假造实际覆盖维数。
planFile=fullfile(c.outputRoot,'evolution_plan.json');
if isfile(planFile)
    old=read_json(planFile);
    assert(strcmp(old.identity,digest(plan_payload(old))),'SHT:T4:PlanChanged','旧计划载荷被改动。');
    assert(strcmp(old.identity,checked.identity),'SHT:T4:ChangedIdentity', ...
        '输入或配置与已保存计划不同，不能用旧确认估时；请指定新批次。');
end
rows=struct([]);
for i=find([c.sorties.selected])
    r=checked.sorties(i);r0=base_state(c,i);p=state_path(c,i);
    if isfile(p),r0=read_json(p);end
    ownerPlan=fullfile(c.outputRoot,r0.resultDirectory,'f3_execution_plan.json');
    if isfile(ownerPlan)
        savedPlan=read_json(ownerPlan);
        item=struct('sortieId',r.sortieId,'kind','saved_execution_estimate', ...
            'estimate',savedPlan.estimate);
    elseif strcmp(r0.status,'confirmed')
        estimate=sht_f3_steady_task('estimate',execution_config(c,i,r0));
        item=struct('sortieId',r.sortieId,'kind','confirmed_owner_estimate','estimate',estimate.estimate);
    elseif isfield(r0,'unboundEstimate')
        item=struct('sortieId',r.sortieId,'kind','confirmed_data_waiting_actual_parent', ...
            'estimate',r0.unboundEstimate);
    elseif r.executableContract&&isfield(r.f3,'estimate')
        item=struct('sortieId',r.sortieId,'kind','coarse_with_selected_compatible_parent', ...
            'estimate',r.f3.estimate);
    else
        estimate=sht_f3_steady_task('estimateData',child_config(c,i,true));
        item=struct('sortieId',r.sortieId,'kind','coarse_before_selection_and_parent', ...
            'estimate',estimate.estimate);
    end
    if isempty(rows),rows=item;else,rows(end+1)=item;end %#ok<AGROW>
end
out=struct('sorties',rows,'noDll',true,'queueWaitingIncluded',false,'newCompute',false);
end

function out=execute(c,~,resuming)
chosen=find([c.sorties.selected]);assert(~isempty(chosen),'SHT:T4:EmptySelection','没有选择执行架次。');
% 在任何计算之前检查所有选择的依赖和确认，不在长算之后才发现缺父。
for i=chosen
    s=read_json(state_path(c,i));
    if s.resultAvailable
        % 保存状态不是可复用模型的证明；模型/结果Excel及真实父均需再核。
        read_action('readresult',struct('resultDirectory',c.outputRoot,'sortieId',s.sortieId));
        continue;
    end
    assert(~isempty(s.intentFile)&&isfile(s.intentFile)&& ...
        strcmpi(file_hash(s.intentFile),s.intentSha256), ...
        'SHT:T4:Confirmation','%s缺少完整数据段的合法确认。',s.sortieId);
    if ~strcmp(s.parentRef,'root')
        parentIndex=find(strcmp({c.sorties.sortieId},s.parentRef));
        parentState=read_json(state_path(c,parentIndex));
        assert(parentState.resultAvailable||ismember(parentIndex,chosen), ...
            'SHT:T4:MissingParent','%s需要父架次%s；该父尚无模型且未选择执行。',s.sortieId,s.parentRef);
        if parentState.resultAvailable
            read_action('readresult',struct('resultDirectory',c.outputRoot,'sortieId',s.parentRef));
        end
    end
    if ~resuming
        assert(ismember(s.status,{'confirmed_data','confirmed'}),'SHT:T4:ResumeRequired', ...
            '已经开始但未完成的架次必须显式resume。');
    end
end
lock=fullfile(c.outputRoot,'evolution.lock');
assert(java.io.File(lock).createNewFile(),'SHT:T4:ConcurrentRun','任务正被占用或遗留锁待核，禁止并发续算。');
release=onCleanup(@()delete_owned(lock));
queueFile=fullfile(c.outputRoot,'queue_state.json');
write_json(queueFile,struct('status','running','updatedAt',datestr(now,31)));
pauseFile=fullfile(c.outputRoot,'pause_requested.json');
if resuming&&isfile(pauseFile),delete_owned(pauseFile);end
completedThisSession=0;
for i=chosen
    if isfile(pauseFile),write_json(queueFile,struct('status','safe_paused_between_sorties', ...
            'updatedAt',datestr(now,31),'stopReason','operator_pause_request'));break;end
    s=read_json(state_path(c,i));if s.resultAvailable,continue;end
    timer=tic;
    try
        if isempty(s.confirmationFile)
            bind_parent(c,i,s);s=read_json(state_path(c,i));
        end
        u=execution_config(c,i,s);
        childAction='run';if isfolder(u.outputRoot),childAction='resume';end
        if strcmp(childAction,'resume')
            assert(resuming,'SHT:T4:ResumeRequired','已有子任务不能静默恢复。');
            st=sht_f3_steady_task('status',struct('resultDirectory',u.outputRoot));
            assert(st.resumeAvailable,'SHT:T4:UnsafeResume','F3无可验证安全检查点，不能恢复。');
            executionPlan=read_json(fullfile(u.outputRoot,'f3_execution_plan.json'));
            estimate=struct('estimate',executionPlan.estimate);
        else
            prepareClock=tic;estimate=sht_f3_steady_task('estimate',u);
            s.estimationPreparation_s=toc(prepareClock);
        end
        s.estimate=estimate.estimate;s.updatedAt=datestr(now,31);
        write_json(state_path(c,i),s);
        if isfile(pauseFile)
            write_json(queueFile,struct('status','safe_paused_between_sorties', ...
                'updatedAt',datestr(now,31),'stopReason','operator_pause_before_owner_compute'));
            break;
        end
        s.status='running';s.sessionStartedAt=datestr(now,31);s.updatedAt=s.sessionStartedAt;
        if ~isfield(s,'startedAt'),s.startedAt=s.sessionStartedAt;end
        write_json(state_path(c,i),s);
        fprintf('[Stage4] %s，父%s/SHA %s，预计 %.1f至%.1f 分钟，F3动作 %s。\n', ...
            s.sortieId,s.parentRef,s.parentSha256,estimate.estimate.totalRange_s/60,childAction);
        result=sht_f3_steady_task(childAction,u);
        if isfield(result,'manifest')&&result.manifest.resultAvailable
            result=effective_model(result);
        end
        s.sessionWall_s=toc(timer);
        if isfield(result,'manifest')&&result.manifest.resultAvailable
            s.status='completed';s.resultAvailable=true;s.converged=result.manifest.converged;
            s.stopReason=result.manifest.stopReason;s.timing=result.manifest.timing;
            % 结果未收敛并不阻断保存；正式模型完整性由F3只读器核验。
            s.modelRelative=relative(c.outputRoot,result.paths.model);
            s.modelSha256=file_hash(result.paths.model);
        else
            assert(isfield(result,'safeStopConfirmed')&&result.safeStopConfirmed, ...
                'SHT:T4:ChildState','子任务未给出合法模型或真实安全停止状态。');
            s.status='safe_paused';s.stopReason='owner_safe_checkpoint';
        end
        s.finishedAt=datestr(now,31);s.updatedAt=s.finishedAt;
        write_json(state_path(c,i),s);
        if strcmp(s.status,'safe_paused')
            write_json(queueFile,struct('status','safe_paused_in_owner', ...
                'updatedAt',datestr(now,31),'stopReason',s.stopReason));break;
        end
    catch failure
        s.status='failed';s.errorIdentifier=failure.identifier;s.stopReason=failure.message;
        s.sessionWall_s=toc(timer);
        s.updatedAt=datestr(now,31);s.finishedAt=s.updatedAt;
        try
            write_json(state_path(c,i),s);
            write_json(queueFile,struct('status','failed','sortieId',s.sortieId, ...
                'identifier',failure.identifier,'message',failure.message,'updatedAt',s.updatedAt));
        catch recordFailure
            % 磁盘或权限错误不能覆盖控制器/求解器原始错误，附加为原因。
            failure=addCause(failure,recordFailure);
        end
        rethrow(failure);
    end
    if s.resultAvailable
        completedThisSession=completedThisSession+1;
        if c.maximumSortiesPerSession>0&&completedThisSession>=c.maximumSortiesPerSession
            write_json(queueFile,struct('status','safe_paused_between_sorties', ...
                'updatedAt',datestr(now,31),'stopReason','session_sortie_limit', ...
                'completedThisSession',completedThisSession));
            break;
        end
    end
end
allDone=true;
for i=chosen,s=read_json(state_path(c,i));allDone=allDone&&s.resultAvailable;end
if allDone,write_json(queueFile,struct('status','completed','updatedAt',datestr(now,31)));end
clear release; % 只有已离开调用循环、释放本进程锁后，才向调用者报告安全停止。
out=read_action('status',struct('resultDirectory',c.outputRoot));
out.indexWorkbook=export_index(c,out);
end

function u=execution_config(c,i,s)
[~,sha]=actual_parent(c,i);
assert(strcmpi(s.parentSha256,sha)&&isfile(s.confirmationFile)&& ...
    strcmpi(file_hash(s.confirmationFile),s.confirmationSha256), ...
    'SHT:T4:ParentChanged','实际父模型或确认载荷已经改变。');
u=struct('confirmationFile',s.confirmationFile,'runId',sprintf('%s_s%03d',c.runId,i), ...
    'outputRoot',fullfile(c.outputRoot,sprintf('s%03d',i),'model'), ...
    'reportRoot',fullfile(c.reportRoot,sprintf('s%03d',i),'model'), ...
    'maximumIterations',c.maximumIterations,'plotEnabled',c.plotEnabled);
end

function out=read_action(action,u)
assert(isstruct(u)&&isscalar(u)&&isfield(u,'resultDirectory')&& ...
    all(ismember(fieldnames(u),{'resultDirectory','sortieId'})), ...
    'SHT:T4:ReadConfig','只读/暂停只需resultDirectory及可选sortieId。');
d=absolute(u.resultDirectory);plan=read_json(fullfile(d,'evolution_plan.json'));
assert(ismember(plan.schemaVersion,{'T4_CHECK_B1_V1','T4_CHECK_V2'}), ...
    'SHT:T4:SavedSchema','不是本接口保存的计划。');
assert(strcmp(plan.identity,digest(plan_payload(plan))), ...
    'SHT:T4:PlanChanged','计划载荷与保存身份不符，不重签。');
% 保存身份是当时的事实，搬迁只读不要求当前配置路径或源码再次相同。
c=plan.configuration;c.outputRoot=d;states=cell(numel(c.sorties),1);
for i=1:numel(states)
    s=read_json(state_path(c,i));child=safe_child(d,s.resultDirectory);
    expected=c.sorties(i);
    assert(strcmp(s.sortieId,expected.sortieId)&&s.order==expected.order&& ...
        strcmp(s.parentRef,expected.parentRef)&&strcmp(s.role,expected.role), ...
        'SHT:T4:StateChanged','架次状态与原计划中的业务身份不一致。');
    if ~isempty(s.parentSha256)
        if strcmp(expected.parentRef,'root')
            assert(strcmp(s.parentSha256,plan.rootSha256)&& ...
                strcmpi(s.parentWorkbook,c.root.workbook), ...
                'SHT:T4:ParentChanged','保存的实际父绑定与已确认根身份不一致。');
        else
            parentMask=strcmp({c.sorties.sortieId},expected.parentRef);p=states{parentMask};
            assert(p.resultAvailable&&isfield(p,'modelSha256')&& ...
                strcmpi(s.parentSha256,p.modelSha256),'SHT:T4:ParentChanged', ...
                '保存的飞行父不是登记父架次的正式模型。');
        end
    end
    if isfile(fullfile(child,'f3_status.json'))
        s.childStatus=sht_f3_steady_task('status',struct('resultDirectory',child));
    end
    states{i}=s;
end
out=struct('engineId',c.engineId,'runId',c.runId,'sorties',{states}, ...
    'processLivenessChecked',false,'currentExecutionCompatibilityChecked',false,'noDll',true);
out.queueStatus='registered';queueFile=fullfile(d,'queue_state.json');
if isfile(queueFile),q=read_json(queueFile);out.queueStatus=q.status;end
out.pauseRequested=isfile(fullfile(d,'pause_requested.json'));
out.safePaused=ismember(out.queueStatus,{'safe_paused_between_sorties','safe_paused_in_owner'})&& ...
    ~isfile(fullfile(d,'evolution.lock'));
if strcmp(action,'status'),return;end
if strcmp(action,'requestpause')
    p=fullfile(d,'pause_requested.json');
    if ~isfile(p),write_new_json(p,struct('requestedAt',datestr(now,31)));end
    out.pauseRequested=true;out.safePaused=false;
    for i=1:numel(states)
        s=states{i};child=safe_child(d,s.resultDirectory);
        if strcmp(s.status,'running')&&isfile(fullfile(child,'run_control','identity.mat'))
            out.childRequest=sht_f3_steady_task('requestPause',struct('resultDirectory',child));
        end
    end
    return;
end
assert(isfield(u,'sortieId'),'SHT:T4:ReadConfig','读取结果必须指定架次。');
i=find(strcmp({c.sorties.sortieId},char(u.sortieId)));assert(isscalar(i),'SHT:T4:Selection','未知架次。');
s=states{i};assert(s.resultAvailable,'SHT:T4:NoResult','该架次没有已保存的合法模型。');
p=safe_child(d,s.modelRelative);
assert(isfile(p)&&strcmp(file_hash(p),s.modelSha256), ...
    'SHT:T4:ResultChanged','保存的模型Excel缺失或内容改变。');
out=sht_f3_steady_task('readResult',struct('resultDirectory',safe_child(d,s.resultDirectory)));
out=effective_model(out);
assert(strcmpi(out.manifest.parentSha256,s.parentSha256), ...
    'SHT:T4:ParentChanged','子任务结果的实际父与本架次绑定不一致。');
check_business(p,c.engineId,s.sortieId,c.sorties(i).identityBasis);
facts=sht_f3_business_identity('workbook',p);
if isfield(facts,'model_id')
    assert(strcmp(facts.model_id,sprintf('%s_s%03d',c.runId,i)), ...
        'SHT:T4:ModelIdentity','正式Excel模型编号与登记架次模型不同。');
end
out.evolution=struct('engineId',c.engineId,'sortieId',s.sortieId,'parentRef',s.parentRef, ...
    'parentWorkbookAtExecution',s.parentWorkbook,'parentSha256',s.parentSha256, ...
    'rootModelId',c.root.modelId,'rootIdentityBasis',c.root.identityBasis,'uqStatus','not_executed');
out.evolution.modelId=sprintf('%s_s%03d',c.runId,i);
out.evolution.fixedTransientSource=struct('source',c.root.source, ...
    'rootModelId',c.root.modelId,'workbookAtRegistration',c.root.workbook, ...
    'rootSha256',plan.rootSha256,'role','inherited_fixed_not_estimated');
out.evolution.uqRecords=uq_records(d,s.modelSha256);
if ~isempty(out.evolution.uqRecords)
    out.evolution.uqStatus='independent_records_available';
end
out.defaultView='training_fit';out.additionalSteadyReplayStatus='not_executed';
out.fullHistoryReplayStatus='not_executed';out.nextSortiePredictionStatus='not_executed';
% 独立测试与本架次训练回放分别展示；存在结果不等于验证通过。
out.trainingFitStatus='available';out.independentValidationStatus='not_executed';
out.independentValidationValid=false;
if isfield(out.manifest,'validationStatus')
    out.independentValidationStatus=out.manifest.validationStatus;
end
if isfield(out.manifest,'validationValid')
    out.independentValidationValid=logical(out.manifest.validationValid);
end
out.independentPointValidationAvailable=~isempty(out.validationPredictions);
out.independentSmallHistoryValidationAvailable=~isempty(out.validationSmallHistory);
out.resultRoles=struct('training','本架次辨识所用数据的拟合', ...
    'independentValidation','另行指定的独立测试，不用于辨识', ...
    'additionalReplay','用户明确请求的附加回放，与默认训练拟合分开', ...
    'nextSortiePrediction','单独冻结和计算的下一架次预测，不由本架次拟合替代');
out.inputOnlyChannels={};out.equilibriumConstraintChannels={};
if strcmp(c.modelRoute,'transient_instant')
    out.inputOnlyChannels={'Np','Ng'};out.equilibriumConstraintChannels={'dNp_dt','dNg_dt'};
end
end

function r=effective_model(r)
% 正式业务父优先使用Owner组合Excel。稳态载体仍单列，不能丢弃相邻
% 载体或将报告字段里的固定参数当作可执行模型参数。
r.modelSource='flight';
if ~isfield(r.paths,'combinedModel'),return;end
combo=sht_f33_transient_delivery('inspect',[],r.paths.combinedModel);
assert(strcmpi(combo.steadySha256,file_hash(r.paths.model)), ...
    'SHT:T4:CombinedCarrier','组合模型与本次稳态载体不是同一身份。');
if isfield(r.paths,'combinedSteady')
    assert(strcmpi(file_hash(r.paths.combinedSteady),combo.steadySha256), ...
        'SHT:T4:CombinedCarrier','相邻稳态载体内容已改变。');
end
r.paths.steadyModel=r.paths.model;r.paths.model=r.paths.combinedModel;
r.model.schedule.designHealth(59:71)=combo.parameters.value;
r.model.schedule.fixedTransient=combo.fixedTransient;
r.combinedModel=combo;r.modelSource='combined';
end

function file=export_index(c,state)
% 索引只引用正式Excel，不用内部MAT补齐任何物理参数；每次发布独立版本。
t=table();
for i=1:numel(state.sorties)
    s=state.sorties{i};path='';sha='';savedResult=struct();
    if s.resultAvailable
        savedResult=read_action('readresult',struct('resultDirectory',c.outputRoot,'sortieId',s.sortieId));
        path=s.modelRelative;sha=s.modelSha256;
    end
    parentId=c.root.modelId;
    if ~strcmp(s.parentRef,'root')
        j=find(strcmp({c.sorties.sortieId},s.parentRef));
        parentId=sprintf('%s_s%03d',c.runId,j);
    end
    converged=NaN;started='';finished='';session=NaN;prepare=NaN;
    compute=NaN;coreExport=NaN;taskExport=NaN;endToEnd=NaN;
    if isfield(s,'converged'),converged=double(s.converged);end
    if s.resultAvailable
        converged=double(savedResult.manifest.converged);
        s.stopReason=savedResult.manifest.stopReason;
        s.timing=savedResult.manifest.timing;
    end
    if isfield(s,'startedAt'),started=s.startedAt;end
    if isfield(s,'finishedAt'),finished=s.finishedAt;end
    if isfield(s,'sessionWall_s'),session=s.sessionWall_s;end
    if isfield(s,'estimationPreparation_s'),prepare=s.estimationPreparation_s;end
    if isfield(s,'timing')
        tm=s.timing;
        if isfield(tm,'coreCompute_s'),compute=tm.coreCompute_s;end
        if isfield(tm,'coreExport_s'),coreExport=tm.coreExport_s;end
        if isfield(tm,'taskExport_s'),taskExport=tm.taskExport_s;end
        if isfield(tm,'endToEnd_s'),endToEnd=tm.endToEnd_s;end
    end
    records=struct([]);uqStatus='not_executed';
    if s.resultAvailable,records=uq_records(c.outputRoot,sha);end
    if ~isempty(records),uqStatus='independent_records_available';end
    row=table(string(c.engineId),string(s.sortieId),s.order,string(s.role), ...
        string(sprintf('%s_s%03d',c.runId,i)),string(s.parentRef),string(parentId), ...
        string(s.parentSha256),string(s.status),s.resultAvailable,converged, ...
        string(path),string(sha),string(s.stopReason),string(uqStatus),numel(records), ...
        string(started),string(finished),string(s.updatedAt), ...
        session,prepare,compute,coreExport,taskExport,endToEnd, ...
        'VariableNames',{'engine_id','sortie_id','order','role','model_id', ...
        'parent_ref','parent_model_id','parent_sha256','status','result_available','converged', ...
        'model_relative_path','model_sha256','stop_reason','uq_status','uq_record_count', ...
        'started_at','finished_at','updated_at','session_wall_s','estimate_preparation_s', ...
        'owner_core_compute_s','owner_core_export_s','owner_task_export_s','owner_end_to_end_s'});
    t=[t;row]; %#ok<AGROW>
end
id=digest(table2struct(t));file=fullfile(c.outputRoot,['evolution_index_' id(1:12) '.xlsx']);
if ~isfile(file),writetable(t,file,'Sheet','Models');end
end

function check_business(file,engine,sortie,basis)
% 老Excel没有业务编号时只接受显式依据；已有矛盾编号不可被人工声明覆盖。
m=sht_f3_business_identity('workbook',file);
if isfield(m,'engine_id'),assert(strcmp(m.engine_id,engine),'SHT:T4:Engine','发动机身份冲突：%s。',file);
else,assert(~isempty(basis),'SHT:T4:IdentityBasis','缺发动机编号，须提供明确依据。');end
if ~isempty(sortie)&&isfield(m,'sortie_id')
    assert(strcmp(m.sortie_id,sortie),'SHT:T4:SortieIdentity','架次身份冲突：%s。',file);
end
end

function out=result_action(action,u,q)
% 结果查询与继续计算分开：这里不要求原测量文件在线，也不加载DLL。
% 趋势参与架次必须显式选择。预测只冻结两个模型，不读取目标架次输出。
if strcmp(action,'exportindex')
    state=read_action('status',u);d=absolute(u.resultDirectory);
    plan=read_json(fullfile(d,'evolution_plan.json'));c=plan.configuration;c.outputRoot=d;
    out=struct('workbook',export_index(c,state),'noDll',true, ...
        'newIdentification',false,'newUQ',false,'newPrediction',false);return;
end
if ismember(action,{'predictionstatus','readprediction'})
    out=read_prediction(u,strcmp(action,'readprediction'));return;
end
assert(isstruct(q)&&isscalar(q),'SHT:T4:Query','查询参数必须为标量结构体。');
if strcmp(action,'parameters')
    r=read_action('readresult',u);
    out=struct('engineId',r.evolution.engineId,'sortieId',r.evolution.sortieId, ...
        'modelWorkbook',r.paths.model,'modelSha256',file_hash(r.paths.model), ...
        'parentSha256',r.evolution.parentSha256,'parameters',r.parameterStates, ...
        'estimatedUpdates',r.parameters,'healthDesign',r.model.schedule.designHealth, ...
        'healthNodes',{r.model.profile.parameters},'fuelBias',r.model.schedule.fuelBias, ...
        'installationLoss',r.model.KdistEq,'intervalStatus','not_computed', ...
        'fixedTransientCIndex',58:70,'fixedTransientValues',r.model.schedule.designHealth(59:71), ...
        'fixedTransientSource',r.evolution.fixedTransientSource, ...
        'noDll',true,'valuesArePhysicalCoefficients',true);
    return;
end
allowed={'historyIds','queries','outputRoot','reportRoot','plotEnabled','predictionId', ...
    'targetSortieId','targetOrder','parentSortieId','minimumSupportedSorties','maximumAbsCorrection'};
assert(all(ismember(fieldnames(q),allowed))&&isfield(q,'historyIds'), ...
    'SHT:T4:TrendConfig','请明确historyIds；不自动按最新文件选择历史。');
ids=cellstr(string(q.historyIds(:)));
assert(~isempty(ids)&&numel(unique(ids))==numel(ids),'SHT:T4:TrendHistory','历史不能为空或重复。');
if strcmp(action,'freezeprediction')
    assert(isfield(q,'targetSortieId'),'SHT:T4:PredictionConfig','必须明确预测目标架次。');
    assert(~ismember(char(q.targetSortieId),ids),'SHT:T4:FutureData', ...
        '预测目标不能作为历史依据；在读取任何模型前拒绝该配置。');
end
status=read_action('status',u);d=absolute(u.resultDirectory);
plan=read_json(fullfile(d,'evolution_plan.json'));c=plan.configuration;
models=cell(numel(ids),1);states=cell(numel(ids),1);positions=zeros(numel(ids),1);
for j=1:numel(ids)
    i=find(strcmp({c.sorties.sortieId},ids{j}));
    assert(isscalar(i),'SHT:T4:TrendHistory','历史架次%s未登记。',ids{j});
    positions(j)=i;states{j}=status.sorties{i};
    models{j}=read_action('readresult',struct('resultDirectory',d,'sortieId',ids{j}));
    % 每个模型只读一次覆盖表；查询数目不会增加Excel打开次数。
    models{j}.queryDictionary=sht_health_parameter_dictionary(0);
    models{j}.queryCoverage=readtable(models{j}.paths.results,'Sheet','node_coverage');
    models{j}.queryFuelCoverage=readtable(models{j}.paths.results,'Sheet','wf_bias_coverage');
end
assert(all(diff(positions)>0),'SHT:T4:TrendOrder','历史必须按登记顺序升序选择，不按文件日期排序。');
queries=struct('cIndex',{},'coordinate',{});
if isfield(q,'queries'),queries=q.queries;
else
    % 默认展示末模型所有真实曲线节点及所有非调度参数，不人为密采样。
    p=models{end}.model.profile.parameters;scheduled=[p.cIndex];
    for j=1:numel(p)
        for k=1:numel(p(j).xNodes),queries(end+1)=struct('cIndex',p(j).cIndex, ...
                'coordinate',p(j).xNodes(k));end %#ok<AGROW>
    end
    for h=setdiff(0:158,scheduled),queries(end+1)=struct('cIndex',h,'coordinate',NaN);end %#ok<AGROW>
    f=models{end}.model.schedule.fuelBias;
    for x=f.xNodes(:)',queries(end+1)=struct('cIndex',-1,'coordinate',x);end %#ok<AGROW>
    queries(end+1)=struct('cIndex',-2,'coordinate',NaN);
end
assert(isstruct(queries)&&~isempty(queries)&&all(isfield(queries,{'cIndex','coordinate'})), ...
    'SHT:T4:TrendQuery','queries必须提供物理编号和实际查询坐标。');
rows=cell(numel(ids)*numel(queries),1);n=0;
for j=1:numel(ids)
    r=models{j};s=states{j};meta=c.sorties(positions(j));
    for k=1:numel(queries)
        z=queries(k);[v,name,unit,axis,axisUnit,method,support,role]=query_parameter(r,z);
        n=n+1;
        rows{n}=table(string(meta.sortieId),meta.order,string(s.parentRef), ...
            string(s.parentSha256),string(s.modelSha256),string(meta.measurementSystemId), ...
            string(meta.role),z.cIndex,string(name),string(unit),string(axis), ...
            string(axisUnit),z.coordinate,v,string(method),support,string(role), ...
            'VariableNames',{'sortie_id','sortie_order','parent_ref','parent_sha256', ...
            'model_sha256','measurement_system_id','business_role','c_index','parameter', ...
            'unit','axis','axis_unit','coordinate','value','evaluation_method', ...
            'data_supported','parameter_role'});
    end
end
out=struct('schemaVersion','T4_PHYSICAL_COORDINATE_TREND_V1','engineId',c.engineId, ...
    'runId',c.runId,'historyIds',{ids},'values',vertcat(rows{1:n}), ...
    'healthExtrapolationCIndex',[1,2,7,8,11,12], ...
    'fuelBiasIsEngineDegradation',false,'futureMeasurementsUsed',false,'noDll',true);
out.identity=digest(rmfield(out,'noDll'));
if strcmp(action,'freezeprediction'),out=freeze_prediction(c,d,out,models,states,q);return;end
if isfield(q,'reportRoot')&&~isempty(q.reportRoot)
    folder=absolute(q.reportRoot);assert(~overlap(folder,d),'SHT:T4:ReportPath','报告不能覆盖模型目录。');
    assert(~isfolder(folder)&&~isfile(folder),'SHT:T4:ReportExists','使用新的趋势报告目录。');
    mkdir(folder);out.workbook=fullfile(folder,'correction_trends.xlsx');
    writetable(out.values,out.workbook,'Sheet','PhysicalCoordinates');
    if isfield(q,'plotEnabled')&&q.plotEnabled,out.figures=plot_trends(out,folder);end
    write_json(fullfile(folder,'trend_identity.json'),out);
end
end

function [v,name,unit,axis,axisUnit,method,support,role]=query_parameter(r,q)
validateattributes(q.cIndex,{'numeric'},{'scalar','finite','integer','>=',-2,'<=',158});
validateattributes(q.coordinate,{'numeric'},{'scalar','real'});
h=q.cIndex;p=r.model.profile.parameters;unit='1';axis='constant';axisUnit='1';
method='constant';support=false;role='fixed_or_inherited';
if h>=0
    dictionary=r.queryDictionary;name=char(dictionary.name(h+1));
    v=r.model.schedule.designHealth(h+1);index=find([p.cIndex]==h,1);
    if ~isempty(index)
        e=p(index);axis=e.axisName;x=e.xNodes;y=e.kNodes;
        if contains(axis,'mass_flow'),axisUnit='kg/s';end
        assert(isfinite(q.coordinate),'SHT:T4:Coordinate','调度参数h%d需要有限物理坐标。',h);
        [v,method]=at_coordinate(x,y,q.coordinate);
        coverage=r.queryCoverage;
        mask=coverage.c_index==h;
        if any(mask),support=covered(coverage.x_node(mask),coverage.active(mask),q.coordinate);end
    else
        assert(isnan(q.coordinate),'SHT:T4:Coordinate','常值h%d不使用横坐标，应为NaN。',h);
    end
    if h>=58&&h<=70
        role='fixed_transient';
    elseif ~dictionary.active(h+1)
        role='reserved';
    elseif support
        role='estimated_in_covered_region';
    end
elseif h==-1
    name='Wf_bias';unit='kg/s';axis='measured_wf_ratio';f=r.model.schedule.fuelBias;
    assert(isfinite(q.coordinate),'SHT:T4:Coordinate','燃油偏置需要测量燃油/设计燃油坐标。');
    [v,method]=at_coordinate(f.xNodes,f.biasNodes,q.coordinate);
    coverage=r.queryFuelCoverage;
    support=covered(coverage.x_node,coverage.active,q.coordinate);
    role='measurement_bias';
else
    name='K_dist_eq';v=r.model.KdistEq;role='installation_loss';
    assert(isnan(q.coordinate),'SHT:T4:Coordinate','装机量是常值，不使用横坐标。');
end
end

function [value,method]=at_coordinate(x,y,q)
x=x(:);y=y(:);
assert(numel(x)>=2&&numel(x)==numel(y)&&all(isfinite([x;y]))&&all(diff(x)>0), ...
    'SHT:T4:Curve','曲线节点不完整或不递增。');
query=min(max(q,x(1)),x(end));value=interp1(x,y,query,'linear');
if q<x(1)||q>x(end)
    method='nearest_endpoint';
elseif any(abs(x-q)<=1e-12*max(1,abs(q)))
    method='saved_node';
else
    method='linear_interpolation';
end
end

function yes=covered(x,active,q)
% 插值存在不代表数据覆盖。只有两侧节点都有实际释放证据才视为支持。
[x,o]=sort(x(:));active=logical(active(o));
if isempty(x),yes=false;return;end
assert(all(diff(x)>0),'SHT:T4:Coverage','覆盖表节点重复。');
if q<x(1)||q>x(end),yes=false;return;end
i=find(abs(x-q)<=1e-12*max(1,abs(q)),1);
if ~isempty(i),yes=active(i);return;end
lo=find(x<q,1,'last');hi=find(x>q,1);yes=active(lo)&&active(hi);
end

function out=freeze_prediction(c,d,trend,models,states,q)
required={'outputRoot','predictionId','targetSortieId','targetOrder','parentSortieId'};
assert(all(isfield(q,required)),'SHT:T4:PredictionConfig','预测缺少明确目标、父或新目录。');
target=text_value(q.targetSortieId,'targetSortieId',false);
id=text_value(q.predictionId,'predictionId',false);
assert(~ismember(target,trend.historyIds),'SHT:T4:FutureData', ...
    '目标架次不能作为其自身预测的历史依据。');
assert(strcmp(q.parentSortieId,trend.historyIds{end}),'SHT:T4:PredictionParent', ...
    '所选历史末架次必须是明确的预测父模型，不能自动选择最新文件。');
assert(all(trend.values.business_role=="normal"),'SHT:T4:FaultParent', ...
    '验证分支不能混入正常历史或成为正常预测父。');
for i=2:numel(trend.historyIds)
    assert(is_ancestor(c,trend.historyIds{i-1},trend.historyIds{i}), ...
        'SHT:T4:TrendLineage','趋势历史必须属于同一明确父链，不能混合平行模型。');
end
targetIndex=find(strcmp({c.sorties.sortieId},target));
if ~isempty(targetIndex)
    assert(c.sorties(targetIndex).order==q.targetOrder&& ...
        strcmp(c.sorties(targetIndex).parentRef,q.parentSortieId)&& ...
        strcmp(c.sorties(targetIndex).role,'normal'),'SHT:T4:PredictionTarget', ...
        '预测声明与已登记的目标顺序/父关系/业务角色冲突。');
end
orders=unique(trend.values.sortie_order,'stable');
validateattributes(q.targetOrder,{'numeric'},{'scalar','integer','finite','>',orders(end)});
minimum=3;if isfield(q,'minimumSupportedSorties'),minimum=q.minimumSupportedSorties;end
validateattributes(minimum,{'numeric'},{'scalar','integer','>=',3});
bound=.08;if isfield(q,'maximumAbsCorrection'),bound=q.maximumAbsCorrection;end
validateattributes(bound,{'numeric'},{'scalar','finite','positive'});
folder=absolute(q.outputRoot);
assert(~overlap(folder,d)&&~isfolder(folder)&&~isfile(folder), ...
    'SHT:T4:PredictionOutput','预测必须使用不重叠的新目录。');
holdModel=models{end}.model;
assert(isfield(holdModel,'reidentificationDefinitionAvailable')&& ...
    holdModel.reidentificationDefinitionAvailable,'SHT:T4:ModelDefinition', ...
    '所选父Excel没有完整物理定义；只能只读，不能猜测坐标或重签后形成预测。');
holdModel.schedule=sht_f33_excel_delivery('restoreSchedule',holdModel);
trendModel=holdModel;decisions=table();
% 运行包/坐标定义改变时不跨合同拟合；固定项沿显式末父保持。
for j=1:numel(models)
    assert(isequal(string(models{j}.model.runtime.asset),string(holdModel.runtime.asset))&& ...
        all(strcmpi(string(models{j}.model.runtime.sha256),string(holdModel.runtime.sha256))), ...
        'SHT:T4:TrendRuntime','历史模型运行包不兼容，应另建趋势段。');
    assert(isequaln(models{j}.model.schedule.designHealth(59:71), ...
        holdModel.schedule.designHealth(59:71)),'SHT:T4:TrendFixedTransient', ...
        '历史固定瞬态参数改变，须另建明确的趋势段。');
end
for j=1:numel(trendModel.schedule.healthEntries)
    e=trendModel.schedule.healthEntries(j);h=e.cIndex;
    if ~ismember(h,trend.healthExtrapolationCIndex),continue;end
    assert(isfield(e,'designCoordinate')&&isfinite(e.designCoordinate), ...
        'SHT:T4:ModelDefinition','父Excel缺h%d正式设计坐标，不猜测节点末端。请接入Owner完整模型合同。',h);
    for k=1:numel(e.xNodes)
        query=struct('cIndex',h,'coordinate',e.xNodes(k));values=zeros(numel(models),1);support=false(size(values));
        for i=1:numel(models)
            [values(i),~,~,axis,axisUnit,~,support(i)]=query_parameter(models{i},query);
            assert(strcmp(axis,holdModel.profile.parameters([holdModel.profile.parameters.cIndex]==h).axisName), ...
                'SHT:T4:TrendAxis','历史h%d调度坐标含义不同。',h);
        end
        use=find(support);proposal=e.kNodes(k);slope=0;reason="hold_insufficient_support";
        if numel(use)>=minimum&&support(end)
            x=orders(use);center=x(end);beta=[ones(numel(use),1),x-center]\values(use);
            predicted=[1,q.targetOrder-center]*beta;
            if isfinite(predicted)&&predicted>=max(-bound,e.lowerBound)&& ...
                    predicted<=min(bound,e.upperBound)
                proposal=predicted;slope=beta(2);reason="linear_supported_history";
            else
                reason="hold_outside_engineering_bound";
            end
        end
        decisions=[decisions;table(h,k,string(axis),string(axisUnit),e.xNodes(k), ...
            e.kNodes(k),proposal,slope,numel(use),reason,'VariableNames', ...
            {'c_index','node_index','axis','axis_unit','coordinate','hold_value','trend_value', ...
            'slope_per_sortie','supported_sorties','decision'})]; %#ok<AGROW>
        e.kNodes(k)=proposal;
    end
    [v,~]=at_coordinate(e.xNodes,e.kNodes,e.designCoordinate);
    if isfield(e,'designValue'),e.designValue=v;end
    if isfield(e,'kNodesDll'),e.kNodesDll=e.kNodes;end
    if isfield(e,'deltaNodesDll'),e.deltaNodesDll=e.kNodes-v;end
    trendModel.schedule.healthEntries(j)=e;trendModel.schedule.designHealth(h+1)=v;
end
% 燃油、装机与全部固定瞬态参数保持末父值，不按健康趋势外推。
assert(isequaln(holdModel.schedule.designHealth(59:71),trendModel.schedule.designHealth(59:71))&& ...
    isequaln(holdModel.schedule.fuelBias,trendModel.schedule.fuelBias),'SHT:T4:FixedValues','固定项发生意外变化。');
mkdir(folder);files=struct('role',{},'path',{},'sha256',{});
% R2019b下按下标赋结构前先明确字段；来源记录与原语义完全相同。
source=struct('sortieId',{},'order',{},'modelSha256',{},'parentSha256',{});
combinationIdentities=struct();
for j=1:numel(models)
    source(j)=struct('sortieId',trend.historyIds{j},'order',orders(j), ...
        'modelSha256',states{j}.modelSha256,'parentSha256',states{j}.parentSha256);
end
formal=struct('options',struct('modelMode',0,'modelRoute',c.modelRoute), ...
    'routeId','stage4_prediction', ...
    'training',struct('sourceSha256',trend.identity),'prior',struct('sourceSha256',states{end}.modelSha256), ...
    'finalSchedule',holdModel.schedule,'estimatedKdistEq',holdModel.KdistEq);
for mode={'hold','trend'}
    if strcmp(mode{1},'trend'),formal.finalSchedule=trendModel.schedule;end
    modelId=[id '_' mode{1}];
    declaration=struct('purpose',c.purpose,'engineId',c.engineId,'sortieId',target, ...
        'parentModelId',models{end}.evolution.modelId,'modelId',modelId, ...
        'basis',struct('engineId','已核所选历史的单台发动机编号', ...
        'sortieId','用户明确声明的下一架次预测目标，未使用未来测量', ...
        'parentModelId','本次明确选择的历史末模型','modelId','本次冻结的独立预测方法编号'));
    formal.options.businessIdentity=sht_f3_business_identity('resolve',struct([]), ...
        declaration,'deterministic');formal.options.businessRunId=modelId;
    formal.routeId=['stage4_prediction_' mode{1}];
    methodRoot=fullfile(folder,mode{1});mkdir(methodRoot);
    carrier=formal;carrier.finalSchedule.designHealth(59:71)=0;
    steadyFile=fullfile(methodRoot,'steady_model.xlsx');
    sht_f33_excel_delivery('write',carrier,steadyFile);
    fixed=sht_f3_current_contract('fixedTransient',formal.finalSchedule.designHealth, ...
        states{end}.modelSha256);
    combination=struct('parameters',table(fixed.cIndex,string(fixed.name(:)), ...
        'VariableNames',{'c_index','name'}),'k',fixed.value, ...
        'converged',false,'stopReason','prediction_model_formed_no_identification', ...
        'options',formal.options,'identity',struct('steadySha256',file_hash(steadyFile), ...
        'fixedTransient',fixed,'predictionId',id,'method',mode{1}));
    combination.options.steadyWorkbook=steadyFile;combination.options.runTag=modelId;
    combination.identityHash=sht_f33_model_adapt_v2('structHash',combination.identity);
    combinationIdentities.(mode{1})=combination.identity;
    file=fullfile(methodRoot,'combined_model.xlsx');
    sht_f33_transient_delivery('write',combination,file);
    restored=sht_f33_transient_delivery('inspect',[],file);
    assert(isequaln(restored.parameters.value,formal.finalSchedule.designHealth(59:71)), ...
        'SHT:T4:PredictionFixedValues','预测组合模型没有保留所选父的固定13项。');
    files(end+1)=struct('role',mode{1},'path',relative(folder,file),'sha256',file_hash(file)); %#ok<AGROW>
    files(end+1)=struct('role',[mode{1} '_steady'],'path',relative(folder,steadyFile), ...
        'sha256',file_hash(steadyFile)); %#ok<AGROW>
end
definition=fullfile(folder,'forecast_definition.xlsx');
writetable(decisions,definition,'Sheet','NodeForecast');writetable(trend.values,definition,'Sheet','HistoricalValues');
files(end+1)=struct('role','definition','path','forecast_definition.xlsx','sha256',file_hash(definition));
out=struct('schemaVersion','T4_NEXT_SORTIE_PREDICTION_V1','engineId',c.engineId, ...
    'predictionId',id,'targetSortieId',target,'targetOrder',q.targetOrder, ...
    'parentSortieId',q.parentSortieId,'parentSha256',states{end}.modelSha256, ...
    'sources',source,'files',files,'combinationIdentities',combinationIdentities, ...
    'createdAt',datestr(now,31), ...
    'minimumSupportedSorties',minimum,'maximumAbsCorrection',bound, ...
    'modelStatus','formed','outputStatus','not_computed','evaluationStatus','no_measurements', ...
    'intervalStatus','not_computed','futureMeasurementsUsed',false, ...
    'automaticallyBecomesBusinessParent',false,'sourceCodeSha256',file_hash(which('sht_stage4_evolution_task')));
out.identity=digest(out);write_new_json(fullfile(folder,'prediction_manifest.json'),out);
out.directory=folder;out.decisions=decisions;
fprintf('[Stage4] 预测%s已形成两模型；尚未计算输出，也没有测量评价。\n',id);
end

function out=read_prediction(u,readTables)
assert(isstruct(u)&&isscalar(u)&&isfield(u,'predictionDirectory')&& ...
    isequal(fieldnames(u),{'predictionDirectory'}),'SHT:T4:PredictionRead','只需predictionDirectory。');
d=absolute(u.predictionDirectory);m=read_json(fullfile(d,'prediction_manifest.json'));
assert(strcmp(m.schemaVersion,'T4_NEXT_SORTIE_PREDICTION_V1')&& ...
    strcmp(m.identity,digest(rmfield(m,'identity'))),'SHT:T4:PredictionIdentity','预测记录身份不完整或已改变。');
out=m;out.noDll=true;out.directory=d;
for j=1:numel(m.files)
    f=m.files(j);p=safe_child(d,f.path);
    assert(isfile(p)&&strcmpi(file_hash(p),f.sha256),'SHT:T4:PredictionChanged','预测文件%s缺失或改变。',f.path);
    if readTables
        if ismember(f.role,{'hold','trend'})
            % 新模型为组合Excel；历史纯稳态预测仍只读，不伪装成已支持
            % 非零固定参数或输入驱动输出。文件的实际合同决定读取方式。
            [~,sheets]=xlsfinfo(p);
            if ismember('TransientParameters',sheets)
                out.(f.role)=sht_f33_transient_delivery('inspect',[],p);
            else
                out.(f.role)=sht_f33_excel_delivery('inspect',p);
            end
        elseif strcmp(f.role,'definition')
            out.decisions=readtable(p,'Sheet','NodeForecast');
            out.history=readtable(p,'Sheet','HistoricalValues');
        end
    end
end
end

function yes=is_ancestor(c,older,newer)
% 按登记的父关系回溯，不把排序相邻或保存日期相近当作继承关系。
yes=false;current=newer;
while ~strcmp(current,'root')
    j=find(strcmp({c.sorties.sortieId},current));
    assert(isscalar(j),'SHT:T4:TrendLineage','历史父引用不在登记表中。');
    current=c.sorties(j).parentRef;
    if strcmp(current,older),yes=true;return;end
end
end

function out=prediction_action(action,user)
% 本层只组织双模型、同输入、同显式初态及后补评价；实际积分沿Start13。
% 一般独立预测仍可直接使用Owner支持的equilibrium。这里的完整显式初态
% 仅用于保持/趋势两方法的公平对照，不意味着禁止一般热平衡初始化。
c=struct('predictionDirectory','','inputFile','','sheet','Data', ...
    'outputRoot','','reportRoot','','integrationStep_s',.1, ...
    'fuelDefinition','measured','initialState',struct(),'plotEnabled',false);
if strcmp(action,'predictionconfiguration'),out=c;return;end
if ismember(action,{'predictionoutputstatus','readpredictionoutput','predictionrequestpause'})
    out=prediction_output(action,user);return;
end
if strcmp(action,'readpredictionevaluation')
    assert(isstruct(user)&&isscalar(user)&&isequal(fieldnames(user),{'evaluationDirectory'}), ...
        'SHT:T4:PredictionEvaluationRead','只需evaluationDirectory。');
    d=absolute(user.evaluationDirectory);m=read_json(fullfile(d,'evaluation_manifest.json'));
    assert(strcmp(m.schemaVersion,'T4_PREDICTION_EVALUATION_V1')&& ...
        strcmp(m.identity,digest(rmfield(m,'identity')))&& ...
        strcmpi(file_hash(safe_child(d,m.workbook)),m.workbookSha256), ...
        'SHT:T4:PredictionEvaluationChanged','保存评价的Excel或身份被改变。');
    out=m;out.metrics=readtable(safe_child(d,m.workbook),'Sheet','Metrics');
    out.noDll=true;out.sourceMeasurementsRequired=false;return;
end
if strcmp(action,'predictionevaluate')
    out=prediction_evaluate(user);return;
end
assert(isstruct(user)&&isscalar(user)&&all(ismember(fieldnames(user),fieldnames(c))), ...
    'SHT:T4:PredictionConfig','预测执行配置包含未知字段。');
for f=fieldnames(user).',c.(f{1})=user.(f{1});end
for f={'predictionDirectory','inputFile','outputRoot','reportRoot'}
    c.(f{1})=absolute(text_value(c.(f{1}),f{1},false));
end
assert(isfile(c.inputFile),'SHT:T4:PredictionInput','缺少实际输入Excel。');
assert(~overlap(c.outputRoot,c.reportRoot),'SHT:T4:PredictionPath','输出和报告目录必须分开。');
for destination={c.outputRoot,c.reportRoot}
    assert(~overlap(destination{1},c.predictionDirectory)&& ...
        ~strcmpi(destination{1},c.inputFile)&& ...
        ~startsWith(lower(c.inputFile),lower([destination{1},filesep])), ...
        'SHT:T4:PredictionPath','预测输出不得覆盖模型或包含输入文件；同级新目录允许。');
end
m=read_prediction(struct('predictionDirectory',c.predictionDirectory),false);
validateattributes(c.plotEnabled,{'logical'},{'scalar'});
s=c.initialState;
assert(isstruct(s)&&isscalar(s)&&all(isfield(s, ...
    {'Np0','Ng0','thermalStrategy','temperature_K','sensorState'}))&& ...
    strcmp(s.thermalStrategy,'explicit'),'SHT:T4:ComparisonInitialState', ...
    '双方法比较须显式给相同两轴、14热和4传感器初态；共同工作数值初猜可省略以保留同一运行包MDL默认值。');
validateattributes(s.temperature_K,{'numeric'},{'numel',14,'finite','real','positive'});
validateattributes(s.sensorState,{'numeric'},{'numel',4,'finite','real'});
% 数值初猜不是物理初态。省略时原样交给Owner，不补零或空数组。
if isfield(s,'commonWorkingSeed')
    validateattributes(s.commonWorkingSeed,{'numeric'},{'numel',6,'finite','real'});
end
checks=struct();models=struct();
for role={'hold','trend'}
    ix=find(strcmp({m.files.role},role{1}));assert(isscalar(ix),'SHT:T4:PredictionModel','缺双预测模型。');
    models.(role{1})=safe_child(c.predictionDirectory,m.files(ix).path);
    u=prediction_owner_config(c,role{1},models.(role{1}));
    checks.(role{1})=Start_FlightModelAdapt_13_TransientModelPrediction('checkData',u);
end
assert(strcmpi(checks.hold.dataSha256,checks.trend.dataSha256)&& ...
    checks.hold.recordCount==checks.trend.recordCount,'SHT:T4:ComparisonInput','两方法输入或范围不一致。');
runtime=sht_f3_current_contract('runtimeIdentity');
identity=struct('configuration',c,'frozenModelIdentity',m.identity, ...
    'businessIdentity',struct('engineId',m.engineId,'targetSortieId',m.targetSortieId, ...
    'parentSortieId',m.parentSortieId,'predictionId',m.predictionId), ...
    'inputSha256',file_hash(c.inputFile),'modelSha256', ...
    struct('hold',checks.hold.modelSha256,'trend',checks.trend.modelSha256), ...
    'runtimeIdentity',runtime,'sourceIdentity',struct(), ...
    'sharedImplementationSha256',sht_f34_contract('implementationHash'));
for name={'sht_stage4_evolution_task','Start_FlightModelAdapt_13_TransientModelPrediction', ...
        'sht_f32_replay_history','sht_f33_transient_delivery','sht_f31_flight_measurement'}
    identity.sourceIdentity.(name{1})=file_identity(which(name{1}));
end
total=checks.hold.estimate.totalRange_s+checks.trend.estimate.totalRange_s;
out=struct('identity',identity,'checks',checks,'estimate',struct('totalRange_s',total, ...
    'scope','两个完整同输入同初态历程；Owner含计算/导出，未含本层准备、冷启动和等待'), ...
    'modelStatus','formed','outputStatus','not_computed','evaluationStatus','not_evaluated', ...
    'intervalStatus','not_computed','noDll',true);
if ismember(action,{'predictioncheck','predictionestimatetime'}),return;end
resuming=strcmp(action,'predictionresume');
planFile=fullfile(c.outputRoot,'prediction_execution_plan.json');
if resuming
    plan=read_json(planFile);
    assert(strcmp(plan.identity,digest(rmfield(plan,'identity')))&& ...
        strcmp(digest(plan.executionIdentity),digest(identity)), ...
        'SHT:T4:PredictionResumeIdentity','输入、模型、初态、配置、包或源码变化；新批次，不重签。');
else
    assert(~isfolder(c.outputRoot)&&~isfile(c.outputRoot)&& ...
        ~isfolder(c.reportRoot)&&~isfile(c.reportRoot),'SHT:T4:PredictionExists','预测使用新目录，已有结果只读或恢复。');
    mkdir(c.outputRoot);mkdir(c.reportRoot);
    plan=struct('schemaVersion','T4_PAIRED_INPUT_PREDICTION_V1', ...
        'executionIdentity',identity,'estimate',out.estimate,'createdAt',datestr(now,31));
    plan.identity=digest(plan);write_new_json(planFile,plan);
end
lock=fullfile(c.outputRoot,'prediction.lock');
assert(java.io.File(lock).createNewFile(),'SHT:T4:PredictionConcurrent','预测进程占用或遗留锁待核。');
release=onCleanup(@()delete_owned(lock));stateFile=fullfile(c.outputRoot,'prediction_output_state.json');
if resuming
    state=read_json(stateFile);
    assert(strcmp(state.planIdentity,plan.identity),'SHT:T4:PredictionState','预测状态与计划不符。');
else
    task=struct('status','not_started','resultAvailable',false,'stopReason','', ...
        'workbookRelative','','workbookSha256','','runtimeRelative','','runtimeSha256','');
    state=struct('planIdentity',plan.identity,'status','registered','startedAt',datestr(now,31), ...
        'updatedAt',datestr(now,31),'roles',struct('hold',task,'trend',task), ...
        'outputStatus','not_computed','evaluationStatus','not_evaluated','intervalStatus','not_computed');
end
pauseFile=fullfile(c.outputRoot,'pause_requested.json');
if resuming&&isfile(pauseFile),delete_owned(pauseFile);end
clock=tic;state.sessionStartedAt=datestr(now,31);state.status='running';
write_json(stateFile,state);
fprintf('[Stage4] 双模型输入驱动预测预计 %.1f至%.1f 分钟，无未来输出调参。\n',total/60);
for role={'hold','trend'}
    key=role{1};st=state.roles.(key);
    if st.resultAvailable,prediction_verify_role(c.outputRoot,st);continue;end
    if isfile(pauseFile),state.status='safe_paused_between_methods';break;end
    try
        % Owner尚无历程内部检查点恢复；已有不完整目录不得伪装成可续算。
        destination=fullfile(c.outputRoot,key);
        assert(~isfolder(destination)&&~isfile(destination), ...
            'SHT:T4:PredictionPartialOwner','不完整历程目录不能内部恢复；保留诊断，使用新批次。');
        st.status='running';state.roles.(key)=st;write_json(stateFile,state);
        r=Start_FlightModelAdapt_13_TransientModelPrediction('runInput', ...
            prediction_owner_config(c,key,models.(key)));
        assert(r.computationallyAccepted,'SHT:T4:PredictionPhysical','Owner未返回物理可接受输出。');
        st.status='completed';st.resultAvailable=true;st.stopReason='complete_input_history';
        st.workbookRelative=relative(c.outputRoot,r.deliveryFile);st.workbookSha256=file_hash(r.deliveryFile);
        rp=fullfile(destination,'prediction_runtime.json');
        st.runtimeRelative=relative(c.outputRoot,rp);st.runtimeSha256=file_hash(rp);
        st.ownerEndToEnd_s=r.endToEnd_s;st.dllCalls=r.executedEvaluationCount;
        state.roles.(key)=st;
    catch failure
        st.status='failed';st.stopReason=failure.message;st.errorIdentifier=failure.identifier;
        state.roles.(key)=st;state.status='failed';state.updatedAt=datestr(now,31);
        state.sessionWall_s=toc(clock);write_json(stateFile,state);rethrow(failure);
    end
    state.updatedAt=datestr(now,31);write_json(stateFile,state);
end
available=[state.roles.hold.resultAvailable,state.roles.trend.resultAvailable];
if all(available),state.status='completed';state.outputStatus='computed';
elseif any(available),state.outputStatus='partially_computed';end
state.sessionWall_s=toc(clock);state.updatedAt=datestr(now,31);write_json(stateFile,state);
prediction_index(c.outputRoot,plan,state);
clear release;
out=prediction_output('predictionoutputstatus',struct('predictionOutputDirectory',c.outputRoot));
if c.plotEnabled&&strcmp(state.outputStatus,'computed')
    data=prediction_output('readpredictionoutput',struct('predictionOutputDirectory',c.outputRoot));
    fig=figure('Name','下一架次输入驱动输出：保持法与趋势法');
    for j=1:4
        names={'Np','Ng','Pt3_eq','Tt45'};units={'rpm','rpm','Pa','K'};n=names{j};
        subplot(2,2,j);plot(data.hold.history.time_s, ...
            [data.hold.history.([n '_sensor']),data.trend.history.([n '_sensor'])]);
        xlabel('时间 / s');ylabel([n ' / ' units{j}]);legend('保持法','趋势法');grid on;
    end
    saveas(fig,fullfile(c.reportRoot,'next_sortie_input_prediction.png'));
    savefig(fig,fullfile(c.reportRoot,'next_sortie_input_prediction.fig'));
end
end

function u=prediction_owner_config(c,role,model)
u=struct('modelWorkbook',model,'inputFile',c.inputFile,'sheet',c.sheet, ...
    'integrationStep_s',c.integrationStep_s,'outputRoot',fullfile(c.outputRoot,role), ...
    'cacheDirectory',fullfile(c.outputRoot,role,'physical_cache'), ...
    'fuelDefinition',c.fuelDefinition,'initialState',c.initialState,'plotEnabled',false);
end

function out=prediction_output(action,u)
assert(isstruct(u)&&isscalar(u)&&isequal(fieldnames(u),{'predictionOutputDirectory'}), ...
    'SHT:T4:PredictionRead','只需predictionOutputDirectory，不要求原输入在线。');
d=absolute(u.predictionOutputDirectory);plan=read_json(fullfile(d,'prediction_execution_plan.json'));
assert(strcmp(plan.schemaVersion,'T4_PAIRED_INPUT_PREDICTION_V1')&& ...
    strcmp(plan.identity,digest(rmfield(plan,'identity'))),'SHT:T4:PredictionPlan','预测计划被改变。');
state=read_json(fullfile(d,'prediction_output_state.json'));
assert(strcmp(state.planIdentity,plan.identity),'SHT:T4:PredictionState','预测状态与原计划不符。');
out=struct('plan',plan,'state',state,'noDll',true,'modelStatus','formed', ...
    'outputStatus',state.outputStatus,'evaluationStatus','not_evaluated', ...
    'intervalStatus','not_computed','safePaused',false,'processLivenessChecked',false);
out.safePaused=strcmp(state.status,'safe_paused_between_methods')&&~isfile(fullfile(d,'prediction.lock'));
if strcmp(action,'predictionrequestpause')
    p=fullfile(d,'pause_requested.json');
    if ~isfile(p),write_new_json(p,struct('requestedAt',datestr(now,31)));end
    out.pauseRequested=true;out.safePaused=false;return;
end
for role={'hold','trend'}
    st=state.roles.(role{1});if ~st.resultAvailable,continue;end
    prediction_verify_role(d,st);
    if strcmp(action,'readpredictionoutput')
        ownerDir=fileparts(safe_child(d,st.workbookRelative));
        out.(role{1})=Start_FlightModelAdapt_13_TransientModelPrediction('read', ...
            struct('resultDirectory',ownerDir));
    end
end
end

function prediction_verify_role(d,s)
for pair={{s.workbookRelative,s.workbookSha256},{s.runtimeRelative,s.runtimeSha256}}
    x=pair{1};file=safe_child(d,x{1});
    assert(isfile(file)&&strcmpi(file_hash(file),x{2}), ...
        'SHT:T4:PredictionResultChanged','保存预测Excel或运行记录缺失/改变。');
end
end

function prediction_index(d,plan,state)
% Excel只交付已保存事实，不依赖JSON补齐可执行模型参数或预测输出。
b=plan.executionIdentity.businessIdentity;rows=table();
for role={'hold','trend'}
    s=state.roles.(role{1});wall=NaN;
    if isfield(s,'ownerEndToEnd_s'),wall=s.ownerEndToEnd_s;end
    t=table(string(b.engineId),string(b.targetSortieId),string(b.parentSortieId), ...
        string(b.predictionId),string(role{1}),string(plan.executionIdentity.modelSha256.(role{1})), ...
        string(s.status),s.resultAvailable,string(s.workbookRelative),string(s.workbookSha256), ...
        wall,string(s.stopReason),"not_evaluated","not_computed", ...
        'VariableNames',{'engine_id','target_sortie_id','parent_sortie_id','prediction_id', ...
        'method','model_sha256','status','output_available','output_relative_path','output_sha256', ...
        'owner_end_to_end_s','stop_reason','evaluation_status','interval_status'});
    rows=[rows;t]; %#ok<AGROW>
end
file=fullfile(d,'prediction_output_index.xlsx');writetable(rows,file,'Sheet','Outputs');
end

function out=prediction_evaluate(u)
assert(isstruct(u)&&isscalar(u)&&isequal(sort(fieldnames(u)), ...
    sort({'predictionOutputDirectory';'observationFile';'outputRoot'})), ...
    'SHT:T4:PredictionEvaluation','需明确已算预测、后补观测Excel和新评价目录。');
d=absolute(u.predictionOutputDirectory);measurement=absolute(u.observationFile);folder=absolute(u.outputRoot);
saved=prediction_output('readpredictionoutput',struct('predictionOutputDirectory',d));
assert(strcmp(saved.outputStatus,'computed'),'SHT:T4:PredictionNotComplete','两种输出须均已真实算成，不能用模型或训练拟合代替。');
assert(~isfolder(folder)&&~isfile(folder)&&~overlap(folder,d)&& ...
    ~strcmpi(folder,measurement)&& ...
    ~startsWith(lower(measurement),lower([folder,filesep])), ...
    'SHT:T4:PredictionEvaluationPath','评价必须使用独立新目录，不得覆盖或包含观测文件；同级目录允许。');
% 正式输出计划已记录目标身份；后补评价不依赖仍在线的原输入或模型目录。
formation=saved.plan.executionIdentity.businessIdentity;
check_business(measurement,formation.engineId,formation.targetSortieId,'用户关联的后补目标架次观测');
rows=table();
for role={'hold','trend'}
    s=saved.state.roles.(role{1});ownerDir=fileparts(safe_child(d,s.workbookRelative));
    r=Start_FlightModelAdapt_13_TransientModelPrediction('compare', ...
        struct('resultDirectory',ownerDir,'observationFile',measurement));
    t=r.metrics;t.method=repmat(string(role{1}),height(t),1);rows=[rows;t]; %#ok<AGROW>
end
% 评价是新对象。原冻结模型、原输入和原输出都不改，不自动选胜者。
mkdir(folder);file=fullfile(folder,'prediction_evaluation.xlsx');writetable(rows,file,'Sheet','Metrics');
meta=table(string(formation.engineId),string(formation.targetSortieId), ...
    string(formation.parentSortieId),string(saved.plan.identity), ...
    string(file_hash(measurement)),"evaluated","not_computed", ...
    'VariableNames',{'engine_id','target_sortie_id','parent_sortie_id', ...
    'prediction_plan_identity','observation_sha256','evaluation_status','interval_status'});
writetable(meta,file,'Sheet','Manifest');
out=struct('schemaVersion','T4_PREDICTION_EVALUATION_V1','predictionPlanIdentity',saved.plan.identity, ...
    'engineId',formation.engineId,'targetSortieId',formation.targetSortieId, ...
    'observationSha256',file_hash(measurement),'outputStatus','computed','evaluationStatus','evaluated', ...
    'workbook','prediction_evaluation.xlsx','workbookSha256',file_hash(file), ...
    'modelRecomputed',false,'modelsChanged',false,'winnerAutomaticallySelected',false, ...
    'intervalStatus','not_computed','createdAt',datestr(now,31));
out.identity=digest(out);write_new_json(fullfile(folder,'evaluation_manifest.json'),out);
out.metrics=rows;out.directory=folder;
end

function out=uq_action(action,user,selection)
% UQ是独立任务：用户明确选择当前模型和概率先验，不由父链自动递推。
% 本层只保存编排身份/状态，概率目标、数值算法和正式Excel由F3负责。
defaults=struct('resultDirectory','','sortieId','','uqId','','method','D', ...
    'sourceStage','2p4','sourceWorkbook','','outputRoot','','reportRoot','', ...
    'confirmationFile','','options',struct(),'businessIdentity',struct());
if strcmp(action,'uqconfiguration'),out=defaults;return;end
if strcmp(action,'uqrecords')
    r=read_action('readresult',user);
    out=struct('modelId',r.evolution.modelId,'modelSha256',file_hash(r.paths.model), ...
        'records',r.evolution.uqRecords,'noDll',true,'intervalsRead',false, ...
        'recordStatusIsSavedFact',true);return;
end
if ismember(action,{'uqstatus','uqread','uqrequestpause'})
    assert(isstruct(user)&&isscalar(user)&&isequal(fieldnames(user),{'uqDirectory'}), ...
        'SHT:T4:UQRead','只读/暂停须指定uqDirectory。');
    directory=absolute(user.uqDirectory);
    plan=read_json(fullfile(directory,'uq_plan.json'));
    assert(strcmp(plan.identity,digest(rmfield(plan,'identity'))), ...
        'SHT:T4:UQPlanChanged','保存的UQ计划身份被改变。');
    state=read_json(fullfile(directory,'uq_state.json'));
    assert(strcmpi(state.targetModelSha256,plan.executionIdentity.targetModelSha256)&& ...
        strcmp(state.uqId,plan.executionIdentity.configuration.uqId)&& ...
        strcmp(state.sortieId,plan.executionIdentity.configuration.sortieId)&& ...
        strcmp(state.method,plan.executionIdentity.configuration.method), ...
        'SHT:T4:UQStateChanged','UQ状态与原任务的模型、编号或方法不一致。');
    out=struct('plan',plan,'state',state,'noDll',true, ...
        'currentExecutionCompatibilityChecked',false, ...
        'statisticallyCalibrated',state.statisticallyCalibrated, ...
        'safePaused',strcmp(state.status,'safe_paused')&&~isfile(fullfile(directory,'uq.lock')), ...
        'processLivenessChecked',false);
    owner=fullfile(directory,'owner');
    if strcmp(action,'uqrequestpause')
        out.pauseRequested=true;out.safePaused=false;
        if isfile(fullfile(owner,'f3_uq_execution_plan.json'))
            out.ownerRequest=sht_f3_steady_task('uqrequestpause',struct('outputRoot',owner));
        else
            error('SHT:T4:UQNotRunning','尚未形成Owner任务，不能虚构安全暂停。');
        end
        return;
    end
    if isfile(fullfile(owner,'f3_uq_execution_plan.json'))
        out.ownerStatus=sht_f3_steady_task('uqstatus',struct('outputRoot',owner));
    end
    if ~state.resultAvailable
        out.intervalStatus='no_available_intervals';
        assert(~strcmp(action,'uqread'),'SHT:T4:UQNoResult','该独立UQ没有可读的正式Excel。');
        return;
    end
    file=safe_child(directory,state.workbookRelative);
    assert(isfile(file)&&strcmpi(file_hash(file),state.workbookSha256), ...
        'SHT:T4:UQResultChanged','UQ交付Excel缺失或改变。');
    out.intervalStatus='computed_target_specific';out.workbook=file;
    if strcmp(action,'uqread')
        out.result=sht_f3_steady_task('uqread',struct('workbook',file));
    end
    return;
end
assert(ismember(action,{'uqpreview','uqconfirm','uqcheck','uqestimatetime','uqrun','uqresume'}), ...
    'SHT:T4:UQAction','不支持UQ操作%s。',action);
assert(isstruct(user)&&isscalar(user)&&all(ismember(fieldnames(user),fieldnames(defaults))), ...
    'SHT:T4:UQConfig','UQ配置包含未知字段。');
c=defaults;for f=fieldnames(user).',c.(f{1})=user.(f{1});end
for f={'resultDirectory','sourceWorkbook','outputRoot','reportRoot'}
    c.(f{1})=absolute(c.(f{1}));
end
for f={'sortieId','uqId'},c.(f{1})=text_value(c.(f{1}),f{1},false);end
assert(~isempty(regexp(c.uqId,'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$','once')), ...
    'SHT:T4:UQId','uqId须为新的ASCII业务编号。');
assert(ismember(c.method,{'C','D'})&&ismember(c.sourceStage,{'2p4','2p7'}), ...
    'SHT:T4:UQMethod','只调度已接通的F3 C/D台架到飞行目标，默认D。');
assert(isstruct(c.options)&&isscalar(c.options)&&isstruct(c.businessIdentity)&& ...
    isscalar(c.businessIdentity),'SHT:T4:UQOptions','选项及业务身份应为结构体。');
r=read_action('readresult',struct('resultDirectory',c.resultDirectory,'sortieId',c.sortieId));
check_business(c.sourceWorkbook,r.evolution.engineId,'', ...
    r.evolution.rootIdentityBasis);
for destination={c.outputRoot,c.reportRoot}
    for source={c.resultDirectory,fileparts(c.sourceWorkbook)}
        assert(~overlap(destination{1},source{1}),'SHT:T4:UQPath','UQ必须使用独立新目录。');
    end
end
assert(~overlap(c.outputRoot,c.reportRoot),'SHT:T4:UQPath','UQ内部结果与报告不可重叠。');
% 新评估另行确认观测，并绑定本架次的新模型。原辨识确认的父模型是
% 上一架次，不能复制、改签后用来评估本架次模型。
if ismember(action,{'uqpreview','uqconfirm'})
    assert(isempty(c.confirmationFile),'SHT:T4:UQConfirmation', ...
        '准备新评估时不传旧confirmationFile；由新确认流程生成。');
    original=read_json(fullfile(c.resultDirectory,'evolution_plan.json'));original=original.configuration;
    ix=find(strcmp({original.sorties.sortieId},c.sortieId));
    data=child_config(original,ix,true);data.taskPurpose='uq_assessment';
    data.taskId=[c.uqId '_assessment'];data.modelId='';
    data.parentSource='unbound';data.parentRoute=original.modelRoute;
    data.parentRelation=struct('source',r.modelSource,'route',original.modelRoute, ...
        'modelId',r.evolution.modelId,'sortieId',c.sortieId, ...
        'basis','明确评估该架次已导出的现有模型，不改演化父关系');
    data.outputRoot=fullfile(c.outputRoot,'assessment_data');
    data.reportRoot=fullfile(c.reportRoot,'assessment_data');
    data.businessIdentity=c.businessIdentity;
    for f={'engineId','sortieId','parentModelId','parentPosteriorId'}
        assert(isfield(c.businessIdentity,f{1})&&~isempty(c.businessIdentity.(f{1})), ...
            'SHT:T4:UQBusiness','评估身份必须明确%s及其依据。',f{1});
    end
    assert(strcmp(data.businessIdentity.engineId,r.evolution.engineId)&& ...
        strcmp(data.businessIdentity.sortieId,c.sortieId)&& ...
        strcmp(data.businessIdentity.parentModelId,r.evolution.modelId), ...
        'SHT:T4:UQBusiness','新评估的发动机、架次或目标模型身份不符。');
    uq_preview_roots(c,data);
    if strcmp(action,'uqpreview')
        out=sht_f3_steady_task('previewData',data);return;
    end
    assert(isstruct(selection)&&isscalar(selection)&&isfield(selection,'windows')&& ...
        all(ismember(fieldnames(selection),{'windows','sortieId'})), ...
        'SHT:T4:UQSelection','uqConfirm需显式selection.windows完整窗口，不自动选段。');
    if isfield(selection,'sortieId')
        assert(strcmp(selection.sortieId,c.sortieId),'SHT:T4:UQSelection','确认架次不符。');
    end
    intent=sht_f3_steady_task('confirmData',data,selection.windows);
    bind=struct('intentFile',intent.intentFile,'parentSource',r.modelSource, ...
        'parentRoute',original.modelRoute,'parentWorkbook',r.paths.model, ...
        'parentDefinition',struct(),'parentRuntimeBinding',struct(), ...
        'businessIdentity',data.businessIdentity, ...
        'outputRoot',fullfile(c.outputRoot,'assessment_binding'), ...
        'reportRoot',fullfile(c.reportRoot,'assessment_binding'));
    out=sht_f3_steady_task('bindParent',bind);
    preparation=struct('schemaVersion','T4_UQ_ASSESSMENT_PREPARATION_V1', ...
        'configuration',c,'targetModelSha256',file_hash(r.paths.model), ...
        'sourceWorkbookSha256',file_hash(c.sourceWorkbook), ...
        'confirmationRelative',relative(c.outputRoot,out.confirmationFile), ...
        'confirmationSha256',file_hash(out.confirmationFile), ...
        'intentRelative',relative(c.outputRoot,intent.intentFile), ...
        'intentSha256',file_hash(intent.intentFile),'createdAt',datestr(now,31));
    preparation.identity=digest(preparation);
    write_new_json(fullfile(c.outputRoot,'uq_assessment_preparation.json'),preparation);
    return;
end

prepared=false;preparationFile=fullfile(c.outputRoot,'uq_assessment_preparation.json');
if isfile(preparationFile)
    preparation=read_json(preparationFile);
    baseConfig=c;baseConfig.confirmationFile='';
    assert(strcmp(preparation.identity,digest(rmfield(preparation,'identity')))&& ...
        strcmp(digest(preparation.configuration),digest(baseConfig))&& ...
        strcmpi(preparation.targetModelSha256,file_hash(r.paths.model))&& ...
        strcmpi(preparation.sourceWorkbookSha256,file_hash(c.sourceWorkbook)), ...
        'SHT:T4:UQPreparationChanged','已确认评估的模型、先验或配置变化；须新批次。');
    file=safe_child(c.outputRoot,preparation.confirmationRelative);
    assert(strcmpi(file_hash(file),preparation.confirmationSha256)&& ...
        strcmpi(file_hash(safe_child(c.outputRoot,preparation.intentRelative)),preparation.intentSha256), ...
        'SHT:T4:UQConfirmation','评估确认或意图改变；不重签历史资产。');
    assert(isempty(c.confirmationFile)||strcmpi(absolute(c.confirmationFile),file), ...
        'SHT:T4:UQConfirmation','显式确认与本次准备记录不同。');
    c.confirmationFile=file;prepared=true;
else
    assert(~isempty(c.confirmationFile),'SHT:T4:UQConfirmation', ...
        '请先uqPreview/uqConfirm，或明确给出已绑定目标模型的新评估确认。');
    c.confirmationFile=absolute(c.confirmationFile);
end
assert(isfile(c.confirmationFile),'SHT:T4:UQConfirmation','评估确认文件不存在。');
owner=struct('modelWorkbook',r.paths.model, ...
    'confirmationFile',c.confirmationFile,'sourceStage',c.sourceStage, ...
    'sourceWorkbook',c.sourceWorkbook,'method',c.method,'runTag',c.uqId, ...
    'outputRoot',fullfile(c.outputRoot,'owner'),'reportRoot',fullfile(c.reportRoot,'owner'), ...
    'options',c.options,'businessIdentity',c.businessIdentity);
% 用当前模型和当前架次作确定性目标，概率先验仍是用户明确给出的Excel。
for f={'engineId','sortieId'}
    value=r.evolution.(f{1});
    assert(~isfield(owner.businessIdentity,f{1})||strcmp(owner.businessIdentity.(f{1}),value), ...
        'SHT:T4:UQBusiness','显式UQ身份与当前模型冲突。');
    owner.businessIdentity.(f{1})=value;
end
identity=struct('configuration',c,'targetModelSha256',file_hash(r.paths.model), ...
    'targetResultsSha256',file_hash(r.paths.results),'confirmationSha256',file_hash(c.confirmationFile), ...
    'probabilityPriorSha256',file_hash(c.sourceWorkbook), ...
    'stage4SourceSha256',file_hash(which('sht_stage4_evolution_task')), ...
    'ownerSourceSha256',file_hash(which('sht_f3_steady_task')), ...
    'uqImplementationSha256',sht_f34_contract('implementationHash'));
resuming=strcmp(action,'uqresume');
if resuming
    plan=read_json(fullfile(c.outputRoot,'uq_plan.json'));
    assert(strcmp(plan.identity,digest(rmfield(plan,'identity')))&& ...
        strcmp(digest(plan.executionIdentity),digest(identity)), ...
        'SHT:T4:UQResumeIdentity','输入/模型/先验/数值配置/源码改变；须新UQ批次，不重签。');
else
    assert((prepared||(~isfolder(c.outputRoot)&&~isfolder(c.reportRoot)))&& ...
        ~isfile(c.outputRoot)&&~isfile(c.reportRoot)&& ...
        ~isfile(fullfile(c.outputRoot,'uq_plan.json'))&& ...
        ~isfolder(owner.outputRoot)&&~isfolder(owner.reportRoot),'SHT:T4:UQExists', ...
        '该UQ目录已存在；请只读或显式恢复，不覆盖。');
end
if ~resuming
    out=sht_f3_steady_task('uqcheck',owner);
    out.stage4Target=identity;out.deterministicParentIsProbabilityPrior=false;
    if ~strcmp(action,'uqrun'),return;end
    % Owner检查通过之后才登记任务，未接通非零/新格式时不会留下伪成功。
    if ~isfolder(c.outputRoot),mkdir(c.outputRoot);end
    if ~isfolder(c.reportRoot),mkdir(c.reportRoot);end
    plan=struct('schemaVersion','T4_INDEPENDENT_UQ_V1','executionIdentity',identity, ...
        'estimate',out.estimate,'createdAt',datestr(now,31));plan.identity=digest(plan);
    write_new_json(fullfile(c.outputRoot,'uq_plan.json'),plan);
end
lock=fullfile(c.outputRoot,'uq.lock');
assert(java.io.File(lock).createNewFile(),'SHT:T4:UQConcurrent','本UQ有运行进程或遗留锁须核查。');
release=onCleanup(@()delete_owned(lock));
state=struct('uqId',c.uqId,'sortieId',c.sortieId,'method',c.method,'status','running', ...
    'resultAvailable',false,'targetModelSha256',identity.targetModelSha256, ...
    'startedAt',datestr(now,31),'updatedAt',datestr(now,31),'stopReason','', ...
    'statisticallyCalibrated',false,'preparationExportWaitingIncludedInCore',false);
state.sessionStartedAt=state.startedAt;
if resuming
    previous=read_json(fullfile(c.outputRoot,'uq_state.json'));
    assert(strcmpi(previous.targetModelSha256,identity.targetModelSha256)&& ...
        strcmp(previous.uqId,c.uqId),'SHT:T4:UQStateChanged','恢复前任务状态与目标不一致。');
    if previous.resultAvailable
        out=uq_action('uqread',struct('uqDirectory',c.outputRoot),struct());return;
    end
    state.startedAt=previous.startedAt;
end
write_json(fullfile(c.outputRoot,'uq_state.json'),state);clock=tic;
fprintf('独立UQ %s/%s：预计 %.1f 至 %.1f 秒；局部D不称统计校准后验。\n', ...
    c.uqId,c.method,plan.estimate.totalRange_s);
try
    register_uq(c,plan,state);
    childAction='uqrun';if resuming,childAction='uqresume';end
    result=sht_f3_steady_task(childAction,owner);
    if isfield(result,'status')&&strcmp(result.status,'paused')
        state.status='safe_paused';state.stopReason=result.message;
        state.resultAvailable=false;
    else
        manifest=read_json(fullfile(owner.outputRoot,'f3_uq_result_manifest.json'));
        targetSha='';
        if isfield(manifest.sourceIdentity,'modelSha256'),targetSha=manifest.sourceIdentity.modelSha256;end
        if isfield(manifest.sourceIdentity,'bModelSha256'),targetSha=manifest.sourceIdentity.bModelSha256;end
        assert(manifest.resultAvailable&&strcmpi(targetSha, ...
            identity.targetModelSha256),'SHT:T4:UQTarget','Owner成果没有对应当前模型。');
        file=absolute(manifest.workbook);
        assert(isfile(file)&&strcmpi(file_hash(file),manifest.sha256), ...
            'SHT:T4:UQExport','正式UQ Excel缺失或身份错误。');
        state.status='completed';state.resultAvailable=true;
        state.workbookRelative=relative(c.outputRoot,file);state.workbookSha256=manifest.sha256;
        state.ownerTiming=manifest.controlTiming;
        state.statisticallyCalibrated=manifest.newPosteriorStatisticallyCalibrated;
    end
    state.sessionWall_s=toc(clock);state.updatedAt=datestr(now,31);
    write_json(fullfile(c.outputRoot,'uq_state.json'),state);
    register_uq(c,plan,state);
    out=struct('state',state,'result',result,'optionalUQDoesNotInvalidateModel',true);
catch failure
    state.status='failed';state.sessionWall_s=toc(clock);state.updatedAt=datestr(now,31);
    state.stopReason=failure.message;state.errorIdentifier=failure.identifier;
    try
        write_json(fullfile(c.outputRoot,'uq_state.json'),state);
        register_uq(c,plan,state);
    catch recordFailure
        failure=addCause(failure,recordFailure);
    end
    rethrow(failure);
end
end

function uq_preview_roots(c,data)
% previewData会保存原预览；confirmData必须复用它，不能把准备根误当结果根。
% 此处只检查精确目录归属。载荷、配置、输入及源码身份仍交F3原Owner核验。
roots={c.outputRoot,c.reportRoot};present=cellfun(@isfolder,roots);
assert(~any(cellfun(@isfile,roots)),'SHT:T4:UQExists','评估准备根被文件占用。');
if ~any(present),return;end
assert(all(present),'SHT:T4:UQPreparationRoot','原预览的结果根和报告根必须同时存在。');
expectedOwner=struct('taskId',data.taskId,'outputRoot',data.outputRoot,'reportRoot',data.reportRoot);
for j=1:2
    top=dir(roots{j});top=top(~ismember({top.name},{'.','..'}));
    assert(numel(top)==1&&top.isdir&&strcmp(top.name,'assessment_data'), ...
        'SHT:T4:UQExists','准备根只能含原assessment_data；已有确认、绑定、计算或其他内容须另建批次。');
    folder=fullfile(roots{j},'assessment_data');leaves=dir(folder);
    leaves=leaves(~ismember({leaves.name},{'.','..'}));
    expected={'f3_task_owner.mat'};
    if j==1,expected={'f3_task_owner.mat','f3_data_preview.mat'};end
    files=leaves(~[leaves.isdir]);folders=leaves([leaves.isdir]);
    allowed={};if j==1,allowed={'delivery','replay_cache'};end
    assert(isequal(sort({files.name}),sort(expected))&& ...
        all(ismember({folders.name},allowed)), ...
        'SHT:T4:UQPreparationRoot','原预览文件缺失或夹带额外内容；不得覆盖或重签。');
    % F32无回放预览会预建这两个目录；只允许空目录，不接受任何计算产物。
    for k=1:numel(folders)
        contents=dir(fullfile(folder,folders(k).name));
        contents=contents(~ismember({contents.name},{'.','..'}));
        assert(isempty(contents),'SHT:T4:UQPreparationRoot', ...
            '预览预建目录%s必须为空；已有内容须另建批次。',folders(k).name);
    end
    saved=load(fullfile(folder,'f3_task_owner.mat'),'owner');
    assert(isfield(saved,'owner')&&isequal(saved.owner,expectedOwner), ...
        'SHT:T4:UQPreparationOwner','原预览不属于本次任务或两根路径不匹配。');
end
end

function register_uq(c,plan,state)
% 每个实际任务单独登记；不写正式模型Excel，不把方法菜单当作已有结果。
folder=fullfile(c.resultDirectory,'uq_registry');
if ~isfolder(folder),mkdir(folder);end
file=fullfile(folder,[c.uqId '.json']);
record=struct('schemaVersion','T4_UQ_RECORD_V1','uqId',c.uqId, ...
    'sortieId',c.sortieId,'method',c.method,'targetModelSha256',state.targetModelSha256, ...
    'uqDirectoryAtExecution',c.outputRoot,'uqPlanIdentity',plan.identity, ...
    'createdAt',plan.createdAt,'updatedAt',state.updatedAt,'statusAtUpdate',state.status, ...
    'resultSavedAtUpdate',state.resultAvailable, ...
    'statisticallyCalibratedAtUpdate',state.statisticallyCalibrated);
if isfile(file)
    old=read_json(file);
    assert(strcmp(old.identity,digest(rmfield(old,'identity')))&& ...
        strcmp(old.uqId,record.uqId)&&strcmp(old.uqPlanIdentity,record.uqPlanIdentity)&& ...
        strcmpi(old.targetModelSha256,record.targetModelSha256), ...
        'SHT:T4:UQRecordConflict','该UQ编号已用于另一目标或批次，不能覆盖旧记录。');
end
record.identity=digest(record);write_json(file,record);
end

function records=uq_records(directory,modelSha256)
% 登记表只说明保存事实。搬迁或源数据离线时仍可列记录，区间须uqRead另核。
records=struct([]);folder=fullfile(directory,'uq_registry');
if ~isfolder(folder),return;end
files=dir(fullfile(folder,'*.json'));
for k=1:numel(files)
    r=read_json(fullfile(folder,files(k).name));
    assert(strcmp(r.schemaVersion,'T4_UQ_RECORD_V1')&& ...
        strcmp(r.identity,digest(rmfield(r,'identity'))), ...
        'SHT:T4:UQRecordChanged','UQ登记记录已改变或不支持。');
    if ~strcmpi(r.targetModelSha256,modelSha256),continue;end
    r.currentUqFileVerified=false;r.intervalsIncluded=false;
    if isempty(records),records=r;else,records(end+1)=r;end %#ok<AGROW>
end
end

function files=plot_trends(r,folder)
% 不按节点序号连线；每条图线对应一个明确物理坐标与测量系统。
t=r.values;queryKeys=t(:,{'c_index','coordinate','measurement_system_id'});
queryKeys.measurement_system_id(queryKeys.c_index~=-1)="";
keys=unique(queryKeys,'rows','stable');files={};
for k=1:height(keys)
    key=keys(k,:);mask=t.c_index==key.c_index& ...
        (t.coordinate==key.coordinate|(isnan(t.coordinate)&isnan(key.coordinate)));
    if key.c_index==-1,mask=mask&t.measurement_system_id==key.measurement_system_id;end
    v=t(mask,:);if height(v)<2||all(v.parameter_role=="reserved"),continue;end
    fig=figure('Visible','off','Color','w','Position',[100 100 1000 460]);
    cleanup=onCleanup(@()close(fig));hold on;
    normal=v.business_role=="normal";
    plot(v.sortie_order(normal),v.value(normal),'o','Color',[.12 .43 .67],'LineWidth',1.2);
    plot(v.sortie_order(~normal),v.value(~normal),'x','Color',[.75 .24 .18],'LineWidth',1.2);
    % 只连接真实、直接的正常父关系；平行验证模型仅用独立标记。
    for j=find(normal)'
        parent=find(v.sortie_id==v.parent_ref(j)&normal);
        if isscalar(parent)
            plot(v.sortie_order([parent,j]),v.value([parent,j]),'-', ...
                'Color',[.12 .43 .67],'HandleVisibility','off');
        end
    end
    grid on;xticks(v.sortie_order);xticklabels(cellstr(v.sortie_id));xtickangle(45);
    xlabel('已登记架次');ylabel(sprintf('%s (%s)',char(v.parameter(1)),char(v.unit(1))),'Interpreter','none');
    title(sprintf('物理坐标 %g %s；蓝色正常链，红色验证模型',key.coordinate,char(v.axis_unit(1))), ...
        'Interpreter','none');
    file=fullfile(folder,sprintf('trend_%03d.png',k));print(fig,file,'-dpng','-r130');
    files{end+1}=file;clear cleanup; %#ok<AGROW>
end
end

function p=state_path(c,i)
p=fullfile(c.outputRoot,sprintf('sortie_%03d.json',i));
end
function r=file_identity(p)
assert(~isempty(p)&&isfile(p),'SHT:T4:MissingFile','文件不存在：%s。',p);
r=struct('path',absolute(p),'sha256',file_hash(p));
end
function h=file_hash(p)
h=sht_f33_model_adapt_v2('fileHash',p);
end
function h=digest(v)
% JSON记录往返后保持同一身份，避免NaN/null、字符串/字符的表示差异。
h=sht_f33_model_adapt_v2('structHash',jsondecode(jsonencode(v)));
end
function v=plan_payload(v)
if isfield(v,'identity'),v=rmfield(v,'identity');end
v.sorties=rmfield(v.sorties,'f3');
end
function p=absolute(p)
p=text_value(p,'path',false);
assert(~isempty(regexp(p,'^([A-Za-z]:[\\/]|\\\\)','once')), ...
    'SHT:T4:AbsolutePath','路径必须由调用方明确为绝对路径：%s。',p);
p=char(java.io.File(p).getCanonicalPath());
end
function yes=overlap(a,b)
yes=strcmpi(a,b)||startsWith(lower(a),lower([b filesep]))||startsWith(lower(b),lower([a filesep]));
end
function r=relative(root,p)
assert(startsWith(lower(p),lower([root filesep])),'SHT:T4:OutputEscape','输出越界。');r=p(numel(root)+2:end);
end
function p=safe_child(root,r)
p=char(java.io.File(fullfile(root,r)).getCanonicalPath());relative(root,p);
end
function s=text_value(s,name,emptyAllowed)
assert((ischar(s)&&(isrow(s)||isempty(s)))||(isstring(s)&&isscalar(s)&&~ismissing(s)), ...
    'SHT:T4:Text','%s必须为文本，编号不可用数值自动转换。',name);
s=strtrim(char(s));assert((emptyAllowed||~isempty(s))&&~any(s==10|s==13), ...
    'SHT:T4:Text','%s为空或含换行。',name);
end
function v=read_json(p)
assert(isfile(p),'SHT:T4:MissingRecord','记录不存在：%s。',p);
fid=fopen(p,'rb');assert(fid>=0,'SHT:T4:Read','无法打开记录。');
cleanup=onCleanup(@()close_file(fid));bytes=fread(fid,Inf,'*uint8')';clear cleanup;
if numel(bytes)>=3&&isequal(bytes(1:3),uint8([239 187 191])),bytes=bytes(4:end);end
v=jsondecode(native2unicode(bytes,'UTF-8'));
end
function write_new_json(p,v)
assert(~isfile(p)&&~isfolder(p),'SHT:T4:ExistingFile','不覆盖已有记录：%s。',p);write_json(p,v);
end
function write_json(p,v)
folder=fileparts(p);assert(isfolder(folder),'SHT:T4:Directory','写目录不存在：%s。',folder);
tmp=[tempname(folder) '.json'];fid=fopen(tmp,'w','n','UTF-8');assert(fid>=0,'SHT:T4:Write','无法写记录。');
cleanup=onCleanup(@()close_file(fid));fprintf(fid,'%s',jsonencode(v));clear cleanup;
[ok,msg]=movefile(tmp,p,'f');assert(ok,'SHT:T4:Publish','发布状态失败：%s。',msg);
end
function close_file(fid)
fclose(fid);
end
function delete_owned(p)
if isfile(p),delete(p);end
end
