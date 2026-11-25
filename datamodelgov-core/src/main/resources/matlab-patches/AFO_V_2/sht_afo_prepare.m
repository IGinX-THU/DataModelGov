function p = sht_afo_prepare(cfg)
%SHT_AFO_PREPARE 创建独立运行副本；原SLX、DLL、MDL和控制律不写入。
% 复用阶梯(数字试车台专属引擎场景):改装模型常驻引擎内存→免load+免手术;
% 项目级改装缓存(_dmg_cache)→免手术;初态结果按依赖SHA缓存→免GTESS重算。
% 首场全新引擎仍走完整流程:复制资产+SHA、初始化、手术、保存。
MODEL='Dll_Control_AFO_V8_5_R2019b';
reference=isfield(cfg,'verificationOriginalSources')&&cfg.verificationOriginalSources;
% 手术版本戳:与 sht_afo_surgery.m/sht_afo_presurgery.m 的 tag 格式一致;
% 手术逻辑或通道字典变化时同步递增 v1,旧改装(内存/缓存)自动失效重做。
expectedTag=sprintf('dmg-afo-surgery-v1|n=%d|ref=%d',numel(sht_afo_channels),double(reference));
assert(~libisloaded('GTESS'),'sht:afo:dllBusy','本进程GTESS已加载，请使用独立MATLAB进程。');
if bdIsLoaded(MODEL)
    sink=[MODEL '/AFO Business Recorder'];
    ours=~isempty(find_system(MODEL,'SearchDepth',1,'Name','AFO Business Recorder'))&&...
        ~isempty(get_param(sink,'Tag'))&&startsWith(get_param(sink,'Tag'),'dmg-afo-surgery');
    assert(ours,'sht:afo:modelBusy', ...
        '本进程已打开同名SLX。请先自行关闭，或使用独立MATLAB进程；本接口不覆盖已打开模型。');
end
validateattributes(cfg.duration,{'double'},{'scalar','positive','finite'});
validateattributes(cfg.recordStep,{'double'},{'scalar','positive','finite'});
validateattributes(cfg.logEverySeconds,{'double'},{'scalar','positive','finite'});
sht_afo_session('validate',cfg);
if ~isfield(cfg,'publishLive'),cfg.publishLive=true;end
if ~isfield(cfg,'publishWallStep'),cfg.publishWallStep=.2;end
if ~isfield(cfg,'publishBatchSize'),cfg.publishBatchSize=128;end
validateattributes(cfg.publishLive,{'logical'},{'scalar'});
validateattributes(cfg.publishWallStep,{'double'},{'scalar','finite','>=',.05});
validateattributes(cfg.publishBatchSize,{'double'},{'scalar','integer','>=',1,'<=',4096});
assert(ismember(cfg.pace,{'realtime','fast'}),'不支持的运行节奏。');
assert(islogical(cfg.externalAir)&&isscalar(cfg.externalAir),'externalAir须为逻辑标量。');
assert(~exist(cfg.outputDir,'dir'),'sht:afo:exists','结果目录已存在，不覆盖。');
clock = tic;
mkdir(cfg.outputDir); runtime = fullfile(cfg.outputDir,'runtime'); mkdir(runtime);
stageFile=fullfile(runtime,'prepare-stage.txt');  % Java 5s tick读取映射为界面阶段文案
stg = tic;
% 只取成套运行所需资产，不复制旧缓存、自动保存或其他版本模型。
names = {'Dll_Control_AFO_V8_5_R2019b.slx','GTESS.dll','GTESS.h', ...
    'blockAndFunctions.h','types_TMATS.H','Turboshaft-TS.mdl', ...
    'HPC01.MAP','HPC02.MAP','HPT01.Map','HPT02.MAP','LPT01.MAP','LPT02.MAP', ...
    'RunCtrlSysModelSHT.m','SFunc_EngModel.m','SFunc_RotorLoadBoundary.m', ...
    'SFunc_SecondaryAirFeedback.m','g04_to_oil_boundaries_fcn.m', ...
    'oil_cooler_inlet_from_bearings_fcn.m','sfunc_out2_to_airboundary_tp16.m', ...
    'sfunc_to_airproxy8_v3_inputs.m','run_fuelIC.m'};
