function cfg = sht_validate_runtime_config(cfg)
%SHT_VALIDATE_RUNTIME_CONFIG 归一化并校验 m 程序运行配置。
% 设计原则：
%   1) 仿真运行只依赖 cfg，不再依赖 baseline；
%   2) cfg.engine.initial 是本次仿真 t=0 发动机物理初值的唯一权威来源；
%   3) 发动机边界输入集中在 cfg.engine.boundary；
%   4) 控制器区分 DPpara、initial 和 linearModel：设计点基准、仿真初值、当前激活线性化系数；
%   5) 未在仿真中使用的线性化矩阵、EKF 参数和诊断量不在这里补齐。

if nargin < 1 || isempty(cfg) || ~isstruct(cfg)
    error('sht:config:missingCfg', 'cfg must be a non-empty struct. Use sht_default_config() to build defaults.');
end

cfg = local_validate_time_and_method(cfg);
cfg = local_validate_engine(cfg);
cfg = local_validate_reference(cfg);
cfg = local_validate_sensor(cfg);
cfg = local_validate_actuator(cfg);
cfg = local_validate_controller(cfg);
cfg = local_validate_plot(cfg);
end

function cfg = local_validate_time_and_method(cfg)
% 仿真步长和控制采样步长属于运行配置，不是发动机模型固有参数。
if ~isfield(cfg, 'stopTime') || isempty(cfg.stopTime)
    cfg.stopTime = 10;
end
if ~isfield(cfg, 'Tsim') || isempty(cfg.Tsim)
    cfg.Tsim = 0.025;
end
if ~isfield(cfg, 'Tctrl') || isempty(cfg.Tctrl)
    cfg.Tctrl = cfg.Tsim;
end
if ~isscalar(cfg.Tsim) || ~isscalar(cfg.Tctrl) || cfg.Tsim <= 0 || cfg.Tctrl <= 0
    error('sht:config:invalidStep', 'Tsim and Tctrl must be positive scalars.');
end
ratio = cfg.Tctrl / cfg.Tsim;
if abs(ratio - round(ratio)) > 1e-9
    error('sht:config:stepRatio', ...
        'Tctrl/Tsim must be an integer in this implementation. Got %.15g.', ratio);
end
if ~isfield(cfg, 'integrationMethod') || isempty(cfg.integrationMethod)
    cfg.integrationMethod = 'euler2';
end
if strcmpi(cfg.integrationMethod, 'euler1')
    cfg.integrationMethod = 'euler1';
elseif strcmpi(cfg.integrationMethod, 'euler2')
    cfg.integrationMethod = 'euler2';
else
    error('sht:config:integrationMethod', ...
        'integrationMethod must be ''euler1'' or ''euler2''.');
end
if ~isfield(cfg, 'throwOnEngineNonconvergence') || isempty(cfg.throwOnEngineNonconvergence)
    cfg.throwOnEngineNonconvergence = false;
end
end

function cfg = local_validate_engine(cfg)
% 发动机本体配置：接口信息、状态初值、输入初值、边界输入。
% 重要约定：cfg.engine.initial 是本次仿真 t=0 发动机物理初值的唯一权威来源。
if ~isfield(cfg, 'engine') || isempty(cfg.engine) || ~isstruct(cfg.engine)
    error('sht:config:missingEngine', 'cfg.engine is required. Use sht_default_config() to build it.');
end
engine = cfg.engine;

engine.modelMode = local_get_field(engine, 'modelMode', 0);
if ~isscalar(engine.modelMode) || ~isfinite(engine.modelMode) || ...
        ~ismember(engine.modelMode, [0, 1])
    error('sht:config:badModelMode', ...
        'cfg.engine.modelMode必须是0（三部件）或1（六部件）。');
end
engine.modelMode = round(engine.modelMode);
if ~isfield(engine, 'modelConfiguration')
    engine.modelConfiguration = '';
end

if ~isfield(engine, 'interface') || isempty(engine.interface) || ~isstruct(engine.interface)
    engine.interface = struct();
end
engine.interface.controlDir = local_get_field(engine.interface, 'controlDir', fileparts(mfilename('fullpath')));
engine.interface.libraryName = local_get_field(engine.interface, 'libraryName', 'GTESS');
engine.interface.headerName = local_get_field(engine.interface, 'headerName', 'GTESS.h');
engine.interface.engineStructName = local_get_field(engine.interface, 'engineStructName', 'EngineTurboshaft');
engine.interface.enginePointerName = local_get_field(engine.interface, 'enginePointerName', 'EngineSHTPointer');
engine.interface.stepInLength = local_get_field(engine.interface, 'stepInLength', 512);
engine.interface.stepOutLength = local_get_field(engine.interface, 'stepOutLength', 128);
if engine.interface.stepInLength ~= 512 || engine.interface.stepOutLength ~= 128
    error('sht:config:dllInterfaceSize', ...
        'GTESS SHT DLL requires stepInLength=512 and stepOutLength=128.');
end
engine.interface.healthLength = local_get_field(engine.interface, 'healthLength', 159);
engine.interface.healthStartIndex = local_get_field(engine.interface, 'healthStartIndex', 41);
engine.interface.healthScheduleEnableIndex = local_get_field( ...
    engine.interface, 'healthScheduleEnableIndex', 18);
engine.interface.inletBoundaryModeIndex = local_get_field( ...
    engine.interface, 'inletBoundaryModeIndex', 17);
if engine.interface.stepInLength < engine.interface.healthStartIndex + engine.interface.healthLength - 1
    error('sht:config:stepInTooShort', ...
        'cfg.engine.interface.stepInLength must cover healthStartIndex:healthStartIndex+healthLength-1.');
end

engine.modelType = local_get_field(engine, 'modelType', 'GTESS_SHT_DLL');
engine.stateNames = local_get_field(engine, 'stateNames', {'Np', 'Ng'});
engine.inputNames = local_get_field(engine, 'inputNames', ...
    {'Np', 'Ng', 'Wf', 'A8', 'Mkp', 'Mkg', 'HpcAlpha', 'health'});
