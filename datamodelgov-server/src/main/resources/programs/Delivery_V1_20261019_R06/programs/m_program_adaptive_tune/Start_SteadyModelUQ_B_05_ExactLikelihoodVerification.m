function result = Start_SteadyModelUQ_B_05_ExactLikelihoodVerification(userCfg)
%START_STEADYMODELUQ_B_05_EXACTLIKELIHOODVERIFICATION 精确验收B似然。
%
% 零参考点用于原似然核查；提议几何在最终选中位置重新计算。
% 两者分别记录。局部协方差只供提议使用，不替代先验或精确后验。
if nargin < 1, userCfg = struct(); end
if ischar(userCfg) && strcmp(userCfg,'testhooks')
    % 纯数值专项测试使用实际内部函数，不复制另一套几何算法。
    result=struct('build',@local_geometry_from_jacobian, ...
        'refine',@local_refine_proposal_geometry);
    return;
end
timer = tic;
preparationCodeIdentity=sht_tc24_uq_external_io('b','preparationidentity');
manifest = sht_steady_model_uq_b_io('resolvewritable',userCfg);
step1 = sht_steady_model_uq_b_io('loadstep',manifest,1);
step4 = sht_steady_model_uq_b_io('loadstep',manifest,4);
contract = step1.contract;
prior = step1.prior;
likelihood = sht_steady_model_uq_likelihood( ...
    'build',step4.measurement);
anchor = contract.referencePoint;
step = contract.parameterTable.difference_step;
step = min(step,0.20*min(anchor-contract.lowerBound, ...
    contract.upperBound-anchor));
if any(step <= 0)
    error('SHT:SteadyUQB:BadLikelihoodDifferenceStep', ...
        '方法B似然中心差分步长非正。');
end
retryCount = zeros(contract.parameterCount,1);
[candidate,exact] = local_evaluate_axis_pairs(contract,anchor,step);
for retry = 1:8
    failed = false(contract.parameterCount,1);
    for j = 1:contract.parameterCount
        failed(j) = ~(exact.valid(2*j) && exact.valid(2*j+1));
    end
    if ~any(failed), break; end
    step(failed) = 0.5*step(failed);
    retryCount(failed) = retryCount(failed)+1;
    [candidate,exact] = local_evaluate_axis_pairs(contract,anchor,step);
end
[logLikelihood,detail] = sht_steady_model_uq_likelihood( ...
    'evaluate',likelihood,exact.residual,exact.valid);
if any(~isfinite(logLikelihood))
    error('SHT:SteadyUQB:LikelihoodAxisVerificationFailed', ...
        '方法B递减差分后仍存在无效锚点或轴向候选。');
end
J = zeros(contract.observationDimension,contract.parameterCount);
for j = 1:contract.parameterCount
    J(:,j) = (exact.residual(:,2*j)-exact.residual(:,2*j+1))/(2*step(j));
end
zeroGeometry=local_geometry_from_jacobian(contract,prior,likelihood,anchor,J);
whitenedJ=zeroGeometry.whitenedJacobian;
priorPrecision=zeroGeometry.priorPrecision;
localCovariance=zeroGeometry.localCovariance;
anchorLatent=zeroGeometry.independentPriorLatent;
gradient = J.'*(likelihood.covariance\exact.residual(:,1)) + ...
    priorPrecision*(anchor-contract.priorMean);
thetaLocal = anchor-localCovariance*gradient;
margin = 1e-8*(contract.upperBound-contract.lowerBound);
thetaLocal = min(max(thetaLocal,contract.lowerBound+margin), ...
    contract.upperBound-margin);
localExact = sht_steady_model_uq_b_common('evaluate',contract,thetaLocal, ...
    contract.trainingData,struct('useCache',true));
[localLogLikelihood,localDetail] = sht_steady_model_uq_likelihood( ...
    'evaluate',likelihood,localExact.residual,localExact.valid);
