function varargout = sht_flight_model_adapt_common(action, varargin)
%SHT_FLIGHT_MODEL_ADAPT_COMMON 第3.3阶段估计与验证共用的确定性模型接口。
%
% 本函数只封装两类必须在02/03程序之间严格一致的逻辑：
%   1) 第3.2阶段输出数据的读取、校验和估计矩阵构造；
%   2) 六维健康参数到100维健康向量的映射，以及二状态飞行历程回放。
%
% 隐藏健康真值不在本公共函数中读取。只有03验证入口有权访问
% flightData.validationData，避免估计程序通过公共函数间接泄漏真值。

if nargin < 1
    error('sht:flightAdaptCommon:missingAction', '必须给定操作名称。');
end

switch lower(char(action))
    case 'paths'
        varargout{1} = local_paths();
    case 'resolveflightdatafile'
        varargout{1} = local_resolve_flight_data_file(varargin{:});
    case 'parameterdefinitions'
        varargout{1} = local_parameter_definitions();
    case 'loadpreprocess'
        [varargout{1:nargout}] = local_load_preprocess(varargin{:});
    case 'measurementobjectcontract'
        varargout{1} = local_measurement_object_contract(varargin{:});
    case 'prepareexperiments'
        varargout{1} = local_prepare_experiments(varargin{:});
    case 'healthfromtheta'
        varargout{1} = local_health_from_theta(varargin{:});
    case 'replay'
        [varargout{1:nargout}] = local_replay(varargin{:});
    case 'residualstatistics'
        varargout{1} = local_residual_statistics(varargin{:});
    case 'outputnames'
        varargout{1} = local_output_names();
    case 'outputunits'
        varargout{1} = local_output_units();
    otherwise
        error('sht:flightAdaptCommon:unknownAction', ...
            '未知操作：%s。', char(action));
end
end

function paths = local_paths()
paths = struct();
paths.programDir = fileparts(mfilename('fullpath'));
paths.programRoot = fileparts(paths.programDir);
paths.testDataDir = fullfile(paths.programDir, 'TestData');
paths.flightDataDir = fullfile(paths.testDataDir, ...
    'flight_data_generation');
paths.middleDataDir = fullfile(paths.programDir, 'MiddleData');
paths.reportOutputRoot = fullfile(paths.programRoot, 'report_outputs');
paths.outputDir = fullfile(paths.reportOutputRoot, 'flight_model_adapt');
paths.latestPreprocessFile = fullfile(paths.middleDataDir, ...
    'flight_model_adapt_01_latest.mat');
paths.latestEstimationFile = fullfile(paths.middleDataDir, ...
    'flight_model_adapt_02_latest.mat');
paths.latestValidationFile = fullfile(paths.middleDataDir, ...
    'flight_model_adapt_03_latest.mat');
end

function filePath = local_resolve_flight_data_file(requestedFile)
% 优先使用合同中记录的原路径；目录迁移后按同名文件回落到TestData。
if nargin < 1 || isempty(requestedFile)
    error('sht:flightAdaptCommon:emptyFlightDataFile', ...
        '待解析的第3.1阶段飞参数据文件不得为空。');
end
requestedFile = char(string(requestedFile));
if isfile(requestedFile)
    filePath = char(java.io.File(requestedFile).getCanonicalPath());
    return;
end

[~, fileName, extension] = fileparts(requestedFile);
paths = local_paths();
candidate = fullfile(paths.flightDataDir, [fileName extension]);
if isfile(candidate)
    filePath = char(java.io.File(candidate).getCanonicalPath());
    return;
end
error('sht:flightAdaptCommon:missingFlightDataFile', ...
    ['第3.1阶段飞参数据文件不存在，且TestData中未找到同名文件：' ...
     '%s。'], requestedFile);
end

function params = local_parameter_definitions()
parameterIndex = (1:6).';
cIndex = [1; 2; 7; 8; 11; 12];
healthIndex = cIndex + 1;
parameterName = ["HPC_hpW"; "HPC_hpEf"; "GT_hpW"; ...
    "GT_hpEf"; "PT_hpW"; "PT_hpEf"];
