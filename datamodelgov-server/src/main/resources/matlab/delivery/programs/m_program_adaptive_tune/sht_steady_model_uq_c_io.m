function varargout = sht_steady_model_uq_c_io(action, varargin)
%SHT_STEADY_MODEL_UQ_C_IO 方法C稳态UQ的独立结果与清单管理。
%
% 中间数据和报告分别写入：
%   MiddleData/steady_model_uq_method_c/<runId>
%   ../report_outputs/steady_model_uq_method_c/<runId>
% 持久化时复用方法A已验证的@project相对路径编码，但不允许
% 方法C清单越过自己的命名空间继续写入。

% 仅显式新任务使用独立IO；历史清单继续经过下方原保护逻辑。
externalArgs=varargin;
if strcmpi(action,'assertcachefile') && numel(varargin)>1,externalArgs=varargin(2);end
if sht_tc24_uq_external_io('c','selected',externalArgs{:})
    [varargout{1:nargout}]=sht_tc24_uq_external_io('c',action,varargin{:});return;
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
        local_assert_writable(manifest);
        varargout{1} = manifest;
    case 'savestep'
        [varargout{1:nargout}] = local_save_step(varargin{:});
    case 'loadstep'
        varargout{1} = local_load_step(varargin{:});
    case 'savemanifest'
        local_save_manifest(varargin{:});
    case 'reportfile'
        varargout{1} = local_output_file(varargin{1}, varargin{2}, true);
    case 'runfile'
        varargout{1} = local_output_file(varargin{1}, varargin{2}, false);
    case 'writetext'
        local_write_text(varargin{:});
    otherwise
        error('SHT:SteadyUQC:UnknownIoAction', ...
            '未知方法C IO动作：%s。', action);
end
end

function paths = local_roots()
programRoot = fileparts(mfilename('fullpath'));
projectRoot = fileparts(programRoot);
paths = struct();
paths.programRoot = programRoot;
paths.projectRoot = projectRoot;
paths.middleRoot = fullfile(programRoot, 'MiddleData', ...
    'steady_model_uq_method_c');
paths.reportRoot = fullfile(projectRoot, 'report_outputs', ...
    'steady_model_uq_method_c');
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
runId = local_option(userCfg, 'runId', ...
    ['steady_uq_c_' datestr(now, 'yyyymmdd_HHMMSS')]);
runId = char(runId);
local_validate_run_id(runId);
runDir = fullfile(paths.middleRoot, runId);
reportDir = fullfile(paths.reportRoot, runId);
local_assert_within(runDir, paths.middleRoot, '运行目录');
local_assert_within(reportDir, paths.reportRoot, '报告目录');
if exist(runDir, 'dir') == 7
    error('SHT:SteadyUQC:RunExists', '方法C运行目录已存在：%s。', runDir);
end
local_mkdir(runDir);
local_mkdir(reportDir);
manifest = struct( ...
    'schemaVersion', 'steady_model_uq_method_c_v1', ...
    'pathSchemaVersion', 'worktree_relative_v1', ...
    'runId', runId, 'createdAt', datestr(now, 30), ...
    'updatedAt', datestr(now, 30), 'programRoot', paths.programRoot, ...
    'runDir', runDir, 'reportDir', reportDir, 'status', 'created', ...
    'completedStep', 0, 'stepFiles', {cell(6, 1)}, ...
    'stepNames', {cell(6, 1)}, 'stepRuntime_s', nan(6, 1), ...
    'randomSeed', local_option(userCfg, 'randomSeed', 20260902), ...
    'route', local_option(userCfg,'route','steady'), 'legacyReadOnly', false);
local_save_manifest(manifest);
end

function manifest = local_resolve(userCfg)
if nargin < 1 || isempty(userCfg), userCfg = struct(); end
paths = local_paths();
runId = char(local_option(userCfg, 'runId', ''));
if isempty(runId)
    file = paths.latestFile;
else
    local_validate_run_id(runId);
    file = fullfile(paths.middleRoot, runId, 'manifest.mat');
end
if exist(file, 'file') ~= 2
    error('SHT:SteadyUQC:ManifestMissing', ...
        '未找到方法C运行清单：%s。', file);
end
saved = load(file, 'manifest');
if ~isfield(saved, 'manifest') || ~isstruct(saved.manifest)
    error('SHT:SteadyUQC:BadManifest', '方法C清单结构不完整：%s。', file);
