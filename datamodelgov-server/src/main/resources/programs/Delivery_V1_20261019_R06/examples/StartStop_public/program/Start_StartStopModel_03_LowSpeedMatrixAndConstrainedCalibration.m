function result = Start_StartStopModel_03_LowSpeedMatrixAndConstrainedCalibration(userCfg)
%START_STARTSTOPMODEL_03_LOWSPEEDMATRIXANDCONSTRAINEDCALIBRATION
% 起动停车阶段五正式入口：低速共同工作矩阵与受约束扩图区校准。
%
% 运行方法：
%   result = Start_StartStopModel_03_LowSpeedMatrixAndConstrainedCalibration();
%
% 程序读取最近一次已通过的阶段一/二扩图结果，不修改输入原图。先评价
% 完整基线矩阵，再执行硬约束灵敏度扫描和少量参数坐标搜索，最后重跑
% 完整矩阵及正常转速区回归。阶段五不执行连续起动和停车积分。

if nargin < 1
    userCfg = struct();
end
cfg = sht_startstop_default_config(userCfg);
[stage12Result, stage12] = sht_startstop_stage_asset('load','stage12',cfg);
mapResult = stage12Result.mapResult;
design = local_load_design(cfg);

timeTag = datestr(now, 'yyyymmdd_HHMMSS');
runRoot = fullfile(cfg.paths.outputRoot, ['Stage05_', timeTag]);
mkdir(runRoot);
runtime = sht_startstop_create_runtime(cfg, mapResult, runRoot);
baselineDir = fullfile(runRoot, 'baseline_matrix');
calibrationDir = fullfile(runRoot, 'calibration');
finalDir = fullfile(runRoot, 'final_matrix');
finalMapsDir = fullfile(runRoot, 'maps_calibrated');

alias = 'GTESS_STARTSTOP';
oldDir = pwd;
programDir = fileparts(mfilename('fullpath'));
originalPath = path;
addpath(programDir);
pathCleanup = onCleanup(@() path(originalPath));
if libisloaded(alias)
    unloadlibrary(alias);
end
sht_load_engine_library(runtime.dllPath, runtime.headerPath, 'alias', alias);
cd(runtime.controlDir);
directoryCleanup = onCleanup(@() cd(oldDir));

fprintf('\n=== 起动停车阶段五：低速矩阵与受约束调图 ===\n');
fprintf('结果目录：%s\n', runRoot);
try
    engPtr = local_initialize_runtime(alias, cfg);
    baselineOptions = struct('label', '校准前基线', ...
        'outputDir', baselineDir, 'writeEvidence', true);
    baselineMatrix = sht_startstop_evaluate_low_speed_matrix( ...
        alias, engPtr, cfg, runtime.controlDir, design, baselineOptions);
    fprintf('基线矩阵：通过 %d / %d，失败 %d。\n', ...
        baselineMatrix.summary.acceptedCount, ...
        baselineMatrix.summary.applicableCount, ...
        baselineMatrix.summary.failedCount);

    if cfg.stage5.calibrationEnabled
        calibration = sht_startstop_calibrate_low_speed_maps( ...
            alias, cfg, runtime, design, calibrationDir, true);
        thetaBest = calibration.thetaBest;
    else
        calllib(alias, 'DLL_SHT_Free');
        calibration = local_disabled_calibration(cfg, baselineMatrix);
        thetaBest = calibration.thetaBest;
    end

    % 搜索结束时运行目录可能停留在最后一个试探候选。必须显式重写最佳
    % 参数并重新初始化，确保最终矩阵和归档图与thetaBest一一对应。
    finalRuntimeMapAudit = sht_startstop_write_candidate_maps( ...
        cfg, thetaBest, runtime.controlDir);
    assert(finalRuntimeMapAudit.accepted, '最佳候选特性图硬检查未通过。');
    engPtr = local_initialize_runtime(alias, cfg);
    finalOptions = struct('label', '校准后最终矩阵', ...
        'outputDir', finalDir, 'writeEvidence', true);
    finalMatrix = sht_startstop_evaluate_low_speed_matrix( ...
        alias, engPtr, cfg, runtime.controlDir, design, finalOptions);
    [normalRegion, ~] = local_verify_normal_region( ...
        alias, engPtr, cfg, design, runtime.controlDir, thetaBest);
    finalMapAudit = sht_startstop_write_candidate_maps( ...
        cfg, thetaBest, finalMapsDir);

    accepted = finalMatrix.accepted && finalMapAudit.accepted && ...
        normalRegion.accepted;
    summaryPath = fullfile(runRoot, 'stage05_acceptance_summary.md');
    manifestPath = fullfile(runRoot, ...
        'stage05_key_file_manifest_sha256.csv');
    local_write_summary(summaryPath, baselineMatrix, finalMatrix, ...
        calibration, normalRegion, finalMapAudit, cfg, accepted);
    result = struct('generatedAt', datestr(now, 31), 'runRoot', runRoot, ...
        'stage12Source', stage12, 'runtime', runtime, ...
        'baselineMatrix', baselineMatrix, 'calibration', calibration, ...
        'thetaBest', thetaBest, 'finalMatrix', finalMatrix, ...
        'normalRegionRegression', normalRegion, ...
        'finalMapAudit', finalMapAudit, 'summaryPath', summaryPath, ...
        'manifestPath', manifestPath, 'accepted', accepted);
    save(fullfile(runRoot, 'stage05_complete_result.mat'), 'result', '-v7');
    if accepted
        sht_startstop_stage_asset('publish','stage05',cfg,result);
    end
    local_write_manifest(runRoot, manifestPath);
