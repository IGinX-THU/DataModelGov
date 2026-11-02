function varargout=sht_f34_prior(action,varargin)
%SHT_F34_PRIOR 3.4 R1联合先验、跨阶段传播和曲线残差映射。
%
% 本模块把正式上游后验转换为当前R1的9维显式参数分布，同时保留
% 2.4完整健康曲线中不能由单个幅值表达的形状残差。台架燃油偏置只做
% 边缘化，不作为飞行燃油偏置条件；首次飞行的K_dist_eq和Wf_bias使用
% 独立飞行工程先验。跨阶段/架次变化协方差目前是工程经验配置，尚未由
% 长期实测数据标定，调用方必须把这一限制写入交付物。

switch lower(char(action))
    case 'build'
        varargout{1}=local_build(varargin{:});
    case 'draw'
        varargout{1}=local_draw(varargin{:});
    case 'logpdf'
        [varargout{1:nargout}]=local_logpdf(varargin{:});
    case 'responsibilities'
        varargout{1}=local_responsibilities(varargin{:});
    case 'conditionalshape'
        [varargout{1:nargout}]=local_conditional_shape(varargin{:});
    case 'applyshape'
        varargout{1}=local_apply_shape(varargin{:});
    case 'moments'
        [varargout{1:nargout}]=local_moments(varargin{:});
    case 'transition'
        varargout{1}=local_transition(varargin{:});
    otherwise
        error('SHT:F34Prior:Action','未知先验动作：%s。',char(action));
end
end

function prior=local_build(context,options)
required={'sourceStage','sourceMethod','sourceWorkbook','transitionMode', ...
    'benchToFlightHealthSigma','flightToFlightHealthSigma', ...
    'benchToFlightShapeSigma','flightToFlightShapeSigma', ...
    'firstFlightKdistSigma','firstFlightFuelSigma_kgps', ...
    'firstFlightFuelShapeSigma_kgps', ...
    'flightToFlightFuelShapeSigma_kgps', ...
    'nuisanceRetainedVariance','nuisanceMaximumRank', ...
    'nuisanceFuelMaximumRank'};
local_require_fields(options,required,'options');
if strcmp(options.sourceStage,'previous_flight')
    assert(~strcmp(context.options.scheduleParameterization,'independent_nodes'), ...
        'SHT:F34Prior:NodePreviousFlight','节点D当前为台架到飞行测试；上一架次节点后验读取尚未实现，不得套用幅值映射。');
    prior=local_build_previous_flight(context,options);
    return;
end
if ~ismember(options.sourceStage,{'2p4','2p7'})
    error('SHT:F34Prior:SourceStage','sourceStage无效。');
end
if ~isfile(options.sourceWorkbook)
    error('SHT:F34Prior:SourceWorkbook','上游后验Excel不存在：%s。', ...
        options.sourceWorkbook);
end

if strcmp(options.sourceStage,'2p7')
    [manifest,summary,samples]=local_tc27_tables(options.sourceWorkbook);
else
    manifest=readtable(options.sourceWorkbook,'Sheet','Manifest');
    summary=readtable(options.sourceWorkbook,'Sheet','ParameterSummary');
    samples=readtable(options.sourceWorkbook,'Sheet','PosteriorSamples');
end
local_validate_upstream(manifest,summary,samples,options);

weights=double(samples.sampleWeight(:));
weights=local_normalize_weights(weights);
n=size(samples,1);
family=context.familyMap;
familyCount=numel(family);
explicitHealth=zeros(n,familyCount);
nodeMap=table();
residualHealth=zeros(n,0);
referenceHealth=zeros(0,1);
processShape=zeros(0,0);
reconstructionMaximum=0;

