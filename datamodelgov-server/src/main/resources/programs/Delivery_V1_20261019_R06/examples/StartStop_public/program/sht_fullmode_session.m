function out=sht_fullmode_session(action,varargin)
%SHT_FULLMODE_SESSION 界面与离线共用的人工试车台会话核心。
% 一进程一会话。prepare仅准备，begin才运行；select_throttle(idle)不是起动。
% submit接受有requestId的明确命令，advance每次只提交完整的0.025秒积分步。
% 保存的纯数值状态与DLL/源/物理资产身份配对；查看历史不加载DLL。
persistent S C
if nargin<1,action='status';end
switch lower(action)
    case 'prepare'
        assert(isempty(S),'已有会话，请先close，不允许静默重置。');
        user=struct();if ~isempty(varargin),user=varargin{1};end
        cfg=sht_fullmode_default_config(user);
        % 同源控制器只读取当前包的普通MDL/DLL，不误用正式共享或另一分支。
        cfg.aboveIdleOverrides.engine.runtimeDirectory=cfg.paths.matlabRoot;
        cfg=sht_startstop_prepare_control(cfg);
        [cfg,asset,points,runtime,identity]=local_prepare_assets(cfg);
        C=local_open(cfg,asset,runtime);
        armed=java.util.concurrent.atomic.AtomicBoolean(true);
        cleanup=onCleanup(@()local_close_on_error(armed));
        r=local_kernel(C,cfg,points,runtime,struct('fullmodeAction','prepare'));
        b=sht_fullmode_load_boundary(cfg,0,0);
        local_call(C,'DLL_SHT_FullModeSetLoad',26100701,7,libpointer('doublePtr',b.vector));
        local_call(C,'DLL_SHT_StartStopReset',0,0,0,1);
        local_call(C,'DLL_SHT_FullModeSetLoad',26100701,7,libpointer('doublePtr',b.vector));
        T=struct('schema',26100701,'cfg',cfg,'runtime',r,'points',points, ...
            'assets',identity,'assetConfig',asset,'runtimeFiles',runtime, ...
            'lifecycle','prepared','throttle','cut','cutLatched',false,'pending',[], ...
            'receipts',repmat(local_receipt(),0,1),'events',{{}}, ...
            'traceRows',zeros(0,numel(local_trace_names())),'thermalRows',zeros(0,1+cfg.topology.temperatureCount), ...
            'wallSeconds',0,'stopReason','','createdAt',datestr(now,31));
        if ~strcmp(cfg.fullmode.initialKind,'stopped'),T=local_nonzero_initial(T,C);end
        local_call(C,'DLL_SHT_FullModeExportState',26100701,64,C.statePointer);
        T.cState=C.statePointer.Value;
        S=local_record(T);out=local_status(S);armed.set(false);clear cleanup;
    case 'begin'
        local_require(S);assert(strcmp(S.lifecycle,'prepared'),'只有prepared会话可以begin。');
        S.lifecycle='running';out=local_status(S);
    case 'submit'
        local_require(S);[S,out]=local_submit(S,varargin{1});
    case 'advance'
        local_require(S);assert(strcmp(S.lifecycle,'running'),'advance需要running会话；暂停时不积分。');
        n=1;if ~isempty(varargin),n=varargin{1};end
        validateattributes(n,{'numeric'},{'scalar','integer','positive','finite'});
        timer=tic;
        for i=1:n
            if S.runtime.acceptedSteps>=S.cfg.fullmode.maximumAcceptedSteps
                S.lifecycle='terminated';S.stopReason='numerical_step_budget';break;
            end
            [candidate,indices]=local_apply_pending(S);
            cfg=candidate.cfg;
            try
                previous=candidate.runtime;
                r=local_kernel(C,cfg,candidate.points,candidate.runtimeFiles, ...
                    struct('fullmodeAction','step','runtime',previous));
                candidate.runtime=r;
                local_call(C,'DLL_SHT_FullModeExportState',26100701,64,C.statePointer);
                candidate.cState=C.statePointer.Value;
                for q=indices(:).'
                    candidate.receipts(q).state='applied';
                    candidate.receipts(q).appliedTimeS=r.timeS;
                end
                candidate.pending=[];
                if ~strcmp(previous.mode,r.mode)
                    candidate.events{end+1}=struct('timeS',r.timeS,'kind','mode_change', ...
                        'from',previous.mode,'to',r.mode);
                end
                if previous.output(12)~=r.output(12)
                    candidate.events{end+1}=struct('timeS',r.timeS,'kind','freewheel_change', ...
                        'engaged',logical(r.output(12)));
                end
                S=candidate;
                stride=round(S.cfg.fullmode.recordPeriodS/S.cfg.stage6.timeStepS);
                if mod(r.acceptedSteps,stride)==0,S=local_record(S);end
            catch ex
                % 内核已回滚C私有状态，保留最后接受点，数值终止不冒充物理停车。
                S.lifecycle='failed';S.stopReason=ex.identifier;
                S.runtime.failureReason=ex.message;
                S.events{end+1}=struct('timeS',S.runtime.timeS,'kind','numerical_failure', ...
                    'identifier',ex.identifier,'message',ex.message);break;
            end
        end
        S.wallSeconds=S.wallSeconds+toc(timer);out=local_status(S);
    case 'pause'
        local_require(S);assert(strcmp(S.lifecycle,'running'),'仅running可以暂停。');
        S.lifecycle='paused';out=local_status(S);
    case 'resume'
        local_require(S);assert(strcmp(S.lifecycle,'paused'),'仅paused可以恢复。');
        S.lifecycle='running';out=local_status(S);
    case 'terminate'
        % 数值终止不发断油命令、不改轴速；最后完整接受点仍可保存查看。
        local_require(S);
        if ~any(strcmp(S.lifecycle,{'terminated','failed'}))
            for q=S.pending(:).',S.receipts(q).state='cancelled_by_termination';end
            S.pending=[];S.lifecycle='terminated';S.stopReason='operator_numerical_stop';
            S.events{end+1}=struct('timeS',S.runtime.timeS,'kind','numerical_termination', ...
                'description','操作者结束数值推进；不等于物理停车');
        end
        out=local_status(S);
    case 'status'
        if isempty(S),out=struct('lifecycle','empty');else,out=local_status(S);end
    case 'result'
        local_require(S);out=local_result(S);
    case 'save'
        local_require(S);folder=varargin{1};assert(~isempty(folder),'保存目录不能为空。');
        if ~isfolder(folder),mkdir(folder);end
        local_call(C,'DLL_SHT_FullModeExportState',26100701,64,C.statePointer);
        S.cState=C.statePointer.Value;result=local_result(S);
        snapshot=S;snapshot.lifecycle='paused';
        file=fullfile(folder,'fullmode_snapshot.mat');
        assert(~isfile(file) && ~isfile(fullfile(folder,'fullmode_results.xlsx')), ...
            '该保存目录已有历史结果，请使用新的目录。');
        save(file,'snapshot','result','-v7.3');
        writetable(result.trace,fullfile(folder,'fullmode_results.xlsx'),'Sheet','Signals');
        if ~isempty(result.thermalTrace)
            writetable(result.thermalTrace,fullfile(folder,'fullmode_results.xlsx'),'Sheet','ThermalStates');
        end
        if ~isempty(S.receipts)
            % R2019b标量结构默认按字段长度展开；一条命令也必须是一行。
            writetable(struct2table(S.receipts,'AsArray',true),fullfile(folder,'fullmode_results.xlsx'),'Sheet','Commands');
        end
        meta=struct('schema',S.schema,'configuration',S.cfg,'identity',S.assets, ...
            'events',{S.events},'physicalStop',S.runtime.physicalStop, ...
            'stopReason',S.stopReason,'elapsedWallS',S.wallSeconds,'matlabVersion',version);
        local_write_utf8(fullfile(folder,'fullmode_manifest.json'),jsonencode(meta));
        out=struct('snapshot',file,'excel',fullfile(folder,'fullmode_results.xlsx'));
    case 'restore'
        assert(isempty(S),'恢复前先close，禁止覆盖活动会话。');
        d=load(varargin{1},'snapshot');T=d.snapshot;
        assert(T.schema==26100701,'快照版本不匹配。');
        root=fileparts(mfilename('fullpath'));
        % 恢复路径可搬迁：源和物理文件以叶名称在当前运行包重新准备，再核SHA。
        base=struct('modelMode',T.cfg.modelMode);
        if numel(varargin)>1
            % 先校验明确的位置覆盖，避免默认构造先搜索部署包之外的开发C工程。
            % 仅向默认构造传递本次显式paths，不沿用快照中可能已失效的旧路径。
            probe=T.cfg;probe.paths.matlabRoot=root;
            local_restore_locations(probe,varargin{2},root);
            if isfield(varargin{2},'paths'),base.paths=varargin{2}.paths;end
        end
        defaults=sht_fullmode_default_config(base);
        cfg=T.cfg;cfg.paths=defaults.paths;
        cfg.fullmode.assetDirectory=defaults.fullmode.assetDirectory;
        cfg.fullmode.seedPoolFile=defaults.fullmode.seedPoolFile;
        cfg.fullmode.outputDirectory=defaults.fullmode.outputDirectory;
        cfg.stage7.assetFile=defaults.stage7.assetFile;
        cfg.aboveIdleOverrides.engine.runtimeDirectory=root;
        if ~isempty(varargin(2:end)),cfg=local_restore_locations(cfg,varargin{2},root);end
        [cfg,asset,points,runtime,identity]=local_prepare_assets(cfg);
        local_verify_identity(T.assets,identity);
        C=local_open(cfg,asset,runtime);
        armed=java.util.concurrent.atomic.AtomicBoolean(true);
        cleanup=onCleanup(@()local_close_on_error(armed));
        T.cfg=cfg;T.assetConfig=asset;T.points=points;T.runtimeFiles=runtime;
        local_call(C,'DLL_SHT_FullModeImportState',26100701,64,libpointer('doublePtr',T.cState));
        % 在当前已保存状态重构代数气路，不推进热状态、控制器和随机数。
        if T.runtime.speed(2)>cfg.lowSpeedSolver.zeroHoldSpeedRpm
            a=local_kernel(C,cfg,points,runtime,struct('fullmodeAction','evaluate', ...
                'runtime',T.runtime,'command',local_c_command(T.runtime.mode)));
            assert(a.converged,'恢复时当前气路不能复现，不能继续。');
            gasIndices=[1:3,15:17];
            delta=max(abs(a.output(gasIndices)-T.runtime.output(gasIndices)));
            assert(delta<1e-7,'恢复代数气路与保存点不一致，最大差%g。',delta);
        end
        local_call(C,'DLL_SHT_FullModeImportState',26100701,64,libpointer('doublePtr',T.cState));
        T.lifecycle='paused';S=T;out=local_status(S);armed.set(false);clear cleanup;
    case 'close'
        if ~isempty(C)
            alias=C.alias;
            if libisloaded(alias),calllib(alias,'DLL_SHT_Free');end
            % 先释放全部MATLAB库代理对象，再卸载；不能让清理回调捕获C副本。
            C=[];
            local_unload(alias);
        end
        S=[];C=[];out=struct('lifecycle','empty');
    otherwise
        error('sht:fullmode:action','未知会话操作：%s。',action);
