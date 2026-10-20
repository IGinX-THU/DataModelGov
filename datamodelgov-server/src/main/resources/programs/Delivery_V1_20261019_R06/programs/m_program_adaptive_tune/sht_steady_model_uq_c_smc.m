function result = sht_steady_model_uq_c_smc( ...
        contract, prior, likelihood, guidedProposal, userOptions)
%SHT_STEADY_MODEL_UQ_C_SMC 方法C单一总体五核温度SMC。
%
% 全部显式参数始终属于同一个联合后验，只有一套粒子、权重、
% 温度序列和祖先谱系。五个核仅是同一后验上的不同移动方式：
%   1  压气机+燃烧室；
%   2  燃气涡轮；
%   3  涵道+动力涡轮+喷管；
%   4  燃油偏置；
%   5  跨部件全局移动与防御性独立跳转。
%
% 每次扫掠按固定配额将N个粒子分配给五核，总候选数严格为N，
% 而不是每个核各产生N个候选。初始粒子来自防御性混合提议q(z)，
% SMC采用统一几何桥
%   pi_beta(z) proportional to q(z)^(1-beta)*[p(z)L(z)]^beta
% 从q连续推进到当前声明的p(z)L(z)，附加参数矩近似保持不变。
% quality借鉴TC27 R073：CESS增温、按需重采样、条件块参考移动。
% 高斯参考只用于提议，不替换先验/似然，也不假设后验单峰。
% 因此beta=0时全部初始粒子
% 等权，不会在似然尚未起作用时用p/q提前淘汰局部高概率分量。
% pCN核虽对标准正态先验p(z)可逆，但在beta<1时还必须计入q/p修正；
% 防御性独立核则使用完整中间目标与对应分量提议密度计算接受率。

if nargin < 5 || isempty(userOptions), userOptions = struct(); end
options = local_options(contract, userOptions);
qualityMode = strcmp(options.samplerProfile,'quality');
referenceHash = '';
if qualityMode
    referenceHash=sht_steady_model_uq_common('filehash',which('sht_tc27_uq_move_reference'));
end
rng(options.randomSeed, 'twister');
n = options.particleCount;
control=[];controlState=[];controlFound=false;
if isfield(userOptions,'runControl')
    control=userOptions.runControl;controlKey=sprintf('smc_c_%d_%d',n,options.randomSeed);
    proposalIdentity=guidedProposal;
    if isfield(proposalIdentity,'createdAt'),proposalIdentity=rmfield(proposalIdentity,'createdAt');end
    controlSignature=sht_tc24_run_control('hash',struct('contract',contract.contractHash, ...
        'runId',contract.config.runId,'options',options,'proposal',proposalIdentity,'likelihood',likelihood, ...
        'source',sht_steady_model_uq_common('filehash',[mfilename('fullpath'),'.m']), ...
        'moveReferenceHash',referenceHash));
    [controlState,controlFound]=sht_tc24_run_control('load',control,controlKey);resumeRng=rng;
    if controlFound,assert(strcmp(controlState.signature,controlSignature),'TC24:SMC:ResumeMismatch','SMC提议/目标/预算改变。');end
end

if ~isstruct(guidedProposal) || ~isfield(guidedProposal, 'dimension') || ...
        guidedProposal.dimension ~= contract.parameterCount
    error('SHT:SteadyUQC:BadGuidedProposal', ...
        '初始防御混合提议与当前方法C参数合同不一致。');
end

% 先校核已有断点，再进行任何昂贵求值。保存初始精确值，续跑不能
% 为重建初始诊断重复回放N个候选，也不能先回放后才发现身份失配。
checkpointFile='';batchSaved=[];
if contract.modelMode==0&&isempty(control)
    checkpointFile=fullfile(fileparts(contract.cacheFile),sprintf('tc24_c_smc_%s_%d_%d.mat', ...
        contract.contractHash(1:16),n,options.randomSeed));
    signature=struct('contractHash',contract.contractHash,'runId',contract.config.runId,'options',options, ...
        'codeHash',sht_steady_model_uq_common('filehash',[mfilename('fullpath'),'.m']), ...
        'moveReferenceHash',referenceHash,'likelihood',likelihood);
    signature.proposal=guidedProposal;
    if isfield(signature.proposal,'createdAt'),signature.proposal=rmfield(signature.proposal,'createdAt');end
    if isfile(checkpointFile)
        batchSaved=load(checkpointFile,'checkpoint','initialExact');
        assert(isequaln(batchSaved.checkpoint.signature,signature), ...
            'TC24:SMC:ResumeMismatch','SMC断点身份不匹配。');
        assert(isfield(batchSaved,'initialExact'),'TC24:SMC:ResumeMismatch','断点缺少初始精确值，禁止补签旧状态。');
    end
end

% 确定性分量配额降低初始混合比例的有限样本波动，权重中仍
% 使用实际配额密度q(z)，不会把局部参考点偷换成先验。
[theta, latent, initialComponent, initialAudit] = ...
    sht_steady_model_uq_b_proposal('sample', guidedProposal, n, ...
    options.randomSeed+1, 'deterministic_mixture');
logQ = sht_steady_model_uq_b_proposal( ...
    'logdensity', guidedProposal, latent, initialAudit.densityWeight);
logPriorLatent = sht_steady_model_uq_b_proposal('logpriorlatent', latent);
[priorImportanceWeights, initialLogNormalization] = ...
    local_normalize_log_weights(logPriorLatent-logQ);
initialImportanceEss = 1/sum(priorImportanceWeights.^2);

if controlFound
    exact=controlState.variables.initialExact;
elseif ~isempty(batchSaved)
    exact=batchSaved.initialExact;
else
    exact = local_evaluate(contract,theta,options);
end
initialExact=exact;
logLikelihood = sht_steady_model_uq_likelihood( ...
    'evaluate', likelihood, exact.residual, exact.valid);
