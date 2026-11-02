function [extended, audit] = sht_startstop_extend_turbine_map( ...
    original, extensionCfg, mapCfg)
%SHT_STARTSTOP_EXTEND_TURBINE_MAP 构造涡轮零速和低速扩展区。
%
% 锁转线在beta=0处满足(Wc=0,PR=1)。沿beta增大，压比和通流能力
% 平滑增加。零速效率是供现有T-MATS功率/转矩接口使用的小正数等效量，
% 不是把锁转工况解释成具有正常级效率；阶段三同时提供近零转矩诊断。

local_require_kind(original, 'turbine');
nMin = original.nc(1);
newNc = local_new_speed_nodes(nMin, mapCfg);
betaOriginal = original.path(:).';
betaSpan = max(betaOriginal(end) - betaOriginal(1), eps);
betaNormalized = (betaOriginal - betaOriginal(1)) / betaSpan;

firstWc = original.Wc(1, :);
firstEff = original.Eff(1, :);
lockedFlowMaximum = extensionCfg.lockedFlowFraction * max(firstWc);
lockedWc = lockedFlowMaximum .* betaNormalized .^ ...
    extensionCfg.lockedFlowBetaExponent;
lockedEff = extensionCfg.zeroEfficiency .* ...
    (0.5 + 0.5 * betaNormalized);
lockedMinPR = 1;
lockedMaxPR = extensionCfg.lockedMaximumPressureRatio;

nNew = numel(newNc);
WcNew = zeros(nNew, numel(betaOriginal));
EffNew = zeros(size(WcNew));
minPRNew = zeros(1, nNew);
maxPRNew = zeros(1, nNew);
for i = 1:nNew
    ratio = newNc(i) / nMin;
    blend = local_smoothstep(ratio);
    WcNew(i, :) = (1 - blend) * lockedWc + blend * firstWc;
    EffNew(i, :) = (1 - blend) * lockedEff + blend * firstEff;
    minPRNew(i) = (1 - blend) * lockedMinPR + ...
        blend * original.minPR(1);
    maxPRNew(i) = (1 - blend) * lockedMaxPR + ...
        blend * original.maxPR(1);
end

extended = original;
extended.fileName = '';
extended.nc = [newNc, original.nc];
extended.Wc = [WcNew; original.Wc];
extended.Eff = [EffNew; original.Eff];
extended.minPR = [minPRNew, original.minPR];
extended.maxPR = [maxPRNew, original.maxPR];
[extended, highSpeedAudit] = local_extend_high_speed_axis( ...
    extended, original, mapCfg);
