function result = Start_StartStopModel_05_VisserThermalCouplingAndFreeze(userCfg)
%START_STARTSTOPMODEL_05_VISSERTHERMALCOUPLINGANDFREEZE
% 阶段七入口：三部件16状态/六部件29状态Visser耦合与停车热浸验收。
%
% 正式运行：
%   result = Start_StartStopModel_05_VisserThermalCouplingAndFreeze();
%
% 关闭图窗、只保存图件：
%   userCfg.stage7.showFigures = false;
%   result = Start_StartStopModel_05_VisserThermalCouplingAndFreeze(userCfg);
%
% 三个正式算例依次为：
%   1) 冷态热状态、无热/间隙反馈；
%   2) 冷态完整耦合；
%   3) 温态完整耦合。
% 每个算例连续执行0->慢车->巡航->慢车->0，并在停车后继续120 s
% 零流量热浸。温态算例是独立初值试验，不属于热再起动。

if nargin < 1
    userCfg = struct();
end
cfg = sht_startstop_default_config(userCfg);
cfg = sht_startstop_prepare_control(cfg);
assert(isfile(cfg.stage7.assetFile), ...
    '缺少当前拓扑的Visser参数资产：%s。', cfg.stage7.assetFile);
loadedAsset = load(cfg.stage7.assetFile, 'parameterAsset');
asset = loadedAsset.parameterAsset;
if cfg.modelMode == 0
    asset = sht_startstop_three_thermal_adapter(asset,cfg);
end
local_validate_asset(asset,cfg);
thermalConfiguration = sht_build_thermal_model_configuration(asset);
[referenceTable, cacheInfo] = ...
    sht_prepare_clearance_reference_lookup(asset.referenceTable);

[stage5Result, stage5] = sht_startstop_stage_asset('load','stage05',cfg);
assert(stage5Result.accepted, '最近阶段五结果未通过，不能进入阶段七。');

timeTag = datestr(now, 'yyyymmdd_HHMMSS');
runRoot = fullfile(cfg.paths.outputRoot, ['Stage07_', timeTag]);
mkdir(runRoot);
runtime = sht_startstop_create_runtime( ...
    cfg, stage5Result.finalMapAudit, runRoot);
caseDefinitions = local_build_case_definitions(cfg, asset);
selectedCaseNames = {caseDefinitions.name};
formalCaseNames = cfg.stage7.formalCaseNames;
isFullAcceptanceRun = isequal(selectedCaseNames(:).', formalCaseNames(:).');

alias = 'GTESS_STARTSTOP_STAGE7';
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

fprintf('\n=== 起动停车阶段七：Visser二层耦合与热浸验收 ===\n');
fprintf('阶段五冻结来源：%s\n', stage5.runRoot);
fprintf('Visser资产：%s\n', cfg.stage7.assetFile);
fprintf('结果目录：%s\n', runRoot);
if isFullAcceptanceRun
    fprintf('运行类型：正式三算例验收。\n');
else
    fprintf('运行类型：调试子集（%d/%d），不形成正式冻结结论。\n', ...
        numel(caseDefinitions), numel(formalCaseNames));
end

caseTemplate = struct('definition', struct(), 'mission', struct(), 'configuration',struct(), ...
    'elapsedS', NaN, 'accepted', false, ...
    'thermalInitialization', struct());
caseResults = repmat(caseTemplate, numel(caseDefinitions), 1);
engineInitialized = false;
try
    for i = 1:numel(caseDefinitions)
        definition = caseDefinitions(i);
        caseCfg = local_apply_case(cfg, asset, referenceTable, ...
            cacheInfo, definition);
        if engineInitialized
            status = calllib(alias, 'DLL_SHT_Free');
            assert(status == 0, '释放前一阶段七算例失败，状态码=%d。', status);
            engineInitialized = false;
        end
        [engPtr, initialization] = local_initialize_case(alias, ...
            caseCfg, thermalConfiguration, asset, definition);
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
            'accepted', mission.accepted, ...
            'thermalInitialization', initialization);
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
    assert(status == 0, '释放最终阶段七算例失败，状态码=%d。', status);
