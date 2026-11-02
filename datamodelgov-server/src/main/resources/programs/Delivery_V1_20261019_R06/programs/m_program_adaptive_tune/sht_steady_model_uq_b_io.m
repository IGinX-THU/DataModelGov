function varargout = sht_steady_model_uq_b_io(action, varargin)
%SHT_STEADY_MODEL_UQ_B_IO 方法B的独立运行清单和结果目录管理。
%
% 方法B所有中间量写入MiddleData/steady_model_uq_method_b，图表和文本
% 写入外层report_outputs/steady_model_uq_method_b。新清单使用可重定位的
% @project路径引用；旧绝对路径清单只能在当前Worktree兼容读取，禁止续写。

% 仅显式新任务使用独立IO；历史清单继续经过下方原保护逻辑。
externalArgs=varargin;
if strcmpi(action,'assertcachefile') && numel(varargin)>1,externalArgs=varargin(2);end
if sht_tc24_uq_external_io('b','selected',externalArgs{:})
    [varargout{1:nargout}]=sht_tc24_uq_external_io('b',action,varargin{:});return;
end
switch lower(char(action))
    case 'paths'
        varargout{1} = local_paths();
    case 'createrun'
        varargout{1} = local_create_run(varargin{:});
    case 'resolve'
        varargout{1} = local_resolve(varargin{:});
    case 'resolvewritable'
        manifest = local_resolve(varargin{:});
        local_assert_writable_manifest(manifest);
        varargout{1} = manifest;
    case 'assertwritable'
        manifest = local_prepare_manifest(varargin{1});
        local_assert_writable_manifest(manifest);
        if nargout > 0, varargout{1} = manifest; end
    case 'savestep'
        [varargout{1:nargout}] = local_save_step(varargin{:});
    case 'loadstep'
        varargout{1} = local_load_step(varargin{:});
    case 'savemanifest'
        local_save_manifest(varargin{:});
    case 'reportfile'
        varargout{1} = local_report_file(varargin{:});
    case 'runfile'
        varargout{1} = local_run_file(varargin{:});
    case 'writetext'
        local_write_text(varargin{:});
    case 'encodepaths'
        varargout{1} = sht_steady_model_uq_io('encodepaths', varargin{1});
    case 'decodepaths'
        varargout{1} = sht_steady_model_uq_io('decodepaths', varargin{1});
    case 'assertcachefile'
        local_assert_cache_file(varargin{1});
    otherwise
        error('SHT:SteadyUQB:UnknownIoAction', ...
            '未知方法B UQ IO动作：%s。', action);
end
end

function paths = local_roots()
programRoot = fileparts(mfilename('fullpath'));
projectRoot = fileparts(programRoot);
paths = struct();
paths.programRoot = programRoot;
paths.projectRoot = projectRoot;
paths.middleRoot = fullfile(programRoot, 'MiddleData', ...
    'steady_model_uq_method_b');
paths.reportRoot = fullfile(projectRoot, 'report_outputs', ...
    'steady_model_uq_method_b');
paths.latestFile = fullfile(paths.middleRoot, 'latest_manifest.mat');
end

function paths = local_paths()
paths = local_roots();
local_mkdir(paths.middleRoot);
local_mkdir(paths.reportRoot);
end

function manifest = local_create_run(userCfg)
if nargin < 1 || isempty(userCfg), userCfg = struct(); end
paths = local_paths();
if isfield(userCfg, 'runId') && ~isempty(userCfg.runId)
    runId = char(userCfg.runId);
else
    runId = ['steady_uq_b_' datestr(now, 'yyyymmdd_HHMMSS')];
end
local_validate_run_id(runId);
runDir = fullfile(paths.middleRoot, runId);
reportDir = fullfile(paths.reportRoot, runId);
local_assert_project_path(runDir);
local_assert_project_path(reportDir);
if exist(runDir, 'dir') == 7
    error('SHT:SteadyUQB:RunExists', '方法B运行目录已存在：%s。', runDir);
end
local_mkdir(runDir);
local_mkdir(reportDir);

