function [a, bNow, bNext] = sht_first_order_foh_coefficients(dt, tau)
%SHT_FIRST_ORDER_FOH_COEFFICIENTS 连续一阶系统的FOH精确离散系数。
%
% 对连续系统
%   tau*dx/dt + x = u
% 假定输入在一个采样区间内由u(k)线性变化到u(k+1)，则
%   x(k+1) = a*x(k) + bNow*u(k) + bNext*u(k+1)。
%
% dt可以是标量，也可以与tau同尺寸。tau必须为有限正值，dt必须为
% 有限非负值。函数保留输入数组形状，便于同时处理多个传感器通道。

if isempty(dt) || isempty(tau) || ~isnumeric(dt) || ~isnumeric(tau)
    error('SHT:SensorFOH:InvalidCoefficientInput', ...
        'dt和tau必须是非空数值。');
end
if any(~isfinite(dt(:))) || any(dt(:) < 0)
    error('SHT:SensorFOH:InvalidSampleTime', ...
        'dt必须为有限非负值。');
end
if any(~isfinite(tau(:))) || any(tau(:) <= 0)
    error('SHT:SensorFOH:InvalidTimeConstant', ...
        'tau必须为有限正值。');
end
if ~(isscalar(dt) || isscalar(tau) || isequal(size(dt), size(tau)))
    error('SHT:SensorFOH:CoefficientSizeMismatch', ...
        'dt和tau必须至少有一个为标量，或者二者尺寸相同。');
end

r = dt ./ tau;
a = exp(-r);
bNow = zeros(size(r));
bNext = zeros(size(r));

% r很小时，直接计算权重会出现相近数相减。采用四阶级数避免
% 浮点消减；常规范围使用expm1提高1-exp(-r)的计算精度。
small = r < 1e-4;
if any(small(:))
    rs = r(small);
    bNow(small) = rs ./ 2 - rs.^2 ./ 3 + rs.^3 ./ 8 - rs.^4 ./ 30;
    bNext(small) = rs ./ 2 - rs.^2 ./ 6 + rs.^3 ./ 24 - rs.^4 ./ 120;
end
if any(~small(:))
    rr = r(~small);
    meanWeight = -expm1(-rr) ./ rr;
    bNow(~small) = meanWeight - a(~small);
    bNext(~small) = 1 - meanWeight;
end
end
