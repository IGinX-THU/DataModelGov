function result = Start_HealthParameterDesign_01_SixComponentTruthSchedule(publish)
%START_HEALTHPARAMETERDESIGN_01_SIXCOMPONENTTRUTHSCHEDULE
% 设计并验收六部件稳态试车替代数据使用的修正系数真值与调度函数。
%
% 本入口完成四项工作：
%   1) 读取已确认的固定工程参考节点，保持现行合成试车真值不变；
%   2) 构造64项稳态修正参数，其中31项具有一维查表调度能力；
%   3) 校核曲线/非单调形状、换算流量坐标、端点截断和引气正性；
%   4) 保存下游MAT数据，并把表格、图和说明写到外层report_outputs。
%
% 本程序只负责形成和离线验收真值资产；运行前由
% sht_health_schedule_initialize_dll把31张增量表一次写入DLL，stepIn继续
% 传递设计点值，DLL按实时局部状态计算K_eff=k_design+Delta(x)。
% publish=false仅返回候选结果，不写MAT/图表、不替换现行真值。

if nargin < 1
    publish = true;
end
validateattributes(publish, {'logical'}, {'scalar'});

thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir);

% 真值曲线是模拟未知个体的工程设定，不必随当前零修正模型重新配平。
% 固定参考值在独立M配置中可重建，不依赖已生成试车MAT或辨识结果。
[anchor, operatingPointTable] = sht_bench_truth_schedule_reference();
baselineFile = anchor.baselineFile;
profile = sht_health_schedule_profile(anchor);

profile.baselineDataFile = baselineFile;
profile.anchorOperatingPoints = operatingPointTable;
profile.baselineBleedFraction = anchor.designBleedFractionAcIn(:);
profile.correctedBleedFractionAtDesign = profile.baselineBleedFraction + ...
    profile.bleedFlowFractionDesign(:);

bleedComparison = local_bleed_comparison(profile);
validation = local_validate_profile(profile, anchor, bleedComparison);
parameterTable = local_parameter_table(profile);
scheduleNodeTable = local_schedule_node_table(profile);

middleDataDir = fullfile(thisDir, 'MiddleData');
reportOutputDir = fullfile(fileparts(thisDir), 'report_outputs', ...
    'health_schedule_truth');
if publish && exist(middleDataDir, 'dir') ~= 7
    mkdir(middleDataDir);
end
if publish && exist(reportOutputDir, 'dir') ~= 7
    mkdir(reportOutputDir);
end

figureFiles = {};
if publish
    figureFiles = local_plot_profile(profile, reportOutputDir);
end

result = struct();
result.schemaVersion = profile.schemaVersion;
result.profile = profile;
result.anchor = anchor;
result.operatingPointTable = operatingPointTable;
result.parameterTable = parameterTable;
result.scheduleNodeTable = scheduleNodeTable;
result.bleedComparison = bleedComparison;
result.validation = validation;
result.pass = validation.pass;
result.published = publish;
result.referencePolicy = anchor.sourcePolicy;
result.figureFiles = figureFiles;
result.output = struct();
result.output.matFile = fullfile(middleDataDir, ...
    'six_component_health_schedule_truth_latest.mat');
result.output.parameterCsv = fullfile(reportOutputDir, ...
    'six_component_health_truth_parameters.csv');
result.output.scheduleNodeCsv = fullfile(reportOutputDir, ...
    'six_component_health_schedule_nodes.csv');
result.output.bleedCsv = fullfile(reportOutputDir, ...
    'six_component_bleed_truth_comparison.csv');
result.output.anchorCsv = fullfile(reportOutputDir, ...
    'six_component_health_schedule_anchor_points.csv');
result.output.summaryMarkdown = fullfile(reportOutputDir, ...
    'six_component_health_schedule_truth_summary.md');

if ~publish
    fprintf('固定参考真值验收=%d；未发布，现行试车Excel与真值文件保持不变。\n', result.pass);
    return;
end
assert(result.pass, '真值调度未通过验收，不发布候选结果。');
save(result.output.matFile, 'result');
writetable(parameterTable, result.output.parameterCsv);
writetable(scheduleNodeTable, result.output.scheduleNodeCsv);
writetable(bleedComparison, result.output.bleedCsv);
writetable(operatingPointTable, result.output.anchorCsv);
local_write_summary(result);

assignin('base', 'SixComponentHealthScheduleTruth', result);
local_print_result(result);
end

