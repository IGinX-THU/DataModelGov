function measurement = sht_flight_measurement_model(simulation, config)
%SHT_FLIGHT_MEASUREMENT_MODEL 构造第3阶段首轮飞参测量历程。
%
% 本函数严格位于真值仿真之后。第 3.1 阶段当前采用的因果顺序为：
%
%   无误差真值 -> 一阶传感器动态 -> 偏置 + 白噪声
%
% 它不调用 DLL、不推进发动机状态，也不把测量值反馈给控制器。这样既能
% 生成含测量误差的飞参记录，又不会改变已经通过 S6/S7 验收的真值轨迹。
% 偏置范围、公共偏置和白噪声标准差与第2阶段使用同一共享定义；
% Wf、T45、Tt3 的偏置随无误差入口流量平滑漂移，覆盖域外固定为最近
% 端点。温度动态按 Tt1、Tamb、
% Tt3、T45、Tt5 五个安装位置分别配置。T45 是规范通道，Tt45 只是
% 同一历程的别名，不单独配置动态或抽取噪声。
% 通用函数仍保留可选延迟能力和 delayed 数据层；3.1 正式入口将延迟
% 固定为零。S10 可通过可选 config.channelRealization 表逐通道覆盖
% 偏置和噪声标准差，其 delay_s 兼容列也必须为零。

if nargin ~= 2 || ~isstruct(simulation) || ~isscalar(simulation) || ...
        ~isstruct(config) || ~isscalar(config)
    error('sht:flightMeasurement:badInput', ...
        'simulation 和 config 必须是标量结构体。');
end
config = local_validate_config(config);
local_require_fields(simulation, {'time','log'}, 'simulation');

time_s = simulation.time(:);
logData = simulation.log;
if numel(time_s) < 2 || any(~isfinite(time_s)) || ...
        any(diff(time_s) <= 0)
    error('sht:flightMeasurement:badTime', ...
        '仿真时间必须是至少包含两个点的严格递增有限序列。');
end
sampleTime_s = median(diff(time_s));
if max(abs(diff(time_s) - sampleTime_s)) > 1e-10 || ...
        abs(sampleTime_s - config.sampleTime_s) > 1e-10
    error('sht:flightMeasurement:sampleTimeMismatch', ...
        '仿真采样周期与测量配置不一致。');
end

definitions = local_channel_definitions(config);
channelCount = numel(definitions);
sampleCount = numel(time_s);
inletFlow_kgps = local_inlet_flow(logData, sampleCount);
channelNames = {definitions.name};
[referenceBiasProfile, biasModelDetail] = ...
    sht_measurement_bias_generator('evaluate', inletFlow_kgps, channelNames);

truth = struct('time_s', time_s);
dynamic = struct('time_s', time_s);
delayed = struct('time_s', time_s);
measured = struct('time_s', time_s);
errorComponent = struct();
errorComponent.dynamic = struct('time_s', time_s);
errorComponent.delay = struct('time_s', time_s);
errorComponent.bias = struct('time_s', time_s);
errorComponent.noise = struct('time_s', time_s);
errorComponent.total = struct('time_s', time_s);

stream = RandStream('mt19937ar', 'Seed', config.randomSeed);
meanError = zeros(channelCount, 1);
rmse = zeros(channelCount, 1);
realizedNoiseStd = zeros(channelCount, 1);
maximumDynamicDifference = zeros(channelCount, 1);
maximumDelayDifference = zeros(channelCount, 1);

