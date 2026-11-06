function file=sht_tc27_uq_delivery_path(c,method)
%SHT_TC27_UQ_DELIVERY_PATH 两种观测模式独立交付，不覆盖历史R007结果。
p=sht_tc27_paths(c.options);suffix='';
if isfield(c,'observationMode'),suffix=['_',c.observationMode];end
if isfield(c.options,'errorModel')&&strcmp(c.options.errorModel,'legacy_R007')
    suffix=[suffix,'_legacy_R007'];
end
if isfield(c.options,'deliveryTag')&&~isempty(c.options.deliveryTag)
    suffix=[suffix,'_',c.options.deliveryTag];
end
file=fullfile(p.middle,['tc27_uq_',method,'_',c.route,'_',c.method, ...
    '_model_',c.identity.delivery(1:12),suffix,'.xlsx']);
end
