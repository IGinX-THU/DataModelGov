function out = sht_startstop_modeling_task(action,varargin)
%SHT_STARTSTOP_MODELING_TASK 界面和离线共用的起停建模任务核心。
% prepare只做文件检查/私有物化；runStage一次运行一个明确阶段。
% 不保存DLL指针。暂停只发生在完整阶段结束，连续积分内部不假装可恢复。
switch lower(action)
    case 'prepare'
        cfg=sht_startstop_modeling_config(varargin{1});
        p=sht_startstop_modeling_package('inventory',cfg);
        task=struct('schema',26101301,'taskId',cfg.taskId,'taskDirectory',cfg.taskDirectory, ...
            'config',cfg,'status','blocked','preflight',p,'bundle',struct(), ...
            'stages',struct(),'createdAt',datestr(now,31),'activeStage','', ...
            'saveStatus','not_requested','lastSave',struct(),'lastError',struct());
        for n=cfg.availableStageNames,task.stages.(n{1})=local_stage();end
        if isempty(task.taskId),task.taskId=['SS_',datestr(now,'yyyymmdd_HHMMSSFFF')];end
        if ~p.ready,out=task;return;end
        task.bundle=sht_startstop_modeling_package('materialize',cfg,p);
        task.taskDirectory=task.bundle.root;task.config.taskDirectory=task.bundle.root;
        task.status='ready';local_save(task);out=task;
    case 'status'
        out=local_load(varargin{1});
        out.pauseRequested=isfile(local_pause_file(out.taskDirectory));
    case 'requestpause'
        task=local_load(varargin{1});
        f=local_pause_file(task.taskDirectory);fid=fopen(f,'w');
        assert(fid>=0,'sht:modeling:pauseWrite','无法记录暂停请求。');
        fprintf(fid,'%s\n',datestr(now,31));fclose(fid);
        out=task;out.pauseRequested=true;
        if ~strcmp(task.status,'running')
            task.status='paused';local_save(task);out=task;out.pauseRequested=true;
        end
    case 'resume'
        task=local_load(varargin{1});local_not_running(task);
        sht_startstop_modeling_package('verify',task.bundle);
        f=local_pause_file(task.taskDirectory);if isfile(f),delete(f);end
        task.status='ready';local_save(task);out=task;
    case 'configure'
        task=local_load(varargin{1});local_not_running(task);
        changes=varargin{2};
        assert(all(ismember(fieldnames(changes),{'engineOverrides','display','requestedStages'})), ...
            'sht:modeling:reconfigure','更换源模型/代码/拓扑需要新任务。');
        old=task.config;task.config=sht_startstop_modeling_config(local_merge(old,changes));
        names=fieldnames(task.stages);
        for k=1:numel(names)
            n=names{k};s=task.stages.(n);
            if ~isempty(s.signature) && ~strcmp(s.signature,local_signature(task,n))
                task.stages.(n).status='stale';
            end
        end
        task.status='ready';local_save(task);out=task;
    case 'runstage'
        task=local_load(varargin{1});stage=lower(char(varargin{2}));
        assert(isfield(task.stages,stage),'sht:modeling:stage','未知阶段：%s。',stage);
        local_not_running(task);
        sht_startstop_modeling_package('verify',task.bundle);
        if isfile(local_pause_file(task.taskDirectory)) || strcmp(task.status,'paused')
            task.status='paused';local_save(task);out=task;return;
        end
        % 独立进程也只能持有同一任务的一把锁；旧锁不自动删除或冒充接续。
        lock=fullfile(task.taskDirectory,'MiddleData','task_state','running.lock');
        assert(java.io.File(lock).mkdir(),'sht:modeling:locked', ...
            '任务已被占用或存在异常退出锁：%s。先核查所属进程，不自动删除。',lock);
        lockCleanup=onCleanup(@()local_unlock(lock)); %#ok<NASGU>
        signature=local_signature(task,stage);
        previous=task.stages.(stage);
        if strcmp(previous.status,'completed') && strcmp(previous.signature,signature)
            local_verify_stage(task,stage);
            fprintf('%s已完成且身份一致，复用结果，不重新计算。\n',stage);
            task.status='ready';local_save(task);out=task;return;
        end
        try
            local_require_parents(task,stage);
        catch ex
            task.status='blocked';task.lastError=local_error(ex);local_save(task);out=task;return;
        end
        rel=fullfile('report_outputs',[stage,'_',datestr(now,'yyyymmdd_HHMMSSFFF')]);
        attempt=fullfile(task.taskDirectory,rel);mkdir(attempt);
        task.stages.(stage)=local_stage();
        task.stages.(stage).signature=signature;
        task.stages.(stage).attemptDirectory=rel;
        task.stages.(stage).status='running';task.activeStage=stage;task.status='running';
        local_save(task);timer=tic;
        fprintf('\n任务%s，执行%s，输出%s\n',task.taskId,stage,attempt);
        try
            context=sht_startstop_modeling_package('context',task.bundle);
            engine=local_engine_config(task);engine.paths.outputRoot=attempt;
            result=local_execute(stage,task,engine);
            [passed,fullPassed]=local_acceptance(stage,result);
            save(fullfile(attempt,'adapter_result.mat'),'result','-v7.3');
            task.stages.(stage).resultFile=fullfile(rel,'adapter_result.mat');
            task.stages.(stage).selectedPassed=passed;
            task.stages.(stage).fullAcceptancePassed=fullPassed;
            task.stages.(stage).status='completed';
            if ~passed,task.stages.(stage).status='completed_with_findings';end
            task.status='ready';
        catch ex
            task.stages.(stage).status='failed';task.status='failed';
            task.stages.(stage).errorIdentifier=ex.identifier;
            task.stages.(stage).errorMessage=ex.message;
            task.lastError=local_error(ex);
            failure=task.lastError; %#ok<NASGU>
            save(fullfile(attempt,'adapter_failure.mat'),'failure','-v7');
            % 三部件原入口在保存失败矩阵后抛错，仍保留逐点失败结果供查看。
            saved=dir(fullfile(attempt,'**','result.mat'));
            if numel(saved)==1
                d=load(fullfile(saved(1).folder,saved(1).name),'result');
                if isfield(d,'result')
                    result=d.result;save(fullfile(attempt,'adapter_result.mat'),'result','-v7.3');
                    task.stages.(stage).resultFile=fullfile(rel,'adapter_result.mat');
                end
            end
            fprintf(2,'阶段%s失败：%s [%s]\n',stage,ex.message,ex.identifier);
        end
        clear context;
        task.stages.(stage).elapsedSeconds=toc(timer);
        task.stages.(stage).completedAt=datestr(now,31);
        task.stages.(stage).evidence=sht_startstop_modeling_package('files',attempt);
        names=fieldnames(task.stages);
        for k=1:numel(names)
            n=names{k};s=task.stages.(n);
            if ~strcmp(n,stage) && ~isempty(s.signature) && ...
                    ~strcmp(s.signature,local_signature(task,n))
                task.stages.(n).status='stale';
            end
        end
        task.activeStage='';
        if isfile(local_pause_file(task.taskDirectory)) && ~strcmp(task.status,'failed'),task.status='paused';end
        local_save(task);out=task;
    case 'engineconfig'
        if isstruct(varargin{1}),task=varargin{1};else,task=local_load(varargin{1});end
        context=sht_startstop_modeling_package('context',task.bundle); %#ok<NASGU>
        out=local_engine_config(task);
    case 'savepackage'
        % 已保存包是只读输入，不恢复旧任务、不改签旧adapter或阶段记录。
        if ischar(varargin{1}) || (isstring(varargin{1}) && isscalar(varargin{1}))
            if isfile(fullfile(char(varargin{1}),'modeling_package.mat'))
                out=sht_startstop_modeling_package('export',varargin{:});return;
            end
        end
        task=local_load(varargin{1});local_not_running(task);
        task.saveStatus='saving';local_save(task);
        try
            args=varargin;args{1}=task;
            out=sht_startstop_modeling_package('export',args{:});
            task.saveStatus='saved';task.lastSave=out;local_save(task);
        catch ex
            task.saveStatus='failed';task.lastError=local_error(ex);local_save(task);rethrow(ex);
        end
    case 'loadresult',out=sht_startstop_modeling_package('view',varargin{1});
    case 'thermalsource',out=sht_startstop_modeling_package('thermalSource',varargin{:});
    case 'fullmodeconfig',out=sht_startstop_modeling_package('fullmodeConfig',varargin{:});
    otherwise,error('sht:modeling:action','未知建模操作：%s。',action);
