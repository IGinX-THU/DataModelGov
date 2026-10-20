function plan=sht_stage4_guard(action,c)
% 阶段4统一入口保护：先解析本次输入，再核查冻结身份，最后检查执行依赖。
% 不运行DLL，不签发旧结果；所有错误在编排层解决，辨识/UQ数学方法保持原样。
sc=sht_stage4_scenarios();ids={sc.id};
if ~isempty(c.scenarioIds),ids=ids(ismember(ids,c.scenarioIds));end
plan=struct('ids',{ids},'scopeTag',strjoin(ids,'_'),'sources',struct(), ...
    'batchSha','','predictionIds',{{}},'forecast',ismember('F06',ids));
if numel(ids)==numel(sc),plan.scopeTag='all';end
plan.predictionIds=ids(ismember(ids,{'F05_N','F05_HPC','F05_GT','F05_PT'}));
plan.reportRoot=c.report;
if ~strcmp(plan.scopeTag,'all'),plan.reportRoot=fullfile(c.report,'scopes',plan.scopeTag);end
evaluationMode='models';if c.fullReplayEnabled,evaluationMode='replay';end
plan.predictionFile=fullfile(c.middle,'prediction',['evaluation_',plan.scopeTag,'_',evaluationMode,'.mat']);
plan.reportMat=fullfile(c.middle,['stage4_report_',plan.scopeTag,'.mat']);
assert(strcmp(version('-release'),'2019b'),'SHT:Stage4:Version','请在MATLAB R2019b执行阶段4。');

% 文件路径和内容均是输入身份。同字节不同路径也不能悄悄使用旧记录。
declared=fieldnames(c.externalMeasurements);
assert(all(ismember(declared,{sc.id})),'SHT:Stage4:Scenario','外部测量映射含未知架次。');
assert(strcmp(c.inputMode,'external')||isempty(declared), ...
    'SHT:Stage4:InputMode','synthetic_demo不接受externalMeasurements，请显式选择external。');
for i=1:numel(sc)
    q=sc(i);source=struct('kind','generated','path','','sha256','');
    if strcmp(c.inputMode,'external')
        source.kind='external';
        if isfield(c.externalMeasurements,q.id)
            source.path=local_path(c.externalMeasurements.(q.id));
            source.sha256=local_hash(source.path);
        end
    elseif q.reuse
        source.kind='historical';source.path=local_path(c.firstMeasurement);
        source.sha256=local_hash(source.path);
    end
    plan.sources.(q.id)=source;
end
contract=local_contract(c,plan.sources);
file=fullfile(c.middle,'stage4_execution_contract.mat');
if isfile(file)
    a=load(file,'contract');
    if ~isfield(a,'contract')||~isequaln(a.contract,contract)
        reason=local_difference(a,contract);
        error('SHT:Stage4:ExecutionIdentity', ...
            '批次%s身份不兼容：%s。请使用新的runId；不得重签旧合同或检查点。',c.runId,reason);
    end
    plan.batchSha=local_hash(file);
else
    assert(ismember(action,{'prepare','freeze','all'}),'SHT:Stage4:PrepareRequired', ...
        '批次%s尚未prepare；请先冻结本次完整外部文件映射和处理配置。',c.runId);
    leftovers=dir(fullfile(c.middle,'**','stage4_*record.mat'));
    assert(isempty(leftovers),'SHT:Stage4:OrphanBatch', ...
        '已有结果但缺少合同，请使用新批次，不为旧记录补签身份。');
end
if strcmp(action,'freeze')
    if ~isfile(file),save(file,'contract','-v7');end
    plan.batchSha=local_hash(file);return;
end