engine.outputMap = local_get_field(engine, 'outputMap', 'EngineTurboshaftStruct');
heatStateEnabled = false;
if isfield(engine, 'transientEffects') && ~isempty(engine.transientEffects)
    engine.transientEffects = local_validate_transient_effects(engine, engine.interface);
    heatStateEnabled = engine.transientEffects.enabled;
end

if ~isfield(engine, 'initial') || isempty(engine.initial) || ~isstruct(engine.initial)
    error('sht:config:missingEngineInitial', 'cfg.engine.initial is required.');
end
initial = engine.initial;
% 转子初值的人机配置入口是 Np0/Ng0；state 是发动机积分器使用的派生状态向量。
% 如果旧配置只给了 state，则兼容性地反推 Np0/Ng0；如果二者同时存在，以 Np0/Ng0 为准重建 state。
hasState = isfield(initial, 'state') && ~isempty(initial.state);
if hasState
    initial.state = initial.state(:);
    expectedStateCount = 2;
    if heatStateEnabled
        expectedStateCount = engine.transientEffects.derivativeOutputCount;
    end
    if numel(initial.state) ~= expectedStateCount
        error('sht:config:engineStateSize', ...
            'cfg.engine.initial.state must contain %d states for the selected engine mode.', ...
            expectedStateCount);
    end
end
if ~isfield(initial, 'Np0') || isempty(initial.Np0)
    if hasState
        initial.Np0 = initial.state(1);
    else
        error('sht:config:missingEngineNp0', 'cfg.engine.initial.Np0 is required.');
    end
end
if ~isfield(initial, 'Ng0') || isempty(initial.Ng0)
    if hasState
        initial.Ng0 = initial.state(2);
    else
        error('sht:config:missingEngineNg0', 'cfg.engine.initial.Ng0 is required.');
    end
end
initial.Np0 = initial.Np0(1);
initial.Ng0 = initial.Ng0(1);
if heatStateEnabled
    if ~hasState
        error('sht:config:missingTransientTemperatureState', ...
            ['Heat-state mode requires cfg.engine.initial.state to match ' ...
             'the active 2502/2503 transient topology.']);
    end
    % Np0/Ng0 仍是转子初值的人机入口；其余热状态由参数资产初始化并原样保留。
    initial.state(1:2) = [initial.Np0; initial.Ng0];
else
    initial.state = [initial.Np0; initial.Ng0];
end
initial.Wf0 = local_get_field(initial, 'Wf0', []);
initial.power0 = local_get_field(initial, 'power0', []);
initial.A80 = local_get_field(initial, 'A80', []);
if isempty(initial.Wf0) || isempty(initial.power0) || isempty(initial.A80)
    error('sht:config:missingEngineInputInitial', ...
        'cfg.engine.initial.Wf0, power0 and A80 are required engine input initial values.');
end
initial.T45 = local_get_field(initial, 'T45', NaN);
initial.Mkp = local_get_field(initial, 'Mkp', NaN);
initial.Mkg = local_get_field(initial, 'Mkg', NaN);

if ~isfield(engine, 'boundary') || isempty(engine.boundary) || ~isstruct(engine.boundary)
    engine.boundary = struct();
end
% 兼容早期 cfg.engine.A8/cfg.engine.power 覆盖写法；正式接口使用 cfg.engine.boundary。
if isfield(engine, 'A8') && ~isempty(engine.A8) && ~isfield(engine.boundary, 'A8')
    engine.boundary.A8 = engine.A8;
end
if isfield(engine, 'power') && ~isempty(engine.power) && ~isfield(engine.boundary, 'power')
    engine.boundary.power = engine.power;
end
engine.boundary.A8 = local_get_field(engine.boundary, 'A8', initial.A80);
engine.boundary.power = local_get_field(engine.boundary, 'power', initial.power0);
engine.boundary.hpsPower = local_get_field(engine.boundary, 'hpsPower', 0);
engine.boundary.ptLoadInputMode = local_get_field( ...
    engine.boundary, 'ptLoadInputMode', 'power');
engine.boundary.gtLoadInputMode = local_get_field( ...
    engine.boundary, 'gtLoadInputMode', 'power');
if isfinite(initial.Mkp) && ...
        (~isfield(engine.boundary, 'Mkp') || isempty(engine.boundary.Mkp))
    engine.boundary.Mkp = initial.Mkp;
end
if engine.interface.healthScheduleEnableIndex ~= 18 || ...
        engine.interface.healthScheduleEnableIndex > engine.interface.stepInLength
    error('sht:config:healthScheduleSwitchIndex', ...
        ['健康修正调度开关必须位于MATLAB stepIn(18)，对应C端stepIn[17]。' ...
         '该位置属于基础输入区stepIn(1:40)中的保留字段。']);
end
if engine.interface.inletBoundaryModeIndex ~= 17 || ...
        engine.interface.inletBoundaryModeIndex > engine.interface.stepInLength
    error('sht:config:inletBoundaryModeIndex', ...
        ['进口边界模式开关必须位于MATLAB stepIn(17)，对应C端stepIn[16]。' ...
         '健康参数调度开关继续使用stepIn(18)。']);
end
if isfinite(initial.Mkg) && ...
        (~isfield(engine.boundary, 'Mkg') || isempty(engine.boundary.Mkg))
    engine.boundary.Mkg = initial.Mkg;
end
engine.boundary.hpcAlpha = local_get_field(engine.boundary, 'hpcAlpha', 0);
engine.boundary.inletBoundaryMode = local_get_field( ...
    engine.boundary, 'inletBoundaryMode', 0);
engine.boundary.altitude = local_get_field(engine.boundary, 'altitude', 0);
engine.boundary.Mach = local_get_field(engine.boundary, 'Mach', 0);
engine.boundary.deltaTemperature = local_get_field( ...
    engine.boundary, 'deltaTemperature', 0);
% 复用正式写入函数完成模式相关字段检查，确保配置校验和实际DLL调用
% 不会形成两套逐渐漂移的接口规则。
sht_apply_inlet_boundary_stepin(zeros(20, 1), engine.boundary);
engine.boundary.health = local_column(local_get_field(engine.boundary, 'health', zeros(engine.interface.healthLength, 1)), engine.interface.healthLength);
engine.boundary.healthScheduleEnabled = local_get_field( ...
    engine.boundary, 'healthScheduleEnabled', false);