end
end

function result=local_execute(stage,task,cfg)
switch stage
    case 'maps'
        if cfg.modelMode==0
            result=Start_StartStopModel_ThreeComponent('maps',cfg);
        else
            % 相同原扩图和资产核心，不另外实现图拟合。
            mapResult=sht_startstop_run_map_stages(cfg,cfg.paths.outputRoot);
            result=struct('mapResult',mapResult,'accepted',mapResult.stage1Accepted && mapResult.stage2Accepted);
            if result.accepted,sht_startstop_stage_asset('publish','stage12',cfg,result);end
        end
    case 'design'
        assert(cfg.modelMode==1 || ~isempty(cfg.designReference),'sht:modeling:integratedDesign', ...
            '三部件设计核查已在matrix入口内部执行，不调用六部件V2。');
        assert(task.preflight.designAvailable,'sht:modeling:designMissing', ...
            '六部件设计复现需要显式source.designStateFile；不自动生成或修改MDL。');
        result=local_run_design(cfg);
        if result.accepted,sht_startstop_stage_asset('publish','design',cfg,result);end
    case 'matrix'
        if cfg.modelMode==0
            result=Start_StartStopModel_ThreeComponent('matrix',cfg);
        else
            result=Start_StartStopModel_03_LowSpeedMatrixAndConstrainedCalibration(cfg);
        end
    case 'physics'
        % 独立物理核只使用当前任务DLL，不强加历史main_sync证据。
        alias='GTESS_MODELING_PHYSICS';
        assert(~libisloaded(alias),'sht:modeling:libraryBusy','物理检查库别名已被使用。');
        sht_load_engine_library(cfg.paths.dll,cfg.paths.matlabHeader,'alias',alias);
        cleanup=onCleanup(@()local_free_physics(alias)); %#ok<NASGU>
        sht_startstop_configure_dll(alias,cfg);
        result=sht_startstop_verify_physics_kernel(alias,cfg,fullfile(cfg.paths.outputRoot,'physics'));
    case {'continuous','thermal'}
        if cfg.modelMode==0
            mode='run';if strcmp(stage,'thermal'),mode='thermal';end
            result=Start_StartStopModel_ThreeComponent(mode,cfg);
        elseif strcmp(stage,'continuous')
            result=Start_StartStopModel_04_ContinuousStartStopAndRobustness(cfg);
        else
            result=Start_StartStopModel_05_VisserThermalCouplingAndFreeze(cfg);
        end
