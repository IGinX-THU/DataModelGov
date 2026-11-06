function [cfg,trim]=sht_tc27_simulation_config(m,thermalMode,health,schedule,measurementEnabled,seed)
%SHT_TC27_SIMULATION_CONFIG 在本次健康、负载和热配置下独立配平。
% 不把旧六部件温度、转速或共同工作解当作三部件初值。
if nargin<6,seed=20260910;end
if nargin<5,measurementEnabled=false;end
if nargin<4,schedule=[];end
if nargin<3,health=zeros(159,1);end
cfg=sht_tc27_config(thermalMode);cfg.engine.health=health(:);
cfg.engine.boundary.health=health(:);
if ~isempty(schedule)
    cfg.engine.healthScheduleProfile=schedule;cfg.engine.boundary.healthScheduleEnabled=1;
end
nominal=cfg;nominal.engine.transientEffects.enabled=false;
nominal.engine.initial.state=nominal.engine.initial.state(1:2);
trim=sht_trim_health_steady_point(nominal,20900*m.Npr(1),m.power_W(1),health);
state=[trim.Np;trim.Ng];wf=trim.Wf;
cfg.engine.boundary.ptLoadInputMode='torque';cfg.engine.boundary.gtLoadInputMode='torque';
cfg.engine.boundary.Mkp=m.power_W(1)/(trim.Np*pi/30);cfg.engine.boundary.Mkg=0;
cfg.engine.boundary.power=m.power_W(1);cfg.engine.boundary.hpsPower=0;
if thermalMode~=0
    engine=sht_engine_open(cfg.engine);cleanup=onCleanup(@()sht_engine_close(engine));
    state=[state;cfg.engine.initial.state(3:end)];
    e=sht_thermal_equilibrium_solve(engine,state,wf,cfg.engine.boundary,'trim_fixed_np', ...
        struct('maximumIterations',40,'verbose',false,'finalJacobianAudit',false));
    assert(e.physicalValid,'TC27:Simulation:Trim','气热初值未收敛：%s',e.stopReason);
    state=e.state;wf=e.fuelFlow_kgps;trim.thermal=e;clear cleanup;
end
cfg.stopTime=m.duration_s;cfg.throwOnEngineNonconvergence=true;
cfg.engine.initial.state=state;cfg.engine.initial.Np0=state(1);cfg.engine.initial.Ng0=state(2);
cfg.engine.initial.Wf0=wf;cfg.engine.initial.power0=m.power_W(1);
cfg.engine.initial.commonWorkingSeed=trim.varIte;
cfg.controller.initial.Np=state(1);cfg.controller.initial.Ng=state(2);
cfg.controller.initial.Wf=wf;cfg.actuator.initialWf=wf;
cfg.reference.commandMode='schedule';cfg.reference.baseNp=state(1);
cfg.reference.baseNg=state(2);cfg.reference.powerBase=m.power_W(1);
cfg.reference.scheduleTime_s=m.time;cfg.reference.scheduleNp_rpm=20900*m.Npr;
cfg.reference.schedulePower_W=m.power_W;
cfg.reference.collectivePitch=struct('enabled',true,'commandMode','schedule', ...
    'scheduleTime_s',m.time,'scheduleTheta_deg',m.theta_deg,'interpolationMethod','linear');
cfg.flight.rotorLoad=struct('enabled',true,'inputMode','collectivePitch', ...
    'designNpRpm',20900,'designPowerW',2176600,'designTorqueNm',2176600/(20900*pi/30), ...
    'collectivePitchMapping',struct('thetaZeroDeg',0,'thetaDesignDeg',12, ...
    'profileTorqueFraction',.15,'thetaValidRangeDeg',[0,14]));
cfg.sensor.mode='identity';cfg.sensor.pressureChannel='Pt1';cfg.sensor.channels{8}='Pt1';
cfg.sensor.randomSeed=seed;cfg.sensor.biasModel=struct('enabled',false);
cfg.sensor.bias=zeros(23,1);cfg.sensor.noiseStd=zeros(23,1);cfg.sensor.timeConstant=zeros(23,1);
if measurementEnabled
    cfg.sensor.mode='firstOrder';spec=sht_tc24_measurement_specification();
    for j=1:23
        name=string(cfg.sensor.channels{j});
        old=["T45","Pt3","Tt3","Pt5","Tt5"];new=["Tt45","Ptb3","Ttb3","Pt6","Tt6"];
        index=find(old==name,1);if ~isempty(index),name=new(index);end
        k=find(spec.name==name,1);if isempty(k),continue;end
        cfg.sensor.bias(j)=sht_tc27_measurements('bias',spec(k,:),trim.scheduleCoordinates.inlet_corrected_mass_flow);
        cfg.sensor.noiseStd(j)=spec.noiseStd(k);cfg.sensor.timeConstant(j)=spec.timeConstant_s(k);
    end
end
cfg=sht_validate_runtime_config(cfg);
end
