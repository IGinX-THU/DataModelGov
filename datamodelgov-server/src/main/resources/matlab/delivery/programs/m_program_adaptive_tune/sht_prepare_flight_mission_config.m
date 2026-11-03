function prepared = sht_prepare_flight_mission_config(baseCfg, mission, health)
%SHT_PREPARE_FLIGHT_MISSION_CONFIG 为单条飞行任务独立配平并生成运行配置。
%
% prepared = sht_prepare_flight_mission_config(baseCfg, mission, health)
%
% 本函数实现第 3.1 阶段 S5 的单任务配置边界。它以已经冻结设计基准的
% mission 为输入，在该任务 t=0 的 Pt1/Tt1/Pamb、总距角、旋翼负载和
% 附件功率下独立配平，然后把配平结果写回两状态时域运行初值。函数不
% 推进仿真时间，不在任务之间传递末状态，也不启用热沉浸或动态间隙。

if nargin ~= 3 || ~isstruct(baseCfg) || ~isscalar(baseCfg) || ...
        ~isstruct(mission) || ~isscalar(mission) || ...
        ~isnumeric(health) || ~isreal(health) || numel(health) ~= 100 || ...
        any(~isfinite(health(:)))
    error('sht:flightMissionTrim:badInput', ...
        '需要标量 baseCfg、标量 mission 和有限的 100 维健康向量。');
end

missionRequired = {'id','definition','runtimeBoundarySchedule','schedule'};
local_require_fields(mission, missionRequired, 'mission');
runtime = mission.runtimeBoundarySchedule;
if ~isstruct(runtime) || ~isscalar(runtime) || ...
        ~all(isfield(runtime, {'enabled','mission','model'})) || ...
        ~local_logical_scalar(runtime.enabled, ...
        'mission.runtimeBoundarySchedule.enabled')
    error('sht:flightMissionTrim:badRuntimeBoundary', ...
        '任务必须给出已启用的 runtimeBoundarySchedule。');
end
if ~istable(mission.schedule)
    error('sht:flightMissionTrim:badSchedule', ...
        'mission.schedule 必须是统一飞行任务时间表。');
end
scheduleRequired = {'time_s','NpCommand_rpm','expectedPload_W'};
if ~all(ismember(scheduleRequired, mission.schedule.Properties.VariableNames))
    error('sht:flightMissionTrim:missingScheduleField', ...
        '任务时间表缺少 time_s、NpCommand_rpm 或 expectedPload_W。');
end

time_s = mission.schedule.time_s(:);
if numel(time_s) < 2 || any(~isfinite(time_s)) || ...
        abs(time_s(1)) > 1e-12 || any(diff(time_s) <= 0)
    error('sht:flightMissionTrim:badTimeGrid', ...
        '任务时间轴必须从 0 s 开始并严格递增。');
end
sampleTime_s = median(diff(time_s));
timeTolerance = 100 * eps(max(1, time_s(end)));
if any(abs(diff(time_s) - sampleTime_s) > timeTolerance) || ...
        abs(time_s(end) - runtime.mission.duration_s) > timeTolerance
    error('sht:flightMissionTrim:nonuniformTimeGrid', ...
        'S5 要求任务时间轴等步长且终点等于任务时长。');
end

targetNpRpm = runtime.model.designNpRpm;
local_assert_positive_scalar(targetNpRpm, ...
    'runtimeBoundarySchedule.model.designNpRpm');
initialBoundary = sht_flight_boundary_step( ...
    0, targetNpRpm, runtime.mission, runtime.model);
designPowerW = runtime.model.designTorqueNm * targetNpRpm * pi / 30;
expectedInitialPowerW = designPowerW * initialBoundary.kTheta;
powerScale = max(1, abs(expectedInitialPowerW));
if abs(initialBoundary.Npr - 1) > 1e-12 || ...
        abs(initialBoundary.Pload_W - expectedInitialPowerW) > ...
        1e-12 * powerScale
    error('sht:flightMissionTrim:initialLoadMismatch', ...
        'Np=Np_design 时初始负载必须满足 Pload=P0*kTheta。');
end

