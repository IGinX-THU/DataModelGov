function varargout = sht_steady_model_adapt_common(action, varargin)
%SHT_STEADY_MODEL_ADAPT_COMMON 2.4 稳态模型修正程序的轻量公共函数。
% 本文件只放三个 Start_SteadyModelAdapt_* 程序确实共用的最小逻辑，
% 避免在多个入口程序中重复 Excel 读取、DLL 稳态回放和分组统计代码。

switch lower(action)
    case 'paths'
        varargout{1} = local_paths();
    case 'readlatesttestdata'
        [varargout{1:nargout}] = local_read_latest_test_data();
    case 'opendefaultengine'
        [varargout{1:nargout}] = local_open_default_engine(varargin{:});
    case 'closeengine'
        local_close_engine(varargin{:});
    case 'evaluatesteady'
        varargout{1} = local_evaluate_steady(varargin{:});
    case 'evaluatetransientpoint'
        varargout{1} = local_evaluate_transient_point(varargin{:});
    case 'defaultgroups'
        varargout{1} = local_default_groups();
    case 'autogroups'
        varargout{1} = local_auto_groups(varargin{:});
    case 'groupsummary'
        varargout{1} = local_group_summary(varargin{:});
    case 'candidateparameters'
        varargout{1} = local_candidate_parameters();
    case 'residualfields'
        varargout{1} = local_residual_fields();
    case 'latestmat'
        varargout{1} = local_latest_mat(varargin{:});
    case 'writetables'
        local_write_tables(varargin{:});
    otherwise
        error('sht:sma:badAction', 'Unknown steady-model-adapt common action: %s', action);
end
end

function paths = local_paths()
thisDir = fileparts(mfilename('fullpath'));
programRoot = fileparts(thisDir);
paths = struct();
paths.mProgramDir = thisDir;
paths.programRoot = programRoot;
paths.testDataDir = fullfile(thisDir, 'TestData');
paths.outputDir = fullfile(thisDir, 'MiddleData');
paths.testDataGenerationDir = fullfile(thisDir, ...
    'TestData', 'test_data_generation');
paths.testDataReportDir = fullfile(programRoot, ...
    'report_outputs', 'test_data_generation');
paths.reportOutputDir = fullfile(programRoot, ...
    'report_outputs', 'steady_model_adapt');
requiredDirs = {paths.outputDir, paths.reportOutputDir};
for i = 1:numel(requiredDirs)
    if ~exist(requiredDirs{i}, 'dir')
        mkdir(requiredDirs{i});
    end
end
end

function [pointStats, batch] = local_read_latest_test_data()
paths = local_paths();
files = dir(fullfile(paths.testDataDir, 'steady_bench_2p4_input_S2_3_2_*.xlsx'));
if isempty(files)
    error('sht:sma:noTestData', 'No 2.4 test-data Excel files were found in %s.', paths.testDataDir);
end

tokens = regexp({files.name}, '^steady_bench_2p4_input_(S2_3_2_\d{2})_(\d{8}_\d{6})\.xlsx$', 'tokens', 'once');
valid = ~cellfun(@isempty, tokens);
files = files(valid);
tokens = tokens(valid);
if isempty(files)
    error('sht:sma:noValidTestData', 'No valid 2.4 input Excel file names were found.');
end

stamps = cellfun(@(x) x{2}, tokens, 'UniformOutput', false);
uniqueStamps = unique(stamps);
latestStamp = uniqueStamps{end};
stampMask = strcmp(stamps, latestStamp);
files = files(stampMask);
tokens = tokens(stampMask);

pointNumbers = cellfun(@(x) sscanf(x{1}, 'S2_3_2_%d'), tokens);
[pointNumbers, order] = sort(pointNumbers);
files = files(order);

records = repmat(local_empty_point_record(), numel(files), 1);
for i = 1:numel(files)
    filePath = fullfile(paths.testDataDir, files(i).name);
    tbl = local_read_excel_table(filePath);
    pointId = sprintf('S2.3.2-%02d', pointNumbers(i));
    records(i) = local_point_record_from_table(tbl, filePath, pointId, pointNumbers(i));
end

pointStats = struct2table(records);

descFile = fullfile(paths.testDataReportDir, ...
    ['steady_bench_2p4_data_description_' latestStamp '.xlsx']);
