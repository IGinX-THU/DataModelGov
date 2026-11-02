function runtime = sht_startstop_create_runtime(cfg, mapResult, runRoot)
%SHT_STARTSTOP_CREATE_RUNTIME 生成只引用扩展图的独立DLL运行目录。

[~,runName] = fileparts(runRoot);
runtimeRoot = fullfile(cfg.paths.matlabRoot,'MiddleData','startstop', ...
    cfg.topology.assetNamespace,'runtime');
if ~isfolder(runtimeRoot), mkdir(runtimeRoot); end
runtimeDir = fullfile(runtimeRoot,runName);
% 不同报告目录可有相同末级名称，同一测试也允许重复执行。旧运行副本
% 已被结果引用时不能覆盖，重名则分配新目录，所有调用方使用返回路径。
if exist(runtimeDir,'file') || isfolder(runtimeDir)
    [~,uniqueName] = fileparts(tempname(runtimeRoot));
    runtimeDir = fullfile(runtimeRoot,[runName,'_',uniqueName]);
end
mkdir(runtimeDir);

support = {'GTESS.dll', 'GTESS.h', 'blockAndFunctions.h', 'types_TMATS.H'};
sources = {cfg.paths.dll, cfg.paths.matlabHeader, ...
    fullfile(cfg.paths.matlabRoot, 'blockAndFunctions.h'), ...
    fullfile(cfg.paths.matlabRoot, 'types_TMATS.H')};
for i = 1:numel(support)
    assert(isfile(sources{i}), '运行依赖不存在：%s', sources{i});
    copyfile(sources{i}, fullfile(runtimeDir, support{i}), 'f');
end

for i = 1:numel(mapResult.items)
    name = mapResult.items(i).name;
    outputName = cfg.maps.(name).outputName;
    copyfile(mapResult.items(i).outputPath, ...
        fullfile(runtimeDir, outputName), 'f');
end

modelText = fileread(cfg.paths.splitModel);
for component = fieldnames(cfg.maps).'
    modelText = local_replace_component_map( ...
        modelText, component{1}, cfg.maps.(component{1}).outputName);
end
modelPath = fullfile(runtimeDir, cfg.topology.modelFile);
fid = fopen(modelPath, 'w');
assert(fid >= 0, '无法写入起停运行配置：%s', modelPath);
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, modelText, 'char');
clear cleanup;

runtime = struct('controlDir', runtimeDir, 'modelPath', modelPath, ...
    'dllPath', fullfile(runtimeDir, 'GTESS.dll'), ...
    'headerPath', fullfile(runtimeDir, 'GTESS.h'), ...
    'createdAt', datestr(now, 31));
save(fullfile(runtimeDir, 'runtime_manifest.mat'), 'runtime', '-v7');
end

function text = local_replace_component_map(text, component, mapName)
lines = regexp(text, '\r\n|\n|\r', 'split');
header = ['[componentName]=', component];
startIndex = find(strcmp(strtrim(lines), header));
assert(numel(startIndex) == 1, '配置中部件%s应恰好出现一次。', component);
next = find(startsWith(strtrim(lines(startIndex + 1:end)), ...
    '[componentName]='), 1, 'first');
if isempty(next)
    stopIndex = numel(lines);
else
    stopIndex = startIndex + next - 1;
end
relative = find(~cellfun(@isempty, regexp(lines(startIndex:stopIndex), ...
    '^\s*mapPath\s*=', 'once')));
assert(numel(relative) == 1, '部件%s的mapPath应恰好出现一次。', component);
index = startIndex + relative - 1;
indent = regexp(lines{index}, '^\s*', 'match', 'once');
lines{index} = [indent, 'mapPath=', mapName];
text = strjoin(lines, newline);
end