function tableOut = local_bleed_comparison(profile)
baseline = profile.baselineBleedFraction(:);
delta = profile.bleedFlowFractionDesign(:);
corrected = baseline + delta;
assert(all(corrected > 0), '至少一条修正后引气比例不为正。');

tableOut = table((1:10).', string(profile.bleedBranchNames), ...
    100*baseline, 100*delta, 100*corrected, ...
    100*delta./baseline, ...
    'VariableNames', {'branch_index','branch_name', ...
    'baseline_percent_ac_inlet','additive_change_percentage_point', ...
    'corrected_percent_ac_inlet','relative_change_percent'});
end

function validation = local_validate_profile(profile, anchor, bleedComparison)
[idleHealth, ~] = sht_health_schedule_evaluate(profile, anchor.idleState);
[designHealth, ~] = sht_health_schedule_evaluate(profile, anchor.designState);

belowState = local_outside_state(profile, -1);
aboveState = local_outside_state(profile, 1);
[belowHealth, belowDetail] = sht_health_schedule_evaluate(profile, belowState);
[aboveHealth, aboveDetail] = sht_health_schedule_evaluate(profile, aboveState);

scheduled = ~strcmp({profile.parameters.mode}, 'constant');
scheduledParameters = profile.parameters(scheduled);
expectedLow = zeros(size(belowHealth));
expectedHigh = zeros(size(aboveHealth));
for i = 1:numel(scheduledParameters)
    p = scheduledParameters(i);
    index = p.matlabHealthIndex;
    expectedLow(index) = p.kNodes(1);
    expectedHigh(index) = p.kNodes(end);
end

scheduledIndex = [scheduledParameters.matlabHealthIndex];
lowClampError = max(abs(belowHealth(scheduledIndex) - expectedLow(scheduledIndex)));
highClampError = max(abs(aboveHealth(scheduledIndex) - expectedHigh(scheduledIndex)));
designError = max(abs(designHealth - profile.truthVectorAtDesign));
additiveIdentityError = max(arrayfun(@(p) max(abs( ...
    p.kNodes - (p.designValue + p.deltaNodes))), scheduledParameters));
designIncrementError = max(arrayfun(@(p) ...
    abs(p.deltaNodes(p.designNodeIndex)), scheduledParameters));
lossParameters = profile.parameters([profile.parameters.zeroFlowAnchored]);
assert(numel(lossParameters) == 4, '必须唯一定义四项压损调度。');
idleLossExpected = zeros(numel(lossParameters), 1);
idleLossActual = zeros(numel(lossParameters), 1);
lossOperatingNodeMatchError = 0;
lossZeroCoordinateError = 0;
lossZeroIncrementConstraintError = 0;
lossZeroEffectiveValueError = 0;
for i = 1:numel(lossParameters)
    p = lossParameters(i);
    idleCoordinate = min(max(p.axisIdleValue, p.xNodes(1)), p.xNodes(end));
    idleLossExpected(i) = interp1(p.xNodes, p.kNodes, idleCoordinate, ...
        p.interpolationMethod);
    idleLossActual(i) = idleHealth(p.matlabHealthIndex);
    expectedNodes = [0, anchor.axes.(p.axisName).connectedOperatingNodes];
    lossOperatingNodeMatchError = max(lossOperatingNodeMatchError, ...
        max(abs(p.xNodes(:) - expectedNodes(:))));
    lossZeroCoordinateError = max(lossZeroCoordinateError, abs(p.xNodes(1)));
    lossZeroIncrementConstraintError = max( ...
        lossZeroIncrementConstraintError, ...
        abs(p.deltaNodes(1) + p.designValue));
    lossZeroEffectiveValueError = max(lossZeroEffectiveValueError, ...
        abs(p.kNodes(1)));
end
idleLossCurveError = max(abs(idleLossActual - idleLossExpected));
lossOperatingNodeCount = unique(arrayfun(@(p) numel(p.xNodes), lossParameters));

pressureRatioIndex = [3, 9, 13, 73, 76, 79, 82, 85, 88] + 1;
pressureRatioError = max(abs(designHealth(pressureRatioIndex)));

activeCurve = [profile.parameters.activeTruth] & ...
    ~strcmp({profile.parameters.mode}, 'constant');
activeCurveParameters = profile.parameters(activeCurve);
nonmonotonicCount = nnz([activeCurveParameters.nonmonotonic]);
largeVariationCount = nnz( ...
    arrayfun(@(p) max(p.relativeIncrementNodes) - ...
    min(p.relativeIncrementNodes), activeCurveParameters) >= 0.45);
