function [sample, state] = sht_sensor_step(state, plantOutput, cfg, dt, ~, plantOutputNext)
%SHT_SENSOR_STEP 传感器模型步进。
% identity 模式直接输出当前信号；firstOrder 模式采用一阶保持器（FOH）
% 对连续一阶传感器方程作解析离散，再在动态输出端叠加偏置和白噪声。
% FOH 同时使用仿真步起点和终点的发动机真值，避免旧实现把终点值视为
% 整个区间恒定输入而使快速过渡响应偏快。
% 当 cfg.biasModel.enabled=true 时，偏置由统一生成器按无误差入口流量
% WIn 逐点计算；未纳入统一规格的内部诊断通道仍使用 cfg.bias。

if nargin < 6 || isempty(plantOutputNext)
    plantOutputNext = plantOutput;
end
if nargin < 4 || isempty(dt)
    dt = 0;
end
if nargin < 3 || isempty(cfg) || ~isstruct(cfg)
    cfg = struct();
end
cfg = local_sensor_cfg_defaults(cfg);

if ~isfield(cfg,'pressureChannel'), cfg.pressureChannel = 'Pt2'; end
plantSample = sht_sensor_pack(plantOutput,cfg.pressureChannel);
plantVector = plantSample.vector;
plantNextSample = sht_sensor_pack(plantOutputNext,cfg.pressureChannel);
plantNextVector = plantNextSample.vector;
n = numel(plantVector);

bias = local_expand_vector(cfg.bias, n, 0);
noiseStd = local_expand_vector(cfg.noiseStd, n, 0);
timeConstant = local_expand_vector(cfg.timeConstant, n, 0);
[bias, biasModelDetail] = local_apply_bias_model( ...
    bias, plantNextSample.vectorNames, plantOutputNext, cfg.biasModel);
[bias, noiseStd, timeConstant] = local_apply_channel_contract( ...
    bias, noiseStd, timeConstant, plantNextSample.vectorNames);

if ~isfield(state, 'rngState')
    rng(cfg.randomSeed);
    state.rngState = rng;
end

needInit = ~isfield(state, 'dynamicVector') || isempty(state.dynamicVector) || ...
    numel(state.dynamicVector) ~= n || ~isfield(state, 'vector') || ...
    isempty(state.vector) || numel(state.vector) ~= n;

if needInit
    state.dynamicVector = plantVector;
end

if strcmpi(cfg.mode, 'firstOrder') && dt > 0
    dynamicVector = local_first_order_sensor_step( ...
        state.dynamicVector, plantVector, plantNextVector, timeConstant, dt);
elseif dt > 0
    dynamicVector = plantNextVector;
else
    dynamicVector = state.dynamicVector;
end

% Theta、Deta 和 Ngc 不是三只独立传感器，而是由入口温压和高压轴
% 转速测量值在线计算的派生反馈量。必须先完成基础通道的传感器动态，
% 再重算派生量，避免控制器增益/加减速调度绕过 Tt1、Pt2 和 Ng 的动态。
dynamicVector = local_rebuild_derived_feedback( ...
    dynamicVector, plantSample.vectorNames);

if needInit || dt > 0
    rng(state.rngState);
    noise = noiseStd .* randn(n, 1);
    noise = local_sync_t45_alias(noise, plantSample.vectorNames);
    state.rngState = rng;
    state.dynamicVector = dynamicVector;
    measuredVector = dynamicVector + bias + noise;
    % 偏置和白噪声施加在基础传感器输出端。随后由这些实际测量值重算
    % 派生反馈量，使 Ngc 调度与闭环真正看到的 Ng/Tt1 保持一致。
    state.vector = local_rebuild_derived_feedback( ...
        measuredVector, plantSample.vectorNames);
    state.lastNoise = noise;
end

sample = local_vector_to_sample(state.vector);
if strcmp(cfg.pressureChannel,'Pt1')
    sample.Pt1 = state.vector(8);
    sample.Pt2 = NaN;
end
sample.vectorNames = plantSample.vectorNames;
state.lastBias = bias;
state.lastBiasModelDetail = biasModelDetail;
state.lastNoiseStd = noiseStd;
state.lastTimeConstant = timeConstant;
state.lastDynamicVector = state.dynamicVector;
state.lastMeasuredVector = state.vector;
end

