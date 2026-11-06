function [epsilonSS, lookupInfo] = sht_lookup_clearance_reference( ...
    referenceTable, npRpm, ngRpm, loadPowerW, inletTtK)
%SHT_LOOKUP_CLEARANCE_REFERENCE 查询当前工况的三个稳态参考归一化间隙。
%
% HPC/GT 以发动机进口基准修正 Ng 作一维线性插值；PT 以发动机进口
% 基准修正 Np 和负载功率作二维线性插值。表中保存的是不含离心项的
% 热参考间隙，查询后用当前绝对转速补回离心项。查询超出线性插值域时，
% 默认采用历史最近表点；三部件PT显式选择continuous_hull_projection时，
% 改为归一化坐标上的凸包边界投影并沿边界分段线性取值，保证连续。
% 若referenceTable包含预构造运行时缓存，则复用HPC/GT排序结果和PT
% scatteredInterpolant；未包含缓存时保持原即时构造路径，兼容其他入口。

local_validate_scalar(npRpm, 'Np');
local_validate_scalar(ngRpm, 'Ng');
local_validate_scalar(loadPowerW, 'loadPower');
local_validate_scalar(inletTtK, 'Tt1');
if inletTtK <= 0
    error('SHT:ClearanceSchedule:InvalidInletTemperature', ...
        'Tt1 必须为有限正值。');
end
if ~isstruct(referenceTable) || ~isfield(referenceTable, 'generated') || ...
        ~referenceTable.generated
    error('SHT:ClearanceSchedule:Unavailable', ...
        'epsilon_ss 稳态参考表尚未生成。');
end

requiredTopFields = {'standardTemperature_K', 'designSpeed_rpm', ...
    'centrifugalCoefficient', 'referenceNormalizedSpeed'};
for i = 1:numel(requiredTopFields)
    if ~isfield(referenceTable, requiredTopFields{i})
        error('SHT:ClearanceSchedule:SchemaMismatch', ...
            'epsilon_ss 参考表缺少字段 %s，请重新执行参数初始化程序。', ...
            requiredTopFields{i});
    end
end
isSplit = isfield(referenceTable, 'topology') && ...
    strcmpi(char(referenceTable.topology), 'split6');
if isSplit
    [epsilonSS, lookupInfo] = local_lookup_split6( ...
        referenceTable, npRpm, ngRpm, loadPowerW, inletTtK);
    return;
end
if ~isfield(referenceTable.HPC, 'correctedSpeed_rpm') || ...
        ~isfield(referenceTable.GT, 'correctedSpeed_rpm') || ...
        ~isfield(referenceTable.PT, 'correctedSpeed_rpm')
    error('SHT:ClearanceSchedule:LegacyCoordinate', ...
        '检测到旧版绝对转速参考表，请重新执行 Start_TransientEffects_01。');
end

standardTemperatureK = referenceTable.standardTemperature_K;
if ~isscalar(standardTemperatureK) || ~isfinite(standardTemperatureK) || ...
        standardTemperatureK <= 0
    error('SHT:ClearanceSchedule:InvalidStandardTemperature', ...
        '参考表标准温度必须为有限正标量。');
end
theta = inletTtK / standardTemperatureK;
inletCorrectedNgRpm = ngRpm / sqrt(theta);
inletCorrectedNpRpm = npRpm / sqrt(theta);

[runtimeCache,cacheEnabled] = local_runtime_cache(referenceTable);
if cacheEnabled
    hpcNg = runtimeCache.HPC.correctedSpeed_rpm;
    gtNg = runtimeCache.GT.correctedSpeed_rpm;
    hpcThermal = runtimeCache.HPC.epsilonSSThermal;
    gtThermal = runtimeCache.GT.epsilonSSThermal;
    hpcPrepared = runtimeCache.HPC;
    gtPrepared = runtimeCache.GT;
else
    hpcNg = referenceTable.HPC.correctedSpeed_rpm(:);
    gtNg = referenceTable.GT.correctedSpeed_rpm(:);
    hpcThermal = referenceTable.HPC.epsilonSSThermal(:);
    gtThermal = referenceTable.GT.epsilonSSThermal(:);
    hpcPrepared = [];
    gtPrepared = [];
