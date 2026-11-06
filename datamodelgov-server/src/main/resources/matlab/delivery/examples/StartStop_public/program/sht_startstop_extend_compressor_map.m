function [extended, audit] = sht_startstop_extend_compressor_map( ...
    original, extensionCfg, mapCfg)
%SHT_STARTSTOP_EXTEND_COMPRESSOR_MAP 构造压气机零速和低速扩展区。
%
% 零速线上，Rline高端固定为(Wc=0,PR=1)，其余正向通流点表示锁转
% 叶栅压损。新增转速线采用三次光滑权重连接到原最低转速线。现阶段
% 效率只是现有T-MATS接口所需的等效量，后续校准以比功和扭矩为准。

local_require_kind(original, 'compressor');
nMin = original.nc(1);
newNc = local_new_speed_nodes(nMin, mapCfg);
path = original.path(:).';

firstWc = original.Wc(1, :);
firstPR = original.PR(1, :);
firstEff = original.Eff(1, :);
pathSpan = max(path(end) - path(1), eps);
pathNormalized = (path - path(1)) / pathSpan;

lockedFlowMaximum = extensionCfg.lockedFlowFraction * max(firstWc);
lockedWc = lockedFlowMaximum .* (1 - pathNormalized) .^ 0.80;
if lockedFlowMaximum > 0
    flowRatio = lockedWc / lockedFlowMaximum;
else
    flowRatio = zeros(size(lockedWc));
end
lockedPR = 1 - extensionCfg.lockedPressureLoss .* flowRatio .^ 2;
lockedEff = extensionCfg.zeroEfficiency * ones(size(path));

nNew = numel(newNc);
WcNew = zeros(nNew, numel(path));
PRNew = zeros(size(WcNew));
EffNew = zeros(size(WcNew));
for i = 1:nNew
    ratio = newNc(i) / nMin;
    blend = local_smoothstep(ratio);
    WcNew(i, :) = (1 - blend) * lockedWc + blend * firstWc;
    PRNew(i, :) = (1 - blend) * lockedPR + blend * firstPR;
    EffNew(i, :) = (1 - blend) * lockedEff + blend * firstEff;
end

extended = original;
extended.fileName = '';
extended.nc = [newNc, original.nc];
extended.Wc = [WcNew; original.Wc];
extended.PR = [PRNew; original.PR];
extended.Eff = [EffNew; original.Eff];
[extended, lowPathAudit] = local_extend_low_path(extended, mapCfg);
[extended, highPathAudit] = local_extend_high_path(extended, mapCfg);
extended.preambleLines{1} = [original.preambleLines{1}, ...
    ' | StartupStop low-speed extension'];

if ~isempty(original.surgeWc)
    surgeWcNew = zeros(1, nNew);
    surgePRNew = zeros(1, nNew);
    for i = 1:nNew
        ratio = newNc(i) / nMin;
        surgeWcNew(i) = ratio * original.surgeWc(1);
        surgePRNew(i) = 1 + ratio ^ 2 * (original.surgePR(1) - 1);
    end
    extended.surgeWc = [surgeWcNew, original.surgeWc];
    extended.surgePR = [surgePRNew, original.surgePR];
end

audit = struct();
audit.newSpeedNodes = newNc;
audit.originalMinimumSpeed = nMin;
audit.zeroFlowAtZeroPressureRatio = ...
    abs(extended.Wc(1, end)) <= 64 * eps && ...
    abs(extended.PR(1, end) - 1) <= 64 * eps;
audit.lockedRotorLossDirection = all(extended.PR(1, :) <= 1 + 64 * eps);
audit.minimumPR = min(extended.PR(:));
audit.minimumEfficiency = min(extended.Eff(:));
audit.finite = all(isfinite([extended.Wc(:); extended.PR(:); ...
    extended.Eff(:)]));
audit.lowPath = lowPathAudit;
audit.highPath = highPathAudit;
audit.accepted = audit.zeroFlowAtZeroPressureRatio && ...
    audit.lockedRotorLossDirection && audit.minimumPR > 0 && ...
    audit.minimumEfficiency > 0 && audit.finite && ...
    lowPathAudit.accepted && highPathAudit.accepted;
end

function [map, audit] = local_extend_low_path(map, cfg)
% Rline低侧对应大流量堵塞端。采用原图首端局部斜率显式补点，使DLL
% 不再依赖隐式直线外推；通流不随Rline减小而降低，压比和效率不在
% 图外反向抬升。所有原始节点保持逐元素不变。
axisTolerance = max(1e-8, 64 * eps(max(1, abs(map.path(1)))));
newPath = cfg.compressorLowPathNodes( ...
    cfg.compressorLowPathNodes < map.path(1) - axisTolerance);
newPath = unique(newPath);
if isempty(newPath)
    audit = struct('addedNodeCount', 0, 'flowNonIncreasing', true, ...
        'finite', true, 'accepted', true);
    return;
