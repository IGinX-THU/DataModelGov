function output=sht_tc27_replay(action,cfg,engine,data,schedule,options)
%SHT_TC27_REPLAY 三部件测量驱动的精确气热求值核。
% points: 稳态路径同时求轴速和热平衡；瞬态时刻固定实测轴速，仅求热平衡。
% history: 首点实测轴速，默认0.1s状态积分（可显式0.025s），正向传感器动态。
% engine由调用方持有，同一优化过程中复用指针；各候选重新写入自己的曲线。
if nargin<6,options=struct();end
if ~isfield(options,'route'),options.route='transient_instant';end
if ~isfield(options,'transientHealth'),options.transientHealth=zeros(13,1);end
if ~isfield(options,'sensorDynamics'),options.sensorDynamics=true;end
sht_health_schedule_initialize_dll(engine,sht_tc27_schedule_profile(schedule),schedule.designHealth);
health=schedule.designHealth(:);health(59:71)=options.transientHealth;
switch lower(action)
    case 'points',output=local_points(cfg,engine,data,schedule,health,options);
    case 'history',output=local_history(cfg,engine,data,schedule,health,options);
    otherwise,error('TC27:Replay:Action','未知求值%s。',action);
end
end

function r=local_points(cfg,engine,data,schedule,health,o)
n=height(data);values=nan(n,11);axes=nan(n,7);states=nan(n,numel(cfg.engine.initial.state));
valid=false(n,1);messages=strings(n,1);residual=nan(n,1);seeds=nan(n,6);
equilibriumDetails=cell(n,1);
thermalReferences=cell(n,1);
returnReference=isfield(o,'returnThermalReference')&&o.returnThermalReference;
reuseRequested=isfield(o,'thermalReferences')&&~isempty(o.thermalReferences);
if reuseRequested
    assert(strcmp(o.route,'transient_instant')&&numel(o.thermalReferences)==n, ...
        'TC27:Replay:ThermalReuse','参考必须逐点匹配瞬态时刻路径。');
end
for j=1:n
    point=data(j,:);b=local_boundary(cfg,point,health,true);wf=local_fuel(point.Wf_mean,schedule.fuelBias);
    x=cfg.engine.initial.state;x(1:2)=[point.Np_mean;point.Ng_mean];
    if isfield(cfg.engine,'tc27ReferenceEquilibria')
        ref=cfg.engine.tc27ReferenceEquilibria;
        distance=cellfun(@(e)((e.state(1)-x(1))/20900)^2+((e.state(2)-x(2))/38000)^2,ref);
        [~,nearest]=min(distance);x(3:end)=ref{nearest}.state(3:end);
        if isfield(ref{nearest},'commonWorkingSeed'),sht_tc27_reset_gas_seed(engine,ref{nearest}.commonWorkingSeed);end
    end
    if isfield(o,'initialStates') && size(o.initialStates,1)==n && all(isfinite(o.initialStates(j,:)))
        x=o.initialStates(j,:).';
        if strcmp(o.route,'transient_instant'),x(1:2)=[point.Np_mean;point.Ng_mean];end
    end
    if isfield(o,'commonWorkingSeed') && size(o.commonWorkingSeed,1)==n && all(isfinite(o.commonWorkingSeed(j,:)))
        sht_tc27_reset_gas_seed(engine,o.commonWorkingSeed(j,:));
    end
    try
        mode='thermal_only';bounds=[5000,70000;5000,70000];
        if strcmp(o.route,'steady')
            mode='steady_predict';center=point.Np_mean;
            if ismember('Np_branch_center_rpm',point.Properties.VariableNames) && isfinite(point.Np_branch_center_rpm)
                center=point.Np_branch_center_rpm;x(1)=center;
                bounds(1,:)=[point.Np_branch_lower_rpm,point.Np_branch_upper_rpm];
            elseif isfield(o,'independentPrediction') && o.independentPrediction
                % 测試工况的实测Np不可用于分支裁剪；域外以中性模型初值求解。
                x(1)=cfg.engine.initial.state(1);
            else,bounds(1,:)=[.88,1.12]*center;end
        end
        retries=0;if strcmp(o.route,'steady'),retries=2;end
        solveOptions=struct( ...
            'maximumIterations',20,'maximumCommonWorkRetries',retries, ...
            'finalJacobianAudit',false,'speedBounds_rpm',bounds);
        if reuseRequested && ~isempty(o.thermalReferences{j})
            e=sht_tc27_thermal_reuse(engine,x,wf,b,o.thermalReferences{j},solveOptions);
        else
            e=sht_thermal_equilibrium_solve(engine,x,wf,b,mode,solveOptions);
        end
        if returnReference && e.physicalValid && strcmp(mode,'thermal_only')
            % 一次性形成参考分解。矩阵及归一化尺度在本次UQ中冻结。
            if rcond(e.jacobian)>1e-12
                [L,U,P]=lu(e.jacobian);e.reuseFactor=struct('L',L,'U',U,'P',P);
                thermalReferences{j}=e;
            end
        end
        valid(j)=e.physicalValid;messages(j)=e.stopReason;residual(j)=e.finalCommonWorkResidual;
        equilibriumDetails{j}=struct('shaftDerivative_rpmps',e.derivative(1:2), ...
            'maxThermalDerivative_Kps',e.finalMaximumThermalDerivative_Kps, ...
            'remainingCorrection',e.remainingCorrection,'iterationCount',e.iterationCount, ...
            'history',e.history,'evaluationCount',e.evaluationCount);
        if isfield(e,'reuse'),equilibriumDetails{j}.reuse=e.reuse;end
        [values(j,:),axes(j,:)]=local_values(e.output,e.derivative);states(j,:)=e.state.';
        seeds(j,:)=double(engine.callContext.engPtr.eng.varIte(1:6));
    catch failure
        messages(j)=string(failure.message);
    end
