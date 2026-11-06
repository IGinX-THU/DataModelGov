function outputPath=sht_startstop_plot_thermal_case_comparison(caseResults,runRoot,cfg)
%SHT_STARTSTOP_PLOT_THERMAL_CASE_COMPARISON 已有历程的三/六部件热对比图。
% 独立绘图入口，不重新调用DLL；单位和温度列均显式给定。
visibility='off';if cfg.stage7.showFigures,visibility='on';end
f=figure('Visible',visibility,'Color','w','Name','Visser起停热耦合对比', ...
    'NumberTitle','off','Position',[80 80 1450 850]);
cleanup=onCleanup(@()local_close(f,cfg.stage7.showFigures));
fields={'Np','Ng','Tt45'};units={'Np / rpm','Ng / rpm','Tt45 / K'};
labels=arrayfun(@(c)c.definition.label,caseResults,'UniformOutput',false);
for j=1:3
    subplot(2,2,j);hold on;
    for i=1:numel(caseResults)
        t=caseResults(i).mission.trace;
        plot(t.time,t.(fields{j}),'LineWidth',0.9);
    end
    grid on;xlabel('时间 / s');ylabel(units{j});title(fields{j});
    legend(labels,'Location','best');
end
subplot(2,2,4);hold on;
for i=1:numel(caseResults)
    t=caseResults(i).mission.thermalTrace;
    names=caseResults(i).mission.thermalContext.stateNames;
    plot(t.time,max(t{:,names},[],2),'LineWidth',0.9);
end
grid on;xlabel('时间 / s');ylabel('最大节点温度 / K');
title(sprintf('%d状态热网络峰值温度',cfg.topology.temperatureCount+2));
legend(labels,'Location','best');sgtitle('Visser起停热耦合对比');
outputPath=fullfile(runRoot,'stage07_case_comparison.png');
print(f,outputPath,'-dpng','-r170');clear cleanup;
end

function local_close(f,show)
if ~show && isgraphics(f),close(f);end
end
