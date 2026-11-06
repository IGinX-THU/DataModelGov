function stepIn = sht_build_transient_step_in_template(parameterAsset, stageName, componentMask)
%SHT_BUILD_TRANSIENT_STEP_IN_TEMPLATE 构造 2.5 瞬态效应统一 stepIn 模板。
%
% 输入：
%   parameterAsset - Start_TransientEffects_01_ParameterInitialization 生成的资产。
%   stageName      - baseline、enhanced_ready、inertia、heat_state、
%                    heat_feedback、clearance_diagnostic、clearance_feedback
%                    或 joint_full。
%   componentMask  - 单部件阶段的位掩码，可选；HPC/Burner/GT/PT=1/2/4/8。
%
% 本函数只负责固定下标的唯一装配，不运行 DLL。每次发动机调用时，调用方
% 应复制返回模板，再覆盖当前气路输入、共同工作猜值、温度状态和 epsilonSS。

if nargin < 2 || isempty(stageName)
    stageName = 'enhanced_ready';
end
if nargin < 3
    componentMask = [];
end

local_validate_asset(parameterAsset);
stageName = lower(char(stageName));
stepIn = zeros(parameterAsset.interface.stepInLength, 1);

% 旧三部件瞬态资产只保存 hlthparas[0:99]；六部件接口已将健康参数区
% 扩展为 hlthparas[0:158]。这里同时接受 100 维历史资产和 159 维新资产：
% 历史资产只写入前 100 项，扩展区保持严格为零；新资产则完整写入。
% 这样既不会改变既有三部件瞬态结果，也不会截断后续六部件瞬态参数。
health = parameterAsset.nominalHealth(:);
stepIn(41:(40 + numel(health))) = health;

% baseline 必须保持 [300:511] 严格为零，其中 stepIn(341)=0 表示关闭
% 增强瞬态效应。发动机三/六部件拓扑由 DLL 初始化模式单独决定。
if strcmp(stageName, 'baseline')
    return;
end

% 参数资产中的 2502/2503 只描述静态参数排列：2503 使用六部件
% 27 状态布局，2502 使用三部件 15 状态布局，不作为运行时拓扑开关。
if parameterAsset.interface.interfaceVersion == 2503
    stepIn = local_build_split_2503(stepIn, parameterAsset, ...
        stageName, componentMask);
    return;
end
if isfield(parameterAsset.interface,'nominalThermalConfigVersion')
    mode=local_thermal_model_mode(parameterAsset);
    count=13+double(mode==3);
    local_require_vector(parameterAsset.nominal,'initialTemperatureState',count);
    stepIn(341)=1;
    % 总开关/惯量开关不改变已初始化的热状态拓扑。即使热演化未打开，
    % Visser也保留其独立导向器状态，不能在这里误切回15状态。
    stepIn(342)=mode;
    stepIn(301:300+count)=parameterAsset.nominal.initialTemperatureState(:);
    stepIn(431:433)=parameterAsset.nominal.epsilonSSCurrent(:);
    switch stageName
        case 'enhanced_ready'
            return;
        case 'inertia'
            stepIn(343)=1; return;
        case 'heat_state'
            stepIn(348)=15;
        case 'heat_feedback'
            stepIn(345)=1; stepIn(348)=local_validate_mask(componentMask,stageName);
        case 'clearance_diagnostic'
            stepIn(346)=1; stepIn(348)=13;
        case 'clearance_feedback'
            assert(ismember(componentMask,[1,4,8]),'间隙反馈须选择单个旋转部件。');
            stepIn(346:347)=1;stepIn(348)=componentMask;
        case 'joint_full'
            stepIn(343:347)=1;stepIn(348)=15;
        otherwise
            error('SHT:TransientTemplate:UnknownStage','未知阶段%s。',stageName);
    end
    if stepIn(346),local_require_epsilon_schedule(parameterAsset);end
    stepIn(342)=mode;stepIn(344)=1;
    stepIn(301:300+count)=parameterAsset.nominal.initialTemperatureState(:);
    return;
end