curveOvershootMax = local_curve_overshoot_max(activeCurveParameters);
[parameterizationFullRank, minimumSingularValue, ...
    maximumConditionNumber] = local_parameterization_rank_check( ...
    scheduledParameters);

validation = struct();
validation.parameterCount = numel(profile.parameters);
validation.activeCount = numel(profile.activeCIndex);
validation.scheduledCount = numel(profile.scheduledCIndex);
validation.activeScheduledCount = numel(profile.activeScheduledCIndex);
validation.activeConstantCount = numel(profile.activeConstantCIndex);
validation.designReproductionMaxAbs = designError;
validation.additiveIdentityMaxAbs = additiveIdentityError;
validation.designIncrementMaxAbs = designIncrementError;
validation.idleLossCurveMaxAbs = idleLossCurveError;
validation.lossOperatingNodeCount = lossOperatingNodeCount;
validation.lossPositiveOperatingNodeCount = 6;
validation.lossOperatingNodeMatchMaxAbs = lossOperatingNodeMatchError;
validation.lossZeroCoordinateMaxAbs = lossZeroCoordinateError;
validation.lossZeroIncrementConstraintMaxAbs = ...
    lossZeroIncrementConstraintError;
validation.lossZeroEffectiveValueMaxAbs = lossZeroEffectiveValueError;
validation.lowEndpointClampMaxAbs = lowClampError;
validation.highEndpointClampMaxAbs = highClampError;
validation.lowClampedQueryCount = nnz([belowDetail.wasClamped]);
validation.highClampedQueryCount = nnz([aboveDetail.wasClamped]);
validation.pressureRatioMaxAbs = pressureRatioError;
validation.nonmonotonicActiveCurveCount = nonmonotonicCount;
validation.largeVariationActiveCurveCount = largeVariationCount;
validation.curveOvershootMax = curveOvershootMax;
validation.parameterizationFullRank = parameterizationFullRank;
validation.parameterizationMinimumSingularValue = minimumSingularValue;
validation.parameterizationMaximumConditionNumber = maximumConditionNumber;
validation.minimumCorrectedBleedPercent = min( ...
    bleedComparison.corrected_percent_ac_inlet);
validation.totalBaselineBleedPercent = sum( ...
    bleedComparison.baseline_percent_ac_inlet);
validation.totalCorrectedBleedPercent = sum( ...
    bleedComparison.corrected_percent_ac_inlet);
validation.pass = validation.parameterCount == 64 && ...
    validation.activeCount == 43 && validation.scheduledCount == 31 && ...
    validation.activeScheduledCount == 22 && ...
    validation.activeConstantCount == 21 && ...
    designError <= 1e-14 && additiveIdentityError <= 1e-14 && ...
    designIncrementError <= 1e-14 && idleLossCurveError <= 1e-14 && ...
    lowClampError <= 1e-14 && highClampError <= 1e-14 && ...
    pressureRatioError <= 1e-14 && ...
    nonmonotonicCount >= 6 && largeVariationCount >= 8 && ...
    curveOvershootMax <= 1e-12 && ...
    isequal(lossOperatingNodeCount, 7) && ...
    lossOperatingNodeMatchError <= 1e-12 && ...
    lossZeroCoordinateError <= 1e-14 && ...
    lossZeroIncrementConstraintError <= 1e-14 && ...
    lossZeroEffectiveValueError <= 1e-14 && ...
    parameterizationFullRank && minimumSingularValue > 1e-6 && ...
    validation.minimumCorrectedBleedPercent > 0;
if ~validation.pass
    error('SHT:HealthSchedule:ValidationFailed', [ ...
        '六部件修正系数真值或调度函数验收失败。' ...
        'count=[%d,%d,%d,%d,%d]，design/additive=[%.3e,%.3e,%.3e]，' ...
        'idleLoss=%.3e，' ...
        'clamp=[%.3e,%.3e]，pressureRatio=%.3e，' ...
        'shape=[nonmono %d, large %d, overshoot %.3e]，' ...
        'lossNodes=[%s, %.3e]，zero=[%.3e,%.3e,%.3e]，' ...
        'rank=[%d,%.3e,%.3e]，minimumBleed=%.3e。'], ...
        validation.parameterCount, validation.activeCount, ...
        validation.scheduledCount, validation.activeScheduledCount, ...
        validation.activeConstantCount, designError, additiveIdentityError, ...
        designIncrementError, idleLossCurveError, lowClampError, highClampError, ...
        pressureRatioError, nonmonotonicCount, largeVariationCount, ...
        curveOvershootMax, mat2str(lossOperatingNodeCount), ...
        lossOperatingNodeMatchError, lossZeroCoordinateError, ...
        lossZeroIncrementConstraintError, lossZeroEffectiveValueError, ...
        parameterizationFullRank, minimumSingularValue, ...
        maximumConditionNumber, ...
        validation.minimumCorrectedBleedPercent);
