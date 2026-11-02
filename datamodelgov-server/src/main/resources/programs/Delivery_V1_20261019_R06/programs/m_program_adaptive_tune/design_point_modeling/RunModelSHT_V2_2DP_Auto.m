function result = RunModelSHT_V2_2DP_Auto(user)
%RUNMODELSHT_V2_2DP_AUTO 六部件独立设计入口，不读V1模型或结果。
% 默认求解/私有复现；写入必须另显式调用commit，并先生成时间备份。
% 两种使用方式与V1_Auto相同，设计目标集中在sht_design_point_config。
if nargin<1,user=struct();end
if isfield(user,'schema'),cfg=user;assert(cfg.modelMode==1,'sht:dp:mode','V2要求六部件。');
else,cfg=sht_design_point_config(1,user);end
result=sht_design_point_task('solve',cfg);
end
