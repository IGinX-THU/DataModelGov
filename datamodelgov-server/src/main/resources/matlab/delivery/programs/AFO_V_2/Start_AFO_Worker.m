function result=Start_AFO_Worker(cfg,observer,serviceSeconds)
%START_AFO_WORKER 界面工作进程入口，与独立运行共用session核心。
% 计算结束后仍保留原进程结果，响应sht_afo_submit投递的save/release/discard。
% release要求保存成功；discard表示用户明确放弃未保存结果。工作进程
% 不自动超时退出，也不把文件重载声称为Simulink动态状态恢复。
if nargin<1,cfg=sht_afo_config;end
if nargin<2,observer=[];end
% 有限等待仅供托管进程/短测：到时返回原调用者，仍保留session结果，
% 不释放实例。调用者必须继续service或显式保存/放弃；默认一直服务。
if nargin<3,serviceSeconds=Inf;end
validateattributes(serviceSeconds,{'double'},{'scalar','real','positive'});
sht_afo_session('prepare',cfg);
try
    sht_afo_session('run',observer);
catch err
    s=sht_afo_session('status');
    if ~ismember(s.state,{'ended','failed'}),rethrow(err);end
    fprintf(2,'计算/导出未正常完成，原进程继续保留结果供检查和重试：%s\n',err.message);
end
serviceClock=tic;
while toc(serviceClock)<serviceSeconds
    s=sht_afo_session('service');
    if strcmp(s.state,'closed'),break;end
    pause(.05);drawnow;
end
result=sht_afo_session('result');
end
