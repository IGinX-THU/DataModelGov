function manifestFile = dmg_init_project(trainingDataFile, resultFile, manifestFile)
%DMG_INIT_PROJECT 项目初始化与零修正回放，返回测量数据表、调度变量表和分组。
%
% 只调用程序包的公共函数，不修改算法包，不调用 local_ 私有函数。
% 零修正回放逻辑参照 sht_steady_model_adapt_v2_common 中 local_run 的开头部分。

startedAt = datestr(now, 31);
try
    programRoot = pwd;

    % 1. 初始化六部件运行时
    runtime = sht_prepare_control_model_runtime(programRoot);
    cfg = sht_default_config(struct('engine', struct('modelMode', 1)));
    if cfg.engine.modelMode ~= 1
        error('DMG:Init:WrongModelMode', '必须使用六部件模型 modelMode=1。');
    end

    % 2. 解析训练数据文件路径
    testDataDir = fullfile(programRoot, 'TestData');
    defaultTraining = fullfile(testDataDir, 'steady_bench_2p4_training_means.xlsx');
    if nargin < 1 || isempty(trainingDataFile)
        trainingFile = defaultTraining;
    else
        trainingFile = sht_resolve_delivery_input_file(trainingDataFile, defaultTraining);
    end
    if ~isfile(trainingFile)
        error('DMG:Init:MissingTrainingData', '训练集不存在：%s。', trainingFile);
    end

    % 3. 读取训练数据（使用公共接口 readmeasurementtable）
    trainingData = sht_steady_model_adapt_v2_common('readmeasurementtable', trainingFile, '训练集');
    required = {'point_id','Np_mean','Ng_mean','Wf_mean','Mkp_mean', ...
        'Mkg_mean','Pt2_mean','Tt1_mean','Pt3_mean','Tt3_mean', ...
        'Tt45_mean','Pt45_mean','Pamb_mean','Tamb_mean', ...
        'Altitude_mean','Mach_mean'};
    columns = trainingData.Properties.VariableNames;
    missingColumns = setdiff(required, columns);
    valid = isempty(missingColumns);
    rowCount = height(trainingData);

    if ~valid
        error('DMG:Init:BadInputSchema', '训练集缺少字段：%s。', strjoin(missingColumns, ', '));
    end
    if rowCount < 1
        error('DMG:Init:EmptyInput', '训练集没有工况点。');
    end

    % 4. 打开发动机 DLL
    engine = sht_engine_open(cfg.engine);
    cleanupObject = onCleanup(@() sht_engine_close(engine));

    % 关闭健康调度（零修正）
    calllib(engine.libraryName, 'DLL_SHT_HealthScheduleSetEnabled', int32(0));

    % 5. 零修正回放：逐工况调用 DLL
    wfDesign = cfg.engine.initial.Wf0;
    baselineRecords = repmat(local_empty_record(), rowCount, 1);
    allValid = true;

    for i = 1:rowCount
        try
            rec = local_replay_one_point(engine, cfg, trainingData(i, :));
            baselineRecords(i) = rec;
            if ~rec.valid
                allValid = false;
                warning('DMG:Init:PointReplayFailed', ...
                    '工况 %s 零修正回放未收敛。', char(trainingData.point_id(i)));
            end
        catch pointError
            baselineRecords(i).point_id = trainingData.point_id(i);
            baselineRecords(i).valid = false;
            baselineRecords(i).error_message = string(pointError.message);
            allValid = false;
        end
    end

    if ~allValid
        warning('DMG:Init:BaselineFailure', ...
            '零修正模型部分工况回放失败，调度变量可能包含缺失值。');
    end

    % 6. 计算 AC 相对换算转速和分组（纯数据计算，不依赖 DLL）
    measuredAcCorrectedSpeed = (trainingData.Ng_mean ./ cfg.engine.initial.Ng0) .* ...
        sqrt(288.15 ./ trainingData.Tt1_mean);
    groups = local_cluster_by_ac_speed(measuredAcCorrectedSpeed, 0.010);

    % 7. 构造测量数据行
    measureRows = cell(rowCount, 1);
    for i = 1:rowCount
        row = struct();
        for c = 1:numel(columns)
            row.(columns{c}) = trainingData{i, c};
        end
        measureRows{i} = row;
    end

    % 8. 构造调度变量行
    scheduleRows = cell(rowCount, 1);
    for i = 1:rowCount
        sr = struct();
        sr.point_id = char(trainingData.point_id(i));
        sr.dataRole = 'training';
        groupId = local_find_group(groups, i);
        if isempty(groupId)
            sr.trainingGroup = 'N/A';
        else
            sr.trainingGroup = sprintf('G%d', groupId);
        end
        sr.acRelativeCorrectedSpeed = measuredAcCorrectedSpeed(i);
        rec = baselineRecords(i);
        if rec.valid
            sr.inletCorrectedMassFlow = rec.inletCorrectedMassFlow;
            sr.burnerInletCorrectedMassFlow = rec.burnerInletCorrectedMassFlow;
            sr.gtTotalPressureRatio = rec.gtTotalPressureRatio;
            sr.gtPtDuctCorrectedMassFlow = rec.gtPtDuctCorrectedMassFlow;
            sr.ptTotalPressureRatio = rec.ptTotalPressureRatio;
            sr.ptNozzleDuctCorrectedMassFlow = rec.ptNozzleDuctCorrectedMassFlow;
            sr.measuredFuelNormalizedCoordinate = trainingData.Wf_mean(i) / wfDesign;
            sr.acCorrectedSpeedDll = rec.acCorrectedSpeedDll;
            sr.converged = true;
            sr.maxModelResidual = rec.maxModelResidual;
        else
            sr.inletCorrectedMassFlow = NaN;
            sr.burnerInletCorrectedMassFlow = NaN;
            sr.gtTotalPressureRatio = NaN;
            sr.gtPtDuctCorrectedMassFlow = NaN;
            sr.ptTotalPressureRatio = NaN;
            sr.ptNozzleDuctCorrectedMassFlow = NaN;
            sr.measuredFuelNormalizedCoordinate = trainingData.Wf_mean(i) / wfDesign;
            sr.acCorrectedSpeedDll = NaN;
            sr.converged = false;
            sr.maxModelResidual = NaN;
        end
        scheduleRows{i} = sr;
    end

    % 9. 构造分组信息
    groupInfo = cell(numel(groups), 1);
    for g = 1:numel(groups)
        gi = struct();
        gi.groupId = sprintf('G%d', g);
        gi.pointIds = char(strjoin(string(trainingData.point_id(groups{g})), ','));
        gi.pointCount = numel(groups{g});
        speeds = measuredAcCorrectedSpeed(groups{g});
        gi.acNcrMean = mean(speeds);
        gi.acNcrMin = min(speeds);
        gi.acNcrMax = max(speeds);
        groupInfo{g} = gi;
    end

    % 10. DLL 哈希
    dllPath = fullfile(programRoot, 'GTESS.dll');
    dllHash = '';
    if isfile(dllPath)
        try
            dllHash = local_file_hash(dllPath);
        catch
            dllHash = '';
        end
    end

    % 11. 保存 MAT 结果
    result = struct();
    result.measureRows = measureRows;
    result.scheduleRows = scheduleRows;
    result.groups = groupInfo;
    result.baselineRecords = baselineRecords;
    result.rowCount = rowCount;
    result.columns = columns;
    result.groupCount = numel(groups);
    result.dllHash = dllHash;
    result.allValid = allValid;
    save(char(resultFile), 'result', '-v7.3');

    % 12. 写入 JSON 清单
    manifest = struct();
    manifest.status = 'SUCCEEDED';
    manifest.entryPoint = 'dmg_init_project';
    manifest.startedAt = startedAt;
    manifest.completedAt = datestr(now, 31);
    manifest.rowCount = rowCount;
    manifest.columns = columns;
    manifest.missingColumns = missingColumns;
    manifest.valid = valid;
    manifest.groupCount = numel(groups);
    manifest.dllHash = dllHash;
    manifest.measureRows = measureRows;
    manifest.scheduleRows = scheduleRows;
    manifest.groups = groupInfo;
    manifest.baselineValid = allValid;
    local_write_json(char(manifestFile), manifest);

    clear cleanupObject;
