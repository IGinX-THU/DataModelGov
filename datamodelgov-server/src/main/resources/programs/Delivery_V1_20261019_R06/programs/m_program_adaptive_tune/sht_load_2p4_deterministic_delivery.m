function delivery = sht_load_2p4_deterministic_delivery(route, workbookFile, usage)
%SHT_LOAD_2P4_DETERMINISTIC_DELIVERY 读取2.4确定性辨识交付结果。
%
% 每条路径只有一个固定Excel阶段接口：
%   2p4_deterministic_steady.xlsx
%   2p4_deterministic_transient_instant.xlsx
% usage='formal'只读Excel，不读取训练表、MAT或SHA旁车。
% 默认internal_audit保持既有UQ/调试调用兼容；新正式预测显式选择formal。
% V3追加NpBranchModel，支持完整独立预测；V2保留内部审计兼容。
% Jacobian、迭代历史、回放配置等工程内部数据保存在由run_id定位
% 的不可变MAT侧车中。收敛状态是诊断信息，不是下游读取门槛。

if nargin < 3, usage='internal_audit'; end
assert(ismember(string(usage),["formal","internal_audit"]), ...
    'SHT:DeterministicDelivery:BadUsage','usage应为formal或internal_audit。');
formalUse=strcmp(usage,'formal');
route = char(string(route));
if ~ismember(route, {'steady','transient_instant'})
    error('SHT:DeterministicDelivery:BadRoute', ...
        'route必须为steady或transient_instant。');
end
if nargin < 2
    workbookFile = '';
end
workbookFile = char(string(workbookFile));

programRoot = fileparts(mfilename('fullpath'));
projectRoot = fileparts(programRoot);
defaultFile = fullfile(programRoot, 'MiddleData', ...
    'steady_model_2p4_delivery', ...
    sprintf('2p4_deterministic_%s.xlsx', route));
if isempty(strtrim(workbookFile))
    workbookFile = defaultFile;
else
    workbookFile = sht_resolve_delivery_input_file(workbookFile, defaultFile);
end
if exist(workbookFile, 'file') ~= 2
    error('SHT:DeterministicDelivery:WorkbookMissing', ...
        '未找到2.4确定性Excel交付物：%s。', workbookFile);
end
if ~formalUse
    local_assert_under_root(workbookFile, projectRoot, 'Excel交付物');
end

manifest = local_read_table(workbookFile, 'Manifest');
correctionSchedule = local_read_table(workbookFile, 'CorrectionSchedule');
measurementBias = local_read_table(workbookFile, 'MeasurementBias');
local_validate_manifest(manifest, route);
local_validate_correction_schedule(correctionSchedule);
local_validate_measurement_bias(measurementBias);
npBranchModel=table();
if string(manifest.schema_version(1))=="SHT_2P4_DETERMINISTIC_EXCEL_DELIVERY_V3"
    npBranchModel=local_read_table(workbookFile,'NpBranchModel');
elseif formalUse
    error('SHT:DeterministicDelivery:UpgradeRequired', ...
        '旧V2交付物缺少独立Np选根模型，请用当前导出入口重新导出，不需要重新辨识。');
end
if height(correctionSchedule) ~= ...
        double(manifest.correction_schedule_row_count(1)) || ...
        height(measurementBias) ~= ...
        double(manifest.measurement_bias_row_count(1))
    error('SHT:DeterministicDelivery:WorkbookRowCountMismatch', ...
        'Manifest记录的调度/偏置行数与Excel实际内容不一致。');
end

expectedSemanticHash = local_semantic_payload_hash( ...
    manifest, correctionSchedule, measurementBias, npBranchModel);
if ~strcmp(expectedSemanticHash, ...
        char(string(manifest.semantic_payload_sha256(1))))
    error('SHT:DeterministicDelivery:SemanticHashMismatch', ...
        'Excel最小交付载荷的语义SHA-256不一致。');