for i = 1:channelCount
    def = definitions(i);
    if ~isfield(logData, def.sourceField)
        error('sht:flightMeasurement:missingTruthField', ...
            '真值日志缺少 flightSparse 通道 %s 的源字段 %s。', ...
            def.name, def.sourceField);
    end
    raw = logData.(def.sourceField)(:);
    if numel(raw) ~= sampleCount || any(~isfinite(raw))
        error('sht:flightMeasurement:badTruthField', ...
            '真值通道 %s 的长度或有限性不正确。', def.name);
    end

    if config.enabled && config.components.dynamics && ...
            def.timeConstant_s > 0
        dynamicValue = local_first_order_filter( ...
            time_s, raw, def.timeConstant_s);
    else
        dynamicValue = raw;
    end

    if config.enabled && config.components.delay && def.delay_s > 0
        delayedValue = local_fixed_sample_delay( ...
            dynamicValue, def.delay_s, sampleTime_s);
    else
        delayedValue = dynamicValue;
    end

    if config.enabled && config.components.bias
        if config.flowDependentBiasEnabled
            % 统一生成器先给出参考公共偏置下的流量历程；若调用者通过
            % channelRealization 覆盖公共偏置，只平移整条曲线，不改变
            % 已冻结的10%漂移幅值和端点钳位规则。
            biasValue = referenceBiasProfile(:, i) + ...
                (def.bias - def.referenceCommonBias);
        else
            biasValue = def.bias * ones(sampleCount, 1);
        end
    else
        biasValue = zeros(sampleCount, 1);
    end
    if config.enabled && config.components.noise
        noiseValue = def.noiseStd * randn(stream, sampleCount, 1);
    else
        noiseValue = zeros(sampleCount, 1);
    end
    measuredValue = delayedValue + biasValue + noiseValue;

    truth.(def.name) = raw;
    dynamic.(def.name) = dynamicValue;
    delayed.(def.name) = delayedValue;
    measured.(def.name) = measuredValue;
    errorComponent.dynamic.(def.name) = dynamicValue - raw;
    errorComponent.delay.(def.name) = delayedValue - dynamicValue;
    errorComponent.bias.(def.name) = biasValue;
    errorComponent.noise.(def.name) = noiseValue;
    errorComponent.total.(def.name) = measuredValue - raw;

    totalError = measuredValue - raw;
    meanError(i) = mean(totalError);
    rmse(i) = sqrt(mean(totalError .^ 2));
    realizedNoiseStd(i) = std(noiseValue, 1);
    maximumDynamicDifference(i) = max(abs(dynamicValue - raw));
    maximumDelayDifference(i) = max(abs(delayedValue - dynamicValue));
end

% Tt45 与 T45 是同一只物理温度传感器的命名别名，必须逐点完全相同。
truth.Tt45 = truth.T45;
dynamic.Tt45 = dynamic.T45;
delayed.Tt45 = delayed.T45;
measured.Tt45 = measured.T45;
errorComponent.dynamic.Tt45 = errorComponent.dynamic.T45;
errorComponent.delay.Tt45 = errorComponent.delay.T45;
errorComponent.bias.Tt45 = errorComponent.bias.T45;
errorComponent.noise.Tt45 = errorComponent.noise.T45;
errorComponent.total.Tt45 = errorComponent.total.T45;

local_require_fields(logData, {'Wf','Wfcmd','Mkg'}, 'simulation.log');
controlRecord = struct();
controlRecord.time_s = time_s;
controlRecord.fuel_command = logData.Wfcmd(:);
controlRecord.source = 'controller_record_only';

specification = struct2table(definitions);
metrics = table({definitions.name}.', {definitions.unit}.', ...
    meanError, rmse, realizedNoiseStd, maximumDynamicDifference, ...
    maximumDelayDifference, ...
    'VariableNames', {'channel','unit','meanError','rmse', ...
    'realizedNoiseStd','maxDynamicDifference','maxDelayDifference'});

[temperatureSteps, temperatureStepsPassed] = ...
    local_temperature_step_response_tests( ...
    config.temperatureBandwidth_radps, sampleTime_s);
allFinite = local_all_numeric_fields_finite(truth) && ...
    local_all_numeric_fields_finite(dynamic) && ...
    local_all_numeric_fields_finite(delayed) && ...
    local_all_numeric_fields_finite(measured);
aliasExactlyMatched = isequal(measured.T45, measured.Tt45) && ...
    isequal(dynamic.T45, dynamic.Tt45) && ...
    isequal(truth.T45, truth.Tt45);
