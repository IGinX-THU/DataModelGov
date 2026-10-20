function [inputEstimate, info] = sht_first_order_foh_inverse( ...
        measuredDynamicOutput, time, tau)
%SHT_FIRST_ORDER_FOH_INVERSE 对FOH一阶传感器模型执行递推逆补偿。
%
% 正向模型为
%   y(k)=a*y(k-1)+bNow*u(k-1)+bNext*u(k)。
% 给定动态输出y后，逐点恢复输入u。首点缺少前一时刻信息，采用
% u(1)=y(1)。实际测量含白噪声时，应先按既定预处理方案平滑，避免
% 逆动态放大高频噪声。

time = time(:);
wasVector = isvector(measuredDynamicOutput);
if wasVector
    measuredDynamicOutput = measuredDynamicOutput(:);
end
if size(measuredDynamicOutput, 1) ~= numel(time) || isempty(time) || ...
        any(~isfinite(time)) || any(diff(time) <= 0) || ...
        any(~isfinite(measuredDynamicOutput(:)))
    error('SHT:SensorFOH:InvalidInverseInput', ...
        'time必须严格递增，且与有限的测量动态输出时间维一致。');
end

nChannel = size(measuredDynamicOutput, 2);
tau = tau(:).';
if isscalar(tau)
    tau = repmat(tau, 1, nChannel);
elseif numel(tau) ~= nChannel
    error('SHT:SensorFOH:InverseChannelSizeMismatch', ...
        'tau必须是标量或包含%d个通道值。', nChannel);
end

inputEstimate = measuredDynamicOutput;
active = isfinite(tau) & tau > 0;
minimumCurrentWeight = Inf;
maximumCurrentWeight = 0;
for k = 2:numel(time)
    if any(active)
        [a, bNow, bNext] = sht_first_order_foh_coefficients( ...
            time(k) - time(k - 1), tau(active));
        if any(bNext <= eps)
            error('SHT:SensorFOH:SingularInverse', ...
                'FOH当前样本输入权重过小，无法稳定执行逆动态补偿。');
        end
        inputEstimate(k, active) = ...
            (measuredDynamicOutput(k, active) - ...
             a .* measuredDynamicOutput(k - 1, active) - ...
             bNow .* inputEstimate(k - 1, active)) ./ bNext;
        minimumCurrentWeight = min(minimumCurrentWeight, min(bNext));
        maximumCurrentWeight = max(maximumCurrentWeight, max(bNext));
    end
end

if ~any(active)
    minimumCurrentWeight = NaN;
    maximumCurrentWeight = NaN;
end
info = struct('discretization', 'FOH', ...
    'minimumCurrentInputWeight', minimumCurrentWeight, ...
    'maximumCurrentInputWeight', maximumCurrentWeight);
if wasVector
    inputEstimate = inputEstimate(:);
end
end