end
workbookHash = local_file_hash(workbookFile);
if ~formalUse, local_verify_sha_sidecar(workbookFile, workbookHash); end

runId = char(string(manifest.run_id(1)));
if formalUse
    model=sht_steady_model_adapt_v2_common('restoredeliverymodel', ...
        manifest,correctionSchedule,measurementBias,npBranchModel);
    delivery=struct('schemaVersion',char(string(manifest.schema_version(1))), ...
        'route',route,'runId',runId,'workbookFile',workbookFile, ...
        'workbookSha256',workbookHash,'manifest',manifest, ...
        'correctionSchedule',correctionSchedule,'measurementBias',measurementBias, ...
        'npBranchModel',npBranchModel,'model',model, ...
        'solverConverged',local_as_logical(manifest.solver_converged(1)), ...
        'stopReason',char(string(manifest.stop_reason(1))), ...
        'formalInterface','standalone_excel','internalDataRead',false);
    return;
end
replaySidecarFile = fullfile(programRoot, 'MiddleData', ...
    'steady_model_adapt_v2_runs', runId, 'result.mat');
if double(manifest.model_mode(1))==0
    replaySidecarFile=fullfile(programRoot,'MiddleData','three_component', ...
        'steady_model_adapt_v2_runs',runId,'result.mat');
end
local_assert_under_root(replaySidecarFile, projectRoot, 'DLL回放侧车');
if exist(replaySidecarFile, 'file') ~= 2
    error('SHT:DeterministicDelivery:ReplaySidecarMissing', ...
        ['Excel已定位run=%s，但内部MAT侧车不存在：%s。' ...
         '该MAT只供程序开发、调试和DLL精确回放使用。'], ...
        runId, replaySidecarFile);
end
loaded = load(replaySidecarFile, 'result');
if ~isfield(loaded, 'result') || ~isstruct(loaded.result)
    error('SHT:DeterministicDelivery:BadReplaySidecar', ...
        '内部MAT侧车缺少result结构。');
end
result = loaded.result;
local_verify_replay_identity(result, manifest, correctionSchedule, ...
    measurementBias, route, runId);

trainingFile = fullfile(programRoot, 'TestData', ...
    'steady_bench_2p4_training_means.xlsx');
if double(manifest.model_mode(1))==0
    trainingFile=fullfile(programRoot,'TestData','three_component','tc24_training_means.xlsx');
end
if exist(trainingFile, 'file') ~= 2 || ...
        ~strcmp(local_file_hash(trainingFile), ...
        char(string(manifest.training_data_sha256(1))))
    error('SHT:DeterministicDelivery:TrainingDataHashMismatch', ...
        '当前正式训练Excel与确定性交付合同不一致。');
end

delivery = struct();
delivery.schemaVersion = char(string(manifest.schema_version(1)));
delivery.route = route;
delivery.runId = runId;
delivery.workbookFile = workbookFile;
delivery.workbookSha256 = workbookHash;
delivery.semanticPayloadSha256 = expectedSemanticHash;
delivery.deterministicContractSha256 = ...
    char(string(manifest.deterministic_contract_sha256(1)));
delivery.nodeContractSha256 = ...
    char(string(manifest.node_contract_sha256(1)));
delivery.manifest = manifest;
delivery.correctionSchedule = correctionSchedule;
delivery.measurementBias = measurementBias;
delivery.solverConverged = local_as_logical(manifest.solver_converged(1));
delivery.stopReason = char(string(manifest.stop_reason(1)));
delivery.trainingFile = trainingFile;
delivery.replaySidecarFile = replaySidecarFile;
delivery.replaySidecarSha256 = local_file_hash(replaySidecarFile);
delivery.result = result;
delivery.npBranchModel = npBranchModel;
delivery.formalInterface = ...
    'excel_minimal_authoritative_mat_internal_replay_sidecar';
end

