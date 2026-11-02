function [state,reference]=sht_startstop_start_reference(state,sample,timeS,cfg)
%SHT_STARTSTOP_START_REFERENCE Ng起动升速和稳定慢车暖机许可。
% 不给Np施加起动速度约束；其变化由轴动力学和旋翼负载共同决定。
% 起动机切除后采用连续初始Ng及其变化率，避免下一拍突然要求零加速。
s=cfg.stage6;
if isempty(state)
    distance=s.startupIdleNgRpm-sample.Ng;
    velocity=sample.NgDot;
    duration=s.idleCaptureRampS;
    if distance>0 && velocity>0
        % 三次Hermite在此范围内单调；不让参考本身人为超过目标。
        duration=min(duration,2*distance/velocity);
    end
    duration=max(duration,cfg.aboveIdle.sampleTimeS);
    state=struct('startTimeS',timeS,'startNpRpm',sample.Np, ...
        'startNgRpm',sample.Ng,'startNgDot',velocity, ...
        'durationS',duration,'stableStartTimeS',NaN,'firstStableTimeS',NaN,'ready',false);
end
elapsed=max(timeS-state.startTimeS,0);
z=min(elapsed/state.durationS,1);
distance=s.startupIdleNgRpm-state.startNgRpm;
ng=state.startNgRpm+(3*z^2-2*z^3)*distance+ ...
    state.durationS*state.startNgDot*(z-2*z^2+z^3);
ngDot=(6*z-6*z^2)*distance/state.durationS+ ...
    state.startNgDot*(1-4*z+3*z^2);
pitch=s.startPitchDeg+(s.idlePitchDeg-s.startPitchDeg)*(3*z^2-2*z^3);
stable=z>=1 && abs(sample.Ng-s.startupIdleNgRpm)<=s.startupNgToleranceRpm && ...
    abs(sample.NpDot)<=s.npDotStableToleranceRpmPerS && ...
    abs(sample.NgDot)<=s.ngDotStableToleranceRpmPerS && ...
    sample.T45<=s.maximumTt45K && sample.startupSafe;
if stable
    if ~isfinite(state.firstStableTimeS),state.firstStableTimeS=timeS;end
    if ~isfinite(state.stableStartTimeS),state.stableStartTimeS=timeS;end
else
    state.stableStartTimeS=NaN;
end
state.ready=isfinite(state.stableStartTimeS) && ...
    timeS-state.stableStartTimeS>=s.startupIdleHoldS-1e-10;
reference=struct('NgRpm',ng,'NgDot',ngDot,'pitchDeg',pitch, ...
    'stable',stable,'ready',state.ready);
end
