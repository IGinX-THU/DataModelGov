function varargout=sht_f34_likelihood(action,varargin)
%SHT_F34_LIKELIHOOD 3.4 R1共用概率似然及条件干扰后验。
%
% 观测为9个稳态窗口的Np、Ng、Pt3_eq和Tt45均值。物理均值由DLL
% 充分热平衡求值；输出公共偏置、窗口均值白噪声、输入测量误差和模型
% 差异构成R0；完整健康/燃油曲线的低秩形状不确定性按给定显式参数做
% 条件边缘化。3.3工程权重不进入本概率模型。

persistent physicsCache cacheHit cacheMiss
if isempty(physicsCache)
    physicsCache=containers.Map('KeyType','char','ValueType','any');
    cacheHit=0;cacheMiss=0;
end

switch lower(char(action))
    case 'build'
        varargout{1}=local_build(varargin{:});
    case 'evaluate'
        [result,conditional,physical,stats]=local_evaluate( ...
            varargin{:},physicsCache,cacheHit,cacheMiss);
        cacheHit=stats.hit;cacheMiss=stats.miss;
        value={result,conditional,physical,stats};
        varargout=value(1:nargout);
    case 'conditionalposterior'
        [varargout{1:nargout}]=local_conditional_posterior(varargin{:});
    case 'evaluatephysicalshape'
        % 为本轮预测和后续方法B显式联合采样共用的精确物理入口。
        % 方法B尚未实现；本接口不会把其请求静默降级为方法C。
        varargout{1}=local_evaluate_physical_shape(varargin{:});
    case 'clearcache'
        physicsCache=containers.Map('KeyType','char','ValueType','any');
        cacheHit=0;cacheMiss=0;
    case 'cachestats'
        varargout{1}=struct('hit',cacheHit,'miss',cacheMiss, ...
            'entryCount',physicsCache.Count);
    case 'loadcache'
        [physicsCache,cacheHit,cacheMiss]=local_load_cache( ...
            varargin{1},varargin{2});
        varargout{1}=struct('hit',cacheHit,'miss',cacheMiss, ...
            'entryCount',physicsCache.Count);
    case 'savecache'
        local_save_cache(varargin{1},varargin{2},physicsCache,cacheHit,cacheMiss);
    case 'seedcache'
        physicsCache=local_seed_cache(varargin{1},varargin{2}, ...
            varargin{3},physicsCache);
        varargout{1}=struct('hit',cacheHit,'miss',cacheMiss, ...
            'entryCount',physicsCache.Count);
    otherwise
        error('SHT:F34Likelihood:Action','未知似然动作：%s。',char(action));
end
end

function likelihood=local_build(context,prior,options,preparedContract)
if nargin<4||~isstruct(preparedContract)||~isscalar(preparedContract)
    error('SHT:F34Likelihood:PreparedContract', ...
        '构造似然时必须显式传入当前3.4准备合同。');
end
fprintf('\n3.4.3-3.4.5 构造观测协方差和条件边缘化灵敏度……\n');
started=tic;
support=[];
if isfield(prior,'physicalSupport'),support=prior.physicalSupport;end
observationMatrix=local_observation(context);
observation=observationMatrix(:);
nWindow=height(context.steadyData);
if ~isfield(context,'steadySource') || ...
        height(context.steadySource)~=nWindow
    error('SHT:F34Likelihood:WindowCount','缺少稳态窗口样本数合同。');
end
sampleCount=double(context.steadySource.sample_count(:));
if any(sampleCount<1)||any(~isfinite(sampleCount))
    error('SHT:F34Likelihood:SampleCount','窗口样本数无效。');
end

anchorTheta=local_anchor_theta(context);
base=local_physical_direct(context,anchorTheta);
if ~base.valid
    error('SHT:F34Likelihood:Anchor','3.3 R1锚点不能得到有效物理解：%s。', ...
        base.message);
end