component = ["HPC"; "HPC"; "GT"; "GT"; "PT"; "PT"];
physicalRole = ["flow"; "efficiency"; "flow"; ...
    "efficiency"; "flow"; "efficiency"];
initialValue = zeros(6,1);
lowerBound = -0.10*ones(6,1);
upperBound = 0.10*ones(6,1);
differenceDelta = 1e-4*ones(6,1);
params = table(parameterIndex, cIndex, healthIndex, parameterName, ...
    component, physicalRole, initialValue, lowerBound, upperBound, ...
    differenceDelta, 'VariableNames', {'parameter_index','c_index', ...
    'health_index','parameter_name','component','physical_role', ...
    'initial_value','lower_bound','upper_bound','difference_delta'});
end

function [data, filePath, fileHash] = local_load_preprocess(requestedFile)
paths = local_paths();
if nargin < 1 || isempty(requestedFile)
    filePath = paths.latestPreprocessFile;
else
    filePath = char(string(requestedFile));
end
if ~isfile(filePath)
    error('sht:flightAdaptCommon:missingPreprocessFile', ...
        '第3.2阶段输出文件不存在：%s。', filePath);
end
filePath = char(java.io.File(filePath).getCanonicalPath());
loaded = load(filePath, 'flightModelAdaptData');
if ~isfield(loaded, 'flightModelAdaptData') || ...
        ~isstruct(loaded.flightModelAdaptData) || ...
        ~isscalar(loaded.flightModelAdaptData)
    error('sht:flightAdaptCommon:invalidPreprocessFile', ...
        '文件中缺少标量结构体 flightModelAdaptData：%s。', filePath);
end
data = loaded.flightModelAdaptData;
local_validate_preprocess_data(data, filePath);
fileHash = sht_transient_model_adapt_common('fileHash', filePath);
end

function local_validate_preprocess_data(data, filePath)
required = {'program','version','shaftLoadInterfaceVersion', ...
    'source','measurementObjectParameters','experiments','validation'};
local_require_fields(data, required, 'flightModelAdaptData');
if ~strcmp(char(string(data.shaftLoadInterfaceVersion)), ...
        'Mkp_Mkg_external_torque_inputs_v2')
    error('sht:flightAdaptCommon:oldShaftLoadInterface', ...
        '第3.2结果仍使用旧扭矩语义，必须先重新运行当前版程序01：%s。', ...
        filePath);
end
if ~isfield(data.source, 'truthDataAccessed') || ...
        logical(data.source.truthDataAccessed)
    error('sht:flightAdaptCommon:preprocessTruthContaminated', ...
        ['第3.2阶段结果未证明 truthDataAccessed=false，拒绝将其作为' ...
         '参数估计输入：%s。'], filePath);
end
if ~isfield(data.source, 'measurementParametersReadFromSource') || ...
        logical(data.source.measurementParametersReadFromSource)
    error('sht:flightAdaptCommon:measurementParameterLeakage', ...
        ['第3.2阶段未证明传感器对象参数独立于第3.1观测文件，' ...
         '拒绝用于参数估计：%s。'], filePath);
end
local_validate_measurement_object_parameters( ...
    data.measurementObjectParameters);
if isempty(data.experiments) || ~isstruct(data.experiments)
    error('sht:flightAdaptCommon:noExperiments', ...
        '第3.2阶段结果不包含可用飞行历程。');
