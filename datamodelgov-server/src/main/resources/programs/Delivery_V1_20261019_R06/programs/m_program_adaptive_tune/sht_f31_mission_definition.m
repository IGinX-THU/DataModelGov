function mission = sht_f31_mission_definition(missionId, sampleTime_s)
%SHT_F31_MISSION_DEFINITION 定义3.1第二轮训练和独立测试飞行任务。
%
% mission = sht_f31_mission_definition(missionId, sampleTime_s)
%
% 两条任务都以40 Hz连续时间历程表示，但训练集和测试集按完整任务隔离，
% 不从相邻样本中随机切分。任务节点之间采用分段半余弦过渡，使高度、
% 马赫数和总距角在每段边界处连续且一阶导数为零。

if nargin < 2 || isempty(sampleTime_s)
    sampleTime_s = 0.025;
end
% 外部调用方只提供单架次节点定义；插值、标签和时间网格仍由本函数生成。
if isstruct(missionId)
    mission=local_finalize(missionId,sampleTime_s);
    return;
end
if isstring(missionId) && isscalar(missionId)
    missionId = char(missionId);
end
if ~ischar(missionId) || size(missionId, 1) ~= 1
    error('SHT:F31Mission:MissionId', ...
        'missionId必须为字符向量或标量字符串。');
end
if ~isscalar(sampleTime_s) || ~isfinite(sampleTime_s) || sampleTime_s <= 0
    error('SHT:F31Mission:SampleTime', 'sampleTime_s必须为有限正标量。');
end

switch upper(strtrim(missionId))
    case 'F31-CAL-01'
        definition = local_calibration_definition();
    case 'F31-VA-01'
        definition = local_validation_definition();
    otherwise
        error('SHT:F31Mission:UnknownMission', ...
            '未知3.1任务%s；仅支持F31-CAL-01和F31-VA-01。', missionId);
end

mission = local_finalize(definition, sampleTime_s);
end

function d = local_calibration_definition()
d = struct();
d.missionId = 'F31-CAL-01';
d.datasetRole = 'identification';
d.displayName = '3.1 typical flight identification mission';
d.nodeTime_s = [0,60,110,180,300,360,510,560,620,670,790,930, ...
    985,1040,1100,1160,1200];
d.altitudeNode_m = [100,100,120,250,900,1000,1000,1100,1100, ...
    1000,1000,400,220,130,130,100,100];
d.machNode = [0,0,0.02,0.06,0.14,0.16,0.16,0.14,0.14,0.18, ...
    0.18,0.10,0.05,0.02,0,0,0];
d.thetaNode_deg = [6.5,6.5,10.5,10.5,10.8,9.2,9.2,10.8,10.8, ...
    8.4,8.4,7.7,7.2,9.6,10.5,6.5,6.5];
d.tailPitchNode_deg = [6.8,6.8,9.5,9.8,9.3,8.5,8.5,10.0,10.0, ...
    7.8,7.8,7.3,6.8,8.8,9.5,6.8,6.8];
d.K_dist_eq = 0.006;
d.segmentId = { ...
    'F31C_01_initial_ground', ...
    'F31C_02_vertical_takeoff', ...
    'F31C_03_hover_to_climb', ...
    'F31C_04_climb_acceleration', ...
    'F31C_05_cruise_establishment', ...
    'F31C_06_cruise_A', ...
    'F31C_07_normal_load_increase', ...
    'F31C_08_high_load_hold', ...
    'F31C_09_unload_acceleration', ...
    'F31C_10_cruise_B', ...
    'F31C_11_descent', ...
    'F31C_12_initial_approach', ...
    'F31C_13_decelerating_approach', ...
    'F31C_14_hover', ...
    'F31C_15_landing', ...
    'F31C_16_final_ground'};
d.segmentType = { ...
    'ground_hold','takeoff_transition','climb_transition', ...
    'climb_transition','cruise_transition','cruise_hold', ...
    'load_transition','high_load_hold','load_transition', ...
    'cruise_hold','descent_transition','approach_transition', ...
    'approach_transition','hover_hold','landing_transition','ground_hold'};
end

function d = local_validation_definition()
d = struct();
d.missionId = 'F31-VA-01';
d.datasetRole = 'independent_validation';
d.displayName = '3.1 typical flight independent validation mission';
d.nodeTime_s = [0,45,90,180,230,320,360,400,485,535,570,600];
d.altitudeNode_m = [100,100,130,650,700,700,760,700,300,130,100,100];
d.machNode = [0,0,0.025,0.12,0.145,0.145,0.12,0.155,0.075, ...
    0.02,0,0];
d.thetaNode_deg = [6.8,6.8,10.2,10.6,9.4,9.4,10.4,8.7,7.8, ...
    9.5,7.0,7.0];
d.tailPitchNode_deg = [7.0,7.0,9.2,9.6,8.7,8.7,9.7,8.0,7.4, ...
    8.7,7.1,7.1];
d.K_dist_eq = 0.004;
d.segmentId = { ...
    'F31V_01_initial_ground', ...
    'F31V_02_takeoff', ...
    'F31V_03_climb', ...
    'F31V_04_cruise_establishment', ...
    'F31V_05_cruise', ...
    'F31V_06_moderate_load_increase', ...
    'F31V_07_load_recovery', ...
    'F31V_08_descent', ...
    'F31V_09_approach', ...
    'F31V_10_hover_landing', ...
    'F31V_11_final_ground'};
