function cfg = sht_default_config(userCfg)
%SHT_DEFAULT_CONFIG 生成 m 程序唯一运行配置 cfg。
% 阅读说明：
%   本函数是 m_program 的集中参数入口。运行仿真只使用 cfg，不再把 baseline 作为第二套参数源传入主程序。
%   baseline 在本文件内部只是临时工作变量，用于复现 RunCtrlSysModelSHT.m 的有效初始化逻辑：
%       1) 人工给定发动机设计点/配平点；
%       2) 调用 GTESS DLL 得到设计点真实输出和转子状态初值；
%       3) 围绕设计点有限差分，提取控制律直接使用的线性化系数；
%       4) 将仿真实际需要的量整理进入 cfg.engine/cfg.sensor/cfg.controller/cfg.actuator。
%   线性化矩阵 A/B/C/D、EKF/自适应建模遗留量、线性化诊断量和记录信息不进入 cfg。
%
% 输入：
%   userCfg   可选覆盖配置。默认可省略。只需要给出待覆盖字段，例如：
%             userCfg.stopTime = 5;
%             userCfg.reference.npPulseAmplitude = 2000;
%             userCfg.controller.ngProtection.ngMax = 38000;
%
% 输出：
%   cfg       完整运行配置。后续仿真、测试和绘图均以 cfg 为唯一参数源。

% 六部件运行时会暂时切换到独立DLL目录。把本文件所在目录显式加入
% MATLAB搜索路径，保证切换目录后仍能解析同目录下的公共加载函数。
programDir = fileparts(mfilename('fullpath'));
addpath(programDir);

if nargin < 1 || isempty(userCfg)
    userCfg = struct();
end

requestedModelMode = local_requested_model_mode(userCfg);
runtimeDirectory = '';
if isfield(userCfg,'engine') && isfield(userCfg.engine,'runtimeDirectory')
    runtimeDirectory = char(userCfg.engine.runtimeDirectory);
    assert(isrow(runtimeDirectory) || isempty(runtimeDirectory), ...
        'sht:config:runtimeDirectory','runtimeDirectory必须为单一路径。');
end
designReference=[];
if isfield(userCfg,'engine') && isfield(userCfg.engine,'designReference')
    designReference=userCfg.engine.designReference;
end
work = local_build_runtime_source(requestedModelMode,runtimeDirectory,designReference);
cfg = local_build_cfg(work);

% 用户覆盖量只描述“这次仿真要改变什么”。
% 若 userCfg.simulation 内含 stopTime/Tsim 等字段，先提升到 cfg 顶层，再递归覆盖。
if ~isempty(fieldnames(userCfg))
    userCfg = local_promote_simulation_fields(userCfg);
    cfg = sht_merge_config(cfg, userCfg);
end

cfg = sht_validate_runtime_config(cfg);
cfg.controller = sht_load_controller_gain_schedule(cfg.controller);
cfg.controller = sht_load_controller_ndot_schedule(cfg.controller);
cfg = sht_validate_runtime_config(cfg);
end

function modelMode = local_requested_model_mode(userCfg)
% 模型模式会影响DLL初始化、配置文件和线性化对象，必须在递归合并
% userCfg之前确定，不能先按三部件计算后再把字段表面改成六部件。
modelMode = 0;
if isfield(userCfg, 'engine') && isstruct(userCfg.engine) && ...
        isfield(userCfg.engine, 'modelMode') && ...
        ~isempty(userCfg.engine.modelMode)
    modelMode = userCfg.engine.modelMode;
end
if ~isscalar(modelMode) || ~isfinite(modelMode) || ...
        ~ismember(modelMode, [0, 1])
    error('sht:config:badModelMode', ...
        'cfg.engine.modelMode必须是0（三部件）或1（六部件）。');
end
modelMode = round(modelMode);
end

function work = local_build_runtime_source(modelMode,runtimeDirectory,designReference)
%LOCAL_BUILD_RUNTIME_SOURCE 复现原初始化脚本的有效计算链路。
% work 是本函数内部临时变量，不作为仿真运行接口返回。

work = struct();