sensor=context.sensorAssumptions;
outputNames={'Np','Ng','Pt3_eq','Tt45'};
inputNames={'Wf','Mkp','Mkg','Tt1','Altitude','Mach','Ps0','Ts_amb'};
inputColumns={'Wf_mean','Mkp_mean','Mkg_mean','Tt1_mean', ...
    'Altitude_mean','Mach_mean','Pamb_mean','Tamb_mean'};
if context.options.modelMode==0
    inputNames(3)=[];inputColumns(3)=[]; % 飞行Mkg不是测点，本轮物理边界为0。
end
instant=strcmp(context.options.modelRoute,'transient_instant');
if instant
    outputNames={'Pt3_eq','Tt45','dNp_dt','dNg_dt'};
    inputNames=[inputNames,{'Np','Ng'}];
    inputColumns=[inputColumns,{'Np_mean','Ng_mean'}];
end

component=struct();
component.outputWhite=zeros(numel(observation));
component.outputBias=zeros(numel(observation));
component.inputWhite=zeros(numel(observation));
component.inputBias=zeros(numel(observation));
component.modelDiscrepancy=zeros(numel(observation));

% 输出测量：公共偏置在同一任务各窗口共享，不能除以窗口样本数；
% 逐点独立白噪声形成的窗口均值方差才除以样本数。
for j=1:numel(outputNames)
    if instant&&j>2,continue;end % 加速度是稳态近似约束，不是转速测量值。
    row=local_sensor_row(sensor,outputNames{j});
    index=(j-1)*nWindow+(1:nWindow);
    biasStd=sensor.totalBiasHalfWidth(row)/sqrt(3);
    component.outputBias(index,index)=component.outputBias(index,index)+ ...
        biasStd^2*ones(nWindow);
    component.outputWhite(index,index)=component.outputWhite(index,index)+ ...
        diag(sensor.noiseStd(row)^2./sampleCount);
end

