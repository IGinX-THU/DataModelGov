function varargout = sht_measurement_bias_generator(action, varargin)
%SHT_MEASUREMENT_BIAS_GENERATOR 统一生成试车与飞参测量偏置。
%
% 本函数是稳态试车、过渡态试车和飞参替代数据共用的偏置真值模型。
% 偏置由两部分组成：
%
%   b_j(W2) = b_common,j + d_j * 0.10 * B_j * phi(W2)
%
% 其中 B_j 是通道偏置允许半宽，b_common,j 是一次试车内保持不变的
% 公共偏置；只有公开资料和测量机理均支持明显流量依赖的 Wf、T45、
% Tt3 启用漂移。phi 在冻结的设计点和地面慢车入口流量之间线性变化，
% 区间外固定为最近端点，禁止无界外推。
%
% 支持的调用：
%   model = sht_measurement_bias_generator('model');
%   table = sht_measurement_bias_generator('specification');
%   cfg   = sht_measurement_bias_generator('channelConfig', names);
%   [bias, detail] = sht_measurement_bias_generator( ...
%       'evaluate', inletFlow_kgps, names);

if nargin < 1 || isempty(action)
    error('SHT:MeasurementBias:MissingAction', '必须给定操作名称。');
end

switch lower(char(action))
    case {'model', 'definition'}
        varargout{1} = local_model();
    case 'specification'
        model = local_model();
        varargout{1} = model.specification;
    case 'channelconfig'
        varargout{1} = local_channel_config(varargin{:});
    case 'evaluate'
        [varargout{1:nargout}] = local_evaluate(varargin{:});
    otherwise
        error('SHT:MeasurementBias:UnknownAction', ...
            '未知操作：%s。', char(action));
end
end

function model = local_model()
% 设计参考值固定为当前第二轮六部件模型设计点。它们用于把百分比规格
% 转换为绝对量，不随某次数据集的样本极值改变。
reference = struct( ...
    'Np', 20800, ...
    'Ng', 38000, ...
    'Wf', 0.151914044493225, ...
    'T45', 1143.4502168824, ...
    'Mkp', 999.278795573804, ...
    'Mkg', 999.278795573804, ...
    'Pt2', 98285.25, ...
    'Tt1', 288.15, ...
    'Pt3', 1572564, ...
    'Tt3', 702.307986952118, ...
    'Pt45', 395927.737357462, ...
    'Pt5', 395927.737357462, ...
    'Tt5', 1143.4502168824, ...
    'Tamb', 288.15, ...
    'Pamb', 101325, ...
    'Altitude', 100, ...
    'Mach', 1);

% 偏置半宽均以设计参考值的比例给出；Pt5/Tt5 首轮分别继承
% Pt45/T45 同类传感器规格，后续取得实物量程与校准证书后替换。
rows = { ...
    'Np',   'rpm',  reference.Np,   'Np0',   0.00010,  +0.624000000000000, 1.286137,   false,  0; ...
    'Ng',   'rpm',  reference.Ng,   'Ng0',   0.00010,  -1.330000000000000, 1.731982,   false,  0; ...
    'Wf',   'kg/s', reference.Wf,   'Wf0',   0.00450,  +0.000478529240154, 3.9186e-5,  true,  +1; ...
    'T45',  'K',    reference.T45,  'T45_0', 0.00250,  -2.001037879544200, 0.342917,   true,  -1; ...
    'Mkp',  'N*m',  reference.Mkp,  'Mkp0',  0.00100,  +0.699495156901663, 0.247386,   false,  0; ...
    'Mkg',  'N*m',  reference.Mkg,  'Mkp0 proxy', 0.00100, -0.699495156901663, 0.247386, false, 0; ...
    'Pt2',  'Pa',   reference.Pt2,  'Pt2_0', 0.00050, -19.657050000000000, 12.06556713, false,  0; ...
    'Tt1',  'K',    reference.Tt1,  'Tt1_0', 0.00050,  +0.100852500000000, 0.041872,  false,  0; ...
    'Pt3',  'Pa',   reference.Pt3,  'Pt3_0', 0.00100, +1100.794800000000, 218.536741, false,  0; ...
    'Tt3',  'K',    reference.Tt3,  'Tt3_0', 0.00200,  -0.983231181732965, 0.213684,   true,  -1; ...
    'Pt45', 'Pa',   reference.Pt45, 'Pt45_0',0.00100, -277.149416150223, 43.618257,  false,  0; ...
    'Pt5',  'Pa',   reference.Pt5,  'Pt45_0 proxy',0.00100,-277.149416150223,43.618257,false,0; ...
    'Tt5',  'K',    reference.Tt5,  'T45_0 proxy',0.00250,-2.001037879544200,0.342917,false,0; ...
    'Tamb', 'K',    reference.Tamb, 'Tamb0', 0.00050,  +0.100852500000000, 0.041872,  false,  0; ...
    'Pamb', 'Pa',   reference.Pamb, 'Pamb0', 0.00020, -14.185500000000000, 12.438729, false,  0; ...
    'Altitude','m', reference.Altitude,'bench_altitude',0.01000,+1.000000000000000,0.500000,false,0; ...
    'Mach',  '-',    reference.Mach, 'bench_mach_prior',0,0,0,false,0};