wfUsesActualFuel = isequal(truth.Wf, logData.Wf(:));
fuelCommandRecordedSeparately = isequal( ...
    controlRecord.fuel_command, logData.Wfcmd(:)) && ...
    strcmp(controlRecord.source, 'controller_record_only');
mkgFiniteAndTimeAligned = numel(truth.Mkg) == sampleCount && ...
    all(isfinite(truth.Mkg));
mkgStrictlyPositive = mkgFiniteAndTimeAligned && all(truth.Mkg > 0);
mkgMinimum = min(truth.Mkg);
mkgNonpositiveCount = nnz(truth.Mkg <= 0);
if config.enabled
    identityWhenDisabled = true;
else
    identityWhenDisabled = local_measurement_layers_equal( ...
        truth, dynamic, delayed, measured, {definitions.name});
end

validation = struct();
validation.passed = allFinite && aliasExactlyMatched && ...
    wfUsesActualFuel && fuelCommandRecordedSeparately && ...
    mkgFiniteAndTimeAligned && identityWhenDisabled && ...
    temperatureStepsPassed;
validation.allFinite = allFinite;
validation.aliasT45Tt45ExactlyMatched = aliasExactlyMatched;
validation.wfUsesActualFuel = wfUsesActualFuel;
validation.fuelCommandRecordedSeparately = fuelCommandRecordedSeparately;
validation.mkgFiniteAndTimeAligned = mkgFiniteAndTimeAligned;
validation.mkgStrictlyPositive = mkgStrictlyPositive;
% 保留旧字段供 S8 结果读取，但其名称只代表旧阶段检查结果，不再参与
% validation.passed。当前 Mkg 是 GT 轴外部附件负载扭矩；当标称附件
% 负载为零时，测量偏置和白噪声可使测量值跨越零。
validation.mkgPositiveAndTimeAligned = mkgStrictlyPositive;
validation.mkgMinimum_Nm = mkgMinimum;
validation.mkgNonpositiveCount = mkgNonpositiveCount;
validation.identityWhenDisabled = identityWhenDisabled;
validation.temperatureStepResponse = temperatureSteps;
validation.temperatureStepResponsesPassed = temperatureStepsPassed;
validation.postProcessingOnly = true;
if ~validation.passed
    error('sht:flightMeasurement:validationFailed', ...
        ['飞参测量链校验失败：finite=%d，alias=%d，WfSource=%d，' ...
         'fuelCommand=%d，Mkg=%d（min=%.9g N*m，nonpositive=%d），' ...
         'identity=%d，temperatureSteps=%d。'], ...
        allFinite, aliasExactlyMatched, wfUsesActualFuel, ...
        fuelCommandRecordedSeparately, mkgFiniteAndTimeAligned, mkgMinimum, ...
        mkgNonpositiveCount, identityWhenDisabled, temperatureStepsPassed);
end

measurement = struct();
measurement.enabled = config.enabled;
measurement.profile = config.profile;
measurement.sampleTime_s = sampleTime_s;
measurement.randomSeed = config.randomSeed;
if config.enabled && config.components.delay && config.delay_s > 0
    measurement.processingOrder = ...
        'truth -> firstOrderDynamics -> fixedSampleDelay -> bias + whiteNoise';
else
    measurement.processingOrder = ...
        'truth -> firstOrderDynamics -> bias + whiteNoise (pureDelayDisabled)';
end
measurement.postProcessingOnly = true;
measurement.config = config;
measurement.specification = specification;
measurement.truth = truth;
measurement.dynamic = dynamic;
measurement.delayed = delayed;
measurement.measured = measured;
measurement.error = errorComponent;
measurement.biasModel = biasModelDetail;
measurement.biasModel.specification = ...
    sht_measurement_bias_generator('specification');
measurement.controlRecord = controlRecord;
measurement.metrics = metrics;
measurement.validation = validation;
end

