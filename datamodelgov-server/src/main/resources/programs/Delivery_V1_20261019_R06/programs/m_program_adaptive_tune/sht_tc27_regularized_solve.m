function solve=sht_tc27_regularized_solve(fun,x0,center,scale,lowerBound,upperBound,step,options)
%SHT_TC27_REGULARIZED_SOLVE 完整有界正则解，无统一更新比例。
% fun仅返回数据残差。物理Tikhonov约束中心固定；数值信赖域参数只控制
% 当前局部求解。每次移动后重新计算逐节点Jacobian，最后保存新Jacobian。
% TSVD严格保留1/s，不使用阻尼；候选不合适时减少保留维数。
defaults=struct('method','tikhonov','lambda',.02,'retainedCount',6, ...
    'maxIterations',10,'difference','central','label','TC27', ...
    'gradientTolerance',1e-5,'stepTolerance',1e-5,'costTolerance',1e-7, ...
    'objectiveImprovementTolerance',0);
fields=fieldnames(defaults);for k=1:numel(fields),if ~isfield(options,fields{k}),options.(fields{k})=defaults.(fields{k});end,end
% 仅用于续算身份，不进入目标、先验、步长或收敛判断。
root=fileparts(mfilename('fullpath'));
backendFiles={'sht_tc27_regularized_solve.m','sht_steady_model_adapt_v2_common.m', ...
    'sht_bounded_least_squares.m','sht_tc27_condition_diagnostics.m'};
options.backendSourceIdentity=cellfun(@(name)sht_tc27_file_identity(fullfile(root,name)), ...
    backendFiles,'UniformOutput',false);
options.runtimeBackend=struct('matlabRelease',version('-release'),'architecture',computer('arch'));
% 回调持有活跃DLL和局部缓存，不得序列化到MAT，也不得用函数句柄比较续算身份。
% 输入合同与源码哈希保留；新进程必须重新建立本轮准备上下文。
storedOptions=options;
if isfield(storedOptions,'differenceContextFactory'),storedOptions=rmfield(storedOptions,'differenceContextFactory');end
if isfield(storedOptions,'runControl'),storedOptions=rmfield(storedOptions,'runControl');end
storedOptions.reusesPreparation=isfield(options,'differenceContextFactory')&&~isempty(options.differenceContextFactory);
controlled=isfield(options,'runControl')&&~isempty(options.runControl);
assert(ismember(options.difference,{'central','forward'}),'差分方式必须为central或forward。');
assert(ismember(options.method,{'tikhonov','tsvd'}),'TC27:Fit:Options','正则方法只能为tikhonov或tsvd。');
validateattributes(options.lambda,{'numeric'},{'scalar','real','finite','nonnegative'});
validateattributes(options.maxIterations,{'numeric'},{'scalar','integer','finite','nonnegative'});
validateattributes(options.retainedCount,{'numeric'},{'scalar','integer','finite','positive'});
assert(isscalar(options.objectiveImprovementTolerance)&&isfinite(options.objectiveImprovementTolerance)&& ...
    options.objectiveImprovementTolerance>=0,'目标相对改善停止容差必须为有限非负数。');
x=x0(:);center=center(:);scale=scale(:);step=step(:);lowerBound=lowerBound(:);upperBound=upperBound(:);
assert(~isempty(x)&&all([numel(center),numel(scale),numel(step),numel(lowerBound),numel(upperBound)]==numel(x))&& ...
    isreal([x;center;scale;step;lowerBound;upperBound])&&all(isfinite([x;center;scale;step;lowerBound;upperBound]))&& ...
    all(lowerBound<upperBound),'TC27:Fit:Dimensions','参数维数、有限值或严格上下界不合法。');