anchorLogPrior = sht_steady_model_uq_sampler('logprior',prior,anchor);
localLogPrior = sht_steady_model_uq_sampler('logprior',prior,thetaLocal);
rawThetaLocal = thetaLocal;
rawLocalMahalanobisSquared = localDetail.mahalanobisSquared;
if ~localExact.valid || ...
        localLogLikelihood+localLogPrior < logLikelihood(1)+anchorLogPrior
    thetaLocal = anchor;
    localExact = local_exact_column(exact,1);
    localLogLikelihood = logLikelihood(1);
    localLogPrior = anchorLogPrior;
    localDetail.mahalanobisSquared = detail.mahalanobisSquared(1);
    selectedAnchorSource = 'zero_prior_center';
else
    selectedAnchorSource = 'one_step_from_zero_prior_center';
end
if contract.modelMode==0
    [dAnchor,dSource]=sht_tc24_uq_d_proposal_anchor(contract);
    if ~isempty(dAnchor)
        dExact=sht_steady_model_uq_b_common('evaluate',contract,dAnchor,contract.trainingData,struct('useCache',true));
        [dLL,dDetail]=sht_steady_model_uq_likelihood('evaluate',likelihood,dExact.residual,dExact.valid);
        dLP=sht_steady_model_uq_sampler('logprior',prior,dAnchor);
        if dLL+dLP>localLogLikelihood+localLogPrior
            thetaLocal=dAnchor;localExact=dExact;localLogLikelihood=dLL;
            localLogPrior=dLP;localDetail=dDetail;selectedAnchorSource=dSource;
        end
    end
end
[structuralPriorOnlyIndex,structuralPriorOnlyAudit] = ...
    local_audit_structural_prior_only( ...
    contract,anchor,thetaLocal,whitenedJ);
% 原结构性仅先验方向仍使用零点和原全边界证据；不能新增低敏感方向。
evaluate=@(points)sht_steady_model_uq_b_common('evaluate',contract,points, ...
    contract.trainingData,struct('useCache',true));
geometryLocation=thetaLocal;
if strcmp(contract.config.bProposalGeometryMode,'zero_reference')
    geometryLocation=zeroGeometry.anchor;
end
[geometry,geometryAudit]=local_refine_proposal_geometry( ...
    contract,prior,likelihood,geometryLocation,zeroGeometry,evaluate);
