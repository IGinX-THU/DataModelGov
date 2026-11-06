function boundary = sht_flight_boundary_step(time_s, Np_rpm, missionCfg, flightCfg)
%SHT_FLIGHT_BOUNDARY_STEP 计算当前采样点的飞行环境、装机边界和旋翼负载。
%
% boundary = sht_flight_boundary_step(time_s, Np_rpm, missionCfg, flightCfg)
%
% 本函数是第 3.1 阶段 S4 的单点边界调度器。它只做代数计算，不保存
% 状态、不调用发动机 DLL，也不修改输入配置。调用者应在每个发动机采样
% 点给出当前动力涡轮转速 Np_rpm；旋翼负载由当前 Np 而不是 Np 指令计算：
%
%   Npr   = Np / Np_design
%   Qload = Q_design * k_theta * Npr^2
%   Pload = Qload * Np * pi / 30
%
% 第二轮正式装机边界定义为：
%
%   Pt1  = [1-(1-sigma_in)-(1-sigma_dist)] * Pt0
%   Tt1  = Tt0 + deltaT_in
%   Pamb = Ps
%   Pback = Ps + deltaP_exhaust
%
% 其中基准安装损失和任务等效畸变损失按损失系数相加；Pamb 是环境静压，
% Pback 是喷管实际承受的独立外界背压。未配置
% rotorLoadModel/exhaustBackPressure 时仍严格执行历史聚合旋翼负载分支。

if nargin ~= 4 || ~isstruct(missionCfg) || ~isscalar(missionCfg) || ...
        ~isstruct(flightCfg) || ~isscalar(flightCfg)
    error('sht:flightBoundaryStep:badInput', ...
        '必须给出 time_s、Np_rpm、标量 missionCfg 和标量 flightCfg。');
end
local_assert_finite_scalar(time_s, 'time_s');
local_assert_positive_scalar(Np_rpm, 'Np_rpm');

missionRequired = {'missionId','duration_s','nodeTime_s', ...
    'thetaNode_deg','nodeSigmaDist','sigmaIn','altitude_m','mach', ...
    'deltaT_K','deltaTIn_K','segmentId'};
flightRequired = {'designNpRpm','designTorqueNm','hpsPower_W', ...
    'deltaPExhaust_Pa','installedBoundaryEnabled', ...
    'collectivePitchMapping'};
local_require_fields(missionCfg, missionRequired, 'missionCfg');
local_require_fields(flightCfg, flightRequired, 'flightCfg');

duration_s = missionCfg.duration_s;
local_assert_positive_scalar(duration_s, 'missionCfg.duration_s');
tolerance = 100 * eps(max(1, duration_s));
if time_s < -tolerance || time_s > duration_s + tolerance
    error('sht:flightBoundaryStep:timeOutsideMission', ...
        'time_s=%.12g 超出任务时间范围 [0, %.12g] s；禁止外推。', ...
        time_s, duration_s);
end
time_s = min(max(time_s, 0), duration_s);

nodeTime_s = local_row_vector(missionCfg.nodeTime_s, ...
    'missionCfg.nodeTime_s');
thetaNode_deg = local_row_vector(missionCfg.thetaNode_deg, ...
    'missionCfg.thetaNode_deg');
sigmaDistNode = local_row_vector(missionCfg.nodeSigmaDist, ...
    'missionCfg.nodeSigmaDist');
nodeCount = numel(nodeTime_s);
if nodeCount < 2 || numel(thetaNode_deg) ~= nodeCount || ...
        numel(sigmaDistNode) ~= nodeCount || ...
        abs(nodeTime_s(1)) > tolerance || ...
        abs(nodeTime_s(end) - duration_s) > tolerance || ...
        any(diff(nodeTime_s) <= 0)
    error('sht:flightBoundaryStep:badMissionNodes', ...
        '时间、总距角和畸变节点必须等长，且时间节点严格覆盖任务范围。');