end
end

function [cfg,asset,points,runtime,identity]=local_prepare_assets(cfg)
assert(isfile(cfg.fullmode.seedPoolFile),'缺少明确配置的低速初值资料：%s。',cfg.fullmode.seedPoolFile);
d=load(cfg.fullmode.seedPoolFile,'result');points=d.result.finalMatrix.points;
asset=[];
if cfg.fullmode.thermalEnabled
    d=load(cfg.stage7.assetFile,'parameterAsset');asset=d.parameterAsset;
    if cfg.modelMode==0,asset=sht_startstop_three_thermal_adapter(asset,cfg);end
    [ref,cache]=sht_prepare_clearance_reference_lookup(asset.referenceTable);
    cfg.stage7.enabled=true;
    cfg.stage7.initialTemperatureState=repmat(asset.referenceTable.defaultInletTotalTemperature_K, ...
        cfg.topology.temperatureCount,1);
    if ~isempty(cfg.fullmode.initialThermalState)
        cfg.stage7.initialTemperatureState=cfg.fullmode.initialThermalState(:);
    end
    cfg.stage7.stateNames=asset.topology.stateNames(3:end);
    cfg.stage7.stepInTemplate=sht_build_transient_step_in_template(asset,'joint_full');
    cfg.stage7.referenceTable=ref;cfg.stage7.clearanceReferenceCacheInfo=cache;
    cfg.stage7.inletTotalTemperatureK=asset.referenceTable.defaultInletTotalTemperature_K;
    cfg.stage7.heatCapacityJPerK=[asset.nominal.visserMetalHeatCapacity(1:cfg.topology.metalCount); ...
        asset.nominal.visserDiskHeatCapacity(:);asset.nominal.visserMetalHeatCapacity(cfg.topology.metalCount+1:end)];
    cfg.stage7.diskRootMetalIndex=asset.topology.diskRootMetalIndex(:);