% 三部件直接使用正式目录；六部件使用由V2设计状态生成的独立
% offDesignMode=2运行目录，绝不改写设计用Turboshaft-TS-Split.mdl。
programDir = fileparts(mfilename('fullpath'));
work.modelMode = modelMode;
if ~isempty(runtimeDirectory)
    % 显式运行包必须在初始配平/线性化前选择，不能先调用根DLL再改路径。
    if ~java.io.File(runtimeDirectory).isAbsolute()
        runtimeDirectory=fullfile(pwd,runtimeDirectory);
    end
    assert(isfolder(runtimeDirectory),'sht:config:runtimeMissing','运行包不存在：%s',runtimeDirectory);
    work.controlDir = char(java.io.File(runtimeDirectory).getCanonicalPath());
    modelName = 'Turboshaft-TS.mdl';
    if modelMode==1,modelName='Turboshaft-TS-Split.mdl';end
    work.modelConfiguration = fullfile(work.controlDir,modelName);
    assert(isfile(work.modelConfiguration),'sht:config:modelMissing','运行包缺少模型文件。');
elseif modelMode == 1
    runtime = sht_prepare_control_model_runtime(programDir);
    work.controlDir = runtime.controlDir;
    work.modelConfiguration = runtime.modelFile;
else
    work.controlDir = programDir;
    work.modelConfiguration = fullfile(programDir, 'Turboshaft-TS.mdl');
end
work.libraryName = 'GTESS';
work.headerName = 'GTESS.h';
work.engineStructName = 'EngineTurboshaft';
work.enginePointerName = 'EngineSHTPointer';
work.stepInLength = 512;      % C 端 DLL stepIn 接口长度。
work.stepOutLength = 128;     % C 端 DLL stepOut 接口长度。
work.healthLength = 159;      % C端h0:h158；三部件仅使用前100个。
work.healthStartIndex = 41;   % MATLAB 1-based，对应 C 端 stepIn[40]。
work.healthScheduleEnableIndex = 18; % MATLAB 1-based，对应C端stepIn[17]。
work.inletBoundaryModeIndex = 17; % MATLAB 1-based，对应C端stepIn[16]。

% 人工给定发动机设计点。移植到其他发动机时，优先修改 local_design_point_parameters。
design = local_design_point_parameters();
% 显式设计解在DLL加载、配平及有限差分之前消费。默认分支不改变原数值。
work.designReference=designReference;
if ~isempty(designReference)
    assert(~isempty(runtimeDirectory),'sht:config:designRuntime', ...
        '显式设计参考必须配套明确的runtimeDirectory，不能回退到旧默认模型。');
    r=designReference;
    assert(isstruct(r) && isscalar(r) && r.schema==26101401 && r.modelMode==modelMode, ...
        'sht:config:designReference','设计参考格式或模型拓扑不一致。');
    assert(numel(r.commonVariables)==6+3*modelMode && all(isfinite(r.commonVariables)), ...
        'sht:config:designReference','设计共同工作解维数或数值不正确。');
    validateattributes([r.NpRpm,r.NgRpm,r.fuelFlowKgPerS,r.loadPowerW,r.nozzleAreaM2], ...
        {'numeric'},{'real','finite','positive'});
    fid=fopen(work.modelConfiguration,'rb');assert(fid>=0,'设计MDL不能读取。');
    guard=onCleanup(@()fclose(fid));bytes=fread(fid,Inf,'*uint8');clear guard;
    digest=java.security.MessageDigest.getInstance('SHA-256');digest.update(typecast(bytes(:),'int8'));
    hash=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
    assert(strcmpi(hash,r.sourceModelSHA256),'sht:config:designPair', ...
        '控制线性化MDL与显式设计结果不配对，禁止用旧设计点替代。');
    design.Wf0=r.fuelFlowKgPerS;design.power0=r.loadPowerW;
    design.Np0=r.NpRpm;design.Ng0=r.NgRpm;design.A80=r.nozzleAreaM2;
end
work.Wf0 = design.Wf0;
work.power0 = design.power0;
work.Np0 = design.Np0;
work.Ng0 = design.Ng0;
work.A80 = design.A80;
work.WfMax = work.Wf0 * 2;
work.WfMin = work.Wf0 * 0.01;
work.accessoryPowerW=0;
if ~isempty(designReference)
    % 本批没有重新标定执行机构和保护值。设计基准变化不自动改变物理限幅。
    inherited=local_design_point_parameters();
    work.WfMax=inherited.Wf0*2;work.WfMin=inherited.Wf0*0.01;
    work.inheritedNgMax=1.05*inherited.Ng0;
    work.accessoryPowerW=designReference.accessoryPowerW;
end