% 所有增强模板都使用同一份固定模型参数，禁止入口脚本自行重复下标映射。
stepIn(351:360) = parameterAsset.nominal.tau0(:);
stepIn(361:370) = parameterAsset.nominal.heatCapacity0(:);
stepIn(371:380) = parameterAsset.nominal.beta(:);
stepIn(381:383) = parameterAsset.nominal.diskTau0(:);
stepIn(384:387) = parameterAsset.nominal.referenceFlow(:);
stepIn(388:391) = parameterAsset.nominal.referenceGasTemperature(:);
stepIn(401:410) = parameterAsset.nominal.clearanceParameter(1, :).';
stepIn(411:420) = parameterAsset.nominal.clearanceParameter(2, :).';
stepIn(421:430) = parameterAsset.nominal.clearanceParameter(3, :).';
stepIn(431:433) = parameterAsset.nominal.epsilonSSCurrent(:);
stepIn(434) = parameterAsset.nominal.kSMHPC;
% C下标434:437保存固定标称间隙-性能灵敏度；health(65:68)只保存
% 围绕这些标称值的无量纲相对修正系数。
stepIn(435:438) = parameterAsset.nominal.clearanceExchangeRate(:);

% C 下标 340:347 对应 MATLAB 下标 341:348。第一个量仅为增强瞬态
% 效应总开关；所有非 baseline 模板统一置 1。
stepIn(341) = 1;
switch stageName
    case 'enhanced_ready'
        % 只验证增强接口及参数装配，不开启任何尚未实现的物理效应。
        stepIn(342:348) = 0;

    case 'inertia'
        stepIn(342) = 0;  % thermalModelMode
        stepIn(343) = 1;  % inertiaEnable

    case 'heat_state'
        stepIn(342) = 1;
        stepIn(344) = 1;
        stepIn(348) = 15;
        stepIn(301:313) = parameterAsset.nominal.initialTemperatureState(:);

    case 'heat_feedback'
        componentMask = local_validate_mask(componentMask, 'heat_feedback');
        stepIn(342) = 1;
        stepIn(344) = 1;
        stepIn(345) = 1;
        stepIn(348) = componentMask;
        stepIn(301:313) = parameterAsset.nominal.initialTemperatureState(:);

    case 'clearance_diagnostic'
        local_require_epsilon_schedule(parameterAsset);
        stepIn(342) = 1;
        stepIn(344) = 1;
        stepIn(346) = 1;
        stepIn(348) = 13;
        stepIn(301:313) = parameterAsset.nominal.initialTemperatureState(:);

    case 'clearance_feedback'
        local_require_epsilon_schedule(parameterAsset);
        componentMask = local_validate_mask(componentMask, 'clearance_feedback');
        if ~ismember(componentMask, [1, 4, 8])
            error('SHT:TransientTemplate:ClearanceMask', ...
                'clearance_feedback 只允许 HPC/GT/PT 掩码 1、4 或 8。');
        end
        stepIn(342) = 1;
        stepIn(344) = 1;
        stepIn(346) = 1;
        stepIn(347) = 1;
        stepIn(348) = componentMask;
        stepIn(301:313) = parameterAsset.nominal.initialTemperatureState(:);

    case 'joint_full'
        % P6 联合阶段统一开启惯量、15 维热状态、四部件热反馈以及
        % HPC/GT/PT 间隙计算与反馈。固定参数区提供四个标称交换率，
        % health(65:68)=0 时仍保留完整的标称间隙物理效应。
        local_require_epsilon_schedule(parameterAsset);
        stepIn(342) = 1;   % thermalModelMode = Kurzke 扩展
        stepIn(343) = 1;   % inertiaEnable
        stepIn(344) = 1;   % heatStateEnable
        stepIn(345) = 1;   % heatFeedbackEnable
        stepIn(346) = 1;   % clearanceEnable
        stepIn(347) = 1;   % clearanceFeedbackEnable
        stepIn(348) = 15;  % HPC/Burner/GT/PT 热状态联合计算
        stepIn(301:313) = parameterAsset.nominal.initialTemperatureState(:);

    otherwise
        error('SHT:TransientTemplate:UnknownStage', ...
            '未知阶段模板：%s。', stageName);
end

% 保留区是接口契约的一部分。这里再次检查，防止资产字段越界写入。
reserved = [349:350, 392:400, 439:512];
if any(stepIn(reserved) ~= 0)
    error('SHT:TransientTemplate:ReservedNonzero', ...
        '统一模板的保留字段必须严格为零。');
end
end

function local_validate_asset(asset)
requiredFields = {'interface', 'nominalHealth', 'nominal', 'referenceTable'};
for i = 1:numel(requiredFields)
    if ~isfield(asset, requiredFields{i})
        error('SHT:TransientTemplate:MissingAssetField', ...
            '参数资产缺少字段 %s。', requiredFields{i});
    end
