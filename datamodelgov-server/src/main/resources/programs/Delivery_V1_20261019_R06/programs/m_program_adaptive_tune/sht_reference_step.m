function [ref, state] = sht_reference_step(state, cfg, dt)
% 阅读说明：
%   本文件模拟顶层指令模块：方波脉冲先形成原始 Np/负载指令，再经过一阶连续滤波。
%   参考指令不是控制器内部状态，单独放在这里便于替换操纵方式或测试工况。
% 参考指令生成模块。
%
%   NpDem 常值 + Pulse Generator + Transfer Fcn(10/(s+10)) + Sum
%
% 输出 ref.NpDem 给离散控制器；ref.power 给发动机负载边界。
% 默认 power 脉冲关闭，因为 V5_1 模型中负载脉冲支路未接入 Sum1。

if ~isfield(state, 'time')
    state.time = 0;
end
if ~isfield(state, 'npFilter')
    state.npFilter = 0;
end
if ~isfield(state, 'powerFilter')
    state.powerFilter = 0;
end

% 2.6 过渡态替代数据采用显式分段指令表。该模式直接给出每个时段的
% Np 和负载功率目标，不经过旧脉冲的一阶滤波；控制系统和燃油执行机构
% 仍按原模型响应。查询下一积分端点，使 5、10、15、20、25 s 的切换
% 精确落在日志采样点上。未显式选择 schedule 时，下面的原脉冲路径不变。
commandMode = local_get_field(cfg, 'commandMode', 'legacy');
if strcmpi(commandMode, 'schedule')
    queryTime = state.time + max(dt, 0);
    [npCommand, segmentIndex] = local_previous_schedule_value( ...
        queryTime, cfg.scheduleTime_s, cfg.scheduleNp_rpm);
    powerCommand = local_previous_schedule_value( ...
        queryTime, cfg.scheduleTime_s, cfg.schedulePower_W);

    state.time = queryTime;
    state.npFilter = npCommand - cfg.baseNp;
    state.powerFilter = powerCommand - cfg.powerBase;

    ref = struct();
    ref.NpDem = npCommand;
    ref.power = powerCommand;
    ref.scheduleSegmentIndex = segmentIndex;
    ref.commandMode = 'schedule';
    if isfield(cfg, 'baseNg') && ~isempty(cfg.baseNg)
        ref.NgDem = cfg.baseNg;
    else
        ref.NgDem = NaN;
    end
    ref = local_attach_collective_pitch_reference(ref, cfg, queryTime);
    return;
end

% 先在当前时刻生成未滤波的 Np 脉冲，再用一阶环节生成控制器看到的平滑 NpDem。
npPulse = local_pulse(state.time, cfg.npPulseAmplitude, ...
    cfg.npPulsePeriod, cfg.npPulseWidthFraction, cfg.npPulsePhaseDelay);

% 负载功率扰动预留。默认保持原来的脉冲输入；若测试显式指定 ramp，
% 则用线性斜坡描述动力涡轮轴负载连续加载/卸载过程。piecewiseRamp
% 用归一化断点描述“前慢后快”或其他非匀速功率计划。
powerCommandMode = local_get_field(cfg, 'powerCommandMode', 'pulse');
if isfield(cfg, 'enablePowerPulse') && cfg.enablePowerPulse
    switch lower(powerCommandMode)
        case 'ramp'
            powerPulse = local_ramp(state.time, cfg.powerPulseAmplitude, ...
                cfg.powerPulsePhaseDelay, cfg.powerRampDuration);
        case 'piecewiseramp'
            powerPulse = local_piecewise_ramp(state.time, ...
                cfg.powerPulseAmplitude, cfg.powerPulsePhaseDelay, ...
                cfg.powerRampDuration, cfg.powerRampTimeFraction, ...
                cfg.powerRampValueFraction);
        otherwise
            powerPulse = local_pulse(state.time, cfg.powerPulseAmplitude, ...
                cfg.powerPulsePeriod, cfg.powerPulseWidthFraction, cfg.powerPulsePhaseDelay);
    end
else
    powerPulse = 0;
end

% 指令滤波属于参考指令生成模块，不属于发动机对象或传感器对象。
state.npFilter = local_integrate_first_order( ...
    state.npFilter, npPulse, cfg.npFilterOmega, dt, state.integrationMethod);
