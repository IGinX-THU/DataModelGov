function result=Start_FlightModelAdapt_11_TransientCoefficientEstimation(action,configuration,selection)
% 界面和独立MATLAB共用：check/preview/confirm/estimate/run/status/requestPause/resume/read。
% 所有业务文件及编号由用户明确指定，config返回集中配置模板，不启动DLL。
% lambda=0.05直接乘二次先验。旧样例请显式使用内部核心，不隐式运行R035。
if nargin<1,action='config';end
if nargin<2,configuration=struct();end
if nargin<3,selection=struct();end
result=sht_f3_transient_task(action,configuration,selection);
end