identity=struct('name',{},'sha256',{});
for k=1:numel(names)
    source=fullfile(cfg.sourceDir,names{k}); assert(exist(source,'file')~=0,'缺少 %s',source);
    sourceHash=local_hash(source);
    if k==1,assert(strcmp(sourceHash,'caed99207d6f7f4b56c1167e4c652b29251a64fd215569d18f526eabbfd74400'), ...
            'sht:afo:modelIdentity','SLX不是已核对的V8_5_R2019b-R105油温单位修正版；需重新确认端口和依赖。');end
    if k==2,assert(strcmp(sourceHash,'29a8c435ed37e4c51b5399f1ffea921c5d8f12ee2d1b28fdda5e02c8d112dddd'), ...
            'sht:afo:dllIdentity','DLL不是AFO已核对身份，不能自动使用主程序新DLL。');end
    copyfile(source,fullfile(runtime,names{k}));
    identity(k)=struct('name',names{k},'sha256',sourceHash);
    % AFO历史M为UTF-8。仅运行副本按R2019b CP936无损转换，不改源。
    if endsWith(names{k},'.m'),local_runtime_encoding(fullfile(runtime,names{k}));end
end
stgCopySecs = toc(stg); fprintf('AFO_PREPARE stage1 copy+sha256: %.2f s\n',stgCopySecs); stg = tic;
local_stage(stageFile,'stage1');
stgEnv = tic;
old=pwd; oldPath=path; oldGen=Simulink.fileGenControl('getConfig');
cleaner=onCleanup(@() local_restore(old,oldPath,oldGen));
cd(runtime);
Simulink.fileGenControl('set','CacheFolder',fullfile(fileparts(fileparts(runtime)),'_slCache'), ...
    'CodeGenFolder',fullfile(runtime,'code'),'createDir',true);
% R2019b切换缓存配置可能恢复旧搜索路径，必须在该操作后加入业务依赖。
addpath(cfg.sourceDir,'-begin');addpath(runtime,'-begin');
fprintf('AFO_PREPARE stage1b env(cd+cache+path): %.2f s\n',toc(stgEnv));
local_stage(stageFile,'stage1b');
% ---- stage2: 初始化(依赖SHA缓存:GTESS.dll与初始化脚本任一未变即直取上次结果) ----
stgInit = tic;
scriptSha='';
for k=1:numel(names)
    if strcmp(names{k},'RunCtrlSysModelSHT.m'),scriptSha=identity(k).sha256;end
end
cacheKey=sprintf('%s|%s|%s',identity(2).sha256,scriptSha,version('-release'));
cached=[];
try,cached=evalin('base','dmg_afo_init_cache');catch,end
if ~(isstruct(cached)&&isfield(cached,'key')&&strcmp(cached.key,cacheKey)&&...
        isfield(cached,'v')&&isfield(cached.v,'Ts')&&isfield(cached.v,'Np0')&&...
        isfield(cached.v,'power0')&&isfield(cached.v,'Wf0')&&isfield(cached.v,'InitStat'))
    % 引擎内存无缓存(新引擎/回填/重启):回退项目级磁盘缓存,免GTESS重算(实测单次2~13s)
    try
        loaded=load(fullfile(cfg.sourceDir,'_dmg_cache','init_cache.mat'));
        if isfield(loaded,'key')&&strcmp(loaded.key,cacheKey)&&isfield(loaded,'v')&&...
                isfield(loaded.v,'Ts')&&isfield(loaded.v,'Np0')&&isfield(loaded.v,'InitStat')
            cached=struct('key',loaded.key,'v',loaded.v);
            assignin('base','dmg_afo_init_cache',cached);  % 回填引擎内存,后续直取
        end
    catch
    end
end
if isstruct(cached)&&isfield(cached,'key')&&strcmp(cached.key,cacheKey)&&...
        isfield(cached,'v')&&isfield(cached.v,'Ts')&&isfield(cached.v,'Np0')&&...
        isfield(cached.v,'power0')&&isfield(cached.v,'Wf0')&&isfield(cached.v,'InitStat')
    v=cached.v;
    fprintf('AFO_PREPARE stage2 initialize (cached): 0.00 s\n');
    local_stage(stageFile,'stage2');
else
    v=sht_afo_initialize(runtime);
    assignin('base','dmg_afo_init_cache',struct('key',cacheKey,'v',v));
    try
        cacheDirI=fullfile(cfg.sourceDir,'_dmg_cache');
        if ~isfolder(cacheDirI),mkdir(cacheDirI);end
        meta=struct('key',cacheKey,'v',v);
        save(fullfile(cacheDirI,'init_cache.mat'),'-struct','meta');
    catch
    end
    fprintf('AFO_PREPARE stage2 initialize: %.2f s\n',toc(stgInit));
    local_stage(stageFile,'stage2');
end
stg = tic;
assert(abs(cfg.recordStep/v.Ts-round(cfg.recordStep/v.Ts))<1e-9, ...
    '记录周期须为模型积分步长的整数倍，不能修改原积分步。');
cfg.designNpRpm=v.Np0; cfg.designPowerW=v.power0; cfg.modelStep=v.Ts;
sht_afo_session('validate',cfg);
assert(abs(cfg.duration/v.Ts-round(cfg.duration/v.Ts))<1e-8, ...
    '仿真终点须落在0.025秒积分网格上。');
