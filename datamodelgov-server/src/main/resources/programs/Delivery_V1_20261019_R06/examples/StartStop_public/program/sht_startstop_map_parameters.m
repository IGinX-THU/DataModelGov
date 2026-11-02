function value = sht_startstop_map_parameters(cfg, theta)
%SHT_STARTSTOP_MAP_PARAMETERS 按部件字典打包/解包低速新增区先验。
% 每部件两个量：锁转流量比例、压气机压损或涡轮锁转最大压比。
names = cfg.topology.componentNames;
if nargin == 1
    value = zeros(1,2*numel(names));
else
    assert(numel(theta)==2*numel(names),'低速图参数个数与拓扑不一致。');
    value = cfg.extension;
end
for i=1:numel(names)
    name=names{i};
    if strcmp(cfg.maps.(name).kind,'compressor')
        second='lockedPressureLoss';
    else
        second='lockedMaximumPressureRatio';
    end
    if nargin==1
        value(2*i-1:2*i)=[cfg.extension.(name).lockedFlowFraction, ...
            cfg.extension.(name).(second)];
    else
        value.(name).lockedFlowFraction=theta(2*i-1);
        value.(name).(second)=theta(2*i);
    end
end
end
