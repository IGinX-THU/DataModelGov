function [referenceTable, cacheInfo] = ...
        sht_prepare_clearance_reference_lookup(referenceTable)
%SHT_PREPARE_CLEARANCE_REFERENCE_LOOKUP 预构造epsilon_ss运行时插值缓存。
%
% 参考表节点在一次参数估计阶段内保持不变，只有查询坐标随时间变化。
% 本函数在进入整轨迹重放前完成一次数据校验、HPC/GT排序以及PT二维
% scatteredInterpolant构造，并把运行时缓存附加到referenceTable中。
% sht_lookup_clearance_reference随后只查询该缓存，不再逐采样点重建。
%
% 该缓存仅用于当前MATLAB进程中的运行时配置，不写回参数资产文件，
% 默认不改变历史最近表点回退；三部件PT可显式选择连续边界投影。

if ~isstruct(referenceTable) || ~isscalar(referenceTable) || ...
        ~isfield(referenceTable,'generated') || ...
        ~referenceTable.generated
    error('SHT:ClearanceSchedule:Unavailable', ...
        'epsilon_ss稳态参考表尚未生成，不能构造运行时插值缓存。');
end
isSplit = isfield(referenceTable,'topology') && ...
    strcmpi(char(referenceTable.topology),'split6');
if isSplit
    requiredComponents = {'AC','CC','GT1','GT2','PT1','PT2'};
else
    requiredComponents = {'HPC','GT','PT'};
end
for i = 1:numel(requiredComponents)
    if ~isfield(referenceTable,requiredComponents{i}) || ...
            ~isstruct(referenceTable.(requiredComponents{i}))
        error('SHT:ClearanceSchedule:SchemaMismatch', ...
            'epsilon_ss参考表缺少部件结构%s。',requiredComponents{i});
    end
end

% 即使输入结构中带有旧缓存，也始终由当前原始表节点重新构造，避免
% 修改表节点后误用过期三角剖分。
if isfield(referenceTable,'runtimeInterpolationCache')
    referenceTable = rmfield(referenceTable,'runtimeInterpolationCache');
end

if isSplit
    runtimeCache = struct();
    runtimeCache.version = 'epsilon-ss-runtime-interpolation-split6-v1';
    for i = 1:4
        name = requiredComponents{i};
        [grid,value] = local_prepare_1d(referenceTable.(name),name);
        runtimeCache.(name) = struct( ...
            'correctedSpeed_rpm',grid, ...
            'epsilonSSThermal',value, ...
            'interpolant',griddedInterpolant(grid,value,'linear','none'));
    end
    for i = 5:6
        name = requiredComponents{i};
        [speed,power,value,speedSpan,powerSpan] = ...
            local_prepare_2d(referenceTable.(name),name);
        runtimeCache.(name) = struct( ...
            'correctedSpeed_rpm',speed, ...
            'loadPower_W',power, ...
            'epsilonSSThermal',value, ...
            'speedSpan_rpm',speedSpan, ...
            'powerSpan_W',powerSpan, ...
            'interpolant',scatteredInterpolant( ...
                speed,power,value,'linear','none'));
    end
    referenceTable.runtimeInterpolationCache = runtimeCache;
    cacheInfo = struct();
    cacheInfo.enabled = true;
    cacheInfo.version = runtimeCache.version;
    cacheInfo.constructedAt = datestr(now,31);
    cacheInfo.componentNames = requiredComponents(:);
    cacheInfo.nodeCount = zeros(6,1);
    for i = 1:6
        cacheInfo.nodeCount(i) = numel( ...
            runtimeCache.(requiredComponents{i}).correctedSpeed_rpm);
    end
    cacheInfo.interpolationMethod = ...
        {'linear';'linear';'linear';'linear';'linear scattered';'linear scattered'};
    cacheInfo.extrapolationMethod = repmat({'none'},6,1);
    return;
end

[hpcGrid,hpcValue] = local_prepare_1d(referenceTable.HPC,'HPC');
[gtGrid,gtValue] = local_prepare_1d(referenceTable.GT,'GT');
[ptSpeed,ptPower,ptValue,ptSpeedSpan,ptPowerSpan] = ...
    local_prepare_2d(referenceTable.PT,'PT');

