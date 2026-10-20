function view = Start_StartStopModeling_ResultView_01(location,showFigures)
%START_STARTSTOPMODELING_RESULTVIEW_01 独立查看已保存结果，绝不加载DLL或续算。
% location为任务目录或delivery模型包目录；结果保留原身份与未覆盖范围。
if nargin<2,showFigures=false;end
view=sht_startstop_modeling_package('view',location);
fprintf('\n起停建模：%s，拓扑=%d，状态=%s\n', ...
    view.taskId,view.modelMode,view.status);
disp(view.stages);
fprintf('实测自动标定/UQ：未实施。详细结果和文件来源见返回结构。\n');
if showFigures
    for k=1:numel(view.figures)
        figure('Name',view.figures{k},'NumberTitle','off');
        image(imread(view.figures{k}));axis image off;
    end
end
end