end
if any(sigmaDistNode <= 0) || any(sigmaDistNode > 1)
    error('sht:flightBoundaryStep:badSigmaDist', ...
        'nodeSigmaDist 必须位于 (0,1]。');
end

% 运行配置会把 0.025 s 重新表示为最接近的双精度公约数，长时间累加后
% 名义整数节点可能略偏小数皮秒。若不处理，节点处单个日志样本会被误标
% 为前一任务段。这里只在远小于采样周期的数值容差内吸附到最近节点，
% 不允许把真实的非节点采样点移动到另一任务段。
nodeSnapTolerance = max(1e-10, 1000 * eps(max(1, duration_s)));
[distanceToNode, nearestNodeIndex] = min(abs(time_s - nodeTime_s));
if distanceToNode <= nodeSnapTolerance
    time_s = nodeTime_s(nearestNodeIndex);
end

% 第二轮长航线允许采用分段半余弦插值。每段两端的变化率均为零，
% 可避免理想折线在任务节点处引入不必要的指令斜率突变。未配置该字段
% 时仍严格使用历史 linear 行为。
interpolationMethod = local_interpolation_method(missionCfg);
segmentIndex = find(time_s < nodeTime_s(2:end) - tolerance, 1, 'first');
if isempty(segmentIndex)
    segmentIndex = nodeCount - 1;
end

altitude_m = local_schedule_value(missionCfg.altitude_m, nodeTime_s, ...
    time_s, 'missionCfg.altitude_m', interpolationMethod, segmentIndex);
mach = local_schedule_value(missionCfg.mach, nodeTime_s, ...
    time_s, 'missionCfg.mach', interpolationMethod, segmentIndex);
deltaT_K = local_schedule_value(missionCfg.deltaT_K, nodeTime_s, ...
    time_s, 'missionCfg.deltaT_K', interpolationMethod, segmentIndex);
deltaTIn_K = local_schedule_value(missionCfg.deltaTIn_K, nodeTime_s, ...
    time_s, 'missionCfg.deltaTIn_K', interpolationMethod, segmentIndex);

theta_deg = local_schedule_value(thetaNode_deg, nodeTime_s, time_s, ...
    'missionCfg.thetaNode_deg', interpolationMethod, segmentIndex);
configuredSigmaDist = local_schedule_value(sigmaDistNode, nodeTime_s, ...
    time_s, 'missionCfg.nodeSigmaDist', interpolationMethod, segmentIndex);
[kTheta, pitchDiagnostic] = sht_collective_pitch_mapping(theta_deg, ...
    'thetaToKTheta', flightCfg.collectivePitchMapping);
if ~pitchDiagnostic.thetaWithinValidRange
    error('sht:flightBoundaryStep:thetaOutsideValidRange', ...
        'time=%.12g s 时 theta=%.12g deg 超出首轮工程有效范围。', ...
        time_s, theta_deg);
end

splitRotorEnabled = isfield(flightCfg,'rotorLoadModel') && ...
    isstruct(flightCfg.rotorLoadModel) && ...
    isfield(flightCfg.rotorLoadModel,'enabled') && ...
    local_logical_scalar(flightCfg.rotorLoadModel.enabled, ...
    'flightCfg.rotorLoadModel.enabled');
thetaTail_deg = NaN;
tailPitchWithinValidRange = true;
if splitRotorEnabled
    if ~isfield(missionCfg,'tailPitchNode_deg')
        error('sht:flightBoundaryStep:missingTailPitch', ...
            '主/尾旋翼分支启用时任务必须提供tailPitchNode_deg。');
    end
    thetaTail_deg = local_schedule_value(missionCfg.tailPitchNode_deg, ...
        nodeTime_s,time_s,'missionCfg.tailPitchNode_deg', ...
        interpolationMethod,segmentIndex);
end

