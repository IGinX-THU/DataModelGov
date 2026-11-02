function fig = sht_plot_control_results(result, plotCfg)
% 阅读说明：
%   本文件只负责绘制运行结果，不参与仿真和控制计算。
%   图中同时画 Np、Ng、燃油、输入指令和保护候选，便于运行 Start_sim 后快速检查闭环行为。
%SHT_PLOT_CONTROL_RESULTS Plot speed, fuel, and input commands after simulation.


if ~isfield(plotCfg, 'figureName') || isempty(plotCfg.figureName)
    plotCfg.figureName = 'SHT m-program closed-loop response';
end
if ~isfield(plotCfg, 'figureNumber') || isempty(plotCfg.figureNumber)
    fig = figure('Name', plotCfg.figureName, 'Color', 'w', ...
        'Position', [100 100 1050 760]);
else
    fig = figure(plotCfg.figureNumber);
    clf(fig);
    set(fig, 'Name', plotCfg.figureName, 'Color', 'w', ...
        'Position', [100 100 1050 760]);
end

t = result.time(:);
logData = result.log;

subplot(3, 1, 1);
yyaxis left;
plot(t, logData.Np, 'b-', 'LineWidth', 1.25);
hold on;
plot(t, logData.NpDem, 'k--', 'LineWidth', 1.1);
ylabel('Np / NpDem (rpm)');
yyaxis right;
plot(t, logData.Ng, 'Color', [0.85 0.2 0.1], 'LineWidth', 1.15);
ylabel('Ng (rpm)');
grid on;
title('Rotor speed response');
legend({'Np', 'NpDem', 'Ng'}, 'Location', 'best');

subplot(3, 1, 2);
plot(t, logData.Wf, 'b-', 'LineWidth', 1.25);
hold on;
if isfield(logData, 'WfcmdNow')
    wfCommandNow = logData.WfcmdNow;
else
    wfCommandNow = logData.Wfcmd;
end
plot(t, wfCommandNow, 'r--', 'LineWidth', 1.1);
legendItems = {'Wf', 'WfcmdNow'};
if isfield(logData, 'WfcmdNext') && ...
        any(abs(logData.WfcmdNext(:) - wfCommandNow(:)) > 1e-12)
    plot(t, logData.WfcmdNext, 'Color', [0.45 0.2 0.75], ...
        'LineStyle', ':', 'LineWidth', 1.1);
    legendItems{end + 1} = 'WfcmdNext';
end
grid on;
ylabel('Fuel flow (kg/s)');
title('Fuel metering system response');
legend(legendItems, 'Location', 'best');

subplot(3, 1, 3);
yyaxis left;
plot(t, logData.NpDem, 'k-', 'LineWidth', 1.15);
ylabel('NpDem (rpm)');
yyaxis right;
plot(t, logData.power, 'Color', [0.2 0.55 0.2], 'LineWidth', 1.15);
ylabel('Power command');
grid on;
xlabel('Time (s)');
title('Input commands');
legend({'NpDem', 'Power'}, 'Location', 'best');

drawnow;
end