catch errorObject
    try
        calllib(alias, 'DLL_SHT_Free');
    catch
    end
    clear engPtr;
    if libisloaded(alias)
        unloadlibrary(alias);
    end
    rethrow(errorObject);
end

calllib(alias, 'DLL_SHT_Free');
clear engPtr;
unloadlibrary(alias);
clear directoryCleanup;
clear pathCleanup;

fprintf('最终矩阵：通过 %d / %d，失败 %d。\n', ...
    finalMatrix.summary.acceptedCount, finalMatrix.summary.applicableCount, ...
    finalMatrix.summary.failedCount);
fprintf('正常转速区普通路径零影响回归：%s\n', ...
    local_pass(normalRegion.ordinary.accepted));
fprintf('起停专用求解器设计点回归：%s\n', ...
    local_pass(normalRegion.enhanced.accepted));
fprintf('阶段五总体结果：%s\n', local_pass(accepted));
fprintf('结果目录：%s\n\n', runRoot);
end


function design = local_load_design(cfg)
current = sht_startstop_stage_asset('load','design',cfg);
design = current.design;
design.inputTargets = current.designTargets;
end

function engPtr = local_initialize_runtime(alias, cfg)
status = calllib(alias, 'DLL_SHT_InitialMode', 1);
assert(status == 0, '六部件运行配置初始化失败，状态码=%d。', status);
sht_startstop_configure_dll(alias, cfg);
engPtrInit.eng = libstruct('EngineTurboshaft');
engPtr = libstruct('EngineSHTPointer', engPtrInit);
stepIn = libpointer('doublePtr', zeros(512, 1));
stepOut = libpointer('doublePtr', zeros(128, 1));
status = calllib(alias, 'DLL_SHT_ConditionsInit', stepIn, stepOut, engPtr);
assert(status == 0, '环境条件初始化失败，状态码=%d。', status);
end

function [regression, engPtr] = local_verify_normal_region( ...
    alias, engPtr, cfg, design, mapDirectory, thetaBest)
% 正常区验收分为两个互不混淆的层次。普通RunOnePoint在同一DLL、MDL、
% 输入和初值下依次装载扩展图与原始图做A/B回放；该差值才回答低速扩图
% 是否影响正常区。起停专用入口只验证增强求解器在设计点仍有高精度根。
target = design.inputTargets;
extendedOrdinary = local_run_ordinary_design(alias, engPtr, target, design);

enhanced = local_run_enhanced_design(alias, engPtr, cfg, design);

