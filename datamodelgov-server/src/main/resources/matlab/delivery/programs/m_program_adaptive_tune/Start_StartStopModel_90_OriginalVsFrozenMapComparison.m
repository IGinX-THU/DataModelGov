function result = Start_StartStopModel_90_OriginalVsFrozenMapComparison(userCfg)
%START_STARTSTOPMODEL_90_ORIGINALVSFROZENMAPCOMPARISON
% 绘制六部件原始特性图与阶段五冻结扩展图，并审计原图区是否保持不变。
%
% 运行方法：
%   result = Start_StartStopModel_90_OriginalVsFrozenMapComparison();
%
% 默认读取最近一次已通过的阶段五结果。若需指定冻结版本：
%   userCfg.mapComparison.stage5RunRoot = ...
%       fullfile('C:\VSCode\Report\StartupStop\report_outputs', ...
%       'StartupStop', 'Stage05_20260825_030059');
%   result = Start_StartStopModel_90_OriginalVsFrozenMapComparison(userCfg);
%
% 原图优先取阶段一随该阶段五结果冻结的只读快照，而不是当前工作目录中
% 同名源文件。这样即使日后替换六部件原图，本次对比仍可准确复现当时
% “原图 -> 扩展并冻结图”的关系。

if nargin < 1
    userCfg = struct();
end

cfg = sht_startstop_default_config(userCfg);
if isempty(cfg.mapComparison.stage5RunRoot)
    [stage5Result,stage5]=sht_startstop_stage_asset('load','stage05',cfg);
else
    stage5 = local_resolve_stage5(cfg);
    loadedStage5 = load(stage5.resultPath, 'result');
    stage5Result = loadedStage5.result;
end
assert(stage5Result.accepted, '指定阶段五结果未通过，不能作为冻结图基线。');

stage12Result = local_load_stage12(stage5Result);
timeTag = datestr(now, 'yyyymmdd_HHMMSS');
runRoot = fullfile(cfg.paths.outputRoot, ['MapComparison_', timeTag]);
figureDir = fullfile(runRoot, 'figures');
mkdir(runRoot);
mkdir(figureDir);

names = {'AC', 'CC', 'GT1', 'GT2', 'PT1', 'PT2'};
items = repmat(local_item_template(), numel(names), 1);
for i = 1:numel(names)
    name = names{i};
    definition = cfg.maps.(name);
    originalPath = local_original_snapshot_path( ...
        name, definition, stage12Result, cfg);
    frozenPath = local_frozen_map_path( ...
        name, definition, stage5Result, stage5.runRoot);
    readAction = local_read_action(definition.kind);
    original = sht_tmats_map_io(readAction, originalPath);
    frozen = sht_tmats_map_io(readAction, frozenPath);
    assert(strcmp(original.kind, frozen.kind), ...
        '%s 原图与冻结图类型不一致。', name);

    audit = local_original_region_audit(original, frozen, ...
        cfg.mapIO.originalRegionTolerance);
    individualPath = fullfile(figureDir, ...
        [name, '_original_vs_frozen.png']);
    local_plot_individual(name, original, frozen, individualPath, cfg);

    items(i).name = name;
    items(i).kind = definition.kind;
    items(i).originalPath = originalPath;
    items(i).frozenPath = frozenPath;
    items(i).originalSpeedLineCount = numel(original.nc);
    items(i).frozenSpeedLineCount = numel(frozen.nc);
    items(i).addedSpeedLineCount = numel(frozen.nc) - numel(original.nc);
    items(i).originalPathNodeCount = numel(original.path);
    items(i).frozenPathNodeCount = numel(frozen.path);
    items(i).addedPathNodeCount = numel(frozen.path) - numel(original.path);
    items(i).originalMinimumSpeed = original.nc(1);
    items(i).frozenMinimumSpeed = frozen.nc(1);
    items(i).originalRegionMaximumAbsolute = audit.maximumAbsolute;
    items(i).originalRegionAccepted = audit.accepted;
    items(i).audit = audit;
    items(i).figurePath = individualPath;
