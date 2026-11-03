function result=Start_FlightModelAdapt_14_SteadyTask(action,configuration,selection)
%START_FLIGHTMODELADAPT_14_STEADYTASK 稳态飞参任务的离线入口。
% 与界面调用sht_f3_steady_task完全相同，无弹窗、隐式样例或工作区依赖。
% 必须显式给出动作和配置。A: check/preview/confirm/read；
% 父尚未生成时：previewData/confirmData只确认完整测量窗口及明确父关系。
% bindParent显式给intentFile、父Excel及全新outputRoot/reportRoot，
% 核验后沿用原确认窗口生成执行凭据；不猜未来SHA或待估参数个数。
% 新flight父继承健康曲线，本架次燃油/装机损失仍按原零参考重估。
% B: estimate/run以confirmationFile、runId、outputRoot、reportRoot运行。
% status/readResult仅传resultDirectory，可在搬迁后无DLL查看完整结果。
% B沿A确认的R1/R2、纯稳态/混合数据及参数化运行；各路线验证范围见报告。
% requestPause只传resultDirectory，
% 不强杀DLL；status的safePaused才表示完整安全点已经保存。
% resume传与原run相同配置，保持runId及两个目录、输入与数值身份不变。
% 若结果已发布则readResult；旧源码确认或检查点不能改签后续用。
% C/D任务另见Start_FlightModelAdapt_15_UncertaintyTask，共用同一核心。
assert(nargin>=2,'SHT:F3Task:Required','必须显式给出action和configuration。');
if nargin<3,selection=struct();end
result=sht_f3_steady_task(action,configuration,selection);
end