installedBoundaryEnabled = local_logical_scalar( ...
    flightCfg.installedBoundaryEnabled, ...
    'flightCfg.installedBoundaryEnabled');
local_assert_recovery(missionCfg.sigmaIn, 'missionCfg.sigmaIn');
if installedBoundaryEnabled
    sigmaIn = missionCfg.sigmaIn;
    sigmaDist = configuredSigmaDist;
else
    sigmaIn = 1;
    sigmaDist = 1;
end

atmosphere = sht_flight_data_common( ...
    'flightAtmosphere', altitude_m, mach, deltaT_K);
% 基准装机压损与等效畸变压损按损失系数相加，避免与
% C端Inlet部件的Pt1->Pt2压损混合。sigmaIn=1-K_install，
% sigmaDist=1-K_dist，因此总恢复系数为1-K_install-K_dist。
totalPressureRecovery = 1 - (1-sigmaIn) - (1-sigmaDist);
local_assert_recovery(totalPressureRecovery, ...
    'combined inlet total-pressure recovery');
Pt1_Pa = totalPressureRecovery * atmosphere.Pt0_Pa;
Tt1_K = atmosphere.Tt0_K + deltaTIn_K;

local_assert_positive_scalar(flightCfg.designNpRpm, ...
    'flightCfg.designNpRpm');
local_assert_positive_scalar(flightCfg.designTorqueNm, ...
    'flightCfg.designTorqueNm');
local_assert_nonnegative_scalar(flightCfg.hpsPower_W, ...
    'flightCfg.hpsPower_W');
Npr = Np_rpm / flightCfg.designNpRpm;
omega_radps = Np_rpm*pi/30;
mainRotorPower_W = NaN;
tailRotorPower_W = NaN;
tailLoadFactor = NaN;
if splitRotorEnabled
    rotor = flightCfg.rotorLoadModel;
    rotorRequired = {'mainDesignPower_W','tailDesignPower_W', ...
        'totalDesignPower_W','tailZeroPitch_deg','tailDesignPitch_deg', ...
        'tailPitchValidRange_deg','tailProfilePowerFraction', ...
        'designDensity_kgpm3'};
    local_require_fields(rotor,rotorRequired,'flightCfg.rotorLoadModel');
    local_assert_positive_scalar(rotor.mainDesignPower_W, ...
        'rotorLoadModel.mainDesignPower_W');
    local_assert_positive_scalar(rotor.tailDesignPower_W, ...
        'rotorLoadModel.tailDesignPower_W');
    local_assert_positive_scalar(rotor.totalDesignPower_W, ...
        'rotorLoadModel.totalDesignPower_W');
    local_assert_positive_scalar(rotor.designDensity_kgpm3, ...
        'rotorLoadModel.designDensity_kgpm3');
    local_assert_finite_scalar(rotor.tailZeroPitch_deg, ...
        'rotorLoadModel.tailZeroPitch_deg');
    local_assert_finite_scalar(rotor.tailDesignPitch_deg, ...
        'rotorLoadModel.tailDesignPitch_deg');
    if rotor.tailDesignPitch_deg == rotor.tailZeroPitch_deg || ...
            ~isnumeric(rotor.tailPitchValidRange_deg) || ...
            numel(rotor.tailPitchValidRange_deg)~=2 || ...
            any(~isfinite(rotor.tailPitchValidRange_deg)) || ...
            rotor.tailPitchValidRange_deg(1) >= rotor.tailPitchValidRange_deg(2)
        error('sht:flightBoundaryStep:tailRotorConfiguration', ...
            '尾桨总距参考或有效范围配置无效。');
    end
    if ~isscalar(rotor.tailProfilePowerFraction) || ...
            ~isfinite(rotor.tailProfilePowerFraction) || ...
            rotor.tailProfilePowerFraction<0 || ...
            rotor.tailProfilePowerFraction>1
        error('sht:flightBoundaryStep:tailProfilePowerFraction', ...
            'tailProfilePowerFraction必须位于[0,1]。');
    end
    tailPitchWithinValidRange = thetaTail_deg >= ...
        rotor.tailPitchValidRange_deg(1) && thetaTail_deg <= ...
        rotor.tailPitchValidRange_deg(2);
    if ~tailPitchWithinValidRange
        error('sht:flightBoundaryStep:tailPitchOutsideValidRange', ...
            'time=%.12g s时尾桨总距%.12g deg超出工程有效范围。', ...
            time_s,thetaTail_deg);
    end
    xiTail = (thetaTail_deg-rotor.tailZeroPitch_deg) / ...
        (rotor.tailDesignPitch_deg-rotor.tailZeroPitch_deg);
    tailLoadFactor = rotor.tailProfilePowerFraction + ...
        (1-rotor.tailProfilePowerFraction)*abs(xiTail)^1.5;
    mainRotorPower_W = rotor.mainDesignPower_W*kTheta*Npr^3;
    tailRotorPower_W = rotor.tailDesignPower_W * ...
        (atmosphere.rho_kgpm3/rotor.designDensity_kgpm3) * ...
        Npr^3*tailLoadFactor;
    Pload_W = mainRotorPower_W+tailRotorPower_W;
    Qload_Nm = Pload_W/omega_radps;