for j=1:familyCount
    if ~family(j).scheduled
        error('SHT:F34Prior:ConstantHealth', ...
            '当前R1不支持把常值h15混入七条健康曲线幅值。');
    end
    c=family(j).cIndex;
    entry=context.priorSchedule.healthEntries(family(j).entryIndex);
    row=find(double(summary.cIndex)==c & ...
        string(summary.groupKind)=="health_schedule");
    [~,order]=sort(double(summary.coordinate(row)));
    row=row(order);
    coordinate=double(summary.coordinate(row));
    entryNode=local_match_entry_nodes(coordinate,entry.xNodes,c);
    reference=entry.kNodes(:).';
    value=repmat(reference,n,1);
    value(:,entryNode)=local_sample_columns(samples,summary,row);
    deterministic=double(summary.deterministicEstimate(row)).';
    if max(abs(reference(entryNode)-deterministic))>5e-8 && ~options.allowReferenceRebase
        error('SHT:F34Prior:ReferenceMismatch', ...
            '3.3参考曲线与2.4确定性h%d节点最大差%.3e。', ...
            c,max(abs(reference(entryNode)-deterministic)));
    end
    delta=value-reference;
    basis=family(j).basis(:);
    denominator=basis.'*basis;
    if denominator<=eps
        error('SHT:F34Prior:EmptyBasis','h%d幅值基函数为空。',c);
    end
    amplitude=delta*basis/denominator;
    residual=delta-amplitude*basis.';
    explicitHealth(:,j)=amplitude;
    reconstructed=reference+amplitude*basis.'+residual;
    reconstructionMaximum=max(reconstructionMaximum, ...
        max(abs(reconstructed-value),[],'all'));

    first=size(residualHealth,2)+1;
    residualHealth=[residualHealth,residual]; %#ok<AGROW>
    referenceHealth=[referenceHealth;reference(:)]; %#ok<AGROW>
    count=numel(reference);
    nodeMap=[nodeMap;table(repmat("health",count,1),repmat(c,count,1), ...
        (1:count).',entry.xNodes(:),reference(:),repmat(j,count,1), ...
        'VariableNames',{'kind','c_index','node_index','coordinate', ...
        'reference_value','family_index'})]; %#ok<AGROW>

    shapeSigma=local_health_shape_sigma(options,j);
    correlation=local_node_correlation(entry.xNodes,0.35);
    projector=eye(count)-basis*basis.'/denominator;
    block=shapeSigma^2*(projector*correlation*projector.');
    if entry.pressureLoss && entry.xNodes(1)==0
        block(1,:)=0;block(:,1)=0;
    end
    processShape=local_block_diag_append(processShape,block);
    if first+count-1~=size(residualHealth,2)
        error('SHT:F34Prior:NodeAssembly','健康形状节点装配错误。');
    end
end

% 2.4中已经形成后验、但当前R1没有显式释放的健康量不能退化成确定值。
% h6、h14保留完整节点残差，h15保留常值残差；它们只进入条件干扰量。
selectedC=[family.cIndex];
scheduledKind=string(summary.groupKind)=="health_schedule";
upstreamScheduledC=unique(double(summary.cIndex(scheduledKind))).';
unselectedC=setdiff(upstreamScheduledC,selectedC,'stable');
for c=unselectedC
    entryIndex=find([context.priorSchedule.healthEntries.cIndex]==c,1);
    if isempty(entryIndex)
        error('SHT:F34Prior:UnselectedEntry','当前参考曲线缺少上游h%d。',c);
    end
    entry=context.priorSchedule.healthEntries(entryIndex);
    row=find(double(summary.cIndex)==c & scheduledKind);
    [~,order]=sort(double(summary.coordinate(row)));row=row(order);
    coordinate=double(summary.coordinate(row));
    entryNode=local_match_entry_nodes(coordinate,entry.xNodes,c);
    reference=entry.kNodes(:).';
    value=repmat(reference,n,1);
    value(:,entryNode)=local_sample_columns(samples,summary,row);
    deterministic=double(summary.deterministicEstimate(row)).';
    if max(abs(reference(entryNode)-deterministic))>5e-8 && ~options.allowReferenceRebase
        error('SHT:F34Prior:UnselectedReference', ...
            '当前参考曲线与上游h%d确定性节点不一致。',c);
    end
    residual=value-reference;
    residualHealth=[residualHealth,residual]; %#ok<AGROW>
    referenceHealth=[referenceHealth;reference(:)]; %#ok<AGROW>
    count=numel(reference);
    nodeMap=[nodeMap;table(repmat("health",count,1),repmat(c,count,1), ...
        (1:count).',entry.xNodes(:),reference(:),zeros(count,1), ...
        'VariableNames',{'kind','c_index','node_index','coordinate', ...
        'reference_value','family_index'})]; %#ok<AGROW>
    sigmaUnselected=local_unselected_health_sigma(options);
    block=sigmaUnselected^2*local_node_correlation(entry.xNodes,0.35);
    if entry.pressureLoss && entry.xNodes(1)==0
        block(1,:)=0;block(:,1)=0;
    end
    processShape=local_block_diag_append(processShape,block);
end

constantRow=find(string(summary.groupKind)=="constant");
for row=constantRow(:).'
    c=double(summary.cIndex(row));
    if c~=15
        error('SHT:F34Prior:UnsupportedConstant','暂不支持上游常值h%d。',c);
    end
    variable=['theta_',char(string(summary.name(row)))];
    if ~ismember(variable,samples.Properties.VariableNames)
        error('SHT:F34Prior:SampleColumn','上游样本缺少%s。',variable);
    end
    reference=context.priorSchedule.h15;
    deterministic=double(summary.deterministicEstimate(row));
    if abs(reference-deterministic)>5e-8
        error('SHT:F34Prior:ConstantReference','当前h15与上游确定性值不一致。');
    end
    residualHealth=[residualHealth,double(samples.(variable))-reference]; %#ok<AGROW>
    referenceHealth=[referenceHealth;reference]; %#ok<AGROW>
    nodeMap=[nodeMap;table("health_constant",c,1,0,reference,0, ...
        'VariableNames',{'kind','c_index','node_index','coordinate', ...
        'reference_value','family_index'})]; %#ok<AGROW>
    processShape=local_block_diag_append(processShape, ...
        local_unselected_health_sigma(options)^2);
end

% 新三部件上游同时交付逐粒子的条件物理参数均值及共同条件协方差。
% 保留其与健康曲线样本的关联；传感器偏置不从台架传递到飞行。
conditionalInherited=false;conditionalCount=0;
if isfield(options,'modelMode')&&options.modelMode==0
    if strcmp(options.sourceStage,'2p7')
        eta=readtable(options.sourceWorkbook,'Sheet','NuisancePrior');
        etaMean=readtable(options.sourceWorkbook,'Sheet','NuisanceSamples');
        assert(height(etaMean)==n&&isequal(etaMean.sample_id,samples.sampleId), ...
            'TC27物理干扰样本编号不一致。');
        ids=double(eta.c_index);means=zeros(n,height(eta));
        for j=1:height(eta),means(:,j)=double(etaMean.(sprintf('h%d',ids(j))));end
        covariance=zeros(height(eta)); % TC27交付的是联合样本，不再叠加一次先验方差。
        keep=(1:height(eta)).';
    else
    eta=readtable(options.sourceWorkbook,'Sheet','ConditionalNuisance');
    etaMean=readtable(options.sourceWorkbook,'Sheet','ConditionalMeans');
    etaCov=readtable(options.sourceWorkbook,'Sheet','ConditionalCovariance');
    assert(height(etaMean)==n && isequal(etaMean.sampleId,samples.sampleId), ...
        '条件物理参数与主后验样本编号不一致。');
    keep=find(string(eta.group_kind)=="health_constant" & string(eta.unit)=="1");
    ids=double(eta.c_index(keep));
    assert(numel(unique(ids))==numel(ids)&&all(ids>=0&ids<58), ...
        '条件物理字典重复或包含本轮不支持的瞬态参数。');
    means=zeros(n,numel(keep));
    for j=1:numel(keep)
        means(:,j)=double(etaMean.(sprintf('eta%02d',keep(j))));
    end
    covariance=double(etaCov{:,:});covariance=covariance(keep,keep);
    end
    references=context.priorSchedule.designHealth(ids+1);
    % Excel中的eta为绝对系数。与既有确定性曲线相减，转为条件增量。
    residualHealth=[residualHealth,means-references(:).'];
    referenceHealth=[referenceHealth;references(:)];
    processShape=local_block_diag_append(processShape,covariance);
    count=numel(keep);
    nodeMap=[nodeMap;table(repmat("health_constant",count,1),ids(:), ...
        ones(count,1),zeros(count,1),references(:),zeros(count,1), ...
        'VariableNames',nodeMap.Properties.VariableNames)];
    conditionalInherited=true;conditionalCount=count;
end

% 首次飞行的燃油测量系统不同于台架系统。这里只建立零中心飞行燃油
% 曲线先验；台架PosteriorSamples中的Wf_bias列从未进入显式中心或条件。
fuel=context.priorSchedule.fuelBias;
fuelCount=numel(fuel.xNodes);
fuelBasis=context.fuelMap.basis(:);
fuelDenominator=fuelBasis.'*fuelBasis;
if fuelDenominator<=eps
    error('SHT:F34Prior:FuelBasis','飞行燃油偏置幅值基函数为空。');
end
fuelProjector=eye(fuelCount)-fuelBasis*fuelBasis.'/fuelDenominator;
fuelCorrelation=local_node_correlation(fuel.xNodes,0.40);
fuelShapeSigma=options.firstFlightFuelShapeSigma_kgps;
fuelShapeCov=fuelShapeSigma^2*(fuelProjector*fuelCorrelation*fuelProjector.');
processShape=local_block_diag_append(processShape,fuelShapeCov);
residualAll=[residualHealth,zeros(n,fuelCount)];
nodeMap=[nodeMap;table(repmat("fuel_bias",fuelCount,1), ...
    nan(fuelCount,1),(1:fuelCount).',fuel.xNodes(:),zeros(fuelCount,1), ...
    zeros(fuelCount,1),'VariableNames',{'kind','c_index','node_index', ...
    'coordinate','reference_value','family_index'})];

% 健康量和燃油量具有不同单位，不能把二者未经尺度处理后竞争同一组
% 特征值。分别提取低秩基，再拼成块对角映射，确保燃油曲线形状不会因
% kg/s数值较小而被健康量方向挤出。
healthCount=size(residualHealth,2);
if strcmp(context.options.scheduleParameterization,'independent_nodes')
    % 在任何低秩压缩之前恢复完整物理节点。幅值/残差分解仅用于无损恢复
    % 原工程变化协方差，不约束本轮独立节点只能同向移动。
    lift=zeros(height(nodeMap),familyCount+2);
    for j=1:familyCount
        index=find(nodeMap.family_index==j);
        lift(index,j)=family(j).basis(:);
    end
    lift(healthCount+1:end,end)=fuelBasis;
    sigma=local_explicit_process_sigma(options,familyCount+2);
    rawCenters=residualAll+[explicitHealth,zeros(n,2)]*lift.';
    rawCov=processShape+lift*diag(sigma.^2)*lift.';
    rawNext=processShape;
    if conditionalCount>0
        inherited=healthCount-conditionalCount+(1:conditionalCount);
        rawNext(inherited,:)=0;rawNext(:,inherited)=0;
    end
    ratio=[repmat(median(options.flightToFlightShapeSigma(:))/ ...
        median(options.benchToFlightShapeSigma(:)),healthCount,1); ...
        repmat(options.flightToFlightFuelShapeSigma_kgps/ ...
        options.firstFlightFuelShapeSigma_kgps,fuelCount,1)];
    rawNext=rawNext.*(ratio*ratio.');
    nextSigma=local_explicit_process_sigma(local_force_transition(options,'flight_to_flight'),9);
    rawNext=rawNext+lift*diag(nextSigma.^2)*lift.';
    prior=sht_f34_node_prior('build',context,options,nodeMap,weights, ...
        rawCenters,rawCov,rawNext,manifest,healthCount);
    prior.quality.conditionalNuisanceInherited=conditionalInherited;
    prior.quality.inheritedConditionalPhysicalCount=conditionalCount;
    prior.quality.rawReconstructionMaximum=reconstructionMaximum;
    return;
end
healthSecond=residualHealth.'*(residualHealth.*weights)+ ...
    processShape(1:healthCount,1:healthCount);
fuelSecond=fuelShapeCov;
healthMaximum=max(0,options.nuisanceMaximumRank-options.nuisanceFuelMaximumRank);
[healthBasis,healthEigen,healthTotal]=local_low_rank_basis( ...
    healthSecond,options.nuisanceRetainedVariance,healthMaximum);
[fuelShapeBasis,fuelEigen,fuelTotal]=local_low_rank_basis( ...
    fuelSecond,options.nuisanceRetainedVariance,options.nuisanceFuelMaximumRank);
basis=blkdiag(healthBasis,fuelShapeBasis);
eigenvalue=[healthEigen(:);fuelEigen(:)];
rankValue=size(basis,2);
total=healthTotal+fuelTotal;
zSamples=residualAll*basis;
processCovZ=basis.'*processShape*basis;
retained=1;
if total>eps,retained=sum(eigenvalue)/total;end

parameter=context.parameterContract;
if height(parameter)~=familyCount+2
    error('SHT:F34Prior:ExplicitDimension','当前R1显式维数不是7+2。');
end
centers=zeros(n,height(parameter));
centers(:,1:familyCount)=explicitHealth;
sigma=local_explicit_process_sigma(options,height(parameter));

prior=struct();
prior.schemaVersion='SHT_F34_PROPAGATED_PRIOR_V1';
prior.sourceStage=options.sourceStage;
prior.sourceMethod=options.sourceMethod;
prior.sourceWorkbook=options.sourceWorkbook;
prior.sourceWorkbookSha256=sht_f33_model_adapt_v2('fileHash',options.sourceWorkbook);
prior.sourceManifest=manifest;
prior.evidenceLineage=table(zeros(0,1),strings(0,1),strings(0,1), ...
    strings(0,1),strings(0,1),strings(0,1), ...
    'VariableNames',{'evidence_order','stage_id','engine_id','sortie_id', ...
    'evidence_sha256','evidence_role'});
prior.transitionMode=options.transitionMode;
prior.parameterTable=parameter;
prior.componentWeights=weights;
prior.componentCenters=centers;
prior.componentSigma=sigma(:).';
prior.lowerBound=parameter.lower_bound(:).';
prior.upperBound=parameter.upper_bound(:).';
prior.componentLogNormalization=local_component_log_normalization( ...
    centers,prior.componentSigma,prior.lowerBound,prior.upperBound);
prior.shape=struct('nodeMap',nodeMap,'basis',basis, ...
    'zSamples',zSamples,'processCovarianceZ',processCovZ, ...
    'componentCovarianceZ',zeros(rankValue,rankValue,0), ...
    'coordinateSecondMoment',eigenvalue(1:rankValue), ...
    'fullProcessCovariance',processShape,'retainedRank',rankValue, ...
    'retainedSecondMomentFraction',retained, ...
    'discardedSecondMomentFraction',max(0,1-retained), ...
    'referenceHealthNodes',referenceHealth, ...
    'healthNodeCount',size(residualHealth,2), ...
    'fuelNodeCount',fuelCount,'reconstructionMaximum',reconstructionMaximum);
prior.quality=struct( ...
    'conditionalNuisanceInherited',conditionalInherited, ...
    'inheritedConditionalPhysicalCount',conditionalCount, ...
    'conditionalNuisanceMode','joint_curve_samples_conditional_physics_and_transition', ...
    'benchFuelBiasMarginalized',true, ...
    'testDataUsed',false,'truthDataUsed',false, ...
    'processCovarianceCalibrated',false, ...
    'processCovarianceBasis','engineering_judgement_pending_longitudinal_study', ...
    'upstreamFormalStatus',char(string(manifest.formal_status(1))));
prior.engineeringAssumption=local_engineering_assumption(options,sigma,rankValue,retained);
prior.summary=local_summary(prior);
end

function prior=local_build_previous_flight(context,options)
% 正式路径读取上一架次Excel交付物，其中必须同时保存每个显式样本
% 的条件形状坐标。MAT仅保留为阶段内部检查点兼容路径。
if isempty(options.sourcePosteriorFile) || ~isfile(options.sourcePosteriorFile)
    error('SHT:F34Prior:PreviousFlight', ...
        'previous_flight必须显式给出上一架次后验文件。');
end
% 下游正式递推优先读取Excel交付物；MAT仅作本阶段内部缓存的兼容路径。
[~,~,extension]=fileparts(options.sourcePosteriorFile);
if strcmpi(extension,'.xlsx')
    posterior=sht_f34_io('readPosterior',options.sourcePosteriorFile);
else
    loaded=load(options.sourcePosteriorFile);
    if isfield(loaded,'methodC')
        posterior=loaded.methodC;
    elseif isfield(loaded,'result')
        posterior=loaded.result;
    else
        error('SHT:F34Prior:PreviousFlight','上一架次文件缺少后验结构。');
    end
end
if ~isfield(posterior,'samples') || ~isfield(posterior,'weights')
    error('SHT:F34Prior:PreviousFlight','上一架次后验缺少联合样本及权重。');
end
if ~isfield(posterior,'evidenceLineage')||~istable(posterior.evidenceLineage)|| ...
        ~ismember('evidence_sha256',posterior.evidenceLineage.Properties.VariableNames)
    error('SHT:F34Prior:PreviousFlightEvidence', ...
        '上一架次正式后验缺少EvidenceLineage，不能安全执行递推。');
end
if any(strcmpi(string(posterior.evidenceLineage.evidence_sha256), ...
        string(context.uqTrainingSourceSha256)))
    error('SHT:F34Prior:DuplicateEvidence', ...
        '当前飞参训练证据已出现在祖先后验中，禁止重复乘入同一似然。');
end
centers=posterior.samples.';
if size(centers,2)~=height(context.parameterContract)
    error('SHT:F34Prior:PreviousFlight','上一架次显式参数维数不一致。');
end
weights=local_normalize_weights(posterior.weights(:));
sigma=local_explicit_process_sigma(options,height(context.parameterContract));
if ~isfield(posterior,'conditionalShapeMean') || ...
        size(posterior.conditionalShapeMean,2)~=numel(weights)
    error('SHT:F34Prior:PreviousFlightShape', ...
        '上一架次后验缺少与样本对应的条件形状均值。');
end
if ~isfield(posterior,'priorShape')
    error('SHT:F34Prior:PreviousFlightShape','上一架次缺少形状映射合同。');
end
prior=struct('schemaVersion','SHT_F34_PROPAGATED_PRIOR_V1', ...
    'sourceStage','previous_flight','sourceMethod',options.sourceMethod, ...
    'sourceWorkbook',options.sourcePosteriorFile, ...
    'sourceWorkbookSha256',sht_f33_model_adapt_v2( ...
    'fileHash',options.sourcePosteriorFile),'sourceManifest',table(), ...
    'evidenceLineage',posterior.evidenceLineage, ...
    'transitionMode',options.transitionMode,'parameterTable',context.parameterContract, ...
    'componentWeights',weights,'componentCenters',centers, ...
    'componentSigma',sigma(:).','lowerBound',context.parameterContract.lower_bound(:).', ...
    'upperBound',context.parameterContract.upper_bound(:).');
prior.componentLogNormalization=local_component_log_normalization( ...
    centers,prior.componentSigma,prior.lowerBound,prior.upperBound);
prior.shape=posterior.priorShape;
prior.shape.zSamples=posterior.conditionalShapeMean.';
if isfield(posterior,'conditionalShapeCovariance')&& ...
        size(posterior.conditionalShapeCovariance,3)==numel(weights)
    prior.shape.componentCovarianceZ=posterior.conditionalShapeCovariance;
elseif isfield(posterior,'conditionalShapeCovarianceMean')
    prior.shape.componentCovarianceZ=repmat( ...
        posterior.conditionalShapeCovarianceMean,1,1,numel(weights));
else
    error('SHT:F34Prior:PreviousFlightShape', ...
        '上一架次后验缺少条件形状协方差。');
end
% 组件协方差保留上一架次后验不确定性；processCovarianceZ
% 只保存从上一架次到当前架次新增的形状Q，避免重复相加。
prior.shape.processCovarianceZ= ...
    local_flight_shape_process_covariance(prior.shape,options);
prior.quality=struct('conditionalNuisanceInherited',true, ...
    'conditionalNuisanceMode','previous_flight_conditional_moments', ...
    'benchFuelBiasMarginalized',true,'testDataUsed',false,'truthDataUsed',false, ...
    'processCovarianceCalibrated',false, ...
    'processCovarianceBasis','engineering_judgement_pending_longitudinal_study', ...
    'upstreamFormalStatus','F34_PREVIOUS_FLIGHT');
prior.engineeringAssumption=local_engineering_assumption( ...
    options,sigma,prior.shape.retainedRank,prior.shape.retainedSecondMomentFraction);
prior.summary=local_summary(prior);
end

function sample=local_draw(prior,count,seed)
if isfield(prior,'nodePrior')
    error('SHT:F34Prior:NodeSamplerReserved','本轮只实现节点D；不得用幅值独立正态抽样器抽取节点相关先验。');
end
if nargin<3 || isempty(seed),seed=340001;end
if ~isscalar(count)||count<1||count~=round(count)
    error('SHT:F34Prior:DrawCount','样本数必须为正整数。');
end
stream=RandStream('mt19937ar','Seed',round(seed));
component=local_weighted_index(prior.componentWeights,count,stream);
d=size(prior.componentCenters,2);
sample=zeros(d,count);
for i=1:count
    mu=prior.componentCenters(component(i),:);
    sample(:,i)=local_truncated_normal_draw(mu,prior.componentSigma, ...
        prior.lowerBound,prior.upperBound,stream).';
end
end

function [value,responsibility]=local_logpdf(prior,theta)
if isfield(prior,'nodePrior')
    [value,responsibility]=sht_f34_node_prior('logpdf',prior,theta);return;
end
theta=local_theta_matrix(theta,size(prior.componentCenters,2));
n=size(theta,2);m=size(prior.componentCenters,1);
logComponent=zeros(m,n);
logWeight=log(max(prior.componentWeights(:),realmin));
sigma=prior.componentSigma;
constant=-sum(log(sigma*sqrt(2*pi)));
for k=1:n
    x=theta(:,k).';
    if any(x<prior.lowerBound) || any(x>prior.upperBound) || any(~isfinite(x))
        logComponent(:,k)=-Inf;
        continue;
    end
    z=(x-prior.componentCenters)./sigma;
    logComponent(:,k)=logWeight+constant-0.5*sum(z.^2,2) ...
        -prior.componentLogNormalization;
end
value=local_logsumexp(logComponent,1);
if nargout>1
    responsibility=exp(logComponent-value);
    responsibility(:,~isfinite(value))=0;
end
end

function responsibility=local_responsibilities(prior,theta)
[~,responsibility]=local_logpdf(prior,theta);
end

function [meanZ,covZ,responsibility]=local_conditional_shape(prior,theta)
if isfield(prior,'nodePrior')
    [meanZ,covZ,responsibility]=sht_f34_node_prior('conditionalShape',prior,theta);return;
end
theta=local_theta_matrix(theta,size(prior.componentCenters,2));
responsibility=local_responsibilities(prior,theta);
k=size(prior.shape.basis,2);n=size(theta,2);
meanZ=zeros(k,n);covZ=zeros(k,k,n);
for i=1:n
    w=responsibility(:,i);
    if sum(w)<=0
        meanZ(:,i)=NaN;covZ(:,:,i)=NaN;continue;
    end
    w=w/sum(w);
    meanZ(:,i)=prior.shape.zSamples.'*w;
    centered=prior.shape.zSamples-meanZ(:,i).';
    covariance=centered.'*(centered.*w)+prior.shape.processCovarianceZ;
    if isfield(prior.shape,'componentCovarianceZ')&& ...
            size(prior.shape.componentCovarianceZ,3)==numel(w)
        for componentIndex=1:numel(w)
            covariance=covariance+w(componentIndex)* ...
                prior.shape.componentCovarianceZ(:,:,componentIndex);
        end
    end
    covZ(:,:,i)=(covariance+covariance.')/2;
end
end

function schedule=local_apply_shape(schedule,prior,z)
z=z(:);
if numel(z)~=size(prior.shape.basis,2) || any(~isfinite(z))
    error('SHT:F34Prior:ShapeCoordinate','形状坐标维数或数值无效。');
end
delta=prior.shape.basis*z;
map=prior.shape.nodeMap;
for c=unique(map.c_index(map.kind=="health")).'
    rows=find(map.kind=="health" & map.c_index==c);
    entryIndex=find([schedule.healthEntries.cIndex]==c,1);
    if isempty(entryIndex),error('SHT:F34Prior:ShapeEntry','缺少h%d曲线。',c);end
    entry=schedule.healthEntries(entryIndex);
    entry.kNodes=entry.kNodes(:)+delta(rows);
    if entry.pressureLoss && entry.xNodes(1)==0,entry.kNodes(1)=0;end
    entry.designValue=local_interp_clamp( ...
        entry.xNodes,entry.kNodes,entry.designCoordinate);
    entry.xNodesDll=entry.xNodes;
    entry.kNodesDll=entry.kNodes;
    entry.deltaNodesDll=entry.kNodes-entry.designValue;
    schedule.healthEntries(entryIndex)=entry;
end
rows=find(map.kind=="health_constant");
for i=rows(:).'
    c=map.c_index(i);
    if c==15,schedule.h15=schedule.h15+delta(i);
    else,schedule.designHealth(c+1)=schedule.designHealth(c+1)+delta(i);end
end
rows=find(map.kind=="fuel_bias");
schedule.fuelBias.biasNodes=schedule.fuelBias.biasNodes(:)+delta(rows);
schedule=local_design_health(schedule);
end

function [meanValue,covariance]=local_moments(prior)
if isfield(prior,'nodePrior')
    [meanValue,covariance]=sht_f34_node_prior('moments',prior);return;
end
w=prior.componentWeights(:);
center=prior.componentCenters;
[componentMean,componentVariance]=local_truncated_component_moments( ...
    center,prior.componentSigma,prior.lowerBound,prior.upperBound);
meanValue=componentMean.'*w;
centered=componentMean-meanValue.';
covariance=centered.'*(centered.*w)+diag(componentVariance.'*w);
covariance=(covariance+covariance.')/2;
end

function next=local_transition(prior,posterior,options)
% 将本架次方法C样本变为下一架次传播中心。该动作只做预测分布，不重复
% 使用当前架次似然；下一架次真正更新时由新的证据ID另建合同。
if ~isfield(posterior,'samples')||~isfield(posterior,'weights')
    error('SHT:F34Prior:Transition','当前后验缺少样本或权重。');
end
next=prior;
next.sourceStage='previous_flight';
next.transitionMode='flight_to_flight';
next.componentCenters=posterior.samples.';
next.componentWeights=local_normalize_weights(posterior.weights(:));
next.componentSigma=local_explicit_process_sigma( ...
    local_force_transition(options,'flight_to_flight'), ...
    size(next.componentCenters,2));
next.componentLogNormalization=local_component_log_normalization( ...
    next.componentCenters,next.componentSigma,next.lowerBound,next.upperBound);
if isfield(posterior,'conditionalShapeMean')
    next.shape.zSamples=posterior.conditionalShapeMean.';
end
if isfield(posterior,'conditionalShapeCovariance')&& ...
        size(posterior.conditionalShapeCovariance,3)==numel(next.componentWeights)
    next.shape.componentCovarianceZ=posterior.conditionalShapeCovariance;
elseif isfield(posterior,'conditionalShapeCovarianceMean')
    next.shape.componentCovarianceZ=repmat( ...
        posterior.conditionalShapeCovarianceMean,1,1,numel(next.componentWeights));
else
    error('SHT:F34Prior:TransitionShape', ...
        '当前后验缺少条件形状协方差。');
end
next.shape.processCovarianceZ= ...
    local_flight_shape_process_covariance(next.shape,options);
next.quality.processCovarianceCalibrated=false;
next.quality.processCovarianceBasis= ...
    'engineering_judgement_pending_longitudinal_study';
next.engineeringAssumption=local_engineering_assumption( ...
    local_force_transition(options,'flight_to_flight'),next.componentSigma, ...
    next.shape.retainedRank,next.shape.retainedSecondMomentFraction);
next.summary=local_summary(next);
end

function covarianceZ=local_flight_shape_process_covariance(shape,options)
% 首轮形状Q已经保存在完整节点空间。下一架次按健康/燃油各自工程尺度
% 缩放后再投影到同一低秩坐标，避免混合单位方向使用一个统一方差。
full=shape.fullProcessCovariance;
nHealth=shape.healthNodeCount;
healthRatio=median(options.flightToFlightShapeSigma(:))/ ...
    median(options.benchToFlightShapeSigma(:));
fuelRatio=options.flightToFlightFuelShapeSigma_kgps/ ...
    options.firstFlightFuelShapeSigma_kgps;
full(1:nHealth,1:nHealth)=healthRatio^2*full(1:nHealth,1:nHealth);
fuel=(nHealth+1):size(full,1);
full(fuel,fuel)=fuelRatio^2*full(fuel,fuel);
full(1:nHealth,fuel)=0;full(fuel,1:nHealth)=0;
covarianceZ=shape.basis.'*full*shape.basis;
covarianceZ=(covarianceZ+covarianceZ.')/2;
end

function sigma=local_explicit_process_sigma(options,dimension)
if dimension~=9
    error('SHT:F34Prior:Dimension','当前R1显式先验必须为9维。');
end
if strcmp(options.transitionMode,'bench_to_flight')
    health=options.benchToFlightHealthSigma;
    kdist=options.firstFlightKdistSigma;
    fuel=options.firstFlightFuelSigma_kgps;
elseif strcmp(options.transitionMode,'flight_to_flight')
    health=options.flightToFlightHealthSigma;
    kdist=options.flightToFlightKdistSigma;
    fuel=options.flightToFlightFuelSigma_kgps;
else
    error('SHT:F34Prior:TransitionMode','未知变化模式%s。',options.transitionMode);
end
if isscalar(health),health=repmat(health,1,7);end
if numel(health)~=7 || any(~isfinite(health)) || any(health<=0)
    error('SHT:F34Prior:HealthSigma','健康变化标准差必须是7个有限正数。');
end
sigma=[health(:).',kdist,fuel];
if any(~isfinite(sigma))||any(sigma<=0)
    error('SHT:F34Prior:ProcessSigma','显式变化标准差无效。');
end
end

function value=local_health_shape_sigma(options,index)
if strcmp(options.transitionMode,'bench_to_flight')
    value=options.benchToFlightShapeSigma;
else
    value=options.flightToFlightShapeSigma;
end
if isscalar(value),return;end
if numel(value)~=7,error('SHT:F34Prior:ShapeSigma','形状变化尺度维数无效。');end
value=value(index);
end

function value=local_unselected_health_sigma(options)
if strcmp(options.transitionMode,'bench_to_flight')
    source=options.benchToFlightShapeSigma;
else
    source=options.flightToFlightShapeSigma;
end
value=median(source(:));
if ~isfinite(value)||value<=0
    error('SHT:F34Prior:UnselectedSigma','未显式健康量变化尺度无效。');
end
end

function assumption=local_engineering_assumption(options,sigma,rankValue,retained)
assumption=struct('calibrated',false, ...
    'status','ENGINEERING_ASSUMPTION_REQUIRES_FUTURE_LONGITUDINAL_STUDY', ...
    'transitionMode',options.transitionMode, ...
    'explicitParameterSigma',sigma(:), ...
    'shapeRetainedRank',rankValue, ...
    'shapeRetainedSecondMomentFraction',retained, ...
    'futureWork',[ ...
    '应使用同一台发动机多架次/多周期后验增量、任务间隔、维修和换件记录，' ...
    '分离采样误差后标定Q，并开展敏感性与长期覆盖率校核。']);
end

function summary=local_summary(prior)
[mu,covariance]=local_moments(prior);
summary=table(prior.parameterTable.parameter_id, ...
    prior.parameterTable.name,prior.parameterTable.unit,mu,sqrt(diag(covariance)), ...
    prior.parameterTable.lower_bound,prior.parameterTable.upper_bound, ...
    'VariableNames',{'parameter_id','name','unit','prior_mean', ...
    'prior_std_approx','lower_bound','upper_bound'});
end

function local_validate_upstream(manifest,summary,samples,options)
if height(manifest)~=1 || ~all(ismember({'formal_status','method_id', ...
        'parameter_count','sample_count'},manifest.Properties.VariableNames))
    error('SHT:F34Prior:Manifest','上游Manifest结构无效。');
end
if isfield(options,'modelMode')&&ismember('model_mode',manifest.Properties.VariableNames)&& ...
        double(manifest.model_mode(1))~=options.modelMode
    error('SHT:F34Prior:ModelMode','后验模型身份与当前第3阶段模型不一致。');
end
if ~strcmpi(char(string(manifest.method_id(1))),options.sourceMethod)
    error('SHT:F34Prior:Method','上游方法与配置不一致。');
end
if ~strcmp(options.sourceStage,'2p7')&& ...
        ~contains(upper(char(string(manifest.formal_status(1)))),'ACCEPTED')
    error('SHT:F34Prior:FormalStatus','上游后验未标记为正式接受。');
end
requiredSummary={'name','cIndex','groupKind','coordinate', ...
    'deterministicEstimate'};
requiredSample={'sampleId','sampleWeight'};
if ~all(ismember(requiredSummary,summary.Properties.VariableNames)) || ...
        ~all(ismember(requiredSample,samples.Properties.VariableNames))
    error('SHT:F34Prior:UpstreamSchema','上游参数表或样本表字段不完整。');
end
if height(summary)~=double(manifest.parameter_count(1)) || ...
        height(samples)~=double(manifest.sample_count(1))
    error('SHT:F34Prior:UpstreamCount','上游Manifest计数与工作表不一致。');
end
end

function [manifest,summary,samples]=local_tc27_tables(file)
% 只统一字段名称，不改变TC27联合样本、权重、物理编号和节点。
raw=readtable(file,'Sheet','Manifest');uq=readtable(file,'Sheet','UQManifest');
d=readtable(file,'Sheet','ParameterDictionary');s=readtable(file,'Sheet','PosteriorSamples');
method=string(uq.value(string(uq.key)=="method"));
assert(isscalar(method)&&method=="C",'当前TC27来源要求方法C联合样本。');
quality=string(uq.value(string(uq.key)=="quality"));
assert(isscalar(quality)&&contains(quality,'POSTERIOR'),'TC27后验质量字段缺失。');
manifest=table(quality,method,height(d),height(s),double(raw.model_mode(1)), ...
    'VariableNames',{'formal_status','method_id','parameter_count','sample_count','model_mode'});
kind=string(d.group_kind);kind(kind=="health_constant")="constant";
summary=table(string(d.node_id),double(d.c_index),kind,double(d.coordinate), ...
    double(d.point_estimate),'VariableNames', ...
    {'name','cIndex','groupKind','coordinate','deterministicEstimate'});
samples=table(s.sample_id,s.weight,'VariableNames',{'sampleId','sampleWeight'});
for j=1:height(d)
    name=char(string(d.node_id(j)));assert(ismember(name,s.Properties.VariableNames));
    samples.(['theta_',name])=s.(name);
end
end

function logNorm=local_component_log_normalization(center,sigma,lower,upper)
alpha=(lower-center)./sigma;
beta=(upper-center)./sigma;
mass=local_normcdf(beta)-local_normcdf(alpha);
if any(mass<=0,'all')||any(~isfinite(mass),'all')
    error('SHT:F34Prior:Truncation','截断高斯分量的支持质量无效。');
end
logNorm=sum(log(mass),2);
end

function x=local_truncated_normal_draw(mu,sigma,lower,upper,stream)
lo=local_normcdf((lower-mu)./sigma);
hi=local_normcdf((upper-mu)./sigma);
u=lo+(hi-lo).*rand(stream,size(mu));
u=min(max(u,eps),1-eps);
x=mu+sigma.*local_norminv(u);
x=min(max(x,lower),upper);
end

function value=local_normcdf(x)
value=0.5*erfc(-x/sqrt(2));
end

function value=local_normpdf(x)
value=exp(-0.5*x.^2)/sqrt(2*pi);
end

function [meanValue,variance]=local_truncated_component_moments( ...
        center,sigma,lower,upper)
alpha=(lower-center)./sigma;beta=(upper-center)./sigma;
mass=local_normcdf(beta)-local_normcdf(alpha);
phiAlpha=local_normpdf(alpha);phiBeta=local_normpdf(beta);
ratio=(phiAlpha-phiBeta)./mass;
meanValue=center+sigma.*ratio;
variance=sigma.^2.*(1+(alpha.*phiAlpha-beta.*phiBeta)./mass-ratio.^2);
variance=max(variance,0);
end

function value=local_norminv(p)
value=-sqrt(2)*erfcinv(2*p);
end

function value=local_logsumexp(x,dimension)
maximum=max(x,[],dimension);
shift=x-maximum;
shift(~isfinite(shift))=-Inf;
value=maximum+log(sum(exp(shift),dimension));
value(~isfinite(maximum))=-Inf;
end

function index=local_weighted_index(weight,count,stream)
edge=cumsum(local_normalize_weights(weight));edge(end)=1;
u=rand(stream,count,1);index=zeros(count,1);
for i=1:count,index(i)=find(edge>=u(i),1);end
end

function weight=local_normalize_weights(weight)
if any(~isfinite(weight))||any(weight<0)||sum(weight)<=0
    error('SHT:F34Prior:Weights','样本权重无效。');
end
weight=weight(:)/sum(weight);
end

function matrix=local_node_correlation(nodes,lengthScale)
x=nodes(:);span=max(x)-min(x);
if span<=eps,matrix=1;return;end
d=abs(x-x.')/span;
matrix=exp(-d/max(lengthScale,eps));
matrix=(matrix+matrix.')/2;
end

function value=local_sample_columns(samples,summary,row)
value=zeros(height(samples),numel(row));
for k=1:numel(row)
    variable=['theta_',char(string(summary.name(row(k))))];
    if ~ismember(variable,samples.Properties.VariableNames)
        error('SHT:F34Prior:SampleColumn','上游样本缺少%s。',variable);
    end
    value(:,k)=double(samples.(variable));
end
end

function index=local_match_entry_nodes(coordinate,entryCoordinate,cIndex)
coordinate=coordinate(:);entryCoordinate=entryCoordinate(:);
tolerance=1e-9*max(1,max(abs(entryCoordinate)));index=zeros(numel(coordinate),1);
for i=1:numel(coordinate)
    [difference,j]=min(abs(entryCoordinate-coordinate(i)));
    if difference>tolerance || any(index(1:i-1)==j)
        error('SHT:F34Prior:NodeCoordinate', ...
            '上游h%d坐标%.16g不能唯一映射到当前完整曲线。', ...
            cIndex,coordinate(i));
    end
    index(i)=j;
end
end

function [basis,eigenvalue,total]=local_low_rank_basis(moment,retained,maxRank)
moment=(moment+moment.')/2;
if isempty(moment) || maxRank==0
    basis=zeros(size(moment,1),0);eigenvalue=zeros(0,1);total=trace(moment);return;
end
[vector,value]=eig(moment,'vector');
[allEigen,order]=sort(max(real(value),0),'descend');
vector=real(vector(:,order));total=sum(allEigen);
if total<=eps
    basis=zeros(size(moment,1),0);eigenvalue=zeros(0,1);return;
end
rankValue=find(cumsum(allEigen)/total>=retained,1);
rankValue=min([rankValue,maxRank,size(vector,2)]);
basis=vector(:,1:rankValue);
eigenvalue=allEigen(1:rankValue);
end

function value=local_block_diag_append(value,block)
if isempty(value),value=block;else,value=blkdiag(value,block);end
end

function theta=local_theta_matrix(theta,dimension)
theta=double(theta);
if isvector(theta),theta=theta(:);end
if size(theta,1)~=dimension
    error('SHT:F34Prior:ThetaDimension','显式参数维数应为%d。',dimension);
end
end

function schedule=local_design_health(schedule)
health=schedule.designHealth(:);
for i=1:numel(schedule.healthEntries)
    entry=schedule.healthEntries(i);
    value=local_interp_clamp(entry.xNodes,entry.kNodes,entry.designCoordinate);
    schedule.healthEntries(i).designValue=value;
    health(entry.cIndex+1)=value;
end
health(16)=schedule.h15;
schedule.designHealth=health;
end

function value=local_interp_clamp(x,y,q)
x=x(:);y=y(:);q=min(max(q,x(1)),x(end));
if numel(x)==1,value=y(1);else,value=interp1(x,y,q,'linear');end
end

function value=local_force_transition(options,mode)
value=options;value.transitionMode=mode;
end

function local_require_fields(value,names,label)
if ~isstruct(value)||~isscalar(value)||~all(isfield(value,names))
    error('SHT:F34Prior:Fields','%s缺少字段：%s。',label, ...
        strjoin(names(~isfield(value,names)),', '));
end
end
