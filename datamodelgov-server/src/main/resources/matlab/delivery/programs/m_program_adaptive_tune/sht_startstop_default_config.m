function cfg = sht_startstop_default_config(userCfg)
%SHT_STARTSTOP_DEFAULT_CONFIG 三/六部件起动停车模型的集中配置。
%
% 本配置只属于 StartupStop 独立分支。所有具有工程不确定性的首轮先验
% 均集中放在这里，避免散落在特性图生成、C接口和测试程序中。

thisDir = fileparts(mfilename('fullpath'));
branchRoot = fileparts(thisDir);
cRoot = fullfile(branchRoot, '涡轴发动机总体性能仿真C程序');

cfg = struct();
cfg.designReference = []; % 可选的已求解设计结果；空值保持原设计默认。
cfg.modelMode = 1;
if nargin >= 1 && isstruct(userCfg) && isfield(userCfg, 'modelMode')
    cfg.modelMode = userCfg.modelMode;
end
assert(isscalar(cfg.modelMode) && any(cfg.modelMode == [0, 1]), ...
    'modelMode只能为0（三部件）或1（六部件）。');
cfg.topology = struct('gasCount',7,'componentNames', ...
    {{'AC','CC','GT1','GT2','PT1','PT2'}}, ...
    'engineFields',{{'HPC','HPC2','HPT','HPT2','LPT','LPT2'}}, ...
    'stationNames',{{'S2','S25','S3','S4','GT1Out','GT2Out','PT1Out','PT2Out'}}, ...
    'heatNames',{{'AC','CC','Burner','GT1','GT2','PT1','PT2'}}, ...
    'compressorIndices',2:3,'turbineIndices',4:7, ...
    'compressorCount',2,'metalCount',19,'diskCount',6,'guideCount',2, ...
    'temperatureCount',27,'temperatureOutputIndices',25:51, ...
    'temperatureInputIndices',301:327,'referenceIndices',488:493, ...
    'modelFile','Turboshaft-TS-Split.mdl','assetNamespace','six_component');
cfg.schemaVersion = 26082401;
cfg.paths = struct();
cfg.paths.branchRoot = branchRoot;
cfg.paths.matlabRoot = thisDir;
cfg.paths.cRoot = cRoot;
cfg.paths.outputRoot = fullfile(branchRoot, 'report_outputs', 'StartupStop');
cfg.paths.splitModel = fullfile(cRoot, 'Turboshaft-TS-Split.mdl');
cfg.paths.dll = fullfile(cRoot, 'x64', 'Release', 'GTESS.dll');
cfg.paths.matlabHeader = fullfile(thisDir, 'GTESS.h');

cfg.mapIO.roundTripTolerance = 64 * eps;
cfg.mapIO.originalRegionTolerance = 0;
cfg.mapIO.lowSpeedNodes = [0, 0.01, 0.02, 0.05, 0.10, ...
    0.15, 0.20, 0.30, 0.40];
cfg.mapIO.transitionNodeFraction = 0.92;
% 起停专用压气机图在原Rline=1喘振端之外增加受控尾部。原图区域逐点
% 冻结，新增节点只供低速联合求解使用，普通稳态/瞬态入口仍读取原图。
cfg.mapIO.compressorLowPathNodes = [-0.50, -0.35, -0.20, -0.10, -0.05];
cfg.mapIO.compressorHighPathNodes = [1.25, 1.50, 1.75, 2.00];
cfg.mapIO.turbineLowBetaNodes = [-0.10, -0.05, -0.02];
cfg.mapIO.turbineHighBetaNodes = [1.25, 1.50, 2.00];
cfg.mapIO.turbineHighSpeedNodes = [1.10, 1.20, 1.30];
cfg.mapIO.generateFigures = true;
cfg.mapIO.showFigures = true;

% 特性图冻结结果可视化。默认对比最近一次已通过的阶段五结果；如需
% 复核指定基线，可把 stage5RunRoot 设置为对应 Stage05_* 目录。
cfg.mapComparison = struct();
cfg.mapComparison.stage5RunRoot = '';
cfg.mapComparison.showFigures = true;
cfg.mapComparison.imageResolutionDpi = 160;

cfg.maps = struct();
cfg.maps.AC = local_map('compressor', ...
    'HPC02_backup_before_surge_line_endpoint_20260706.MAP', ...
    'AC_StartupStop_LowSpeed.MAP');