geometryAudit.configurationMode=contract.config.bProposalGeometryMode;
if geometryAudit.fallback
    warning('SHT:SteadyUQB:ProposalGeometryFallback', ...
        '新提议位置几何计算未完成，整套回退到零参考几何；原因：%s；失败索引：%s。', ...
        geometryAudit.fallbackReason,mat2str(geometryAudit.failedParameterIndex(:).'));
end
newNorm=sqrt(sum(geometry.whitenedJacobian(:,structuralPriorOnlyIndex).^2,1));
structuralConflictIndex=structuralPriorOnlyIndex(newNorm>1e-10);
if ~isempty(structuralConflictIndex)
    save(fullfile(manifest.runDir,'proposal_geometry_structural_conflict.mat'), ...
        'zeroGeometry','geometry','geometryAudit','structuralConflictIndex', ...
        'structuralPriorOnlyAudit','-v7.3');
    error('SHT:SteadyUQB:ProposalStructuralConflict', ...
        '新位置几何与原结构性先验方向冲突，索引%s；已保存证据，未完成B05。', ...
        mat2str(structuralConflictIndex(:).'));
end
J=geometry.jacobian;
whitenedJ=geometry.whitenedJacobian;
precision=geometry.localPrecision;
localCovariance=geometry.localCovariance;
latentTransformJacobian=geometry.latentTransformJacobian;
latentWhitenedJacobian=geometry.latentWhitenedJacobian;
latentSingularValues=geometry.latentSingularValues;
latentBasis=geometry.latentPcnBasis;
latentRank=geometry.latentInformedRank;
% 从活动参数中单独构造完整正交基。前activeLatentInformedRank列对应
% 局部受数据约束方向，其余列对应局部弱信息方向。后续跨块pCN在两类
% 方向上使用不同步长，避免SMC重采样把弱信息方向伪收缩成窄后验。
activeParameterIndex = setdiff((1:contract.parameterCount).', ...
    structuralPriorOnlyIndex,'stable');
activeLatentWhitenedJacobian = ...
    latentWhitenedJacobian(:,activeParameterIndex);
[~,activeLatentSingularMatrix,activeLatentPcnBasis] = ...
    svd(activeLatentWhitenedJacobian);
activeLatentSingularValues = diag(activeLatentSingularMatrix);
activeLatentInformedRank = rank(activeLatentWhitenedJacobian);
activeBasisOrthogonalityError = norm( ...
    activeLatentPcnBasis.'*activeLatentPcnBasis- ...
    eye(numel(activeParameterIndex)),'fro');
zeroResidualLog = sht_steady_model_uq_likelihood( ...
    'evaluate',likelihood,zeros(contract.observationDimension,1),true);
passed = abs(zeroResidualLog-likelihood.logNormalizingConstant) <= 1e-10 && ...
    all(isfinite(J(:))) && localExact.valid && ...
    latentRank <= min(contract.observationDimension,contract.parameterCount) && ...
    structuralPriorOnlyAudit.passed && activeBasisOrthogonalityError <= 1e-8;
if ~passed
    error('SHT:SteadyUQB:LikelihoodVerificationFailed', ...
        '方法B高斯似然、局部雅可比或局部参考点验收失败。');
end
result = struct('likelihood',likelihood,'differenceStep',step, ...
    'differenceRetryCount',retryCount,'anchor',anchor, ...
    'anchorCandidates',candidate,'anchorExact',exact, ...
    'anchorLogLikelihood',logLikelihood,'anchorDetail',detail, ...
    'jacobian',J,'whitenedJacobian',whitenedJ, ...
    'whitenedJacobianRank',rank(whitenedJ), ...
    'whitenedJacobianSingularValues',svd(whitenedJ,'econ'), ...
    'localPrecision',precision,'localCovariance',localCovariance, ...
    'anchorIndependentPriorLatent',anchorLatent, ...
    'latentTransformJacobian',latentTransformJacobian, ...
    'latentWhitenedJacobian',latentWhitenedJacobian, ...
    'latentSingularValues',latentSingularValues, ...
    'latentPcnBasis',latentBasis,'latentInformedRank',latentRank, ...
    'activeParameterIndex',activeParameterIndex, ...
    'activeLatentWhitenedJacobian',activeLatentWhitenedJacobian, ...
    'activeLatentSingularValues',activeLatentSingularValues, ...
    'activeLatentPcnBasis',activeLatentPcnBasis, ...
    'activeLatentInformedRank',activeLatentInformedRank, ...
    'activeBasisOrthogonalityError',activeBasisOrthogonalityError, ...
    'thetaLocal',thetaLocal,'localExact',localExact, ...
    'localLogLikelihood',localLogLikelihood, ...
    'localMahalanobisSquared',localDetail.mahalanobisSquared, ...
    'rawThetaLocal',rawThetaLocal, ...
    'rawLocalMahalanobisSquared',rawLocalMahalanobisSquared, ...
    'selectedAnchorSource',selectedAnchorSource,'passed',passed, ...
    'zeroReferenceGeometry',zeroGeometry, ...
    'geometryAnchor',geometry.anchor,'geometryAudit',geometryAudit, ...
    'geometryIndependentPriorLatent',geometry.independentPriorLatent, ...
    'structuralPriorOnlyParameterIndex',structuralPriorOnlyIndex, ...
    'structuralPriorOnlyAudit',structuralPriorOnlyAudit, ...
    'methodAPosteriorUsed',false,'truthRead',false,'testDataRead',false);
% 身份在真正计算之前取得，结束时再次核对；不为历史数值补签。
result.preparationCodeIdentity=preparationCodeIdentity;
sht_tc24_uq_external_io('b','checkpreparationidentity',result,'新计算的B05');
runtime = toc(timer);
[manifest,file] = sht_steady_model_uq_b_io( ...
    'savestep',manifest,5,'exact_likelihood_verification',result,runtime);
fprintf(['[2.4UQ-B.5] 似然检查：J=%dx%d，数值秩=%d，零中心D2=%.3f，' ...
    '局部参考D2=%.3f，差分候选=%d。\n'],size(J,1),size(J,2), ...
    rank(whitenedJ),detail.mahalanobisSquared(1), ...
    localDetail.mahalanobisSquared,size(candidate,2));
fprintf('[2.4UQ-B.5] 局部参考来源：%s；产物：%s\n', ...
    selectedAnchorSource,file);
fprintf('[2.4UQ-B.5] 提议几何：%s；新增候选=%d，缓存命中=%d，未缓存候选=%d。\n', ...
    geometryAudit.source,geometryAudit.candidateEvaluationCount, ...
    geometryAudit.cacheHitCount,geometryAudit.uncachedCandidateCount);
fprintf(['[2.4UQ-B.5] 精确先验保留方向：%d个；全边界联合扰动' ...
    '最大残差变化=%.3e。\n'],numel(structuralPriorOnlyIndex), ...
    structuralPriorOnlyAudit.maximumResidualChangeNorm);
fprintf(['[2.4UQ-B.5] 活动潜空间：%d维，局部数值秩=%d，' ...
    '数值零空间维数=%d，基正交误差=%.3e。\n'], ...
    numel(activeParameterIndex),activeLatentInformedRank, ...
    numel(activeParameterIndex)-activeLatentInformedRank, ...
    activeBasisOrthogonalityError);
fprintf('  数值满秩不等于全部参数工程可辨识；B07另按先验尺度比较信息强弱。\n');
result.manifest = manifest;
end

function geometry=local_geometry_from_jacobian(contract,prior,likelihood,anchor,J)
% 所有供采样使用的派生量在同一个位置构造，避免新旧字段混用。
whitenedJ=likelihood.cholLower\J;
priorPrecision=contract.priorCovariance\eye(contract.parameterCount);
priorPrecision=.5*(priorPrecision+priorPrecision.');
precision=whitenedJ.'*whitenedJ+priorPrecision;
precision=.5*(precision+precision.');
[V,D]=eig(precision);value=real(diag(D));
value=max(value,1e-10*max(value));
covariance=V*diag(1./value)*V.';
covariance=.5*(covariance+covariance.');
[transform,latent]=local_prior_latent_jacobian(prior,anchor);
latentJ=whitenedJ*transform;
[~,S,basis]=svd(latentJ);
geometry=struct('anchor',anchor(:),'jacobian',J,'whitenedJacobian',whitenedJ, ...
    'priorPrecision',priorPrecision,'localPrecision',precision,'localCovariance',covariance, ...
    'independentPriorLatent',latent,'latentTransformJacobian',transform, ...
    'latentWhitenedJacobian',latentJ,'latentSingularValues',diag(S), ...
    'latentPcnBasis',basis,'latentInformedRank',rank(latentJ));
end

function [geometry,audit]=local_refine_proposal_geometry( ...
        contract,prior,likelihood,location,zeroGeometry,evaluate)
% 最大4次缩步，只重算失败列的新正负对，成功列不重复回放。
% 回退时整套使用零点几何，绝不拼接来自不同位置的Jacobian列。
n=contract.parameterCount;maxRetries=4;
geometry=zeroGeometry;
audit=struct('requestedAnchor',location(:),'actualAnchor',zeroGeometry.anchor, ...
    'source','zero_reference_reused','fallback',false,'fallbackReason','', ...
    'maximumRetries',maxRetries,'differenceStep',zeros(n,1), ...
    'retryCount',zeros(n,1),'failedParameterIndex',zeros(0,1), ...
    'candidateEvaluationCount',0,'cacheHitCount',0,'uncachedCandidateCount',0, ...
    'modelRuntimeSeconds',0,'nativeDLLCallCount',NaN, ...
    'countDefinition','Uncached parameter vectors; not native DLL ABI calls');
if isequal(location(:),zeroGeometry.anchor(:)),return;end
step=min(contract.parameterTable.difference_step(:), ...
    .20*min(location(:)-contract.lowerBound(:),contract.upperBound(:)-location(:)));
audit.differenceStep=step;
if any(~isfinite(step)|step<=0) || ...
        any(location(:)+step==location(:)|location(:)-step==location(:))
    audit.fallback=true;audit.source='zero_reference_fallback';
    audit.fallbackReason='No representable interior centered-difference step';
    return;
end
residual=nan(contract.observationDimension,2*n);valid=false(1,2*n);
failed=(1:n).';
for attempt=0:maxRetries
    if attempt>0
        step(failed)=.5*step(failed);
        audit.retryCount(failed)=audit.retryCount(failed)+1;
    end
    point=repmat(location(:),1,2*numel(failed));
    for k=1:numel(failed)
        j=failed(k);point(j,2*k-1)=location(j)+step(j);point(j,2*k)=location(j)-step(j);
    end
    if any(any(point<contract.lowerBound(:)|point>contract.upperBound(:))) || ...
            any(location(failed)+step(failed)==location(failed) | ...
            location(failed)-step(failed)==location(failed))
        audit.fallbackReason='Difference step left the representable interior';
        break;
    end
    exact=evaluate(point);
    audit.candidateEvaluationCount=audit.candidateEvaluationCount+size(point,2);
    audit.cacheHitCount=audit.cacheHitCount+exact.cacheHitCount;
    audit.uncachedCandidateCount=audit.uncachedCandidateCount+exact.dllEvaluationCount;
    if isfield(exact,'dllRuntime_s')
        audit.modelRuntimeSeconds=audit.modelRuntimeSeconds+exact.dllRuntime_s;
    end
    for k=1:numel(failed)
        slots=[2*failed(k)-1,2*failed(k)];sample=[2*k-1,2*k];
        residual(:,slots)=exact.residual(:,sample);
        valid(slots)=exact.valid(sample)&all(isfinite(exact.residual(:,sample)),1);
    end
    failed=find(~(valid(1:2:end)&valid(2:2:end))).';
    if isempty(failed),break;end
end
audit.differenceStep=step;audit.failedParameterIndex=failed(:);
if ~isempty(failed)
    audit.fallback=true;audit.source='zero_reference_fallback';
    if isempty(audit.fallbackReason),audit.fallbackReason='Finite retry budget exhausted';end
    return;
end
J=(residual(:,1:2:end)-residual(:,2:2:end))./(2*step.');
if any(~isfinite(J(:)))
    audit.fallback=true;audit.source='zero_reference_fallback';
    audit.fallbackReason='Nonfinite derivative';return;
end
geometry=local_geometry_from_jacobian(contract,prior,likelihood,location,J);
audit.actualAnchor=geometry.anchor;audit.source='selected_location_relinearized';
end

function [priorOnlyIndex,audit] = local_audit_structural_prior_only( ...
        contract,anchor,localPoint,whitenedJacobian)
% 只有局部导数严格为零且全边界联合扰动仍不改变残差的方向，才允许
% 在SMC中解析保留原先验。该判定不依赖参数名称，避免把弱敏感误当无关。
columnNorm = sqrt(sum(whitenedJacobian.^2,1));
locallyZeroIndex = find(columnNorm <= 1e-12).';
priorIndependent = false(size(locallyZeroIndex));
allIndex = (1:contract.parameterCount).';
for i = 1:numel(locallyZeroIndex)
    other = setdiff(allIndex,locallyZeroIndex(i));
    priorIndependent(i) = all(abs(contract.priorCorrelation( ...
        locallyZeroIndex(i),other)) <= 1e-14);
end
candidateIndex = locallyZeroIndex(priorIndependent);
excludedCorrelatedIndex = locallyZeroIndex(~priorIndependent);
if isempty(candidateIndex)
    priorOnlyIndex = zeros(0,1);
    audit = struct('locallyZeroParameterIndex',locallyZeroIndex(:), ...
        'excludedDueToPriorCorrelation',excludedCorrelatedIndex(:), ...
        'candidateParameterIndex',candidateIndex, ...
        'candidateCIndex',zeros(0,1),'candidateCount',0, ...
        'allCandidatesValid',true,'residualChangeNorm',zeros(0,1), ...
        'maximumResidualChangeNorm',0,'tolerance',1e-10, ...
        'passed',true);
    return;
end

previousState = rng;
cleanupObject = onCleanup(@() rng(previousState));
rng(contract.config.randomSeed+5001,'twister');
theta = repmat(anchor,1,6);
theta(candidateIndex,2) = contract.lowerBound(candidateIndex);
theta(candidateIndex,3) = contract.upperBound(candidateIndex);
theta(candidateIndex,4) = contract.lowerBound(candidateIndex) + ...
    (contract.upperBound(candidateIndex)-contract.lowerBound(candidateIndex)) ...
    .*rand(numel(candidateIndex),1);
theta(:,5) = localPoint;
theta(:,6) = localPoint;
theta(candidateIndex,6) = contract.lowerBound(candidateIndex) + ...
    (contract.upperBound(candidateIndex)-contract.lowerBound(candidateIndex)) ...
    .*rand(numel(candidateIndex),1);
exact = sht_steady_model_uq_b_common('evaluate',contract,theta, ...
    contract.trainingData,struct('useCache',true));
changeNorm = [norm(exact.residual(:,2)-exact.residual(:,1)); ...
    norm(exact.residual(:,3)-exact.residual(:,1)); ...
    norm(exact.residual(:,4)-exact.residual(:,1)); ...
    norm(exact.residual(:,6)-exact.residual(:,5))];
tolerance = 1e-10*max(1,norm(exact.residual(:,1)));
independent = all(exact.valid) && all(changeNorm <= tolerance);
if independent
    priorOnlyIndex = candidateIndex(:);
else
    priorOnlyIndex = zeros(0,1);
end
audit = struct('locallyZeroParameterIndex',locallyZeroIndex(:), ...
    'excludedDueToPriorCorrelation',excludedCorrelatedIndex(:), ...
    'candidateParameterIndex',candidateIndex(:), ...
    'candidateCIndex',contract.parameterTable.c_index(candidateIndex), ...
    'candidateCount',numel(candidateIndex), ...
    'allCandidatesValid',all(exact.valid), ...
    'residualChangeNorm',changeNorm, ...
    'maximumResidualChangeNorm',max(changeNorm), ...
    'tolerance',tolerance,'passed',isempty(candidateIndex) || independent);
clear cleanupObject;
end

function [candidate,exact] = local_evaluate_axis_pairs(contract,anchor,step)
candidate = zeros(contract.parameterCount,1+2*contract.parameterCount);
candidate(:,1) = anchor;
for j = 1:contract.parameterCount
    candidate(:,2*j) = anchor;
    candidate(j,2*j) = candidate(j,2*j)+step(j);
    candidate(:,2*j+1) = anchor;
    candidate(j,2*j+1) = candidate(j,2*j+1)-step(j);
end
exact = sht_steady_model_uq_b_common('evaluate',contract,candidate, ...
    contract.trainingData,struct('useCache',true));
end

function output = local_exact_column(exact,index)
output = exact;
output.theta = exact.theta(:,index);
output.residual = exact.residual(:,index);
output.valid = exact.valid(index);
output.prediction = exact.prediction(index);
output.insideBounds = exact.insideBounds(index);
output.candidateCount = 1;
output.cacheHitCount = double(index<=exact.cacheHitCount);
output.dllEvaluationCount = 0;
end

function [transform,latent] = local_prior_latent_jacobian(prior,theta)
latent = sht_steady_model_uq_sampler('thetatolatent',prior,theta);
correlatedLatent = prior.cholCorrelation*latent;
zMarginal = (theta-prior.mean)./prior.sigma;
phiCorrelated = exp(-0.5*correlatedLatent.^2)/sqrt(2*pi);
phiMarginal = max(exp(-0.5*zMarginal.^2)/sqrt(2*pi),realmin);
diagonal = prior.sigma.*prior.normalization.*phiCorrelated./phiMarginal;
transform = diag(diagonal)*prior.cholCorrelation;
end