if ~isscalar(engine.boundary.healthScheduleEnabled) || ...
        ~(islogical(engine.boundary.healthScheduleEnabled) || ...
          isnumeric(engine.boundary.healthScheduleEnabled)) || ...
        ~isfinite(double(engine.boundary.healthScheduleEnabled)) || ...
        ~ismember(double(engine.boundary.healthScheduleEnabled), [0, 1])
    error('sht:config:healthScheduleEnable', ...
        'cfg.engine.boundary.healthScheduleEnabled必须为逻辑量或数值0/1。');
end
engine.boundary.healthScheduleEnabled = ...
    logical(engine.boundary.healthScheduleEnabled);
% 三部件和六部件模型都支持DLL内部实时调度。具体表数量、健康参数
% 下标及调度坐标由初始化接口按modelMode分别校验，避免在通用配置层
% 误拒绝三部件13表调度，也不在此重复维护模式相关参数字典。

% 在统一配置入口完成一次初值解析。普通闭环默认沿用功率指令模式；
% 回放/辨识程序会显式改为 torque 模式并给定 Mkp/Mkg。
engine.boundary = sht_resolve_shaft_load_boundary( ...
    engine.boundary, initial.state);
initial.Mkp = engine.boundary.Mkp;
initial.Mkg = engine.boundary.Mkg;
engine.initial = initial;

cfg.engine = engine;
end

function effects = local_validate_transient_effects(engine, interface)
% 仅在显式启用时扩展状态：三部件Kurzke为15维，六部件Kurzke为27维，
% 六部件Visser为29维。发动机三/六部件拓扑由engine.modelMode决定，
% 热模型拓扑由stepIn(342)中的thermalModelMode明确选择。
effects = local_get_field(engine, 'transientEffects', struct());
effects.enabled = local_get_field(effects, 'enabled', false);
if ~isscalar(effects.enabled) || ...
        ~(islogical(effects.enabled) || isnumeric(effects.enabled)) || ...
        ~isfinite(double(effects.enabled)) || ...
        ~ismember(double(effects.enabled), [0, 1])
    error('sht:config:transientEffectsEnable', ...
        'cfg.engine.transientEffects.enabled must be logical false/true or numeric 0/1.');
end
effects.enabled = logical(effects.enabled);

if ~effects.enabled
    effects.stepInTemplate = zeros(interface.stepInLength, 1);
    effects.temperatureStateStartIndex = 301;
    effects.derivativeOutputCount = 2;
    effects.validOutputIndex = 16;
    return;
end

if ~isfield(effects, 'stepInTemplate') || isempty(effects.stepInTemplate)
    error('sht:config:missingTransientStepInTemplate', ...
        'Heat-state mode requires cfg.engine.transientEffects.stepInTemplate.');
end
effects.stepInTemplate = effects.stepInTemplate(:);
if numel(effects.stepInTemplate) ~= interface.stepInLength || ...
        any(~isfinite(effects.stepInTemplate))
    error('sht:config:transientStepInTemplate', ...
        'The transient stepIn template must contain 512 finite values.');
end

% MATLAB 下标 341:348 对应 C 下标 340:347。所有离散控制量都按
% “与目标值相差不超过 1e-6”解释，不依赖 double 恰好表示某个整数。
switchValue = effects.stepInTemplate(341:348).';
binaryValue = switchValue(3:7);
componentMask = round(switchValue(8));
heatFeedbackEnabled = logical(round(switchValue(5)));
heatStateEnabled = logical(round(switchValue(4)));
clearanceEnabled = logical(round(switchValue(6)));
clearanceFeedbackEnabled = logical(round(switchValue(7)));
parameterLayoutVersion = 2502;
thermalModelMode = round(switchValue(2));
if engine.modelMode == 1
    parameterLayoutVersion = 2503;
end
if engine.modelMode == 1 || thermalModelMode == 3 || ...
        isfield(effects,'thermalModelConfiguration')
    if ~isfield(effects,'thermalModelConfiguration') || ...
            ~isstruct(effects.thermalModelConfiguration) || ...
            ~all(isfield(effects.thermalModelConfiguration, ...
            {'thermalModelMode','configVersion','parameterCount','parameterVector'}))
        error('sht:config:missingThermalModelConfiguration', ...
            ['六部件增强瞬态模型必须通过' ...
             'thermalModelConfiguration一次性初始化标称热参数。']);
    end
    thermalConfiguration = effects.thermalModelConfiguration;
    expectedThermalVersion = nan;
    expectedThermalParameterCount = nan;
    if thermalModelMode == 1
        expectedThermalVersion = 250201 + 100*engine.modelMode;
        expectedThermalParameterCount = 147;
    elseif thermalModelMode == 3
        expectedThermalVersion = 250203 + 100*engine.modelMode;
        expectedThermalParameterCount = 178;
    end
    if thermalConfiguration.thermalModelMode ~= thermalModelMode || ...
            thermalConfiguration.configVersion ~= expectedThermalVersion || ...
            thermalConfiguration.parameterCount ~= expectedThermalParameterCount || ...
            numel(thermalConfiguration.parameterVector) ~= ...
                expectedThermalParameterCount || ...
            any(~isfinite(thermalConfiguration.parameterVector(:)))
        error('sht:config:thermalModelConfigurationMismatch', ...
            ['标称热配置必须与stepIn中的thermalModelMode一致，并使用' ...
             '该模型唯一的版本号和有限参数向量。']);
    end
    if thermalModelMode == 3
        local_validate_cooling_split_configuration(effects);
    end
end
switchesInvalid = abs(switchValue(1) - 1) > 1e-6 || ...
        abs(switchValue(2) - thermalModelMode) > 1e-6 || ...
        ~ismember(thermalModelMode, [1, 3]) || ...
        any(abs(binaryValue - round(binaryValue)) > 1e-6) || ...
        any(round(binaryValue) < 0 | round(binaryValue) > 1) || ...
        abs(switchValue(8) - componentMask) > 1e-6 || ...
        componentMask < 0 || componentMask > 15 || ...
        (clearanceFeedbackEnabled && ~clearanceEnabled);
