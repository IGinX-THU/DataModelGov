function audit = sht_startstop_original_region_audit(original, frozen, tolerance)
speedIndex = local_axis_indices(frozen.nc, original.nc, tolerance);
pathIndex = local_axis_indices(frozen.path, original.path, tolerance);
audit = struct();
audit.addedLineCount = numel(frozen.nc)-numel(original.nc);
audit.addedPathNodeCount = numel(frozen.path)-numel(original.path);
audit.speedAxisMaximumAbsolute = max(abs( ...
    frozen.nc(speedIndex) - original.nc));
audit.pathAxisMaximumAbsolute = max(abs( ...
    frozen.path(pathIndex) - original.path));
audit.flowMaximumAbsolute = local_max_abs( ...
    frozen.Wc(speedIndex, pathIndex) - original.Wc);
audit.efficiencyMaximumAbsolute = local_max_abs( ...
    frozen.Eff(speedIndex, pathIndex) - original.Eff);
if strcmp(original.kind, 'compressor')
    audit.pressureMaximumAbsolute = local_max_abs( ...
        frozen.PR(speedIndex, pathIndex) - original.PR);
    audit.pressureEndpointMaximumAbsolute = 0;
    audit.surgeFlowMaximumAbsolute = max(abs( ...
        frozen.surgeWc(speedIndex) - original.surgeWc));
    audit.surgePressureMaximumAbsolute = max(abs( ...
        frozen.surgePR(speedIndex) - original.surgePR));
else
    originalPR = local_turbine_pr(original);
    frozenPR = local_turbine_pr(frozen);
    audit.pressureMaximumAbsolute = local_max_abs( ...
        frozenPR(speedIndex, pathIndex) - originalPR);
    audit.pressureEndpointMaximumAbsolute = max([max(abs( ...
        frozen.minPR(speedIndex) - original.minPR)), max(abs( ...
        frozen.maxPR(speedIndex) - original.maxPR))]);
    audit.surgeFlowMaximumAbsolute = 0;
    audit.surgePressureMaximumAbsolute = 0;
end
audit.maximumAbsolute = max([audit.speedAxisMaximumAbsolute, ...
    audit.pathAxisMaximumAbsolute, audit.flowMaximumAbsolute, ...
    audit.efficiencyMaximumAbsolute, audit.pressureMaximumAbsolute, ...
    audit.pressureEndpointMaximumAbsolute, ...
    audit.surgeFlowMaximumAbsolute, audit.surgePressureMaximumAbsolute]);
audit.tolerance = tolerance;
audit.accepted = audit.maximumAbsolute <= tolerance;
end

function index = local_axis_indices(fullAxis, originalAxis, tolerance)
index = zeros(size(originalAxis));
for i = 1:numel(originalAxis)
    [difference, nearest] = min(abs(fullAxis - originalAxis(i)));
    numericalTolerance = 64 * eps(max(1, abs(originalAxis(i))));
    assert(difference <= max(tolerance, numericalTolerance), ...
        '冻结图缺少原始坐标节点 %.17g。', originalAxis(i));
    index(i) = nearest;
end
end

function value = local_turbine_pr(map)
if isfield(map, 'PR') && ~isempty(map.PR)
    value = map.PR;
else
    beta = (map.path - map.path(1)) / ...
        max(map.path(end) - map.path(1), eps);
    value = map.minPR(:) + (map.maxPR(:) - map.minPR(:)) .* beta;
end
end


function v = local_max_abs(x)
v=max(abs(x(:)));
end
