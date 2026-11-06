function seed = sht_get_steady_trim_initial_guess( ...
        cfg, targetNpRpm, loadPowerW, requestedId)
%SHT_GET_STEADY_TRIM_INITIAL_GUESS 获取可复用的六部件稳态配平初值。
%
% seed = sht_get_steady_trim_initial_guess(cfg, targetNpRpm, loadPowerW)
%   根据目标转速和负载功率自动选择初值。当前初值库包含：
%   1) 六部件设计点初值：从 RunModelSHT_V2_design_state.mat 读取；
%   2) 地面慢车126 kW固化初值：用于当前七点稳态试车方案；
%   3) 历史1%设计功率固化初值：保留给极低负载边界测试。
%
% seed = sht_get_steady_trim_initial_guess(..., requestedId)
%   显式选择 'auto'、'six_component_design' 或
%   'six_component_ground_idle_npr70_power126kw' 或
%   'six_component_ground_idle_npr70_power01'。
%
% 返回的 varIte 是 DLL_SHT_varIteInit 所需的9维共同工作变量；Wf 是
% 外层转速配平使用的燃油初值；z=[varIte;Wf] 是10维外层配平初值。
% 固化初值只负责选择数值分支，不能替代调用后的DLL收敛和残差检查。

if nargin < 3 || nargin > 4
    error('SHT:SteadySeed:BadInputCount', ...
        '需要输入 cfg、targetNpRpm、loadPowerW，以及可选的 requestedId。');
end
if nargin < 4 || isempty(requestedId)
    requestedId = 'auto';
end
local_validate_input(cfg, targetNpRpm, loadPowerW, requestedId);

targetNpRatio = targetNpRpm / cfg.engine.initial.Np0;
targetPowerRatio = loadPowerW / cfg.engine.initial.power0;
groundIdle126kW = local_ground_idle_126kw_anchor( ...
    cfg, targetNpRatio, targetPowerRatio);
groundIdlePower01 = local_ground_idle_power01_anchor( ...
    cfg, targetNpRatio, targetPowerRatio);
specialized = [groundIdle126kW, groundIdlePower01];
design = local_design_anchor(cfg, targetNpRatio, targetPowerRatio);

requestedId = lower(strtrim(char(requestedId)));
if strcmp(requestedId, 'auto')
    applicable = find([specialized.available] & [specialized.applicable]);
    if isempty(applicable)
        seed = design;
    else
        [~, nearest] = min([specialized(applicable).distance]);
        seed = specialized(applicable(nearest));
    end
elseif strcmp(requestedId, design.id)
    seed = design;
else
    selected = find(strcmp(requestedId, {specialized.id}), 1);
    if isempty(selected)
        error('SHT:SteadySeed:UnknownId', ...
            '未知稳态初值标识：%s。', requestedId);
    end
    seed = specialized(selected);
    if ~seed.available
        error('SHT:SteadySeed:IncompatibleGroundIdleAnchor', ...
            ['地面慢车固化初值与当前模型基线不兼容。当前必须满足' ...
             'modelMode=1、Np0=20800 rpm、Ng0=38000 rpm、' ...
             'power0=2176600 W、A80=0.10573。']);
    end
end

seed.requestedId = requestedId;
seed.targetNpRpm = targetNpRpm;
seed.targetLoadPowerW = loadPowerW;
seed.targetNpRatio = targetNpRatio;
seed.targetPowerRatio = targetPowerRatio;
end

function seed = local_ground_idle_126kw_anchor( ...
        cfg, targetNpRatio, targetPowerRatio)
% 该向量来自2026-08-18六部件零修正模型、Npr=0.70、126 kW直接
% 扭矩工况的严格收敛结果。它是当前七点稳态试车方案的专用初值。
seed = local_empty_seed();
seed.id = 'six_component_ground_idle_npr70_power126kw';
seed.description = '六部件地面慢车Npr=0.70、等效126kW严格收敛初值';
seed.modelMode = 1;
seed.isSpecialized = true;
seed.variableNames = { ...
    'WIn'; 'AC_Rline'; 'CC_Rline'; 'GT1_PR'; 'GT2_PR'; ...
    'PT1_PR'; 'PT2_PR'; 'Np'; 'Ng'};