if ~heatStateEnabled
    % 已初始化的15/16/27/29状态拓扑可暂时冻结，供只启用惯量的对照。
    % 冻结热状态时不可让热/间隙反馈继续作用。
    switchesInvalid = switchesInvalid || heatFeedbackEnabled || ...
        clearanceEnabled || clearanceFeedbackEnabled || ~ismember(componentMask,[0,15]);
elseif heatFeedbackEnabled && clearanceFeedbackEnabled
    % P6 联合配置必须使用完整掩码。单一 componentMask 同时控制热状态、
    % 热反馈和间隙部件选择，因此不能用单部件掩码冒充 15 维联合验证。
    switchesInvalid = switchesInvalid || componentMask ~= 15;
elseif ~clearanceEnabled && ~heatFeedbackEnabled
    switchesInvalid = switchesInvalid || componentMask ~= 15;
elseif clearanceEnabled && ~clearanceFeedbackEnabled && ~heatFeedbackEnabled
    switchesInvalid = switchesInvalid || componentMask ~= 13;
elseif clearanceFeedbackEnabled
    switchesInvalid = switchesInvalid || ~ismember(componentMask, [1, 4, 8]);
end
if switchesInvalid
    error('sht:config:transientStepInSwitches', ...
        ['Transient template requires transientEffectsEnable=1, ' ...
         'thermalModelMode=1 (Kurzke) or 3 (Visser), and ' ...
         'heatStateEnable=0 requires disabled heat/clearance feedback. P5 diagnostic mask is 13; feedback only accepts ' ...
         'single-component masks 1/4/8; P6 joint feedback requires mask 15.']);
end

if clearanceEnabled
    if ~isfield(effects, 'clearanceReferenceTable') || ...
            ~isstruct(effects.clearanceReferenceTable) || ...
            ~isfield(effects.clearanceReferenceTable, 'generated') || ...
            ~effects.clearanceReferenceTable.generated
        error('sht:config:missingClearanceReferenceTable', ...
            'P5 requires a generated epsilon_ss reference table.');
    end
    referenceTable = effects.clearanceReferenceTable;
    commonSchemaInvalid = ~isfield(referenceTable, 'standardTemperature_K') || ...
            ~isscalar(referenceTable.standardTemperature_K) || ...
            ~isfinite(referenceTable.standardTemperature_K) || ...
            referenceTable.standardTemperature_K <= 0 || ...
            ~isfield(referenceTable, 'defaultInletTotalTemperature_K') || ...
            ~isscalar(referenceTable.defaultInletTotalTemperature_K) || ...
            ~isfinite(referenceTable.defaultInletTotalTemperature_K) || ...
            referenceTable.defaultInletTotalTemperature_K <= 0;
    if engine.modelMode == 1
        componentNames = {'AC','CC','GT1','GT2','PT1','PT2'};
        componentSchemaInvalid = false;
        for componentIndex = 1:numel(componentNames)
            name = componentNames{componentIndex};
            componentSchemaInvalid = componentSchemaInvalid || ...
                ~isfield(referenceTable, name) || ...
                ~isfield(referenceTable.(name), 'correctedSpeed_rpm');
            if componentIndex >= 5
                componentSchemaInvalid = componentSchemaInvalid || ...
                    ~isfield(referenceTable.(name), 'loadPower_W');
            end
        end
        epsilonIndex = 488:493;
    else
        componentSchemaInvalid = ~isfield(referenceTable, 'HPC') || ...
            ~isfield(referenceTable.HPC, 'correctedSpeed_rpm') || ...
            ~isfield(referenceTable, 'GT') || ...
            ~isfield(referenceTable.GT, 'correctedSpeed_rpm') || ...
            ~isfield(referenceTable, 'PT') || ...
            ~isfield(referenceTable.PT, 'correctedSpeed_rpm') || ...
            ~isfield(referenceTable.PT, 'loadPower_W');
        epsilonIndex = 431:433;
    end
    if commonSchemaInvalid || componentSchemaInvalid
        error('sht:config:legacyClearanceReferenceTable', ...
            ['P5/P6 requires the inlet-corrected-speed epsilon_ss table. ' ...
             'Run Start_TransientEffects_01_ParameterInitialization first.']);
    end
    if any(~isfinite(effects.stepInTemplate(epsilonIndex))) || ...
            any(effects.stepInTemplate(epsilonIndex) <= 0)
        error('sht:config:invalidClearanceReference', ...
            'P5 template epsilon_ss values must be finite and positive.');
    end
end

effects.temperatureStateStartIndex = 301;
if engine.modelMode == 1
    effects.metalNodeCount = 19;
    effects.diskNodeCount = 6;
    effects.guideVaneNodeCount = 0;
    effects.heatComponentCount = 7;
    effects.clearanceComponentCount = 6;
    if thermalModelMode == 3
        effects.guideVaneNodeCount = 2;
        effects.derivativeOutputCount = 29;
        effects.validOutputIndex = 30;
    else
        effects.derivativeOutputCount = 27;
        effects.validOutputIndex = 28;
    end
else
    effects.metalNodeCount = 10;
    effects.diskNodeCount = 3;
    effects.guideVaneNodeCount = 0;
    effects.heatComponentCount = 4;
    effects.clearanceComponentCount = 3;
    effects.derivativeOutputCount = 15;
    effects.validOutputIndex = 16;
    if thermalModelMode == 3
        effects.guideVaneNodeCount = 1;
        effects.derivativeOutputCount = 16;
        effects.validOutputIndex = 17;
    end
end
effects.parameterLayoutVersion = parameterLayoutVersion;
effects.thermalModelMode = thermalModelMode;
effects.inertiaEnabled = logical(round(switchValue(3)));
effects.heatFeedbackEnabled = heatFeedbackEnabled;
effects.clearanceEnabled = clearanceEnabled;
effects.clearanceFeedbackEnabled = clearanceFeedbackEnabled;
effects.componentMask = componentMask;
end

