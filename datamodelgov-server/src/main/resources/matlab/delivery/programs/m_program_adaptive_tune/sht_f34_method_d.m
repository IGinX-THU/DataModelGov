function result=sht_f34_method_d(prepared,likelihood,userOptions,control)
%SHT_F34_METHOD_D 3.4方法D：MAP与局部Laplace/Gauss-Newton快速评估。
%
% 方法D与方法C使用同一先验和似然。它只把最终模态附近近似为高斯，
% 不进行后验Monte Carlo采样；边界、非对称性和多峰可能性由独立诊断
% 明示，不能把本结果冒充全局后验。

if nargin<3||isempty(userOptions),userOptions=struct();end
if nargin<4,control=[];end
sht_f34_contract('verifyImplementation',prepared.contract);
options=prepared.options;
names=fieldnames(userOptions);
for i=1:numel(names),options.(names{i})=userOptions.(names{i});end
context=prepared.context;prior=prepared.prior;
if ~isfield(likelihood,'implementationSha256')|| ...
        ~strcmp(likelihood.implementationSha256,sht_f33_model_adapt_v2( ...
        'fileHash',which('sht_f34_likelihood')))|| ...
        ~isfield(likelihood,'optionsSha256')|| ...
        ~strcmp(likelihood.optionsSha256,prepared.contract.optionsSha256)|| ...
        ~isfield(likelihood,'preparedContractSha256')|| ...
        ~strcmp(likelihood.preparedContractSha256,sht_f33_model_adapt_v2( ...
        'structHash',prepared.contract))
    error('SHT:F34MethodD:LikelihoodStale', ...
        '似然与当前程序或冻结配置不一致，请先重跑步骤01。');
end
cacheFile=local_cache_file(likelihood,prepared);
started=tic;
cacheBefore=sht_f34_likelihood('loadCache',likelihood,cacheFile);
cacheCleanup=onCleanup(@()sht_f34_likelihood( ...
    'saveCache',likelihood,cacheFile)); %#ok<NASGU>
parameter=prior.parameterTable;dimension=height(parameter);
[priorMean,priorCovariance]=sht_f34_prior('moments',prior);
scale=max(sqrt(diag(priorCovariance)),parameter.difference_step(:));
% 借鉴TC27：物理导数使用先验标准化的小步长，避免粗步长偏差支配驻点判据。
% 此尺度只影响数值导数，不改变先验或测量协方差。
fdStep=min(parameter.difference_step(:),1e-3*scale);
fdStep=max(fdStep,1e-5*scale);
derivativeParameter=parameter;derivativeParameter.difference_step=fdStep;
lower=(parameter.lower_bound-priorMean)./scale;
upper=(parameter.upper_bound-priorMean)./scale;
runIdentity=struct('prepared',prepared.contract,'likelihood',likelihood.contractHash, ...
    'physics',likelihood.physicsContractHash,'options',options, ...
    'source',sht_f33_model_adapt_v2('fileHash',[mfilename('fullpath'),'.m']), ...
    'priorSource',sht_f33_model_adapt_v2('fileHash',which('sht_f34_prior')), ...
    'release',version('-release'),'architecture',computer('arch'));
found=false;previousRuntime=0;completedIteration=0;
if ~isempty(control)
    [saved,found]=sht_tc24_run_control('load',control,'uq_D_iteration');
end
if found
    sht_f33_model_adapt_v2('checkpointpure',saved);
    assert(strcmp(saved.schema,'F34_D_SAFE_ITERATION_C4')&&isequaln(saved.identity,runIdentity), ...
        'SHT:F34D:CheckpointIdentity','D安全断点的源码、目标或算法配置改变；不能续签。');
    assert(isequaln(saved.scale,scale)&&isequaln(saved.fdStep,fdStep), ...
        'SHT:F34D:CheckpointScale','D标准化或差分尺度改变。');
    theta=saved.theta;z=saved.z;objective=saved.objective;current=saved.current;
    trustRadius=saved.trustRadius;trace=saved.trace;stopReason=saved.stopReason;
    completedIteration=saved.iteration;previousRuntime=saved.runtime_s;
    if isfield(context,'thermalSession')&&~isempty(saved.numericalCache)
        % 复用现有Map对象，让调用者和D/C看到相同的纯数值暖起点。
        target=context.thermalSession.cache;oldKeys=keys(target);
        if ~isempty(oldKeys),remove(target,oldKeys);end
        restored=sht_f33_model_adapt_v2('checkpointcache','restore',saved.numericalCache);
        newKeys=keys(restored);for k=1:numel(newKeys),target(newKeys{k})=restored(newKeys{k});end
    end
