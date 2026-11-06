function varargout = sht_afo_session(action,varargin)
%SHT_AFO_SESSION 多系统单会话核心，界面与独立离线使用同一实现。
% prepare(cfg) -> 快照；run(observer) -> 结果。observer(snapshot)可调用
% command/pause/resume/stop。另一进程可原子写入inbox/*.json并读取status.json。
% pause在主步观测点服务，保持整个Simulink实例，不分段重启、不伪造停车。
persistent S
switch lower(action)
    case 'validate'
        local_validate(varargin{1});
    case 'prepare'
        assert(isempty(S)||strcmp(S.state,'closed')|| ...
            (ismember(S.state,{'ended','failed'})&&strcmp(S.saveState,'saved')), ...
            'sht:afo:busy','已有未保存会话，先保存或明确放弃，不能覆盖内存结果。');
        p=sht_afo_prepare(varargin{1});
        % 准备期间不得发布只有一半字段的ready会话。先完成字典，再一次赋值。
        [catalog,catalogHash]=sht_afo_catalog;
        S=struct('prepared',p,'initialConfig',p.config,'state','ready','time',0,'commandTime',-Inf, ...
            'applied',local_commands(p.config),'pending',[], ...
            'events',struct('id',{},'kind',{},'value',{},'status',{}, ...
            'acceptedTime',{},'appliedTime',{},'reason',{}), ...
            'lastRecord',-Inf,'lastService',-Inf,'timeData',[],'values',{{}}, ...
            'observer',[],'pauseRequested',false,'stopRequested',false, ...
            'pauseSeconds',0,'paceSeconds',0,'started',[], ...
            'lastLog',-Inf,'latest',[],'stopReason','','wallSeconds',0, ...
            'saveState','not_started','saveError','','startedAtLocal','', ...
            'sessionId',char(java.util.UUID.randomUUID),'sampleTime',NaN, ...
            'lastValues',{{}},'publishedSeq',0,'publishError','','observerError','', ...
            'publishClock',tic,'lastPublishWall',-Inf,'isFinal',false, ...
            'lastHeartbeat','','releaseRequested',false,'catalog',{catalog},'catalogHash',catalogHash);
        if p.initialTransition
            S.events(end+1)=struct('id','initial_transition','kind','initial', ...
                'value',S.applied,'status','accepted','acceptedTime',0, ...
                'appliedTime',NaN,'reason','explicit_initial_transition_not_trimmed_target');
        end
        mkdir(fullfile(p.config.outputDir,'inbox'));mkdir(fullfile(p.config.outputDir,'processed_commands'));
        mkdir(fullfile(p.config.outputDir,'stream'));
        sht_afo_json(fullfile(p.config.outputDir,'channels.json'),struct( ...
            'schema','SHT_AFO_CATALOG_V2','runId',p.config.runId, ...
            'sessionId',S.sessionId,'channelCatalogHash',S.catalogHash,'channels',S.catalog));
        local_publish(true);varargout{1}=local_status(S);
    case 'status'
        assert(~isempty(S),'无会话。');varargout{1}=local_status(S);
    case 'command'
        assert(~isempty(S),'无会话。');c=varargin{1};
        assert(isstruct(c)&&all(isfield(c,{'id','kind','value'})),'命令缺少id/kind/value。');
        assert(ischar(c.id)&&~isempty(regexp(c.id,'^[A-Za-z0-9_-]{1,80}$','once')),'命令编号不合法。');
        j=find(strcmp({S.events.id},c.id),1);
        if ~isempty(j)
            assert(strcmp(S.events(j).kind,c.kind)&&isequaln(S.events(j).value,c.value), ...
                'sht:afo:commandCollision','相同命令编号不能改变内容。');
            varargout{1}=S.events(j);return
        end
        event=struct('id',c.id,'kind',c.kind,'value',c.value,'status','rejected', ...
            'acceptedTime',S.time,'appliedTime',NaN,'reason','');
        try
            if isfield(c,'sessionId'),assert(strcmp(c.sessionId,S.sessionId),'会话身份不匹配。');end
            if isfield(c,'runId'),assert(strcmp(c.runId,S.prepared.config.runId),'运行身份不匹配。');end
            management=ismember(c.kind,{'save','release','discard'});
            if management
                assert(ismember(S.state,{'ended','failed'}),'管理命令只在计算结束后接受。');
                if strcmp(c.kind,'release'),assert(strcmp(S.saveState,'saved'),'未保存结果只能明确discard后释放。');end
            else
                assert(ismember(S.state,{'ready','running','paused'}),'会话不能接受物理操纵。');
            end
            assert(management||~S.stopRequested||strcmp(c.kind,'stop'),'正在结束，不再接收新的操纵。');
            switch c.kind
                case 'pause',S.pauseRequested=true;
                case 'resume',S.pauseRequested=false;
                case 'stop',S.stopRequested=true;
                case {'save','release','discard'} % 先登记事件，再执行管理动作。
                otherwise
                    assert(isempty(S.pending),'已有待生效命令，请查询其回执。');
                    candidate=S.prepared.config;candidate=local_assign(candidate,c);
                    local_validate(candidate);S.pending=c;
            end
            event.status='accepted';
        catch err,event.reason=err.message;
        end
        S.events(end+1)=event;
        if strcmp(event.status,'accepted')&&ismember(c.kind,{'save','release','discard'})
            try
                if strcmp(c.kind,'save'),local_save_result;
                else,S.releaseRequested=true;S.state='closed';end
                S.events(end).status='applied';S.events(end).appliedTime=S.time;
            catch err,S.events(end).status='failed';S.events(end).reason=err.message;end
        end
        varargout{1}=S.events(end);local_publish(true);
    case {'pause','resume','stop'}
        c=struct('id',['op_' char(java.util.UUID.randomUUID)],'kind',lower(action),'value',0);
        varargout{1}=sht_afo_session('command',c);
    case 'source'
        t=varargin{1};
        if t>S.commandTime+1e-10
            S.commandTime=t;
            local_control_ack('initial');
            if ~isempty(S.pending)&&~S.stopRequested
                c=S.pending;S.prepared.config=local_assign(S.prepared.config,c);
                S.applied=local_commands(S.prepared.config);S.pending=[];
                j=find(strcmp({S.events.id},c.id),1);S.events(j).status='applied';S.events(j).appliedTime=t;
            end
        end
        varargout{1}=S.applied;
    case 'record'
        t=varargin{1};values=varargin{2};
        if t<=S.lastService+1e-10,return;end
        if isempty(S.timeData)
            spec=sht_afo_channels;
            for k=1:numel(spec)
                assert(numel(values{k})==numel(spec(k).names),'sht:afo:portWidth', ...
                    '通道%s实际宽度%d与已核对字典%d不同。',spec(k).id,numel(values{k}),numel(spec(k).names));
            end
        end
        S.lastService=t;S.time=t;S.lastValues=values;
        if t+1e-9>=S.lastRecord+S.prepared.config.recordStep|| ...
                t+1e-9>=S.prepared.config.duration
            local_append;
        end
        if t>=S.lastLog+S.prepared.config.logEverySeconds
            fprintf('AFO t=%.3f s | Np=%.1f | Ng=%.1f | Wf=%.5f\n',t,values{1}(9),values{1}(10),values{4});
            S.lastLog=t;
        end
        local_inbox(S.prepared.config.outputDir);
        local_publish(false);local_observe;
        drawnow;
        if S.pauseRequested && ~S.stopRequested
            S.state='paused';local_control_ack('pause');local_publish(true);pauseClock=tic;
            while S.pauseRequested && ~S.stopRequested
                pause(0.02);local_inbox(S.prepared.config.outputDir);
                local_publish(false);local_observe;
                drawnow;
            end
            S.pauseSeconds=S.pauseSeconds+toc(pauseClock);S.state='running';local_control_ack('resume');local_publish(true);
        end
        if S.stopRequested
            S.stopReason='user_ended_computation';local_control_ack('stop');local_append;local_publish(true);
            set_param(S.prepared.model,'SimulationCommand','stop');
        elseif strcmp(S.prepared.config.pace,'realtime')
            wait=max(0,t-(toc(S.started)-S.pauseSeconds));
            if wait>0,waitClock=tic;pause(wait);S.paceSeconds=S.paceSeconds+toc(waitClock);end
        end
    case 'run'
        assert(~isempty(S)&&strcmp(S.state,'ready'),'须先准备；结束结果不能作为恢复状态。');
        assert(~bdIsLoaded(S.prepared.model)&&~libisloaded('GTESS'),'sht:afo:busy', ...
            '当前进程已有模型或GTESS，不能覆盖其他会话。');
        local_verify_prepared(S.prepared);
        if ~isempty(varargin),S.observer=varargin{1};end
        S.state='running';S.started=tic;S.startedAtLocal=datestr(now,'yyyy-mm-ddTHH:MM:SS');local_publish(true);
        old=pwd;oldPath=path;oldGen=Simulink.fileGenControl('getConfig');
        restore=onCleanup(@()local_cleanup(old,oldPath,oldGen));
        cd(S.prepared.runtime);
        Simulink.fileGenControl('set','CacheFolder',fullfile(S.prepared.runtime,'cache'), ...
            'CodeGenFolder',fullfile(S.prepared.runtime,'code'),'createDir',true);
        addpath(S.prepared.config.sourceDir,'-begin');addpath(S.prepared.runtime,'-begin');
        try
            load_system(fullfile(S.prepared.runtime,[S.prepared.model '.slx']));
            rehash path;
            required={'SFunc_AFO_Command','SFunc_AFO_Recorder','sht_afo_channels'};
            for k=1:numel(required)
                assert(exist(required{k},'file')==2,'sht:afo:runtimePath', ...
                    '运行前找不到适配函数%s，请检查成套程序路径。',required{k});
            end
            simulation=sim(S.prepared.model,'ReturnWorkspaceOutputs','on');
            S.wallSeconds=toc(S.started);S.state='ended';S.isFinal=true;local_append;local_publish(true);
            if isempty(S.stopReason),S.stopReason='time_limit';end
            local_cancel_pending;
            assert(~isempty(S.timeData),'没有采集到物理数据。');
            if strcmp(S.stopReason,'time_limit')
                assert(abs(simulation.tout(end)-S.prepared.config.duration)<1e-8,'未达到指定终点。');
            end
        catch err
            S.wallSeconds=toc(S.started);S.state='failed';S.stopReason=err.message;S.isFinal=true;local_append;
            fprintf(2,'%s\n',getReport(err,'extended','hyperlinks','off'));
            fprintf(2,'异常时适配路径存在=%d，记录器=%s，当前目录=%s\n', ...
                any(strcmp(strsplit(path,pathsep),S.prepared.config.sourceDir)), ...
                which('SFunc_AFO_Recorder'),pwd);
            local_cancel_pending;
            % 诊断或导出自身出错时也必须保留最初的求解异常。
            try
                local_publish(true);S.result=local_result(S);local_save_result;
            catch saveError,fprintf(2,'保存失败（原错误另报）：%s\n',saveError.message);end
            rethrow(err);
        end
        % 导出放在数值求解异常分支之外，不能把Excel被占用误判为物理求解失败。
        S.result=local_result(S);local_save_result;varargout{1}=S.result;
    case 'save'
        assert(~isempty(S)&&isfield(S,'result')&&ismember(S.state,{'ended','failed'}), ...
            '须先结束计算；保存重试不会重新计算或改变历史轨迹。');
        local_save_result;varargout{1}=S.result;
    case 'result'
        assert(isfield(S,'result'),'结果尚未形成。');varargout{1}=S.result;
    case 'service'
        % 供工作进程在计算结束后继续处理保存重试和释放，不重新调用sim。
        assert(~isempty(S),'无会话。');local_inbox(S.prepared.config.outputDir);
        local_publish(false);local_observe;varargout{1}=local_status(S);
    case 'close'
        assert(isempty(S)||~ismember(S.state,{'running','paused'}),'先结束当前运行。');
        if ~isempty(S)
            assert(strcmp(S.state,'ready')||strcmp(S.saveState,'saved')||strcmp(S.state,'closed'), ...
                '未保存结果不能关闭；请保存或明确提交discard。');
            S.state='closed';local_publish(true);
        end
    otherwise,error('sht:afo:action','未知动作 %s',action);
end
    function local_cancel_pending
        for n=1:numel(S.events)
            if strcmp(S.events(n).status,'accepted')
                S.events(n).status='not_applied';S.events(n).reason='computation_ended_before_application';
            end
        end
        S.pending=[];
    end
    function local_control_ack(kind)
        for n=1:numel(S.events)
            if strcmp(S.events(n).kind,kind)&&strcmp(S.events(n).status,'accepted')
                S.events(n).status='applied';S.events(n).appliedTime=S.time;
            end
        end
    end
    function local_save_result
        S.saveState='writing';S.saveError='';local_publish(true);
        try
            sht_afo_results('save',S.result,S.prepared.config.outputDir);S.saveState='saved';
        catch saveError
            S.saveState='failed';S.saveError=saveError.message;
            local_publish(true);
            rethrow(saveError);
        end
        local_publish(true);
    end
    function local_append
        % 只取已经执行的主步输出；尾样本不插值，不重复积分。
        if isempty(S.lastValues)||S.sampleTime==S.time,return;end
        S.lastRecord=S.time;S.sampleTime=S.time;S.timeData(end+1,1)=S.time;
        S.values(end+1,:)=S.lastValues;S.latest=S.lastValues;
    end
    function local_observe
        if isempty(S.observer),return;end
        try,S.observer(local_status(S));
        catch observerError
            % 绘图/客户端异常与数值异常分开；历史仍记录并可重新连接。
            S.observerError=observerError.message;S.observer=[];local_publish(true);
            warning('sht:afo:observer','观察回调停用：%s',observerError.message);
        end
    end
    function local_publish(force)
        wall=toc(S.publishClock);
        if ~force&&wall-S.lastPublishWall<S.prepared.config.publishWallStep&& ...
                numel(S.timeData)-S.publishedSeq<S.prepared.config.publishBatchSize,return;end
        S.lastPublishWall=wall;S.lastHeartbeat=datestr(now,'yyyy-mm-ddTHH:MM:SS.FFF');
        try
            if S.prepared.config.publishLive
                while S.publishedSeq<numel(S.timeData)
                    first=S.publishedSeq+1;last=min(numel(S.timeData),first+S.prepared.config.publishBatchSize-1);
                    rows=zeros(last-first+1,numel(S.catalog));
                    for n=first:last,rows(n-first+1,:)=horzcat(S.values{n,:});end
                    quality=double(~isfinite(rows)); % 0有限值，1非有限值；不以0补数据。
                    unknown=strcmp({S.catalog.availability},'unit_unconfirmed');
                    quality(:,unknown)=3;
                    if ismember(S.prepared.config.loadMode,{'power','torque'})
                        mask=ismember({S.catalog.id},{'load_02','load_03','load_06'});
                        quality(:,mask&all(~isfinite(rows),1))=2;
                    end
                    packet=struct('schema','SHT_AFO_SAMPLES_V2','runId',S.prepared.config.runId, ...
                        'sessionId',S.sessionId,'channelCatalogHash',S.catalogHash, ...
                        'firstSeq',first,'lastSeq',last,'sampleSeq',(first:last)', ...
                        'sampleTime',S.timeData(first:last),'values',rows,'quality',quality, ...
                        'isFinal',S.isFinal&&last==numel(S.timeData));
                    sht_afo_json(fullfile(S.prepared.config.outputDir,'stream',sprintf('%012d.json',first)),packet);
                    S.publishedSeq=last;
                end
            end
            S.publishError='';
        catch publishError
            S.publishError=publishError.message; % 保留未发布区间，下一周期从原序号重试。
        end
        try
            sht_afo_json(fullfile(S.prepared.config.outputDir,'status.json'),local_status(S));
            for n=1:numel(S.events)
                sht_afo_json(fullfile(S.prepared.config.outputDir,'processed_commands', ...
                    [S.events(n).id '.json.receipt.json']),S.events(n));
            end
        catch publishError,S.publishError=publishError.message;end
    end
end
function cfg=local_assign(cfg,c)
switch c.kind
    case 'np',cfg.npRatio=c.value;
    case 'load'
        switch cfg.loadMode
            case 'power',cfg.powerW=c.value;
            case 'torque',cfg.mkpNm=c.value;
            case 'pitch',cfg.pitchDeg=c.value;
            case 'dual_pitch'
                assert(numel(c.value)==2,'主尾桨须成对提交。');
                cfg.mainPitchDeg=c.value(1);cfg.tailPitchDeg=c.value(2);
        end
    otherwise,error('sht:afo:command','未知命令，不允许运行中改变配置。');
end
end
function local_validate(c)
assert(ischar(c.engineId)&&~isempty(strtrim(c.engineId)),'发动机编号不能为空。');
assert(ischar(c.runId)&&~isempty(strtrim(c.runId)),'运行编号不能为空。');
assert(isscalar(c.npRatio)&&any(abs(c.npRatio-[.8 .9 .95 1 1.05])<1e-12),'Np须选80/90/95/100/105%%。');
assert(ismember(c.loadMode,{'power','torque','pitch','dual_pitch'}),'未知负载方式。');
validateattributes(c.powerW,{'double'},{'real','scalar','finite','nonnegative'});
validateattributes(c.mkpNm,{'double'},{'real','scalar','finite','nonnegative'});
if strcmp(c.loadMode,'pitch'),validateattributes(c.pitchDeg,{'double'},{'real','scalar','>=',6,'<=',14});end
if strcmp(c.loadMode,'dual_pitch')
    validateattributes(c.mainPitchDeg,{'double'},{'real','scalar','finite','>=',c.mainPitchBounds(1),'<=',c.mainPitchBounds(2)});
    validateattributes(c.tailPitchDeg,{'double'},{'real','scalar','finite','>=',c.tailPitchBounds(1),'<=',c.tailPitchBounds(2)});
    validateattributes(c.tailToMainPowerRatio,{'double'},{'real','scalar','finite','nonnegative'});
    validateattributes(c.tailDesignPitchDeg,{'double'},{'real','scalar','finite','positive'});
    th=local_equivalent_pitch(c);
    assert(th>=6&&th<=14,'sht:afo:equivalentPitch', ...
        '主尾桨合成等效角%.6g超出现有负载模型6至14度范围，拒绝施加而不静默限幅。',th);
end
end
function x=local_commands(c)
theta=c.pitchDeg;
if strcmp(c.loadMode,'dual_pitch')
    % 与现有单旋翼1.5次幂式一致的扭矩可加折算：两桨真正独立变化，
    % 合成后的等效角仅供旧边界使用，不把尾桨接到GT附件轴。
    theta=local_equivalent_pitch(c);
end
x=[c.npRatio*c.designNpRpm,c.powerW,c.mkpNm,theta];
end
function theta=local_equivalent_pitch(c)
f=1/(1+c.tailToMainPowerRatio);gm=.15+.85*(c.mainPitchDeg/12)^1.5;
gt=.15+.85*abs(c.tailPitchDeg/c.tailDesignPitchDeg)^1.5;
theta=12*((f*gm+(1-f)*gt-.15)/.85)^(2/3);
end
function out=local_status(s)
wall=0;if ~isempty(s.started),wall=toc(s.started);end
if ismember(s.state,{'ended','failed','closed'}),wall=s.wallSeconds;end
out=struct('schema','SHT_AFO_STATUS_V2','runId',s.prepared.config.runId, ...
    'engineId',s.prepared.config.engineId,'state',s.state,'time',s.time, ...
    'wallSeconds',wall,'prepareSeconds',s.prepared.prepareSeconds, ...
    'applied',s.applied,'pending',s.pending,'events',s.events,'stopReason',s.stopReason, ...
    'saveState',s.saveState,'saveError',s.saveError, ...
    'sessionId',s.sessionId,'channelCatalogHash',s.catalogHash, ...
    'currentSimulationTime',s.time,'sampleTime',s.sampleTime,'sampleSeq',numel(s.timeData), ...
    'publishedSeq',s.publishedSeq,'isFinal',s.isFinal,'lastHeartbeat',s.lastHeartbeat, ...
    'duration',s.prepared.config.duration,'progress',min(1,max(0,s.time/s.prepared.config.duration)), ...
    'pauseRequested',s.pauseRequested,'stopRequested',s.stopRequested, ...
    'publishLive',s.prepared.config.publishLive,'publishError',s.publishError, ...
    'observerError',s.observerError);
if ~isempty(s.latest)
    out.Np=s.latest{1}(9);out.Ng=s.latest{1}(10);out.Wf=s.latest{4};
    out.values=s.latest; % 与sht_afo_channels同顺序；全部系统供同一实时视图读取。
end
end
function local_inbox(folder)
files=dir(fullfile(folder,'inbox','*.json'));
for k=1:numel(files)
    file=fullfile(files(k).folder,files(k).name);
    try
        c=sht_afo_read_json(file);s=sht_afo_session('status');
        assert(isfield(c,'sessionId')&&strcmp(c.sessionId,s.sessionId)&& ...
            isfield(c,'runId')&&strcmp(c.runId,s.runId),'外部命令缺少或不匹配运行/会话身份。');
        r=sht_afo_session('command',c);
    catch err,r=struct('status','rejected','reason',err.message);end
    sht_afo_json(fullfile(folder,'processed_commands',[files(k).name '.receipt.json']),r);
    movefile(file,fullfile(folder,'processed_commands',files(k).name));
end
end
function r=local_result(s)
r=struct('schema','SHT_AFO_RESULT_V2','config',s.prepared.config, ...
    'initialConfig',s.initialConfig, ...
    'identity',s.prepared.identity,'state',s.state,'stopReason',s.stopReason, ...
    'time',s.timeData,'values',{s.values},'channels',sht_afo_channels, ...
    'events',s.events,'initialState',s.prepared.initialState,'finalSimulationTime',s.time, ...
    'preparedAtLocal',s.prepared.preparedAtLocal,'startedAtLocal',s.startedAtLocal, ...
    'matlabVersion',s.prepared.matlabVersion,'matlabRelease',s.prepared.matlabRelease, ...
    'catalog',s.catalog,'channelCatalogHash',s.catalogHash,'sessionId',s.sessionId, ...
    'timing',struct('prepare',s.prepared.prepareSeconds,'runWall',s.wallSeconds, ...
    'humanPause',s.pauseSeconds,'paceWait',s.paceSeconds, ...
    'computeAndService',max(0,s.wallSeconds-s.pauseSeconds-s.paceSeconds)));
end
function local_verify_prepared(p)
% 准备之后的源文件/运行副本变化必须重新准备，不用旧初态搭配新依赖。
for k=1:numel(p.identity)
    item=p.identity(k);
    if strcmp(item.name,'runtime/instrumented_model.slx')
        file=fullfile(p.runtime,[p.model '.slx']);
    elseif startsWith(item.name,'runtime/')
        file=fullfile(p.runtime,item.name(9:end));
    else,file=fullfile(p.config.sourceDir,item.name);end
    fid=fopen(file,'rb');assert(fid>=0,'sht:afo:identity','准备依赖丢失：%s',file);
    bytes=fread(fid,Inf,'*uint8');fclose(fid);
    md=java.security.MessageDigest.getInstance('SHA-256');md.update(bytes);
    sha=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
    assert(strcmp(sha,item.sha256),'sht:afo:identity','准备后依赖改变，请重新准备：%s',file);
end
end
function local_cleanup(folder,oldPath,oldGen)
if bdIsLoaded('Dll_Control_AFO_V8_5_R2019b'),close_system('Dll_Control_AFO_V8_5_R2019b',0);end
if libisloaded('GTESS'),calllib('GTESS','DLL_SHT_Free');unloadlibrary('GTESS');end
Simulink.fileGenControl('setConfig','config',oldGen);cd(folder);path(oldPath);
end