% 调用发动机模型得到设计点真实输出、状态初值和线性化直接系数。
engine = local_open_baseline_engine(work);
try
    [~, engout0] = local_run_baseline_onepoint(engine, work, ...
        [work.Np0; work.Ng0], work.Wf0, work.power0);
    [~, work.initialState, work.T450, work.PTDriveTorque0] = ...
        local_extract_initial_baseline_outputs(engout0, work.modelMode);
    if ~isempty(designReference)
        diag=local_engine_convergence_diag(engout0);
        assert(diag.convergeTag==0 && diag.errMax<=1e-6 && ...
            max(abs(work.initialState-[work.Np0;work.Ng0]))<0.1, ...
            'sht:config:designTrim','显式设计回放不闭合或转速偏离；不继续用错误点线性化。');
        work.designConsumption=struct('reference',designReference, ...
            'appliedBeforeLibraryLoad',true,'trimStateRpm',work.initialState, ...
            'linearizationStateRpm',[work.Np0;work.Ng0], ...
            'actualFuelFlowKgPerS',work.Wf0,'loadPowerW',work.power0, ...
            'nozzleAreaM2',work.A80,'trimResidualMax',diag.errMax, ...
            'inheritedWfLimits',[work.WfMin,work.WfMax],'inheritedNgMaxRpm',work.inheritedNgMax);
    end
    % Mkp 是 PT 外部负载扭矩。设计点仍以原 power0 给定负载，因此由
    % power0 和当前 Np0 换算，不能再取 DLL 内部 LPS_Trq。
    work.Mkp0 = work.power0 / (pi * work.initialState(1) / 30);
    work.Mkg0 = work.accessoryPowerW/(pi*work.initialState(2)/30);

    [~, B, ~, D] = local_linearize_baseline_engine(engine, work, design.linearizationStep);
    work.b11 = B(1, 1);
    work.b21 = B(2, 1);
    work.d31 = D(3, 1);
    work.d41 = D(4, 1);
catch err
    oldDir = engine.oldDir;
    try
        calllib(work.libraryName, 'DLL_SHT_Free');
    catch
    end
    engine = local_clear_baseline_engine_handles(engine); %#ok<NASGU>
    local_unload_baseline_library(work, oldDir);
    rethrow(err);
end
oldDir = engine.oldDir;
try
    calllib(work.libraryName, 'DLL_SHT_Free');
catch
end
engine = local_clear_baseline_engine_handles(engine); %#ok<NASGU>
local_unload_baseline_library(work, oldDir);
end

function design = local_design_point_parameters()
%LOCAL_DESIGN_POINT_PARAMETERS 人工给定的发动机设计点和配置阶段线性化步长。
% 注意：这里不保存“原始模型基准采样步长”。Tsim/Tctrl 是运行配置，在 local_build_cfg 中给默认值。
design = struct();
% 新版设计点与 RunCtrlSysModelSHT.m 保持一致。
% RunModelSHT_V1_2DP.m 属于直接调用 RunSteadyComponents 的单独设计点计算脚本，
% 其中 stepIn(21:26) 的六个部件匹配变量不作为闭环仿真入口默认配置。
design.Wf0 = 0.151914044437980;
design.power0 = 2176600;
design.Np0 = 20900;
design.Ng0 = 38000;
design.A80 = 0.10573;
design.linearizationStep = 1e-4;
end

function engine = local_open_baseline_engine(work)
%LOCAL_OPEN_BASELINE_ENGINE 打开用于配置阶段计算的 DLL 句柄。
engine = struct();
engine.oldDir = pwd;
try
    cd(work.controlDir);
    if libisloaded(work.libraryName)
        try
            calllib(work.libraryName, 'DLL_SHT_Free');
        catch
        end
        unloadlibrary(work.libraryName);
    end
    sht_load_engine_library(work.libraryName, work.headerName);
    status = calllib(work.libraryName, ...
        'DLL_SHT_InitialMode', work.modelMode);
    if status ~= 0
        error('sht:baseline:modelInitialization', ...
            'DLL_SHT_InitialMode(%d)失败，状态码=%d。', ...
            work.modelMode, status);
    end

    engPtrInit.eng = libstruct(work.engineStructName);
    engine.engPtr = libstruct(work.enginePointerName, engPtrInit);
    engine.stepIn = libpointer('doublePtr', zeros(work.stepInLength, 1));
    engine.stepOut = libpointer('doublePtr', zeros(work.stepOutLength, 1));

    % 对应原初始化脚本 ConditionsInit 前的 step_in.Value(11:13)=[0;0;0]。
    engine.stepIn.Value(11:13) = [0; 0; 0];
    calllib(work.libraryName, 'DLL_SHT_ConditionsInit', ...
        engine.stepIn, engine.stepOut, engine.engPtr);
catch err
    oldDir = engine.oldDir;
    try
        calllib(work.libraryName, 'DLL_SHT_Free');
    catch
    end
    engine = local_clear_baseline_engine_handles(engine); %#ok<NASGU>
    local_unload_baseline_library(work, oldDir);
    rethrow(err);
