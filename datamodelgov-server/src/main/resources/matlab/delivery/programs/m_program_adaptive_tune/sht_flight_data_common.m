function output = sht_flight_data_common(action, varargin)
%SHT_FLIGHT_DATA_COMMON 第 3.1 阶段飞行环境公共计算。
%
% 当前 S4 提供两项稳定接口：
%   atmosphere = sht_flight_data_common( ...
%       'flightAtmosphere', pressureAltitude_m, mach, deltaT_K)
%   constants = sht_flight_data_common('constants')
%
% pressureAltitude_m 在首轮明确解释为气压高度。静压由该高度的 ISA
% 对流层关系计算；deltaT_K 只表示相对 ISA 的静温偏差，不反向改变气压
% 高度对应的静压。当前按项目要求，超出 0~11 km 名义适用范围时静默沿用
% 同一对流层公式，不报警、不截断；返回值会记录是否发生公式外推。若以后
% 输入几何高度和实测温压，应增加独立模式，不能悄悄改变变量含义。

if nargin < 1
    error('sht:flightDataCommon:missingAction', ...
        '必须给出 flightAtmosphere 或 constants 操作。');
end
if isstring(action) && isscalar(action)
    action = char(action);
end
if ~ischar(action)
    error('sht:flightDataCommon:badAction', ...
        'action 必须是字符行向量或标量字符串。');
end

switch lower(strtrim(action))
    case 'flightatmosphere'
        if numel(varargin) ~= 3
            error('sht:flightDataCommon:badAtmosphereInputCount', ...
                ['flightAtmosphere 需要 pressureAltitude_m、mach 和 ' ...
                 'deltaT_K 三个输入。']);
        end
        output = local_flight_atmosphere( ...
            varargin{1}, varargin{2}, varargin{3});

    case 'constants'
        if ~isempty(varargin)
            error('sht:flightDataCommon:badConstantsInputCount', ...
                'constants 操作不接收附加输入。');
        end
        output = local_constants();

    otherwise
        error('sht:flightDataCommon:unknownAction', ...
            '未知操作 %s；只支持 flightAtmosphere 或 constants。', action);
end
end

function atmosphere = local_flight_atmosphere(altitude_m, mach, deltaT_K)
local_assert_finite_scalar(altitude_m, 'pressureAltitude_m');
local_assert_finite_scalar(mach, 'mach');
local_assert_finite_scalar(deltaT_K, 'deltaT_K');

c = local_constants();
if mach < 0 || mach > c.maximumMach
    error('sht:flightDataCommon:machOutsideRange', ...
        'mach=%.12g 超出首轮适用范围 [0, %.12g]。', ...
        mach, c.maximumMach);
end

Tisa_K = c.seaLevelTemperature_K - c.temperatureLapseRate_Kpm * altitude_m;
Ts_K = Tisa_K + deltaT_K;
if Tisa_K <= 0 || Ts_K <= c.minimumStaticTemperature_K
    error('sht:flightDataCommon:staticTemperatureTooLow', ...
        ['对流层公式外推后 Tisa=%.12g K、Ts=%.12g K，已超出数值可行域；' ...
         'Ts 必须高于安全下限 %.12g K。'], ...
        Tisa_K, ...
        Ts_K, c.minimumStaticTemperature_K);
end

pressureExponent = c.gravity_mps2 / ...
    (c.gasConstant_JpkgK * c.temperatureLapseRate_Kpm);
Ps_Pa = c.seaLevelPressure_Pa * ...
    (Tisa_K / c.seaLevelTemperature_K) ^ pressureExponent;
rho_kgpm3 = Ps_Pa / (c.gasConstant_JpkgK * Ts_K);
speedOfSound_mps = sqrt(c.gamma * c.gasConstant_JpkgK * Ts_K);
trueAirspeed_mps = mach * speedOfSound_mps;
dynamicPressure_Pa = 0.5 * rho_kgpm3 * trueAirspeed_mps ^ 2;

ramTemperatureRatio = 1 + 0.5 * (c.gamma - 1) * mach ^ 2;
ramPressureRatio = ramTemperatureRatio ^ (c.gamma / (c.gamma - 1));
Tt0_K = Ts_K * ramTemperatureRatio;
Pt0_Pa = Ps_Pa * ramPressureRatio;

numericValues = [Tisa_K, Ts_K, Ps_Pa, rho_kgpm3, ...
    speedOfSound_mps, trueAirspeed_mps, dynamicPressure_Pa, ...
    ramTemperatureRatio, ramPressureRatio, Tt0_K, Pt0_Pa];
if any(~isfinite(numericValues)) || any(numericValues([1:5,8:11]) <= 0)
    error('sht:flightDataCommon:nonfiniteAtmosphere', ...
        '飞行环境计算产生非有限值或非正热力学量。');
end
if Pt0_Pa + 1e-10 < Ps_Pa || Tt0_K + 1e-10 < Ts_K
    error('sht:flightDataCommon:invalidRamState', ...
        '来流总压或总温低于对应静态量。');
end

atmosphere = struct();
atmosphere.model = 'ISA_troposphere_pressure_altitude';
atmosphere.altitudeDefinition = 'pressureAltitude';
atmosphere.pressureAltitude_m = altitude_m;
atmosphere.troposphereFormulaExtrapolated = ...
    altitude_m < c.minimumAltitude_m || altitude_m > c.maximumAltitude_m;
atmosphere.altitudeLimitPolicy = 'silentTroposphereFormulaExtrapolation';
atmosphere.mach = mach;
atmosphere.deltaT_K = deltaT_K;
atmosphere.Tisa_K = Tisa_K;
atmosphere.Ts_K = Ts_K;
atmosphere.Ps_Pa = Ps_Pa;
atmosphere.rho_kgpm3 = rho_kgpm3;
atmosphere.speedOfSound_mps = speedOfSound_mps;
atmosphere.trueAirspeed_mps = trueAirspeed_mps;
atmosphere.dynamicPressure_Pa = dynamicPressure_Pa;
atmosphere.ramTemperatureRatio = ramTemperatureRatio;
atmosphere.ramPressureRatio = ramPressureRatio;
atmosphere.Tt0_K = Tt0_K;
atmosphere.Pt0_Pa = Pt0_Pa;
atmosphere.pressureUsesIsaTemperature = true;
atmosphere.constants = c;
end

function c = local_constants()
% 1976 标准大气对流层常数；首轮只实现 0~11 km 单层关系。
c = struct();
c.seaLevelTemperature_K = 288.15;
c.seaLevelPressure_Pa = 101325;
c.temperatureLapseRate_Kpm = 0.0065;
c.gravity_mps2 = 9.80665;
c.gasConstant_JpkgK = 287.05287;
c.gamma = 1.4;
c.minimumAltitude_m = 0;
c.maximumAltitude_m = 11000;
c.altitudeLimitPolicy = 'silentTroposphereFormulaExtrapolation';
c.maximumMach = 1.0;
c.minimumStaticTemperature_K = 150;
end

function local_assert_finite_scalar(value, name)
if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
        ~isfinite(value)
    error('sht:flightDataCommon:badScalar', ...
        '%s 必须是有限实数标量。', name);
end
end
