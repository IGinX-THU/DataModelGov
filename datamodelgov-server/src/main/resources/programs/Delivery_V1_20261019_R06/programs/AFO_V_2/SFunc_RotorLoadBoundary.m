function SFunc_RotorLoadBoundary(block)
%SFunc_RotorLoadBoundary 旋翼总距、PT负载扭矩和功率的无状态边界模型。
%
% 输入向量：
%   u(1) 当前 Np，rpm；
%   u(2) 旧功率指令，W，仅 legacyPower 模式使用；
%   u(3) 直接 Mkp 指令，N*m，仅 directTorque 模式使用；
%   u(4) 0.75R 处等效总距角，deg，仅 collectivePitch 模式使用。
%
% 输出向量：
%   y = [Mkp; theta; kTheta; Npr; Pload; thetaWithinValidRange]。
%
% 模式：
%   legacyPower    严格保持旧功率边界，Mkp = P_ref / omega_p；
%   directTorque   Mkp 是权威输入；
%   collectivePitch  theta 是权威输入。
%
% 本模块只构造飞机/旋翼侧负载边界，不调用发动机 DLL。

setup(block);
end

function setup(block)
block.NumDialogPrms = 2;
block.NumInputPorts = 1;
block.NumOutputPorts = 1;

block.SetPreCompInpPortInfoToDynamic;
block.SetPreCompOutPortInfoToDynamic;
block.InputPort(1).Dimensions = 4;
block.InputPort(1).DirectFeedthrough = true;
block.OutputPort(1).Dimensions = 6;

block.SampleTimes = [-1 0];
block.SimStateCompliance = 'DefaultSimState';
block.RegBlockMethod('Outputs', @Output);
end

function Output(block)
mode = local_normalize_mode(block.DialogPrm(1).Data);
cfg = local_validate_config(block.DialogPrm(2).Data);

input = block.InputPort(1).Data(:);
if numel(input) ~= 4 || any(~isfinite(input))
    error('sht:slxRotorLoad:badInput', ...
        '旋翼负载模型输入必须是 4 维有限实数向量。');
end

Np = input(1);
referencePower = input(2);
directMkp = input(3);
thetaCommand = input(4);
if Np <= 0
    error('sht:slxRotorLoad:badNp', 'Np 必须为有限正值。');
end

designOmega = cfg.designNpRpm * pi / 30;
designTorque = cfg.designPowerW / designOmega;
Npr = Np / cfg.designNpRpm;

switch mode
    case 'legacypower'
        if referencePower < 0
            error('sht:slxRotorLoad:badReferencePower', ...
                'legacyPower 模式的功率指令不得为负。');
        end
        % 兼容模式的首要约束是 DLL 接收到的功率与旧 SLX 完全一致。
        % kTheta 和 theta 仅表示设计转速下的等效诊断量，不参与 Mkp
        % 计算；否则采用 Mkp~Np^2 会使实际功率变成 P_ref*Npr^3。
        kTheta = referencePower / cfg.designPowerW;
        if kTheta >= cfg.profileTorqueFraction
            theta = local_k_theta_to_theta(kTheta, cfg);
        else
            % 低于简化旋翼模型的剖面阻力下限时不存在等效桨距角。
            % 保留功率边界并用 NaN 明确标记该诊断量不可用。
            theta = NaN;
        end
        Mkp = referencePower / (Np * pi / 30);

    case 'directtorque'
        if directMkp < 0
            error('sht:slxRotorLoad:badDirectTorque', ...
                'directTorque 模式的 Mkp 不得为负。');
        end
        Mkp = directMkp;
        theta = NaN;
        kTheta = NaN;

    case 'collectivepitch'
        theta = thetaCommand;
        kTheta = local_theta_to_k_theta(theta, cfg);
        Mkp = designTorque * kTheta * Npr^2;

    otherwise
        error('sht:slxRotorLoad:unknownMode', ...
            '不支持的旋翼负载输入模式 %s。', mode);
end

Pload = Mkp * Np * pi / 30;
if strcmp(mode, 'directtorque')
    thetaWithinValidRange = true;
else
    thetaWithinValidRange = theta >= cfg.thetaValidRangeDeg(1) && ...
        theta <= cfg.thetaValidRangeDeg(2);
end

block.OutputPort(1).Data = [ ...
    Mkp; theta; kTheta; Npr; Pload; double(thetaWithinValidRange)];
end

function mode = local_normalize_mode(rawMode)
if isstring(rawMode) && isscalar(rawMode)
    rawMode = char(rawMode);