catch exception
    manifest = struct();
    manifest.status = 'FAILED';
    manifest.entryPoint = 'dmg_init_project';
    manifest.startedAt = startedAt;
    manifest.completedAt = datestr(now, 31);
    manifest.identifier = exception.identifier;
    manifest.message = exception.message;
    local_write_json(char(manifestFile), manifest);
    rethrow(exception);
end
end

% ===================== 零修正回放（使用公共函数） =====================

function record = local_empty_record()
record = struct('point_id', "", 'valid', false, ...
    'inletCorrectedMassFlow', NaN, 'burnerInletCorrectedMassFlow', NaN, ...
    'gtTotalPressureRatio', NaN, 'gtPtDuctCorrectedMassFlow', NaN, ...
    'ptTotalPressureRatio', NaN, 'ptNozzleDuctCorrectedMassFlow', NaN, ...
    'acCorrectedSpeedDll', NaN, 'maxModelResidual', NaN, ...
    'error_message', "");
end

function record = local_replay_one_point(engine, cfg, point)
% 零修正回放单个工况，参照 local_evaluate_point 的稳态路径。
npMeasured = point.Np_mean(1);
ngMeasured = point.Ng_mean(1);
wfInput = point.Wf_mean(1);
fuelBias = 0;  % 零修正
wfModel = wfInput - fuelBias;
if ~isfinite(wfModel) || wfModel <= 0
    error('DMG:Init:NonPositiveFuel', ...
        '工况%s的燃油流量非正。', char(point.point_id));
