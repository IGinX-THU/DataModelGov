function varargout = sht_f33_thermal_equilibrium(action,varargin)
% 3.3稳态点的标称Visser热平衡适配器，不读取飞参生成真值。
% prepare只用先验连续预测转速确定物理解范围；温度不是历史边界。
% open/batch/close构成一次会话，缓存仅在本会话内有效，不跨合同复用。
switch lower(action)
    case 'prepare'
        varargout{1}=local_prepare(varargin{:});
    case 'open'
        varargout{1}=local_open(varargin{:});
    case 'batch'
        varargout{1}=local_batch(varargin{:});
    case 'close'
        % DLL由每次batch独占打开/关闭，会话只保存配置和数值缓存。
    otherwise
        error('SHT:F33Thermal:Action','未知操作：%s',action);
end
end

function branch=local_prepare(history,segments,points,assets,sensor,width,sourceHash,varargin)
p=fileparts(mfilename('fullpath'));
opts=struct('sourceSha256',sourceHash,'integrationMethod','euler2', ...
    'sensorDynamicsEnabled',true,'progressIntervalSamples',8000, ...
    'cacheDirectory',fullfile(p,'MiddleData','flight_model_adapt_3p3_v2', ...
    'thermal_branch_replay_cache'));
if isfield(assets,'modelMode')&&assets.modelMode==0
    paths=sht_f3_current_contract('paths');
    opts.cacheDirectory=fullfile(paths.middle,'thermal_branch_replay_cache');
end
if ~isempty(varargin)&&isfield(varargin{1},'integrationStep_s')&&~isfield(varargin{1},'time_s')
    opts.integrationStep_s=varargin{1}.integrationStep_s;
    if isfield(varargin{1},'cacheDirectory')
        opts.cacheDirectory=varargin{1}.cacheDirectory;
    end
    varargin={};
end
if isempty(varargin)
    names={'sample_id','time_s','Ps0','Tt1','Pt3_eq','Ng','Np', ...
        'Mkp','Mkg','Wf','Tt45','Altitude','Mach','Ts_amb'};
    replay=sht_f32_replay_history('run',history(:,names),assets,'personalized',sensor,opts);
else
    % 专项验证已按当前完整合同获得同一先验的全历程，可直接复用该对象。
    % 不读取其他历史运行结果；时间轴与实际测量输出必须逐值相同。
    replay=varargin{1};
    assert(numel(replay.time_s)==height(history) && ...
        all(abs(replay.time_s(:)-history.time_s(:))<=1e-9) && ...
        isequal(replay.measuredOutput,[history.Np,history.Ng,history.Pt3_eq,history.Tt45]), ...
        '当前全历程对象与待验证飞参不一致。');
end
assert(replay.computationallyAccepted,'先验连续预测不能提供有效物理解初猜。');
speeds=zeros(height(points),2);
for k=1:height(points)
    j=find(string(segments.segment_id)==points.point_id(k),1);
    assert(~isempty(j),'稳态点未找到对应测量窗口。');
    rows=round(segments.first(j)):round(segments.last(j));
    speeds(k,:)=mean(replay.state(rows,1:2),1);
end
branch=struct('pointIds',points.point_id,'speedSeed',speeds, ...
    'relativeHalfWidth',width,'lowerNp',speeds(:,1)*(1-width), ...
    'upperNp',speeds(:,1)*(1+width),'source','same_prior_continuous_prediction', ...
    'pointMeasuredSpeedUsed',false,'thermalHistoryUsed',false, ...
    'sourceHash',sourceHash,'replayCache',replay.cacheFile,'assetContract',assets.contract);
end

function session=local_open(assets,branch,points,varargin)
route='steady';if ~isempty(varargin),route=varargin{1};end
assert(ismember(route,{'steady','transient_instant'}),'未知热平衡模型路径。');
assert(isequal(branch.pointIds,points.point_id),'物理解范围与当前点集不一致。');
assert(~ismember('Pback_mean',points.Properties.VariableNames),'禁止输入不可测背压。');
if isfield(assets,'modelMode')&&assets.modelMode==0
    cfg=assets.configuration;