end
if ~ischar(rawMode)
    error('sht:slxRotorLoad:badMode', ...
        'RotorLoadInputMode 必须是字符向量或标量字符串。');
end
mode = lower(strtrim(rawMode));
if ~ismember(mode, {'legacypower', 'directtorque', 'collectivepitch'})
    error('sht:slxRotorLoad:badMode', ...
        ['RotorLoadInputMode 必须为 legacyPower、directTorque 或 ' ...
         'collectivePitch。']);
end
end

function cfg = local_validate_config(cfg)
if ~isstruct(cfg) || ~isscalar(cfg)
    error('sht:slxRotorLoad:badConfig', ...
        'RotorLoadCfg 必须是标量结构体。');
end

required = {'designNpRpm', 'designPowerW', 'thetaZeroDeg', ...
    'thetaDesignDeg', 'profileTorqueFraction', 'thetaValidRangeDeg'};
for index = 1:numel(required)
    if ~isfield(cfg, required{index})
        error('sht:slxRotorLoad:missingConfig', ...
            'RotorLoadCfg 缺少字段 %s。', required{index});
    end
end

local_positive_scalar(cfg.designNpRpm, 'designNpRpm');
local_positive_scalar(cfg.designPowerW, 'designPowerW');
local_finite_scalar(cfg.thetaZeroDeg, 'thetaZeroDeg');
local_finite_scalar(cfg.thetaDesignDeg, 'thetaDesignDeg');

if cfg.thetaDesignDeg <= cfg.thetaZeroDeg
    error('sht:slxRotorLoad:badReferenceAngle', ...
        'thetaDesignDeg 必须大于 thetaZeroDeg。');
end
if ~isscalar(cfg.profileTorqueFraction) || ...
        ~isfinite(cfg.profileTorqueFraction) || ...
        cfg.profileTorqueFraction < 0 || cfg.profileTorqueFraction >= 1
    error('sht:slxRotorLoad:badProfileFraction', ...
        'profileTorqueFraction 必须位于 [0,1) 内。');
end

range = cfg.thetaValidRangeDeg(:).';
if numel(range) ~= 2 || any(~isfinite(range)) || range(1) >= range(2)
    error('sht:slxRotorLoad:badValidRange', ...
        'thetaValidRangeDeg 必须是严格递增的二元有限向量。');
end
if range(1) < cfg.thetaZeroDeg || ...
        cfg.thetaDesignDeg < range(1) || cfg.thetaDesignDeg > range(2)
    error('sht:slxRotorLoad:inconsistentValidRange', ...
        '有效范围不得低于零升力角，并且必须包含设计参考角。');
end
cfg.thetaValidRangeDeg = range;
end

function kTheta = local_theta_to_k_theta(theta, cfg)
if theta < cfg.thetaZeroDeg
    error('sht:slxRotorLoad:belowZeroLiftAngle', ...
        '总距角 %.12g deg 低于等效零升力角 %.12g deg。', ...
        theta, cfg.thetaZeroDeg);
end

normalizedAngle = (theta - cfg.thetaZeroDeg) / ...
    (cfg.thetaDesignDeg - cfg.thetaZeroDeg);
kTheta = cfg.profileTorqueFraction + ...
    (1 - cfg.profileTorqueFraction) * normalizedAngle^1.5;
end

function theta = local_k_theta_to_theta(kTheta, cfg)
tolerance = 100 * eps(max(1, abs(kTheta)));
if kTheta < cfg.profileTorqueFraction - tolerance
    error('sht:slxRotorLoad:belowProfileFloor', ...
        'kTheta=%.12g 低于型阻转矩下限 %.12g。', ...
        kTheta, cfg.profileTorqueFraction);
end

normalizedTorque = max((kTheta - cfg.profileTorqueFraction) / ...
    (1 - cfg.profileTorqueFraction), 0);
theta = cfg.thetaZeroDeg + ...
    (cfg.thetaDesignDeg - cfg.thetaZeroDeg) * normalizedTorque^(2 / 3);
end

function local_positive_scalar(value, name)
local_finite_scalar(value, name);
if value <= 0
    error('sht:slxRotorLoad:badPositiveScalar', ...
        '%s 必须为正值。', name);
end
end

function local_finite_scalar(value, name)
if ~isnumeric(value) || ~isreal(value) || ...
        ~isscalar(value) || ~isfinite(value)
    error('sht:slxRotorLoad:badScalar', ...
        '%s 必须是有限实数标量。', name);
end
end
