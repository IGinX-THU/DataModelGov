function [health, detail] = sht_health_schedule_evaluate(profile, operatingState)
%SHT_HEALTH_SCHEDULE_EVALUATE 计算给定工况下的159维修正系数向量。
%
% 常值参数直接返回designValue；一维调度参数统一计算
% K_eff=designValue+Delta(x)。旋转部件采用6节点，压损采用零流量锚点
% 加6个负载接通工况节点。所有曲线超出覆盖域时固定到最近端点。

if nargin ~= 2 || ~isstruct(profile) || ~isstruct(operatingState)
    error('SHT:HealthSchedule:BadInput', ...
        '需要有效的profile和标量operatingState结构体。');
end

parameters = profile.parameters;
health = zeros(numel(profile.truthVectorAtDesign), 1);
detail = repmat(struct('cIndex', NaN, 'name', '', 'coordinate', NaN, ...
    'coordinateClamped', NaN, 'value', NaN, 'wasClamped', false, ...
    'incrementValue', NaN, ...
    'scheduleKind', '', 'interpolationMethod', ''), ...
    numel(parameters), 1);

for i = 1:numel(parameters)
    parameter = parameters(i);
    if strcmp(parameter.mode, 'constant')
        coordinate = NaN;
        coordinateClamped = NaN;
        value = parameter.designValue;
        incrementValue = 0;
        wasClamped = false;
    elseif strcmp(parameter.mode, 'table1d')
        if ~isfield(operatingState, parameter.axisName)
            error('SHT:HealthSchedule:MissingCoordinate', ...
                '计算h%d %s时缺少工况坐标operatingState.%s。', ...
                parameter.cIndex, parameter.name, parameter.axisName);
        end
        coordinate = operatingState.(parameter.axisName);
        if ~isscalar(coordinate) || ~isfinite(coordinate)
            error('SHT:HealthSchedule:BadCoordinate', ...
                '工况坐标%s必须为有限标量。', parameter.axisName);
        end
        xLower = parameter.xNodes(1);
        xUpper = parameter.xNodes(end);
        coordinateClamped = min(max(coordinate, xLower), xUpper);
        incrementValue = interp1(parameter.xNodes, parameter.deltaNodes, ...
            coordinateClamped, parameter.interpolationMethod);
        value = parameter.designValue + incrementValue;
        wasClamped = coordinate ~= coordinateClamped;
    else
        error('SHT:HealthSchedule:UnknownMode', ...
            'h%d使用了未知调度模式%s。', parameter.cIndex, parameter.mode);
    end

    health(parameter.matlabHealthIndex) = value;
    detail(i).cIndex = parameter.cIndex;
    detail(i).name = parameter.name;
    detail(i).coordinate = coordinate;
    detail(i).coordinateClamped = coordinateClamped;
    detail(i).value = value;
    detail(i).wasClamped = wasClamped;
    detail(i).incrementValue = incrementValue;
    detail(i).scheduleKind = parameter.scheduleKind;
    detail(i).interpolationMethod = parameter.interpolationMethod;
end
end
