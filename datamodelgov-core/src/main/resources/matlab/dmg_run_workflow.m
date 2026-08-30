function manifestFile = dmg_run_workflow(entryPoint, requestFile, resultFile, manifestFile)
entryPoint = char(entryPoint);
if isempty(regexp(entryPoint, '^[A-Za-z][A-Za-z0-9_]*$', 'once'))
    error('DMG:Workflow:InvalidEntryPoint', '非法MATLAB入口函数：%s。', entryPoint);
end
request = jsondecode(fileread(char(requestFile)));
argumentCount = double(request.argumentCount);
arguments = cell(1, argumentCount);
for i = 1:argumentCount
    field = sprintf('arg%d', i);
    if ~isfield(request, field)
        error('DMG:Workflow:MissingArgument', '工作流请求缺少参数：%s。', field);
    end
    arguments{i} = request.(field);
end
startedAt = datestr(now, 31);
% 预加载 GTESS.dll：MATLAB R2019b 的 SetDefaultDllDirectories 限制了 DLL 搜索路径，
% loadlibrary 无法通过 PATH 找到 DLL 依赖。先用 Java System.load() 以绝对路径加载
% GTESS.dll，使其进入进程地址空间，后续 loadlibrary("GTESS.dll") 即可直接命中。
local_preload_gtess_dll();
try
    result = feval(entryPoint, arguments{:});
    save(char(resultFile), 'result', '-v7.3');
    manifest = struct('status', 'SUCCEEDED', 'entryPoint', entryPoint, ...
        'startedAt', startedAt, 'completedAt', datestr(now, 31), ...
        'resultFile', char(resultFile));
    scalarFields = {'passed','performed','status','message','truthWasRead', ...
        'testDataUsedForInference','runId','runtime_s'};
    for i = 1:numel(scalarFields)
        name = scalarFields{i};
        if isstruct(result) && isfield(result, name)
            value = result.(name);
            if ischar(value) || (isstring(value) && isscalar(value)) || ...
                    (isnumeric(value) && isscalar(value)) || ...
                    (islogical(value) && isscalar(value))
                manifest.(name) = value;
            end
        end
    end
    manifest.resultSummary = local_summarize(result, 0);
    local_write_json(char(manifestFile), manifest);
catch exception
    stack = arrayfun(@(item) struct('name', item.name, 'line', item.line), ...
        exception.stack, 'UniformOutput', false);
    manifest = struct('status', 'FAILED', 'entryPoint', entryPoint, ...
        'startedAt', startedAt, 'completedAt', datestr(now, 31), ...
        'identifier', exception.identifier, 'message', exception.message, ...
        'stack', {stack});
    local_write_json(char(manifestFile), manifest);
    rethrow(exception);
end
end

function summary = local_summarize(value, depth)
if depth >= 4
    summary = struct('kind', class(value), 'size', size(value));
elseif istable(value)
    rowCount = min(height(value), 200);
    summary = struct('kind', 'table', 'columns', {value.Properties.VariableNames}, ...
        'rowCount', height(value), 'rows', {table2struct(value(1:rowCount, :))});
elseif isstruct(value)
    if ~isscalar(value)
        count = min(numel(value), 100);
        summary = arrayfun(@(item) local_summarize(item, depth + 1), ...
            value(1:count), 'UniformOutput', false);
    else
        summary = struct();
        names = fieldnames(value);
        for i = 1:min(numel(names), 100)
            name = names{i};
            try
                summary.(name) = local_summarize(value.(name), depth + 1);
            catch
                summary.(name) = struct('kind', class(value.(name)), ...
                    'size', size(value.(name)));
            end
        end
    end
elseif iscell(value)
    count = min(numel(value), 100);
    summary = cell(size(value(1:count)));
    for i = 1:count
        summary{i} = local_summarize(value{i}, depth + 1);
    end
elseif isnumeric(value) || islogical(value)
    if numel(value) <= 1000
        summary = value;
    else
        finite = value(isfinite(value));
        summary = struct('kind', class(value), 'size', size(value), ...
            'minimum', local_optional_stat(finite, @min), ...
            'maximum', local_optional_stat(finite, @max));
    end
elseif ischar(value)
    summary = value;
elseif isstring(value)
    summary = cellstr(value);
else
    summary = struct('kind', class(value), 'size', size(value));
end
end

function value = local_optional_stat(data, operation)
if isempty(data)
    value = [];
else
    value = operation(data(:));
end
end

function local_preload_gtess_dll()
%LOCAL_PRELOAD_GTESS_DLL 用 Java System.load 预加载 GTESS.dll 及其依赖。
% MATLAB R2019b 的 loadlibrary 受 SetDefaultDllDirectories 限制，
% 无法通过 PATH 搜索 DLL 依赖（如 VCRUNTIME140.dll）。
% 先用 java.lang.System.load() 以绝对路径加载 GTESS.dll 依赖的 runtime，
% 再加载 GTESS.dll 本体，使其进入进程地址空间，
% 后续 loadlibrary("GTESS.dll") 直接命中已加载模块，不再触发搜索。
try
    candidates = { ...
        fullfile(pwd, 'GTESS.dll'), ...
        fullfile(pwd, 'MiddleData', 'control_model_runtime', 'mode1', 'GTESS.dll')};
    dllPath = '';
    for i = 1:numel(candidates)
        if isfile(candidates{i})
            dllPath = candidates{i};
            break;
        end
    end
    if isempty(dllPath)
        return;  % 当前工作目录没有 GTESS.dll，跳过预加载
    end
    % 先加载 GTESS.dll 依赖的 VC runtime（从 MATLAB bin 目录或 System32）
    matlabRoot = fullfile(matlabroot, 'bin', 'win64');
    vcrPath = fullfile(matlabRoot, 'vcruntime140.dll');
    if isfile(vcrPath)
        try java.lang.System.load(vcrPath); catch, end
    end
    msvcpPath = fullfile(matlabRoot, 'msvcp140.dll');
    if isfile(msvcpPath)
        try java.lang.System.load(msvcpPath); catch, end
    end
    % 加载 GTESS.dll 本体
    java.lang.System.load(dllPath);
catch
    % 预加载失败不中断流程，让后续 loadlibrary 报出原始错误
end
end

function local_write_json(path, value)
[fileId, message] = fopen(path, 'w', 'n', 'UTF-8');
if fileId < 0
    error('DMG:Workflow:ManifestWriteFailed', '无法写入工作流清单：%s。', message);
end
cleanup = onCleanup(@() fclose(fileId));
count = fprintf(fileId, '%s', jsonencode(value));
if count <= 0
    error('DMG:Workflow:ManifestWriteFailed', '工作流清单写入失败：%s。', path);
end
end