% 先验证已有记录。模型索引会读取本批全部已有记录，不能只校验所选记录。
data=struct();models=struct();
for i=1:numel(sc)
    id=sc(i).id;
    f=fullfile(c.middle,id,'stage4_data_record.mat');
    if isfile(f)
        a=load(f,'record');r=a.record;
        local_batch(r,plan.batchSha,id);
        assert(isequaln(r.identity.source,plan.sources.(id)), ...
            'SHT:Stage4:InputIdentity','%s当前选择的测量源与记录不一致，请新建批次。',id);
        local_check(r.measurementFile,r.measurementSha,[id,' measurement']);
        if ~isempty(plan.sources.(id).path)
            assert(strcmpi(local_path(r.measurementFile),plan.sources.(id).path), ...
                'SHT:Stage4:InputIdentity','%s记录的测量路径与本次选择不一致。',id);
        end
        if ~isempty(r.preprocessFile)
            local_check(r.preprocessFile,r.preprocessSha,[id,' preprocessing']);
            local_check(r.preparedWorkbook,r.preparedSha,[id,' prepared Excel']);
        end
        data.(id)=r;
    end
    f=fullfile(c.middle,id,'stage4_model_record.mat');
    if isfile(f)
        a=load(f,'record');r=a.record;local_batch(r,plan.batchSha,id);
        local_check(r.modelFile,r.modelSha,[id,' model']);
        local_check(r.resultFile,r.resultSha,[id,' result']);
        if ~isempty(r.uqFile),local_check(r.uqFile,r.uqSha,[id,' D workbook']);end
        models.(id)=r;
    end
end
% 父子链是只读依赖：父记录的正式Excel必须仍是子记录当时实际使用的文件。
for id=fieldnames(models)'
    r=models.(id{1});
    if ~r.historical
        assert(isfield(data,r.id),'SHT:Stage4:MissingDependency','%s缺少本架次数据记录。',r.id);
        dr=data.(r.id);
        assert(strcmp(r.identity.measurementSha,dr.measurementSha)&& ...
            strcmp(r.identity.preparedSha,dr.preparedSha)&&strcmp(r.identity.preprocessingSha,dr.preprocessSha), ...
            'SHT:Stage4:InputIdentity','%s模型与当前预处理证据不一致。',r.id);
        local_check(r.parentFile,r.identity.parentSha,[r.id,' parent']);
        if ~strcmp(r.parent,'BENCH')
            assert(isfield(models,r.parent),'SHT:Stage4:MissingDependency', ...
                '%s需要父模型%s；请显式先执行父架次。',r.id,r.parent);
            pr=models.(r.parent);
            assert(strcmpi(local_path(pr.modelFile),local_path(r.parentFile))&& ...
                strcmp(pr.modelSha,r.identity.parentSha),'SHT:Stage4:ParentIdentity', ...
                '%s父模型索引已经改变，请使用新批次。',r.id);
        end
    end
end

missing={};
if ismember(action,{'prepare','all','generate'})
    for id=ids
        if strcmp(c.inputMode,'external')&&isempty(plan.sources.(id{1}).path)
            missing{end+1}=[id{1},': externalMeasurements未提供文件']; %#ok<AGROW>
        end
    end
end
available=fieldnames(models)';
plannedData=fieldnames(data)';
if strcmp(action,'all'),plannedData=union(plannedData,ids,'stable');end
if ismember(action,{'estimate','all'})
    for i=1:numel(sc)
        q=sc(i);
        if ~ismember(q.id,ids)||strcmp(q.role,'prediction_only'),continue;end
        historical=q.reuse&&strcmp(c.inputMode,'synthetic_demo');
        if ~historical&&~ismember(q.id,plannedData)
            missing{end+1}=[q.id,': 缺少generate产生的预处理数据']; %#ok<AGROW>
        end
        if ~strcmp(q.parent,'BENCH')&&~ismember(q.parent,available)
            missing{end+1}=[q.id,': 缺少父模型 ',q.parent,'（未选择或尚未完成）']; %#ok<AGROW>
        end
        available=union(available,{q.id},'stable');
    end
end
if ismember(action,{'predict','all'})
    requiredModels={};requiredData={};
    if plan.forecast
        requiredModels={'F01','F02','F03','F04','F05_N'};
        if c.fullReplayEnabled,requiredData={'F06'};end
    end
    if c.fullReplayEnabled&&~isempty(plan.predictionIds)
        requiredModels=union(requiredModels,[{'F04'},plan.predictionIds],'stable');
        requiredData=union(requiredData,plan.predictionIds,'stable');
    end
    for id=reshape(setdiff(requiredModels,available,'stable'),1,[])
        missing{end+1}=['预测/比较需要模型 ',id{1},'；不自动补算']; %#ok<AGROW>
    end
    for id=reshape(setdiff(requiredData,plannedData,'stable'),1,[])
        missing{end+1}=['预测/比较需要测量数据 ',id{1},'；不自动生成']; %#ok<AGROW>
    end
