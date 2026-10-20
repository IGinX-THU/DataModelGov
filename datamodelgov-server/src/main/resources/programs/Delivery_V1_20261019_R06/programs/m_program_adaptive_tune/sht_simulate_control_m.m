function result = sht_simulate_control_m(cfg)
% 阅读说明：
%   本文件是离散时间仿真调度器，不直接设计控制律。
%   它负责把连续对象和离散控制器按真实因果顺序串起来：控制器采样 -> 燃油执行机构 -> 发动机 -> 传感器。
%   若要理解闭环时序，优先看本文件主循环；若要理解控制律，转到 sht_full_controller_step。
%SHT_SIMULATE_CONTROL_M Closed-loop turboshaft control simulation in MATLAB code.
% 涡轴发动机闭环控制 m 程序主循环。
%
%   1) Pulse Generator + Transfer Fcn + Sum  -> sht_reference_step
%   2) Turboshaft Engine Control System      -> sht_full_controller_step
%   3) Fuel System                           -> sht_actuator_derivative
%   4) Level-2 MATLAB S-Function             -> sht_engine_derivative
%   5) Demux/Scope/To Workspace              -> sht_log_record 日志模块
%
% 执行时序按真实控制系统显式展开：
%   控制器每 Tctrl 采样一次传感器输出并计算 WfcmdNext；
%   commandDelay 决定控制器输出寄存器 WfcmdNow 是否相对 WfcmdNext 延后一拍；
%   燃油执行机构、发动机本体和传感器按因果级联分区二阶积分；
%   执行器先给出 Wf_k/Wf_{k+1}，发动机再用燃油端点推进，
%   传感器最后用 yEng_k/yEng_{k+1} 端点输出推进。

% 输入处理：Start_sim 已经生成 cfg；本函数不再隐式创建空配置。
if nargin ~= 1 || isempty(cfg)
    error('sht:simulate:missingInput', ...
        'Call sht_simulate_control_m with cfg. Use Start_sim() for default execution.');
end

cfg = local_normalize_config(cfg);

% 打开并初始化 GTESS.dll。engine 结构只保存库名和路径，
% 实际发动机状态由 xEngine=[Np;Ng] 和 DLL 内部迭代初值共同决定。
engine = sht_engine_open(cfg.engine);
cleanup = onCleanup(@() sht_engine_close(engine));

nSteps = round(cfg.stopTime / cfg.Tsim);
time = (0:nSteps)' * cfg.Tsim;
nLog = nSteps + 1;

% 发动机转子初值来自基线配平点；燃油执行机构初值来自 cfg.actuator，默认等于 cfg.engine.initial.Wf0。
xEngine = cfg.engine.initial.state(:);
wf = cfg.actuator.initialWf;

% 参考指令模块：对应顶层 NpDem 常值、Pulse Generator 和一阶 Transfer Fcn。
refState = struct('time', 0, 'npFilter', 0, 'powerFilter', 0, ...
    'integrationMethod', cfg.integrationMethod);
[ref, refState] = sht_reference_step(refState, cfg.reference, 0);

% 初始化发动机 k 点评估缓存。后续每个步长只新增预测点和 k+1 端点评估。
boundary = local_build_runtime_boundary(cfg, ref, xEngine, 0);
engineEval = local_engine_eval(engine, xEngine, wf, boundary);
engineY = engineEval.y;

% 传感器模块：默认 identity；接口预留为连续一阶惯性和噪声/偏置。
sensorState = struct();
[sample, sensorState] = sht_sensor_step(sensorState, engineY, ...
    cfg.sensor, 0, cfg.integrationMethod, engineY);

% 控制器初始化前先按 t=0 的 Ngc 调度一次线性化系数，保证 z2NgPrev 等离散记忆量
% 与本次仿真初始工况一致。
[cfg.controller, initialGainScheduleDiag] = sht_apply_controller_gain_schedule( ...
    cfg.controller, sample);
controllerState = sht_steady_governor_init(cfg.controller);
controllerState = local_align_full_controller_initial_state(...
    controllerState, cfg.controller, sample);
wfCommandNext = controllerState.Wfcmd;
wfCommandNextRegister = controllerState.Wfcmd;
wfCommandNow = controllerState.Wfcmd;
ctrlDiag = sht_log_record.emptyControllerDiag(controllerState);
ctrlDiag.gainScheduleEnabled = initialGainScheduleDiag.enabled;
ctrlDiag.gainScheduleNgc = initialGainScheduleDiag.Ngc;
ctrlDiag.gainScheduleNgcClamped = initialGainScheduleDiag.NgcClamped;
ctrlDiag.gainScheduleAtLowerBound = initialGainScheduleDiag.atLowerBound;
ctrlDiag.gainScheduleAtUpperBound = initialGainScheduleDiag.atUpperBound;
ctrlDiag.linearB11 = cfg.controller.linearModel.b11;
ctrlDiag.linearB21 = cfg.controller.linearModel.b21;
ctrlDiag.linearD31 = cfg.controller.linearModel.d31;
ctrlDiag.linearD41 = cfg.controller.linearModel.d41;
actDiag = struct('rawRate', 0, 'limitedRate', 0, ...
    'wfCommand', wfCommandNow, 'wfCommandNext', wfCommandNext, ...
    'wfCommandNow', wfCommandNow);
engineDiag = engineEval.diag;

log = sht_log_record.allocate(nLog, numel(xEngine));
log = sht_log_record.store(log, 1, time(1), xEngine, wf, ...
    wfCommandNext, wfCommandNow, ref, sample, ...
    engineY, ctrlDiag, actDiag, engineDiag, true);
log = local_store_runtime_boundary_log(log, 1, boundary, engineY);

nextControlTime = 0;
controlTolerance = max(1e-12, cfg.Tsim * 1e-9);

