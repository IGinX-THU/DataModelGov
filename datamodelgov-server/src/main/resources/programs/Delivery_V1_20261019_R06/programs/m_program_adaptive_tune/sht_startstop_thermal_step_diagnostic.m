function diagnostic=sht_startstop_thermal_step_diagnostic(temperature,derivative,dt,rateLimit)
%SHT_STARTSTOP_THERMAL_STEP_DIAGNOSTIC 将热状态变化检查与积分步长解耦。
% 温变率是工程变化包线，不是积分误差。数值精度另用步长收敛测试检查。
% 同时记录实际相邻温差，避免把dt*dT/dt冒充Heun积分后的温差。
assert(isequal(size(temperature),size(derivative)) && ~isempty(temperature), ...
    '温度与导数必须具有相同的非空尺寸。');
assert(isscalar(dt) && isfinite(dt) && dt>0 && isscalar(rateLimit) && ...
    isfinite(rateLimit) && rateLimit>0,'步长和温变率上限必须为正有限标量。');
changes=diff(temperature,1,1);
actualStep=NaN;
if ~isempty(changes),actualStep=max(abs(changes(:)));end
diagnostic=struct('maximumDerivativeKPerS',max(abs(derivative(:))), ...
    'maximumActualStepK',actualStep,'rateLimitKPerS',rateLimit);
diagnostic.maximumSampledRateKPerS=diagnostic.maximumActualStepK/dt;
diagnostic.maximumEulerStepEstimateK=diagnostic.maximumDerivativeKPerS*dt;
diagnostic.accepted=size(temperature,1)>=2 && all(isfinite(temperature(:))) && all(isfinite(derivative(:))) && ...
    max(diagnostic.maximumDerivativeKPerS,diagnostic.maximumSampledRateKPerS)<=rateLimit;
end