end

% 轴负载功率（DLL 接口需要功率，不是扭矩）
ptLoadPower = point.Mkp_mean(1) * pi * npMeasured / 30;
gtLoadPower = point.Mkg_mean(1) * pi * ngMeasured / 30;

% 构造 stepInValue
stepInValue = zeros(cfg.engine.interface.stepInLength, 1);
stepInValue(1:10) = [npMeasured; ngMeasured; wfModel; ...
    cfg.engine.boundary.A8; 0; ptLoadPower; gtLoadPower; 0; ...
    cfg.engine.boundary.hpcAlpha; 0];

% 模式4：Pamb/Tamb/Mach/Tt1/Pt2
inletBoundary = struct( ...
    'inletBoundaryMode', 4, ...
    'altitude', point.Altitude_mean(1), ...
    'Mach', point.Mach_mean(1), ...
    'deltaTemperature', 0, ...
    'Pamb', point.Pamb_mean(1), ...
    'Tamb', point.Tamb_mean(1), ...
    'Tt1', point.Tt1_mean(1), ...
    'Pt2', point.Pt2_mean(1));
[stepInValue, ~] = sht_apply_inlet_boundary_stepin(stepInValue, inletBoundary);

% 健康调度关闭，健康参数全零
stepInValue(cfg.engine.interface.healthScheduleEnableIndex) = 0;
healthStart = cfg.engine.interface.healthStartIndex;
stepInValue(healthStart:healthStart + 9) = 0;

% 获取初值
seedInfo = sht_get_steady_trim_initial_guess(cfg, npMeasured, ptLoadPower, 'auto');
if seedInfo.available && numel(seedInfo.varIte) == 9 && all(isfinite(seedInfo.varIte))
    seed = seedInfo.varIte(:);
else
    npRatio = npMeasured / cfg.engine.initial.Np0;
    loadRatio = ptLoadPower / cfg.engine.initial.power0;
    seed = [max(2.5, 6.7 * max(loadRatio, 0.15)); ...
        min(max(0.70 + 0.18 * (1 - loadRatio), 0.5), 0.98); ...
        min(max(0.70 + 0.14 * (1 - loadRatio), 0.5), 0.98); ...
        2.0 + 1.8 * max(loadRatio, 0.1); ...
        1.5 + 1.6 * max(loadRatio, 0.1); ...
        1.5 + 1.5 * max(loadRatio, 0.1); ...
        1.5 + 1.5 * max(loadRatio, 0.1); ...
        1.5 + 1.0 * max(loadRatio, 0.1); ...
        1.5 + 1.0 * max(loadRatio, 0.1)];
