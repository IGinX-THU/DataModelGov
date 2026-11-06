function result = Start_FlightModelAdapt_01_PreprocessAndEquivalentReplay(userCfg)
%START_FLIGHTMODELADAPT_01_PREPROCESSANDEQUIVALENTREPLAY 3.2 飞参预处理入口。
%
% 第二轮默认调用 sht_f32_preprocess_and_replay，严格读取3.1生成的
% F31_FLIGHT_EXCEL_V3稀疏飞参，以入口模式5在C端重构Pt0/Pt1；
% 排气背压由现有M侧模型按可测Mkp和预测Np逐时刻计算，并按
% 默认三部件Visser16模型连续回放；六部件须显式配置并隔离输出。旧首轮仅在指定
% implementationMode='legacy_first_round' 时运行。
%
% 第二轮正式调用：
%   已完成批次不可覆盖，重新处理应给定新的runTag：
%   result = Start_FlightModelAdapt_01_PreprocessAndEquivalentReplay( ...
%       struct('runTag','new_preprocess_batch','plotEnabled',false));
%
% 首轮历史复现：
%   result = Start_FlightModelAdapt_01_PreprocessAndEquivalentReplay( ...
%       struct('implementationMode','legacy_first_round'));
%
% 以下旧主体对应第3.2阶段首轮最小功能：
%   1) 只读取 flightData.estimationData，不访问健康真值和误差实现真值；
%   2) 复用3.1阶段已有任务标签，整理稳态窗口、过渡态片段和任务阶段；
%   3) 在本入口独立配置传感器对象参数，对测量通道做零相位
%      平滑，并对温度通道做一阶传感器逆动态补偿；
%   4) 用1截面 Pt1/Tt1、Pamb 及测得 Mkp/Mkg 重构轴负载边界；
%   5) 用100维零修正、2状态、无瞬态效应发动机模型完成开环等效回放；
%   6) 输出样本质量、共同工作残差和测量/模型对比，供3.3阶段读取。
%
% 重要边界：
%   - Mkp 是 PT 负载/输出轴传递扭矩，Mkg 是 GT 轴外部附件负载扭矩；
%     二者均为可测模型输入。theta-kTheta 负载模型和附件功率调度仅用于
%     数据生成及边界一致性诊断，不再代替测得扭矩进入参数估计回放；
%   - 偏置范围、噪声强度和动态带宽是3.2中的建模对象参数，不从
%     3.1替代数据中读取生成真值；
%   - 测量偏置在真实任务中未知，本程序不作“完美校正”，避免真值泄漏；
%   - 本文件不修改任何第2阶段入口或共享函数。
%
if nargin < 1 || isempty(userCfg)
    userCfg = struct();
end
if ~isstruct(userCfg) || ~isscalar(userCfg)
    error('sht:flightAdapt01:badUserConfig', ...
        'userCfg 必须为标量结构体。');
end
implementationMode = 'second_round_long_mission';
if isfield(userCfg,'implementationMode') && ...
        ~isempty(userCfg.implementationMode)
    implementationMode = lower(char(string(userCfg.implementationMode)));
    userCfg = rmfield(userCfg,'implementationMode');
end
if ~strcmp(implementationMode,'legacy_first_round')
    result = sht_f32_preprocess_and_replay(userCfg);
    return;
end

fprintf('\n=== Start_FlightModelAdapt_01: preprocess and replay flight data ===\n');
thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir);

if nargin < 1 || isempty(userCfg)
    userCfg = struct();
elseif ~isstruct(userCfg) || ~isscalar(userCfg)
    error('sht:flightAdapt01:badUserConfig', ...
        'userCfg 必须为标量结构体。');
end

options = local_default_options();
options = local_merge_struct(options, userCfg);
options = local_validate_options(options);
sourceFile = local_resolve_source_file(thisDir, options.sourceFile);

loaded = load(sourceFile, 'flightData');
if ~isfield(loaded, 'flightData') || ~isstruct(loaded.flightData)
    error('sht:flightAdapt01:noFlightData', ...
        '源文件不包含 flightData 结构：%s', sourceFile);
end
flightData = loaded.flightData;
local_validate_flight_data(flightData, sourceFile);

% 只把 estimationData 送入后续逻辑。此后不再保留 flightData 局部
% 变量，防止误把 validationData 中的健康或传感器生成真值带入结果。
estimationData = flightData.estimationData;
sourceSchemaVersion = flightData.schemaVersion;
sourceDataType = flightData.dataSource;
clear flightData loaded;

historyCount = numel(estimationData.histories);
replayCfg = sht_default_config();
% 第3阶段首轮明确使用2状态无瞬态效应模型。删除该可选字段可保证
% sht_engine_derivative 始终走基准 x=[Np;Ng] 分支。
if isfield(replayCfg.engine, 'transientEffects')
    replayCfg.engine = rmfield(replayCfg.engine, 'transientEffects');
end
replayCfg.engine.boundary.health = zeros( ...
    replayCfg.engine.interface.healthLength, 1);
if isempty(options.designNpRpm)
    options.designNpRpm = replayCfg.engine.initial.Np0;
end
if isempty(options.designPowerW)
    options.designPowerW = replayCfg.engine.initial.power0;
end

experiments = repmat(local_empty_experiment(), historyCount, 1);
for i = 1:historyCount
    experiments(i) = local_preprocess_history( ...
        estimationData.histories(i), ...
        options.measurementObjectParameters, options);
end

if options.replayEnabled
    engine = sht_engine_open(replayCfg.engine);
    engineCleanup = onCleanup(@() sht_engine_close(engine));
    for i = 1:historyCount
        experiments(i) = local_replay_history( ...
            engine, replayCfg, experiments(i), options);
    end
    clear engineCleanup;
else
    for i = 1:historyCount
        experiments(i).replay.enabled = false;
    end
end

qualitySummary = local_quality_summary(experiments, options);
validation = local_validate_result(experiments, qualitySummary, options);

result = struct();
result.program = mfilename;
result.version = '3.2-minimal-v3-measurement-object-config';
result.shaftLoadInterfaceVersion = ...
    'Mkp_Mkg_external_torque_inputs_v2';
result.createdAt = datestr(now, 31);
result.description = [ ...
    '飞参稳态/过渡态标签整理、温度传感器动态补偿、装机边界重构和' ...
    '零健康二状态模型等效回放结果。'];
