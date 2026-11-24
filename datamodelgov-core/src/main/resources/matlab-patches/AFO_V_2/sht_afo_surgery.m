function sht_afo_surgery(model, spec)
%SHT_AFO_SURGERY Ó„'9Å:ÆŸäÅAFO}ä/°UhS-Functionê¨¿İX
% Mnàs,Î8{öÅ–:gL;í prepare 1(¹(ˆkóÇ
commandNames={'NpDem','Constant2','Mkp Direct Command','Collective Pitch Command'};
reference=isfield(cfg,'verificationOriginalSources')&&cfg.verificationOriginalSources;
if reference,assert(cfg.legacyPulses,'Ô­Ö¸ÁîÔ´Ö»ÓÃÓÚÏÔÊ½¾ÉÂö³å»Ø¹é¡£');end
for k=1:4
    if reference,continue;end % »Ø¹é±£ÁôÔ­³£Öµ¿é£¬ÔËĞĞÉí·İÔÚÏÂ·½°´Êµ¼ÊSLX¼ÆËã¡£
    b=[model '/' commandNames{k}]; ph=get_param(b,'PortHandles');
    ln=get_param(ph.Outport,'Line'); dest=get_param(ln,'DstPortHandle'); pos=get_param(b,'Position');
    delete_line(ln);delete_block(b);
    add_block('simulink/User-Defined Functions/Level-2 MATLAB S-Function',b, ...
        'FunctionName','SFunc_AFO_Command','Parameters',num2str(k),'Position',pos);
    ph=get_param(b,'PortHandles');
    for j=1:numel(dest),add_line(model,ph.Outport,dest(j),'autorouting','on');end
end
% È«²¿ÒµÎñÊä³ö½ÓÍ¬Ò»¸öÖ»¶Á¼ÇÂ¼Æ÷£¬²»Ôö¼ÓÎïÀí·´À¡¡£
spec=sht_afo_channels; sink=[model '/AFO Business Recorder'];
add_block('simulink/User-Defined Functions/Level-2 MATLAB S-Function',sink, ...
    'FunctionName','SFunc_AFO_Recorder','Parameters',num2str(numel(spec)), ...
    'Position',[2200 100 2360 400]);
connections=cell(numel(spec),3);
for k=1:numel(spec)
    src=Simulink.ID.getHandle([model ':' num2str(spec(k).sid)]);
    connections(k,:)={spec(k).id,getfullname(src),spec(k).port};
    port=sht_afo_observation_port(model,src,spec(k).port,k);
    dest=get_param(sink,'PortHandles');
    add_line(model,port,dest.Inport(k),'autorouting','on');
end
save_system(model);

end