end
for q = 1:numel(data.experiments)
    experiment = data.experiments(q);
    local_require_fields(experiment, {'experimentId','time_s', ...
        'processedMeasurement','modelInput','quality','replay'}, ...
        sprintf('experiments(%d)', q));
    time = experiment.time_s(:);
    if numel(time) < 2 || any(~isfinite(time)) || any(diff(time) <= 0)
        error('sht:flightAdaptCommon:invalidExperimentTime', ...
            '%s 的时间轴必须有限且严格递增。', experiment.experimentId);
    end
    local_require_fields(experiment.processedMeasurement, ...
        [local_output_names(), {'Wf','Mkp','Mkg'}], ...
        [experiment.experimentId ' processedMeasurement']);
    local_require_fields(experiment.modelInput, ...
        {'Wf_kgps','Mkp_Nm','Mkg_Nm','Pt1_Pa','Tt1_K','Pamb_Pa'}, ...
        [experiment.experimentId ' modelInput']);
    if ~isfield(experiment.quality, 'usable') || ...
            numel(experiment.quality.usable) ~= numel(time) || ...
            ~all(logical(experiment.quality.usable(:)))
        error('sht:flightAdaptCommon:unusablePreprocessSample', ...
            ['%s 含第3.2阶段不可用样本。首轮3.3要求使用全部样本，' ...
             '因此不能静默删点。'], experiment.experimentId);
    end
    if ~isfield(experiment.replay, 'enabled') || ...
            ~logical(experiment.replay.enabled) || ...
            ~isfield(experiment.replay, 'modelType') || ...
            ~strcmp(experiment.replay.modelType, ...
            'two_state_zero_health_no_transient_effects')
        error('sht:flightAdaptCommon:invalidPreprocessReplay', ...
            '%s 不是第3阶段首轮要求的二状态零健康回放。', ...
            experiment.experimentId);
    end
end
end

function contract = local_measurement_object_contract(data)
local_require_fields(data, {'version','source', ...
    'measurementObjectParameters'}, 'flightModelAdaptData');
local_require_fields(data.source, ...
    {'measurementParametersReadFromSource'}, 'flightModelAdaptData.source');
local_validate_measurement_object_parameters( ...
    data.measurementObjectParameters);

parameters = data.measurementObjectParameters;
channelTable = parameters.channelTable;
contract = struct();
contract.preprocessVersion = char(string(data.version));
contract.schemaVersion = char(string(parameters.schemaVersion));
contract.configurationSource = ...
    char(string(parameters.configurationSource));
contract.channelCount = height(channelTable);
contract.channelNames = cellstr(string(channelTable.channel));
contract.biasDistribution = char(string(parameters.biasDistribution));
contract.noiseDistribution = char(string(parameters.noiseDistribution));
contract.delayDistribution = char(string(parameters.delayDistribution));
contract.measurementParametersReadFromSource = ...
    logical(data.source.measurementParametersReadFromSource);
end

function local_validate_measurement_object_parameters(parameters)
if ~isstruct(parameters) || ~isscalar(parameters)
    error('sht:flightAdaptCommon:invalidMeasurementObjectParameters', ...
        '第3.2传感器对象参数必须为标量结构体。');
end
required = {'schemaVersion','enabled','configurationSource', ...
    'biasDistribution','noiseDistribution','delayDistribution', ...
    'delayChoices_s','channelTable'};
local_require_fields(parameters, required, ...
    'flightModelAdaptData.measurementObjectParameters');
if ~isscalar(parameters.enabled) || ~logical(parameters.enabled)
    error('sht:flightAdaptCommon:disabledMeasurementObjectParameters', ...
        '第3.2传感器对象参数必须处于启用状态。');
end
if isempty(char(string(parameters.configurationSource)))
    error('sht:flightAdaptCommon:missingMeasurementConfigurationSource', ...
        '第3.2传感器对象参数未记录配置来源。');
end
if ~strcmp(char(string(parameters.biasDistribution)), ...
        'uniform_symmetric') || ...
        ~strcmp(char(string(parameters.noiseDistribution)), ...
        'zero_mean_gaussian') || ...
        ~strcmp(char(string(parameters.delayDistribution)), 'fixed_zero') || ...
        ~isequal(parameters.delayChoices_s(:), 0)
    error('sht:flightAdaptCommon:unsupportedMeasurementContract', ...
        ['首轮3.3只接受对称均匀偏置、高斯白噪声和' ...
         '零独立纯延迟的第3.2传感器对象合同。']);
end

channelTable = parameters.channelTable;
tableFields = {'channel','unit','biasLower','biasUpper','noiseStd', ...
    'timeConstant_s','bandwidth_radps','delayLower_s','delayUpper_s'};
