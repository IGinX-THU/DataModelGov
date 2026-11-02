function result = Start_StartStopModeling_SimpleTest(designTaskDirectory,user)
%START_STARTSTOPMODELING_SIMPLETEST 新设计模型的有限低速检查，不进行调图搜索。
% user明确指定adapterDirectory、codeDirectory、taskDirectory。
% 复用起停建模适配器的私有资产准备/扩图，复用原低速矩阵求解器。
% 这是9个指定低速点的简单测试，不等于连续起动/暖机/停车或热校准。
assert(nargin==2 && isstruct(user),'sht:dp:startupConfig','请明确指定起停适配器、核心及新任务目录。');
for n={'adapterDirectory','codeDirectory','taskDirectory'}
    assert(isfield(user,n{1})&&~isempty(user.(n{1})),'sht:dp:startupConfig','缺少%s。',n{1});
end
assert(isempty(setdiff(fieldnames(user),{'adapterDirectory','codeDirectory','taskDirectory', ...
    'engineOverrides','showFigures'})),'sht:dp:startupConfig','存在未知起停简单测试配置。');
d=sht_design_point_task('validate',designTaskDirectory);
assert(d.accepted && strcmpi(sht_design_point_mdl('sha256',d.candidateMdl),d.candidateSHA256), ...
    'sht:dp:designNotVerified','需要本次已复现、身份未变的设计配置。');
oldPath=path;restore=onCleanup(@()path(oldPath)); %#ok<NASGU>
addpath(user.adapterDirectory,'-begin');
assert(strcmpi(which('sht_startstop_modeling_task'),fullfile(user.adapterDirectory,'sht_startstop_modeling_task.m')), ...
    'sht:dp:startupAdapter','没有选中明确指定的起停适配器。');
u=struct('modelMode',d.config.modelMode,'taskDirectory',user.taskDirectory, ...
    'engineId',d.config.engineId,'source',struct('codeDirectory',user.codeDirectory, ...
    'modelDirectory',d.candidateDirectory,'dllDirectory',d.candidateDirectory, ...
    'modelFile',d.config.modelFile,'designStateFile', ...
    fullfile(d.taskDirectory,'MiddleData','design_state.mat')), ...
    'display',struct('showFigures',false,'generateMapFigures',false));
if isfield(user,'engineOverrides'),u.engineOverrides=user.engineOverrides;end
if isfield(user,'showFigures'),u.display.showFigures=user.showFigures;u.display.generateMapFigures=user.showFigures;end
% 新设计的物理量必须传给原低速核心，不能默用旧20800/20900等默认。
u.engineOverrides.startStop.designNpRpm=d.config.design.NpRpm;
u.engineOverrides.startStop.designNgRpm=d.config.design.NgRpm;
u.engineOverrides.startStop.nozzleAreaM2=d.config.design.nozzleAreaM2;
u.engineOverrides.startStop.designRotorPowerW=d.config.design.loadPowerW;
u.engineOverrides.startStop.gtAccessoryPowerW=d.config.design.accessoryPowerW;
timer=tic;fprintf('起停简单测试粗估30~600秒：扩图及9个低速点，不含连续起停。\n');
t=sht_startstop_modeling_task('prepare',u);
assert(strcmp(t.status,'ready'),'sht:dp:startupInputs','起停准备未就绪，请检查preflight。');
t=sht_startstop_modeling_task('runstage',t.taskDirectory,'maps');
assert(strcmp(t.stages.maps.status,'completed') && t.stages.maps.selectedPassed, ...
    'sht:dp:maps','扩图或原工作域检查未通过，见任务逐项结果。');
s=load(fullfile(t.taskDirectory,t.stages.maps.resultFile),'result');
maps=s.result;if isfield(maps,'maps'),maps=maps.maps;end
cfg=sht_startstop_modeling_task('engineconfig',t);
context=sht_startstop_modeling_package('context',t.bundle); %#ok<NASGU>
runRoot=fullfile(t.taskDirectory,'report_outputs','design_point_simple_test');mkdir(runRoot);
runtime=sht_startstop_create_runtime(cfg,maps.mapResult,runRoot);
alias='GTESS';assert(~libisloaded(alias),'sht:dp:libraryOccupied','GTESS正在被使用；不会强制卸载。');
oldDir=pwd;dirCleanup=onCleanup(@()cd(oldDir)); %#ok<NASGU>
cd(runtime.controlDir);
sht_load_engine_library(runtime.dllPath,runtime.headerPath,'alias',alias,'includepath',runtime.controlDir);
try
    matrix=local_matrix(alias,cfg,runtime,maps.mapResult,d.solution.design,runRoot);
catch ex
    try,local_close(alias);catch cleanupError,warning('sht:dp:cleanup','%s',cleanupError.message);end
    rethrow(ex);
end
local_close(alias);
result=struct('schema',26101401,'designTaskDirectory',d.taskDirectory, ...
    'designModelSHA256',d.candidateSHA256,'taskDirectory',t.taskDirectory, ...
    'modelMode',d.config.modelMode,'configuration',cfg,'runtime',runtime, ...
    'maps',maps.mapResult,'matrix',matrix,'accepted',matrix.accepted, ...
    'elapsedSeconds',toc(timer),'continuousTest','not_run','thermalTest','not_run');
save(fullfile(runRoot,'simple_test_result.mat'),'result','-v7.3');
writetable(matrix.table,fullfile(runRoot,'simple_test_points.xlsx'),'UseExcel',false);
disp(matrix.table);
fprintf('简单测试通过点数%d/%d；实际耗时%.3f秒。未运行连续起停或热状态测试。\n', ...
    sum([matrix.points.solverConverged]),numel(matrix.points),result.elapsedSeconds);
end

function r=local_matrix(alias,cfg,runtime,maps,design,output)
status=calllib(alias,'DLL_SHT_InitialMode',cfg.modelMode);
assert(status==0,'sht:dp:startupInit','起停DLL初始化失败%d。',status);
sht_startstop_configure_dll(alias,cfg);
e.eng=libstruct('EngineTurboshaft');p=libstruct('EngineSHTPointer',e);
input=libpointer('doublePtr',zeros(512,1));out=libpointer('doublePtr',zeros(128,1));
status=calllib(alias,'DLL_SHT_ConditionsInit',input,out,p);
assert(status==0,'sht:dp:startupInit','起停环境初始化失败%d。',status);
options=struct('ngRatio',[0.2,0.3,0.65],'branchNames',{{'lagging'}},'branchFactors',0.6, ...
    'stateNames',{{'no_fuel','pre_ignition','fired_low_fuel'}}, ...
    'label','design_point_simple_9','outputDir',output,'writeEvidence',true);
r=sht_startstop_evaluate_low_speed_matrix(alias,p,cfg,maps.extendedMapDir,design,options);
assert(isfile(runtime.modelPath),'sht:dp:runtime','运行MDL丢失。');
end

function local_close(alias)
if ~libisloaded(alias),return;end
status=calllib(alias,'DLL_SHT_Free');assert(status==0,'sht:dp:free','DLL释放失败。');
unloadlibrary(alias);assert(~libisloaded(alias),'sht:dp:unload','DLL未卸载。');
end
