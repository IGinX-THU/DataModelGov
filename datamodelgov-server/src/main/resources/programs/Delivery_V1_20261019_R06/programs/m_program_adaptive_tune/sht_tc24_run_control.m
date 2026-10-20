function varargout=sht_tc24_run_control(action,varargin)
% 共用的离线/UI协作停止协议；directory已经是完整任务目录，不再拼runId。
% 只保存调用方明确提交的完整安全单元，不强杀DLL，不保存函数句柄。
% identity必须包含调用方数据、物理包、源码、算法/提议/预算/随机设置。
action=lower(char(action));
switch action
    case 'hash'
        varargout{1}=digest(varargin{1});return;
    case 'open'
        options=varargin{1};identity=varargin{2};
        assert(isstruct(identity)&&isscalar(identity)&&~isempty(fieldnames(identity)), ...
            'TC24:Control:Identity','必须提供非空完整执行身份。');
        directory=sht_tc24_absolute_path(options.directory);
        assert(~isempty(directory),'TC24:Control:Directory','缺少完整任务目录。');
        runId=char(options.runId);assert(~isempty(runId),'缺少运行标识。');
        control=struct('schemaVersion','SHT_RUN_CONTROL_V1','directory',directory, ...
            'runId',runId,'identityHash',digest(identity),'resume',option(options,'resume',false));
        control.controlDirectory=fullfile(directory,'run_control');
        control.timer=option(options,'timer',tic);
        control.sessionStartDatenum=option(options,'sessionStartDatenum',now);
        control.sessionStartedAt=datestr(control.sessionStartDatenum,30);
        control.sessionToken=option(options,'sessionToken',strrep(char(java.util.UUID.randomUUID()),'-',''));
        control.priorActiveSeconds=0;control.priorPausedSeconds=0;
        if ~exist(control.controlDirectory,'dir'),mkdir(control.controlDirectory);end
        lock=java.io.File(fullfile(control.controlDirectory,'session.lock'));
        assert(lock.createNewFile(),'TC24:Control:ActiveRun', ...
            '该运行仍持有写入锁；不能并发恢复。异常退出的锁须核查原进程后人工处理。');
        try
        identityFile=fullfile(control.controlDirectory,'identity.mat');
        if isfile(identityFile)
            assert(control.resume,'TC24:Control:Exists','运行已存在；续跑须显式resume=true。');
            old=load(identityFile,'record');
            assert(strcmp(old.record.schemaVersion,control.schemaVersion)&& ...
                strcmp(old.record.runId,runId)&&strcmp(old.record.identityHash,control.identityHash), ...
                'TC24:Control:IdentityMismatch','运行内容身份变化，不能续用检查点。');
            previous=readState(control);
            assert(ismember(previous.status,{'stopped','failed','partial'})&&previous.checkpointAvailable, ...
                'TC24:Control:NotResumable','仅能恢复已确认安全停止/失败且有检查点的运行。');
            control.priorActiveSeconds=previous.activeSeconds;
            control.priorPausedSeconds=previous.pausedSeconds;
            if ismember(previous.status,{'stopped','partial'})
                control.priorPausedSeconds=control.priorPausedSeconds+ ...
                    max(0,(control.sessionStartDatenum-previous.updatedDatenum)*86400);
            end
            request=fullfile(control.controlDirectory,'stop_request.mat');
            if isfile(request),delete(request);end % 仅消费已验证同一运行的旧停止请求。
        else
            assert(~control.resume,'TC24:Control:Missing','未找到本批新协议，不能恢复旧检查点。');
            if ~exist(control.controlDirectory,'dir'),mkdir(control.controlDirectory);end
            record=struct('schemaVersion',control.schemaVersion,'runId',runId, ...
                'identityHash',control.identityHash,'identity',identity,'createdAt',datestr(now,30));
            atomic(identityFile,'record',record);
        end
        if control.resume
            writeState(control,'running',previous.safePoint,previous.checkpointFile,previous.checkpointAvailable);
        else
            writeState(control,'running','initialization','',false);
        end
        varargout{1}=control;
        catch err
            releaseLock(control);rethrow(err);
        end
    case 'requeststop'
        control=resolveControl(varargin{1});
        previous=readState(control);
        if ~strcmp(previous.status,'running')
            varargout{1}=struct('status',previous.status,'safeStopConfirmed',strcmp(previous.status,'stopped'), ...
                'message','任务当前未运行，不新增停止请求。');return;
        end
        record=struct('schemaVersion',control.schemaVersion,'runId',control.runId, ...
            'identityHash',control.identityHash,'requestedAt',datestr(now,30));
        atomic(fullfile(control.controlDirectory,'stop_request.mat'),'record',record);
        varargout{1}=struct('status','stop_requested','safeStopConfirmed',false, ...
            'message','请求已保存；当前DLL或未完成安全单元结束后响应。');
    case 'poll'
        control=varargin{1};requested=false;
        file=fullfile(control.controlDirectory,'stop_request.mat');
        if isfile(file)
            saved=load(file,'record');verify(saved.record,control);requested=true;
        end
        varargout{1}=requested;
    case {'save','boundary'}
        control=varargin{1};key=validKey(varargin{2});state=varargin{3};
        record=struct('schemaVersion',control.schemaVersion,'runId',control.runId, ...
            'identityHash',control.identityHash,'key',key,'state',state, ...
            'rngState',rng,'savedAt',datestr(now,30));
        file=fullfile(control.controlDirectory,[key,'.mat']);atomic(file,'record',record);
        progress=struct();if isstruct(state)&&isfield(state,'progress'),progress=state.progress;end
        writeState(control,'running',key,file,true,progress);
        if strcmp(action,'boundary')&&sht_tc24_run_control('poll',control)
            writeState(control,'stopped',key,file,true);
            releaseLock(control);
            error('TC24:Control:Stopped','已在安全点%s保存；未完成单元在恢复时按记录重算。',key);
        end
        if nargout,varargout{1}=file;end
    case 'load'
        control=varargin{1};key=validKey(varargin{2});state=[];found=false;
        file=fullfile(control.controlDirectory,[key,'.mat']);
        if control.resume&&isfile(file)
            saved=load(file,'record');verify(saved.record,control);
            assert(strcmp(saved.record.key,key),'TC24:Control:KeyMismatch','检查点键不一致。');
            state=saved.record.state;rng(saved.record.rngState);found=true;
        end
        varargout={state,found};
    case 'state'
        varargout{1}=readState(resolveControl(varargin{1}));
    case 'finishsession'
        % 供外层异常清理使用；仅本次会话可释放自己的锁，拒绝修改别人的旧状态。
        control=resolveControl(varargin{1});old=readState(control);
        assert(strcmp(old.sessionToken,varargin{2}),'TC24:Control:SessionMismatch', ...
            '结束请求不属于当前持锁会话。');
        control.timer=varargin{4};control.sessionToken=old.sessionToken;
        control.sessionStartedAt=old.sessionStartedAt;
        control.priorActiveSeconds=old.priorActiveSeconds;
        control.priorPausedSeconds=old.pausedSeconds;
        varargout{1}=sht_tc24_run_control('finish',control,varargin{3});
    case 'finish'
        control=varargin{1};status=char(varargin{2});
        old=readState(control);writeState(control,status,old.safePoint,old.checkpointFile,old.checkpointAvailable);
        if ismember(status,{'completed','completed_diagnostic','failed','stopped','partial'}),releaseLock(control);end
        if nargout,varargout{1}=readState(control);end
    otherwise
        error('TC24:Control:Action','未知运行控制动作%s。',action);
