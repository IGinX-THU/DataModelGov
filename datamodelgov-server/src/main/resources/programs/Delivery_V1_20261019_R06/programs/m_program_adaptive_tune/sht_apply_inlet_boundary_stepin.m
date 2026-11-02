function [stepInValue, detail] = sht_apply_inlet_boundary_stepin(stepInValue, boundary)
%SHT_APPLY_INLET_BOUNDARY_STEPIN 将命名进口边界写入 DLL 基础输入区。
%
% MATLAB 与 C 的固定对应关系如下（MATLAB 为 1 基下标）：
%   11 高度，12 马赫数，13 非标准温差，14 Pt1或Pt2，
%   15 Tt1，16 环境或进口静压，
%   17 进口边界模式，18 健康参数调度开关，19 Tamb，
%   20 模式2/5外部装机总压恢复系数。
%
% 模式定义：
%   0：仅在 ConditionsInit 中读取高度/Mach/非标准温差，运行入口沿用
%      初始化时锁存的环境边界；
%   1：直接给定 Pt1/Tt1/Pamb，用于历史外部 Pt1 接口回归；
%   2：给定 Pamb/Tamb/Mach，由 DLL 重构 Pt1/Tt1，供替代数据生成；
%   3：逐次给定高度/Mach/静温Tamb，DLL复用标准大气模型计算Pamb，
%      并重构Pt1/Tt1，供无测量数据预测；
%   4：给定 Pamb/Tamb/Mach、测量 Tt1 和测量 Pt2。DLL重构
%      Pt1，但以测量Pt2直接作为压气机进口压力，专用于参数辨识。
%   5：给定可测 Ps0/Ts_amb/Mach/Tt1 和外部装机总压恢复系数，
%      DLL统一重构Pt0/Pt1，专用于稀疏飞参回放。
%
% 模式4是Pt2唯一允许作为输入的模式，且stepIn(14)在该模式下
% 的语义为Pt2，不再是Pt1。

if ~isnumeric(stepInValue) || ~isreal(stepInValue) || numel(stepInValue) < 20
    error('SHT:InletBoundary:StepInTooShort', ...
        'stepInValue 必须是至少包含20个元素的实数数组。');
end
if nargin < 2 || ~isstruct(boundary) || ~isscalar(boundary)
    error('SHT:InletBoundary:InvalidBoundary', ...
        'boundary 必须是标量结构体。');
end

mode = local_resolve_mode(boundary);
altitude = local_optional_scalar(boundary, {'altitude','altitude_m'}, 0);
mach = local_optional_scalar(boundary, {'Mach','mach'}, 0);
deltaTemperature = local_optional_scalar(boundary, ...
    {'deltaTemperature','deltaTemperature_K'}, 0);

local_validate_finite(altitude, 'altitude');
local_validate_nonnegative(mach, 'Mach');
local_validate_finite(deltaTemperature, 'deltaTemperature');

% 每次完整覆盖模式相关槽位，防止复用 stepIn 模板时残留另一模式数据。
stepInValue(11) = altitude;
stepInValue(12) = mach;
stepInValue(13) = deltaTemperature;
stepInValue(14:17) = 0;
stepInValue(17) = mode;
stepInValue(19:20) = 0;

switch mode
    case 0
        % 标准大气模式只使用高度、马赫数和非标准温差。
    case 1
        pt1 = local_required_positive(boundary, 'Pt1');
        tt1 = local_required_positive(boundary, 'Tt1');
        pamb = local_required_positive(boundary, 'Pamb');
        stepInValue(14:16) = [pt1; tt1; pamb];
    case 2
        pamb = local_required_positive(boundary, 'Pamb');
        tamb = local_required_positive(boundary, 'Tamb');
        inletTotalPressureRecovery = local_optional_scalar(boundary, ...
            {'inletTotalPressureRecovery','totalPressureRecovery'}, 1);
        local_validate_recovery(inletTotalPressureRecovery, ...
            'inletTotalPressureRecovery');
        stepInValue(16) = pamb;
        stepInValue(19) = tamb;
        stepInValue(20) = inletTotalPressureRecovery;
    case 3
        tamb = local_required_positive(boundary, 'Tamb');
        % 模式3的静温直接决定相对标准大气温差，禁止残留的显式dT参与。
        stepInValue(13) = 0;
        stepInValue(19) = tamb;
    case 4
        pt2 = local_required_positive(boundary, 'Pt2');
        tt1 = local_required_positive(boundary, 'Tt1');
        pamb = local_required_positive(boundary, 'Pamb');
        tamb = local_required_positive(boundary, 'Tamb');
        stepInValue(14:16) = [pt2; tt1; pamb];
        stepInValue(19) = tamb;
    case 5
        ps0 = local_required_positive_alias(boundary, {'Ps0','Pamb'});
        tt1 = local_required_positive(boundary, 'Tt1');
        tamb = local_required_positive_alias(boundary, {'Ts_amb','Tamb'});
        inletTotalPressureRecovery = local_optional_scalar(boundary, ...
            {'inletTotalPressureRecovery','totalPressureRecovery'}, 1);
        local_validate_recovery(inletTotalPressureRecovery, ...
            'inletTotalPressureRecovery');
        stepInValue(15:16) = [tt1; ps0];
        stepInValue(19) = tamb;
        stepInValue(20) = inletTotalPressureRecovery;
    otherwise
        error('SHT:InletBoundary:InternalMode', ...
            '未处理的进口边界模式%d。', mode);