function local_validate_manifest(manifest, route)
required = {'schema_version','stage_id','method_id','run_id','route', ...
    'delivery_status','result_quality_status','solver_converged', ...
    'convergence_is_delivery_gate','stop_reason','configured_lambda', ...
    'model_mode','inlet_boundary_mode','parameter_dictionary_id', ...
    'schedule_schema_version','interpolation','endpoint_policy', ...
    'correction_schedule_row_count','measurement_bias_row_count', ...
    'semantic_payload_sha256','deterministic_contract_sha256', ...
    'node_contract_sha256','training_data_sha256', ...
    'test_data_used_for_inference','hidden_truth_used_for_inference', ...
    'internal_mat_relative_path'};
local_require_columns(manifest, required, 'Manifest');
if height(manifest) ~= 1
    error('SHT:DeterministicDelivery:BadManifestRows', ...
        'Manifest必须且只能有1行。');
end
if ~ismember(string(manifest.schema_version(1)), ...
        ["SHT_2P4_DETERMINISTIC_EXCEL_DELIVERY_V2", ...
         "SHT_2P4_DETERMINISTIC_EXCEL_DELIVERY_V3"]) || ...
        string(manifest.stage_id(1)) ~= "2.4" || ...
        string(manifest.method_id(1)) ~= "M3" || ...
        string(manifest.delivery_status(1)) ~= "DELIVERED"
    error('SHT:DeterministicDelivery:BadDeliveryContract', ...
        'Excel不是可交付的2.4 M3 V2结果。');
end
if string(manifest.route(1)) ~= string(route)
    error('SHT:DeterministicDelivery:RouteMismatch', ...
        'Excel路线%s与请求路线%s不一致。', ...
        string(manifest.route(1)), string(route));
end
if local_as_logical(manifest.convergence_is_delivery_gate(1))
    error('SHT:DeterministicDelivery:ConvergenceGateReintroduced', ...
        '现行合同不允许把收敛状态作为下游读取门槛。');
end
if local_as_logical(manifest.test_data_used_for_inference(1)) || ...
        local_as_logical(manifest.hidden_truth_used_for_inference(1))
    error('SHT:DeterministicDelivery:InferenceContamination', ...
        '确定性Excel记录了测试数据或隐藏真值泄漏。');
end
if ~isfinite(double(manifest.configured_lambda(1))) || ...
        double(manifest.configured_lambda(1)) <= 0
    error('SHT:DeterministicDelivery:BadLambda', ...
        'Manifest中的正则化系数无效。');
end
end

function local_validate_correction_schedule(tbl)
required = {'correction_name','c_index','schedule_kind','axis_name', ...
    'axis_unit','node_index','coordinate','correction_value', ...
    'correction_unit','interpolation','endpoint_policy','zero_anchor', ...
    'lower_bound','upper_bound','source_method','node_role'};
local_require_columns(tbl, required, 'CorrectionSchedule');
numeric = [double(tbl.c_index), double(tbl.node_index), ...
    double(tbl.coordinate), double(tbl.correction_value), ...
    double(tbl.lower_bound), double(tbl.upper_bound)];
if isempty(tbl) || any(~isfinite(numeric(:))) || ...
        any(double(tbl.correction_value) < double(tbl.lower_bound)) || ...
        any(double(tbl.correction_value) > double(tbl.upper_bound))
    error('SHT:DeterministicDelivery:BadCorrectionSchedule', ...
        'CorrectionSchedule为空、存在非有限值或超出物理边界。');
end
expectedCIndex = [0; 1; 2; 6; 7; 8; 10; 11; 12; 14; 15];
if ~isequal(unique(double(tbl.c_index)), expectedCIndex)
    error('SHT:DeterministicDelivery:IncompleteCorrectionClasses', ...
        'CorrectionSchedule未完整包含进气道、总体部件和喷管修正系数。');