end

% 调用稳态求解器（扭矩边界模式）
solve = sht_solve_steady_components_from_seed(engine, cfg, stepInValue, seed, ...
    struct('ptLoadTorqueNm', point.Mkp_mean(1), ...
           'gtLoadTorqueNm', point.Mkg_mean(1)));
eng = solve.engOut.eng;
ret = solve.ret;

% 提取调度变量
record = local_empty_record();
record.point_id = point.point_id(1);
record.maxModelResidual = max(abs([double(eng.errOut(:)); double(eng.Nozzle.y(end))]));

% 换算流量
record.inletCorrectedMassFlow = local_corrected_flow(eng.Ambient.gasPathOut);
record.burnerInletCorrectedMassFlow = local_corrected_flow(eng.HPC2.y);
record.gtPtDuctCorrectedMassFlow = local_corrected_flow(eng.HPT2.y);
record.ptNozzleDuctCorrectedMassFlow = local_corrected_flow(eng.LPT2.y);

% 压比
record.acCorrectedSpeedDll = double(eng.HPC.y(16));
varIte = double(eng.varIte(:));
if numel(varIte) >= 7
    record.gtTotalPressureRatio = varIte(4) * varIte(5);
    record.ptTotalPressureRatio = varIte(6) * varIte(7);
end

% 有效性检查
maxResidual = record.maxModelResidual;
record.valid = ret == 0 && ...
    isfinite(maxResidual) && maxResidual <= 1e-2 && ...
    all(isfinite([record.inletCorrectedMassFlow, record.burnerInletCorrectedMassFlow, ...
    record.gtTotalPressureRatio, record.gtPtDuctCorrectedMassFlow, ...
    record.ptTotalPressureRatio, record.ptNozzleDuctCorrectedMassFlow]));

if ~record.valid
    record.error_message = string(sprintf( ...
        'ret=%d, maxResidual=%.6g', ret, maxResidual));
end
end

function correctedFlow = local_corrected_flow(gasPath)
gasPath = double(gasPath(:));
massFlow = gasPath(1);
totalTemperature = gasPath(3);
totalPressure = gasPath(4);
correctedFlow = massFlow * sqrt(totalTemperature / 288.15) * ...
    101325 / totalPressure;
end

% ===================== 分组（纯数据计算） =====================

function groups = local_cluster_by_ac_speed(correctedSpeed, spanLimit)
correctedSpeed = correctedSpeed(:);
[sortedSpeed, order] = sort(correctedSpeed);
clusterMembers = {};
startIndex = 1;
for i = 2:numel(order)
    if sortedSpeed(i) - sortedSpeed(startIndex) > spanLimit
        clusterMembers{end + 1} = order(startIndex:(i - 1)); %#ok<AGROW>
        startIndex = i;
    end
end
clusterMembers{end + 1} = order(startIndex:end);
groups = clusterMembers;
end

function groupId = local_find_group(groups, rowIndex)
groupId = [];
for i = 1:numel(groups)
    if ismember(rowIndex, groups{i})
        groupId = i;
        return;
    end
end
end

% ===================== 工具函数 =====================

function hash = local_file_hash(filePath)
hasher = java.security.MessageDigest.getInstance('SHA-256');
f = fopen(filePath, 'rb');
cleanup = onCleanup(@() fclose(f));
while ~feof(f)
    block = fread(f, 65536, 'uint8');
    if ~isempty(block)
        hasher.update(block);
    end
end
digest = typecast(hasher.digest(), 'uint8');
hash = lower(reshape(dec2hex(digest, 2), 1, []));
end

function local_write_json(path, value)
[fileId, message] = fopen(path, 'w', 'n', 'UTF-8');
if fileId < 0
    error('DMG:Init:ManifestWriteFailed', '无法写入清单：%s。', message);
end
cleanup = onCleanup(@() fclose(fileId));
fprintf(fileId, '%s', jsonencode(value));
end