d.segmentType = { ...
    'ground_hold','takeoff_transition','climb_transition', ...
    'cruise_transition','cruise_hold','load_transition', ...
    'load_transition','descent_transition','approach_transition', ...
    'landing_transition','ground_hold'};
end

function mission = local_finalize(d, sampleTime_s)
nodeTime = d.nodeTime_s(:);
altitudeNode = d.altitudeNode_m(:);
machNode = d.machNode(:);
thetaNode = d.thetaNode_deg(:);
tailPitchNode = d.tailPitchNode_deg(:);
nodeCount = numel(nodeTime);
if nodeCount < 2 || any(diff(nodeTime) <= 0) || ...
        any([numel(altitudeNode),numel(machNode),numel(thetaNode), ...
        numel(tailPitchNode)] ~= nodeCount)
    error('SHT:F31Mission:Definition', '任务节点定义无效。');
end
if numel(d.segmentId) ~= nodeCount - 1 || ...
        numel(d.segmentType) ~= nodeCount - 1
    error('SHT:F31Mission:SegmentDefinition', ...
        '任务分段标签数量必须等于节点数减一。');
end
duration_s = nodeTime(end);
sampleCount = round(duration_s / sampleTime_s) + 1;
time_s = (0:(sampleCount - 1)).' * sampleTime_s;
if abs(time_s(end) - duration_s) > 1e-10
    error('SHT:F31Mission:TimeGrid', ...
        '任务时长%.12g s不能被采样周期%.12g s整除。',duration_s,sampleTime_s);
end

[altitude_m,segmentIndex] = local_half_cosine_schedule( ...
    time_s,nodeTime,altitudeNode);
mach = local_half_cosine_schedule(time_s,nodeTime,machNode);
theta_cmd_deg = local_half_cosine_schedule(time_s,nodeTime,thetaNode);
tail_pitch_cmd_deg = local_half_cosine_schedule( ...
    time_s,nodeTime,tailPitchNode);
segment_id = d.segmentId(segmentIndex).';
segment_type = d.segmentType(segmentIndex).';
segment_id = segment_id(:);
segment_type = segment_type(:);

holdMask = contains(segment_type,'hold');
steady_eligible = false(sampleCount,1);
for i = 1:(nodeCount - 1)
    if contains(d.segmentType{i},'hold')
        % 每个保持段两端保留3 s保护区，避免过渡尾迹被标成稳态。
        steady_eligible = steady_eligible | ...
            (time_s >= nodeTime(i) + 3 & time_s <= nodeTime(i + 1) - 3);
    end
end
slow_transition_eligible = contains(segment_type, ...
    {'climb_transition','cruise_transition','descent_transition'});
transient_eligible = ~holdMask;

segment = table((1:(nodeCount - 1)).',nodeTime(1:end-1),nodeTime(2:end), ...
    d.segmentId(:),d.segmentType(:),altitudeNode(1:end-1), ...
    altitudeNode(2:end),machNode(1:end-1),machNode(2:end), ...
    thetaNode(1:end-1),thetaNode(2:end), ...
    tailPitchNode(1:end-1),tailPitchNode(2:end), ...
    'VariableNames',{'index','start_s','end_s','segment_id','segment_type', ...
    'altitude_start_m','altitude_end_m','mach_start','mach_end', ...
    'theta_start_deg','theta_end_deg', ...
    'tail_pitch_start_deg','tail_pitch_end_deg'});

mission = struct();
mission.schemaVersion = 'F31_MISSION_V2';
mission.missionId = d.missionId;
mission.datasetRole = d.datasetRole;
mission.displayName = d.displayName;
mission.sampleTime_s = sampleTime_s;
mission.sampleRate_Hz = 1 / sampleTime_s;
mission.duration_s = duration_s;
mission.sampleCount = sampleCount;
mission.segmentCount = nodeCount - 1;
mission.interpolationMethod = 'halfCosine';
mission.time_s = time_s;
mission.nodeTime_s = nodeTime.';
mission.altitudeNode_m = altitudeNode.';
mission.machNode = machNode.';
mission.thetaNode_deg = thetaNode.';
mission.tailPitchNode_deg = tailPitchNode.';
mission.K_dist_eq = d.K_dist_eq;
mission.altitude_m = altitude_m;
mission.mach = mach;
mission.theta_cmd_deg = theta_cmd_deg;
mission.tail_pitch_cmd_deg = tail_pitch_cmd_deg;
mission.Npr_ref = ones(sampleCount,1);
mission.deltaT_K = 10 * ones(sampleCount,1);
mission.segment_id = segment_id;
mission.segment_type = segment_type;
mission.steady_eligible = steady_eligible;
mission.slow_transition_eligible = slow_transition_eligible;
mission.transient_eligible = transient_eligible;
mission.segment = segment;
if isfield(d,'initialThermalCheckMode')
    mission.initialThermalCheckMode=d.initialThermalCheckMode;
end
end

function [value,segmentIndex] = local_half_cosine_schedule(time,nodeTime,nodeValue)
segmentIndex = discretize(time,[-Inf;nodeTime(2:end-1);Inf]);
segmentIndex = min(max(segmentIndex,1),numel(nodeTime)-1);
t0 = nodeTime(segmentIndex);
t1 = nodeTime(segmentIndex + 1);
v0 = nodeValue(segmentIndex);
v1 = nodeValue(segmentIndex + 1);
u = min(max((time - t0) ./ (t1 - t0),0),1);
blend = 0.5 - 0.5*cos(pi*u);
value = v0 + (v1 - v0).*blend;
end