runtimeCache = struct();
runtimeCache.version = 'epsilon-ss-runtime-interpolation-v1';
runtimeCache.HPC = struct('correctedSpeed_rpm',hpcGrid, ...
    'epsilonSSThermal',hpcValue, ...
    'interpolant',griddedInterpolant( ...
        hpcGrid,hpcValue,'linear','none'));
runtimeCache.GT = struct('correctedSpeed_rpm',gtGrid, ...
    'epsilonSSThermal',gtValue, ...
    'interpolant',griddedInterpolant( ...
        gtGrid,gtValue,'linear','none'));
runtimeCache.PT = struct( ...
    'correctedSpeed_rpm',ptSpeed, ...
    'loadPower_W',ptPower, ...
    'epsilonSSThermal',ptValue, ...
    'speedSpan_rpm',ptSpeedSpan, ...
    'powerSpan_W',ptPowerSpan, ...
    'interpolant',scatteredInterpolant( ...
        ptSpeed,ptPower,ptValue,'linear','none'));
if isfield(referenceTable.PT,'extrapolationPolicy')
    policy=char(referenceTable.PT.extrapolationPolicy);
    assert(ismember(policy,{'nearest_node','continuous_hull_projection'}), ...
        'SHT:ClearanceSchedule:BoundaryPolicy','未知PT参考表边界策略%s。',policy);
    if strcmp(policy,'continuous_hull_projection')
        runtimeCache.PT.boundaryProjection=sht_clearance_hull_projection( ...
            'prepare',ptSpeed,ptPower,ptValue);
    end
end
referenceTable.runtimeInterpolationCache = runtimeCache;

cacheInfo = struct();
cacheInfo.enabled = true;
cacheInfo.version = runtimeCache.version;
cacheInfo.constructedAt = datestr(now,31);
cacheInfo.hpcNodeCount = numel(hpcGrid);
cacheInfo.gtNodeCount = numel(gtGrid);
cacheInfo.ptNodeCount = numel(ptSpeed);
cacheInfo.ptInterpolationMethod = 'linear';
cacheInfo.ptExtrapolationMethod = 'none';
end

function [grid,value] = local_prepare_1d(component,componentName)
required = {'correctedSpeed_rpm','epsilonSSThermal'};
for i = 1:numel(required)
    if ~isfield(component,required{i})
        error('SHT:ClearanceSchedule:SchemaMismatch', ...
            '%s一维参考表缺少字段%s。',componentName,required{i});
    end
end
grid = component.correctedSpeed_rpm(:);
value = component.epsilonSSThermal(:);
if numel(grid)<2 || numel(grid)~=numel(value) || ...
        any(~isfinite(grid)) || any(~isfinite(value))
    error('SHT:ClearanceSchedule:SchemaMismatch', ...
        '%s一维参考表必须包含至少两个有限且一一对应的节点。', ...
        componentName);
end
[grid,order] = sort(grid);
value = value(order);
if any(diff(grid)<=0)
    error('SHT:ClearanceSchedule:SchemaMismatch', ...
        '%s一维参考表坐标必须严格递增且不得重复。',componentName);
end
end

function [speed,power,value,speedSpan,powerSpan] = ...
        local_prepare_2d(component,componentName)
if nargin < 2
    componentName = 'PT';
end
required = {'correctedSpeed_rpm','loadPower_W','epsilonSSThermal'};
for i = 1:numel(required)
    if ~isfield(component,required{i})
        error('SHT:ClearanceSchedule:SchemaMismatch', ...
            '%s二维参考表缺少字段%s。',componentName,required{i});
    end
end
speed = component.correctedSpeed_rpm(:);
power = component.loadPower_W(:);
value = component.epsilonSSThermal(:);
if numel(speed)<3 || numel(speed)~=numel(power) || ...
        numel(speed)~=numel(value) || any(~isfinite(speed)) || ...
        any(~isfinite(power)) || any(~isfinite(value))
    error('SHT:ClearanceSchedule:SchemaMismatch', ...
        '%s二维参考表必须包含至少三个有限且一一对应的节点。', ...
        componentName);
end
speedSpan = max(speed)-min(speed);
powerSpan = max(power)-min(power);
if speedSpan<=0 || powerSpan<=0
    error('SHT:ClearanceSchedule:SchemaMismatch', ...
        '%s二维参考表的修正转速和负载功率跨度都必须大于零。', ...
        componentName);
end
end
