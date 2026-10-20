function result = sht_startstop_write_candidate_maps(cfg, theta, outputDir)
%SHT_STARTSTOP_WRITE_CANDIDATE_MAPS 生成并硬检查一组阶段五候选特性图。
%
% theta每个部件两个参数，仅控制新增低速区。函数先在内存中完成零速边界、
% 有限性、连接连续性和原图区逐元素冻结检查；任一硬检查失败时不把候选
% 标记为可供DLL评价。输入原图始终只读，输出写入独立运行目录。

theta = theta(:).';
assert(numel(theta) == 2*numel(cfg.topology.componentNames), ...
    '阶段五候选参数个数与模型拓扑不一致。');
assert(all(isfinite(theta)), '阶段五候选参数出现NaN/Inf。');
if ~isfolder(outputDir)
    mkdir(outputDir);
end

lower = cfg.stage5.calibrationLowerBound;
upper = cfg.stage5.calibrationUpperBound;
withinBounds = all(theta >= lower) && all(theta <= upper);
extension = sht_startstop_map_parameters(cfg,theta);
names = cfg.topology.componentNames;
items = repmat(struct(), numel(names), 1);
smoothness = 0;
for i = 1:numel(names)
    name = names{i};
    definition = cfg.maps.(name);
    sourcePath = fullfile(cfg.paths.cRoot, definition.sourceName);
    if strcmp(definition.kind, 'compressor')
        readAction = 'readCompressor';
        writeAction = 'writeCompressor';
    elseif strcmp(definition.kind, 'turbine')
        readAction = 'readTurbine';
        writeAction = 'writeTurbine';
    else
        error('未知特性图类型：%s。', definition.kind);
    end
    original = sht_tmats_map_io(readAction, sourcePath);
    if strcmp(definition.kind, 'compressor')
        [extended, physicsAudit] = sht_startstop_extend_compressor_map( ...
            original, extension.(name), cfg.mapIO);
    else
        [extended, physicsAudit] = sht_startstop_extend_turbine_map( ...
            original, extension.(name), cfg.mapIO);
    end
    outputPath = fullfile(outputDir, definition.outputName);
    sht_tmats_map_io(writeAction, outputPath, extended, '%.17g');
    reread = sht_tmats_map_io(readAction, outputPath);
    roundTripAudit = sht_tmats_map_io('compare', extended, reread, ...
        cfg.mapIO.roundTripTolerance);
    originalRegionAudit = local_original_region_audit(original, reread, ...
        cfg.mapIO.originalRegionTolerance);
    shapeAudit = local_shape_audit(original, reread);
    itemAccepted = withinBounds && physicsAudit.accepted && ...
        roundTripAudit.accepted && originalRegionAudit.accepted && ...
        shapeAudit.accepted;

    items(i).name = name;
    items(i).kind = definition.kind;
    items(i).sourcePath = sourcePath;
    items(i).outputPath = outputPath;
    items(i).physicsAudit = physicsAudit;
    items(i).roundTripAudit = roundTripAudit;
    items(i).originalRegionAudit = originalRegionAudit;
    items(i).shapeAudit = shapeAudit;
    items(i).accepted = itemAccepted;
    smoothness = smoothness + shapeAudit.smoothnessPenalty;
end

result = struct('theta', theta, 'extension', extension, 'items', items, ...
    'withinBounds', withinBounds, 'smoothnessPenalty', smoothness, ...
    'accepted', withinBounds && all([items.accepted]), ...
    'outputDir', outputDir);
end

function audit = local_original_region_audit(original, extended, tolerance)
audit = sht_startstop_original_region_audit(original, extended, tolerance);
end

function index = local_axis_indices(fullAxis, originalAxis, tolerance)
index = zeros(size(originalAxis));
for i = 1:numel(originalAxis)
    [difference, nearest] = min(abs(fullAxis - originalAxis(i)));
    assert(difference <= max(tolerance, 64 * eps(max(1, ...
        abs(originalAxis(i))))), '扩展图缺少原始坐标节点。');
    index(i) = nearest;
end
end