% 主时间循环。
% 每一轮从 t_k 推进到 t_{k+1}：先在需要时执行离散控制器，再推进连续执行器/发动机/传感器。
for k = 1:nSteps
    t = time(k);

    % 当前步的发动机边界条件。负载功率可能来自参考指令滤波器，因此每步重新写入。
    boundary = local_build_runtime_boundary(cfg, ref, xEngine, t);
    if ~local_engine_eval_matches(engineEval, xEngine, wf, boundary)
        engineEval = local_engine_eval(engine, xEngine, wf, boundary);
        engineY = engineEval.y;
    end

    % 控制器采样时刻：用当前传感器采样 sample 和当前参考 ref 计算下一拍燃油指令。
    % oneSample 模式下，sht_full_controller_step 内部先给出输出寄存器当前值
    % WfcmdNow=上一拍 WfcmdNext，再把本拍 WfcmdNext 写入下一拍状态。
    if t + controlTolerance >= nextControlTime
        [sample, sensorState] = sht_sensor_step(sensorState, engineY, ...
            cfg.sensor, 0, cfg.integrationMethod, engineY);
        % 离散控制器只在采样时刻运行一次；dt 使用 Tctrl，而不是连续对象积分步长 Tsim。
        [wfCommandNext, controllerState, ctrlDiag] = sht_full_controller_step( ...
            controllerState, sample, ref, cfg.controller, ...
            cfg.Tctrl, cfg.integrationMethod);
        if isfield(ctrlDiag, 'wfCommandNow')
            wfCommandNow = ctrlDiag.wfCommandNow;
        else
            wfCommandNow = wfCommandNext;
        end
        % WfcmdDelay 是控制器输出寄存器，主要用于检查 oneSample 时序是否符合预期。
        wfCommandNextRegister = controllerState.WfcmdDelay;
        ctrlDiag.wfCommandNext = wfCommandNext;
        ctrlDiag.wfCommandNow = wfCommandNow;
        nextControlTime = nextControlTime + cfg.Tctrl;
        didControlUpdate = true;
    else
        didControlUpdate = false;
    end

    % 因果级联分区积分：执行器 -> 发动机。传感器随后用发动机端点输出推进。
    engineEvalStart = engineEval;

    [xEngine, wf, engineEvalNext, engineDiag, actDiag] = local_integrate_cascade( ...
        engine, xEngine, wf, wfCommandNow, boundary, engineEvalStart, cfg, t);

    if cfg.throwOnEngineNonconvergence && ...
            (engineDiag.convergeTag ~= 0 || engineDiag.maxErr > 1e-5)
        error('sht:engine:nonconverged', ...
            'Engine nonconvergence at t=%.6f: tag=%d, maxErr=%g', ...
            time(k + 1), engineDiag.convergeTag, engineDiag.maxErr);
    end

    % 积分步结束后用发动机 k/k+1 端点输出推进传感器状态。
    [sample, sensorState] = sht_sensor_step(sensorState, engineEvalStart.y, ...
        cfg.sensor, cfg.Tsim, cfg.integrationMethod, engineEvalNext.y);
    engineEval = engineEvalNext;
    engineY = engineEval.y;

    refState.time = t;
    [ref, refState] = sht_reference_step(refState, cfg.reference, cfg.Tsim);

    % 日志记录放在步末，此时发动机、执行器、传感器和参考指令都已经推进到 t_{k+1}。
    log = sht_log_record.store(log, k + 1, time(k + 1), xEngine, wf, ...
        wfCommandNext, wfCommandNow, ref, sample, engineY, ctrlDiag, ...
        actDiag, engineDiag, didControlUpdate);
    % 记录本积分步实际施加给 DLL 的端点负载，而不是下一采样点刚更新的
    % 参考指令。原 log.power 字段仍保持既有参考指令语义。
    log = local_store_runtime_boundary_log( ...
        log, k + 1, engineEval.boundary, engineY);
end

clear cleanup;

log = sht_log_record.addDerivedSignals(log);

result = struct();
result.time = time;
result.log = log;
result.cfg = cfg;
result.finalState = struct('engine', xEngine, 'wf', wf, ...
    'wfCommandNext', wfCommandNext, 'wfCommandNow', wfCommandNow, ...
    'wfCommandNextRegister', wfCommandNextRegister, 'controller', controllerState, ...
    'reference', refState, 'sensor', sensorState, 'engineEval', engineEval);
end

function cfg = local_normalize_config(cfg)
% 配置归一化只做接口安全处理，不做控制律计算。
% 运行时参数全部来自 cfg；若用户直接调用本函数，也统一经过 sht_validate_runtime_config 检查。
cfg = sht_validate_runtime_config(cfg);
cfg = local_validate_flight_boundary_schedule(cfg);
end

function evalInfo = local_engine_eval(engine, x, wf, boundary)
% 统一封装一次发动机 DLL 调用，便于缓存 k/k+1 端点计算结果。
boundary = sht_resolve_shaft_load_boundary(boundary, x);
[xDot, y, diagInfo] = sht_engine_derivative(engine, x, wf, boundary);
evalInfo = struct();
evalInfo.xEngine = x(:);
evalInfo.wf = wf;
evalInfo.boundary = boundary;
evalInfo.xDot = xDot(:);
evalInfo.y = y;
evalInfo.diag = diagInfo;
end

function tf = local_engine_eval_matches(evalInfo, x, wf, boundary)
% 判断缓存的发动机评估是否仍对应当前状态和边界条件。
tf = isstruct(evalInfo) && isfield(evalInfo, 'xEngine') && ...
    isfield(evalInfo, 'wf') && isfield(evalInfo, 'boundary') && ...
    numel(evalInfo.xEngine) == numel(x) && ...
    max(abs(evalInfo.xEngine(:) - x(:))) < 1e-9 && ...
    abs(evalInfo.wf - wf) < 1e-12 && ...
    local_boundary_matches(evalInfo.boundary, boundary);
