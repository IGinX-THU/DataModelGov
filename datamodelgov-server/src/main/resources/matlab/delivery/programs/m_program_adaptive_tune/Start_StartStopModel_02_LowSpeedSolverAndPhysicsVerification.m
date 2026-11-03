function result = Start_StartStopModel_02_LowSpeedSolverAndPhysicsVerification(userCfg)
%START_STARTSTOPMODEL_02_LOWSPEEDSOLVERANDPHYSICSVERIFICATION
% 起动停车阶段三、四正式入口：低速求解诊断与起停物理单元验收。
%
% 本入口使用阶段二生成的扩展图建立独立运行目录，不覆盖正式特性图。
% 阶段三先做正常区回归、设计点增强求解和低速失败诊断；阶段四再以
% 可解释合成净气动力矩隔离验收起动机、燃烧建立、两惯量和自由轮。

if nargin < 1
    userCfg = struct();
end
cfg = sht_startstop_default_config(userCfg);
[stage12Result, stage12] = sht_startstop_stage_asset('load','stage12',cfg);
mapResult = stage12Result.mapResult;

timeTag = datestr(now, 'yyyymmdd_HHMMSS');
runRoot = fullfile(cfg.paths.outputRoot, ['Stage34_', timeTag]);
mkdir(runRoot);
runtime = sht_startstop_create_runtime(cfg, mapResult, runRoot);

alias = 'GTESS_STARTSTOP';
oldDir = pwd;
programDir = fileparts(mfilename('fullpath'));
originalPath = path;
addpath(programDir);
pathCleanup = onCleanup(@() path(originalPath));
if libisloaded(alias)
    unloadlibrary(alias);
end
% 先在本分支程序目录调用加载辅助函数，再进入独立运行目录。DLL和头文件
% 均使用绝对路径，避免加载过程依赖主线目录；初始化及后续计算则必须保持
% 当前目录为runtime，否则DLL会误读未扩展的正式MDL和特性图。
sht_load_engine_library(runtime.dllPath, runtime.headerPath, 'alias', alias);
cd(runtime.controlDir);
directoryCleanup = onCleanup(@() cd(oldDir));

try
    initializationStatus = calllib(alias, 'DLL_SHT_InitialMode', 1);
    assert(initializationStatus == 0, ...
        '六部件运行配置初始化失败，状态码=%d。', initializationStatus);
    initialization = sht_startstop_configure_dll(alias, cfg);
    [engPtr, conditionsStatus] = local_initialize_conditions(alias);
    assert(conditionsStatus == 0, '环境条件初始化失败，状态码=%d。', conditionsStatus);

    stage3 = local_verify_low_speed_solver(alias, engPtr, cfg, runRoot);
    stage4Dir = fullfile(runRoot, 'stage04_physics');
    stage4 = sht_startstop_verify_physics_kernel(alias, cfg, stage4Dir);
    baseline = local_verify_normal_region_regression(cfg);

    accepted = stage3.accepted && stage4.accepted && baseline.accepted;
    summaryPath = fullfile(runRoot, 'stage34_verification_summary.md');
    local_write_summary(summaryPath, stage3, stage4, baseline, accepted);

    result = struct('generatedAt', datestr(now, 31), 'runRoot', runRoot, ...
        'runtime', runtime, 'stage12Source', stage12, ...
        'initialization', initialization, 'stage3', stage3, ...
        'stage4', stage4, 'baselineRegression', baseline, ...
        'summaryPath', summaryPath, 'accepted', accepted);
    save(fullfile(runRoot, 'stage34_complete_result.mat'), 'result', '-v7');
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

fprintf('\n=== 起动停车阶段三/四验收 ===\n');
fprintf('阶段三低速求解与诊断：%s\n', local_pass(stage3.accepted));
fprintf('阶段四起停物理内核：%s\n', local_pass(stage4.accepted));
fprintf('正常转速区零影响回归：%s\n', local_pass(baseline.accepted));
fprintf('结果目录：%s\n\n', runRoot);
end


function [engPtr, status] = local_initialize_conditions(alias)
engPtrInit.eng = libstruct('EngineTurboshaft');
engPtr = libstruct('EngineSHTPointer', engPtrInit);
stepIn = libpointer('doublePtr', zeros(512, 1));
stepOut = libpointer('doublePtr', zeros(128, 1));
status = calllib(alias, 'DLL_SHT_ConditionsInit', stepIn, stepOut, engPtr);
end