else
    cfg=sht_default_config(struct('engine',struct('modelMode',1)));
    cfg=sht_configure_transient_visser29(cfg,'joint_full',assets.paths.visserAsset);
    cfg.engine.reynoldsCorrection=sht_reynolds_correction_config(1);
end
cfg.engine.boundary.health=assets.personalized.health;
cfg.engine.boundary.health(90:112)=0;
priorSchedule=[];
if isfield(assets,'steadySchedule'),priorSchedule=assets.steadySchedule;end
fixed=[];
if numel(cfg.engine.initial.state)==16
    source='';
    if isfield(assets,'contract')&&isfield(assets.contract,'fixedTransient')
        source=assets.contract.fixedTransient.sourceSha256;
    end
    fixed=sht_f3_current_contract('fixedTransient',cfg.engine.boundary.health,source);
end
cfg.engine.boundary.healthScheduleEnabled=true;
cfg.engine.healthScheduleProfile=assets.personalized.profile;
session=struct('cfg',cfg,'branch',branch,'modelRoute',route,'priorSchedule',priorSchedule, ...
    'points',points,'fixedTransient',fixed, ...
    'cache',containers.Map('KeyType','char','ValueType','any'));
end

function batch=local_batch(session,schedules,recoveries,varargin)
% cache键包含全部调度、燃油偏置及进口恢复。其他物理配置与点集在会话中冻结。
% 可选温度初猜扰动只供独立重复测试，同时绕过缓存和已收敛初猜。
offset=0; if ~isempty(varargin),offset=varargin{1};end
empty=struct('prediction',table(),'valid',false,'diagnostic',struct());
candidate=repmat(empty,numel(schedules),1);
engine=[];engineCleanup=[]; %#ok<NASGU>
for i=1:numel(schedules)
    schedule=schedules{i};
    assert(all(schedule.designHealth(90:112)==0),'本轮不释放瞬态修正系数。');
    transientCount=23;transientStart=90;
    if numel(session.cfg.engine.initial.state)==16
        assert(isequal(schedule.designHealth(59:71),session.fixedTransient.value), ...
            'SHT:F33Thermal:FixedTransientChanged', ...
            '稳态候选不得改变所选组合父的13项固定瞬态参数。');
        transientCount=13;transientStart=59;
    end
    key=sht_f33_model_adapt_v2('structHash',struct('schedule',schedule, ...
        'recovery',recoveries(i)));
    if offset==0 && isKey(session.cache,key)
        candidate(i)=session.cache(key); continue;
    end
    if isempty(engine)
        % 同进程只能有一个GTESS实例。将所有库对象限制在本批求值内，
        % 返回后小幅历程或完整回放可以安全建立自己的调用上下文。
        engine=sht_engine_open(session.cfg.engine);
        engineCleanup=onCleanup(@()sht_engine_close(engine));
    end
    if numel(schedules)>1,fprintf('    热平衡候选 %d/%d：%d点\n',i,numel(schedules),height(session.points));end
    profile=sht_f33_model_adapt_v2('buildProfile',schedule);
    sht_health_schedule_initialize_dll(engine,profile,schedule.designHealth);
    records=cell(height(session.points),1); prediction=table();
    for k=1:height(session.points)
        point=session.points(k,:);
        b=session.cfg.engine.boundary; b.health=schedule.designHealth;
        b.inletBoundaryMode=5; b.altitude=point.Altitude_mean; b.Mach=point.Mach_mean;
        b.deltaTemperature=0; b.Ps0=point.Pamb_mean; b.Pamb=point.Pamb_mean;
        b.Ts_amb=point.Tamb_mean; b.Tamb=point.Tamb_mean; b.Tt1=point.Tt1_mean;
        b.inletTotalPressureRecovery=recoveries(i);
        b.Mkp=point.Mkp_mean; b.Mkg=point.Mkg_mean;
        b.ptLoadInputMode='torque'; b.gtLoadInputMode='torque';
        b.flightBoundaryEnabled=true;
        for field={'Pback','epsilonSSHeld'}
            if isfield(b,field{1}),b=rmfield(b,field{1});end
        end
        b.exhaustBackPressureModel=sht_f32_replay_history('backpressureModel');
        fuel=schedule.fuelBias;
        coordinate=point.Wf_mean/fuel.wfDesign;
        coordinate=min(max(coordinate,min(fuel.xNodes)),max(fuel.xNodes));
        bias=interp1(fuel.xNodes,fuel.biasNodes,coordinate,'linear');
        wf=point.Wf_mean-bias;
        assert(isfinite(wf)&&wf>0,'燃油偏置修正后物理流量无效。');
        state=session.cfg.engine.initial.state(:);
        state(1:2)=session.branch.speedSeed(k,:).';
        warmKey=sprintf('warm_point_%d',k);
        if offset==0 && isKey(session.cache,warmKey),state=session.cache(warmKey);end
        if strcmp(session.modelRoute,'transient_instant')
            % 两轴转速是本窗口的测量均值，只求其余温度状态的热平衡。
            % 三部件14个温度状态、六部件27个；轴加速度保留为输出。
            state(1:2)=[point.Np_mean;point.Ng_mean];
        end
        state(3:end)=state(3:end)+offset;
        bounds=[session.branch.lowerNp(k),session.branch.upperNp(k)];
        gasSeed=double(engine.callContext.engPtr.eng.varIte(1:6));
        try
        if numel(state)==16
            records{k}=local_three_solve(engine,state,wf,b,bounds,session,k,profile,offset);
        else
            records{k}=local_solve(engine,state,wf,b,bounds,session.modelRoute);
        end
        catch exception
            % 宽先验候选允许没有可计算的气热平衡；只捕获已知数值物理
            % 失败。配置、接口、字段及未知错误必须继续抛出，不能静默拒绝。
            known={'SHT:ThermalEquilibrium:PhysicalEvaluationFailed', ...
                'SHT:ThermalEquilibrium:DifferenceEvaluationFailed', ...
                'SHT:ThermalEquilibrium:RankDeficientJacobian'};
            if numel(state)~=16||~ismember(exception.identifier,known),rethrow(exception);end
            sht_tc27_reset_gas_seed(engine,gasSeed);
            names={'Np','Ng','Pt3','Tt45','inlet_corrected_mass_flow', ...
                'burner_inlet_corrected_mass_flow','gt_pt_duct_corrected_mass_flow', ...
                'pt_nozzle_duct_corrected_mass_flow','ac_corrected_speed', ...
                'gt_total_pressure_ratio','pt_total_pressure_ratio','dNp_dt','dNg_dt'};
            invalidPrediction=array2table(nan(1,numel(names)),'VariableNames',names);
            records{k}=struct('valid',false,'prediction',invalidPrediction, ...
                'state',state,'derivative',nan(size(state)),'modelResidual',NaN, ...
                'stop',[exception.identifier,': ',exception.message], ...
                'errorIdentifier',exception.identifier,'errorMessage',exception.message);
        end
        if records{k}.valid && offset==0,session.cache(warmKey)=records{k}.state;end
        prediction=[prediction;records{k}.prediction]; %#ok<AGROW>
    end
    candidate(i).prediction=prediction;
    candidate(i).valid=all(cellfun(@(r)r.valid,records));
    candidate(i).diagnostic=struct('records',{records},'nominalVisser',true, ...
        'individualTransientHealth',schedule.designHealth(transientStart+(0:transientCount-1)), ...
        'thermalHistoryUsed',false);
    % 无效初猜可能在后续暖启动下恢复；不把一次失败永久固化为缓存。
    if offset==0 && candidate(i).valid,session.cache(key)=candidate(i);end
