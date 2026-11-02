function result=sht_f34_method_c(prepared,likelihood,methodD,userOptions,control)
%SHT_F34_METHOD_C 3.4方法C：防御性提议驱动的精确DLL SMC。
%
% 目标始终是同一个p(theta)*L(theta)。方法D只构造高效提议，不进入
% 目标定义；防御性先验分量保留远离局部模态和潜在多峰区域的概率质量。
% SMC粒子不是四条独立MCMC链，因此不使用Rhat硬门。

if nargin<4||isempty(userOptions),userOptions=struct();end
if nargin<5,control=[];end
sht_f34_contract('verifyImplementation',prepared.contract);
options=prepared.options;
names=fieldnames(userOptions);
for i=1:numel(names),options.(names{i})=userOptions.(names{i});end
if ~isfield(options,'methodCFinalMoveSweeps'),options.methodCFinalMoveSweeps=4;end
if ~isfield(options,'methodCIndependentMoveFraction'),options.methodCIndependentMoveFraction=0.2;end
validateattributes(options.methodCFinalMoveSweeps,{'numeric'},{'scalar','integer','nonnegative'});
validateattributes(options.methodCIndependentMoveFraction,{'numeric'},{'scalar','>=',0,'<=',1});
if isfield(userOptions,'particleCount')
    particleCount=userOptions.particleCount;
else
    particleCount=options.methodCParticleCount;
end
if isfield(userOptions,'seed'),seed=userOptions.seed;else,seed=options.methodCIndependentSeed;end
if particleCount<32||particleCount~=round(particleCount)
    error('SHT:F34MethodC:ParticleCount','粒子数至少为32且必须为整数。');
end

context=prepared.context;prior=prepared.prior;
if ~isfield(likelihood,'implementationSha256')|| ...
        ~strcmp(likelihood.implementationSha256,sht_f33_model_adapt_v2( ...
        'fileHash',which('sht_f34_likelihood')))|| ...
        ~isfield(likelihood,'optionsSha256')|| ...
        ~strcmp(likelihood.optionsSha256,prepared.contract.optionsSha256)|| ...
        ~isfield(likelihood,'preparedContractSha256')|| ...
        ~strcmp(likelihood.preparedContractSha256,sht_f33_model_adapt_v2( ...
        'structHash',prepared.contract))
    error('SHT:F34MethodC:LikelihoodStale', ...
        '似然与当前程序或冻结配置不一致，请先重跑步骤01。');
end
if ~isempty(methodD)&&isfield(methodD,'likelihoodContractHash')&& ...
        ~strcmp(methodD.likelihoodContractHash,likelihood.contractHash)
    error('SHT:F34MethodC:Lineage', ...
        '方法D与当前似然合同不一致，必须先重新运行方法D。');
end
if ~isempty(methodD)&&(~isfield(methodD,'implementationSha256')|| ...
        ~strcmp(methodD.implementationSha256,sht_f33_model_adapt_v2( ...
        'fileHash',which('sht_f34_method_d'))))
    error('SHT:F34MethodC:MethodDStale', ...
        '方法D结果与当前程序不一致，必须先重新运行步骤02。');
end
cacheFile=local_cache_file(likelihood,prepared);
started=tic;
cacheBefore=sht_f34_likelihood('loadCache',likelihood,cacheFile);
cacheCleanup=onCleanup(@()sht_f34_likelihood( ...
    'saveCache',likelihood,cacheFile)); %#ok<NASGU>
proposal=local_build_proposal(prior,methodD,options);
% 节点先验的联合截断归一化常数未知，不能当作已归一化的提议。
% 全域分量用盒内均匀分布，局部D仅加速，不改变后验概率目标。
if isfield(prior,'nodePrior')
    proposal.defensiveKind='uniform_physical_box';
else
    proposal.defensiveKind='normalized_truncated_prior';