changed=abs(cfg.npRatio-1)>1e-12;
switch cfg.loadMode
    case 'power',changed=changed||abs(cfg.powerW-v.power0)>1e-8;
    case 'torque',changed=changed||abs(cfg.mkpNm-v.power0/(v.Np0*pi/30))>1e-8;
    case 'pitch',changed=changed||abs(cfg.pitchDeg-12)>1e-12;
    case 'dual_pitch',changed=changed||abs(cfg.mainPitchDeg-12)>1e-12||abs(cfg.tailPitchDeg-cfg.tailDesignPitchDeg)>1e-12;
end
assert(~changed||cfg.initialTransitionConfirmed,'sht:afo:initialTransition', ...
    '当前只能准备配套正转速初态。初始目标不同，请先确认从该初态过渡，或运行后再施加。');
% ---- 内存改装模型守卫:同版本手术戳且已停止则复用;版本不符弃用重做 ----
stgGuard = tic;
model=MODEL;
rtSlx=fullfile(runtime,[model '.slx']);
if bdIsLoaded(model)
    sink=[model '/AFO Business Recorder'];
    try
        if ~strcmp(get_param(model,'SimulationStatus'),'stopped')
            set_param(model,'SimulationCommand','stop');
        end
    catch
    end
    t0=tic;
    while bdIsLoaded(model)&&~strcmp(get_param(model,'SimulationStatus'),'stopped')&&toc(t0)<60
        pause(0.2);
    end
    if ~strcmp(get_param(model,'SimulationStatus'),'stopped')||...
            ~strcmp(get_param(sink,'Tag'),expectedTag)
        close_system(model,0);  % 上一场未停止/旧版本改装:弃用,下方走load+手术
    end
end
fprintf('AFO_PREPARE stage3a guard: %.2f s\n',toc(stgGuard));
local_stage(stageFile,'stage3a');
stgLoad = tic;
if ~bdIsLoaded(model)
    % 项目级改装缓存(上一场手术产物/启动预装配产物):免手术,只付load
    cacheDir=fullfile(cfg.sourceDir,'_dmg_cache');
    cacheSlx=fullfile(cacheDir,[model '.slx']);
    fromCache=false;
    if exist(cacheSlx,'file')==2
        meta=local_cache_meta(fullfile(cacheDir,'cache.mat'));
        fromCache=~isempty(meta)&&strcmp(meta.tag,expectedTag)&&...
            strcmp(meta.sourceSha,identity(1).sha256);
    end
    if fromCache
        copyfile(cacheSlx,rtSlx);  % 覆盖stage1新拷的原始模型
        try
            load_system(rtSlx);
        catch
            copyfile(fullfile(cfg.sourceDir,[model '.slx']),rtSlx); % 缓存损坏回退原始模型
            load_system(rtSlx);
        end
    else
        load_system(rtSlx);
    end
end
stgLoadSecs = toc(stgLoad); fprintf('AFO_PREPARE stage3 load_system: %.2f s\n',stgLoadSecs); stg = tic;
local_stage(stageFile,'stage3');
stgMW = tic;
mw=get_param(model,'ModelWorkspace'); fields=fieldnames(v);
for k=1:numel(fields),assignin(mw,fields{k},v.(fields{k}));end
assignin(mw,'ExternalSecondaryAirEnabled',double(cfg.externalAir));
assignin(mw,'Wfb',v.Wf0);
% 去掉旧InitFcn对基础工作区及相邻项目的隐式依赖，数值边界不变。
set_param(model,'InitFcn','');
stgMWsec = toc(stgMW); fprintf('AFO_PREPARE stage4 workspace+pulses: %.2f s\n',stgMWsec); stgSurg = tic;
local_stage(stageFile,'stage4');
if strcmp(cfg.loadMode,'power'),mode='legacyPower';
elseif strcmp(cfg.loadMode,'torque'),mode='directTorque';
else,mode='collectivePitch';end
assignin(mw,'RotorLoadInputMode',mode);
set_param(model,'StopTime',sprintf('%.17g',cfg.duration),'ReturnWorkspaceOutputs','on', ...
    'SaveTime','on','TimeSaveName','tout');
if ~cfg.legacyPulses
    pulses=find_system(model,'SearchDepth',1,'BlockType','DiscretePulseGenerator');
    for k=1:numel(pulses),set_param(pulses{k},'Amplitude','0');end
end
[connections,surgeried]=sht_afo_surgery(model,cfg);  % 幂等:同版本手术戳已就位则零成本返回
% runtime副本必须与内存中改装模型一致(run前身份校验与结果追溯都指向该文件)
if ~strcmp(get_param(model,'FileName'),rtSlx)
    fn=get_param(model,'FileName');
    if exist(fn,'file')==2
        copyfile(fn,rtSlx);          % 上一场runtime的改装模型文件(毫秒级)
    else
        save_system(model,rtSlx);    % 旧输出目录已清理:内存状态落盘(兜底)
    end