else

reference=context.uqReferenceResult;
if isfield(reference,'estimatedTheta')
    % 3.3结果仅提供优化初值；其同批飞行证据不会被再次写入3.4先验。
    deterministic=reference.estimatedTheta(:);
elseif isfield(reference,'finalTheta')
    deterministic=reference.finalTheta(:);
else
    deterministic=zeros(dimension,1);
end
startTheta=[min(max(deterministic,parameter.lower_bound),parameter.upper_bound), ...
    min(max(priorMean,parameter.lower_bound),parameter.upper_bound)];
% 允许从已完成的快速运行检查点继续，避免为改进驻点质量而重复
% 起点筛查。该点仍须和其他起点一样计算完整后验目标，不能直接接受。
if isfield(userOptions,'initialTheta')&& ...
        numel(userOptions.initialTheta)==dimension
    continued=min(max(userOptions.initialTheta(:), ...
        parameter.lower_bound),parameter.upper_bound);
    startTheta=[continued,startTheta];
end
[startObjective,startDetail]=local_objective( ...
    likelihood,context,prior,startTheta);
[objective,index]=min(startObjective);
theta=startTheta(:,index);z=(theta-priorMean)./scale;
current=startDetail(index);

fprintf('\n3.4.6 方法D快速评估：%d维，最多%d次迭代。\n', ...
    dimension,options.methodDMaximumIterations);
trustRadius=options.methodDTrustRadiusInitial;
trace=repmat(struct('iteration',0,'objective',NaN,'logLikelihood',NaN, ...
    'logPrior',NaN,'gradientNorm',NaN,'stepNorm',NaN,'trustRadius',NaN, ...
    'accepted',false,'lineFraction',NaN),options.methodDMaximumIterations,1);
stopReason='maximum_iterations';
end

