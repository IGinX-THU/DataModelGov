function result = RunModelSHT_V1_2DP_Auto(user)
%RUNMODELSHT_V1_2DP_AUTO 三部件可配置设计入口，原V1不变。
% 默认仅在新任务副本中求解及复现，不改源MDL。
% c=sht_design_point_config(0); c.sourceDirectory='所选模型目录';
% r=RunModelSHT_V1_2DP_Auto(c);
% 审核r.parameterComparison后显式提交：
% r=sht_design_point_task('commit',r.taskDirectory);
if nargin<1,user=struct();end
if isfield(user,'schema'),cfg=user;assert(cfg.modelMode==0,'sht:dp:mode','V1要求三部件。');
else,cfg=sht_design_point_config(0,user);end
result=sht_design_point_task('solve',cfg);
end