result.source = struct( ...
    'file', sourceFile, ...
    'schemaVersion', sourceSchemaVersion, ...
    'dataSource', sourceDataType, ...
    'historyCount', historyCount, ...
    'truthDataAccessed', false, ...
    'measurementParametersReadFromSource', false);
result.options = options;
result.measurementObjectParameters = options.measurementObjectParameters;
result.experiments = experiments;
result.qualitySummary = qualitySummary;
result.validation = validation;
result.output = struct('saved', false, 'matFile', '', ...
    'latestMatFile', '', 'summaryCsv', '', 'figureFiles', {{}});

if options.plotEnabled
    result.output.figureFiles = local_plot_results( ...
        experiments, options.figureDir, options.saveEnabled);
end
if options.saveEnabled
    result.output = local_save_result( ...
        result, options.outputDir, options.figureDir);
end

local_print_summary(result);
if ~validation.passed
    error('sht:flightAdapt01:validationFailed', ...
        '3.2结果未通过质量门限，详见 result.validation 和 qualitySummary。');
end
end

function options = local_default_options()
paths = sht_flight_model_adapt_common('paths');
options = struct();
options.sourceFile = '';
options.outputDir = paths.middleDataDir;
options.figureDir = paths.outputDir;
options.plotEnabled = true;
options.saveEnabled = true;
options.replayEnabled = true;
options.dynamicCompensationEnabled = true;
options.fastChannelCutoff_Hz = 4.0;
options.gasTemperatureCutoff_Hz = 2.0;
options.ambientTemperatureCutoff_Hz = 1.0;
options.compensatedTemperatureChannels = ...
    {'T45','Tt1','Tt3','Tt5','Tamb'};
options.designNpRpm = [];
options.designPowerW = [];
options.maximumAcceptedResidual = 0.01;
options.minimumSteadySamples = 1;
options.minimumTransitionSamples = 1;
% 这是个性化建模端对实际传感器的工程先验，不是3.1替代数据
% 生成时使用的隐藏真值。真实对象应通过 userCfg 用标定结果覆盖。
options.measurementObjectParameters = ...
    local_default_measurement_object_parameters();
end

function parameters = local_default_measurement_object_parameters()
% 15通道首轮工程先验。偏置用对称区间表示未知固定偏置；
% noiseStd 是单点零均值白噪声标准差；当前独立纯延迟固定为零。
channel = {'Np';'Ng';'Wf';'T45';'Mkg';'Mkp';'Pt1';'Tt1'; ...
    'Pt3';'Tt3';'Pt45';'Pt5';'Tt5';'Pamb';'Tamb'};
shared = sht_measurement_bias_generator('channelConfig', channel);
unit = shared.unit;
biasMagnitude = shared.totalBiasHalfWidth;
noiseStd = shared.noiseStd;
timeConstant_s = [0.020;0.020;0.020;0.50;0.020;0.020;0.020; ...
    1.00;0.020;0.30;0.020;0.020;0.60;0.020;2.00];
bandwidth_radps = 1./timeConstant_s;
delayLower_s = zeros(size(timeConstant_s));
delayUpper_s = zeros(size(timeConstant_s));

parameters = struct();
parameters.schemaVersion = '3.2-measurement-object-parameters-v2';
parameters.enabled = true;
parameters.configurationSource = 'stage3p2_entry_engineering_prior';
parameters.description = ...
    ['个性化建模端配置的传感器对象参数；偏置半宽与白噪声标准差' ...
     '来自统一测量误差规格，不由3.1估计数据泄露实际误差实现。'];
parameters.biasDistribution = 'uniform_symmetric';
parameters.noiseDistribution = 'zero_mean_gaussian';
parameters.delayDistribution = 'fixed_zero';
parameters.delayChoices_s = 0;
parameters.biasModel = sht_measurement_bias_generator('model');
parameters.channelTable = table(channel,unit,-biasMagnitude,biasMagnitude, ...
    shared.commonBias,shared.flowDriftEnabled,shared.maxFlowDrift, ...
    noiseStd,timeConstant_s,bandwidth_radps,delayLower_s,delayUpper_s, ...
    'VariableNames', {'channel','unit','biasLower','biasUpper', ...
    'commonBiasReference','flowDriftEnabled','maxFlowDrift', ...
    'noiseStd','timeConstant_s','bandwidth_radps','delayLower_s', ...
    'delayUpper_s'});
end

function options = local_validate_options(options)
logicalFields = {'plotEnabled','saveEnabled','replayEnabled', ...
    'dynamicCompensationEnabled'};
for i = 1:numel(logicalFields)
    name = logicalFields{i};
    value = options.(name);
    if ~(islogical(value) && isscalar(value)) && ...
            ~(isnumeric(value) && isscalar(value) && isfinite(value) && ...
              any(value == [0, 1]))
        error('sht:flightAdapt01:badLogicalOption', ...
            '%s 必须为标量逻辑量。', name);
    end
    options.(name) = logical(value);
end

positiveFields = {'fastChannelCutoff_Hz','gasTemperatureCutoff_Hz', ...
    'ambientTemperatureCutoff_Hz','maximumAcceptedResidual'};
for i = 1:numel(positiveFields)
    name = positiveFields{i};
    value = options.(name);
    if ~(isnumeric(value) && isscalar(value) && isfinite(value) && value > 0)
        error('sht:flightAdapt01:badPositiveOption', ...
            '%s 必须为有限正数。', name);
    end
end

optionalPositiveFields = {'designNpRpm','designPowerW'};
for i = 1:numel(optionalPositiveFields)
    name = optionalPositiveFields{i};
    value = options.(name);
    if ~isempty(value) && ~(isnumeric(value) && isscalar(value) && ...
            isfinite(value) && value > 0)
        error('sht:flightAdapt01:badDesignReference', ...
            '%s 必须为空或有限正数。', name);
    end
end

countFields = {'minimumSteadySamples','minimumTransitionSamples'};
for i = 1:numel(countFields)
    name = countFields{i};
    value = options.(name);
    if ~(isnumeric(value) && isscalar(value) && isfinite(value) && ...
            value >= 0 && abs(value-round(value)) < 1e-12)
        error('sht:flightAdapt01:badCountOption', ...
            '%s 必须为非负整数。', name);
    end
    options.(name) = round(value);
end

