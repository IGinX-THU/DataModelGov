function result = Start_sim(userCfg)
%START_SIM 涡轴发动机闭环控制 m 程序正式起始入口。
% 默认运行时不需要输入参数；需要临时修改仿真时间、指令或控制器参数时，通过 userCfg 覆盖默认 cfg。

thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir);

if nargin < 1 || isempty(userCfg)
    cfg = sht_default_config();
else
    cfg = sht_default_config(userCfg);
end
sht_write_baseline_to_workspace(cfg);

result = sht_simulate_control_m(cfg);
result.configManifest = struct( ...
    'configSource', 'sht_default_config.m', ...
    'modelMode', cfg.engine.modelMode, ...
    'designPointSource', cfg.engine.modelConfiguration, ...
    'runtimeInput', 'cfg', ...
    'designPoint', cfg.engine.initial, ...
    'createdAt', datestr(now, 31));

if isfield(result.cfg, 'plot') && isfield(result.cfg.plot, 'enable') && result.cfg.plot.enable
    result.figure = sht_plot_control_results(result, result.cfg.plot);
end
end