end
end

function result=local_run_design(cfg)
% V2固定使用GTESS。只取得本次独占的库，不能卸载其他会话的库。
alias='GTESS';before=libisloaded(alias);
assert(~before,'sht:modeling:designLibraryBusy', ...
    'GTESS已被其他调用加载，不能执行设计阶段；现有库及其状态保持不变。');
try
    if isempty(cfg.designReference)
        result=RunModelSHT_V2_2DP();
    else
        result=local_replay_explicit_design(alias,cfg);
    end
catch original
    % 此处V2调用栈及其局部libstruct/libpointer已经退出。原异常仍为主错误。
    try
        local_release_design(alias);
    catch cleanupError
        original=addCause(original,cleanupError);
    end
    rethrow(original);
end
returned=libisloaded(alias);
% 不依赖V2内部onCleanup与代理对象的析构先后，释放失败不能发布完成状态。
released=local_release_design(alias);
result.libraryLifecycle=struct('alias',alias,'beforeLoaded',before, ...
    'afterDesignReturnedLoaded',returned,'freeCalled',released.freeCalled, ...
    'freeStatus',released.freeStatus,'afterCleanupLoaded',libisloaded(alias));
fprintf('设计库生命周期：调用前=%d，设计回放返回=%d，外层释放后=%d。\n', ...
    before,returned,result.libraryLifecycle.afterCleanupLoaded);