function [bias, noiseStd, timeConstant] = local_apply_channel_contract( ...
        bias, noiseStd, timeConstant, channelNames)
%LOCAL_APPLY_CHANNEL_CONTRACT 约束物理测点和派生量的误差施加位置。
% 向量中的 T45 是控制器兼容槽位，Tt45 是对外规范槽位；二者表示同一只
% 站位 4.5 总温传感器，必须共享动态、偏置和噪声。Ngc、Theta、Deta
% 则由基础测量量计算，禁止再叠加一套独立传感器误差。
primaryIndex = local_channel_index(channelNames, 'T45');
aliasIndex = local_channel_index(channelNames, 'Tt45');
bias(aliasIndex) = bias(primaryIndex);
noiseStd(aliasIndex) = noiseStd(primaryIndex);
timeConstant(aliasIndex) = timeConstant(primaryIndex);

derivedNames = {'Ngc', 'Theta', 'Deta'};
for i = 1:numel(derivedNames)
    index = local_channel_index(channelNames, derivedNames{i});
    bias(index) = 0;
    noiseStd(index) = 0;
    timeConstant(index) = 0;
end
end

function cfg = local_sensor_cfg_defaults(cfg)
if ~isfield(cfg, 'mode') || isempty(cfg.mode)
    cfg.mode = 'identity';
end
if ~isfield(cfg, 'bias')
    cfg.bias = [];
end
if ~isfield(cfg, 'noiseStd')
    cfg.noiseStd = [];
end
if ~isfield(cfg, 'timeConstant')
    cfg.timeConstant = 0;
end
if ~isfield(cfg, 'randomSeed') || isempty(cfg.randomSeed)
    cfg.randomSeed = 1;
end
if ~isfield(cfg, 'biasModel') || isempty(cfg.biasModel)
    cfg.biasModel = struct('enabled', false);
elseif ~isstruct(cfg.biasModel) || ~isscalar(cfg.biasModel)
    error('SHT:Sensor:InvalidBiasModel', ...
        'cfg.biasModel 必须是标量结构体。');
elseif ~isfield(cfg.biasModel, 'enabled') || isempty(cfg.biasModel.enabled)
    cfg.biasModel.enabled = false;
end
end

function [bias, detail] = local_apply_bias_model( ...
        bias, channelNames, plantOutput, biasModel)
detail = struct('enabled', false);
if ~logical(biasModel.enabled)
    return;
end
if ~isfield(plantOutput, 'WIn') || ~isscalar(plantOutput.WIn) || ...
        ~isfinite(plantOutput.WIn)
    error('SHT:Sensor:MissingBiasFlowDriver', ...
        '流量相关偏置已启用，但发动机输出缺少有限标量 WIn。');
end

[generatedBias, generatedDetail] = sht_measurement_bias_generator( ...
    'evaluate', plantOutput.WIn, channelNames);
generatedBias = generatedBias(:);
supported = generatedDetail.channelConfig.supported(:);
% 2.6连续试车允许在不改变共享偏置字典的前提下，为不同试验生成
% 独立但幅度受控的公共偏置实现。比例只作用于公共偏置，既定的流量
% 漂移幅值和方向保持不变；未配置该字段时比例严格为1，历史结果不变。
if isfield(biasModel,'campaignCommonBiasScale') && ...
        ~isempty(biasModel.campaignCommonBiasScale)
    scale = biasModel.campaignCommonBiasScale(:);
    if isscalar(scale)
        scale = repmat(scale,numel(channelNames),1);
    end
    if numel(scale) ~= numel(channelNames) || any(~isfinite(scale)) || ...
            any(scale <= 0)
        error('SHT:Sensor:CampaignBiasScale', ...
            'campaignCommonBiasScale必须为正有限标量或与传感器向量等长。');
    end
    commonBias = generatedDetail.channelConfig.commonBias(:);
    generatedBias = generatedBias + (scale-1).*commonBias;
    generatedDetail.campaignCommonBiasScale = scale;
end
bias(supported) = generatedBias(supported);
detail = generatedDetail;
detail.enabled = true;
end

