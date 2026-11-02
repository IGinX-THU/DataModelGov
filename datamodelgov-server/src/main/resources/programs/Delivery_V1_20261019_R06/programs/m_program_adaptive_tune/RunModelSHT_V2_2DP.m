function result = RunModelSHT_V2_2DP()
%RUNMODELSHT_V2_2DP 六部件 M1 拆分模型设计点求解与手工配置复现验证。
%
% 本程序只使用 C 程序中的 modelMode=1，不读取、不运行三部件模型，
% 也不依赖 Turboshaft-TS.mdl。实际任务由
% Turboshaft-TS-Split.mdl 的 offDesignMode 决定：
%   offDesignMode=0：联合求解 12 个设计变量，计算并打印需要人工写入
%                    MDL 的共同工作初值、PRDes/EffDes和部件缩放系数；
%   offDesignMode=2：读取人工更新后的 MDL，核对共同工作残差、设计点
%                    输出、设计字段、缩放系数和50%/50%级功率分配。
%
% 程序不修改 Turboshaft-TS-Split.mdl。设计数值保存在 MiddleData 中，
% 仅供第二次运行做复现对比，不代替人工审核和配置修改。
%
% M1 只使用原始通用特性图：
%   AC      : HPC02_backup_before_surge_line_endpoint_20260706.MAP
%   CC      : SingleStgRadialCompr.MAP
%   GT1/GT2 : HPT02.MAP
%   PT1/PT2 : LPT02.MAP
%
% 50%/50% 是设计点的实际级轴功率约束，不是固定压比分配。
% offDesignMode=2 运行时不再强制功率比，各级功率由特性图和级间
% 共同工作关系自然决定。

clc;
close all;

cfg = local_configuration();
offDesignMode = local_read_off_design_mode(cfg.paths.splitMdl);

oldDir = pwd;
cd(cfg.paths.runtimeDir);
restoreDirectory = onCleanup(@() cd(oldDir)); %#ok<NASGU>

alias = cfg.interface.alias;
local_force_unload(alias);
sht_load_engine_library(cfg.paths.dll, cfg.paths.header, 'alias', alias, ...
    'includepath', cfg.paths.runtimeDir);
closeLibrary = onCleanup(@() local_close_library(alias)); %#ok<NASGU>

engInit.eng = libstruct(cfg.interface.engineStructName);
engPtr = libstruct(cfg.interface.enginePointerName, engInit);
stepIn = libpointer('doublePtr', zeros(cfg.interface.stepInLength, 1));
stepOut = libpointer('doublePtr', zeros(cfg.interface.stepOutLength, 1));

switch offDesignMode
    case 0
        local_initialize(alias, engPtr, stepIn, stepOut, cfg);
        initial = local_initial_design_vector(cfg);
        [solution, history, design] = local_solve_design( ...
            alias, engPtr, stepIn, stepOut, initial, cfg);
        status = calllib(alias, 'DLL_SHT_Free');
        assert(status == 0, '拆分设计模式 DLL 释放失败，状态码=%d。', status);

        designState = local_make_design_state(solution, design, cfg);
        local_save_design_state(cfg.paths.designState, designState);

        result.generatedAt = datestr(now, 31);
        result.workflow = 'design';
        result.modelMode = 1;
        result.offDesignMode = offDesignMode;
        result.configuration = cfg;
        result.designTargets = cfg.design;
        result.solution = solution;
        result.iterationHistory = history;
        result.design = design;
        result.accepted = design.converged;

        local_print_design_result(result, cfg);

    case 2
        designState = local_load_design_state(cfg.paths.designState, cfg);
        design = designState.design;

        local_initialize(alias, engPtr, stepIn, stepOut, cfg);
        verification = local_verify_operational_mdl( ...
            alias, engPtr, stepIn, stepOut, design, cfg);
        status = calllib(alias, 'DLL_SHT_Free');
        assert(status == 0, '拆分运行模式 DLL 释放失败，状态码=%d。', status);

        result.generatedAt = datestr(now, 31);
        result.workflow = 'verification';
        result.modelMode = 1;
        result.offDesignMode = offDesignMode;
        result.configuration = cfg;
        result.designTargets = cfg.design;
        result.designState = designState;
        result.solution = designState.solution;
        result.design = design;
        result.verification = verification;
        result.accepted = verification.accepted;

        local_print_verification_result(result, cfg);

    otherwise
        error('RunModelSHT_V2:UnsupportedOffDesignMode', ...
            ['Turboshaft-TS-Split.mdl 中 offDesignMode=%g。V2 只接受 ', ...
             '0（设计求解）或 2（手工配置复现验证）。'], offDesignMode);
end

if ~isfolder(cfg.paths.reportDir)
    mkdir(cfg.paths.reportDir);
end
save(cfg.paths.resultMat, 'result', '-v7.3');
local_write_summary(cfg.paths.summary, result);

if nargout == 0
    assignin('base', 'RunModelSHT_V2_result', result);
end
end

function cfg = local_configuration()
thisDir = fileparts(mfilename('fullpath'));
reportRoot = fileparts(thisDir);

cfg.paths.runtimeDir = thisDir;
cfg.paths.dll = fullfile(thisDir, 'GTESS.dll');
cfg.paths.header = fullfile(thisDir, 'GTESS.h');
cfg.paths.splitMdl = fullfile(thisDir, 'Turboshaft-TS-Split.mdl');
cfg.paths.middleData = fullfile(thisDir, 'MiddleData');
cfg.paths.designState = fullfile(cfg.paths.middleData, ...
    'RunModelSHT_V2_design_state.mat');
cfg.paths.reportDir = fullfile(reportRoot, 'report_outputs', 'component_split_m1');
cfg.paths.resultMat = fullfile(cfg.paths.reportDir, ...
    'component_split_m1_design_result.mat');
cfg.paths.summary = fullfile(cfg.paths.reportDir, ...
    'component_split_m1_design_summary.txt');

% 使用 GTESS.dll 的标准接口别名，避免同一头文件被重复注册。
cfg.interface.alias = 'GTESS';
cfg.interface.engineStructName = 'EngineTurboshaft';
cfg.interface.enginePointerName = 'EngineSHTPointer';
cfg.interface.stepInLength = 512;
cfg.interface.stepOutLength = 128;

cfg.design.NpRpm = 20800.0;
cfg.design.NgRpm = 38000.0;
cfg.design.Wf0 = 0.151914044493225;
cfg.design.loadPowerW = 2176600.0;
cfg.design.accessoryPowerW = 0.0;
cfg.design.nozzleAreaM2 = 0.10573;

% 六部件模型的独立设计点约束。以下数值属于发动机设计点数据，
% 由 V2 显式持有；运行时不再从三部件模型计算或读取参考值。
cfg.design.targetTt4K = 1620.0;
% 25 截面目标来自现阶段工程设计锚点；3 截面目标来自 V1 原三部件
% 设计点求解结果。数值在此显式冻结，V2 运行时不读取 V1 程序、状态
% 文件或 Turboshaft-TS.mdl，因而仍可独立运行。
cfg.design.targetTt25K = 478.95;
cfg.design.targetPt25Pa = 478500.0;
cfg.design.targetTt3K = 702.307986952118;
cfg.design.targetPt3Pa = 1572564.0;
cfg.design.targetGTExitPressurePa = 395927.73735746136;
cfg.design.targetPTExitPressurePa = 108055.52351408009;
cfg.design.gtStageOneWorkFraction = 0.5;
cfg.design.ptStageOneWorkFraction = 0.5;

% 2 截面总温总压已在模型设计阶段事先计算并在此显式给定。MATLAB 不再
% 建立第二套进气道模型，只读取 DLL 内 Inlet 的实际出口状态并与给定值
% 严格比较，防止后续环境或进气道修改造成两处模型不一致而未被发现。
cfg.design.targetTt2K = 288.15;
cfg.design.targetPt2Pa = 98285.25;
% V2 显式记录 2/25/3 截面的 W、Tt、Pt，并由这些状态反算 AC/CC 的
% PRDes；AC/CC 和四级涡轮的 EffDes 均直接采用 DLL 变比热热力计算给出
% 的实际等熵效率。设计校准量最终同时折算进 PRDes/EffDes 与缩放系数。
% 入口程序只显式保留构造九维共同工作变量所需的 Rline 锚点；六个
% 部件的特性图路径从拆分 MDL 自动读取，避免形成第二份配置源。
cfg.component.AC.RlineDes = 0.6;
cfg.component.CC.RlineDes = 0.6;

% 求解变量：W2, PR_GT1, PR_GT2, PR_PT1, PR_PT2, Wf,
% kPR_AC, kEta_AC, kPR_CC, kEta_CC, kEta_GT, kEta_PT。
% Np/Ng 和 AC/CC 设计 Rline 是已知设计点量。六个 k 参数只在设计
% 求解中校准部件缩放系数；求解完成后分别折算进 s_C_PR、s_C_Eff
% 和 s_T_Eff，offDesignMode=2 及后续运行不保留健康修正输入。
cfg.solver.initial = [6.7; 2.0; 2.0; 1.9; 1.9; ...
    cfg.design.Wf0; 0; 0; 0; 0; 0; 0];
cfg.solver.scale = [10; 5; 5; 5; 5; 0.2; ...
    0.05; 0.05; 0.05; 0.05; 0.05; 0.05];
cfg.solver.lower = [0.5; 1.01; 1.01; 1.01; 1.01; 0.05; ...
    -0.2; -0.2; -0.2; -0.2; -0.2; -0.2];
cfg.solver.upper = [15; 8; 8; 8; 8; 0.35; ...
    0.2; 0.2; 0.2; 0.2; 0.2; 0.2];
cfg.solver.finiteDifferenceStep = 1.0e-4;
cfg.solver.maximumIterations = 40;
cfg.solver.residualTolerance = 1.0e-8;
cfg.solver.minimumLineSearchFactor = 1.0 / 256.0;
cfg.solver.maximumNormalizedStep = 0.5;
% 初值若落在喷管反压区，只缩小PT膨胀比的超1部分，逐次用DLL复核。
% 这不是设计约束，也不读取历史设计解；正式求解仍释放全部12个变量。
cfg.solver.maximumFeasibilityAttempts = 16;
cfg.solver.pressureRatioExcessRetention = 0.9;
cfg.solver.initialNozzlePressureRatio = 1.001; % 仅初值留出0.1%压差余量

cfg.tolerance.operationalResidual = 1.0e-7;
cfg.tolerance.workSplit = 1.0e-7;
cfg.tolerance.designReplayRelative = 1.0e-7;
cfg.tolerance.scaleReplayRelative = 1.0e-8;
cfg.tolerance.compressorStationRelative = 1.0e-7;
cfg.tolerance.designFieldReplayRelative = 1.0e-8;
cfg.tolerance.designFieldTrimRelative = 1.0e-7;
cfg.tolerance.pressureRatioClosureRelative = 1.0e-10;
cfg.tolerance.station2TargetRelative = 1.0e-10;
cfg.tolerance.manualMdlParameterRelative = 1.0e-8;
% offDesignMode=0 下，DLL 前六项是 Rline/N 设计锚点残差。
% V2 已把这些锚点的解析解直接代入，因此它们应当严格接近零。
cfg.tolerance.designAnchorResidual = 1.0e-12;

