function [xDot, y, diagInfo] = sht_engine_derivative(engine, xEngine, wf, boundary)
% 阅读说明：
%   本文件是 MATLAB 侧调用 GTESS.dll 的发动机连续对象封装。
%   输入为当前发动机状态、实际燃油流量和边界条件；输出为状态导数、发动机输出测量量和收敛诊断。
%   所有与 DLL 输出通道顺序相关的细节集中在本文件，避免散落到控制器代码中。
%SHT_ENGINE_DERIVATIVE Evaluate GTESS engine derivative and output.
% 发动机本体连续模型接口。
%
% Derivatives 方法：将当前转子状态、燃油量、喷口面积、外部轴负载等
% 组装为 stepIn，调用 GTESS.dll 的 DLL_SHT_RunOneStep。
%
% 输入：
%   基准模式 xEngine=[Np;Ng]；三部件Kurzke在其后追加10+3个热状态，
%   三部件Visser另有1个GT等效导向器温度；
%   六部件Kurzke追加19个金属温度和6个转盘温度；六部件Visser
%   再在末尾追加GT1/GT2两个导向叶片温度；
%   wf      = 燃油执行机构输出；
%   boundary 包含 A8、Mkp、Mkg、hpcAlpha、health 等上层边界量。
%   原生扭矩模式由DLL按候选轴速换算功率；历史功率边界仍显式保留。
%
% 输出：
%   xDot    = 与 xEngine 同维的状态导数；
%   y       = 命名后的发动机测量/诊断量；
%   diagInfo= DLL 收敛标志与残差。

% DLL 输入数组长度与 C 端 engineTurboshaft.c 保持一致：stepIn[512]。
% 修正系数从MATLAB的41号元素开始写入，对应C端
% stepIn[40]，h0:h158共159个；三部件模式只解释前100个。
stepInLength = 512;
stepOutLength = 128;
healthLength = 159;
healthStartIndex = 41;
healthScheduleEnableIndex = 18;
if isfield(engine, 'stepInLength') && ~isempty(engine.stepInLength)
    stepInLength = engine.stepInLength;
end
if isfield(engine, 'stepOutLength') && ~isempty(engine.stepOutLength)
    stepOutLength = engine.stepOutLength;
end
if isfield(engine, 'healthLength') && ~isempty(engine.healthLength)
    healthLength = engine.healthLength;
end
if isfield(engine, 'healthStartIndex') && ~isempty(engine.healthStartIndex)
    healthStartIndex = engine.healthStartIndex;
end
if isfield(engine, 'healthScheduleEnableIndex') && ...
        ~isempty(engine.healthScheduleEnableIndex)
    healthScheduleEnableIndex = engine.healthScheduleEnableIndex;
end
healthEndIndex = healthStartIndex + healthLength - 1;
if stepInLength < max(healthEndIndex, healthScheduleEnableIndex)
    error('sht:engine:stepInTooShort', 'stepInLength must cover the complete health-parameter block.');
end

heatStateEnabled = isfield(engine, 'transientEffects') && ...
    isstruct(engine.transientEffects) && ...
    isfield(engine.transientEffects, 'enabled') && ...
    engine.transientEffects.enabled;
modelMode = 0;
if isfield(engine, 'modelMode') && ~isempty(engine.modelMode)
    modelMode = engine.modelMode;
end
if ~isscalar(modelMode) || ~isfinite(modelMode) || ~ismember(modelMode, [0, 1])
    error('sht:engine:modelMode', ...
        'engine.modelMode必须为0（三部件）或1（六部件）。');
end
parameterLayoutVersion = 0;
metalNodeCount = 0;
diskNodeCount = 0;
guideVaneNodeCount = 0;
heatComponentCount = 0;
temperatureStateCount = 0;
engineStateCount = 2;
validOutputIndex = [];
epsilonStepInIndex = [];
if heatStateEnabled
    if modelMode == 1
        parameterLayoutVersion = 2503;
        metalNodeCount = 19;
        diskNodeCount = 6;
        heatComponentCount = 7;
        epsilonStepInIndex = 488:493;
        thermalModelMode = round(engine.transientEffects.stepInTemplate(342));
        if thermalModelMode == 3
            guideVaneNodeCount = 2;
            validOutputIndex = 30;
        elseif thermalModelMode == 1
            validOutputIndex = 28;
        else
            error('sht:engine:thermalModelMode', ...
                '六部件热状态模式必须为1（Kurzke）或3（Visser）。');
        end
    else
        parameterLayoutVersion = 2502;
        metalNodeCount = 10;
        diskNodeCount = 3;
        heatComponentCount = 4;
        epsilonStepInIndex = 431:433;
        validOutputIndex = 16;
        if round(engine.transientEffects.stepInTemplate(342)) == 3
            guideVaneNodeCount = 1;
            validOutputIndex = 17;
        end
    end
    temperatureStateCount = metalNodeCount + diskNodeCount + ...
        guideVaneNodeCount;
    engineStateCount = 2 + temperatureStateCount;
