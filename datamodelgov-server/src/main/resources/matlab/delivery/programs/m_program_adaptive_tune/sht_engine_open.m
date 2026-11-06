function engine = sht_engine_open(engineCfg)
%SHT_ENGINE_OPEN 加载并初始化 GTESS 涡轴发动机 DLL。
% engineCfg 来自 cfg.engine，DLL 目录、库名、头文件和结构体名称均放在 cfg.engine.interface 中。

interface = engineCfg.interface;
oldDir = pwd;
cd(interface.controlDir);
restoreDirectory = onCleanup(@() cd(oldDir));

if libisloaded(interface.libraryName)
    try
        calllib(interface.libraryName, 'DLL_SHT_Free');
    catch
    end
    unloadlibrary(interface.libraryName);
end

loadDiagnostics = sht_load_engine_library( ...
    interface.libraryName, interface.headerName);
modelMode = 0;
if isfield(engineCfg, 'modelMode') && ~isempty(engineCfg.modelMode)
    modelMode = engineCfg.modelMode;
end
status = calllib(interface.libraryName, 'DLL_SHT_InitialMode', modelMode);
if status ~= 0
    local_cleanup_failed_open(interface.libraryName, {});
    error('sht:engine:modelInitialization', ...
        'DLL_SHT_InitialMode(%d)失败，状态码=%d。', modelMode, status);
end

% 标称热模型参数与当前DLL实例同寿命周期，只在发动机打开时
% 初始化一次。此时尚未进入ConditionsInit和任何部件求值，因而不会
% 留下部分运行状态。动态温度、epsilon_ss和个体修正量仍由
% sht_engine_derivative在每次调用时写入stepIn。
thermalConfigurationInitialization = [];
coolingSplitInitialization = [];
reynoldsCorrectionInitialization = [];
if isfield(engineCfg,'reynoldsCorrection') && ...
        ~isempty(engineCfg.reynoldsCorrection)
    try
        reynoldsCorrectionInitialization = ...
            sht_initialize_reynolds_correction_dll( ...
                interface,modelMode,engineCfg.reynoldsCorrection);
    catch reynoldsCorrectionError
        local_cleanup_failed_open(interface.libraryName, {});
        rethrow(reynoldsCorrectionError);
    end
end
if isfield(engineCfg,'transientEffects') && ...
        ~isempty(engineCfg.transientEffects) && ...
        isfield(engineCfg.transientEffects,'thermalModelConfiguration') && ...
        ~isempty(engineCfg.transientEffects.thermalModelConfiguration)
    try
        thermalConfigurationInitialization = ...
            sht_initialize_thermal_model_dll(interface,modelMode, ...
            engineCfg.transientEffects.thermalModelConfiguration);
    catch thermalConfigurationError
        local_cleanup_failed_open(interface.libraryName, {});
        rethrow(thermalConfigurationError);
    end
end

if isfield(engineCfg,'transientEffects') && ...
        ~isempty(engineCfg.transientEffects) && ...
        isfield(engineCfg.transientEffects,'coolingSplitConfiguration') && ...
        ~isempty(engineCfg.transientEffects.coolingSplitConfiguration)
    try
        coolingSplitInitialization = sht_initialize_cooling_split_dll( ...
            interface,modelMode, ...
            engineCfg.transientEffects.coolingSplitConfiguration);
    catch coolingSplitError
        local_cleanup_failed_open(interface.libraryName, {});
        rethrow(coolingSplitError);
    end
end

engPtrInit.eng = libstruct(interface.engineStructName);
engPtr = libstruct(interface.enginePointerName, engPtrInit);
% engPtr 已经持有嵌套发动机结构。立即清除构造临时量，避免后续初始化
% 报错时该临时引用阻止 unloadlibrary；正常运行不再需要 engPtrInit。
clear engPtrInit;
stepInValue = zeros(interface.stepInLength, 1);
% 模式0的环境边界只在ConditionsInit读取。若调用方配置了非零高度、
% Mach或温差，必须在此处锁存；后续四个运行入口不再重复读取这些槽位。
inletMode = 0;
if isfield(engineCfg, 'boundary') && ...
        isfield(engineCfg.boundary, 'inletBoundaryMode') && ...
        ~isempty(engineCfg.boundary.inletBoundaryMode)
    inletMode = engineCfg.boundary.inletBoundaryMode;
end
if inletMode == 0 && isfield(engineCfg, 'boundary')
    stepInValue = sht_apply_inlet_boundary_stepin( ...
        stepInValue, engineCfg.boundary);
end
stepIn = libpointer('doublePtr', stepInValue);
stepOut = libpointer('doublePtr', zeros(interface.stepOutLength, 1));
try
    status = calllib(interface.libraryName, ...
        'DLL_SHT_ConditionsInit', stepIn, stepOut, engPtr);
    if status ~= 0
        error('sht:engine:conditionInitialization', ...
            'DLL_SHT_ConditionsInit失败，状态码=%d。', status);
    end
catch conditionInitializationError
    local_cleanup_failed_open(interface.libraryName, ...
        {engPtr, stepIn, stepOut});
    rethrow(conditionInitializationError);
end