end

function result=local_replay_explicit_design(alias,cfg)
% 新设计只做模式2直接复现，不调用含固定旧目标的V2配置构造器。
% 物理求值仍全部由原DLL执行；三/六分别传入6/9个共同工作变量。
r=cfg.designReference;
assert(strcmpi(sht_startstop_modeling_package('hash',cfg.paths.splitModel),r.sourceModelSHA256), ...
    'sht:modeling:designPair','设计MDL身份变化。');
sht_load_engine_library(cfg.paths.dll,cfg.paths.matlabHeader,'alias',alias, ...
    'includepath',cfg.paths.matlabRoot);
assert(calllib(alias,'DLL_SHT_InitialMode',cfg.modelMode)==0, ...
    'sht:modeling:designInitial','设计回放初始化失败。');
p.eng=libstruct('EngineTurboshaft');holder=libstruct('EngineSHTPointer',p);
stepIn=libpointer('doublePtr',zeros(512,1));stepOut=libpointer('doublePtr',zeros(128,1));
assert(calllib(alias,'DLL_SHT_ConditionsInit',stepIn,stepOut,holder)==0, ...
    'sht:modeling:designConditions','设计回放环境初始化失败。');
in=zeros(512,1);
in(1:10)=[r.NpRpm;r.NgRpm;r.fuelFlowKgPerS;r.nozzleAreaM2;0; ...
    r.loadPowerW;r.accessoryPowerW;0;0;0];
in(21:20+numel(r.commonVariables))=r.commonVariables;
stepIn.Value=in;
[status,~,out,engine]=calllib(alias,'DLL_SHT_RunSteadyComponents',stepIn,stepOut,holder);
assert(status==0,'sht:modeling:designReplay','直接设计回放失败，状态%d。',status);
e=engine.eng;
if cfg.modelMode==0,c=e.HPC;g=e.HPT;p=e.LPT;else,c=e.HPC2;g=e.HPT2;p=e.LPT2;end
observed=[c.y(1),c.y(3),c.y(4),g.y(3),g.y(4),p.y(3),p.y(4), ...
    e.LPS_Nmech,e.HPS_Nmech,e.LPS_Trq];
residual=out(1:6+3*cfg.modelMode);
relative=abs(observed-r.expectedOutput)./max(abs(r.expectedOutput),1);
temperatureRelative=abs(e.Burner.y(3)-r.targetTt4K)/r.targetTt4K;
result=struct('modelMode',cfg.modelMode,'workflow','explicit_design_replay', ...
    'offDesignMode',2,'designReference',r,'actualStepIn',in, ...
    'residual',residual,'output',observed,'designReplayRelative',relative, ...
    'temperatureRelative',temperatureRelative,'accepted', ...
    all(isfinite(residual)) && max(abs(residual))<=1e-7 && ...
    all(isfinite(relative)) && max(relative)<=1e-7 && temperatureRelative<=1e-7);
% 保留原六部件低速矩阵入口读取的设计资产合同，不重算或覆盖设计状态。
statePath=fullfile(cfg.paths.matlabRoot,'MiddleData', ...
    sprintf('RunModelSHT_V%d_design_state.mat',cfg.modelMode+1));
assert(strcmpi(sht_startstop_modeling_package('hash',statePath),r.designStateSHA256), ...
    'sht:modeling:designPair','物化后的设计状态身份不一致。');
loaded=load(statePath,'designState');result.design=loaded.designState.design;
if isfield(loaded.designState,'designTargets')
    result.designTargets=loaded.designState.designTargets;
else
    result.designTargets=struct('NpRpm',r.NpRpm,'NgRpm',r.NgRpm, ...
        'loadPowerW',r.loadPowerW,'accessoryPowerW',r.accessoryPowerW, ...
        'nozzleAreaM2',r.nozzleAreaM2,'targetTt4K',r.targetTt4K);
end
end

function result=local_release_design(alias)
result=struct('freeCalled',false,'freeStatus',NaN);
if libisloaded(alias)
    status=calllib(alias,'DLL_SHT_Free');
    assert(status==0,'sht:modeling:designLibraryFree', ...
        '设计阶段自身库%s释放发动机数据失败，状态码%d。',alias,status);
    result.freeCalled=true;result.freeStatus=status;
    unloadlibrary(alias);