end
clear engPtr;
unloadlibrary(alias);
clear directoryCleanup;
clear pathCleanup;

comparison = local_compare_cases(caseResults);
% 调试子集只评价本次实际运行的算例。跨算例的二层作用辨认只有在三个
% 正式算例同时存在时才有定义，不能反过来把单算例PASS误写成FAIL。
selectedCasesAccepted = all([caseResults.accepted]);
comparisonAccepted = comparison.available && ...
    comparison.thermalFeedbackDetected && ...
    comparison.initialThermalConditionEffectDetected;
formalAccepted = isFullAcceptanceRun && selectedCasesAccepted && ...
    comparisonAccepted;
summaryPath = fullfile(runRoot, 'stage07_acceptance_summary.md');
comparisonFigurePath = local_plot_case_comparison( ...
    caseResults, runRoot, cfg);
manifestPath = fullfile(runRoot, 'stage07_key_file_manifest_sha256.csv');
if isFullAcceptanceRun
    resultPath = fullfile(runRoot, 'stage07_complete_result.mat');
else
    resultPath = fullfile(runRoot, 'stage07_subset_result.mat');
end
acceptance = struct('selectedCaseNames', {selectedCaseNames}, ...
    'formalCaseNames', {formalCaseNames}, ...
    'isFullAcceptanceRun', isFullAcceptanceRun, ...
    'selectedCasesAccepted', selectedCasesAccepted, ...
    'comparisonAccepted', comparisonAccepted, ...
    'formalAccepted', formalAccepted);
local_write_summary(summaryPath, stage5, cfg, asset, caseResults, ...
    comparison, acceptance);

result = struct('generatedAt', datestr(now, 31), 'runRoot', runRoot, 'configuration',cfg, ...
    'stage5Source', stage5, 'runtime', runtime, ...
    'assetFile', cfg.stage7.assetFile, ...
    'thermalConfiguration', thermalConfiguration, ...
    'caseResults', caseResults, 'comparison', comparison, ...
    'acceptance', acceptance, 'summaryPath', summaryPath, ...
    'comparisonFigurePath', comparisonFigurePath, ...
    'manifestPath', manifestPath, 'resultPath', resultPath, ...
    'accepted', formalAccepted);
save(resultPath, 'result', '-v7.3');
local_write_manifest(runRoot, manifestPath);

fprintf('\n本次所选算例结果：%s\n', local_pass(selectedCasesAccepted));
fprintf('通过算例：%d / %d\n', sum([caseResults.accepted]), ...
    numel(caseResults));
fprintf('热/间隙反馈可观测：%s\n', ...
    local_optional_pass(comparison.available, ...
    comparison.thermalFeedbackDetected));
fprintf('初始热状态影响可观测：%s\n', ...
    local_optional_pass(comparison.available, ...
    comparison.initialThermalConditionEffectDetected));
if isFullAcceptanceRun
    fprintf('阶段七正式验收结果：%s\n', local_pass(formalAccepted));
else
    fprintf('阶段七正式验收结果：未执行（调试子集）。\n');
end
fprintf('结果目录：%s\n\n', runRoot);
end

function local_validate_asset(asset,cfg)
assert(isstruct(asset) && isfield(asset, 'interface') && ...
    asset.interface.interfaceVersion == 2502 + cfg.modelMode && ...
    asset.interface.thermalModelMode == 3, ...
    'Visser资产接口必须与三/六部件拓扑一致且thermalModelMode=3。');
if cfg.modelMode == 1
    assert(isfield(asset,'selfCheck') && asset.selfCheck.passed,'六部件参数资产自检未通过。');
end
assert(isfield(asset, 'topology') && ...
    numel(asset.topology.stateNames) == cfg.topology.temperatureCount+2 && ...
    numel(asset.topology.diskRootMetalIndex) == cfg.topology.diskCount, ...
    'Visser资产状态拓扑或转盘根部映射与当前模型不一致。');
assert(numel(asset.nominal.initialTemperatureState) == cfg.topology.temperatureCount, ...
    'Visser资产初始温度维数与当前模型不一致。');
