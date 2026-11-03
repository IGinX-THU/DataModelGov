function runtime = sht_prepare_control_model_runtime(sourceDir)
%SHT_PREPARE_CONTROL_MODEL_RUNTIME 只读核验六部件运行配置及其依赖。
% 用户手工写入并复核的模式2 MDL是唯一运行依据。不得用历史设计MAT
% 重新赋值，也不自动生成/覆盖另一份MDL。需要更改MDL时先向用户申请。
% 设计模式0仍由V2入口使用；普通仿真遇到模式0应提示用户完成配置。
if nargin < 1 || isempty(sourceDir)
    sourceDir = fileparts(mfilename('fullpath'));
end
sourceDir = char(sourceDir);
sourceModel = fullfile(sourceDir, 'Turboshaft-TS-Split.mdl');
assert(isfile(sourceModel), '缺少六部件配置：%s', sourceModel);
modelText = fileread(sourceModel);
modeToken = regexp(modelText, ...
    '(?m)^\s*offDesignMode\s*=\s*([0-9]+)', 'tokens');
assert(numel(modeToken) == 1 && str2double(modeToken{1}{1}) == 2, ...
    'SHT:ControlRuntime:ManualMdlRequired', ...
    ['普通仿真需要用户确认的offDesignMode=2配置：%s。' ...
     '请用V2求解并手工写入、复核；程序不会自动改写MDL。'], sourceModel);

tokens = regexp(modelText, ...
    '(?m)^[ \t]*mapPath[ \t]*=[ \t]*([^\r\n]+?)[ \t]*$', 'tokens');
assert(numel(tokens) == 6, '六部件配置应有六个mapPath字段。');
mapFiles = cellfun(@(t) strtrim(t{1}), tokens, 'UniformOutput', false);
mapFiles = unique(mapFiles, 'stable');
dependencies = [{'GTESS.dll', 'GTESS.h', 'blockAndFunctions.h', ...
    'types_TMATS.H'}, mapFiles];
for i = 1:numel(dependencies)
    path = fullfile(sourceDir, dependencies{i});
    assert(isfile(path), '缺少六部件运行依赖：%s', path);
end

% 直接从权威目录加载，避免旧运行副本或旧设计状态抵消手工配置。
% 已有MiddleData/control_model_runtime只保留作历史证据，不再自动同步。
runtime = struct('modelMode', 1, 'controlDir', sourceDir, ...
    'modelFile', sourceModel, 'sourceModel', sourceModel, ...
    'designStateFile', '', 'mapFiles', {mapFiles(:)}, ...
    'generatedAt', datestr(now, 31), 'designStateGeneratedAt', '', ...
    'sourcePolicy', 'user_confirmed_mode2_mdl_read_only');
end