cfg.maps.CC = local_map('compressor', 'SingleStgRadialCompr.MAP', ...
    'CC_StartupStop_LowSpeed.MAP');
cfg.maps.GT1 = local_map('turbine', 'HPT02.MAP', ...
    'GT1_StartupStop_LowSpeed.MAP');
cfg.maps.GT2 = local_map('turbine', 'HPT02.MAP', ...
    'GT2_StartupStop_LowSpeed.MAP');
cfg.maps.PT1 = local_map('turbine', 'LPT02.MAP', ...
    'PT1_StartupStop_LowSpeed.MAP');
cfg.maps.PT2 = local_map('turbine', 'LPT02.MAP', ...
    'PT2_StartupStop_LowSpeed.MAP');

% 零速图首轮先验只决定新增区域，不改变原图。压气机零速正向通流
% 表示总压损失；涡轮零速线保留从单位压比起始的锁转通流能力。
cfg.extension.AC = struct('lockedFlowFraction', 0.08, ...
    'lockedPressureLoss', 0.06, 'zeroEfficiency', 0.50);
cfg.extension.CC = struct('lockedFlowFraction', 0.10, ...
    'lockedPressureLoss', 0.09, 'zeroEfficiency', 0.50);
cfg.extension.GT1 = local_turbine_extension(0.34, 1.80, 0.025);
cfg.extension.GT2 = local_turbine_extension(0.32, 1.75, 0.025);
cfg.extension.PT1 = local_turbine_extension(0.30, 1.55, 0.020);
cfg.extension.PT2 = local_turbine_extension(0.28, 1.50, 0.020);

% 阶段三增强求解器配置。startStop接口关闭时，现有所有DLL入口仍调用
% 原newtonSolver，确保正常转速区不发生隐式算法切换。
cfg.lowSpeedSolver = struct('enabled', true, ...
    'activeSpeedRatio', 0.02, 'zeroHoldSpeedRpm', 0.5, ...
    'lowFlowReferenceKgPerS', 0.05, 'maxIterations', 60, ...
    'maxBacktracks', 10, 'minimumStepScale', 2^-10, ...
    'accuracyRequired', 1e-7, 'disturbanceFactor', 1e-4, ...
    'shutdownAccuracyRequired', 1e-4, ...
    'pivotRelativeTolerance', 1e-11, 'rankRelativeTolerance', 1e-9, ...
    'acPathMaximum', 2.0, 'ccPathMaximum', 2.0, ...
    'nozzleFlowBlendPressureRatio', 0.002);

% 阶段四首轮物理先验。数值均在后续SS5/SS6校准前保持显式可追溯。
cfg.startStop = struct();
cfg.startStop.configVersion = 26091204;
% 静态物理核检查的缺省值；连续入口从统一控制配置再次赋值。
cfg.startStop.maximumGasTemperatureK = 1400;
cfg.startStop.designNpRpm = 20800;
cfg.startStop.designNgRpm = 38000;
cfg.startStop.idleNgRatio = 0.65;
cfg.startStop.lightOffNgRatio = 0.12;
cfg.startStop.selfSustainNgRatio = 0.42;
cfg.startStop.starterCutoutNgRatio = 0.55;
cfg.startStop.ignitionDelayS = 0.50;
cfg.startStop.flameBuildS = 1.50;
cfg.startStop.starterStallTorqueNm = 95;
cfg.startStop.starterZeroTorqueSpeedRatio = 0.62;
cfg.startStop.lightOffFuelKgPerS = 0.025;
cfg.startStop.idleFuelKgPerS = 0.070;
cfg.startStop.hpsInertiaKgM2 = 0.283;
cfg.startStop.ptEngineInertiaKgM2 = 0.40;
cfg.startStop.rotorReflectedInertiaKgM2 = 1.20;
cfg.startStop.hpsCoulombLossNm = 2.5;
cfg.startStop.hpsViscousLossNmPerKrpm = 0.30;
cfg.startStop.hpsWindageLossNmPerKrpm2 = 0.015;
cfg.startStop.ptCoulombLossNm = 1.0;
cfg.startStop.ptViscousLossNmPerKrpm = 0.12;
cfg.startStop.ptWindageLossNmPerKrpm2 = 0.008;
cfg.startStop.gtAccessoryPowerW = 3000;
% 与六部件总体模型设计点一致。配合 thetaDesignDeg=12 deg，可使
% theta=10 deg、Npr=1 时得到约1.735 MW轴负载，与稳态数据闭合。
cfg.startStop.designRotorPowerW = 2176600;
cfg.startStop.collectivePitchDeg = 6;
cfg.startStop.thetaZeroDeg = 0;
cfg.startStop.thetaDesignDeg = 12;
cfg.startStop.profileTorqueFraction = 0.15;
cfg.startStop.rotorCoulombLossNm = 2.0;
cfg.startStop.rotorViscousLossNmPerKrpm = 0.05;
cfg.startStop.freewheelSpeedToleranceRpm = 5;
cfg.startStop.stopHoldSpeedRpm = 0.5;
cfg.startStop.timeStepS = 0.01;
cfg.startStop.nozzleAreaM2 = 0.10573;

