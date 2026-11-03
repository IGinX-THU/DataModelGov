function result = sht_tc27_uq_smc( ...
        contract, prior, likelihood, guidedProposal, userOptions)
%SHT_TC27_UQ_SMC 保留TC24-R051五核SMC数学内核，使用TC27求值回调。
% 源sht_steady_model_uq_c_smc.m只读。TC27增加谱预条件提议和逐扫掠
% 随机配额轮换；桥分布及MH比不变，不运行TC24或B方法任务。
% L由回调定义：稳态为直接DLL有界边缘似然；联合历程为代理似然。
% 内部exact仅表示当前回调结果，不自动代表DLL或完整非线性边缘化。
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
% 从q连续推进到本回调定义的目标p(z)L(z)。因此beta=0时全部初始粒子
% 等权，不会在似然尚未起作用时用p/q提前淘汰局部高概率分量。
% pCN核虽对标准正态先验p(z)可逆，但在beta<1时还必须计入q/p修正；
% 防御性独立核则使用完整中间目标与对应分量提议密度计算接受率。

if nargin < 5 || isempty(userOptions), userOptions = struct(); end
control=[];if isfield(userOptions,'runControl'),control=userOptions.runControl;end
options = local_options(contract, userOptions);
qualityMode=strcmp(options.samplerProfile,'quality');
rng(options.randomSeed, 'twister');
n = options.particleCount;

if ~isstruct(guidedProposal) || ~isfield(guidedProposal, 'dimension') || ...
        guidedProposal.dimension ~= contract.parameterCount
    error('SHT:SteadyUQC:BadGuidedProposal', ...
        '初始防御混合提议与当前方法C参数合同不一致。');
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

exact = contract.evaluateFunction(theta);
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

% TC24每层保存完整粒子、随机状态及移动统计，续跑不能换目标或配置。
startStage=1;checkpointFile='';
stateNames={'theta','latent','logLikelihood','logPrior','logPriorLatent','logQ', ...
    'exact','weights','ancestor','beta','rho','logEvidence','dllEvaluationCount', ...
    'dllRuntime','stage','totalAttempted','totalAccepted','totalEsjd', ...
    'totalGlobalSubAttempted','totalGlobalSubAccepted','particleKernelAttempted'};
if contract.modelMode==0
    checkpointFile=fullfile(fileparts(contract.cacheFile),sprintf('tc27_c_smc_%s_%d_%d.mat', ...
        contract.contractHash(1:16),n,options.randomSeed));
    signature=struct('contractHash',contract.contractHash,'options',options, ...
        'proposalHash',sht_tc27_uq_proposal_identity(guidedProposal), ...
        'matlabRelease',version('-release'),'architecture',computer('arch'), ...
        'codeHash',sht_steady_model_uq_common('filehash',[mfilename('fullpath'),'.m']), ...
        'moveReferenceHash',sht_tc27_file_identity(fullfile(fileparts(mfilename('fullpath')), ...
        'sht_tc27_uq_move_reference.m')));
    if isfile(checkpointFile)
        saved=load(checkpointFile,'checkpoint');cp=saved.checkpoint;
        assert(isequaln(cp.signature,signature),'TC24:SMC:ResumeMismatch','SMC断点身份不匹配。');
        load(checkpointFile,stateNames{:});
        rng(cp.rngState);startStage=cp.completedStage+1;
    end