function xNext = local_first_order_sensor_step(x, rawNow, rawNext, tau, dt)
xNext = x(:);
tau = tau(:);
active = isfinite(tau) & tau > 0;
if any(~active)
    xNext(~active) = rawNext(~active);
end
if ~any(active)
    return;
end

xa = x(active);
taua = tau(active);
[a, bNow, bNext] = sht_first_order_foh_coefficients(dt, taua);

rawNowActive = rawNow(active);
rawNextActive = rawNext(active);
xNext(active) = a .* xa + bNow .* rawNowActive + bNext .* rawNextActive;
end

function vector = local_rebuild_derived_feedback(vector, channelNames)
%LOCAL_REBUILD_DERIVED_FEEDBACK 由基础测量值构造无独立误差的派生反馈量。
% 修正量定义与发动机部件模型一致：
%   Theta = Tt1 / 288.15
%   Deta  = Pt2 / 101325
%   Ngc   = Ng / sqrt(Theta)
% channelNames 用于显式校验传感器向量合同，避免以后调整向量顺序时静默错位。
required = {'Ng', 'Ngc', 'Theta', 'Deta', 'Pt2', 'Tt1', 'T45', 'Tt45'};
if any(strcmp(channelNames,'Pt1')), required{5} = 'Pt1'; end
index = zeros(size(required));
for i = 1:numel(required)
    index(i) = local_channel_index(channelNames, required{i});
end

ng = vector(index(1));
pt2 = vector(index(5));
tt1 = vector(index(6));
if ~isfinite(tt1) || tt1 <= 0
    error('SHT:Sensor:InvalidMeasuredTt1', ...
        '用于闭环修正转速计算的 Tt1 测量值必须为有限正数，当前为 %.12g K。', tt1);
end
if ~isfinite(pt2) || pt2 <= 0
    error('SHT:Sensor:InvalidMeasuredPt2', ...
        '用于闭环压力修正量计算的 Pt2 测量值必须为有限正数，当前为 %.12g Pa。', pt2);
end
if ~isfinite(ng)
    error('SHT:Sensor:InvalidMeasuredNg', ...
        '用于闭环修正转速计算的 Ng 测量值必须有限。');
end

theta = tt1 / 288.15;
vector(index(3)) = theta;
vector(index(4)) = pt2 / 101325;
vector(index(2)) = ng / sqrt(theta);
% 对外规范槽位始终复制控制器实际使用的同一物理测点结果。
vector(index(8)) = vector(index(7));
end

function vector = local_sync_t45_alias(vector, channelNames)
primaryIndex = local_channel_index(channelNames, 'T45');
aliasIndex = local_channel_index(channelNames, 'Tt45');
vector(aliasIndex) = vector(primaryIndex);
end

function index = local_channel_index(channelNames, channelName)
match = find(strcmp(channelNames, channelName));
if numel(match) ~= 1
    error('SHT:Sensor:ChannelContract', ...
        '传感器向量必须且只能包含一个 %s 通道。', channelName);
end
index = match;
end

function sample = local_vector_to_sample(v)
sample = struct();
sample.Np = v(1);
sample.Ng = v(2);
sample.T45 = v(3);
sample.Mkp = v(4);
sample.Ngc = v(5);
sample.Theta = v(6);
sample.Deta = v(7);
sample.Pt2 = v(8);
sample.Tt1 = v(9);
sample.Pt3 = v(10);
sample.Tt3 = v(11);
sample.Pt45 = v(12);
sample.Tt45 = v(13);
sample.Pt5 = v(14);
sample.Tt5 = v(15);
sample.T5 = sample.Tt5;
sample.HpcStallMargin = v(16);
sample.FAR = v(17);
sample.T4 = v(18);
sample.Mkg = v(19);
sample.Pamb = v(20);
sample.Tamb = v(21);
sample.Altitude = v(22);
sample.Mach = v(23);
sample.vector = v;
end

function v = local_expand_vector(inputValue, n, fillValue)
v = fillValue * ones(n, 1);
if isempty(inputValue)
    return;
end
inputValue = inputValue(:);
m = min(numel(inputValue), n);
v(1:m) = inputValue(1:m);
end