% 热参数沿用明确来源的标称先验，MDL必须一致。DLL已在本次起停工程
% 中升级，不能伪改旧资产的DLL指纹；新DLL的配置和动力学由本轮测试验证。
engineCfg=struct('interface',struct('controlDir',cfg.paths.matlabRoot, ...
    'libraryName','GTESS','headerName','GTESS.h'), ...
    'modelConfiguration',fullfile(cfg.paths.matlabRoot,cfg.topology.modelFile));
identity=sht_engine_artifact_identity(engineCfg);
fields={'dllSHA256','headerSHA256','modelSHA256'};
assert(isfield(asset,'modelIdentity'),'Visser资产缺少来源身份。');
for i=3
    assert(isfield(asset.modelIdentity,fields{i}) && ...
        strcmpi(asset.modelIdentity.(fields{i}),identity(i).sha256), ...
        'Visser资产的%s与当前分支不一致，必须重新构造或验证。',fields{i});
end
end


function definitions = local_build_case_definitions(cfg, asset)
ambientK = asset.referenceTable.defaultInletTotalTemperature_K;
hotState = asset.nominal.initialTemperatureState(:);
warmState = ambientK + cfg.stage7.warmInitialFraction * ...
    (hotState - ambientK);
template = struct('name', '', 'label', '', 'deltaTemperatureK', 0, ...
    'initialTemperatureState', zeros(cfg.topology.temperatureCount, 1), ...
    'stepInTemplate', zeros(512, 1), 'feedbackMode', '');
allCases = repmat(template, 3, 1);
allCases(1) = local_case(template, 'cold_no_feedback', ...
    '冷态热状态，无热/间隙反馈', ambientK * ones(cfg.topology.temperatureCount, 1), ...
    asset.stepInTemplates.heatState, 'heat_state_no_feedback');
allCases(2) = local_case(template, 'cold_full_coupled', ...
    '冷态Visser完整耦合', ambientK * ones(cfg.topology.temperatureCount, 1), ...
    asset.stepInTemplates.jointFull, 'joint_full');
allCases(3) = local_case(template, 'warm_full_coupled', ...
    '温态Visser完整耦合', warmState, ...
    asset.stepInTemplates.jointFull, 'joint_full');

selected = cfg.stage7.caseNames;
assert(iscell(selected) && ~isempty(selected), ...
    'cfg.stage7.caseNames必须为非空元胞数组。');
definitions = repmat(template, numel(selected), 1);
for i = 1:numel(selected)
    index = find(strcmp({allCases.name}, selected{i}), 1, 'first');
    assert(~isempty(index), '未知的阶段七算例：%s。', selected{i});
    definitions(i) = allCases(index);
end
end

function value = local_case(template, name, label, state, stepIn, mode)
value = template;
value.name = name;
value.label = label;
value.initialTemperatureState = state(:);
value.stepInTemplate = stepIn(:);
value.feedbackMode = mode;
end

function caseCfg = local_apply_case(cfg, asset, referenceTable, cacheInfo, definition)
caseCfg = cfg;
caseCfg.lowSpeedSolver.zeroHoldSpeedRpm = ...
    cfg.stage6.gasPathActivationNgRatio * cfg.startStop.designNgRpm;
caseCfg.lowSpeedSolver.accuracyRequired = cfg.stage6.solverAccuracyRequired;
caseCfg.stage6.zeroHoldAfterStopS = cfg.stage7.postStopHeatSoakS;
caseCfg.stage6.maximumMissionS = cfg.stage7.maximumMissionS;
caseCfg.stage6.showFigures = cfg.stage7.showFigures;
caseCfg.stage7.enabled = true;
caseCfg.stage7.initialTemperatureState = definition.initialTemperatureState;
caseCfg.stage7.stateNames = asset.topology.stateNames(3:end);
caseCfg.stage7.stepInTemplate = definition.stepInTemplate;
caseCfg.stage7.referenceTable = referenceTable;
caseCfg.stage7.clearanceReferenceCacheInfo = cacheInfo;
caseCfg.stage7.inletTotalTemperatureK = ...
    asset.referenceTable.defaultInletTotalTemperature_K + ...
    definition.deltaTemperatureK;
