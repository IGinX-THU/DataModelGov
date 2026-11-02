function points = sht_tc24_operating_points(role)
%SHT_TC24_OPERATING_POINTS TC24三部件稳态训练/测试工况的唯一配置表。
%
% 本函数只定义已经确认的目标转速和轴输出功率，不生成试车测量数据。
% STEP02/STEP03使用训练点建立零修正稳态锚点与真值调度坐标；测试点
% 留给后续STEP04及以后作独立预测验证。

if nargin < 1 || isempty(role)
    role = 'all';
end
role = lower(char(role));
assert(ismember(role, {'all','train','test'}), ...
    'role必须为all、train或test。');

designNpRpm = 20900;
designPowerKw = 2176.6;

id = ["TR01";"TR02";"TR03";"TR04";"TR05";"TR06"; ...
    "TR07";"TR08";"TR09";"TR10";"TR11";"TR12"; ...
    "TE01";"TE02";"TE03";"TE04"];
setName = [repmat("train",12,1); repmat("test",4,1)];
npRpm = [20900;20900;20900;20900;20900;20900; ...
    18810;18810;16720;16720;14630;14000; ...
    20900;19855;17765;15675];
powerKw = [2176.6;2020;1890;1756;1317;878; ...
    1317;878;878;659;439;125; ...
    1600;1450;1000;550];
loadConnected = [true(11,1); false; true(4,1)];
source = [repmat("用户给定",6,1); repmat("工程试配",5,1); ...
    "用户给定"; repmat("独立测试设计",4,1)];
representative = repmat("",16,1);
representative(1) = "high";
representative(9) = "medium";
representative(12) = "low";

npRatio = npRpm ./ designNpRpm;
powerRatio = powerKw ./ designPowerKw;
thetaDeg = nan(size(powerKw));
for i = 1:numel(powerKw)
    if loadConnected(i)
        kTheta = powerRatio(i) / npRatio(i)^3;
        normalizedPitch = (kTheta - 0.15) / 0.85;
        assert(normalizedPitch >= 0 && normalizedPitch <= 1 + 1e-12, ...
            '%s目标功率超出当前总距角负载映射范围。', id(i));
        thetaDeg(i) = 12 * max(normalizedPitch, 0)^(2/3);
    end
end
torqueNm = powerKw * 1000 ./ (pi .* npRpm / 30);
loadMode = repmat("collective_pitch",16,1);
loadMode(~loadConnected) = "constant_torque";

points = table(id,setName,npRatio,npRpm,powerKw,powerRatio,thetaDeg, ...
    torqueNm,loadConnected,loadMode,source,representative, ...
    'VariableNames', {'point_id','set_name','Np_ratio','Np_rpm', ...
    'load_power_kW','load_power_ratio','theta_deg','target_torque_Nm', ...
    'load_connected','load_mode','source','representative_level'});

switch role
    case 'train'
        points = points(points.set_name == "train",:);
    case 'test'
        points = points(points.set_name == "test",:);
end
end
