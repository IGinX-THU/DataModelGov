function [nuT45Max, diagInfo] = sht_t45_protection_limiter( ...
    candidate, state, cfg, dt)
%SHT_T45_PROTECTION_LIMITER 计算 T45 温度保护在 Nu 域给出的上限候选。
% 复用 V5_2 的全域变增益比例式：
%   K = interp1(gainScheduleError, gainScheduleValue, abs(T45Max-T45))
%   Nu_T45_max = (T45Max-T45)*K*Tctrl*b21/d31
% 本函数不包含自由误差带和额外启用裕度，是否真正接管由完整控制器统一低选决定。

t45 = local_get_field(candidate, 'T45', cfg.initial.T45);
nuMain = local_get_field(candidate, 'Nu_main', 0);
protCfg = cfg.t45Protection;

t45Max = local_get_field(protCfg, 't45Max', inf);
enabled = local_get_field(protCfg, 'enable', true);
t45Ref = t45Max;

commandError = t45Ref - t45;
t45Prev = local_get_field(state, 'T45Prev', t45);
if ~isfinite(t45Prev)
    t45Prev = t45;
end
t45Delta = t45 - t45Prev;

% 普通调用缺省为零，仍严格执行原调度P。直轴小惯量全模式可显式启用
% 升温趋势超前，抵偿既有指令排队及执行器响应；不改变物理温度限值。
% 只用当前/上一控制拍测量，不读取未来值。降温时不借超前项额外加油。
leadTime = local_get_field(protCfg, 'riseLeadTimeS', 0);
assert(isnumeric(leadTime) && isreal(leadTime) && isscalar(leadTime) && ...
    isfinite(leadTime) && leadTime >= 0, 'sht:controller:t45Lead', ...
    '温限riseLeadTimeS必须为有限非负标量，单位s。');
controlError = commandError;
if leadTime > 0
    assert(isfinite(dt) && dt > 0 && isfinite(t45), 'sht:controller:t45Lead', ...
        '启用温升超前需要正控制周期和有限温度测量。');
    riseRate = max(0, t45Delta / dt);
    controlError = commandError - leadTime * riseRate;
end

[errorGain, scheduleError, scheduleValue, scheduleLookupError] = local_t45_gain_schedule(commandError, protCfg);
scale = local_t45_nu_scale(dt, cfg);
errorGainNu = errorGain * scale;

if ~enabled
    nuT45Max = inf;
else
    nuT45Max = errorGainNu * controlError;
end

tol = 1e-12;
active = logical(enabled) && isfinite(nuT45Max) ...
    && nuT45Max < nuMain - tol;

diagInfo = struct();
diagInfo.enable = logical(enabled);
diagInfo.T45 = t45;
diagInfo.T45Max = t45Max;
diagInfo.T45Ref = t45Ref;
diagInfo.T45ActivationMargin = 0;
diagInfo.T45FreeErrorBand = NaN;
diagInfo.T45CommandError = commandError;
diagInfo.T45CommandErrorPrev = local_get_field(state, ...
    'T45CommandErrorPrev', 0);
diagInfo.T45Delta = t45Delta;
diagInfo.T45ControlLaw = 'v5_2_gainScheduledP';
diagInfo.T45ErrorGain = errorGain;
diagInfo.T45ErrorGainNu = errorGainNu;
diagInfo.T45ScaledErrorGainNu = errorGainNu;
diagInfo.T45TempRateGainNu = NaN;
diagInfo.T45D31 = cfg.linearModel.d31;
diagInfo.K_TNu = NaN;
diagInfo.T45TargetOmega = NaN;
diagInfo.T45TargetZeta = NaN;
diagInfo.T45GainScheduleError = abs(commandError);
diagInfo.T45GainScheduleK = errorGain;
diagInfo.T45GainScheduleLookupError = scheduleLookupError;
diagInfo.T45GainScheduleErrorGrid = scheduleError;
diagInfo.T45GainScheduleKGrid = scheduleValue;
diagInfo.T45NuScale = scale;
diagInfo.Nu_T45_max = nuT45Max;
diagInfo.t45ProtectionActive = active;
diagInfo.t45ProtectionSelected = false;
if leadTime > 0
    diagInfo.T45ControlLaw = 'gainScheduledP_positiveRiseLead';
    diagInfo.T45LeadTimeS = leadTime;
    diagInfo.T45RiseRateKPerS = riseRate;
    diagInfo.T45AnticipatedK = t45 + leadTime * riseRate;
    diagInfo.T45ControlError = controlError;
    diagInfo.T45TempRateGainNu = errorGainNu * leadTime;
end
end

function scale = local_t45_nu_scale(dt, cfg)
if cfg.linearModel.d31 ~= 0
    scale = dt * cfg.linearModel.b21 / cfg.linearModel.d31;
else
    scale = NaN;
end
end

function [gain, scheduleError, scheduleValue, scheduleLookupError] = local_t45_gain_schedule(commandError, protCfg)
scheduleError = local_get_field(protCfg, 'gainScheduleError', ...
    [0 5 10 20 50 100 1000]);
scheduleValue = local_get_field(protCfg, 'gainScheduleValue', ...
    [4 4 8 12 16 20 24]);
scheduleLookupError = min(max(abs(commandError), scheduleError(1)), ...
    scheduleError(end));
gain = interp1(scheduleError, scheduleValue, scheduleLookupError, ...
    'linear', 'extrap');
end

function value = local_get_field(s, name, defaultValue)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end