end
stream=RandStream('mt19937ar','Seed',round(seed));
runIdentity=struct('prepared',prepared.contract.optionsSha256, ...
    'likelihood',likelihood.contractHash,'physics',likelihood.physicsContractHash, ...
    'source',sht_f33_model_adapt_v2('fileHash',[mfilename('fullpath'),'.m']), ...
    'priorSource',sht_f33_model_adapt_v2('fileHash',which('sht_f34_prior')), ...
    'proposal',proposal,'options',options,'particleCount',particleCount,'seed',seed, ...
    'release',version('-release'),'architecture',computer('arch'));
checkpointFile=fullfile(prepared.paths.runDir,sprintf('C_state_N%d_seed%d.mat',particleCount,seed));
resumed=false;previousRuntime=0;finalSweep=0;
if isfile(checkpointFile)
    saved=load(checkpointFile,'state');state=saved.state;
    assert(isequaln(state.runIdentity,runIdentity),'SHT:F34C:CheckpointIdentity', ...
        'SMC断点的源码、目标或随机/提议配置改变，请使用新批次，不重签旧断点。');
    theta=state.theta;proposalLabel=state.proposalLabel;physical=state.physical;
    logPrior=state.logPrior;logQ=state.logQ;logLikelihood=state.logLikelihood;
    weights=state.weights;beta=state.beta;logEvidence=state.logEvidence;
    stage=state.stage;ancestor=state.ancestor;stageIndex=state.stageIndex;
    initialValidFraction=state.initialValidFraction;stream.State=state.streamState;
    finalSweep=state.finalSweep;previousRuntime=state.runtime_s;resumed=true;
    assert(isfield(state,'schema')&&strcmp(state.schema,'F34_C_SAFE_LAYER_C4'), ...
        'SHT:F34C:CheckpointSchema','旧SMC状态没有完整数值恢复合同，不得重签使用。');
    sht_f33_model_adapt_v2('checkpointpure',state);
    if ~isempty(control)
        [controlled,hasControlled]=sht_tc24_run_control('load',control, ...
            sprintf('uq_C_N%d_seed%d',particleCount,seed));
        assert(hasControlled&&isequaln(controlled,state), ...
            'SHT:F34C:ControlCheckpoint','SMC物理断点与安全控制断点不一致。');
    end
    if isfield(context,'thermalSession')&&~isempty(state.numericalCache)
        target=context.thermalSession.cache;oldKeys=keys(target);
        if ~isempty(oldKeys),remove(target,oldKeys);end
        restored=sht_f33_model_adapt_v2('checkpointcache','restore',state.numericalCache);
        newKeys=keys(restored);for k=1:numel(newKeys),target(newKeys{k})=restored(newKeys{k});end
    end
else
[theta,proposalLabel]=local_draw_proposal(prior,proposal,particleCount,stream);
[evaluation,~,physical]=sht_f34_likelihood( ...
    'evaluate',likelihood,context,prior,theta);
logPrior=sht_f34_prior('logpdf',prior,theta);
logQ=local_log_proposal(prior,proposal,theta);
logLikelihood=evaluation.logLikelihood;
initialValidFraction=nnz(isfinite(logLikelihood))/particleCount;
minimumValid=0.8*particleCount;
if isfield(prior,'nodePrior'),minimumValid=max(2,0.5*particleCount);end
if nnz(isfinite(logLikelihood))<minimumValid
    error('SHT:F34MethodC:InitialValidity', ...
        '初始粒子只有%d/%d个有效物理解。',nnz(isfinite(logLikelihood)),particleCount);
end

weights=ones(particleCount,1)/particleCount;
beta=0;logEvidence=0;stage=repmat(local_empty_stage(), ...
    options.methodCMaximumStages,1);ancestor=(1:particleCount).';
stageIndex=0;
end
fprintf('\n3.4.7 方法C：%d粒子，seed=%d，全域防御提议比例=%.2f。\n', ...
    particleCount,seed,proposal.priorFraction);