end

epsilonThermal = zeros(3, 1);
[epsilonThermal(1), hpcFallback] = local_interp1_or_nearest( ...
    hpcNg,hpcThermal,inletCorrectedNgRpm,'HPC',hpcPrepared);
[epsilonThermal(2), gtFallback] = local_interp1_or_nearest( ...
    gtNg,gtThermal,inletCorrectedNgRpm,'GT',gtPrepared);

if cacheEnabled
    ptNp = runtimeCache.PT.correctedSpeed_rpm;
    ptPower = runtimeCache.PT.loadPower_W;
    ptThermal = runtimeCache.PT.epsilonSSThermal;
    ptPrepared = runtimeCache.PT;
else
    ptNp = referenceTable.PT.correctedSpeed_rpm(:);
    ptPower = referenceTable.PT.loadPower_W(:);
    ptThermal = referenceTable.PT.epsilonSSThermal(:);
    ptPrepared = [];
end
ptPolicy='nearest_node';
if isfield(referenceTable.PT,'extrapolationPolicy')
    ptPolicy=char(referenceTable.PT.extrapolationPolicy);
end
[epsilonThermal(3), ptFallback] = local_interp2_or_nearest( ...
    ptNp,ptPower,ptThermal,inletCorrectedNpRpm,loadPowerW,ptPrepared,ptPolicy);

if any(~isfinite(epsilonThermal))
    error('SHT:ClearanceSchedule:InvalidTableValue', ...
        'epsilon_ss 线性插值或最近点回退得到非有限热参考间隙。');
end

designSpeed = referenceTable.designSpeed_rpm(:);
b = referenceTable.centrifugalCoefficient(:);
nRef = referenceTable.referenceNormalizedSpeed(:);
currentSpeed = [ngRpm; ngRpm; npRpm];
normalizedSpeed = currentSpeed ./ designSpeed;
epsilonSS = epsilonThermal - b .* (normalizedSpeed .^ 2 - nRef .^ 2);
if any(~isfinite(epsilonSS)) || any(epsilonSS <= 0)
    error('SHT:ClearanceSchedule:InvalidResult', ...
        '查询得到非有限或非正 epsilon_ss，拒绝继续积分。');
end

if nargout>=2
    lookupInfo = struct();
    lookupInfo.epsilonSSThermal = epsilonThermal;
    lookupInfo.normalizedSpeed = normalizedSpeed;
    lookupInfo.centrifugalContribution = ...
        -b .* (normalizedSpeed .^ 2 - nRef .^ 2);
    lookupInfo.query = struct('Np_rpm',npRpm,'Ng_rpm',ngRpm, ...
        'Tt1_K',inletTtK, ...
        'inletCorrectedNp_rpm',inletCorrectedNpRpm, ...
        'inletCorrectedNg_rpm',inletCorrectedNgRpm, ...
        'loadPower_W',loadPowerW);
    lookupInfo.nearestPointFallback = struct( ...
        'used',[hpcFallback.used;gtFallback.used;ptFallback.used], ...
        'HPC',hpcFallback,'GT',gtFallback,'PT',ptFallback);
end
end

function [value, fallback] = local_interp1_or_nearest( ...
    grid,tableValue,query,componentName,prepared)
% 域内使用线性插值；域外保持最近端点的热参考间隙。
if nargin<5
    prepared = [];
end
grid = grid(:);
tableValue = tableValue(:);
if isempty(prepared)
    if numel(grid) < 2 || numel(grid) ~= numel(tableValue) || ...
            any(~isfinite(grid)) || any(~isfinite(tableValue))
        error('SHT:ClearanceSchedule:SchemaMismatch', ...
            '%s 一维参考表必须包含至少两个有限且一一对应的节点。', ...
            componentName);
    end
    [grid, order] = sort(grid);
    tableValue = tableValue(order);
    if any(diff(grid) <= 0)
        error('SHT:ClearanceSchedule:SchemaMismatch', ...
            '%s 一维参考表坐标必须严格递增且不得重复。',componentName);
    end