else
    cfg.stage7.enabled=false;
end
cfg.lowSpeedSolver.zeroHoldSpeedRpm=cfg.stage6.gasPathActivationNgRatio*cfg.startStop.designNgRpm;
cfg.lowSpeedSolver.accuracyRequired=cfg.stage6.solverAccuracyRequired;
names=cfg.topology.componentNames;items=repmat(struct('name','','outputPath',''),1,numel(names));
for k=1:numel(names)
    items(k)=struct('name',names{k},'outputPath',fullfile(cfg.fullmode.assetDirectory,cfg.maps.(names{k}).outputName));
    assert(isfile(items(k).outputPath),'缺少低速物理图：%s。',items(k).outputPath);
end
if isempty(cfg.fullmode.outputDirectory)
    cfg.fullmode.outputDirectory=fullfile(fileparts(cfg.paths.matlabRoot),'report_outputs', ...
        'fullmode',sprintf('R011_%s',datestr(now,'yyyymmdd_HHMMSS')));
end
runtime=sht_startstop_create_runtime(cfg,struct('items',items),cfg.fullmode.outputDirectory);
files={cfg.paths.dll,cfg.paths.matlabHeader,cfg.paths.splitModel,cfg.fullmode.seedPoolFile};
if cfg.fullmode.thermalEnabled,files{end+1}=cfg.stage7.assetFile;end
for k=1:numel(items),files{end+1}=items(k).outputPath;end
code=dir(fullfile(cfg.paths.matlabRoot,'*.m'));
for k=1:numel(code),files{end+1}=fullfile(code(k).folder,code(k).name);end
identity=repmat(struct('name','','sha256','','bytes',0),numel(files),1);
for k=1:numel(files)
    [~,n,e]=fileparts(files{k});identity(k).name=[n,e];
    identity(k).sha256=local_hash(files{k});v=dir(files{k});identity(k).bytes=v.bytes;
end
end