end

overviewPath = fullfile(figureDir, ...
    'six_component_original_vs_frozen_overview.png');
overviewFigure = local_plot_overview(items, overviewPath, cfg);
summaryTable = local_summary_table(items);
csvPath = fullfile(runRoot, 'map_comparison_audit.csv');
writetable(summaryTable, csvPath);
summaryPath = fullfile(runRoot, 'map_comparison_summary.md');
accepted = all([items.originalRegionAccepted]) && ...
    all([items.addedSpeedLineCount] > 0);
local_write_summary(summaryPath, stage5, items, overviewPath, accepted);

result = struct('generatedAt', datestr(now, 31), 'runRoot', runRoot, ...
    'stage5Source', stage5, 'items', items, ...
    'summaryTable', summaryTable, 'csvPath', csvPath, ...
    'summaryPath', summaryPath, 'overviewPath', overviewPath, ...
    'accepted', accepted);
save(fullfile(runRoot, 'map_comparison_result.mat'), 'result', '-v7');

fprintf('\n=== 六部件原图与阶段五冻结图对比 ===\n');
fprintf('阶段五来源：%s\n', stage5.runRoot);
for i = 1:numel(items)
    fprintf(['%-3s：转速线 %d -> %d（新增 %d），路径节点 %d -> %d', ...
        '（新增 %d），原图区最大差 %.3e，%s\n'], ...
        items(i).name, items(i).originalSpeedLineCount, ...
        items(i).frozenSpeedLineCount, items(i).addedSpeedLineCount, ...
        items(i).originalPathNodeCount, items(i).frozenPathNodeCount, ...
        items(i).addedPathNodeCount, ...
        items(i).originalRegionMaximumAbsolute, ...
        local_pass(items(i).originalRegionAccepted));
end
fprintf('总体审计：%s\n', local_pass(accepted));
fprintf('总览图：%s\n', overviewPath);
fprintf('结果目录：%s\n\n', runRoot);

if ~cfg.mapComparison.showFigures && isgraphics(overviewFigure)
    close(overviewFigure);
end
end

function latest = local_resolve_stage5(cfg)
requested = cfg.mapComparison.stage5RunRoot;
if ~isempty(requested)
    resultPath = fullfile(requested, 'stage05_complete_result.mat');
    assert(isfile(resultPath), '指定目录缺少阶段五完整结果：%s。', resultPath);
    loaded = load(resultPath, 'result');
    assert(isfield(loaded, 'result') && isfield(loaded.result, 'accepted') && ...
        loaded.result.accepted, '指定阶段五结果未通过验收：%s。', requested);
    latest = struct('runRoot', requested, 'resultPath', resultPath);
    return;
end

entries = dir(fullfile(cfg.paths.outputRoot, 'Stage05_*'));
entries = entries([entries.isdir]);
assert(~isempty(entries), '没有阶段五结果，请先运行Start_StartStopModel_03。');
[~, order] = sort([entries.datenum], 'descend');
for i = order
    runRoot = fullfile(entries(i).folder, entries(i).name);
    resultPath = fullfile(runRoot, 'stage05_complete_result.mat');
    if ~isfile(resultPath)
        continue;
    end
    loaded = load(resultPath, 'result');
    if isfield(loaded, 'result') && isfield(loaded.result, 'accepted') && ...
            loaded.result.accepted
        latest = struct('runRoot', runRoot, 'resultPath', resultPath);
        return;
    end
end
error('没有找到已通过的完整阶段五结果。');
end

function stage12Result = local_load_stage12(stage5Result)
assert(isfield(stage5Result, 'stage12Source') && ...
    isfield(stage5Result.stage12Source, 'resultPath'), ...
    '阶段五结果缺少阶段一/二来源记录。');
path = stage5Result.stage12Source.resultPath;
assert(isfile(path), '阶段一/二来源结果不存在：%s。', path);
loaded = load(path, 'result');
assert(isfield(loaded, 'result') && isfield(loaded.result, 'mapResult'), ...
    '阶段一/二来源结果结构不完整：%s。', path);