% 输入测量误差通过同一物理锚点的DLL灵敏度传播。Wf的系统偏置已经由
% 显式Wf_bias曲线及其形状干扰表示，此处只传播Wf白噪声，避免双计。
inputSensitivity=struct();
inputAudit=table();
for j=1:numel(inputNames)
    name=inputNames{j};column=inputColumns{j};
    row=local_sensor_row(sensor,name);
    step=max(options.inputDifferenceScale*sensor.totalBiasHalfWidth(row), ...
        2*sensor.noiseStd(row));
    if ~isfinite(step)||step<=0
        error('SHT:F34Likelihood:InputStep','%s输入差分步无效。',name);
    end
    modified=context.steadyData;
    modified.(column)=modified.(column)+step;
    perturbedContext=local_replace_points(context,modified);
    cleanup=onCleanup(@()sht_f33_model_adapt_v2( ...
        'closeUqContext',perturbedContext)); %#ok<NASGU>
    perturbed=local_physical_direct(perturbedContext,anchorTheta);
    if ~perturbed.valid
        error('SHT:F34Likelihood:InputDifference', ...
            '%s输入前向差分不能得到有效物理解：%s。',name,perturbed.message);
    end
    derivativeMatrix=(reshape(perturbed.output,nWindow,4)- ...
        reshape(base.output,nWindow,4))/step;
    inputSensitivity.(name)=derivativeMatrix;
    biasStd=sensor.totalBiasHalfWidth(row)/sqrt(3);
    whiteStd=sensor.noiseStd(row)./sqrt(sampleCount);
    globalVector=derivativeMatrix(:);
    if ~strcmp(name,'Wf')
        component.inputBias=component.inputBias+ ...
            biasStd^2*(globalVector*globalVector.');
    end
    for i=1:nWindow
        localVector=zeros(4*nWindow,1);
        localVector(i+(0:3)*nWindow)=derivativeMatrix(i,:);
        component.inputWhite=component.inputWhite+ ...
            whiteStd(i)^2*(localVector*localVector.');
    end
    inputAudit=[inputAudit;table(string(name),string(sensor.unit(row)),step, ...
        sensor.totalBiasHalfWidth(row),sensor.noiseStd(row),~strcmp(name,'Wf'), ...
        'VariableNames',{'channel','unit','difference_step', ...
        'bias_half_width','white_noise_std','common_bias_propagated'})]; %#ok<AGROW>
end

% 预先声明的模型差异，不用当前拟合残差反向调大。每通道由少量任务内
% 共享部分和窗口独立部分组成，以避免把其伪装为传感器白噪声。
rho=options.modelDiscrepancyCorrelation;
modelStd=zeros(4,1);
for j=1:4
    if instant&&j>2
        % 与TC24瞬态时刻口径一致，允许稳态窗口有有限轴加速度。
        % 该项为平稳性工程先验，不按样本数缩小，也不重算转速测量噪声。
        modelStd(j)=options.stationarityStd_rpmps(j-2);
    else
        row=local_sensor_row(sensor,outputNames{j});sourceIndex=j;
        if instant,sourceIndex=j+2;end
        modelStd(j)=options.modelDiscrepancyFraction(sourceIndex)*sensor.designReference(row);
    end
    index=(j-1)*nWindow+(1:nWindow);
    block=modelStd(j)^2*((1-rho)*eye(nWindow)+rho*ones(nWindow));
    component.modelDiscrepancy(index,index)=block;
end

% 条件曲线形状低秩灵敏度。所有方向均使用当前参考曲线的实际DLL回放，
% 仅线性边缘化近似，不以代理模型替代物理均值。
shapeRank=prior.shape.retainedRank;
shapeSensitivity=zeros(numel(observation),shapeRank);
shapeStep=zeros(shapeRank,1);
for j=1:shapeRank
    variance=max(prior.shape.coordinateSecondMoment(j),eps);
    shapeStep(j)=max(options.shapeDifferenceScale*sqrt(variance),1e-7);
    z=zeros(shapeRank,1);z(j)=shapeStep(j);
    % 必须先构造显式参数模型，再施加剩余修正量；反过来会被3.3的
    % designHealth重建清零，导致24个物理参数的灵敏度虚假为零。
    if ~isempty(support)
        k=find(support.index==j);
        if ~isempty(k)&&z(j)>support.upper(k)
            z(j)=-shapeStep(j);shapeStep(j)=z(j);
        end
        if ~isempty(k)
            assert(z(j)>=support.lower(k)&&z(j)<=support.upper(k), ...
                '条件参数在零参考处没有合法差分方向。');
        end
    end
    shaped=local_evaluate_physical_shape(context,prior,anchorTheta,z);
    if ~shaped.valid
        error('SHT:F34Likelihood:ShapeDifference', ...
            '第%d个剩余修正量方向不能得到有效物理解：%s。',j,shaped.message);
    end
    shapeSensitivity(:,j)=(shaped.output-base.output)/shapeStep(j);
end

Rbase=component.outputWhite+component.outputBias+component.inputWhite+ ...
    component.inputBias+component.modelDiscrepancy;
Rbase=(Rbase+Rbase.')/2;
[Rbase,jitter]=local_make_spd(Rbase,'Rbase');

implementationSha256=sht_f33_model_adapt_v2( ...
    'fileHash',[mfilename('fullpath'),'.m']);
preparedContractSha256=sht_f33_model_adapt_v2('structHash',preparedContract);
physicsContract=struct( ...
    'trainingPoints',context.steadyData, ...
    'thermalBranch',context.uqThermalBranch, ...
    'priorSchedule',context.priorSchedule, ...
    'familyMap',context.familyMap, ...
    'fuelMap',context.fuelMap, ...
    'parameterContract',context.parameterContract, ...
    'physicalAssetContract',context.replayAssets.contract, ...
    'engineArtifactIdentity',context.uqEngineArtifactIdentity, ...
    'modelRoute',context.options.modelRoute, ...
    'modelOptions',context.options, ...
    'modelAdapterSha256',sht_f33_model_adapt_v2( ...
        'fileHash',which('sht_f33_model_adapt_v2')), ...
    'thermalSolverSha256',sht_f33_model_adapt_v2( ...
        'fileHash',which('sht_f33_thermal_equilibrium')));
physicsContractHash=sht_f33_model_adapt_v2('structHash',physicsContract);
% DLL相同不足以保证物理求值相同，绑定实际M调用链的关键源文件。
names={'sht_f32_replay_history','sht_f33_schedule_parameterization', ...
    'sht_thermal_equilibrium_solve','sht_tc27_thermal_reuse', ...
    'sht_engine_derivative','sht_engine_open','sht_exhaust_backpressure', ...
    'sht_lookup_clearance_reference','sht_health_schedule_initialize_dll'};
sourceHashes=cell(size(names));
for i=1:numel(names)
    sourceHashes{i}=sht_f33_model_adapt_v2('fileHash',which(names{i}));
end
physicsContractHash=sht_f33_model_adapt_v2('structHash',struct( ...
    'base',physicsContractHash,'dependencyNames',{names},'dependencyHashes',{sourceHashes}));
priorIdentity=struct('componentWeights',prior.componentWeights, ...
    'componentCenters',prior.componentCenters, ...
    'componentSigma',prior.componentSigma, ...
    'lowerBound',prior.lowerBound,'upperBound',prior.upperBound, ...
    'shapeBasis',prior.shape.basis,'shapeZSamples',prior.shape.zSamples, ...
    'shapeProcessCovarianceZ',prior.shape.processCovarianceZ, ...
    'shapeComponentCovarianceZ',prior.shape.componentCovarianceZ, ...
    'shapeNodeMap',prior.shape.nodeMap);
if isfield(prior,'nodePrior')
    priorIdentity.nodePrior=prior.nodePrior;
    priorIdentity.componentCovariance=prior.componentCovariance;
end

likelihood=struct('schemaVersion','SHT_F34_R1_LIKELIHOOD_V1', ...
    'createdAt',datestr(now,31),'observation',observation, ...
    'observationMatrix',observationMatrix,'observationChannels',{outputNames}, ...
    'windowIds',context.steadyData.point_id,'sampleCount',sampleCount, ...
    'anchorTheta',anchorTheta,'anchorPhysicalOutput',base.output, ...
    'Rbase',Rbase,'RbaseJitter',jitter,'covarianceComponents',component, ...
    'inputSensitivity',inputSensitivity,'inputAudit',inputAudit, ...
    'shapeSensitivity',shapeSensitivity,'shapeDifferenceStep',shapeStep, ...
    'modelDiscrepancyStd',modelStd,'inputCrossCovarianceAssumedZero', ...
    options.inputCrossCovarianceAssumedZero, ...
    'measurementBiasDistribution','symmetric_uniform_variance_equivalent', ...
    'conditionalNuisanceMode','low_rank_conditional_gaussian', ...
    'physicsMode','exact_DLL_sufficient_thermal_equilibrium', ...
    'inferenceTestDataUsed',false,'inferenceTruthDataUsed',false, ...
    'physicsContractHash',physicsContractHash, ...
    'preparedContractSha256',preparedContractSha256, ...
    'buildRuntime_s',toc(started));
if ~isempty(support)
    likelihood.physicalSupport=support;
    likelihood.supportQuadratureCount=256;
    likelihood.supportQuadratureSeed=93101;
    likelihood.conditionalNuisanceMode='physical_bounded_conditional_gaussian_QMC';
    likelihood.supportNormalization='conditional_prior_normalized_for_each_explicit_theta';
end
likelihood.contractHash=sht_f33_model_adapt_v2('structHash',struct( ...
    'observation',observation,'Rbase',Rbase,'shapeSensitivity',shapeSensitivity, ...
    'priorIdentity',priorIdentity,'parameter',prior.parameterTable, ...
    'trainingEvidence',context.uqTrainingSourceSha256, ...
    'physicsContractHash',physicsContractHash, ...
    'preparedContractSha256',preparedContractSha256, ...
    'implementationSha256',implementationSha256, ...
    'support',support,'boundedBackendSha256',sht_f33_model_adapt_v2( ...
    'fileHash',which('sht_f34_bounded_condition'))));
likelihood.implementationSha256=implementationSha256;
likelihood.optionsSha256=sht_f33_model_adapt_v2('structHash',options);
paths=sht_f34_contract('paths',options);
likelihood.cacheFile=fullfile(paths.runDir,'f34_exact_physics_cache.mat');
fprintf('似然合同完成：观测%d维，条件形状%d维，构造耗时 %.1f s。\n', ...
    numel(observation),shapeRank,likelihood.buildRuntime_s);
fprintf('各观测/平稳性约束标准差：');fprintf(' %.6g',modelStd);fprintf('\n');
end

function [result,conditional,physical,stats]=local_evaluate( ...
        likelihood,context,prior,thetaMatrix,cache,hit,miss)
thetaMatrix=double(thetaMatrix);
if isvector(thetaMatrix),thetaMatrix=thetaMatrix(:);end
dimension=height(prior.parameterTable);
if size(thetaMatrix,1)~=dimension
    error('SHT:F34Likelihood:Theta','候选参数维数应为%d。',dimension);
end
n=size(thetaMatrix,2);m=numel(likelihood.observation);
physical=zeros(m,n);valid=false(1,n);message=strings(1,n);
missing=false(1,n);keys=cell(1,n);
for i=1:n
    keys{i}=local_cache_key(likelihood.physicsContractHash,thetaMatrix(:,i));
    if isKey(cache,keys{i})
        value=cache(keys{i});physical(:,i)=value.output;
        valid(i)=value.valid;message(i)=value.message;hit=hit+1;
    else
        missing(i)=true;
    end
end
if any(missing)
    index=find(missing);
    % 同一批候选可能因边界裁剪或重采样而完全相同。只对每个精确参数
    % 向量调用一次DLL，再从缓存回填重复列，避免无信息的重复回放。
    pending=containers.Map('KeyType','char','ValueType','double');
    uniqueIndex=zeros(1,numel(index));uniqueCount=0;
    for k=1:numel(index)
        i=index(k);
        if ~isKey(pending,keys{i})
            uniqueCount=uniqueCount+1;uniqueIndex(uniqueCount)=i;
            pending(keys{i})=uniqueCount;
        end
    end
    uniqueIndex=uniqueIndex(1:uniqueCount);
    % miss按实际新增的物理DLL参数点计数；同批重复参数视为缓存复用。
    % 这样缓存审计不再把重采样产生的重复列误报成额外DLL回放。
    miss=miss+uniqueCount;
    hit=hit+(numel(index)-uniqueCount);
    evaluation=sht_f33_model_adapt_v2( ...
        'evaluateCandidates',context,thetaMatrix(:,uniqueIndex));
    for k=1:numel(uniqueIndex)
        i=uniqueIndex(k);candidate=evaluation.candidate(k);
        value=struct('output',nan(m,1),'valid',candidate.valid, ...
            'message',string(candidate.historyReplayError));
        if candidate.valid
            value.output=likelihood.observation+candidate.steadyRaw(:);
        end
        cache(keys{i})=value;
    end
    for k=1:numel(index)
        i=index(k);value=cache(keys{i});physical(:,i)=value.output;
        valid(i)=value.valid;message(i)=value.message;
    end
end

logLikelihood=-Inf(1,n);prediction=nan(m,n);residualMatrix=nan(m,n);
covarianceMatrix=nan(m,m,n);
shapeMean=nan(prior.shape.retainedRank,n);
shapeCovariance=nan(prior.shape.retainedRank,prior.shape.retainedRank,n);
for i=1:n
    if ~valid(i),continue;end
    [meanZ,covZ]=sht_f34_prior('conditionalShape',prior,thetaMatrix(:,i));
    meanValue=physical(:,i)+likelihood.shapeSensitivity*meanZ;
    S=likelihood.Rbase+likelihood.shapeSensitivity*covZ* ...
        likelihood.shapeSensitivity.';
    [S,~]=local_make_spd(S,'candidate covariance');
    residual=likelihood.observation-meanValue;
    [logLikelihood(i),ok]=local_gaussian_logpdf(residual,S);
    if ok&&isfield(likelihood,'physicalSupport')
        % 有界先验必须重新归一化；仅截断后验样本、不修正似然是不一致的。
        [~,~,detail]=local_conditional_posterior(likelihood,prior,thetaMatrix(:,i),physical(:,i));
        priorBox=sht_f34_bounded_condition('evaluate',meanZ,covZ,likelihood.physicalSupport, ...
            likelihood.supportQuadratureCount,likelihood.supportQuadratureSeed);
        logLikelihood(i)=logLikelihood(i)+detail.logProbability-priorBox.logProbability;
        meanValue=physical(:,i)+likelihood.shapeSensitivity*priorBox.mean;
        residual=likelihood.observation-meanValue;
        % 以下协方差仅作输出矩和D方法GN预条件；精确的有界仿射
        % 似然仍用上面的高斯积分乘矩形概率比，不以矩匹配替代。
        S=likelihood.Rbase+likelihood.shapeSensitivity*priorBox.covariance*likelihood.shapeSensitivity.';
        [S,~]=local_make_spd(S,'bounded prior output moment');
    end
    if ~ok
        valid(i)=false;continue;
    end
    prediction(:,i)=meanValue;
    residualMatrix(:,i)=residual;
    covarianceMatrix(:,:,i)=S;
    shapeMean(:,i)=meanZ;shapeCovariance(:,:,i)=covZ;
end
result=struct('logLikelihood',logLikelihood,'prediction',prediction, ...
    'residual',residualMatrix,'covariance',covarianceMatrix, ...
    'valid',valid,'message',message,'theta',thetaMatrix);
conditional=struct('priorMean',shapeMean,'priorCovariance',shapeCovariance);
stats=struct('hit',hit,'miss',miss,'entryCount',cache.Count);
end

function [posteriorMean,posteriorCovariance,detail]=local_conditional_posterior( ...
        likelihood,prior,theta,physicalOutput)
[meanZ,covZ]=sht_f34_prior('conditionalShape',prior,theta);
G=likelihood.shapeSensitivity;
S=likelihood.Rbase+G*covZ*G.';
[S,~]=local_make_spd(S,'conditional covariance');
residual=likelihood.observation-(physicalOutput+G*meanZ);
gain=(covZ*G.')/S;
posteriorMean=meanZ+gain*residual;
posteriorCovariance=covZ-gain*G*covZ;
posteriorCovariance=(posteriorCovariance+posteriorCovariance.')/2;
detail=struct('gaussianMean',posteriorMean,'gaussianCovariance',posteriorCovariance, ...
    'logProbability',0);
if isfield(likelihood,'physicalSupport')
    box=sht_f34_bounded_condition('evaluate',posteriorMean,posteriorCovariance, ...
        likelihood.physicalSupport,likelihood.supportQuadratureCount,likelihood.supportQuadratureSeed);
    posteriorMean=box.mean;posteriorCovariance=box.covariance;
    detail.logProbability=box.logProbability;
    detail.integrationEss=box.integrationEss;
end
end

function result=local_evaluate_physical_shape(context,prior,theta,z)
theta=double(theta);z=double(z);
if isvector(theta),theta=theta(:);end
if isvector(z),z=z(:);end
if size(theta,2)~=size(z,2)||size(theta,1)~=height(prior.parameterTable)|| ...
        size(z,1)~=prior.shape.retainedRank
    error('SHT:F34Likelihood:PhysicalShapeDimension', ...
        '显式参数与条件形状坐标维数不一致。');
end
modelSet=sht_f33_model_adapt_v2('thetaToModels',context,theta);
if isfield(prior,'physicalSupport')
    b=prior.physicalSupport;
    bad=any(z(b.index,:)<b.lower | z(b.index,:)>b.upper,1);
    if any(bad)
        error('SHT:F34Likelihood:PhysicalParameterBounds', ...
            '剩余物理修正量超出上游声明边界，不能送入DLL或裁剪为端点。');
    end
end
nCandidate=size(theta,2);schedules=cell(nCandidate,1);
for i=1:nCandidate
    schedules{i}=sht_f34_prior('applyShape',modelSet.schedules{i},prior,z(:,i));
end
batch=sht_f33_thermal_equilibrium( ...
    'batch',context.thermalSession,schedules,modelSet.recoveries);
nWindow=height(context.steadyData);output=nan(4*nWindow,nCandidate);
valid=false(1,nCandidate);message=strings(1,nCandidate);
for i=1:nCandidate
    valid(i)=batch.candidate(i).valid;
    if valid(i)
        q=batch.candidate(i).prediction;
        if strcmp(context.options.modelRoute,'transient_instant')
            output(:,i)=reshape([q.Pt3,q.Tt45,q.dNp_dt,q.dNg_dt],[],1);
        else,output(:,i)=reshape([q.Np,q.Ng,q.Pt3,q.Tt45],[],1);end
    else
        if isfield(batch.candidate(i),'message')
            message(i)=string(batch.candidate(i).message);
        else
            message(i)="invalid_physical_candidate";
        end
    end
end
result=struct('output',output,'valid',valid,'message',message, ...
    'theta',theta,'shapeCoordinate',z,'testDataUsed',false, ...
    'truthDataUsed',false,'interface','future_method_B_exact_joint_physics');
end

function value=local_physical_direct(context,theta)
evaluation=sht_f33_model_adapt_v2('evaluateCandidates',context,theta);
candidate=evaluation.candidate(1);
value=struct('valid',candidate.valid,'output',nan(4*height(context.steadyData),1), ...
    'message',char(candidate.historyReplayError));
if candidate.valid
    observed=local_observation(context);
    value.output=observed(:)+candidate.steadyRaw(:);
end
end

function observed=local_observation(context)
d=context.steadyData;
if strcmp(context.options.modelRoute,'transient_instant')
    observed=[d.Pt3_mean,d.Tt45_mean,zeros(height(d),2)];
else,observed=[d.Np_mean,d.Ng_mean,d.Pt3_mean,d.Tt45_mean];end
end

function context=local_replace_points(context,points)
context.steadyData=points;
context=local_reopen_session(context);
end

function context=local_reopen_session(context)
context.thermalSession=sht_f33_thermal_equilibrium('open', ...
    context.replayAssets,context.uqThermalBranch,context.steadyData, ...
    context.options.modelRoute);
end

function theta=local_anchor_theta(context)
reference=context.uqReferenceResult;
if isfield(reference,'estimatedTheta')
    % 第二轮3.3正式字段。该结果只用于数值线性化锚点，不进入3.4先验。
    theta=reference.estimatedTheta(:);
elseif isfield(reference,'finalTheta')
    % 兼容早期内部结果字段。
    theta=reference.finalTheta(:);
elseif isfield(reference,'theta')
    theta=reference.theta(:);
else
    theta=zeros(height(context.parameterContract),1);
end
if numel(theta)~=height(context.parameterContract)
    error('SHT:F34Likelihood:AnchorDimension','3.3锚点维数不符合R1合同。');
end
theta=min(max(theta,context.parameterContract.lower_bound), ...
    context.parameterContract.upper_bound);
end

function row=local_sensor_row(sensor,name)
row=find(strcmp(cellstr(string(sensor.name)),name),1);
if isempty(row)
    error('SHT:F34Likelihood:Sensor','测量对象先验缺少%s。',name);
end
end

function [matrix,jitter]=local_make_spd(matrix,label)
matrix=(matrix+matrix.')/2;
scale=max(1,max(abs(diag(matrix))));jitter=0;
for k=0:10
    [~,flag]=chol(matrix+jitter*eye(size(matrix)));
    if flag==0
        matrix=matrix+jitter*eye(size(matrix));return;
    end
    if k==0,jitter=scale*1e-12;else,jitter=jitter*10;end
end
error('SHT:F34Likelihood:Covariance','%s不能形成正定矩阵。',label);
end

function [value,ok]=local_gaussian_logpdf(residual,covariance)
[L,flag]=chol(covariance,'lower');ok=flag==0;
if ~ok,value=-Inf;return;end
z=L\residual;
value=-0.5*(z.'*z+2*sum(log(diag(L)))+numel(residual)*log(2*pi));
ok=isfinite(value);
end

function key=local_cache_key(physicsContractHash,theta)
% 用IEEE-754精确字节表示生成键，避免十进制打印舍入导致两个不同
% 候选参数误命中同一物理缓存。
hex=num2hex(theta(:));
key=[physicsContractHash,'|',reshape(hex.',1,[])];
end

function [cache,hit,miss]=local_load_cache(likelihood,fileName)
cache=containers.Map('KeyType','char','ValueType','any');hit=0;miss=0;
if isempty(fileName)||~isfile(fileName),return;end
loaded=load(fileName,'cacheKeys','cacheValues','cachePhysicsContractHash');
if ~isfield(loaded,'cachePhysicsContractHash')|| ...
        ~strcmp(char(loaded.cachePhysicsContractHash),likelihood.physicsContractHash)
    warning('SHT:F34Likelihood:CacheContract', ...
        '精确物理缓存合同不一致，已忽略旧缓存。');
    return;
end
for i=1:numel(loaded.cacheKeys)
    cache(loaded.cacheKeys{i})=loaded.cacheValues{i};
end
end

function local_save_cache(likelihood,fileName,cache,hit,miss) %#ok<INUSD>
if isempty(fileName),return;end
folder=fileparts(fileName);if ~isfolder(folder),mkdir(folder);end
cacheKeys=cache.keys;cacheValues=cache.values; %#ok<NASGU>
cachePhysicsContractHash=likelihood.physicsContractHash; %#ok<NASGU>
temporary=[tempname(folder),'.mat'];
cleanup=onCleanup(@()local_delete_if_exists(temporary)); %#ok<NASGU>
save(temporary,'cacheKeys','cacheValues','cachePhysicsContractHash','-v7.3');
[ok,message]=movefile(temporary,fileName,'f');
if ~ok,error('SHT:F34Likelihood:CacheSave','精确物理缓存写入失败：%s。',message);end
end

function cache=local_seed_cache(likelihood,theta,physical,cache)
theta=double(theta);physical=double(physical);
if size(theta,2)~=size(physical,2)|| ...
        size(physical,1)~=numel(likelihood.observation)
    error('SHT:F34Likelihood:SeedDimension','精确物理缓存播种维数不一致。');
end
for i=1:size(theta,2)
    if any(~isfinite(theta(:,i)))||any(~isfinite(physical(:,i))),continue;end
    key=local_cache_key(likelihood.physicsContractHash,theta(:,i));
    cache(key)=struct('output',physical(:,i),'valid',true, ...
        'message',"seeded_from_frozen_exact_result");
end
end

function local_delete_if_exists(fileName)
if isfile(fileName),delete(fileName);end
end