caseCfg.stage7.heatCapacityJPerK = [ ...
    asset.nominal.visserMetalHeatCapacity(1:cfg.topology.metalCount); ...
    asset.nominal.visserDiskHeatCapacity(:); ...
    asset.nominal.visserMetalHeatCapacity(cfg.topology.metalCount+1:end)];
caseCfg.stage7.diskRootMetalIndex = ...
    asset.topology.diskRootMetalIndex(:);
end

function [engPtr, initialization] = local_initialize_case( ...
    alias, cfg, thermalConfiguration, asset, definition)
status = calllib(alias, 'DLL_SHT_InitialMode', cfg.modelMode);
assert(status == 0, '部件模式%d运行配置初始化失败，状态码=%d。',cfg.modelMode,status);
startStopInitialization = sht_startstop_configure_dll(alias, cfg);
interface = struct('libraryName', alias);
thermalInitialization = sht_initialize_thermal_model_dll( ...
    interface, cfg.modelMode, thermalConfiguration);
coolingInitialization = sht_initialize_cooling_split_dll( ...
    interface, cfg.modelMode, asset.coolingSplitConfiguration);
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
initialization = struct('startStop', startStopInitialization, ...
    'thermal', thermalInitialization, 'cooling', coolingInitialization, ...
    'conditionStatus', status);
end

function comparison = local_compare_cases(caseResults)
comparison = struct('available', false, ...
    'coldFullMinusNoFeedback', struct(), ...
    'warmFullMinusColdFull', struct(), ...
    'thermalFeedbackDetected', false, ...
    'initialThermalConditionEffectDetected', false);
names = {caseResults.definition};
names = cellfun(@(item) item.name, names, 'UniformOutput', false);
indexNo = find(strcmp(names, 'cold_no_feedback'), 1);
indexCold = find(strcmp(names, 'cold_full_coupled'), 1);
indexWarm = find(strcmp(names, 'warm_full_coupled'), 1);
if isempty(indexNo) || isempty(indexCold) || isempty(indexWarm)
    return;
end
comparison.available = true;
comparison.coldFullMinusNoFeedback = local_trace_difference( ...
    caseResults(indexCold).mission.trace, ...
    caseResults(indexNo).mission.trace);
comparison.warmFullMinusColdFull = local_trace_difference( ...
    caseResults(indexWarm).mission.trace, ...
    caseResults(indexCold).mission.trace);
fields = {'Np','Ng','Tt45','effectiveFuel'};
feedbackValues = cellfun(@(name) ...
    comparison.coldFullMinusNoFeedback.maximumAbsolute.(name), fields);
initialValues = cellfun(@(name) ...
    comparison.warmFullMinusColdFull.maximumAbsolute.(name), fields);
feedbackMetric = max(feedbackValues);
initialMetric = max(initialValues);
comparison.thermalFeedbackDetected = feedbackMetric > 1.0e-6;
comparison.initialThermalConditionEffectDetected = initialMetric > 1.0e-6;
end

function result = local_trace_difference(left, right)
endTime = min(left.time(end), right.time(end));
t = linspace(0, endTime, 2001).';
fields = {'Np','Ng','Tt45','effectiveFuel'};
maximum = struct();
rmsValue = struct();
for i = 1:numel(fields)
    name = fields{i};
    difference = interp1(left.time, left.(name), t, 'linear') - ...
        interp1(right.time, right.(name), t, 'linear');
    maximum.(name) = max(abs(difference));
    rmsValue.(name) = sqrt(mean(difference .^ 2));
end
result = struct('commonEndTimeS', endTime, ...
    'maximumAbsolute', maximum, 'rms', rmsValue);
end

function local_write_summary(path, stage5, cfg, asset, caseResults, ...
    comparison, acceptance)
fid = fopen(path, 'w');
assert(fid >= 0, '无法写入阶段七验收摘要：%s。', path);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# 阶段七Visser二层耦合与热浸验收\n\n');
fprintf(fid, '- 运行类型：**%s**\n', local_run_type(acceptance));
fprintf(fid, '- 本次所选算例结果：**%s**\n', ...
    local_pass(acceptance.selectedCasesAccepted));