if ~istable(channelTable) || ...
        ~all(ismember(tableFields, channelTable.Properties.VariableNames))
    error('sht:flightAdaptCommon:invalidMeasurementObjectTable', ...
        '第3.2传感器对象参数表字段不完整。');
end
expectedChannels = {'Np','Ng','Wf','T45','Mkg','Mkp','Pt1','Tt1', ...
    'Pt3','Tt3','Pt45','Pt5','Tt5','Pamb','Tamb'};
actualChannels = cellstr(string(channelTable.channel));
if height(channelTable) ~= numel(expectedChannels) || ...
        numel(unique(actualChannels)) ~= numel(actualChannels) || ...
        ~all(ismember(expectedChannels, actualChannels))
    error('sht:flightAdaptCommon:measurementObjectChannelSet', ...
        '第3.2传感器对象参数必须唯一覆盖15个正式测量通道。');
end
numericFields = {'biasLower','biasUpper','noiseStd','timeConstant_s', ...
    'bandwidth_radps','delayLower_s','delayUpper_s'};
for i = 1:numel(numericFields)
    value = channelTable.(numericFields{i});
    if ~isnumeric(value) || any(~isfinite(value))
        error('sht:flightAdaptCommon:nonfiniteMeasurementObjectValue', ...
            '传感器对象参数 %s 必须全部有限。', ...
            numericFields{i});
    end
end
if any(channelTable.biasLower > channelTable.biasUpper) || ...
        any(channelTable.noiseStd < 0) || ...
        any(channelTable.timeConstant_s <= 0) || ...
        any(channelTable.bandwidth_radps <= 0) || ...
        any(channelTable.delayLower_s ~= 0) || ...
        any(channelTable.delayUpper_s ~= 0) || ...
        any(abs(channelTable.timeConstant_s .* ...
        channelTable.bandwidth_radps - 1) > 1e-10)
    error('sht:flightAdaptCommon:invalidMeasurementObjectValue', ...
        '第3.2传感器对象的偏置、噪声、带宽或零延迟配置无效。');
end
end

function experiments = local_prepare_experiments(sourceExperiments)
experiments = sourceExperiments(:);
for q = 1:numel(experiments)
    measurement = experiments(q).processedMeasurement;
    measuredOutput = local_measurement_matrix(measurement);
    n = numel(experiments(q).time_s);
    if size(measuredOutput,1) ~= n || size(measuredOutput,2) ~= 6 || ...
            any(~isfinite(measuredOutput(:)))
        error('sht:flightAdaptCommon:invalidMeasuredOutput', ...
            '%s 的六通道测量输出无效。', experiments(q).experimentId);
    end
    experiments(q).measuredOutput = measuredOutput;
    experiments(q).outputFields = local_output_names();
    experiments(q).outputUnits = local_output_units();
    experiments(q).outputScale = ...
        sht_transient_model_adapt_common('outputScale', measuredOutput);
    experiments(q).integrationWeight_s = ...
        sht_transient_model_adapt_common( ...
        'integrationWeights', experiments(q).time_s(:));
    % 用户已明确要求使用3.2输出的全部数据。这里不读取
    % healthEstimationEligible，质量掩码固定为全真；输入校验已保证全部
    % quality.usable 均为真。
    experiments(q).estimationMask = true(n,1);
end
end

function health = local_health_from_theta(theta, healthLength, params)
if nargin < 3 || isempty(params)
    params = local_parameter_definitions();
end
theta = theta(:);
if numel(theta) ~= height(params) || any(~isfinite(theta))
    error('sht:flightAdaptCommon:invalidTheta', ...
        '紧凑健康参数必须为%d维有限列向量。', height(params));
end
if ~(isscalar(healthLength) && isfinite(healthLength) && ...
        healthLength == round(healthLength) && ...
        healthLength >= max(params.health_index))
    error('sht:flightAdaptCommon:invalidHealthLength', ...
        '100维健康向量长度配置无效。');
end
health = zeros(healthLength,1);
health(params.health_index) = theta;
end