end
end

function state = local_outside_state(profile, direction)
scheduled = profile.parameters(~strcmp({profile.parameters.mode}, 'constant'));
names = unique({scheduled.axisName}, 'stable');
state = struct();
for i = 1:numel(names)
    parameters = scheduled(strcmp({scheduled.axisName}, names{i}));
    lower = min(arrayfun(@(p) p.xNodes(1), parameters));
    upper = max(arrayfun(@(p) p.xNodes(end), parameters));
    span = max(upper - lower, max(abs([lower, upper])) * 0.1 + eps);
    if direction < 0
        state.(names{i}) = lower - 0.2 * span;
    else
        state.(names{i}) = upper + 0.2 * span;
    end
end
end

function maximumOvershoot = local_curve_overshoot_max(parameters)
maximumOvershoot = 0;
for i = 1:numel(parameters)
    p = parameters(i);
    query = linspace(p.xNodes(1), p.xNodes(end), 401);
    value = interp1(p.xNodes, p.kNodes, query, p.interpolationMethod);
    lowerOvershoot = min(p.kNodes) - min(value);
    upperOvershoot = max(value) - max(p.kNodes);
    maximumOvershoot = max([maximumOvershoot, lowerOvershoot, ...
        upperOvershoot, 0]);
end
end

function [allFullRank, minimumSingularValue, maximumConditionNumber] = ...
        local_parameterization_rank_check(parameters)
% 在各节点检查[k_design, Delta_i]的局部设计矩阵。设计节点Delta_d固定，
% 压损零节点Delta_0=-k_design同样是约束而非自由参数。若把全部Delta_i
% 与k_design同时释放，分片基函数和为1会产生结构奇异；这里显式验证
% 当前自由参数定义已经消除该问题。
allFullRank = true;
minimumSingularValue = inf;
maximumConditionNumber = 0;
for i = 1:numel(parameters)
    p = parameters(i);
    nodeCount = numel(p.xNodes);
    fixedIncrement = p.designNodeIndex;
    if p.zeroFlowAnchored
        fixedIncrement = unique([1, fixedIncrement]);
    end
    freeIncrement = setdiff(1:nodeCount, fixedIncrement);
    matrix = zeros(nodeCount, 1 + numel(freeIncrement));
    if p.zeroFlowAnchored
        matrix(2:end, 1) = 1;
    else
        matrix(:, 1) = 1;
    end
    for j = 1:numel(freeIncrement)
        matrix(freeIncrement(j), j + 1) = 1;
    end
    singularValue = svd(matrix, 'econ');
    expectedRank = size(matrix, 2);
    actualRank = rank(matrix, 1e-12);
    allFullRank = allFullRank && actualRank == expectedRank;
    minimumSingularValue = min(minimumSingularValue, min(singularValue));
    maximumConditionNumber = max(maximumConditionNumber, cond(matrix));
end
end

function tableOut = local_parameter_table(profile)
p = profile.parameters(:);
n = numel(p);
cIndex = zeros(n, 1);
matlabHealthIndex = zeros(n, 1);
matlabStepInIndex = zeros(n, 1);
name = strings(n, 1);
scope = strings(n, 1);
activeTruth = false(n, 1);
mode = strings(n, 1);
scheduleKind = strings(n, 1);
interpolationMethod = strings(n, 1);
axisName = strings(n, 1);
axisLabel = strings(n, 1);
idleValue = zeros(n, 1);
designValue = zeros(n, 1);
nonmonotonic = false(n, 1);
scheduleRange = zeros(n, 1);
zeroFlowAnchored = false(n, 1);
normalNodeCount = zeros(n, 1);
[idleHealth, ~] = sht_health_schedule_evaluate(profile, profile.idleState);
for i = 1:n
    cIndex(i) = p(i).cIndex;
    matlabHealthIndex(i) = p(i).matlabHealthIndex;
    matlabStepInIndex(i) = p(i).matlabStepInIndex;
    name(i) = p(i).name;
    scope(i) = p(i).scope;
    activeTruth(i) = p(i).activeTruth;
    mode(i) = p(i).mode;
    scheduleKind(i) = p(i).scheduleKind;
    interpolationMethod(i) = p(i).interpolationMethod;
    axisName(i) = p(i).axisName;
    axisLabel(i) = p(i).axisLabel;
    idleValue(i) = idleHealth(p(i).matlabHealthIndex);
    designValue(i) = p(i).designValue;
    nonmonotonic(i) = p(i).nonmonotonic;
    scheduleRange(i) = p(i).scheduleRange;
    zeroFlowAnchored(i) = p(i).zeroFlowAnchored;
    normalNodeCount(i) = numel(p(i).xNodes);