% 阶段五低速共同工作矩阵。矩阵只固定轴转速并求解七维气路变量，
% 不把人工指定转速点解释为连续起动轨迹。点火后工况低于最低点火
% 转速时标记为不适用，不强迫模型产生非物理燃烧状态。
cfg.stage5 = struct();
cfg.stage5.ngRatio = [0, 0.01, 0.02, 0.05, 0.10, ...
    0.15, 0.20, 0.30, cfg.startStop.idleNgRatio];
cfg.stage5.npBranchNames = {'stationary', 'lagging', 'synchronous'};
cfg.stage5.npBranchFactors = [0, 0.6, 1.0];
cfg.stage5.energyStateNames = {'no_fuel', 'pre_ignition', 'fired_low_fuel'};
cfg.stage5.firedMinimumNgRatio = cfg.startStop.lightOffNgRatio;
cfg.stage5.firedPreconditionTimeS = cfg.startStop.ignitionDelayS + ...
    cfg.startStop.flameBuildS + 0.25;
cfg.stage5.fuelScheduleNgRatio = [cfg.startStop.lightOffNgRatio, ...
    cfg.startStop.idleNgRatio];
cfg.stage5.fuelScheduleKgPerS = [cfg.startStop.lightOffFuelKgPerS, ...
    cfg.startStop.idleFuelKgPerS];
cfg.stage5.matrixResidualRmsTolerance = 1e-6;
cfg.stage5.matrixMaximumResidualTolerance = 1e-5;
cfg.stage5.requiredRank = 7;
cfg.stage5.maximumCondition = 1e10;
% 起停专用七维求解器与设计模式求解器的方程组织不同，但在有火RUN态下
% 应复现同一设计工况。除严格残差外，变量和输出采用0.1%的工程一致性
% 门限，防止把零燃油风车根等错误根仅凭“残差小”误判为设计点。
cfg.stage5.enhancedDesignResidualTolerance = 1e-7;
cfg.stage5.enhancedDesignVariableRelativeTolerance = 1e-3;
cfg.stage5.enhancedDesignOutputRelativeTolerance = 1e-3;
cfg.stage5.maximumRetryCount = 24;
cfg.stage5.lowSpeedHeuristicSeed = ...
    [0.05; 0.8; 0.8; 1.05; 1.05; 1.05; 1.05];
cfg.stage5.gasVariableMinimum = [0, -0.5, -0.5, 1, 1, 1, 1];
cfg.stage5.gasVariableMaximum = [20, cfg.lowSpeedSolver.acPathMaximum, ...
    cfg.lowSpeedSolver.ccPathMaximum, 5, 5, 5, 5];

% 阶段五受约束校准。参数顺序固定为 AC/CC 的零速通流比例和压损，
% 以及四级涡轮的零速通流比例和零速最大压比。零速效率不参与搜索。
cfg.stage5.calibrationEnabled = true;
cfg.stage5.calibrationParameterNames = { ...
    'AC_flow', 'AC_pressure_loss', 'CC_flow', 'CC_pressure_loss', ...
    'GT1_flow', 'GT1_max_pr', 'GT2_flow', 'GT2_max_pr', ...
    'PT1_flow', 'PT1_max_pr', 'PT2_flow', 'PT2_max_pr'};
cfg.stage5.calibrationLowerBound = [ ...
    0.03, 0.01, 0.04, 0.02, ...
    0.12, 1.15, 0.12, 1.15, 0.12, 1.15, 0.12, 1.15];