function result = local_verify_low_speed_solver(alias, engPtr, cfg, runRoot)
current = sht_startstop_stage_asset('load','design',cfg);
design = current.design;

status = calllib(alias, 'DLL_SHT_StartStopReset', ...
    cfg.startStop.designNgRpm, cfg.startStop.designNpRpm, ...
    cfg.startStop.designNpRpm, 1);
assert(status == 0, '设计点起停状态复位失败，状态码=%d。', status);
designInput = local_base_step_input(cfg);
designInput(1) = cfg.startStop.designNpRpm;
designInput(2) = cfg.startStop.designNgRpm;
designInput(3) = design.Wf;
designInput(21:27) = design.commonVariables(1:7);
designInput(31) = 2; % C stepIn[30]：正常运行
designInput(32) = cfg.startStop.designNpRpm;
designInput(34) = 1;
designInput(36) = 1;
[designStatus, designOutput] = local_call_start_stop(alias, engPtr, designInput);
designDiagnostics = local_read_diagnostics(alias);

% 精确停车保持态：不调用气路Newton，但起动指令仍能向Ng施加转矩。
status = calllib(alias, 'DLL_SHT_StartStopReset', 0, 0, 0, 1);
assert(status == 0, '零速状态复位失败。');
zeroInput = local_base_step_input(cfg);
zeroInput(3) = 0;
zeroInput(31) = 0;
zeroInput(32) = 0;
zeroInput(34) = 0;
[zeroStatus, zeroOutput] = local_call_start_stop(alias, engPtr, zeroInput);

status = calllib(alias, 'DLL_SHT_StartStopReset', 0, 0, 0, 1);
assert(status == 0, '零速起动状态复位失败。');
crankInput = zeroInput;
crankInput(31) = 1;
crankInput(34) = 1;
[crankStatus, crankOutput] = local_call_start_stop(alias, engPtr, crankInput);

% 2% Ng低速探针允许不收敛，但必须给出有限残差、秩和边界诊断。
probeNg = 0.02 * cfg.startStop.designNgRpm;
status = calllib(alias, 'DLL_SHT_StartStopReset', probeNg, 0, 0, 1);
assert(status == 0, '低速探针状态复位失败。');
probeInput = zeroInput;
probeInput(2) = probeNg;
probeInput(21:27) = [0.05; 0.8; 0.8; 1.05; 1.05; 1.05; 1.05];
probeInput(31) = 1;
probeInput(34) = 0;
probeInput(36) = 1;
[probeStatus, probeOutput] = local_call_start_stop(alias, engPtr, probeInput);
probeDiagnostics = local_read_diagnostics(alias);

checks = struct();
checks.designCallStatus = designStatus == 0;
checks.designSolverConverged = designOutput(65) == 0 && ...
    designOutput(66) == 1;
checks.designResidual = designOutput(70) <= 1e-7 && ...
    designOutput(71) <= 1e-7;
checks.designRank = designDiagnostics(9) == 7;
checks.zeroHoldCallStatus = zeroStatus == 0;
checks.zeroHoldBypassesNewton = zeroOutput(65) == 6 && ...
    zeroOutput(68) == 0;
checks.zeroHoldDerivative = max(abs(zeroOutput(1:3))) < 1e-12;
checks.coldCrankOnlyDrivesNg = crankStatus == 0 && ...
    crankOutput(2) > 0 && abs(crankOutput(1)) < 1e-12;
checks.probeCallStatus = probeStatus == 0;
checks.probeDiagnosticsPresent = probeDiagnostics(5) > 0 && ...
    isfinite(probeDiagnostics(13)) && isfinite(probeDiagnostics(14)) && ...
    probeDiagnostics(9) >= 0 && probeDiagnostics(9) <= 7;
checks.accepted = all(cell2mat(struct2cell(checks)));

result = struct('designOutput', designOutput, ...
    'designDiagnostics', designDiagnostics, 'zeroOutput', zeroOutput, ...
    'crankOutput', crankOutput, 'probeOutput', probeOutput, ...
    'probeDiagnostics', probeDiagnostics, 'checks', checks, ...
    'accepted', checks.accepted);