manifest = struct();
manifest.schemaVersion = 'steady_model_uq_method_b_v1';
manifest.pathSchemaVersion = 'worktree_relative_v1';
manifest.runId = runId;
manifest.createdAt = datestr(now, 30);
manifest.updatedAt = manifest.createdAt;
manifest.programRoot = paths.programRoot;
manifest.runDir = runDir;
manifest.reportDir = reportDir;
manifest.status = 'created';
manifest.completedStep = 0;
manifest.stepFiles = cell(10, 1);
manifest.stepNames = cell(10, 1);
manifest.stepRuntime_s = nan(10, 1);
manifest.randomSeed = local_option(userCfg, 'randomSeed', 20260822);
manifest.route = char(local_option(userCfg, 'route', 'transient_instant'));
manifest.legacyReadOnly = false;
local_save_manifest(manifest);
end

function manifest = local_resolve(userCfg)
if nargin < 1 || isempty(userCfg), userCfg = struct(); end
paths = local_paths();
requestedRunId = '';
if isfield(userCfg, 'runId') && ~isempty(userCfg.runId)
    requestedRunId = char(userCfg.runId);
    local_validate_run_id(requestedRunId);
    file = fullfile(paths.middleRoot, requestedRunId, 'manifest.mat');
else
    requestedRoute = char(local_option(userCfg, 'route', ''));
    routeFile = '';
    if ismember(requestedRoute, {'steady','transient_instant'})
        routeFile = fullfile(paths.middleRoot, ...
            ['latest_manifest_' requestedRoute '.mat']);
    end
    if ~isempty(routeFile) && exist(routeFile, 'file') == 2
        file = routeFile;
    else
        file = paths.latestFile;
    end
end
if exist(file, 'file') ~= 2
    error('SHT:SteadyUQB:ManifestMissing', ...
        '未找到方法B运行清单：%s。请先运行B01或总入口。', file);
end
s = load(file, 'manifest');
if ~isfield(s, 'manifest') || ~isstruct(s.manifest)
    error('SHT:SteadyUQB:BadManifest', '方法B清单缺少manifest结构：%s。', file);
end
manifest = local_prepare_manifest(s.manifest);
if ~isempty(requestedRunId) && ~strcmp(manifest.runId, requestedRunId)
    error('SHT:SteadyUQB:ManifestRunIdMismatch', ...
        '目录请求runId=%s，但清单记录runId=%s。', ...
        requestedRunId, manifest.runId);
end
end

function [manifest, file] = local_save_step( ...
        manifest, step, name, payload, runtime_s)
if step < 1 || step > 10 || step ~= floor(step)
    error('SHT:SteadyUQB:BadStep', '步骤号必须为1至10的整数。');
end
if nargin < 5 || isempty(runtime_s), runtime_s = NaN; end
manifest = local_prepare_manifest(manifest);
local_assert_writable_manifest(manifest);
safeName = regexprep(char(name), '[^A-Za-z0-9_]', '_');
if isempty(safeName)
    error('SHT:SteadyUQB:BadStepName', '方法B步骤名称清理后为空。');
end
file = fullfile(manifest.runDir, ...
    sprintf('step%02d_%s.mat', step, safeName));
local_assert_project_path(file);
runtimePayload = sht_steady_model_uq_io('decodepaths', payload);
payload = sht_steady_model_uq_io('encodepaths', runtimePayload); %#ok<NASGU>
save(file, 'payload', '-v7.3');
manifest.stepFiles{step} = file;
manifest.stepNames{step} = char(name);
manifest.stepRuntime_s(step) = runtime_s;
manifest.completedStep = max(manifest.completedStep, step);
manifest.updatedAt = datestr(now, 30);
manifest.status = sprintf('step_%02d_complete', step);
if step == 10, manifest.status = 'complete'; end
local_save_manifest(manifest);
end

function payload = local_load_step(manifest, step)
manifest = local_prepare_manifest(manifest);
if step < 1 || step > numel(manifest.stepFiles) || ...
        isempty(manifest.stepFiles{step})
    error('SHT:SteadyUQB:StepMissing', ...
        '方法B运行%s尚无步骤%d产物。', manifest.runId, step);
end
file = manifest.stepFiles{step};
local_assert_project_path(file);
if exist(file, 'file') ~= 2
    error('SHT:SteadyUQB:StepFileMissing', '步骤文件不存在：%s。', file);
end
s = load(file, 'payload');
if ~isfield(s, 'payload')
    error('SHT:SteadyUQB:BadStepFile', '步骤文件缺少payload：%s。', file);
end
payload = sht_steady_model_uq_io('decodepaths', s.payload);
end

