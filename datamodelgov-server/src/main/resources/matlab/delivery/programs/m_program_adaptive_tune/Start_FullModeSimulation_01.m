function status=Start_FullModeSimulation_01(user)
%START_FULLMODESIMULATION_01 准备并开始人工会话，不自动发起起动或运行。
% 示例：
%   Start_FullModeSimulation_01(struct('modelMode',0));
%   sht_fullmode_session('submit',struct('requestId','idle1', ...
%       'action','select_throttle','value','idle'));
%   sht_fullmode_session('advance',1);
%   sht_fullmode_session('submit',struct('requestId','start1','action','start'));
%   sht_fullmode_session('advance',400); % 仿真10秒，继续查看status。
% Ng稳定暖机60秒后会保持慢车，必须再明确选择run。无需GUI。
if nargin<1,user=struct();end
sht_fullmode_session('prepare',user);
status=sht_fullmode_session('begin');
fprintf('会话开始，mode=%s；选择慢车不自动起动。\n',status.mode);
end