save(fullfile(runRoot, 'stage03_low_speed_solver_result.mat'), 'result', '-v7');
local_write_stage3(fullfile(runRoot, 'stage03_low_speed_solver_summary.md'), result);
end

function input = local_base_step_input(cfg)
input = zeros(512, 1);
input(4) = 0.10573; % A8，m^2
input(5) = 0;       % 外部空气系统关闭
input(7) = cfg.startStop.gtAccessoryPowerW;
input(17) = 0;      % C stepIn[16]：标准大气边界
input(18) = 0;      % 健康调度关闭
input(30) = cfg.startStop.timeStepS;
input(33) = cfg.startStop.collectivePitchDeg;
input(35) = 900;
input(341) = 0;     % 增强瞬态效应关闭，阶段四只验收基础起停物理
end

function [status, output] = local_call_start_stop(alias, engPtr, input)
inputPointer = libpointer('doublePtr', input);
outputPointer = libpointer('doublePtr', zeros(128, 1));
status = calllib(alias, 'DLL_SHT_RunStartStopStep', ...
    inputPointer, outputPointer, engPtr);
output = outputPointer.Value;
end

function diagnostics = local_read_diagnostics(alias)
pointer = libpointer('doublePtr', zeros(97, 1));
status = calllib(alias, 'DLL_SHT_LowSpeedSolverGetDiagnostics', pointer, 97);
assert(status == 0, '读取低速求解诊断失败，状态码=%d。', status);
diagnostics = pointer.Value;
end

function regression = local_verify_normal_region_regression(cfg)
current = sht_startstop_stage_asset('load','main_sync',cfg);
regression = current.normalRegionRegression;
end


function local_write_stage3(path, result)
fid = fopen(path, 'w');
assert(fid >= 0, '无法写入阶段三摘要：%s。', path);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# 阶段三低速求解与诊断验收\n\n');
fprintf(fid, '- 总体结果：**%s**\n', local_pass(result.accepted));
fprintf(fid, '- 设计点增强Newton状态：%.0f\n', result.designOutput(65));
fprintf(fid, '- 设计点残差RMSE：%.6e\n', result.designOutput(70));
fprintf(fid, '- 设计点最大绝对残差：%.6e\n', result.designOutput(71));
fprintf(fid, '- 设计点尺度化Jacobian条件数：%.6e\n', result.designDiagnostics(17));
fprintf(fid, '- 设计点有效秩：%.0f / 7\n', result.designDiagnostics(9));
fprintf(fid, '- 2%% Ng探针求解状态：%.0f（允许不收敛，要求可诊断）\n', ...
    result.probeDiagnostics(1));
fprintf(fid, '- 探针最终RMSE/最大残差：%.6e / %.6e\n\n', ...
    result.probeDiagnostics(13), result.probeDiagnostics(14));
fields = fieldnames(result.checks);
for i = 1:numel(fields)
    if ~strcmp(fields{i}, 'accepted')
        fprintf(fid, '- `%s`：%s\n', fields{i}, ...
            local_pass(result.checks.(fields{i})));
    end
end
end

function local_write_summary(path, stage3, stage4, baseline, accepted)
fid = fopen(path, 'w');
assert(fid >= 0, '无法写入阶段三/四摘要：%s。', path);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# 起动停车阶段三、四验收摘要\n\n');
fprintf(fid, '- 总体结果：**%s**\n', local_pass(accepted));
fprintf(fid, '- 阶段三低速求解和诊断：%s\n', local_pass(stage3.accepted));
fprintf(fid, '- 阶段四起停物理内核：%s\n', local_pass(stage4.accepted));
fprintf(fid, '- 正常转速区零影响回归：%s\n\n', local_pass(baseline.accepted));
fprintf(fid, '正常区共同工作变量最大绝对差为 %.3e，输出最大相对差为 %.3e；', ...
    baseline.commonVariableMaximumAbsolute, baseline.outputMaximumRelative);
fprintf(fid, '低速扩展与增强求解只由专用入口启用。\n');
end

function value = local_pass(tf)
if tf
    value = 'PASS';
else
    value = 'FAIL';
end
end
