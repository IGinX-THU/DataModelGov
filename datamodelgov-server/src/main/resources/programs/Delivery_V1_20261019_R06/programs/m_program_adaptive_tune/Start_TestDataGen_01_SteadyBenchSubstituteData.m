function result = Start_TestDataGen_01_SteadyBenchSubstituteData(purpose, comparison)
%START_TESTDATAGEN_01_STEADYBENCHSUBSTITUTEDATA 生成六部件稳态台架替代数据。
%
% 第二轮稳态工况设计遵循以下工程约束：
%   1) 只使用六部件发动机模型（modelMode=1）；
%   2) 7个训练工况沿用已确认的六负载接合点和一个地面慢车点；
%   3) 3个测试工况覆盖高、中、低转速及不同桨距负载，全部保持负载接合；
%   4) 负载接合点以总距角为权威负载指令，经旋翼负载模型实时生成
%      Mkp和Pload；地慢训练点使用等效126 kW恒定直接扭矩；
%      扭矩以0.70Np0为换算基准对应126 kW轴功率，不再使用旧1%power0边界；
%   5) 每点先完成六部件稳态配平，再执行 20 s 闭环保持，取末 5 s
%      平稳窗口生成试车测量数据和隐藏真值；
%   6) 加载已验收的六部件43项非零真值和31张调度表，同时开启传感器
%      动态、公共偏置、流量漂移和白噪声；
%   7) 下游只获得每个工况稳态窗口内各可测时间历程的算术平均值，
%      训练集和测试集分别写入两个Excel；无误差真值只保存在隐藏MAT中。
% purpose='zero_health_anchors'仅重新配平七个零修正训练工况，返回最终
% DLL状态；不读历史真值、不执行传感器/闭环保持、不写任何数据文件。
% comparison仅用于隔离对照：runTag为新目录名，profile可指定候选真值。
% 未提供comparison时保留正式生成行为；隔离对照不替换任何latest。

if nargin < 1
    purpose = 'measurement_data';
end
purpose = validatestring(purpose, {'measurement_data', 'zero_health_anchors'});
if nargin<2, comparison=struct(); end
assert(isstruct(comparison)&&isscalar(comparison),'对照配置必须为标量结构体。');
% 三部件新测量合同独立组织数据，不覆盖六部件历史正式输入。
if isfield(comparison,'modelMode') && comparison.modelMode == 0
    assert(strcmp(purpose,'measurement_data'),'三部件锚点使用TC24-STEP02入口。');
    result = Start_TC24_03_SteadyBenchDataGeneration(comparison);
    return;
end
isolated=isfield(comparison,'runTag');
if isolated
    assert(~isempty(regexp(char(comparison.runTag),'^[A-Za-z0-9_-]+$','once')), ...
        '对照runTag仅允许字母、数字、下划线和连字符。');
end
assert(~isfield(comparison,'profile')||isolated, ...
    '候选profile仅允许用于带runTag的隔离对照，禁止隐式发布。');
anchorOnly = strcmp(purpose, 'zero_health_anchors');

thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir);

cfg = sht_default_config(struct( ...
    'engine', struct('modelMode', 1), ...
    'plot', struct('enable', false)));
rotorCfg = local_rotor_config(cfg);
testCfg = local_test_config(cfg, rotorCfg, anchorOnly);
testCfg.isolatedRunTag='';
if isolated
    testCfg.isolatedRunTag=char(comparison.runTag);
    target=fullfile(thisDir,'MiddleData','stage2_migration_data',testCfg.isolatedRunTag);
    assert(~isfolder(target),'对照目录已存在，请指定新的runTag。');
end
if isfield(comparison,'profile') && ~anchorOnly
    testCfg.healthScheduleProfile=comparison.profile;
    testCfg.healthScheduleSourceFile='explicit_isolated_candidate';
    testCfg.healthProfile=comparison.profile.schemaVersion;
    testCfg.health=comparison.profile.truthVectorAtDesign(:);
    active=comparison.profile.parameters([comparison.profile.parameters.activeTruth]);
    testCfg.healthUsedIndex=sort([active.matlabHealthIndex]);
end
cfg.engine.boundary.health = testCfg.health;
cfg.engine.boundary.healthScheduleEnabled = testCfg.healthScheduleEnabled;
cfg.engine.boundary.inletBoundaryMode = testCfg.benchEnvironment.inletBoundaryMode;
cfg.engine.boundary.altitude = testCfg.benchEnvironment.altitude;
cfg.engine.boundary.Mach = testCfg.benchEnvironment.Mach;
cfg.engine.boundary.deltaTemperature = testCfg.benchEnvironment.deltaTemperature;
cfg.engine.boundary.Pamb = testCfg.benchEnvironment.Pamb;
cfg.engine.boundary.Tamb = testCfg.benchEnvironment.Tamb;
cfg.engine.healthScheduleProfile = testCfg.healthScheduleProfile;
points = local_point_definitions(cfg, rotorCfg, testCfg);
if anchorOnly
    points = points(strcmp({points.dataset_role}, 'training'));
end

designRun = local_run_design_seed(cfg, testCfg);
testCfg.variableCount = numel(designRun.varIte);
testCfg.scale = local_variable_scale(cfg, testCfg.variableCount);
zSeed = [designRun.varIte(:); cfg.engine.initial.Wf0];
zLastGood = zSeed;

records = repmat(local_empty_record(), numel(points), 1);
timeHistories = cell(numel(points), 1);
anchorEngines = cell(numel(points), 1);
for i = 1:numel(points)
    point = points(i);
    if i > 1
        local_assert_required_seed(records, i, point);
        zSeed = local_predict_seed(records, i, zLastGood);
    end

    reusableSeed = struct('available', false, 'isSpecialized', false, ...
        'id', '', 'z', []);
    if strcmpi(point.load_input_mode, 'directTorque')
        reusableSeed = sht_get_steady_trim_initial_guess( ...
            cfg, point.target_Np, point.target_load_power, ...
            point.seed_source_point_id);
        if reusableSeed.available && reusableSeed.isSpecialized
            zSeed = reusableSeed.z;
        end
    end

    trim = local_trim_with_engine(cfg, testCfg, point, zSeed);
    trim.seedSourcePointId = point.seed_source_point_id;
    trim.fallbackUsed = false;
    if reusableSeed.available && reusableSeed.isSpecialized
        trim.strategy = ['reusable_fixed_seed:', reusableSeed.id];
    else
        trim.strategy = 'sequential_previous_point_seed';
    end
    if ~trim.converged
        trim = local_global_continuation_fallback( ...
            cfg, testCfg, point, trim);
    end
    if anchorOnly
        % 九个共同工作残差含两轴平衡，另核验目标Np；气路单步收敛不足以
        % 证明稳态锚点有效。所有调度坐标必须来自这次最终DLL状态。
        % RunOnePoint的stepOut不是共同工作残差输出契约；在它的最终解处
        % 再调用一次RunSteadyComponents显式校验，避免用清零缓冲假验收。
        trim.z = [trim.ev.varIte(:); trim.ev.wf];
        checkEngine = sht_engine_open(cfg.engine);
        checkCleanup = onCleanup(@() sht_engine_close(checkEngine));
        trim.ev = local_eval_steady(checkEngine, cfg, testCfg, point, trim.z);
        clear checkCleanup;
        fFinal = local_residual(trim.ev, point.target_Np);
        assert(trim.converged && trim.ev.ret == 0 && ...
            local_is_converged(trim.ev, fFinal, testCfg, point.target_Np), ...
            'SHT:TestDataGen:InvalidZeroHealthAnchor', ...
            '零修正锚点%s未配平：max|r|=%.9g，Np误差=%.6g rpm。', ...
            point.point_id, max(abs(fFinal)), trim.ev.output.Np-point.target_Np);
        trim.z = [trim.ev.varIte(:); trim.ev.wf];
        records(i) = local_record_from_trim(i, point, trim, testCfg);
        records(i).quality_pass = true;
        records(i).quality_reason = 'zero_health_trim_only';
        anchorEngines{i} = trim.ev.engineSnapshot;
        fprintf('零修正锚点 %s：Np=%.3f，Ng=%.3f rpm，max|r|=%.3e\n', ...
            point.point_id, trim.ev.output.Np, trim.ev.output.Ng, max(abs(fFinal)));
    elseif trim.converged
        [simSummary, simTruthSummary, timeHistories{i}] = local_run_controlled_steady_simulation( ...
            cfg, testCfg, point, trim);
        records(i) = local_record_from_simulation(point, trim, simSummary, simTruthSummary, testCfg);
    else
        records(i) = local_record_from_trim(i, point, trim, testCfg);
    end

    if trim.converged
        zLastGood = trim.z(:);
    end
    zSeed = zLastGood;
end

dataTable = struct2table(records);
if anchorOnly
    result = struct('dataTable', dataTable, 'anchorEngines', {anchorEngines}, ...
        'pointDefinitions', points, 'benchEnvironment', testCfg.benchEnvironment, ...
        'truthHealth', testCfg.health, 'healthScheduleEnabled', false, ...
        'sourceModel', cfg.engine.modelConfiguration);
    return;
end
output = local_write_outputs(thisDir, testCfg, points, dataTable, timeHistories);

result = struct();
result.engineId = testCfg.engineId;
result.caseId = testCfg.caseId;
result.modelMode = cfg.engine.modelMode;
result.loadInputMode = testCfg.loadInputMode;
result.rotorLoadConfig = rotorCfg;
result.groundIdleConfig = testCfg.groundIdle;
result.healthProfile = testCfg.healthProfile;
result.healthScheduleSourceFile = testCfg.healthScheduleSourceFile;
result.healthScheduleEnabled = testCfg.healthScheduleEnabled;
result.pointDefinitions = points;
result.truthHealth = testCfg.health;
result.truth_health_parameters = testCfg.health;
result.truthHealthUsedIndex = testCfg.healthUsedIndex;
result.measurementErrorModel = testCfg.measurementError;
result.benchEnvironment = testCfg.benchEnvironment;
result.dataTable = dataTable;
result.timeHistories = timeHistories;
result.output = output;
result.qualitySummary = local_quality_summary(dataTable);

% 最新批次结果供后续验证程序稳定定位。图形句柄只属于当前
% MATLAB会话，不进入可复用MAT资产。
latestResultFile = fullfile(thisDir, 'MiddleData', ...
    'steady_bench_10point_latest_result.mat');
if isolated
    latestResultFile=fullfile(output.outputDir,'result.mat');
end
result.output.latestResultFile = latestResultFile;
figureHandlesForSession = result.output.figureHandles;
result.output.figureHandles = [];
save(latestResultFile, 'result', '-v7.3');
result.output.figureHandles = figureHandlesForSession;

assignin('base', 'Start_TestDataGen_01_result', result);
local_print_summary(result);
end

function testCfg = local_test_config(cfg, rotorCfg, anchorOnly)
%LOCAL_TEST_CONFIG 汇总本次替代数据生成的固定设置。
testCfg = struct();
testCfg.engineId = 'TS_INDIV_001';
testCfg.caseId = 'bench_steady_six_component_7train_3test_truth_schedule_v2';
testCfg.modelMode = cfg.engine.modelMode;
testCfg.loadInputMode = 'mixedByPoint';
testCfg.loadConnected = 'pointSpecific';
% 真值资产已由Start_HealthParameterDesign_01独立设计和验收。
% 数据生成入口只负责读取，不在运行中重新设计真值。
if anchorOnly
    testCfg.healthScheduleProfile = [];
    testCfg.healthScheduleSourceFile = '';
    testCfg.healthProfile = 'zero_health_anchor_preparation';
    testCfg.healthScheduleEnabled = false;
else
    [testCfg.healthScheduleProfile, testCfg.healthScheduleSourceFile] = ...
        local_load_health_schedule_truth();
    testCfg.healthProfile = testCfg.healthScheduleProfile.schemaVersion;
    testCfg.healthScheduleEnabled = true;
end
testCfg.rotorLoad = rotorCfg;
testCfg.groundIdle = struct();
testCfg.groundIdle.NpRatio = 0.70;
testCfg.groundIdle.equivalentPowerW = 126.0e3;
testCfg.groundIdle.referencePowerRatio = ...
    testCfg.groundIdle.equivalentPowerW / cfg.engine.initial.power0;
testCfg.groundIdle.MkpRatio = ...
    testCfg.groundIdle.referencePowerRatio / testCfg.groundIdle.NpRatio;
testCfg.groundIdle.loadConnected = false;
testCfg.groundIdle.seedSourcePointId = ...
    'six_component_ground_idle_npr70_power126kw';
testCfg.groundIdle.rationale = ...
    '在70%Np0下采用等效126kW直接扭矩，表示负载脱开后的等效轴系负载。';
testCfg.A8 = cfg.engine.initial.A80;
testCfg.hpsPower = 0;
testCfg.hpcAlpha = 0;
if anchorOnly
    testCfg.health = zeros(159, 1);
    testCfg.healthUsedIndex = [];
else
    testCfg.health = testCfg.healthScheduleProfile.truthVectorAtDesign(:);
    activeParameter = testCfg.healthScheduleProfile.parameters( ...
        [testCfg.healthScheduleProfile.parameters.activeTruth]);
    testCfg.healthUsedIndex = sort([activeParameter.matlabHealthIndex]);
end
testCfg.benchEnvironment = local_bench_environment(cfg);
testCfg.maxNewtonIter = 25;
testCfg.residualTol = 1e-7;
testCfg.npTolRpm = 0.5;
testCfg.normalizedPerturb = 1e-4;
testCfg.variableCount = NaN;
testCfg.scale = [];
testCfg.wfMin = cfg.actuator.wfMin;
testCfg.wfMax = cfg.actuator.wfMax;
testCfg.t45Max = cfg.controller.t45Protection.t45Max;
testCfg.maxModelErrorTol = 1e-6;
testCfg.simulationStopTime = 20.0;
testCfg.steadyWindowDuration = 5.0;
testCfg.steadyWindowStartTime = testCfg.simulationStopTime - testCfg.steadyWindowDuration;
testCfg.steadyWindowEndTime = testCfg.simulationStopTime;
testCfg.minSteadyWindowSamples = 2;
testCfg.measurementError = local_test_measurement_error_model(cfg);
if anchorOnly
    testCfg.measurementError.enabled = false;
end
end

function environment = local_bench_environment(cfg)
%LOCAL_BENCH_ENVIRONMENT 用 DLL 标准大气模型生成100 m试车环境真值。
% 这里先用模式0查询标准大气，再把所得Pamb/Tamb作为模式2的外部
% 环境边界。这样不在MATLAB侧复制大气模型，也避免两处公式漂移。
engine = sht_engine_open(cfg.engine);
cleanup = onCleanup(@() sht_engine_close(engine));

queryBoundary = struct('inletBoundaryMode', 0, 'altitude', 100.0, ...
    'Mach', 0.0, 'deltaTemperature', 0.0);
stepInValue = zeros(cfg.engine.interface.stepInLength, 1);
[stepInValue, ~] = sht_apply_inlet_boundary_stepin( ...
    stepInValue, queryBoundary);
engInit.eng = libstruct(engine.engineStructName);
engPtr = libstruct(engine.enginePointerName, engInit);
stepIn = libpointer('doublePtr', stepInValue);
stepOut = libpointer('doublePtr', zeros(engine.stepOutLength, 1));
[status, ~, ~, engOut] = calllib(engine.libraryName, ...
    'DLL_SHT_ConditionsInit', stepIn, stepOut, engPtr);