% 暂时换装原始六部件图，完成普通路径基准回放。回放后必须恢复thetaBest
% 对应的扩展图并重新初始化，保证调用者后续归档和释放的运行态一致。
status = calllib(alias, 'DLL_SHT_Free');
assert(status == 0, '正常区A/B回放释放扩展图运行态失败，状态码=%d。', status);
local_install_original_maps(cfg, mapDirectory);
engPtr = local_initialize_runtime(alias, cfg);
originalOrdinary = local_run_ordinary_design(alias, engPtr, target, design);
status = calllib(alias, 'DLL_SHT_Free');
assert(status == 0, '正常区A/B回放释放原图运行态失败，状态码=%d。', status);
restoreAudit = sht_startstop_write_candidate_maps(cfg, thetaBest, mapDirectory);
assert(restoreAudit.accepted, '正常区A/B回放后恢复扩展图失败。');
engPtr = local_initialize_runtime(alias, cfg);

ordinary = struct();
ordinary.original = originalOrdinary;
ordinary.extended = extendedOrdinary;
ordinary.commonVariableMaximumAbsolute = max(abs( ...
    extendedOrdinary.commonVariables - originalOrdinary.commonVariables));
ordinary.outputMaximumRelative = max(abs( ...
    extendedOrdinary.actualOutput(:) - originalOrdinary.actualOutput(:)) ./ ...
    max(abs(originalOrdinary.actualOutput(:)), 1));
ordinary.accepted = originalOrdinary.accepted && extendedOrdinary.accepted && ...
    ordinary.commonVariableMaximumAbsolute <= 1e-10 && ...
    ordinary.outputMaximumRelative <= 1e-10;

regression = struct();
regression.ordinary = ordinary;
regression.enhanced = enhanced;
regression.commonVariableMaximumAbsolute = ...
    ordinary.commonVariableMaximumAbsolute;
regression.outputMaximumRelative = ordinary.outputMaximumRelative;
regression.accepted = ordinary.accepted && enhanced.accepted;
end

function ordinary = local_run_ordinary_design(alias, engPtr, target, design)
ordinaryInput = zeros(512, 1);
ordinaryInput(1:10) = [target.NpRpm; target.NgRpm; design.Wf; ...
    target.nozzleAreaM2; 0; target.loadPowerW; target.accessoryPowerW; ...
    0; 0; 0];
ordinaryInput(21:29) = design.commonVariables(1:9);
ordinaryInput(341) = 0;
seedPointer = libpointer('doublePtr', ordinaryInput);
seedOutput = libpointer('doublePtr', zeros(128, 1));
seedStatus = calllib(alias, 'DLL_SHT_varIteInit', ...
    seedPointer, seedOutput, engPtr);
assert(seedStatus == 0, '正常区普通路径初值写入失败，状态码=%d。', seedStatus);
ordinaryPointer = libpointer('doublePtr', ordinaryInput);
ordinaryOutputPointer = libpointer('doublePtr', zeros(128, 1));
[ordinaryCallStatus, ~, ordinaryStepOutput, ordinaryEngOut] = calllib( ...
    alias, 'DLL_SHT_RunOnePoint', ordinaryPointer, ordinaryOutputPointer, engPtr);
ordinaryEng = ordinaryEngOut.eng;
ordinaryActualOutput = local_design_output(ordinaryEng);
ordinary = struct();
ordinary.callStatus = ordinaryCallStatus;
ordinary.convergeTag = ordinaryEng.convergeTag;
ordinary.maximumResidual = max(abs(ordinaryEng.errOut(1:9)));
ordinary.commonVariables = ordinaryEng.varIte(1:9).';
ordinary.actualOutput = ordinaryActualOutput;
ordinary.stepOutput = ordinaryStepOutput;
ordinary.accepted = ordinaryCallStatus == 0 && ...
    ordinaryEng.convergeTag == 0 && ordinary.maximumResidual <= 1e-7;
end

function enhanced = local_run_enhanced_design(alias, engPtr, cfg, design)
status = calllib(alias, 'DLL_SHT_StartStopReset', ...
    cfg.startStop.designNgRpm, cfg.startStop.designNpRpm, ...
    cfg.startStop.designNpRpm, 1);