end
if heatStateEnabled
    stepInValue = engine.transientEffects.stepInTemplate(:);
    if numel(stepInValue) >= 341 && abs(stepInValue(341) - 1) > 1e-6
        error('sht:engine:transientEffectsEnable', ...
            '启用增强瞬态效应时stepIn(341)必须为1。');
    end
    if numel(stepInValue) ~= stepInLength || ...
            numel(xEngine) ~= engineStateCount
        error('sht:engine:heatStateInterface', ...
            ['瞬态效应模式要求 512 维模板；参数布局 %d 应具有 %d 个' ...
             '发动机状态，当前为 %d。'], parameterLayoutVersion, ...
             engineStateCount, numel(xEngine));
    end
else
    stepInValue = zeros(stepInLength, 1);
    if numel(xEngine) ~= 2
        error('sht:engine:baselineStateSize', ...
            'Baseline engine mode requires xEngine=[Np;Ng].');
    end
end

% M 程序以 Mkp/Mkg 表示两个轴的外部负载扭矩；DLL 接口保持不变，
% 在每次求值前按当前 Np/Ng 生成对应负载功率。
boundary = sht_resolve_shaft_load_boundary(boundary, xEngine);
if isfield(boundary,'exhaustBackPressureModel') && ...
        ~isempty(boundary.exhaustBackPressureModel)
    if isfield(boundary,'Pback') && ~isempty(boundary.Pback)
        error('sht:engine:conflictingBackPressure', ...
            '不可同时提供模型背压配置与固定Pback输入。');
    end
    % 飞参模式5的静压字段为Ps0；不另行重建环境压力。
    if isfield(boundary,'Ps0')
        ambientPressure=boundary.Ps0;
    else
        ambientPressure=boundary.Pamb;
    end
    boundary.Pback=sht_exhaust_backpressure(ambientPressure, ...
        boundary.power,boundary.exhaustBackPressureModel);
end
exhaustBackPressure = 0;
if isfield(boundary,'Pback') && ~isempty(boundary.Pback)
    exhaustBackPressure = boundary.Pback;
    if ~isscalar(exhaustBackPressure) || ~isfinite(exhaustBackPressure) || ...
            exhaustBackPressure <= 0
        error('sht:engine:exhaustBackPressure', ...
            'boundary.Pback必须为有限正的绝对压力；缺省时应不设置该字段。');
    end
end
stepInValue(1:10) = [ ...
    xEngine(1), ...
    xEngine(2), ...
    wf, ...
    boundary.A8, ...
    0, ...
    boundary.power, ...
    boundary.hpsPower, ...
    0, ...
    boundary.hpcAlpha, ...
    exhaustBackPressure];

if heatStateEnabled
    % C 端只求导，不改写或积分金属温度和转盘温度状态。
    temperatureStartIndex = engine.transientEffects.temperatureStateStartIndex;
    stepInValue(temperatureStartIndex:temperatureStartIndex + ...
        temperatureStateCount - 1) = xEngine(3:engineStateCount);
    if isfield(engine.transientEffects, 'clearanceEnabled') && ...
            engine.transientEffects.clearanceEnabled
        % 直接调用本函数时允许按当前点查询；闭环积分器会显式传入步内保持值。
        if (~isfield(boundary, 'epsilonSSHeld') || isempty(boundary.epsilonSSHeld)) && ...
                isfield(engine.transientEffects, 'clearanceReferenceTable') && ...
                isfield(boundary, 'power')
            boundary.epsilonSSHeld = sht_lookup_clearance_reference( ...
                engine.transientEffects.clearanceReferenceTable, ...
                xEngine(1), xEngine(2), boundary.power, ...
                local_clearance_inlet_temperature( ...
                boundary, engine.transientEffects.clearanceReferenceTable));
        end
        if ~isfield(boundary, 'epsilonSSHeld') || ...
                numel(boundary.epsilonSSHeld) ~= diskNodeCount || ...
                any(~isfinite(boundary.epsilonSSHeld(:))) || ...
                any(boundary.epsilonSSHeld(:) <= 0)
            error('sht:engine:clearanceReference', ...
                '间隙模型需要 %d 个有限正值 epsilon_ss。', diskNodeCount);
        end
        stepInValue(epsilonStepInIndex) = boundary.epsilonSSHeld(:);
    end