end
if ~ismember(asset.interface.interfaceVersion, [2502, 2503]) || ...
        asset.interface.stepInLength ~= 512 || asset.interface.stepOutLength ~= 128
    error('SHT:TransientTemplate:InterfaceMismatch', ...
        '参数资产接口必须为 version=2502/2503、stepIn=512、stepOut=128。');
end
healthLength = numel(asset.nominalHealth);
if ~ismember(healthLength, [100, 159])
    error('SHT:TransientTemplate:HealthLength', ...
        'nominalHealth 必须包含 100 个历史参数或 159 个扩展参数，当前为 %d。', ...
        healthLength);
end
if asset.interface.interfaceVersion == 2503 && healthLength ~= 159
    error('SHT:TransientTemplate:SplitHealthLength', ...
        '2503 六部件资产必须包含 h0:h158 共 159 个健康参数。');
end
expectedRateCount = 4;
if asset.interface.interfaceVersion == 2503
    expectedRateCount = 8;
end
if ~isfield(asset.nominal, 'clearanceExchangeRate') || ...
        numel(asset.nominal.clearanceExchangeRate) ~= expectedRateCount || ...
        any(~isfinite(asset.nominal.clearanceExchangeRate(:))) || ...
        any(asset.nominal.clearanceExchangeRate(:) > 0)
    error('SHT:TransientTemplate:NominalClearanceRate', ...
        '%d 个标称间隙交换率必须是有限的非正数。', expectedRateCount);
end
end

function stepIn = local_build_split_2503(stepIn, asset, stageName, componentMask)
% 2503六部件路径的标称热/间隙参数通过独立初始化接口一次写入
% DLL。stepIn只保留动态状态、当前工况epsilon_ss、开关及个体修正量。
% 这里仍校验标称字段，因为同一份asset将交给配置向量组装函数。
thermalModelMode = local_thermal_model_mode(asset);
if thermalModelMode == 1
    local_require_vector(asset.nominal, 'tau0', 19);
    local_require_vector(asset.nominal, 'heatCapacity0', 19);
    local_require_vector(asset.nominal, 'beta', 19);
    local_require_vector(asset.nominal, 'diskTau0', 6);
    temperatureStateCount = 25;
else
    local_require_vector(asset.nominal, 'visserMetalHeatCapacity', 21);
    local_require_vector(asset.nominal, 'visserHotGasConductance0', 21);
    local_require_vector(asset.nominal, 'visserHotGasBeta', 21);
    local_require_vector(asset.nominal, 'visserDiskHeatCapacity', 6);
    local_require_vector(asset.nominal, 'visserRootDiskConductance0', 6);
    local_require_vector(asset.nominal, 'visserCoolingConductance0', 19);
    temperatureStateCount = 27;
end
local_require_vector(asset.nominal, 'referenceFlow', 7);
local_require_vector(asset.nominal, 'referenceGasTemperature', 7);
local_require_vector(asset.nominal, 'epsilonSSCurrent', 6);
local_require_vector(asset.nominal, 'clearanceExchangeRate', 8);
local_require_vector(asset.nominal, 'initialTemperatureState', ...
    temperatureStateCount);
if ~isfield(asset.nominal, 'clearanceParameter') || ...
        ~isequal(size(asset.nominal.clearanceParameter), [6, 10])
    error('SHT:TransientTemplate:SplitClearanceParameter', ...
        '2503 clearanceParameter 必须为 6x10。');
end
if ~isfield(asset.nominal, 'kSM') || numel(asset.nominal.kSM) ~= 2
    error('SHT:TransientTemplate:SplitSurgeMargin', ...
        '2503 kSM 必须包含 AC、CC 两项。');
end

% epsilon_ss是本工况的查表结果，不属于标称配置。仿真过程中
% sht_engine_derivative会在每个已接受积分步开始时覆盖这六个数值。
stepIn(488:493) = asset.nominal.epsilonSSCurrent(:);
stepIn(341) = 1;

