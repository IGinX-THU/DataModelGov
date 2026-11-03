function result = Start_StartStopModel_04_ContinuousStartStopAndRobustness(userCfg)
%START_STARTSTOPMODEL_04_CONTINUOUSSTARTSTOPANDROBUSTNESS
% 第六阶段正式入口：连续起动、巡航、停车与小扰动鲁棒性验收。
%
% 运行方法：
%   result = Start_StartStopModel_04_ContinuousStartStopAndRobustness();
%
% 仅调试标称算例：
%   userCfg.stage6.caseNames = {'nominal'};
%   result = Start_StartStopModel_04_ContinuousStartStopAndRobustness(userCfg);
% 调试子集只生成subset结果，不具备阶段六正式验收资格。只有默认九算例
% 按正式顺序全部执行并逐项通过，result.accepted才可能为true。
%
% 关闭MATLAB图窗、只保存PNG：
%   userCfg.stage6.showFigures = false;
%
% 程序只读取最近一次已通过的阶段五冻结图。每个算例从零速开始且只复位
% 一次C状态机，完整执行0->慢车->巡航->慢车->0，不拼接静态结果。

if nargin < 1
    userCfg = struct();
end
cfg = sht_startstop_default_config(userCfg);
cfg = sht_startstop_prepare_control(cfg);
[stage5Result, stage5] = sht_startstop_stage_asset('load','stage05',cfg);
assert(stage5Result.accepted, '最近阶段五结果未通过，不能进入连续验收。');

timeTag = datestr(now, 'yyyymmdd_HHMMSS');
runRoot = fullfile(cfg.paths.outputRoot, ['Stage06_', timeTag]);
mkdir(runRoot);
runtime = sht_startstop_create_runtime( ...
    cfg, stage5Result.finalMapAudit, runRoot);
caseDefinitions = local_build_case_definitions(cfg);
selectedCaseNames = {caseDefinitions.name};
formalCaseNames = cfg.stage6.formalCaseNames;
isFullAcceptanceRun = isequal(selectedCaseNames(:).', formalCaseNames(:).');

alias = 'GTESS_STARTSTOP';
oldDir = pwd;
originalPath = path;
programDir = fileparts(mfilename('fullpath'));
addpath(programDir);
pathCleanup = onCleanup(@() path(originalPath));
directoryCleanup = onCleanup(@() cd(oldDir));
if libisloaded(alias)
    unloadlibrary(alias);
end
sht_load_engine_library(runtime.dllPath, runtime.headerPath, 'alias', alias);
cd(runtime.controlDir);

fprintf('\n=== 起动停车阶段六：连续起停与鲁棒性验收 ===\n');
fprintf('阶段五来源：%s\n', stage5.runRoot);
fprintf('结果目录：%s\n', runRoot);
if isFullAcceptanceRun
    fprintf('运行类型：正式九算例验收。\n');
else
    fprintf('运行类型：调试子集（%d/%d），不形成正式验收结论。\n', ...
        numel(selectedCaseNames), numel(formalCaseNames));
end

caseTemplate = struct('definition', struct(), 'mission', struct(), 'configuration',struct(), ...
    'elapsedS', NaN, 'accepted', false);
caseResults = repmat(caseTemplate, numel(caseDefinitions), 1);
engineInitialized = false;
try
    for i = 1:numel(caseDefinitions)
        definition = caseDefinitions(i);
        caseCfg = local_apply_case(cfg, definition);
        if engineInitialized
            status = calllib(alias, 'DLL_SHT_Free');
            assert(status == 0, '释放前一鲁棒性算例失败，状态码=%d。', status);
            engineInitialized = false;
        end
        engPtr = local_initialize_case(alias, caseCfg, definition);
        engineInitialized = true;
        caseDir = fullfile(runRoot, sprintf('%02d_%s', i, definition.name));
        fprintf('\n[%d/%d] %s\n', i, numel(caseDefinitions), definition.label);
        ticCase = tic;
        mission = sht_startstop_run_continuous_mission(alias, engPtr, ...
            caseCfg, stage5Result.finalMatrix.points, ...
            runtime.controlDir, definition, caseDir);
        elapsedS = toc(ticCase);
        caseResults(i) = struct('definition', definition, 'configuration',caseCfg, ...
            'mission', mission, 'elapsedS', elapsedS, ...
            'accepted', mission.accepted);
        fprintf('结果：%s，耗时 %.3f s，轨迹 %.3f s。\n', ...
            local_pass(mission.accepted), elapsedS, mission.trace.time(end));
    end
