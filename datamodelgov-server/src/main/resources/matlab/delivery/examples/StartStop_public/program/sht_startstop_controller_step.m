function [fuel,state,info] = sht_startstop_controller_step( ...
    state,sample,segment,startFuel,targetNpRatio,phase,cfg)
%SHT_STARTSTOP_CONTROLLER_STEP 起动供油、主调速器接管和停车断油的唯一入口。
% fuel为本步送入DLL的计量燃油；fuelCommand是执行机构输入；C内部的
% effectiveFuel还包含点火/燃烧效率影响。三者不能混用。
a = cfg.aboveIdle;
s = cfg.stage6;
dt = s.timeStepS;
if isempty(state)
    state = struct('fuel',0,'command',0,'normal',[], ...
        'count',0,'temperatureLimit',cfg.startStop.lightOffFuelKgPerS, ...
        'diag',struct(),'lastSegment',-1);
end
tick = false;
startupTemperatureSelected = false;
startupActive = segment == 1 && isfield(sample,'startupControlActive') && ...
    sample.startupControlActive;
governorNp = targetNpRatio*cfg.startStop.designNpRpm;
reference = struct('NpDem',governorNp);
% 起动阶段的温度保护独立于Ng/Np调速模式。进入Ng受控升速后，
% 仍必须限制供油，避免不同发动机模型的升速燃烧温度越过保护上限。
if segment == 1 && phase >= 3
    rate = min(-s.temperatureFuelIntegralGainKgPerS2K * ...
        (sample.T45-s.temperatureSoftLimitK), ...
        s.temperatureFuelRecoveryRateKgPerS2);
    state.temperatureLimit = min(max(state.temperatureLimit+dt*rate, ...
        s.temperatureMinimumFuelKgPerS),a.actuator.wfMax);
end
if startupActive
    reference.governorMode='Ng';
    reference.NgDem=sample.startupNgReferenceRpm;
    reference.NgDotDem=sample.startupNgReferenceDot;
    reference.NgErrorGain=s.startupNgErrorGain;
end
if segment >= 7 || segment == 0
    % 截止阀使燃油直接为零，不受主控制器正最小燃油限制。
    state.command = 0;
    state.fuel = 0;
elseif segment == 1 && ~startupActive
    state.command = min(startFuel,state.temperatureLimit);
    startupTemperatureSelected = state.command < startFuel-1e-12;
elseif isempty(state.normal)
    % 受控升速开始时只初始化一次；稳定慢车后正式交接时不再次初始化。
    [ctrl,~] = sht_apply_controller_gain_schedule(a.controller,sample);
    ctrl.initial = struct('Np',sample.Np,'Ng',sample.Ng, ...
        'Wf',state.fuel,'T45',sample.T45,'Mkp',sample.Mkp);
    state.normal = sht_steady_governor_init(ctrl);
    % 起动尚有加速度，不能把Ng滤波状态按严格稳态初始化。
    state.normal.NgFilterState = sample.Ng-sample.NgDot/ctrl.filterOmega;
    state.normal.z2NgPrev = sample.NgDot-ctrl.linearModel.b21*state.fuel;
    state.normal.z2Ng = state.normal.z2NgPrev;
    state.normal.WfcmdDelay = state.command;
    state.normal.Wfcmd = state.command;
    state.count = 0;
elseif state.count >= a.integrationSubsteps
    [~,state.normal,state.diag] = sht_full_controller_step( ...
        state.normal,sample,reference, ...
        a.controller,a.sampleTimeS,'euler2');
    % oneSample时本拍输出是wfCommandNow，不可误用wfCommandNext跳过一拍。
    state.command = state.diag.wfCommandNow;
    state.count = 0;
    tick = true;
end
if segment == 1 && startupActive
    commandBeforeTemperatureLimit = state.command;
    state.command = min(state.command,state.temperatureLimit);
    if sample.T45 < s.temperatureSoftLimitK
        % Ng调速减油不能把有火起动根拉到C的熄火阈值以下。
        state.command = max(state.command,s.temperatureMinimumFuelKgPerS);
    end
    startupTemperatureSelected = state.command < commandBeforeTemperatureLimit-1e-12;
end
fuel = state.fuel;
info = struct('fuelCommand',state.command,'controlTick',double(tick), ...
    'controlModeId',0,'Ngc',sample.Ngc,'MkpFeedback',sample.Mkp, ...
    'gainScheduleAtLowerBound',false,'gainScheduleAtUpperBound',false, ...
    'ngTopProtectionSelected',false,'t45ProtectionSelected',startupTemperatureSelected, ...
    'mkpProtectionSelected',false,'Nu_main',NaN,'Nu_selected',NaN, ...
    'governorNpReferenceRpm',governorNp);
if segment == 1, info.controlModeId = 10; end
if startupActive || (segment >= 2 && segment <= 6)
    info.controlModeId = 1;
    fields = fieldnames(info);
    for i=1:numel(fields)
        if isfield(state.diag,fields{i})
            info.(fields{i}) = state.diag.(fields{i});
        end
    end
    info.fuelCommand = state.command;
    info.controlTick = double(tick);
    info.Ngc = sample.Ngc;
    if startupActive,info.controlModeId = 11;end
    state.count = state.count+1;
end
if segment > 0 && segment < 7
    % 与主程序共用执行器导数；二阶显式梯形积分推进到下一发动机步。
    k1 = sht_actuator_derivative(state.fuel,state.command,a.actuator);
    k2 = sht_actuator_derivative(state.fuel+dt*k1,state.command,a.actuator);
    state.fuel = min(max(state.fuel+0.5*dt*(k1+k2),0),a.actuator.wfMax);
end
state.lastSegment = segment;
end