logPrior = sht_steady_model_uq_sampler('logprior', prior, theta);
minimumValid = max(12, ceil(0.20*n));
if nnz(isfinite(logLikelihood)) < minimumValid
    error('SHT:SteadyUQC:InitialValidity', ...
        '初始粒子只有%d/%d个具有有效精确似然，最低需要%d个。', ...
        nnz(isfinite(logLikelihood)), n, minimumValid);
end

% beta=0的目标正是q(z)，因此正式SMC从等权粒子开始。下面的直接
% p(z)L(z)/q(z)权重只作初始覆盖审计，不参与第一个SMC温度层。
bridgeScore = logPriorLatent+logLikelihood-logQ;
[initialTargetWeights, initialLogEvidenceEstimate] = ...
    local_normalize_log_weights(bridgeScore);
initialTargetImportanceEss = 1/sum(initialTargetWeights.^2);
initialTargetComponentMass = zeros(1,guidedProposal.componentCount);
for component = 1:guidedProposal.componentCount
    initialTargetComponentMass(component) = ...
        sum(initialTargetWeights(initialComponent==component));
end
[~,dominantInitialTargetComponent] = max(initialTargetComponentMass);
[initialBestLogTargetLatent,initialBestIndex] = max( ...
    logPriorLatent+logLikelihood);

weights = ones(1,n)/n;

ancestor = 1:n;
beta = 0;
rho = options.initialPcnScale;
logEvidence = 0;
dllEvaluationCount = exact.dllEvaluationCount;
dllRuntime = exact.dllRuntime_s;
stage = repmat(local_empty_stage(), options.maximumStageCount, 1);
totalAttempted = zeros(1,5);
totalAccepted = zeros(1,5);
totalEsjd = zeros(1,5);
totalGlobalSubAttempted = zeros(1,2);
totalGlobalSubAccepted = zeros(1,2);
particleKernelAttempted=zeros(n,5);
particleMoveCount=zeros(1,n);

% TC24每层保存完整粒子、随机状态及移动统计，续跑不能换目标或配置。
startStage=1;
stateNames={'theta','latent','logLikelihood','logPrior','logPriorLatent','logQ', ...
    'exact','initialExact','weights','ancestor','beta','rho','logEvidence','dllEvaluationCount', ...
    'dllRuntime','stage','totalAttempted','totalAccepted','totalEsjd', ...
    'totalGlobalSubAttempted','totalGlobalSubAccepted','particleKernelAttempted','particleMoveCount'};
if ~isempty(batchSaved)
        cp=batchSaved.checkpoint;
        load(checkpointFile,stateNames{:});
        rng(cp.rngState);startStage=cp.completedStage+1;
end
resumeInStage=false;sweepStart=1;
controlNames=[stateNames,{'initialComponent','initialAudit','initialImportanceEss', ...
    'initialLogNormalization','initialTargetWeights','initialLogEvidenceEstimate', ...
    'initialTargetImportanceEss','initialTargetComponentMass','dominantInitialTargetComponent', ...
    'initialBestLogTargetLatent','initialBestIndex','attempted','accepted','esjdSum', ...
    'globalSubAttempted','globalSubAccepted','deltaBeta','essBeforeResample','essAfterResample','resampled','sweepCount', ...
    'moveReference','conditionalEss','pcnAttempted','pcnAccepted','scaleBefore','stageStartLatent'}];
if controlFound
    % 名单固定在源码内；恢复完整移动轮，而不是只恢复粒子位置。
    for ci=1:numel(controlNames),cn=controlNames{ci};eval([cn,'=controlState.variables.(cn);']);end
    startStage=controlState.stageIndex;sweepStart=controlState.nextSweep;
    resumeInStage=controlState.inStage;rng(resumeRng);
