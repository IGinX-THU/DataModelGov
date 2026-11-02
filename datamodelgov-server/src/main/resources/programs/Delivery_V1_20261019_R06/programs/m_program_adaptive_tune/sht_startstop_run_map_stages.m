function result = sht_startstop_run_map_stages(cfg, runRoot)
%SHT_STARTSTOP_RUN_MAP_STAGES 执行阶段一读写验收和阶段二低速扩图。

stage1Dir = fullfile(runRoot, 'stage01_map_io');
stage2Dir = fullfile(runRoot, 'stage02_low_speed_maps');
snapshotDir = fullfile(stage1Dir, 'maps_original_snapshot');
roundTripDir = fullfile(stage1Dir, 'maps_roundtrip');
extendedDir = fullfile(stage2Dir, 'maps_extended');
figureDir = fullfile(stage2Dir, 'figures');
local_make_dirs({stage1Dir, stage2Dir, snapshotDir, roundTripDir, ...
    extendedDir, figureDir});

names = cfg.topology.componentNames;
items = repmat(struct(), numel(names), 1);
for i = 1:numel(names)
    name = names{i};
    definition = cfg.maps.(name);
    sourcePath = fullfile(cfg.paths.cRoot, definition.sourceName);
    assert(isfile(sourcePath), '缺少%s输入特性图：%s', name, sourcePath);

    snapshotPath = fullfile(snapshotDir, ...
        sprintf('%s__%s', name, definition.sourceName));
    copyfile(sourcePath, snapshotPath, 'f');

    readAction = ['read', upper(definition.kind(1)), definition.kind(2:end)];
    writeAction = ['write', upper(definition.kind(1)), definition.kind(2:end)];
    original = sht_tmats_map_io(readAction, sourcePath);
    roundTripPath = fullfile(roundTripDir, ...
        sprintf('%s_roundtrip.MAP', name));
    sht_tmats_map_io(writeAction, roundTripPath, original, '%.17g');
    roundTrip = sht_tmats_map_io(readAction, roundTripPath);
    roundTripAudit = sht_tmats_map_io('compare', original, roundTrip, ...
        cfg.mapIO.roundTripTolerance);

    if strcmp(definition.kind, 'compressor')
        [extended, physicsAudit] = ...
            sht_startstop_extend_compressor_map(original, ...
            cfg.extension.(name), cfg.mapIO);
    else
        [extended, physicsAudit] = ...
            sht_startstop_extend_turbine_map(original, ...
            cfg.extension.(name), cfg.mapIO);
    end
    outputPath = fullfile(extendedDir, definition.outputName);
    sht_tmats_map_io(writeAction, outputPath, extended, '%.17g');
    reread = sht_tmats_map_io(readAction, outputPath);
    extendedRoundTripAudit = sht_tmats_map_io('compare', extended, reread, ...
        cfg.mapIO.roundTripTolerance);
    originalRegionAudit = local_original_region_audit( ...
        original, reread, cfg.mapIO.originalRegionTolerance);
    if cfg.mapIO.generateFigures
        figurePath = local_plot_map(name, original, reread, figureDir,cfg.mapIO);
    else
        figurePath = '';
    end

    items(i).name = name;
    items(i).kind = definition.kind;
    items(i).sourcePath = sourcePath;
    items(i).sourceSha256 = local_sha256(sourcePath);
    items(i).snapshotPath = snapshotPath;
    items(i).roundTripPath = roundTripPath;
    items(i).outputPath = outputPath;
    items(i).outputSha256 = local_sha256(outputPath);
    items(i).originalMinimumSpeed = original.nc(1);
    items(i).extendedMinimumSpeed = reread.nc(1);
    items(i).addedSpeedLineCount = numel(reread.nc) - numel(original.nc);
    items(i).roundTripAudit = roundTripAudit;
    items(i).extendedRoundTripAudit = extendedRoundTripAudit;
    items(i).originalRegionAudit = originalRegionAudit;
    items(i).physicsAudit = physicsAudit;
    items(i).figurePath = figurePath;
    items(i).accepted = roundTripAudit.accepted && ...
        extendedRoundTripAudit.accepted && originalRegionAudit.accepted && ...
        physicsAudit.accepted;
end

result = struct();
result.items = items;
result.stage1Accepted = all(arrayfun(@(x) x.roundTripAudit.accepted, items));
result.stage2Accepted = all(arrayfun(@(x) x.accepted, items));
result.extendedMapDir = extendedDir;
result.summaryPath = fullfile(runRoot, 'stage12_map_summary.md');
local_write_summary(result.summaryPath, result);
save(fullfile(runRoot, 'stage12_map_result.mat'), 'result', '-v7');
end

function audit = local_original_region_audit(original, extended, tolerance)
audit = sht_startstop_original_region_audit(original, extended, tolerance);
end

function path = local_plot_map(name, original, extended, outputDir,options)
visibility='off';
if isfield(options,'showFigures') && options.showFigures,visibility='on';end
figureHandle = figure('Visible', visibility, 'Color', 'w', ...
    'Position', [100, 100, 1180, 760]);
if strcmp(visibility,'off'),cleanup = onCleanup(@() close(figureHandle));end
% 新节点既可能位于低速端，也可能位于高速端，不再用前n行表示新增区。
newIndex = find(~ismember(extended.nc,original.nc));
nNew = numel(newIndex);
newColor = [0.85, 0.20, 0.12];
oldColor = [0.15, 0.25, 0.45];

