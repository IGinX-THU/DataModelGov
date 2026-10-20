function varargout=sht_f34_io(action,varargin)
%SHT_F34_IO 3.4 R1正式Excel交付、回读与递推接口。
% 正式交付只包含下游重现后验、条件形状分布、跨架次传播和预测
% 所需的信息。隐藏真值、调试中间量和仿真误差实现不写入该工作簿。
switch lower(char(action))
    case 'export'
        varargout{1}=local_export(varargin{:});
    case 'readposterior'
        varargout{1}=local_read_posterior(varargin{1});
    case 'verify'
        varargout{1}=local_verify(varargin{1});
    case 'previewtables'
        % 纯格式预览，用于无预测交付核查；不发布文件，不改签统计结果。
        % export仍独立执行完整身份/实现核验，不能用预览绕过正式交付检查。
        varargout{1}=local_build_tables(varargin{:});
    otherwise
        error('SHT:F34IO:Action','未知3.4 IO动作：%s。',char(action));
end
end

function delivery=local_export(prepared,likelihood,methodD,methodC,prediction)
if nargin<5,prediction=[];end
if ~isempty(prediction)
    assert(isfield(prediction,'posteriorPredictionIdentity')&& ...
        strcmp(prediction.posteriorPredictionIdentity, ...
        sht_f34_prediction_identity(likelihood,methodD,methodC)), ...
        'SHT:F34IO:PredictionStale','预测不对应当前实际样本/权重/条件参数及源码。');
end
local_validate_result(prepared,methodD,methodC);
if ~isfield(likelihood,'preparedContractSha256')|| ...
        ~strcmp(likelihood.preparedContractSha256,sht_f33_model_adapt_v2( ...
        'structHash',prepared.contract))
    error('SHT:F34IO:PreparedLineage', ...
        '似然与当前准备合同不一致，禁止发布历史合同结果。');
end
if ~isfield(methodD,'likelihoodContractHash')|| ...
        ~isfield(methodC,'likelihoodContractHash')|| ...
        ~strcmp(methodD.likelihoodContractHash,likelihood.contractHash)|| ...
        ~strcmp(methodC.likelihoodContractHash,likelihood.contractHash)
    error('SHT:F34IO:Lineage','方法C/D与当前似然合同不一致。');
end
tables=local_build_tables(prepared,likelihood,methodD,methodC,prediction);
verification=tables.Verification;
if any(verification.blocking & ~verification.passed)
    failed=strjoin(cellstr(verification.check_id( ...
        verification.blocking & ~verification.passed)),', ');
    error('SHT:F34IO:BlockingVerification','正式交付阻断项未通过：%s。',failed);
end

fileName=prepared.paths.deliveryFile;
folder=fileparts(fileName);
if ~isfolder(folder),mkdir(folder);end
temporary=[tempname(folder),'.xlsx'];
cleanup=onCleanup(@()local_delete_if_exists(temporary)); %#ok<NASGU>
    % 正式工作簿不携带求解轨迹、提议密度、祖先编号及测试图表。
    % 这些调试材料仍在内部MAT和report_outputs，不能成为下游运行依赖。
    order={'Manifest','EvidenceLineage','ParameterDictionary','ParameterSummary','PosteriorSamples', ...
    'ModelState','RuntimeAssets','PosteriorCovariance','ConditionalShapeMean', ...
    'ConditionalShapeCovariance','ConditionalShapeCovBySample', ...
    'ShapeBasis','ShapeNodeMap', ...
    'ShapeCoordinateMoments','ShapeFullProcessQ','ShapeMetadata', ...
    'QAssumptions'};
if prepared.options.modelMode~=0
    order=setdiff(order,{'ModelState','RuntimeAssets'},'stable');
end
if isfield(prepared.prior,'nodePrior'),order{end+1}='NodeNextFlightQ';end
if isfield(tables,'BusinessIdentity'),order{end+1}='BusinessIdentity';end
if isfield(tables,'FixedTransient'),order{end+1}='FixedTransient';end
if isfield(methodC,'physicalSupport')
    order=[order,{'ConditionalSupport','ConditionalGaussianMean','ConditionalGaussianCovBySample'}];
end
% C正式消费者仅需C的样本/条件分布；D是数值提议和对照，不作为附带后验交付。
for i=1:numel(order)
    value=tables.(order{i});
    if ~istable(value)||width(value)==0||height(value)==0
        value=table("not_applicable",'VariableNames',{'status'});
    end
    writetable(value,temporary,'Sheet',order{i});
end
local_verify_expected(temporary,tables);
if isfile(fileName)
    % 冻结载荷相同则保持正式文件字节和哈希。仅忽略生成时刻，不忽略
    % 样本、权重、条件协方差、模型或来源；禁止同标签发布另一套结果。
    for j=1:numel(order)
        actual=readtable(fileName,'Sheet',order{j},'PreserveVariableNames',true);
        expected=tables.(order{j});
        assert(local_same_payload(actual,expected),'SHT:F34IO:ExistingDelivery', ...
            '已有Excel的%s载荷不同，请使用新runTag，不覆盖正式结果。',order{j});
    end
    delete(temporary);