end
stageIndex=startStage-1;
if beta>=1-options.betaTolerance&&~resumeInStage,startStage=options.maximumStageCount+1;end
for stageIteration = startStage:options.maximumStageCount
    stageIndex=stageIteration;
    if ~resumeInStage
    bridgeScore = logPriorLatent+logLikelihood-logQ;
    if qualityMode
        betaNext=local_next_conditional_beta(beta,bridgeScore,weights,options.conditionalEssFraction);
    else
        betaNext = local_next_beta(beta,bridgeScore,weights, ...
            options.targetEssFraction,options.minimumBetaIncrement);
    end
    deltaBeta = betaNext-beta;
    [newWeights, logIncrement] = local_tempered_weights( ...
        weights, bridgeScore, deltaBeta);
    logEvidence = logEvidence+logIncrement;
    essBeforeResample = 1/sum(newWeights.^2);
    conditionalEss=local_conditional_ess(weights,bridgeScore,deltaBeta);
    beta = betaNext;
    moveReference=[];
    if qualityMode
        % 在重采样前保留带权信息；本层内参考分布和尺度不再改变。
        moveReference=sht_tc27_uq_move_reference('build',latent,newWeights,beta,options);
    end
    needResample=beta<1-options.betaTolerance;
    if qualityMode,needResample=essBeforeResample<options.resampleEssFraction*n;end
    if needResample
        index = local_systematic_index(newWeights, n);
        [theta,latent,logLikelihood,logPrior,logPriorLatent,logQ, ...
            exact,ancestor] = ...
            local_resample_state(index,theta,latent,logLikelihood, ...
            logPrior,logPriorLatent,logQ,exact,ancestor);
        particleKernelAttempted=particleKernelAttempted(index,:);
        particleMoveCount=particleMoveCount(index);
        weights = ones(1,n)/n;
        essAfterResample = n;
        resampled = true;
    else
        weights = newWeights;
        essAfterResample = essBeforeResample;
        resampled = false;
    end
    sweepCount=options.moveSweeps;
    if beta>=1-options.betaTolerance,beta=1;sweepCount=options.finalMoveSweeps;end

    attempted = zeros(1,5);
    accepted = zeros(1,5);
    esjdSum = zeros(1,5);
    globalSubAttempted = zeros(1,2);
    globalSubAccepted = zeros(1,2);
    pcnAttempted=zeros(1,5);pcnAccepted=zeros(1,5);
    scaleBefore=rho;stageStartLatent=latent;
    sweepStart=1;
    end
    resumeInStage=false;
    for sweep = sweepStart:sweepCount
        allocation = sht_steady_model_uq_b_proposal( ...
            'allocation', options.kernelWeights, n, ...
            stageIndex+sweep-2);
        if qualityMode
            % 公共旧分配器返回列向量，原circshift未轮换。只在C侧打乱
            % 固定配额标签，不改B及其他消费者，也不依赖粒子的当前状态。
            allocation.component=reshape(allocation.component(randperm(n)),1,[]);
        end
        for kernel=1:5
            particleKernelAttempted(:,kernel)=particleKernelAttempted(:,kernel)+ ...
                (allocation.component(:)==kernel);
        end
        [theta,latent,logLikelihood,logPrior,logPriorLatent,logQ, ...
            exact,move] = ...
            local_five_kernel_sweep(contract,prior,likelihood, ...
            guidedProposal,initialAudit.densityWeight,beta,theta,latent, ...
            logLikelihood,logPrior,logPriorLatent,logQ,exact,options, ...
            rho,allocation,stageIndex+sweep-2,moveReference);
        particleMoveCount=particleMoveCount+move.acceptedMask;
        pcnAttempted=pcnAttempted+move.pcnAttempted;
        pcnAccepted=pcnAccepted+move.pcnAccepted;
        attempted = attempted+move.attempted;
        accepted = accepted+move.accepted;
        esjdSum = esjdSum+move.esjdSum;
        globalSubAttempted = globalSubAttempted+ ...
            move.globalSubAttempted;
        globalSubAccepted = globalSubAccepted+move.globalSubAccepted;
        dllEvaluationCount = dllEvaluationCount+move.dllCount;
        dllRuntime = dllRuntime+move.dllRuntime_s;
        if ~qualityMode
        for kernel = 1:4
            if move.pcnAttempted(kernel) > 0
                rho(kernel) = local_adapt_scale(rho(kernel), ...
                    move.pcnAccepted(kernel)/move.pcnAttempted(kernel), ...
                    kernel,options);
            end
        end
        if move.pcnAttempted(5) > 0
            rho(5) = local_adapt_scale(rho(5), ...
                move.pcnAccepted(5)/move.pcnAttempted(5),5,options);
        end
        end
        if ~isempty(control)
            state=struct('signature',controlSignature,'stageIndex',stageIndex,'nextSweep',sweep+1,'inStage',true,'variables',struct());
            state.progress=struct('phase','SMC_C','stage',stageIndex,'sweep',sweep, ...
                'sweepLimit',sweepCount,'beta',beta,'particleCount',n);
            for ci=1:numel(controlNames),cn=controlNames{ci};state.variables.(cn)=eval(cn);end
            sht_tc24_run_control('boundary',control,controlKey,state);
        end
    end

    if sum(attempted) ~= n*sweepCount
        error('SHT:SteadyUQC:ProposalBudgetViolation', ...
            '本层应产生%d个候选，实际为%d个。', ...
            n*sweepCount, sum(attempted));
    end
    totalAttempted = totalAttempted+attempted;
    totalAccepted = totalAccepted+accepted;
    totalEsjd = totalEsjd+esjdSum;
    totalGlobalSubAttempted = totalGlobalSubAttempted+globalSubAttempted;
    totalGlobalSubAccepted = totalGlobalSubAccepted+globalSubAccepted;
    acceptance = accepted./max(attempted,1);
    normalizedEsjd = esjdSum./max(attempted,1);
    if qualityMode && beta<1-options.betaTolerance
        for kernel=1:5
            if pcnAttempted(kernel)>0
                rho(kernel)=local_adapt_scale(rho(kernel),pcnAccepted(kernel)/pcnAttempted(kernel),kernel,options);
            end
        end
    end
    stage(stageIndex) = struct('index',stageIndex,'beta',beta, ...
        'delta_beta',deltaBeta, ...
        'conditional_ess',conditionalEss,'pcn_scale_used',scaleBefore, ...
        'ancestor_mass_ess',local_ancestor_ess(ancestor,weights), ...
        'reference_displacement',local_reference_displacement(moveReference,latent-stageStartLatent,weights), ...
        'ess_before_resample',essBeforeResample, ...
        'ess_after_resample',essAfterResample,'resampled',resampled, ...
        'pcn_scale_after_adaptation',rho, ...
        'kernel_attempted',attempted,'kernel_accepted',accepted, ...
        'kernel_acceptance',acceptance,'kernel_normalized_esjd', ...
        normalizedEsjd,'global_subkernel_attempted',globalSubAttempted, ...
        'global_subkernel_accepted',globalSubAccepted, ...
        'global_subkernel_acceptance',globalSubAccepted./ ...
        max(globalSubAttempted,1),'valid_fraction', ...
        mean(isfinite(logLikelihood)),'unique_ancestor_count', ...
        numel(unique(ancestor)),'move_sweeps',sweepCount, ...
        'proposal_budget_expected',n*sweepCount, ...
        'proposal_budget_actual',sum(attempted));
    if options.verbose
        fprintf(['  C-SMC stage=%2d beta=%.6f dBeta=%.3g ESS=%.1f ' ...
            'resample=%d ' ...
            'acc=[%.1f %.1f %.1f %.1f %.1f]%% ' ...
            'rho=[%.3f %.3f %.3f %.3f %.3f] DLL=%d\n'], ...
            stageIndex,beta,deltaBeta,essBeforeResample,resampled, ...
            100*acceptance,rho,dllEvaluationCount);
    end
    if ~isempty(checkpointFile)
        checkpoint=struct('signature',signature,'completedStage',stageIndex,'rngState',rng);
        temporary=[checkpointFile,'.partial.mat'];
        save(temporary,stateNames{:},'checkpoint','-v7.3');movefile(temporary,checkpointFile,'f');
    end
    if ~isempty(control)
        state=struct('signature',controlSignature,'stageIndex',stageIndex+1,'nextSweep',1,'inStage',false,'variables',struct());
        state.progress=struct('phase','SMC_C','stage',stageIndex,'sweep',sweepCount, ...
            'sweepLimit',sweepCount,'beta',beta,'particleCount',n);
        for ci=1:numel(controlNames),cn=controlNames{ci};state.variables.(cn)=eval(cn);end
        sht_tc24_run_control('boundary',control,controlKey,state);
    end
    if beta >= 1-options.betaTolerance
        beta = 1;
        break;
    end