end
end

function engine = local_clear_baseline_engine_handles(engine)
%LOCAL_CLEAR_BASELINE_ENGINE_HANDLES 清空会阻止 unloadlibrary 的 DLL 句柄字段。
if isfield(engine, 'stepIn')
    engine.stepIn = [];
end
if isfield(engine, 'stepOut')
    engine.stepOut = [];
end
if isfield(engine, 'engPtr')
    engine.engPtr = [];
end
end

function local_unload_baseline_library(work, oldDir)
%LOCAL_UNLOAD_BASELINE_LIBRARY 卸载配置阶段 DLL 并恢复调用者当前目录。
try
    if libisloaded(work.libraryName)
        unloadlibrary(work.libraryName);
    end
catch closeErr
    warning('sht:baseline:closeFailed', ...
        'Failed to unload baseline engine library cleanly: %s', closeErr.message);
end
if ~isempty(oldDir) && exist(oldDir, 'dir')
    cd(oldDir);
end
end

function [xDot, engout, diagInfo] = local_run_baseline_onepoint(engine, work, x, wf, power)
%LOCAL_RUN_BASELINE_ONEPOINT 对应原脚本 DLL_SHT_RunOnePoint，用于配平点输出。
engine.stepIn.Value = zeros(work.stepInLength, 1);
engine.stepOut.Value = zeros(work.stepOutLength, 1);
engine.stepIn.Value(1:10) = [x(1) x(2) wf work.A80 0 power 0 0 0 0]';
engine.stepIn.Value(7)=work.accessoryPowerW;
[~, ~, stepout, engout] = calllib(work.libraryName, ...
    'DLL_SHT_RunOnePoint', engine.stepIn, engine.stepOut, engine.engPtr);
xDot = stepout(1:2);
diagInfo = local_engine_convergence_diag(engout);
local_warn_if_not_converged(diagInfo, 'RunOnePoint baseline');
end

function [xDot, engout, diagInfo] = local_run_baseline_onestep(engine, work, x, wf, power)
%LOCAL_RUN_BASELINE_ONESTEP 对应原脚本 DLL_SHT_RunOneStep，用于瞬态导数和有限差分。
engine.stepIn.Value = zeros(work.stepInLength, 1);
engine.stepOut.Value = zeros(work.stepOutLength, 1);
engine.stepIn.Value(1:10) = [x(1) x(2) wf work.A80 0 power 0 0 0 0]';
engine.stepIn.Value(7)=work.accessoryPowerW;
[~, ~, stepout, engout] = calllib(work.libraryName, ...
    'DLL_SHT_RunOneStep', engine.stepIn, engine.stepOut, engine.engPtr);
xDot = stepout(1:2);
diagInfo = local_engine_convergence_diag(engout);
local_warn_if_not_converged(diagInfo, 'RunOneStep linearization');
end

function diagInfo = local_engine_convergence_diag(engout)
%LOCAL_ENGINE_CONVERGENCE_DIAG 统一提取 DLL 收敛诊断，诊断只在配置阶段即时使用，不进入 cfg。
errs = abs([engout.eng.errOut engout.eng.Nozzle.y(end)]);
diagInfo = struct();
diagInfo.errMax = max(errs);
diagInfo.convergeTag = engout.eng.convergeTag;
end

function local_warn_if_not_converged(diagInfo, context)
%LOCAL_WARN_IF_NOT_CONVERGED 保持原脚本的收敛检查语义。
if diagInfo.convergeTag ~= 0 || diagInfo.errMax > 1e-6
    warning('sht:baseline:engineNotConverged', ...
        '%s not converged: convergeTag=%d, errMax=%g', ...
        context, diagInfo.convergeTag, diagInfo.errMax);
end
end

function [initOut, initStat, t45, ptDriveTorque] = ...
        local_extract_initial_baseline_outputs(engout, modelMode)
%LOCAL_EXTRACT_INITIAL_BASELINE_OUTPUTS 复现原脚本 InitOut/InitStat 通道定义。
% initOut 只在本地用于提取可读初值，不作为运行配置整体保留。
[hpcOut, gtOut, ptOut] = local_terminal_components(engout.eng, modelMode);
initOut = zeros(128, 1);
initOut(1) = engout.eng.Ambient.gasPathOut(4);
initOut(2) = engout.eng.Ambient.gasPathOut(3);
initOut(3) = hpcOut.y(4);
initOut(4) = hpcOut.y(3);
initOut(5) = gtOut.y(4);
initOut(6) = gtOut.y(3);
initOut(7) = ptOut.y(4);
initOut(8) = ptOut.y(3);
initOut(9) = engout.eng.LPS_Nmech;
initOut(10) = engout.eng.HPS_Nmech;
initOut(11) = engout.eng.HPC.y(8);
initOut(12) = engout.eng.LPS_Trq;
initOut(13) = engout.eng.HPC.u(6);
initOut(14) = engout.eng.HPT.y(16);
initOut(15) = engout.eng.LPT.y(16);
initOut(16) = engout.eng.timeNow;
initOut(17) = max(abs([engout.eng.errOut engout.eng.Nozzle.y(end)]));