end

function tf = local_boundary_matches(a, b)
% 发动机边界量变化时，k 点评估必须重新计算，不能复用上一缓存。
fields = {'A8', 'power', 'hpsPower', 'Mkp', 'Mkg', 'hpcAlpha'};
for i = 1:numel(fields)
    name = fields{i};
    if ~isfield(a, name) || ~isfield(b, name) || abs(a.(name) - b.(name)) > 1e-12
        tf = false;
        return;
    end
end
optionalFields = {'inletBoundaryMode', 'altitude', 'Mach', ...
    'deltaTemperature', 'Pt1', 'Tt1', 'Pamb', 'Pback', 'Tamb', 'ptShaftInertiaFactor', ...
    'healthScheduleEnabled','clearanceInletTotalTemperature_K'};
for i = 1:numel(optionalFields)
    if ~local_optional_scalar_matches(a, b, optionalFields{i}, 1e-12)
        tf = false;
        return;
    end
end
healthLength = max([100, local_numel_field(a, 'health'), local_numel_field(b, 'health')]);
ha = zeros(healthLength, 1);
hb = zeros(healthLength, 1);
if isfield(a, 'health') && ~isempty(a.health)
    n = min(numel(a.health), healthLength);
    ha(1:n) = a.health(1:n);
end
if isfield(b, 'health') && ~isempty(b.health)
    n = min(numel(b.health), healthLength);
    hb(1:n) = b.health(1:n);
end
tf = max(abs(ha - hb)) <= 1e-12;
if tf
    epsilonLength = max([local_numel_field(a, 'epsilonSSHeld'), ...
        local_numel_field(b, 'epsilonSSHeld')]);
    if epsilonLength > 0
        ea = nan(epsilonLength, 1);
        eb = nan(epsilonLength, 1);
        if isfield(a, 'epsilonSSHeld') && ~isempty(a.epsilonSSHeld)
            ea(1:numel(a.epsilonSSHeld)) = a.epsilonSSHeld(:);
        end
        if isfield(b, 'epsilonSSHeld') && ~isempty(b.epsilonSSHeld)
            eb(1:numel(b.epsilonSSHeld)) = b.epsilonSSHeld(:);
        end
        tf = all(isfinite(ea)) && all(isfinite(eb)) && ...
            max(abs(ea - eb)) <= 1e-15;
    end
end
end

function boundary = local_attach_clearance_reference(cfg, xEngine, boundary)
% 只在 P5 开启时增加边界字段；基准/P3/P4 的缓存键和结构保持不变。
if ~isfield(cfg.engine, 'transientEffects')
    return;
end
effects = cfg.engine.transientEffects;
if ~isstruct(effects) || ~isfield(effects, 'clearanceEnabled') || ...
        ~effects.clearanceEnabled
    return;
end
expectedStateCount = 15;
if isfield(effects, 'derivativeOutputCount') && ...
        ~isempty(effects.derivativeOutputCount)
    expectedStateCount = effects.derivativeOutputCount;
elseif isfield(cfg.engine, 'modelMode') && cfg.engine.modelMode == 1
    expectedStateCount = 27;
    if isfield(effects, 'thermalModelMode') && ...
            effects.thermalModelMode == 3
        expectedStateCount = 29;
    end
end
if numel(xEngine) ~= expectedStateCount
    error('sht:simulate:clearanceStateSize', ...
        'Clearance mode requires %d engine states for the active topology.', ...
        expectedStateCount);
end
[boundary.epsilonSSHeld, boundary.clearanceLookupInfo] = ...
    sht_lookup_clearance_reference(effects.clearanceReferenceTable, ...
    xEngine(1), xEngine(2), boundary.power, ...
    local_clearance_inlet_temperature(boundary, effects.clearanceReferenceTable));
end

function boundary = local_build_runtime_boundary(cfg, ref, xEngine, time_s)
% 默认分支严格沿用 ref.power；collectivePitch 分支则以总距角为权威输入，
% 直接计算旋翼负载扭矩和功率，避免由功率反算总距角。
% S4 飞行任务模式则以 theta(t) 为原始边界，并用当前 Np 计算 DLL 负载。
boundary = cfg.engine.boundary;
flightBoundaryEnabled = local_flight_boundary_enabled(cfg);
if flightBoundaryEnabled
    boundary = local_refresh_flight_boundary(cfg, boundary, xEngine, time_s);
else
    boundary.power = ref.power;
    boundary.ptLoadInputMode = 'power';
end
if ~flightBoundaryEnabled && local_rotor_load_enabled(cfg)
    inputMode = local_rotor_load_input_mode(cfg);
    boundary.rotorLoadInputMode = inputMode;
    switch inputMode
        case 'legacypower'
            boundary.rotorLoadCommandValue = ref.power;
            % 保留历史字段，方便既有诊断程序继续读取。
            boundary.rotorLoadPowerCommandW = ref.power;
        case 'collectivepitch'
            if ~isfield(ref, 'thetaCollectiveDeg') || ...
                    ~isscalar(ref.thetaCollectiveDeg) || ...
                    ~isfinite(ref.thetaCollectiveDeg)
                error('sht:simulate:missingCollectivePitchCommand', ...
                    ['collectivePitch 旋翼负载模式缺少有限的 ' ...
                     'ref.thetaCollectiveDeg。']);
            end
            boundary.rotorLoadCommandValue = ref.thetaCollectiveDeg;
            boundary.rotorLoadCollectivePitchCommandDeg = ...
                ref.thetaCollectiveDeg;
        case 'directtorque'
            if ~isfield(cfg.flight.rotorLoad, 'directTorqueCommandNm') || ...
                    ~isscalar(cfg.flight.rotorLoad.directTorqueCommandNm) || ...
                    ~isfinite(cfg.flight.rotorLoad.directTorqueCommandNm)
                error('sht:simulate:missingDirectTorqueCommand', ...
                    ['directTorque 旋翼负载模式需要有限的 ' ...
                     'cfg.flight.rotorLoad.directTorqueCommandNm。']);
            end
            boundary.rotorLoadCommandValue = ...
                cfg.flight.rotorLoad.directTorqueCommandNm;
        otherwise
            error('sht:simulate:badRotorLoadInputMode', ...
                '不支持的旋翼负载输入模式 %s。', inputMode);
    end
    boundary = local_refresh_rotor_load_boundary(cfg, boundary, xEngine);
