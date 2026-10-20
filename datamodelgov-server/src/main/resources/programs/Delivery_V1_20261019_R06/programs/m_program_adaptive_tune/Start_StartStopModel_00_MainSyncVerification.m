function result = Start_StartStopModel_00_MainSyncVerification(snapshotRoot)
%START_STARTSTOPMODEL_00_MAINSYNCVERIFICATION 主模型同步的可重复验收入口。
% 仅读取StartupStop内的主模型快照，与分支DLL在相同原图、MDL和输入下
% 分别运行。没有将主目录作为运行目录，也不会向主目录写入任何资产。
cfg = sht_startstop_default_config();
if nargin < 1
    snapshotRoot = fullfile(cfg.paths.branchRoot,'Backups','MainSync_20260907_step1');
end
sourceDir = fullfile(snapshotRoot,'main','M');
assert(isfolder(sourceDir), '缺少已备份的主模型来源。');
clock = tic;
designResult = RunModelSHT_V2_2DP();
assert(designResult.accepted, '当前MDL设计点复现不通过，禁止继续。');
sht_startstop_stage_asset('publish','design',cfg,designResult);
assetNames = {'transient_effects_split_kurzke27_parameters.mat', ...
    'transient_effects_split_visser29_parameters_v2.mat'};
assets = cell(1,numel(assetNames));
for i = 1:numel(assets)
    data = load(fullfile(sourceDir,'MiddleData',assetNames{i}),'parameterAsset');
    assets{i} = data.parameterAsset;
end
reference = local_replay(sourceDir,designResult,assets,'GTESS_SYNC_REFERENCE');
candidate = local_replay(cfg.paths.matlabRoot,designResult,assets,'GTESS_SYNC_CURRENT');
names = fieldnames(reference);
rows = cell(numel(names),7);
for i = 1:numel(names)
    a = reference.(names{i}); b = candidate.(names{i});
    outputError = max(abs(a.output-b.output)./max(abs(a.output),1));
    derivativeError = max(abs(a.derivative-b.derivative)./max(abs(a.derivative),1));
    passed = a.status==0 && b.status==0 && a.convergeTag==0 && b.convergeTag==0 ...
        && max(a.residual,b.residual)<=1e-6 ...
        && all(isfinite([a.output;b.output;a.derivative;b.derivative])) ...
        && max(outputError,derivativeError) <= 1e-7;
    rows(i,:) = {names{i},a.status,b.status,a.residual,b.residual, ...
        max(outputError,derivativeError),passed};
end
comparison = cell2table(rows,'VariableNames',{'caseName','mainStatus', ...
    'branchStatus','mainResidual','branchResidual','maximumRelativeDifference','accepted'});
disp(comparison);
result = struct('accepted',all(comparison.accepted),'comparison',comparison, ...
    'reference',reference,'candidate',candidate,'snapshotRoot',snapshotRoot, ...
    'design',designResult.design,'generatedAt',datestr(now,31));
result.normalRegionRegression = struct('accepted',result.accepted, ...
    'commonVariableMaximumAbsolute',max(abs(reference.design.variables-candidate.design.variables)), ...
    'outputMaximumRelative',max(comparison.maximumRelativeDifference), ...
    'oldMaximumResidual',reference.design.residual, ...
    'newMaximumResidual',candidate.design.residual);
out = fullfile(cfg.paths.outputRoot,['MainSync_',datestr(now,'yyyymmdd_HHMMSS')]);
mkdir(out);
writetable(comparison,fullfile(out,'main_branch_comparison.csv'));
if result.accepted
    % 先用相同温度、冷却分流和参考间隙验证两DLL，再发布兼容资产。
    % 标称参数/表数据不改变；仅记录明确的继承来源和本次数值验证证据。
    engineCfg=struct('interface',struct('controlDir',cfg.paths.matlabRoot, ...
        'libraryName','GTESS','headerName','GTESS.h'), ...
        'modelConfiguration',fullfile(cfg.paths.matlabRoot,'Turboshaft-TS-Split.mdl'));
    actual=sht_engine_artifact_identity(engineCfg);
    targetIdentity=struct('dllFile',actual(1).file,'dllSHA256',actual(1).sha256, ...
        'headerFile',actual(2).file,'headerSHA256',actual(2).sha256, ...
        'modelFile',actual(3).file,'modelSHA256',actual(3).sha256);
    for i = 1:numel(assets)
        parameterAsset = assets{i};
        parameterAsset.inheritanceVerification = struct('sourceIdentity', ...
            parameterAsset.modelIdentity,'comparisonFile',fullfile(out,'main_branch_comparison.csv'), ...
            'verifiedAt',datestr(now,31),'accepted',true);
        parameterAsset.modelIdentity = targetIdentity;
        save(fullfile(cfg.paths.matlabRoot,'MiddleData',assetNames{i}), 'parameterAsset','-v7.3');
    end
    sht_startstop_stage_asset('publish','main_sync',cfg,result);
