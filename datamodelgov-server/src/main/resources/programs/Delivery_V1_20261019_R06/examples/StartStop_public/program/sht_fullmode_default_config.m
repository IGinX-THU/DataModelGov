function cfg=sht_fullmode_default_config(user)
%SHT_FULLMODE_DEFAULT_CONFIG 全模式会话集中配置；仅构造配置，不启动仿真。
% 本目录与TestData中的物理资产构成可搬迁运行包，不使用开发机绝对路径。
if nargin<1, user=struct(); end
root=fileparts(mfilename('fullpath'));
base=struct();
if isfolder(fullfile(fileparts(root),'C'))
    base.paths=struct('cRoot',fullfile(fileparts(root),'C'));
end
if isfield(user,'modelMode'),base.modelMode=user.modelMode;end
if isfield(user,'paths'),base.paths=user.paths;end
cfg=sht_startstop_default_config(base);
f=struct('version',26100701,'recordPeriodS',0.1,'maximumAcceptedSteps',80000,'npRatio',0.9, ...
    'loadMode','dual_collective','load',struct('powerW',0,'mkpNm',0, ...
    'mainPitchDeg',6,'tailPitchDeg',5),'powerEngagementRpm',1000, ...
    'tailToMainPowerRatio',0.10,'tailDesignPitchDeg',10, ...
    'mainPitchBoundsDeg',[0,14],'tailPitchBoundsDeg',[-8,18], ...
    'densityKgPerM3',1.225,'designDensityKgPerM3',1.225, ...
    'initialKind','stopped','initialNpRatio',0.90, ...
    'initialThermalState',[],'thermalEnabled',true, ...
    'coldBlowDurationS',30, ...
    'sensor',struct('mode','identity','bias',[],'noiseStd',[], ...
    'timeConstant',0,'randomSeed',1701,'biasModel',struct('enabled',false)), ...
    'outputDirectory','','assetDirectory',fullfile(root,'TestData','fullmode', ...
    sprintf('model%d',cfg.modelMode)),'seedPoolFile','');
if cfg.modelMode==0
    f.seedPoolFile=fullfile(root,'MiddleData','startstop','three_component', ...
        'stage05_20260922_062007_901','result.mat');
else
    f.seedPoolFile=fullfile(root,'MiddleData','startstop','stage05_20260922_041617_601','result.mat');
end
cfg.fullmode=f;
cfg=sht_merge_config(cfg,user);
% 顶层randomSeed从未进入传感器。旧配置只告知并忽略，不能静默映射，
% 否则同一旧配置的噪声序列会改变；配置构造也不设置全局rng。
if isfield(cfg.fullmode,'randomSeed')
    cfg.fullmode=rmfield(cfg.fullmode,'randomSeed');
    warning('sht:fullmode:deprecatedRandomSeed', ...
        ['fullmode.randomSeed未参与全模式噪声生成，现已忽略。', ...
         '只有fullmode.sensor.randomSeed生效；未配置该字段时仍使用1701。']);
end
assert(cfg.stage6.timeStepS==0.025 && strcmp(cfg.stage6.integrationMethod,'euler2'), ...
    '全模式正式合同为0.025秒二阶欧拉，不能用记录周期替代积分。');
assert(cfg.fullmode.recordPeriodS==0.1,'正式记录频率固定10Hz。');
assert(any(strcmp(cfg.fullmode.loadMode,{'power','mkp','dual_collective'})), ...
    'loadMode必须为power、mkp或dual_collective。');
assert(any(strcmp(cfg.fullmode.initialKind,{'stopped','idle','cruise','maximum'})), ...
    '初态请选择stopped、idle、cruise或maximum；完整恢复使用restore接口。');
% 正恒功率/正恒扭矩静止起动已由用户取消。准备阶段即报明原因，
% 不加载DLL试错，不自动卸载或改成其他负载规律；非零初态不受影响。
if strcmp(cfg.fullmode.initialKind,'stopped')
    positiveDirect=false;
    if strcmp(cfg.fullmode.loadMode,'power')
        validateattributes(cfg.fullmode.load.powerW,{'numeric'},{'scalar','real','finite','nonnegative'});
        positiveDirect=cfg.fullmode.load.powerW>0;
    elseif strcmp(cfg.fullmode.loadMode,'mkp')
        validateattributes(cfg.fullmode.load.mkpNm,{'numeric'},{'scalar','real','finite','nonnegative'});
        positiveDirect=cfg.fullmode.load.mkpNm>0;
    end
    if positiveDirect
        error('sht:fullmode:unsupportedColdDirectLoad', ...
            '不支持正恒功率/正恒Mkp从静止起动。请使用相容的非零初态，或使用双总距起动方案；程序不会自动改变负载模式。');
    end
end
assert(isfinite(cfg.fullmode.powerEngagementRpm) && cfg.fullmode.powerEngagementRpm>0);
cfg.fullmode.active=true;
end