function [outputs, diagnostics, trajectories] = local_replay( ...
        engine, cfg, experiments, health, options)
if nargin < 5 || isempty(options)
    options = struct();
end
if ~isfield(options, 'modelResidualAcceptance')
    options.modelResidualAcceptance = 1e-2;
end
if ~(isscalar(options.modelResidualAcceptance) && ...
        isfinite(options.modelResidualAcceptance) && ...
        options.modelResidualAcceptance > 0)
    error('sht:flightAdaptCommon:invalidResidualAcceptance', ...
        'modelResidualAcceptance 必须为有限正数。');
end
health = health(:);
if numel(health) ~= cfg.engine.interface.healthLength || ...
        any(~isfinite(health))
    error('sht:flightAdaptCommon:invalidHealthVector', ...
        '发动机回放要求完整有限的健康向量。');
end

nHistory = numel(experiments);
outputs = cell(nHistory,1);
trajectories = repmat(local_empty_trajectory(), nHistory,1);
diagnostics = repmat(local_empty_diagnostic(), nHistory,1);
for q = 1:nHistory
    [outputs{q}, diagnostics(q), trajectories(q)] = ...
        local_replay_history(engine, cfg, experiments(q), health, options);
end
end

function [modelOutput, diagnostic, trajectory] = local_replay_history( ...
        engine, cfg, experiment, health, options)
time = experiment.time_s(:);
input = experiment.modelInput;
measurement = experiment.processedMeasurement;
x = [measurement.Np(1); measurement.Ng(1)];

% 每次参数扰动、每条历程都按当前候选健康参数重建共同工作初值。
% 这一步只初始化4个气动共同工作变量，Np/Ng动态状态仍取测量首点。
cfg.engine.boundary.Mkp = input.Mkp_Nm(1);
cfg.engine.boundary.Mkg = input.Mkg_Nm(1);
cfg.engine.boundary.ptLoadInputMode = 'torque';
cfg.engine.boundary.gtLoadInputMode = 'torque';
seedLoadPower = input.Mkp_Nm(1) * x(1) * pi / 30;
seedPoint = struct('Np_mean',x(1), 'Ng_mean',x(2), ...
    'Wf_mean',input.Wf_kgps(1), ...
    'Mkp_mean',input.Mkp_Nm(1), 'Mkg_mean',input.Mkg_Nm(1), ...
    'target_load_power_mean',seedLoadPower, ...
    'Pt1_mean',input.Pt1_Pa(1), 'Tt1_mean',input.Tt1_K(1), ...
    'Pamb_mean',input.Pamb_Pa(1));
seedEvaluation = sht_steady_model_adapt_common( ...
    'evaluateTransientPoint', engine, cfg, seedPoint, health);
if numel(seedEvaluation.varIte) < 4 || ...
        any(~isfinite(seedEvaluation.varIte(1:4)))
    error('sht:flightAdaptCommon:invalidReplaySeed', ...
        '%s 的共同工作初值无效。', experiment.experimentId);
end
local_reset_var_start(engine, cfg, ...
    [seedEvaluation.varIte(1:4); x]);

n = numel(time);
model = local_empty_model(n);
state = NaN(n,2);
appliedLoadPower = NaN(n,1);
maxResidualBySample = NaN(n,1);
convergeTagBySample = zeros(n,1);
evaluationCount = 1; % 包含共同工作初值求值。