function local_validate_cooling_split_configuration(effects)
% Visser使用独立初始化接口提交19条内部换热支路比例。这里先在MATLAB
% 配置边界完成与C端相同的版本、长度、范围和逐公开流路守恒检查。
if ~isfield(effects, 'coolingSplitConfiguration') || ...
        ~isstruct(effects.coolingSplitConfiguration) || ...
        ~all(isfield(effects.coolingSplitConfiguration, ...
        {'configVersion','parameterCount','ratio'}))
    error('sht:config:missingCoolingSplitConfiguration', ...
        'Visser热模型必须提供19维coolingSplitConfiguration。');
end
configuration = effects.coolingSplitConfiguration;
ratio = configuration.ratio(:);
if configuration.configVersion ~= 250304 || ...
        configuration.parameterCount ~= 19 || numel(ratio) ~= 19 || ...
        any(~isfinite(ratio)) || any(ratio < 0 | ratio > 1)
    error('sht:config:coolingSplitConfiguration', ...
        '冷却分流配置必须使用version=250304和19个[0,1]有限比例。');
end
routeStart = [1,4,6,10,12,14,15,17,18,19];
routeCount = [3,2,4,2,2,1,2,1,1,1];
for routeIndex = 1:numel(routeStart)
    index = routeStart(routeIndex) + (0:routeCount(routeIndex)-1);
    if abs(sum(ratio(index)) - 1) > 1e-9
        error('sht:config:coolingSplitRouteSum', ...
            '第%d条公开冷却流的内部分流比例和必须为1。', routeIndex);
    end
end
end

function cfg = local_validate_reference(cfg)
% 参考指令默认围绕发动机初始点构造。
if ~isfield(cfg, 'reference') || isempty(cfg.reference) || ~isstruct(cfg.reference)
    cfg.reference = struct();
end
ref = cfg.reference;
init = cfg.engine.initial;
ref.baseNp = local_get_field(ref, 'baseNp', init.Np0);
ref.baseNg = local_get_field(ref, 'baseNg', init.Ng0);
ref.npPulseAmplitude = local_get_field(ref, 'npPulseAmplitude', -2000);
ref.npPulsePeriod = local_get_field(ref, 'npPulsePeriod', 100);
ref.npPulseWidthFraction = local_get_field(ref, 'npPulseWidthFraction', 0.05);
ref.npPulsePhaseDelay = local_get_field(ref, 'npPulsePhaseDelay', 1);
ref.npFilterOmega = local_get_field(ref, 'npFilterOmega', 10);
ref.enablePowerPulse = local_get_field(ref, 'enablePowerPulse', false);
ref.powerBase = local_get_field(ref, 'powerBase', init.power0);
ref.powerPulseAmplitude = local_get_field(ref, 'powerPulseAmplitude', -2e5);
ref.powerPulsePeriod = local_get_field(ref, 'powerPulsePeriod', 10);
ref.powerPulseWidthFraction = local_get_field(ref, 'powerPulseWidthFraction', 0.40);
ref.powerPulsePhaseDelay = local_get_field(ref, 'powerPulsePhaseDelay', 2);
ref.powerFilterOmega = local_get_field(ref, 'powerFilterOmega', 10);
ref.powerCommandMode = local_get_field(ref, 'powerCommandMode', 'pulse');
ref.powerRampDuration = local_get_field(ref, 'powerRampDuration', 2);
ref.powerRampTimeFraction = local_get_field(ref, 'powerRampTimeFraction', [0 1]);
ref.powerRampValueFraction = local_get_field(ref, 'powerRampValueFraction', [0 1]);
% commandMode='schedule' 用于 2.6 过渡态台架替代数据的显式分段指令。
% 默认仍是 legacy，因此没有配置新模式的既有入口保持原行为。
ref.commandMode = local_get_field(ref, 'commandMode', 'legacy');
if strcmpi(ref.commandMode, 'schedule')
    ref = local_validate_reference_schedule(ref, cfg.stopTime);
elseif strcmpi(ref.commandMode, 'legacy')
    ref = local_validate_power_ramp_profile(ref);
else
    error('sht:config:badReferenceCommandMode', ...
        'cfg.reference.commandMode 只允许为 legacy 或 schedule。');
end
cfg.reference = ref;
end

function ref = local_validate_reference_schedule(ref, stopTime)
% 显式分段指令采用共同时间断点和右连续零阶保持。共同断点可确保 Np
% 与负载功率在同一积分端点切换，不会因两套时间轴不同步产生歧义。
requiredFields = {'scheduleTime_s', 'scheduleNp_rpm', 'schedulePower_W'};
for i = 1:numel(requiredFields)
    if ~isfield(ref, requiredFields{i}) || isempty(ref.(requiredFields{i}))
        error('sht:config:missingReferenceSchedule', ...
            'schedule 模式缺少 cfg.reference.%s。', requiredFields{i});
    end
end

time = ref.scheduleTime_s(:);
np = ref.scheduleNp_rpm(:);
power = ref.schedulePower_W(:);
if numel(time) < 2 || numel(np) ~= numel(time) || numel(power) ~= numel(time)
    error('sht:config:badReferenceScheduleSize', ...
        'scheduleTime_s、scheduleNp_rpm 和 schedulePower_W 必须等长，且至少包含两个断点。');
end
if any(~isfinite(time)) || any(~isfinite(np)) || any(~isfinite(power))
    error('sht:config:badReferenceScheduleValue', ...
        '分段参考指令的时间、转速和功率必须全部为有限数值。');
end
if abs(time(1)) > 1e-12 || any(diff(time) <= 0)
    error('sht:config:badReferenceScheduleTime', ...
        'scheduleTime_s 必须从 0 s 开始并严格递增。');
end
if time(end) < stopTime - 1e-12
    error('sht:config:shortReferenceSchedule', ...
        '分段指令只覆盖到 %.9g s，小于仿真终止时间 %.9g s。', time(end), stopTime);
end
if any(np <= 0) || any(power < 0)
    error('sht:config:badReferenceScheduleTarget', ...
        '分段指令中的 Np 必须大于 0 rpm，负载功率必须不小于 0 W。');
end