end
batch=struct('candidate',candidate,'branch',session.branch);
end

function r=local_three_solve(engine,x,wf,b,bounds,session,k,profile,offset)
% 复用TC27的固定参考热矩阵；参考来自固定先验而非首个随机候选。
% 每次仍计算真实DLL热残差，失败自动回退完整热求解，不冻结温度。
route=session.modelRoute;mode='thermal_only';speedBounds=[5000,40000;5000,70000];
if strcmp(route,'steady'),mode='steady_predict';speedBounds(1,:)=bounds;end
o=struct('maximumIterations',20,'finalJacobianAudit',true, ...
    'speedBounds_rpm',speedBounds,'verbose',false);
key=sprintf('fixed_reference_%d',k);
if strcmp(route,'transient_instant')&&offset==0
    if ~isKey(session.cache,key)
        s=session.priorSchedule;bp=b;bp.health=s.designHealth;bp.inletTotalPressureRecovery=.995;
        fuel=s.fuelBias;q=session.points.Wf_mean(k)/fuel.wfDesign;
        q=min(max(q,min(fuel.xNodes)),max(fuel.xNodes));
        w0=session.points.Wf_mean(k)-interp1(fuel.xNodes,fuel.biasNodes,q,'linear');
        x0=session.cfg.engine.initial.state(:);x0(1:2)=x(1:2);
        seed=double(engine.callContext.engPtr.eng.varIte(1:6));
        sht_health_schedule_initialize_dll(engine,sht_tc27_schedule_profile(s),s.designHealth);
        ref=sht_thermal_equilibrium_solve(engine,x0,w0,bp,'thermal_only',o);
        sht_health_schedule_initialize_dll(engine,profile,b.health);
        sht_tc27_reset_gas_seed(engine,seed);
        if ref.physicalValid&&rcond(ref.jacobian)>1e-12
            [L,U,P]=lu(ref.jacobian);ref.reuseFactor=struct('L',L,'U',U,'P',P);
            session.cache(key)=ref;
        end
    end
    if isKey(session.cache,key)
        e=sht_tc27_thermal_reuse(engine,x,wf,b,session.cache(key),o);
    else,e=sht_thermal_equilibrium_solve(engine,x,wf,b,mode,o);end