function config = local_validate_config(config)
% 仅用于复现历史 S8/S10 归档。新 3.1 入口不再生成这两个旧字段。
if ~isfield(config, 'temperatureBandwidth_radps') && ...
        isfield(config, 'gasTemperatureBandwidth_radps') && ...
        isfield(config, 'ambientTemperatureBandwidth_radps')
    config.temperatureBandwidth_radps = struct( ...
        'Tt1',  config.ambientTemperatureBandwidth_radps, ...
        'Tamb', config.ambientTemperatureBandwidth_radps, ...
        'Tt3',  config.gasTemperatureBandwidth_radps, ...
        'T45',  config.gasTemperatureBandwidth_radps, ...
        'Tt5',  config.gasTemperatureBandwidth_radps);
end
required = {'enabled','profile','sampleTime_s','randomSeed', ...
    'fastSensorTimeConstant_s','temperatureBandwidth_radps', ...
    'delay_s','components'};
local_require_fields(config, required, 'config');
config.enabled = local_logical_scalar(config.enabled, 'config.enabled');
config.profile = local_char_row(config.profile, 'config.profile');
if ~strcmp(config.profile, 'flightSparse')
    error('sht:flightMeasurement:badProfile', ...
        '首轮正式测量配置必须为 flightSparse。');
end
local_assert_positive_scalar(config.sampleTime_s, 'config.sampleTime_s');
local_assert_integer_seed(config.randomSeed, 'config.randomSeed');
if ~isfield(config,'biasRealizationMode') || ...
        isempty(config.biasRealizationMode)
    % 历史入口保持原固定偏置，不改变第2阶段或已归档算例。
    config.biasRealizationMode = 'configured_fixed';
end
if ~isfield(config,'biasRandomSeed') || isempty(config.biasRandomSeed)
    config.biasRandomSeed = config.randomSeed;
end
config.biasRealizationMode = local_char_row( ...
    config.biasRealizationMode,'config.biasRealizationMode');
validBiasModes = {'configured_fixed','uniform_symmetric_single'};
if ~ismember(config.biasRealizationMode,validBiasModes)
    error('sht:flightMeasurement:badBiasRealizationMode', ...
        'config.biasRealizationMode必须为%s之一。', ...
        strjoin(validBiasModes,', '));
end
local_assert_integer_seed(config.biasRandomSeed,'config.biasRandomSeed');
if ~isfield(config, 'flowDependentBiasEnabled') || ...
        isempty(config.flowDependentBiasEnabled)
    config.flowDependentBiasEnabled = true;
end
config.flowDependentBiasEnabled = local_logical_scalar( ...
    config.flowDependentBiasEnabled, 'config.flowDependentBiasEnabled');
local_assert_positive_scalar(config.fastSensorTimeConstant_s, ...
    'config.fastSensorTimeConstant_s');
temperatureChannels = {'Tt1','Tamb','Tt3','T45','Tt5'};
if ~isstruct(config.temperatureBandwidth_radps) || ...
        ~isscalar(config.temperatureBandwidth_radps)
    error('sht:flightMeasurement:badTemperatureBandwidthConfig', ...
        'config.temperatureBandwidth_radps 必须是标量结构体。');
end
local_require_fields(config.temperatureBandwidth_radps, ...
    temperatureChannels, 'config.temperatureBandwidth_radps');
for i = 1:numel(temperatureChannels)
    name = temperatureChannels{i};
    local_assert_positive_scalar( ...
        config.temperatureBandwidth_radps.(name), ...
        ['config.temperatureBandwidth_radps.' name]);
end
local_assert_nonnegative_scalar(config.delay_s, 'config.delay_s');
if abs(config.delay_s / config.sampleTime_s - ...
        round(config.delay_s / config.sampleTime_s)) > 1e-10
    error('sht:flightMeasurement:nonintegerDelay', ...
        '首轮固定延迟必须是记录采样周期的整数倍。');
end
if ~isstruct(config.components) || ~isscalar(config.components)
    error('sht:flightMeasurement:badComponents', ...
        'config.components 必须是标量结构体。');
end
componentNames = {'dynamics','delay','bias','noise'};
local_require_fields(config.components, componentNames, 'config.components');
for i = 1:numel(componentNames)
    name = componentNames{i};
    config.components.(name) = local_logical_scalar( ...
        config.components.(name), ['config.components.' name]);