end
result.elapsedSeconds = toc(clock);
save(fullfile(out,'main_sync_complete_result.mat'),'result','-v7.3');
fprintf('主模型同步一致性：%d；耗时 %.1f s；%s\n',result.accepted,result.elapsedSeconds,out);
assert(result.accepted,'主模型同步一致性未通过，请检查逐项对照。');
end

function result = local_replay(controlDir,designResult,assets,alias)
if nargin < 4 || isempty(alias)
    alias = 'GTESS_SYNC';
end
programDir = fileparts(mfilename('fullpath'));
originalPath = path;
addpath(programDir);
pathCleanup = onCleanup(@() path(originalPath));
oldDir = pwd;
cd(controlDir);
directoryCleanup = onCleanup(@() cd(oldDir));
alias = 'GTESS_SYNC';
sht_load_engine_library(fullfile(controlDir,'GTESS.dll'),fullfile(controlDir,'GTESS.h'), ...
    'alias',alias,'thunkfilename',[alias, '_thunk']);
try
    assert(calllib(alias,'DLL_SHT_InitialMode',1)==0);
    init.eng = libstruct('EngineTurboshaft');
    ptr = libstruct('EngineSHTPointer',init);
    clear init;
    in = libpointer('doublePtr',zeros(512,1));
    out = libpointer('doublePtr',zeros(128,1));
    assert(calllib(alias,'DLL_SHT_ConditionsInit',in,out,ptr)==0);
    d = designResult.design;
    x = zeros(512,1);
    t = designResult.designTargets;
    x(1:10) = [t.NpRpm;t.NgRpm;d.Wf;t.nozzleAreaM2;0;t.loadPowerW;t.accessoryPowerW;0;0;0];
    x(21:29) = d.commonVariables(1:9);
    result.design = local_evaluate(alias,ptr,in,out,x,'DLL_SHT_RunOnePoint');
    base = x;
    % 正常区多个固定状态。求导验证不要求气动力矩和负载平衡，但要求气路收敛。
    speeds = [1,1,1; .95,.97,.90; .90,.93,.76; .80,.87,.57; .70,.82,.40];
    for i=1:size(speeds,1)
        x=base; x(1:3)=base(1:3).*speeds(i,:)';
        result.(sprintf('state_%d',i))=local_evaluate(alias,ptr,in,out,x,'DLL_SHT_RunOneStep');
    end
    for h=[0:25,30:39,44:53,71:88]
        x=base; x(41+h)=.002;
        result.(sprintf('health_%d',h))=local_evaluate(alias,ptr,in,out,x,'DLL_SHT_RunOneStep');
    end
    % 新边界模式：外部恢复和独立背压不能互相覆盖，也不能当作健康修正。
    x=base;
    boundary=struct('inletBoundaryMode',5,'Ps0',90000,'Tamb',298.15, ...
        'Mach',.2,'Tt1',300,'inletTotalPressureRecovery',.98);
    x=sht_apply_inlet_boundary_stepin(x,boundary);
    x(10)=92000;
    result.flightBoundary=local_evaluate(alias,ptr,in,out,x,'DLL_SHT_RunOneStep');
    interface=struct('libraryName',alias);
    sht_initialize_reynolds_correction_dll(interface,1,sht_reynolds_correction_config(1));
    result.reynoldsEnabled=local_evaluate(alias,ptr,in,out,x,'DLL_SHT_RunOneStep');
    sht_initialize_reynolds_correction_dll(interface,1,sht_reynolds_correction_config(0));
    result.variableScheduleNodes=local_schedule_nodes(alias);
    in.Value=zeros(512,1);
    assert(calllib(alias,'DLL_SHT_ConditionsInit',in,out,ptr)==0);
    for k=1:numel(assets)
        asset=assets{k};
        sht_initialize_thermal_model_dll(interface,1,sht_build_thermal_model_configuration(asset));
        if k==2, sht_initialize_cooling_split_dll(interface,1,asset.coolingSplitConfiguration); end
        for perturb=[0,15,-15]
            x=sht_build_transient_step_in_template(asset,'joint_full');
            x(1:10)=base(1:10); x(21:29)=base(21:29);
            x(301:300+numel(asset.nominal.initialTemperatureState))= ...
                asset.nominal.initialTemperatureState(:)+perturb;
            x(488:493)=sht_lookup_clearance_reference(asset.referenceTable, ...
                base(1),base(2),base(6),288.15);
            name=sprintf('thermal%d_%d',k,perturb+15);
            result.(name)=local_evaluate(alias,ptr,in,out,x,'DLL_SHT_RunOneStep');
        end
    end
    calllib(alias,'DLL_SHT_Free'); clear ptr in out;
    unloadlibrary(alias);
