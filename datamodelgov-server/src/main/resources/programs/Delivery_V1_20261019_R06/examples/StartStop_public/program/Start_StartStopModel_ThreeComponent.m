function result = Start_StartStopModel_ThreeComponent(stage,userCfg)
%START_STARTSTOPMODEL_THREECOMPONENT 三部件起停模型的完整M工作流。
% result=Start_StartStopModel_ThreeComponent('all')依次执行扩图、低速矩阵、
% 受约束校准、连续起停、Visser16热浸与单元检查。
% 也可选maps/matrix/run/thermal/verify。verify不启动完整连续历程。
% 输入仅为本StartupStop目录的原始HPC/HPT/LPT图、三部件MDL和显式先验。
% 所有新图只写MiddleData/startstop/three_component，不覆盖输入原图。
if nargin<1,stage='all';end
if nargin<2,userCfg=struct();end
originalPath=path;
addpath(fileparts(mfilename('fullpath')));
pathCleanup=onCleanup(@()path(originalPath)); %#ok<NASGU>
userCfg.modelMode=0;
cfg=sht_startstop_default_config(userCfg);
cfg.paths.outputRoot=fullfile(cfg.paths.outputRoot,'three_component');
if ~isfolder(cfg.paths.outputRoot),mkdir(cfg.paths.outputRoot);end
assert(any(strcmp(stage,{'all','maps','matrix','run','thermal','verify'})),'未知执行阶段。');
result=struct('requestedStage',stage,'accepted',true);
if any(strcmp(stage,{'all','maps'}))
    root=fullfile(cfg.paths.outputRoot,['Maps_',datestr(now,'yyyymmdd_HHMMSS_FFF')]);
    mkdir(root);
    mapResult=sht_startstop_run_map_stages(cfg,root);
    result.maps=struct('mapResult',mapResult,'accepted', ...
        mapResult.stage1Accepted && mapResult.stage2Accepted,'runRoot',root);
    sht_startstop_stage_asset('publish','stage12',cfg,result.maps);
end
if any(strcmp(stage,{'all','matrix'}))
    source=sht_startstop_stage_asset('load','stage12',cfg);
    root=fullfile(cfg.paths.outputRoot,['Matrix_',datestr(now,'yyyymmdd_HHMMSS_FFF')]);
    mkdir(root); runtime=sht_startstop_create_runtime(cfg,source.mapResult,root);
    old=pwd; cd(runtime.controlDir); restore=onCleanup(@()cd(old));
    alias='GTESS';
    sht_load_engine_library(runtime.dllPath,runtime.headerPath,'alias',alias);
    clean=onCleanup(@()local_close(alias));
    eng=local_initialize(alias,cfg);
    design=local_design(alias,eng,cfg);
    % 不从MDL的通用负载示例值推断旋翼设计功率，而由气路设计点复算。
    cfg.startStop.designRotorPowerW=design.rotorPowerW;
    cfg.startStop.nozzleAreaM2=design.nozzleAreaM2;
    fprintf('三部件设计点：Np=%.6f, Ng=%.6f rpm，PT功率=%.3f kW。\n', ...
        design.commonVariables(5:6),design.rotorPowerW/1000);
    sht_startstop_configure_dll(alias,cfg);
    baseline=sht_startstop_evaluate_low_speed_matrix(alias,eng,cfg, ...
        runtime.controlDir,design,struct('writeEvidence',true,'outputDir',fullfile(root,'before')));
    fprintf('低速矩阵初检：%d/%d。\n',baseline.summary.acceptedCount,baseline.summary.applicableCount);
    if cfg.stage5.calibrationEnabled && ~baseline.accepted
        calibration=sht_startstop_calibrate_low_speed_maps(alias,cfg,runtime,design, ...
            fullfile(root,'calibration'),true);
        theta=calibration.thetaBest;
    else
        calllib(alias,'DLL_SHT_Free');
        theta=sht_startstop_map_parameters(cfg);
        calibration=struct('thetaBest',theta,'performed',false);
    end
    audit=sht_startstop_write_candidate_maps(cfg,theta,runtime.controlDir);
    assert(audit.accepted,'候选扩图不满足原图区冻结/有限性检查。');
    eng=local_initialize(alias,cfg);
    final=sht_startstop_evaluate_low_speed_matrix(alias,eng,cfg,runtime.controlDir,design, ...
        struct('writeEvidence',true,'outputDir',fullfile(root,'after')));
    audit=sht_startstop_write_candidate_maps(cfg,theta,fullfile(root,'maps'));
    result.matrix=struct('accepted',final.accepted && audit.accepted, ...
        'runRoot',root,'configuration',cfg,'design',design,'thetaBest',theta, ...
        'baselineMatrix',baseline,'calibration',calibration, ...
        'finalMatrix',final,'finalMapAudit',audit);
    save(fullfile(root,'result.mat'),'result','-v7.3');
    if result.matrix.accepted
        sht_startstop_stage_asset('publish','stage05',cfg,result.matrix);
    end
    clear eng clean;
    unloadlibrary(alias);
    clear restore;
    fprintf('三部件低速矩阵最终：%d/%d；结果%s。\n', ...
        final.summary.acceptedCount,final.summary.applicableCount,root);
    assert(result.matrix.accepted,'低速矩阵尚有失败，已保留逐点原因。');
end
if any(strcmp(stage,{'all','run','thermal'}))
    frozen=sht_startstop_stage_asset('load','stage05',cfg);
    userCfg.startStop.designRotorPowerW=frozen.design.rotorPowerW;
    userCfg.startStop.nozzleAreaM2=frozen.design.nozzleAreaM2;
    userCfg.paths.outputRoot=cfg.paths.outputRoot;