stage12Result = loaded.result;
end

function path = local_original_snapshot_path(name, definition, stage12, cfg)
path = '';
items = stage12.mapResult.items;
index = find(strcmp({items.name}, name), 1, 'first');
if ~isempty(index) && isfield(items(index), 'snapshotPath') && ...
        isfile(items(index).snapshotPath)
    path = items(index).snapshotPath;
end
if isempty(path)
    % 仅兼容早期未保存快照的结果；当前正式流程都会走上面的快照路径。
    path = fullfile(cfg.paths.cRoot, definition.sourceName);
end
assert(isfile(path), '%s 原始特性图或其冻结快照不存在：%s。', name, path);
end

function path = local_frozen_map_path(name, definition, stage5Result, runRoot)
path = '';
if isfield(stage5Result, 'finalMapAudit') && ...
        isfield(stage5Result.finalMapAudit, 'items')
    items = stage5Result.finalMapAudit.items;
    index = find(strcmp({items.name}, name), 1, 'first');
    if ~isempty(index) && isfield(items(index), 'outputPath') && ...
            isfile(items(index).outputPath)
        path = items(index).outputPath;
    end
end
if isempty(path)
    path = fullfile(runRoot, 'maps_calibrated', definition.outputName);
end
assert(isfile(path), '%s 阶段五冻结特性图不存在：%s。', name, path);
end

function action = local_read_action(kind)
if strcmp(kind, 'compressor')
    action = 'readCompressor';
elseif strcmp(kind, 'turbine')
    action = 'readTurbine';
else
    error('未知特性图类型：%s。', kind);
end
end

function audit = local_original_region_audit(original, frozen, tolerance)
audit = sht_startstop_original_region_audit(original, frozen, tolerance);
end


function local_plot_individual(name, original, frozen, path, cfg)
f = figure('Visible', 'off', 'Color', 'w', ...
    'Name', [name, ' 原图与冻结图对比'], 'NumberTitle', 'off', ...
    'Position', [80, 80, 1320, 560]);
cleanup = onCleanup(@() close(f));
ax1 = subplot(1, 2, 1, 'Parent', f);
local_plot_pressure(ax1, name, original, frozen, true);
ax2 = subplot(1, 2, 2, 'Parent', f);
local_plot_efficiency(ax2, name, original, frozen, false);
sgtitle(f, [name, ' 原特性图与阶段五冻结扩展图']);
print(f, path, '-dpng', local_resolution_argument(cfg));
clear cleanup;
end

function figureHandle = local_plot_overview(items, path, cfg)
visible = local_visibility(cfg.mapComparison.showFigures);
figureHandle = figure('Visible', visible, 'Color', 'w', ...
    'Name', '六部件原图与阶段五冻结图对比', 'NumberTitle', 'off', ...
    'Position', [30, 30, 1880, 1120]);
for i = 1:numel(items)
    original = sht_tmats_map_io(local_read_action(items(i).kind), ...
        items(i).originalPath);
    frozen = sht_tmats_map_io(local_read_action(items(i).kind), ...
        items(i).frozenPath);
    ax1 = subplot(3, 4, 2 * i - 1, 'Parent', figureHandle);
    local_plot_pressure(ax1, items(i).name, original, frozen, i == 1);
    ax2 = subplot(3, 4, 2 * i, 'Parent', figureHandle);
    local_plot_efficiency(ax2, items(i).name, original, frozen, false);
end
sgtitle(figureHandle, ...
    '六部件原特性图与阶段五冻结扩展图（黑虚线：原图；蓝线：冻结图原转速线；红线：新增转速线）');
print(figureHandle, path, '-dpng', local_resolution_argument(cfg));
drawnow;
end

function local_plot_pressure(ax, name, original, frozen, showLegend)
hold(ax, 'on');
newMask = local_new_speed_mask(frozen.nc, original.nc);
oldMask = ~newMask;
if strcmp(original.kind, 'compressor')
    xFrozen = frozen.Wc;
    yFrozen = frozen.PR;
    xOriginal = original.Wc;
    yOriginal = original.PR;
    xLabel = 'W_c';
    yLabel = 'PR';
