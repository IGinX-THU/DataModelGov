function [nuNgTopMax, diagInfo] = sht_ng_protection_limiter( ...
    candidate, state, cfg, dt)
%SHT_NG_PROTECTION_LIMITER 计算 Ng 超转保护在 Nu 域给出的上限候选。
% 控制律：
%   e_NgTop(k)=NgMax-Ng(k)
%   Nu_NgTop_max=K_e*Tctrl*e_NgTop(k)+K_de*(e_NgTop(k)-e_NgTop(k-1))
% 其中 e_NgTop(k-1) 的初值为 NgMax-Ng0，对应 V5_2 Unit Delay 初值。

ng = local_get_field(candidate, 'Ng', cfg.initial.Ng);
nuMain = local_get_field(candidate, 'Nu_main', 0);
protCfg = cfg.ngProtection;

ngMax = local_get_field(protCfg, 'ngMax', 1.05 * cfg.DPpara.Ng0);
enabled = local_get_field(protCfg, 'enable', true);
ngRef = ngMax;

commandError = ngRef - ng;
commandErrorPrev = local_get_field(state, 'NgTopCommandErrorPrev', ...
    ngRef - cfg.initial.Ng);
commandErrorDelta = commandError - commandErrorPrev;

errorGain = local_get_field(protCfg, 'errorGain', 4);
errorDeltaGain = local_get_field(protCfg, 'errorDeltaGain', 2);

if ~enabled
    nuNgTopMax = inf;
else
    nuNgTopMax = errorGain * dt * commandError ...
        + errorDeltaGain * commandErrorDelta;
end

tol = 1e-12;
active = logical(enabled) && isfinite(nuNgTopMax) ...
    && nuNgTopMax < nuMain - tol;

diagInfo = struct();
diagInfo.enable = logical(enabled);
diagInfo.Ng = ng;
diagInfo.NgMax = ngMax;
diagInfo.NgTopRef = ngRef;
diagInfo.NgTopError = ng - ngMax;
diagInfo.NgTopProtectionError = ng - ngRef;
diagInfo.NgTopCommandError = commandError;
diagInfo.NgTopCommandErrorPrev = commandErrorPrev;
diagInfo.NgTopCommandErrorDelta = commandErrorDelta;
diagInfo.NgTopErrorGain = errorGain;
diagInfo.NgTopErrorDeltaGain = errorDeltaGain;
diagInfo.NgTopKp = NaN;
diagInfo.NgTopControlLaw = 'v5_2_errorDelta';
diagInfo.NgTopActivationMargin = 0;
diagInfo.Nu_NgTop_max = nuNgTopMax;
diagInfo.ngTopProtectionActive = active;
diagInfo.ngTopProtectionSelected = false;
end

function value = local_get_field(s, name, defaultValue)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end