end
manifest = local_prepare_manifest(saved.manifest);
if ~isempty(runId) && ~strcmp(runId, manifest.runId)
    error('SHT:SteadyUQC:RunIdMismatch', ...
        '请求的runId与清单记录不一致。');
end
end

function [manifest, file] = local_save_step( ...
        manifest, step, name, payload, runtime_s)
if step < 1 || step > 6 || step ~= floor(step)
    error('SHT:SteadyUQC:BadStep', '方法C步骤号必须为1至6的整数。');
end
if nargin < 5 || isempty(runtime_s), runtime_s = NaN; end
manifest = local_prepare_manifest(manifest);
local_assert_writable(manifest);
safeName = regexprep(char(name), '[^A-Za-z0-9_]', '_');
if isempty(safeName)
    error('SHT:SteadyUQC:BadStepName', '方法C步骤名清理后为空。');
end
file = fullfile(manifest.runDir, ...
    sprintf('step%02d_%s.mat', step, safeName));
local_assert_within(file, manifest.runDir, '步骤文件');
payload = sht_steady_model_uq_io('encodepaths', ...
    sht_steady_model_uq_io('decodepaths', payload));
save(file, 'payload', '-v7.3');
manifest.stepFiles{step} = file;
manifest.stepNames{step} = char(name);
manifest.stepRuntime_s(step) = runtime_s;
manifest.completedStep = max(manifest.completedStep, step);
manifest.updatedAt = datestr(now, 30);
manifest.status = sprintf('step_%02d_complete', step);
if step == 6, manifest.status = 'complete'; end
local_save_manifest(manifest);
end

function payload = local_load_step(manifest, step)
manifest = local_prepare_manifest(manifest);
if step < 1 || step > numel(manifest.stepFiles) || ...
        isempty(manifest.stepFiles{step})
    error('SHT:SteadyUQC:StepMissing', ...
        '运行%s尚无步骤%d产物。', manifest.runId, step);
end
file = manifest.stepFiles{step};
local_assert_within(file, manifest.runDir, '步骤文件');
if exist(file, 'file') ~= 2
    error('SHT:SteadyUQC:StepFileMissing', '方法C步骤文件不存在：%s。', file);
end
saved = load(file, 'payload');
payload = sht_steady_model_uq_io('decodepaths', saved.payload);
end

function local_save_manifest(manifest)
manifest = local_prepare_manifest(manifest);
local_assert_writable(manifest);
runtimeManifest = manifest;
if isfield(runtimeManifest, 'legacyReadOnly')
    runtimeManifest = rmfield(runtimeManifest, 'legacyReadOnly');
end
manifest = sht_steady_model_uq_io('encodepaths', runtimeManifest);
save(fullfile(runtimeManifest.runDir, 'manifest.mat'), 'manifest');
paths = local_paths();
if startsWith(runtimeManifest.runId,'tc24_')
    save(fullfile(paths.middleRoot,'tc24_latest_manifest.mat'),'manifest');
else
    save(paths.latestFile, 'manifest');
end
end

function file = local_output_file(manifest, name, isReport)
manifest = local_prepare_manifest(manifest);
local_assert_writable(manifest);
name = local_safe_leaf_name(name);
if isReport
    folder = manifest.reportDir;
else
    folder = manifest.runDir;
end
local_mkdir(folder);
file = fullfile(folder, name);
local_assert_within(file, folder, '输出文件');
end

function local_write_text(file, content)
file = char(sht_steady_model_uq_io('decodepaths', file));
paths = local_roots();
local_assert_within(file, paths.projectRoot, '文本输出');
[folder, ~, ~] = fileparts(file);
local_mkdir(folder);
fid = fopen(file, 'w', 'n', 'UTF-8');
if fid < 0
    error('SHT:SteadyUQC:TextOpenFailed', '无法写入文本：%s。', file);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s', char(content));
end

function manifest = local_prepare_manifest(manifest)
if ~isstruct(manifest) || ~isscalar(manifest) || ...
        ~isfield(manifest, 'runId') || ~isfield(manifest, 'schemaVersion')
    error('SHT:SteadyUQC:BadManifest', '方法C清单缺少基本字段。');
