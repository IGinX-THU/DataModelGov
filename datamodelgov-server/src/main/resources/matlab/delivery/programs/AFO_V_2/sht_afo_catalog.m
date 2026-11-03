function [catalog,hash]=sht_afo_catalog(spec)
%SHT_AFO_CATALOG 稳定列ID、物理来源和界面显示清单。显示数不等于采集数。
if nargin==0,spec=sht_afo_channels;end
display=readtable(fullfile(fileparts(mfilename('fullpath')),'sht_afo_display_channels.csv'), ...
    'Encoding','UTF-8','TextType','char');
catalog=struct('id',{},'group',{},'name',{},'unit',{},'source',{},'role',{}, ...
    'display',{},'displayGroup',{},'panel',{},'physicalDefinition',{},'availability',{});
for k=1:numel(spec)
    for j=1:numel(spec(k).names)
        id=sprintf('%s_%02d',spec(k).id,j);
        if startsWith(spec(k).id,'fuel_proxy_')||startsWith(spec(k).id,'air_g')
            id=spec(k).id;
        end
        n=find(strcmp(display.Id,id));assert(numel(n)<=1,'重复显示ID。');
        name=spec(k).names{j};definition=spec(k).role;panel='';displayGroup='';
        if ~isempty(n)
            name=display.DisplayName{n};definition=display.PhysicalDefinition{n};
            panel=display.Panel{n};displayGroup=display.Group{n};
        end
        availability='recorded';
        if strcmp(spec(k).units{j},'model_unit_unconfirmed'),availability='unit_unconfirmed';end
        catalog(end+1)=struct('id',id,'group',spec(k).group,'name',name, ...
            'unit',spec(k).units{j},'source',sprintf('%d:%d',spec(k).sid,spec(k).port), ...
            'role',spec(k).role,'display',~isempty(n),'displayGroup',displayGroup,'panel',panel, ...
            'physicalDefinition',definition,'availability',availability);
    end
end
assert(numel(unique({catalog.id}))==numel(catalog),'采集字典ID不唯一。');
assert(all(ismember(display.Id,{catalog.id})),'显示清单含未采集通道。');
bytes=unicode2native(jsonencode(catalog),'UTF-8');
md=java.security.MessageDigest.getInstance('SHA-256');md.update(bytes);
hash=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end