n = size(rows, 1);
channels = repmat(struct( ...
    'name', '', 'unit', '', 'designReference', NaN, ...
    'referenceSource', '', 'totalBiasHalfWidthFraction', NaN, ...
    'totalBiasHalfWidthPctDesign', NaN, 'totalBiasHalfWidth', NaN, ...
    'commonBias', NaN, 'commonBiasPctDesign', NaN, ...
    'noiseStd', NaN, 'noiseStdPctDesign', NaN, ...
    'flowDriftEnabled', false, 'flowDriftDirection', 0, ...
    'maxFlowDriftFractionOfBiasHalfWidth', 0.10, ...
    'maxFlowDrift', 0, 'maxFlowDriftPctDesign', 0), n, 1);
for i = 1:n
    designReference = rows{i, 3};
    halfWidthFraction = rows{i, 5};
    halfWidth = designReference * halfWidthFraction;
    commonBias = rows{i, 6};
    noiseStd = rows{i, 7};
    driftEnabled = logical(rows{i, 8});
    driftDirection = rows{i, 9};

    channels(i).name = rows{i, 1};
    channels(i).unit = rows{i, 2};
    channels(i).designReference = designReference;
    channels(i).referenceSource = rows{i, 4};
    channels(i).totalBiasHalfWidthFraction = halfWidthFraction;
    channels(i).totalBiasHalfWidthPctDesign = 100 * halfWidthFraction;
    channels(i).totalBiasHalfWidth = halfWidth;
    channels(i).commonBias = commonBias;
    channels(i).commonBiasPctDesign = 100 * commonBias / designReference;
    channels(i).noiseStd = noiseStd;
    channels(i).noiseStdPctDesign = 100 * noiseStd / designReference;
    channels(i).flowDriftEnabled = driftEnabled;
    channels(i).flowDriftDirection = driftDirection;
    if driftEnabled
        channels(i).maxFlowDrift = 0.10 * halfWidth;
        channels(i).maxFlowDriftPctDesign = ...
            100 * 0.10 * halfWidthFraction;
    else
        channels(i).maxFlowDrift = 0;
        channels(i).maxFlowDriftPctDesign = 0;
    end
end

model = struct();
model.version = 'flow_dependent_bias_v1';
model.description = [ ...
    '一次试车公共偏置 + 仅Wf/T45/Tt3启用的入口流量相关系统漂移；' ...
    '漂移最大为偏置半宽的10%，流量覆盖域外固定到最近端点。'];
model.flowVariable = 'W2/WIn';
model.flowUnit = 'kg/s';
model.designFlow_kgps = 6.71144232125483;
model.idleFlow_kgps = 2.67949330351727;
model.maximumDriftFractionOfBiasHalfWidth = 0.10;
model.extrapolationMethod = 'nearest_endpoint_clamp';
model.commonBiasScope = 'one_test_campaign';
model.whiteNoiseScope = 'independent_samples_with_fixed_channel_std';
model.channels = channels;
model.specification = struct2table(channels);
end

