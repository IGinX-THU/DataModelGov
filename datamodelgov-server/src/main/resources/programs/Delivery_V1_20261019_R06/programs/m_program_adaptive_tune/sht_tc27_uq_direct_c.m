function C=sht_tc27_uq_direct_c(c,target,evaluate,proposal,J,V,singular,runControl)
%SHT_TC27_UQ_DIRECT_C 仅稳态点的直接DLL驱动SMC，无前向代理近似。
% 对每个候选分别求实际训练工况的气热平衡，再计算同一个有界附加参数
% 边缘似然。D的Jacobian仅决定提议尺度，不替代任一候选的物理响应。
% 附加参数的局部仿射近似和矩形数值积分仍存在，不能称为无近似UQ。
assert(strcmp(c.observationMode,'steady_points')&&isempty(c.histories), ...
    'TC27:UQ:DirectSteadyOnly','直接C入口要求仅稳态工况。');
if nargin<8,runControl=[];end
bounded=c.options.cBoundedNuisance;
contract=c;contract.evaluateFunction=@directEvaluate;
dimension=numel(c.observed)+double(bounded);
constant=-.5*(target.logDet+numel(c.observed)*log(2*pi));
if bounded,constant=constant-target.logPriorBox;end
likelihood=struct('dimension',dimension,'cholLower',speye(dimension), ...
    'logNormalizingConstant',constant);
options=struct('blockBasis',{{}},'blockInformedRank',zeros(4,1), ...
    'globalBasis',V,'globalInformedRank',nnz(singular>1), ...
    'blockSingularValues',{{}},'globalSingularValues',singular, ...
    'particleCount',c.options.particleCount,'randomSeed',c.options.randomSeed+200, ...
    'moveSweeps',c.options.cDirectMoveSweeps, ...
    'finalMoveSweeps',c.options.cDirectFinalMoveSweeps, ...
    'adaptFinalScales',false,'initialPcnScale',.5*ones(1,5), ...
    'minimumPcnScale',1e-6*ones(1,5),'maximumPcnScale',.95*ones(1,5));
options.samplerProfile=c.options.cSamplerProfile;
options.conditionalEssFraction=c.options.cConditionalEssFraction;
options.resampleEssFraction=c.options.cResampleEssFraction;
if strcmp(options.samplerProfile,'quality')
    options.kernelWeights=[.10,.10,.10,.10,.60];
    options.initialPcnScale=.7*ones(1,5);
    options.globalPcnFraction=.9;
end
if isfield(c.options,'cSamplingSeed') && ~isempty(c.options.cSamplingSeed)
    options.randomSeed=c.options.cSamplingSeed;
end
for k=1:4
    index=c.parameterBlockIndex{k};[~,S,B]=svd(J(:,index),'econ');
    options.blockBasis{k}=B;options.blockInformedRank(k)=nnz(diag(S)>1);
    options.blockSingularValues{k}=diag(S);
end
fprintf(['TC27-C稳态直接DLL-SMC：%d粒子，每层%d次移动，末层%d次；' ...
    '不建立代理、不进行代理校正。末层冻结提议尺度。\n'], ...
    options.particleCount,options.moveSweeps,options.finalMoveSweeps);
fprintf('采样配置=%s；粒子权重ESS不等于独立样本数或统计校准。\n',options.samplerProfile);
file=fullfile(c.directory,'C_direct_smc.mat');
% 完成结果也检查提议/数值后端身份，不能绕过底层SMC断点检查。
runIdentity=struct('contractHash',c.contractHash,'options',options, ...
    'matlabRelease',version('-release'),'architecture',computer('arch'), ...
    'proposalHash',sht_tc27_uq_proposal_identity(proposal), ...
    'smcSourceHash',sht_tc27_file_identity(fullfile(fileparts(mfilename('fullpath')),'sht_tc27_uq_smc.m')), ...
    'moveReferenceHash',sht_tc27_file_identity(fullfile(fileparts(mfilename('fullpath')),'sht_tc27_uq_move_reference.m')), ...
    'directSourceHash',sht_tc27_file_identity([mfilename('fullpath'),'.m']));
if isfile(file)
    saved=load(file,'smc');smc=saved.smc;
    assert(strcmp(smc.contractHash,c.contractHash),'直接SMC结果身份不匹配。');
    assert(isfield(smc,'runIdentity')&&isequaln(smc.runIdentity,runIdentity), ...
        'TC27:UQ:DirectResumeIdentity','直接SMC完成结果与当前提议/源码不一致，请使用新批次。');
else
    options.runControl=runControl;
    smc=sht_tc27_uq_smc(contract,c.prior,likelihood,proposal,options);
    smc.runIdentity=runIdentity;
    smc.contractHash=c.contractHash;save(file,'smc','-v7.3');
end
% 恢复物理量残差供冻结后的预测与审计使用。通常全部命中本合同缓存，
% 不把移动中拒绝的候选或上一轮后验混入本轮粒子。
raw=evaluate(smc.theta);assert(all(raw.valid),'最终粒子含无效DLL求值。');
weights=smc.weights/sum(smc.weights);
[distinct,~,membership]=unique(smc.theta.','rows');
mass=accumarray(membership,weights(:));
C=struct('theta',smc.theta,'weights',weights,'exactResidual',raw.residual, ...
    'exactValid',raw.valid,'effectiveSampleSize',1/sum(weights.^2), ...
    'distinctSampleCount',size(distinct,1),'distinctSupportWeightESS',1/sum(mass.^2), ...
    'smcFinalBeta',smc.finalBeta,'smcStageCount',smc.stageCount, ...
    'smcKernelAcceptance',smc.kernelAcceptance, ...
    'quality','DIRECT_DLL_SMC_FINITE_PARTICLE_POSTERIOR', ...
    'samplingBackend','direct_dll_smc','surrogateUsed',false, ...
    'deltaLogLikelihood',nan(size(weights)), ...
    'fixedCountCorrectionCompleted',false,'plannedCorrectionCount',0, ...
    'directLogLikelihood',smc.logLikelihood,'directGaussianConstant',constant, ...
    'directSMC',smc,'roundDiagnostics',{{}});
C.repeatabilityStatus='NOT_ESTABLISHED_BY_SINGLE_RUN';
C.monteCarloErrorEstimated=false;
% 权重ESS不是链ESS。完整移动统计、祖先数和互异支撑一并交付诊断；
% 到达beta=1只说明完成当前数值目标，不证明全局覆盖或95%统计校准。
if C.distinctSupportWeightESS<32
    C.quality=[C.quality,'_LIMITED_DISTINCT_SUPPORT'];
end
fprintf('TC27-C直接采样完成：beta=%.6f，权重ESS=%.1f/%d，互异支撑ESS=%.1f，祖先%d。\n', ...
    C.smcFinalBeta,C.effectiveSampleSize,numel(weights), ...
    C.distinctSupportWeightESS,smc.uniqueAncestorCount);
    function out=directEvaluate(theta)
        out=evaluate(theta);physical=out.residual;
        out.residual=sht_tc27_uq_whiten(target,physical);
        if bounded
            q=sht_tc27_uq_bounded_target('evaluate',target,physical);
            % 增广二次残差给出 exp(-0.5*sum(w.^2))*Pconditional。
            % Pprior与高斯归一化常数放在likelihood中。
            out.residual=[out.residual;sqrt(max(0,-2*q.logBoxProbability))];
            out.valid=out.valid&isfinite(q.logLikelihood);
        end
    end
end