end
for i = 1:numel(expectedCIndex)
    one = tbl(double(tbl.c_index) == expectedCIndex(i), :);
    [nodeIndex, order] = sort(double(one.node_index));
    one = one(order, :);
    if ~isequal(nodeIndex, (1:height(one)).')
        error('SHT:DeterministicDelivery:BadCorrectionNodeIndex', ...
            'c_index=%d的节点编号不连续。', expectedCIndex(i));
    end
    kind = unique(string(one.schedule_kind));
    if expectedCIndex(i) == 15
        if height(one) ~= 1 || kind ~= "constant" || ...
                string(one.interpolation(1)) ~= "constant"
            error('SHT:DeterministicDelivery:BadConstantCorrection', ...
                'Nozzle_K_A8必须是单节点常值。');
        end
    elseif numel(kind) ~= 1 || kind ~= "scheduled" || ...
            any(diff(double(one.coordinate)) <= 0) || ...
            any(string(one.interpolation) ~= "linear")
        error('SHT:DeterministicDelivery:BadScheduledCorrection', ...
            'c_index=%d的线性调度节点不合法。', expectedCIndex(i));
    end
    anchor = arrayfun(@local_as_logical, one.zero_anchor);
    if any(anchor & (abs(double(one.coordinate)) > 1e-14 | ...
            abs(double(one.correction_value)) > 1e-14))
        error('SHT:DeterministicDelivery:BadZeroAnchor', ...
            'c_index=%d的零流量固定锚点不是(0,0)。', expectedCIndex(i));
    end
end
end

function local_validate_measurement_bias(tbl)
required = {'bias_name','bias_type','axis_name','axis_unit', ...
    'node_index','coordinate','bias_value','bias_unit','interpolation', ...
    'endpoint_policy','lower_bound','upper_bound','reference_value', ...
    'source_method'};
local_require_columns(tbl, required, 'MeasurementBias');
numeric = [double(tbl.node_index), double(tbl.coordinate), ...
    double(tbl.bias_value), double(tbl.lower_bound), ...
    double(tbl.upper_bound), double(tbl.reference_value)];
if isempty(tbl) || any(~isfinite(numeric(:))) || ...
        any(string(tbl.bias_name) ~= "Wf_bias") || ...
        any(string(tbl.bias_unit) ~= "kg/s") || ...
        any(string(tbl.interpolation) ~= "linear") || ...
        any(diff(double(tbl.coordinate)) <= 0) || ...
        ~isequal(double(tbl.node_index), (1:height(tbl)).') || ...
        any(double(tbl.bias_value) < double(tbl.lower_bound)) || ...
        any(double(tbl.bias_value) > double(tbl.upper_bound))
    error('SHT:DeterministicDelivery:BadMeasurementBias', ...
        'MeasurementBias中的Wf_bias调度不完整或数值无效。');
end
end

function local_verify_replay_identity(result, manifest, correction, bias, ...
        route, runId)
required = {'runId','route','deterministicContractHash','nodeContractHash', ...
    'finalSchedule','parameterDefinition','options','identity','acceptance', ...
    'stageRefine'};
if ~all(isfield(result, required))
    error('SHT:DeterministicDelivery:IncompleteReplaySidecar', ...
        '内部MAT侧车缺少现行M3合同字段。');
end
if ~strcmp(result.runId, runId) || ~strcmp(result.route, route) || ...
        ~strcmp(result.deterministicContractHash, ...
        char(string(manifest.deterministic_contract_sha256(1)))) || ...
        ~strcmp(result.nodeContractHash, ...
        char(string(manifest.node_contract_sha256(1))))
    error('SHT:DeterministicDelivery:ReplayIdentityMismatch', ...
        'Excel与内部MAT侧车的run/路线/合同哈希不一致。');
end
if abs(double(manifest.configured_lambda(1)) - ...
        result.options.stageDM3RegularizationStrength) > ...
        64 * eps(max(1, abs(result.options.stageDM3RegularizationStrength)))
    error('SHT:DeterministicDelivery:LambdaIdentityMismatch', ...
        'Excel与内部MAT侧车的正则化系数不一致。');
end
solverConverged = isfield(result.acceptance, 'allStagesConverged') && ...
    logical(result.acceptance.allStagesConverged);
if local_as_logical(manifest.solver_converged(1)) ~= solverConverged || ...
        string(manifest.stop_reason(1)) ~= string(result.stageRefine.stopReason) || ...
        double(manifest.model_mode(1)) ~= result.options.modelMode || ...
        double(manifest.inlet_boundary_mode(1)) ~= ...
        result.options.inletBoundaryMode || ...
        string(manifest.schedule_schema_version(1)) ~= ...
        string(result.finalSchedule.schemaVersion) || ...
        string(manifest.interpolation(1)) ~= ...
        string(result.finalSchedule.interpolation) || ...
        string(manifest.endpoint_policy(1)) ~= ...
        string(result.finalSchedule.extrapolation)
    error('SHT:DeterministicDelivery:ManifestReplayMismatch', ...
        'Excel Manifest与内部MAT侧车的求解诊断或模型配置不一致。');
end
local_compare_correction_with_result(correction, result);
local_compare_bias_with_result(bias, result);
end

function local_compare_correction_with_result(tbl, result)
schedule = result.finalSchedule;
for i = 1:numel(schedule.healthEntries)
    entry = schedule.healthEntries(i);
    one = tbl(double(tbl.c_index) == entry.cIndex, :);
    [~, order] = sort(double(one.node_index));
    one = one(order, :);
    if height(one) ~= numel(entry.xNodes) || ...
            any(string(one.correction_name) ~= string(entry.name)) || ...
            any(string(one.axis_name) ~= string(entry.axisName)) || ...
            local_max_abs(double(one.coordinate), entry.xNodes) > 1e-12 || ...
            local_max_abs(double(one.correction_value), entry.kNodes) > 1e-12
        error('SHT:DeterministicDelivery:CorrectionScheduleMismatch', ...
            'Excel与内部MAT侧车的%s调度曲线不一致。', entry.name);
    end
end
nozzle = tbl(double(tbl.c_index) == 15, :);
if height(nozzle) ~= 1 || ...
        abs(double(nozzle.correction_value(1)) - schedule.h15) > 1e-12
    error('SHT:DeterministicDelivery:NozzleCorrectionMismatch', ...
        'Excel与内部MAT侧车的Nozzle_K_A8不一致。');
end
end

function local_compare_bias_with_result(tbl, result)
fuel = result.finalSchedule.fuelBias;
if height(tbl) ~= numel(fuel.xNodes) || ...
        local_max_abs(double(tbl.coordinate), fuel.xNodes) > 1e-12 || ...
        local_max_abs(double(tbl.bias_value), fuel.biasNodes) > 1e-12 || ...
        any(string(tbl.bias_unit) ~= "kg/s")
    error('SHT:DeterministicDelivery:MeasurementBiasMismatch', ...
        'Excel与内部MAT侧车的Wf_bias调度不一致。');
end
end

function hashText = local_semantic_payload_hash(manifest, correction, bias, branch)
tables = struct('Manifest', manifest, 'CorrectionSchedule', correction, ...
    'MeasurementBias', bias);
sheetName = {'Manifest','CorrectionSchedule','MeasurementBias'};
if ~isempty(branch)
    tables.NpBranchModel=branch;
    sheetName{end+1}='NpBranchModel';
end
line = strings(0, 1);
for i = 1:numel(sheetName)
    tbl = tables.(sheetName{i});
    if strcmp(sheetName{i}, 'Manifest')
        tbl = removevars(tbl, 'semantic_payload_sha256');
    end
    line(end + 1, 1) = "SHEET|" + string(sheetName{i}); %#ok<AGROW>
    line = [line; local_table_canonical_lines(tbl)]; %#ok<AGROW>
end
hashText = local_text_hash(strjoin(cellstr(line), newline));
end

function line = local_table_canonical_lines(tbl)
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
            if isnan(one)
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

function hashText = local_text_hash(textValue)
digest = java.security.MessageDigest.getInstance('SHA-256');
bytes = unicode2native(char(textValue), 'UTF-8');
if ~isempty(bytes)
    digest.update(typecast(uint8(bytes(:)), 'int8'));
end
raw = typecast(int8(digest.digest()), 'uint8');
hashText = lower(reshape(dec2hex(raw, 2).', 1, []));
end

function tbl = local_read_table(fileName, sheetName)
try
    tbl = readtable(fileName, 'Sheet', sheetName, ...
        'PreserveVariableNames', true, 'TextType', 'string');
catch
    tbl = readtable(fileName, 'Sheet', sheetName, ...
        'PreserveVariableNames', true);
end
end

function local_require_columns(tbl, names, sheetName)
missing = setdiff(names, tbl.Properties.VariableNames);
if ~isempty(missing)
    error('SHT:DeterministicDelivery:MissingWorkbookColumns', ...
        '%s缺少字段：%s。', sheetName, strjoin(missing, ', '));
end
end

function value = local_as_logical(value)
if islogical(value)
    value = value(1);
elseif isnumeric(value)
    value = isfinite(value(1)) && value(1) ~= 0;
else
    textValue = lower(strtrim(char(string(value(1)))));
    if ismember(textValue, {'true','1','yes'})
        value = true;
    elseif ismember(textValue, {'false','0','no',''})
        value = false;
    else
        error('SHT:DeterministicDelivery:BadLogicalValue', ...
            '无法把%s解释为逻辑值。', textValue);
    end
end
end

function local_verify_sha_sidecar(fileName, actualHash)
sidecar = [fileName '.sha256'];
if exist(sidecar, 'file') ~= 2
    error('SHT:DeterministicDelivery:ShaSidecarMissing', ...
        'Excel缺少SHA-256旁车：%s。', sidecar);
end
content = strtrim(fileread(sidecar));
token = regexp(content, '^([0-9a-fA-F]{64})\s+', 'tokens', 'once');
if isempty(token) || ~strcmpi(token{1}, actualHash)
    error('SHT:DeterministicDelivery:ShaMismatch', ...
        'Excel字节哈希与SHA-256旁车不一致。');
end
end

function value = local_max_abs(a, b)
if numel(a) ~= numel(b)
    value = inf;
elseif isempty(a)
    value = 0;
else
    value = max(abs(a(:) - b(:)));
end
end

function local_assert_under_root(pathValue, rootValue, label)
pathCanonical = local_canonical(pathValue);
rootCanonical = local_canonical(rootValue);
prefix = [rootCanonical filesep];
if ~strcmpi(pathCanonical, rootCanonical) && ...
        ~startsWith(lower(pathCanonical), lower(prefix))
    error('SHT:DeterministicDelivery:PathOutsideProject', ...
        '%s越过当前项目边界：%s。', label, pathValue);
end
end

function value = local_canonical(pathValue)
value = char(javaObject('java.io.File', char(pathValue)).getCanonicalPath());
end

function hashText = local_file_hash(fileName)
fileId = fopen(fileName, 'r');
if fileId < 0
    error('SHT:DeterministicDelivery:HashReadFailed', ...
        '无法读取文件并计算SHA-256：%s。', fileName);
end
cleanupObject = onCleanup(@() fclose(fileId));
digest = java.security.MessageDigest.getInstance('SHA-256');
while true
    value = fread(fileId, 1024 * 1024, '*uint8');
    if isempty(value), break; end
    digest.update(typecast(value(:), 'int8'));
end
clear cleanupObject;
raw = typecast(int8(digest.digest()), 'uint8');
hashText = lower(reshape(dec2hex(raw, 2).', 1, []));
end