end
if surgeried
    % 手术刚发生:同步项目级改装缓存,下一次prepare/启动预装配免手术
    cacheDir=fullfile(cfg.sourceDir,'_dmg_cache');
    if ~exist(cacheDir,'dir'),mkdir(cacheDir);end
    try
        copyfile(rtSlx,fullfile(cacheDir,[model '.slx']));
        meta=struct('tag',expectedTag,'sourceSha',identity(1).sha256,'updatedAt',datestr(now));
        save(fullfile(cacheDir,'cache.mat'),'-struct','meta');
    catch
    end
end
fprintf('AFO_PREPARE stage5 surgery+save: %.2f s\n',toc(stgSurg));
local_stage(stageFile,'stage5');
p=struct('config',cfg,'runtime',runtime,'model',model,'identity',identity, ...
    'initialState',v.InitStat,'initialOutput',v.InitOut, ...
    'initialTransition',changed, ...
    'prepareSeconds',toc(clock),'schema','SHT_AFO_PREPARED_V1', ...
    'preparedAtLocal',datestr(now,'yyyy-mm-ddTHH:MM:SS'), ...
    'matlabVersion',version,'matlabRelease',version('-release'), ...
    'observationConnections',{connections});
% 新入口与记录器的身份同样参与结果追溯，不只记录旧物理模型。
stgTail = tic;
helpers={'sht_afo_config.m','sht_afo_initialize.m','sht_afo_prepare.m', ...
    'sht_afo_session.m','sht_afo_results.m','sht_afo_channels.m', ...
    'SFunc_AFO_Command.m','SFunc_AFO_Recorder.m','Start_AFO_Multisystem.m', ...
    'sht_afo_submit.m','Start_AFO_ResultView.m','sht_afo_observation_port.m', ...
    'sht_afo_catalog.m','sht_afo_json.m','sht_afo_read_live.m', ...
    'Start_AFO_Worker.m','sht_afo_display_channels.csv','sht_afo_read_json.m'};
for k=1:numel(helpers)
    p.identity(end+1)=struct('name',helpers{k},'sha256',local_hash(fullfile(cfg.sourceDir,helpers{k})));
end
p.identity(end+1)=struct('name','runtime/instrumented_model.slx', ...
    'sha256',local_hash(rtSlx));
for k=2:numel(names)
    p.identity(end+1)=struct('name',['runtime/' names{k}], ...
        'sha256',local_hash(fullfile(runtime,names{k})));
end
save(fullfile(cfg.outputDir,'prepared.mat'),'p');
fprintf('AFO_PREPARE stage6 identity+save: %.2f s\n',toc(stgTail));
local_stage(stageFile,'stage6');
fprintf('AFO准备完成：实际Np=%.3f rpm，Ng=%.3f rpm，准备%.2f s。\n', ...
    v.InitStat(1),v.InitStat(2),p.prepareSeconds);
fprintf('预计人工1倍速计算至少%.1f s，另加编译/暂停；fast不保证实时。\n',cfg.duration);
end
function local_stage(file,tag)
% 阶段完成标签落盘(ASCII,毫秒级):供Java进度tick读取映射界面文案;失败静默(仅影响文案)
try
    fid=fopen(file,'w');
    if fid>0,fprintf(fid,'%s',tag);fclose(fid);end
catch
end
end
function local_restore(folder,p,g)
% 改装模型保留在内存(下一场prepare直取复用、run免load_system);只还原环境。
Simulink.fileGenControl('setConfig','config',g);cd(folder);path(p);
end
function meta=local_cache_meta(file)
meta=[];
try
    loaded=load(file);
    if isfield(loaded,'tag')&&isfield(loaded,'sourceSha')
        meta=struct('tag',loaded.tag,'sourceSha',loaded.sourceSha);
    end
catch
end
end
function h=local_hash(file)
fid=fopen(file,'rb');g=onCleanup(@()fclose(fid));bytes=fread(fid,Inf,'*uint8');
md=java.security.MessageDigest.getInstance('SHA-256');md.update(bytes); ...
    h=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end
function local_runtime_encoding(file)
fid=fopen(file,'rb');bytes=fread(fid,Inf,'*uint8')';fclose(fid);
txt=native2unicode(bytes,'UTF-8');out=unicode2native(txt,'GBK');
assert(isequal(native2unicode(out,'GBK'),txt),'运行副本编码不能无损转换：%s',file);
fid=fopen(file,'wb');fwrite(fid,out,'uint8');fclose(fid);
end
