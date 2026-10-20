function result = sht_startstop_verify_physics_kernel(alias, cfg, outputDir)
%SHT_STARTSTOP_VERIFY_PHYSICS_KERNEL 独立验收起动机、燃烧和两惯量逻辑。
%
% 本测试故意不调用气路模型，而向状态机提供可解释的合成净气动力矩。
% 因此一旦失败，可直接归因于SS4物理/状态机，而不是低速特性图或Newton。

if ~isfolder(outputDir)
    mkdir(outputDir);
end
p = cfg.startStop;
dt = p.timeStepS;
time = (0:dt:120).';
count = numel(time);

names = {'Ng','Np','Nrotor','NgDot','NpDot','NrotorDot','phase', ...
    'starterTorque','effectiveFuel','flameFraction','hpsLoss','ptLoss', ...
    'rotorLoad','freewheelTorque','freewheelEngaged','event', ...
    'requiredFreewheelTorque','hpsGasTorque','ptGasTorque','valid'};
data = zeros(count, numel(names));

status = calllib(alias, 'DLL_SHT_StartStopReset', 0, 0, 0, 1);
assert(status == 0, '起停状态复位失败，状态码=%d。', status);

ng = 0;
np = 0;
nRotor = 0;
previous = zeros(24, 1);
for k = 1:count
    t = time(k);
    if t < 1
        command = 0;
        fuel = 0;
        ignition = 0;
    elseif t < 30
        command = 1;
        fuel = p.idleFuelKgPerS;
        ignition = 1;
    elseif t < 40
        command = 2;
        fuel = 1.10 * p.idleFuelKgPerS;
        ignition = 1;
    else
        command = 3;
        fuel = 0;
        ignition = 0;
    end

    if command == 1 || command == 2
        availability = min(max(previous(6) / max(fuel, eps), 0), 1);
        if command == 1
            ngTarget = p.idleNgRatio * p.designNgRpm;
            npTarget = 0.78 * p.designNpRpm;
        else
            ngTarget = 0.72 * p.designNgRpm;
            npTarget = 0.90 * p.designNpRpm;
        end
        hpsDemand = previous(8) + 0.0030 * (ngTarget - ng);
        ptDemand = previous(9) + previous(10) + 0.012 * (npTarget - np);
        hpsGasTorque = availability * min(max(hpsDemand, 0), 85);
        ptGasTorque = availability * min(max(ptDemand, 0), 450);
    elseif command == 3
        % 燃油切断后，压气机泵气和涡轮风阻使两根发动机轴净气动力矩为负。
        hpsGasTorque = -20 * min(max(ng / (0.2 * p.designNgRpm), 0), 1);
        ptGasTorque = -80 * min(max(np / (0.2 * p.designNpRpm), 0), 1);
    else
        hpsGasTorque = 0;
        ptGasTorque = 0;
    end

    input = [dt; command; ng; np; nRotor; hpsGasTorque; ptGasTorque; ...
        fuel; 6; ignition; 900; p.gtAccessoryPowerW];
    inputPointer = libpointer('doublePtr', input);
    outputPointer = libpointer('doublePtr', zeros(24, 1));
    status = calllib(alias, 'DLL_SHT_StartStopPhysicsStep', ...
        inputPointer, numel(input), outputPointer, 24);
    assert(status == 0, '物理内核第%d步失败，状态码=%d。', k, status);
    output = outputPointer.Value;

    data(k, :) = [ng, np, nRotor, output(1), output(2), output(3), ...
        output(4), output(5), output(6), output(7), output(8), output(9), ...
        output(10), output(11), output(12), output(13), output(17), ...
        hpsGasTorque, ptGasTorque, output(24)];
    ng = max(0, ng + dt * output(1));
    np = max(0, np + dt * output(2));
    nRotor = max(0, nRotor + dt * output(3));
    previous = output;
end

column = cell2struct(num2cell(1:numel(names)), names, 2);
event = data(:, column.event);
phase = data(:, column.phase);
freewheel = data(:, column.freewheelEngaged);
% 只在冷转和点火延迟阶段检查起动机轴系作用。停车阶段同样无火焰，
% 但显然不属于冷转，不能混入该判据。
coldCrank = phase == 1 | phase == 2;
freewheelTransitions = find(diff(freewheel) < -0.5) + 1;
reengagementTransitions = find(diff(freewheel) > 0.5) + 1;
requiredEvents = [1, 2, 3, 4, 5, 6, 7, 8];
firstEventIndex = nan(size(requiredEvents));
for i = 1:numel(requiredEvents)
    hit = find(event == requiredEvents(i), 1, 'first');
    if ~isempty(hit)
        firstEventIndex(i) = hit;
    end
end

checks = struct();
checks.finite = all(isfinite(data(:)));
checks.allStepsValid = all(data(:, column.valid) > 0.5);
checks.starterActsOnNg = max(data(coldCrank, column.NgDot)) > 0;
checks.starterDoesNotDriveNp = ...
    max(abs(data(coldCrank, column.NpDot))) < 1e-10;
checks.fuelZeroBeforeLightOff = ...
    max(abs(data(phase < 3, column.effectiveFuel))) < 1e-12;
checks.eventOrder = all(isfinite(firstEventIndex)) && ...
    all(diff(firstEventIndex) > 0);
checks.singleFreewheelDisengagement = numel(freewheelTransitions) == 1;
checks.noFreewheelReengagement = isempty(reengagementTransitions);
checks.noNegativeTransmittedTorque = ...
    min(data(freewheel > 0.5, column.freewheelTorque)) >= -1e-9;
