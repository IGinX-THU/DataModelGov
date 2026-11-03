function out = sht_startstop_modeling_package(action,varargin)
%SHT_STARTSTOP_MODELING_PACKAGE 建模输入、结果与可搬迁候选包的文件合同。
% 原算法逐叶复制、逐叶核SHA；从不复制整个tune，不修改源模型或旧latest。
% hash/verify/view只读。materialize/export才写入明确的新目录。
switch lower(action)
    case 'inventory', out=local_inventory(varargin{1});
    case 'materialize', out=local_materialize(varargin{1},varargin{2});
    case 'verify', out=local_verify(varargin{1});
    case 'context', out=local_context(varargin{1});
    case 'hash', out=local_hash(varargin{1});
    case 'digest', out=local_digest(varargin{1});
    case 'files', out=local_files(varargin{1});
    case 'export', out=local_export_dispatch(varargin{:});
    case 'thermalsource', out=local_thermal_options(varargin{:});
    case 'view', out=local_view(varargin{1});
    case 'fullmodeconfig', out=local_fullmode(varargin{:});
    otherwise, error('sht:modeling:packageAction','未知文件操作：%s。',action);
end
end

function p=local_inventory(cfg)
p=struct('ready',false,'issues',{{}},'files',repmat(local_file(),0,1), ...
    'maps',struct(),'designAvailable',false,'thermalAvailable',false, ...
    'designReference',[]);
if isempty(cfg.taskDirectory),p.issues{end+1}='必须显式指定taskDirectory。';end
roots={'codeDirectory','modelDirectory','dllDirectory'};
for k=1:numel(roots)
    if ~isfolder(cfg.source.(roots{k}))
        p.issues{end+1}=['源目录不存在：source.',roots{k}];
    end
end
if ~isempty(p.issues),return;end
code=local_absolute(cfg.source.codeDirectory); mdlRoot=local_absolute(cfg.source.modelDirectory);
dllRoot=local_absolute(cfg.source.dllDirectory);
if ~isempty(cfg.taskDirectory)
    target=local_absolute(cfg.taskDirectory);
    for r={code,mdlRoot,dllRoot,fileparts(mfilename('fullpath'))}
        if local_under(target,r{1}) || local_under(r{1},target)
            p.issues{end+1}=['任务目录与只读输入/程序目录重叠：',r{1}];
        end
    end
end
mdl=fullfile(mdlRoot,cfg.source.modelFile);
if ~isfile(mdl),p.issues{end+1}=['缺少MDL：',mdl];return;end
text=fileread(mdl);
names={'HPC','HPT','LPT'};
expected='Turboshaft-TS.mdl';
if cfg.modelMode==1,names={'AC','CC','GT1','GT2','PT1','PT2'};expected='Turboshaft-TS-Split.mdl';end
% C初始化仍按固定拓扑文件名加载；不把任意改名的MDL冒充受支持输入。
if ~strcmp(cfg.source.modelFile,expected)
    p.issues{end+1}=['当前DLL要求该拓扑文件名为',expected];
end
mode=regexp(text,'(?m)^\s*offDesignMode\s*=\s*([0-9]+)','tokens','once');
if isempty(mode) || str2double(mode{1})~=2
    p.issues{end+1}='源MDL须为已配置完成的offDesignMode=2；本任务不改写设计参数。';