initStat = zeros(2, 1);
initStat(1) = engout.eng.LPS_Nmech;
initStat(2) = engout.eng.HPS_Nmech;
t45 = gtOut.y(3);
ptDriveTorque = engout.eng.LPS_Trq;
end

function [hpcOut, gtOut, ptOut] = local_terminal_components(eng, modelMode)
% 三部件模型的HPC/HPT/LPT本身就是总体部件出口；六部件模型必须读取
% CC/GT2/PT2出口，才能保持Pt3/Tt3、Pt45/Tt45和Pt5/Tt5的截面定义。
if modelMode == 1
    hpcOut = eng.HPC2;
    gtOut = eng.HPT2;
    ptOut = eng.LPT2;
else
    hpcOut = eng.HPC;
    gtOut = eng.HPT;
    ptOut = eng.LPT;
end
end

function [A, B, C, D] = local_linearize_baseline_engine(engine, work, dlt)
%LOCAL_LINEARIZE_BASELINE_ENGINE 复现原脚本中心差分线性化。
% A/B/C/D 只在本函数内部用于提取 b11/b21/d31/d41，不进入运行配置。
scale = [work.Np0; work.Ng0; work.Wf0; work.power0];
x0 = [work.Np0; work.Ng0];
wf0 = work.Wf0;
power0 = work.power0;

A = zeros(2, 2);
B = zeros(2, 2);
C = [eye(2); zeros(2, 2)];
D = zeros(4, 2);

% 名义点评估用于保持原脚本线性化调用次序和收敛检查。
local_run_baseline_onestep(engine, work, x0, wf0, power0);

for j = 1:2
    xMinus = x0;
    xPlus = x0;
    dx = dlt * scale(j);
    xMinus(j) = x0(j) - dx;
    xPlus(j) = x0(j) + dx;
    [xDotMinus, outMinus] = local_linearization_eval(engine, work, xMinus, wf0, power0);
    [xDotPlus, outPlus] = local_linearization_eval(engine, work, xPlus, wf0, power0);
    A(:, j) = (xDotPlus - xDotMinus) / (2 * dx);
    C(3:4, j) = ([outPlus.T45; outPlus.PTDriveTorque] - ...
        [outMinus.T45; outMinus.PTDriveTorque]) / (2 * dx);
end

wfDelta = dlt * scale(3);
[xDotMinus, outMinus] = local_linearization_eval(engine, work, x0, wf0 - wfDelta, power0);
[xDotPlus, outPlus] = local_linearization_eval(engine, work, x0, wf0 + wfDelta, power0);
B(:, 1) = (xDotPlus - xDotMinus) / (2 * wfDelta);
D(3:4, 1) = ([outPlus.T45; outPlus.PTDriveTorque] - ...
    [outMinus.T45; outMinus.PTDriveTorque]) / (2 * wfDelta);

powerDelta = dlt * scale(4);
[xDotMinus, outMinus] = local_linearization_eval(engine, work, x0, wf0, power0 - powerDelta);
[xDotPlus, outPlus] = local_linearization_eval(engine, work, x0, wf0, power0 + powerDelta);
B(:, 2) = (xDotPlus - xDotMinus) / (2 * powerDelta);
D(3:4, 2) = ([outPlus.T45; outPlus.PTDriveTorque] - ...
    [outMinus.T45; outMinus.PTDriveTorque]) / (2 * powerDelta);
end

function [xDot, out] = local_linearization_eval(engine, work, x, wf, power)
%LOCAL_LINEARIZATION_EVAL 一次线性化扰动点评估。
[xDot, engout] = local_run_baseline_onestep(engine, work, x, wf, power);
[~, gtOut, ~] = local_terminal_components(engout.eng, work.modelMode);
out = struct();
out.T45 = gtOut.y(3);
% d41 仍表示燃油对 PT 驱动扭矩能力的局部灵敏度，供扭矩保护控制律
% 估算可用控制权；它不是外部负载扭矩 Mkp 的直接导数。
out.PTDriveTorque = engout.eng.LPS_Trq;
end