if strcmpi(powerCommandMode, 'ramp') || strcmpi(powerCommandMode, 'piecewiseRamp')
    % 斜坡本身已经是连续负载输入；这里不再叠加一阶滤波，避免负载计划被额外滞后。
    state.powerFilter = powerPulse;
else
    state.powerFilter = local_integrate_first_order( ...
        state.powerFilter, powerPulse, cfg.powerFilterOmega, dt, state.integrationMethod);
end
state.time = state.time + dt;

ref = struct();
ref.NpDem = cfg.baseNp + state.npFilter;
ref.power = cfg.powerBase + state.powerFilter;

if isfield(cfg, 'baseNg') && ~isempty(cfg.baseNg)
    ref.NgDem = cfg.baseNg;
else
    ref.NgDem = NaN;
end
ref = local_attach_collective_pitch_reference(ref, cfg, state.time);
end

function y = local_pulse(t, amplitude, period, widthFraction, phaseDelay)
% 容差用于避免 t=2.000000 这类固定步长边界被浮点误差推后一拍。
if period <= 0 || widthFraction <= 0
    y = 0;
    return;
end
tol = 1e-10 * max([1, abs(t), abs(phaseDelay), abs(period)]);
if t < phaseDelay - tol
    y = 0;
    return;
end
tau = mod(max(t - phaseDelay, 0), period);
if tau < period * widthFraction - tol
    y = amplitude;
else
    y = 0;
end
end

function y = local_ramp(t, amplitude, phaseDelay, rampDuration)
% 线性斜坡：phaseDelay 前为 0，随后 rampDuration 内从 0 变化到 amplitude。
if rampDuration <= 0
    y = amplitude * double(t >= phaseDelay);
    return;
end
tol = 1e-10 * max([1, abs(t), abs(phaseDelay), abs(rampDuration)]);
if t < phaseDelay - tol
    y = 0;
    return;
end
tau = min(max(t - phaseDelay, 0), rampDuration);
y = amplitude * tau / rampDuration;
end

function y = local_piecewise_ramp(t, amplitude, phaseDelay, rampDuration, timeFraction, valueFraction)
% 分段线性斜坡：
%   timeFraction  是 [0,1] 内的时间断点；
%   valueFraction 是 [0,1] 内的功率增量断点；
%   输出为 amplitude*interp1(timeFraction,valueFraction,tau/rampDuration)。
% 典型用途是低负载加载初期先慢一点，避开 T45 贴边区；后半段利用温度裕度提高加载速率。
if rampDuration <= 0
    y = amplitude * double(t >= phaseDelay);
    return;
end
tol = 1e-10 * max([1, abs(t), abs(phaseDelay), abs(rampDuration)]);
if t < phaseDelay - tol
    y = 0;
    return;
end

timeFraction = timeFraction(:);
valueFraction = valueFraction(:);
tauFraction = min(max((t - phaseDelay) / rampDuration, 0), 1);
yFraction = interp1(timeFraction, valueFraction, tauFraction, 'linear');
y = amplitude * yFraction;
end

function xNext = local_integrate_first_order(x, u, omega, dt, method)
% method='euler2' 时采用 Heun 形式，尽量与连续一阶滤波器响应接近。
% 一阶环节 dx/dt=omega*(u-x)，用于参考滤波和负载滤波。
if dt <= 0 || omega <= 0
    xNext = x;
    return;
end
dx1 = omega * (u - x);
if strcmpi(method, 'euler2')
    xPred = x + dt * dx1;
    dx2 = omega * (u - xPred);
    xNext = x + 0.5 * dt * (dx1 + dx2);
else
    xNext = x + dt * dx1;
end
end

function value = local_get_field(s, name, defaultValue)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end

function [value, index] = local_previous_schedule_value(time, breakTime, breakValue)
% 分段零阶保持采用右连续定义：到达切换时刻即使用该时刻的新指令。
breakTime = breakTime(:);
breakValue = breakValue(:);
tolerance = 32 * eps(max([1; abs(time); abs(breakTime)]));
index = find(breakTime <= time + tolerance, 1, 'last');
if isempty(index)
    index = 1;
end
value = breakValue(index);
end