catch exception
    calllib(alias,'DLL_SHT_Free'); clear ptr in out;
    unloadlibrary(alias); rethrow(exception);
end
end

function r=local_schedule_nodes(alias)
% 节点数为数据，不再假定6/7点；直接检验1点、32点、端点截断和非法表拒绝。
assert(calllib(alias,'DLL_SHT_HealthScheduleReset')==0);
xp=libpointer('doublePtr',1); dp=libpointer('doublePtr',.003);
assert(calllib(alias,'DLL_SHT_HealthScheduleConfigureTable',1,5,1,xp,dp)==0);
yp=libpointer('doublePtr',0); answer=zeros(5,1);
for i=1:2
    assert(calllib(alias,'DLL_SHT_HealthScheduleEvaluateIncrement',1,i*2-2,yp)==0);
    answer(i)=yp.Value;
end
xx=linspace(.5,1,32)'; yy=.01*(xx-1);
xp=libpointer('doublePtr',xx); dp=libpointer('doublePtr',yy);
assert(calllib(alias,'DLL_SHT_HealthScheduleConfigureTable',1,5,32,xp,dp)==0);
coordinates=[0,.731,2];
for i=1:3
    assert(calllib(alias,'DLL_SHT_HealthScheduleEvaluateIncrement',1,coordinates(i),yp)==0);
    answer(i+2)=yp.Value;
end
assert(max(abs(answer-[.003;.003;-.005;-.00269;0]))<1e-14);
assert(calllib(alias,'DLL_SHT_HealthScheduleConfigureTable',0,1,1,xp,dp)~=0);
xx(3)=xx(2); xp.Value=xx;
assert(calllib(alias,'DLL_SHT_HealthScheduleConfigureTable',1,5,32,xp,dp)~=0);
assert(calllib(alias,'DLL_SHT_HealthScheduleReset')==0);
r=struct('status',0,'convergeTag',0,'residual',0,'variables',zeros(9,1), ...
    'output',answer,'derivative',zeros(29,1));
end

function r=local_evaluate(alias,ptr,in,out,x,entry)
in.Value=x;
assert(calllib(alias,'DLL_SHT_varIteInit',in,out,ptr)==0);
[status,~,values,ep]=calllib(alias,entry,in,out,ptr);
e=ep.eng;
r=struct('status',status,'convergeTag',e.convergeTag, ...
    'residual',max(abs(e.errOut(1:7))), 'variables',e.varIte(1:9)', ...
    'output',[e.Inlet.gasPathOut(:);e.HPC.y(:);e.HPC2.y(:); ...
    e.HPT.y(:);e.HPT2.y(:);e.LPT.y(:);e.LPT2.y(:); ...
    e.LPS_Nmech;e.HPS_Nmech;e.LPS_Trq], 'derivative',values(1:29));
end