catch errorObject
    if engineInitialized
        try
            calllib(alias, 'DLL_SHT_Free');
        catch
        end
    end
    clear engPtr;
    if libisloaded(alias)
        unloadlibrary(alias);
    end
    rethrow(errorObject);
end

if engineInitialized
    status = calllib(alias, 'DLL_SHT_Free');
    assert(status == 0, '释放最终鲁棒性算例失败，状态码=%d。', status);
end
clear engPtr;
unloadlibrary(alias);
clear directoryCleanup;
clear pathCleanup;

subsetAccepted = all([caseResults.accepted]);
formalAccepted = isFullAcceptanceRun && subsetAccepted;
accepted = formalAccepted;
if isFullAcceptanceRun
    summaryPath = fullfile(runRoot, 'stage06_acceptance_summary.md');
    resultPath = fullfile(runRoot, 'stage06_complete_result.mat');
else
    summaryPath = fullfile(runRoot, 'stage06_subset_summary.md');
    resultPath = fullfile(runRoot, 'stage06_subset_result.mat');
end
manifestPath = fullfile(runRoot, 'stage06_key_file_manifest_sha256.csv');
acceptance = struct();
acceptance.selectedCaseNames = selectedCaseNames;
acceptance.formalCaseNames = formalCaseNames;
acceptance.subsetAccepted = subsetAccepted;
acceptance.isFullAcceptanceRun = isFullAcceptanceRun;
acceptance.formalAccepted = formalAccepted;
local_write_summary(summaryPath, stage5, caseResults, acceptance);
local_plot_robustness(caseResults, runRoot, cfg);

result = struct('generatedAt', datestr(now, 31), 'runRoot', runRoot, 'configuration',cfg, ...
    'stage5Source', stage5, 'runtime', runtime, ...
    'caseResults', caseResults, 'summaryPath', summaryPath, ...
    'manifestPath', manifestPath, 'resultPath', resultPath, ...
    'selectedCaseNames', {selectedCaseNames}, ...
    'formalCaseNames', {formalCaseNames}, ...
    'subsetAccepted', subsetAccepted, ...
    'isFullAcceptanceRun', isFullAcceptanceRun, ...
    'formalAccepted', formalAccepted, 'accepted', accepted);
save(resultPath, 'result', '-v7');
local_write_manifest(runRoot, manifestPath);

fprintf('\n本次所选算例结果：%s\n', local_pass(subsetAccepted));
fprintf('通过算例：%d / %d\n', sum([caseResults.accepted]), ...
    numel(caseResults));
if isFullAcceptanceRun
    fprintf('阶段六正式验收结果：%s\n', local_pass(formalAccepted));
else
    fprintf('阶段六正式验收结果：未执行（本次为调试子集）。\n');
end
fprintf('结果目录：%s\n\n', runRoot);
end


function definitions = local_build_case_definitions(cfg)
template = struct('name', '', 'label', '', 'deltaTemperatureK', 0, ...
    'starterMultiplier', 1, 'ignitionMultiplier', 1, ...
    'frictionMultiplier', 1, 'inertiaMultiplier', 1, ...
    'loadMultiplier', 1);
allCases = repmat(template, 9, 1);
allCases(1) = local_case(template, 'nominal', '标称');
allCases(2) = local_case(template, 'hot_ambient', '高温环境');
allCases(2).deltaTemperatureK = 20;
allCases(3) = local_case(template, 'cold_ambient', '低温环境');
allCases(3).deltaTemperatureK = -20;
allCases(4) = local_case(template, 'weak_starter', '起动机能力降低');
allCases(4).starterMultiplier = 0.90;
allCases(5) = local_case(template, 'slow_ignition', '点火/火焰建立变慢');
allCases(5).ignitionMultiplier = 1.20;
allCases(6) = local_case(template, 'high_friction', '轴系摩擦增大');
allCases(6).frictionMultiplier = 1.20;
allCases(7) = local_case(template, 'high_inertia', '轴系与旋翼惯量增大');
allCases(7).inertiaMultiplier = 1.20;
allCases(8) = local_case(template, 'high_load', '旋翼负载增大');
allCases(8).loadMultiplier = 1.10;
allCases(9) = local_case(template, 'combined_adverse', '中等不利组合');
allCases(9).deltaTemperatureK = 15;
allCases(9).starterMultiplier = 0.95;
allCases(9).ignitionMultiplier = 1.10;
allCases(9).frictionMultiplier = 1.10;
allCases(9).inertiaMultiplier = 1.10;
allCases(9).loadMultiplier = 1.05;