end
end

function definitions = local_channel_definitions(config)
% 偏置范围、公共偏置和白噪声标准差由统一生成器维护。Pt5/Tt5 分别
% 继承同类 Pt45/T45 传感器规格，待实物量程与校准证书可用后替换。
fastTau = config.fastSensorTimeConstant_s;
temperatureBandwidth = config.temperatureBandwidth_radps;
delay_s = config.delay_s;
rows = { ...
    'Np',   'Np',   'rpm', fastTau, delay_s; ...
    'Ng',   'Ng',   'rpm', fastTau, delay_s; ...
    'Wf',   'Wf',   'kg/s',fastTau, delay_s; ...
    'T45',  'T45',  'K',   1 / temperatureBandwidth.T45, delay_s; ...
    'Mkg',  'Mkg',  'N*m', fastTau, delay_s; ...
    'Mkp',  'Mkp',  'N*m', fastTau, delay_s; ...
    'Pt1',  'Pt1',  'Pa',  fastTau, delay_s; ...
    'Tt1',  'Tt1',  'K',   1 / temperatureBandwidth.Tt1, delay_s; ...
    'Pt3',  'Pt3',  'Pa',  fastTau, delay_s; ...
    'Tt3',  'Tt3',  'K',   1 / temperatureBandwidth.Tt3, delay_s; ...
    'Pt45', 'Pt45', 'Pa',  fastTau, delay_s; ...
    'Pt5',  'Pt5',  'Pa',  fastTau, delay_s; ...
    'Tt5',  'Tt5',  'K',   1 / temperatureBandwidth.Tt5, delay_s; ...
    'Pamb', 'Pamb', 'Pa',  fastTau, delay_s; ...
    'Tamb', 'Tamb', 'K',   1 / temperatureBandwidth.Tamb, delay_s};
channelConfig = sht_measurement_bias_generator( ...
    'channelConfig', rows(:, 1));
definitions = repmat(struct('name','','sourceField','','unit','', ...
    'bias',0,'referenceCommonBias',0,'biasHalfWidth',0, ...
    'flowDriftEnabled',false,'maxFlowDrift',0, ...
    'noiseStd',0,'noiseStdPctDesign',0, ...
    'timeConstant_s',0,'bandwidth_radps',0, ...
    'delay_s',0,'delaySamples',0), size(rows, 1), 1);
sharedSpecification = sht_measurement_bias_generator('specification');
for i = 1:size(rows, 1)
    definitions(i).name = rows{i, 1};
    definitions(i).sourceField = rows{i, 2};
    definitions(i).unit = rows{i, 3};
    definitions(i).bias = channelConfig.commonBias(i);
    definitions(i).referenceCommonBias = channelConfig.commonBias(i);
    definitions(i).biasHalfWidth = channelConfig.totalBiasHalfWidth(i);
    definitions(i).flowDriftEnabled = channelConfig.flowDriftEnabled(i);
    definitions(i).maxFlowDrift = channelConfig.maxFlowDrift(i);
    definitions(i).noiseStd = channelConfig.noiseStd(i);
    row = find(strcmp(sharedSpecification.name, rows{i, 1}), 1, 'first');
    definitions(i).noiseStdPctDesign = ...
        sharedSpecification.noiseStdPctDesign(row);
    definitions(i).timeConstant_s = rows{i, 4};
    definitions(i).bandwidth_radps = 1 / rows{i, 4};
    definitions(i).delay_s = rows{i, 5};
    definitions(i).delaySamples = round(rows{i, 5} / config.sampleTime_s);
end
if strcmp(config.biasRealizationMode,'uniform_symmetric_single')
    % rows中的偏置绝对值在该模式下解释为对称均匀分布半宽，不再解释
    % 为本次数据的固定实现。独立偏置流避免改变白噪声随机序列。
    biasStream = RandStream('mt19937ar','Seed',config.biasRandomSeed);
    for i = 1:numel(definitions)
        halfWidth = definitions(i).biasHalfWidth;
        definitions(i).bias = halfWidth*(2*rand(biasStream)-1);
    end
