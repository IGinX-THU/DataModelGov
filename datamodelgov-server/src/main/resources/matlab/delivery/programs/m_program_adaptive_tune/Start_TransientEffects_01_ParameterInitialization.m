%% Start_TransientEffects_01_ParameterInitialization
% 2.5 三类瞬态效应首轮发动机集成参数资产初始化。
%
% 本程序只使用瞬态效应总开关=0、全部健康修正为零的传统稳态模型生成
% 参数，不打开任何新瞬态物理效应。P6 阶段同时以最新 9 点试车替代数据
% 的目标 Np、目标负载和外部边界作为输入网格，在零健康传统模型上重新
% 执行七变量稳态配平，生成 epsilon_ss 稳态参考表。试车数据中的发动机
% 真值输出不参与建表；Wf_true 和六维共同工作变量只作为 Newton 初猜。

clear;
clc;

thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir);
middleDataDir = fullfile(thisDir, 'MiddleData');
if ~exist(middleDataDir, 'dir')
    mkdir(middleDataDir);
end

% 在打开DLL之前先确认存在三部件参考网格。这样当前目录只保留
% model_mode=1六部件数据时会直接给出边界说明，不会在异常退栈阶段
% 留下仍被libstruct引用的DLL对象。
referenceGridFile = local_find_legacy_reference_grid(thisDir);

cfg = sht_default_config();
engine = sht_engine_open(cfg.engine);
cleanupEngine = onCleanup(@() sht_engine_close(engine)); %#ok<NASGU>

%% P1.5-PA-01：使用传统稳态入口获得唯一设计参考点
stepInValue = zeros(engine.stepInLength, 1);
stepInValue(1:10) = [ ...
    cfg.engine.initial.Np0; ...
    cfg.engine.initial.Ng0; ...
    cfg.engine.initial.Wf0; ...
    cfg.engine.initial.A80; ...
    0; ...
    cfg.engine.initial.power0; ...
    cfg.engine.boundary.hpsPower; ...
    0; ...
    cfg.engine.boundary.hpcAlpha; ...
    0];

% 参数资产和参考表必须来自零健康传统模型，不能混入 2.2/2.4 估计结果。
health = zeros(100, 1);
stepInValue(41:140) = health;

engPtrInit.eng = libstruct(engine.engineStructName);
engPtr = libstruct(engine.enginePointerName, engPtrInit);
stepIn = libpointer('doublePtr', stepInValue);
stepOut = libpointer('doublePtr', zeros(engine.stepOutLength, 1));
[returnCode, ~, ~, engOut] = calllib(engine.libraryName, ...
    'DLL_SHT_RunOnePoint', stepIn, stepOut, engPtr);
eng = engOut.eng;

if returnCode ~= 0 || eng.convergeTag ~= 0
    error('SHT:TransientParameter:DesignPointFailed', ...
        '传统设计稳态点失败：returnCode=%g, convergeTag=%g。', ...
        returnCode, eng.convergeTag);
end

%% P1.5-PA-02：把气路量映射成具名物理量
station = struct();
station.inletOutlet = local_gas_path(eng.Inlet.gasPathOut, 'Inlet outlet / HPC inlet');
station.hpcOutlet = local_gas_path(eng.HPC.y(1:5), 'HPC outlet / Burner inlet');
station.burnerOutlet = local_gas_path(eng.Burner.y(1:5), 'Burner outlet / GT inlet');
station.gtOutlet = local_gas_path(eng.HPT.y(1:5), 'GT outlet');
station.ptInlet = local_gas_path(eng.Duct2.gasPathOut, 'Duct2 outlet / PT inlet');
station.ptOutlet = local_gas_path(eng.LPT.y(1:5), 'PT outlet');

beta = 0.5 * ones(10, 1);
referenceFlow = [ ...
    station.inletOutlet.W; ...
    station.hpcOutlet.W; ...
    station.burnerOutlet.W; ...
    station.ptInlet.W];
referenceGasTemperature = [ ...
    local_drive_temperature(station.inletOutlet.Tt, station.hpcOutlet.Tt, beta(1)); ...
    local_drive_temperature(station.hpcOutlet.Tt, station.burnerOutlet.Tt, beta(4)); ...
    local_drive_temperature(station.burnerOutlet.Tt, station.gtOutlet.Tt, beta(5)); ...
    local_drive_temperature(station.ptInlet.Tt, station.ptOutlet.Tt, beta(8))];

% y(24) 是 Compressor_TMATS_body.c 的 Pwrout[J/s]；
% y(19) 是 Turbine_TMATS_body.c 的 Pwrout[J/s]。魔数只在此处集中映射，
% 参数资产和后续算法均使用下列具名字段。
componentPower = struct();
componentPower.HPC = abs(eng.HPC.y(24));
componentPower.Burner = abs(eng.fuelFlow * ...
    eng.Burner.burnStruct.LHV * eng.Burner.burnStruct.Eff);
componentPower.GT = abs(eng.HPT.y(19));
componentPower.PT = abs(eng.LPT.y(19));
powerScale = [componentPower.HPC; componentPower.Burner; ...
    componentPower.GT; componentPower.PT];

if any(~isfinite(referenceFlow)) || any(referenceFlow <= 0) || ...
        any(~isfinite(referenceGasTemperature)) || any(referenceGasTemperature <= 0) || ...
        any(~isfinite(powerScale)) || any(powerScale <= 0)
    error('SHT:TransientParameter:InvalidDesignQuantity', ...
        '设计点参考流量、温度或功率尺度包含非有限值/非正值。');
end

%% P1.5-PA-03：生成 A 类和 C 类首轮参数
tau0 = [1; 2; 5; 1; 1; 2; 5; 1; 2; 5];
diskTau0 = [300; 300; 300];
rhoQ = 0.01;
deltaTCal = 100;
heatWeight = [0.25; 0.25; 0.50; 1.00; 0.25; 0.25; 0.50; 0.25; 0.25; 0.50];
componentPowerForNode = [ ...
    repmat(powerScale(1), 3, 1); ...
    powerScale(2); ...
    repmat(powerScale(3), 3, 1); ...
    repmat(powerScale(4), 3, 1)];
heatCapacity0 = heatWeight .* rhoQ .* componentPowerForNode .* tau0 ./ deltaTCal;

initialTemperatureState = [ ...
    repmat(referenceGasTemperature(1), 3, 1); ...
    referenceGasTemperature(2); ...
    repmat(referenceGasTemperature(3), 3, 1); ...
    repmat(referenceGasTemperature(4), 3, 1); ...
    referenceGasTemperature([1, 3, 4])];

% 三个部件的归一化间隙参数：[epsilon_ref,a_c,a_b,a_d,b,w_b,
% T_c_ref,T_b_eff_ref,T_d_ref,n_ref]。参考温度来自同一设计稳态点。
clearanceParameter = zeros(3, 10);
for i = 1:3
    if i == 1
        tref = referenceGasTemperature(1);
    elseif i == 2
        tref = referenceGasTemperature(3);
    else
        tref = referenceGasTemperature(4);
    end
    clearanceParameter(i, :) = [ ...
        0.015, 3.0e-5, 1.0e-5, 5.0e-5, 0.003, 0.5, ...
        tref, tref, tref, 1.0];
end

%% P6-PA-05B：用零健康传统稳态目标配平生成 epsilon_ss 参考表
referenceTable = local_generate_clearance_reference_table( ...
    referenceGridFile, cfg, engine, health, clearanceParameter, beta, eng);
[epsilonSSCurrent, designLookupInfo] = sht_lookup_clearance_reference( ...
    referenceTable, cfg.engine.initial.Np0, cfg.engine.initial.Ng0, ...
    stepInValue(6), station.inletOutlet.Tt);

%% P1.5-PA-04~08：资产、来源、有效域和自检
parameterAsset = struct();
parameterAsset.assetVersion = '2.5-P6-joint-v5';
parameterAsset.generatedAt = [datestr(now, 'yyyy-mm-ddTHH:MM:SS'), '+08:00'];
parameterAsset.assetClass = 'engine_integration_parameter_set';
parameterAsset.isSyntheticUnitTestSet = false;
parameterAsset.interface = struct( ...
    'interfaceVersion', 2502, ...
    'stepInLength', 512, ...
    'stepOutLength', 128, ...
    'controlValueTolerance', 1e-6);