batch = struct();
batch.stamp = latestStamp;
batch.testDataDir = paths.testDataDir;
batch.inputFiles = fullfile(paths.testDataDir, {files.name})';
batch.descriptionFile = descFile;
batch.pointCount = height(pointStats);
batch.shaftLoadInterfaceVersion = ...
    'Mkp_Mkg_external_torque_inputs_v2';
end

function tbl = local_read_excel_table(filePath)
try
    tbl = readtable(filePath, 'FileType', 'spreadsheet', 'TextType', 'string');
catch
    tbl = readtable(filePath, 'FileType', 'spreadsheet');
end
end

function rec = local_empty_point_record()
rec = struct();
rec.point_id = "";
rec.case_name = "";
rec.source_file = "";
rec.point_number = NaN;
rec.sample_count = NaN;
rec.steady_sample_count = NaN;
rec.steady_time_start_s = NaN;
rec.steady_time_end_s = NaN;
rec.quality_pass = false;
rec.quality_reason = "";

fields = local_statistics_fields();
for i = 1:numel(fields)
    rec.([fields{i} '_mean']) = NaN;
    rec.([fields{i} '_std']) = NaN;
end
end

function fields = local_statistics_fields()
fields = { ...
    'target_Np_ratio', 'target_Np', ...
    'target_load_power_ratio', 'target_load_power', ...
    'Np', 'Ng', 'Wf', 'T45', 'Pt45', ...
    'Mkp', 'Mkg', 'shaft_power', ...
    'Pt1', 'Tt1', 'Pt3', 'Tt3', 'Pamb', 'Tamb'};
end

function rec = local_point_record_from_table(tbl, filePath, pointId, pointNumber)
requiredInterface = "Mkp_Mkg_external_torque_inputs_v2";
interfaceVersion = string(local_first_text( ...
    tbl, 'shaft_load_interface_version', ''));
if interfaceVersion ~= requiredInterface
    error('sht:sma:staleShaftLoadInterface', ...
        ['稳态试车数据未声明当前 Mkp/Mkg 外部扭矩输入接口：%s。' ...
         '请重新运行 Start_TestDataGen_01_SteadyBenchSubstituteData。'], ...
        filePath);
end

rec = local_empty_point_record();
rec.point_id = string(pointId);
rec.point_number = pointNumber;
rec.source_file = string(filePath);
rec.case_name = local_first_text(tbl, 'case_name', pointId);
rec.sample_count = height(tbl);

mask = local_steady_mask(tbl);
rec.steady_sample_count = sum(mask);
if any(mask)
    time = local_column(tbl, 'time_s', NaN(height(tbl), 1));
    rec.steady_time_start_s = min(time(mask));
    rec.steady_time_end_s = max(time(mask));
end

if local_has_column(tbl, 'quality_pass')
    q = local_column(tbl, 'quality_pass', true(height(tbl), 1));
    rec.quality_pass = all(logical(q(mask)));
else
    rec.quality_pass = true;
end
rec.quality_reason = local_first_text(tbl, 'quality_reason', '');

fields = local_statistics_fields();
for i = 1:numel(fields)
    value = local_column(tbl, fields{i}, NaN(height(tbl), 1));
    rec.([fields{i} '_mean']) = mean(value(mask), 'omitnan');
    rec.([fields{i} '_std']) = std(value(mask), 0, 'omitnan');
end
end

function mask = local_steady_mask(tbl)
n = height(tbl);
if local_has_column(tbl, 'steady_window_flag')
    mask = logical(local_column(tbl, 'steady_window_flag', false(n, 1)));