end
if ~strcmp(char(manifest.schemaVersion), 'steady_model_uq_method_c_v1')
    error('SHT:SteadyUQC:ManifestSchemaMismatch', ...
        '清单不属于方法C，禁止跨方法解释。');
end
portable = isfield(manifest, 'pathSchemaVersion') && ...
    strcmp(char(manifest.pathSchemaVersion), 'worktree_relative_v1');
manifest = sht_steady_model_uq_io('decodepaths', manifest);
manifest.runId = char(manifest.runId);
local_validate_run_id(manifest.runId);
paths = local_roots();
manifest.programRoot = paths.programRoot;
manifest.runDir = fullfile(paths.middleRoot, manifest.runId);
manifest.reportDir = fullfile(paths.reportRoot, manifest.runId);
if ~isfield(manifest, 'stepFiles') || isempty(manifest.stepFiles)
    manifest.stepFiles = cell(6, 1);
end
if numel(manifest.stepFiles) < 6
    manifest.stepFiles(end + 1:6) = {[]};
end
for i = 1:numel(manifest.stepFiles)
    if isempty(manifest.stepFiles{i}), continue; end
    [~, base, ext] = fileparts(char(manifest.stepFiles{i}));
    manifest.stepFiles{i} = fullfile(manifest.runDir, [base ext]);
end
manifest.legacyReadOnly = ~portable;
local_assert_within(manifest.runDir, paths.middleRoot, '运行目录');
local_assert_within(manifest.reportDir, paths.reportRoot, '报告目录');
end

function local_assert_writable(manifest)
if ~isfield(manifest, 'pathSchemaVersion') || ...
        ~strcmp(char(manifest.pathSchemaVersion), 'worktree_relative_v1') || ...
        (isfield(manifest, 'legacyReadOnly') && manifest.legacyReadOnly)
    error('SHT:SteadyUQC:LegacyManifestReadOnly', ...
        '旧绝对路径清单只允许读取，禁止继续写入。');
end
paths = local_roots();
local_assert_same(manifest.runDir, fullfile(paths.middleRoot, manifest.runId));
local_assert_same(manifest.reportDir, fullfile(paths.reportRoot, manifest.runId));
for i = 1:numel(manifest.stepFiles)
    if ~isempty(manifest.stepFiles{i})
        local_assert_within(manifest.stepFiles{i}, manifest.runDir, '步骤文件');
    end
end
end

function local_validate_run_id(runId)
if isempty(regexp(runId, '^[A-Za-z0-9][A-Za-z0-9_-]*$', 'once'))
    error('SHT:SteadyUQC:BadRunId', ...
        'runId只允许字母、数字、下划线和连字符：%s。', runId);
end
end

function name = local_safe_leaf_name(name)
name = char(name);
[folder, base, ext] = fileparts(name);
if isempty(name) || ~isempty(folder) || ~strcmp(name, [base ext]) || ...
        any(name == '/') || any(name == '\') || ismember(name, {'.', '..'})
    error('SHT:SteadyUQC:BadOutputName', '输出必须为单一文件名：%s。', name);
end
end

function local_mkdir(folder)
paths = local_roots();
local_assert_within(folder, paths.projectRoot, '目录');
if exist(folder, 'dir') ~= 7
    [ok, message] = mkdir(folder);
    if ~ok
        error('SHT:SteadyUQC:MkdirFailed', '无法创建目录%s：%s。', folder, message);
    end
end
end

function local_assert_same(first, second)
if ~strcmpi(local_canonical(first), local_canonical(second))
    error('SHT:SteadyUQC:ManifestWriteBoundary', ...
        '方法C清单写目录与当前命名空间不一致。');
end
end

function local_assert_within(candidate, root, label)
candidate = local_canonical(candidate);
root = local_canonical(root);
prefix = [root filesep];
if ~strcmpi(candidate, root) && ...
        ~(numel(candidate) > numel(prefix) && ...
        strncmpi(candidate, prefix, numel(prefix)))
    error('SHT:SteadyUQC:WriteBoundary', ...
        '%s越过方法C允许边界：%s。', label, candidate);
end
end

function value = local_canonical(value)
value = char(sht_steady_model_uq_io('decodepaths', char(value)));
value = char(java.io.File(value).getCanonicalPath());
end

function value = local_option(options, name, defaultValue)
if isstruct(options) && isfield(options, name) && ~isempty(options.(name))
    value = options.(name);
else
    value = defaultValue;
end
end