% 统一整理成行向量，便于配置显示和结果记录；计算函数内部仍会转列向量。
ref.scheduleTime_s = time.';
ref.scheduleNp_rpm = np.';
ref.schedulePower_W = power.';
end

function ref = local_validate_power_ramp_profile(ref)
timeFraction = ref.powerRampTimeFraction(:);
valueFraction = ref.powerRampValueFraction(:);
if numel(timeFraction) ~= numel(valueFraction) || numel(timeFraction) < 2
    error('sht:config:badPowerRampProfile', ...
        'powerRampTimeFraction and powerRampValueFraction must have the same length and at least two points.');
end
if any(~isfinite(timeFraction)) || any(~isfinite(valueFraction))
    error('sht:config:badPowerRampProfile', ...
        'powerRampTimeFraction and powerRampValueFraction must be finite.');
end
if abs(timeFraction(1)) > 1e-12 || abs(timeFraction(end) - 1) > 1e-12
    error('sht:config:badPowerRampProfile', ...
        'powerRampTimeFraction must start at 0 and end at 1.');
end
if abs(valueFraction(1)) > 1e-12 || abs(valueFraction(end) - 1) > 1e-12
    error('sht:config:badPowerRampProfile', ...
        'powerRampValueFraction must start at 0 and end at 1.');
end
if any(diff(timeFraction) <= 0)
    error('sht:config:badPowerRampProfile', ...
        'powerRampTimeFraction must be strictly increasing.');
end
if any(diff(valueFraction) < 0)
    error('sht:config:badPowerRampProfile', ...
        'powerRampValueFraction must be nondecreasing.');
end
if any(timeFraction < 0 | timeFraction > 1) || any(valueFraction < 0 | valueFraction > 1)
    error('sht:config:badPowerRampProfile', ...
        'power ramp profile fractions must stay in [0, 1].');
end
ref.powerRampTimeFraction = timeFraction.';
ref.powerRampValueFraction = valueFraction.';
end

function cfg = local_validate_sensor(cfg)
% 传感器默认直连，可在 cfg.sensor 中扩展一阶动态、偏置和噪声。
if ~isfield(cfg, 'sensor') || isempty(cfg.sensor) || ~isstruct(cfg.sensor)
    cfg.sensor = struct();
end
sensor = cfg.sensor;
defaultChannels = {'Np', 'Ng', 'T45', 'Mkp', 'Ngc', 'Theta', 'Deta', ...
    'Pt2', 'Tt1', 'Pt3', 'Tt3', 'Pt45', 'Tt45', 'Pt5', 'Tt5', ...
    'HpcStallMargin', 'FAR', 'T4', 'Mkg', 'Pamb', 'Tamb', ...
    'Altitude', 'Mach'};
sensor.mode = local_get_field(sensor, 'mode', 'identity');
sensor.timeConstant = local_get_field(sensor, 'timeConstant', 0);
sensor.channels = local_get_field(sensor, 'channels', defaultChannels);
n = numel(sensor.channels);
sensor.bias = local_column(local_get_field(sensor, 'bias', zeros(n, 1)), n);
sensor.noiseStd = local_column(local_get_field(sensor, 'noiseStd', zeros(n, 1)), n);
sensor.randomSeed = local_get_field(sensor, 'randomSeed', 1);
sensor.biasModel = local_get_field(sensor, 'biasModel', struct('enabled', false));
if ~isstruct(sensor.biasModel) || ~isscalar(sensor.biasModel)
    error('sht:config:badSensorBiasModel', ...
        'sensor.biasModel 必须是标量结构体。');
end
sensor.biasModel.enabled = local_get_field(sensor.biasModel, 'enabled', false);
if ~(islogical(sensor.biasModel.enabled) || isnumeric(sensor.biasModel.enabled)) || ...
        ~isscalar(sensor.biasModel.enabled) || ...
        ~isfinite(double(sensor.biasModel.enabled)) || ...
        ~ismember(double(sensor.biasModel.enabled), [0, 1])
    error('sht:config:badSensorBiasModelSwitch', ...
        'sensor.biasModel.enabled 必须是逻辑量或0/1。');
end
sensor.biasModel.enabled = logical(sensor.biasModel.enabled);
cfg.sensor = sensor;
end

function cfg = local_validate_actuator(cfg)
% 燃油执行机构初值来自发动机输入初值 Wf0。
% 这里不把 actuator.initialWf 作为独立权威源，避免执行器初值与发动机/控制器燃油初值不一致。
if ~isfield(cfg, 'actuator') || isempty(cfg.actuator) || ~isstruct(cfg.actuator)
    cfg.actuator = struct();
end
act = cfg.actuator;
wf0 = cfg.engine.initial.Wf0;
act.modelType = local_get_field(act, 'modelType', 'firstOrderRateLimitedFuelMetering');
act.gain = local_get_field(act, 'gain', 25);
% cfg.engine.initial.Wf0 是 t=0 燃油物理初值；执行器积分初值必须与其同步。
act.initialWf = wf0;
act.wfMin = local_get_field(act, 'wfMin', wf0 * 0.01);
act.wfMax = local_get_field(act, 'wfMax', wf0 * 2);
act.wfRateLimit = local_get_field(act, 'wfRateLimit', 1.5);
if act.wfMin >= act.wfMax
    error('sht:config:fuelBounds', 'cfg.actuator.wfMin must be smaller than wfMax.');
end
cfg.actuator = act;
end

function cfg = local_validate_controller(cfg)
% 控制器参数只保留运行时直接使用的量：DPpara、initial、linearModel、采样/滤波、保护限值和执行机构已知约束。
% 其中 controller.initial 由 engine.initial 同步生成，不再作为独立的 0 时刻物理初值来源。
if ~isfield(cfg, 'controller') || isempty(cfg.controller) || ~isstruct(cfg.controller)
    cfg.controller = struct();
end
ctrl = cfg.controller;
init = cfg.engine.initial;

ctrl.sampleTime = cfg.Tctrl;
ctrl.commandDelay = local_get_field(ctrl, 'commandDelay', 'oneSample');
if strcmpi(ctrl.commandDelay, 'oneSample')
    ctrl.commandDelay = 'oneSample';