options.sourceFile = local_char_row(options.sourceFile, 'sourceFile');
options.outputDir = local_char_row(options.outputDir, 'outputDir');
options.figureDir = local_char_row(options.figureDir, 'figureDir');
options.measurementObjectParameters = ...
    local_validate_measurement_object_parameters( ...
    options.measurementObjectParameters);
channelListValid = iscell(options.compensatedTemperatureChannels) && ...
    all(cellfun(@(x) ischar(x) && isrow(x), ...
    options.compensatedTemperatureChannels));
if ~channelListValid
    error('sht:flightAdapt01:badChannelList', ...
        'compensatedTemperatureChannels 必须为字符向量元胞数组。');
end
end

function parameters = local_validate_measurement_object_parameters(parameters)
required = {'schemaVersion','enabled','configurationSource', ...
    'biasDistribution','noiseDistribution','delayDistribution', ...
    'delayChoices_s','channelTable'};
local_require_fields(parameters, required, 'measurementObjectParameters');
if ~isstruct(parameters) || ~isscalar(parameters) || ...
        ~logical(parameters.enabled)
    error('sht:flightAdapt01:badMeasurementObjectParameters', ...
        'measurementObjectParameters 必须是已启用的标量结构体。');
end
if ~strcmp(char(string(parameters.biasDistribution)), ...
        'uniform_symmetric') || ...
        ~strcmp(char(string(parameters.noiseDistribution)), ...
        'zero_mean_gaussian') || ...
        ~strcmp(char(string(parameters.delayDistribution)), 'fixed_zero')
    error('sht:flightAdapt01:unsupportedMeasurementDistribution', ...
        '首轮只支持对称均匀偏置、高斯白噪声和零纯延迟。');
end
if ~isequal(parameters.delayChoices_s(:),0)
    error('sht:flightAdapt01:nonzeroMeasurementDelay', ...
        '当前传感器对象参数必须使用零独立纯延迟。');
end

tbl = parameters.channelTable;
needed = {'channel','unit','biasLower','biasUpper','noiseStd', ...
    'timeConstant_s','bandwidth_radps','delayLower_s','delayUpper_s'};
if ~istable(tbl) || ~all(ismember(needed,tbl.Properties.VariableNames))
    error('sht:flightAdapt01:badMeasurementObjectTable', ...
        '传感器对象参数表字段不完整。');
end
expected = {'Np','Ng','Wf','T45','Mkg','Mkp','Pt1','Tt1', ...
    'Pt3','Tt3','Pt45','Pt5','Tt5','Pamb','Tamb'};
actual = cellstr(string(tbl.channel));
if height(tbl)~=numel(expected) || numel(unique(actual))~=numel(actual) || ...
        ~all(ismember(expected,actual))
    error('sht:flightAdapt01:measurementObjectChannelSet', ...
        '传感器对象参数必须唯一覆盖15个正式测量通道。');
end
numericNames = {'biasLower','biasUpper','noiseStd','timeConstant_s', ...
    'bandwidth_radps','delayLower_s','delayUpper_s'};
for i = 1:numel(numericNames)
    value = tbl.(numericNames{i});
    if ~isnumeric(value) || any(~isfinite(value))
        error('sht:flightAdapt01:nonfiniteMeasurementObjectValue', ...
            '传感器对象参数 %s 必须全部有限。',numericNames{i});
    end
end
if any(tbl.biasLower>tbl.biasUpper) || any(tbl.noiseStd<0) || ...
        any(tbl.timeConstant_s<=0) || any(tbl.bandwidth_radps<=0) || ...
        any(tbl.delayLower_s~=0) || any(tbl.delayUpper_s~=0) || ...
        any(abs(tbl.timeConstant_s.*tbl.bandwidth_radps-1)>1e-10)
    error('sht:flightAdapt01:invalidMeasurementObjectValue', ...
        '偏置范围、噪声、动态带宽或零延迟配置无效。');
end
parameters.schemaVersion = char(string(parameters.schemaVersion));
parameters.configurationSource = ...
    char(string(parameters.configurationSource));
parameters.channelTable = tbl;
end

function sourceFile = local_resolve_source_file(thisDir, requestedFile)
if ~isempty(requestedFile)
    sourceFile = sht_flight_model_adapt_common( ...
        'resolveFlightDataFile', requestedFile);
    return;
end

paths = sht_flight_model_adapt_common('paths');
patterns = {'flight_parameter_substitute_3_1-S9_*.mat'};
candidates = [];
for patternIndex = 1:numel(patterns)
    found = dir(fullfile(paths.flightDataDir, patterns{patternIndex}));
    candidates = [candidates; found(:)]; %#ok<AGROW>
end

programContainer = fileparts(fileparts(thisDir));
archiveRoot = fullfile(programContainer, '备份', ...
    '3.1飞参替代数据首轮开发');
if exist(archiveRoot, 'dir')
    archives = dir(fullfile(archiveRoot, 'S11_complete_*'));
    archives = archives([archives.isdir]);
    for i = 1:numel(archives)
        for patternIndex = 1:numel(patterns)
            found = dir(fullfile(archives(i).folder, archives(i).name, ...
                'formal_data', patterns{patternIndex}));
            candidates = [candidates; found(:)]; %#ok<AGROW>
        end
    end
end

if isempty(candidates)
    error('sht:flightAdapt01:noDefaultSource', ...
        ['未找到3.1-S9正式 flightData。可通过 userCfg.sourceFile ' ...
         '显式指定数据文件。']);
end
[~, latestIndex] = max([candidates.datenum]);
sourceFile = fullfile(candidates(latestIndex).folder, ...
    candidates(latestIndex).name);
sourceFile = sht_flight_model_adapt_common( ...
    'resolveFlightDataFile', sourceFile);
end

function local_validate_flight_data(flightData, sourceFile)
required = {'schemaVersion','dataSource','shaftLoadInterfaceVersion', ...
    'estimationData'};
local_require_fields(flightData, required, 'flightData');
if ~strcmp(char(string(flightData.dataSource)), ...
        'synthetic_flight_parameter_substitute')
    error('sht:flightAdapt01:sourceType', ...
        '当前最小实现只接受3.1飞参替代数据：%s', sourceFile);
end
if ~strcmp(char(string(flightData.shaftLoadInterfaceVersion)), ...
        'Mkp_Mkg_external_torque_inputs_v2')
    error('sht:flightAdapt01:oldShaftLoadInterface', ...
        '飞参数据仍使用旧扭矩语义，必须由当前版3.1程序重新生成：%s。', ...
        sourceFile);