if status ~= 0
    error('SHT:TestDataGen:BenchAtmosphereInitFailed', ...
        '100 m试车环境标准大气初始化失败，状态码=%d。', status);
end

environment = struct();
environment.inletBoundaryMode = 2;
environment.altitude = 100.0;
environment.Mach = 0.0;
environment.deltaTemperature = 0.0;
environment.Pamb = double(engOut.eng.Ambient.y(5));
environment.Tamb = double(engOut.eng.Ambient.y(6));
environment.source = 'DLL_mode0_standard_atmosphere_at_100m';
assert(isfinite(environment.Pamb) && environment.Pamb > 0 && ...
    isfinite(environment.Tamb) && environment.Tamb > 0, ...
    '100 m试车环境Pamb/Tamb无效。');

% libstruct/libpointer对象应先于DLL卸载释放。若直接等到函数退出，
% MATLAB可能先执行onCleanup卸载库，再析构这些接口对象，从而产生
% “库未加载”的非功能性警告。显式清理后再触发cleanup，资源顺序唯一。
clear engOut engPtr engInit stepIn stepOut;
clear cleanup;
end

function [profile, sourceFile] = local_load_health_schedule_truth()
%LOCAL_LOAD_HEALTH_SCHEDULE_TRUTH 读取已验收的六部件健康真值资产。
thisDir = fileparts(mfilename('fullpath'));
sourceFile = fullfile(thisDir, 'MiddleData', ...
    'six_component_health_schedule_truth_latest.mat');
assert(exist(sourceFile, 'file') == 2, ...
    ['缺少六部件健康调度真值资产：%s。' ...
     '请先运行Start_HealthParameterDesign_01_SixComponentTruthSchedule。'], ...
    sourceFile);
loaded = load(sourceFile, 'result');
assert(isfield(loaded, 'result') && isfield(loaded.result, 'profile') && ...
    isfield(loaded.result, 'pass') && loaded.result.pass, ...
    '六部件健康调度真值资产结构无效或未通过验收。');
profile = loaded.result.profile;
assert(profile.modelMode == 1 && numel(profile.truthVectorAtDesign) == 159, ...
    '健康调度真值资产与六部件159维接口不一致。');
assert(nnz([profile.parameters.activeTruth]) == 43 && ...
    all(profile.bleedPressureRecoveryDesign == 0), ...
    ['六部件健康真值资产仍是旧版口径：K_PRec必须全部为0，' ...
     '活动真值必须为43项。请先重新运行' ...
     'Start_HealthParameterDesign_01_SixComponentTruthSchedule。']);
end

function model = local_test_measurement_error_model(cfg)
%LOCAL_TEST_MEASUREMENT_ERROR_MODEL 试车测量数据的传感器偏置、白噪声和动态滞后配置。
% 反馈通道的误差进入闭环传感器模型；记录通道采用同一误差规格生成测量记录。
model = struct();
model.enabled = true;
model.randomSeed = 20260708;
model.description = [ ...
    '真实信号一阶传感器动态 + 一次试车公共偏置 + ' ...
    '显著通道10%流量漂移 + 输出端白噪声'];
model.biasModel = local_2p3_bias_model();
model.temperatureDynamics = sht_temperature_sensor_dynamics('model');
model.fields = local_measurement_error_specs(cfg);
end

function specs = local_measurement_error_specs(~)
% 公共偏置、偏置半宽、流量漂移和白噪声标准差由共享定义统一维护。
names = {'Np','Ng','Wf','Tt45','Mkp','Mkg','Pt2','Tt1', ...
    'Pt3','Tt3','Pt45','Tamb','Pamb','Altitude','Mach'};
timeConstant = 0.020 * ones(size(names));
temperatureConfig = sht_temperature_sensor_dynamics( ...
    'channelConfig', names);
timeConstant(temperatureConfig.supported) = ...
    temperatureConfig.timeConstant_s(temperatureConfig.supported);
lookupNames = names;
lookupNames(strcmp(lookupNames, 'Tt45')) = {'T45'};
channelConfig = sht_measurement_bias_generator( ...
    'channelConfig', lookupNames);
specs = repmat(local_error_spec('', 'absolute', NaN, 0, 0, 0, ''), ...
    numel(names), 1);
for i = 1:numel(names)
    specs(i) = local_error_spec(names{i}, 'absolute', NaN, ...
        channelConfig.commonBias(i), channelConfig.noiseStd(i), ...
        timeConstant(i), channelConfig.unit{i});
    specs(i).sharedBiasEnabled = true;
    specs(i).totalBiasHalfWidth = channelConfig.totalBiasHalfWidth(i);
    specs(i).flowDriftEnabled = channelConfig.flowDriftEnabled(i);
    specs(i).maxFlowDrift = channelConfig.maxFlowDrift(i);
end
end

function model = local_2p3_bias_model()
% 2.3输出使用规范测点名，同时保持尚未迁移的其他阶段共享字典不变。
model = sht_measurement_bias_generator('model');
index = find(strcmp({model.channels.name}, 'T45'), 1, 'first');
if isempty(index)
    error('SHT:TestDataGen:MissingTt45BiasDefinition', ...
        '共享偏置字典缺少45截面总温通道。');
end
model.channels(index).name = 'Tt45';
for i = 1:numel(model.channels)
    model.channels(i).referenceSource = strrep( ...
        model.channels(i).referenceSource, 'T45', 'Tt45');
end
model.description = strrep(model.description, 'Wf/T45/Tt3', ...
    'Wf/Tt45/Tt3');
model.specification = struct2table(model.channels);
end

function spec = local_error_spec(name, mode, reference, biasValue, noiseValue, timeConstant, unit)
%LOCAL_ERROR_SPEC 构造单个试车测量数据通道的误差规格。
spec = struct();
spec.name = name;
spec.mode = mode;
spec.reference = reference;
spec.biasValue = biasValue;
spec.noiseValue = noiseValue;
spec.timeConstant = timeConstant;
spec.unit = unit;
spec.sharedBiasEnabled = false;
spec.totalBiasHalfWidth = NaN;
spec.flowDriftEnabled = false;
spec.maxFlowDrift = 0;
end

function rotorCfg = local_rotor_config(cfg)
%LOCAL_ROTOR_CONFIG 与六部件控制律验收入口使用同一总距角负载模型。
designNp = cfg.controller.DPpara.Np0;
designPower = cfg.engine.initial.power0;
rotorCfg = struct();
rotorCfg.enabled = true;
rotorCfg.inputMode = 'collectivePitch';
rotorCfg.designNpRpm = designNp;
rotorCfg.designPowerW = designPower;
rotorCfg.designTorqueNm = designPower / (designNp*pi/30);
rotorCfg.collectivePitchMapping = struct( ...
    'thetaZeroDeg', 0, ...
    'thetaDesignDeg', 12, ...
    'profileTorqueFraction', 0.15, ...
    'thetaValidRangeDeg', [6, 14]);
end

function points = local_point_definitions(cfg, rotorCfg, testCfg)
%LOCAL_POINT_DEFINITIONS 七个训练点和三个独立测试点。
% 运行顺序按转速/负载邻近性排列，用于提高连续配平收敛性；
% dataset_role才是数据划分的权威标志，与运行先后顺序无关。
np0 = cfg.engine.initial.Np0;
power0 = cfg.engine.initial.power0;
defs = { ...
    'S2.3.2-01', 'Npr100_Theta8',  'training', 1.00,  8.0, '设计转速低负载训练点'; ...
    'S2.3.2-02', 'Npr100_Theta10', 'training', 1.00, 10.0, '设计转速中负载训练点'; ...
    'S2.3.2-03', 'Npr100_Theta12', 'training', 1.00, 12.0, '设计转速最大状态训练点'; ...
    'S2.3.2-08', 'Npr95_Theta11',  'test',     0.95, 11.0, '高转速负载接合测试点'; ...
    'S2.3.2-04', 'Npr90_Theta10',  'training', 0.90, 10.0, '90%动力轴转速训练点'; ...
    'S2.3.2-09', 'Npr85_Theta9',   'test',     0.85,  9.0, '中等转速负载接合测试点'; ...
    'S2.3.2-05', 'Npr80_Theta10',  'training', 0.80, 10.0, '80%动力轴转速训练点'; ...
    'S2.3.2-06', 'Npr70_Theta10',  'training', 0.70, 10.0, '低转速负载接合训练点'; ...
    'S2.3.2-10', 'Npr70_Theta8',   'test',     0.70,  8.0, '慢车转速负载接合测试点'};

points = repmat(local_empty_point(), size(defs, 1) + 1, 1);
for i = 1:size(defs, 1)
    points(i).point_id = defs{i, 1};
    points(i).case_name = defs{i, 2};
    points(i).dataset_role = defs{i, 3};
    points(i).target_Np_ratio = defs{i, 4};
    points(i).collective_pitch_deg = defs{i, 5};
    points(i).description = defs{i, 6};
    points(i).target_Np = points(i).target_Np_ratio * np0;
    loadState = sht_rotor_load_model(points(i).target_Np, ...
        points(i).collective_pitch_deg, rotorCfg, 'collectivePitch');
    points(i).k_theta = loadState.kTheta;
    points(i).target_Mkp = loadState.QloadNm;
    points(i).target_Mkp_ratio = loadState.QloadNm / rotorCfg.designTorqueNm;
    points(i).target_load_power = loadState.PloadW;
    points(i).target_load_power_ratio = loadState.PloadW / power0;
    points(i).load_input_mode = 'collectivePitch';
    points(i).load_connected = true;
end

% 地面慢车点采用直接扭矩边界。扭矩由126 kW和0.70Np0换算，并使用
% 已固化的126 kW严格收敛解作为初值。
i = size(defs, 1) + 1;
idleCfg = testCfg.groundIdle;
points(i).point_id = 'S2.3.2-07';
points(i).case_name = 'GroundIdle_Npr70_DirectTorque';
points(i).dataset_role = 'training';
points(i).description = '地面慢车负载脱开、等效126kW轴系负载点';
points(i).target_Np_ratio = idleCfg.NpRatio;
points(i).target_Np = idleCfg.NpRatio * np0;
points(i).target_Mkp_ratio = idleCfg.MkpRatio;
points(i).target_Mkp = idleCfg.MkpRatio * rotorCfg.designTorqueNm;
loadState = sht_rotor_load_model(points(i).target_Np, ...
    points(i).target_Mkp, rotorCfg, 'directTorque');
points(i).target_load_power = loadState.PloadW;
points(i).target_load_power_ratio = loadState.PloadW / power0;
points(i).load_input_mode = 'directTorque';
points(i).load_connected = idleCfg.loadConnected;
points(i).seed_source_point_id = idleCfg.seedSourcePointId;
end

function point = local_empty_point()
point = struct();
point.point_id = '';
point.case_name = '';
point.dataset_role = '';
point.description = '';
point.target_Np_ratio = NaN;
point.target_Np = NaN;
point.collective_pitch_deg = NaN;
point.k_theta = NaN;
point.target_Mkp = NaN;
point.target_Mkp_ratio = NaN;
point.target_load_power_ratio = NaN;
point.target_load_power = NaN;
point.load_input_mode = '';
point.load_connected = false;
point.seed_source_point_id = '';
end

function local_assert_required_seed(records, index, point)
%LOCAL_ASSERT_REQUIRED_SEED 校验前序工况初值；公共固化初值由其函数自检。
if isempty(point.seed_source_point_id)
    return;
end
% 固化初值由公共函数完成基线一致性检查，不要求它在当前批次中紧邻出现。
if startsWith(point.seed_source_point_id, 'six_component_')
    return;
end
previous = records(index - 1);
if ~strcmp(previous.point_id, point.seed_source_point_id) || ...
        ~previous.trim_converged
    error('SHT:TestDataGen:RequiredSeedUnavailable', ...
        ['工况%s要求使用已收敛工况%s作为初值，但紧邻前一点为%s，' ...
         'trim_converged=%d。'], ...
        point.point_id, point.seed_source_point_id, previous.point_id, ...
        previous.trim_converged);
end
end

function zSeed = local_predict_seed(~, ~, previous)
%LOCAL_PREDICT_SEED 采用上一个收敛点，避免跨部件特性分支盲目外推。
% 前两个占位输入保留在接口中，便于以后按工况拓扑选择邻近种子。
zSeed = previous(:);
end

function scale = local_variable_scale(cfg, variableCount)
%LOCAL_VARIABLE_SCALE 六部件共同工作变量与 Wf 的牛顿变量尺度。
if variableCount == 9
    scale = [10; 1; 1; 5; 5; 5; 5; ...
        cfg.engine.initial.Np0; cfg.engine.initial.Ng0; 0.3];
elseif variableCount == 6
    scale = [10; 1; 5; 5; ...
        cfg.engine.initial.Np0; cfg.engine.initial.Ng0; 0.3];
else
    error('SHT:TestDataGen:UnexpectedVariableCount', ...
        'DLL 返回 %d 个共同工作变量，当前程序仅支持三部件6个或六部件9个。', ...
        variableCount);
end
end

function ev = local_run_design_seed(cfg, testCfg)
%LOCAL_RUN_DESIGN_SEED 获取设计点迭代变量种子。
% sht_simulate_control_m 会自行打开/关闭 GTESS 库，因此本脚本只在
% RunOnePoint/RunSteadyComponents 局部调用期间持有 engine 句柄。
engine = sht_engine_open(cfg.engine);
cleanup = onCleanup(@() sht_engine_close(engine));
ev = local_run_onepoint(engine, cfg, testCfg, ...
    cfg.engine.initial.Wf0, cfg.engine.initial.power0, []);
clear cleanup;
end

function trim = local_trim_with_engine(cfg, testCfg, point, zSeed)
%LOCAL_TRIM_WITH_ENGINE 在局部 engine 生命周期内完成单工况稳态配平。
engine = sht_engine_open(cfg.engine);
cleanup = onCleanup(@() sht_engine_close(engine));
trim = local_trim_at_condition(engine, cfg, testCfg, point, zSeed);
clear cleanup;
end

function trim = local_global_continuation_fallback(cfg, testCfg, point, primaryTrim)
%LOCAL_GLOBAL_CONTINUATION_FALLBACK 局部Newton失败后的同口径延拓回退。
% 常规点先使用邻近收敛点，慢车点先使用固化初值。只有局部求解失败时
% 才从设计点沿负载/转速分阶段延拓；进口模式、健康调度和修正系数均
% 与主路径保持一致，不允许用另一套边界得到表面收敛结果。
trim = primaryTrim;
try
    globalTrim = sht_trim_health_steady_point( ...
        cfg, point.target_Np, point.target_load_power, testCfg.health);
catch trimErr
    trim.strategy = 'point_seed_and_global_continuation_failed';
    trim.fallbackUsed = true;
    trim.fallbackError = trimErr.message;
    return;
end

engine = sht_engine_open(cfg.engine);
cleanup = onCleanup(@() sht_engine_close(engine));
ev = local_run_onepoint(engine, cfg, testCfg, globalTrim.Wf, ...
    point.target_load_power, globalTrim.varIte);