else
    xFrozen = local_turbine_pr(frozen);
    yFrozen = frozen.Wc;
    xOriginal = local_turbine_pr(original);
    yOriginal = original.Wc;
    xLabel = 'PR';
    yLabel = 'W_c';
end
handles = local_plot_comparison_rows(ax, xFrozen, yFrozen, ...
    xOriginal, yOriginal, oldMask, newMask);
xlabel(ax, xLabel);
ylabel(ax, yLabel);
title(ax, [name, ' 流量/压比']);
grid(ax, 'on');
if showLegend
    legend(ax, handles, {'冻结图原转速线', '新增转速线', '原图'}, ...
        'Location', 'best');
end
end

function local_plot_efficiency(ax, name, original, frozen, showLegend)
hold(ax, 'on');
newMask = local_new_speed_mask(frozen.nc, original.nc);
oldMask = ~newMask;
if strcmp(original.kind, 'compressor')
    xFrozen = frozen.Wc;
    xOriginal = original.Wc;
    xLabel = 'W_c';
else
    xFrozen = local_turbine_pr(frozen);
    xOriginal = local_turbine_pr(original);
    xLabel = 'PR';
end
handles = local_plot_comparison_rows(ax, xFrozen, frozen.Eff, ...
    xOriginal, original.Eff, oldMask, newMask);
xlabel(ax, xLabel);
ylabel(ax, 'Efficiency');
title(ax, [name, ' 效率']);
grid(ax, 'on');
if showLegend
    legend(ax, handles, {'冻结图原转速线', '新增转速线', '原图'}, ...
        'Location', 'best');
end
end

function handles = local_plot_comparison_rows(ax, xFrozen, yFrozen, ...
        xOriginal, yOriginal, oldMask, newMask)
frozenColor = [0.20, 0.45, 0.75];
newColor = [0.86, 0.20, 0.13];
originalColor = [0.08, 0.08, 0.08];
hFrozen = plot(ax, nan, nan, '-', 'Color', frozenColor, ...
    'LineWidth', 0.8);
hNew = plot(ax, nan, nan, '-', 'Color', newColor, 'LineWidth', 1.0);
hOriginal = plot(ax, nan, nan, '--', 'Color', originalColor, ...
    'LineWidth', 1.15);
local_plot_selected_rows(ax, xFrozen, yFrozen, oldMask, ...
    '-', frozenColor, 0.8);
local_plot_selected_rows(ax, xFrozen, yFrozen, newMask, ...
    '-', newColor, 1.0);
local_plot_selected_rows(ax, xOriginal, yOriginal, ...
    true(size(xOriginal, 1), 1), '--', originalColor, 1.15);
handles = [hFrozen, hNew, hOriginal];
end