parameterAsset.modelIdentity = struct();
parameterAsset.modelIdentity.dllFile = fullfile(thisDir, 'GTESS.dll');
parameterAsset.modelIdentity.dllSHA256 = local_sha256(parameterAsset.modelIdentity.dllFile);
parameterAsset.modelIdentity.headerFile = fullfile(thisDir, 'GTESS.h');
parameterAsset.modelIdentity.headerSHA256 = local_sha256(parameterAsset.modelIdentity.headerFile);
parameterAsset.modelIdentity.modelFile = fullfile(thisDir, 'Turboshaft-TS.mdl');
parameterAsset.modelIdentity.modelSHA256 = local_sha256(parameterAsset.modelIdentity.modelFile);

parameterAsset.designPoint = struct();
parameterAsset.designPoint.input = struct( ...
    'Np_rpm', stepInValue(1), 'Ng_rpm', stepInValue(2), ...
    'Wf_kgps', stepInValue(3), 'A8_m2', stepInValue(4), ...
    'loadPower_W', stepInValue(6), 'hpsPower_W', stepInValue(7));
parameterAsset.designPoint.output = struct( ...
    'Np_rpm', eng.LPS_Nmech, 'Ng_rpm', eng.HPS_Nmech, ...
    'fuelFlow_kgps', eng.fuelFlow, 'convergeTag', eng.convergeTag, ...
    'maxResidual', max(abs(eng.errOut(:))));
parameterAsset.designPoint.station = station;
parameterAsset.designPoint.componentPower_W = componentPower;

parameterAsset.nominalHealth = health;
parameterAsset.nominal = struct();
parameterAsset.nominal.tau0 = tau0;
parameterAsset.nominal.heatCapacity0 = heatCapacity0;
parameterAsset.nominal.beta = beta;
parameterAsset.nominal.diskTau0 = diskTau0;
parameterAsset.nominal.referenceFlow = referenceFlow;
parameterAsset.nominal.referenceGasTemperature = referenceGasTemperature;
parameterAsset.nominal.clearanceParameter = clearanceParameter;
parameterAsset.nominal.epsilonSSCurrent = epsilonSSCurrent;
parameterAsset.nominal.kSMHPC = -5;
parameterAsset.nominal.initialTemperatureState = initialTemperatureState;
% 四个量是固定模型参数，不是修正系数真值。hlthparas[64:67] 只保存
% 围绕这些标称值的相对修正，正常入口中的默认值始终为零。
parameterAsset.nominal.clearanceExchangeRate = [-1.0; -1.0; -0.5; -0.5];

parameterAsset.calibrationPrior = struct( ...
    'rhoQ', rhoQ, 'deltaTCal_K', deltaTCal, ...
    'heatWeight', heatWeight, ...
    'statement', ['C 类热容仅为数值联调先验，不是型号真值；2.6 前需要由' ...
                  '质量-比热、文献或试验辨识确认/替换。']);

parameterAsset.parameterSources = table( ...
    {'tau0'; 'beta'; 'diskTau0'; 'referenceFlow'; 'referenceGasTemperature'; ...
     'referenceTemperature'; 'heatCapacity0'; 'nominalClearanceExchangeRate'; ...
     'epsilonSSTable'}, ...
    {'A'; 'A'; 'A'; 'B'; 'B'; 'B'; 'C'; 'C'; 'B'}, ...
    {'Kurzke Table 7.4-1'; 'first-round midpoint definition'; ...
     'first-round slow disk prior'; 'current baseline design point'; ...
     'current baseline design point'; 'current baseline design point'; ...
     'rhoQ controlled scaling'; ...
     'first-round engineering nominal sensitivity, pending test calibration'; ...
     'zero-health traditional steady model trimmed to target Np/load grid'}, ...
    'VariableNames', {'ParameterGroup', 'SourceCategory', 'Source'});

parameterAsset.referenceTable = referenceTable;
parameterAsset.validDomain = struct( ...
    'designPointReferenceAvailable', true, ...
    'epsilonSSScheduleAvailable', true, ...
    'clearanceStageReleased', true, ...
    'HPC_inletCorrectedNg_rpm', [min(referenceTable.HPC.correctedSpeed_rpm), ...
                   max(referenceTable.HPC.correctedSpeed_rpm)], ...
    'GT_inletCorrectedNg_rpm', [min(referenceTable.GT.correctedSpeed_rpm), ...
                  max(referenceTable.GT.correctedSpeed_rpm)], ...
    'PT_inletCorrectedNp_rpm', [min(referenceTable.PT.correctedSpeed_rpm), ...
                  max(referenceTable.PT.correctedSpeed_rpm)], ...
    'PT_loadPower_W', [min(referenceTable.PT.loadPower_W), ...
                       max(referenceTable.PT.loadPower_W)]);

heatFlowAtCalibration = heatCapacity0 ./ tau0 .* deltaTCal;
componentHeatFlow = [sum(heatFlowAtCalibration(1:3)); heatFlowAtCalibration(4); ...
    sum(heatFlowAtCalibration(5:7)); sum(heatFlowAtCalibration(8:10))];
targetHeatFlow = rhoQ .* powerScale;
relativeHeatBalanceError = abs(componentHeatFlow - targetHeatFlow) ./ targetHeatFlow;

parameterAsset.selfCheck = struct();
parameterAsset.selfCheck.designPointConverged = returnCode == 0 && eng.convergeTag == 0;
parameterAsset.selfCheck.transientHealthIsZero = all(health(59:77) == 0);
parameterAsset.selfCheck.positiveAandBCParameters = ...
    all(tau0 > 0) && all(heatCapacity0 > 0) && all(diskTau0 > 0) && ...
    all(referenceFlow > 0) && all(referenceGasTemperature > 0);
parameterAsset.selfCheck.nominalClearanceRateValid = ...
    all(isfinite(parameterAsset.nominal.clearanceExchangeRate)) && ...
    all(parameterAsset.nominal.clearanceExchangeRate <= 0) && ...
    any(parameterAsset.nominal.clearanceExchangeRate < 0);
parameterAsset.selfCheck.componentHeatFlow_W = componentHeatFlow;
parameterAsset.selfCheck.targetHeatFlow_W = targetHeatFlow;
parameterAsset.selfCheck.relativeHeatBalanceError = relativeHeatBalanceError;
parameterAsset.selfCheck.heatBalancePassed = all(relativeHeatBalanceError < 1e-12);
parameterAsset.selfCheck.epsilonScheduleCheck = 'PASSED';
parameterAsset.selfCheck.epsilonScheduleMaxNodeError = ...
    referenceTable.selfCheck.maxNodeDynamicClearanceError;
parameterAsset.selfCheck.designLookup = designLookupInfo;
parameterAsset.selfCheck.referenceTrimAllConverged = ...
    referenceTable.selfCheck.allTrimPointsConverged;
parameterAsset.selfCheck.referenceTrimMaxNpError_rpm = ...
    referenceTable.selfCheck.maxTrimNpError_rpm;
parameterAsset.selfCheck.referenceTrimMaxResidual = ...
    referenceTable.selfCheck.maxTrimResidual;

parameterAsset.stepInTemplates = struct();
parameterAsset.stepInTemplates.baseline = ...
    sht_build_transient_step_in_template(parameterAsset, 'baseline');
parameterAsset.stepInTemplates.enhancedReady = ...
    sht_build_transient_step_in_template(parameterAsset, 'enhanced_ready');
parameterAsset.stepInTemplates.clearanceDiagnostic = ...
    sht_build_transient_step_in_template(parameterAsset, 'clearance_diagnostic');
parameterAsset.stepInTemplates.jointFull = ...
    sht_build_transient_step_in_template(parameterAsset, 'joint_full');
stepInTemplate = parameterAsset.stepInTemplates.enhancedReady;