function cfg = local_build_cfg(work)
%LOCAL_BUILD_CFG 四个子系统和仿真调度的默认配置。
% 配置分层原则：
%   cfg.engine.initial     发动机设计点/配平点和输入初值；
%   cfg.engine.boundary    发动机外部边界输入，仿真时可被参考指令覆盖；
%   cfg.sensor             传感器模型；
%   cfg.controller         离散控制器和直接使用的线性化系数；
%   cfg.actuator           燃油执行机构。

cfg = struct();

% 仿真全局参数。Tsim 是连续对象数值积分步长，Tctrl 是控制器采样周期。
% 这里给出运行默认值；它不是从 Simulink 或原脚本保留下来的“模型基准采样步长”。
cfg.stopTime = 10;
cfg.Tsim = 0.025;
cfg.Tctrl = cfg.Tsim;
cfg.integrationMethod = 'euler2';
cfg.throwOnEngineNonconvergence = false;

cfg.plot = struct();
cfg.plot.enable = true;
cfg.plot.figureName = 'SHT closed-loop response';

% 发动机本体子系统。
cfg.engine = struct();
cfg.engine.modelType = 'GTESS_SHT_DLL';
cfg.engine.modelMode = work.modelMode;
if isfield(work,'designConsumption'),cfg.engine.designConsumption=work.designConsumption;end
cfg.engine.modelConfiguration = work.modelConfiguration;
cfg.engine.interface = struct();
cfg.engine.interface.controlDir = work.controlDir;
cfg.engine.interface.libraryName = work.libraryName;
cfg.engine.interface.headerName = work.headerName;
cfg.engine.interface.engineStructName = work.engineStructName;
cfg.engine.interface.enginePointerName = work.enginePointerName;
cfg.engine.interface.stepInLength = work.stepInLength;
cfg.engine.interface.stepOutLength = work.stepOutLength;
cfg.engine.interface.healthLength = work.healthLength;
cfg.engine.interface.healthStartIndex = work.healthStartIndex;
cfg.engine.interface.healthScheduleEnableIndex = ...
    work.healthScheduleEnableIndex;
cfg.engine.interface.inletBoundaryModeIndex = ...
    work.inletBoundaryModeIndex;
cfg.engine.stateNames = {'Np', 'Ng'};
cfg.engine.inputNames = {'Np', 'Ng', 'Wf', 'A8', 'Mkp', 'Mkg', 'HpcAlpha', 'health'};
cfg.engine.outputMap = 'EngineTurboshaftStruct';

% 发动机本体 0 时刻物理初值与输入初值。Np0/Ng0 是转子初值配置入口，state 由校验函数自动生成。
cfg.engine.initial = struct();
cfg.engine.initial.Np0 = work.Np0;
cfg.engine.initial.Ng0 = work.Ng0;
cfg.engine.initial.Wf0 = work.Wf0;
cfg.engine.initial.power0 = work.power0;
cfg.engine.initial.A80 = work.A80;
cfg.engine.initial.T45 = work.T450;
cfg.engine.initial.Mkp = work.Mkp0;
cfg.engine.initial.Mkg = work.Mkg0;

% 发动机边界输入。负载功率默认等于设计点 power0，仿真时可由参考指令滤波器覆盖。
cfg.engine.boundary = struct();
cfg.engine.boundary.A8 = work.A80;
cfg.engine.boundary.power = work.power0;
cfg.engine.boundary.hpsPower = work.accessoryPowerW;
% 默认闭环仍以功率指令为权威输入，适配器按实时转速生成可测负载扭矩。
cfg.engine.boundary.ptLoadInputMode = 'power';
cfg.engine.boundary.gtLoadInputMode = 'power';
cfg.engine.boundary.hpcAlpha = 0;
% 默认保持历史标准大气路径。数据生成和辨识入口必须分别显式选择模式2和3。
cfg.engine.boundary.inletBoundaryMode = 0;
cfg.engine.boundary.altitude = 0;
cfg.engine.boundary.Mach = 0;
cfg.engine.boundary.deltaTemperature = 0;
cfg.engine.boundary.health = zeros(work.healthLength, 1);
% 默认严格保持历史常值修正语义；只有显式置1才启用DLL调度表。
cfg.engine.boundary.healthScheduleEnabled = false;