elseif strcmpi(ctrl.commandDelay, 'zeroDelay')
    ctrl.commandDelay = 'zeroDelay';
else
    error('sht:config:commandDelay', ...
        'controller.commandDelay must be ''oneSample'' or ''zeroDelay''.');
end
ctrl.filterDiscretization = local_get_field(ctrl, 'filterDiscretization', 'euler2');
if strcmpi(ctrl.filterDiscretization, 'tustin')
    ctrl.filterDiscretization = 'tustin';
elseif strcmpi(ctrl.filterDiscretization, 'euler2')
    ctrl.filterDiscretization = 'euler2';
else
    error('sht:config:filterDiscretization', ...
        'controller.filterDiscretization must be ''tustin'' or ''euler2''.');
end
ctrl.filterOmega = local_get_field(ctrl, 'filterOmega', 10);
ctrl.npErrorGain = local_get_field(ctrl, 'npErrorGain', 8);
ctrl.npDeltaGain = local_get_field(ctrl, 'npDeltaGain', 4);
ctrl.ngCompGain = local_get_field(ctrl, 'ngCompGain', 2);
ctrl.wfFilterOmega = local_get_field(ctrl, 'wfFilterOmega', 20);

legacyTrim = struct();
if isfield(ctrl, 'trim') && isstruct(ctrl.trim)
    legacyTrim = ctrl.trim;
end

if ~isfield(ctrl, 'DPpara') || isempty(ctrl.DPpara) || ~isstruct(ctrl.DPpara)
    ctrl.DPpara = struct();
end
ctrl.DPpara.Np0 = local_get_field(ctrl.DPpara, 'Np0', local_get_field(legacyTrim, 'Np0', init.Np0));
ctrl.DPpara.Ng0 = local_get_field(ctrl.DPpara, 'Ng0', local_get_field(legacyTrim, 'Ng0', init.Ng0));
ctrl.DPpara.Wf0 = local_get_field(ctrl.DPpara, 'Wf0', local_get_field(legacyTrim, 'Wf0', init.Wf0));
ctrl.DPpara.T45 = local_get_field(ctrl.DPpara, 'T45', local_get_field(legacyTrim, 'T45', init.T45));
ctrl.DPpara.Mkp = local_get_field(ctrl.DPpara, 'Mkp', local_get_field(legacyTrim, 'Mkp', init.Mkp));

% 控制器初值是控制器离散记忆量的初始化基准，必须与发动机 t=0 物理初值一致。
% 因此这里总是从 cfg.engine.initial 同步，不保留用户单独写入的 controller.initial。
ctrl.initial = struct();
ctrl.initial.Np = init.Np0;
ctrl.initial.Ng = init.Ng0;
ctrl.initial.Wf = init.Wf0;
ctrl.initial.T45 = init.T45;
ctrl.initial.Mkp = init.Mkp;
if isfield(ctrl, 'trim')
    ctrl = rmfield(ctrl, 'trim');
end

if ~isfield(ctrl, 'linearModel') || isempty(ctrl.linearModel) || ~isstruct(ctrl.linearModel)
    error('sht:config:missingLinearCoefficients', ...
        'cfg.controller.linearModel.b11/b21/d31/d41 are required by the controller.');
end
names = {'b11', 'b21', 'd31', 'd41'};
for i = 1:numel(names)
    name = names{i};
    if ~isfield(ctrl.linearModel, name) || isempty(ctrl.linearModel.(name))
        error('sht:config:missingLinearCoefficient', 'cfg.controller.linearModel.%s is required.', name);
    end
end
ctrl.gainSchedule = local_validate_gain_schedule(ctrl);
ctrl.ndotSchedule = local_validate_ndot_schedule(ctrl);
ctrl.accelDecelLimit = local_validate_accel_decel_limit(ctrl);

if ~isfield(ctrl, 'fullControl') || isempty(ctrl.fullControl) || ~isstruct(ctrl.fullControl)
    ctrl.fullControl = struct();
end
ctrl.fullControl.enable = true;
ctrl.fullControl.mode = local_get_field(ctrl.fullControl, 'mode', 'stage4p5_incrementAuthority');

if ~isfield(ctrl, 'actuatorLimitsKnown') || isempty(ctrl.actuatorLimitsKnown) || ~isstruct(ctrl.actuatorLimitsKnown)
    ctrl.actuatorLimitsKnown = struct();
end
limits = ctrl.actuatorLimitsKnown;
limits.followPhysicalActuator = local_get_field(limits, 'followPhysicalActuator', true);
if limits.followPhysicalActuator
    limits.wfMin = cfg.actuator.wfMin;
    limits.wfMax = cfg.actuator.wfMax;
    limits.wfRateLimit = cfg.actuator.wfRateLimit;
else
    limits.wfMin = local_get_field(limits, 'wfMin', cfg.actuator.wfMin);
    limits.wfMax = local_get_field(limits, 'wfMax', cfg.actuator.wfMax);
    limits.wfRateLimit = local_get_field(limits, 'wfRateLimit', cfg.actuator.wfRateLimit);
end
ctrl.actuatorLimitsKnown = limits;
ctrl.wfMin = limits.wfMin;
ctrl.wfMax = limits.wfMax;
ctrl.wfRateLimit = limits.wfRateLimit;

ctrl.ngProtection = local_validate_ng_protection(ctrl);
ctrl.t45Protection = local_validate_t45_protection(ctrl);
ctrl.mkpProtection = local_validate_mkp_protection(ctrl);

cfg.controller = ctrl;
end

function gainSchedule = local_validate_gain_schedule(ctrl)
if ~isfield(ctrl, 'gainSchedule') || isempty(ctrl.gainSchedule) || ~isstruct(ctrl.gainSchedule)
    gainSchedule = struct();
else
    gainSchedule = ctrl.gainSchedule;