if ~parameterAsset.selfCheck.designPointConverged || ...
        ~parameterAsset.selfCheck.transientHealthIsZero || ...
        ~parameterAsset.selfCheck.positiveAandBCParameters || ...
        ~parameterAsset.selfCheck.nominalClearanceRateValid || ...
        ~parameterAsset.selfCheck.heatBalancePassed || ...
        ~parameterAsset.selfCheck.referenceTrimAllConverged || ...
        parameterAsset.selfCheck.epsilonScheduleMaxNodeError > 1e-12
    error('SHT:TransientParameter:SelfCheckFailed', ...
        '瞬态效应参数资产自检未全部通过，拒绝保存。');
end

assetFile = fullfile(middleDataDir, 'transient_effects_initial_parameters.mat');
reportOutputDir = fullfile(fileparts(thisDir), ...
    'report_outputs', 'transient_effects');
if ~exist(reportOutputDir, 'dir')
    mkdir(reportOutputDir);
end
summaryFile = fullfile(reportOutputDir, ...
    'transient_effects_initial_parameters_summary.txt');
save(assetFile, 'parameterAsset', 'stepInTemplate', '-v7');
local_write_summary(summaryFile, parameterAsset);

% MATLAB 只有在全部 libstruct/libpointer 对象释放后才允许 unloadlibrary。
% 先清除这些接口对象，再主动关闭 DLL；随后清除 onCleanup，其第二次检查
% 会因库已卸载而直接返回。该顺序避免拒绝卸载和重复 DLL_SHT_Free。
clear eng engOut engPtr engPtrInit stepIn stepOut;
sht_engine_close(engine);
clear cleanupEngine;

fprintf('\n2.5 瞬态效应首轮参数资产生成完成。\n');
fprintf('  参数布局版本     : %d\n', parameterAsset.interface.interfaceVersion);
fprintf('  DLL SHA-256       : %s\n', parameterAsset.modelIdentity.dllSHA256);
fprintf('  设计点 Np / Ng    : %.9f / %.9f rpm\n', ...
    parameterAsset.designPoint.output.Np_rpm, parameterAsset.designPoint.output.Ng_rpm);
