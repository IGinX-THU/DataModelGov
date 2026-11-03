function response=sht_afo_submit(folder,command)
%SHT_AFO_SUBMIT 从另一MATLAB进程/界面投递指令，不需要GUI或网络。
% queued只说明文件完整落盘；status或receipt中的applied才是生效证据。
assert(isstruct(command)&&all(isfield(command,{'id','kind','value'})), ...
    '命令须含id、kind、value。');
assert(ischar(command.id)&&~isempty(regexp(command.id,'^[A-Za-z0-9_-]{1,80}$','once')), ...
    '命令id须为1至80位英文、数字、下划线或连字符。');
inbox=fullfile(folder,'inbox');assert(exist(inbox,'dir')==7,'会话尚未准备。');
state=sht_afo_read_json(fullfile(folder,'status.json'));
assert(strcmp(state.schema,'SHT_AFO_STATUS_V2'),'须使用R065会话。');
assert(~strcmp(state.state,'closed'),'会话已经释放。');
if isfield(command,'sessionId'),assert(strcmp(command.sessionId,state.sessionId),'会话身份不匹配。');end
if isfield(command,'runId'),assert(strcmp(command.runId,state.runId),'运行身份不匹配。');end
command.sessionId=state.sessionId;command.runId=state.runId;
file=fullfile(inbox,[command.id '.json']);
processed=fullfile(folder,'processed_commands',[command.id '.json']);
if exist(file,'file')==2||exist(processed,'file')==2
    old=file;if exist(processed,'file')==2,old=processed;end
    q=sht_afo_read_json(old);
    assert(strcmp(q.kind,command.kind)&&isequaln(q.value(:),command.value(:)), ...
        '相同命令id不能改变内容。');
    response=struct('status','already_submitted','id',command.id);return
end
sht_afo_json(file,command);response=struct('status','queued','id',command.id, ...
    'sessionId',state.sessionId);
end
