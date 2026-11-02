function filtered = sht_first_order_foh_filter(time, rawValue, tau, initialOutput)
%SHT_FIRST_ORDER_FOH_FILTER 使用FOH精确离散模型处理完整时间历程。
%
% rawValue的每一列代表一个通道；tau可以是标量或与通道数相同的
% 行/列向量。tau<=0的通道保持直通。initialOutput省略时取首个真值。

if nargin < 4 || isempty(initialOutput)
    initialOutput = rawValue(1, :);
end
time = time(:);
if isvector(rawValue)
    rawValue = rawValue(:);
end
if size(rawValue, 1) ~= numel(time) || isempty(time) || ...
        any(~isfinite(time)) || any(diff(time) <= 0) || ...
        any(~isfinite(rawValue(:)))
    error('SHT:SensorFOH:InvalidFilterInput', ...
        'time必须严格递增，且与有限的rawValue时间维一致。');
end

nChannel = size(rawValue, 2);
tau = local_expand_channel_value(tau, nChannel, 'tau');
initialOutput = local_expand_channel_value(initialOutput, nChannel, ...
    'initialOutput');
if any(~isfinite(initialOutput))
    error('SHT:SensorFOH:InvalidInitialOutput', ...
        'initialOutput必须为有限值。');
end

filtered = NaN(size(rawValue));
filtered(1, :) = initialOutput;
active = isfinite(tau) & tau > 0;
for k = 2:numel(time)
    filtered(k, ~active) = rawValue(k, ~active);
    if any(active)
        [a, bNow, bNext] = sht_first_order_foh_coefficients( ...
            time(k) - time(k - 1), tau(active));
        filtered(k, active) = a .* filtered(k - 1, active) + ...
            bNow .* rawValue(k - 1, active) + ...
            bNext .* rawValue(k, active);
    end
end
end

function value = local_expand_channel_value(value, nChannel, name)
value = value(:).';
if isscalar(value)
    value = repmat(value, 1, nChannel);
elseif numel(value) ~= nChannel
    error('SHT:SensorFOH:ChannelSizeMismatch', ...
        '%s必须是标量或包含%d个通道值。', name, nChannel);
end
end
