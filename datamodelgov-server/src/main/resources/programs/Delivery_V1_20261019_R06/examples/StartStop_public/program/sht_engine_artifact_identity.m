function artifacts = sht_engine_artifact_identity(engineCfg)
%SHT_ENGINE_ARTIFACT_IDENTITY 实际DLL、递归本地声明、MDL和全部MAP身份。
% 仅读文件；不根据旧设计结果生成或改写任何MDL/特性图。
root = engineCfg.interface.controlDir;
files = {fullfile(root,[engineCfg.interface.libraryName '.dll']), ...
    fullfile(root,engineCfg.interface.headerName),engineCfg.modelConfiguration};
kinds = {'dll','header','model_configuration'};
parserStub=fullfile(root,'matlab_loadlibrary_include','stdio.h');
if isfile(parserStub)
    files{end+1}=parserStub; kinds{end+1}='matlab_parser_header';
end
queue = files(2); visited = {};
while ~isempty(queue)
    file = queue{1}; queue(1) = [];
    if any(strcmpi(visited,file)), continue; end
    visited{end+1} = file; %#ok<AGROW>
    local_check(file);
    includes = regexp(fileread(file),'#\s*include\s*"([^"]+)"','tokens');
    for i = 1:numel(includes)
        child = fullfile(fileparts(file),includes{i}{1});
        local_check(child);
        if ~any(strcmpi(files,child))
            files{end+1} = child; kinds{end+1} = 'header_dependency'; %#ok<AGROW>
        end
        queue{end+1} = child; %#ok<AGROW>
    end
end
local_check(engineCfg.modelConfiguration);
maps = regexp(fileread(engineCfg.modelConfiguration), ...
    'mapPath\s*=\s*([^;\r\n]+)','tokens');
for i = 1:numel(maps)
    map = strtrim(strrep(strrep(maps{i}{1},'"',''),'''',''));
    if isempty(regexp(map,'^(?:[A-Za-z]:|[\\/])','once'))
        map = fullfile(fileparts(engineCfg.modelConfiguration),map);
    end
    local_check(map);
    if ~any(strcmpi(files,map))
        files{end+1} = map; kinds{end+1} = 'component_map'; %#ok<AGROW>
    end
end
artifacts = repmat(struct('kind','','file','','sha256',''),numel(files),1);
for i = 1:numel(files)
    local_check(files{i});
    fid=fopen(files{i},'rb'); cleaner=onCleanup(@() fclose(fid));
    bytes=fread(fid,Inf,'*uint8'); clear cleaner;
    digest=java.security.MessageDigest.getInstance('SHA-256');
    digest.update(bytes);
    hash=lower(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
    artifacts(i)=struct('kind',kinds{i},'file',files{i},'sha256',hash);
end
end

function local_check(file)
if ~isfile(file)
    error('SHT:EngineIdentity:MissingAsset','运行依赖不存在：%s。',file);
end
end