for k = 1:n
    boundary = local_boundary_at(cfg, input, health, k, x);
    [xDot1, y1, diag1] = sht_engine_derivative( ...
        engine, x, input.Wf_kgps(k), boundary);
    local_validate_evaluation(experiment.experimentId, time(k), ...
        x, xDot1, y1, diag1);
    state(k,:) = x.';
    appliedLoadPower(k) = boundary.power;
    model = local_assign_model(model, y1, k);
    maxResidualBySample(k) = max([maxResidualBySample(k), ...
        diag1.maxErr], [], 'omitnan');
    convergeTagBySample(k) = max(abs([convergeTagBySample(k), ...
        diag1.convergeTag]));
    evaluationCount = evaluationCount + 1;

    if k == n
        continue;
    end
    dt = time(k+1)-time(k);
    xPredict = x + dt*xDot1;
    boundaryPredict = local_boundary_at( ...
        cfg, input, health, k+1, xPredict);
    [xDot2, y2, diag2] = sht_engine_derivative( ...
        engine, xPredict, input.Wf_kgps(k+1), boundaryPredict);
    local_validate_evaluation(experiment.experimentId, time(k+1), ...
        xPredict, xDot2, y2, diag2);

    xNext = x + 0.5*dt*(xDot1+xDot2);
    boundaryEnd = local_boundary_at( ...
        cfg, input, health, k+1, xNext);
    [xDotEnd, yEnd, diagEnd] = sht_engine_derivative( ...
        engine, xNext, input.Wf_kgps(k+1), boundaryEnd);
    local_validate_evaluation(experiment.experimentId, time(k+1), ...
        xNext, xDotEnd, yEnd, diagEnd);
    maxResidualBySample(k+1) = max([maxResidualBySample(k+1), ...
        diag2.maxErr, diagEnd.maxErr], [], 'omitnan');
    convergeTagBySample(k+1) = max(abs([convergeTagBySample(k+1), ...
        diag2.convergeTag, diagEnd.convergeTag]));
    evaluationCount = evaluationCount + 2;
    x = xNext;
end

modelOutput = local_model_matrix(model);
maximumResidual = max([seedEvaluation.maxErr; maxResidualBySample], ...
    [], 'omitnan');
diagnostic = local_empty_diagnostic();
diagnostic.experimentId = experiment.experimentId;
diagnostic.sampleCount = n;
diagnostic.evaluationCount = evaluationCount;
diagnostic.maximumResidual = maximumResidual;
diagnostic.nonzeroConvergeTagCount = nnz(convergeTagBySample);
diagnostic.seedResidual = seedEvaluation.maxErr;
diagnostic.accepted = maximumResidual < ...
    options.modelResidualAcceptance;

trajectory = local_empty_trajectory();
trajectory.experimentId = experiment.experimentId;
trajectory.time_s = time;
trajectory.state = state;
trajectory.modelOutput = modelOutput;
trajectory.modelOutputStruct = model;
trajectory.appliedLoadPower_W = appliedLoadPower;
trajectory.maxResidualBySample = maxResidualBySample;
trajectory.convergeTagBySample = convergeTagBySample;
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
stepInValue = zeros(cfg.engine.interface.stepInLength,1);
stepInValue(21:(20+numel(seed))) = seed(:);
stepIn = libpointer('doublePtr', stepInValue);
stepOut = libpointer('doublePtr', ...
    zeros(cfg.engine.interface.stepOutLength,1));
engPtrInit.eng = libstruct(engine.engineStructName);
engPtr = libstruct(engine.enginePointerName, engPtrInit);
calllib(engine.libraryName, 'DLL_SHT_varIteInit', ...
    stepIn, stepOut, engPtr);
end

function local_validate_evaluation(experimentId, time, state, ...
        stateDerivative, output, diagnostic)
value = [state(:); stateDerivative(:); output.Np; output.Ng; ...
    output.Pt3; output.Tt3; output.Tt45; output.Pt45; ...
    diagnostic.maxErr; diagnostic.convergeTag];
if any(~isfinite(value))
    error('sht:flightAdaptCommon:nonfiniteReplay', ...
        '%s 在t=%.9g s出现非有限状态、输出或诊断量。', ...
        experimentId, time);
end
end

function model = local_assign_model(model, output, k)
model.Np(k) = output.Np;
model.Ng(k) = output.Ng;
model.Pt3(k) = output.Pt3;
model.Tt3(k) = output.Tt3;
model.T45(k) = output.Tt45;
model.Pt45(k) = output.Pt45;
end

function stats = local_residual_statistics(experiments, modelOutputs, ...
        outputResidualWeight)
if nargin < 3 || isempty(outputResidualWeight)
    outputResidualWeight = ones(1,6);