function channelConfig = local_channel_config(channelNames)
channelNames = local_channel_names(channelNames);
model = local_model();
n = numel(channelNames);
channelConfig = struct();
channelConfig.names = channelNames(:);
channelConfig.supported = false(n, 1);
channelConfig.commonBias = zeros(n, 1);
channelConfig.noiseStd = zeros(n, 1);
channelConfig.totalBiasHalfWidth = zeros(n, 1);
channelConfig.flowDriftEnabled = false(n, 1);
channelConfig.flowDriftDirection = zeros(n, 1);
channelConfig.maxFlowDrift = zeros(n, 1);
channelConfig.unit = repmat({''}, n, 1);

definitionNames = {model.channels.name};
for i = 1:n
    % 历史测量模型内部曾使用T45命名。外部数据合同已经统一为Tt45，
    % 此处只做名称兼容，不改变既有T45传感器参数及历史调用结果。
    lookupName = channelNames{i};
    if strcmp(lookupName, 'Tt45')
        lookupName = 'T45';
    end
    index = find(strcmp(definitionNames, lookupName), 1, 'first');
    if isempty(index)
        continue;
    end
    item = model.channels(index);
    channelConfig.supported(i) = true;
    channelConfig.commonBias(i) = item.commonBias;
    channelConfig.noiseStd(i) = item.noiseStd;
    channelConfig.totalBiasHalfWidth(i) = item.totalBiasHalfWidth;
    channelConfig.flowDriftEnabled(i) = item.flowDriftEnabled;
    channelConfig.flowDriftDirection(i) = item.flowDriftDirection;
    channelConfig.maxFlowDrift(i) = item.maxFlowDrift;
    channelConfig.unit{i} = item.unit;
end
channelConfig.modelVersion = model.version;
end

function [bias, detail] = local_evaluate(inletFlow_kgps, channelNames)
if nargin < 2
    error('SHT:MeasurementBias:MissingEvaluateInput', ...
        'evaluate 需要入口流量和通道名。');
end
if ~isnumeric(inletFlow_kgps) || ~isreal(inletFlow_kgps) || ...
        isempty(inletFlow_kgps) || any(~isfinite(inletFlow_kgps(:)))
    error('SHT:MeasurementBias:InvalidFlow', ...
        '入口流量必须是非空有限实数数组。');
end

flow = inletFlow_kgps(:);
model = local_model();
channelConfig = local_channel_config(channelNames);

rawFactor = (model.designFlow_kgps - flow) ./ ...
    (model.designFlow_kgps - model.idleFlow_kgps);
% 明确采用最近端点外推：高于设计流量固定为0，低于慢车流量固定为1。
flowFactor = min(max(rawFactor, 0), 1);

nSample = numel(flow);
nChannel = numel(channelConfig.names);
bias = repmat(channelConfig.commonBias(:).', nSample, 1);
for i = 1:nChannel
    if channelConfig.supported(i) && channelConfig.flowDriftEnabled(i)
        bias(:, i) = bias(:, i) + ...
            channelConfig.flowDriftDirection(i) * ...
            channelConfig.maxFlowDrift(i) .* flowFactor;
    end
end

detail = struct();
detail.modelVersion = model.version;
detail.inletFlow_kgps = flow;
detail.rawFlowFactor = rawFactor;
detail.flowFactor = flowFactor;
detail.designFlow_kgps = model.designFlow_kgps;
detail.idleFlow_kgps = model.idleFlow_kgps;
detail.extrapolationMethod = model.extrapolationMethod;
detail.aboveDesignCount = nnz(rawFactor < 0);
detail.belowIdleCount = nnz(rawFactor > 1);
detail.channelConfig = channelConfig;
end

function names = local_channel_names(value)
if ischar(value)
    names = {value};
elseif isstring(value)
    names = cellstr(value(:));
elseif iscell(value)
    names = value(:);
else
    error('SHT:MeasurementBias:InvalidChannelNames', ...
        '通道名必须是字符、字符串或字符元胞数组。');
end
for i = 1:numel(names)
    if isstring(names{i}) && isscalar(names{i})
        names{i} = char(names{i});
    end
    if ~ischar(names{i}) || size(names{i}, 1) ~= 1 || ...
            isempty(strtrim(names{i}))
        error('SHT:MeasurementBias:InvalidChannelName', ...
            '第%d个通道名不是非空字符行。', i);
    end
    names{i} = strtrim(names{i});
end
end