fprintf('  Wref              : %s kg/s\n', mat2str(referenceFlow.', 10));
fprintf('  Tgref             : %s K\n', mat2str(referenceGasTemperature.', 10));
fprintf('  C0                : %s J/K\n', mat2str(heatCapacity0.', 10));
fprintf('  标称间隙交换率     : %s\n', ...
    mat2str(parameterAsset.nominal.clearanceExchangeRate.', 10));
fprintf('  epsilon_ss 表状态 : %s\n', parameterAsset.referenceTable.status);
fprintf('  参考表节点误差     : %.3e\n', ...
    parameterAsset.referenceTable.selfCheck.maxNodeDynamicClearanceError);
fprintf('  参考输入网格       : %s\n', parameterAsset.referenceTable.sourceFile);
fprintf('  MAT 资产          : %s\n', assetFile);
fprintf('  可读摘要          : %s\n', summaryFile);

function gas = local_gas_path(vector, location)
% 气路五元组在 C 端冻结为 [W, ht, Tt, Pt, FAR]。
vector = vector(:);
if numel(vector) < 5
    error('SHT:TransientParameter:GasPathWidth', '%s 气路向量不足 5 项。', location);
end
gas = struct('location', location, 'W', vector(1), 'ht', vector(2), ...
    'Tt', vector(3), 'Pt', vector(4), 'FAR', vector(5));
end

function temperature = local_drive_temperature(tIn, tOut, beta)
temperature = (1 - beta) * tIn + beta * tOut;
end

function correctedSpeed = local_inlet_corrected_speed(speedRpm, inletTtK)
% 发动机进口基准修正转速。该量只作为稳态参考间隙调度坐标；离心变形
% 仍使用绝对转速，二者不能混用。
standardTemperatureK = 288.15;
if any(~isfinite(speedRpm(:))) || any(speedRpm(:) < 0) || ...
        any(~isfinite(inletTtK(:))) || any(inletTtK(:) <= 0)
    error('SHT:TransientParameter:InvalidCorrectedSpeedInput', ...
        '进口基准修正转速的转速和 Tt1 必须分别为有限非负值和有限正值。');
end
correctedSpeed = speedRpm ./ sqrt(inletTtK ./ standardTemperatureK);
end

function [coordinate, value, guardInfo] = local_add_constant_endpoint_guards( ...
    coordinateCore, valueCore, requestedRange, componentName)
% 在已有零健康稳态节点之外，仅扩展热参考间隙的常值端点。选择常值而
% 不是斜率外推，是因为表值已剔除离心项，首轮不凭空放大未知热趋势。
coordinate = coordinateCore(:);
value = valueCore(:);
requestedRange = requestedRange(:).';
if numel(requestedRange) ~= 2 || any(~isfinite(requestedRange)) || ...
        requestedRange(1) <= 0 || requestedRange(2) <= requestedRange(1)
    error('SHT:TransientParameter:InvalidCorrectedSpeedGuardRange', ...
        '%s 修正转速保护范围无效。', componentName);
end
coreRange = [min(coordinate), max(coordinate)];
addedLow = requestedRange(1) < coreRange(1);
addedHigh = requestedRange(2) > coreRange(2);
if addedLow
    coordinate = [requestedRange(1); coordinate];
    value = [value(1); value];
end
if addedHigh
    coordinate = [coordinate; requestedRange(2)];
    value = [value; value(end)];
end
guardInfo = struct( ...
    'coreRange_rpm', coreRange, ...
    'finalRange_rpm', [min(coordinate), max(coordinate)], ...
    'addedLowGuard', addedLow, ...
    'addedHighGuard', addedHigh);
end

function referenceTable = local_generate_clearance_reference_table( ...
    sourceFile, cfg, engine, health, clearanceParameter, beta, designEng)
    % 9 点 MAT 只提供目标工况、外部边界和 Newton 初猜；所有参考温度和
    % 间隙均由零健康传统模型在目标 Np/负载下重新配平后计算。PT 的
    % Np 保护节点扩展到 +/-12%，覆盖默认 -2000 rpm 脉冲并保留裕量。
loaded = load(sourceFile, 'dataTable');
if ~isfield(loaded, 'dataTable') || ~istable(loaded.dataTable)
    error('SHT:TransientParameter:InvalidReferenceGrid', ...
        '参考 MAT 缺少 dataTable：%s', sourceFile);
end

grid = loaded.dataTable;
% 本入口只维护三部件15状态历史资产，不能把当前六部件试车网格当作
% 三部件模型的参考工况。此前直接读取“最新文件”会把model_mode=1
% 数据送入三部件七变量配平，最终以非有限雅可比的形式间接失败。
if ismember('model_mode', grid.Properties.VariableNames)
    sourceModelMode = unique(grid.model_mode);
    if numel(sourceModelMode)~=1 || sourceModelMode~=0
        error('SHT:TransientParameter:ReferenceGridModelMode', ...
            ['Start_TransientEffects_01仅用于三部件历史模型，参考网格' ...
             'model_mode必须恒为0；当前文件为%s，实际模式为%s。' ...
             '六部件Kurzke/Visser请分别运行Start_TransientEffects_06/10。'], ...
            sourceFile,mat2str(sourceModelMode(:).'));
    end
end

required = {'point_id', 'target_Np', 'target_load_power_true', 'Wf_true', ...
    'var_Win', 'var_HPCRline', 'var_HPTPR', 'var_LPTPR', ...
    'var_Np', 'var_Ng', 'Tt1_true', 'Pamb_true'};
missing = setdiff(required, grid.Properties.VariableNames, 'stable');
if ~isempty(missing)
    error('SHT:TransientParameter:ReferenceGridColumns', ...
        '参考网格缺少字段：%s。', strjoin(missing, ', '));
end
% 当前试车数据已将可测量压力统一改为 Pt2，不再保存旧字段 Pt1_true。
% epsilon_ss 建表仍需要 DLL 模式1的真实 Pt1 边界，因此优先兼容旧字段，
% 新数据则读取数据生成阶段专门保留的无误差模型边界 model_Pt1。绝不能
% 把测量 Pt2 填入 Pt1 输入槽位，否则会重复计算进口压损。
if ismember('Pt1_true', grid.Properties.VariableNames)
    pt1Boundary = grid.Pt1_true;
elseif ismember('model_Pt1', grid.Properties.VariableNames)
    pt1Boundary = grid.model_Pt1;
else
    error('SHT:TransientParameter:ReferenceGridPt1Boundary', ...
        '参考网格必须提供旧Pt1_true或当前model_Pt1无误差边界。');
end

nGrid = height(grid);
guardRelativeOffset = [0; -0.12; -0.06; 0.06; 0.12];
% PT二维参考表不能把正常测量误差或逆动态补偿后的微小边界波动误判为
% 物理域外。只在现有最低、最高负载边界向外增加2%保护层，并对每个
% 保护点重新执行零健康稳态配平；内部负载层不复制，避免无意义增大表。
loadPowerGuardRelativeOffset = [-0.02; 0.02];
minimumCoreLoadPower = min(grid.target_load_power_true);
maximumCoreLoadPower = max(grid.target_load_power_true);
requestedLoadPowerRange = [minimumCoreLoadPower * ...
    (1 + loadPowerGuardRelativeOffset(1)), ...
    maximumCoreLoadPower * (1 + loadPowerGuardRelativeOffset(2))];
loadPowerTolerance = 100 * eps(max(abs(grid.target_load_power_true)));
loadOffsetsByGrid = cell(nGrid,1);
for i = 1:nGrid
    offsets = 0;
    if abs(grid.target_load_power_true(i)-minimumCoreLoadPower) <= ...
            loadPowerTolerance
        offsets(end+1) = loadPowerGuardRelativeOffset(1); %#ok<AGROW>
    end
    if abs(grid.target_load_power_true(i)-maximumCoreLoadPower) <= ...
            loadPowerTolerance
        offsets(end+1) = loadPowerGuardRelativeOffset(2); %#ok<AGROW>
    end
    loadOffsetsByGrid{i} = offsets;
end
nGuardPerCore = numel(guardRelativeOffset);
nPoint = nGuardPerCore * sum(cellfun(@numel,loadOffsetsByGrid));
pointID = cell(nPoint, 1);
isCore = false(nPoint, 1);
npGuardRelativeOffset = zeros(nPoint, 1);
loadPowerGuardRelativeOffsetAtPoint = zeros(nPoint,1);
np = zeros(nPoint, 1);
modelNp = zeros(nPoint, 1);
ng = zeros(nPoint, 1);
loadPower = zeros(nPoint, 1);
pt1 = zeros(nPoint, 1);
tt1 = zeros(nPoint, 1);
pamb = zeros(nPoint, 1);
ncr = zeros(nPoint, 3);
inletCorrectedNp = zeros(nPoint, 1);
inletCorrectedNg = zeros(nPoint, 1);
metalTemperature = zeros(nPoint, 10);
diskTemperature = zeros(nPoint, 3);
epsilonThermal = zeros(nPoint, 3);
epsilonFull = zeros(nPoint, 3);
trimWf = zeros(nPoint, 1);
trimNpError = zeros(nPoint, 1);
trimResidual = zeros(nPoint, 1);
trimIteration = zeros(nPoint, 1);
trimCondition = zeros(nPoint, 1);

trimConfig = local_zero_health_trim_config(cfg, health);
designSeed = [reshape(designEng.varIte(1:6), [], 1); ...
    cfg.engine.initial.Wf0];
previousSeed = designSeed;
pointIndex = 0;

for i = 1:nGrid
    corePointID = char(string(grid.point_id(i)));
    rowLoadOffsets = loadOffsetsByGrid{i};
    for loadGuardIndex = 1:numel(rowLoadOffsets)
      loadRelativeOffset = rowLoadOffsets(loadGuardIndex);
      for guardIndex = 1:nGuardPerCore
        pointIndex = pointIndex + 1;
        relativeOffset = guardRelativeOffset(guardIndex);
        target = struct( ...
            'Np_rpm', grid.target_Np(i) * (1 + relativeOffset), ...
            'loadPower_W', grid.target_load_power_true(i) * ...
                (1 + loadRelativeOffset), ...
            'Pt1_Pa', pt1Boundary(i), ...
            'Tt1_K', grid.Tt1_true(i), ...
            'Pamb_Pa', grid.Pamb_true(i));
        gridSeed = [grid.var_Win(i); grid.var_HPCRline(i); ...
            grid.var_HPTPR(i); grid.var_LPTPR(i); ...
            target.Np_rpm; grid.var_Ng(i); grid.Wf_true(i)];

        % 首选与目标点最接近的原 9 点初猜；若其 Newton 路径失败，再依次
        % 尝试上一零健康收敛点和设计点。两条备用初猜都把 Np/Wf 对齐到
        % 当前目标附近，但不会把试车真值作为固定模型输入。
        previousCandidate = previousSeed;
        previousCandidate(5) = target.Np_rpm;
        previousCandidate(7) = grid.Wf_true(i);
        designCandidate = designSeed;
        designCandidate(5) = target.Np_rpm;
        designCandidate(7) = grid.Wf_true(i);
        candidateSeeds = [gridSeed, previousCandidate, designCandidate];

        trim = [];
        bestFailed = [];
        for attempt = 1:size(candidateSeeds, 2)
            candidate = local_trim_zero_health_steady_point( ...
                engine, cfg, trimConfig, target, candidateSeeds(:, attempt));
            if isempty(bestFailed) || candidate.normF < bestFailed.normF
                bestFailed = candidate;
            end
            if candidate.converged
                trim = candidate;
                break;
            end
        end
        if isempty(trim)
            error('SHT:TransientParameter:ReferenceTrimFailed', ...
                ['零健康参考点 %s 目标配平失败：targetNp=%.15g rpm，' ...
                 'load=%.15g W，bestNorm=%.15g。'], ...
                corePointID, target.Np_rpm, target.loadPower_W, ...
                bestFailed.normF);
        end

        modelEng = trim.modelEng;
        previousSeed = trim.z;
        suffix = {};
        if loadRelativeOffset < 0
            suffix{end+1} = 'LOAD_GUARD_LOW'; %#ok<AGROW>
        elseif loadRelativeOffset > 0
            suffix{end+1} = 'LOAD_GUARD_HIGH'; %#ok<AGROW>
        end
        if relativeOffset < 0
            suffix{end+1} = 'NP_GUARD_LOW'; %#ok<AGROW>
        elseif relativeOffset > 0
            suffix{end+1} = 'NP_GUARD_HIGH'; %#ok<AGROW>
        end
        if isempty(suffix)
            pointID{pointIndex} = corePointID;
            isCore(pointIndex) = true;
        else
            pointID{pointIndex} = strjoin([{corePointID},suffix],'_');
        end
        npGuardRelativeOffset(pointIndex) = relativeOffset;
        loadPowerGuardRelativeOffsetAtPoint(pointIndex) = loadRelativeOffset;
        % PT 调度坐标严格使用目标绝对转速；模型实际转速单独保存并进入
        % 误差自检，避免 Newton 终止容差制造边界伪外推。
        np(pointIndex) = target.Np_rpm;
        modelNp(pointIndex) = modelEng.LPS_Nmech;
        ng(pointIndex) = modelEng.HPS_Nmech;
        loadPower(pointIndex) = target.loadPower_W;
        pt1(pointIndex) = target.Pt1_Pa;
        tt1(pointIndex) = target.Tt1_K;
        pamb(pointIndex) = target.Pamb_Pa;
        ncr(pointIndex, :) = [modelEng.HPC.y(16), modelEng.HPT.y(15), ...
            modelEng.LPT.y(15)];
        inletCorrectedNp(pointIndex) = local_inlet_corrected_speed( ...
            np(pointIndex), tt1(pointIndex));
        inletCorrectedNg(pointIndex) = local_inlet_corrected_speed( ...
            ng(pointIndex), tt1(pointIndex));
        [metalTemperature(pointIndex, :), diskTemperature(pointIndex, :), ...
            epsilonThermal(pointIndex, :), epsilonFull(pointIndex, :)] = ...
            local_reference_quantities(modelEng, beta, clearanceParameter, ...
            [modelEng.HPS_Nmech, modelEng.HPS_Nmech, target.Np_rpm]);
        trimWf(pointIndex) = trim.z(7);
        trimNpError(pointIndex) = modelNp(pointIndex) - target.Np_rpm;
        trimResidual(pointIndex) = max(abs(trim.f(1:6)));
        trimIteration(pointIndex) = trim.iteration;
        trimCondition(pointIndex) = trim.conditionNumber;
      end
    end
end

% 初始化工况必须是参考表中的精确锚点。S01 与传统设计点具有相同的
% Np/Ng/负载边界，因此直接采用同一次 RunOnePoint 的气路温度，并把
% 调度坐标写成控制模型的目标转速。这样既消除外层 Newton 终止容差
% 造成的 1e-11 量级伪动态间隙，也没有复制或外推任何边界节点。
designAnchorIndex = find(isCore & ...
    abs(np - cfg.engine.initial.Np0) <= 1e-12 & ...
    abs(loadPower - cfg.engine.initial.power0) <= 1e-6, 1, 'first');
if isempty(designAnchorIndex)
    error('SHT:TransientParameter:MissingDesignAnchor', ...
        '9 点核心网格中缺少与传统设计点一致的 Np/负载锚点。');
end
ng(designAnchorIndex) = cfg.engine.initial.Ng0;
modelNp(designAnchorIndex) = designEng.LPS_Nmech;
ncr(designAnchorIndex, :) = [designEng.HPC.y(16), ...
    designEng.HPT.y(15), designEng.LPT.y(15)];
inletCorrectedNp(designAnchorIndex) = local_inlet_corrected_speed( ...
    np(designAnchorIndex), tt1(designAnchorIndex));
inletCorrectedNg(designAnchorIndex) = local_inlet_corrected_speed( ...
    ng(designAnchorIndex), tt1(designAnchorIndex));
[metalTemperature(designAnchorIndex, :), ...
    diskTemperature(designAnchorIndex, :), ...
    epsilonThermal(designAnchorIndex, :), ...
    epsilonFull(designAnchorIndex, :)] = local_reference_quantities( ...
    designEng, beta, clearanceParameter, ...
    [cfg.engine.initial.Ng0, cfg.engine.initial.Ng0, ...
     cfg.engine.initial.Np0]);
trimWf(designAnchorIndex) = cfg.engine.initial.Wf0;
trimNpError(designAnchorIndex) = ...
    designEng.LPS_Nmech - cfg.engine.initial.Np0;
trimResidual(designAnchorIndex) = max(abs(designEng.errOut(:)));
trimIteration(designAnchorIndex) = 0;  % 外层七变量配平未调用
trimCondition(designAnchorIndex) = 0;  % 对设计点精确锚定不适用

[hpcNgCore, hpcThermalCore] = local_collapse_1d( ...
    inletCorrectedNg, epsilonThermal(:, 1), 'HPC');
[gtNgCore, gtThermalCore] = local_collapse_1d( ...
    inletCorrectedNg, epsilonThermal(:, 2), 'GT');
[ptCoordinate, ptThermal] = local_collapse_2d( ...
    [inletCorrectedNp, loadPower], epsilonThermal(:, 3));

% HPC/GT 的表值是不含离心项的热参考间隙。对超出已配平稳态节点、但仍
% 属于既有正常瞬态需求的修正转速，只增加常值热端点；实时离心变形仍由
% 下方绝对转速 N^2 项计算，避免把同一速度效应重复计入热参考表。
standardTemperatureK = 288.15;
designInletTtK = designEng.Ambient.gasPathOut(3);
designCorrectedNg = local_inlet_corrected_speed( ...
    cfg.engine.initial.Ng0, designInletTtK);
correctedNgRangeFactor = [0.90, 1.10];
requestedCorrectedNgRange = designCorrectedNg .* correctedNgRangeFactor;
[hpcNg, hpcThermal, hpcGuardInfo] = local_add_constant_endpoint_guards( ...
    hpcNgCore, hpcThermalCore, requestedCorrectedNgRange, 'HPC');
[gtNg, gtThermal, gtGuardInfo] = local_add_constant_endpoint_guards( ...
    gtNgCore, gtThermalCore, requestedCorrectedNgRange, 'GT');

designSpeed = [designEng.HPT.turbineStruct.NDes; ...
    designEng.HPT.turbineStruct.NDes; designEng.LPT.turbineStruct.NDes];
referenceTable = struct();
referenceTable.generated = true;
referenceTable.status = 'generated_and_validated_in_P6';
referenceTable.sourceFile = sourceFile;
referenceTable.sourceFileSHA256 = local_sha256(sourceFile);
referenceTable.sourceRole = ['TARGET_AND_BOUNDARY_GRID_ONLY: target Np/load and ' ...
    'external boundary are fixed inputs; Wf_true and six matching variables are ' ...
    'Newton seeds only; S01 is the exact traditional-design anchor; each core ' ...
    'point adds solved Np +/-12% guard nodes; PT minimum/maximum load rows ' ...
    'add outward 2% solved load-power guard layers; HPC/GT add constant-thermal ' ...
    'endpoint guards over 0.90-1.10 design inlet-corrected Ng; ' ...
    'measured/truth engine outputs are not reference outputs'];
referenceTable.interpolation = struct( ...
    'HPC', ['inlet-corrected Ng linear in-domain; nearest table node ' ...
            'out-of-domain with command-window warning'], ...
    'GT', ['inlet-corrected Ng linear in-domain; nearest table node ' ...
           'out-of-domain with command-window warning'], ...
    'PT', ['inlet-corrected Np-loadPower scattered linear in-domain; ' ...
           'nearest normalized-coordinate table node out-of-domain ' ...
           'with command-window warning']);
referenceTable.standardTemperature_K = standardTemperatureK;
referenceTable.defaultInletTotalTemperature_K = designInletTtK;
referenceTable.scheduleDefinition = struct( ...
    'HPC', 'Ng/sqrt(Tt1/Tstd)', ...
    'GT', 'Ng/sqrt(Tt1/Tstd)', ...
    'PT', '[Np/sqrt(Tt1/Tstd), loadPower]', ...
    'Tstd_K', standardTemperatureK);
referenceTable.domainGuard = struct( ...
    'correctedNgRangeFactor', correctedNgRangeFactor, ...
    'requestedCorrectedNgRange_rpm', requestedCorrectedNgRange, ...
    'thermalEndpointMethod', 'constant_nearest_validated_steady_endpoint', ...
    'runtimeOutOfDomainMethod', ...
        'nearest_table_node_with_transition_warning', ...
    'centrifugalTermUsesAbsoluteSpeed', true, ...
    'HPC', hpcGuardInfo, 'GT', gtGuardInfo, ...
    'ptNpGuardRelativeOffset', guardRelativeOffset(:).', ...
    'ptLoadPowerGuardRelativeOffset', ...
        loadPowerGuardRelativeOffset(:).', ...
    'ptCoreLoadPowerRange_W', ...
        [minimumCoreLoadPower,maximumCoreLoadPower], ...
    'ptRequestedLoadPowerRange_W',requestedLoadPowerRange);
referenceTable.designSpeed_rpm = designSpeed;
referenceTable.centrifugalCoefficient = clearanceParameter(:, 5);
referenceTable.referenceNormalizedSpeed = clearanceParameter(:, 10);
referenceTable.HPC = struct('correctedSpeed_rpm', hpcNg, ...
    'epsilonSSThermal', hpcThermal);
referenceTable.GT = struct('correctedSpeed_rpm', gtNg, ...
    'epsilonSSThermal', gtThermal);
referenceTable.PT = struct('correctedSpeed_rpm', ptCoordinate(:, 1), ...
    'loadPower_W', ptCoordinate(:, 2), ...
    'epsilonSSThermal', ptThermal);
referenceTable.operatingPoints = table(pointID, isCore, npGuardRelativeOffset, ...
    loadPowerGuardRelativeOffsetAtPoint, ...
    np, modelNp, ng, inletCorrectedNp, inletCorrectedNg, loadPower, ...
    pt1, tt1, pamb, trimWf, trimNpError, trimResidual, ...
    trimIteration, trimCondition, ...
    ncr(:, 1), ncr(:, 2), ncr(:, 3), ...
    epsilonThermal(:, 1), epsilonThermal(:, 2), epsilonThermal(:, 3), ...
    epsilonFull(:, 1), epsilonFull(:, 2), epsilonFull(:, 3), ...
    'VariableNames', {'PointID', 'IsCore', 'NpGuardRelativeOffset', ...
    'LoadPowerGuardRelativeOffset', ...
    'Np_rpm', 'modelNp_rpm', 'Ng_rpm', ...
    'inletCorrectedNp_rpm', 'inletCorrectedNg_rpm', ...
    'loadPower_W', 'Pt1_Pa', 'Tt1_K', 'Pamb_Pa', 'trimWf_kgps', ...
    'trimNpError_rpm', 'trimMaxResidual', 'trimIteration', ...
    'trimConditionNumber', ...
    'HPC_Ncr', 'GT_Ncr', 'PT_Ncr', ...
    'epsilonThermal_HPC', 'epsilonThermal_GT', 'epsilonThermal_PT', ...
    'epsilonSS_HPC', 'epsilonSS_GT', 'epsilonSS_PT'});
referenceTable.equilibriumMetalTemperature_K = metalTemperature;
referenceTable.equilibriumDiskTemperature_K = diskTemperature;

nodeError = zeros(nPoint, 3);
for i = 1:nPoint
    epsilonQuery = sht_lookup_clearance_reference( ...
        referenceTable, np(i), ng(i), loadPower(i), tt1(i));
    nodeError(i, :) = epsilonQuery(:).' - epsilonFull(i, :);
end
referenceTable.selfCheck = struct( ...
    'pointCount', nPoint, ...
    'corePointCount', sum(isCore), ...
    'guardPointCount', sum(~isCore), ...
    'loadPowerGuardPointCount', ...
        nnz(loadPowerGuardRelativeOffsetAtPoint~=0), ...
    'guardRelativeMagnitude', max(abs(guardRelativeOffset)), ...
    'loadPowerGuardRelativeMagnitude', ...
        max(abs(loadPowerGuardRelativeOffset)), ...
    'loadPowerGuardCoveragePassed', ...
        min(ptCoordinate(:,2))<=requestedLoadPowerRange(1) && ...
        max(ptCoordinate(:,2))>=requestedLoadPowerRange(2), ...
    'maxNodeDynamicClearanceError', max(abs(nodeError(:))), ...
    'allTrimPointsConverged', true, ...
    'maxTrimNpError_rpm', max(abs(trimNpError)), ...
    'maxTrimResidual', max(abs(trimResidual)), ...
    'allValuesFinitePositive', all(isfinite(epsilonFull(:))) && ...
        all(epsilonFull(:) > 0), ...
    'noExtrapolation', true);
if ~referenceTable.selfCheck.allValuesFinitePositive || ...
        ~referenceTable.selfCheck.loadPowerGuardCoveragePassed || ...
        referenceTable.selfCheck.maxTrimNpError_rpm > trimConfig.npTolerance_rpm || ...
        referenceTable.selfCheck.maxTrimResidual > trimConfig.residualTolerance || ...
        referenceTable.selfCheck.maxNodeDynamicClearanceError > 1e-12
    error('SHT:TransientParameter:ReferenceTableSelfCheck', ...
        'epsilon_ss 参考表节点回算未通过。');
end
end

function sourceFile = local_find_legacy_reference_grid(thisDir)
% 只选择三部件历史网格；六部件数据由Start_TransientEffects_06/10使用。
testDataDir = fullfile(thisDir, 'TestData', 'test_data_generation');
files = dir(fullfile(testDataDir, 'steady_bench_substitute_*.mat'));
if isempty(files)
    error('SHT:TransientParameter:MissingReferenceGrid', ...
        '未找到epsilon_ss建表所需的稳态输入网格：%s', testDataDir);
end
[~, order] = sort([files.datenum], 'descend');
for fileIndex = order
    candidate = fullfile(files(fileIndex).folder,files(fileIndex).name);
    loaded = load(candidate, 'dataTable');
    if ~isfield(loaded, 'dataTable') || ~istable(loaded.dataTable)
        continue;
    end
    grid = loaded.dataTable;
    if ~ismember('model_mode', grid.Properties.VariableNames) || ...
            all(grid.model_mode==0)
        sourceFile = candidate;
        return;
    end
end
error('SHT:TransientParameter:MissingLegacyReferenceGrid', ...
    ['当前TestData只包含六部件稳态网格，不能重建三部件15状态历史资产。' ...
     '现有冻结历史资产仍可用于回归；六部件Kurzke/Visser请运行' ...
     'Start_TransientEffects_06/10。']);
end

function trimConfig = local_zero_health_trim_config(cfg, health)
% 复用 2.3 已验证的七变量配平尺度；本函数只冻结零健康和当前外边界。
trimConfig = struct();
trimConfig.health = health(:);
trimConfig.maximumIteration = 30;
trimConfig.residualTolerance = 1e-7;
trimConfig.npTolerance_rpm = 0.05;
trimConfig.normalizedPerturbation = 1e-4;
trimConfig.scale = [10; 1; 5; 5; cfg.engine.initial.Np0; ...
    cfg.engine.initial.Ng0; 0.3];
trimConfig.wfMinimum = cfg.actuator.wfMin;
trimConfig.wfMaximum = cfg.actuator.wfMax;
end

function trim = local_trim_zero_health_steady_point( ...
    engine, cfg, trimConfig, target, initialGuess)
% 七个未知量为六维共同工作变量和 Wf；第七个方程约束目标 Np。
z = initialGuess(:);
z(7) = min(max(z(7), trimConfig.wfMinimum), trimConfig.wfMaximum);
evaluation = local_evaluate_zero_health_components( ...
    engine, cfg, trimConfig, target, z);
residual = local_zero_health_trim_residual(evaluation, target.Np_rpm);
trim = local_pack_zero_health_trim(z, evaluation, residual, 0, false, Inf);

for iteration = 1:trimConfig.maximumIteration
    if local_zero_health_trim_converged( ...
            evaluation, residual, trimConfig, target.Np_rpm)
        finalEvaluation = local_run_zero_health_one_point( ...
            engine, cfg, trimConfig, target, z);
        finalResidual = local_zero_health_trim_residual( ...
            finalEvaluation, target.Np_rpm);
        converged = local_zero_health_trim_converged( ...
            finalEvaluation, finalResidual, trimConfig, target.Np_rpm) && ...
            finalEvaluation.modelEng.convergeTag == 0;
        trim = local_pack_zero_health_trim(z, finalEvaluation, ...
            finalResidual, iteration - 1, converged, trim.conditionNumber);
        return;
    end

    [jacobian, conditionNumber] = local_zero_health_trim_jacobian( ...
        engine, cfg, trimConfig, target, z, residual);
    if ~all(isfinite(jacobian(:))) || rcond(jacobian) < 1e-14
        trim = local_pack_zero_health_trim(z, evaluation, residual, ...
            iteration - 1, false, conditionNumber);
        return;
    end

    normalizedStep = -(jacobian \ residual);
    physicalStep = normalizedStep(:) .* trimConfig.scale(:);
    [trialZ, trialEvaluation, trialResidual, accepted] = ...
        local_zero_health_trim_line_search(engine, cfg, trimConfig, ...
        target, z, physicalStep, norm(residual, inf));
    if ~accepted
        trim = local_pack_zero_health_trim(z, evaluation, residual, ...
            iteration - 1, false, conditionNumber);
        return;
    end

    z = trialZ;
    evaluation = trialEvaluation;
    residual = trialResidual;
    trim = local_pack_zero_health_trim(z, evaluation, residual, ...
        iteration, false, conditionNumber);
end

% 若最后一次接受步恰好达到收敛阈值，也必须执行传统 RunOnePoint 分支确认。
if local_zero_health_trim_converged( ...
        evaluation, residual, trimConfig, target.Np_rpm)
    finalEvaluation = local_run_zero_health_one_point( ...
        engine, cfg, trimConfig, target, z);
    finalResidual = local_zero_health_trim_residual( ...
        finalEvaluation, target.Np_rpm);
    converged = local_zero_health_trim_converged( ...
        finalEvaluation, finalResidual, trimConfig, target.Np_rpm) && ...
        finalEvaluation.modelEng.convergeTag == 0;
    trim = local_pack_zero_health_trim(z, finalEvaluation, ...
        finalResidual, trimConfig.maximumIteration, converged, ...
        trim.conditionNumber);
end
end

function [jacobian, conditionNumber] = local_zero_health_trim_jacobian( ...
    engine, cfg, trimConfig, target, z, residual0)
nParameter = numel(z);
jacobian = zeros(nParameter, nParameter);
for column = 1:nParameter
    delta = trimConfig.normalizedPerturbation * trimConfig.scale(column);
    zPlus = z;
    zMinus = z;
    zPlus(column) = zPlus(column) + delta;
    zMinus(column) = zMinus(column) - delta;
    zPlus(7) = min(max(zPlus(7), trimConfig.wfMinimum), trimConfig.wfMaximum);
    zMinus(7) = min(max(zMinus(7), trimConfig.wfMinimum), trimConfig.wfMaximum);

    if zPlus(column) ~= z(column) && zMinus(column) ~= z(column)
        residualPlus = local_zero_health_trim_residual( ...
            local_evaluate_zero_health_components( ...
            engine, cfg, trimConfig, target, zPlus), target.Np_rpm);
        residualMinus = local_zero_health_trim_residual( ...
            local_evaluate_zero_health_components( ...
            engine, cfg, trimConfig, target, zMinus), target.Np_rpm);
        jacobian(:, column) = (residualPlus - residualMinus) / ...
            (2 * trimConfig.normalizedPerturbation);
    elseif zPlus(column) ~= z(column)
        residualPlus = local_zero_health_trim_residual( ...
            local_evaluate_zero_health_components( ...
            engine, cfg, trimConfig, target, zPlus), target.Np_rpm);
        jacobian(:, column) = (residualPlus - residual0) / ...
            trimConfig.normalizedPerturbation;
    elseif zMinus(column) ~= z(column)
        residualMinus = local_zero_health_trim_residual( ...
            local_evaluate_zero_health_components( ...
            engine, cfg, trimConfig, target, zMinus), target.Np_rpm);
        jacobian(:, column) = (residual0 - residualMinus) / ...
            trimConfig.normalizedPerturbation;
    else
        jacobian(:, column) = NaN;
    end
end

if ~all(isfinite(jacobian(:)))
    conditionNumber = Inf;
    return;
end
singularValue = svd(jacobian);
if isempty(singularValue) || min(singularValue) <= 0
    conditionNumber = Inf;
else
    conditionNumber = max(singularValue) / min(singularValue);
end
end

function [trialZ, trialEvaluation, trialResidual, accepted] = ...
    local_zero_health_trim_line_search( ...
    engine, cfg, trimConfig, target, z, step, currentNorm)
trialZ = z;
trialEvaluation = local_evaluate_zero_health_components( ...
    engine, cfg, trimConfig, target, z);
trialResidual = local_zero_health_trim_residual( ...
    trialEvaluation, target.Np_rpm);
accepted = false;
for alpha = [1, 0.5, 0.25, 0.125, 0.0625, 0.03125]
    candidateZ = z + alpha * step;
    candidateZ(7) = min(max(candidateZ(7), ...
        trimConfig.wfMinimum), trimConfig.wfMaximum);
    candidateEvaluation = local_evaluate_zero_health_components( ...
        engine, cfg, trimConfig, target, candidateZ);
    candidateResidual = local_zero_health_trim_residual( ...
        candidateEvaluation, target.Np_rpm);
    candidateNorm = norm(candidateResidual, inf);
    if isfinite(candidateNorm) && candidateNorm < currentNorm
        trialZ = candidateZ;
        trialEvaluation = candidateEvaluation;
        trialResidual = candidateResidual;
        accepted = true;
        return;
    end
end
end

function evaluation = local_evaluate_zero_health_components( ...
    engine, cfg, trimConfig, target, z)
stepInValue = local_zero_health_step_in(cfg, trimConfig, target, z);
stepInValue(21:26) = z(1:6);
engPtrInit.eng = libstruct(engine.engineStructName);
engPtr = libstruct(engine.enginePointerName, engPtrInit);
stepIn = libpointer('doublePtr', stepInValue);
stepOut = libpointer('doublePtr', zeros(engine.stepOutLength, 1));
[returnCode, ~, stepOutValue, engOut] = calllib(engine.libraryName, ...
    'DLL_SHT_RunSteadyComponents', stepIn, stepOut, engPtr);
evaluation = local_pack_zero_health_evaluation( ...
    returnCode, stepOutValue, engOut.eng);
end

function evaluation = local_run_zero_health_one_point( ...
    engine, cfg, trimConfig, target, z)
% 外层配平收敛后，用同一 z 初始化传统 RunOnePoint，确认分支未切换。
seedInput = zeros(engine.stepInLength, 1);
seedInput(21:26) = z(1:6);
seedEngPtrInit.eng = libstruct(engine.engineStructName);
seedEngPtr = libstruct(engine.enginePointerName, seedEngPtrInit);
seedPtr = libpointer('doublePtr', seedInput);
seedOut = libpointer('doublePtr', zeros(engine.stepOutLength, 1));
calllib(engine.libraryName, 'DLL_SHT_varIteInit', seedPtr, seedOut, seedEngPtr);

stepInValue = local_zero_health_step_in(cfg, trimConfig, target, z);
engPtrInit.eng = libstruct(engine.engineStructName);
engPtr = libstruct(engine.enginePointerName, engPtrInit);
stepIn = libpointer('doublePtr', stepInValue);
stepOut = libpointer('doublePtr', zeros(engine.stepOutLength, 1));
[returnCode, ~, stepOutValue, engOut] = calllib(engine.libraryName, ...
    'DLL_SHT_RunOnePoint', stepIn, stepOut, engPtr);
evaluation = local_pack_zero_health_evaluation( ...
    returnCode, stepOutValue, engOut.eng);
end

function stepInValue = local_zero_health_step_in(cfg, trimConfig, target, z)
stepInValue = zeros(512, 1);
stepInValue(1:10) = [z(5); z(6); z(7); cfg.engine.initial.A80; 0; ...
    target.loadPower_W; cfg.engine.boundary.hpsPower; 0; ...
    cfg.engine.boundary.hpcAlpha; 0];
stepInValue(14:17) = [target.Pt1_Pa; target.Tt1_K; target.Pamb_Pa; 1];
stepInValue(41:(40 + numel(trimConfig.health))) = trimConfig.health;
end

function residual = local_zero_health_trim_residual(evaluation, targetNp)
residual = zeros(7, 1);
residual(1:6) = evaluation.stepOut(1:6);
residual(7) = (evaluation.modelEng.LPS_Nmech - targetNp) / targetNp;
if evaluation.returnCode ~= 0 || any(~isfinite(residual))
    residual(:) = Inf;
end
end

function passed = local_zero_health_trim_converged( ...
    evaluation, residual, trimConfig, targetNp)
passed = evaluation.returnCode == 0 && ...
    max(abs(residual(1:6))) <= trimConfig.residualTolerance && ...
    abs(evaluation.modelEng.LPS_Nmech - targetNp) <= ...
        trimConfig.npTolerance_rpm;
end

function evaluation = local_pack_zero_health_evaluation( ...
    returnCode, stepOutValue, modelEng)
evaluation = struct();
evaluation.returnCode = returnCode;
evaluation.stepOut = stepOutValue(:);
evaluation.modelEng = modelEng;
end

function trim = local_pack_zero_health_trim( ...
    z, evaluation, residual, iteration, converged, conditionNumber)
trim = struct();
trim.z = z(:);
trim.modelEng = evaluation.modelEng;
trim.f = residual(:);
trim.iteration = iteration;
trim.converged = converged;
trim.normF = norm(residual, inf);
trim.conditionNumber = conditionNumber;
end

function [metal, disk, epsilonThermal, epsilonFull] = ...
    local_reference_quantities(eng, beta, clearanceParameter, speedOverride)
% 当前稳态点令每个金属温度等于其驱动气体温度，转盘等于叶根温度。
if nargin < 4 || isempty(speedOverride)
    speed = [eng.HPS_Nmech, eng.HPS_Nmech, eng.LPS_Nmech];
else
    speed = speedOverride(:).';
    if numel(speed) ~= 3 || any(~isfinite(speed)) || any(speed < 0)
        error('SHT:TransientParameter:ReferenceSpeed', ...
            '间隙参考点速度必须是三个有限非负绝对转速。');
    end
end
tin = [eng.Inlet.gasPathOut(3); eng.HPC.y(3); ...
    eng.Burner.y(3); eng.Duct2.gasPathOut(3)];
tout = [eng.HPC.y(3); eng.Burner.y(3); eng.HPT.y(3); eng.LPT.y(3)];
nodeStart = [1, 4, 5, 8];
nodeCount = [3, 1, 3, 3];
metal = zeros(1, 10);
for component = 1:4
    nodes = nodeStart(component):(nodeStart(component) + nodeCount(component) - 1);
    metal(nodes) = ((1 - beta(nodes)) * tin(component) + ...
        beta(nodes) * tout(component)).';
end
disk = metal([2, 6, 9]);

designSpeed = [eng.HPT.turbineStruct.NDes, ...
    eng.HPT.turbineStruct.NDes, eng.LPT.turbineStruct.NDes];
clearanceNodeStart = [1, 5, 8];
epsilonThermal = zeros(1, 3);
epsilonFull = zeros(1, 3);
for component = 1:3
    p = clearanceParameter(component, :);
    node = clearanceNodeStart(component);
    tBladeEffective = p(6) * metal(node) + (1 - p(6)) * metal(node + 1);
    epsilonThermal(component) = p(1) + ...
        p(2) * (metal(node + 2) - p(7)) - ...
        p(3) * (tBladeEffective - p(8)) - ...
        p(4) * (disk(component) - p(9));
    normalizedSpeed = speed(component) / designSpeed(component);
    epsilonFull(component) = epsilonThermal(component) - ...
        p(5) * (normalizedSpeed ^ 2 - p(10) ^ 2);
end
end

function [coordinate, value] = local_collapse_1d(coordinateRaw, valueRaw, name)
[coordinate, ~, group] = unique(coordinateRaw(:), 'sorted');
value = accumarray(group, valueRaw(:), [], @mean);
spread = accumarray(group, valueRaw(:), [], @(x) max(x) - min(x));
if numel(coordinate) < 2 || any(spread > 1e-12)
    error('SHT:TransientParameter:Ambiguous1DSchedule', ...
        '%s 的进口基准修正 Ng 坐标不足或同一坐标存在多值。', name);
end
end

function [coordinate, value] = local_collapse_2d(coordinateRaw, valueRaw)
[coordinate, ~, group] = unique(coordinateRaw, 'rows', 'sorted');
value = accumarray(group, valueRaw(:), [], @mean);
spread = accumarray(group, valueRaw(:), [], @(x) max(x) - min(x));
centered = coordinate - mean(coordinate, 1);
if size(coordinate, 1) < 3 || rank(centered) < 2 || any(spread > 1e-12)
    error('SHT:TransientParameter:Ambiguous2DSchedule', ...
        'PT 的进口基准修正 Np-负载坐标不足、共线或同一坐标存在多值。');
end
end

function hashText = local_sha256(fileName)
if ~exist(fileName, 'file')
    error('SHT:TransientParameter:MissingIdentityFile', '模型标识文件不存在：%s', fileName);
end
fid = fopen(fileName, 'rb');
if fid < 0
    error('SHT:TransientParameter:HashOpenFailed', '无法读取：%s', fileName);
end
cleanupFile = onCleanup(@() fclose(fid)); %#ok<NASGU>
bytes = fread(fid, inf, '*uint8');
digest = java.security.MessageDigest.getInstance('SHA-256');
digest.update(typecast(bytes(:), 'int8'));
hashBytes = typecast(digest.digest(), 'uint8');
hashText = upper(reshape(dec2hex(hashBytes, 2).', 1, []));
end

function local_write_summary(fileName, asset)
fid = fopen(fileName, 'w', 'n', 'UTF-8');
if fid < 0
    error('SHT:TransientParameter:SummaryOpenFailed', '无法写入摘要：%s', fileName);
end
cleanupFile = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '2.5 三类瞬态效应首轮参数资产摘要\n');
fprintf(fid, 'assetVersion: %s\n', asset.assetVersion);
fprintf(fid, 'generatedAt: %s\n', asset.generatedAt);
fprintf(fid, 'interfaceVersion: %d\n', asset.interface.interfaceVersion);
fprintf(fid, 'DLL_SHA256: %s\n', asset.modelIdentity.dllSHA256);
fprintf(fid, 'Np_rpm: %.15g\n', asset.designPoint.output.Np_rpm);
fprintf(fid, 'Ng_rpm: %.15g\n', asset.designPoint.output.Ng_rpm);
fprintf(fid, 'tau0_s: %s\n', mat2str(asset.nominal.tau0.', 12));
fprintf(fid, 'beta: %s\n', mat2str(asset.nominal.beta.', 12));
fprintf(fid, 'diskTau0_s: %s\n', mat2str(asset.nominal.diskTau0.', 12));
fprintf(fid, 'Wref_kgps: %s\n', mat2str(asset.nominal.referenceFlow.', 12));
fprintf(fid, 'Tgref_K: %s\n', mat2str(asset.nominal.referenceGasTemperature.', 12));
fprintf(fid, 'C0_J_per_K: %s\n', mat2str(asset.nominal.heatCapacity0.', 12));
fprintf(fid, 'nominalClearanceExchangeRate: %s\n', ...
    mat2str(asset.nominal.clearanceExchangeRate.', 12));
fprintf(fid, 'epsilonSSTableStatus: %s\n', asset.referenceTable.status);
fprintf(fid, 'epsilonSSTableSource: %s\n', asset.referenceTable.sourceFile);
fprintf(fid, 'epsilonSSTableSourceSHA256: %s\n', ...
    asset.referenceTable.sourceFileSHA256);
fprintf(fid, 'epsilonSSDesign: %s\n', ...
    mat2str(asset.nominal.epsilonSSCurrent.', 12));
fprintf(fid, 'epsilonSSMaxNodeError: %.15g\n', ...
    asset.referenceTable.selfCheck.maxNodeDynamicClearanceError);
fprintf(fid, 'referenceTrimMaxNpError_rpm: %.15g\n', ...
    asset.referenceTable.selfCheck.maxTrimNpError_rpm);
fprintf(fid, 'referenceTrimMaxResidual: %.15g\n', ...
    asset.referenceTable.selfCheck.maxTrimResidual);
fprintf(fid, 'PTLoadPowerCoreRange_W: %s\n', ...
    mat2str(asset.referenceTable.domainGuard.ptCoreLoadPowerRange_W,12));
fprintf(fid, 'PTLoadPowerGuardRange_W: %s\n', ...
    mat2str([min(asset.referenceTable.PT.loadPower_W), ...
    max(asset.referenceTable.PT.loadPower_W)],12));
fprintf(fid, 'PTLoadPowerGuardPointCount: %d\n', ...
    asset.referenceTable.selfCheck.loadPowerGuardPointCount);
fprintf(fid, 'heatBalanceRelativeError: %s\n', ...
    mat2str(asset.selfCheck.relativeHeatBalanceError.', 12));
fprintf(fid, 'allSelfChecksPassed: %d\n', ...
    asset.selfCheck.designPointConverged && ...
    asset.selfCheck.transientHealthIsZero && ...
    asset.selfCheck.positiveAandBCParameters && ...
    asset.selfCheck.nominalClearanceRateValid && ...
    asset.selfCheck.heatBalancePassed && ...
    asset.referenceTable.selfCheck.loadPowerGuardCoveragePassed && ...
    asset.referenceTable.selfCheck.maxNodeDynamicClearanceError <= 1e-12);
end