else
    [ok,message]=movefile(temporary,fileName);
    if ~ok,error('SHT:F34IO:Publish','Excel原子发布失败：%s。',message);end
end
fileHash=sht_f33_model_adapt_v2('fileHash',fileName);
sidecar=[fileName,'.sha256'];
if ~isfile(sidecar)
fid=fopen(sidecar,'w','n','UTF-8');
if fid<0,error('SHT:F34IO:Sidecar','无法写入SHA-256旁车。');end
fileCleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
[~,leaf,extension]=fileparts(fileName);
fprintf(fid,'%s  %s%s\n',fileHash,leaf,extension);
else
    assert(contains(fileread(sidecar),fileHash),'SHT:F34IO:SidecarChanged','原SHA旁车不匹配。');
end
delivery=struct('schemaVersion','SHT_F34_R1_DELIVERY_V1', ...
    'workbookFile',fileName,'workbookSha256',fileHash, ...
    'posteriorSampleCount',methodC.particleCount,'posteriorEss',methodC.ess, ...
    'formalInterface','excel','truthExported',false, ...
    'status','FINITE_SMC_CONDITIONAL_ENGINEERING_Q', ...
    'processCovarianceCalibrated',false, ...
    'processCovarianceStatus',prepared.contract.processCovarianceStatus);
end

function yes=local_same_payload(actual,expected)
yes=height(actual)==height(expected)&&isequal(actual.Properties.VariableNames,expected.Properties.VariableNames);
if ~yes,return;end
for j=1:width(expected)
    name=expected.Properties.VariableNames{j};if strcmp(name,'completed_at'),continue;end
    a=actual.(name);b=expected.(name);
    if isnumeric(b)||islogical(b)
        if ~(isnumeric(a)||islogical(a)),yes=false;return;end
        yes=isequal(size(a),size(b))&&all((isnan(a(:))&isnan(b(:)))|abs(double(a(:))-double(b(:)))<1e-12);
    else
        yes=isequaln(string(a),string(b));
    end
    if ~yes,return;end
end
end

function tables=local_build_tables(prepared,likelihood,methodD,methodC,prediction)
prior=prepared.prior;parameter=prior.parameterTable;
n=methodC.particleCount;d=height(parameter);rankValue=prior.shape.retainedRank;
weights=methodC.weights(:)/sum(methodC.weights);

