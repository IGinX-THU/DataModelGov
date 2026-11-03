function result = sht_startstop_run_continuous_mission( ...
    alias, engPtr, cfg, stage5Points, mapDirectory, caseDef, outputDir)
%SHT_STARTSTOP_RUN_CONTINUOUS_MISSION 连续执行一次完整起动、巡航和停车任务。
%
% MATLAB承担任务指令、燃油调节和转速/金属热状态的Heun数值积分。起停阶段、
% 有效燃油、气路共同工作、轴系动力学及自由轮逻辑始终由同一个C状态机
% 推进。整个函数只复位一次状态，禁止用静态点或分段文件拼接轨迹。

% 人工会话只复用气路/积分内核，不执行下面的自动任务转段脚本。
if isstruct(caseDef) && isfield(caseDef,'fullmodeAction')
    local_validate_fullmode_inlet_boundary(cfg);
    switch caseDef.fullmodeAction
        case 'prepare'
            result=local_fullmode_prepare(cfg,stage5Points,mapDirectory);
        case 'step'
            result=local_fullmode_step(alias,engPtr,cfg,stage5Points,caseDef.runtime);
        case 'refresh'
            r=caseDef.runtime;r.plant=local_fullmode_plant(cfg,r,r.snapshot);
            r.appliedLoad=sht_fullmode_load_boundary(cfg,r.speed(1),r.speed(3));
            oldRng=rng;guard=onCleanup(@()rng(oldRng));
            [r.sample,r.sensorState]=local_fullmode_sensor(r.sensorState,r.plant,cfg.fullmode.sensor,0,r.plant);
            result=r;
        case 'evaluate'
            r=caseDef.runtime; preview=cfg;preview.stage6.timeStepS=0;
            % 非零配平/恢复与正式推进采用同一已收敛近邻根池。这里仅评估
            % 当前气路，不积分，也不更新调用者持有的已接受根。
            seeds=local_candidate_seeds(stage5Points,r.seed,r.seed, ...
                r.speed(2),r.speed(1),r.fuel>0,r.output(4),cfg);
            result=local_execute_step(alias,engPtr,preview,r.maps,r.speed(1), ...
                r.speed(2),r.speed(3),r.fuel,caseDef.command,1, ...
                cfg.fullmode.load.mainPitchDeg,r.gasTemperatureK,seeds, ...
                r.output(4),r.thermal,true);
        otherwise
            error('sht:fullmode:action','未知会话内核操作。');
    end
    return;
end

if ~isfolder(outputDir)
    mkdir(outputDir);
end

s = cfg.stage6;
dt = s.timeStepS;
assert(isfinite(s.idleCaptureRampS) && s.idleCaptureRampS > 0 && ...
    isfield(cfg,'aboveIdle'), '必须先配置统一控制器和慢车过渡时间。');
maximumSteps = ceil(s.maximumMissionS / dt) + 1;
[names, column] = local_trace_schema(cfg);
data = nan(maximumSteps, numel(names));
controlNames = {'fuelCommand','controlTick','controlModeId','Ngc','MkpFeedback','MkpFeedbackExpected', ...
    'gainScheduleAtLowerBound','gainScheduleAtUpperBound', ...
    'ngTopProtectionSelected','t45ProtectionSelected','mkpProtectionSelected', ...
    'Nu_main','Nu_selected','governorNpReferenceRpm', ...
    'startupNgReferenceRpm','startupNgReferenceDot','startupStable','startupHoldElapsedS'};
controlData = nan(maximumSteps,numel(controlNames));
maps = local_read_maps(cfg, mapDirectory);
thermal = local_initialize_thermal_context(cfg);
if thermal.enabled
    [thermalNames, thermalColumn] = local_thermal_trace_schema(thermal,cfg);
    thermalData = nan(maximumSteps, numel(thermalNames));
else
    thermalNames = {};
    thermalColumn = struct();
    thermalData = zeros(0, 0);
end

status = calllib(alias, 'DLL_SHT_StartStopReset', 0, 0, 0, 1);
assert(status == 0, '连续任务状态复位失败，状态码=%d。', status);

npRpm = 0;
ngRpm = 0;
rotorRpm = 0;
segment = 0;
segmentTime = 0;
stableTime = 0;
controllerState = [];
startupControl = [];
% 接管时记录实际转速；目标始终为用户给定慢车，不跟随超调后的转速。
idleCaptureStartNpRatio = NaN;
idleControlStartTime = NaN;
handoverNpReferenceRpm = NaN;
idleTransfer = struct('timeS',NaN,'startNpRatio',NaN,'targetNpRatio',NaN, ...
    'previousFuelKgPerS',NaN,'fuelTargetKgPerS',NaN,'appliedFuelKgPerS',NaN, ...
    'sameInputCommandDifferenceKgPerS',NaN,'controllerStateContinuous',false);
lastNgc = 0;
measuredGasTemperatureK = 288.15 + caseDef.deltaTemperatureK;
seed = local_select_stage5_seed(stage5Points, 0, 0, false, cfg);
previousRoot = nan(cfg.topology.gasCount, 1);
previousOutput = zeros(128, 1);
completed = false;
failureReason = '';
idleStableReached = false;
cruiseStableReached = false;
startupBeginTime = NaN;
shutdownBeginTime = NaN;
integrationAudit = struct('method',s.integrationMethod,'timeStepS',dt, ...
    'previewCount',0,'previewPhaseChanges',0,'previewFreewheelChanges',0, ...
    'maximumPreviewResidual',0,'maximumClockErrorS',0,'maximumPreviewRetries',0);