end
assert(~libisloaded(alias),'sht:modeling:designLibraryUnload', ...
    '设计阶段结束后自身库%s仍被加载，不能继续下一阶段。',alias);
end

function cfg=local_engine_config(task)
root=task.bundle.codeDirectory;source=task.bundle.sourceModelDirectory;
user=task.config.engineOverrides;user.modelMode=task.config.modelMode;
user.paths=struct('matlabRoot',root,'branchRoot',fileparts(root),'cRoot',source, ...
    'splitModel',fullfile(source,task.config.source.modelFile), ...
    'dll',fullfile(root,'GTESS.dll'),'matlabHeader',fullfile(root,'GTESS.h'), ...
    'outputRoot',fullfile(task.taskDirectory,'report_outputs'));
if isfield(task.preflight,'designReference')
    user.designReference=task.preflight.designReference;
end
cfg=sht_startstop_default_config(user);
names=cfg.topology.componentNames;
for k=1:numel(names),cfg.maps.(names{k}).sourceName=task.preflight.maps.(names{k});end
cfg.mapIO.generateFigures=task.config.display.generateMapFigures;
cfg.mapIO.showFigures=task.config.display.showFigures;
cfg.stage6.showFigures=task.config.display.showFigures;cfg.stage7.showFigures=task.config.display.showFigures;
if task.preflight.thermalAvailable
    cfg.stage7.assetFile=fullfile(task.taskDirectory,'TestData','upstream','thermal_parameters.mat');
else
    cfg.stage7.assetFile='';
end
cfg.aboveIdleOverrides.engine.runtimeDirectory=root;
cfg.aboveIdleOverrides.engine.modelMode=cfg.modelMode;
end

function local_require_parents(task,stage)
parents={};
switch stage
    case 'matrix'
        parents={'maps'};
        if task.config.modelMode==1 || task.preflight.designAvailable,parents{end+1}='design';end
    case {'continuous','thermal'},parents={'matrix'};
end
for k=1:numel(parents)
    name=parents{k};s=task.stages.(name);
    assert(strcmp(s.status,'completed') && s.selectedPassed && ...
        strcmp(s.signature,local_signature(task,name)), ...
        'sht:modeling:prerequisite','缺少当前身份下通过的%s阶段；请显式执行，不自动补算。',name);
    local_verify_stage(task,name);
end
if strcmp(stage,'thermal')
    assert(task.preflight.thermalAvailable,'sht:modeling:thermalMissing','热校核缺source.thermalFile。');
end
end

function signature=local_signature(task,stage)
cfg=task.config;
% 显示选项不影响数值复用；修改输出根或文件名不能使旧物理证据换身份。
over=cfg.engineOverrides;
for field={'mapIO','stage6','stage7'}
    f=field{1};
    if isfield(over,f)
        for n={'showFigures','generateFigures','maximumPlotPoints','imageResolutionDpi'}
            if isfield(over.(f),n{1}),over.(f)=rmfield(over.(f),n{1});end
        end
    end
end
switch stage
    case 'maps',fields={'mapIO','extension'};
    case 'design',fields={};
    case 'matrix',fields={'mapIO','extension','startStop','stage5','lowSpeedSolver'};
    case 'physics',fields={'startStop','lowSpeedSolver'};
    case 'continuous',fields={'mapIO','extension','startStop','stage5','lowSpeedSolver','stage6','aboveIdleOverrides'};
    case 'thermal',fields={'mapIO','extension','startStop','stage5','lowSpeedSolver','stage6','stage7','aboveIdleOverrides'};
end
selected=struct();
for k=1:numel(fields),if isfield(over,fields{k}),selected.(fields{k})=over.(fields{k});end,end
identity=struct('stage',stage,'source',task.bundle.identity,'mode',cfg.modelMode,'overrides',selected);
% 下游绑定上游的实际输出，不只绑定配置；重新生成不同图后不能复用旧校核。
parents={};
if strcmp(stage,'matrix')
    parents={'maps'};
    if cfg.modelMode==1 || task.preflight.designAvailable,parents{end+1}='design';end