end

% 进口边界的四种模式统一由一个显式字典写入。特别注意：Pt2 是 Inlet
% 的模型输出，任何模式都不会把测量 Pt2 写入 Pt1 输入槽位。
[stepInValue, inletBoundaryDetail] = ...
    sht_apply_inlet_boundary_stepin(stepInValue, boundary);

health = zeros(healthLength, 1);
if isfield(boundary, 'health') && ~isempty(boundary.health)
    n = min(numel(boundary.health), healthLength);
    health(1:n) = boundary.health(1:n);
end
stepInValue(healthStartIndex:healthEndIndex) = health;
scheduleEnabled = false;
if isfield(boundary, 'healthScheduleEnabled') && ...
        ~isempty(boundary.healthScheduleEnabled)
    scheduleEnabled = boundary.healthScheduleEnabled;
end
if ~isscalar(scheduleEnabled) || ...
        ~(islogical(scheduleEnabled) || isnumeric(scheduleEnabled)) || ...
        ~isfinite(double(scheduleEnabled)) || ...
        ~ismember(double(scheduleEnabled), [0, 1])
    error('sht:engine:healthScheduleEnable', ...
        'boundary.healthScheduleEnabled必须为逻辑量或数值0/1。');
end
stepInValue(healthScheduleEnableIndex) = double(logical(scheduleEnabled));

% 正常仿真路径复用 sht_engine_open 创建的三个库对象，仅更新本次输入值。
% C 端 DLL_SHT_RunOneStep 入口会首先清零 stepOut，因此这里无需在每次
% 调用前重新分配或清零输出指针。保留旧式即时构造分支，兼容少量由历史
% 测试程序手工构造、尚未携带 callContext 的 engine 结构。
if isfield(engine, 'callContext') && ...
        isstruct(engine.callContext) && ...
        all(isfield(engine.callContext, {'stepIn','stepOut','engPtr'}))
    stepIn = engine.callContext.stepIn;
    stepOut = engine.callContext.stepOut;
    engPtr = engine.callContext.engPtr;
    stepIn.Value = stepInValue;
else
    engPtrInit.eng = libstruct(engine.engineStructName);
    engPtr = libstruct(engine.enginePointerName, engPtrInit);
    stepIn = libpointer('doublePtr', stepInValue);
    stepOut = libpointer('doublePtr', zeros(stepOutLength, 1));
end

[ret, ~, stepOutValue, engOut] = calllib( ...
    engine.libraryName, 'DLL_SHT_RunOneStep', stepIn, stepOut, engPtr);

% 非零ret表示DLL已拒绝本次求值，输出可能已清零或仍含上次状态。
% 必须先报告原始错误，不能再用这些值映射测量量或计算RNI诊断。
% ret=0但convergeTag非零仍沿用下游原有的共同工作收敛/重试处理。
if ret ~= 0
    local_report_dll_failure(ret, engOut, modelMode, ...
        healthStartIndex, healthLength);
end

if heatStateEnabled
    xDot = stepOutValue(1:engineStateCount);
else
    xDot = stepOutValue(1:2);
end
% 负载机械断开时，外部折算惯量不再挂在PT轴上。本因子只改变
% 轴加速度，不修改稳态气路、健康系数或正式MDL中的接合状态惯量。
if isfield(boundary,'ptShaftInertiaFactor')
    factor=boundary.ptShaftInertiaFactor;
    assert(isscalar(factor)&&isfinite(factor)&&factor>0, ...
        'sht:engine:inertiaFactor','PT轴相对惯量必须为正有限值。');
    xDot(1)=xDot(1)/factor;