while beta<1-1e-12 && stageIndex<options.methodCMaximumStages
    stageIndex=stageIndex+1;
    score=(logPrior(:)+logLikelihood(:)-logQ(:));
    betaNext=local_next_beta(beta,weights,score, ...
        options.methodCConditionalEssFraction);
    delta=betaNext-beta;
    conditionalEss=local_conditional_ess(weights,score,delta);
    [weights,logIncrement]=local_update_weights(weights,delta*score);
    logEvidence=logEvidence+logIncrement;
    beta=betaNext;ess=1/sum(weights.^2);resampled=false;
    accepted=0;attempted=0;validMove=0;
    % 最后一层也允许重采样和MCMC移动。若beta恰好到1但累计ESS已经很低，
    % 只保留带权退化粒子会降低最终后验代表性；在正式目标上执行同一
    % 不变核不会改变目标分布，证据增量仍使用重采样前权重计算。
    if ess<options.methodCResampleFraction*particleCount
        index=local_systematic_resample(weights,particleCount,stream);
        theta=theta(:,index);logPrior=logPrior(index);logQ=logQ(index);
        logLikelihood=logLikelihood(index);physical=physical(:,index);
        proposalLabel=proposalLabel(index);ancestor=ancestor(index);
        weights=ones(particleCount,1)/particleCount;resampled=true;
        for sweep=1:options.methodCMoveSweeps
            [theta,logPrior,logQ,logLikelihood,physical,move]= ...
                local_move(theta,logPrior,logQ,logLikelihood,physical, ...
                beta,weights,prior,proposal,likelihood,context,stream,options);
            accepted=accepted+move.accepted;attempted=attempted+move.attempted;
            validMove=validMove+move.valid;
        end
    end
    stage(stageIndex)=struct('index',stageIndex,'beta',beta, ...
        'deltaBeta',delta,'conditionalEss',conditionalEss,'ess',ess, ...
        'resampled',resampled, ...
        'moveAccepted',accepted,'moveAttempted',attempted, ...
        'moveValid',validMove,'moveAcceptance',accepted/max(attempted,1), ...
        'moveValidFraction',validMove/max(attempted,1), ...
        'logEvidenceIncrement',logIncrement);
    fprintf(['  C stage %2d: beta=%.6f, CESS=%.1f/%d, ESS=%.1f/%d, ' ...
        'resample=%d, move=%.3f\n'],stageIndex,beta,conditionalEss, ...
        particleCount,ess,particleCount,resampled,accepted/max(attempted,1));
    save_checkpoint();
end
if beta<1-1e-12
    error('SHT:F34MethodC:Temperature','%d层后beta仅达到%.6f。',stageIndex,beta);
end
% beta=1后固定当前目标继续移动，不以重采样后的权重ESS冒充独立样本数。
% 每次完整移动后保存RNG与粒子；中断恢复不会把其他批次样本混入本后验。
while finalSweep<options.methodCFinalMoveSweeps
    finalSweep=finalSweep+1;
    [theta,logPrior,logQ,logLikelihood,physical,move]=local_move( ...
        theta,logPrior,logQ,logLikelihood,physical,beta,weights, ...
        prior,proposal,likelihood,context,stream,options);
    stage(stageIndex).moveAccepted=stage(stageIndex).moveAccepted+move.accepted;
    stage(stageIndex).moveAttempted=stage(stageIndex).moveAttempted+move.attempted;
    stage(stageIndex).moveValid=stage(stageIndex).moveValid+move.valid;
    stage(stageIndex).moveAcceptance=stage(stageIndex).moveAccepted/stage(stageIndex).moveAttempted;
    stage(stageIndex).moveValidFraction=stage(stageIndex).moveValid/stage(stageIndex).moveAttempted;
    fprintf('  C final move %d/%d: acceptance=%.3f, elapsed=%.1fs\n', ...
        finalSweep,options.methodCFinalMoveSweeps,move.accepted/move.attempted,toc(started));
    save_checkpoint();
end
stage=stage(1:stageIndex);