end
if beta < 1-options.betaTolerance
    error('SHT:SteadyUQC:MaximumStages', ...
        '方法C在%d层后beta仅到%.6f。', ...
        options.maximumStageCount,beta);
end

stage = stage(1:stageIndex);
weights = weights/sum(weights);
exact.theta = theta;
exact.valid = isfinite(logLikelihood);
exact.insideBounds = true(1,n);
exact.candidateCount = n;
logPrior = sht_steady_model_uq_sampler('logprior',prior,theta);
logTargetLatent = logPriorLatent+logLikelihood;
[finalBestLogTargetLatent,finalBestIndex] = max(logTargetLatent);
finalAncestorComponentMass = zeros(1,guidedProposal.componentCount);
ancestorComponent = initialComponent(ancestor);
for component = 1:guidedProposal.componentCount
    finalAncestorComponentMass(component) = ...
        sum(weights(ancestorComponent==component));
end
dominantInitialTargetComponentRetained = ...
    finalAncestorComponentMass(dominantInitialTargetComponent) > 1e-8;
diagnostic = sht_steady_model_uq_sampler( ...
    'diagnostics',theta,weights,log(max(weights,realmin)),prior);
% 权重启发式不等于相关SMC样本的均值误差，几何簇不等于后验峰。
diagnostic.weightOnlyMeanErrorHeuristic=diagnostic.meanMcse;
diagnostic.meanMcse=nan(size(diagnostic.meanMcse));diagnostic.maximumMeanMcseToSd=NaN;
diagnostic.exploratoryClusterCount=diagnostic.modeCount;
diagnostic.exploratoryClusterIndex=diagnostic.modeIndex;
diagnostic.exploratoryClusterMass=diagnostic.modeMass;
diagnostic.modeCount=NaN;diagnostic.modeIndex=[];diagnostic.modeMass=[];
diagnostic.weightTailHeuristic=diagnostic.paretoKApprox;diagnostic.paretoKApprox=NaN;
diagnostic.batchInterpretation='INDEX_PARTITION_ONLY_NOT_INDEPENDENT_REPLICATES';
diagnostic.monteCarloErrorEstimated=false;diagnostic.multimodalityEstablished=false;
diagnostic.repeatabilityStatus='REQUIRES_INDEPENDENT_SEEDS';
diagnostic.ancestorMassESS=local_ancestor_ess(ancestor,weights);
diagnostic.unmovedParticleFraction=mean(particleMoveCount==0);
resamplingCount = nnz([stage.resampled]);
uniqueAncestorCount = numel(unique(ancestor));
result = struct('schemaVersion','steady_model_uq_method_c_smc_v6_quality', ...
    'moveReferenceHash',referenceHash,'particleKernelAttempted',particleKernelAttempted, ...
    'particleMoveCount',particleMoveCount, ...
    'theta',theta,'latent',latent,'weights',weights, ...
    'logLikelihood',logLikelihood, ...
    'logPrior',logPrior,'logPriorLatent',logPriorLatent,'logQ',logQ, ...
    'logTargetLatent',logTargetLatent,'exact',exact,'stage',stage, ...
    'stageCount',stageIndex,'finalBeta',beta,'finalPcnScale',rho, ...
    'kernelAttempted',totalAttempted,'kernelAccepted',totalAccepted, ...
    'kernelAcceptance',totalAccepted./max(totalAttempted,1), ...
    'kernelNormalizedEsjd',totalEsjd./max(totalAttempted,1), ...
    'kernelNames',{{'compressor_burner','gas_generator_turbine', ...
    'duct_power_turbine_nozzle','fuel_bias','global_cross_component'}}, ...
    'globalSubkernelNames',{{'global_pcn','defensive_independent'}}, ...
    'globalSubkernelAttempted',totalGlobalSubAttempted, ...
    'globalSubkernelAccepted',totalGlobalSubAccepted, ...
    'globalSubkernelAcceptance',totalGlobalSubAccepted./ ...
    max(totalGlobalSubAttempted,1), ...
    'initialImportanceEss',initialImportanceEss, ...
    'initialPriorImportanceWeights',priorImportanceWeights, ...
    'initialTargetImportanceEss',initialTargetImportanceEss, ...
    'initialTargetImportanceWeights',initialTargetWeights, ...
    'initialTargetComponentMass',initialTargetComponentMass, ...
    'dominantInitialTargetComponent',dominantInitialTargetComponent, ...
    'initialBestLogTargetLatent',initialBestLogTargetLatent, ...
    'initialBestLogTargetIndex',initialBestIndex, ...
    'finalBestLogTargetLatent',finalBestLogTargetLatent, ...
    'finalBestLogTargetIndex',finalBestIndex, ...
    'initialToFinalBestLogTargetGap', ...
    initialBestLogTargetLatent-finalBestLogTargetLatent, ...
    'finalAncestorComponentMass',finalAncestorComponentMass, ...
    'dominantInitialTargetComponentRetained', ...
    dominantInitialTargetComponentRetained, ...
    'initialProposalComponent',initialComponent, ...
    'initialProposalAudit',initialAudit, ...
    'initialProposalDensityWeight',initialAudit.densityWeight, ...
    'initialLogPriorNormalizationEstimate',initialLogNormalization, ...
    'initialDirectLogEvidenceEstimate',initialLogEvidenceEstimate, ...
    'diagnostic',diagnostic,'logEvidenceEstimate',logEvidence, ...
    'resamplingCount',resamplingCount, ...
    'uniqueAncestorCount',uniqueAncestorCount, ...
    'uniqueAncestorFraction',uniqueAncestorCount/n, ...
    'ancestorId',ancestor,'dllEvaluationCount',dllEvaluationCount, ...
    'dllRuntime_s',dllRuntime,'populationCount',1, ...
    'singleGlobalWeightVector',true,'postHocPosteriorPoolingUsed',false, ...
    'proposalBudgetPerSweep',n,'options',options);