iteration=completedIteration;
for iteration=completedIteration+1:options.methodDMaximumIterations
    if strcmp(stopReason,'gradient_small'),break;end
    gradient=local_forward_gradient(z,priorMean,scale,lower,upper, ...
        fdStep,likelihood,context,prior,objective);
    gradientNorm=norm(z-min(max(z-gradient,lower),upper),inf);
    % 梯度来自完整混合先验及参数相关似然。GN矩阵仅作正定数值预条件，
    % 不能把2.7固定协方差/单高斯先验的目标直接移植到这里。
    baseEval=sht_f34_likelihood('evaluate',likelihood,context,prior,theta);
    J=local_prediction_jacobian(theta,scale,derivativeParameter, ...
        likelihood,context,prior,baseEval.prediction);
    localPriorCov=local_prior_covariance(prior,theta);
    B=(J.'*(baseEval.covariance(:,:,1)\J)+(localPriorCov\eye(dimension))).*(scale*scale.');
    [B,~]=local_make_spd(B);
    accepted=false;stepNorm=0;lineFraction=1;
    if gradientNorm>options.methodDGradientTolerance
        regularizer=0;
        for attempt=1:12
            % 解完整的有界二次子问题，不先求无约束步再裁剪，也不乘更新比例。
            [direction,qp]=sht_steady_model_adapt_v2_common('m3boxquadraticsolve', ...
                B+regularizer*eye(dimension),gradient, ...
                max(lower-z,-trustRadius),min(upper-z,trustRadius),1e-8,20*dimension);
            if ~qp.passed,error('SHT:F34MethodD:QP','有界二次求解未满足KKT。');end
            nextZ=z+direction;trialTheta=priorMean+scale.*nextZ;
            [trialObjective,trialDetail]=local_objective(likelihood,context,prior,trialTheta);
            if isfinite(trialObjective)&&trialObjective<objective
                stepNorm=norm(direction,inf);z=nextZ;theta=trialTheta;
                objective=trialObjective;current=trialDetail;accepted=true;
                trustRadius=min(options.methodDTrustRadiusMaximum,1.5*trustRadius);
                break;
            end
            trustRadius=max(1e-6,0.5*trustRadius);
            regularizer=max(1e-4,4*max(regularizer,1e-4));
        end
    end
    trace(iteration)=struct('iteration',iteration,'objective',objective, ...
        'logLikelihood',current.logLikelihood,'logPrior',current.logPrior, ...
        'gradientNorm',gradientNorm,'stepNorm',stepNorm, ...
        'trustRadius',trustRadius,'accepted',accepted, ...
        'lineFraction',lineFraction);
    fprintf('  D iter %2d: Phi=% .6e, ||g||inf=%.3g, step=%.3g, accept=%d\n', ...
        iteration,objective,gradientNorm,stepNorm,accepted);
    progress=struct('theta',theta,'trace',trace(1:iteration), ...
        'likelihoodContractHash',likelihood.contractHash, ...
        'implementationSha256',sht_f33_model_adapt_v2('fileHash',[mfilename('fullpath'),'.m']), ...
        'optionsSha256',prepared.contract.optionsSha256, ...
        'status','restart_point_only_not_completed_posterior'); %#ok<NASGU>
    save([prepared.paths.methodDFile,'.progress.mat'],'progress','-v7.3');
    sht_f34_likelihood('saveCache',likelihood,cacheFile);
    if gradientNorm<=options.methodDGradientTolerance,stopReason='gradient_small';end
    completedIteration=iteration;
    if ~isempty(control)
        numericalCache=[];
        if isfield(context,'thermalSession')
            numericalCache=sht_f33_model_adapt_v2('checkpointcache','save',context.thermalSession.cache);
        end
        state=struct('schema','F34_D_SAFE_ITERATION_C4','identity',runIdentity, ...
            'theta',theta,'z',z,'objective',objective,'current',current, ...
            'scale',scale,'fdStep',fdStep,'trustRadius',trustRadius,'trace',trace, ...
            'iteration',iteration,'stopReason',stopReason,'numericalCache',numericalCache, ...
            'runtime_s',previousRuntime+toc(started), ...
            'progress',struct('phase','D','iteration',iteration,'objective',objective));
        sht_f33_model_adapt_v2('checkpointpure',state);
        sht_tc24_run_control('boundary',control,'uq_D_iteration',state);
    end
    if strcmp(stopReason,'gradient_small'),break;end
end
% 冷恢复已满足停止判据时不多做一轮，但仍执行下方最终重新线性化。
trace=trace(1:completedIteration);

% 最终点必须重新线性化。曲率由物理输出Jacobian、当前有效观测协方差
% 和先验混合在该点的局部二阶矩组成；数值信赖域不写入后验协方差。
[finalEval,~,physical]=sht_f34_likelihood( ...
    'evaluate',likelihood,context,prior,theta);
finalGradient=local_forward_gradient(z,priorMean,scale,lower,upper, ...
        fdStep,likelihood,context,prior,objective);
projectedGradient=finalGradient;
projectedGradient(z<=lower+1e-10 & finalGradient>0)=0;
projectedGradient(z>=upper-1e-10 & finalGradient<0)=0;
converged=norm(projectedGradient,inf)<=options.methodDGradientTolerance;
if converged,stopReason='final_projected_gradient_small';end
if ~finalEval.valid
    error('SHT:F34MethodD:FinalPoint','方法D最终点物理求值无效。');
end
[jacobian,finalStep]=local_prediction_jacobian(theta,scale,derivativeParameter, ...
    likelihood,context,prior,finalEval.prediction);