end
tableOut = table(cIndex, matlabHealthIndex, matlabStepInIndex, name, ...
    scope, activeTruth, mode, scheduleKind, interpolationMethod, ...
    axisName, axisLabel, idleValue, designValue, nonmonotonic, ...
    scheduleRange, zeroFlowAnchored, normalNodeCount);
end

function tableOut = local_schedule_node_table(profile)
p = profile.parameters(~strcmp({profile.parameters.mode}, 'constant'));
rowCount = sum(arrayfun(@(x) numel(x.xNodes), p));
cIndex = zeros(rowCount, 1);
name = strings(rowCount, 1);
axisName = strings(rowCount, 1);
axisLabel = strings(rowCount, 1);
axisUnit = strings(rowCount, 1);
interpolationMethod = strings(rowCount, 1);
scheduleKind = strings(rowCount, 1);
nodeRole = strings(rowCount, 1);
nodeIndex = zeros(rowCount, 1);
normalizedProgress = zeros(rowCount, 1);
axisValue = zeros(rowCount, 1);
deltaValue = zeros(rowCount, 1);
kValue = zeros(rowCount, 1);
row = 0;
for i = 1:numel(p)
    [nodeX, nodeNormalized, nodeDelta, nodeK, nodeMethod, role] = ...
        local_export_schedule_nodes(p(i));
    for j = 1:numel(nodeX)
        row = row + 1;
        cIndex(row) = p(i).cIndex;
        name(row) = p(i).name;
        axisName(row) = p(i).axisName;
        axisLabel(row) = p(i).axisLabel;
        axisUnit(row) = p(i).axisUnit;
        interpolationMethod(row) = nodeMethod(j);
        scheduleKind(row) = p(i).scheduleKind;
        nodeRole(row) = role(j);
        nodeIndex(row) = j;
        normalizedProgress(row) = nodeNormalized(j);
        axisValue(row) = nodeX(j);
        deltaValue(row) = nodeDelta(j);
        kValue(row) = nodeK(j);
    end
end
tableOut = table(cIndex, name, axisName, axisLabel, axisUnit, ...
    interpolationMethod, scheduleKind, nodeRole, nodeIndex, ...
    normalizedProgress, axisValue, deltaValue, kValue);
end

function [x, normalized, delta, k, method, role] = ...
        local_export_schedule_nodes(parameter)
x = parameter.xNodes;
normalized = parameter.normalizedNodes;
delta = parameter.deltaNodes;
k = parameter.kNodes;
method = repmat(string(parameter.interpolationMethod), 1, numel(x));
if parameter.zeroFlowAnchored
    role = repmat("load_connected_corrected_flow", 1, numel(x));
    role(1) = "zero_flow_anchor";
else
    role = repmat("curve_node", 1, numel(x));
end
role(parameter.designNodeIndex) = "design_anchor";
end

function files = local_plot_profile(profile, outputDir)
files = strings(6, 1);
fileCursor = 0;
commonIndex = [0, 1, 2, 6, 7, 8, 10, 11, 12, 14, 15];
figure1 = figure('Name', '六部件总体启用修正系数', 'Color', 'w', ...
    'Position', [60, 40, 1500, 900]);
for i = 1:numel(commonIndex)
    parameter = local_find_parameter(profile, commonIndex(i));
    subplot(4, 3, i);
    local_plot_parameter(parameter);
end
sgtitle('总体部件、流道与喷管启用真值（压损按局部换算流量调度）');
newFiles = local_save_figure(figure1, outputDir, ...
    '01_enabled_common_health_parameters');
files(fileCursor + (1:numel(newFiles))) = newFiles;
fileCursor = fileCursor + numel(newFiles);

figure2 = figure('Name', '十路物理引气常值修正', 'Color', 'w', ...
    'Position', [100, 70, 1450, 760]);