else,e=sht_thermal_equilibrium_solve(engine,x,wf,b,mode,o);end
y=e.output;dx=e.derivative;
names={'Np','Ng','Pt3','Tt45','inlet_corrected_mass_flow', ...
    'burner_inlet_corrected_mass_flow','gt_pt_duct_corrected_mass_flow', ...
    'pt_nozzle_duct_corrected_mass_flow','ac_corrected_speed', ...
    'gt_total_pressure_ratio','pt_total_pressure_ratio'};
prediction=table();for j=1:numel(names),prediction.(names{j})=y.(names{j});end
prediction.dNp_dt=dx(1);prediction.dNg_dt=dx(2);
[~,lookup]=sht_lookup_clearance_reference(engine.transientEffects.clearanceReferenceTable, ...
    e.state(1),e.state(2),max(b.Mkp*e.state(1)*pi/30,0),y.Tt1);
valid=e.physicalValid&&e.thermalPassed;
if strcmp(route,'steady'),valid=valid&&e.shaftPassed&&e.state(1)>=bounds(1)&&e.state(1)<=bounds(2);end
r=struct('state',e.state,'derivative',dx,'prediction',prediction,'modelRoute',route, ...
    'valid',valid,'strictResidualPassed',e.strictResidualPassed,'modelResidual',e.finalCommonWorkResidual, ...
    'remainingNewtonStep',e.remainingCorrection,'maximumRealEigenvalue',e.maximumRealJacobianEigenvalue, ...
    'referenceNearestFallback',any(lookup.nearestPointFallback.used),'referenceLookup',lookup, ...
    'backpressureClosure_Pa', ...
    y.Pback-sht_exhaust_backpressure(b.Ps0,max(b.Mkp*e.state(1)*pi/30,0),b.exhaustBackPressureModel), ...
    'stop',char(e.stopReason),'iterations',e.iterationCount,'trace',e.history,'equilibrium',e);
end