end
if any(strcmp(stage,{'all','run'}))
    result.continuous=Start_StartStopModel_04_ContinuousStartStopAndRobustness(userCfg);
end
if any(strcmp(stage,{'all','thermal'}))
    result.thermal=Start_StartStopModel_05_VisserThermalCouplingAndFreeze(userCfg);
end
if any(strcmp(stage,{'all','verify'}))
    result.kernel=Test_StartStop_KernelsAndThermalTopology(0);
    result.coastdownMatrix=Test_StartStop_ThreeComponentCoastdownMatrix;
end
fields={'maps','matrix','continuous','thermal','kernel','coastdownMatrix'};
for i=1:numel(fields)
    if isfield(result,fields{i}),result.accepted=result.accepted && result.(fields{i}).accepted;end
end
result.completedAt=datestr(now,31);
% 工作流索引只服务本模型；历史结果仍保留，不能覆盖六部件索引。
root=fullfile(cfg.paths.matlabRoot,'MiddleData','startstop','three_component');
if ~isfolder(root),mkdir(root);end
save(fullfile(root,['workflow_',stage,'_latest.mat']),'result','-v7.3');
end

function eng=local_initialize(alias,cfg)
assert(calllib(alias,'DLL_SHT_InitialMode',0)==0,'三部件初始化失败。');
sht_startstop_configure_dll(alias,cfg);
p.eng=libstruct('EngineTurboshaft'); eng=libstruct('EngineSHTPointer',p);
assert(calllib(alias,'DLL_SHT_ConditionsInit',libpointer('doublePtr',zeros(512,1)), ...
    libpointer('doublePtr',zeros(128,1)),eng)==0,'环境初始化失败。');
end

function d=local_design(alias,eng,cfg)
% 原V1方程：六个共同工作/轴平衡残差，加燃烧室出口总温目标。
% 设计目标1620K和2176.6kW沿用已确认三部件基准，不重写MDL。
text=fileread(cfg.paths.splitModel);
tok=regexp(text,'(?m)^\s*varStartVec\s*=([^\r\n]+)','tokens','once');
x=[sscanf(tok{1},'%f');0.15171];
targetPowerW=2176600;targetTt4K=1620;accessoryPowerW=0;
explicit=isfield(cfg,'designReference') && ~isempty(cfg.designReference);
if explicit
    r=cfg.designReference;
    assert(r.modelMode==0 && numel(r.commonVariables)==6, ...
        'sht:startstop:designReference','三部件不能消费六部件共同工作解。');
    x=[r.commonVariables(:);r.fuelFlowKgPerS];
    targetPowerW=r.loadPowerW;targetTt4K=r.targetTt4K;accessoryPowerW=r.accessoryPowerW;
end
scale=[10;1;5;5;cfg.startStop.designNpRpm;cfg.startStop.designNgRpm;.3];
for iteration=1:20
    [r,output]=evaluate(x);
    if max(abs(r))<1e-8,break;end
    assert(~explicit,'sht:startstop:designReplay', ...
        '显式设计解直接回放残差为%g；禁止重新配平掩盖设计结果或MDL错配。',max(abs(r)));
    J=zeros(7);
    for j=1:7
        xp=x;xp(j)=xp(j)+1e-5*scale(j);
        J(:,j)=(evaluate(xp)-r)/1e-5;
    end
    dx=-(J\r).*scale;
    accepted=false;
    for alpha=2.^-(0:12)
        trial=x+alpha*dx;
        if any(trial([1,3:7])<=0),continue;end
        if norm(evaluate(trial))<norm(r),x=trial;accepted=true;break;end
    end
    assert(accepted,'三部件设计校核没有下降方向，r=%g。',max(abs(r)));
end
[r,output]=evaluate(x);
assert(max(abs(r))<1e-8,'三部件设计点方程不闭合。');
assert(max(abs(x(5:6)-[cfg.startStop.designNpRpm;cfg.startStop.designNgRpm]))<0.1, ...
    'MDL设计点与明确的设计转速不一致，禁止静默接受。');
d=struct('commonVariables',x(1:6),'fuelFlowKgPerS',x(7), ...
    'output',[output.HPC.y(3:4),output.Burner.y(3),output.HPT.y(3),output.LPT.y(3)], ...
    'rotorPowerW',output.LPT.y(6)*output.LPS.effMech*x(5)*pi/30, ...
    'nozzleAreaM2',cfg.startStop.nozzleAreaM2, ...
    'residual',r,'accepted',true);
if explicit,d.designReference=cfg.designReference;end
    function [r,e]=evaluate(v)
        in=zeros(512,1);in(1:3)=[v(5:6);v(7)];
        in(4)=cfg.startStop.nozzleAreaM2;in(6)=targetPowerW;in(7)=accessoryPowerW;
        in(21:26)=v(1:6);
        [status,~,out,p]=calllib(alias,'DLL_SHT_RunSteadyComponents', ...
            libpointer('doublePtr',in),libpointer('doublePtr',zeros(128,1)),eng);
        assert(status==0,'设计点DLL求值失败：%d。',status);
        e=p.eng; r=[out(1:6);(e.Burner.y(3)-targetTt4K)/targetTt4K];
    end
end

function local_close(alias)
if libisloaded(alias)
    % 异常清理时外层libstruct可能尚未释放，因此先释放C实例；正常路径
    % 清除全部指针后再卸载库，避免MATLAB的“未清除变量”卸载错误。
    calllib(alias,'DLL_SHT_Free');
end
end
