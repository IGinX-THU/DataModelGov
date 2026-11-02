function out=sht_fullmode_session(action,varargin)
%SHT_FULLMODE_SESSION 全模式仿真会话统一入口，由数字试车台会话调用。
% 一个进程一次会话：prepare（准备）后 begin 进入，先 select_throttle(idle) 再推进动作。
% submit（提交）携带 requestId 做幂等确认，advance 每次只推进一步（默认0.025s，取自步长）。
% 状态持久化时校验 DLL/源/参数一致性，校验失败时拒绝复用旧 DLL。
persistent S C
if nargin<1,action='status';end
switch lower(action)
    case 'prepare'
        assert(isempty(S),'存在未关闭的活动会话，请先close后再准备。');
        user=struct();if ~isempty(varargin),user=varargin{1};end
        cfg=sht_fullmode_default_config(user);
% 同源恢复只读取当前工作目录，经 MDL/DLL 一致性校验后才允许恢复同一支路。
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
        local_require(S);assert(strcmp(S.lifecycle,'running'),'advance要求running会话(停止收尾期间不可用)。');
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
% 数值异常时立即标记失败并终止推进，避免带病状态继续冒进导致停车。
                S.lifecycle='failed';S.stopReason=ex.identifier;
                S.runtime.failureReason=ex.message;
                S.events{end+1}=struct('timeS',S.runtime.timeS,'kind','numerical_failure', ...
                    'identifier',ex.identifier,'message',ex.message);break;
            end
        end
        S.wallSeconds=S.wallSeconds+toc(timer);out=local_status(S);
    case 'pause'
        local_require(S);assert(strcmp(S.lifecycle,'running'),'未处于running，不能暂停。');
        S.lifecycle='paused';out=local_status(S);
    case 'resume'
        local_require(S);assert(strcmp(S.lifecycle,'paused'),'未处于paused，不能恢复。');
        S.lifecycle='running';out=local_status(S);
    case 'terminate'
% 终止为即时动作：未确认的挂起命令按取消处理，之后由 close 统一回收查看。
        local_require(S);
        if ~any(strcmp(S.lifecycle,{'terminated','failed'}))
            for q=S.pending(:).',S.receipts(q).state='cancelled_by_termination';end
            S.pending=[];S.lifecycle='terminated';S.stopReason='operator_numerical_stop';
            S.events{end+1}=struct('timeS',S.runtime.timeS,'kind','numerical_termination', ...
                'description','紧急断油确认指令，解除断油闭锁。');
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
            '目标目录已存在历史快照或结果文件,拒绝覆盖;请更换输出目录或删除旧产物后再保存。')
        save(file,'snapshot','result','-v7.3');
        writetable(result.trace,fullfile(folder,'fullmode_results.xlsx'),'Sheet','Signals');
        if ~isempty(result.thermalTrace)
            writetable(result.thermalTrace,fullfile(folder,'fullmode_results.xlsx'),'Sheet','ThermalStates');
        end
        if ~isempty(S.receipts)
% R2019b 的结构体数组按字段自动扩展，统一字段后写入同一张命令表。
            writetable(struct2table(S.receipts,'AsArray',true),fullfile(folder,'fullmode_results.xlsx'),'Sheet','Commands');
        end
        meta=struct('schema',S.schema,'configuration',S.cfg,'identity',S.assets, ...
            'events',{S.events},'physicalStop',S.runtime.physicalStop, ...
            'stopReason',S.stopReason,'elapsedWallS',S.wallSeconds,'matlabVersion',version);
        local_write_utf8(fullfile(folder,'fullmode_manifest.json'),jsonencode(meta));
        out=struct('snapshot',file,'excel',fullfile(folder,'fullmode_results.xlsx'));
    case 'restore'
        assert(isempty(S),'恢复前须close，禁止存在活动会话。');
        d=load(varargin{1},'snapshot');T=d.snapshot;
        assert(T.schema==26100701,'快照版本不匹配。');
        root=fileparts(mfilename('fullpath'));
