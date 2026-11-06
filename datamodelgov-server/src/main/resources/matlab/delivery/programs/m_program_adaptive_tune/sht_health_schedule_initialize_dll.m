function info = sht_health_schedule_initialize_dll(engine, profile, designVector)
%SHT_HEALTH_SCHEDULE_INITIALIZE_DLL 将模式相关一维健康调度表写入DLL。
%
% stepIn中的h0:h158仍是设计点值k_design。本函数按模型模式初始化
% 三部件13项或六部件31项Delta(x)的横坐标和增量节点；DLL在每次
% 局部部件求值时计算
% K_eff=k_design+Delta(x)。调度开关由每次模型调用的stepIn(18)给出，
% 本函数不保留跨调用的运行开关状态。初始化失败会立即复位DLL调度
% 系统，避免留下部分表已配置、部分表未配置的不完整状态。
%
% 可选designVector只用于设定初始化时压损表的
% Delta_0=-k_design。参数辨识回放时不需要重新写入整张表：DLL在
% 每次读取stepIn设计点值后，都会再次令四项压损表满足
% Delta_0=-k_design，因而K_eff(0)=0始终成立。其余Delta节点由
% profile显式给出。
assert(isstruct(engine) && isfield(engine, 'libraryName') && ...
    libisloaded(engine.libraryName), '发动机DLL尚未打开。');
assert(isfield(engine, 'modelMode') && ismember(engine.modelMode, [0, 1]), ...
    '发动机必须明确处于三部件modelMode=0或六部件modelMode=1。');
assert(isstruct(profile) && isfield(profile, 'parameters') && ...
    isfield(profile, 'scheduledCIndex') && isfield(profile, 'modelMode'), ...
    'profile不是有效健康调度资产。');
assert(profile.modelMode == engine.modelMode, ...
    '调度资产modelMode=%d与当前DLL modelMode=%d不一致。', ...
    profile.modelMode, engine.modelMode);
expectedCount = local_expected_table_count(engine.modelMode);
if nargin < 3 || isempty(designVector)
    designVector = profile.truthVectorAtDesign;
end
designVector = double(designVector(:));
assert(numel(designVector) == numel(profile.truthVectorAtDesign) && ...
    all(isfinite(designVector)), ...
    'designVector必须是与健康参数字典等长的有限列向量。');

libraryName = engine.libraryName;
status = calllib(libraryName, 'DLL_SHT_HealthScheduleReset');
assert(status == 0, 'DLL健康调度复位失败，状态码=%d。', status);

scheduled = ~strcmp({profile.parameters.mode}, 'constant');
parameters = profile.parameters(scheduled);
try
    for i = 1:numel(parameters)
        parameter = parameters(i);
        axisType = local_axis_type(parameter.axisName);
        xNode = double(parameter.xNodes(:));
        deltaNode = double(parameter.deltaNodes(:));
        local_validate_nodes(parameter, axisType, xNode, deltaNode);
        if parameter.zeroFlowAnchored
            deltaNode(1) = -designVector(parameter.matlabHealthIndex);
        end
        xPointer = libpointer('doublePtr', xNode);
        deltaPointer = libpointer('doublePtr', deltaNode);
        status = calllib(libraryName, ...
            'DLL_SHT_HealthScheduleConfigureTable', ...
            int32(parameter.cIndex), int32(axisType), ...
            int32(numel(xNode)), xPointer, deltaPointer);
        if status ~= 0
            error('SHT:HealthSchedule:DLLTableInitialization', ...
                'h%d %s调度表初始化失败，状态码=%d。', ...
                parameter.cIndex, parameter.name, status);
        end
    end

    configuredCount = calllib(libraryName, ...
        'DLL_SHT_HealthScheduleGetConfiguredCount');
    assert(configuredCount == numel(parameters) && ...
        configuredCount == expectedCount, ...
        'DLL调度表数量为%d，modelMode=%d预期为%d。', ...
        configuredCount, engine.modelMode, expectedCount);
    % 初始化结束后保持常值语义。每次RunOnePoint/RunOneStep调用都会
    % 用stepIn(18)覆盖该内部状态，因此不会继承前一次模型调用的开关。
    status = calllib(libraryName, ...
        'DLL_SHT_HealthScheduleSetEnabled', int32(0));
    assert(status == 0, 'DLL健康调度初始化状态设置失败，状态码=%d。', status);
catch exception
    calllib(libraryName, 'DLL_SHT_HealthScheduleReset');
    rethrow(exception);
end

info = struct();
info.schemaVersion = 'SHT_HEALTH_SCHEDULE_DLL_INIT_V7_MODE_DEPENDENT';
info.modelMode = engine.modelMode;
info.expectedCount = expectedCount;
info.runtimeSwitchMatlabIndex = engine.healthScheduleEnableIndex;
info.runtimeSwitchCIndex = engine.healthScheduleEnableIndex - 1;
info.initialEnabledState = false;
info.configuredCount = configuredCount;
info.healthCIndex = [parameters.cIndex].';
info.axisType = arrayfun(@(p) local_axis_type(p.axisName), parameters).';
info.nodeCount = arrayfun(@(p) numel(p.xNodes), parameters).';
info.maximumNodeCount = 32;
info.designVector = designVector;
end

function local_validate_nodes(parameter, axisType, xNode, deltaNode)
maximumNodeCount = 32;
assert(~isempty(xNode) && numel(xNode) == numel(deltaNode) && ...
    all(isfinite(xNode)) && all(isfinite(deltaNode)) && ...
    all(diff(xNode) > 0), ...
    'h%d %s的节点必须等长、有限且横坐标严格递增。', ...
    parameter.cIndex, parameter.name);
if axisType <= 4
    assert(numel(xNode) >= 2 && numel(xNode) <= maximumNodeCount && ...
        xNode(1) == 0 && parameter.zeroFlowAnchored, ...
        'h%d %s压损调度必须含2~%d个节点且首节点为零流量。', ...
        parameter.cIndex, parameter.name, maximumNodeCount);
else
    assert(numel(xNode) >= 1 && numel(xNode) <= maximumNodeCount && ...
        ~parameter.zeroFlowAnchored, ...
        'h%d %s旋转部件调度必须含1~%d个节点。', ...
        parameter.cIndex, parameter.name, maximumNodeCount);
end
end

function axisType = local_axis_type(axisName)
names = { ...
    'inlet_corrected_mass_flow', ...
    'burner_inlet_corrected_mass_flow', ...
    'gt_pt_duct_corrected_mass_flow', ...
    'pt_nozzle_duct_corrected_mass_flow', ...
    'ac_corrected_speed', ...
    'cc_corrected_speed', ...
    'gt_total_pressure_ratio', ...
    'pt_total_pressure_ratio'};
axisType = find(strcmp(names, axisName), 1);
if isempty(axisType) && strcmp(axisName, 'hpc_corrected_speed')
    % C端轴类型5在三部件模式表示HPC，在六部件模式表示AC。
    axisType = 5;
end
assert(~isempty(axisType), '未知DLL健康调度坐标：%s。', axisName);
end

function count = local_expected_table_count(modelMode)
if modelMode == 0
    count = 13;
else
    count = 31;
end
end