end
y = local_map_engine_output(engOut.eng, boundary, modelMode,engine);
% 飞行环境模式不向DLL传入Tt1；参考间隙查询需要的温度仅作M侧辅助量。
% 复用既有任务边界诊断值，并逐次与C的实际总温核对，避免静默双模型。
% 已有任务诊断为常比热近似，C采用变比热；本任务最大差约0.0024 K。
% 0.02 K仅限制该辅助坐标误差，不放宽气路求解精度，也不替代C总温。
if isfield(boundary,'clearanceInletTotalTemperature_K')
    referenceTt1=boundary.clearanceInletTotalTemperature_K;
    if ~isscalar(referenceTt1) || ~isfinite(referenceTt1) || referenceTt1<=0 || ...
            abs(referenceTt1-y.Tt1)>0.02
        error('sht:engine:clearanceTemperatureMismatch', ...
            '间隙查询入口总温%.12g K与C计算的Tt1 %.12g K不一致。',referenceTt1,y.Tt1);
    end
end
diagInfo = struct();
diagInfo.ret = ret;
diagInfo.convergeTag = engOut.eng.convergeTag;
diagInfo.maxErr = y.maxErr;
diagInfo.inletBoundary = inletBoundaryDetail;
% 保留原始结构体节点值供接口验收，正式输出Pt2必须与该值逐位一致。
diagInfo.rawInletPt2 = double(engOut.eng.Inlet.gasPathOut(4));
diagInfo.rawAmbientPt1 = double(engOut.eng.Ambient.gasPathOut(4));
if heatStateEnabled
    % 热模型诊断只在显式启用时出现，保证默认 finalState 结构与 P2 完全一致。
    % 驱动气体温度和热状态参数无论反馈开关是否开启都由 C 端热模型计算。
    % 将其显式返回，供 2.6 初始稳态热状态构造使用，避免在 M 端重复实现
    % 部件节点与气路温度之间的映射关系。
    heatEvaluation = engOut.eng.transientHeatEvaluation;
    diagInfo.heatStateEnabled = true;
    diagInfo.thermalModelMode = round( ...
        engine.transientEffects.stepInTemplate(342));
    diagInfo.evaluationValid = stepOutValue(validOutputIndex);
    diagInfo.temperatureStateDerivative = xDot(3:end);
    diagInfo.heatDrivingTemperature_K = ...
        double(heatEvaluation.gasTemperature(1:metalNodeCount));
    diagInfo.heatTimeConstant_s = ...
        double(heatEvaluation.timeConstant(1:metalNodeCount));
    diagInfo.diskTimeConstant_s = ...
        double(heatEvaluation.diskTimeConstant(1:diskNodeCount));
    if diagInfo.thermalModelMode == 3
        diagInfo.guideVaneTemperatureDerivative_Kps = ...
            double(heatEvaluation.guideVaneTemperatureDerivative(1:guideVaneNodeCount));
        diagInfo.guideVaneDrivingTemperature_K = ...
            double(heatEvaluation.visserGuideVaneGasTemperature(1:guideVaneNodeCount));
        diagInfo.guideVaneMainGasHeatFlow_W = ...
            double(heatEvaluation.visserGuideVaneHeatFlow(1:guideVaneNodeCount));
        diagInfo.visserMainGasHeatFlow_W = ...
            double(heatEvaluation.visserMainGasHeatFlow(1:heatComponentCount));
        diagInfo.visserMainGasFrontHeatFlow_W = ...
            double(heatEvaluation.visserMainGasFrontHeatFlow(1:heatComponentCount));
        diagInfo.visserMainGasRearHeatFlow_W = ...
            double(heatEvaluation.visserMainGasRearHeatFlow(1:heatComponentCount));
        diagInfo.visserMetalCoolingHeatFlow_W = ...
            double(heatEvaluation.visserMetalCoolingHeatFlow(1:metalNodeCount+guideVaneNodeCount));
        diagInfo.visserDiskCoolingHeatFlow_W = ...
            double(heatEvaluation.visserDiskCoolingHeatFlow(1:diskNodeCount));
        diagInfo.visserRootDiskHeatFlow_W = ...
            double(heatEvaluation.visserRootDiskHeatFlow(1:diskNodeCount));
        diagInfo.visserCoolingBranchHeatFlow_W = ...
            double(heatEvaluation.visserCoolingBranchHeatFlow(1:19));
        diagInfo.visserCoolingInletTemperature_K = ...
            double(heatEvaluation.visserCoolingInletTemperature(1:10));
        diagInfo.visserCoolingOutletTemperature_K = ...
            double(heatEvaluation.visserCoolingOutletTemperature(1:10));
        diagInfo.visserEnergyResidual_W = ...
            double(heatEvaluation.visserEnergyResidual);
        diagInfo.visserNormalizedEnergyResidual = ...
            double(heatEvaluation.visserNormalizedEnergyResidual);
    end
    % 组件归一化流量指标由 C 端使用实际局部气路状态计算。参数资产
    % 初始化程序通过该诊断反求各组件参考流量，从而不在 MATLAB 中
    % 重复实现冷却气掺混及分级流量路由。
    diagInfo.componentRNIStar = ...
        double(heatEvaluation.componentRNIStar(1:heatComponentCount));
    if modelMode == 1
        diagInfo.componentPower_W = abs([ ...
            double(engOut.eng.HPC.y(24)); ...
            double(engOut.eng.HPC2.y(24)); ...
            double(engOut.eng.fuelFlow * engOut.eng.Burner.burnStruct.LHV * ...
                engOut.eng.Burner.burnStruct.Eff); ...
            double(engOut.eng.HPT.y(19)); ...
            double(engOut.eng.HPT2.y(19)); ...
            double(engOut.eng.LPT.y(19)); ...
            double(engOut.eng.LPT2.y(19))]);
        % 与C端SHT_EvaluateClearanceStates调用时的六个轴系设计转速一致。
        % CompressorStruct不保存机械NDes，因此AC/CC从同轴HPT读取38000 rpm；
        % 这只是轴系基准来源，不表示用涡轮特性参数替代压气机特性参数。
        diagInfo.clearanceDesignSpeed_rpm = [ ...
            double(engOut.eng.HPT.turbineStruct.NDes); ...
            double(engOut.eng.HPT.turbineStruct.NDes); ...
            double(engOut.eng.HPT.turbineStruct.NDes); ...
            double(engOut.eng.HPT2.turbineStruct.NDes); ...
            double(engOut.eng.LPT.turbineStruct.NDes); ...
            double(engOut.eng.LPT2.turbineStruct.NDes)];
    else
        diagInfo.componentPower_W = abs([ ...
            double(engOut.eng.HPC.y(24)); ...
            double(engOut.eng.fuelFlow * engOut.eng.Burner.burnStruct.LHV * ...
                engOut.eng.Burner.burnStruct.Eff); ...
            double(engOut.eng.HPT.y(19)); ...
            double(engOut.eng.LPT.y(19))]);
        diagInfo.clearanceDesignSpeed_rpm = [ ...
            double(engOut.eng.HPT.turbineStruct.NDes); ...
            double(engOut.eng.HPT.turbineStruct.NDes); ...
            double(engOut.eng.LPT.turbineStruct.NDes)];
    end
    if isfield(engine.transientEffects, 'heatFeedbackEnabled') && ...
            engine.transientEffects.heatFeedbackEnabled
        thermalDiagnostics = engOut.eng.transientDiagnostics;
        diagInfo.heatFeedbackEnabled = true;
        diagInfo.heatFeedbackComponentMask = ...
            engine.transientEffects.componentMask;
        diagInfo.heatFeedbackApplied = ...
            double(thermalDiagnostics.heatFeedbackApplied(1: ...
            heatComponentCount));
        diagInfo.heatFeedbackConverged = ...
            double(thermalDiagnostics.heatFeedbackConverged(1: ...
            heatComponentCount));
        diagInfo.heatFeedbackIterationCount = ...
            double(thermalDiagnostics.heatFeedbackIterationCount(1: ...
            heatComponentCount));
        diagInfo.heatFeedbackIterationResidual_K = ...
            double(thermalDiagnostics.heatFeedbackIterationResidual(1: ...
            heatComponentCount));
        diagInfo.heatFeedbackEnergyResidual_W = ...
            double(thermalDiagnostics.heatFeedbackEnergyResidual(1: ...
            heatComponentCount));
        diagInfo.componentHeatFlow_W = ...
            double(heatEvaluation.componentHeatFlow(1: ...
            heatComponentCount));
    end
    if isfield(engine.transientEffects, 'clearanceEnabled') && ...
            engine.transientEffects.clearanceEnabled
        clearanceEvaluation = engOut.eng.transientClearanceEvaluation;
        diagInfo.clearanceEnabled = true;
        diagInfo.clearanceFeedbackEnabled = ...
            engine.transientEffects.clearanceFeedbackEnabled;
        diagInfo.clearanceActual = ...
            double(clearanceEvaluation.actualClearance(1:diskNodeCount));
        diagInfo.clearanceSteady = ...
            double(clearanceEvaluation.steadyClearance(1:diskNodeCount));
        diagInfo.clearanceDynamic = ...
            double(clearanceEvaluation.dynamicClearance(1:diskNodeCount));
        diagInfo.clearanceNormalizedSpeed = ...
            double(clearanceEvaluation.normalizedSpeed(1:diskNodeCount));
        diagInfo.clearanceFlowMultiplier = ...
            double(clearanceEvaluation.flowMultiplier(1:diskNodeCount));
        diagInfo.clearanceEfficiencyMultiplier = ...
            double(clearanceEvaluation.efficiencyMultiplier(1:diskNodeCount));
        diagInfo.clearanceSurgeMarginMultiplier = ...
            double(clearanceEvaluation.surgeMarginMultiplier(1: ...
            min(2, diskNodeCount)));
        diagInfo.clearanceFeedbackApplied = ...
            double(clearanceEvaluation.feedbackApplied(1:diskNodeCount));
    end
