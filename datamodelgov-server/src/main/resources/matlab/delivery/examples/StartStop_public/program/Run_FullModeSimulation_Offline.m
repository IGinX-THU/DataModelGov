function result=Run_FullModeSimulation_Offline(user,plan)
%RUN_FULLMODESIMULATION_OFFLINE 与人工/界面入口相同的核心，执行明确命令表。
% plan.commands每项：requestId/action/value/atTimeS/whenMode。whenMode为空
% 表示只按时间；例如进入idle后再发run，不用预先假定起动何时完成。
% durationS是数值运行窗口，不表示发动机已停车；结果分别给出二者。
if nargin<1,user=struct();end
if nargin<2
    plan=struct('durationS',350,'commands',{{ ...
        struct('requestId','idle','action','select_throttle','value','idle','atTimeS',0), ...
        struct('requestId','start','action','start','atTimeS',0.025), ...
        struct('requestId','run','action','select_throttle','value','run','atTimeS',0,'whenMode','idle'), ...
        struct('requestId','stop','action','normal_stop','atTimeS',250)}});
end
validateattributes(plan.durationS,{'numeric'},{'scalar','finite','positive'});
commands=plan.commands;assert(iscell(commands),'命令表使用cell，容纳不同命令字段。');
% 全表先检查，避免晚到的非法模式在发动机已经运行后才报错。
% 只规范化局部命令副本，result.offlinePlan仍保留调用者的原始输入。
commands=local_mode_conditions(commands);
Start_FullModeSimulation_01(user);sent=false(size(commands));
guard=onCleanup(@()sht_fullmode_session('close'));
while true
    status=sht_fullmode_session('status');
    if status.timeS>=plan.durationS-1e-10 || ~strcmp(status.lifecycle,'running'),break;end
    for k=1:numel(commands)
        if sent(k),continue;end
        q=commands{k};ready=status.timeS>=q.atTimeS-1e-10;
        if isfield(q,'whenMode'),ready=ready && strcmp(status.mode,q.whenMode);q=rmfield(q,'whenMode');end
        if ready
            q=rmfield(q,'atTimeS');receipt=sht_fullmode_session('submit',q);sent(k)=true;
            assert(~strcmp(receipt.state,'rejected'),'命令被拒绝：%s，%s。',q.requestId,receipt.reason);
        end
    end
    sht_fullmode_session('advance',1);
end
result=sht_fullmode_session('result');
result.offlinePlan=plan;result.commandsSent=sent;
if isfield(user,'fullmode') && isfield(user.fullmode,'saveDirectory')
    result.saved=sht_fullmode_session('save',user.fullmode.saveDirectory);
end
fprintf('离线窗口结束：t=%g s，physicalStop=%d，数值状态=%s，耗时=%.3g s。\n', ...
    result.terminalStatus.timeS,result.terminalStatus.physicalStop, ...
    result.terminalStatus.lifecycle,result.terminalStatus.wallSeconds);
end

function commands=local_mode_conditions(commands)
% 这里匹配发动机运行模式，不匹配paused等会话状态或cruise等初态名称。
modes={'stopped','cranking','warmup','idle_handover','idle','run', ...
    'coldblow','cooldown','shutdown'};
for k=1:numel(commands)
    q=commands{k};
    if ~isstruct(q) || ~isscalar(q)
        error('sht:fullmode:invalidCommand', ...
            '第%d条离线命令必须为标量结构体。',k);
    end
    if ~isfield(q,'whenMode'),continue;end
    value=q.whenMode;
    if isstring(value)
        valid=isscalar(value) && ~ismissing(value);
        if valid,value=char(value);end
    else
        valid=ischar(value) && (isrow(value) || isequal(size(value),[0,0]));
    end
    if ~valid
        error('sht:fullmode:invalidWhenMode', ...
            '第%d条命令whenMode必须为字符行向量或非missing标量string，实际类型%s，大小%s。', ...
            k,class(q.whenMode),mat2str(size(q.whenMode)));
    end
    if isempty(value)
        q=rmfield(q,'whenMode');
    elseif any(strcmp(value,modes))
        q.whenMode=value;
    else
        error('sht:fullmode:unknownWhenMode', ...
            '第%d条命令whenMode="%s"未知。允许值：%s；空文本表示仅按时间触发。', ...
            k,value,strjoin(modes,', '));
    end
    commands{k}=q;
end
end