extended = local_extend_beta_axis(extended, original, extensionCfg, mapCfg);
extended.PR = repmat(extended.minPR(:), 1, numel(extended.path)) + ...
    (repmat(extended.maxPR(:), 1, numel(extended.path)) - ...
    repmat(extended.minPR(:), 1, numel(extended.path))) .* ...
    repmat(extended.path(:).', numel(extended.nc), 1);
extended.hasFullPRSurface = false;
extended.preambleLines{1} = [original.preambleLines{1}, ...
    ' | StartupStop low-speed extension'];

audit = struct();
audit.newSpeedNodes = newNc;
audit.newHighSpeedNodes = highSpeedAudit.newSpeedNodes;
audit.originalMinimumSpeed = nMin;
audit.zeroPointAccepted = abs(extended.Wc(1, 1)) <= 64 * eps && ...
    abs(extended.minPR(1) - 1) <= 64 * eps && ...
    all(extended.Eff(1, :) > 0);
audit.pressureRangeAccepted = all(extended.minPR >= 1) && ...
    all(extended.maxPR > extended.minPR);
audit.originalMinimumEfficiency = min(original.Eff(:));
audit.addedMinimumEfficiency = min(EffNew(:));
% 原始Gasturb图的边缘区可能本来就含负效率点。低速扩展必须保持与
% 该最低转速线连续，但不能制造比原图更低的新极值。真正扭矩方向在
% 阶段三结合比功和轴功率单独验收，不能仅凭单个效率表格值判死刑。
efficiencyTolerance = 128 * eps(max(1, abs(audit.originalMinimumEfficiency)));
audit.efficiencyRangeAccepted = audit.addedMinimumEfficiency >= ...
    audit.originalMinimumEfficiency - efficiencyTolerance;
audit.finite = all(isfinite([extended.Wc(:); extended.Eff(:); ...
    extended.minPR(:); extended.maxPR(:)]));
audit.accepted = audit.zeroPointAccepted && ...
    audit.pressureRangeAccepted && audit.efficiencyRangeAccepted && ...
    highSpeedAudit.accepted && audit.finite;
end

function [map, audit] = local_extend_high_speed_axis(map, original, cfg)
% 冷拖时涡轮入口温度低，较低机械转速也可能对应高换算转速。这里沿原图
% 最高两条转速线的局部趋势显式补点，替代DLL隐式外推；原图网格不改。
axisTolerance = max(1e-8, 64 * eps(max(1, abs(map.nc(end)))));
newNc = cfg.turbineHighSpeedNodes( ...
    cfg.turbineHighSpeedNodes > map.nc(end) + axisTolerance);
newNc = unique(newNc);
if isempty(newNc)
    audit = struct('newSpeedNodes', zeros(1, 0), 'finite', true, ...
        'pressureRangeAccepted', true, 'efficiencyRangeAccepted', true, ...
        'accepted', true);
    return;
end

speedStep = map.nc(end) - map.nc(end - 1);
assert(speedStep > 0, '涡轮原图换算转速轴必须严格递增。');
flowSlope = (map.Wc(end, :) - map.Wc(end - 1, :)) / speedStep;
efficiencySlope = (map.Eff(end, :) - map.Eff(end - 1, :)) / speedStep;
minimumPressureSlope = (map.minPR(end) - map.minPR(end - 1)) / speedStep;
maximumPressureSlope = (map.maxPR(end) - map.maxPR(end - 1)) / speedStep;
originalMinimumEfficiency = min(original.Eff(:));

flowHigh = zeros(numel(newNc), numel(map.path));
efficiencyHigh = zeros(size(flowHigh));
minimumPressureHigh = zeros(1, numel(newNc));
maximumPressureHigh = zeros(1, numel(newNc));
for i = 1:numel(newNc)
    distance = newNc(i) - map.nc(end);
    flowHigh(i, :) = max(0, map.Wc(end, :) + distance * flowSlope);
    efficiencyHigh(i, :) = max(originalMinimumEfficiency, ...
        map.Eff(end, :) + distance * efficiencySlope);
    minimumPressureHigh(i) = max(1, ...
        map.minPR(end) + distance * minimumPressureSlope);
    maximumPressureHigh(i) = max(minimumPressureHigh(i) + 1e-6, ...
        map.maxPR(end) + distance * maximumPressureSlope);
end

map.nc = [map.nc, newNc];
map.Wc = [map.Wc; flowHigh];
map.Eff = [map.Eff; efficiencyHigh];
map.minPR = [map.minPR, minimumPressureHigh];
map.maxPR = [map.maxPR, maximumPressureHigh];
finite = all(isfinite([flowHigh(:); efficiencyHigh(:); ...
    minimumPressureHigh(:); maximumPressureHigh(:)]));
pressureRangeAccepted = all(minimumPressureHigh >= 1) && ...
    all(maximumPressureHigh > minimumPressureHigh);
efficiencyTolerance = 128 * eps(max(1, abs(originalMinimumEfficiency)));
efficiencyRangeAccepted = min(efficiencyHigh(:)) >= ...
    originalMinimumEfficiency - efficiencyTolerance;
audit = struct('newSpeedNodes', newNc, 'finite', finite, ...
    'pressureRangeAccepted', pressureRangeAccepted, ...
    'efficiencyRangeAccepted', efficiencyRangeAccepted, ...
    'accepted', finite && pressureRangeAccepted && efficiencyRangeAccepted);
end

function extended = local_extend_beta_axis(extended, original, cfg, mapCfg)
% 原图首列对应的最小压比通常仍大于1。起停冷拖需要在不改动原节点的
% 条件下补出PR=1附近的通流段；静止动力涡轮还需要beta>1的堵塞尾部。
low = mapCfg.turbineLowBetaNodes(:).';
low = low(low < original.path(1));
betaAtUnitPressure = (1 - extended.minPR) ./ ...
    (extended.maxPR - extended.minPR);
% 每条转速线的PR=1位置不同。把解析位置并入公共beta轴，保证已知
% 转速线上Wc=0；两条转速线之间仍需起停专用C查询按物理压比重建
% beta<0的三角通流区，矩形双线性插值本身不能保持这条斜边界。
low = unique([cfg.unitPressureBetaAnchor, low, betaAtUnitPressure]);
low = low(low < original.path(1));
low = low(low >= cfg.unitPressureBetaAnchor - 64 * eps);
high = mapCfg.turbineHighBetaNodes(:).';
high = unique(high(high > original.path(end)));

nRow = numel(extended.nc);
nLow = numel(low);
nHigh = numel(high);
WcLow = zeros(nRow, nLow);
EffLow = zeros(nRow, nLow);
if nLow > 0
    efficiencyFloor = max(1e-4, 0.25 * cfg.zeroEfficiency);
    for i = 1:nRow
        denominator = original.path(1) - betaAtUnitPressure(i);
        if denominator <= 64 * eps
            coordinate = zeros(1, nLow);
        else
            coordinate = max(0, min(1, ...
                (low - betaAtUnitPressure(i)) / denominator));
        end
        coordinate = coordinate .^ cfg.unitPressureFlowExponent;
        WcLow(i, :) = extended.Wc(i, 1) .* coordinate;
        EffLow(i, :) = efficiencyFloor + ...
            (extended.Eff(i, 1) - efficiencyFloor) .* coordinate;
    end
end

WcHigh = zeros(nRow, nHigh);
EffHigh = zeros(nRow, nHigh);
if nHigh > 0
    pathStep = original.path(end) - original.path(end - 1);
    flowSlope = max((extended.Wc(:, end) - extended.Wc(:, end - 1)) / ...
        pathStep, 0) * cfg.highBetaFlowSlopeFactor;
    for j = 1:nHigh
        WcHigh(:, j) = extended.Wc(:, end) + ...
            flowSlope * (high(j) - original.path(end));
        EffHigh(:, j) = extended.Eff(:, end);
    end
end

extended.path = [low, original.path(:).', high];
extended.Wc = [WcLow, extended.Wc, WcHigh];
extended.Eff = [EffLow, extended.Eff, EffHigh];
end

function nodes = local_new_speed_nodes(nMin, cfg)
axisTolerance = max(1e-8, 64 * eps(max(1, abs(nMin))));
nodes = cfg.lowSpeedNodes(cfg.lowSpeedNodes < nMin - axisTolerance);
transition = cfg.transitionNodeFraction * nMin;
if transition > 0 && transition < nMin - axisTolerance
    nodes = [nodes, transition];
end
nodes = unique(nodes);
end

function value = local_smoothstep(x)
x = min(max(x, 0), 1);
value = x .* x .* (3 - 2 .* x);
end

function local_require_kind(map, expected)
if ~isfield(map, 'kind') || ~strcmp(map.kind, expected)
    error('sht:startStop:mapKind', '输入特性图必须为%s。', expected);
end
end