assert(all(x>=lowerBound & x<=upperBound),'初值超出参数边界。');
assert(all(scale>0 & step>0),'参数尺度及差分步长必须为正。');
% 保留工程尺度的物理含义，同曲线相关先验只改变正则二次型。
correlation=eye(numel(x));
if isfield(options,'priorCorrelation'),correlation=options.priorCorrelation;end
assert(isequal(size(correlation),[numel(x),numel(x)])&&all(isfinite(correlation(:))), '先验相关矩阵维数/数值错误。');
priorRoot=chol((correlation+correlation.')/2,'lower');
priorPrecision=priorRoot.'\(priorRoot\eye(numel(x)));
timer=tic;cache=containers.Map('KeyType','char','ValueType','any');count=0;history=table();converged=false;
stopReason="maximum_iterations";previousCost=Inf;lastMove=Inf;
stagnationDetected=false;lastTrialCount=0;lastValidTrialCount=0;
% 以下仅记录诊断：每轮KKT使用的维数、实际尝试维数及最后接受维数
% 可能不同。最后一轮重新求导不能抹掉上一轮已接受的降秩事实。
tsvdTrace=table();lastTsvdAccepted=struct('retainedCount',NaN,'iteration',NaN, ...
    'jacobianCondition',NaN,'informationCondition',NaN,'singularValues',[]);
firstIteration=0;q=[];
if controlled&&options.runControl.resume
    [saved,found]=sht_tc24_run_control('load',options.runControl,options.runControlKey);
    if found,q=saved.resumeState;end
elseif ~controlled&&isfield(options,'checkpointFile')&&isfile(options.checkpointFile)
    saved=load(options.checkpointFile,'resumeState');q=saved.resumeState;
end
if ~isempty(q)
    assert(isequaln(q.center,center)&&isequaln(q.scale,scale)&& ...
        isequaln(q.step,step)&&isequaln(q.lowerBound,lowerBound)&&isequaln(q.upperBound,upperBound)&& ...
        isequaln(q.options,storedOptions),'局部求解检查点参数或配置不一致。');
    x=q.x;firstIteration=q.nextIteration;history=q.history;previousCost=q.previousCost;lastMove=q.lastMove;
    if isfield(q,'evaluationCount'),count=q.evaluationCount;end
    if isfield(q,'initialLinearization'),initialLinearization=q.initialLinearization;end
    if isfield(q,'tsvdTrace'),tsvdTrace=q.tsvdTrace;lastTsvdAccepted=q.lastTsvdAccepted;end
    fprintf('%s从第%d次已接受迭代继续；将重新计算当前Jacobian。\n',options.label,firstIteration);
end
for iteration=firstIteration:options.maxIterations
    [r,meta]=evaluate(x);assert(meta.valid&&all(isfinite(r)),'TC27:Fit:InvalidInitial','%s当前参数回放无效：%s',options.label,jsonencode(meta));
    % 可选专项差分上下文只作用于Jacobian；正式目标仍由evaluate完整重算。
    % 工厂每轮用当前参数刷新准备状态，不能跨轮冻结，更不能混入目标缓存。
    frozenPreparation=isfield(options,'differenceContextFactory')&&~isempty(options.differenceContextFactory);
    differenceFun=[];
    if frozenPreparation,differenceFun=options.differenceContextFactory(x);end
    z=(x-center)./scale;J=zeros(numel(r),numel(x));
    skippedHistoryBlocks=0;skippedColumns=0;
    for j=1:numel(x)
        % 只在本节点影响的数据块上计算导数。支撑域外的轨迹不发生变化；
        % 目标函数直接复用该轨迹，本处也不对该块作差分。先验项仍完整保留。
        rows=true(numel(r),1);
        if isfield(meta,'jacobianBlocks')
            blocks=meta.jacobianBlocks;
            for b=1:numel(blocks)
                if ~blocks(b).support(j)
                    rows(blocks(b).rows)=false;
                    skippedHistoryBlocks=skippedHistoryBlocks+strcmp(blocks(b).kind,'history');
                end
            end
        end
        if ~any(rows),skippedColumns=skippedColumns+1;continue;end
        hMagnitude=min(step(j),.49*(upperBound(j)-lowerBound(j)));xp=x;xm=x;
        differenceValid=false;
        for retry=1:5
            % 缩步只保存正幅值；每次重试重新判定方向，不能沿用上次的负号。
            h=hMagnitude;
            if strcmp(options.difference,'central') && x(j)-h>lowerBound(j) && x(j)+h<upperBound(j)
                xp(j)=x(j)+h;xm(j)=x(j)-h;[rp,mp]=evaluateDifference(xp);[rm,mm]=evaluateDifference(xm);
                if mp.valid&&mm.valid&&all(isfinite(rp))&&all(isfinite(rm)),J(rows,j)=(rp(rows)-rm(rows))/(2*h);differenceValid=true;break;end
            else
                if x(j)+h>upperBound(j),h=-h;end
                xp(j)=x(j)+h;[rp,mp]=evaluateDifference(xp);
                if mp.valid&&all(isfinite(rp)),J(rows,j)=(rp(rows)-r(rows))/h;differenceValid=true;break;end
            end
            fprintf('%s参数%d差分幅值%g存在无效回放，减半重试。\n',options.label,j,h);hMagnitude=hMagnitude/2;
        end
        assert(differenceValid,'TC27:Fit:Difference','%s参数%d缩小差分幅值后仍无效：%s',options.label,j,jsonencode(mp));
        if mod(j,6)==0 || j==numel(x)
            jacobianLabel='真实Jacobian';if frozenPreparation,jacobianLabel='冻结准备近似Jacobian';end
            fprintf('%s迭代%d：%s %d/%d列，累计%.1fs。\n',options.label,iteration,jacobianLabel,j,numel(x),toc(timer));
        end
    end
    A=J.*scale.';[u,s,v]=svd(A,'econ');singular=diag(s);
    if iteration==0&&isfield(options,'captureInitialLinearization')&&options.captureInitialLinearization
        initialLinearization=struct('x',x,'residual',r,'jacobian',J,'elapsed_s',toc(timer));
    end
    lambda=options.lambda;isTsvd=strcmp(options.method,'tsvd');
    if isTsvd,lambda=0;end
    cost=.5*(r.'*r+lambda^2*(z.'*priorPrecision*z));gradient=A.'*r+lambda^2*priorPrecision*z;
    projected=gradient;projected(x<=lowerBound+1e-12 & gradient>0)=0;projected(x>=upperBound-1e-12 & gradient<0)=0;
    kkt=norm(projected,Inf);
    stationarityRetainedCount=NaN;
    if isTsvd
        rr=min(options.retainedCount,nnz(singular>max(size(A))*eps(max(singular))));
        stationarityRetainedCount=rr;
        vr=v(:,1:rr);
        % 截断问题只要求保留子空间的驻点，丢弃子空间返回固定先验中心。
        kkt=max(norm(vr.'*projected,Inf),norm(z-vr*(vr.'*z),Inf));
    end
    history=[history;table(iteration,cost,.5*(r.'*r),kkt,lastMove,count,toc(timer), ...
        stationarityRetainedCount,lastTsvdAccepted.retainedCount, ...
        'VariableNames',{'iteration','totalCost','dataCost','projectedGradient','previousMove', ...
        'evaluationCount','elapsed_s','tsvdStationarityRetainedCount','tsvdLastAcceptedRetainedCount'})]; %#ok<AGROW>
    fprintf('%s %d/%d: cost %.6g, data %.6g, KKT %.3g, eval %d, %.1fs\n', ...
        options.label,iteration,options.maxIterations,cost,.5*(r.'*r),kkt,count,toc(timer));
    relativeImprovement=Inf;
    if iteration>0&&isfinite(lastMove)&&isfinite(previousCost)
        relativeImprovement=(previousCost-cost)/max(abs(previousCost),1e-12);
    end
    objectiveImprovementPassed=options.objectiveImprovementTolerance>0&& ...
        relativeImprovement>=0&&relativeImprovement<options.objectiveImprovementTolerance;
    fprintf('  relative improvement %.6g; skipped history/node blocks %d, full columns %d.\n', ...
        relativeImprovement,skippedHistoryBlocks,skippedColumns);
    if kkt<options.gradientTolerance
        converged=true;stopReason="fresh_jacobian_stationarity";break;
    elseif objectiveImprovementPassed
        % 这是目标改善停止，不等同于梯度驻点。无有效更新时不触发此条件。
        converged=true;stopReason="fresh_jacobian_small_objective_improvement";break;
    elseif iteration>0 && lastMove<options.stepTolerance && ...
            abs(previousCost-cost)/max(1,previousCost)<options.costTolerance
        converged=true;stopReason="fresh_jacobian_small_step_and_cost";break;
    end
    if iteration==options.maxIterations,break;end
    accepted=false;mu=0;trialCount=10;retained=min(options.retainedCount,numel(singular));
    lastTrialCount=0;lastValidTrialCount=0;
    for trial=1:trialCount
        if isTsvd
            retained=min(retained,nnz(singular>max(size(A))*eps(max(singular))));
            if retained<1,break;end
            vr=v(:,1:retained);
            condition=singular(1)/singular(retained);
            tsvdTrace=[tsvdTrace;table(iteration,trial,retained,condition,condition^2,false,false,false, ...
                'VariableNames',{'iteration','trial','retainedCount','jacobianCondition', ...
                'informationCondition','insideBounds','validEvaluation','accepted'})]; %#ok<AGROW>
            dz=-z+vr*(vr.'*z-(u(:,1:retained).'*r)./singular(1:retained));
        else
            H=A.'*A+lambda^2*priorPrecision+mu*eye(numel(x));
            [dz,audit]=sht_steady_model_adapt_v2_common('m3boxquadraticsolve', ...
                H,gradient,(lowerBound-x)./scale,(upperBound-x)./scale,1e-9,500);
            assert(audit.passed,'有界二次子问题未满足KKT。');
        end
        candidate=x+scale.*dz;
        if all(candidate>=lowerBound-1e-12 & candidate<=upperBound+1e-12)
            if isTsvd,tsvdTrace.insideBounds(end)=true;end
            candidate=min(max(candidate,lowerBound),upperBound); % 仅去除舍入级越界。
            [rr,mm]=evaluate(candidate);zz=(candidate-center)./scale;
            candidateCost=.5*(rr.'*rr+lambda^2*(zz.'*priorPrecision*zz));
            lastTrialCount=lastTrialCount+1;
            lastValidTrialCount=lastValidTrialCount+double(mm.valid&&isfinite(candidateCost));
            if isTsvd,tsvdTrace.validEvaluation(end)=mm.valid&&isfinite(candidateCost);end
            if mm.valid && candidateCost<cost
                if isTsvd
                    tsvdTrace.accepted(end)=true;
                    lastTsvdAccepted=struct('retainedCount',retained,'iteration',iteration, ...
                        'jacobianCondition',condition,'informationCondition',condition^2,'singularValues',singular);
                end
                previousCost=cost;lastMove=norm(dz,Inf);x=candidate;accepted=true;break;
            end
        end
        if isTsvd,retained=retained-1;else,if mu==0,mu=1e-4;else,mu=mu*10;end,end
    end
    if ~accepted
        % 当前参数处已有新Jacobian，且完整正则步/数值信赖域或降秩
        % 候选已全部试过。参数不变时重复同一差分和候选没有新增信息。
        % 工程停滞不是梯度收敛；仍保留最终参数的完整准备导数审计。
        stagnationDetected=lastValidTrialCount>0;
        stopReason="fresh_jacobian_no_acceptable_step";
        if stagnationDetected,stopReason="fresh_jacobian_stagnation";end
        warning('TC27:Fit:NoDescent', ...
            '%s本轮%d个候选中%d个有效但无下降步，保留当前解并停止；不声明梯度收敛。', ...
            options.label,lastTrialCount,lastValidTrialCount);
        break;
    end
    if controlled||isfield(options,'checkpointFile')
        resumeState=struct('x',x,'nextIteration',iteration+1,'center',center,'scale',scale, ...
            'lowerBound',lowerBound,'upperBound',upperBound,'step',step,'options',storedOptions, ...
            'history',history,'previousCost',previousCost,'lastMove',lastMove, ...
            'evaluationCount',count);
        resumeState.tsvdTrace=tsvdTrace;resumeState.lastTsvdAccepted=lastTsvdAccepted;
        if exist('initialLinearization','var')
            resumeState.initialLinearization=initialLinearization;
        end
        if controlled
            state=struct('resumeState',resumeState,'progress',struct( ...
                'stage',options.label,'nextIteration',iteration+1,'evaluationCount',count));
            sht_tc24_run_control('boundary',options.runControl,options.runControlKey,state);
        else
            save(options.checkpointFile,'resumeState');
        end
    end
end
solve=struct('x',x,'center',center,'priorScale',scale,'options',storedOptions, ...
    'converged',converged,'stopReason',stopReason,'iterationCount',iteration, ...
    'residual',r,'meta',meta,'dataJacobian',J,'scaledDataJacobian',A, ...
    'singularValues',singular,'history',history,'elapsedSeconds',toc(timer), ...
    'evaluationCount',count,'globalUpdateFactorUsed',false,'finalJacobianAtFinalParameters',true, ...
    'priorCorrelation',correlation,'firstOrderStationarityPassed',kkt<options.gradientTolerance);
solve.relativeObjectiveImprovement=relativeImprovement;
solve.stagnationDetected=stagnationDetected;
solve.lastTrialCount=lastTrialCount;
solve.lastValidTrialCount=lastValidTrialCount;
if exist('initialLinearization','var'),solve.initialLinearization=initialLinearization;end
solve.frozenPreparationJacobian=frozenPreparation;
if frozenPreparation
    solve.approximateFirstOrderStationarityPassed=solve.firstOrderStationarityPassed;
    solve.firstOrderStationarityPassed=false;
    solve.stopReason=replace(solve.stopReason,'fresh_jacobian','fresh_frozen_preparation_jacobian');
end
solve.objectiveImprovementPassed=objectiveImprovementPassed;
solve.finalSkippedHistoryJacobianBlocks=skippedHistoryBlocks;
solve.finalSkippedDataJacobianColumns=skippedColumns;
% lambda是二次罚项的平方根；报告实际矩阵，避免与lambda线性定义混淆。
solve.actualRegularizationWeight=lambda^2;
solve.normalizedPriorPrecision=priorPrecision;
diagnosticCount=NaN;dimensionSource='not_tsvd';
if isTsvd
    diagnosticCount=stationarityRetainedCount;dimensionSource='final_stationarity_subspace_no_accepted_step';
    if isfinite(lastTsvdAccepted.retainedCount)
        diagnosticCount=lastTsvdAccepted.retainedCount;dimensionSource='last_accepted_step_dimension_at_final_jacobian';
    end
end
solve.conditionDiagnostics=sht_tc27_condition_diagnostics(A,options.method,lambda^2,priorPrecision,diagnosticCount);
solve.conditionDiagnostics.retainedDimensionSource=dimensionSource;
solve.conditionDiagnostics.finalStationarityRetainedCount=stationarityRetainedCount;
solve.conditionDiagnostics.lastAcceptedStep=lastTsvdAccepted;
solve.conditionDiagnostics.trialHistory=tsvdTrace;
solve.conditionSummary=solve.conditionDiagnostics.summary;
solve.conditionSummary.retainedDimensionSource=string(dimensionSource);
solve.conditionSummary.stationarityRetainedCount=stationarityRetainedCount;
solve.conditionSummary.lastAcceptedRetainedCount=lastTsvdAccepted.retainedCount;
solve.normalizedDataJacobianCondition=solve.conditionDiagnostics.fullDataJacobianCondition;
solve.normalizedDataInformationCondition=solve.conditionDiagnostics.fullDataInformationCondition;
solve.regularizedJacobianCondition=solve.conditionDiagnostics.regularizedJacobianCondition;
solve.regularizedInformationCondition=solve.conditionDiagnostics.regularizedInformationCondition;
solve.regularizedConditionSpace=solve.conditionDiagnostics.regularizedConditionSpace;
solve.tsvdEffectiveRetainedCount=solve.conditionDiagnostics.tsvdEffectiveRetainedCount;
fprintf('条件数诊断（参数尺度标准化）：完整J=%.6g，完整信息=%.6g；%s：J=%.6g，信息=%.6g。\n', ...
    solve.normalizedDataJacobianCondition,solve.normalizedDataInformationCondition, ...
    solve.regularizedConditionSpace,solve.regularizedJacobianCondition,solve.regularizedInformationCondition);
if isTsvd
    fprintf('TSVD配置%d，最终KKT维数%g，最后接受维数%g，当前诊断有效维数%g；%s。截断不证明所有原参数可辨识。\n', ...
        options.retainedCount,stationarityRetainedCount,lastTsvdAccepted.retainedCount, ...
        solve.tsvdEffectiveRetainedCount,dimensionSource);
end
solve.regularizationDefinition='0.5*lambda^2*z''*P*z, z=(x-center)./priorScale';
candidates=[.01,.02,.05,.1,.2,.5,1,2,5,10];gcv=zeros(numel(candidates),1);
[uc,sc,vc]=svd(A*priorRoot,'econ');sc=diag(sc);zc=priorRoot\z;
for j=1:numel(candidates)
    q=candidates(j);d=-priorRoot*vc*((sc.*(uc.'*r)+q^2*(vc.'*zc))./(sc.^2+q^2));
    projectedResidual=r+A*d;dof=sum(sc.^2./(sc.^2+q^2));
    gcv(j)=sum(projectedResidual.^2)/max(eps,(numel(r)-dof)^2);
end
[~,best]=min(gcv);solve.gcvRecommendation=candidates(best);solve.gcv=table(candidates.',gcv,'VariableNames',{'lambda','GCV'});
    function [value,detail]=evaluate(parameter)
        key=sprintf('%.17g,',parameter);
        if isKey(cache,key),item=cache(key);value=item{1};detail=item{2};return;end
        [value,detail]=fun(parameter);value=value(:);count=count+1;cache(key)={value,detail};
    end
    function [value,detail]=evaluateDifference(parameter)
        if isempty(differenceFun),[value,detail]=evaluate(parameter);return;end
        [value,detail]=differenceFun(parameter);value=value(:);count=count+1;
    end
end