function C=local_open(cfg,asset,runtime)
old=pwd;guard=onCleanup(@()cd(old));cd(runtime.controlDir);
alias='SHT_FULLMODE_R011';
assert(~libisloaded(alias),'别名已经加载，拒绝共享另一会话的隐状态。');
sht_load_engine_library(runtime.dllPath,runtime.headerPath,'alias',alias);
C=struct('alias',alias,'engine',[],'statePointer',libpointer('doublePtr',zeros(64,1)));
try
    local_call(C,'DLL_SHT_InitialMode',cfg.modelMode);
    initialization=sht_startstop_configure_dll(alias,cfg);
    C.solverConfiguration=initialization.solverVector;
    if ~isempty(asset)
        interface=struct('libraryName',alias);
        sht_initialize_thermal_model_dll(interface,cfg.modelMode,sht_build_thermal_model_configuration(asset));
        sht_initialize_cooling_split_dll(interface,cfg.modelMode,asset.coolingSplitConfiguration);
    end
    init=struct('eng',libstruct('EngineTurboshaft'));C.engine=libstruct('EngineSHTPointer',init);clear init;
    local_call(C,'DLL_SHT_ConditionsInit',libpointer('doublePtr',zeros(512,1)), ...
        libpointer('doublePtr',zeros(128,1)),C.engine);
catch ex
    if libisloaded(alias),calllib(alias,'DLL_SHT_Free');end
    C=[];local_unload(alias);rethrow(ex);
end
end

function out=local_kernel(C,cfg,points,runtime,request)
old=pwd;guard=onCleanup(@()cd(old));cd(runtime.controlDir);
out=sht_startstop_run_continuous_mission(C.alias,C.engine,cfg,points,runtime.controlDir,request,'');
end