function local_save_manifest(manifest)
manifest = local_prepare_manifest(manifest);
local_assert_writable_manifest(manifest);
local_mkdir(manifest.runDir);
runtimeManifest = manifest;
if isfield(runtimeManifest, 'legacyReadOnly')
    runtimeManifest = rmfield(runtimeManifest, 'legacyReadOnly');
end
manifest = sht_steady_model_uq_io('encodepaths', runtimeManifest); %#ok<NASGU>
file = fullfile(runtimeManifest.runDir, 'manifest.mat');
local_assert_project_path(file);
save(file, 'manifest');
paths = local_paths();
if startsWith(runtimeManifest.runId,'tc24_')
    save(fullfile(paths.middleRoot,'tc24_latest_manifest.mat'),'manifest');
    return; % 三部件运行不得覆盖六部件默认续跑指针。
end
save(paths.latestFile, 'manifest');
if isfield(runtimeManifest, 'route') && ...
        ismember(char(runtimeManifest.route), {'steady','transient_instant'})
    routeLatestFile = fullfile(paths.middleRoot, ...
        ['latest_manifest_' char(runtimeManifest.route) '.mat']);
    save(routeLatestFile, 'manifest');
end
end

function file = local_report_file(manifest, name)
manifest = local_prepare_manifest(manifest);
local_assert_writable_manifest(manifest);
name = local_safe_leaf_name(name, '报告文件名');
local_mkdir(manifest.reportDir);
file = fullfile(manifest.reportDir, name);
local_assert_project_path(file);
end

function file = local_run_file(manifest, name)
manifest = local_prepare_manifest(manifest);
local_assert_writable_manifest(manifest);
name = local_safe_leaf_name(name, '运行文件名');
local_mkdir(manifest.runDir);
file = fullfile(manifest.runDir, name);
local_assert_project_path(file);
end

function local_write_text(file, content)
file = sht_steady_model_uq_io('decodepaths', char(file));
local_assert_project_path(file);
[folder, ~, ~] = fileparts(file);
local_mkdir(folder);
fid = fopen(file, 'w', 'n', 'UTF-8');
if fid < 0
    error('SHT:SteadyUQB:TextOpenFailed', '无法写入文本文件：%s。', file);
end
cleanupObject = onCleanup(@() fclose(fid));
fprintf(fid, '%s', char(content));
clear cleanupObject;
end

function manifest = local_prepare_manifest(manifest)
if ~isstruct(manifest) || ~isscalar(manifest) || ~isfield(manifest, 'runId')
    error('SHT:SteadyUQB:BadManifest', '方法B运行清单必须包含runId。');
end
if ~isfield(manifest, 'schemaVersion') || ...
        ~strcmp(char(manifest.schemaVersion), 'steady_model_uq_method_b_v1')
    error('SHT:SteadyUQB:ManifestSchemaMismatch', ...
        '清单不是方法B的steady_model_uq_method_b_v1清单，禁止跨方法解释。');
end
if isfield(manifest, 'pathSchemaVersion') && ...
        ~strcmp(char(manifest.pathSchemaVersion), 'worktree_relative_v1')
    error('SHT:SteadyUQB:UnsupportedPathSchema', ...
        '不支持方法B路径清单版本：%s。', char(manifest.pathSchemaVersion));
end
isPortable = isfield(manifest, 'pathSchemaVersion') && ...
    strcmp(char(manifest.pathSchemaVersion), 'worktree_relative_v1');
manifest = sht_steady_model_uq_io('decodepaths', manifest);
manifest.runId = char(manifest.runId);
local_validate_run_id(manifest.runId);
paths = local_paths();
manifest.programRoot = paths.programRoot;
manifest.runDir = fullfile(paths.middleRoot, manifest.runId);
manifest.reportDir = fullfile(paths.reportRoot, manifest.runId);
if ~isfield(manifest, 'stepFiles') || isempty(manifest.stepFiles)
    manifest.stepFiles = cell(10, 1);
elseif ~iscell(manifest.stepFiles)
    manifest.stepFiles = cellstr(manifest.stepFiles);
end
for i = 1:numel(manifest.stepFiles)
    if isempty(manifest.stepFiles{i})
        continue;
    end
    [~, baseName, extension] = fileparts(char(manifest.stepFiles{i}));
    manifest.stepFiles{i} = fullfile(manifest.runDir, [baseName extension]);
end
manifest.legacyReadOnly = ~isPortable;
local_assert_project_path(manifest.runDir);
local_assert_project_path(manifest.reportDir);
end