selected = cfg.stage6.caseNames;
assert(iscell(selected) && ~isempty(selected), ...
    'cfg.stage6.caseNames必须为非空元胞数组。');
definitions = repmat(template, numel(selected), 1);
for i = 1:numel(selected)
    index = find(strcmp({allCases.name}, selected{i}), 1, 'first');
    assert(~isempty(index), '未知的阶段六算例：%s。', selected{i});
    definitions(i) = allCases(index);
end
end

function value = local_case(template, name, label)
value = template;
value.name = name;
value.label = label;
end

function caseCfg = local_apply_case(cfg, definition)
caseCfg = cfg;
p = caseCfg.startStop;
caseCfg.lowSpeedSolver.zeroHoldSpeedRpm = ...
    cfg.stage6.gasPathActivationNgRatio * p.designNgRpm;
caseCfg.lowSpeedSolver.accuracyRequired = ...
    cfg.stage6.solverAccuracyRequired;
p.starterStallTorqueNm = p.starterStallTorqueNm * ...
    definition.starterMultiplier;
p.ignitionDelayS = p.ignitionDelayS * definition.ignitionMultiplier;
p.flameBuildS = p.flameBuildS * definition.ignitionMultiplier;
frictionFields = {'hpsCoulombLossNm','hpsViscousLossNmPerKrpm', ...
    'hpsWindageLossNmPerKrpm2','ptCoulombLossNm', ...
    'ptViscousLossNmPerKrpm','ptWindageLossNmPerKrpm2', ...
    'rotorCoulombLossNm','rotorViscousLossNmPerKrpm'};
for i = 1:numel(frictionFields)
    name = frictionFields{i};
    p.(name) = p.(name) * definition.frictionMultiplier;
end
inertiaFields = {'hpsInertiaKgM2','ptEngineInertiaKgM2', ...
    'rotorReflectedInertiaKgM2'};
for i = 1:numel(inertiaFields)
    name = inertiaFields{i};
    p.(name) = p.(name) * definition.inertiaMultiplier;
end
p.designRotorPowerW = p.designRotorPowerW * definition.loadMultiplier;
caseCfg.startStop = p;
end

function engPtr = local_initialize_case(alias, cfg, definition)
status = calllib(alias, 'DLL_SHT_InitialMode', cfg.modelMode);
assert(status == 0, '部件模式%d运行配置初始化失败，状态码=%d。',cfg.modelMode,status);
sht_startstop_configure_dll(alias, cfg);
engPtrInit.eng = libstruct('EngineTurboshaft');
engPtr = libstruct('EngineSHTPointer', engPtrInit);
stepIn = zeros(512, 1);
stepIn(11) = 0;
stepIn(12) = 0;
stepIn(13) = definition.deltaTemperatureK;
stepIn(17) = 0;
stepInPointer = libpointer('doublePtr', stepIn);
stepOutPointer = libpointer('doublePtr', zeros(128, 1));
status = calllib(alias, 'DLL_SHT_ConditionsInit', ...
    stepInPointer, stepOutPointer, engPtr);
assert(status == 0, '环境条件初始化失败，状态码=%d。', status);
end

function local_write_summary(path, stage5, caseResults, acceptance)
fid = fopen(path, 'w');
assert(fid >= 0, '无法写入阶段六验收摘要：%s。', path);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# 阶段六连续起停与鲁棒性验收\n\n');
if acceptance.isFullAcceptanceRun
    runType = '正式九算例验收';
    formalResult = local_pass(acceptance.formalAccepted);
else
    runType = '调试子集';
    formalResult = '未执行（调试子集不形成正式结论）';
end
fprintf(fid, '- 运行类型：**%s**\n', runType);
fprintf(fid, '- 本次所选算例结果：**%s**\n', ...
    local_pass(acceptance.subsetAccepted));
fprintf(fid, '- 阶段六正式验收结果：**%s**\n', formalResult);
fprintf(fid, '- 所选/正式算例数：`%d / %d`\n', ...
    numel(acceptance.selectedCaseNames), numel(acceptance.formalCaseNames));