end
if ~isnumeric(outputResidualWeight) || ...
        ~isequal(size(outputResidualWeight),[1,6]) || ...
        any(~isfinite(outputResidualWeight)) || ...
        any(outputResidualWeight <= 0)
    error('sht:flightAdaptCommon:invalidOutputWeight', ...
        'outputResidualWeight必须为1×6有限正向量。');
end
if numel(modelOutputs) ~= numel(experiments)
    error('sht:flightAdaptCommon:outputHistoryCount', ...
        '模型输出历程数与实验数不一致。');
end

nOutput = 6;
residuals = cell(numel(experiments),1);
physicalResiduals = cell(numel(experiments),1);
cost = 0;
sumSquaredPhysical = zeros(1,nOutput);
totalWeight = 0;
historyRms = NaN(numel(experiments),nOutput);
sqrtOutputWeight = sqrt(outputResidualWeight);
for q = 1:numel(experiments)
    model = modelOutputs{q};
    measured = experiments(q).measuredOutput;
    if ~isequal(size(model),size(measured)) || any(~isfinite(model(:)))
        error('sht:flightAdaptCommon:invalidModelOutput', ...
            '%s 的模型输出尺寸错误或包含非有限值。', ...
            experiments(q).experimentId);
    end
    physical = measured-model;
    normalized = (physical./experiments(q).outputScale) .* ...
        sqrtOutputWeight;
    weight = experiments(q).integrationWeight_s(:);
    residuals{q} = normalized;
    physicalResiduals{q} = physical;
    cost = cost + sum(weight.*sum(normalized.^2,2));
    sumSquaredPhysical = sumSquaredPhysical + ...
        sum(physical.^2.*weight,1);
    totalWeight = totalWeight + sum(weight);
    historyRms(q,:) = sqrt(sum(physical.^2.*weight,1)/sum(weight));
end
if totalWeight <= 0
    error('sht:flightAdaptCommon:noResidualWeight', ...
        '全部飞行历程的积分权重总和必须为正。');
end
stats = struct();
stats.cost = cost;
stats.residuals = residuals;
stats.physicalResiduals = physicalResiduals;
stats.rmsPhysical = sqrt(sumSquaredPhysical/totalWeight);
stats.historyRmsPhysical = historyRms;
stats.totalIntegrationWeight_s = totalWeight;
stats.outputResidualWeight = outputResidualWeight;
end

function matrix = local_measurement_matrix(measurement)
matrix = [measurement.Np(:), measurement.Ng(:), ...
    measurement.Pt3(:), measurement.Tt3(:), measurement.T45(:), ...
    measurement.Pt45(:)];
end

function matrix = local_model_matrix(model)
matrix = [model.Np,model.Ng,model.Pt3,model.Tt3, ...
    model.T45,model.Pt45];
end

function names = local_output_names()
names = {'Np','Ng','Pt3','Tt3','T45','Pt45'};
end

function units = local_output_units()
units = {'rpm','rpm','Pa','K','K','Pa'};
end

function model = local_empty_model(n)
model = struct('Np',NaN(n,1), 'Ng',NaN(n,1), ...
    'Pt3',NaN(n,1), 'Tt3',NaN(n,1), 'T45',NaN(n,1), ...
    'Pt45',NaN(n,1));
end

function diagnostic = local_empty_diagnostic()
diagnostic = struct('experimentId','', 'sampleCount',0, ...
    'evaluationCount',0, 'maximumResidual',NaN, ...
    'nonzeroConvergeTagCount',0, 'seedResidual',NaN, ...
    'accepted',false);
end

function trajectory = local_empty_trajectory()
trajectory = struct('experimentId','', 'time_s',[], 'state',[], ...
    'modelOutput',[], 'modelOutputStruct',struct(), ...
    'appliedLoadPower_W',[], 'maxResidualBySample',[], ...
    'convergeTagBySample',[]);
end

function local_require_fields(value, fields, context)
missing = fields(~isfield(value,fields));
if ~isempty(missing)
    error('sht:flightAdaptCommon:missingField', ...
        '%s缺少字段：%s。', context, strjoin(missing,', '));
end
end