function ref = local_attach_collective_pitch_reference(ref, cfg, queryTime)
%LOCAL_ATTACH_COLLECTIVE_PITCH_REFERENCE 可选的直接总距角权威指令。
%
% 旧控制程序没有 collectivePitch 配置时不增加字段，保证历史轴功率模式
% 的输出结构和数值完全不变。启用后只生成 ref.thetaCollectiveDeg；旋翼
% 负载模型再根据当前 Np 计算 Mkp 和 Pload。
if ~isfield(cfg, 'collectivePitch') || isempty(cfg.collectivePitch)
    return;
end
pitch = cfg.collectivePitch;
if ~isstruct(pitch) || ~isscalar(pitch)
    error('sht:reference:badCollectivePitchConfig', ...
        'reference.collectivePitch 必须是标量结构体。');
end
enabled = local_get_field(pitch, 'enabled', false);
if ~(islogical(enabled) || isnumeric(enabled)) || ...
        ~isscalar(enabled) || ~isfinite(enabled)
    error('sht:reference:badCollectivePitchSwitch', ...
        'collectivePitch.enabled 必须是有限标量逻辑开关。');
end
if ~logical(enabled)
    return;
end

commandMode = local_get_field(pitch, 'commandMode', 'schedule');
if isstring(commandMode) && isscalar(commandMode)
    commandMode = char(commandMode);
end
if ~ischar(commandMode)
    error('sht:reference:badCollectivePitchMode', ...
        'collectivePitch.commandMode 必须为字符向量或标量字符串。');
end

switch lower(strtrim(commandMode))
    case 'constant'
        thetaDeg = local_finite_scalar_field(pitch, 'baseTheta_deg');
    case 'schedule'
        if ~isfield(pitch, 'scheduleTime_s') || ...
                ~isfield(pitch, 'scheduleTheta_deg')
            error('sht:reference:missingCollectivePitchSchedule', ...
                ['collectivePitch.schedule 模式需要 scheduleTime_s 和 ' ...
                 'scheduleTheta_deg。']);
        end
        scheduleTime = pitch.scheduleTime_s(:);
        scheduleTheta = pitch.scheduleTheta_deg(:);
        if isempty(scheduleTime) || numel(scheduleTime) ~= numel(scheduleTheta) || ...
                any(~isfinite(scheduleTime)) || any(~isfinite(scheduleTheta)) || ...
                any(diff(scheduleTime) <= 0)
            error('sht:reference:badCollectivePitchSchedule', ...
                ['总距角时间和数值节点必须等长、有限且非空，' ...
                 '时间节点必须严格递增。']);
        end
        interpolationMethod = local_get_field( ...
            pitch, 'interpolationMethod', 'linear');
        if isstring(interpolationMethod) && isscalar(interpolationMethod)
            interpolationMethod = char(interpolationMethod);
        end
        if ~ischar(interpolationMethod) || ...
                ~ismember(lower(strtrim(interpolationMethod)), {'linear', 'previous'})
            error('sht:reference:badCollectivePitchInterpolation', ...
                '总距角插值方法必须为 linear 或 previous。');
        end
        if numel(scheduleTime) == 1
            thetaDeg = scheduleTheta(1);
        else
            boundedTime = min(max(queryTime, scheduleTime(1)), scheduleTime(end));
            thetaDeg = interp1(scheduleTime, scheduleTheta, boundedTime, ...
                lower(strtrim(interpolationMethod)));
        end
    otherwise
        error('sht:reference:badCollectivePitchMode', ...
            '总距角指令模式必须为 constant 或 schedule，当前为 %s。', ...
            commandMode);
end

if ~isscalar(thetaDeg) || ~isfinite(thetaDeg)
    error('sht:reference:badCollectivePitchCommand', ...
        '本步总距角指令必须是有限标量。');
end
ref.thetaCollectiveDeg = double(thetaDeg);
ref.collectivePitchCommandMode = lower(strtrim(commandMode));
end

function value = local_finite_scalar_field(s, fieldName)
if ~isfield(s, fieldName) || ~isnumeric(s.(fieldName)) || ...
        ~isscalar(s.(fieldName)) || ~isfinite(s.(fieldName))
    error('sht:reference:badCollectivePitchValue', ...
        'collectivePitch.%s 必须是有限标量。', fieldName);
end
value = double(s.(fieldName));
end