end
end

function local_report_dll_failure(ret, engOut, modelMode, healthStart, healthLength)
% 原始返回码是首要依据。诊断缺失或解包失败时，也不能丢失这个错误码。
diagnosticCode = NaN;
index = NaN;
value = NaN;
try
    diagnostics = engOut.eng.transientDiagnostics;
    diagnosticCode = double(diagnostics.errorCode);
    index = double(diagnostics.offendingStepInIndex);
    value = double(diagnostics.offendingValue);
catch
    % 旧DLL/异常桥接结果可能没有可读诊断；下面仍原样报告ret。
end
location = 'DLL未提供可确认的输入位置';
if isequal(diagnosticCode, double(ret)) && isscalar(index) && isfinite(index)
    if index >= 0 && index == fix(index)
        location = sprintf('C stepIn[%d] / MATLAB stepIn(%d)', index, index + 1);
        healthIndex = index - (healthStart - 1);
        if healthIndex >= 0 && healthIndex < healthLength
            location = sprintf('%s，健康参数h%d', location, healthIndex);
        end
    elseif index < 0
        % 负值是C端内部/派生量标记，不是可以加1换算的MATLAB数组下标。
        location = sprintf('C内部/派生量位置标记%d（非stepIn数组下标）', index);
    end
end
description = '请按所用DLL的错误码定义检查输入或物理求值';
if ret == 2501008
    description = '参数或参数派生量无效；不能仅凭此错误码认定为引气问题';