end
stageIndex=startStage-1;
% 完整末层断点恢复后直接整理结果，不能再执行空for循环把stageIndex
% 覆盖成空数组。未完成层仍按原随机状态重走，DLL结果由精确缓存复用。
if beta<1-options.betaTolerance
for stageIndex = startStage:options.maximumStageCount
    bridgeScore = logPriorLatent+logLikelihood-logQ;
    if qualityMode
        % CESS衡量本次增温损失，ESS控制是否重采样。二者不可混为一谈。
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
        % 必须先用增温后的加权粒子估计几何，再重采样；本层移动中不刷新。
        % 初始桥接q始终独立冻结，不能用此参考替换q后继续沿用原权重。
        moveReference=sht_tc27_uq_move_reference('build',latent,newWeights,beta,options);
    end

    % 标准resample-move SMC：中间温度层按目标ESS重采样并精确移动；
    % beta=1保留最终重要性权重，再用额外移动扫掠提高数值粒子多样性。
    needResample=beta<1-options.betaTolerance;
    if qualityMode,needResample=essBeforeResample<options.resampleEssFraction*n;end
    if needResample
        index = local_systematic_index(newWeights, n);
        [theta,latent,logLikelihood,logPrior,logPriorLatent,logQ, ...
            exact,ancestor] = ...
            local_resample_state(index,theta,latent,logLikelihood, ...
            logPrior,logPriorLatent,logQ,exact,ancestor);
        weights = ones(1,n)/n;
        particleKernelAttempted=particleKernelAttempted(index,:);
        essAfterResample = n;
        resampled = true;
    else
        weights = newWeights;
        essAfterResample = essBeforeResample;
        resampled = false;
    end
    sweepCount=options.moveSweeps;
    if beta>=1-options.betaTolerance,beta=1;sweepCount=options.finalMoveSweeps;end
    layerStartLatent=latent;layerStartTheta=theta;
    frozenRho=rho;

    attempted = zeros(1,5);
    accepted = zeros(1,5);
    esjdSum = zeros(1,5);
    globalSubAttempted = zeros(1,2);
    globalSubAccepted = zeros(1,2);
    for sweep = 1:sweepCount
        allocation = sht_steady_model_uq_b_proposal( ...
            'allocation', options.kernelWeights, n, ...
            stageIndex+sweep-2);
        % 固定配额但随机分配粒子。不能依赖历史分配器的circshift：
        % 其标签可能为列向量，沿第2维轮换会成为空操作，导致同一粒子
        % 永远只更新同一物理块。随机置换与状态无关，保持各核不变分布。
        allocation.component=reshape(allocation.component(randperm(n)),1,[]);
        for kernel=1:5
            selected=allocation.component==kernel;
            particleKernelAttempted(selected,kernel)=particleKernelAttempted(selected,kernel)+1;
        end
        [theta,latent,logLikelihood,logPrior,logPriorLatent,logQ, ...
            exact,move] = ...
            local_five_kernel_sweep(contract,prior,likelihood, ...
            guidedProposal,initialAudit.densityWeight,beta,theta,latent, ...
            logLikelihood,logPrior,logPriorLatent,logQ,exact,options, ...
            rho,allocation,stageIndex+sweep-2,moveReference);
        attempted = attempted+move.attempted;
        accepted = accepted+move.accepted;
        esjdSum = esjdSum+move.esjdSum;
        globalSubAttempted = globalSubAttempted+ ...
            move.globalSubAttempted;
        globalSubAccepted = globalSubAccepted+move.globalSubAccepted;
        dllEvaluationCount = dllEvaluationCount+move.dllCount;
        dllRuntime = dllRuntime+move.dllRuntime_s;
        for kernel = 1:4
            if move.pcnAttempted(kernel) > 0 && ...
                    ~qualityMode&&(beta<1-options.betaTolerance||options.adaptFinalScales)
                rho(kernel) = local_adapt_scale(rho(kernel), ...
                    move.pcnAccepted(kernel)/move.pcnAttempted(kernel), ...
                    kernel,options);
            end
        end
        if move.pcnAttempted(5) > 0 && ...
                ~qualityMode&&(beta<1-options.betaTolerance||options.adaptFinalScales)
            rho(5) = local_adapt_scale(rho(5), ...
                move.pcnAccepted(5)/move.pcnAttempted(5),5,options);
        end
        if options.verbose && move.dllCount>0
            fprintf('  C-SMC层%d移动%d/%d：新DLL候选%d组，本扫掠%.1fs，接受%d/%d。\n', ...
                stageIndex,sweep,sweepCount,move.dllCount,move.dllRuntime_s,sum(move.accepted),n);
        end
    end
    % quality核的尺度仅在两层之间调整；不依据本层轨迹提前终止移动，
    % 避免状态相关的“达到稳定就停”改变末层抽样分布。
    if qualityMode && beta<1-options.betaTolerance
        for k=1:5
            rho(k)=local_adapt_scale(frozenRho(k),accepted(k)/max(attempted(k),1),k,options);
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
    stage(stageIndex) = struct('index',stageIndex,'beta',beta, ...
        'delta_beta',deltaBeta, ...
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
        'proposal_budget_actual',sum(attempted), ...
        'conditional_ess',conditionalEss,'weight_ess',1/sum(weights.^2), ...
        'ancestor_mass_ess',local_ancestor_ess(ancestor,weights), ...
        'unchanged_particle_fraction',mean(all(theta==layerStartTheta,1)), ...
        'layer_mean_square_displacement',sum(weights.*sum((latent-layerStartLatent).^2,1))/size(latent,1), ...
        'layer_reference_displacement',local_reference_displacement(moveReference,latent-layerStartLatent,weights), ...
        'reference_shrinkage',local_reference_field(moveReference,'shrinkage'), ...
        'reference_relative_minimum_eigenvalue',local_reference_field(moveReference,'relativeMinimumEigenvalue'));
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
        assert(~isempty(checkpointFile),'TC27:UQ:SMCCheckpoint', ...
            '外部停止只允许在完整SMC温度层检查点落盘之后。');
        sht_tc24_run_control('boundary',control,'CStage', ...
            struct('contractHash',contract.contractHash, ...
            'checkpointFile',checkpointFile,'checkpointSHA256', ...
            sht_tc27_file_identity(checkpointFile), ...
            'progress',struct('stage','C_temperature_layer', ...
            'completedStage',stageIndex,'beta',beta,'particleCount',n)));
    end
    if beta >= 1-options.betaTolerance
        beta = 1;
        break;
    end
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
% 共享诊断中的sqrt(variance/weightESS)忽略了重采样血缘与MCMC相关性。
% 保留该数值的明确启发式名称，但不再把它作为MCSE或后验多峰证据。
if isfield(diagnostic,'meanMcse')
    diagnostic.weightOnlyMeanErrorHeuristic=diagnostic.meanMcse;
    diagnostic.meanMcse=nan(size(diagnostic.meanMcse));
    diagnostic.maximumMeanMcseToSd=NaN;