switch stageName
    case 'enhanced_ready'
        stepIn(342:348) = 0;
    case 'inertia'
        stepIn(342) = 0;
        stepIn(343) = 1;
    case 'heat_state'
        stepIn(342) = thermalModelMode;
        stepIn(344) = 1;
        stepIn(348) = 15;
        stepIn(301:(300+temperatureStateCount)) = ...
            asset.nominal.initialTemperatureState(:);
    case 'heat_feedback'
        componentMask = local_validate_mask(componentMask, stageName);
        stepIn(342) = thermalModelMode;
        stepIn(344) = 1;
        stepIn(345) = 1;
        stepIn(348) = componentMask;
        stepIn(301:(300+temperatureStateCount)) = ...
            asset.nominal.initialTemperatureState(:);
    case 'clearance_diagnostic'
        local_require_epsilon_schedule(asset);
        stepIn(342) = thermalModelMode;
        stepIn(344) = 1;
        stepIn(346) = 1;
        stepIn(348) = 13;
        stepIn(301:(300+temperatureStateCount)) = ...
            asset.nominal.initialTemperatureState(:);
    case 'clearance_feedback'
        local_require_epsilon_schedule(asset);
        componentMask = local_validate_mask(componentMask, stageName);
        if ~ismember(componentMask, [1, 4, 8])
            error('SHT:TransientTemplate:ClearanceMask', ...
                'clearance_feedback 只允许 HPC/GT/PT 掩码 1、4 或 8。');
        end
        stepIn(342) = thermalModelMode;
        stepIn(344) = 1;
        stepIn(346) = 1;
        stepIn(347) = 1;
        stepIn(348) = componentMask;
        stepIn(301:(300+temperatureStateCount)) = ...
            asset.nominal.initialTemperatureState(:);
    case 'joint_full'
        local_require_epsilon_schedule(asset);
        stepIn(342) = thermalModelMode;
        stepIn(343:347) = 1;
        stepIn(348) = 15;
        stepIn(301:(300+temperatureStateCount)) = ...
            asset.nominal.initialTemperatureState(:);
    otherwise
        error('SHT:TransientTemplate:UnknownStage', ...
            '未知阶段模板：%s。', stageName);
end

% 原固定参数区作为新路径的保留区必须严格为零，防止形成
% “初始化配置+stepIn参数”两个相互矛盾的权威来源。
if thermalModelMode == 3
    reserved = [328:340, 349:487, 494:512];
else
    reserved = [326:340, 349:487, 494:512];
end
if any(stepIn(reserved) ~= 0)
    error('SHT:TransientTemplate:ReservedNonzero', ...
        '2503 模板的保留字段必须严格为零。');
end
end

function mode = local_thermal_model_mode(asset)
mode = 1;
if isfield(asset.interface,'thermalModelMode') && ...
        ~isempty(asset.interface.thermalModelMode)
    mode = asset.interface.thermalModelMode;
elseif isfield(asset,'thermalModelMode') && ~isempty(asset.thermalModelMode)
    mode = asset.thermalModelMode;
elseif isfield(asset.nominal,'thermalModelMode') && ...
        ~isempty(asset.nominal.thermalModelMode)
    mode = asset.nominal.thermalModelMode;
end
if ~isscalar(mode) || ~isfinite(mode) || ~ismember(mode,[1,3])
    error('SHT:TransientTemplate:ThermalModelMode', ...
        '六部件热模型模式必须为1或3。');
end
end

function local_require_vector(valueStruct, fieldName, expectedCount)
if ~isfield(valueStruct, fieldName)
    error('SHT:TransientTemplate:SplitField', ...
        '2503 缺少字段 %s。', fieldName);
end
value = valueStruct.(fieldName);
if numel(value) ~= expectedCount || any(~isfinite(value(:)))
    error('SHT:TransientTemplate:SplitField', ...
        '2503 字段 %s 必须包含 %d 个有限值。', fieldName, expectedCount);
end
end

function mask = local_validate_mask(mask, stageName)
if isempty(mask) || ~isscalar(mask) || ~isfinite(mask) || ...
        abs(mask - round(mask)) > 1e-6 || mask < 1 - 1e-6 || mask > 15 + 1e-6
    error('SHT:TransientTemplate:InvalidMask', ...
        '%s 需要与 1~15 某个目标掩码相差不超过 1e-6。', stageName);
end
mask = round(mask);
end

function local_require_epsilon_schedule(asset)
if ~isfield(asset.referenceTable, 'generated') || ~asset.referenceTable.generated
    error('SHT:TransientTemplate:EpsilonScheduleUnavailable', ...
        ['epsilon_ss 调度表按实施主清单在步骤 7 生成；当前资产只冻结了' ...
         '接口字段，不能提前构造间隙阶段模板。']);
end
end
