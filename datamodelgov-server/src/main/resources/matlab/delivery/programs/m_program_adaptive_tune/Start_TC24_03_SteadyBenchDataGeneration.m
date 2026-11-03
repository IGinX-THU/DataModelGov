function result = Start_TC24_03_SteadyBenchDataGeneration(options)
%START_TC24_03_STEADYBENCHDATAGENERATION TC24-STEP04，12训练点及4测试点。
% 正式Excel只有编号、实际有效记录数sample_count和测量均值。全历程、偏置实现和健康真值
% 单独保存在MiddleData/three_component，辨识入口不得读取这些验证资产。
% 0.025s仿真、0.1s记录；完整有效段全部参与均值，不再二次截尾。
% 默认每点0~20s共201条记录，正式Excel仍为每工况一行。
if nargin<1, options=struct(); end
if ~isfield(options,'pointIds'), options.pointIds=strings(0,1); end
if ~isfield(options,'stopTime'), options.stopTime=20; end
if ~isfield(options,'publish'), options.publish=isempty(options.pointIds); end
validateattributes(options.publish,{'logical','numeric'},{'scalar','binary'});
validateattributes(options.stopTime,{'numeric'},{'scalar','finite','>=',5});
sampling=sht_data_sampling_specification();
assert(abs(options.stopTime/sampling.sampleInterval_s-round(options.stopTime/sampling.sampleInterval_s))<1e-8, ...
    'TC24:Generation:StopAlignment','stopTime必须是0.1s的整数倍。');