elseif any(strcmp(stage,{'continuous','thermal'}))
    parents={'matrix'};
end
identity.parents=struct();
for k=1:numel(parents)
    s=task.stages.(parents{k});
    identity.parents.(parents{k})=struct('signature',s.signature,'evidence',s.evidence);
end
signature=sht_startstop_modeling_package('digest',identity);
end

function local_verify_stage(task,stage)
s=task.stages.(stage);
for k=1:numel(s.evidence)
    item=s.evidence(k);file=fullfile(task.taskDirectory,s.attemptDirectory,item.relative);
    assert(isfile(file) && strcmp(sht_startstop_modeling_package('hash',file),item.sha256), ...
        'sht:modeling:evidenceChanged','阶段%s已保存证据变化：%s。',stage,item.relative);
end
assert(~isempty(s.resultFile),'sht:modeling:resultMissing','阶段没有可复用结果。');
end

function [passed,full]=local_acceptance(stage,r)
if strcmp(stage,'maps') && isfield(r,'maps'),r=r.maps;end
if strcmp(stage,'matrix') && isfield(r,'matrix'),r=r.matrix;end
if strcmp(stage,'continuous') && isfield(r,'continuous'),r=r.continuous;end
if strcmp(stage,'thermal') && isfield(r,'thermal'),r=r.thermal;end
passed=isfield(r,'accepted') && logical(r.accepted);full=false;
if strcmp(stage,'continuous')
    passed=r.subsetAccepted;full=r.formalAccepted;
elseif strcmp(stage,'thermal')
    passed=r.acceptance.selectedCasesAccepted;full=r.acceptance.formalAccepted;
end
end

function s=local_stage()
s=struct('status','not_run','signature','','selectedPassed',false,'fullAcceptancePassed',false, ...
    'elapsedSeconds',0,'completedAt','','attemptDirectory','','resultFile','', ...
    'errorIdentifier','','errorMessage','','evidence',struct('relative',{},'bytes',{},'sha256',{}));
end

function task=local_load(root)
p=fullfile(root,'MiddleData','task_state','task.mat');
assert(isfile(p),'sht:modeling:taskMissing','缺少任务状态：%s。',p);
d=load(p,'task');task=d.task;
assert(task.schema==26101301,'sht:modeling:schema','任务状态版本不支持。');
assert(strcmpi(char(java.io.File(root).getCanonicalPath()),task.taskDirectory), ...
    'sht:modeling:taskMoved','任务运行检查点不能换根冒充继续；搬迁使用导出的模型包。');
end

function local_save(task)
root=fullfile(task.taskDirectory,'MiddleData','task_state');
file=fullfile(root,'task.mat');tmp=[tempname(root),'.mat'];
save(tmp,'task','-v7.3');[ok,msg]=movefile(tmp,file,'f');
assert(ok,'sht:modeling:stateSave','任务状态保存失败：%s。',msg);
end

function local_not_running(task)
assert(~strcmp(task.status,'running'),'sht:modeling:running','任务仍在运行，不能并发修改配置或重启。');
end

function path=local_pause_file(root)
path=fullfile(root,'MiddleData','task_state','pause_requested.txt');
end

function local_unlock(lock)
if isfolder(lock),rmdir(lock);end
end

function e=local_error(ex)
e=struct('identifier',ex.identifier,'message',ex.message,'stack',ex.stack,'time',datestr(now,31));
% 原异常和清理异常分别保存，不用后者覆盖真正失败原因。
e.causes=cell(size(ex.cause));
for k=1:numel(ex.cause),e.causes{k}=local_error(ex.cause{k});end
end

function local_free_physics(alias)
if libisloaded(alias),calllib(alias,'DLL_SHT_Free');unloadlibrary(alias);end
end

function a=local_merge(a,b)
names=fieldnames(b);
for k=1:numel(names)
    n=names{k};if isfield(a,n) && isstruct(a.(n)) && isstruct(b.(n))
        a.(n)=local_merge(a.(n),b.(n));else,a.(n)=b.(n);end
end
end