end
gainSchedule.enable = local_get_field(gainSchedule, 'enable', false);
gainSchedule.variableName = local_get_field(gainSchedule, 'variableName', 'gainSchedule');
gainSchedule.independentVariable = local_get_field(gainSchedule, 'independentVariable', 'Ngc');
gainSchedule.interpolationMethod = local_get_field(gainSchedule, 'interpolationMethod', 'linear');
gainSchedule.extrapolationMode = local_get_field(gainSchedule, 'extrapolationMode', 'clamp');
if ~isfield(gainSchedule, 'sourceFile')
    gainSchedule.sourceFile = '';
end

if gainSchedule.enable
    if isfield(gainSchedule, 'Ngc') && ~isempty(gainSchedule.Ngc)
        names = {'b11', 'b21', 'd31', 'd41'};
        n = numel(gainSchedule.Ngc);
        for i = 1:numel(names)
            name = names{i};
            if ~isfield(gainSchedule, name) || numel(gainSchedule.(name)) ~= n
                error('sht:config:badGainSchedule', ...
                    'cfg.controller.gainSchedule.%s must have the same length as Ngc.', name);
            end
        end
    elseif isempty(gainSchedule.sourceFile)
        error('sht:config:missingGainSchedule', ...
            'gainSchedule.enable is true, but neither table data nor sourceFile is configured.');
    end
end
end

function ndotSchedule = local_validate_ndot_schedule(ctrl)
if ~isfield(ctrl, 'ndotSchedule') || isempty(ctrl.ndotSchedule) || ~isstruct(ctrl.ndotSchedule)
    ndotSchedule = struct();
else
    ndotSchedule = ctrl.ndotSchedule;
end
ndotSchedule.enable = local_get_field(ndotSchedule, 'enable', false);
ndotSchedule.variableName = local_get_field(ndotSchedule, 'variableName', 'ndotSchedule');
ndotSchedule.independentVariable = local_get_field(ndotSchedule, 'independentVariable', 'Ngc');
ndotSchedule.interpolationMethod = local_get_field(ndotSchedule, 'interpolationMethod', 'linear');
ndotSchedule.extrapolationMode = local_get_field(ndotSchedule, 'extrapolationMode', 'clamp');
if ~isfield(ndotSchedule, 'sourceFile')
    ndotSchedule.sourceFile = '';
end

if ndotSchedule.enable
    if isfield(ndotSchedule, 'Ngc') && ~isempty(ndotSchedule.Ngc)
        names = {'NgdotMax', 'NgdotMin', 'AccelWfLimit', 'DecelWfLimit'};
        n = numel(ndotSchedule.Ngc);
        for i = 1:numel(names)
            name = names{i};
            if ~isfield(ndotSchedule, name) || numel(ndotSchedule.(name)) ~= n
                error('sht:config:badNdotSchedule', ...
                    'cfg.controller.ndotSchedule.%s must have the same length as Ngc.', name);
            end
        end
    elseif isempty(ndotSchedule.sourceFile)
        error('sht:config:missingNdotSchedule', ...
            'ndotSchedule.enable is true, but neither table data nor sourceFile is configured.');
    end
end
end

function accelDecelLimit = local_validate_accel_decel_limit(ctrl)
if ~isfield(ctrl, 'accelDecelLimit') || isempty(ctrl.accelDecelLimit) ...
        || ~isstruct(ctrl.accelDecelLimit)
    accelDecelLimit = struct();
else
    accelDecelLimit = ctrl.accelDecelLimit;
end
accelDecelLimit.enable = local_get_field(accelDecelLimit, 'enable', false);
end

function ng = local_validate_ng_protection(ctrl)
if ~isfield(ctrl, 'ngProtection') || isempty(ctrl.ngProtection) || ~isstruct(ctrl.ngProtection)
    ng = struct();
else
    ng = ctrl.ngProtection;
end
ng.enable = local_get_field(ng, 'enable', true);
ng.ngMax = local_get_field(ng, 'ngMax', 1.05 * ctrl.DPpara.Ng0);
ng.errorGain = local_get_field(ng, 'errorGain', 4);
ng.errorDeltaGain = local_get_field(ng, 'errorDeltaGain', 2);
end

function t45 = local_validate_t45_protection(ctrl)
if ~isfield(ctrl, 't45Protection') || isempty(ctrl.t45Protection) || ~isstruct(ctrl.t45Protection)
    t45 = struct();
else
    t45 = ctrl.t45Protection;
end
t45.enable = local_get_field(t45, 'enable', true);
t45.t45Max = local_get_field(t45, 't45Max', 1400);
t45.gainScheduleError = local_get_field(t45, 'gainScheduleError', [0 5 10 20 50 100 1000]);
t45.gainScheduleValue = local_get_field(t45, 'gainScheduleValue', [4 4 8 12 16 20 24]);
end

function mkp = local_validate_mkp_protection(ctrl)
if ~isfield(ctrl, 'mkpProtection') || isempty(ctrl.mkpProtection) || ~isstruct(ctrl.mkpProtection)
    mkp = struct();
else
    mkp = ctrl.mkpProtection;
end
mkp.enable = local_get_field(mkp, 'enable', true);
mkp.mkpMax = local_get_field(mkp, 'mkpMax', 1200);
mkp.gainScheduleError = local_get_field(mkp, 'gainScheduleError', [0 5 10 20 50 100 1000]);
mkp.gainScheduleValue = local_get_field(mkp, 'gainScheduleValue', [4 4 8 12 16 20 24]);
end

function cfg = local_validate_plot(cfg)
if ~isfield(cfg, 'plot') || isempty(cfg.plot) || ~isstruct(cfg.plot)
    cfg.plot = struct();
end
cfg.plot.enable = local_get_field(cfg.plot, 'enable', true);
cfg.plot.figureName = local_get_field(cfg.plot, 'figureName', 'SHT closed-loop response');
end


function value = local_get_field(s, name, defaultValue)
%LOCAL_GET_FIELD 读取结构体字段；空字段视为未配置。
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end

function x = local_column(x, n)
%LOCAL_COLUMN 将标量/向量整理成指定长度列向量。
if isempty(x)
    x = zeros(n, 1);
elseif isscalar(x)
    x = repmat(x, n, 1);
else
    x = x(:);
    if numel(x) < n
        x(end + 1:n, 1) = 0;
    elseif numel(x) > n
        x = x(1:n);
    end
end
end