cfg.stage5.calibrationUpperBound = [ ...
    0.20, 0.20, 0.25, 0.25, ...
    0.55, 2.50, 0.55, 2.50, 0.55, 2.50, 0.55, 2.50];
cfg.stage5.sensitivityRelativeStep = 0.12;
cfg.stage5.maximumReleasedParameters = 4;
cfg.stage5.coordinateSearchRounds = 2;
cfg.stage5.coordinateInitialStepFraction = 0.12;
cfg.stage5.coordinateStepReduction = 0.5;
cfg.stage5.minimumObjectiveImprovement = 1e-8;
cfg.stage5.calibrationSubsetNgRatio = [0.01, 0.02, 0.05, 0.10, 0.15, 0.30, ...
    cfg.startStop.idleNgRatio];
cfg.stage5.calibrationSubsetBranches = {'stationary', 'lagging', ...
    'synchronous'};
cfg.stage5.calibrationSubsetStates = {'no_fuel', 'fired_low_fuel'};

% 阶段六连续任务与鲁棒性验收。任务调度仅决定上层指令和燃油给定，
% 起停阶段、有效燃油、轴系动力学和自由轮状态仍由同一次C状态机连续推进。
% 所有鲁棒性算例均复用阶段五冻结图，不允许通过重调图吸收动态问题。
cfg.stage6 = struct();
cfg.stage6.timeStepS = 0.025;
cfg.stage6.integrationMethod = 'euler2'; % 显式梯形/Heun；euler1仅供历史数值回归。
cfg.stage6.initialHoldS = 1.0;
cfg.stage6.maximumStartupS = 80.0; % 达到稳定慢车的时限，不把暖机时间混入
cfg.stage6.idleStableDwellS = 3.0;
cfg.stage6.maximumIdleSettleS = 60.0;
cfg.stage6.idleCaptureRampS = 10.0;
% 起动控制先完成升速与负载斜坡，再连续稳定保持；不是首次到值即接管。
cfg.stage6.startupIdleHoldS = 60.0;
cfg.stage6.startupNgToleranceRpm = 190.0; % 设计Ng的0.5%，工程稳定带
cfg.stage6.startupIdleNgRpm = 28643.94; % 六部件标称负载慢车平衡标定
cfg.stage6.startupNgErrorGain = 1.0; % 1/s，Ng参考误差反馈
cfg.stage6.idleHandoverRampS = 3.0;
cfg.stage6.startupControlStrategy = 'stable_idle_R008';
% Ng目标采用连续速度和变化率连接；同一过渡内逐步加入慢车桨距负载。
% 不再先开环加负载、等待转速稳定后才启动调速器。
cfg.stage6.cruiseRampS = 20.0;
cfg.stage6.cruiseStableDwellS = 5.0;
cfg.stage6.maximumCruiseHoldS = 30.0;
cfg.stage6.returnRampS = 20.0;
cfg.stage6.idleBeforeShutdownS = 5.0;
cfg.stage6.maximumShutdownS = 240.0;
cfg.stage6.zeroHoldAfterStopS = 1.0;
cfg.stage6.maximumMissionS = 480.0;
% 矩阵仍单独检查1%/2% Ng处的非零气路根；连续任务在4% Ng以下
% 使用零流量渐近分支，轴系摩擦/起动机/旋翼运动继续积分。该简化
% 不等价于已校准的低速风车或反向通流模型，需随实测数据进一步确认。
cfg.stage6.gasPathActivationNgRatio = 0.04;
cfg.stage6.ignitionEnableNgRatio = 0.20;
cfg.stage6.idleNpRpm = 14000;
% idleNpRatio在配置合并后按当前构型设计转速派生，不是独立输入。
cfg.stage6.cruiseNpRatio = 1.00;
cfg.stage6.startPitchDeg = 0.0;
cfg.stage6.idlePitchDeg = 6.0;
cfg.stage6.cruisePitchDeg = 10.0;
% 阶段五的 idleFuelKgPerS 是低速共同工作矩阵扫描点，不等同于连续
% 仅用于点火至自持阶段的给油参考；Ng暖机燃油由闭环计算，不钳在该值。
cfg.stage6.idleFuelFeedforwardKgPerS = 0.043;
% 慢车以上不再配置独立PI、巡航前馈或燃油速率限制。
% 这些量由sht_startstop_prepare_control从本地同源主控制器配置读取。
% 起动阶段温度软限制低于硬保护，给执行机构和热端响应留出滞后裕度；
% 硬保护仍为cfg.startStop.maximumGasTemperatureK。
cfg.stage6.temperatureSoftLimitK = 1000;
cfg.stage6.temperatureMinimumFuelKgPerS = 0.015;
% 温度误差经积分形成连续燃油上限，量纲为 kg/(s^2*K)。温度高于
% 软门限时收紧上限，低于软门限时释放上限，避免硬低选产生燃油锯齿。
cfg.stage6.temperatureFuelIntegralGainKgPerS2K = 2.0e-4;
cfg.stage6.temperatureFuelRecoveryRateKgPerS2 = 2.0e-3;
cfg.stage6.npStableToleranceRatio = 0.025;
cfg.stage6.ngDotStableToleranceRpmPerS = 80;
cfg.stage6.npDotStableToleranceRpmPerS = 80;
cfg.stage6.stopSpeedToleranceRpm = cfg.startStop.stopHoldSpeedRpm;