assert(status == 0, '正常区回归状态复位失败。');
% Reset后的状态是STOPPED。若直接下发RUN，物理内核会按停车态把有效燃油
% 置零，得到的只是设计转速下的零燃油风车根。这里先用独立物理接口在
% 固定设计转速下走完点火延迟和火焰建立，明确进入RUN后再验收气路根。
statePreparation = local_prepare_design_run_state(alias, cfg, design);
assert(statePreparation.accepted, ...
    '起停状态机未能在设计点回归前进入RUN，最终phase=%d。', ...
    statePreparation.phase);
input = zeros(512, 1);
input(1) = cfg.startStop.designNpRpm;
input(2) = cfg.startStop.designNgRpm;
input(3) = design.Wf;
input(4) = 0.10573;
input(7) = cfg.startStop.gtAccessoryPowerW;
input(21:27) = design.commonVariables(1:7);
input(30) = cfg.startStop.timeStepS;
input(31) = 2;
input(32) = cfg.startStop.designNpRpm;
input(33) = cfg.startStop.collectivePitchDeg;
input(34) = 1;
input(35) = 900;
input(36) = 1;
input(341) = 0;
inputPointer = libpointer('doublePtr', input);
outputPointer = libpointer('doublePtr', zeros(128, 1));
[callStatus, ~, output, engOut] = calllib(alias, ...
    'DLL_SHT_RunStartStopStep', inputPointer, outputPointer, engPtr);
diagnosticPointer = libpointer('doublePtr', zeros(97, 1));
status = calllib(alias, 'DLL_SHT_LowSpeedSolverGetDiagnostics', ...
    diagnosticPointer, 97);
assert(status == 0, '正常区回归诊断读取失败。');
diagnostics = diagnosticPointer.Value;
eng = engOut.eng;
actualOutput = local_design_output(eng);
commonVariables = diagnostics(18:24);
commonReference = design.commonVariables(1:7);
enhanced = struct();
enhanced.callStatus = callStatus;
enhanced.solverStatus = diagnostics(1);
enhanced.residualRms = diagnostics(13);
enhanced.maximumResidual = diagnostics(14);
enhanced.commonVariableMaximumAbsolute = max(abs( ...
    commonVariables - commonReference));
enhanced.commonVariableMaximumRelative = max(abs( ...
    commonVariables - commonReference) ./ max(abs(commonReference), 1));
enhanced.outputMaximumRelative = max(abs(actualOutput(:) - ...
    design.output(:)) ./ max(abs(design.output(:)), 1));
enhanced.commonVariables = commonVariables;
enhanced.actualOutput = actualOutput;
enhanced.preparation = statePreparation;
enhanced.phase = round(output(4));
enhanced.effectiveFuelKgPerS = output(6);
enhanced.effectiveFuelRelativeError = abs(output(6) - design.Wf) / ...
    max(abs(design.Wf), eps);
enhanced.stepOutput = output;
enhanced.accepted = callStatus == 0 && diagnostics(1) == 0 && ...
    diagnostics(2) == 1 && enhanced.maximumResidual <= ...
    cfg.stage5.enhancedDesignResidualTolerance && ...
    enhanced.phase == 8 && enhanced.effectiveFuelRelativeError <= 1e-12 && ...
    enhanced.commonVariableMaximumRelative <= ...
    cfg.stage5.enhancedDesignVariableRelativeTolerance && ...
    enhanced.outputMaximumRelative <= ...
    cfg.stage5.enhancedDesignOutputRelativeTolerance;
end

function preparation = local_prepare_design_run_state(alias, cfg, design)
% 只推进起停状态机，不积分转速。固定设计转速避免为验收而改变气路工况。
dt = cfg.startStop.timeStepS;
maximumTimeS = cfg.startStop.ignitionDelayS + ...
    cfg.startStop.flameBuildS + 10;
maximumSteps = ceil(maximumTimeS / dt);
input = [dt; 1; cfg.startStop.designNgRpm; ...
    cfg.startStop.designNpRpm; cfg.startStop.designNpRpm; 0; 0; ...
    design.Wf; cfg.startStop.collectivePitchDeg; 1; 900; ...
    cfg.startStop.gtAccessoryPowerW];