local_assert_core_files(cfg);
cfg.componentMapPath = local_read_component_map_paths(cfg.paths.splitMdl);
local_assert_component_map_files(cfg);
if ~isfolder(cfg.paths.middleData)
    mkdir(cfg.paths.middleData);
end
end

function local_assert_core_files(cfg)
required = {cfg.paths.dll, cfg.paths.header, cfg.paths.splitMdl};
for i = 1:numel(required)
    assert(isfile(required{i}), '缺少 M1 运行文件：%s', required{i});
end
end

function mapPath = local_read_component_map_paths(path)
%LOCAL_READ_COMPONENT_MAP_PATHS 从拆分 MDL 的部件段读取六条特性图路径。
% 每个目标部件必须且只能配置一条 mapPath，防止配置缺失或重复时
% 程序悄悄使用错误特性图。
componentNames = {'AC', 'CC', 'GT1', 'GT2', 'PT1', 'PT2'};
found = false(size(componentNames));
mapPath = struct();
currentComponent = '';
lines = regexp(fileread(path), '\r\n|\n|\r', 'split');

for i = 1:numel(lines)
    componentToken = regexp(lines{i}, ...
        '^\s*\[componentName\]\s*=\s*(.*?)\s*$', 'tokens', 'once');
    if ~isempty(componentToken)
        currentComponent = strtrim(componentToken{1});
        continue;
    end

    mapToken = regexp(lines{i}, ...
        '^\s*mapPath\s*=\s*(.*?)\s*$', 'tokens', 'once');
    index = find(strcmp(componentNames, currentComponent), 1);
    if isempty(mapToken) || isempty(index)
        continue;
    end

    assert(~found(index), ...
        '拆分 MDL 的部件 %s 重复配置 mapPath：%s', ...
        currentComponent, path);
    value = strtrim(mapToken{1});
    assert(~isempty(value), ...
        '拆分 MDL 的部件 %s 的 mapPath 为空：%s', ...
        currentComponent, path);
    mapPath.(currentComponent) = value;
    found(index) = true;
end

assert(all(found), '拆分 MDL 缺少以下部件的 mapPath：%s（文件：%s）', ...
    strjoin(componentNames(~found), ', '), path);
end

function local_assert_component_map_files(cfg)
componentNames = {'AC', 'CC', 'GT1', 'GT2', 'PT1', 'PT2'};
for i = 1:numel(componentNames)
    name = componentNames{i};
    configuredPath = cfg.componentMapPath.(name);
    if isempty(regexp(configuredPath, ...
            '^(?:[A-Za-z]:[\\/]|[\\/]{2}|/)', 'once'))
        resolvedPath = fullfile(cfg.paths.runtimeDir, configuredPath);
    else
        resolvedPath = configuredPath;
    end
    assert(isfile(resolvedPath), ...
        '拆分 MDL 的部件 %s 所引用特性图不存在：%s', ...
        name, resolvedPath);
end
end

function offDesignMode = local_read_off_design_mode(path)
text = fileread(path);
token = regexp(text, ...
    '(?m)^[ \t]*offDesignMode[ \t]*=[ \t]*([-+0-9.eE]+)', ...
    'tokens', 'once');
assert(~isempty(token), '配置文件缺少 offDesignMode：%s', path);
offDesignMode = str2double(token{1});
assert(isfinite(offDesignMode), '配置文件 offDesignMode 不是有效数值：%s', path);
end

function mdl = local_read_manual_design_parameters(path)
%LOCAL_READ_MANUAL_DESIGN_PARAMETERS 直接读取人工写入MDL的设计参数。
%
% 本函数不使用DLL回读值，目的是把设计状态与MDL原始文本逐项比较。
% 比较范围严格对应offDesignMode=0命令行打印的人工写入清单。
text = fileread(path);
mdl.offDesignMode = local_read_mdl_numeric_assignment( ...
    text, 'offDesignMode', path);
mdl.varStartVecDime = local_read_mdl_numeric_assignment( ...
    text, 'varStartVecDime', path);
mdl.varStartVec = local_read_mdl_numeric_assignment( ...
    text, 'varStartVec', path);

componentNames = {'AC', 'CC', 'GT1', 'GT2', 'PT1', 'PT2'};
fieldNames = struct();
fieldNames.AC = {'PRDes', 'EffDes', 's_C_Nc_in', 's_C_Wc_in', ...
    's_C_PR_in', 's_C_Eff_in'};
fieldNames.CC = fieldNames.AC;
turbineFields = {'EffDes', 's_T_Nc', 's_T_Wc', 's_T_PR', 's_T_Eff'};
fieldNames.GT1 = turbineFields;
fieldNames.GT2 = turbineFields;
fieldNames.PT1 = turbineFields;
fieldNames.PT2 = turbineFields;

for i = 1:numel(componentNames)
    component = componentNames{i};
    names = fieldNames.(component);
    for j = 1:numel(names)
        mdl.(component).(names{j}) = NaN;
    end
end

currentComponent = '';
lines = regexp(text, '\r\n|\n|\r', 'split');
for i = 1:numel(lines)
    componentToken = regexp(lines{i}, ...
        '^\s*\[componentName\]\s*=\s*(.*?)\s*$', 'tokens', 'once');
    if ~isempty(componentToken)
        currentComponent = strtrim(componentToken{1});
        continue;
    end
    if ~ismember(currentComponent, componentNames)
        continue;
    end

    assignment = regexp(lines{i}, ...
        '^\s*([A-Za-z][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$', ...
        'tokens', 'once');
    if isempty(assignment)
        continue;
    end
    name = assignment{1};
    if ~ismember(name, fieldNames.(currentComponent))
        continue;
    end
    assert(isnan(mdl.(currentComponent).(name)), ...
        '拆分MDL的部件%s重复配置字段%s：%s', ...
        currentComponent, name, path);
    value = sscanf(assignment{2}, '%f').';
    assert(isscalar(value) && isfinite(value), ...
        '拆分MDL的部件%s字段%s不是有效标量：%s', ...
        currentComponent, name, path);
    mdl.(currentComponent).(name) = value;
end
end

function value = local_read_mdl_numeric_assignment(text, name, path)
pattern = sprintf('(?m)^\\s*%s\\s*=\\s*(.*?)\\s*$', ...
    regexptranslate('escape', name));
token = regexp(text, pattern, 'tokens');
assert(numel(token) == 1, ...
    '拆分MDL字段%s缺失或重复：%s', name, path);
value = sscanf(token{1}{1}, '%f').';
assert(~isempty(value) && all(isfinite(value)), ...
    '拆分MDL字段%s不是有效数值：%s', name, path);
end

function comparison = local_compare_manual_design_parameters(design, cfg)
%LOCAL_COMPARE_MANUAL_DESIGN_PARAMETERS 对比全部人工写入设计参数。
mdl = local_read_manual_design_parameters(cfg.paths.splitMdl);

varNames = {'varStartVec(1).W2', 'varStartVec(2).AC_Rline', ...
    'varStartVec(3).CC_Rline', 'varStartVec(4).GT1_PR', ...
    'varStartVec(5).GT2_PR', 'varStartVec(6).PT1_PR', ...
    'varStartVec(7).PT2_PR', 'varStartVec(8).Np', ...
    'varStartVec(9).Ng'};
designFieldNames = {'AC.PRDes', 'AC.EffDes', 'CC.PRDes', ...
    'CC.EffDes', 'GT1.EffDes', 'GT2.EffDes', ...
    'PT1.EffDes', 'PT2.EffDes'};
scaleNames = { ...
    'AC.s_C_Nc_in', 'AC.s_C_Wc_in', 'AC.s_C_PR_in', 'AC.s_C_Eff_in', ...
    'CC.s_C_Nc_in', 'CC.s_C_Wc_in', 'CC.s_C_PR_in', 'CC.s_C_Eff_in', ...
    'GT1.s_T_Nc', 'GT1.s_T_Wc', 'GT1.s_T_PR', 'GT1.s_T_Eff', ...
    'GT2.s_T_Nc', 'GT2.s_T_Wc', 'GT2.s_T_PR', 'GT2.s_T_Eff', ...
    'PT1.s_T_Nc', 'PT1.s_T_Wc', 'PT1.s_T_PR', 'PT1.s_T_Eff', ...
    'PT2.s_T_Nc', 'PT2.s_T_Wc', 'PT2.s_T_PR', 'PT2.s_T_Eff'};

expectedVar = design.commonVariables(:).';
actualVar = nan(1, numel(expectedVar));
copyCount = min(numel(mdl.varStartVec), numel(actualVar));
actualVar(1:copyCount) = mdl.varStartVec(1:copyCount);
expectedDesignField = design.componentDesignFields.vector;
actualDesignField = [mdl.AC.PRDes, mdl.AC.EffDes, ...
    mdl.CC.PRDes, mdl.CC.EffDes, mdl.GT1.EffDes, ...
    mdl.GT2.EffDes, mdl.PT1.EffDes, mdl.PT2.EffDes];
expectedScale = design.scalars.vector;
actualScale = [ ...
    mdl.AC.s_C_Nc_in, mdl.AC.s_C_Wc_in, ...
    mdl.AC.s_C_PR_in, mdl.AC.s_C_Eff_in, ...
    mdl.CC.s_C_Nc_in, mdl.CC.s_C_Wc_in, ...
    mdl.CC.s_C_PR_in, mdl.CC.s_C_Eff_in, ...
    mdl.GT1.s_T_Nc, mdl.GT1.s_T_Wc, mdl.GT1.s_T_PR, mdl.GT1.s_T_Eff, ...
    mdl.GT2.s_T_Nc, mdl.GT2.s_T_Wc, mdl.GT2.s_T_PR, mdl.GT2.s_T_Eff, ...
    mdl.PT1.s_T_Nc, mdl.PT1.s_T_Wc, mdl.PT1.s_T_PR, mdl.PT1.s_T_Eff, ...
    mdl.PT2.s_T_Nc, mdl.PT2.s_T_Wc, mdl.PT2.s_T_PR, mdl.PT2.s_T_Eff];

comparison.names = [{'offDesignMode', 'varStartVecDime'}, ...
    varNames, designFieldNames, scaleNames];
comparison.designValue = [2, numel(expectedVar), expectedVar, ...
    expectedDesignField, expectedScale];
comparison.mdlValue = [mdl.offDesignMode, mdl.varStartVecDime, ...
    actualVar, actualDesignField, actualScale];
comparison.absoluteDifference = abs( ...
    comparison.mdlValue - comparison.designValue);
comparison.relativeDifference = local_relative_difference( ...
    comparison.mdlValue, comparison.designValue);