end

function options = local_options(contract,user)
cfg = contract.config;
options = struct();
profile='legacy_reference';if contract.modelMode==0,profile='quality';end
options.samplerProfile=char(local_option(user,'samplerProfile',profile));
assert(ismember(options.samplerProfile,{'quality','legacy_reference'}),'TC24:C:SamplerProfile','未知采样配置。');
options.conditionalEssFraction=local_option(user,'conditionalEssFraction',.8);
options.resampleEssFraction=local_option(user,'resampleEssFraction',.55);
options.referenceShrinkage=local_option(user,'referenceShrinkage',.15);
options.referenceEigenvalueFloor=local_option(user,'referenceEigenvalueFloor',.05);
options.globalSingularValues=local_option(user,'globalSingularValues',zeros(contract.parameterCount,1));
options.globalSingularValues=options.globalSingularValues(:);
assert(numel(options.globalSingularValues)==contract.parameterCount&& ...
    all(isfinite(options.globalSingularValues))&&all(options.globalSingularValues>=0), ...
    'TC24:C:ReferenceSpectrum','参考奇异值必须覆盖全部参数，弱方向补零。');
validateattributes(options.conditionalEssFraction,{'numeric'},{'scalar','>',0,'<',1});
validateattributes(options.resampleEssFraction,{'numeric'},{'scalar','>',0,'<',1});
validateattributes(options.referenceShrinkage,{'numeric'},{'scalar','>=',0,'<=',1});
validateattributes(options.referenceEigenvalueFloor,{'numeric'},{'scalar','finite','positive'});
options.particleCount = local_option(user,'particleCount',cfg.formalSampleCount);
options.randomSeed = local_option(user,'randomSeed',cfg.randomSeed);
options.targetEssFraction = local_option( ...
    user,'targetEssFraction',cfg.smcFormalTargetEssFraction);
options.minimumBetaIncrement = local_option(user,'minimumBetaIncrement',1e-4);
options.betaTolerance = local_option(user,'betaTolerance',1e-10);
options.maximumStageCount = local_option( ...
    user,'maximumStageCount',cfg.maximumStageCount);
options.moveSweeps = local_option(user,'moveSweeps',cfg.formalMoveSweeps);
options.finalMoveSweeps = local_option( ...
    user,'finalMoveSweeps',cfg.formalFinalMoveSweeps);
options.kernelWeights = local_option(user,'kernelWeights',cfg.kernelWeights);
options.initialPcnScale = local_option( ...
    user,'initialPcnScale',cfg.initialPcnScale);
options.minimumPcnScale = local_option( ...
    user,'minimumPcnScale',cfg.minimumPcnScale);
options.maximumPcnScale = local_option( ...
    user,'maximumPcnScale',cfg.maximumPcnScale);
options.targetAcceptance = local_option( ...
    user,'targetAcceptance',cfg.targetAcceptance);
options.pcnAdaptGain = local_option(user,'pcnAdaptGain',1.0);
options.blockIndex = local_option( ...
    user,'blockIndex',contract.parameterBlockIndex);
options.blockBasis = local_option(user,'blockBasis',[]);
options.blockInformedRank = local_option(user,'blockInformedRank',[]);
options.globalBasis = local_option(user,'globalBasis',[]);
options.globalInformedRank = local_option(user,'globalInformedRank',[]);
options.blockNullScaleMultiplier = local_option(user, ...
    'blockNullScaleMultiplier',cfg.blockNullScaleMultiplier);
options.maximumBlockNullScale = local_option(user, ...
    'maximumBlockNullScale',cfg.maximumBlockNullScale);
options.globalNullScaleMultiplier = local_option(user, ...
    'globalNullScaleMultiplier',cfg.globalNullScaleMultiplier);
options.maximumGlobalNullScale = local_option(user, ...
    'maximumGlobalNullScale',cfg.maximumGlobalNullScale);
options.globalPcnFraction = local_option( ...
    user,'globalPcnFraction',cfg.globalPcnFraction);
options.useCache = logical(local_option(user,'useCache',cfg.useCache));
options.verbose = logical(local_option(user,'verbose',cfg.verbose));

fiveFields = {'kernelWeights','initialPcnScale','minimumPcnScale', ...
    'maximumPcnScale','targetAcceptance'};
for i = 1:numel(fiveFields)
    options.(fiveFields{i}) = options.(fiveFields{i})(:).';
    if numel(options.(fiveFields{i})) ~= 5 || ...
            any(~isfinite(options.(fiveFields{i})))
        error('SHT:SteadyUQC:BadFiveKernelOption', ...
            '%s必须包含5个有限数。',fiveFields{i});
    end
end
assert(all(options.kernelWeights>=0)&&sum(options.kernelWeights)>0, ...
    'TC24:C:KernelWeights','五核配额必须非负且总和为正。');
assert(all(options.minimumPcnScale>0)&&all(options.maximumPcnScale<1)&& ...
    all(options.initialPcnScale>=options.minimumPcnScale)&& ...
    all(options.initialPcnScale<=options.maximumPcnScale), ...
    'TC24:C:PcnScale','移动尺度必须满足0<最小值<=初值<=最大值<1。');
