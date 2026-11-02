function [cfg, parameterAsset] = sht_configure_transient_visser29( ...
    cfg, stageName, assetFile, componentMask)
%SHT_CONFIGURE_TRANSIENT_VISSER29 显式启用六部件29状态Visser热网络。
%
% 本入口只负责选择Visser资产和运行阶段，标称热参数仍由Kurzke/Visser
% 共享的初始化接口提交；29个动态状态、当前epsilon_ss和个体修正量仍
% 通过stepIn逐次传递。stageName支持heat_state、heat_feedback、
% clearance_diagnostic、clearance_feedback和joint_full。

if nargin < 1 || isempty(cfg)
    userCfg = struct();
    userCfg.engine.modelMode = 1;
    cfg = sht_default_config(userCfg);
end
if ~isfield(cfg, 'engine') || ~isfield(cfg.engine, 'modelMode') || ...
        cfg.engine.modelMode ~= 1
    error('SHT:Visser29:ModelMode', ...
        'Visser 29状态模型只允许用于六部件modelMode=1。');
end
if nargin < 2 || isempty(stageName)
    stageName = 'heat_state';
end
if nargin < 3 || isempty(assetFile)
    thisDir = fileparts(mfilename('fullpath'));
    assetFile = fullfile(thisDir, 'MiddleData', ...
        'transient_effects_split_visser29_parameters.mat');
end
if nargin < 4
    componentMask = [];
end

[cfg, parameterAsset] = sht_configure_transient_heat_state(cfg, assetFile);
if ~isfield(cfg.engine.transientEffects, 'thermalModelMode') || ...
        cfg.engine.transientEffects.thermalModelMode ~= 3 || ...
        numel(cfg.engine.initial.state) ~= 29
    error('SHT:Visser29:AssetTopology', ...
        '所选资产没有形成thermalModelMode=3的29状态拓扑。');
end

stageName = lower(char(stageName));
switch stageName
    case 'heat_state'
        cfg.engine.transientEffects.stage = ...
            'Visser29_heat_state_no_feedback';
    case 'heat_feedback'
        componentMask = local_require_mask(componentMask, stageName);
        cfg.engine.transientEffects.stepInTemplate = ...
            sht_build_transient_step_in_template( ...
            parameterAsset, stageName, componentMask);
        cfg.engine.transientEffects.stage = 'Visser29_heat_feedback';
    case 'clearance_diagnostic'
        cfg.engine.transientEffects.stepInTemplate = ...
            sht_build_transient_step_in_template(parameterAsset, stageName);
        cfg.engine.transientEffects.stage = ...
            'Visser29_clearance_diagnostic';
        [referenceTable, cacheInfo] = ...
            sht_prepare_clearance_reference_lookup( ...
            parameterAsset.referenceTable);
        cfg.engine.transientEffects.clearanceReferenceTable = referenceTable;
        cfg.engine.transientEffects.clearanceReferenceCacheInfo = cacheInfo;
    case 'clearance_feedback'
        componentMask = local_require_mask(componentMask, stageName);
        cfg.engine.transientEffects.stepInTemplate = ...
            sht_build_transient_step_in_template( ...
            parameterAsset, stageName, componentMask);
        cfg.engine.transientEffects.stage = ...
            'Visser29_clearance_feedback';
        [referenceTable, cacheInfo] = ...
            sht_prepare_clearance_reference_lookup( ...
            parameterAsset.referenceTable);
        cfg.engine.transientEffects.clearanceReferenceTable = referenceTable;
        cfg.engine.transientEffects.clearanceReferenceCacheInfo = cacheInfo;
    case 'joint_full'
        [cfg, parameterAsset] = sht_configure_transient_joint(cfg, assetFile);
        cfg.engine.transientEffects.stage = 'Visser29_joint_full';
    otherwise
        error('SHT:Visser29:Stage', '不支持Visser运行阶段：%s。', stageName);
end

cfg = sht_validate_runtime_config(cfg);
end

function mask = local_require_mask(mask, stageName)
if isempty(mask) || ~isscalar(mask) || ~isfinite(mask) || ...
        mask ~= round(mask) || mask < 1 || mask > 15
    error('SHT:Visser29:ComponentMask', ...
        '%s需要1至15之间的整数componentMask。', stageName);
end
mask = round(mask);
end
