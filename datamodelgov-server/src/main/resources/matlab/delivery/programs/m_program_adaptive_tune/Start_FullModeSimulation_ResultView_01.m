function result=Start_FullModeSimulation_ResultView_01(file,plotEnabled)
%START_FULLMODESIMULATION_RESULTVIEW_01 独立历史查看；绝不加载DLL或准备模型。
% file为保存的fullmode_snapshot.mat，显示记录完整性与命令及停止原因。
if nargin<2,plotEnabled=true;end
d=load(file,'result');assert(isfield(d,'result'),'文件不含全模式结果。');result=d.result;
disp(result.terminalStatus);
% 与Excel导出一致：只有一条命令时也按一个结构记录显示为一行。
if ~isempty(result.commands),disp(struct2table(result.commands,'AsArray',true));end
if plotEnabled && ~isempty(result.trace)
    t=result.trace;
    figure('Name','全模式连续仿真','NumberTitle','off');
    subplot(3,1,1);plot(t.timeS,[t.NpRpm,t.NgRpm,t.NrotorPTEquivalentRpm]);
    ylabel('转速 / rpm');legend('Np','Ng','PT侧折算旋翼转速');grid on;
    subplot(3,1,2);plot(t.timeS,[t.Tt45TrueK,t.Tt45MeasuredK]);
    ylabel('Tt45 / K');legend('真值','测量');grid on;
    subplot(3,1,3);plot(t.timeS,[t.actuatorFuelKgPerS,t.effectiveFuelKgPerS]);
    ylabel('燃油 / kg/s');xlabel('时间 / s');legend('计量燃油','有效燃油');grid on;
end
end
