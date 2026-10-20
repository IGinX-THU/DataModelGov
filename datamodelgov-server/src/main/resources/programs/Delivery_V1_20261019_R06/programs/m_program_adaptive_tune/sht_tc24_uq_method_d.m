function result=sht_tc24_uq_method_d(contract,prior,likelihood,options)
%SHT_TC24_UQ_METHOD_D 同一C目标的物理坐标MAP及有界局部高斯初评。
% 数值信赖域只决定如何到达驻点，不改变先验，也不用统一更新比例。
% 最后的局部样本来自近似二次分布，不是DLL精确SMC后验。
if nargin<4,options=struct();end
timer=tic;n=contract.parameterCount;scale=prior.sigma(:);
maximum=opt(options,'maxIterations',10);gradientTolerance=opt(options,'gradientTolerance',1e-3);
sampleCount=opt(options,'localSampleCount',512);
differenceMode=opt(options,'differenceMode','central');
assert(ismember(differenceMode,{'forward','central'}),'TC24:D:Difference','未知差分方式。');
validateattributes(maximum,{'numeric'},{'scalar','integer','positive'});
validateattributes(sampleCount,{'numeric'},{'scalar','integer','>=',128});
lower=prior.lower./scale;upper=prior.upper./scale;
margin=1e-8*(upper-lower);lo=lower+margin;hi=upper-margin;
initial=[contract.thetaHat,prior.mean];
initial=min(max(initial,scale.*lo),scale.*hi);
exact=evalmodel(initial);phi=objective(initial,exact);
[cost,chosen]=min(phi);assert(isfinite(cost),'TC24:D:NoInitial','D初始候选均不可解。');
x=initial(:,chosen)./scale;current=subset(exact,chosen);radius=1;mu=0;
rows=repmat(struct('iteration',0,'objective',NaN,'projected_gradient',NaN, ...
    'step_norm',NaN,'accepted',false,'ratio',NaN,'radius',NaN,'solver_damping',NaN),0,1);
converged=false;reason='maximum_iterations';dllCount=exact.dllEvaluationCount;
firstIteration=1;
lastDifferenceAudit=table();
control=[];if isfield(options,'runControl'),control=options.runControl;end
signature=struct('contractHash',contract.contractHash,'maximumIterations',maximum, ...
    'gradientTolerance',gradientTolerance,'sampleCount',sampleCount, ...
    'differenceMode',differenceMode, ...
    'methodCodeHash',sht_steady_model_uq_common('filehash',[mfilename('fullpath'),'.m']), ...
    'differenceCodeHash',sht_steady_model_uq_common('filehash', ...
    fullfile(fileparts(mfilename('fullpath')),'sht_tc24_uq_d_difference.m')));
if ~isempty(control)
    [savedControl,foundControl]=sht_tc24_run_control('load',control,'method_d_iteration');
    if foundControl
        assert(isequaln(savedControl.signature,signature),'TC24:D:ResumeMismatch', ...
            'D运行控制断点与当前数值配置不一致。');
        cp=savedControl;
        x=cp.x;rows=cp.history;radius=cp.radius;mu=cp.mu;current=cp.current;
        cost=cp.objective;dllCount=cp.dllEvaluationCount;
        firstIteration=cp.nextIteration;converged=cp.converged;reason=cp.stopReason;
        lastDifferenceAudit=cp.lastDifferenceAudit;
        if converged,firstIteration=maximum+1;end
    end
elseif isfield(options,'checkpointFile') && isfile(options.checkpointFile) && opt(options,'resumeIterations',true)
    saved=load(options.checkpointFile,'checkpoint');cp=saved.checkpoint;
    assert(isfield(cp,'signature') && isequaln(cp.signature,signature), ...
        'TC24:D:ResumeMismatch','D断点目标、代码或求解配置改变，不能静默续用。');
    x=cp.x;rows=cp.history;radius=cp.radius;mu=cp.mu;rng(cp.rngState);
    current=evalmodel(x.*scale);cost=objective(x.*scale,current);
    dllCount=cp.dllEvaluationCount+current.dllEvaluationCount;
    if ~isempty(rows),firstIteration=rows(end).iteration+1;end
