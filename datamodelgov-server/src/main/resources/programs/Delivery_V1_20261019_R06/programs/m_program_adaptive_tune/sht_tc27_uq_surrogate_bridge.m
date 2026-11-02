function C=sht_tc27_uq_surrogate_bridge(c,target,D,evaluate,proposal,J,V,singular)
%SHT_TC27_UQ_SURROGATE_BRIDGE 当前合同训练代理，再渐进校正到同一DLL目标。
% 不读取任何旧后验或测试集。所有训练/加密点由本入口按固定种子产生；
% 相同物理身份的逐点缓存只减少重复回放，不改变候选生成或随机状态。
assert(isempty(c.histories)&&c.options.cBoundedNuisance,'本批桥接仅实现有界附加参数的稳态C。');
seed=c.options.randomSeed;a=c.options.cSurrogateLikelihoodPower;
dataFile=fullfile(c.directory,'C_bridge_training.mat');
if isfile(dataFile),q=load(dataFile,'training','blind');training=q.training;blind=q.blind;
else
    theta=sht_steady_model_uq_b_proposal('sample',proposal,c.options.surrogateTrainingCount,seed+100,'deterministic_mixture');
    theta=[theta,zeros(c.parameterCount,1),c.thetaHat,D.map];
    [~,q]=unique(theta.','rows','stable');theta=theta(:,q);r=evaluate(theta);
    training=struct('theta',theta(:,r.valid),'residual',r.residual(:,r.valid));
    theta=sht_steady_model_uq_b_proposal('sample',proposal,c.options.blindCount,seed+101,'fixed_count');
    assert(~any(ismember(theta.',training.theta.','rows')),'盲测与训练点重复。');r=evaluate(theta);
    blind=struct('theta',theta(:,r.valid),'residual',r.residual(:,r.valid));
    save(dataFile,'training','blind','-v7.3');
end
opts=struct('blockBasis',{{}},'blockInformedRank',zeros(4,1),'globalBasis',V, ...
    'globalInformedRank',nnz(singular>1),'particleCount',c.options.particleCount, ...
    'moveSweeps',4,'finalMoveSweeps',c.options.cFinalMoveSweeps, ...
    'blockSingularValues',{{}},'globalSingularValues',singular,'adaptFinalScales',false, ...
    'initialPcnScale',.5*ones(1,5),'minimumPcnScale',1e-6*ones(1,5),'maximumPcnScale',.95*ones(1,5));
geometry=struct('blocks',{c.parameterBlockIndex},'basis',{{}},'singular',{{}});
for k=1:4
    rows=c.parameterBlockIndex{k};[~,sb,vb]=svd(J(:,rows),'econ');
    opts.blockBasis{k}=vb;opts.blockSingularValues{k}=diag(sb);opts.blockInformedRank(k)=nnz(diag(sb)>1);
    geometry.basis{k}=vb;geometry.singular{k}=diag(sb);
end
geometry.basis{5}=V;geometry.singular{5}=singular;
diagnostics=cell(2,1);
for round=0:1
    file=fullfile(c.directory,sprintf('C_bridge_proxy_round%d.mat',round));
    if isfile(file),q=load(file,'surrogate','smc','one');surrogate=q.surrogate;smc=q.smc;one=q.one;
    else
        white=sht_tc27_uq_whiten(target,training.residual);
        surrogate=sht_tc27_uq_surrogate('fit',c,training.theta,white,D);
        surrogate.boxGain=target.conditionalGain*surrogate.basis;
        surrogate.boxStd=sqrt(diag(target.conditionalCovariance));
        surrogate.boxLower=target.lower;surrogate.boxUpper=target.upper;
        b=proxy(blind.theta);e=exact(blind.theta);err=e.logLikelihood-b;
        one=struct('round',round,'trainingCount',size(training.theta,2),'blindCount',numel(err), ...
            'blindMeanLogError',mean(err),'blindCenteredMedian',median(abs(err-median(err))), ...
            'blindStdLogError',std(err),'blindMaxCentered',max(abs(err-median(err))), ...
            'usedTruth',false,'usedTest',false,'usedOldPosterior',false);
        fprintf('能量GP轮%d：训练%d，独立盲测%d，中心化logL误差中位%.3g/std %.3g。\n', ...
            round,one.trainingCount,one.blindCount,one.blindCenteredMedian,one.blindStdLogError);
        sc=c;sc.contractHash=sht_tc27_uq_hash(struct('base',c.contractHash,'round',round,'training',training));
        sc.evaluateFunction=@proxyResidual;opts.randomSeed=seed+200+round;
        m=size(surrogate.basis,2)+1;
        likelihood=struct('dimension',m,'cholLower',speye(m),'logNormalizingConstant',0);
        smc=sht_tc27_uq_smc(sc,c.prior,likelihood,proposal,opts);
        save(file,'surrogate','smc','one','-v7.3');
    end
    diagnostics{round+1}=one;
    if round==0
        file=fullfile(c.directory,'C_bridge_training_refined.mat');
        if isfile(file),q=load(file,'training');training=q.training;
        else
            theta=sht_steady_model_uq_sampler('resample',smc.theta,smc.weights,c.options.cBridgeRefinementCount,seed+301);
            r=evaluate(theta);training.theta=[training.theta,theta(:,r.valid)];
            training.residual=[training.residual,r.residual(:,r.valid)];
            [~,q]=unique(training.theta.','rows','stable');training.theta=training.theta(:,q);training.residual=training.residual(:,q);
            save(file,'training','-v7.3');
        end
    end
end
theta=sht_steady_model_uq_sampler('resample',smc.theta,smc.weights,c.options.cBridgeParticles,seed+401);
initial=struct('theta',theta,'weights',ones(1,size(theta,2))/size(theta,2));
o=struct('seed',seed+402,'power',a,'moveSweeps',c.options.cBridgeMoveSweeps, ...
    'finalSweeps',c.options.cBridgeFinalSweeps,'maximumStages',c.options.cBridgeMaximumStages, ...
    'bypass',c.options.cBridgeBypassProbability);
r=sht_tc27_uq_da_bridge(c,initial,@proxy,@exact,geometry,o);
save(fullfile(c.directory,'C_surrogate_bridge_result.mat'),'r','-v7.3');
accept=sum(vertcat(r.stages.accepted),1)./max(sum(vertcat(r.stages.attempted),1),1);
C=struct('theta',r.theta,'weights',r.weights,'exactResidual',r.exactResidual,'exactValid',r.exactValid, ...
    'effectiveSampleSize',r.effectiveSampleSize,'distinctSampleCount',r.distinctSampleCount, ...
    'distinctSupportWeightESS',r.distinctSupportWeightESS,'smcFinalBeta',r.gamma, ...
    'smcStageCount',numel(r.stages),'smcKernelAcceptance',accept, ...
    'quality','SURROGATE_BRIDGED_DLL_FINITE_PARTICLE_POSTERIOR', ...
    'samplingBackend','surrogate_first_delayed_acceptance_bridge','surrogateUsed',true, ...
    'deltaLogLikelihood',r.logLikelihood-r.proxyLogLikelihood,'fixedCountCorrectionCompleted',true, ...
    'plannedCorrectionCount',size(r.theta,2),'bridgeResult',r,'roundDiagnostics',{diagnostics});
fprintf('代理桥C完成：ESS %.1f/%d，互异支撑ESS %.1f，桥接候选%d、需DLL筛查%d。\n', ...
    r.effectiveSampleSize,numel(r.weights),r.distinctSupportWeightESS,r.attempted,r.screenPassed);
    function out=proxyResidual(theta)
        out=sht_tc27_uq_surrogate('predict',surrogate,theta);out.residual=sqrt(a)*out.residual;
    end
    function logL=proxy(theta)
        q=sht_tc27_uq_surrogate('predict',surrogate,theta);logL=-.5*sum(q.residual.^2,1);
    end
    function out=exact(theta)
        out=evaluate(theta);q=sht_tc27_uq_bounded_target('evaluate',target,out.residual);
        % 省去相同的高斯常数和先验矩形概率常数；均与theta无关。
        out.logLikelihood=q.logLikelihood+target.logPriorBox;
        out.logLikelihood(~out.valid)=-Inf;
    end
end
