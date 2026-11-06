function [wfDot, diagInfo] = sht_actuator_derivative(wf, wfCommand, cfg)
% 阅读说明：
%   本文件描述燃油执行机构的一阶连续动态和速率限制。
%   控制器输出 WfcmdNow 在一个控制周期内保持，执行机构连续积分得到实际进入发动机的 Wf。
%SHT_ACTUATOR_DERIVATIVE Continuous fuel-metering actuator derivative.
% 燃油执行机构连续模型。
%
%   Sum3:      Wf_cmd - Wf
%   Gain:      actuator.gain，当前 V5_2 默认 25
%   Saturation: +/- actuator.wfRateLimit
%   Integrator: 初值 actuator.initialWf，输出 Wf
%
% 配置口径：
%   cfg 是 cfg.actuator 子结构，表示真实燃油执行机构物理参数；
%   控制器内部用于燃油增量抗饱和的限制位于 cfg.controller.actuatorLimitsKnown，
%   二者默认相同，但为了后续执行机构失配/故障仿真，代码层面必须分开。

% 一阶执行机构：dWf/dt = gain*(Wfcmd-Wf)，随后受物理速率限制裁剪。
gain = local_get_cfg_scalar(cfg, 'gain', 25);
rateLimit = local_get_cfg_scalar(cfg, 'wfRateLimit', inf);
rawRate = gain * (wfCommand - wf);
wfDot = min(max(rawRate, -rateLimit), rateLimit);

diagInfo = struct();
diagInfo.rawRate = rawRate;
diagInfo.limitedRate = wfDot;
diagInfo.wfCommand = wfCommand;
diagInfo.actuatorGain = gain;
diagInfo.wfRateLimit = rateLimit;
end

function value = local_get_cfg_scalar(cfg, name, defaultValue)
if isstruct(cfg) && isfield(cfg, name) && ~isempty(cfg.(name))
    value = cfg.(name);
else
    value = defaultValue;
end
end
