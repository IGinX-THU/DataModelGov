function outputPath = sht_startstop_plot_control_detail(t,cfg,outputDir)
%SHT_STARTSTOP_PLOT_CONTROL_DETAIL 只读已计算历程，展示控制作用及跟踪误差。
show=cfg.stage6.showFigures;visibility='off';if show,visibility='on';end
f=figure('Visible',visibility,'Color','w','Position',[80 60 1400 1000], ...
    'Name','起停统一控制：跟踪、执行机构与保护','NumberTitle','off');
cleanup=onCleanup(@()local_close(f,show));
ix=unique(round(linspace(1,height(t),min(height(t),cfg.stage6.maximumPlotPoints))));
p=t(ix,:);normal=p.segment>=2 & p.segment<=6 & p.controlModeId~=10;
target=p.NpTargetRatio*cfg.startStop.designNpRpm;
target(~normal)=NaN; % Ng暖机不是Np调速，不能计算虚假的Np跟踪误差。
subplot(3,2,1);plot(p.time,p.Np,p.time,target,'--');grid on;
xlabel('时间 / s');ylabel('Np / rpm');legend('实际','指令');title('动力轴转速跟踪');
subplot(3,2,2);plot(p.time(normal),100*(p.Np(normal)-target(normal))/cfg.startStop.designNpRpm);
grid on;xlabel('时间 / s');ylabel('误差 / 设计转速%');title('慢车以上跟踪误差');
subplot(3,2,3);plot(p.time,p.fuelCommand,'--',p.time,p.commandedFuel,p.time,p.effectiveFuel);
grid on;xlabel('时间 / s');ylabel('kg/s');legend('命令','计量','有效燃烧');title('燃油执行链');
subplot(3,2,4);stairs(p.time,p.controlModeId);grid on;
xlabel('时间 / s');ylabel('控制模式编号');
title({'0断油；10起动供油；11 Ng升速/暖机','1 Np主调速；5/6/7限速/限温/限矩'});
subplot(3,2,5);plot(p.time,p.freewheelTorque);hold on;
yline(cfg.aboveIdle.controller.mkpProtection.mkpMax,'--');grid on;
xlabel('时间 / s');ylabel('Mkp / N m');title('输出轴传递扭矩与限制');
subplot(3,2,6);plot(p.time,p.Ng);hold on;
if ismember('startupNgReferenceRpm',p.Properties.VariableNames)
    ngRef=p.startupNgReferenceRpm;ngRef(p.controlModeId~=11)=NaN;
    plot(p.time,ngRef,'--');
end
yline(cfg.aboveIdle.controller.ngProtection.ngMax,'--');grid on;
xlabel('时间 / s');ylabel('Ng / rpm');title('燃气发生器转速与限制');
outputPath=fullfile(outputDir,'continuous_control_detail.png');
print(f,outputPath,'-dpng','-r150');
end
function local_close(f,show)
if ~show && isgraphics(f),close(f);end
end