end

% epsilon_ss 查询和 DLL 调用均使用已经按当前轴速解析后的实际功率。
boundary = sht_resolve_shaft_load_boundary(boundary, xEngine);

% P5 在已接受步起点查询一次 epsilon_ss；整个积分步及其全部子阶段保持。
boundary = local_attach_clearance_reference(cfg, xEngine, boundary);
end

function boundary = local_refresh_state_dependent_boundary( ...
        cfg, boundary, xEngine, time_s)
% Heun 预测点和校正端点必须使用各自时刻及各自 Np。默认分支沿用
% 原行为；只有 S4 显式开启后才刷新时变进气边界和 theta 调度。
if local_flight_boundary_enabled(cfg)
    boundary = local_refresh_flight_boundary(cfg, boundary, xEngine, time_s);
else
    boundary = local_refresh_rotor_load_boundary(cfg, boundary, xEngine);
end
boundary = sht_resolve_shaft_load_boundary(boundary, xEngine);
end

function boundary = local_refresh_flight_boundary(cfg, boundary, xEngine, time_s)
if isempty(xEngine) || ~isfinite(xEngine(1)) || xEngine(1) <= 0
    error('sht:simulate:badFlightBoundaryNp', ...
        '飞行任务边界需要有限正的当前 Np 状态。');
end
schedule = cfg.flight.boundarySchedule;
flightPoint = sht_flight_boundary_step(time_s, xEngine(1), ...
    schedule.mission, schedule.model);

% 飞行任务以旋翼模型给出的 Qload 作为 PT 负载扭矩边界；附件仍由
% hpsPower 调度并换算为 Mkg。真值生成只给DLL环境静态、Mach和
% 装机总压恢复，Pt1/Tt1由C端模式2重构，不使用直接总参量模式。
if isfield(boundary,'Pt1'), boundary = rmfield(boundary,'Pt1'); end
if isfield(boundary,'Tt1'), boundary = rmfield(boundary,'Tt1'); end
% 只供M侧间隙参考查询，不作为DLL总温输入。使用任务边界已有诊断量，
% 不新增大气/进气道公式；导数包装器逐次核对C返回的Tt1，差异即报错。
boundary.clearanceInletTotalTemperature_K=flightPoint.Tt1_K;
boundary.Pamb = flightPoint.Pamb_Pa;
if isfield(flightPoint,'Pback_Pa')
    boundary.Pback = flightPoint.Pback_Pa;
elseif isfield(boundary,'Pback')
    boundary = rmfield(boundary,'Pback');
end
boundary.inletBoundaryMode = 2;
boundary.altitude = flightPoint.altitude_m;
boundary.Mach = flightPoint.mach;
boundary.deltaTemperature = flightPoint.deltaT_K;
boundary.Tamb = flightPoint.Ts_K;
boundary.inletTotalPressureRecovery = flightPoint.totalPressureRecovery;
boundary.Mkp = flightPoint.Qload_Nm;
boundary.ptLoadInputMode = 'torque';
boundary.hpsPower = flightPoint.hpsPower_W;
boundary.gtLoadInputMode = 'power';
boundary.thetaCollectiveDeg = flightPoint.theta_deg;
boundary.kTheta = flightPoint.kTheta;
boundary.thetaWithinValidRange = flightPoint.thetaWithinValidRange;
boundary.thetaTailDeg = flightPoint.thetaTail_deg;
boundary.tailPitchWithinValidRange = flightPoint.tailPitchWithinValidRange;
boundary.tailLoadFactor = flightPoint.tailLoadFactor;
boundary.mainRotorPowerW = flightPoint.mainRotorPower_W;
boundary.tailRotorPowerW = flightPoint.tailRotorPower_W;
boundary.splitRotorLoadEnabled = flightPoint.splitRotorLoadEnabled;
boundary.Npr = flightPoint.Npr;
boundary.QloadNm = flightPoint.Qload_Nm;
boundary.PloadW = flightPoint.Pload_W;
boundary.rotorLoadEnabled = true;
boundary.flightBoundaryEnabled = true;
boundary.flightBoundaryTime_s = flightPoint.time_s;
boundary.flightMissionId = flightPoint.missionId;
boundary.flightSegmentId = flightPoint.segmentId;
boundary.flightSegmentIndex = flightPoint.segmentIndex;
boundary.flightAltitude_m = flightPoint.altitude_m;
boundary.flightMach = flightPoint.mach;
boundary.flightDeltaT_K = flightPoint.deltaT_K;
boundary.flightPt0_Pa = flightPoint.Pt0_Pa;
boundary.flightTt0_K = flightPoint.Tt0_K;
boundary.flightExpectedPt1_Pa = flightPoint.Pt1_Pa;
boundary.flightExpectedTt1_K = flightPoint.Tt1_K;
boundary.flightSigmaIn = flightPoint.sigmaIn;
boundary.flightSigmaDist = flightPoint.sigmaDist;
boundary.flightTotalPressureRecovery = flightPoint.totalPressureRecovery;
boundary.flightDeltaPExhaust_Pa = flightPoint.deltaPExhaust_Pa;
boundary.flightExhaustBackPressureEnabled = ...
    flightPoint.exhaustBackPressureEnabled;
