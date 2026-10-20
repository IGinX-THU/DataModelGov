function path = sht_startstop_plot_continuous_trace(trace, caseDef, outputDir, cfg)
% 从已保存的历程重绘，不调用DLL；阶段标签来自实际热模型配置。
assert(istable(trace) && height(trace)>1, '绘图至少需要两个历程点。');
stageLabel = '阶段六连续起停';
if isfield(cfg,'stage7') && cfg.stage7.enabled
    stageLabel = '阶段七Visser连续起停';
end
visibility = local_visibility(cfg.stage6.showFigures);
pointCount = min(height(trace), cfg.stage6.maximumPlotPoints);
plotIndex = unique(round(linspace(1, height(trace), pointCount)));
plotTrace = trace(plotIndex, :);
timeLimit = [trace.time(1), trace.time(end)];
f = figure('Visible', visibility, 'Color', 'w', ...
    'Name', [stageLabel, '：', caseDef.label], ...
    'NumberTitle', 'off', 'Position', [60 60 1450 980]);
cleanup = onCleanup(@() local_close_if_hidden(f, cfg.stage6.showFigures));
subplot(4, 2, 1);
plot(plotTrace.time, plotTrace.Ng, plotTrace.time, plotTrace.Np, ...
    plotTrace.time, plotTrace.Nrotor, 'LineWidth', 1.0); grid on;
xlim(timeLimit);
xlabel('时间 / s'); ylabel('转速 / rpm');
legend('Ng','Np','旋翼等效转速','Location','best'); title('轴系转速');
subplot(4, 2, 2);
stairs(plotTrace.time, plotTrace.phase, 'LineWidth', 1.0); hold on;
stairs(plotTrace.time, plotTrace.segment, '--', 'LineWidth', 1.0); grid on;
xlim(timeLimit);
xlabel('时间 / s'); ylabel('状态码'); legend('C阶段','任务段');
title('统一状态机与任务调度');
subplot(4, 2, 3);
plot(plotTrace.time, plotTrace.commandedFuel, plotTrace.time, ...
    plotTrace.effectiveFuel, 'LineWidth', 1.0); hold on; grid on;
labels={'计量燃油','有效燃烧燃油'};
if ismember('fuelCommand',plotTrace.Properties.VariableNames)
    plot(plotTrace.time,plotTrace.fuelCommand,'--','LineWidth',0.8);
    labels{end+1}='执行机构命令';
end
xlim(timeLimit);
xlabel('时间 / s'); ylabel('燃油 / (kg/s)');
legend(labels,'Location','best'); title('燃油与燃烧建立');
subplot(4, 2, 4);
temperatureLine = plot(plotTrace.time, plotTrace.Tt45, ...
    'LineWidth', 1.0); hold on;
softLine = yline(cfg.stage6.temperatureSoftLimitK, '--');
grid on; xlabel('时间 / s'); ylabel('Tt45 / K');
xlim(timeLimit);
legend([temperatureLine, softLine], ...
    {'Tt45','控制限温值'}, 'Location','best');
title('热端温度与保护门限');
subplot(4, 2, 5);
yyaxis left;
plot(plotTrace.time, plotTrace.pitchDeg, 'LineWidth', 1.0);
ylabel('总距角 / deg');
yyaxis right;
plot(plotTrace.time, plotTrace.rotorLoadTorque, 'LineWidth', 1.0);
ylabel('负载转矩 / (N m)');
grid on; xlim(timeLimit); xlabel('时间 / s'); title('旋翼负载调度');
legend('总距角','旋翼负载转矩','Location','best');
subplot(4, 2, 6);
plot(plotTrace.time, plotTrace.hpsGasTorque, plotTrace.time, ...
    plotTrace.ptGasTorque, plotTrace.time, plotTrace.starterTorque, ...
    'LineWidth', 1.0); grid on; xlim(timeLimit);
xlabel('时间 / s'); ylabel('转矩 / (N m)');
legend('HPS气路','PT气路','起动机'); title('气路和起动机转矩');
subplot(4, 2, 7);
plot(plotTrace.time, plotTrace.freewheelTorque, plotTrace.time, ...
    plotTrace.requiredFreewheelTorque, 'LineWidth', 1.0); hold on;
stairs(plotTrace.time, 100 * plotTrace.freewheelEngaged, '--', ...
    'LineWidth', 1.0);
grid on; xlabel('时间 / s'); ylabel('转矩 / (N m)');
xlim(timeLimit);
legend('实际传递','维持同步所需','接合状态x100'); title('自由轮');
subplot(4, 2, 8);
semilogy(plotTrace.time, max(plotTrace.maximumResidual, eps), ...
    'LineWidth', 1.0);
grid on; xlabel('时间 / s'); ylabel('最大残差');
title(sprintf('%d维共同工作残差',cfg.topology.gasCount));
xlim(timeLimit);
sgtitle([stageLabel, '：', caseDef.label]);
path = fullfile(outputDir, 'continuous_mission_overview.png');
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