clear cleanup;
f = local_residual(ev, point.target_Np);
converged = globalTrim.converged && ...
    local_is_converged(ev, f, testCfg, point.target_Np);
trim = local_pack_trim(globalTrim.z, ev, f, ...
    primaryTrim.iter + globalTrim.iteration, converged, ...
    norm(f, inf), globalTrim.jacobianConditionNumber);
trim.seedSourcePointId = point.seed_source_point_id;
trim.fallbackUsed = true;
trim.strategy = 'point_seed_then_global_continuation';
trim.primaryAttemptNormF = primaryTrim.normF;
trim.primaryAttemptIterations = primaryTrim.iter;
trim.fallbackError = '';
end

function trim = local_trim_at_condition(engine, cfg, testCfg, point, z0)
%LOCAL_TRIM_AT_CONDITION 对单个工况点进行外层稳态配平。
z = z0(:);
z(end) = min(max(z(end), testCfg.wfMin), testCfg.wfMax);

ev = local_eval_steady(engine, cfg, testCfg, point, z);
f = local_residual(ev, point.target_Np);
bestNorm = norm(f, inf);
trim = local_pack_trim(z, ev, f, 0, false, bestNorm, Inf);

for iter = 1:testCfg.maxNewtonIter
    if local_is_converged(ev, f, testCfg, point.target_Np)
        evFinal = local_run_onepoint(engine, cfg, testCfg, z(end), ...
            point.target_load_power, z(1:end-1));
        trim = local_pack_trim(z, evFinal, f, iter - 1, true, norm(f, inf), trim.condJ);
        return;
    end

    [jac, condJ] = local_jacobian(engine, cfg, testCfg, point, z, f);
    if ~all(isfinite(jac(:))) || rcond(jac) < 1e-14
        trim = local_pack_trim(z, ev, f, iter - 1, false, norm(f, inf), condJ);
        return;
    end

    dzNorm = -(jac \ f);
    dz = dzNorm(:) .* testCfg.scale(:);
    [zTrial, evTrial, fTrial, accepted] = local_line_search( ...
        engine, cfg, testCfg, point, z, dz, bestNorm);

    if ~accepted
        trim = local_pack_trim(z, ev, f, iter - 1, false, norm(f, inf), condJ);
        return;
    end

    z = zTrial;
    ev = evTrial;
    f = fTrial;
    bestNorm = norm(f, inf);
    trim = local_pack_trim(z, ev, f, iter, false, bestNorm, condJ);
end

finalConverged = local_is_converged(ev, f, testCfg, point.target_Np);
if finalConverged
    ev = local_run_onepoint(engine, cfg, testCfg, z(end), ...
        point.target_load_power, z(1:end-1));
end
trim = local_pack_trim(z, ev, f, testCfg.maxNewtonIter, ...
    finalConverged, norm(f, inf), trim.condJ);
end

function tf = local_is_converged(ev, f, testCfg, targetNp)
% DLL_SHT_RunSteadyComponents 只计算给定稳态变量的残差，不更新
% convergeTag；因此外层配平收敛只看匹配残差和目标转速误差。
tf = ev.ret == 0 && max(abs(f(1:end-1))) <= testCfg.residualTol ...
    && abs(ev.output.Np - targetNp) <= testCfg.npTolRpm;
end

function [jac, condJ] = local_jacobian(engine, cfg, testCfg, point, z, f0)
n = numel(z);
jac = zeros(n, n);
for j = 1:n
    dz = testCfg.normalizedPerturb * testCfg.scale(j);
    zp = z;
    zm = z;
    zp(j) = zp(j) + dz;
    zm(j) = zm(j) - dz;
    zp(end) = min(max(zp(end), testCfg.wfMin), testCfg.wfMax);
    zm(end) = min(max(zm(end), testCfg.wfMin), testCfg.wfMax);

    if zp(j) ~= z(j) && zm(j) ~= z(j)
        fp = local_residual(local_eval_steady(engine, cfg, testCfg, point, zp), point.target_Np);
        fm = local_residual(local_eval_steady(engine, cfg, testCfg, point, zm), point.target_Np);
        jac(:, j) = (fp - fm) / (2 * testCfg.normalizedPerturb);
    elseif zp(j) ~= z(j)
        fp = local_residual(local_eval_steady(engine, cfg, testCfg, point, zp), point.target_Np);
        jac(:, j) = (fp - f0) / testCfg.normalizedPerturb;
    elseif zm(j) ~= z(j)
        fm = local_residual(local_eval_steady(engine, cfg, testCfg, point, zm), point.target_Np);
        jac(:, j) = (f0 - fm) / testCfg.normalizedPerturb;
    else
        jac(:, j) = NaN;
    end
end

s = svd(jac);
if isempty(s) || min(s) == 0
    condJ = Inf;
else
    condJ = max(s) / min(s);
end
end

function [zTrial, evTrial, fTrial, accepted] = local_line_search( ...
    engine, cfg, testCfg, point, z, dz, currentNorm)
accepted = false;
zTrial = z;
evTrial = local_eval_steady(engine, cfg, testCfg, point, z);
fTrial = local_residual(evTrial, point.target_Np);

for alpha = [1 0.5 0.25 0.125 0.0625 0.03125]
    zCandidate = z + alpha * dz;
    zCandidate(end) = min(max(zCandidate(end), testCfg.wfMin), testCfg.wfMax);
    evCandidate = local_eval_steady(engine, cfg, testCfg, point, zCandidate);
    fCandidate = local_residual(evCandidate, point.target_Np);
    candidateNorm = norm(fCandidate, inf);
    if isfinite(candidateNorm) && candidateNorm < currentNorm
        zTrial = zCandidate;
        evTrial = evCandidate;
        fTrial = fCandidate;
        accepted = true;
        return;
    end
end
end

function ev = local_run_onepoint(engine, cfg, testCfg, wf, power, seed)
if ~isempty(seed)
    local_set_seed(engine, seed);
end
stepInValue = local_step_in(cfg, testCfg, wf, power);
engPtrInit.eng = libstruct(engine.engineStructName);
engPtr = libstruct(engine.enginePointerName, engPtrInit);
stepIn = libpointer('doublePtr', stepInValue);
stepOut = libpointer('doublePtr', zeros(128, 1));
[ret, ~, stepOutValue, engOut] = calllib(engine.libraryName, ...
    'DLL_SHT_RunOnePoint', stepIn, stepOut, engPtr);
ev = local_pack_eval( ...
    ret, stepOutValue, engOut.eng, wf, power, testCfg.hpsPower, ...
    cfg.engine.modelMode);
end

function ev = local_eval_steady(engine, cfg, testCfg, point, z)
stepInValue = local_step_in(cfg, testCfg, z(end), point.target_load_power);
stepInValue(21:(20 + testCfg.variableCount)) = z(1:end-1);
engPtrInit.eng = libstruct(engine.engineStructName);
engPtr = libstruct(engine.enginePointerName, engPtrInit);
stepIn = libpointer('doublePtr', stepInValue);
stepOut = libpointer('doublePtr', zeros(128, 1));
[ret, ~, stepOutValue, engOut] = calllib(engine.libraryName, ...
    'DLL_SHT_RunSteadyComponents', stepIn, stepOut, engPtr);
ev = local_pack_eval(ret, stepOutValue, engOut.eng, z(end), ...
    point.target_load_power, testCfg.hpsPower, cfg.engine.modelMode);
end

function stepInValue = local_step_in(cfg, testCfg, wf, power)
stepInValue = zeros(512, 1);
stepInValue(1:10) = [ ...
    cfg.engine.initial.Np0, ...
    cfg.engine.initial.Ng0, ...
    wf, ...
    testCfg.A8, ...
    0, ...
    power, ...
    testCfg.hpsPower, ...
    0, ...
    testCfg.hpcAlpha, ...
    0];
[stepInValue, inletBoundaryDetail] = ...
    sht_apply_inlet_boundary_stepin(stepInValue, testCfg.benchEnvironment);
assert(inletBoundaryDetail.mode == 2 && ...
    ~inletBoundaryDetail.directPt1InputUsed && ...
    ~inletBoundaryDetail.pt2InputUsed, ...
    '稳态替代数据必须使用模式2，且不得把Pt2写入进口边界输入。');
% stepIn(18) 是修正系数调度总开关。关闭时 DLL 仍按历史方式直接
% 使用 stepIn(41:199) 中的常值；打开时 DLL 在已初始化的31张表上
% 计算 K_eff=k_design+Delta(x)。稳态配平和单点回放必须显式一致。
stepInValue(18) = double(testCfg.healthScheduleEnabled);
health = testCfg.health(:);
stepInValue(41:(40 + numel(health))) = health;
end

function local_set_seed(engine, seed)
stepInValue = zeros(512, 1);
stepInValue(21:(20 + numel(seed))) = seed(:);
engPtrInit.eng = libstruct(engine.engineStructName);
engPtr = libstruct(engine.enginePointerName, engPtrInit);
stepIn = libpointer('doublePtr', stepInValue);
stepOut = libpointer('doublePtr', zeros(128, 1));
calllib(engine.libraryName, 'DLL_SHT_varIteInit', stepIn, stepOut, engPtr);
end

function f = local_residual(ev, targetNp)
variableCount = numel(ev.varIte);
f = zeros(variableCount + 1, 1);
f(1:variableCount) = ev.stepOut(1:variableCount);
f(end) = (ev.output.Np - targetNp) / targetNp;
end

function ev = local_pack_eval(ret, stepOutValue, eng, wf, power, hpsPower, modelMode)
ev = struct();
ev.ret = ret;
ev.stepOut = stepOutValue(:);
ev.wf = wf;
ev.power = power;
ev.convergeTag = eng.convergeTag;
ev.residual = eng.errOut(1:eng.varVecDime).';
ev.maxErr = max(abs([ev.residual; eng.Nozzle.y(end)]));
ev.varIte = eng.varIte(1:eng.varVecDime).';
ev.engineSnapshot = eng;
ev.output = local_pack_output(eng, wf, power, hpsPower, ev.maxErr, modelMode);
end

function y = local_pack_output(eng, wf, power, hpsPower, maxErr, modelMode)
%LOCAL_PACK_OUTPUT 按 2.3.1 默认字段集组织模型输出。
if modelMode == 1
    hpcOut = eng.HPC2;
    gtOut = eng.HPT2;
    ptOut = eng.LPT2;
else
    hpcOut = eng.HPC;
    gtOut = eng.HPT;
    ptOut = eng.LPT;
end
y = struct();
y.Pt1 = eng.Ambient.gasPathOut(4);
y.Tt1 = eng.Ambient.gasPathOut(3);
y.Pt2 = eng.Inlet.gasPathOut(4);
y.Tt2 = eng.Inlet.gasPathOut(3);
y.Pamb = eng.Ambient.y(5);
y.Tamb = eng.Ambient.y(6);
y.Altitude = eng.altitude;
y.Mach = eng.machNumber;
y.Pt3 = hpcOut.y(4);
y.Tt3 = hpcOut.y(3);
y.Pt45 = gtOut.y(4);
y.Tt45 = gtOut.y(3);
y.Pt5 = ptOut.y(4);
y.Tt5 = ptOut.y(3);
y.Np = eng.LPS_Nmech;
y.Ng = eng.HPS_Nmech;
y.Wf = wf;
y.Mkp = power / max(y.Np*pi/30, eps);
y.Mkg = hpsPower / max(y.Ng*pi/30, eps);
y.target_load_power = power;
y.shaft_power = power;
y.PTDriveTorque = eng.LPS_Trq;
y.GTInternalNetTorque = eng.HPS_Trq;
y.Theta = y.Tt1 / 288.15;
y.Deta = y.Pt2 / 101325;
y.Ngc = y.Ng / sqrt(max(y.Theta, eps));
y.PRc = y.Pt3 / max(y.Pt2, eps);
% 六部件模式下 eng.HPC 为轴流压气机，y(16) 是以 HPC/AC 进口
% 总温为基准、并按特性图设计换算转速归一化后的相对换算转速。
y.HPC_Ncr = eng.HPC.y(16);
y.HpcStallMargin = eng.HPC.y(8);
if modelMode == 1
    y.HpcStallMargin = min(y.HpcStallMargin, eng.HPC2.y(8));
end
y.HptBeta = gtOut.y(16);
y.LptBeta = ptOut.y(16);
y.FAR = eng.Burner.y(5);
y.T4 = eng.Burner.y(3);
if modelMode == 1
    y.ErrHPC = max(abs(eng.errOut(1:2)));
    y.ErrHPT = max(abs(eng.errOut(3:4)));
    y.ErrLPT = max(abs(eng.errOut(5:6)));
    y.ErrNozzle = eng.errOut(7);
    y.ErrLPS = eng.errOut(8);
    y.ErrHPS = eng.errOut(9);
else
    y.ErrHPC = eng.errOut(1);
    y.ErrHPT = eng.errOut(2);
    y.ErrLPT = eng.errOut(3);
    y.ErrNozzle = eng.errOut(4);
    y.ErrLPS = eng.errOut(5);
    y.ErrHPS = eng.errOut(6);
end
y.ErrNozzleEnd = eng.Nozzle.y(end);
y.max_model_error = maxErr;
end

function [summary, truthSummary, timeHistory] = local_run_controlled_steady_simulation(cfg, testCfg, point, trim)
%LOCAL_RUN_CONTROLLED_STEADY_SIMULATION 执行单工况 20 s 闭环稳态仿真。
simCfg = local_control_sim_config(cfg, testCfg, point, trim);
summary = local_empty_sim_summary(testCfg);
truthSummary = local_empty_sim_summary(testCfg);
timeHistory = struct();
timeHistory.point_id = point.point_id;
timeHistory.case_name = point.case_name;
timeHistory.errorMessage = '';

try
    simResult = sht_simulate_control_m(simCfg);
    mask = local_steady_window_mask(simResult.log.time, testCfg);
    truthLog = local_prepare_truth_log(simResult.log, point);
    [measuredLog, sensorError] = local_apply_test_measurement_error( ...
        truthLog, simResult.log, point, testCfg);

    truthSummary = local_pack_simulation_summary(truthLog, mask, point, testCfg);
    summary = local_pack_simulation_summary(measuredLog, mask, point, testCfg);

    timeHistory.time = truthLog.time;
    timeHistory.log = measuredLog;
    timeHistory.logMeasured = measuredLog;
    timeHistory.logTrue = truthLog;
    timeHistory.sensorError = sensorError;
    timeHistory.windowMask = mask;
    timeHistory.summary = summary;
    timeHistory.summaryTrue = truthSummary;
catch simErr
    summary.errorMessage = simErr.message;
    truthSummary.errorMessage = simErr.message;
    timeHistory.errorMessage = simErr.message;
end
end

function log = local_prepare_truth_log(log, point)
%LOCAL_PREPARE_TRUTH_LOG 补充按点定义的权威负载输入及派生负载真值。
if isfield(log, 'time')
    n = numel(log.time);
else
    n = 0;
end
if isfield(log, 'Pload') && numel(log.Pload) == n
    log.target_load_power = log.Pload(:);
else
    log.target_load_power = log.Mkp(:) .* log.Np(:) * pi / 30;
end
if isfield(log, 'thetaCollectiveDeg') && numel(log.thetaCollectiveDeg) == n
    log.collective_pitch_deg = log.thetaCollectiveDeg(:);