% 参考指令/外部操纵。当前默认匹配 V5_2：Np 指令 1 s 开始向下 2000 rpm，持续 5 s。
cfg.reference = struct();
cfg.reference.baseNp = work.Np0;
cfg.reference.baseNg = work.Ng0;
cfg.reference.npPulseAmplitude = -2000;
cfg.reference.npPulsePeriod = 100;
cfg.reference.npPulseWidthFraction = 0.05;
cfg.reference.npPulsePhaseDelay = 1;
cfg.reference.npFilterOmega = 10;
cfg.reference.enablePowerPulse = false;
cfg.reference.powerBase = work.power0;
cfg.reference.powerPulseAmplitude = -2e5;
cfg.reference.powerPulsePeriod = 10;
cfg.reference.powerPulseWidthFraction = 0.40;
cfg.reference.powerPulsePhaseDelay = 2;
cfg.reference.powerFilterOmega = 10;

% 传感器子系统。默认 identity，后续真实传感器动态只需扩展 sht_sensor_step 和这里的参数。
cfg.sensor = struct();
cfg.sensor.mode = 'identity';
cfg.sensor.timeConstant = 0;
cfg.sensor.channels = {'Np', 'Ng', 'T45', 'Mkp', 'Ngc', 'Theta', 'Deta', ...
    'Pt2', 'Tt1', 'Pt3', 'Tt3', 'Pt45', 'Tt45', 'Pt5', 'Tt5', ...
    'HpcStallMargin', 'FAR', 'T4', 'Mkg', 'Pamb', 'Tamb', ...
    'Altitude', 'Mach'};
cfg.sensor.bias = zeros(numel(cfg.sensor.channels), 1);
cfg.sensor.noiseStd = zeros(numel(cfg.sensor.channels), 1);
cfg.sensor.randomSeed = 1;
cfg.sensor.biasModel = struct('enabled', false);

% 执行器/燃油系统子系统。只保留 Wf0，不再设置 Wfb。
cfg.actuator = struct();
cfg.actuator.modelType = 'firstOrderRateLimitedFuelMetering';
cfg.actuator.gain = 25;
cfg.actuator.initialWf = work.Wf0;
cfg.actuator.wfMin = work.WfMin;
cfg.actuator.wfMax = work.WfMax;
cfg.actuator.wfRateLimit = 1.5;  % 燃油系统最大变化率，属于执行器物理参数。

% 控制器子系统。DPpara、initial 和 linearModel 分别表示设计点基准、仿真初值和当前激活线性化系数。
cfg.controller = struct();
cfg.controller.sampleTime = cfg.Tctrl;
cfg.controller.commandDelay = 'oneSample';
cfg.controller.filterDiscretization = 'euler2';
cfg.controller.filterOmega = 10;
cfg.controller.npErrorGain = 8;
cfg.controller.npDeltaGain = 4;
cfg.controller.ngCompGain = 2;
cfg.controller.wfFilterOmega = 20;  % 原 omega_u，属于控制器内燃油指令滤波参数。

% 控制器设计点/额定基准。DPpara 只表示唯一设计点，不随本次仿真初始条件改变。
cfg.controller.DPpara = struct();
cfg.controller.DPpara.Np0 = work.Np0;
cfg.controller.DPpara.Ng0 = work.Ng0;
cfg.controller.DPpara.Wf0 = work.Wf0;
cfg.controller.DPpara.T45 = work.T450;
cfg.controller.DPpara.Mkp = work.Mkp0;

% 控制器离散状态初值。initial 表示本次仿真 t=0 时刻控制器内部记忆量的初始化基准。
cfg.controller.initial = struct();
cfg.controller.initial.Np = cfg.engine.initial.Np0;
cfg.controller.initial.Ng = cfg.engine.initial.Ng0;
cfg.controller.initial.Wf = cfg.engine.initial.Wf0;
cfg.controller.initial.T45 = cfg.engine.initial.T45;
cfg.controller.initial.Mkp = cfg.engine.initial.Mkp;

cfg.controller.linearModel = struct();
cfg.controller.linearModel.b11 = work.b11;
cfg.controller.linearModel.b21 = work.b21;
cfg.controller.linearModel.d31 = work.d31;
cfg.controller.linearModel.d41 = work.d41;

% 控制参数调度表。默认启用 Ngc 一维调度；Start_CtrlDesign_01 会生成同目录下的 mat 文件。
% 若用户显式关闭 gainSchedule.enable，则控制器回退到 cfg.controller.linearModel 固定系数。
cfg.controller.gainSchedule = struct();
cfg.controller.gainSchedule.enable = true;
cfg.controller.gainSchedule.sourceFile = fullfile(fileparts(mfilename('fullpath')), ...
    'sht_controller_gain_schedule.mat');
cfg.controller.gainSchedule.variableName = 'gainSchedule';
cfg.controller.gainSchedule.independentVariable = 'Ngc';
cfg.controller.gainSchedule.interpolationMethod = 'linear';
cfg.controller.gainSchedule.extrapolationMode = 'clamp';