inputPointer = libpointer('doublePtr', input);
outputPointer = libpointer('doublePtr', zeros(24, 1));
phase = 0;
status = -1;
for stepCount = 1:maximumSteps
    status = calllib(alias, 'DLL_SHT_StartStopPhysicsStep', ...
        inputPointer, numel(input), outputPointer, 24);
    assert(status == 0, ...
        '设计点状态准备第%d步失败，状态码=%d。', stepCount, status);
    phase = round(outputPointer.Value(4));
    if phase == 8
        break;
    end
    if phase == 7
        % START只负责到达慢车；随后显式切换RUN，验证正常起动指令序列。
        input(2) = 2;
        inputPointer.Value = input;
    end
end
preparation = struct('accepted', status == 0 && phase == 8, ...
    'phase', phase, 'stepCount', stepCount, ...
    'elapsedS', stepCount * dt, 'physicsOutput', outputPointer.Value);
end

function local_install_original_maps(cfg, outputDir)
names = {'AC', 'CC', 'GT1', 'GT2', 'PT1', 'PT2'};
for i = 1:numel(names)
    definition = cfg.maps.(names{i});
    source = fullfile(cfg.paths.cRoot, definition.sourceName);
    destination = fullfile(outputDir, definition.outputName);
    assert(isfile(source), '正常区A/B回放缺少原始特性图：%s。', source);
    [copied, message] = copyfile(source, destination, 'f');
    assert(copied, '换装原始特性图失败：%s。', message);
end
end

function output = local_design_output(eng)
output = [eng.HPC2.y(1), eng.HPC2.y(3), eng.HPC2.y(4), ...
    eng.HPT2.y(3), eng.HPT2.y(4), eng.LPT2.y(3), eng.LPT2.y(4), ...
    eng.LPS_Nmech, eng.HPS_Nmech, eng.LPS_Trq];
end

function calibration = local_disabled_calibration(cfg, baselineMatrix)
theta = [cfg.extension.AC.lockedFlowFraction, ...
    cfg.extension.AC.lockedPressureLoss, ...
    cfg.extension.CC.lockedFlowFraction, ...
    cfg.extension.CC.lockedPressureLoss, ...
    cfg.extension.GT1.lockedFlowFraction, ...
    cfg.extension.GT1.lockedMaximumPressureRatio, ...
    cfg.extension.GT2.lockedFlowFraction, ...
    cfg.extension.GT2.lockedMaximumPressureRatio, ...
    cfg.extension.PT1.lockedFlowFraction, ...
    cfg.extension.PT1.lockedMaximumPressureRatio, ...
    cfg.extension.PT2.lockedFlowFraction, ...
    cfg.extension.PT2.lockedMaximumPressureRatio];
calibration = struct('thetaInitial', theta, 'thetaBest', theta, ...
    'baseline', struct('matrix', baselineMatrix), ...
    'best', struct('matrix', baselineMatrix), 'evaluationCount', 0, ...
    'releasedParameterIndex', [], 'improved', false, 'accepted', true);
end

function local_write_summary(path, baseline, final, calibration, ...
    normalRegion, mapAudit, cfg, accepted)
fid = fopen(path, 'w', 'n', 'UTF-8');
assert(fid >= 0, '无法写入阶段五验收摘要：%s。', path);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# 起动停车阶段五验收摘要\n\n');
fprintf(fid, '- 总体结果：**%s**\n', local_pass(accepted));
fprintf(fid, '- 基线矩阵通过/适用：%d / %d\n', ...
    baseline.summary.acceptedCount, baseline.summary.applicableCount);
fprintf(fid, '- 最终矩阵通过/适用：%d / %d\n', ...
    final.summary.acceptedCount, final.summary.applicableCount);
fprintf(fid, '- 基线/最终失败点：%d / %d\n', ...
    baseline.summary.failedCount, final.summary.failedCount);
fprintf(fid, '- 基线/最终最大RMSE：%.6e / %.6e\n', ...
    baseline.summary.maximumResidualRms, final.summary.maximumResidualRms);
fprintf(fid, '- 候选DLL评价次数：%d\n', calibration.evaluationCount);
fprintf(fid, '- 原图区逐元素冻结：%s\n', ...
    local_pass(all(arrayfun(@(x) x.originalRegionAudit.accepted, ...
    mapAudit.items))));