else
    log.collective_pitch_deg = point.collective_pitch_deg * ones(n, 1);
end
if isfield(log, 'kTheta') && numel(log.kTheta) == n
    log.k_theta = log.kTheta(:);
else
    log.k_theta = point.k_theta * ones(n, 1);
end
% 原始控制日志中的Ngc/Theta/Deta是控制器实际采样量。构造真值层时
% 必须改由无误差基础信号重算，防止把测量派生量误标为试车数据真值。
log = local_rebuild_log_derived_quantities(log, 'true');
% 原始控制日志保留内部兼容字段；对外试车数据只发布规范字段Tt45。
if isfield(log, 'T45')
    log = rmfield(log, 'T45');
end
end

function [measuredLog, sensorError] = local_apply_test_measurement_error(truthLog, rawLog, point, testCfg)
%LOCAL_APPLY_TEST_MEASUREMENT_ERROR 汇总闭环传感器输出，形成试车数据测量值。
measuredLog = truthLog;
sensorError = struct();
sensorError.enabled = testCfg.measurementError.enabled;
sensorError.randomSeed = testCfg.measurementError.randomSeed;
sensorError.point_id = point.point_id;
sensorError.applied = repmat(struct('name', '', 'bias', NaN, 'noiseStdMean', NaN, ...
    'biasMin', NaN, 'biasMax', NaN, 'noiseStdMax', NaN, ...
    'timeConstant', NaN, 'mode', '', 'unit', '', 'source', '', ...
    'flowDriftEnabled', false), 0, 1);

if ~testCfg.measurementError.enabled || ~isfield(truthLog, 'time') || isempty(truthLog.time)
    return;
end

specs = testCfg.measurementError.fields;
mappings = local_sensor_output_mappings();
for i = 1:numel(mappings)
    [spec, found] = local_find_measurement_spec(specs, mappings(i).name);
    if ~found || ~isfield(truthLog, spec.name)
        continue;
    end
    if ~isfield(rawLog, mappings(i).sampleField)
        error('SHT:TestDataGen:MissingSensorLog', ...
            '闭环传感器日志缺少字段 %s，无法生成 %s 测量值。', ...
            mappings(i).sampleField, mappings(i).name);
    end
    measuredLog.(mappings(i).name) = rawLog.(mappings(i).sampleField)(:);

    truthValue = truthLog.(spec.name)(:);
    [bias, sigma] = local_measurement_error_bias_sigma( ...
        truthValue, spec, local_measurement_flow(truthLog, numel(truthValue)));
    sensorError.applied(end + 1, 1) = ...
        local_sensor_error_item(spec, bias, sigma, 'closed_loop_sensor'); %#ok<AGROW>
end

% 与控制器保持同一物理定义：派生量不能独立叠加误差，而应由完成传感器
% 动态、偏置和噪声处理后的基础测量值重算。
measuredLog = local_rebuild_log_derived_quantities(measuredLog, 'measured');

% 负载功率不设置独立传感器误差。当前接口以 Mkp 为可测负载边界，
% 功率由同一时刻的 Mkp 与 Np 测量值派生，保证三者满足运动学恒等式。
if isfield(measuredLog, 'Mkp') && isfield(measuredLog, 'Np')
    measuredLog.target_load_power = ...
        measuredLog.Mkp(:) .* measuredLog.Np(:) * pi / 30;
end

% Wf 不进入反馈传感器向量，但交付给参数估计的燃油记录仍需加入测量误差。
stream = RandStream('mt19937ar', ...
    'Seed', local_point_noise_seed(testCfg.measurementError.randomSeed + 500000, point.point_id));
recordOnlyNames = {'Wf'};
for i = 1:numel(recordOnlyNames)
    [spec, found] = local_find_measurement_spec(specs, recordOnlyNames{i});
    if ~found || ~isfield(truthLog, spec.name)
        continue;
    end
    truthValue = truthLog.(spec.name)(:);
    [measuredValue, item] = local_record_only_sensor_measurement( ...
        truthLog.time(:), truthValue, spec, stream, ...
        local_measurement_flow(truthLog, numel(truthValue)));
    measuredLog.(spec.name) = measuredValue;
    sensorError.applied(end + 1, 1) = item; %#ok<AGROW>
end
end

function log = local_rebuild_log_derived_quantities(log, layerName)
%LOCAL_REBUILD_LOG_DERIVED_QUANTITIES 保持真值层和测量层的派生量自洽。
required = {'Ng', 'Pt2', 'Tt1'};
for i = 1:numel(required)
    name = required{i};
    if ~isfield(log, name)
        error('SHT:TestDataGen:MissingDerivedSource', ...
            '%s层缺少派生量源字段%s。', layerName, name);
    end
end
ng = log.Ng(:);
pt2 = log.Pt2(:);
tt1 = log.Tt1(:);
if numel(ng) ~= numel(pt2) || numel(ng) ~= numel(tt1)
    error('SHT:TestDataGen:DerivedSourceLength', ...
        '%s层的Ng、Pt2和Tt1长度不一致。', layerName);
end
if any(~isfinite(ng)) || any(~isfinite(pt2) | pt2 <= 0) || ...
        any(~isfinite(tt1) | tt1 <= 0)
    error('SHT:TestDataGen:InvalidDerivedSource', ...
        '%s层的Ng必须有限，Pt2和Tt1必须为有限正数。', layerName);
end
log.Theta = tt1 / 288.15;
log.Deta = pt2 / 101325;
log.Ngc = ng ./ sqrt(log.Theta);
end

function seed = local_point_noise_seed(baseSeed, pointId)
%LOCAL_POINT_NOISE_SEED 为每个工况点生成可复现的白噪声种子。
tokens = regexp(pointId, '(\d+)$', 'tokens', 'once');
if isempty(tokens)
    pointNumber = sum(double(pointId));
else
    pointNumber = str2double(tokens{1});
end
seed = baseSeed + 1009 * pointNumber;
end

function [bias, sigma] = local_measurement_error_bias_sigma( ...
        truthValue, spec, inletFlow)
%LOCAL_MEASUREMENT_ERROR_BIAS_SIGMA 根据通道类型计算偏置和逐采样噪声标准差。
if nargin >= 3 && isfield(spec, 'sharedBiasEnabled') && ...
        spec.sharedBiasEnabled
    lookupName = spec.name;
    if strcmp(lookupName, 'Tt45')
        lookupName = 'T45';
    end
    bias = sht_measurement_bias_generator( ...
        'evaluate', inletFlow, {lookupName});
    bias = bias(:, 1);
else
    bias = [];
end
switch spec.mode
    case 'relative'
        if isempty(bias), bias = spec.biasValue .* truthValue; end
        sigma = max(abs(spec.noiseValue .* truthValue), eps);
    case 'scale'
        if isempty(bias)
            bias = spec.biasValue .* spec.reference .* ones(size(truthValue));
        end
        sigma = abs(spec.noiseValue .* spec.reference) .* ones(size(truthValue));
    case 'absolute'
        if isempty(bias), bias = spec.biasValue .* ones(size(truthValue)); end
        sigma = abs(spec.noiseValue) .* ones(size(truthValue));
    otherwise
        error('SHT:TestDataGen:InvalidMeasurementErrorMode', ...
            '未知试车测量误差模式：%s', spec.mode);
end
end

function mappings = local_sensor_output_mappings()
%LOCAL_SENSOR_OUTPUT_MAPPINGS 闭环传感器日志字段到试车测量数据字段的映射。
mappings = struct( ...
    'name', {'Np', 'Ng', 'Tt45', 'Mkp', 'Mkg', 'Pt2', 'Tt1', ...
        'Pt3', 'Tt3', 'Pt45', 'Tamb', 'Pamb', 'Altitude', 'Mach'}, ...
    'sampleField', {'sampleNp', 'sampleNg', 'sampleTt45', 'sampleMkp', ...
        'sampleMkg', 'samplePt2', 'sampleTt1', 'samplePt3', 'sampleTt3', ...
        'samplePt45', 'sampleTamb', 'samplePamb', ...
        'sampleAltitude', 'sampleMach'});
end

function [spec, found] = local_find_measurement_spec(specs, name)
%LOCAL_FIND_MEASUREMENT_SPEC 按字段名查找试车测量误差配置。
names = {specs.name};
idx = find(strcmp(names, name), 1, 'first');
found = ~isempty(idx);
if found
    spec = specs(idx);
else
    spec = struct();
end
end

function [measuredValue, item] = local_record_only_sensor_measurement( ...
        time, truthValue, spec, stream, inletFlow)
%LOCAL_RECORD_ONLY_SENSOR_MEASUREMENT 为非反馈记录量生成测量值。
[bias, sigma] = local_measurement_error_bias_sigma( ...
    truthValue, spec, inletFlow);
dynamicValue = local_first_order_filter_signal(time, truthValue, spec.timeConstant);
measuredValue = dynamicValue + bias + sigma .* randn(stream, size(truthValue));
item = local_sensor_error_item(spec, bias, sigma, 'record_only_sensor');
end

function filtered = local_first_order_filter_signal(time, rawValue, timeConstant)
%LOCAL_FIRST_ORDER_FILTER_SIGNAL 对记录型真实信号施加FOH一阶传感器动态。
filtered = sht_first_order_foh_filter(time, rawValue, timeConstant);
end

function item = local_sensor_error_item(spec, bias, sigma, source)
%LOCAL_SENSOR_ERROR_ITEM 记录单个测量通道的误差配置摘要。
item = struct();
item.name = spec.name;
item.bias = local_mean_vector(bias);
item.biasMin = min(bias);
item.biasMax = max(bias);
item.noiseStdMean = local_mean_vector(sigma);
item.noiseStdMax = local_max_abs_vector(sigma);
item.timeConstant = spec.timeConstant;
item.mode = spec.mode;
item.unit = spec.unit;
item.source = source;
item.flowDriftEnabled = isfield(spec, 'flowDriftEnabled') && ...
    spec.flowDriftEnabled;
end

function flow = local_measurement_flow(logData, expectedLength)
%LOCAL_MEASUREMENT_FLOW 读取无误差入口空气流量，禁止使用带噪Wf替代。
if ~isfield(logData, 'WIn') || ~isnumeric(logData.WIn) || ...
        numel(logData.WIn) ~= expectedLength || ...
        any(~isfinite(logData.WIn(:)))
    error('SHT:TestDataGen:MissingBiasFlow', ...
        '测量偏置生成需要与时间轴等长的有限 WIn 真值。');
end
flow = logData.WIn(:);
end

function simCfg = local_control_sim_config(cfg, testCfg, point, trim)
%LOCAL_CONTROL_SIM_CONFIG 为当前稳态点构造恒定指令闭环仿真配置。
y0 = trim.ev.output;
simCfg = cfg;
simCfg.stopTime = testCfg.simulationStopTime;
simCfg.throwOnEngineNonconvergence = false;

% 发动机、执行机构和控制器初值取自外层稳态配平点，避免 20 s 仿真开始时出现
% 与目标工况无关的初始冲击。
simCfg.engine.initial.Np0 = y0.Np;
simCfg.engine.initial.Ng0 = y0.Ng;
if isfield(simCfg.engine.initial, 'state')
    simCfg.engine.initial = rmfield(simCfg.engine.initial, 'state');
end
simCfg.engine.initial.Wf0 = y0.Wf;
simCfg.engine.initial.power0 = point.target_load_power;
simCfg.engine.initial.A80 = testCfg.A8;
simCfg.engine.initial.T45 = y0.Tt45;
simCfg.engine.initial.Mkp = y0.Mkp;
simCfg.engine.initial.Mkg = y0.Mkg;

simCfg.engine.boundary.A8 = testCfg.A8;
simCfg.engine.boundary.power = point.target_load_power;
simCfg.engine.boundary.hpsPower = testCfg.hpsPower;
simCfg.engine.boundary.Mkp = point.target_Mkp;
simCfg.engine.boundary.Mkg = 0;
simCfg.engine.boundary.ptLoadInputMode = 'torque';
simCfg.engine.boundary.gtLoadInputMode = 'torque';
simCfg.engine.boundary.hpcAlpha = testCfg.hpcAlpha;
simCfg.engine.boundary.health = testCfg.health;
simCfg.engine.boundary.healthScheduleEnabled = testCfg.healthScheduleEnabled;
simCfg.engine.boundary.inletBoundaryMode = ...
    testCfg.benchEnvironment.inletBoundaryMode;
simCfg.engine.boundary.altitude = testCfg.benchEnvironment.altitude;
simCfg.engine.boundary.Mach = testCfg.benchEnvironment.Mach;
simCfg.engine.boundary.deltaTemperature = ...
    testCfg.benchEnvironment.deltaTemperature;
simCfg.engine.boundary.Pamb = testCfg.benchEnvironment.Pamb;
simCfg.engine.boundary.Tamb = testCfg.benchEnvironment.Tamb;
if isfield(simCfg.engine.boundary, 'Pt1')
    simCfg.engine.boundary = rmfield(simCfg.engine.boundary, 'Pt1');
end
if isfield(simCfg.engine.boundary, 'Tt1')
    simCfg.engine.boundary = rmfield(simCfg.engine.boundary, 'Tt1');
end
simCfg.engine.healthScheduleProfile = testCfg.healthScheduleProfile;

simCfg.flight.rotorLoad = testCfg.rotorLoad;
simCfg.flight.rotorLoad.enabled = true;
simCfg.flight.rotorLoad.inputMode = point.load_input_mode;

% 本步骤生成稳态台架替代数据，不叠加转速或负载脉冲。
simCfg.reference.baseNp = point.target_Np;
simCfg.reference.baseNg = y0.Ng;
simCfg.reference.npPulseAmplitude = 0;
simCfg.reference.npPulsePeriod = max(100, 10 * testCfg.simulationStopTime);
simCfg.reference.npPulseWidthFraction = 0;
simCfg.reference.npPulsePhaseDelay = testCfg.simulationStopTime + 1;
simCfg.reference.enablePowerPulse = false;
simCfg.reference.powerBase = point.target_load_power;
simCfg.reference.powerPulseAmplitude = 0;
if isfield(simCfg.reference, 'commandMode')
    simCfg.reference = rmfield(simCfg.reference, 'commandMode');
end
switch lower(point.load_input_mode)
    case 'collectivepitch'
        simCfg.reference.collectivePitch = struct( ...
            'enabled', true, ...
            'commandMode', 'schedule', ...
            'scheduleTime_s', [0, testCfg.simulationStopTime], ...
            'scheduleTheta_deg', ...
                [point.collective_pitch_deg, point.collective_pitch_deg], ...
            'interpolationMethod', 'previous');
    case 'directtorque'
        simCfg.flight.rotorLoad.directTorqueCommandNm = point.target_Mkp;
        simCfg.reference.collectivePitch = struct('enabled', false);
    otherwise
        error('SHT:TestDataGen:UnsupportedPointLoadMode', ...
            '工况%s使用了不支持的负载输入模式%s。', ...
            point.point_id, point.load_input_mode);
end

simCfg.sensor.channels = local_sensor_channel_names();
if testCfg.measurementError.enabled
    % 试车传感器误差进入闭环反馈；非反馈记录量在仿真后使用同一误差规格单独生成。
    simCfg.sensor.mode = 'firstOrder';
    [simCfg.sensor.bias, simCfg.sensor.noiseStd, simCfg.sensor.timeConstant] = ...
        local_sensor_error_vectors(simCfg.sensor.channels, testCfg.measurementError.fields);
    simCfg.sensor.randomSeed = local_point_noise_seed(testCfg.measurementError.randomSeed, point.point_id);
    simCfg.sensor.biasModel = struct('enabled', true);