seed.varIte = [ ...
    2.6794933036016380; ...
    1.1021712766172673; ...
    0.34845391758140659; ...
    1.8869183620034293; ...
    1.6989782888396414; ...
    1.2409372891835171; ...
    1.0900230455888797; ...
    14559.999999999998; ...
    26189.848519927709];
seed.Wf = 0.027291087212764676;
seed.z = [seed.varIte; seed.Wf];
seed.referenceNpRatio = 0.70;
seed.referencePowerRatio = 126.0e3 / 2176600;
seed.referenceTorqueRatio = seed.referencePowerRatio / seed.referenceNpRatio;
seed.referenceResidualInfinityNorm = 2.6434674275000929e-7;
seed.validNpRatio = [0.68, 0.72];
seed.validPowerRatio = [0.045, 0.075];
seed.source = 'zero-health six-component converged trim, 126 kW, 2026-08-18';
seed = local_finalize_ground_idle_seed( ...
    seed, cfg, targetNpRatio, targetPowerRatio);
end

function seed = local_ground_idle_power01_anchor( ...
        cfg, targetNpRatio, targetPowerRatio)
% 该向量来自2026-08-18的六部件零修正基线严格配平结果。变量顺序与
% mode=1下C端varStartStore完全一致，最后的Wf不写入varStartStore。
seed = local_empty_seed();
seed.id = 'six_component_ground_idle_npr70_power01';
seed.description = '六部件地面慢车Npr=0.70、Pload/P0=0.01严格收敛初值';
seed.modelMode = 1;
seed.isSpecialized = true;
seed.variableNames = { ...
    'WIn'; 'AC_Rline'; 'CC_Rline'; 'GT1_PR'; 'GT2_PR'; ...
    'PT1_PR'; 'PT2_PR'; 'Np'; 'Ng'};
seed.varIte = [ ...
    1.7566929297040006; ...
    1.1431492884137855; ...
    0.30323855950698292; ...
    1.8172956797790063; ...
    1.3445245720369652; ...
    1.1019141902319936; ...
    1.0082135215477983; ...
    14559.999999999998; ...
    21671.948103020444];
seed.Wf = 0.016758158169043871;
seed.z = [seed.varIte; seed.Wf];
seed.referenceNpRatio = 0.70;
seed.referencePowerRatio = 0.01;
seed.referenceTorqueRatio = 0.01 / 0.70;
seed.referenceResidualInfinityNorm = 1.658797279746575e-9;
seed.validNpRatio = [0.65, 0.75];
seed.validPowerRatio = [0.003, 0.03];
seed.source = 'zero-health six-component converged trim, 2026-08-18';

seed = local_finalize_ground_idle_seed( ...
    seed, cfg, targetNpRatio, targetPowerRatio);
end

function seed = local_finalize_ground_idle_seed( ...
        seed, cfg, targetNpRatio, targetPowerRatio)
% 两个慢车固化点共享同一模型基线兼容性和适用域判定。
baseline = [20800, 38000, 2176600, 0.10573];
current = [cfg.engine.initial.Np0, cfg.engine.initial.Ng0, ...
    cfg.engine.initial.power0, cfg.engine.initial.A80];
scale = max(abs(baseline), 1);
baselineCompatible = cfg.engine.modelMode == 1 && ...
    all(abs(current - baseline) ./ scale <= 1e-10);
seed.available = baselineCompatible;
seed.applicable = baselineCompatible && ...
    targetNpRatio >= seed.validNpRatio(1) && ...
    targetNpRatio <= seed.validNpRatio(2) && ...
    targetPowerRatio >= seed.validPowerRatio(1) && ...
    targetPowerRatio <= seed.validPowerRatio(2);
seed.distance = local_normalized_distance(seed, ...
    targetNpRatio, targetPowerRatio);
end

function seed = local_design_anchor(cfg, targetNpRatio, targetPowerRatio)
seed = local_empty_seed();
seed.id = 'six_component_design';
seed.description = '当前V2六部件设计状态共同工作初值';
seed.modelMode = 1;
seed.isSpecialized = false;
seed.variableNames = { ...
    'WIn'; 'AC_Rline'; 'CC_Rline'; 'GT1_PR'; 'GT2_PR'; ...
    'PT1_PR'; 'PT2_PR'; 'Np'; 'Ng'};