else
    % 历史分支必须保持原运算顺序，以支持旧飞行任务精确回归。
    Qload_Nm = flightCfg.designTorqueNm*kTheta*Npr^2;
    Pload_W = Qload_Nm*omega_radps;
end

local_assert_finite_scalar(flightCfg.deltaPExhaust_Pa, ...
    'flightCfg.deltaPExhaust_Pa');
Pamb_Pa = atmosphere.Ps_Pa;
Pback_Pa = NaN;
deltaPExhaust_Pa = flightCfg.deltaPExhaust_Pa;
exhaustBackPressureEnabled = false;
if isfield(flightCfg,'exhaustBackPressure') && ...
        isstruct(flightCfg.exhaustBackPressure) && ...
        isfield(flightCfg.exhaustBackPressure,'enabled') && ...
        local_logical_scalar(flightCfg.exhaustBackPressure.enabled, ...
        'flightCfg.exhaustBackPressure.enabled')
    exhaust = flightCfg.exhaustBackPressure;
    local_require_fields(exhaust,{'designRise_Pa','designPower_W'}, ...
        'flightCfg.exhaustBackPressure');
    local_assert_nonnegative_scalar(exhaust.designRise_Pa, ...
        'exhaustBackPressure.designRise_Pa');
    local_assert_positive_scalar(exhaust.designPower_W, ...
        'exhaustBackPressure.designPower_W');
    % 固定几何排气装置的首轮压损按流量平方变化；缺少排气流量测量时，
    % 用归一化轴端功率作为单调代理，并在设计功率处严格锚定。
    Pback_Pa=sht_exhaust_backpressure(atmosphere.Ps_Pa,Pload_W,exhaust);
    deltaPExhaust_Pa=Pback_Pa-atmosphere.Ps_Pa;
    exhaustBackPressureEnabled = true;
else
    % 兼容旧接口：历史非零值仍通过修改Pamb表达，正式第二轮不走此分支。
    Pamb_Pa = atmosphere.Ps_Pa+flightCfg.deltaPExhaust_Pa;
end
if Pt1_Pa<=0 || Tt1_K<=0 || Pamb_Pa<=0 || ...
        (exhaustBackPressureEnabled && Pback_Pa<=0)
    error('sht:flightBoundaryStep:nonpositiveBoundary', ...
        'Pt1、Tt1、Pamb和启用时的Pback必须均为正数。');
end

if ~iscell(missionCfg.segmentId) || ...
        numel(missionCfg.segmentId) ~= nodeCount - 1
    error('sht:flightBoundaryStep:badSegmentIds', ...
        'segmentId 必须是长度为节点数减一的元胞数组。');