% 校验路径只允许迁移源目录内文件，恢复前按清单对资产做SHA校验。
        base=struct('modelMode',T.cfg.modelMode);
        if numel(varargin)>1
% 若校验后确认位置已迁移，则按恢复覆盖重定位，避免默认路径残留导致C资产校验失败。
% 覆盖仅接受白名单式 paths 键，防止夹带失效的绝对路径。
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
        % 恢复前按当前状态校验气路一致性；转速低于零保持阈值时跳过稳态复算。
        if T.runtime.speed(2)>cfg.lowSpeedSolver.zeroHoldSpeedRpm
            a=local_kernel(C,cfg,points,runtime,struct('fullmodeAction','evaluate', ...
                'runtime',T.runtime,'command',local_c_command(T.runtime.mode)));
            assert(a.converged,'恢复时稳态未能收敛，请检查初态一致性。');
            gasIndices=[1:3,15:17];
            delta=max(abs(a.output(gasIndices)-T.runtime.output(gasIndices)));
            assert(delta<1e-7,'恢复后稳态保持量不一致(delta=%g)。',delta);
        end
        local_call(C,'DLL_SHT_FullModeImportState',26100701,64,libpointer('doublePtr',T.cState));
        T.lifecycle='paused';S=T;out=local_status(S);armed.set(false);clear cleanup;
    case 'close'
        if ~isempty(C)
            alias=C.alias;
            if libisloaded(alias),calllib(alias,'DLL_SHT_Free');end
% DLL_SHT_Free 已释放C侧资源，此处仅回收 MATLAB 库句柄与引用。
            C=[];
            local_unload(alias);
        end
        S=[];C=[];out=struct('lifecycle','empty');
    otherwise
        error('sht:fullmode:action','未知会话动作：%s。',action);
end
end

function [cfg,asset,points,runtime,identity]=local_prepare_assets(cfg)
assert(isfile(cfg.fullmode.seedPoolFile),'缺少确认配置的初值种子池文件：%s。',cfg.fullmode.seedPoolFile);
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
    assert(isfile(items(k).outputPath),'缺少特性图输出文件：%s。',items(k).outputPath);
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
assert(~libisloaded(alias),'DLL已经加载，可能被另一个会话占用，请先检查状态。');
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
% 准备阶段框架调平：按初始化指令构造非零稳态（转速/燃油/气路同步），只调平衡不推进。
% 全部在同一个 DLL 内核内完成，不依赖附加工具箱。
cfg=S.cfg;r=S.runtime;
% 求解前先收紧求解器容差（残差约0.1 rpm/s量级），保证气路调平精度足够。
% 即使Jacobian/迭代方向失真，准备阶段的分步收敛也能完成配置。
solverBefore=C.solverConfiguration;solverTight=solverBefore;
solverTight(3)=min(solverBefore(3),1e-8);alias=C.alias;
local_solver_configuration(alias,solverTight);
solverGuard=onCleanup(@()local_solver_configuration(alias,solverBefore));
ratio=cfg.fullmode.initialNpRatio;
if strcmp(cfg.fullmode.initialKind,'idle'),ratio=cfg.stage6.idleNpRatio;end
if strcmp(cfg.fullmode.initialKind,'maximum'),ratio=1;end
assert(ratio>0 && ratio<=1.05,'当前转速Np超出准备阶段允许范围。');
r.speed=[ratio*cfg.startStop.designNpRpm;cfg.stage6.startupIdleNgRpm;ratio*cfg.startStop.designNpRpm];
% 初始化直接给定Np/PT轴状态；非总距双载模式时第三轴转速归零，避免未对齐的机构初值。
if ~strcmp(cfg.fullmode.loadMode,'dual_collective'),r.speed(3)=0;end
r.mode='run';if strcmp(cfg.fullmode.initialKind,'idle'),r.mode='idle';end
r.warmupComplete=true;r.physicalStop=false;
% 燃油初值先取 idleFuel 前馈作为慢车燃油；只取稳态初值，不加动态偏置。
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
    assert(rcond(J)>1e-12,'稳态联合平衡Jacobian奇异(条件数不足),无法继续求解。');
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
% 常规图解值在拐点附近令 Newton 迭代无法收敛时，启用下降式兜底重试。
% 兜底以缩放变量做无约束搜索，与同一 DLL 的原求解结果保持一致。
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
        error('sht:fullmode:initialTrim','初始微调后转速未收敛：dNp=%g，dNg=%g。',e(1),e(2));
    end
