function varargout=sht_tc24_uq_d_fast_prediction(action,varargin)
% D专用局部传播。主/附加参数保持条件关联，不逐个后验样本调用DLL。
switch action
    case 'conditional',varargout{1}=conditionalApproximation(varargin{:});
    case 'predict',[varargout{1:nargout}]=predictApproximation(varargin{:});
    otherwise,error('TC24:D:FastAction','未知快速传播操作。');
end
end

function nc=conditionalApproximation(c,s,q,theta)
assert(~isfield(s,'boundedLikelihood'),'TC24:D:FastBounded','快速传播仅支持已确认的矩边缘化目标。');
G=(s.nuisanceJacobian{1}+s.nuisanceJacobian{2})/2;V=diag(s.nuisanceVariance);
S=s.measurementC.selected.covariance;K=(V*G.')/S;
r=q.finalExact.residual+q.physicalJacobian*(theta-q.map)+s.likelihood.additiveResidualShift;
mu=s.nuisanceMean-K*r;C=V-K*G*V;C=(C+C.')/2;
assert(min(eig(C))>=-1e-12,'TC24:D:FastCovariance','条件协方差非半正定。');
extra=.25*(s.nuisanceJacobian{1}-s.nuisanceJacobian{2})*V*(s.nuisanceJacobian{1}-s.nuisanceJacobian{2}).';
assert(norm(s.baseMeasurement.selected.covariance+extra+G*V*G.'-S,'fro')/norm(S,'fro')<1e-10);
sd=sqrt(max(diag(C),eps));t=c.nuisanceParameterTable;
outside=.5*erfc(-(t.lower_bound-mu)./(sqrt(2)*sd))+.5*erfc((t.upper_bound-mu)./(sqrt(2)*sd));
nc=struct('mean',mu,'covariance',C,'priorMean',s.nuisanceMean, ...
    'trainingValid',true(1,size(theta,2)),'parameterTable',t,'gain',K, ...
    'anchorVariationCovariance',extra,'marginalOutsideSupportProbability',outside, ...
    'supportClippingApplied',false,'representation','local_linearized_moment_conditional', ...
    'dllEvaluationCount',0,'physicalValidityNotEvaluated',true,'referenceTheta',q.map);
end

function [exact,variance,audit,Gall]=predictApproximation(c,data,p,nc,q,opts)
timer=tic;n=c.parameterCount;N=size(p.theta,2);d=height(nc.parameterTable);
[obs,~,~]=sht_steady_model_uq_common('observation',c.baseContract,data,'steady');
m=numel(obs)/height(data);residual=nan(numel(obs),N);variance=nan(numel(obs),1);
Gall=zeros(numel(obs),d);checks={};references={};count=0;
lower=[c.lowerBound;nc.parameterTable.lower_bound];upper=[c.upperBound;nc.parameterTable.upper_bound];
scale=[c.priorSigma;nc.parameterTable.prior_sigma];
step=max(1e-8,min([c.parameterTable.difference_step;nc.parameterTable.difference_step],.005*scale));
w=p.weights(:)/sum(p.weights);meanTheta=p.theta*w;
for point=1:height(data)
    local=opts;[folder,stem]=fileparts(opts.cacheFile);
    local.cacheFile=fullfile(folder,sprintf('D_fast_point_%03d',point),[stem,'.mat']);
    evaluate=@(z)sht_steady_model_uq_b_common('evaluate',c.auxiliaryContract,z,data(point,:),local);
    candidates=[q.map,c.thetaHat,meanTheta];chosen=0;
    for candidate=1:size(candidates,2)
        center=[candidates(:,candidate);nc.priorMean];base=evaluate(center);count=count+base.dllEvaluationCount;
        if all(base.valid) && all(isfinite(base.residual(:))),chosen=candidate;break;end
    end
    if chosen==0
        warning('TC24:D:NoLinearReference','%s无可解参考；保留该点缺失，不删后验。',string(data.point_id(point)));
        references{end+1}=table(string(data.point_id(point)),0,false,0, ...
            'VariableNames',{'point_id','reference_candidate','linearization_available','dll_evaluations'}); %#ok<AGROW>
        continue;
    end
    J=nan(m,n+d);pending=1:n+d;h=step;
    for attempt=1:3
        dz=h(pending);direction=ones(size(dz));
        direction(upper(pending)-center(pending)<center(pending)-lower(pending))=-1;
        room=max(upper(pending)-center(pending),center(pending)-lower(pending));dz=direction.*min(dz,.4*room);
        assert(all(abs(dz)>eps),'TC24:D:FastStep','稳态差分步长退化。');
        z=repmat(center,1,numel(pending));
        for k=1:numel(pending),z(pending(k),k)=z(pending(k),k)+dz(k);end
        e=evaluate(z);count=count+e.dllEvaluationCount;
        good=logical(e.valid) & all(isfinite(e.residual),1);
        J(:,pending(good))=(e.residual(:,good)-base.residual)./dz(good).';
        pending=pending(~good);h(pending)=h(pending)/2;
        if isempty(pending),break;end
    end
    available=isempty(pending);rows=(point-1)*m+(1:m);
    references{end+1}=table(string(data.point_id(point)),chosen,available,count, ...
        'VariableNames',{'point_id','reference_candidate','linearization_available','dll_evaluations'}); %#ok<AGROW>
    if ~available
        warning('TC24:D:FastDerivative','%s差分无效，不将失败导数置零。',string(data.point_id(point)));continue;
    end
    % 条件均值随主参数变化，保留相关性；剩余条件方差另加一次。
    residual(rows,:)=base.residual+J(:,1:n)*(p.theta-center(1:n))+J(:,n+1:end)*(nc.mean-nc.priorMean);
    Gall(rows,:)=J(:,n+1:end);variance(rows)=max(diag(J(:,n+1:end)*nc.covariance*J(:,n+1:end).'),0);
    % 四个预定样本抽查显式非线性；抽查比例不是全后验可解质量。
    ids=unique(round(linspace(1,N,4)));z=[p.theta(:,ids);repmat(nc.priorMean,1,numel(ids))];
    e=evaluate(z);count=count+e.dllEvaluationCount;
    approx=base.residual+J(:,1:n)*(p.theta(:,ids)-center(1:n));
    for k=1:numel(ids)
        err=e.residual(:,k)-approx(:,k);
        for j=1:m
            checks{end+1}=table(string(data.point_id(point)),ids(k),j,logical(e.valid(k)),err(j), ...
                'VariableNames',{'point_id','sample_index','output_index','exact_valid','linearization_error'}); %#ok<AGROW>
        end
    end
end
exact=struct('residual',residual,'valid',all(isfinite(residual),1),'dllEvaluationCount',count);
audit=struct('method','steady_first_order_at_valid_reference','runtime_s',toc(timer), ...
    'references',vertcat(references{:}),'spotChecks',vertcat(checks{:}), ...
    'globalRootMassEstimated',false,'posteriorSamplesUnchanged',true, ...
    'conditionalParameterCrossDependencePreserved',true,'truthUsed',false, ...
    'dllEvaluationCount',count,'samplewiseNonlinearPrediction',false);
fprintf('TC24-D快速传播：%d工况，%d组代数样本，%.1fs；未逐样本验证稳态根。\n',height(data),N,toc(timer));
end