checks.rotorCannotBackDriveAfterDisengagement = isempty(freewheelTransitions) || ...
    max(abs(data(freewheelTransitions(1):end, column.freewheelTorque))) < 1e-9;
checks.shutdownFuelZero = ...
    max(abs(data(time >= 40, column.effectiveFuel))) < 1e-12;
checks.npContinuousAtDisengagement = isempty(freewheelTransitions) || ...
    abs(diff(data(freewheelTransitions(1)-1:freewheelTransitions(1), ...
        column.Np))) < 500;
checks.reachesIdle = any(phase == 7);
checks.reachesShutdown = any(phase == 9);
checks.accepted = all(cell2mat(struct2cell(checks)));

trace = array2table([time, data], 'VariableNames', [{'time'}, names]);
csvPath = fullfile(outputDir, 'stage04_physics_trace.csv');
writetable(trace, csvPath);
figurePath = local_plot_trace(time, data, column, outputDir);
summaryPath = fullfile(outputDir, 'stage04_physics_summary.md');
local_write_summary(summaryPath, checks, requiredEvents, firstEventIndex, ...
    time, freewheelTransitions, data, column);

result = struct('time', time, 'data', data, 'names', {names}, ...
    'checks', checks, 'firstEventIndex', firstEventIndex, ...
    'freewheelTransitions', freewheelTransitions, 'csvPath', csvPath, ...
    'figurePath', figurePath, 'summaryPath', summaryPath, ...
    'accepted', checks.accepted);
save(fullfile(outputDir, 'stage04_physics_result.mat'), 'result', '-v7');
end

function path = local_plot_trace(time, data, c, outputDir)
f = figure('Visible', 'off', 'Color', 'w', 'Position', [80 80 1280 900]);
cleanup = onCleanup(@() close(f));
subplot(3, 2, 1);
plot(time, data(:, c.Ng), time, data(:, c.Np), ...
    time, data(:, c.Nrotor), 'LineWidth', 1.0); grid on;
xlabel('时间 / s'); ylabel('转速 / rpm');
legend('Ng','Np','旋翼等效转速','Location','best'); title('两轴与旋翼');
subplot(3, 2, 2);
stairs(time, data(:, c.phase), 'LineWidth', 1.1); hold on;
stairs(time, data(:, c.freewheelEngaged), '--', 'LineWidth', 1.1); grid on;
xlabel('时间 / s'); ylabel('离散状态'); legend('阶段','自由轮接合');
title('起停状态机');
subplot(3, 2, 3);
plot(time, data(:, c.starterTorque), time, data(:, c.hpsGasTorque), ...
    time, data(:, c.hpsLoss), 'LineWidth', 1.0); grid on;
xlabel('时间 / s'); ylabel('转矩 / N m');
legend('起动机','HPS气路净转矩','HPS损失'); title('高压轴转矩');
subplot(3, 2, 4);
plot(time, data(:, c.ptGasTorque), time, data(:, c.rotorLoad), ...
    time, data(:, c.freewheelTorque), 'LineWidth', 1.0); grid on;
xlabel('时间 / s'); ylabel('转矩 / N m');
legend('PT气动力矩','旋翼负载','自由轮传递'); title('动力涡轮/旋翼转矩');
subplot(3, 2, 5);
plot(time, data(:, c.effectiveFuel), time, data(:, c.flameFraction), ...
    'LineWidth', 1.0); grid on;
xlabel('时间 / s'); ylabel('燃油或比例');
legend('有效燃烧燃油 kg/s','火焰建立比例'); title('点火与燃烧建立');
subplot(3, 2, 6);
stem(time, data(:, c.event), '.', 'MarkerSize', 4); grid on;
xlabel('时间 / s'); ylabel('事件码'); title('可追溯事件序列');
path = fullfile(outputDir, 'stage04_start_stop_physics.png');
print(f, path, '-dpng', '-r170');
clear cleanup;
end

function local_write_summary(path, checks, requiredEvents, eventIndex, ...
    time, freewheelTransitions, data, c)
fid = fopen(path, 'w');
assert(fid >= 0, '无法写入物理验收摘要：%s。', path);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# 阶段四起动停车物理内核验收\n\n');
fprintf(fid, '- 总体结果：**%s**\n', local_pass(checks.accepted));
fprintf(fid, '- 合成力矩只用于隔离验证状态机，不作为低速气路标定结果。\n\n');
fprintf(fid, '## 事件时刻\n\n');
fprintf(fid, '|事件码|首次时刻/s|\n|---:|---:|\n');
for i = 1:numel(requiredEvents)
    if isfinite(eventIndex(i))
        eventTime = time(eventIndex(i));
    else
        eventTime = NaN;
    end
    fprintf(fid, '|%d|%.6g|\n', requiredEvents(i), eventTime);
end
fprintf(fid, '\n## 判据\n\n');
fields = fieldnames(checks);
for i = 1:numel(fields)
    if ~strcmp(fields{i}, 'accepted')
        fprintf(fid, '- `%s`：%s\n', fields{i}, local_pass(checks.(fields{i})));
    end
end
if ~isempty(freewheelTransitions)
    k = freewheelTransitions(1);
    fprintf(fid, '\n自由轮首次脱开：t=%.6g s，脱开前所需传递转矩=%.6g N m，Np=%.6g rpm。\n', ...
        time(k), data(k, c.requiredFreewheelTorque), data(k, c.Np));
end
end

function value = local_pass(tf)
if tf
    value = 'PASS';
else
    value = 'FAIL';
end
end
