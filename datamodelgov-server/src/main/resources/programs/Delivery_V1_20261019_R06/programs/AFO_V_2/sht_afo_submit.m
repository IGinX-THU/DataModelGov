function response=sht_afo_submit(folder,command)
%SHT_AFO_SUBMIT 从另一MATLAB进程/界面投递指令，不需要GUI或网络。
% queued只说明文件完整落盘；status或receipt中的applied才是生效证据。
assert(isstruct(command)&&all(isfield(command,{'id','kind','value'})), ...
    '命令须含id、kind、value。');
assert(ischar(command.id)&&~isempty(regexp(command.id,'^[A-Za-z0-9_-]{1,80}$','once')), ...
    '命令id须为1至80位英文、数字、下划线或连字符。');
inbox=fullfile(folder,'inbox');assert(exist(inbox,'dir')==7,'会话尚未准备。');
file=fullfile(inbox,[command.id '.json']);
processed=fullfile(folder,'processed_commands',[command.id '.json']);
if exist(file,'file')==2||exist(processed,'file')==2
    old=file;if exist(processed,'file')==2,old=processed;end
    q=jsondecode(fileread(old));
    assert(strcmp(q.kind,command.kind)&&isequaln(q.value(:),command.value(:)), ...
        '相同命令id不能改变内容。');
    response=struct('status','already_submitted','id',command.id);return
end
tmp=[file '.tmp'];f=fopen(tmp,'w','n','UTF-8');assert(f>=0,'无法创建命令。');
g=onCleanup(@()fclose(f));fprintf(f,'%s',jsonencode(command));clear g;
movefile(tmp,file);response=struct('status','queued','id',command.id);
end