comparison.relativeDifference(~isfinite( ...
    comparison.relativeDifference)) = Inf;
comparison.passed = comparison.relativeDifference <= ...
    cfg.tolerance.manualMdlParameterRelative;
comparison.passed(1) = mdl.offDesignMode == 2;
comparison.passed(2) = mdl.varStartVecDime == numel(expectedVar) && ...
    numel(mdl.varStartVec) == numel(expectedVar);
comparison.allPassed = all(comparison.passed);
comparison.maximumRelativeDifference = max(comparison.relativeDifference);
comparison.tolerance = cfg.tolerance.manualMdlParameterRelative;
comparison.mdlPath = cfg.paths.splitMdl;

comparison.notWrittenNames = {'Wf', 'kPR_AC', 'kEta_AC', ...
    'kPR_CC', 'kEta_CC', 'kEta_GT', 'kEta_PT'};
comparison.notWrittenDesignValue = [design.Wf, ...
    design.compressorCorrection, design.efficiencyCorrection];
end

function local_initialize(alias, engPtr, stepIn, stepOut, cfg)
status = calllib(alias, 'DLL_SHT_InitialMode', 1);
assert(status == 0, '六部件 DLL mode=1 初始化失败，状态码=%d。', status);
stepIn.Value = zeros(cfg.interface.stepInLength, 1);
stepOut.Value = zeros(cfg.interface.stepOutLength, 1);
stepIn.Value(11:13) = [0; 0; 0];
status = calllib(alias, 'DLL_SHT_ConditionsInit', stepIn, stepOut, engPtr);
assert(status == 0, '环境条件初始化失败，状态码=%d。', status);
end

function initial = local_initial_design_vector(cfg)
initial = cfg.solver.initial(:);
initial = min(max(initial, cfg.solver.lower), cfg.solver.upper);
end

function [solution, history, design] = local_solve_design( ...
    alias, engPtr, stepIn, stepOut, initial, cfg)
x = initial(:);
[x, initialization] = local_prepare_feasible_design_initial( ...
    alias, engPtr, stepIn, stepOut, x, cfg);
n = numel(x);
history.iteration = zeros(cfg.solver.maximumIterations, 1);
history.residualInfinityNorm = nan(cfg.solver.maximumIterations, 1);
history.residualTwoNorm = nan(cfg.solver.maximumIterations, 1);
history.lineSearchFactor = nan(cfg.solver.maximumIterations, 1);
history.jacobianReciprocalCondition = nan(cfg.solver.maximumIterations, 1);
history.variable = nan(cfg.solver.maximumIterations, n);
history.nozzlePressureRatio = nan(cfg.solver.maximumIterations, 1);
history.rejectedBackPressureSteps = zeros(cfg.solver.maximumIterations, 1);