% 加减速 Ngdot 调度表。Start_CtrlDesign_03 根据边界搜索结果生成同目录下的 mat 文件。
% 当前阶段已经明确：加减速限制全部关闭，暂不继续重设计 NgdotMax/NgdotMin 表。
% 因此这里默认不加载调度表，避免未校准的 Ngdot 计划继续影响诊断判断。
% 后续若只需要离线诊断，可在单独测试入口中显式设置 ndotSchedule.enable=true。
cfg.controller.ndotSchedule = struct();
cfg.controller.ndotSchedule.enable = false;
cfg.controller.ndotSchedule.sourceFile = fullfile(fileparts(mfilename('fullpath')), ...
    'sht_controller_ndot_schedule.mat');
cfg.controller.ndotSchedule.variableName = 'ndotSchedule';
cfg.controller.ndotSchedule.independentVariable = 'Ngc';
cfg.controller.ndotSchedule.interpolationMethod = 'linear';
cfg.controller.ndotSchedule.extrapolationMode = 'clamp';

% 加减速限制开关。该开关决定 NgdotMax/NgdotMin 是否真正进入 Nu 高低选。
% 当前阶段默认关闭，阶段 7/8 后续工作先聚焦可行的功率加载剖面和保护协调。
cfg.controller.accelDecelLimit = struct();
cfg.controller.accelDecelLimit.enable = false;

% 完整控制器分支固定启用：Np 主回路、Ng/T45/Mkp 保护候选和燃油增量统一限幅。
cfg.controller.fullControl = struct();
cfg.controller.fullControl.enable = true;
cfg.controller.fullControl.mode = 'stage4p5_incrementAuthority';
% 控制器已知执行机构限制。默认与物理执行器一致；做失配研究时可在 userCfg 中覆盖。
cfg.controller.actuatorLimitsKnown = struct();
cfg.controller.actuatorLimitsKnown.followPhysicalActuator = true;
cfg.controller.actuatorLimitsKnown.wfMin = cfg.actuator.wfMin;
cfg.controller.actuatorLimitsKnown.wfMax = cfg.actuator.wfMax;
cfg.controller.actuatorLimitsKnown.wfRateLimit = cfg.actuator.wfRateLimit;
cfg.controller.wfMin = cfg.controller.actuatorLimitsKnown.wfMin;
cfg.controller.wfMax = cfg.controller.actuatorLimitsKnown.wfMax;
cfg.controller.wfRateLimit = cfg.controller.actuatorLimitsKnown.wfRateLimit;

% Ng 超转保护。NgMax 只用于 Ng 超转保护，默认 1.05*设计点 Ng0。
cfg.controller.ngProtection = struct();
cfg.controller.ngProtection.enable = true;
cfg.controller.ngProtection.ngMax = 1.05 * cfg.controller.DPpara.Ng0;
if isfield(work,'inheritedNgMax'),cfg.controller.ngProtection.ngMax=work.inheritedNgMax;end
cfg.controller.ngProtection.errorGain = 4;
cfg.controller.ngProtection.errorDeltaGain = 2;

% T45 温度保护：复用 V5_2 思路的全域变增益比例候选。
cfg.controller.t45Protection = struct();
cfg.controller.t45Protection.enable = true;
cfg.controller.t45Protection.t45Max = 1400;
cfg.controller.t45Protection.gainScheduleError = [0 5 10 20 50 100 1000];
cfg.controller.t45Protection.gainScheduleValue = [4 4 8 12 16 20 24];

% Mkp 扭矩保护：与 T45 保护同构，候选 Nu 参与增量高低选。
cfg.controller.mkpProtection = struct();
cfg.controller.mkpProtection.enable = true;
cfg.controller.mkpProtection.mkpMax = 1200;
cfg.controller.mkpProtection.gainScheduleError = [0 5 10 20 50 100 1000];
cfg.controller.mkpProtection.gainScheduleValue = [4 4 8 12 16 20 24];
end

function userCfg = local_promote_simulation_fields(userCfg)
%LOCAL_PROMOTE_SIMULATION_FIELDS 兼容 userCfg.simulation.xxx 写法。
if ~isstruct(userCfg) || ~isfield(userCfg, 'simulation') || isempty(userCfg.simulation)
    return;
end
sim = userCfg.simulation;
names = {'stopTime', 'Tsim', 'Tctrl', 'integrationMethod', ...
    'throwOnEngineNonconvergence'};
for i = 1:numel(names)
    name = names{i};
    if isfield(sim, name)
        userCfg.(name) = sim.(name);
    end
end
end
