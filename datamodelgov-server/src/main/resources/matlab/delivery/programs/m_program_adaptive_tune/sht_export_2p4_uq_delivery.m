function delivery = sht_export_2p4_uq_delivery(method, runResult)
%SHT_EXPORT_2P4_UQ_DELIVERY 将正式UQ后验发布为Excel阶段交付物。
%
% 工作簿包含参数字典、带权后验样本、边际区间、联合协方差、
% 训练/测试预测区间和验收诊断。隐藏真值、真值覆盖率和仿真误差
% 实现不进入下游正式交付物。MAT只保留为本阶段内部运行缓存。

method = upper(char(string(method)));
if ~ismember(method, {'A','B','C','D'})
    error('SHT:UQDelivery:BadMethod', 'method必须为A、B、C或D。');
end
minimumStepCount = 10;
inferenceStepIndex = 8;
if strcmp(method,'C')
    minimumStepCount = 6;
    inferenceStepIndex = 5;
end
if strcmp(method,'D'),minimumStepCount=4;inferenceStepIndex=3;end
requiredFields = {'steps','posterior','posteriorDiagnostic','validation'};
if ~isstruct(runResult) || ...
        ~all(isfield(runResult,requiredFields)) || ...
        numel(runResult.steps) < minimumStepCount
    error('SHT:UQDelivery:BadRunResult', ...
        'runResult不是完整的2.4 UQ正式结果。');
end
contract = runResult.steps{1}.contract;
posterior = runResult.posterior;
diagnostic = runResult.posteriorDiagnostic;
validation = runResult.validation;
if ~isfield(posterior, 'passed') || ~posterior.passed || ...
        ~isfield(runResult, 'passed') || ~runResult.passed
    error('SHT:UQDelivery:UnacceptedPosterior', ...
        '未通过正式后验/预测验收，拒绝发布下游Excel。');
end

theta = double(posterior.theta);
weight = double(posterior.weights(:));
if size(theta, 1) ~= contract.parameterCount || ...
        size(theta, 2) ~= numel(weight) || any(~isfinite(theta(:))) || ...
        any(~isfinite(weight)) || any(weight < 0) || sum(weight) <= 0
    error('SHT:UQDelivery:BadPosteriorSamples', ...
        '后验样本、权重或参数维数无效。');
end
weight = weight / sum(weight);
if any(theta < contract.lowerBound(:) - 1e-12 | ...
        theta > contract.upperBound(:) + 1e-12, 'all')
    error('SHT:UQDelivery:PosteriorOutsideBounds', ...
        '正式后验样本越过硬边界。');
end

tables = local_build_tables(method, runResult, contract, posterior, ...
    diagnostic, validation, theta, weight, inferenceStepIndex);
programRoot = fileparts(mfilename('fullpath'));
deliveryRoot = fullfile(programRoot, 'MiddleData', ...
    'steady_model_2p4_delivery', 'uq');
if isfield(contract,'modelMode') && contract.modelMode==0
    deliveryRoot=fullfile(programRoot,'MiddleData','three_component','steady_model_2p4_delivery','uq');
end
explicitOutput=isfield(contract.config,'outputDirectory') && ~isempty(contract.config.outputDirectory);
if explicitOutput
    deliveryRoot=fullfile(sht_tc24_absolute_path(contract.config.outputDirectory), ...
        runResult.runId);
end
if exist(deliveryRoot, 'dir') ~= 7
    mkdir(deliveryRoot);
end
runId = char(string(runResult.runId));
if isfield(runResult,'deliveryTag') && ~isempty(runResult.deliveryTag)
    runId=[runId,'_',char(runResult.deliveryTag)];
    tables.Manifest.inference_run_id=string(runResult.runId);
    tables.Manifest.run_id=string(runId);
end
routeTag = char(string(contract.route));
contract12 = char(string(contract.contractHash));
contract12 = contract12(1:12);
fileName = sprintf('2p4_uq_method_%s_%s_%s.xlsx', ...
    lower(method), routeTag, contract12);
deliveryDir = fullfile(deliveryRoot, runId);
if explicitOutput
    % 同一个run已由入口隔离，不再次重复长runId，避免R2019b Excel路径超限。
    deliveryDir=fullfile(deliveryRoot,'Excel');
    fileName=sprintf('posterior_%s.xlsx',lower(method));
end
if exist(deliveryDir, 'file') == 2
    error('SHT:UQDelivery:RunExists', ...
        '不可变UQ交付路径已被文件占用：%s。', deliveryDir);
