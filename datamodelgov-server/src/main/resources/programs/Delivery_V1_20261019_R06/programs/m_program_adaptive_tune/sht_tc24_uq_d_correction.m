function result=sht_tc24_uq_d_correction(contract,prior,likelihood,result,options)
% 用同一个非线性概率目标校正局部样本；不改变先验，不利用验证真值。
% q是现有有界二次近似，未知截断归一化常数在自归一化权重中抵消。
% 该结果仍是有限局部提议的重要性近似，不升级为全局SMC后验。
theta=result.formal.theta;scale=prior.sigma(:);n=size(theta,2);
if isfield(options,'evaluateFunction'),exact=options.evaluateFunction(theta);
else,exact=sht_steady_model_uq_c_common('evaluate',contract,theta,contract.trainingData, ...
        struct('useCache',true,'useRobustTransientFallback',true));end
logTarget=sht_steady_model_uq_likelihood('evaluate',likelihood,exact.residual,exact.valid) ...
    +sht_steady_model_uq_sampler('logprior',prior,theta);
z=(theta-result.quadraticCenter)./scale;
logQ=-.5*sum(z.*(result.scaledHessian*z),1);
logWeight=logTarget-logQ;assert(any(isfinite(logWeight)),'TC24:D:Correction','无有限校正权重。');
w=exp(logWeight-max(logWeight));w=w(:)/sum(w);
ess=1/sum(w.^2);maximum=max(w);
% 方差/权重诊断不假称独立样本ESS，不因低ESS丢失原始校正候选。
stable=ess>=max(64,.15*n) && maximum<.1 && result.samplingStable;
weighted=result.formal;weighted.weights=w;
weighted.logLikelihood=sht_steady_model_uq_likelihood('evaluate',likelihood,exact.residual,exact.valid);
weighted.logPrior=sht_steady_model_uq_sampler('logprior',prior,theta);
weighted.samplingMethod='bounded_local_importance_nonlinear_correction';
weighted.formalGlobalPosterior=false;
result.uncorrectedFormal=result.formal;result.uncorrectedSummary=result.summary;
result.correctedFormal=weighted;
result.correctedSummary=sht_steady_model_uq_sampler('summary',theta,w,contract);
delta=logWeight(isfinite(logWeight));delta=delta-median(delta);
result.nonlinearCorrection=struct('weightESS',ess,'maximumWeight',maximum, ...
    'stable',stable,'sampleCount',n,'logRatioRange',max(delta)-min(delta), ...
    'invalidCandidates',nnz(~exact.valid),'logWeights',logWeight, ...
    'truthRead',false,'testRead',false,'globalConvergenceClaimed',false);
result.dllEvaluationCount=result.dllEvaluationCount+exact.dllEvaluationCount;
if stable
    result.formal=weighted;result.summary=result.correctedSummary;
    result.localMean=theta*w;result.quality='LOCAL_IMPORTANCE_CORRECTED';
end
fprintf('TC24-D nonlinear correction: weight ESS %.1f/%d, max weight %.4f, selected=%d.\n', ...
    ess,n,maximum,stable);
end