end

query = local_snap_roundoff_at_boundary(query, grid);
if isempty(prepared)
    value = interp1(grid,tableValue,query,'linear',NaN);
else
    value = prepared.interpolant(query);
end
fallback = struct('used', false, 'nodeIndex', NaN, ...
    'queryCoordinate', query, 'usedCoordinate', NaN, ...
    'thermalValue', NaN, 'normalizedDistance', 0);
if ~isfinite(value)
    [distance, index] = min(abs(grid - query));
    value = tableValue(index);
    fallback.used = true;
    fallback.nodeIndex = index;
    fallback.usedCoordinate = grid(index);
    fallback.thermalValue = value;
    fallback.normalizedDistance = distance / (grid(end) - grid(1));
end

message = '';
if fallback.used
    message = sprintf([ ...
        '%s epsilon_ss 查询超出一维线性插值域：进口基准修正 Ng=%.15g rpm；' ...
        '采用最近表点 %.15g rpm 的热参考间隙 %.15g。'], ...
        componentName,query,fallback.usedCoordinate,fallback.thermalValue);
end
local_update_fallback_warning(componentName, fallback.used, message);
end

function [value, fallback] = local_interp2_or_nearest( ...
    speedGrid,powerGrid,tableValue,speedQuery,powerQuery,prepared,policy)
% PT 域外最近点距离按两坐标各自跨度归一化，避免功率量纲支配距离。
if nargin<6
    prepared = [];
end
if nargin<7,policy='nearest_node';end
assert(ismember(policy,{'nearest_node','continuous_hull_projection'}), ...
    'SHT:ClearanceSchedule:BoundaryPolicy','未知PT参考表边界策略%s。',policy);
speedGrid = speedGrid(:);
powerGrid = powerGrid(:);
tableValue = tableValue(:);
if isempty(prepared)
    if numel(speedGrid) < 3 || numel(speedGrid) ~= numel(powerGrid) || ...
            numel(speedGrid) ~= numel(tableValue) || ...
            any(~isfinite(speedGrid)) || any(~isfinite(powerGrid)) || ...
            any(~isfinite(tableValue))
        error('SHT:ClearanceSchedule:SchemaMismatch', ...
            'PT 二维参考表必须包含至少三个有限且一一对应的节点。');
    end
    speedSpan = max(speedGrid)-min(speedGrid);
    powerSpan = max(powerGrid)-min(powerGrid);
    if speedSpan<=0 || powerSpan<=0
        error('SHT:ClearanceSchedule:SchemaMismatch', ...
            'PT 二维参考表的修正转速和负载功率跨度都必须大于零。');
    end
    interpolant = scatteredInterpolant(speedGrid,powerGrid, ...
        tableValue,'linear','none');
else
    speedSpan = prepared.speedSpan_rpm;
    powerSpan = prepared.powerSpan_W;
    interpolant = prepared.interpolant;
end

speedQuery = local_snap_roundoff_at_boundary(speedQuery, speedGrid);
powerQuery = local_snap_roundoff_at_boundary(powerQuery, powerGrid);
value = interpolant(speedQuery, powerQuery);
fallback = struct('used', false, 'nodeIndex', NaN, ...
    'queryCoordinate', [speedQuery, powerQuery], ...
    'usedCoordinate', [NaN, NaN], 'thermalValue', NaN, ...
    'normalizedDistance', 0);
if ~isfinite(value) && strcmp(policy,'continuous_hull_projection')
    if ~isempty(prepared) && isfield(prepared,'boundaryProjection')
        geometry=prepared.boundaryProjection;
    else
        geometry=sht_clearance_hull_projection('prepare',speedGrid,powerGrid,tableValue);
    end
    [value,projection]=sht_clearance_hull_projection('query',geometry,[speedQuery,powerQuery]);
    fallback.used=true;fallback.usedCoordinate=projection.usedCoordinate;
    fallback.thermalValue=value;fallback.normalizedDistance=projection.normalizedDistance;
    fallback.edgeIndex=projection.edgeIndex;fallback.edgeFraction=projection.edgeFraction;