end

detail = struct();
detail.mode = mode;
detail.altitude_m = altitude;
detail.Mach = mach;
detail.deltaTemperature_K = stepInValue(13);
detail.directPt1InputUsed = mode == 1;
detail.measuredTt1InputUsed = ismember(mode, [1, 4, 5]);
detail.pt2InputUsed = mode == 4;
detail.ambientPressureInputUsed = ismember(mode, [1, 2, 4, 5]);
detail.altitudeAtmosphereUsed = mode == 3;
detail.externalPressureRecoveryInputUsed = ismember(mode, [2, 5]);
detail.measuredStaticPressureReplayUsed = mode == 5;
if ismember(mode, [2, 5])
    detail.inletTotalPressureRecovery = stepInValue(20);
else
    detail.inletTotalPressureRecovery = NaN;
end
detail.matlabIndices = struct('altitude',11,'Mach',12, ...
    'deltaTemperature',13,'Pt1_or_Pt2',14,'Pt1',14,'Pt2',14, ...
    'Tt1',15,'Pamb',16, ...
    'mode',17,'healthScheduleEnabled',18,'Tamb',19, ...
    'inletTotalPressureRecovery',20);
end

function mode = local_resolve_mode(boundary)
if isfield(boundary, 'inletBoundaryMode') && ...
        ~isempty(boundary.inletBoundaryMode)
    value = boundary.inletBoundaryMode;
elseif all(isfield(boundary, {'Pt1','Tt1','Pamb'})) && ...
        all(~cellfun(@isempty, {boundary.Pt1,boundary.Tt1,boundary.Pamb}))
    % 兼容改造前已有的外部 Pt1/Tt1/Pamb 配置。
    value = 1;
else
    value = 0;
end
if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
        ~isfinite(value) || value ~= round(value) || ~ismember(value, 0:5)
    error('SHT:InletBoundary:InvalidMode', ...
        'boundary.inletBoundaryMode 必须是整数0、1、2、3、4或5。');
end
mode = double(value);
end

function value = local_optional_scalar(s, names, defaultValue)
value = defaultValue;
for i = 1:numel(names)
    if isfield(s, names{i}) && ~isempty(s.(names{i}))
        value = s.(names{i});
        return;
    end
end
end

function value = local_required_positive(s, name)
if ~isfield(s, name) || isempty(s.(name))
    error('SHT:InletBoundary:MissingField', ...
        '当前进口边界模式缺少 boundary.%s。', name);
end
value = s.(name);
if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
        ~isfinite(value) || value <= 0
    error('SHT:InletBoundary:InvalidPositiveField', ...
        'boundary.%s 必须为有限正标量。', name);
end
end

function value = local_required_positive_alias(s, names)
value = [];
selectedName = '';
for i = 1:numel(names)
    if isfield(s, names{i}) && ~isempty(s.(names{i}))
        value = s.(names{i});
        selectedName = names{i};
        break;
    end
end
if isempty(selectedName)
    error('SHT:InletBoundary:MissingField', ...
        '当前进口边界模式缺少 boundary.%s。', strjoin(names, '或'));
end
if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
        ~isfinite(value) || value <= 0
    error('SHT:InletBoundary:InvalidPositiveField', ...
        'boundary.%s 必须为有限正标量。', selectedName);
end
end

function local_validate_finite(value, name)
if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ~isfinite(value)
    error('SHT:InletBoundary:InvalidFiniteField', ...
        'boundary.%s 必须为有限实标量。', name);
end
end

function local_validate_nonnegative(value, name)
local_validate_finite(value, name);
if value < 0
    error('SHT:InletBoundary:InvalidNonnegativeField', ...
        'boundary.%s 必须为非负值。', name);
end
end

function local_validate_recovery(value, name)
local_validate_finite(value, name);
if value <= 0 || value > 1
    error('SHT:InletBoundary:InvalidRecovery', ...
        'boundary.%s必须为(0,1]内的有限标量。', name);
end
end