function S=local_nonzero_initial(S,C)
% 准备阶段可以配平；在线施加与恢复绝不配平。只求Ng和燃油，气路共同工作
% 由同一低速DLL内核内部求解。不依赖Optimization Toolbox。
cfg=S.cfg;r=S.runtime;
% 外层轴系配平要求0.1 rpm/s，内层气路残差必须足够小，否则数值噪声
% 会使Jacobian/下降判据失真。仅准备期间收紧，结束时恢复正式积分配置。
solverBefore=C.solverConfiguration;solverTight=solverBefore;
solverTight(3)=min(solverBefore(3),1e-8);alias=C.alias;
local_solver_configuration(alias,solverTight);
solverGuard=onCleanup(@()local_solver_configuration(alias,solverBefore));
ratio=cfg.fullmode.initialNpRatio;
if strcmp(cfg.fullmode.initialKind,'idle'),ratio=cfg.stage6.idleNpRatio;end
if strcmp(cfg.fullmode.initialKind,'maximum'),ratio=1;end
assert(ratio>0 && ratio<=1.05,'非零初态Np比例超出允许准备范围。');
r.speed=[ratio*cfg.startStop.designNpRpm;cfg.stage6.startupIdleNgRpm;ratio*cfg.startStop.designNpRpm];
% 测功器直接作用于PT轴，不连接独立旋翼；不能给未连接旋翼虚构初始动能。
if ~strcmp(cfg.fullmode.loadMode,'dual_collective'),r.speed(3)=0;end
r.mode='run';if strcmp(cfg.fullmode.initialKind,'idle'),r.mode='idle';end
r.warmupComplete=true;r.physicalStop=false;
% 矩阵扫描的idleFuel不是连续慢车燃油。这里只选择数值初猜，不改控制参数。
r.fuel=cfg.stage6.idleFuelFeedforwardKgPerS;
local_call(C,'DLL_SHT_FullModeExportState',26100701,64,C.statePointer);
v=C.statePointer.Value;v(9)=7;v(16)=1;v(18:20)=r.speed([2,1,3]);
local_call(C,'DLL_SHT_FullModeImportState',26100701,64,libpointer('doublePtr',v));
trimHistory=zeros(0,6);
for it=1:40
    [e,a]=local_trim_eval(S,C,r);
    r.seed=a.diagnostics(17+(1:cfg.topology.gasCount));
    trimHistory(end+1,:)=[it,r.speed(2),r.fuel,e(:).',a.diagnostics(14)]; %#ok<AGROW>
    if max(abs(e))<0.1,break;end
    J=zeros(2);x=[r.speed(2);r.fuel];step=[5;1e-5];
    for j=1:2
        rr=r;if j==1,rr.speed(2)=x(1)+step(1);else,rr.fuel=x(2)+step(2);end
        [ee,~]=local_trim_eval(S,C,rr);J(:,j)=(ee-e)/step(j);
    end
    assert(rcond(J)>1e-12,'初态配平Jacobian奇异，请更换相容负载。');
    change=-(J\e);accepted=false;
    for b=0:8
        next=x+2^-b*change;
        if next(1)<=0 || next(1)>1.05*cfg.startStop.designNgRpm || next(2)<=0 || next(2)>0.7,continue;end
        rr=r;rr.speed(2)=next(1);rr.fuel=next(2);
        try,[ee,aa]=local_trim_eval(S,C,rr);catch,continue;end
        if norm(ee)<norm(e)
            rr.seed=aa.diagnostics(17+(1:cfg.topology.gasCount));
            r=rr;a=aa;accepted=true;break;
        end
    end
    if ~accepted
        % 特性图插值折点附近差分Newton方向可能不再下降。仅对两个准备
        % 变量作无工具箱局部搜索，仍以同一DLL和原轴加速度误差验收。
        scale=[100;1e-3];options=optimset('Display','off','MaxIter',120, ...
            'MaxFunEvals',260,'TolX',1e-7,'TolFun',1e-8);
        z=fminsearch(@(z)local_trim_cost(S,C,r,x+scale.*(z(:)-1)),ones(2,1),options);
        next=x+scale.*(z(:)-1);rr=r;rr.speed(2)=next(1);rr.fuel=next(2);
        [ee,aa]=local_trim_eval(S,C,rr);
        if norm(ee)<norm(e)
            rr.seed=aa.diagnostics(17+(1:cfg.topology.gasCount));r=rr;a=aa;accepted=true;
        end
    end
    if ~accepted
        if ~isfolder(cfg.fullmode.outputDirectory),mkdir(cfg.fullmode.outputDirectory);end
        save(fullfile(cfg.fullmode.outputDirectory,'initial_trim_failure.mat'), ...
            'trimHistory','cfg','J','x','e','change');
        error('sht:fullmode:initialTrim','给定负载和非零初态不能配平：dNp=%g，dNg=%g。',e(1),e(2));
    end
end
[e,a]=local_trim_eval(S,C,r);assert(max(abs(e))<0.1,'非零初态40次内未配平：%s。',mat2str(e));
r.output=a.output;r.snapshot=a.snapshot;r.gasTemperatureK=a.snapshot.tt45K;
r.seed=a.diagnostics(17+(1:cfg.topology.gasCount));
if r.thermal.enabled
    % 若要求热平衡初态，必须提供配套热状态；本例保留用户给定温度并明确标记。
    S.events{end+1}=struct('timeS',0,'kind','nonzero_cold_metal_initial', ...
        'description','轴系/气路配平，金属温度为配置给定值，并非热平衡');
end
r.controller=struct('fuel',r.fuel,'command',r.fuel,'normal',[],'count',0, ...
    'temperatureLimit',r.fuel,'diag',struct(),'lastSegment',-1);
r.sensorState=struct();
r=local_kernel(C,cfg,S.points,S.runtimeFiles,struct('fullmodeAction','refresh','runtime',r));
S.runtime=r;
S.events{end+1}=struct('timeS',0,'kind','initial_trim', ...
    'history',trimHistory,'finalSpeedDerivativeRpmPerS',e(:).');
S.throttle='run';if strcmp(r.mode,'idle'),S.throttle='idle';end
S.cfg.fullmode.npRatio=ratio;
clear solverGuard;
end

function local_solver_configuration(alias,values)
status=calllib(alias,'DLL_SHT_LowSpeedSolverConfigure',26082503,numel(values), ...
    libpointer('doublePtr',values));
assert(status==0,'准备阶段气路精度配置/恢复失败：%d。',status);
end

function cost=local_trim_cost(S,C,r,x)
if x(1)<=0 || x(1)>1.05*S.cfg.startStop.designNgRpm || x(2)<=0 || x(2)>.7
    cost=1e12;return;
end
r.speed(2)=x(1);r.fuel=x(2);
try,e=local_trim_eval(S,C,r);cost=sum(e.^2);catch,cost=1e12;end
end

function [e,a]=local_trim_eval(S,C,r)
state=libpointer('doublePtr',zeros(64,1));
local_call(C,'DLL_SHT_FullModeExportState',26100701,64,state);before=state.Value;
a=local_kernel(C,S.cfg,S.points,S.runtimeFiles, ...
    struct('fullmodeAction','evaluate','runtime',r,'command',4));
local_call(C,'DLL_SHT_FullModeExportState',26100701,64,state);after=state.Value;
% 前7项负载表随当前查询转速更新，其余私有状态必须逐项保持。
assert(isequaln(before(8:end),after(8:end)), ...
    '零时间配平评估推进了起停私有状态，不能作为初态准备。');
if ~a.converged
    diagnostic=struct('modelMode',S.cfg.modelMode,'loadMode',S.cfg.fullmode.loadMode, ...
        'loadConfiguration',S.cfg.fullmode.load,'speedRpm',r.speed, ...
        'fuelKgPerS',r.fuel,'thermalEnabled',r.thermal.enabled, ...
        'thermalState',r.thermal.state,'acceptedSeed',r.seed, ...
        'candidateSeeds',a.candidateSeeds,'attemptHistory',{a.attemptHistory}, ...
        'callStatus',a.callStatus,'diagnostics',a.diagnostics,'stepOut',a.output, ...
        'cStateBefore',before,'cStateAfter',after,'exceptionMessage',a.errorMessage);
    folder=fullfile(S.cfg.fullmode.outputDirectory,'diagnostics');
    if ~isfolder(folder),mkdir(folder);end
    file=[tempname(folder),'.mat'];save(file,'diagnostic','-v7.3');
    error('sht:fullmode:initialGasPath', ...
        ['非零初态气路无解：Np=%g, Ng=%g rpm, Wf=%g kg/s，call=%g，' ...
        'solver=%g，maxR=%g，尝试%d组根，valid=%g。数值证据：%s。%s'], ...
        r.speed(1),r.speed(2),r.fuel,a.callStatus,a.diagnostics(1), ...
        a.diagnostics(14),numel(a.attemptHistory),a.output(24),file,a.errorMessage);
end
e=a.output(1:2);
end

function [S,receipt]=local_submit(S,q)
assert(isstruct(q) && isscalar(q) && isfield(q,'requestId') && isfield(q,'action'), ...
    '命令必须为包含requestId和action的标量结构。');
assert(local_text_scalar(q.requestId) && local_text_scalar(q.action), ...
    'requestId和action必须为非空单行文本。');
q.requestId=char(q.requestId);q.action=char(q.action);
id=char(q.requestId);assert(~isempty(id) && numel(id)<=128,'requestId为空或过长。');
existing=find(strcmp({S.receipts.requestId},id),1);
if ~isempty(existing)
    assert(strcmp(S.receipts(existing).payload,jsonencode(orderfields(q))), ...
        '同一requestId不能携带不同命令。');receipt=S.receipts(existing);return;
end
receipt=local_receipt();receipt.requestId=id;receipt.action=char(q.action);
receipt.submittedAt=datestr(now,31);receipt.acceptedTimeS=S.runtime.timeS;
receipt.state='accepted';
try
    receipt.payload=jsonencode(orderfields(q));
    assert(~any(strcmp(S.lifecycle,{'failed','terminated'})),'数值会话已终止，只能保存/查看/关闭。');
    cut=strcmp(q.action,'emergency_cutoff') || ...
        (strcmp(q.action,'select_throttle') && isfield(q,'value') && ...
        local_text_scalar(q.value) && strcmp(q.value,'cut'));
    if cut
        S.cutLatched=true;
        for k=S.pending(:).',S.receipts(k).state='superseded_by_cutoff';end
        S.pending=[];
    elseif S.cutLatched && ~strcmp(q.action,'acknowledge_cutoff')
        error('sht:fullmode:cutoffLatched','切断已锁存，必须物理停转后明确复位，旧RUN不能越过切断。');
    end
    switch q.action
        case 'select_throttle'
            assert(isfield(q,'value') && local_text_scalar(q.value) && ...
                any(strcmp(q.value,{'cut','idle','run'})),'油门必须为cut/idle/run单个文本值。');
            if strcmp(q.value,'run'),assert(S.runtime.warmupComplete && ...
                    any(strcmp(S.runtime.mode,{'idle','run'})),'暖机未完成或状态不允许进入运行。');end
        case {'start','cold_blow'}
            assert(S.runtime.physicalStop,'起动和冷吹需确认物理停转，不拼接新轨迹。');
            if strcmp(q.action,'start')
                assert(strcmp(S.throttle,'idle'),'先选择慢车，再单独发起起动。');
                % 也保护非零初态停车后的再次起动，不能仅检查最初配置。
                local_check_cold_direct_load(S.cfg);
            end
        case 'exit_cold_blow'
            assert(strcmp(S.runtime.mode,'coldblow'),'当前不是冷吹。');
        case 'abort_start'
            assert(any(strcmp(S.runtime.mode,{'cranking','warmup'})),'当前不在起动/暖机。');
        case 'normal_stop'
            assert(any(strcmp(S.runtime.mode,{'idle','run','idle_handover'})),'当前不允许计划停车。');
        case 'emergency_cutoff'
        case 'set_np_gear'
            assert(isfield(q,'value'),'Np挡位命令缺少value。');
            validateattributes(q.value,{'numeric'},{'scalar','real','finite'});
            assert(any(q.value==[.8,.9,.95,1,1.05]),'Np挡位必须为设计转速80/90/95/100/105%。');
        case 'apply_load'
            assert(isfield(q,'value') && isstruct(q.value) && isscalar(q.value), ...
                'apply_load需要标量负载结构。');
            if strcmp(S.cfg.fullmode.loadMode,'power'),allowed={'powerW'};
            elseif strcmp(S.cfg.fullmode.loadMode,'mkp'),allowed={'mkpNm'};
            else,allowed={'mainPitchDeg','tailPitchDeg'};end
            names=fieldnames(q.value);
            assert(~isempty(names) && all(ismember(names,allowed)), ...
                '当前%s负载只接受字段：%s。',S.cfg.fullmode.loadMode,strjoin(allowed,','));
            assert(~any(strcmp(S.runtime.mode,{'cranking','warmup','idle_handover'})), ...
                '起动和暖机采用连续接载参考，在线负载请在慢车/运行时施加；不能接受后又被暖机参考覆盖。');
            cfg=S.cfg;cfg.fullmode.load=sht_merge_config(cfg.fullmode.load,q.value);
            sht_fullmode_load_boundary(cfg,S.runtime.speed(1),S.runtime.speed(3));
            if S.runtime.physicalStop,local_check_cold_direct_load(cfg);end
        case 'acknowledge_cutoff'
            assert(S.runtime.physicalStop,'切断复位必须等物理停转。');
        otherwise
            error('sht:fullmode:command','未知命令：%s。',q.action);
    end
catch ex
    receipt.state='rejected';receipt.reason=ex.message;
end
S.receipts(end+1)=receipt;
if strcmp(receipt.state,'accepted'),S.pending(end+1)=numel(S.receipts);end
end

function local_check_cold_direct_load(cfg)
% 直接轴负载在正常运行中仍可施加；只拒绝已取消的正负载静止组合。
f=cfg.fullmode;
if (strcmp(f.loadMode,'power') && f.load.powerW>0) || ...
        (strcmp(f.loadMode,'mkp') && f.load.mkpNm>0)
    error('sht:fullmode:unsupportedColdDirectLoad', ...
        '不支持正恒功率/正恒Mkp从静止起动或在静止时施加。请使用相容的非零初态，或使用双总距起动方案。');
end
end

function [S,indices]=local_apply_pending(S)
indices=S.pending;
for k=indices(:).'
    q=jsondecode(S.receipts(k).payload);
    oldMode=S.runtime.mode;
    switch q.action
        case 'select_throttle'
            S.throttle=q.value;
            if strcmp(q.value,'cut'),S.runtime.mode='shutdown';
            elseif strcmp(q.value,'run'),S.runtime.mode='run';
            elseif strcmp(S.runtime.mode,'run'),S.runtime.mode='idle';end
        case 'start'
            S.runtime.mode='cranking';S.runtime.warmupComplete=false;
            S.runtime.controller=[];S.runtime.startupControl=[];
        case 'cold_blow'
            S.runtime.mode='coldblow';S.runtime.controller=[];
        case {'exit_cold_blow','abort_start','emergency_cutoff'}
            S.runtime.mode='shutdown';S.throttle='cut';
        case 'normal_stop'
            S.runtime.mode='cooldown';S.throttle='idle';
        case 'set_np_gear'
            S.cfg.fullmode.npRatio=q.value;
        case 'apply_load'
            S.cfg.fullmode.load=sht_merge_config(S.cfg.fullmode.load,q.value);
        case 'acknowledge_cutoff'
            S.cutLatched=false;S.throttle='cut';
    end
    if ~strcmp(oldMode,S.runtime.mode),S.runtime.modeStartS=S.runtime.timeS;end
end
end

function S=local_record(S)
r=S.runtime;p=r.plant;m=r.sample;b=r.appliedLoad;
row=[r.timeS;r.speed;p.Tt45;m.T45;p.Mkp;m.Mkp; ...
    p.Np;m.Np;p.Ng;m.Ng;r.fuel;r.output(6);r.output(4);r.output(7); ...
    r.output(12);r.output(11)*r.speed(1)*pi/30;S.cfg.fullmode.npRatio*S.cfg.startStop.designNpRpm; ...
    r.output(19);b.mainPitchDeg;b.tailPitchDeg;b.mainTorqueNm;b.tailTorqueNm; ...
    double(b.powerEngaged);r.output(24)].';
% 第24槽为C侧实际气路有效标记。无效气路不以保留的控制后备值冒充测量真值。
channels=local_extra_channels();
extra=nan(1,2*numel(channels)+1);
for k=1:numel(channels)
    name=channels{k};
    if isfield(p,name),extra(2*k-1)=p.(name);end
    if isfield(m,name),extra(2*k)=m.(name);end
end
extra(end)=p.WIn;
gasEvaluated=r.snapshot.physicalValid && all(isfinite(r.snapshot.stationWTP(:)));
actualReference=NaN;
if isfield(r.controlInfo,'governorNpReferenceRpm'),actualReference=r.controlInfo.governorNpReferenceRpm;end
S.traceRows(end+1,:)=[row,extra,double(gasEvaluated),r.output(1:2).',r.output(21:23).',actualReference];
if r.thermal.enabled,S.thermalRows(end+1,:)=[r.timeS;r.thermal.state].';end
end

function names=local_trace_names()
names={'timeS','NpRpm','NgRpm','NrotorPTEquivalentRpm','Tt45TrueK','Tt45MeasuredK', ...
    'MkpTrueNm','MkpMeasuredNm','NpTrueRpm','NpMeasuredRpm','NgTrueRpm','NgMeasuredRpm', ...
    'actuatorFuelKgPerS','effectiveFuelKgPerS','phase','flameFraction','freewheelEngaged', ...
    'actualPTLoadPowerW','NpTargetRpm','CClockS','mainPitchDeg','tailPitchDeg', ...
    'mainAeroTorqueNm','tailAeroTorqueNm','powerLoadEngaged','gasPathValid'};
channels=local_extra_channels();
units={'Pa','K','Pa','K','Pa','Pa','K','K','Nm','Pa','K','m',''};
for k=1:numel(channels)
    names=[names,{[channels{k},'True',units{k}],[channels{k},'Measured',units{k}]}]; %#ok<AGROW>
end
names{end+1}='inletMassFlowKgPerS';
names{end+1}='gasPathEvaluated';
names=[names,{'NpDotRpmPerS','NgDotRpmPerS','hotStartFlag','hungStartFlag','flameoutFlag'}];
names{end+1}='NpGovernorReferenceRpm';
end

function channels=local_extra_channels()
channels={'Pt2','Tt1','Pt3','Tt3','Pt45','Pt5','Tt5','T4','Mkg','Pamb','Tamb','Altitude','Mach'};
end

function yes=local_text_scalar(value)
yes=(ischar(value) && isrow(value) && ~isempty(value)) || ...
    (isstring(value) && isscalar(value) && ~ismissing(value) && strlength(value)>0);
end

function result=local_result(S)
names=local_trace_names();
result=struct('configuration',S.cfg,'identity',S.assets,'trace',array2table(S.traceRows,'VariableNames',names), ...
    'thermalTrace',table(),'commands',S.receipts,'events',{S.events}, ...
    'terminalStatus',local_status(S),'matlabVersion',version,'createdAt',S.createdAt);
if S.runtime.thermal.enabled
    thermalNames=[{'timeS'},reshape(S.runtime.thermal.stateNames,1,[])];
    thermalNames=matlab.lang.makeValidName(thermalNames);
    result.thermalTrace=array2table(S.thermalRows,'VariableNames',thermalNames);
end
result.signalRoles=struct('truth',{{'NpTrueRpm','NgTrueRpm','Tt45TrueK','MkpTrueNm'}}, ...
    'measuredFeedback',{{'NpMeasuredRpm','NgMeasuredRpm','Tt45MeasuredK','MkpMeasuredNm'}}, ...
    'derived',{{'NrotorPTEquivalentRpm','actualPTLoadPowerW'}}, ...
    'unmodeled',{{'oilPressure','oilTemperature','electricalBus'}});
for k=27+2*(0:numel(local_extra_channels())-1)
    result.signalRoles.truth{end+1}=names{k};
end
result.signalRoles.measured=names(contains(names,'Measured'));
result.signalRoles.derived{end+1}='inletMassFlowKgPerS';
result.signalRoles.diagnostics={'gasPathValid','gasPathEvaluated','NpDotRpmPerS', ...
    'NgDotRpmPerS','hotStartFlag','hungStartFlag','flameoutFlag'};
result.signalRoles.derived{end+1}='NpGovernorReferenceRpm';
result.recordSchema=26100704;
result.signalRoles.validity=['gasPathValid保留DLL第24项有效标志（含零速轴系后备）；' ...
    'gasPathEvaluated表示已有实际气路解。NaN表示物理量不可用，不补零。'];
end

function out=local_status(S)
r=S.runtime;
out=struct('lifecycle',S.lifecycle,'mode',r.mode,'throttle',S.throttle,'timeS',r.timeS, ...
    'speedRpm',r.speed,'acceptedSteps',r.acceptedSteps,'physicalStop',r.physicalStop, ...
    'warmupComplete',r.warmupComplete,'cutLatched',S.cutLatched,'failureReason',r.failureReason, ...
    'stopReason',S.stopReason,'wallSeconds',S.wallSeconds,'commandReceipts',S.receipts, ...
    'appliedLoad',r.appliedLoad,'requestedLoad',S.cfg.fullmode.load, ...
    'alarms',struct('hotStart',logical(r.output(21)),'hungStart',logical(r.output(22)), ...
    'flameout',logical(r.output(23))));
end

function r=local_receipt()
r=struct('requestId','','action','','state','','submittedAt','','acceptedTimeS',NaN, ...
    'appliedTimeS',NaN,'reason','','payload','');
end

function local_require(S)
assert(~isempty(S),'尚未prepare会话。');
end
function local_call(C,name,varargin)
status=calllib(C.alias,name,varargin{:});assert(status==0,'DLL函数%s失败：%d。',name,status);
end
function local_unload(alias)
if libisloaded(alias),unloadlibrary(alias);end
end
function local_close_on_error(armed)
% prepare/restore的onCleanup仅在异常时关闭，成功后由调用方显式清除保护。
if armed.get(),sht_fullmode_session('close');end
end
function h=local_hash(file)
fid=fopen(file,'rb');assert(fid>=0,'不能读取身份文件：%s。',file);c=onCleanup(@()fclose(fid));
d=java.security.MessageDigest.getInstance('SHA-256');d.update(typecast(fread(fid,inf,'*uint8'),'int8'));
h=upper(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end
function local_verify_identity(a,b)
assert(numel(a)==numel(b),'恢复源/资产清单数量变化，不能给旧快照重签名。');
for i=1:numel(a)
    assert(strcmp(a(i).name,b(i).name) && strcmp(a(i).sha256,b(i).sha256), ...
        '恢复身份不匹配：%s。',a(i).name);
end
end
function n=local_c_command(mode)
if strcmp(mode,'run'),n=2;elseif strcmp(mode,'coldblow'),n=5;
elseif any(strcmp(mode,{'cranking','warmup'})),n=1;
elseif strcmp(mode,'stopped'),n=0;
elseif strcmp(mode,'shutdown'),n=3;else,n=4;end
end
function cfg=local_restore_locations(cfg,override,root)
% 恢复只准搬迁读写位置；参数/积分/控制修改须另起准备或显式运行命令。
assert(isstruct(override) && isscalar(override),'恢复位置覆盖应为标量结构体。');
groups=fieldnames(override);assert(all(ismember(groups,{'paths','fullmode','stage7'})), ...
    '恢复不能覆盖物理、控制或状态配置。');
for i=1:numel(groups)
    group=groups{i};items=override.(group);assert(isstruct(items) && isscalar(items));
    if strcmp(group,'paths'),allowed=fieldnames(cfg.paths);
    elseif strcmp(group,'fullmode'),allowed={'outputDirectory','assetDirectory','seedPoolFile'};
    else,allowed={'assetFile'};end
    fields=fieldnames(items);assert(all(ismember(fields,allowed)),'恢复覆盖只允许路径字段。');
    for j=1:numel(fields)
        value=items.(fields{j});assert(ischar(value) || (isstring(value) && isscalar(value)));
        cfg.(group).(fields{j})=char(value);
    end
end
assert(strcmp(cfg.paths.matlabRoot,root),'源码根目录由实际入口决定，不能覆盖。');
end
function local_write_utf8(file,text)
fid=fopen(file,'w','n','UTF-8');assert(fid>=0);c=onCleanup(@()fclose(fid));fprintf(fid,'%s',text);
end