for k = 1:maximumSteps
    timeS = (k - 1) * dt;
    % 同一个C状态机确认自持、起动机切除及火焰建立之后，M开始受控
    % 升速。此时仍是起动模式；达到目标并连续稳定保持后才正式接管。
    startupSafe = previousOutput(4)>=6 && previousOutput(4)<9 && ...
        previousOutput(7)>=1-1e-10 && ~any(previousOutput(21:23)>0.5);
    sample = struct('Np',npRpm,'Ng',ngRpm,'T45',measuredGasTemperatureK, ...
        'Mkp',previousOutput(11),'Ngc',lastNgc,'NgDot',previousOutput(2), ...
        'NpDot',previousOutput(1),'startupSafe',startupSafe, ...
        'startupControlActive',false);
    startupReference = struct('NgRpm',s.startupIdleNgRpm,'NgDot',0, ...
        'pitchDeg',s.idlePitchDeg,'stable',false,'ready',false);
    if segment==1 && (startupSafe || ~isempty(startupControl))
        [startupControl,startupReference] = sht_startstop_start_reference( ...
            startupControl,sample,timeS,cfg);
        sample.startupControlActive = true;
        sample.startupNgReferenceRpm = startupReference.NgRpm;
        sample.startupNgReferenceDot = startupReference.NgDot;
    end
    enteringIdleCapture = segment==1 && startupReference.ready;
    if enteringIdleCapture
        segment = 2;
        segmentTime = 0;
        stableTime = 0;
        idleCaptureStartNpRatio = npRpm / cfg.startStop.designNpRpm;
        idleControlStartTime = timeS;
    end
    controlElapsed = timeS-idleControlStartTime;
    [command, ignition, pitchDeg, npTargetRatio, startFuel] = ...
        local_mission_command(segment, segmentTime, ngRpm,cfg);
    if segment==1 && sample.startupControlActive
        pitchDeg=startupReference.pitchDeg;
    end
    if isempty(controllerState), previousFuelCommand=0;
    else, previousFuelCommand=controllerState.command; end
    if enteringIdleCapture
        % 同一拍、同一输入的反事实检查：继续起动保持与转正常控制必须
        % 得到相同结果。自然的一拍调节量不是模式切换造成的燃油跳变。
        [~,heldState,heldInfo]=sht_startstop_controller_step( ...
            controllerState,sample,1,startFuel,s.idleNpRatio,previousOutput(4),cfg);
        % Ng切Np时匹配本拍Nu候选值，避免用Np瞬时误差制造燃油阶跃。
        % 这只初始化正常调速参考，不重置发动机或执行器的真实状态。
        [ctrl,~]=sht_apply_controller_gain_schedule(cfg.aboveIdle.controller,sample);
        desiredNu=sht_steady_governor_compute(controllerState.normal,sample, ...
            struct('NpDem',s.idleNpRpm,'governorMode','Ng','NgDem',startupReference.NgRpm, ...
            'NgDotDem',startupReference.NgDot,'NgErrorGain',s.startupNgErrorGain), ...
            ctrl,cfg.aboveIdle.sampleTimeS);
        handoverNpReferenceRpm=npRpm + ...
            ctrl.npDeltaGain/ctrl.npErrorGain* ...
            (npRpm-controllerState.normal.NpPrev)/cfg.aboveIdle.sampleTimeS + ...
            desiredNu.Nu_main*ctrl.linearModel.b11/ctrl.linearModel.b21/ ...
            (ctrl.npErrorGain*cfg.aboveIdle.sampleTimeS);
    end
    if segment==2
        fraction=local_smooth_progress(segmentTime/s.idleHandoverRampS);
        npTargetRatio=(handoverNpReferenceRpm+ ...
            fraction*(s.idleNpRpm-handoverNpReferenceRpm))/cfg.startStop.designNpRpm;
    end
    [commandedFuel,controllerState,controlInfo] = sht_startstop_controller_step( ...
        controllerState,sample,segment,startFuel,npTargetRatio,previousOutput(4),cfg);
    controlInfo.MkpFeedbackExpected=previousOutput(11);
    controlInfo.startupNgReferenceRpm=startupReference.NgRpm;
    controlInfo.startupNgReferenceDot=startupReference.NgDot;
    controlInfo.startupStable=double(startupReference.stable);
    controlInfo.startupHoldElapsedS=0;
    if ~isempty(startupControl) && isfinite(startupControl.stableStartTimeS)
        controlInfo.startupHoldElapsedS=max(timeS-startupControl.stableStartTimeS,0);
    end
    for ci=1:numel(controlNames)
        controlData(k,ci)=controlInfo.(controlNames{ci});
    end
    if enteringIdleCapture
        idleTransfer = struct('timeS',timeS,'startNpRatio',idleCaptureStartNpRatio, ...
            'targetNpRatio',npTargetRatio,'previousFuelKgPerS',previousFuelCommand, ...
            'fuelTargetKgPerS',controlInfo.fuelCommand,'appliedFuelKgPerS',commandedFuel, ...
            'sameInputCommandDifferenceKgPerS',controlInfo.fuelCommand-heldInfo.fuelCommand, ...
            'controllerStateContinuous', ...
                abs(controllerState.normal.Wfcmd-heldState.normal.Wfcmd)<1e-10 && ...
                abs(controllerState.fuel-heldState.fuel)<1e-10 && ...
                controllerState.count==heldState.count);
    end

    firedBranch = previousOutput(4) >= 3 && previousOutput(4) < 9 && ...
        command ~= 3;
    seedCandidates = local_candidate_seeds(stage5Points, seed, ...
        previousRoot, ngRpm, npRpm, firedBranch, previousOutput(4), cfg);
    attempt = local_execute_step(alias, engPtr, cfg, maps, ...
        npRpm, ngRpm, rotorRpm, commandedFuel, command, ignition, ...
        pitchDeg, measuredGasTemperatureK, seedCandidates, ...
        previousOutput(4), thermal);
    callStatus = attempt.callStatus;
    output = attempt.output;
    diagnostics = attempt.diagnostics;
    snapshot = attempt.snapshot;
    if ~isempty(attempt.errorMessage)
        failureReason = sprintf('第%d步DLL调用异常：%s', ...
            k, attempt.errorMessage);
    end

    activeGasPath = diagnostics(1) ~= 6;
    solverConverged = callStatus == 0 && ...
        ((diagnostics(1) == 0 && diagnostics(2) > 0.5) || ...
        diagnostics(1) == 6);
    if activeGasPath && solverConverged
        currentRoot = diagnostics(17+(1:cfg.topology.gasCount));
        if all(isfinite(previousRoot))
            rootStep = max(abs(currentRoot - previousRoot) ./ ...
                s.rootVariableScale);
        else
            rootStep = NaN;
        end
        previousRoot = currentRoot;
        seed = currentRoot;
        if isfinite(snapshot.tt45K)
            measuredGasTemperatureK = snapshot.tt45K;
        end
        if isfinite(snapshot.Ngc), lastNgc=snapshot.Ngc; end
    else
        rootStep = NaN;
    end

    data(k, :) = local_trace_row(timeS, segment, command, output, ...
        npRpm, ngRpm, rotorRpm, npTargetRatio, pitchDeg, commandedFuel, ...
        measuredGasTemperatureK, callStatus, diagnostics, rootStep, ...
        attempt.attemptCount, snapshot, column, numel(names),cfg);
    if thermal.enabled
        thermalData(k, :) = local_thermal_trace_row(timeS, segment, ...
            thermal.state, output(cfg.topology.temperatureOutputIndices), snapshot, thermalColumn, ...
            numel(thermalNames),cfg);
    end

    if isempty(failureReason) && (~solverConverged || output(24) < 0.5)
        failureReason = sprintf(['第%d步气路/物理求解无效：call=%g, status=%g, ', ...
            'rRMS=%g, maxR=%g。'], k, callStatus, diagnostics(1), ...
            diagnostics(13), diagnostics(14));
    end
    if ~isempty(failureReason)
        break;
    end

    % 主调用已提交一个dt；预测与校正端点只评估导数，不再推进C状态机。
    % 执行器给出Wf_{k+1}，控制指令及本拍桨距保持不变，控制器不重复调用。
    speed = [npRpm;ngRpm;rotorRpm];
    nextSpeed = max(0,speed+dt*output(1:3));
    nextThermal = thermal;
    if thermal.enabled
        nextThermal.state = thermal.state+dt*output(cfg.topology.temperatureOutputIndices);
    end
    feedback = attempt;
    if strcmp(s.integrationMethod,'euler2')
        previewCfg=cfg;previewCfg.stage6.timeStepS=0;
        previewSeeds=local_candidate_seeds(stage5Points,seed,previousRoot, ...
            nextSpeed(2),nextSpeed(1),output(6)>0,output(4),cfg);
        predictor=local_execute_step(alias,engPtr,previewCfg,maps, ...
            nextSpeed(1),nextSpeed(2),nextSpeed(3),controllerState.fuel, ...
            command,ignition,pitchDeg,measuredGasTemperatureK,previewSeeds, ...
            output(4),nextThermal);
        if ~predictor.converged
            failureReason=sprintf('第%d步Heun预测评估失败：status=%g, maxR=%g。', ...
                k,predictor.callStatus,predictor.diagnostics(14));break;
        end
        nextSpeed=max(0,speed+0.5*dt*(output(1:3)+predictor.output(1:3)));
        if thermal.enabled
            ids=cfg.topology.temperatureOutputIndices;
            nextThermal.state=thermal.state+0.5*dt*(output(ids)+predictor.output(ids));
        end
        % 与试车主积分器一致，在最终校正状态重新求气路；不能把预测状态
        % 的Tt45/Ngc/扭矩冒充校正后的反馈，也不能把预测事件提交给状态机。
        finalSeeds=previewSeeds;
        if predictor.diagnostics(1)~=6
            finalSeeds=[predictor.diagnostics(17+(1:cfg.topology.gasCount)).';previewSeeds];
        end
        feedback=local_execute_step(alias,engPtr,previewCfg,maps, ...
            nextSpeed(1),nextSpeed(2),nextSpeed(3),controllerState.fuel, ...
            command,ignition,pitchDeg,measuredGasTemperatureK,finalSeeds, ...
            output(4),nextThermal);
        if ~feedback.converged
            failureReason=sprintf('第%d步Heun校正端点评估失败：status=%g, maxR=%g。', ...
                k,feedback.callStatus,feedback.diagnostics(14));break;
        end
        integrationAudit.previewCount=integrationAudit.previewCount+2;
        integrationAudit.previewPhaseChanges=integrationAudit.previewPhaseChanges+ ...
            double(predictor.output(4)~=output(4));
        integrationAudit.previewFreewheelChanges=integrationAudit.previewFreewheelChanges+ ...
            double(predictor.output(12)~=output(12));
        integrationAudit.maximumPreviewResidual=max(integrationAudit.maximumPreviewResidual, ...
            max([predictor.diagnostics(14),feedback.diagnostics(14)]));
        integrationAudit.maximumPreviewRetries=max(integrationAudit.maximumPreviewRetries, ...
            max(predictor.attemptCount,feedback.attemptCount));
        integrationAudit.maximumClockErrorS=max(integrationAudit.maximumClockErrorS, ...
            max(abs([output(19)-timeS,predictor.output(19)-timeS-dt, ...
            feedback.output(19)-timeS-dt])));
        if isfinite(feedback.snapshot.tt45K),measuredGasTemperatureK=feedback.snapshot.tt45K;end
        if isfinite(feedback.snapshot.Ngc),lastNgc=feedback.snapshot.Ngc;end
        if feedback.diagnostics(1)~=6,seed=feedback.diagnostics(17+(1:cfg.topology.gasCount));end
    end
    if thermal.enabled && (any(~isfinite(nextThermal.state)) || any(nextThermal.state<=0))
        failureReason=sprintf('第%d步热状态积分得到非有限或非正温度。',k);break;
    end
    npRpm=nextSpeed(1);ngRpm=nextSpeed(2);rotorRpm=nextSpeed(3);
    thermal=nextThermal;
    previousOutput=feedback.output;

    [segment, segmentTime, stableTime, idleStableReached, ...
        cruiseStableReached, completed, transitionFailure, ...
        startupBeginTime, shutdownBeginTime] = local_advance_segment( ...
        segment, segmentTime, stableTime, idleStableReached, ...
        cruiseStableReached, feedback.output, npRpm, ngRpm, rotorRpm, ...
        npTargetRatio, timeS + dt, startupBeginTime, ...
        shutdownBeginTime, cfg,controlElapsed+dt,startupControl);
    if ~isempty(transitionFailure)
        failureReason = transitionFailure;
        break;
    end
    if completed
        break;
    end
end

used = find(isfinite(data(:, column.time)), 1, 'last');
if isempty(used)
    used = 0;
end
data = data(1:used, :);
trace = array2table(data, 'VariableNames', names);
trace = [trace,array2table(controlData(1:used,:), 'VariableNames',controlNames)];
csvPath = fullfile(outputDir, 'continuous_mission_trace.csv');
writetable(trace, csvPath);
thermalTrace = table();
thermalCsvPath = '';
if thermal.enabled
    thermalData = thermalData(1:used, :);
    thermalTrace = array2table(thermalData, ...
        'VariableNames', thermalNames);
    thermalCsvPath = fullfile(outputDir, 'thermal_state_trace.csv');
    writetable(thermalTrace, thermalCsvPath);
end

% 轨迹每一行记录的是本步积分前状态；任务完成判定使用的是同一步积分后
% 状态。终端停车验收必须使用积分后状态，否则临界一步会出现“状态机已
% 完成、CSV末行仍略高于停车门限”的假失败。
terminalSpeedRpm = [npRpm; ngRpm; rotorRpm];
checks = local_acceptance_checks(trace, failureReason, ...
    idleStableReached, cruiseStableReached, completed, ...
    terminalSpeedRpm, cfg, idleTransfer);
checks.integrationClockAccepted=integrationAudit.maximumClockErrorS<1e-7;
checks.accepted=checks.accepted && checks.integrationClockAccepted;
if thermal.enabled
    checks = local_add_thermal_acceptance_checks(checks, ...
        thermalTrace, thermal, cfg);
end
summaryPath = fullfile(outputDir, 'continuous_mission_summary.md');
local_write_summary(summaryPath, caseDef, checks, trace, failureReason, ...
    terminalSpeedRpm, cfg, thermalTrace, idleTransfer);
figurePath = sht_startstop_plot_continuous_trace(trace, caseDef, outputDir, cfg);
controlFigurePath = sht_startstop_plot_control_detail(trace,cfg,outputDir);
thermalFigurePath = '';
if thermal.enabled
    thermalFigurePath = local_plot_thermal_trace( ...
        thermalTrace, caseDef, outputDir, cfg, thermal);
end

result = struct('caseDefinition', caseDef, 'trace', trace, ...
    'integrationAudit',integrationAudit, ...
    'controlConfiguration',cfg.aboveIdle, ...
    'startupControl',startupControl,'startupConfiguration',s, ...
    'idleTransfer',idleTransfer, ...
    'lastAttempt',attempt, ...
    'checks', checks, 'failureReason', failureReason, ...
    'idleStableReached', idleStableReached, ...
    'cruiseStableReached', cruiseStableReached, ...
    'completed', completed, 'summaryPath', summaryPath, ...
    'csvPath', csvPath, 'figurePath', figurePath, ...
    'controlFigurePath',controlFigurePath, ...
    'thermalTrace', thermalTrace, 'thermalCsvPath', thermalCsvPath, ...
    'thermalFigurePath', thermalFigurePath, ...
    'thermalContext', local_public_thermal_context(thermal), ...
    'terminalSpeedRpm', terminalSpeedRpm, ...
    'accepted', checks.accepted);
save(fullfile(outputDir, 'continuous_mission_result.mat'), 'result', '-v7');
end

function r=local_fullmode_prepare(cfg,points,mapDirectory)
% 本结构只含数值和配置；无libpointer，允许完整保存和冷进程恢复。
r=struct('timeS',0,'acceptedSteps',0,'speed',zeros(3,1),'fuel',0, ...
    'controller',[],'startupControl',[],'handoverNpRpm',NaN,'handoverStartS',NaN, ...
    'mode','stopped','modeStartS',0,'warmupComplete',false, ...
    'maps',local_read_maps(cfg,mapDirectory),'thermal',local_initialize_thermal_context(cfg), ...
    'seed',local_select_stage5_seed(points,0,0,false,cfg), ...
    'output',zeros(128,1),'snapshot',local_empty_snapshot(cfg), ...
    'gasTemperatureK',288.15,'sensorState',struct(),'sample',struct(), ...
    'plant',struct(),'failureReason','','physicalStop',true,'controlInfo',struct(), ...
    'npCommand',[]);
r.plant=local_fullmode_plant(cfg,r,r.snapshot);
r.appliedLoad=sht_fullmode_load_boundary(cfg,0,0);
if isfield(cfg.fullmode,'inletBoundary')
    % 显式边界已限定为非零初态。此时只是配平前的空壳，Pt2尚未知；
    % 既有非零初态配平后的refresh会用实际进口出口压力初始化传感器。
    % evaluate只求气路/轴系，不消费sample；不在这里伪造Pt2或提前推进。
    return;
end
oldRng=rng;guard=onCleanup(@()rng(oldRng));
[r.sample,r.sensorState]=local_fullmode_sensor(r.sensorState,r.plant,cfg.fullmode.sensor,0,r.plant);
end

function local_validate_fullmode_inlet_boundary(cfg)
% 未给显式边界时不改变历史mode0。此增量只接通地面标准温度下的非零初态，
% 不扩展一般环境冷态起动，也不把空配置或缺字段悄悄解释成默认环境。
if ~isfield(cfg,'fullmode') || ~isfield(cfg.fullmode,'inletBoundary'),return;end
b=cfg.fullmode.inletBoundary;
assert(isstruct(b) && isscalar(b),'sht:fullmode:inletBoundary', ...
    'fullmode.inletBoundary必须是完整的标量结构体。');
required={'inletBoundaryMode','Pt1','Tt1','Pamb','Tamb','altitude','Mach','deltaTemperature'};
for k=1:numel(required)
    name=required{k};
    assert(isfield(b,name),'sht:fullmode:inletBoundary', ...
        '显式进口边界缺少字段%s；不会回退到标准大气模式。',name);
    validateattributes(b.(name),{'numeric'},{'real','scalar','finite'},mfilename,name);
end
assert(all(ismember(fieldnames(b),required)),'sht:fullmode:inletBoundary', ...
    '显式进口边界包含不支持的字段，请使用已约定的mode1字段。');
assert(b.inletBoundaryMode==1 && b.Pt1>0 && b.Tt1>0 && b.Pamb>0 && b.Tamb>0, ...
    'sht:fullmode:inletBoundary','显式进口边界只接受mode1及正Pt1/Tt1/Pamb/Tamb。');
assert(b.altitude==0 && b.Mach==0 && b.deltaTemperature==0 && ...
    b.Tamb==288.15 && b.Tt1==b.Tamb,'sht:fullmode:inletBoundaryScope', ...
    '本批显式边界仅支持地面静止标准温度：高度/Mach/deltaT=0，Tt1=Tamb=288.15 K。');
assert(isfield(cfg.fullmode,'active') && cfg.fullmode.active && ...
    any(strcmp(cfg.fullmode.initialKind,{'idle','cruise','maximum'})), ...
    'sht:fullmode:inletBoundaryScope', ...
    '显式进口边界仅用于相容非零初态，不支持以此配置扩展静止起动。');
end

function r=local_fullmode_step(alias,engPtr,cfg,points,r)
% 每次调用接受一个完整Heun步。C状态在失败时回滚；M更新在函数成功返回
% 后才交给会话对象。控制器与传感器在一拍中各推进一次，预览不推进它们。
beforePointer=libpointer('doublePtr',zeros(64,1));
status=calllib(alias,'DLL_SHT_FullModeExportState',26100701,64,beforePointer);
assert(status==0,'起停私有状态导出失败。');
before=beforePointer.Value;
try
    dt=cfg.stage6.timeStepS;s=cfg.stage6;modeBefore=r.mode;
    % 标称Np模型含旋翼折算惯量。测功器直连或自由轮脱开时，只剩PT
    % 本体惯量；b11=d(NpDot)/dWf须按惯量反比换算，不能仍用全惯量值。
    % 这里只改本拍控制模型，不改物理惯量、调速增益、保护限值或普通入口。
    cfg=local_fullmode_control_inertia(cfg,r.output(12)>0.5);
    sample=r.sample;sample.NpDot=r.output(1);sample.NgDot=r.output(2);
    sample.startupSafe=r.output(4)>=6 && r.output(4)<9 && ...
        r.output(7)>=1-1e-10 && ~any(r.output(21:23)>0.5);
    sample.startupControlActive=false;
    pitch=cfg.fullmode.load.mainPitchDeg;fuelFeedforward=s.idleFuelFeedforwardKgPerS;
    reference=s.idleNpRatio;segment=3;command=4;ignition=1;
    if any(strcmp(r.mode,{'cranking','warmup'}))
        segment=1;
        [command,ignition,pitch,reference,fuelFeedforward]= ...
            local_mission_command(1,0,r.speed(2),cfg);
        if sample.startupSafe || ~isempty(r.startupControl)
            [r.startupControl,startRef]=sht_startstop_start_reference(r.startupControl,sample,r.timeS,cfg);
            r.mode='warmup';sample.startupControlActive=true;
            sample.startupNgReferenceRpm=startRef.NgRpm;sample.startupNgReferenceDot=startRef.NgDot;
            pitch=startRef.pitchDeg;
            if startRef.ready
                [ctrl,~]=sht_apply_controller_gain_schedule(cfg.aboveIdle.controller,sample);
                nu=sht_steady_governor_compute(r.controller.normal,sample, ...
                    struct('NpDem',s.idleNpRpm,'governorMode','Ng', ...
                    'NgDem',startRef.NgRpm,'NgDotDem',startRef.NgDot,'NgErrorGain',s.startupNgErrorGain), ...
                    ctrl,cfg.aboveIdle.sampleTimeS);
                r.handoverNpRpm=sample.Np+ctrl.npDeltaGain/ctrl.npErrorGain* ...
                    (sample.Np-r.controller.normal.NpPrev)/cfg.aboveIdle.sampleTimeS+ ...
                    nu.Nu_main*ctrl.linearModel.b11/ctrl.linearModel.b21/(ctrl.npErrorGain*cfg.aboveIdle.sampleTimeS);
                r.mode='idle_handover';r.handoverStartS=r.timeS;
                r.warmupComplete=true;sample.startupControlActive=false;segment=2;command=4;
            end
        end
    elseif strcmp(r.mode,'run')
        command=2;reference=cfg.fullmode.npRatio;
    elseif strcmp(r.mode,'coldblow')
        segment=0;command=5;ignition=0;fuelFeedforward=0;
        if r.timeS-r.modeStartS>=cfg.fullmode.coldBlowDurationS
            r.mode='shutdown';r.modeStartS=r.timeS;command=6;
        end
    elseif any(strcmp(r.mode,{'shutdown','stopped'}))
        segment=7;command=3;ignition=0;fuelFeedforward=0;
        if strcmp(r.mode,'stopped'),command=0;end
    elseif strcmp(r.mode,'cooldown')
        command=4;reference=s.idleNpRatio;
        if r.timeS-r.modeStartS>=10 && ...
                abs(r.speed(1)-s.idleNpRpm)<s.npStableToleranceRatio*cfg.startStop.designNpRpm
            r.mode='shutdown';r.modeStartS=r.timeS;segment=7;command=3;ignition=0;
        end
    end
    if strcmp(r.mode,'idle_handover')
        z=local_smooth_progress((r.timeS-r.handoverStartS)/s.idleHandoverRampS);
        reference=(r.handoverNpRpm+z*(s.idleNpRpm-r.handoverNpRpm))/cfg.startStop.designNpRpm;
        segment=2;command=4;
        if z>=1,r.mode='idle';r.modeStartS=r.timeS;end
    end
    % 暖机双总距随既有主桨参考连续变化；尾桨使用相同比例以保持标称总载荷。
    if any(strcmp(r.mode,{'cranking','warmup','idle_handover'})) && ...
            strcmp(cfg.fullmode.loadMode,'dual_collective')
        cfg.fullmode.load.mainPitchDeg=pitch;
        cfg.fullmode.load.tailPitchDeg=pitch/cfg.startStop.thetaDesignDeg*cfg.fullmode.tailDesignPitchDeg;
    end
    % 五挡提交的是最终目标。沿用原起停升/降速20秒参考过渡，不能把
    % 操作者阶跃直接送入调速器而绕过原参考轨迹。只保存指令状态，不配平。
    [r,reference]=local_fullmode_np_reference(r,reference,cfg,modeBefore);
    [fuel,nextController,info]=sht_startstop_controller_step(r.controller,sample, ...
        segment,fuelFeedforward,reference,r.output(4),cfg);
    if ignition==0,fuel=0;nextController.fuel=0;nextController.command=0;end
    seeds=local_candidate_seeds(points,r.seed,r.seed,r.speed(2),r.speed(1), ...
        fuel>0,r.output(4),cfg);
    first=local_execute_step(alias,engPtr,cfg,r.maps,r.speed(1),r.speed(2), ...
        r.speed(3),fuel,command,ignition,pitch,r.gasTemperatureK,seeds,r.output(4),r.thermal);
    local_fullmode_require(first,'整步起点');
    predictorSpeed=max(0,r.speed+dt*first.output(1:3));thermal=r.thermal;
    ids=cfg.topology.temperatureOutputIndices;
    if thermal.enabled,thermal.state=r.thermal.state+dt*first.output(ids);end
    previewCfg=cfg;previewCfg.stage6.timeStepS=0;
    predictor=local_execute_step(alias,engPtr,previewCfg,r.maps,predictorSpeed(1), ...
        predictorSpeed(2),predictorSpeed(3),nextController.fuel,command,ignition,pitch, ...
        r.gasTemperatureK,seeds,first.output(4),thermal);
    local_fullmode_require(predictor,'Heun预测端点');
    speed=max(0,r.speed+dt/2*(first.output(1:3)+predictor.output(1:3)));
    if thermal.enabled,thermal.state=r.thermal.state+dt/2*(first.output(ids)+predictor.output(ids));end
    assert(~thermal.enabled || all(isfinite(thermal.state) & thermal.state>0),'热积分得到非法温度。');
    if predictor.diagnostics(1)~=6,seeds=[predictor.diagnostics(17+(1:cfg.topology.gasCount)).';seeds];end
    endpoint=local_execute_step(alias,engPtr,previewCfg,r.maps,speed(1),speed(2),speed(3), ...
        nextController.fuel,command,ignition,pitch,r.gasTemperatureK,seeds,first.output(4),thermal);
    local_fullmode_require(endpoint,'Heun校正端点');
    r.speed=speed;r.thermal=thermal;r.output=endpoint.output;r.snapshot=endpoint.snapshot;
    r.appliedLoad=sht_fullmode_load_boundary(cfg,speed(1),speed(3));
    r.controller=nextController;r.fuel=nextController.fuel;r.controlInfo=info;
    if endpoint.diagnostics(1)~=6
        r.seed=endpoint.diagnostics(17+(1:cfg.topology.gasCount));
        r.gasTemperatureK=endpoint.snapshot.tt45K;
    end
    nextPlant=local_fullmode_plant(cfg,r,endpoint.snapshot);
    oldRng=rng;guard=onCleanup(@()rng(oldRng));
    [r.sample,r.sensorState]=local_fullmode_sensor(r.sensorState,r.plant,cfg.fullmode.sensor,dt,nextPlant);
    r.plant=nextPlant;r.timeS=r.timeS+dt;r.acceptedSteps=r.acceptedSteps+1;
    r.physicalStop=all(speed<=0.5) && endpoint.output(7)==0;
    if strcmp(r.mode,'shutdown') && r.physicalStop,r.mode='stopped';r.modeStartS=r.timeS;end
catch ex
    status=calllib(alias,'DLL_SHT_FullModeImportState',26100701,64,libpointer('doublePtr',before));
    if status~=0,error('sht:fullmode:rollback','数值步失败且C状态回滚失败：%s。',ex.message);end
    rethrow(ex);
end
end

function [r,ratio]=local_fullmode_np_reference(r,ratio,cfg,modeBefore)
target=ratio*cfg.startStop.designNpRpm;
if ~any(strcmp(r.mode,{'idle','run','cooldown'})) || strcmp(modeBefore,'idle_handover')
    % Ng暖机及已有3秒无扰交接保持原算法，不叠加另一层指令过渡。
    r.npCommand=struct('value',target,'target',target,'start',target,'timeS',r.timeS,'durationS',0);
    return;
end
if isempty(r.npCommand)
    r.npCommand=struct('value',r.speed(1),'target',r.speed(1), ...
        'start',r.speed(1),'timeS',r.timeS,'durationS',0);
end
p=r.npCommand;
if abs(target-p.target)>1e-8
    p.start=p.value;p.target=target;p.timeS=r.timeS;
    if target>=p.start,p.durationS=cfg.stage6.cruiseRampS;
    else,p.durationS=cfg.stage6.returnRampS;end
end
if p.durationS>0
    z=local_smooth_progress((r.timeS+cfg.stage6.timeStepS-p.timeS)/p.durationS);
else,z=1;end
p.value=p.start+(p.target-p.start)*z;r.npCommand=p;
ratio=p.value/cfg.startStop.designNpRpm;
end

function cfg=local_fullmode_control_inertia(cfg,freewheelEngaged)
s=cfg.startStop;
referenceInertia=s.ptEngineInertiaKgM2+s.rotorReflectedInertiaKgM2;
effectiveInertia=s.ptEngineInertiaKgM2;
if strcmp(cfg.fullmode.loadMode,'dual_collective') && freewheelEngaged
    effectiveInertia=referenceInertia;
end
ratio=referenceInertia/effectiveInertia;
cfg.aboveIdle.controller.linearModel.b11=cfg.aboveIdle.controller.linearModel.b11*ratio;
if isfield(cfg.aboveIdle.controller,'gainSchedule') && ...
        isfield(cfg.aboveIdle.controller.gainSchedule,'b11')
    cfg.aboveIdle.controller.gainSchedule.b11=cfg.aboveIdle.controller.gainSchedule.b11*ratio;
end
% b21属于Ng，d31属于温度，d41属于静态扭矩增益，均不随PT惯量缩放。
end

function local_fullmode_require(a,label)
if ~a.converged
    error('sht:fullmode:numericalStep','%s失败：call=%g，solver=%g，maxR=%g，residual=%s，%s', ...
        label,a.callStatus,a.diagnostics(1),a.diagnostics(14), ...
        mat2str(a.diagnostics(34:46).',6),a.errorMessage);
end
end

function p=local_fullmode_plant(cfg,r,s)
% 气路未激活时只保留真实边界和轴系量，不伪造稳态气路输出。
p=struct('Np',r.speed(1),'Ng',r.speed(2),'Tt45',r.gasTemperatureK, ...
    'Mkp',r.output(11),'Mkg',0,'Tt1',288.15,'Pt2',101325,'Pamb',101325, ...
    'Tamb',288.15,'Altitude',0,'Mach',0,'WIn',0, ...
    'Pt3',NaN,'Tt3',NaN,'Pt45',NaN,'Pt5',NaN,'Tt5',NaN,'T4',NaN);
explicitBoundary=isfield(cfg.fullmode,'inletBoundary');
if explicitBoundary
    b=cfg.fullmode.inletBoundary;
    p.Pamb=b.Pamb;p.Tamb=b.Tamb;p.Tt1=b.Tt1;
    p.Altitude=b.altitude;p.Mach=b.Mach;
    % 无气路时进口出口总压尚不可用，不能用给定Pt1冒充Pt2。
    p.Pt2=NaN;
end
if r.speed(2)>0
    z=min(r.speed(2)/(cfg.startStop.idleNgRatio*cfg.startStop.designNgRpm),1);
    accessory=cfg.startStop.gtAccessoryPowerW*z^2*(3-2*z);
    omega=r.speed(2)*pi/30;p.Mkg=accessory*omega/(omega^2+(20*pi/30)^2);
end
if isfinite(s.Ngc),p.NgcRaw=s.Ngc;end
if ~isempty(s.stationWTP) && all(isfinite(s.stationWTP(1,:)))
    p.WIn=s.stationWTP(1,1);p.Tt1=s.stationWTP(1,2);p.Pt2=s.stationWTP(1,3);
    i=1+cfg.topology.compressorCount;p.Tt3=s.stationWTP(i,2);p.Pt3=s.stationWTP(i,3);
    p.T4=s.stationWTP(i+1,2);
    i=i+1+(numel(cfg.topology.componentNames)-cfg.topology.compressorCount)/2;
    p.Pt45=s.stationWTP(i,3);p.Tt45=s.tt45K;
    p.Pt5=s.stationWTP(end,3);p.Tt5=s.stationWTP(end,2);
end
if explicitBoundary && isfield(s,'inletBoundaryActual')
    % 气路已计算时记录DLL实际消费的边界；Pt2仍来自上面的进口出口站。
    b=s.inletBoundaryActual;
    p.Pamb=b.Pamb;p.Tamb=b.Tamb;p.Tt1=b.Tt1;
    p.Altitude=b.altitude;p.Mach=b.Mach;
end
end

function [sample,state]=local_fullmode_sensor(state,rawNow,cfg,dt,rawNext)
% 静止时尚无气路解的通道保持NaN。首次获得有限气路值时，用该首个值
% 初始化这一只传感器，并将这一拍的起点补成首个值；不臆造缺失历程。
% 已有效通道的FOH、随机序列、偏置和控制反馈完全沿用公共传感器函数。
pressure='Pt2';if isfield(cfg,'pressureChannel'),pressure=cfg.pressureChannel;end
a=sht_sensor_pack(rawNow,pressure);b=sht_sensor_pack(rawNext,pressure);
reinitialized=false(size(b.vector));
if isfield(state,'dynamicVector') && numel(state.dynamicVector)==numel(b.vector)
    reinitialized=isfinite(b.vector) & (~isfinite(a.vector) | ~isfinite(state.dynamicVector));
    for k=find(reinitialized(:)).'
        name=b.vectorNames{k};if strcmp(name,'T45'),name='Tt45';end
        rawNow.(name)=b.vector(k);
        state.dynamicVector(k)=b.vector(k);
    end
end
[sample,state]=sht_sensor_step(state,rawNow,cfg,dt,0,rawNext);
if ~isfield(state,'availabilityInitializations'),state.availabilityInitializations=zeros(size(b.vector));end
state.availabilityInitializations=state.availabilityInitializations+double(reinitialized);
state.availableChannels=isfinite(b.vector);
end

function [command, ignition, pitchDeg, targetRatio, fuelTarget] = ...
    local_mission_command(segment, segmentTime, ngRpm,cfg)
p = cfg.startStop;
s = cfg.stage6;
command = 0;
ignition = 0;
pitchDeg = s.startPitchDeg;
targetRatio = 0;
fuelTarget = 0;

switch segment
    case 0
        return;
    case 1
        command = 1;
        % 冷拖至慢车采用显式供油先验。有效燃油仍由C程序按点火延迟、
        % 火焰建立比例和低速燃烧效率计算，MATLAB不重复实现燃烧模型。
        ngRatio = ngRpm / p.designNgRpm;
        ignition = double(ngRatio >= s.ignitionEnableNgRatio);
        progress = (ngRatio - p.lightOffNgRatio) / ...
            (p.idleNgRatio - p.lightOffNgRatio);
        progress = min(max(progress, 0), 1);
        fuelTarget = p.lightOffFuelKgPerS + progress * ...
            (s.idleFuelFeedforwardKgPerS - p.lightOffFuelKgPerS);
        pitchDeg = s.startPitchDeg;
        targetRatio = s.idleNpRatio;
        return;
    case 2
        command = 1;
        ignition = 1;
        targetRatio = s.idleNpRatio;
        % 起动控制已经完成升速、加桨距和连续保持，不再重复加载。
        pitchDeg = s.idlePitchDeg;
        fuelTarget = s.idleFuelFeedforwardKgPerS;
    case 3
        command = 2;
        ignition = 1;
        progress = local_smooth_progress(segmentTime / s.cruiseRampS);
        targetRatio = s.idleNpRatio + ...
            (s.cruiseNpRatio - s.idleNpRatio) * progress;
        pitchDeg = s.idlePitchDeg + ...
            (s.cruisePitchDeg - s.idlePitchDeg) * progress;
    case 4
        command = 2;
        ignition = 1;
        targetRatio = s.cruiseNpRatio;
        pitchDeg = s.cruisePitchDeg;
    case 5
        command = 2;
        ignition = 1;
        progress = local_smooth_progress(segmentTime / s.returnRampS);
        targetRatio = s.cruiseNpRatio - ...
            (s.cruiseNpRatio - s.idleNpRatio) * progress;
        pitchDeg = s.cruisePitchDeg - ...
            (s.cruisePitchDeg - s.idlePitchDeg) * progress;
    case 6
        command = 2;
        ignition = 1;
        targetRatio = s.idleNpRatio;
        pitchDeg = s.idlePitchDeg;
    otherwise
        command = 3;
        ignition = 0;
        pitchDeg = s.startPitchDeg;
        targetRatio = 0;
        fuelTarget = 0;
        return;
end
end

function [segment, segmentTime, stableTime, idleStable, cruiseStable, ...
    completed, failure, startupBegin, shutdownBegin] = ...
    local_advance_segment(segment, segmentTime, stableTime, idleStable, ...
    cruiseStable, output, npRpm, ngRpm, rotorRpm, targetRatio, timeS, ...
    startupBegin, shutdownBegin, cfg,controlElapsed,startupControl)
s = cfg.stage6;
p = cfg.startStop;
failure = '';
completed = false;
segmentTime = segmentTime + s.timeStepS;

stable = abs(npRpm / p.designNpRpm - targetRatio) <= ...
    s.npStableToleranceRatio && ...
    abs(output(1)) <= s.npDotStableToleranceRpmPerS && ...
    abs(output(2)) <= s.ngDotStableToleranceRpmPerS;
% 正式接管必须有明确时刻；负载斜坡已经在起动保持之前完成。
if segment == 2 && (~isfinite(controlElapsed) || controlElapsed<s.idleHandoverRampS)
    stable = false;
end
if stable
    stableTime = stableTime + s.timeStepS;
else
    stableTime = 0;
end

switch segment
    case 0
        if segmentTime >= s.initialHoldS
            segment = 1;
            segmentTime = 0;
            stableTime = 0;
            startupBegin = timeS;
        end
    case 1
        % Ng稳定暖机许可在下一步开始处判断；达到慢车与完成暖机分别限时。
        everStable=~isempty(startupControl) && isfinite(startupControl.firstStableTimeS);
        if ~everStable && isfinite(startupBegin) && timeS-startupBegin>s.maximumStartupS
            failure = sprintf('起动超过%.3g s仍未到达慢车阶段。', ...
                s.maximumStartupS);
        elseif isfinite(startupBegin) && timeS-startupBegin> ...
                s.maximumStartupS+s.startupIdleHoldS+s.maximumIdleSettleS
            failure='已到慢车但未能完成连续稳定暖机，超过允许等待时间。';
        end
    case 2
        if stableTime >= s.idleStableDwellS
            idleStable = true;
            segment = 3;
            segmentTime = 0;
            stableTime = 0;
        elseif segmentTime > s.maximumIdleSettleS
            failure = sprintf('慢车在%.3g s内未稳定。', ...
                s.maximumIdleSettleS);
        end
    case 3
        if segmentTime >= s.cruiseRampS
            segment = 4;
            segmentTime = 0;
            stableTime = 0;
        end
    case 4
        if stableTime >= s.cruiseStableDwellS
            cruiseStable = true;
            segment = 5;
            segmentTime = 0;
            stableTime = 0;
        elseif segmentTime > s.maximumCruiseHoldS
            failure = sprintf('巡航在%.3g s内未稳定。', ...
                s.maximumCruiseHoldS);
        end
    case 5
        if segmentTime >= s.returnRampS
            segment = 6;
            segmentTime = 0;
            stableTime = 0;
        end
    case 6
        if segmentTime >= s.idleBeforeShutdownS
            segment = 7;
            segmentTime = 0;
            stableTime = 0;
            shutdownBegin = timeS;
        end
    case 7
        if output(4) == 10
            segment = 8;
            segmentTime = 0;
            stableTime = 0;
        elseif isfinite(shutdownBegin) && timeS - shutdownBegin > ...
                s.maximumShutdownS
            failure = sprintf('停车超过%.3g s仍未到达停车完成阶段。', ...
                s.maximumShutdownS);
        end
    case 8
        stopped = max([ngRpm, npRpm, rotorRpm]) <= ...
            s.stopSpeedToleranceRpm;
        if stopped && segmentTime >= s.zeroHoldAfterStopS
            segment = 9;
            completed = true;
        end
end

if timeS >= s.maximumMissionS && ~completed && isempty(failure)
    failure = sprintf('任务超过总时限%.3g s。', s.maximumMissionS);
end
end

function seeds = local_candidate_seeds(points, currentSeed, previousRoot, ...
    ngRpm, npRpm, fired, previousPhase, cfg)
% 正常情况下首选上一时刻根。LIGHT_OFF阶段存在无燃烧和已燃烧两个
% 吸引域，优先使用阶段五已燃根；只有主初值失败时才依次尝试邻近根。
if previousPhase == 3
    primary = local_select_stage5_seed(points, ngRpm, npRpm, true, cfg);
else
    primary = currentSeed(:);
end
candidate = primary.';
if all(isfinite(previousRoot))
    candidate(end + 1, :) = previousRoot(:).';
end

finiteVariable = reshape(arrayfun( ...
    @(item) all(isfinite(item.variable)), points), 1, []);
available = reshape([points.applicable], 1, []) & ...
    reshape([points.accepted], 1, []) & ...
    reshape([points.solverStatus], 1, []) == 0 & ...
    reshape([points.ngRatio], 1, []) > 0 & finiteVariable;
pool = points(available);
ngRatio = ngRpm / cfg.startStop.designNgRpm;
npRatio = npRpm / cfg.startStop.designNpRpm;
isFired = strcmp({pool.stateName}, 'fired_low_fuel');
statePenalty = double(isFired ~= fired);
distance = ([pool.ngRatio] - ngRatio).^2 + ...
    ([pool.npRatio] - npRatio).^2 + 0.25 * statePenalty;
[~, order] = sort(distance, 'ascend');
for i = order
    candidate(end + 1, :) = pool(i).variable(:).'; %#ok<AGROW>
    if size(candidate, 1) >= 2 * cfg.stage6.maximumRootRetries
        break;
    end
end
candidate = unique(round(candidate * 1e11) / 1e11, 'rows', 'stable');
seeds = candidate(1:min(size(candidate, 1), ...
    cfg.stage6.maximumRootRetries), :);
end

function attempt = local_execute_step(alias, engPtr, cfg, maps, ...
    npRpm, ngRpm, rotorRpm, fuel, command, ignition, pitchDeg, ...
    gasTemperatureK, seeds, previousPhase, thermal, captureTrace)
% 正式step仍沿用原15参数合同。只有零时间评估采集完整数值尝试证据。
if nargin<16,captureTrace=false;end
if captureTrace,history=cell(0,1);end
template = struct('callStatus', -999, 'output', zeros(128, 1), ...
    'diagnostics', nan(97, 1), 'snapshot', local_empty_snapshot(cfg), ...
    'attemptCount', 0, 'converged', false, 'errorMessage', '');
attempt = template;
bestScore = [Inf, Inf, Inf];
for i = 1:size(seeds, 1)
    current = template;
    current.attemptCount = i;
    input = local_step_input(cfg, npRpm, ngRpm, rotorRpm, fuel, ...
        command, ignition, pitchDeg, gasTemperatureK, seeds(i, :).', ...
        thermal);
    inputPointer = libpointer('doublePtr', input);
    outputPointer = libpointer('doublePtr', zeros(128, 1));
    try
        if isfield(cfg,'fullmode') && isfield(cfg.fullmode,'active') && cfg.fullmode.active
            loadBoundary=sht_fullmode_load_boundary(cfg,npRpm,rotorRpm);
            status=calllib(alias,'DLL_SHT_FullModeSetLoad',26100701,7, ...
                libpointer('doublePtr',loadBoundary.vector));
            assert(status==0,'会话负载合同被DLL拒绝：%d。',status);
        end
        [current.callStatus, ~, current.output, engOut] = calllib( ...
            alias, 'DLL_SHT_RunStartStopStep', ...
            inputPointer, outputPointer, engPtr);
        current.diagnostics = local_read_diagnostics(alias);
        if current.callStatus == 0 && current.diagnostics(1) ~= 6
            current.snapshot = local_capture_engine(engOut.eng, maps,cfg);
        elseif current.callStatus == 0
            current.snapshot.physicalValid = true;
        end
        if current.callStatus == 0 && thermal.enabled
            current.snapshot = local_capture_thermal( ...
                current.snapshot, engOut.eng);
        end
        current.converged = current.callStatus == 0 && ...
            ((current.diagnostics(1) == 0 && ...
            current.diagnostics(2) > 0.5) || current.diagnostics(1) == 6) && ...
            current.output(24) > 0.5;
    catch errorObject
        current.errorMessage = errorObject.message;
    end

    if captureTrace
        history{end+1}=struct('seed',seeds(i,:),'stepIn',input, ...
            'callStatus',current.callStatus,'diagnostics',current.diagnostics, ...
            'gasResidual',current.diagnostics(33+(1:cfg.topology.gasCount)), ...
            'stepOut',current.output,'converged',current.converged, ...
            'exceptionMessage',current.errorMessage); %#ok<AGROW>
    end

    score = [double(~current.converged), ...
        local_finite_or_inf(current.diagnostics(13)), ...
        local_finite_or_inf(current.diagnostics(14))];
    if local_lexicographic_less(score, bestScore)
        bestScore = score;
        attempt = current;
    end
    if current.converged
        attempt = current;
        break;
    end
end

% 若某个失败尝试先改变了阶段而后续尝试才收敛，C状态机不会重复发出
% 同一事件。根据跨步阶段变化恢复一次性事件码，保证事件证据不丢失。
if attempt.converged && attempt.output(13) == 0 && ...
        attempt.output(4) ~= previousPhase
    attempt.output(13) = local_phase_transition_event( ...
        previousPhase, attempt.output(4));
end
if captureTrace
    attempt.candidateSeeds=seeds;attempt.attemptHistory=history;
end
end

function event = local_phase_transition_event(previousPhase, currentPhase)
event = 0;
if any(previousPhase == [0, 10]) && currentPhase == 1
    event = 1;
elseif previousPhase == 1 && currentPhase == 2
    event = 2;
elseif previousPhase == 2 && currentPhase == 3
    event = 3;
elseif any(previousPhase == [3, 4]) && currentPhase == 5
    event = 4;
elseif previousPhase >= 3 && previousPhase <= 5 && currentPhase == 6
    event = 5;
elseif previousPhase < 7 && currentPhase == 7
    event = 6;
elseif currentPhase == 9 && previousPhase ~= 9
    event = 7;
elseif previousPhase == 9 && currentPhase == 10
    event = 9;
end
end

function input = local_step_input(cfg, npRpm, ngRpm, rotorRpm, fuel, ...
    command, ignition, pitchDeg, gasTemperatureK, seed, thermal)
if thermal.enabled
    input = thermal.stepInTemplate;
else
    input = zeros(512, 1);
end
input(1) = npRpm;
input(2) = ngRpm;
input(3) = fuel;
input(4) = cfg.startStop.nozzleAreaM2;
input(5) = 0;
input(7) = cfg.startStop.gtAccessoryPowerW;
input(17) = 0;
input(18) = 0;
input(20+(1:cfg.topology.gasCount)) = seed;
input(30) = cfg.stage6.timeStepS;
input(31) = command;
input(32) = rotorRpm;
input(33) = pitchDeg;
input(34) = ignition;
input(35) = gasTemperatureK;
input(36) = 1;
if isfield(cfg,'fullmode') && isfield(cfg.fullmode,'active') && ...
        cfg.fullmode.active && isfield(cfg.fullmode,'inletBoundary')
    % 配平、Heun两次斜率/校正及恢复评估共用此入口；H/N均实传同一边界。
    input=sht_apply_inlet_boundary_stepin(input,cfg.fullmode.inletBoundary);
end
if thermal.enabled
    input(cfg.topology.temperatureInputIndices) = thermal.state;
    loadPowerW = local_rotor_load_power( ...
        cfg, rotorRpm, pitchDeg);
    if isfield(cfg,'fullmode') && isfield(cfg.fullmode,'active') && cfg.fullmode.active
        loadBoundary=sht_fullmode_load_boundary(cfg,npRpm,rotorRpm);
        loadPowerW=loadBoundary.referencePowerW;
    end
    epsilonSS = sht_lookup_clearance_reference( ...
        thermal.referenceTable, npRpm, ngRpm, loadPowerW, ...
        thermal.inletTotalTemperatureK);
    input(cfg.topology.referenceIndices) = epsilonSS(:);
else
    input(341) = 0;
end
end

function seed = local_select_stage5_seed(points, ngRpm, npRpm, fired, cfg)
% 严格零速保持点没有执行七维Newton，其diagnostics变量只是零值占位，
% 不能作为首个非零转速点的共同工作初值。这里只允许使用真正由七维
% 求解器收敛得到、无边界命中且变量有限的阶段五根。
finiteVariable = reshape(arrayfun( ...
    @(item) all(isfinite(item.variable)), points), 1, []);
applicable = reshape([points.applicable], 1, []) & ...
    reshape([points.accepted], 1, []) & ...
    reshape([points.solverStatus], 1, []) == 0 & ...
    reshape([points.ngRatio], 1, []) > 0 & finiteVariable;
candidate = points(applicable);
assert(~isempty(candidate), '阶段五没有可用的已收敛根。');
if fired
    statePenalty = ~strcmp({candidate.stateName}, 'fired_low_fuel');
else
    statePenalty = strcmp({candidate.stateName}, 'fired_low_fuel');
end
ngRatio = ngRpm / cfg.startStop.designNgRpm;
npRatio = npRpm / cfg.startStop.designNpRpm;
distance = ([candidate.ngRatio] - ngRatio).^2 + ...
    ([candidate.npRatio] - npRatio).^2 + 0.25 * statePenalty;
[~, index] = min(distance);
seed = candidate(index).variable(:);
end

function maps = local_read_maps(cfg, mapDirectory)
components = cfg.topology.componentNames;
maps = struct();
for i = 1:numel(components)
    name = components{i};
    definition = cfg.maps.(name);
    mapPath = fullfile(mapDirectory, definition.outputName);
    assert(isfile(mapPath), '连续任务缺少特性图：%s。', mapPath);
    action = ['read', upper(definition.kind(1)), definition.kind(2:end)];
    maps.(name) = sht_tmats_map_io(action, mapPath);
end
end

function diagnostics = local_read_diagnostics(alias)
pointer = libpointer('doublePtr', zeros(97, 1));
status = calllib(alias, 'DLL_SHT_LowSpeedSolverGetDiagnostics', pointer, 97);
assert(status == 0, '读取低速求解诊断失败，状态码=%d。', status);
diagnostics = pointer.Value;
end

function snapshot = local_capture_engine(eng,maps,cfg)
snapshot=local_empty_snapshot(cfg);
gas=sht_startstop_engine_snapshot(eng,maps,cfg);
names=fieldnames(gas);
for i=1:numel(names), snapshot.(names{i})=gas.(names{i}); end
if isfield(cfg,'fullmode') && isfield(cfg.fullmode,'active') && ...
        cfg.fullmode.active && isfield(cfg.fullmode,'inletBoundary')
    % 只增加M内部诊断，不改变Engine公开结构或默认路径的快照字段。
    snapshot.inletBoundaryActual=struct('inletBoundaryMode',double(eng.useInletBoundaryInput), ...
        'Pt1',double(eng.Ambient.gasPathOut(4)),'Tt1',double(eng.Ambient.gasPathOut(3)), ...
        'Pamb',double(eng.Ambient.y(5)),'Tamb',double(eng.Ambient.y(6)), ...
        'altitude',double(eng.altitude),'Mach',double(eng.machNumber), ...
        'deltaTemperature',double(eng.dTemperature));
end
end

function snapshot = local_capture_thermal(snapshot, eng)
try
    heat = eng.transientHeatEvaluation;
    clearance = eng.transientClearanceEvaluation;
    snapshot.thermalNormalizedEnergyResidual = ...
        double(heat.visserNormalizedEnergyResidual);
    snapshot.thermalEnergyResidualW = double(heat.visserEnergyResidual);
    snapshot.rootDiskHeatFlowW = ...
        double(heat.visserRootDiskHeatFlow(:));
    snapshot.actualClearance = double(clearance.actualClearance(:));
    snapshot.steadyClearance = double(clearance.steadyClearance(:));
    snapshot.dynamicClearance = double(clearance.dynamicClearance(:));
    snapshot.clearanceFlowMultiplier = ...
        double(clearance.flowMultiplier(:));
    snapshot.clearanceEfficiencyMultiplier = ...
        double(clearance.efficiencyMultiplier(:));
    diagnostics = eng.transientDiagnostics;
    snapshot.transientErrorCode = double(diagnostics.errorCode);
    snapshot.transientOffendingStepInIndex = ...
        double(diagnostics.offendingStepInIndex);
    snapshot.transientOffendingValue = double(diagnostics.offendingValue);
    snapshot.heatFeedbackApplied = ...
        double(diagnostics.heatFeedbackApplied(:));
    snapshot.heatFeedbackConverged = ...
        double(diagnostics.heatFeedbackConverged(:));
    snapshot.heatFeedbackIterationCount = ...
        double(diagnostics.heatFeedbackIterationCount(:));
    snapshot.heatFeedbackIterationResidual = ...
        double(diagnostics.heatFeedbackIterationResidual(:));
    values = [snapshot.thermalNormalizedEnergyResidual; ...
        snapshot.thermalEnergyResidualW; snapshot.rootDiskHeatFlowW; ...
        snapshot.actualClearance; snapshot.steadyClearance; ...
        snapshot.dynamicClearance; snapshot.clearanceFlowMultiplier; ...
        snapshot.clearanceEfficiencyMultiplier; ...
        snapshot.heatFeedbackIterationResidual];
    snapshot.thermalValid = all(isfinite(values));
catch errorObject
    snapshot.thermalValid = false;
    snapshot.errorMessage = strtrim(sprintf('%s %s', ...
        snapshot.errorMessage, errorObject.message));
end
end

function margin = local_axis_margin(value, axis)
axis = axis(:);
span = max(axis(end) - axis(1), eps);
margin = min((value - axis(1)) / span, (axis(end) - value) / span);
end

function snapshot = local_empty_snapshot(cfg)
snapshot=sht_startstop_engine_snapshot([],struct(),cfg);
snapshot.thermalNormalizedEnergyResidual=NaN;
snapshot.thermalEnergyResidualW=NaN;
diskFields={'rootDiskHeatFlowW','actualClearance','steadyClearance', ...
    'dynamicClearance','clearanceFlowMultiplier','clearanceEfficiencyMultiplier'};
for i=1:numel(diskFields), snapshot.(diskFields{i})=nan(cfg.topology.diskCount,1); end
heatFields={'heatFeedbackApplied','heatFeedbackConverged', ...
    'heatFeedbackIterationCount','heatFeedbackIterationResidual'};
for i=1:numel(heatFields), snapshot.(heatFields{i})=nan(numel(cfg.topology.heatNames),1); end
snapshot.transientErrorCode=NaN;
snapshot.transientOffendingStepInIndex=NaN;
snapshot.transientOffendingValue=NaN;
snapshot.thermalValid=false;
end

function thermal = local_initialize_thermal_context(cfg)
thermal = struct('enabled', false, 'state', zeros(cfg.topology.temperatureCount, 1), ...
    'initialState', zeros(cfg.topology.temperatureCount, 1), 'stateNames', {cell(cfg.topology.temperatureCount, 1)}, ...
    'stepInTemplate', zeros(512, 1), 'referenceTable', struct(), ...
    'inletTotalTemperatureK', 288.15, 'heatCapacityJPerK', ...
    ones(cfg.topology.temperatureCount, 1), 'diskRootMetalIndex', (1:cfg.topology.diskCount).', ...
    'clearanceEnabled', false);
if ~isfield(cfg, 'stage7') || ~isstruct(cfg.stage7) || ...
        ~isfield(cfg.stage7, 'enabled') || ~cfg.stage7.enabled
    return;
end
required = {'initialTemperatureState','stateNames','stepInTemplate', ...
    'referenceTable','inletTotalTemperatureK','heatCapacityJPerK', ...
    'diskRootMetalIndex'};
for i = 1:numel(required)
    assert(isfield(cfg.stage7, required{i}), ...
        '阶段七运行配置缺少字段%s。', required{i});
end
state = cfg.stage7.initialTemperatureState(:);
names = cfg.stage7.stateNames(:);
template = cfg.stage7.stepInTemplate(:);
capacity = cfg.stage7.heatCapacityJPerK(:);
rootIndex = cfg.stage7.diskRootMetalIndex(:);
assert(numel(state) == cfg.topology.temperatureCount && all(isfinite(state)) && all(state > 0), ...
    '阶段七初始温度必须包含当前拓扑数量的有限正值。');
assert(iscell(names) && numel(names) == cfg.topology.temperatureCount, ...
    '阶段七热状态名称数量必须与当前模型拓扑一致。');
assert(numel(template) == 512 && template(341) == 1 && ...
    template(342) == 3 && template(344) == 1, ...
    '阶段七stepIn模板必须显式启用Visser热状态。');
assert(numel(capacity) == cfg.topology.temperatureCount && all(isfinite(capacity)) && ...
    all(capacity > 0), '阶段七热容向量必须包含当前拓扑数量的有限正值。');
assert(numel(rootIndex) == cfg.topology.diskCount && all(rootIndex == round(rootIndex)) && ...
    all(rootIndex >= 1 & rootIndex <= cfg.topology.metalCount), ...
    '阶段七各转盘对应的根部金属索引非法。');
assert(isscalar(cfg.stage7.inletTotalTemperatureK) && ...
    isfinite(cfg.stage7.inletTotalTemperatureK) && ...
    cfg.stage7.inletTotalTemperatureK > 0, ...
    '阶段七进口总温必须为有限正标量。');
thermal.enabled = true;
thermal.state = state;
thermal.initialState = state;
thermal.stateNames = names;
thermal.stepInTemplate = template;
thermal.referenceTable = cfg.stage7.referenceTable;
thermal.inletTotalTemperatureK = cfg.stage7.inletTotalTemperatureK;
thermal.heatCapacityJPerK = capacity;
thermal.diskRootMetalIndex = rootIndex;
thermal.clearanceEnabled = template(346) > 0.5;
if isfield(cfg,'fullmode') && isfield(cfg.fullmode,'active') && ...
        cfg.fullmode.active && isfield(cfg.fullmode,'inletBoundary')
    % 参考间隙查询和气路输入必须采用同一Tt1，不沿用另一资产的默认温度。
    thermal.inletTotalTemperatureK=cfg.fullmode.inletBoundary.Tt1;
end
end

function public = local_public_thermal_context(thermal)
public = rmfield(thermal, {'stepInTemplate','referenceTable'});
end

function powerW = local_rotor_load_power(cfg, rotorRpm, pitchDeg)
p = cfg.startStop;
designOmega = p.designNpRpm * pi / 30;
designTorque = p.designRotorPowerW / designOmega;
speedRatio = min(max(abs(rotorRpm) / p.designNpRpm, 0), 1.5);
pitchRatio = min(max((pitchDeg - p.thetaZeroDeg) / ...
    (p.thetaDesignDeg - p.thetaZeroDeg), 0), 1.5);
pitchLoad = p.profileTorqueFraction + ...
    (1 - p.profileTorqueFraction) * pitchRatio ^ 1.5;
loadTorque = designTorque * pitchLoad * speedRatio ^ 2 + ...
    p.rotorCoulombLossNm * tanh(rotorRpm / 20) + ...
    p.rotorViscousLossNmPerKrpm * abs(rotorRpm) / 1000;
powerW = max(0, loadTorque * abs(rotorRpm) * pi / 30);
end

function [names, c] = local_thermal_trace_schema(thermal,cfg)
names = {'time','segment'};
for i = 1:numel(thermal.stateNames)
    names{end + 1} = thermal.stateNames{i}; %#ok<AGROW>
end
for i = 1:numel(thermal.stateNames)
    names{end + 1} = ['d_', thermal.stateNames{i}]; %#ok<AGROW>
end
names = [names, {'normalizedEnergyResidual','energyResidualW', ...
    'thermalValid','transientErrorCode','transientOffendingStepInIndex', ...
    'transientOffendingValue'}];
heatComponents = cfg.topology.heatNames;
for i = 1:numel(heatComponents)
    name = heatComponents{i};
    names = [names, {['heatFeedbackApplied_', name], ...
        ['heatFeedbackConverged_', name], ...
        ['heatFeedbackIterationCount_', name], ...
        ['heatFeedbackIterationResidual_', name]}]; %#ok<AGROW>
end
components = cfg.topology.componentNames;
for i = 1:numel(components)
    name = components{i};
    names = [names, {['rootDiskHeatFlow_', name], ...
        ['actualClearance_', name], ['steadyClearance_', name], ...
        ['dynamicClearance_', name], ['flowMultiplier_', name], ...
        ['efficiencyMultiplier_', name]}]; %#ok<AGROW>
end
names = matlab.lang.makeUniqueStrings( ...
    matlab.lang.makeValidName(names, 'ReplacementStyle', 'delete'));
c = cell2struct(num2cell(1:numel(names)), names, 2);
end

function row = local_thermal_trace_row(timeS, segment, state, derivative, ...
    snapshot, c, count,cfg)
row = nan(1, count);
row(c.time) = timeS;
row(c.segment) = segment;
% time和segment之后固定为当前拓扑数量的状态、当前拓扑数量的导数，避免依赖字段字典顺序。
row(2+(1:numel(state))) = state(:).';
row(2+numel(state)+(1:numel(state))) = derivative(:).';
row(c.normalizedEnergyResidual) = ...
    snapshot.thermalNormalizedEnergyResidual;
row(c.energyResidualW) = snapshot.thermalEnergyResidualW;
row(c.thermalValid) = snapshot.thermalValid;
row(c.transientErrorCode) = snapshot.transientErrorCode;
row(c.transientOffendingStepInIndex) = ...
    snapshot.transientOffendingStepInIndex;
row(c.transientOffendingValue) = snapshot.transientOffendingValue;
heatComponents = cfg.topology.heatNames;
for i = 1:numel(heatComponents)
    name = heatComponents{i};
    row(c.(['heatFeedbackApplied_', name])) = ...
        snapshot.heatFeedbackApplied(i);
    row(c.(['heatFeedbackConverged_', name])) = ...
        snapshot.heatFeedbackConverged(i);
    row(c.(['heatFeedbackIterationCount_', name])) = ...
        snapshot.heatFeedbackIterationCount(i);
    row(c.(['heatFeedbackIterationResidual_', name])) = ...
        snapshot.heatFeedbackIterationResidual(i);
end
components = cfg.topology.componentNames;
for i = 1:numel(components)
    name = components{i};
    row(c.(['rootDiskHeatFlow_', name])) = snapshot.rootDiskHeatFlowW(i);
    row(c.(['actualClearance_', name])) = snapshot.actualClearance(i);
    row(c.(['steadyClearance_', name])) = snapshot.steadyClearance(i);
    row(c.(['dynamicClearance_', name])) = snapshot.dynamicClearance(i);
    row(c.(['flowMultiplier_', name])) = ...
        snapshot.clearanceFlowMultiplier(i);
    row(c.(['efficiencyMultiplier_', name])) = ...
        snapshot.clearanceEfficiencyMultiplier(i);
end
end

function [names, c] = local_trace_schema(cfg)
names = {'time','segment','command','phase','event','Np','Ng','Nrotor', ...
    'NpTargetRatio','NgDot','NpDot','NrotorDot','pitchDeg', ...
    'commandedFuel','effectiveFuel','flameFraction','starterTorque', ...
    'hpsGasTorque','ptGasTorque','hpsNetTorque','ptNetTorque', ...
    'rotorNetTorque','rotorLoadTorque','freewheelTorque', ...
    'requiredFreewheelTorque','freewheelEngaged','Tt45', ...
    'hotStart','hungStart','flameout','physicsValid','callStatus', ...
    'rootAttempts', ...
    'solverStatus','solverConverged','iterations','functionEvaluations', ...
    'residualRms','maximumResidual','conditionNumber','rank', ...
    'boundaryCount','normalizedRootStep','minimumMapMargin', ...
    'mapExtrapolated'};
components = cfg.topology.componentNames;
for i = 1:numel(components)
    names{end + 1} = [components{i}, '_NcMap']; %#ok<AGROW>
    names{end + 1} = [components{i}, '_Path']; %#ok<AGROW>
    names{end + 1} = [components{i}, '_Margin']; %#ok<AGROW>
end
c = cell2struct(num2cell(1:numel(names)), names, 2);
end

function row = local_trace_row(timeS, segment, command, output, ...
    npRpm, ngRpm, rotorRpm, targetRatio, pitchDeg, commandedFuel, ...
    gasTemperatureK, callStatus, diagnostics, rootStep, rootAttempts, ...
    snapshot, c, count,cfg)
row = nan(1, count);
row(c.time) = timeS;
row(c.segment) = segment;
row(c.command) = command;
row(c.phase) = output(4);
row(c.event) = output(13);
row(c.Np) = npRpm;
row(c.Ng) = ngRpm;
row(c.Nrotor) = rotorRpm;
row(c.NpTargetRatio) = targetRatio;
row(c.NgDot) = output(2);
row(c.NpDot) = output(1);
row(c.NrotorDot) = output(3);
row(c.pitchDeg) = pitchDeg;
row(c.commandedFuel) = commandedFuel;
row(c.effectiveFuel) = output(6);
row(c.flameFraction) = output(7);
row(c.starterTorque) = output(5);
row(c.hpsGasTorque) = snapshot.hpsGasTorqueNm;
row(c.ptGasTorque) = snapshot.ptGasTorqueNm;
row(c.hpsNetTorque) = output(15);
row(c.ptNetTorque) = output(16);
row(c.rotorNetTorque) = output(17);
row(c.rotorLoadTorque) = output(10);
row(c.freewheelTorque) = output(11);
row(c.requiredFreewheelTorque) = output(14);
row(c.freewheelEngaged) = output(12);
row(c.Tt45) = gasTemperatureK;
row(c.hotStart) = output(21);
row(c.hungStart) = output(22);
row(c.flameout) = output(23);
row(c.physicsValid) = output(24);
row(c.callStatus) = callStatus;
row(c.rootAttempts) = rootAttempts;
row(c.solverStatus) = diagnostics(1);
row(c.solverConverged) = diagnostics(2);
row(c.iterations) = diagnostics(3);
row(c.functionEvaluations) = diagnostics(4);
row(c.residualRms) = diagnostics(13);
row(c.maximumResidual) = diagnostics(14);
row(c.conditionNumber) = diagnostics(17);
row(c.rank) = diagnostics(9);
row(c.boundaryCount) = diagnostics(11);
row(c.normalizedRootStep) = rootStep;
row(c.minimumMapMargin) = snapshot.minimumMapMargin;
row(c.mapExtrapolated) = snapshot.mapExtrapolated;
components = cfg.topology.componentNames;
for i = 1:numel(components)
    row(c.([components{i}, '_NcMap'])) = snapshot.mapCoordinate(i, 1);
    row(c.([components{i}, '_Path'])) = snapshot.mapCoordinate(i, 2);
    row(c.([components{i}, '_Margin'])) = min(snapshot.mapMargin(i, :));
end
end

function checks = local_acceptance_checks(trace, failureReason, ...
    idleStable, cruiseStable, completed, terminalSpeedRpm, cfg, idleTransfer)
s = cfg.stage6;
active = trace.solverStatus ~= 6;
events = trace.event;
requiredEvents = (1:9).';
firstEvent = nan(size(requiredEvents));
for i = 1:numel(requiredEvents)
    hit = find(events == requiredEvents(i), 1, 'first');
    if ~isempty(hit)
        firstEvent(i) = hit;
    end
end
freewheelDrop = find(diff(trace.freewheelEngaged) < -0.5) + 1;
freewheelRise = find(diff(trace.freewheelEngaged) > 0.5) + 1;
shutdown = trace.command == 3;
root = trace.normalizedRootStep(isfinite(trace.normalizedRootStep));
if isempty(root)
    maximumRootStep = 0;
else
    maximumRootStep = max(root);
end
mapMargin = trace.minimumMapMargin(isfinite(trace.minimumMapMargin));
if isempty(mapMargin)
    minimumMapMargin = 0;
else
    minimumMapMargin = min(mapMargin);
end

checks = struct();
checks.noRuntimeFailure = isempty(failureReason);
checks.completed = completed;
checks.finiteCoreStates = all(isfinite([trace.Np; trace.Ng; ...
    trace.Nrotor; trace.commandedFuel; trace.effectiveFuel]));
checks.allCallsSuccessful = all(trace.callStatus == 0);
checks.allPhysicsValid = all(trace.physicsValid > 0.5);
checks.allSolversConverged = all(trace.solverConverged(active) > 0.5);
normalGasPath = active & trace.phase ~= 9;
shutdownGasPath = active & trace.phase == 9;
checks.residualsAccepted = ...
    all(trace.residualRms(normalGasPath) <= s.residualRmsTolerance) && ...
    all(trace.maximumResidual(normalGasPath) <= ...
    s.maximumResidualTolerance) && ...
    all(trace.residualRms(shutdownGasPath) <= ...
    s.shutdownResidualRmsTolerance) && ...
    all(trace.maximumResidual(shutdownGasPath) <= ...
    s.shutdownMaximumResidualTolerance);
checks.rankAccepted = all(trace.rank(active) >= s.requiredRank);
checks.conditionAccepted = all(trace.conditionNumber(active) <= ...
    s.maximumCondition);
checks.noBoundaryHit = all(trace.boundaryCount(active) == 0);
checks.noMapExtrapolation = minimumMapMargin >= -1e-10 && ...
    ~any(trace.mapExtrapolated(active) > 0.5);
checks.eventOrder = all(isfinite(firstEvent)) && all(diff(firstEvent) > 0);
checks.idleStable = idleStable;
checks.cruiseStable = cruiseStable;
normalIdle=trace.segment==2 & trace.time>=idleTransfer.timeS+s.idleHandoverRampS;
checks.idleReferenceMatchesConfiguredSpeed = any(normalIdle) && ...
    all(abs(trace.NpTargetRatio(normalIdle)-s.idleNpRatio)<=1e-12);
hold = trace.time>=idleTransfer.timeS-s.startupIdleHoldS-1e-9 & ...
    trace.time<=idleTransfer.timeS+1e-9;
checks.startupStableHoldCompleted = nnz(hold)>=round(s.startupIdleHoldS/s.timeStepS)+1 && ...
    all(trace.startupStable(hold)>0.5) && ...
    all(abs(trace.Ng(hold)-s.startupIdleNgRpm)<=s.startupNgToleranceRpm);
checks.idleHandoverReferenceContinuous = any(hold) && ...
    all(abs(trace.startupNgReferenceDot(hold))<1e-9) && ...
    all(abs(trace.pitchDeg(hold)-s.idlePitchDeg)<1e-9);
checks.idleFuelTargetBumpless = isfinite(idleTransfer.sameInputCommandDifferenceKgPerS) && ...
    abs(idleTransfer.sameInputCommandDifferenceKgPerS)<=1e-10 && ...
    idleTransfer.controllerStateContinuous;
firstPowerRise = find(trace.segment == 3,1);
checks.idleRampCompletedBeforePowerRise = ~isempty(firstPowerRise) && ...
    trace.time(firstPowerRise)-idleTransfer.timeS >= ...
    s.idleHandoverRampS+s.idleStableDwellS-2*s.timeStepS;
checks.speedWithinLimit = max(trace.Np) <= ...
    s.maximumSpeedRatio * cfg.startStop.designNpRpm && ...
    max(trace.Ng) <= s.maximumSpeedRatio * cfg.startStop.designNgRpm;
checks.temperatureWithinLimit = max(trace.Tt45) <= s.maximumTt45K && ...
    ~any(trace.hotStart > 0.5);
checks.noHungOrFlameout = ~any(trace.hungStart > 0.5) && ...
    ~any(trace.flameout > 0.5);
checks.singleFreewheelDisengagement = numel(freewheelDrop) == 1;
checks.noFreewheelReengagement = isempty(freewheelRise);
engaged = trace.freewheelEngaged > 0.5;
checks.noNegativeTransmittedTorque = ...
    all(trace.freewheelTorque(engaged) >= -1e-8);
checks.shutdownFuelZero = any(shutdown) && ...
    all(abs(trace.effectiveFuel(shutdown)) <= 1e-12);
checks.rootContinuationAccepted = maximumRootStep <= ...
    s.maximumNormalizedRootStep;
checks.finalZeroSpeed = completed && ...
    max(terminalSpeedRpm) <= s.stopSpeedToleranceRpm;
ticks=trace.time(trace.controlTick>0.5);
checks.controllerClockAccepted=numel(ticks)>1 && ...
    max(abs(diff(ticks)-cfg.aboveIdle.sampleTimeS))<1e-9;
normal=trace.segment>=2 & trace.segment<=6 & trace.controlModeId~=10;
checks.controlFeedbackValid=any(normal) && all(isfinite(trace.Ngc(normal))) && ...
    all(trace.Ngc(normal)>0) && all(isfinite(trace.MkpFeedback));
checks.transmittedTorqueFeedbackAccepted= ...
    max(abs(trace.MkpFeedback(2:end)-trace.freewheelTorque(1:end-1)))<1e-9;
if strcmp(s.integrationMethod,'euler2')
    % Heun使用校正端点的传递扭矩；不能用上一积分起点的扭矩检查。
    checks.transmittedTorqueFeedbackAccepted= ...
        max(abs(trace.MkpFeedback-trace.MkpFeedbackExpected))<1e-9;
end
checks.ngProtectionLimitAccepted=max(trace.Ng)<=cfg.aboveIdle.controller.ngProtection.ngMax;
checks.mkpProtectionLimitAccepted=max(trace.freewheelTorque)<=cfg.aboveIdle.controller.mkpProtection.mkpMax;
wfRate=diff(trace.commandedFuel)/s.timeStepS;
notCutoff=trace.command(2:end)~=3;
checks.actuatorRateAccepted=all(abs(wfRate(notCutoff))<=cfg.aboveIdle.actuator.wfRateLimit+1e-10);
checks.accepted = all(cell2mat(struct2cell(checks)));
checks.firstEventIndex = firstEvent;
checks.maximumNormalizedRootStep = maximumRootStep;
checks.minimumMapMargin = minimumMapMargin;
checks.freewheelDisengagementIndex = freewheelDrop;
end

function checks = local_add_thermal_acceptance_checks( ...
    checks, thermalTrace, thermal, cfg)
s = cfg.stage7;
stateNames = thermal.stateNames(:).';
derivativeNames = cellfun(@(name) ['d_', name], stateNames, ...
    'UniformOutput', false);
temperature = thermalTrace{:, stateNames};
derivative = thermalTrace{:, derivativeNames};
thermalStep = sht_startstop_thermal_step_diagnostic(temperature,derivative, ...
    cfg.stage6.timeStepS,s.maximumThermalRateKPerS);
maximumEnergyResidual = max(abs(thermalTrace.normalizedEnergyResidual));

checks.thermalStateCountAccepted = size(temperature, 2) == cfg.topology.temperatureCount;
checks.thermalStatesFinite = all(isfinite(temperature(:))) && ...
    all(isfinite(derivative(:)));
checks.thermalStatesWithinBounds = ...
    min(temperature(:)) >= s.minimumTemperatureK && ...
    max(temperature(:)) <= s.maximumTemperatureK;
checks.thermalRateAccepted = thermalStep.accepted;
checks.thermalEvaluationValid = all(thermalTrace.thermalValid > 0.5);
checks.thermalEnergyBalanceAccepted = maximumEnergyResidual <= ...
    s.normalizedEnergyResidualTolerance;

% C端以“已请求热反馈但迭代次数为0”标记低速非压缩/非膨胀状态下的
% 受控旁路。它只允许发生在停车段；起动、慢车或巡航出现该旁路说明
% 热反馈没有真正参与，应直接判为验收失败。
heatComponents = cfg.topology.heatNames;
heatFeedbackBypassCount = zeros(1, numel(heatComponents));
bypassOutsideShutdown = false(height(thermalTrace), 1);
for i = 1:numel(heatComponents)
    name = heatComponents{i};
    bypass = thermalTrace.(['heatFeedbackApplied_', name]) > 0.5 & ...
        thermalTrace.(['heatFeedbackIterationCount_', name]) == 0;
    heatFeedbackBypassCount(i) = nnz(bypass);
    bypassOutsideShutdown = bypassOutsideShutdown | ...
        (bypass & thermalTrace.segment ~= 7);
end
checks.heatFeedbackBypassLimitedToShutdown = ...
    ~any(bypassOutsideShutdown);

if thermal.clearanceEnabled
    components = cfg.topology.componentNames;
    actual = zeros(height(thermalTrace), cfg.topology.diskCount);
    steady = zeros(height(thermalTrace), cfg.topology.diskCount);
    flowMultiplier = zeros(height(thermalTrace), cfg.topology.diskCount);
    efficiencyMultiplier = zeros(height(thermalTrace), cfg.topology.diskCount);
    for i = 1:cfg.topology.diskCount
        actual(:, i) = thermalTrace.(['actualClearance_', components{i}]);
        steady(:, i) = thermalTrace.(['steadyClearance_', components{i}]);
        flowMultiplier(:, i) = ...
            thermalTrace.(['flowMultiplier_', components{i}]);
        efficiencyMultiplier(:, i) = ...
            thermalTrace.(['efficiencyMultiplier_', components{i}]);
    end
    checks.clearanceStatesAccepted = all(isfinite([actual(:); steady(:)])) && ...
        all(actual(:) > 0) && all(steady(:) > 0) && ...
        all(isfinite([flowMultiplier(:); efficiencyMultiplier(:)])) && ...
        all(flowMultiplier(:) > 0) && all(efficiencyMultiplier(:) > 0);
else
    checks.clearanceStatesAccepted = true;
end

zeroFlow = thermalTrace.segment == 8;
checks.postStopHeatSoakCovered = nnz(zeroFlow) >= 2;
storedEnergyRelativeDrift = Inf;
heatRedistributionK = 0;
initialRootDiskDifferenceK = Inf;
finalRootDiskDifferenceK = Inf;
if checks.postStopHeatSoakCovered
    zeroTemperature = temperature(zeroFlow, :);
    storedEnergy = zeroTemperature * thermal.heatCapacityJPerK;
    storedEnergyRelativeDrift = ...
        (max(storedEnergy) - min(storedEnergy)) / ...
        max(abs(storedEnergy(1)), 1);
    difference = zeros(size(zeroTemperature, 1), cfg.topology.diskCount);
    for i = 1:cfg.topology.diskCount
        rootIndex = thermal.diskRootMetalIndex(i);
        diskIndex = cfg.topology.metalCount + i;
        difference(:, i) = zeroTemperature(:, rootIndex) - ...
            zeroTemperature(:, diskIndex);
    end
    reduction = abs(difference(1, :)) - abs(difference(end, :));
    heatRedistributionK = max(reduction);
    initialRootDiskDifferenceK = max(abs(difference(1,:)));
    finalRootDiskDifferenceK = max(abs(difference(end,:)));
end
checks.zeroFlowEnergyConserved = storedEnergyRelativeDrift <= ...
    s.zeroFlowStoredEnergyRelativeTolerance;
% 长滑转可能在机械停转之前已完成根部/转盘热平衡。此时不应要求
% 平衡态重新产生温差；非均匀温度下的换热能力另由物理单元测试验收。
checks.postStopInitiallyEquilibrated = initialRootDiskDifferenceK <= ...
    s.minimumHeatRedistributionK;
checks.postStopInternalRedistribution = heatRedistributionK >= ...
    s.minimumHeatRedistributionK || (checks.postStopInitiallyEquilibrated && ...
    finalRootDiskDifferenceK <= s.minimumHeatRedistributionK);

checks.maximumThermalStepK = thermalStep.maximumActualStepK;
checks.maximumThermalRateKPerS = thermalStep.maximumDerivativeKPerS;
checks.maximumSampledThermalRateKPerS = thermalStep.maximumSampledRateKPerS;
checks.maximumNormalizedEnergyResidual = maximumEnergyResidual;
checks.zeroFlowStoredEnergyRelativeDrift = storedEnergyRelativeDrift;
checks.maximumHeatRedistributionK = heatRedistributionK;
checks.initialPostStopRootDiskDifferenceK = initialRootDiskDifferenceK;
checks.heatFeedbackBypassTotalCount = sum(heatFeedbackBypassCount);
checks.heatFeedbackBypassCountByComponent = heatFeedbackBypassCount;
thermalChecks = [checks.thermalStateCountAccepted, ...
    checks.thermalStatesFinite, checks.thermalStatesWithinBounds, ...
    checks.thermalRateAccepted, checks.thermalEvaluationValid, ...
    checks.thermalEnergyBalanceAccepted, checks.clearanceStatesAccepted, ...
    checks.postStopHeatSoakCovered, checks.zeroFlowEnergyConserved, ...
    checks.postStopInternalRedistribution, ...
    checks.heatFeedbackBypassLimitedToShutdown];
checks.accepted = checks.accepted && all(thermalChecks);
end

function local_write_summary(path, caseDef, checks, trace, failureReason, ...
    terminalSpeedRpm, cfg, thermalTrace, idleTransfer)
fid = fopen(path, 'w');
assert(fid >= 0, '无法写入连续任务摘要：%s。', path);
cleanup = onCleanup(@() fclose(fid));
if isempty(thermalTrace)
    stageTitle = '第六阶段连续起停算例';
else
    stageTitle = '第七阶段Visser耦合连续起停算例';
end
fprintf(fid, '# %s：%s\n\n', stageTitle, caseDef.label);
fprintf(fid, '- 算例标识：`%s`\n', caseDef.name);
fprintf(fid, '- 总体结果：**%s**\n', local_pass(checks.accepted));
fprintf(fid, '- 连续步数：%d\n', height(trace));
fprintf(fid, '- 总时长：%.6g s\n', trace.time(end));
fprintf(fid, '- 最大 Ng/Np：%.6g / %.6g rpm\n', max(trace.Ng), max(trace.Np));
fprintf(fid, ['- 积分后终端 Np/Ng/旋翼等效转速：', ...
    '%.6g / %.6g / %.6g rpm\n'], terminalSpeedRpm(1), ...
    terminalSpeedRpm(2), terminalSpeedRpm(3));
fprintf(fid, '- 最大 Tt45：%.6g K\n', max(trace.Tt45));
fprintf(fid, '- 最大归一化根步长：%.6g（门限 %.6g）\n', ...
    checks.maximumNormalizedRootStep, cfg.stage6.maximumNormalizedRootStep);
fprintf(fid, '- 最小特性图归一化边界裕度：%.6g\n', checks.minimumMapMargin);
fprintf(fid, '- 慢车接管时刻：%.6g s；实际Np/目标Np：%.9g / %.9g（设计值比例）。\n', ...
    idleTransfer.timeS,idleTransfer.startNpRatio,idleTransfer.targetNpRatio);
fprintf(fid, '- 起动暖机Ng目标：%.6g rpm；误差带%.6g rpm内连续稳定%.6g s后转Np调速，Np目标%.6g rpm。\n', ...
    cfg.stage6.startupIdleNgRpm,cfg.stage6.startupNgToleranceRpm, ...
    cfg.stage6.startupIdleHoldS,cfg.stage6.idleNpRpm);
fprintf(fid, '- 正式交接与继续起动保持的同拍燃油命令差：%.9g kg/s；内部状态连续：%d。\n', ...
    idleTransfer.sameInputCommandDifferenceKgPerS,idleTransfer.controllerStateContinuous);
fprintf(fid, '- 接管前命令/接管后命令/实际计量燃油：%.9g / %.9g / %.9g kg/s。\n', ...
    idleTransfer.previousFuelKgPerS,idleTransfer.fuelTargetKgPerS, ...
    idleTransfer.appliedFuelKgPerS);
fprintf(fid, '- 统一控制：周期%.6g s，积分步长%.9g s，Tt45限制%.6g K，Ng限制%.6g rpm，Mkp限制%.6g Nm。\n', ...
    cfg.aboveIdle.sampleTimeS,cfg.stage6.timeStepS,cfg.stage6.maximumTt45K, ...
    cfg.aboveIdle.controller.ngProtection.ngMax,cfg.aboveIdle.controller.mkpProtection.mkpMax);
fprintf(fid, '- 发动机/热状态积分方法：%s；控制器每拍仅更新一次。\n',cfg.stage6.integrationMethod);
fprintf(fid, '- 旧表d41修复：%d；修复记录保存在controlConfiguration.torqueGainRepair。\n', ...
    cfg.aboveIdle.torqueGainRepair.applied);
if isempty(failureReason)
    fprintf(fid, '- 运行中断原因：无\n\n');
else
    fprintf(fid, '- 运行中断原因：%s\n\n', failureReason);
end

fprintf(fid, '## 事件时刻\n\n');
fprintf(fid, '|事件码|首次时刻/s|\n|---:|---:|\n');
for i = 1:9
    index = checks.firstEventIndex(i);
    if isfinite(index)
        eventTime = trace.time(index);
    else
        eventTime = NaN;
    end
    fprintf(fid, '|%d|%.6g|\n', i, eventTime);
end

fprintf(fid, '\n## 验收判据\n\n');
fields = fieldnames(checks);
skip = {'accepted','firstEventIndex','maximumNormalizedRootStep', ...
    'minimumMapMargin','freewheelDisengagementIndex', ...
    'maximumThermalStepK','maximumThermalRateKPerS', ...
    'maximumSampledThermalRateKPerS','maximumNormalizedEnergyResidual', ...
    'zeroFlowStoredEnergyRelativeDrift','maximumHeatRedistributionK', ...
    'heatFeedbackBypassTotalCount', ...
    'heatFeedbackBypassCountByComponent','postStopInitiallyEquilibrated', ...
    'initialPostStopRootDiskDifferenceK'};
for i = 1:numel(fields)
    if ~ismember(fields{i}, skip)
        fprintf(fid, '- `%s`：%s\n', fields{i}, ...
            local_pass(checks.(fields{i})));
    end
end
if ~isempty(thermalTrace)
    fprintf(fid, '\n## Visser热网络量化结果\n\n');
    fprintf(fid, '- 热状态数：%d（发动机状态数为%d，不含旋翼）。\n',cfg.topology.temperatureCount,cfg.topology.temperatureCount+2);
    fprintf(fid, '- 最大实际相邻采样温差：%.6g K。\n', ...
        checks.maximumThermalStepK);
    fprintf(fid, '- 最大热导数/相邻样本温变率：%.6g / %.6g K/s（工程上限%.6g K/s；非积分误差）。\n', ...
        checks.maximumThermalRateKPerS,checks.maximumSampledThermalRateKPerS, ...
        cfg.stage7.maximumThermalRateKPerS);
    fprintf(fid, '- 最大归一化能量残差：%.6e。\n', ...
        checks.maximumNormalizedEnergyResidual);
    fprintf(fid, '- 零流量热浸总储能相对漂移：%.6e。\n', ...
        checks.zeroFlowStoredEnergyRelativeDrift);
    fprintf(fid, '- 根部-转盘温差最大收缩量：%.6g K。\n', ...
        checks.maximumHeatRedistributionK);
    fprintf(fid,'- 机械停转时最大根部-转盘温差：%.6g K；已热平衡：%d。\n', ...
        checks.initialPostStopRootDiskDifferenceK,checks.postStopInitiallyEquilibrated);
    fprintf(fid, '- 低速非压缩/非膨胀热反馈旁路次数（%s）：',strjoin(cfg.topology.heatNames,'/'));
    fprintf(fid, '%d ', checks.heatFeedbackBypassCountByComponent);
    fprintf(fid, '。\n');
end
end

function path = local_plot_thermal_trace(trace, caseDef, outputDir, cfg, thermal)
visibility = local_visibility(cfg.stage7.showFigures);
pointCount = min(height(trace), cfg.stage6.maximumPlotPoints);
index = unique(round(linspace(1, height(trace), pointCount)));
t = trace.time(index);
temperature = trace{index, thermal.stateNames};
metal = temperature(:, 1:cfg.topology.metalCount);
diskGuide = temperature(:, cfg.topology.metalCount+1:end);
f = figure('Visible', visibility, 'Color', 'w', ...
    'Name', ['阶段七Visser热网络：', caseDef.label], ...
    'NumberTitle', 'off', 'Position', [70 70 1450 900]);
cleanup = onCleanup(@() local_close_if_hidden(f, cfg.stage7.showFigures));

subplot(2, 2, 1);
plot(t, metal, 'LineWidth', 0.8); grid on;
xlabel('时间 / s'); ylabel('金属温度 / K'); title('部件金属温度状态');

subplot(2, 2, 2);
plot(t, diskGuide, 'LineWidth', 0.9); grid on;
xlabel('时间 / s'); ylabel('温度 / K');
title(sprintf('%d个转盘与%d个导向器温度',cfg.topology.diskCount,cfg.topology.guideCount));
legend(thermal.stateNames(cfg.topology.metalCount+1:end), 'Interpreter', 'none', ...
    'Location', 'best');

subplot(2, 2, 3);
components = cfg.topology.componentNames;
dynamicClearance = zeros(numel(index), cfg.topology.diskCount);
for i = 1:cfg.topology.diskCount
    dynamicClearance(:, i) = ...
        trace{index, ['dynamicClearance_', components{i}]};
end
plot(t, dynamicClearance, 'LineWidth', 0.9); grid on;
xlabel('时间 / s'); ylabel('\epsilon-\epsilon_{ss}');
title('旋转部件动态间隙偏差');
legend(components, 'Location', 'best');

subplot(2, 2, 4);
yyaxis left;
semilogy(t, max(abs(trace.normalizedEnergyResidual(index)), eps), ...
    'LineWidth', 1.0);
ylabel('归一化能量残差');
yyaxis right;
derivativeNames = cellfun(@(name) ['d_', name], ...
    thermal.stateNames, 'UniformOutput', false);
maximumDerivative = max(abs(trace{index, derivativeNames}), [], 2);
plot(t, maximumDerivative, 'LineWidth', 1.0);
ylabel('max |dT/dt| / (K/s)');
grid on; xlabel('时间 / s'); title('能量守恒与热状态变化率');
sgtitle(['阶段七Visser二层：', caseDef.label]);
path = fullfile(outputDir, 'visser_thermal_clearance_overview.png');
print(f, path, '-dpng', '-r170');
clear cleanup;
end


function value = local_visibility(showFigures)
if showFigures
    value = 'on';
else
    value = 'off';
end
end

function local_close_if_hidden(handle, showFigures)
if ~showFigures && isgraphics(handle)
    close(handle);
end
end

function value = local_smooth_progress(value)
value = min(max(value, 0), 1);
value = value * value * (3 - 2 * value);
end

function value = local_finite_or_inf(value)
if ~isfinite(value)
    value = Inf;
end
end

function tf = local_lexicographic_less(left, right)
tf = false;
for i = 1:numel(left)
    if left(i) < right(i)
        tf = true;
        return;
    elseif left(i) > right(i)
        return;
    end
end
end

function value = local_pass(tf)
if tf
    value = 'PASS';
else
    value = 'FAIL';
end
end