end
[e,a]=local_trim_eval(S,C,r);assert(max(abs(e))<0.1,'残差超过0.1，未达平衡：%s。',mat2str(e));
r.output=a.output;r.snapshot=a.snapshot;r.gasTemperatureK=a.snapshot.tt45K;
r.seed=a.diagnostics(17+(1:cfg.topology.gasCount));
if r.thermal.enabled
% 热模型启用时记录非零冷金属初值事件，由平衡残差自动收敛实现跳过初始平衡。
    S.events{end+1}=struct('timeS',0,'kind','nonzero_cold_metal_initial', ...
        'description','进气/通道平衡残差自动收敛为该设定值，用于跳过初始平衡。');
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
assert(status==0,'准备阶段通道求解/恢复失败：%d。',status);
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
% 前7项为当前查询转速刷新量，仅第8位之后的状态须与暂停前完全一致。
assert(isequaln(before(8:end),after(8:end)), ...
    '暂停时保持平衡推进锁定并冻结状态，恢复后转为动态准备。');
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
        ['微调后状态汇总：Np=%g, Ng=%g rpm, Wf=%g kg/s, call=%g；' ...
        'solver=%g, maxR=%g, 迭代=%d, valid=%g, 数值证据：%s%s'], ...
        r.speed(1),r.speed(2),r.fuel,a.callStatus,a.diagnostics(1), ...
        a.diagnostics(14),numel(a.attemptHistory),a.output(24),file,a.errorMessage);
end
e=a.output(1:2);
end

function [S,receipt]=local_submit(S,q)
assert(isstruct(q) && isscalar(q) && isfield(q,'requestId') && isfield(q,'action'), ...
    '命令应为包含requestId与action的标量结构。');
assert(local_text_scalar(q.requestId) && local_text_scalar(q.action), ...
    'requestId与action必须为非空文本标量。');
q.requestId=char(q.requestId);q.action=char(q.action);
id=char(q.requestId);assert(~isempty(id) && numel(id)<=128,'requestId为空或超过128字符。');
existing=find(strcmp({S.receipts.requestId},id),1);
if ~isempty(existing)
    assert(strcmp(S.receipts(existing).payload,jsonencode(orderfields(q))), ...
        '同一requestId请求携带了不同载荷。');receipt=S.receipts(existing);return;
end
receipt=local_receipt();receipt.requestId=id;receipt.action=char(q.action);
receipt.submittedAt=datestr(now,31);receipt.acceptedTimeS=S.runtime.timeS;
receipt.state='accepted';
try
    receipt.payload=jsonencode(orderfields(q));
    assert(~any(strcmp(S.lifecycle,{'failed','terminated'})),'会话已终止，只能保存/查看/关闭。');
    cut=strcmp(q.action,'emergency_cutoff') || ...
        (strcmp(q.action,'select_throttle') && isfield(q,'value') && ...
        local_text_scalar(q.value) && strcmp(q.value,'cut'));
    if cut
        S.cutLatched=true;
        for k=S.pending(:).',S.receipts(k).state='superseded_by_cutoff';end
        S.pending=[];
    elseif S.cutLatched && ~strcmp(q.action,'acknowledge_cutoff')
        error('sht:fullmode:cutoffLatched','已进入断油闭锁，必须先确认停转(acknowledge_cutoff)才能解除；RUN档不能越过断油。');
    end
    switch q.action
        case 'select_throttle'
            assert(isfield(q,'value') && local_text_scalar(q.value) && ...
                any(strcmp(q.value,{'cut','idle','run'})),'油门档位必须为cut/idle/run之一(文本值)。');
            if strcmp(q.value,'run'),assert(S.runtime.warmupComplete && ...
                    any(strcmp(S.runtime.mode,{'idle','run'})),'暖机未完成或当前不在慢车/运行状态,不能选择RUN档。');end
        case {'start','cold_blow'}
            assert(S.runtime.physicalStop,'起动/冷吹前必须确认物理停转，才能拼接新轨迹。');
            if strcmp(q.action,'start')
                assert(strcmp(S.throttle,'idle'),'必须先选择慢车档位才能起动。');
