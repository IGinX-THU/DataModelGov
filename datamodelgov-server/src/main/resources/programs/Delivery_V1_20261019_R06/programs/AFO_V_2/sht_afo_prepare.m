function p = sht_afo_prepare(cfg)
%SHT_AFO_PREPARE 创建独立运行副本；原SLX、DLL、MDL和控制律不写入。
assert(~bdIsLoaded('Dll_Control_AFO_V8_5_R2019b'),'sht:afo:modelBusy', ...
    '本进程已打开同名SLX。请先自行关闭，或使用独立MATLAB进程；本接口不覆盖已打开模型。');
assert(~libisloaded('GTESS'),'sht:afo:dllBusy','本进程GTESS已加载，请使用独立MATLAB进程。');
validateattributes(cfg.duration,{'double'},{'scalar','positive','finite'});
validateattributes(cfg.recordStep,{'double'},{'scalar','positive','finite'});
validateattributes(cfg.logEverySeconds,{'double'},{'scalar','positive','finite'});
sht_afo_session('validate',cfg);
assert(ismember(cfg.pace,{'realtime','fast'}),'不支持的运行节奏。');
assert(islogical(cfg.externalAir)&&isscalar(cfg.externalAir),'externalAir须为逻辑标量。');
assert(~exist(cfg.outputDir,'dir'),'sht:afo:exists','结果目录已存在，不覆盖。');
clock = tic;
mkdir(cfg.outputDir); runtime = fullfile(cfg.outputDir,'runtime'); mkdir(runtime);
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
old=pwd; oldPath=path; oldGen=Simulink.fileGenControl('getConfig');
cleaner=onCleanup(@() local_restore(old,oldPath,oldGen));
cd(runtime);
Simulink.fileGenControl('set','CacheFolder',fullfile(runtime,'cache'), ...
    'CodeGenFolder',fullfile(runtime,'code'),'createDir',true);
% R2019b切换缓存配置可能恢复旧搜索路径，必须在该操作后加入业务依赖。
addpath(cfg.sourceDir,'-begin');addpath(runtime,'-begin');
v=sht_afo_initialize(runtime);
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
model='Dll_Control_AFO_V8_5_R2019b';load_system(fullfile(runtime,[model '.slx']));
mw=get_param(model,'ModelWorkspace'); fields=fieldnames(v);
for k=1:numel(fields),assignin(mw,fields{k},v.(fields{k}));end
assignin(mw,'ExternalSecondaryAirEnabled',double(cfg.externalAir));
assignin(mw,'Wfb',v.Wf0);
% 去掉旧InitFcn对基础工作区及相邻项目的隐式依赖，数值边界不变。
set_param(model,'InitFcn','');
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
% 新源只替代四个指令常值，原物理接线和原脉冲验证分支均保留。
commandNames={'NpDem','Constant2','Mkp Direct Command','Collective Pitch Command'};
reference=isfield(cfg,'verificationOriginalSources')&&cfg.verificationOriginalSources;
if reference,assert(cfg.legacyPulses,'原指令源只用于显式旧脉冲回归。');end
for k=1:4
    if reference,continue;end % 回归保留原常值块，运行身份在下方按实际SLX计算。
    b=[model '/' commandNames{k}]; ph=get_param(b,'PortHandles');
    ln=get_param(ph.Outport,'Line'); dest=get_param(ln,'DstPortHandle'); pos=get_param(b,'Position');
    delete_line(ln);delete_block(b);
    add_block('simulink/User-Defined Functions/Level-2 MATLAB S-Function',b, ...
        'FunctionName','SFunc_AFO_Command','Parameters',num2str(k),'Position',pos);
    ph=get_param(b,'PortHandles');
    for j=1:numel(dest),add_line(model,ph.Outport,dest(j),'autorouting','on');end
end
% 全部业务输出接同一个只读记录器，不增加物理反馈。
spec=sht_afo_channels; sink=[model '/AFO Business Recorder'];
add_block('simulink/User-Defined Functions/Level-2 MATLAB S-Function',sink, ...
    'FunctionName','SFunc_AFO_Recorder','Parameters',num2str(numel(spec)), ...
    'Position',[2200 100 2360 400]);
for k=1:numel(spec)
    src=Simulink.ID.getHandle([model ':' num2str(spec(k).sid)]);
    ph=get_param(src,'PortHandles'); dest=get_param(sink,'PortHandles');
    add_line(model,ph.Outport(spec(k).port),dest.Inport(k),'autorouting','on');
end
save_system(model);close_system(model,0);
p=struct('config',cfg,'runtime',runtime,'model',model,'identity',identity, ...
    'initialState',v.InitStat,'initialOutput',v.InitOut, ...
    'initialTransition',changed, ...
    'prepareSeconds',toc(clock),'schema','SHT_AFO_PREPARED_V1', ...
    'preparedAtLocal',datestr(now,'yyyy-mm-ddTHH:MM:SS'), ...
    'matlabVersion',version,'matlabRelease',version('-release'));
% 新入口与记录器的身份同样参与结果追溯，不只记录旧物理模型。
helpers={'sht_afo_config.m','sht_afo_initialize.m','sht_afo_prepare.m', ...
    'sht_afo_session.m','sht_afo_results.m','sht_afo_channels.m', ...
    'SFunc_AFO_Command.m','SFunc_AFO_Recorder.m','Start_AFO_Multisystem.m', ...
    'sht_afo_submit.m','Start_AFO_ResultView.m'};
for k=1:numel(helpers)
    p.identity(end+1)=struct('name',helpers{k},'sha256',local_hash(fullfile(cfg.sourceDir,helpers{k})));
end
p.identity(end+1)=struct('name','runtime/instrumented_model.slx', ...
    'sha256',local_hash(fullfile(runtime,[model '.slx'])));
for k=2:numel(names)
    p.identity(end+1)=struct('name',['runtime/' names{k}], ...
        'sha256',local_hash(fullfile(runtime,names{k})));
end
save(fullfile(cfg.outputDir,'prepared.mat'),'p');
fprintf('AFO准备完成：实际Np=%.3f rpm，Ng=%.3f rpm，准备%.2f s。\n', ...
    v.InitStat(1),v.InitStat(2),p.prepareSeconds);
fprintf('预计人工1倍速计算至少%.1f s，另加编译/暂停；fast不保证实时。\n',cfg.duration);
end
function local_restore(folder,p,g)
if bdIsLoaded('Dll_Control_AFO_V8_5_R2019b'),close_system('Dll_Control_AFO_V8_5_R2019b',0);end
Simulink.fileGenControl('setConfig','config',g);cd(folder);path(p);
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