elseif exist(deliveryDir, 'dir') == 7
    workbookFile = fullfile(deliveryDir,fileName);
    if exist(workbookFile,'file') ~= 2
        error('SHT:UQDelivery:ExistingWorkbookMissing', ...
            '既有不可变UQ目录缺少当前合同工作簿：%s。',workbookFile);
    end
    local_verify_readback(workbookFile,tables);
    local_verify_existing_identity(workbookFile,tables.Manifest);
    existingManifest=readtable(workbookFile,'Sheet','Manifest');
    if ismember(method,{'B','C'}) && ~ismember( ...
            'deterministic_reference_semantics',existingManifest.Properties.VariableNames)
        workbookFile=sht_repackage_2p4_uq_excel(workbookFile,contract);
    end
    fileHash = local_file_hash(workbookFile);
    local_verify_sha_sidecar(workbookFile,fileHash,fileName);
    delivery = local_delivery_metadata(method,routeTag,runId, ...
        workbookFile,fileHash,contract.parameterCount,size(theta,2),weight);
    fprintf('[2.4UQ-Delivery] 复用已验证不可变Excel：%s\n',workbookFile);
    return;
end
uuid = char(java.util.UUID.randomUUID());
if explicitOutput,uuid=uuid(1:8);end
partialDir = fullfile(deliveryRoot, ['.uq.' uuid '.partial']);
cleanupObject = onCleanup(@() local_remove_partial(partialDir, deliveryRoot));
[created, message] = mkdir(partialDir);
if ~created
    error('SHT:UQDelivery:PartialCreateFailure', ...
        '无法创建UQ Excel partial目录：%s。', message);
end
partialFile = fullfile(partialDir, fileName);
local_write_tables(partialFile, tables);
local_verify_readback(partialFile, tables);
fileHash = local_file_hash(partialFile);
sidecar = [partialFile '.sha256'];
fid = fopen(sidecar, 'w', 'n', 'UTF-8');
if fid < 0
    error('SHT:UQDelivery:ShaWriteFailure', '无法写入UQ Excel SHA旁车。');
end
fileCleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s  %s\n', fileHash, fileName);
clear fileCleanup;
[moved, message] = movefile(partialDir, deliveryDir);
if ~moved
    error('SHT:UQDelivery:AtomicPublishFailure', ...
        'UQ Excel交付目录原子发布失败：%s。', message);
end
clear cleanupObject;
workbookFile = fullfile(deliveryDir, fileName);
if ~strcmp(local_file_hash(workbookFile), fileHash)
    error('SHT:UQDelivery:PostPublishHashMismatch', ...
        'UQ Excel发布后哈希发生变化。');
end

delivery = local_delivery_metadata(method,routeTag,runId,workbookFile, ...
    fileHash,contract.parameterCount,size(theta,2),weight);
end

function delivery = local_delivery_metadata(method,routeTag,runId, ...
        workbookFile,fileHash,parameterCount,sampleCount,weight)
delivery = struct('schemaVersion','SHT_2P4_UQ_EXCEL_DELIVERY_V1', ...
    'method',method,'route',routeTag,'runId',runId, ...
    'workbookFile',workbookFile,'workbookSha256',fileHash, ...
    'sha256File',[workbookFile '.sha256'], ...
    'parameterCount',parameterCount,'sampleCount',sampleCount, ...
    'posteriorEss',1/sum(weight.^2),'passed',true, ...
    'hiddenTruthExported',false,'formalInterface','excel');
if strcmp(method,'D'),delivery.posteriorEss=NaN;end
end

function tables = local_build_tables(method, runResult, contract, posterior, ...
        diagnostic, validation, theta, weight, inferenceStepIndex)
nParameter = size(theta, 1);
nSample = size(theta, 2);
essValue = 1 / sum(weight .^ 2);
if strcmp(method,'D'),essValue=NaN;end % 等权局部近似样本数不是全局SMC有效样本数。
maximumWeight = max(weight);
inferenceRoute = string(local_struct_text(validation, ...
    'posteriorInferenceRoute',contract.route));
outputPredictionRoute = string(local_struct_text(validation, ...
    'outputPredictionRoute','steady'));
deterministicHash = "";
deterministicFile = "";
if isfield(contract, 'deterministicWorkbookSha256')
    deterministicHash = string(contract.deterministicWorkbookSha256);
end
if isfield(contract, 'deterministicWorkbookFile')
    deterministicFile = string(contract.deterministicWorkbookFile);
end
tables = struct();
% 新交付显式记录本次后验实际回放资产，不拿确定性Excel历史身份替代。
identityContract=contract;
if isfield(contract,'baseContract'),identityContract=contract.baseContract;end
if isfield(identityContract,'engineArtifacts')
    a=identityContract.engineArtifacts;names=strings(numel(a),1);
    for k=1:numel(a),[~,n,e]=fileparts(a(k).file);names(k)=string([n,e]);end
    tables.RuntimeAssets=table(string({a.kind}).',names,string({a.sha256}).', ...
        'VariableNames',{'kind','name','sha256'});