function local_assert_writable_manifest(manifest)
if ~isfield(manifest, 'pathSchemaVersion') || ...
        ~strcmp(char(manifest.pathSchemaVersion), 'worktree_relative_v1') || ...
        (isfield(manifest, 'legacyReadOnly') && manifest.legacyReadOnly)
    error('SHT:SteadyUQB:LegacyManifestReadOnly', ...
        '旧绝对路径方法B清单%s仅允许兼容读取，禁止继续写入。', ...
        manifest.runId);
end
paths = local_paths();
expectedRunDir = fullfile(paths.middleRoot, manifest.runId);
expectedReportDir = fullfile(paths.reportRoot, manifest.runId);
if ~local_same_path(manifest.runDir, expectedRunDir) || ...
        ~local_same_path(manifest.reportDir, expectedReportDir)
    error('SHT:SteadyUQB:ManifestWriteBoundary', ...
        '方法B运行%s的写目录没有落在当前Worktree固定命名空间。', ...
        manifest.runId);
end
for i = 1:numel(manifest.stepFiles)
    if ~isempty(manifest.stepFiles{i}) && ...
            ~local_is_within(manifest.stepFiles{i}, manifest.runDir)
        error('SHT:SteadyUQB:StepWriteBoundary', ...
            '方法B步骤%d文件越过当前运行目录：%s。', ...
            i, manifest.stepFiles{i});
    end
end
end

function local_validate_run_id(runId)
if isempty(regexp(runId, '^[A-Za-z0-9][A-Za-z0-9_-]*$', 'once'))
    error('SHT:SteadyUQB:BadRunId', ...
        'runId只允许字母、数字、下划线和连字符，且必须以字母或数字开头：%s。', ...
        runId);
end
end

function name = local_safe_leaf_name(name, label)
name = char(name);
[folder, baseName, extension] = fileparts(name);
if isempty(name) || ~isempty(folder) || ~strcmp(name, [baseName extension]) || ...
        any(name == '/') || any(name == '\') || ismember(name, {'.', '..'})
    error('SHT:SteadyUQB:BadOutputName', ...
        '%s必须是不含目录的单一文件名：%s。', label, name);
end
end

function local_mkdir(folder)
local_assert_project_path(folder);
if exist(folder, 'dir') ~= 7
    [ok, message] = mkdir(folder);
    if ~ok
        error('SHT:SteadyUQB:MkdirFailed', ...
            '无法创建目录%s：%s。', folder, message);
    end
end
end

function local_assert_project_path(pathValue)
sht_steady_model_uq_io('assertprojectpath', pathValue);
end

function local_assert_cache_file(pathValue)
% 方法B缓存与方法A物理隔离，防止配置覆盖把缓存写到项目内其他位置。
pathValue = sht_steady_model_uq_io('decodepaths', char(pathValue));
local_assert_project_path(pathValue);
paths = local_roots();
if ~local_is_within(pathValue, paths.middleRoot)
    error('SHT:SteadyUQB:CacheWriteBoundary', ...
        '方法B缓存越过专属MiddleData根：%s。', pathValue);
end
[~, baseName, extension] = fileparts(pathValue);
name = [baseName extension];
if isempty(regexp(name, ...
        ['^exact_(?:(?:training|test)|output_(?:steady|transient_instant)|' ...
        'output_(?:training|test)_(?:steady|transient_instant))_' ...
        'cache_[0-9A-Fa-f]{16,64}\.mat$'], 'once'))
    error('SHT:SteadyUQB:BadCacheFileName', ...
        '方法B缓存文件名不符合合同绑定规则：%s。', name);
end
end

function tf = local_is_within(pathValue, root)
pathValue = local_canonical_path(char(pathValue));
root = local_canonical_path(char(root));
tf = strcmpi(pathValue, root) || startsWith(lower(pathValue), ...
    [lower(root) lower(filesep)]);
end

function tf = local_same_path(first, second)
tf = strcmpi(local_canonical_path(char(first)), ...
    local_canonical_path(char(second)));
end

function pathValue = local_canonical_path(pathValue)
pathValue = char(java.io.File(char(pathValue)).getCanonicalPath());
end

function value = local_option(options, name, defaultValue)
if isstruct(options) && isfield(options, name) && ~isempty(options.(name))
    value = options.(name);
else
    value = defaultValue;
end
end
