function [cfg, parameterAsset] = sht_configure_transient_heat_state(cfg, assetFile)
%SHT_CONFIGURE_TRANSIENT_HEAT_STATE 启用三部件或六部件热状态积分。
%
% 该函数是基准2维模型与三部件15维、六部件Kurzke 27维及
% 六部件Visser 29维模型之间的
% 公共配置边界：
%   1) 读取步骤 1 生成并绑定当前模型哈希的参数资产；
%   2) 构造 heat_state stepIn 模板，但保持热反馈和间隙通道关闭；
%   3) 按资产拓扑用设计参考点温度初始化13、25或27个热状态；
%   4) 校验资产与当前 DLL、头文件和模型文件完全匹配。
%
% 不调用本函数时，现有 cfg 继续使用 [Np;Ng] 两维状态和原 DLL 路径。

if nargin < 1 || isempty(cfg)
    cfg = sht_default_config();
end
thisDir = fileparts(mfilename('fullpath'));
if nargin < 2 || isempty(assetFile)
    if isfield(cfg.engine, 'modelMode') && cfg.engine.modelMode == 1
        assetFile = fullfile(thisDir, 'MiddleData', ...
            'transient_effects_split_kurzke27_parameters.mat');
    else
        assetFile = fullfile(thisDir, 'MiddleData', ...
            'transient_effects_initial_parameters.mat');
    end
end
if ~exist(assetFile, 'file')
    error('SHT:TransientHeat:MissingAsset', ...
        ['热状态参数资产不存在。三部件请运行Start_TransientEffects_01，' ...
         '六部件请运行Start_TransientEffects_06：%s'], ...
        assetFile);
end

loaded = load(assetFile, 'parameterAsset');
if ~isfield(loaded, 'parameterAsset')
    error('SHT:TransientHeat:InvalidAsset', ...
        '参数资产文件中缺少 parameterAsset：%s', assetFile);
end
parameterAsset = loaded.parameterAsset;
acceptedAssetVersions = {'2.5-P6-joint-v5', '2.5-split-kurzke27-v1', ...
    '2.5-split-visser29-v1', '2.5-split-visser29-v2', ...
    'TC27-three-kurzke15-v1','TC27-three-visser16-v1'};
if ~isfield(parameterAsset, 'assetVersion') || ...
        ~ismember(parameterAsset.assetVersion, acceptedAssetVersions)
    error('SHT:TransientHeat:AssetVersion', ...
        '当前程序不支持参数资产版本 %s。', ...
        local_text_field(parameterAsset, 'assetVersion', '<missing>'));
end
% 2502/2503 是参数资产布局版本。运行时拓扑仍只由 modelMode 决定。
expectedLayout = 2502 + double(cfg.engine.modelMode == 1);
if ~isfield(parameterAsset, 'interface') || ...
        parameterAsset.interface.interfaceVersion ~= expectedLayout
    error('SHT:TransientHeat:ModelInterfaceMismatch', ...
        'modelMode=%d要求参数布局版本=%d。', ...
        cfg.engine.modelMode, expectedLayout);
end

local_verify_model_identity(cfg, parameterAsset);
stepInTemplate = sht_build_transient_step_in_template(parameterAsset, 'heat_state');
thermalModelConfiguration = [];
thermalModelMode = 0;
if cfg.engine.modelMode == 1 || isfield(parameterAsset.interface,'nominalThermalConfigVersion')
    thermalModelConfiguration = ...
        sht_build_thermal_model_configuration(parameterAsset);
    thermalModelMode = thermalModelConfiguration.thermalModelMode;
end

cfg.engine.transientEffects = struct();
cfg.engine.transientEffects.enabled = true;
cfg.engine.transientEffects.stage = 'P3_heat_state_no_feedback';
cfg.engine.transientEffects.parameterAssetFile = assetFile;
cfg.engine.transientEffects.stepInTemplate = stepInTemplate;
cfg.engine.transientEffects.parameterLayoutVersion = expectedLayout;
cfg.engine.transientEffects.thermalModelMode = thermalModelMode;
if ~isempty(thermalModelConfiguration)
    cfg.engine.transientEffects.thermalModelConfiguration = ...
        thermalModelConfiguration;
end
if thermalModelMode == 3
    if ~isfield(parameterAsset, 'coolingSplitConfiguration') || ...
            isempty(parameterAsset.coolingSplitConfiguration)
        error('SHT:TransientHeat:MissingCoolingSplitConfiguration', ...
            'Visser 29状态资产缺少coolingSplitConfiguration。');
    end
    cfg.engine.transientEffects.coolingSplitConfiguration = ...
        parameterAsset.coolingSplitConfiguration;