end
tables.Manifest = table( ...
    "SHT_2P4_UQ_EXCEL_DELIVERY_V1", "2.4", string(method), ...
    string(runResult.runId), string(contract.route),inferenceRoute, ...
    outputPredictionRoute, ...
    string(datestr(now, 31)), "FORMAL_ACCEPTED", ...
    string(contract.contractHash), deterministicHash, deterministicFile, ...
    nParameter, nSample, essValue, maximumWeight, ...
    logical(posterior.passed), logical(validation.passed), false, false, ...
    string(local_struct_text(validation,'uncertaintyScope','not_recorded')), ...
    local_struct_logical(validation,'measurementUncertaintyIncluded',true), ...
    local_struct_logical(validation, ...
        'marginalizedNuisancePredictionIncluded',true), ...
    'VariableNames', {'schema_version','stage_id','method_id','run_id', ...
    'route','posterior_inference_route','output_prediction_route', ...
    'completed_at','formal_status','uq_contract_sha256', ...
    'deterministic_workbook_sha256','deterministic_workbook_file', ...
    'parameter_count','sample_count','posterior_ess', ...
    'maximum_normalized_weight','formal_posterior_passed', ...
    'posterior_prediction_passed','test_data_used_for_inference', ...
    'hidden_truth_exported','prediction_uncertainty_scope', ...
    'measurement_uncertainty_included', ...
    'marginalized_nuisance_prediction_included'});

parameterTable = contract.parameterTable;
if strcmp(method,'D') && isfield(validation,'predictionSampling')
    a=validation.predictionSampling;
    tables.Manifest.prediction_subsampling_enabled=a.enabled;
    tables.Manifest.prediction_sample_count=a.uniquePredictionCount;
    tables.Manifest.prediction_requested_count=a.requestedCount;
    tables.Manifest.prediction_sampling_seed=a.randomSeed;
    tables.Manifest.parameter_posterior_unchanged=a.originalParameterPosteriorUnchanged;
end
if isfield(validation,'predictionConditioning')
    tables.Manifest.prediction_conditioning=string(validation.predictionConditioning);
    tables.Manifest.training_minimum_point_valid_mass=min(validation.trainingPointValidMass);
    tables.Manifest.test_minimum_point_valid_mass=min(validation.testPointValidMass);
    tables.Manifest.interval_stability_confirmed=false;
    tables.Manifest.statistical_calibration_confirmed=false;
    tables.Manifest.uncertainty_quality="SINGLE_RUN_SMC_RESULT";
    if strcmp(method,'D'),tables.Manifest.uncertainty_quality="LOCAL_APPROXIMATION";end
end
if isfield(runResult,'predictionMode'),tables.Manifest.prediction_mode=string(runResult.predictionMode);end
if isfield(validation,'trainingOutputPredictionComputed')
    tables.Manifest.training_output_prediction_computed=validation.trainingOutputPredictionComputed;
end
if isfield(contract,'dBendPrior')
    tables.Manifest.engineering_bend_prior_scale=contract.dBendPrior.factor;
    tables.Manifest.engineering_prior_changed=true;
    tables.EngineeringBendPrior=contract.dBendPrior.table;
end
if isfield(contract,'modelMode')
    tables.Manifest.model_mode=contract.modelMode;
    if contract.modelMode==0,tables.Manifest.inlet_boundary_mode=1;end
    tables.Manifest.pressure_measurement="Pt2";
    if contract.modelMode==0,tables.Manifest.pressure_measurement="Pt1";end
end
parameterIndex = (1:nParameter).';
name = string(parameterTable.name);
baseName = local_table_string(parameterTable, 'base_name', name);
cIndex = local_table_numeric(parameterTable, 'c_index', nan(nParameter,1));
groupKind = local_table_string(parameterTable, 'group_kind', ...
    repmat("unknown",nParameter,1));
coordinate = local_table_numeric(parameterTable, 'coordinate', ...
    zeros(nParameter,1));
axisName = local_table_string(parameterTable, 'axis_name', ...
    repmat("constant",nParameter,1));
unit = local_table_string(parameterTable, 'unit', repmat("1",nParameter,1));
lowerBound = double(contract.lowerBound(:));
upperBound = double(contract.upperBound(:));
priorMean = double(contract.priorMean(:));
priorSigma = double(contract.priorSigma(:));
deterministicEstimate = local_table_numeric(parameterTable, ...
    'point_estimate', nan(nParameter,1));
% B合同的point_estimate被置零用于独立先验，不代表确定性辨识值。
if isfield(contract,'deterministicEstimate') && ...
        numel(contract.deterministicEstimate)==nParameter
    deterministicEstimate=double(contract.deterministicEstimate(:));
end
tables.Manifest.deterministic_reference_semantics="frozen_estimate_not_prior_center";
if isfield(contract,'deterministicRunId')
    tables.Manifest.deterministic_run_id=string(contract.deterministicRunId);
