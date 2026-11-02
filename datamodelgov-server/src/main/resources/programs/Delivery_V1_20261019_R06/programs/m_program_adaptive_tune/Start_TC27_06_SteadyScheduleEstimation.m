function result=Start_TC27_06_SteadyScheduleEstimation(route,method,options)
%START_TC27_06_STEADYSCHEDULEESTIMATION 三部件2.7稳态系数独立四组合入口。
% route='steady'或'transient_instant'；method='I'或'II'。
% 默认M0/瞬态时刻/II。两路分别读取自己的TC24 Excel，不依赖另一条路径。
% B组内、D联合都保留Tikhonov和无阻尼TSVD选项，正则强度由用户指定。
% 四组合均默认：B与D0中心差分，D1前向差分，辨识积分0.1s；
% D总目标相对下降不足0.1%时停止，最终仍计算新Jacobian。
% 独立小幅测试使用0.025s，不因辨识提速降低验证积分精度。
% 两条路径的正则强度、方法I/II的曲线构造分别保留。显式覆盖示例：
%   options=struct('integrationStep_s',0.025,'tag','R006d_fine');
%   result=Start_TC27_06_SteadyScheduleEstimation('transient_instant','II',options);
% 只查看配置不运行辨识：sht_tc27_estimation_options('steady','I')。
if nargin<1||isempty(route),route='transient_instant';end
if nargin<2||isempty(method),method='II';end
if nargin<3,options=struct();end
% 独立06调用也先报估时；05已完成，不把前置准备重复计入06工作量。
o=sht_tc27_estimation_options(route,method,options);p=sht_tc27_paths(o);
a=load(fullfile(p.middle,'tc27_prepared_data.mat'),'result');
estimate=sht_tc27_runtime_estimate('steady_update',o, ...
    struct('route',route,'prepared',a.result,'stage','06_after_preparation', ...
    'resume',o.resume));
result=sht_tc27_steady_estimation(route,method,options);
result.estimatedTime=estimate;
end