engine = struct();
engine.libraryName = interface.libraryName;
engine.controlDir = interface.controlDir;
engine.engineStructName = interface.engineStructName;
engine.enginePointerName = interface.enginePointerName;
engine.stepInLength = interface.stepInLength;
engine.stepOutLength = interface.stepOutLength;
engine.healthLength = interface.healthLength;
engine.healthStartIndex = interface.healthStartIndex;
engine.healthScheduleEnableIndex = interface.healthScheduleEnableIndex;
engine.inletBoundaryModeIndex = interface.inletBoundaryModeIndex;
engine.modelMode = modelMode;
engine.loadLibraryDiagnostics = loadDiagnostics;
if ~isempty(thermalConfigurationInitialization)
    engine.thermalConfigurationInitialization = ...
        thermalConfigurationInitialization;
end
if ~isempty(coolingSplitInitialization)
    engine.coolingSplitInitialization = coolingSplitInitialization;
end
if ~isempty(reynoldsCorrectionInitialization)
    engine.reynoldsCorrectionInitialization = ...
        reynoldsCorrectionInitialization;
end
if isfield(engineCfg, 'modelConfiguration')
    engine.modelConfiguration = engineCfg.modelConfiguration;
else
    engine.modelConfiguration = '';
end

% 健康调度表是三部件/六部件模型的可选初始化资产。只有调用方
% 显式提供 healthScheduleProfile 时才写入DLL，因而未配置调度资产的
% 历史常值修正以及零修正程序运行路径不变。将这一步
% 放在统一发动机打开入口，可保证稳态配平和闭环时域仿真
% 每次重新加载DLL后都使用同一批调度表。
if isfield(engineCfg, 'healthScheduleProfile') && ...
        ~isempty(engineCfg.healthScheduleProfile)
    designVector = [];
    if isfield(engineCfg, 'boundary') && ...
            isfield(engineCfg.boundary, 'health') && ...
            ~isempty(engineCfg.boundary.health)
        designVector = engineCfg.boundary.health;
    end
    try
        engine.healthScheduleInitialization = ...
            sht_health_schedule_initialize_dll( ...
                engine, engineCfg.healthScheduleProfile, designVector);
    catch scheduleError
        local_cleanup_failed_open(interface.libraryName, ...
            {engPtr, stepIn, stepOut});
        rethrow(scheduleError);
    end
end

% 一条仿真历程内会高频调用 DLL_SHT_RunOneStep。stepIn、stepOut 和
% EngineSHTPointer 均为 MATLAB 的句柄型库对象，可以在同一 DLL 生命周期
% 内安全复用。把 ConditionsInit 已经使用过的三个对象保存为运行时调用
% 上下文，避免每次求导重新构造嵌套 libstruct 和 libpointer。
%
% 上下文只属于当前 MATLAB 进程和当前 DLL 实例；sht_engine_close 会在
% unloadlibrary 前显式 delete 这些对象。不得跨进程、跨 DLL 重载复用。
engine.callContext = struct();
engine.callContext.schemaVersion = 'SHT_ENGINE_CALL_CONTEXT_V1';
engine.callContext.stepIn = stepIn;
engine.callContext.stepOut = stepOut;
engine.callContext.engPtr = engPtr;
% 调用方若已完成当前工况完整配平，显式沿用其共同工作初值。
% 仅给定Np/Ng/Wf并不能初始化DLL内部气路Newton猜值，低负载尤其敏感。
if isfield(engineCfg,'initial') && isfield(engineCfg.initial,'commonWorkingSeed')
    try
    seed=double(engineCfg.initial.commonWorkingSeed(:));
    count=6+3*double(modelMode==1);
    assert(numel(seed)==count && all(isfinite(seed)), ...
        'sht:engine:initialSeed','当前模式要求%d维有限共同工作初值。',count);
    values=zeros(interface.stepInLength,1);values(21:20+count)=seed;
    stepIn.Value=values;
    status=calllib(interface.libraryName,'DLL_SHT_varIteInit',stepIn,stepOut,engPtr);
    assert(status==0,'sht:engine:seedStatus','共同工作初值写入失败：%d。',status);
    catch seedError
        local_cleanup_failed_open(interface.libraryName,{stepIn,stepOut,engPtr});
        rethrow(seedError);
    end
end

% 仅在调用方显式配置 P3 时增加该字段；默认 engine 结构保持原样。
if isfield(engineCfg, 'transientEffects') && ~isempty(engineCfg.transientEffects)
    engine.transientEffects = engineCfg.transientEffects;
end
engine.isOpen = true;
clear restoreDirectory;
end

function local_cleanup_failed_open(libraryName, libraryObjects)
%LOCAL_CLEANUP_FAILED_OPEN 清理尚未成功返回的 DLL 初始化过程。
% 初始化异常时，调用方拿不到 engine，因而不能依赖 sht_engine_close。
% 必须在本函数内部按“C资源、MATLAB包装对象、动态库”的顺序完整回收，
% 同时避免清理错误覆盖真正的初始化错误。
if libisloaded(libraryName)
    try
        calllib(libraryName, 'DLL_SHT_Free');
    catch
    end
end

for i = 1:numel(libraryObjects)
    if isempty(libraryObjects{i})
        continue;
    end
    try
        delete(libraryObjects{i});
    catch
    end
end

if libisloaded(libraryName)
    try
        unloadlibrary(libraryName);
    catch cleanupError
        warning('sht:engine:failedOpenCleanup', ...
            'DLL初始化失败后的资源清理未完成：%s', cleanupError.message);
    end
end
end
