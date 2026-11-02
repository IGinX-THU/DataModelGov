function varargout = sht_steady_model_adapt_v2_common(action, varargin)
%SHT_STEADY_MODEL_ADAPT_V2_COMMON 三/六部件稳态修正系数辨识公共内核。
%
% 该文件只提供无状态公共能力。两个正式入口分别选择steady和
% transient_instant模型口径，互不读取结果、互不调用，也不共享初值文件。
% 六部件模式4使用实测Pt2；TC24三部件模式1使用实测Pt1/Tt1。
% 正式辨识不读取隐藏真值或真值节点；历史真值输入对照不得混入正式入口。

switch lower(action)
    case 'parameterdefinition'
        % 显式选项只读字典：不补默认配置，也不初始化模型或读取数据。
        if numel(varargin) ~= 1 || ~isstruct(varargin{1}) || ~isscalar(varargin{1})
            error('SHT:SteadyAdaptV2:ParameterDefinitionOptions', ...
                'parameterdefinition 必须提供一个显式标量 options 结构体。');
        end
        options = varargin{1};
        if ~isfield(options, 'estimateInletPressureLoss') || ...
                ~(islogical(options.estimateInletPressureLoss) || ...
                isnumeric(options.estimateInletPressureLoss)) || ...
                ~isreal(options.estimateInletPressureLoss) || ...
                ~isscalar(options.estimateInletPressureLoss) || ...
                ~ismember(options.estimateInletPressureLoss, [0, 1])
            error('SHT:SteadyAdaptV2:ParameterDefinitionInletFlag', ...
                'options.estimateInletPressureLoss 必须显式给定为 true/false 或 0/1。');
        end
        varargout{1} = local_parameter_definition(options);
    case 'stagebpriorscale'
        varargout{1} = local_stage_b_prior_scale(varargin{:});
    case 'schedulenodesourceaudit'
        varargout{1} = local_schedule_node_source_audit(varargin{:});
    case 'stagecinitialcoordinates'
        varargout{1} = local_stage_c_initial_coordinates(varargin{:});
    case 'reportschedulestabilization'
        varargout{1} = local_report_schedule_stabilization(varargin{:});
    case 'defaultoptions'
        varargout{1} = local_default_options(varargin{:});
    case 'run'
        varargout{1} = local_run(varargin{:});
    case 'prepare'
        varargout{1} = local_run(varargin{1},varargin{2},[],true);
    case 'runfromstagec'
        varargout{1} = local_run(varargin{:});
    case 'runstagedfromschedules'
        varargout{1} = local_run_stage_d_from_schedules(varargin{:});
    case 'paths'
        varargout{1} = local_paths(varargin{:});
    case 'readmeasurementtable'
        varargout{1} = local_read_measurement_table(varargin{:});
    case 'measurementweighting'
        varargout{1} = local_residual_weighting(varargin{:});
    case 'validatesavedschedule'
        varargout{1} = local_validate_saved_schedule(varargin{:});
    case 'validateconstant'
        % 与调度曲线测试共用分支约束/稳态回放，只替换为冻结A常值模型。
        varargout{1} = local_validate_saved_schedule(varargin{1},varargin{2},[],true);
    case 'predictsavedschedule'
        varargout{1} = local_predict_saved_schedule(varargin{:});
    case 'restoredeliverymodel'
        varargout{1} = local_restore_delivery_model(varargin{:});
    case 'exportdeliveryworkbook'
        varargout{1} = local_write_m3_result_excel_atomic(varargin{:});
    case 'evaluateschedule'
        varargout{1} = local_evaluate_saved_schedule(varargin{:});
    case 'evaluateconstant'
        varargout{1} = local_evaluate_saved_constant(varargin{:});
    case 'evaluateoffsetbatch'
        varargout{1} = local_evaluate_offset_batch(varargin{:});
    case 'evaluateoffsetbatchdataset'
        varargout{1} = local_evaluate_offset_batch_dataset(varargin{:});
    case 'evaluateschedulebatchdataset'
        varargout{1} = local_evaluate_schedule_batch_dataset(varargin{:});
    case 'evaluatescheduletrajectorybatch'
        varargout{1} = local_evaluate_schedule_trajectory_batch(varargin{:});
    case 'evaluatedatasetvariants'
        varargout{1} = local_evaluate_dataset_variants(varargin{:});
    case 'm3nodecontract'
        varargout{1} = local_build_m3_node_contract(varargin{:});
    case 'm3scheduletonodes'
        varargout{1} = local_m3_schedule_to_vector(varargin{:});
    case 'm3nodestoschedule'
        varargout{1} = local_m3_vector_to_schedule(varargin{:});
    case 'm3centraldifferencekernel'
        [varargout{1:nargout}] = local_strict_central_jacobian(varargin{:});
    case 'boundedsolverkernel'
        % 用解析残差单独回归A/B共用更新器，不启动发动机或读取试车数据。
        varargout{1} = local_bounded_lm(varargin{:});
    case 'm3priorcovariance'
        varargout{1} = local_m3_prior_bundle(varargin{:});
    case 'm3boxquadraticsolve'
        [varargout{1:nargout}] = local_m3_box_quadratic_solve(varargin{:});
    case 'm3workbookselftest'
        varargout{1} = local_m3_workbook_selftest(varargin{:});
    case 'publishdeterministicdelivery'
        varargout{1} = local_publish_existing_deterministic_delivery( ...
            varargin{:});
    otherwise
        error('SHT:SteadyAdaptV2:UnknownAction', ...
            '未知第二轮稳态辨识公共动作：%s。', action);
end
end

function cfg = local_engine_config(options)
% 运行包是显式求值配置，不从历史Excel或另一个分支猜测，不启用RNI。
engine=struct('modelMode',options.modelMode);
if isfield(options,'runtimeDirectory') && ~isempty(options.runtimeDirectory)
    engine.runtimeDirectory=options.runtimeDirectory;
end
cfg=sht_default_config(struct('engine',engine));
end

function audit = local_schedule_node_source_audit(result)
% 只读专项检查：复用正式分组/节点构造/重锚定函数，不运行参数优化。
% 已有B结果仅用于提供各组纵坐标；真值资产不作为输入，也不参与比较目标。
options = local_complete_options(result.options,result.route);
assert((options.inletBoundaryMode == 4 || options.modelMode==0) && ~result.truthWasRead, ...
    'SHT:NodeSource:Boundary', '节点隔离核查只适用于正式模式4结果。');
data = local_read_measurement_table(result.input.trainingFile, '训练集');
[data, ~] = local_prepare_np_branch_data(data, table(), options);
cfg = local_engine_config(options);
speed = local_measured_ac_corrected_speed(data, cfg);
groups = local_cluster_by_ac_speed(data, speed, options.clusterSpan);
assert(isequal(groups.point_ids, result.groups.point_ids));
assert(max(abs(groups.ac_ncr_mean-result.groups.ac_ncr_mean)) < 1e-12);
parameters = local_parameter_definition(options);
engine = sht_engine_open(cfg.engine);
cleanup = onCleanup(@() sht_engine_close(engine));
zeroModel = local_constant_model(parameters, zeros(height(parameters),1), 0);
[prediction, valid] = local_evaluate_dataset( ...
    result.route, engine, cfg, data, zeroModel, options);
if ~valid
    disp(prediction(:,{'point_id','valid','error_message'}));
end
assert(valid, 'SHT:NodeSource:InvalidReplay', '公开训练数据零修正回放失败。');
prediction=local_stage_c_initial_coordinates(data,prediction,result.stageB,options);
schedule = local_build_schedule(data, prediction, groups, result.stageB, ...
    parameters, cfg.engine.initial.Wf0, options);
rows = repmat(struct('c_index',NaN,'name',"",'axis',"", ...
    'raw_group_count',NaN,'positive_node_count',NaN,'dll_node_count',NaN, ...
    'group_mean_error',NaN), 0, 1);
for j = 1:numel(schedule.healthEntries)
    e = schedule.healthEntries(j);
    expected = zeros(height(groups),1);
    for g = 1:height(groups)
        idx = local_group_row_indices(groups,g);
        expected(g) = mean(prediction.(e.axisName)(idx));
    end
    difference = max(abs(expected-e.groupCoordinates));
    assert(difference < 1e-12);
    if options.adaptiveEvidenceNodes
        assert(numel(e.xNodes)<=height(data)+double(e.pressureLoss));
        q=prediction.(e.axisName);first=1+double(e.pressureLoss);
        assert(abs(e.xNodes(first)-min(q))<1e-12 && abs(e.xNodes(end)-max(q))<1e-12);
        assert(isequal(e.nodeFormation.pointGroup,local_point_group_membership(data,groups)));
    else
        assert(numel(e.xNodes) <= height(groups)+double(e.pressureLoss));
    end
    assert(isequal(e.xNodes, e.xNodesDll) && ~e.dllResamplingUsed);
    rows(end+1,1) = struct('c_index',e.cIndex,'name',string(e.name), ...
        'axis',string(e.axisName),'raw_group_count',height(groups), ...
        'positive_node_count',numel(e.xNodes)-double(e.pressureLoss), ...
        'dll_node_count',numel(e.xNodesDll),'group_mean_error',difference); %#ok<AGROW>
end
expectedFuel = zeros(height(groups),1);
for g = 1:height(groups)
    idx = local_group_row_indices(groups,g);
    expectedFuel(g) = mean(data.Wf_mean(idx))/cfg.engine.initial.Wf0;
end
fuelError = max(abs(expectedFuel-schedule.fuelBias.groupCoordinates));
assert(fuelError < 1e-12);
if options.inletBoundaryMode==4
    direct = local_build_direct_inlet_pressure_loss( ...
        data, prediction, table(), table(), options);
    assert(isequal(direct.entry.groupCoordinates,prediction.inlet_corrected_mass_flow));
end

% 反事实检查：只改测量Ng，分组坐标必须响应；只改模型横坐标，
% 组内物理坐标必须响应。这不是重新生成试车数据或重新估计参数。
changedData = data;
changedData.Ng_mean = data.Ng_mean + 0.002*cfg.engine.initial.Ng0 .* ...
    sqrt(data.Tt1_mean/288.15);
changedSpeed = local_measured_ac_corrected_speed(changedData,cfg);
assert(max(abs(changedSpeed-speed-0.002)) < 1e-12);
changedPrediction = prediction;
axes = unique(parameters.axis_name(parameters.scheduled));
for j = 1:numel(axes)
    field = char(axes(j));
    changedPrediction.(field) = 1.002*prediction.(field);
end
moved = local_reanchor_schedule(schedule,data,changedPrediction, ...
    groups,parameters,options);
reanchorError = 0;
for j = 1:numel(moved.healthEntries)
    e = moved.healthEntries(j);
    expected = 1.002*schedule.healthEntries(j).groupCoordinates;
    reanchorError = max(reanchorError,max(abs(e.groupCoordinates-expected)));
end
assert(reanchorError < 1e-12);

% 点数与组数不写死为7/6：使用1、3、9组的接口级人工数据检查。
% 此处只测试节点组装规则，不声称人工数据是物理可行的发动机工况。
counts = [1,3,9];
nodeCounts = zeros(size(counts));
for c = 1:numel(counts)
    n = counts(c);
    small = data(ones(n,1),:);
    small.point_id = compose("AUDIT-%02d",(1:n).');
    x = 0.65+(0:n-1).'*0.05;
    small.Ng_mean = cfg.engine.initial.Ng0*x.*sqrt(small.Tt1_mean/288.15);
    small.Wf_mean = cfg.engine.initial.Wf0*(0.4+(0:n-1).'*0.06);
    g = local_cluster_by_ac_speed(small, ...
        local_measured_ac_corrected_speed(small,cfg),options.clusterSpan);
    assert(height(g)==n);
    p = prediction(ones(n,1),:);
    for j = 1:numel(axes), p.(char(axes(j)))=x; end
    b = repmat(result.stageB(1),n,1);
    s = local_build_schedule(small,p,g,b,parameters,cfg.engine.initial.Wf0,options);
    nodeCounts(c) = numel(s.fuelBias.xNodes);
    assert(nodeCounts(c)==n);
    for j = 1:numel(s.healthEntries)
        e=s.healthEntries(j);
        if options.adaptiveEvidenceNodes && strcmp(e.axisName,'burner_inlet_corrected_mass_flow')
            assert(numel(e.xNodes)<=n+double(e.pressureLoss));
        else
            assert(numel(e.xNodes)==n+double(e.pressureLoss));
        end
    end
    if n==9
        p.(char(axes(1)))(2)=p.(char(axes(1)))(1);
        merged = local_build_schedule(small,p,g,b,parameters,cfg.engine.initial.Wf0,options);
        use = strcmp({merged.healthEntries.axisName},char(axes(1)));
        selectedEntries=merged.healthEntries(use);
        for index=1:numel(selectedEntries)
            e=selectedEntries(index);
            if options.adaptiveEvidenceNodes && strcmp(e.axisName,'burner_inlet_corrected_mass_flow')
                assert(numel(e.xNodes)<=n-1+double(e.pressureLoss));
            else
                assert(numel(e.xNodes)==n-1+double(e.pressureLoss));
            end
        end
    end
end
audit = struct('pass',true,'route',result.route,'groups',groups, ...
    'nodeSources',struct2table(rows),'fuelGroupMeanMaxError',fuelError, ...
    'reanchorMaxError',reanchorError,'variableGroupCounts',counts, ...
    'variableFuelNodeCounts',nodeCounts,'truthRead',false, ...
    'scope','training-only replay and production node assembly; no parameter optimization');
clear cleanup;
end

function result = local_run_stage_d_from_schedules( ...
        route, initialSchedule, priorCenterSchedule, options)
%LOCAL_RUN_STAGE_D_FROM_SCHEDULES 在冻结节点网格上单独执行阶段D。
%
% 该入口服务于“外部候选调度作为初值”的受控对比试验。它复用正式
% 阶段D的实际执行节点、完整中心差分Jacobian、有界Tikhonov求解和
% 最终点新Jacobian审核，但不重复阶段A/B/C，也不写latest或正式Excel。
% initialSchedule决定非线性迭代初值；priorCenterSchedule仅决定正则中心。
% 两者可以不同，但必须能在同一冻结节点合同上逐项对应。
route = local_validate_route(route);
if nargin < 4 || isempty(options)
    options = local_default_options(route);
else
    options = local_complete_options(options, route);
end
if ~strcmp(options.stageDParameterization, 'actual_execution_nodes') || ...
        ~strcmp(options.stageDJacobianMethod, 'node_central_full') || ...
        ~strcmp(options.stageDRegularizationMethod, 'tikhonov')
    error('SHT:SteadyAdaptV2:StageDOnlyMethodMismatch', ...
        ['阶段D独立精修只允许actual_execution_nodes、' ...
         'node_central_full和tikhonov组合。']);
end
if options.inletBoundaryMode ~= 4 && ~(options.modelMode==0 && options.inletBoundaryMode==1)
    error('SHT:SteadyAdaptV2:StageDOnlyBoundaryMode', ...
        '当前阶段D独立精修合同只允许模式4实测Pt2边界。');
end
if numel(options.stageDM3ContinuationRegularizationStrengths) ~= 1
    error('SHT:SteadyAdaptV2:StageDOnlyContinuationForbidden', ...
        ['后验引导精修必须在一个固定物理正则强度下比较；' ...
         '不得混入多层延续初始化。']);
end

rng(options.randomSeed, 'twister');
runTimer = tic;
phaseTimer = tic;
paths = local_paths(options);
codeSnapshotBefore = local_deterministic_code_snapshot(paths, route);
runtimeTrainingSnapshotBefore = local_source_file_snapshot(paths.trainingFile);
[trainingData, testData] = local_read_input_tables(paths, options);
runtimeTrainingSnapshotAfterRead = ...
    local_source_file_snapshot(paths.trainingFile);
local_assert_source_file_snapshot_equal(runtimeTrainingSnapshotBefore, ...
    runtimeTrainingSnapshotAfterRead, '阶段D独立精修训练Excel读取期间');
testDataAvailable = options.evaluateTestSet && ~isempty(testData);
[trainingData, testData, npBranchPrior] = ...
    local_prepare_np_branch_data(trainingData, testData, options);
parameters = local_parameter_definition(options);

cfg = local_engine_config(options);
if cfg.engine.modelMode ~= options.modelMode
    error('SHT:SteadyAdaptV2:StageDOnlyWrongModelMode', ...
        '阶段D独立精修必须使用六部件模型modelMode=1。');
end
runtimeSnapshotBefore = local_runtime_identity_snapshot(paths, cfg);
engine = sht_engine_open(cfg.engine);
cleanupObject = onCleanup(@() sht_engine_close(engine));
timing = struct('dataAndInitializationSeconds', toc(phaseTimer));

wfDesign = cfg.engine.initial.Wf0;
scales = local_residual_scales(route, cfg, trainingData, options);
zeroModel = local_constant_model(parameters, zeros(height(parameters), 1), 0);
phaseTimer = tic;
[baselineTraining, baselineTrainingValid] = local_evaluate_dataset( ...
    route, engine, cfg, trainingData, zeroModel, options);
[baselineTest, baselineTestValid] = local_evaluate_dataset( ...
    route, engine, cfg, testData, zeroModel, options);
if ~baselineTrainingValid
    error('SHT:SteadyAdaptV2:StageDOnlyBaselineFailure', ...
        '零修正模型不能完成全部训练工况回放，禁止执行阶段D独立精修。');
end
measuredAcCorrectedSpeed = local_measured_ac_corrected_speed( ...
    trainingData, cfg);
groups = local_cluster_by_ac_speed( ...
    trainingData, measuredAcCorrectedSpeed, options.clusterSpan);
weighting = local_residual_weighting( ...
    route, trainingData, baselineTraining, scales, options);
timing.baselineAndContractSeconds = toc(phaseTimer);

% 后验均值使用正式UQ冻结的执行节点坐标。原阶段C正则中心如采用不同
% 网格，只在这些冻结坐标上插值重表达，不改变其函数含义。
priorCenterOnInitialGrid = local_m3_regrid_prior_center( ...
    priorCenterSchedule, initialSchedule, parameters);
initialNodeContract = local_build_m3_node_contract( ...
    initialSchedule, parameters, wfDesign, options);
priorCenterNodeContract = local_build_m3_node_contract( ...
    priorCenterOnInitialGrid, parameters, wfDesign, options);
local_assert_m3_contract_layout(initialNodeContract, priorCenterNodeContract);

phaseTimer = tic;
[initialTraining, initialTrainingValid] = local_evaluate_dataset( ...
    route, engine, cfg, trainingData, ...
    local_schedule_model(initialSchedule), options);
[initialTest, initialTestValid] = local_evaluate_dataset( ...
    route, engine, cfg, testData, local_schedule_model(initialSchedule), options);
[priorTraining, priorTrainingValid] = local_evaluate_dataset( ...
    route, engine, cfg, trainingData, ...
    local_schedule_model(priorCenterOnInitialGrid), options);
[priorTest, priorTestValid] = local_evaluate_dataset( ...
    route, engine, cfg, testData, ...
    local_schedule_model(priorCenterOnInitialGrid), options);
if ~initialTrainingValid || ~priorTrainingValid
    error('SHT:SteadyAdaptV2:StageDOnlyScheduleReplayInvalid', ...
        ['给定初值或正则中心不能完成全部训练工况精确回放：' ...
         'initial=%d，prior=%d。'], initialTrainingValid, priorTrainingValid);
end
timing.initialEvaluationSeconds = toc(phaseTimer);

phaseTimer = tic;
[stageRefine, finalSchedule] = local_run_stage_d_pass( ...
    initialSchedule, priorCenterOnInitialGrid, [], route, engine, cfg, ...
    trainingData, parameters, weighting, wfDesign, options, ...
    'D_posterior_informed_fixed_grid_refine');
timing.stageDSeconds = toc(phaseTimer);

phaseTimer = tic;
[finalTraining, finalTrainingValid] = local_evaluate_dataset( ...
    route, engine, cfg, trainingData, ...
    local_schedule_model(finalSchedule), options);
[finalTest, finalTestValid] = local_evaluate_dataset( ...
    route, engine, cfg, testData, local_schedule_model(finalSchedule), options);
finalNodeContract = local_build_m3_node_contract( ...
    finalSchedule, parameters, wfDesign, options);
finalPriorCenterNodeContract = local_build_m3_node_contract( ...
    priorCenterOnInitialGrid, parameters, wfDesign, options);
local_assert_m3_contract_layout(finalNodeContract, ...
    finalPriorCenterNodeContract);

baselineMetricsTraining = local_dataset_metrics( ...
    route, trainingData, baselineTraining, scales);
baselineMetricsTest = local_dataset_metrics( ...
    route, testData, baselineTest, scales);
initialMetricsTraining = local_dataset_metrics( ...
    route, trainingData, initialTraining, scales);
initialMetricsTest = local_dataset_metrics( ...
    route, testData, initialTest, scales);
priorMetricsTraining = local_dataset_metrics( ...
    route, trainingData, priorTraining, scales);
priorMetricsTest = local_dataset_metrics( ...
    route, testData, priorTest, scales);
finalMetricsTraining = local_dataset_metrics( ...
    route, trainingData, finalTraining, scales);
finalMetricsTest = local_dataset_metrics( ...
    route, testData, finalTest, scales);
timing.finalEvaluationSeconds = toc(phaseTimer);
timing.estimationSeconds = toc(runTimer);

runId = options.runId;
if isempty(runId)
    runId = sprintf('det_m3_stage_d_only_%s', ...
        datestr(now, 'yyyymmdd_HHMMSS'));
end
codeSnapshotAfter = local_deterministic_code_snapshot(paths, route);
runtimeSnapshotAfter = local_runtime_identity_snapshot(paths, cfg);
trainingSnapshotAfter = local_source_file_snapshot(paths.trainingFile);
local_assert_identity_snapshot_equal(codeSnapshotBefore, ...
    codeSnapshotAfter, '阶段D独立精修MATLAB代码');
local_assert_identity_snapshot_equal(runtimeSnapshotBefore, ...
    runtimeSnapshotAfter, '阶段D独立精修模型运行资产');
local_assert_source_file_snapshot_equal(runtimeTrainingSnapshotBefore, ...
    trainingSnapshotAfter, '阶段D独立精修训练Excel');
[identity, deterministicContractHash] = ...
    local_deterministic_result_identity(paths, cfg, route, options, ...
    weighting, npBranchPrior, finalNodeContract.nodeContractHash, runId, ...
    codeSnapshotBefore, runtimeSnapshotBefore, ...
    runtimeTrainingSnapshotBefore);

result = struct();
result.schemaVersion = ...
    'SHT_STEADY_MODEL_ADAPT_V2_STAGE_D_FROM_SCHEDULES_V1';
result.program = 'sht_steady_model_adapt_v2_common/runStageDFromSchedules';
result.route = route;
result.createdAt = datestr(now, 31);
result.runId = runId;
result.options = options;
result.timing = timing;
result.input = struct('trainingFile', paths.trainingFile, ...
    'testFile', paths.testFile, ...
    'trainingPointCount', height(trainingData), ...
    'testPointCount', height(testData), ...
    'testDataAvailable', testDataAvailable, ...
    'testDataUsedForInference', false, ...
    'hiddenTruthUsedForInference', false);
result.parameterDefinition = parameters;
result.npBranchPrior = npBranchPrior;
result.residualScales = scales;
result.residualWeighting = weighting;
result.groups = groups;
result.initialSchedule = initialSchedule;
result.priorCenterSchedule = priorCenterOnInitialGrid;
result.finalSchedule = finalSchedule;
result.initialNodeContract = initialNodeContract;
result.priorCenterNodeContract = priorCenterNodeContract;
result.nodeContract = finalNodeContract;
result.finalPriorCenterNodeContract = finalPriorCenterNodeContract;
result.nodeContractHash = finalNodeContract.nodeContractHash;
result.stageDParameterization = options.stageDParameterization;
result.stageDJacobianMethod = options.stageDJacobianMethod;
result.stageRefine = stageRefine;
result.fixedExecutionGrid = true;
result.reanchorExecuted = false;
result.baseline = struct('training', baselineTraining, ...
    'test', baselineTest, 'trainingValid', baselineTrainingValid, ...
    'testValid', local_optional_test_valid( ...
        testDataAvailable, baselineTestValid), ...
    'trainingMetrics', baselineMetricsTraining, ...
    'testMetrics', baselineMetricsTest);
result.initial = struct('training', initialTraining, 'test', initialTest, ...
    'trainingValid', initialTrainingValid, ...
    'testValid', local_optional_test_valid(testDataAvailable, initialTestValid), ...
    'trainingMetrics', initialMetricsTraining, ...
    'testMetrics', initialMetricsTest);
result.priorCenter = struct('training', priorTraining, 'test', priorTest, ...
    'trainingValid', priorTrainingValid, ...
    'testValid', local_optional_test_valid(testDataAvailable, priorTestValid), ...
    'trainingMetrics', priorMetricsTraining, ...
    'testMetrics', priorMetricsTest);
result.final = struct('training', finalTraining, 'test', finalTest, ...
    'trainingValid', finalTrainingValid, ...
    'testValid', local_optional_test_valid(testDataAvailable, finalTestValid), ...
    'trainingMetrics', finalMetricsTraining, ...
    'testMetrics', finalMetricsTest);
result.predictionTrainingTable = local_prediction_detail_table( ...
    route, trainingData, initialTraining, finalTraining, scales);
result.predictionTestTable = local_prediction_detail_table( ...
    route, testData, initialTest, finalTest, scales);
result.residualStatistics = local_residual_statistics( ...
    local_raw_data_residual_matrix(route, trainingData, finalTraining, ...
    cellstr(weighting.names)), weighting);
result.identity = identity;
result.deterministicContractHash = deterministicContractHash;
result.truthWasRead = false;
result.formalLatestOverwritten = false;
result.acceptance = struct( ...
    'stageDConverged', stageRefine.converged, ...
    'trainingReplayValid', finalTrainingValid, ...
    'testReplayValid', local_optional_test_valid( ...
        testDataAvailable, finalTestValid), ...
    'nodeRoundTripPassed', finalNodeContract.roundTripPassed, ...
    'resultUsableForComparison', finalTrainingValid && ...
        (~testDataAvailable || finalTestValid) && ...
        finalNodeContract.roundTripPassed, ...
    'testDataUsedForInference', false, ...
    'hiddenTruthUsedForInference', false);

if options.requireValidFinalReplay && ...
        ~result.acceptance.resultUsableForComparison
    error('SHT:SteadyAdaptV2:StageDOnlyFinalReplayInvalid', ...
        '阶段D独立精修最终训练/测试回放或节点往返检查未通过。');
end
if options.verbose
    fprintf(['阶段D独立精修完成：初值/最终训练NRMS=%.6g/%.6g，' ...
        '测试NRMS=%.6g/%.6g，迭代=%d，收敛=%d，耗时=%.1f s。\n'], ...
        initialMetricsTraining.overall_nrms, ...
        finalMetricsTraining.overall_nrms, ...
        initialMetricsTest.overall_nrms, finalMetricsTest.overall_nrms, ...
        stageRefine.iterationCount, stageRefine.converged, ...
        timing.estimationSeconds);
end
clear cleanupObject;
end

function reuse=local_validate_stage_c_reuse(source,route,options,training,runtime,groups,parameters,weighting,code)
% 仅放行同一问题的D强度/迭代预算/信赖域对照。改变训练数据、A/B算法、节点规则或DLL时，
% 必须重算A/B/C，不能因缓存文件存在就直接复用。
assert(strcmp(source.route,route) && source.options.modelMode==options.modelMode, ...
    'SHT:SteadyAdaptV2:StageCReuseRoute','A/B/C来源路径或部件模式不一致。');
assert(~source.truthWasRead && ~source.input.testDataUsedForInference && ...
    ~options.evaluateTestSet && ~options.stageAOnly, ...
    'SHT:SteadyAdaptV2:StageCReuseData','复用辨识不得读取真值或测试集。');
assert(strcmp(source.identity.trainingDataSha256,training.sha256) && ...
    strcmp(source.identity.runtimeAggregateSha256,runtime.aggregateSha256), ...
    'SHT:SteadyAdaptV2:StageCReuseIdentity','训练数据或DLL/MDL/MAP身份发生改变。');
assert(isequaln(source.groups,groups) && isequaln(source.parameterDefinition,parameters) && ...
    strcmp(source.identity.residualWeightingSha256,local_value_hash(weighting)), ...
    'SHT:SteadyAdaptV2:StageCReuseProblem','分组、待估参数或残差权重不一致。');
allowed={'stageDM3RegularizationStrength','stageDM3RegularizationCandidates', ...
    'maxIterationRefine','stageDCoordinateReserveIterations', ...
    'stageDM3GlobalizationMethod','stageDM3TrustMaximumTrials', ...
    'stageDM3ContinuationRegularizationStrengths','outputTag','runId', ...
    'publishLatest','saveStampedResult','verbose','figureVisible', ...
    'saveStageCDevelopmentCheckpoint'};
old=source.options;new=options;
% 旧记录缺省等同于统一尺度；只补这一新增空选项，不放行B配置改变。
if ~isfield(old,'stageBTikhonovPriorScaleByGroupSize')
    old.stageBTikhonovPriorScaleByGroupSize=[];
end
if ~isfield(old,'stageCBurnerCoordinateSource')
    old.stageCBurnerCoordinateSource='baseline';
end
if ~isfield(old,'stageCCoordinatePolicy')
    old.stageCCoordinatePolicy='schedule_reanchor';
end
if ~isfield(old,'stageCOrdinatePolicy')
    old.stageCOrdinatePolicy='group_average';
end
old=rmfield(old,intersect(fieldnames(old),allowed));
new=rmfield(new,intersect(fieldnames(new),allowed));
assert(isequaln(orderfields(old),orderfields(new)), ...
    'SHT:SteadyAdaptV2:StageCReuseOptions','除D正则强度、迭代预算、信赖域方式及输出设置外，配置发生改变。');
a=source.identity.codeArtifacts;b=code.assets;
assert(isequal(a.name,b.name),'SHT:SteadyAdaptV2:StageCReuseCode','代码依赖集合改变。');
changed=a.sha256~=b.sha256;
% 本接口只增加原D入口的A/B/C复用途径，核心数值算法未变；记录这个例外。
assert(all(ismember(a.name(changed),"sht_steady_model_adapt_v2_common.m")), ...
    'SHT:SteadyAdaptV2:StageCReuseCode','除复用入口以外的代码依赖改变，必须重算A/B/C。');
reuse=struct('used',true,'sourceRunId',source.runId, ...
    'sourceDeterministicContractHash',source.deterministicContractHash, ...
    'changedCodeArtifacts',a(changed,:), ...
    'trainingAndRuntimeUnchanged',true,'parameterGroupsAndWeightsUnchanged',true, ...
    'allowedOptionChanges',{allowed});
end

function options = local_default_options(route)
% 所有可调数值集中在入口配置中，避免求解器内部出现不可追溯常数。
route = local_validate_route(route);
options = struct();
options.route = route;
options.modelMode = 1;
options.includeTC24FlowResidual = true;
options.tc24FlowEngineeringScale = .20; % kg/s，只用于三部件间接流量辅助项
options.clusterSpan = 0.020;
% 当前约六个工况组对应的理想平均间距约为全跨度的20%。相邻证据节点若
% 小于全跨度的5%，通常已不足以稳定支撑独立线性插值段，应合并。
options.nodeMergeFraction = 0.05;
options.nodeMergeAbsolute = 1e-8;
options.nodeMergeRelativeFloor = 1e-3;
% 近节点纵坐标差异超过一个组内工程先验标准差时给出警告，但仍按
% 信息权重平均并继续执行，交由后续全工况联合微调检验其影响。
options.nodeMergeConflictSigmaMultiplier = 1.0;
% TC24新节点机制显式启用；旧六部件/历史对照保持原默认口径。
options.adaptiveEvidenceNodes = false;
options.nodeAdaptiveSpanFraction = 0.02;
options.nodeSpeedAbsoluteSpacing = 0.01;
options.nodePressureRatioRelativeSpacing = 0.01;
options.nodeFlowRelativeSpacing = 0.01;
% 固定参考只由TC24显式启用；其他阶段保持既有行为。参考轴独立于训练集。
options.nodeReferencePolicy = 'training_span_legacy';
options.nodeEngineeringReference = struct();
options.nodePressureRatioSpanFraction = 0.05;
options.nodeFlowSpanFraction = 0.15;
options.nodeFlowDesignFloorFraction = 0.01;
options.nodeFuelSpanFraction = 0.05;
options.burnerAutomaticNodes = true;
options.burnerSelectionStandardErrors = 1;
% 首次C构造燃烧室曲线的坐标来源。group_corrected只读取本轮B的
% 已接受回放，不增加DLL调用；其余曲线保持原流程，C后仍更新全局坐标。
options.stageCBurnerCoordinateSource = 'baseline';
% R037测试1：全部发动机曲线从B最终常值模型取得坐标，C只构造一次。
% 缺省保留历史流程；该选项不改变纵坐标算法、燃油测量坐标或D更新。
% group_corrected_reanchor在相同B坐标起点上，复用原C规则重构一次。
options.stageCCoordinatePolicy = 'schedule_reanchor';
% R039测试2：固定几何节点，拟合曲线在每个B组的平均值；默认仍用原方法。
options.stageCOrdinatePolicy = 'group_average';
options.stageDCoordinatePolicy = 'legacy';
options.stageDCoordinateIntervalThreshold = 0.25;
options.stageDCoordinateOutsideThreshold = 0.02;
options.stageDCoordinateReserveIterations = 2;
options.steadySolver = 'matlab';
options.steadyUseMeasuredPower = false;
options.shaftLoadInputMode = 0; % 旧结果默认功率接口；TC24瞬态路线显式选择1。
options.maxModelResidual = 1e-2;
options.maxIterationA = 12;
options.maxIterationGroup = 4;
% 阶段D最多执行10次非线性迭代。M3每次迭代都在当前真实执行节点处
% 重新计算完整中心差分Jacobian，因此不再设置独立的“重新线性化次数”
% 上限。收敛和最大迭代次数是正常终止条件，线性预测误差只保留诊断。
options.maxIterationRefine = 10;
options.initialLambda = 1e-2;
options.costRelativeTolerance = 1e-4;
options.stepRelativeTolerance = 1e-3;
options.figureVisible = 'off';
% 业务适配仅影响文件与事件，不参与残差、正则化或收敛判断。
options.outputDirectory = '';
options.progressCallback = [];
options.plotEnabled = true;
options.verbose = true;
options.randomSeed = 20260820;
options.saveStampedResult = true;
% 专项参数扫描应保存各自不可变MAT run，但不得覆盖固定Excel
% 和内部latest MAT。正式入口保持true；扫描入口显式设为false。
options.publishLatest = true;
% 实际交付辨识只读取训练集。历史专项对照如需在同一运行中评价测试集，
% 必须显式打开evaluateTestSet并给出testFile。
options.trainingFile = '';
options.testFile = '';
options.evaluateTestSet = false;
options.inletBoundaryMode = 4;
options.pt1TruthFile = '';
options.outputTag = '';
options.runId = '';
options.stageAOnly = false;
% 瞬态时刻路径完成测试集回放后，额外用各测试点的瞬态共同工作解
% 初始化稳态求解，检验同一组参数对整机稳态平衡和两轴转速的预测能力。
options.evaluateSteadyTestFromTransient = true;
% 正式辨识和正式UQ保持C端RunOneStep原求解口径。该开关只允许专项
% 诊断调用稳健七维Newton，以区分参数不可行与C端Newton未收敛。
options.useRobustTransientFallback = false;
% 稳态模型以Mkp/Mkg为外部扭矩边界，Newton每次残差计算按候选转速
% 实时换算功率。瞬态时刻模型的Np/Ng是已测状态，仍使用该时刻固定功率。
if strcmp(route, 'steady')
    options.steadyLoadBoundaryMode = 'torque';
else
    options.steadyLoadBoundaryMode = 'fixed_power';
end
% Np合理分支只约束稳态共同工作求根，不裁剪输出、不进入残差。训练点
% 可用自身实测Np识别根；测试和独立预测只能使用训练功率曲线给出的先验。
options.steadyNpBranchEnabled = true;
options.steadyNpBranchStrictResidual = 1e-7;
options.steadyNpBranchAdaptiveRetry = true;
% 训练阶段的零修正模型尚可与测量Np相差约10%。该宽门只排除离散的
% 错误数学根，不能使用测试预测的窄容许带，否则会把初始模型误差当失败。
options.steadyNpTrainingBranchRelativeHalfWidth = 0.20;
options.steadyNpSelectionPolicy='first_inside';
options.steadyNpAllowOutsideConstantInitialization=false;
options.steadyNpBranchPriorOptions = struct( ...
    'sigmaMultiplier', 3.0, ...
    'minimumRelativeHalfWidth', 0.03, ...
    'maximumRelativeHalfWidth', 0.08);
options.includePt2Residual = false;
options.estimateInletPressureLoss = false;
options.stageARegularizationMethod = 'tsvd';
% 阶段A采用Tikhonov时，对10个发动机参数和1个燃油偏置的工程先验
% 标准差统一缩放。该倍率只改变统计正则强度，不改变LM数值阻尼。
options.stageATikhonovPriorScale = 1.0;
% TSVD首选直接配置“截断个数”。保留个数字段仅用于兼容历史入口；
% 非空时由它覆盖截断个数，并由待估参数总数反算实际截断个数。
options.stageATsvdTruncatedCount = 5;
options.stageATsvdRetainedCount = [];
% TSVD只允许严格截断伪逆：保留方向使用1/sigma，截断方向置零。
% 若求解不稳定，应减少保留奇异方向数，不得引入阻尼TSVD。
options.stageATsvdStepMode = 'direct_inverse';
% 阶段B保留两种正式方法：
%   tikhonov  以阶段A为先验中心的软约束方法；
%   tsvd      逐轮更新SVD子空间，保留方向直接逆、截断方向置零。
options.stageBRegularizationMethod = 'tikhonov';
% 阶段B采用Tikhonov时，缩放当前参数字典（含燃油偏置）的先验标准差。
% TC24为11个发动机参数加1个燃油偏置；小于1增强正则，不改变LM数值阻尼。
options.stageBTikhonovPriorScale = 0.75;
% 留空保持旧统一尺度。二元向量按[单工况, 多工况]选择，不改变参数中心。
options.stageBTikhonovPriorScaleByGroupSize = [];
% r=1...6扫描表明，保留5个方向时训练集和两类测试集预测最均衡。
options.stageBTsvdRetainedCount = 5;
% 阶段D在Stage C调度曲线基础上联合估计10个健康曲线整体偏移和
% 1个燃油偏置曲线整体偏移。Tikhonov保留原实现；TSVD仅使用数据
% 雅可比，保留方向直接逆、截断方向严格置零。
% A/B仍是11个常值物理坐标，但统一采用严格正负中心差分。只有阶段D
% 的actual_execution_nodes参数化称为M3；旧11维曲线偏移仅供对照。
options.constantJacobianMethod = 'strict_central';
options.stageDParameterization = 'actual_execution_nodes';
options.stageDJacobianMethod = 'node_central_full';
options.stageDRegularizationMethod = 'tikhonov';
options.stageDTikhonovPriorScale = 1.0;
% r=1...11扫描及专项稳定性检查表明，保留6个方向在参数恢复、输出
% 泛化和条件数之间更均衡；正式入口采用该值，Tikhonov仍可切换对照。
options.stageDTsvdRetainedCount = 6;
% 阶段D稳定性检查接口。差分倍率只缩放阶段D物理参数差分步长；
% 初值为空时从零偏移开始，非空时必须提供全部11个整体偏移量。
options.stageDDifferenceStepScale = 1.0;
options.stageDInitialOffset = [];
% M3实际采用的正则强度由用户显式配置。稳态路径暂定默认0.05；
% 瞬态时刻路径经完整非线性路线复测后默认0.20：它是候选集中最弱且
% 通过最终点新Jacobian驻点审核的正则强度。
% 候选集仍逐项应用
% 完整Tikhonov解并精确回放，用于给出GCV推荐值，但GCV不再替用户
% 改写实际采用值；不允许全局alpha或线搜索。只有显式选择受控的
% 非线性全局化方法时，才允许使用与物理先验强度分离的LM算法阻尼。
if strcmp(route, 'steady')
    options.stageDM3RegularizationStrength = 0.05;
else
    options.stageDM3RegularizationStrength = 0.20;
end
options.stageDM3RegularizationCandidates = ...
    [0.05, 0.10, 0.20, 0.50, 1, 2, 5, 10, 20, 50, 100];
% M3非线性全局化方式。none保留原始完整局部解路线；
% regularized_trust_region使用精确DLL总目标降低比管理算法阻尼；
% regularizing_lm_inexact_newton按照增广线性化残差收缩准则选择阻尼，
% 再用精确DLL总目标作安全校核。两类阻尼均不改变物理先验正则强度。
options.stageDM3GlobalizationMethod = 'none';
% 为空时只使用stageDM3RegularizationStrength。非空时按给定顺序
% 连续求解；所有层始终共用同一Stage-C先验中心，上一层只提供初值。
options.stageDM3ContinuationRegularizationStrengths = [];
options.stageDM3TrustAcceptanceRatio = 0.10;
options.stageDM3TrustPoorRatio = 0.25;
options.stageDM3TrustGoodRatio = 0.75;
options.stageDM3TrustDampingIncreaseFactor = 4.0;
options.stageDM3TrustDampingDecreaseFactor = 0.25;
options.stageDM3TrustInitialDamping = 0;
options.stageDM3TrustMinimumDamping = 1e-8;
options.stageDM3TrustMaximumDamping = 1e8;
options.stageDM3TrustMaximumTrials = 12;
options.stageDM3TrustStationarityTolerance = 1e-3;
% 无论是否启用信赖域，正式收敛都必须在最终参数点重新计算完整
% Jacobian，并以该新Jacobian检查有界正则化目标的一阶最优性。
options.stageDM3FinalStationarityTolerance = 1e-3;
% 正则化LM非精确Newton准则。rho指定一次线性化步后保留的增广残差
% 比例；内层只做矩阵运算，只有选定的mu才进入精确DLL回放。
options.stageDM3InexactNewtonResidualRatio = 0.70;
options.stageDM3InexactNewtonRatioTolerance = 1e-3;
options.stageDM3InexactNewtonDampingIncreaseFactor = 4.0;
options.stageDM3InexactNewtonMinimumDamping = 1e-10;
options.stageDM3InexactNewtonMaximumDamping = 1e8;
options.stageDM3InexactNewtonMaximumSearchIterations = 40;
options.stageDM3InexactNewtonMaximumExactSafeguardTrials = 10;
options.stageDM3InexactNewtonStationarityTolerance = 1e-3;
% 与现行节点UQ相同的组内相关先验语义，便于后续概率合同无歧义绑定。
options.stageDM3NodePriorCommonCorrelation = 0.60;
options.stageDM3NodePriorCorrelationLength = 0.35;
options.stageDM3NodePriorIndependentFraction = 0.05;
options.stageDM3FuelPriorCommonCorrelation = 0.80;
options.stageDM3FuelPriorCorrelationLength = 0.40;
options.stageDM3FuelPriorIndependentFraction = 0.05;
options.stageDM3BatchSize = 16;
options.stageDM3StabilityNodeCount = 3;
options.stageDM3StabilityRelativeTolerance = 0.25;
options.stageDM3StabilityPolicy = 'error';
options.stageDSteadyLocalBranch = false;
options.stageDSteadyLocalBranchHalfWidth = 0.05;
options.saveStageCDevelopmentCheckpoint = false;
% 线性预测误差衡量本轮Jacobian的局部预测质量，仅用于结果诊断；
% 不再作为继续迭代、候选资格或正式验收的硬门。
options.stageDM3LinearPredictionRelativeTolerance = 0.10;
options.stageDM3BoxKktRelativeTolerance = 1e-10;
options.stageDM3BoxMaximumIterations = 1000;
% 阶段D第一次联合微调后更新模型坐标。横坐标迁移不属于参数辨识，
% 但它会改变分段线性曲线的查询结果，因此使用由大到小的松弛系数
% 尝试重锚定；仅接受数据代价增幅不超过1%的最大迁移步。
options.stageDReanchorCostIncreaseTolerance = 0.01;
options.stageDReanchorCoefficientChangeFraction = 0.10;
options.stageDReanchorRelaxationFactors = [1, 0.5, 0.25, 0.125, 0.0625];
options.stageDConditionalSecondPass = true;
% 正式入口打开以下门控，专项扫描程序保持关闭以便记录未收敛方案。
options.requireConvergedStages = false;
options.requireValidFinalReplay = false;
% measured表示输入Wf是传感器读数，需要扣除估计偏置；physical_model
% 表示输入已经是发动机模型所需的物理燃油流量，不再应用测量偏置。
options.fuelInputSemantics = 'measured';
% 残差权重只改变观测误差度量，不改变参数先验、TSVD保留数或各阶段
% 求解流程。fixed_covariance供外层输出误差松弛循环传入本轮固定协方差；
% 协方差只能在一次完整A/B/D内层优化结束后更新，不能在高斯-牛顿迭代中变权。
options.residualWeightingMethod = 'engineering_scale';
% none表示在物理量坐标中直接白化；design_reference表示先按冻结
% 设计参考值无量纲化，再对经过同一坐标变换的协方差白化。两种写法
% 数学上是同一二次型，本开关用于专项数值等价性验证。
options.residualNormalizationMode = 'none';
options.residualWindowSampleCount = 201;
options.residualCovarianceEigenvalueFloor = 1e-8;
options.residualCovarianceOverride = [];
options.residualCovarianceSource = '';
% 输出误差协方差外层交替时，用上一次内层解暖启动A和各组B。默认留空，
% 因而不改变正式02/03入口从零修正开始的既有行为。
options.stageAInitialValue = [];
options.stageBInitialValueByGroup = [];
end

function result = local_run(route, options, stageCSource, prepareOnly)
% 第三个参数仅用于明确授权的D正则化试验，复用同一路径已冻结的A/B/C。
% 仍执行原正式D1、坐标更新、D2、最终回放及交付流程，不复制第二套求解器。
if nargin<3,stageCSource=[];end
if nargin<4,prepareOnly=false;end
stageCReuse=struct('used',false);
route = local_validate_route(route);
if nargin < 2 || isempty(options)
    options = local_default_options(route);
else
    options = local_complete_options(options, route);
end
rng(options.randomSeed, 'twister');
runTimer = tic;
phaseTimer = tic;

paths = local_paths(options);
local_progress(options,'initialization',0,0);
codeSnapshotBefore = local_deterministic_code_snapshot(paths, route);
trainingSnapshotBefore = local_source_file_snapshot(paths.trainingFile);
[trainingData, testData] = local_read_input_tables(paths, options);
trainingSnapshotAfterRead = local_source_file_snapshot(paths.trainingFile);
local_assert_source_file_snapshot_equal(trainingSnapshotBefore, ...
    trainingSnapshotAfterRead, '训练Excel读取期间');
testDataAvailable = options.evaluateTestSet && ~isempty(testData);
truthInput = struct('used', false, 'sourceFile', "", ...
    'sourceColumn', "", 'pointCount', 0);
if options.inletBoundaryMode == 1 && options.modelMode ~= 0
    [trainingData, testData, truthInput] = local_attach_pt1_truth( ...
        trainingData, testData, paths, options);
elseif ~ismember(options.inletBoundaryMode, [1, 2, 4, 5])
    error('SHT:SteadyAdaptV2:UnsupportedInletBoundaryMode', ...
        ['第二轮稳态辨识公共内核仅支持模式1（Pt1/Tt1直接输入对照）' ...
         '、模式2（Pamb/Tamb/Mach环境输入）或模式4' ...
         '（实测Pt2直接输入），以及模式5（稀疏飞参输入），当前为%d。'], ...
         options.inletBoundaryMode);
end
[trainingData, testData, npBranchPrior] = ...
    local_prepare_np_branch_data(trainingData, testData, options);
parameters = local_parameter_definition(options);

cfg = local_engine_config(options);
runtimeSnapshotBefore = local_runtime_identity_snapshot(paths, cfg);
engine = sht_engine_open(cfg.engine);
cleanupObject = onCleanup(@() sht_engine_close(engine));
timing = struct();
timing.dataAndInitializationSeconds = toc(phaseTimer);

wfDesign = cfg.engine.initial.Wf0;
scales = local_residual_scales(route, cfg, trainingData, options);
zeroModel = local_constant_model(parameters, zeros(height(parameters), 1), 0);

if options.verbose
    fprintf('\n=== %d部件稳态修正系数辨识：%s ===\n', ...
        3+3*options.modelMode,local_route_label(route));
    fprintf('训练点：%d，嵌入测试点：%d，设计点Wf：%.9g kg/s\n', ...
        height(trainingData), height(testData), wfDesign);
    if ~testDataAvailable
        fprintf('参数辨识未读取测试集；测试验证由独立交付入口执行。\n');
    end
end

% 零修正回放给出物理调度坐标；分组另由实测Ng/Tt1确定，不读取真值资产。
local_progress(options,'baseline_and_grouping',0,0);
phaseTimer = tic;
[preparationIdentity,preparationHash]=local_preparation_identity( ...
    route,options,paths,codeSnapshotBefore,runtimeSnapshotBefore);
prepared=[];
if isfield(options,'preparedInput')&&~isempty(options.preparedInput)
    saved=load(options.preparedInput,'preview');prepared=saved.preview;
    assert(strcmp(prepared.schemaVersion,'TC24_PREPARED_V1')&& ...
        strcmp(prepared.identityHash,preparationHash), ...
        'TC24:Preview:IdentityMismatch','预览的数据、配置、源码或运行包已改变，请重新准备。');
end
if isempty(prepared)
[baselineTraining, baselineTrainingValid] = local_evaluate_dataset( ...
    route, engine, cfg, trainingData, zeroModel, options);
[baselineTest, baselineTestValid, baselineTestDiagnostic] = local_evaluate_dataset( ...
    route, engine, cfg, testData, zeroModel, options);
if ~baselineTrainingValid
    disp(baselineTraining(:, {'point_id','return_code','converge_tag', ...
        'max_model_residual','error_message'}));
    error('SHT:SteadyAdaptV2:BaselineTrainingFailure', ...
        '零修正模型不能完成全部训练工况回放，禁止继续参数估计。');
end
% 分组是试车数据本身的属性，不应随稳态/瞬态回放路径改变。AC与CC
% 共用高压轴，且进气道近似绝热，因此用实测Ng和Tt1构造相对换算
% 转速。模型内部AC换算转速仍用于各调度曲线的实际横坐标。
measuredAcCorrectedSpeed = local_measured_ac_corrected_speed( ...
    trainingData, cfg);
groups = local_cluster_by_ac_speed( ...
    trainingData, measuredAcCorrectedSpeed, options.clusterSpan);
weighting = local_residual_weighting( ...
    route, trainingData, baselineTraining, scales, options);
else
    baselineTraining=prepared.baselineTraining;baselineTrainingValid=prepared.baselineTrainingValid;
    baselineTest=prepared.baselineTest;baselineTestValid=prepared.baselineTestValid;
    baselineTestDiagnostic=prepared.baselineTestDiagnostic;
    measuredAcCorrectedSpeed=prepared.measuredAcCorrectedSpeed;
    groups=prepared.groups;weighting=prepared.weighting;
end
timing.baselineAndClusteringSeconds = toc(phaseTimer);
preparation=struct('schemaVersion','TC24_PREPARED_V1','route',route, ...
    'identity',preparationIdentity,'identityHash',preparationHash, ...
    'trainingData',trainingData,'testData',testData,'groups',groups, ...
    'baselineTraining',baselineTraining,'baselineTrainingValid',baselineTrainingValid, ...
    'baselineTest',baselineTest,'baselineTestValid',baselineTestValid, ...
    'baselineTestDiagnostic',baselineTestDiagnostic,'measuredAcCorrectedSpeed',measuredAcCorrectedSpeed, ...
    'weighting',weighting,'scales',scales,'parameters',parameters, ...
    'rngState',rng,'runtimeSeconds',toc(runTimer),'reused',~isempty(prepared), ...
    'dataSemantics','完整有效段均值及逐点实际样本数；不执行历程裁剪', ...
    'nodeSemantics','分组与基准物理坐标已准备；最终节点还依赖B/C修正结果');
if ~isempty(prepared),rng(prepared.rngState);end
if prepareOnly,result=preparation;clear cleanupObject;return;end
if isfield(options,'runControlOptions')&&~isempty(options.runControlOptions)
    runIdentity=struct('preparation',preparationIdentity,'runId',options.runId, ...
        'controlCodeHash',local_file_hash(which('sht_tc24_run_control')));
    options.runControl=sht_tc24_run_control('open',options.runControlOptions,runIdentity);
    local_progress(options,'run_identity_verified',0,0);
    sht_tc24_run_control('boundary',options.runControl,'prepared',preparation);
end

if options.verbose
    if options.modelMode==0, compressorName='HPC'; else, compressorName='AC'; end
    fprintf('%s相对换算转速聚类得到%d组。\n', compressorName, height(groups));
    disp(groups(:, {'group_id','point_ids','point_count', ...
        'ac_ncr_mean','ac_ncr_min','ac_ncr_max'}));
end

% 阶段A：全部训练工况上的常值估计。模式4默认将进气道压损从联合
% 未知量中移除，因此为10个发动机修正系数加1个燃油偏置。
if isempty(stageCSource)
phaseTimer = tic;
[lowerA, upperA, priorSigmaA, diffStepA] = ...
    local_constant_parameter_settings(parameters, wfDesign, 'global');
x0A = zeros(height(parameters) + 1, 1);
if ~isempty(options.stageAInitialValue)
    x0A = options.stageAInitialValue(:);
    if numel(x0A) ~= height(parameters) + 1
        error('SHT:SteadyAdaptV2:BadStageAInitialValue', ...
            '阶段A暖启动长度为%d，预期%d。', ...
            numel(x0A), height(parameters) + 1);
    end
end
priorSigmaAUsed = priorSigmaA;
if strcmp(options.stageARegularizationMethod, 'tikhonov')
    priorSigmaAUsed = priorSigmaA .* options.stageATikhonovPriorScale;
end
[retainedCountA, truncatedCountA, countSourceA] = ...
    local_resolve_stage_a_tsvd_count(options, numel(x0A));
options.stageATsvdRetainedCountResolved = retainedCountA;
options.stageATsvdTruncatedCountResolved = truncatedCountA;
options.stageATsvdCountSource = countSourceA;
objectiveA = @(x) local_constant_objective( ...
    x, route, engine, cfg, trainingData, parameters, weighting, ...
    zeros(size(x0A)), priorSigmaAUsed, options, ...
    options.stageARegularizationMethod);
stageAOptions = options;
stageAUseDirectTsvdInverse = ...
    strcmp(options.stageARegularizationMethod, 'tsvd') && ...
    strcmp(options.stageATsvdStepMode, 'direct_inverse');
if stageAUseDirectTsvdInverse
    % 无阻尼TSVD不使用LM滤波参数；候选步仍需通过边界、有效性和
    % 代价下降线搜索，因此“无阻尼”不等于无约束全步接受。
    stageAOptions.initialLambda = 0;
end
stageA = local_bounded_lm(objectiveA, x0A, lowerA, upperA, ...
    diffStepA, options.maxIterationA, stageAOptions, 'A_all_point_constant', ...
    options.stageARegularizationMethod, priorSigmaAUsed, ...
    retainedCountA, stageAUseDirectTsvdInverse, ...
    options.constantJacobianMethod);
stageA.priorSigmaBaseline = priorSigmaA;
stageA.priorSigmaUsed = priorSigmaAUsed;
stageA.tikhonovPriorScale = options.stageATikhonovPriorScale;
timing.stageASeconds = toc(phaseTimer);

if options.verbose
    fprintf('阶段A：cost %.6g -> %.6g，迭代%d次，停止原因=%s。\n', ...
        stageA.costInitial, stageA.costFinal, stageA.iterationCount, ...
        stageA.stopReason);
    fprintf(['阶段A正则化：%s；信息矩阵维数=%d x %d；' ...
        '待估计参数=%d；保留/截断奇异值=%d/%d。\n'], ...
        upper(stageA.regularizationMethod), ...
        stageA.informationMatrixDimension(1), ...
        stageA.informationMatrixDimension(2), ...
        stageA.parameterCount, stageA.retainedSingularValueCount, ...
        stageA.truncatedSingularValueCount);
    if strcmp(stageA.regularizationMethod, 'tsvd')
        fprintf('阶段A TSVD步长模式：%s。\n', stageA.tsvdStepMode);
    end
end

if options.stageAOnly
    result = local_finish_stage_a_only(route, options, paths, ...
        trainingData, testData, parameters, scales, weighting, engine, cfg, ...
        zeroModel, baselineTraining, baselineTest, ...
        baselineTrainingValid, baselineTestValid, groups, stageA, ...
        timing, runTimer, truthInput, baselineTestDiagnostic);
    clear cleanupObject;
    return;
end

% 阶段B：每个AC转速组内同时估计10个发动机修正系数和1个燃油偏置。
% 两种方法使用同一个阶段A结果作为参考中心，但弱方向的处理不同。
phaseTimer = tic;
groupResults = repmat(local_empty_group_result(), height(groups), 1);
[lowerG, upperG, priorSigmaG, diffStepG] = ...
    local_constant_parameter_settings(parameters, wfDesign, 'group');
for i = 1:height(groups)
    rowMask = local_group_row_indices(groups, i);
    groupData = trainingData(rowMask, :);
    stageBMethod = options.stageBRegularizationMethod;
    priorSigmaGUsed = priorSigmaG;
    priorScaleG = 1;
    if strcmp(stageBMethod, 'tikhonov')
        priorScaleG = local_stage_b_prior_scale(options, height(groupData));
        priorSigmaGUsed = priorSigmaG .* priorScaleG;
    end
    objectiveG = @(x) local_constant_objective( ...
        x, route, engine, cfg, groupData, parameters, weighting, ...
        stageA.x, priorSigmaGUsed, options, stageBMethod);
    stageBOptions = options;
    if strcmp(stageBMethod, 'tsvd')
        stageBOptions.initialLambda = 0;
    end
    labelG = sprintf('B_group_%02d', i);
    x0G = stageA.x;
    if ~isempty(options.stageBInitialValueByGroup)
        if size(options.stageBInitialValueByGroup, 1) ~= height(groups) || ...
                size(options.stageBInitialValueByGroup, 2) ~= numel(stageA.x)
            error('SHT:SteadyAdaptV2:BadStageBInitialValue', ...
                '阶段B暖启动矩阵应为%d x %d。', height(groups), numel(stageA.x));
        end
        x0G = options.stageBInitialValueByGroup(i, :).';
    end
    solveG = local_bounded_lm(objectiveG, x0G, lowerG, upperG, ...
        diffStepG, options.maxIterationGroup, stageBOptions, labelG, ...
        stageBMethod, priorSigmaGUsed, options.stageBTsvdRetainedCount, ...
        strcmp(stageBMethod, 'tsvd'), options.constantJacobianMethod);
    solveG = local_annotate_stage_b_solve( ...
        solveG, stageA.x, priorSigmaGUsed, stageBMethod);
    solveG.tikhonovPriorScale = priorScaleG;
    solveG.priorSigmaBaseline = priorSigmaG;
    solveG.priorSigmaUsed = priorSigmaGUsed;
    groupResults(i).group_id = groups.group_id(i);
    groupResults(i).point_ids = groups.point_ids(i);
    groupResults(i).row_indices = rowMask;
    groupResults(i).x = solveG.x;
    groupResults(i).solve = solveG;
    if options.verbose
        if strcmp(stageBMethod, 'tikhonov')
            fprintf('阶段B %s：%d个工况，先验尺度乘数=%.6g（越小约束越强）。\n', ...
                char(groups.group_id(i)),height(groupData),priorScaleG);
        end
        fprintf(['阶段B %s（%s）：cost %.6g -> %.6g，迭代%d次，' ...
            '保留奇异方向%d个。\n'], ...
            char(groups.group_id(i)), upper(stageBMethod), ...
            solveG.costInitial, solveG.costFinal, solveG.iterationCount, ...
            solveG.retainedSingularValueCount);
    end
end
timing.stageBSeconds = toc(phaseTimer);

% 阶段C：组间等效常值转换为10条健康曲线、1条燃油偏置曲线和h15常值。
local_progress(options,'C_schedule_construction',0,0);
phaseTimer = tic;
coordinatePrediction=local_stage_c_initial_coordinates( ...
    trainingData,baselineTraining,groupResults,options);
scheduleB = local_build_schedule( ...
    trainingData, coordinatePrediction, groups, groupResults, ...
    parameters, wfDesign, options);
if options.inletBoundaryMode == 4 && ~options.estimateInletPressureLoss
    inletDirect = local_build_direct_inlet_pressure_loss( ...
        trainingData, stageA.meta.prediction, table(), table(), options);
    scheduleB = local_attach_direct_inlet_schedule(scheduleB, inletDirect);
end
[scheduleB, predictionBTraining, predictionBTrainingValid, ...
    scheduleStabilization] = local_stabilize_schedule( ...
    scheduleB, stageA.x, route, engine, cfg, trainingData, ...
    parameters, options);
if ~predictionBTrainingValid
    error('SHT:SteadyAdaptV2:NoValidScheduleInitialization', ...
        '组间调度曲线向阶段A回缩后仍不能通过全部训练工况收敛门限。');
end
scheduleStabilization = local_report_schedule_stabilization(scheduleStabilization);
scheduleBBeforeReanchor = scheduleB;
predictionBBeforeReanchor = predictionBTraining;
if strcmp(options.stageCCoordinatePolicy,'group_corrected_once')
    % 坐标与B系数已在构造时逐工况配对。上面的调度回放只检查可行性，
    % 不再用它改变节点；保留原审计字段，明确记录本次未执行C重构。
    stageBReanchor=struct('executed',false,'policy',options.stageCCoordinatePolicy, ...
        'maxNormalizedCoordinateShift',0,'automaticNodes',options.adaptiveEvidenceNodes, ...
        'groupConstantsRefit',false,'stage','C','coordinateSource','B_final_constant_model', ...
        'groupPredictionReuseCount',height(trainingData),'extraCoordinateReplays',0);
else
    % 历史对照：先形成调度模型，再用其运行结果重构横坐标。
    [scheduleB, stageBReanchor, ~] = local_reanchor_schedule( ...
        scheduleB,trainingData,predictionBBeforeReanchor,groups,parameters,options);
    [predictionBTraining, predictionBTrainingValid] = local_evaluate_dataset( ...
        route,engine,cfg,trainingData,local_schedule_model(scheduleB),options);
    stageBReanchor.executed=true;
    stageBReanchor.policy=options.stageCCoordinatePolicy;
    if strcmp(options.stageCCoordinatePolicy,'group_corrected_reanchor')
        stageBReanchor.coordinateSource='C_first_schedule_replay';
        stageBReanchor.initialCoordinateSource='B_final_constant_model';
        stageBReanchor.groupPredictionReuseCount=height(trainingData);
        stageBReanchor.extraCoordinateReplays=height(trainingData);
    end
end
stageBReanchor.dataCostBefore = local_prediction_data_cost( ...
    route, trainingData, predictionBBeforeReanchor, weighting);
stageBReanchor.dataCostAfter = local_prediction_data_cost( ...
    route, trainingData, predictionBTraining, weighting);
stageBReanchor.relativeDataCostChange = ...
    (stageBReanchor.dataCostAfter - stageBReanchor.dataCostBefore) / ...
    max(stageBReanchor.dataCostBefore, eps);
stageBReanchor.replayValid = predictionBTrainingValid;
if ~predictionBTrainingValid
    error('SHT:SteadyAdaptV2:InvalidStageBReanchor', ...
        '阶段B修正模型横坐标重锚定后存在不能合法回放的训练工况。');
end
if options.verbose
    if stageBReanchor.executed
        fprintf(['阶段C调度回放后重构坐标：最大归一化移动=%.6g，' ...
            '数据代价相对变化=%+.4f%%。\n'], ...
            stageBReanchor.maxNormalizedCoordinateShift, ...
            100*stageBReanchor.relativeDataCostChange);
    else
        fprintf(['阶段C：复用%d个工况的B最终修正坐标，一次构造；' ...
            '未执行调度回放后的节点重构，D坐标更新保留。\n'],height(trainingData));
    end
end
timing.stageCSeconds = toc(phaseTimer);
else
    stageCReuse=local_validate_stage_c_reuse(stageCSource,route,options, ...
        trainingSnapshotBefore,runtimeSnapshotBefore,groups,parameters,weighting,codeSnapshotBefore);
    stageA=stageCSource.stageA;groupResults=stageCSource.stageB;
    scheduleB=stageCSource.scheduleBeforeRefine;
    scheduleBBeforeReanchor=stageCSource.stageBScheduleBeforeReanchor;
    predictionBBeforeReanchor=stageCSource.stageBPredictionBeforeReanchor;
    stageBReanchor=stageCSource.stageBReanchor;
    scheduleStabilization=stageCSource.scheduleStabilization;
    [predictionBTraining,predictionBTrainingValid]=local_evaluate_dataset( ...
        route,engine,cfg,trainingData,local_schedule_model(scheduleB),options);
    assert(predictionBTrainingValid,'SHT:SteadyAdaptV2:StageCReuseReplay', ...
        '复用的C阶段曲线不能完成当前训练回放。');
    delta=local_data_residual(route,trainingData,predictionBTraining,weighting)- ...
        local_data_residual(route,trainingData,stageCSource.scheduleBeforeRefineTrainingPrediction,weighting);
    stageCReuse.maximumWeightedReplayDifference=max(abs(delta(:)));
    assert(stageCReuse.maximumWeightedReplayDifference<1e-6, ...
        'SHT:SteadyAdaptV2:StageCReuseReplay','C回放与冻结结果不一致，不能跳过A/B/C。');
    timing.stageASeconds=0;timing.stageBSeconds=0;timing.stageCSeconds=0;
    fprintf('复用%s的A/B/C，不重复辨识；C回放最大加权差=%.3g。\n', ...
        stageCSource.runId,stageCReuse.maximumWeightedReplayDifference);
end

if options.saveStageCDevelopmentCheckpoint && isempty(stageCSource)
    % 仅用于失败定位和D独立试算，不自动恢复、不发布、不代替正式A/B/C。
    checkpointFile=fullfile(paths.middleDataDir,['tc24_',route,'_stageC_debug.mat']);
    save(checkpointFile,'scheduleB','options','trainingSnapshotBefore', ...
        'runtimeSnapshotBefore','stageA','groupResults','stageBReanchor', ...
        'scheduleStabilization','timing','-v7.3');
end

% 阶段D：默认逐执行节点联合微调，再用D1模型
% 更新横坐标。TC24按覆盖/区间移动诊断决定外层重定位，变化后必须
% 再次求解；其他入口保留既有legacy策略，不能混淆两者的行为。
phaseTimer = tic;
stageDPassOptions = options;
stageDPassOptions.maxIterationRefine = options.maxIterationRefine;
stageDMaximumIterations = local_stage_d_iteration_budget(stageDPassOptions);
if strcmp(options.stageDCoordinatePolicy,'diagnostic_outer')
    % 总预算不变，预留少量迭代给必要的外层坐标更新，避免D1耗尽
    % 全部预算后得到一套未经D2拟合的新网格。
    stageDPassOptions.maxIterationRefine=max(1,stageDMaximumIterations- ...
        options.stageDCoordinateReserveIterations);
end
[stageRefinePass1, scheduleD1] = local_run_stage_d_pass( ...
    scheduleB, scheduleB, options.stageDInitialOffset, route, engine, cfg, ...
    trainingData, parameters, weighting, wfDesign, stageDPassOptions, ...
    'D1_all_point_schedule_refine');
predictionD1 = stageRefinePass1.meta.prediction;
[candidateD1Reanchored, ~, stageDReanchor, ...
    candidateInletDirect] = local_guarded_stage_d_reanchor( ...
    scheduleD1, trainingData, predictionD1, groups, parameters, ...
    weighting, route, engine, cfg, options);
remainingStageDIterations = max(0, stageDMaximumIterations - ...
    stageRefinePass1.iterationCount);
reanchorNumericallyUsable = stageRefinePass1.converged && ...
    remainingStageDIterations >= 1 && options.stageDConditionalSecondPass;
if strcmp(options.stageDCoordinatePolicy,'diagnostic_outer')
    reanchorNumericallyUsable=remainingStageDIterations>=1 && options.stageDConditionalSecondPass;
elseif strcmp(options.stageDParameterization, 'actual_execution_nodes')
    reanchorNumericallyUsable = reanchorNumericallyUsable && ...
        stageRefinePass1.boundedSolution.strictlyInterior;
end
if reanchorNumericallyUsable
    scheduleD1Reanchored = candidateD1Reanchored;
    inletDirect = candidateInletDirect;
    stageDReanchor.suppressed = false;
    stageDReanchor.suppressionReason = "";
else
    % 重锚是D1收敛后的坐标一致性处理，不得在D1未收敛、总迭代预算
    % 已耗尽或边界点无法继续中心差分时替换D1精确结果。
    scheduleD1Reanchored = scheduleD1;
    stageDReanchor.accepted = false;
    stageDReanchor.appliedRelaxationFactor = 0;
    stageDReanchor.suppressed = true;
    if ~options.stageDConditionalSecondPass
        stageDReanchor.suppressionReason = "new_grid_requires_second_pass";
    elseif ~stageRefinePass1.converged
        stageDReanchor.suppressionReason = "D1_not_converged";
    elseif remainingStageDIterations < 1
        stageDReanchor.suppressionReason = "stage_D_iteration_budget_exhausted";
    else
        stageDReanchor.suppressionReason = ...
            "D1_boundary_point_cannot_support_strict_central_D2";
    end
end
if strcmp(options.stageDCoordinatePolicy,'diagnostic_outer') && ...
        ~stageDReanchor.accepted && remainingStageDIterations>=1 && ...
        ~stageRefinePass1.converged
    % 没有必要移动坐标时，剩余预算继续优化原网格，不能因预留机制
    % 提前结束本来允许执行的十次迭代。
    stageDReanchor.continueSameGrid=true;
else
    stageDReanchor.continueSameGrid=false;
end
if strcmp(options.stageDParameterization, 'actual_execution_nodes')
    % M3重锚后只要坐标或系数发生变化，就在新节点合同上完整重算
    % Jacobian和正则化解，绝不沿用重锚前的导数。
    stageDReanchor.secondPassTriggered = ...
        options.stageDConditionalSecondPass && stageDReanchor.accepted && ...
        (stageDReanchor.maxNormalizedCoordinateShift > 0 || ...
        stageDReanchor.maxPriorScaledCoefficientChange > 0);
else
    stageDReanchor.secondPassTriggered = ...
        options.stageDConditionalSecondPass && stageDReanchor.accepted && ...
        stageDReanchor.maxPriorScaledCoefficientChange > ...
            options.stageDReanchorCoefficientChangeFraction;
end
stageDReanchor.secondPassTriggered=stageDReanchor.secondPassTriggered || ...
    stageDReanchor.continueSameGrid;

stageRefinePass2 = struct('executed', false);
if stageDReanchor.secondPassTriggered
    if strcmp(options.stageDParameterization, 'actual_execution_nodes')
        % D2仍以Stage-C函数为正则中心，只把它重表达在重锚后的节点坐标上；
        % 禁止把D1估计误当成新的先验均值并累计漂移。
        stageD2PriorCenterSchedule = local_m3_regrid_prior_center( ...
            scheduleB, scheduleD1Reanchored, parameters);
    else
        stageD2PriorCenterSchedule = scheduleD1Reanchored;
    end
    % 延续序列只用于D1获得稳定初值。D2位于重锚后的最终
    % 物理正则强度上，不再重复全部延续路径。
    stageDPassOptions.maxIterationRefine = min( ...
        options.maxIterationRefine, remainingStageDIterations);
    stageDPassOptions.stageDM3ContinuationRegularizationStrengths = ...
        options.stageDM3RegularizationStrength;
    [stageRefinePass2, finalSchedule] = local_run_stage_d_pass( ...
        scheduleD1Reanchored, stageD2PriorCenterSchedule, [], ...
        route, engine, cfg, trainingData, ...
        parameters, weighting, wfDesign, stageDPassOptions, ...
        'D2_conditional_schedule_refine');
    stageRefinePass2.executed = true;
    stageRefine = stageRefinePass2;
else
    finalSchedule = scheduleD1Reanchored;
    stageRefine = stageRefinePass1;
end
stageRefine.passCount = 1 + double(stageDReanchor.secondPassTriggered);
stageRefine.conditionalSecondPassTriggered = ...
    stageDReanchor.secondPassTriggered;
stageRefine.maximumStageDIterations = stageDMaximumIterations;
stageDUsedIterations = stageRefinePass1.iterationCount;
if stageDReanchor.secondPassTriggered
    stageDUsedIterations = stageDUsedIterations + ...
        stageRefinePass2.iterationCount;
end
stageRefine.remainingStageDIterations = max(0, ...
    stageDMaximumIterations - stageDUsedIterations);
if strcmp(options.stageDParameterization, 'actual_execution_nodes')
    stageRefine = local_m3_combine_stage_d_pass_audit( ...
        stageRefine, stageRefinePass1, stageRefinePass2, options);
    stageRefine.reanchorReplayAudit = stageDReanchor.replayAudit;
    stageRefine.totalStageDReplayAudit = struct( ...
        'candidateCount', stageRefine.replayAudit.actualCandidateCount + ...
            stageDReanchor.replayAudit.candidateCount, ...
        'pointReplayCount', stageRefine.replayAudit.pointReplayCount + ...
            stageDReanchor.replayAudit.pointReplayCount, ...
        'solveAttemptCount', stageRefine.replayAudit.solveAttemptCount + ...
            stageDReanchor.replayAudit.solveAttemptCount, ...
        'invalidPointCount', stageRefine.replayAudit.invalidPointCount + ...
            stageDReanchor.replayAudit.invalidPointCount, ...
        'cacheHitCount', stageRefine.replayAudit.cacheHitCount, ...
        'wallSeconds', stageRefine.replayAudit.wallSeconds + ...
            stageDReanchor.replayAudit.wallSeconds);
    finalNodeContract = local_build_m3_node_contract( ...
        finalSchedule, parameters, wfDesign, options);
    finalPriorCenterSchedule = local_m3_regrid_prior_center( ...
        scheduleB, finalSchedule, parameters);
    finalPriorCenterNodeContract = local_build_m3_node_contract( ...
        finalPriorCenterSchedule, parameters, wfDesign, options);
    local_assert_m3_contract_layout( ...
        finalNodeContract, finalPriorCenterNodeContract);
    stageRefine.linearizationNodeContract = stageRefine.nodeContract;
    stageRefine.linearizationNodeContractHash = stageRefine.nodeContractHash;
    stageRefine.nodeContract = finalNodeContract;
    stageRefine.nodeContractHash = finalNodeContract.nodeContractHash;
else
    finalNodeContract = struct();
    finalPriorCenterNodeContract = struct();
end
stageDEveryPassConverged = stageRefinePass1.converged && ...
    (~stageDReanchor.secondPassTriggered || stageRefinePass2.converged);
% D1可以因预留D2预算而结束，并非最终辨识解。D阶段采用最后一次求解
% 的收敛检查；M3已在该解重新计算Jacobian。不能用中间D1否决已收敛D2。
stageDAllConverged = stageRefine.converged;
finalModel = local_schedule_model(finalSchedule);
if options.verbose && strcmp(options.stageDCoordinatePolicy,'diagnostic_outer')
    fprintf(['阶段D横坐标更新：未使用统一回缩；坐标迁移=%d，' ...
        '数据代价相对变化=%+.4f%%，D2=%d。\n'], ...
        stageDReanchor.accepted,100*stageDReanchor.relativeDataCostIncrease, ...
        stageDReanchor.secondPassTriggered);
elseif options.verbose
    fprintf(['阶段D横坐标重锚定：最大归一化移动=%.6g，' ...
        '采用松弛系数=%.6g，接受=%d，数据代价相对变化=%+.4f%%，' ...
        '最大先验尺度化查询变化=%.6g，D2=%d。\n'], ...
        stageDReanchor.maxNormalizedCoordinateShift, ...
        stageDReanchor.appliedRelaxationFactor, stageDReanchor.accepted, ...
        100 * stageDReanchor.relativeDataCostIncrease, ...
        stageDReanchor.maxPriorScaledCoefficientChange, ...
        stageDReanchor.secondPassTriggered);
end
timing.stageDSeconds = toc(phaseTimer);

phaseTimer = tic;
[finalTraining, finalTrainingValid] = local_evaluate_dataset( ...
    route, engine, cfg, trainingData, finalModel, options);
[finalTest, finalTestValid, finalTestDiagnostic] = local_evaluate_dataset( ...
    route, engine, cfg, testData, finalModel, options);

steadyTestFromTransient = local_evaluate_transient_test_as_steady( ...
    route, engine, cfg, trainingData, testData, ...
    zeroModel, finalModel, options, ...
    baselineTestDiagnostic, finalTestDiagnostic);

baselineMetricsTraining = local_dataset_metrics( ...
    route, trainingData, baselineTraining, scales);
baselineMetricsTest = local_dataset_metrics( ...
    route, testData, baselineTest, scales);
finalMetricsTraining = local_dataset_metrics( ...
    route, trainingData, finalTraining, scales);
finalMetricsTest = local_dataset_metrics( ...
    route, testData, finalTest, scales);

parameterTable = local_parameter_result_table( ...
    parameters, stageA.x, groupResults, finalSchedule);
parameterClassTable = local_m3_parameter_class_table( ...
    parameters, finalSchedule, wfDesign);
groupEstimateTable = local_group_estimate_table( ...
    groups, groupResults, parameters, wfDesign);
scheduleNodeTable = local_schedule_node_table(finalSchedule);
predictionTrainingTable = local_prediction_detail_table( ...
    route, trainingData, baselineTraining, finalTraining, scales);
predictionTestTable = local_prediction_detail_table( ...
    route, testData, baselineTest, finalTest, scales);
timing.finalEvaluationSeconds = toc(phaseTimer);
timing.estimationSeconds = toc(runTimer);

result = struct();
if strcmp(options.stageDParameterization, 'actual_execution_nodes')
    result.schemaVersion = ...
        'SHT_STEADY_MODEL_ADAPT_V2_RESULT_V8_M3_BOUNDED_ATOMIC';
else
    result.schemaVersion = ...
        'SHT_STEADY_MODEL_ADAPT_V2_RESULT_V6_RESIDUAL_RELAXATION';
end
result.program = local_route_entry_program(route);
result.route = route;
result.routeLabel = local_route_label(route);
result.createdAt = datestr(now, 31);
result.timing = timing;
result.options = options;
result.options.progressCallback=[];
result.input = struct('trainingFile', paths.trainingFile, ...
    'testFile', paths.testFile, 'trainingPointCount', height(trainingData), ...
    'testPointCount', height(testData), ...
    'testDataAvailable', testDataAvailable, ...
    'inletBoundaryMode', options.inletBoundaryMode, ...
    'residualIncludesPt2', options.includePt2Residual, ...
    'pt1TruthSource', truthInput, ...
    'steadyNpBranchEnabled', options.steadyNpBranchEnabled, ...
    'steadyNpBranchTrainingReference', ...
    'measured_training_Np_for_root_selection_only', ...
    'testDataUsedForInference', false, ...
    'hiddenTruthUsedForInference', false);
result.parameterDefinition = parameters;
result.npBranchPrior = npBranchPrior;
    result.residualScales = scales;
    result.residualWeighting = weighting;
    finalRawResidual = local_raw_data_residual_matrix( ...
        route, trainingData, finalTraining, cellstr(weighting.names));
    result.residualStatistics = local_residual_statistics( ...
        finalRawResidual, weighting);
result.groups = groups;
result.baseline = struct('training', baselineTraining, ...
    'test', baselineTest, 'trainingValid', baselineTrainingValid, ...
    'testValid', local_optional_test_valid(testDataAvailable, baselineTestValid), ...
    'trainingMetrics', baselineMetricsTraining, ...
    'testMetrics', baselineMetricsTest);
result.stageA = stageA;
if stageCReuse.used && options.stageDM3RegularizationStrength == ...
        stageCSource.options.stageDM3RegularizationStrength && ...
        options.maxIterationRefine == stageCSource.options.maxIterationRefine && ...
        options.stageDCoordinateReserveIterations == stageCSource.options.stageDCoordinateReserveIterations && ...
        strcmp(options.stageDM3GlobalizationMethod,stageCSource.options.stageDM3GlobalizationMethod) && ...
        options.stageDM3TrustMaximumTrials == stageCSource.options.stageDM3TrustMaximumTrials && ...
        isequaln(options.stageDM3ContinuationRegularizationStrengths, ...
        stageCSource.options.stageDM3ContinuationRegularizationStrengths)
    % 同lambda、同预算且同数值求解器才应逐值复现。对照允许结果改变，
    % 但上游A/B/C、训练数据、节点规则和模型身份检查仍必须通过。
    oldVector=local_m3_schedule_to_vector(finalNodeContract,stageCSource.finalSchedule);
    newVector=local_m3_schedule_to_vector(finalNodeContract,finalSchedule);
    stageCReuse.sameStrengthMaximumParameterDifference=max(abs(newVector-oldVector));
    stageCReuse.sameStrengthMaximumResidualDifference=max(abs( ...
        local_data_residual(route,trainingData,finalTraining,weighting)- ...
        local_data_residual(route,trainingData,stageCSource.final.training,weighting)));
    assert(stageCReuse.sameStrengthMaximumParameterDifference<1e-7 && ...
        stageCReuse.sameStrengthMaximumResidualDifference<1e-6, ...
        'SHT:SteadyAdaptV2:StageCReuseReproduction', ...
        '相同lambda完整D复现失败：参数差=%.3g，残差差=%.3g，禁止发布。', ...
        stageCReuse.sameStrengthMaximumParameterDifference, ...
        stageCReuse.sameStrengthMaximumResidualDifference);
end
result.stageCReuse = stageCReuse;
result.stageB = groupResults;
result.stageBScheduleBeforeReanchor = scheduleBBeforeReanchor;
result.stageBPredictionBeforeReanchor = predictionBBeforeReanchor;
result.stageBReanchor = stageBReanchor;
result.scheduleBeforeRefine = scheduleB;
result.scheduleBeforeRefineTrainingPrediction = predictionBTraining;
result.scheduleBeforeRefineTrainingValid = predictionBTrainingValid;
result.scheduleStabilization = scheduleStabilization;
result.stageRefine = stageRefine;
result.stageRefinePass1 = stageRefinePass1;
result.stageRefinePass2 = stageRefinePass2;
result.stageDReanchor = stageDReanchor;
result.finalSchedule = finalSchedule;
result.nodeContract = finalNodeContract;
result.finalPriorCenterNodeContract = finalPriorCenterNodeContract;
if strcmp(options.stageDParameterization, 'actual_execution_nodes')
    result.nodeContractHash = finalNodeContract.nodeContractHash;
    result.stageDJacobianMethod = 'node_central_full';
    result.stageDParameterization = 'actual_execution_nodes';
else
    result.nodeContractHash = '';
    result.stageDJacobianMethod = options.stageDJacobianMethod;
    result.stageDParameterization = 'legacy_curve_offsets_auxiliary';
end
result.final = struct('training', finalTraining, 'test', finalTest, ...
    'trainingValid', finalTrainingValid, ...
    'testValid', local_optional_test_valid(testDataAvailable, finalTestValid), ...
    'trainingMetrics', finalMetricsTraining, ...
    'testMetrics', finalMetricsTest);
result.steadyTestFromTransient = steadyTestFromTransient;
result.parameterTable = parameterTable;
% parameterTable保留旧版10个发动机修正量的兼容口径；
% parameterClassTable是M3正式物理类别口径，必须显式含Wf_bias且保留kg/s。
result.parameterClassTable = parameterClassTable;
result.groupEstimateTable = groupEstimateTable;
result.scheduleNodeTable = scheduleNodeTable;
result.predictionTrainingTable = predictionTrainingTable;
result.predictionTestTable = predictionTestTable;
% 模式1联合估计h0，且D1未收敛时不会经过直接压损/重锚赋值分支。
% 从最终曲线取诊断，允许空结构，不能因诊断变量缺省丢弃有效D1结果。
result.inletPressureLossDirect = local_schedule_direct_inlet(finalSchedule);
result.truthWasRead = truthInput.used;
stageBConverged = arrayfun(@(x) x.solve.converged, groupResults);
m3Passed = true;
if strcmp(options.stageDParameterization, 'actual_execution_nodes')
    controlledTrustDamping = strcmp(options.stageDM3GlobalizationMethod, ...
        'regularized_trust_region') && ...
        isfield(stageRefine, 'regularizedTrustRegionUsed') && ...
        stageRefine.regularizedTrustRegionUsed;
    controlledInexactNewtonDamping = ...
        strcmp(options.stageDM3GlobalizationMethod, ...
        'regularizing_lm_inexact_newton') && ...
        isfield(stageRefine, 'regularizingInexactNewtonUsed') && ...
        stageRefine.regularizingInexactNewtonUsed;
    lmDampingIsControlled = ~stageRefine.lmDampingUsed || ...
        ((controlledTrustDamping || controlledInexactNewtonDamping) && ...
        (~isfield(stageRefine, 'uncontrolledLmDampingUsed') || ...
        ~stageRefine.uncontrolledLmDampingUsed));
    m3Passed = finalNodeContract.roundTripPassed && ...
        stageRefine.stepStabilityPassed && ...
        all(stageRefine.perturbationAudit.positive_valid) && ...
        all(stageRefine.perturbationAudit.negative_valid) && ...
        stageRefine.allBoundedSolutionsPassed && ...
        stageRefine.boundedSolution.passed && ...
        stageRefine.fullUpdateAppliedWithoutGlobalScaling && ...
        ~stageRefine.globalAlphaUsed && lmDampingIsControlled;
end
% “统计/数值收敛”和“结果可交付”是两个不同概念。只要最终
% 调度节点可往返重建、数值有限、且DLL回放有效，就应生成唯一
% Excel交付结果；收敛与停止原因仅供下游和工程人员评估结果质量。
deliveryEligible = finalTrainingValid && ...
    (~testDataAvailable || finalTestValid);
if strcmp(options.stageDParameterization, 'actual_execution_nodes')
    deliveryEligible = deliveryEligible && ...
        finalNodeContract.roundTripPassed && ...
        all(isfinite(finalNodeContract.centerVector)) && ...
        all(finalNodeContract.centerVector >= finalNodeContract.lowerBound) && ...
        all(finalNodeContract.centerVector <= finalNodeContract.upperBound);
end
result.acceptance = struct( ...
    'stageAConverged', stageA.converged, ...
    'stageBAllConverged', all(stageBConverged), ...
    'stageBConvergedByGroup', stageBConverged(:), ...
    'stageDConverged', stageDAllConverged, ...
    'stageDEveryPassConverged', stageDEveryPassConverged, ...
    'm3Passed', m3Passed, ...
    'm3NodeRoundTripPassed', strcmp(options.stageDParameterization, ...
        'legacy_curve_offsets_auxiliary') || finalNodeContract.roundTripPassed, ...
    'testDataUsedForInference', false, ...
    'hiddenTruthUsedForInference', false, ...
    'trainingReplayValid', finalTrainingValid, ...
    'testReplayValid', local_optional_test_valid(testDataAvailable, finalTestValid), ...
    'allStagesConverged', stageA.converged && ...
        all(stageBConverged) && stageDAllConverged && m3Passed, ...
    'deliveryEligible', deliveryEligible, ...
    'formalAccepted', stageA.converged && ...
        all(stageBConverged) && stageDAllConverged && m3Passed && ...
        finalTrainingValid && (~testDataAvailable || finalTestValid));

if options.requireConvergedStages && ~result.acceptance.allStagesConverged
    failedGroup = find(~stageBConverged);
    error('SHT:SteadyAdaptV2:FormalStageNotConverged', ...
        ['正式%s路径存在未收敛阶段：A=%d，B未收敛组=%s，D=%d。' ...
         '当前结果不会覆盖正式latest文件。'], ...
        route, stageA.converged, mat2str(failedGroup(:).'), ...
        stageDAllConverged);
end
if options.requireValidFinalReplay && ...
        ~(finalTrainingValid && (~testDataAvailable || finalTestValid))
    error('SHT:SteadyAdaptV2:FormalReplayInvalid', ...
        ['正式%s路径最终训练/测试回放有效性为%d/%s；' ...
         '当前结果不会覆盖正式latest文件。'], ...
        route, finalTrainingValid, ...
        local_optional_test_valid_text(testDataAvailable, finalTestValid));
end

stamp = datestr(now, 'yyyymmdd_HHMMSS');
routeTag = local_result_tag(route, options);
if strcmp(options.stageDParameterization, 'actual_execution_nodes') && ...
        ~contains(routeTag, 'm3')
    error('SHT:SteadyAdaptV2:M3OutputTagRequired', ...
        ['M3正式结果必须使用包含m3的独立outputTag，拒绝覆盖冻结旧路线' ...
         '的无后缀latest结果。']);
end
if isempty(options.runId)
    runId = sprintf('%s_%s', routeTag, stamp);
else
    runId = options.runId;
end
result.runId = runId;
codeSnapshotAfter = local_deterministic_code_snapshot(paths, route);
runtimeSnapshotAfter = local_runtime_identity_snapshot(paths, cfg);
trainingSnapshotAfter = local_source_file_snapshot(paths.trainingFile);
local_assert_identity_snapshot_equal( ...
    codeSnapshotBefore, codeSnapshotAfter, 'MATLAB代码');
local_assert_identity_snapshot_equal( ...
    runtimeSnapshotBefore, runtimeSnapshotAfter, '模型运行资产');
local_assert_source_file_snapshot_equal( ...
    trainingSnapshotBefore, trainingSnapshotAfter, '训练Excel辨识期间');
[result.identity, result.deterministicContractHash] = ...
    local_deterministic_result_identity(paths, cfg, route, options, ...
    weighting, npBranchPrior, result.nodeContractHash, runId, ...
    codeSnapshotBefore, runtimeSnapshotBefore, trainingSnapshotBefore);
runRoot = fullfile(paths.middleDataDir, 'steady_model_adapt_v2_runs');
runDir = fullfile(runRoot, runId);
runMatFile = fullfile(runDir, 'result.mat');
reportRoot = fullfile(paths.reportOutputDir, 'runs');
reportRunDir = fullfile(reportRoot, runId);
deliveryRoot = fullfile(paths.middleDataDir, 'steady_model_2p4_delivery');
deliveryRoute = local_route_tag(route);
% 每条路径只对外发布一个固定Excel。runId位于Manifest中，用于
% 定位不可变MAT侧车；历史运行的迭代、Jacobian和回放证据不再写入Excel。
excelFile = fullfile(deliveryRoot, sprintf( ...
    '2p4_deterministic_%s.xlsx', deliveryRoute));
if exist(runDir, 'file') || exist(runDir, 'dir') || ...
        exist(reportRunDir, 'file') || exist(reportRunDir, 'dir')
    error('SHT:SteadyAdaptV2:RunExists', ...
        '不可变确定性runId已存在，拒绝覆盖：%s。', runId);
end
if ~exist(runRoot, 'dir')
    mkdir(runRoot);
end
if ~exist(reportRoot, 'dir')
    mkdir(reportRoot);
end
if ~exist(deliveryRoot, 'dir')
    mkdir(deliveryRoot);
end
publishId = char(java.util.UUID.randomUUID());
% Worktree与中文目录本身较长；partial目录只需UUID唯一性，不重复runId，
% 避免R2020a的Excel写入链在Windows长路径下失败。
partialLeaf = sprintf('.m3.%s.partial', publishId);
partialRunDir = fullfile(runRoot, partialLeaf);
partialReportDir = fullfile(reportRoot, partialLeaf);
partialDeliveryDir = fullfile(deliveryRoot, partialLeaf);
partialCleanup = onCleanup(@() local_remove_partial_run_dirs( ...
    partialRunDir, partialReportDir, partialDeliveryDir, ...
    runRoot, reportRoot, deliveryRoot, partialLeaf));
if exist(partialRunDir, 'file') || exist(partialRunDir, 'dir') || ...
        exist(partialReportDir, 'file') || exist(partialReportDir, 'dir') || ...
        exist(partialDeliveryDir, 'file') || exist(partialDeliveryDir, 'dir')
    error('SHT:SteadyAdaptV2:PartialRunCreateFailure', ...
        '唯一确定性partial目录已存在。');
end
[createdRun, runMessage] = mkdir(partialRunDir);
[createdReport, reportMessage] = mkdir(partialReportDir);
[createdDelivery, deliveryMessage] = mkdir(partialDeliveryDir);
if ~createdRun || ~createdReport || ~createdDelivery
    error('SHT:SteadyAdaptV2:PartialRunCreateFailure', ...
        '无法创建确定性partial目录：run=%s；report=%s；delivery=%s。', ...
        runMessage, reportMessage, deliveryMessage);
end
latestFile = fullfile(paths.middleDataDir, ...
    ['steady_model_adapt_v2_' routeTag '_latest.mat']);
stampedFile = fullfile(paths.middleDataDir, ...
    ['steady_model_adapt_v2_' routeTag '_' stamp '.mat']);
summaryFile = fullfile(reportRunDir, ...
    ['steady_model_adapt_v2_' routeTag '_' stamp '_summary.md']);
partialRunMatFile = fullfile(partialRunDir, 'result.mat');
partialExcelFile = fullfile(partialDeliveryDir, ...
    sprintf('2p4_deterministic_%s.xlsx', deliveryRoute));
partialSummaryFile = fullfile(partialReportDir, ...
    ['steady_model_adapt_v2_' routeTag '_' stamp '_summary.md']);

result.output = struct('latestMatFile', latestFile, ...
    'stampedMatFile', stampedFile, 'excelFile', excelFile, ...
    'summaryFile', summaryFile, 'runDir', runDir, ...
    'runMatFile', runMatFile, 'reportRunDir', reportRunDir, ...
    'deliveryDir', deliveryRoot, 'deliveryWorkbookFile', excelFile, ...
    'figureFiles', strings(0, 1), ...
    'publishedToLatest', result.acceptance.deliveryEligible && ...
        options.publishLatest, ...
    'publishedToDelivery', result.acceptance.deliveryEligible && ...
        options.publishLatest);
workbookAudit = local_write_result_excel(partialExcelFile, result);
if strcmp(result.stageDParameterization, 'actual_execution_nodes')
    result.workbookVerification = workbookAudit.verification;
    result.output.excelSha256 = workbookAudit.fileSha256;
    result.output.excelSemanticPayloadSha256 = ...
        workbookAudit.semanticPayloadSha256;
    result.output.excelSha256File = [excelFile '.sha256'];
end
plotPaths = paths;
plotPaths.reportOutputDir = partialReportDir;
partialFigureFiles = strings(0,1);
if options.plotEnabled
    try,partialFigureFiles=local_plot_result(result,plotPaths,stamp);
    catch plotError,warning('SHT:SteadyAdaptV2:OptionalPlot','绘图失败但数值结果保留：%s',plotError.message);end
end
figureFiles = strings(numel(partialFigureFiles), 1);
for i = 1:numel(partialFigureFiles)
    [~, figureName, figureExtension] = fileparts(partialFigureFiles(i));
    figureFiles(i) = string(fullfile(reportRunDir, ...
        figureName + figureExtension));
end
result.output.figureFiles = figureFiles;
local_write_summary(partialSummaryFile, result);
local_assert_identity_snapshot_equal(codeSnapshotBefore, ...
    local_deterministic_code_snapshot(paths, route), '正式输出写入期间MATLAB代码');
local_assert_identity_snapshot_equal(runtimeSnapshotBefore, ...
    local_runtime_identity_snapshot(paths, cfg), '正式输出写入期间模型运行资产');
local_assert_source_file_snapshot_equal(trainingSnapshotBefore, ...
    local_source_file_snapshot(paths.trainingFile), '正式输出写入期间训练Excel');
save(partialRunMatFile, 'result', '-v7.3');
loadedPublishedResult = load(partialRunMatFile, 'result');
if ~isfield(loadedPublishedResult, 'result') || ...
        ~strcmp(loadedPublishedResult.result.runId, runId) || ...
        (options.requireConvergedStages && ...
        ~loadedPublishedResult.result.acceptance.formalAccepted)
    error('SHT:SteadyAdaptV2:PartialRunReadbackFailure', ...
        'partial run结果写后读回未通过runId/当前发布合同。');
end
[moved, moveMessage] = movefile(partialReportDir, reportRunDir);
if ~moved
    error('SHT:SteadyAdaptV2:ReportRunAtomicPublishFailure', ...
        '确定性报告run目录原子发布失败：%s。', moveMessage);
end
[moved, moveMessage] = movefile(partialRunDir, runDir);
if ~moved
    local_remove_exact_published_dir(reportRunDir, reportRoot, runId);
    error('SHT:SteadyAdaptV2:MiddleRunAtomicPublishFailure', ...
        '确定性MiddleData run目录原子发布失败：%s。', moveMessage);
end
if result.acceptance.deliveryEligible && options.publishLatest
    % 先发布不可变MAT run，再替换固定Excel，确保Excel中的run_id
    % 在任何时刻都不会指向一个尚未存在的内部侧车。
    local_publish_fixed_delivery_workbook( ...
        partialExcelFile, excelFile, publishId);
    local_save_result_atomic(latestFile, result, publishId);
    if options.saveStampedResult
        local_save_result_atomic(stampedFile, result, publishId);
    end
end
% 专项扫描和不可交付运行的调试证据只保存在MAT与报告目录；
% 阶段Excel只保留每条路径的当前唯一结果。
local_remove_exact_partial_dir( ...
    partialDeliveryDir, deliveryRoot, partialLeaf);
clear partialCleanup;

if options.verbose
    fprintf('\n冻结残差权重：%s；设计点归一化等价性误差=%.3e。\n', ...
        weighting.method, ...
        weighting.normalizationEquivalence.relativeCostDifference);
    fprintf('\n最终训练NRMS：%.6g -> %.6g。\n', ...
        baselineMetricsTraining.overall_nrms, ...
        finalMetricsTraining.overall_nrms);
    if testDataAvailable
        fprintf('嵌入测试NRMS：%.6g -> %.6g；训练/测试回放有效：%d/%d。\n', ...
            baselineMetricsTest.overall_nrms, finalMetricsTest.overall_nrms, ...
            finalTrainingValid, finalTestValid);
    else
        fprintf('训练回放有效：%d；测试集未在辨识入口中读取。\n', ...
            finalTrainingValid);
    end
    local_print_steady_test_from_transient(steadyTestFromTransient);
    fprintf('辨识与验证计算耗时：%.3f s。\n', timing.estimationSeconds);
    if result.acceptance.deliveryEligible && options.publishLatest
        fprintf('当前路径结果已交付（收敛=%d）：\n  %s\n  %s\n', ...
            result.acceptance.allStagesConverged, latestFile, excelFile);
    elseif result.acceptance.deliveryEligible
        fprintf(['专项扫描的不可变MAT run已保存，按配置不替换' ...
            '唯一Excel交付物：\n  %s\n'], runMatFile);
    else
        fprintf(['结果结构或最终回放未满足交付条件，仅保存不可变' ...
            '诊断MAT run：\n  %s\n'], runMatFile);
    end
end

clear cleanupObject;
end

function result = local_finish_stage_a_only(route, options, paths, ...
        trainingData, testData, parameters, scales, weighting, engine, cfg, ...
        zeroModel, baselineTraining, baselineTest, baselineTrainingValid, ...
        baselineTestValid, groups, stageA, timing, runTimer, truthInput, ...
        baselineTestDiagnostic)
% 对照试验只验收全工况常值辨识，不进入分组与调度曲线。
phaseTimer = tic;
nHealth = height(parameters);
stageAModel = local_constant_model( ...
    parameters, stageA.x(1:nHealth), stageA.x(end));
[stageATraining, stageATrainingValid] = local_evaluate_dataset( ...
    route, engine, cfg, trainingData, stageAModel, options);
[stageATest, stageATestValid, stageATestDiagnostic] = local_evaluate_dataset( ...
    route, engine, cfg, testData, stageAModel, options);
steadyTestFromTransient = local_evaluate_transient_test_as_steady( ...
    route, engine, cfg, trainingData, testData, ...
    zeroModel, stageAModel, options, ...
    baselineTestDiagnostic, stageATestDiagnostic);
baselineMetricsTraining = local_dataset_metrics( ...
    route, trainingData, baselineTraining, scales);
baselineMetricsTest = local_dataset_metrics( ...
    route, testData, baselineTest, scales);
stageAMetricsTraining = local_dataset_metrics( ...
    route, trainingData, stageATraining, scales);
stageAMetricsTest = local_dataset_metrics( ...
    route, testData, stageATest, scales);
predictionTrainingTable = local_prediction_detail_table( ...
    route, trainingData, baselineTraining, stageATraining, scales);
predictionTestTable = local_prediction_detail_table( ...
    route, testData, baselineTest, stageATest, scales);
if options.inletBoundaryMode == 4 && ~options.estimateInletPressureLoss
    inletPressureLossDirect = local_build_direct_inlet_pressure_loss( ...
        trainingData, stageATraining, testData, stageATest, options);
else
    inletPressureLossDirect = struct();
end
timing.finalEvaluationSeconds = toc(phaseTimer);
timing.estimationSeconds = toc(runTimer);

parameterTable = table( ...
    [parameters.c_index; NaN], ...
    [parameters.name; "Wf_bias"], ...
    [repmat("health_coefficient", nHealth, 1); "kg/s"], ...
    stageA.x(:), ...
    'VariableNames', {'c_index','name','unit','stageA_estimate'});

result = struct();
result.schemaVersion = ...
    'SHT_STEADY_MODEL_ADAPT_V2_STAGE_A_RESULT_V3_RESIDUAL_WEIGHTING';
result.program = '';
result.route = route;
result.routeLabel = [local_route_label(route) '（仅A阶段）'];
result.createdAt = datestr(now, 31);
result.timing = timing;
result.options = options;
result.input = struct('trainingFile', paths.trainingFile, ...
    'testFile', paths.testFile, 'trainingPointCount', height(trainingData), ...
    'testPointCount', height(testData), ...
    'testDataAvailable', ~isempty(testData), ...
    'inletBoundaryMode', options.inletBoundaryMode, ...
    'residualIncludesPt2', options.includePt2Residual, ...
    'pt1TruthSource', truthInput);
result.parameterDefinition = parameters;
result.residualScales = scales;
result.residualWeighting = weighting;
result.groups = groups;
result.baseline = struct('training', baselineTraining, ...
    'test', baselineTest, 'trainingValid', baselineTrainingValid, ...
    'testValid', local_optional_test_valid(~isempty(testData), baselineTestValid), ...
    'trainingMetrics', baselineMetricsTraining, ...
    'testMetrics', baselineMetricsTest);
result.stageA = stageA;
result.stageAReplay = struct('training', stageATraining, ...
    'test', stageATest, 'trainingValid', stageATrainingValid, ...
    'testValid', local_optional_test_valid(~isempty(testData), stageATestValid), ...
    'trainingMetrics', stageAMetricsTraining, ...
    'testMetrics', stageAMetricsTest);
result.steadyTestFromTransient = steadyTestFromTransient;
result.parameterTable = parameterTable;
result.predictionTrainingTable = predictionTrainingTable;
result.predictionTestTable = predictionTestTable;
result.inletPressureLossDirect = inletPressureLossDirect;
result.truthWasRead = truthInput.used;

stamp = datestr(now, 'yyyymmdd_HHMMSS');
routeTag = local_result_tag(route, options);
latestFile = fullfile(paths.middleDataDir, ...
    ['steady_model_adapt_v2_' routeTag '_latest.mat']);
stampedFile = fullfile(paths.middleDataDir, ...
    ['steady_model_adapt_v2_' routeTag '_' stamp '.mat']);
excelFile = fullfile(paths.reportOutputDir, ...
    ['steady_model_adapt_v2_' routeTag '_' stamp '.xlsx']);
summaryFile = fullfile(paths.reportOutputDir, ...
    ['steady_model_adapt_v2_' routeTag '_' stamp '_summary.md']);
result.output = struct('latestMatFile', latestFile, ...
    'stampedMatFile', stampedFile, 'excelFile', excelFile, ...
    'summaryFile', summaryFile, 'figureFiles', strings(0, 1));

save(latestFile, 'result', '-v7.3');
if options.saveStampedResult
    save(stampedFile, 'result', '-v7.3');
end
writetable(parameterTable, excelFile, 'Sheet', 'stageA_parameters');
writetable(stageA.history, excelFile, 'Sheet', 'stageA_history');
writetable(predictionTrainingTable, excelFile, 'Sheet', 'training');
if result.input.testDataAvailable
    writetable(predictionTestTable, excelFile, 'Sheet', 'test');
end
writetable(scales, excelFile, 'Sheet', 'residual_scales');
local_write_residual_weighting_excel(excelFile, weighting);
local_write_steady_test_from_transient_excel( ...
    excelFile, steadyTestFromTransient);
if ~isempty(fieldnames(inletPressureLossDirect))
    writetable(inletPressureLossDirect.trainingTable, excelFile, ...
        'Sheet', 'inlet_kdp_training');
    if result.input.testDataAvailable
        writetable(inletPressureLossDirect.testTable, excelFile, ...
            'Sheet', 'inlet_kdp_test');
    end
    inletNodeTable = table( ...
        inletPressureLossDirect.entry.xNodes, ...
        inletPressureLossDirect.entry.kNodes, ...
        'VariableNames', {'inlet_corrected_mass_flow','Inlet_K_dP'});
    writetable(inletNodeTable, excelFile, 'Sheet', 'inlet_kdp_nodes');
end
local_write_stage_a_summary(summaryFile, result);

if options.verbose
    fprintf('\nA阶段训练NRMS：%.6g -> %.6g。\n', ...
        baselineMetricsTraining.overall_nrms, ...
        stageAMetricsTraining.overall_nrms);
    if result.input.testDataAvailable
        fprintf('A阶段测试NRMS：%.6g -> %.6g；训练/测试回放有效：%d/%d。\n', ...
            baselineMetricsTest.overall_nrms, stageAMetricsTest.overall_nrms, ...
            stageATrainingValid, stageATestValid);
    else
        fprintf('A阶段训练回放有效：%d；测试集未在辨识入口中读取。\n', ...
            stageATrainingValid);
    end
    local_print_steady_test_from_transient(steadyTestFromTransient);
    fprintf('A阶段辨识与回放耗时：%.3f s。\n', timing.estimationSeconds);
    fprintf('结果：\n  %s\n  %s\n', latestFile, excelFile);
end
end

function local_write_stage_a_summary(filePath, result)
fid = fopen(filePath, 'w', 'n', 'UTF-8');
if fid < 0
    error('SHT:SteadyAdaptV2:SummaryOpenFailure', ...
        '无法写入A阶段摘要：%s。', filePath);
end
cleanupObject = onCleanup(@() fclose(fid));
fprintf(fid, '# 第二轮六部件稳态辨识A阶段对照\n\n');
fprintf(fid, '- 模型路径：%s\n', result.routeLabel);
fprintf(fid, '- 进口边界模式：%d\n', result.input.inletBoundaryMode);
fprintf(fid, '- 残差是否包含Pt2：%d\n', ...
    result.input.residualIncludesPt2);
fprintf(fid, '- Pt1来源：%s\n', result.input.pt1TruthSource.sourceFile);
fprintf(fid, '- 训练点/测试点：%d/%d\n', ...
    result.input.trainingPointCount, result.input.testPointCount);
fprintf(fid, '- cost：%.12g -> %.12g\n', ...
    result.stageA.costInitial, result.stageA.costFinal);
fprintf(fid, '- 迭代次数：%d\n', result.stageA.iterationCount);
fprintf(fid, '- 停止原因：%s\n', result.stageA.stopReason);
fprintf(fid, '- 数值秩/条件数：%d / %.12g\n', ...
    result.stageA.numericalRank, result.stageA.conditionNumber);
fprintf(fid, '- 阶段A正则化：%s\n', ...
    upper(result.stageA.regularizationMethod));
if strcmpi(result.stageA.regularizationMethod, 'tikhonov')
    fprintf(fid, '- Tikhonov先验尺度统一倍率：%.8g\n', ...
        result.options.stageATikhonovPriorScale);
elseif strcmpi(result.stageA.regularizationMethod, 'tsvd')
    fprintf(fid, '- TSVD步长模式：%s\n', ...
        result.stageA.tsvdStepMode);
end
fprintf(fid, '- 信息矩阵维数：%d x %d\n', ...
    result.stageA.informationMatrixDimension(1), ...
    result.stageA.informationMatrixDimension(2));
fprintf(fid, '- 待估计参数个数：%d\n', result.stageA.parameterCount);
fprintf(fid, '- 奇异值保留/截断个数：%d/%d\n', ...
    result.stageA.retainedSingularValueCount, ...
    result.stageA.truncatedSingularValueCount);
if ~isempty(fieldnames(result.inletPressureLossDirect))
    fprintf(fid, '- 进气道压损：逐工况方程反算后线性拟合，设计点值=%.12g\n', ...
        result.inletPressureLossDirect.designValue);
end
fprintf(fid, '- 训练NRMS：%.12g -> %.12g\n', ...
    result.baseline.trainingMetrics.overall_nrms, ...
    result.stageAReplay.trainingMetrics.overall_nrms);
if result.input.testDataAvailable
    fprintf(fid, '- 测试NRMS：%.12g -> %.12g\n', ...
        result.baseline.testMetrics.overall_nrms, ...
        result.stageAReplay.testMetrics.overall_nrms);
else
    fprintf(fid, '- 测试集：未在参数辨识入口中读取\n');
end
if result.steadyTestFromTransient.performed
    fprintf(fid, ['- 测试集额外稳态模型NRMS（以对应瞬态收敛解为初值）：' ...
        '%.12g -> %.12g\n'], ...
        result.steadyTestFromTransient.baseline.steadyMetrics.overall_nrms, ...
        result.steadyTestFromTransient.corrected.steadyMetrics.overall_nrms);
    fprintf(fid, '- 额外稳态模型零修正/阶段A回放有效：%d/%d\n', ...
        result.steadyTestFromTransient.baseline.steadyValid, ...
        result.steadyTestFromTransient.corrected.steadyValid);
end
if result.input.testDataAvailable
    fprintf(fid, '- 训练/测试回放有效：%d/%d\n', ...
        result.stageAReplay.trainingValid, result.stageAReplay.testValid);
else
    fprintf(fid, '- 训练回放有效：%d\n', ...
        result.stageAReplay.trainingValid);
end
clear cleanupObject;
end

function route = local_validate_route(route)
route = lower(string(route));
if ~isscalar(route) || ~ismember(route, ["steady", "transient_instant"])
    error('SHT:SteadyAdaptV2:BadRoute', ...
        '模型路径必须为steady或transient_instant。');
end
route = char(route);
end

function options = local_complete_options(options, route)
defaults = local_default_options(route);
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(options, names{i}) || isempty(options.(names{i}))
        options.(names{i}) = defaults.(names{i});
    end
end
options.route = route;
if ~isscalar(options.inletBoundaryMode) || ...
        ~ismember(options.inletBoundaryMode, [1, 2, 4, 5])
    error('SHT:SteadyAdaptV2:BadInletBoundaryMode', ...
        '正式辨识的options.inletBoundaryMode必须为1、2、4或5。');
end
if ~islogical(options.stageAOnly) || ~isscalar(options.stageAOnly)
    error('SHT:SteadyAdaptV2:BadStageAOnly', ...
        'options.stageAOnly必须为逻辑标量。');
end
if ~islogical(options.evaluateSteadyTestFromTransient) || ...
        ~isscalar(options.evaluateSteadyTestFromTransient)
    error('SHT:SteadyAdaptV2:BadSteadyTestSwitch', ...
        'options.evaluateSteadyTestFromTransient必须为逻辑标量。');
end
if ~islogical(options.useRobustTransientFallback) || ...
        ~isscalar(options.useRobustTransientFallback)
    error('SHT:SteadyAdaptV2:BadTransientFallbackSwitch', ...
        'options.useRobustTransientFallback必须为逻辑标量。');
end
loadMode = lower(string(options.steadyLoadBoundaryMode));
if ~isscalar(loadMode) || ~ismember(loadMode, ["fixed_power", "torque"])
    error('SHT:SteadyAdaptV2:BadSteadyLoadBoundaryMode', ...
        'options.steadyLoadBoundaryMode必须为fixed_power或torque。');
end
options.steadyLoadBoundaryMode = char(loadMode);
assert(isscalar(string(options.stageCOrdinatePolicy)) && ...
    ismember(string(options.stageCOrdinatePolicy),["group_average","group_mean_fit"]), ...
    'SHT:SteadyAdaptV2:StageCOrdinatePolicy','未知C阶段纵坐标策略。');
assert(strcmp(options.stageCOrdinatePolicy,'group_average') || ...
    (options.modelMode==0 && options.adaptiveEvidenceNodes), ...
    'SHT:SteadyAdaptV2:StageCOrdinateScope','直接纵坐标拟合仅在TC24自适应节点中启用。');
assert(isscalar(string(options.stageCCoordinatePolicy)) && ...
    ismember(string(options.stageCCoordinatePolicy), ...
    ["schedule_reanchor","group_corrected_once","group_corrected_reanchor"]), ...
    'SHT:SteadyAdaptV2:StageCCoordinatePolicy','未知C阶段坐标策略。');
assert(strcmp(options.stageCCoordinatePolicy,'schedule_reanchor') || ...
    (options.modelMode==0 && options.adaptiveEvidenceNodes && ...
    strcmp(options.stageCBurnerCoordinateSource,'baseline')), ...
    'SHT:SteadyAdaptV2:StageCCoordinateScope', ...
    'B全坐标测试仅适用于TC24自适应节点，不与燃烧室单项坐标试验混用。');
assert(ismember(string(options.steadySolver),["matlab","dll_first"]), ...
    'SHT:SteadyAdaptV2:Solver','steadySolver必须为matlab或dll_first。');
assert(isnumeric(options.shaftLoadInputMode) && isscalar(options.shaftLoadInputMode) && ...
    ismember(options.shaftLoadInputMode,[0,1]), ...
    'SHT:SteadyAdaptV2:LoadMode','shaftLoadInputMode必须为0（功率）或1（扭矩）。');
assert(options.shaftLoadInputMode==0 || (~options.steadyUseMeasuredPower && ...
    strcmp(options.steadyLoadBoundaryMode,'torque')), ...
    'SHT:SteadyAdaptV2:MixedLoadMode','原生扭矩接口不能同时配置固定功率边界。');
assert(ismember(string(options.stageDCoordinatePolicy),["legacy","diagnostic_outer"]), ...
    'SHT:SteadyAdaptV2:CoordinatePolicy','未知D阶段坐标策略。');
assert(ismember(string(options.stageDM3StabilityPolicy),["error","diagnostic"]), ...
    'SHT:SteadyAdaptV2:StabilityPolicy','差分稳定性策略应为error或diagnostic。');
nodeSettings=[options.nodeAdaptiveSpanFraction,options.nodeSpeedAbsoluteSpacing, ...
    options.nodePressureRatioRelativeSpacing,options.nodeFlowRelativeSpacing, ...
    options.nodePressureRatioSpanFraction,options.nodeFlowSpanFraction, ...
    options.nodeFlowDesignFloorFraction,options.nodeFuelSpanFraction, ...
    options.burnerSelectionStandardErrors,options.stageDCoordinateIntervalThreshold, ...
    options.stageDCoordinateOutsideThreshold];
assert(all(isfinite(nodeSettings) & nodeSettings>=0), ...
    'SHT:SteadyAdaptV2:NodeSettings','节点与自动选点参数必须有限且非负。');
assert(ismember(string(options.nodeReferencePolicy), ...
    ["training_span_legacy","fixed_engineering"]), ...
    'SHT:SteadyAdaptV2:NodeReference','未知工程参考范围策略。');
reserve=options.stageDCoordinateReserveIterations;
assert(isnumeric(reserve) && isscalar(reserve) && isfinite(reserve) && ...
    reserve>=0 && reserve==fix(reserve), ...
    'SHT:SteadyAdaptV2:Reserve','D外层预留迭代数必须为非负整数。');
if ~islogical(options.steadyNpBranchEnabled) || ...
        ~isscalar(options.steadyNpBranchEnabled)
    error('SHT:SteadyAdaptV2:BadNpBranchSwitch', ...
        'options.steadyNpBranchEnabled必须为逻辑标量。');
end
if ~isnumeric(options.steadyNpBranchStrictResidual) || ...
        ~isscalar(options.steadyNpBranchStrictResidual) || ...
        ~isfinite(options.steadyNpBranchStrictResidual) || ...
        options.steadyNpBranchStrictResidual <= 0
    error('SHT:SteadyAdaptV2:BadNpBranchResidual', ...
        'options.steadyNpBranchStrictResidual必须为有限正标量。');
end
if ~islogical(options.steadyNpBranchAdaptiveRetry) || ...
        ~isscalar(options.steadyNpBranchAdaptiveRetry)
    error('SHT:SteadyAdaptV2:BadNpBranchRetrySwitch', ...
        'options.steadyNpBranchAdaptiveRetry必须为逻辑标量。');
end
if ~isnumeric(options.steadyNpTrainingBranchRelativeHalfWidth) || ...
        ~isscalar(options.steadyNpTrainingBranchRelativeHalfWidth) || ...
        ~isfinite(options.steadyNpTrainingBranchRelativeHalfWidth) || ...
        options.steadyNpTrainingBranchRelativeHalfWidth <= 0 || ...
        options.steadyNpTrainingBranchRelativeHalfWidth >= 1
    error('SHT:SteadyAdaptV2:BadTrainingNpBranchWidth', ...
        ['options.steadyNpTrainingBranchRelativeHalfWidth必须为' ...
         '(0,1)内有限标量。']);
end
if ~isstruct(options.steadyNpBranchPriorOptions) || ...
        ~isscalar(options.steadyNpBranchPriorOptions)
    error('SHT:SteadyAdaptV2:BadNpBranchPriorOptions', ...
        'options.steadyNpBranchPriorOptions必须为标量结构体。');
end
if ~islogical(options.includePt2Residual) || ...
        ~isscalar(options.includePt2Residual)
    error('SHT:SteadyAdaptV2:BadPt2ResidualSwitch', ...
        'options.includePt2Residual必须为逻辑标量。');
end
if ~islogical(options.estimateInletPressureLoss) || ...
        ~isscalar(options.estimateInletPressureLoss)
    error('SHT:SteadyAdaptV2:BadInletEstimateSwitch', ...
        'options.estimateInletPressureLoss必须为逻辑标量。');
end
weightingMethod = lower(string(options.residualWeightingMethod));
validWeightingMethods = ["engineering_scale", "measurement_covariance", ...
    "fixed_covariance", "hybrid_measurement_model", ...
    "hybrid_correlated_bias"];
if ~isscalar(weightingMethod) || ...
        ~ismember(weightingMethod, validWeightingMethods)
    error('SHT:SteadyAdaptV2:BadResidualWeightingMethod', ...
        '未知残差权重方法：%s。', weightingMethod);
end
options.residualWeightingMethod = char(weightingMethod);
normalizationMode = lower(string(options.residualNormalizationMode));
validNormalizationModes = ["none", "design_reference"];
if ~isscalar(normalizationMode) || ...
        ~ismember(normalizationMode, validNormalizationModes)
    error('SHT:SteadyAdaptV2:BadResidualNormalizationMode', ...
        '未知残差归一化模式：%s。', normalizationMode);
end
options.residualNormalizationMode = char(normalizationMode);
if weightingMethod == "fixed_covariance"
    covariance = options.residualCovarianceOverride;
    if ~isnumeric(covariance) || ~ismatrix(covariance) || ...
            isempty(covariance) || size(covariance, 1) ~= size(covariance, 2) || ...
            any(~isfinite(covariance(:)))
        error('SHT:SteadyAdaptV2:BadResidualCovarianceOverride', ...
            'fixed_covariance必须提供有限非空方阵。');
    end
elseif ~isempty(options.residualCovarianceOverride)
    error('SHT:SteadyAdaptV2:UnexpectedResidualCovarianceOverride', ...
        '只有fixed_covariance方法允许提供residualCovarianceOverride。');
end
if ~isempty(options.residualWindowSampleCount) && (~isnumeric(options.residualWindowSampleCount) || ...
        ~isscalar(options.residualWindowSampleCount) || ...
        ~isfinite(options.residualWindowSampleCount) || ...
        options.residualWindowSampleCount < 1 || ...
        options.residualWindowSampleCount ~= ...
        round(options.residualWindowSampleCount))
    error('SHT:SteadyAdaptV2:BadResidualWindowSampleCount', ...
        '稳态窗口样本数必须为正整数。');
end
    if ~isnumeric(options.residualCovarianceEigenvalueFloor) || ...
        ~isscalar(options.residualCovarianceEigenvalueFloor) || ...
        ~isfinite(options.residualCovarianceEigenvalueFloor) || ...
        options.residualCovarianceEigenvalueFloor <= 0 || ...
        options.residualCovarianceEigenvalueFloor >= 1
        error('SHT:SteadyAdaptV2:BadResidualEigenvalueFloor', ...
            '残差相关矩阵特征值下限必须位于(0,1)内。');
    end
    initialFields = {'stageAInitialValue','stageBInitialValueByGroup'};
    for iInitial = 1:numel(initialFields)
        value = options.(initialFields{iInitial});
        if ~isempty(value) && (~isnumeric(value) || any(~isfinite(value(:))))
            error('SHT:SteadyAdaptV2:BadRelaxationInitialValue', ...
                '%s必须为空或有限数值数组。', initialFields{iInitial});
        end
    end
method = lower(string(options.stageARegularizationMethod));
if ~isscalar(method) || ~ismember(method, ["tsvd", "tikhonov"])
    error('SHT:SteadyAdaptV2:BadStageARegularization', ...
        '阶段A正则化方式必须为tsvd或tikhonov。');
end
options.stageARegularizationMethod = char(method);
if ~isnumeric(options.stageATikhonovPriorScale) || ...
        ~isscalar(options.stageATikhonovPriorScale) || ...
        ~isfinite(options.stageATikhonovPriorScale) || ...
        options.stageATikhonovPriorScale <= 0
    error('SHT:SteadyAdaptV2:BadStageATikhonovPriorScale', ...
        'options.stageATikhonovPriorScale必须为有限正标量。');
end
stageAStepMode = lower(string(options.stageATsvdStepMode));
if ~isscalar(stageAStepMode) || stageAStepMode ~= "direct_inverse"
    error('SHT:SteadyAdaptV2:BadStageATsvdStepMode', ...
        ['options.stageATsvdStepMode只允许direct_inverse。TSVD保留方向' ...
         '必须严格使用1/sigma；若不稳定，应减少保留奇异方向数。']);
end
options.stageATsvdStepMode = char(stageAStepMode);
    stageBMethod = lower(string(options.stageBRegularizationMethod));
validStageBMethods = ["tikhonov", "tsvd"];
if ~isscalar(stageBMethod) || ~ismember(stageBMethod, validStageBMethods)
    error('SHT:SteadyAdaptV2:BadStageBRegularization', ...
        '阶段B正则化方式必须为tikhonov或tsvd。');
end
    options.stageBRegularizationMethod = char(stageBMethod);
    constantJacobianMethod = lower(string(options.constantJacobianMethod));
    if ~isscalar(constantJacobianMethod) || ...
            constantJacobianMethod ~= "strict_central"
        error('SHT:SteadyAdaptV2:BadConstantJacobianMethod', ...
            ['阶段A/B只允许strict_central；它们仍是11维常值物理坐标，' ...
             '不得标记为逐调度节点M3。']);
    end
    options.constantJacobianMethod = char(constantJacobianMethod);
if ~isnumeric(options.stageBTikhonovPriorScale) || ...
        ~isscalar(options.stageBTikhonovPriorScale) || ...
        ~isfinite(options.stageBTikhonovPriorScale) || ...
        options.stageBTikhonovPriorScale <= 0
    error('SHT:SteadyAdaptV2:BadStageBTikhonovPriorScale', ...
        'options.stageBTikhonovPriorScale必须为有限正标量。');
end
% 运行前校核分组尺度，避免到某一组才发现非法配置。
local_stage_b_prior_scale(options, 1);
if ~isnumeric(options.stageBTsvdRetainedCount) || ...
        ~isscalar(options.stageBTsvdRetainedCount) || ...
        ~isfinite(options.stageBTsvdRetainedCount) || ...
        options.stageBTsvdRetainedCount < 1 || ...
        options.stageBTsvdRetainedCount ~= round(options.stageBTsvdRetainedCount)
    error('SHT:SteadyAdaptV2:BadStageBTsvdRetainedCount', ...
        'options.stageBTsvdRetainedCount必须为正整数。');
end
stageDMethod = lower(string(options.stageDRegularizationMethod));
validStageDMethods = ["tikhonov", "tsvd"];
if ~isscalar(stageDMethod) || ~ismember(stageDMethod, validStageDMethods)
    error('SHT:SteadyAdaptV2:BadStageDRegularization', ...
        '阶段D正则化方式必须为tikhonov或tsvd。');
end
    options.stageDRegularizationMethod = char(stageDMethod);
    stageDParameterization = lower(string(options.stageDParameterization));
    validStageDParameterizations = ["actual_execution_nodes", ...
        "legacy_curve_offsets_auxiliary"];
    if ~isscalar(stageDParameterization) || ...
            ~ismember(stageDParameterization, validStageDParameterizations)
        error('SHT:SteadyAdaptV2:BadStageDParameterization', ...
            ['阶段D参数化必须为actual_execution_nodes，或仅供冻结旧路线' ...
             '对照的legacy_curve_offsets_auxiliary。']);
    end
    options.stageDParameterization = char(stageDParameterization);
    stageDJacobianMethod = lower(string(options.stageDJacobianMethod));
    if stageDParameterization == "actual_execution_nodes"
        if stageDJacobianMethod ~= "node_central_full"
            error('SHT:SteadyAdaptV2:BadM3MethodCombination', ...
                ['实际执行节点阶段D必须使用node_central_full。正则化方法' ...
                 '可选择Tikhonov完整解或先验中心化无阻尼TSVD。']);
        end
    elseif ~ismember(stageDJacobianMethod, ...
            ["legacy_one_sided_fallback", "strict_central"])
        error('SHT:SteadyAdaptV2:BadLegacyStageDJacobianMethod', ...
            '辅助旧参数化的差分方式必须为legacy_one_sided_fallback或strict_central。');
    end
    options.stageDJacobianMethod = char(stageDJacobianMethod);
if ~isnumeric(options.stageDTikhonovPriorScale) || ...
        ~isscalar(options.stageDTikhonovPriorScale) || ...
        ~isfinite(options.stageDTikhonovPriorScale) || ...
        options.stageDTikhonovPriorScale <= 0
    error('SHT:SteadyAdaptV2:BadStageDTikhonovPriorScale', ...
        'options.stageDTikhonovPriorScale必须为有限正标量。');
end
if ~isnumeric(options.stageDTsvdRetainedCount) || ...
        ~isscalar(options.stageDTsvdRetainedCount) || ...
        ~isfinite(options.stageDTsvdRetainedCount) || ...
        options.stageDTsvdRetainedCount < 1 || ...
        options.stageDTsvdRetainedCount ~= round(options.stageDTsvdRetainedCount)
    error('SHT:SteadyAdaptV2:BadStageDTsvdRetainedCount', ...
        'options.stageDTsvdRetainedCount必须为正整数。');
end
if ~isnumeric(options.stageDDifferenceStepScale) || ...
        ~isscalar(options.stageDDifferenceStepScale) || ...
        ~isfinite(options.stageDDifferenceStepScale) || ...
        options.stageDDifferenceStepScale <= 0
    error('SHT:SteadyAdaptV2:BadStageDDifferenceStepScale', ...
        'options.stageDDifferenceStepScale必须为有限正标量。');
end
    if ~isempty(options.stageDInitialOffset) && ...
        (~isnumeric(options.stageDInitialOffset) || ...
        ~isvector(options.stageDInitialOffset) || ...
        any(~isfinite(options.stageDInitialOffset(:))))
    error('SHT:SteadyAdaptV2:BadStageDInitialOffset', ...
             'options.stageDInitialOffset必须为空或有限数值向量。');
    end
    lambdaCandidate = options.stageDM3RegularizationCandidates(:).';
    if ~isnumeric(lambdaCandidate) || isempty(lambdaCandidate) || ...
            any(~isfinite(lambdaCandidate) | lambdaCandidate <= 0) || ...
            any(diff(lambdaCandidate) <= 0)
        error('SHT:SteadyAdaptV2:BadM3RegularizationCandidates', ...
            'M3正则强度候选必须是严格递增的有限正向量。');
    end
    options.stageDM3RegularizationCandidates = lambdaCandidate;
    configuredLambda = options.stageDM3RegularizationStrength;
    if ~isnumeric(configuredLambda) || ~isscalar(configuredLambda) || ...
            ~isfinite(configuredLambda) || configuredLambda <= 0
        error('SHT:SteadyAdaptV2:BadM3RegularizationStrength', ...
            'M3用户配置正则强度必须为有限正标量。');
    end
    lambdaTolerance = 64 * eps(max([1, abs(configuredLambda), ...
        abs(lambdaCandidate)]));
    configuredIndex = find(abs(lambdaCandidate - configuredLambda) <= ...
        lambdaTolerance, 1, 'first');
    if isempty(configuredIndex)
        error('SHT:SteadyAdaptV2:M3RegularizationStrengthNotCandidate', ...
            ['M3用户配置正则强度%.8g必须包含在GCV候选集中；' ...
             '请同时更新stageDM3RegularizationCandidates。'], ...
            configuredLambda);
    end
    % 钉到候选表中的同一浮点值，避免结果合同中出现语义相同但字节不同
    % 的正则强度。
    options.stageDM3RegularizationStrength = ...
        lambdaCandidate(configuredIndex);
    globalizationMethod = lower(string(options.stageDM3GlobalizationMethod));
    validGlobalizationMethod = ["none", "regularized_trust_region", ...
        "regularizing_lm_inexact_newton"];
    if ~isscalar(globalizationMethod) || ...
            ~ismember(globalizationMethod, validGlobalizationMethod)
        error('SHT:SteadyAdaptV2:BadM3GlobalizationMethod', ...
            ['options.stageDM3GlobalizationMethod必须为none、' ...
             'regularized_trust_region或' ...
             'regularizing_lm_inexact_newton。']);
    end
    if globalizationMethod ~= "none" && ...
            ~strcmpi(options.stageDRegularizationMethod, 'tikhonov')
        error('SHT:SteadyAdaptV2:M3ControlledLmRequiresTikhonov', ...
            'M3受控LM方法当前只与Tikhonov物理先验目标配套。');
    end
    options.stageDM3GlobalizationMethod = char(globalizationMethod);
    continuation = options.stageDM3ContinuationRegularizationStrengths;
    if isempty(continuation)
        continuation = options.stageDM3RegularizationStrength;
    end
    if ~isnumeric(continuation) || ~isvector(continuation) || ...
            any(~isfinite(continuation(:)) | continuation(:) <= 0)
        error('SHT:SteadyAdaptV2:BadM3ContinuationStrengths', ...
            'M3延续正则强度必须是非空有限正向量。');
    end
    continuation = double(continuation(:).');
    for iContinuation = 1:numel(continuation)
        oneTolerance = 64 * eps(max([1, abs(continuation(iContinuation)), ...
            abs(lambdaCandidate)]));
        oneIndex = find(abs(lambdaCandidate - continuation(iContinuation)) <= ...
            oneTolerance, 1, 'first');
        if isempty(oneIndex)
            error('SHT:SteadyAdaptV2:M3ContinuationStrengthNotCandidate', ...
                ['M3延续正则强度%.8g不在GCV候选表中；' ...
                 '请更新stageDM3RegularizationCandidates。'], ...
                continuation(iContinuation));
        end
        continuation(iContinuation) = lambdaCandidate(oneIndex);
    end
    if abs(continuation(end) - options.stageDM3RegularizationStrength) > ...
            64 * eps(max([1, abs(continuation(end)), ...
            abs(options.stageDM3RegularizationStrength)]))
        error('SHT:SteadyAdaptV2:M3ContinuationFinalStrengthMismatch', ...
            ['M3延续序列的最后一层必须等于' ...
             'stageDM3RegularizationStrength。']);
    end
    options.stageDM3ContinuationRegularizationStrengths = continuation;
    trustPositiveFields = {'stageDM3TrustAcceptanceRatio', ...
        'stageDM3TrustPoorRatio','stageDM3TrustGoodRatio', ...
        'stageDM3TrustDampingIncreaseFactor', ...
        'stageDM3TrustDampingDecreaseFactor','stageDM3TrustMinimumDamping', ...
        'stageDM3TrustMaximumDamping','stageDM3TrustStationarityTolerance', ...
        'stageDM3FinalStationarityTolerance'};
    for iTrust = 1:numel(trustPositiveFields)
        value = options.(trustPositiveFields{iTrust});
        if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || value <= 0
            error('SHT:SteadyAdaptV2:BadM3TrustOption', ...
                'options.%s必须为有限正标量。', trustPositiveFields{iTrust});
        end
    end
    if options.stageDM3TrustAcceptanceRatio >= ...
            options.stageDM3TrustPoorRatio || ...
            options.stageDM3TrustPoorRatio >= ...
            options.stageDM3TrustGoodRatio || ...
            options.stageDM3TrustGoodRatio >= 1
        error('SHT:SteadyAdaptV2:BadM3TrustRatio', ...
            '信赖域比率必须满足0<acceptance<poor<good<1。');
    end
    if options.stageDM3TrustDampingIncreaseFactor <= 1 || ...
            options.stageDM3TrustDampingDecreaseFactor >= 1 || ...
            options.stageDM3TrustMaximumDamping <= ...
            options.stageDM3TrustMinimumDamping
        error('SHT:SteadyAdaptV2:BadM3TrustDampingFactors', ...
            ['信赖域阻尼增大因子必须>1，减小因子必须<1，' ...
             '最大阻尼必须大于最小阻尼。']);
    end
    initialDamping = options.stageDM3TrustInitialDamping;
    if ~isnumeric(initialDamping) || ~isscalar(initialDamping) || ...
            ~isfinite(initialDamping) || initialDamping < 0 || ...
            initialDamping > options.stageDM3TrustMaximumDamping
        error('SHT:SteadyAdaptV2:BadM3TrustInitialDamping', ...
            '信赖域初始算法阻尼必须为有限非负标量且不超上限。');
    end
    if ~isnumeric(options.stageDM3TrustMaximumTrials) || ...
            ~isscalar(options.stageDM3TrustMaximumTrials) || ...
            ~isfinite(options.stageDM3TrustMaximumTrials) || ...
            options.stageDM3TrustMaximumTrials < 1 || ...
            options.stageDM3TrustMaximumTrials ~= ...
            round(options.stageDM3TrustMaximumTrials)
        error('SHT:SteadyAdaptV2:BadM3TrustMaximumTrials', ...
            '每次线性化的信赖域最大候选数必须为正整数。');
    end
    inexactUnitFields = {'stageDM3InexactNewtonResidualRatio', ...
        'stageDM3InexactNewtonRatioTolerance'};
    for iInexact = 1:numel(inexactUnitFields)
        value = options.(inexactUnitFields{iInexact});
        if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || ...
                value <= 0 || value >= 1
            error('SHT:SteadyAdaptV2:BadM3InexactNewtonRatio', ...
                'options.%s必须为(0,1)内有限标量。', ...
                inexactUnitFields{iInexact});
        end
    end
    inexactPositiveFields = { ...
        'stageDM3InexactNewtonDampingIncreaseFactor', ...
        'stageDM3InexactNewtonMinimumDamping', ...
        'stageDM3InexactNewtonMaximumDamping', ...
        'stageDM3InexactNewtonStationarityTolerance'};
    for iInexact = 1:numel(inexactPositiveFields)
        value = options.(inexactPositiveFields{iInexact});
        if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || value <= 0
            error('SHT:SteadyAdaptV2:BadM3InexactNewtonOption', ...
                'options.%s必须为有限正标量。', ...
                inexactPositiveFields{iInexact});
        end
    end
    if options.stageDM3InexactNewtonDampingIncreaseFactor <= 1 || ...
            options.stageDM3InexactNewtonMaximumDamping <= ...
            options.stageDM3InexactNewtonMinimumDamping
        error('SHT:SteadyAdaptV2:BadM3InexactNewtonDamping', ...
            ['非精确Newton阻尼增大因子必须>1，且最大阻尼必须大于' ...
             '最小阻尼。']);
    end
    inexactIntegerFields = { ...
        'stageDM3InexactNewtonMaximumSearchIterations', ...
        'stageDM3InexactNewtonMaximumExactSafeguardTrials'};
    for iInexact = 1:numel(inexactIntegerFields)
        value = options.(inexactIntegerFields{iInexact});
        if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || ...
                value < 1 || value ~= round(value)
            error('SHT:SteadyAdaptV2:BadM3InexactNewtonIterationLimit', ...
                'options.%s必须为正整数。', inexactIntegerFields{iInexact});
        end
    end
    correlationFields = {'stageDM3NodePriorCommonCorrelation', ...
        'stageDM3NodePriorCorrelationLength', ...
        'stageDM3NodePriorIndependentFraction', ...
        'stageDM3FuelPriorCommonCorrelation', ...
        'stageDM3FuelPriorCorrelationLength', ...
        'stageDM3FuelPriorIndependentFraction'};
    for iCorrelation = 1:numel(correlationFields)
        value = options.(correlationFields{iCorrelation});
        if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || ...
                value <= 0 || value >= 1
            error('SHT:SteadyAdaptV2:BadM3PriorCorrelation', ...
                'options.%s必须是(0,1)内有限标量。', ...
                correlationFields{iCorrelation});
        end
    end
    positiveIntegerFields = {'stageDM3BatchSize', ...
        'stageDM3StabilityNodeCount', ...
        'stageDM3BoxMaximumIterations'};
    for iInteger = 1:numel(positiveIntegerFields)
        value = options.(positiveIntegerFields{iInteger});
        if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || ...
                value < 1 || value ~= round(value)
            error('SHT:SteadyAdaptV2:BadM3PositiveInteger', ...
                'options.%s必须为正整数。', positiveIntegerFields{iInteger});
        end
    end
    if ~isnumeric(options.stageDM3StabilityRelativeTolerance) || ...
            ~isscalar(options.stageDM3StabilityRelativeTolerance) || ...
            ~isfinite(options.stageDM3StabilityRelativeTolerance) || ...
            options.stageDM3StabilityRelativeTolerance <= 0
        error('SHT:SteadyAdaptV2:BadM3StabilityTolerance', ...
            'M3的h/h2相对稳定性门限必须为有限正标量。');
    end
    positiveToleranceFields = { ...
        'stageDM3LinearPredictionRelativeTolerance', ...
        'stageDM3BoxKktRelativeTolerance'};
    for iTolerance = 1:numel(positiveToleranceFields)
        value = options.(positiveToleranceFields{iTolerance});
        if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || ...
                value <= 0
            error('SHT:SteadyAdaptV2:BadM3PositiveTolerance', ...
                'options.%s必须为有限正标量。', ...
                positiveToleranceFields{iTolerance});
        end
    end
if ~isnumeric(options.stageDReanchorCostIncreaseTolerance) || ...
        ~isscalar(options.stageDReanchorCostIncreaseTolerance) || ...
        ~isfinite(options.stageDReanchorCostIncreaseTolerance) || ...
        options.stageDReanchorCostIncreaseTolerance < 0
    error('SHT:SteadyAdaptV2:BadStageDReanchorCostTolerance', ...
        '阶段D重锚定数据代价增幅门限必须为有限非负标量。');
end
if ~isnumeric(options.stageDReanchorCoefficientChangeFraction) || ...
        ~isscalar(options.stageDReanchorCoefficientChangeFraction) || ...
        ~isfinite(options.stageDReanchorCoefficientChangeFraction) || ...
        options.stageDReanchorCoefficientChangeFraction < 0
    error('SHT:SteadyAdaptV2:BadStageDReanchorCoefficientTolerance', ...
        '阶段D重锚定查询变化门限必须为有限非负标量。');
end
relaxation = options.stageDReanchorRelaxationFactors(:).';
if ~isnumeric(relaxation) || isempty(relaxation) || ...
        any(~isfinite(relaxation) | relaxation <= 0 | relaxation > 1) || ...
        any(diff(relaxation) >= 0)
    error('SHT:SteadyAdaptV2:BadStageDReanchorRelaxation', ...
        '阶段D重锚定松弛系数必须是位于(0,1]内的严格递减有限向量。');
end
options.stageDReanchorRelaxationFactors = relaxation;
if ~islogical(options.stageDConditionalSecondPass) || ...
        ~isscalar(options.stageDConditionalSecondPass)
    error('SHT:SteadyAdaptV2:BadStageDSecondPassSwitch', ...
        'options.stageDConditionalSecondPass必须为逻辑标量。');
end
logicalOptionNames = {'requireConvergedStages', ...
    'requireValidFinalReplay', 'evaluateTestSet', 'publishLatest'};
for i = 1:numel(logicalOptionNames)
    name = logicalOptionNames{i};
    if ~islogical(options.(name)) || ~isscalar(options.(name))
        error('SHT:SteadyAdaptV2:BadFormalAcceptanceSwitch', ...
            'options.%s必须为逻辑标量。', name);
    end
end
if ~isnumeric(options.stageATsvdTruncatedCount) || ...
        ~isscalar(options.stageATsvdTruncatedCount) || ...
        ~isfinite(options.stageATsvdTruncatedCount) || ...
        options.stageATsvdTruncatedCount < 0 || ...
        options.stageATsvdTruncatedCount ~= round(options.stageATsvdTruncatedCount)
    error('SHT:SteadyAdaptV2:BadTsvdTruncatedCount', ...
        'options.stageATsvdTruncatedCount必须为非负整数。');
end
if ~isempty(options.stageATsvdRetainedCount) && ...
        (~isnumeric(options.stageATsvdRetainedCount) || ...
        ~isscalar(options.stageATsvdRetainedCount) || ...
        ~isfinite(options.stageATsvdRetainedCount) || ...
        options.stageATsvdRetainedCount < 1 || ...
        options.stageATsvdRetainedCount ~= round(options.stageATsvdRetainedCount))
    error('SHT:SteadyAdaptV2:BadTsvdRetainedCount', ...
        '非空的options.stageATsvdRetainedCount必须为正整数。');
end
if options.inletBoundaryMode == 4
    if options.estimateInletPressureLoss
        error('SHT:SteadyAdaptV2:Mode4InletCompensationConflict', ...
            ['模式4已经根据Pt1/Pt2直接反算进气道压损，' ...
             '不得再把Inlet_K_dP放入联合估计。']);
    end
    if options.includePt2Residual
        error('SHT:SteadyAdaptV2:Mode4Pt2ResidualConflict', ...
            '模式4以实测Pt2作为模型输入，Pt2不得同时作为拟合残差。');
    end
end
    options.outputTag = char(string(options.outputTag));
    options.runId = local_scalar_text(options.runId, 'options.runId');
    if ~isempty(options.runId) && isempty(regexp(options.runId, ...
            '^[A-Za-z0-9][A-Za-z0-9_-]*$', 'once'))
        error('SHT:SteadyAdaptV2:BadRunId', ...
            'options.runId只能包含ASCII字母、数字、下划线和连字符。');
    end
options.pt1TruthFile = char(string(options.pt1TruthFile));
options.trainingFile = local_scalar_text(options.trainingFile, ...
    'options.trainingFile');
options.testFile = local_scalar_text(options.testFile, 'options.testFile');
fuelInputSemantics = lower(string(options.fuelInputSemantics));
if ~isscalar(fuelInputSemantics) || ...
        ~ismember(fuelInputSemantics, ["measured", "physical_model"])
    error('SHT:SteadyAdaptV2:BadFuelInputSemantics', ...
        'options.fuelInputSemantics必须为measured或physical_model。');
end
options.fuelInputSemantics = char(fuelInputSemantics);
end

function value = local_scalar_text(value, name)
value = string(value);
if ~isscalar(value)
    error('SHT:SteadyAdaptV2:BadTextOption', ...
        '%s必须是字符向量或字符串标量。', name);
end
value = char(value);
end

function value = local_optional_test_valid(testAvailable, testValid)
if testAvailable
    value = logical(testValid);
else
    value = NaN;
end
end

function value = local_optional_test_valid_text(testAvailable, testValid)
if testAvailable
    value = sprintf('%d', logical(testValid));
else
    value = '未执行';
end
end

function [retainedCount, truncatedCount, source] = ...
        local_resolve_stage_a_tsvd_count(options, parameterCount)
% 将用户入口的截断个数转换为求解器所需的保留个数。历史入口若显式
% 给出保留个数，则保持兼容，但同一次运行只采用一种口径。
if isempty(options.stageATsvdRetainedCount)
    truncatedCount = options.stageATsvdTruncatedCount;
    retainedCount = parameterCount - truncatedCount;
    source = 'truncated_count';
else
    retainedCount = options.stageATsvdRetainedCount;
    truncatedCount = parameterCount - retainedCount;
    source = 'retained_count_compatibility_override';
end
if retainedCount < 1 || retainedCount > parameterCount || ...
        truncatedCount < 0 || truncatedCount >= parameterCount
    error('SHT:SteadyAdaptV2:BadResolvedTsvdCount', ...
        ['阶段A共有%d个待估参数，TSVD必须至少保留1个方向；' ...
         '当前请求保留/截断=%d/%d。'], ...
        parameterCount, retainedCount, truncatedCount);
end
end

function label = local_route_label(route)
if strcmp(route, 'steady')
    label = '稳态模型路径';
else
    label = '瞬态时刻模型路径';
end
end

function tag = local_route_tag(route)
if strcmp(route, 'steady')
    tag = 'steady';
else
    tag = 'transient_instant';
end
end

function program = local_route_entry_program(route)
% 正式结果在公共内核发布前即冻结入口身份，入口返回后不得再覆写MAT。
if strcmp(route, 'steady')
    program = 'Start_SteadyModelAdapt_V2_02_SteadyModelParameterEstimation';
else
    program = 'Start_SteadyModelAdapt_V2_03_TransientInstantEstimation';
end
end

function tag = local_result_tag(route, options)
tag = local_route_tag(route);
suffix = lower(strtrim(options.outputTag));
if isempty(suffix)
    return;
end
suffix = regexprep(suffix, '[^a-z0-9_]+', '_');
suffix = regexprep(suffix, '^_+|_+$', '');
if isempty(suffix)
    error('SHT:SteadyAdaptV2:BadOutputTag', ...
        'options.outputTag没有可用的ASCII字母或数字。');
end
tag = [tag '_' suffix];
end

function [identity,hash]=local_preparation_identity(route,options,paths,code,runtime)
% 路径只用于定位，内容才决定能否复用；不包含回调、输出目录或活句柄。
semantic=options;
ignored={'trainingFile','testFile','pt1TruthFile','outputTag','runId','runtimeDirectory', ...
    'outputDirectory','figureVisible','verbose','saveStampedResult','publishLatest', ...
    'progressCallback','plotEnabled','preparedInput','runControl','runControlOptions', ...
    'resume','enableRunControl','timingHistoryDirectory','timingQuery'};
semantic=rmfield(semantic,intersect(fieldnames(semantic),ignored));
testHash='NOT_REQUESTED';
if options.evaluateTestSet&&isfile(paths.testFile),testHash=local_file_hash(paths.testFile);end
identity=struct('route',route,'trainingSha256',local_file_hash(paths.trainingFile), ...
    'testSha256',testHash,'options',semantic,'codeSha256',code.aggregateSha256, ...
    'runtimeSha256',runtime.aggregateSha256);
hash=sht_tc24_run_control('hash',identity);
end

function snapshot = local_deterministic_code_snapshot(paths, route)
% 冻结本辨识路径直接及运行配置间接调用的MATLAB依赖，运行前后必须一致。
if strcmp(route, 'steady')
    entryName = 'Start_SteadyModelAdapt_V2_02_SteadyModelParameterEstimation.m';
else
    entryName = 'Start_SteadyModelAdapt_V2_03_TransientInstantEstimation.m';
end
name = string({entryName; ...
    'sht_steady_model_adapt_v2_common.m'; ...
    'sht_tc24_run_control.m'; ...
    'sht_tc24_node_engineering_reference.m'; ...
    'sht_trim_health_steady_point.m'; ...
    'sht_measurement_mean_sample_count.m'; ...
    'sht_default_config.m'; ...
    'sht_prepare_control_model_runtime.m'; ...
    'sht_engine_open.m'; ...
    'sht_engine_close.m'; ...
    'sht_engine_derivative.m'; ...
    'sht_load_engine_library.m'; ...
    'sht_apply_inlet_boundary_stepin.m'; ...
    'sht_first_order_foh_filter.m'; ...
    'sht_first_order_foh_coefficients.m'; ...
    'sht_get_steady_trim_initial_guess.m'; ...
    'sht_health_schedule_initialize_dll.m'; ...
    'sht_measurement_bias_generator.m'; ...
    'sht_resolve_delivery_input_file.m'; ...
    'sht_solve_steady_components_from_seed.m'; ...
    'sht_solve_steady_np_branch.m'; ...
    'sht_solve_transient_components_from_seed.m'; ...
    'sht_steady_np_branch_prior.m'; ...
    'sht_initialize_cooling_split_dll.m'; ...
    'sht_initialize_thermal_model_dll.m'; ...
    'sht_lookup_clearance_reference.m'; ...
    'sht_resolve_shaft_load_boundary.m'; ...
    'sht_identification_schedule_nodes.m'; ...
    'sht_fit_group_node_ordinates.m'; ...
    'sht_merge_config.m'; ...
    'sht_validate_runtime_config.m'; ...
    'sht_load_controller_gain_schedule.m'; ...
    'sht_load_controller_ndot_schedule.m'; ...
    'sht_sensor_step.m'; ...
    'sht_sensor_pack.m'});
sha256 = strings(numel(name), 1);
byteCount = zeros(numel(name), 1);
for i = 1:numel(name)
    fileName = fullfile(paths.tuneDir, name(i));
    if ~isfile(fileName)
        error('SHT:SteadyAdaptV2:CodeIdentityFileMissing', ...
            '确定性代码身份文件不存在：%s。', fileName);
    end
    [~, functionName] = fileparts(char(name(i)));
    resolvedFile = which(functionName);
    if isempty(resolvedFile) || ~strcmpi( ...
            local_canonical_file_name(resolvedFile), ...
            local_canonical_file_name(fileName))
        error('SHT:SteadyAdaptV2:CodeIdentityPathShadowed', ...
            ['MATLAB路径实际解析文件与当前Worktree合同文件不一致：%s；' ...
             '实际=%s；合同=%s。'], functionName, resolvedFile, fileName);
    end
    info = dir(fileName);
    byteCount(i) = info.bytes;
    sha256(i) = local_file_hash(fileName);
end
assets = table(name, byteCount, sha256, ...
    'VariableNames', {'name','byte_count','sha256'});
snapshot = struct('schemaVersion', ...
    'SHT_STEADY_MODEL_ADAPT_V2_CODE_SNAPSHOT_V1', 'assets', assets, ...
    'aggregateSha256', local_asset_table_hash(assets));
end

function snapshot = local_runtime_identity_snapshot(paths, cfg)
% 同时冻结实际加载目录和生成它的Worktree源资产，不持久化绝对路径。
runtimeDir = cfg.engine.interface.controlDir;
% 只冻结真正加载的资产。运行目录现在就是tune，不能把其全部脚本、
% 无关结果及历史设计MAT当作模型输入，否则写报告也会使运行失效。
dependencies=sht_engine_artifact_identity(cfg.engine);
listing=[];
for dependencyIndex=1:numel(dependencies)
    listing=[listing;dir(dependencies(dependencyIndex).file)]; %#ok<AGROW>
end
[~, order] = sort(lower(string({listing.name})));
listing = listing(order);
logicalName = strings(0, 1);
role = strings(0, 1);
byteCount = zeros(0, 1);
sha256 = strings(0, 1);
observedByteCount = zeros(0, 1);
observedFileSha256 = strings(0, 1);
for i = 1:numel(listing)
    runtimeFile = fullfile(listing(i).folder, listing(i).name);
    rawHash = local_file_hash(runtimeFile);
    semanticHash = rawHash;
    semanticByteCount = listing(i).bytes;
    assetRole = "actual_loaded_runtime";
    if strcmpi(listing(i).name, 'runtime_manifest.mat')
        % manifest含生成时间和绝对Worktree路径；合同只哈希去时刻、便携化
        % 后的语义载荷，同时另存原始字节哈希用于本次运行TOCTOU门。
        semanticHash = local_runtime_manifest_semantic_hash(runtimeFile);
        semanticByteCount = 0;
        assetRole = "runtime_manifest_semantic";
    end
    logicalName(end + 1, 1) = "runtime/" + string(listing(i).name); %#ok<AGROW>
    role(end + 1, 1) = assetRole; %#ok<AGROW>
    byteCount(end + 1, 1) = semanticByteCount; %#ok<AGROW>
    sha256(end + 1, 1) = semanticHash; %#ok<AGROW>
    observedByteCount(end + 1, 1) = listing(i).bytes; %#ok<AGROW>
    observedFileSha256(end + 1, 1) = rawHash; %#ok<AGROW>
    sourceFile = fullfile(paths.tuneDir, listing(i).name);
    if isfile(sourceFile) && ~strcmpi( ...
            local_canonical_file_name(sourceFile), ...
            local_canonical_file_name(fullfile(runtimeDir, listing(i).name)))
        sourceInfo = dir(sourceFile);
        logicalName(end + 1, 1) = ...
            "runtime_source/" + string(listing(i).name); %#ok<AGROW>
        role(end + 1, 1) = "runtime_generation_source"; %#ok<AGROW>
        byteCount(end + 1, 1) = sourceInfo.bytes; %#ok<AGROW>
        sourceHash = local_file_hash(sourceFile);
        sha256(end + 1, 1) = sourceHash; %#ok<AGROW>
        observedByteCount(end + 1, 1) = sourceInfo.bytes; %#ok<AGROW>
        observedFileSha256(end + 1, 1) = sourceHash; %#ok<AGROW>
    end
end
extraRelative = "matlab_loadlibrary_include/stdio.h";
extraRole = "loadlibrary_parser_header";
for i = 1:numel(extraRelative)
    fileName = fullfile(paths.tuneDir, strrep(char(extraRelative(i)), '/', filesep));
    if ~isfile(fileName)
        error('SHT:SteadyAdaptV2:RuntimeIdentityFileMissing', ...
            '模型运行身份文件不存在：%s。', fileName);
    end
    info = dir(fileName);
    logicalName(end + 1, 1) = "source/" + extraRelative(i); %#ok<AGROW>
    role(end + 1, 1) = extraRole(i); %#ok<AGROW>
    byteCount(end + 1, 1) = info.bytes; %#ok<AGROW>
    fileHash = local_file_hash(fileName);
    sha256(end + 1, 1) = fileHash; %#ok<AGROW>
    observedByteCount(end + 1, 1) = info.bytes; %#ok<AGROW>
    observedFileSha256(end + 1, 1) = fileHash; %#ok<AGROW>
end
[logicalName, order] = sort(logicalName);
role = role(order);
byteCount = byteCount(order);
sha256 = sha256(order);
observedByteCount = observedByteCount(order);
observedFileSha256 = observedFileSha256(order);
assets = table(logicalName, role, byteCount, sha256, ...
    observedByteCount, observedFileSha256, ...
    'VariableNames', {'name','role','byte_count','sha256', ...
    'observed_byte_count','observed_file_sha256'});
snapshot = struct('schemaVersion', ...
    'SHT_STEADY_MODEL_ADAPT_V2_RUNTIME_SNAPSHOT_V1', 'assets', assets, ...
    'aggregateSha256', local_asset_table_hash(assets));
end

function hashText = local_runtime_manifest_semantic_hash(fileName)
loaded = load(fileName, 'runtime');
if ~isfield(loaded, 'runtime') || ~isstruct(loaded.runtime)
    error('SHT:SteadyAdaptV2:BadRuntimeManifest', ...
        'runtime_manifest.mat不含有效runtime结构。');
end
runtime = loaded.runtime;
if isfield(runtime, 'generatedAt')
    runtime = rmfield(runtime, 'generatedAt');
end
if isfield(runtime, 'controlDir')
    runtime.controlDir = '@runtime';
end
if isfield(runtime, 'modelFile')
    runtime.modelFile = ['@runtime/' local_file_leaf(runtime.modelFile)];
end
if isfield(runtime, 'sourceModel')
    runtime.sourceModel = ['@source/' local_file_leaf(runtime.sourceModel)];
end
if isfield(runtime, 'designStateFile')
    runtime.designStateFile = ['@source/MiddleData/' ...
        local_file_leaf(runtime.designStateFile)];
end
if isfield(runtime, 'mapFiles')
    mapFile = string(runtime.mapFiles(:));
    for i = 1:numel(mapFile)
        mapFile(i) = string(local_file_leaf(mapFile(i)));
    end
    runtime.mapFiles = cellstr(mapFile);
end
hashText = local_value_hash(runtime);
end

function hashText = local_asset_table_hash(assets)
line = strings(height(assets), 1);
for i = 1:height(assets)
    roleText = "";
    if ismember('role', assets.Properties.VariableNames)
        roleText = string(assets.role(i));
    end
    line(i) = string(assets.name(i)) + "|" + roleText + "|" + ...
        string(sprintf('%.0f', assets.byte_count(i))) + "|" + ...
        string(assets.sha256(i));
end
hashText = local_text_hash(strjoin(cellstr(line), newline));
end

function snapshot = local_source_file_snapshot(fileName)
if ~isfile(fileName)
    error('SHT:SteadyAdaptV2:SourceIdentityFileMissing', ...
        '源数据身份文件不存在：%s。', fileName);
end
info = dir(fileName);
snapshot = struct('name', string(local_file_leaf(fileName)), ...
    'byteCount', info.bytes, 'sha256', local_file_hash(fileName));
end

function local_assert_source_file_snapshot_equal(before, after, label)
if ~strcmp(before.name, after.name) || before.byteCount ~= after.byteCount || ...
        ~strcmp(before.sha256, after.sha256)
    error('SHT:SteadyAdaptV2:SourceIdentityChanged', ...
        '%s发生字节变化，正式结果拒绝发布。', label);
end
end

function local_assert_identity_snapshot_equal(before, after, label)
if ~strcmp(before.schemaVersion, after.schemaVersion) || ...
        ~strcmp(before.aggregateSha256, after.aggregateSha256) || ...
        ~isequal(before.assets, after.assets)
    error('SHT:SteadyAdaptV2:InferenceIdentityChanged', ...
        '%s在参数辨识运行前后发生变化，正式结果拒绝发布。', label);
end
end

function [identity, contractHash] = local_deterministic_result_identity( ...
        paths, cfg, route, options, weighting, npBranchPrior, ...
        nodeContractHash, runId, codeSnapshot, runtimeSnapshot, ...
        trainingSnapshot)
% 只冻结训练侧和运行侧身份。测试文件与隐藏真值既不读取也不哈希，
% 从合同构造层保证其不可能参与节点、步长或正则强度选择。
trainingHash = trainingSnapshot.sha256;
interface = cfg.engine.interface;
dllFile = fullfile(interface.controlDir, [interface.libraryName '.dll']);
headerFile = fullfile(interface.controlDir, interface.headerName);
dllHash = local_file_hash(dllFile);
headerHash = local_file_hash(headerFile);
if isfield(cfg.engine, 'modelConfiguration') && ...
        ~isempty(cfg.engine.modelConfiguration)
    modelFile = cfg.engine.modelConfiguration;
    modelHash = local_file_hash(modelFile);
    modelName = string(local_file_leaf(modelFile));
else
    modelHash = 'NOT_AVAILABLE';
    modelName = "NOT_AVAILABLE";
end

codeArtifacts = codeSnapshot.assets;
aggregateCodeHash = codeSnapshot.aggregateSha256;

solverOptions = options;
nonSemanticFields = {'trainingFile','testFile','pt1TruthFile','outputTag', ...
    'runId','figureVisible','verbose','saveStampedResult','evaluateTestSet', ...
    'publishLatest','outputDirectory','progressCallback','plotEnabled', ...
    'preparedInput','runControl','runControlOptions','resume','enableRunControl','timingHistoryDirectory','timingQuery'};
nonSemanticFields = nonSemanticFields(ismember( ...
    nonSemanticFields, fieldnames(solverOptions)));
solverOptions = rmfield(solverOptions, nonSemanticFields);
solverOptionsHash = local_value_hash(solverOptions);
weightingHash = local_value_hash(weighting);
npBranchContractHash = local_value_hash(npBranchPrior);

identity = struct();
identity.schemaVersion = ...
    'SHT_STEADY_MODEL_ADAPT_V2_DETERMINISTIC_IDENTITY_V2';
identity.runId = runId;
identity.route = route;
identity.trainingDataName = string(local_file_leaf(paths.trainingFile));
identity.trainingDataSha256 = trainingHash;
identity.trainingDataByteCount = trainingSnapshot.byteCount;
identity.testDataReadDuringInference = false;
identity.hiddenTruthReadDuringInference = false;
identity.dllName = string(local_file_leaf(dllFile));
identity.dllSha256 = dllHash;
identity.headerName = string(local_file_leaf(headerFile));
identity.headerSha256 = headerHash;
identity.modelConfigurationName = modelName;
identity.modelConfigurationSha256 = modelHash;
identity.codeArtifacts = codeArtifacts;
identity.aggregateCodeSha256 = aggregateCodeHash;
identity.runtimeAssets = runtimeSnapshot.assets;
identity.runtimeAggregateSha256 = runtimeSnapshot.aggregateSha256;
identity.runtimeAssetCount = height(runtimeSnapshot.assets);
identity.codeAndRuntimeStableDuringInference = true;
identity.solverOptionsSha256 = solverOptionsHash;
identity.residualWeightingSha256 = weightingHash;
identity.npBranchContractSha256 = npBranchContractHash;
identity.nodeContractSha256 = nodeContractHash;

contractLine = { ...
    'schema=SHT_STEADY_MODEL_ADAPT_V2_DETERMINISTIC_CONTRACT_V2', ...
    ['run_id=' runId], ['route=' route], ...
    ['training_sha256=' trainingHash], ['dll_sha256=' dllHash], ...
    ['header_sha256=' headerHash], ['model_sha256=' char(modelHash)], ...
    ['code_sha256=' aggregateCodeHash], ...
    ['runtime_assets_sha256=' runtimeSnapshot.aggregateSha256], ...
    ['solver_options_sha256=' solverOptionsHash], ...
    ['residual_weighting_sha256=' weightingHash], ...
    ['np_branch_sha256=' npBranchContractHash], ...
    ['node_contract_sha256=' char(nodeContractHash)], ...
    'test_data_used_for_inference=false', ...
    'hidden_truth_used_for_inference=false'};
contractHash = local_text_hash(strjoin(contractLine, '|'));
identity.deterministicContractSha256 = contractHash;
end

function name = local_file_leaf(filePath)
[~, base, extension] = fileparts(char(filePath));
name = [base extension];
end

function hashText = local_file_hash(filePath)
filePath = char(filePath);
% MATLAB把Simulink模型的exist(...,'file')分类为4而不是普通文件2；
% 身份哈希关心的是“可读的实际文件”，统一使用isfile避免误拒绝MDL。
if ~isfile(filePath)
    error('SHT:SteadyAdaptV2:HashFileMissing', ...
        '身份哈希文件不存在：%s。', filePath);
end
fid = fopen(filePath, 'r');
if fid < 0
    error('SHT:SteadyAdaptV2:HashReadFailure', ...
        '无法读取文件并计算SHA-256：%s。', filePath);
end
cleanupObject = onCleanup(@() fclose(fid));
digest = java.security.MessageDigest.getInstance('SHA-256');
while true
    bytes = fread(fid, 1024 * 1024, '*uint8');
    if isempty(bytes)
        break;
    end
    digest.update(typecast(bytes(:), 'int8'));
end
clear cleanupObject;
hashBytes = typecast(int8(digest.digest()), 'uint8');
hashText = lower(reshape(dec2hex(hashBytes, 2).', 1, []));
end

function hashText = local_text_hash(textValue)
bytes = unicode2native(char(textValue), 'UTF-8');
hashText = local_byte_hash(bytes);
end

function hashText = local_value_hash(value)
bytes = getByteStreamFromArray(value);
hashText = local_byte_hash(bytes);
end

function hashText = local_byte_hash(bytes)
digest = java.security.MessageDigest.getInstance('SHA-256');
bytes = uint8(bytes(:));
if ~isempty(bytes)
    digest.update(typecast(bytes, 'int8'));
end
hashBytes = typecast(int8(digest.digest()), 'uint8');
hashText = lower(reshape(dec2hex(hashBytes, 2).', 1, []));
end

function paths = local_paths(options)
if nargin < 1 || isempty(options)
    options = struct('trainingFile', '', 'testFile', '');
end
thisDir = fileparts(mfilename('fullpath'));
programRoot = fileparts(thisDir);
paths = struct();
paths.tuneDir = thisDir;
paths.middleDataDir = fullfile(thisDir, 'MiddleData');
paths.testDataDir = fullfile(thisDir, 'TestData');
paths.reportOutputDir = fullfile(programRoot, ...
    'report_outputs', 'steady_model_adapt_v2');
if isfield(options,'modelMode') && options.modelMode==0
    paths.middleDataDir=fullfile(paths.middleDataDir,'three_component');
    paths.testDataDir=fullfile(paths.testDataDir,'three_component');
    paths.reportOutputDir=fullfile(programRoot,'report_outputs','three_component','deterministic');
end
paths.trainingFile = fullfile(paths.testDataDir, ...
    'steady_bench_2p4_training_means.xlsx');
paths.testFile = fullfile(paths.testDataDir, ...
    'steady_bench_2p4_test_means.xlsx');
if isfield(options,'outputDirectory') && ~isempty(options.outputDirectory)
    assert(isfield(options,'runId') && ~isempty(regexp(options.runId, ...
        '^[A-Za-z0-9_-]+$','once')),'SHT:SteadyAdaptV2:OutputRunId','独立输出须给定合法runId。');
    outputRoot=fullfile(sht_tc24_absolute_path(options.outputDirectory),options.runId);
    paths.middleDataDir=fullfile(outputRoot,'MiddleData');
    paths.reportOutputDir=fullfile(outputRoot,'report_outputs');
end
if isfield(options, 'trainingFile') && ~isempty(options.trainingFile)
    paths.trainingFile = sht_resolve_delivery_input_file( ...
        options.trainingFile, paths.trainingFile);
end
if isfield(options, 'testFile') && ~isempty(options.testFile)
    paths.testFile = sht_resolve_delivery_input_file( ...
        options.testFile, paths.testFile);
end
dirs = {paths.middleDataDir, paths.reportOutputDir};
for i = 1:numel(dirs)
    if ~exist(dirs{i}, 'dir')
        mkdir(dirs{i});
    end
end
end

function [trainingData, testData] = local_read_input_tables(paths, options)
if ~exist(paths.trainingFile, 'file')
    error('SHT:SteadyAdaptV2:MissingTrainingData', ...
        '训练集不存在：%s。', paths.trainingFile);
end
trainingData = local_read_table(paths.trainingFile);
local_validate_input_table(trainingData, '训练集');
if options.evaluateTestSet
    if ~exist(paths.testFile, 'file')
        error('SHT:SteadyAdaptV2:MissingTestData', ...
            '已要求嵌入测试评价，但测试集不存在：%s。', paths.testFile);
    end
    testData = local_read_table(paths.testFile);
    local_validate_input_table(testData, '测试集');
else
    % 保留同一表结构，使历史结果组织和专项研究接口继续可用；零行测试表
    % 不参与任何参数估计、指标计算或正式验收。
    testData = trainingData([], :);
end
end

function tbl = local_read_measurement_table(filePath, label)
if nargin < 2 || isempty(label)
    label = '测量数据';
end
filePath = char(string(filePath));
if exist(filePath, 'file') ~= 2
    error('SHT:SteadyAdaptV2:MissingMeasurementData', ...
        '%s文件不存在：%s。', label, filePath);
end
tbl = local_read_table(filePath);
local_validate_input_table(tbl, label);
end

function [trainingData, targetData, result] = ...
        local_prepare_np_branch_data(trainingData, targetData, options)
% 训练点Np是当前参数估计的合法观测量，可用于识别训练点的物理解分支。
% 目标/测试点Np绝不参与分支构造，只由训练功率曲线、目标Wf和Mkp预测。
result = struct('enabled', false, 'method', "", ...
    'trainingReference', table(), 'trainingPrior', struct(), ...
    'targetPrior', struct(), 'targetNpUsed', false, ...
    'loadBoundaryMode', "torque");
if ~options.steadyNpBranchEnabled
    return;
end

reference = table(string(trainingData.point_id), ...
    double(trainingData.Np_mean), ...
    'VariableNames', {'point_id','Np_ref_rpm'});
trainingPrior = sht_steady_np_branch_prior( ...
    trainingData, trainingData, reference, ...
    options.steadyNpBranchPriorOptions);
trainingData = local_attach_np_branch_columns( ...
    trainingData, trainingPrior.testTable, ...
    "training_observed_np_root_selector", true);
trainingWidth = options.steadyNpTrainingBranchRelativeHalfWidth;
trainingData.Np_branch_relative_half_width(:) = trainingWidth;
trainingData.Np_branch_lower_rpm = ...
    trainingData.Np_branch_center_rpm .* (1 - trainingWidth);
trainingData.Np_branch_upper_rpm = ...
    trainingData.Np_branch_center_rpm .* (1 + trainingWidth);

targetPrior = struct();
if ~isempty(targetData)
    targetPrior = sht_steady_np_branch_prior( ...
        trainingData, targetData, reference, ...
        options.steadyNpBranchPriorOptions);
    if ~targetPrior.allTestPointsAvailable
        unavailable = targetPrior.testTable.point_id( ...
            ~targetPrior.testTable.available);
        error('SHT:SteadyAdaptV2:NpBranchTargetOutOfRange', ...
            ['以下目标工况的Wf超出训练功率曲线覆盖域，禁止外插：%s。' ...
             '请补充相邻训练工况或显式关闭本专项分支机制。'], ...
            strjoin(cellstr(unavailable), ', '));
    end
    targetData = local_attach_np_branch_columns( ...
        targetData, targetPrior.testTable, ...
        "training_power_curve", false);
end

result.enabled = true;
result.method = "training_piecewise_linear_power_curve";
result.trainingReference = reference;
result.trainingPrior = trainingPrior;
result.trainingRootSelectionRelativeHalfWidth = trainingWidth;
result.trainingRootSelectionTable = trainingData(:, { ...
    'point_id','Np_branch_center_rpm','Np_branch_lower_rpm', ...
    'Np_branch_upper_rpm','Np_branch_relative_half_width'});
result.targetPrior = targetPrior;
result.targetNpUsed = false;
end

function data = local_attach_np_branch_columns( ...
        data, priorTable, source, referenceUsesPointNp)
if height(data) ~= height(priorTable) || ...
        any(string(data.point_id) ~= string(priorTable.point_id))
    error('SHT:SteadyAdaptV2:NpBranchPointMismatch', ...
        'Np分支先验与目标数据的工况顺序不一致。');
end
data.Np_branch_center_rpm = priorTable.Np_branch_center_rpm;
data.Np_branch_lower_rpm = priorTable.Np_lower_rpm;
data.Np_branch_upper_rpm = priorTable.Np_upper_rpm;
data.Np_branch_relative_half_width = priorTable.relative_half_width;
data.Np_branch_available = priorTable.available;
data.Np_branch_source = repmat(string(source), height(data), 1);
data.Np_branch_reference_uses_point_Np = ...
    repmat(logical(referenceUsesPointNp), height(data), 1);
end

function data = local_attach_observed_training_np_branch(data, options)
% 2.7联合辨识训练点包含多个Np挡位和负载序列，不再满足单一Wf-功率
% 严格单调曲线假设。训练Np本来就是合法观测输出，因此只用它选择各
% 训练点的物理解，并按2.4相同训练半宽构造根区间；该值不形成额外
% 残差，也不用于独立验证点的分支预测。
center = double(data.Np_mean(:));
width = options.steadyNpTrainingBranchRelativeHalfWidth;
if any(~isfinite(center)) || any(center <= 0) || ...
        ~isfinite(width) || width <= 0 || width >= 1
    error('SHT:SteadyAdaptV2:BadObservedTrainingNpBranch', ...
        '训练Np或训练分支相对半宽无效。');
end
data.Np_branch_center_rpm = center;
data.Np_branch_lower_rpm = center .* (1 - width);
data.Np_branch_upper_rpm = center .* (1 + width);
data.Np_branch_relative_half_width = repmat(width, height(data), 1);
data.Np_branch_available = true(height(data), 1);
data.Np_branch_source = repmat( ...
    "training_observed_np_root_selector", height(data), 1);
data.Np_branch_reference_uses_point_Np = true(height(data), 1);
end

function [trainingData, testData, meta] = local_attach_pt1_truth( ...
        trainingData, testData, paths, options)
% 模式1仅用于受控对照：Excel仍保持真实可测字段，Pt1从与
% 当前Excel工况编号一致的替代数据MAT中按point_id严格匹配。
if isempty(options.pt1TruthFile)
    sourceDir = fullfile(paths.testDataDir, 'test_data_generation');
    candidates = dir(fullfile(sourceDir, 'steady_bench_substitute_*.mat'));
    [~, order] = sort([candidates.datenum], 'descend');
    candidates = candidates(order);
    candidateFiles = strings(numel(candidates), 1);
    for i = 1:numel(candidates)
        candidateFiles(i) = string(fullfile( ...
            candidates(i).folder, candidates(i).name));
    end
else
    candidateFiles = string(options.pt1TruthFile);
end
if isempty(candidateFiles)
    error('SHT:SteadyAdaptV2:MissingPt1TruthFile', ...
        '没有找到steady_bench_substitute_*.mat，无法获取Pt1真值。');
end

allData = [trainingData; testData];
selectedFile = "";
selectedPt1 = [];
lastReason = "";
for i = 1:numel(candidateFiles)
    filePath = candidateFiles(i);
    if ~isfile(filePath)
        lastReason = "文件不存在";
        continue;
    end
    source = load(char(filePath), 'dataTable');
    if ~isfield(source, 'dataTable') || ~istable(source.dataTable)
        lastReason = "缺少dataTable";
        continue;
    end
    sourceTable = source.dataTable;
    required = {'point_id','model_Pt1','Np','Ng','Wf','Tt1'};
    if ~all(ismember(required, sourceTable.Properties.VariableNames))
        lastReason = "dataTable缺少必要字段";
        continue;
    end
    sourceId = string(sourceTable.point_id);
    if numel(unique(sourceId)) ~= numel(sourceId)
        lastReason = "point_id不唯一";
        continue;
    end
    [matched, location] = ismember(allData.point_id, sourceId);
    if ~all(matched)
        lastReason = "point_id与Excel不完整匹配";
        continue;
    end
    % 用三个独立测量量防止误读到同编号的历史数据。
    sourceCheck = [sourceTable.Np(location), sourceTable.Ng(location), ...
        sourceTable.Tt1(location)];
    excelCheck = [allData.Np_mean, allData.Ng_mean, allData.Tt1_mean];
    tolerance = 1e-9 + 1e-9 * max(abs(excelCheck), 1);
    if any(abs(sourceCheck - excelCheck) > tolerance, 'all')
        lastReason = "测量均值与Excel不一致";
        continue;
    end
    pt1 = sourceTable.model_Pt1(location);
    if ~isnumeric(pt1) || any(~isfinite(pt1) | pt1 <= 0)
        lastReason = "model_Pt1不是有限正值";
        continue;
    end
    selectedFile = filePath;
    selectedPt1 = pt1(:);
    break;
end
if strlength(selectedFile) == 0
    error('SHT:SteadyAdaptV2:NoMatchingPt1TruthFile', ...
        '未找到与当前Excel严格一致的Pt1真值数据：%s。', lastReason);
end

nTraining = height(trainingData);
trainingData.Pt1_truth = selectedPt1(1:nTraining);
testData.Pt1_truth = selectedPt1((nTraining + 1):end);
meta = struct('used', true, 'sourceFile', selectedFile, ...
    'sourceColumn', "dataTable.model_Pt1", ...
    'pointCount', numel(selectedPt1));
end

function tbl = local_read_table(filePath)
try
    tbl = readtable(filePath, 'FileType', 'spreadsheet', 'TextType', 'string');
catch
    tbl = readtable(filePath, 'FileType', 'spreadsheet');
end
tbl.point_id = string(tbl.point_id);
% 新试车合同只在明确存在测量耙和Pt1列时转换内部语义；不生成Pt2测量。
if ismember('Ptb3_mean',tbl.Properties.VariableNames)
    tbl.Pt3_mean=tbl.Ptb3_mean;tbl.Tt3_mean=tbl.Ttb3_mean;
    tbl.Wa2_mean=tbl.Wa1_mean-tbl.Wb_mean;
    tbl.Mkg_mean=zeros(height(tbl),1); % 工程先验：无GT附件功率提取
end
end

function local_validate_input_table(tbl, label)
if ismember('sample_count',tbl.Properties.VariableNames)
    sht_measurement_mean_sample_count(tbl);
end
required = {'point_id','Np_mean','Ng_mean','Wf_mean','Tt45_mean', ...
    'Pt45_mean','Mkp_mean','Mkg_mean','Pt2_mean','Tt1_mean', ...
    'Pt3_mean','Tt3_mean','Pamb_mean','Tamb_mean', ...
    'Altitude_mean','Mach_mean'};
if ismember('Ptb3_mean',tbl.Properties.VariableNames)
    required=setdiff(required,{'Pt2_mean'});
    required=[required,{'Pt1_mean','Ptb3_mean','Ttb3_mean','Pt6_mean','Tt6_mean','Wa1_mean','Wb_mean'}];
end
missing = setdiff(required, tbl.Properties.VariableNames);
if ~isempty(missing)
    error('SHT:SteadyAdaptV2:BadInputSchema', ...
        '%s缺少字段：%s。', label, strjoin(missing, ', '));
end
if height(tbl) < 1
    error('SHT:SteadyAdaptV2:EmptyInput', '%s没有工况点。', label);
end
numericFields = setdiff(required, {'point_id'});
for i = 1:numel(numericFields)
    value = tbl.(numericFields{i});
    if ~isnumeric(value) || any(~isfinite(value))
        error('SHT:SteadyAdaptV2:BadInputValue', ...
            '%s字段%s必须全部为有限数值。', label, numericFields{i});
    end
end
if numel(unique(tbl.point_id)) ~= height(tbl)
    error('SHT:SteadyAdaptV2:DuplicatePointId', ...
        '%s的point_id存在重复。', label);
end
end

function parameters = local_parameter_definition(options)
cIndex = [0; 1; 2; 6; 7; 8; 10; 11; 12; 14; 15];
name = ["Inlet_K_dP"; "HPC_K_W"; "HPC_K_eta"; ...
    "Burner_K_dP"; "GT_K_W"; "GT_K_eta"; ...
    "GT_PT_Duct_K_dP"; "PT_K_W"; "PT_K_eta"; ...
    "PT_Nozzle_Duct_K_dP"; "Nozzle_K_A8"];
axisName = ["inlet_corrected_mass_flow"; "ac_corrected_speed"; ...
    "ac_corrected_speed"; "burner_inlet_corrected_mass_flow"; ...
    "gt_total_pressure_ratio"; "gt_total_pressure_ratio"; ...
    "gt_pt_duct_corrected_mass_flow"; "pt_total_pressure_ratio"; ...
    "pt_total_pressure_ratio"; "pt_nozzle_duct_corrected_mass_flow"; ...
    "constant"];
axisType = [1; 5; 5; 2; 7; 7; 3; 8; 8; 4; 0];
scheduled = axisType ~= 0;
pressureLoss = ismember(cIndex, [0, 6, 10, 14]);
lowerBound = [-0.02; -0.08; -0.08; -0.08; -0.10; -0.10; ...
    -0.08; -0.10; -0.10; -0.08; -0.10];
upperBound = [0.15; 0.08; 0.08; 0.04; 0.10; 0.10; ...
    0.10; 0.10; 0.10; 0.10; 0.10];
% 阶段A使用零中心、参数专用的工程先验尺度。该尺度与本轮总体部件
% 修正量级相当，使真值通常位于约1~2个先验标准差内，同时抑制多个
% 弱可辨识参数通过大幅反向变化共同拟合同一组测量输出。
priorSigmaGlobal = [0.012; 0.015; 0.015; 0.012; 0.018; 0.018; ...
    0.012; 0.018; 0.018; 0.012; 0.020];
priorSigmaGroup = [0.018; 0.015; 0.015; 0.015; 0.018; 0.018; ...
    0.015; 0.018; 0.018; 0.015; 0.018];
finiteDifferenceStep = 5e-4 * ones(numel(cIndex), 1);
parameters = table(cIndex, cIndex + 1, name, scheduled, pressureLoss, ...
    axisName, axisType, lowerBound, upperBound, priorSigmaGlobal, ...
    priorSigmaGroup, finiteDifferenceStep, ...
    'VariableNames', {'c_index','matlab_index','name','scheduled', ...
    'pressure_loss','axis_name','axis_type','lower_bound','upper_bound', ...
    'prior_sigma_global','prior_sigma_group','difference_step'});
if ~options.estimateInletPressureLoss
    parameters(parameters.c_index == 0, :) = [];
end
end

function scales = local_residual_scales(route, cfg, data, options)
if options.modelMode==0
    names=["Ptb3";"Ttb3";"Pt45";"Tt45";"Pt6";"Tt6";"Wa2"];
    value=[7863;3.51;1980;5.72;550;4;.20];
    value(end)=options.tc24FlowEngineeringScale;
    if ~options.includeTC24FlowResidual
        names(end)=[];value(end)=[];
    end
    if strcmp(route,'steady')
        names=["Np";"Ng";names];value=[63;114;value];
    else
        names=[names;"dNp_dt";"dNg_dt"];value=[value;20.9;38];
    end
    scales=table(names,value,'VariableNames',{'name','scale'});return;
end
if strcmp(route, 'steady')
    names = ["Np","Ng","Pt2","Pt3","Tt3","Tt45","Pt45"];
    value = [max(0.003 * max(abs(data.Np_mean)), 30); ...
        max(0.003 * max(abs(data.Ng_mean)), 50); ...
        max(0.0005 * max(abs(data.Pt2_mean)), 50); ...
        max(0.005 * max(abs(data.Pt3_mean)), 1000); ...
        max(0.005 * max(abs(data.Tt3_mean)), 1); ...
        max(0.005 * max(abs(data.Tt45_mean)), 1); ...
        max(0.005 * max(abs(data.Pt45_mean)), 500)];
else
    names = ["Pt2","Pt3","Tt3","Tt45","Pt45","dNp_dt","dNg_dt"];
    value = [max(0.0005 * max(abs(data.Pt2_mean)), 50); ...
        max(0.005 * max(abs(data.Pt3_mean)), 1000); ...
        max(0.005 * max(abs(data.Tt3_mean)), 1); ...
        max(0.005 * max(abs(data.Tt45_mean)), 1); ...
        max(0.005 * max(abs(data.Pt45_mean)), 500); ...
        max(0.001 * cfg.engine.initial.Np0, 10); ...
        max(0.001 * cfg.engine.initial.Ng0, 20)];
end
if ~options.includePt2Residual
    keep = names ~= "Pt2";
    names = names(keep);
    value = value(keep);
end
names = names(:);
value = value(:);
scales = table(names, value, 'VariableNames', {'name','scale'});
end

function weighting = local_residual_weighting( ...
        route, data, baselinePrediction, scales, options)
%LOCAL_RESIDUAL_WEIGHTING 在参数更新前构造并冻结残差协方差。
% 每个工况的输出误差视为同一通道协方差下的独立观测。公共偏置在
% 当前对比中折算为通道方差，而不从已经包含模型差异的残差反复调权。
names = cellstr(scales.name);
raw = local_raw_data_residual_matrix(route, data, baselinePrediction, names);
legacyCount=options.residualWindowSampleCount;
if options.modelMode==0,legacyCount=[];end
meanSampleCount=sht_measurement_mean_sample_count(data,legacyCount);
% 每个工况可以来自不同长度的有效段；通道级值仅作摘要，正式协方差
% 保留逐工况方差。工程尺度方式仍完全不按记录数改变目标权重。
measurementSigmaByPoint=zeros(height(data),numel(names));
for p=1:height(data)
    pointOptions=options;pointOptions.residualWindowSampleCount=meanSampleCount(p);
    measurementSigmaByPoint(p,:)=local_measurement_residual_sigma(names,pointOptions).';
end
measurementSigma=sqrt(mean(measurementSigmaByPoint.^2,1)).';
if options.modelMode==0
    modelSigma=scales.scale/3;
else
    modelSigma = local_model_discrepancy_sigma(names);
end
method = lower(string(options.residualWeightingMethod));
shrinkage = 0;
observationCovariance = [];
commonBiasSigma = zeros(numel(names), 1);
independentSigma = zeros(numel(names), 1);

switch method
    case "engineering_scale"
        covariance = diag(scales.scale .^ 2);
        source = 'frozen engineering channel scales';
    case "measurement_covariance"
        covariance = diag(measurementSigma .^ 2);
        observationCovariance=diag(measurementSigmaByPoint(:).^2);
        source = 'independent sensor specification frozen before estimation';
    case "fixed_covariance"
        covariance = options.residualCovarianceOverride;
        if size(covariance, 1) ~= numel(names)
            error('SHT:SteadyAdaptV2:ResidualCovarianceDimensionMismatch', ...
                '外部协方差维数为%d，当前残差通道数为%d。', ...
                size(covariance, 1), numel(names));
        end
        source = strtrim(options.residualCovarianceSource);
        if isempty(source)
            source = 'external covariance fixed for one complete A/B/D solve';
        end
    case "hybrid_measurement_model"
        covariance = diag(measurementSigma .^ 2 + modelSigma .^ 2);
        pointVariance=measurementSigmaByPoint.^2+modelSigma(:).'.^2;
        observationCovariance=diag(pointVariance(:));
        source = 'sensor specification plus pre-frozen model discrepancy';
    case "hybrid_correlated_bias"
        [covariance, observationCovariance, commonBiasSigma, ...
            independentSigma] = local_hybrid_correlated_bias_covariance( ...
            names, meanSampleCount, modelSigma, options);
        source = [ ...
            'sensor common bias marginalized across operating points plus ' ...
            'independent white noise and pre-frozen model discrepancy'];
    otherwise
        error('SHT:SteadyAdaptV2:UnknownResidualWeighting', ...
            '未知残差权重方法：%s。', method);
end

[covariance, correlation, physicalCholLower, eigenvalues, jitter] = ...
    local_factor_residual_covariance(covariance, options);
activeSigma = sqrt(diag(covariance));
normalizationScale = local_residual_normalization_scale( ...
    names, scales.scale, options);
coordinateCovariance = covariance ./ ...
    (normalizationScale * normalizationScale.');
[coordinateCovariance, ~, coordinateCholLower, ~, coordinateJitter] = ...
    local_factor_residual_covariance(coordinateCovariance, options);
if strcmp(options.residualNormalizationMode, 'design_reference')
    cholLower = coordinateCholLower;
else
    cholLower = physicalCholLower;
end

isStackedObservationCovariance = ~isempty(observationCovariance);
observationCholLower = [];
physicalObservationCholLower = [];
observationJitter = 0;
if isStackedObservationCovariance
    [observationCovariance, ~, physicalObservationCholLower, ~, ...
        observationJitter] = local_factor_residual_covariance( ...
        observationCovariance, options);
    stackedNormalizationScale = repelem( ...
        normalizationScale(:), height(data));
    normalizedObservationCovariance = observationCovariance ./ ...
        (stackedNormalizationScale * stackedNormalizationScale.');
    [normalizedObservationCovariance, ~, normalizedObservationCholLower, ...
        ~, normalizedObservationJitter] = ...
        local_factor_residual_covariance( ...
        normalizedObservationCovariance, options);
    if strcmp(options.residualNormalizationMode, 'design_reference')
        observationCholLower = normalizedObservationCholLower;
        observationJitter = normalizedObservationJitter;
    else
        observationCholLower = physicalObservationCholLower;
    end
else
    stackedNormalizationScale = [];
    normalizedObservationCovariance = [];
end
equivalence = local_whitening_normalization_equivalence( ...
    raw, covariance, physicalCholLower, normalizationScale);

weighting = struct();
weighting.method = char(method);
weighting.source = source;
weighting.names = string(names(:));
weighting.covariance = covariance;
weighting.correlation = correlation;
weighting.cholLower = cholLower;
weighting.physicalCholLower = physicalCholLower;
weighting.coordinateCovariance = coordinateCovariance;
weighting.coordinateCholLower = coordinateCholLower;
weighting.normalizationMode = options.residualNormalizationMode;
weighting.normalizationScale = normalizationScale;
weighting.isStackedObservationCovariance = ...
    isStackedObservationCovariance;
weighting.observationPointIds = string(data.point_id(:));
weighting.observationCovariance = observationCovariance;
weighting.observationCholLower = observationCholLower;
weighting.physicalObservationCholLower = physicalObservationCholLower;
weighting.stackedNormalizationScale = stackedNormalizationScale;
weighting.normalizedObservationCovariance = ...
    normalizedObservationCovariance;
weighting.observationCholeskyJitter = observationJitter;
weighting.activeSigma = activeSigma;
weighting.engineeringScale = scales.scale(:);
weighting.measurementSigma = measurementSigma;
weighting.measurementSigmaByPoint=measurementSigmaByPoint;
weighting.meanSampleCount=meanSampleCount;
weighting.modelDiscrepancySigma = modelSigma;
weighting.commonBiasSigma = commonBiasSigma;
weighting.independentSigma = independentSigma;
weighting.shrinkageIntensity = shrinkage;
weighting.correlationEigenvalues = eigenvalues;
weighting.choleskyJitter = jitter;
weighting.coordinateCholeskyJitter = coordinateJitter;
weighting.frozenAt = 'zero_correction_baseline_before_stage_A';
weighting.normalizationEquivalence = equivalence;
weighting.diagnosticTable = table(weighting.names, ...
    weighting.engineeringScale, measurementSigma, modelSigma, activeSigma, ...
    commonBiasSigma, independentSigma, normalizationScale, ...
    'VariableNames', {'name','engineering_scale','measurement_sigma', ...
    'model_discrepancy_sigma','active_sigma','common_bias_sigma', ...
    'independent_sigma','normalization_scale'});
end

function scale = local_residual_normalization_scale( ...
        names, engineeringScale, options)
if strcmp(options.residualNormalizationMode, 'none')
    scale = ones(numel(names), 1);
    return;
end
specification = sht_measurement_bias_generator('specification');
specName = string(specification.name);
scale = engineeringScale(:);
for i = 1:numel(names)
    name = string(names{i});
    if name == "dNp_dt" || name == "dNg_dt"
        continue;
    end
    lookup = name;
    if lookup == "Tt45"
        lookup = "T45";
    end
    row = specName == lookup;
    if nnz(row) ~= 1 || ~isfinite(specification.designReference(row)) || ...
            specification.designReference(row) == 0
        error('SHT:SteadyAdaptV2:MissingNormalizationReference', ...
            '通道%s没有唯一非零设计参考值。', name);
    end
    scale(i) = abs(specification.designReference(row));
end
end

function [channelCovariance, observationCovariance, commonBiasSigma, ...
        independentSigma] = local_hybrid_correlated_bias_covariance( ...
        names, meanSampleCount, modelSigma, options)
% 一次试车的标定偏置在全部工况间保持一致，不能把它按独立噪声重复
% 计算。这里将未知公共偏置边缘化为每个通道的低秩11'协方差；窗口
% 白噪声和预先冻结的模型差异仍作为工况间独立项。流量相关偏置漂移
% 暂归入模型差异，不利用当前残差在线反推其大小。
commonBiasSigma = zeros(numel(names), 1);
independentSigma = zeros(numel(names), 1);
sampleCount=numel(meanSampleCount);
whiteVarianceByPoint=zeros(sampleCount,numel(names));
direct = ~ismember(names, {'dNp_dt','dNg_dt'});
if any(direct)
    cfg = sht_measurement_bias_generator('channelConfig', names(direct));
    if options.modelMode==0
        cfg=sht_tc24_uq_measurement('sensors',names(direct));
    end
    if any(~cfg.supported)
        missing = string(names(direct));
        error('SHT:SteadyAdaptV2:MissingCorrelatedBiasSpecification', ...
            '通道缺少公共偏置规格：%s。', ...
            strjoin(missing(~cfg.supported), ', '));
    end
    commonBiasSigma(direct) = cfg.totalBiasHalfWidth(:) / sqrt(3);
    whiteVarianceByPoint(:,direct)=cfg.noiseStd(:).'.^2./meanSampleCount(:);
    whiteMeanSigma=sqrt(mean(whiteVarianceByPoint(:,direct),1)).';
    independentSigma(direct) = sqrt( ...
        whiteMeanSigma .^ 2 + modelSigma(direct) .^ 2);
end
independentSigma(strcmp(names, 'dNp_dt')) = 5;
independentSigma(strcmp(names, 'dNg_dt')) = 15;
if any(~isfinite(commonBiasSigma) | commonBiasSigma < 0) || ...
        any(~isfinite(independentSigma) | independentSigma <= 0)
    error('SHT:SteadyAdaptV2:InvalidCorrelatedBiasScale', ...
        '公共偏置和独立误差尺度必须有限，且独立尺度必须为正。');
end

channelVariance = commonBiasSigma .^ 2 + independentSigma .^ 2;
channelCovariance = diag(channelVariance);
pointVariance=whiteVarianceByPoint+modelSigma(:).'.^2;
pointVariance(:,strcmp(names,'dNp_dt'))=5^2;
pointVariance(:,strcmp(names,'dNg_dt'))=15^2;
observationCount = sampleCount * numel(names);
observationCovariance = zeros(observationCount, observationCount);
for j = 1:numel(names)
    index = (j - 1) * sampleCount + (1:sampleCount);
    observationCovariance(index, index) = ...
        commonBiasSigma(j) ^ 2 * ones(sampleCount) + ...
        diag(pointVariance(:,j));
end
end

function sigma = local_measurement_residual_sigma(names, options)
if options.modelMode==0
    spec=sht_tc24_measurement_specification();sigma=zeros(numel(names),1);
    for k=1:numel(names)
        j=find(spec.name==string(names{k}),1);
        if ~isempty(j)
            sigma(k)=sqrt(spec.biasHalfWidth(j)^2/3+spec.noiseStd(j)^2/options.residualWindowSampleCount);
        elseif strcmp(names{k},'Wa2'),sigma(k)=.10;
        elseif strcmp(names{k},'dNp_dt'),sigma(k)=5;
        elseif strcmp(names{k},'dNg_dt'),sigma(k)=15;
        else,error('TC24:UnknownMeasurement','缺少%s误差规格。',names{k});end
    end
    return;
end
% 稳态窗口均值中的白噪声按样本数衰减；一次试车公共偏置不衰减。
sigma = zeros(numel(names), 1);
direct = ~ismember(names, {'dNp_dt','dNg_dt'});
if any(direct)
    cfg = sht_measurement_bias_generator('channelConfig', names(direct));
    if any(~cfg.supported)
        missing = string(names(direct));
        error('SHT:SteadyAdaptV2:MissingMeasurementSpecification', ...
            '残差通道缺少测量误差规格：%s。', ...
            strjoin(missing(~cfg.supported), ', '));
    end
    biasSigma = cfg.totalBiasHalfWidth(:) / sqrt(3);
    whiteSigma = cfg.noiseStd(:) / sqrt(options.residualWindowSampleCount);
    sigma(direct) = sqrt(biasSigma .^ 2 + whiteSigma .^ 2);
end
sigma(strcmp(names, 'dNp_dt')) = 5;
sigma(strcmp(names, 'dNg_dt')) = 15;
if any(~isfinite(sigma) | sigma <= 0)
    error('SHT:SteadyAdaptV2:InvalidMeasurementSigma', ...
        '每个残差通道必须具有有限正测量标准差。');
end
end

function sigma = local_model_discrepancy_sigma(names)
% 采用2.4不确定性合同中在推断前冻结的首轮模型差异尺度：直接输出
% 默认取设计参考值的0.1%，涡轮后总温Tt45取0.15%。该项不从当前
% 数据残差反推，避免拟合较差的通道在下一轮被自动降权。
specification = sht_measurement_bias_generator('specification');
specName = string(specification.name);
sigma = zeros(numel(names), 1);
for i = 1:numel(names)
    name = string(names{i});
    if name == "dNp_dt" || name == "dNg_dt"
        continue;
    end
    lookup = name;
    if lookup == "Tt45"
        lookup = "T45";
    end
    row = specName == lookup;
    if nnz(row) ~= 1
        error('SHT:SteadyAdaptV2:MissingModelReference', ...
            '通道%s没有唯一设计参考值。', name);
    end
    fraction = 0.001;
    if name == "Tt45"
        fraction = 0.0015;
    end
    sigma(i) = fraction * specification.designReference(row);
end
end

function [covariance, correlation, cholLower, eigenvalues, jitter] = ...
        local_factor_residual_covariance(covariance, options)
covariance = 0.5 * (covariance + covariance.');
sigma = sqrt(max(diag(covariance), realmin));
correlation = covariance ./ (sigma * sigma.');
correlation = 0.5 * (correlation + correlation.');
[vectors, values] = eig(correlation);
eigenvalues = real(diag(values));
floorValue = options.residualCovarianceEigenvalueFloor;
eigenvalues = max(eigenvalues, floorValue);
correlation = real(vectors * diag(eigenvalues) * vectors.');
% 特征值保护会轻微改变对角线，重新标准化后保持原通道方差。
normalizer = sqrt(max(diag(correlation), realmin));
correlation = correlation ./ (normalizer * normalizer.');
correlation = 0.5 * (correlation + correlation.');
covariance = diag(sigma) * correlation * diag(sigma);

base = max(mean(diag(covariance)), realmin);
jitter = 0;
for i = 1:8
    [cholLower, flag] = chol( ...
        covariance + jitter * eye(size(covariance)), 'lower');
    if flag == 0
        covariance = covariance + jitter * eye(size(covariance));
        return;
    end
    if jitter == 0
        jitter = 1e-12 * base;
    else
        jitter = 10 * jitter;
    end
end
error('SHT:SteadyAdaptV2:ResidualCovarianceNotPositiveDefinite', ...
    '残差协方差经有限正则后仍不能Cholesky分解。');
end

function detail = local_whitening_normalization_equivalence( ...
        raw, covariance, cholPhysical, engineeringScale)
% 先除设计/工程尺度再对白化协方差作同一坐标变换，只会对残差施加
% 正交旋转，不会改变二次代价、J''J或高斯-牛顿参数增量。
scale = engineeringScale(:);
normalizedCovariance = covariance ./ (scale * scale.');
normalizedCovariance = 0.5 * ...
    (normalizedCovariance + normalizedCovariance.');
[cholNormalized, flag] = chol(normalizedCovariance, 'lower');
if flag ~= 0
    error('SHT:SteadyAdaptV2:NormalizationEquivalenceFactorFailure', ...
        '归一化协方差不能完成Cholesky分解。');
end
physicalResidual = raw / cholPhysical.';
normalizedRaw = raw ./ scale.';
normalizedResidual = normalizedRaw / cholNormalized.';
physicalNorm2 = sum(physicalResidual(:) .^ 2);
normalizedNorm2 = sum(normalizedResidual(:) .^ 2);
detail = struct('physicalWhitenedNormSquared', physicalNorm2, ...
    'normalizedWhitenedNormSquared', normalizedNorm2, ...
    'relativeCostDifference', ...
    abs(physicalNorm2 - normalizedNorm2) / max(physicalNorm2, eps), ...
    'conclusion', 'design_normalization_plus_consistent_whitening_is_equivalent');
end

function detail = local_residual_statistics(raw, weighting)
%LOCAL_RESIDUAL_STATISTICS 保存外层输出误差松弛需要的充分统计量。
sampleCount = size(raw, 1);
secondMoment = (raw.' * raw) / max(sampleCount, 1);
if weighting.isStackedObservationCovariance
    coordinateResidual = local_coordinate_raw_vector(raw, weighting);
    whitened = weighting.observationCholLower \ coordinateResidual;
    logDeterminant = 2 * sum(log(diag(weighting.observationCholLower)));
else
    coordinateRaw = local_coordinate_raw_matrix(raw, weighting);
    whitened = coordinateRaw / weighting.cholLower.';
    logDeterminant = sampleCount * ...
        2 * sum(log(diag(weighting.cholLower)));
end
negativeLogLikelihood = 0.5 * (sum(whitened(:) .^ 2) + ...
    logDeterminant);
detail = struct('names',weighting.names,'sampleCount',sampleCount, ...
    'rawResidualMatrix',raw,'secondMoment',secondMoment, ...
    'diagonalSecondMoment',diag(secondMoment), ...
    'negativeLogLikelihoodWithoutConstant',negativeLogLikelihood);
end

function model = local_constant_model(parameters, thetaHealth, fuelBias)
model = struct();
model.kind = 'constant';
model.health = zeros(159, 1);
for i = 1:height(parameters)
    model.health(parameters.matlab_index(i)) = thetaHealth(i);
end
model.fuelBias = fuelBias;
model.schedule = [];
end

function model = local_schedule_model(schedule)
model = struct('kind', 'schedule', 'health', schedule.designHealth, ...
    'fuelBias', NaN, 'schedule', schedule);
end

function [lower, upper, priorSigma, diffStep] = ...
        local_constant_parameter_settings(parameters, wfDesign, stage)
lower = [parameters.lower_bound; -0.02 * wfDesign];
upper = [parameters.upper_bound; 0.02 * wfDesign];
if strcmp(stage, 'global')
    % 燃油偏置真值约为设计点燃油的0.3%，采用同量级零中心先验。
    priorSigma = [parameters.prior_sigma_global; 0.003 * wfDesign];
else
    priorSigma = [parameters.prior_sigma_group; 0.0025 * wfDesign];
end
diffStep = [parameters.difference_step; max(2e-6, 1e-4 * wfDesign)];
end

function [lower, upper, priorSigma, diffStep] = ...
        local_refine_parameter_settings(schedule, parameters, wfDesign)
n = height(parameters) + 1;
lower = -inf(n, 1);
upper = inf(n, 1);
priorSigma = [0.010 * ones(height(parameters), 1); 0.0015 * wfDesign];
diffStep = [2e-4 * ones(height(parameters), 1); max(1e-6, 5e-5 * wfDesign)];
for i = 1:height(parameters)
    if parameters.scheduled(i)
        entry = schedule.healthEntries([schedule.healthEntries.cIndex] == ...
            parameters.c_index(i));
        active = true(size(entry.kNodes));
        if entry.pressureLoss
            active(1) = false;
        end
        values = entry.kNodes(active);
    else
        values = schedule.h15;
    end
    lower(i) = max(-0.025, parameters.lower_bound(i) - min(values));
    upper(i) = min(0.025, parameters.upper_bound(i) - max(values));
end
fuelValues = schedule.fuelBias.biasNodes;
lower(end) = max(-0.004 * wfDesign, -0.02 * wfDesign - min(fuelValues));
upper(end) = min(0.004 * wfDesign, 0.02 * wfDesign - max(fuelValues));
end

function [residual, meta] = local_constant_objective( ...
        x, route, engine, cfg, data, parameters, weighting, ...
        priorCenter, priorSigma, options, regularizationMethod)
model = local_constant_model(parameters, x(1:height(parameters)), x(end));
[prediction, valid] = local_evaluate_dataset( ...
    route, engine, cfg, data, model, options);
dataResidual = local_data_residual(route, data, prediction, weighting);
if ~valid || any(~isfinite(dataResidual))
    dataResidual = local_penalty_residual(numel(dataResidual));
end
regularization = (x(:) - priorCenter(:)) ./ priorSigma(:);
if strcmpi(regularizationMethod, 'tikhonov')
    residual = [dataResidual; regularization];
else
    % TSVD直接作用于数据雅可比。弱奇异方向被截断后保持在当前值，
    % 不再通过附加伪观测行改变数据残差的奇异谱。
    residual = dataResidual;
end
meta = struct('valid', valid, 'prediction', prediction, ...
    'dataResidual', dataResidual, 'regularization', regularization, ...
    'regularizationMethod', char(regularizationMethod));
end

function [residual, meta] = local_schedule_objective( ...
        offset, baseSchedule, route, engine, cfg, data, ...
        parameters, weighting, priorSigma, options, regularizationMethod)
schedule = local_apply_schedule_offsets(baseSchedule, offset, parameters);
model = local_schedule_model(schedule);
[prediction, valid] = local_evaluate_dataset( ...
    route, engine, cfg, data, model, options);
dataResidual = local_data_residual(route, data, prediction, weighting);
if ~valid || any(~isfinite(dataResidual))
    dataResidual = local_penalty_residual(numel(dataResidual));
end
regularization = offset(:) ./ priorSigma(:);
if strcmpi(regularizationMethod, 'tikhonov')
    residual = [dataResidual; regularization];
else
    residual = dataResidual;
end
meta = struct('valid', valid, 'prediction', prediction, ...
    'dataResidual', dataResidual, 'regularization', regularization, ...
    'regularizationMethod', char(regularizationMethod), ...
    'schedule', schedule);
end

function residual = local_penalty_residual(n)
residual = 1e3 * ones(n, 1);
end

function solve = local_bounded_lm(varargin)
% A整体/B单组为明确安全单元；未完成单元可重算，已完成求解不重复。
options=varargin{7};label=['constant_',varargin{8}];
if isfield(options,'runControl')
    [saved,found]=sht_tc24_run_control('load',options.runControl,label);
    if found,solve=saved.solve;return;end
end
solve=local_bounded_lm_impl(varargin{:});
if isfield(options,'runControl')
    sht_tc24_run_control('boundary',options.runControl,label,struct('solve',solve));
end
end

function solve = local_bounded_lm_impl( ...
        objective, x0, lower, upper, diffStep, maxIteration, options, label, ...
        regularizationMethod, parameterScale, retainedCountRequested, ...
        useDirectTsvdInverse, jacobianMethod)
% 有界高斯-牛顿。Tikhonov使用增广残差；TSVD在参数尺度归一化
% 的数据雅可比上截断弱奇异方向。仅评价完整有界候选，不使用统一缩步。
x = min(max(x0(:), lower(:)), upper(:));
% 本函数已有名为lower的边界向量，不能调用同名MATLAB函数。
% 入口校验已经把方法名规范为小写，这里只做字符类型统一。
regularizationMethod = char(string(regularizationMethod));
isTsvd = strcmp(regularizationMethod, 'tsvd');
if ~islogical(useDirectTsvdInverse) || ...
        ~isscalar(useDirectTsvdInverse)
    error('SHT:SteadyAdaptV2:BadDirectTsvdSwitch', ...
        '%s的TSVD直接伪逆开关必须为逻辑标量。', label);
end
useDirectTsvdInverse = isTsvd && useDirectTsvdInverse;
if isTsvd && ~useDirectTsvdInverse
    error('SHT:SteadyAdaptV2:DampedTsvdForbidden', ...
        ['%s请求了非严格伪逆TSVD。当前工程禁止阻尼TSVD；' ...
         '请改用direct_inverse并在必要时减少保留奇异方向数。'], label);
end
parameterScale = parameterScale(:);
if numel(parameterScale) ~= numel(x) || ...
        any(~isfinite(parameterScale) | parameterScale <= 0)
    error('SHT:SteadyAdaptV2:BadParameterScale', ...
        '%s的参数尺度必须与待估参数等长且均为有限正值。', label);
end
[r, meta] = objective(x);
if any(~isfinite(r)) || ~meta.valid
    error('SHT:SteadyAdaptV2:InitialObjectiveInvalid', ...
        '%s初始参数不能完成全部参与工况的合法模型回放。', label);
end
cost = 0.5 * (r' * r);
costInitial = cost;
initialX = x;
initialResidual = r;
initialMeta = meta;
initialJ = [];
initialDataJ = [];
initialJacobianAudit = table();
lambda = options.initialLambda;
history = repmat(local_empty_iteration_record(), maxIteration, 1);
lastRetainedCount = numel(x);
stopReason = "max_iteration";
converged = false;

for iteration = 1:maxIteration
    local_progress(options,label,iteration,maxIteration);
    [J, jacobianAudit] = local_compute_jacobian( ...
        objective, x, r, lower, upper, diffStep, jacobianMethod);
    if iteration == 1
        % 保存进入本阶段、尚未接受任何参数更新时的数据雅可比。阶段A
        % 的该快照就是零修正基准模型，可供后续与阶段D最终个体模型
        % 使用同一尺度开展局部可辨识性对比。这里只复用求解器本来就
        % 要计算的首次雅可比，不增加DLL差分回放。
        initialJ = J;
        initialJacobianAudit = jacobianAudit;
        initialDataResidualCount = numel(initialMeta.dataResidual);
        initialDataJ = initialJ(1:initialDataResidualCount, :);
    end
    if isTsvd
        % z=D^{-1}*Delta_x，Jz=J*D。D采用工程先验尺度，仅用于
        % 消除不同参数单位和量级的影响，不作为高斯先验惩罚项。
        scaledJ = J .* parameterScale.';
        [u, sMatrix, v] = svd(scaledJ, 'econ');
        singularValueIteration = diag(sMatrix);
        if isempty(singularValueIteration)
            numericalRankIteration = 0;
        else
            rankThreshold = max(size(scaledJ)) * ...
                eps(max(singularValueIteration));
            numericalRankIteration = sum( ...
                singularValueIteration > rankThreshold);
        end
        retainedCount = min([retainedCountRequested, ...
            numericalRankIteration, numel(singularValueIteration)]);
        if retainedCount < 1
            error('SHT:SteadyAdaptV2:ZeroTsvdRank', ...
                '%s的数据雅可比没有可保留的数值奇异方向。', label);
        end
        retainedSingularValue = singularValueIteration(1:retainedCount);
        % 纯TSVD伪逆：保留方向使用1/sigma，未保留方向不进入求和，
        % 因而其更新严格为零。数值零奇异值已由rankThreshold排除；
        % 此处不允许增加阻尼或其他隐式滤波。
        filterFactor = 1 ./ retainedSingularValue;
        stepScaled = -v(:, 1:retainedCount) * ...
            (filterFactor .* (u(:, 1:retainedCount)' * r));
        step = parameterScale .* stepScaled;
        lastRetainedCount = retainedCount;
    else
        gradient = J' * r;
        curvature = J' * J;
        diagonal = max(diag(curvature), 1);
        step = -(curvature + lambda * diag(diagonal)) \ gradient;
        lastRetainedCount = min(numel(x), rank(J));
    end
    normalizedStep = norm(step ./ max(upper - lower, eps));
    directionalDerivative = r' * (J * step);

    % 小步长本身就是既定收敛条件，必须在评价完整候选之前检查。如果将该判断
    % 放到候选步被接受之后，那么位于数值驻点附近的无阻尼TSVD会因为
    % 没有更低代价候选而被误报为no_acceptable_step。
    if normalizedStep < options.stepRelativeTolerance
        history(iteration).iteration = iteration;
        history(iteration).cost_before = cost;
        history(iteration).cost_after = cost;
        history(iteration).cost_relative_change = 0;
        history(iteration).lambda = lambda;
        history(iteration).alpha = 0;
        history(iteration).step_relative_norm = normalizedStep;
        history(iteration).proposed_step_relative_norm = normalizedStep;
        history(iteration).directional_derivative = directionalDerivative;
        history(iteration).accepted = false;
        history(iteration).stop_reason = "parameter_step_small";
        converged = true;
        stopReason = "parameter_step_small";
        break;
    end

    accepted = false;
    trialCost = cost;
    trialX = x;
    trialR = r;
    trialMeta = meta;
    bestValidTrialCost = Inf;
    % 保留边界投影，但不把完整解乘0.5/0.25等统一比例。alpha仅保留为
    % 兼容历史诊断的接受标记：接受为1，未更新为0，不再用于计算候选。
    candidate = min(max(x + step, lower), upper);
    [candidateR, candidateMeta] = objective(candidate);
    candidateCost = 0.5 * (candidateR' * candidateR);
    candidateValid = all(isfinite(candidateR)) && candidateMeta.valid;
    if candidateValid
        bestValidTrialCost = candidateCost;
    end
    if candidateValid && candidateCost < cost
        accepted = true;
        trialCost = candidateCost;
        trialX = candidate;
        trialR = candidateR;
        trialMeta = candidateMeta;
    end

    history(iteration).iteration = iteration;
    history(iteration).cost_before = cost;
    history(iteration).cost_after = trialCost;
    history(iteration).lambda = lambda;
    history(iteration).alpha = double(accepted);
    history(iteration).proposed_step_relative_norm = normalizedStep;
    history(iteration).step_relative_norm = norm((trialX-x) ./ max(upper-lower,eps));
    history(iteration).full_candidate_valid = candidateValid;
    history(iteration).full_candidate_cost = candidateCost;
    history(iteration).directional_derivative = directionalDerivative;
    if isfinite(bestValidTrialCost)
        history(iteration).best_trial_relative_change = ...
            (bestValidTrialCost - cost) / max(cost, eps);
    end
    history(iteration).accepted = accepted;

    if ~accepted
        if isTsvd
            % 本点Jacobian已重算。固定r、固定差分步长且参数未改变，再次
            % 计算会得到相同完整候选。保留当前有效解并报告停滞，不能把
            % “一个非线性完整步不下降”当作驻点，也不能自动改r或加阻尼。
            stopReason = "full_tsvd_step_rejected_not_converged";
            history(iteration).stop_reason = stopReason;
            fprintf('%s：完整TSVD步未接受，保留当前有效解（未收敛）；未使用缩步或阻尼。\n',label);
            break;
        end
        history(iteration).stop_reason = "step_rejected";
        lambda = min(lambda * 10, 1e12);
        if lambda >= 1e10
            stopReason = "no_acceptable_step";
            break;
        end
        continue;
    end

    relativeCostChange = abs(cost - trialCost) / max(cost, eps);
    x = trialX;
    r = trialR;
    meta = trialMeta;
    cost = trialCost;
    if ~isTsvd
        lambda = max(lambda / 3, 1e-10);
    end
    history(iteration).cost_relative_change = relativeCostChange;
    % 小步长已由上方未缩放的完整步判定，不得用接受后的位移制造收敛。
    if relativeCostChange < options.costRelativeTolerance
        converged = true;
        stopReason = "cost_change_small";
        history(iteration).stop_reason = stopReason;
        break;
    end
end

iterationCount = iteration;
history = struct2table(history(1:iterationCount));

% 保存结果中的雅可比必须对应最终参数，而不是最后一次已接受步之前的
% 参数。该重算同时为后续工程可辨识性分析提供不含先验伪观测的数据
% 雅可比；它会增加一次n参数差分，但避免使用过时灵敏度得出错误结论。
[finalJ, finalJacobianAudit] = local_compute_jacobian( ...
    objective, x, r, lower, upper, diffStep, jacobianMethod);
lastJ = finalJ;
dataResidualCount = numel(meta.dataResidual);
dataJ = finalJ(1:dataResidualCount, :);
scaledDataJ = dataJ .* parameterScale.';
if isTsvd
    lastScaledJ = scaledDataJ;
else
    lastScaledJ = finalJ;
end
singularValues = svd(lastScaledJ, 'econ');
if isempty(singularValues)
    numericalRank = 0;
    conditionNumber = Inf;
else
    threshold = max(size(lastJ)) * eps(max(singularValues));
    numericalRank = sum(singularValues > threshold);
    if numericalRank >= 1
        conditionNumber = singularValues(1) / singularValues(numericalRank);
    else
        conditionNumber = Inf;
    end
end

solve = struct();
solve.label = label;
solve.x = x;
solve.initialX = initialX;
solve.initialResidual = initialResidual;
solve.initialDataResidual = initialMeta.dataResidual;
solve.initialJacobian = initialJ;
solve.initialDataJacobian = initialDataJ;
solve.initialJacobianAudit = initialJacobianAudit;
solve.converged = converged;
solve.stopReason = stopReason;
solve.iterationCount = iterationCount;
solve.costInitial = costInitial;
solve.costFinal = cost;
solve.residual = r;
solve.meta = meta;
solve.jacobian = lastJ;
solve.scaledJacobian = lastScaledJ;
solve.dataJacobian = dataJ;
solve.scaledDataJacobian = scaledDataJ;
solve.finalJacobianAudit = finalJacobianAudit;
solve.jacobianMethod = char(jacobianMethod);
solve.singularValues = singularValues;
solve.numericalRank = numericalRank;
solve.conditionNumber = conditionNumber;
solve.regularizationMethod = regularizationMethod;
solve.fullStepOnly = true;
solve.globalAlphaUsed = false;
if isTsvd
    solve.tsvdStepMode = 'direct_inverse';
else
    solve.tsvdStepMode = 'not_applicable';
end
solve.parameterScale = parameterScale;
solve.parameterCount = numel(x);
solve.dataResidualCount = dataResidualCount;
solve.lowerBound = lower(:);
solve.upperBound = upper(:);
solve.differenceStep = diffStep(:);
solve.informationMatrixDimension = [numel(x), numel(x)];
solve.requestedRetainedSingularValueCount = retainedCountRequested;
if isTsvd
    solve.retainedSingularValueCount = min(lastRetainedCount, numericalRank);
else
    solve.retainedSingularValueCount = numericalRank;
end
solve.truncatedSingularValueCount = max(0, ...
    numel(x) - solve.retainedSingularValueCount);
if solve.retainedSingularValueCount >= 1
    solve.retainedConditionNumber = singularValues(1) / ...
        singularValues(solve.retainedSingularValueCount);
else
    solve.retainedConditionNumber = Inf;
end
solve.history = history;
dataSingularValues = svd(scaledDataJ, 'econ');
solve.dataSingularValues = dataSingularValues;
if isempty(dataSingularValues)
    solve.dataNumericalRank = 0;
    solve.dataConditionNumber = Inf;
else
    dataRankThreshold = max(size(scaledDataJ)) * ...
        eps(max(dataSingularValues));
    solve.dataNumericalRank = sum(dataSingularValues > dataRankThreshold);
    if solve.dataNumericalRank >= 1
        solve.dataConditionNumber = dataSingularValues(1) / ...
            dataSingularValues(solve.dataNumericalRank);
    else
        solve.dataConditionNumber = Inf;
    end
end
end

function [J, audit] = local_compute_jacobian( ...
        objective, x, residual, lower, upper, diffStep, method)
% lower是本函数的边界向量，不能在此调用同名MATLAB文本函数。
method = string(method);
switch method
    case "strict_central"
        [J, audit] = local_strict_central_jacobian( ...
            objective, x, residual, lower, upper, diffStep);
    case "legacy_one_sided_fallback"
        J = local_legacy_finite_difference_jacobian( ...
            objective, x, residual, lower, upper, diffStep);
        audit = table();
    otherwise
        error('SHT:SteadyAdaptV2:UnknownJacobianMethod', ...
            '未知数值Jacobian方法：%s。', method);
end
end

function J = local_legacy_finite_difference_jacobian( ...
        objective, x, residual, lower, upper, diffStep)
% 只供冻结旧路线的辅助复现。它不是M3，也不得用于新的正式辨识结果。
% 不能把模型无效时返回的有限惩罚向量当作真实输出，否则雅可比会出现
% 人工巨大列，并直接污染奇异值、TSVD方向和可辨识性判断。
J = zeros(numel(residual), numel(x));
for j = 1:numel(x)
    direction = [1, -1];
    if x(j) + diffStep(j) > upper(j)
        direction = [-1, 1];
    end
    derivativeAvailable = false;
    for stepScale = [1, 0.5, 0.25, 0.125, 0.0625]
        for signValue = direction
            xp = x;
            xp(j) = min(max(x(j) + ...
                signValue * stepScale * diffStep(j), ...
                lower(j)), upper(j));
            actualStep = xp(j) - x(j);
            if actualStep == 0
                continue;
            end
            [rp, perturbedMeta] = objective(xp);
            if perturbedMeta.valid && all(isfinite(rp))
                J(:, j) = (rp - residual) / actualStep;
                derivativeAvailable = true;
                break;
            end
        end
        if derivativeAvailable
            break;
        end
    end
    if ~derivativeAvailable
        error('SHT:SteadyAdaptV2:FiniteDifferenceUnavailable', ...
            ['参数%d在正、反两个差分方向均不能完成合法模型回放；' ...
             '请减小差分步长或检查参数边界。'], j);
    end
end
end

function [J, audit] = local_strict_central_jacobian( ...
        objective, x, residual, lower, upper, diffStep, batchSize)
%LOCAL_STRICT_CENTRAL_JACOBIAN 严格成对、对称缩步的中心差分。
% 正负候选必须使用同一个实际步长并严格位于边界内。任一方向无效时，
% 两个方向一起缩步重算；绝不裁剪、换向或退化为单侧导数。
x = x(:);
residual = residual(:);
lower = lower(:);
upper = upper(:);
diffStep = diffStep(:);
if nargin < 7 || isempty(batchSize)
    batchSize = numel(x);
end
if ~isnumeric(batchSize) || ~isscalar(batchSize) || ...
        ~isfinite(batchSize) || batchSize < 1 || batchSize ~= round(batchSize)
    error('SHT:SteadyAdaptV2:BadCentralDifferenceBatchSize', ...
        '中心差分批大小必须为正整数。');
end
if numel(lower) ~= numel(x) || numel(upper) ~= numel(x) || ...
        numel(diffStep) ~= numel(x) || any(~isfinite(x)) || ...
        any(~isfinite(lower) & lower ~= -Inf) || ...
        any(~isfinite(upper) & upper ~= Inf) || ...
        any(~isfinite(diffStep) | diffStep <= 0)
    error('SHT:SteadyAdaptV2:BadCentralDifferenceInput', ...
        '中心差分的参数、边界和步长必须等长，参数有限且步长为有限正数。');
end
J = zeros(numel(residual), numel(x));
nodeIndex = (1:numel(x)).';
requestedStep = diffStep;
usedStep = nan(size(x));
shrinkCount = zeros(size(x));
positiveValid = false(size(x));
negativeValid = false(size(x));
candidateEvaluationCount = zeros(size(x));
actualPositiveStep = nan(size(x));
actualNegativeStep = nan(size(x));
scaleList = 2 .^ (0:-1:-12);
batchSize = min(batchSize, numel(x));
for batchStart = 1:batchSize:numel(x)
for j = batchStart:min(numel(x), batchStart + batchSize - 1)
    derivativeAvailable = false;
    for k = 1:numel(scaleList)
        h = diffStep(j) * scaleList(k);
        xp = x;
        xm = x;
        targetPlus = x(j) + h;
        targetMinus = x(j) - h;
        if ~(targetPlus < upper(j) && targetMinus > lower(j))
            continue;
        end
        xp(j) = targetPlus;
        xm(j) = targetMinus;
        plusStep = xp(j) - x(j);
        minusStep = x(j) - xm(j);
        stepTolerance = 32 * eps(max([1, abs(x(j)), abs(h)]));
        if abs(plusStep - h) > stepTolerance || ...
                abs(minusStep - h) > stepTolerance
            error('SHT:SteadyAdaptV2:CentralDifferenceStepMismatch', ...
                '参数%d的实际正负步长与目标步长不一致。', j);
        end
        [rp, plusMeta] = objective(xp);
        [rm, minusMeta] = objective(xm);
        candidateEvaluationCount(j) = candidateEvaluationCount(j) + 2;
        plusOk = plusMeta.valid && all(isfinite(rp));
        minusOk = minusMeta.valid && all(isfinite(rm));
        if plusOk && minusOk
            J(:, j) = (rp(:) - rm(:)) / (2 * h);
            usedStep(j) = h;
            shrinkCount(j) = k - 1;
            positiveValid(j) = true;
            negativeValid(j) = true;
            actualPositiveStep(j) = plusStep;
            actualNegativeStep(j) = minusStep;
            derivativeAvailable = true;
            break;
        end
    end
    if ~derivativeAvailable
        error('SHT:SteadyAdaptV2:CentralDifferenceUnavailable', ...
            ['参数%d无法取得一对边界内且回放有效的对称扰动；' ...
             '禁止退化为单侧差分。'], j);
    end
end
end
audit = table(nodeIndex, requestedStep, usedStep, shrinkCount, ...
    positiveValid, negativeValid, actualPositiveStep, actualNegativeStep, ...
    candidateEvaluationCount, ...
    'VariableNames', {'node_index','requested_step','used_step', ...
    'shrink_count','positive_valid','negative_valid', ...
    'actual_positive_step','actual_negative_step', ...
    'candidate_evaluation_count'});
end

function scale = local_stage_b_prior_scale(options, pointCount)
% 按本次实际分组的工况数选尺度，不依赖固定组号、真值或测试结果。
% 空表是旧统一方法；[s1,s2]分别用于1点和至少2点。所有参数含Wf同乘。
if ~isnumeric(pointCount) || ~isreal(pointCount) || ~isscalar(pointCount) || ...
        ~isfinite(pointCount) || pointCount<1 || pointCount~=fix(pointCount)
    error('SHT:SteadyAdaptV2:BadGroupPointCount','B组工况数必须为正整数。');
end
scale=options.stageBTikhonovPriorScale;
if ~isnumeric(scale) || ~isreal(scale) || ~isscalar(scale) || ...
        ~isfinite(scale) || scale<=0
    error('SHT:SteadyAdaptV2:BadStageBTikhonovPriorScale','B统一先验尺度必须为有限正数。');
end
if ~isfield(options,'stageBTikhonovPriorScaleByGroupSize') || ...
        isempty(options.stageBTikhonovPriorScaleByGroupSize)
    return;
end
values=options.stageBTikhonovPriorScaleByGroupSize;
if ~isnumeric(values) || ~isreal(values) || ~isvector(values) || ...
        numel(values)~=2 || any(~isfinite(values)) || any(values<=0)
    error('SHT:SteadyAdaptV2:BadStageBGroupPriorScale', ...
        'B分组先验尺度必须为空或[单工况尺度, 多工况尺度]两个有限正数。');
end
scale=values(1+double(pointCount>=2));
end

function solve = local_annotate_stage_b_solve( ...
        solve, priorCenter, parameterScale, method)
% 统一阶段B方法的诊断字段，便于同一对比程序直接汇总。
priorCenter = priorCenter(:);
parameterScale = parameterScale(:);
scaledDisplacement = (solve.x(:) - priorCenter) ./ parameterScale;
solve.stageBMethod = char(method);
solve.priorCenter = priorCenter;
solve.scaledPriorDisplacement = scaledDisplacement;
solve.scaledPriorDisplacementNorm = norm(scaledDisplacement);
solve.maxAbsScaledPriorDisplacement = max(abs(scaledDisplacement));
solve.dataCostFinal = 0.5 * sum(solve.meta.dataResidual(:) .^ 2);
solve.priorPenaltyCostFinal = ...
    0.5 * sum(solve.meta.regularization(:) .^ 2);
if ~isfield(solve, 'discardedSubspaceDisplacementNorm')
    solve.discardedSubspaceDisplacementNorm = NaN;
end
end

function record = local_empty_iteration_record()
record = struct('iteration', NaN, 'cost_before', NaN, ...
    'cost_after', NaN, 'cost_relative_change', NaN, ...
    'lambda', NaN, 'alpha', NaN, 'step_relative_norm', NaN, ...
    'proposed_step_relative_norm', NaN, ...
    'directional_derivative', NaN, ...
    'best_trial_relative_change', NaN, ...
    'full_candidate_valid', false, 'full_candidate_cost', NaN, ...
    'accepted', false, 'stop_reason', "");
end

function group = local_empty_group_result()
group = struct('group_id', "", 'point_ids', "", ...
    'row_indices', [], 'x', [], 'solve', struct());
end

function correctedSpeed = local_measured_ac_corrected_speed(data, cfg)
% AC与CC由高压轴共同驱动。以设计点Ng0和288.15 K为基准，将实测
% 高压轴转速按实测Tt1换算，可得到不依赖模型回放路径的分组坐标。
if any(~isfinite(data.Ng_mean) | data.Ng_mean <= 0) || ...
        any(~isfinite(data.Tt1_mean) | data.Tt1_mean <= 0)
    error('SHT:SteadyAdaptV2:BadMeasuredAcSpeedInput', ...
        '构造压气机相对换算转速需要有限正值Ng_mean和Tt1_mean。');
end
correctedSpeed = (data.Ng_mean ./ cfg.engine.initial.Ng0) .* ...
    sqrt(288.15 ./ data.Tt1_mean);
end

function groups = local_cluster_by_ac_speed(data, correctedSpeed, spanLimit)
correctedSpeed = correctedSpeed(:);
if numel(correctedSpeed) ~= height(data) || ...
        any(~isfinite(correctedSpeed))
    error('SHT:SteadyAdaptV2:BadClusterCoordinate', ...
        '压气机相对换算转速分组坐标必须与训练工况等长且全部有限。');
end
[sortedSpeed, order] = sort(correctedSpeed);
clusterMembers = {};
startIndex = 1;
for i = 2:numel(order)
    if sortedSpeed(i) - sortedSpeed(startIndex) > spanLimit
        clusterMembers{end + 1, 1} = order(startIndex:(i - 1)); %#ok<AGROW>
        startIndex = i;
    end
end
clusterMembers{end + 1, 1} = order(startIndex:end);

record = repmat(struct('group_id', "", 'point_ids', "", ...
    'point_count', NaN, 'ac_ncr_mean', NaN, 'ac_ncr_min', NaN, ...
    'ac_ncr_max', NaN, 'row_indices', []), numel(clusterMembers), 1);
for i = 1:numel(clusterMembers)
    idx = clusterMembers{i}(:);
    speed = correctedSpeed(idx);
    record(i).group_id = string(sprintf('G%02d', i));
    record(i).point_ids = strjoin(data.point_id(idx), ',');
    record(i).point_count = numel(idx);
    record(i).ac_ncr_mean = mean(speed);
    record(i).ac_ncr_min = min(speed);
    record(i).ac_ncr_max = max(speed);
    record(i).row_indices = idx;
end
groups = struct2table(record);
groups.coordinate_source(:) = "measured_Ng_Tt1";
end

function idx = local_group_row_indices(groups, groupIndex)
%LOCAL_GROUP_ROW_INDICES 兼容struct2table对等长数组的自动展开行为。
% 各组成员数不同时，row_indices是元胞列；全部组恰好都是单点组
% （或等长组）时，MATLAB会将其压缩成数值列或矩阵。两种表示均
% 恢复为同一个列向量下标，避免聚类结果改变时触发类型错误。
value = groups.row_indices;
if iscell(value)
    idx = value{groupIndex};
else
    idx = value(groupIndex, :);
end
idx = idx(:);
idx = idx(isfinite(idx) & idx >= 1 & idx == round(idx));
if isempty(idx)
    error('SHT:SteadyAdaptV2:EmptyGroupRows', ...
        '聚类组%d没有合法的训练工况行号。', groupIndex);
end
end

function prediction=local_stage_c_initial_coordinates(data,baseline,groupResults,options)
% B常值辨识的系数及运行横坐标应成对使用。对换算流量非常密集的
% 燃烧室，零修正坐标的微小错位可能先选3点、回放后又选2点，改变
% 后续先验。按point_id严格配对，不按组拼接顺序直接覆盖数据。
prediction=baseline;
source=options.stageCBurnerCoordinateSource;
assert(ismember(string(source),["baseline","group_corrected"]), ...
    'SHT:SteadyAdaptV2:BurnerCoordinateSource','未知燃烧室初始坐标来源。');
allGroupCoordinates=isfield(options,'stageCCoordinatePolicy') && ...
    ismember(string(options.stageCCoordinatePolicy), ...
    ["group_corrected_once","group_corrected_reanchor"]);
if allGroupCoordinates
    % 从实际参数字典取得全部需调度的发动机坐标，不硬编码某一部件。
    % 燃油偏置坐标在构造处始终来自data.Wf_mean，不能被模型燃油替换。
    parameters=local_parameter_definition(options);
    axes=cellstr(unique(parameters.axis_name(parameters.scheduled),'stable'));
elseif strcmp(source,'baseline')
    return;
else
    axes={'burner_inlet_corrected_mass_flow'};
end
ids=strings(0,1);x=zeros(0,numel(axes));
for g=1:numel(groupResults)
    p=groupResults(g).solve.meta.prediction;
    assert(all(ismember(axes,p.Properties.VariableNames)), ...
        'SHT:SteadyAdaptV2:MissingGroupAxis','B最终回放缺少调度坐标字段。');
    values=p{:,axes};
    assert(all(p.valid) && all(isfinite(values(:))) && all(values(:)>0), ...
        'SHT:SteadyAdaptV2:InvalidGroupCoordinates','B组回放坐标无效，不能用于C构造。');
    ids=[ids;string(p.point_id)];x=[x;values]; %#ok<AGROW>
end
assert(numel(unique(ids))==numel(ids), ...
    'SHT:SteadyAdaptV2:DuplicateGroupCoordinates','B结果中工况编号重复。');
[found,order]=ismember(string(data.point_id),ids);
assert(all(found) && numel(ids)==height(data) && ...
    isequal(string(data.point_id),string(baseline.point_id)), ...
    'SHT:SteadyAdaptV2:MissingGroupCoordinates','B结果与训练工况不能逐一对应。');
prediction{:,axes}=x(order,:);
end

function schedule = local_build_schedule( ...
        data, baselinePrediction, groups, groupResults, ...
        parameters, wfDesign, options)
groupTheta = zeros(numel(groupResults), numel(groupResults(1).x));
for groupIndex = 1:numel(groupResults)
    groupTheta(groupIndex, :) = groupResults(groupIndex).x(:).';
end
[~, designRow] = max(data.Wf_mean);
entries = repmat(local_empty_schedule_entry(), ...
    sum(parameters.scheduled), 1);
entryCounter = 0;
for p = 1:height(parameters)
    if ~parameters.scheduled(p)
        continue;
    end
    entryCounter = entryCounter + 1;
    axisField = char(parameters.axis_name(p));
    xGroup = zeros(height(groups), 1);
    kGroup = groupTheta(:, p);
    for g = 1:height(groups)
        idx = local_group_row_indices(groups, g);
        xGroup(g) = mean(baselinePrediction.(axisField)(idx));
    end
    rawGroupX = xGroup;
    rawGroupK = kGroup;
    conflictTolerance = options.nodeMergeConflictSigmaMultiplier * ...
        parameters.prior_sigma_group(p);
    [xGroup, kGroup, mergeCount, mergeDiagnostics] = ...
        local_merge_near_nodes(xGroup, kGroup, options, ...
        groups.point_count, parameters.name(p), conflictTolerance);
    pressureLoss = parameters.pressure_loss(p);
    if pressureLoss
        xCanonical = [0; xGroup(:)];
        kCanonical = [0; kGroup(:)];
    else
        xCanonical = xGroup(:);
        kCanonical = kGroup(:);
    end
    entry = local_empty_schedule_entry();
    entry.cIndex = parameters.c_index(p);
    entry.name = char(parameters.name(p));
    entry.axisName = axisField;
    entry.axisType = parameters.axis_type(p);
    entry.pressureLoss = pressureLoss;
    entry.xNodes = xCanonical;
    entry.kNodes = kCanonical;
    entry.designCoordinate = baselinePrediction.(axisField)(designRow);
    entry.lowerBound = parameters.lower_bound(p);
    entry.upperBound = parameters.upper_bound(p);
    entry.mergedNodeCount = mergeCount;
    entry.groupIds = string(groups.group_id);
    entry.groupCoordinates = rawGroupX(:);
    entry.groupValues = rawGroupK(:);
    entry.mergeDiagnostics = mergeDiagnostics;
    if options.adaptiveEvidenceNodes
        membership = local_point_group_membership(data, groups);
        formed = sht_identification_schedule_nodes('build', ...
            baselinePrediction.(axisField), membership, rawGroupK, ...
            pressureLoss, axisField, options);
        formed = local_fit_c_ordinates(formed,pressureLoss, ...
            entry.lowerBound,entry.upperBound,options);
        entry.xNodes = formed.xNodes;
        entry.kNodes = min(max(formed.kNodes,entry.lowerBound),entry.upperBound);
        if pressureLoss, entry.kNodes(1)=0; end
        entry.nodeFormation = formed.nodeFormation;
        entry.mergedNodeCount = height(data)-numel(formed.xNodes)+double(pressureLoss);
        local_report_evidence_conflict(formed.nodeFormation,conflictTolerance,entry.name,data);
        if formed.nodeFormation.selection.performed && options.verbose
            fprintf('燃烧室自动选点：%d个几何候选 -> %d个工作节点；原点固定。\n', ...
                numel(formed.nodeFormation.candidateX),numel(entry.xNodes)-1);
            disp(formed.nodeFormation.selection.scores);
        end
    end
    entry = local_refresh_schedule_entry(entry);
    entries(entryCounter) = entry;
end

xFuel = zeros(height(groups), 1);
kFuel = groupTheta(:, end);
for g = 1:height(groups)
    idx = local_group_row_indices(groups, g);
    xFuel(g) = mean(data.Wf_mean(idx) / wfDesign);
end
rawFuelX = xFuel;
rawFuelK = kFuel;
fuelConflictTolerance = options.nodeMergeConflictSigmaMultiplier * ...
    0.0025 * wfDesign;
[xFuel, kFuel, fuelMergeCount, fuelMergeDiagnostics] = ...
    local_merge_near_nodes(xFuel, kFuel, options, groups.point_count, ...
    "Wf_measurement_bias", fuelConflictTolerance);

schedule = struct();
schedule.schemaVersion = 'SHT_ESTIMATED_SCHEDULE_V2_VARIABLE_DLL_NODES';
schedule.interpolation = 'linear';
schedule.extrapolation = 'nearest_endpoint';
schedule.healthEntries = entries;
schedule.h15 = mean(groupTheta(:, find(parameters.c_index == 15, 1)));
schedule.fuelBias = struct('axisName', 'measured_wf_ratio', ...
    'xNodes', xFuel(:), 'biasNodes', kFuel(:), ...
    'mergedNodeCount', fuelMergeCount, 'wfDesign', wfDesign, ...
    'groupIds', string(groups.group_id), ...
    'groupCoordinates', rawFuelX(:), 'groupValues', rawFuelK(:), ...
    'mergeDiagnostics', fuelMergeDiagnostics);
if options.adaptiveEvidenceNodes
    formed=sht_identification_schedule_nodes('build', ...
        data.Wf_mean/wfDesign,local_point_group_membership(data,groups), ...
        rawFuelK,false,'measured_wf_ratio',options);
    formed=local_fit_c_ordinates(formed,false,-0.02*wfDesign,0.02*wfDesign,options);
    schedule.fuelBias.xNodes=formed.xNodes;
    schedule.fuelBias.biasNodes=formed.kNodes;
    schedule.fuelBias.nodeFormation=formed.nodeFormation;
    local_report_evidence_conflict(formed.nodeFormation, ...
        fuelConflictTolerance,'Wf_measurement_bias',data);
end
schedule.groupCount = height(groups);
schedule.designPointId = data.point_id(designRow);
schedule.designHealth = local_schedule_design_health(schedule);
end

function formed=local_fit_c_ordinates(formed,pressureLoss,lower,upper,options)
% 只拟合纵坐标，不改变节点选择、横坐标或原始B组证据；D的坐标迁移不调用它。
if strcmp(options.stageCOrdinatePolicy,'group_mean_fit')
    formed=sht_fit_group_node_ordinates(formed,pressureLoss,lower,upper);
end
end

function membership=local_point_group_membership(data,groups)
membership=zeros(height(data),1);
for g=1:height(groups),membership(local_group_row_indices(groups,g))=g;end
assert(all(membership>0),'SHT:SteadyAdaptV2:MissingNodeGroup','每个训练工况必须属于一个组。');
end

function local_report_evidence_conflict(f,tolerance,name,data)
% 提示工况及差值，但冲突不会取消平均或阻断后续D阶段。
index=find(f.candidateVerticalSpread>tolerance);
for j=index(:).'
    if isfield(f,'candidatePointRows')
        rows=f.candidatePointRows{j};source=strjoin(data.point_id(rows),',');
    else
        source="legacy_not_recorded";
    end
    warning('SHT:SteadyAdaptV2:NodeEvidenceConflict', ...
        '%s候选簇%d（%s）组值跨度%.6g，超过提示尺度%.6g；按工况权重平均并继续D辨识。', ...
        name,j,source,f.candidateVerticalSpread(j),tolerance);
end
end

function direct = local_build_direct_inlet_pressure_loss( ...
        trainingData, trainingPrediction, testData, testPrediction, options)
% 模式4已由C程序按实际进口方程反算每个工况的附加压损。这里只做
% 排序、近邻节点合并和线性拟合，不再把h0放回联合参数优化。
required = {'inlet_corrected_mass_flow', ...
    'inlet_pressure_loss_correction', 'Pt1_internal', 'Pt2_measured', ...
    'inlet_nominal_loss', 'inlet_total_loss', 'inlet_ram_recovery'};
if ~all(ismember(required, trainingPrediction.Properties.VariableNames))
    error('SHT:SteadyAdaptV2:MissingDirectInletFields', ...
        '模式4回放结果缺少进气道压损直接反算字段。');
end
valid = trainingPrediction.valid & ...
    isfinite(trainingPrediction.inlet_corrected_mass_flow) & ...
    isfinite(trainingPrediction.inlet_pressure_loss_correction);
if ~all(valid)
    error('SHT:SteadyAdaptV2:InvalidDirectInletEstimate', ...
        '存在不能用于进气道压损直接拟合的训练工况。');
end
xRaw = trainingPrediction.inlet_corrected_mass_flow;
kRaw = trainingPrediction.inlet_pressure_loss_correction;
[xMerged, kMerged, mergeCount, mergeDiagnostics] = ...
    local_merge_near_nodes(xRaw, kRaw, options, ones(size(xRaw)), ...
    "Inlet_K_dP", 0.012 * options.nodeMergeConflictSigmaMultiplier);
if xMerged(1) <= 0
    error('SHT:SteadyAdaptV2:NonPositiveInletFlowNode', ...
        '训练工况的进口换算流量节点必须为正。');
end

entry = local_empty_schedule_entry();
entry.cIndex = 0;
entry.name = 'Inlet_K_dP';
entry.axisName = 'inlet_corrected_mass_flow';
entry.axisType = 1;
entry.pressureLoss = true;
entry.xNodes = [0; xMerged(:)];
entry.kNodes = [0; kMerged(:)];
[~, designRow] = max(trainingData.Wf_mean);
entry.designCoordinate = xRaw(designRow);
entry.lowerBound = -0.02;
entry.upperBound = 0.15;
entry.mergedNodeCount = mergeCount;
entry.groupIds = string(trainingData.point_id);
entry.groupCoordinates = xRaw(:);
entry.groupValues = kRaw(:);
entry.mergeDiagnostics = mergeDiagnostics;
entry = local_refresh_schedule_entry(entry);

trainingTable = local_direct_inlet_detail_table( ...
    trainingData, trainingPrediction, entry);
if ~isempty(testData) && ~isempty(testPrediction)
    testTable = local_direct_inlet_detail_table( ...
        testData, testPrediction, entry);
else
    testTable = table();
end
direct = struct();
direct.method = 'mode4_exact_equation_inversion_and_linear_fit';
direct.interpolation = 'linear';
direct.extrapolation = 'nearest_endpoint';
direct.entry = entry;
direct.trainingTable = trainingTable;
direct.testTable = testTable;
direct.rawTrainingNodeCount = numel(xRaw);
direct.mergedPositiveNodeCount = numel(xMerged);
direct.mergeCount = mergeCount;
direct.designValue = entry.designValue;
end

function detail = local_direct_inlet_detail_table(data, prediction, entry)
x = prediction.inlet_corrected_mass_flow;
k = prediction.inlet_pressure_loss_correction;
kFit = arrayfun(@(value) local_interp_clamp( ...
    entry.xNodes, entry.kNodes, value), x);
detail = table(data.point_id, x, prediction.Pt1_internal, ...
    prediction.Pt2_measured, prediction.inlet_nominal_loss, ...
    k, prediction.inlet_total_loss, prediction.inlet_ram_recovery, ...
    kFit, k - kFit, ...
    'VariableNames', {'point_id','inlet_corrected_mass_flow', ...
    'Pt1_internal_Pa','Pt2_measured_Pa','nominal_loss', ...
    'direct_K_dP','total_loss','ram_recovery','fitted_K_dP', ...
    'fit_residual'});
end

function schedule = local_attach_direct_inlet_schedule(schedule, direct)
if any([schedule.healthEntries.cIndex] == 0)
    error('SHT:SteadyAdaptV2:DuplicateInletSchedule', ...
        '调度结构中已经存在h0，不能重复附加直接反算结果。');
end
schedule.healthEntries(end + 1) = direct.entry;
[~, order] = sort([schedule.healthEntries.cIndex]);
schedule.healthEntries = schedule.healthEntries(order);
schedule.directInletPressureLoss = direct;
schedule.designHealth = local_schedule_design_health(schedule);
end

function entry = local_empty_schedule_entry()
entry = struct('cIndex', NaN, 'name', '', 'axisName', '', ...
    'axisType', NaN, 'pressureLoss', false, 'xNodes', [], ...
    'kNodes', [], 'designCoordinate', NaN, 'designValue', NaN, ...
    'xNodesDll', [], 'kNodesDll', [], 'deltaNodesDll', [], ...
    'lowerBound', NaN, 'upperBound', NaN, 'mergedNodeCount', 0, ...
    'dllResamplingUsed', false, 'groupIds', strings(0, 1), ...
    'groupCoordinates', [], 'groupValues', [], ...
    'mergeDiagnostics', struct(), 'nodeFormation', struct());
end

function count = local_schedule_node_capacity()
% 与C端SHT_HEALTH_SCHEDULE_MAX_NODES保持一致。
count = 32;
end

function entry = local_refresh_schedule_entry(entry)
xNode = double(entry.xNodes(:));
kNode = double(entry.kNodes(:));
if isempty(xNode) || numel(xNode) ~= numel(kNode) || ...
        any(~isfinite(xNode)) || any(~isfinite(kNode)) || ...
        any(diff(xNode) <= 0)
    error('SHT:SteadyAdaptV2:InvalidScheduleNodes', ...
        '%s的有效节点必须等长、有限且横坐标严格递增。', entry.name);
end
minimumNodeCount = 1 + double(entry.pressureLoss);
maximumNodeCount = local_schedule_node_capacity();
if numel(xNode) < minimumNodeCount || numel(xNode) > maximumNodeCount
    error('SHT:SteadyAdaptV2:ScheduleNodeCapacity', ...
        '%s有效节点数为%d，DLL允许范围为%d~%d；禁止静默重采样。', ...
        entry.name, numel(xNode), minimumNodeCount, maximumNodeCount);
end
if entry.pressureLoss && ...
        (xNode(1) ~= 0 || abs(kNode(1)) > 1e-14)
    error('SHT:SteadyAdaptV2:PressureScheduleZeroAnchor', ...
        '%s压损调度首节点必须满足x=0且K_eff=0。', entry.name);
end

entry.xNodes = xNode;
entry.kNodes = kNode;
entry.designValue = local_interp_clamp( ...
    xNode, kNode, entry.designCoordinate);
% 估计有效节点就是DLL执行节点。保留Dll字段仅为兼容已有下游读取代码。
entry.xNodesDll = xNode;
entry.kNodesDll = kNode;
entry.deltaNodesDll = kNode - entry.designValue;
if entry.pressureLoss
    entry.deltaNodesDll(1) = -entry.designValue;
end
entry.dllResamplingUsed = false;
end

function health = local_schedule_design_health(schedule)
health = zeros(159, 1);
for i = 1:numel(schedule.healthEntries)
    entry = schedule.healthEntries(i);
    health(entry.cIndex + 1) = entry.designValue;
end
health(16) = schedule.h15;
end

function [xMerged, yMerged, mergeCount, detail] = ...
        local_merge_near_nodes(x, y, options, weights, label, ...
        conflictTolerance)
if nargin < 4 || isempty(weights)
    weights = ones(size(x));
end
if nargin < 5 || strlength(string(label)) == 0
    label = "unnamed_schedule";
end
if nargin < 6 || isempty(conflictTolerance)
    conflictTolerance = Inf;
end
[x, order] = sort(x(:));
y = y(order);
weights = weights(:);
weights = weights(order);
if numel(y) ~= numel(x) || numel(weights) ~= numel(x) || ...
        any(~isfinite(x) | ~isfinite(y) | ~isfinite(weights)) || ...
        any(weights <= 0)
    error('SHT:SteadyAdaptV2:BadMergeNodeInput', ...
        '调度函数%s的待合并横坐标、纵坐标和权重必须等长且有限，权重为正。', ...
        char(string(label)));
end
span = max(x) - min(x);
threshold = max(options.nodeMergeAbsolute, ...
    max(options.nodeMergeFraction * max(span, eps), ...
    options.nodeMergeRelativeFloor * max(1, median(abs(x)))));
xOut = [];
yOut = [];
memberX = x(1);
memberY = y(1);
memberWeight = weights(1);
conflictCount = 0;
maxVerticalSpread = 0;
for i = 2:numel(x)
    % 以整个候选簇的首点为基准，禁止“相邻点接龙”把总跨度超过门限的
    % 一串节点错误合并为一个节点。
    if x(i) - memberX(1) <= threshold
        memberX(end + 1, 1) = x(i); %#ok<AGROW>
        memberY(end + 1, 1) = y(i); %#ok<AGROW>
        memberWeight(end + 1, 1) = weights(i); %#ok<AGROW>
    else
        [xValue, yValue, conflict, verticalSpread] = ...
            local_finish_node_merge_cluster(memberX, memberY, ...
            memberWeight, label, conflictTolerance);
        xOut(end + 1, 1) = xValue; %#ok<AGROW>
        yOut(end + 1, 1) = yValue; %#ok<AGROW>
        conflictCount = conflictCount + double(conflict);
        maxVerticalSpread = max(maxVerticalSpread, verticalSpread);
        memberX = x(i);
        memberY = y(i);
        memberWeight = weights(i);
    end
end
[xValue, yValue, conflict, verticalSpread] = ...
    local_finish_node_merge_cluster(memberX, memberY, memberWeight, ...
    label, conflictTolerance);
xOut(end + 1, 1) = xValue;
yOut(end + 1, 1) = yValue;
conflictCount = conflictCount + double(conflict);
maxVerticalSpread = max(maxVerticalSpread, verticalSpread);
xMerged = xOut;
yMerged = yOut;
mergeCount = numel(x) - numel(xMerged);
detail = struct('label', string(label), 'sourceNodeCount', numel(x), ...
    'mergedNodeCount', numel(xMerged), 'removedNodeCount', mergeCount, ...
    'coordinateSpan', span, 'mergeThreshold', threshold, ...
    'conflictTolerance', conflictTolerance, ...
    'conflictCount', conflictCount, ...
    'maxVerticalSpread', maxVerticalSpread);
end

function [xValue, yValue, conflict, verticalSpread] = ...
        local_finish_node_merge_cluster(x, y, weights, label, ...
        conflictTolerance)
weightSum = sum(weights);
xValue = sum(weights .* x) / weightSum;
yValue = sum(weights .* y) / weightSum;
verticalSpread = max(y) - min(y);
conflict = numel(x) > 1 && verticalSpread > conflictTolerance;
if conflict
    warning('SHT:SteadyAdaptV2:LocalIdentificationConflict', ...
        ['调度函数%s存在横坐标过近但纵坐标差异较大的局部辨识冲突：' ...
         '纵向跨度=%.6g，警告门限=%.6g。程序按权重平均后继续执行。'], ...
        char(string(label)), verticalSpread, conflictTolerance);
end
end

function schedule = local_apply_schedule_offsets( ...
        baseSchedule, offset, parameters)
schedule = baseSchedule;
for p = 1:height(parameters)
    if parameters.scheduled(p)
        idx = find([schedule.healthEntries.cIndex] == ...
            parameters.c_index(p), 1);
        entry = schedule.healthEntries(idx);
        active = true(size(entry.kNodes));
        if entry.pressureLoss
            active(1) = false;
        end
        entry.kNodes(active) = entry.kNodes(active) + offset(p);
        entry.kNodes(active) = min(max(entry.kNodes(active), ...
            entry.lowerBound), entry.upperBound);
        if entry.pressureLoss
            entry.kNodes(1) = 0;
        end
        schedule.healthEntries(idx) = local_refresh_schedule_entry(entry);
    else
        schedule.h15 = min(max(schedule.h15 + offset(p), ...
            parameters.lower_bound(p)), parameters.upper_bound(p));
    end
end
schedule.fuelBias.biasNodes = schedule.fuelBias.biasNodes + offset(end);
fuelLimit = 0.02 * schedule.fuelBias.wfDesign;
schedule.fuelBias.biasNodes = min(max( ...
    schedule.fuelBias.biasNodes, -fuelLimit), fuelLimit);
schedule.designHealth = local_schedule_design_health(schedule);
end

function [stableSchedule, prediction, valid, retentionDetail] = ...
        local_stabilize_schedule(baseSchedule, stageAValue, route, ...
        engine, cfg, data, parameters, options)
% 组内估计分别合法，并不保证拼接后的曲线对所有点仍合法。采用从完整组间
% 形状到全局常值的同伦回缩。若阶段A常值在低流量门控后的调度表示中
% 仍不可行，再把绝对修正幅值连续回缩到已验证可行的零修正基线。
retentionCandidates = [1, 0.85, 0.70, 0.55, 0.40, 0.25, 0.10, 0];
stableSchedule = baseSchedule;
prediction = table();
valid = false;
retentionDetail = struct('shapeScale', NaN, 'absoluteScale', NaN, ...
    'strategy', "not_found");
for scale = retentionCandidates
    candidate = baseSchedule;
    for p = 1:height(parameters)
        if parameters.scheduled(p)
            idx = find([candidate.healthEntries.cIndex] == ...
                parameters.c_index(p), 1);
            entry = candidate.healthEntries(idx);
            active = true(size(entry.kNodes));
            if entry.pressureLoss
                active(1) = false;
            end
            entry.kNodes(active) = stageAValue(p) + scale * ...
                (entry.kNodes(active) - stageAValue(p));
            if isfield(entry,'nodeFormation') && ~isempty(fieldnames(entry.nodeFormation))
                entry.nodeFormation.groupValues=stageAValue(p)+scale* ...
                    (entry.nodeFormation.groupValues-stageAValue(p));
            end
            if entry.pressureLoss
                entry.kNodes(1) = 0;
            end
            candidate.healthEntries(idx) = local_refresh_schedule_entry(entry);
        else
            candidate.h15 = stageAValue(p) + scale * ...
                (candidate.h15 - stageAValue(p));
        end
    end
    candidate.fuelBias.biasNodes = stageAValue(end) + scale * ...
        (candidate.fuelBias.biasNodes - stageAValue(end));
    candidate.designHealth = local_schedule_design_health(candidate);
    [candidatePrediction, candidateValid] = local_evaluate_dataset( ...
        route, engine, cfg, data, local_schedule_model(candidate), options);
    if candidateValid
        stableSchedule = candidate;
        prediction = candidatePrediction;
        valid = true;
        retentionDetail.shapeScale = scale;
        retentionDetail.absoluteScale = 1;
        retentionDetail.strategy = "shape_homotopy";
        return;
    end
end

% 形状完全回缩仍无效时，说明阶段A绝对幅值与低流量门控组合后过强。
% 继续缩小绝对幅值；absoluteScale=0严格等价于零修正调度，因此只要
% 基线回放有效，本循环必然提供一个物理可行的阶段D初值。
absoluteCandidates = [0.75, 0.50, 0.25, 0.10, 0];
for absoluteScale = absoluteCandidates
    candidate = baseSchedule;
    for p = 1:height(parameters)
        if parameters.scheduled(p)
            idx = find([candidate.healthEntries.cIndex] == ...
                parameters.c_index(p), 1);
            entry = candidate.healthEntries(idx);
            entry.kNodes(:) = absoluteScale * stageAValue(p);
            if isfield(entry,'nodeFormation') && ~isempty(fieldnames(entry.nodeFormation))
                entry.nodeFormation.groupValues(:)=absoluteScale*stageAValue(p);
            end
            if entry.pressureLoss
                entry.kNodes(1) = 0;
            end
            candidate.healthEntries(idx) = local_refresh_schedule_entry(entry);
        else
            candidate.h15 = absoluteScale * stageAValue(p);
        end
    end
    candidate.fuelBias.biasNodes(:) = absoluteScale * stageAValue(end);
    candidate.designHealth = local_schedule_design_health(candidate);
    [candidatePrediction, candidateValid] = local_evaluate_dataset( ...
        route, engine, cfg, data, local_schedule_model(candidate), options);
    if candidateValid
        stableSchedule = candidate;
        prediction = candidatePrediction;
        valid = true;
        retentionDetail.shapeScale = 0;
        retentionDetail.absoluteScale = absoluteScale;
        retentionDetail.strategy = "absolute_homotopy";
        return;
    end
end
end

function detail = local_report_schedule_stabilization(detail)
% 用户允许保留C阶段物理可行性备用分支，但不能隐藏它对曲线的改变。
% 此分支不用于改善目标代价，也不替代D阶段完整正则化求解。
detail.fallbackUsed = detail.shapeScale < 1 || detail.absoluteScale < 1;
if detail.fallbackUsed
    detail.message = sprintf([ ...
        '阶段C触发备用可行性回缩：strategy=%s，形状保留=%.6g，' ...
        '绝对幅值保留=%.6g。组间曲线（含燃油偏置）已改变，' ...
        '该结果仅为阶段D初值，不表示辨识精度提高。'], ...
        char(detail.strategy), detail.shapeScale, detail.absoluteScale);
    warning('SHT:SteadyAdaptV2:ScheduleFeasibilityFallback', '%s', detail.message);
else
    detail.message = '阶段C原始组间曲线可行，未使用备用回缩（形状/幅值均为1）。';
    fprintf('%s\n', detail.message);
end
end

function maximumIterations = local_stage_d_iteration_budget(options)
%LOCAL_STAGE_D_ITERATION_BUDGET 计算阶段D允许的非线性迭代总数。
% 普通路线为maxIterationRefine。延续路线中每个物理正则层都是
% 一个完整的非线性求解，因而预算按层数累加。
maximumIterations = options.maxIterationRefine;
if strcmp(options.stageDParameterization, 'actual_execution_nodes') && ...
        isfield(options, 'stageDM3ContinuationRegularizationStrengths') && ...
        ~isempty(options.stageDM3ContinuationRegularizationStrengths)
    maximumIterations = maximumIterations * ...
        numel(options.stageDM3ContinuationRegularizationStrengths);
end
end

function [solve,refinedSchedule]=local_run_stage_d_pass(varargin)
% D1/D2各自为安全单元，保留其最终Jacobian、全部求解审计和原C先验。
options=varargin{11};label=['schedule_',varargin{12}];
if isfield(options,'runControl')
    [saved,found]=sht_tc24_run_control('load',options.runControl,label);
    if found,solve=saved.solve;refinedSchedule=saved.refinedSchedule;return;end
end
[solve,refinedSchedule]=local_run_stage_d_pass_impl(varargin{:});
if isfield(options,'runControl')
    sht_tc24_run_control('boundary',options.runControl,label, ...
        struct('solve',solve,'refinedSchedule',refinedSchedule));
end
end

function [solve, refinedSchedule] = local_run_stage_d_pass_impl( ...
        baseSchedule, priorCenterSchedule, initialOffset, ...
        route, engine, cfg, data, ...
        parameters, weighting, wfDesign, options, label)
if strcmp(options.stageDParameterization, 'actual_execution_nodes')
    [solve, refinedSchedule] = local_run_stage_d_m3_pass( ...
        baseSchedule, priorCenterSchedule, initialOffset, ...
        route, engine, cfg, data, ...
        parameters, weighting, wfDesign, options, label);
    return;
end
% 旧11维整曲线偏移只保留为显式辅助对照，不能标记为M3。
[lower, upper, priorSigma, differenceStep] = ...
    local_refine_parameter_settings(baseSchedule, parameters, wfDesign);
differenceStep = differenceStep .* options.stageDDifferenceStepScale;
parameterCount = height(parameters) + 1;
if isempty(initialOffset)
    x0 = zeros(parameterCount, 1);
else
    x0 = initialOffset(:);
    if numel(x0) ~= parameterCount || any(~isfinite(x0))
        error('SHT:SteadyAdaptV2:BadStageDInitialOffsetLength', ...
            '阶段D初值必须为空或包含%d个有限整体偏移量。', ...
            parameterCount);
    end
    if any(x0 < lower | x0 > upper)
        error('SHT:SteadyAdaptV2:StageDInitialOffsetOutOfBounds', ...
            '阶段D初值存在超出当前调度曲线可用参数边界的分量。');
    end
end

method = options.stageDRegularizationMethod;
priorSigmaUsed = priorSigma;
solveOptions = options;
if strcmp(method, 'tikhonov')
    priorSigmaUsed = priorSigma .* options.stageDTikhonovPriorScale;
else
    solveOptions.initialLambda = 0;
end
objective = @(x) local_schedule_objective( ...
    x, baseSchedule, route, engine, cfg, data, parameters, weighting, ...
    priorSigmaUsed, options, method);
solve = local_bounded_lm(objective, x0, lower, upper, ...
    differenceStep, options.maxIterationRefine, solveOptions, label, ...
    method, priorSigmaUsed, options.stageDTsvdRetainedCount, ...
    strcmp(method, 'tsvd'), options.stageDJacobianMethod);
solve.executed = true;
solve.initialOffset = x0;
solve.differenceStep = differenceStep;
solve.differenceStepScale = options.stageDDifferenceStepScale;
solve.lowerBound = lower;
solve.upperBound = upper;
relativeLowerMargin = (solve.x - lower) ./ max(upper - lower, eps);
relativeUpperMargin = (upper - solve.x) ./ max(upper - lower, eps);
solve.minimumRelativeBoundMargin = min([ ...
    relativeLowerMargin(:); relativeUpperMargin(:)]);
solve.atBound = solve.minimumRelativeBoundMargin <= 1e-8;
solve.parameterization = 'legacy_curve_offsets_auxiliary';
refinedSchedule = local_apply_schedule_offsets( ...
    baseSchedule, solve.x, parameters);
end

function contract = local_build_m3_node_contract( ...
        schedule, parameters, wfDesign, options)
%LOCAL_BUILD_M3_NODE_CONTRACT 从实际Stage-C调度动态冻结M3未知量。
% 顺序与现行节点UQ保持一致：9条受估健康曲线、Wf_bias全部节点、h15。
% 模式4直接反算的Inlet_K_dP整条排除；压损曲线(0,0)固定锚点排除。
if nargin < 3 || isempty(wfDesign)
    wfDesign = schedule.fuelBias.wfDesign;
end
if nargin < 4 || isempty(options)
    options = local_default_options('steady');
end
requiredSchedule = {'healthEntries','fuelBias','h15'};
if ~isstruct(schedule) || ~all(isfield(schedule, requiredSchedule))
    error('SHT:SteadyAdaptV2:BadM3Schedule', ...
        'M3节点合同要求完整的Stage-C调度结构。');
end
if ~istable(parameters) || ...
        ~all(ismember({'c_index','name','scheduled','pressure_loss', ...
        'lower_bound','upper_bound','prior_sigma_global','difference_step'}, ...
        parameters.Properties.VariableNames))
    error('SHT:SteadyAdaptV2:BadM3ParameterDictionary', ...
        'M3节点合同缺少完整参数字典。');
end

index = zeros(0, 1);
nodeId = strings(0, 1);
baseName = strings(0, 1);
cIndex = zeros(0, 1);
unit = strings(0, 1);
groupIndex = zeros(0, 1);
groupKind = strings(0, 1);
scheduleEntryIndex = zeros(0, 1);
dllNodeIndex = zeros(0, 1);
nodeIndex = zeros(0, 1);
coordinate = zeros(0, 1);
normalizedCoordinate = zeros(0, 1);
centerValue = zeros(0, 1);
lowerBound = zeros(0, 1);
upperBound = zeros(0, 1);
priorSigma = zeros(0, 1);
differenceStep = zeros(0, 1);
axisName = strings(0, 1);
pressureLoss = false(0, 1);
executionNode = false(0, 1);
counter = 0;
group = 0;

anchorBaseName = strings(0, 1);
anchorCIndex = zeros(0, 1);
anchorAxisName = strings(0, 1);
anchorNodeIndex = zeros(0, 1);
anchorCoordinate = zeros(0, 1);
anchorValue = zeros(0, 1);
anchorReason = strings(0, 1);

for p = 1:height(parameters)
    if ~parameters.scheduled(p)
        continue;
    end
    entryIndex = find([schedule.healthEntries.cIndex] == ...
        parameters.c_index(p), 1);
    if isempty(entryIndex)
        error('SHT:SteadyAdaptV2:M3ScheduleEntryMissing', ...
            'Stage-C调度缺少待估曲线%s。', parameters.name(p));
    end
    entry = schedule.healthEntries(entryIndex);
    if ~isequal(entry.xNodes(:), entry.xNodesDll(:)) || ...
            ~isequal(entry.kNodes(:), entry.kNodesDll(:)) || ...
            entry.dllResamplingUsed
        error('SHT:SteadyAdaptV2:M3DllNodeMismatch', ...
            '%s的估计节点与DLL实际执行节点不一致，拒绝构造M3。', ...
            parameters.name(p));
    end
    active = (1:numel(entry.xNodesDll)).';
    if entry.pressureLoss
        if entry.xNodesDll(1) ~= 0 || abs(entry.kNodesDll(1)) > 1e-14
            error('SHT:SteadyAdaptV2:M3PressureAnchorMismatch', ...
                '%s的固定压力损失锚点不是(0,0)。', parameters.name(p));
        end
        anchorBaseName(end + 1, 1) = string(parameters.name(p)); %#ok<AGROW>
        anchorCIndex(end + 1, 1) = parameters.c_index(p); %#ok<AGROW>
        anchorAxisName(end + 1, 1) = string(entry.axisName); %#ok<AGROW>
        anchorNodeIndex(end + 1, 1) = 1; %#ok<AGROW>
        anchorCoordinate(end + 1, 1) = 0; %#ok<AGROW>
        anchorValue(end + 1, 1) = 0; %#ok<AGROW>
        anchorReason(end + 1, 1) = "fixed_pressure_loss_zero_anchor"; %#ok<AGROW>
        active = active(2:end);
    end
    if isempty(active)
        error('SHT:SteadyAdaptV2:M3NoActiveScheduleNode', ...
            '%s没有可进入M3的活动节点。', parameters.name(p));
    end
    group = group + 1;
    for q = 1:numel(active)
        counter = counter + 1;
        j = active(q);
        index(counter, 1) = counter;
        nodeId(counter, 1) = sprintf('h%03d_n%03d', ...
            parameters.c_index(p), q);
        baseName(counter, 1) = string(parameters.name(p));
        cIndex(counter, 1) = parameters.c_index(p);
        unit(counter, 1) = "1";
        groupIndex(counter, 1) = group;
        groupKind(counter, 1) = "health_schedule";
        scheduleEntryIndex(counter, 1) = entryIndex;
        dllNodeIndex(counter, 1) = j;
        nodeIndex(counter, 1) = q;
        coordinate(counter, 1) = entry.xNodesDll(j);
        centerValue(counter, 1) = entry.kNodesDll(j);
        lowerBound(counter, 1) = parameters.lower_bound(p);
        upperBound(counter, 1) = parameters.upper_bound(p);
        priorSigma(counter, 1) = parameters.prior_sigma_global(p) * ...
            options.stageDTikhonovPriorScale;
        differenceStep(counter, 1) = parameters.difference_step(p) * ...
            options.stageDDifferenceStepScale;
        axisName(counter, 1) = string(entry.axisName);
        pressureLoss(counter, 1) = entry.pressureLoss;
        executionNode(counter, 1) = true;
    end
end

% 将模式4直接反算入口曲线作为显式排除项冻结，而不是依赖遍历顺序。
estimatedCIndex = parameters.c_index(parameters.scheduled);
for i = 1:numel(schedule.healthEntries)
    entry = schedule.healthEntries(i);
    if ismember(entry.cIndex, estimatedCIndex)
        continue;
    end
    for j = 1:numel(entry.xNodes)
        anchorBaseName(end + 1, 1) = string(entry.name); %#ok<AGROW>
        anchorCIndex(end + 1, 1) = entry.cIndex; %#ok<AGROW>
        anchorAxisName(end + 1, 1) = string(entry.axisName); %#ok<AGROW>
        anchorNodeIndex(end + 1, 1) = j; %#ok<AGROW>
        anchorCoordinate(end + 1, 1) = entry.xNodes(j); %#ok<AGROW>
        anchorValue(end + 1, 1) = entry.kNodes(j); %#ok<AGROW>
        anchorReason(end + 1, 1) = "excluded_direct_inlet_pt1_pt2_path"; %#ok<AGROW>
    end
end

fuel = schedule.fuelBias;
if isempty(fuel.xNodes) || ...
        numel(fuel.xNodes) ~= numel(fuel.biasNodes) || ...
        abs(fuel.wfDesign - wfDesign) > 32 * eps(max(1, abs(wfDesign)))
    error('SHT:SteadyAdaptV2:M3BadFuelSchedule', ...
        'Wf_bias节点或设计点燃油合同无效。');
end
group = group + 1;
fuelLimit = 0.02 * wfDesign;
for q = 1:numel(fuel.xNodes)
    counter = counter + 1;
    index(counter, 1) = counter;
    nodeId(counter, 1) = sprintf('wf_bias_n%03d', q);
    baseName(counter, 1) = "Wf_bias";
    cIndex(counter, 1) = -1;
    unit(counter, 1) = "kg/s";
    groupIndex(counter, 1) = group;
    groupKind(counter, 1) = "fuel_bias";
    scheduleEntryIndex(counter, 1) = 0;
    dllNodeIndex(counter, 1) = q;
    nodeIndex(counter, 1) = q;
    coordinate(counter, 1) = fuel.xNodes(q);
    centerValue(counter, 1) = fuel.biasNodes(q);
    lowerBound(counter, 1) = -fuelLimit;
    upperBound(counter, 1) = fuelLimit;
    priorSigma(counter, 1) = 0.003 * wfDesign * ...
        options.stageDTikhonovPriorScale;
    differenceStep(counter, 1) = max(1e-6, 5e-5 * wfDesign) * ...
        options.stageDDifferenceStepScale;
    axisName(counter, 1) = "measured_wf_ratio";
    pressureLoss(counter, 1) = false;
    executionNode(counter, 1) = true;
end

nozzleRow = find(parameters.c_index == 15, 1);
if isempty(nozzleRow)
    error('SHT:SteadyAdaptV2:M3NozzleMissing', ...
        '参数字典缺少Nozzle_K_A8/h15。');
end
group = group + 1;
counter = counter + 1;
index(counter, 1) = counter;
nodeId(counter, 1) = "h015_constant";
baseName(counter, 1) = "Nozzle_K_A8";
cIndex(counter, 1) = 15;
unit(counter, 1) = "1";
groupIndex(counter, 1) = group;
groupKind(counter, 1) = "constant";
scheduleEntryIndex(counter, 1) = 0;
dllNodeIndex(counter, 1) = 0;
nodeIndex(counter, 1) = 1;
coordinate(counter, 1) = 0;
centerValue(counter, 1) = schedule.h15;
lowerBound(counter, 1) = parameters.lower_bound(nozzleRow);
upperBound(counter, 1) = parameters.upper_bound(nozzleRow);
priorSigma(counter, 1) = parameters.prior_sigma_global(nozzleRow) * ...
    options.stageDTikhonovPriorScale;
differenceStep(counter, 1) = parameters.difference_step(nozzleRow) * ...
    options.stageDDifferenceStepScale;
axisName(counter, 1) = "constant";
pressureLoss(counter, 1) = false;
executionNode(counter, 1) = true;

for g = 1:group
    use = groupIndex == g;
    xGroup = coordinate(use);
    if numel(xGroup) == 1 || max(xGroup) == min(xGroup)
        normalizedCoordinate(use) = 0;
    else
        normalizedCoordinate(use) = ...
            (xGroup - min(xGroup)) / (max(xGroup) - min(xGroup));
    end
end

parameterTable = table(index, nodeId, baseName, cIndex, unit, groupIndex, ...
    groupKind, scheduleEntryIndex, dllNodeIndex, nodeIndex, coordinate, ...
    normalizedCoordinate, centerValue, lowerBound, upperBound, priorSigma, ...
    differenceStep, axisName, pressureLoss, executionNode, ...
    'VariableNames', {'index','node_id','base_name','c_index','unit', ...
    'group_index','group_kind','schedule_entry_index','dll_node_index', ...
    'node_index','coordinate','normalized_coordinate','center_value', ...
    'lower_bound','upper_bound','prior_sigma','difference_step', ...
    'axis_name','pressure_loss','execution_node'});
fixedAnchorTable = table(anchorBaseName, anchorCIndex, anchorAxisName, ...
    anchorNodeIndex, anchorCoordinate, anchorValue, anchorReason, ...
    'VariableNames', {'base_name','c_index','axis_name','node_index', ...
    'coordinate','value','reason'});
if any(centerValue < lowerBound | centerValue > upperBound) || ...
        any(~isfinite(priorSigma) | priorSigma <= 0) || ...
        any(~isfinite(differenceStep) | differenceStep <= 0)
    error('SHT:SteadyAdaptV2:M3NodeContractBounds', ...
        'M3活动节点必须位于闭物理边界内，且先验尺度和差分步长为正。');
end

contract = struct();
contract.schemaVersion = 'SHT_STEADY_MODEL_ADAPT_V2_M3_NODE_CONTRACT_V1';
contract.parameterization = 'actual_execution_nodes';
contract.jacobianMethod = 'node_central_full';
contract.parameterCount = height(parameterTable);
contract.groupCount = group;
contract.parameterTable = parameterTable;
contract.fixedAnchorTable = fixedAnchorTable;
contract.centerVector = centerValue;
contract.lowerBound = lowerBound;
contract.upperBound = upperBound;
contract.priorSigma = priorSigma;
contract.differenceStep = differenceStep;
contract.centerStrictlyInterior = all( ...
    centerValue > lowerBound & centerValue < upperBound);
contract.centerAtPhysicalBound = any( ...
    centerValue == lowerBound | centerValue == upperBound);
contract.scheduleTemplate = schedule;
contract.hashCanonicalization = 'm3_node_contract_utf8_v1';
contract.nodeContractHash = local_m3_node_contract_hash( ...
    parameterTable, fixedAnchorTable);

roundTrip = local_m3_schedule_to_vector(contract, ...
    local_m3_vector_to_schedule(contract, centerValue));
roundTripTolerance = 64 * eps(max(1, max(abs(centerValue))));
contract.roundTripMaximumAbsoluteError = max(abs(roundTrip - centerValue));
contract.roundTripPassed = ...
    contract.roundTripMaximumAbsoluteError <= roundTripTolerance;
if ~contract.roundTripPassed
    error('SHT:SteadyAdaptV2:M3NodeRoundTripFailure', ...
        'M3节点向量与调度结构往返误差超过数值容差。');
end
end

function schedule = local_m3_vector_to_schedule(contract, theta)
theta = theta(:);
if ~isstruct(contract) || ~isfield(contract, 'parameterTable') || ...
        ~isfield(contract, 'scheduleTemplate') || ...
        numel(theta) ~= contract.parameterCount || any(~isfinite(theta))
    error('SHT:SteadyAdaptV2:M3BadNodeVector', ...
        'M3节点向量必须与节点合同等长且全部有限。');
end
if any(theta < contract.lowerBound | theta > contract.upperBound)
    error('SHT:SteadyAdaptV2:M3NodeVectorOutOfBounds', ...
        'M3节点向量超出物理硬边界；禁止裁剪。');
end
schedule = contract.scheduleTemplate;
tbl = contract.parameterTable;
groups = unique(tbl.group_index, 'stable');
for g = groups(:).'
    rows = find(tbl.group_index == g);
    kind = tbl.group_kind(rows(1));
    switch char(kind)
        case 'health_schedule'
            entryIndex = tbl.schedule_entry_index(rows(1));
            entry = schedule.healthEntries(entryIndex);
            expectedNode = tbl.dll_node_index(rows);
            entry.kNodes(expectedNode) = theta(rows);
            entry = local_refresh_schedule_entry(entry);
            schedule.healthEntries(entryIndex) = entry;
        case 'fuel_bias'
            expectedNode = tbl.dll_node_index(rows);
            schedule.fuelBias.biasNodes(expectedNode) = theta(rows);
        case 'constant'
            if numel(rows) ~= 1
                error('SHT:SteadyAdaptV2:M3ConstantNodeMultiplicity', ...
                    'h15常值组必须且只能包含一个节点。');
            end
            schedule.h15 = theta(rows);
        otherwise
            error('SHT:SteadyAdaptV2:M3UnknownNodeKind', ...
                '未知M3节点组类型：%s。', kind);
    end
end
schedule.designHealth = local_schedule_design_health(schedule);
end

function theta = local_m3_schedule_to_vector(contract, schedule)
if ~isstruct(schedule) || ~isfield(schedule, 'healthEntries') || ...
        ~isfield(schedule, 'fuelBias') || ~isfield(schedule, 'h15')
    error('SHT:SteadyAdaptV2:M3BadScheduleForVector', ...
        '输入不是可提取M3节点的完整调度结构。');
end
tbl = contract.parameterTable;
theta = nan(contract.parameterCount, 1);
for i = 1:contract.parameterCount
    switch char(tbl.group_kind(i))
        case 'health_schedule'
            entry = schedule.healthEntries(tbl.schedule_entry_index(i));
            if entry.cIndex ~= tbl.c_index(i)
                error('SHT:SteadyAdaptV2:M3ScheduleEntryIdentityMismatch', ...
                    '节点%d的调度条目身份与合同不一致。', i);
            end
            theta(i) = entry.kNodesDll(tbl.dll_node_index(i));
        case 'fuel_bias'
            theta(i) = schedule.fuelBias.biasNodes(tbl.dll_node_index(i));
        case 'constant'
            theta(i) = schedule.h15;
        otherwise
            error('SHT:SteadyAdaptV2:M3UnknownNodeKind', ...
                '未知M3节点组类型：%s。', tbl.group_kind(i));
    end
end
if any(~isfinite(theta))
    error('SHT:SteadyAdaptV2:M3NonfiniteScheduleVector', ...
        '从调度结构提取的M3节点向量存在非有限值。');
end
end

function hashText = local_m3_node_contract_hash(parameterTable, anchorTable)
line = strings(height(parameterTable) + height(anchorTable) + 1, 1);
line(1) = "schema=SHT_STEADY_MODEL_ADAPT_V2_M3_NODE_CONTRACT_V1";
cursor = 1;
for i = 1:height(parameterTable)
    cursor = cursor + 1;
    line(cursor) = sprintf([ ...
        'A|%d|%s|%s|%.17g|%s|%d|%s|%d|%d|%d|%.17g|%.17g|' ...
        '%.17g|%.17g|%.17g|%.17g|%.17g|%s|%d|%d'], ...
        parameterTable.index(i), char(parameterTable.node_id(i)), ...
        char(parameterTable.base_name(i)), parameterTable.c_index(i), ...
        char(parameterTable.unit(i)), parameterTable.group_index(i), ...
        char(parameterTable.group_kind(i)), ...
        parameterTable.schedule_entry_index(i), ...
        parameterTable.dll_node_index(i), parameterTable.node_index(i), ...
        parameterTable.coordinate(i), ...
        parameterTable.normalized_coordinate(i), ...
        parameterTable.center_value(i), parameterTable.lower_bound(i), ...
        parameterTable.upper_bound(i), parameterTable.prior_sigma(i), ...
        parameterTable.difference_step(i), ...
        char(parameterTable.axis_name(i)), ...
        parameterTable.pressure_loss(i), parameterTable.execution_node(i));
end
for i = 1:height(anchorTable)
    cursor = cursor + 1;
    line(cursor) = sprintf('F|%s|%.17g|%s|%d|%.17g|%.17g|%s', ...
        char(anchorTable.base_name(i)), anchorTable.c_index(i), ...
        char(anchorTable.axis_name(i)), anchorTable.node_index(i), ...
        anchorTable.coordinate(i), anchorTable.value(i), ...
        char(anchorTable.reason(i)));
end
hashText = local_text_hash(strjoin(cellstr(line), newline));
end

function evaluation = local_m3_evaluate_node_vector( ...
        theta, contract, route, engine, cfg, data, weighting, options, ...
        candidateId, purpose, nodeIndex, signValue, stepValue)
timerValue = tic;
schedule = local_m3_vector_to_schedule(contract, theta);
roundTrip = local_m3_schedule_to_vector(contract, schedule);
roundTripError = max(abs(roundTrip - theta(:)));
roundTripTolerance = 64 * eps(max(1, max(abs(theta))));
if roundTripError > roundTripTolerance
    error('SHT:SteadyAdaptV2:M3AppliedNodeMismatch', ...
        'M3候选%s写入调度后的实际节点值与目标不一致。', candidateId);
end
seedMatrix=[];
replayOptions=options;
if strcmp(route,'steady') && nodeIndex>0 && options.stageDSteadyLocalBranch && ...
        isfield(options,'linearizationSolutionSeed')
    seedMatrix=options.linearizationSolutionSeed;
    replayOptions.steadyPerturbationSameBranch=true;
end
[prediction, replayValid, replayDiagnostic] = local_evaluate_dataset( ...
    route, engine, cfg, data, local_schedule_model(schedule), replayOptions,seedMatrix);
rawMatrix = local_raw_data_residual_matrix( ...
    route, data, prediction, cellstr(weighting.names));
rawResidual = rawMatrix(:);
whitenedResidual = local_data_residual(route, data, prediction, weighting);
valid = replayValid && all(isfinite(rawResidual)) && ...
    all(isfinite(whitenedResidual));

pointReplayCount = height(data);
invalidPointCount = pointReplayCount;
if istable(prediction) && ismember('valid', prediction.Properties.VariableNames)
    invalidPointCount = sum(~prediction.valid);
end
solveAttemptCount = pointReplayCount;
if istable(prediction) && ...
        ismember('np_branch_attempt_count', prediction.Properties.VariableNames)
    attempt = prediction.np_branch_attempt_count;
    attempt(~isfinite(attempt) | attempt < 1) = 1;
    solveAttemptCount = sum(attempt);
end
wallSeconds = toc(timerValue);
evaluation = struct();
evaluation.candidateId = char(candidateId);
evaluation.purpose = char(purpose);
evaluation.nodeIndex = nodeIndex;
evaluation.sign = signValue;
evaluation.step = stepValue;
evaluation.theta = theta(:);
evaluation.schedule = schedule;
evaluation.prediction = prediction;
evaluation.replayDiagnostic = replayDiagnostic;
evaluation.rawResidual = rawResidual;
evaluation.whitenedResidual = whitenedResidual;
evaluation.valid = logical(valid);
evaluation.pointReplayCount = pointReplayCount;
evaluation.solveAttemptCount = solveAttemptCount;
evaluation.invalidPointCount = invalidPointCount;
evaluation.cacheHitCount = 0;
evaluation.wallSeconds = wallSeconds;
evaluation.roundTripMaximumAbsoluteError = roundTripError;
end

function record = local_m3_candidate_record(evaluation)
record = struct('candidate_id', string(evaluation.candidateId), ...
    'purpose', string(evaluation.purpose), ...
    'node_index', evaluation.nodeIndex, ...
    'sign', evaluation.sign, 'step', evaluation.step, ...
    'point_replay_count', evaluation.pointReplayCount, ...
    'solve_attempt_count', evaluation.solveAttemptCount, ...
    'invalid_point_count', evaluation.invalidPointCount, ...
    'cache_hit_count', evaluation.cacheHitCount, ...
    'valid', evaluation.valid, ...
    'wall_seconds', evaluation.wallSeconds, ...
    'round_trip_maximum_absolute_error', ...
        evaluation.roundTripMaximumAbsoluteError);
end

function record = local_empty_m3_candidate_record()
record = struct('candidate_id', "", 'purpose', "", ...
    'node_index', NaN, 'sign', NaN, 'step', NaN, ...
    'point_replay_count', 0, 'solve_attempt_count', 0, ...
    'invalid_point_count', 0, 'cache_hit_count', 0, ...
    'valid', false, 'wall_seconds', 0, ...
    'round_trip_maximum_absolute_error', NaN);
end

function [rawJacobian, whitenedJacobian, auditTable, ...
        candidateRecords, usedStep] = local_m3_central_jacobian( ...
        contract, evaluator, baseEvaluation, options, label)
% 每个节点的正负候选均独立、完整回放全部训练点。batchSize只控制循环
% 分段，不改变候选或残差顺序，因此不同批量必须得到同一Jacobian。
theta0 = contract.centerVector;
d = contract.parameterCount;
rawJacobian = zeros(numel(baseEvaluation.rawResidual), d);
whitenedJacobian = zeros(numel(baseEvaluation.whitenedResidual), d);
usedStep = nan(d, 1);
requestedStep = contract.differenceStep;
shrinkCount = zeros(d, 1);
positiveValid = false(d, 1);
negativeValid = false(d, 1);
positiveCandidateId = strings(d, 1);
negativeCandidateId = strings(d, 1);
positiveWallSeconds = zeros(d, 1);
negativeWallSeconds = zeros(d, 1);
candidateEvaluationCount = zeros(d, 1);
minimumBoundMargin = min(theta0 - contract.lowerBound, ...
    contract.upperBound - theta0);
candidateRecords = repmat(local_empty_m3_candidate_record(), 0, 1);
batchSize = min(options.stageDM3BatchSize, d);
scaleList = 2 .^ (0:-1:-12);
for batchStart = 1:batchSize:d
    batchEnd = min(d, batchStart + batchSize - 1);
    for j = batchStart:batchEnd
        found = false;
        for k = 1:numel(scaleList)
            h = requestedStep(j) * scaleList(k);
            thetaPlus = theta0;
            thetaMinus = theta0;
            targetPlus = theta0(j) + h;
            targetMinus = theta0(j) - h;
            if ~(targetPlus < contract.upperBound(j) && ...
                    targetMinus > contract.lowerBound(j))
                continue;
            end
            thetaPlus(j) = targetPlus;
            thetaMinus(j) = targetMinus;
            actualPlus = thetaPlus(j) - theta0(j);
            actualMinus = theta0(j) - thetaMinus(j);
            stepTolerance = 32 * eps(max([1, abs(theta0(j)), abs(h)]));
            if abs(actualPlus - h) > stepTolerance || ...
                    abs(actualMinus - h) > stepTolerance
                error('SHT:SteadyAdaptV2:M3PerturbationMismatch', ...
                    '%s节点%d的实际正负扰动与目标步长不一致。', label, j);
            end
            plusId = sprintf('%s_node%04d_plus_s%02d', label, j, k - 1);
            minusId = sprintf('%s_node%04d_minus_s%02d', label, j, k - 1);
            plusEvaluation = evaluator(thetaPlus, plusId, ...
                'm3_positive_perturbation', j, 1, h);
            minusEvaluation = evaluator(thetaMinus, minusId, ...
                'm3_negative_perturbation', j, -1, h);
            candidateRecords(end + 1, 1) = ...
                local_m3_candidate_record(plusEvaluation); %#ok<AGROW>
            candidateRecords(end + 1, 1) = ...
                local_m3_candidate_record(minusEvaluation); %#ok<AGROW>
            candidateEvaluationCount(j) = candidateEvaluationCount(j) + 2;
            if plusEvaluation.valid && minusEvaluation.valid
                rawJacobian(:, j) = (plusEvaluation.rawResidual - ...
                    minusEvaluation.rawResidual) / (2 * h);
                whitenedJacobian(:, j) = ...
                    (plusEvaluation.whitenedResidual - ...
                    minusEvaluation.whitenedResidual) / (2 * h);
                usedStep(j) = h;
                shrinkCount(j) = k - 1;
                positiveValid(j) = true;
                negativeValid(j) = true;
                positiveCandidateId(j) = plusId;
                negativeCandidateId(j) = minusId;
                positiveWallSeconds(j) = plusEvaluation.wallSeconds;
                negativeWallSeconds(j) = minusEvaluation.wallSeconds;
                found = true;
                break;
            end
        end
        if ~found
            error('SHT:SteadyAdaptV2:M3CentralDifferenceUnavailable', ...
                ['%s节点%d（%s）无法取得一对边界内且回放有效的对称' ...
                 '候选；禁止单侧回退。'], label, j, ...
                 contract.parameterTable.node_id(j));
        end
    end
end
auditTable = table(contract.parameterTable.index, ...
    contract.parameterTable.node_id, contract.parameterTable.base_name, ...
    contract.parameterTable.unit, requestedStep, usedStep, shrinkCount, ...
    minimumBoundMargin, positiveValid, negativeValid, ...
    positiveCandidateId, negativeCandidateId, positiveWallSeconds, ...
    negativeWallSeconds, candidateEvaluationCount, ...
    'VariableNames', {'node_index','node_id','base_name','unit', ...
    'requested_step','used_step','shrink_count','minimum_bound_margin', ...
    'positive_valid','negative_valid','positive_candidate_id', ...
    'negative_candidate_id','positive_wall_seconds', ...
    'negative_wall_seconds','candidate_evaluation_count'});
end

function [stabilityTable, candidateRecords] = ...
        local_m3_step_stability(contract, evaluator, whitenedJacobian, ...
        usedStep, options, label)
% 选取健康、Wf_bias和h15中灵敏度最大的代表节点比较h与h/2。
d = contract.parameterCount;
columnNorm = sqrt(sum(whitenedJacobian .^ 2, 1)).';
selected = zeros(0, 1);
kindList = ["health_schedule", "fuel_bias", "constant"];
for k = 1:numel(kindList)
    idx = find(contract.parameterTable.group_kind == kindList(k));
    if isempty(idx)
        continue;
    end
    [~, localIndex] = max(columnNorm(idx));
    selected(end + 1, 1) = idx(localIndex); %#ok<AGROW>
end
[~, descending] = sort(columnNorm, 'descend');
for i = 1:numel(descending)
    if numel(selected) >= min(options.stageDM3StabilityNodeCount, d)
        break;
    end
    if ~ismember(descending(i), selected)
        selected(end + 1, 1) = descending(i); %#ok<AGROW>
    end
end
selected = selected(1:min(numel(selected), ...
    options.stageDM3StabilityNodeCount));
n = numel(selected);
nodeIndex = selected;
nodeId = contract.parameterTable.node_id(selected);
hStep = usedStep(selected);
halfStep = 0.5 * hStep;
relativeDifference = nan(n, 1);
fullNorm = columnNorm(selected);
halfNorm = nan(n, 1);
halfPairNpDifference=nan(n,1);
halfPairNgDifference=nan(n,1);
positiveValid = false(n, 1);
negativeValid = false(n, 1);
passed = false(n, 1);
candidateRecords = repmat(local_empty_m3_candidate_record(), 0, 1);
theta0 = contract.centerVector;
for i = 1:n
    j = selected(i);
    h = halfStep(i);
    thetaPlus = theta0;
    thetaMinus = theta0;
    thetaPlus(j) = theta0(j) + h;
    thetaMinus(j) = theta0(j) - h;
    plusEvaluation = evaluator(thetaPlus, ...
        sprintf('%s_node%04d_plus_half', label, j), ...
        'm3_h_half_stability_positive', j, 1, h);
    minusEvaluation = evaluator(thetaMinus, ...
        sprintf('%s_node%04d_minus_half', label, j), ...
        'm3_h_half_stability_negative', j, -1, h);
    candidateRecords(end + 1, 1) = ...
        local_m3_candidate_record(plusEvaluation); %#ok<AGROW>
    candidateRecords(end + 1, 1) = ...
        local_m3_candidate_record(minusEvaluation); %#ok<AGROW>
    positiveValid(i) = plusEvaluation.valid;
    negativeValid(i) = minusEvaluation.valid;
    if plusEvaluation.valid && minusEvaluation.valid
        halfPairNpDifference(i)=max(abs(plusEvaluation.prediction.Np-minusEvaluation.prediction.Np));
        halfPairNgDifference(i)=max(abs(plusEvaluation.prediction.Ng-minusEvaluation.prediction.Ng));
        halfDerivative = (plusEvaluation.whitenedResidual - ...
            minusEvaluation.whitenedResidual) / (2 * h);
        halfNorm(i) = norm(halfDerivative);
        denominator = max([norm(whitenedJacobian(:, j)), ...
            halfNorm(i), 1e-12]);
        relativeDifference(i) = ...
            norm(whitenedJacobian(:, j) - halfDerivative) / denominator;
        passed(i) = relativeDifference(i) <= ...
            options.stageDM3StabilityRelativeTolerance;
    end
end
stabilityTable = table(nodeIndex, nodeId, hStep, halfStep, fullNorm, ...
    halfNorm, relativeDifference, positiveValid, negativeValid, passed, ...
    'VariableNames', {'node_index','node_id','h','h_over_2', ...
    'h_derivative_norm','half_derivative_norm','relative_difference', ...
    'positive_valid','negative_valid','passed'});
stabilityTable.half_pair_max_Np_difference_rpm=halfPairNpDifference;
stabilityTable.half_pair_max_Ng_difference_rpm=halfPairNgDifference;
if ~all(passed)
    if strcmp(options.stageDM3StabilityPolicy,'diagnostic')
        % 保留原全节点对称差分，不把半步检验当成“精度已通过”。
        % 分段线性折点及求根分支均可能使割线随步长改变；继续非线性
        % 迭代与最终点新Jacobian检查，同时向结果报告传递未通过状态。
        warning('SHT:SteadyAdaptV2:M3StepStabilityDiagnostic', ...
            '%s差分稳定性诊断未通过，继续迭代；不将其标记为通过。',label);
        disp(stabilityTable(~passed,:));
    else
        error('SHT:SteadyAdaptV2:M3StepStabilityFailure', ...
            '%s代表节点h/h2中心差分稳定性未通过，失败节点=%s。', ...
            label, mat2str(nodeIndex(~passed).'));
    end
end
end

function [correlation, covariance, cholLower, groupTable] = ...
        local_m3_prior_covariance(contract, options)
% 同一曲线节点相关、不同曲线严格分块独立；Wf_bias保留kg/s尺度。
tbl = contract.parameterTable;
d = contract.parameterCount;
correlation = zeros(d);
groups = unique(tbl.group_index, 'stable');
groupIndex = zeros(numel(groups), 1);
name = strings(numel(groups), 1);
kind = strings(numel(groups), 1);
firstNode = zeros(numel(groups), 1);
lastNode = zeros(numel(groups), 1);
nodeCount = zeros(numel(groups), 1);
commonCorrelation = zeros(numel(groups), 1);
correlationLength = zeros(numel(groups), 1);
independentFraction = zeros(numel(groups), 1);
for k = 1:numel(groups)
    g = groups(k);
    idx = find(tbl.group_index == g);
    n = numel(idx);
    if tbl.group_kind(idx(1)) == "fuel_bias"
        omega = options.stageDM3FuelPriorCommonCorrelation;
        ell = options.stageDM3FuelPriorCorrelationLength;
        eta = options.stageDM3FuelPriorIndependentFraction;
    elseif n > 1
        omega = options.stageDM3NodePriorCommonCorrelation;
        ell = options.stageDM3NodePriorCorrelationLength;
        eta = options.stageDM3NodePriorIndependentFraction;
    else
        omega = 0;
        ell = 1;
        eta = 0;
    end
    if n == 1
        block = 1;
    else
        z = tbl.normalized_coordinate(idx);
        distance = z - z.';
        smoothBlock = omega * ones(n) + (1 - omega) * ...
            exp(-0.5 * (distance / ell) .^ 2);
        block = (1 - eta) * smoothBlock + eta * eye(n);
        block = 0.5 * (block + block.');
    end
    [~, flag] = chol(block);
    if flag ~= 0
        error('SHT:SteadyAdaptV2:M3PriorBlockNotPositiveDefinite', ...
            'M3先验组%d（%s）不是正定矩阵。', g, tbl.base_name(idx(1)));
    end
    correlation(idx, idx) = block;
    groupIndex(k) = g;
    name(k) = tbl.base_name(idx(1));
    kind(k) = tbl.group_kind(idx(1));
    firstNode(k) = idx(1);
    lastNode(k) = idx(end);
    nodeCount(k) = n;
    commonCorrelation(k) = omega;
    correlationLength(k) = ell;
    independentFraction(k) = eta;
end
sigma = contract.priorSigma(:);
covariance = (sigma * sigma.') .* correlation;
covariance = 0.5 * (covariance + covariance.');
[cholLower, flag] = chol(covariance, 'lower');
if flag ~= 0
    error('SHT:SteadyAdaptV2:M3PriorNotPositiveDefinite', ...
        '完整M3节点先验协方差不是正定矩阵。');
end
groupTable = table(groupIndex, name, kind, firstNode, lastNode, ...
    nodeCount, commonCorrelation, correlationLength, independentFraction, ...
    'VariableNames', {'group_index','name','kind','first_node', ...
    'last_node','node_count','common_correlation','correlation_length', ...
    'independent_fraction'});
end

function bundle = local_m3_prior_bundle(contract, options)
[correlation, covariance, cholLower, groupTable] = ...
    local_m3_prior_covariance(contract, options);
bundle = struct('correlation', correlation, 'covariance', covariance, ...
    'cholLower', cholLower, 'groupTable', groupTable);
end

function priorSchedule = local_m3_regrid_prior_center( ...
        stageCSchedule, targetGridSchedule, parameters)
%LOCAL_M3_REGRID_PRIOR_CENTER 将Stage-C先验函数重表达到D2节点坐标。
% D阶段重锚可能改变横坐标。D2的线性化点是D1重锚结果，但正则均值仍应
% 来自Stage-C；因此只在目标坐标查询Stage-C曲线，不继承D1纵向估计。
priorSchedule = targetGridSchedule;
for p = 1:height(parameters)
    if ~parameters.scheduled(p)
        continue;
    end
    cIndex = parameters.c_index(p);
    sourceIndex = find([stageCSchedule.healthEntries.cIndex] == cIndex, 1);
    targetIndex = find([priorSchedule.healthEntries.cIndex] == cIndex, 1);
    if isempty(sourceIndex) || isempty(targetIndex)
        error('SHT:SteadyAdaptV2:M3PriorRegridEntryMissing', ...
            'Stage-C或D2节点网格缺少c_index=%d的调度曲线。', cIndex);
    end
    source = stageCSchedule.healthEntries(sourceIndex);
    target = priorSchedule.healthEntries(targetIndex);
    for j = 1:numel(target.xNodes)
        target.kNodes(j) = local_interp_clamp( ...
            source.xNodes, source.kNodes, target.xNodes(j));
    end
    if target.pressureLoss
        target.kNodes(1) = 0;
    end
    target = local_refresh_schedule_entry(target);
    priorSchedule.healthEntries(targetIndex) = target;
end
for j = 1:numel(priorSchedule.fuelBias.xNodes)
    priorSchedule.fuelBias.biasNodes(j) = local_interp_clamp( ...
        stageCSchedule.fuelBias.xNodes, ...
        stageCSchedule.fuelBias.biasNodes, ...
        priorSchedule.fuelBias.xNodes(j));
end
priorSchedule.h15 = stageCSchedule.h15;
priorSchedule.designHealth = local_schedule_design_health(priorSchedule);
end

function [x, audit] = local_m3_box_quadratic_solve( ...
        hessian, linearTerm, lowerBound, upperBound, ...
        relativeKktTolerance, maximumIterations)
%LOCAL_M3_BOX_QUADRATIC_SOLVE 确定性活动集有界严格凸二次解。
% 求解 0.5*x'*H*x + q'*x，lower<=x<=upper。初值只用来建立
% 可行活动集；最终更新是通过KKT门的完整有界最优解，不是
% 对无约束解的静默裁剪，也不使用统一alpha或LM阻尼。
hessian = double(hessian);
linearTerm = double(linearTerm(:));
lowerBound = double(lowerBound(:));
upperBound = double(upperBound(:));
d = numel(linearTerm);
if ~isequal(size(hessian), [d, d]) || numel(lowerBound) ~= d || ...
        numel(upperBound) ~= d || any(~isfinite(hessian(:))) || ...
        any(~isfinite(linearTerm)) || any(~isfinite(lowerBound)) || ...
        any(~isfinite(upperBound)) || any(lowerBound >= upperBound)
    error('SHT:SteadyAdaptV2:M3BadBoxQuadraticInput', ...
        '有界二次问题的H/q/上下界维数或有限性无效。');
end
if ~isnumeric(relativeKktTolerance) || ~isscalar(relativeKktTolerance) || ...
        ~isfinite(relativeKktTolerance) || relativeKktTolerance <= 0 || ...
        ~isnumeric(maximumIterations) || ~isscalar(maximumIterations) || ...
        ~isfinite(maximumIterations) || maximumIterations < 1 || ...
        maximumIterations ~= round(maximumIterations)
    error('SHT:SteadyAdaptV2:M3BadBoxQuadraticTolerance', ...
        '有界二次求解器的KKT容差和最大迭代数无效。');
end
hessian = 0.5 * (hessian + hessian.');
[~, cholFlag] = chol(hessian);
if cholFlag ~= 0
    error('SHT:SteadyAdaptV2:M3BoxQuadraticNotPositiveDefinite', ...
        '有界二次问题的Hessian不是正定矩阵。');
end

% M3内部的x=0对应先验中心，正常严格可行。纯求解器测试
% 若0不可行，则以边界中点作为可行起点，不将它当作解。
x = zeros(d, 1);
if any(x < lowerBound | x > upperBound)
    x = 0.5 * (lowerBound + upperBound);
end
activeLower = false(d, 1);
activeUpper = false(d, 1);
primalTolerance = 64 * eps(max([1; abs(lowerBound); abs(upperBound)]));
passed = false;
releaseCount = 0;
boundHitCount = 0;
for iteration = 1:maximumIterations
    active = activeLower | activeUpper;
    free = ~active;
    equalitySolution = x;
    equalitySolution(activeLower) = lowerBound(activeLower);
    equalitySolution(activeUpper) = upperBound(activeUpper);
    if any(free)
        rhs = -linearTerm(free);
        if any(active)
            rhs = rhs - hessian(free, active) * equalitySolution(active);
        end
        equalitySolution(free) = hessian(free, free) \ rhs;
    end
    if any(~isfinite(equalitySolution))
        error('SHT:SteadyAdaptV2:M3BoxQuadraticNonfiniteStep', ...
            '有界二次求解器产生了非有限等式约束解。');
    end

    violatingLower = free & equalitySolution < lowerBound - primalTolerance;
    violatingUpper = free & equalitySolution > upperBound + primalTolerance;
    if any(violatingLower | violatingUpper)
        direction = equalitySolution - x;
        alpha = 1;
        movingUpper = find(free & direction > 0);
        movingLower = find(free & direction < 0);
        if ~isempty(movingUpper)
            alpha = min(alpha, min((upperBound(movingUpper) - ...
                x(movingUpper)) ./ direction(movingUpper)));
        end
        if ~isempty(movingLower)
            alpha = min(alpha, min((lowerBound(movingLower) - ...
                x(movingLower)) ./ direction(movingLower)));
        end
        if ~isfinite(alpha) || alpha < 0 || alpha > 1
            error('SHT:SteadyAdaptV2:M3BoxQuadraticBadFeasibleStep', ...
                '活动集到边界的可行步长无效：%.17g。', alpha);
        end
        x = x + alpha * direction;
        hitLower = free & abs(x - lowerBound) <= primalTolerance;
        hitUpper = free & abs(x - upperBound) <= primalTolerance;
        if ~any(hitLower | hitUpper)
            error('SHT:SteadyAdaptV2:M3BoxQuadraticNoBoundHit', ...
                '等式解越界但可行步未命中任一边界。');
        end
        activeLower(hitLower) = true;
        activeUpper(hitUpper) = true;
        boundHitCount = boundHitCount + sum(hitLower | hitUpper);
        continue;
    end
    x = equalitySolution;
    % 线性代数舍入可能令本应位于边界的自由解越界约1e-15。这里只把
    % 已证明处于求解器原始可行容差内的数值残差钉到精确边界，并将其
    % 纳入活动集；这不是对物理越界候选做裁剪。
    roundoffLower = free & x < lowerBound & ...
        x >= lowerBound - primalTolerance;
    roundoffUpper = free & x > upperBound & ...
        x <= upperBound + primalTolerance;
    if any(roundoffLower | roundoffUpper)
        x(roundoffLower) = lowerBound(roundoffLower);
        x(roundoffUpper) = upperBound(roundoffUpper);
        activeLower(roundoffLower) = true;
        activeUpper(roundoffUpper) = true;
        boundHitCount = boundHitCount + sum(roundoffLower | roundoffUpper);
        continue;
    end
    gradient = hessian * x + linearTerm;
    kktScale = max([norm(hessian * x, inf), norm(linearTerm, inf), 1]);
    absoluteKktTolerance = relativeKktTolerance * kktScale;
    lowerViolation = find(activeLower & gradient < -absoluteKktTolerance);
    upperViolation = find(activeUpper & gradient > absoluteKktTolerance);
    if ~isempty(lowerViolation) || ~isempty(upperViolation)
        candidate = [lowerViolation; upperViolation];
        violation = [ -gradient(lowerViolation); gradient(upperViolation)];
        [~, worst] = max(violation);
        release = candidate(worst);
        activeLower(release) = false;
        activeUpper(release) = false;
        releaseCount = releaseCount + 1;
        continue;
    end
    freeResidual = 0;
    if any(free)
        freeResidual = norm(gradient(free), inf);
    end
    if freeResidual <= absoluteKktTolerance
        passed = true;
        break;
    end
end

gradient = hessian * x + linearTerm;
primalViolation = max([max(lowerBound - x), max(x - upperBound), 0]);
free = ~(activeLower | activeUpper);
freeStationarity = 0;
if any(free)
    freeStationarity = norm(gradient(free), inf);
end
lowerDualViolation = max([0; -gradient(activeLower)]);
upperDualViolation = max([0; gradient(activeUpper)]);
kktResidual = max([primalViolation, freeStationarity, ...
    lowerDualViolation, upperDualViolation]);
kktScale = max([norm(hessian * x, inf), norm(linearTerm, inf), 1]);
relativeKktResidual = kktResidual / kktScale;
passed = passed && primalViolation <= primalTolerance && ...
    relativeKktResidual <= relativeKktTolerance;
audit = struct('method', 'deterministic_box_active_set', ...
    'iterationCount', iteration, 'maximumIterations', maximumIterations, ...
    'activeLower', activeLower, 'activeUpper', activeUpper, ...
    'activeBoundCount', sum(activeLower | activeUpper), ...
    'boundHitCount', boundHitCount, 'releaseCount', releaseCount, ...
    'gradient', gradient, 'primalViolation', primalViolation, ...
    'freeStationarityResidualInf', freeStationarity, ...
    'lowerDualViolation', lowerDualViolation, ...
    'upperDualViolation', upperDualViolation, ...
    'kktResidualInf', kktResidual, ...
    'relativeKktResidual', relativeKktResidual, ...
    'hessianReciprocalCondition', rcond(hessian), 'passed', passed);
if ~passed
    error('SHT:SteadyAdaptV2:M3BoxQuadraticKktFailure', ...
        ['有界二次求解未在%d次迭代内通过KKT门：' ...
         'primal=%.3e，relative KKT=%.3e。'], iteration, ...
        primalViolation, relativeKktResidual);
end
end

function [solve, refinedSchedule] = local_run_stage_d_m3_pass( ...
        baseSchedule, priorCenterSchedule, initialOffset, ...
        route, engine, cfg, data, ...
        parameters, weighting, wfDesign, options, label)
%LOCAL_RUN_STAGE_D_M3_PASS 可选的物理正则强度延续外层。
% 延续只改变求解初值，不改变Stage-C先验中心。最终结果的
% 概率/正则语义始终由序列最后一个lambda决定。
sequence = options.stageDM3ContinuationRegularizationStrengths(:).';
if isempty(sequence)
    sequence = options.stageDM3RegularizationStrength;
end
if numel(sequence) == 1
    singleOptions = options;
    singleOptions.stageDM3RegularizationStrength = sequence(1);
    [solve, refinedSchedule] = local_run_stage_d_m3_single_lambda_pass( ...
        baseSchedule, priorCenterSchedule, initialOffset, route, engine, ...
        cfg, data, parameters, weighting, wfDesign, singleOptions, label);
    solve.history.continuation_stage = ...
        ones(height(solve.history), 1);
    solve.history.continuation_lambda = ...
        repmat(sequence(1), height(solve.history), 1);
    solve.perturbationAudit.continuation_stage = ...
        ones(height(solve.perturbationAudit), 1);
    solve.perturbationAudit.continuation_lambda = ...
        repmat(sequence(1), height(solve.perturbationAudit), 1);
    solve.stepStability.continuation_stage = ...
        ones(height(solve.stepStability), 1);
    solve.stepStability.continuation_lambda = ...
        repmat(sequence(1), height(solve.stepStability), 1);
    solve.regularizationCandidates.continuation_stage = ...
        ones(height(solve.regularizationCandidates), 1);
    solve.regularizationCandidates.continuation_lambda = ...
        repmat(sequence(1), height(solve.regularizationCandidates), 1);
    solve.regularizationCandidates.continuation_final_selected = ...
        solve.regularizationCandidates.final_selected;
    solve.candidateReplayIdentity.continuation_stage = ...
        ones(height(solve.candidateReplayIdentity), 1);
    solve.candidateReplayIdentity.continuation_lambda = ...
        repmat(sequence(1), height(solve.candidateReplayIdentity), 1);
    solve.linearizationHistory.continuation_stage = ...
        ones(height(solve.linearizationHistory), 1);
    solve.linearizationHistory.continuation_lambda = ...
        repmat(sequence(1), height(solve.linearizationHistory), 1);
    if isfield(solve, 'trustRegionHistory') && ...
            ~isempty(solve.trustRegionHistory)
        solve.trustRegionHistory.continuation_stage = ...
            ones(height(solve.trustRegionHistory), 1);
        solve.trustRegionHistory.continuation_lambda = ...
            repmat(sequence(1), height(solve.trustRegionHistory), 1);
    end
    if isfield(solve, 'inexactNewtonHistory') && ...
            ~isempty(solve.inexactNewtonHistory)
        solve.inexactNewtonHistory.continuation_stage = ...
            ones(height(solve.inexactNewtonHistory), 1);
        solve.inexactNewtonHistory.continuation_lambda = ...
            repmat(sequence(1), height(solve.inexactNewtonHistory), 1);
    end
    solve.continuationUsed = false;
    solve.continuationRegularizationStrengths = sequence(:);
    solve.continuationStageCount = 1;
    solve.continuationAllStagesConverged = solve.converged;
    solve.continuationHistory = table(1, sequence(1), solve.converged, ...
        solve.iterationCount, string(solve.stopReason), solve.costFinal, ...
        solve.dataCostFinal, solve.wallSeconds, ...
        'VariableNames', {'continuation_stage','physical_lambda', ...
        'converged','iteration_count','stop_reason','final_total_objective', ...
        'final_data_cost','wall_seconds'});
    return;
end

stageSolve = cell(numel(sequence), 1);
currentSchedule = baseSchedule;
for iStage = 1:numel(sequence)
    stageOptions = options;
    stageOptions.stageDM3RegularizationStrength = sequence(iStage);
    stageOptions.stageDM3ContinuationRegularizationStrengths = sequence(iStage);
    stageLabel = sprintf('%s_continuation_%02d_lambda_%s', label, iStage, ...
        local_m3_number_tag(sequence(iStage)));
    stageInitialOffset = [];
    if iStage == 1
        stageInitialOffset = initialOffset;
    end
    [stageSolve{iStage}, currentSchedule] = ...
        local_run_stage_d_m3_single_lambda_pass( ...
        currentSchedule, priorCenterSchedule, stageInitialOffset, route, ...
        engine, cfg, data, parameters, weighting, wfDesign, stageOptions, ...
        stageLabel);
end

solve = stageSolve{end};
refinedSchedule = currentSchedule;
allHistory = table();
allPerturbation = table();
allStability = table();
allRegularization = table();
allCandidateReplay = table();
allTrustHistory = table();
allInexactNewtonHistory = table();
allLinearizationHistory = table();
allBounded = true;
allLinearPrediction = true;
continuationConverged = false(numel(sequence), 1);
continuationIterationCount = zeros(numel(sequence), 1);
continuationStopReason = strings(numel(sequence), 1);
continuationCost = nan(numel(sequence), 1);
continuationDataCost = nan(numel(sequence), 1);
continuationWall = nan(numel(sequence), 1);
for iStage = 1:numel(sequence)
    one = stageSolve{iStage};
    continuationConverged(iStage) = one.converged;
    continuationIterationCount(iStage) = one.iterationCount;
    continuationStopReason(iStage) = string(one.stopReason);
    continuationCost(iStage) = one.costFinal;
    continuationDataCost(iStage) = one.dataCostFinal;
    continuationWall(iStage) = one.wallSeconds;

    history = one.history;
    history.continuation_stage = repmat(iStage, height(history), 1);
    history.continuation_lambda = repmat(sequence(iStage), height(history), 1);
    allHistory = [allHistory; history]; %#ok<AGROW>
    perturbation = one.perturbationAudit;
    perturbation.continuation_stage = repmat(iStage, height(perturbation), 1);
    perturbation.continuation_lambda = ...
        repmat(sequence(iStage), height(perturbation), 1);
    allPerturbation = [allPerturbation; perturbation]; %#ok<AGROW>
    stability = one.stepStability;
    stability.continuation_stage = repmat(iStage, height(stability), 1);
    stability.continuation_lambda = ...
        repmat(sequence(iStage), height(stability), 1);
    allStability = [allStability; stability]; %#ok<AGROW>
    regularization = one.regularizationCandidates;
    regularization.continuation_stage = ...
        repmat(iStage, height(regularization), 1);
    regularization.continuation_lambda = ...
        repmat(sequence(iStage), height(regularization), 1);
    regularization.continuation_final_selected = ...
        false(height(regularization), 1);
    if iStage == numel(sequence)
        regularization.continuation_final_selected = ...
            regularization.final_selected;
    end
    regularization.final_selected = ...
        regularization.continuation_final_selected;
    allRegularization = [allRegularization; regularization]; %#ok<AGROW>
    replay = one.candidateReplayIdentity;
    replay.continuation_stage = repmat(iStage, height(replay), 1);
    replay.continuation_lambda = ...
        repmat(sequence(iStage), height(replay), 1);
    allCandidateReplay = [allCandidateReplay; replay]; %#ok<AGROW>
    linearHistory = one.linearizationHistory;
    linearHistory.continuation_stage = ...
        repmat(iStage, height(linearHistory), 1);
    linearHistory.continuation_lambda = ...
        repmat(sequence(iStage), height(linearHistory), 1);
    allLinearizationHistory = [allLinearizationHistory; linearHistory]; %#ok<AGROW>
    if isfield(one, 'trustRegionHistory') && ~isempty(one.trustRegionHistory)
        trustHistory = one.trustRegionHistory;
        trustHistory.continuation_stage = ...
            repmat(iStage, height(trustHistory), 1);
        trustHistory.continuation_lambda = ...
            repmat(sequence(iStage), height(trustHistory), 1);
        allTrustHistory = [allTrustHistory; trustHistory]; %#ok<AGROW>
    end
    if isfield(one, 'inexactNewtonHistory') && ...
            ~isempty(one.inexactNewtonHistory)
        inexactHistory = one.inexactNewtonHistory;
        inexactHistory.continuation_stage = ...
            repmat(iStage, height(inexactHistory), 1);
        inexactHistory.continuation_lambda = ...
            repmat(sequence(iStage), height(inexactHistory), 1);
        allInexactNewtonHistory = ...
            [allInexactNewtonHistory; inexactHistory]; %#ok<AGROW>
    end
    allBounded = allBounded && one.boundedSolution.passed;
    allLinearPrediction = allLinearPrediction && ...
        all(one.linearizationHistory.linear_prediction_passed);
end

solve.history = allHistory;
solve.perturbationAudit = allPerturbation;
solve.stepStability = allStability;
solve.stepStabilityPassed = all(allStability.passed);
solve.regularizationCandidates = allRegularization;
solve.candidateReplayIdentity = allCandidateReplay;
solve.linearizationHistory = allLinearizationHistory;
solve.linearPredictionCheck.history = allLinearizationHistory;
solve.trustRegionHistory = allTrustHistory;
solve.inexactNewtonHistory = allInexactNewtonHistory;
solve.replayAudit = local_m3_aggregate_replay_audit(stageSolve, options);
solve.replayAudit.continuationStageCount = numel(sequence);
solve.replayAudit.linearizationPassCount = sum(continuationIterationCount);
solve.iterationCount = sum(continuationIterationCount);
solve.m3LinearizationPassCount = solve.iterationCount;
solve.m3IterationCount = solve.iterationCount;
solve.maximumIterations = options.maxIterationRefine * numel(sequence);
solve.wallSeconds = sum(continuationWall);
solve.allBoundedSolutionsPassed = allBounded;
solve.allLinearPredictionChecksPassed = allLinearPrediction;
solve.continuationUsed = true;
solve.continuationRegularizationStrengths = sequence(:);
solve.continuationStageCount = numel(sequence);
solve.continuationAllStagesConverged = all(continuationConverged);
solve.continuationHistory = table((1:numel(sequence)).', sequence(:), ...
    continuationConverged, continuationIterationCount, ...
    continuationStopReason, continuationCost, continuationDataCost, ...
    continuationWall, 'VariableNames', {'continuation_stage', ...
    'physical_lambda','converged','iteration_count','stop_reason', ...
    'final_total_objective','final_data_cost','wall_seconds'});
solve.selectedRegularizationCandidateIndexAggregated = ...
    find(allRegularization.continuation_final_selected, 1, 'first');
solve.selectedRegularizationCandidateIndexSemantic = ...
    'within_final_continuation_linearization';
solve.lmDampingUsed = any(cellfun(@(x) x.lmDampingUsed, stageSolve));
solve.regularizedTrustRegionUsed = any(cellfun( ...
    @(x) isfield(x, 'regularizedTrustRegionUsed') && ...
    x.regularizedTrustRegionUsed, stageSolve));
solve.regularizingInexactNewtonUsed = any(cellfun( ...
    @(x) isfield(x, 'regularizingInexactNewtonUsed') && ...
    x.regularizingInexactNewtonUsed, stageSolve));
solve.uncontrolledLmDampingUsed = false;
solve.nonlinearConvergence.continuationAllStagesConverged = ...
    all(continuationConverged);
solve.nonlinearConvergence.totalContinuationIterations = ...
    sum(continuationIterationCount);
end

function tag = local_m3_number_tag(value)
tag = regexprep(sprintf('%.8g', value), '\.', 'p');
tag = regexprep(tag, '-', 'm');
tag = regexprep(tag, '\+', '');
end

function [solve, refinedSchedule] = local_run_stage_d_m3_single_lambda_pass( ...
        baseSchedule, priorCenterSchedule, initialOffset, ...
        route, engine, cfg, data, ...
        parameters, weighting, wfDesign, options, label)
%LOCAL_RUN_STAGE_D_M3_PASS 以固定Stage-C先验中心迭代重新线性化。
priorContract = local_build_m3_node_contract( ...
    priorCenterSchedule, parameters, wfDesign, options);
if ~priorContract.centerStrictlyInterior
    error('SHT:SteadyAdaptV2:M3PriorCenterAtBound', ...
        'Stage-C先验中心必须严格位于物理边界内。');
end
d = priorContract.parameterCount;
if ~isempty(initialOffset)
    initialOffset = initialOffset(:);
    if numel(initialOffset) ~= d || any(~isfinite(initialOffset)) || ...
            any(abs(initialOffset) > 0)
        error('SHT:SteadyAdaptV2:M3NonzeroInitialOffsetForbidden', ...
            ['M3必须以Stage-C实际节点值为正则中心；初始偏移' ...
             '只能为空或%d维全零向量。'], d);
    end
end

maximumIterations = options.maxIterationRefine;
passSolve = cell(maximumIterations, 1);
passSchedule = cell(maximumIterations, 1);
currentSchedule = baseSchedule;
converged = false;
trustState = struct('damping', options.stageDM3TrustInitialDamping);
confirmationAudits = cell(0, 1);
for k = 1:maximumIterations
    local_progress(options,label,k,maximumIterations);
    passLabel = sprintf('%s_linearization_%02d', label, k);
    % 每次非线性迭代都在当前精确DLL解处重新计算完整Jacobian。不存在
    % 独立的重新线性化次数上限，也不复用上一轮Jacobian。
    [oneSolve, candidateSchedule, trustState] = ...
        local_run_stage_d_m3_linearization( ...
        currentSchedule, priorContract, route, engine, cfg, data, ...
        parameters, weighting, options, passLabel, trustState);
    passSolve{k} = oneSolve;
    passSchedule{k} = candidateSchedule;
    currentSchedule = candidateSchedule;
    if oneSolve.nonlinearConvergence.proposedConverged
        % 候选步长和目标变化很小只表示“可能收敛”。接受后的参数点与
        % 本轮Jacobian线性化点不同，必须在候选点重新计算完整Jacobian，
        % 再检查有界正则化目标的一阶最优性。
        oneAudit = local_m3_final_convergence_audit( ...
            candidateSchedule, priorContract, oneSolve, route, engine, ...
            cfg, data, parameters, weighting, options, ...
            sprintf('%s_final_check_after_%02d', label, k));
        confirmationAudits{end + 1, 1} = oneAudit; %#ok<AGROW>
        if oneAudit.converged
            converged = true;
            finalIterationIndex = k;
            break;
        end
    end
end
passSolve = passSolve(1:k);
passSchedule = passSchedule(1:k);
if converged
    finalAudit = confirmationAudits{end};
    stopReason = 'fresh_final_jacobian_stationarity_converged';
else
    % 达到最大迭代次数不是异常。保留全部精确DLL历史，并选取正则化
    % 总目标最小的候选作为可比较结果，同时明确标记尚未满足收敛条件。
    totalObjective = cellfun(@(x) x.costFinal, passSolve);
    [~, finalIterationIndex] = min(totalObjective);
    % 即使达到最大更新次数，也在最终保留点执行一次独立新Jacobian审核。
    % 审核不再生成参数更新，因此不计入maximumIterations。
    finalAudit = local_m3_final_convergence_audit( ...
        passSchedule{finalIterationIndex}, priorContract, ...
        passSolve{finalIterationIndex}, route, engine, cfg, data, ...
        parameters, weighting, options, ...
        sprintf('%s_final_check_after_maximum', label));
    confirmationAudits{end + 1, 1} = finalAudit;
    converged = finalAudit.converged;
    if converged
        stopReason = 'fresh_final_jacobian_stationarity_converged';
    else
        stopReason = 'maximum_iterations_best_exact_iterate_retained_not_converged';
    end
end
solve = passSolve{finalIterationIndex};
refinedSchedule = passSchedule{finalIterationIndex};
solve.label = label;
solve.m3LinearizationPassCount = k;
solve.m3IterationCount = k;
solve.maximumIterations = maximumIterations;
solve.finalIterationIndex = finalIterationIndex;
solve.finalResultIsLastIteration = finalIterationIndex == k;
solve.priorCenterNodeContract = priorContract;
solve.priorCenterNodeContractHash = priorContract.nodeContractHash;

allHistory = table();
allPerturbation = table();
allStability = table();
allRegularization = table();
allCandidateReplay = table();
allTrustHistory = table();
allInexactNewtonHistory = table();
linearizationPass = (1:k).';
dataCostBefore = zeros(k, 1);
dataCostAfter = zeros(k, 1);
    selectedLambda = zeros(k, 1);
    gcvRecommendedLambda = zeros(k, 1);
    selectedRetainedCount = nan(k, 1);
    gcvRecommendedRetainedCount = nan(k, 1);
linearPredictionRelativeError = zeros(k, 1);
linearPredictionPassed = false(k, 1);
totalObjectiveBefore = zeros(k, 1);
totalObjectiveAfter = zeros(k, 1);
totalObjectiveRelativeChange = zeros(k, 1);
standardizedStepRelativeNorm = zeros(k, 1);
nonlinearConvergenceProposed = false(k, 1);
totalObjectiveDecreased = false(k, 1);
trustTrialCount = zeros(k, 1);
trustAcceptedDamping = nan(k, 1);
trustAcceptanceRatio = nan(k, 1);
inexactNewtonTrialCount = zeros(k, 1);
inexactNewtonAcceptedDamping = nan(k, 1);
inexactNewtonAcceptedResidualRatio = nan(k, 1);
inexactNewtonTargetResidualRatio = nan(k, 1);
inexactNewtonSearchIterationCount = zeros(k, 1);
finalResultSelected = false(k, 1);
finalResultSelected(finalIterationIndex) = true;
for i = 1:k
    one = passSolve{i};
    oneHistory = one.history;
    oneHistory.linearization_pass = repmat(i, height(oneHistory), 1);
    allHistory = [allHistory; oneHistory]; %#ok<AGROW>
    onePerturbation = one.perturbationAudit;
    onePerturbation.linearization_pass = ...
        repmat(i, height(onePerturbation), 1);
    onePerturbation.linearization_node_contract_sha256 = ...
        repmat(string(one.nodeContractHash), height(onePerturbation), 1);
    allPerturbation = [allPerturbation; onePerturbation]; %#ok<AGROW>
    oneStability = one.stepStability;
    oneStability.linearization_pass = repmat(i, height(oneStability), 1);
    allStability = [allStability; oneStability]; %#ok<AGROW>
    oneRegularization = one.regularizationCandidates;
    oneRegularization.linearization_pass = ...
        repmat(i, height(oneRegularization), 1);
    oneRegularization.linearization_node_contract_sha256 = ...
        repmat(string(one.nodeContractHash), height(oneRegularization), 1);
    oneRegularization.final_selected = false(height(oneRegularization), 1);
    if i == finalIterationIndex
        oneRegularization.final_selected = oneRegularization.selected;
    end
    allRegularization = [allRegularization; oneRegularization]; %#ok<AGROW>
    oneReplay = one.candidateReplayIdentity;
    oneReplay.linearization_pass = repmat(i, height(oneReplay), 1);
    oneReplay.linearization_node_contract_sha256 = ...
        repmat(string(one.nodeContractHash), height(oneReplay), 1);
    allCandidateReplay = [allCandidateReplay; oneReplay]; %#ok<AGROW>
    if isfield(one, 'trustRegionHistory') && ~isempty(one.trustRegionHistory)
        oneTrust = one.trustRegionHistory;
        oneTrust.linearization_pass = repmat(i, height(oneTrust), 1);
        oneTrust.linearization_node_contract_sha256 = ...
            repmat(string(one.nodeContractHash), height(oneTrust), 1);
        allTrustHistory = [allTrustHistory; oneTrust]; %#ok<AGROW>
        trustTrialCount(i) = height(oneTrust);
        acceptedTrust = find(oneTrust.accepted, 1, 'last');
        if ~isempty(acceptedTrust)
            trustAcceptedDamping(i) = oneTrust.algorithmic_damping(acceptedTrust);
            trustAcceptanceRatio(i) = oneTrust.reduction_ratio(acceptedTrust);
        end
    end
    if isfield(one, 'inexactNewtonHistory') && ...
            ~isempty(one.inexactNewtonHistory)
        oneInexact = one.inexactNewtonHistory;
        oneInexact.linearization_pass = repmat(i, height(oneInexact), 1);
        oneInexact.linearization_node_contract_sha256 = ...
            repmat(string(one.nodeContractHash), height(oneInexact), 1);
        allInexactNewtonHistory = ...
            [allInexactNewtonHistory; oneInexact]; %#ok<AGROW>
        inexactNewtonTrialCount(i) = height(oneInexact);
        acceptedInexact = find(oneInexact.accepted, 1, 'last');
        if ~isempty(acceptedInexact)
            inexactNewtonAcceptedDamping(i) = ...
                oneInexact.algorithmic_damping(acceptedInexact);
            inexactNewtonAcceptedResidualRatio(i) = ...
                oneInexact.linearized_augmented_residual_ratio(acceptedInexact);
            inexactNewtonTargetResidualRatio(i) = ...
                oneInexact.target_residual_ratio(acceptedInexact);
            inexactNewtonSearchIterationCount(i) = ...
                oneInexact.matrix_search_iteration_count(acceptedInexact);
        end
    end
    dataCostBefore(i) = one.dataCostInitial;
    dataCostAfter(i) = one.dataCostFinal;
    selectedLambda(i) = one.selectedRegularizationStrength;
    gcvRecommendedLambda(i) = ...
        one.gcvRecommendedRegularizationStrength;
    if isfield(one, 'selectedRetainedSingularValueCount')
        selectedRetainedCount(i) = ...
            one.selectedRetainedSingularValueCount;
        gcvRecommendedRetainedCount(i) = ...
            one.gcvRecommendedRetainedSingularValueCount;
    end
    linearPredictionRelativeError(i) = ...
        one.linearPredictionCheck.relativeResidualError;
    linearPredictionPassed(i) = one.linearPredictionCheck.passed;
    totalObjectiveBefore(i) = one.costInitial;
    totalObjectiveAfter(i) = one.costFinal;
    totalObjectiveRelativeChange(i) = ...
        one.nonlinearConvergence.totalObjectiveRelativeChange;
    standardizedStepRelativeNorm(i) = ...
        one.nonlinearConvergence.standardizedStepRelativeNorm;
    nonlinearConvergenceProposed(i) = ...
        one.nonlinearConvergence.proposedConverged;
    totalObjectiveDecreased(i) = ...
        one.nonlinearConvergence.totalObjectiveDecreased;
end
% 最终点审核是纯验证线性化，不属于参数更新迭代。为保证调用量和正式
% 工作簿可追溯，将其扰动与回放记录追加到审计表，但单独编号。
for i = 1:numel(confirmationAudits)
    oneAudit = confirmationAudits{i};
    auditPass = k + i;
    onePerturbation = oneAudit.perturbationAudit;
    onePerturbation.linearization_pass = ...
        repmat(auditPass, height(onePerturbation), 1);
    onePerturbation.linearization_node_contract_sha256 = ...
        repmat(string(oneAudit.nodeContractHash), ...
        height(onePerturbation), 1);
    allPerturbation = [allPerturbation; onePerturbation]; %#ok<AGROW>
    oneReplay = oneAudit.candidateReplayIdentity;
    oneReplay.linearization_pass = repmat(auditPass, height(oneReplay), 1);
    oneReplay.linearization_node_contract_sha256 = ...
        repmat(string(oneAudit.nodeContractHash), height(oneReplay), 1);
    allCandidateReplay = [allCandidateReplay; oneReplay]; %#ok<AGROW>
end
solve.finalLinearizationHistory = solve.history;
solve.finalPerturbationAudit = solve.perturbationAudit;
solve.finalStepStability = solve.stepStability;
solve.finalRegularizationCandidates = solve.regularizationCandidates;
solve.finalCandidateReplayIdentity = solve.candidateReplayIdentity;
solve.history = allHistory;
solve.perturbationAudit = allPerturbation;
solve.stepStability = allStability;
solve.stepStabilityPassed = all(allStability.passed);
solve.regularizationCandidates = allRegularization;
solve.selectedRegularizationCandidateIndexWithinFinalLinearization = ...
    solve.selectedRegularizationCandidateIndex;
solve.selectedRegularizationCandidateIndexAggregated = ...
    find(allRegularization.final_selected, 1, 'first');
solve.selectedRegularizationCandidateIndexSemantic = ...
    'within_final_linearization';
solve.candidateReplayIdentity = allCandidateReplay;
solve.trustRegionHistory = allTrustHistory;
solve.inexactNewtonHistory = allInexactNewtonHistory;
solve.linearizationHistory = table(linearizationPass, dataCostBefore, ...
    dataCostAfter, selectedLambda, gcvRecommendedLambda, ...
    selectedRetainedCount, gcvRecommendedRetainedCount, ...
    totalObjectiveBefore, totalObjectiveAfter, ...
    totalObjectiveRelativeChange, standardizedStepRelativeNorm, ...
    nonlinearConvergenceProposed, totalObjectiveDecreased, ...
    linearPredictionRelativeError, linearPredictionPassed, ...
    trustTrialCount, trustAcceptedDamping, trustAcceptanceRatio, ...
    inexactNewtonTrialCount, inexactNewtonAcceptedDamping, ...
    inexactNewtonAcceptedResidualRatio, inexactNewtonTargetResidualRatio, ...
    inexactNewtonSearchIterationCount, ...
    finalResultSelected, ...
    'VariableNames', {'linearization_pass','data_cost_before', ...
    'data_cost_after','selected_lambda','gcv_recommended_lambda', ...
    'selected_retained_singular_value_count', ...
    'gcv_recommended_retained_singular_value_count', ...
    'total_objective_before','total_objective_after', ...
    'total_objective_relative_change','standardized_step_relative_norm', ...
    'nonlinear_convergence_proposed','total_objective_decreased', ...
    'linear_prediction_relative_error','linear_prediction_passed', ...
    'trust_trial_count','trust_accepted_algorithmic_damping', ...
    'trust_acceptance_ratio', ...
    'inexact_newton_exact_safeguard_trial_count', ...
    'inexact_newton_accepted_algorithmic_damping', ...
    'inexact_newton_accepted_linearized_residual_ratio', ...
    'inexact_newton_target_residual_ratio', ...
    'inexact_newton_matrix_search_iteration_count', ...
    'final_result_selected'});
solve.linearPredictionCheck.history = solve.linearizationHistory;
solve.linearPredictionCheck.passed = ...
    linearPredictionPassed(finalIterationIndex);
solve.finalConvergenceAudits = confirmationAudits;
solve.finalConvergenceAudit = finalAudit;
solve.finalPerturbationAudit = finalAudit.perturbationAudit;
solve.finalCandidateReplayIdentity = finalAudit.candidateReplayIdentity;
% 正式导出的Jacobian必须对应最终采用参数点，而不是生成该候选的上一
% 线性化点。初始Jacobian字段仍保留原迭代信息用于追溯。
solve.rawDataJacobian = finalAudit.rawJacobian;
solve.dataJacobian = finalAudit.whitenedJacobian;
solve.whitenedDataJacobian = finalAudit.whitenedJacobian;
solve.parameterScaledJacobian = finalAudit.parameterScaledJacobian;
solve.priorWhitenedJacobian = finalAudit.priorWhitenedJacobian;
solve.scaledDataJacobian = finalAudit.priorWhitenedJacobian;
solve.dataSingularValues = finalAudit.singularValues;
solve.singularValues = finalAudit.singularValues;
solve.dataNumericalRank = finalAudit.numericalRank;
solve.numericalRank = finalAudit.numericalRank;
solve.dataConditionNumber = finalAudit.conditionNumber;
solve.conditionNumber = finalAudit.conditionNumber;
solve.differenceStep = finalAudit.usedDifferenceStep;
solve.replayAudit = local_m3_aggregate_replay_audit(passSolve, options);
solve.replayAudit = local_m3_add_confirmation_replay_audit( ...
    solve.replayAudit, confirmationAudits);
solve.wallSeconds = solve.replayAudit.wallSeconds;
solve.iterationCount = k;
solve.converged = converged;
solve.stopReason = stopReason;
solve.nonlinearConvergence.converged = converged;
solve.nonlinearConvergence.stopReason = stopReason;
solve.nonlinearConvergence.iterationCount = k;
solve.nonlinearConvergence.maximumIterations = maximumIterations;
solve.nonlinearConvergence.finalIterationIndex = finalIterationIndex;
solve.nonlinearConvergence.finalPointUsedFreshJacobian = true;
solve.nonlinearConvergence.finalFreshJacobianConfirmed = ...
    finalAudit.converged;
solve.nonlinearConvergence.finalProjectedGradient = ...
    finalAudit.projectedGradientInf;
solve.nonlinearConvergence.finalStationarityTolerance = ...
    finalAudit.stationarityTolerance;
solve.nonlinearConvergence.finalObjectiveIdentityRelativeError = ...
    finalAudit.objectiveIdentityRelativeError;
solve.nonlinearConvergence.finalObjectiveIdentityPassed = ...
    finalAudit.objectiveIdentityPassed;
solve.m3LinearizationPassCount = k + numel(confirmationAudits);
solve.m3IterationCount = k;
solve.lmDampingUsed = any(cellfun(@(x) x.lmDampingUsed, passSolve));
solve.regularizedTrustRegionUsed = any(cellfun( ...
    @(x) isfield(x, 'regularizedTrustRegionUsed') && ...
    x.regularizedTrustRegionUsed, passSolve));
solve.regularizingInexactNewtonUsed = any(cellfun( ...
    @(x) isfield(x, 'regularizingInexactNewtonUsed') && ...
    x.regularizingInexactNewtonUsed, passSolve));
solve.uncontrolledLmDampingUsed = any(cellfun( ...
    @(x) isfield(x, 'uncontrolledLmDampingUsed') && ...
    x.uncontrolledLmDampingUsed, passSolve));
end

function audit = local_m3_final_convergence_audit( ...
        finalSchedule, priorContract, sourceSolve, route, engine, cfg, data, ...
        parameters, weighting, options, label)
%LOCAL_M3_FINAL_CONVERGENCE_AUDIT 在最终候选点独立重算Jacobian。
% 该函数只验证，不求解新的参数步，因此不会改变最终调度函数，也不计入
% 参数更新次数。正式收敛同时要求精确回放、步长、目标变化和一阶最优性。
timerValue = tic;
contract = local_build_m3_node_contract( ...
    finalSchedule, parameters, finalSchedule.fuelBias.wfDesign, options);
local_assert_m3_contract_layout(contract, priorContract);
theta = contract.centerVector;
evaluator = @(candidateTheta, candidateId, purpose, nodeIndex, ...
        signValue, stepValue) local_m3_evaluate_node_vector( ...
        candidateTheta, contract, route, engine, cfg, data, weighting, ...
        options, candidateId, purpose, nodeIndex, signValue, stepValue);
baseline = evaluator(theta, sprintf('%s_baseline', label), ...
    'm3_final_convergence_baseline', 0, 0, 0);
if ~baseline.valid
    error('SHT:SteadyAdaptV2:M3FinalConvergenceReplayInvalid', ...
        '%s的最终参数点不能完成全部训练工况精确回放。', label);
end
if strcmp(route,'steady') && options.stageDSteadyLocalBranch
    derivativeOptions=options;
    derivativeOptions.linearizationSolutionSeed=baseline.replayDiagnostic.solutionSeed;
    evaluator=@(candidateTheta,candidateId,purpose,nodeIndex,signValue,stepValue) ...
        local_m3_evaluate_node_vector(candidateTheta,contract,route,engine,cfg,data, ...
        weighting,derivativeOptions,candidateId,purpose,nodeIndex,signValue,stepValue);
end
[rawJacobian, whitenedJacobian, perturbationAudit, ...
    jacobianRecords, usedStep] = local_m3_central_jacobian( ...
    contract, evaluator, baseline, options, label);
candidateRecords = repmat(local_empty_m3_candidate_record(), ...
    1 + numel(jacobianRecords), 1);
candidateRecords(1) = local_m3_candidate_record(baseline);
candidateRecords(2:end) = jacobianRecords;
candidateReplayIdentity = struct2table(candidateRecords);

[~, ~, priorCholLower, ~] = ...
    local_m3_prior_covariance(priorContract, options);
priorPrecisionFactor = priorCholLower \ eye(contract.parameterCount);
priorPrecision = priorPrecisionFactor.' * priorPrecisionFactor;
deltaPrior = theta - priorContract.centerVector;
lambda = options.stageDM3RegularizationStrength;
gradient = whitenedJacobian.' * baseline.whitenedResidual + ...
    lambda ^ 2 * priorPrecision * deltaPrior;
projectedGradient = local_m3_scaled_projected_gradient( ...
    gradient, theta, contract.lowerBound, contract.upperBound, ...
    contract.priorSigma);
z = priorCholLower \ deltaPrior;
dataCost = 0.5 * sum(baseline.whitenedResidual .^ 2);
totalObjective = dataCost + 0.5 * lambda ^ 2 * sum(z .^ 2);
objectiveIdentityRelativeError = abs(totalObjective - sourceSolve.costFinal) / ...
    max([abs(totalObjective), abs(sourceSolve.costFinal), 1e-12]);
objectiveIdentityTolerance = 1e-8;

stepRelativeNorm = ...
    sourceSolve.nonlinearConvergence.standardizedStepRelativeNorm;
objectiveRelativeChange = ...
    sourceSolve.nonlinearConvergence.totalObjectiveRelativeChange;
stepPassed = stepRelativeNorm <= options.stepRelativeTolerance;
objectiveChangePassed = ...
    objectiveRelativeChange <= options.costRelativeTolerance;
stationarityPassed = ...
    projectedGradient <= options.stageDM3FinalStationarityTolerance;
objectiveIdentityPassed = ...
    objectiveIdentityRelativeError <= objectiveIdentityTolerance;
converged = baseline.valid && stepPassed && objectiveChangePassed && ...
    stationarityPassed && objectiveIdentityPassed;

standardizedJacobian = whitenedJacobian * priorCholLower;
[~, sMatrix, ~] = svd(standardizedJacobian, 'econ');
singularValues = diag(sMatrix);
rankTolerance = 0;
if ~isempty(singularValues)
    rankTolerance = max(size(standardizedJacobian)) * ...
        eps(max(singularValues));
end
numericalRank = sum(singularValues > rankTolerance);
if numericalRank >= 1
    conditionNumber = singularValues(1) / singularValues(numericalRank);
else
    conditionNumber = Inf;
end

audit = struct();
audit.label = label;
audit.converged = converged;
audit.exactReplayValid = baseline.valid;
audit.stepRelativeNorm = stepRelativeNorm;
audit.stepRelativeTolerance = options.stepRelativeTolerance;
audit.stepCriterionPassed = stepPassed;
audit.totalObjectiveRelativeChange = objectiveRelativeChange;
audit.objectiveRelativeTolerance = options.costRelativeTolerance;
audit.objectiveChangeCriterionPassed = objectiveChangePassed;
audit.projectedGradientInf = projectedGradient;
audit.stationarityTolerance = options.stageDM3FinalStationarityTolerance;
audit.stationarityCriterionPassed = stationarityPassed;
audit.freshDataCost = dataCost;
audit.freshTotalObjective = totalObjective;
audit.sourceTotalObjective = sourceSolve.costFinal;
audit.objectiveIdentityRelativeError = objectiveIdentityRelativeError;
audit.objectiveIdentityTolerance = objectiveIdentityTolerance;
audit.objectiveIdentityPassed = objectiveIdentityPassed;
audit.theta = theta;
audit.nodeContract = contract;
audit.nodeContractHash = contract.nodeContractHash;
audit.rawJacobian = rawJacobian;
audit.whitenedJacobian = whitenedJacobian;
audit.parameterScaledJacobian = ...
    whitenedJacobian .* contract.priorSigma.';
audit.priorWhitenedJacobian = standardizedJacobian;
audit.singularValues = singularValues;
audit.numericalRank = numericalRank;
audit.conditionNumber = conditionNumber;
audit.usedDifferenceStep = usedStep;
audit.perturbationAudit = perturbationAudit;
audit.candidateReplayIdentity = candidateReplayIdentity;
audit.replayAudit = struct( ...
    'minimumRequiredJacobianCandidateCount', 1 + 2 * contract.parameterCount, ...
    'jacobianCandidateCount', height(candidateReplayIdentity), ...
    'actualCandidateCount', height(candidateReplayIdentity), ...
    'pointReplayCount', sum(candidateReplayIdentity.point_replay_count), ...
    'solveAttemptCount', sum(candidateReplayIdentity.solve_attempt_count), ...
    'invalidPointCount', sum(candidateReplayIdentity.invalid_point_count), ...
    'cacheHitCount', sum(candidateReplayIdentity.cache_hit_count), ...
    'wallSeconds', toc(timerValue), 'pauseCount', 0, 'resumeCount', 0);
end

function aggregate = local_m3_add_confirmation_replay_audit( ...
        aggregate, confirmationAudits)
field = {'minimumRequiredJacobianCandidateCount','jacobianCandidateCount', ...
    'actualCandidateCount','pointReplayCount','solveAttemptCount', ...
    'invalidPointCount','cacheHitCount','wallSeconds','pauseCount', ...
    'resumeCount'};
for i = 1:numel(confirmationAudits)
    one = confirmationAudits{i}.replayAudit;
    for j = 1:numel(field)
        aggregate.(field{j}) = aggregate.(field{j}) + one.(field{j});
    end
end
aggregate.linearizationPassCount = ...
    aggregate.linearizationPassCount + numel(confirmationAudits);
end

function audit = local_m3_aggregate_replay_audit(passSolve, options)
field = {'minimumRequiredJacobianCandidateCount','jacobianCandidateCount', ...
    'actualCandidateCount','pointReplayCount','solveAttemptCount', ...
    'invalidPointCount','cacheHitCount','wallSeconds','pauseCount', ...
    'resumeCount'};
audit = struct();
for i = 1:numel(field)
    value = 0;
    for k = 1:numel(passSolve)
        value = value + passSolve{k}.replayAudit.(field{i});
    end
    audit.(field{i}) = value;
end
audit.batchSize = options.stageDM3BatchSize;
audit.resumeSupported = false;
audit.linearizationPassCount = numel(passSolve);
end

function finalSolve = local_m3_combine_stage_d_pass_audit( ...
        finalSolve, pass1, pass2, options)
% D2是重锚后的最终数值快照，但正式调用量必须同时包含D1。
stageSolve = {pass1};
stageLabel = "D1";
if isfield(pass2, 'executed') && pass2.executed
    stageSolve{end + 1, 1} = pass2;
    stageLabel(end + 1, 1) = "D2";
end
finalSolve.finalStageReplayAudit = finalSolve.replayAudit;
finalSolve.finalStageCandidateReplayIdentity = ...
    finalSolve.candidateReplayIdentity;
finalSolve.finalStagePerturbationAudit = finalSolve.perturbationAudit;
finalSolve.finalStageStepStability = finalSolve.stepStability;
finalSolve.finalStageRegularizationCandidates = ...
    finalSolve.regularizationCandidates;
allCandidateReplay = table();
allPerturbation = table();
allStability = table();
allRegularization = table();
allLinearizationHistory = table();
allTrustHistory = table();
allInexactNewtonHistory = table();
allBounded = true;
allLinearPrediction = true;
anyTrustDamping = false;
anyRegularizedTrustRegion = false;
anyRegularizingInexactNewton = false;
anyUncontrolledDamping = false;
for i = 1:numel(stageSolve)
    one = stageSolve{i};
    replay = one.candidateReplayIdentity;
    replay.stage_pass = repmat(stageLabel(i), height(replay), 1);
    allCandidateReplay = [allCandidateReplay; replay]; %#ok<AGROW>
    perturbation = one.perturbationAudit;
    perturbation.stage_pass = repmat(stageLabel(i), height(perturbation), 1);
    allPerturbation = [allPerturbation; perturbation]; %#ok<AGROW>
    stability = one.stepStability;
    stability.stage_pass = repmat(stageLabel(i), height(stability), 1);
    allStability = [allStability; stability]; %#ok<AGROW>
    regularization = one.regularizationCandidates;
    regularization.stage_pass = ...
        repmat(stageLabel(i), height(regularization), 1);
    regularization.final_stage_selected = false(height(regularization), 1);
    if i == numel(stageSolve)
        regularization.final_stage_selected = regularization.final_selected;
    end
    allRegularization = [allRegularization; regularization]; %#ok<AGROW>
    history = one.linearizationHistory;
    history.stage_pass = repmat(stageLabel(i), height(history), 1);
    % D1、D2各自运行时都有一个局部最终行；组合后的正式结果只能保留
    % 最后阶段的一个全局最终标记，否则下游无法唯一定位实际采用点。
    history.final_result_selected(:) = false;
    if i == numel(stageSolve)
        history.final_result_selected(one.finalIterationIndex) = true;
    end
    allLinearizationHistory = [allLinearizationHistory; history]; %#ok<AGROW>
    if isfield(one, 'trustRegionHistory') && ~isempty(one.trustRegionHistory)
        trustHistory = one.trustRegionHistory;
        trustHistory.stage_pass = ...
            repmat(stageLabel(i), height(trustHistory), 1);
        allTrustHistory = [allTrustHistory; trustHistory]; %#ok<AGROW>
    end
    if isfield(one, 'inexactNewtonHistory') && ...
            ~isempty(one.inexactNewtonHistory)
        inexactHistory = one.inexactNewtonHistory;
        inexactHistory.stage_pass = ...
            repmat(stageLabel(i), height(inexactHistory), 1);
        allInexactNewtonHistory = ...
            [allInexactNewtonHistory; inexactHistory]; %#ok<AGROW>
    end
    anyTrustDamping = anyTrustDamping || one.lmDampingUsed;
    anyRegularizedTrustRegion = anyRegularizedTrustRegion || ...
        (isfield(one, 'regularizedTrustRegionUsed') && ...
        one.regularizedTrustRegionUsed);
    anyRegularizingInexactNewton = anyRegularizingInexactNewton || ...
        (isfield(one, 'regularizingInexactNewtonUsed') && ...
        one.regularizingInexactNewtonUsed);
    anyUncontrolledDamping = anyUncontrolledDamping || ...
        (isfield(one, 'uncontrolledLmDampingUsed') && ...
        one.uncontrolledLmDampingUsed);
    oneBoundedPassed = one.boundedSolution.passed;
    if isfield(one, 'allBoundedSolutionsPassed')
        oneBoundedPassed = one.allBoundedSolutionsPassed;
    end
    oneLinearPredictionPassed = one.linearPredictionCheck.passed;
    if isfield(one, 'allLinearPredictionChecksPassed')
        oneLinearPredictionPassed = one.allLinearPredictionChecksPassed;
    end
    allBounded = allBounded && oneBoundedPassed;
    allLinearPrediction = allLinearPrediction && oneLinearPredictionPassed;
end
finalSolve.candidateReplayIdentity = allCandidateReplay;
finalSolve.perturbationAudit = allPerturbation;
finalSolve.stepStability = allStability;
finalSolve.stepStabilityPassed = all(allStability.passed);
finalSolve.regularizationCandidates = allRegularization;
finalSolve.selectedRegularizationCandidateIndexAggregated = ...
    find(allRegularization.final_stage_selected, 1, 'first');
finalSolve.selectedRegularizationCandidateIndexSemantic = ...
    'within_final_linearization';
finalSolve.linearizationHistory = allLinearizationHistory;
finalSolve.history = allLinearizationHistory;
finalSolve.linearPredictionCheck.history = allLinearizationHistory;
finalSolve.trustRegionHistory = allTrustHistory;
finalSolve.inexactNewtonHistory = allInexactNewtonHistory;
finalSolve.replayAudit = local_m3_aggregate_replay_audit( ...
    stageSolve, options);
finalSolve.replayAudit.stagePassCount = numel(stageSolve);
finalSolve.replayAudit.linearizationPassCount = sum(cellfun( ...
    @(x) x.m3LinearizationPassCount, stageSolve));
finalSolve.allBoundedSolutionsPassed = allBounded;
finalSolve.allLinearPredictionChecksPassed = allLinearPrediction;
finalSolve.lmDampingUsed = anyTrustDamping;
finalSolve.regularizedTrustRegionUsed = anyRegularizedTrustRegion;
finalSolve.regularizingInexactNewtonUsed = anyRegularizingInexactNewton;
finalSolve.uncontrolledLmDampingUsed = anyUncontrolledDamping;
finalSolve.m3LinearizationPassCountTotal = ...
    finalSolve.replayAudit.linearizationPassCount;
finalSolve.iterationCount = sum(cellfun( ...
    @(x) x.m3IterationCount, stageSolve));
previousHistoryCount = sum(cellfun( ...
    @(x) height(x.linearizationHistory), stageSolve(1:end-1)));
finalSolve.finalIterationIndex = previousHistoryCount + ...
    stageSolve{end}.finalIterationIndex;
finalSolve.finalResultIsLastIteration = ...
    finalSolve.finalIterationIndex == height(allLinearizationHistory);
finalSolve.nonlinearConvergence.finalIterationIndex = ...
    finalSolve.finalIterationIndex;
if nnz(allLinearizationHistory.final_result_selected) ~= 1
    error('SHT:SteadyAdaptV2:M3CombinedFinalSelectionInvalid', ...
        '组合后的D阶段历史必须且只能标记一个最终采用迭代。');
end
finalSolve.wallSeconds = finalSolve.replayAudit.wallSeconds;
end

function local_assert_m3_contract_layout(currentContract, priorContract)
current = currentContract.parameterTable;
prior = priorContract.parameterTable;
textField = {'node_id','base_name','unit','group_kind','axis_name'};
numericField = {'index','c_index','group_index','schedule_entry_index', ...
    'dll_node_index','node_index','coordinate','normalized_coordinate', ...
    'lower_bound','upper_bound','prior_sigma','difference_step'};
same = height(current) == height(prior);
for i = 1:numel(textField)
    same = same && isequal(current.(textField{i}), prior.(textField{i}));
end
for i = 1:numel(numericField)
    same = same && isequaln(current.(numericField{i}), prior.(numericField{i}));
end
same = same && isequaln(currentContract.fixedAnchorTable, ...
    priorContract.fixedAnchorTable);
if ~same
    error('SHT:SteadyAdaptV2:M3LinearizationContractDrift', ...
        ['同一次Stage-D完整求解的重新线性化改变了节点顺序、坐标、边界、' ...
         '先验或固定锚点；必须停止并重建独立M3合同。']);
end
end

function [solve, refinedSchedule, trustState] = ...
        local_run_stage_d_m3_linearization( ...
        baseSchedule, priorContract, route, engine, cfg, data, ...
        parameters, weighting, options, label, trustState)
%LOCAL_RUN_STAGE_D_M3_LINEARIZATION 一次逐节点M3与完整有界正则候选回放。
passTimer = tic;
contract = local_build_m3_node_contract(baseSchedule, parameters, ...
    baseSchedule.fuelBias.wfDesign, options);
% 参数字典由options稳定生成；下式对节点合同的全部非中心字段作严格核对。
local_assert_m3_contract_layout(contract, priorContract);
d = contract.parameterCount;
priorCenter = priorContract.centerVector;
linearizationPoint = contract.centerVector;
evaluator = @(theta, candidateId, purpose, nodeIndex, signValue, stepValue) ...
    local_m3_evaluate_node_vector(theta, contract, route, engine, cfg, ...
    data, weighting, options, candidateId, purpose, nodeIndex, ...
    signValue, stepValue);

baselineEvaluation = evaluator(linearizationPoint, ...
    sprintf('%s_baseline', label), 'm3_linearization_baseline', 0, 0, 0);
if ~baselineEvaluation.valid
    error('SHT:SteadyAdaptV2:M3BaselineReplayInvalid', ...
        '%s的M3线性化点不能完成全部训练工况回放。', label);
end
baselineCandidateRecord = local_m3_candidate_record(baselineEvaluation);
if strcmp(route,'steady') && options.stageDSteadyLocalBranch
    derivativeOptions=options;
    derivativeOptions.linearizationSolutionSeed=baselineEvaluation.replayDiagnostic.solutionSeed;
    evaluator=@(theta,candidateId,purpose,nodeIndex,signValue,stepValue) ...
        local_m3_evaluate_node_vector(theta,contract,route,engine,cfg,data, ...
        weighting,derivativeOptions,candidateId,purpose,nodeIndex,signValue,stepValue);
end
[rawJacobian, whitenedJacobian, perturbationAudit, ...
    jacobianCandidateRecords, usedStep] = local_m3_central_jacobian( ...
    contract, evaluator, baselineEvaluation, options, label);
[stepStability, stabilityCandidateRecords] = local_m3_step_stability( ...
    contract, evaluator, whitenedJacobian, usedStep, options, label);
candidateRecords = repmat(local_empty_m3_candidate_record(), ...
    1 + numel(jacobianCandidateRecords) + ...
    numel(stabilityCandidateRecords), 1);
candidateRecords(1) = baselineCandidateRecord;
candidateRecords(2:(1 + numel(jacobianCandidateRecords))) = ...
    jacobianCandidateRecords;
candidateRecords((2 + numel(jacobianCandidateRecords)):end) = ...
    stabilityCandidateRecords;

[priorCorrelation, priorCovariance, priorCholLower, priorGroupTable] = ...
    local_m3_prior_covariance(priorContract, options);
priorPrecisionFactor = priorCholLower \ eye(d);
priorPrecision = priorPrecisionFactor.' * priorPrecisionFactor;
standardizedJacobian = whitenedJacobian * priorCholLower;
[~, sMatrix, ~] = svd(standardizedJacobian, 'econ');
singularValues = diag(sMatrix);
if strcmpi(options.stageDRegularizationMethod, 'tsvd')
    [solve, refinedSchedule] = local_run_stage_d_m3_tsvd_linearization( ...
        contract, priorCenter, linearizationPoint, evaluator, ...
        baselineEvaluation, rawJacobian, whitenedJacobian, ...
        perturbationAudit, usedStep, stepStability, priorCorrelation, ...
        priorCovariance, priorCholLower, priorGroupTable, candidateRecords, ...
        standardizedJacobian, options, label, passTimer);
    return;
end
if ismember(lower(string(options.stageDM3GlobalizationMethod)), ...
        ["regularized_trust_region", "regularizing_lm_inexact_newton"])
    [solve, refinedSchedule, trustState] = ...
        local_run_stage_d_m3_controlled_lm_linearization( ...
        contract, priorCenter, linearizationPoint, evaluator, ...
        baselineEvaluation, rawJacobian, whitenedJacobian, ...
        perturbationAudit, usedStep, stepStability, priorCorrelation, ...
        priorCovariance, priorCholLower, priorGroupTable, candidateRecords, ...
        standardizedJacobian, options, label, passTimer, trustState);
    return;
end
lambda = options.stageDM3RegularizationCandidates(:);
nLambda = numel(lambda);
effectiveDegreesOfFreedom = nan(nLambda, 1);
linearizedDataCost = inf(nLambda, 1);
exactDataCost = inf(nLambda, 1);
linearizedGcv = inf(nLambda, 1);
exactGcv = inf(nLambda, 1);
priorStandardizedUpdateNorm = inf(nLambda, 1);
maximumAbsoluteUpdate = inf(nLambda, 1);
minimumRelativeBoundMargin = -inf(nLambda, 1);
kktResidualInf = inf(nLambda, 1);
relativeKktResidual = inf(nLambda, 1);
activeBoundCount = nan(nLambda, 1);
boxIterationCount = nan(nLambda, 1);
withinBounds = false(nLambda, 1);
replayPerformed = false(nLambda, 1);
replayValid = false(nLambda, 1);
trainingCostNonincrease = false(nLambda, 1);
eligible = false(nLambda, 1);
selected = false(nLambda, 1);
gcvRecommended = false(nLambda, 1);
boxConstrainedEquivalent = true(nLambda, 1);
candidateId = strings(nLambda, 1);
candidateTheta = cell(nLambda, 1);
candidateDeltaPrior = cell(nLambda, 1);
candidateAppliedUpdate = cell(nLambda, 1);
candidateZ = cell(nLambda, 1);
candidateEvaluation = cell(nLambda, 1);
candidateBoxAudit = cell(nLambda, 1);
baselineDataCost = 0.5 * sum(baselineEvaluation.whitenedResidual .^ 2);
m = numel(baselineEvaluation.whitenedResidual);
linearizedIntercept = baselineEvaluation.whitenedResidual + ...
    whitenedJacobian * (priorCenter - linearizationPoint);
lowerDelta = contract.lowerBound - priorCenter;
upperDelta = contract.upperBound - priorCenter;
for i = 1:nLambda
    lambdaValue = lambda(i);
    hessian = whitenedJacobian.' * whitenedJacobian + ...
        lambdaValue ^ 2 * priorPrecision;
    linearTerm = whitenedJacobian.' * linearizedIntercept;
    [deltaPrior, boxAudit] = local_m3_box_quadratic_solve( ...
        hessian, linearTerm, lowerDelta, upperDelta, ...
        options.stageDM3BoxKktRelativeTolerance, ...
        options.stageDM3BoxMaximumIterations);
    theta = priorCenter + deltaPrior;
    appliedUpdate = theta - linearizationPoint;
    z = priorCholLower \ deltaPrior;
    free = ~(boxAudit.activeLower | boxAudit.activeUpper);
    if any(free)
        influence = whitenedJacobian(:, free) * ...
            (hessian(free, free) \ whitenedJacobian(:, free).');
        effectiveDof = trace(influence);
    else
        effectiveDof = 0;
    end
    candidateTheta{i} = theta;
    candidateDeltaPrior{i} = deltaPrior;
    candidateAppliedUpdate{i} = appliedUpdate;
    candidateZ{i} = z;
    candidateBoxAudit{i} = boxAudit;
    effectiveDegreesOfFreedom(i) = effectiveDof;
    priorStandardizedUpdateNorm(i) = norm(z);
    maximumAbsoluteUpdate(i) = max(abs(appliedUpdate));
    relativeLower = (theta - contract.lowerBound) ./ ...
        max(contract.upperBound - contract.lowerBound, eps);
    relativeUpper = (contract.upperBound - theta) ./ ...
        max(contract.upperBound - contract.lowerBound, eps);
    minimumRelativeBoundMargin(i) = min([relativeLower; relativeUpper]);
    withinBounds(i) = all(theta >= contract.lowerBound & ...
        theta <= contract.upperBound);
    kktResidualInf(i) = boxAudit.kktResidualInf;
    relativeKktResidual(i) = boxAudit.relativeKktResidual;
    activeBoundCount(i) = boxAudit.activeBoundCount;
    boxIterationCount(i) = boxAudit.iterationCount;
    linearResidual = linearizedIntercept + whitenedJacobian * deltaPrior;
    linearizedDataCost(i) = 0.5 * sum(linearResidual .^ 2);
    denominator = max((m - effectiveDof) ^ 2, eps);
    linearizedGcv(i) = m * sum(linearResidual .^ 2) / denominator;
    candidateId(i) = sprintf('%s_tikhonov_%02d', label, i);
    oneEvaluation = evaluator(theta, candidateId(i), ...
        'm3_full_box_regularized_candidate', 0, 0, NaN);
    candidateEvaluation{i} = oneEvaluation;
    candidateRecords(end + 1, 1) = ...
        local_m3_candidate_record(oneEvaluation); %#ok<AGROW>
    replayPerformed(i) = true;
    replayValid(i) = oneEvaluation.valid;
    if ~oneEvaluation.valid
        continue;
    end
    exactDataCost(i) = 0.5 * sum(oneEvaluation.whitenedResidual .^ 2);
    exactGcv(i) = m * sum(oneEvaluation.whitenedResidual .^ 2) / denominator;
    trainingCostNonincrease(i) = exactDataCost(i) <= ...
        baselineDataCost * (1 + 1e-8);
    % 资格只表示该线性子问题及其DLL精确候选在数值和物理上可用。
    % 数据代价是否下降以及线性预测是否准确均为迭代诊断，不能据此
    % 否定固定lambda或提前终止非线性重新线性化过程。
    eligible(i) = boxAudit.passed && withinBounds(i) && replayValid(i);
end
eligibleIndex = find(eligible);
if isempty(eligibleIndex)
    failureTable=table(lambda,relativeKktResidual,withinBounds,replayValid, ...
        cellfun(@(x)x.passed,candidateBoxAudit), ...
        cellfun(@(x)x.invalidPointCount,candidateEvaluation), ...
        'VariableNames',{'lambda','relative_kkt_residual','within_bounds', ...
        'replay_valid','box_passed','invalid_point_count'});
    disp(failureTable);
    for failureIndex=1:nLambda
        failedPrediction=candidateEvaluation{failureIndex}.prediction;
        if isempty(failedPrediction),continue;end
        fprintf('%s lambda=%.6g无效回放明细：\n',label,lambda(failureIndex));
        disp(failedPrediction(~failedPrediction.valid,{'point_id','Np','Ng', ...
            'np_branch_center_rpm','np_branch_lower_rpm','np_branch_upper_rpm', ...
            'max_model_residual','np_branch_passed','error_message'}));
    end
    if options.modelMode==0 && options.saveStageCDevelopmentCheckpoint
        failurePaths=local_paths(options);
        failure=struct('label',label,'table',failureTable,'contract',contract, ...
            'baseline',baselineEvaluation,'candidates',{candidateEvaluation}, ...
            'boxAudit',{candidateBoxAudit},'options',options, ...
            'stepStability',stepStability,'whitenedJacobian',whitenedJacobian);
        save(fullfile(failurePaths.middleDataDir,'tc24_np_branch_D_failure_debug.mat'), ...
            'failure','-v7.3');
    end
    error('SHT:SteadyAdaptV2:M3NoEligibleRegularizedSolution', ...
        ['%s没有通过KKT、物理边界和DLL精确回放的有界完整正则化解；' ...
         '这是数值候选无效，不是线性预测或数据代价诊断门。'], label);
end
[~, bestLocal] = min(exactGcv(eligibleIndex));
gcvRecommendedIndex = eligibleIndex(bestLocal);
gcvRecommended(gcvRecommendedIndex) = true;
configuredLambda = options.stageDM3RegularizationStrength;
lambdaTolerance = 64 * eps(max([1; abs(lambda); abs(configuredLambda)]));
selectedIndex = find(abs(lambda - configuredLambda) <= lambdaTolerance, ...
    1, 'first');
if isempty(selectedIndex)
    error('SHT:SteadyAdaptV2:M3ConfiguredLambdaMissing', ...
        '用户配置正则强度%.8g不在当前候选表中。', configuredLambda);
end
if ~eligible(selectedIndex)
    error('SHT:SteadyAdaptV2:M3ConfiguredLambdaInvalid', ...
        ['用户配置正则强度%.8g的本轮候选未通过KKT、物理边界或DLL' ...
         '精确回放，不能生成下一非线性迭代点；GCV建议值%.8g不会' ...
         '替代用户配置。'], configuredLambda, lambda(gcvRecommendedIndex));
end
selected(selectedIndex) = true;
selectedTheta = candidateTheta{selectedIndex};
deltaPrior = candidateDeltaPrior{selectedIndex};
fullUpdate = candidateAppliedUpdate{selectedIndex};
selectedZ = candidateZ{selectedIndex};
selectedEvaluation = candidateEvaluation{selectedIndex};
selectedLambda = lambda(selectedIndex);
boundedSolution = candidateBoxAudit{selectedIndex};
if options.verbose
    fprintf(['%s正则强度：用户采用=%.8g，GCV推荐=%.8g，' ...
        '采用值精确GCV=%.8g。\n'], label, selectedLambda, ...
        lambda(gcvRecommendedIndex), exactGcv(selectedIndex));
end
boundedSolution.primalFeasible = withinBounds(selectedIndex);
boundedSolution.strictlyInterior = ...
    all(selectedTheta > contract.lowerBound & ...
    selectedTheta < contract.upperBound);
boundedSolution.kktStationarityResidualInf = boundedSolution.kktResidualInf;
boundedSolution.relativeKktStationarityResidual = ...
    boundedSolution.relativeKktResidual;
refinedSchedule = selectedEvaluation.schedule;

regularizationCandidates = table(lambda, effectiveDegreesOfFreedom, ...
    linearizedDataCost, exactDataCost, linearizedGcv, exactGcv, ...
    priorStandardizedUpdateNorm, maximumAbsoluteUpdate, ...
    minimumRelativeBoundMargin, kktResidualInf, relativeKktResidual, ...
    activeBoundCount, boxIterationCount, withinBounds, replayPerformed, ...
    replayValid, trainingCostNonincrease, eligible, selected, ...
    gcvRecommended, candidateId, ...
    boxConstrainedEquivalent, ...
    'VariableNames', {'lambda','effective_degrees_of_freedom', ...
    'linearized_data_cost','exact_data_cost','linearized_gcv','exact_gcv', ...
    'prior_standardized_solution_norm','maximum_absolute_applied_update', ...
    'minimum_relative_bound_margin','kkt_residual_inf', ...
    'relative_kkt_residual','active_bound_count','box_iteration_count', ...
    'within_bounds','replay_performed','replay_valid', ...
    'training_cost_nonincrease','eligible','selected','gcv_recommended', ...
    'candidate_id', ...
    'box_constrained_equivalent'});

currentDeltaPrior = linearizationPoint - priorCenter;
currentZ = priorCholLower \ currentDeltaPrior;
augmentedResidual = [selectedEvaluation.whitenedResidual; ...
    selectedLambda * selectedZ];
initialAugmentedResidual = [baselineEvaluation.whitenedResidual; ...
    selectedLambda * currentZ];
initialTotalCost = 0.5 * sum(initialAugmentedResidual .^ 2);
finalTotalCost = 0.5 * sum(augmentedResidual .^ 2);
standardizedStepRelativeNorm = norm(selectedZ - currentZ) / ...
    max([1, norm(currentZ), norm(selectedZ)]);
totalCostRelativeChange = abs(finalTotalCost - initialTotalCost) / ...
    max([abs(initialTotalCost), abs(finalTotalCost), 1e-12]);
nonlinearConvergenceProposed = ...
    standardizedStepRelativeNorm <= options.stepRelativeTolerance && ...
    totalCostRelativeChange <= options.costRelativeTolerance;
augmentedJacobian = [whitenedJacobian; ...
    selectedLambda * priorPrecisionFactor];
scaledAugmentedJacobian = [standardizedJacobian; ...
    selectedLambda * eye(d)];
rankTolerance = 0;
if ~isempty(singularValues)
    rankTolerance = max(size(standardizedJacobian)) * ...
        eps(max(singularValues));
end
numericalRank = sum(singularValues > rankTolerance);
if numericalRank >= 1
    conditionNumber = singularValues(1) / singularValues(numericalRank);
else
    conditionNumber = Inf;
end
relativeLower = (selectedTheta - contract.lowerBound) ./ ...
    max(contract.upperBound - contract.lowerBound, eps);
relativeUpper = (contract.upperBound - selectedTheta) ./ ...
    max(contract.upperBound - contract.lowerBound, eps);
finalMinimumMargin = min([relativeLower; relativeUpper]);
linearPrediction = linearizedIntercept + whitenedJacobian * deltaPrior;
linearPredictionRelativeError = norm( ...
    selectedEvaluation.whitenedResidual - linearPrediction) / ...
    max([norm(selectedEvaluation.whitenedResidual), ...
    norm(linearPrediction), 1e-12]);
linearPredictionPassed = linearPredictionRelativeError <= ...
    options.stageDM3LinearPredictionRelativeTolerance;

candidateReplayIdentity = struct2table(candidateRecords);
history = table(1, baselineDataCost, exactDataCost(selectedIndex), ...
    selectedLambda, true, linearPredictionRelativeError, ...
    linearPredictionPassed, "full_box_regularized_solution_applied", ...
    'VariableNames', {'iteration','data_cost_before','data_cost_after', ...
    'selected_lambda','full_update_applied', ...
    'linear_prediction_relative_error','linear_prediction_passed', ...
    'stop_reason'});
solve = struct();
solve.label = label;
solve.executed = true;
solve.parameterization = 'actual_execution_nodes';
solve.jacobianMethod = 'node_central_full';
solve.x = selectedTheta;
solve.initialX = linearizationPoint;
solve.priorCenterX = priorCenter;
solve.initialOffset = zeros(d, 1);
solve.offset = fullUpdate;
solve.fullRegularizedUpdate = fullUpdate;
solve.priorCenteredFullSolution = deltaPrior;
solve.fullUpdateAppliedWithoutGlobalScaling = true;
solve.globalAlphaUsed = false;
solve.lmDampingUsed = false;
% 一次线性化本身不等于整个非线性阶段收敛。外层只有在本轮使用新
% Jacobian得到的完整候选同时满足参数步长和总目标变化条件时才收敛。
solve.converged = false;
solve.stopReason = 'nonlinear_iteration_completed';
solve.iterationCount = 1;
solve.costInitial = initialTotalCost;
solve.costFinal = finalTotalCost;
solve.dataCostInitial = baselineDataCost;
solve.dataCostFinal = exactDataCost(selectedIndex);
solve.initialResidual = [baselineEvaluation.whitenedResidual; ...
    selectedLambda * currentZ];
solve.initialDataResidual = baselineEvaluation.whitenedResidual;
solve.residual = augmentedResidual;
solve.meta = struct('valid', selectedEvaluation.valid, ...
    'prediction', selectedEvaluation.prediction, ...
    'dataResidual', selectedEvaluation.whitenedResidual, ...
    'rawDataResidual', selectedEvaluation.rawResidual, ...
    'regularization', selectedLambda * selectedZ, ...
    'regularizationMethod', 'box_constrained_tikhonov', ...
    'schedule', refinedSchedule);
solve.initialJacobian = augmentedJacobian;
solve.initialDataJacobian = whitenedJacobian;
solve.jacobian = augmentedJacobian;
solve.rawDataJacobian = rawJacobian;
solve.dataJacobian = whitenedJacobian;
solve.whitenedDataJacobian = whitenedJacobian;
solve.parameterScaledJacobian = ...
    whitenedJacobian .* priorContract.priorSigma.';
solve.priorWhitenedJacobian = standardizedJacobian;
solve.scaledDataJacobian = standardizedJacobian;
solve.scaledJacobian = scaledAugmentedJacobian;
solve.singularValues = singularValues;
solve.dataSingularValues = singularValues;
solve.numericalRank = numericalRank;
solve.dataNumericalRank = numericalRank;
solve.conditionNumber = conditionNumber;
solve.dataConditionNumber = conditionNumber;
solve.regularizationMethod = 'box_constrained_tikhonov';
solve.tsvdStepMode = 'not_applicable';
solve.parameterScale = priorContract.priorSigma;
solve.parameterCount = d;
solve.activeNodeCount = d;
solve.dataResidualCount = m;
solve.lowerBound = contract.lowerBound;
solve.upperBound = contract.upperBound;
solve.differenceStep = usedStep;
solve.differenceStepScale = options.stageDDifferenceStepScale;
solve.informationMatrixDimension = [d, d];
solve.requestedRetainedSingularValueCount = d;
solve.retainedSingularValueCount = numericalRank;
solve.truncatedSingularValueCount = max(0, d - numericalRank);
solve.retainedConditionNumber = conditionNumber;
solve.history = history;
solve.nodeContract = contract;
solve.nodeContractHash = contract.nodeContractHash;
solve.fixedAnchorTable = contract.fixedAnchorTable;
solve.perturbationAudit = perturbationAudit;
solve.stepStability = stepStability;
solve.stepStabilityPassed = all(stepStability.passed);
solve.priorCorrelation = priorCorrelation;
solve.priorCovariance = priorCovariance;
solve.priorCholLower = priorCholLower;
solve.priorGroupTable = priorGroupTable;
solve.regularizationCandidates = regularizationCandidates;
solve.regularizationSelectionCriterion = ...
    'user_configured_strength_with_exact_training_gcv_advisory';
solve.regularizationControlMode = ...
    'user_configured_with_gcv_advisory';
solve.configuredRegularizationStrength = configuredLambda;
solve.selectedRegularizationStrength = selectedLambda;
solve.selectedRegularizationCandidateIndex = selectedIndex;
solve.gcvRecommendedRegularizationStrength = lambda(gcvRecommendedIndex);
solve.gcvRecommendedRegularizationCandidateIndex = gcvRecommendedIndex;
solve.boundedSolution = boundedSolution;
solve.linearPredictionCheck = struct( ...
    'predictedWhitenedResidual', linearPrediction, ...
    'exactWhitenedResidual', selectedEvaluation.whitenedResidual, ...
    'relativeResidualError', linearPredictionRelativeError, ...
    'relativeTolerance', options.stageDM3LinearPredictionRelativeTolerance, ...
    'passed', linearPredictionPassed, ...
    'usesIndependentFullDllCandidate', true, ...
    'diagnosticOnly', true);
solve.nonlinearConvergence = struct( ...
    'standardizedStepRelativeNorm', standardizedStepRelativeNorm, ...
    'stepRelativeTolerance', options.stepRelativeTolerance, ...
    'totalObjectiveRelativeChange', totalCostRelativeChange, ...
    'objectiveRelativeTolerance', options.costRelativeTolerance, ...
    'totalObjectiveDecreased', finalTotalCost <= initialTotalCost, ...
    'proposedConverged', nonlinearConvergenceProposed, ...
    'evaluatedAfterFreshJacobian', true);
solve.candidateReplayIdentity = candidateReplayIdentity;
solve.replayAudit = struct( ...
    'minimumRequiredJacobianCandidateCount', 1 + 2 * d, ...
    'jacobianCandidateCount', 1 + sum( ...
        perturbationAudit.candidate_evaluation_count), ...
    'actualCandidateCount', height(candidateReplayIdentity), ...
    'pointReplayCount', sum(candidateReplayIdentity.point_replay_count), ...
    'solveAttemptCount', sum(candidateReplayIdentity.solve_attempt_count), ...
    'invalidPointCount', sum(candidateReplayIdentity.invalid_point_count), ...
    'cacheHitCount', sum(candidateReplayIdentity.cache_hit_count), ...
    'wallSeconds', sum(candidateReplayIdentity.wall_seconds), ...
    'batchSize', options.stageDM3BatchSize, ...
    'pauseCount', 0, 'resumeCount', 0, 'resumeSupported', false);
solve.minimumRelativeBoundMargin = finalMinimumMargin;
solve.atBound = finalMinimumMargin <= 1e-8;
solve.wallSeconds = toc(passTimer);
end

function [solve, refinedSchedule, trustState] = ...
        local_run_stage_d_m3_controlled_lm_linearization( ...
        contract, priorCenter, linearizationPoint, evaluator, ...
        baselineEvaluation, rawJacobian, whitenedJacobian, ...
        perturbationAudit, usedStep, stepStability, priorCorrelation, ...
        priorCovariance, priorCholLower, priorGroupTable, candidateRecords, ...
        standardizedJacobian, options, label, passTimer, trustState)
%LOCAL_RUN_STAGE_D_M3_CONTROLLED_LM_LINEARIZATION 受控正则化LM步。
%
% 固定物理目标为
%   Phi(theta)=0.5*||r(theta)||^2
%              +0.5*lambda^2*||L\(theta-theta_prior)||^2。
% 算法阻尼mu只加在当前步theta-theta_k上。信赖域路线由精确DLL
% 实际降低量与局部模型预测降低量之比调节mu；非精确Newton路线
% 由增广线性化残差收缩比选择mu，精确DLL仅作总目标安全校核。
% 因此mu不是新的先验强度，也不是对已求得更新量乘经验alpha。

d = contract.parameterCount;
m = numel(baselineEvaluation.whitenedResidual);
lambdaPhysical = options.stageDM3RegularizationStrength;
priorPrecisionFactor = priorCholLower \ eye(d);
priorPrecision = priorPrecisionFactor.' * priorPrecisionFactor;
linearizedIntercept = baselineEvaluation.whitenedResidual + ...
    whitenedJacobian * (priorCenter - linearizationPoint);
lowerDelta = contract.lowerBound - priorCenter;
upperDelta = contract.upperBound - priorCenter;
currentDelta = linearizationPoint - priorCenter;
currentZ = priorCholLower \ currentDelta;
baselineDataCost = 0.5 * sum(baselineEvaluation.whitenedResidual .^ 2);
currentTotalCost = baselineDataCost + ...
    0.5 * lambdaPhysical ^ 2 * sum(currentZ .^ 2);

% GCV仍作为诊断建议，但不为每个建议lambda执行额外DLL回放。
% 精确回放只服务于用户指定的物理lambda和信赖域候选。
lambda = options.stageDM3RegularizationCandidates(:);
nLambda = numel(lambda);
effectiveDegreesOfFreedom = nan(nLambda, 1);
linearizedDataCost = inf(nLambda, 1);
exactDataCost = nan(nLambda, 1);
linearizedGcv = inf(nLambda, 1);
exactGcv = nan(nLambda, 1);
priorStandardizedUpdateNorm = nan(nLambda, 1);
maximumAbsoluteUpdate = nan(nLambda, 1);
minimumRelativeBoundMargin = nan(nLambda, 1);
kktResidualInf = nan(nLambda, 1);
relativeKktResidual = nan(nLambda, 1);
activeBoundCount = nan(nLambda, 1);
boxIterationCount = nan(nLambda, 1);
withinBounds = false(nLambda, 1);
replayPerformed = false(nLambda, 1);
replayValid = false(nLambda, 1);
trainingCostNonincrease = false(nLambda, 1);
eligible = false(nLambda, 1);
selected = false(nLambda, 1);
gcvRecommended = false(nLambda, 1);
candidateId = strings(nLambda, 1);
boxConstrainedEquivalent = true(nLambda, 1);
advisoryBox = cell(nLambda, 1);
for iLambda = 1:nLambda
    oneHessian = whitenedJacobian.' * whitenedJacobian + ...
        lambda(iLambda) ^ 2 * priorPrecision;
    oneLinearTerm = whitenedJacobian.' * linearizedIntercept;
    [oneDelta, oneBox] = local_m3_box_quadratic_solve( ...
        oneHessian, oneLinearTerm, lowerDelta, upperDelta, ...
        options.stageDM3BoxKktRelativeTolerance, ...
        options.stageDM3BoxMaximumIterations);
    advisoryBox{iLambda} = oneBox;
    oneTheta = priorCenter + oneDelta;
    oneLinearResidual = linearizedIntercept + whitenedJacobian * oneDelta;
    oneFree = ~(oneBox.activeLower | oneBox.activeUpper);
    if any(oneFree)
        oneInfluence = whitenedJacobian(:, oneFree) * ...
            (oneHessian(oneFree, oneFree) \ ...
            whitenedJacobian(:, oneFree).');
        effectiveDegreesOfFreedom(iLambda) = trace(oneInfluence);
    else
        effectiveDegreesOfFreedom(iLambda) = 0;
    end
    linearizedDataCost(iLambda) = 0.5 * sum(oneLinearResidual .^ 2);
    oneDenominator = max((m - effectiveDegreesOfFreedom(iLambda)) ^ 2, eps);
    linearizedGcv(iLambda) = ...
        m * sum(oneLinearResidual .^ 2) / oneDenominator;
    oneZ = priorCholLower \ oneDelta;
    priorStandardizedUpdateNorm(iLambda) = norm(oneZ);
    maximumAbsoluteUpdate(iLambda) = ...
        max(abs(oneTheta - linearizationPoint));
    relativeLower = (oneTheta - contract.lowerBound) ./ ...
        max(contract.upperBound - contract.lowerBound, eps);
    relativeUpper = (contract.upperBound - oneTheta) ./ ...
        max(contract.upperBound - contract.lowerBound, eps);
    minimumRelativeBoundMargin(iLambda) = min([relativeLower; relativeUpper]);
    kktResidualInf(iLambda) = oneBox.kktResidualInf;
    relativeKktResidual(iLambda) = oneBox.relativeKktResidual;
    activeBoundCount(iLambda) = oneBox.activeBoundCount;
    boxIterationCount(iLambda) = oneBox.iterationCount;
    withinBounds(iLambda) = all(oneTheta >= contract.lowerBound & ...
        oneTheta <= contract.upperBound);
    eligible(iLambda) = oneBox.passed && withinBounds(iLambda);
    candidateId(iLambda) = sprintf('%s_lambda_%s_linear_gcv', ...
        label, local_m3_number_tag(lambda(iLambda)));
end
eligibleIndex = find(eligible);
if isempty(eligibleIndex)
    error('SHT:SteadyAdaptV2:M3TrustNoGcvCandidate', ...
        '%s的全部GCV诊断候选均未通过有界KKT求解。', label);
end
[~, bestLocal] = min(linearizedGcv(eligibleIndex));
gcvRecommendedIndex = eligibleIndex(bestLocal);
gcvRecommended(gcvRecommendedIndex) = true;
lambdaTolerance = 64 * eps(max([1; abs(lambda); abs(lambdaPhysical)]));
selectedIndex = find(abs(lambda - lambdaPhysical) <= lambdaTolerance, 1, 'first');
if isempty(selectedIndex) || ~eligible(selectedIndex)
    error('SHT:SteadyAdaptV2:M3TrustConfiguredLambdaInvalid', ...
        '用户指定的物理正则强度%.8g无有效有界局部子问题。', ...
        lambdaPhysical);
end
selected(selectedIndex) = true;

globalizationMethod = lower(string(options.stageDM3GlobalizationMethod));
useTrustRegion = globalizationMethod == "regularized_trust_region";
useInexactNewton = globalizationMethod == "regularizing_lm_inexact_newton";
if ~(useTrustRegion || useInexactNewton)
    error('SHT:SteadyAdaptV2:M3ControlledLmBadMethod', ...
        '受控LM求解器收到不支持的全局化方式：%s。', globalizationMethod);
end
if useTrustRegion
    stationarityTolerance = options.stageDM3TrustStationarityTolerance;
else
    stationarityTolerance = options.stageDM3InexactNewtonStationarityTolerance;
end
if ~isstruct(trustState) || ~isfield(trustState, 'damping') || ...
        ~isscalar(trustState.damping) || ~isfinite(trustState.damping) || ...
        trustState.damping < 0
    error('SHT:SteadyAdaptV2:M3ControlledLmBadState', ...
        '受控LM内部状态必须含有限非负damping。');
end
if useTrustRegion
    maximumTrials = options.stageDM3TrustMaximumTrials;
else
    maximumTrials = options.stageDM3InexactNewtonMaximumExactSafeguardTrials;
end
trialIndex = (1:maximumTrials).';
algorithmicDamping = nan(maximumTrials, 1);
predictedObjective = nan(maximumTrials, 1);
exactObjective = nan(maximumTrials, 1);
predictedReduction = nan(maximumTrials, 1);
actualReduction = nan(maximumTrials, 1);
reductionRatio = nan(maximumTrials, 1);
standardizedTrialStepNorm = nan(maximumTrials, 1);
physicalProjectedGradient = nan(maximumTrials, 1);
trialReplayPerformed = false(maximumTrials, 1);
trialReplayValid = false(maximumTrials, 1);
accepted = false(maximumTrials, 1);
decision = strings(maximumTrials, 1);
trustCandidateId = strings(maximumTrials, 1);
linearizedAugmentedResidualRatio = nan(maximumTrials, 1);
inexactNewtonTargetRatio = nan(maximumTrials, 1);
inexactNewtonRatioError = nan(maximumTrials, 1);
inexactNewtonSearchIterations = zeros(maximumTrials, 1);
inexactNewtonEqualityTargetBracketed = false(maximumTrials, 1);
inexactNewtonSelectionMode = strings(maximumTrials, 1);
trustCandidateRecords = repmat(local_empty_m3_candidate_record(), 0, 1);
acceptedEvaluation = [];
acceptedTheta = [];
acceptedDelta = [];
acceptedBox = [];
currentAugmentedResidual = [baselineEvaluation.whitenedResidual; ...
    lambdaPhysical * currentZ];
currentAugmentedResidualNorm = norm(currentAugmentedResidual);
lastProjectedGradient = Inf;
if useTrustRegion
    mu = min(trustState.damping, options.stageDM3TrustMaximumDamping);
else
    mu = min(trustState.damping, ...
        options.stageDM3InexactNewtonMaximumDamping);
end
for iTrial = 1:maximumTrials
    if useInexactNewton && iTrial == 1
        [trial, selection] = local_m3_select_inexact_newton_trial( ...
            contract, priorCenter, priorCholLower, ...
            priorPrecision, whitenedJacobian, linearizedIntercept, ...
            lowerDelta, upperDelta, currentDelta, currentZ, ...
            currentAugmentedResidualNorm, lambdaPhysical, ...
            trustState.damping, options);
        mu = trial.mu;
    else
        trial = local_m3_build_controlled_lm_trial(mu, contract, ...
            priorCenter, priorCholLower, priorPrecision, ...
            whitenedJacobian, linearizedIntercept, lowerDelta, upperDelta, ...
            currentDelta, currentZ, currentAugmentedResidualNorm, ...
            lambdaPhysical, options);
        selection = struct('searchIterationCount', 1, ...
            'equalityTargetBracketed', false, ...
            'selectionMode', "prescribed_damping");
    end
    algorithmicDamping(iTrial) = trial.mu;
    predictedObjective(iTrial) = trial.predictedObjective;
    predictedReduction(iTrial) = currentTotalCost - trial.predictedObjective;
    standardizedTrialStepNorm(iTrial) = trial.standardizedStepRelativeNorm;
    physicalProjectedGradient(iTrial) = trial.physicalProjectedGradient;
    linearizedAugmentedResidualRatio(iTrial) = ...
        trial.linearizedAugmentedResidualRatio;
    lastProjectedGradient = trial.physicalProjectedGradient;
    if useInexactNewton
        inexactNewtonTargetRatio(iTrial) = ...
            options.stageDM3InexactNewtonResidualRatio;
        inexactNewtonRatioError(iTrial) = ...
            trial.linearizedAugmentedResidualRatio - ...
            options.stageDM3InexactNewtonResidualRatio;
        inexactNewtonSearchIterations(iTrial) = selection.searchIterationCount;
        inexactNewtonEqualityTargetBracketed(iTrial) = ...
            selection.equalityTargetBracketed;
        inexactNewtonSelectionMode(iTrial) = selection.selectionMode;
        trustCandidateId(iTrial) = sprintf('%s_inexact_%02d_mu_%s', ...
            label, iTrial, local_m3_number_tag(mu));
        replayPurpose = 'm3_regularizing_lm_inexact_newton_candidate';
    else
        trustCandidateId(iTrial) = sprintf('%s_trust_%02d_mu_%s', ...
            label, iTrial, local_m3_number_tag(mu));
        replayPurpose = 'm3_regularized_trust_region_candidate';
    end

    if ~(isfinite(predictedReduction(iTrial)) && ...
            predictedReduction(iTrial) > 0)
        decision(iTrial) = "rejected_nonpositive_predicted_reduction";
    else
        oneEvaluation = evaluator(trial.theta, trustCandidateId(iTrial), ...
            replayPurpose, 0, 0, mu);
        trustCandidateRecords(end + 1, 1) = ...
            local_m3_candidate_record(oneEvaluation); %#ok<AGROW>
        trialReplayPerformed(iTrial) = true;
        trialReplayValid(iTrial) = oneEvaluation.valid;
        if oneEvaluation.valid
            oneDataCost = 0.5 * sum(oneEvaluation.whitenedResidual .^ 2);
            exactObjective(iTrial) = oneDataCost + ...
                0.5 * lambdaPhysical ^ 2 * sum(trial.z .^ 2);
            actualReduction(iTrial) = currentTotalCost - exactObjective(iTrial);
            reductionRatio(iTrial) = actualReduction(iTrial) / ...
                predictedReduction(iTrial);
            if useTrustRegion
                acceptExact = actualReduction(iTrial) > 0 && ...
                    reductionRatio(iTrial) >= ...
                    options.stageDM3TrustAcceptanceRatio;
            else
                exactDecreaseTolerance = max(1e-12, ...
                    1e-10 * max(1, abs(currentTotalCost)));
                acceptExact = actualReduction(iTrial) > exactDecreaseTolerance;
            end
            if acceptExact
                accepted(iTrial) = true;
                if useTrustRegion
                    decision(iTrial) = "accepted_by_exact_reduction_ratio";
                else
                    decision(iTrial) = ...
                        "accepted_inexact_newton_with_exact_safeguard";
                end
                acceptedEvaluation = oneEvaluation;
                acceptedTheta = trial.theta;
                acceptedDelta = trial.delta;
                acceptedBox = trial.boxAudit;
                break;
            elseif actualReduction(iTrial) <= 0
                decision(iTrial) = "rejected_nonpositive_exact_reduction";
            else
                decision(iTrial) = "rejected_insufficient_exact_reduction";
            end
        else
            decision(iTrial) = "rejected_invalid_exact_replay";
        end
    end

    if useTrustRegion
        if mu <= 0
            mu = max(options.stageDM3TrustMinimumDamping, lambdaPhysical ^ 2);
        else
            mu = min(options.stageDM3TrustMaximumDamping, max( ...
                options.stageDM3TrustMinimumDamping, ...
                mu * options.stageDM3TrustDampingIncreaseFactor));
        end
    else
        if mu <= 0
            mu = max(options.stageDM3InexactNewtonMinimumDamping, ...
                lambdaPhysical ^ 2);
        else
            mu = min(options.stageDM3InexactNewtonMaximumDamping, max( ...
                options.stageDM3InexactNewtonMinimumDamping, ...
                mu * options.stageDM3InexactNewtonDampingIncreaseFactor));
        end
    end
end
trialCount = iTrial;

if isempty(acceptedEvaluation)
    currentGradient = whitenedJacobian.' * ...
        baselineEvaluation.whitenedResidual + ...
        lambdaPhysical ^ 2 * priorPrecision * currentDelta;
    currentProjectedGradient = local_m3_scaled_projected_gradient( ...
        currentGradient, linearizationPoint, contract.lowerBound, ...
        contract.upperBound, contract.priorSigma);
    if currentProjectedGradient <= stationarityTolerance
        % 当前点已满足局部投影驻点条件时，保留当前点并正常
        % 终止。这不是用门限拒绝迭代，而是求解器的收敛判据。
        acceptedEvaluation = baselineEvaluation;
        acceptedTheta = linearizationPoint;
        acceptedDelta = currentDelta;
        acceptedBox = advisoryBox{selectedIndex};
        accepted(iTrial) = true;
        decision(iTrial) = "stationary_current_point_retained";
        exactObjective(iTrial) = currentTotalCost;
        predictedObjective(iTrial) = currentTotalCost;
        predictedReduction(iTrial) = 0;
        actualReduction(iTrial) = 0;
        reductionRatio(iTrial) = NaN;
        standardizedTrialStepNorm(iTrial) = 0;
        physicalProjectedGradient(iTrial) = currentProjectedGradient;
        trustCandidateId(iTrial) = string(baselineEvaluation.candidateId);
    else
        % 内层预算耗尽不等于物理回放失败，也不是收敛。保留已验证
        % 的当前点，外层继续重算Jacobian，直至正常收敛或用完总预算。
        % 不接受任何劣化候选；物理梯度仍超过门限，零步长不能单独
        % 触发收敛。最后一次独立Jacobian审核与最佳有效点保留仍执行。
        acceptedEvaluation = baselineEvaluation;
        acceptedTheta = linearizationPoint;
        acceptedDelta = currentDelta;
        acceptedBox = advisoryBox{selectedIndex};
        accepted(iTrial) = true;
        decision(iTrial) = "nonstationary_stalled_current_point_retained";
        exactObjective(iTrial) = currentTotalCost;
        predictedObjective(iTrial) = currentTotalCost;
        predictedReduction(iTrial) = 0;
        actualReduction(iTrial) = 0;
        reductionRatio(iTrial) = NaN;
        standardizedTrialStepNorm(iTrial) = 0;
        physicalProjectedGradient(iTrial) = currentProjectedGradient;
        trustCandidateId(iTrial) = string(baselineEvaluation.candidateId);
        trialReplayPerformed(iTrial) = false;
        trialReplayValid(iTrial) = baselineEvaluation.valid;
        if options.verbose
            fprintf(['%s：%d个内层候选后未找到下降步，保留有效当前点，' ...
                '不判收敛；梯度=%.3e，最后候选梯度=%.3e。\n'], ...
                label, maximumTrials, currentProjectedGradient, lastProjectedGradient);
        end
    end
end

acceptedIndex = find(accepted(1:trialCount), 1, 'last');
acceptedMu = algorithmicDamping(acceptedIndex);
acceptedRho = reductionRatio(acceptedIndex);
if useTrustRegion
    if isfinite(acceptedRho) && acceptedRho >= options.stageDM3TrustGoodRatio
        nextMu = acceptedMu * options.stageDM3TrustDampingDecreaseFactor;
        if nextMu < options.stageDM3TrustMinimumDamping
            nextMu = 0;
        end
    elseif isfinite(acceptedRho) && ...
            acceptedRho < options.stageDM3TrustPoorRatio
        if acceptedMu <= 0
            nextMu = max(options.stageDM3TrustMinimumDamping, lambdaPhysical ^ 2);
        else
            nextMu = min(options.stageDM3TrustMaximumDamping, ...
                acceptedMu * options.stageDM3TrustDampingIncreaseFactor);
        end
    else
        nextMu = acceptedMu;
    end
else
    % 非精确Newton每轮都重新根据当前增广残差求mu；上一轮值只作为
    % 下一轮矩阵搜索的起始尺度，不改变收缩准则。
    nextMu = acceptedMu;
end
if decision(acceptedIndex) == "nonstationary_stalled_current_point_retained"
    % 下一次新Jacobian从完整局部步重新尝试，不继承耗尽时的极大mu。
    nextMu = 0;
end
trustState.damping = nextMu;

selectedTheta = acceptedTheta;
deltaPrior = acceptedDelta;
fullUpdate = selectedTheta - linearizationPoint;
selectedZ = priorCholLower \ deltaPrior;
selectedEvaluation = acceptedEvaluation;
boundedSolution = acceptedBox;
boundedSolution.primalFeasible = all(selectedTheta >= contract.lowerBound & ...
    selectedTheta <= contract.upperBound);
boundedSolution.strictlyInterior = all(selectedTheta > contract.lowerBound & ...
    selectedTheta < contract.upperBound);
boundedSolution.kktStationarityResidualInf = boundedSolution.kktResidualInf;
boundedSolution.relativeKktStationarityResidual = ...
    boundedSolution.relativeKktResidual;
refinedSchedule = selectedEvaluation.schedule;

selectedDataCost = 0.5 * sum(selectedEvaluation.whitenedResidual .^ 2);
selectedTotalCost = selectedDataCost + ...
    0.5 * lambdaPhysical ^ 2 * sum(selectedZ .^ 2);
standardizedStepRelativeNorm = norm(selectedZ - currentZ) / ...
    max([1, norm(currentZ), norm(selectedZ)]);
totalCostRelativeChange = abs(selectedTotalCost - currentTotalCost) / ...
    max([abs(currentTotalCost), abs(selectedTotalCost), 1e-12]);
selectedProjectedGradient = physicalProjectedGradient(acceptedIndex);
nonlinearConvergenceProposed = ...
    standardizedStepRelativeNorm <= options.stepRelativeTolerance && ...
    totalCostRelativeChange <= options.costRelativeTolerance && ...
    selectedProjectedGradient <= stationarityTolerance;

relativeLower = (selectedTheta - contract.lowerBound) ./ ...
    max(contract.upperBound - contract.lowerBound, eps);
relativeUpper = (contract.upperBound - selectedTheta) ./ ...
    max(contract.upperBound - contract.lowerBound, eps);
finalMinimumMargin = min([relativeLower; relativeUpper]);
linearPrediction = linearizedIntercept + whitenedJacobian * deltaPrior;
linearPredictionRelativeError = norm( ...
    selectedEvaluation.whitenedResidual - linearPrediction) / ...
    max([norm(selectedEvaluation.whitenedResidual), ...
    norm(linearPrediction), 1e-12]);
linearPredictionPassed = linearPredictionRelativeError <= ...
    options.stageDM3LinearPredictionRelativeTolerance;

% 用信赖域实际接受的候选更新用户指定lambda行。
exactDataCost(selectedIndex) = selectedDataCost;
selectedDenominator = max((m - effectiveDegreesOfFreedom(selectedIndex)) ^ 2, eps);
exactGcv(selectedIndex) = ...
    m * sum(selectedEvaluation.whitenedResidual .^ 2) / selectedDenominator;
priorStandardizedUpdateNorm(selectedIndex) = norm(selectedZ);
maximumAbsoluteUpdate(selectedIndex) = max(abs(fullUpdate));
minimumRelativeBoundMargin(selectedIndex) = finalMinimumMargin;
kktResidualInf(selectedIndex) = boundedSolution.kktResidualInf;
relativeKktResidual(selectedIndex) = boundedSolution.relativeKktResidual;
activeBoundCount(selectedIndex) = boundedSolution.activeBoundCount;
boxIterationCount(selectedIndex) = boundedSolution.iterationCount;
withinBounds(selectedIndex) = boundedSolution.primalFeasible;
replayPerformed(selectedIndex) = true;
replayValid(selectedIndex) = selectedEvaluation.valid;
trainingCostNonincrease(selectedIndex) = selectedDataCost <= ...
    baselineDataCost * (1 + 1e-8);
candidateId(selectedIndex) = string(selectedEvaluation.candidateId);
regularizationCandidates = table(lambda, effectiveDegreesOfFreedom, ...
    linearizedDataCost, exactDataCost, linearizedGcv, exactGcv, ...
    priorStandardizedUpdateNorm, maximumAbsoluteUpdate, ...
    minimumRelativeBoundMargin, kktResidualInf, relativeKktResidual, ...
    activeBoundCount, boxIterationCount, withinBounds, replayPerformed, ...
    replayValid, trainingCostNonincrease, eligible, selected, ...
    gcvRecommended, candidateId, boxConstrainedEquivalent, ...
    'VariableNames', {'lambda','effective_degrees_of_freedom', ...
    'linearized_data_cost','exact_data_cost','linearized_gcv','exact_gcv', ...
    'prior_standardized_solution_norm','maximum_absolute_applied_update', ...
    'minimum_relative_bound_margin','kkt_residual_inf', ...
    'relative_kkt_residual','active_bound_count','box_iteration_count', ...
    'within_bounds','replay_performed','replay_valid', ...
    'training_cost_nonincrease','eligible','selected','gcv_recommended', ...
    'candidate_id','box_constrained_equivalent'});

if useTrustRegion
    trustRegionHistory = table(trialIndex(1:trialCount), ...
        algorithmicDamping(1:trialCount), ...
        repmat(currentTotalCost, trialCount, 1), ...
        predictedObjective(1:trialCount), exactObjective(1:trialCount), ...
        predictedReduction(1:trialCount), actualReduction(1:trialCount), ...
        reductionRatio(1:trialCount), standardizedTrialStepNorm(1:trialCount), ...
        physicalProjectedGradient(1:trialCount), ...
        trialReplayPerformed(1:trialCount), trialReplayValid(1:trialCount), ...
        accepted(1:trialCount), decision(1:trialCount), ...
        trustCandidateId(1:trialCount), ...
        'VariableNames', {'trust_trial','algorithmic_damping', ...
        'current_exact_objective','predicted_objective','exact_objective', ...
        'predicted_reduction','actual_reduction','reduction_ratio', ...
        'standardized_step_relative_norm','physical_projected_gradient', ...
        'replay_performed','replay_valid','accepted','decision','candidate_id'});
    inexactNewtonHistory = table();
else
    trustRegionHistory = table();
    inexactNewtonHistory = table(trialIndex(1:trialCount), ...
        algorithmicDamping(1:trialCount), ...
        repmat(currentTotalCost, trialCount, 1), ...
        predictedObjective(1:trialCount), exactObjective(1:trialCount), ...
        predictedReduction(1:trialCount), actualReduction(1:trialCount), ...
        reductionRatio(1:trialCount), ...
        linearizedAugmentedResidualRatio(1:trialCount), ...
        inexactNewtonTargetRatio(1:trialCount), ...
        inexactNewtonRatioError(1:trialCount), ...
        inexactNewtonSearchIterations(1:trialCount), ...
        inexactNewtonEqualityTargetBracketed(1:trialCount), ...
        inexactNewtonSelectionMode(1:trialCount), ...
        standardizedTrialStepNorm(1:trialCount), ...
        physicalProjectedGradient(1:trialCount), ...
        trialReplayPerformed(1:trialCount), trialReplayValid(1:trialCount), ...
        accepted(1:trialCount), decision(1:trialCount), ...
        trustCandidateId(1:trialCount), ...
        'VariableNames', {'exact_safeguard_trial','algorithmic_damping', ...
        'current_exact_objective','predicted_objective','exact_objective', ...
        'predicted_reduction','actual_reduction', ...
        'actual_to_predicted_reduction_ratio_diagnostic', ...
        'linearized_augmented_residual_ratio','target_residual_ratio', ...
        'ratio_minus_target','matrix_search_iteration_count', ...
        'equality_target_bracketed','selection_mode', ...
        'standardized_step_relative_norm','physical_projected_gradient', ...
        'replay_performed','replay_valid','accepted','decision','candidate_id'});
end

allCandidateRecords = candidateRecords(:);
if ~isempty(trustCandidateRecords)
    allCandidateRecords = [allCandidateRecords; trustCandidateRecords];
end
candidateReplayIdentity = struct2table(allCandidateRecords);
currentGradient = whitenedJacobian.' * baselineEvaluation.whitenedResidual + ...
    lambdaPhysical ^ 2 * priorPrecision * currentDelta;
currentProjectedGradient = local_m3_scaled_projected_gradient( ...
    currentGradient, linearizationPoint, contract.lowerBound, ...
    contract.upperBound, contract.priorSigma);
augmentedResidual = [selectedEvaluation.whitenedResidual; ...
    lambdaPhysical * selectedZ];
initialAugmentedResidual = [baselineEvaluation.whitenedResidual; ...
    lambdaPhysical * currentZ];
augmentedJacobian = [whitenedJacobian; ...
    lambdaPhysical * priorPrecisionFactor];
scaledAugmentedJacobian = [standardizedJacobian; ...
    lambdaPhysical * eye(d)];
[~, sMatrix, ~] = svd(standardizedJacobian, 'econ');
singularValues = diag(sMatrix);
rankTolerance = 0;
if ~isempty(singularValues)
    rankTolerance = max(size(standardizedJacobian)) * eps(max(singularValues));
end
numericalRank = sum(singularValues > rankTolerance);
if numericalRank >= 1
    conditionNumber = singularValues(1) / singularValues(numericalRank);
else
    conditionNumber = Inf;
end
if useTrustRegion
    stepStopReason = "regularized_trust_region_step_completed";
    regularizationMethod = 'box_constrained_tikhonov_trust_region';
    regularizationSelectionCriterion = ...
        'user_physical_lambda_with_linearized_gcv_advisory_and_exact_trust_ratio';
    regularizationControlMode = ...
        'user_physical_lambda_separate_exact_ratio_controlled_lm_damping';
else
    stepStopReason = "regularizing_lm_inexact_newton_step_completed";
    regularizationMethod = ...
        'box_constrained_tikhonov_regularizing_lm_inexact_newton';
    regularizationSelectionCriterion = ...
        'user_physical_lambda_with_linearized_gcv_advisory_and_inexact_newton_ratio';
    regularizationControlMode = ...
        'user_physical_lambda_separate_inexact_newton_controlled_lm_damping';
end
history = table(1, baselineDataCost, selectedDataCost, lambdaPhysical, ...
    true, linearPredictionRelativeError, linearPredictionPassed, ...
    stepStopReason, ...
    'VariableNames', {'iteration','data_cost_before','data_cost_after', ...
    'selected_lambda','full_update_applied', ...
    'linear_prediction_relative_error','linear_prediction_passed', ...
    'stop_reason'});

solve = struct();
solve.label = label;
solve.executed = true;
solve.parameterization = 'actual_execution_nodes';
solve.jacobianMethod = 'node_central_full';
solve.x = selectedTheta;
solve.initialX = linearizationPoint;
solve.priorCenterX = priorCenter;
solve.initialOffset = zeros(d, 1);
solve.offset = fullUpdate;
solve.fullRegularizedUpdate = fullUpdate;
solve.priorCenteredFullSolution = deltaPrior;
solve.fullUpdateAppliedWithoutGlobalScaling = true;
solve.globalAlphaUsed = false;
solve.lmDampingUsed = any(algorithmicDamping(1:trialCount) > 0);
solve.regularizedTrustRegionUsed = useTrustRegion;
solve.regularizingInexactNewtonUsed = useInexactNewton;
solve.uncontrolledLmDampingUsed = false;
solve.converged = false;
solve.stopReason = 'nonlinear_iteration_completed';
solve.iterationCount = 1;
solve.costInitial = currentTotalCost;
solve.costFinal = selectedTotalCost;
solve.dataCostInitial = baselineDataCost;
solve.dataCostFinal = selectedDataCost;
solve.initialResidual = initialAugmentedResidual;
solve.initialDataResidual = baselineEvaluation.whitenedResidual;
solve.residual = augmentedResidual;
solve.meta = struct('valid', selectedEvaluation.valid, ...
    'prediction', selectedEvaluation.prediction, ...
    'dataResidual', selectedEvaluation.whitenedResidual, ...
    'rawDataResidual', selectedEvaluation.rawResidual, ...
    'regularization', lambdaPhysical * selectedZ, ...
    'regularizationMethod', regularizationMethod, ...
    'schedule', refinedSchedule);
solve.initialJacobian = augmentedJacobian;
solve.initialDataJacobian = whitenedJacobian;
solve.jacobian = augmentedJacobian;
solve.rawDataJacobian = rawJacobian;
solve.dataJacobian = whitenedJacobian;
solve.whitenedDataJacobian = whitenedJacobian;
solve.parameterScaledJacobian = ...
    whitenedJacobian .* contract.priorSigma.';
solve.priorWhitenedJacobian = standardizedJacobian;
solve.scaledDataJacobian = standardizedJacobian;
solve.scaledJacobian = scaledAugmentedJacobian;
solve.singularValues = singularValues;
solve.dataSingularValues = singularValues;
solve.numericalRank = numericalRank;
solve.dataNumericalRank = numericalRank;
solve.conditionNumber = conditionNumber;
solve.dataConditionNumber = conditionNumber;
solve.regularizationMethod = regularizationMethod;
solve.tsvdStepMode = 'not_applicable';
solve.parameterScale = contract.priorSigma;
solve.parameterCount = d;
solve.activeNodeCount = d;
solve.dataResidualCount = m;
solve.lowerBound = contract.lowerBound;
solve.upperBound = contract.upperBound;
solve.differenceStep = usedStep;
solve.differenceStepScale = options.stageDDifferenceStepScale;
solve.informationMatrixDimension = [d, d];
solve.requestedRetainedSingularValueCount = d;
solve.retainedSingularValueCount = numericalRank;
solve.truncatedSingularValueCount = max(0, d - numericalRank);
solve.retainedConditionNumber = conditionNumber;
solve.history = history;
solve.nodeContract = contract;
solve.nodeContractHash = contract.nodeContractHash;
solve.fixedAnchorTable = contract.fixedAnchorTable;
solve.perturbationAudit = perturbationAudit;
solve.stepStability = stepStability;
solve.stepStabilityPassed = all(stepStability.passed);
solve.priorCorrelation = priorCorrelation;
solve.priorCovariance = priorCovariance;
solve.priorCholLower = priorCholLower;
solve.priorGroupTable = priorGroupTable;
solve.regularizationCandidates = regularizationCandidates;
solve.regularizationSelectionCriterion = regularizationSelectionCriterion;
solve.regularizationControlMode = regularizationControlMode;
solve.configuredRegularizationStrength = lambdaPhysical;
solve.selectedRegularizationStrength = lambdaPhysical;
solve.selectedRegularizationCandidateIndex = selectedIndex;
solve.gcvRecommendedRegularizationStrength = lambda(gcvRecommendedIndex);
solve.gcvRecommendedRegularizationCandidateIndex = gcvRecommendedIndex;
solve.boundedSolution = boundedSolution;
solve.linearPredictionCheck = struct( ...
    'predictedWhitenedResidual', linearPrediction, ...
    'exactWhitenedResidual', selectedEvaluation.whitenedResidual, ...
    'relativeResidualError', linearPredictionRelativeError, ...
    'relativeTolerance', options.stageDM3LinearPredictionRelativeTolerance, ...
    'passed', linearPredictionPassed, ...
    'usesIndependentFullDllCandidate', true, 'diagnosticOnly', true);
solve.nonlinearConvergence = struct( ...
    'standardizedStepRelativeNorm', standardizedStepRelativeNorm, ...
    'stepRelativeTolerance', options.stepRelativeTolerance, ...
    'totalObjectiveRelativeChange', totalCostRelativeChange, ...
    'objectiveRelativeTolerance', options.costRelativeTolerance, ...
    'physicalProjectedGradientInitial', currentProjectedGradient, ...
    'physicalProjectedGradientFinalLinearModel', selectedProjectedGradient, ...
    'stationarityTolerance', stationarityTolerance, ...
    'totalObjectiveDecreased', selectedTotalCost <= currentTotalCost, ...
    'proposedConverged', nonlinearConvergenceProposed, ...
    'evaluatedAfterFreshJacobian', true);
if useTrustRegion
    solve.trustRegion = struct( ...
        'method', 'ratio_controlled_regularizing_levenberg_marquardt', ...
        'physicalRegularizationStrength', lambdaPhysical, ...
        'initialAlgorithmicDamping', algorithmicDamping(1), ...
        'acceptedAlgorithmicDamping', acceptedMu, ...
        'acceptedReductionRatio', acceptedRho, ...
        'nextAlgorithmicDamping', nextMu, ...
        'trialCount', trialCount, 'acceptedTrialIndex', acceptedIndex, ...
        'acceptanceRatio', options.stageDM3TrustAcceptanceRatio, ...
        'poorRatio', options.stageDM3TrustPoorRatio, ...
        'goodRatio', options.stageDM3TrustGoodRatio, ...
        'physicalObjectiveIncludesAlgorithmicDamping', false);
    solve.inexactNewton = struct('executed', false);
else
    solve.trustRegion = struct('executed', false);
    solve.inexactNewton = struct( ...
        'method', 'hanke_style_regularizing_lm_inexact_newton', ...
        'physicalRegularizationStrength', lambdaPhysical, ...
        'targetLinearizedAugmentedResidualRatio', ...
        options.stageDM3InexactNewtonResidualRatio, ...
        'ratioTolerance', options.stageDM3InexactNewtonRatioTolerance, ...
        'acceptedAlgorithmicDamping', acceptedMu, ...
        'acceptedLinearizedAugmentedResidualRatio', ...
        linearizedAugmentedResidualRatio(acceptedIndex), ...
        'equalityTargetBracketed', ...
        inexactNewtonEqualityTargetBracketed(acceptedIndex), ...
        'matrixSearchIterationCount', ...
        inexactNewtonSearchIterations(acceptedIndex), ...
        'exactSafeguardTrialCount', trialCount, ...
        'acceptedExactSafeguardTrialIndex', acceptedIndex, ...
        'exactDllObjectiveUsedOnlyAsSafeguard', true, ...
        'discrepancyPrincipleUsed', false, ...
        'discrepancyPrincipleUnavailableReason', ...
        'M0_engineering_residual_has_no_calibrated_noise_norm', ...
        'physicalObjectiveIncludesAlgorithmicDamping', false);
end
solve.trustRegionHistory = trustRegionHistory;
solve.inexactNewtonHistory = inexactNewtonHistory;
solve.candidateReplayIdentity = candidateReplayIdentity;
solve.replayAudit = struct( ...
    'minimumRequiredJacobianCandidateCount', 1 + 2 * d, ...
    'jacobianCandidateCount', 1 + sum( ...
        perturbationAudit.candidate_evaluation_count), ...
    'actualCandidateCount', height(candidateReplayIdentity), ...
    'pointReplayCount', sum(candidateReplayIdentity.point_replay_count), ...
    'solveAttemptCount', sum(candidateReplayIdentity.solve_attempt_count), ...
    'invalidPointCount', sum(candidateReplayIdentity.invalid_point_count), ...
    'cacheHitCount', sum(candidateReplayIdentity.cache_hit_count), ...
    'wallSeconds', sum(candidateReplayIdentity.wall_seconds), ...
    'batchSize', options.stageDM3BatchSize, ...
    'pauseCount', 0, 'resumeCount', 0, 'resumeSupported', false);
solve.minimumRelativeBoundMargin = finalMinimumMargin;
solve.atBound = finalMinimumMargin <= 1e-8;
solve.wallSeconds = toc(passTimer);
end

function [trial, selection] = local_m3_select_inexact_newton_trial( ...
        contract, priorCenter, priorCholLower, ...
        priorPrecision, whitenedJacobian, linearizedIntercept, ...
        lowerDelta, upperDelta, currentDelta, currentZ, ...
        currentAugmentedResidualNorm, lambdaPhysical, initialDamping, options)
%LOCAL_M3_SELECT_INEXACT_NEWTON_TRIAL 以增广残差收缩比选择LM阻尼。
%
% 对固定物理目标的增广残差R=[r;lambda*z]，寻找mu使
% ||R_k+A_k*s(mu)||/||R_k||约等于rho。搜索过程只解有界二次
% 子问题，不调用DLL；最终选中的mu才由外层执行一次精确回放。

target = options.stageDM3InexactNewtonResidualRatio;
tolerance = options.stageDM3InexactNewtonRatioTolerance;
maximumSearch = options.stageDM3InexactNewtonMaximumSearchIterations;
increaseFactor = options.stageDM3InexactNewtonDampingIncreaseFactor;
minimumDamping = options.stageDM3InexactNewtonMinimumDamping;
maximumDamping = options.stageDM3InexactNewtonMaximumDamping;

zeroTrial = local_m3_build_controlled_lm_trial(0, contract, ...
    priorCenter, priorCholLower, priorPrecision, ...
    whitenedJacobian, linearizedIntercept, lowerDelta, upperDelta, ...
    currentDelta, currentZ, currentAugmentedResidualNorm, ...
    lambdaPhysical, options);
searchCount = 1;
if zeroTrial.linearizedAugmentedResidualRatio >= target
    trial = zeroTrial;
    selection = struct('searchIterationCount', searchCount, ...
        'equalityTargetBracketed', ...
        zeroTrial.linearizedAugmentedResidualRatio <= target + tolerance, ...
        'selectionMode', "undamped_step_satisfies_inexact_newton_inequality");
    return;
end

lowerTrial = zeroTrial;
initialPositiveDamping = max([minimumDamping, lambdaPhysical ^ 2, ...
    min(maximumDamping, initialDamping)]);
upperTrial = local_m3_build_controlled_lm_trial(initialPositiveDamping, ...
    contract, priorCenter, priorCholLower, ...
    priorPrecision, whitenedJacobian, linearizedIntercept, lowerDelta, ...
    upperDelta, currentDelta, currentZ, currentAugmentedResidualNorm, ...
    lambdaPhysical, options);
searchCount = searchCount + 1;
while upperTrial.linearizedAugmentedResidualRatio < target && ...
        upperTrial.mu < maximumDamping && searchCount < maximumSearch
    lowerTrial = upperTrial;
    nextMu = min(maximumDamping, max(minimumDamping, ...
        upperTrial.mu * increaseFactor));
    if nextMu <= upperTrial.mu
        break;
    end
    upperTrial = local_m3_build_controlled_lm_trial(nextMu, contract, ...
        priorCenter, priorCholLower, priorPrecision, ...
        whitenedJacobian, linearizedIntercept, lowerDelta, upperDelta, ...
        currentDelta, currentZ, currentAugmentedResidualNorm, ...
        lambdaPhysical, options);
    searchCount = searchCount + 1;
end

if upperTrial.linearizedAugmentedResidualRatio < target
    trial = upperTrial;
    selection = struct('searchIterationCount', searchCount, ...
        'equalityTargetBracketed', false, ...
        'selectionMode', "maximum_damping_without_target_bracket");
    return;
end

% 始终保留满足q>=rho的一侧，避免选择违反非精确Newton不等式的步。
while upperTrial.linearizedAugmentedResidualRatio > target + tolerance && ...
        searchCount < maximumSearch
    lowerMu = lowerTrial.mu;
    upperMu = upperTrial.mu;
    if lowerMu <= 0
        middleMu = 0.5 * upperMu;
    else
        middleMu = sqrt(lowerMu * upperMu);
    end
    if ~(middleMu > lowerMu && middleMu < upperMu)
        break;
    end
    middleTrial = local_m3_build_controlled_lm_trial(middleMu, contract, ...
        priorCenter, priorCholLower, priorPrecision, ...
        whitenedJacobian, linearizedIntercept, lowerDelta, upperDelta, ...
        currentDelta, currentZ, currentAugmentedResidualNorm, ...
        lambdaPhysical, options);
    searchCount = searchCount + 1;
    if middleTrial.linearizedAugmentedResidualRatio >= target
        upperTrial = middleTrial;
    else
        lowerTrial = middleTrial;
    end
end
trial = upperTrial;
selection = struct('searchIterationCount', searchCount, ...
    'equalityTargetBracketed', true, ...
    'selectionMode', "bracketed_inexact_newton_ratio_search");
end

function trial = local_m3_build_controlled_lm_trial(mu, contract, ...
        priorCenter, priorCholLower, priorPrecision, ...
        whitenedJacobian, linearizedIntercept, lowerDelta, upperDelta, ...
        currentDelta, currentZ, currentAugmentedResidualNorm, ...
        lambdaPhysical, options)
%LOCAL_M3_BUILD_CONTROLLED_LM_TRIAL 构造一个不调用DLL的有界LM候选。
hessian = whitenedJacobian.' * whitenedJacobian + ...
    (lambdaPhysical ^ 2 + mu) * priorPrecision;
linearTerm = whitenedJacobian.' * linearizedIntercept - ...
    mu * priorPrecision * currentDelta;
[delta, boxAudit] = local_m3_box_quadratic_solve(hessian, linearTerm, ...
    lowerDelta, upperDelta, options.stageDM3BoxKktRelativeTolerance, ...
    options.stageDM3BoxMaximumIterations);
theta = priorCenter + delta;
z = priorCholLower \ delta;
linearResidual = linearizedIntercept + whitenedJacobian * delta;
linearizedAugmentedResidual = [linearResidual; lambdaPhysical * z];
predictedObjective = 0.5 * sum(linearizedAugmentedResidual .^ 2);
standardizedStepRelativeNorm = norm(z - currentZ) / ...
    max([1, norm(currentZ), norm(z)]);
physicalGradient = whitenedJacobian.' * linearResidual + ...
    lambdaPhysical ^ 2 * priorPrecision * delta;
physicalProjectedGradient = local_m3_scaled_projected_gradient( ...
    physicalGradient, theta, contract.lowerBound, contract.upperBound, ...
    contract.priorSigma);
trial = struct('mu', mu, 'delta', delta, 'theta', theta, 'z', z, ...
    'boxAudit', boxAudit, 'linearResidual', linearResidual, ...
    'predictedObjective', predictedObjective, ...
    'standardizedStepRelativeNorm', standardizedStepRelativeNorm, ...
    'physicalProjectedGradient', physicalProjectedGradient, ...
    'linearizedAugmentedResidualRatio', ...
    norm(linearizedAugmentedResidual) / max(currentAugmentedResidualNorm, eps));
end

function relativeGradient = local_m3_scaled_projected_gradient( ...
        gradient, theta, lowerBound, upperBound, priorSigma)
% 用参数先验标准差消除量纲，再按有界最优性去除指向
% 可行域外的梯度分量。
gradient = gradient(:);
theta = theta(:);
lowerBound = lowerBound(:);
upperBound = upperBound(:);
priorSigma = priorSigma(:);
marginTolerance = 64 * eps(max([1; abs(lowerBound); abs(upperBound)]));
projected = gradient;
atLower = theta <= lowerBound + marginTolerance;
atUpper = theta >= upperBound - marginTolerance;
projected(atLower & gradient >= 0) = 0;
projected(atUpper & gradient <= 0) = 0;
scaled = priorSigma .* projected;
relativeGradient = norm(scaled, inf);
end

function [solve, refinedSchedule] = local_run_stage_d_m3_tsvd_linearization( ...
        contract, priorCenter, linearizationPoint, evaluator, ...
        baselineEvaluation, rawJacobian, whitenedJacobian, ...
        perturbationAudit, usedStep, stepStability, priorCorrelation, ...
        priorCovariance, priorCholLower, priorGroupTable, candidateRecords, ...
        standardizedJacobian, options, label, passTimer)
%LOCAL_RUN_STAGE_D_M3_TSVD_LINEARIZATION 一次先验中心化无阻尼TSVD更新。
%
% 使用 z=L\(theta-theta_prior) 消除参数单位、先验尺度和组内相关性的
% 影响。对 A=J*L 做SVD后，保留方向严格使用1/sigma，截断方向令z=0，
% 即回到Stage-C先验中心。这里不使用LM、谱阻尼、全局更新比例或裁剪；
% 配置阶数得到的完整候选若越出物理边界，直接报告配置无效。

% 截断方向回到先验中心属于TSVD参数化定义，不是附加高斯惩罚项，
% 因而非线性收敛目标只包含精确DLL数据代价。

d = contract.parameterCount;
m = numel(baselineEvaluation.whitenedResidual);
[u, sMatrix, v] = svd(standardizedJacobian, 'econ');
singularValues = diag(sMatrix);
if isempty(singularValues)
    numericalRank = 0;
else
    rankTolerance = max(size(standardizedJacobian)) * ...
        eps(max(singularValues));
    numericalRank = sum(singularValues > rankTolerance);
end
maximumRetained = min([numericalRank, numel(singularValues), m - 1]);
requestedRetained = options.stageDTsvdRetainedCount;
if maximumRetained < 1 || requestedRetained > maximumRetained
    error('SHT:SteadyAdaptV2:M3BadTsvdRetainedCount', ...
        ['%s请求保留%d个奇异方向，但当前数值秩=%d、数据残差数=%d，' ...
         '为保持GCV分母和直接伪逆有效，最多只能保留%d个。'], ...
        label, requestedRetained, numericalRank, m, maximumRetained);
end

linearizedIntercept = baselineEvaluation.whitenedResidual + ...
    whitenedJacobian * (priorCenter - linearizationPoint);
lowerBound = contract.lowerBound;
upperBound = contract.upperBound;
span = max(upperBound - lowerBound, eps);
retainedCount = (1:maximumRetained).';
candidateCount = numel(retainedCount);
linearizedDataCost = inf(candidateCount, 1);
linearizedGcv = inf(candidateCount, 1);
priorStandardizedUpdateNorm = inf(candidateCount, 1);
maximumAbsoluteUpdate = inf(candidateCount, 1);
minimumRelativeBoundMargin = -inf(candidateCount, 1);
withinBounds = false(candidateCount, 1);
candidateTheta = cell(candidateCount, 1);
candidateZ = cell(candidateCount, 1);
candidateId = strings(candidateCount, 1);
for i = 1:candidateCount
    q = retainedCount(i);
    z = -v(:, 1:q) * ((u(:, 1:q).' * linearizedIntercept) ./ ...
        singularValues(1:q));
    theta = priorCenter + priorCholLower * z;
    candidateZ{i} = z;
    candidateTheta{i} = theta;
    candidateId(i) = sprintf('%s_tsvd_r%02d', label, q);
    linearResidual = linearizedIntercept + ...
        standardizedJacobian * z;
    linearizedDataCost(i) = 0.5 * sum(linearResidual .^ 2);
    linearizedGcv(i) = m * sum(linearResidual .^ 2) / ...
        max((m - q) ^ 2, eps);
    priorStandardizedUpdateNorm(i) = norm(z);
    maximumAbsoluteUpdate(i) = max(abs(theta - linearizationPoint));
    relativeLower = (theta - lowerBound) ./ span;
    relativeUpper = (upperBound - theta) ./ span;
    minimumRelativeBoundMargin(i) = min([relativeLower; relativeUpper]);
    withinBounds(i) = all(theta >= lowerBound & theta <= upperBound);
end

selectedIndex = requestedRetained;
selectedTheta = candidateTheta{selectedIndex};
selectedZ = candidateZ{selectedIndex};
if ~withinBounds(selectedIndex)
    [minimumMargin, worstIndex] = min([ ...
        (selectedTheta - lowerBound) ./ span; ...
        (upperBound - selectedTheta) ./ span]);
    if worstIndex > d
        nodeIndex = worstIndex - d;
        boundName = 'upper';
    else
        nodeIndex = worstIndex;
        boundName = 'lower';
    end
    error('SHT:SteadyAdaptV2:M3TsvdCandidateOutOfBounds', ...
        ['%s保留%d阶TSVD候选越出%s边界：节点=%s，theta=%.8g，' ...
         'lower=%.8g，upper=%.8g，归一化最小边界裕度=%.3e。' ...
         '不得通过裁剪或更新比例掩盖，应减少保留阶数或调整先验尺度。'], ...
        label, requestedRetained, boundName, ...
        char(contract.parameterTable.node_id(nodeIndex)), ...
        selectedTheta(nodeIndex), lowerBound(nodeIndex), ...
        upperBound(nodeIndex), minimumMargin);
end

selectedEvaluation = evaluator(selectedTheta, candidateId(selectedIndex), ...
    'm3_prior_centered_tsvd_candidate', 0, 0, NaN);
candidateRecords(end + 1, 1) = ...
    local_m3_candidate_record(selectedEvaluation);
if ~selectedEvaluation.valid
    error('SHT:SteadyAdaptV2:M3TsvdCandidateReplayInvalid', ...
        '%s保留%d阶TSVD候选不能完成全部训练工况精确DLL回放。', ...
        label, requestedRetained);
end

exactDataCost = nan(candidateCount, 1);
exactGcv = nan(candidateCount, 1);
replayPerformed = false(candidateCount, 1);
replayValid = false(candidateCount, 1);
trainingCostNonincrease = false(candidateCount, 1);
eligible = false(candidateCount, 1);
selected = false(candidateCount, 1);
gcvRecommended = false(candidateCount, 1);
baselineDataCost = 0.5 * sum(baselineEvaluation.whitenedResidual .^ 2);
exactDataCost(selectedIndex) = ...
    0.5 * sum(selectedEvaluation.whitenedResidual .^ 2);
exactGcv(selectedIndex) = m * ...
    sum(selectedEvaluation.whitenedResidual .^ 2) / ...
    max((m - requestedRetained) ^ 2, eps);
replayPerformed(selectedIndex) = true;
replayValid(selectedIndex) = true;
trainingCostNonincrease(selectedIndex) = ...
    exactDataCost(selectedIndex) <= baselineDataCost * (1 + 1e-8);
eligible(selectedIndex) = true;
selected(selectedIndex) = true;
gcvEligible = find(withinBounds & isfinite(linearizedGcv));
[~, gcvLocalIndex] = min(linearizedGcv(gcvEligible));
gcvRecommendedIndex = gcvEligible(gcvLocalIndex);
gcvRecommended(gcvRecommendedIndex) = true;

% TSVD没有二次惩罚KKT系统。沿用boundedSolution字段只承载物理边界
% 可行性，KKT量明确置NaN，避免把未计算的KKT误报为零残差。
activeTolerance = 64 * eps(max([1; abs(selectedTheta)]));
activeLower = abs(selectedTheta - lowerBound) <= activeTolerance;
activeUpper = abs(selectedTheta - upperBound) <= activeTolerance;
primalViolation = max([max(lowerBound - selectedTheta), ...
    max(selectedTheta - upperBound), 0]);
boundedSolution = struct( ...
    'method', 'prior_centered_tsvd_direct_inverse_feasibility', ...
    'iterationCount', 1, 'maximumIterations', 1, ...
    'activeLower', activeLower, 'activeUpper', activeUpper, ...
    'activeBoundCount', sum(activeLower | activeUpper), ...
    'boundHitCount', 0, 'releaseCount', 0, ...
    'gradient', nan(d, 1), 'primalViolation', primalViolation, ...
    'freeStationarityResidualInf', NaN, ...
    'lowerDualViolation', NaN, 'upperDualViolation', NaN, ...
    'kktResidualInf', NaN, 'relativeKktResidual', NaN, ...
    'hessianReciprocalCondition', NaN, 'passed', primalViolation == 0, ...
    'primalFeasible', primalViolation == 0, ...
    'strictlyInterior', all(selectedTheta > lowerBound & ...
    selectedTheta < upperBound), ...
    'kktStationarityResidualInf', NaN, ...
    'relativeKktStationarityResidual', NaN);

lambda = nan(candidateCount, 1);
effectiveDegreesOfFreedom = retainedCount;
kktResidualInf = nan(candidateCount, 1);
relativeKktResidual = nan(candidateCount, 1);
activeBoundCount = nan(candidateCount, 1);
activeBoundCount(selectedIndex) = boundedSolution.activeBoundCount;
boxIterationCount = nan(candidateCount, 1);
boxIterationCount(selectedIndex) = 1;
boxConstrainedEquivalent = false(candidateCount, 1);
regularizationCandidates = table(lambda, retainedCount, ...
    effectiveDegreesOfFreedom, linearizedDataCost, exactDataCost, ...
    linearizedGcv, exactGcv, priorStandardizedUpdateNorm, ...
    maximumAbsoluteUpdate, minimumRelativeBoundMargin, kktResidualInf, ...
    relativeKktResidual, activeBoundCount, boxIterationCount, ...
    withinBounds, replayPerformed, replayValid, ...
    trainingCostNonincrease, eligible, selected, gcvRecommended, ...
    candidateId, boxConstrainedEquivalent, ...
    'VariableNames', {'lambda','retained_singular_value_count', ...
    'effective_degrees_of_freedom','linearized_data_cost', ...
    'exact_data_cost','linearized_gcv','exact_gcv', ...
    'prior_standardized_solution_norm', ...
    'maximum_absolute_applied_update','minimum_relative_bound_margin', ...
    'kkt_residual_inf','relative_kkt_residual','active_bound_count', ...
    'box_iteration_count','within_bounds','replay_performed', ...
    'replay_valid','training_cost_nonincrease','eligible','selected', ...
    'gcv_recommended','candidate_id','box_constrained_equivalent'});

currentZ = priorCholLower \ (linearizationPoint - priorCenter);
fullUpdate = selectedTheta - linearizationPoint;
initialTotalCost = baselineDataCost;
finalTotalCost = exactDataCost(selectedIndex);
standardizedStepRelativeNorm = norm(selectedZ - currentZ) / ...
    max([1, norm(currentZ), norm(selectedZ)]);
totalCostRelativeChange = abs(finalTotalCost - initialTotalCost) / ...
    max([abs(initialTotalCost), abs(finalTotalCost), 1e-12]);
nonlinearConvergenceProposed = ...
    standardizedStepRelativeNorm <= options.stepRelativeTolerance && ...
    totalCostRelativeChange <= options.costRelativeTolerance;
linearPrediction = linearizedIntercept + ...
    standardizedJacobian * selectedZ;
linearPredictionRelativeError = norm( ...
    selectedEvaluation.whitenedResidual - linearPrediction) / ...
    max([norm(selectedEvaluation.whitenedResidual), ...
    norm(linearPrediction), 1e-12]);
linearPredictionPassed = linearPredictionRelativeError <= ...
    options.stageDM3LinearPredictionRelativeTolerance;
refinedSchedule = selectedEvaluation.schedule;

history = table(1, baselineDataCost, exactDataCost(selectedIndex), NaN, ...
    requestedRetained, true, linearPredictionRelativeError, ...
    linearPredictionPassed, "full_prior_centered_tsvd_solution_applied", ...
    'VariableNames', {'iteration','data_cost_before','data_cost_after', ...
    'selected_lambda','selected_retained_singular_value_count', ...
    'full_update_applied','linear_prediction_relative_error', ...
    'linear_prediction_passed','stop_reason'});

retainedConditionNumber = ...
    singularValues(1) / singularValues(requestedRetained);
conditionNumber = singularValues(1) / singularValues(numericalRank);
relativeLower = (selectedTheta - lowerBound) ./ span;
relativeUpper = (upperBound - selectedTheta) ./ span;
finalMinimumMargin = min([relativeLower; relativeUpper]);
candidateReplayIdentity = struct2table(candidateRecords);

solve = struct();
solve.label = label;
solve.executed = true;
solve.parameterization = 'actual_execution_nodes';
solve.jacobianMethod = 'node_central_full';
solve.x = selectedTheta;
solve.initialX = linearizationPoint;
solve.priorCenterX = priorCenter;
solve.initialOffset = zeros(d, 1);
solve.offset = fullUpdate;
solve.fullRegularizedUpdate = fullUpdate;
solve.priorCenteredFullSolution = selectedTheta - priorCenter;
solve.fullUpdateAppliedWithoutGlobalScaling = true;
solve.globalAlphaUsed = false;
solve.lmDampingUsed = false;
solve.converged = false;
solve.stopReason = 'nonlinear_iteration_completed';
solve.iterationCount = 1;
solve.costInitial = initialTotalCost;
solve.costFinal = finalTotalCost;
solve.dataCostInitial = baselineDataCost;
solve.dataCostFinal = exactDataCost(selectedIndex);
solve.initialResidual = baselineEvaluation.whitenedResidual;
solve.initialDataResidual = baselineEvaluation.whitenedResidual;
solve.residual = selectedEvaluation.whitenedResidual;
solve.meta = struct('valid', selectedEvaluation.valid, ...
    'prediction', selectedEvaluation.prediction, ...
    'dataResidual', selectedEvaluation.whitenedResidual, ...
    'rawDataResidual', selectedEvaluation.rawResidual, ...
    'regularization', zeros(0, 1), ...
    'regularizationMethod', 'prior_centered_tsvd_direct_inverse', ...
    'schedule', refinedSchedule);
solve.initialJacobian = whitenedJacobian;
solve.initialDataJacobian = whitenedJacobian;
solve.jacobian = whitenedJacobian;
solve.rawDataJacobian = rawJacobian;
solve.dataJacobian = whitenedJacobian;
solve.whitenedDataJacobian = whitenedJacobian;
solve.parameterScaledJacobian = ...
    whitenedJacobian .* contract.priorSigma.';
solve.priorWhitenedJacobian = standardizedJacobian;
solve.scaledDataJacobian = standardizedJacobian;
solve.scaledJacobian = standardizedJacobian;
solve.singularValues = singularValues;
solve.dataSingularValues = singularValues;
solve.numericalRank = numericalRank;
solve.dataNumericalRank = numericalRank;
solve.conditionNumber = conditionNumber;
solve.dataConditionNumber = conditionNumber;
solve.regularizationMethod = 'prior_centered_tsvd_direct_inverse';
solve.tsvdStepMode = 'direct_inverse';
solve.parameterScale = contract.priorSigma;
solve.parameterCount = d;
solve.activeNodeCount = d;
solve.dataResidualCount = m;
solve.lowerBound = lowerBound;
solve.upperBound = upperBound;
solve.differenceStep = usedStep;
solve.differenceStepScale = options.stageDDifferenceStepScale;
solve.informationMatrixDimension = [d, d];
solve.requestedRetainedSingularValueCount = requestedRetained;
solve.retainedSingularValueCount = requestedRetained;
solve.truncatedSingularValueCount = d - requestedRetained;
solve.retainedConditionNumber = retainedConditionNumber;
solve.history = history;
solve.nodeContract = contract;
solve.nodeContractHash = contract.nodeContractHash;
solve.fixedAnchorTable = contract.fixedAnchorTable;
solve.perturbationAudit = perturbationAudit;
solve.stepStability = stepStability;
solve.stepStabilityPassed = all(stepStability.passed);
solve.priorCorrelation = priorCorrelation;
solve.priorCovariance = priorCovariance;
solve.priorCholLower = priorCholLower;
solve.priorGroupTable = priorGroupTable;
solve.regularizationCandidates = regularizationCandidates;
solve.regularizationSelectionCriterion = ...
    'user_configured_retained_rank_with_linearized_gcv_advisory';
solve.regularizationControlMode = 'user_configured_tsvd_rank';
solve.configuredRegularizationStrength = NaN;
solve.selectedRegularizationStrength = NaN;
solve.selectedRegularizationCandidateIndex = selectedIndex;
solve.gcvRecommendedRegularizationStrength = NaN;
solve.gcvRecommendedRegularizationCandidateIndex = gcvRecommendedIndex;
solve.selectedRetainedSingularValueCount = requestedRetained;
solve.gcvRecommendedRetainedSingularValueCount = ...
    retainedCount(gcvRecommendedIndex);
solve.boundedSolution = boundedSolution;
solve.linearPredictionCheck = struct( ...
    'predictedWhitenedResidual', linearPrediction, ...
    'exactWhitenedResidual', selectedEvaluation.whitenedResidual, ...
    'relativeResidualError', linearPredictionRelativeError, ...
    'relativeTolerance', options.stageDM3LinearPredictionRelativeTolerance, ...
    'passed', linearPredictionPassed, ...
    'usesIndependentFullDllCandidate', true, 'diagnosticOnly', true);
solve.nonlinearConvergence = struct( ...
    'standardizedStepRelativeNorm', standardizedStepRelativeNorm, ...
    'stepRelativeTolerance', options.stepRelativeTolerance, ...
    'totalObjectiveRelativeChange', totalCostRelativeChange, ...
    'objectiveRelativeTolerance', options.costRelativeTolerance, ...
    'totalObjectiveDecreased', finalTotalCost <= initialTotalCost, ...
    'proposedConverged', nonlinearConvergenceProposed, ...
    'evaluatedAfterFreshJacobian', true);
solve.candidateReplayIdentity = candidateReplayIdentity;
solve.replayAudit = struct( ...
    'minimumRequiredJacobianCandidateCount', 1 + 2 * d, ...
    'jacobianCandidateCount', 1 + sum( ...
    perturbationAudit.candidate_evaluation_count), ...
    'actualCandidateCount', height(candidateReplayIdentity), ...
    'pointReplayCount', sum(candidateReplayIdentity.point_replay_count), ...
    'solveAttemptCount', sum(candidateReplayIdentity.solve_attempt_count), ...
    'invalidPointCount', sum(candidateReplayIdentity.invalid_point_count), ...
    'cacheHitCount', sum(candidateReplayIdentity.cache_hit_count), ...
    'wallSeconds', sum(candidateReplayIdentity.wall_seconds), ...
    'batchSize', options.stageDM3BatchSize, ...
    'pauseCount', 0, 'resumeCount', 0, 'resumeSupported', false);
solve.minimumRelativeBoundMargin = finalMinimumMargin;
solve.atBound = finalMinimumMargin <= 1e-8;
solve.wallSeconds = toc(passTimer);
end

function [acceptedSchedule, acceptedPrediction, detail, direct] = ...
        local_guarded_stage_d_reanchor(baseSchedule, data, basePrediction, ...
        groups, parameters, weighting, route, engine, cfg, options)
if strcmp(options.stageDCoordinatePolicy,'diagnostic_outer')
    [acceptedSchedule,acceptedPrediction,detail,direct]= ...
        local_diagnostic_coordinate_update(baseSchedule,data,basePrediction, ...
        parameters,weighting,route,engine,cfg,options);
    return;
end
% 阶段D的纵向参数已经由全部工况联合估计。横坐标重锚定只能作为坐标
% 一致性更新，不能反过来显著破坏数据拟合。按从大到小的松弛系数尝试，
% 接受满足回放有效性和数据代价门限的最大步；全部失败则保留D1结果。
baseCost = local_prediction_data_cost(route, data, basePrediction, weighting);
factorList = options.stageDReanchorRelaxationFactors(:);
attemptRecord = repmat(struct('relaxation_factor', NaN, ...
    'replay_valid', false, 'data_cost', Inf, ...
    'relative_data_cost_increase', Inf, ...
    'max_normalized_coordinate_shift', NaN, ...
    'max_prior_scaled_coefficient_change', NaN, ...
    'point_replay_count', 0, 'solve_attempt_count', 0, ...
    'invalid_point_count', 0, 'wall_seconds', 0, ...
    'accepted', false), numel(factorList), 1);
attemptDetail = cell(numel(factorList), 1);

accepted = false;
acceptedSchedule = baseSchedule;
acceptedPrediction = basePrediction;
acceptedDirect = local_schedule_direct_inlet(baseSchedule);
acceptedCoefficientTable = table();
acceptedMaxCoefficientChange = 0;
acceptedMaxShift = 0;
acceptedFactor = 0;
attemptCount = 0;

for i = 1:numel(factorList)
    factor = factorList(i);
    attemptCount = i;
    [candidateSchedule, candidateDetail, candidateDirect] = ...
        local_reanchor_schedule(baseSchedule, data, basePrediction, ...
        groups, parameters, options, factor);
    replayTimer = tic;
    [candidatePrediction, candidateValid] = local_evaluate_dataset( ...
        route, engine, cfg, data, local_schedule_model(candidateSchedule), ...
        options);
    replayWallSeconds = toc(replayTimer);
    solveAttemptCount = height(data);
    if istable(candidatePrediction) && ismember( ...
            'np_branch_attempt_count', ...
            candidatePrediction.Properties.VariableNames)
        attempt = candidatePrediction.np_branch_attempt_count;
        attempt(~isfinite(attempt) | attempt < 1) = 1;
        solveAttemptCount = sum(attempt);
    end
    invalidPointCount = height(data);
    if istable(candidatePrediction) && ...
            ismember('valid', candidatePrediction.Properties.VariableNames)
        invalidPointCount = sum(~candidatePrediction.valid);
    end
    candidateCost = local_prediction_data_cost( ...
        route, data, candidatePrediction, weighting);
    relativeIncrease = (candidateCost - baseCost) / max(baseCost, eps);
    [maxCoefficientChange, coefficientTable] = ...
        local_schedule_query_change(baseSchedule, candidateSchedule, ...
        basePrediction, parameters);
    candidateAccepted = candidateValid && isfinite(candidateCost) && ...
        relativeIncrease <= options.stageDReanchorCostIncreaseTolerance;

    attemptRecord(i) = struct('relaxation_factor', factor, ...
        'replay_valid', logical(candidateValid), 'data_cost', candidateCost, ...
        'relative_data_cost_increase', relativeIncrease, ...
        'max_normalized_coordinate_shift', ...
            candidateDetail.maxNormalizedCoordinateShift, ...
        'max_prior_scaled_coefficient_change', maxCoefficientChange, ...
        'point_replay_count', height(data), ...
        'solve_attempt_count', solveAttemptCount, ...
        'invalid_point_count', invalidPointCount, ...
        'wall_seconds', replayWallSeconds, ...
        'accepted', logical(candidateAccepted));
    attemptDetail{i} = struct('reanchor', candidateDetail, ...
        'coefficientChangeTable', coefficientTable);

    if candidateAccepted
        accepted = true;
        acceptedSchedule = candidateSchedule;
        acceptedPrediction = candidatePrediction;
        acceptedDirect = candidateDirect;
        acceptedCoefficientTable = coefficientTable;
        acceptedMaxCoefficientChange = maxCoefficientChange;
        acceptedMaxShift = candidateDetail.maxNormalizedCoordinateShift;
        acceptedFactor = factor;
        break;
    end
end

attemptRecord = attemptRecord(1:attemptCount);
attemptDetail = attemptDetail(1:attemptCount);
if accepted
    finalCost = attemptRecord(end).data_cost;
    finalRelativeIncrease = attemptRecord(end).relative_data_cost_increase;
    rejectionReason = "";
else
    finalCost = baseCost;
    finalRelativeIncrease = 0;
    rejectionReason = "全部候选迁移步均超过数据代价增幅门限，保留D1曲线";
    warning('SHT:SteadyAdaptV2:StageDReanchorRejected', ...
        ['阶段D横坐标重锚定未通过回放验收门，已保留D1结果；' ...
         '最大允许数据代价增幅为%.3f%%。'], ...
        100 * options.stageDReanchorCostIncreaseTolerance);
end

detail = struct();
detail.accepted = accepted;
detail.appliedRelaxationFactor = acceptedFactor;
detail.dataCostBefore = baseCost;
detail.dataCostAfter = finalCost;
detail.relativeDataCostIncrease = finalRelativeIncrease;
detail.maxNormalizedCoordinateShift = acceptedMaxShift;
detail.maxPriorScaledCoefficientChange = acceptedMaxCoefficientChange;
detail.coefficientChangeTable = acceptedCoefficientTable;
detail.replayValid = true;
detail.attemptTable = struct2table(attemptRecord);
detail.replayAudit = struct('candidateCount', height(detail.attemptTable), ...
    'pointReplayCount', sum(detail.attemptTable.point_replay_count), ...
    'solveAttemptCount', sum(detail.attemptTable.solve_attempt_count), ...
    'invalidPointCount', sum(detail.attemptTable.invalid_point_count), ...
    'wallSeconds', sum(detail.attemptTable.wall_seconds));
detail.attemptDetail = attemptDetail;
detail.rejectionReason = rejectionReason;
detail.reanchorCount = local_optional_struct_scalar( ...
    acceptedSchedule, 'coordinateReanchorCount', 0);
direct = acceptedDirect;
end

function [schedule,detail,direct]=local_rebuild_evidence_coordinates( ...
        base,data,prediction,groups,parameters,options)
% C阶段允许依据修正模型重新自动选点；不重复B阶段参数优化。
schedule=base; membership=local_point_group_membership(data,groups);
maximum=0; [~,designRow]=max(data.Wf_mean);
for i=1:numel(base.healthEntries)
    e=base.healthEntries(i);
    if ~isfield(e,'nodeFormation') || isempty(fieldnames(e.nodeFormation)),continue;end
    if strcmp(options.stageCBurnerCoordinateSource,'group_corrected') && ...
            strcmp(e.axisName,'burner_inlet_corrected_mass_flow')
        % 该曲线已由本轮B组内修正模型的“坐标-系数”成对数据形成。
        % 不用尚未联合辨识的全局曲线回放坐标重新安放B常值；D阶段
        % 再依据其实际修正模型迁移已有节点，并继续联合辨识。
        continue;
    end
    x=prediction.(e.axisName); old=e.nodeFormation.pointCoordinates;
    formed=sht_identification_schedule_nodes('build',x,membership, ...
        e.nodeFormation.groupValues,e.pressureLoss,e.axisName,options);
    formed=local_fit_c_ordinates(formed,e.pressureLoss,e.lowerBound,e.upperBound,options);
    p=find(parameters.c_index==e.cIndex,1);
    tolerance=options.nodeMergeConflictSigmaMultiplier*parameters.prior_sigma_group(p);
    local_report_evidence_conflict(formed.nodeFormation,tolerance,e.name,data);
    maximum=max(maximum,max(abs(x-old))/max(max(old)-min(old),1e-12));
    e.xNodes=formed.xNodes;e.kNodes=min(max(formed.kNodes,e.lowerBound),e.upperBound);
    if e.pressureLoss,e.kNodes(1)=0;end
    e.nodeFormation=formed.nodeFormation;e.designCoordinate=x(designRow);
    for g=1:height(groups),e.groupCoordinates(g)=mean(x(membership==g));end
    schedule.healthEntries(i)=local_refresh_schedule_entry(e);
end
schedule.designHealth=local_schedule_design_health(schedule);
schedule.coordinateReanchorCount=local_optional_struct_scalar(base,'coordinateReanchorCount',0)+1;
detail=struct('maxNormalizedCoordinateShift',maximum,'automaticNodes',true, ...
    'groupConstantsRefit',false,'stage','C');
detail.burnerCoordinatePairsPreserved=strcmp( ...
    options.stageCBurnerCoordinateSource,'group_corrected');
direct=local_schedule_direct_inlet(schedule);
end

function [schedule,prediction,detail,direct]=local_diagnostic_coordinate_update( ...
        base,data,basePrediction,parameters,weighting,route,engine,cfg,options)
% 一次外层迁移：无代价门、无统一回缩。仅处理确实影响工作区间的
% 坐标漂移。迁移后必须执行D2；D1尚未收敛不构成迁移禁令。
schedule=base;prediction=basePrediction;candidate=base;
rows=repmat(struct('parameter',"",'interval_relative_shift',0, ...
    'uncovered_points',0,'outside_interval_fraction',0,'function_change',0, ...
    'order_conflict',false,'update_needed',false),numel(base.healthEntries),1);
anyMove=false;[~,designRow]=max(data.Wf_mean);
for i=1:numel(base.healthEntries)
    e=base.healthEntries(i);x=basePrediction.(e.axisName);
    m=sht_identification_schedule_nodes('move',e,x);
    need=m.changed && (m.maximumOutsideIntervalFraction>options.stageDCoordinateOutsideThreshold || ...
        m.maximumIntervalRelativeShift>options.stageDCoordinateIntervalThreshold);
    rows(i)=struct('parameter',string(e.name), ...
        'interval_relative_shift',m.maximumIntervalRelativeShift, ...
        'uncovered_points',m.uncoveredPointCount, ...
        'outside_interval_fraction',m.maximumOutsideIntervalFraction, ...
        'function_change',m.maximumFunctionChange, ...
        'order_conflict',m.orderConflict,'update_needed',need);
    if m.orderConflict
        warning('SHT:SteadyAdaptV2:CoordinateOrder', ...
            '%s运行坐标次序改变，保留原支撑网格并记录；不静默合并或换序。',e.name);
    elseif need
        e=m.entry;e.designCoordinate=x(designRow);
        candidate.healthEntries(i)=local_refresh_schedule_entry(e);anyMove=true;
    end
end
baseCost=local_prediction_data_cost(route,data,basePrediction,weighting);
detail=struct('accepted',false,'appliedRelaxationFactor',0, ...
    'dataCostBefore',baseCost,'dataCostAfter',baseCost,'relativeDataCostIncrease',0, ...
    'maxNormalizedCoordinateShift',max([rows.interval_relative_shift]), ...
    'maxPriorScaledCoefficientChange',0,'coefficientChangeTable',table(), ...
    'coordinateTable',struct2table(rows),'replayValid',true, ...
    'attemptTable',table(),'attemptDetail',{{}},'rejectionReason',"not_needed", ...
    'reanchorCount',local_optional_struct_scalar(base,'coordinateReanchorCount',0), ...
    'policy','diagnostic_outer','costGateUsed',false,'globalRelaxationUsed',false, ...
    'replayAudit',struct('candidateCount',0,'pointReplayCount',0, ...
    'solveAttemptCount',0,'invalidPointCount',0,'wallSeconds',0));
direct=local_schedule_direct_inlet(base);
if ~anyMove,return;end
candidate.designHealth=local_schedule_design_health(candidate);
timer=tic;
[p,valid]=local_evaluate_dataset(route,engine,cfg,data, ...
    local_schedule_model(candidate),options);
seconds=toc(timer);cost=local_prediction_data_cost(route,data,p,weighting);
[change,changeTable]=local_schedule_query_change(base,candidate,basePrediction,parameters);
detail.maxPriorScaledCoefficientChange=change;detail.coefficientChangeTable=changeTable;
detail.replayAudit=struct('candidateCount',1,'pointReplayCount',height(data), ...
    'solveAttemptCount',sum(max(1,p.np_branch_attempt_count)), ...
    'invalidPointCount',sum(~p.valid),'wallSeconds',seconds);
detail.attemptTable=table(valid,cost,(cost-baseCost)/max(baseCost,eps), ...
    'VariableNames',{'replay_valid','data_cost','relative_data_cost_increase'});
detail.candidateDataCost=cost;
if ~valid
    detail.rejectionReason="moved_grid_physical_replay_invalid";
    warning('SHT:SteadyAdaptV2:CoordinateReplay','新坐标初值存在物理回放失败，保留D1；未应用代价增幅门。');
    return;
end
schedule=candidate;prediction=p;detail.accepted=true;
detail.appliedRelaxationFactor=1;detail.dataCostAfter=cost;
detail.relativeDataCostIncrease=(cost-baseCost)/max(baseCost,eps);
detail.rejectionReason="";schedule.coordinateReanchorCount=detail.reanchorCount+1;
detail.reanchorCount=schedule.coordinateReanchorCount;
end

function direct = local_schedule_direct_inlet(schedule)
direct = struct();
if isfield(schedule, 'directInletPressureLoss') && ...
        isstruct(schedule.directInletPressureLoss)
    direct = schedule.directInletPressureLoss;
end
end

function [schedule, detail, direct] = local_reanchor_schedule( ...
        baseSchedule, data, referencePrediction, groups, parameters, ...
        options, relaxationFactor)
if options.adaptiveEvidenceNodes
    [schedule,detail,direct]=local_rebuild_evidence_coordinates( ...
        baseSchedule,data,referencePrediction,groups,parameters,options);
    return;
end
% 用当前修正模型的运行坐标重建调度横坐标。组成员及组内参数值保持
% 不变；这里只改变“该组参数值位于哪个物理坐标”，不重复执行B辨识。
if nargin < 7
    relaxationFactor = 1;
end
if ~isnumeric(relaxationFactor) || ~isscalar(relaxationFactor) || ...
        ~isfinite(relaxationFactor) || relaxationFactor <= 0 || ...
        relaxationFactor > 1
    error('SHT:SteadyAdaptV2:BadReanchorRelaxationFactor', ...
        '横坐标重锚定松弛系数必须是(0,1]内的有限标量。');
end
schedule = baseSchedule;
[~, designRow] = max(data.Wf_mean);
record = repmat(struct('parameter', "", 'c_index', NaN, ...
    'axis_name', "", 'max_coordinate_shift', NaN, ...
    'normalized_coordinate_shift', NaN, 'source_node_count', NaN, ...
    'merged_node_count', NaN, 'removed_node_count', NaN, ...
    'merge_threshold', NaN, 'conflict_count', NaN, ...
    'max_vertical_spread', NaN), 0, 1);

for p = 1:height(parameters)
    if ~parameters.scheduled(p)
        continue;
    end
    entryIndex = find([schedule.healthEntries.cIndex] == ...
        parameters.c_index(p), 1);
    if isempty(entryIndex)
        error('SHT:SteadyAdaptV2:MissingScheduleForReanchor', ...
            '横坐标重锚定缺少h%d调度函数。', parameters.c_index(p));
    end
    entry = schedule.healthEntries(entryIndex);
    if numel(entry.groupCoordinates) ~= height(groups)
        error('SHT:SteadyAdaptV2:BadReanchorGroupCoordinateCount', ...
            'h%d保存的组坐标数量%d与当前分组数%d不一致。', ...
            entry.cIndex, numel(entry.groupCoordinates), height(groups));
    end
    oldGroupX = entry.groupCoordinates(:);
    groupK = arrayfun(@(value) local_interp_clamp( ...
        entry.xNodes, entry.kNodes, value), oldGroupX);
    axisField = char(parameters.axis_name(p));
    if ~ismember(axisField, referencePrediction.Properties.VariableNames)
        error('SHT:SteadyAdaptV2:MissingReanchorAxis', ...
            '修正模型回放结果缺少横坐标字段%s。', axisField);
    end
    targetGroupX = zeros(height(groups), 1);
    for g = 1:height(groups)
        idx = local_group_row_indices(groups, g);
        targetGroupX(g) = mean(referencePrediction.(axisField)(idx));
    end
    newGroupX = oldGroupX + relaxationFactor * ...
        (targetGroupX - oldGroupX);
    conflictTolerance = options.nodeMergeConflictSigmaMultiplier * ...
        parameters.prior_sigma_group(p);
    [mergedX, mergedK, removedCount, mergeDetail] = ...
        local_merge_near_nodes(newGroupX, groupK, options, ...
        groups.point_count, parameters.name(p), conflictTolerance);
    if entry.pressureLoss
        entry.xNodes = [0; mergedX(:)];
        entry.kNodes = [0; mergedK(:)];
    else
        entry.xNodes = mergedX(:);
        entry.kNodes = mergedK(:);
    end
    entry.designCoordinate = entry.designCoordinate + relaxationFactor * ...
        (referencePrediction.(axisField)(designRow) - entry.designCoordinate);
    entry.mergedNodeCount = removedCount;
    entry.groupIds = string(groups.group_id);
    entry.groupCoordinates = newGroupX(:);
    entry.groupValues = groupK(:);
    entry.mergeDiagnostics = mergeDetail;
    entry = local_refresh_schedule_entry(entry);
    schedule.healthEntries(entryIndex) = entry;

    combinedSpan = max([oldGroupX; newGroupX]) - ...
        min([oldGroupX; newGroupX]);
    coordinateScale = max(combinedSpan, ...
        options.nodeMergeRelativeFloor * ...
        max(1, median(abs([oldGroupX; newGroupX]))));
    maxShift = max(abs(newGroupX - oldGroupX));
    r = struct('parameter', string(entry.name), ...
        'c_index', entry.cIndex, 'axis_name', string(entry.axisName), ...
        'max_coordinate_shift', maxShift, ...
        'normalized_coordinate_shift', maxShift / coordinateScale, ...
        'source_node_count', mergeDetail.sourceNodeCount, ...
        'merged_node_count', mergeDetail.mergedNodeCount, ...
        'removed_node_count', mergeDetail.removedNodeCount, ...
        'merge_threshold', mergeDetail.mergeThreshold, ...
        'conflict_count', mergeDetail.conflictCount, ...
        'max_vertical_spread', mergeDetail.maxVerticalSpread);
    record(end + 1, 1) = r; %#ok<AGROW>
end

direct = struct();
if options.inletBoundaryMode == 4 && ...
        ~options.estimateInletPressureLoss && ...
        any([schedule.healthEntries.cIndex] == 0)
    direct = local_build_direct_inlet_pressure_loss( ...
        data, referencePrediction, table(), table(), options);
    inletIndex = find([schedule.healthEntries.cIndex] == 0, 1);
    schedule.healthEntries(inletIndex) = direct.entry;
    schedule.directInletPressureLoss = direct;
end
schedule.coordinateReanchorCount = ...
    local_optional_struct_scalar(baseSchedule, 'coordinateReanchorCount', 0) + 1;
schedule.designHealth = local_schedule_design_health(schedule);
if isempty(record)
    detail.entryTable = table();
    detail.maxNormalizedCoordinateShift = 0;
else
    detail.entryTable = struct2table(record);
    detail.maxNormalizedCoordinateShift = ...
        max(detail.entryTable.normalized_coordinate_shift);
end
detail.reanchorCount = schedule.coordinateReanchorCount;
detail.relaxationFactor = relaxationFactor;
end

function value = local_optional_struct_scalar(source, name, defaultValue)
if isfield(source, name) && isscalar(source.(name)) && ...
        isfinite(source.(name))
    value = source.(name);
else
    value = defaultValue;
end
end

function cost = local_prediction_data_cost(route, data, prediction, weighting)
if isempty(prediction) || ~ismember('valid', prediction.Properties.VariableNames) || ...
        ~all(prediction.valid)
    cost = Inf;
    return;
end
residual = local_data_residual(route, data, prediction, weighting);
if any(~isfinite(residual))
    cost = Inf;
else
    cost = 0.5 * sum(residual(:) .^ 2);
end
end

function [maxScaledChange, detailTable] = local_schedule_query_change( ...
        oldSchedule, newSchedule, prediction, parameters)
record = repmat(struct('parameter', "", 'c_index', NaN, ...
    'max_absolute_change', NaN, 'prior_scale', NaN, ...
    'prior_scaled_change', NaN), 0, 1);
for i = 1:numel(newSchedule.healthEntries)
    newEntry = newSchedule.healthEntries(i);
    oldIndex = find([oldSchedule.healthEntries.cIndex] == ...
        newEntry.cIndex, 1);
    if isempty(oldIndex) || ...
            ~ismember(newEntry.axisName, prediction.Properties.VariableNames)
        continue;
    end
    oldEntry = oldSchedule.healthEntries(oldIndex);
    query = prediction.(newEntry.axisName);
    oldValue = arrayfun(@(x) local_interp_clamp( ...
        oldEntry.xNodes, oldEntry.kNodes, x), query);
    newValue = arrayfun(@(x) local_interp_clamp( ...
        newEntry.xNodes, newEntry.kNodes, x), query);
    maxChange = max(abs(newValue - oldValue));
    parameterRow = find(parameters.c_index == newEntry.cIndex, 1);
    if isempty(parameterRow)
        priorScale = 0.012;
    else
        priorScale = parameters.prior_sigma_group(parameterRow);
    end
    r = struct('parameter', string(newEntry.name), ...
        'c_index', newEntry.cIndex, 'max_absolute_change', maxChange, ...
        'prior_scale', priorScale, ...
        'prior_scaled_change', maxChange / max(priorScale, eps));
    record(end + 1, 1) = r; %#ok<AGROW>
end
if isempty(record)
    detailTable = table();
    maxScaledChange = 0;
else
    detailTable = struct2table(record);
    maxScaledChange = max(detailTable.prior_scaled_change);
end
end

function value = local_interp_clamp(x, y, query)
x = x(:);
y = y(:);
if numel(x) == 1
    value = y(1);
    return;
end
query = min(max(query, x(1)), x(end));
value = interp1(x, y, query, 'linear');
end

function [prediction, allValid, diagnostic] = local_evaluate_dataset( ...
        route, engine, cfg, data, model, options, initialSeedMatrix)
variableCount=6+3*double(cfg.engine.modelMode==1);
% 一次候选参数对应的调度表只初始化一次，随后对所有工况重复查询。
if nargin < 7 || isempty(initialSeedMatrix)
    initialSeedMatrix = [];
else
    if ~isnumeric(initialSeedMatrix) || ...
            ~isequal(size(initialSeedMatrix), [height(data), variableCount]) || ...
            any(~isfinite(initialSeedMatrix(:)))
        error('SHT:SteadyAdaptV2:BadInitialSeedMatrix', ...
            '外部共同工作初值必须为测试点数x9的有限矩阵。');
    end
end
if strcmp(model.kind, 'schedule')
    local_configure_dll_schedule(engine, model.schedule);
else
    local_disable_dll_schedule(engine);
end

records = repmat(local_empty_prediction_record(), height(data), 1);
diagnostic = local_empty_dataset_diagnostic(height(data),variableCount);
allValid = true;
for i = 1:height(data)
    try
        seedOverride = [];
        if ~isempty(initialSeedMatrix)
            seedOverride = initialSeedMatrix(i, :).';
        end
        [records(i), pointDiagnostic] = local_evaluate_point( ...
            route, engine, cfg, data(i, :), model, options, seedOverride);
        diagnostic.baseSeed(i, :) = pointDiagnostic.baseSeed;
        diagnostic.initialSeed(i, :) = pointDiagnostic.initialSeed;
        diagnostic.solutionSeed(i, :) = pointDiagnostic.solutionSeed;
        diagnostic.seedSource(i) = pointDiagnostic.seedSource;
        diagnostic.solutionAvailable(i) = ...
            pointDiagnostic.solutionAvailable;
        diagnostic.branchAttemptCount(i) = ...
            pointDiagnostic.branchAttemptCount;
        diagnostic.branchSelectedAttempt(i) = ...
            pointDiagnostic.branchSelectedAttempt;
        diagnostic.branchPassed(i) = pointDiagnostic.branchPassed;
        diagnostic.branchSelectedNpRpm(i) = ...
            pointDiagnostic.branchSelectedNpRpm;
        diagnostic.branchSelectedRelativeDistance(i) = ...
            pointDiagnostic.branchSelectedRelativeDistance;
        diagnostic.gaspathSeedPrepared(i) = ...
            pointDiagnostic.gaspathSeedPrepared;
        diagnostic.gaspathSeedRobustFallbackUsed(i) = ...
            pointDiagnostic.gaspathSeedRobustFallbackUsed;
        diagnostic.gaspathSeedMaxResidual(i) = ...
            pointDiagnostic.gaspathSeedMaxResidual;
        diagnostic.branchRootTable{i} = pointDiagnostic.branchRootTable;
    catch evaluationError
        records(i) = local_empty_prediction_record();
        records(i).point_id = data.point_id(i);
        records(i).valid = false;
        records(i).error_message = string(evaluationError.message);
    end
    allValid = allValid && records(i).valid;
end
prediction = struct2table(records);
end

function [record, diagnostic] = local_evaluate_point( ...
        route, engine, cfg, point, model, options, seedOverride)
if nargin < 7
    seedOverride = [];
end
variableCount=6+3*double(cfg.engine.modelMode==1);
gasCount=variableCount-2;
diagnostic = local_empty_point_diagnostic(variableCount);
npMeasured = point.Np_mean(1);
ngMeasured = point.Ng_mean(1);
[npBranchActive, npBranch] = local_np_branch_from_point( ...
    route, point, options);
npSolver = npMeasured;
if npBranchActive
    npSolver = npBranch.centerRpm;
end
wfInput = point.Wf_mean(1);
if strcmp(model.kind, 'schedule')
    xFuel = wfInput / model.schedule.fuelBias.wfDesign;
    fuelBias = local_interp_clamp(model.schedule.fuelBias.xNodes, ...
        model.schedule.fuelBias.biasNodes, xFuel);
    health = model.schedule.designHealth;
    scheduleEnabled = true;
else
    fuelBias = model.fuelBias;
    health = model.health;
    scheduleEnabled = false;
end
if strcmp(options.fuelInputSemantics, 'physical_model')
    fuelBias = 0;
end
wfModel = wfInput - fuelBias;
if ~isfinite(wfModel) || wfModel <= 0
    error('SHT:SteadyAdaptV2:NonPositiveFuel', ...
        '工况%s的燃油偏置使模型燃油流量非正。', char(point.point_id));
end

% 功率用于初值和诊断。旧接口传功率；原生扭矩接口直接传Mkp/Mkg，
% 由DLL按每次候选转速换算。两种扭矩实现采用同一物理负载关系。
ptLoadPower = point.Mkp_mean(1) * pi * npSolver / 30;
gtLoadPower = point.Mkg_mean(1) * pi * ngMeasured / 30;
if strcmp(route,'steady') && options.steadyUseMeasuredPower
    assert(ismember('Pshaft_mean',point.Properties.VariableNames), ...
        'SHT:SteadyAdaptV2:MissingMeasuredPower','稳态功率边界要求测量Pshaft_mean（W）。');
    ptLoadPower=point.Pshaft_mean(1);
    assert(isfinite(ptLoadPower) && ptLoadPower>=0, ...
        'SHT:SteadyAdaptV2:BadMeasuredPower','测量PT轴功率必须为有限非负值。');
    % 本轮GT附件无功率提取；不能把未知Ng或PT输出用于构造附件功率。
    assert(point.Mkg_mean(1)==0,'SHT:SteadyAdaptV2:AccessoryPower', ...
        '当前TC24固定功率合同仅支持Mkg=0；非零附件需明确独立功率输入。');
    gtLoadPower=0;
end
stepInValue = zeros(cfg.engine.interface.stepInLength, 1);
stepInValue(1:10) = [npSolver; ngMeasured; wfModel; ...
    cfg.engine.boundary.A8; 0; ptLoadPower; gtLoadPower; 0; ...
    cfg.engine.boundary.hpcAlpha; 0];
if options.shaftLoadInputMode==1
    stepInValue(6:8)=[point.Mkp_mean(1);point.Mkg_mean(1);1];
end
% 旧显式背压接口仅保留给确有背压边界的调用方，3.3不再生成该列。
if ismember('Pback_mean',point.Properties.VariableNames)
    pback=point.Pback_mean(1);
    if ~isnumeric(pback) || ~isreal(pback) || ~isscalar(pback) || ...
            ~isfinite(pback) || pback<=0
        error('SHT:SteadyAdaptV2:BadPointBackpressure', ...
            'Pback_mean必须为有限正的排气绝对压力（Pa）。');
    end
    stepInValue(10)=pback;
end
backpressureModel=[];
if isfield(cfg.engine,'exhaustBackPressureModel')
    if ismember('Pback_mean',point.Properties.VariableNames)
        error('SHT:SteadyAdaptV2:ConflictingBackpressure', ...
            '模型计算背压与外部Pback_mean不能同时提供。');
    end
    backpressureModel=cfg.engine.exhaustBackPressureModel;
    backpressureModel.ambientPressure_Pa=point.Pamb_mean(1);
    stepInValue(10)=sht_exhaust_backpressure( ...
        point.Pamb_mean(1),ptLoadPower,backpressureModel);
end
if options.inletBoundaryMode == 1
    % 受控方法对照：Pt1使用替代数据真值，Tt1仍使用试车
    % 测量均值。该路径不是真实数据可部署方案，只用于判断边界
    % 重构方式对参数辨识的影响。
    if options.modelMode==0
        pt1Input=point.Pt1_mean(1);
    elseif ~ismember('Pt1_truth', point.Properties.VariableNames)
        error('SHT:SteadyAdaptV2:MissingPt1Truth', ...
            '模式1对照缺少Pt1_truth。');
    else
        pt1Input=point.Pt1_truth(1);
    end
    inletBoundary = struct( ...
        'inletBoundaryMode', 1, ...
        'altitude', point.Altitude_mean(1), ...
        'Mach', point.Mach_mean(1), ...
        'deltaTemperature', 0, ...
        'Pt1', pt1Input, ...
        'Tt1', point.Tt1_mean(1), ...
        'Pamb', point.Pamb_mean(1));
elseif options.inletBoundaryMode == 2
    % 模式2：预测入口只给Pamb/Tamb/Mach，DLL重构Pt1和Tt1，再由
    % 进口部件计算Pt2。高度只作为可选元数据，不参与重复环境计算。
    inletBoundary = struct( ...
        'inletBoundaryMode', 2, ...
        'altitude', point.Altitude_mean(1), ...
        'Mach', point.Mach_mean(1), ...
        'deltaTemperature', 0, ...
        'Pamb', point.Pamb_mean(1), ...
        'Tamb', point.Tamb_mean(1));
elseif options.inletBoundaryMode == 3
    % 模式3只用于无测量数据预测：逐点给定高度、Mach和静温，DLL
    % 复用标准大气模型计算Pamb，再重构Pt1/Tt1。
    inletBoundary = struct( ...
        'inletBoundaryMode', 3, ...
        'altitude', point.Altitude_mean(1), ...
        'Mach', point.Mach_mean(1), ...
        'deltaTemperature', 0, ...
        'Tamb', point.Tamb_mean(1));
elseif options.inletBoundaryMode == 4
    % 模式4：仍由环境边界重构内部Pt1，直接以实测Pt2作为AC入口
    % 压力。进气道压损由C程序按原始压损方程反算，不参与联合估计。
    inletBoundary = struct( ...
        'inletBoundaryMode', 4, ...
        'altitude', point.Altitude_mean(1), ...
        'Mach', point.Mach_mean(1), ...
        'deltaTemperature', 0, ...
        'Pamb', point.Pamb_mean(1), ...
        'Tamb', point.Tamb_mean(1), ...
        'Tt1', point.Tt1_mean(1), ...
        'Pt2', point.Pt2_mean(1));
else
    % 模式5：稀疏飞参回放只提供实测Ps0、Mach、Ts_amb与Tt1。
    % C程序统一重构Pt0/Pt1；Pt3_eq只作为输出观测，绝不回灌入口。
    inletBoundary = struct( ...
        'inletBoundaryMode', 5, ...
        'altitude', point.Altitude_mean(1), ...
        'Mach', point.Mach_mean(1), ...
        'deltaTemperature', 0, ...
        'Ps0', point.Pamb_mean(1), ...
        'Ts_amb', point.Tamb_mean(1), ...
        'Tt1', point.Tt1_mean(1), ...
        'inletTotalPressureRecovery', ...
        point.inlet_pressure_recovery_mean(1));
end
[stepInValue, inletBoundaryDetail] = ...
    sht_apply_inlet_boundary_stepin(stepInValue, inletBoundary);
if options.inletBoundaryMode == 1
    assert(inletBoundaryDetail.mode == 1 && ...
        inletBoundaryDetail.directPt1InputUsed && ...
        ~inletBoundaryDetail.pt2InputUsed && ...
        stepInValue(14) == pt1Input, ...
        'Pt1真值对照的模式1边界契约被破坏。');
elseif options.inletBoundaryMode == 2
    assert(inletBoundaryDetail.mode == 2 && ...
        ~inletBoundaryDetail.directPt1InputUsed && ...
        ~inletBoundaryDetail.measuredTt1InputUsed && ...
        ~inletBoundaryDetail.pt2InputUsed && stepInValue(14) == 0 && ...
        stepInValue(15) == 0, ...
        '模式2预测契约被破坏：Pt1、Tt1和Pt2均应由DLL内部重构。');
elseif options.inletBoundaryMode == 3
    assert(inletBoundaryDetail.mode == 3 && ...
        ~inletBoundaryDetail.directPt1InputUsed && ...
        ~inletBoundaryDetail.measuredTt1InputUsed && ...
        ~inletBoundaryDetail.pt2InputUsed && ...
        inletBoundaryDetail.altitudeAtmosphereUsed && ...
        all(stepInValue(14:16) == 0) && ...
        stepInValue(19) == point.Tamb_mean(1), ...
        '模式3预测契约被破坏：仅允许高度、Mach和静温进入环境重构。');
elseif options.inletBoundaryMode == 4
    assert(inletBoundaryDetail.mode == 4 && ...
        ~inletBoundaryDetail.directPt1InputUsed && ...
        inletBoundaryDetail.pt2InputUsed && ...
        stepInValue(14) == point.Pt2_mean(1), ...
        '模式4辨识回放契约被破坏：stepIn(14)必须为实测Pt2。');
else
    assert(inletBoundaryDetail.mode == 5 && ...
        ~inletBoundaryDetail.directPt1InputUsed && ...
        ~inletBoundaryDetail.pt2InputUsed && ...
        inletBoundaryDetail.measuredTt1InputUsed && ...
        inletBoundaryDetail.measuredStaticPressureReplayUsed && ...
        stepInValue(14) == 0 && ...
        stepInValue(15) == point.Tt1_mean(1) && ...
        stepInValue(16) == point.Pamb_mean(1), ...
        '模式5飞参回放契约被破坏：不得把Pt3_eq或Pt2作为入口输入。');
end
stepInValue(cfg.engine.interface.healthScheduleEnableIndex) = ...
    double(scheduleEnabled);
healthStart = cfg.engine.interface.healthStartIndex;
stepInValue(healthStart:(healthStart + numel(health) - 1)) = health(:);

if isempty(seedOverride)
    seed = local_initial_common_variable_seed( ...
        cfg, ptLoadPower, npSolver, ngMeasured);
    diagnostic.seedSource = "configured_initial_guess";
else
    seed = seedOverride(:);
    if numel(seed) ~= variableCount || any(~isfinite(seed))
        error('SHT:SteadyAdaptV2:BadPointInitialSeed', ...
            '工况%s的外部共同工作初值必须为有限9维向量。', ...
            char(point.point_id));
    end
    diagnostic.seedSource = "external_common_work_seed";
end
if npBranchActive && isempty(seedOverride)
    [seed, gaspathSeed] = local_prepare_branch_gaspath_seed( ...
        engine, cfg, stepInValue, seed, options);
    diagnostic.seedSource = gaspathSeed.source;
    diagnostic.gaspathSeedPrepared = gaspathSeed.prepared;
    diagnostic.gaspathSeedRobustFallbackUsed = ...
        gaspathSeed.robustFallbackUsed;
    diagnostic.gaspathSeedMaxResidual = gaspathSeed.maxResidual;
elseif npBranchActive
    diagnostic.gaspathSeedPrepared = true;
    diagnostic.gaspathSeedRobustFallbackUsed = false;
    diagnostic.gaspathSeedMaxResidual = NaN;
end
diagnostic.baseSeed = seed(:).';
selectionPolicy=options.steadyNpSelectionPolicy;
if npBranchActive && ~isempty(seedOverride) && ...
        isfield(options,'steadyPerturbationSameBranch') && options.steadyPerturbationSameBranch
    % 求导必须沿中心解的同一局部解支。参考是模型解，不是额外观测；
    % 仍求解全部共同工作变量，不固定Np，不改变功率边界。
    center=seed(end-1);halfWidth=options.stageDSteadyLocalBranchHalfWidth;
    assert(center>=npBranch.lowerRpm && center<=npBranch.upperRpm, ...
        'SHT:SteadyAdaptV2:DerivativeCenterOutsideNpBranch', ...
        'Jacobian中心根Np=%.6f rpm未通过原工况分支范围，禁止据此另建局部分支。',center);
    npBranch.lowerRpm=max(npBranch.lowerRpm,center*(1-halfWidth));
    npBranch.upperRpm=min(npBranch.upperRpm,center*(1+halfWidth));
    npBranch.centerRpm=center;
    npBranch.relativeHalfWidth=min([halfWidth,1-npBranch.lowerRpm/center, ...
        npBranch.upperRpm/center-1]);
    npBranch.referenceUsesPointNp=false;
    npBranch.localContinuation=true;
end
diagnostic.initialSeed = seed(:).';
local_set_dll_seed(engine, cfg, seed);
robustFallbackUsed = false;
npBranchPassed = true;
npBranchReason = "not_applied";
if strcmp(route, 'steady')
    if npBranchActive
        branchSolve = sht_solve_steady_np_branch( ...
            engine, cfg, stepInValue, seed, point.Mkp_mean(1), ...
            point.Mkg_mean(1), npBranch, struct( ...
            'strictResidual', options.steadyNpBranchStrictResidual, ...
            'enableAdaptiveRetry', options.steadyNpBranchAdaptiveRetry, ...
            'exhaustBackPressureModel',backpressureModel, ...
            'loadBoundary',options.steadyLoadBoundaryMode,'solver',options.steadySolver, ...
            'selectionPolicy',selectionPolicy, ...
            'allowOutsidePreference',options.steadyUseMeasuredPower && ...
                npBranch.referenceUsesPointNp && strcmp(model.kind,'constant') && ...
                options.steadyNpAllowOutsideConstantInitialization));
        fallback = branchSolve.selectedSolve;
        ret = fallback.ret;
        eng = fallback.engOut.eng;
        diagnostic.initialSeed = branchSolve.selectedSeed(:).';
        diagnostic.branchRootTable = branchSolve.rootTable;
        diagnostic.branchAttemptCount = branchSolve.attemptCount;
        diagnostic.branchSelectedAttempt = branchSolve.selectedAttempt;
        diagnostic.branchPassed = branchSolve.branchConstraintPassed;
        diagnostic.branchSelectedNpRpm = branchSolve.selectedNpRpm;
        diagnostic.branchSelectedRelativeDistance = ...
            branchSolve.selectedRelativeDistance;
        npBranchPassed = branchSolve.passed;
        npBranchReason = branchSolve.reason;
    elseif strcmp(options.steadyLoadBoundaryMode, 'torque')
        % Mkp/Mkg是外部负载扭矩。把功率换算放入共同工作残差计算，
        % 避免用未知测试转速预先固定轴功率并诱发错误稳态分支。
        fallback = sht_solve_steady_components_from_seed( ...
            engine, cfg, stepInValue, seed, struct( ...
            'ptLoadTorqueNm', point.Mkp_mean(1), ...
            'gtLoadTorqueNm', point.Mkg_mean(1), ...
            'exhaustBackPressureModel',backpressureModel));
        ret = fallback.ret;
        eng = fallback.engOut.eng;
    elseif strcmp(options.steadySolver,'matlab') || ~isempty(backpressureModel)
        fallback=sht_solve_steady_components_from_seed(engine,cfg,stepInValue,seed, ...
            struct('exhaustBackPressureModel',backpressureModel));
        ret=fallback.ret;eng=fallback.engOut.eng;
    else
        [ret, ~, eng] = local_call_one_point( ...
            engine, cfg, stepInValue);
        % C内置Newton失败时才启用指定分支的阻尼求解器，正常工况不增加开销。
        initialResidual = local_engine_max_residual(eng);
        if ret ~= 0 || eng.convergeTag ~= 0 || ...
                ~isfinite(initialResidual) || ...
                initialResidual > options.maxModelResidual
            fallback = sht_solve_steady_components_from_seed( ...
                engine, cfg, stepInValue, seed);
            ret = fallback.ret;
            eng = fallback.engOut.eng;
        end
    end
    dNpDt = NaN;
    dNgDt = NaN;
else
    [ret, stepOutValue, eng] = local_call_one_step( ...
        engine, cfg, stepInValue);
    initialResidual = local_engine_max_residual(eng);
    if options.useRobustTransientFallback && ...
            (ret ~= 0 || eng.convergeTag ~= 0 || ...
            ~isfinite(initialResidual) || ...
            initialResidual > options.maxModelResidual)
        fallback = sht_solve_transient_components_from_seed( ...
            engine, cfg, stepInValue, seed(1:gasCount));
        ret = fallback.ret;
        eng = fallback.engOut.eng;
        stepOutValue = fallback.stepOut;
        robustFallbackUsed = true;
    end
    dNpDt = stepOutValue(1);
    dNgDt = stepOutValue(2);
    if robustFallbackUsed
        % DLL_SHT_RunTransientComponents的前7项为共同工作残差，随后两项
        % 才是两轴导数；RunOneStep则直接把导数写在前两项。
        dNpDt = stepOutValue(gasCount+1);
        dNgDt = stepOutValue(gasCount+2);
    end
end

maxResidual = local_engine_max_residual(eng);
record = local_empty_prediction_record();
record.point_id = point.point_id(1);
record.return_code = ret;
record.converge_tag = double(eng.convergeTag);
record.max_model_residual = maxResidual;
record.robust_transient_fallback_used = robustFallbackUsed;
record.wf_measured = wfInput;
record.wf_bias = fuelBias;
record.wf_model = wfModel;
record.Np = double(eng.LPS_Nmech);
record.Ng = double(eng.HPS_Nmech);
if options.shaftLoadInputMode==1
    ptLoadPower=double(eng.LPS_Power);gtLoadPower=double(eng.HPS_Power);
end
record.pt_load_power_input_W=ptLoadPower;
record.gt_load_power_input_W=gtLoadPower;
if strcmp(route,'steady') && npBranchActive
    record.dll_one_point_calls=branchSolve.dllCallCount;
    record.matlab_steady_calls=branchSolve.matlabCallCount;
    record.outside_np_preference_admitted=branchSolve.outsidePreferenceAdmitted;
end
record.Pback = stepInValue(10);
if record.Pback==0,record.Pback=double(eng.Ambient.y(5));end
if ~isempty(backpressureModel)
    record.Pback=sht_exhaust_backpressure(point.Pamb_mean(1), ...
        point.Mkp_mean(1)*pi*record.Np/30,backpressureModel);
end
record.np_branch_active = npBranchActive;
if npBranchActive
    record.np_branch_center_rpm = npBranch.centerRpm;
    record.np_branch_lower_rpm = npBranch.lowerRpm;
    record.np_branch_upper_rpm = npBranch.upperRpm;
    record.np_branch_selected_attempt = diagnostic.branchSelectedAttempt;
    record.np_branch_attempt_count = diagnostic.branchAttemptCount;
    record.np_branch_selected_relative_distance = ...
        diagnostic.branchSelectedRelativeDistance;
    record.np_branch_passed = branchSolve.branchConstraintPassed;
    record.np_branch_source = npBranch.source;
    record.np_branch_reference_uses_point_Np = ...
        npBranch.referenceUsesPointNp;
end
if options.inletBoundaryMode == 1
    record.Pt1_boundary_input = pt1Input;
end
record.Pt1_internal = double(eng.Ambient.gasPathOut(4));
record.Tt1 = double(eng.Ambient.gasPathOut(3));
record.Pamb = double(eng.Ambient.y(5));
record.Tamb = double(eng.Ambient.y(6));
record.Pt2 = double(eng.Inlet.gasPathOut(4));
if ismember('Pt2_mean',point.Properties.VariableNames)
    record.Pt2_measured = point.Pt2_mean(1);
end
record.inlet_boundary_mode = inletBoundaryDetail.mode;
record.direct_pt1_input_used = inletBoundaryDetail.directPt1InputUsed;
record.pt2_input_used = inletBoundaryDetail.pt2InputUsed;
record.inlet_nominal_loss = ...
    double(eng.Inlet.pressureLossModel.lastNominalLoss);
record.inlet_pressure_loss_correction = ...
    double(eng.Inlet.pressureLossModel.lastCorrectionLoss);
record.inlet_total_loss = ...
    double(eng.Inlet.pressureLossModel.lastTotalLoss);
recoveryDenominator = record.Pt1_internal * ...
    (1 - record.inlet_total_loss);
if isfinite(recoveryDenominator) && recoveryDenominator > 0
    record.inlet_ram_recovery = record.Pt2 / recoveryDenominator;
end
if cfg.engine.modelMode==0
    compressor=eng.HPC;gt=eng.HPT;pt=eng.LPT;
else
    compressor=eng.HPC2;gt=eng.HPT2;pt=eng.LPT2;
end
record.Pt3 = double(compressor.y(4));
record.Tt3 = double(compressor.y(3));
record.Tt45 = double(gt.y(3));
record.Pt45 = double(gt.y(4));
record.Ptb3=record.Pt3;record.Ttb3=record.Tt3;
record.Pt6=double(pt.y(4));record.Tt6=double(pt.y(3));
record.Wa2=double(eng.Inlet.gasPathOut(1));
record.dNp_dt = dNpDt;
record.dNg_dt = dNgDt;
record.inlet_corrected_mass_flow = local_corrected_flow( ...
    eng.Ambient.gasPathOut);
record.burner_inlet_corrected_mass_flow = local_corrected_flow( ...
    compressor.y);
record.gt_pt_duct_corrected_mass_flow = local_corrected_flow( ...
    gt.y);
record.pt_nozzle_duct_corrected_mass_flow = local_corrected_flow( ...
    pt.y);
record.ac_corrected_speed = double(eng.HPC.y(16));
% 六部件模式下HPC2对应离心压气机（CC）。该量只作为调度坐标诊断
% 输出，不进入残差，也不改变既有稳态/瞬态求解方程。三部件兼容结构
% 若没有完整HPC2输出，则退回AC坐标，避免破坏历史调用。
if isfield(eng,'HPC2') && isfield(eng.HPC2,'y') && numel(eng.HPC2.y) >= 16
    record.cc_corrected_speed = double(eng.HPC2.y(16));
else
    record.cc_corrected_speed = record.ac_corrected_speed;
end
varIte = double(eng.varIte(:));
if cfg.engine.modelMode==0
    record.gt_total_pressure_ratio=double(eng.HPT_PRin);
    record.pt_total_pressure_ratio=double(eng.LPT_PRin);
elseif numel(varIte) >= 7
    record.gt_total_pressure_ratio = varIte(4) * varIte(5);
    record.pt_total_pressure_ratio = varIte(6) * varIte(7);
end
% convergeTag保留为求解器诊断，但不单独否决候选。部分工况会在达到
% 迭代停止条件时返回tag=1，而共同工作残差已经远低于验收门限。
record.valid = ret == 0 && ...
    isfinite(maxResidual) && maxResidual <= options.maxModelResidual && ...
    all(isfinite([record.Np, record.Ng, record.Pamb, record.Tamb, ...
    record.Tt1, record.Pt2, record.Pt3, record.Tt3, ...
    record.Tt45, record.Pt45]));
if npBranchActive
    record.valid = record.valid && npBranchPassed;
end
if strcmp(route, 'transient_instant')
    record.valid = record.valid && all(isfinite([dNpDt, dNgDt]));
end
if ~record.valid
    record.error_message = string(sprintf( ...
        'ret=%d, tag=%g, maxResidual=%.6g, npBranch=%s', ...
        ret, record.converge_tag, maxResidual, char(npBranchReason)));
end

solutionSeed = double(eng.varIte(:));
if strcmp(route, 'transient_instant')
    % 瞬态模型只求解前7个气路共同工作变量；两轴转速是已测状态输入，
    % 因此构造后续稳态初值时必须显式补回当前测试点Np/Ng。
    solutionSeed = [solutionSeed(1:gasCount); npMeasured; ngMeasured];
else
    solutionSeed = solutionSeed(1:variableCount);
end
diagnostic.solutionSeed = solutionSeed(:).';
diagnostic.solutionAvailable = record.valid && ...
    all(isfinite(solutionSeed));
end

function diagnostic = local_empty_dataset_diagnostic(pointCount,variableCount)
diagnostic = struct( ...
    'baseSeed', nan(pointCount, variableCount), ...
    'initialSeed', nan(pointCount, variableCount), ...
    'solutionSeed', nan(pointCount, variableCount), ...
    'seedSource', strings(pointCount, 1), ...
    'solutionAvailable', false(pointCount, 1), ...
    'branchAttemptCount', zeros(pointCount, 1), ...
    'branchSelectedAttempt', nan(pointCount, 1), ...
    'branchPassed', false(pointCount, 1), ...
    'branchSelectedNpRpm', nan(pointCount, 1), ...
    'branchSelectedRelativeDistance', nan(pointCount, 1), ...
    'gaspathSeedPrepared', false(pointCount, 1), ...
    'gaspathSeedRobustFallbackUsed', false(pointCount, 1), ...
    'gaspathSeedMaxResidual', nan(pointCount, 1), ...
    'branchRootTable', {cell(pointCount, 1)});
end

function diagnostic = local_empty_point_diagnostic(variableCount)
diagnostic = struct('baseSeed', nan(1, variableCount), ...
    'initialSeed', nan(1, variableCount), ...
    'solutionSeed', nan(1, variableCount), 'seedSource', "", ...
    'solutionAvailable', false, 'branchAttemptCount', 0, ...
    'branchSelectedAttempt', NaN, 'branchPassed', false, ...
    'branchSelectedNpRpm', NaN, ...
    'branchSelectedRelativeDistance', NaN, ...
    'gaspathSeedPrepared', false, ...
    'gaspathSeedRobustFallbackUsed', false, ...
    'gaspathSeedMaxResidual', NaN, ...
    'branchRootTable', table());
end

function record = local_empty_prediction_record()
record = struct('point_id', "", 'return_code', NaN, ...
    'converge_tag', NaN, 'max_model_residual', NaN, ...
    'robust_transient_fallback_used', false, ...
    'pt_load_power_input_W',NaN,'gt_load_power_input_W',NaN, ...
    'dll_one_point_calls',0,'matlab_steady_calls',0, ...
    'outside_np_preference_admitted',false, ...
    'wf_measured', NaN, 'wf_bias', NaN, 'wf_model', NaN, ...
    'Np', NaN, 'Ng', NaN, 'Pback', NaN, 'Pt1_boundary_input', NaN, ...
    'np_branch_active', false, 'np_branch_center_rpm', NaN, ...
    'np_branch_lower_rpm', NaN, 'np_branch_upper_rpm', NaN, ...
    'np_branch_selected_attempt', NaN, ...
    'np_branch_attempt_count', 0, ...
    'np_branch_selected_relative_distance', NaN, ...
    'np_branch_passed', false, 'np_branch_source', "", ...
    'np_branch_reference_uses_point_Np', false, ...
    'Pt1_internal', NaN, 'Tt1', NaN, 'Pamb', NaN, 'Tamb', NaN, ...
    'Pt2', NaN, 'Pt2_measured', NaN, ...
    'inlet_boundary_mode', NaN, 'direct_pt1_input_used', false, ...
    'pt2_input_used', false, 'inlet_nominal_loss', NaN, ...
    'inlet_pressure_loss_correction', NaN, ...
    'inlet_total_loss', NaN, 'inlet_ram_recovery', NaN, ...
    'Pt3', NaN, 'Tt3', NaN, 'Ptb3',NaN,'Ttb3',NaN, ...
    'Pt6',NaN,'Tt6',NaN,'Wa2',NaN, ...
    'Tt45', NaN, 'Pt45', NaN, 'dNp_dt', NaN, 'dNg_dt', NaN, ...
    'inlet_corrected_mass_flow', NaN, ...
    'burner_inlet_corrected_mass_flow', NaN, ...
    'gt_pt_duct_corrected_mass_flow', NaN, ...
    'pt_nozzle_duct_corrected_mass_flow', NaN, ...
    'ac_corrected_speed', NaN, 'cc_corrected_speed', NaN, ...
    'gt_total_pressure_ratio', NaN, ...
    'pt_total_pressure_ratio', NaN, 'valid', false, ...
    'error_message', "");
end

function [active, branch] = local_np_branch_from_point(route, point, options)
active = false;
branch = struct('centerRpm', NaN, 'lowerRpm', NaN, ...
    'upperRpm', NaN, 'relativeHalfWidth', NaN, 'source', "", ...
    'referenceUsesPointNp', false);
if ~strcmp(route, 'steady') || ~options.steadyNpBranchEnabled
    return;
end
required = {'Np_branch_center_rpm','Np_branch_lower_rpm', ...
    'Np_branch_upper_rpm','Np_branch_relative_half_width', ...
    'Np_branch_available','Np_branch_source', ...
    'Np_branch_reference_uses_point_Np'};
if any(~ismember(required, point.Properties.VariableNames))
    return;
end
if ~logical(point.Np_branch_available(1))
    if ismember('Np_branch_optional',point.Properties.VariableNames) && ...
            logical(point.Np_branch_optional(1))
        return;
    end
    error('SHT:SteadyAdaptV2:NpBranchUnavailable', ...
        '工况%s没有可用Np合理分支。', char(point.point_id));
end
branch.centerRpm = double(point.Np_branch_center_rpm(1));
branch.lowerRpm = double(point.Np_branch_lower_rpm(1));
branch.upperRpm = double(point.Np_branch_upper_rpm(1));
branch.relativeHalfWidth = ...
    double(point.Np_branch_relative_half_width(1));
branch.source = string(point.Np_branch_source(1));
branch.referenceUsesPointNp = ...
    logical(point.Np_branch_reference_uses_point_Np(1));
active = true;
end

function [seed, detail] = local_prepare_branch_gaspath_seed( ...
        engine, cfg, stepInValue, seed, options)
gasCount=4+3*double(cfg.engine.modelMode==1);
% 在Np分支中心和给定Ng初值下先求七维瞬态气路共同工作解。该计算只
% 生成稳态Newton的气路初值，不使用目标工况的Np测量值或输出残差。
detail = struct('prepared', false, 'robustFallbackUsed', false, ...
    'maxResidual', NaN, 'source', "configured_initial_guess");
local_set_dll_seed(engine, cfg, seed);
[ret, ~, eng] = local_call_one_step(engine, cfg, stepInValue);
maxResidual = local_engine_max_residual(eng);
varIte = double(eng.varIte(:));
directValid = ret == 0 && isfinite(maxResidual) && ...
    maxResidual <= options.maxModelResidual && numel(varIte) >= gasCount && ...
    all(isfinite(varIte(1:gasCount)));
if directValid
    seed(1:gasCount) = varIte(1:gasCount);
    detail.prepared = true;
    detail.maxResidual = maxResidual;
    detail.source = "transient_gaspath_seed_at_np_branch_center";
    return;
end

fallback = sht_solve_transient_components_from_seed( ...
    engine, cfg, stepInValue, seed(1:gasCount));
fallbackEng = fallback.engOut.eng;
fallbackResidual = local_engine_max_residual(fallbackEng);
fallbackVarIte = double(fallbackEng.varIte(:));
fallbackValid = fallback.ret == 0 && fallback.converged && ...
    isfinite(fallbackResidual) && ...
    fallbackResidual <= options.maxModelResidual && ...
    numel(fallbackVarIte) >= gasCount && all(isfinite(fallbackVarIte(1:gasCount)));
if fallbackValid
    seed(1:gasCount) = fallbackVarIte(1:gasCount);
    detail.prepared = true;
    detail.robustFallbackUsed = true;
    detail.maxResidual = fallbackResidual;
    detail.source = "robust_transient_gaspath_seed_at_np_branch_center";
else
    detail.maxResidual = min([maxResidual, fallbackResidual], ...
        [], 'omitnan');
    detail.source = "configured_initial_guess_after_gaspath_seed_failure";
end
end

function seed = local_initial_common_variable_seed( ...
        cfg, ptLoadPower, npMeasured, ngMeasured)
if cfg.engine.modelMode==0
    info=sht_get_steady_trim_initial_guess(cfg,npMeasured,ptLoadPower,'auto');
    if info.available && numel(info.varIte)==6
        seed=double(info.varIte(:));
    else
        ratio=max(.08,ptLoadPower/cfg.engine.initial.power0);
        seed=[max(1.5,6.7*ratio);.6;2.5+ratio;1.3+2.2*ratio;npMeasured;ngMeasured];
    end
    seed(5:6)=[npMeasured;ngMeasured];return;
end
seedInfo = sht_get_steady_trim_initial_guess( ...
    cfg, npMeasured, ptLoadPower, 'auto');
if seedInfo.available && numel(seedInfo.varIte) == 9 && ...
        all(isfinite(seedInfo.varIte))
    seed = seedInfo.varIte(:);
else
    % 仅在公共初值资产不可用时使用设计状态附近的工程回退值。
    npRatio = npMeasured / cfg.engine.initial.Np0;
    loadRatio = ptLoadPower / cfg.engine.initial.power0;
    seed = [max(2.5, 6.7 * max(loadRatio, 0.15)); ...
        min(max(0.70 + 0.18 * (1 - loadRatio), 0.5), 0.98); ...
        min(max(0.70 + 0.14 * (1 - loadRatio), 0.5), 0.98); ...
        2.0 + 1.8 * max(loadRatio, 0.1); ...
        1.5 + 1.6 * max(loadRatio, 0.1); ...
        1.5 + 1.5 * max(loadRatio, 0.1); ...
        1.2 + 1.2 * max(loadRatio, 0.1); ...
        npMeasured; ngMeasured];
    if npRatio < 0.75
        seed(8:9) = [npMeasured; ngMeasured];
    end
end
seed(8) = npMeasured;
seed(9) = ngMeasured;
end

function local_set_dll_seed(engine, cfg, seed)
stepInValue = zeros(cfg.engine.interface.stepInLength, 1);
stepInValue(21:20+numel(seed)) = seed(:);
engPtr = local_engine_pointer(engine);
stepIn = libpointer('doublePtr', stepInValue);
stepOut = libpointer('doublePtr', zeros(cfg.engine.interface.stepOutLength, 1));
status = calllib(engine.libraryName, 'DLL_SHT_varIteInit', ...
    stepIn, stepOut, engPtr);
if status ~= 0
    error('SHT:SteadyAdaptV2:SeedInitializationFailure', ...
        'DLL共同工作初值写入失败，状态码=%d。', status);
end
end

function [ret, stepOutValue, eng] = local_call_one_point( ...
        engine, cfg, stepInValue)
engPtr = local_engine_pointer(engine);
stepIn = libpointer('doublePtr', stepInValue);
stepOut = libpointer('doublePtr', zeros(cfg.engine.interface.stepOutLength, 1));
[ret, ~, stepOutValue, engOut] = calllib(engine.libraryName, ...
    'DLL_SHT_RunOnePoint', stepIn, stepOut, engPtr);
eng = engOut.eng;
end

function [ret, stepOutValue, eng] = local_call_one_step( ...
        engine, cfg, stepInValue)
engPtr = local_engine_pointer(engine);
stepIn = libpointer('doublePtr', stepInValue);
stepOut = libpointer('doublePtr', zeros(cfg.engine.interface.stepOutLength, 1));
[ret, ~, stepOutValue, engOut] = calllib(engine.libraryName, ...
    'DLL_SHT_RunOneStep', stepIn, stepOut, engPtr);
eng = engOut.eng;
end

function engPtr = local_engine_pointer(engine)
engPtrInit.eng = libstruct(engine.engineStructName);
engPtr = libstruct(engine.enginePointerName, engPtrInit);
end

function value = local_engine_max_residual(eng)
value = max(abs([double(eng.errOut(:)); double(eng.Nozzle.y(end))]));
end

function correctedFlow = local_corrected_flow(gasPath)
gasPath = double(gasPath(:));
massFlow = gasPath(1);
totalTemperature = gasPath(3);
totalPressure = gasPath(4);
correctedFlow = massFlow * sqrt(totalTemperature / 288.15) * ...
    101325 / totalPressure;
end

function local_disable_dll_schedule(engine)
status = calllib(engine.libraryName, ...
    'DLL_SHT_HealthScheduleSetEnabled', int32(0));
if status ~= 0
    % DLL刚初始化、尚未配置表时SetEnabled(0)也应返回0；非0表示接口漂移。
    error('SHT:SteadyAdaptV2:ScheduleDisableFailure', ...
        '关闭DLL健康调度失败，状态码=%d。', status);
end
end

function local_configure_dll_schedule(engine, schedule)
% DLL要求31张表全部就绪后才能启用。本程序只估计其中10张，剩余表
% 使用零增量占位，确保未估参数严格保持stepIn给定常值（本轮为0）。
local_disable_dll_schedule(engine);
status = calllib(engine.libraryName, 'DLL_SHT_HealthScheduleReset');
if status ~= 0
    error('SHT:SteadyAdaptV2:ScheduleResetFailure', ...
        '复位DLL健康调度失败，状态码=%d。', status);
end

[allIndex, allAxis] = local_all_schedule_dictionary();
if engine.modelMode==0
    allIndex=allIndex(1:13);allAxis=allAxis(1:13);
end
for i = 1:numel(allIndex)
    cIndex = allIndex(i);
    axisType = allAxis(i);
    estimatedIndex = find([schedule.healthEntries.cIndex] == cIndex, 1);
    if isempty(estimatedIndex)
        [xNode, deltaNode] = local_zero_increment_schedule(axisType);
    else
        entry = schedule.healthEntries(estimatedIndex);
        xNode = entry.xNodes(:);
        deltaNode = entry.deltaNodesDll(:);
    end
    status = calllib(engine.libraryName, ...
        'DLL_SHT_HealthScheduleConfigureTable', int32(cIndex), ...
        int32(axisType), int32(numel(xNode)), ...
        libpointer('doublePtr', xNode), ...
        libpointer('doublePtr', deltaNode));
    if status ~= 0
        error('SHT:SteadyAdaptV2:ScheduleConfigureFailure', ...
            '配置h%d调度表失败，axis=%d，nodeCount=%d，状态码=%d。', ...
            cIndex, axisType, numel(xNode), status);
    end
end
configured = calllib(engine.libraryName, ...
    'DLL_SHT_HealthScheduleGetConfiguredCount');
if configured ~= numel(allIndex)
    error('SHT:SteadyAdaptV2:ScheduleCountMismatch', ...
        'DLL已配置调度表数量为%d，预期%d。', configured,numel(allIndex));
end
end

function [cIndex, axisType] = local_all_schedule_dictionary()
cIndex = [0, 1, 2, 3, 6, 7, 8, 9, 10, 11, 12, 13, 14, 71:88].';
axisType = zeros(size(cIndex));
for i = 1:numel(cIndex)
    h = cIndex(i);
    if h == 0
        axisType(i) = 1;
    elseif h == 6
        axisType(i) = 2;
    elseif h == 10
        axisType(i) = 3;
    elseif h == 14
        axisType(i) = 4;
    elseif ismember(h, [1:3, 71:73])
        axisType(i) = 5;
    elseif ismember(h, 74:76)
        axisType(i) = 6;
    elseif ismember(h, [7:9, 77:82])
        axisType(i) = 7;
    elseif ismember(h, [11:13, 83:88])
        axisType(i) = 8;
    else
        error('SHT:SteadyAdaptV2:InternalScheduleDictionary', ...
            'h%d未配置调度坐标。', h);
    end
end
end

function [xNode, deltaNode] = local_zero_increment_schedule(axisType)
if axisType <= 4
    xNode = [0; 1; 2; 3; 4; 5; 6];
elseif axisType <= 6
    xNode = [0.5; 0.7; 0.85; 1.0; 1.15; 1.3];
else
    xNode = [1; 2; 3; 4; 5; 6];
end
deltaNode = zeros(size(xNode));
end

function residual = local_data_residual(route, data, prediction, weighting)
names = cellstr(weighting.names);
raw = local_raw_data_residual_matrix(route, data, prediction, names);
if weighting.isStackedObservationCovariance
    coordinateResidual = local_coordinate_raw_vector(raw, weighting);
    observationCholLower = local_observation_chol_for_data( ...
        weighting, data);
    residual = observationCholLower \ coordinateResidual;
    return;
end
if size(weighting.cholLower, 1) ~= numel(names)
    error('SHT:SteadyAdaptV2:ResidualWeightingDimensionMismatch', ...
        '残差通道数与冻结白化矩阵维数不一致。');
end
coordinateRaw = local_coordinate_raw_matrix(raw, weighting);
% covariance=L*L''，每个工况行向量右除L''等价于L\e。
whitened = coordinateRaw / weighting.cholLower.';
% 保持历史“按通道连续堆叠”的列主序，仅改变通道坐标变换。
residual = whitened(:);
end

function coordinateRaw = local_coordinate_raw_matrix(raw, weighting)
if strcmp(weighting.normalizationMode, 'design_reference')
    coordinateRaw = raw ./ weighting.normalizationScale(:).';
else
    coordinateRaw = raw;
end
end

function coordinateResidual = local_coordinate_raw_vector(raw, weighting)
coordinateResidual = raw(:);
if strcmp(weighting.normalizationMode, 'design_reference')
    coordinateResidual = coordinateResidual ./ ...
        repelem(weighting.normalizationScale(:), size(raw, 1));
end
end

function cholLower = local_observation_chol_for_data(weighting, data)
queryIds = string(data.point_id(:));
[found, rowIndex] = ismember(queryIds, weighting.observationPointIds);
if ~all(found) || numel(unique(rowIndex)) ~= numel(rowIndex)
    error('SHT:SteadyAdaptV2:ObservationSubsetMappingFailure', ...
        '当前数据不能唯一映射到冻结观测协方差的训练工况行。');
end
fullCount = numel(weighting.observationPointIds);
subsetCount = numel(rowIndex);
channelCount = numel(weighting.names);
index = zeros(subsetCount * channelCount, 1);
for j = 1:channelCount
    target = (j - 1) * subsetCount + (1:subsetCount);
    index(target) = (j - 1) * fullCount + rowIndex;
end
if strcmp(weighting.normalizationMode, 'design_reference')
    covariance = weighting.normalizedObservationCovariance(index, index);
else
    covariance = weighting.observationCovariance(index, index);
end
[cholLower, flag] = chol(0.5 * (covariance + covariance.'), 'lower');
if flag ~= 0
    error('SHT:SteadyAdaptV2:ObservationSubsetFactorFailure', ...
        '冻结观测协方差子矩阵不能完成Cholesky分解。');
end
end

function raw = local_raw_data_residual_matrix(route, data, prediction, names)
raw = zeros(height(data), numel(names));
for j = 1:numel(names)
    name = names{j};
    raw(:, j) = prediction.(name) - local_target_vector(data, name);
end
if strcmp(route, 'steady') && any(ismember(names, {'dNp_dt','dNg_dt'}))
    error('SHT:SteadyAdaptV2:InternalResidualDefinition', ...
        '稳态路径残差错误包含轴加速度。');
end
end

function target = local_target_vector(data, name)
switch name
    case {'Ptb3','Ttb3','Pt6','Tt6','Wa2'}
        target=data.([name,'_mean']);
    case 'Np'
        target = data.Np_mean;
    case 'Ng'
        target = data.Ng_mean;
    case 'Pt2'
        target = data.Pt2_mean;
    case 'Pt3'
        target = data.Pt3_mean;
    case 'Tt3'
        target = data.Tt3_mean;
    case 'Tt45'
        target = data.Tt45_mean;
    case 'Pt45'
        target = data.Pt45_mean;
    case {'dNp_dt', 'dNg_dt'}
        target = zeros(height(data), 1);
    otherwise
        error('SHT:SteadyAdaptV2:UnknownResidual', ...
            '未知残差字段%s。', name);
end
end

function metrics = local_dataset_metrics(route, data, prediction, scales)
names = cellstr(scales.name);
if isempty(data)
    field = string(names(:));
    nanColumn = nan(numel(names), 1);
    metrics = struct('route', route, 'valid_point_nrms', NaN, ...
        'overall_nrms', NaN, 'valid_point_count', 0, 'point_count', 0, ...
        'all_points_valid', NaN, 'max_model_residual', NaN, ...
        'byField', table(field, nanColumn, nanColumn, nanColumn, nanColumn, ...
        'VariableNames', {'field','rmse','normalized_rmse', ...
        'mean_absolute_error','mean_absolute_relative_error_pct'}));
    return;
end
validPoint = prediction.valid & ...
    isfinite(prediction.max_model_residual);
field = strings(numel(names), 1);
rmse = nan(numel(names), 1);
normalizedRmse = nan(numel(names), 1);
meanAbsoluteError = nan(numel(names), 1);
meanAbsoluteRelativeErrorPct = nan(numel(names), 1);
for i = 1:numel(names)
    field(i) = string(names{i});
    target = local_target_vector(data, names{i});
    predictedValue = prediction.(names{i});
    fieldValid = validPoint & isfinite(predictedValue) & ...
        isfinite(target);
    if ~any(fieldValid)
        continue;
    end
    target = target(fieldValid);
    errorValue = predictedValue(fieldValid) - target;
    rmse(i) = sqrt(mean(errorValue .^ 2));
    normalizedRmse(i) = rmse(i) / scales.scale(i);
    meanAbsoluteError(i) = mean(abs(errorValue));
    denominator = abs(target);
    valid = denominator > max(1e-12, 1e-8 * max(denominator));
    if any(valid)
        meanAbsoluteRelativeErrorPct(i) = ...
            mean(abs(errorValue(valid)) ./ denominator(valid)) * 100;
    end
end
metrics = struct();
metrics.route = route;
metrics.valid_point_nrms = sqrt(mean(normalizedRmse .^ 2, 'omitnan'));
if all(validPoint)
    metrics.overall_nrms = metrics.valid_point_nrms;
else
    % 不用失败回放的默认零值或溢出值伪造“全集误差”。
    metrics.overall_nrms = NaN;
end
metrics.valid_point_count = sum(validPoint);
metrics.point_count = height(prediction);
metrics.all_points_valid = all(validPoint);
metrics.max_model_residual = max( ...
    prediction.max_model_residual(validPoint), [], 'omitnan');
metrics.byField = table(field, rmse, normalizedRmse, meanAbsoluteError, ...
    meanAbsoluteRelativeErrorPct, ...
    'VariableNames', {'field','rmse','normalized_rmse', ...
    'mean_absolute_error','mean_absolute_relative_error_pct'});
end

function evaluation = local_evaluate_transient_test_as_steady( ...
        route, engine, cfg, scaleReferenceData, testData, ...
        baselineModel, correctedModel, options, ...
        baselineTransientDiagnostic, correctedTransientDiagnostic)
% 瞬态时刻模型的收敛结果包含7个气路共同工作变量和实测Np/Ng。
% 转入稳态测试时只原样继承7个气路变量及Ng；Np由训练集功率曲线
% 预测的分支中心替换。该支路只评价独立测试集，不参与参数更新。
evaluation = struct('performed', false, ...
    'initializationSource', "", 'residualScales', table(), ...
    'baseline', struct(), 'corrected', struct(), ...
    'predictionTable', table(), 'seedTransferTable', table());
if isempty(testData) || ~strcmp(route, 'transient_instant') || ...
        ~options.evaluateSteadyTestFromTransient
    return;
end
if ~all(baselineTransientDiagnostic.solutionAvailable) || ...
        ~all(correctedTransientDiagnostic.solutionAvailable)
    error('SHT:SteadyAdaptV2:TransientSeedUnavailable', ...
        '存在未收敛的瞬态测试点，不能构造完整稳态初值。');
end

% 归一化尺度由训练集冻结，测试集只负责评价，不能反向定义指标尺度。
steadyScales = local_residual_scales( ...
    'steady', cfg, scaleReferenceData, options);
steadyOptions = options;
if ~options.steadyUseMeasuredPower
    steadyOptions.steadyLoadBoundaryMode = 'torque';
end
[baselinePrediction, baselineValid, baselineSteadyDiagnostic] = ...
    local_evaluate_dataset('steady', engine, cfg, testData, ...
    baselineModel, steadyOptions, baselineTransientDiagnostic.solutionSeed);
[correctedPrediction, correctedValid, correctedSteadyDiagnostic] = ...
    local_evaluate_dataset('steady', engine, cfg, testData, ...
    correctedModel, steadyOptions, correctedTransientDiagnostic.solutionSeed);

baselineMetrics = local_dataset_metrics( ...
    'steady', testData, baselinePrediction, steadyScales);
correctedMetrics = local_dataset_metrics( ...
    'steady', testData, correctedPrediction, steadyScales);
predictionTable = local_prediction_detail_table( ...
    'steady', testData, baselinePrediction, correctedPrediction, ...
    steadyScales);
seedTransferTable = local_transient_to_steady_seed_table( ...
    testData, baselineTransientDiagnostic, baselineSteadyDiagnostic, ...
    baselinePrediction, correctedTransientDiagnostic, ...
    correctedSteadyDiagnostic, correctedPrediction);

evaluation.performed = true;
evaluation.initializationSource = ...
    "瞬态收敛气路初值加训练功率曲线Np分支";
evaluation.residualScales = steadyScales;
evaluation.baseline = struct( ...
    'transientConvergedSeed', baselineTransientDiagnostic.solutionSeed, ...
    'steadyPrediction', baselinePrediction, ...
    'steadyValid', baselineValid, 'steadyMetrics', baselineMetrics, ...
    'steadyDiagnostic', baselineSteadyDiagnostic);
evaluation.corrected = struct( ...
    'transientConvergedSeed', correctedTransientDiagnostic.solutionSeed, ...
    'steadyPrediction', correctedPrediction, ...
    'steadyValid', correctedValid, 'steadyMetrics', correctedMetrics, ...
    'steadyDiagnostic', correctedSteadyDiagnostic);
evaluation.predictionTable = predictionTable;
evaluation.seedTransferTable = seedTransferTable;
end

function tbl = local_transient_to_steady_seed_table( ...
        data, baselineTransient, baselineSteady, baselinePrediction, ...
        correctedTransient, correctedSteady, correctedPrediction)
n = height(data);
modelVariant = [repmat("zero_correction", n, 1); ...
    repmat("estimated_correction", n, 1)];
pointId = [string(data.point_id); string(data.point_id)];
transientSeed = [baselineTransient.solutionSeed; ...
    correctedTransient.solutionSeed];
steadyBaseSeed = [baselineSteady.baseSeed; correctedSteady.baseSeed];
steadyInitialSeed = [baselineSteady.initialSeed; ...
    correctedSteady.initialSeed];
steadySolution = [baselineSteady.solutionSeed; ...
    correctedSteady.solutionSeed];
seedSource = [baselineSteady.seedSource; correctedSteady.seedSource];
steadyValid = [baselinePrediction.valid; correctedPrediction.valid];
steadyMaxResidual = [baselinePrediction.max_model_residual; ...
    correctedPrediction.max_model_residual];
% 七个气路变量和Ng必须原样继承瞬态收敛解；Np由训练功率曲线分支
% 中心替换，这是有意的物理解选择，不能误判为初值传递错误。
nVariable=size(transientSeed,2);npIndex=nVariable-1;
preservedIndex = [1:nVariable-2,nVariable];
seedTransferMaxAbsError = max(abs( ...
    steadyBaseSeed(:, preservedIndex) - ...
    transientSeed(:, preservedIndex)), [], 2);
seedScale = max(abs(transientSeed(:, preservedIndex)), [], 2);
seedTolerance = 1e-12 * max(1, seedScale);
if any(seedTransferMaxAbsError > seedTolerance)
    error('SHT:SteadyAdaptV2:TransientSeedTransferMismatch', ...
        '瞬态收敛解传入稳态初值时发生数值改变。');
end

tbl = table(modelVariant, pointId, seedSource, ...
    seedTransferMaxAbsError, ...
    transientSeed(:, npIndex), steadyInitialSeed(:, npIndex), ...
    steadyInitialSeed(:, npIndex) - transientSeed(:, npIndex), ...
    steadyValid, steadyMaxResidual, ...
    'VariableNames', {'model_variant','point_id','seed_source', ...
    'preserved_seed_transfer_max_abs_error', ...
    'transient_Np_seed_rpm','steady_branch_Np_seed_rpm', ...
    'Np_seed_replacement_rpm','steady_valid', ...
    'steady_max_model_residual'});
variableName = {'Win','Rline_AC','Rline_CC','PR_GT1','PR_GT2', ...
    'PR_PT1','PR_PT2','Np','Ng'};
if nVariable==6,variableName={'Win','Rline_HPC','PR_GT','PR_PT','Np','Ng'};end
for j = 1:numel(variableName)
    tbl.(['transient_' variableName{j}]) = transientSeed(:, j);
    tbl.(['steady_base_' variableName{j}]) = steadyBaseSeed(:, j);
    tbl.(['steady_initial_' variableName{j}]) = steadyInitialSeed(:, j);
    tbl.(['steady_solution_' variableName{j}]) = steadySolution(:, j);
end
end

function local_write_steady_test_from_transient_excel(filePath, evaluation)
if ~evaluation.performed
    return;
end
writetable(evaluation.baseline.steadyMetrics.byField, filePath, ...
    'Sheet', 'steady_test_metric_base');
writetable(evaluation.corrected.steadyMetrics.byField, filePath, ...
    'Sheet', 'steady_test_metric_est');
writetable(evaluation.predictionTable, filePath, ...
    'Sheet', 'steady_test_prediction');
writetable(evaluation.seedTransferTable, filePath, ...
    'Sheet', 'steady_test_seed');
writetable(evaluation.residualScales, filePath, ...
    'Sheet', 'steady_test_scales');
end

function local_print_steady_test_from_transient(evaluation)
if ~evaluation.performed
    return;
end
fprintf(['测试集额外稳态回放（以对应瞬态收敛解为初值）NRMS：' ...
    '%.6g -> %.6g；有效：%d/%d。\n'], ...
    evaluation.baseline.steadyMetrics.overall_nrms, ...
    evaluation.corrected.steadyMetrics.overall_nrms, ...
    evaluation.baseline.steadyValid, evaluation.corrected.steadyValid);
comparison = table( ...
    evaluation.corrected.steadyMetrics.byField.field, ...
    evaluation.baseline.steadyMetrics.byField.normalized_rmse, ...
    evaluation.corrected.steadyMetrics.byField.normalized_rmse, ...
    evaluation.corrected.steadyMetrics.byField.mean_absolute_relative_error_pct, ...
    'VariableNames', {'field','baseline_normalized_rmse', ...
    'corrected_normalized_rmse','corrected_mean_abs_relative_error_pct'});
disp(comparison);
end

function tbl = local_parameter_result_table( ...
        parameters, stageAValue, groupResults, finalSchedule)
groupMatrix = zeros(numel(groupResults), numel(stageAValue));
for i = 1:numel(groupResults)
    groupMatrix(i, :) = groupResults(i).x(:).';
end
n = height(parameters);
cIndex = parameters.c_index;
name = parameters.name;
scheduled = parameters.scheduled;
stageA = stageAValue(1:n);
groupMean = mean(groupMatrix(:, 1:n), 1).';
groupMin = min(groupMatrix(:, 1:n), [], 1).';
groupMax = max(groupMatrix(:, 1:n), [], 1).';
finalDesignValue = nan(n, 1);
for i = 1:n
    if parameters.scheduled(i)
        entry = finalSchedule.healthEntries( ...
            [finalSchedule.healthEntries.cIndex] == cIndex(i));
        finalDesignValue(i) = entry.designValue;
    else
        finalDesignValue(i) = finalSchedule.h15;
    end
end
lowerBound = parameters.lower_bound;
upperBound = parameters.upper_bound;
tbl = table(cIndex, name, scheduled, stageA, groupMean, groupMin, ...
    groupMax, finalDesignValue, lowerBound, upperBound, ...
    'VariableNames', {'c_index','name','scheduled','stageA_constant', ...
    'group_mean','group_min','group_max','final_design_value', ...
    'lower_bound','upper_bound'});
end

function tbl = local_m3_parameter_class_table( ...
        parameters, finalSchedule, wfDesign)
%LOCAL_M3_PARAMETER_CLASS_TABLE 正式11物理类别口径。
% M3节点是数值自由度，不能改写成新的故障类别；对外仍按
% 10个无量纲发动机修正量加1个kg/s燃油测量偏置报告。
nHealth = height(parameters);
n = nHealth + 1;
cIndex = nan(n, 1);
cIndex(1:nHealth) = parameters.c_index;
name = [parameters.name; "Wf_bias"];
parameterKind = [repmat("engine_health", nHealth, 1); "fuel_bias"];
unit = [repmat("1", nHealth, 1); "kg/s"];
scheduled = [parameters.scheduled; true];
referenceCoordinate = nan(n, 1);
estimate = nan(n, 1);
for i = 1:nHealth
    if parameters.scheduled(i)
        entry = finalSchedule.healthEntries( ...
            [finalSchedule.healthEntries.cIndex] == parameters.c_index(i));
        if numel(entry) ~= 1
            error('SHT:SteadyAdaptV2:M3ParameterClassScheduleMismatch', ...
                '参数%s的最终调度曲线数量不是1。', parameters.name(i));
        end
        referenceCoordinate(i) = entry.designCoordinate;
        estimate(i) = entry.designValue;
    else
        referenceCoordinate(i) = 0;
        estimate(i) = finalSchedule.h15;
    end
end
referenceCoordinate(end) = 1;
estimate(end) = local_interp_clamp(finalSchedule.fuelBias.xNodes, ...
    finalSchedule.fuelBias.biasNodes, 1);
lowerBound = [parameters.lower_bound; -0.02 * wfDesign];
upperBound = [parameters.upper_bound; 0.02 * wfDesign];
priorSigma = [parameters.prior_sigma_global; 0.003 * wfDesign];
differenceStep = [parameters.difference_step; max(1e-6, 5e-5 * wfDesign)];
tbl = table(cIndex, name, parameterKind, unit, scheduled, ...
    referenceCoordinate, estimate, lowerBound, upperBound, priorSigma, ...
    differenceStep, ...
    'VariableNames', {'c_index','name','parameter_kind','unit','scheduled', ...
    'reference_coordinate','estimate','lower_bound','upper_bound', ...
    'prior_sigma','difference_step'});
end

function tbl = local_group_estimate_table( ...
        groups, groupResults, parameters, wfDesign)
nGroup = height(groups);
nParameter = height(parameters);
rows = nGroup * (nParameter + 1);
groupId = strings(rows, 1);
pointIds = strings(rows, 1);
parameter = strings(rows, 1);
cIndex = nan(rows, 1);
estimate = nan(rows, 1);
unit = strings(rows, 1);
cursor = 0;
for g = 1:nGroup
    x = groupResults(g).x;
    for p = 1:nParameter
        cursor = cursor + 1;
        groupId(cursor) = groups.group_id(g);
        pointIds(cursor) = groups.point_ids(g);
        parameter(cursor) = parameters.name(p);
        cIndex(cursor) = parameters.c_index(p);
        estimate(cursor) = x(p);
        unit(cursor) = "1";
    end
    cursor = cursor + 1;
    groupId(cursor) = groups.group_id(g);
    pointIds(cursor) = groups.point_ids(g);
    parameter(cursor) = "Wf_measurement_bias";
    cIndex(cursor) = NaN;
    estimate(cursor) = x(end);
    unit(cursor) = "kg/s";
end
estimateRelativeToDesignPct = estimate / wfDesign * 100;
estimateRelativeToDesignPct(~isnan(cIndex)) = NaN;
tbl = table(groupId, pointIds, parameter, cIndex, estimate, unit, ...
    estimateRelativeToDesignPct, ...
    'VariableNames', {'group_id','point_ids','parameter','c_index', ...
    'estimate','unit','wf_bias_relative_to_design_pct'});
end

function tbl = local_schedule_node_table(schedule)
record = repmat(struct('parameter', "", 'c_index', NaN, ...
    'axis_name', "", 'node_index', NaN, 'x', NaN, ...
    'effective_value', NaN, 'design_value', NaN, ...
    'zero_anchor', false, 'dll_execution_node', false, ...
    'dll_resampling_used', false), 0, 1);
for i = 1:numel(schedule.healthEntries)
    entry = schedule.healthEntries(i);
    for j = 1:numel(entry.xNodes)
        r = struct('parameter', string(entry.name), ...
            'c_index', entry.cIndex, 'axis_name', string(entry.axisName), ...
            'node_index', j, 'x', entry.xNodes(j), ...
            'effective_value', entry.kNodes(j), ...
            'design_value', entry.designValue, ...
            'zero_anchor', entry.pressureLoss && j == 1, ...
            'dll_execution_node', ~entry.dllResamplingUsed, ...
            'dll_resampling_used', entry.dllResamplingUsed);
        record(end + 1, 1) = r; %#ok<AGROW>
    end
    if entry.dllResamplingUsed
        for j = 1:numel(entry.xNodesDll)
            r = struct('parameter', string(entry.name) + "_DLL", ...
                'c_index', entry.cIndex, 'axis_name', string(entry.axisName), ...
                'node_index', j, 'x', entry.xNodesDll(j), ...
                'effective_value', entry.kNodesDll(j), ...
                'design_value', entry.designValue, ...
                'zero_anchor', entry.pressureLoss && j == 1, ...
                'dll_execution_node', true, ...
                'dll_resampling_used', true);
            record(end + 1, 1) = r; %#ok<AGROW>
        end
    end
end
for j = 1:numel(schedule.fuelBias.xNodes)
    r = struct('parameter', "Wf_measurement_bias", 'c_index', NaN, ...
        'axis_name', "measured_wf_ratio", 'node_index', j, ...
        'x', schedule.fuelBias.xNodes(j), ...
        'effective_value', schedule.fuelBias.biasNodes(j), ...
        'design_value', NaN, 'zero_anchor', false, ...
        'dll_execution_node', false, 'dll_resampling_used', false);
    record(end + 1, 1) = r; %#ok<AGROW>
end
tbl = struct2table(record);
end

function tbl = local_prediction_detail_table( ...
        route, data, baseline, finalPrediction, scales)
names = cellstr(scales.name);
record = repmat(struct('point_id', "", 'field', "", ...
    'measured', NaN, 'baseline_model', NaN, 'corrected_model', NaN, ...
    'baseline_error', NaN, 'corrected_error', NaN, ...
    'baseline_relative_error_pct', NaN, ...
    'corrected_relative_error_pct', NaN, ...
    'baseline_normalized_error', NaN, ...
    'corrected_normalized_error', NaN), ...
    height(data) * numel(names), 1);
cursor = 0;
for i = 1:height(data)
    for j = 1:numel(names)
        cursor = cursor + 1;
        target = local_target_vector(data(i, :), names{j});
        baselineError = baseline.(names{j})(i) - target;
        correctedError = finalPrediction.(names{j})(i) - target;
        record(cursor).point_id = data.point_id(i);
        record(cursor).field = string(names{j});
        record(cursor).measured = target;
        record(cursor).baseline_model = baseline.(names{j})(i);
        record(cursor).corrected_model = finalPrediction.(names{j})(i);
        record(cursor).baseline_error = baselineError;
        record(cursor).corrected_error = correctedError;
        if abs(target) > 1e-12
            record(cursor).baseline_relative_error_pct = ...
                baselineError / abs(target) * 100;
            record(cursor).corrected_relative_error_pct = ...
                correctedError / abs(target) * 100;
        end
        record(cursor).baseline_normalized_error = ...
            baselineError / scales.scale(j);
        record(cursor).corrected_normalized_error = ...
            correctedError / scales.scale(j);
    end
end
tbl = struct2table(record);
tbl.Properties.Description = [local_route_label(route) '模型输出对比'];
end

function audit = local_write_result_excel(filePath, result)
if strcmp(result.stageDParameterization, 'actual_execution_nodes')
    audit = local_write_m3_result_excel_atomic(filePath, result);
    return;
end
local_write_result_excel_direct(filePath, result, struct(), table());
audit = struct('verification', table(), 'fileSha256', '', ...
    'semanticPayloadSha256', '');
end

function audit = local_m3_workbook_selftest(result)
% 仅供无DLL结构测试：在系统临时目录执行完整写入/关闭/重开/哈希流程。
if ~isstruct(result) || ~isfield(result, 'stageDParameterization') || ...
        ~strcmp(result.stageDParameterization, 'actual_execution_nodes')
    error('SHT:SteadyAdaptV2:M3WorkbookSelfTestBadResult', ...
        '工作簿自测需要完整M3结果结构。');
end
parentDir = tempdir;
leaf = ['sht_m3_workbook_' char(java.util.UUID.randomUUID())];
testDir = fullfile(parentDir, leaf);
if ~mkdir(testDir)
    error('SHT:SteadyAdaptV2:M3WorkbookSelfTestCreateFailure', ...
        '无法创建工作簿自测临时目录。');
end
cleanupObject = onCleanup(@() local_remove_workbook_selftest_dir( ...
    testDir, parentDir, leaf));
fileName = fullfile(testDir, 'm3_workbook_selftest.xlsx');
audit = local_write_result_excel(fileName, result);
if ~exist(fileName, 'file') || ~exist([fileName '.sha256'], 'file') || ...
        ~audit.atomicPublished || ~audit.sha256SidecarWritten
    error('SHT:SteadyAdaptV2:M3WorkbookSelfTestPublishFailure', ...
        '工作簿自测未生成完整原子文件与SHA旁车。');
end
audit.temporaryArtifactsScopedForCleanup = true;
clear cleanupObject;
local_remove_workbook_selftest_dir(testDir, parentDir, leaf);
end

function local_remove_workbook_selftest_dir(testDir, parentDir, leaf)
if exist(testDir, 'dir') ~= 7
    return;
end
expected = fullfile(parentDir, leaf);
if ~startsWith(leaf, 'sht_m3_workbook_') || ...
        ~strcmpi(local_canonical_file_name(testDir), ...
        local_canonical_file_name(expected)) || ...
        ~strcmpi(local_canonical_file_name(fileparts(testDir)), ...
        local_canonical_file_name(parentDir))
    warning('SHT:SteadyAdaptV2:UnsafeWorkbookSelfTestCleanupRefused', ...
        '工作簿自测目录未通过精确临时边界门，拒绝清理：%s。', testDir);
    return;
end
[removed, message] = rmdir(testDir, 's');
if ~removed
    warning('SHT:SteadyAdaptV2:WorkbookSelfTestCleanupFailure', ...
        '无法清理工作簿自测目录%s：%s。', testDir, message);
end
end

function local_write_result_excel_direct( ...
        filePath, result, formalTables, ~)
if exist(filePath, 'file')
    delete(filePath);
end
if strcmp(result.stageDParameterization, 'actual_execution_nodes')
    % 正式Excel只传递下游运行所必需的阶段结果。迭代历史、
    % Jacobian、拟合指标和回放证据继续保存在不可变MAT侧车中。
    writetable(formalTables.Manifest, filePath, 'Sheet', 'Manifest');
    writetable(formalTables.CorrectionSchedule, filePath, ...
        'Sheet', 'CorrectionSchedule');
    writetable(formalTables.MeasurementBias, filePath, ...
        'Sheet', 'MeasurementBias');
    writetable(formalTables.NpBranchModel, filePath, ...
        'Sheet', 'NpBranchModel');
    return;
end
writetable(result.parameterTable, filePath, 'Sheet', 'parameters');
writetable(result.groups(:, setdiff(result.groups.Properties.VariableNames, ...
    {'row_indices'})), filePath, 'Sheet', 'groups');
writetable(result.groupEstimateTable, filePath, 'Sheet', 'group_estimates');
writetable(result.scheduleNodeTable, filePath, 'Sheet', 'schedule_nodes');
writetable(result.stageA.history, filePath, 'Sheet', 'stageA_history');
writetable(result.stageRefine.history, filePath, 'Sheet', 'refine_history');
writetable(struct2table(result.timing), filePath, 'Sheet', 'timing');
writetable(result.baseline.trainingMetrics.byField, filePath, ...
    'Sheet', 'baseline_train_metric');
writetable(result.final.trainingMetrics.byField, filePath, ...
    'Sheet', 'final_train_metric');
writetable(result.predictionTrainingTable, filePath, ...
    'Sheet', 'training_prediction');
writetable(result.residualScales, filePath, 'Sheet', 'residual_scales');
local_write_residual_weighting_excel(filePath, result.residualWeighting);
if isfield(result,'npBranchPrior') && result.npBranchPrior.enabled
    writetable(result.npBranchPrior.trainingPrior.trainingTable, ...
        filePath,'Sheet','np_branch_training');
    writetable(result.npBranchPrior.trainingRootSelectionTable, ...
        filePath,'Sheet','np_branch_train_gate');
    writetable(result.npBranchPrior.trainingPrior.leaveOneOutTable, ...
        filePath,'Sheet','np_branch_loo');
    if isfield(result.npBranchPrior.targetPrior,'testTable')
        writetable(result.npBranchPrior.targetPrior.testTable, ...
            filePath,'Sheet','np_branch_target');
    end
end
if result.input.testDataAvailable
    writetable(result.baseline.testMetrics.byField, filePath, ...
        'Sheet', 'baseline_test_metric');
    writetable(result.final.testMetrics.byField, filePath, ...
        'Sheet', 'final_test_metric');
    writetable(result.predictionTestTable, filePath, ...
        'Sheet', 'test_prediction');
end
local_write_steady_test_from_transient_excel( ...
    filePath, result.steadyTestFromTransient);
if isfield(result, 'inletPressureLossDirect') && ...
        ~isempty(fieldnames(result.inletPressureLossDirect))
    writetable(result.inletPressureLossDirect.trainingTable, filePath, ...
        'Sheet', 'inlet_kdp_training');
    inletNodeTable = table( ...
        result.inletPressureLossDirect.entry.xNodes, ...
        result.inletPressureLossDirect.entry.kNodes, ...
        'VariableNames', {'inlet_corrected_mass_flow','Inlet_K_dP'});
    writetable(inletNodeTable, filePath, 'Sheet', 'inlet_kdp_nodes');
end
end

function audit = local_write_m3_result_excel_atomic(filePath, result)
% 正式M3工作簿先在同卷唯一partial文件中完成三次读回，再原子发布。
if exist(filePath, 'file') || exist(filePath, 'dir') || ...
        exist([filePath '.sha256'], 'file')
    error('SHT:SteadyAdaptV2:M3WorkbookTargetExists', ...
        '正式M3工作簿或SHA旁车已存在，拒绝覆盖：%s。', filePath);
end
[folder, baseName, extension] = fileparts(filePath);
uniqueId = char(java.util.UUID.randomUUID());
% 外层正式run partial目录已经提供隔离；内层仍保留独立UUID，但采用
% 短文件名，确保在深层Worktree中也低于R2020a工作簿路径上限。
partialFile = fullfile(folder, sprintf('.w.%s%s', uniqueId, extension));
shaFile = [filePath '.sha256'];
partialShaFile = fullfile(folder, sprintf('.w.%s.sha256', uniqueId));
cleanupObject = onCleanup(@() local_delete_exact_files( ...
    {partialFile, partialShaFile}));

completedAt = datestr(now, 31);
formalTables = local_m3_formal_tables(result, completedAt, "");
semanticHash = local_m3_semantic_payload_hash(formalTables);
formalTables.Manifest.semantic_payload_sha256(:) = string(semanticHash);
if ~strcmp(semanticHash, local_m3_semantic_payload_hash(formalTables))
    error('SHT:SteadyAdaptV2:M3WorkbookSemanticHashInstability', ...
        '确定性M3工作簿规范载荷哈希不稳定。');
end

local_write_result_excel_direct(partialFile, result, formalTables, table());
firstReadback = local_m3_formal_readback(partialFile, formalTables);
if ~all(firstReadback.passed)
    error('SHT:SteadyAdaptV2:M3WorkbookFirstReadFailure', ...
        '正式M3最小工作簿首次写后读回失败。');
end
secondReadback = local_m3_formal_readback(partialFile, formalTables);
thirdReadback = local_m3_formal_readback(partialFile, formalTables);
if ~all(secondReadback.passed) || ~all(thirdReadback.passed)
    error('SHT:SteadyAdaptV2:M3WorkbookFinalReadFailure', ...
        '正式M3最小工作簿最终关闭重开验证失败。');
end

[moved, moveMessage] = movefile(partialFile, filePath);
if ~moved
    error('SHT:SteadyAdaptV2:M3WorkbookAtomicPublishFailure', ...
        '正式M3工作簿原子发布失败：%s。', moveMessage);
end
fileHash = local_file_hash(filePath);
fid = fopen(partialShaFile, 'w', 'n', 'UTF-8');
if fid < 0
    error('SHT:SteadyAdaptV2:M3WorkbookShaWriteFailure', ...
        '无法写入正式M3工作簿SHA旁车。');
end
shaCleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s  %s\n', fileHash, [baseName extension]);
clear shaCleanup;
[moved, moveMessage] = movefile(partialShaFile, shaFile);
if ~moved
    error('SHT:SteadyAdaptV2:M3WorkbookShaPublishFailure', ...
        '正式M3工作簿SHA旁车原子发布失败：%s。', moveMessage);
end
if ~strcmp(local_file_hash(filePath), fileHash)
    error('SHT:SteadyAdaptV2:M3WorkbookPostPublishHashMismatch', ...
        '正式M3工作簿发布后的字节哈希发生变化。');
end
audit = struct('verification', thirdReadback, ...
    'firstReadback', firstReadback, 'secondReadback', secondReadback, ...
    'thirdReadback', thirdReadback, 'fileSha256', fileHash, ...
    'semanticPayloadSha256', semanticHash, 'atomicPublished', true, ...
    'sha256SidecarWritten', true);
clear cleanupObject;
end

function formal = local_m3_formal_tables(result, completedAt, semanticHash)
formal = struct();
formal.CorrectionSchedule = local_m3_correction_schedule_table(result);
formal.MeasurementBias = local_m3_measurement_bias_table(result);
formal.NpBranchModel = sht_np_branch_delivery('build',result);
formal.Manifest = local_m3_manifest_table(result, semanticHash, completedAt, ...
    height(formal.CorrectionSchedule), height(formal.MeasurementBias));
end

function hashText = local_m3_semantic_payload_hash(formal)
sheetName = {'Manifest','CorrectionSchedule','MeasurementBias','NpBranchModel'};
line = strings(0, 1);
for i = 1:numel(sheetName)
    tbl = formal.(sheetName{i});
    if strcmp(sheetName{i}, 'Manifest') && ...
            ismember('semantic_payload_sha256', tbl.Properties.VariableNames)
        tbl = removevars(tbl, 'semantic_payload_sha256');
    end
    line(end + 1, 1) = "SHEET|" + string(sheetName{i}); %#ok<AGROW>
    line = [line; local_m3_table_canonical_lines(tbl)]; %#ok<AGROW>
end
hashText = local_text_hash(strjoin(cellstr(line), newline));
end

function line = local_m3_table_canonical_lines(tbl)
name = string(tbl.Properties.VariableNames);
line = "COLUMNS|" + strjoin(name, '|');
for r = 1:height(tbl)
    value = strings(1, width(tbl));
    for c = 1:width(tbl)
        column = tbl.(tbl.Properties.VariableNames{c});
        one = column(r, :);
        if islogical(one)
            value(c) = string(double(one));
        elseif isnumeric(one)
            if ~isscalar(one)
                error('SHT:SteadyAdaptV2:M3WorkbookNonscalarCell', ...
                    '正式M3工作簿规范表只允许标量数值单元。');
            elseif isnan(one)
                value(c) = "<EMPTY>";
            elseif isinf(one)
                if one > 0
                    value(c) = "<INF>";
                else
                    value(c) = "<-INF>";
                end
            else
                value(c) = string(sprintf('%.17g', one));
            end
        else
            textValue = string(one);
            if ismissing(textValue) || strlength(textValue) == 0
                textValue = "<EMPTY>";
            end
            textValue = replace(textValue, "\", "\\");
            textValue = replace(textValue, "|", "\|");
            textValue = replace(textValue, newline, "\n");
            value(c) = textValue;
        end
    end
    line(end + 1, 1) = "ROW|" + strjoin(value, '|'); %#ok<AGROW>
end
end

function audit = local_m3_formal_readback(filePath, formal)
sheetName = ["Manifest"; "CorrectionSchedule"; "MeasurementBias"; "NpBranchModel"];
expectedRowCount = zeros(numel(sheetName), 1);
actualRowCount = zeros(numel(sheetName), 1);
expectedColumnCount = zeros(numel(sheetName), 1);
actualColumnCount = zeros(numel(sheetName), 1);
passed = false(numel(sheetName), 1);
detail = strings(numel(sheetName), 1);
for i = 1:numel(sheetName)
    expected = formal.(char(sheetName(i)));
    actual = readtable(filePath, 'Sheet', char(sheetName(i)), ...
        'PreserveVariableNames', true);
    expectedRowCount(i) = height(expected);
    actualRowCount(i) = height(actual);
    expectedColumnCount(i) = width(expected);
    actualColumnCount(i) = width(actual);
    [passed(i), detail(i)] = ...
        local_m3_table_readback_matches(expected, actual);
end
audit = table(sheetName, expectedRowCount, actualRowCount, ...
    expectedColumnCount, actualColumnCount, passed, detail, ...
    'VariableNames', {'sheet','expected_row_count','actual_row_count', ...
    'expected_column_count','actual_column_count','passed','detail'});
end

function [passed, detail] = local_m3_table_readback_matches(expected, actual)
passed = false;
if height(expected) ~= height(actual) || width(expected) ~= width(actual) || ...
        ~isequal(expected.Properties.VariableNames, ...
        actual.Properties.VariableNames)
    detail = sprintf('shape_or_header_mismatch expected=%dx%d actual=%dx%d', ...
        height(expected), width(expected), height(actual), width(actual));
    return;
end
for c = 1:width(expected)
    name = expected.Properties.VariableNames{c};
    left = expected.(name);
    right = actual.(name);
    if islogical(left)
        if ~(islogical(right) || isnumeric(right)) || ...
                any(logical(right(:)) ~= left(:))
            detail = "logical_mismatch:" + string(name);
            return;
        end
    elseif isnumeric(left)
        if ~isnumeric(right) || ~isequal(size(left), size(right)) || ...
                any(isnan(left(:)) ~= isnan(right(:))) || ...
                any(isinf(left(:)) ~= isinf(right(:)))
            detail = "numeric_shape_or_empty_mismatch:" + string(name);
            return;
        end
        finite = isfinite(left) & isfinite(right);
        tolerance = 1e-12 + 1e-12 * abs(left(finite));
        if any(abs(left(finite) - right(finite)) > tolerance)
            detail = "numeric_tolerance_mismatch:" + string(name);
            return;
        end
    else
        leftText = string(left);
        rightText = string(right);
        leftText(ismissing(leftText)) = "";
        rightText(ismissing(rightText)) = "";
        if ~isequal(leftText, rightText)
            detail = "text_mismatch:" + string(name);
            return;
        end
    end
end
passed = true;
detail = "readback_equal";
end

function local_delete_exact_files(fileList)
for i = 1:numel(fileList)
    if exist(fileList{i}, 'file') == 2
        delete(fileList{i});
    end
end
end

function local_remove_partial_run_dirs( ...
        partialRunDir, partialReportDir, partialDeliveryDir, ...
        runRoot, reportRoot, deliveryRoot, partialLeaf)
% 失败恢复只清理本次UUID命名的partial目录；绝不接受宽目录或通配符。
local_remove_exact_partial_dir(partialRunDir, runRoot, partialLeaf);
local_remove_exact_partial_dir(partialReportDir, reportRoot, partialLeaf);
local_remove_exact_partial_dir(partialDeliveryDir, deliveryRoot, partialLeaf);
end

function local_remove_exact_partial_dir(targetDir, expectedRoot, partialLeaf)
if exist(targetDir, 'dir') ~= 7
    return;
end
expected = fullfile(expectedRoot, partialLeaf);
targetCanonical = local_canonical_file_name(targetDir);
expectedCanonical = local_canonical_file_name(expected);
validLeaf = startsWith(partialLeaf, '.') && endsWith(partialLeaf, '.partial') && ...
    isempty(regexp(partialLeaf, '[\\/:]', 'once'));
if ~validLeaf || ~strcmpi(targetCanonical, expectedCanonical)
    warning('SHT:SteadyAdaptV2:UnsafePartialCleanupRefused', ...
        'partial目录不满足精确边界，拒绝清理：%s。', targetDir);
    return;
end
[removed, message] = rmdir(targetDir, 's');
if ~removed
    warning('SHT:SteadyAdaptV2:PartialCleanupFailure', ...
        '无法清理本次partial目录%s：%s。', targetDir, message);
end
end

function local_remove_exact_published_dir(targetDir, expectedRoot, runId)
% 仅回滚本次尚未完成三目录提交的精确runId目录，绝不处理既有运行。
if exist(targetDir, 'dir') ~= 7
    return;
end
expected = fullfile(expectedRoot, runId);
validRunId = ~isempty(regexp(runId, ...
    '^[A-Za-z0-9][A-Za-z0-9_-]*$', 'once'));
if ~validRunId || ~strcmpi(local_canonical_file_name(targetDir), ...
        local_canonical_file_name(expected))
    warning('SHT:SteadyAdaptV2:UnsafePublishedRollbackRefused', ...
        '提交回滚目标未通过精确runId边界门：%s。', targetDir);
    return;
end
[removed, message] = rmdir(targetDir, 's');
if ~removed
    warning('SHT:SteadyAdaptV2:PublishedRollbackFailure', ...
        '无法回滚本次未完成提交目录%s：%s。', targetDir, message);
end
end

function info = local_publish_existing_deterministic_delivery(result)
%LOCAL_PUBLISH_EXISTING_DETERMINISTIC_DELIVERY
% 使用已完成的不可变MAT run重建固定Excel交付物。该入口只用于
% 交付合同升级和结构回归，不重算参数，也不修改MAT侧车。
required = {'route','runId','stageDParameterization','finalSchedule', ...
    'nodeContract','deterministicContractHash','nodeContractHash', ...
    'identity','options','acceptance'};
if ~isstruct(result) || ~all(isfield(result, required)) || ...
        ~strcmp(result.stageDParameterization, 'actual_execution_nodes')
    error('SHT:SteadyAdaptV2:BadExistingDeliveryResult', ...
        '重建Excel需要完整的M3不可变结果。');
end
if ~local_result_delivery_eligible(result)
    error('SHT:SteadyAdaptV2:ExistingResultNotDeliverable', ...
        '已有结果的调度结构或最终回放无效，不能生成交付Excel。');
end
paths = local_paths(result.options);
deliveryRoot = fullfile(paths.middleDataDir, 'steady_model_2p4_delivery');
if exist(deliveryRoot, 'dir') ~= 7
    mkdir(deliveryRoot);
end
routeTag = local_route_tag(result.route);
targetFile = fullfile(deliveryRoot, sprintf( ...
    '2p4_deterministic_%s.xlsx', routeTag));
publishId = char(java.util.UUID.randomUUID());
partialLeaf = sprintf('.delivery.%s.partial', publishId);
partialDir = fullfile(deliveryRoot, partialLeaf);
if ~mkdir(partialDir)
    error('SHT:SteadyAdaptV2:ExistingDeliveryPartialCreateFailure', ...
        '无法创建Excel重建临时目录。');
end
cleanupObject = onCleanup(@() local_remove_exact_partial_dir( ...
    partialDir, deliveryRoot, partialLeaf));
stagedFile = fullfile(partialDir, sprintf( ...
    '2p4_deterministic_%s.xlsx', routeTag));
audit = local_write_result_excel(stagedFile, result);
local_publish_fixed_delivery_workbook(stagedFile, targetFile, publishId);
local_remove_exact_partial_dir(partialDir, deliveryRoot, partialLeaf);
clear cleanupObject;
info = struct('route', result.route, 'runId', result.runId, ...
    'workbookFile', targetFile, 'fileSha256', audit.fileSha256, ...
    'semanticPayloadSha256', audit.semanticPayloadSha256, ...
    'solverConverged', local_result_solver_converged(result), ...
    'published', true);
end

function local_publish_fixed_delivery_workbook(stagedFile, targetFile, publishId)
% 先完成临时工作簿的写后读回与哈希，再替换固定目标。如替换
% 途中失败，精确恢复上一份工作簿，不删除其他文件。
stagedSha = [stagedFile '.sha256'];
targetSha = [targetFile '.sha256'];
if exist(stagedFile, 'file') ~= 2 || exist(stagedSha, 'file') ~= 2
    error('SHT:SteadyAdaptV2:StagedDeliveryMissing', ...
        '临时Excel或SHA-256旁车不完整。');
end
[targetDir, targetBase, targetExtension] = fileparts(targetFile);
if exist(targetDir, 'dir') ~= 7
    error('SHT:SteadyAdaptV2:DeliveryTargetDirectoryMissing', ...
        '固定Excel交付目录不存在：%s。', targetDir);
end
stagedHash = local_file_hash(stagedFile);
fid = fopen(stagedSha, 'w', 'n', 'UTF-8');
if fid < 0
    error('SHT:SteadyAdaptV2:StagedDeliveryShaRewriteFailure', ...
        '无法更新固定Excel的SHA-256旁车内容。');
end
shaCleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s  %s\n', stagedHash, [targetBase targetExtension]);
clear shaCleanup;

backupFile = fullfile(targetDir, sprintf('.%s.%s.previous%s', ...
    targetBase, publishId, targetExtension));
backupSha = [backupFile '.sha256'];
if exist(backupFile, 'file') || exist(backupSha, 'file')
    error('SHT:SteadyAdaptV2:DeliveryBackupExists', ...
        '唯一Excel交付备份名称冲突。');
end
hadTarget = exist(targetFile, 'file') == 2;
hadTargetSha = exist(targetSha, 'file') == 2;
targetBackedUp = false;
targetShaBackedUp = false;
newTargetPublished = false;
newTargetShaPublished = false;
try
    if hadTarget
        [ok, message] = movefile(targetFile, backupFile);
        if ~ok
            error('SHT:SteadyAdaptV2:DeliveryBackupFailure', '%s', message);
        end
        targetBackedUp = true;
    end
    if hadTargetSha
        [ok, message] = movefile(targetSha, backupSha);
        if ~ok
            error('SHT:SteadyAdaptV2:DeliveryShaBackupFailure', '%s', message);
        end
        targetShaBackedUp = true;
    end
    [ok, message] = movefile(stagedFile, targetFile);
    if ~ok
        error('SHT:SteadyAdaptV2:DeliveryWorkbookReplaceFailure', '%s', message);
    end
    newTargetPublished = true;
    [ok, message] = movefile(stagedSha, targetSha);
    if ~ok
        error('SHT:SteadyAdaptV2:DeliveryShaReplaceFailure', '%s', message);
    end
    newTargetShaPublished = true;
    if ~strcmp(local_file_hash(targetFile), stagedHash)
        error('SHT:SteadyAdaptV2:DeliveryPostReplaceHashMismatch', ...
            '固定Excel替换后字节哈希不一致。');
    end
catch exception
    if newTargetPublished
        local_delete_exact_files({targetFile});
    end
    if newTargetShaPublished
        local_delete_exact_files({targetSha});
    end
    if targetBackedUp && exist(backupFile, 'file') == 2
        movefile(backupFile, targetFile);
    end
    if targetShaBackedUp && exist(backupSha, 'file') == 2
        movefile(backupSha, targetSha);
    end
    rethrow(exception);
end
local_delete_exact_files({backupFile, backupSha});
end

function local_save_result_atomic(targetFile, result, publishId)
% 同卷临时MAT写后读回，再以单文件替换发布latest/时间戳副本。
[folder, baseName, extension] = fileparts(targetFile);
if ~strcmpi(extension, '.mat') || exist(folder, 'dir') ~= 7
    error('SHT:SteadyAdaptV2:BadAtomicResultTarget', ...
        '原子结果目标必须是现有目录中的MAT文件：%s。', targetFile);
end
partialFile = fullfile(folder, sprintf('.%s.%s.partial.mat', ...
    baseName, publishId));
if exist(partialFile, 'file') || exist(partialFile, 'dir')
    error('SHT:SteadyAdaptV2:AtomicResultPartialExists', ...
        '唯一MAT partial目标已存在：%s。', partialFile);
end
cleanupObject = onCleanup(@() local_delete_exact_files({partialFile}));
save(partialFile, 'result', '-v7.3');
readback = load(partialFile, 'result');
if ~isfield(readback, 'result') || ...
        ~strcmp(readback.result.runId, result.runId) || ...
        ~strcmp(readback.result.deterministicContractHash, ...
        result.deterministicContractHash) || ...
        ~isfield(readback.result.acceptance, 'deliveryEligible') || ...
        ~readback.result.acceptance.deliveryEligible
    error('SHT:SteadyAdaptV2:AtomicResultReadbackFailure', ...
        'MAT partial写后读回未通过runId/合同/可交付结构门。');
end
[moved, message] = movefile(partialFile, targetFile, 'f');
if ~moved
    error('SHT:SteadyAdaptV2:AtomicResultPublishFailure', ...
        'MAT结果原子发布失败：%s。', message);
end
clear cleanupObject;
end

function canonical = local_canonical_file_name(fileName)
fileObject = javaObject('java.io.File', char(fileName));
canonical = char(fileObject.getCanonicalPath());
end

function tbl = local_m3_manifest_table( ...
        result, semanticHash, completedAt, correctionRowCount, biasRowCount)
deliveryEligible = local_result_delivery_eligible(result);
deliveryStatus = "NOT_DELIVERABLE";
if deliveryEligible
    deliveryStatus = "DELIVERED";
end
solverConverged = local_result_solver_converged(result);
qualityStatus = "NOT_CONVERGED_DIAGNOSTIC";
if solverConverged
    qualityStatus = "CONVERGED";
end
gcvLambda = NaN;
if isfield(result.stageRefine, 'gcvRecommendedRegularizationStrength')
    gcvLambda = result.stageRefine.gcvRecommendedRegularizationStrength;
end
internalMat = fullfile('MiddleData', 'steady_model_adapt_v2_runs', ...
    result.runId, 'result.mat');
dictionaryId="SHT_2P4_10_ESTIMATED_HEALTH_PLUS_DIRECT_INLET_AND_WF_BIAS_V1";
if result.options.modelMode==0
    internalMat=fullfile('MiddleData','three_component','steady_model_adapt_v2_runs',result.runId,'result.mat');
    dictionaryId="TC24_11_ESTIMATED_HEALTH_PLUS_WF_BIAS_V1";
end
tbl = table("SHT_2P4_DETERMINISTIC_EXCEL_DELIVERY_V3", "2.4", "M3", ...
    string(result.runId), string(result.route), string(result.createdAt), ...
    string(completedAt), deliveryStatus, qualityStatus, ...
    solverConverged, false, string(result.stageRefine.stopReason), ...
    string(result.options.stageDRegularizationMethod), ...
    result.options.stageDM3RegularizationStrength, gcvLambda, ...
    result.options.modelMode, result.options.inletBoundaryMode, ...
    dictionaryId, ...
    string(result.finalSchedule.schemaVersion), ...
    string(result.finalSchedule.interpolation), ...
    string(result.finalSchedule.extrapolation), correctionRowCount, ...
    biasRowCount, string(semanticHash), ...
    string(result.deterministicContractHash), ...
    string(result.nodeContractHash), ...
    string(result.identity.trainingDataSha256), ...
    logical(result.identity.testDataReadDuringInference), ...
    logical(result.identity.hiddenTruthReadDuringInference), ...
    logical(result.identity.codeAndRuntimeStableDuringInference), ...
    string(internalMat), ...
    'VariableNames', {'schema_version','stage_id','method_id','run_id', ...
    'route','started_at','completed_at','delivery_status', ...
    'result_quality_status','solver_converged', ...
    'convergence_is_delivery_gate','stop_reason', ...
    'regularization_method','configured_lambda','gcv_recommended_lambda', ...
    'model_mode','inlet_boundary_mode','parameter_dictionary_id', ...
    'schedule_schema_version','interpolation','endpoint_policy', ...
    'correction_schedule_row_count','measurement_bias_row_count', ...
    'semantic_payload_sha256','deterministic_contract_sha256', ...
    'node_contract_sha256','training_data_sha256', ...
    'test_data_used_for_inference','hidden_truth_used_for_inference', ...
    'code_and_runtime_stable_during_inference', ...
    'internal_mat_relative_path'});
executionOptions=local_complete_options(result.options,result.route);
tbl.steady_load_boundary=string(executionOptions.steadyLoadBoundaryMode);
tbl.steady_use_measured_power=logical(executionOptions.steadyUseMeasuredPower);
tbl.steady_solver=string(executionOptions.steadySolver);
tbl.shaft_load_input_mode=executionOptions.shaftLoadInputMode;
tbl.np_selection_policy=string(executionOptions.steadyNpSelectionPolicy);
end

function tbl = local_m3_correction_schedule_table(result)
% 传递完整发动机修正模型：包括模式4直接反算的进气道压损
% 曲线、9条联合辨识调度曲线和常值Nozzle_K_A8。
schedule = result.finalSchedule;
record = repmat(struct('correction_name', "", 'c_index', NaN, ...
    'schedule_kind', "", 'axis_name', "", 'axis_unit', "", ...
    'node_index', NaN, 'coordinate', NaN, 'correction_value', NaN, ...
    'correction_unit', "1", 'interpolation', "", ...
    'endpoint_policy', "", 'zero_anchor', false, ...
    'lower_bound', NaN, 'upper_bound', NaN, 'source_method', "", ...
    'node_role', ""), 0, 1);
for i = 1:numel(schedule.healthEntries)
    entry = schedule.healthEntries(i);
    sourceMethod = "joint_parameter_estimation";
    if entry.cIndex == 0 && result.options.inletBoundaryMode==4
        sourceMethod = "direct_inlet_equation_inversion";
    end
    for j = 1:numel(entry.xNodes)
        one = struct('correction_name', string(entry.name), ...
            'c_index', entry.cIndex, 'schedule_kind', "scheduled", ...
            'axis_name', string(entry.axisName), ...
            'axis_unit', local_schedule_axis_unit(entry.axisName), ...
            'node_index', j, 'coordinate', entry.xNodes(j), ...
            'correction_value', entry.kNodes(j), ...
            'correction_unit', "1", ...
            'interpolation', string(schedule.interpolation), ...
            'endpoint_policy', string(schedule.extrapolation), ...
            'zero_anchor', logical(entry.pressureLoss && j == 1), ...
            'lower_bound', entry.lowerBound, ...
            'upper_bound', entry.upperBound, ...
            'source_method', sourceMethod, 'node_role', "estimated");
        if one.zero_anchor
            one.node_role = "fixed_zero_anchor";
        end
        record(end + 1, 1) = one; %#ok<AGROW>
    end
end
nozzleRow = find(result.parameterDefinition.c_index == 15, 1);
if isempty(nozzleRow)
    error('SHT:SteadyAdaptV2:DeliveryNozzleDefinitionMissing', ...
        '正式Excel缺少Nozzle_K_A8参数定义。');
end
record(end + 1, 1) = struct('correction_name', "Nozzle_K_A8", ...
    'c_index', 15, 'schedule_kind', "constant", ...
    'axis_name', "constant", 'axis_unit', "1", 'node_index', 1, ...
    'coordinate', 0, 'correction_value', schedule.h15, ...
    'correction_unit', "1", 'interpolation', "constant", ...
    'endpoint_policy', "constant", 'zero_anchor', false, ...
    'lower_bound', result.parameterDefinition.lower_bound(nozzleRow), ...
    'upper_bound', result.parameterDefinition.upper_bound(nozzleRow), ...
    'source_method', "joint_parameter_estimation", ...
    'node_role', "estimated");
tbl = struct2table(record);
% 恢复DLL的K_des+Delta节点约定需要同一参考横坐标，不依赖设计MAT。
tbl.design_coordinate = zeros(height(tbl),1);
for i=1:numel(schedule.healthEntries)
    use=tbl.c_index==schedule.healthEntries(i).cIndex;
    tbl.design_coordinate(use)=schedule.healthEntries(i).designCoordinate;
end
[~, order] = sortrows([tbl.c_index, tbl.node_index], [1, 2]);
tbl = tbl(order, :);
expectedCIndex = [0; 1; 2; 6; 7; 8; 10; 11; 12; 14; 15];
if ~isequal(unique(tbl.c_index), expectedCIndex) || ...
        any(~isfinite(tbl.coordinate)) || ...
        any(~isfinite(tbl.correction_value))
    error('SHT:SteadyAdaptV2:IncompleteCorrectionDelivery', ...
        '正式Excel修正系数调度不完整或存在非有限值。');
end
end

function tbl = local_m3_measurement_bias_table(result)
fuel = result.finalSchedule.fuelBias;
n = numel(fuel.xNodes);
if n < 1 || n ~= numel(fuel.biasNodes) || ...
        any(~isfinite(fuel.xNodes)) || any(~isfinite(fuel.biasNodes)) || ...
        any(diff(fuel.xNodes) <= 0)
    error('SHT:SteadyAdaptV2:InvalidFuelBiasDelivery', ...
        '正式Excel的Wf_bias节点无效。');
end
fuelClass = result.parameterClassTable( ...
    string(result.parameterClassTable.name) == "Wf_bias", :);
if height(fuelClass) ~= 1
    error('SHT:SteadyAdaptV2:FuelBiasClassMissing', ...
        '正式Excel缺少唯一Wf_bias物理类别。');
end
tbl = table(repmat("Wf_bias", n, 1), ...
    repmat("fuel_flow_measurement_bias", n, 1), ...
    repmat(string(fuel.axisName), n, 1), repmat("1", n, 1), ...
    (1:n).', fuel.xNodes(:), fuel.biasNodes(:), repmat("kg/s", n, 1), ...
    repmat(string(result.finalSchedule.interpolation), n, 1), ...
    repmat(string(result.finalSchedule.extrapolation), n, 1), ...
    repmat(fuelClass.lower_bound, n, 1), ...
    repmat(fuelClass.upper_bound, n, 1), ...
    repmat(fuel.wfDesign, n, 1), ...
    repmat("joint_parameter_estimation", n, 1), ...
    'VariableNames', {'bias_name','bias_type','axis_name','axis_unit', ...
    'node_index','coordinate','bias_value','bias_unit','interpolation', ...
    'endpoint_policy','lower_bound','upper_bound','reference_value', ...
    'source_method'});
end

function unit = local_schedule_axis_unit(axisName)
axisName = string(axisName);
if contains(axisName, "corrected_mass_flow")
    unit = "kg/s";
else
    unit = "1";
end
end

function value = local_result_solver_converged(result)
value = isfield(result, 'acceptance') && ...
    isfield(result.acceptance, 'allStagesConverged') && ...
    logical(result.acceptance.allStagesConverged);
end

function value = local_result_delivery_eligible(result)
if isfield(result, 'acceptance') && ...
        isfield(result.acceptance, 'deliveryEligible')
    value = logical(result.acceptance.deliveryEligible);
    return;
end
% 兼容已冻结的旧M3 run：不使用formalAccepted，只检查调度结构
% 和最终DLL回放是否可用。
value = isfield(result, 'nodeContract') && ...
    isfield(result.nodeContract, 'roundTripPassed') && ...
    logical(result.nodeContract.roundTripPassed) && ...
    all(isfinite(result.nodeContract.centerVector));
if isfield(result, 'acceptance') && ...
        isfield(result.acceptance, 'trainingReplayValid')
    value = value && logical(result.acceptance.trainingReplayValid);
end
if isfield(result, 'input') && isfield(result.input, 'testDataAvailable') && ...
        logical(result.input.testDataAvailable) && ...
        isfield(result.acceptance, 'testReplayValid')
    value = value && logical(result.acceptance.testReplayValid);
end
end

function tbl = local_m3_schedule_nodes_workbook_table(result) %#ok<DEFNU>
contract = result.nodeContract;
active = contract.parameterTable;
fixed = contract.fixedAnchorTable;
nActive = height(active);
nFixed = height(fixed);
nodeRole = [repmat("active_execution_node", nActive, 1); ...
    repmat("fixed_or_excluded", nFixed, 1)];
order = [active.index; nan(nFixed, 1)];
nodeId = [active.node_id; "fixed_" + string((1:nFixed).')];
baseName = [active.base_name; fixed.base_name];
cIndex = [active.c_index; fixed.c_index];
groupKind = [active.group_kind; repmat("fixed_or_excluded", nFixed, 1)];
dllNodeIndex = [active.dll_node_index; fixed.node_index];
nodeIndex = [active.node_index; fixed.node_index];
coordinate = [active.coordinate; fixed.coordinate];
axisName = [active.axis_name; fixed.axis_name];
unit = [active.unit; repmat("1", nFixed, 1)];
estimatedValue = [active.center_value; fixed.value];
priorCenterValue = [result.finalPriorCenterNodeContract.centerVector; ...
    nan(nFixed, 1)];
selectedDeltaFromPrior = [active.center_value - ...
    result.finalPriorCenterNodeContract.centerVector; nan(nFixed, 1)];
finalAppliedUpdate = result.stageRefine.fullRegularizedUpdate(:);
linearizationCenterActive = ...
    result.stageRefine.linearizationNodeContract.centerVector(:);
if numel(finalAppliedUpdate) ~= nActive || ...
        numel(linearizationCenterActive) ~= nActive
    error('SHT:SteadyAdaptV2:M3WorkbookFullUpdateDimensionMismatch', ...
        '正式工作簿线性化中心/完整更新向量与活动节点数不一致。');
end
linearizationCenterValue = [linearizationCenterActive; ...
    nan(nFixed, 1)];
finalAppliedUpdate = [finalAppliedUpdate; nan(nFixed, 1)];
lowerBound = [active.lower_bound; nan(nFixed, 1)];
upperBound = [active.upper_bound; nan(nFixed, 1)];
priorSigma = [active.prior_sigma; nan(nFixed, 1)];
differenceStep = [active.difference_step; nan(nFixed, 1)];
executionNode = [active.execution_node; false(nFixed, 1)];
fixedReason = [repmat("", nActive, 1); fixed.reason];
tbl = table(nodeRole, order, nodeId, baseName, cIndex, groupKind, ...
    dllNodeIndex, nodeIndex, coordinate, axisName, unit, estimatedValue, ...
    priorCenterValue, linearizationCenterValue, selectedDeltaFromPrior, ...
    finalAppliedUpdate, ...
    lowerBound, upperBound, priorSigma, differenceStep, executionNode, ...
    fixedReason, ...
    'VariableNames', {'node_role','parameter_order','node_id','base_name', ...
    'c_index','group_kind','dll_node_index','node_index','coordinate', ...
    'axis_name','unit','estimated_value','prior_center_value', ...
    'linearization_center_value','selected_delta_from_prior', ...
    'final_applied_update','lower_bound','upper_bound', ...
    'prior_sigma','difference_step','execution_node','fixed_reason'});
end

function tbl = local_m3_audit_workbook_table(stageRefine) %#ok<DEFNU>
tbl = stageRefine.perturbationAudit;
n = height(tbl);
isFinal = true(n, 1);
if ismember('stage_pass', tbl.Properties.VariableNames)
    isFinal = isFinal & tbl.stage_pass == tbl.stage_pass(end);
end
if ismember('continuation_stage', tbl.Properties.VariableNames)
    finalContinuationStage = max(tbl.continuation_stage(isFinal));
    isFinal = isFinal & ...
        tbl.continuation_stage == finalContinuationStage;
end
if ismember('linearization_pass', tbl.Properties.VariableNames)
    finalLinearization = max(tbl.linearization_pass(isFinal));
    isFinal = isFinal & tbl.linearization_pass == finalLinearization;
end
rawNorm = sqrt(sum(stageRefine.rawDataJacobian .^ 2, 1)).';
whiteNorm = sqrt(sum(stageRefine.whitenedDataJacobian .^ 2, 1)).';
scaledNorm = sqrt(sum(stageRefine.parameterScaledJacobian .^ 2, 1)).';
if sum(isFinal) ~= numel(rawNorm)
    error('SHT:SteadyAdaptV2:M3AuditFinalJacobianDimensionMismatch', ...
        'M3Audit的最终扰动行数与最终Jacobian列数不一致。');
end
tbl.raw_derivative_norm = nan(n, 1);
tbl.whitened_derivative_norm = nan(n, 1);
tbl.parameter_scaled_derivative_norm = nan(n, 1);
tbl.raw_derivative_norm(isFinal) = rawNorm;
tbl.whitened_derivative_norm(isFinal) = whiteNorm;
tbl.parameter_scaled_derivative_norm(isFinal) = scaledNorm;
tbl.final_jacobian_snapshot = isFinal;
end

function tbl = local_m3_fit_metrics_workbook_table(result) %#ok<DEFNU>
dataset = strings(0, 1);
model = strings(0, 1);
field = strings(0, 1);
rmse = zeros(0, 1);
normalizedRmse = zeros(0, 1);
meanAbsoluteError = zeros(0, 1);
meanAbsoluteRelativeErrorPct = zeros(0, 1);
validPointCount = zeros(0, 1);
status = strings(0, 1);
metricSet = {result.baseline.trainingMetrics, result.final.trainingMetrics};
modelName = ["uncorrected", "M3"];
for k = 1:numel(metricSet)
    one = metricSet{k};
    dataset(end + 1, 1) = "training"; %#ok<AGROW>
    model(end + 1, 1) = modelName(k); %#ok<AGROW>
    field(end + 1, 1) = "overall"; %#ok<AGROW>
    rmse(end + 1, 1) = NaN; %#ok<AGROW>
    normalizedRmse(end + 1, 1) = one.overall_nrms; %#ok<AGROW>
    meanAbsoluteError(end + 1, 1) = NaN; %#ok<AGROW>
    meanAbsoluteRelativeErrorPct(end + 1, 1) = NaN; %#ok<AGROW>
    validPointCount(end + 1, 1) = one.valid_point_count; %#ok<AGROW>
    status(end + 1, 1) = "inference_training_evidence"; %#ok<AGROW>
    byField = one.byField;
    count = height(byField);
    dataset = [dataset; repmat("training", count, 1)]; %#ok<AGROW>
    model = [model; repmat(modelName(k), count, 1)]; %#ok<AGROW>
    field = [field; byField.field]; %#ok<AGROW>
    rmse = [rmse; byField.rmse]; %#ok<AGROW>
    normalizedRmse = [normalizedRmse; byField.normalized_rmse]; %#ok<AGROW>
    meanAbsoluteError = [meanAbsoluteError; ...
        byField.mean_absolute_error]; %#ok<AGROW>
    meanAbsoluteRelativeErrorPct = [meanAbsoluteRelativeErrorPct; ...
        byField.mean_absolute_relative_error_pct]; %#ok<AGROW>
    validPointCount = [validPointCount; ...
        repmat(one.valid_point_count, count, 1)]; %#ok<AGROW>
    status = [status; repmat("inference_training_evidence", ...
        count, 1)]; %#ok<AGROW>
end
if result.input.testDataAvailable
    testSet = {result.baseline.testMetrics, result.final.testMetrics};
    for k = 1:numel(testSet)
        one = testSet{k};
        count = height(one.byField);
        dataset = [dataset; "test"; repmat("test", count, 1)]; %#ok<AGROW>
        model = [model; modelName(k); repmat(modelName(k), count, 1)]; %#ok<AGROW>
        field = [field; "overall"; one.byField.field]; %#ok<AGROW>
        rmse = [rmse; NaN; one.byField.rmse]; %#ok<AGROW>
        normalizedRmse = [normalizedRmse; one.overall_nrms; ...
            one.byField.normalized_rmse]; %#ok<AGROW>
        meanAbsoluteError = [meanAbsoluteError; NaN; ...
            one.byField.mean_absolute_error]; %#ok<AGROW>
        meanAbsoluteRelativeErrorPct = [meanAbsoluteRelativeErrorPct; NaN; ...
            one.byField.mean_absolute_relative_error_pct]; %#ok<AGROW>
        validPointCount = [validPointCount; ...
            repmat(one.valid_point_count, count + 1, 1)]; %#ok<AGROW>
        status = [status; repmat("post_inference_validation", ...
            count + 1, 1)]; %#ok<AGROW>
    end
else
    dataset(end + 1, 1) = "test";
    model(end + 1, 1) = "M3";
    field(end + 1, 1) = "overall";
    rmse(end + 1, 1) = NaN;
    normalizedRmse(end + 1, 1) = NaN;
    meanAbsoluteError(end + 1, 1) = NaN;
    meanAbsoluteRelativeErrorPct(end + 1, 1) = NaN;
    validPointCount(end + 1, 1) = 0;
    status(end + 1, 1) = ...
        "deferred_to_frozen_post_inference_validation";
end
tbl = table(dataset, model, field, rmse, normalizedRmse, ...
    meanAbsoluteError, meanAbsoluteRelativeErrorPct, validPointCount, ...
    status, ...
    'VariableNames', {'dataset','model','field','rmse','normalized_rmse', ...
    'mean_absolute_error','mean_absolute_relative_error_pct', ...
    'valid_point_count','status'});
end

function tbl = local_m3_verification_workbook_table(result)
check = [ ...
    "formal_acceptance"; "physical_parameter_class_count"; ...
    "wf_bias_unit"; "node_round_trip"; "node_hash_consistency"; ...
    "strict_positive_central_replay"; "strict_negative_central_replay"; ...
    "h_half_stability"; "full_regularized_update"; ...
    "all_bounded_solution_kkt"; "linear_prediction_diagnostic_recorded"; ...
    "no_global_alpha"; "controlled_nonlinear_globalization"; ...
    "training_replay_valid"; "test_data_excluded_from_inference"; ...
    "hidden_truth_excluded_from_inference"; ...
    "prior_center_plus_delta_reconstructs_final"; ...
    "linearization_plus_full_update_reconstructs_final"];
if strcmpi(result.options.stageDRegularizationMethod, 'tsvd')
    check(10) = "all_tsvd_candidates_within_physical_bounds";
end
passed = [ ...
    result.acceptance.formalAccepted; ...
    height(result.parameterClassTable) == 11; ...
    result.parameterClassTable.unit(end) == "kg/s"; ...
    result.nodeContract.roundTripPassed; ...
    strcmp(result.nodeContractHash, result.nodeContract.nodeContractHash); ...
    all(result.stageRefine.perturbationAudit.positive_valid); ...
    all(result.stageRefine.perturbationAudit.negative_valid); ...
    result.stageRefine.stepStabilityPassed; ...
    result.stageRefine.fullUpdateAppliedWithoutGlobalScaling; ...
    result.stageRefine.allBoundedSolutionsPassed; ...
    isfinite(result.stageRefine.linearPredictionCheck.relativeResidualError) && ...
        result.stageRefine.linearPredictionCheck.diagnosticOnly; ...
    ~result.stageRefine.globalAlphaUsed; ...
    local_m3_damping_control_passed(result); ...
    result.acceptance.trainingReplayValid; ...
    ~result.identity.testDataReadDuringInference; ...
    ~result.identity.hiddenTruthReadDuringInference; ...
    max(abs(result.finalPriorCenterNodeContract.centerVector + ...
        (result.nodeContract.centerVector - ...
        result.finalPriorCenterNodeContract.centerVector) - ...
        result.nodeContract.centerVector)) <= 1e-12; ...
    max(abs(result.stageRefine.linearizationNodeContract.centerVector + ...
        result.stageRefine.fullRegularizedUpdate - ...
        result.nodeContract.centerVector)) <= 1e-12];
detail = [ ...
    string(result.acceptance.formalAccepted); ...
    string(height(result.parameterClassTable)); ...
    result.parameterClassTable.unit(end); ...
    sprintf('max_abs_error=%.3e', ...
        result.nodeContract.roundTripMaximumAbsoluteError); ...
    string(result.nodeContractHash); ...
    sprintf('count=%d', height(result.stageRefine.perturbationAudit)); ...
    sprintf('count=%d', height(result.stageRefine.perturbationAudit)); ...
    sprintf('max_relative_difference=%.3e', ...
        max(result.stageRefine.stepStability.relative_difference)); ...
    local_m3_regularization_verification_detail(result); ...
    local_m3_bound_verification_detail(result); ...
    sprintf('diagnostic_all_below_reference=%d,final_relative_error=%.3e,reference=%.3e', ...
        result.stageRefine.allLinearPredictionChecksPassed, ...
        result.stageRefine.linearPredictionCheck.relativeResidualError, ...
        result.stageRefine.linearPredictionCheck.relativeTolerance); ...
    string(result.stageRefine.globalAlphaUsed); ...
    local_m3_damping_control_detail(result); ...
    string(result.acceptance.trainingReplayValid); ...
    string(result.identity.testDataReadDuringInference); ...
    string(result.identity.hiddenTruthReadDuringInference); ...
    sprintf('max_abs_error=%.3e', max(abs( ...
        result.finalPriorCenterNodeContract.centerVector + ...
        (result.nodeContract.centerVector - ...
        result.finalPriorCenterNodeContract.centerVector) - ...
        result.nodeContract.centerVector))); ...
    sprintf('max_abs_error=%.3e', max(abs( ...
        result.stageRefine.linearizationNodeContract.centerVector + ...
        result.stageRefine.fullRegularizedUpdate - ...
        result.nodeContract.centerVector)))];
tbl = table(check, logical(passed), detail, ...
    'VariableNames', {'check','passed','detail'});
end

function passed = local_m3_damping_control_passed(result)
if ~result.stageRefine.lmDampingUsed
    passed = true;
    return;
end
method = string(result.options.stageDM3GlobalizationMethod);
controlledTrust = method == "regularized_trust_region" && ...
    isfield(result.stageRefine, 'regularizedTrustRegionUsed') && ...
    result.stageRefine.regularizedTrustRegionUsed;
controlledInexact = method == "regularizing_lm_inexact_newton" && ...
    isfield(result.stageRefine, 'regularizingInexactNewtonUsed') && ...
    result.stageRefine.regularizingInexactNewtonUsed;
passed = (controlledTrust || controlledInexact) && ...
    (~isfield(result.stageRefine, 'uncontrolledLmDampingUsed') || ...
    ~result.stageRefine.uncontrolledLmDampingUsed);
end

function detail = local_m3_damping_control_detail(result)
if ~result.stageRefine.lmDampingUsed
    detail = "algorithmic_damping_not_used";
elseif local_m3_damping_control_passed(result)
    if strcmp(result.options.stageDM3GlobalizationMethod, ...
            'regularizing_lm_inexact_newton')
        detail = "linearized_residual_ratio_controlled_inexact_newton";
    else
        detail = "exact_reduction_ratio_controlled_regularized_trust_region";
    end
else
    detail = "uncontrolled_algorithmic_damping_detected";
end
end

function detail = local_m3_regularization_verification_detail(result)
if strcmpi(result.options.stageDRegularizationMethod, 'tsvd')
    detail = sprintf('retained=%d,truncated=%d,retained_condition=%.6g', ...
        result.stageRefine.retainedSingularValueCount, ...
        result.stageRefine.truncatedSingularValueCount, ...
        result.stageRefine.retainedConditionNumber);
else
    detail = string(result.stageRefine.selectedRegularizationStrength);
end
end

function detail = local_m3_bound_verification_detail(result)
if strcmpi(result.options.stageDRegularizationMethod, 'tsvd')
    detail = sprintf('all_passed=%d,min_relative_margin=%.3e', ...
        result.stageRefine.allBoundedSolutionsPassed, ...
        result.stageRefine.minimumRelativeBoundMargin);
else
    detail = sprintf('all_passed=%d,final_relative_kkt=%.3e', ...
        result.stageRefine.allBoundedSolutionsPassed, ...
        result.stageRefine.boundedSolution.relativeKktStationarityResidual);
end
end

function tbl = local_m3_workbook_verification_table( ...
        result, semanticHash, firstReadback, secondReadback) %#ok<DEFNU>
core = local_m3_verification_workbook_table(result);
checkId = string(core.check);
category = repmat("formal_gate", height(core), 1);
expected = repmat("true", height(core), 1);
actual = string(core.detail);
tolerance = repmat("contract_defined", height(core), 1);
passed = logical(core.passed);
blocking = true(height(core), 1);
failure = strings(height(core), 1);
failure(~passed) = "formal_gate_failed";
% 显式关闭requireConvergedStages的专项扫描允许保存未收敛诊断run。
% 它仍保留formal_acceptance=false，但该行不阻断工作簿原子写入，且
% 外层不会发布到正式latest。
formalRow = checkId == "formal_acceptance";
if ~result.options.requireConvergedStages
    category(formalRow) = "diagnostic_status";
    expected(formalRow) = "recorded_without_latest_publication";
    blocking(formalRow) = false;
    failure(formalRow) = "";
end

readbackSet = {firstReadback, secondReadback};
readbackLabel = ["first_write_readback", "second_reopen_readback"];
for k = 1:numel(readbackSet)
    audit = readbackSet{k};
    if isempty(audit)
        continue;
    end
    for i = 1:height(audit)
        checkId(end + 1, 1) = readbackLabel(k) + "_" + ...
            lower(audit.sheet(i)); %#ok<AGROW>
        category(end + 1, 1) = "workbook_readback"; %#ok<AGROW>
        expected(end + 1, 1) = sprintf('%dx%d', ...
            audit.expected_row_count(i), ...
            audit.expected_column_count(i)); %#ok<AGROW>
        actual(end + 1, 1) = sprintf('%dx%d;%s', ...
            audit.actual_row_count(i), audit.actual_column_count(i), ...
            audit.detail(i)); %#ok<AGROW>
        tolerance(end + 1, 1) = "abs<=1e-12+1e-12*abs(reference)"; %#ok<AGROW>
        passed(end + 1, 1) = audit.passed(i); %#ok<AGROW>
        blocking(end + 1, 1) = true; %#ok<AGROW>
        if audit.passed(i)
            failure(end + 1, 1) = ""; %#ok<AGROW>
        else
            failure(end + 1, 1) = audit.detail(i); %#ok<AGROW>
        end
    end
end
checkId(end + 1, 1) = "semantic_payload_sha256";
category(end + 1, 1) = "semantic_identity";
expected(end + 1, 1) = string(semanticHash);
actual(end + 1, 1) = string(semanticHash);
tolerance(end + 1, 1) = "exact_sha256";
passed(end + 1, 1) = true;
blocking(end + 1, 1) = true;
failure(end + 1, 1) = "";
tbl = table(checkId, category, expected, actual, tolerance, passed, ...
    blocking, failure, ...
    'VariableNames', {'check_id','category','expected','actual', ...
    'tolerance','passed','blocking','failure'});
end

function local_write_residual_weighting_excel(filePath, weighting)
writetable(weighting.diagnosticTable, filePath, ...
    'Sheet', 'residual_weighting');
variableNames = matlab.lang.makeUniqueStrings( ...
    matlab.lang.makeValidName(cellstr(weighting.names)));
covarianceTable = array2table(weighting.covariance, ...
    'VariableNames', variableNames);
covarianceTable = addvars(covarianceTable, weighting.names, ...
    'Before', 1, 'NewVariableNames', 'name');
writetable(covarianceTable, filePath, 'Sheet', 'residual_covariance');
correlationTable = array2table(weighting.correlation, ...
    'VariableNames', variableNames);
correlationTable = addvars(correlationTable, weighting.names, ...
    'Before', 1, 'NewVariableNames', 'name');
writetable(correlationTable, filePath, 'Sheet', 'residual_correlation');
end

function files = local_plot_result(result, paths, stamp)
files = strings(0, 1);
routeTag = local_route_tag(result.route);

fig1 = figure('Visible', result.options.figureVisible, ...
    'Color', 'w', 'Position', [100, 100, 1100, 480]);
fields = result.final.trainingMetrics.byField.field;
trainValues = [result.baseline.trainingMetrics.byField.normalized_rmse, ...
    result.final.trainingMetrics.byField.normalized_rmse];
if result.input.testDataAvailable
    subplot(1, 2, 1);
end
bar(trainValues);
set(gca, 'XTick', 1:numel(fields), 'XTickLabel', cellstr(fields));
xtickangle(35); grid on;
ylabel('归一化RMSE'); title('训练集');
legend({'零修正','估计修正'}, 'Location', 'best');
if result.input.testDataAvailable
    testValues = [result.baseline.testMetrics.byField.normalized_rmse, ...
        result.final.testMetrics.byField.normalized_rmse];
    subplot(1, 2, 2);
    bar(testValues);
    set(gca, 'XTick', 1:numel(fields), 'XTickLabel', cellstr(fields));
    xtickangle(35); grid on;
    ylabel('归一化RMSE'); title('独立测试集');
    legend({'零修正','估计修正'}, 'Location', 'best');
end
sgtitle([result.routeLabel '：模型修正前后输出误差']);
file1 = fullfile(paths.reportOutputDir, ...
    ['steady_model_adapt_v2_' routeTag '_' stamp '_prediction_error.png']);
saveas(fig1, file1); close(fig1);
files(end + 1, 1) = string(file1);

fig2 = figure('Visible', result.options.figureVisible, ...
    'Color', 'w', 'Position', [80, 40, 1250, 900]);
for i = 1:numel(result.finalSchedule.healthEntries)
    entry = result.finalSchedule.healthEntries(i);
    subplot(5, 2, i);
    plot(entry.xNodes, entry.kNodes, '-o', 'LineWidth', 1.3, ...
        'MarkerSize', 4);
    grid on; xlabel(strrep(entry.axisName, '_', '\_'));
    ylabel('K_{eff}'); title(sprintf('h%d %s', ...
        entry.cIndex, strrep(entry.name, '_', '\_')));
end
sgtitle([result.routeLabel '：10个估计健康调度函数']);
file2 = fullfile(paths.reportOutputDir, ...
    ['steady_model_adapt_v2_' routeTag '_' stamp '_health_schedules.png']);
saveas(fig2, file2); close(fig2);
files(end + 1, 1) = string(file2);

fig3 = figure('Visible', result.options.figureVisible, ...
    'Color', 'w', 'Position', [100, 100, 720, 460]);
plot(result.finalSchedule.fuelBias.xNodes, ...
    result.finalSchedule.fuelBias.biasNodes, '-o', ...
    'LineWidth', 1.5, 'MarkerSize', 5);
grid on; xlabel('Wf_{meas}/Wf_{des}'); ylabel('b_{Wf} (kg/s)');
title([result.routeLabel '：燃油测量偏置调度函数']);
file3 = fullfile(paths.reportOutputDir, ...
    ['steady_model_adapt_v2_' routeTag '_' stamp '_wf_bias_schedule.png']);
saveas(fig3, file3); close(fig3);
files(end + 1, 1) = string(file3);
end

function local_write_summary(filePath, result)
fid = fopen(filePath, 'w', 'n', 'UTF-8');
if fid < 0
    error('SHT:SteadyAdaptV2:SummaryWriteFailure', ...
        '无法写入摘要：%s。', filePath);
end
cleanupObject = onCleanup(@() fclose(fid));
fprintf(fid, '# %d部件稳态修正系数辨识结果摘要\n\n',3+3*result.options.modelMode);
fprintf(fid, '- 路径：%s\n', result.routeLabel);
fprintf(fid, '- 生成时间：%s\n', result.createdAt);
fprintf(fid, '- runId：`%s`\n', result.runId);
fprintf(fid, '- 确定性合同SHA-256：`%s`\n', ...
    result.deterministicContractHash);
fprintf(fid, '- 训练点/测试点：%d/%d\n', ...
    result.input.trainingPointCount, result.input.testPointCount);
if result.npBranchPrior.enabled
    fprintf(fid, '- 稳态Np合理分支选择：启用\n');
    fprintf(fid, '- 训练Np仅用于训练点物理解选择：1\n');
    fprintf(fid, '- 训练内部留一Np误差RMS：%.4f%%\n', ...
        100 * result.npBranchPrior.trainingPrior.leaveOneOutRmsRelative);
    fprintf(fid, '- 训练物理解分支门相对半宽：%.4f%%\n', ...
        100 * result.npBranchPrior.trainingRootSelectionRelativeHalfWidth);
    fprintf(fid, '- 测试预测Np容许带相对半宽：%.4f%%\n', ...
        100 * result.npBranchPrior.trainingPrior.relativeHalfWidth);
    fprintf(fid, '- 稳态负载边界：候选转速与Mkp/Mkg实时换算功率\n');
end
fprintf(fid, '- AC转速分组数：%d\n', height(result.groups));
if isfield(result, 'scheduleStabilization')
    d = result.scheduleStabilization;
    fprintf(fid, '- 阶段C可行性备用分支：%s；形状保留=%.6g，绝对幅值保留=%.6g\n', ...
        char(d.strategy), d.shapeScale, d.absoluteScale);
    if isfield(d, 'message')
        fprintf(fid, '- 阶段C说明：%s\n', d.message);
    end
end
fprintf(fid, '- 冻结残差权重方法：%s\n', ...
    result.residualWeighting.method);
fprintf(fid, '- 残差权重冻结时刻：%s\n', ...
    result.residualWeighting.frozenAt);
fprintf(fid, '- 全协方差收缩强度：%.8g\n', ...
    result.residualWeighting.shrinkageIntensity);
fprintf(fid, '- 设计点归一化加一致白化的代价相对差：%.3e\n', ...
    result.residualWeighting.normalizationEquivalence.relativeCostDifference);
fprintf(fid, '- 阶段A正则化方法：%s\n', ...
    result.options.stageARegularizationMethod);
if strcmpi(result.options.stageARegularizationMethod, 'tsvd')
    fprintf(fid, '- 阶段A生效的TSVD步长模式：%s\n', ...
        result.options.stageATsvdStepMode);
    fprintf(fid, '- 阶段A截断/保留奇异方向：%d/%d\n', ...
        result.stageA.truncatedSingularValueCount, ...
        result.stageA.retainedSingularValueCount);
elseif strcmpi(result.options.stageARegularizationMethod, 'tikhonov')
    fprintf(fid, '- 阶段A生效的Tikhonov先验尺度统一倍率：%.8g\n', ...
        result.options.stageATikhonovPriorScale);
end
fprintf(fid, '- 阶段B正则化方法：%s\n', ...
    result.options.stageBRegularizationMethod);
if strcmpi(result.options.stageBRegularizationMethod, 'tikhonov')
    if isfield(result.options,'stageBTikhonovPriorScaleByGroupSize') && ...
            ~isempty(result.options.stageBTikhonovPriorScaleByGroupSize)
        fprintf(fid, '- 阶段B先验尺度倍率[单工况, 多工况]：[%.8g, %.8g]，越小正则越强。\n', ...
            result.options.stageBTikhonovPriorScaleByGroupSize);
    else
        fprintf(fid, '- 阶段B生效的Tikhonov先验尺度统一倍率：%.8g\n', ...
            result.options.stageBTikhonovPriorScale);
    end
elseif strcmpi(result.options.stageBRegularizationMethod, 'tsvd')
    fprintf(fid, '- 阶段B生效的无阻尼TSVD保留奇异方向：%d\n', ...
        result.options.stageBTsvdRetainedCount);
end
fprintf(fid, '- 阶段D正则化方法：%s\n', ...
    result.options.stageDRegularizationMethod);
if strcmpi(result.options.stageDRegularizationMethod, 'tikhonov')
    fprintf(fid, '- 阶段D生效的Tikhonov先验尺度统一倍率：%.8g\n', ...
        result.options.stageDTikhonovPriorScale);
elseif strcmpi(result.options.stageDRegularizationMethod, 'tsvd')
    fprintf(fid, '- 阶段D生效的无阻尼TSVD保留奇异方向：%d\n', ...
        result.options.stageDTsvdRetainedCount);
end
fprintf(fid, '- 阶段D参数化：%s\n', result.stageDParameterization);
fprintf(fid, '- 阶段DJacobian：%s\n', result.stageDJacobianMethod);
if strcmp(result.stageDParameterization, 'actual_execution_nodes')
    fprintf(fid, '- M3活动节点数：%d\n', ...
        result.nodeContract.parameterCount);
    fprintf(fid, '- M3节点合同SHA-256：`%s`\n', ...
        result.nodeContractHash);
    if strcmpi(result.options.stageDRegularizationMethod, 'tsvd')
        fprintf(fid, '- M3用户配置并实际采用的TSVD保留阶数：%d\n', ...
            result.stageRefine.selectedRetainedSingularValueCount);
        fprintf(fid, '- M3线性化GCV建议的TSVD保留阶数：%d\n', ...
            result.stageRefine.gcvRecommendedRetainedSingularValueCount);
        fprintf(fid, '- M3截断阶数/保留子空间条件数：%d/%.6g\n', ...
            result.stageRefine.truncatedSingularValueCount, ...
            result.stageRefine.retainedConditionNumber);
    else
        fprintf(fid, '- M3用户配置并实际采用的正则强度：%.8g\n', ...
            result.stageRefine.selectedRegularizationStrength);
        fprintf(fid, '- M3冻结训练证据的GCV推荐正则强度：%.8g\n', ...
            result.stageRefine.gcvRecommendedRegularizationStrength);
    end
    fprintf(fid, '- M3正负中心差分全部有效：%d\n', ...
        all(result.stageRefine.perturbationAudit.positive_valid & ...
        result.stageRefine.perturbationAudit.negative_valid));
    fprintf(fid, '- M3代表节点h/h2稳定性：%d\n', ...
        result.stageRefine.stepStabilityPassed);
    fprintf(fid, '- M3阶段D/重新线性化次数：%d/%d\n', ...
        result.stageRefine.replayAudit.stagePassCount, ...
        result.stageRefine.replayAudit.linearizationPassCount);
    fprintf(fid, '- M3候选/训练点回放/求解尝试：%d/%d/%d\n', ...
        result.stageRefine.replayAudit.actualCandidateCount, ...
        result.stageRefine.replayAudit.pointReplayCount, ...
        result.stageRefine.replayAudit.solveAttemptCount);
    if strcmpi(result.options.stageDRegularizationMethod, 'tsvd')
        fprintf(fid, ['- M3全部TSVD候选边界可行/最终最小相对边界裕度/' ...
            '活动边界数：%d/%.3e/%d\n'], ...
            result.stageRefine.allBoundedSolutionsPassed, ...
            result.stageRefine.minimumRelativeBoundMargin, ...
            result.stageRefine.boundedSolution.activeBoundCount);
    else
        fprintf(fid, ['- M3全部有界解KKT/最终相对KKT残差/' ...
            '最终活动边界数：%d/%.3e/%d\n'], ...
            result.stageRefine.allBoundedSolutionsPassed, ...
            result.stageRefine.boundedSolution.relativeKktStationarityResidual, ...
            result.stageRefine.boundedSolution.activeBoundCount);
    end
    fprintf(fid, ['- M3线性预测诊断（不参与终止或验收）全部低于参考值/' ...
        '最终相对误差/参考值：%d/%.6g/%.6g\n'], ...
        result.stageRefine.allLinearPredictionChecksPassed, ...
        result.stageRefine.linearPredictionCheck.relativeResidualError, ...
        result.stageRefine.linearPredictionCheck.relativeTolerance);
    fprintf(fid, '- M3无全局alpha/非线性全局化受控：%d/%d\n', ...
        ~result.stageRefine.globalAlphaUsed, ...
        local_m3_damping_control_passed(result));
    fprintf(fid, '- M3非线性全局化方式：%s\n', ...
        result.options.stageDM3GlobalizationMethod);
    if isfield(result.stageRefine, 'continuationRegularizationStrengths')
        fprintf(fid, '- M3物理正则延续序列：%s\n', mat2str( ...
            result.stageRefine.continuationRegularizationStrengths(:).', 8));
    end
else
    fprintf(fid, '- 辅助旧路线阶段D最大迭代次数：%d\n', ...
        result.options.maxIterationRefine);
end
fprintf(fid, '- 阶段D差分步长倍率：%.8g\n', ...
    result.options.stageDDifferenceStepScale);
fprintf(fid, '- 阶段D初值偏移二范数：%.8g\n', ...
    norm(result.stageRefine.initialOffset));
fprintf(fid, '- 阶段A代价：%.8g -> %.8g\n', ...
    result.stageA.costInitial, result.stageA.costFinal);
fprintf(fid, '- 联合微调代价：%.8g -> %.8g\n', ...
    result.stageRefine.costInitial, result.stageRefine.costFinal);
fprintf(fid, '- 辨识与验证计算耗时：%.3f s\n', ...
    result.timing.estimationSeconds);
fprintf(fid, '- 训练集总体NRMS：%.8g -> %.8g\n', ...
    result.baseline.trainingMetrics.overall_nrms, ...
    result.final.trainingMetrics.overall_nrms);
if result.input.testDataAvailable
    fprintf(fid, '- 测试集总体NRMS：%.8g -> %.8g\n', ...
        result.baseline.testMetrics.overall_nrms, ...
        result.final.testMetrics.overall_nrms);
else
    fprintf(fid, '- 测试集：未在参数辨识入口中读取\n');
end
if result.steadyTestFromTransient.performed
    fprintf(fid, ['- 测试集额外稳态模型NRMS（以对应瞬态收敛解为初值）：' ...
        '%.8g -> %.8g\n'], ...
        result.steadyTestFromTransient.baseline.steadyMetrics.overall_nrms, ...
        result.steadyTestFromTransient.corrected.steadyMetrics.overall_nrms);
    fprintf(fid, '- 额外稳态模型零修正/估计修正回放有效：%d/%d\n', ...
        result.steadyTestFromTransient.baseline.steadyValid, ...
        result.steadyTestFromTransient.corrected.steadyValid);
end
if result.input.testDataAvailable
    fprintf(fid, '- 训练/测试有效：%d/%d\n\n', ...
        result.final.trainingValid, result.final.testValid);
else
    fprintf(fid, '- 训练有效：%d\n\n', result.final.trainingValid);
end
fprintf(fid, '- A/B/D阶段收敛：%d/%d/%d\n', ...
    result.acceptance.stageAConverged, ...
    result.acceptance.stageBAllConverged, ...
    result.acceptance.stageDConverged);
fprintf(fid, '- 正式验收状态：%d\n\n', ...
    result.acceptance.formalAccepted);
fprintf(fid, '参数估计程序未读取隐藏真值。参数真值和燃油偏置真值只能由独立对比程序读取。\n');
clear cleanupObject;
end

function output = local_evaluate_saved_schedule(result, data)
% 供后续公开数据回放使用；不读取另一条路径或隐藏真值。
if ~isstruct(result) || ~isfield(result, 'finalSchedule')
    error('SHT:SteadyAdaptV2:BadSavedResult', ...
        'result不包含可用finalSchedule。');
end
options = local_complete_options(result.options, result.route);
cfg = local_engine_config(options);
engine = sht_engine_open(cfg.engine);
cleanupObject = onCleanup(@() sht_engine_close(engine));
[prediction, valid] = local_evaluate_dataset(result.route, engine, cfg, ...
    data, local_schedule_model(result.finalSchedule), options);
output = struct('prediction', prediction, 'valid', valid);
clear cleanupObject;
end

function output = local_evaluate_saved_constant(result, data)
%LOCAL_EVALUATE_SAVED_CONSTANT 独立回放已保存的阶段A常值估计。
% 该接口只使用result.stageA和公开测量表，不读取隐藏真值，也不使用
% 阶段B/D结果，便于在调整阶段A正则化后直接评价训练集或测试集。
if ~isstruct(result) || ~isfield(result, 'stageA') || ...
        ~isfield(result.stageA, 'x') || ...
        ~isfield(result, 'parameterDefinition')
    error('SHT:SteadyAdaptV2:BadStageAResult', ...
        'result不包含可用于常值回放的stageA和parameterDefinition。');
end
parameters = result.parameterDefinition;
x = result.stageA.x(:);
if numel(x) ~= height(parameters) + 1
    error('SHT:SteadyAdaptV2:BadStageAParameterCount', ...
        'stageA参数数目%d与定义数目%d不一致。', ...
        numel(x), height(parameters) + 1);
end
options = local_complete_options(result.options, result.route);
cfg = local_engine_config(options);
engine = sht_engine_open(cfg.engine);
cleanupObject = onCleanup(@() sht_engine_close(engine));
model = local_constant_model(parameters, x(1:height(parameters)), x(end));
[prediction, valid] = local_evaluate_dataset(result.route, engine, cfg, ...
    data, model, options);
output = struct('prediction', prediction, 'valid', valid);
clear cleanupObject;
end

function output = local_evaluate_offset_batch( ...
        result, trainingData, testData, offsetMatrix)
%LOCAL_EVALUATE_OFFSET_BATCH 批量精确回放最终调度附近的参数偏移。
% 每列offsetMatrix表示相对result.finalSchedule的11维增量。DLL在整批
% 候选间只打开一次，避免工程可辨识性验证重复加载库和配置环境。
required = {'route','options','parameterDefinition','finalSchedule'};
if ~isstruct(result) || ~all(isfield(result, required))
    error('SHT:SteadyAdaptV2:BadOffsetBatchResult', ...
        'result缺少批量偏移回放所需字段。');
end
local_validate_input_table(trainingData, '批量回放训练集');
local_validate_input_table(testData, '批量回放测试集');
parameters = result.parameterDefinition;
parameterCount = height(parameters) + 1;
if ~isnumeric(offsetMatrix) || size(offsetMatrix, 1) ~= parameterCount || ...
        any(~isfinite(offsetMatrix(:)))
    error('SHT:SteadyAdaptV2:BadOffsetMatrix', ...
        'offsetMatrix必须为%d行的有限数值矩阵。', parameterCount);
end

options = local_complete_options(result.options, result.route);
% 批量回放只评价候选，不触发正式结果保存门控。
options.requireConvergedStages = false;
options.requireValidFinalReplay = false;
cfg = local_engine_config(options);
engine = sht_engine_open(cfg.engine);
cleanupObject = onCleanup(@() sht_engine_close(engine));

candidateCount = size(offsetMatrix, 2);
candidate = repmat(struct('offset', [], 'schedule', struct(), ...
    'trainingPrediction', table(), 'trainingValid', false, ...
    'testPrediction', table(), 'testValid', false), candidateCount, 1);
for i = 1:candidateCount
    schedule = local_apply_schedule_offsets( ...
        result.finalSchedule, offsetMatrix(:, i), parameters);
    model = local_schedule_model(schedule);
    [trainingPrediction, trainingValid] = local_evaluate_dataset( ...
        result.route, engine, cfg, trainingData, model, options);
    [testPrediction, testValid] = local_evaluate_dataset( ...
        result.route, engine, cfg, testData, model, options);
    candidate(i).offset = offsetMatrix(:, i);
    candidate(i).schedule = schedule;
    candidate(i).trainingPrediction = trainingPrediction;
    candidate(i).trainingValid = trainingValid;
    candidate(i).testPrediction = testPrediction;
    candidate(i).testValid = testValid;
end
output = struct('route', result.route, ...
    'parameterCount', parameterCount, ...
    'candidateCount', candidateCount, 'candidate', candidate);
clear cleanupObject;
end

function output = local_evaluate_offset_batch_dataset(result, data, offsetMatrix)
%LOCAL_EVALUATE_OFFSET_BATCH_DATASET 只对一个显式给定的数据集批量回放。
% 该接口用于2.4贝叶斯不确定性量化。推断阶段只传入训练集，避免原批量
% 接口在每个候选处顺带计算测试集而造成信息泄漏和无效DLL开销。
required = {'route','options','parameterDefinition','finalSchedule'};
if ~isstruct(result) || ~all(isfield(result, required))
    error('SHT:SteadyAdaptV2:BadDatasetBatchResult', ...
        'result缺少单数据集批量偏移回放所需字段。');
end
local_validate_input_table(data, '单数据集批量回放输入');
parameters = result.parameterDefinition;
parameterCount = height(parameters) + 1;
if ~isnumeric(offsetMatrix) || size(offsetMatrix, 1) ~= parameterCount || ...
        any(~isfinite(offsetMatrix(:)))
    error('SHT:SteadyAdaptV2:BadDatasetOffsetMatrix', ...
        'offsetMatrix必须为%d行的有限数值矩阵。', parameterCount);
end

options = local_complete_options(result.options, result.route);
options.requireConvergedStages = false;
options.requireValidFinalReplay = false;
cfg = local_engine_config(options);
engine = sht_engine_open(cfg.engine);
cleanupObject = onCleanup(@() sht_engine_close(engine));

candidateCount = size(offsetMatrix, 2);
candidate = repmat(struct('offset', [], 'schedule', struct(), ...
    'prediction', table(), 'valid', false), candidateCount, 1);
for i = 1:candidateCount
    schedule = local_apply_schedule_offsets( ...
        result.finalSchedule, offsetMatrix(:, i), parameters);
    model = local_schedule_model(schedule);
    [prediction, valid] = local_evaluate_dataset( ...
        result.route, engine, cfg, data, model, options);
    candidate(i).offset = offsetMatrix(:, i);
    candidate(i).schedule = schedule;
    candidate(i).prediction = prediction;
    candidate(i).valid = valid;
end
output = struct('route', result.route, ...
    'parameterCount', parameterCount, 'pointCount', height(data), ...
    'candidateCount', candidateCount, 'candidate', candidate);
clear cleanupObject;
end

function output = local_evaluate_schedule_batch_dataset( ...
        result, data, schedules, batchOptions)
%LOCAL_EVALUATE_SCHEDULE_BATCH_DATASET 批量回放显式给定的完整调度结构。
% 该接口服务节点级贝叶斯UQ。调度节点由上游概率合同恢复，本函数只负责
% 在一次DLL加载中逐候选精确回放，不解释参数向量，也不读取隐藏真值。
if nargin < 4 || isempty(batchOptions)
    batchOptions = struct();
end
required = {'route','options','finalSchedule'};
if ~isstruct(result) || ~all(isfield(result, required))
    error('SHT:SteadyAdaptV2:BadScheduleBatchResult', ...
        'result缺少完整调度批量回放所需字段。');
end
if isfield(batchOptions,'inputDriven') && isequal(batchOptions.inputDriven,true)
    % 独立预测没有目标测量输出，模式3也不输入Pamb，不能按辨识表强求有限。
    physicalModes=[2,3];
    if result.options.modelMode==0,physicalModes=[1,2,3];end
    assert(strcmp(batchOptions.routeOverride,'steady') && ...
        ismember(batchOptions.inletBoundaryMode,physicalModes) && ...
        strcmp(result.options.fuelInputSemantics,'physical_model'), ...
        'SHT:SteadyAdaptV2:BadPhysicalBatch', ...
        '独立批量预测必须采用物理燃油及允许的进口模式%s。',mat2str(physicalModes));
    fields={'Wf_mean','Mkp_mean','Mkg_mean','Tamb_mean','Mach_mean','Np_mean','Ng_mean'};
    if batchOptions.inletBoundaryMode==1
        fields=[fields,{'Pt1_mean','Tt1_mean','Pamb_mean'}];
    elseif batchOptions.inletBoundaryMode==2, fields{end+1}='Pamb_mean';
    else, fields{end+1}='Altitude_mean'; end
    assert(istable(data) && all(ismember(fields,data.Properties.VariableNames)) && ...
        all(isfinite(data{:,fields}),'all'), ...
        'SHT:SteadyAdaptV2:BadPhysicalBatchData','独立预测物理边界/初值必须完整且有限。');
else
    local_validate_input_table(data, '完整调度批量回放输入');
end
if iscell(schedules)
    if isempty(schedules) || ~all(cellfun(@isstruct, schedules))
        error('SHT:SteadyAdaptV2:BadScheduleBatch', ...
            'schedules元胞必须非空且每个元素均为调度结构。');
    end
    scheduleCell = schedules(:);
elseif isstruct(schedules) && ~isempty(schedules)
    scheduleCell = arrayfun(@(item) item, schedules(:), ...
        'UniformOutput', false);
else
    error('SHT:SteadyAdaptV2:BadScheduleBatch', ...
        'schedules必须为非空结构数组或结构元胞数组。');
end

evaluationRoute = result.route;
if isfield(batchOptions,'routeOverride') && ...
        ~isempty(batchOptions.routeOverride)
    evaluationRoute = local_validate_route(batchOptions.routeOverride);
end
options = local_complete_options(result.options, evaluationRoute);
options.requireConvergedStages = false;
options.requireValidFinalReplay = false;
if isfield(batchOptions, 'inletBoundaryMode') && ...
        ~isempty(batchOptions.inletBoundaryMode)
    value = batchOptions.inletBoundaryMode;
    allowedModes=[1,2,4,5];
    if isfield(batchOptions,'inputDriven') && isequal(batchOptions.inputDriven,true)
        allowedModes=[2,3];
        if options.modelMode==0,allowedModes=[1,2,3];end
    end
    if ~isnumeric(value) || ~isscalar(value) || ...
            ~ismember(value, allowedModes)
        error('SHT:SteadyAdaptV2:BadBatchInletBoundaryMode', ...
            '批量回放inletBoundaryMode必须为1、2、4或5。');
    end
    options.inletBoundaryMode = double(value);
end
if isfield(batchOptions, 'steadyNpBranchEnabled') && ...
        ~isempty(batchOptions.steadyNpBranchEnabled)
    value = batchOptions.steadyNpBranchEnabled;
    if ~islogical(value) || ~isscalar(value)
        error('SHT:SteadyAdaptV2:BadBatchNpBranchSwitch', ...
            '批量回放steadyNpBranchEnabled必须为逻辑标量。');
    end
    options.steadyNpBranchEnabled = value;
end
if isfield(batchOptions, 'useRobustTransientFallback') && ...
        ~isempty(batchOptions.useRobustTransientFallback)
    value = batchOptions.useRobustTransientFallback;
    if ~islogical(value) || ~isscalar(value)
        error('SHT:SteadyAdaptV2:BadBatchTransientFallbackSwitch', ...
            '批量回放useRobustTransientFallback必须为逻辑标量。');
    end
    options.useRobustTransientFallback = value;
end
if isfield(batchOptions, 'maxModelResidual') && ...
        ~isempty(batchOptions.maxModelResidual)
    value = batchOptions.maxModelResidual;
    if ~isnumeric(value) || ~isscalar(value) || ...
            ~isfinite(value) || value <= 0
        error('SHT:SteadyAdaptV2:BadBatchResidualThreshold', ...
            '批量回放maxModelResidual必须为有限正标量。');
    end
    options.maxModelResidual = value;
end
if isfield(batchOptions, 'steadyLoadBoundaryMode') && ...
        ~isempty(batchOptions.steadyLoadBoundaryMode)
    value = lower(string(batchOptions.steadyLoadBoundaryMode));
    if ~isscalar(value) || ~ismember(value, ["fixed_power", "torque"])
        error('SHT:SteadyAdaptV2:BadBatchSteadyLoadBoundaryMode', ...
            '批量回放steadyLoadBoundaryMode必须为fixed_power或torque。');
    end
    options.steadyLoadBoundaryMode = char(value);
end
% 稳态批量回放必须显式选择Np物理解分支。辨识训练点允许使用本批
% 实测Np选择根；独立验证点只能由上游给出的训练集预测分支，禁止读取
% 验证点Np参与根选择。该处理只影响共同工作初值和分支边界，不改变
% 稳态方程、残差或测量输出。
if strcmp(evaluationRoute,'steady') && options.steadyNpBranchEnabled
    branchField={'Np_branch_center_rpm','Np_branch_lower_rpm', ...
        'Np_branch_upper_rpm','Np_branch_relative_half_width', ...
        'Np_branch_available','Np_branch_source', ...
        'Np_branch_reference_uses_point_Np'};
    fieldPresent=ismember(branchField,data.Properties.VariableNames);
    if any(fieldPresent) && ~all(fieldPresent)
        error('SHT:SteadyAdaptV2:PartialBatchNpBranchContract', ...
            '批量稳态数据只包含部分Np分支字段，拒绝使用不完整合同。');
    end
    if ~all(fieldPresent)
        if isfield(batchOptions,'npBranchTrainingData') && ...
                ~isempty(batchOptions.npBranchTrainingData)
            branchTrainingData=batchOptions.npBranchTrainingData;
            if ~istable(branchTrainingData)
                error('SHT:SteadyAdaptV2:BadBatchNpBranchTrainingData', ...
                    'npBranchTrainingData必须是完整训练测量表。');
            end
            local_validate_input_table(branchTrainingData, ...
                '批量稳态回放Np分支训练集');
            [~,data] = local_prepare_np_branch_data( ...
                branchTrainingData,data,options);
        else
            % 当前data就是辨识训练证据，实测Np仅用于选择该训练点的物理解。
            data = local_attach_observed_training_np_branch(data,options);
        end
    end
end
cfg = local_engine_config(options);
% 仅显式调用方启用；不改变2.4/2.7既有批量接口的默认模型。
if isfield(batchOptions,'reynoldsCorrection') && ...
        ~isempty(batchOptions.reynoldsCorrection)
    cfg.engine.reynoldsCorrection=batchOptions.reynoldsCorrection;
end
if isfield(batchOptions,'exhaustBackPressureModel') && ...
        ~isempty(batchOptions.exhaustBackPressureModel)
    cfg.engine.exhaustBackPressureModel=batchOptions.exhaustBackPressureModel;
end
engine = sht_engine_open(cfg.engine);
cleanupObject = onCleanup(@() sht_engine_close(engine));

candidateCount = numel(scheduleCell);
candidateRecovery = nan(candidateCount, 1);
if isfield(batchOptions, 'inletPressureRecoveryByCandidate') && ...
        ~isempty(batchOptions.inletPressureRecoveryByCandidate)
    candidateRecovery = ...
        double(batchOptions.inletPressureRecoveryByCandidate(:));
    if numel(candidateRecovery) ~= candidateCount || ...
            any(~isfinite(candidateRecovery)) || ...
            any(candidateRecovery <= 0) || any(candidateRecovery > 1)
        error('SHT:SteadyAdaptV2:BadBatchInletRecovery', ...
            ['inletPressureRecoveryByCandidate必须与候选数等长，' ...
             '且全部位于(0,1]。']);
    end
end
initialSeed = repmat({[]}, candidateCount, 1);
% 三部件为4个气路猜值和2个轴速，六部件为7个气路猜值和2个轴速。
seedWidth = 6 + 3 * (options.modelMode ~= 0);
if isfield(batchOptions, 'initialSeedMatrices') && ...
        ~isempty(batchOptions.initialSeedMatrices)
    seedInput = batchOptions.initialSeedMatrices;
    if isnumeric(seedInput)
        if ~isequal(size(seedInput), [height(data), seedWidth]) || ...
                any(~isfinite(seedInput(:)))
            error('SHT:SteadyAdaptV2:BadSharedBatchSeed', ...
                '共享批量初值必须为测试点数x%d的有限矩阵。', seedWidth);
        end
        initialSeed(:) = {seedInput};
    elseif iscell(seedInput) && numel(seedInput) == candidateCount
        for i = 1:candidateCount
            value = seedInput{i};
            if ~isequal(size(value), [height(data), seedWidth]) || ...
                    any(~isfinite(value(:)))
                error('SHT:SteadyAdaptV2:BadCandidateBatchSeed', ...
                    '候选%d的批量初值必须为测试点数x%d的有限矩阵。', i, seedWidth);
            end
            initialSeed{i} = value;
        end
    else
        error('SHT:SteadyAdaptV2:BadBatchSeedContainer', ...
            ['initialSeedMatrices必须为共享测试点数x%d矩阵，或与候选数' ...
             '一致的矩阵元胞数组。'], seedWidth);
    end
end
candidate = repmat(struct('schedule', struct(), ...
    'prediction', table(), 'valid', false, ...
    'diagnostic', struct()), candidateCount, 1);
if isfield(batchOptions,'uqSteadyContinuation') && batchOptions.uqSteadyContinuation
    assert(strcmp(evaluationRoute,'steady') && options.modelMode==0 && ...
        strcmp(options.steadyLoadBoundaryMode,'torque') && ...
        strcmp(options.fuelInputSemantics,'physical_model'), ...
        'SHT:UQRoot:Contract','当前解支追踪只用于三部件、固定扭矩的独立UQ稳态预测。');
    assert(all(isnan(candidateRecovery)) && ~isfield(batchOptions,'exhaustBackPressureModel'), ...
        'SHT:UQRoot:UnsupportedBoundary','新增逐候选入口或背压模型需单独验证。');
    continuationOptions=options;continuationOptions.steadyNpBranchEnabled=true;
    continuationOptions.steadyNpSelectionPolicy='first_inside';
    continuationOptions.steadyNpBranchAdaptiveRetry=false;
    continuationOptions.steadySolver='dll_first';
    evaluate=@(point,schedule,seed)local_evaluate_dataset(evaluationRoute,engine,cfg, ...
        point,local_schedule_model(schedule),continuationOptions,seed);
    evaluateReference=@(point,schedule,seed)local_evaluate_dataset(evaluationRoute,engine,cfg, ...
        point,local_schedule_model(schedule),options,seed);
    continuationSettings=struct();
    if isfield(batchOptions,'uqContinuationOptions'),continuationSettings=batchOptions.uqContinuationOptions;end
    candidate=sht_uq_steady_root_continuation(evaluate,result.finalSchedule, ...
        scheduleCell,data,cfg,continuationSettings,evaluateReference);
else
for i = 1:candidateCount
    schedule = scheduleCell{i};
    if ~isfield(schedule, 'healthEntries') || ...
            ~isfield(schedule, 'fuelBias') || ~isfield(schedule, 'h15')
        error('SHT:SteadyAdaptV2:IncompleteSchedule', ...
            '候选%d不是完整的健康参数调度结构。', i);
    end
    model = local_schedule_model(schedule);
    candidateData = data;
    if isfinite(candidateRecovery(i))
        candidateData.inlet_pressure_recovery_mean = ...
            repmat(candidateRecovery(i), height(candidateData), 1);
    end
    [prediction, valid, diagnostic] = local_evaluate_dataset( ...
        evaluationRoute, engine, cfg, candidateData, model, options, ...
        initialSeed{i});
    candidate(i).schedule = schedule;
    candidate(i).prediction = prediction;
    candidate(i).valid = valid;
    candidate(i).diagnostic = diagnostic;
end
end
output = struct('route', evaluationRoute, ...
    'pointCount', height(data), 'candidateCount', candidateCount, ...
    'inletPressureRecoveryByCandidate', candidateRecovery, ...
    'robustTransientFallbackEnabled', ...
    options.useRobustTransientFallback, ...
    'candidate', candidate);
output.reynoldsCorrectionEnabled=isfield(engine,'reynoldsCorrectionInitialization');
output.exhaustBackPressureProvided=ismember('Pback_mean',data.Properties.VariableNames);
output.exhaustBackPressureModelEnabled=isfield(cfg.engine,'exhaustBackPressureModel');
clear cleanupObject;
end

function output = local_evaluate_schedule_trajectory_batch( ...
        result, experiments, schedules, batchOptions)
%LOCAL_EVALUATE_SCHEDULE_TRAJECTORY_BATCH 两状态连续历程精确回放。
% 每段历程只在起点使用测量 Np/Ng 初始化，随后由 DLL 给出的两轴导数
% 连续积分。增强 Kurzke/Visser 瞬态效应保持关闭，因此本接口只辨识
% 稳态修正系数。热模型关闭不等于数据没有热历史影响，调用方须单独
% 评估该近似；本接口不通过冻结隐藏热状态来掩盖模型差异。
if nargin < 4 || isempty(batchOptions), batchOptions = struct(); end
required = {'route','options','parameterDefinition','finalSchedule'};
if ~isstruct(result) || ~all(isfield(result,required))
    error('SHT:SteadyAdaptV2:BadTrajectoryResult', ...
        'result缺少连续历程回放所需字段。');
end
if ~isstruct(experiments) || isempty(experiments)
    error('SHT:SteadyAdaptV2:BadTrajectoryExperiments', ...
        'experiments必须为非空小幅变化历程结构数组。');
end
scheduleCell = local_schedule_cell(schedules);
trajectoryUserOptions = batchOptions;
exhaustBackPressureModel=[];
if isfield(trajectoryUserOptions,'exhaustBackPressureModel')
    exhaustBackPressureModel=trajectoryUserOptions.exhaustBackPressureModel;
    trajectoryUserOptions=rmfield(trajectoryUserOptions,'exhaustBackPressureModel');
end
reynoldsCorrection=[];
if isfield(trajectoryUserOptions,'reynoldsCorrection')
    reynoldsCorrection=trajectoryUserOptions.reynoldsCorrection;
    trajectoryUserOptions=rmfield(trajectoryUserOptions,'reynoldsCorrection');
end
candidateRecovery = nan(numel(scheduleCell), 1);
if isfield(trajectoryUserOptions, 'inletMeanRecoveryByCandidate') && ...
        ~isempty(trajectoryUserOptions.inletMeanRecoveryByCandidate)
    candidateRecovery = ...
        double(trajectoryUserOptions.inletMeanRecoveryByCandidate(:));
    if numel(candidateRecovery) ~= numel(scheduleCell) || ...
            any(~isfinite(candidateRecovery)) || ...
            any(candidateRecovery <= 0) || any(candidateRecovery > 1)
        error('SHT:SteadyAdaptV2:BadTrajectoryCandidateRecovery', ...
            ['inletMeanRecoveryByCandidate必须与候选数等长，' ...
             '且全部位于(0,1]。']);
    end
    trajectoryUserOptions = rmfield(trajectoryUserOptions, ...
        'inletMeanRecoveryByCandidate');
end
trajectoryOptions = local_trajectory_options(trajectoryUserOptions);
local_validate_trajectory_experiments(experiments);

cfg = sht_default_config(struct('engine',struct('modelMode',1)));
if ~isempty(reynoldsCorrection)
    cfg.engine.reynoldsCorrection=reynoldsCorrection;
end
if ~isempty(exhaustBackPressureModel)
    cfg.engine.exhaustBackPressureModel=exhaustBackPressureModel;
end
if isfield(cfg.engine,'transientEffects') && ...
        isstruct(cfg.engine.transientEffects) && ...
        isfield(cfg.engine.transientEffects,'enabled') && ...
        cfg.engine.transientEffects.enabled
    error('SHT:SteadyAdaptV2:EnhancedTransientUnexpectedlyEnabled', ...
        '2.7稳态参数历程回放必须关闭增强瞬态效应。');
end
engine = sht_engine_open(cfg.engine);
cleanupObject = onCleanup(@() sht_engine_close(engine));

candidateCount = numel(scheduleCell);
candidate = repmat(local_empty_trajectory_candidate(),candidateCount,1);
for i = 1:candidateCount
    schedule = scheduleCell{i};
    if ~all(isfield(schedule,{'healthEntries','fuelBias','h15','designHealth'}))
        error('SHT:SteadyAdaptV2:IncompleteTrajectorySchedule', ...
            '候选%d不是完整的健康参数调度结构。',i);
    end
    candidate(i).schedule = schedule;
    try
        local_configure_dll_schedule(engine,schedule);
        candidateExperiments = experiments;
        candidateOptions = trajectoryOptions;
        if isfinite(candidateRecovery(i))
            candidateOptions.inletMeanRecovery = candidateRecovery(i);
            for experimentIndex = 1:numel(candidateExperiments)
                candidateExperiments(experimentIndex).data. ...
                    inlet_pressure_recovery = repmat(candidateRecovery(i), ...
                    height(candidateExperiments(experimentIndex).data), 1);
            end
        end
        candidate(i) = local_replay_trajectory_candidate( ...
            engine,cfg,candidateExperiments,schedule,candidateOptions, ...
            candidate(i));
    catch replayError
        candidate(i).valid = false;
        candidate(i).errorMessage = string(replayError.message);
    end
end
output = struct('route','two_state_trajectory', ...
    'candidateCount',candidateCount,'segmentCount',numel(experiments), ...
    'sampleCount',sum(arrayfun(@(x)height(x.data),experiments)), ...
    'inletPressureRecoveryByCandidate',candidateRecovery, ...
    'integrationMethod',trajectoryOptions.integrationMethod, ...
    'enhancedTransientEffectsEnabled',false,'candidate',candidate);
output.reynoldsCorrectionEnabled=isfield(engine,'reynoldsCorrectionInitialization');
output.exhaustBackPressureProvided=arrayfun( ...
    @(item)ismember('Pback',item.data.Properties.VariableNames),experiments);
output.exhaustBackPressureModelEnabled=isfield(cfg.engine,'exhaustBackPressureModel');
clear cleanupObject;
end

function scheduleCell = local_schedule_cell(schedules)
if iscell(schedules)
    if isempty(schedules) || ~all(cellfun(@isstruct,schedules))
        error('SHT:SteadyAdaptV2:BadTrajectoryScheduleCell', ...
            'schedules元胞必须非空且每个元素均为调度结构。');
    end
    scheduleCell = schedules(:);
elseif isstruct(schedules) && ~isempty(schedules)
    scheduleCell = arrayfun(@(item)item,schedules(:),'UniformOutput',false);
else
    error('SHT:SteadyAdaptV2:BadTrajectorySchedule', ...
        'schedules必须为非空结构数组或结构元胞数组。');
end
end

function options = local_trajectory_options(user)
options = struct('integrationMethod','heun', ...
    'maxModelResidual',1e-2, ...
    'sensorTimeConstant_s',[0.020,0.020,0.020,0.050,0.050,0.020], ...
    'inletBoundaryMode',4,'inletMeanRecovery',0.995);
name = fieldnames(user);
for i = 1:numel(name)
    if ~isfield(options,name{i})
        error('SHT:SteadyAdaptV2:UnknownTrajectoryOption', ...
            '未知连续历程回放配置：%s。',name{i});
    end
    options.(name{i}) = user.(name{i});
end
method = lower(string(options.integrationMethod));
if ~isscalar(method) || ~ismember(method,["euler","heun"])
    error('SHT:SteadyAdaptV2:BadTrajectoryIntegrator', ...
        'integrationMethod必须为euler或heun。');
end
options.integrationMethod = char(method);
if ~isscalar(options.maxModelResidual) || ...
        ~isfinite(options.maxModelResidual) || options.maxModelResidual <= 0
    error('SHT:SteadyAdaptV2:BadTrajectoryResidualThreshold', ...
        'maxModelResidual必须为有限正标量。');
end
tau = options.sensorTimeConstant_s(:).';
if numel(tau) ~= 6 || any(~isfinite(tau)) || any(tau < 0)
    error('SHT:SteadyAdaptV2:BadTrajectorySensorDynamics', ...
        'sensorTimeConstant_s必须为6个有限非负数。');
end
options.sensorTimeConstant_s = tau;
if ~isscalar(options.inletBoundaryMode) || ...
        ~ismember(options.inletBoundaryMode,[4,5])
    error('SHT:SteadyAdaptV2:BadTrajectoryInletMode', ...
        '连续历程回放进口模式必须为4或5。');
end
if ~isscalar(options.inletMeanRecovery) || ...
        ~isfinite(options.inletMeanRecovery) || ...
        options.inletMeanRecovery<=0 || options.inletMeanRecovery>1
    error('SHT:SteadyAdaptV2:BadTrajectoryInletRecovery', ...
        'inletMeanRecovery必须为(0,1]内有限标量。');
end
end

function local_validate_trajectory_experiments(experiments)
required = {'Np','Ng','Wf','Mkp','Mkg','Pt2','Tt1','Pt3','Tt3', ...
    'Tt45','Pt45','Pamb','Tamb','Altitude','Mach'};
for i = 1:numel(experiments)
    item = experiments(i);
    if ~all(isfield(item,{'experimentId','data','time_s','fitMask'})) || ...
            ~istable(item.data)
        error('SHT:SteadyAdaptV2:BadTrajectoryExperiment', ...
            '第%d段历程缺少experimentId/data/time_s/fitMask。',i);
    end
    missing = setdiff(required,item.data.Properties.VariableNames);
    if ~isempty(missing)
        error('SHT:SteadyAdaptV2:MissingTrajectoryColumns', ...
            '第%d段历程缺少列：%s。',i,strjoin(missing,', '));
    end
    if ismember('Pback',item.data.Properties.VariableNames)
        pressure=item.data.Pback;
        if ~isnumeric(pressure) || ~isreal(pressure) || ...
                any(~isfinite(pressure)) || any(pressure<=0)
            error('SHT:SteadyAdaptV2:BadTrajectoryBackpressure', ...
                '第%d段Pback必须为有限正的排气绝对压力（Pa）。',i);
        end
    end
    n = height(item.data);
    t = item.time_s(:);
    if n < 2 || numel(t) ~= n || numel(item.fitMask) ~= n || ...
            any(~isfinite(t)) || any(diff(t) <= 0) || ...
            any(~isfinite(item.data{:,required}),'all')
        error('SHT:SteadyAdaptV2:InvalidTrajectoryExperiment', ...
            '第%d段历程的长度、时间轴、有效掩码或数值无效。',i);
    end
end
end

function candidate = local_replay_trajectory_candidate( ...
        engine,cfg,experiments,schedule,options,candidate)
sampleCount = sum(arrayfun(@(x)height(x.data),experiments));
pointId = strings(sampleCount,1);
segmentIndex = zeros(sampleCount,1);
time_s = zeros(sampleCount,1);
raw = nan(sampleCount,6);
sensor = nan(sampleCount,6);
axisValue = nan(sampleCount,7);
segment = repmat(struct('experimentId',"",'rowIndices',[], ...
    'valid',false,'maximumResidual',NaN,'dllCallCount',0),numel(experiments),1);
cursor = 0;
allValid = true;
maximumResidual = 0;
dllCallCount = 0;
for s = 1:numel(experiments)
    item = experiments(s);
    n = height(item.data);
    row = cursor + (1:n);
    [rawSegment,axisSegment,diagnostic] = local_replay_two_state_segment( ...
        engine,cfg,item,schedule,options);
    measuredInitial = [item.data.Np(1),item.data.Ng(1), ...
        item.data.Pt3(1),item.data.Tt3(1), ...
        item.data.Tt45(1),item.data.Pt45(1)];
    sensorSegment = sht_first_order_foh_filter( ...
        item.time_s(:),rawSegment,options.sensorTimeConstant_s,measuredInitial);
    pointId(row) = compose('%s-%05d',string(item.experimentId),(1:n).');
    segmentIndex(row) = s;
    time_s(row) = item.time_s(:);
    raw(row,:) = rawSegment;
    sensor(row,:) = sensorSegment;
    axisValue(row,:) = axisSegment;
    segment(s).experimentId = string(item.experimentId);
    segment(s).rowIndices = row(:);
    segment(s).valid = diagnostic.valid;
    segment(s).maximumResidual = diagnostic.maximumResidual;
    segment(s).dllCallCount = diagnostic.dllCallCount;
    allValid = allValid && diagnostic.valid;
    maximumResidual = max(maximumResidual,diagnostic.maximumResidual);
    dllCallCount = dllCallCount + diagnostic.dllCallCount;
    cursor = cursor + n;
end
outputNames = {'Np','Ng','Pt3','Tt3','Tt45','Pt45'};
axisNames = {'inlet_corrected_mass_flow', ...
    'burner_inlet_corrected_mass_flow','gt_pt_duct_corrected_mass_flow', ...
    'pt_nozzle_duct_corrected_mass_flow','ac_corrected_speed', ...
    'gt_total_pressure_ratio','pt_total_pressure_ratio'};
candidate.rawPrediction = array2table(raw,'VariableNames',outputNames);
candidate.prediction = array2table(sensor,'VariableNames',outputNames);
candidate.axis = array2table(axisValue,'VariableNames',axisNames);
candidate.point_id = pointId;
candidate.segment_index = segmentIndex;
candidate.time_s = time_s;
candidate.segment = segment;
candidate.valid = allValid && all(isfinite(sensor),'all') && ...
    all(isfinite(axisValue),'all');
candidate.maximumResidual = maximumResidual;
candidate.dllCallCount = dllCallCount;
if ~candidate.valid && strlength(candidate.errorMessage) == 0
    candidate.errorMessage = "连续历程回放包含无效DLL步或非有限输出";
end
end

function [raw,axisValue,diagnostic] = local_replay_two_state_segment( ...
        engine,cfg,experiment,schedule,options)
data = experiment.data;
time = experiment.time_s(:);
n = height(data);
raw = nan(n,6);
axisValue = nan(n,7);
state = [data.Np(1);data.Ng(1)];
valid = true;
maximumResidual = 0;
dllCallCount = 0;
for k = 1:n
    [wf,boundary] = local_trajectory_input( ...
        cfg,data,k,state,schedule,options);
    [xDot,y,diagInfo] = sht_engine_derivative(engine,state,wf,boundary);
    dllCallCount = dllCallCount + 1;
    [stepValid,maximumResidual] = local_accumulate_step_diagnostic( ...
        diagInfo,maximumResidual,options.maxModelResidual);
    valid = valid && stepValid;
    raw(k,:) = [state(1),state(2),y.Pt3,y.Tt3,y.Tt45,y.Pt45];
    axisValue(k,:) = [y.inlet_corrected_mass_flow, ...
        y.burner_inlet_corrected_mass_flow,y.gt_pt_duct_corrected_mass_flow, ...
        y.pt_nozzle_duct_corrected_mass_flow,y.ac_corrected_speed, ...
        y.gt_total_pressure_ratio,y.pt_total_pressure_ratio];
    if k == n, continue; end
    dt = time(k+1)-time(k);
    if strcmp(options.integrationMethod,'heun')
        predictor = state + dt*xDot(1:2);
        [wfNext,boundaryNext] = local_trajectory_input( ...
            cfg,data,k+1,predictor,schedule,options);
        [xDotNext,~,diagNext] = sht_engine_derivative( ...
            engine,predictor,wfNext,boundaryNext);
        dllCallCount = dllCallCount + 1;
        [stepValid,maximumResidual] = local_accumulate_step_diagnostic( ...
            diagNext,maximumResidual,options.maxModelResidual);
        valid = valid && stepValid;
        state = state + 0.5*dt*(xDot(1:2)+xDotNext(1:2));
    else
        state = state + dt*xDot(1:2);
    end
    if any(~isfinite(state)) || any(state <= 0)
        error('SHT:SteadyAdaptV2:InvalidIntegratedShaftSpeed', ...
            '历程%s在t=%.6g s后得到无效Np/Ng。', ...
            char(string(experiment.experimentId)),time(k));
    end
end
diagnostic = struct('valid',valid,'maximumResidual',maximumResidual, ...
    'dllCallCount',dllCallCount);
end

function [wfModel,boundary] = local_trajectory_input( ...
        cfg,data,row,state,schedule,options)
wfMeasured = data.Wf(row);
xFuel = wfMeasured / schedule.fuelBias.wfDesign;
fuelBias = local_interp_clamp(schedule.fuelBias.xNodes, ...
    schedule.fuelBias.biasNodes,xFuel);
wfModel = wfMeasured - fuelBias;
if ~isfinite(wfModel) || wfModel <= 0
    error('SHT:SteadyAdaptV2:NonPositiveTrajectoryFuel', ...
        '连续历程燃油偏置修正后流量非正。');
end
boundary = cfg.engine.boundary;
boundary.ptLoadInputMode = 'torque';
boundary.gtLoadInputMode = 'torque';
boundary.Mkp = data.Mkp(row);
boundary.Mkg = data.Mkg(row);
boundary.altitude = data.Altitude(row);
boundary.Mach = data.Mach(row);
boundary.deltaTemperature = 0;
boundary.inletBoundaryMode = options.inletBoundaryMode;
if options.inletBoundaryMode == 4
    boundary.Pamb = data.Pamb(row);
    boundary.Tamb = data.Tamb(row);
    boundary.Tt1 = data.Tt1(row);
    boundary.Pt2 = data.Pt2(row);
else
    boundary.Ps0 = data.Pamb(row);
    boundary.Ts_amb = data.Tamb(row);
    boundary.Tt1 = data.Tt1(row);
    if ismember('inlet_pressure_recovery',data.Properties.VariableNames)
        boundary.inletTotalPressureRecovery = ...
            data.inlet_pressure_recovery(row);
    else
        boundary.inletTotalPressureRecovery = options.inletMeanRecovery;
    end
end
boundary.health = schedule.designHealth;
boundary.healthScheduleEnabled = true;
if ismember('Pback',data.Properties.VariableNames)
    boundary.Pback=data.Pback(row);
end
if isfield(cfg.engine,'exhaustBackPressureModel')
    if isfield(boundary,'Pback')
        error('SHT:SteadyAdaptV2:ConflictingBackpressure', ...
            '模型背压回放不能接收固定Pback历程。');
    end
    boundary.exhaustBackPressureModel=cfg.engine.exhaustBackPressureModel;
end
% power/hpsPower会由扭矩接口按当前候选状态重新计算，这两个初值仅保持
% 结构字段完备，不能作为权威边界。
boundary.power = data.Mkp(row)*pi*state(1)/30;
boundary.hpsPower = data.Mkg(row)*pi*state(2)/30;
end

function [valid,maximumResidual] = local_accumulate_step_diagnostic( ...
        diagnostic,maximumResidual,threshold)
value = double(diagnostic.maxErr);
maximumResidual = max(maximumResidual,value);
valid = diagnostic.ret == 0 && isfinite(value) && value <= threshold;
end

function candidate = local_empty_trajectory_candidate()
candidate = struct('schedule',struct(),'rawPrediction',table(), ...
    'prediction',table(),'axis',table(),'point_id',strings(0,1), ...
    'segment_index',zeros(0,1),'time_s',zeros(0,1), ...
    'segment',struct([]),'valid',false,'maximumResidual',NaN, ...
    'dllCallCount',0,'errorMessage',"");
end

function output = local_evaluate_dataset_variants( ...
        result, dataVariants, offset, variantOptions)
%LOCAL_EVALUATE_DATASET_VARIANTS 在一次DLL加载内回放多份数据扰动。
% 每个元胞是一份满足2.4输入合同的数据表，所有变体使用同一组11维
% 参数偏移。可通过variantOptions显式指定回放路径和共同工作初值；
% 省略该参数时保持原有行为。该接口专门服务输入误差有限差分传播。
if nargin < 4 || isempty(variantOptions)
    variantOptions = struct();
end
if ~isstruct(variantOptions) || ~isscalar(variantOptions)
    error('SHT:SteadyAdaptV2:BadVariantOptions', ...
        'variantOptions必须为标量结构体。');
end
required = {'route','options','parameterDefinition','finalSchedule'};
if ~isstruct(result) || ~all(isfield(result, required))
    error('SHT:SteadyAdaptV2:BadVariantResult', ...
        'result缺少数据变体回放所需字段。');
end
if ~iscell(dataVariants) || isempty(dataVariants)
    error('SHT:SteadyAdaptV2:BadDataVariants', ...
        'dataVariants必须是非空表格元胞数组。');
end
parameters = result.parameterDefinition;
parameterCount = height(parameters) + 1;
if ~isnumeric(offset) || numel(offset) ~= parameterCount || ...
        any(~isfinite(offset(:)))
    error('SHT:SteadyAdaptV2:BadVariantOffset', ...
        'offset必须为%d维有限向量。', parameterCount);
end
for i = 1:numel(dataVariants)
    local_validate_input_table(dataVariants{i}, sprintf('数据变体%d', i));
end

evaluationRoute = result.route;
if isfield(variantOptions, 'routeOverride') && ...
        ~isempty(variantOptions.routeOverride)
    evaluationRoute = local_validate_route(variantOptions.routeOverride);
end
options = local_complete_options(result.options, evaluationRoute);
options.requireConvergedStages = false;
options.requireValidFinalReplay = false;
if isfield(variantOptions, 'steadyNpBranchEnabled') && ...
        ~isempty(variantOptions.steadyNpBranchEnabled)
    value = variantOptions.steadyNpBranchEnabled;
    if ~islogical(value) || ~isscalar(value)
        error('SHT:SteadyAdaptV2:BadVariantNpBranchSwitch', ...
            '数据变体steadyNpBranchEnabled必须为逻辑标量。');
    end
    options.steadyNpBranchEnabled = value;
end
if isfield(variantOptions, 'useRobustTransientFallback') && ...
        ~isempty(variantOptions.useRobustTransientFallback)
    value = variantOptions.useRobustTransientFallback;
    if ~islogical(value) || ~isscalar(value)
        error('SHT:SteadyAdaptV2:BadVariantFallbackSwitch', ...
            '数据变体useRobustTransientFallback必须为逻辑标量。');
    end
    options.useRobustTransientFallback = value;
end
if isfield(variantOptions, 'maxModelResidual') && ...
        ~isempty(variantOptions.maxModelResidual)
    value = variantOptions.maxModelResidual;
    if ~isnumeric(value) || ~isscalar(value) || ...
            ~isfinite(value) || value <= 0
        error('SHT:SteadyAdaptV2:BadVariantResidualThreshold', ...
            '数据变体maxModelResidual必须为有限正标量。');
    end
    options.maxModelResidual = value;
end
if isfield(variantOptions, 'steadyLoadBoundaryMode') && ...
        ~isempty(variantOptions.steadyLoadBoundaryMode)
    value = lower(string(variantOptions.steadyLoadBoundaryMode));
    if ~isscalar(value) || ~ismember(value, ["fixed_power", "torque"])
        error('SHT:SteadyAdaptV2:BadVariantSteadyLoadBoundaryMode', ...
            '数据变体steadyLoadBoundaryMode必须为fixed_power或torque。');
    end
    options.steadyLoadBoundaryMode = char(value);
end
initialSeedMatrix = [];
seedWidth = 6 + 3 * (options.modelMode ~= 0);
if isfield(variantOptions, 'initialSeedMatrix') && ...
        ~isempty(variantOptions.initialSeedMatrix)
    initialSeedMatrix = variantOptions.initialSeedMatrix;
    if ~isnumeric(initialSeedMatrix) || ...
            ~isequal(size(initialSeedMatrix), [height(dataVariants{1}), seedWidth]) || ...
            any(~isfinite(initialSeedMatrix(:)))
        error('SHT:SteadyAdaptV2:BadVariantInitialSeed', ...
            '数据变体共同工作初值必须为测试点数x%d的有限矩阵。', seedWidth);
    end
end
cfg = local_engine_config(options);
engine = sht_engine_open(cfg.engine);
cleanupObject = onCleanup(@() sht_engine_close(engine));
schedule = local_apply_schedule_offsets( ...
    result.finalSchedule, offset(:), parameters);
model = local_schedule_model(schedule);

variant = repmat(struct('prediction', table(), 'valid', false, ...
    'diagnostic', struct()), ...
    numel(dataVariants), 1);
for i = 1:numel(dataVariants)
    variantSeed=initialSeedMatrix;
    if isfield(variantOptions,'initialSeedMatrices')
        assert(numel(variantOptions.initialSeedMatrices)==numel(dataVariants), ...
            'TC24:UQ:VariantSeedCount','数据变体与初值数量不一致。');
        variantSeed=variantOptions.initialSeedMatrices{i};
        assert(isequal(size(variantSeed),[height(dataVariants{i}),seedWidth]) && ...
            all(isfinite(variantSeed(:))),'TC24:UQ:VariantSeedShape','数据变体初值维数不正确。');
    end
    [variant(i).prediction, variant(i).valid, variant(i).diagnostic] = ...
        local_evaluate_dataset(evaluationRoute, engine, cfg, ...
        dataVariants{i}, model, options, variantSeed);
end
output = struct('route', evaluationRoute, ...
    'variantCount', numel(dataVariants), ...
    'offset', offset(:), 'variant', variant);
clear cleanupObject;
end

function output = local_validate_saved_schedule(result, testData, validationCfg, constantStageA)
%LOCAL_VALIDATE_SAVED_SCHEDULE 用冻结辨识结果独立验证真实测试集。
% 测试数据只用于回放和误差统计，不参与参数更新，也不读取参数真值。
requiredResult = {'route','options','parameterDefinition', ...
    'finalSchedule','residualScales'};
if nargin < 4, constantStageA = false; end
if constantStageA
    requiredResult = {'route','options','parameterDefinition','stageA','residualScales'};
end
if ~isstruct(result) || ~all(isfield(result, requiredResult))
    error('SHT:SteadyAdaptV2:BadValidationResult', ...
        '辨识结果缺少测试验证所需字段。');
end
local_validate_input_table(testData, '测试集');
if nargin < 3
    validationCfg = [];
end

options = local_complete_options(result.options, result.route);
options.requireConvergedStages = false;
options.requireValidFinalReplay = false;
options.evaluateTestSet = false;
options.fuelInputSemantics = 'measured';
trainingData = table();
if isfield(result, 'input') && isfield(result.input, 'trainingFile') && ...
        exist(result.input.trainingFile, 'file') == 2
    trainingData = local_read_measurement_table( ...
        result.input.trainingFile, '原辨识训练集');
end
if options.steadyNpBranchEnabled && isempty(trainingData)
    error('SHT:SteadyAdaptV2:MissingNpBranchTrainingData', ...
        ['找不到原辨识训练集，不能在不读取测试Np的前提下建立稳态' ...
         '合理分支。']);
end
npBranchPrior = struct('enabled', false);
if ~isempty(trainingData)
    [trainingData, testData, npBranchPrior] = ...
        local_prepare_np_branch_data(trainingData, testData, options);
end
if isempty(validationCfg)
    cfg = local_engine_config(options);
else
    cfg = validationCfg;
    if ~isstruct(cfg) || ~isscalar(cfg) || ~isfield(cfg, 'engine') || ...
            ~isstruct(cfg.engine) || ~isfield(cfg.engine, 'interface') || ...
            ~isfield(cfg.engine, 'modelMode') || cfg.engine.modelMode ~= options.modelMode
        error('SHT:SteadyAdaptV2:BadFrozenValidationConfig', ...
            '外部冻结验证配置必须是完整的六部件modelMode=1配置。');
    end
end
engine = sht_engine_open(cfg.engine);
cleanupObject = onCleanup(@() sht_engine_close(engine));

zeroModel = local_constant_model(result.parameterDefinition, ...
    zeros(height(result.parameterDefinition), 1), 0);
if constantStageA
    x = result.stageA.x(:);
    assert(numel(x)==height(result.parameterDefinition)+1, ...
        'SHT:SteadyAdaptV2:BadStageAParameterCount','A阶段常值参数维数不匹配。');
    finalModel = local_constant_model(result.parameterDefinition,x(1:end-1),x(end));
else
    finalModel = local_schedule_model(result.finalSchedule);
end
[baselinePrediction, baselineValid, baselineDiagnostic] = ...
    local_evaluate_dataset(result.route, engine, cfg, testData, ...
    zeroModel, options);
[correctedPrediction, correctedValid, correctedDiagnostic] = ...
    local_evaluate_dataset(result.route, engine, cfg, testData, ...
    finalModel, options);

baselineMetrics = local_dataset_metrics(result.route, testData, ...
    baselinePrediction, result.residualScales);
correctedMetrics = local_dataset_metrics(result.route, testData, ...
    correctedPrediction, result.residualScales);
predictionTable = local_prediction_detail_table(result.route, testData, ...
    baselinePrediction, correctedPrediction, result.residualScales);

steadyFromTransient = struct('performed', false, ...
    'skipReason', "辨识结果不是瞬态时刻路径", ...
    'initializationSource', "", 'residualScales', table(), ...
    'baseline', struct(), 'corrected', struct(), ...
    'predictionTable', table(), 'seedTransferTable', table());
if strcmp(result.route, 'transient_instant')
    if isempty(trainingData)
        steadyFromTransient.skipReason = ...
            "找不到原辨识训练集，不能冻结稳态误差归一化尺度";
    else
        steadyOptions = options;
        steadyOptions.evaluateSteadyTestFromTransient = true;
        steadyFromTransient = local_evaluate_transient_test_as_steady( ...
            result.route, engine, cfg, trainingData, testData, ...
            zeroModel, finalModel, steadyOptions, ...
            baselineDiagnostic, correctedDiagnostic);
        steadyFromTransient.skipReason = "";
    end
end

output = struct();
output.schemaVersion = 'SHT_STEADY_MODEL_TEST_VALIDATION_V2_NP_BRANCH';
output.route = result.route;
output.createdAt = datestr(now, 31);
output.testData = testData;
output.baseline = struct('prediction', baselinePrediction, ...
    'valid', baselineValid, 'metrics', baselineMetrics, ...
    'diagnostic', baselineDiagnostic);
output.corrected = struct('prediction', correctedPrediction, ...
    'valid', correctedValid, 'metrics', correctedMetrics, ...
    'diagnostic', correctedDiagnostic);
output.predictionTable = predictionTable;
output.steadyFromTransient = steadyFromTransient;
output.npBranchPrior = npBranchPrior;
output.testNpUsedForBranchSelection = false;
% 兼容旧字段：这里特指分支约束稳态回放的负载功率。瞬态主路径仍按
% 其模型定义使用实测Np作为状态，并由Mkp*Np换算瞬态时刻轴功率。
output.testNpUsedForLoadPower = false;
output.steadyReplayUsesTestNpForLoadPower = false;
output.primaryRouteUsesMeasuredNpAsState = ...
    strcmp(result.route, 'transient_instant');
output.primaryRouteLoadPowerUsesMeasuredNp = ...
    strcmp(result.route, 'transient_instant');
output.testDataUsedForInference = false;
output.truthWasRead = false;
output.passed = correctedValid && ...
    (~steadyFromTransient.performed || ...
    steadyFromTransient.corrected.steadyValid);
clear cleanupObject;
end

function model = local_restore_delivery_model(manifest, correction, bias, branch)
% 最小可执行模型只由Excel恢复，不构造虚假的训练路径或求解历史。
options=local_default_options(char(string(manifest.route(1))));
options.modelMode=double(manifest.model_mode(1));
options.inletBoundaryMode=double(manifest.inlet_boundary_mode(1));
if ismember('shaft_load_input_mode',manifest.Properties.VariableNames)
    options.shaftLoadInputMode=double(manifest.shaft_load_input_mode(1));
end
if ismember('steady_load_boundary',manifest.Properties.VariableNames)
    options.steadyLoadBoundaryMode=char(string(manifest.steady_load_boundary(1)));
    options.steadyUseMeasuredPower=logical(manifest.steady_use_measured_power(1));
    options.steadySolver=char(string(manifest.steady_solver(1)));
end
if ismember('np_selection_policy',manifest.Properties.VariableNames)
    options.steadyNpSelectionPolicy=char(string(manifest.np_selection_policy(1)));
end
options.estimateInletPressureLoss=options.modelMode==0;
options.includePt2Residual=false;
dictionaryOptions=options;
% h0虽不参加联合辨识，仍是完整发动机模型的一条必需曲线。
dictionaryOptions.estimateInletPressureLoss=true;
parameters=local_parameter_definition(dictionaryOptions);
schedule=struct('schemaVersion',char(string(manifest.schedule_schema_version(1))), ...
    'interpolation',char(string(manifest.interpolation(1))), ...
    'extrapolation',char(string(manifest.endpoint_policy(1))), ...
    'healthEntries',repmat(local_empty_schedule_entry(),0,1),'h15',0);
for i=1:height(parameters)
    rows=correction(correction.c_index==parameters.c_index(i),:);
    rows=sortrows(rows,'node_index');
    if parameters.c_index(i)==15
        schedule.h15=rows.correction_value(1); continue;
    end
    entry=local_empty_schedule_entry();
    entry.cIndex=parameters.c_index(i); entry.name=char(parameters.name(i));
    entry.axisName=char(parameters.axis_name(i)); entry.axisType=parameters.axis_type(i);
    entry.pressureLoss=parameters.pressure_loss(i);
    if any(string(rows.axis_name)~=string(entry.axisName))
        error('SHT:SteadyAdaptV2:DeliveryAxisMismatch','h%d调度轴与字典不一致。',entry.cIndex);
    end
    entry.xNodes=double(rows.coordinate); entry.kNodes=double(rows.correction_value);
    entry.lowerBound=rows.lower_bound(1); entry.upperBound=rows.upper_bound(1);
    if ismember('design_coordinate',rows.Properties.VariableNames)
        entry.designCoordinate=rows.design_coordinate(1);
    else
        entry.designCoordinate=entry.xNodes(end);
    end
    entry=local_refresh_schedule_entry(entry);
    schedule.healthEntries(end+1,1)=entry;
end
bias=sortrows(bias,'node_index');
schedule.fuelBias=struct('axisName',char(string(bias.axis_name(1))), ...
    'xNodes',double(bias.coordinate),'biasNodes',double(bias.bias_value), ...
    'wfDesign',double(bias.reference_value(1)));
schedule.designHealth=local_schedule_design_health(schedule);
model=struct('schemaVersion','SHT_2P4_EXECUTABLE_MODEL_V1', ...
    'options',options,'finalSchedule',schedule,'npBranchModel',branch, ...
    'parameterDefinition',parameters, ...
    'route',char(string(manifest.route(1))),'runId',char(string(manifest.run_id(1))), ...
    'solverConverged',logical(manifest.solver_converged(1)), ...
    'trainingDataRequired',false);
end

function output = local_predict_saved_schedule(result, predictionInput)
%LOCAL_PREDICT_SAVED_SCHEDULE 对指定物理输入执行无测量输出稳态预测。
% Wf_model是模型物理输入，不应用辨识得到的燃油传感器偏置；修正系数
% 调度和进气道压损调度仍使用冻结的最终个体模型。
requiredResult = {'options','finalSchedule'};
if ~isstruct(result) || ~all(isfield(result, requiredResult))
    error('SHT:SteadyAdaptV2:BadPredictionResult', ...
        '辨识结果缺少输入驱动预测所需字段。');
end

options = local_complete_options(result.options, 'steady');
cfg = local_engine_config(options);
[inputTable, internalData, inletBoundaryMode] = local_normalize_prediction_input( ...
    predictionInput, cfg);
options = local_complete_options(result.options, 'steady');
options.inletBoundaryMode = inletBoundaryMode;
if ~options.steadyUseMeasuredPower
    options.steadyLoadBoundaryMode = 'torque';
elseif ~ismember('Pshaft_mean',internalData.Properties.VariableNames)
    error('SHT:SteadyAdaptV2:PredictionPowerRequired', ...
        '当前交付模型采用功率边界，独立预测需提供Pshaft_W；Mkp仅用于选根。');
end
options.fuelInputSemantics = 'physical_model';
options.evaluateTestSet = false;
options.evaluateSteadyTestFromTransient = false;
options.requireConvergedStages = false;
options.requireValidFinalReplay = false;

trainingDataRead=false;
if isfield(result,'npBranchModel') && ~isempty(result.npBranchModel)
    [internalData,npBranchPrior]=sht_np_branch_delivery( ...
        'query',result.npBranchModel,internalData,inletBoundaryMode);
else
if ~isfield(result, 'input') || ~isfield(result.input, 'trainingFile') || ...
        exist(result.input.trainingFile, 'file') ~= 2
    error('SHT:SteadyAdaptV2:MissingPredictionBranchTrainingData', ...
        ['独立稳态预测需要原辨识训练集建立Np合理分支，当前结果没有' ...
         '可访问的trainingFile。']);
end
branchTrainingData = local_read_measurement_table( ...
    result.input.trainingFile, '原辨识训练集');
branchTrainingData.Wf_mean = local_training_physical_fuel( ...
    branchTrainingData.Wf_mean, result.finalSchedule);
[~, internalData, npBranchPrior] = ...
    local_prepare_np_branch_data(branchTrainingData, internalData, options);
internalData.Np_branch_source(:) = ...
    "training_physical_fuel_power_curve";
npBranchPrior.trainingFuelCoordinate = ...
    "estimated_physical_model_fuel_after_frozen_bias_correction";
trainingDataRead=true;
end

engine = sht_engine_open(cfg.engine);
cleanupObject = onCleanup(@() sht_engine_close(engine));
zeroModel = struct('kind','constant','health',zeros(159,1), ...
    'fuelBias',0,'schedule',[]);
finalModel = local_schedule_model(result.finalSchedule);
[baselinePrediction, baselineValid, baselineDiagnostic] = ...
    local_evaluate_dataset('steady', engine, cfg, internalData, ...
    zeroModel, options);
[correctedPrediction, correctedValid, correctedDiagnostic] = ...
    local_evaluate_dataset('steady', engine, cfg, internalData, ...
    finalModel, options);
% 无实测Ng的独立预测不能把一个设计Ng初值当成唯一可行分支。
% 仅对气路未收敛点调整数值初值；不改变边界、系数或Np选根范围。
% 已有有效根保持原样，备选解仍须满足全部共同工作残差。
initialCorrectedPrediction=correctedPrediction;
ngSeedRetryCount=zeros(height(internalData),1);
for row=find(~correctedPrediction.valid).'
    for factor=[1.05,0.95,1.10,0.90]
        trial=internalData(row,:);
        trial.Ng_mean=internalData.Ng_mean(row)*factor;
        [candidate,ok,diagnostic]=local_evaluate_dataset( ...
            'steady',engine,cfg,trial,finalModel,options);
        ngSeedRetryCount(row)=ngSeedRetryCount(row)+1;
        if ok
            correctedPrediction(row,:)=candidate;
            fields=fieldnames(correctedDiagnostic);
            for f=1:numel(fields)
                correctedDiagnostic.(fields{f})(row,:)=diagnostic.(fields{f});
            end
            break;
        end
    end
end
correctedValid=all(correctedPrediction.valid);

predictionTable = local_input_driven_prediction_table( ...
    inputTable, baselinePrediction, correctedPrediction, options.modelMode);
output = struct();
output.schemaVersion = 'SHT_STEADY_INPUT_DRIVEN_PREDICTION_V3_NP_BRANCH';
output.createdAt = datestr(now, 31);
if inletBoundaryMode == 1
    requiredFields={'Pt1','Tt1','Pamb','Tamb','Mach','Wf_model','Mkp','Mkg'};
    optionalFields={'point_id','Altitude','Np_initial','Ng_initial','inletBoundaryMode'};
    environmentDefinition='measured_Pt1_Tt1';
elseif inletBoundaryMode == 2
    requiredFields = {'Pamb','Tamb','Mach','Wf_model','Mkp','Mkg'};
    optionalFields = {'point_id','Altitude','Np_initial','Ng_initial', ...
        'inletBoundaryMode'};
    environmentDefinition = 'Pamb_Tamb_Mach';
else
    requiredFields = {'Altitude','Tamb','Mach','Wf_model','Mkp','Mkg'};
    optionalFields = {'point_id','Np_initial','Ng_initial', ...
        'inletBoundaryMode'};
    environmentDefinition = 'Altitude_Tamb_Mach';
end
output.inputContract = struct( ...
    'requiredFields', {requiredFields}, ...
    'optionalFields', {optionalFields}, ...
    'inletBoundaryMode', inletBoundaryMode, ...
    'environmentDefinition', environmentDefinition, ...
    'altitudeUsedForAtmosphere', inletBoundaryMode == 3, ...
    'ambientPressureProvided', ismember(inletBoundaryMode,[1,2]), ...
    'fuelInputSemantics', 'physical_model', ...
    'controlLoopUsed', false);
output.input = inputTable;
% 后验传播需要与确定性预测完全一致的内部工况表。该表只包含用户
% 指定边界及数值求解初值，不包含测量输出或参数真值。
output.internalData = internalData;
output.npBranchPrior = npBranchPrior;
output.baseline = struct('prediction', baselinePrediction, ...
    'valid', baselineValid, 'diagnostic', baselineDiagnostic);
output.corrected = struct('prediction', correctedPrediction, ...
    'valid', correctedValid, 'diagnostic', correctedDiagnostic);
output.initialCorrectedPrediction=initialCorrectedPrediction;
output.ngSeedRetryCount=ngSeedRetryCount;
output.predictionTable = predictionTable;
output.measurementDataUsed = trainingDataRead;
output.targetMeasurementDataUsed = false;
output.trainingMeasurementDataUsedForBranchPrior = trainingDataRead;
output.targetNpUsedForBranchSelection = false;
output.targetNpUsedForLoadPower = false;
output.truthWasRead = false;
output.passed = correctedValid;
clear cleanupObject;
end

function wfModel = local_training_physical_fuel(wfMeasured, schedule)
wfMeasured = double(wfMeasured(:));
wfModel = nan(size(wfMeasured));
for i = 1:numel(wfMeasured)
    xFuel = wfMeasured(i) / schedule.fuelBias.wfDesign;
    bias = local_interp_clamp(schedule.fuelBias.xNodes, ...
        schedule.fuelBias.biasNodes, xFuel);
    wfModel(i) = wfMeasured(i) - bias;
end
if any(~isfinite(wfModel)) || any(wfModel <= 0) || ...
        any(diff(sort(wfModel)) <= 0)
    error('SHT:SteadyAdaptV2:BadPhysicalFuelBranchCoordinate', ...
        ['冻结燃油偏置修正后的训练Wf必须为有限正值且互不重复，' ...
         '否则不能建立独立预测的Np分支曲线。']);
end
end

function [inputTable, internalData, inletBoundaryMode] = ...
        local_normalize_prediction_input(input, cfg)
if isstruct(input) && isscalar(input)
    input = struct2table(input, 'AsArray', true);
end
if ~istable(input) || height(input) < 1
    error('SHT:SteadyAdaptV2:BadPredictionInput', ...
        '预测输入必须是非空表或标量结构体。');
end

n = height(input);
names = input.Properties.VariableNames;
hasExplicitMode = ismember('inletBoundaryMode', names);
hasPamb = ismember('Pamb', names);
hasAltitude = ismember('Altitude', names);
if hasExplicitMode
    modeValue = input.inletBoundaryMode;
    if ~isnumeric(modeValue) || ~iscolumn(modeValue) || ...
            numel(modeValue) ~= n || any(~isfinite(modeValue)) || ...
            any(modeValue ~= round(modeValue)) || ...
            any(~ismember(modeValue, [1, 2, 3])) || numel(unique(modeValue)) ~= 1
        error('SHT:SteadyAdaptV2:BadPredictionInletMode', ...
            'inletBoundaryMode必须为整列一致的1、2或3；模式1仅用于三部件测量Pt1入口。');
    end
    inletBoundaryMode = double(modeValue(1));
elseif hasPamb && ~hasAltitude
    inletBoundaryMode = 2;
elseif hasAltitude && ~hasPamb
    inletBoundaryMode = 3;
elseif hasPamb && hasAltitude
    error('SHT:SteadyAdaptV2:AmbiguousPredictionInletMode', ...
        ['预测输入同时包含Pamb和Altitude。请显式给定' ...
         'inletBoundaryMode=2或3，避免环境定义歧义。']);
else
    error('SHT:SteadyAdaptV2:MissingPredictionEnvironment', ...
        '预测输入必须给定Pamb（模式2）或Altitude（模式3）。');
end

commonRequired = {'Tamb','Mach','Wf_model','Mkp','Mkg'};
if inletBoundaryMode == 1
    assert(cfg.engine.modelMode==0,'TC24:Prediction:Mode','测量Pt1预测仅在三部件接入中启用。');
    required=[{'Pt1','Tt1','Pamb'},commonRequired];
elseif inletBoundaryMode == 2
    required = [{'Pamb'}, commonRequired];
else
    required = [{'Altitude'}, commonRequired];
end
missing = setdiff(required, input.Properties.VariableNames);
if ~isempty(missing)
    error('SHT:SteadyAdaptV2:BadPredictionSchema', ...
        '预测输入缺少字段：%s。', strjoin(missing, ', '));
end
for i = 1:numel(required)
    value = input.(required{i});
    if ~isnumeric(value) || ~iscolumn(value) || numel(value) ~= n || ...
            any(~isfinite(value))
        error('SHT:SteadyAdaptV2:BadPredictionValue', ...
            '预测输入字段%s必须是有限数值列。', required{i});
    end
end
if any(input.Tamb <= 0 | input.Wf_model <= 0 | ...
        input.Mach < 0 | input.Mkp < 0 | input.Mkg < 0) || ...
        (inletBoundaryMode == 2 && any(input.Pamb <= 0))
    error('SHT:SteadyAdaptV2:PredictionInputOutOfRange', ...
        ['Tamb、Wf_model必须为正，Mach、Mkp和Mkg必须非负；' ...
         '模式2的Pamb还必须为正。']);
end
if inletBoundaryMode==1
    assert(all(input.Pt1>0 & input.Tt1>0 & input.Pamb>0), ...
        'TC24:Prediction:Units','Pt1/Pamb使用正绝对压力Pa，Tt1使用正温度K。');
end

if ~ismember('point_id', input.Properties.VariableNames)
    input.point_id = "PRED_" + compose('%03d', (1:n).');
else
    input.point_id = string(input.point_id);
end
if numel(unique(input.point_id)) ~= n
    error('SHT:SteadyAdaptV2:DuplicatePredictionPointId', ...
        '预测输入point_id必须唯一。');
end
input = local_add_optional_prediction_column(input, 'Altitude', zeros(n, 1));
input = local_add_optional_prediction_column(input, 'Pamb', nan(n, 1));
input = local_add_optional_prediction_column(input, 'Np_initial', ...
    repmat(cfg.engine.initial.Np0, n, 1));
input = local_add_optional_prediction_column(input, 'Ng_initial', ...
    repmat(cfg.engine.initial.Ng0, n, 1));

optionalNumeric = {'Altitude','Np_initial','Ng_initial'};
for i = 1:numel(optionalNumeric)
    value = input.(optionalNumeric{i});
    if ~isnumeric(value) || ~iscolumn(value) || numel(value) ~= n || ...
            any(~isfinite(value))
        error('SHT:SteadyAdaptV2:BadPredictionOptionalValue', ...
            '预测输入字段%s必须是有限数值列。', optionalNumeric{i});
    end
end
if any(input.Np_initial <= 0 | input.Ng_initial <= 0)
    error('SHT:SteadyAdaptV2:BadPredictionInitialSpeed', ...
        'Np_initial和Ng_initial必须为正。');
end
input.inletBoundaryMode = repmat(inletBoundaryMode, n, 1);

internalData = table(input.point_id, input.Np_initial, input.Ng_initial, ...
    input.Wf_model, nan(n,1), nan(n,1), input.Mkp, input.Mkg, ...
    nan(n,1), nan(n,1), nan(n,1), nan(n,1), input.Pamb, input.Tamb, ...
    input.Altitude, input.Mach, ...
    'VariableNames', {'point_id','Np_mean','Ng_mean','Wf_mean', ...
    'Tt45_mean','Pt45_mean','Mkp_mean','Mkg_mean','Pt2_mean', ...
    'Tt1_mean','Pt3_mean','Tt3_mean','Pamb_mean','Tamb_mean', ...
    'Altitude_mean','Mach_mean'});
if inletBoundaryMode==1
    internalData.Pt1_mean=input.Pt1;internalData.Tt1_mean=input.Tt1;
end
if ismember('Pshaft_W',input.Properties.VariableNames)
    assert(isnumeric(input.Pshaft_W) && all(isfinite(input.Pshaft_W)) && ...
        all(input.Pshaft_W>=0),'SHT:SteadyAdaptV2:PredictionPower','Pshaft_W必须为有限非负功率W。');
    internalData.Pshaft_mean=input.Pshaft_W;
end
inputTable = input(:, {'point_id','inletBoundaryMode','Altitude','Pamb','Tamb','Mach', ...
    'Wf_model','Mkp','Mkg','Np_initial','Ng_initial'});
if inletBoundaryMode==1,inputTable.Pt1=input.Pt1;inputTable.Tt1=input.Tt1;end
if ismember('Pshaft_W',input.Properties.VariableNames),inputTable.Pshaft_W=input.Pshaft_W;end
end

function local_progress(options,phase,iteration,maximum)
if ~isfield(options,'progressCallback') || isempty(options.progressCallback),return;end
event=struct('phase',phase,'status','running','iteration',iteration, ...
    'iterationLimit',maximum,'fraction',NaN,'message','');
% 迭代可提前结束且每轮费用不定；不把迭代占比伪装成总耗时进度。
if maximum>0,event.message=sprintf('iteration %d/%d',iteration,maximum);end
try,options.progressCallback(event);
catch e,warning('SHT:SteadyAdaptV2:Callback','可选事件回调失败：%s',e.message);end
end

function tbl = local_add_optional_prediction_column(tbl, name, defaultValue)
if ~ismember(name, tbl.Properties.VariableNames)
    tbl.(name) = defaultValue;
end
end

function tbl = local_input_driven_prediction_table( ...
        input, baseline, corrected, modelMode)
tbl = table(input.point_id, input.inletBoundaryMode, input.Altitude, ...
    input.Pamb, input.Tamb, input.Mach, input.Wf_model, input.Mkp, input.Mkg, ...
    baseline.Np, corrected.Np, baseline.Ng, corrected.Ng, ...
    corrected.Pamb, corrected.Tamb, corrected.Tt1, ...
    corrected.Pt1_internal, corrected.Pt2, ...
    corrected.Pt3, corrected.Tt3, corrected.Tt45, corrected.Pt45, ...
    corrected.np_branch_center_rpm, corrected.np_branch_lower_rpm, ...
    corrected.np_branch_upper_rpm, corrected.np_branch_attempt_count, ...
    corrected.np_branch_passed, ...
    corrected.max_model_residual, corrected.return_code, ...
    corrected.converge_tag, corrected.valid, corrected.error_message, ...
    'VariableNames', {'point_id','inlet_boundary_mode','Altitude_m', ...
    'input_Pamb_Pa','input_Tamb_K','Mach','Wf_model_kg_s','Mkp_Nm','Mkg_Nm','baseline_Np_rpm', ...
    'corrected_Np_rpm','baseline_Ng_rpm','corrected_Ng_rpm', ...
    'model_Pamb_Pa','model_Tamb_K','corrected_Tt1_K', ...
    'corrected_Pt1_Pa','corrected_Pt2_Pa', ...
    'corrected_Pt3_Pa','corrected_Tt3_K','corrected_Tt45_K', ...
    'corrected_Pt45_Pa','Np_branch_center_rpm','Np_branch_lower_rpm', ...
    'Np_branch_upper_rpm','Np_branch_attempt_count','Np_branch_passed', ...
    'max_model_residual','return_code', ...
    'converge_tag','valid','error_message'});
if modelMode == 0
    % 三部件公开预测结果补齐当前正式测点；旧六部件表结构不变。
    tbl.corrected_Ptb3_Pa = corrected.Ptb3;
    tbl.corrected_Ttb3_K = corrected.Ttb3;
    tbl.corrected_Pt6_Pa = corrected.Pt6;
    tbl.corrected_Tt6_K = corrected.Tt6;
    tbl.corrected_Wa2_kg_s = corrected.Wa2;
end
end