else
    time = local_column(tbl, 'time_s', (0:n-1)');
    tEnd = max(time);
    mask = time >= tEnd - 5;
end
mask = mask(:);
if ~any(mask)
    mask = true(n, 1);
end
end

function tf = local_has_column(tbl, name)
tf = ismember(name, tbl.Properties.VariableNames);
end

function x = local_column(tbl, name, defaultValue)
if local_has_column(tbl, name)
    x = tbl.(name);
else
    x = defaultValue;
end
if iscell(x)
    x = string(x);
end
if isstring(x) || ischar(x)
    x = str2double(x);
end
x = x(:);
end

function txt = local_first_text(tbl, name, defaultValue)
if local_has_column(tbl, name) && height(tbl) > 0
    raw = tbl.(name);
    if iscell(raw)
        txt = string(raw{1});
    elseif isstring(raw)
        txt = raw(1);
    else
        txt = string(raw(1));
    end
else
    txt = string(defaultValue);
end
end

function [engine, cfg] = local_open_default_engine(varargin)
% 不给模式时保留原三部件行为；第二轮六部件程序应显式传入1。
modelMode = 0;
if ~isempty(varargin)
    modelMode = varargin{1};
end
if ~isscalar(modelMode) || ~isfinite(modelMode) || ...
        ~ismember(round(modelMode), [0, 1])
    error('SHT:SteadyAdapt:BadModelMode', ...
        'openDefaultEngine的模型模式必须为0或1。');
end
cfg = sht_default_config(struct( ...
    'engine', struct('modelMode', round(modelMode))));
engine = sht_engine_open(cfg.engine);
end

function local_close_engine(engine)
if nargin > 0
    sht_engine_close(engine);
end
end

function ev = local_evaluate_steady(engine, cfg, point, health)
%LOCAL_EVALUATE_STEADY 使用测量均值输入调用 DLL_SHT_RunOnePoint。
% point 为 pointStats 的一行 table 或 struct，health 为 100 维修正系数向量。
if nargin < 4 || isempty(health)
    health = zeros(cfg.engine.interface.healthLength, 1);
end
health = health(:);
if numel(health) < cfg.engine.interface.healthLength
    health(end+1:cfg.engine.interface.healthLength, 1) = 0;
end

np0 = local_point_value(point, 'Np_mean', cfg.engine.initial.Np0);
ng0 = local_point_value(point, 'Ng_mean', cfg.engine.initial.Ng0);
wf = local_point_value(point, 'Wf_mean', cfg.engine.initial.Wf0);
loadBoundary = local_point_load_boundary(point, cfg, np0, ng0);
pt1 = local_point_value(point, 'Pt1_mean', NaN);
tt1 = local_point_value(point, 'Tt1_mean', NaN);
ps = local_point_value(point, 'Pamb_mean', NaN);

stepInValue = zeros(cfg.engine.interface.stepInLength, 1);
stepInValue(1:10) = [ ...
    np0, ...
    ng0, ...
    wf, ...
    cfg.engine.boundary.A8, ...
    0, ...
    loadBoundary.power, ...
    loadBoundary.hpsPower, ...
    0, ...
    cfg.engine.boundary.hpcAlpha, ...
    0];

% C 端采用 0 基下标：stepIn[13]=Pt1，stepIn[14]=Tt1，
% stepIn[15]=Ps，stepIn[16]=外部入口边界启用标志。
% MATLAB 侧对应 1 基下标 14:17。该入口边界只用于 2.4
% Start_SteadyModelAdapt_* 程序，其他程序暂不改动。
if all(isfinite([pt1, tt1, ps])) && all([pt1, tt1, ps] > 0)
    stepInValue(14:17) = [pt1; tt1; ps; 1];
end

idx0 = cfg.engine.interface.healthStartIndex;
idx1 = idx0 + cfg.engine.interface.healthLength - 1;
stepInValue(idx0:idx1) = health(1:cfg.engine.interface.healthLength);

engPtrInit.eng = libstruct(engine.engineStructName);
engPtr = libstruct(engine.enginePointerName, engPtrInit);
stepIn = libpointer('doublePtr', stepInValue);
stepOut = libpointer('doublePtr', zeros(cfg.engine.interface.stepOutLength, 1));

seedInfo = local_set_var_start(engine, cfg, point, stepOut, engPtr);

if cfg.engine.modelMode == 1 && seedInfo.isSpecialized
    seedSolve = sht_solve_steady_components_from_seed( ...
        engine, cfg, stepInValue, seedInfo.varIte);
    ret = seedSolve.ret;
    stepOutValue = seedSolve.stepOut;
    engOut = seedSolve.engOut;
    explicitSeedSolveUsed = true;
    explicitSeedSolveIterations = seedSolve.iteration;
    explicitSeedSolveConverged = seedSolve.converged;
else
    [ret, ~, stepOutValue, engOut] = calllib( ...
        engine.libraryName, 'DLL_SHT_RunOnePoint', ...
        stepIn, stepOut, engPtr);
    explicitSeedSolveUsed = false;
    explicitSeedSolveIterations = 0;
    explicitSeedSolveConverged = engOut.eng.convergeTag == 0;
end

ev = local_pack_steady_eval( ...
    ret, stepOutValue, engOut.eng, wf, loadBoundary, ...
    cfg.engine.modelMode);
if explicitSeedSolveUsed && ~explicitSeedSolveConverged
    ev.convergeTag = 1;
    ev.maxErr = max(ev.maxErr, seedSolve.residualInfinityNorm);
    ev.output.max_model_error = ev.maxErr;
end
ev.initialGuessId = seedInfo.id;
ev.explicitSeedSolveUsed = explicitSeedSolveUsed;
ev.explicitSeedSolveIterations = explicitSeedSolveIterations;
ev.explicitSeedSolveConverged = explicitSeedSolveConverged;
end

function ev = local_evaluate_transient_point(engine, cfg, point, health)
%LOCAL_EVALUATE_TRANSIENT_POINT 使用瞬态点模型调用 DLL_SHT_RunOneStep。
% 该入口用于 2.4 方案 B：Np/Ng 取试车测量稳态均值并作为模型输入，
% C 端只求解 WIn、HPC_Rline、HPT_PR 和 LPT_PR 四个气动共同工作变量。
if nargin < 4 || isempty(health)
    health = zeros(cfg.engine.interface.healthLength, 1);
end
health = health(:);
if numel(health) < cfg.engine.interface.healthLength
    health(end+1:cfg.engine.interface.healthLength, 1) = 0;
end

np = local_point_value(point, 'Np_mean', cfg.engine.initial.Np0);
ng = local_point_value(point, 'Ng_mean', cfg.engine.initial.Ng0);
wf = local_point_value(point, 'Wf_mean', cfg.engine.initial.Wf0);
loadBoundary = local_point_load_boundary(point, cfg, np, ng);
pt1 = local_point_value(point, 'Pt1_mean', NaN);
tt1 = local_point_value(point, 'Tt1_mean', NaN);
ps = local_point_value(point, 'Pamb_mean', NaN);

stepInValue = zeros(cfg.engine.interface.stepInLength, 1);
stepInValue(1:10) = [ ...
    np, ...
    ng, ...
    wf, ...
    cfg.engine.boundary.A8, ...
    0, ...
    loadBoundary.power, ...
    loadBoundary.hpsPower, ...
    0, ...
    cfg.engine.boundary.hpcAlpha, ...
    0];

% C 端 0 基下标 stepIn[13:16] 对应 MATLAB 1 基下标 14:17。
% 这里把 Pt1/Tt1/Ps 作为进气道入口边界给定，避免方案 B 使用默认环境边界。
if all(isfinite([pt1, tt1, ps])) && all([pt1, tt1, ps] > 0)
    stepInValue(14:17) = [pt1; tt1; ps; 1];
end

idx0 = cfg.engine.interface.healthStartIndex;
idx1 = idx0 + cfg.engine.interface.healthLength - 1;
stepInValue(idx0:idx1) = health(1:cfg.engine.interface.healthLength);

engPtrInit.eng = libstruct(engine.engineStructName);
engPtr = libstruct(engine.enginePointerName, engPtrInit);
stepIn = libpointer('doublePtr', stepInValue);
stepOut = libpointer('doublePtr', zeros(cfg.engine.interface.stepOutLength, 1));

% RunOneStep 内部仍使用 C 端 varStartStore 作为 4 维共同工作变量初值。
% 每个工况点调用前显式重置，可以保证雅可比中心差分可重复。
local_set_var_start(engine, cfg, point, stepOut, engPtr);

[ret, ~, stepOutValue, engOut] = calllib( ...
    engine.libraryName, 'DLL_SHT_RunOneStep', stepIn, stepOut, engPtr);

ev = local_pack_transient_point_eval( ...
    ret, stepOutValue, engOut.eng, wf, loadBoundary, ...
    cfg.engine.modelMode);
end

function boundary = local_point_load_boundary(point, cfg, np, ng)
% Mkp/Mkg 是稳态点或瞬态点的外部测量输入。旧数据若暂时缺少对应字段，
% 只允许由原功率字段换算以完成迁移，不能回退到 DLL 内部扭矩输出。
boundary = cfg.engine.boundary;
mkpDefault = local_point_value(point, 'target_load_power_mean', ...
    cfg.engine.initial.power0) / max(pi*np/30, eps);
mkgDefault = local_default_mkg(cfg, ng);
boundary.Mkp = local_point_value(point, 'Mkp_mean', mkpDefault);
boundary.Mkg = local_point_value(point, 'Mkg_mean', mkgDefault);
boundary.ptLoadInputMode = 'torque';
boundary.gtLoadInputMode = 'torque';
boundary = sht_resolve_shaft_load_boundary(boundary, [np; ng]);
end

function mkg = local_default_mkg(cfg, ng)
if isfield(cfg.engine.boundary, 'Mkg') && ...
        isnumeric(cfg.engine.boundary.Mkg) && ...
        isscalar(cfg.engine.boundary.Mkg) && ...
        isfinite(cfg.engine.boundary.Mkg)
    mkg = cfg.engine.boundary.Mkg;
else
    mkg = cfg.engine.boundary.hpsPower / max(pi*ng/30, eps);
end
end

function seedInfo = local_set_var_start(engine, cfg, point, stepOut, engPtr)
%LOCAL_SET_VAR_START 每次稳态评价前重置 C 端非线性求解初值。
% C 端 DLL_SHT_RunOnePoint 会沿用全局 varStartStore。参数估计和
% Jacobi 差分要求每个工况点独立、可重复计算，因此这里显式调用
% DLL_SHT_varIteInit，避免前一次工况的收敛结果影响当前残差。三部件
% 模式写入6维初值，六部件模式必须写入完整9维初值。
stepInValue = zeros(cfg.engine.interface.stepInLength, 1);
[seed, seedInfo] = local_var_start_seed(cfg, point);
stepInValue(21:(20 + numel(seed))) = seed(:);
stepIn = libpointer('doublePtr', stepInValue);
calllib(engine.libraryName, 'DLL_SHT_varIteInit', stepIn, stepOut, engPtr);
end

function [seed, seedInfo] = local_var_start_seed(cfg, point)
%LOCAL_VAR_START_SEED 构造与模型模式严格一致的稳态共同工作初值。
% mode=0的六个量为[WIn,HPC_Rline,HPT_PR,LPT_PR,Np,Ng]；mode=1
% 的九个量为[WIn,AC_Rline,CC_Rline,GT1_PR,GT2_PR,PT1_PR,PT2_PR,Np,Ng]。
% 初值只服务于非线性方程求解，不作为测量数据或估计结果。当前 2.3
% 地面慢车及其邻近低负载点优先使用公共固化初值；其他六部件工况
% 使用当前V2设计状态初值。每次回放仍由C端Newton完成严格残差验收。
powerRatio = local_point_value(point, 'target_load_power_ratio_mean', ...
    local_point_value(point, 'target_load_power_mean', cfg.engine.initial.power0) / cfg.engine.initial.power0);
npRatio = local_point_value(point, 'target_Np_ratio_mean', ...
    local_point_value(point, 'Np_mean', cfg.engine.initial.Np0) / cfg.engine.initial.Np0);

if cfg.engine.modelMode == 1
    targetNp = npRatio * cfg.engine.initial.Np0;
    targetPower = powerRatio * cfg.engine.initial.power0;
    seedInfo = sht_get_steady_trim_initial_guess( ...
        cfg, targetNp, targetPower, 'auto');
    if ~seedInfo.available || numel(seedInfo.varIte) ~= 9 || ...
            any(~isfinite(seedInfo.varIte))
        error('SHT:SteadyAdapt:SixComponentSeedUnavailable', ...
            '无法为六部件工况构造有效的9维共同工作初值。');
    end
    seed = seedInfo.varIte(:);
    seed(8) = local_point_value(point, 'Np_mean', seed(8));
    seed(9) = local_point_value(point, 'Ng_mean', seed(9));
    seedInfo.varIte = seed;
    return;
end

seedInfo = struct('id', 'three_component_engineering_curve', ...
    'isSpecialized', false, 'available', true);

powerDrop = max(0, 1 - powerRatio);
npDrop = max(0, 1 - npRatio);
npRise = max(0, npRatio - 1);

wInDefault = 6.693 - 3.0 * powerDrop + 1.0 * npDrop - 0.6 * npRise;
hpcRlineDefault = 0.707 + 0.16 * powerDrop + 0.02 * npDrop;
hptPRDefault = 4.012 - 0.21 * powerDrop + 0.40 * npDrop;
lptPRDefault = 3.465 - 1.70 * powerDrop + 0.20 * npDrop;

wInDefault = min(max(wInDefault, 5.5), 7.2);
hpcRlineDefault = min(max(hpcRlineDefault, 0.5), 0.95);
hptPRDefault = min(max(hptPRDefault, 3.2), 4.4);
lptPRDefault = min(max(lptPRDefault, 2.5), 3.8);

wIn = local_point_value(point, 'WIn', local_point_value(point, 'WIn_mean', wInDefault));
hpcRline = local_point_value(point, 'HPC_Rline', hpcRlineDefault);
hptPR = local_point_value(point, 'HPT_PR', hptPRDefault);
lptPR = local_point_value(point, 'LPT_PR', lptPRDefault);
np = local_point_value(point, 'Np_mean', cfg.engine.initial.Np0);
ng = local_point_value(point, 'Ng_mean', cfg.engine.initial.Ng0);

seed = [wIn; hpcRline; hptPR; lptPR; np; ng];
fallback = [wInDefault; hpcRlineDefault; hptPRDefault; lptPRDefault; cfg.engine.initial.Np0; cfg.engine.initial.Ng0];
bad = ~isfinite(seed);
seed(bad) = fallback(bad);
end

function value = local_point_value(point, fieldName, defaultValue)
if istable(point)
    if ismember(fieldName, point.Properties.VariableNames)
        value = point.(fieldName)(1);
    else
        value = defaultValue;
    end
elseif isstruct(point) && isfield(point, fieldName)
    value = point.(fieldName);
else
    value = defaultValue;
end
if isempty(value) || (isnumeric(value) && isnan(value))
    value = defaultValue;
end
end

function ev = local_pack_steady_eval( ...
        ret, stepOutValue, eng, wf, loadBoundary, modelMode)
errs = abs([eng.errOut(:); eng.Nozzle.y(end)]);
ev = struct();
ev.ret = ret;
ev.stepOut = stepOutValue(:);
ev.convergeTag = eng.convergeTag;
ev.maxErr = max(errs);
ev.varIte = eng.varIte(1:eng.varVecDime).';
ev.WIn = ev.varIte(1);

y = struct();
y.Np = eng.LPS_Nmech;
y.Ng = eng.HPS_Nmech;
y.Wf = wf;
y.Mkp = loadBoundary.Mkp;
y.Mkg = loadBoundary.Mkg;
y.target_load_power = loadBoundary.power;
y.hps_load_power = loadBoundary.hpsPower;
y.Pt1 = eng.Ambient.gasPathOut(4);
y.Tt1 = eng.Ambient.gasPathOut(3);
y.Pamb = eng.Ambient.y(5);
y.Tamb = eng.Ambient.y(6);
if modelMode == 1
    hpc = eng.HPC2;
    gt = eng.HPT2;
    pt = eng.LPT2;
else
    hpc = eng.HPC;
    gt = eng.HPT;
    pt = eng.LPT;
end
y.Pt3 = hpc.y(4);
y.Tt3 = hpc.y(3);
y.T45 = gt.y(3);
y.Pt45 = gt.y(4);
y.shaft_power = loadBoundary.power;
y.PTDriveTorque = eng.LPS_Trq;
y.GTInternalNetTorque = eng.HPS_Trq;
y.HPC_Ncr = hpc.y(16);
y.HPT_Ncr = gt.y(15);
y.LPT_Ncr = pt.y(15);
y.HPC_WcMap = hpc.y(17);
y.HPT_WcMap = gt.y(16);
y.LPT_WcMap = pt.y(16);
y.HPT_Beta = gt.y(17);
y.LPT_Beta = pt.y(17);
y.WIn = ev.WIn;
y.Inlet_WOut = eng.Inlet.gasPathOut(1);
% eng.HPC.gasPathIn 在 MATLAB 中是 C 指针，不能直接作为数值使用。
% HPC 入口流量与 Inlet 出口流量同一气路节点，故用 Inlet.gasPathOut(1)。
y.HPC_WIn = y.Inlet_WOut;
y.ErrHPC = eng.errOut(1);
y.ErrHPT = eng.errOut(2);
y.ErrLPT = eng.errOut(3);
y.ErrNozzle = eng.errOut(4);
y.ErrLPS = eng.errOut(5);
y.ErrHPS = eng.errOut(6);
y.ErrNozzleEnd = eng.Nozzle.y(end);
y.max_model_error = ev.maxErr;
ev.output = y;
end

function ev = local_pack_transient_point_eval( ...
        ret, stepOutValue, eng, wf, loadBoundary, modelMode)
%LOCAL_PACK_TRANSIENT_POINT_EVAL 统一打包方案 B 瞬态点模型输出。
% 先复用稳态回放的输出映射，再补充轴动力学诊断量。
ev = local_pack_steady_eval( ...
    ret, stepOutValue, eng, wf, loadBoundary, modelMode);
dNpDt = stepOutValue(1);
dNgDt = stepOutValue(2);

ev.xDot = [dNpDt; dNgDt];
ev.output.dNp_dt = dNpDt;
ev.output.dNg_dt = dNgDt;
ev.output.PT_torque_balance = ev.output.PTDriveTorque - ev.output.Mkp;
ev.output.GT_torque_balance = ev.output.GTInternalNetTorque - ev.output.Mkg;
end

function groups = local_default_groups()
groups = struct([]);
groups(1).group_id = "G1";
groups(1).role = "estimate";
groups(1).description = "主估计组";
groups(1).points = ["S2.3.2-01","S2.3.2-02","S2.3.2-03","S2.3.2-04","S2.3.2-05","S2.3.2-06"];

groups(2).group_id = "T1";
groups(2).role = "test";
groups(2).description = "测试验证点";
groups(2).points = "S2.3.2-07";

groups(3).group_id = "G2";
groups(3).role = "local_check";
groups(3).description = "低 LPT_Ncr 局部组";
groups(3).points = ["S2.3.2-08","S2.3.2-09"];
end

function groups = local_auto_groups(pointStats, thresholdPctpt)
%LOCAL_AUTO_GROUPS 按三部件 Ncr 跨度自动生成允许重叠的工况组。
% 在原始试车工况顺序上寻找连续窗口；只要 HPC/HPT/LPT 三个部件
% Ncr 的组内跨度都不超过 thresholdPctpt，就认为该窗口可以成组。
% 输出时仅保留最大有效窗口，避免把被包含的短窗口全部列出；不同
% 最大窗口可以共享工况点。未被多点组覆盖的工况点作为单点组显示。
if nargin < 2 || isempty(thresholdPctpt)
    thresholdPctpt = 5;
end

nPoint = height(pointStats);
if nPoint == 0
    groups = struct([]);
    return;
end

starts = [];
ends = [];
for i = 1:nPoint
    for j = (i + 1):nPoint
        sub = pointStats(i:j, :);
        spans = local_ncr_spans_pctpt(sub);
        if all(spans <= thresholdPctpt)
            starts(end + 1, 1) = i; %#ok<AGROW>
            ends(end + 1, 1) = j; %#ok<AGROW>
        else
            break;
        end
    end
end

if ~isempty(starts)
    keep = true(numel(starts), 1);
    for i = 1:numel(starts)
        for j = 1:numel(starts)
            if i == j
                continue;
            end
            containedByLarger = starts(j) <= starts(i) && ends(j) >= ends(i) ...
                && (starts(j) < starts(i) || ends(j) > ends(i));
            if containedByLarger
                keep(i) = false;
                break;
            end
        end
    end
    starts = starts(keep);
    ends = ends(keep);
end

pointIds = string(pointStats.point_id);
covered = false(nPoint, 1);
groupRanges = {};
groupKind = strings(0, 1);

for i = 1:numel(starts)
    idx = starts(i):ends(i);
    groupRanges{end + 1, 1} = idx; %#ok<AGROW>
    groupKind(end + 1, 1) = "multi"; %#ok<AGROW>
    covered(idx) = true;
end

for i = 1:nPoint
    if ~covered(i)
        groupRanges{end + 1, 1} = i; %#ok<AGROW>
        groupKind(end + 1, 1) = "single"; %#ok<AGROW>
    end
end

groups = struct([]);
for i = 1:numel(groupRanges)
    idx = groupRanges{i};
    groups(i).group_id = string(sprintf('G%02d', i));
    if groupKind(i) == "multi" && i == 1
        groups(i).role = "estimate";
    elseif groupKind(i) == "multi"
        groups(i).role = "local_check";
    else
        groups(i).role = "single_point";
    end
    groups(i).description = string(sprintf('%s, three-component Ncr span <= %.3g pctpt', char(groupKind(i)), thresholdPctpt));
    groups(i).points = pointIds(idx).';
end
end

function spans = local_ncr_spans_pctpt(tbl)
[~, ~, hpcSpan] = local_span_pctpt(tbl, 'HPC_Ncr');
[~, ~, hptSpan] = local_span_pctpt(tbl, 'HPT_Ncr');
[~, ~, lptSpan] = local_span_pctpt(tbl, 'LPT_Ncr');
spans = [hpcSpan, hptSpan, lptSpan];
end

function groupTable = local_group_summary(pointStats, groups)
records = repmat(struct( ...
    'group_id',"", 'role',"", 'description',"", 'source_points',"", ...
    'point_count',NaN, ...
    'HPC_Ncr_min',NaN, 'HPC_Ncr_max',NaN, 'HPC_Ncr_span_pctpt',NaN, ...
    'HPT_Ncr_min',NaN, 'HPT_Ncr_max',NaN, 'HPT_Ncr_span_pctpt',NaN, ...
    'LPT_Ncr_min',NaN, 'LPT_Ncr_max',NaN, 'LPT_Ncr_span_pctpt',NaN, ...
    'WIn_min',NaN, 'WIn_max',NaN, 'WIn_span',NaN, ...
    'ncr_span_warning',false), numel(groups), 1);

for i = 1:numel(groups)
    mask = ismember(string(pointStats.point_id), groups(i).points);
    sub = pointStats(mask, :);
    records(i).group_id = groups(i).group_id;
    records(i).role = groups(i).role;
    records(i).description = groups(i).description;
    records(i).source_points = strjoin(groups(i).points, ",");
    records(i).point_count = height(sub);
    [records(i).HPC_Ncr_min, records(i).HPC_Ncr_max, records(i).HPC_Ncr_span_pctpt] = local_span_pctpt(sub, 'HPC_Ncr');
    [records(i).HPT_Ncr_min, records(i).HPT_Ncr_max, records(i).HPT_Ncr_span_pctpt] = local_span_pctpt(sub, 'HPT_Ncr');
    [records(i).LPT_Ncr_min, records(i).LPT_Ncr_max, records(i).LPT_Ncr_span_pctpt] = local_span_pctpt(sub, 'LPT_Ncr');
    [records(i).WIn_min, records(i).WIn_max, records(i).WIn_span] = local_span_abs(sub, 'WIn');
    records(i).ncr_span_warning = any([ ...
        records(i).HPC_Ncr_span_pctpt, records(i).HPT_Ncr_span_pctpt, records(i).LPT_Ncr_span_pctpt] > 5);
end

groupTable = struct2table(records);
end

function [vmin, vmax, span] = local_span_pctpt(tbl, fieldName)
[vmin, vmax, rawSpan] = local_span_abs(tbl, fieldName);
span = rawSpan * 100;
end

function [vmin, vmax, span] = local_span_abs(tbl, fieldName)
if isempty(tbl) || ~ismember(fieldName, tbl.Properties.VariableNames)
    vmin = NaN; vmax = NaN; span = NaN;
    return;
end
v = tbl.(fieldName);
vmin = min(v, [], 'omitnan');
vmax = max(v, [], 'omitnan');
span = vmax - vmin;
end

function params = local_candidate_parameters()
theta_id = [1; 2; 3; 8; 9; 11; 12; 13; 15; 16];
theta_name = [ ...
    "Inlet.hpdP_Loss"; ...
    "HPC.hpW"; ...
    "HPC.hpEf"; ...
    "HPT.hpW"; ...
    "HPT.hpEf"; ...
    "Duct2.hpdP_Loss"; ...
    "LPT.hpW"; ...
    "LPT.hpEf"; ...
    "Duct3.hpdP_Loss"; ...
    "Nozzle.hpA8"];
theta_type = ["压损"; "流量"; "效率"; "流量"; "效率"; "压损"; "流量"; "效率"; "压损"; "面积"];
schedule_table = ["FlowPath"; "HPC"; "HPC"; "HPT"; "HPT"; "FlowPath"; "LPT"; "LPT"; "FlowPath"; "FlowPath"];
scheduler_name = ["WIn"; "HPC_Ncr"; "HPC_Ncr"; "HPT_Ncr"; "HPT_Ncr"; "WIn"; "LPT_Ncr"; "LPT_Ncr"; "WIn"; "WIn"];
theta_limit = 0.10 * ones(numel(theta_id), 1);
params = table(theta_id, theta_name, theta_type, schedule_table, scheduler_name, theta_limit);
end

function fields = local_residual_fields()
fields = {'Np','Ng','Pt3','Tt3','T45','Pt45'};
end

function filePath = local_latest_mat(pattern)
paths = local_paths();
files = dir(fullfile(paths.outputDir, pattern));
if isempty(files)
    filePath = "";
    return;
end
[~, idx] = max([files.datenum]);
filePath = string(fullfile(paths.outputDir, files(idx).name));
end

function local_write_tables(filePath, sheetTables)
names = fieldnames(sheetTables);
for i = 1:numel(names)
    tbl = sheetTables.(names{i});
    if isempty(tbl)
        continue;
    end
    writetable(tbl, filePath, 'Sheet', names{i});
end
end