end
end
function verify(record,control)
assert(strcmp(record.schemaVersion,control.schemaVersion)&& ...
    strcmp(record.runId,control.runId)&&strcmp(record.identityHash,control.identityHash), ...
    'TC24:Control:IdentityMismatch','控制记录与运行/源码/数值身份不一致。');
end
function releaseLock(control)
file=fullfile(control.controlDirectory,'session.lock');if isfile(file),delete(file);end
end
function control=resolveControl(value)
if isstruct(value),control=value;return;end
directory=sht_tc24_absolute_path(value);folder=fullfile(directory,'run_control');
saved=load(fullfile(folder,'identity.mat'),'record');control=saved.record;
control.directory=directory;control.controlDirectory=folder;
end
function state=readState(control)
saved=load(fullfile(control.controlDirectory,'state.mat'),'record');verify(saved.record,control);state=saved.record;
end
function writeState(control,status,key,file,available,progress)
if nargin<6
    progress=struct();stateFile=fullfile(control.controlDirectory,'state.mat');
    if isfile(stateFile)
        old=readState(control);if isfield(old,'progress'),progress=old.progress;end
    end
end
current=toc(control.timer);
record=struct('schemaVersion',control.schemaVersion,'runId',control.runId, ...
    'identityHash',control.identityHash,'status',status,'safePoint',key, ...
    'checkpointFile',file,'checkpointAvailable',available,'updatedAt',datestr(now,30), ...
    'updatedDatenum',now,'sessionStartedAt',control.sessionStartedAt, ...
    'sessionToken',control.sessionToken, ...
    'currentSessionSeconds',current,'priorActiveSeconds',control.priorActiveSeconds, ...
    'activeSeconds',control.priorActiveSeconds+current,'pausedSeconds',control.priorPausedSeconds, ...
    'unfinishedUnitMayRepeat',true,'progress',progress);
atomic(fullfile(control.controlDirectory,'state.mat'),'record',record);
end
function atomic(file,name,value)
% 同目录临时文件完成后替换，绝不把半写MAT标为可续跑检查点。
assert(~containsHandle(value),'TC24:Control:LiveHandle','检查点不能含函数/DLL/图形句柄。');
payload=struct();payload.(name)=value;temporary=[file,'.partial.mat'];
save(temporary,'-struct','payload','-v7.3');[ok,message]=movefile(temporary,file,'f');
assert(ok,'TC24:Control:AtomicSave','检查点落盘失败：%s',message);
end
function yes=containsHandle(value)
yes=isa(value,'function_handle')||isa(value,'handle')||isa(value,'lib.pointer')||isa(value,'lib.struct');
if yes,return;end
if isstruct(value)
    f=fieldnames(value);for i=1:numel(value),for j=1:numel(f),if containsHandle(value(i).(f{j})),yes=true;return;end,end,end
elseif iscell(value)
    for i=1:numel(value),if containsHandle(value{i}),yes=true;return;end,end
end
end
function key=validKey(value)
key=char(value);assert(~isempty(regexp(key,'^[A-Za-z][A-Za-z0-9_]*$','once')), ...
    'TC24:Control:Key','检查点键只能使用字母、数字和下划线。');
end
function hash=digest(value)
assert(~containsHandle(value),'TC24:Control:LiveHandle','内容身份不能包含函数或运行句柄。');
md=java.security.MessageDigest.getInstance('SHA-256');
md.update(unicode2native(jsonencode(value),'UTF-8'));
hash=upper(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end
function value=option(s,name,default)
value=default;if isfield(s,name),value=s.(name);end
end