elseif ret == 2501007
    description = '动态状态值无效';
end
error('sht:engine:dllEvaluationFailed', ...
    ['DLL_SHT_RunOneStep拒绝本次求值：ret=%.17g，errorCode=%.17g，modelMode=%d。' ...
     '%s；C报告值=%.17g（可能为派生量），原始位置标记=%g。%s。' ...
     '已停止输出映射及Reynolds诊断；本次清零或残留输出不可使用。'], ...
    ret, diagnosticCode, modelMode, location, value, index, description);
end

function inletTtK = local_clearance_inlet_temperature(boundary, referenceTable)
% 直接调用发动机导数包装器时，与闭环积分器使用同一入口总温来源规则。
if isfield(boundary,'clearanceInletTotalTemperature_K')
    inletTtK=boundary.clearanceInletTotalTemperature_K;
    assert(isscalar(inletTtK)&&isfinite(inletTtK)&&inletTtK>0, ...
        '间隙查询入口总温必须为正的有限标量。');
elseif isfield(boundary, 'Tt1') && isscalar(boundary.Tt1) && ...
        isfinite(boundary.Tt1) && boundary.Tt1 > 0
    inletTtK = boundary.Tt1;
elseif isfield(referenceTable, 'defaultInletTotalTemperature_K') && ...
        isscalar(referenceTable.defaultInletTotalTemperature_K) && ...
        isfinite(referenceTable.defaultInletTotalTemperature_K) && ...
        referenceTable.defaultInletTotalTemperature_K > 0
    inletTtK = referenceTable.defaultInletTotalTemperature_K;
