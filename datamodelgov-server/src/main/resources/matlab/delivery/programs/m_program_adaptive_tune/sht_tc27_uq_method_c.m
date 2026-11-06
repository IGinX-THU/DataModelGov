function C=sht_tc27_uq_method_c(c,covariance,D,evaluate,runControl)
%SHT_TC27_UQ_METHOD_C 稳态C支持代理渐进桥接/直接DLL/旧代理三种后端。
% 先验防御分量保留全域支持。精确校正只修正当前目标，不修复错误的
% 测量/附加参数假设。ESS是权重指标，不冒充MCMC独立样本数或覆盖保证。
timer=tic;seed=c.options.randomSeed;
if nargin<5,runControl=[];end
bounded=c.options.cBoundedNuisance;
if bounded
    originalCovariance=covariance;
    covariance=sht_tc27_uq_bounded_target('build',c,covariance);
    boundedTarget=covariance;save(fullfile(c.directory,'C_bounded_target.mat'),'boundedTarget','-v7.3');
    % D只提供初值。把其Jacobian恢复到物理单位，再对白化目标变换，
    % 避免将D的截断矩高斯近似直接当成C的新目标。
    z=D.physicalJacobian;
    z=z+originalCovariance.U*((originalCovariance.shrink./(1-originalCovariance.shrink)).*(originalCovariance.U.'*z));
    rawJ=sht_tc27_uq_base_transform(originalCovariance,z,true);
    D.physicalJacobian=sht_tc27_uq_whiten(covariance,rawJ,false);
    ref=evaluate(D.map);D.finalExact.residual=sht_tc27_uq_whiten(covariance,ref.residual);
end
center=min(max(D.map,c.lowerBound+1e-9*c.priorSigma),c.upperBound-1e-9*c.priorSigma);
z0=sht_steady_model_uq_sampler('thetatolatent',c.prior,center);n=c.parameterCount;
transform=zeros(n);
for j=1:n,zp=z0;zm=z0;zp(j)=zp(j)+1e-4;zm(j)=zm(j)-1e-4;
    transform(:,j)=(sht_steady_model_uq_sampler('latenttotheta',c.prior,zp)- ...
        sht_steady_model_uq_sampler('latenttotheta',c.prior,zm))/2e-4;end
J=D.physicalJacobian*transform;[~,S,V]=svd(J,'econ');singular=diag(S);
geometry=struct('activeParameterIndex',(1:n).','structuralPriorOnlyParameterIndex',zeros(0,1), ...
    'activeLatentPcnBasis',V,'activeLatentInformedRank',nnz(singular>1), ...
    'activeLatentSingularValues',singular,'thetaLocal',center);
proposal=sht_steady_model_uq_b_proposal('build',c.prior,geometry, ...
    struct('priorWeight',.20,'informedScaleInflation',1.5,'minimumInformedScale',.002));
if strcmp(c.observationMode,'steady_points')&&strcmp(c.options.steadyCBackend,'surrogate_bridge')
    C=sht_tc27_uq_surrogate_bridge(c,covariance,D,evaluate,proposal,J,V,singular);
    rounds=C.roundDiagnostics;
elseif strcmp(c.observationMode,'steady_points')&&strcmp(c.options.steadyCBackend,'direct_dll')
    % 稳态候选直接求解气热平衡。先验、协方差和有界边缘似然不变，
    % 不建立GP/POD、不训练历程代理，也不作末端代理误差重加权。
    C=sht_tc27_uq_direct_c(c,covariance,evaluate,proposal,J,V,singular,runControl);
    rounds={};
else
[trainingTheta,~]=sht_steady_model_uq_b_proposal('sample',proposal,c.options.surrogateTrainingCount,seed+100,'deterministic_mixture');
training=evaluate(trainingTheta);trainingTheta=trainingTheta(:,training.valid);
white=sht_tc27_uq_whiten(covariance,training.residual(:,training.valid));
% 已有物理参考点也参加训练，尤其约束MAP附近的非线性余项为实际值；
% 这不引入真值，也不改变先验。三点回放通常已在D/协方差阶段缓存。
anchors=[zeros(n,1),c.thetaHat,D.map];anchorExact=evaluate(anchors);
trainingTheta=[trainingTheta,anchors(:,anchorExact.valid)];
white=[white,sht_tc27_uq_whiten(covariance,anchorExact.residual(:,anchorExact.valid))];
[~,keep]=unique(trainingTheta.','rows','stable');trainingTheta=trainingTheta(:,keep);white=white(:,keep);
% 盲测集种子独立，首次训练绝不使用盲测误差进行输出拟合。
[blindTheta,~]=sht_steady_model_uq_b_proposal('sample',proposal,c.options.blindCount,seed+101,'fixed_count');
assert(~any(ismember(blindTheta.',trainingTheta.','rows')), ...
    'TC27:UQ:BlindOverlap','独立盲测点与训练点重合。');
blindExact=evaluate(blindTheta);blindWhite=sht_tc27_uq_whiten(covariance,blindExact.residual);
blindLog=-.5*sum(blindWhite.^2,1);
if bounded
    b=sht_tc27_uq_bounded_target('evaluate',covariance,blindExact.residual);
    blindLog=b.logLikelihood+covariance.logPriorBox;
end
rounds=cell(c.options.maxRefinementRounds+1,1);bestScore=-Inf;
for round=0:c.options.maxRefinementRounds
    surrogateFile=fullfile(c.directory,sprintf('surrogate_round%d.mat',round));
    if isfile(surrogateFile),q=load(surrogateFile,'surrogate');surrogate=q.surrogate;
    else
        surrogate=sht_tc27_uq_surrogate('fit',c,trainingTheta,white,D);
        if bounded
            surrogate.boxGain=covariance.conditionalGain*surrogate.basis;
            surrogate.boxStd=sqrt(diag(covariance.conditionalCovariance));
            surrogate.boxLower=covariance.lower;surrogate.boxUpper=covariance.upper;
        end
        save(surrogateFile,'surrogate','-v7.3');
    end
    proxyBlind=sht_tc27_uq_surrogate('predict',surrogate,blindTheta);
    deltaBlind=blindLog+.5*sum(proxyBlind.residual.^2,1);
    good=blindExact.valid;blindAudit=struct('validCount',nnz(good),'sampleCount',numel(good), ...
        'medianAbsDeltaLogLikelihood',median(abs(deltaBlind(good))), ...
        'maximumAbsDeltaLogLikelihood',max(abs(deltaBlind(good))),'usedForTraining',false);
    dz=surrogate.basis*proxyBlind.residual(1:size(surrogate.basis,2),good)-blindWhite(:,good);
    dz=dz+covariance.U*((covariance.shrink./(1-covariance.shrink)).*(covariance.U.'*dz));
    physicalError=sht_tc27_uq_base_transform(covariance,dz,true);
    blindAudit.physicalError=local_physical_error(c,physicalError);
    writetable(blindAudit.physicalError,fullfile(c.report,sprintf('C_round%d_blind_physical_error.csv',round)));
    smcContract=c;smcContract.contractHash=sht_tc27_uq_hash(struct('base',c.contractHash,'round',round, ...
        'training',sht_tc27_uq_hash(trainingTheta)));
    smcContract.evaluateFunction=@(theta)sht_tc27_uq_surrogate('predict',surrogate,theta);
    opts=struct('blockBasis',{{}},'blockInformedRank',zeros(4,1),'globalBasis',V, ...
        'globalInformedRank',nnz(singular>1),'particleCount',c.options.particleCount, ...
        'randomSeed',seed+200+round,'moveSweeps',4,'finalMoveSweeps',c.options.cFinalMoveSweeps, ...
        'blockSingularValues',{{}},'globalSingularValues',singular, ...
        'initialPcnScale',.5*ones(1,5),'minimumPcnScale',1e-6*ones(1,5), ...
        'maximumPcnScale',.95*ones(1,5));
    for k=1:4
        q=c.parameterBlockIndex{k};[~,sb,vb]=svd(J(:,q),'econ');
        opts.blockBasis{k}=vb;opts.blockInformedRank(k)=nnz(diag(sb)>1);
        opts.blockSingularValues{k}=diag(sb);
    end
    dimension=size(surrogate.basis,2)+double(bounded);
    model=struct('dimension',dimension,'cholLower',speye(dimension), ...
        'logNormalizingConstant',-.5*(covariance.logDet+numel(c.observed)*log(2*pi)));
    smc=sht_tc27_uq_smc(smcContract,c.prior,model,proposal,opts);
    % 按SMC权重抽取当前候选，再以精确似然/代理似然恢复同一C目标。
    theta=sht_steady_model_uq_sampler('resample',smc.theta,smc.weights, ...
        c.options.exactCorrectionCount,seed+300+round);
    % 状态无关的随机排列让先导批不受系统重采样的粒子顺序影响。
    theta=theta(:,randperm(size(theta,2)));
    proxy=sht_tc27_uq_surrogate('predict',surrogate,theta);
    exact=sht_tc27_uq_exact_correction(theta,proxy.residual,evaluate, ...
        @exactWhite,round<c.options.maxRefinementRounds);
    theta=exact.theta;w=sht_tc27_uq_whiten(covariance,exact.residual);
    logRatio=exact.logRatio;weight=exact.weights;ess=exact.effectiveSampleSize;
    [distinct,~,membership]=unique(theta.','rows');
    supportWeight=accumarray(membership,weight(:));supportESS=1/sum(supportWeight.^2);
    one=struct('round',round,'theta',theta,'weights',weight,'exactResidual',exact.residual, ...
        'exactValid',exact.valid,'effectiveSampleSize',ess,'smcFinalBeta',smc.finalBeta, ...
        'smcStageCount',smc.stageCount,'smcKernelAcceptance',smc.kernelAcceptance, ...
        'blindAudit',blindAudit,'deltaLogLikelihood',logRatio,'trainingCount',size(trainingTheta,2), ...
        'quality','EXACT_REWEIGHTED_C_APPROXIMATION_LIMITED_ESS');
    one.distinctSampleCount=size(distinct,1);one.distinctSupportWeightESS=supportESS;
    % 候选来自高概率域而非全先验。单独给出该处似然误差，不用
    % 全域物理RMSE替代后验区域代理质量，也不拿测试集调代理。
    one.posteriorRegionMedianAbsDeltaLogL=median(abs(logRatio(exact.valid)));
    one.posteriorRegionStdDeltaLogL=std(logRatio(exact.valid));
    one.fixedCountCorrectionCompleted=exact.complete;one.plannedCorrectionCount=exact.plannedCount;
    one.surrogateUniqueParticleFraction=size(unique(smc.theta.','rows'),1)/size(smc.theta,2);
    % 重复拷贝同一个点不能形成额外概率分辨率。质量标记同时检查
    % 重加权稳定性和互异支撑，仍不宣称全局峰覆盖或统计校准。
    if ~exact.complete,one.quality='REFINEMENT_PILOT_NOT_POSTERIOR';end
    if exact.complete&&ess>=max(32,.2*numel(weight))&&supportESS>=32&&smc.finalBeta>=1-1e-10
        one.quality='EXACT_REWEIGHTED_C_APPROXIMATION';
    end
    rounds{round+1}=one;save(fullfile(c.directory,sprintf('C_round%d.mat',round)),'one','-v7.3');
    fprintf('TC27-C轮%d: beta=%.6f, 精确有效%d/%d, 权重ESS=%.1f, 互异支撑ESS=%.1f, 盲测中位|delta logL|=%.3g。\n', ...
        round,smc.finalBeta,nnz(exact.valid),numel(weight),ess,supportESS,blindAudit.medianAbsDeltaLogLikelihood);
    score=min(ess,supportESS);
    if exact.complete&&score>bestScore,C=one;bestScore=score;end
    if strcmp(one.quality,'EXACT_REWEIGHTED_C_APPROXIMATION'),C=one;break;end
    % 只用于下一轮代理训练，不把旧轮后验点直接拼成最终后验。
    trainingTheta=[trainingTheta,theta(:,exact.valid)];white=[white,w(:,exact.valid)]; %#ok<AGROW>
    [~,uniqueIndex]=unique(trainingTheta.','rows','stable');trainingTheta=trainingTheta(:,uniqueIndex);white=white(:,uniqueIndex);
end
    C.samplingBackend='surrogate_smc_dll_reweighting';
    C.surrogateUsed=true;
end
C.method='C';C.contractHash=c.contractHash;C.formalGlobalPosterior=false;
C.statisticalCalibrationConfirmed=false;
C.approximation=['24_nuisance_',c.options.nuisanceAnchorMode,'_moment_marginalization'];
if bounded
    C.approximation='bounded_24_nuisance_local_affine_numerical_marginalization';
end
C.observationMode=c.observationMode;C.integrationStep_s=c.options.integrationStep_s;
C.roundDiagnostics=rounds;C.runtime_s=toc(timer);C.truthRead=false;C.testUsedForFit=false;
if C.surrogateUsed
    C.correctionAttemptCount=size(C.theta,2);C.correctionValidCount=nnz(C.exactValid);
else
    C.correctionAttemptCount=0;C.correctionValidCount=0;
end
positive=C.exactValid&C.weights>0;
C.theta=C.theta(:,positive);C.weights=C.weights(positive);C.weights=C.weights/sum(C.weights);
C.exactResidual=C.exactResidual(:,positive);C.exactValid=C.exactValid(positive);
C.deltaLogLikelihood=C.deltaLogLikelihood(positive);
if isfield(C,'directLogLikelihood'),C.directLogLikelihood=C.directLogLikelihood(positive);end
if bounded
    q=sht_tc27_uq_bounded_target('evaluate',covariance,C.exactResidual,true);
    C.boundedNuisance=q;C.nuisanceDraws=q.nuisanceDraws;
    C.boxIntegrationWeightedMeanAbsDeltaLog=sum(C.weights.*abs(q.integrationDeltaLog));
    C.boxIntegrationMaximumAbsDeltaLog=max(abs(q.integrationDeltaLog));
    if C.boxIntegrationWeightedMeanAbsDeltaLog>.1
        C.quality=[C.quality,'_BOX_INTEGRATION_REFINEMENT_NEEDED'];
    end
end
C.summary=sht_steady_model_uq_sampler('summary',C.theta,C.weights,c);
C.summary=sht_tc27_uq_empirical_summary(C.theta,C.weights,C.summary);
    function w=exactWhite(residual)
        w=sht_tc27_uq_whiten(covariance,residual);
        if bounded
            q=sht_tc27_uq_bounded_target('evaluate',covariance,residual);
            w=[w;sqrt(max(0,-2*q.logBoxProbability))];
        end
    end
end

function tableOut=local_physical_error(c,error)
tableOut=table();offset=0;sets=[height(c.trainingData),arrayfun(@(h)height(h.data),c.histories)];
for block=1:numel(sets)
    count=sets(block);names=c.historyNames;label=sprintf('history%d',block-1);
    if block==1,names=c.outputNames;label='steady_instant';end
    for j=1:9
        rows=offset+(j-1)*count+(1:count);v=error(rows,:);
        tableOut=[tableOut;table(string(label),string(names{j}),sqrt(mean(v(:).^2)),max(abs(v(:))), ...
            'VariableNames',{'block','output','RMSE','maximum_absolute_error'})]; %#ok<AGROW>
    end
    offset=offset+9*count;
end
end