tables=struct();
if isfield(prior,'nodePrior')
    tables.NodeNextFlightQ=local_matrix_table(prior.nodePrior.jointNextFlightCovariance, ...
        string((1:size(prior.nodePrior.jointNextFlightCovariance,1)).'),'q');
end
if prepared.options.modelMode==0
    deployment=sht_f34_deployment('tables',prepared);
    tables.ModelState=deployment.ModelState;
    tables.RuntimeAssets=deployment.RuntimeAssets;
    if isfield(prepared.context.priorSchedule,'fixedTransient')
        f=prepared.context.priorSchedule.fixedTransient;
        tables.FixedTransient=table(f.cIndex,string(f.name(:)),f.value, ...
            repmat("1",13,1),repmat(string(f.sourceSha256),13,1), ...
            repmat("fixed_not_sampled",13,1), ...
            'VariableNames',{'c_index','parameter','value','unit','source_sha256','treatment'});
    end
end
tables.MethodDCovariance=array2table(methodD.covariance);
tables.MethodDShapeMean=table(methodD.conditionalShapeMean(:),'VariableNames',{'mean'});
tables.MethodDShapeCovariance=array2table(methodD.conditionalShapeCovariance);
evidenceLineage=local_evidence_lineage(prepared);
tables.Manifest=table("SHT_F34_R1_DELIVERY_V1","3.4","R1", ...
    string(prepared.options.engineId),string(prepared.options.sortieId), ...
    string(prepared.options.parentPosteriorId),string(methodC.methodId), ...
    string(datestr(now,31)), ...
    "FINITE_SMC_CONDITIONAL_ENGINEERING_Q", ...
    string(prepared.contract.trainingEvidenceSha256), ...
    string(prepared.contract.sourcePosteriorSha256),d,n,methodC.ess, ...
    methodC.finalBeta,methodC.uniqueParticleCount,methodC.uniqueAncestorCount, ...
    methodC.totalMoveAcceptance, ...
    methodC.independentRepeatStability.repeatSeed, ...
    methodC.independentRepeatStability.repeatParticleCount, ...
    methodC.independentRepeatStability.stable, ...
    methodC.independentRepeatStability.maximumMeanDifferenceOverPosteriorStd, ...
    methodC.independentRepeatStability.minimumIntervalOverlapFraction, ...
    false,false,false,height(evidenceLineage), ...
    string(prepared.contract.processCovarianceStatus), ...
    'VariableNames',{'schema_version','stage_id','route_id','engine_id', ...
    'sortie_id','parent_posterior_id','posterior_method','completed_at', ...
    'formal_status','training_evidence_sha256','source_posterior_sha256', ...
    'parameter_count','sample_count','posterior_ess','final_beta', ...
    'unique_particle_count','unique_ancestor_count','move_acceptance', ...
    'repeat_seed','repeat_particle_count','repeat_stable', ...
    'repeat_maximum_mean_difference_over_posterior_std', ...
    'repeat_minimum_interval_overlap_fraction', ...
    'test_data_used_for_inference','truth_data_used_for_inference', ...
    'hidden_truth_exported','evidence_lineage_count','process_covariance_status'});

tables.EvidenceLineage=evidenceLineage;
if isfield(prepared.options,'businessIdentity')
    binding=prepared.options.businessIdentity;
    tables.BusinessIdentity=sht_f3_business_identity('table',binding);
    tables.Manifest.parent_model_id=string(binding.parentModelId);
    tables.Manifest.current_model_id=string(binding.currentModelId);
    tables.Manifest.business_identity_purpose=string(binding.purpose);
end
tables.Manifest.route_id=string(prepared.context.options.modelRoute);
tables.Manifest.model_mode=prepared.options.modelMode;
if isfield(prior,'nodePrior')
    tables.Manifest.parameterization="independent_nodes";
    tables.Manifest.next_Q_coordinates="explicit_parameter_then_conditional_node";
    tables.Manifest.next_transition="joint_gaussian_mixture_conditioned_on_explicit_box";
    tables.Manifest.normalized_model_evidence_available=false;
end
if strcmp(prepared.context.options.modelRoute,'transient_instant')
    tables.Manifest.route_id="R2";
end
tables.Manifest.method_d_converged=methodD.converged;
tables.Manifest.method_d_gradient=methodD.finalProjectedGradientNorm;
tables.Manifest.method_d_curvature=string(methodD.curvatureApproximation);
tables.Manifest.shape_retained_fraction=prior.shape.retainedSecondMomentFraction;
tables.Manifest.shape_target_fraction=prepared.options.nuisanceRetainedVariance;
tables.Manifest.shape_target_met=prior.shape.retainedSecondMomentFraction>=prepared.options.nuisanceRetainedVariance;
tables.Manifest.data_method=string(prepared.options.dataMethod);
tables.Manifest.distinct_support_weight_ess=methodC.distinctSupportWeightESS;
tables.Manifest.ancestor_mass_ess=methodC.ancestorMassESS;
tables.Manifest.statistical_calibration_confirmed=false;
tables.Manifest.conditional_nuisance_approximation="low_rank_conditional_moment_gaussian";
if isfield(methodC,'physicalSupport')
    tables.Manifest.conditional_nuisance_approximation="physically_bounded_gaussian_affine_response_QMC";
    tables.Manifest.conditional_moments_are_gaussian_parameters=false;
    tables.Manifest.conditional_sampling_contract="ConditionalSupport_and_ConditionalGaussianMean_and_ConditionalGaussianCovBySample";
    tables.Manifest.next_transition="bounded_conditional_parent_plus_joint_Q_conditioned_on_joint_support";
end
tables.ParameterDictionary=parameter;
tables.ParameterSummary=prior.summary;
tables.ParameterSummary.method_d_map=methodD.map;
tables.ParameterSummary.method_d_std=methodD.standardDeviation;
tables.ParameterSummary.method_d_q025=methodD.interval95(:,1);
tables.ParameterSummary.method_d_q975=methodD.interval95(:,2);
tables.ParameterSummary.method_c_mean=methodC.mean;
tables.ParameterSummary.method_c_std=sqrt(max(diag(methodC.covariance),0));
tables.ParameterSummary.method_c_q025=methodC.interval95(:,1);
tables.ParameterSummary.method_c_q975=methodC.interval95(:,2);
sampleId=(1:n).';
sampleTable=table(sampleId,weights,methodC.logLikelihood(:), ...
    methodC.logPrior(:),methodC.logProposal(:), ...
    methodC.proposalLabel(:),methodC.ancestor(:), ...
    'VariableNames',{'sample_id','weight','log_likelihood','log_prior', ...
    'log_proposal','proposal_source','ancestor'});
sampleColumn=strings(d,1);
for i=1:d
    sampleColumn(i)="theta_"+string(parameter.parameter_id(i));
    sampleColumn(i)=string(matlab.lang.makeValidName(char(sampleColumn(i))));
    sampleTable.(char(sampleColumn(i)))=methodC.samples(i,:).';
end
tables.ParameterSummary.sample_column=sampleColumn;
tables.PosteriorSamples=sampleTable;
tables.PosteriorSamples=sampleTable(:,[{'sample_id','weight'},cellstr(sampleColumn).']);
tables.PosteriorCovariance=local_matrix_table(methodC.covariance, ...
    string(parameter.parameter_id),'p');
sigma=sqrt(max(diag(methodC.covariance),eps));
correlation=methodC.covariance./max(sigma*sigma.',eps);
tables.PosteriorCorrelation=local_matrix_table(correlation, ...
    string(parameter.parameter_id),'p');

shapeId=(1:rankValue).';
shapeMean=table(sampleId,'VariableNames',{'sample_id'});
for i=1:rankValue
    shapeMean.(sprintf('z%03d',i))=methodC.conditionalShapeMean(i,:).';
end
tables.ConditionalShapeMean=shapeMean;
tables.ConditionalShapeCovariance=local_matrix_table( ...
    methodC.conditionalShapeCovarianceMean,string(shapeId),'z');
tables.ConditionalShapeCovBySample=local_covariance_by_sample_table( ...
    methodC.conditionalShapeCovariance,sampleId);
if isfield(methodC,'physicalSupport')
    b=methodC.physicalSupport;
    tables.ConditionalSupport=table(b.index,b.lower,b.upper,b.name,b.c_index, ...
        repmat(methodC.conditionalQuadratureCount,numel(b.index),1), ...
        repmat(methodC.conditionalQuadratureSeed,numel(b.index),1), ...
        'VariableNames',{'index','lower','upper','name','c_index','quadrature_count','quadrature_seed'});
    raw=table(sampleId,'VariableNames',{'sample_id'});
    for i=1:rankValue,raw.(sprintf('z%03d',i))=methodC.conditionalGaussianMean(i,:).';end
    tables.ConditionalGaussianMean=raw;
    tables.ConditionalGaussianCovBySample=local_covariance_by_sample_table( ...
        methodC.conditionalGaussianCovariance,sampleId);
end
tables.ShapeBasis=local_matrix_table(prior.shape.basis, ...
    string((1:size(prior.shape.basis,1)).'),'z');
tables.ShapeBasis.Properties.VariableNames{1}='node_row';
tables.ShapeNodeMap=prior.shape.nodeMap;
tables.ShapeCoordinateMoments=table(shapeId, ...
    prior.shape.coordinateSecondMoment(:), ...
    'VariableNames',{'shape_coordinate','second_moment'});
tables.ShapeFullProcessQ=local_matrix_table( ...
    prior.shape.fullProcessCovariance, ...
    string((1:size(prior.shape.fullProcessCovariance,1)).'),'q');
tables.ShapeMetadata=table(rankValue,prior.shape.healthNodeCount, ...
    prior.shape.fuelNodeCount,true, ...
    prior.shape.retainedSecondMomentFraction, ...
    'VariableNames',{'retained_rank','health_node_count','fuel_node_count', ...
    'sample_specific_conditional_covariance', ...
    'retained_second_moment_fraction'});
tables.QAssumptions=local_q_table(prepared);
tables.QSensitivity=methodC.qSensitivity;
tables.LikelihoodAudit=local_likelihood_audit(likelihood);
tables.MethodDTrace=struct2table(methodD.trace);
tables.MethodDNonlinearity=methodD.nonlinearity;
tables.MethodCStages=struct2table(methodC.stage);
tables.MethodCRepeatStability=methodC.independentRepeatStability.table;
tables.MarginalModes=methodC.marginalModeDiagnostic;
tables.CurveSummary=methodC.curveSummary;
if isempty(prediction)
    tables.PredictionSummary=table();tables.PredictionDetail=table();
    tables.PredictionValidity=table();
    tables.EngineeringSelfSensitivity=table();
    tables.EngineeringCompensation=table();
else
    tables.PredictionSummary=prediction.summary;
    tables.PredictionDetail=prediction.detail;
    tables.PredictionValidity=local_prediction_validity_table(prediction);
    if isfield(prediction,'engineeringCompensation')
        tables.EngineeringSelfSensitivity= ...
            prediction.engineeringCompensation.singleParameter;
        tables.EngineeringCompensation= ...
            prediction.engineeringCompensation.pairDiagnostic;
    else
        tables.EngineeringSelfSensitivity=table();
        tables.EngineeringCompensation=table();
    end
end
tables.Verification=local_verification(prepared,methodD,methodC,prediction);
end

function tableValue=local_prediction_validity_table(prediction)
% 独立任务物理解筛选是预测结果的适用条件，必须随正式交付显式保存。
if ~isfield(prediction,'methodC')|| ...
        ~isfield(prediction.methodC,'physicalValidityAudit')
    tableValue=table();
    return;
end
audit=prediction.methodC.physicalValidityAudit;
predictionMode=["fixed_transfer";"next_sortie"];
candidateCount=[audit.fixedCandidateCount;audit.nextCandidateCount];
jointlyValidCount=[audit.fixedValidCount;audit.nextValidCount];
invalidExplicitCount=[audit.fixedInvalidExplicitCount; ...
    audit.nextInvalidExplicitCount];
invalidPhysicalCount=[audit.fixedInvalidPhysicalCount; ...
    audit.nextInvalidPhysicalCount];
jointlyValidFraction=jointlyValidCount./candidateCount;
conditioning=repmat(string(audit.conditioning),2,1);
tableValue=table(predictionMode,candidateCount,jointlyValidCount, ...
    jointlyValidFraction,invalidExplicitCount,invalidPhysicalCount,conditioning, ...
    'VariableNames',{'prediction_mode','candidate_count', ...
    'jointly_valid_count','jointly_valid_fraction', ...
    'invalid_explicit_count','invalid_physical_count','conditioning'});
end

function tableValue=local_q_table(prepared)
o=prepared.options;
parameterId=string(prepared.prior.parameterTable.parameter_id);
benchSigma=[o.benchToFlightHealthSigma(:);o.firstFlightKdistSigma; ...
    o.firstFlightFuelSigma_kgps];
flightSigma=[o.flightToFlightHealthSigma(:);o.flightToFlightKdistSigma; ...
    o.flightToFlightFuelSigma_kgps];
if isfield(prepared.prior,'nodePrior')
    benchSigma=sqrt(diag(prepared.prior.componentCovariance));
    d=height(prepared.prior.parameterTable);
    flightSigma=sqrt(diag(prepared.prior.nodePrior.jointNextFlightCovariance(1:d,1:d)));
end
tableValue=table(parameterId,benchSigma,flightSigma, ...
    repmat(false,numel(parameterId),1), ...
    repmat("engineering_judgement_pending_longitudinal_study", ...
    numel(parameterId),1),'VariableNames',{'parameter_id', ...
    'bench_to_flight_sigma','flight_to_flight_sigma','calibrated', ...
    'basis'});
tableValue.bench_shape_sigma=repmat(o.benchToFlightShapeSigma,numel(parameterId),1);
tableValue.flight_shape_sigma=repmat(o.flightToFlightShapeSigma,numel(parameterId),1);
tableValue.future_required_study=repmat( ...
    "same_engine_multi_sortie_longitudinal_calibration_and_coverage_validation", ...
    numel(parameterId),1);
end

function tableValue=local_evidence_lineage(prepared)
required={'evidence_order','stage_id','engine_id','sortie_id', ...
    'evidence_sha256','evidence_role'};
if isfield(prepared.prior,'evidenceLineage')&&istable(prepared.prior.evidenceLineage)
    tableValue=prepared.prior.evidenceLineage;
else
    tableValue=table(zeros(0,1),strings(0,1),strings(0,1),strings(0,1), ...
        strings(0,1),strings(0,1),'VariableNames',required);
end
if ~all(ismember(required,tableValue.Properties.VariableNames))
    error('SHT:F34IO:EvidenceLineage','继承证据血缘字段不完整。');
end
tableValue=tableValue(:,required);
tableValue.evidence_order=double(tableValue.evidence_order);
textField={'stage_id','engine_id','sortie_id','evidence_sha256','evidence_role'};
for i=1:numel(textField)
    tableValue.(textField{i})=string(tableValue.(textField{i}));
end
if any(strlength(tableValue.evidence_sha256)==0)|| ...
        numel(unique(lower(tableValue.evidence_sha256)))~=height(tableValue)
    error('SHT:F34IO:EvidenceLineage', ...
        '继承证据血缘包含空哈希或重复哈希，不能继续递推。');
end
currentHash=string(prepared.contract.trainingEvidenceSha256);
if any(strcmpi(string(tableValue.evidence_sha256),currentHash))
    error('SHT:F34IO:DuplicateEvidence','当前训练证据已存在于祖先血缘中。');
end
current=table(height(tableValue)+1,"3.4",string(prepared.options.engineId), ...
    string(prepared.options.sortieId),currentHash,"likelihood_evidence", ...
    'VariableNames',required);
tableValue=[tableValue;current];
end

function tableValue=local_likelihood_audit(likelihood)
channel=string(likelihood.observationChannels(:));
knownChannel=["Np";"Ng";"Pt3_eq";"Tt45";"dNp_dt";"dNg_dt"];
knownUnit=["rpm";"rpm";"Pa";"K";"rpm/s";"rpm/s"];
unit=strings(size(channel));
for i=1:numel(channel)
    row=find(knownChannel==channel(i),1);
    if isempty(row),unit(i)="unknown";else,unit(i)=knownUnit(row);end
end
modelDiscrepancyStd=likelihood.modelDiscrepancyStd(:);
tableValue=table(channel,unit,modelDiscrepancyStd, ...
    'VariableNames',{'channel','unit','model_discrepancy_std'});
tableValue.observation_count=repmat(numel(likelihood.observation),height(tableValue),1);
tableValue.shape_rank=repmat(size(likelihood.shapeSensitivity,2),height(tableValue),1);
end

function verification=local_verification(prepared,methodD,methodC,prediction)
checkId=["method_c_reached_beta_one";"weights_finite_normalized"; ...
    "samples_within_bounds";"conditional_shape_complete"; ...
    "test_not_used_for_inference";"truth_not_used_for_inference"; ...
    "engineering_q_explicitly_labelled";"independent_seed_repeat_completed"; ...
    "independent_seed_stability";"particle_diversity_at_least_half"; ...
    "method_d_converged"; ...
    "prediction_is_post_inference"];
lower=prepared.prior.lowerBound(:);upper=prepared.prior.upperBound(:);
passed=[abs(methodC.finalBeta-1)<=1e-10; ...
    all(isfinite(methodC.weights))&&abs(sum(methodC.weights)-1)<=1e-10; ...
    all(methodC.samples>=lower-1e-12 & methodC.samples<=upper+1e-12,'all'); ...
    size(methodC.conditionalShapeMean,2)==methodC.particleCount; ...
    ~methodC.testDataUsed&&~prepared.contract.testDataAccessed; ...
    ~methodC.truthDataUsed&&~prepared.contract.truthDataAccessed; ...
    ~prepared.contract.processCovarianceCalibrated&& ...
    contains(string(prepared.contract.processCovarianceStatus),'FUTURE_LONGITUDINAL_STUDY'); ...
    isfield(methodC,'independentRepeatStability')&& ...
    methodC.independentRepeatStability.repeatSeed~=methodC.seed; ...
    methodC.independentRepeatStability.stable; ...
    methodC.uniqueParticleFraction>=0.5; ...
    methodD.converged; ...
    isempty(prediction)||(~prediction.inferenceTestDataUsed&&prediction.predictionTestDataUsed)];
blocking=[true;true;true;true;true;true;true;true;false;false;false;false];
detail=[string(sprintf('beta=%.17g',methodC.finalBeta)); ...
    string(sprintf('sumWeight=%.17g',sum(methodC.weights))); ...
    "all samples checked";string(sprintf('%d x %d',size(methodC.conditionalShapeMean))); ...
    string(methodC.testDataUsed);string(methodC.truthDataUsed); ...
    string(prepared.contract.processCovarianceStatus); ...
    string(sprintf('primary=%d, repeat=%d',methodC.seed, ...
        methodC.independentRepeatStability.repeatSeed)); ...
    string(methodC.independentRepeatStability.qualityLevel); ...
    string(sprintf('%d/%d',methodC.uniqueParticleCount,methodC.particleCount)); ...
    string(methodD.stopReason);local_prediction_detail_text(prediction)];
verification=table(checkId,passed,blocking,detail, ...
    'VariableNames',{'check_id','passed','blocking','detail'});
end

function value=local_prediction_detail_text(prediction)
if isempty(prediction),value="prediction_not_run"; ...
else,value="independent_validation_read_after_posterior_freeze";end
end

function tableValue=local_matrix_table(matrix,rowLabel,prefix)
column=arrayfun(@(i)sprintf('%s%03d',prefix,i),1:size(matrix,2), ...
    'UniformOutput',false);
tableValue=array2table(matrix,'VariableNames',column);
tableValue=addvars(tableValue,rowLabel(:),'Before',1,'NewVariableNames','row_id');
end

function tableValue=local_covariance_by_sample_table(covariance,sampleId)
rankValue=size(covariance,1);
if size(covariance,2)~=rankValue||size(covariance,3)~=numel(sampleId)
    error('SHT:F34IO:ConditionalCovariance', ...
        '逐样本条件形状协方差维数不一致。');
end
tableValue=table(sampleId(:),'VariableNames',{'sample_id'});
for i=1:rankValue
    for j=1:i
        name=sprintf('c%03d_%03d',i,j);
        tableValue.(name)=reshape(covariance(i,j,:),[],1);
    end
end
end

function local_validate_result(prepared,methodD,methodC)
if ~strcmp(methodC.schemaVersion,'SHT_F34_METHOD_C_V1')|| ...
        ~strcmp(methodD.schemaVersion,'SHT_F34_METHOD_D_V1')
    error('SHT:F34IO:Schema','方法C/D结果版本不兼容。');
end
if methodC.particleCount~=size(methodC.samples,2)|| ...
        size(methodC.samples,1)~=height(prepared.prior.parameterTable)
    error('SHT:F34IO:Dimension','方法C样本维数不符合R1合同。');
end
if ~isfield(methodC,'implementationSha256')|| ...
        ~strcmp(methodC.implementationSha256,sht_f33_model_adapt_v2( ...
        'fileHash',which('sht_f34_method_c')))|| ...
        ~isfield(methodD,'implementationSha256')|| ...
        ~strcmp(methodD.implementationSha256,sht_f33_model_adapt_v2( ...
        'fileHash',which('sht_f34_method_d')))
    error('SHT:F34IO:ImplementationLineage', ...
        '方法C/D结果与当前程序版本不一致，必须重新运行。');
end
requiredRepeat={'repeatSeed','repeatParticleCount','stable', ...
    'maximumMeanDifferenceOverPosteriorStd', ...
    'minimumIntervalOverlapFraction','table','qualityLevel'};
if ~isfield(methodC,'independentRepeatStability')|| ...
        ~all(isfield(methodC.independentRepeatStability,requiredRepeat))
    error('SHT:F34IO:IndependentRepeat', ...
        '正式交付前必须完成方法C独立随机种子复算。');
end
if ~isfield(methodC,'curveSummary')||~istable(methodC.curveSummary)|| ...
        isempty(methodC.curveSummary)
    error('SHT:F34IO:CurveSummary','正式交付前必须恢复实际曲线节点区间。');
end
if ~isfield(methodC,'qSensitivity')||~istable(methodC.qSensitivity)|| ...
        isempty(methodC.qSensitivity)
    error('SHT:F34IO:QSensitivity', ...
        '正式交付前必须完成0.5/1/2倍工程Q敏感性计算。');
end
end

function local_verify_expected(fileName,tables)
    required={'Manifest','EvidenceLineage','ParameterSummary','PosteriorSamples', ...
    'ConditionalShapeMean','ConditionalShapeCovBySample', ...
    'ShapeBasis','ShapeNodeMap','ModelState','RuntimeAssets', ...
    'ConditionalSupport','ConditionalGaussianMean','ConditionalGaussianCovBySample','FixedTransient'};
required=required(isfield(tables,required));
for i=1:numel(required)
    actual=readtable(fileName,'Sheet',required{i},'PreserveVariableNames',true);
    expected=tables.(required{i});
    if height(actual)~=height(expected)||width(actual)~=width(expected)
        error('SHT:F34IO:Readback','%s工作表写后回读尺寸不一致。',required{i});
    end
end
sample=readtable(fileName,'Sheet','PosteriorSamples','PreserveVariableNames',true);
if abs(sum(sample.weight)-1)>1e-10
    error('SHT:F34IO:ReadbackWeight','Excel回读后验样本权重未归一化。');
end
end

function verification=local_verify(fileName)
if ~isfile(fileName),error('SHT:F34IO:Missing','Excel交付物不存在。');end
    manifest=readtable(fileName,'Sheet','Manifest','PreserveVariableNames',true);
sample=readtable(fileName,'Sheet','PosteriorSamples','PreserveVariableNames',true);
checks=[height(manifest)==1;contains(string(manifest.formal_status(1)), ...
    'CONDITIONAL_ENGINEERING_Q');abs(sum(sample.weight)-1)<=1e-10; ...
    ~logical(manifest.hidden_truth_exported(1))];
verification=table(["manifest_single_row";"q_scope_labelled"; ...
    "weight_normalized";"truth_not_exported"],checks, ...
    'VariableNames',{'check_id','passed'});
end

function posterior=local_read_posterior(fileName)
if ~isfile(fileName),error('SHT:F34IO:PreviousMissing','上一架次后验Excel不存在。');end
manifest=readtable(fileName,'Sheet','Manifest','PreserveVariableNames',true);
summary=readtable(fileName,'Sheet','ParameterSummary','PreserveVariableNames',true);
samples=readtable(fileName,'Sheet','PosteriorSamples','PreserveVariableNames',true);
evidenceLineage=readtable(fileName,'Sheet','EvidenceLineage', ...
    'PreserveVariableNames',true);
requiredEvidence={'evidence_order','stage_id','engine_id','sortie_id', ...
    'evidence_sha256','evidence_role'};
if ~all(ismember(requiredEvidence,evidenceLineage.Properties.VariableNames))
    error('SHT:F34IO:PreviousEvidence', ...
        '上一架次Excel缺少完整EvidenceLineage字段。');
end
evidenceLineage=evidenceLineage(:,requiredEvidence);
evidenceLineage.evidence_order=double(evidenceLineage.evidence_order);
for i=2:numel(requiredEvidence)
    evidenceLineage.(requiredEvidence{i})=string( ...
        evidenceLineage.(requiredEvidence{i}));
end
if any(strlength(evidenceLineage.evidence_sha256)==0)|| ...
        numel(unique(lower(evidenceLineage.evidence_sha256)))~=height(evidenceLineage)
    error('SHT:F34IO:PreviousEvidence', ...
        '上一架次EvidenceLineage包含空哈希或重复哈希。');
end
if height(manifest)~=1|| ...
        ~contains(string(manifest.formal_status(1)),'CONDITIONAL_ENGINEERING_Q')
    error('SHT:F34IO:PreviousManifest', ...
        '上一架次Excel不是可识别的3.4正式交付。');
end
if abs(sum(double(samples.weight))-1)>1e-10|| ...
        any(~isfinite(double(samples.weight)))||any(double(samples.weight)<0)
    error('SHT:F34IO:PreviousWeights','上一架次后验权重无效。');
end
dimension=height(summary);theta=zeros(dimension,height(samples));
for i=1:dimension
    column=char(string(summary.sample_column(i)));
    if ~ismember(column,samples.Properties.VariableNames)
        error('SHT:F34IO:PreviousColumn','上一架次Excel缺少%s。',column);
    end
    theta(i,:)=double(samples.(column)).';
end
shapeMean=readtable(fileName,'Sheet','ConditionalShapeMean', ...
    'PreserveVariableNames',true);
shapeCov=local_read_matrix(fileName,'ConditionalShapeCovariance');
shapeCovBySample=readtable(fileName,'Sheet','ConditionalShapeCovBySample', ...
    'PreserveVariableNames',true);
basis=local_read_matrix(fileName,'ShapeBasis');
nodeMap=readtable(fileName,'Sheet','ShapeNodeMap','PreserveVariableNames',true);
if ismember('kind',nodeMap.Properties.VariableNames)
    nodeMap.kind=string(nodeMap.kind);
end
moment=readtable(fileName,'Sheet','ShapeCoordinateMoments', ...
    'PreserveVariableNames',true);
fullQ=local_read_matrix(fileName,'ShapeFullProcessQ');
metadata=readtable(fileName,'Sheet','ShapeMetadata','PreserveVariableNames',true);
rankValue=double(metadata.retained_rank(1));z=zeros(rankValue,height(samples));
for i=1:rankValue,z(i,:)=double(shapeMean.(sprintf('z%03d',i))).';end
componentCovariance=zeros(rankValue,rankValue,height(samples));
for i=1:rankValue
    for j=1:i
        name=sprintf('c%03d_%03d',i,j);
        if ~ismember(name,shapeCovBySample.Properties.VariableNames)
            error('SHT:F34IO:PreviousShapeCovariance', ...
                '上一架次Excel缺少逐样本条件协方差列%s。',name);
        end
        value=double(shapeCovBySample.(name));
        componentCovariance(i,j,:)=reshape(value,1,1,[]);
        componentCovariance(j,i,:)=reshape(value,1,1,[]);
    end
end
priorShape=struct('basis',basis,'nodeMap',nodeMap, ...
    'retainedRank',rankValue,'healthNodeCount',double(metadata.health_node_count(1)), ...
    'retainedSecondMomentFraction', ...
    double(metadata.retained_second_moment_fraction(1)), ...
    'coordinateSecondMoment',double(moment.second_moment(:)), ...
    'fullProcessCovariance',fullQ,'processCovarianceZ',shapeCov, ...
    'componentCovarianceZ',componentCovariance, ...
    'fuelNodeCount',double(metadata.fuel_node_count(1)), ...
    'zSamples',z.');
posterior=struct('schemaVersion','SHT_F34_METHOD_C_V1', ...
    'samples',theta,'weights',double(samples.weight(:)), ...
    'conditionalShapeMean',z, ...
    'conditionalShapeCovariance',componentCovariance, ...
    'conditionalShapeCovarianceMean',shapeCov,'priorShape',priorShape, ...
    'evidenceLineage',evidenceLineage, ...
    'sourceManifest',manifest,'sourceWorkbook',fileName, ...
    'sourceWorkbookSha256',sht_f33_model_adapt_v2('fileHash',fileName));
posterior.parameterDictionary=readtable(fileName,'Sheet','ParameterDictionary');
[~,sheets]=xlsfinfo(fileName);
if ismember('BusinessIdentity',sheets)
    posterior.businessIdentity=readtable(fileName,'Sheet','BusinessIdentity','PreserveVariableNames',true);
end
if ismember('ConditionalSupport',sheets)
    b=readtable(fileName,'Sheet','ConditionalSupport');
    posterior.physicalSupport=struct('index',b.index,'lower',b.lower,'upper',b.upper, ...
        'name',string(b.name),'c_index',b.c_index);
    posterior.conditionalQuadratureCount=b.quadrature_count(1);
    posterior.conditionalQuadratureSeed=b.quadrature_seed(1);
    t=readtable(fileName,'Sheet','ConditionalGaussianMean');raw=zeros(size(z));
    assert(isequal(double(t.sample_id),double(samples.sample_id)), ...
        '原始条件高斯均值与主样本编号顺序不一致。');
    for i=1:rankValue,raw(i,:)=t.(sprintf('z%03d',i)).';end
    posterior.conditionalGaussianMean=raw;
    t=readtable(fileName,'Sheet','ConditionalGaussianCovBySample');raw=componentCovariance;
    assert(isequal(double(t.sample_id),double(samples.sample_id)), ...
        '原始条件高斯协方差与主样本编号顺序不一致。');
    for i=1:rankValue
        for j=1:i
            name=sprintf('c%03d_%03d',i,j);
            value=reshape(t.(name),1,1,[]);raw(i,j,:)=value;raw(j,i,:)=value;
        end
    end
    posterior.conditionalGaussianCovariance=raw;
end
if ismember('parameterization',manifest.Properties.VariableNames)&& ...
        strcmp(string(manifest.parameterization(1)),"independent_nodes")
    posterior.jointNextFlightCovariance=local_read_matrix(fileName,'NodeNextFlightQ');
    q=posterior.jointNextFlightCovariance;
    assert(isequal(size(q),[dimension+rankValue,dimension+rankValue])&& ...
        max(abs(q-q.'),[],'all')<1e-12&&min(eig((q+q.')/2))>-1e-14, ...
        '节点联合跨架次协方差不合法。');
end
if ismember('model_mode',manifest.Properties.VariableNames)&&manifest.model_mode(1)==0
    model=readtable(fileName,'Sheet','ModelState');[~,order]=sort(model.chunk_id);
    posterior.modelState=jsondecode(char(join(string(model.json_text(order)),'')));
    posterior.runtimeAssets=readtable(fileName,'Sheet','RuntimeAssets');
end
assert(isequal(double(samples.sample_id),double(shapeMean.sample_id))&& ...
    isequal(double(samples.sample_id),double(shapeCovBySample.sample_id)), ...
    'SHT:F34IO:ConditionalOrder','条件均值/协方差与主样本编号顺序不一致。');
assert(all(isfinite(theta(:)))&&all(isfinite(z(:))), ...
    'SHT:F34IO:Finite','Excel参数和条件形状不能包含NaN或Inf。');
end

function matrix=local_read_matrix(fileName,sheet)
value=readtable(fileName,'Sheet',sheet,'PreserveVariableNames',true);
matrix=table2array(value(:,2:end));
matrix=double(matrix);
end

function local_delete_if_exists(fileName)
if isfile(fileName),delete(fileName);end
end