function audit = local_shape_audit(original, extended)
axisTolerance = 64 * eps(max(1, max(abs(original.nc))));
lowSpeedIndex = find(extended.nc < original.nc(1) - axisTolerance);
assert(~isempty(lowSpeedIndex), '候选图没有新增低速转速线。');
originalSpeedIndex = local_axis_indices(extended.nc, original.nc, 0);
index = [lowSpeedIndex, originalSpeedIndex(1)];
nc = extended.nc(index);
Wc = extended.Wc(index, :);
Eff = extended.Eff(index, :);
finite = all(isfinite([nc(:); Wc(:); Eff(:)]));
axisOrdered = all(diff(nc) > 0) && all(diff(extended.path) > 0);
if strcmp(original.kind, 'compressor')
    pressure = extended.PR(index, :);
    finite = finite && all(isfinite(pressure(:))) && all(pressure(:) > 0);
    % 高Rline尾部由末端斜率单独约束，不应把其放大的绝对差异误作低速
    % 转速线连接断裂。连接检查只在原图Rline节点上进行。
    originalPathIndex = local_axis_indices(extended.path, original.path, 0);
    connectionRelative = max([local_relative_jump( ...
        Wc(end - 1, originalPathIndex), Wc(end, originalPathIndex)), ...
        local_relative_jump(pressure(end - 1, originalPathIndex), ...
        pressure(end, originalPathIndex)), ...
        local_relative_jump(Eff(end - 1, originalPathIndex), ...
        Eff(end, originalPathIndex))]);
    smoothness = local_surface_smoothness(Wc) + ...
        local_surface_smoothness(pressure) + local_surface_smoothness(Eff);
else
    pressure = [extended.minPR(index); extended.maxPR(index)];
    finite = finite && all(isfinite(pressure(:))) && ...
        all(extended.minPR(index) >= 1) && ...
        all(extended.maxPR(index) > extended.minPR(index));
    % beta边缘新增节点描述PR=1和堵塞尾部，其位置随Nc变化，不能用
    % 固定beta列的相对跳变量代替物理连续性。连接门限在原beta节点上
    % 评价；新增节点另由有限性、轴有序性和整体曲率约束。
    originalPathIndex = local_axis_indices( ...
        extended.path, original.path, 0);
    connectionRelative = max([local_relative_jump( ...
        Wc(end - 1, originalPathIndex), Wc(end, originalPathIndex)), ...
        local_relative_jump(Eff(end - 1, originalPathIndex), ...
        Eff(end, originalPathIndex)), ...
        local_relative_jump(extended.minPR(index(end - 1)), ...
        extended.minPR(index(end))), ...
        local_relative_jump(extended.maxPR(index(end - 1)), ...
        extended.maxPR(index(end)))]);
    smoothness = local_surface_smoothness(Wc) + ...
        local_surface_smoothness(Eff) + ...
        local_curve_smoothness(extended.minPR(index)) + ...
        local_curve_smoothness(extended.maxPR(index));
end
% 0.92倍原最低转速处采用smoothstep连接，最后一步相对跃变量应远小于
% 普通外推差异。5%只拦截明显断裂，不把斜率先验误当成型号事实。
connectionAccepted = connectionRelative <= 0.05;
audit = struct('finite', finite, 'axisOrdered', axisOrdered, ...
    'connectionMaximumRelative', connectionRelative, ...
    'connectionAccepted', connectionAccepted, ...
    'smoothnessPenalty', smoothness, ...
    'accepted', finite && axisOrdered && connectionAccepted);
end

function value = local_relative_jump(a, b)
value = max(abs(a(:) - b(:)) ./ max([abs(a(:)), abs(b(:)), ...
    1e-12 * ones(numel(a), 1)], [], 2));
end

function value = local_surface_smoothness(surface)
scale = max(max(surface(:)) - min(surface(:)), 1e-12);
if size(surface, 1) < 3
    value = 0;
else
    value = mean((diff(surface, 2, 1) / scale) .^ 2, 'all');
end
end

function value = local_curve_smoothness(curve)
scale = max(max(curve) - min(curve), 1e-12);
if numel(curve) < 3
    value = 0;
else
    value = mean((diff(curve, 2) / scale) .^ 2);
end
end