S=finalEval.covariance(:,:,1);
responsibility=sht_f34_prior('responsibilities',prior,theta);
center=prior.componentCenters;
conditionalCenter=center.'*responsibility;
centered=center-conditionalCenter.';
priorLocalCov=centered.'*(centered.*responsibility)+ ...
    local_kernel_covariance(prior);
[priorLocalCov,~]=local_make_spd(priorLocalCov);
H=jacobian.'*(S\jacobian)+(priorLocalCov\eye(dimension));
[H,hessianJitter]=local_make_spd(H);
covariance=H\eye(dimension);covariance=(covariance+covariance.')/2;
standardDeviation=sqrt(max(diag(covariance),0));
% 不把正态端点裁到物理边界后仍冒称精确95%有界后验区间。
interval=[theta-1.95996398454*standardDeviation,theta+1.95996398454*standardDeviation];

[shapeMean,shapeCovariance,shapeDetail]=sht_f34_likelihood( ...
    'conditionalPosterior',likelihood,prior,theta,physical(:,1));
nonlinearity=local_nonlinearity_check(theta,covariance,objective,finalGradient./scale,parameter, ...
    likelihood,context,prior);

qualityLevel='LOCAL_GAUSS_NEWTON_PRIOR_MOMENT';
if ~converged,qualityLevel='LOCAL_GAUSS_NEWTON_NONSTATIONARY';end
result=struct('schemaVersion','SHT_F34_METHOD_D_V1', ...
    'createdAt',datestr(now,31),'methodId','D','qualityLevel',qualityLevel, ...
    'parameterTable',parameter,'map',theta,'meanApproximation',theta, ...
    'covariance',covariance,'standardDeviation',standardDeviation, ...
    'interval95',interval,'objective',objective, ...
    'logLikelihood',finalEval.logLikelihood,'logPrior', ...
    sht_f34_prior('logpdf',prior,theta),'converged',converged, ...
    'stopReason',stopReason,'trace',trace,'predictionAtMap', ...
    finalEval.prediction(:,1),'physicalOutputAtMap',physical(:,1), ...
    'effectiveObservationCovarianceAtMap',S,'predictionJacobian',jacobian, ...
    'differenceStep',finalStep,'localPriorCovariance',priorLocalCov, ...
    'hessian',H,'hessianJitter',hessianJitter, ...
    'conditionalShapeMean',shapeMean,'conditionalShapeCovariance',shapeCovariance, ...
    'priorShape',prior.shape,'nonlinearity',nonlinearity, ...
    'runtime_s',toc(started),'testDataUsed',false,'truthDataUsed',false, ...
    'warning',['方法D使用正定Gauss-Newton及局部先验矩协方差近似，不是精确混合后验Hessian；' ...
    '不得据此排除多峰、边界偏斜或远端概率质量。']);
result.likelihoodContractHash=likelihood.contractHash;
if isfield(likelihood,'physicalSupport')
    result.physicalSupport=likelihood.physicalSupport;
    result.conditionalGaussianMean=shapeDetail.gaussianMean;
    result.conditionalGaussianCovariance=shapeDetail.gaussianCovariance;
    result.conditionalQuadratureCount=likelihood.supportQuadratureCount;
    result.conditionalQuadratureSeed=likelihood.supportQuadratureSeed;
end
result.physicsContractHash=likelihood.physicsContractHash;
result.implementationSha256=sht_f33_model_adapt_v2( ...
    'fileHash',[mfilename('fullpath'),'.m']);
result.preparedOptionsSha256=prepared.contract.optionsSha256;
result.finalProjectedGradientNorm=norm(projectedGradient,inf);
result.curvatureApproximation='positive_Gauss_Newton_plus_local_prior_moment_precision';
result.intervalInterpretation='unbounded_local_normal_reference_not_calibrated_bounded_quantiles';
result.intervalCrossesBounds=interval(:,1)<parameter.lower_bound|interval(:,2)>parameter.upper_bound;
result.scaledDifferenceStep=fdStep./scale;
result.resumedFromSafeCheckpoint=found;
result.totalRuntime_s=previousRuntime+toc(started);
cacheAfter=sht_f34_likelihood('cacheStats');
result.cacheAudit=struct('entryCountBefore',cacheBefore.entryCount, ...
    'entryCountAfter',cacheAfter.entryCount,'hit',cacheAfter.hit, ...
    'miss',cacheAfter.miss);
result.summary=local_summary(result,prior);
fprintf('方法D完成：Phi=%.6e，收敛=%d（%s），耗时 %.1f s。\n', ...
    objective,converged,stopReason,result.runtime_s);
end

function [objective,detail]=local_objective(likelihood,context,prior,theta)
[evaluation,~,~]=sht_f34_likelihood('evaluate',likelihood,context,prior,theta);
logPrior=sht_f34_prior('logpdf',prior,theta);
logPosterior=evaluation.logLikelihood+logPrior;
objective=-logPosterior;
objective(~evaluation.valid|~isfinite(objective))=Inf;
detail=repmat(struct('logLikelihood',NaN,'logPrior',NaN),1,size(theta,2));
for i=1:numel(detail)
    detail(i).logLikelihood=evaluation.logLikelihood(i);
    detail(i).logPrior=logPrior(i);
end
end

function [gradient,stepZ]=local_forward_gradient(z,center,scale,lower,upper, ...
        physicalStep,likelihood,context,prior,baseObjective)
n=numel(z);stepZ=zeros(n,1);
for i=1:n
    magnitude=physicalStep(i)/scale(i);
    if z(i)+magnitude<=upper(i)
        stepZ(i)=magnitude;
    elseif z(i)-magnitude>=lower(i)
        stepZ(i)=-magnitude;
    else
        error('SHT:F34MethodD:Difference','参数%d没有可用差分方向。',i);
    end
end
value=nan(n,1);remaining=(1:n).';
for attempt=1:8
    if isempty(remaining),break;end
    trial=repmat(z,1,numel(remaining));
    for k=1:numel(remaining)
        i=remaining(k);trial(i,k)=z(i)+stepZ(i);
    end
    theta=center+scale.*trial;
    candidate=local_objective(likelihood,context,prior,theta);
    finite=isfinite(candidate(:));value(remaining(finite))=candidate(finite);
    remaining=remaining(~finite);stepZ(remaining)=0.5*stepZ(remaining);
end
% 若一侧持续落入无效物理解，尝试同量级反向差分。
for k=1:numel(remaining)
    i=remaining(k);opposite=-stepZ(i);
    if z(i)+opposite<lower(i)||z(i)+opposite>upper(i),continue;end
    trial=z;trial(i)=z(i)+opposite;
    candidate=local_objective(likelihood,context,prior,center+scale.*trial);
    if isfinite(candidate),value(i)=candidate;stepZ(i)=opposite;end
end
if any(~isfinite(value))
    error('SHT:F34MethodD:GradientDifference', ...
        '参数%s在步长减半及换向后仍没有有效差分点。', ...
        strjoin(cellstr(string(prior.parameterTable.parameter_id(~isfinite(value)))),', '));
end
gradient=(value(:)-baseObjective)./stepZ;
end

function [J,step]=local_prediction_jacobian(theta,scale,parameter, ...
        likelihood,context,prior,basePrediction)
n=numel(theta);step=zeros(n,1);
for i=1:n
    magnitude=parameter.difference_step(i);
    if theta(i)+magnitude<=parameter.upper_bound(i)
        step(i)=magnitude;
    else
        step(i)=-magnitude;
    end
end
J=nan(numel(basePrediction),n);remaining=(1:n).';
for attempt=1:8
    if isempty(remaining),break;end
    trial=repmat(theta,1,numel(remaining));
    for k=1:numel(remaining)
        i=remaining(k);trial(i,k)=theta(i)+step(i);
    end
    evaluation=sht_f34_likelihood('evaluate',likelihood,context,prior,trial);
    valid=find(evaluation.valid(:));
    for k=valid.'
        i=remaining(k);J(:,i)=(evaluation.prediction(:,k)-basePrediction)/step(i);
    end
    remaining=remaining(~evaluation.valid(:));step(remaining)=0.5*step(remaining);
end
for k=1:numel(remaining)
    i=remaining(k);opposite=-step(i);
    if theta(i)+opposite<parameter.lower_bound(i)|| ...
            theta(i)+opposite>parameter.upper_bound(i),continue;end
    trial=theta;trial(i)=theta(i)+opposite;
    evaluation=sht_f34_likelihood('evaluate',likelihood,context,prior,trial);
    if evaluation.valid
        J(:,i)=(evaluation.prediction(:,1)-basePrediction)/opposite;step(i)=opposite;
    end
end
if any(~isfinite(J),'all')
    bad=find(any(~isfinite(J),1));
    error('SHT:F34MethodD:Jacobian', ...
        '参数%s在步长减半及换向后仍无有效Jacobian点。', ...
        strjoin(cellstr(string(parameter.parameter_id(bad))),', '));
end
end

function diagnostic=local_nonlinearity_check(theta,covariance,baseObjective,gradient, ...
        parameter,likelihood,context,prior)
[vector,value]=eig((covariance+covariance.')/2,'vector');
[value,order]=sort(max(real(value),0),'descend');vector=real(vector(:,order));
count=min(3,numel(value));multipliers=[-2,-1,1,2];
candidate=zeros(numel(theta),count*numel(multipliers));
direction=zeros(count*numel(multipliers),1);sigmaMultiplier=direction;
k=0;
for i=1:count
    for multiplier=multipliers
        k=k+1;direction(k)=i;sigmaMultiplier(k)=multiplier;
        candidate(:,k)=min(max(theta+multiplier*sqrt(value(i))*vector(:,i), ...
            parameter.lower_bound),parameter.upper_bound);
    end
end
objective=local_objective(likelihood,context,prior,candidate);
% 候选在物理边界被截断后，实际扰动长度不再等于声明的sigma倍数。
delta=candidate-theta;
% 未达驻点时保留一阶项，否则把非零斜率误报成非线性曲率误差。
linear=(gradient.'*delta).';
predicted=linear+0.5*sum(delta.*(covariance\delta),1).';
observed=objective(:)-baseObjective;
diagnostic=table(direction,sigmaMultiplier,linear,predicted,observed, ...
    abs(observed-predicted),'VariableNames',{'direction','sigma_multiplier', ...
    'linear_delta_objective','quadratic_delta_objective','exact_delta_objective','absolute_difference'});
end

function covariance=local_prior_covariance(prior,theta)
weight=sht_f34_prior('responsibilities',prior,theta);
center=prior.componentCenters;meanValue=center.'*weight;
centered=center-meanValue.';
covariance=centered.'*(centered.*weight)+local_kernel_covariance(prior);
[covariance,~]=local_make_spd(covariance);
end

function covariance=local_kernel_covariance(prior)
if isfield(prior,'componentCovariance'),covariance=prior.componentCovariance;
else,covariance=diag(prior.componentSigma.^2);end
end

function tableValue=local_summary(result,prior)
tableValue=table(prior.parameterTable.parameter_id,prior.parameterTable.name, ...
    prior.parameterTable.unit,result.map,result.standardDeviation, ...
    result.interval95(:,1),result.interval95(:,2), ...
    'VariableNames',{'parameter_id','name','unit','map','std_local', ...
    'q025_local','q975_local'});
end

function [matrix,jitter]=local_make_spd(matrix)
matrix=(matrix+matrix.')/2;scale=max(1,max(abs(diag(matrix))));jitter=0;
for k=0:12
    [~,flag]=chol(matrix+jitter*eye(size(matrix)));
    if flag==0,matrix=matrix+jitter*eye(size(matrix));return;end
    if k==0,jitter=scale*1e-12;else,jitter=jitter*10;end
end
error('SHT:F34MethodD:SPD','矩阵不能正定化。');
end

function fileName=local_cache_file(likelihood,prepared)
if isfield(likelihood,'cacheFile')
    fileName=likelihood.cacheFile;
else
    fileName=fullfile(prepared.paths.runDir,'f34_exact_physics_cache.mat');
end
end