else
    simCfg.sensor.mode = 'identity';
    simCfg.sensor.bias = zeros(numel(simCfg.sensor.channels), 1);
    simCfg.sensor.noiseStd = zeros(numel(simCfg.sensor.channels), 1);
    simCfg.sensor.timeConstant = zeros(numel(simCfg.sensor.channels), 1);
    simCfg.sensor.randomSeed = 1;
    simCfg.sensor.biasModel = struct('enabled', false);
end
end

function names = local_sensor_channel_names()
names = {'Np', 'Ng', 'Tt45', 'Mkp', 'Ngc', 'Theta', 'Deta', ...
    'Pt2', 'Tt1', 'Pt3', 'Tt3', 'Pt45', 'Tt45', 'Pt5', 'Tt5', ...
    'HpcStallMargin', 'FAR', 'T4', 'Mkg', 'Pamb', 'Tamb', ...
    'Altitude', 'Mach'};
end

function [bias, noiseStd, timeConstant] = local_sensor_error_vectors(channelNames, specs)
%LOCAL_SENSOR_ERROR_VECTORS 将试车测量误差规格映射到闭环传感器向量。
n = numel(channelNames);
bias = zeros(n, 1);
noiseStd = zeros(n, 1);
timeConstant = zeros(n, 1);
for i = 1:n
    [spec, found] = local_find_measurement_spec(specs, channelNames{i});
    if ~found
        continue;
    end
    bias(i) = spec.biasValue;
    noiseStd(i) = abs(spec.noiseValue);
    timeConstant(i) = spec.timeConstant;
end
end

function mask = local_steady_window_mask(time, testCfg)
t = time(:);
tol = max(1e-12, testCfg.simulationStopTime * 1e-12);
mask = t >= testCfg.steadyWindowStartTime - tol ...
    & t <= testCfg.steadyWindowEndTime + tol;
end

function summary = local_pack_simulation_summary(logInput, mask, point, testCfg)
%LOCAL_PACK_SIMULATION_SUMMARY 对指定时间历程求稳态窗口统计量。
if isfield(logInput, 'log')
    log = logInput.log;
else
    log = logInput;
end
summary = local_empty_sim_summary(testCfg);
summary.converged = any(mask);
summary.sample_count = sum(mask);
summary.time_s = local_mean_vector(log.time(mask));

summary.collective_pitch_deg = local_mean_field(log, 'collective_pitch_deg', mask);
summary.k_theta = local_mean_field(log, 'k_theta', mask);
summary.target_load_power = local_mean_field(log, 'target_load_power', mask);
summary.Np = local_mean_field(log, 'Np', mask);
summary.Ng = local_mean_field(log, 'Ng', mask);
summary.HPC_Ncr = local_mean_field(log, 'HPC_Ncr', mask);
summary.Wf = local_mean_field(log, 'Wf', mask);
summary.Tt45 = local_mean_field(log, 'Tt45', mask);
summary.Pt45 = local_mean_field(log, 'Pt45', mask);
summary.Mkp = local_mean_field(log, 'Mkp', mask);
summary.Mkg = local_mean_field(log, 'Mkg', mask);
summary.Pt1_internal = local_mean_field(log, 'Pt1', mask);
summary.Pt2 = local_mean_field(log, 'Pt2', mask);
summary.Tt1 = local_mean_field(log, 'Tt1', mask);
summary.Pt3 = local_mean_field(log, 'Pt3', mask);
summary.Tt3 = local_mean_field(log, 'Tt3', mask);
summary.Pamb = local_mean_field(log, 'Pamb', mask);
summary.Tamb = local_mean_field(log, 'Tamb', mask);
summary.Altitude = local_mean_field(log, 'Altitude', mask);
summary.Mach = local_mean_field(log, 'Mach', mask);
summary.Pt5 = local_mean_field(log, 'Pt5', mask);
summary.Tt5 = local_mean_field(log, 'Tt5', mask);
summary.HpcStallMargin = local_mean_field(log, 'HpcStallMargin', mask);
summary.HptBeta = local_mean_field(log, 'HptBeta', mask);
summary.LptBeta = local_mean_field(log, 'LptBeta', mask);
summary.FAR = local_mean_field(log, 'FAR', mask);
summary.T4 = local_mean_field(log, 'T4', mask);
summary.shaft_power = local_mean_product(log, 'Mkp', 'Np', mask, pi / 30);
summary.Theta = summary.Tt1 / 288.15;
summary.Deta = summary.Pt2 / 101325;
summary.Ngc = summary.Ng / sqrt(max(summary.Theta, eps));
summary.PRc = summary.Pt3 / max(summary.Pt2, eps);
summary.NpError = summary.Np - point.target_Np;
summary.NpErrorAbs = abs(summary.NpError);
summary.max_model_error = local_max_abs_field(log, 'maxErr', mask);
summary.convergeTag = local_max_abs_field(log, 'convergeTag', mask);
summary.std_Np = local_std_field(log, 'Np', mask);
summary.std_HPC_Ncr = local_std_field(log, 'HPC_Ncr', mask);
summary.std_Wf = local_std_field(log, 'Wf', mask);
summary.std_Tt45 = local_std_field(log, 'Tt45', mask);
summary.max_abs_Np_error = local_max_abs_vector(log.Np(mask) - point.target_Np);

summary.converged = summary.converged ...
    && summary.sample_count >= testCfg.minSteadyWindowSamples ...
    && isfinite(summary.Np) ...
    && isfinite(summary.max_model_error);
end

function summary = local_empty_sim_summary(testCfg)
summary = struct();
summary.converged = false;
summary.errorMessage = '';
summary.time_s = NaN;
summary.startTime = testCfg.steadyWindowStartTime;
summary.endTime = testCfg.steadyWindowEndTime;
summary.sample_count = 0;
summary.collective_pitch_deg = NaN;
summary.k_theta = NaN;
summary.target_load_power = NaN;
summary.Np = NaN;
summary.Ng = NaN;
summary.HPC_Ncr = NaN;
summary.Wf = NaN;
summary.Tt45 = NaN;
summary.Pt45 = NaN;
summary.Mkp = NaN;
summary.Mkg = NaN;
summary.shaft_power = NaN;
summary.Pt1_internal = NaN;
summary.Pt2 = NaN;
summary.Tt1 = NaN;
summary.Pt3 = NaN;
summary.Tt3 = NaN;
summary.Pamb = NaN;
summary.Tamb = NaN;
summary.Altitude = NaN;
summary.Mach = NaN;
summary.Pt5 = NaN;
summary.Tt5 = NaN;
summary.Theta = NaN;
summary.Deta = NaN;
summary.Ngc = NaN;
summary.PRc = NaN;
summary.NpError = NaN;
summary.NpErrorAbs = NaN;
summary.convergeTag = NaN;
summary.max_model_error = NaN;
summary.std_Np = NaN;
summary.std_HPC_Ncr = NaN;
summary.std_Wf = NaN;
summary.std_Tt45 = NaN;
summary.max_abs_Np_error = NaN;
summary.HpcStallMargin = NaN;
summary.HptBeta = NaN;
summary.LptBeta = NaN;
summary.FAR = NaN;
summary.T4 = NaN;
end

function value = local_mean_field(s, name, mask)
if isfield(s, name)
    value = local_mean_vector(s.(name)(mask));
else
    value = NaN;
end
end

function value = local_mean_vector(values)
values = values(isfinite(values));
if isempty(values)
    value = NaN;
else
    value = mean(values);
end
end

function value = local_std_field(s, name, mask)
if ~isfield(s, name)
    value = NaN;
    return;
end
values = s.(name)(mask);
values = values(isfinite(values));
if numel(values) < 2
    value = NaN;
else
    value = std(values);
end
end

function value = local_mean_product(s, name1, name2, mask, scale)
if ~isfield(s, name1) || ~isfield(s, name2)
    value = NaN;
    return;
end
values = s.(name1)(mask) .* s.(name2)(mask) * scale;
value = local_mean_vector(values);
end

function value = local_max_abs_field(s, name, mask)
if isfield(s, name)
    value = local_max_abs_vector(s.(name)(mask));
else
    value = NaN;
end
end

function value = local_max_abs_vector(values)
values = values(isfinite(values));
if isempty(values)
    value = NaN;
else
    value = max(abs(values));
end
end

function trim = local_pack_trim(z, ev, f, iter, converged, normF, condJ)
trim = struct();
trim.z = z(:);
trim.ev = ev;
trim.f = f(:);
trim.iter = iter;
trim.converged = converged;
trim.normF = normF;
trim.condJ = condJ;
end

function record = local_empty_record()
record = struct();
record.time_s = NaN;
record.point_id = '';
record.case_name = '';
record.dataset_role = '';
record.engine_id = '';
record.case_id = '';
record.model_mode = NaN;
record.load_input_mode = '';
record.load_connected = false;
record.target_Np_ratio = NaN;
record.target_Np = NaN;
record.collective_pitch_deg = NaN;
record.k_theta = NaN;
record.target_Mkp = NaN;
record.target_Mkp_ratio = NaN;
record.target_load_power_ratio = NaN;
record.target_load_power = NaN;
record.seed_source_point_id = '';
record.Np = NaN;
record.Ng = NaN;
record.HPC_Ncr = NaN;
record.Wf = NaN;
record.Tt45 = NaN;
record.Pt45 = NaN;
record.Mkp = NaN;
record.Mkg = NaN;
record.shaft_power = NaN;
record.model_Pt1 = NaN;
record.Pt2 = NaN;
record.Tt1 = NaN;
record.Pt3 = NaN;
record.Tt3 = NaN;
record.Pamb = NaN;
record.Tamb = NaN;
record.Altitude = NaN;
record.Mach = NaN;
record.target_load_power_true = NaN;
record.Np_true = NaN;
record.Ng_true = NaN;
record.Wf_true = NaN;
record.Tt45_true = NaN;
record.Pt45_true = NaN;
record.Mkp_true = NaN;
record.Mkg_true = NaN;
record.Pt2_true = NaN;
record.Tt1_true = NaN;
record.Pt3_true = NaN;
record.Tt3_true = NaN;
record.Pamb_true = NaN;
record.Tamb_true = NaN;
record.Altitude_true = NaN;
record.Mach_true = NaN;
record.model_Pt5 = NaN;
record.model_Tt5 = NaN;
record.Theta = NaN;
record.Deta = NaN;
record.Ngc = NaN;
record.PRc = NaN;
record.NpError = NaN;
record.NpErrorAbs = NaN;
record.convergeTag = NaN;
record.max_model_error = NaN;
record.normF = NaN;
record.iter = NaN;
record.condJ = NaN;
record.trim_strategy = '';
record.trim_fallback_used = false;
record.trim_primary_attempt_normF = NaN;
record.trim_converged = false;
record.sim_converged = false;
record.sim_duration_s = NaN;
record.steady_window_start_s = NaN;
record.steady_window_end_s = NaN;
record.steady_window_sample_count = NaN;
record.steady_window_std_Np = NaN;
record.steady_window_std_HPC_Ncr = NaN;
record.steady_window_std_Wf = NaN;
record.steady_window_std_Tt45 = NaN;
record.steady_window_max_abs_Np_error = NaN;
record.sim_error_message = '';
record.quality_pass = false;
record.quality_reason = '';
record.ErrHPC = NaN;
record.ErrHPT = NaN;
record.ErrLPT = NaN;
record.ErrNozzle = NaN;
record.ErrLPS = NaN;
record.ErrHPS = NaN;
record.ErrNozzleEnd = NaN;
record.HpcStallMargin = NaN;
record.HptBeta = NaN;
record.LptBeta = NaN;
record.FAR = NaN;
record.T4 = NaN;
record.var_Win = NaN;
record.var_HPCRline = NaN;
record.var_HPTPR = NaN;
record.var_LPTPR = NaN;
record.var_ACRline = NaN;
record.var_CCRline = NaN;
record.var_GT1PR = NaN;
record.var_GT2PR = NaN;
record.var_PT1PR = NaN;
record.var_PT2PR = NaN;
record.var_Np = NaN;
record.var_Ng = NaN;
end

function record = local_record_from_trim(index, point, trim, testCfg)
ev = trim.ev;
y = ev.output;
record = local_empty_record();
record.time_s = index - 1;
record.point_id = point.point_id;
record.case_name = point.case_name;
record.engine_id = testCfg.engineId;
record.case_id = testCfg.caseId;
record = local_assign_point_definition(record, point, testCfg);
record.target_load_power = point.target_load_power;
record.Np = y.Np;
record.Ng = y.Ng;
record.HPC_Ncr = y.HPC_Ncr;
record.Wf = y.Wf;
record.Tt45 = y.Tt45;
record.Pt45 = y.Pt45;
record.Mkp = y.Mkp;
record.Mkg = y.Mkg;
record.shaft_power = y.shaft_power;
record.model_Pt1 = y.Pt1;
record.Pt2 = y.Pt2;
record.Tt1 = y.Tt1;
record.Pt3 = y.Pt3;
record.Tt3 = y.Tt3;
record.Pamb = y.Pamb;
record.Tamb = y.Tamb;
record.Altitude = y.Altitude;
record.Mach = y.Mach;
record = local_assign_class_a_truth(record);
record.model_Pt5 = y.Pt5;
record.model_Tt5 = y.Tt5;
record.Theta = y.Theta;
record.Deta = y.Deta;
record.Ngc = y.Ngc;
record.PRc = y.PRc;
record.NpError = y.Np - point.target_Np;
record.NpErrorAbs = abs(record.NpError);
record.convergeTag = ev.convergeTag;
record.max_model_error = y.max_model_error;
record.normF = trim.normF;
record.iter = trim.iter;
record.condJ = trim.condJ;
record = local_assign_trim_strategy(record, trim);
record.trim_converged = trim.converged;
record.sim_converged = false;
record.sim_duration_s = 0;
record.steady_window_start_s = NaN;
record.steady_window_end_s = NaN;
record.steady_window_sample_count = 0;
record.sim_error_message = 'controlled_sim_not_run';
record.ErrHPC = y.ErrHPC;
record.ErrHPT = y.ErrHPT;
record.ErrLPT = y.ErrLPT;
record.ErrNozzle = y.ErrNozzle;
record.ErrLPS = y.ErrLPS;
record.ErrHPS = y.ErrHPS;
record.ErrNozzleEnd = y.ErrNozzleEnd;
record.HpcStallMargin = y.HpcStallMargin;
record.HptBeta = y.HptBeta;
record.LptBeta = y.LptBeta;
record.FAR = y.FAR;
record.T4 = y.T4;
record = local_assign_trim_variables(record, trim, testCfg);
[record.quality_pass, record.quality_reason] = local_quality_check(record, testCfg);
end