end
saveSafeIteration(firstIteration);
for iteration=firstIteration:maximum
    [J,gp,Hp,count]=linearize(x,current);dllCount=dllCount+count;
    r=whiten(current.residual);g=J.'*r+gp;H=J.'*J+Hp;H=(H+H.')/2;
    projected=x-min(max(x-g,lo),hi);pg=norm(projected,inf);
    if pg<gradientTolerance
        converged=true;reason='fresh_projected_gradient';saveSafeIteration(iteration);break;
    end
    accepted=false;rho=NaN;dx=zeros(n,1);
    % 每次尝试解完整有界二次子问题，失败后减小信赖域并重新求解。
    eigMin=min(eig(H));damping=max(mu,max(0,1e-8-eigMin));
    for attempt=1:12
        [dx,qp]=sht_steady_model_adapt_v2_common('m3boxquadraticsolve', ...
            H+damping*eye(n),g,max(lo-x,-radius),min(hi-x,radius),1e-8,20*n);
        if ~qp.passed,error('TC24:D:Quadratic','有界二次子问题未满足KKT。');end
        candidate=(x+dx).*scale;trial=evalmodel(candidate);dllCount=dllCount+trial.dllEvaluationCount;
        trialCost=objective(candidate,trial);predicted=-g.'*dx-.5*dx.'*H*dx;
        if predicted>0,rho=(cost-trialCost)/predicted;else,rho=-Inf;end
        if isfinite(trialCost) && trialCost<cost && rho>1e-4
            x=x+dx;cost=trialCost;current=trial;accepted=true;
            if rho>.75,radius=min(4,2*radius);end
            mu=damping/3;break;
        end
        radius=max(1e-6,radius/2);damping=max(1e-4,4*max(damping,1e-4));
    end
    rows(end+1,1)=struct('iteration',iteration,'objective',cost, ...
        'projected_gradient',pg,'step_norm',norm(dx),'accepted',accepted, ...
        'ratio',rho,'radius',radius,'solver_damping',damping); %#ok<AGROW>
    fprintf('TC24-D %2d/%d: objective %.8g, projected gradient %.3g, accepted=%d.\n', ...
        iteration,maximum,cost,pg,accepted);
    if isfield(options,'checkpointFile')
        checkpoint=struct('contractHash',contract.contractHash,'x',x,'history',rows, ...
            'objective',cost,'radius',radius,'mu',mu,'rngState',rng, ...
            'signature',signature,'dllEvaluationCount',dllCount); %#ok<NASGU>
        temporary=[options.checkpointFile,'.partial.mat'];
        save(temporary,'checkpoint','-v7.3');movefile(temporary,options.checkpointFile,'f');
    end
    saveSafeIteration(iteration+1);
end
% 无论因何结束，都在最终位置重新计算物理导数和原先验曲率。
current=evalmodel(x.*scale);dllCount=dllCount+current.dllEvaluationCount;
[J,gp,Hp,count]=linearize(x,current);dllCount=dllCount+count;
g=J.'*whiten(current.residual)+gp;H=(J.'*J+Hp);H=(H+H.')/2;
pg=norm(x-min(max(x-g,lo),hi),inf);
converged=pg<gradientTolerance;
if converged,reason='fresh_projected_gradient';end
gaussNewtonHessian=H;
curvatureAudit=struct('enabled',false,'applied',false,'dllEvaluationCount',0);
if opt(options,'curvatureRefinement',false)
    [H,curvatureAudit]=sht_tc24_uq_d_curvature(@costEvaluation,x,g,H,J,lo,hi,options);
    dllCount=dllCount+curvatureAudit.dllEvaluationCount;
end
[~,flag]=chol(H);curvaturePositive=flag==0;
map=x.*scale;covariance=nan(n);localMean=nan(n,1);
samples=map;weights=1;localRhat=Inf;samplingStable=false;
localSampling=struct('minimumAutocorrelationESS',0,'meanMCSE',nan(n,1));
if curvaturePositive
    covariance=(H\eye(n)).*(scale*scale.');
    % 未达精确驻点时，二次展开的中心并非最终迭代点，二者分别记录。
    quadraticCenter=x-H\g;
    [scaledSamples,localRhat,localSampling]=boundedNormal(quadraticCenter,H,lower,upper,sampleCount, ...
        opt(options,'randomSeed',20260910),x);
    localSampling.meanMCSE=localSampling.meanMCSE.*scale;
    samples=scaledSamples.*scale;weights=ones(size(samples,2),1)/size(samples,2);
    localMean=samples*weights;samplingStable=isfinite(localRhat) && localRhat<1.05;
else
    quadraticCenter=nan(n,1);
end
quality='LOCAL_APPROXIMATION_NONSTATIONARY';
if ~curvaturePositive,quality='LOCAL_CURVATURE_NOT_POSITIVE';
elseif converged && ~samplingStable,quality='LOCAL_APPROXIMATION_SAMPLING_UNSTABLE';
elseif converged,quality='LOCAL_APPROXIMATION_STATIONARY';end
% passed只表示可输出带身份的局部结果，不等于全局正式后验通过。
posterior=struct('theta',samples,'weights',weights,'passed',curvaturePositive, ...
    'logLikelihood',nan(1,size(samples,2)),'logPrior',nan(1,size(samples,2)), ...
    'samplingMethod','bounded_local_quadratic_approximation', ...
    'formalGlobalPosterior',false);
result=struct('map',map,'localMean',localMean,'untruncatedLocalCovariance',covariance, ...
    'quadraticCenter',quadraticCenter.*scale,'scaledHessian',H, ...
    'physicalJacobian',(likelihood.cholLower*J).*(1./scale.'), ...
    'whitenedScaledJacobian',J,'priorHessianScaled',Hp,'finalExact',current, ...
    'history',struct2table(rows),'converged',converged,'stopReason',reason, ...
    'projectedGradient',pg,'gradientTolerance',gradientTolerance,'localRhat',localRhat, ...
    'samplingStable',samplingStable,'curvaturePositive',curvaturePositive,'quality',quality, ...
    'formal',posterior,'passed',curvaturePositive,'formalGlobalPosterior',false, ...
    'dllEvaluationCount',dllCount,'runtime_s',toc(timer),'truthRead',false,'testDataRead',false);
result.summary=sht_steady_model_uq_sampler('summary',samples,weights,contract);
result.scaledGradient=g;
result.gaussNewtonHessian=gaussNewtonHessian;
result.curvatureAudit=curvatureAudit;
result.finalDifferenceAudit=lastDifferenceAudit;
result.localSamplingDiagnostics=localSampling;
result.numericalConfiguration=signature;
if opt(options,'nonlinearCorrection',false) && curvaturePositive
    result=sht_tc24_uq_d_correction(contract,prior,likelihood,result,options);
end
result.runtime_s=toc(timer);

    function saveSafeIteration(nextIteration)
        if isempty(control),return;end
        % 只在一次完整求导/信赖域更新之后保存；停止不会截断DLL调用。
        state=struct('signature',signature,'x',x,'history',rows,'radius',radius, ...
            'mu',mu,'current',current,'objective',cost,'dllEvaluationCount',dllCount, ...
            'nextIteration',nextIteration,'converged',converged,'stopReason',reason, ...
            'lastDifferenceAudit',lastDifferenceAudit,'progress', ...
            struct('phase','D_local_MAP','completedIteration',nextIteration-1,'iterationLimit',maximum));
        sht_tc24_run_control('boundary',control,'method_d_iteration',state);
    end

    function out=evalmodel(theta)
        if isfield(options,'evaluateFunction'),out=options.evaluateFunction(theta);
        else,out=sht_steady_model_uq_c_common('evaluate',contract,theta,contract.trainingData, ...
                struct('useCache',true,'useRobustTransientFallback',true));end
    end
    function value=objective(theta,out)
        value=-sht_steady_model_uq_likelihood('evaluate',likelihood,out.residual,out.valid) ...
            -sht_steady_model_uq_sampler('logprior',prior,theta);
    end
    function [value,count]=costEvaluation(scaledTheta)
        out=evalmodel(scaledTheta.*scale);
        value=objective(scaledTheta.*scale,out);count=out.dllEvaluationCount;
    end
    function value=whiten(residual)
        if isfield(likelihood,'additiveResidualShift'),residual=residual+likelihood.additiveResidualShift;end
        value=likelihood.cholLower\residual;
    end
    function [J,gp,Hp,count]=linearize(point,out)
        % 归一化步长上限1e-3，避免前向差分截断误差支配最终驻点判据。
        delta=max(1e-5,min(.001,contract.parameterTable.difference_step./scale));
        scaledEvaluate=@(z)evalmodel(z.*scale);
        [physical,count,lastDifferenceAudit]=sht_tc24_uq_d_difference( ...
            'residual',scaledEvaluate,point,out,delta,lo,hi,differenceMode);
        J=likelihood.cholLower\physical;
        [gp,Hp]=priorDerivatives(prior,point,scale,lo,hi);
    end
end

function [g,H]=priorDerivatives(prior,x,scale,lo,hi)
% 对真实copula截断先验求数值导数；只做代数计算，不调用DLL。
n=numel(x);h=2e-4*ones(n,1);
f=@(z)-sht_steady_model_uq_sampler('logprior',prior,z.*scale);
[g,H]=sht_tc24_uq_d_difference('prior',f,x,h,lo,hi);
end

function [sample,rhat,diagnostic]=boundedNormal(center,precision,lo,hi,count,seed,start)
% 在白化坐标中做受限正态Gibbs，避免物理坐标的强相关导致缓慢移动。
% x=center+L*z，z为标准正态；每次由所有物理边界求出z_j的精确区间。
old=rng;cleanup=onCleanup(@()rng(old));rng(seed,'twister');
n=numel(center);per=ceil(count/2);chain=zeros(n,per,2);burn=512;thin=2;
L=chol(precision,'lower').'\eye(n);
for c=1:2
    z=L\(start-center);x=start;
    for t=1:burn+thin*per
        for j=1:n
            direction=L(:,j);rest=x-direction*z(j);
            active=abs(direction)>1e-14;
            aa=(lo(active)-rest(active))./direction(active);
            bb=(hi(active)-rest(active))./direction(active);
            left=max(min(aa,bb));right=min(max(aa,bb));
            z(j)=sht_tc24_uq_d_truncated_normal(left,right);x=rest+direction*z(j);
        end
        if t>burn && mod(t-burn,thin)==0,chain(:,(t-burn)/thin,c)=x;end
    end
end
within=reshape(mean(var(chain,0,2),3),n,1);
between=per*var(reshape(mean(chain,2),n,2),0,2);
rhat=max(sqrt(((per-1)/per*within+between/per)./max(within,eps)));
sample=reshape(chain,n,[]);sample=sample(:,1:count);
ess=zeros(n,1);
for j=1:n
    covariance=zeros(1,per);
    for c=1:2
        v=reshape(chain(j,:,c),1,per);v=v-mean(v);
        transform=fft(v,2*per);ac=real(ifft(abs(transform).^2));
        covariance=covariance+ac(1:per)./(per:-1:1)/2;
    end
    rho=covariance/max(covariance(1),realmin);positiveSum=0;previous=Inf;
    for lag=2:2:per-1
        pair=rho(lag)+rho(lag+1);if pair<=0,break;end
        pair=min(pair,previous);positiveSum=positiveSum+pair;previous=pair;
    end
    ess(j)=min(count,2*per/max(1,1+2*positiveSum));
end
diagnostic=struct('autocorrelationESS',ess,'minimumAutocorrelationESS',min(ess), ...
    'meanMCSE',sqrt(var(sample,0,2)./max(ess,1)),'chainCount',2, ...
    'burnInPerChain',burn,'thin',thin,'diagnosticScope','bounded_local_quadratic_only', ...
    'globalConvergenceClaimed',false);
clear cleanup;
end

function out=subset(in,k)
out=in;out.residual=in.residual(:,k);out.valid=in.valid(k);
end

function v=opt(s,n,d)
v=d;if isfield(s,n) && ~isempty(s.(n)),v=s.(n);end
end