end
estimationData = flightData.estimationData;
local_require_fields(estimationData, ...
    {'historyCount','histories','sampleTime_s'}, ...
    'flightData.estimationData');
if estimationData.historyCount ~= numel(estimationData.histories) || ...
        isempty(estimationData.histories)
    error('sht:flightAdapt01:historyCount', ...
        'estimationData.historyCount 与 histories 数量不一致。');
end
if isfield(flightData,'measurementErrorSpec') || ...
        isfield(estimationData,'uncertaintyAssumptions')
    error('sht:flightAdapt01:measurementParameterLeak', ...
        ['3.1观测数据不应附带传感器生成真值或不确定性先验；' ...
         '请用当前3.1入口重新生成数据。']);
end
end

function experiment = local_preprocess_history(history, ...
        measurementObjectParameters, options)
local_require_fields(history, {'missionId','variantId','time_s', ...
    'command','measurement','labels','quality'}, 'estimation history');
time_s = history.time_s(:);
if numel(time_s) < 3 || any(~isfinite(time_s)) || ...
        any(diff(time_s) <= 0)
    error('sht:flightAdapt01:badTime', ...
        '%s 时间轴无效。', char(string(history.missionId)));
end
dt = diff(time_s);
sampleTime_s = median(dt);
if max(abs(dt-sampleTime_s)) > max(1e-10, 1e-6*sampleTime_s)
    error('sht:flightAdapt01:nonuniformTime', ...
        '%s 当前最小实现要求等间隔采样。', ...
        char(string(history.missionId)));
end

specification = measurementObjectParameters.channelTable;
if ~istable(specification) || ...
        ~all(ismember({'channel','bandwidth_radps'}, ...
        specification.Properties.VariableNames))
    error('sht:flightAdapt01:badMeasurementSpec', ...
        '3.2传感器对象参数必须包含 channel 和 bandwidth_radps。');
end
channelNames = cellstr(string(specification.channel));
measurement = history.measurement;
processed = struct('time_s', time_s);
raw = struct('time_s', time_s);
compensationRecords = repmat(local_empty_compensation_record(), ...
    numel(channelNames), 1);

for i = 1:numel(channelNames)
    name = channelNames{i};
    if ~isfield(measurement, name)
        error('sht:flightAdapt01:missingMeasurement', ...
            '%s 缺少测量通道 %s。', ...
            char(string(history.missionId)), name);
    end
    value = measurement.(name)(:);
    if numel(value) ~= numel(time_s) || any(~isfinite(value))
        error('sht:flightAdapt01:badMeasurement', ...
            '%s 的 %s 通道长度错误或含非有限值。', ...
            char(string(history.missionId)), name);
    end
    raw.(name) = value;

    cutoff_Hz = local_channel_cutoff(name, options);
    filtered = sht_transient_model_adapt_common( ...
        'smoo', value, time_s, cutoff_Hz);
    bandwidth_radps = specification.bandwidth_radps(i);
    compensate = options.dynamicCompensationEnabled && ...
        any(strcmp(name, options.compensatedTemperatureChannels));
    if compensate
        filtered = local_inverse_first_order( ...
            filtered, time_s, bandwidth_radps, name);
    end
    processed.(name) = filtered;
    compensationRecords(i) = struct( ...
        'channel', name, ...
        'smoothingCutoff_Hz', cutoff_Hz, ...
        'sensorBandwidth_radps', bandwidth_radps, ...
        'inverseDynamicsApplied', compensate);
end

modelInput = local_reconstruct_boundary(history, processed, options);
labels = local_normalize_labels(history.labels, numel(time_s));
quality = local_build_sample_quality(history, raw, processed, ...
    modelInput, labels);

experiment = local_empty_experiment();
experiment.experimentId = sprintf('%s_%s', ...
    char(string(history.missionId)), char(string(history.variantId)));
experiment.missionId = char(string(history.missionId));
experiment.variantId = char(string(history.variantId));
experiment.sampleTime_s = sampleTime_s;
experiment.time_s = time_s;
experiment.rawMeasurement = raw;
experiment.processedMeasurement = processed;
experiment.modelInput = modelInput;
experiment.labels = labels;
experiment.quality = quality;
experiment.compensation = struct2table(compensationRecords);
experiment.replay = local_empty_replay();
end

function cutoff_Hz = local_channel_cutoff(name, options)
if any(strcmp(name, {'T45','Tt3','Tt5'}))
    cutoff_Hz = options.gasTemperatureCutoff_Hz;
elseif any(strcmp(name, {'Tt1','Tamb'}))
    cutoff_Hz = options.ambientTemperatureCutoff_Hz;
else
    cutoff_Hz = options.fastChannelCutoff_Hz;
end
end

function estimate = local_inverse_first_order(measured, time_s, ...
        bandwidth_radps, signalName)
% 一阶测量环节 ydot=omega*(x-y) 的离散精确逆。输入先经过零相位
% 平滑，避免差分项把白噪声无限放大。首点没有前一采样，保持测量首值。
if ~(isscalar(bandwidth_radps) && isfinite(bandwidth_radps) && ...
        bandwidth_radps > 0)
    error('sht:flightAdapt01:badSensorBandwidth', ...
        '%s 的传感器带宽无效。', signalName);
end
dt = diff(time_s);
alpha = 1-exp(-bandwidth_radps*dt);
if any(alpha <= sqrt(eps))
    error('sht:flightAdapt01:singularSensorInverse', ...
        '%s 的离散一阶逆动态病态。', signalName);
end
estimate = measured;
estimate(2:end) = measured(1:end-1) + diff(measured)./alpha;
if any(~isfinite(estimate))
    error('sht:flightAdapt01:nonfiniteSensorInverse', ...
        '%s 逆动态补偿产生非有限结果。', signalName);
end
end

function modelInput = local_reconstruct_boundary(history, measurement, options)
local_require_fields(history.command, {'hpsPower_W','theta_deg','kTheta'}, ...
    'history.command');
n = numel(measurement.time_s);
hpsPower_W = history.command.hpsPower_W(:);
if isscalar(hpsPower_W)
    hpsPower_W = repmat(hpsPower_W, n, 1);
end
if numel(hpsPower_W) ~= n || any(~isfinite(hpsPower_W))
    error('sht:flightAdapt01:badAccessoryPower', ...
        '%s 的附件功率边界无效。', char(string(history.missionId)));