function record = local_record_from_simulation(point, trim, simSummary, simTruthSummary, testCfg)
record = local_empty_record();
record.time_s = simSummary.time_s;
record.point_id = point.point_id;
record.case_name = point.case_name;
record.engine_id = testCfg.engineId;
record.case_id = testCfg.caseId;
record = local_assign_point_definition(record, point, testCfg);
record.target_load_power = simSummary.target_load_power;
record.Np = simSummary.Np;
record.Ng = simSummary.Ng;
% 相对换算转速属于模型工作点诊断量，采用无传感器误差的真值日志。
record.HPC_Ncr = simTruthSummary.HPC_Ncr;
record.Wf = simSummary.Wf;
record.Tt45 = simSummary.Tt45;
record.Pt45 = simSummary.Pt45;
record.Mkp = simSummary.Mkp;
record.Mkg = simSummary.Mkg;
record.shaft_power = simSummary.shaft_power;
record.model_Pt1 = simTruthSummary.Pt1_internal;
record.Pt2 = simSummary.Pt2;
record.Tt1 = simSummary.Tt1;
record.Pt3 = simSummary.Pt3;
record.Tt3 = simSummary.Tt3;
record.Pamb = simSummary.Pamb;
record.Tamb = simSummary.Tamb;
record.Altitude = simSummary.Altitude;
record.Mach = simSummary.Mach;
record = local_assign_class_a_truth(record, simTruthSummary);
record.model_Pt5 = simSummary.Pt5;
record.model_Tt5 = simSummary.Tt5;
record.Theta = simSummary.Theta;
record.Deta = simSummary.Deta;
record.Ngc = simSummary.Ngc;
record.PRc = simSummary.PRc;
% 真实闭环试车按转速传感器测量值判断工况是否到点；传感器偏置会使
% 真值 Np 与目标值存在小偏差，因此质量筛选使用测量 Np 误差。
record.NpError = simSummary.NpError;
record.NpErrorAbs = simSummary.NpErrorAbs;
record.convergeTag = simSummary.convergeTag;
record.max_model_error = simSummary.max_model_error;
record.normF = trim.normF;
record.iter = trim.iter;
record.condJ = trim.condJ;
record = local_assign_trim_strategy(record, trim);
record.trim_converged = trim.converged;
record.sim_converged = simSummary.converged;
record.sim_duration_s = testCfg.simulationStopTime;
record.steady_window_start_s = simSummary.startTime;
record.steady_window_end_s = simSummary.endTime;
record.steady_window_sample_count = simSummary.sample_count;
record.steady_window_std_Np = simSummary.std_Np;
record.steady_window_std_HPC_Ncr = simTruthSummary.std_HPC_Ncr;
record.steady_window_std_Wf = simSummary.std_Wf;
record.steady_window_std_Tt45 = simSummary.std_Tt45;
record.steady_window_max_abs_Np_error = simSummary.max_abs_Np_error;
record.sim_error_message = simSummary.errorMessage;

% 单点稳态配平残差仍作为该工况的模型方程诊断保留；最终测量值来自闭环时间平均。
yTrim = trim.ev.output;
record.ErrHPC = yTrim.ErrHPC;
record.ErrHPT = yTrim.ErrHPT;
record.ErrLPT = yTrim.ErrLPT;
record.ErrNozzle = yTrim.ErrNozzle;
record.ErrLPS = yTrim.ErrLPS;
record.ErrHPS = yTrim.ErrHPS;
record.ErrNozzleEnd = yTrim.ErrNozzleEnd;
record.HpcStallMargin = simSummary.HpcStallMargin;
record.HptBeta = simSummary.HptBeta;
record.LptBeta = simSummary.LptBeta;
record.FAR = simSummary.FAR;
record.T4 = simSummary.T4;
record = local_assign_trim_variables(record, trim, testCfg);
[record.quality_pass, record.quality_reason] = local_quality_check(record, testCfg);
end

function record = local_assign_point_definition(record, point, testCfg)
%LOCAL_ASSIGN_POINT_DEFINITION 保存本点权威输入和名义派生负载。
record.dataset_role = point.dataset_role;
record.model_mode = testCfg.modelMode;
record.load_input_mode = point.load_input_mode;
record.load_connected = point.load_connected;
record.target_Np_ratio = point.target_Np_ratio;
record.target_Np = point.target_Np;
record.collective_pitch_deg = point.collective_pitch_deg;
record.k_theta = point.k_theta;
record.target_Mkp = point.target_Mkp;
record.target_Mkp_ratio = point.target_Mkp_ratio;
record.target_load_power_ratio = point.target_load_power_ratio;
record.seed_source_point_id = point.seed_source_point_id;
end

function record = local_assign_trim_strategy(record, trim)
%LOCAL_ASSIGN_TRIM_STRATEGY 保存极低负载分支处理方式，避免静默回退。
if isfield(trim, 'strategy')
    record.trim_strategy = trim.strategy;
end
if isfield(trim, 'fallbackUsed')
    record.trim_fallback_used = logical(trim.fallbackUsed);
end
if isfield(trim, 'primaryAttemptNormF')
    record.trim_primary_attempt_normF = trim.primaryAttemptNormF;
end
end

function record = local_assign_trim_variables(record, trim, testCfg)
%LOCAL_ASSIGN_TRIM_VARIABLES 按模型模式解释共同工作变量，禁止错位记录。
record.var_Win = trim.z(1);
if testCfg.modelMode == 1
    record.var_ACRline = trim.z(2);
    record.var_CCRline = trim.z(3);
    record.var_GT1PR = trim.z(4);
    record.var_GT2PR = trim.z(5);
    record.var_PT1PR = trim.z(6);
    record.var_PT2PR = trim.z(7);
else
    record.var_HPCRline = trim.z(2);
    record.var_HPTPR = trim.z(3);
    record.var_LPTPR = trim.z(4);
end
record.var_Np = trim.z(end - 2);
record.var_Ng = trim.z(end - 1);
end

function record = local_assign_class_a_truth(record, source)
%LOCAL_ASSIGN_CLASS_A_TRUTH 保存试车数据真值。
% 主字段保存加入偏置和白噪声后的试车数据测量值；*_true 字段保存无噪声、
% 无偏置的试车数据真值，用于后续参数估计误差评价。
if nargin < 2
    source = record;
end
record.target_load_power_true = source.target_load_power;
record.Np_true = source.Np;
record.Ng_true = source.Ng;
record.Wf_true = source.Wf;
record.Tt45_true = source.Tt45;
record.Pt45_true = source.Pt45;
record.Mkp_true = source.Mkp;
record.Mkg_true = source.Mkg;
record.Pt2_true = source.Pt2;
record.Tt1_true = source.Tt1;
record.Pt3_true = source.Pt3;
record.Tt3_true = source.Tt3;
record.Pamb_true = source.Pamb;
record.Tamb_true = source.Tamb;
record.Altitude_true = source.Altitude;
record.Mach_true = source.Mach;
end

function [pass, reason] = local_quality_check(record, testCfg)
reasons = {};
if record.convergeTag ~= 0
    reasons{end + 1} = 'convergeTag_nonzero'; %#ok<AGROW>
end
if ~record.trim_converged
    reasons{end + 1} = 'outer_trim_not_converged'; %#ok<AGROW>
end
if ~record.sim_converged
    reasons{end + 1} = 'controlled_sim_not_converged'; %#ok<AGROW>
end
if record.steady_window_sample_count < testCfg.minSteadyWindowSamples
    reasons{end + 1} = 'steady_window_samples_insufficient'; %#ok<AGROW>
end
if record.max_model_error > testCfg.maxModelErrorTol
    reasons{end + 1} = 'max_model_error_large'; %#ok<AGROW>
end
if record.NpErrorAbs > testCfg.npTolRpm
    reasons{end + 1} = 'Np_error_large'; %#ok<AGROW>
end
if record.Tt45_true > testCfg.t45Max
    reasons{end + 1} = 'Tt45_over_limit'; %#ok<AGROW>
end
thetaRange = testCfg.rotorLoad.collectivePitchMapping.thetaValidRangeDeg;
if record.model_mode ~= 1
    reasons{end + 1} = 'not_six_component_model'; %#ok<AGROW>
end
switch lower(record.load_input_mode)
    case 'collectivepitch'
        if ~record.load_connected
            reasons{end + 1} = 'collective_pitch_load_not_connected'; %#ok<AGROW>
        end
        if record.collective_pitch_deg < thetaRange(1) || ...
                record.collective_pitch_deg > thetaRange(2)
            reasons{end + 1} = 'collective_pitch_outside_valid_range'; %#ok<AGROW>
        end
    case 'directtorque'
        if ~isfinite(record.target_Mkp) || record.target_Mkp < 0 || ...
                ~isfinite(record.target_Mkp_ratio) || record.target_Mkp_ratio < 0
            reasons{end + 1} = 'invalid_direct_torque_command'; %#ok<AGROW>
        end
    otherwise
        reasons{end + 1} = 'unsupported_load_mode'; %#ok<AGROW>
end
if ~all(isfinite(local_record_numeric_values(record)))
    reasons{end + 1} = 'nonfinite_value'; %#ok<AGROW>
end
pass = isempty(reasons);
if pass
    reason = 'pass';
else
    reason = strjoin(reasons, ';');
end
end

function values = local_record_numeric_values(record)
values = [ ...
    record.model_mode; record.target_Np; record.target_Mkp; ...
    record.target_Mkp_ratio; record.target_load_power; ...
    record.Np; record.Ng; record.HPC_Ncr; ...
    record.Wf; record.Tt45; record.Pt45; record.Mkp; record.Mkg; ...
    record.shaft_power; record.Pt2; record.Tt1; record.Pt3; record.Tt3; ...
    record.Pamb; record.Tamb; record.Altitude; record.Mach; ...
    record.target_load_power_true; record.Np_true; record.Ng_true; ...
    record.Wf_true; record.Tt45_true; record.Pt45_true; ...
    record.Mkp_true; record.Mkg_true; record.Pt2_true; record.Tt1_true; ...
    record.Pt3_true; record.Tt3_true; record.Pamb_true; record.Tamb_true; ...
    record.Altitude_true; record.Mach_true; ...
    record.model_Pt5; record.model_Tt5; record.max_model_error; ...
    record.sim_duration_s; record.steady_window_start_s; ...
    record.steady_window_end_s; record.steady_window_sample_count; ...
    record.steady_window_std_Np; record.steady_window_std_HPC_Ncr; ...
    record.steady_window_std_Wf; ...
    record.steady_window_std_Tt45; record.steady_window_max_abs_Np_error];
if strcmpi(record.load_input_mode, 'collectivePitch')
    values = [values; record.collective_pitch_deg; record.k_theta]; %#ok<AGROW>
end
end

function output = local_write_outputs(thisDir, testCfg, points, dataTable, timeHistories)
outputDir = fullfile(thisDir, 'TestData', 'test_data_generation');
testDataDir = fullfile(thisDir, 'TestData');
reportOutputDir = fullfile(fileparts(thisDir), ...
    'report_outputs', 'test_data_generation');
if ~isempty(testCfg.isolatedRunTag)
    outputDir=fullfile(thisDir,'MiddleData','stage2_migration_data',testCfg.isolatedRunTag);
    testDataDir=outputDir;
    reportOutputDir=fullfile(fileparts(thisDir),'report_outputs', ...
        'stage2_migration_data',testCfg.isolatedRunTag);
end
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end
if ~exist(testDataDir, 'dir')
    mkdir(testDataDir);
end
if ~exist(reportOutputDir, 'dir')
    mkdir(reportOutputDir);
end

stamp = datestr(now, 'yyyymmdd_HHMMSS');
matFile = fullfile(outputDir, ['steady_bench_substitute_' stamp '.mat']);
csvFile = fullfile(reportOutputDir, ...
    ['steady_bench_substitute_' stamp '.csv']);
dataDescriptionExcelFile = fullfile(reportOutputDir, ...
    ['steady_bench_2p4_data_description_' stamp '.xlsx']);

metadata = struct();
metadata.generator = mfilename;
metadata.generatedAt = datestr(now, 31);
metadata.engineId = testCfg.engineId;
metadata.caseId = testCfg.caseId;
metadata.modelMode = testCfg.modelMode;
metadata.loadInputMode = testCfg.loadInputMode;
metadata.loadConnected = testCfg.loadConnected;
metadata.loadInputModeByPoint = {points.load_input_mode}.';
metadata.loadConnectedByPoint = [points.load_connected].';
metadata.datasetRoleByPoint = {points.dataset_role}.';
metadata.trainingPointCount = sum(strcmp({points.dataset_role}, 'training'));
metadata.testPointCount = sum(strcmp({points.dataset_role}, 'test'));
metadata.rotorLoadConfig = testCfg.rotorLoad;
metadata.groundIdleConfig = testCfg.groundIdle;
metadata.healthProfile = testCfg.healthProfile;
metadata.healthScheduleEnabled = testCfg.healthScheduleEnabled;
metadata.healthScheduleSourceFile = testCfg.healthScheduleSourceFile;
metadata.truthHealthScheduleProfile = testCfg.healthScheduleProfile;
metadata.HPCNcrDefinition = ...
    '六部件模式下轴流压气机HPC/AC进口基准、按特性图设计换算转速归一化的相对换算转速；来自无测量误差模型日志。';
metadata.loadPowerDefinition = ...
    'target_load_power=Mkp*Np*pi/30；不设置独立功率测量误差。';
metadata.healthUsedIndex = testCfg.healthUsedIndex;
metadata.truthHealth = testCfg.health;
metadata.truth_health_parameters = testCfg.health;
metadata.benchEnvironment = testCfg.benchEnvironment;
metadata.simulationStopTime = testCfg.simulationStopTime;
metadata.steadyWindowStartTime = testCfg.steadyWindowStartTime;
metadata.steadyWindowEndTime = testCfg.steadyWindowEndTime;
metadata.steadyWindowDuration = testCfg.steadyWindowDuration;
metadata.measurementTerminology = 'A 类变量后续统称为试车测量数据；*_true 为试车数据真值；同名主字段为试车数据测量值。';
metadata.sensorErrorModel = testCfg.measurementError;
metadata.classAMeasurementFields = { ...
    'target_load_power', 'Np', 'Ng', 'Wf', 'Tt45', 'Pt45', ...
    'Mkp', 'Mkg', 'Pt2', 'Tt1', 'Pt3', 'Tt3', 'Pamb', 'Tamb', ...
    'Altitude', 'Mach'};
metadata.classATruthFields = { ...
    'target_load_power_true', 'Np_true', 'Ng_true', 'Wf_true', ...
    'Tt45_true', 'Pt45_true', 'Mkp_true', 'Mkg_true', ...
    'Pt2_true', 'Tt1_true', 'Pt3_true', 'Tt3_true', ...
    'Pamb_true', 'Tamb_true', 'Altitude_true', 'Mach_true'};
metadata.testDataMeasuredFields = metadata.classAMeasurementFields;
metadata.testDataTruthFields = metadata.classATruthFields;
metadata.points = points;
metadata.quality = local_quality_summary(dataTable);
metadata.classAPlotFields = local_class_a_plot_field_names();
inputPackage = local_build_2p4_input_package(dataTable, metadata, matFile, csvFile);
figureHandles=[];
if isempty(testCfg.isolatedRunTag)
    figureHandles = local_plot_class_a_time_histories(timeHistories);
end

save(matFile, 'dataTable', 'metadata', 'timeHistories', 'inputPackage', '-v7.3');
try
    writetable(dataTable, csvFile);
catch writeErr
    warning('SHT:TestDataGen:CsvWriteFailed', ...
        'CSV 文件写入失败：%s', writeErr.message);
    csvFile = '';