elseif strcmp(action,'report')
    for id=reshape(setdiff(setdiff(ids,{'F06'},'stable'),available,'stable'),1,[])
        missing{end+1}=['报告所选模型尚未完成：',id{1}]; %#ok<AGROW>
    end
end
assert(isempty(missing),'SHT:Stage4:MissingDependency', ...
    '开始计算前发现缺项：\n%s\n请明确补跑依赖或调整scenarioIds；本次未自动扩大执行范围。', ...
    strjoin(missing,newline));
% 预测评估记录按执行范围隔离，并绑定实际读取的父链和测量文件。
modelIds={};dataIds={};
if plan.forecast
    modelIds={'F01','F02','F03','F04','F05_N'};
    if c.fullReplayEnabled,dataIds={'F06'};end
end
if c.fullReplayEnabled&&~isempty(plan.predictionIds)
    modelIds=union(modelIds,[{'F04'},plan.predictionIds],'stable');
    dataIds=union(dataIds,plan.predictionIds,'stable');
end
evidence=struct();
for id=modelIds
    if isfield(models,id{1})
        r=models.(id{1});
        evidence.([id{1},'_model'])={r.modelSha,r.resultSha};
    end
end
for id=dataIds
    if isfield(data,id{1}),evidence.([id{1},'_data'])=data.(id{1}).measurementSha;end
end
plan.predictionIdentity=struct('batchSha',plan.batchSha,'ids',{ids}, ...
    'fullReplayEnabled',c.fullReplayEnabled,'evidence',evidence);
if ismember(action,{'predict','report'})&&isfile(plan.predictionFile)
    old=load(plan.predictionFile,'result');
    assert(isfield(old.result,'identity')&&isequaln(old.result.identity,plan.predictionIdentity), ...
        'SHT:Stage4:PredictionIdentity','该执行范围的预测配置/依赖已变化，不得使用旧评估；请新建批次。');
    if isfield(old.result.frozen,'holdFile')
        local_check(old.result.frozen.holdFile,old.result.frozen.holdSha,'F06 hold');
        local_check(old.result.frozen.trendFile,old.result.frozen.trendSha,'F06 trend');
    end
    for k=1:numel(old.result.replays)
        r=old.result.replays(k);local_check(r.cacheFile,r.cacheSha,'replay cache');
    end
end
end

function contract=local_contract(c,sources)
% 显式覆盖F3编排、三种消费者、动态调用及共享引擎桥接；源路径也参与身份。
t=fileparts(mfilename('fullpath'));
patterns={'sht_f3*.m','sht_stage4*.m','sht_engine_*.m','sht_thermal_*.m'};
names={};
for k=1:numel(patterns)
    f=dir(fullfile(t,patterns{k}));names=[names,{f.name}]; %#ok<AGROW>
end
names=[names,{'Start_Stage4_01_AutomaticModeling.m','Start_FlightModelUQ_R1_02_MethodD.m', ...
    'sht_health_schedule_initialize_dll.m','sht_lookup_clearance_reference.m', ...
    'sht_exhaust_backpressure.m','sht_tc27_thermal_reuse.m','sht_tc27_file_identity.m', ...
    'sht_r2019b_preflight.m','sht_steady_governor_compute.m', ...
    'sht_simulate_control_m.m','sht_load_controller_gain_schedule.m', ...
    'sht_load_engine_library.m'}];
names=unique(names);
f=fullfile(c.middle,'stage4_execution_contract.mat');
if isfile(f)
    old=load(f,'contract');
    assert(isfield(old.contract,'sourceNames')&&strcmp(old.contract.schema,c.schema), ...
        'SHT:Stage4:ExecutionIdentity','旧版批次合同不能续算，请新建批次；禁止重签旧检查点。');
    % 已冻结批次逐项核查其完整源码闭包，连同新增动态入口一起检查。
    names=union(old.contract.sourceNames,names);
else
    names=local_sources(names);
end
files=cellfun(@which,names,'UniformOutput',false);
a=sht_f3_three_component_assets('verifyruntime');
for n={'GTESS.dll','GTESS.h','Turboshaft-TS.mdl','HPC02.MAP','HPT02.MAP','LPT02.MAP'}
    files{end+1}=fullfile(a.runtime,n{1}); %#ok<AGROW>