elseif ~isfinite(value)
    distanceSquared = ((speedGrid - speedQuery) ./ speedSpan) .^ 2 + ...
        ((powerGrid - powerQuery) ./ powerSpan) .^ 2;
    [minimumDistanceSquared, index] = min(distanceSquared);
    value = tableValue(index);
    fallback.used = true;
    fallback.nodeIndex = index;
    fallback.usedCoordinate = [speedGrid(index), powerGrid(index)];
    fallback.thermalValue = value;
    fallback.normalizedDistance = sqrt(minimumDistanceSquared);
end
fallback.policy=policy;

message = '';
if fallback.used
    if strcmp(policy,'continuous_hull_projection')
        message=sprintf(['PT epsilon_ss查询超出二维覆盖域：修正Np=%.15g rpm，' ...
            '负载=%.15g W；连续投影到边界[%.15g rpm, %.15g W]，热参考间隙%.15g。'], ...
            speedQuery,powerQuery,fallback.usedCoordinate(1),fallback.usedCoordinate(2),value);
    else
        message = sprintf([ ...
        'PT epsilon_ss 查询超出二维线性插值覆盖域：进口基准修正 Np=' ...
        '%.15g rpm，负载功率=%.15g W；采用归一化坐标距离最近表点 ' ...
        '[%.15g rpm, %.15g W] 的热参考间隙 %.15g。'], ...
        speedQuery,powerQuery,fallback.usedCoordinate(1), ...
        fallback.usedCoordinate(2),fallback.thermalValue);
    end
end
local_update_fallback_warning('PT', fallback.used, message);
end

function [cache,enabled] = local_runtime_cache(referenceTable)
enabled = isfield(referenceTable,'runtimeInterpolationCache');
if ~enabled
    cache = struct();
    return;
end
cache = referenceTable.runtimeInterpolationCache;
required = {'version','HPC','GT','PT'};
if ~isstruct(cache) || ~isscalar(cache) || ...
        any(~isfield(cache,required)) || ...
        ~strcmp(cache.version,'epsilon-ss-runtime-interpolation-v1') || ...
        ~isfield(cache.HPC,'interpolant') || ...
        ~isa(cache.HPC.interpolant,'griddedInterpolant') || ...
        ~isfield(cache.GT,'interpolant') || ...
        ~isa(cache.GT.interpolant,'griddedInterpolant') || ...
        ~isfield(cache.PT,'interpolant') || ...
        ~isa(cache.PT.interpolant,'scatteredInterpolant')
    error('SHT:ClearanceSchedule:InvalidRuntimeCache', ...
        'epsilon_ss运行时插值缓存无效，请重新执行缓存构造程序。');
end
end

function value = local_snap_roundoff_at_boundary(value, grid)
% 先吸收机器精度及共同工作求解容差造成的边界伪越界，再由插值函数
% 判定真正的域外查询。相对容差1e-10在20800 rpm处仅约2e-6 rpm，
% 远小于任何物理可分辨转速变化，不会掩盖真实的参考表覆盖不足。
gridMin = min(grid);
gridMax = max(grid);
coordinateScale = max([1;abs(grid(:));abs(value)]);
tolerance = max(32*eps(coordinateScale),1e-10*coordinateScale);
if value < gridMin && gridMin - value <= tolerance
    value = gridMin;
elseif value > gridMax && value - gridMax <= tolerance
    value = gridMax;
end
end

function local_update_fallback_warning(componentName, fallbackUsed, message)
% 每个部件在一次MATLAB会话中首次越界时提示一次。瞬态历程可能在参考表
% 边界两侧反复穿越；若按“每次重新进入域外”报警，会产生数千条相同日志，
% 既不能增加诊断信息，也会明显拖慢长历程辨识。clear本函数后计数自然复位。
persistent hasWarned
if isempty(hasWarned)
    hasWarned = struct('HPC', false, 'GT', false, 'PT', false);
end
if ~isfield(hasWarned, componentName)
    hasWarned.(componentName) = false;