% 根延续量按七个变量允许区间归一化。该判据只识别离散跳根，不要求
% 根在快速动态过程中缓慢不变；阈值在连续名义轨迹结果中同时原样记录。
cfg.stage6.rootVariableScale = [20; 2.5; 2.5; 4; 4; 4; 4];
cfg.stage6.maximumNormalizedRootStep = 0.35;
cfg.stage6.maximumRootRetries = 8;
% 连续动态每步均重新求解共同工作点，采用与输出精度相匹配的动态
% Newton门限；静态阶段五仍保留更严格的1e-6矩阵验收要求。
cfg.stage6.solverAccuracyRequired = 1e-5;
cfg.stage6.residualRmsTolerance = 1e-5;
% 七维残差在RMS门限处的单分量理论上限为sqrt(7)倍，取3e-5留出
% 浮点舍入余量；该门限仍远小于连续积分一步造成的状态变化。
cfg.stage6.maximumResidualTolerance = 3e-5;
cfg.stage6.shutdownResidualRmsTolerance = 1e-4;
cfg.stage6.shutdownMaximumResidualTolerance = 3e-4;
cfg.stage6.requiredRank = cfg.stage5.requiredRank;
cfg.stage6.maximumCondition = cfg.stage5.maximumCondition;
cfg.stage6.maximumSpeedRatio = 1.10;
cfg.stage6.maximumTt45K = cfg.startStop.maximumGasTemperatureK;
% 默认在交互式MATLAB中显示并保留每个算例的历程图和总体对比图。
% 批处理或只需要文件输出时，可由入口配置为 false。
cfg.stage6.showFigures = true;
% 仅限制绘图点数，CSV、MAT和全部验收计算始终使用原始时间步数据。
cfg.stage6.maximumPlotPoints = 4000;

% 首轮鲁棒性矩阵采用单因素小扰动，并增加一个中等不利组合。初始金属
% 温度属于阶段七Visser热网络，不在本阶段伪造为一层气路输入。
cfg.stage6.formalCaseNames = {'nominal', 'hot_ambient', 'cold_ambient', ...
    'weak_starter', 'slow_ignition', 'high_friction', ...
    'high_inertia', 'high_load', 'combined_adverse'};
cfg.stage6.formalCaseLabels = {'标称', '高温环境', '低温环境', ...
    '起动机能力降低', '点火/火焰建立变慢', '轴系摩擦增大', ...
    '轴系与旋翼惯量增大', '旋翼负载增大', '中等不利组合'};
% caseNames允许入口程序临时选择调试子集；formalCaseNames始终保存正式
% 九算例矩阵，不能随调试配置隐式改变。
cfg.stage6.caseNames = cfg.stage6.formalCaseNames;
cfg.stage6.caseLabels = cfg.stage6.formalCaseLabels;

% 阶段七Visser二层耦合。默认关闭，只有阶段七正式入口完成标称热参数
% 初始化并提供27维动态状态后才启用，因此阶段六及普通慢车以上仿真不受影响。
cfg.stage7 = struct();
cfg.stage7.enabled = false;
cfg.stage7.assetFile = fullfile(thisDir, 'MiddleData', ...
    'transient_effects_split_visser29_parameters_v2.mat');
