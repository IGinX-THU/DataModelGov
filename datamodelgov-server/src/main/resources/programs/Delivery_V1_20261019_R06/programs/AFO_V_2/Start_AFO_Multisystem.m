function result=Start_AFO_Multisystem(cfg,observer)
%START_AFO_MULTISYSTEM 独立离线入口；界面可调用相同session核心。
% cfg=sht_afo_config; cfg.pace='fast'; cfg.duration=30;
% result=Start_AFO_Multisystem(cfg);
% observer为可选函数句柄，处理进度/人工命令；不要求GUI或网络。
if nargin<1,cfg=sht_afo_config;end
if nargin<2,observer=[];end
sht_afo_session('prepare',cfg);
result=sht_afo_session('run',observer);
if cfg.plots,sht_afo_results('plot',fullfile(cfg.outputDir,'AFO_results.xlsx'));end
end