end
if fallbackUsed && ~hasWarned.(componentName)
    warning(['SHT:ClearanceSchedule:', componentName, ...
        'NearestPointFallback'], '%s 后续连续越界点不再重复提示。', message);
    hasWarned.(componentName) = true;
end
end

function local_validate_scalar(value, variableName)
if ~isscalar(value) || ~isfinite(value)
    error('SHT:ClearanceSchedule:InvalidQuery', ...
        '%s 必须是有限标量。', variableName);
end
end

function [epsilonSS, lookupInfo] = local_lookup_split6( ...
    referenceTable, npRpm, ngRpm, loadPowerW, inletTtK)
% 六部件顺序固定为AC、CC、GT1、GT2、PT1、PT2。前四个部件使用
% 进口基准修正Ng的一维表，两个动力涡轮级使用修正Np-负载二维表。
componentNames = {'AC','CC','GT1','GT2','PT1','PT2'};
for i = 1:numel(componentNames)
    if ~isfield(referenceTable, componentNames{i})
        error('SHT:ClearanceSchedule:SplitSchemaMismatch', ...
            '六部件参考表缺少%s。', componentNames{i});
    end
end
standardTemperatureK = referenceTable.standardTemperature_K;
theta = inletTtK / standardTemperatureK;
correctedNgRpm = ngRpm / sqrt(theta);
correctedNpRpm = npRpm / sqrt(theta);
[runtimeCache, cacheEnabled] = local_split_runtime_cache(referenceTable);

epsilonThermal = zeros(6,1);
fallback = cell(6,1);
for i = 1:4
    name = componentNames{i};
    component = referenceTable.(name);
    prepared = [];
    if cacheEnabled
        component = runtimeCache.(name);
        prepared = component;
    end
    [epsilonThermal(i), fallback{i}] = local_interp1_or_nearest( ...
        component.correctedSpeed_rpm, component.epsilonSSThermal, ...
        correctedNgRpm, name, prepared);
end
for i = 5:6
    name = componentNames{i};
    component = referenceTable.(name);
    prepared = [];
    if cacheEnabled
        component = runtimeCache.(name);
        prepared = component;
    end
    [epsilonThermal(i), fallback{i}] = local_interp2_or_nearest_named( ...
        component.correctedSpeed_rpm, component.loadPower_W, ...
        component.epsilonSSThermal, correctedNpRpm, loadPowerW, ...
        prepared, name);
end

designSpeed = referenceTable.designSpeed_rpm(:);
b = referenceTable.centrifugalCoefficient(:);
nRef = referenceTable.referenceNormalizedSpeed(:);
if numel(designSpeed) ~= 6 || numel(b) ~= 6 || numel(nRef) ~= 6
    error('SHT:ClearanceSchedule:SplitSchemaMismatch', ...
        '六部件参考表的设计转速、离心系数和参考归一化转速均须为6维。');
end
currentSpeed = [ngRpm;ngRpm;ngRpm;ngRpm;npRpm;npRpm];
normalizedSpeed = currentSpeed ./ designSpeed;
epsilonSS = epsilonThermal - b .* (normalizedSpeed.^2 - nRef.^2);
if any(~isfinite(epsilonSS)) || any(epsilonSS <= 0)
    error('SHT:ClearanceSchedule:InvalidResult', ...
        '六部件查询得到非有限或非正epsilon_ss。');
end

lookupInfo = struct();
lookupInfo.componentNames = componentNames(:);
lookupInfo.epsilonSSThermal = epsilonThermal;
lookupInfo.normalizedSpeed = normalizedSpeed;
lookupInfo.centrifugalContribution = ...
    -b .* (normalizedSpeed.^2 - nRef.^2);
lookupInfo.query = struct('Np_rpm',npRpm,'Ng_rpm',ngRpm, ...
    'Tt1_K',inletTtK,'inletCorrectedNp_rpm',correctedNpRpm, ...
    'inletCorrectedNg_rpm',correctedNgRpm,'loadPower_W',loadPowerW);