boundary.flightTroposphereFormulaExtrapolated = ...
    flightPoint.troposphereFormulaExtrapolated;
end

function boundary = local_refresh_rotor_load_boundary(cfg, boundary, xEngine)
% 旋翼气动负载依赖当前 Np。预测点和校正端点均调用本函数，不能把
% 一个采样点的负载冻结到整个 Heun 积分步。
if ~local_rotor_load_enabled(cfg)
    return;
end
if ~isfield(boundary, 'rotorLoadCommandValue') || ...
        ~isscalar(boundary.rotorLoadCommandValue) || ...
        ~isfinite(boundary.rotorLoadCommandValue)
    error('sht:simulate:missingRotorLoadCommand', ...
        '旋翼负载模式缺少有限的权威边界指令。');
end
if isempty(xEngine) || ~isfinite(xEngine(1))
    error('sht:simulate:badRotorSpeed', ...
        '飞行旋翼负载模式需要有限的当前 Np 状态。');
end

inputMode = local_rotor_load_input_mode(cfg);
loadState = sht_rotor_load_model( ...
    xEngine(1), boundary.rotorLoadCommandValue, ...
    cfg.flight.rotorLoad, inputMode);
boundary.power = loadState.PloadW;
boundary.Mkp = loadState.QloadNm;
boundary.ptLoadInputMode = 'torque';
boundary.rotorLoadInputMode = inputMode;
boundary.kTheta = loadState.kTheta;
boundary.thetaCollectiveDeg = loadState.thetaCollectiveDeg;
boundary.thetaWithinValidRange = loadState.thetaWithinValidRange;
boundary.Npr = loadState.Npr;
boundary.QloadNm = loadState.QloadNm;
boundary.PloadW = loadState.PloadW;
boundary.rotorLoadEnabled = true;
end

function enabled = local_rotor_load_enabled(cfg)
enabled = false;
if ~isfield(cfg, 'flight') || ~isstruct(cfg.flight) || ...
        ~isfield(cfg.flight, 'rotorLoad') || ~isstruct(cfg.flight.rotorLoad) || ...
        ~isfield(cfg.flight.rotorLoad, 'enabled') || ...
        isempty(cfg.flight.rotorLoad.enabled)
    return;
end
flag = cfg.flight.rotorLoad.enabled;
if ~(islogical(flag) || isnumeric(flag)) || ~isscalar(flag) || ~isfinite(flag)
    error('sht:simulate:badRotorLoadSwitch', ...
        'cfg.flight.rotorLoad.enabled 必须是有限标量逻辑开关。');
end
enabled = logical(flag);
end

function mode = local_rotor_load_input_mode(cfg)
%LOCAL_ROTOR_LOAD_INPUT_MODE 解析M程序旋翼负载的权威输入类型。
mode = 'legacypower';
if isfield(cfg.flight.rotorLoad, 'inputMode') && ...
        ~isempty(cfg.flight.rotorLoad.inputMode)
    mode = cfg.flight.rotorLoad.inputMode;
end
if isstring(mode) && isscalar(mode)
    mode = char(mode);
end
if ~ischar(mode)
    error('sht:simulate:badRotorLoadInputMode', ...
        'cfg.flight.rotorLoad.inputMode必须为字符向量或标量字符串。');
end
mode = lower(strtrim(mode));
if ~ismember(mode, {'legacypower', 'directtorque', 'collectivepitch'})
    error('sht:simulate:badRotorLoadInputMode', ...
        ['cfg.flight.rotorLoad.inputMode必须为legacyPower、directTorque或' ...
         'collectivePitch，当前为%s。'], mode);
end
end

function cfg = local_validate_flight_boundary_schedule(cfg)
% 关闭或缺失时不补字段，保证第 2 阶段 cfg 和日志结构保持原样。
if ~isfield(cfg, 'flight') || ~isstruct(cfg.flight) || ...
        ~isfield(cfg.flight, 'boundarySchedule') || ...
        isempty(cfg.flight.boundarySchedule)
    return;
end
schedule = cfg.flight.boundarySchedule;
if ~isstruct(schedule) || ~isscalar(schedule)
    error('sht:simulate:badFlightBoundarySchedule', ...
        'cfg.flight.boundarySchedule 必须是标量结构体。');
end
if ~isfield(schedule, 'enabled') || isempty(schedule.enabled)
    schedule.enabled = false;
end
if ~(islogical(schedule.enabled) || isnumeric(schedule.enabled)) || ...
        ~isscalar(schedule.enabled) || ~isfinite(schedule.enabled)
    error('sht:simulate:badFlightBoundarySwitch', ...
        'cfg.flight.boundarySchedule.enabled 必须是有限标量逻辑开关。');
end
schedule.enabled = logical(schedule.enabled);
cfg.flight.boundarySchedule = schedule;
if ~schedule.enabled
    return;
end
if ~isfield(schedule, 'mission') || ~isfield(schedule, 'model') || ...
        ~isstruct(schedule.mission) || ~isscalar(schedule.mission) || ...
        ~isstruct(schedule.model) || ~isscalar(schedule.model)
    error('sht:simulate:missingFlightBoundaryConfig', ...
        '启用 S4 时必须给出 boundarySchedule.mission 和 .model。');
