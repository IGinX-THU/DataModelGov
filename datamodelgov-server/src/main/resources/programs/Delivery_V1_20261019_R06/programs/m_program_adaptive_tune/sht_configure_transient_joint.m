function [cfg, parameterAsset] = sht_configure_transient_joint(cfg, assetFile)
%SHT_CONFIGURE_TRANSIENT_JOINT 构造三类瞬态效应联合配置。
%
% 联合配置同时启用：
%   1) 双轴惯量修正通道；
%   2) 2502的10+3或2503的19+6个热状态及热反馈；
%   3) 三个总体部件或六个拆分部件的动态间隙计算与性能反馈。
%
% 四个间隙-性能通道都使用参数资产中的固定标称交换率。health(65:68)
% 是围绕标称值的相对修正系数，此处全部保持为零。K_Jg/K_Jp 同样不在
% 这里虚构型号值，调用方可显式给定辨识值或验证用合成值。

if nargin < 1 || isempty(cfg)
    cfg = sht_default_config();
end
if nargin < 2
    assetFile = [];
end

[cfg, parameterAsset] = sht_configure_transient_heat_state(cfg, assetFile);
if ~isfield(parameterAsset, 'referenceTable') || ...
        ~parameterAsset.referenceTable.generated
    error('SHT:TransientJoint:MissingReferenceTable', ...
        'P6 必须使用已经生成并验证的 epsilon_ss 参考表。');
end

template = sht_build_transient_step_in_template(parameterAsset, 'joint_full');
health = cfg.engine.boundary.health(:);
if parameterAsset.interface.interfaceVersion == 2503
    % h104:h111 是六部件八个局部间隙交换率相对修正。
    health(105:112) = 0;
    clearanceChannel = ['AC_W+AC_eta+CC_W+CC_eta+' ...
        'GT1_eta+GT2_eta+PT1_eta+PT2_eta'];
else
    health(65:68) = 0;
    clearanceChannel = 'HPC_W+HPC_eta+GT_eta+PT_eta';
end

cfg.engine.boundary.health = health;
cfg.engine.transientEffects.stage = 'P6_joint_full';
cfg.engine.transientEffects.stepInTemplate = template;
cfg.engine.transientEffects.inertiaEnabled = true;
cfg.engine.transientEffects.heatFeedbackEnabled = true;
cfg.engine.transientEffects.clearanceEnabled = true;
cfg.engine.transientEffects.clearanceFeedbackEnabled = true;
cfg.engine.transientEffects.componentMask = 15;
cfg.engine.transientEffects.clearanceComponentMask = 15;
cfg.engine.transientEffects.clearanceChannel = clearanceChannel;
[preparedReference,cacheInfo] = sht_prepare_clearance_reference_lookup( ...
    parameterAsset.referenceTable);
cfg.engine.transientEffects.clearanceReferenceTable = preparedReference;
cfg.engine.transientEffects.clearanceReferenceCacheInfo = cacheInfo;

% 统一校验器在此冻结512/128、15/27维状态、开关依赖和完整掩码契约。
cfg = sht_validate_runtime_config(cfg);
end
