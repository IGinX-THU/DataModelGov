function [nuMkpMax, diagInfo] = sht_mkp_protection_limiter( ...
    candidate, state, cfg, dt)
%SHT_MKP_PROTECTION_LIMITER 计算 Mkp 负载扭矩保护的燃油增量上限。
% Mkp 是 PT 负载/输出轴传递扭矩测量值。d41 保留为燃油对 PT 驱动
% 扭矩能力的局部灵敏度，用于把扭矩裕度换算成燃油控制权；二者物理
% 含义不同，不能再把 DLL 内部 LPS_Trq 直接当作 Mkp 反馈。

mkp = local_get_field(candidate, 'Mkp', cfg.initial.Mkp);
nuMain = local_get_field(candidate, 'Nu_main', 0);
protCfg = cfg.mkpProtection;

mkpMax = local_get_field(protCfg, 'mkpMax', inf);
enabled = local_get_field(protCfg, 'enable', true);
mkpRef = mkpMax;

commandError = mkpRef - mkp;
mkpPrev = local_get_field(state, 'MkpPrev', mkp);
if ~isfinite(mkpPrev)
    mkpPrev = mkp;
end
mkpDelta = mkp - mkpPrev;

[errorGain, scheduleError, scheduleValue, scheduleLookupError] = local_mkp_gain_schedule(commandError, protCfg);
scale = local_mkp_nu_scale(dt, cfg);
errorGainNu = errorGain * scale;

if ~enabled
    nuMkpMax = inf;
else
    nuMkpMax = errorGainNu * commandError;
end

tol = 1e-12;
active = logical(enabled) && isfinite(nuMkpMax) ...
    && nuMkpMax < nuMain - tol;

diagInfo = struct();
diagInfo.enable = logical(enabled);
diagInfo.Mkp = mkp;
diagInfo.MkpMax = mkpMax;
diagInfo.MkpRef = mkpRef;
diagInfo.MkpCommandError = commandError;
diagInfo.MkpCommandErrorPrev = local_get_field(state, ...
    'MkpCommandErrorPrev', 0);
diagInfo.MkpDelta = mkpDelta;
diagInfo.MkpControlLaw = 'v5_2_gainScheduledP';
diagInfo.MkpErrorGain = errorGain;
diagInfo.MkpErrorGainNu = errorGainNu;
diagInfo.MkpGainScheduleError = abs(commandError);
diagInfo.MkpGainScheduleK = errorGain;
diagInfo.MkpGainScheduleLookupError = scheduleLookupError;
diagInfo.MkpGainScheduleErrorGrid = scheduleError;
diagInfo.MkpGainScheduleKGrid = scheduleValue;
diagInfo.MkpNuScale = scale;
diagInfo.MkpD41 = cfg.linearModel.d41;
diagInfo.Nu_Mkp_max = nuMkpMax;
diagInfo.mkpProtectionActive = active;
diagInfo.mkpProtectionSelected = false;
end

function scale = local_mkp_nu_scale(dt, cfg)
if cfg.linearModel.d41 ~= 0
    scale = dt * cfg.linearModel.b21 / cfg.linearModel.d41;
else
    scale = NaN;
end
end

function [gain, scheduleError, scheduleValue, scheduleLookupError] = local_mkp_gain_schedule(commandError, protCfg)
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