end
if ~isfield(schedule.mission, 'duration_s') || ...
        ~isscalar(schedule.mission.duration_s) || ...
        ~isfinite(schedule.mission.duration_s) || ...
        schedule.mission.duration_s <= 0
    error('sht:simulate:badFlightMissionDuration', ...
        '飞行任务 duration_s 必须是有限正标量。');
end
tolerance = 100 * eps(max(1, schedule.mission.duration_s));
if cfg.stopTime > schedule.mission.duration_s + tolerance
    error('sht:simulate:flightMissionTooShort', ...
        ['仿真 stopTime=%.12g s 超出飞行任务 duration_s=%.12g s；' ...
         '时间边界禁止外推。'], cfg.stopTime, schedule.mission.duration_s);
end

% 在加载 DLL 前校验任务起点和仿真终点，尽早暴露配置错误。
Np0 = cfg.engine.initial.state(1);
sht_flight_boundary_step(0, Np0, schedule.mission, schedule.model);
sht_flight_boundary_step(cfg.stopTime, Np0, ...
    schedule.mission, schedule.model);
end

function enabled = local_flight_boundary_enabled(cfg)
enabled = false;
if ~isfield(cfg, 'flight') || ~isstruct(cfg.flight) || ...
        ~isfield(cfg.flight, 'boundarySchedule') || ...
        ~isstruct(cfg.flight.boundarySchedule) || ...
        ~isfield(cfg.flight.boundarySchedule, 'enabled') || ...
        isempty(cfg.flight.boundarySchedule.enabled)
    return;
end
flag = cfg.flight.boundarySchedule.enabled;
if ~(islogical(flag) || isnumeric(flag)) || ~isscalar(flag) || ...
        ~isfinite(flag)
    error('sht:simulate:badFlightBoundarySwitch', ...
        'cfg.flight.boundarySchedule.enabled 必须是有限标量逻辑开关。');
end
enabled = logical(flag);
end

function log = local_store_runtime_boundary_log(log, index, boundary, engineY)
log = local_store_rotor_load_log(log, index, boundary);
log = local_store_flight_boundary_log(log, index, boundary, engineY);
end

function log = local_store_flight_boundary_log(log, index, boundary, engineY)
% 飞行边界关闭时不增加字段，保证既有第 2 阶段日志结构和结果不变。
if ~isfield(boundary, 'flightBoundaryEnabled') || ...
        ~boundary.flightBoundaryEnabled
    return;
end
if ~isfield(log, 'flightBoundaryEnabled')
    n = numel(log.time);
    log.flightBoundaryEnabled = false(n, 1);
    log.flightBoundaryTime = nan(n, 1);
    log.flightAltitude = nan(n, 1);
    log.flightMach = nan(n, 1);
    log.flightDeltaT = nan(n, 1);
    log.flightPt0 = nan(n, 1);
    log.flightTt0 = nan(n, 1);
    log.flightPt1 = nan(n, 1);
    log.flightTt1 = nan(n, 1);
    log.flightPamb = nan(n, 1);
    log.flightPback = nan(n, 1);
    log.flightPbackCommand = nan(n, 1);
    log.flightDeltaPExhaust = nan(n, 1);
    log.flightHpsPower = nan(n, 1);
    log.flightSigmaIn = nan(n, 1);
    log.flightSigmaDist = nan(n, 1);
    log.flightTotalPressureRecovery = nan(n, 1);
    log.flightInletBoundaryMode = nan(n, 1);
    log.flightExpectedPt1 = nan(n, 1);
    log.flightExpectedTt1 = nan(n, 1);
    % 下列量只在飞行边界模式下记录，用于装机进气损失的物理影响校核。
    % 压比由各部件实际进出口总压计算，不参与控制器或状态推进。
    log.flightWIn = nan(n, 1);
    log.flightHpcPressureRatio = nan(n, 1);
    log.flightGtPressureRatio = nan(n, 1);
    log.flightPtPressureRatio = nan(n, 1);
    log.flightSegmentIndex = nan(n, 1);
    log.flightTroposphereFormulaExtrapolated = false(n, 1);
    log.flightMissionId = repmat({''}, n, 1);
    log.flightSegmentId = repmat({''}, n, 1);
end
log.flightBoundaryEnabled(index) = true;
log.flightBoundaryTime(index) = boundary.flightBoundaryTime_s;
log.flightAltitude(index) = boundary.flightAltitude_m;
log.flightMach(index) = boundary.flightMach;
log.flightDeltaT(index) = boundary.flightDeltaT_K;
log.flightPt0(index) = boundary.flightPt0_Pa;
log.flightTt0(index) = boundary.flightTt0_K;
log.flightPamb(index) = boundary.Pamb;
if isfield(boundary,'Pback')
    log.flightPbackCommand(index) = boundary.Pback;
    if ~isfield(engineY,'Pback') || ~isscalar(engineY.Pback) || ...
            ~isfinite(engineY.Pback)
        error('sht:simulate:missingExhaustBackPressureResponse', ...
            '启用独立排气背压后，发动机输出必须返回有限的Pback。');
    end
    log.flightPback(index) = engineY.Pback;
else
    log.flightPbackCommand(index) = boundary.Pamb;
    log.flightPback(index) = boundary.Pamb;
end
log.flightDeltaPExhaust(index) = boundary.flightDeltaPExhaust_Pa;
log.flightHpsPower(index) = boundary.hpsPower;
log.flightSigmaIn(index) = boundary.flightSigmaIn;
log.flightSigmaDist(index) = boundary.flightSigmaDist;
log.flightTotalPressureRecovery(index) = ...
    boundary.flightTotalPressureRecovery;
