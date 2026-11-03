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

[errorGain, scheduleError, scheduleValue, scheduleLookupError] = local_t45_gain_schedule(commandError, protCfg);
scale = local_t45_nu_scale(dt, cfg);
errorGainNu = errorGain * scale;

if ~enabled
    nuT45Max = inf;
else
    nuT45Max = errorGainNu * commandError;
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