end
[inputPackageExcelFiles, dataDescriptionExcelFile] = local_write_2p4_excel_files( ...
    inputPackage, testDataDir, dataDescriptionExcelFile);

output = struct();
output.outputDir = outputDir;
output.testDataDir = testDataDir;
output.reportOutputDir = reportOutputDir;
output.matFile = matFile;
output.csvFile = csvFile;
output.inputPackageExcelFiles = inputPackageExcelFiles;
if numel(inputPackageExcelFiles) >= 2
    output.trainingExcelFile = inputPackageExcelFiles{1};
    output.testExcelFile = inputPackageExcelFiles{2};
else
    output.trainingExcelFile = '';
    output.testExcelFile = '';
end
output.dataDescriptionExcelFile = dataDescriptionExcelFile;
output.figureHandles = figureHandles;
end

function inputPackage = local_build_2p4_input_package(dataTable, metadata, sourceMatFile, sourceCsvFile)
%LOCAL_BUILD_2P4_INPUT_PACKAGE 构造面向 2.4 参数估计的输入数据包。
% estimation 只放估计算法允许直接读取的数据；validation 单独保存仿真真值，
% 用于算法开发阶段评价估计误差，正式估计流程不得把该部分作为输入。
passMask = dataTable.quality_pass;
meanInputTable = local_build_2p4_steady_mean_input_table(dataTable);
inputFields = local_existing_table_fields(meanInputTable, local_2p4_input_field_names());
truthFields = local_existing_table_fields(dataTable, local_2p4_truth_field_names());
diagnosticFields = local_existing_table_fields(dataTable, local_2p4_diagnostic_field_names());

inputPackage = struct();
inputPackage.packageVersion = ...
    '2.4_excel_input_v7_pt2_environment_mode3_ready';
inputPackage.shaftLoadInterfaceVersion = ...
    'Mkp_Mkg_external_torque_inputs_v2';
inputPackage.createdAt = datestr(now, 31);
inputPackage.sourceMatFile = sourceMatFile;
inputPackage.sourceCsvFile = sourceCsvFile;

inputPackage.estimation = struct();
inputPackage.estimation.description = ...
    '2.4 参数估计允许读取的稳态窗口测量时间历程算术平均值；每个工况一行。';
inputPackage.estimation.inputTable = meanInputTable(:, inputFields);
inputPackage.estimation.trainingTable = inputPackage.estimation.inputTable( ...
    strcmp(inputPackage.estimation.inputTable.dataset_role, 'training'), :);
inputPackage.estimation.testTable = inputPackage.estimation.inputTable( ...
    strcmp(inputPackage.estimation.inputTable.dataset_role, 'test'), :);
inputPackage.estimation.inputFields = inputFields;
inputPackage.estimation.measurementFields = { ...
    'Np_mean', 'Ng_mean', 'Wf_mean', 'Tt45_mean', 'Pt45_mean', ...
    'Mkp_mean', 'Mkg_mean', 'Pt2_mean', 'Tt1_mean', ...
    'Pt3_mean', 'Tt3_mean', 'Pamb_mean', 'Tamb_mean', ...
    'Altitude_mean', 'Mach_mean'};
inputPackage.estimation.aggregationRule = ...
    '对每个 quality_pass 工况的完整稳态窗口逐个可测通道取算术平均。';
inputPackage.estimation.qualityRule = ...
    '只导出 quality_pass == true 的工况；训练集和测试集由 dataset_role 显式隔离。';

inputPackage.validation = struct();
inputPackage.validation.description = '算法验证用隐藏真值；参数估计主流程不得直接使用。';
inputPackage.validation.truthTable = dataTable(passMask, truthFields);
inputPackage.validation.truthFields = truthFields;
inputPackage.validation.truthHealth = metadata.truthHealth;
inputPackage.validation.healthUsedIndex = metadata.healthUsedIndex;
inputPackage.validation.truthHealthScheduleProfile = metadata.truthHealthScheduleProfile;

inputPackage.diagnostics = struct();
inputPackage.diagnostics.table = dataTable(passMask, diagnosticFields);
inputPackage.diagnostics.fields = diagnosticFields;

inputPackage.metadata = metadata;
inputPackage.metadata.truthHealth = [];
inputPackage.metadata.truth_health_parameters = [];
inputPackage.metadata.truthHealthScheduleProfile = [];
inputPackage.metadata.points = metadata.points(passMask);
end

function inputTable = local_build_2p4_steady_mean_input_table(dataTable)
%LOCAL_BUILD_2P4_STEADY_MEAN_INPUT_TABLE 将每个稳态窗口压缩为一行测量均值。
% dataTable 中的主测量字段已由 local_pack_simulation_summary 对完整
% 稳态窗口求均值。这里仅重命名并隔离公开字段，不做第二次平均，
% 也不输出 *_true、修正系数真值、工况指令或模型内部诊断量。
source = dataTable(dataTable.quality_pass, :);
n = height(source);
if n == 0
    inputTable = table();
    return;
end

dataset_role = source.dataset_role;
point_id = source.point_id;

Np_mean = source.Np;
Ng_mean = source.Ng;
Wf_mean = source.Wf;
Tt45_mean = source.Tt45;
Pt45_mean = source.Pt45;
Mkp_mean = source.Mkp;
Mkg_mean = source.Mkg;
Pt2_mean = source.Pt2;
Tt1_mean = source.Tt1;
Pt3_mean = source.Pt3;
Tt3_mean = source.Tt3;
Pamb_mean = source.Pamb;
Tamb_mean = source.Tamb;
Altitude_mean = source.Altitude;
Mach_mean = source.Mach;

% 地面试车马赫数是先验已知常值，不叠加偏置、动态或白噪声。
assert(all(source.Mach == 0) && all(source.Mach_true == 0), ...
    '稳态试车数据的Mach真值和测量值必须严格为0。');

inputTable = table(dataset_role, point_id, ...
    Np_mean, Ng_mean, Wf_mean, Tt45_mean, Pt45_mean, Mkp_mean, Mkg_mean, ...
    Pt2_mean, Tt1_mean, Pt3_mean, Tt3_mean, Pamb_mean, Tamb_mean, ...
    Altitude_mean, Mach_mean);
end

function [inputPackageExcelFiles, dataDescriptionExcelFile] = local_write_2p4_excel_files( ...
    inputPackage, outputDir, dataDescriptionExcelFile)
%LOCAL_WRITE_2P4_EXCEL_FILES 写出训练、测试两个稳态均值文件。
% 文件名固定，便于下游程序稳定定位；重复运行时原子语义是“当前批次
% 覆盖上一批次”。完整历程、真值和诊断信息只保存在隐藏 MAT 中。
inputTable = inputPackage.estimation.inputTable;
if isempty(inputTable) || width(inputTable) == 0 || ...
        ~ismember('dataset_role', inputTable.Properties.VariableNames)
    warning('SHT:TestDataGen:Empty2p4InputTable', ...
        '没有可写出的 2.4 稳态窗口均值，请检查 quality_pass。');
    inputPackageExcelFiles = {'', ''};
    dataDescriptionExcelFile = local_write_2p4_data_description(inputPackage, dataDescriptionExcelFile);
    return;
end
trainingFile = fullfile(outputDir, 'steady_bench_2p4_training_means.xlsx');
testFile = fullfile(outputDir, 'steady_bench_2p4_test_means.xlsx');
inputPackageExcelFiles = {trainingFile; testFile};
tables = {inputPackage.estimation.trainingTable; inputPackage.estimation.testTable};
labels = {'training'; 'test'};
excelFields = local_2p4_excel_field_names();

for i = 1:2
    outputFile = inputPackageExcelFiles{i};
    try
        if exist(outputFile, 'file')
            delete(outputFile);
        end
        writetable(tables{i}(:, excelFields), outputFile);
    catch writeErr
        warning('SHT:TestDataGen:InputPackageExcelWriteFailed', ...
            '2.4 %s 稳态均值 Excel 写入失败：%s', labels{i}, writeErr.message);
        inputPackageExcelFiles{i} = '';
    end
end

dataDescriptionExcelFile = local_write_2p4_data_description(inputPackage, dataDescriptionExcelFile);
end

function dataDescriptionExcelFile = local_write_2p4_data_description(~, dataDescriptionExcelFile)
%LOCAL_WRITE_2P4_DATA_DESCRIPTION 写出 2.4 输入数据列说明。
try
    if exist(dataDescriptionExcelFile, 'file')
        delete(dataDescriptionExcelFile);
    end
    fieldDictionary = local_2p4_excel_field_dictionary(local_2p4_excel_field_names());
    writetable(fieldDictionary, dataDescriptionExcelFile, 'Sheet', 'FieldDictionary');
catch writeErr
    warning('SHT:TestDataGen:DataDescriptionExcelWriteFailed', ...
        '2.4 数据说明 Excel 文件写入失败：%s', writeErr.message);
    dataDescriptionExcelFile = '';
end
end

function fieldDictionary = local_2p4_excel_field_dictionary(inputFields)
%LOCAL_2P4_EXCEL_FIELD_DICTIONARY 生成 2.4 输入 Excel 的字段字典。
definitions = local_2p4_field_definitions();
n = numel(inputFields);
fieldName = cell(n, 1);
unit = cell(n, 1);
role = cell(n, 1);
descriptionText = cell(n, 1);

for i = 1:n
    fieldName{i} = inputFields{i};
    idx = find(strcmp(definitions.field_name, inputFields{i}), 1, 'first');
    if isempty(idx)
        unit{i} = '-';
        role{i} = '待确认字段';
        descriptionText{i} = '当前字段未在默认字典中定义，使用前需人工确认。';
    else
        unit{i} = definitions.unit{idx};
        role{i} = definitions.role{idx};
        descriptionText{i} = definitions.description{idx};
    end
end

fieldDictionary = table(fieldName, unit, role, descriptionText, ...
    'VariableNames', {'field_name', 'unit', 'role', 'description'});
end

function definitions = local_2p4_field_definitions()
%LOCAL_2P4_FIELD_DEFINITIONS 2.4 输入表字段含义。
rows = { ...
    'data_contract_version', '-', '接口契约', '稳态均值数据契约版本。'; ...
    'aggregation_method', '-', '统计规则', '各测量通道在完整稳态窗口内的统计方法。'; ...
    'dataset_role', '-', '数据划分', 'training表示辨识训练集，test表示独立测试集。'; ...
    'time_s', 's', '数据标识', '单个稳态工况点内的仿真/试车记录时间。'; ...
    'sample_index', '-', '数据标识', '单个稳态工况点内的采样序号。'; ...
    'shaft_load_interface_version', '-', '接口契约', ...
        'Mkp/Mkg 外部轴负载扭矩输入接口版本；用于拒绝旧扭矩语义数据。'; ...
    'point_id', '-', '数据标识', '稳态工况点编号。'; ...
    'case_name', '-', '数据标识', '稳态工况点名称。'; ...
    'engine_id', '-', '数据标识', '个体发动机编号。'; ...
    'case_id', '-', '数据标识', '数据批次编号。'; ...
    'model_mode', '-', '模型配置', '发动机模型模式；本批数据固定为1，即六部件模式。'; ...
    'load_input_mode', '-', '负载接口', '权威负载输入模式；负载接合点为collectivePitch，地面慢车点为directTorque。'; ...
    'load_connected', 'logical', '负载接口', '旋翼/主负载是否接合；地面慢车直接扭矩点为假。'; ...
    'seed_source_point_id', '-', '数值初始化', '初值来源标识；可为已收敛前序工况或公共固化初值，空值表示采用常规顺序种子。'; ...
    'target_Np_ratio', '-', '工况设定', '动力涡轮目标转速相对设计值的比例。'; ...
    'target_Np', 'rpm', '工况设定', '动力涡轮目标转速。'; ...
    'collective_pitch_deg', 'deg', '工况设定', '0.75R处等效总距角权威输入。'; ...
    'k_theta', '-', '派生输入', '由总距角映射得到的无量纲扭矩系数。'; ...
    'target_Mkp', 'N*m', '负载边界', '名义PT负载扭矩；由总距角派生或由directTorque直接给定。'; ...
    'target_Mkp_ratio', '-', '工况设定', '名义PT负载扭矩相对设计点Mkp0的比例。'; ...
    'target_load_power_ratio', '-', '工况设定', '目标负载功率相对设计值的比例。'; ...
    'target_load_power', 'W', '派生测量量', '由同一时刻Mkp与Np测量值计算的负载功率。'; ...
    'Np', 'rpm', '试车测量数据', '动力涡轮转速测量值。'; ...
    'Ng', 'rpm', '试车测量数据', '燃气发生器转速测量值。'; ...
    'Wf', 'kg/s', '试车测量数据', '燃油质量流量测量值。'; ...
    'Tt45', 'K', '试车测量数据', '45 截面总温测量值。'; ...
    'Pt45', 'Pa', '试车测量数据', '45 截面总压测量值。'; ...
    'Mkp', 'N*m', '试车测量数据', 'PT负载/输出轴传递扭矩测量值。'; ...
    'Mkg', 'N*m', '试车测量数据', 'GT轴外部附件负载扭矩测量值。'; ...
    'shaft_power', 'W', '派生测量量', '由动力轴扭矩测量值和动力涡轮转速测量值换算得到的轴功率。'; ...
    'Pt2', 'Pa', '试车测量数据', '进气道出口/轴流压气机进口总压测量值。'; ...
    'Tt1', 'K', '试车测量数据', '发动机入口总温测量值。'; ...
    'Pt3', 'Pa', '试车测量数据', '压气机出口总压测量值。'; ...
    'Tt3', 'K', '试车测量数据', '压气机出口总温测量值。'; ...
    'Pamb', 'Pa', '试车测量数据', '试车环境压力记录值。'; ...
    'Tamb', 'K', '试车测量数据', '试车环境温度记录值。'; ...
    'Altitude', 'm', '试车测量数据', '试车台海拔高度测量值。'; ...
    'Mach', '-', '试车先验数据', '地面静止试车固定为0，不叠加测量误差。'; ...
    'steady_window_start_s', 's', '统计窗口', '稳态均值统计窗口起始时刻。'; ...
    'steady_window_end_s', 's', '统计窗口', '稳态均值统计窗口结束时刻。'; ...
    'steady_window_sample_count', '-', '统计窗口', '参与稳态均值计算的完整窗口样本数。'; ...
    'Np_mean', 'rpm', '试车测量均值', '动力涡轮转速在完整稳态窗口内的算术平均值。'; ...
    'Ng_mean', 'rpm', '试车测量均值', '燃气发生器转速在完整稳态窗口内的算术平均值。'; ...
    'Wf_mean', 'kg/s', '试车测量均值', '燃油质量流量在完整稳态窗口内的算术平均值。'; ...
    'Tt45_mean', 'K', '试车测量均值', '45截面总温在完整稳态窗口内的算术平均值。'; ...
    'Pt45_mean', 'Pa', '试车测量均值', '45截面总压在完整稳态窗口内的算术平均值。'; ...
    'Mkp_mean', 'N*m', '试车测量均值', 'PT负载/输出轴传递扭矩在完整稳态窗口内的算术平均值。'; ...
    'Mkg_mean', 'N*m', '试车测量均值', 'GT轴外部附件负载扭矩在完整稳态窗口内的算术平均值。'; ...
    'shaft_power_mean', 'W', '派生测量均值', '逐样本计算Mkp*Np*pi/30后在完整稳态窗口内取平均。'; ...
    'Pt2_mean', 'Pa', '试车测量均值', '进气道出口/轴流压气机进口总压在完整稳态窗口内的算术平均值。'; ...
    'Tt1_mean', 'K', '试车测量均值', '发动机入口总温在完整稳态窗口内的算术平均值。'; ...
    'Pt3_mean', 'Pa', '试车测量均值', '压气机出口总压在完整稳态窗口内的算术平均值。'; ...
    'Tt3_mean', 'K', '试车测量均值', '压气机出口总温在完整稳态窗口内的算术平均值。'; ...
    'Pamb_mean', 'Pa', '试车测量均值', '环境压力在完整稳态窗口内的算术平均值。'; ...
    'Tamb_mean', 'K', '试车测量均值', '环境温度在完整稳态窗口内的算术平均值。'; ...
    'Altitude_mean', 'm', '试车测量均值', '海拔高度在完整稳态窗口内的算术平均值。'; ...
    'Mach_mean', '-', '试车先验均值', '地面静止试车固定为0。'; ...
    'steady_window_flag', 'logical', '数据标识', '是否属于本程序用于稳态窗口统计的时间段。'; ...
    'quality_pass', 'logical', '质量标记', '该工况点是否默认允许进入 2.4 参数估计。'; ...
    'quality_reason', '-', '质量标记', '质量检查结果说明。'};
