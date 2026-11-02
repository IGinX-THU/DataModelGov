function [dWfFinal, diagInfo] = sht_fuel_increment_saturator( ...
    dWfRaw, wfPrevious, cfg, dt)
% 阅读说明：
%   本文件是控制器侧唯一的燃油增量抗饱和入口。
%   上游所有回路最终都必须先形成一个原始燃油增量 dWfRaw，再在这里同时考虑 WfMin、WfMax 和 WfRateLimit。
%   这种集中处理避免每个限制保护回路各自设计一套执行机构抗饱和逻辑。
%SHT_FUEL_INCREMENT_SATURATOR Apply fuel actuator bounds to one increment.
%
% This is the single anti-actuator-saturation point for the controller:
% all upstream loops produce a raw fuel increment, and this function applies
% fuel min/max and rate limits consistently.


% 燃油约束来自控制器配置，通常与物理执行机构限制保持一致。
wfMin = local_get_cfg_scalar(cfg, 'wfMin', -inf);
wfMax = local_get_cfg_scalar(cfg, 'wfMax', inf);
rateLimit = local_get_cfg_scalar(cfg, 'wfRateLimit', inf);

% 速率限制先转换为一个采样周期内允许的燃油增量上下界。
if isfinite(rateLimit) && dt > 0
    dWfRateUpMax = rateLimit * dt;
    dWfRateDownMin = -rateLimit * dt;
else
    dWfRateUpMax = inf;
    dWfRateDownMin = -inf;
end

% 绝对燃油上下限和速率上下限取交集，形成最终可施加的增量区间。
dWfUpper = min(wfMax - wfPrevious, dWfRateUpMax);
dWfLower = max(wfMin - wfPrevious, dWfRateDownMin);
dWfFinal = min(max(dWfRaw, dWfLower), dWfUpper);
wfSelectedNext = wfPrevious + dWfFinal;

tol = 1e-13;
% dWf_aw_error 是执行机构饱和造成的增量损失，可作为后续抗饱和设计的统一诊断量。
diagInfo = struct();
diagInfo.dWf_raw_increment = dWfRaw;
diagInfo.dWf_final = dWfFinal;
diagInfo.dWf_aw_error = dWfFinal - dWfRaw;
diagInfo.dWf_upper_bound = dWfUpper;
diagInfo.dWf_lower_bound = dWfLower;
diagInfo.dWf_rate_up_max = dWfRateUpMax;
diagInfo.dWf_rate_down_min = dWfRateDownMin;
diagInfo.Wf_selected_next = wfSelectedNext;
diagInfo.Wf_upper_bound = wfPrevious + dWfUpper;
diagInfo.Wf_lower_bound = wfPrevious + dWfLower;
diagInfo.Wf_rate_up_max = wfPrevious + dWfRateUpMax;
diagInfo.Wf_rate_down_min = wfPrevious + dWfRateDownMin;
diagInfo.WfMin = wfMin;
diagInfo.WfMax = wfMax;
diagInfo.WfRateLimit = rateLimit;
diagInfo.fuelUpperActive = abs(dWfFinal - dWfUpper) <= tol;
diagInfo.fuelLowerActive = abs(dWfFinal - dWfLower) <= tol;
diagInfo.fuelBoundsApplied = true;
end

function value = local_get_cfg_scalar(cfg, name, defaultValue)
if isfield(cfg, name) && ~isempty(cfg.(name))
    value = cfg.(name);
else
    value = defaultValue;
end
end