cfg = baseCfg;
cfg.stopTime = runtime.mission.duration_s;
cfg.Tsim = sampleTime_s;
cfg.Tctrl = sampleTime_s;
cfg.plot.enable = false;

% 首轮严格保持两状态、零传感器误差和无三类瞬态增强模型。数据资产仍
% 采用原100维健康真值；进入当前DLL前，按显式接口长度在尾部补零。
if isfield(cfg.engine, 'transientEffects')
    cfg.engine = rmfield(cfg.engine, 'transientEffects');
end
cfg.sensor.mode = 'identity';
cfg.sensor.timeConstant = 0;
cfg.sensor.bias = zeros(numel(cfg.sensor.channels), 1);
cfg.sensor.noiseStd = zeros(numel(cfg.sensor.channels), 1);

interfaceHealthLength = cfg.engine.interface.healthLength;
if ~isscalar(interfaceHealthLength) || ~isfinite(interfaceHealthLength) || ...
        interfaceHealthLength < numel(health) || ...
        interfaceHealthLength ~= floor(interfaceHealthLength)
    error('sht:flightMissionTrim:badHealthInterfaceLength', ...
        'DLL健康接口长度必须是且至少为100的有限正整数。');
end
interfaceHealth = zeros(interfaceHealthLength, 1);
interfaceHealth(1:numel(health)) = health(:);

% 配平与运行必须共享完全相同的物理边界。theta/kTheta/Qload 是配置
% 诊断字段；M 层逐点将 Mkp/Mkg 与当前轴转速换算为 DLL 的功率输入。
cfg.engine.boundary.health = interfaceHealth;
cfg.engine.boundary.Pt1 = initialBoundary.Pt1_Pa;
cfg.engine.boundary.Tt1 = initialBoundary.Tt1_K;
cfg.engine.boundary.Pamb = initialBoundary.Pamb_Pa;
cfg.engine.boundary.power = initialBoundary.Pload_W;
cfg.engine.boundary.hpsPower = initialBoundary.hpsPower_W;
cfg.engine.boundary.theta_deg = initialBoundary.theta_deg;
cfg.engine.boundary.kTheta = initialBoundary.kTheta;
cfg.engine.boundary.Qload_Nm = initialBoundary.Qload_Nm;

% S4 在每个积分子阶段读取该调度。参考模块只负责 Np 指令；功率时间表
% 仍完整写入以保持日志语义，但启用 S4 后不会覆盖 theta-Np 负载边界。
cfg.flight = struct('boundarySchedule', runtime);
cfg.reference.commandMode = 'schedule';
cfg.reference.baseNp = targetNpRpm;
cfg.reference.powerBase = initialBoundary.Pload_W;
cfg.reference.scheduleTime_s = time_s;
cfg.reference.scheduleNp_rpm = mission.schedule.NpCommand_rpm(:);
cfg.reference.schedulePower_W = mission.schedule.expectedPload_W(:);
cfg = sht_validate_runtime_config(cfg);

if numel(cfg.engine.initial.state) ~= 2 || ...
        ~isequal(cfg.engine.stateNames, {'Np','Ng'})
    error('sht:flightMissionTrim:stateCount', ...
        'S5 必须使用严格的 [Np; Ng] 两状态模型。');
end

trim = sht_trim_health_steady_point( ...
    cfg, targetNpRpm, initialBoundary.Pload_W, interfaceHealth);
if ~trim.converged
    error('sht:flightMissionTrim:notConverged', ...
        '%s 的独立稳态配平未收敛。', mission.id);
end

finiteTrim = [trim.Np, trim.Ng, trim.Wf, trim.T45, trim.Pt45, ...
    trim.Mkp, trim.Mkg, trim.maxErr, trim.residualInfinityNorm];
if trim.ret ~= 0 || any(~isfinite(finiteTrim))
    error('sht:flightMissionTrim:nonfiniteTrimOutput', ...
        '%s 的最终 DLL 配平调用返回错误或非有限输出。', mission.id);
end