cfg.stage7.postStopHeatSoakS = 120.0;
cfg.stage7.maximumMissionS = 620.0;
cfg.stage7.warmInitialFraction = 0.50;
cfg.stage7.minimumTemperatureK = 150.0;
cfg.stage7.maximumTemperatureK = 2000.0;
% R004的5 K/步对应1/120 s，即600 K/s。用温变率保持工程包线不随dt改变。
% 该项不代表数值积分精度，精度另通过步长对照核查。
cfg.stage7.maximumThermalRateKPerS = 600.0;
cfg.stage7.normalizedEnergyResidualTolerance = 1.0e-9;
cfg.stage7.zeroFlowStoredEnergyRelativeTolerance = 1.0e-10;
cfg.stage7.minimumHeatRedistributionK = 1.0e-6;
cfg.stage7.showFigures = true;
cfg.stage7.formalCaseNames = {'cold_no_feedback', ...
    'cold_full_coupled', 'warm_full_coupled'};
cfg.stage7.caseNames = cfg.stage7.formalCaseNames;

% 三部件总体图独立扩展，不复用六部件串联图或其低速校准系数。
if cfg.modelMode == 0
    cfg.topology = struct('gasCount',4,'componentNames',{{'HPC','HPT','LPT'}}, ...
        'engineFields',{{'HPC','HPT','LPT'}}, ...
        'stationNames',{{'S2','S3','S4','GTOut','PTOut'}}, ...
        'heatNames',{{'HPC','Burner','GT','PT'}}, ...
        'compressorIndices',2,'turbineIndices',3:4, ...
        'compressorCount',1,'metalCount',10,'diskCount',3,'guideCount',1, ...
        'temperatureCount',14,'temperatureOutputIndices',[25:34,44:46,50], ...
        'temperatureInputIndices',301:314,'referenceIndices',431:433, ...
        'modelFile','Turboshaft-TS.mdl','assetNamespace','three_component');
    cfg.paths.splitModel = fullfile(cRoot,cfg.topology.modelFile);
    cfg.maps = struct('HPC',local_map('compressor','HPC02.MAP','HPC_StartupStop_LowSpeed.MAP'), ...
        'HPT',local_map('turbine','HPT02.MAP','HPT_StartupStop_LowSpeed.MAP'), ...
        'LPT',local_map('turbine','LPT02.MAP','LPT_StartupStop_LowSpeed.MAP'));
    cfg.extension = struct('HPC',struct('lockedFlowFraction',0.10, ...
        'lockedPressureLoss',0.14,'zeroEfficiency',0.50), ...
        'HPT',local_turbine_extension(0.34,2.5,0.025), ...
        'LPT',local_turbine_extension(0.30,2.0,0.020));
    cfg.startStop.designNpRpm = 20900;
    % 三部件最低速涡轮PR接近1，较小差分避免跨过可行域边界。
    cfg.lowSpeedSolver.disturbanceFactor = 1e-5;
    cfg.stage5.coordinateSearchRounds = 4;
    cfg.stage5.requiredRank = 4;
    cfg.stage5.lowSpeedHeuristicSeed = [0.05;0.8;1.05;1.05];
    cfg.stage5.gasVariableMinimum = [0,-0.5,1,1];
    cfg.stage5.gasVariableMaximum = [20,2,10,10];
    cfg.stage5.calibrationParameterNames = {'HPC_flow','HPC_pressure_loss', ...
        'HPT_flow','HPT_max_pr','LPT_flow','LPT_max_pr'};
    cfg.stage5.calibrationLowerBound = [0.03,0.01,0.12,1.15,0.12,1.15];
    cfg.stage5.calibrationUpperBound = [0.25,0.30,0.60,4.0,0.60,3.5];
    cfg.stage6.requiredRank = 4;
    % 三部件冷态热负荷下，0.043 kg/s会停在Ng=0.648附近，无法跨过
    % 已确认的0.65慢车事件门限。专用前馈保留适当加速余量，温限仍有效。
    cfg.stage6.idleFuelFeedforwardKgPerS = 0.045;
    cfg.stage6.startupIdleNgRpm = 25010.52; % 三部件标称Np约14000、桨距6度
    cfg.stage6.rootVariableScale = [20;2.5;9;9];
    cfg.stage7.assetFile = fullfile(thisDir,'MiddleData','startstop', ...
        'three_component','tc27_visser16_parameters.mat');
end