else
    error('sht:engine:clearanceInletTemperature', ...
        '修正转速调度需要当前 Tt1 或参考表默认入口总温。');
end
end

function y = local_map_engine_output(eng, boundary, modelMode,engine)
%LOCAL_MAP_ENGINE_OUTPUT Map GTESS EngineTurboshaft struct to named signals.
% 将 DLL 返回的 EngineTurboshaft 结构映射为 m 程序统一信号名。
%
% 字段顺序与 SFunc_EngModel.Derivatives 中写入 DWork(1:20) 的逻辑一致，
% 同时补充 FAR、T4、convergeTag 等诊断量。

% maxErr 汇总 C 程序非线性方程残差和喷管残差，是判断单步求解质量的主要诊断量。
errs = abs([eng.errOut, eng.Nozzle.y(end)]);

% 六部件模式下，3、45和5截面分别位于CC、GT2和PT2出口。控制器
% 保护量和记录量必须读取末级出口，不能沿用结构体中第一级的历史名称。
if modelMode == 1
    hpcOutlet = eng.HPC2;
    gtOutlet = eng.HPT2;
    ptOutlet = eng.LPT2;
else
    hpcOutlet = eng.HPC;
    gtOutlet = eng.HPT;
    ptOutlet = eng.LPT;
end

y = struct();
y.Pt1 = eng.Ambient.gasPathOut(4);
y.Tt1 = eng.Ambient.gasPathOut(3);
y.Pt2 = eng.Inlet.gasPathOut(4);
y.Tt2 = eng.Inlet.gasPathOut(3);
y.Pamb = eng.Ambient.y(5);
y.Pback = y.Pamb;
if isfield(boundary,'Pback') && ~isempty(boundary.Pback)
    y.Pback = boundary.Pback;
end
y.Tamb = eng.Ambient.y(6);
y.Altitude = eng.altitude;
y.Mach = eng.machNumber;
% Inlet 出口与 HPC/AC 入口是同一气路节点。WIn 是测量偏置流量漂移模型
% 使用的无测量误差驱动量，因此稳态试车、过渡态试车和飞行任务均显式
% 返回；它只用于测量误差生成和诊断，不作为被测传感器反馈量。
y.WIn = eng.Inlet.gasPathOut(1);
y.Pt3 = hpcOutlet.y(4);
y.Tt3 = hpcOutlet.y(3);
y.Pt45 = gtOutlet.y(4);
y.Tt45 = gtOutlet.y(3);
y.Pt5 = ptOutlet.y(4);
y.Tt5 = ptOutlet.y(3);
y.Np = eng.LPS_Nmech;
y.Ng = eng.HPS_Nmech;
if modelMode == 1
    y.HpcStallMargin = min(eng.HPC.y(8), eng.HPC2.y(8));
else
y.HpcStallMargin = eng.HPC.y(8);
end
% Mkp/Mkg 是外部可测负载边界的镜像，不再取自 DLL 内部扭矩结果。
y.Mkp = boundary.Mkp;
y.Mkg = boundary.Mkg;
y.PTLoadPower = boundary.power;
y.GTAccessoryPower = boundary.hpsPower;
% 保留 DLL 原扭矩量作为内部动力学诊断，避免继续混用 Mkp/Mkg 名称。
y.PTDriveTorque = eng.LPS_Trq;
y.GTInternalNetTorque = eng.HPS_Trq;
% Compressor_TMATS_body 的 u(6) 是机械转速，而 y(14) 才是按部件入口
% 总温修正后的 Nc。保留 NgcRaw 字段名兼容既有程序，但纠正其物理含义。
y.NgcRaw = eng.HPC.y(14);
% 三个 Ncr 均为各部件特性图实际使用的归一化修正转速坐标。
% HPC 与 GT 虽在同一高压轴上，但入口总温不同，必须分别读取部件输出，
% 不能用同一个绝对 Ng 或控制器使用的 Ngc 代替。
y.HPC_Ncr = eng.HPC.y(16);
y.GT_Ncr = eng.HPT.y(15);
y.PT_Ncr = eng.LPT.y(15);
y.HptBeta = gtOutlet.y(16);
y.LptBeta = ptOutlet.y(16);
if modelMode == 1
    y.CC_Ncr = eng.HPC2.y(16);
    y.GT2_Ncr = eng.HPT2.y(15);
    y.PT2_Ncr = eng.LPT2.y(15);