log.flightInletBoundaryMode(index) = boundary.inletBoundaryMode;
log.flightExpectedPt1(index) = boundary.flightExpectedPt1_Pa;
log.flightExpectedTt1(index) = boundary.flightExpectedTt1_K;
requiredEngineFields = {'WIn','Pt1','Tt1','Pt3','BurnerPtOut','Pt45','Pt5'};
for fieldIndex = 1:numel(requiredEngineFields)
    name = requiredEngineFields{fieldIndex};
    if ~isfield(engineY, name) || ~isscalar(engineY.(name)) || ...
            ~isfinite(engineY.(name))
        error('sht:simulate:missingFlightResponse', ...
            '飞行边界日志所需发动机输出 %s 缺失或无效。', name);
    end
end
log.flightPt1(index) = engineY.Pt1;
log.flightTt1(index) = engineY.Tt1;
pressureValues = [engineY.Pt1, engineY.Pt3, engineY.BurnerPtOut, ...
    engineY.Pt45, engineY.Pt5];
if engineY.WIn <= 0 || any(pressureValues <= 0)
    error('sht:simulate:nonpositiveFlightResponse', ...
        '飞行边界日志中的入口流量或部件总压必须为正。');
end
log.flightWIn(index) = engineY.WIn;
log.flightHpcPressureRatio(index) = engineY.Pt3 / engineY.Pt1;
log.flightGtPressureRatio(index) = engineY.BurnerPtOut / engineY.Pt45;
log.flightPtPressureRatio(index) = engineY.Pt45 / engineY.Pt5;
log.flightSegmentIndex(index) = boundary.flightSegmentIndex;
log.flightTroposphereFormulaExtrapolated(index) = ...
    boundary.flightTroposphereFormulaExtrapolated;
log.flightMissionId{index} = boundary.flightMissionId;
log.flightSegmentId{index} = boundary.flightSegmentId;
if isfield(engineY,'reynoldsIndex')
    if ~isfield(log,'reynoldsIndex')
        n = numel(log.time);
        componentCount = numel(engineY.reynoldsIndex);
        log.reynoldsIndex = nan(n,componentCount);
        log.reynoldsFlowMultiplier = nan(n,componentCount);
        log.reynoldsEfficiencyMultiplier = nan(n,componentCount);
        log.reynoldsClampedLow = false(n,componentCount);
        log.reynoldsComponentName = engineY.reynoldsComponentName;
    end
    log.reynoldsIndex(index,:) = engineY.reynoldsIndex(:).';
    log.reynoldsFlowMultiplier(index,:) = ...
        engineY.reynoldsFlowMultiplier(:).';
    log.reynoldsEfficiencyMultiplier(index,:) = ...
        engineY.reynoldsEfficiencyMultiplier(:).';
    log.reynoldsClampedLow(index,:) = engineY.reynoldsClampedLow(:).';
end
end

function log = local_store_rotor_load_log(log, index, boundary)
% 新字段仅用于飞行负载诊断，不参与控制器、执行机构或发动机状态推进。
% 关闭分支不创建任何新字段，使第 2 阶段日志结构也保持原样。
if ~isfield(boundary, 'rotorLoadEnabled') || ~boundary.rotorLoadEnabled
    return;
end
if ~isfield(log, 'kTheta')
    n = numel(log.time);
    log.kTheta = nan(n, 1);
    log.thetaCollectiveDeg = nan(n, 1);
    log.thetaWithinValidRange = false(n, 1);
    log.Npr = nan(n, 1);
    log.Qload = nan(n, 1);
    log.Pload = nan(n, 1);
    log.thetaTailDeg = nan(n, 1);
    log.tailPitchWithinValidRange = false(n, 1);
    log.tailLoadFactor = nan(n, 1);
    log.mainRotorPower = nan(n, 1);
    log.tailRotorPower = nan(n, 1);
    log.splitRotorLoadEnabled = false(n, 1);
    log.rotorLoadEnabled = false(n, 1);
end
log.kTheta(index) = boundary.kTheta;
log.thetaCollectiveDeg(index) = boundary.thetaCollectiveDeg;
log.thetaWithinValidRange(index) = boundary.thetaWithinValidRange;
log.Npr(index) = boundary.Npr;
log.Qload(index) = boundary.QloadNm;
log.Pload(index) = boundary.PloadW;
if isfield(boundary,'thetaTailDeg')
    log.thetaTailDeg(index) = boundary.thetaTailDeg;
    log.tailPitchWithinValidRange(index) = ...
        boundary.tailPitchWithinValidRange;
    log.tailLoadFactor(index) = boundary.tailLoadFactor;
    log.mainRotorPower(index) = boundary.mainRotorPowerW;
    log.tailRotorPower(index) = boundary.tailRotorPowerW;
    log.splitRotorLoadEnabled(index) = boundary.splitRotorLoadEnabled;
end
log.rotorLoadEnabled(index) = true;
end

function inletTtK = local_clearance_inlet_temperature(boundary, referenceTable)
% 飞行模式使用经C逐次校核的当前总温辅助量。其他路径保持原取值规则。
if isfield(boundary,'clearanceInletTotalTemperature_K')
    inletTtK=boundary.clearanceInletTotalTemperature_K;
    assert(isscalar(inletTtK)&&isfinite(inletTtK)&&inletTtK>0, ...
        '间隙查询入口总温必须为正的有限标量。');
elseif isfield(boundary, 'Tt1') && isscalar(boundary.Tt1) && ...
        isfinite(boundary.Tt1) && boundary.Tt1 > 0
    inletTtK = boundary.Tt1;
elseif isfield(referenceTable, 'defaultInletTotalTemperature_K') && ...
        isscalar(referenceTable.defaultInletTotalTemperature_K) && ...
        isfinite(referenceTable.defaultInletTotalTemperature_K) && ...
        referenceTable.defaultInletTotalTemperature_K > 0
    inletTtK = referenceTable.defaultInletTotalTemperature_K;
