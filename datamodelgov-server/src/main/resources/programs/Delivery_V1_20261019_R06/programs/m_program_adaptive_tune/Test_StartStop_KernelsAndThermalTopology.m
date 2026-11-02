function result=Test_StartStop_KernelsAndThermalTopology(modelMode,verificationDll)
% 起停物理单元、零流量热状态开关及Kurzke/Visser拓扑专项回归。
if nargin<1,modelMode=0;end
if nargin<2,verificationDll='';end
cfg=sht_startstop_default_config(struct('modelMode',modelMode));
op=path;addpath(cfg.paths.matlabRoot);pc=onCleanup(@()path(op)); %#ok<NASGU>
frozen=sht_startstop_stage_asset('load','stage05',cfg);
root=fullfile(cfg.paths.outputRoot,sprintf('Kernel_M%d_%s',modelMode,datestr(now,'yyyymmdd_HHMMSS')));
mkdir(root);runtime=sht_startstop_create_runtime(cfg,frozen.finalMapAudit,root);
% 可用完整重编译候选进行同一组检查；只替换本测试的隔离运行副本。
% 这不发布stage05，不把候选DLL假记成已有运行资产。
if ~isempty(verificationDll)
    assert(isfile(verificationDll),'缺少重编译候选DLL。');
    copyfile(verificationDll,runtime.dllPath);
end
wd=pwd;cd(runtime.controlDir);dc=onCleanup(@()cd(wd)); %#ok<NASGU>
alias='GTESS_SS_KERNEL';sht_load_engine_library(runtime.dllPath,runtime.headerPath,'alias',alias);
assert(calllib(alias,'DLL_SHT_InitialMode',modelMode)==0);sht_startstop_configure_dll(alias,cfg);
init.eng=libstruct('EngineTurboshaft');ep=libstruct('EngineSHTPointer',init);clear init;
pin=libpointer('doublePtr',zeros(512,1));pout=libpointer('doublePtr',zeros(128,1));
assert(calllib(alias,'DLL_SHT_ConditionsInit',pin,pout,ep)==0);
physics=sht_startstop_verify_physics_kernel(alias,cfg,fullfile(root,'physics'));
a=load(cfg.stage7.assetFile,'parameterAsset');asset=a.parameterAsset;
if modelMode==0,asset=sht_startstop_three_thermal_adapter(asset,cfg);end
interface=struct('libraryName',alias);
sht_initialize_thermal_model_dll(interface,modelMode,sht_build_thermal_model_configuration(asset));
sht_initialize_cooling_split_dll(interface,modelMode,asset.coolingSplitConfiguration);
% 非均匀金属温度使零流量根部/转盘换热非零，才能检出开关残留。
x=sht_build_transient_step_in_template(asset,'heat_state');
x(1:40)=0;x(4)=cfg.startStop.nozzleAreaM2;x(30)=.01;x(35)=288.15;
x(cfg.topology.temperatureInputIndices)=asset.nominal.initialTemperatureState;
x(cfg.topology.referenceIndices)=asset.nominal.epsilonSSCurrent;
calllib(alias,'DLL_SHT_StartStopReset',0,0,0,1);
[s,v]=evaluate('DLL_SHT_RunStartStopStep',x);
checks.zeroFlowVisserValid=s==0 && v(24)==1 && all(isfinite(v));
checks.zeroFlowHeatNotTrivial=max(abs(v(cfg.topology.temperatureOutputIndices)))>1e-8;
off=x;off(341)=0;
[s,v]=evaluate('DLL_SHT_RunStartStopStep',off);
checks.thermalSwitchOffClearsDerivatives=s==0 && all(v(25:51)==0);
[s,v]=evaluate('DLL_SHT_RunStartStopStep',x);
checks.thermalSwitchOnRestoresDerivatives=s==0 && max(abs(v(cfg.topology.temperatureOutputIndices)))>1e-8;
invalid=off;invalid(8)=1;
checks.nativeTorqueRejected=evaluate('DLL_SHT_RunStartStopStep',invalid)~=0;
invalid=off;invalid(30)=NaN;
checks.nonfiniteTimeRejected=evaluate('DLL_SHT_RunStartStopStep',invalid)~=0;
invalid=off;invalid(2)=-1;
checks.negativeSpeedRejected=evaluate('DLL_SHT_RunStartStopStep',invalid)~=0;
% 负输入失败后零速起动仍应正常，不能污染状态机/热上下文。
off(31)=1;
[s,v]=evaluate('DLL_SHT_RunStartStopStep',off);
checks.coldCrankAfterFailure=s==0 && v(2)>0 && all(isfinite(v));

% 普通入口在正流量下分别核对15/16或27/29状态热模型。
modelFile=fileread(fullfile(runtime.controlDir,cfg.topology.modelFile));
tok=regexp(modelFile,'(?m)^\s*varStartVec\s*=([^\r\n]+)','tokens','once');
seed=sscanf(tok{1},'%f');
thermalRows={};
for method=[1 3]
    b=asset;
    if method==1 && modelMode==0
        q=load(fullfile(cfg.paths.matlabRoot,'MiddleData','startstop','three_component', ...
            'tc27_kurzke15_parameters.mat'),'parameterAsset');b=q.parameterAsset;
    elseif method==1
        q=load(fullfile(cfg.paths.matlabRoot,'MiddleData', ...
            'transient_effects_split_kurzke27_parameters.mat'),'parameterAsset');b=q.parameterAsset;
    end
    sht_initialize_thermal_model_dll(interface,modelMode,sht_build_thermal_model_configuration(b));
    x=sht_build_transient_step_in_template(b,'joint_full');
    x(1:4)=[seed(end-1:end);.15171;.10573];x(6)=2176600;x(7)=3000;
    x(21:20+numel(seed))=seed;
    count=13+12*modelMode;
    if method==3,count=14+13*modelMode;end
    x(301:300+count)=b.nominal.initialTemperatureState;
    x(cfg.topology.referenceIndices)=b.nominal.epsilonSSCurrent;
    pin.Value=x;calllib(alias,'DLL_SHT_varIteInit',pin,pout,ep);
    [s,v]=evaluate('DLL_SHT_RunOneStep',x);
    valid=s==0 && all(isfinite(v(1:count+2)));
    thermalRows(end+1,:)={method,count+2,s,max(abs(v(3:count+2))),valid}; %#ok<AGROW>
end
calllib(alias,'DLL_SHT_Free');clear ep pin pout;unloadlibrary(alias);
t=cell2table(thermalRows,'VariableNames',{'thermalMode','engineStateCount','status','maximumThermalDerivative','valid'});
result=struct('checks',checks,'physics',physics,'thermal',t,'runRoot',root, ...
    'verificationDll',verificationDll,'runtimeDll',runtime.dllPath, ...
    'accepted',physics.accepted && all(structfun(@(v)logical(v),checks)) && all(t.valid));
writetable(t,fullfile(root,'thermal_topology.csv'));
save(fullfile(root,'result.mat'),'result','-v7');disp(checks);disp(t);
assert(result.accepted,'起停/热拓扑专项检查存在失败项。');
    function [status,values]=evaluate(entry,input)
        pin.Value=input;pout.Value=zeros(128,1);
        [status,~,values]=calllib(alias,entry,pin,pout,ep);
    end
end