groups = {30:39, 44:53};
groupTitles = {'流量比例加性修正（AC进口流量基准）', ...
    '取气总温乘性修正'};
for i = 1:2
    subplot(2, 1, i);
    values = zeros(10, 1);
    for j = 1:10
        values(j) = local_find_parameter(profile, groups{i}(j)).designValue;
    end
    bar(1:10, values, 0.72, 'FaceColor', [0.16, 0.47, 0.69]);
    hold on;
    plot([0.5, 10.5], [0, 0], 'k-', 'LineWidth', 0.8);
    hold off;
    xlim([0.5, 10.5]);
    xticks(1:10);
    ylabel('K');
    title(groupTitles{i});
    grid on;
end
xlabel('十路物理引气接口序号');
sgtitle('十路物理引气启用常值真值（K_{PRec}固定为0且不参与分析）');
newFiles = local_save_figure(figure2, outputDir, ...
    '02_enabled_bleed_health_parameters');
files(fileCursor + (1:numel(newFiles))) = newFiles;
fileCursor = fileCursor + numel(newFiles);

componentIndex = [71, 74, 77, 80, 83, 86];
componentNames = {'AC','CC','GT1','GT2','PT1','PT2'};
figure3 = figure('Name', '六个子部件局部修正', 'Color', 'w', ...
    'Position', [140, 90, 1450, 820]);
for i = 1:6
    subplot(3, 2, i);
    flowParameter = local_find_parameter(profile, componentIndex(i));
    efficiencyParameter = local_find_parameter(profile, componentIndex(i) + 1);
    xDense = linspace(flowParameter.xNodes(1), ...
        flowParameter.xNodes(end), 201);
    flowValue = interp1(flowParameter.xNodes, ...
        flowParameter.kNodes, xDense, flowParameter.interpolationMethod);
    efficiencyValue = interp1(efficiencyParameter.xNodes, ...
        efficiencyParameter.kNodes, xDense, ...
        efficiencyParameter.interpolationMethod);
    plot(xDense, flowValue, 'LineWidth', 1.8, 'Color', [0.00, 0.45, 0.74]);
    hold on;
    plot(xDense, efficiencyValue, 'LineWidth', 1.8, ...
        'Color', [0.85, 0.33, 0.10]);
    plot(flowParameter.xNodes, flowParameter.kNodes, 'o', ...
        'Color', [0.00, 0.45, 0.74], 'MarkerFaceColor', 'w');
    plot(efficiencyParameter.xNodes, efficiencyParameter.kNodes, ...
        's', 'Color', [0.85, 0.33, 0.10], 'MarkerFaceColor', 'w');
    plot([xDense(1), xDense(end)], [0, 0], 'k-', 'LineWidth', 0.7);
    hold off;
    xlim([xDense(1), xDense(end)]);
    xlabel(local_axis_caption(flowParameter));
    ylabel('K');
    title(componentNames{i});
    legend({'K_W','K_eta'}, 'Location', 'best', 'Interpreter', 'none');
    grid on;
end
sgtitle('六个旋转子部件启用局部真值（压比修正均为0）');
newFiles = local_save_figure(figure3, outputDir, ...
    '03_enabled_local_component_health_parameters');
files(fileCursor + (1:numel(newFiles))) = newFiles;
fileCursor = fileCursor + numel(newFiles);

assert(fileCursor == numel(files), '修正系数图形输出文件数量与预期不一致。');

% 11个总体/流道参数、20个引气参数和12个局部参数均已进入图形。
assert(numel(commonIndex) + 20 + 12 == numel(profile.activeCIndex), ...
    '启用修正系数绘图覆盖数与真值启用数不一致。');
end

function local_plot_parameter(parameter)
if strcmp(parameter.mode, 'constant')
    xDense = linspace(0, 1, 201);
    value = parameter.designValue .* ones(size(xDense));
else
    xDense = linspace(parameter.xNodes(1), parameter.xNodes(end), 201);
    value = interp1(parameter.xNodes, parameter.kNodes, xDense, ...
        parameter.interpolationMethod);
end
plot(xDense, value, 'LineWidth', 1.8, 'Color', [0.00, 0.45, 0.74]);
hold on;
if ~strcmp(parameter.mode, 'constant')
    plot(parameter.xNodes, parameter.kNodes, 'o', ...
        'Color', [0.00, 0.45, 0.74], 'MarkerFaceColor', 'w');