fprintf(fid, '- 所选算例：`%s`\n', strjoin(acceptance.selectedCaseNames, ', '));
fprintf(fid, '- 阶段五冻结来源：`%s`\n', stage5.runRoot);
fprintf(fid, '- 任务形式：单次连续 `0 -> 慢车 -> 巡航 -> 慢车 -> 0`。\n');
fprintf(fid, '- 初始金属温度扰动：本阶段不适用，留待阶段七Visser热网络。\n\n');
fprintf(fid, '|算例|结果|计算耗时/s|轨迹时长/s|最大Ng/rpm|最大Np/rpm|最大Tt45/K|最大根步长|最小图裕度|\n');
fprintf(fid, '|---|---|---:|---:|---:|---:|---:|---:|---:|\n');
for i = 1:numel(caseResults)
    item = caseResults(i);
    trace = item.mission.trace;
    checks = item.mission.checks;
    fprintf(fid, '|%s|%s|%.6g|%.6g|%.6g|%.6g|%.6g|%.6g|%.6g|\n', ...
        item.definition.label, local_pass(item.accepted), item.elapsedS, ...
        trace.time(end), max(trace.Ng), max(trace.Np), max(trace.Tt45), ...
        checks.maximumNormalizedRootStep, checks.minimumMapMargin);
end
fprintf(fid, '\n各算例的完整事件时刻、逐项判据、时间历程和图件位于对应子目录。\n');
end

function local_plot_robustness(caseResults, runRoot, cfg)
count = numel(caseResults);
labels = cell(count, 1);
elapsed = zeros(count, 1);
duration = zeros(count, 1);
rootStep = zeros(count, 1);
minimumMargin = zeros(count, 1);
for i = 1:count
    labels{i} = caseResults(i).definition.label;
    elapsed(i) = caseResults(i).elapsedS;
    duration(i) = caseResults(i).mission.trace.time(end);
    rootStep(i) = caseResults(i).mission.checks.maximumNormalizedRootStep;
    minimumMargin(i) = caseResults(i).mission.checks.minimumMapMargin;
end
visibility = local_visibility(cfg.stage6.showFigures);
f = figure('Visible', visibility, 'Color', 'w', ...
    'Name', '阶段六鲁棒性算例总体对比', 'NumberTitle', 'off', ...
    'Position', [80 80 1400 760]);
cleanup = onCleanup(@() local_close_if_hidden(f, cfg.stage6.showFigures));
subplot(2, 2, 1); bar(elapsed); grid on; ylabel('计算耗时 / s'); title('计算耗时');
subplot(2, 2, 2); bar(duration); grid on; ylabel('任务时长 / s'); title('连续轨迹时长');
subplot(2, 2, 3); bar(rootStep); grid on; ylabel('归一化根步长'); title('根延续');
subplot(2, 2, 4); bar(minimumMargin); grid on; ylabel('归一化边界裕度'); title('特性图覆盖');
for i = 1:4
    subplot(2, 2, i);
    set(gca, 'XTick', 1:count, 'XTickLabel', labels, ...
        'XTickLabelRotation', 25);
end
path = fullfile(runRoot, 'stage06_robustness_overview.png');
print(f, path, '-dpng', '-r170');
clear cleanup;
end

function value = local_visibility(showFigures)
if showFigures
    value = 'on';
else
    value = 'off';
end
end

function local_close_if_hidden(handle, showFigures)
if ~showFigures && isgraphics(handle)
    close(handle);
end
end

function local_write_manifest(runRoot, path)
files = dir(fullfile(runRoot, '**', '*'));
files = files(~[files.isdir]);
fullPaths = fullfile({files.folder}, {files.name});
[~, order] = sort(lower(fullPaths));
files = files(order);

fid = fopen(path, 'w', 'n', 'UTF-8');
assert(fid >= 0, '无法写入阶段六SHA-256清单：%s。', path);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'relative_path,bytes,sha256\n');
for i = 1:numel(files)
    filePath = fullfile(files(i).folder, files(i).name);
    if strcmpi(filePath, path)
        continue;
    end
    relativePath = erase(filePath, [runRoot, filesep]);
    relativePath = strrep(relativePath, '"', '""');
    fprintf(fid, '"%s",%d,%s\n', relativePath, files(i).bytes, ...
        local_sha256(filePath));
end
clear cleanup;
end

function value = local_sha256(path)
fid = fopen(path, 'rb');
assert(fid >= 0, '无法读取文件以计算SHA-256：%s。', path);
cleanup = onCleanup(@() fclose(fid));
bytes = fread(fid, Inf, '*uint8');
engine = javaMethod('getInstance', ...
    'java.security.MessageDigest', 'SHA-256');
engine.update(typecast(bytes(:), 'int8'));
digest = typecast(engine.digest(), 'uint8');
value = lower(reshape(dec2hex(digest, 2).', 1, []));
clear cleanup;
end

function value = local_pass(tf)
if tf
    value = 'PASS';
else
    value = 'FAIL';
end
end