end

theta_deg = history.command.theta_deg(:);
kTheta = history.command.kTheta(:);
if numel(theta_deg) ~= n || numel(kTheta) ~= n || ...
        any(~isfinite(theta_deg)) || any(~isfinite(kTheta)) || ...
        any(kTheta <= 0)
    error('sht:flightAdapt01:badRotorLoadCommand', ...
        '%s 的 theta/kTheta 负载指令无效。', ...
        char(string(history.missionId)));
end

% 旋翼模型和附件功率只用于检查测得扭矩边界是否与生成端指令一致。
Npr = measurement.Np/options.designNpRpm;
scheduledLoadPower_W = options.designPowerW .* kTheta .* Npr.^3;
targetLoadPower_W = measurement.Mkp .* measurement.Np * pi/30;
measuredAccessoryPower_W = measurement.Mkg .* measurement.Ng * pi/30;
if any(~isfinite(targetLoadPower_W)) || any(targetLoadPower_W <= 0) || ...
        any(~isfinite(measuredAccessoryPower_W)) || ...
        any(measuredAccessoryPower_W < 0)
    error('sht:flightAdapt01:badLoadPower', ...
        '%s 由 Mkp/Mkg 与轴转速重构的负载功率无效。', ...
        char(string(history.missionId)));
end

modelInput = struct();
modelInput.Wf_kgps = measurement.Wf;
modelInput.Mkp_Nm = measurement.Mkp;
modelInput.Mkg_Nm = measurement.Mkg;
modelInput.targetLoadPower_W = targetLoadPower_W;
modelInput.hpsPower_W = measuredAccessoryPower_W;
modelInput.Pt1_Pa = measurement.Pt1;
modelInput.Tt1_K = measurement.Tt1;
modelInput.Pamb_Pa = measurement.Pamb;
modelInput.theta_deg = theta_deg;
modelInput.kTheta = kTheta;
modelInput.Npr = Npr;
modelInput.scheduledLoadPower_W = scheduledLoadPower_W;
modelInput.scheduledAccessoryPower_W = hpsPower_W;
modelInput.loadPowerMethod = 'measured_Mkp_Mkg_times_current_shaft_speed';
modelInput.designNpRpm = options.designNpRpm;
modelInput.designPowerW = options.designPowerW;
end

function labels = local_normalize_labels(sourceLabels, n)
if ~istable(sourceLabels) || height(sourceLabels) ~= n
    error('sht:flightAdapt01:badLabels', ...
        '任务标签必须是与时间轴等长的表。');
end
required = {'segmentId','windowType','windowTypeCode', ...
    'candidateWindowId','isSteadyCandidate','healthEstimationEligible'};
if ~all(ismember(required, sourceLabels.Properties.VariableNames))
    error('sht:flightAdapt01:missingLabels', ...
        '任务标签字段不完整。');
end
labels = sourceLabels(:, required);
labels.segmentId = cellstr(string(labels.segmentId));
labels.windowType = cellstr(string(labels.windowType));
labels.isSteadyCandidate = logical(labels.isSteadyCandidate);
labels.healthEstimationEligible = ...
    logical(labels.healthEstimationEligible);
end

function quality = local_build_sample_quality(history, raw, processed, ...
        modelInput, labels)
n = numel(processed.time_s);
sourceAccepted = true(n,1);
if isfield(history.quality, 'sampleAccepted')
    sourceAccepted = logical(history.quality.sampleAccepted(:));
end
if numel(sourceAccepted) ~= n
    error('sht:flightAdapt01:badSourceQuality', ...
        '%s 的 sampleAccepted 长度错误。', ...
        char(string(history.missionId)));
end

finiteMask = true(n,1);
rawFields = setdiff(fieldnames(raw), {'time_s'});
for i = 1:numel(rawFields)
    finiteMask = finiteMask & isfinite(raw.(rawFields{i}));
end
processedFields = setdiff(fieldnames(processed), {'time_s'});
for i = 1:numel(processedFields)
    finiteMask = finiteMask & isfinite(processed.(processedFields{i}));
end
finiteMask = finiteMask & ...
    isfinite(modelInput.Mkp_Nm) & modelInput.Mkp_Nm >= 0 & ...
    isfinite(modelInput.Mkg_Nm) & modelInput.Mkg_Nm >= 0;

usable = sourceAccepted & finiteMask;
windowType = labels.windowType;
quality = struct();
quality.sourceAccepted = sourceAccepted;
quality.finite = finiteMask;
quality.usable = usable;
quality.steady = usable & labels.isSteadyCandidate;
quality.transition = usable & strcmp(windowType, 'transition');
quality.settling = usable & strcmp(windowType, 'settling');
quality.boundaryValidation = usable & ...
    strcmp(windowType, 'boundaryValidation');
quality.healthEstimationEligible = usable & ...
    labels.healthEstimationEligible;
end

function experiment = local_replay_history(engine, cfg, experiment, options)
time_s = experiment.time_s;
input = experiment.modelInput;
measurement = experiment.processedMeasurement;
health = zeros(cfg.engine.interface.healthLength, 1);
x = [measurement.Np(1); measurement.Ng(1)];

% 先以首点测量和重构边界求一次气动共同工作点，仅把其4个气动变量
% 用作 DLL 非线性求解初值；发动机动态状态仍严格取测量 Np/Ng。
cfg.engine.boundary.Mkp = input.Mkp_Nm(1);
cfg.engine.boundary.Mkg = input.Mkg_Nm(1);
cfg.engine.boundary.ptLoadInputMode = 'torque';
cfg.engine.boundary.gtLoadInputMode = 'torque';
seedPoint = struct( ...
    'Np_mean', x(1), ...
    'Ng_mean', x(2), ...
    'Wf_mean', input.Wf_kgps(1), ...
    'Mkp_mean', input.Mkp_Nm(1), ...
    'Mkg_mean', input.Mkg_Nm(1), ...
    'target_load_power_mean', input.targetLoadPower_W(1), ...
    'Pt1_mean', input.Pt1_Pa(1), ...
    'Tt1_mean', input.Tt1_K(1), ...
    'Pamb_mean', input.Pamb_Pa(1));
seedEvaluation = sht_steady_model_adapt_common( ...
    'evaluateTransientPoint', engine, cfg, seedPoint, health);
