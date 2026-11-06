function result = Start_SteadyModelAdapt_V2_02_SteadyModelParameterEstimation(trainingDataFile)
%START_STEADYMODELADAPT_V2_02_STEADYMODELPARAMETERESTIMATION
% 第二轮六部件稳态修正系数估计入口一：稳态模型路径。
%
% 输入：真实可测稳态均值训练集Excel。trainingDataFile为空或省略时，
% 使用TestData目录下的默认训练集。参数辨识只读取训练集，测试集验证由
% Start_SteadyModelAdapt_V2_05_TestDataValidation独立执行。
% 模式4由DLL根据环境边界重构Pt1，以测量Pt2直接作为AC进口压力，
% 并按进口模型方程逐工况反算Inlet_K_dP。联合估计包含其余10个
% 发动机修正系数和1个燃油偏置；残差为Np、Ng、Pt3、Tt3、Tt45、Pt45。
%
% 本程序不读取瞬态时刻路径结果，也不读取隐藏真值。入口顶部配置只影响
% 本路径，修改后可独立重复运行。

if nargin < 1
    trainingDataFile = '';
end
if isstruct(trainingDataFile) && isfield(trainingDataFile,'modelMode') && trainingDataFile.modelMode==0
    result=Start_TC24_04_SteadyEstimation(trainingDataFile);
    return;
end
trainingDataFile = local_optional_file_name(trainingDataFile, ...
    'trainingDataFile');

options = sht_steady_model_adapt_v2_common('defaultOptions', 'steady');

% --------------------------- 入口配置 ---------------------------
options.clusterSpan = 0.020;       % AC相对换算转速最大组内跨度
options.maxIterationA = 24;        % 稳态模型A阶段无阻尼TSVD迭代上限
options.maxIterationGroup = 20;    % 单点欠定组可能需要更充分的阻尼收敛
options.maxIterationRefine = 10;   % D阶段非线性迭代上限；每轮均重新计算Jacobian
options.maxModelResidual = 1e-2;   % 候选工况共同工作最大残差门限
options.figureVisible = 'off';     % 改为'on'可在MATLAB中显示结果图
options.verbose = true;
options.inletBoundaryMode = 4;
options.includePt2Residual = false;
options.estimateInletPressureLoss = false;

% A阶段方法开关：'tsvd'或'tikhonov'。
% 默认使用无阻尼TSVD r=4：11个待估参数中保留4个奇异方向，等价于
% 严格截断7个方向；切换为Tikhonov时使用下方s=0.50。
options.stageARegularizationMethod = 'tsvd';
options.stageATikhonovPriorScale = 0.50;
options.stageATsvdTruncatedCount = 7;
options.stageATsvdRetainedCount = [];
options.stageATsvdStepMode = 'direct_inverse';
% B阶段方法开关：'tsvd'或'tikhonov'。
% 默认采用Tikhonov s=0.50；切换为无阻尼TSVD时保留r=5。
options.stageBRegularizationMethod = 'tikhonov';
options.stageBTikhonovPriorScale = 0.50;
options.stageBTsvdRetainedCount = 5;
% D阶段正式采用逐真实执行节点M3。稳态路径当前暂定lambda=0.05；
% 收敛只由最多10次参数更新和最终点新Jacobian一阶最优性审核判定。
% 候选集同时计算GCV推荐值，但不覆盖用户选择。完整解直接应用，
% 不使用LM阻尼、统一alpha或全局线搜索缩放。
options.constantJacobianMethod = 'strict_central';
options.stageDParameterization = 'actual_execution_nodes';
options.stageDJacobianMethod = 'node_central_full';
options.stageDRegularizationMethod = 'tikhonov';
options.stageDTikhonovPriorScale = 1.00;
options.stageDDifferenceStepScale = 0.5;
options.stageDInitialOffset = [];
options.stageDM3RegularizationStrength = 0.05;
options.stageDM3RegularizationCandidates = ...
    [0.05, 0.10, 0.20, 0.50, 1, 2, 5, 10];
options.stageAOnly = false;
options.evaluateSteadyTestFromTransient = false;
options.outputTag = 'm3';
% 每次正式运行自动生成不可变runId，避免换入新试车数据时
% 与历史运行冲突。稳态路径的唯一正式Excel交付物由公共程序原子替换。
options.runId = '';
% 达到10次上限时正常返回可诊断结果。收敛状态写入Manifest，
% 但不是Excel发布或下游读取门槛；结构完整且最终回放有效即可交付。
options.requireConvergedStages = false;
options.requireValidFinalReplay = true;
options.trainingFile = trainingDataFile;
options.evaluateTestSet = false;
options.testFile = '';
% ----------------------------------------------------------------

result = sht_steady_model_adapt_v2_common('run', 'steady', options);
estimatedParameterCount = height(result.parameterDefinition) + 1;
if estimatedParameterCount ~= 11
    error('SHT:SteadyAdaptV2Steady:BadParameterCount', ...
        ['正式稳态路径必须估计10个发动机修正参数和1个燃油偏置，' ...
         '当前结果为%d个参数。'], estimatedParameterCount);
end
% 公共内核已完成不可变MAT run、固定Excel读回和内部latest MAT发布。入口返回后
% 不得再次覆写MAT，否则会破坏工作簿与确定性合同的一致身份。
assignin('base', 'SteadyModelAdaptV2SteadyResult', result);
end

function value = local_optional_file_name(value, name)
value = string(value);
if ~isscalar(value)
    error('SHT:SteadyAdaptV2Steady:BadFileName', ...
        '%s必须是字符向量或字符串标量。', name);
end
value = char(value);
end
