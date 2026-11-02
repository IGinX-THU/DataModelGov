function [health, mapping] = sht_map_split_kurzke_health(groupedParameter, baseHealth)
%SHT_MAP_SPLIT_KURZKE_HEALTH 将首轮10维Kurzke参数映射到23个DLL局部通道。
%
% 首轮辨识仍采用工程上容易理解的10个总体方向：
%   1 K_Jg          高压轴转动惯量相对修正
%   2 K_Jp          动力轴转动惯量相对修正
%   3 K_tau_HPC     AC与CC金属热时间常数共同修正
%   4 K_tau_Burner  燃烧室衬套热时间常数修正
%   5 K_tau_GT      GT1与GT2金属热时间常数共同修正
%   6 K_tau_PT      PT1与PT2金属热时间常数共同修正
%   7 K_gapW_HPC    AC与CC间隙-流量交换率共同修正
%   8 K_gapEta_HPC  AC与CC间隙-效率交换率共同修正
%   9 K_gapEta_GT   GT1与GT2间隙-效率交换率共同修正
%  10 K_gapEta_PT   PT1与PT2间隙-效率交换率共同修正
%
% DLL局部通道固定为h89:h111。六个转盘时间常数修正h98:h103在首轮
% 固定为零，但保留在接口中供后续辨识。该函数是10维与23维之间的唯一
% 显式字典，入口程序不得自行复制下标。

if nargin < 2 || isempty(baseHealth)
    baseHealth = zeros(159,1);
end
if ~isnumeric(baseHealth) || numel(baseHealth) ~= 159 || ...
        any(~isfinite(baseHealth(:)))
    error('SHT:Kurzke27:BaseHealth', ...
        'baseHealth必须是h0:h158共159个有限数值。');
end

[p, groupedNames] = local_normalize_grouped_parameter(groupedParameter);
health = baseHealth(:);

% MATLAB下标比健康参数编号大1，例如h89对应health(90)。
health(90) = p(1);   % h89  K_Jg
health(91) = p(2);   % h90  K_Jp
health(92) = p(3);   % h91  AC thermal tau
health(93) = p(3);   % h92  CC thermal tau
health(94) = p(4);   % h93  Burner thermal tau
health(95) = p(5);   % h94  GT1 thermal tau
health(96) = p(5);   % h95  GT2 thermal tau
health(97) = p(6);   % h96  PT1 thermal tau
health(98) = p(6);   % h97  PT2 thermal tau
health(99:104) = 0;  % h98:h103，首轮转盘时间常数修正关闭
health(105) = p(7);  % h104 AC flow exchange
health(106) = p(8);  % h105 AC efficiency exchange
health(107) = p(7);  % h106 CC flow exchange
health(108) = p(8);  % h107 CC efficiency exchange
health(109) = p(9);  % h108 GT1 efficiency exchange
health(110) = p(9);  % h109 GT2 efficiency exchange
health(111) = p(10); % h110 PT1 efficiency exchange
health(112) = p(10); % h111 PT2 efficiency exchange

localNames = { ...
    'K_Jg','K_Jp', ...
    'K_tau_AC','K_tau_CC','K_tau_Burner', ...
    'K_tau_GT1','K_tau_GT2','K_tau_PT1','K_tau_PT2', ...
    'K_tauDisk_AC','K_tauDisk_CC','K_tauDisk_GT1', ...
    'K_tauDisk_GT2','K_tauDisk_PT1','K_tauDisk_PT2', ...
    'K_gapW_AC','K_gapEta_AC','K_gapW_CC','K_gapEta_CC', ...
    'K_gapEta_GT1','K_gapEta_GT2','K_gapEta_PT1','K_gapEta_PT2'};
mapping = struct();
mapping.version = 'split-kurzke27-health-map-v1';
mapping.groupedNames = groupedNames(:);
mapping.groupedValue = p;
mapping.localHealthNumber = (89:111).';
mapping.localMatlabIndex = (90:112).';
mapping.localNames = localNames(:);
mapping.localValue = health(90:112);
mapping.diskCorrectionFixedAtZero = true;
end

function [p, names] = local_normalize_grouped_parameter(value)
names = {'K_Jg','K_Jp','K_tau_HPC','K_tau_Burner', ...
    'K_tau_GT','K_tau_PT','K_gapW_HPC','K_gapEta_HPC', ...
    'K_gapEta_GT','K_gapEta_PT'};
if isstruct(value)
    p = zeros(10,1);
    for i = 1:10
        if ~isfield(value,names{i})
            error('SHT:Kurzke27:GroupedField', ...
                '首轮10维参数结构缺少字段%s。',names{i});
        end
        p(i) = value.(names{i});
    end
else
    p = value(:);
end
if ~isnumeric(p) || numel(p) ~= 10 || any(~isfinite(p))
    error('SHT:Kurzke27:GroupedParameter', ...
        '首轮Kurzke参数必须是10个有限数值或对应具名结构。');
end
end
