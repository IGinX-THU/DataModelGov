function task = Start_StartStopModeling_01(user)
%START_STARTSTOPMODELING_01 起停建模独立离线入口，与界面共用任务核心。
% 先调用sht_startstop_modeling_config配置source与taskDirectory。
% requestedStages默认空：只准备，不暗中执行矩阵或完整起停任务。
% 示例：user.requestedStages={'maps'}; task=Start_StartStopModeling_01(user);
if nargin<1, user=struct(); end
cfg=sht_startstop_modeling_config(user);
task=sht_startstop_modeling_task('prepare',cfg);
fprintf('建模任务：%s\n私有目录：%s\n',task.taskId,task.taskDirectory);
if strcmp(task.status,'blocked')
    fprintf('准备未就绪：%s\n',strjoin(task.preflight.issues,newline));
    return;
end
for k=1:numel(cfg.requestedStages)
    task=sht_startstop_modeling_task('runStage',task.taskDirectory,cfg.requestedStages{k});
    if any(strcmp(task.status,{'paused','failed','blocked'})), break; end
end
end