if numel(seedEvaluation.varIte) < 4 || ...
        any(~isfinite(seedEvaluation.varIte(1:4)))
    error('sht:flightAdapt01:badReplaySeed', ...
        '%s 首点共同工作初值无效。', experiment.experimentId);
end
local_reset_var_start(engine, cfg, ...
    [seedEvaluation.varIte(1:4); x]);

n = numel(time_s);
model = local_empty_model_output(n);
state = NaN(n,2);
appliedLoadPower_W = NaN(n,1);
maxResidualBySample = NaN(n,1);
convergeTagBySample = zeros(n,1);
evaluationCount = 0;

for k = 1:n
    boundary = local_boundary_at(cfg, input, health, k, x);
    [xDot1, y1, diag1] = sht_engine_derivative( ...
        engine, x, input.Wf_kgps(k), boundary);
    local_validate_engine_evaluation( ...
        experiment.experimentId, time_s(k), x, xDot1, y1, diag1);
    state(k,:) = x.';
    appliedLoadPower_W(k) = boundary.power;
    model = local_assign_model_output(model, y1, k);
    maxResidualBySample(k) = diag1.maxErr;
    convergeTagBySample(k) = diag1.convergeTag;
    evaluationCount = evaluationCount + 1;

    if k == n
        continue;
    end
    dt = time_s(k+1)-time_s(k);
    xPredict = x + dt*xDot1;
    boundaryNext = local_boundary_at( ...
        cfg, input, health, k+1, xPredict);
    [xDot2, y2, diag2] = sht_engine_derivative( ...
        engine, xPredict, input.Wf_kgps(k+1), boundaryNext);
    local_validate_engine_evaluation( ...
        experiment.experimentId, time_s(k+1), ...
        xPredict, xDot2, y2, diag2);
    xNext = x + 0.5*dt*(xDot1+xDot2);
    boundaryEnd = local_boundary_at( ...
        cfg, input, health, k+1, xNext);
    [xDotEnd, yEnd, diagEnd] = sht_engine_derivative( ...
        engine, xNext, input.Wf_kgps(k+1), boundaryEnd);
    local_validate_engine_evaluation( ...
        experiment.experimentId, time_s(k+1), ...
        xNext, xDotEnd, yEnd, diagEnd);
    maxResidualBySample(k+1) = max([maxResidualBySample(k+1), ...
        diag2.maxErr, diagEnd.maxErr], [], 'omitnan');
    convergeTagBySample(k+1) = max(abs([diag2.convergeTag, ...
        diagEnd.convergeTag]));
    evaluationCount = evaluationCount + 2;
    x = xNext;
end

measuredOutput = local_measured_output_matrix(measurement);
modelOutput = local_model_output_matrix(model);
errorValue = modelOutput-measuredOutput;
usable = experiment.quality.usable;
if ~any(usable)
    error('sht:flightAdapt01:noUsableReplaySamples', ...
        '%s 没有可用于回放评价的样本。', experiment.experimentId);
end
rmsError = sqrt(mean(errorValue(usable,:).^2, 1));
maxAbsError = max(abs(errorValue(usable,:)), [], 1);

replay = local_empty_replay();
replay.enabled = true;
replay.modelType = 'two_state_zero_health_no_transient_effects';
replay.stateNames = {'Np','Ng'};
replay.outputNames = {'Np','Ng','Pt3','Tt3','T45','Pt45'};
replay.state = state;
replay.modelOutput = model;
replay.appliedLoadPower_W = appliedLoadPower_W;
replay.measuredOutputMatrix = measuredOutput;
replay.error = errorValue;
replay.rmsError = rmsError;
replay.maxAbsError = maxAbsError;
replay.maxResidualBySample = maxResidualBySample;
replay.convergeTagBySample = convergeTagBySample;
replay.maximumResidual = max(maxResidualBySample);
replay.nonzeroConvergeTagCount = nnz(convergeTagBySample);
replay.evaluationCount = evaluationCount;
replay.residualAccepted = ...
    replay.maximumResidual < options.maximumAcceptedResidual;
experiment.replay = replay;
end

function boundary = local_boundary_at(cfg, input, health, k, xEngine)
boundary = struct();
boundary.A8 = cfg.engine.boundary.A8;
boundary.Mkp = input.Mkp_Nm(k);
boundary.Mkg = input.Mkg_Nm(k);
boundary.ptLoadInputMode = 'torque';
boundary.gtLoadInputMode = 'torque';
boundary.hpcAlpha = cfg.engine.boundary.hpcAlpha;
boundary.health = health;
boundary.Pt1 = input.Pt1_Pa(k);
boundary.Tt1 = input.Tt1_K(k);
boundary.Pamb = input.Pamb_Pa(k);
boundary.flightBoundaryEnabled = true;
boundary = sht_resolve_shaft_load_boundary(boundary, xEngine);
end

function local_reset_var_start(engine, cfg, seed)
stepInValue = zeros(cfg.engine.interface.stepInLength, 1);
stepInValue(21:(20+numel(seed))) = seed(:);
stepIn = libpointer('doublePtr', stepInValue);
stepOut = libpointer('doublePtr', ...
    zeros(cfg.engine.interface.stepOutLength, 1));
engPtrInit.eng = libstruct(engine.engineStructName);
engPtr = libstruct(engine.enginePointerName, engPtrInit);
calllib(engine.libraryName, 'DLL_SHT_varIteInit', ...
    stepIn, stepOut, engPtr);
end

function local_validate_engine_evaluation(experimentId, time_s, ...
        state, stateDerivative, output, diagnostic)
if any(~isfinite(state)) || any(~isfinite(stateDerivative)) || ...
        ~all(isfinite([output.Np, output.Ng, output.Pt3, output.Tt3, ...
        output.Tt45, output.Pt45, ...
        output.HPC_Ncr, output.GT_Ncr, output.PT_Ncr, ...
        diagnostic.maxErr, diagnostic.convergeTag]))
    error('sht:flightAdapt01:nonfiniteReplay', ...
        '%s 在 t=%.6g s 出现非有限模型结果。', experimentId, time_s);
end
end