end
segmentId = missionCfg.segmentId{segmentIndex};
if isstring(segmentId) && isscalar(segmentId)
    segmentId = char(segmentId);
end
if ~ischar(segmentId) || size(segmentId, 1) ~= 1
    error('sht:flightBoundaryStep:badSegmentId', ...
        'segmentId 中的每个元素必须是字符行向量或标量字符串。');
end

numericValues = [altitude_m, mach, deltaT_K, deltaTIn_K, theta_deg, ...
    kTheta, sigmaIn, sigmaDist, Pt1_Pa, Tt1_K, Pamb_Pa, Npr, ...
    Qload_Nm, Pload_W,deltaPExhaust_Pa];
if any(~isfinite(numericValues))
    error('sht:flightBoundaryStep:nonfiniteResult', ...
        '当前采样点的边界或负载计算产生非有限值。');
end

boundary = struct();
boundary.missionId = missionCfg.missionId;
boundary.segmentId = segmentId;
boundary.segmentIndex = segmentIndex;
boundary.time_s = time_s;
boundary.altitude_m = altitude_m;
boundary.mach = mach;
boundary.deltaT_K = deltaT_K;
boundary.troposphereFormulaExtrapolated = ...
    atmosphere.troposphereFormulaExtrapolated;
boundary.altitudeLimitPolicy = atmosphere.altitudeLimitPolicy;
boundary.Tisa_K = atmosphere.Tisa_K;
boundary.Ts_K = atmosphere.Ts_K;
boundary.Ps_Pa = atmosphere.Ps_Pa;
boundary.rho_kgpm3 = atmosphere.rho_kgpm3;
boundary.speedOfSound_mps = atmosphere.speedOfSound_mps;
boundary.trueAirspeed_mps = atmosphere.trueAirspeed_mps;
boundary.dynamicPressure_Pa = atmosphere.dynamicPressure_Pa;
boundary.ramTemperatureRatio = atmosphere.ramTemperatureRatio;
boundary.ramPressureRatio = atmosphere.ramPressureRatio;
boundary.Pt0_Pa = atmosphere.Pt0_Pa;
boundary.Tt0_K = atmosphere.Tt0_K;
boundary.sigmaIn = sigmaIn;
boundary.sigmaDist = sigmaDist;
boundary.totalPressureRecovery = totalPressureRecovery;
boundary.deltaTIn_K = deltaTIn_K;
boundary.Pt1_Pa = Pt1_Pa;
boundary.Tt1_K = Tt1_K;
boundary.deltaPExhaust_Pa = deltaPExhaust_Pa;
boundary.Pamb_Pa = Pamb_Pa;
boundary.exhaustBackPressureEnabled = exhaustBackPressureEnabled;
if exhaustBackPressureEnabled
    boundary.Pback_Pa = Pback_Pa;
end
boundary.theta_deg = theta_deg;
boundary.kTheta = kTheta;
boundary.thetaWithinValidRange = ...
    pitchDiagnostic.thetaWithinValidRange;
boundary.Np_rpm = Np_rpm;
boundary.Npr = Npr;
boundary.Qload_Nm = Qload_Nm;
boundary.Pload_W = Pload_W;
boundary.splitRotorLoadEnabled = splitRotorEnabled;
boundary.thetaTail_deg = thetaTail_deg;
boundary.tailPitchWithinValidRange = tailPitchWithinValidRange;
boundary.tailLoadFactor = tailLoadFactor;
boundary.mainRotorPower_W = mainRotorPower_W;
boundary.tailRotorPower_W = tailRotorPower_W;
boundary.hpsPower_W = flightCfg.hpsPower_W;
boundary.installedBoundaryEnabled = installedBoundaryEnabled;
boundary.externalSecondaryAirEnabled = false;
end

function value = local_schedule_value( ...
        configuredValue, nodeTime_s, time_s, name, method, segmentIndex)
