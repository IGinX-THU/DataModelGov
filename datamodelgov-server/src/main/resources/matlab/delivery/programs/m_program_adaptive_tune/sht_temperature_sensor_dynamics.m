function varargout = sht_temperature_sensor_dynamics(action, varargin)
%SHT_TEMPERATURE_SENSOR_DYNAMICS 统一维护试车与飞参温度传感器动态参数。
%
% 温度传感器采用连续一阶惯性模型：
%
%   tau * dTm/dt + Tm = Ttrue,  omega = 1 / tau
%
% 当前2.3稳态台架替代数据首先使用本字典。后续进入过渡态试车和
% 飞参数据阶段时，应直接复用本函数，不得在入口程序中复制另一套值。
% 离散仿真统一使用已有FOH解析离散函数。
%
% 支持的调用：
%   model = sht_temperature_sensor_dynamics('model');
%   tbl = sht_temperature_sensor_dynamics('specification');
%   value = sht_temperature_sensor_dynamics('timeConstantStruct');
%   value = sht_temperature_sensor_dynamics('bandwidthStruct');
%   cfg = sht_temperature_sensor_dynamics('channelConfig', names);

if nargin < 1 || isempty(action)
    action = 'model';
end

switch lower(char(action))
    case {'model', 'definition'}
        varargout{1} = local_model();
    case 'specification'
        model = local_model();
        varargout{1} = model.specification;
    case 'timeconstantstruct'
        model = local_model();
        varargout{1} = local_value_struct(model.channels, 'timeConstant_s');
    case 'bandwidthstruct'
        model = local_model();
        varargout{1} = local_value_struct(model.channels, 'bandwidth_radps');
    case 'channelconfig'
        varargout{1} = local_channel_config(varargin{:});
    otherwise
        error('SHT:TemperatureSensor:UnknownAction', ...
            '未知操作：%s。', char(action));
end
end

function model = local_model()
names = {'Tt1'; 'Tamb'; 'Tt3'; 'Tt45'; 'Tt5'};
timeConstant_s = [1.00; 2.00; 0.30; 0.50; 0.60];
bandwidth_radps = 1 ./ timeConstant_s;
stationMeaning = { ...
    '发动机1截面进口总温'; ...
    '环境静温'; ...
    '压气机出口总温'; ...
    '45截面总温'; ...
    '动力涡轮出口总温'};

model = struct();
model.version = 'temperature_sensor_dynamics_v1';
model.modelType = 'continuous_first_order';
model.discretization = 'FOH_exact';
model.delay_s = 0;
model.channels = repmat(struct( ...
    'name', '', 'stationMeaning', '', 'timeConstant_s', NaN, ...
    'bandwidth_radps', NaN), numel(names), 1);
for i = 1:numel(names)
    model.channels(i).name = names{i};
    model.channels(i).stationMeaning = stationMeaning{i};
    model.channels(i).timeConstant_s = timeConstant_s(i);
    model.channels(i).bandwidth_radps = bandwidth_radps(i);
end
model.specification = struct2table(model.channels);
end

function values = local_value_struct(channels, fieldName)
values = struct();
for i = 1:numel(channels)
    values.(channels(i).name) = channels(i).(fieldName);
end
end

function config = local_channel_config(channelNames)
if isstring(channelNames)
    channelNames = cellstr(channelNames(:));
elseif ischar(channelNames)
    channelNames = {channelNames};
elseif iscell(channelNames)
    channelNames = channelNames(:);
else
    error('SHT:TemperatureSensor:InvalidChannelNames', ...
        '通道名必须是字符向量、字符串数组或元胞数组。');
end

model = local_model();
definitionNames = {model.channels.name};
n = numel(channelNames);
config = struct();
config.names = channelNames;
config.supported = false(n, 1);
config.timeConstant_s = zeros(n, 1);
config.bandwidth_radps = inf(n, 1);
for i = 1:n
    index = find(strcmp(definitionNames, channelNames{i}), 1, 'first');
    if isempty(index)
        continue;
    end
    config.supported(i) = true;
    config.timeConstant_s(i) = model.channels(index).timeConstant_s;
    config.bandwidth_radps(i) = model.channels(index).bandwidth_radps;
end
end