% R2019b may decode Chinese path literals inconsistently; resolve by file features.
if nargin>=1 && isfield(userCfg,'paths') && isfield(userCfg.paths,'cRoot')
    cRoot = userCfg.paths.cRoot;
    assert(isfolder(cRoot),'显式C工程路径不存在：%s。',cRoot);
else
    cRoot = sht_startstop_resolve_c_root(branchRoot);
end
cfg.paths.cRoot = cRoot;
cfg.paths.splitModel = fullfile(cRoot, cfg.topology.modelFile);
cfg.paths.dll = fullfile(cRoot, 'x64', 'Release', 'GTESS.dll');
if nargin >= 1 && ~isempty(userCfg)
    if ~isstruct(userCfg)
        error('sht:startStop:badConfig', 'userCfg必须为结构体。');
    end
    cfg = sht_merge_config(cfg, userCfg);
end
if ~isempty(cfg.designReference)
    r=cfg.designReference;
    assert(isstruct(r) && isscalar(r) && r.schema==26101401 && r.modelMode==cfg.modelMode, ...
        'sht:startstop:designReference','显式设计参考的格式或拓扑不相容。');
    validateattributes([r.NpRpm,r.NgRpm,r.fuelFlowKgPerS,r.loadPowerW,r.nozzleAreaM2], ...
        {'numeric'},{'real','finite','positive'});
    keys={'designNpRpm','designNgRpm','designRotorPowerW','nozzleAreaM2'};
    values=[r.NpRpm,r.NgRpm,r.loadPowerW,r.nozzleAreaM2];
    for k=1:numel(keys)
        if isfield(userCfg,'startStop') && isfield(userCfg.startStop,keys{k})
            assert(abs(userCfg.startStop.(keys{k})-values(k))<=1e-8*max(1,abs(values(k))), ...
                'sht:startstop:designConflict','startStop.%s与显式设计结果冲突。',keys{k});
        end
        cfg.startStop.(keys{k})=values(k);
    end
end
assert(isscalar(cfg.stage6.idleNpRpm) && isfinite(cfg.stage6.idleNpRpm) && ...
    cfg.stage6.idleNpRpm > 0 && cfg.stage6.idleNpRpm < cfg.startStop.designNpRpm, ...
    '慢车转速idleNpRpm必须为正且低于设计Np。');
if nargin >= 1 && isfield(userCfg,'stage6') && ...
        isfield(userCfg.stage6,'idleNpRatio') && ...
        ~isfield(userCfg.stage6,'idleNpRpm')
    error('sht:startstop:idleSpeedUnit', ...
        '慢车目标请配置stage6.idleNpRpm，idleNpRatio仅为派生比例。');
end
cfg.stage6.idleNpRatio = cfg.stage6.idleNpRpm/cfg.startStop.designNpRpm;
assert(isscalar(cfg.stage6.startupIdleHoldS) && ...
    isfinite(cfg.stage6.startupIdleHoldS) && cfg.stage6.startupIdleHoldS>0 && ...
    isscalar(cfg.stage6.startupNgToleranceRpm) && ...
    isfinite(cfg.stage6.startupNgToleranceRpm) && cfg.stage6.startupNgToleranceRpm>0 && ...
    isfinite(cfg.stage6.startupIdleNgRpm) && cfg.stage6.startupIdleNgRpm>0 && ...
    cfg.stage6.startupIdleNgRpm<cfg.startStop.designNgRpm && ...
    cfg.stage6.startupIdleNgRpm>=cfg.startStop.idleNgRatio*cfg.startStop.designNgRpm && ...
    isfinite(cfg.stage6.startupNgErrorGain) && cfg.stage6.startupNgErrorGain>0 && ...
    isfinite(cfg.stage6.idleHandoverRampS) && cfg.stage6.idleHandoverRampS>0, ...
    '起动慢车稳定保持时间与转速误差带必须为有限正数。');
end

function item = local_map(kind, sourceName, outputName)
item = struct('kind', kind, 'sourceName', sourceName, ...
    'outputName', outputName);
end

function item = local_turbine_extension(flowFraction, maxPR, efficiency)
item = struct('lockedFlowFraction', flowFraction, ...
    'lockedMaximumPressureRatio', maxPR, ...
    'zeroEfficiency', efficiency, ...
    'lockedFlowBetaExponent', 1.0, ...
    'unitPressureBetaAnchor', -0.10, ...
    'unitPressureFlowExponent', 1.0, ...
    'highBetaFlowSlopeFactor', 1.0);
end