else
    error('sht:simulate:clearanceInletTemperature', ...
        '修正转速调度需要当前 Tt1 或参考表默认入口总温。');
end
end

function tf = local_optional_scalar_matches(a, b, name, tolerance)
% 可选飞行边界必须“同时不存在”或“同时存在且数值相同”。字段只在一侧
% 出现时必须使缓存失效，避免在四种进口边界模式之间错误复用。
hasA = isfield(a, name) && ~isempty(a.(name));
hasB = isfield(b, name) && ~isempty(b.(name));
if ~hasA && ~hasB
    tf = true;
    return;
end
if hasA ~= hasB || ~isscalar(a.(name)) || ~isscalar(b.(name)) || ...
        ~isfinite(a.(name)) || ~isfinite(b.(name))
    tf = false;
    return;
end
tf = abs(a.(name) - b.(name)) <= tolerance;
end

function n = local_numel_field(s, name)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    n = numel(s.(name));
else
    n = 0;
end
end

function [xNext, wfNext, engineEvalNext, engineDiag, actDiag] = local_integrate_cascade( ...
    engine, x, wf, wfCommandNow, boundary, engineEval, cfg, time_s)
% 连续对象积分统一放在主仿真文件中，便于阅读真实物理对象推进顺序。
% 控制器、执行器、发动机、传感器虽然代码上分模块，但物理因果顺序在这里显式串联。
% 因果级联分区积分。
%
% 1) 执行器先以 WfcmdNow 为保持输入，从 Wf_k 推进到 Wf_{k+1}；
% 2) 发动机使用 Wf_k 和 Wf_{k+1} 端点燃油量做二阶欧拉推进；
% 3) 修正后的发动机 k+1 端点评估返回给主循环，供传感器端点积分和下一步缓存。

if ~local_engine_eval_matches(engineEval, x, wf, boundary)
    engineEval = local_engine_eval(engine, x, wf, boundary);
end

% k 端点导数：发动机导数来自缓存，避免在同一状态下重复调用 DLL。
xDot1 = engineEval.xDot;
y1 = engineEval.y;
engineDiag1 = engineEval.diag;
[wfDot1, actDiag1] = sht_actuator_derivative(wf, wfCommandNow, cfg.actuator);

% euler2 对应显式梯形/Heun：先用 k 端点导数预测，再在预测端点评估导数并取平均。
% euler1 则只用 k 端点导数，主要作为数值对照和快速调试选项。
if strcmpi(cfg.integrationMethod, 'euler2')
    wfPred = wf + cfg.Tsim * wfDot1;
    [wfDot2, actDiag2] = sht_actuator_derivative(wfPred, wfCommandNow, cfg.actuator);
    wfNext = wf + 0.5 * cfg.Tsim * (wfDot1 + wfDot2);
    wfNext = min(max(wfNext, cfg.actuator.wfMin), cfg.actuator.wfMax);

    % 发动机预测端点使用已经预测出的 Wf_{k+1}，体现执行器 -> 发动机的因果级联。
    xPred = x + cfg.Tsim * xDot1;
    boundaryPredictor = local_refresh_state_dependent_boundary( ...
        cfg, boundary, xPred, time_s + cfg.Tsim);
    engineEvalPredictor = local_engine_eval(engine, xPred, wfNext, boundaryPredictor);
    xNext = x + 0.5 * cfg.Tsim * (xDot1 + engineEvalPredictor.xDot);
    boundaryNext = local_refresh_state_dependent_boundary( ...
        cfg, boundary, xNext, time_s + cfg.Tsim);
    engineEvalNext = local_engine_eval(engine, xNext, wfNext, boundaryNext);

    predictorDiag = engineEvalPredictor.diag;
    actDiag = actDiag2;
else
    wfNext = wf + cfg.Tsim * wfDot1;
    wfNext = min(max(wfNext, cfg.actuator.wfMin), cfg.actuator.wfMax);
    xNext = x + cfg.Tsim * xDot1;
    boundaryNext = local_refresh_state_dependent_boundary( ...
        cfg, boundary, xNext, time_s + cfg.Tsim);
    engineEvalNext = local_engine_eval(engine, xNext, wfNext, boundaryNext);

    predictorDiag = engineDiag1;
    actDiag = actDiag1;
end

engineDiag = engineEvalNext.diag;
engineDiag.predictor = predictorDiag;
engineDiag.firstEval = engineDiag1;
engineDiag.firstOutput = y1;
actDiag.firstEval = actDiag1;
actDiag.wfStart = wf;
actDiag.wfEnd = wfNext;
actDiag.wfCommand = wfCommandNow;
actDiag.wfCommandNow = wfCommandNow;
end

function state = local_align_full_controller_initial_state( ...
        state, controllerCfg, initialSample)
% 使用 t=0 的实际测量样本初始化离散差分和保护记忆量。
% 传感器偏置在一次试车内从开始即已存在；若仍用无误差设计值初始化，
% 控制器会把首个采样的固定偏置误认为一次真实突变。
state.NpPrev = initialSample.Np;
state.NgPrev = initialSample.Ng;
state.NgFilterState = initialSample.Ng;
state.z2NgPrev = -state.WfFilterState * controllerCfg.linearModel.b21;
state.z2Ng = state.z2NgPrev;

ngMax = controllerCfg.ngProtection.ngMax;
state.NgTopCommandErrorPrev = ngMax - initialSample.Ng;
state.NgTopErrorPrev = state.NgTopCommandErrorPrev;

state.T45Prev = initialSample.T45;
state.T45CommandErrorPrev = ...
    controllerCfg.t45Protection.t45Max - initialSample.T45;
state.MkpPrev = initialSample.Mkp;
state.MkpCommandErrorPrev = ...
    controllerCfg.mkpProtection.mkpMax - initialSample.Mkp;
end
