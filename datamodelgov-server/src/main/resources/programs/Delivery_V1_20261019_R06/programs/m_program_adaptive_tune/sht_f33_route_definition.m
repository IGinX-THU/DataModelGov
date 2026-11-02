function route = sht_f33_route_definition(varargin)
%SHT_F33_ROUTE_DEFINITION 3.3四条辨识路线的唯一定义。
%
%   route = sht_f33_route_definition()
%       返回默认路线R2（瞬态时刻模型、纯稳态平均点）。
%
%   route = sht_f33_route_definition('R3')
%       按路线编号返回模型路径和数据方法。
%
%   route = sht_f33_route_definition('steady','steady_only')
%       根据底层配置反查路线编号。
%
% 路线编号只表示“前向模型×辨识数据”组合，不表示调度曲线
% 的幅值法或独立节点法。后两者由scheduleParameterization单独选择。

definition = {
    'R1', 'steady',            'steady_only',               '稳态模型 + 纯稳态平均点';
    'R2', 'transient_instant', 'steady_only',               '瞬态时刻模型 + 纯稳态平均点';
    'R3', 'steady',            'steady_plus_small_history', '稳态模型 + 稳态点与小幅历程';
    'R4', 'transient_instant', 'steady_plus_small_history', '瞬态时刻模型 + 稳态点与小幅历程'};

if nargin == 0
    index = 2;
elseif nargin == 1
    routeId = upper(strtrim(char(string(varargin{1}))));
    index = find(strcmp(definition(:, 1), routeId), 1);
    if isempty(index)
        error('SHT:F33Route:UnknownRoute', ...
            '路线编号必须为R1、R2、R3或R4，当前为%s。', routeId);
    end
elseif nargin == 2
    modelRoute = lower(strtrim(char(string(varargin{1}))));
    dataMethod = lower(strtrim(char(string(varargin{2}))));
    index = find(strcmp(definition(:, 2), modelRoute) & ...
        strcmp(definition(:, 3), dataMethod), 1);
    if isempty(index)
        error('SHT:F33Route:UnknownCombination', ...
            '模型路径%s与数据方法%s不构成有效3.3路线。', ...
            modelRoute, dataMethod);
    end
else
    error('SHT:F33Route:BadInputCount', ...
        '只允许不给参数、给出一个路线编号或给出模型/数据两个参数。');
end

route = struct('routeId', definition{index, 1}, ...
    'modelRoute', definition{index, 2}, ...
    'dataMethod', definition{index, 3}, ...
    'label', definition{index, 4});
end