end
r=struct('prediction',array2table(values,'VariableNames',local_names()), ...
    'coordinates',array2table(axes,'VariableNames',local_axes()),'states',states, ...
    'valid',valid,'messages',messages,'maxResidual',residual);
r.commonWorkingSeed=seeds;
r.equilibriumDetails=equilibriumDetails;
if returnReference,r.thermalReferences=thermalReferences;end
r.prediction.point_id=data.point_id;
end

function r=local_history(cfg,engine,t,schedule,health,o)
% 记录周期与积分步长分开。步长对照不改测量数据，也不暗中子步细分。
if ~isfield(o,'integrationStep_s'),o.integrationStep_s=.1;end
dtModel=o.integrationStep_s;
assert(isscalar(dtModel)&&isfinite(dtModel)&&dtModel>0,'积分步长必须为有限正数。');
recordTime=t.Time_s(:);time=(recordTime(1):dtModel:recordTime(end)).';
recordStep=median(diff(recordTime));
assert(all(isfinite(t{:,{'Pt1','Tt1','Pamb','Tamb','Altitude','Mach','Mkp','Wf'}}),'all')&& ...
    all(diff(recordTime)>0)&&max(abs(diff(recordTime)-recordStep))<1e-7, ...
    'TC27:Replay:Discontinuous','回放不得跨过无效输入或缺测，请先形成连续记录块。');
assert(abs(time(end)-recordTime(end))<1e-8,'历程时长必须对齐积分步长。');
index=round((recordTime-recordTime(1))/dtModel)+1;
assert(all(index>=1&index<=numel(time))&&max(abs(time(index)-recordTime))<1e-8, ...
    '所有测量时刻必须落在积分网格上；不得静默舍入或丢弃测量记录。');
