function result = Start_SteadyModelAdapt_V2_03_TransientInstantEstimation(trainingDataFile)
%START_STEADYMODELADAPT_V2_03_TRANSIENTINSTANTESTIMATION
% 第二轮六部件稳态修正系数估计入口二：瞬态时刻模型路径。
%
% 输入：Np、Ng、修正后Wf、Mkp、Mkg、Pamb、Tamb、Mach、测量Tt1
% 和测量Pt2。模式4由DLL重构Pt1，以测量Pt2直接作为AC进口压力，
% 并按进口模型方程逐工况反算Inlet_K_dP。联合估计只包含其余10个
% 发动机修正系数和1个燃油偏置，残差为Pt3、Tt3、Tt45、Pt45、
% dNp/dt和dNg/dt；稳态窗口的两个轴加速度目标均为0。
% trainingDataFile为空或省略时使用TestData目录下的默认训练集。
% 参数辨识只读取训练集；测试集验证由独立交付入口执行。
%
% 本程序不读取稳态模型路径结果，也不读取隐藏真值。两条路径的参数、
% 分组、初值和结果文件全部独立。

if nargin < 1
    trainingDataFile = '';
end
if isstruct(trainingDataFile) && isfield(trainingDataFile,'modelMode') && trainingDataFile.modelMode==0
    result=Start_TC24_05_TransientInstantEstimation(trainingDataFile);
    return;
end
trainingDataFile = local_optional_file_name(trainingDataFile, ...
    'trainingDataFile');

options = sht_steady_model_adapt_v2_common( ...
    'defaultOptions', 'transient_instant');

% --------------------------- 入口配置 ---------------------------
options.clusterSpan = 0.020;
options.maxIterationA = 12;
options.maxIterationGroup = 4;
options.maxIterationRefine = 10; % D阶段非线性迭代上限；每轮均重新计算Jacobian
options.maxModelResidual = 1e-2;
options.figureVisible = 'off';
options.verbose = true;
options.inletBoundaryMode = 4;
options.includePt2Residual = false;
options.estimateInletPressureLoss = false;
% A阶段方法开关：'tsvd'或'tikhonov'。
% 默认使用无阻尼TSVD r=6，即11个参数中严格截断5个方向；切换为
% Tikhonov时使用下方s=1.00。
options.stageARegularizationMethod = 'tsvd';
options.stageATikhonovPriorScale = 1.00;
options.stageATsvdTruncatedCount = 5;
options.stageATsvdRetainedCount = [];
options.stageATsvdStepMode = 'direct_inverse';
% B阶段方法开关：'tsvd'或'tikhonov'。
% 默认采用Tikhonov s=0.75；切换为无阻尼TSVD时保留r=5。
options.stageBRegularizationMethod = 'tikhonov';
options.stageBTikhonovPriorScale = 0.75;
options.stageBTsvdRetainedCount = 5;
% D阶段正式采用逐真实执行节点M3。与稳态路径一致，用户确定
% 默认lambda=0.05；候选集同时计算GCV推荐值，但不覆盖用户选择。
% 完整解直接应用，不使用统一alpha或全局更新比例。收敛审核结果
% 作为诊断信息保留，不阻止结构完整的唯一Excel结果向下游交付。
options.constantJacobianMethod = 'strict_central';
options.stageDParameterization = 'actual_execution_nodes';
options.stageDJacobianMethod = 'node_central_full';
options.stageDRegularizationMethod = 'tikhonov';
options.stageDTikhonovPriorScale = 1.0;
options.stageDDifferenceStepScale = 0.5;
options.stageDInitialOffset = [];
options.stageDM3RegularizationStrength = 0.05;
options.stageDM3RegularizationCandidates = ...
    [0.05, 0.10, 0.20, 0.50, 1, 2, 5, 10];
options.stageAOnly = false;         % 运行阶段A、B、C和D完整辨识流程
options.evaluateSteadyTestFromTransient = false;
% M3使用独立、不可变身份，不覆盖冻结旧路线的无后缀latest文件。
options.outputTag = 'm3';
% 每次正式运行自动生成不可变runId；瞬态时刻路径的唯一正式
% Excel交付物由公共程序原子替换。
options.runId = '';
% 达到10次上限时正常返回可诊断结果。收敛状态写入Manifest，
% 但不是Excel发布或下游读取门槛；结构完整且最终回放有效即可交付。
options.requireConvergedStages = false;
options.requireValidFinalReplay = true;
options.trainingFile = trainingDataFile;
options.evaluateTestSet = false;
options.testFile = '';
% ----------------------------------------------------------------

result = sht_steady_model_adapt_v2_common( ...
    'run', 'transient_instant', options);
estimatedParameterCount = height(result.parameterDefinition) + 1;
if estimatedParameterCount ~= 11
    error('SHT:SteadyAdaptV2Transient:BadParameterCount', ...
        ['正式瞬态路径必须估计10个发动机修正参数和1个燃油偏置，' ...
         '当前结果为%d个参数。'], estimatedParameterCount);
end
% 公共内核已完成不可变MAT run、固定Excel读回和内部latest MAT发布。入口返回后
% 不得再次覆写MAT，否则会破坏工作簿与确定性合同的一致身份。
assignin('base', 'SteadyModelAdaptV2TransientInstantResult', result);
end

function value = local_optional_file_name(value, name)
value = string(value);
if ~isscalar(value)
    error('SHT:SteadyAdaptV2Transient:BadFileName', ...
        '%s必须是字符向量或字符串标量。', name);
end
value = char(value);
end