end

if isfield(config, 'channelRealization') && ...
        ~isempty(config.channelRealization)
    definitions = local_apply_channel_realization( ...
        definitions, config.channelRealization, config.sampleTime_s);
end
end

function flow = local_inlet_flow(logData, expectedLength)
% 飞参日志优先使用统一 WIn；兼容旧结果时允许读取 flightWIn。
if isfield(logData, 'WIn')
    flow = logData.WIn;
elseif isfield(logData, 'flightWIn')
    flow = logData.flightWIn;
else
    error('sht:flightMeasurement:missingBiasFlow', ...
        '流量相关偏置需要无误差入口流量 WIn 或 flightWIn。');
end
if ~isnumeric(flow) || numel(flow) ~= expectedLength || ...
        any(~isfinite(flow(:)))
    error('sht:flightMeasurement:badBiasFlow', ...
        '入口流量必须与飞参时间轴等长且全部有限。');
end
flow = flow(:);
end

function definitions = local_apply_channel_realization( ...
        definitions, realization, sampleTime_s)
% S10 只允许覆盖测量误差实现，不允许改变通道、单位或传感器动态。
if ~istable(realization)
    error('sht:flightMeasurement:badChannelRealization', ...
        'config.channelRealization 必须是 table。');
end
required = {'name','bias','noiseStd','delay_s'};
missing = required(~ismember(required, realization.Properties.VariableNames));
if ~isempty(missing)
    error('sht:flightMeasurement:missingRealizationColumns', ...
        'config.channelRealization 缺少列：%s。', strjoin(missing, ', '));
end
expectedNames = {definitions.name}.';
actualNames = cellstr(string(realization.name));
if height(realization) ~= numel(expectedNames) || ...
        numel(unique(actualNames)) ~= numel(actualNames) || ...
        ~isempty(setxor(expectedNames, actualNames))
    error('sht:flightMeasurement:realizationChannelMismatch', ...
        'channelRealization 必须且只能包含全部 15 个规范测量通道。');
end

for i = 1:numel(definitions)
    row = find(strcmp(actualNames, definitions(i).name), 1);
    bias = realization.bias(row);
    noiseStd = realization.noiseStd(row);
    delay_s = realization.delay_s(row);
    if ~isnumeric(bias) || ~isscalar(bias) || ~isfinite(bias) || ...
            ~isnumeric(noiseStd) || ~isscalar(noiseStd) || ...
            ~isfinite(noiseStd) || noiseStd < 0 || ...
            ~isnumeric(delay_s) || ~isscalar(delay_s) || ...
            ~isfinite(delay_s) || delay_s < 0
        error('sht:flightMeasurement:badRealizationValue', ...
            '通道 %s 的偏置、噪声标准差或延迟值非法。', ...
            definitions(i).name);
    end
    delaySamples = delay_s / sampleTime_s;
    if abs(delaySamples - round(delaySamples)) > 1e-10
        error('sht:flightMeasurement:nonintegerRealizationDelay', ...
            '通道 %s 的延迟必须是采样周期的整数倍。', ...
            definitions(i).name);
    end
    definitions(i).bias = bias;
    definitions(i).noiseStd = noiseStd;
    definitions(i).delay_s = delay_s;
    definitions(i).delaySamples = round(delaySamples);
end
end

function filtered = local_first_order_filter(time_s, raw, timeConstant_s)
% 初值取首个真值，表示记录开始前传感器已在初始配平点达到平衡。
filtered = raw(:);
for i = 2:numel(filtered)
    dt = time_s(i) - time_s(i - 1);
    alpha = 1 - exp(-dt / timeConstant_s);
    filtered(i) = filtered(i - 1) + alpha * ...
        (raw(i) - filtered(i - 1));
end
end

function delayed = local_fixed_sample_delay(value, delay_s, sampleTime_s)
delaySamples = round(delay_s / sampleTime_s);
delayed = value(:);
if delaySamples <= 0
    return;