end
posteriorMean = theta * weight;
posteriorStd = sqrt(max(0, sum((theta - posteriorMean).^2 .* ...
    weight.', 2)));
posteriorMedian = zeros(nParameter,1);
posteriorQ025 = zeros(nParameter,1);
posteriorQ975 = zeros(nParameter,1);
for i = 1:nParameter
    q = local_weighted_quantile(theta(i,:), weight, [0.025,0.5,0.975]);
    posteriorQ025(i) = q(1);
    posteriorMedian(i) = q(2);
    posteriorQ975(i) = q(3);
end
logPosterior = double(posterior.logLikelihood(:)) + ...
    double(posterior.logPrior(:));
[~, mapSample] = max(logPosterior);
posteriorMap = theta(:,mapSample);
if strcmp(method,'D'),posteriorMap=diagnostic.map;end
credibleWidth95 = posteriorQ975 - posteriorQ025;
stdContraction = 1 - posteriorStd ./ max(priorSigma, eps);
tables.ParameterSummary = table(parameterIndex,name,baseName,cIndex, ...
    groupKind,coordinate,axisName,unit,lowerBound,upperBound,priorMean, ...
    priorSigma,deterministicEstimate,posteriorMean,posteriorMedian, ...
    posteriorMap,posteriorStd,posteriorQ025,posteriorQ975, ...
    credibleWidth95,stdContraction);

sampleId = (1:nSample).';
sampleWeight = weight;
logLikelihood = double(posterior.logLikelihood(:));
logPrior = double(posterior.logPrior(:));
sampleTable = table(sampleId,sampleWeight,logLikelihood,logPrior);
variableNames = local_parameter_variable_names(name);
for i = 1:nParameter
    sampleTable.(variableNames{i}) = theta(i,:).';
end
tables.PosteriorSamples = sampleTable;

centered = theta - posteriorMean;
covariance = (centered .* weight.') * centered.';
scale = sqrt(max(diag(covariance),eps));
correlation = covariance ./ max(scale*scale.',eps);
matrixNames = arrayfun(@(i) sprintf('p%03d',i), ...
    1:nParameter,'UniformOutput',false);
tables.PosteriorCovariance = array2table(covariance, ...
    'VariableNames',matrixNames);
tables.PosteriorCovariance = addvars(tables.PosteriorCovariance, name, ...
    'Before',1,'NewVariableNames','parameter_name');
tables.PosteriorCorrelation = array2table(correlation, ...
    'VariableNames',matrixNames);
tables.PosteriorCorrelation = addvars(tables.PosteriorCorrelation, name, ...
    'Before',1,'NewVariableNames','parameter_name');
tables.ParameterGroups = contract.parameterGroupTable;

if isfield(diagnostic, 'fixedAnchorTable')
    if ~istable(diagnostic.fixedAnchorTable)
        error('SHT:UQDelivery:InvalidFixedAnchors', ...
            '显式固定锚点必须为table；合法无锚点请提供空table。');
    end
    tables.FixedAnchors = local_public_table(diagnostic.fixedAnchorTable);
elseif isfield(contract, 'deterministicWorkbookFile') && ...
        ~isempty(contract.deterministicWorkbookFile)
    tables.FixedAnchors = local_read_fixed_anchors( ...
        contract.deterministicWorkbookFile);
else
    if isfield(contract,'deterministicFormalInterface') && ...
            contains(string(contract.deterministicFormalInterface),'excel')
        error('SHT:UQDelivery:MissingDeterministicWorkbook', ...
            'Excel合同缺少确定性父工作簿，无法确认固定锚点。');
    end
    tables.FixedAnchors = table();
end
tables.TrainingIntervals = local_public_table(validation.trainingTable);
tables.TestIntervals = local_public_table(validation.testTable);
if isfield(validation,'inletPressureLossTable') && ...
        istable(validation.inletPressureLossTable)
    tables.InletLoss = local_public_table(validation.inletPressureLossTable);
else
    tables.InletLoss = table();
end

stageCount = local_struct_numeric(posterior,'stageCount',NaN);
finalBeta = local_struct_numeric(posterior,'finalBeta',NaN);
dllEvaluationCount = local_struct_numeric(posterior,'dllEvaluationCount',NaN);
dllRuntime_s = local_struct_numeric(posterior,'dllRuntime_s',NaN);
tables.SamplingDiagnostics = table(essValue,maximumWeight,stageCount, ...
    finalBeta,dllEvaluationCount,dllRuntime_s,logical(posterior.passed), ...
    'VariableNames', {'posterior_ess','maximum_normalized_weight', ...
    'stage_count','final_beta','dll_evaluation_count','dll_runtime_s', ...
    'passed'});
tables.PredictionDiagnostics = local_acceptance_table(validation.acceptance);
tables.Verification = local_verification_table( ...
    runResult, contract, theta, weight, tables, inferenceStepIndex);
if isfield(validation,'predictionErrorRealization')
    tables.Manifest.prediction_scenario=string(validation.predictionErrorRealization);
    tables.Manifest.training_fuel_bias_applied_to_new_trial=false;
end
tables.Manifest.distribution_representation="weighted_joint_empirical_posterior";
if strcmp(method,'D')
    tables.Manifest.formal_status=string(diagnostic.quality);
    tables.Manifest.formal_posterior_passed=false;
    tables.Manifest.distribution_representation="bounded_local_quadratic_approximation";
    if isfield(posterior,'samplingMethod')
        tables.Manifest.distribution_representation=string(posterior.samplingMethod);
    end
    tables.Manifest.local_covariance_role="uncorrected_quadratic_proposal_geometry";
    tables.Verification.check_id(1)="local_curvature_supports_approximation";
    tables.LocalApproximation=table(string(diagnostic.quality),diagnostic.converged, ...
        diagnostic.projectedGradient,diagnostic.localRhat,false, ...
        'VariableNames',{'quality','stationary','projected_gradient','local_rhat','formal_global_posterior'});
    tables.LocalQuadraticCenter=table(name,diagnostic.quadraticCenter, ...
        'VariableNames',{'parameter_name','center'});
    tables.LocalCovariance=array2table(diagnostic.untruncatedLocalCovariance,'VariableNames',matrixNames);
end
if isfield(runResult,'conditionalNuisance')
    nc=runResult.conditionalNuisance;
    tables.ConditionalNuisance=nc.parameterTable;
    tables.ConditionalNuisance.prior_actual_mean=nc.priorMean;
    tables.ConditionalNuisance.conditional_sd=sqrt(max(diag(nc.covariance),0));
    tables.ConditionalNuisance.outside_support_probability=nc.marginalOutsideSupportProbability*weight;
    nuisanceNames=cellstr(compose('eta%02d',1:size(nc.mean,1)));
    tables.ConditionalMeans=array2table(nc.mean.','VariableNames',nuisanceNames);
    tables.ConditionalMeans=addvars(tables.ConditionalMeans,sampleId, ...
        'Before',1,'NewVariableNames','sampleId');
    tables.ConditionalMeans.training_physical_valid=nc.trainingValid(:);
    if isfield(nc,'physicalValidityNotEvaluated') && nc.physicalValidityNotEvaluated
        tables.ConditionalMeans.training_physical_valid=nan(size(nc.trainingValid(:)));
        tables.Manifest.conditional_training_validity="not_evaluated_local_linearization";
    end
    tables.ConditionalCovariance=array2table(nc.covariance,'VariableNames',nuisanceNames);
    tables.Manifest.conditional_nuisance_representation=string(nc.representation);
    tables.Manifest.conditional_nuisance_support_clipped=false;
    if isfield(nc,'quadratureSamples')
        q=size(nc.quadratureSamples,2);n=size(nc.mean,2);dEta=size(nc.mean,1);
        if isfield(nc,'gaussianMean') && isfield(nc,'gaussianCovariance')
            % 原始条件高斯参数加硬边界足以恢复整个截断分布，减少正式Excel体积。
            tables.ConditionalGaussianMeans=array2table(nc.gaussianMean.','VariableNames',nuisanceNames);
            tables.ConditionalGaussianMeans=addvars(tables.ConditionalGaussianMeans,sampleId, ...
                'Before',1,'NewVariableNames','sampleId');
            tables.ConditionalGaussianCov=array2table(nc.gaussianCovariance,'VariableNames',nuisanceNames);
            tables.Manifest.conditional_gaussian_encoded=true;
            tables.Manifest.conditional_quadrature_seed=nc.quadratureSeed;
            tables.Manifest.conditional_quadrature_algorithm="Genz_Sobol_static_order_v1";
        else
            cloud=reshape(permute(nc.quadratureSamples,[2,3,1]),q*n,dEta);
            tables.ConditionalQuadrature=array2table(cloud,'VariableNames',nuisanceNames);
            tables.ConditionalQuadrature=addvars(tables.ConditionalQuadrature, ...
                repelem(sampleId,q),repmat((1:q).',n,1),nc.quadratureWeights(:), ...
                'Before',1,'NewVariableNames',{'sampleId','quadratureId','weight'});
        end
        tables.Manifest.conditional_quadrature_count=q;
        tables.Manifest.conditional_covariance_role="average_diagnostic_only_use_bounded_distribution";
    end
end
end

function fixedAnchors = local_read_fixed_anchors(workbookFile)
% 当前V2确定性交付使用CorrectionSchedule；ScheduleNodes仅兼容旧合同。
% R2019b的xlsfinfo可能依赖Excel COM或可选app.xml，失败不能当作无锚点。
% SpreadsheetDatastore的公开sheetnames方法直接读取工作簿，不启动Excel。
if exist(workbookFile,'file') ~= 2
    error('SHT:UQDelivery:MissingDeterministicWorkbook', ...
        '确定性父工作簿不存在：%s。',workbookFile);
end
try
    source = spreadsheetDatastore(workbookFile);
    sheetNames = sheetnames(source,1);
catch cause
    exception = MException('SHT:UQDelivery:UnreadableDeterministicWorkbook', ...
        '无法读取确定性父工作簿的工作表目录：%s。',workbookFile);
    throw(addCause(exception,cause));
end
if any(strcmpi(sheetNames,'CorrectionSchedule'))
    nodes = readtable(workbookFile,'Sheet','CorrectionSchedule', ...
        'PreserveVariableNames',true);
elseif any(strcmpi(sheetNames,'ScheduleNodes'))
    nodes = readtable(workbookFile,'Sheet','ScheduleNodes', ...
        'PreserveVariableNames',true);
else
    error('SHT:UQDelivery:MissingScheduleSheet', ...
        '确定性父工作簿缺少CorrectionSchedule或ScheduleNodes表：%s。',workbookFile);
end

if ~any(ismember({'node_role','zero_anchor'},nodes.Properties.VariableNames))
    error('SHT:UQDelivery:MissingAnchorClassification', ...
        '调度表缺少node_role和zero_anchor，无法判断哪些节点固定。');
end
keep = false(height(nodes),1);
if ismember('node_role',nodes.Properties.VariableNames)
    role = lower(strtrim(string(nodes.node_role)));
    keep = contains(role,'fixed') | contains(role,'anchor');
    if ~any(keep)
        keep = role ~= "estimated" & role ~= "active_execution_node";
    end
end
if ismember('zero_anchor',nodes.Properties.VariableNames)
    zeroAnchor = nodes.zero_anchor;
    if isnumeric(zeroAnchor) || islogical(zeroAnchor)
        keep = keep | logical(zeroAnchor);
    else
        zeroAnchor = lower(strtrim(string(zeroAnchor)));
        keep = keep | ismember(zeroAnchor,["true","1","yes"]);
    end
end
fixedAnchors = local_public_table(nodes(keep,:));
end

function local_write_tables(fileName, tables)
sheetOrder = {'Manifest','ParameterSummary','PosteriorSamples', ...
    'PosteriorCovariance','PosteriorCorrelation','ParameterGroups', ...
    'FixedAnchors','TrainingIntervals','TestIntervals','InletLoss', ...
    'SamplingDiagnostics','PredictionDiagnostics','Verification'};
sheetOrder=[sheetOrder,setdiff(fieldnames(tables),sheetOrder,'stable').'];
for i = 1:numel(sheetOrder)
    name = sheetOrder{i};
    value = tables.(name);
    if isempty(value) || (istable(value) && width(value) == 0)
        value = table("not_applicable", ...
            'VariableNames',{'status'});
    end
    writetable(value,fileName,'Sheet',name);
end
end

function local_verify_readback(fileName, tables)
required = {'Manifest','ParameterSummary','PosteriorSamples','Verification'};
for i = 1:numel(required)
    expected = tables.(required{i});
    actual = readtable(fileName,'Sheet',required{i}, ...
        'PreserveVariableNames',true);
    if strcmp(required{i},'Manifest')
        % V1工作簿允许在Manifest尾部增加不改变统计结果的诊断列。
        % 既有B交付物保持不可变，因此这里只强制公共身份列存在；具体
        % 身份和值继续由local_verify_existing_identity逐项核对。
        identity = {'schema_version','method_id','run_id','route', ...
            'posterior_inference_route','output_prediction_route', ...
            'uq_contract_sha256','deterministic_workbook_sha256', ...
            'parameter_count','sample_count'};
        dimensionsPassed = height(actual) == height(expected) && ...
            all(ismember(identity,actual.Properties.VariableNames));
    else
        dimensionsPassed = height(actual) == height(expected) && ...
            width(actual) == width(expected);
    end
    if ~dimensionsPassed
        error('SHT:UQDelivery:WorkbookReadbackFailure', ...
            '%s写后读回的尺寸不一致。', required{i});
    end
end
% 对新写入和同run复用采用同一锚点检查，不能只验随机样本和清单身份。
local_verify_fixed_anchor_readback(fileName,tables.FixedAnchors);
verification = readtable(fileName,'Sheet','Verification', ...
    'PreserveVariableNames',true);
if any(logical(verification.blocking) & ~logical(verification.passed))
    error('SHT:UQDelivery:WorkbookVerificationFailure', ...
        'UQ Excel写后读回存在阻断失败。');
end
end

function local_verify_fixed_anchor_readback(fileName,expected)
try
    actual = readtable(fileName,'Sheet','FixedAnchors','PreserveVariableNames',true);
catch cause
    exception = MException('SHT:UQDelivery:FixedAnchorReadbackMismatch', ...
        '固定锚点表不可读取：%s。请使用新revision导出，勿覆盖旧工作簿或重签原sidecar。',fileName);
    throw(addCause(exception,cause));
end
if isempty(expected) || width(expected)==0
    valid = height(actual)==1 && isequal(actual.Properties.VariableNames,{'status'}) && ...
        strcmp(string(actual.status(1)),"not_applicable");
else
    valid = height(actual)==height(expected) && ...
        isequal(actual.Properties.VariableNames,expected.Properties.VariableNames);
    if valid
        for j=1:width(expected)
            name=expected.Properties.VariableNames{j};a=actual.(name);e=expected.(name);
            if isnumeric(e) || islogical(e)
                valid=(isnumeric(a)||islogical(a)) && isequaln(double(a),double(e));
            else
                a=string(a);e=string(e);a(ismissing(a))="";e(ismissing(e))="";
                valid=isequal(a,e);
            end
            if ~valid,break;end
        end
    end
end
if ~valid
    error('SHT:UQDelivery:FixedAnchorReadbackMismatch', ...
        '固定锚点的字段、行数或值与当前合同不一致：%s。请使用新revision导出，勿覆盖旧工作簿或重签原sidecar。',fileName);
end
end

function local_verify_existing_identity(fileName,expectedManifest)
actual = readtable(fileName,'Sheet','Manifest', ...
    'PreserveVariableNames',true);
identity = {'schema_version','method_id','run_id','route', ...
    'posterior_inference_route','output_prediction_route', ...
    'uq_contract_sha256','deterministic_workbook_sha256', ...
    'parameter_count','sample_count'};
for i = 1:numel(identity)
    name = identity{i};
    if ~ismember(name,actual.Properties.VariableNames) || ...
            ~ismember(name,expectedManifest.Properties.VariableNames) || ...
            ~isequal(string(actual.(name)(1)), ...
            string(expectedManifest.(name)(1)))
        error('SHT:UQDelivery:ExistingWorkbookIdentityMismatch', ...
            '既有UQ工作簿身份字段%s与当前运行不一致：%s。', ...
            name,fileName);
    end
end
end

function local_verify_sha_sidecar(workbookFile,fileHash,fileName)
sidecar = [workbookFile '.sha256'];
if exist(sidecar,'file') ~= 2
    error('SHT:UQDelivery:ExistingShaMissing', ...
        '既有UQ工作簿缺少SHA-256旁车：%s。',sidecar);
end
tokens = regexp(strtrim(fileread(sidecar)),'\s+','split');
if numel(tokens) < 2 || ~strcmpi(tokens{1},fileHash) || ...
        ~strcmp(tokens{2},fileName)
    error('SHT:UQDelivery:ExistingShaMismatch', ...
        '既有UQ工作簿与SHA-256旁车不一致：%s。',workbookFile);
end
end

function tbl = local_verification_table(runResult,contract,theta,weight, ...
        tables,inferenceStepIndex)
checkId = ["formal_posterior_accepted";"prediction_accepted"; ...
    "weights_finite_normalized";"samples_within_bounds"; ...
    "parameter_dimension";"excel_deterministic_input"; ...
    "test_data_not_used_for_inference";"hidden_truth_not_exported"; ...
    "steady_output_prediction_only"];
passed = [logical(runResult.posterior.passed);logical(runResult.validation.passed); ...
    all(isfinite(weight)) && abs(sum(weight)-1) <= 1e-12; ...
    all(theta >= contract.lowerBound(:)-1e-12 & ...
    theta <= contract.upperBound(:)+1e-12,'all'); ...
    size(theta,1) == contract.parameterCount; ...
    isfield(contract,'deterministicFormalInterface') && ...
    contains(string(contract.deterministicFormalInterface),'excel'); ...
    ~local_struct_logical(runResult.steps{inferenceStepIndex}, ...
        'testDataRead',false); ...
    ~local_table_has_private_columns(tables.TrainingIntervals) && ...
    ~local_table_has_private_columns(tables.TestIntervals); ...
    strcmp(local_struct_text(runResult.validation, ...
        'outputPredictionRoute',''),'steady') && ...
    ~local_struct_logical(runResult.validation, ...
        'transientInstantOutputUncertaintyAnalyzed',true)];
blocking = true(size(passed));
if isfield(runResult.validation,'posteriorDeliveryReady'),blocking(2)=false;end
detail = [string(runResult.posterior.passed);string(runResult.validation.passed); ...
    sprintf('sum=%.17g',sum(weight)); ...
    sprintf('min_margin=%.3e',min([theta-contract.lowerBound(:); ...
    contract.upperBound(:)-theta],[],'all')); ...
    sprintf('%d/%d',size(theta,1),contract.parameterCount); ...
    string(local_struct_text(contract,'deterministicFormalInterface','')); ...
    string(local_struct_logical( ...
        runResult.steps{inferenceStepIndex},'testDataRead',false)); ...
    "truth/hidden columns removed"; ...
    string(local_struct_text(runResult.validation, ...
        'outputPredictionRoute',''))];
tbl = table(checkId,logical(passed),blocking,detail, ...
    'VariableNames',{'check_id','passed','blocking','detail'});
end

function value = local_table_string(tbl,name,defaultValue)
if ismember(name,tbl.Properties.VariableNames)
    value = string(tbl.(name));
else
    value = string(defaultValue);
end
value = value(:);
end

function value = local_table_numeric(tbl,name,defaultValue)
if ismember(name,tbl.Properties.VariableNames)
    value = double(tbl.(name));
else
    value = double(defaultValue);
end
value = value(:);
end

function names = local_parameter_variable_names(parameterNames)
raw = matlab.lang.makeValidName(cellstr("theta_" + parameterNames));
names = matlab.lang.makeUniqueStrings(raw, {'sampleId','sampleWeight', ...
    'logLikelihood','logPrior'});
end

function q = local_weighted_quantile(value,weight,probability)
[value,order] = sort(double(value(:)));
weight = double(weight(order));
weight = weight / sum(weight);
cumulative = cumsum(weight);
q = zeros(size(probability));
for i = 1:numel(probability)
    index = find(cumulative >= probability(i),1,'first');
    if isempty(index), index = numel(value); end
    q(i) = value(index);
end
end

function tbl = local_public_table(tbl)
if ~istable(tbl), tbl = table(); return; end
name = string(tbl.Properties.VariableNames);
private = contains(lower(name),'truth') | contains(lower(name),'hidden') | ...
    contains(lower(name),'validation_only');
tbl(:,private) = [];
end

function value = local_table_has_private_columns(tbl)
if ~istable(tbl), value = false; return; end
name = lower(string(tbl.Properties.VariableNames));
value = any(contains(name,'truth') | contains(name,'hidden'));
end

function tbl = local_acceptance_table(value)
if ~isstruct(value) || isempty(fieldnames(value))
    tbl = table("not_available",false, ...
        'VariableNames',{'metric','value'});
    return;
end
names = string(fieldnames(value));
metric = strings(0,1);
textValue = strings(0,1);
for i = 1:numel(names)
    one = value.(char(names(i)));
    if isscalar(one) && (isnumeric(one) || islogical(one) || ...
            ischar(one) || isstring(one))
        metric(end+1,1) = names(i); %#ok<AGROW>
        textValue(end+1,1) = string(one); %#ok<AGROW>
    end
end
tbl = table(metric,textValue,'VariableNames',{'metric','value'});
end

function value = local_struct_numeric(s,name,defaultValue)
if isstruct(s) && isfield(s,name) && isnumeric(s.(name)) && ...
        isscalar(s.(name))
    value = double(s.(name));
else
    value = defaultValue;
end
end

function value = local_struct_logical(s,name,defaultValue)
if isstruct(s) && isfield(s,name) && isscalar(s.(name))
    value = logical(s.(name));
else
    value = defaultValue;
end
end

function value = local_struct_text(s,name,defaultValue)
if isstruct(s) && isfield(s,name)
    value = char(string(s.(name)));
else
    value = defaultValue;
end
end

function local_remove_partial(partialDir,deliveryRoot)
if exist(partialDir,'dir') ~= 7, return; end
if ~startsWith(lower(local_canonical(partialDir)), ...
        lower([local_canonical(deliveryRoot) filesep])) || ...
        ~contains(string(fileparts(partialDir)), ...
        'steady_model_2p4_delivery')
    warning('SHT:UQDelivery:UnsafePartialCleanupRefused', ...
        '拒绝清理越界UQ partial目录：%s。',partialDir);
    return;
end
rmdir(partialDir,'s');
end

function value = local_canonical(pathValue)
value = char(javaObject('java.io.File',char(pathValue)).getCanonicalPath());
end

function hashText = local_file_hash(fileName)
fileId = fopen(fileName,'r');
if fileId < 0
    error('SHT:UQDelivery:HashReadFailed', ...
        '无法读取文件并计算SHA-256：%s。',fileName);
end
cleanupObject = onCleanup(@() fclose(fileId));
digest = java.security.MessageDigest.getInstance('SHA-256');
while true
    % 与确定性Excel接口使用同一R2020a安全实现，确保旁车冻结内容而非长度。
    value = fread(fileId,1024*1024,'*uint8');
    if isempty(value), break; end
    digest.update(typecast(value(:),'int8'));
end
clear cleanupObject;
raw = typecast(int8(digest.digest()),'uint8');
hashText = lower(reshape(dec2hex(raw,2).',1,[]));
end
