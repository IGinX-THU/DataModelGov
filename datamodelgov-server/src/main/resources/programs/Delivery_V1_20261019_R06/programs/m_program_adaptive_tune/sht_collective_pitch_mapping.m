function [outputValue, diagnostic] = sht_collective_pitch_mapping( ...
    inputValue, direction, mappingCfg)
%SHT_COLLECTIVE_PITCH_MAPPING 在等效总距角和归一化负载因子之间转换。
%
% 本函数实现第 3.1 阶段首轮工程近似：
%
%   k_theta = r_p + (1-r_p) * ((theta-theta_z)/(theta_0-theta_z))^(3/2)
%
% 其中 theta 是 0.75R 处等效总距角，theta_z 是等效零升力总距角，
% theta_0 是设计参考总距角，r_p 是设计点型阻转矩占总转矩的比例。
% 该映射只表示首轮等效关系，不代替真实旋翼 C_Q-theta 特性图。
%
% direction 可取：
%   'thetaToKTheta' : inputValue 为总距角，单位 deg；
%   'kThetaToTheta' : inputValue 为无量纲 k_theta。
%
% mappingCfg 必须包含：
%   thetaZeroDeg          等效零升力总距角，deg；
%   thetaDesignDeg        设计参考总距角，deg；
%   profileTorqueFraction 设计点型阻转矩比例，范围 [0,1)；
%   thetaValidRangeDeg    首轮工程有效范围 [min,max]，deg。
%
% 函数不对超出 thetaValidRangeDeg 的值进行截断，只在 diagnostic
% 中返回范围标志，由上层任务调度器决定报警或停止。

if nargin ~= 3 || ~isstruct(mappingCfg)
    error('sht:collectivePitch:badInput', ...
        '需要输入数值、转换方向和总距映射配置。');
end
if ~isnumeric(inputValue) || ~isreal(inputValue) || ...
        any(~isfinite(inputValue(:)))
    error('sht:collectivePitch:badValue', ...
        '输入必须是有限实数标量或数组。');
end
if isstring(direction) && isscalar(direction)
    direction = char(direction);
end
if ~ischar(direction)
    error('sht:collectivePitch:badDirection', ...
        'direction 必须为 thetaToKTheta 或 kThetaToTheta。');
end

requiredFields = {'thetaZeroDeg', 'thetaDesignDeg', ...
    'profileTorqueFraction', 'thetaValidRangeDeg'};
for i = 1:numel(requiredFields)
    if ~isfield(mappingCfg, requiredFields{i})
        error('sht:collectivePitch:missingConfig', ...
            '总距映射配置缺少字段 %s。', requiredFields{i});
    end
end

thetaZeroDeg = mappingCfg.thetaZeroDeg;
thetaDesignDeg = mappingCfg.thetaDesignDeg;
profileFraction = mappingCfg.profileTorqueFraction;
validRangeDeg = mappingCfg.thetaValidRangeDeg(:).';

local_assert_finite_scalar(thetaZeroDeg, 'thetaZeroDeg');
local_assert_finite_scalar(thetaDesignDeg, 'thetaDesignDeg');
if thetaDesignDeg <= thetaZeroDeg
    error('sht:collectivePitch:badReferenceAngles', ...
        'thetaDesignDeg 必须大于 thetaZeroDeg。');
end
if ~isnumeric(profileFraction) || ~isreal(profileFraction) || ...
        ~isscalar(profileFraction) || ~isfinite(profileFraction) || ...
        profileFraction < 0 || profileFraction >= 1
    error('sht:collectivePitch:badProfileFraction', ...
        'profileTorqueFraction 必须位于 [0,1) 内。');
end
if ~isnumeric(validRangeDeg) || ~isreal(validRangeDeg) || ...
        numel(validRangeDeg) ~= 2 || any(~isfinite(validRangeDeg)) || ...
        validRangeDeg(1) >= validRangeDeg(2)
    error('sht:collectivePitch:badValidRange', ...
        'thetaValidRangeDeg 必须是严格递增的两元有限向量。');
end
if validRangeDeg(1) < thetaZeroDeg || ...
        thetaDesignDeg < validRangeDeg(1) || ...
        thetaDesignDeg > validRangeDeg(2)
    error('sht:collectivePitch:inconsistentValidRange', ...
        ['thetaValidRangeDeg 不得低于 thetaZeroDeg，' ...
         '且必须包含 thetaDesignDeg。']);
end

angleScaleDeg = thetaDesignDeg - thetaZeroDeg;
switch lower(strtrim(direction))
    case 'thetatoktheta'
        thetaDeg = inputValue;
        if any(thetaDeg(:) < thetaZeroDeg)
            error('sht:collectivePitch:belowZeroLiftAngle', ...
                '总距角不得小于 thetaZeroDeg=%.12g deg。', thetaZeroDeg);
        end
        normalizedAngle = (thetaDeg - thetaZeroDeg) / angleScaleDeg;
        kTheta = profileFraction + ...
            (1 - profileFraction) .* normalizedAngle .^ 1.5;
        outputValue = kTheta;

    case 'kthetatotheta'
        kTheta = inputValue;
        tolerance = 100 * eps(max(1, max(abs(kTheta(:)))));
        if any(kTheta(:) < profileFraction - tolerance)
            error('sht:collectivePitch:belowProfileFloor', ...
                ['k_theta 不得小于型阻转矩下限 %.12g；' ...
                 '当前最小值为 %.12g。'], ...
                profileFraction, min(kTheta(:)));
        end
        normalizedTorque = max((kTheta - profileFraction) / ...
            (1 - profileFraction), 0);
        thetaDeg = thetaZeroDeg + angleScaleDeg .* ...
            normalizedTorque .^ (2 / 3);
        outputValue = thetaDeg;

    otherwise
        error('sht:collectivePitch:unknownDirection', ...
            'direction=%s 无效；必须为 thetaToKTheta 或 kThetaToTheta。', ...
            direction);
end

validKThetaRange = profileFraction + (1 - profileFraction) .* ...
    ((validRangeDeg - thetaZeroDeg) / angleScaleDeg) .^ 1.5;
diagnostic = struct();
diagnostic.thetaDeg = thetaDeg;
diagnostic.kTheta = kTheta;
diagnostic.thetaWithinValidRange = ...
    thetaDeg >= validRangeDeg(1) & thetaDeg <= validRangeDeg(2);
diagnostic.thetaValidRangeDeg = validRangeDeg;
diagnostic.kThetaValidRange = validKThetaRange;
diagnostic.thetaZeroDeg = thetaZeroDeg;
diagnostic.thetaDesignDeg = thetaDesignDeg;
diagnostic.profileTorqueFraction = profileFraction;
end

function local_assert_finite_scalar(value, name)
if ~isnumeric(value) || ~isreal(value) || ...
        ~isscalar(value) || ~isfinite(value)
    error('sht:collectivePitch:badScalar', '%s 必须是有限标量。', name);
end
end