for iteration = 1:cfg.solver.maximumIterations
    [residual, sample] = local_design_residual( ...
        alias, engPtr, stepIn, stepOut, x, cfg);
    residualInf = norm(residual, inf);
    residualTwo = norm(residual, 2);
    history.iteration(iteration) = iteration;
    history.residualInfinityNorm(iteration) = residualInf;
    history.residualTwoNorm(iteration) = residualTwo;
    history.variable(iteration, :) = x.';
    history.nozzlePressureRatio(iteration) = sample.nozzlePressureRatio;
    fprintf('M1 设计点迭代 %2d：max|r|=%.6e, ||r||2=%.6e\n', ...
        iteration, residualInf, residualTwo);
    if local_design_converged(residual, sample, cfg)
        break;
    end

    jacobian = zeros(numel(residual), n);
    h = cfg.solver.finiteDifferenceStep;
    for j = 1:n
        plus = x;
        minus = x;
        plus(j) = min(cfg.solver.upper(j), x(j) + h * cfg.solver.scale(j));
        minus(j) = max(cfg.solver.lower(j), x(j) - h * cfg.solver.scale(j));
        normalizedSpan = (plus(j) - minus(j)) / cfg.solver.scale(j);
        assert(normalizedSpan > 0, '变量 %d 有限差分区间退化。', j);
        [residualPlus, samplePlus] = local_design_residual( ...
            alias, engPtr, stepIn, stepOut, plus, cfg);
        [residualMinus, sampleMinus] = local_design_residual( ...
            alias, engPtr, stepIn, stepOut, minus, cfg);
        % 反压区的喷管残差不代表本设计任务的正向排气方程。
        % 差分跨越该边界时用可行侧差分，不将反压侧数值混入Jacobian。
        plusFeasible = samplePlus.nozzlePressureRatio > 1 && plus(j) > x(j);
        minusFeasible = sampleMinus.nozzlePressureRatio > 1 && minus(j) < x(j);
        if plusFeasible && minusFeasible
            jacobian(:, j) = (residualPlus - residualMinus) / normalizedSpan;
        elseif plusFeasible
            jacobian(:, j) = (residualPlus - residual) / ...
                ((plus(j) - x(j)) / cfg.solver.scale(j));
        elseif minusFeasible
            jacobian(:, j) = (residual - residualMinus) / ...
                ((x(j) - minus(j)) / cfg.solver.scale(j));
        else
            error('RunModelSHT_V2:NoFeasibleDifference', ...
                ['设计变量%d两侧差分均不可用；喷管Pt/Pback为%.9g、%.9g，', ...
                 '请检查初值和变量边界。'], ...
                j, samplePlus.nozzlePressureRatio, sampleMinus.nozzlePressureRatio);
        end
    end

    reciprocalCondition = rcond(jacobian);
    history.jacobianReciprocalCondition(iteration) = reciprocalCondition;
    if reciprocalCondition > 1.0e-12
        normalizedStep = -(jacobian \ residual);
    else
        % 近奇异时用小规模 Tikhonov 正则化求解，避免显式 inv(J)。
        regularization = max(1.0e-10, 1.0e-6 * norm(jacobian, 'fro')^2);
        normalizedStep = -(jacobian.' * jacobian + ...
            regularization * eye(n)) \ (jacobian.' * residual);
    end
    maximumStep = max(abs(normalizedStep));
    if maximumStep > cfg.solver.maximumNormalizedStep
        normalizedStep = normalizedStep * ...
            (cfg.solver.maximumNormalizedStep / maximumStep);
    end

    accepted = false;
    factor = 1.0;
    while factor >= cfg.solver.minimumLineSearchFactor
        candidate = x + factor * normalizedStep .* cfg.solver.scale;
        candidate = min(max(candidate, cfg.solver.lower), cfg.solver.upper);
        [candidateResidual, candidateSample] = local_design_residual( ...
            alias, engPtr, stepIn, stepOut, candidate, cfg);
        feasible = candidateSample.nozzlePressureRatio > 1;
        if ~feasible
            history.rejectedBackPressureSteps(iteration) = ...
                history.rejectedBackPressureSteps(iteration) + 1;
        end
        if feasible && norm(candidateResidual, 2) < residualTwo
            x = candidate;
            accepted = true;
            break;
        end
        factor = factor / 2.0;
    end
    history.lineSearchFactor(iteration) = factor;
    assert(accepted, ...
        ['M1设计迭代%d未找到可行下降步，max|r|=%.6e，', ...
         '喷管Pt/Pback=%.9g，Tt2实际/目标=%.12g/%.12g K，', ...
         'Pt2实际/目标=%.12g/%.12g Pa。未满足最终精度，不作为收敛；', ...
         '请检查设计目标、初值、特性图覆盖及变量边界。'], ...
        iteration, residualInf, sample.nozzlePressureRatio, ...
        sample.compressorPath.totalTemperatureK(1), cfg.design.targetTt2K, ...
        sample.compressorPath.totalPressurePa(1), cfg.design.targetPt2Pa);
end

[finalResidual, finalSample] = local_design_residual( ...
    alias, engPtr, stepIn, stepOut, x, cfg);
activeMaxResidual = norm(finalResidual, inf);
% 最终DLL复算是唯一验收依据，不继承循环内较早一次的收敛标志。
converged = local_design_converged(finalResidual, finalSample, cfg);
assert(converged, 'RunModelSHT_V2:FinalDesignNotConverged', ...
    ['M1设计点最终复算未通过（已执行%d轮，上限%d轮），max|r|=%.6e；', ...
     'Tt2实际/目标=%.12g/%.12g K，Pt2实际/目标=%.12g/%.12g Pa，', ...
     '2截面相对差%.6e，压比闭合相对差%.6e。'], ...
    iteration, cfg.solver.maximumIterations, activeMaxResidual, ...
    finalSample.compressorPath.totalTemperatureK(1), cfg.design.targetTt2K, ...
    finalSample.compressorPath.totalPressurePa(1), cfg.design.targetPt2Pa, ...
    finalSample.station2TargetMaxRelative, ...
    finalSample.componentDesignFields.pressureRatioClosureMaxRelative);

used = find(history.iteration > 0, 1, 'last');
fields = fieldnames(history);
for i = 1:numel(fields)
    value = history.(fields{i});
    history.(fields{i}) = value(1:used, :);
end

solution = x;
design = finalSample;
design.initialization = initialization;
design.residual = finalResidual;
design.activeMaxResidual = activeMaxResidual;
design.pressureRatioClosureMaxRelative = ...
    design.componentDesignFields.pressureRatioClosureMaxRelative;
design.maxResidual = max(activeMaxResidual, ...
    design.designAnchor.maxResidual);
design.converged = converged && ...
    design.designAnchor.maxResidual <= cfg.tolerance.designAnchorResidual && ...
    design.station2TargetMaxRelative <= cfg.tolerance.station2TargetRelative && ...
    design.pressureRatioClosureMaxRelative <= ...
        cfg.tolerance.pressureRatioClosureRelative;
assert(design.pressureRatioClosureMaxRelative <= ...
    cfg.tolerance.pressureRatioClosureRelative, ...
    ['设计求解已结束，但由显式2/25/3截面总压得到的AC/CC设计压比', ...
     '与DLL最终实际压比仍不闭合，最大相对差 %.6e。'], ...
    design.pressureRatioClosureMaxRelative);
assert(design.station2TargetMaxRelative <= cfg.tolerance.station2TargetRelative, ...
    ['设计求解结束后2截面目标仍不闭合：Tt2实际/目标=%.12g/%.12g K，', ...
     'Pt2实际/目标=%.12g/%.12g Pa，最大相对差%.6e。'], ...
    design.compressorPath.totalTemperatureK(1), cfg.design.targetTt2K, ...
    design.compressorPath.totalPressurePa(1), cfg.design.targetPt2Pa, ...
    design.station2TargetMaxRelative);
end

function passed = local_design_converged(residual, sample, cfg)
% 最终物理目标必须同时满足，不能仅凭残差变小或无下降步判定成功。
passed = norm(residual, inf) <= cfg.solver.residualTolerance && ...
    sample.designAnchor.maxResidual <= cfg.tolerance.designAnchorResidual && ...
    sample.station2TargetMaxRelative <= cfg.tolerance.station2TargetRelative && ...
    sample.componentDesignFields.pressureRatioClosureMaxRelative <= ...
        cfg.tolerance.pressureRatioClosureRelative && ...
    sample.nozzlePressureRatio > 1;
end

function [x, record] = local_prepare_feasible_design_initial( ...
    alias, engPtr, stepIn, stepOut, initial, cfg)
% 只恢复初值的正向排气可行性，不按历史解配平，也不在M端重建气路模型。
% 减小PT1/PT2膨胀比可提高喷管入口总压；是否可行完全由DLL回放判断。
x = initial(:);
record.original = x;
record.variable = [];
record.nozzlePressureRatio = [];
for attempt = 0:cfg.solver.maximumFeasibilityAttempts
    [~, sample] = local_design_residual(alias, engPtr, stepIn, stepOut, x, cfg);
    record.variable(end+1, :) = x.';
    record.nozzlePressureRatio(end+1, 1) = sample.nozzlePressureRatio;
    if sample.nozzlePressureRatio > cfg.solver.initialNozzlePressureRatio
        record.adjusted = x;
        record.attempts = attempt;
        record.applied = attempt > 0;
        if record.applied
            fprintf(['M1初值可行性恢复%d次：喷管Pt/Pback %.9g -> %.9g；', ...
                'PT1/PT2初始膨胀比 %.9g/%.9g -> %.9g/%.9g。\n'], ...
                attempt, record.nozzlePressureRatio(1), sample.nozzlePressureRatio, ...
                initial(4), initial(5), x(4), x(5));
        end
        return;
    end
    if attempt == cfg.solver.maximumFeasibilityAttempts
        break;
    end
    x(4:5) = max(cfg.solver.lower(4:5), ...
        1 + cfg.solver.pressureRatioExcessRetention * (x(4:5) - 1));
end
error('RunModelSHT_V2:InfeasibleDesignInitial', ...
    ['设计初值无法恢复正向排气：喷管总压%.12g Pa，背压%.12g Pa，', ...
     'Pt/Pback=%.9g。请检查PT初始膨胀比、边界和设计目标。'], ...
    sample.nozzleTotalPressurePa, sample.nozzleBackPressurePa, ...
    sample.nozzlePressureRatio);
end

function [residual, sample] = local_design_residual( ...
    alias, engPtr, stepIn, stepOut, x, cfg)
commonVariables = [x(1); cfg.component.AC.RlineDes; ...
    cfg.component.CC.RlineDes; x(2:5); cfg.design.NpRpm; cfg.design.NgRpm];
stepIn.Value = local_base_step_in( ...
    cfg, cfg.design.NpRpm, cfg.design.NgRpm, x(6));
stepIn.Value(21:29) = commonVariables;
% C 的修正系数从 stepIn(41) 起按 0 基 h 编号映射。
% h71:h88 为六个子部件的 [K_W,K_eta,K_PR]，顺序为
% AC、CC、GT1、GT2、PT1、PT2。设计点临时校准量只在本次
% offDesignMode=0 调用中非零，最终折算进 MDL 缩放系数。
stepIn.Value(114) = x(7);          % AC:  h73, K_PR
stepIn.Value(113) = x(8);          % AC:  h72, K_eta
stepIn.Value(117) = x(9);          % CC:  h76, K_PR
stepIn.Value(116) = x(10);         % CC:  h75, K_eta
stepIn.Value([119, 122]) = x(11);  % GT1/GT2: h78/h81, K_eta
stepIn.Value([125, 128]) = x(12);  % PT1/PT2: h84/h87, K_eta
[status, ~, stepOutValue, engOut] = calllib( ...
    alias, 'DLL_SHT_RunSteadyComponents', stepIn, stepOut, engPtr);
assert(status == 0, '拆分模型设计点部件求值失败，状态码=%d。', status);
eng = engOut.eng;

assert(all(isfinite(stepOutValue(1:9))), ...
    '设计点DLL九项共同工作残差中出现 NaN/Inf。');
designAnchor = local_validate_design_anchor_residual( ...
    stepOutValue(1:6), commonVariables, eng, cfg);

gtPower = [eng.HPT.y(19), eng.HPT2.y(19)];
ptPower = [eng.LPT.y(19), eng.LPT2.y(19)];
assert(all(isfinite(gtPower)) && all(isfinite(ptPower)), ...
    '设计点涡轮功率产生 NaN/Inf。');
assert(sum(gtPower) > 0 && sum(ptPower) > 0, ...
    '设计点涡轮功率必须为正值。');

residual = zeros(12, 1);
% offDesignMode=0 下，前六项并非流量匹配残差，而是 AC/CC 的
% Rline 设计锚点和四个涡轮的轴转速设计锚点。V2 已将这些方程的
% 解析解直接代入 commonVariables，并由上面的门禁逐项验证为零；
% 因此外层 Newton 只保留喷管、轴系、温度、总压和级做功方程。
residual(1) = gtPower(1) / sum(gtPower) - ...
    cfg.design.gtStageOneWorkFraction;
residual(2) = ptPower(1) / sum(ptPower) - ...
    cfg.design.ptStageOneWorkFraction;
residual(3) = stepOutValue(7); % 喷管流量匹配
residual(4) = stepOutValue(8); % 低压轴功率平衡
residual(5) = stepOutValue(9); % 高压轴功率平衡
residual(6) = (eng.Burner.y(3) - cfg.design.targetTt4K) / ...
    cfg.design.targetTt4K;
residual(7) = (eng.HPT2.y(4) - cfg.design.targetGTExitPressurePa) / ...
    cfg.design.targetGTExitPressurePa;
residual(8) = (eng.LPT2.y(4) - cfg.design.targetPTExitPressurePa) / ...
    cfg.design.targetPTExitPressurePa;
% AC/CC 不再由 MDL 中的 PRDes/EffDes 单独决定设计点，而是以 25、3
% 截面的总温总压为物理约束，反求最终应写入的压比/效率缩放系数。
residual(9) = (eng.HPC.y(3) - cfg.design.targetTt25K) / ...
    cfg.design.targetTt25K;
residual(10) = (eng.HPC.y(4) - cfg.design.targetPt25Pa) / ...
    cfg.design.targetPt25Pa;
residual(11) = (eng.HPC2.y(3) - cfg.design.targetTt3K) / ...
    cfg.design.targetTt3K;
residual(12) = (eng.HPC2.y(4) - cfg.design.targetPt3Pa) / ...
    cfg.design.targetPt3Pa;

sample.output = local_capture_output(eng);
% 从DLL实际喷管输入缓冲读总压和背压，避免解引用C裸指针或重算模型。
sample.nozzleTotalPressurePa = eng.Nozzle.u(4);
sample.nozzleBackPressurePa = eng.Nozzle.u(6);
sample.nozzlePressureRatio = ...
    sample.nozzleTotalPressurePa / sample.nozzleBackPressurePa;
sample.Tt4K = eng.Burner.y(3);
sample.gtPowerW = gtPower;
sample.ptPowerW = ptPower;
sample.gtWorkSplit = gtPower(1) / sum(gtPower);
sample.ptWorkSplit = ptPower(1) / sum(ptPower);
sample.turbineEfficiency = local_capture_turbine_efficiency(eng);
sample.compressorStation = local_capture_compressor_station(eng);
sample.compressorPerformance = local_capture_compressor_performance(eng);
sample.compressorPath = local_capture_compressor_path(eng);
sample.station2TargetRelative = local_station2_target_relative( ...
    sample.compressorPath, cfg);
sample.station2TargetMaxRelative = max(sample.station2TargetRelative);
% 流量迭代与有限差分会改变进口名义压损，故此处只记录目标偏差。
% 2截面精度与压比闭合在完整设计收敛时验收，门限保持原值。
sample.componentDesignFields = local_derive_component_design_fields( ...
    eng, sample.compressorPath, cfg);
sample.configuredDesignFields = local_capture_configured_design_fields(eng);
sample.commonVariables = commonVariables;
sample.Wf = x(6);
sample.scalars = local_capture_scalars(eng);
sample.scalars.AC(3) = sample.scalars.AC(3) * (1 + x(7));
sample.scalars.AC(4) = sample.scalars.AC(4) * (1 + x(8));
sample.scalars.CC(3) = sample.scalars.CC(3) * (1 + x(9));
sample.scalars.CC(4) = sample.scalars.CC(4) * (1 + x(10));
sample.scalars.GT1(4) = sample.scalars.GT1(4) * (1 + x(11));
sample.scalars.GT2(4) = sample.scalars.GT2(4) * (1 + x(11));
sample.scalars.PT1(4) = sample.scalars.PT1(4) * (1 + x(12));
sample.scalars.PT2(4) = sample.scalars.PT2(4) * (1 + x(12));
sample.scalars.vector = [sample.scalars.AC, sample.scalars.CC, ...
    sample.scalars.GT1, sample.scalars.GT2, ...
    sample.scalars.PT1, sample.scalars.PT2];
sample.compressorCorrection = x(7:10).';
sample.efficiencyCorrection = [x(11), x(12)];
sample.mapCoordinates = local_capture_map_coordinates(eng);
sample.dllResidual = stepOutValue(1:9).';
sample.designAnchor = designAnchor;
end

function anchor = local_validate_design_anchor_residual( ...
    residual, commonVariables, eng, cfg)
%LOCAL_VALIDATE_DESIGN_ANCHOR_RESIDUAL 验证设计锚点代数消元没有失配。
%
% offDesignMode=0 时，六部件模型调用 Compressor_TMATS_body，压气机
% y(7)=(Rline-RlineDes)/Rline；涡轮 y(7)=(N-NDes)/NDes。
% V2 不把这些已知根继续交给 Newton，但必须检查 M 程序传入值与
% DLL 从拆分 MDL 读取的锚点完全一致。

anchor.names = {'AC'; 'CC'; 'GT1'; 'GT2'; 'PT1'; 'PT2'};
anchor.quantities = {'Rline'; 'Rline'; 'Ng_rpm'; 'Ng_rpm'; ...
    'Np_rpm'; 'Np_rpm'};
anchor.inputValue = [commonVariables(2); commonVariables(3); ...
    commonVariables(9); commonVariables(9); ...
    commonVariables(8); commonVariables(8)];
anchor.configuredValue = [eng.HPC.compressorStruct.RlineDes; ...
    eng.HPC2.compressorStruct.RlineDes; ...
    eng.HPT.turbineStruct.NDes; eng.HPT2.turbineStruct.NDes; ...
    eng.LPT.turbineStruct.NDes; eng.LPT2.turbineStruct.NDes];
anchor.residual = residual(:);

assert(all(isfinite(anchor.inputValue)) && ...
    all(isfinite(anchor.configuredValue)) && ...
    all(anchor.inputValue(1:2) ~= 0) && ...
    all(anchor.configuredValue ~= 0), ...
    '设计锚点输入或DLL/MDL配置值非法。');

anchor.recomputedResidual = zeros(6, 1);
anchor.recomputedResidual(1:2) = ...
    (anchor.inputValue(1:2) - anchor.configuredValue(1:2)) ./ ...
    anchor.inputValue(1:2);
anchor.recomputedResidual(3:6) = ...
    (anchor.inputValue(3:6) - anchor.configuredValue(3:6)) ./ ...
    anchor.configuredValue(3:6);
anchor.maxResidual = max(abs(anchor.residual));
anchor.formulaMismatch = max(abs( ...
    anchor.residual - anchor.recomputedResidual));

tolerance = cfg.tolerance.designAnchorResidual;
if anchor.maxResidual <= tolerance && ...
        anchor.formulaMismatch <= tolerance
    return;
end

bad = find(abs(anchor.residual) > tolerance | ...
    abs(anchor.recomputedResidual) > tolerance);
if isempty(bad)
    bad = (1:numel(anchor.residual)).';
end

detailLine = cell(numel(bad), 1);
for k = 1:numel(bad)
    i = bad(k);
    detailLine{k} = sprintf( ...
        ['  %-3s %-7s：M程序传入=%.17g，DLL/MDL锚点=%.17g，', ...
         'DLL残差=%+.9e，公式复核=%+.9e\n'], ...
        anchor.names{i}, anchor.quantities{i}, ...
        anchor.inputValue(i), anchor.configuredValue(i), ...
        anchor.residual(i), anchor.recomputedResidual(i));
end
detail = [detailLine{:}];

if anchor.formulaMismatch > tolerance
    diagnosis = [ ...
        'DLL残差还与设计锚点公式不一致。请确认实际加载的是当前GTESS.dll，', ...
        '并确认Turboshaft-TS-Split.mdl的offDesignMode=0、部件顺序及接口版本正确。'];
else
    diagnosis = [ ...
        'M程序给定值与拆分MDL中的设计锚点不一致。请先确定目标值，再同步：', ...
        'AC/CC的RlineDes，GT1/GT2的NDes与cfg.design.NgRpm，', ...
        'PT1/PT2的NDes与cfg.design.NpRpm。'];
end

error('RunModelSHT_V2:DesignAnchorMismatch', '%s', sprintf( ...
    ['六部件设计锚点严格零残差检查失败（容差 %.3e）。\n', ...
     'offDesignMode=0下，stepOut(1:6)依次约束AC/CC的Rline及', ...
     'GT1/GT2/PT1/PT2的轴转速，不是流量残差。\n%s原因判断：%s'], ...
    tolerance, detail, diagnosis));
end

function verification = local_verify_operational_mdl( ...
    alias, engPtr, stepIn, stepOut, design, cfg)
verification.mdlParameterComparison = ...
    local_compare_manual_design_parameters(design, cfg);
stepIn.Value = local_base_step_in( ...
    cfg, cfg.design.NpRpm, cfg.design.NgRpm, design.Wf);
stepIn.Value(21:29) = design.commonVariables;
[status, ~, stepOutValue, engOut] = calllib( ...
    alias, 'DLL_SHT_RunSteadyComponents', stepIn, stepOut, engPtr);
assert(status == 0, '生成配置的直接设计点回放失败，状态码=%d。', status);
eng = engOut.eng;
directOutput = local_capture_output(eng);
directScalars = local_capture_input_scalars(eng);
directTurbineEfficiency = local_capture_turbine_efficiency(eng);
directCompressorStation = local_capture_compressor_station(eng);
directCompressorPerformance = local_capture_compressor_performance(eng);
directCompressorPath = local_capture_compressor_path(eng);
directComponentDesignFields = local_derive_component_design_fields( ...
    eng, directCompressorPath, cfg);
configuredDesignFields = local_capture_configured_design_fields(eng);
stationTargets = local_compressor_station_targets(cfg);
gtPower = [eng.HPT.y(19), eng.HPT2.y(19)];
ptPower = [eng.LPT.y(19), eng.LPT2.y(19)];

verification.directReplayResidual = stepOutValue(1:9);
verification.directReplayMaxResidual = max(abs(stepOutValue(1:9)));
verification.designReplayRelative = abs(directOutput - design.output) ./ ...
    max(abs(design.output), 1);
verification.designReplayMaxRelative = max(verification.designReplayRelative);
verification.scaleReplayRelative = local_relative_difference( ...
    directScalars.vector, design.scalars.vector);
verification.scaleReplayMaxRelative = max(verification.scaleReplayRelative);
verification.directReplayTurbineEfficiency = directTurbineEfficiency;
verification.directReplayCompressorStation = directCompressorStation;
verification.directReplayCompressorPerformance = directCompressorPerformance;
verification.directReplayCompressorPath = directCompressorPath;
verification.directStation2TargetRelative = ...
    local_station2_target_relative(directCompressorPath, cfg);
verification.directStation2TargetMaxRelative = max( ...
    verification.directStation2TargetRelative);
verification.directReplayComponentDesignFields = directComponentDesignFields;
verification.configuredDesignFields = configuredDesignFields;
verification.configuredDesignFieldRelative = local_relative_difference( ...
    configuredDesignFields.vector, design.componentDesignFields.vector);
verification.configuredDesignFieldMaxRelative = max( ...
    verification.configuredDesignFieldRelative);
verification.derivedDesignFieldRelative = local_relative_difference( ...
    directComponentDesignFields.vector, design.componentDesignFields.vector);
verification.derivedDesignFieldMaxRelative = max( ...
    verification.derivedDesignFieldRelative);
verification.directStationTargetRelative = local_relative_difference( ...
    directCompressorStation, stationTargets);
verification.directStationTargetMaxRelative = max( ...
    verification.directStationTargetRelative);
verification.gtWorkSplit = gtPower(1) / sum(gtPower);
verification.ptWorkSplit = ptPower(1) / sum(ptPower);
verification.gtWorkSplitError = abs(verification.gtWorkSplit - ...
    cfg.design.gtStageOneWorkFraction);
verification.ptWorkSplitError = abs(verification.ptWorkSplit - ...
    cfg.design.ptStageOneWorkFraction);

% 使用配置内的 varStartVec 再运行一次 C 端 Newton，验证配置
% 可脱离设计程序独立加载和配平。
stepIn.Value = local_base_step_in( ...
    cfg, cfg.design.NpRpm, cfg.design.NgRpm, design.Wf);
[status, ~, ~, trimEngOut] = calllib( ...
    alias, 'DLL_SHT_RunOnePoint', stepIn, stepOut, engPtr);
assert(status == 0, '生成配置的内部 Newton 配平调用失败。');
trimEng = trimEngOut.eng;
verification.trimConvergeTag = trimEng.convergeTag;
verification.trimConverged = trimEng.convergeTag == 0;
verification.trimMaxResidual = max(abs(trimEng.errOut(1:9)));
verification.trimVariable = trimEng.varIte(1:9).';
verification.trimOutput = local_capture_output(trimEng);
verification.trimTurbineEfficiency = ...
    local_capture_turbine_efficiency(trimEng);
verification.trimCompressorStation = ...
    local_capture_compressor_station(trimEng);
verification.trimCompressorPerformance = ...
    local_capture_compressor_performance(trimEng);
verification.trimCompressorPath = local_capture_compressor_path(trimEng);
verification.trimStation2TargetRelative = ...
    local_station2_target_relative(verification.trimCompressorPath, cfg);
verification.trimStation2TargetMaxRelative = max( ...
    verification.trimStation2TargetRelative);
verification.trimComponentDesignFields = ...
    local_derive_component_design_fields( ...
    trimEng, verification.trimCompressorPath, cfg);
verification.trimDesignFieldRelative = local_relative_difference( ...
    verification.trimComponentDesignFields.vector, ...
    design.componentDesignFields.vector);
verification.trimDesignFieldMaxRelative = max( ...
    verification.trimDesignFieldRelative);
verification.trimStationTargetRelative = local_relative_difference( ...
    verification.trimCompressorStation, stationTargets);
verification.trimStationTargetMaxRelative = max( ...
    verification.trimStationTargetRelative);

% 本函数只依据六部件设计结果判断运行配置能否忠实复现并独立收敛。
verification.accepted = ...
    verification.mdlParameterComparison.allPassed && ...
    verification.directReplayMaxResidual <= cfg.tolerance.operationalResidual && ...
    verification.designReplayMaxRelative <= cfg.tolerance.designReplayRelative && ...
    verification.scaleReplayMaxRelative <= cfg.tolerance.scaleReplayRelative && ...
    verification.configuredDesignFieldMaxRelative <= ...
        cfg.tolerance.designFieldReplayRelative && ...
    verification.derivedDesignFieldMaxRelative <= ...
        cfg.tolerance.designFieldReplayRelative && ...
    directComponentDesignFields.pressureRatioClosureMaxRelative <= ...
        cfg.tolerance.pressureRatioClosureRelative && ...
    verification.directStation2TargetMaxRelative <= ...
        cfg.tolerance.station2TargetRelative && ...
    verification.directStationTargetMaxRelative <= ...
        cfg.tolerance.compressorStationRelative && ...
    verification.trimStationTargetMaxRelative <= ...
        cfg.tolerance.compressorStationRelative && ...
    verification.trimDesignFieldMaxRelative <= ...
        cfg.tolerance.designFieldTrimRelative && ...
    verification.trimStation2TargetMaxRelative <= ...
        cfg.tolerance.station2TargetRelative && ...
    verification.gtWorkSplitError <= cfg.tolerance.workSplit && ...
    verification.ptWorkSplitError <= cfg.tolerance.workSplit && ...
    verification.trimConverged && ...
    verification.trimMaxResidual <= cfg.tolerance.operationalResidual;
end

function designState = local_make_design_state(solution, design, cfg)
designState.schemaVersion = 5;
designState.generatedAt = datestr(now, 31);
designState.modelMode = 1;
designState.modelConfiguration = 'Turboshaft-TS-Split.mdl';
designState.solution = solution;
designState.design = design;
designState.designTargets = cfg.design;
designState.targetWorkSplit = [cfg.design.gtStageOneWorkFraction, ...
    cfg.design.ptStageOneWorkFraction];
end

function local_save_design_state(path, designState)
save(path, 'designState', '-v7');
end

function designState = local_load_design_state(path, cfg)
assert(isfile(path), ...
    ['未找到 V2 设计状态记录：%s\n请先把 Turboshaft-TS-Split.mdl ', ...
     '设为 offDesignMode=0 并运行 V2，人工写入输出参数后再以 ', ...
     'offDesignMode=2 运行验证。'], path);
loaded = load(path, 'designState');
assert(isfield(loaded, 'designState'), ...
    'V2 设计状态文件不含 designState：%s', path);
designState = loaded.designState;
assert(isfield(designState, 'modelMode') && designState.modelMode == 1, ...
    'V2 设计状态文件与六部件模型不匹配：%s', path);
assert(isfield(designState, 'schemaVersion') && ...
    designState.schemaVersion >= 5 && isfield(designState, 'designTargets'), ...
    ['V2 设计状态不是包含显式2截面目标及部件设计字段的当前版本：%s\n', ...
     '请先以 offDesignMode=0 重新运行 V2，生成 schemaVersion=5 的状态。'], path);
assert(isfield(designState, 'design') && ...
    numel(designState.design.commonVariables) == 9, ...
    'V2 设计状态文件缺少有效的九维共同工作变量：%s', path);
assert(isfield(designState.design, 'compressorPath') && ...
    isfield(designState.design, 'componentDesignFields') && ...
    numel(designState.design.componentDesignFields.vector) == 8, ...
    'V2 设计状态缺少 2/25/3 截面或八项部件设计字段：%s', path);
targetNames = {'NpRpm', 'NgRpm', 'loadPowerW', ...
    'targetTt2K', 'targetPt2Pa', 'targetTt4K', ...
    'targetTt25K', 'targetPt25Pa', 'targetTt3K', 'targetPt3Pa', ...
    'targetGTExitPressurePa', 'targetPTExitPressurePa'};
for i = 1:numel(targetNames)
    name = targetNames{i};
    assert(isfield(designState.designTargets, name), ...
        'V2 设计状态缺少设计目标 %s：%s', name, path);
    relative = local_relative_difference( ...
        designState.designTargets.(name), cfg.design.(name));
    assert(relative <= 1.0e-12, ...
        ['V2 当前设计目标 %s 与设计状态不一致（相对差 %.6e）。\n', ...
         '请先以 offDesignMode=0 重新求解。'], name, relative);
end
end

function local_print_design_result(result, cfg)
d = result.design;
fprintf('\nV2 M1 六部件设计点参数求解完成。\n');
fprintf('  最大设计残差              : %.6e\n', d.maxResidual);
fprintf('  六部件设计锚点最大残差    : %.6e\n', ...
    d.designAnchor.maxResidual);
fprintf('  DLL喷管/低压轴/高压轴残差 : %+.6e / %+.6e / %+.6e\n', ...
    d.dllResidual(7), d.dllResidual(8), d.dllResidual(9));
fprintf('  GT1/GT2 轴功率比           : %.9f / %.9f\n', ...
    d.gtWorkSplit, 1 - d.gtWorkSplit);
fprintf('  PT1/PT2 轴功率比           : %.9f / %.9f\n', ...
    d.ptWorkSplit, 1 - d.ptWorkSplit);
fprintf(['  涡轮设计点实际等熵效率     : GT1=%.9f，GT2=%.9f，', ...
    'PT1=%.9f，PT2=%.9f\n'], d.turbineEfficiency);
fprintf(['  压气机截面 Tt25/Pt25/Tt3/Pt3: %.9f K / %.6f Pa / ', ...
    '%.9f K / %.6f Pa\n'], d.compressorStation);
fprintf(['  压气机实际 PR/Eff           : AC=%.9f/%.9f，', ...
    'CC=%.9f/%.9f\n'], d.compressorPerformance);
fprintf('  2 截面显式设计值 Tt/Pt      : %.9f K / %.6f Pa\n', ...
    cfg.design.targetTt2K, cfg.design.targetPt2Pa);
local_print_compressor_path(d.compressorPath);
fprintf('  2 截面设计值最大相对误差    : %.6e\n', ...
    d.station2TargetMaxRelative);
fprintf(['  反算设计字段                 : AC(PRDes/EffDes)=%.12g/%.12g，', ...
    'CC(PRDes/EffDes)=%.12g/%.12g\n'], ...
    d.componentDesignFields.AC, d.componentDesignFields.CC);
fprintf(['  反算涡轮 EffDes              : GT1=%.12g，GT2=%.12g，', ...
    'PT1=%.12g，PT2=%.12g\n'], ...
    d.componentDesignFields.GT1, d.componentDesignFields.GT2, ...
    d.componentDesignFields.PT1, d.componentDesignFields.PT2);
fprintf('  设计点 Tt4 / P45 / P5      : %.6f K / %.6f Pa / %.6f Pa\n', ...
    d.Tt4K, d.output(5), d.output(7));
fprintf('  设计燃油流量               : %.17g kg/s（不是 MDL 字段）\n', d.Wf);
fprintf(['  kPR_AC / kEta_AC / kPR_CC / kEta_CC: ', ...
    '%.17g / %.17g / %.17g / %.17g\n'], d.compressorCorrection);
fprintf('  kEtaGT / kEtaPT            : %.17g / %.17g\n', ...
    d.efficiencyCorrection(1), d.efficiencyCorrection(2));
fprintf(['  上述辅助量已折算进 AC/CC 的 s_C_PR/s_C_Eff 和四个涡轮的 ', ...
    's_T_Eff，不作为运行参数保留。\n']);

fprintf('\n请人工审核后在 Turboshaft-TS-Split.mdl 中写入：\n');
fprintf('offDesignMode=2\n');
fprintf('varStartVecDime=9\n');
fprintf('varStartVec=%s\n', local_format_vector(d.commonVariables));
local_print_compressor_configuration( ...
    'AC', d.componentDesignFields.AC, d.scalars.AC);
local_print_compressor_configuration( ...
    'CC', d.componentDesignFields.CC, d.scalars.CC);
local_print_turbine_configuration( ...
    'GT1', d.componentDesignFields.GT1, d.scalars.GT1);
local_print_turbine_configuration( ...
    'GT2', d.componentDesignFields.GT2, d.scalars.GT2);
local_print_turbine_configuration( ...
    'PT1', d.componentDesignFields.PT1, d.scalars.PT1);
local_print_turbine_configuration( ...
    'PT2', d.componentDesignFields.PT2, d.scalars.PT2);
fprintf(['\n程序没有修改 MDL。人工写入后保持 offDesignMode=2，', ...
    '再次运行 RunModelSHT_V2_2DP 完成复现验证。\n']);
fprintf('设计状态记录：%s\n', cfg.paths.designState);
end

function local_print_verification_result(result, cfg)
v = result.verification;
fprintf('\nV2 M1 六部件手工配置验证完成。\n');
local_print_mdl_parameter_comparison(v.mdlParameterComparison);
fprintf('  直接回放最大共同工作残差  : %.6e\n', ...
    v.directReplayMaxResidual);
fprintf('  设计/运行输出最大相对差    : %.6e\n', ...
    v.designReplayMaxRelative);
fprintf('  缩放系数最大相对差         : %.6e\n', ...
    v.scaleReplayMaxRelative);
fprintf('  GT1/GT2 轴功率比            : %.9f / %.9f\n', ...
    v.gtWorkSplit, 1 - v.gtWorkSplit);
fprintf('  PT1/PT2 轴功率比            : %.9f / %.9f\n', ...
    v.ptWorkSplit, 1 - v.ptWorkSplit);
fprintf(['  涡轮设计点实际等熵效率      : GT1=%.9f，GT2=%.9f，', ...
    'PT1=%.9f，PT2=%.9f\n'], v.directReplayTurbineEfficiency);
fprintf(['  压气机截面 Tt25/Pt25/Tt3/Pt3 : %.9f K / %.6f Pa / ', ...
    '%.9f K / %.6f Pa\n'], v.directReplayCompressorStation);
fprintf(['  压气机实际 PR/Eff             : AC=%.9f/%.9f，', ...
    'CC=%.9f/%.9f\n'], v.directReplayCompressorPerformance);
local_print_compressor_path(v.directReplayCompressorPath);
fprintf('  2 截面显式设计值 Tt/Pt       : %.9f K / %.6f Pa\n', ...
    cfg.design.targetTt2K, cfg.design.targetPt2Pa);
fprintf('  2 截面设计值最大相对误差     : %.6e\n', ...
    v.directStation2TargetMaxRelative);
fprintf('  MDL设计字段最大相对差         : %.6e\n', ...
    v.configuredDesignFieldMaxRelative);
fprintf('  回放反算设计字段最大相对差     : %.6e\n', ...
    v.derivedDesignFieldMaxRelative);
fprintf('  压气机截面目标最大相对误差   : %.6e\n', ...
    v.directStationTargetMaxRelative);
fprintf('  C 端 Newton 独立配平        : %s\n', ...
    local_pass_fail(v.trimConverged));
fprintf('  C 端 Newton 最大残差        : %.6e\n', v.trimMaxResidual);
fprintf('  配平后截面目标最大相对误差   : %.6e\n', ...
    v.trimStationTargetMaxRelative);
fprintf('  配平后设计字段最大相对误差   : %.6e\n', ...
    v.trimDesignFieldMaxRelative);
fprintf('  配平后2截面最大相对误差      : %.6e\n', ...
    v.trimStation2TargetMaxRelative);
fprintf('  完整设计复现验收            : %s\n', ...
    local_pass_fail(result.accepted));
fprintf('  设计状态记录                : %s\n', cfg.paths.designState);
fprintf('  结果摘要                    : %s\n', cfg.paths.summary);
end

function local_print_mdl_parameter_comparison(comparison)
fprintf(['\n  offDesignMode=2设计参数与MDL原始文本逐项对比', ...
    '（共%d项，门限%.3e）\n'], ...
    numel(comparison.names), comparison.tolerance);
fprintf('  %-30s %20s %20s %12s %6s\n', ...
    '参数', '设计值', 'MDL值', '相对误差', '结果');
for i = 1:numel(comparison.names)
    fprintf('  %-30s %20.12g %20.12g %12.3e %6s\n', ...
        comparison.names{i}, comparison.designValue(i), ...
        comparison.mdlValue(i), comparison.relativeDifference(i), ...
        local_pass_fail(comparison.passed(i)));
end
fprintf('  %d项人工写入参数总体核对     : %s\n', ...
    numel(comparison.names), local_pass_fail(comparison.allPassed));

fprintf(['\n  以下设计求解量没有对应MDL字段，不参与写入值比较；', ...
    '程序运行时相应临时修正保持为零：\n']);
for i = 1:numel(comparison.notWrittenNames)
    fprintf('  %-30s %20.12g\n', ...
        comparison.notWrittenNames{i}, ...
        comparison.notWrittenDesignValue(i));
end
end

function local_print_compressor_configuration(name, designField, value)
fprintf('[%s]\n', name);
fprintf('PRDes=%.17g\n', designField(1));
fprintf('EffDes=%.17g\n', designField(2));
fprintf('s_C_Nc_in=%.17g\n', value(1));
fprintf('s_C_Wc_in=%.17g\n', value(2));
fprintf('s_C_PR_in=%.17g\n', value(3));
fprintf('s_C_Eff_in=%.17g\n', value(4));
end

function local_print_turbine_configuration(name, designField, value)
fprintf('[%s]\n', name);
fprintf('EffDes=%.17g\n', designField);
fprintf('s_T_Nc=%.17g\n', value(1));
fprintf('s_T_Wc=%.17g\n', value(2));
fprintf('s_T_PR=%.17g\n', value(3));
fprintf('s_T_Eff=%.17g\n', value(4));
end

function scalars = local_capture_scalars(eng)
scalars.AC = [eng.HPC.s_C_Nc_des, eng.HPC.s_C_Wc_des, ...
    eng.HPC.s_C_PR_des, eng.HPC.s_C_Eff_des];
scalars.CC = [eng.HPC2.s_C_Nc_des, eng.HPC2.s_C_Wc_des, ...
    eng.HPC2.s_C_PR_des, eng.HPC2.s_C_Eff_des];
scalars.GT1 = [eng.HPT.s_T_Nc_des, eng.HPT.s_T_Wc_des, ...
    eng.HPT.s_T_PR_des, eng.HPT.s_T_Eff_des];
scalars.GT2 = [eng.HPT2.s_T_Nc_des, eng.HPT2.s_T_Wc_des, ...
    eng.HPT2.s_T_PR_des, eng.HPT2.s_T_Eff_des];
scalars.PT1 = [eng.LPT.s_T_Nc_des, eng.LPT.s_T_Wc_des, ...
    eng.LPT.s_T_PR_des, eng.LPT.s_T_Eff_des];
scalars.PT2 = [eng.LPT2.s_T_Nc_des, eng.LPT2.s_T_Wc_des, ...
    eng.LPT2.s_T_PR_des, eng.LPT2.s_T_Eff_des];
scalars.vector = [scalars.AC, scalars.CC, scalars.GT1, ...
    scalars.GT2, scalars.PT1, scalars.PT2];
end

function scalars = local_capture_input_scalars(eng)
scalars.AC = [eng.HPC.s_C_Nc_in, eng.HPC.s_C_Wc_in, ...
    eng.HPC.s_C_PR_in, eng.HPC.s_C_Eff_in];
scalars.CC = [eng.HPC2.s_C_Nc_in, eng.HPC2.s_C_Wc_in, ...
    eng.HPC2.s_C_PR_in, eng.HPC2.s_C_Eff_in];
scalars.GT1 = [eng.HPT.turbineStruct.s_T_Nc, eng.HPT.turbineStruct.s_T_Wc, ...
    eng.HPT.turbineStruct.s_T_PR, eng.HPT.turbineStruct.s_T_Eff];
scalars.GT2 = [eng.HPT2.turbineStruct.s_T_Nc, eng.HPT2.turbineStruct.s_T_Wc, ...
    eng.HPT2.turbineStruct.s_T_PR, eng.HPT2.turbineStruct.s_T_Eff];
scalars.PT1 = [eng.LPT.turbineStruct.s_T_Nc, eng.LPT.turbineStruct.s_T_Wc, ...
    eng.LPT.turbineStruct.s_T_PR, eng.LPT.turbineStruct.s_T_Eff];
scalars.PT2 = [eng.LPT2.turbineStruct.s_T_Nc, eng.LPT2.turbineStruct.s_T_Wc, ...
    eng.LPT2.turbineStruct.s_T_PR, eng.LPT2.turbineStruct.s_T_Eff];
scalars.vector = [scalars.AC, scalars.CC, scalars.GT1, ...
    scalars.GT2, scalars.PT1, scalars.PT2];
end

function coordinates = local_capture_map_coordinates(eng)
coordinates.AC = [eng.HPC.y(16), eng.HPC_Rline];
coordinates.CC = [eng.HPC2.y(16), eng.HPC2_Rline];
coordinates.GT1 = [eng.HPT.y(15), eng.HPT.y(17)];
coordinates.GT2 = [eng.HPT2.y(15), eng.HPT2.y(17)];
coordinates.PT1 = [eng.LPT.y(15), eng.LPT.y(17)];
coordinates.PT2 = [eng.LPT2.y(15), eng.LPT2.y(17)];
end

function station = local_capture_compressor_station(eng)
% 顺序固定为 [Tt25, Pt25, Tt3, Pt3]，便于与设计目标逐项比较。
station = [eng.HPC.y(3), eng.HPC.y(4), ...
    eng.HPC2.y(3), eng.HPC2.y(4)];
assert(all(isfinite(station)), '压气机 25/3 截面状态出现 NaN/Inf。');
end

function performance = local_capture_compressor_performance(eng)
% Compressor_TMATS_body.c 中 y[14]、y[26] 分别为实际压比和实际效率；
% MATLAB 从 1 开始编号，因此读取 y(15)、y(27)。
performance = [eng.HPC.y(15), eng.HPC.y(27), ...
    eng.HPC2.y(15), eng.HPC2.y(27)];
assert(all(isfinite(performance)), 'AC/CC 实际压比或效率出现 NaN/Inf。');
end

function path = local_capture_compressor_path(eng)
%LOCAL_CAPTURE_COMPRESSOR_PATH 记录串联压气机 2/25/3 截面的热力状态。
%
% 2 截面是 Inlet 出口和 AC 进口。本函数只读取 DLL 的实际计算结果，
% 不在 MATLAB 中重复实现环境或进气道模型；实际值随后与V2顶部显式
% 给定的设计值比较。
path.stationName = {'2', '25', '3'};
path.massFlowKgPerS = [eng.Inlet.gasPathOut(1), ...
    eng.HPC.y(1), eng.HPC2.y(1)];
path.totalTemperatureK = [eng.Inlet.gasPathOut(3), ...
    eng.HPC.y(3), eng.HPC2.y(3)];
path.totalPressurePa = [eng.Inlet.gasPathOut(4), ...
    eng.HPC.y(4), eng.HPC2.y(4)];
path.vector = [path.massFlowKgPerS(1), path.totalTemperatureK(1), ...
    path.totalPressurePa(1), path.massFlowKgPerS(2), ...
    path.totalTemperatureK(2), path.totalPressurePa(2), ...
    path.massFlowKgPerS(3), path.totalTemperatureK(3), ...
    path.totalPressurePa(3)];
assert(all(isfinite(path.vector)) && ...
    all(path.massFlowKgPerS > 0) && ...
    all(path.totalTemperatureK > 0) && all(path.totalPressurePa > 0), ...
    '压气机 2/25/3 截面状态非法。');
end

function relative = local_station2_target_relative(path, cfg)
%LOCAL_STATION2_TARGET_RELATIVE 比较DLL结果与事先给定的2截面设计值。
actual = [path.totalTemperatureK(1), path.totalPressurePa(1)];
target = [cfg.design.targetTt2K, cfg.design.targetPt2Pa];
relative = local_relative_difference(actual, target);
end

function fields = local_derive_component_design_fields(eng, path, cfg)
%LOCAL_DERIVE_COMPONENT_DESIGN_FIELDS 从设计点实际热力状态反算 MDL 字段。
%
% 压气机 PRDes 由V2顶部显式给定的2/25/3截面设计总压计算。压气机和
% 涡轮 EffDes 则读取DLL部件函数按变比热气体性质计算后的实际等熵效率，
% 避免常比热近似与C程序热力定义不一致。path仅用于检查DLL实际压比与
% 显式设计压比是否闭合，不作为第二套设计数据源。
fields.AC = [cfg.design.targetPt25Pa / cfg.design.targetPt2Pa, ...
    eng.HPC.y(27)];
fields.CC = [cfg.design.targetPt3Pa / cfg.design.targetPt25Pa, ...
    eng.HPC2.y(27)];
fields.GT1 = eng.HPT.y(20);
fields.GT2 = eng.HPT2.y(20);
fields.PT1 = eng.LPT.y(20);
fields.PT2 = eng.LPT2.y(20);
fields.vector = [fields.AC, fields.CC, fields.GT1, fields.GT2, ...
    fields.PT1, fields.PT2];
fields.names = {'AC.PRDes', 'AC.EffDes', 'CC.PRDes', 'CC.EffDes', ...
    'GT1.EffDes', 'GT2.EffDes', 'PT1.EffDes', 'PT2.EffDes'};

actualPressureRatio = [path.totalPressurePa(2) / path.totalPressurePa(1), ...
    path.totalPressurePa(3) / path.totalPressurePa(2)];
derivedPressureRatio = [fields.AC(1), fields.CC(1)];
fields.pressureRatioClosureRelative = local_relative_difference( ...
    derivedPressureRatio, actualPressureRatio);
fields.pressureRatioClosureMaxRelative = max( ...
    fields.pressureRatioClosureRelative);
assert(all(isfinite(fields.vector)) && all(fields.vector > 0), ...
    '反算的八项部件设计字段出现非法值。');
end

function fields = local_capture_configured_design_fields(eng)
%LOCAL_CAPTURE_CONFIGURED_DESIGN_FIELDS 读取 DLL 实际加载的 MDL 设计字段。
fields.AC = [eng.HPC.compressorStruct.PRDes, ...
    eng.HPC.compressorStruct.EffDes];
fields.CC = [eng.HPC2.compressorStruct.PRDes, ...
    eng.HPC2.compressorStruct.EffDes];
fields.GT1 = eng.HPT.turbineStruct.EffDes;
fields.GT2 = eng.HPT2.turbineStruct.EffDes;
fields.PT1 = eng.LPT.turbineStruct.EffDes;
fields.PT2 = eng.LPT2.turbineStruct.EffDes;
fields.vector = [fields.AC, fields.CC, fields.GT1, fields.GT2, ...
    fields.PT1, fields.PT2];
assert(all(isfinite(fields.vector)) && all(fields.vector > 0), ...
    '拆分 MDL 中的八项部件设计字段出现非法值。');
end

function local_print_compressor_path(path)
fprintf(['  2 截面 DLL实算 W/Tt/Pt       : %.9f kg/s / %.9f K / ', ...
    '%.6f Pa\n'], path.massFlowKgPerS(1), path.totalTemperatureK(1), ...
    path.totalPressurePa(1));
fprintf(['  25截面 W/Tt/Pt              : %.9f kg/s / %.9f K / ', ...
    '%.6f Pa\n'], path.massFlowKgPerS(2), path.totalTemperatureK(2), ...
    path.totalPressurePa(2));
fprintf(['  3 截面 W/Tt/Pt              : %.9f kg/s / %.9f K / ', ...
    '%.6f Pa\n'], path.massFlowKgPerS(3), path.totalTemperatureK(3), ...
    path.totalPressurePa(3));
end

function targets = local_compressor_station_targets(cfg)
targets = [cfg.design.targetTt25K, cfg.design.targetPt25Pa, ...
    cfg.design.targetTt3K, cfg.design.targetPt3Pa];
end

function efficiency = local_capture_turbine_efficiency(eng)
% Turbine_TMATS_body.c 的 y[19] 是最终实际等熵效率；MATLAB 从 1 开始
% 编号，因此读取 y(20)。它已经综合特性图效率、效率缩放和健康修正，
% 不能用 MDL 中的 EffDes 或 s_T_Eff 代替。
efficiency = [eng.HPT.y(20), eng.HPT2.y(20), ...
    eng.LPT.y(20), eng.LPT2.y(20)];
assert(all(isfinite(efficiency)), '四个涡轮的实际效率出现 NaN/Inf。');
end

function output = local_capture_output(eng)
compressor = eng.HPC2;
gtExit = eng.HPT2;
ptExit = eng.LPT2;
output = [compressor.y(1), compressor.y(3), compressor.y(4), ...
    gtExit.y(3), gtExit.y(4), ptExit.y(3), ptExit.y(4), ...
    eng.LPS_Nmech, eng.HPS_Nmech, eng.LPS_Trq];
end

function value = local_base_step_in(cfg, npRpm, ngRpm, wf)
value = zeros(cfg.interface.stepInLength, 1);
value(1:10) = [npRpm; ngRpm; wf; cfg.design.nozzleAreaM2; 0; ...
    cfg.design.loadPowerW; cfg.design.accessoryPowerW; 0; 0; 0];
end

function relative = local_relative_difference(a, b)
relative = abs(a - b) ./ max(abs(b), 1.0e-15);
end

function value = local_format_vector(vector)
items = arrayfun(@(x) sprintf('%.17g', x), vector(:).', ...
    'UniformOutput', false);
value = strjoin(items, '   ');
end

function local_write_summary(path, result)
fid = fopen(path, 'w', 'n', 'UTF-8');
assert(fid >= 0, '无法写入 M1 设计点摘要：%s', path);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
d = result.design;
fprintf(fid, 'M1 六部件拆分模型设计点手工配置工作流摘要\n');
fprintf(fid, '生成时间：%s\n', result.generatedAt);
fprintf(fid, '本次工作流：%s\n\n', result.workflow);
t = result.designTargets;
fprintf(fid, ['独立六部件设计目标：Np=%.12g rpm，Ng=%.12g rpm，', ...
    'Pload=%.12g W\n'], t.NpRpm, t.NgRpm, t.loadPowerW);
fprintf(fid, 'Tt4=%.12g K，P45=%.12g Pa，P5=%.12g Pa\n\n', ...
    t.targetTt4K, t.targetGTExitPressurePa, t.targetPTExitPressurePa);
fprintf(fid, '2截面显式设计值 Tt2=%.12g K，Pt2=%.12g Pa\n', ...
    t.targetTt2K, t.targetPt2Pa);
fprintf(fid, ['压气机截面目标 Tt25=%.12g K，Pt25=%.12g Pa，', ...
    'Tt3=%.12g K，Pt3=%.12g Pa\n\n'], ...
    t.targetTt25K, t.targetPt25Pa, t.targetTt3K, t.targetPt3Pa);

if strcmp(result.workflow, 'design')
    init = d.initialization;
    fprintf(fid, ['初值正向排气恢复：启用=%d，调整次数=%d，', ...
        '喷管Pt/Pback=%.12g -> %.12g\n'], ...
        init.applied, init.attempts, init.nozzlePressureRatio(1), ...
        init.nozzlePressureRatio(end));
    fprintf(fid, '原始初值=[%s]\n', local_format_vector(init.original));
    fprintf(fid, '可行初值=[%s]\n', local_format_vector(init.adjusted));
    fprintf(fid, '最终喷管Pt/Pback=%.12g\n', d.nozzlePressureRatio);
    fprintf(fid, '拆分设计解 x=[%s]\n', local_format_vector(result.solution));
    fprintf(fid, ['变量顺序：[W2, PR_GT1, PR_GT2, PR_PT1, PR_PT2, Wf, ', ...
        'kPR_AC, kEta_AC, kPR_CC, kEta_CC, kEta_GT, kEta_PT]\n']);
    fprintf(fid, ['压气机设计辅助量 [kPR_AC kEta_AC kPR_CC kEta_CC]', ...
        '=[%s]\n'], local_format_vector(d.compressorCorrection));
    fprintf(fid, ['kEtaGT=%.12g，kEtaPT=%.12g；二者仅为设计点效率校准', ...
        '辅助量，已折算进待手工填写的效率缩放系数。\n'], ...
        d.efficiencyCorrection(1), d.efficiencyCorrection(2));
    fprintf(fid, ['全部压气机辅助量已折算进待手工填写的 ', ...
        's_C_PR/s_C_Eff，运行输入保持为零。\n']);
    fprintf(fid, '设计最大残差=%.6e\n', d.maxResidual);
    fprintf(fid, '六部件设计锚点最大残差=%.6e（门限 %.3e）\n', ...
        d.designAnchor.maxResidual, ...
        result.configuration.tolerance.designAnchorResidual);
    fprintf(fid, 'DLL九项共同工作残差=[%s]\n', ...
        local_format_vector(d.dllResidual));
    fprintf(fid, '设计结果 Tt4=%.12g K，P45=%.12g Pa，P5=%.12g Pa\n', ...
        d.Tt4K, d.output(5), d.output(7));
    fprintf(fid, '压气机截面 [Tt25 Pt25 Tt3 Pt3]=[%s]\n', ...
        local_format_vector(d.compressorStation));
    fprintf(fid, ['压气机气路 [W2 Tt2 Pt2 W25 Tt25 Pt25 W3 Tt3 Pt3]', ...
        '=[%s]\n'], local_format_vector(d.compressorPath.vector));
    fprintf(fid, '2截面显式设计值最大相对误差=%.6e\n', ...
        d.station2TargetMaxRelative);
    fprintf(fid, '压气机实际 [PR_AC Eff_AC PR_CC Eff_CC]=[%s]\n', ...
        local_format_vector(d.compressorPerformance));
    fprintf(fid, ['待写入设计字段 [AC.PRDes AC.EffDes CC.PRDes ', ...
        'CC.EffDes GT1.EffDes GT2.EffDes PT1.EffDes PT2.EffDes]', ...
        '=[%s]\n'], local_format_vector(d.componentDesignFields.vector));
    fprintf(fid, '压气机压比定义闭合最大相对差=%.6e\n', ...
        d.componentDesignFields.pressureRatioClosureMaxRelative);
    fprintf(fid, 'GT1/GT2 功率=%.12g / %.12g W，比例=%.9f / %.9f\n', ...
        d.gtPowerW(1), d.gtPowerW(2), d.gtWorkSplit, 1-d.gtWorkSplit);
    fprintf(fid, 'PT1/PT2 功率=%.12g / %.12g W，比例=%.9f / %.9f\n\n', ...
        d.ptPowerW(1), d.ptPowerW(2), d.ptWorkSplit, 1-d.ptWorkSplit);
    fprintf(fid, '设计点实际等熵效率 [GT1 GT2 PT1 PT2]=[%s]\n\n', ...
        local_format_vector(d.turbineEfficiency));

    names = {'AC', 'CC', 'GT1', 'GT2', 'PT1', 'PT2'};
    for i = 1:numel(names)
        values = d.scalars.(names{i});
        fprintf(fid, '%-3s 缩放系数 [Nc Wc PR Eff] = [%s]\n', ...
            names{i}, local_format_vector(values));
    end
    fprintf(fid, '\n程序未修改 MDL；等待人工写入后再次运行验证。\n');
else
    v = result.verification;
    c = v.mdlParameterComparison;
    fprintf(fid, ['offDesignMode=2设计参数与MDL原始文本逐项对比', ...
        '（%d项，门限%.3e）\n'], numel(c.names), c.tolerance);
    fprintf(fid, '%-30s\t设计值\tMDL值\t相对误差\t结果\n', '参数');
    for i = 1:numel(c.names)
        fprintf(fid, '%-30s\t%.17g\t%.17g\t%.6e\t%s\n', ...
            c.names{i}, c.designValue(i), c.mdlValue(i), ...
            c.relativeDifference(i), local_pass_fail(c.passed(i)));
    end
    fprintf(fid, '人工写入参数总体核对=%s\n\n', ...
        local_pass_fail(c.allPassed));
    fprintf(fid, '无MDL字段的设计求解量（不参与写入比较）：\n');
    for i = 1:numel(c.notWrittenNames)
        fprintf(fid, '%-30s\t%.17g\n', ...
            c.notWrittenNames{i}, c.notWrittenDesignValue(i));
    end
    fprintf(fid, '\n');
    fprintf(fid, '运行配置直接回放最大残差=%.6e\n', ...
        v.directReplayMaxResidual);
    fprintf(fid, '设计/运行配置输出最大相对差=%.6e\n', ...
        v.designReplayMaxRelative);
    fprintf(fid, '缩放系数重读最大相对差=%.6e\n', ...
        v.scaleReplayMaxRelative);
    fprintf(fid, 'GT1/GT2 功率比例=%.9f / %.9f\n', ...
        v.gtWorkSplit, 1-v.gtWorkSplit);
    fprintf(fid, 'PT1/PT2 功率比例=%.9f / %.9f\n', ...
        v.ptWorkSplit, 1-v.ptWorkSplit);
    fprintf(fid, '设计点实际等熵效率 [GT1 GT2 PT1 PT2]=[%s]\n', ...
        local_format_vector(v.directReplayTurbineEfficiency));
    fprintf(fid, '压气机截面 [Tt25 Pt25 Tt3 Pt3]=[%s]\n', ...
        local_format_vector(v.directReplayCompressorStation));
    fprintf(fid, ['压气机气路 [W2 Tt2 Pt2 W25 Tt25 Pt25 W3 Tt3 Pt3]', ...
        '=[%s]\n'], ...
        local_format_vector(v.directReplayCompressorPath.vector));
    fprintf(fid, '2截面显式设计值最大相对误差=%.6e\n', ...
        v.directStation2TargetMaxRelative);
    fprintf(fid, '压气机实际 [PR_AC Eff_AC PR_CC Eff_CC]=[%s]\n', ...
        local_format_vector(v.directReplayCompressorPerformance));
    fprintf(fid, 'MDL八项设计字段最大相对差=%.6e\n', ...
        v.configuredDesignFieldMaxRelative);
    fprintf(fid, '直接回放反算设计字段最大相对差=%.6e\n', ...
        v.derivedDesignFieldMaxRelative);
    fprintf(fid, '压气机截面目标最大相对误差=%.6e\n', ...
        v.directStationTargetMaxRelative);
    fprintf(fid, '内部 Newton 配平=%s，最大残差=%.6e\n', ...
        local_pass_fail(v.trimConverged), v.trimMaxResidual);
    fprintf(fid, '配平后压气机截面目标最大相对误差=%.6e\n', ...
        v.trimStationTargetMaxRelative);
    fprintf(fid, '配平后八项设计字段最大相对误差=%.6e\n', ...
        v.trimDesignFieldMaxRelative);
    fprintf(fid, '配平后2截面显式设计值最大相对误差=%.6e\n', ...
        v.trimStation2TargetMaxRelative);
    fprintf(fid, '完整设计复现验收=%s\n', local_pass_fail(result.accepted));
end
end

function local_close_library(alias)
if libisloaded(alias)
    try
        calllib(alias, 'DLL_SHT_Free');
    catch
    end
    try
        unloadlibrary(alias);
    catch
    end
end
end

function local_force_unload(alias)
if libisloaded(alias)
    local_close_library(alias);
end
end

function text = local_pass_fail(value)
if value
    text = 'PASS';
else
    text = 'FAIL';
end
end
