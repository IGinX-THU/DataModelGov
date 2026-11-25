function [catalog,hash]=sht_afo_catalog(spec)
%SHT_AFO_CATALOG 稳定列ID、物理来源和界面显示清单。显示数不等于采集数。
% 进程级memoize(readtable解析CSV每次1~9s):键=CSV与通道字典的mtime/字节数,
% 任一文件变化自动失效重读;引擎复位clear sht_afo_session不影响本函数persistent。
persistent C H K
if nargin==0,spec=sht_afo_channels;end
csv=fullfile(fileparts(mfilename('fullpath')),'sht_afo_display_channels.csv');
% 键计算整体fail-safe:memo只是优化,任何异常(dir字段缺失/文件暂不可见)都放弃memo
% 走原readtable逻辑,绝不因优化路径报错(实测启动窗口dir结构偶发缺datnum字段)
key='';
try
    dc=dir(csv);chm=dir(which('sht_afo_channels'));
    if ~isempty(dc)&&~isempty(chm)&&isfield(dc,'datnum')&&isfield(dc,'bytes')&&...
            isfield(chm,'datnum')&&isfield(chm,'bytes')
        key=sprintf('%d|%d|%d|%d|%d|%s',dc(1).datnum,dc(1).bytes,numel(spec), ...
            chm(1).datnum,chm(1).bytes,version('-release'));
    end
catch
    key='';
end
if isempty(C)||~strcmp(K,key)
    [C,H]=local_catalog_impl(csv,spec);
    K=key;
end
catalog=C;hash=H;
end
function [catalog,hash]=local_catalog_impl(csv,spec)
display=readtable(csv,'Encoding','UTF-8','TextType','char');
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