end
if cfg.engine.modelMode == 1
    stateNames = { ...
        'Np', 'Ng', ...
        'T_AC_b', 'T_AC_r', 'T_AC_c', ...
        'T_CC_b', 'T_CC_r', 'T_CC_c', 'T_B_liner', ...
        'T_GT1_b', 'T_GT1_r', 'T_GT1_c', ...
        'T_GT2_b', 'T_GT2_r', 'T_GT2_c', ...
        'T_PT1_b', 'T_PT1_r', 'T_PT1_c', ...
        'T_PT2_b', 'T_PT2_r', 'T_PT2_c', ...
        'T_AC_d', 'T_CC_d', 'T_GT1_d', 'T_GT2_d', 'T_PT1_d', 'T_PT2_d'};
    if thermalModelMode == 3
        stateNames = [stateNames, {'T_GT1_guide', 'T_GT2_guide'}];
    end
    cfg.engine.stateNames = stateNames;
else
    cfg.engine.stateNames = { ...
        'Np', 'Ng', ...
        'T_HPC_b', 'T_HPC_r', 'T_HPC_c', 'T_B_liner', ...
        'T_GT_b', 'T_GT_r', 'T_GT_c', ...
        'T_PT_b', 'T_PT_r', 'T_PT_c', ...
        'T_HPC_d', 'T_GT_d', 'T_PT_d'};
    if thermalModelMode == 3
        cfg.engine.stateNames{end+1}='T_GT_guide';
    end
end
cfg.engine.initial.state = [ ...
    cfg.engine.initial.Np0; ...
    cfg.engine.initial.Ng0; ...
    parameterAsset.nominal.initialTemperatureState(:)];

% 再走统一运行配置校验，避免入口脚本绕过 512/128、开关和状态维数契约。
cfg = sht_validate_runtime_config(cfg);
end

function local_verify_model_identity(cfg, asset)
required = {'dllSHA256', 'headerSHA256', 'modelSHA256'};
for i = 1:numel(required)
    if ~isfield(asset, 'modelIdentity') || ...
            ~isfield(asset.modelIdentity, required{i})
        error('SHT:TransientHeat:MissingModelIdentity', ...
            '参数资产缺少 modelIdentity.%s。', required{i});
    end
end

controlDir = cfg.engine.interface.controlDir;
dllFile = fullfile(controlDir, [cfg.engine.interface.libraryName, '.dll']);
headerFile = fullfile(controlDir, cfg.engine.interface.headerName);
if isfield(cfg.engine, 'modelConfiguration') && ...
        ~isempty(cfg.engine.modelConfiguration)
    modelFile = cfg.engine.modelConfiguration;
elseif cfg.engine.modelMode == 1
    modelFile = fullfile(controlDir, 'Turboshaft-TS-Split.mdl');
else
    modelFile = fullfile(controlDir, 'Turboshaft-TS.mdl');
end
actual = {local_sha256(dllFile), local_sha256(headerFile), local_sha256(modelFile)};
expected = {asset.modelIdentity.dllSHA256, ...
    asset.modelIdentity.headerSHA256, asset.modelIdentity.modelSHA256};
names = {'DLL', 'header', 'model'};
for i = 1:numel(actual)
    if ~strcmpi(actual{i}, expected{i})
        error('SHT:TransientHeat:ModelIdentityMismatch', ...
            '%s SHA-256 与当前参数资产不一致，拒绝混用不同模型版本。', names{i});
    end
end
end

function hashText = local_sha256(fileName)
if ~exist(fileName, 'file')
    error('SHT:TransientHeat:MissingIdentityFile', ...
        '模型标识文件不存在：%s', fileName);
end
fid = fopen(fileName, 'rb');
if fid < 0
    error('SHT:TransientHeat:HashOpenFailed', '无法读取：%s', fileName);
end
cleanupFile = onCleanup(@() fclose(fid)); %#ok<MSNU>
bytes = fread(fid, inf, '*uint8');
digest = java.security.MessageDigest.getInstance('SHA-256');
digest.update(typecast(bytes(:), 'int8'));
hashBytes = typecast(digest.digest(), 'uint8');
hashText = upper(reshape(dec2hex(hashBytes, 2).', 1, []));
end

function value = local_text_field(s, name, defaultValue)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = char(s.(name));
else
    value = defaultValue;
end
end