end
files=[files,{a.visserAsset,a.tc24Posterior,a.instantWorkbook}];
% 普通Np控制默认实际加载此表；加载器源码相同不代表表内容相同。
% 与sht_default_config使用同一源码目录，不从当前目录或根DLL旁猜选。
% ndotSchedule当前默认关闭；若共享配置改变，其源码身份仍会使旧批次拒绝。
controllerRoot=fileparts(which('sht_default_config'));
files{end+1}=fullfile(controllerRoot,'sht_controller_gain_schedule.mat');
if strcmp(c.inputMode,'synthetic_demo')
    files=[files,{c.firstMeasurement,c.firstModel,c.firstResult}];
    % 历史D可不存在，但其缺失/出现也不能改变同一批次身份。
    if isfile(c.firstD),files{end+1}=c.firstD;end
end
files=cellfun(@local_path,files,'UniformOutput',false);
hashes=cellfun(@local_hash,files,'UniformOutput',false);
options=rmfield(c,{'scenarioIds','uqEnabled','plotEnabled','fullReplayEnabled','externalMeasurements'});
contract=struct('schema',c.schema,'files',{files},'sha256',{hashes}, ...
    'sourceNames',{names},'options',options,'sources',sources,'release',version('-release'));
end

function names=local_sources(anchors)
% 新批次发现静态调用闭包，并并入显式动态调用族。仅缓存发现结果，不缓存哈希判断。
% 每次复用前重新核对路径和内容；不因另一个分支修改共享函数而误用旧闭包。
persistent cachedNames cachedPaths cachedHashes;
if ~isempty(cachedNames)&&all(ismember(anchors,cachedNames))
    paths=cellfun(@which,cachedNames,'UniformOutput',false);
    if isequal(paths,cachedPaths)&&all(cellfun(@isfile,paths))
        hashes=cellfun(@local_hash,paths,'UniformOutput',false);
        if isequal(hashes,cachedHashes),names=cachedNames;return;end
    end
end
roots=cellfun(@which,anchors,'UniformOutput',false);
[files,~]=matlab.codetools.requiredFilesAndProducts(roots);
names=anchors;
for i=1:numel(files)
    [~,name,ext]=fileparts(files{i});
    assert(strcmpi(ext,'.m'),'SHT:Stage4:DependencyType', ...
        '新增非M依赖须明确登记后使用：%s。',files{i});
    names{end+1}=[name,ext]; %#ok<AGROW>
end
names=unique(names);cachedNames=names;
cachedPaths=cellfun(@which,names,'UniformOutput',false);
cachedHashes=cellfun(@local_hash,cachedPaths,'UniformOutput',false);
end

function reason=local_difference(old,current)
reason='配置、处理源码或物理依赖改变';
if ~isfield(old,'contract')||~isfield(old.contract,'sources')
    reason='旧版合同，不支持在原数值批次续算';return;
end
a=old.contract;
for id=fieldnames(current.sources)'
    if ~isfield(a.sources,id{1})||~isequaln(a.sources.(id{1}),current.sources.(id{1}))
        reason=[id{1},'测量文件的路径或内容改变'];return;
    end
end
if ~isequaln(a.options,current.options),reason='处理/辨识配置改变';return;end
for i=1:numel(current.files)
    j=find(strcmpi(a.files,current.files{i}),1);
    if isempty(j)||~strcmp(a.sha256{j},current.sha256{i})
        reason=['依赖改变：',current.files{i}];return;
    end
end
end

function local_batch(r,sha,id)
assert(isfield(r,'batchSha')&&strcmp(r.batchSha,sha), ...
    'SHT:Stage4:RecordIdentity','%s不属于当前冻结合同，请使用新批次；禁止重签旧记录。',id);
end
function local_check(file,sha,label)
assert(isfile(file),'SHT:Stage4:MissingDependency','缺少%s：%s。',label,file);
assert(strcmp(local_hash(file),sha),'SHT:Stage4:ArtifactIdentity', ...
    '%s内容已变：%s。请使用新批次，不重签。',label,file);
end
function value=local_hash(file)
assert(isfile(file),'SHT:Stage4:MissingDependency','缺少依赖文件：%s。',file);
value=sht_tc27_file_identity(file);
end
function file=local_path(file)
file=char(file);
assert(~isempty(file),'SHT:Stage4:MissingDependency','依赖源无法定位，请检查MATLAB路径。');
file=char(java.io.File(file).getCanonicalPath());
end