% 允许常值，也允许与任务节点等长的分段调度。
if ~isnumeric(configuredValue) || ~isreal(configuredValue) || ...
        isempty(configuredValue) || any(~isfinite(configuredValue(:)))
    error('sht:flightBoundaryStep:badScheduledValue', ...
        '%s 必须是有限实数标量或与任务节点等长的向量。', name);
end
if isscalar(configuredValue)
    value = configuredValue;
elseif isvector(configuredValue) && numel(configuredValue) == numel(nodeTime_s)
    values = configuredValue(:).';
    switch method
        case {'linear','previous'}
            value = interp1(nodeTime_s, values, time_s, method);
        case 'halfcosine'
            t0 = nodeTime_s(segmentIndex);
            t1 = nodeTime_s(segmentIndex + 1);
            u = min(max((time_s - t0) / (t1 - t0), 0), 1);
            blend = 0.5 - 0.5 * cos(pi * u);
            value = values(segmentIndex) + ...
                (values(segmentIndex + 1) - values(segmentIndex)) * blend;
        otherwise
            error('sht:flightBoundaryStep:internalInterpolationMethod', ...
                '未处理的任务插值方法 %s。', method);
    end
else
    error('sht:flightBoundaryStep:badScheduledValueLength', ...
        '%s 必须是标量或长度为 %d 的向量。', name, numel(nodeTime_s));
end
end

function method = local_interpolation_method(missionCfg)
method = 'linear';
if isfield(missionCfg, 'interpolationMethod') && ...
        ~isempty(missionCfg.interpolationMethod)
    method = missionCfg.interpolationMethod;
end
if isstring(method) && isscalar(method)
    method = char(method);
end
if ~ischar(method) || size(method, 1) ~= 1
    error('sht:flightBoundaryStep:badInterpolationMethod', ...
        'missionCfg.interpolationMethod 必须为字符向量或标量字符串。');
end
method = lower(strtrim(method));
if ~ismember(method, {'linear','previous','halfcosine'})
    error('sht:flightBoundaryStep:badInterpolationMethod', ...
        '任务插值方法必须为 linear、previous 或 halfCosine。');
end
end

function row = local_row_vector(value, name)
if ~isnumeric(value) || ~isreal(value) || ~isvector(value) || ...
        isempty(value) || any(~isfinite(value(:)))
    error('sht:flightBoundaryStep:badVector', ...
        '%s 必须是非空有限实数向量。', name);
end
row = value(:).';
end

function local_require_fields(value, required, name)
for i = 1:numel(required)
    if ~isfield(value, required{i})
        error('sht:flightBoundaryStep:missingField', ...
            '%s 缺少字段 %s。', name, required{i});
    end
end
end

function value = local_logical_scalar(value, name)
if ~(islogical(value) || isnumeric(value)) || ~isscalar(value) || ...
        ~isfinite(value)
    error('sht:flightBoundaryStep:badLogical', ...
        '%s 必须是有限标量逻辑开关。', name);
end
value = logical(value);
end

function local_assert_recovery(value, name)
if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
        ~isfinite(value) || value <= 0 || value > 1
    error('sht:flightBoundaryStep:badRecovery', ...
        '%s 必须位于 (0,1]。', name);
end
end

function local_assert_positive_scalar(value, name)
if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
        ~isfinite(value) || value <= 0
    error('sht:flightBoundaryStep:badPositiveScalar', ...
        '%s 必须是有限正标量。', name);
end
end

function local_assert_nonnegative_scalar(value, name)
if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
        ~isfinite(value) || value < 0
    error('sht:flightBoundaryStep:badNonnegativeScalar', ...
        '%s 必须是有限非负标量。', name);
end
end

function local_assert_finite_scalar(value, name)
if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
        ~isfinite(value)
    error('sht:flightBoundaryStep:badFiniteScalar', ...
        '%s 必须是有限实数标量。', name);
end
end
