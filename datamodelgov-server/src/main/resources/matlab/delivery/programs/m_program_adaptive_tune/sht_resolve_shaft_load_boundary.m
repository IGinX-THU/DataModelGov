function boundary = sht_resolve_shaft_load_boundary(boundary, xEngine)
%SHT_RESOLVE_SHAFT_LOAD_BOUNDARY 统一解析 PT/GT 外部轴负载边界。
%
% M 程序业务接口采用外部负载扭矩：
%   Mkp = PT 负载/输出轴传递扭矩，N*m；
%   Mkg = GT 轴外部附件负载扭矩，N*m。
%
% 此辅助函数服务于旧功率接口(stepIn(8)=0)，使用当前轴转速换算：
%
%   Pload = Mload * pi * N / 30
% 新原生扭矩接口(stepIn(8)=1)直接写Mkp/Mkg，由DLL在共同工作求值时
% 换算；不能将本函数得到的power/hpsPower写进原生扭矩槽位。
%
% 两个轴分别通过 ptLoadInputMode 和 gtLoadInputMode 选择权威输入：
%   'torque'：Mkp/Mkg 为权威输入，随当前转速重新计算 power/hpsPower；
%   'power' ：power/hpsPower 为兼容输入，随当前转速计算 Mkp/Mkg。
%
% 普通闭环仿真可继续使用 power 模式以继承原功率指令；试车/飞参回放和
% 参数辨识必须显式使用 torque 模式，防止把测得扭矩误当成模型输出。

if nargin ~= 2 || ~isstruct(boundary)
    error('sht:loadBoundary:badInput', ...
        'boundary 必须是结构体，并同时给出当前 xEngine=[Np;Ng;...]。');
end
xEngine = xEngine(:);
if numel(xEngine) < 2 || any(~isfinite(xEngine(1:2))) || any(xEngine(1:2) <= 0)
    error('sht:loadBoundary:badShaftSpeed', ...
        '扭矩/功率换算需要有限正的当前 Np 和 Ng。');
end

omegaP = pi * xEngine(1) / 30;
omegaG = pi * xEngine(2) / 30;

ptMode = local_resolve_mode(boundary, 'ptLoadInputMode', 'Mkp', 'power');
gtMode = local_resolve_mode(boundary, 'gtLoadInputMode', 'Mkg', 'hpsPower');

boundary.ptLoadInputMode = ptMode;
boundary.gtLoadInputMode = gtMode;

switch ptMode
    case 'torque'
        boundary.Mkp = local_finite_scalar(boundary, 'Mkp');
        boundary.power = boundary.Mkp * omegaP;
    case 'power'
        boundary.power = local_finite_scalar(boundary, 'power');
        boundary.Mkp = boundary.power / omegaP;
end

switch gtMode
    case 'torque'
        boundary.Mkg = local_finite_scalar(boundary, 'Mkg');
        boundary.hpsPower = boundary.Mkg * omegaG;
    case 'power'
        boundary.hpsPower = local_finite_scalar(boundary, 'hpsPower');
        boundary.Mkg = boundary.hpsPower / omegaG;
end

% 明确记录本次 DLL 求值实际使用的物理量，便于日志和回归检查。
boundary.PTLoadTorque_Nm = boundary.Mkp;
boundary.GTAccessoryLoadTorque_Nm = boundary.Mkg;
boundary.PTLoadPower_W = boundary.power;
boundary.GTAccessoryPower_W = boundary.hpsPower;
end

function mode = local_resolve_mode(boundary, modeField, torqueField, powerField)
% 兼容直接调用旧函数的情况：未给模式时，有且仅有扭矩字段则采用扭矩模式，
% 其余情况沿用原功率接口。正式配置会显式写入模式，不依赖该推断。
if isfield(boundary, modeField) && ~isempty(boundary.(modeField))
    rawMode = boundary.(modeField);
elseif isfield(boundary, torqueField) && ~isempty(boundary.(torqueField)) && ...
        (~isfield(boundary, powerField) || isempty(boundary.(powerField)))
    rawMode = 'torque';
else
    rawMode = 'power';
end

if isstring(rawMode) && isscalar(rawMode)
    rawMode = char(rawMode);
end
if ~ischar(rawMode)
    error('sht:loadBoundary:badMode', ...
        '%s 必须为 ''torque'' 或 ''power''。', modeField);
end
mode = lower(strtrim(rawMode));
if ~ismember(mode, {'torque', 'power'})
    error('sht:loadBoundary:badMode', ...
        '%s 必须为 ''torque'' 或 ''power''，当前为 %s。', modeField, rawMode);
end
end

function value = local_finite_scalar(s, fieldName)
if ~isfield(s, fieldName) || isempty(s.(fieldName)) || ...
        ~isnumeric(s.(fieldName)) || ~isscalar(s.(fieldName)) || ...
        ~isfinite(s.(fieldName))
    error('sht:loadBoundary:badValue', ...
        '%s 必须是有限标量。', fieldName);
end
value = double(s.(fieldName));
end