end
plot([xDense(1), xDense(end)], [0, 0], 'k-', 'LineWidth', 0.7);
hold off;
xlim([xDense(1), xDense(end)]);
if strcmp(parameter.mode, 'constant')
    xlabel('常值参数（无调度来源变量）');
else
    xlabel(local_axis_caption(parameter));
end
ylabel('K');
title(sprintf('h%d %s', parameter.cIndex, parameter.name), ...
    'Interpreter', 'none');
grid on;
end

function text = local_axis_caption(parameter)
% 横坐标直接标明DLL实时查询所使用的物理来源量。
if strcmp(parameter.axisUnit, '-')
    text = sprintf('%s（调度来源变量）', parameter.axisLabel);
else
    text = sprintf('%s / %s（调度来源变量）', ...
        parameter.axisLabel, parameter.axisUnit);
end
end

function files = local_save_figure(handle, outputDir, stem)
pngFile = fullfile(outputDir, [stem, '.png']);
figFile = fullfile(outputDir, [stem, '.fig']);
print(handle, pngFile, '-dpng', '-r180');
savefig(handle, figFile);
files = string({pngFile; figFile});
end

function parameter = local_find_parameter(profile, cIndex)
match = [profile.parameters.cIndex] == cIndex;
assert(nnz(match) == 1, '无法唯一找到h%d。', cIndex);
parameter = profile.parameters(match);
end

function local_write_summary(result)
fileId = fopen(result.output.summaryMarkdown, 'w', 'n', 'UTF-8');
assert(fileId >= 0, '无法写入总结文件：%s。', result.output.summaryMarkdown);
cleanup = onCleanup(@() fclose(fileId));
v = result.validation;
fprintf(fileId, '# 六部件稳态修正系数真值与调度函数验收摘要\n\n');
fprintf(fileId, '- 配置版本：`%s`\n', result.profile.schemaVersion);
fprintf(fileId, '- 参数定义：%d项；真值启用：%d项。\n', ...
    v.parameterCount, v.activeCount);
fprintf(fileId, '- 一维调度能力：%d项，其中当前启用%d项；启用常值%d项。\n', ...
    v.scheduledCount, v.activeScheduledCount, v.activeConstantCount);
fprintf(fileId, ['- 参数化：K_eff=k_design+Delta(x)，设计点Delta_d=0；' ...
    '旋转部件使用6个非均匀节点；每项压损使用零流量锚点和' ...
    '6个负载接通工况换算流量节点，Delta_0=-k_design；' ...
    '正常工作域越界固定至最近端点。\n']);
fprintf(fileId, '- 设计点复现最大绝对误差：`%.3e`。\n', ...
    v.designReproductionMaxAbs);
fprintf(fileId, '- 加性恒等式/设计点增量最大误差：`%.3e / %.3e`。\n', ...
    v.additiveIdentityMaxAbs, v.designIncrementMaxAbs);
fprintf(fileId, '- 慢车端四项压损曲线误差：`%.3e`。\n', ...
    v.idleLossCurveMaxAbs);
fprintf(fileId, '- 每项压损总节点/正流量工况节点数：`%d / %d`。\n', ...
    v.lossOperatingNodeCount, v.lossPositiveOperatingNodeCount);
fprintf(fileId, '- 压损节点与“0+六个负载接通工况”最大偏差：`%.3e kg/s`。\n', ...
    v.lossOperatingNodeMatchMaxAbs);
fprintf(fileId, '- 压损零流量坐标/增量约束/有效值误差：`%.3e / %.3e / %.3e`。\n', ...
    v.lossZeroCoordinateMaxAbs, v.lossZeroIncrementConstraintMaxAbs, ...
    v.lossZeroEffectiveValueMaxAbs);
fprintf(fileId, '- 增量参数化满秩/最小奇异值/最大条件数：`%s / %.3e / %.3e`。\n', ...
    local_pass_text(v.parameterizationFullRank), ...
    v.parameterizationMinimumSingularValue, ...
    v.parameterizationMaximumConditionNumber);
fprintf(fileId, '- 启用非单调曲线/大变化曲线：`%d / %d`项。\n', ...
    v.nonmonotonicActiveCurveCount, v.largeVariationActiveCurveCount);
fprintf(fileId, '- 低端解析行为/高端截断误差：`%.3e / %.3e`。\n', ...
    v.lowEndpointClampMaxAbs, v.highEndpointClampMaxAbs);
fprintf(fileId, '- 全部压比修正最大绝对值：`%.3e`。\n', ...
    v.pressureRatioMaxAbs);