if cfg.engine.modelMode ~= 1
    return;
end
thisDir = fileparts(mfilename('fullpath'));
stateFile = fullfile(thisDir, 'MiddleData', ...
    'RunModelSHT_V2_design_state.mat');
if ~isfile(stateFile)
    return;
end
loaded = load(stateFile, 'designState');
if ~isfield(loaded, 'designState') || ...
        ~isfield(loaded.designState, 'modelMode') || ...
        loaded.designState.modelMode ~= 1 || ...
        ~isfield(loaded.designState, 'design') || ...
        ~isfield(loaded.designState.design, 'commonVariables') || ...
        numel(loaded.designState.design.commonVariables) ~= 9 || ...
        any(~isfinite(loaded.designState.design.commonVariables(:)))
    return;
end

seed.varIte = loaded.designState.design.commonVariables(:);
seed.Wf = cfg.engine.initial.Wf0;
seed.z = [seed.varIte; seed.Wf];
seed.referenceNpRatio = 1;
seed.referencePowerRatio = 1;
seed.referenceTorqueRatio = 1;
seed.referenceResidualInfinityNorm = NaN;
seed.validNpRatio = [0, Inf];
seed.validPowerRatio = [0, Inf];
seed.source = stateFile;
seed.available = true;
seed.applicable = true;
seed.distance = local_normalized_distance(seed, ...
    targetNpRatio, targetPowerRatio);
end

function distance = local_normalized_distance(seed, npRatio, powerRatio)
npScale = 0.05;
powerFloor = 1e-6;
powerScale = log(3);
npDistance = (npRatio - seed.referenceNpRatio) / npScale;
powerDistance = log(max(powerRatio, powerFloor) / ...
    max(seed.referencePowerRatio, powerFloor)) / powerScale;
distance = hypot(npDistance, powerDistance);
end

function seed = local_empty_seed()
seed = struct();
seed.id = '';
seed.description = '';
seed.modelMode = NaN;
seed.isSpecialized = false;
seed.variableNames = cell(0, 1);
seed.varIte = zeros(0, 1);
seed.Wf = NaN;
seed.z = zeros(0, 1);
seed.referenceNpRatio = NaN;
seed.referencePowerRatio = NaN;
seed.referenceTorqueRatio = NaN;
seed.referenceResidualInfinityNorm = NaN;
seed.validNpRatio = [NaN, NaN];
seed.validPowerRatio = [NaN, NaN];
seed.source = '';
seed.available = false;
seed.applicable = false;
seed.distance = Inf;
end

function local_validate_input(cfg, targetNpRpm, loadPowerW, requestedId)
required = {'engine'};
if ~isstruct(cfg) || any(~isfield(cfg, required)) || ...
        ~isstruct(cfg.engine) || ...
        ~isfield(cfg.engine, 'modelMode') || ...
        ~isfield(cfg.engine, 'initial') || ...
        ~isstruct(cfg.engine.initial)
    error('SHT:SteadySeed:BadConfig', ...
        'cfg必须包含engine.modelMode和engine.initial。');
end
initialFields = {'Np0', 'Ng0', 'power0', 'Wf0', 'A80'};
if any(~isfield(cfg.engine.initial, initialFields))
    error('SHT:SteadySeed:BadConfig', ...
        'cfg.engine.initial缺少设计点转速、功率、燃油或喷口面积。');
end
initialValues = cellfun(@(name) cfg.engine.initial.(name), initialFields);
if any(~isfinite(initialValues)) || cfg.engine.initial.Np0 <= 0 || ...
        cfg.engine.initial.power0 <= 0
    error('SHT:SteadySeed:BadConfig', '设计点配置必须是有限正值。');
end
if ~isscalar(targetNpRpm) || ~isfinite(targetNpRpm) || targetNpRpm <= 0 || ...
        ~isscalar(loadPowerW) || ~isfinite(loadPowerW) || loadPowerW < 0
    error('SHT:SteadySeed:BadTarget', ...
        '目标Np必须为有限正值，负载功率必须为有限非负值。');
end
if ~(ischar(requestedId) || (isstring(requestedId) && isscalar(requestedId)))
    error('SHT:SteadySeed:BadId', 'requestedId必须是字符向量或标量字符串。');
end
end