% 冷态下也允许框架调平，但直接施加负载起动前必须通过冷态负载校验。
                local_check_cold_direct_load(S.cfg);
            end
        case 'exit_cold_blow'
            assert(strcmp(S.runtime.mode,'coldblow'),'当前不是冷吹状态。');
        case 'abort_start'
            assert(any(strcmp(S.runtime.mode,{'cranking','warmup'})),'当前不在起动/暖机阶段。');
        case 'normal_stop'
            assert(any(strcmp(S.runtime.mode,{'idle','run','idle_handover'})),'当前不在慢车或运行状态。');
        case 'emergency_cutoff'
        case 'set_np_gear'
            assert(isfield(q,'value'),'Np档位指令缺少value。');
            validateattributes(q.value,{'numeric'},{'scalar','real','finite'});
            assert(any(q.value==[.8,.9,.95,1,1.05]),'Np档位必须为标准档80/90/95/100/105%。');
        case 'apply_load'
            assert(isfield(q,'value') && isstruct(q.value) && isscalar(q.value), ...
                'apply_load需要负载配置结构。');
            if strcmp(S.cfg.fullmode.loadMode,'power'),allowed={'powerW'};
            elseif strcmp(S.cfg.fullmode.loadMode,'mkp'),allowed={'mkpNm'};
            else,allowed={'mainPitchDeg','tailPitchDeg'};end
            names=fieldnames(q.value);
            assert(~isempty(names) && all(ismember(names,allowed)), ...
                '当前%s模式下只允许这些字段：%s。',S.cfg.fullmode.loadMode,strjoin(allowed,','));
            assert(~any(strcmp(S.runtime.mode,{'cranking','warmup','idle_handover'})), ...
                '起动/暖机阶段不能修改负载参数；负载应在慢车/运行时施加，以保持暖机窗口稳定。');
            cfg=S.cfg;cfg.fullmode.load=sht_merge_config(cfg.fullmode.load,q.value);
            sht_fullmode_load_boundary(cfg,S.runtime.speed(1),S.runtime.speed(3));
            if S.runtime.physicalStop,local_check_cold_direct_load(cfg);end
        case 'acknowledge_cutoff'
            assert(S.runtime.physicalStop,'只有确认物理停转后才能确认断油闭锁。');
        otherwise
            error('sht:fullmode:command','未知指令：%s。',q.action);
    end
catch ex
    receipt.state='rejected';receipt.reason=ex.message;
end
S.receipts(end+1)=receipt;
if strcmp(receipt.state,'accepted'),S.pending(end+1)=numel(S.receipts);end
end

function local_check_cold_direct_load(cfg)
% 冷态直接施加负载拦截：仅放行总距模式，功率或Mkp负载一律拒绝。
f=cfg.fullmode;
if (strcmp(f.loadMode,'power') && f.load.powerW>0) || ...
        (strcmp(f.loadMode,'mkp') && f.load.mkpNm>0)
    error('sht:fullmode:unsupportedColdDirectLoad', ...
        '冷停车状态不支持直接施加功率或Mkp负载;负载只能在慢车/运行状态施加,或改用总距模式。');
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
% 第24项为C侧实测的功率投入状态，与主/尾桨扭矩共同构成负载通道。
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
result.signalRoles.validity=['gasPathValid为DLL侧24通道有效标志(由气路系数决定)，' ...
    'gasPathEvaluated表示实际进入气路解算。NaN表示该样本未参与解算。'];