if strcmp(original.kind, 'compressor')
    subplot(2, 2, 1); hold on;
    local_plot_rows(extended.Wc(newIndex, :), extended.PR(newIndex, :), newColor);
    local_plot_rows(original.Wc, original.PR, oldColor);
    xlabel('W_c'); ylabel('PR'); title([name, ' 流量-压比']); grid on;

    subplot(2, 2, 2); hold on;
    local_plot_rows(extended.Wc(newIndex, :), extended.Eff(newIndex, :), newColor);
    local_plot_rows(original.Wc, original.Eff, oldColor);
    xlabel('W_c'); ylabel('Efficiency'); title([name, ' 流量-效率']); grid on;

    subplot(2, 2, 3); hold on;
    local_plot_rows(repmat(extended.path, nNew, 1), ...
        extended.Wc(newIndex, :), newColor);
    local_plot_rows(repmat(original.path, numel(original.nc), 1), ...
        original.Wc, oldColor);
    xlabel('Rline'); ylabel('W_c'); title('Rline-流量'); grid on;

    subplot(2, 2, 4); hold on;
    local_plot_rows(repmat(extended.path, nNew, 1), ...
        extended.PR(newIndex, :), newColor);
    local_plot_rows(repmat(original.path, numel(original.nc), 1), ...
        original.PR, oldColor);
    xlabel('Rline'); ylabel('PR'); title('Rline-压比'); grid on;
else
    extendedPR = local_turbine_pr(extended);
    originalPR = local_turbine_pr(original);
    subplot(2, 2, 1); hold on;
    local_plot_rows(extended.Wc(newIndex, :), extendedPR(newIndex, :), newColor);
    local_plot_rows(original.Wc, originalPR, oldColor);
    xlabel('W_c'); ylabel('PR'); title([name, ' 流量-压比']); grid on;

    subplot(2, 2, 2); hold on;
    local_plot_rows(extendedPR(newIndex, :), extended.Eff(newIndex, :), newColor);
    local_plot_rows(originalPR, original.Eff, oldColor);
    xlabel('PR'); ylabel('Efficiency'); title([name, ' 压比-效率']); grid on;

    subplot(2, 2, 3); hold on;
    local_plot_rows(repmat(extended.path, nNew, 1), ...
        extended.Wc(newIndex, :), newColor);
    local_plot_rows(repmat(original.path, numel(original.nc), 1), ...
        original.Wc, oldColor);
    xlabel('beta'); ylabel('W_c'); title('beta-流量'); grid on;

    subplot(2, 2, 4); hold on;
    plot(extended.nc(newIndex), extended.maxPR(newIndex), 'o-', ...
        'Color', newColor, 'LineWidth', 1.1); hold on;
    plot(original.nc, original.maxPR, '.-', 'Color', oldColor, ...
        'LineWidth', 1.1);
    xlabel('N_{c,r}'); ylabel('PR_{max}'); title('最大压比边界'); grid on;
end
sgtitle([name, ' 原图与低速扩展图对比（红：新增，蓝：原图）']);
path = fullfile(outputDir, [name, '_map_extension.png']);
print(figureHandle, path, '-dpng', '-r160');
clear cleanup;
end

function value = local_turbine_pr(map)
if isfield(map, 'hasFullPRSurface') && map.hasFullPRSurface
    value = map.PR;
else
    % beta是原始图坐标；扩展到负beta后不能重新按首末列归一化。
    value = map.minPR(:) + (map.maxPR(:) - map.minPR(:)) .* map.path;
end
end

function local_plot_rows(x, y, color)
for i = 1:size(x, 1)
    plot(x(i, :), y(i, :), '-', 'Color', color, 'LineWidth', 0.8);
end
end

function local_write_summary(path, result)
fid = fopen(path, 'w');
assert(fid >= 0, '无法写入阶段一/二摘要：%s', path);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# 起动停车阶段一、二特性图验收摘要\n\n');
fprintf(fid, '- 生成时间：%s\n', datestr(now, 31));
fprintf(fid, '- 阶段一读写验收：%s\n', local_pass(result.stage1Accepted));
fprintf(fid, '- 阶段二扩图验收：%s\n\n', local_pass(result.stage2Accepted));
fprintf(fid, '|部件|原最低换算转速|新增线数|读写最大差|原图区最大差|物理检查|总结果|\n');
fprintf(fid, '|---|---:|---:|---:|---:|---|---|\n');
for i = 1:numel(result.items)
    item = result.items(i);
    fprintf(fid, '|%s|%.9g|%d|%.3e|%.3e|%s|%s|\n', ...
        item.name, item.originalMinimumSpeed, item.addedSpeedLineCount, ...
        item.roundTripAudit.maxAbsolute, ...
        item.originalRegionAudit.maximumAbsolute, ...
        local_pass(item.physicsAudit.accepted), local_pass(item.accepted));
end
end

function value = local_pass(tf)
if tf
    value = 'PASS';
else
    value = 'FAIL';
end
end

function hash = local_sha256(path)
fid = fopen(path, 'rb');
assert(fid >= 0, '无法读取文件以计算SHA-256：%s', path);
cleanup = onCleanup(@() fclose(fid));
bytes = fread(fid, Inf, '*uint8');
engine = javaMethod('getInstance', 'java.security.MessageDigest', 'SHA-256');
engine.update(typecast(bytes(:), 'int8'));
digest = typecast(engine.digest(), 'uint8');
hash = lower(reshape(dec2hex(digest, 2).', 1, []));
clear cleanup;
end


function local_make_dirs(paths)
for i = 1:numel(paths)
    if ~isfolder(paths{i})
        mkdir(paths{i});
    end
end
end
