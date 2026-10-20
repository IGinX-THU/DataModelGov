function result = sht_steady_model_uq_b_smc( ...
        contract, prior, likelihood, guidedProposal, userOptions)
%SHT_STEADY_MODEL_UQ_B_SMC 方法B的变维联合几何桥SMC。
%
% 全部参数始终属于同一个联合后验，维数由输入字典确定。只有一套粒子、权重、温度序列
% 和祖先谱系。五个核只是同一后验上的不同移动方式：
%   1  压气机+燃烧室；
%   2  燃气涡轮及其前四路冷却气；
%   3  涵道+动力涡轮+喷管及其后六路冷却气；
%   4  燃油测量偏置；
%   5  跨部件全局pCN与防御性独立跳转。
%
% 每次扫掠按固定整数配额将N个粒子分配给五核，每个粒子只生成一个
% 候选，所以一轮候选总数严格为N。初始粒子来自防御性混合提议q(z)，
% SMC采用统一几何桥
%   pi_beta(z) proportional to q(z)^(1-beta)*[p(z)L(z)]^beta
% 从q连续推进到精确后验p(z)L(z)。beta=0时粒子等权，beta=1时目标
% 与输入合同定义的贝叶斯后验完全一致。局部Jacobian和SVD只设计提议，不替代
% 完整DLL似然。

if nargin < 5 || isempty(userOptions), userOptions = struct(); end
options = local_options(contract,userOptions);
qualityMode=strcmp(options.samplerProfile,'quality');
referenceHash='';
if qualityMode || options.finalReferenceMove
    referenceHash=sht_steady_model_uq_common('filehash',which('sht_tc27_uq_move_reference'));
end
rng(options.randomSeed,'twister');
n = options.particleCount;
control=[];controlState=[];controlFound=false;
if isfield(userOptions,'runControl')
    control=userOptions.runControl;
    controlKey=sprintf('smc_b_%d_%d',n,options.randomSeed);
    proposalIdentity=guidedProposal;
    if isfield(proposalIdentity,'createdAt'),proposalIdentity=rmfield(proposalIdentity,'createdAt');end
    controlSignature=sht_tc24_run_control('hash',struct('contract',contract.contractHash, ...
        'runId',contract.config.runId,'options',options,'proposal',proposalIdentity,'likelihood',likelihood, ...
        'source',sht_steady_model_uq_common('filehash',[mfilename('fullpath'),'.m']), ...
        'moveReferenceHash',referenceHash));
    [controlState,controlFound]=sht_tc24_run_control('load',control,controlKey);resumeRng=rng;
    if controlFound,assert(strcmp(controlState.signature,controlSignature),'TC24:SMC:ResumeMismatch','SMC提议/目标/预算改变。');end
end

if ~isstruct(guidedProposal) || ~isfield(guidedProposal,'dimension') || ...
        guidedProposal.dimension ~= contract.parameterCount
    error('SHT:SteadyUQB:BadGuidedProposal', ...
        '初始防御混合提议与方法B参数字典维数不一致。');
end