fprintf(fileId, '- 10路基准/修正后总引气比例：`%.4f%% / %.4f%%`（AC进口流量基准）。\n', ...
    v.totalBaselineBleedPercent, v.totalCorrectedBleedPercent);
fprintf(fileId, '- 综合验收：**%s**。\n\n', local_pass_text(v.pass));

fprintf(fileId, '## 10路引气流量修正\n\n');
fprintf(fileId, '|序号|名称|基准/%%|加性变化/百分点|修正后/%%|相对变化/%%|\n');
fprintf(fileId, '|---:|---|---:|---:|---:|---:|\n');
tableIn = result.bleedComparison;
for i = 1:height(tableIn)
    fprintf(fileId, '|%d|%s|%.4f|%+.4f|%.4f|%+.3f|\n', ...
        tableIn.branch_index(i), tableIn.branch_name(i), ...
        tableIn.baseline_percent_ac_inlet(i), ...
        tableIn.additive_change_percentage_point(i), ...
        tableIn.corrected_percent_ac_inlet(i), ...
        tableIn.relative_change_percent(i));
end

fprintf(fileId, '\n## 适用边界\n\n');
fprintf(fileId, ['本结果是试车替代数据的可复现实验真值，不是实测发动机退化规律。' ...
    '本MAT资产需由sht_health_schedule_initialize_dll在六部件模型初始化后装载；' ...
    'stepIn传递设计点值，stepIn(18)逐次选择常值或调度语义，' ...
    'DLL查询Delta分段线性表并计算K_eff=k_design+Delta(x)。' ...
    '燃烧室和流道名义压损已在C程序中按局部归一化修正流量平方建模，' ...
    '并保留名义压损低流量门控；个体压损修正仍使用独立的Delta调度表，' ...
    '不得把名义压损规律和个体修正规律混为一体。\n']);
clear cleanup;
end

function local_print_result(result)
v = result.validation;
fprintf('\n=== 六部件稳态修正系数真值与调度设计 ===\n');
fprintf('参数定义/启用真值       : %d / %d\n', v.parameterCount, v.activeCount);
fprintf('调度能力/启用调度/常值 : %d / %d / %d\n', ...
    v.scheduledCount, v.activeScheduledCount, v.activeConstantCount);
fprintf('非单调曲线/大变化曲线   : %d / %d\n', ...
    v.nonmonotonicActiveCurveCount, v.largeVariationActiveCurveCount);
fprintf('压损总节点/正流量节点   : %d / %d\n', ...
    v.lossOperatingNodeCount, v.lossPositiveOperatingNodeCount);
fprintf('压损0+六工况节点偏差    : %.3e kg/s\n', ...
    v.lossOperatingNodeMatchMaxAbs);
fprintf('压损零流量K/Delta约束误差: %.3e / %.3e\n', ...
    v.lossZeroEffectiveValueMaxAbs, v.lossZeroIncrementConstraintMaxAbs);
fprintf('增量参数化最小奇异值/最大条件数: %.3e / %.3e\n', ...
    v.parameterizationMinimumSingularValue, ...
    v.parameterizationMaximumConditionNumber);
fprintf('h6 Burner_K_dP设计值    : %+.6f\n', ...
    result.profile.truthVectorAtDesign(7));
fprintf('全部压比修正最大值      : %.3e\n', v.pressureRatioMaxAbs);
fprintf('低端解析/高端截断误差   : %.3e / %.3e\n', ...
    v.lowEndpointClampMaxAbs, v.highEndpointClampMaxAbs);
fprintf('10路总引气比例（基准/修正后）: %.4f%% / %.4f%%\n', ...
    v.totalBaselineBleedPercent, v.totalCorrectedBleedPercent);
fprintf('综合验收                 : %s\n\n', local_pass_text(v.pass));

fprintf('10路引气流量比例（AC进口流量基准）：\n');
disp(result.bleedComparison(:, {'branch_index','branch_name', ...
    'baseline_percent_ac_inlet','additive_change_percentage_point', ...
    'corrected_percent_ac_inlet'}));

fprintf('全部启用修正系数的慢车端/设计点真值：\n');
activeTable = result.parameterTable(result.parameterTable.activeTruth, ...
    {'cIndex','name','mode','axisName','idleValue','designValue'});
disp(activeTable);
fprintf('下游MAT：%s\n', result.output.matFile);
fprintf('图表目录：%s\n', fileparts(result.output.summaryMarkdown));
end

function text = local_pass_text(pass)
if pass
    text = 'PASS';
else
    text = 'FAIL';
end
end