sampling=sht_data_sampling_specification((0:sampling.simulationStep_s:options.stopTime).');
root=fileparts(mfilename('fullpath'));
out=fullfile(fileparts(root),'report_outputs','three_component', ...
    ['TC24_STEP04_',datestr(now,'yyyymmdd_HHMMSS')]);
mkdir(out);
middle=fullfile(root,'MiddleData','three_component');
% 非发布复现也必须隔离检查点，不能覆盖正式造数的恢复位置。
checkpointFile=fullfile(middle,'tc24_generation_checkpoint.mat');
if ~options.publish
    [~,runLeaf]=fileparts(out);
    checkpointDir=fullfile(middle,'generation_checks',runLeaf);
    if ~isfolder(checkpointDir),mkdir(checkpointDir);end
    checkpointFile=fullfile(checkpointDir,'checkpoint.mat');
end
source=load(fullfile(middle,'three_component_health_schedule_latest.mat'));
assert(isfield(source,'profile'),'调度资产缺少profile。');
profile=source.profile;
package=sht_tc24_runtime_package();
cfg=sht_default_config(struct('engine',struct('modelMode',0, ...
    'runtimeDirectory',package.directory),'plot',struct('enable',false)));
cfg.Tsim=sampling.simulationStep_s;
cfg.engine.boundary.health=profile.truthVectorAtDesign;
cfg.engine.boundary.healthScheduleEnabled=true;
cfg.engine.healthScheduleProfile=profile;
cfg.engine.boundary.inletBoundaryMode=2;
cfg.engine.boundary.altitude=0; cfg.engine.boundary.Mach=0;
cfg.engine.boundary.Pamb=101325; cfg.engine.boundary.Tamb=288.15;
cfg.engine.boundary.deltaTemperature=0;
spec=sht_tc24_measurement_specification();
allPoints=sht_tc24_operating_points();points=allPoints;
if ~isempty(options.pointIds), points=points(ismember(points.point_id,string(options.pointIds)),:); end
assert(height(points)>0,'未选择有效工况。');
% Wa1/Wb尚无实机标定资料：以下仅为可复现软件试验假设。
meter=struct('scavengeFraction',.05,'area_m2',.08,'areaBiasFraction',.005, ...
    'staticPressureBias_Pa',-10,'staticPressureNoiseStd_Pa',4, ...
    'blowerBiasFraction',.02,'blowerNoiseStdFraction',.005, ...
    'description','工程模拟计量配置，不是本机真实标定');
fprintf('TC24: modelMode=0, Np0=20900 rpm, altitude=0 m, Mach=0.\n');
fprintf('Simulation %.3f s; recording %.3f s (%g Hz); full %g s record = %d mean samples.\n', ...
    sampling.simulationStep_s,sampling.sampleInterval_s,sampling.sampleRate_Hz, ...
    sampling.recordDuration_s,sampling.recordSampleCount);
fprintf('模拟计量：Wb/Wa1=%.3f，A=%.3f m2；不计算鼓风机耗功。\n', ...
    meter.scavengeFraction,meter.area_m2);
disp(spec);
writetable(spec,fullfile(out,'measurement_specification.csv'));
n=height(points); histories=cell(n,1); trims=cell(n,1); measured=table(); truth=table();
timer=tic;
for i=1:n
    point=points(i,:);
    % 单点重放与全批次使用同一种子，不让筛选后的行号改变误差实现。
    seedIndex=find(allPoints.point_id==point.point_id,1);
    trim=sht_trim_health_steady_point(cfg,point.Np_rpm,1000*point.load_power_kW,profile.truthVectorAtDesign);
    trims{i}=trim;
    sim=local_sim_config(cfg,point,trim,spec,options.stopTime,seedIndex);
    run=sht_simulate_control_m(sim);
    l=run.log; simulationMask=true(size(l.time));
    assert(all(isfinite(l.Np)) && max(l.maxErr)<1e-5, ...
        'TC24:Generation:InvalidReplay','%s闭环气路不收敛，max|r|=%g。',point.point_id,max(l.maxErr));
    assert(max(l.Np(simulationMask))-min(l.Np(simulationMask))<.001*20900 && ...
        max(l.Ng(simulationMask))-min(l.Ng(simulationMask))<.001*38000, ...
        'TC24:Generation:NotSteady','%s完整有效段转速不平稳：Np峰峰值%g rpm，Ng峰峰值%g rpm；不得静默截尾发布。', ...
        point.point_id,max(l.Np)-min(l.Np),max(l.Ng)-min(l.Ng));
    [fullTruth,fullMeasured,fullBias]=local_measurements(l,spec,meter,seedIndex,sim);
    [~,sampleIndex]=sht_data_sampling_specification(l.time);
    sampleTime=l.time(sampleIndex);
    mask=true(size(sampleTime));
    assert(nnz(mask)==sampling.recordSampleCount,'TC24:Generation:WindowCount', ...
        '完整有效段记录数与本次采样配置不符。');
    % 先完成原40Hz测量和闭环，再选取同一时刻的真值、测量和偏置。
    % 保存高频诊断副本用于回归，绝不能用它替代10Hz交付均值。
    t=local_select_samples(fullTruth,sampleIndex);
    m=local_select_samples(fullMeasured,sampleIndex);
    bias=local_select_samples(fullBias,sampleIndex);
    simulation=struct('time',l.time,'windowMask',simulationMask, ...
        'truth',fullTruth,'measured',fullMeasured,'bias',fullBias);
    histories{i}=struct('point_id',point.point_id,'time',sampleTime,'windowMask',mask, ...
        'truth',t,'measured',m,'bias',bias,'log',l,'configuration',sim, ...
        'sampleIndex',sampleIndex,'sampling',sampling,'simulation',simulation);
    tr=table(point.point_id,'VariableNames',{'point_id'});
    mr=table(point.point_id,nnz(mask),'VariableNames',{'point_id','sample_count'});
    fields=fieldnames(m);
    for j=1:numel(fields)
        field=fields{j}; mr.([field,'_mean'])=mean(m.(field)(mask));
        tr.([field,'_mean'])=mean(t.(field)(mask));
    end
    measured=[measured;mr]; truth=[truth;tr]; %#ok<AGROW>
    assert(max(abs(t.Wa1-t.Wb-l.WIn(sampleIndex)))<1e-12,'Wa1-Wb质量守恒失败。');
    assert(max(abs(l.Deta-l.samplePt1/101325))<1e-12,'Pt1测量未进入闭环Deta。');
    fprintf('%s: Np %.2f rpm, Ng %.2f rpm, Wf %.8f kg/s, P %.2f kW, elapsed %.1f s\n', ...
        point.point_id,mr.Np_mean,mr.Ng_mean,mr.Wf_mean,mr.Pshaft_mean/1000,toc(timer));
    save(checkpointFile,'histories','trims','measured','truth','points','options','package','-v7.3');
end
result=struct('schema','TC24_MEASURED_BENCH_V4_POINT_COUNTS','modelMode',0,'points',points, ...
    'measurement',measured,'truth',truth,'histories',{histories},'trims',{trims}, ...
    'specification',spec,'meterAssumption',meter,'profile',profile,'sampling',sampling, ...
    'elapsedSeconds',toc(timer),'reportDirectory',out);
result.checkpointFile=checkpointFile;
result.runtimePackage=package;
save(fullfile(out,'generation_result.mat'),'result','-v7.3');
if options.publish
    assert(sum(points.set_name=="train")==12 && sum(points.set_name=="test")==4,'完整发布须12+4点。');
    target=fullfile(root,'TestData','three_component'); if ~isfolder(target),mkdir(target);end
    result.trainingFile=fullfile(target,'tc24_training_means.xlsx');
    result.testFile=fullfile(target,'tc24_test_means.xlsx');
    writetable(measured(points.set_name=="train",:),result.trainingFile);
    writetable(measured(points.set_name=="test",:),result.testFile);
    save(fullfile(middle,'tc24_bench_latest.mat'),'result','-v7.3');
end
writetable(measured,fullfile(out,'measurement_means.csv'));
writetable(truth,fullfile(out,'validation_truth_means.csv'));
local_plot(result);
end

function sampled=local_select_samples(full,index)
sampled=struct();names=fieldnames(full);
for k=1:numel(names)
    sampled.(names{k})=full.(names{k})(index);
end
end

function sim=local_sim_config(cfg,p,trim,spec,stopTime,index)
sim=cfg; sim.stopTime=stopTime; sim.throwOnEngineNonconvergence=true;
sim.engine.initial.state=[trim.Np;trim.Ng];
sim.engine.initial.Np0=trim.Np; sim.engine.initial.Ng0=trim.Ng;
sim.engine.initial.Wf0=trim.Wf; sim.engine.initial.power0=p.load_power_kW*1000;
sim.engine.initial.commonWorkingSeed=trim.varIte;
% 控制器和执行机构也从本工况配平值启动，不能沿用设计点燃油初值。
sim.controller.initial.Np=trim.Np;sim.controller.initial.Ng=trim.Ng;
sim.controller.initial.Wf=trim.Wf;sim.actuator.initialWf=trim.Wf;
sim.engine.boundary.ptLoadInputMode='torque'; sim.engine.boundary.gtLoadInputMode='torque';
sim.engine.boundary.Mkp=p.target_torque_Nm;sim.engine.boundary.Mkg=0;
sim.engine.boundary.power=p.load_power_kW*1000;sim.engine.boundary.hpsPower=0;
sim.reference.baseNp=p.Np_rpm;sim.reference.baseNg=trim.Ng;
sim.reference.npPulseAmplitude=0;sim.reference.enablePowerPulse=false;
sim.reference.powerBase=p.load_power_kW*1000;sim.reference.powerPulseAmplitude=0;
if isfield(sim.reference,'commandMode'),sim.reference=rmfield(sim.reference,'commandMode');end
rotor=struct('enabled',true,'collectivePitchMapping',struct( ...
    'thetaZeroDeg',0,'thetaDesignDeg',12,'profileTorqueFraction',.15));
rotor.designNpRpm=20900;rotor.designPowerW=2176600;
rotor.designTorqueNm=2176600/(20900*pi/30);
% 使用既有负载模型字段；theta下限只针对本次已确认的低负载工况放宽。
rotor.collectivePitchMapping.thetaValidRangeDeg=[5,14];
if p.load_connected
    rotor.inputMode='collectivePitch';
    sim.reference.collectivePitch=struct('enabled',true,'commandMode','schedule', ...
        'scheduleTime_s',[0,stopTime],'scheduleTheta_deg',[p.theta_deg,p.theta_deg], ...
        'interpolationMethod','previous');
else
    rotor.inputMode='directTorque';rotor.directTorqueCommandNm=p.target_torque_Nm;
    sim.engine.boundary.ptShaftInertiaFactor=.25;
    % 同一动力学下b11与Np等效惯量成反比，调速器也应使用脱开后的增益。
    sim.controller.gainSchedule.b11=sim.controller.gainSchedule.b11/.25;
    sim.controller.linearModel.b11=sim.controller.linearModel.b11/.25;
    sim.reference.collectivePitch=struct('enabled',false);
end
sim.flight.rotorLoad=rotor;
sim.sensor.mode='firstOrder';sim.sensor.pressureChannel='Pt1';
sim.sensor.channels{8}='Pt1'; sim.sensor.randomSeed=20260908+index*101;
sim.sensor.biasModel=struct('enabled',false);
sim.sensor.bias=zeros(23,1);sim.sensor.noiseStd=zeros(23,1);sim.sensor.timeConstant=zeros(23,1);
for j=1:23
    channel=sim.sensor.channels{j};
    if strcmp(channel,'T45'),channel='Tt45';end
    if strcmp(channel,'Pt3'),channel='Ptb3';end
    if strcmp(channel,'Tt3'),channel='Ttb3';end
    if strcmp(channel,'Pt5'),channel='Pt6';end
    if strcmp(channel,'Tt5'),channel='Tt6';end
    k=find(spec.name==channel,1);
    if isempty(k),continue;end
    sim.sensor.bias(j)=local_bias(spec(k,:),trim.scheduleCoordinates.inlet_corrected_mass_flow);
    sim.sensor.noiseStd(j)=spec.noiseStd(k);sim.sensor.timeConstant(j)=spec.timeConstant_s(k);
end
end

function b=local_bias(row,flow)
% 偏置真值仅造数侧使用。Wf/Ttb3/Tt45保留随流量的10%范围漂移。
f=min(max((6.7114-flow)/(6.7114-2.1803),0),1);
signs=struct('Np',.3,'Ng',-.35,'Wf',.7,'Mkp',.7,'Pt1',-.4,'Tt1',.7, ...
    'Ptb3',.7,'Ttb3',-.7,'Pt45',-.7,'Tt45',-.7,'Pt6',-.5,'Tt6',-.6, ...
    'Pamb',-.7,'Tamb',.7,'Altitude',1,'Mach',0,'RH',.5);
b=row.biasHalfWidth*signs.(char(row.name));
if row.name=="Wf",b=b+.1*row.biasHalfWidth*f;end
if ismember(row.name,["Ttb3","Tt45"]),b=b-.1*row.biasHalfWidth*f;end
end

function [t,m,bias]=local_measurements(l,spec,meter,index,sim)
names=cellstr(spec.name); sources={'Np','Ng','Wf','Mkp','Pt1','Tt1','Pt3','Tt3', ...
    'Pt45','Tt45','Pt5','Tt5','Pamb','Tamb','Altitude','Mach','RH'};
samples={'sampleNp','sampleNg','','sampleMkp','samplePt1','sampleTt1', ...
    'samplePt3','sampleTt3','samplePt45','sampleTt45','samplePt5','sampleT5', ...
    'samplePamb','sampleTamb','sampleAltitude','sampleMach',''};
rng(20260908+index*101+500000,'twister');
n=numel(l.time);t=struct();m=struct();bias=struct();
for j=1:numel(names)
    name=names{j};
    if strcmp(name,'RH'), raw=60*ones(n,1);else,raw=l.(sources{j});end
    if strcmp(name,'Mach'),raw=zeros(n,1);end
    t.(name)=raw;
    b=arrayfun(@(w)local_bias(spec(j,:),w),l.WIn);
    bias.(name)=b;
    if isempty(samples{j})
        filtered=local_filter(l.time,raw,spec.timeConstant_s(j));
        m.(name)=filtered+b+spec.noiseStd(j)*randn(n,1);
    else
        m.(name)=l.(samples{j});
        % 这些通道已在控制闭环注入偏置，不再记录另一套随瞬时流量计算的值。
        sensorIndex=find(strcmp(sim.sensor.channels,sources{j}),1);
        if strcmp(name,'Pt1'),sensorIndex=8;end
        if strcmp(name,'Tt6'),sensorIndex=find(strcmp(sim.sensor.channels,'Tt5'),1);end
        if isempty(sensorIndex) && strcmp(name,'Tt45')
            sensorIndex=find(strcmp(sim.sensor.channels,'T45'),1);
        end
        assert(~isempty(sensorIndex),'TC24:Generation:BiasIndex','无法追溯%s的闭环偏置。',name);
        bias.(name)=repmat(sim.sensor.bias(sensorIndex),n,1);
    end
end
t.Wa1=l.WIn/(1-meter.scavengeFraction);t.Wb=t.Wa1-l.WIn;
% 用等熵低速计量截面关系得到静压，然后使用同一时刻测量Pt1/Tt1
% 反算Wa1，共同误差由此自然保留。飞行Mach=0不代替计量截面Mach。
gamma=1.4;R=287.05;A=meter.area_m2;
mach=zeros(n,1);
for k=1:n
    q=t.Wa1(k)*sqrt(t.Tt1(k))/(A*t.Pt1(k)*sqrt(gamma/R));
    mach(k)=fzero(@(v)v*(1+.2*v*v)^(-3)-q,[0,.9]);
end
ps=t.Pt1./(1+.2*mach.^2).^3.5;
psm=ps+meter.staticPressureBias_Pa+meter.staticPressureNoiseStd_Pa*randn(n,1);
mm=sqrt(max(0,5*((m.Pt1./psm).^(2/7)-1)));
m.Wa1=A*(1+meter.areaBiasFraction)*m.Pt1.*sqrt(gamma./(R*m.Tt1)).*mm./(1+.2*mm.^2).^3;
m.Wb=t.Wb*(1+meter.blowerBiasFraction)+meter.blowerNoiseStdFraction*t.Wb.*randn(n,1);
t.Pshaft=t.Mkp.*t.Np*pi/30;m.Pshaft=m.Mkp.*m.Np*pi/30;
% 未建模的鼓风机出口/局部单点温压显式缺省，不复制测量耙代表值。
for name={'Pt3','Tt3','Pt13','Tt13'}
    t.(name{1})=nan(n,1);m.(name{1})=nan(n,1);
end
end

function y=local_filter(t,u,tau)
y=u;
for k=2:numel(t)
    [a,b,c]=sht_first_order_foh_coefficients(t(k)-t(k-1),tau);
    y(k)=a*y(k-1)+b*u(k-1)+c*u(k);
end
end

function local_plot(result)
f=figure('Visible','off','Position',[100,100,1100,750]);
names={'Np','Ng','Wf','Tt45','Pshaft','Wa1'};
for j=1:6
    subplot(3,2,j);hold on;
    plot(result.truth.([names{j},'_mean']),'k-o');
    plot(result.measurement.([names{j},'_mean']),'r-x');
    ylabel(names{j},'Interpreter','none');xlabel('Point index');grid on;
end
legend('Truth','Measured');
print(f,fullfile(result.reportDirectory,'measurement_comparison.png'),'-dpng','-r150');close(f);
end