function local_plot_selected_rows(ax, x, y, mask, style, color, width)
indices = find(mask(:).');
for i = indices
    plot(ax, x(i, :), y(i, :), style, 'Color', color, ...
        'LineWidth', width);
end
end

function mask = local_new_speed_mask(fullAxis, originalAxis)
mask = true(size(fullAxis));
for i = 1:numel(originalAxis)
    [difference, nearest] = min(abs(fullAxis - originalAxis(i)));
    tolerance = 64 * eps(max(1, abs(originalAxis(i))));
    assert(difference <= tolerance, ...
        '冻结图缺少原始转速节点 %.17g。', originalAxis(i));
    mask(nearest) = false;
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

function tableOut = local_summary_table(items)
count = numel(items);
Component = cell(count, 1);
Kind = cell(count, 1);
OriginalFile = cell(count, 1);
FrozenFile = cell(count, 1);
OriginalSpeedLines = zeros(count, 1);
FrozenSpeedLines = zeros(count, 1);
AddedSpeedLines = zeros(count, 1);
OriginalPathNodes = zeros(count, 1);
FrozenPathNodes = zeros(count, 1);
AddedPathNodes = zeros(count, 1);
OriginalRegionMaximumAbsolute = zeros(count, 1);
OriginalRegionAccepted = false(count, 1);
for i = 1:count
    Component{i} = items(i).name;
    Kind{i} = items(i).kind;
    OriginalFile{i} = items(i).originalPath;
    FrozenFile{i} = items(i).frozenPath;
    OriginalSpeedLines(i) = items(i).originalSpeedLineCount;
    FrozenSpeedLines(i) = items(i).frozenSpeedLineCount;
    AddedSpeedLines(i) = items(i).addedSpeedLineCount;
    OriginalPathNodes(i) = items(i).originalPathNodeCount;
    FrozenPathNodes(i) = items(i).frozenPathNodeCount;
    AddedPathNodes(i) = items(i).addedPathNodeCount;
    OriginalRegionMaximumAbsolute(i) = ...
        items(i).originalRegionMaximumAbsolute;
    OriginalRegionAccepted(i) = items(i).originalRegionAccepted;
end
tableOut = table(Component, Kind, OriginalFile, FrozenFile, ...
    OriginalSpeedLines, FrozenSpeedLines, AddedSpeedLines, ...
    OriginalPathNodes, FrozenPathNodes, AddedPathNodes, ...
    OriginalRegionMaximumAbsolute, OriginalRegionAccepted);
end

function local_write_summary(path, stage5, items, overviewPath, accepted)
fid = fopen(path, 'w', 'n', 'UTF-8');
assert(fid >= 0, '无法写入特性图对比摘要：%s。', path);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# 六部件原图与阶段五冻结图对比摘要\n\n');
fprintf(fid, '- 生成时间：%s\n', datestr(now, 31));
fprintf(fid, '- 阶段五来源：`%s`\n', stage5.runRoot);
fprintf(fid, '- 原图口径：该阶段五所继承阶段一保存的原图快照。\n');
fprintf(fid, '- 总体审计：**%s**\n', local_pass(accepted));
fprintf(fid, '- 总览图：`%s`\n\n', overviewPath);
fprintf(fid, ['|部件|原/冻结转速线|新增转速线|原/冻结路径节点|', ...
    '新增路径节点|原图区最大绝对差|冻结审计|\n']);
fprintf(fid, '|---|---:|---:|---:|---:|---:|---|\n');
for i = 1:numel(items)
    item = items(i);
    fprintf(fid, '|%s|%d/%d|%d|%d/%d|%d|%.3e|%s|\n', ...
        item.name, item.originalSpeedLineCount, ...
        item.frozenSpeedLineCount, item.addedSpeedLineCount, ...
        item.originalPathNodeCount, item.frozenPathNodeCount, ...
        item.addedPathNodeCount, item.originalRegionMaximumAbsolute, ...
        local_pass(item.originalRegionAccepted));
end
fprintf(fid, ['\n冻结审计通过只证明原图区逐元素未改变且冻结图确实增加了', ...
    '转速线；连续起停能否通过仍由阶段六独立验收。\n']);
end

function item = local_item_template()
item = struct('name', '', 'kind', '', 'originalPath', '', ...
    'frozenPath', '', 'originalSpeedLineCount', 0, ...
    'frozenSpeedLineCount', 0, 'addedSpeedLineCount', 0, ...
    'originalPathNodeCount', 0, 'frozenPathNodeCount', 0, ...
    'addedPathNodeCount', 0, 'originalMinimumSpeed', NaN, ...
    'frozenMinimumSpeed', NaN, 'originalRegionMaximumAbsolute', Inf, ...
    'originalRegionAccepted', false, 'audit', struct(), ...
    'figurePath', '');
end

function argument = local_resolution_argument(cfg)
argument = sprintf('-r%d', cfg.mapComparison.imageResolutionDpi);
end

function value = local_visibility(showFigures)
if showFigures
    value = 'on';
else
    value = 'off';
end
end

function value = local_pass(tf)
if tf
    value = 'PASS';
else
    value = 'FAIL';
end
end