end
if isfield(engine,'reynoldsCorrectionInitialization')
    % 涡轮特性图入口采用前端冷却气掺混后的 Tts1/Pts1，分别位于
    % Turbine.y 的 MATLAB 下标 22/23；这与 C 端 RNI 修正口径一致。
    count=3+3*double(modelMode==1);
    state = repmat(struct('totalTemperature_K',NaN, ...
        'totalPressure_Pa',NaN),count,1);
    % gasPathIn在C结构中是指针，MATLAB libstruct不能稳定索引其后续
    % 元素；改读严格同节点的上游固定数组gasPathOut。
    state(1).totalTemperature_K = eng.Inlet.gasPathOut(3);
    state(1).totalPressure_Pa = eng.Inlet.gasPathOut(4);
    firstTurbine=2;turbine={eng.HPT,eng.LPT};
    if modelMode==1
        state(2).totalTemperature_K = eng.HPC.y(3);
        state(2).totalPressure_Pa = eng.HPC.y(4);
        firstTurbine=3;turbine={eng.HPT,eng.HPT2,eng.LPT,eng.LPT2};
    end
    for reynoldsIndex = 1:numel(turbine)
        state(reynoldsIndex+firstTurbine-1).totalTemperature_K = ...
            turbine{reynoldsIndex}.y(22);
        state(reynoldsIndex+firstTurbine-1).totalPressure_Pa = ...
            turbine{reynoldsIndex}.y(23);
    end
    reynolds = sht_reynolds_correction_evaluate( ...
        engine.reynoldsCorrectionInitialization.configuration,state);
    y.reynoldsComponentName = reynolds.name;
    y.reynoldsIndex = reynolds.reynoldsIndex;
    y.reynoldsFlowMultiplier = reynolds.flowMultiplier;
    y.reynoldsEfficiencyMultiplier = reynolds.efficiencyMultiplier;
    y.reynoldsClampedLow = reynolds.clampedLow;
end
% 健康参数调度必须查询当前候选模型在当前积分状态下的物理坐标。
% 将 C 端实际工作点显式返回，2.7 小幅历程回放据此统计每段历程对
% 各调度节点的访问权重；禁止用测量转速预先计算并冻结横坐标。
y.inlet_corrected_mass_flow = local_corrected_flow(eng.Ambient.gasPathOut);
y.burner_inlet_corrected_mass_flow = local_corrected_flow(hpcOutlet.y);
y.gt_pt_duct_corrected_mass_flow = local_corrected_flow(gtOutlet.y);
y.pt_nozzle_duct_corrected_mass_flow = local_corrected_flow(ptOutlet.y);
y.ac_corrected_speed = eng.HPC.y(16);
varIte = double(eng.varIte(:));
if modelMode == 0
    % 整体GT/PT的物理压比就是三部件共同工作变量3/4，不能乘以轴速。
    y.gt_total_pressure_ratio = varIte(3);
    y.pt_total_pressure_ratio = varIte(4);
elseif numel(varIte) >= 7
    y.gt_total_pressure_ratio = varIte(4) * varIte(5);
    y.pt_total_pressure_ratio = varIte(6) * varIte(7);
else
    y.gt_total_pressure_ratio = NaN;
    y.pt_total_pressure_ratio = NaN;
end
y.timeNow = eng.timeNow;
y.maxErr = max(errs);
y.BurnerPtOut = eng.Burner.y(4);
% C 端 Burner_TMATS_body.c 中 y[4] 是 FARcOut；MATLAB 下标对应 y(5)。
% 这里的 FAR 是燃烧室出口燃空比，用于减速贫油/熄火边界估算。
y.FAR = eng.Burner.y(5);
y.T4 = eng.Burner.y(3);
y.convergeTag = eng.convergeTag;
end

function correctedFlow = local_corrected_flow(gasPath)
% 与稳态辨识公共内核保持同一换算流量定义。
gasPath = double(gasPath(:));
correctedFlow = gasPath(1) * sqrt(gasPath(3) / 288.15) * ...
    101325 / gasPath(4);
end