validateattributes(options.moveSweeps,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(options.finalMoveSweeps,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(options.maximumStageCount,{'numeric'},{'scalar','integer','positive','finite'});
options.kernelWeights = options.kernelWeights/sum(options.kernelWeights);
if options.particleCount < 24 || options.particleCount ~= floor(options.particleCount)
    error('SHT:SteadyUQC:BadParticleCount', '粒子数必须为不小于24的整数。');
end
if options.targetEssFraction <= 0 || options.targetEssFraction >= 1 || ...
        options.globalPcnFraction <= 0 || options.globalPcnFraction >= 1
    error('SHT:SteadyUQC:BadFractionOption', ...
        'ESS目标与全局pCN比例必须位于(0,1)。');
end
if numel(options.blockIndex) ~= 5 || ...
        ~isequal(sort(options.blockIndex{5}(:)),(1:contract.parameterCount).')
    error('SHT:SteadyUQC:BadBlockIndex', ...
        '方法C必须包含四个物理块和一个全维跨块核。');
end
if numel(options.blockBasis) ~= 4 || numel(options.blockInformedRank) ~= 4
    error('SHT:SteadyUQC:MissingBlockGeometry', ...
        '方法C需要四个物理块的局部SVD几何。');
end
for k = 1:4
    dimension = numel(options.blockIndex{k});
    basis = options.blockBasis{k};
    if ~isequal(size(basis),[dimension,dimension]) || ...
            norm(basis.'*basis-eye(dimension),'fro') > 1e-8 || ...
            options.blockInformedRank(k) < 0 || ...
            options.blockInformedRank(k) > dimension
        error('SHT:SteadyUQC:BadBlockGeometry', ...
            '物理块%d的SVD基或信息秩无效。',k);
    end
end
if ~isequal(size(options.globalBasis), ...
        [contract.parameterCount,contract.parameterCount]) || ...
        norm(options.globalBasis.'*options.globalBasis- ...
        eye(contract.parameterCount),'fro') > 1e-8 || ...
        options.globalInformedRank < 0 || ...
        options.globalInformedRank > contract.parameterCount
    error('SHT:SteadyUQC:BadGlobalGeometry', ...
        '跨部件全局SVD基或信息秩无效。');
end
end

function [theta,latent,logLikelihood,logPrior,logPriorLatent,logQ, ...
        exact,move] = local_five_kernel_sweep( ...
        contract,prior,likelihood,guidedProposal,proposalDensityWeight, ...
        beta,theta,latent,logLikelihood,logPrior,logPriorLatent,logQ, ...
        exact,options,rho,allocation,phase,moveReference)
% 先构造全部N个候选，再合并为一次DLL批量回放。每个粒子在一次扫掠中
% 只由一个核更新，因此合批不会改变任一核的提议密度或接受概率。
n = size(theta,2);
proposalLatent = latent;
proposalKind = ones(1,n); % 1=pCN，2=防御性独立MH
independentComponent = zeros(1,n);

for kernel = 1:4
    particleIndex = find(allocation.component==kernel);
    if isempty(particleIndex), continue; end
    index = options.blockIndex{kernel};
    if ~isempty(moveReference)
        proposalLatent(:,particleIndex)=sht_tc27_uq_move_reference( ...
            'propose',moveReference,latent(:,particleIndex),kernel,rho(kernel));
    else
    proposalLatent(index,particleIndex) = local_operator_pcn( ...
        latent(index,particleIndex),options.blockBasis{kernel}, ...
        options.blockInformedRank(kernel),rho(kernel), ...
        options.blockNullScaleMultiplier(kernel), ...
        options.maximumBlockNullScale(kernel), ...
        options.minimumPcnScale(kernel));
    end
end

% 第5核配额内部由全局pCN与防御性独立MH共享，二者之和仍等于第5核配额。
globalIndex = find(allocation.component==5);
subAllocation = local_global_allocation( ...
    numel(globalIndex),options.globalPcnFraction,phase);
globalPcnIndex = globalIndex(subAllocation.component==1);
independentIndex = globalIndex(subAllocation.component==2);
if ~isempty(globalPcnIndex)
    if ~isempty(moveReference)
        proposalLatent(:,globalPcnIndex)=sht_tc27_uq_move_reference( ...
            'propose',moveReference,latent(:,globalPcnIndex),5,rho(5));
    else
    proposalLatent(:,globalPcnIndex) = local_operator_pcn( ...
        latent(:,globalPcnIndex),options.globalBasis, ...
        options.globalInformedRank,rho(5), ...
        options.globalNullScaleMultiplier,options.maximumGlobalNullScale, ...
        options.minimumPcnScale(5));
    end
end
if ~isempty(independentIndex)
    independentComponent(independentIndex) = ...
        local_independent_component_labels(guidedProposal, ...
        numel(independentIndex),phase);
    proposalKind(independentIndex) = 2;
    for component = 1:guidedProposal.componentCount
        targetIndex = independentIndex( ...
            independentComponent(independentIndex)==component);
        if isempty(targetIndex), continue; end
        [~,componentLatent] = sht_steady_model_uq_b_proposal( ...
            'samplecomponent',guidedProposal,component, ...
            numel(targetIndex),[],false);
        proposalLatent(:,targetIndex) = componentLatent;
    end
end

proposalTheta = sht_steady_model_uq_sampler( ...
    'latenttotheta',prior,proposalLatent);
proposalExact = local_evaluate(contract,proposalTheta,options);
proposalLogLikelihood = sht_steady_model_uq_likelihood( ...
    'evaluate',likelihood,proposalExact.residual,proposalExact.valid);
proposalLogPrior = sht_steady_model_uq_sampler( ...
    'logprior',prior,proposalTheta);
proposalLogPriorLatent = sht_steady_model_uq_b_proposal( ...
    'logpriorlatent',proposalLatent);
proposalLogQMixture = sht_steady_model_uq_b_proposal( ...
    'logdensity',guidedProposal,proposalLatent,proposalDensityWeight);

% pCN对标准正态先验p(z)可逆。中间目标还含有q(z)^(1-beta)，
% 因此接受率必须补入(1-beta)*Delta[log q-log p]；到beta=1时
% 自动退化为通常的完整似然比。
logAlpha = (1-beta)*( ...
    (proposalLogQMixture-logQ) - ...
    (proposalLogPriorLatent-logPriorLatent)) + ...
    beta*(proposalLogLikelihood-logLikelihood);
if ~isempty(moveReference)
    % 提议对本层参考g可逆，而非对先验可逆；必须保留g(z)/g(z')。
    logAlpha=(1-beta)*(proposalLogQMixture-logQ)+ ...
        beta*(proposalLogPriorLatent-logPriorLatent+proposalLogLikelihood-logLikelihood)+ ...
        sht_tc27_uq_move_reference('logdensity',moveReference,latent)- ...
        sht_tc27_uq_move_reference('logdensity',moveReference,proposalLatent);
end
for component = 1:guidedProposal.componentCount
    targetIndex = find(proposalKind==2 & independentComponent==component);
    if isempty(targetIndex), continue; end
    proposalComponentLogQ = sht_steady_model_uq_b_proposal( ...
        'logcomponentdensity',guidedProposal,component, ...
        proposalLatent(:,targetIndex));
    currentComponentLogQ = sht_steady_model_uq_b_proposal( ...
        'logcomponentdensity',guidedProposal,component, ...
        latent(:,targetIndex));
    proposalLogTarget = (1-beta)*proposalLogQMixture(targetIndex) + ...
        beta*(proposalLogPriorLatent(targetIndex) + ...
        proposalLogLikelihood(targetIndex));
    currentLogTarget = (1-beta)*logQ(targetIndex) + ...
        beta*(logPriorLatent(targetIndex)+logLikelihood(targetIndex));
    logAlpha(targetIndex) = proposalLogTarget-currentLogTarget + ...
        currentComponentLogQ-proposalComponentLogQ;
end
accept = log(rand(1,n)) < min(0,logAlpha);

move = local_empty_move();
move.acceptedMask=double(accept);
for kernel = 1:5
    particleIndex = find(allocation.component==kernel);
    acceptedIndex = particleIndex(accept(particleIndex));
    move.attempted(kernel) = numel(particleIndex);
    move.accepted(kernel) = numel(acceptedIndex);
    if kernel <= 4
        jumpIndex = options.blockIndex{kernel};
    else
        jumpIndex = (1:contract.parameterCount).';
    end
    jump = proposalLatent(jumpIndex,acceptedIndex)- ...
        latent(jumpIndex,acceptedIndex);
    move.esjdSum(kernel) = sum(jump(:).^2)/max(numel(jumpIndex),1);
end
move.pcnAttempted(1:4) = move.attempted(1:4);
move.pcnAccepted(1:4) = move.accepted(1:4);
move.pcnAttempted(5) = numel(globalPcnIndex);
move.pcnAccepted(5) = nnz(accept(globalPcnIndex));
move.globalSubAttempted = [numel(globalPcnIndex),numel(independentIndex)];
move.globalSubAccepted = [nnz(accept(globalPcnIndex)), ...
    nnz(accept(independentIndex))];
move.dllCount = proposalExact.dllEvaluationCount;
move.dllRuntime_s = proposalExact.dllRuntime_s;

acceptedIndex = find(accept);
theta(:,acceptedIndex) = proposalTheta(:,acceptedIndex);
latent(:,acceptedIndex) = proposalLatent(:,acceptedIndex);
logLikelihood(acceptedIndex) = proposalLogLikelihood(acceptedIndex);
logPrior(acceptedIndex) = proposalLogPrior(acceptedIndex);
logPriorLatent(acceptedIndex) = proposalLogPriorLatent(acceptedIndex);
logQ(acceptedIndex) = proposalLogQMixture(acceptedIndex);
exact.residual(:,acceptedIndex) = proposalExact.residual(:,acceptedIndex);
exact.valid(acceptedIndex) = proposalExact.valid(acceptedIndex);
end

function proposal = local_operator_pcn( ...
        current,basis,informedRank,rho,nullMultiplier,maximumNull,minimumScale)
coordinate = basis.'*current;
scale = rho*ones(size(coordinate,1),1);
if informedRank < numel(scale)
    scale(informedRank+1:end) = min(maximumNull, nullMultiplier*rho);
end
scale = min(max(scale,minimumScale),maximumNull);
proposalCoordinate = sqrt(1-scale.^2).*coordinate + ...
    scale.*randn(size(coordinate));
proposal = basis*proposalCoordinate;
end

function labels = local_independent_component_labels(proposal,count,phase)
if count < proposal.componentCount
    labels = ones(1,count);
else
    allocation = sht_steady_model_uq_b_proposal('allocation', ...
        [proposal.priorWeight,proposal.localWeight],count,phase);
    labels = allocation.component;
end
end

function allocation = local_global_allocation(count,pcnFraction,phase)
if count <= 0
    allocation = struct('component',zeros(1,0));
elseif count == 1
    allocation = struct('component',1);
else
    allocation = sht_steady_model_uq_b_proposal( ...
        'allocation',[pcnFraction,1-pcnFraction],count,phase);
end
end

function move = local_empty_move()
move = struct('attempted',zeros(1,5),'accepted',zeros(1,5), ...
    'esjdSum',zeros(1,5),'pcnAttempted',zeros(1,5), ...
    'pcnAccepted',zeros(1,5),'globalSubAttempted',zeros(1,2), ...
    'globalSubAccepted',zeros(1,2),'dllCount',0,'dllRuntime_s',0);
end

function value = local_adapt_scale(value,acceptance,kernel,options)
value = value*exp(options.pcnAdaptGain* ...
    (acceptance-options.targetAcceptance(kernel)));
value = min(options.maximumPcnScale(kernel), ...
    max(options.minimumPcnScale(kernel),value));
end

function betaNext = local_next_beta( ...
        beta,bridgeScore,weights,targetFraction,minIncrement)
if beta >= 1, betaNext = 1; return; end
target = min(targetFraction*numel(weights),0.95/sum(weights.^2));
if local_incremental_ess(weights,bridgeScore,1-beta) >= target
    betaNext = 1;
    return;
end
lower = beta;
upper = 1;
for i = 1:60
    middle = 0.5*(lower+upper);
    if local_incremental_ess(weights,bridgeScore,middle-beta) < target
        upper = middle;
    else
        lower = middle;
    end
end
betaNext = max(lower,min(1,beta+minIncrement));
end

function value = local_incremental_ess(weights,bridgeScore,deltaBeta)
[newWeights,~] = local_tempered_weights(weights,bridgeScore,deltaBeta);
value = 1/sum(newWeights.^2);
end

function [weights,logIncrement] = local_tempered_weights( ...
        weights,bridgeScore,deltaBeta)
% 零权重保持为零；不能因数值下限让已淘汰的无效粒子重新参与加权。
logValue = -inf(size(weights));
keep=weights>0&isfinite(bridgeScore);
logValue(keep) = log(weights(keep))+deltaBeta*bridgeScore(keep);
maximum = max(logValue);
if ~isfinite(maximum)
    error('SHT:SteadyUQC:AllWeightsInvalid', ...
        '当前升温后全部粒子权重无效。');
end
scaled = exp(logValue-maximum);
weights = scaled/sum(scaled);
logIncrement = maximum+log(sum(scaled));
end

function index = local_systematic_index(weights,count)
weights = weights(:)/sum(weights);
cumulative = cumsum(weights);
cumulative(end) = 1;
position = ((0:count-1).'+rand)/count;
index = zeros(count,1);
j = 1;
for i = 1:count
    while position(i) > cumulative(j), j = j+1; end
    index(i) = j;
end
index = index.';
end

function [theta,latent,logLikelihood,logPrior,logPriorLatent,logQ, ...
        exact,ancestor] = local_resample_state( ...
        index,theta,latent,logLikelihood,logPrior,logPriorLatent,logQ, ...
        exact,ancestor)
theta = theta(:,index);
latent = latent(:,index);
logLikelihood = logLikelihood(index);
logPrior = logPrior(index);
logPriorLatent = logPriorLatent(index);
logQ = logQ(index);
exact.residual = exact.residual(:,index);
exact.valid = exact.valid(index);
ancestor = ancestor(index);
end

function [weights,logMeanWeight] = local_normalize_log_weights(logWeight)
maximum = max(logWeight);
raw = exp(logWeight-maximum);
weights = raw/sum(raw);
logMeanWeight = maximum+log(sum(raw))-log(numel(raw));
end

function record = local_empty_stage()
record = struct('index',0,'beta',NaN,'delta_beta',NaN, ...
    'conditional_ess',NaN,'pcn_scale_used',nan(1,5), ...
    'ancestor_mass_ess',NaN,'reference_displacement',NaN, ...
    'ess_before_resample',NaN,'ess_after_resample',NaN, ...
    'resampled',false, ...
    'pcn_scale_after_adaptation',nan(1,5), ...
    'kernel_attempted',zeros(1,5),'kernel_accepted',zeros(1,5), ...
    'kernel_acceptance',nan(1,5),'kernel_normalized_esjd',nan(1,5), ...
    'global_subkernel_attempted',zeros(1,2), ...
    'global_subkernel_accepted',zeros(1,2), ...
    'global_subkernel_acceptance',nan(1,2), ...
    'valid_fraction',NaN,'unique_ancestor_count',0,'move_sweeps',0, ...
    'proposal_budget_expected',0,'proposal_budget_actual',0);
end

function out=local_evaluate(contract,theta,options)
% 解析短测显式注入回调；正式入口仍使用唯一TC24物理求值器。
if isfield(contract,'evaluateFunction')
    out=contract.evaluateFunction(theta);
else
    out=sht_steady_model_uq_c_common('evaluate',contract,theta, ...
        contract.trainingData,struct('useCache',options.useCache));
end
end

function next=local_next_conditional_beta(beta,score,weights,fraction)
target=fraction*numel(weights);
if local_conditional_ess(weights,score,1-beta)>=target,next=1;return;end
lo=beta;hi=1;
for k=1:60
    mid=(lo+hi)/2;
    if local_conditional_ess(weights,score,mid-beta)<target,hi=mid;else,lo=mid;end
end
if lo<=beta
    assert(beta==0,'TC24:C:TemperingStalled','CESS增温停滞，请检查目标及有限似然。');
    next=eps;
else
    next=lo;
end
end

function value=local_conditional_ess(weights,score,increment)
if increment==0,value=numel(weights);return;end
keep=weights>0&isfinite(score);
if ~any(keep),value=0;return;end
a=increment*score(keep);a=a-max(a);v=exp(a);w=weights(keep);
value=numel(weights)*sum(w.*v)^2/sum(w.*v.^2);
end

function value=local_ancestor_ess(ancestor,weights)
[~,~,group]=unique(ancestor);mass=accumarray(group(:),weights(:));
value=1/sum(mass.^2);
end

function value=local_reference_displacement(ref,delta,weights)
value=NaN;
if ~isempty(ref),q=ref.cholLower\delta;value=sum(weights.*sum(q.^2,1))/size(q,1);end
end

function value = local_option(options,name,defaultValue)
if isstruct(options) && isfield(options,name) && ~isempty(options.(name))
    value = options.(name);
else
    value = defaultValue;
end
end