inputs={'Pt1','Tt1','Pamb','Tamb','Altitude','Mach','Mkp','Wf'};
u=interp1(recordTime,t{:,inputs},time,'linear');
fuel=local_fuel(u(:,8),schedule.fuelBias);x=cfg.engine.initial.state;x(1:2)=[t.Np(1);t.Ng(1)];
if isfield(cfg.engine,'tc27ReferenceEquilibria')
    ref=cfg.engine.tc27ReferenceEquilibria;
    distance=cellfun(@(q)((q.state(1)-x(1))/20900)^2+((q.state(2)-x(2))/38000)^2,ref);
    [~,nearest]=min(distance);x(3:end)=ref{nearest}.state(3:end);
    if isfield(ref{nearest},'commonWorkingSeed'),sht_tc27_reset_gas_seed(engine,ref{nearest}.commonWorkingSeed);end
end
b=local_boundary(cfg,t(1,:),health,false);
if isfield(o,'initialWorkingSeed')
    % 局部准备状态复用专项：共同工作猜值也恢复到同一断点，避免候选顺序影响。
    sht_tc27_reset_gas_seed(engine,o.initialWorkingSeed);
end
initialPolicy='model_equilibrium_at_measured_initial_speed';
initialEvaluations=0;
if isfield(o,'initialState')
    % 显式断点用于同轮Jacobian准备状态复用，也用于初态扰动短测。
    % 是否采用冻结准备近似由上层求解记录，不能仅凭本字段判定用途。
    x=o.initialState(:);assert(numel(x)==numel(cfg.engine.initial.state)&&all(isfinite(x)),'子历程初状态无效。');
    initialPolicy='explicit_initial_state';
else
    e=sht_thermal_equilibrium_solve(engine,x,fuel(1),b,'thermal_only', ...
        struct('maximumIterations',20,'finalJacobianAudit',false));
    assert(e.physicalValid,'TC27:Replay:InitialThermal','首点热状态求解失败。');x=e.state;
    initialEvaluations=e.evaluationCount;
end
values=zeros(numel(time),11);states=zeros(numel(time),numel(x));maxResidual=0;
returnSeeds=isfield(o,'returnWorkingSeeds')&&o.returnWorkingSeeds;
if returnSeeds,workingSeeds=zeros(numel(time),6);end
coordinateBounds=[inf(1,7);-inf(1,7)];
for k=1:numel(time)
    b=local_interpolated_boundary(cfg,u(k,:),health);
    [d,y,di]=sht_engine_derivative(engine,x,fuel(k),b);local_check(d,di,time(k),x);
    [values(k,:),coordinate]=local_values(y,d);states(k,:)=x.';maxResidual=max(maxResidual,di.maxErr);
    if returnSeeds,workingSeeds(k,:)=double(engine.callContext.engPtr.eng.varIte(1:6));end
    coordinateBounds=[min(coordinateBounds(1,:),coordinate);max(coordinateBounds(2,:),coordinate)];
    if k==numel(time),break;end
    dt=time(k+1)-time(k);xp=x+dt*d;
    bp=local_interpolated_boundary(cfg,u(k+1,:),health);
    [dp,yp,dip]=sht_engine_derivative(engine,xp,fuel(k+1),bp);local_check(dp,dip,time(k+1),xp);
    [~,coordinate]=local_values(yp,dp);
    coordinateBounds=[min(coordinateBounds(1,:),coordinate);max(coordinateBounds(2,:),coordinate)];
    x=x+.5*dt*(d+dp);
end
% 传感器动态后叠加未知偏置属于似然/辨识参数；这里不读取造数实际误差。
sensor=values;spec=sht_tc24_measurement_specification();names=local_names();
if o.sensorDynamics
    for j=1:8
        q=find(spec.name==string(names{j}),1);tau=spec.timeConstant_s(q);
        % 初始记录可直接初始化观测状态，不对后续输出作逆补偿。
        if ismember(names{j},t.Properties.VariableNames),sensor(1,j)=t.(names{j})(1);end
        if isfield(o,'initialSensorState')
            assert(numel(o.initialSensorState)==8&&all(isfinite(o.initialSensorState)), ...
                'TC27:Replay:SensorRestart','传感器断点状态必须为八维有限数值。');
            sensor(1,j)=o.initialSensorState(j);
        end
        [a,beta,gamma]=sht_first_order_foh_coefficients(dtModel,tau);
        for k=2:numel(time),sensor(k,j)=a*sensor(k-1,j)+beta*values(k-1,j)+gamma*values(k,j);end
    end