function model = local_assign_model_output(model, y, k)
model.Np(k) = y.Np;
model.Ng(k) = y.Ng;
model.Pt3(k) = y.Pt3;
model.Tt3(k) = y.Tt3;
model.T45(k) = y.Tt45;
model.Pt45(k) = y.Pt45;
% 三个 Ncr 是各部件特性图实际使用的相对换算转速坐标。GT 与 HPC
% 虽同属高压轴，但入口总温不同，必须分别读取 DLL 部件输出。
model.HPC_Ncr(k) = y.HPC_Ncr;
model.GT_Ncr(k) = y.GT_Ncr;
model.PT_Ncr(k) = y.PT_Ncr;
end

function matrix = local_measured_output_matrix(measurement)
matrix = [measurement.Np, measurement.Ng, measurement.Pt3, ...
    measurement.Tt3, measurement.T45, measurement.Pt45];
end

function matrix = local_model_output_matrix(model)
matrix = [model.Np, model.Ng, model.Pt3, model.Tt3, ...
    model.T45, model.Pt45];
end

function summary = local_quality_summary(experiments, options)
n = numel(experiments);
missionId = cell(n,1);
sampleCount = zeros(n,1);
usableCount = zeros(n,1);
steadyCount = zeros(n,1);
transitionCount = zeros(n,1);
settlingCount = zeros(n,1);
boundaryCount = zeros(n,1);
healthEligibleCount = zeros(n,1);
maximumReplayResidual = NaN(n,1);
nonzeroConvergeTagCount = zeros(n,1);
replayAccepted = false(n,1);
for i = 1:n
    missionId{i} = experiments(i).missionId;
    sampleCount(i) = numel(experiments(i).time_s);
    usableCount(i) = nnz(experiments(i).quality.usable);
    steadyCount(i) = nnz(experiments(i).quality.steady);
    transitionCount(i) = nnz(experiments(i).quality.transition);
    settlingCount(i) = nnz(experiments(i).quality.settling);
    boundaryCount(i) = nnz( ...
        experiments(i).quality.boundaryValidation);
    healthEligibleCount(i) = nnz( ...
        experiments(i).quality.healthEstimationEligible);
    if experiments(i).replay.enabled
        maximumReplayResidual(i) = ...
            experiments(i).replay.maximumResidual;
        nonzeroConvergeTagCount(i) = ...
            experiments(i).replay.nonzeroConvergeTagCount;
        replayAccepted(i) = experiments(i).replay.residualAccepted;
    else
        replayAccepted(i) = ~options.replayEnabled;
    end
end
summary = table(missionId, sampleCount, usableCount, steadyCount, ...
    transitionCount, settlingCount, boundaryCount, ...
    healthEligibleCount, maximumReplayResidual, ...
    nonzeroConvergeTagCount, replayAccepted);
end

function validation = local_validate_result(experiments, summary, options)
sampleQualityPassed = all(summary.usableCount == summary.sampleCount);
labelCoveragePassed = all( ...
    summary.steadyCount >= options.minimumSteadySamples & ...
    summary.transitionCount >= options.minimumTransitionSamples);
replayPassed = all(summary.replayAccepted);
finiteOutputPassed = true;
for i = 1:numel(experiments)
    if experiments(i).replay.enabled
        finiteOutputPassed = finiteOutputPassed && ...
            all(isfinite(experiments(i).replay.state(:))) && ...
            all(isfinite(experiments(i).replay.error(:)));
    end
end
validation = struct();
validation.truthIsolationPassed = true;
validation.measurementParametersConfiguredInStage3p2 = true;
validation.measurementParametersReadFromSource = false;
validation.sampleQualityPassed = sampleQualityPassed;
validation.labelCoveragePassed = labelCoveragePassed;
validation.replayPassed = replayPassed;
validation.finiteOutputPassed = finiteOutputPassed;
validation.passed = validation.truthIsolationPassed && ...
    sampleQualityPassed && labelCoveragePassed && replayPassed && ...
    finiteOutputPassed;
end

function figureFiles = local_plot_results(experiments, outputDir, saveEnabled)
figureFiles = cell(0,1);
if saveEnabled && ~exist(outputDir, 'dir')
    mkdir(outputDir);
end
names = {'Np','Ng','Pt3','Tt3','T45','Pt45'};
units = {'rpm','rpm','Pa','K','K','Pa'};
for i = 1:numel(experiments)
    if ~experiments(i).replay.enabled
        continue;
    end
    experiment = experiments(i);
    measured = experiment.replay.measuredOutputMatrix;
    model = local_model_output_matrix(experiment.replay.modelOutput);
    fig = figure('Name', ['3.2 replay - ' experiment.missionId], ...
        'Color', 'w');
    for j = 1:numel(names)
        subplot(3,2,j);
        plot(experiment.time_s, measured(:,j), 'k-', ...
            'LineWidth', 1.0, 'DisplayName', '测量预处理');
        hold on;
        plot(experiment.time_s, model(:,j), 'r--', ...
            'LineWidth', 1.0, 'DisplayName', '标称模型回放');
        grid on;
        xlabel('时间 / s');
        ylabel([names{j} ' / ' units{j}]);
        title(names{j}, 'Interpreter', 'none');
        if j == 1
            legend('Location', 'best');
        end
    end
    if saveEnabled
        base = fullfile(outputDir, ...
            ['flight_model_adapt_01_' experiment.missionId]);
        figFile = [base '.fig'];
        pngFile = [base '.png'];
        savefig(fig, figFile);
        print(fig, pngFile, '-dpng', '-r160');
        figureFiles{end+1,1} = figFile; %#ok<AGROW>
        figureFiles{end+1,1} = pngFile; %#ok<AGROW>
    end
end

% 三个部件各占一个子图，并在同一坐标轴叠加全部任务历程。该图用于
% 判断不同飞行数据的特性图相对换算转速覆盖是否接近，不把轴绝对转速
% 或控制器换算转速误当作部件 Ncr。
activeIndex = find(arrayfun(@(x) x.replay.enabled, experiments));
if ~isempty(activeIndex)
    fields = {'HPC_Ncr','GT_Ncr','PT_Ncr'};
    titles = {'HPC 相对换算转速','GT 相对换算转速', ...
        'PT 相对换算转速'};
    colors = lines(numel(activeIndex));
    fig = figure('Name', '3.2 component relative corrected speed', ...
        'Color', 'w', 'Position', [100, 80, 1100, 850]);
    for fieldIndex = 1:numel(fields)
        subplot(3,1,fieldIndex);
        hold on;
        for historyIndex = 1:numel(activeIndex)
            experiment = experiments(activeIndex(historyIndex));
            plot(experiment.time_s, ...
                experiment.replay.modelOutput.(fields{fieldIndex}), ...
                'LineWidth', 1.1, ...
                'Color', colors(historyIndex,:), ...
                'DisplayName', experiment.missionId);
        end
        grid on;
        xlabel('时间 / s');
        ylabel([fields{fieldIndex} ' / 1'], 'Interpreter', 'none');
        title(titles{fieldIndex});
        legend('Location', 'eastoutside', 'Interpreter', 'none');
    end
    sgtitle('全部飞行历程的部件相对换算转速');
    if saveEnabled
        base = fullfile(outputDir, ...
            'flight_model_adapt_01_relative_corrected_speed');
        figFile = [base '.fig'];
        pngFile = [base '.png'];
        savefig(fig, figFile);
        print(fig, pngFile, '-dpng', '-r160');
        figureFiles{end+1,1} = figFile;
        figureFiles{end+1,1} = pngFile;
    end