% 检查点已经保存了初始精确残差，续跑无需再付一次N粒子的DLL开销。
checkpointFile='';signature=struct();resumed=false;
if contract.modelMode==0&&isempty(control)
    % 精确DLL缓存只依赖物理合同，可以跨运行共享；SMC状态还依赖提议和
    % 随机过程，必须按运行隔离。同一运行改变合同/几何仍由signature拒绝。
    runId=contract.config.runId;
    assert(~isempty(runId),'TC24:SMC:RunIdentity','SMC断点必须有明确运行编号。');
    digest=java.security.MessageDigest.getInstance('SHA-256');
    digest.update(typecast(uint8(unicode2native(char(runId),'UTF-8')),'int8'));
    bytes=typecast(int8(digest.digest()),'uint8');
    runKey=lower(reshape(dec2hex(bytes,2).',1,[]));
    checkpointFile=fullfile(fileparts(contract.cacheFile),sprintf('tc24_b_smc_%s_%d_%d.mat', ...
        runKey(1:16),n,options.randomSeed));
    signature=struct('contractHash',contract.contractHash,'options',options, ...
        'codeHash',sht_steady_model_uq_common('filehash',[mfilename('fullpath'),'.m']));
    signature.runId=char(runId);
    signature.likelihood=likelihood;
    signature.moveReferenceHash=referenceHash;
    signature.proposal=guidedProposal;
    if isfield(signature.proposal,'createdAt'),signature.proposal=rmfield(signature.proposal,'createdAt');end
    signature.spectralCodeHash=sht_steady_model_uq_common('filehash',which('sht_tc24_uq_spectral_pcn'));
    resumed=isfile(checkpointFile);
    if resumed
        saved=load(checkpointFile,'checkpoint','initialExact');
        assert(isequaln(saved.checkpoint.signature,signature), ...
            'TC24:SMC:ResumeMismatch','SMC断点目标、几何、配置或源码身份不匹配。');
        initialExact=saved.initialExact;
    end
end

% 确定性分量配额和分量内反向样本降低有限样本波动。密度q始终按
% 实际整数配额计算，不把局部参考点偷换成贝叶斯先验。
[theta,latent,initialComponent,initialAudit] = ...
    sht_steady_model_uq_b_proposal('sample',guidedProposal,n, ...
    options.randomSeed+1,'deterministic_mixture');
logQ = sht_steady_model_uq_b_proposal( ...
    'logdensity',guidedProposal,latent,initialAudit.densityWeight);
logPriorLatent = sht_steady_model_uq_b_proposal('logpriorlatent',latent);
[priorImportanceWeights,initialLogNormalization] = ...
    local_normalize_log_weights(logPriorLatent-logQ);
initialImportanceEss = 1/sum(priorImportanceWeights.^2);

if controlFound
    exact=controlState.variables.initialExact;initialExact=exact;
elseif resumed
    exact=initialExact;
else
    exact = local_evaluate(contract,theta,options);
    initialExact=exact;
end
logLikelihood = sht_steady_model_uq_likelihood( ...
    'evaluate',likelihood,exact.residual,exact.valid);
logPrior = sht_steady_model_uq_sampler('logprior',prior,theta);
minimumValid = max(12,ceil(0.20*n));
if nnz(isfinite(logLikelihood)) < minimumValid
    error('SHT:SteadyUQB:InitialValidity', ...
        '初始粒子只有%d/%d个具有有效精确似然，最低需要%d个。', ...
        nnz(isfinite(logLikelihood)),n,minimumValid);
end

% pL/q只用于初始覆盖审计。正式几何桥从q的等权粒子开始。
bridgeScore = logPriorLatent+logLikelihood-logQ;
[initialTargetWeights,initialLogEvidenceEstimate] = ...
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
priorOnlyRefreshCount = 0;
finalMoveHistory=struct('sweep',{},'mean',{},'std',{},'meanLogLikelihood',{},'q025',{},'q975',{});
finalReferenceAudit=[];
stage = repmat(local_empty_stage(),options.maximumStageCount,1);
totalAttempted = zeros(1,5);
totalAccepted = zeros(1,5);
totalEsjd = zeros(1,5);
totalGlobalSubAttempted = zeros(1,2);
totalGlobalSubAccepted = zeros(1,2);
totalIndependentComponentAttempted = zeros(1,guidedProposal.componentCount);
totalIndependentComponentAccepted = zeros(1,guidedProposal.componentCount);
particleKernelAttempted=zeros(n,5);
particleMoveCount=zeros(1,n);

% TC24每层保存完整粒子、随机状态及移动统计，续跑不能换目标或配置。
startStage=1;previousDllCount=0;
stateNames={'theta','latent','logLikelihood','logPrior','logPriorLatent','logQ', ...
    'exact','weights','ancestor','beta','rho','logEvidence','dllEvaluationCount', ...
    'dllRuntime','stage','totalAttempted','totalAccepted','totalEsjd', ...
    'totalGlobalSubAttempted','totalGlobalSubAccepted','priorOnlyRefreshCount','totalIndependentComponentAttempted','totalIndependentComponentAccepted','finalMoveHistory','initialExact', ...
    'particleKernelAttempted','particleMoveCount','finalReferenceAudit'};
if contract.modelMode==0&&isempty(control)
    if isfile(checkpointFile)
        saved=load(checkpointFile,'checkpoint');cp=saved.checkpoint;
        assert(isequaln(cp.signature,signature),'TC24:SMC:ResumeMismatch','SMC断点身份不匹配。');
        load(checkpointFile,stateNames{:});
        rng(cp.rngState);startStage=cp.completedStage+1;
        previousDllCount=dllEvaluationCount;
    end
end
resumeInStage=false;sweepStart=1;
controlNames=[stateNames,{'initialComponent','initialAudit','initialImportanceEss', ...
    'initialLogNormalization','initialTargetWeights','initialLogEvidenceEstimate', ...
    'initialTargetImportanceEss','initialTargetComponentMass','dominantInitialTargetComponent', ...
    'initialBestLogTargetLatent','initialBestIndex','attempted','accepted','esjdSum', ...
    'globalSubAttempted','globalSubAccepted','independentComponentAttempted','independentComponentAccepted', ...
    'deltaBeta','essBeforeResample','essAfterResample','resampled','sweepCount', ...
    'moveReference','conditionalEss','pcnAttempted','pcnAccepted','scaleBefore','stageStartLatent'}];
if controlFound
    % 字段名单在源码内固定，不执行检查点携带的表达式。
    for ci=1:numel(controlNames)
        cn=controlNames{ci};eval([cn,'=controlState.variables.(cn);']);
    end
    startStage=controlState.stageIndex;sweepStart=controlState.nextSweep;
    resumeInStage=controlState.inStage;previousDllCount=dllEvaluationCount;rng(resumeRng);
end
stageIndex=startStage-1;
if beta>=1-options.betaTolerance&&~resumeInStage,startStage=options.maximumStageCount+1;end
% MATLAB空for会清空循环变量。单独使用迭代变量，保留已完成断点的层号。
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
    [newWeights,logIncrement] = local_tempered_weights( ...
        weights,bridgeScore,deltaBeta);
    logEvidence = logEvidence+logIncrement;
    essBeforeResample = 1/sum(newWeights.^2);
    conditionalEss=local_conditional_ess(weights,bridgeScore,deltaBeta);
    beta = betaNext;
    moveReference=[];
    if qualityMode || (options.finalReferenceMove && beta>=1-options.betaTolerance)
        % 参考分布仅用于设计候选；B的全部联合先验和精确似然不变。
        % 使用重采样前的加权总体，层内冻结参考与尺度，最后一层不再适应。
        moveReference=sht_tc27_uq_move_reference('build',latent,newWeights,beta,options);
        if beta>=1-options.betaTolerance
            finalReferenceAudit=struct('beta',beta,'mean',moveReference.mean, ...
                'covariance',moveReference.covariance,'shrinkage',moveReference.shrinkage, ...
                'weightESS',moveReference.weightESS,'nullOnlySubkernelDisabled',true);
        end
    end

    % 中间层重采样；最终层保留重要性权重。结构性先验方向若存在，可在
    % 重采样后精确刷新，其q与p边际相同且不影响DLL残差。
    needResample=beta<1-options.betaTolerance;
    if qualityMode,needResample=essBeforeResample<options.resampleEssFraction*n;end
    if needResample
        index = local_systematic_index(newWeights,n);
        [theta,latent,logLikelihood,logPrior,logPriorLatent,logQ, ...
            exact,ancestor] = local_resample_state(index,theta,latent, ...
            logLikelihood,logPrior,logPriorLatent,logQ,exact,ancestor);
        particleKernelAttempted=particleKernelAttempted(index,:);
        particleMoveCount=particleMoveCount(index);
        if ~qualityMode
        [theta,latent,logPrior,logPriorLatent,logQ] = ...
            local_refresh_prior_only(theta,latent,prior,guidedProposal, ...
            initialAudit.densityWeight,options.priorOnlyIndex,logPrior, ...
            logPriorLatent,logQ);
        priorOnlyRefreshCount = priorOnlyRefreshCount + ...
            ~isempty(options.priorOnlyIndex);
        end
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
    independentComponentAttempted = zeros(1,guidedProposal.componentCount);
    independentComponentAccepted = zeros(1,guidedProposal.componentCount);
    pcnAttempted=zeros(1,5);pcnAccepted=zeros(1,5);
    scaleBefore=rho;stageStartLatent=latent;
    if beta==1
        finalMoveHistory=local_final_record(0,theta,weights,logLikelihood);
    end
    sweepStart=1;
    end
    resumeInStage=false;
    for sweep = sweepStart:sweepCount
        allocation = sht_steady_model_uq_b_proposal( ...
            'allocation',options.kernelWeights,n,stageIndex+sweep-2);
        if qualityMode
            % 固定整数配额，随机排列核标签，使每个粒子有机会接受全部核。
            allocation.component=reshape(allocation.component(randperm(n)),1,[]);
        end
        for kernel=1:5
            particleKernelAttempted(:,kernel)=particleKernelAttempted(:,kernel)+ ...
                (allocation.component(:)==kernel);
        end
        [theta,latent,logLikelihood,logPrior,logPriorLatent,logQ, ...
            exact,move] = local_five_kernel_sweep( ...
            contract,prior,likelihood,guidedProposal, ...
            initialAudit.densityWeight,beta,theta,latent,logLikelihood, ...
            logPrior,logPriorLatent,logQ,exact,options,rho,allocation, ...
            stageIndex+sweep-2,moveReference);
        particleMoveCount=particleMoveCount+move.acceptedMask;
        pcnAttempted=pcnAttempted+move.pcnAttempted;
        pcnAccepted=pcnAccepted+move.pcnAccepted;
        attempted = attempted+move.attempted;
        accepted = accepted+move.accepted;
        esjdSum = esjdSum+move.esjdSum;
        globalSubAttempted = globalSubAttempted+move.globalSubAttempted;
        globalSubAccepted = globalSubAccepted+move.globalSubAccepted;
        independentComponentAttempted = independentComponentAttempted + ...
            move.independentComponentAttempted;
        independentComponentAccepted = independentComponentAccepted + ...
            move.independentComponentAccepted;
        dllEvaluationCount = dllEvaluationCount+move.dllCount;
        dllRuntime = dllRuntime+move.dllRuntime_s;
        for kernel = 1:5
            if ~qualityMode && move.pcnAttempted(kernel) > 0 && ...
                    ~(beta==1 && options.freezeFinalPcnScale)
                rho(kernel) = local_adapt_scale(rho(kernel), ...
                    move.pcnAccepted(kernel)/move.pcnAttempted(kernel), ...
                    kernel,options);
            end
        end
        if beta==1
            finalMoveHistory(end+1)=local_final_record(sweep,theta,weights,logLikelihood); %#ok<AGROW>
            if options.verbose && (mod(sweep,4)==0 || sweep==sweepCount)
                fprintf('  B-SMC final move=%d/%d meanLL=%.4f DLL=%d frozenScale=%d\n', ...
                    sweep,sweepCount,finalMoveHistory(end).meanLogLikelihood,dllEvaluationCount,options.freezeFinalPcnScale);
            end
        end
        if ~isempty(control)
            state=struct('signature',controlSignature,'stageIndex',stageIndex,'nextSweep',sweep+1,'inStage',true,'variables',struct());
            state.progress=struct('phase','SMC_B','stage',stageIndex,'sweep',sweep, ...
                'sweepLimit',sweepCount,'beta',beta,'particleCount',n);
            for ci=1:numel(controlNames),cn=controlNames{ci};state.variables.(cn)=eval(cn);end
            sht_tc24_run_control('boundary',control,controlKey,state);
        end
    end

    if sum(attempted) ~= n*sweepCount
        error('SHT:SteadyUQB:ProposalBudgetViolation', ...
            '本层应产生%d个候选，实际为%d个。', ...
            n*sweepCount,sum(attempted));
    end
    totalAttempted = totalAttempted+attempted;
    totalAccepted = totalAccepted+accepted;
    totalEsjd = totalEsjd+esjdSum;
    totalGlobalSubAttempted = totalGlobalSubAttempted+globalSubAttempted;
    totalGlobalSubAccepted = totalGlobalSubAccepted+globalSubAccepted;
    totalIndependentComponentAttempted = ...
        totalIndependentComponentAttempted+independentComponentAttempted;
    totalIndependentComponentAccepted = ...
        totalIndependentComponentAccepted+independentComponentAccepted;
    acceptance = accepted./max(attempted,1);
    normalizedEsjd = esjdSum./max(attempted,1);
    if qualityMode && beta<1-options.betaTolerance
        for kernel=1:5
            if pcnAttempted(kernel)>0
                rho(kernel)=local_adapt_scale(rho(kernel), ...
                    pcnAccepted(kernel)/pcnAttempted(kernel),kernel,options);
            end
        end
    end
    stage(stageIndex) = struct('index',stageIndex,'beta',beta, ...
        'delta_beta',deltaBeta,'conditional_ess',conditionalEss, ...
        'pcn_scale_before',scaleBefore,'reference_frozen_within_stage',~isempty(moveReference), ...
        'net_mean_squared_move',mean(sum((latent-stageStartLatent).^2,1)), ...
        'ess_before_resample',essBeforeResample, ...
        'ess_after_resample',essAfterResample,'resampled',resampled, ...
        'pcn_scale_after_adaptation',rho, ...
        'kernel_attempted',attempted,'kernel_accepted',accepted, ...
        'kernel_acceptance',acceptance,'kernel_normalized_esjd', ...
        normalizedEsjd,'block_acceptance',acceptance, ...
        'global_subkernel_attempted',globalSubAttempted, ...
        'global_subkernel_accepted',globalSubAccepted, ...
        'global_subkernel_acceptance',globalSubAccepted./ ...
        max(globalSubAttempted,1), ...
        'guided_acceptance',globalSubAccepted(2)/max(globalSubAttempted(2),1), ...
        'guided_component_attempted',independentComponentAttempted, ...
        'guided_component_accepted',independentComponentAccepted, ...
        'guided_component_acceptance',independentComponentAccepted./ ...
        max(independentComponentAttempted,1), ...
        'valid_fraction',mean(isfinite(logLikelihood)), ...
        'unique_ancestor_count',numel(unique(ancestor)), ...
        'move_sweeps',sweepCount,'proposal_budget_expected',n*sweepCount, ...
        'proposal_budget_actual',sum(attempted));
    if options.verbose
        fprintf(['  B-SMC stage=%2d beta=%.6f dBeta=%.3g ESS=%.1f ' ...
            'resample=%d acc=[%.1f %.1f %.1f %.1f %.1f]%% ' ...
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
        state.progress=struct('phase','SMC_B','stage',stageIndex,'sweep',sweepCount, ...
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
    error('SHT:SteadyUQB:MaximumStages', ...
        '方法B在%d层后beta仅到%.6f。',options.maximumStageCount,beta);
end

stage = stage(1:stageIndex);
weights = weights/sum(weights);
% quality全部方向由联合核移动，不采用依赖q边际独立性假设的免回放刷新。
if ~qualityMode
[theta,latent,logPrior,logPriorLatent,logQ] = ...
    local_refresh_prior_only(theta,latent,prior,guidedProposal, ...
    initialAudit.densityWeight,options.priorOnlyIndex,logPrior, ...
    logPriorLatent,logQ);
priorOnlyRefreshCount = priorOnlyRefreshCount + ...
    ~isempty(options.priorOnlyIndex);
end
exact.theta = theta;
exact.valid = isfinite(logLikelihood);
exact.insideBounds = true(1,n);
exact.candidateCount = n;
logTargetLatent = logPriorLatent+logLikelihood;
[finalBestLogTargetLatent,finalBestIndex] = max(logTargetLatent);
finalAncestorComponentMass = zeros(1,guidedProposal.componentCount);
ancestorComponent = initialComponent(ancestor);
for component = 1:guidedProposal.componentCount
    finalAncestorComponentMass(component) = ...
        sum(weights(ancestorComponent==component));
end
dominantInitialTargetComponentRetained = ...
    finalAncestorComponentMass(dominantInitialTargetComponent)>1e-8;
diagnostic = sht_steady_model_uq_sampler( ...
    'diagnostics',theta,weights,log(max(weights,realmin)),prior);
% 同一SMC总体内的粒子有共同谱系，不能用权重ESS伪装独立样本MCSE；
% 索引分批和探索性聚类也不证明独立重复或物理多峰。
diagnostic.weightOnlyMeanErrorHeuristic=diagnostic.meanMcse;
diagnostic.meanMcse=nan(size(diagnostic.meanMcse));diagnostic.maximumMeanMcseToSd=NaN;
diagnostic.exploratoryClusterCount=diagnostic.modeCount;
diagnostic.exploratoryClusterIndex=diagnostic.modeIndex;
diagnostic.exploratoryClusterMass=diagnostic.modeMass;
diagnostic.modeCount=NaN;diagnostic.modeIndex=[];diagnostic.modeMass=[];
diagnostic.weightTailHeuristic=diagnostic.paretoKApprox;diagnostic.paretoKApprox=NaN;
diagnostic.monteCarloErrorEstimated=false;diagnostic.multimodalityEstablished=false;
diagnostic.repeatabilityStatus='REQUIRES_INDEPENDENT_SEEDS';
diagnostic.batchInterpretation='INDEX_PARTITION_ONLY_NOT_INDEPENDENT_REPLICATES';
diagnostic.unmovedParticleFraction=mean(particleMoveCount==0);
resamplingCount = nnz([stage.resampled]);
uniqueAncestorCount = numel(unique(ancestor));
kernelNames = {'compressor_burner','gas_generator_turbine', ...
    'duct_power_turbine_nozzle','fuel_bias','global_cross_component'};
kernelAcceptance = totalAccepted./max(totalAttempted,1);

% 同时保留B06/B08/B09和历史报告会读取的旧字段名称。
result = struct('schemaVersion','steady_model_uq_method_b_smc_v5_bridge', ...
    'theta',theta,'latent',latent,'weights',weights, ...
    'logLikelihood',logLikelihood,'logPrior',logPrior, ...
    'logPriorLatent',logPriorLatent,'logQ',logQ, ...
    'logTargetLatent',logTargetLatent,'exact',exact,'stage',stage, ...
    'stageCount',stageIndex,'finalBeta',beta,'finalPcnScale',rho, ...
    'kernelAttempted',totalAttempted,'kernelAccepted',totalAccepted, ...
    'kernelAcceptance',kernelAcceptance, ...
    'kernelNormalizedEsjd',totalEsjd./max(totalAttempted,1), ...
    'kernelNames',{kernelNames}, ...
    'globalSubkernelNames',{{'global_pcn','defensive_independent'}}, ...
    'globalSubkernelAttempted',totalGlobalSubAttempted, ...
    'globalSubkernelAccepted',totalGlobalSubAccepted, ...
    'globalSubkernelAcceptance',totalGlobalSubAccepted./ ...
    max(totalGlobalSubAttempted,1), ...
    'guidedAttempted',totalGlobalSubAttempted(2), ...
    'guidedAccepted',totalGlobalSubAccepted(2), ...
    'guidedAcceptance',totalGlobalSubAccepted(2)/ ...
    max(totalGlobalSubAttempted(2),1), ...
    'guidedComponentAttempted',totalIndependentComponentAttempted, ...
    'guidedComponentAccepted',totalIndependentComponentAccepted, ...
    'guidedComponentAcceptance',totalIndependentComponentAccepted./ ...
    max(totalIndependentComponentAttempted,1), ...
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
    'proposalBudgetPerSweep',n,'priorOnlyParameterIndex', ...
    options.priorOnlyIndex,'priorOnlyRefreshCount',priorOnlyRefreshCount, ...
    'geometricBridgeUsed',true,'options',options, ...
    'finalBlockScale',rho,'blockAttempted',totalAttempted, ...
    'blockAccepted',totalAccepted,'blockAcceptance',kernelAcceptance, ...
    'blockNames',{kernelNames},'finalCrossNullScale', ...
    local_global_null_scale(rho(5),options));
result.finalMoveHistory=finalMoveHistory;
result.finalReferenceAudit=finalReferenceAudit;
result.samplerProfile=options.samplerProfile;
result.moveReferenceHash=referenceHash;
result.particleKernelAttempted=particleKernelAttempted;
result.particleMoveCount=particleMoveCount;
result.samplingPrecisionDiagnostic=sht_steady_model_uq_b_precision_diagnostic(result,prior);
result.resumedFromCheckpoint=resumed;
result.incrementalDllEvaluationCount=dllEvaluationCount-previousDllCount;
end

function options = local_options(contract,user)
cfg = contract.config;
options = struct();
options.samplerProfile=char(local_option(user,'samplerProfile', ...
    local_option(cfg,'bSamplerProfile','legacy_reference')));
assert(ismember(options.samplerProfile,{'quality','legacy_reference'}), ...
    'TC24:B:SamplerProfile','未知B采样配置。');
options.conditionalEssFraction=local_option(user,'conditionalEssFraction',.8);
options.resampleEssFraction=local_option(user,'resampleEssFraction',.55);
options.referenceShrinkage=local_option(user,'referenceShrinkage',.15);
options.referenceEigenvalueFloor=local_option(user,'referenceEigenvalueFloor',.05);
% 正式B07显式传入；先导B06不隐式继承此开关，保留V1调参随机路径。
options.finalReferenceMove=local_option(user,'finalReferenceMove',false);
validateattributes(options.finalReferenceMove,{'logical','numeric'},{'scalar','finite'});
assert(ismember(options.finalReferenceMove,[0 1]),'TC24:B:FinalReferenceFlag', ...
    'finalReferenceMove必须为0或1。');
options.finalReferenceMove=logical(options.finalReferenceMove);
validateattributes(options.conditionalEssFraction,{'numeric'},{'scalar','finite','>',0,'<',1});
validateattributes(options.resampleEssFraction,{'numeric'},{'scalar','finite','>',0,'<',1});
validateattributes(options.referenceShrinkage,{'numeric'},{'scalar','finite','>=',0,'<=',1});
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
options.blockIndex = local_option(user,'blockIndex',contract.samplingKernelIndex);
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
options.globalNullOnlyFraction=local_option(user,'globalNullOnlyFraction', ...
    local_option(cfg,'globalNullOnlyFraction',0));
options.globalNullOnlyScale=local_option(user,'globalNullOnlyScale', ...
    local_option(cfg,'globalNullOnlyScale',.35));
options.priorOnlyIndex = unique(local_option( ...
    user,'priorOnlyIndex',zeros(0,1)),'stable');
options.priorOnlyIndex = options.priorOnlyIndex(:);
options.useCache = logical(local_option(user,'useCache',cfg.useCache));
options.verbose = logical(local_option(user,'verbose',cfg.verbose));
options.pcnGeometry=char(local_option(user,'pcnGeometry',local_option(cfg,'pcnGeometry','rank_split')));
options.freezeFinalPcnScale=logical(local_option(user,'freezeFinalPcnScale',local_option(cfg,'freezeFinalPcnScale',false)));
options.blockSingularValue=local_option(user,'blockSingularValue',[]);
options.globalSingularValue=local_option(user,'globalSingularValue',[]);
% B自身似然的全谱，未受观测约束的方向补零，不能借用C的矩似然几何。
options.globalSingularValues=zeros(contract.parameterCount,1);
assert(numel(options.globalSingularValue)<=contract.parameterCount && ...
    all(isfinite(options.globalSingularValue)) && all(options.globalSingularValue>=0), ...
    'TC24:B:ReferenceSpectrum','B参考奇异值无效。');
options.globalSingularValues(1:numel(options.globalSingularValue))=options.globalSingularValue(:);
if strcmp(options.samplerProfile,'quality')
    assert(~isempty(options.globalSingularValue),'TC24:B:ReferenceSpectrum','quality需提供B自身全谱。');
    assert(options.globalNullOnlyFraction==0,'TC24:B:NullOnlyConflict', ...
        'quality由完整参考协方差处理弱方向，不同时启用旧弱方向专用核。');
    options.freezeFinalPcnScale=true;
end
if options.finalReferenceMove
    assert(~isempty(options.globalSingularValue),'TC24:B:ReferenceSpectrum', ...
        '末层参考需要B自身的全谱，不能使用其他统计目标的几何。');
    options.freezeFinalPcnScale=true;
end
assert(ismember(options.pcnGeometry,{'rank_split','spectral'}),'未知pCN几何。');
if strcmp(options.pcnGeometry,'spectral')
    assert(numel(options.blockSingularValue)==4 && ~isempty(options.globalSingularValue), ...
        'SHT:SteadyUQB:SpectralGeometry','逐方向核必须具有当前B似然的奇异值，不能借用C几何。');
end

fiveFields = {'kernelWeights','initialPcnScale','minimumPcnScale', ...
    'maximumPcnScale','targetAcceptance'};
for i = 1:numel(fiveFields)
    options.(fiveFields{i}) = options.(fiveFields{i})(:).';
    if numel(options.(fiveFields{i})) ~= 5 || ...
            any(~isfinite(options.(fiveFields{i})))
        error('SHT:SteadyUQB:BadFiveKernelOption', ...
            '%s必须包含5个有限数。',fiveFields{i});
    end
end
assert(all(options.kernelWeights>=0)&&sum(options.kernelWeights)>0, ...
    'TC24:B:KernelWeights','五核配额必须非负且总和为正。');
assert(all(options.minimumPcnScale>0)&&all(options.maximumPcnScale<1)&& ...
    all(options.initialPcnScale>=options.minimumPcnScale)&& ...
    all(options.initialPcnScale<=options.maximumPcnScale), ...
    'TC24:B:PcnScale','移动尺度须满足0<最小值<=初值<=最大值<1。');
validateattributes(options.moveSweeps,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(options.finalMoveSweeps,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(options.maximumStageCount,{'numeric'},{'scalar','integer','positive','finite'});
options.kernelWeights = options.kernelWeights/sum(options.kernelWeights);
if options.particleCount < 24 || options.particleCount ~= floor(options.particleCount)
    error('SHT:SteadyUQB:BadParticleCount','粒子数必须为不小于24的整数。');
end
if options.targetEssFraction <= 0 || options.targetEssFraction >= 1 || ...
        options.globalPcnFraction <= 0 || options.globalPcnFraction >= 1
    error('SHT:SteadyUQB:BadFractionOption', ...
        'ESS目标与全局pCN比例必须位于(0,1)。');
end
if numel(options.blockIndex) ~= 5 || ...
        ~isequal(sort(options.blockIndex{5}(:)), ...
        (1:contract.parameterCount).')
    error('SHT:SteadyUQB:BadBlockIndex', ...
        '方法B必须包含四个物理块和一个全维跨块核。');
end
physicalUnion = sort(vertcat(options.blockIndex{1:4}));
if ~isequal(physicalUnion,(1:contract.parameterCount).') || ...
        sum(cellfun(@numel,options.blockIndex(1:4))) ~= ...
        contract.parameterCount
    error('SHT:SteadyUQB:BadPhysicalBlockPartition', ...
        '四个物理块必须互斥且完整覆盖全部参数。');
end
if numel(options.blockBasis) ~= 4 || numel(options.blockInformedRank) ~= 4
    error('SHT:SteadyUQB:MissingBlockGeometry', ...
        '方法B需要四个物理块的局部SVD几何。');
end
for k = 1:4
    dimension = numel(options.blockIndex{k});
    basis = options.blockBasis{k};
    if ~isequal(size(basis),[dimension,dimension]) || ...
            norm(basis.'*basis-eye(dimension),'fro') > 1e-8 || ...
            options.blockInformedRank(k) < 0 || ...
            options.blockInformedRank(k) > dimension
        error('SHT:SteadyUQB:BadBlockGeometry', ...
            '物理块%d的SVD基或信息秩无效。',k);
    end
end
if ~isequal(size(options.globalBasis), ...
        [contract.parameterCount,contract.parameterCount]) || ...
        norm(options.globalBasis.'*options.globalBasis- ...
        eye(contract.parameterCount),'fro') > 1e-8 || ...
        options.globalInformedRank < 0 || ...
        options.globalInformedRank > contract.parameterCount
    error('SHT:SteadyUQB:BadGlobalGeometry', ...
        '跨部件全局SVD基或信息秩无效。');
end
if any(options.priorOnlyIndex < 1) || ...
        any(options.priorOnlyIndex > contract.parameterCount)
    error('SHT:SteadyUQB:BadPriorOnlyIndex', ...
        '结构性先验参数下标超出参数合同。');
end
end

function [theta,latent,logLikelihood,logPrior,logPriorLatent,logQ, ...
        exact,move] = local_five_kernel_sweep( ...
        contract,prior,likelihood,guidedProposal,proposalDensityWeight, ...
        beta,theta,latent,logLikelihood,logPrior,logPriorLatent,logQ, ...
        exact,options,rho,allocation,phase,moveReference)
% 先构造全部N个候选，再合并为一次DLL批量回放。一个粒子在一次扫掠中
% 只属于一个核，合批不改变任一核的提议分布或Metropolis接受概率。
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
    elseif strcmp(options.pcnGeometry,'spectral')
        proposalLatent(index,particleIndex)=sht_tc24_uq_spectral_pcn( ...
            latent(index,particleIndex),options.blockBasis{kernel}, ...
            options.blockSingularValue{kernel},rho(kernel));
    else
        proposalLatent(index,particleIndex) = local_operator_pcn( ...
        latent(index,particleIndex),options.blockBasis{kernel}, ...
        options.blockInformedRank(kernel),rho(kernel), ...
        options.blockNullScaleMultiplier(kernel), ...
        options.maximumBlockNullScale(kernel), ...
        options.minimumPcnScale(kernel));
    end
end

% 第五核配额内部由全局pCN和防御性独立MH共享。
globalIndex = find(allocation.component==5);
subAllocation = local_global_allocation( ...
    numel(globalIndex),options.globalPcnFraction,phase);
globalPcnIndex = globalIndex(subAllocation.component==1);
independentIndex = globalIndex(subAllocation.component==2);
nullOnlyIndex=[];jointPcnIndex=globalPcnIndex;
% 参考核对g可逆，旧弱方向核对先验可逆，二者不可共用一个g修正项。
% 参考启用时全部全局pCN配额用于联合参考移动，不增加候选总预算。
if isempty(moveReference) && options.globalNullOnlyFraction>0 && ...
        options.globalInformedRank<size(theta,1) && ~isempty(globalPcnIndex)
    split=local_global_allocation(numel(globalPcnIndex),options.globalNullOnlyFraction,phase);
    nullOnlyIndex=globalPcnIndex(split.component==1);
    jointPcnIndex=globalPcnIndex(split.component==2);
    proposalLatent(:,nullOnlyIndex)=sht_uq_null_pcn( ...
        latent(:,nullOnlyIndex),options.globalBasis,options.globalInformedRank,options.globalNullOnlyScale);
end
if ~isempty(jointPcnIndex)
    if ~isempty(moveReference)
        proposalLatent(:,jointPcnIndex)=sht_tc27_uq_move_reference( ...
            'propose',moveReference,latent(:,jointPcnIndex),5,rho(5));
    elseif strcmp(options.pcnGeometry,'spectral')
        proposalLatent(:,jointPcnIndex)=sht_tc24_uq_spectral_pcn( ...
            latent(:,jointPcnIndex),options.globalBasis,options.globalSingularValue,rho(5));
    else
        proposalLatent(:,jointPcnIndex) = local_operator_pcn( ...
        latent(:,jointPcnIndex),options.globalBasis, ...
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

% pCN对标准正态先验p(z)可逆。中间目标还含q(z)^(1-beta)，因此
% 必须补入(1-beta)*Delta[log q-log p]；beta=1时退化为完整似然比。
if isempty(moveReference)
logAlpha = (1-beta)*( ...
    (proposalLogQMixture-logQ) - ...
    (proposalLogPriorLatent-logPriorLatent)) + ...
    beta*(proposalLogLikelihood-logLikelihood);
else
    % 参考高斯g只决定候选。MH必须补g(z)/g(z')，不能把g当作后验。
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
        beta*(proposalLogPriorLatent(targetIndex)+ ...
        proposalLogLikelihood(targetIndex));
    currentLogTarget = (1-beta)*logQ(targetIndex) + ...
        beta*(logPriorLatent(targetIndex)+logLikelihood(targetIndex));
    logAlpha(targetIndex) = proposalLogTarget-currentLogTarget + ...
        currentComponentLogQ-proposalComponentLogQ;
end
accept = log(rand(1,n)) < min(0,logAlpha);

move = local_empty_move(guidedProposal.componentCount);
move.acceptedMask=accept;
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
    jump = proposalLatent(jumpIndex,acceptedIndex) - ...
        latent(jumpIndex,acceptedIndex);
    move.esjdSum(kernel) = sum(jump(:).^2)/max(numel(jumpIndex),1);
end
move.pcnAttempted(1:4) = move.attempted(1:4);
move.pcnAccepted(1:4) = move.accepted(1:4);
% 弱方向专用核使用固定尺度，其接受率不能驱动强方向步长的适应。
move.pcnAttempted(5) = numel(jointPcnIndex);
move.pcnAccepted(5) = nnz(accept(jointPcnIndex));
move.globalSubAttempted = [numel(globalPcnIndex),numel(independentIndex)];
move.globalSubAccepted = [nnz(accept(globalPcnIndex)), ...
    nnz(accept(independentIndex))];
for component = 1:guidedProposal.componentCount
    index = independentIndex(independentComponent(independentIndex)==component);
    move.independentComponentAttempted(component) = numel(index);
    move.independentComponentAccepted(component) = nnz(accept(index));
end
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
    scale(informedRank+1:end) = min(maximumNull,nullMultiplier*rho);
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

function move = local_empty_move(componentCount)
move = struct('attempted',zeros(1,5),'accepted',zeros(1,5), ...
    'esjdSum',zeros(1,5),'pcnAttempted',zeros(1,5), ...
    'pcnAccepted',zeros(1,5),'globalSubAttempted',zeros(1,2), ...
    'globalSubAccepted',zeros(1,2), ...
    'independentComponentAttempted',zeros(1,componentCount), ...
    'independentComponentAccepted',zeros(1,componentCount), ...
    'dllCount',0,'dllRuntime_s',0);
end

function value = local_adapt_scale(value,acceptance,kernel,options)
value = value*exp(options.pcnAdaptGain* ...
    (acceptance-options.targetAcceptance(kernel)));
value = min(options.maximumPcnScale(kernel), ...
    max(options.minimumPcnScale(kernel),value));
end

function value = local_global_null_scale(rho,options)
value = min(options.maximumGlobalNullScale, ...
    options.globalNullScaleMultiplier*rho);
value = max(value,options.minimumPcnScale(5));
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
logValue = log(max(weights,realmin))+deltaBeta*bridgeScore;
maximum = max(logValue);
if ~isfinite(maximum)
    error('SHT:SteadyUQB:AllWeightsInvalid', ...
        '当前几何桥推进后全部粒子权重无效。');
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

function [theta,latent,logPrior,logPriorLatent,logQ] = ...
        local_refresh_prior_only(theta,latent,prior,guidedProposal, ...
        densityWeight,index,logPrior,logPriorLatent,logQ)
if isempty(index), return; end
latent(index,:) = randn(numel(index),size(latent,2));
theta = sht_steady_model_uq_sampler('latenttotheta',prior,latent);
logPrior = sht_steady_model_uq_sampler('logprior',prior,theta);
logPriorLatent = sht_steady_model_uq_b_proposal('logpriorlatent',latent);
logQ = sht_steady_model_uq_b_proposal( ...
    'logdensity',guidedProposal,latent,densityWeight);
end

function [weights,logMeanWeight] = local_normalize_log_weights(logWeight)
maximum = max(logWeight);
if ~isfinite(maximum)
    error('SHT:SteadyUQB:InvalidImportanceWeights', ...
        '全部重要性权重均无效。');
end
raw = exp(logWeight-maximum);
weights = raw/sum(raw);
logMeanWeight = maximum+log(sum(raw))-log(numel(raw));
end

function record = local_empty_stage()
record = struct('index',0,'beta',NaN,'delta_beta',NaN, ...
    'conditional_ess',NaN,'pcn_scale_before',nan(1,5), ...
    'reference_frozen_within_stage',false,'net_mean_squared_move',NaN, ...
    'ess_before_resample',NaN,'ess_after_resample',NaN, ...
    'resampled',false,'pcn_scale_after_adaptation',nan(1,5), ...
    'kernel_attempted',zeros(1,5),'kernel_accepted',zeros(1,5), ...
    'kernel_acceptance',nan(1,5),'kernel_normalized_esjd',nan(1,5), ...
    'block_acceptance',nan(1,5), ...
    'global_subkernel_attempted',zeros(1,2), ...
    'global_subkernel_accepted',zeros(1,2), ...
    'global_subkernel_acceptance',nan(1,2), ...
    'guided_acceptance',NaN,'guided_component_attempted',zeros(1,2), ...
    'guided_component_accepted',zeros(1,2), ...
    'guided_component_acceptance',nan(1,2), ...
    'valid_fraction',NaN,'unique_ancestor_count',0,'move_sweeps',0, ...
    'proposal_budget_expected',0,'proposal_budget_actual',0);
end

function exact=local_evaluate(contract,theta,options)
% 解析小例题可注入无DLL求值器；业务合同不含此字段，始终走B精确回放。
if isfield(contract,'evaluateFunction')
    exact=contract.evaluateFunction(theta);
else
    exact=sht_steady_model_uq_b_common('evaluate',contract,theta, ...
        contract.trainingData,struct('useCache',options.useCache));
end
end

function next=local_next_conditional_beta(beta,score,weights,fraction)
target=fraction*numel(weights);
if local_conditional_ess(weights,score,1-beta)>=target,next=1;return;end
lo=0;hi=1-beta;
for k=1:60
    mid=(lo+hi)/2;
    if local_conditional_ess(weights,score,mid)<target,hi=mid;else,lo=mid;end
end
assert(lo>eps(max(1,beta)),'TC24:B:ConditionalEssSupport', ...
    '当前有效似然支持不足以满足CESS目标；不能用强制温度跳跃掩盖。');
next=beta+lo;
end

function value=local_conditional_ess(weights,score,delta)
if delta==0,value=numel(weights);return;end
w=weights(:)/sum(weights);a=delta*score(:);a=a-max(a);
t=exp(a);value=numel(w)*sum(w.*t)^2/sum(w.*t.^2);
end

function value = local_option(options,name,defaultValue)
if isstruct(options) && isfield(options,name) && ~isempty(options.(name))
    value = options.(name);
else
    value = defaultValue;
end
end

function record=local_final_record(sweep,theta,weights,logLikelihood)
% 只记录当前总体的矩和等尾端点，不拼接历次总体，不虚增粒子数。
w=weights(:)/sum(weights);mu=theta*w;
sd=sqrt(sum((theta-mu).^2.*w.',2)/max(1-sum(w.^2),eps));
q=zeros(size(theta,1),2);
for j=1:size(theta,1)
    q(j,:)=sht_steady_model_uq_sampler('weightedquantile',theta(j,:),w,[.025 .975]);
end
record=struct('sweep',sweep,'mean',mu,'std',sd, ...
    'meanLogLikelihood',sum(w.*logLikelihood(:)),'q025',q(:,1),'q975',q(:,2));
end
