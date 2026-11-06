function port=sht_afo_observation_port(model,block,number,index)
%SHT_AFO_OBSERVATION_PORT 将嵌套信号只读引出，不改原有反馈连接。
% 每层只增加末尾Outport，已有端口编号保持不变。全部信号最终交给
% 一个记录器，避免多个局部记录器在同一时刻相互覆盖。
ph=get_param(block,'PortHandles');port=ph.Outport(number);
parent=get_param(block,'Parent');level=0;
while ~strcmp(parent,model)
    level=level+1;
    outs=find_system(parent,'SearchDepth',1,'BlockType','Outport');
    next=1;
    for j=1:numel(outs),next=max(next,str2double(get_param(outs{j},'Port'))+1);end
    tap=sprintf('%s/AFO_Observe_%03d_%02d',parent,index,level);
    add_block('simulink/Sinks/Out1',tap,'Port',num2str(next), ...
        'Position',[1600 20+index*20 1630 34+index*20]);
    dst=get_param(tap,'PortHandles');add_line(parent,port,dst.Inport,'autorouting','on');
    ph=get_param(parent,'PortHandles');port=ph.Outport(next);
    parent=get_param(parent,'Parent');
end
end