lookupInfo.nearestPointFallback = struct();
lookupInfo.nearestPointFallback.used = cellfun(@(x)x.used,fallback);
for i = 1:6
    lookupInfo.nearestPointFallback.(componentNames{i}) = fallback{i};
end
end

function [cache, enabled] = local_split_runtime_cache(referenceTable)
enabled = isfield(referenceTable, 'runtimeInterpolationCache');
if ~enabled
    cache = struct();
    return;
end
cache = referenceTable.runtimeInterpolationCache;
componentNames = {'AC','CC','GT1','GT2','PT1','PT2'};
if ~isstruct(cache) || ~isfield(cache,'version') || ...
        ~strcmp(cache.version,'epsilon-ss-runtime-interpolation-split6-v1')
    error('SHT:ClearanceSchedule:InvalidRuntimeCache', ...
        '六部件epsilon_ss运行时插值缓存版本无效。');
end
for i = 1:numel(componentNames)
    name = componentNames{i};
    if ~isfield(cache,name) || ~isfield(cache.(name),'interpolant')
        error('SHT:ClearanceSchedule:InvalidRuntimeCache', ...
            '六部件epsilon_ss缓存缺少%s。',name);
    end
end
end

function [value, fallback] = local_interp2_or_nearest_named( ...
    speedGrid,powerGrid,tableValue,speedQuery,powerQuery,prepared,componentName)
% 复用二维数学规则，但把告警中的部件名称从历史PT改为PT1/PT2。
if nargin < 6
    prepared = [];
end
speedGrid = speedGrid(:);
powerGrid = powerGrid(:);
tableValue = tableValue(:);
if isempty(prepared)
    if numel(speedGrid)<3 || numel(speedGrid)~=numel(powerGrid) || ...
            numel(speedGrid)~=numel(tableValue) || ...
            any(~isfinite(speedGrid)) || any(~isfinite(powerGrid)) || ...
            any(~isfinite(tableValue))
        error('SHT:ClearanceSchedule:SchemaMismatch', ...
            '%s二维参考表节点无效。',componentName);
    end
    speedSpan = max(speedGrid)-min(speedGrid);
    powerSpan = max(powerGrid)-min(powerGrid);
    if speedSpan<=0 || powerSpan<=0
        error('SHT:ClearanceSchedule:SchemaMismatch', ...
            '%s二维参考表坐标跨度必须大于零。',componentName);
    end
    interpolant = scatteredInterpolant(speedGrid,powerGrid, ...
        tableValue,'linear','none');
else
    speedSpan = prepared.speedSpan_rpm;
    powerSpan = prepared.powerSpan_W;
    interpolant = prepared.interpolant;
end
speedQuery = local_snap_roundoff_at_boundary(speedQuery,speedGrid);
powerQuery = local_snap_roundoff_at_boundary(powerQuery,powerGrid);
value = interpolant(speedQuery,powerQuery);
fallback = struct('used',false,'nodeIndex',NaN, ...
    'queryCoordinate',[speedQuery,powerQuery], ...
    'usedCoordinate',[NaN,NaN],'thermalValue',NaN, ...
    'normalizedDistance',0);
if ~isfinite(value)
    distanceSquared = ((speedGrid-speedQuery)./speedSpan).^2 + ...
        ((powerGrid-powerQuery)./powerSpan).^2;
    [minimumDistanceSquared,index] = min(distanceSquared);
    value = tableValue(index);
    fallback.used = true;
    fallback.nodeIndex = index;
    fallback.usedCoordinate = [speedGrid(index),powerGrid(index)];
    fallback.thermalValue = value;
    fallback.normalizedDistance = sqrt(minimumDistanceSquared);
end
message = '';
if fallback.used
    message = sprintf(['%s epsilon_ss查询超出二维线性插值覆盖域：' ...
        '修正Np=%.15g rpm，负载=%.15g W；采用最近表点[%.15g, %.15g]。'], ...
        componentName,speedQuery,powerQuery, ...
        fallback.usedCoordinate(1),fallback.usedCoordinate(2));
end
local_update_fallback_warning(componentName,fallback.used,message);
end