% 显式样本对应的条件形状后验是下一架次递推和完整曲线预测的必需量。
rankValue=prior.shape.retainedRank;
conditionalMean=zeros(rankValue,particleCount);
conditionalCovariance=zeros(rankValue,rankValue,particleCount);
conditionalCovarianceMean=zeros(rankValue);
rawMean=conditionalMean;rawCovariance=conditionalCovariance;
for i=1:particleCount
    [conditionalMean(:,i),covariance,detail]=sht_f34_likelihood( ...
        'conditionalPosterior',likelihood,prior,theta(:,i),physical(:,i));
    rawMean(:,i)=detail.gaussianMean;rawCovariance(:,:,i)=detail.gaussianCovariance;
    conditionalCovariance(:,:,i)=covariance;
    conditionalCovarianceMean=conditionalCovarianceMean+weights(i)*covariance;
end

[meanValue,covariance,interval]=local_weighted_moments(theta,weights);
summary=table(prior.parameterTable.parameter_id,prior.parameterTable.name, ...
    prior.parameterTable.unit,meanValue,sqrt(max(diag(covariance),0)), ...
    interval(:,1),interval(:,2), ...
    'VariableNames',{'parameter_id','name','unit','posterior_mean', ...
    'posterior_std','q025','q975'});
modeDiagnostic=local_marginal_mode_diagnostic(theta,weights,prior.parameterTable);
[uniqueParticle,~,membership]=unique(theta.','rows');
uniqueParticleCount=size(uniqueParticle,1);
supportMass=accumarray(membership,weights(:));
[~,~,lineage]=unique(ancestor);ancestorMass=accumarray(lineage,weights(:));
uniqueAncestorCount=numel(unique(ancestor));
totalAccepted=sum([stage.moveAccepted]);totalAttempted=sum([stage.moveAttempted]);
qualityLevel='DIRECT_DLL_SMC_FINITE_PARTICLE_POSTERIOR';
if uniqueParticleCount<0.5*particleCount
    qualityLevel='GLOBAL_SMC_LOW_DIVERSITY';
end

result=struct('schemaVersion','SHT_F34_METHOD_C_V1', ...
    'createdAt',datestr(now,31),'methodId','C','qualityLevel',qualityLevel, ...
    'samples',theta,'weights',weights,'logLikelihood',logLikelihood(:), ...
    'logPrior',logPrior(:),'logProposal',logQ(:), ...
    'physicalOutput',physical,'proposalLabel',proposalLabel(:), ...
    'ancestor',ancestor,'proposal',proposal,'stage',stage, ...
    'finalBeta',beta,'ess',1/sum(weights.^2),'logEvidence',logEvidence, ...
    'mean',meanValue,'covariance',covariance,'interval95',interval, ...
    'summary',summary,'marginalModeDiagnostic',modeDiagnostic, ...
    'conditionalShapeMean',conditionalMean, ...
    'conditionalShapeCovariance',conditionalCovariance, ...
    'conditionalShapeCovarianceMean',conditionalCovarianceMean, ...
    'priorShape',prior.shape,'runtime_s',toc(started), ...
    'particleCount',particleCount,'seed',seed, ...
    'initialValidFraction',initialValidFraction, ...
    'uniqueParticleCount',uniqueParticleCount, ...
    'uniqueAncestorCount',uniqueAncestorCount, ...
    'uniqueParticleFraction',uniqueParticleCount/particleCount, ...
    'uniqueAncestorFraction',uniqueAncestorCount/particleCount, ...
    'totalMoveAcceptance',totalAccepted/max(totalAttempted,1), ...
    'testDataUsed',false,'truthDataUsed',false, ...
    'targetDefinition','exact_DLL_mean_plus_linearized_conditional_nuisance', ...
    'processCovarianceCalibrated',false, ...
    'processCovarianceStatus', ...
        'ENGINEERING_ASSUMPTION_REQUIRES_FUTURE_LONGITUDINAL_STUDY');
result.likelihoodContractHash=likelihood.contractHash;
if isfield(likelihood,'physicalSupport')
    result.physicalSupport=likelihood.physicalSupport;
    result.conditionalGaussianMean=rawMean;
    result.conditionalGaussianCovariance=rawCovariance;
    result.conditionalQuadratureCount=likelihood.supportQuadratureCount;
    result.conditionalQuadratureSeed=likelihood.supportQuadratureSeed;
    result.targetDefinition='exact_DLL_explicit_plus_bounded_affine_conditional_nuisance';
end
result.physicsContractHash=likelihood.physicsContractHash;
result.implementationSha256=sht_f33_model_adapt_v2( ...
    'fileHash',[mfilename('fullpath'),'.m']);
result.preparedOptionsSha256=prepared.contract.optionsSha256;
result.runIdentity=runIdentity;result.resumedFromCheckpoint=resumed;
result.distinctSupportWeightESS=1/sum(supportMass.^2);
result.ancestorMassESS=1/sum(ancestorMass.^2);
result.finalMoveSweeps=finalSweep;result.totalRuntime_s=previousRuntime+toc(started);
cacheAfter=sht_f34_likelihood('cacheStats');
result.cacheAudit=struct('entryCountBefore',cacheBefore.entryCount, ...
    'entryCountAfter',cacheAfter.entryCount,'hit',cacheAfter.hit, ...
    'miss',cacheAfter.miss);
if isfield(prior,'nodePrior')
    result.logEvidenceInterpretation='unnormalized_common_box_prior_target_not_model_evidence';
    result.parameterization='independent_nodes';
end
fprintf('方法C完成：ESS=%.1f/%d，温度层%d，耗时 %.1f s。\n', ...
    result.ess,particleCount,stageIndex,result.runtime_s);
fprintf('粒子多样性：不同参数点%d/%d，不同祖先%d/%d，移动接受率%.3f。\n', ...
    uniqueParticleCount,particleCount,uniqueAncestorCount,particleCount, ...
    result.totalMoveAcceptance);
    function save_checkpoint()
        numericalCache=[];
        if isfield(context,'thermalSession')
            numericalCache=sht_f33_model_adapt_v2('checkpointcache','save',context.thermalSession.cache);
        end
        state=struct('schema','F34_C_SAFE_LAYER_C4','runIdentity',runIdentity, ...
            'numericalCache',numericalCache,'theta',theta,'proposalLabel',proposalLabel, ...
            'physical',physical,'logPrior',logPrior,'logQ',logQ,'logLikelihood',logLikelihood, ...
            'weights',weights,'beta',beta,'logEvidence',logEvidence,'stage',stage, ...
            'ancestor',ancestor,'stageIndex',stageIndex,'initialValidFraction',initialValidFraction, ...
            'streamState',stream.State,'finalSweep',finalSweep,'runtime_s',previousRuntime+toc(started));
        sht_f34_likelihood('saveCache',likelihood,cacheFile);
        sht_f33_model_adapt_v2('checkpointpure',state);
        temporary=[checkpointFile,'.pending.mat'];save(temporary,'state','-v7.3');
        [ok,message]=movefile(temporary,checkpointFile,'f');assert(ok,message);
        if ~isempty(control)
            sht_tc24_run_control('boundary',control,sprintf('uq_C_N%d_seed%d',particleCount,seed),state);
        end
    end
end

function proposal=local_build_proposal(prior,methodD,options)
lower=prior.lowerBound(:);upper=prior.upperBound(:);range=upper-lower;
if isempty(methodD)
    dimension=numel(lower);
    proposal=struct('schemaVersion','SHT_F34_DEFENSIVE_PROPOSAL_V1', ...
        'priorFraction',1,'localFraction',0,'meanZ',zeros(dimension,1), ...
        'covarianceZ',eye(dimension),'cholZ',eye(dimension),'jitter',0, ...
        'lower',lower,'upper',upper,'localProposalUsed',false);
    return;
end
x=(methodD.map-lower)./range;x=min(max(x,1e-6),1-1e-6);
meanZ=log(x./(1-x));
derivative=1./(range.*x.*(1-x));
covarianceZ=(derivative.*methodD.covariance).*derivative.';
covarianceZ=options.methodCProposalScale^2*covarianceZ;
[covarianceZ,jitter]=local_make_spd(covarianceZ);
proposal=struct('schemaVersion','SHT_F34_DEFENSIVE_PROPOSAL_V1', ...
    'priorFraction',options.methodCDefensivePriorFraction, ...
    'localFraction',1-options.methodCDefensivePriorFraction, ...
    'meanZ',meanZ,'covarianceZ',covarianceZ, ...
    'cholZ',chol(covarianceZ,'lower'),'jitter',jitter, ...
    'lower',lower,'upper',upper,'localProposalUsed',true);
end

function [theta,label]=local_draw_proposal(prior,proposal,n,stream)
% 独立抽取混合分量，使实际采样律严格等于logQ中的混合密度。
% 固定round(p*n)却仍用p作密度权重，在小粒子批次会不一致。
nPrior=nnz(rand(stream,1,n)<proposal.priorFraction);nLocal=n-nPrior;
thetaPrior=zeros(numel(proposal.lower),0);
if nPrior>0
    if strcmp(proposal.defensiveKind,'uniform_physical_box')
        thetaPrior=proposal.lower+(proposal.upper-proposal.lower).*rand(stream,numel(proposal.lower),nPrior);
    else
        thetaPrior=sht_f34_prior('draw',prior,nPrior,randi(stream,2^31-1));
    end
end
z=proposal.meanZ+proposal.cholZ*randn(stream,numel(proposal.meanZ),nLocal);
thetaLocal=local_z_to_theta(z,proposal);
theta=[thetaPrior,thetaLocal];label=[ones(1,nPrior),2*ones(1,nLocal)];
order=randperm(stream,n);theta=theta(:,order);label=label(order);
end

function value=local_log_proposal(prior,proposal,theta)
if strcmp(proposal.defensiveKind,'uniform_physical_box')
    logPrior=repmat(-sum(log(proposal.upper-proposal.lower)),1,size(theta,2));
    logPrior(any(theta<proposal.lower|theta>proposal.upper,1))=-Inf;
else
    logPrior=sht_f34_prior('logpdf',prior,theta);
end
z=local_theta_to_z(theta,proposal);
logLocalZ=local_mvn_logpdf(z,proposal.meanZ,proposal.cholZ);
logJac=local_log_dz_dtheta(theta,proposal);
logLocal=logLocalZ+logJac;
value=local_logsumexp([log(proposal.priorFraction)+logPrior; ...
    log(proposal.localFraction)+logLocal],1);
end

function [theta,logPrior,logQ,logLikelihood,physical,move]=local_move( ...
        theta,logPrior,logQ,logLikelihood,physical,beta,weights, ...
        prior,proposal,likelihood,context,stream,options)
n=size(theta,2);z=local_theta_to_z(theta,proposal);
meanZ=z*weights;centered=z-meanZ;
covariance=(centered.*weights.')*centered.';
% 数值脊项只保证协方差正定，必须跟随当前粒子尺度。不能加入
% 绝对固定的0.05I，否则在窄后验方向会生成多倍标准差的九维跳转。
diagonal=diag(covariance);positive=diagonal(diagonal>0&isfinite(diagonal));
if isempty(positive),reference=1;else,reference=median(positive);end
covariance=covariance+max(1e-12,1e-6*reference)*eye(size(z,1));
[covariance,~]=local_make_spd(covariance);
scale=2.38/sqrt(size(z,1));
trialZ=z+scale*chol(covariance,'lower')*randn(stream,size(z));
trialTheta=local_z_to_theta(trialZ,proposal);
independent=rand(stream,1,n)<options.methodCIndependentMoveFraction;
if any(independent)
    trialTheta(:,independent)=local_draw_proposal(prior,proposal,nnz(independent),stream);
end
[trialEval,~,trialPhysical]=sht_f34_likelihood( ...
    'evaluate',likelihood,context,prior,trialTheta);
trialLogPrior=sht_f34_prior('logpdf',prior,trialTheta);
trialLogQ=local_log_proposal(prior,proposal,trialTheta);
currentTarget=(1-beta)*logQ+beta*(logPrior+logLikelihood)+ ...
    local_log_dtheta_dz(theta,proposal);
trialTarget=(1-beta)*trialLogQ+beta*(trialLogPrior+trialEval.logLikelihood)+ ...
    local_log_dtheta_dz(trialTheta,proposal);
logRatio=trialTarget-currentTarget;
% 独立核在物理参数空间以q提议，必须保留q(current)/q(trial)。
% 与logit对称随机游走核混合不改变同一个桥接目标。
logRatio(independent)=beta*((trialLogPrior(independent)+trialEval.logLikelihood(independent)- ...
    trialLogQ(independent))-(logPrior(independent)+logLikelihood(independent)-logQ(independent)));
accept=log(rand(stream,1,n))<min(0,logRatio) & trialEval.valid;
theta(:,accept)=trialTheta(:,accept);logPrior(accept)=trialLogPrior(accept);
logQ(accept)=trialLogQ(accept);logLikelihood(accept)=trialEval.logLikelihood(accept);
physical(:,accept)=trialPhysical(:,accept);
move=struct('accepted',nnz(accept),'attempted',n,'valid',nnz(trialEval.valid));
end

function betaNext=local_next_beta(beta,weights,score,targetFraction)
if beta>=1,betaNext=1;return;end
target=targetFraction*numel(weights);
if local_conditional_ess(weights,score,1-beta)>=target
    betaNext=1;return;
end
lower=beta;upper=1;
for i=1:50
    middle=(lower+upper)/2;
    if local_conditional_ess(weights,score,middle-beta)<target
        upper=middle;
    else
        lower=middle;
    end
end
betaNext=min(1,max(beta+1e-6,lower));
end

function value=local_conditional_ess(weights,score,delta)
% CESS衡量“本次温度增量”带来的额外退化，而不重复惩罚已经存在的
% 累计权重不均匀。因此 delta=0 时 CESS 必须等于 N，即使当前累计
% ESS 已低于 N。若直接计算更新后的累计 ESS，温度进程会在第一层后停滞。
weights=weights(:)/sum(weights);
increment=delta*score(:);
increment=increment-max(increment);
ratio=exp(increment);
numerator=sum(weights.*ratio);
denominator=sum(weights.*ratio.^2);
value=numel(weights)*numerator^2/max(denominator,realmin);
end

function [weights,logMean]=local_update_weights(weights,logIncrement)
logWeight=log(max(weights(:),realmin))+logIncrement(:);
maximum=max(logWeight);normalizer=maximum+log(sum(exp(logWeight-maximum)));
weights=exp(logWeight-normalizer);
% 该量是相对于当前归一化权重的增量归一化常数。
logMean=normalizer;
end

function index=local_systematic_resample(weights,n,stream)
edge=cumsum(weights(:));edge(end)=1;
u=(rand(stream)/n)+(0:n-1)'/n;index=zeros(n,1);j=1;
for i=1:n
    while u(i)>edge(j),j=j+1;end
    index(i)=j;
end
end

function z=local_theta_to_z(theta,proposal)
x=(theta-proposal.lower)./(proposal.upper-proposal.lower);
x=min(max(x,eps),1-eps);z=log(x./(1-x));
end

function theta=local_z_to_theta(z,proposal)
x=1./(1+exp(-z));x=min(max(x,eps),1-eps);
theta=proposal.lower+(proposal.upper-proposal.lower).*x;
end

function value=local_log_dz_dtheta(theta,proposal)
x=(theta-proposal.lower)./(proposal.upper-proposal.lower);
x=min(max(x,eps),1-eps);
value=-sum(log(proposal.upper-proposal.lower)+log(x)+log(1-x),1);
end

function value=local_log_dtheta_dz(theta,proposal)
value=-local_log_dz_dtheta(theta,proposal);
end

function value=local_mvn_logpdf(z,meanValue,cholValue)
centered=z-meanValue;standard=cholValue\centered;
value=-0.5*(sum(standard.^2,1)+2*sum(log(diag(cholValue)))+ ...
    size(z,1)*log(2*pi));
end

function [meanValue,covariance,interval]=local_weighted_moments(sample,weight)
weight=weight(:)/sum(weight);meanValue=sample*weight;
centered=sample-meanValue;covariance=(centered.*weight.')*centered.';
covariance=(covariance+covariance.')/2;
interval=zeros(size(sample,1),2);
for i=1:size(sample,1)
    interval(i,:)=local_weighted_quantile(sample(i,:),weight,[0.025,0.975]);
end
end

function value=local_weighted_quantile(sample,weight,probability)
[sample,order]=sort(sample(:));weight=weight(order);cdf=cumsum(weight);cdf=cdf/cdf(end);
value=zeros(size(probability));
for i=1:numel(probability)
    index=find(cdf>=probability(i),1);value(i)=sample(index);
end
end

function tableValue=local_marginal_mode_diagnostic(sample,weight,parameter)
n=size(sample,1);modeCount=zeros(n,1);skewnessValue=zeros(n,1);
for i=1:n
    x=sample(i,:);w=weight(:).';mu=sum(w.*x);sigma=sqrt(sum(w.*(x-mu).^2));
    skewnessValue(i)=sum(w.*(x-mu).^3)/max(sigma^3,eps);
    if sigma<=eps,modeCount(i)=1;continue;end
    grid=linspace(min(x),max(x),161);bandwidth=max(0.2*sigma,numel(x)^(-1/5)*sigma);
    density=zeros(size(grid));
    for k=1:numel(x)
        density=density+w(k)*exp(-0.5*((grid-x(k))/bandwidth).^2);
    end
    peak=density(2:end-1)>density(1:end-2)&density(2:end-1)>=density(3:end);
    peak=peak & density(2:end-1)>0.10*max(density);
    modeCount(i)=max(1,nnz(peak));
end
tableValue=table(parameter.parameter_id,modeCount,skewnessValue, ...
    'VariableNames',{'parameter_id','marginal_mode_count','weighted_skewness'});
end

function value=local_logsumexp(x,dimension)
maximum=max(x,[],dimension);
shift=x-maximum;shift(~isfinite(shift))=-Inf;
value=maximum+log(sum(exp(shift),dimension));
value(~isfinite(maximum))=-Inf;
end

function [matrix,jitter]=local_make_spd(matrix)
matrix=(matrix+matrix.')/2;scale=max(1,max(abs(diag(matrix))));jitter=0;
for k=0:12
    [~,flag]=chol(matrix+jitter*eye(size(matrix)));
    if flag==0,matrix=matrix+jitter*eye(size(matrix));return;end
    if k==0,jitter=scale*1e-12;else,jitter=jitter*10;end
end
error('SHT:F34MethodC:SPD','矩阵不能正定化。');
end

function value=local_empty_stage()
value=struct('index',0,'beta',NaN,'deltaBeta',NaN, ...
    'conditionalEss',NaN,'ess',NaN, ...
    'resampled',false,'moveAccepted',0,'moveAttempted',0, ...
    'moveValid',0,'moveAcceptance',NaN,'moveValidFraction',NaN, ...
    'logEvidenceIncrement',NaN);
end


function fileName=local_cache_file(likelihood,prepared)
if isfield(likelihood,'cacheFile')
    fileName=likelihood.cacheFile;
else
    fileName=fullfile(prepared.paths.runDir,'f34_exact_physics_cache.mat');
end
end