end

pathStep = map.path(2) - map.path(1);
assert(pathStep > 0, '压气机原图Rline轴必须严格递增。');
flowSlope = min((map.Wc(:, 2) - map.Wc(:, 1)) / pathStep, 0);
pressureSlope = max((map.PR(:, 2) - map.PR(:, 1)) / pathStep, 0);
efficiencySlope = max((map.Eff(:, 2) - map.Eff(:, 1)) / pathStep, 0);
firstPath = map.path(1);
firstFlow = map.Wc(:, 1);
firstPressure = map.PR(:, 1);
firstEfficiency = map.Eff(:, 1);
flowTail = zeros(numel(map.nc), numel(newPath));
pressureTail = zeros(size(flowTail));
efficiencyTail = zeros(size(flowTail));
for j = 1:numel(newPath)
    distance = newPath(j) - firstPath;
    flowTail(:, j) = max(0, firstFlow + distance * flowSlope);
    pressureTail(:, j) = max(0.05, ...
        firstPressure + distance * pressureSlope);
    efficiencyTail(:, j) = max(0.05, ...
        firstEfficiency + distance * efficiencySlope);
end

map.path = [newPath, map.path];
map.Wc = [flowTail, map.Wc];
map.PR = [pressureTail, map.PR];
map.Eff = [efficiencyTail, map.Eff];
flowDifference = diff(map.Wc(:, 1:(numel(newPath) + 1)), 1, 2);
tolerance = 128 * eps(max(1, max(abs(map.Wc(:)))));
finite = all(isfinite([flowTail(:); pressureTail(:); efficiencyTail(:)]));
flowNonIncreasing = all(flowDifference(:) <= tolerance);
audit = struct('addedNodeCount', numel(newPath), ...
    'flowNonIncreasing', flowNonIncreasing, 'finite', finite, ...
    'accepted', finite && flowNonIncreasing && ...
        all(pressureTail(:) > 0) && all(efficiencyTail(:) > 0));
end

function [map, audit] = local_extend_high_path(map, cfg)
% 原图Rline=1通常对应喘振边界。起停固定转速匹配仍可能需要更低流量的
% 后喘振数学尾部，因此只在起停专用图中显式增加Rline节点。尾部沿原图
% 末端的非增流量斜率延拓；压比和效率不允许在边界外反向抬升。这样既
% 消除DLL隐式外推，也不改写任何原始网格点。
axisTolerance = max(1e-8, 64 * eps(max(1, abs(map.path(end)))));
newPath = cfg.compressorHighPathNodes( ...
    cfg.compressorHighPathNodes > map.path(end) + axisTolerance);
newPath = unique(newPath);
if isempty(newPath)
    audit = struct('addedNodeCount', 0, 'flowNonIncreasing', true, ...
        'finite', true, 'accepted', true);
    return;
end

pathStep = map.path(end) - map.path(end - 1);
assert(pathStep > 0, '压气机原图Rline轴必须严格递增。');
flowSlope = min((map.Wc(:, end) - map.Wc(:, end - 1)) / pathStep, 0);
pressureSlope = min((map.PR(:, end) - map.PR(:, end - 1)) / pathStep, 0);
efficiencySlope = min((map.Eff(:, end) - map.Eff(:, end - 1)) / pathStep, 0);

lastPath = map.path(end);
lastFlow = map.Wc(:, end);
lastPressure = map.PR(:, end);
lastEfficiency = map.Eff(:, end);
flowTail = zeros(numel(map.nc), numel(newPath));
pressureTail = zeros(size(flowTail));
efficiencyTail = zeros(size(flowTail));
for j = 1:numel(newPath)
    distance = newPath(j) - lastPath;
    flowTail(:, j) = max(0, lastFlow + distance * flowSlope);
    pressureTail(:, j) = max(0.05, ...
        lastPressure + distance * pressureSlope);
    efficiencyTail(:, j) = max(0.05, ...
        lastEfficiency + distance * efficiencySlope);
end

map.path = [map.path, newPath];
map.Wc = [map.Wc, flowTail];
map.PR = [map.PR, pressureTail];
map.Eff = [map.Eff, efficiencyTail];
tailStart = size(map.Wc, 2) - numel(newPath);
flowDifference = diff(map.Wc(:, tailStart:end), 1, 2);
tolerance = 128 * eps(max(1, max(abs(map.Wc(:)))));
finite = all(isfinite([flowTail(:); pressureTail(:); efficiencyTail(:)]));
flowNonIncreasing = all(flowDifference(:) <= tolerance);
audit = struct('addedNodeCount', numel(newPath), ...
    'flowNonIncreasing', flowNonIncreasing, 'finite', finite, ...
    'accepted', finite && flowNonIncreasing && ...
        all(pressureTail(:) > 0) && all(efficiencyTail(:) > 0));
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