function result=local_solve(engine,state,wf,b,bounds,route)
% 外层物理Newton与参数优化无关。每次求值均由DLL重新计算气路及热导数。
% 原有1e-7共同工作阈值接近DLL自身精度，故同时给出严格判据和工程精度。
scale=[100;100;ones(27,1)]; step=[.5;.5;repmat(.05,27,1)];
strictTol=[1e-5;1e-5;repmat(1e-6,27,1)];
engineeringTol=[1e-3;1e-3;repmat(1e-4,27,1)];
free=(1:29).';
if strcmp(route,'transient_instant'),free=(3:29).';end
fixedSpeed=state(1:2);
stop='maximum_physical_iterations'; trace=zeros(0,3);
for iteration=0:20
    [dx,~,diag]=sht_engine_derivative(engine,state,wf,b);
    if all(abs(dx(free))<=strictTol(free))&&diag.maxErr<=1e-6
        stop='thermal_residual_small';break;
    end
    if iteration==20,break;end
    J=zeros(numel(free));
    for j=1:numel(free)
        index=free(j);trial=state;trial(index)=trial(index)+step(index);
        dd=sht_engine_derivative(engine,trial,wf,b);
        J(:,j)=(dd(free)-dx(free))./scale(free)/step(index);
    end
    update=zeros(29,1);update(free)=-(J\(dx(free)./scale(free)));accepted=false;
    for power=0:12
        trial=state+2^(-power)*update;
        if trial(1)<bounds(1)||trial(1)>bounds(2)||trial(2)<5000|| ...
                trial(2)>70000||any(trial(3:end)<100|trial(3:end)>3000),continue;end
        [dd,~,check]=sht_engine_derivative(engine,trial,wf,b);
        if check.evaluationValid&&all(isfinite(dd))&&norm(dd(free)./scale(free))<norm(dx(free)./scale(free))
            state=trial;accepted=true;break;
        end
    end
    trace(end+1,:)=[iteration,norm(dx(free)./scale(free)),accepted]; %#ok<AGROW>
    if ~accepted,stop='physical_numerical_floor_or_no_decrease';break;end
end
[dx,y,diag]=sht_engine_derivative(engine,state,wf,b);
% 最终独立中心差分只验证物理根精度，参数Jacobian仍用前向差分。
J=zeros(numel(free));
for j=1:numel(free)
    index=free(j);
    plus=state;minus=state;plus(index)=plus(index)+step(index);minus(index)=minus(index)-step(index);
    dp=sht_engine_derivative(engine,plus,wf,b);
    dm=sht_engine_derivative(engine,minus,wf,b);
    J(:,j)=(dp(free)-dm(free))/(2*step(index));
end
remaining=zeros(29,1);remaining(free)=-(J\dx(free));
strict=all(abs(dx(free))<=strictTol(free))&&diag.maxErr<=1e-7;
valid=diag.evaluationValid&&diag.maxErr<=1e-6&&all(abs(dx(free))<=engineeringTol(free))&& ...
    all(isfinite(remaining))&&max(abs(remaining(1:2)))<=.01&& ...
    max(abs(remaining(3:end)))<=.001&&state(1)>=bounds(1)&&state(1)<=bounds(2);
names={'Np','Ng','Pt3','Tt45','inlet_corrected_mass_flow', ...
    'burner_inlet_corrected_mass_flow','gt_pt_duct_corrected_mass_flow', ...
    'pt_nozzle_duct_corrected_mass_flow','ac_corrected_speed', ...
    'gt_total_pressure_ratio','pt_total_pressure_ratio'};
prediction=table();
for j=1:numel(names),prediction.(names{j})=y.(names{j});end
prediction.dNp_dt=dx(1);prediction.dNg_dt=dx(2);
if strcmp(route,'transient_instant')
    assert(isequal(state(1:2),fixedSpeed),'瞬态时刻热平衡改变了输入转速。');
end
power=max(b.Mkp*state(1)*pi/30,0);
[~,reference]=sht_lookup_clearance_reference( ...
    engine.transientEffects.clearanceReferenceTable,state(1),state(2),power,b.Tt1);
result=struct('state',state,'derivative',dx,'prediction',prediction,'modelRoute',route, ...
    'valid',valid,'strictResidualPassed',strict,'modelResidual',diag.maxErr, ...
    'remainingNewtonStep',remaining,'maximumRealEigenvalue',max(real(eig(J))), ...
    'referenceNearestFallback',any(reference.nearestPointFallback.used), ...
    'backpressureClosure_Pa',y.Pback-sht_exhaust_backpressure(b.Ps0,power,b.exhaustBackPressureModel), ...
    'stop',stop,'iterations',iteration,'trace',trace);
end