definitions = cell2table(rows, ...
    'VariableNames', {'field_name', 'unit', 'role', 'description'});
end

function fields = local_2p4_input_field_names()
%LOCAL_2P4_INPUT_FIELD_NAMES 2.4 参数估计默认输入字段。
fields = { ...
    'dataset_role', 'point_id', ...
    'Np_mean', 'Ng_mean', 'Wf_mean', 'Tt45_mean', 'Pt45_mean', ...
    'Mkp_mean', 'Mkg_mean', ...
    'Pt2_mean', 'Tt1_mean', 'Pt3_mean', 'Tt3_mean', ...
    'Pamb_mean', 'Tamb_mean', 'Altitude_mean', 'Mach_mean'};
end

function fields = local_2p4_excel_field_names()
%LOCAL_2P4_EXCEL_FIELD_NAMES 对外Excel只保留编号和可测通道均值。
fields = { ...
    'point_id', ...
    'Np_mean', 'Ng_mean', 'Wf_mean', 'Tt45_mean', 'Pt45_mean', ...
    'Mkp_mean', 'Mkg_mean', ...
    'Pt2_mean', 'Tt1_mean', 'Pt3_mean', 'Tt3_mean', ...
    'Pamb_mean', 'Tamb_mean', 'Altitude_mean', 'Mach_mean'};
end

function fields = local_2p4_truth_field_names()
%LOCAL_2P4_TRUTH_FIELD_NAMES 2.4 算法验证用隐藏真值字段。
fields = { ...
    'dataset_role', 'point_id', 'case_name', ...
    'model_mode', 'load_input_mode', 'load_connected', ...
    'collective_pitch_deg', 'k_theta', 'target_Mkp', 'target_Mkp_ratio', ...
    'target_load_power_true', 'Np_true', 'Ng_true', 'Wf_true', ...
    'Tt45_true', 'Pt45_true', 'Mkp_true', 'Mkg_true', ...
    'Pt2_true', 'Tt1_true', 'Pt3_true', 'Tt3_true', ...
    'Pamb_true', 'Tamb_true', 'Altitude_true', 'Mach_true'};
end

function fields = local_2p4_diagnostic_field_names()
%LOCAL_2P4_DIAGNOSTIC_FIELD_NAMES 2.4 前处理与复核可用诊断字段。
fields = { ...
    'point_id', 'case_name', ...
    'model_Pt1', 'model_Pt5', 'model_Tt5', 'Theta', 'Deta', 'Ngc', 'HPC_Ncr', 'PRc', ...
    'NpError', 'NpErrorAbs', 'convergeTag', 'max_model_error', ...
    'normF', 'iter', 'condJ', 'trim_converged', 'sim_converged', ...
    'trim_strategy', 'trim_fallback_used', 'trim_primary_attempt_normF', ...
    'sim_duration_s', 'steady_window_start_s', 'steady_window_end_s', ...
    'steady_window_sample_count', 'steady_window_std_Np', ...
    'steady_window_std_HPC_Ncr', ...
    'steady_window_std_Wf', 'steady_window_std_Tt45', ...
    'steady_window_max_abs_Np_error', ...
    'ErrHPC', 'ErrHPT', 'ErrLPT', 'ErrNozzle', ...
    'ErrLPS', 'ErrHPS', 'ErrNozzleEnd', ...
    'HpcStallMargin', 'HptBeta', 'LptBeta', 'FAR', 'T4', ...
    'var_Win', 'var_HPCRline', 'var_HPTPR', ...
    'var_LPTPR', 'var_ACRline', 'var_CCRline', ...
    'var_GT1PR', 'var_GT2PR', 'var_PT1PR', 'var_PT2PR', ...
    'var_Np', 'var_Ng'};
end

function fields = local_existing_table_fields(dataTable, requestedFields)
%LOCAL_EXISTING_TABLE_FIELDS 保留表中实际存在的字段，避免接口轻微调整导致出错。
fields = requestedFields(ismember(requestedFields, dataTable.Properties.VariableNames));
end

function figureHandles = local_plot_class_a_time_histories(timeHistories)
%LOCAL_PLOT_CLASS_A_TIME_HISTORIES 在 MATLAB 中绘制试车测量数据和收敛误差时间历程。
fields = local_time_history_plot_fields();
figureHandles = gobjects(numel(timeHistories), 1);
for i = 1:numel(timeHistories)
    if i > 1
        continue;
    end

    history = timeHistories{i};
    if ~isstruct(history) || ~isfield(history, 'log') || isempty(history.log)
        continue;
    end

    figureHandles(i) = local_plot_one_point_class_a(history, fields);
end
end

function fig = local_plot_one_point_class_a(history, fields)
time = history.time(:);
logMeasured = history.log;
if isfield(history, 'logMeasured')
    logMeasured = history.logMeasured;
end
logTrue = logMeasured;
if isfield(history, 'logTrue')
    logTrue = history.logTrue;
end
fig = figure('Visible', 'on', 'Color', 'w', ...
    'Name', sprintf('%s %s 试车测量数据与收敛误差时间历程', history.point_id, history.case_name), ...
    'Position', [100, 100, 1100, 760]);

for k = 1:16
    ax = subplot(4, 4, k, 'Parent', fig);
    if k > numel(fields)
        axis(ax, 'off');
        continue;
    end

    field = fields(k);
    local_plot_one_history_field(ax, time, logTrue, logMeasured, field, k);
    grid(ax, 'on');
    xlabel(ax, 't / s');
    ylabel(ax, field.unit);
    title(ax, field.label, 'Interpreter', 'none');
    xlim(ax, [min(time), max(time)]);
end

sgtitle(sprintf('%s  %s  试车测量数据与收敛误差时间历程', ...
    history.point_id, history.case_name), 'Interpreter', 'none');
drawnow;
end

function local_plot_one_history_field(ax, time, logTrue, logMeasured, field, plotIndex)
%LOCAL_PLOT_ONE_HISTORY_FIELD 试车测量数据绘制真值/测量值，诊断量绘制单条曲线。
truthValue = local_log_field(logTrue, field.name);
measuredValue = local_log_field(logMeasured, field.name);
hold(ax, 'on');
if strcmp(field.name, 'maxErr')
    plot(ax, time, measuredValue, 'k-', 'LineWidth', 1.0);
else
    plot(ax, time, truthValue, 'b-', 'LineWidth', 1.0);
    plot(ax, time, measuredValue, 'r-', 'LineWidth', 0.8);
    if plotIndex == 1
        legend(ax, {'试车数据真值', '试车数据测量值'}, ...
            'Location', 'best', 'Interpreter', 'none');
    end
end
hold(ax, 'off');
end

function values = local_log_field(logData, name)
if isfield(logData, name)
    values = logData.(name)(:);
else
    values = nan(numel(logData.time), 1);
end
end

function fields = local_class_a_plot_fields()
%LOCAL_CLASS_A_PLOT_FIELDS 曲线图字段顺序与 2.3.1 试车测量数据保持一致。
fields = struct( ...
    'name', {'Np', 'Ng', 'Wf', 'Tt45', 'Mkp', 'Mkg', ...
        'Pt2', 'Tt1', 'Pt3', 'Tt3', 'Pt45', 'Tamb', 'Pamb'}, ...
    'label', {'Np', 'Ng', 'Wf', 'Tt45', 'Mkp', 'Mkg', ...
        'Pt2', 'Tt1', 'Pt3', 'Tt3', 'Pt45', 'Tamb', 'Pamb'}, ...
    'unit', {'rpm', 'rpm', 'kg/s', 'K', 'N*m', 'N*m', ...
        'Pa', 'K', 'Pa', 'K', 'Pa', 'K', 'Pa'});
end

function fields = local_time_history_plot_fields()
%LOCAL_TIME_HISTORY_PLOT_FIELDS 绘图字段：A 类变量后追加模型最大收敛误差。
fields = [local_class_a_plot_fields(), ...
    struct('name', 'maxErr', 'label', '最大收敛误差', 'unit', '-')];
end

function names = local_class_a_plot_field_names()
fields = local_class_a_plot_fields();
names = {fields.name};
end

function summary = local_quality_summary(dataTable)
summary = struct();
summary.pointCount = height(dataTable);
summary.passCount = sum(dataTable.quality_pass);
summary.failCount = summary.pointCount - summary.passCount;
summary.allPassed = summary.failCount == 0;
summary.trainingCount = sum(strcmp(dataTable.dataset_role, 'training'));
summary.testCount = sum(strcmp(dataTable.dataset_role, 'test'));
summary.trainingPassCount = sum(strcmp(dataTable.dataset_role, 'training') & ...
    dataTable.quality_pass);
summary.testPassCount = sum(strcmp(dataTable.dataset_role, 'test') & ...
    dataTable.quality_pass);
if summary.pointCount > 0
    summary.maxNpErrorAbs = max(dataTable.NpErrorAbs);
    summary.maxModelError = max(dataTable.max_model_error);
    hpcNcr = dataTable.HPC_Ncr(isfinite(dataTable.HPC_Ncr));
    if isempty(hpcNcr)
        summary.minHPCNcr = NaN;
        summary.maxHPCNcr = NaN;
        summary.spanHPCNcr = NaN;
    else
        summary.minHPCNcr = min(hpcNcr);
        summary.maxHPCNcr = max(hpcNcr);
        summary.spanHPCNcr = summary.maxHPCNcr - summary.minHPCNcr;
    end
    passMask = dataTable.quality_pass;
    if any(passMask)
        summary.maxPassNpErrorAbs = max(dataTable.NpErrorAbs(passMask));
        summary.maxPassModelError = max(dataTable.max_model_error(passMask));
    else
        summary.maxPassNpErrorAbs = NaN;
        summary.maxPassModelError = NaN;
    end
else
    summary.maxNpErrorAbs = NaN;
    summary.maxModelError = NaN;
    summary.minHPCNcr = NaN;
    summary.maxHPCNcr = NaN;
    summary.spanHPCNcr = NaN;
    summary.maxPassNpErrorAbs = NaN;
    summary.maxPassModelError = NaN;
end
end

function local_print_summary(result)
fprintf('\n=== Steady bench substitute data generation ===\n');
fprintf('Engine: %s, case: %s\n', result.engineId, result.caseId);
fprintf('Model mode: %d, load input: %s\n', ...
    result.modelMode, result.loadInputMode);
fprintf('Health profile: %s, nonzero corrections: %d\n', ...
    result.healthProfile, numel(result.truthHealthUsedIndex));
fprintf('Health scheduling: %d\n', result.healthScheduleEnabled);
fprintf('Points: %d, pass: %d, fail: %d\n', ...
    result.qualitySummary.pointCount, ...
    result.qualitySummary.passCount, ...
    result.qualitySummary.failCount);
fprintf('Training: %d/%d pass; test: %d/%d pass\n', ...
    result.qualitySummary.trainingPassCount, result.qualitySummary.trainingCount, ...
    result.qualitySummary.testPassCount, result.qualitySummary.testCount);
fprintf('Max |Np-target|, all points = %.6g rpm\n', result.qualitySummary.maxNpErrorAbs);
fprintf('Max model error, all points = %.6g\n', result.qualitySummary.maxModelError);
fprintf('Max |Np-target|, passed points = %.6g rpm\n', result.qualitySummary.maxPassNpErrorAbs);
fprintf('Max model error, passed points = %.6g\n', result.qualitySummary.maxPassModelError);
fprintf('HPC relative corrected speed range = %.9f to %.9f (span %.9f)\n', ...
    result.qualitySummary.minHPCNcr, result.qualitySummary.maxHPCNcr, ...
    result.qualitySummary.spanHPCNcr);
fprintf('MAT file: %s\n', result.output.matFile);
if ~isempty(result.output.csvFile)
    fprintf('CSV file: %s\n', result.output.csvFile);
end
if isfield(result.output, 'inputPackageExcelFiles') && ~isempty(result.output.inputPackageExcelFiles)
    validInputFiles = result.output.inputPackageExcelFiles(~cellfun(@isempty, result.output.inputPackageExcelFiles));
    fprintf('2.4 input Excel files: %d\n', numel(validInputFiles));
    for i = 1:numel(validInputFiles)
        fprintf('  %s\n', validInputFiles{i});
    end
end
if ~isempty(result.output.dataDescriptionExcelFile)
    fprintf('2.4 data description Excel file: %s\n', result.output.dataDescriptionExcelFile);
end
local_print_summary_vertical(result.dataTable);
end

function local_print_summary_vertical(dataTable)
%LOCAL_PRINT_SUMMARY_VERTICAL 将原横向摘要表按工况点纵向打印。
fields = {'point_id', 'dataset_role', 'load_input_mode', 'load_connected', ...
    'seed_source_point_id', 'target_Np_ratio', 'collective_pitch_deg', ...
    'k_theta', 'target_Mkp_ratio', 'target_Mkp', 'target_load_power_ratio', ...
    'Wf', 'Np', 'NpError', 'Ng', 'HPC_Ncr', 'Tt45', 'Pt45', 'Mkp', 'Mkg', ...
    'trim_strategy', 'trim_fallback_used', ...
    'quality_pass', 'quality_reason'};

fprintf('\n=== Steady point summary, vertical layout ===\n');
for i = 1:height(dataTable)
    fprintf('\n[%02d]\n', i);
    for k = 1:numel(fields)
        name = fields{k};
        value = dataTable.(name)(i);
        fprintf('  %-24s = %s\n', name, local_format_summary_value(value));
    end
end
end

function textValue = local_format_summary_value(value)
if iscell(value)
    textValue = char(value{1});
elseif islogical(value)
    textValue = sprintf('%d', value);
elseif isnumeric(value)
    textValue = sprintf('%.12g', value);
elseif isstring(value)
    textValue = char(value);
elseif ischar(value)
    textValue = value;
else
    textValue = '<unsupported>';
end
end