end
for k=1:numel(names)
    n=names{k};
    block=regexp(text,['\[componentName\]\s*=\s*',n,'\s*\r?\n([\s\S]*?)(?=\[componentName\]|$)'],'tokens','once');
    if isempty(block),p.issues{end+1}=['所选MDL缺少部件',n];continue;end
    m=regexp(block{1},'(?m)^\s*mapPath\s*=\s*([^\r\n]+)','tokens','once');
    if isempty(m),p.issues{end+1}=['部件缺少mapPath：',n];continue;end
    map=strtrim(m{1});
    if contains(map,'..') || contains(map,'\') || contains(map,'/') || contains(map,':')
        p.issues{end+1}=['首轮需模型目录内的MAP叶文件：',map];continue;
    end
    p.maps.(n)=map;
    p=local_add(p,fullfile(mdlRoot,map),'original_map',fullfile('TestData','source_model',map));
end
p=local_add(p,mdl,'model',fullfile('TestData','source_model',expected));
for n={'GTESS.dll','GTESS.h','blockAndFunctions.h','types_TMATS.H'}
    p=local_add(p,fullfile(dllRoot,n{1}),'engine_interface',fullfile('TestData','source_model',n{1}));
end
% 递归追踪已知算法名字，另列动态调用入口。只解析ASCII标识符，不转码旧源码。
queue={'sht_startstop_default_config','sht_startstop_run_map_stages', ...
    'sht_startstop_create_runtime','sht_startstop_stage_asset', ...
    'sht_startstop_map_parameters','sht_startstop_verify_physics_kernel', ...
    'sht_startstop_write_candidate_maps','Start_StartStopModel_ThreeComponent', ...
    'Start_StartStopModel_03_LowSpeedMatrixAndConstrainedCalibration', ...
    'Start_StartStopModel_04_ContinuousStartStopAndRobustness', ...
    'Start_StartStopModel_05_VisserThermalCouplingAndFreeze', ...
    'RunModelSHT_V2_2DP','sht_fullmode_session','Run_FullModeSimulation_Offline', ...
    'Start_FullModeSimulation_01','Start_FullModeSimulation_ResultView_01', ...
    'Start_TC27_ThermalPreparationResultView_01','sht_tc27_file_identity'};
seen={};
while ~isempty(queue)
    name=queue{1};queue(1)=[];
    if ismember(name,seen),continue;end
    seen{end+1}=name; %#ok<AGROW>
    file=fullfile(code,[name,'.m']);
    p=local_add(p,file,'algorithm_source',fullfile('MiddleData','engine_code',[name,'.m']));
    if ~isfile(file),continue;end
    refs=regexp(fileread(file),'\<(sht_[A-Za-z0-9_]+|Start_StartStopModel_[A-Za-z0-9_]+|RunModelSHT_V2_2DP)\s*\(','tokens');
    for j=1:numel(refs)
        if isfile(fullfile(code,[refs{j}{1},'.m'])),queue{end+1}=refs{j}{1};end %#ok<AGROW>
    end
end
% MDL结构解析器位于独立子目录；不能依赖开发机恰好已addpath。
p=local_add(p,fullfile(code,'design_point_modeling','sht_design_point_mdl.m'), ...
    'algorithm_source',fullfile('MiddleData','engine_code','design_point_modeling','sht_design_point_mdl.m'));
for n={'sht_controller_gain_schedule.mat','sht_controller_ndot_schedule.mat','matlab_loadlibrary_include/stdio.h'}
    p=local_add(p,fullfile(code,n{1}),'runtime_support',fullfile('MiddleData','engine_code',n{1}));
end
if ~isempty(cfg.source.designStateFile)
    designName=sprintf('RunModelSHT_V%d_design_state.mat',cfg.modelMode+1);
    p=local_add(p,cfg.source.designStateFile,'design_input', ...
        fullfile('MiddleData','engine_code','MiddleData',designName));
    p.designAvailable=isfile(cfg.source.designStateFile);
    if p.designAvailable
        try
            p.designReference=local_design_reference(cfg.source.designStateFile,mdl,cfg.modelMode);
        catch ex
            p.issues{end+1}=['设计状态与模型不相容：',ex.message];
        end
    end
end
if ~isempty(cfg.source.thermalFile)
    p=local_add(p,cfg.source.thermalFile,'thermal_input',fullfile('TestData','upstream','thermal_parameters.mat'));
    p.thermalAvailable=isfile(cfg.source.thermalFile);
end
adapter=fileparts(mfilename('fullpath'));
for n={'Start_StartStopModeling_01','sht_startstop_modeling_config', ...
        'sht_startstop_modeling_task','sht_startstop_modeling_package', ...
        'Start_StartStopModeling_ResultView_01','Test_StartStopModeling_01'}
    p=local_add(p,fullfile(adapter,[n{1},'.m']),'adapter_source',fullfile('TestData','adapter_identity',[n{1},'.m']));
end
p.ready=isempty(p.issues);
end

function r=local_design_reference(stateFile,mdl,mode)
% 显式设计结果是求解后的共同工作解，不是设计初猜。先检查配对关系，
% 再交给设计回放和控制线性化；本函数只读文件，不加载DLL。
loaded=load(stateFile,'designState');
assert(isfield(loaded,'designState'),'sht:modeling:designState','文件缺少designState。');
s=loaded.designState;
assert(isstruct(s) && isscalar(s) && isfield(s,'modelMode') && s.modelMode==mode, ...
    'sht:modeling:designTopology','三/六部件设计状态不能混用。');
assert(isfield(s,'design') && isfield(s.design,'converged') && s.design.converged, ...
    'sht:modeling:designNotSolved','设计状态不是已收敛的设计解。');
d=s.design;n=6+3*mode;x=d.commonVariables(:);
assert(numel(x)==n && all(isfinite(x)) && isfinite(d.Wf) && d.Wf>0, ...
    'sht:modeling:designState','共同工作解维数或实际燃油量非法。');
t=fileread(mdl);configured=local_mdl_value(t,'','varStartVec');
local_design_equal(x,configured,'varStartVec');
r=struct('schema',26101401,'modelMode',mode,'commonVariables',x, ...
    'NpRpm',x(end-1),'NgRpm',x(end),'fuelFlowKgPerS',d.Wf, ...
    'loadPowerW',NaN,'accessoryPowerW',NaN,'nozzleAreaM2',NaN, ...
    'targetTt4K',NaN,'sourceModelSHA256',local_hash(mdl), ...
    'designStateSHA256',local_hash(stateFile),'expectedOutput',d.output(:).');
assert(numel(r.expectedOutput)==10 && all(isfinite(r.expectedOutput)), ...
    'sht:modeling:designState','设计输出必须为当前V1/V2定义的10通道。');
if mode==1
    assert(isfield(s,'schemaVersion') && s.schemaVersion>=5 && isfield(s,'designTargets'), ...
        'sht:modeling:designState','六部件需要V2 schema>=5及其完整设计目标。');
    target=s.designTargets;
    for f={'NpRpm','NgRpm','loadPowerW','accessoryPowerW','nozzleAreaM2','targetTt4K'}
        validateattributes(target.(f{1}),{'numeric'},{'scalar','real','finite'});
    end
    local_design_equal([r.NpRpm;r.NgRpm],[target.NpRpm;target.NgRpm],'设计转速');
    r.loadPowerW=target.loadPowerW;r.accessoryPowerW=target.accessoryPowerW;
    r.nozzleAreaM2=target.nozzleAreaM2;r.targetTt4K=target.targetTt4K;
    names={'AC','CC','GT1','GT2','PT1','PT2'};keys=names;ncompressors=2;
    r.targetSource='V2 designTargets; offDesignMode=2 uses explicit boundary inputs';
else
    assert(isfield(s,'targetTt4K'),'sht:modeling:designState','三部件设计状态缺少Tt4目标。');
    % V1记录只含Tt4目标；其余边界取与该设计解逐项配对的配置MDL。
    r.loadPowerW=local_mdl_value(t,'','PowerOutLPS');
    r.accessoryPowerW=local_mdl_value(t,'','PowerOutHPS');
    r.nozzleAreaM2=local_mdl_value(t,'Nozzle','aeroThroat');
    r.targetTt4K=s.targetTt4K;
    local_design_equal(r.targetTt4K,local_mdl_value(t,'','TtBurnerOut'),'Tt4目标');
    names={'HPC','HPT','LPT'};keys={'HPC','GT','PT'};ncompressors=1;
    r.targetSource='V1 solved state plus paired configured MDL boundaries';
end
validateattributes([r.NpRpm,r.NgRpm,r.loadPowerW,r.nozzleAreaM2,r.targetTt4K], ...
    {'numeric'},{'real','finite','positive'});
validateattributes(r.accessoryPowerW,{'numeric'},{'scalar','real','finite','nonnegative'});
local_design_equal(r.nozzleAreaM2,local_mdl_value(t,'Nozzle','aeroThroat'),'喷口面积');
for k=1:numel(names)
    if k<=ncompressors,fields={'s_C_Nc_in','s_C_Wc_in','s_C_PR_in','s_C_Eff_in'};
    else,fields={'s_T_Nc','s_T_Wc','s_T_PR','s_T_Eff'};end
    actual=zeros(4,1);
    for j=1:4,actual(j)=local_mdl_value(t,names{k},fields{j});end
    local_design_equal(actual,d.scalars.(keys{k}),[names{k},'缩放系数']);
end
% 当前设计模块采用地面标准环境；不能在消费时静默换成另一套环境。
local_design_equal([local_mdl_value(t,'','altitude');local_mdl_value(t,'','machNumber'); ...
    local_mdl_value(t,'','dTemperature')],zeros(3,1),'设计环境');
r.inheritedParameters={'controller gains','shaft inertia','physical limits', ...
    'thermal capacities','cooling split prior'};
end

function value=local_mdl_value(text,component,key)
if isempty(component)
    first=regexp(text,'\[componentName\]','start','once');
    if ~isempty(first),text=text(1:first-1);end
else
    block=regexp(text,['\[componentName\]\s*=\s*',regexptranslate('escape',component), ...
        '\s*\r?\n([\s\S]*?)(?=\[componentName\]|$)'],'tokens');
    assert(numel(block)==1,'sht:modeling:designMdl','部件%s缺失或重复。',component);
    text=block{1}{1};
end
tokens=regexp(text,['(?m)^\s*',regexptranslate('escape',key),'\s*=([^\r\n]+)'],'tokens');
assert(numel(tokens)==1,'sht:modeling:designMdl','字段%s.%s缺失或重复。',component,key);
value=sscanf(tokens{1}{1},'%f');
assert(~isempty(value) && all(isfinite(value)),'sht:modeling:designMdl','字段%s不是有限数值。',key);
end

function local_design_equal(a,b,name)
a=a(:);b=b(:);
assert(numel(a)==numel(b) && all(abs(a-b)<=1e-8.*max(1,abs(a))), ...
    'sht:modeling:designPair','%s与设计状态不一致，不能消费错配资产。',name);
end

function p=local_add(p,path,role,relative)
if any(strcmp({p.files.relative},relative)),return;end
f=local_file();f.source=local_absolute(path);f.relative=relative;f.role=role;
if isfile(path)
    d=dir(path);f.bytes=d.bytes;f.sha256=local_hash(path);
else
    p.issues{end+1}=['缺少',role,'：',path];
end
p.files(end+1)=f;
end

function x=local_file()
x=struct('source','','relative','','role','','bytes',0,'sha256','');
end

function bundle=local_materialize(cfg,preflight)
assert(preflight.ready,'sht:modeling:notReady','输入检查未通过，不能物化。');
root=local_absolute(cfg.taskDirectory);
assert(~isfolder(root) && ~isfile(root),'sht:modeling:exists','任务目录已存在，拒绝覆盖：%s。',root);
mkdir(root);
records=preflight.files;
for k=1:numel(records)
    r=records(k);
    assert(strcmp(local_hash(r.source),r.sha256),'sht:modeling:sourceChanged','准备期间源文件变化：%s。',r.source);
    local_copy(r.source,fullfile(root,r.relative),r.sha256);
end
code=fullfile(root,'MiddleData','engine_code');
src=fullfile(root,'TestData','source_model');
% 旧入口要求原MDL/DLL在M目录，stage_asset又要求C目录配对；此处同源复制。
for k=1:numel(records)
    if ismember(records(k).role,{'model','original_map','engine_interface'})
        [~,n,e]=fileparts(records(k).relative);r=records(k);
        r.relative=fullfile('MiddleData','engine_code',[n,e]);
        local_copy(fullfile(root,records(k).relative),fullfile(root,r.relative),r.sha256);
        records(end+1)=r; %#ok<AGROW>
    end
end
bundle=struct('root',root,'codeDirectory',code,'sourceModelDirectory',src, ...
    'files',records,'createdAt',datestr(now,31));
bundle.identity=local_digest(rmfield(records,'source'));
mkdir(fullfile(root,'report_outputs'));mkdir(fullfile(root,'MiddleData','task_state'));
local_verify(bundle);
end

function report=local_verify(bundle)
bad={};
for k=1:numel(bundle.files)
    r=bundle.files(k);p=fullfile(bundle.root,r.relative);
    if ~local_under(p,bundle.root) || ~isfile(p) || ~strcmp(local_hash(p),r.sha256)
        bad{end+1}=r.relative; %#ok<AGROW>
    end
end
assert(isempty(bad),'sht:modeling:identityChanged','私有输入/源码身份变化：%s。',strjoin(bad,', '));
% 任务执行依赖当前适配源码，不能把开发中修改的任务程序冒充旧检查点。
adapter=fileparts(mfilename('fullpath'));
rows=bundle.files(strcmp({bundle.files.role},'adapter_source'));
for k=1:numel(rows)
    [~,n,e]=fileparts(rows(k).relative);
    assert(strcmp(local_hash(fullfile(adapter,[n,e])),rows(k).sha256), ...
        'sht:modeling:adapterChanged','适配源码已变化，请建新任务，不重签旧任务：%s。',n);
end
report=struct('passed',true,'checkedFiles',numel(bundle.files),'checkedAt',datestr(now,31));
end

function cleaner=local_context(bundle)
local_verify(bundle);
oldPath=path;oldDir=pwd;
cleaner=onCleanup(@()local_restore(oldPath,oldDir));
addpath(bundle.codeDirectory,'-begin');
addpath(fullfile(bundle.codeDirectory,'design_point_modeling'),'-begin');cd(bundle.codeDirectory);
rows=bundle.files(strcmp({bundle.files.role},'algorithm_source'));
for k=1:numel(rows)
    [~,n]=fileparts(rows(k).relative);
    expected=fullfile(bundle.root,rows(k).relative);
    assert(strcmpi(local_absolute(which(n)),local_absolute(expected)), ...
        'sht:modeling:resolution','函数解析未指向任务私有源码：%s。',n);
end
end

function local_restore(p,d)
cd(d);path(p);
end

function delivered=local_export(task,destination,options)
local_verify(task.bundle);
destination=local_absolute(destination);
assert(~isfolder(destination) && ~isfile(destination), ...
    'sht:modeling:exportExists','保存目标已存在，拒绝覆盖历史包。');
assert(~local_under(destination,task.bundle.sourceModelDirectory) && ...
    ~local_under(destination,task.bundle.codeDirectory), ...
    'sht:modeling:exportPath','不能向任务源模型或执行源码目录保存成果。');
for name={'codeDirectory','modelDirectory','dllDirectory'}
    assert(~local_under(destination,task.config.source.(name{1})), ...
        'sht:modeling:exportPath','不能向原始只读输入目录内保存候选。');
end
mkdir(destination);
package=struct('schema',26101301,'taskId',task.taskId,'modelMode',task.config.modelMode, ...
    'savedAt',datestr(now,31),'status',task.status,'configuration',task.config, ...
    'sourceIdentity',task.bundle.identity,'engineConfiguration',struct(), ...
    'stages',task.stages,'results',struct(),'assets',struct(), ...
    'runtimeReady',false,'thermalReady',false,'limitations',{{ ...
    '工程先验与数值校核，不等于实测标定；未实施参数UQ。', ...
    '仅当前明确来源的发动机配置；不承诺任意MDL或新机器可用。', ...
    '阶段安全点恢复不等于积分中途恢复；旧全模式快照不换身份。'}});
try
    % 精确复制代码和原始运行输入，不导出可再生桥接文件或历史缓存。
    for k=1:numel(task.bundle.files)
        r=task.bundle.files(k);
        if strcmp(r.role,'algorithm_source') || strcmp(r.role,'runtime_support')
            rel=erase(r.relative,['MiddleData',filesep,'engine_code',filesep]);
            local_copy(fullfile(task.taskDirectory,r.relative),fullfile(destination,'program',rel),r.sha256);
        elseif strcmp(r.role,'adapter_source')
            [~,n,e]=fileparts(r.relative);
            local_copy(fullfile(task.taskDirectory,r.relative),fullfile(destination,'program','startupstop_modeling',[n,e]),r.sha256);
        elseif ismember(r.role,{'model','original_map','engine_interface'}) && startsWith(r.relative,'TestData')
            [~,n,e]=fileparts(r.relative);
            local_copy(fullfile(task.taskDirectory,r.relative),fullfile(destination,'program',[n,e]),r.sha256);
            local_copy(fullfile(task.taskDirectory,r.relative),fullfile(destination,'C',[n,e]),r.sha256);
            if strcmp([n,e],'GTESS.dll')
                local_copy(fullfile(task.taskDirectory,r.relative),fullfile(destination,'C','x64','Release','GTESS.dll'),r.sha256);
            end
        elseif strcmp(r.role,'thermal_input')
            package.assets.thermalFile=fullfile('assets','thermal_parameters.mat');
            local_copy(fullfile(task.taskDirectory,r.relative),fullfile(destination,package.assets.thermalFile),r.sha256);
        elseif strcmp(r.role,'design_input')
            [~,n,e]=fileparts(r.relative);
            rel=fullfile('program','MiddleData',[n,e]);
            local_copy(fullfile(task.taskDirectory,r.relative),fullfile(destination,rel),r.sha256);
        end
    end
    fields=fieldnames(task.stages);
    for k=1:numel(fields)
        s=task.stages.(fields{k});
        if isempty(s.resultFile),continue;end
        local_check_evidence(task,s);
        d=load(fullfile(task.taskDirectory,s.resultFile),'result');package.results.(fields{k})=d.result;
        for j=1:numel(s.evidence)
            item=s.evidence(j);rel=fullfile('evidence',fields{k},item.relative);
            local_copy(fullfile(task.taskDirectory,s.attemptDirectory,item.relative),fullfile(destination,rel),item.sha256);
        end
    end
    context=local_context(task.bundle); %#ok<NASGU>
    e=sht_startstop_modeling_task('engineConfig',task);
    package.engineConfiguration=e;
    mapResult=[];
    if isfield(package.results,'matrix') && strcmp(task.stages.matrix.status,'completed') ...
            && local_selected_pass(package.results.matrix)
        r=package.results.matrix;
        if isfield(r,'matrix'),r=r.matrix;end
        mapResult=r.finalMapAudit;
        result=struct('finalMatrix',struct('points',r.finalMatrix.points), ...
            'accepted',true,'scope','Selected matrix only; see package evidence'); %#ok<NASGU>
        package.assets.seedPoolFile=fullfile('assets','seed_pool.mat');
        local_mkdir(fileparts(fullfile(destination,package.assets.seedPoolFile)));
        save(fullfile(destination,package.assets.seedPoolFile),'result','-v7');
        if task.config.modelMode==0
            package.engineConfiguration.startStop.designRotorPowerW=r.design.rotorPowerW;
            package.engineConfiguration.startStop.nozzleAreaM2=r.design.nozzleAreaM2;
        end
    elseif isfield(package.results,'maps') && strcmp(task.stages.maps.status,'completed')
        r=package.results.maps;if isfield(r,'maps'),r=r.maps;end
        mapResult=r.mapResult;
    end
    if ~isempty(mapResult)
        package.assets.mapDirectory=fullfile('assets','maps');
        for k=1:numel(mapResult.items)
            item=mapResult.items(k);name=e.maps.(item.name).outputName;
            local_copy(item.outputPath,fullfile(destination,package.assets.mapDirectory,name),local_hash(item.outputPath));
        end
        % 复用原配置生成器，只在任务内生成，再把候选MDL作为可审计产物保存。
        runtime=sht_startstop_create_runtime(e,mapResult,fullfile(task.taskDirectory,'MiddleData',['Export_',datestr(now,'HHMMSSFFF')]));
        package.assets.candidateModelFile=fullfile('assets','candidate_model',e.topology.modelFile);
        local_copy(runtime.modelPath,fullfile(destination,package.assets.candidateModelFile),local_hash(runtime.modelPath));
    end
    package.runtimeReady=isfield(package.assets,'seedPoolFile') && isfield(package.assets,'mapDirectory');
    if isfield(package.assets,'thermalFile')
        package.thermalReady=local_thermal_check(fullfile(destination,package.assets.thermalFile),e);
    end
    clear context;
    % 所有供执行使用的路径在消费者端根据包根重新构造；原绝对路径只留来源。
    package.engineConfiguration=local_portable_engine(package.engineConfiguration);
    package.sourcePackageIdentity=struct('kind','completed_task','identity',task.bundle.identity, ...
        'historicalCodeIdentity',task.bundle.identity);
    package=local_make_thermal_source(destination,package);
    package=local_attach_thermal(destination,package,options);
    package.executionIdentity=local_execution_identity(destination);
    save(fullfile(destination,'modeling_package.mat'),'package','-v7.3');
    local_write_excel(package,fullfile(destination,'modeling_summary.xlsx'));
    manifest=local_files(destination);
    writetable(struct2table(manifest),fullfile(destination,'files_sha256.csv'),'Encoding','UTF-8');
    delivered=struct('saved',true,'directory',destination,'runtimeReady',package.runtimeReady, ...
        'thermalReady',package.thermalReady,'thermalSourceReady',package.thermalSourceReady, ...
        'excel',fullfile(destination,'modeling_summary.xlsx'), ...
        'manifest',fullfile(destination,'files_sha256.csv'));
catch ex
    failure=struct('identifier',ex.identifier,'message',ex.message,'time',datestr(now,31)); %#ok<NASGU>
    save(fullfile(destination,'save_failure.mat'),'failure','-v7');
    rethrow(ex);
end
end

function delivered=local_export_dispatch(source,destination,options)
if nargin<3,options=struct();end
assert(isstruct(options) && isscalar(options) && ...
    all(ismember(fieldnames(options),{'executionCodeDirectory','thermalPreparationResultFile'})), ...
    'sht:modeling:exportOptions','保存选项只允许执行源码根和明确的完成热结果。');
if ischar(source) || (isstring(source) && isscalar(source))
    delivered=local_export_saved(char(source),destination,options);
else
    assert(~isfield(options,'executionCodeDirectory'),'sht:modeling:taskExecution', ...
        '活动任务保持其已核源码；更换执行代码请从已保存包另存，不重签任务。');
    delivered=local_export(source,destination,options);
end
end

function [p,rows,missingRuntime]=local_read_package(folder,readOnlyView)
if nargin<2,readOnlyView=false;end
missingRuntime={};
folder=local_absolute(folder);manifest=fullfile(folder,'files_sha256.csv');
assert(isfile(manifest),'sht:modeling:packageIncomplete','保存包缺少完整清单。');
rows=readtable(manifest,'Delimiter',',','Encoding','UTF-8','Format','%q%f%q','TextType','string');
assert(isequal(rows.Properties.VariableNames,{'relative','bytes','sha256'}) && ...
    numel(unique(lower(rows.relative)))==height(rows), ...
    'sht:modeling:packageManifest','包清单列或路径唯一性错误。');
for k=1:height(rows)
    f=local_child_file(folder,char(rows.relative(k)));d=dir(f);
    % 历史查看不需要加载DLL，允许其缺失，但不允许现存文件被篡改。
    % 导出、热来源和实际运行仍要求所有声明文件完整。
    if readOnlyView && ~isfile(f) && endsWith(lower(char(rows.relative(k))),'.dll')
        missingRuntime{end+1}=char(rows.relative(k));continue; %#ok<AGROW>
    end
    assert(isfile(f) && isfinite(rows.bytes(k)) && ~isempty(d) && ...
        d.bytes==rows.bytes(k) && strcmpi(local_hash(f),char(rows.sha256(k))), ...
        'sht:modeling:packageChanged','模型包文件缺失或身份变化：%s。',f);
end
assert(any(strcmp(rows.relative,'modeling_package.mat')), ...
    'sht:modeling:packageManifest','完成清单必须包含modeling_package.mat。');
d=load(fullfile(folder,'modeling_package.mat'),'package');p=d.package;
assert(isstruct(p) && isscalar(p) && ismember(p.modelMode,[0,1]), ...
    'sht:modeling:packageSchema','保存包格式不支持。');
end

function f=local_child_file(root,relative)
assert(ischar(relative) && ~isempty(relative) && isempty(regexp(relative,'^[\\/]|:','once')), ...
    'sht:modeling:relativePath','需要包内相对路径。');
parts=regexp(relative,'[\\/]','split');
assert(~any(ismember(parts,{'..','.'})), 'sht:modeling:relativePath','路径不得含.或..。');
f=local_absolute(fullfile(root,relative));
assert(local_under(f,root) && ~strcmpi(f,local_absolute(root)), ...
    'sht:modeling:relativePath','文件路径越出明确包根。');
end

function delivered=local_export_saved(source,destination,options)
source=local_absolute(source);[p,rows]=local_read_package(source);
destination=local_absolute(destination);
code=fileparts(fileparts(mfilename('fullpath')));
if isfield(options,'executionCodeDirectory'),code=local_absolute(options.executionCodeDirectory);end
assert(~isfolder(destination) && ~isfile(destination) && ...
    ~local_under(destination,source) && ~local_under(source,destination) && ...
    ~local_under(destination,code) && ~local_under(code,destination), ...
    'sht:modeling:exportPath','另存必须使用不与旧包/执行源码重叠的新目录。');
% 新代码仅按依赖清单供件；物理输入来自旧包，不用新代码根的MDL替换。
execution=local_execution_sources(code,rows);
for n={'GTESS.dll','GTESS.h','blockAndFunctions.h','types_TMATS.H', ...
        'sht_controller_gain_schedule.mat','sht_controller_ndot_schedule.mat'}
    assert(strcmpi(local_hash(fullfile(source,'program',n{1})),local_hash(fullfile(code,n{1}))), ...
        'sht:modeling:executionPair','新执行源与旧包配套接口/控制资产不一致：%s。',n{1});
end
mkdir(destination);
oldSource='';
if isfield(p.assets,'thermalSourceDirectory'),oldSource=p.assets.thermalSourceDirectory;end
for k=1:height(rows)
    rel=char(rows.relative(k));
    if ismember(rel,{'modeling_package.mat','modeling_summary.xlsx','execution_sources.csv'}) || ...
            (startsWith(rel,['program',filesep]) && endsWith(rel,'.m')) || ...
            (~isempty(oldSource) && startsWith(rel,[oldSource,filesep]))
        continue;
    end
    local_copy(fullfile(source,rel),fullfile(destination,rel),char(rows.sha256(k)));
end
for k=1:numel(execution)
    r=execution(k);local_copy(r.source,fullfile(destination,'program',r.relative),r.sha256);
end
oldManifestHash=local_hash(fullfile(source,'files_sha256.csv'));
rel=fullfile('evidence','source_packages',oldManifestHash,'files_sha256.csv');
if ~isfile(fullfile(destination,rel))
    local_copy(fullfile(source,'files_sha256.csv'),fullfile(destination,rel),oldManifestHash);
end
historicalMAT=fullfile(fileparts(rel),'modeling_package.mat');
if ~isfile(fullfile(destination,historicalMAT))
    local_copy(fullfile(source,'modeling_package.mat'),fullfile(destination,historicalMAT), ...
        local_hash(fullfile(source,'modeling_package.mat')));
end
p.sourcePackageIdentity=struct('kind','saved_package','manifestSHA256',oldManifestHash, ...
    'packageMAT_SHA256',local_hash(fullfile(source,'modeling_package.mat')), ...
    'historicalTaskId',p.taskId,'manifestRelative',rel,'packageRelative',historicalMAT, ...
    'historicalExecutionUnchanged',true,'notCheckpointResume',true);
p.savedAt=datestr(now,31);p.deliveryContractVersion=26101501;
context=local_code_context(fullfile(destination,'program')); %#ok<NASGU>
p=local_make_thermal_source(destination,p);
p=local_attach_thermal(destination,p,options);
p.executionIdentity=local_execution_identity(destination);
% 只有末尾清单写成才视为完整包；中途失败不能成为可读取的正式结果。
package=p;save(fullfile(destination,'modeling_package.mat'),'package','-v7.3');
local_write_excel(p,fullfile(destination,'modeling_summary.xlsx'));
manifest=local_files(destination);
writetable(struct2table(manifest),fullfile(destination,'files_sha256.csv'),'Encoding','UTF-8');
delivered=struct('saved',true,'directory',destination,'runtimeReady',p.runtimeReady, ...
    'thermalReady',p.thermalReady,'thermalSourceReady',p.thermalSourceReady, ...
    'manifest',fullfile(destination,'files_sha256.csv'),'excel',fullfile(destination,'modeling_summary.xlsx'));
end

function records=local_execution_sources(code,oldRows)
% 保存包的执行闭包与历史来源清单分开；只识别项目ASCII函数名。
records=repmat(local_file(),0,1);queue={};
for k=1:height(oldRows)
    rel=char(oldRows.relative(k));
    if startsWith(rel,['program',filesep]) && endsWith(rel,'.m'),queue{end+1}=rel(9:end);end %#ok<AGROW>
end
queue=[queue,{'design_point_modeling/sht_design_point_mdl.m', ...
    'Start_TC27_ThermalPreparationResultView_01.m','sht_tc27_file_identity.m'}];
while ~isempty(queue)
    rel=strrep(queue{1},'/',filesep);queue(1)=[];
    if any(strcmp({records.relative},rel)),continue;end
    f=local_child_file(code,rel);assert(isfile(f),'sht:modeling:dependency','缺少交付依赖：%s。',f);
    r=local_file();r.source=f;r.relative=rel;r.role='execution_source';
    d=dir(f);r.bytes=d.bytes;r.sha256=local_hash(f);records(end+1)=r; %#ok<AGROW>
    refs=regexp(fileread(f),'\<(sht_[A-Za-z0-9_]+|Start_FullMode[A-Za-z0-9_]+)\s*\(','tokens');
    for j=1:numel(refs)
        name=[refs{j}{1},'.m'];
        if isfile(fullfile(code,name)),queue{end+1}=name;end %#ok<AGROW>
    end
end
end

function identity=local_execution_identity(folder)
files=local_files(fullfile(folder,'program'));files=files(endsWith({files.relative},'.m'));
writetable(struct2table(files),fullfile(folder,'execution_sources.csv'),'Encoding','UTF-8');
identity=struct('schema',26101501,'files',files,'manifestRelative','execution_sources.csv', ...
    'manifestSHA256',local_hash(fullfile(folder,'execution_sources.csv')), ...
    'identity',local_digest(files),'purpose','Actual code for new sessions; not historical result producer');
end

function p=local_make_thermal_source(folder,p)
p.thermalSourceReady=false;p.thermalSourceIssue='当前公开继承热来源仅支持三部件真实设计及扩展图。';
state=fullfile(folder,'program','MiddleData','RunModelSHT_V1_design_state.mat');
if p.modelMode~=0 || ~isfile(state) || ~isfield(p.assets,'candidateModelFile') || ~isfield(p.assets,'mapDirectory'),return;end
context=local_code_context(fullfile(folder,'program')); %#ok<NASGU>
source=fullfile(folder,'program','Turboshaft-TS.mdl');
runtime=local_child_file(folder,p.assets.candidateModelFile);
reference=local_design_reference(state,source,0);
maps=local_derived_model(source,runtime);
rel=fullfile('assets','thermal_source');targetRoot=fullfile(folder,rel);mkdir(targetRoot);
names=[{'GTESS.dll','GTESS.h','blockAndFunctions.h','types_TMATS.H','Turboshaft-TS.mdl'},maps];
rows=cell(8,5);
for k=1:8
    if k<=4,f=fullfile(folder,'program',names{k});role='paired_engine_interface';
    elseif k==5,f=runtime;role='derived_runtime_model';
    else,f=fullfile(folder,p.assets.mapDirectory,names{k});role='extended_low_speed_map';end
    target=fullfile(targetRoot,'runtime',names{k});h=local_hash(f);local_copy(f,target,h);d=dir(f);
    rows(k,:)={names{k},['runtime/',names{k}],sprintf('%.0f',d.bytes),h,role};
end
t=cell2table(rows,'VariableNames',{'Name','SourcePath','Bytes','SHA256','Role'});
csv=fullfile(targetRoot,'runtime_eight_files.csv');writetable(t,csv,'Encoding','UTF-8');
lineage=struct('ModelMode',0,'OffDesignMode',2,'DerivedModelOnlyMapPathsAndEOLChanged',true, ...
    'SourceModelSHA256',local_hash(source),'RuntimeModelSHA256',local_hash(runtime), ...
    'DesignReference',reference,'EightFileManifestSHA256',local_hash(csv), ...
    'SourcePathBase','physicalManifestFile_directory','sourceModelRelative','program/Turboshaft-TS.mdl', ...
    'designStateRelative','program/MiddleData/RunModelSHT_V1_design_state.mat', ...
    'configurationSHA256',local_hash(fullfile(folder,'program','sht_default_config.m')), ...
    'controllerGainRelative','program/sht_controller_gain_schedule.mat', ...
    'controllerGainSHA256',local_hash(fullfile(folder,'program','sht_controller_gain_schedule.mat')));
local_write_json(fullfile(targetRoot,'lineage.json'),lineage);
p.assets.thermalSourceDirectory=rel;p.thermalSourceReady=true;p.thermalSourceIssue='';
end

function maps=local_derived_model(source,runtime)
a=sht_design_point_mdl('read',source);b=sht_design_point_mdl('read',runtime);
assert(numel(a.assignments)==numel(b.assignments),'sht:modeling:derivedModel','派生MDL字段数变化。');
text=a.text;indices=[];maps=cell(1,3);names={'HPC','HPT','LPT'};
for k=1:numel(a.assignments)
    x=a.assignments(k);y=b.assignments(k);
    assert(strcmp(x.component,y.component) && strcmp(x.key,y.key),'sht:modeling:derivedModel','MDL字段顺序不一致。');
    if strcmp(x.key,'mapPath') && ismember(x.component,names)
        map=strtrim(y.value);
        assert(isempty(regexp(map,'[\\/:]|\.\.','once')) && ~isempty(map), ...
            'sht:modeling:derivedModel','MAP必须为包内叶文件。');
        maps{strcmp(names,x.component)}=map;indices(end+1)=k; %#ok<AGROW>
    else
        assert(strcmp(x.value,y.value),'sht:modeling:derivedModel','派生MDL改变了%s.%s。',x.component,x.key);
    end
end
assert(numel(indices)==3 && numel(unique(maps))==3,'sht:modeling:derivedModel','需三份独立图。');
for k=fliplr(indices)
    x=a.assignments(k);y=b.assignments(k);
    text=[text(1:x.start-1),x.prefix,y.value,x.suffix,text(x.stop+1:end)];
end
assert(strcmp(regexprep(text,'\r\n|\r','\n'),regexprep(b.text,'\r\n|\r','\n')), ...
    'sht:modeling:derivedModel','MDL变化不止三条MAP路径和换行。');
assert(sht_design_point_mdl('value',runtime,'','offDesignMode')==2, ...
    'sht:modeling:derivedModel','运行MDL必须为mode2。');
end

function [s,lineage]=local_source_fields(folder,p)
assert(isfield(p,'thermalSourceReady') && p.thermalSourceReady, ...
    'sht:modeling:thermalSourceMissing','保存包尚无有效三部件热来源；需真实设计MAT及扩展图，六部件不可走此分支。');
base=local_child_file(folder,p.assets.thermalSourceDirectory);
lineage=local_read_json(fullfile(base,'lineage.json'));
csv=fullfile(base,'runtime_eight_files.csv');
assert(strcmpi(local_hash(csv),lineage.EightFileManifestSHA256),'sht:modeling:thermalSource','八文件清单SHA变化。');
s=struct('runtimeDirectory',fullfile(base,'runtime'),'physicalManifestFile',csv, ...
    'physicalManifestSHA256',local_hash(csv),'lineageFile',fullfile(base,'lineage.json'), ...
    'lineageSHA256',local_hash(fullfile(base,'lineage.json')), ...
    'sourceModelFile',local_child_file(folder,lineage.sourceModelRelative), ...
    'designStateFile',local_child_file(folder,lineage.designStateRelative), ...
    'configurationSHA256',lineage.configurationSHA256, ...
    'controllerGainFile',local_child_file(folder,lineage.controllerGainRelative), ...
    'controllerGainSHA256',lineage.controllerGainSHA256, ...
    'candidatePackageId',[p.taskId,'_',local_hash_prefix(local_hash(fullfile(folder,'modeling_package.mat')))]);
end

function h=local_hash_prefix(h)
h=h(1:12);
end

function options=local_thermal_options(folder,request)
assert(nargin==2 && isstruct(request) && isscalar(request), ...
    'sht:modeling:thermalRequest','请给出先验热包、边界、参考点及新输出目录。');
required={'inheritedThermalRuntimeDirectory','boundary','referencePoints','assetDirectory'};
allowed=[required,{'thermalProgramDirectory','execute','deadlineEpochSeconds'}];
assert(all(isfield(request,required)) && all(ismember(fieldnames(request),allowed)), ...
    'sht:modeling:thermalRequest','热准备请求缺字段或含未允许字段；不接受用户手填身份。');
folder=local_absolute(folder);p=local_read_package(folder);[options,~]=local_source_fields(folder,p);
% 旧热先验读者按其交付根定位相对资产。允许明确选择TC27模块，不猜根。
context=[];
if isfield(request,'thermalProgramDirectory'),context=local_code_context(request.thermalProgramDirectory);end %#ok<NASGU>
assert(~isempty(which('sht_tc27_runtime_package')),'sht:modeling:thermalModule','请安装或明确选择配套TC27公开模块。');
assert(~isempty(which('sht_default_config')) && ...
    strcmpi(local_hash(which('sht_default_config')),options.configurationSHA256), ...
    'sht:modeling:thermalModule','当前TC27模块配置源码与来源包不配套，请明确选择正确的thermalProgramDirectory。');
prior=sht_tc27_runtime_package(request.inheritedThermalRuntimeDirectory);
options.inheritedThermalPair=struct('sourceRuntimeDirectory',prior.directory, ...
    'kurzkeFile',prior.kurzkeFile,'visserFile',prior.thermalFile, ...
    'kurzkeSHA256',local_hash(prior.kurzkeFile),'visserSHA256',local_hash(prior.thermalFile));
for f={'boundary','referencePoints','assetDirectory','execute','deadlineEpochSeconds'}
    if isfield(request,f{1}),options.(f{1})=request.(f{1});end
end
end

function p=local_attach_thermal(folder,p,options)
if ~isfield(options,'thermalPreparationResultFile'),return;end
assert(p.modelMode==0 && p.thermalSourceReady,'sht:modeling:thermalSourceMissing','本热完成结果仅绑定三部件来源。');
view=Start_TC27_ThermalPreparationResultView_01(options.thermalPreparationResultFile);
assert(view.complete && view.environmentMetadataAvailable, ...
    'sht:modeling:thermalIncomplete','需完整热结果及实际生成环境，历史未知环境不能自动补齐。');
[~,lineage]=local_source_fields_without_package_file(folder,p);
g=view.generationConfiguration;
assert(strcmp(view.result.preparation.schemaVersion,'TC27_G11_INHERITED_THERMAL_READY_V1') && ...
    all(view.thermalAssets.kurzke.physicalValid) && all(view.thermalAssets.visser.physicalValid), ...
    'sht:modeling:thermalIncomplete','需要物理有效的新设计继承热完成结果。');
assert(isequaln(g.sourceDesignReference,lineage.DesignReference), ...
    'sht:modeling:thermalDesign','热结果原设计参考与本包不一致。');
assert(strcmpi(g.executionDesignReference.sourceModelSHA256,lineage.RuntimeModelSHA256), ...
    'sht:modeling:thermalDesign','热结果执行MDL不一致。');
assert(strcmpi(g.configurationIdentity.defaultConfigSHA256,lineage.configurationSHA256) && ...
    strcmpi(g.configurationIdentity.controllerGainSHA256,lineage.controllerGainSHA256), ...
    'sht:modeling:thermalConfiguration','热计算与新包的配置/增益身份不一致。');
local_compare_physical(folder,p,view.result.preparation.physicalIdentity.assets);
rel=fullfile('assets','thermal_preparation');target=fullfile(folder,rel);
assert(~isfolder(target),'sht:modeling:thermalExists','目标新包已有完成热结果，不静默替换。');
local_copy(view.resultFile,fullfile(target,'tc27_thermal_preparation_result.mat'),local_hash(view.resultFile));
for key={'kurzke','visser'}
    a=view.thermalAssets.(key{1});[~,n,e]=fileparts(a.file);
    local_copy(a.file,fullfile(target,[n,e]),a.sha256);
end
p.assets.thermalPreparationResultFile=fullfile(rel,'tc27_thermal_preparation_result.mat');
p.assets.thermalFile=fullfile(rel,'tc27_visser16_parameters.mat');
p.assets.kurzkeThermalFile=fullfile(rel,'tc27_kurzke15_parameters.mat');
p.generationConfiguration=g;p.thermalBinding='derived_runtime_eight_files';p.thermalReady=true;
end

function [base,lineage]=local_source_fields_without_package_file(folder,p)
base=local_child_file(folder,p.assets.thermalSourceDirectory);
lineage=local_read_json(fullfile(base,'lineage.json'));
end

function local_compare_physical(folder,p,items)
[base,~]=local_source_fields_without_package_file(folder,p);
t=readtable(fullfile(base,'runtime_eight_files.csv'),'Delimiter',',','Encoding','UTF-8', ...
    'Format','%q%q%q%q%q','TextType','string');
assert(numel(items)==8 && height(t)==8,'sht:modeling:thermalPhysical','热来源需恰好八文件。');
for k=1:8
    i=find(strcmp({items.name},char(t.Name(k))));f=fullfile(base,'runtime',char(t.Name(k)));
    assert(isscalar(i) && strcmpi(items(i).sha256,char(t.SHA256(k))) && ...
        strcmpi(local_hash(f),char(t.SHA256(k))), ...
        'sht:modeling:thermalPhysical','热结果与本包运行资产不一致：%s。',char(t.Name(k)));
end
end

function guard=local_code_context(root)
root=local_absolute(root);old=path;guard=onCleanup(@()path(old));
addpath(root,'-begin');
if isfolder(fullfile(root,'design_point_modeling')),addpath(fullfile(root,'design_point_modeling'),'-begin');end
end

function x=local_read_json(file)
fid=fopen(file,'rb');assert(fid>=0,'sht:modeling:json','不能读JSON。');
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
x=jsondecode(native2unicode(fread(fid,Inf,'*uint8').','UTF-8'));
end

function local_write_json(file,x)
fid=fopen(file,'w','n','UTF-8');assert(fid>=0,'sht:modeling:json','不能写JSON。');
c=onCleanup(@()fclose(fid));fprintf(fid,'%s',jsonencode(x)); %#ok<NASGU>
end

function e=local_portable_engine(e)
for field={'paths','aboveIdle'}
    if isfield(e,field{1}),e=rmfield(e,field{1});end
end
if isfield(e,'aboveIdleOverrides') && isfield(e.aboveIdleOverrides,'engine')
    e.aboveIdleOverrides.engine=rmfield(e.aboveIdleOverrides.engine,'runtimeDirectory');
end
if isfield(e,'stage7'),e.stage7.assetFile='';end
end

function ok=local_thermal_check(file,cfg)
d=load(file,'parameterAsset');assert(isfield(d,'parameterAsset'),'sht:modeling:thermal','缺少parameterAsset。');
a=d.parameterAsset;
assert(a.interface.interfaceVersion==2502+cfg.modelMode && a.interface.thermalModelMode==3, ...
    'sht:modeling:thermal','热参数接口与所选拓扑不相容。');
assert(numel(a.nominal.initialTemperatureState)==cfg.topology.temperatureCount, ...
    'sht:modeling:thermal','热状态维数错误。');
assert(isfield(a,'modelIdentity') && strcmpi(a.modelIdentity.modelSHA256,local_hash(cfg.paths.splitModel)), ...
    'sht:modeling:thermal','热参数源MDL身份与任务MDL不一致。');
ok=true;
end

function out=local_fullmode(folder,options)
if nargin<2,options=struct();end
folder=local_absolute(folder);
p=local_read_package(folder);
assert(p.runtimeReady,'sht:modeling:missingSeed','尚缺同一候选图的有效矩阵种子；不能进入全模式。');
assert(~isfield(options,'paths') && ~isfield(options,'modelMode') && ~isfield(options,'maps'), ...
    'sht:modeling:consumerOverride','消费者不能用覆盖配置更换包内模型、图或DLL。');
assert(all(ismember(fieldnames(options),{'fullmode'})), ...
    'sht:modeling:consumerOverride','候选消费只允许fullmode操纵配置。');
cfg=p.engineConfiguration;cfg.modelMode=p.modelMode;
root=fullfile(folder,'program');
cfg.paths=struct('matlabRoot',root,'branchRoot',folder,'cRoot',fullfile(folder,'C'), ...
    'splitModel',fullfile(root,cfg.topology.modelFile),'dll',fullfile(root,'GTESS.dll'), ...
    'matlabHeader',fullfile(root,'GTESS.h'),'outputRoot',fullfile(folder,'report_outputs'));
cfg.fullmode=struct('assetDirectory',fullfile(folder,p.assets.mapDirectory), ...
    'seedPoolFile',fullfile(folder,p.assets.seedPoolFile),'thermalEnabled',false);
% 热模型不静默打开或关闭：调用者必须明确指定；缺资产时不能请求热运行。
assert(isfield(options,'fullmode') && isfield(options.fullmode,'thermalEnabled'), ...
    'sht:modeling:thermalChoice','请显式选择fullmode.thermalEnabled。');
assert(~isfield(options.fullmode,'assetDirectory') && ~isfield(options.fullmode,'seedPoolFile'), ...
    'sht:modeling:consumerOverride','不能混用其他候选的图或种子。');
if options.fullmode.thermalEnabled
    assert(p.thermalReady,'sht:modeling:thermalMissing','候选包没有相容热配置，不能启用热运行。');
    cfg.stage7.assetFile=fullfile(folder,p.assets.thermalFile);
end
thermal=[];
if isfield(p.assets,'thermalPreparationResultFile')
    context=local_code_context(root); %#ok<NASGU>
    thermal=Start_TC27_ThermalPreparationResultView_01(local_child_file(folder,p.assets.thermalPreparationResultFile));
    assert(thermal.complete && thermal.environmentMetadataAvailable && ...
        isequaln(thermal.generationConfiguration,p.generationConfiguration), ...
        'sht:modeling:thermalGeneration','保存包与热结果生成配置不一致。');
    local_compare_physical(folder,p,thermal.result.preparation.physicalIdentity.assets);
    % 派生MDL已经引用包内低速图；后续运行目录仅复制相同物理字节。
    candidate=local_child_file(folder,p.assets.candidateModelFile);
    [base,lineage]=local_source_fields_without_package_file(folder,p);
    maps=local_derived_model(fullfile(root,cfg.topology.modelFile),candidate);
    assert(strcmpi(local_hash(candidate),lineage.RuntimeModelSHA256), ...
        'sht:modeling:thermalRuntime','候选运行MDL与热计算绑定不一致。');
    for k=1:3
        assert(strcmpi(local_hash(fullfile(cfg.fullmode.assetDirectory,maps{k})), ...
            local_hash(fullfile(base,'runtime',maps{k}))), ...
            'sht:modeling:thermalRuntime','全模式实际地图与热来源不同。');
    end
    if options.fullmode.thermalEnabled
        cfg.paths.splitModel=candidate;
    end
end
cfg.fullmode=local_merge(cfg.fullmode,options.fullmode);
out=struct('configuration',cfg,'programDirectory',root, ...
    'sourcePackage',folder,'startsNewSession',true,'doesNotRestoreOldSnapshot',true, ...
    'thermalPreparation',thermal);
end

function view=local_view(location)
if isfile(fullfile(location,'modeling_package.mat'))
    [p,~,missingRuntime]=local_read_package(location,true);
    view=struct('taskId',p.taskId,'modelMode',p.modelMode,'status',p.status, ...
        'stages',local_stage_table(p.stages),'results',p.results,'configuration',p.configuration, ...
        'runtimeReady',p.runtimeReady,'thermalReady',p.thermalReady,'figures',{{}},'directory',location);
    view.thermalPreparation=[];
    view.missingRuntimeFiles=missingRuntime;
    view.executionFilesComplete=isempty(missingRuntime);
    if isfield(p.assets,'thermalPreparationResultFile')
        context=local_code_context(fullfile(location,'program')); %#ok<NASGU>
        view.thermalPreparation=Start_TC27_ThermalPreparationResultView_01( ...
            local_child_file(location,p.assets.thermalPreparationResultFile));
    end
    if isfield(p,'sourcePackageIdentity'),view.sourcePackageIdentity=p.sourcePackageIdentity;end
    if isfield(p,'executionIdentity'),view.executionIdentity=p.executionIdentity;end
else
    d=load(fullfile(location,'MiddleData','task_state','task.mat'),'task');t=d.task;
    view=struct('taskId',t.taskId,'modelMode',t.config.modelMode,'status',t.status, ...
        'stages',local_stage_table(t.stages),'results',struct(),'configuration',t.config, ...
        'runtimeReady',false,'thermalReady',false,'figures',{{}},'directory',location);
    names=fieldnames(t.stages);
    for k=1:numel(names)
        s=t.stages.(names{k});
        if ~isempty(s.resultFile) && isfile(fullfile(location,s.resultFile))
            d=load(fullfile(location,s.resultFile),'result');view.results.(names{k})=d.result;
        end
    end
end
files=dir(fullfile(location,'**','*.png'));
view.figures=fullfile({files.folder},{files.name});
end

function local_write_excel(p,file)
summary=table({p.taskId},{p.status},p.modelMode,p.runtimeReady,p.thermalReady, ...
    'VariableNames',{'TaskId','ComputationStatus','ModelMode','RuntimeReady','ThermalReady'});
writetable(summary,file,'Sheet','Task');
writetable(local_stage_table(p.stages),file,'Sheet','Stages');
rows=local_parameter_rows(p.engineConfiguration,'',{});
if ~isempty(rows)
    t=cell2table(rows,'VariableNames',{'Parameter','Value','Unit','Source'});writetable(t,file,'Sheet','Parameters');
end
limits=table(p.limitations(:),'VariableNames',{'Limitation'});writetable(limits,file,'Sheet','Limits');
names=fieldnames(p.assets);values=cellfun(@(n)p.assets.(n),names,'UniformOutput',false);
writetable(table(names,values,'VariableNames',{'Role','RelativePath'}),file,'Sheet','Assets');
end

function rows=local_parameter_rows(x,prefix,rows)
if isstruct(x) && isscalar(x)
    names=fieldnames(x);
    for k=1:numel(names)
        n=names{k};if isempty(prefix),key=n;else,key=[prefix,'.',n];end
        rows=local_parameter_rows(x.(n),key,rows);
    end
elseif isnumeric(x) || islogical(x) || ischar(x) || iscellstr(x)
    if ischar(x),value=x;elseif iscellstr(x),value=strjoin(x,',');else,value=mat2str(x,14);end
    unit='dimensionless_or_see_parameter_definition';
    if endsWith(prefix,'Rpm'),unit='rpm';elseif endsWith(prefix,'KgPerS'),unit='kg/s';
    elseif endsWith(prefix,'Nm'),unit='N*m';elseif endsWith(prefix,'KgM2'),unit='kg*m^2';
    elseif endsWith(prefix,'M2'),unit='m^2';elseif endsWith(prefix,'W'),unit='W';
    elseif endsWith(prefix,'K'),unit='K';elseif endsWith(prefix,'S'),unit='s';
    elseif endsWith(prefix,'Deg'),unit='deg';end
    rows(end+1,:)={prefix,value,unit,'Selected source defaults plus explicit task overrides'};
end
end

function t=local_stage_table(stages)
names=fieldnames(stages);rows=cell(numel(names),8);
for k=1:numel(names)
    s=stages.(names{k});rows(k,:)={names{k},s.status,s.selectedPassed,s.fullAcceptancePassed, ...
        s.elapsedSeconds,s.resultFile,s.errorIdentifier,s.errorMessage};
end
t=cell2table(rows,'VariableNames',{'Stage','Status','SelectedPassed','FullAcceptancePassed', ...
    'ElapsedSeconds','ResultFile','ErrorIdentifier','ErrorMessage'});
end

function yes=local_selected_pass(r)
if isfield(r,'matrix'),r=r.matrix;end
yes=isfield(r,'accepted') && r.accepted;
end

function local_check_evidence(task,s)
for k=1:numel(s.evidence)
    r=s.evidence(k);p=fullfile(task.taskDirectory,s.attemptDirectory,r.relative);
    assert(isfile(p) && strcmp(local_hash(p),r.sha256), ...
        'sht:modeling:evidenceChanged','已完成阶段证据变化：%s。',p);
end
end

function f=local_files(folder)
d=dir(fullfile(folder,'**','*'));d=d(~[d.isdir]);
f=repmat(struct('relative','','bytes',0,'sha256',''),numel(d),1);
for k=1:numel(d)
    p=fullfile(d(k).folder,d(k).name);
    f(k)=struct('relative',p(numel(folder)+2:end),'bytes',d(k).bytes,'sha256',local_hash(p));
end
if ~isempty(f),[~,i]=sort({f.relative});f=f(i);end
end

function local_copy(source,target,hash)
local_mkdir(fileparts(target));
assert(~isfile(target),'sht:modeling:copyExists','目标文件已存在：%s。',target);
[ok,msg]=copyfile(source,target);assert(ok,'sht:modeling:copy','复制失败：%s。',msg);
% 只读源属性可能随copyfile带入；执行副本的MDL/MAP需允许原算法生成运行副本。
fileattrib(target,'+w');
assert(strcmpi(local_hash(target),hash),'sht:modeling:copyHash','复制后身份不一致：%s。',target);
end

function local_mkdir(p)
if ~isfolder(p),[ok,msg]=mkdir(p);assert(ok,'sht:modeling:mkdir','创建目录失败：%s。',msg);end
end

function p=local_absolute(p)
p=char(java.io.File(char(p)).getCanonicalPath());
end

function yes=local_under(p,root)
p=local_absolute(p);root=local_absolute(root);
yes=strcmpi(p,root) || startsWith(lower(p),lower([root,filesep]));
end

function value=local_hash(p)
fid=fopen(p,'rb');assert(fid>=0,'sht:modeling:missingFile','不能读取文件：%s。',p);
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
md=java.security.MessageDigest.getInstance('SHA-256');
while ~feof(fid),b=fread(fid,1048576,'*uint8');if ~isempty(b),md.update(typecast(b(:),'int8'));end,end
value=upper(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end

function value=local_digest(x)
if isstruct(x),x=local_order(x);end
b=unicode2native(jsonencode(x),'UTF-8');md=java.security.MessageDigest.getInstance('SHA-256');
md.update(typecast(uint8(b(:)),'int8'));value=upper(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end

function x=local_order(x)
x=orderfields(x);
for i=1:numel(x)
    names=fieldnames(x);
    for k=1:numel(names)
        n=names{k};if isstruct(x(i).(n)),x(i).(n)=local_order(x(i).(n));end
    end
end
end

function a=local_merge(a,b)
names=fieldnames(b);
for k=1:numel(names)
    n=names{k};if isfield(a,n) && isstruct(a.(n)) && isstruct(b.(n))
        a.(n)=local_merge(a.(n),b.(n));else,a.(n)=b.(n);end
end
end