fprintf(fid, '- 阶段七正式验收结果：**%s**\n', ...
    local_formal_result(acceptance));
fprintf(fid, '- 阶段五冻结来源：`%s`\n', stage5.runRoot);
fprintf(fid, '- Visser资产版本：`%s`\n', asset.assetVersion);
fprintf(fid, '- 状态拓扑：2轴 + %d金属 + %d转盘 + %d导向器 = %d。\n', ...
    cfg.topology.metalCount,cfg.topology.diskCount,cfg.topology.guideCount,cfg.topology.temperatureCount+2);
fprintf(fid, '- 停车后零流量热浸：%.6g s。\n\n', ...
    cfg.stage7.postStopHeatSoakS);
fprintf(fid, '|算例|结果|耗时/s|轨迹/s|最大Tt45/K|最大热步长/K|最大能量残差|零流量储能漂移|温差收缩/K|\n');
fprintf(fid, '|---|---|---:|---:|---:|---:|---:|---:|---:|\n');
for i = 1:numel(caseResults)
    item = caseResults(i);
    checks = item.mission.checks;
    fprintf(fid, '|%s|%s|%.6g|%.6g|%.6g|%.6g|%.6e|%.6e|%.6g|\n', ...
        item.definition.label, local_pass(item.accepted), item.elapsedS, ...
        item.mission.trace.time(end), max(item.mission.trace.Tt45), ...
        checks.maximumThermalStepK, ...
        checks.maximumNormalizedEnergyResidual, ...
        checks.zeroFlowStoredEnergyRelativeDrift, ...
        checks.maximumHeatRedistributionK);
end
fprintf(fid, '\n## 二层作用辨认\n\n');
fprintf(fid, '- 冷态完整耦合相对无反馈的影响：**%s**。\n', ...
    local_optional_pass(comparison.available, ...
    comparison.thermalFeedbackDetected));
fprintf(fid, '- 温态相对冷态初值的影响：**%s**。\n', ...
    local_optional_pass(comparison.available, ...
    comparison.initialThermalConditionEffectDetected));
if comparison.available
    local_write_difference(fid, '冷态完整耦合 - 冷态无反馈', ...
        comparison.coldFullMinusNoFeedback);
    local_write_difference(fid, '温态完整耦合 - 冷态完整耦合', ...
        comparison.warmFullMinusColdFull);
end
fprintf(fid, '\n本阶段不执行热再起动，也不因热网络结果反向修改阶段五冻结特性图。\n');
end

function local_write_difference(fid, titleText, difference)
fprintf(fid, '\n### %s\n\n', titleText);
fprintf(fid, '|量|最大绝对差|RMS差|\n|---|---:|---:|\n');
fields = {'Np','Ng','Tt45','effectiveFuel'};
for i = 1:numel(fields)
    name = fields{i};
    fprintf(fid, '|%s|%.6g|%.6g|\n', name, ...
        difference.maximumAbsolute.(name), difference.rms.(name));
end
end

function path = local_plot_case_comparison(caseResults, runRoot, cfg)
path=sht_startstop_plot_thermal_case_comparison(caseResults,runRoot,cfg);
end

function local_write_manifest(runRoot, path)
files = dir(fullfile(runRoot, '**', '*'));
files = files(~[files.isdir]);
fullPaths = fullfile({files.folder}, {files.name});
[~, order] = sort(lower(fullPaths));
files = files(order);
fid = fopen(path, 'w', 'n', 'UTF-8');
assert(fid >= 0, '无法写入阶段七SHA-256清单：%s。', path);
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

function value = local_run_type(acceptance)
if acceptance.isFullAcceptanceRun
    value = '正式三算例验收';
else
    value = '调试子集';
end
end

function value = local_formal_result(acceptance)
if acceptance.isFullAcceptanceRun
    value = local_pass(acceptance.formalAccepted);
else
    value = '未执行（调试子集不形成正式结论）';
end
end

function value = local_pass(tf)
if tf
    value = 'PASS';
else
    value = 'FAIL';
end
end

function value = local_optional_pass(available, tf)
if ~available
    value = '未评价（缺少完整对比算例）';
else
    value = local_pass(tf);
end
end