% 配平后只更新运行初值，不反向修改任务已经冻结的设计转速、设计功率和
% 设计转矩。Mkp/Mkg 是边界输入，其初值与独立配平点保持一致。
cfg.engine.initial.Np0 = trim.Np;
cfg.engine.initial.Ng0 = trim.Ng;
cfg.engine.initial.Wf0 = trim.Wf;
cfg.engine.initial.T45 = trim.T45;
cfg.engine.initial.Mkp = trim.Mkp;
cfg.engine.initial.Mkg = trim.Mkg;
cfg.engine.initial.power0 = initialBoundary.Pload_W;
cfg.engine.initial.state = [trim.Np; trim.Ng];
cfg.engine.boundary.power = initialBoundary.Pload_W;
cfg.reference.baseNp = trim.Np;
cfg.reference.baseNg = trim.Ng;
cfg.reference.powerBase = initialBoundary.Pload_W;
cfg = sht_validate_runtime_config(cfg);

runtimeInitialBoundary = sht_flight_boundary_step( ...
    0, trim.Np, runtime.mission, runtime.model);
npErrorRpm = abs(trim.Np - targetNpRpm);
runtimePowerMismatchW = abs( ...
    runtimeInitialBoundary.Pload_W - initialBoundary.Pload_W);
powerToleranceW = max(1e-3, 1e-6 * initialBoundary.Pload_W);
validationPassed = trim.converged && trim.ret == 0 && ...
    npErrorRpm <= 0.5 && trim.maxErr <= 0.01 && ...
    runtimePowerMismatchW <= powerToleranceW && ...
    numel(cfg.engine.initial.state) == 2 && ...
    isequal(cfg.engine.boundary.health(:), interfaceHealth) && ...
    cfg.engine.boundary.hpsPower == initialBoundary.hpsPower_W;
if ~validationPassed
    error('sht:flightMissionTrim:validationFailed', ...
        ['%s 的 S5 验收失败：Np误差=%.6g rpm，运行初始功率偏差=' ...
         '%.6g W，maxErr=%.6g。'], mission.id, npErrorRpm, ...
        runtimePowerMismatchW, trim.maxErr);
end

prepared = struct();
prepared.stage = '3.1-S5';
prepared.missionId = mission.id;
prepared.config = cfg;
prepared.trim = trim;
prepared.initialBoundary = initialBoundary;
prepared.runtimeInitialBoundary = runtimeInitialBoundary;
prepared.health = health(:);
prepared.interfaceHealth = interfaceHealth;
prepared.validation = struct( ...
    'passed', validationPassed, ...
    'trimConverged', trim.converged, ...
    'dllReturnCode', trim.ret, ...
    'dllConvergeTag', trim.convergeTag, ...
    'targetNpRpm', targetNpRpm, ...
    'npErrorRpm', npErrorRpm, ...
    'residualInfinityNorm', trim.residualInfinityNorm, ...
    'maxEngineResidual', trim.maxErr, ...
    'initialLoadPowerW', initialBoundary.Pload_W, ...
    'runtimeInitialLoadPowerW', runtimeInitialBoundary.Pload_W, ...
    'runtimePowerMismatchW', runtimePowerMismatchW, ...
    'hpsPowerW', initialBoundary.hpsPower_W, ...
    'stateCount', numel(cfg.engine.initial.state), ...
    'healthNonzeroCount', nnz(health));
end

function local_require_fields(value, names, valueName)
for i = 1:numel(names)
    if ~isfield(value, names{i})
        error('sht:flightMissionTrim:missingField', ...
            '%s 缺少字段 %s。', valueName, names{i});
    end
end
end

function value = local_logical_scalar(value, name)
if ~(islogical(value) || isnumeric(value)) || ~isscalar(value) || ...
        ~isfinite(value) || ~(value == 0 || value == 1)
    error('sht:flightMissionTrim:badSwitch', ...
        '%s 必须是数值为 0 或 1 的有限标量开关。', name);
end
value = logical(value);
end

function local_assert_positive_scalar(value, name)
if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
        ~isfinite(value) || value <= 0
    error('sht:flightMissionTrim:badPositiveScalar', ...
        '%s 必须是有限正标量。', name);
end
end