end

function out=local_status(S)
r=S.runtime;
p=r.plant;m=r.sample;
out=struct('lifecycle',S.lifecycle,'mode',r.mode,'throttle',S.throttle,'timeS',r.timeS, ...
    'speedRpm',r.speed,'acceptedSteps',r.acceptedSteps,'physicalStop',r.physicalStop, ...
    'warmupComplete',r.warmupComplete,'cutLatched',S.cutLatched,'failureReason',r.failureReason, ...
    'stopReason',S.stopReason,'wallSeconds',S.wallSeconds,'commandReceipts',S.receipts, ...
    'appliedLoad',r.appliedLoad,'requestedLoad',S.cfg.fullmode.load, ...
    'tt45K',p.Tt45,'tt45MeasuredK',m.T45,'fuelKgPerS',r.fuel, ...
    'npDesignRpm',S.cfg.startStop.designNpRpm,'npRatioTarget',S.cfg.fullmode.npRatio, ...
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
status=calllib(C.alias,name,varargin{:});assert(status==0,'DLL调用%s失败：%d。',name,status);
end
function local_unload(alias)
if libisloaded(alias),unloadlibrary(alias);end
end
function local_close_on_error(armed)
% prepare/restore 经 onCleanup 兜底：初始化异常时由托管回收器以安全方式关闭会话。
if armed.get(),sht_fullmode_session('close');end
end
function h=local_hash(file)
fid=fopen(file,'rb');assert(fid>=0,'无法读取二进制文件：%s。',file);c=onCleanup(@()fclose(fid));
d=java.security.MessageDigest.getInstance('SHA-256');d.update(typecast(fread(fid,inf,'*uint8'),'int8'));
h=upper(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end
function local_verify_identity(a,b)
assert(numel(a)==numel(b),'恢复源与初态单位不一致，恢复可能失败，请检查标签。');
for i=1:numel(a)
    assert(strcmp(a(i).name,b(i).name) && strcmp(a(i).sha256,b(i).sha256), ...
        '恢复数据不匹配：%s。',a(i).name);
end
end
function n=local_c_command(mode)
if strcmp(mode,'run'),n=2;elseif strcmp(mode,'coldblow'),n=5;
elseif any(strcmp(mode,{'cranking','warmup'})),n=1;
elseif strcmp(mode,'stopped'),n=0;
elseif strcmp(mode,'shutdown'),n=3;else,n=4;end
end
function cfg=local_restore_locations(cfg,override,root)
% 恢复覆盖只允许迁移可写位置；白名单外的模型/资产/参数沿用准备时的校验规则。
assert(isstruct(override) && isscalar(override),'恢复位置覆盖应为标量结构。');
groups=fieldnames(override);assert(all(ismember(groups,{'paths','fullmode','stage7'})), ...
    '恢复不能修改推进状态相关设置。');
for i=1:numel(groups)
    group=groups{i};items=override.(group);assert(isstruct(items) && isscalar(items));
    if strcmp(group,'paths'),allowed=fieldnames(cfg.paths);
    elseif strcmp(group,'fullmode'),allowed={'outputDirectory','assetDirectory','seedPoolFile'};
    else,allowed={'assetFile'};end
    fields=fieldnames(items);assert(all(ismember(fields,allowed)),'恢复载荷只允许通道字段。');
    for j=1:numel(fields)
        value=items.(fields{j});assert(ischar(value) || (isstring(value) && isscalar(value)));
        cfg.(group).(fields{j})=char(value);
    end
end
assert(strcmp(cfg.paths.matlabRoot,root),'源码目录与实际运行目录不一致，可能已改动。');
end
function local_write_utf8(file,text)
fid=fopen(file,'w','n','UTF-8');assert(fid>=0);c=onCleanup(@()fclose(fid));fprintf(fid,'%s',text);
end