end
if isfield(diagnostic,'modeCount')
    diagnostic.exploratoryClusterCount=diagnostic.modeCount;
    diagnostic.exploratoryClusterIndex=diagnostic.modeIndex;
    diagnostic.exploratoryClusterMass=diagnostic.modeMass;
    diagnostic.modeCount=NaN;
    diagnostic.modeIndex=[];diagnostic.modeMass=[];
end
diagnostic.batchInterpretation='INDEX_PARTITION_ONLY_NOT_INDEPENDENT_REPLICATES';
diagnostic.weightTailHeuristic=diagnostic.paretoKApprox;
diagnostic.paretoKApprox=NaN;
diagnostic.monteCarloErrorEstimated=false;
diagnostic.multimodalityEstablished=false;
diagnostic.ancestorMassESS=local_ancestor_ess(ancestor,weights);
diagnostic.repeatabilityStatus='REQUIRES_INDEPENDENT_SEEDS';
resamplingCount = nnz([stage.resampled]);
uniqueAncestorCount = numel(unique(ancestor));
result = struct('schemaVersion','tc27_target_callback_smc_v3', ...
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
    'particleKernelAttempted',particleKernelAttempted, ...
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
result.samplerProfile=options.samplerProfile;
result.gaussianReferenceUsedForProposalOnly=qualityMode;
result.initialBridgeDensityFrozen=true;
result.finiteParticleAdaptiveSMC=true;
if qualityMode
    result.kernelNames={'conditional_compressor_burner','conditional_GT', ...
        'conditional_duct_PT_nozzle','conditional_fuel','global_cross_component'};
    result.globalSubkernelNames={'learned_gaussian_reference_MH','defensive_independent'};
end
end

function options = local_options(contract,user)
cfg = contract.config;
options = struct();
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
options.adaptFinalScales = logical(local_option(user,'adaptFinalScales',true));
options.blockIndex = local_option( ...
    user,'blockIndex',contract.parameterBlockIndex);
options.blockBasis = local_option(user,'blockBasis',[]);
options.blockInformedRank = local_option(user,'blockInformedRank',[]);
options.globalBasis = local_option(user,'globalBasis',[]);
options.globalInformedRank = local_option(user,'globalInformedRank',[]);
options.blockSingularValues=local_option(user,'blockSingularValues',cell(4,1));
options.globalSingularValues=local_option(user,'globalSingularValues',[]);
options.spectralProposalFloor=local_option(user,'spectralProposalFloor',.002);
options.spectralProposalInflation=local_option(user,'spectralProposalInflation',1.2);
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
options.samplerProfile=local_option(user,'samplerProfile','legacy_reference');
options.conditionalEssFraction=local_option(user,'conditionalEssFraction',.8);
options.resampleEssFraction=local_option(user,'resampleEssFraction',.55);
options.referenceShrinkage=local_option(user,'referenceShrinkage',.15);
options.referenceEigenvalueFloor=local_option(user,'referenceEigenvalueFloor',.05);
assert(ismember(options.samplerProfile,{'quality','legacy_reference'}));
validateattributes([options.conditionalEssFraction,options.resampleEssFraction, ...
    options.referenceShrinkage],{'numeric'},{'real','finite','>',0,'<',1});
validateattributes(options.referenceEigenvalueFloor,{'numeric'},{'scalar','real','finite','positive'});

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
    values=options.blockSingularValues{k};
    assert(isempty(values)||(numel(values)==dimension&&all(isfinite(values))&&all(values>=0)), ...
        'TC27:UQ:SpectralGeometry','分块奇异值与参数维数不符。');
    basis = options.blockBasis{k};
    if ~isequal(size(basis),[dimension,dimension]) || ...
            norm(basis.'*basis-eye(dimension),'fro') > 1e-8 || ...
            options.blockInformedRank(k) < 0 || ...
            options.blockInformedRank(k) > dimension
        error('SHT:SteadyUQC:BadBlockGeometry', ...
            '物理块%d的SVD基或信息秩无效。',k);
    end
end
assert(isempty(options.globalSingularValues)||(numel(options.globalSingularValues)==contract.parameterCount&& ...
    all(isfinite(options.globalSingularValues))&&all(options.globalSingularValues>=0)), ...
    'TC27:UQ:SpectralGeometry','全局奇异值与参数维数不符。');
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
    if ~isempty(moveReference)
        proposalLatent(:,particleIndex)=sht_tc27_uq_move_reference( ...
            'propose',moveReference,latent(:,particleIndex),kernel,rho(kernel));
        continue;
    end
    index = options.blockIndex{kernel};
    if ~isempty(options.blockSingularValues{kernel})
        proposalLatent(index,particleIndex)=sht_tc27_uq_spectral_pcn( ...
            latent(index,particleIndex),options.blockBasis{kernel},options.blockSingularValues{kernel}, ...
            rho(kernel),beta,options.spectralProposalFloor,options.spectralProposalInflation, ...
            options.maximumBlockNullScale(kernel));
        continue;
    end
    proposalLatent(index,particleIndex) = local_operator_pcn( ...
        latent(index,particleIndex),options.blockBasis{kernel}, ...
        options.blockInformedRank(kernel),rho(kernel), ...
        options.blockNullScaleMultiplier(kernel), ...
        options.maximumBlockNullScale(kernel), ...
        options.minimumPcnScale(kernel));
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
    elseif ~isempty(options.globalSingularValues)
        proposalLatent(:,globalPcnIndex)=sht_tc27_uq_spectral_pcn( ...
            latent(:,globalPcnIndex),options.globalBasis,options.globalSingularValues, ...
            rho(5),beta,options.spectralProposalFloor,options.spectralProposalInflation,options.maximumGlobalNullScale);
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
proposalExact = contract.evaluateFunction(proposalTheta);
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
    % 新核对冻结的高斯参考g可逆，接受率必须是完整pi比乘g的反向比。
    % 遗漏后半项会将参考分布错误乘入后验；测试覆盖完整核和条件分块核。
    logAlpha=(1-beta)*(proposalLogQMixture-logQ)+ ...
        beta*(proposalLogPriorLatent+proposalLogLikelihood-logPriorLatent-logLikelihood)+ ...
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
logValue = log(weights)+deltaBeta*bridgeScore;
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
    'ess_before_resample',NaN,'ess_after_resample',NaN, ...
    'resampled',false, ...
    'pcn_scale_after_adaptation',nan(1,5), ...
    'kernel_attempted',zeros(1,5),'kernel_accepted',zeros(1,5), ...
    'kernel_acceptance',nan(1,5),'kernel_normalized_esjd',nan(1,5), ...
    'global_subkernel_attempted',zeros(1,2), ...
    'global_subkernel_accepted',zeros(1,2), ...
    'global_subkernel_acceptance',nan(1,2), ...
    'valid_fraction',NaN,'unique_ancestor_count',0,'move_sweeps',0, ...
    'proposal_budget_expected',0,'proposal_budget_actual',0, ...
    'conditional_ess',NaN,'weight_ess',NaN,'ancestor_mass_ess',NaN, ...
    'unchanged_particle_fraction',NaN,'layer_mean_square_displacement',NaN, ...
    'layer_reference_displacement',NaN,'reference_shrinkage',NaN, ...
    'reference_relative_minimum_eigenvalue',NaN);
end

function next=local_next_conditional_beta(beta,score,weights,fraction)
n=numel(weights);target=fraction*n;
if local_conditional_ess(weights,score,1-beta)>=target,next=1;return;end
lo=beta;hi=1;
for k=1:60
    mid=(lo+hi)/2;
    if local_conditional_ess(weights,score,mid-beta)<target,hi=mid;else,lo=mid;end
end
% 无效物理点的似然为零，任意正增温都会淘汰；仅在beta=0允许跨越
% 这个跳变，实际CESS如实保存。不用强制1e-4掩盖之后的粒子退化。
if lo<=beta
    assert(beta==0,'TC27:UQ:TemperingStalled','CESS增温停滞，请检查目标及有限似然。');
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

function value=local_reference_field(ref,name)
value=NaN;if ~isempty(ref),value=ref.(name);end
end

function value = local_option(options,name,defaultValue)
if isstruct(options) && isfield(options,name) && ~isempty(options.(name))
    value = options.(name);
else
    value = defaultValue;
end
end