end
end

function output = local_save_result(result, outputDir, reportOutputDir)
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end
if ~exist(reportOutputDir, 'dir')
    mkdir(reportOutputDir);
end
stamp = datestr(now, 'yyyymmdd_HHMMSS');
matFile = fullfile(outputDir, ...
    ['flight_model_adapt_01_preprocess_' stamp '.mat']);
latestMatFile = fullfile(outputDir, ...
    'flight_model_adapt_01_latest.mat');
summaryCsv = fullfile(reportOutputDir, ...
    ['flight_model_adapt_01_quality_' stamp '.csv']);

output = result.output;
output.saved = true;
output.matFile = matFile;
output.latestMatFile = latestMatFile;
output.summaryCsv = summaryCsv;

% MAT 内也保存最终输出路径，保证下游读取 latest 文件后能够追溯本次
% 时间戳文件、质量表和图形，而不是看到保存前的空占位字段。
flightModelAdaptData = result;
flightModelAdaptData.output = output;
save(matFile, 'flightModelAdaptData', '-v7.3');
save(latestMatFile, 'flightModelAdaptData', '-v7.3');
writetable(result.qualitySummary, summaryCsv);
clear flightModelAdaptData;
end

function local_print_summary(result)
fprintf('\n3.2 最小预处理与等效回放完成：\n');
fprintf('  源数据：%s\n', result.source.file);
fprintf('  历程数：%d；隐藏真值访问：%d\n', ...
    result.source.historyCount, result.source.truthDataAccessed);
fprintf(['  传感器对象参数：来源=%s，通道数=%d，' ...
    '从3.1数据读取=%d\n'], ...
    result.measurementObjectParameters.configurationSource, ...
    height(result.measurementObjectParameters.channelTable), ...
    result.source.measurementParametersReadFromSource);
for i = 1:height(result.qualitySummary)
    row = result.qualitySummary(i,:);
    fprintf(['  %-22s samples=%d, steady=%d, transition=%d, ' ...
        'maxResidual=%.6g, replayAccepted=%d\n'], ...
        row.missionId{1}, row.sampleCount, row.steadyCount, ...
        row.transitionCount, row.maximumReplayResidual, ...
        row.replayAccepted);
    if result.experiments(i).replay.enabled
        names = result.experiments(i).replay.outputNames;
        truth = result.experiments(i).replay.rmsError;
        fprintf('    RMS：');
        for j = 1:numel(names)
            fprintf('%s=%.6g%s', names{j}, truth(j), ...
                local_separator(j, numel(names)));
        end
        fprintf('\n');
    end
end
fprintf('  总体验收：%d\n', result.validation.passed);
if result.output.saved
    fprintf('  输出：%s\n', result.output.matFile);
end
end

function value = local_separator(index, count)
if index < count
    value = ', ';
else
    value = '';
end
end

function experiment = local_empty_experiment()
experiment = struct( ...
    'experimentId', '', ...
    'missionId', '', ...
    'variantId', '', ...
    'sampleTime_s', NaN, ...
    'time_s', [], ...
    'rawMeasurement', struct(), ...
    'processedMeasurement', struct(), ...
    'modelInput', struct(), ...
    'labels', table(), ...
    'quality', struct(), ...
    'compensation', table(), ...
    'replay', local_empty_replay());
end

function replay = local_empty_replay()
replay = struct( ...
    'enabled', false, ...
    'modelType', '', ...
    'stateNames', {{}}, ...
    'outputNames', {{}}, ...
    'state', [], ...
    'modelOutput', struct(), ...
    'appliedLoadPower_W', [], ...
    'measuredOutputMatrix', [], ...
    'error', [], ...
    'rmsError', [], ...
    'maxAbsError', [], ...
    'maxResidualBySample', [], ...
    'convergeTagBySample', [], ...
    'maximumResidual', NaN, ...
    'nonzeroConvergeTagCount', 0, ...
    'evaluationCount', 0, ...
    'residualAccepted', false);
end

function model = local_empty_model_output(n)
model = struct();
names = {'Np','Ng','Pt3','Tt3','T45','Pt45', ...
    'HPC_Ncr','GT_Ncr','PT_Ncr'};
for i = 1:numel(names)
    model.(names{i}) = NaN(n,1);
end
end

function record = local_empty_compensation_record()
record = struct( ...
    'channel', '', ...
    'smoothingCutoff_Hz', NaN, ...
    'sensorBandwidth_radps', NaN, ...
    'inverseDynamicsApplied', false);
end

function local_require_fields(value, fields, context)
missing = fields(~isfield(value, fields));
if ~isempty(missing)
    error('sht:flightAdapt01:missingField', ...
        '%s 缺少字段：%s。', context, strjoin(missing, ', '));
end
end

function merged = local_merge_struct(base, override)
merged = base;
names = fieldnames(override);
for i = 1:numel(names)
    name = names{i};
    if isfield(merged, name) && isstruct(merged.(name)) && ...
            isscalar(merged.(name)) && isstruct(override.(name)) && ...
            isscalar(override.(name))
        merged.(name) = local_merge_struct(merged.(name), ...
            override.(name));
    else
        merged.(name) = override.(name);
    end
end
end

function value = local_char_row(value, name)
if isstring(value) && isscalar(value)
    value = char(value);
end
if ~(ischar(value) && (isempty(value) || isrow(value)))
    error('sht:flightAdapt01:badTextOption', ...
        '%s 必须为字符行向量或标量字符串。', name);
end
end