fprintf(fid, '- 正常区共同变量最大绝对差：%.3e\n', ...
    normalRegion.commonVariableMaximumAbsolute);
fprintf(fid, '- 正常区输出最大相对差：%.3e\n', ...
    normalRegion.outputMaximumRelative);
fprintf(fid, '- 普通RunOnePoint正常区回归：%s\n', ...
    local_pass(normalRegion.ordinary.accepted));
fprintf(fid, '- 起停专用求解器设计点最大残差：%.3e\n', ...
    normalRegion.enhanced.maximumResidual);
fprintf(fid, '- 起停专用求解器设计点状态机阶段：%d（8表示RUN）\n', ...
    normalRegion.enhanced.phase);
fprintf(fid, '- 起停专用求解器设计点有效燃油相对差：%.3e\n', ...
    normalRegion.enhanced.effectiveFuelRelativeError);
fprintf(fid, '- 起停专用求解器相对冻结设计根的共同变量最大绝对差：%.3e\n', ...
    normalRegion.enhanced.commonVariableMaximumAbsolute);
fprintf(fid, '- 起停专用求解器相对冻结设计根的共同变量最大相对差：%.3e\n', ...
    normalRegion.enhanced.commonVariableMaximumRelative);
fprintf(fid, '- 起停专用求解器相对冻结设计根的输出最大相对差：%.3e\n', ...
    normalRegion.enhanced.outputMaximumRelative);
fprintf(fid, '- 起停专用求解器变量/输出相对差门限：%.3e / %.3e\n', ...
    cfg.stage5.enhancedDesignVariableRelativeTolerance, ...
    cfg.stage5.enhancedDesignOutputRelativeTolerance);
fprintf(fid, '- 正常区综合回归：%s\n\n', local_pass(normalRegion.accepted));
fprintf(fid, '|参数|初值|最终值|\n');
fprintf(fid, '|---|---:|---:|\n');
for i = 1:12
    fprintf(fid, '|%s|%.8g|%.8g|\n', ...
        cfg.stage5.calibrationParameterNames{i}, ...
        calibration.thetaInitial(i), calibration.thetaBest(i));
end
fprintf(fid, '\n轻微特性图越界只作为风险记录；本次总体通过还要求该点同时满足');
fprintf(fid, '气路残差、物理量有限性和Jacobian秩判据。\n');
end

function value = local_pass(tf)
if tf
    value = 'PASS';
else
    value = 'FAIL';
end
end

function local_write_manifest(runRoot, manifestPath)
% 固化本次运行依赖、DLL、特性图和结果哈希。清单自身不参与哈希，
% 避免写入自身哈希造成递归定义。
files = dir(fullfile(runRoot, '**', '*'));
files = files(~[files.isdir]);
fullPaths = fullfile({files.folder}, {files.name});
[~, order] = sort(lower(fullPaths));
files = files(order);

fid = fopen(manifestPath, 'w', 'n', 'UTF-8');
assert(fid >= 0, '无法写入阶段五SHA-256清单：%s。', manifestPath);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'relative_path,bytes,sha256\n');
for i = 1:numel(files)
    path = fullfile(files(i).folder, files(i).name);
    if strcmpi(path, manifestPath)
        continue;
    end
    relativePath = erase(path, [runRoot, filesep]);
    relativePath = strrep(relativePath, '"', '""');
    fprintf(fid, '"%s",%d,%s\n', relativePath, files(i).bytes, ...
        local_sha256(path));
end
clear cleanup;
end

function hash = local_sha256(path)
fid = fopen(path, 'rb');
assert(fid >= 0, '无法读取文件以计算SHA-256：%s。', path);
cleanup = onCleanup(@() fclose(fid));
bytes = fread(fid, Inf, '*uint8');
engine = javaMethod('getInstance', ...
    'java.security.MessageDigest', 'SHA-256');
engine.update(typecast(bytes(:), 'int8'));
digest = typecast(engine.digest(), 'uint8');
hash = lower(reshape(dec2hex(digest, 2).', 1, []));
clear cleanup;
end
