function [connections,modified] = sht_afo_surgery(model, cfg)
%SHT_AFO_SURGERY 结构性手术(幂等):4个指令常值换 Level-2 MATLAB S-Function 源,
% 全部业务输出接同一只读记录器(SFunc_AFO_Recorder)，不增加物理反馈。
% prepare与启动预装配共用:模型已带同版本手术戳(记录器块Tag)时零成本返回现有连接,
% 不重做手术——同引擎连续准备免重复手术(实测8~19s)的核心。手术逻辑或通道字典
% 变化时递增下方版本串(与 sht_afo_prepare.m/sht_afo_presurgery.m 的 expectedTag
% 同步),旧改装(内存/缓存)自动失效重做。
spec=sht_afo_channels;
reference=isfield(cfg,'verificationOriginalSources')&&cfg.verificationOriginalSources;
tag=sprintf('dmg-afo-surgery-v1|n=%d|ref=%d',numel(spec),double(reference));
sink=[model '/AFO Business Recorder'];
if ~isempty(find_system(model,'SearchDepth',1,'Name','AFO Business Recorder')) && ...
        strcmp(get_param(sink,'Tag'),tag)
    connections=local_connections(model,spec);modified=false;return;
end
modified=true;
if reference
    assert(cfg.legacyPulses,'原指令源只用于显式旧脉冲回归。');
else
    % 新源只替代四个指令常值，原物理接线和原脉冲验证分支均保留。
    commandNames={'NpDem','Constant2','Mkp Direct Command','Collective Pitch Command'};
    for k=1:4
        b=[model '/' commandNames{k}]; ph=get_param(b,'PortHandles');
        ln=get_param(ph.Outport,'Line'); dest=get_param(ln,'DstPortHandle'); pos=get_param(b,'Position');
        delete_line(ln);delete_block(b);
        add_block('simulink/User-Defined Functions/Level-2 MATLAB S-Function',b, ...
            'FunctionName','SFunc_AFO_Command','Parameters',num2str(k),'Position',pos);
        ph=get_param(b,'PortHandles');
        for j=1:numel(dest),add_line(model,ph.Outport,dest(j),'autorouting','off');end
    end
end
% 全部业务输出接同一个只读记录器，不增加物理反馈。
local_drop_recorder(model,sink);  % 旧版本手术残留(异Tag)先拆除(原始模型无记录器时内部自守卫)
add_block('simulink/User-Defined Functions/Level-2 MATLAB S-Function',sink, ...
    'FunctionName','SFunc_AFO_Recorder','Parameters',num2str(numel(spec)), ...
    'Position',[2200 100 2360 400]);
connections=cell(numel(spec),3);
for k=1:numel(spec)
    src=Simulink.ID.getHandle([model ':' num2str(spec(k).sid)]);
    connections(k,:)={spec(k).id,getfullname(src),spec(k).port};
    port=sht_afo_observation_port(model,src,spec(k).port,k);
    dest=get_param(sink,'PortHandles');
    add_line(model,port,dest.Inport(k),'autorouting','off');
end
% 手术戳最后落:半途失败不留戳,复用守卫不会把半成品当改装模型。
set_param(sink,'Tag',tag);
save_system(model);
end
function connections=local_connections(model,spec)
% 复用路径不重连信号线,观测连接描述直接按当前模型与通道字典重算(与手术路径一致)。
connections=cell(numel(spec),3);
for k=1:numel(spec)
    src=Simulink.ID.getHandle([model ':' num2str(spec(k).sid)]);
    connections(k,:)={spec(k).id,getfullname(src),spec(k).port};
end
end
function local_drop_recorder(model,sink)
% 只在记录器已存在时拆除(原始模型没有该块,get_param会抛"无效Simulink对象名")
if isempty(find_system(model,'SearchDepth',1,'Name','AFO Business Recorder')),return;end
ph=get_param(sink,'PortHandles');
for j=1:numel(ph.Inport)
    ln=get_param(ph.Inport(j),'Line');
    if ln>0,delete_line(ln);end
end
delete_block(sink);
end