end
delayed(1:delaySamples) = value(1);
delayed(delaySamples + 1:end) = value(1:end - delaySamples);
end

function test = local_step_response_test(bandwidth_radps, sampleTime_s)
timeConstant_s = 1 / bandwidth_radps;
stepCount = round(timeConstant_s / sampleTime_s);
if abs(stepCount * sampleTime_s - timeConstant_s) > 1e-12
    error('sht:flightMeasurement:stepTestGrid', ...
        '温度时间常数必须落在当前 0.025 s 测试网格上。');
end
time_s = (0:sampleTime_s:2 * timeConstant_s).';
raw = ones(size(time_s));
raw(1) = 0;
filtered = local_first_order_filter(time_s, raw, timeConstant_s);
valueAtOneTau = filtered(stepCount + 1);
expected = 1 - exp(-1);
test = struct();
test.bandwidth_radps = bandwidth_radps;
test.timeConstant_s = timeConstant_s;
test.valueAtOneTimeConstant = valueAtOneTau;
test.expected63p2 = expected;
test.absoluteError = abs(valueAtOneTau - expected);
test.passed = test.absoluteError <= 1e-12;
end

function [tests, passed] = local_temperature_step_response_tests( ...
        bandwidth, sampleTime_s)
% 五个物理温度通道分别验收，避免一个代表性带宽掩盖配置错误。
channelNames = {'Tt1','Tamb','Tt3','T45','Tt5'};
tests = struct();
passed = true;
for i = 1:numel(channelNames)
    name = channelNames{i};
    tests.(name) = local_step_response_test( ...
        bandwidth.(name), sampleTime_s);
    passed = passed && tests.(name).passed;
end
end

function matched = local_measurement_layers_equal( ...
        truth, dynamic, delayed, measured, names)
matched = true;
for i = 1:numel(names)
    name = names{i};
    matched = matched && isequal(truth.(name), dynamic.(name)) && ...
        isequal(truth.(name), delayed.(name)) && ...
        isequal(truth.(name), measured.(name));
end
end

function passed = local_all_numeric_fields_finite(values)
passed = true;
names = fieldnames(values);
for i = 1:numel(names)
    value = values.(names{i});
    if isnumeric(value)
        passed = passed && all(isfinite(value(:)));
    end
end
end

function local_require_fields(value, names, pathName)
for i = 1:numel(names)
    if ~isfield(value, names{i})
        error('sht:flightMeasurement:missingField', ...
            '%s 缺少字段 %s。', pathName, names{i});
    end
end
end

function value = local_logical_scalar(value, name)
if ~(islogical(value) || isnumeric(value)) || ~isscalar(value) || ...
        ~isfinite(value) || abs(double(value) - round(double(value))) > 1e-9 || ...
        ~ismember(round(double(value)), [0, 1])
    error('sht:flightMeasurement:badSwitch', ...
        '%s 必须为逻辑标量或与 0/1 的差不超过 1e-9。', name);
end
value = logical(round(double(value)));
end

function value = local_char_row(value, name)
if isstring(value) && isscalar(value)
    value = char(value);
end
if ~ischar(value) || size(value, 1) ~= 1 || isempty(strtrim(value))
    error('sht:flightMeasurement:badText', ...
        '%s 必须是非空字符行向量或标量字符串。', name);
end
value = strtrim(value);
end

function local_assert_integer_seed(value, name)
if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
        ~isfinite(value) || value < 0 || value > 2^32 - 1 || ...
        abs(value - round(value)) > 1e-9
    error('sht:flightMeasurement:badSeed', ...
        '%s 必须是 [0,2^32-1] 内的整数。', name);
end
end

function local_assert_positive_scalar(value, name)
if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
        ~isfinite(value) || value <= 0
    error('sht:flightMeasurement:badPositiveScalar', ...
        '%s 必须是有限正实数。', name);
end
end

function local_assert_nonnegative_scalar(value, name)
if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
        ~isfinite(value) || value < 0
    error('sht:flightMeasurement:badNonnegativeScalar', ...
        '%s 必须是有限非负实数。', name);
end
end
