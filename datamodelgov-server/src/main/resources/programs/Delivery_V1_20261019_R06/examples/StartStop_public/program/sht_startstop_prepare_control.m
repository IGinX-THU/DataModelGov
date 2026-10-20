function cfg = sht_startstop_prepare_control(cfg)
%SHT_STARTSTOP_PREPARE_CONTROL 在打开起停DLL之前准备同源慢车以上控制器。
% 不依赖主程序目录，不从历史运行结果加载控制状态。控制核心、增益表及
% sht_default_config均来自StartupStop本地受版本管理的副本。
% userCfg.aboveIdleOverrides允许显式试验覆盖，并随结果保存，不能静默调参。
overrides = struct('engine',struct('modelMode',cfg.modelMode));
if isfield(cfg,'aboveIdleOverrides')
    overrides = sht_merge_config(overrides,cfg.aboveIdleOverrides);
end
assert(overrides.engine.modelMode == cfg.modelMode,'控制器与发动机拓扑不一致。');
if isfield(cfg,'designReference') && ~isempty(cfg.designReference)
    % 必须在sht_default_config打开DLL和建立局部控制模型前传入。
    assert(~isfield(overrides.engine,'designReference') || ...
        isequaln(overrides.engine.designReference,cfg.designReference), ...
        'sht:startstop:designConflict','控制覆盖值不能另指定不一致的设计参考。');
    overrides.engine.designReference=cfg.designReference;
end
normal = sht_default_config(overrides);
% 修复在两边共用的增益表加载器完成，此处只归档，不重复计算。
gs=normal.controller.gainSchedule;
repair=struct('applied',false,'oldD41',[],'newD41',[],'torquePerAcceleration',NaN);
if isfield(gs,'torqueGainRepair'),repair=gs.torqueGainRepair;end
cfg.aboveIdle = struct('controller',normal.controller, ...
    'actuator',normal.actuator,'sampleTimeS',normal.Tctrl, ...
    'sourceFile',which('sht_default_config'),'version','STARTSTOP-R008');
cfg.aboveIdle.torqueGainRepair=repair;
if isfield(normal.engine,'designConsumption')
    cfg.aboveIdle.designConsumption=normal.engine.designConsumption;
end
% Np主回路增益沿用原值；起动暖机改由Ng参考管理，不再提前切换Np。
assert(isfinite(normal.controller.npErrorGain) && isfinite(normal.controller.npDeltaGain) && ...
    normal.controller.npErrorGain>0 && normal.controller.npDeltaGain>=0, ...
    'Np调速器误差增益必须为正，差分增益必须非负。');
requestedStep = cfg.stage6.timeStepS;
assert(isfinite(requestedStep) && requestedStep > 0, '积分步长必须为正。');
substeps = max(1,ceil(normal.Tctrl/requestedStep));
cfg.aboveIdle.integrationSubsteps = substeps;
cfg.aboveIdle.requestedStepS = requestedStep;
cfg.stage6.timeStepS = normal.Tctrl/substeps;
cfg.startStop.timeStepS = cfg.stage6.timeStepS;
assert(ismember(cfg.stage6.integrationMethod,{'euler1','euler2'}), ...
    '发动机积分方法只能为euler1或euler2。');
cfg.aboveIdle.integrationMethod=cfg.stage6.integrationMethod;
limit = normal.controller.t45Protection.t45Max;
% 硬保护仍沿用同源控制器；起动阶段软限制允许在 userCfg.stage6 中
% 单独收紧，避免执行机构滞后把温度越过硬保护。
softLimit = cfg.stage6.temperatureSoftLimitK;
if ~isscalar(softLimit) || ~isfinite(softLimit) || softLimit <= 0 || softLimit > limit
    softLimit = limit;
end
cfg.startStop.maximumGasTemperatureK = limit;
cfg.stage6.temperatureSoftLimitK = softLimit;
cfg.stage6.maximumTt45K = limit;
assert(cfg.startStop.configVersion == 26091204, ...
    '统一控制连续任务必须使用30项起停配置接口。');
fprintf('统一控制: Tctrl=%.6g s, dt=%.9g s, Tt45max=%.6g K, Ngmax=%.6g rpm, Mkpmax=%.6g Nm\n', ...
    normal.Tctrl,cfg.stage6.timeStepS,limit, ...
    normal.controller.ngProtection.ngMax,normal.controller.mkpProtection.mkpMax);
fprintf('发动机积分: %s，每控制拍%d个积分步。\n',cfg.stage6.integrationMethod,substeps);
fprintf('起动暖机: Ng=%.6g rpm，连续稳定%.6g s；正常慢车Np=%.6g rpm。\n', ...
    cfg.stage6.startupIdleNgRpm,cfg.stage6.startupIdleHoldS,cfg.stage6.idleNpRpm);
end