end
r=struct('time',recordTime,'prediction',array2table(sensor(index,:),'VariableNames',names), ...
    'physicalPrediction',array2table(values(index,:),'VariableNames',names), ...
    'states',states(index,:),'valid',true,'maxResidual',maxResidual, ...
    'initialThermalPolicy',initialPolicy, ...
    'integrationStep_s',dtModel,'sensorDynamics',o.sensorDynamics, ...
    'integrationIntervalCount',numel(time)-1,'integrationDerivativeCalls',2*numel(time)-1);
r.coordinateBounds=array2table(coordinateBounds,'VariableNames',local_axes());
r.fuelCoordinateBounds=[min(t.Wf),max(t.Wf)]/schedule.fuelBias.wfDesign;
r.initialThermalEvaluationCount=initialEvaluations;
r.dllEvaluationCount=initialEvaluations+r.integrationDerivativeCalls;
if returnSeeds,r.workingSeeds=workingSeeds(index,:);end
end

function b=local_boundary(cfg,t,health,means)
if means,suffix='_mean';else,suffix='';end
fields={'Pt1','Tt1','Pamb','Tamb','Altitude','Mach','Mkp','Wf'};u=zeros(1,8);
for j=1:8,u(j)=t.([fields{j},suffix]);end
b=local_interpolated_boundary(cfg,u,health);
end
function b=local_interpolated_boundary(cfg,u,health)
b=cfg.engine.boundary;b.inletBoundaryMode=1;b.Pt1=u(1);b.Tt1=u(2);b.Pamb=u(3);
b.Tamb=u(4);b.altitude=u(5);b.Mach=u(6);b.Mkp=u(7);b.Mkg=0;
b.ptLoadInputMode='torque';b.gtLoadInputMode='torque';b.health=health;b.healthScheduleEnabled=1;
end
function wf=local_fuel(measured,bias)
x=measured/bias.wfDesign;
if numel(bias.xNodes)==1,b=repmat(bias.biasNodes,size(x));
else,b=interp1(bias.xNodes,bias.biasNodes,min(max(x,min(bias.xNodes)),max(bias.xNodes)),'linear');end
wf=measured-b;assert(all(wf>0),'TC27:Replay:Fuel','偏置导致非正燃油。');
end
function [v,a]=local_values(y,d)
v=[y.Np,y.Ng,y.Pt3,y.Tt3,y.Pt45,y.Tt45,y.Pt5,y.Tt5,y.WIn,d(1),d(2)];
names=local_axes();a=zeros(1,numel(names));for j=1:numel(names),a(j)=y.(names{j});end
end
function n=local_names()
n={'Np','Ng','Ptb3','Ttb3','Pt45','Tt45','Pt6','Tt6','Wa2','dNp_dt','dNg_dt'};
end
function n=local_axes()
n={'inlet_corrected_mass_flow','burner_inlet_corrected_mass_flow', ...
    'gt_pt_duct_corrected_mass_flow','pt_nozzle_duct_corrected_mass_flow', ...
    'ac_corrected_speed','gt_total_pressure_ratio','pt_total_pressure_ratio'};
end
function local_check(d,diagnostic,time,state)
assert(all(isfinite(d))&&diagnostic.ret==0&&diagnostic.convergeTag==0&&diagnostic.maxErr<1e-5, ...
    'TC27:Replay:ModelFailure','t=%.3f模型求值失败，Np=%.6f rpm，Ng=%.6f rpm，ret=%g，收敛标志=%g，残差%g。', ...
    time,state(1),state(2),diagnostic.ret,diagnostic.convergeTag,diagnostic.maxErr);
end
