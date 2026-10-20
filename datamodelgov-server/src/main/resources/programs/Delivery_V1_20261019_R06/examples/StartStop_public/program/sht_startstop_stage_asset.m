function [result, source] = sht_startstop_stage_asset(action, stage, cfg, result)
%SHT_STARTSTOP_STAGE_ASSET 保存/读取当前模型的起停中间资产，不搜索历史报告。
% DLL、头文件、MDL或原图改变后，旧资产明确失效，必须重新执行上游。
root = fullfile(cfg.paths.matlabRoot, 'MiddleData', 'startstop');
if cfg.modelMode == 0
    root = fullfile(root,cfg.topology.assetNamespace);
end
assert(ismember(stage, {'design','stage12','stage05','main_sync'}), '未知资产阶段。');
files = {cfg.paths.dll, cfg.paths.matlabHeader, cfg.paths.splitModel};
names = fieldnames(cfg.maps);
for i = 1:numel(names)
    files{end+1} = fullfile(cfg.paths.cRoot,cfg.maps.(names{i}).sourceName); %#ok<AGROW>
end
identity = cellfun(@local_hash, files, 'UniformOutput', false);
assert(strcmp(local_hash(fullfile(cfg.paths.matlabRoot,'GTESS.dll')),identity{1}), ...
    'M目录DLL与C构建DLL不一致，禁止发布/继承起停资产。');
assert(strcmp(local_hash(fullfile(cfg.paths.matlabRoot,cfg.topology.modelFile)),identity{3}), ...
    'M目录与C目录的当前拓扑MDL不一致。');
indexPath = fullfile(root, [stage, '_latest.mat']);
mapField = '';
if strcmp(stage,'stage12'), mapField = 'mapResult'; end
if strcmp(stage,'stage05'), mapField = 'finalMapAudit'; end
if strcmp(action,'publish')
    assert(result.accepted, '未通过的结果不能发布为下游资产。');
    leaf = [stage, '_', datestr(now,'yyyymmdd_HHMMSS_FFF')];
    assetRoot = fullfile(root, leaf);
    mkdir(assetRoot);
    mapHashes = {};
    if ~isempty(mapField)
        mkdir(fullfile(assetRoot,'maps'));
        for i = 1:numel(result.(mapField).items)
            item = result.(mapField).items(i);
            [~,name,ext] = fileparts(item.outputPath);
            relative = fullfile('maps',[name,ext]);
            copyfile(item.outputPath, fullfile(assetRoot,relative));
            result.(mapField).items(i).outputPath = relative;
            mapHashes{i} = local_hash(fullfile(assetRoot,relative)); %#ok<AGROW>
        end
    end
    save(fullfile(assetRoot,'result.mat'),'result','identity','mapHashes','-v7.3');
    save(indexPath,'leaf');
elseif ~strcmp(action,'load')
    error('操作只能是publish或load。');
end
assert(isfile(indexPath), '缺少%s当前资产，请先重新执行上游。',stage);
index = load(indexPath,'leaf');
assert(~contains(index.leaf,'..') && ~contains(index.leaf,filesep), '资产索引非法。');
assetRoot = fullfile(root,index.leaf);
source = struct('runRoot',assetRoot,'resultPath',fullfile(assetRoot,'result.mat'));
saved = load(source.resultPath);
assert(isequal(identity,saved.identity), 'sht:startstop:staleAsset', ...
    '%s资产的DLL/头文件/MDL/原图身份已变化，禁止继承旧验收。',stage);
result = saved.result;
assert(result.accepted, '资产没有通过验收。');
if ~isempty(mapField)
    for i = 1:numel(result.(mapField).items)
        p = fullfile(assetRoot,result.(mapField).items(i).outputPath);
        assert(strcmp(local_hash(p),saved.mapHashes{i}), '冻结图被修改：%s',p);
        result.(mapField).items(i).outputPath = p;
    end
end
source.identity = identity;
end

function value = local_hash(p)
fid = fopen(p,'rb');
assert(fid >= 0, '缺少当前资产依赖：%s',p);
cleanup = onCleanup(@() fclose(fid));
md = java.security.MessageDigest.getInstance('SHA-256');
md.update(typecast(fread(fid,inf,'*uint8'),'int8'));
value = upper(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end
