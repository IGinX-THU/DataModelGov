function varargout=sht_f34_node_prior(action,varargin)
%SHT_F34_NODE_PRIOR 独立节点D的联合先验及解析条件分布，无工具箱。
% 每个台架粒子保留一组完整节点中心。工程变化协方差允许节点独立变化，
% 同时保留其相关性；没有把台架后验或本轮节点压缩成一个幅值。
switch lower(char(action))
    case 'build'
        varargout{1}=local_build(varargin{:});
    case 'logpdf'
        [varargout{1:nargout}]=local_logpdf(varargin{:});
    case 'conditionalshape'
        [varargout{1:nargout}]=local_conditional(varargin{:});
    case 'moments'
        [varargout{1:nargout}]=local_moments(varargin{:});
    otherwise
        error('SHT:F34NodePrior:Action','未知节点先验动作。');
end
end

function prior=local_build(context,options,map,w,centers,Q,Qnext,manifest,nh)
parameter=context.parameterContract;d=height(parameter);m=height(map);
selected=zeros(d,1);
for j=1:d
    kind=char(parameter.kind(j));c=parameter.c_index(j);node=parameter.node_index(j);
    if strcmp(kind,'health_node')
        row=find(map.kind=="health"&map.c_index==c&map.node_index==node);
    elseif strcmp(kind,'fuel_bias_node')
        row=find(map.kind=="fuel_bias"&map.node_index==node);
    elseif strcmp(kind,'sortie_nuisance')&&contains(string(parameter.parameter_id(j)),"dist")
        row=m+1;
    else
        error('SHT:F34NodePrior:Dictionary','不支持的节点参数%s。',char(parameter.parameter_id(j)));
    end
    assert(numel(row)==1,'节点必须与物理编号和坐标唯一匹配。');selected(j)=row;
end
assert(numel(unique(selected))==d,'节点参数重复。');
centers=[centers,zeros(numel(w),1)];
Q=blkdiag(Q,options.firstFlightKdistSigma^2);
Qnext=blkdiag(Qnext,options.flightToFlightKdistSigma^2);
remaining=setdiff((1:m).',selected,'stable');
% 固定零流量压损端点等严格零方差量不产生求导列，其余方向全部保留。
second=sum(centers.^2.*w,1).'+diag(Q);
remaining=remaining(second(remaining)>1e-24);
basis=zeros(m,numel(remaining));
for j=1:numel(remaining),basis(remaining(j),j)=1;end
Qee=Q(selected,selected);scale=sqrt(diag(Qee));
[R,flag]=chol(Qee./(scale*scale.'));
assert(flag==0,'节点工程协方差不是正定矩阵，不能用对角矩阵替代。');
gain=Q(remaining,selected)/Qee;
Qc=Q(remaining,remaining)-gain*Q(selected,remaining);
Qc=(Qc+Qc.')/2;
assert(min(eig(Qc))>-1e-15,'条件协方差存在实质负特征值。');
prior=struct('schemaVersion','SHT_F34_NODE_PRIOR_V1', ...
    'sourceStage',options.sourceStage,'sourceMethod',options.sourceMethod, ...
    'sourceWorkbook',options.sourceWorkbook, ...
    'sourceWorkbookSha256',sht_f33_model_adapt_v2('fileHash',options.sourceWorkbook), ...
    'sourceManifest',manifest,'transitionMode',options.transitionMode, ...
    'parameterTable',parameter,'componentWeights',w, ...
    'componentCenters',centers(:,selected),'componentSigma',scale.', ...
    'componentCovariance',Qee,'lowerBound',parameter.lower_bound.', ...
    'upperBound',parameter.upper_bound.');
prior.nodePrior=struct('schema','PHYSICAL_NODE_MIXTURE_COMMON_BOX_V1', ...
    'selectedPhysicalIndices',selected,'remainingPhysicalIndices',remaining, ...
    'scaledCholesky',R,'conditioningGain',gain, ...
    'jointNextFlightCovariance',Qnext([selected;remaining],[selected;remaining]), ...
    'boundPolicy','joint_mixture_conditioned_on_common_explicit_box', ...
    'normalizingConstant','theta_independent_not_needed_for_D', ...
    'momentsPolicy','untruncated_mixture_preconditioner_except_independent_Kdist');
prior.shape=struct('nodeMap',map,'basis',basis, ...
    'zSamples',centers(:,remaining),'processCovarianceZ',Qc, ...
    'componentCovarianceZ',zeros(numel(remaining),numel(remaining),0), ...
    'coordinateSecondMoment',second(remaining), ...
    'fullProcessCovariance',Q(1:m,1:m),'retainedRank',numel(remaining), ...
    'retainedSecondMomentFraction',1,'discardedSecondMomentFraction',0, ...
    'referenceHealthNodes',map.reference_value(1:nh), ...
    'healthNodeCount',nh,'fuelNodeCount',m-nh,'reconstructionMaximum',0);
prior.evidenceLineage=table(zeros(0,1),strings(0,1),strings(0,1), ...
    strings(0,1),strings(0,1),strings(0,1), ...
    'VariableNames',{'evidence_order','stage_id','engine_id','sortie_id','evidence_sha256','evidence_role'});
prior.quality=struct('benchFuelBiasMarginalized',true,'testDataUsed',false, ...
    'truthDataUsed',false,'processCovarianceCalibrated',false, ...
    'conditionalNuisanceMode','full_remaining_node_conditional_gaussian_mixture', ...
    'processCovarianceBasis','engineering_judgement_pending_longitudinal_study', ...
    'upstreamFormalStatus',char(string(manifest.formal_status(1))));
prior.engineeringAssumption=struct('nodeCovarianceSource', ...
    'uncompressed_physical_reconstruction_of_existing_engineering_Q', ...
    'fixedExplicitNodeCount',d,'uncoveredNodesRetained',true, ...
    'oldAmplitudeBoxNotReused',true,'fullRemainingVarianceRetained',true);
prior.physicalSupport=sht_f34_bounded_condition('build',prior);
[mu,V]=local_moments(prior);
prior.summary=parameter;
prior.summary.mean=mu;prior.summary.std=sqrt(diag(V));
prior.summary.moment_interpretation=repmat("preconditioning_moments_not_truncated_prior_quantiles",d,1);
end

function [value,responsibility]=local_logpdf(prior,theta)
d=size(prior.componentCenters,2);theta=reshape(theta,d,[]);
logp=-inf(numel(prior.componentWeights),size(theta,2));
s=prior.componentSigma;R=prior.nodePrior.scaledCholesky;
constant=-sum(log(s))-sum(log(diag(R)))-d/2*log(2*pi);
for j=1:size(theta,2)
    x=theta(:,j).';
    if any(~isfinite(x))||any(x<prior.lowerBound)||any(x>prior.upperBound),continue;end
    z=((x-prior.componentCenters)./s)/R;
    logp(:,j)=log(prior.componentWeights)+constant-0.5*sum(z.^2,2);
end
peak=max(logp,[],1);value=peak+log(sum(exp(logp-peak),1));
value(~isfinite(peak))=-Inf;
responsibility=exp(logp-value);responsibility(:,~isfinite(value))=0;
end

function [mu,V,responsibility]=local_conditional(prior,theta)
d=size(prior.componentCenters,2);theta=reshape(theta,d,[]);
[~,responsibility]=local_logpdf(prior,theta);
k=prior.shape.retainedRank;mu=zeros(k,size(theta,2));V=zeros(k,k,size(theta,2));
for j=1:size(theta,2)
    w=responsibility(:,j);
    if sum(w)<=0,mu(:,j)=NaN;V(:,:,j)=NaN;continue;end
    % 条件均值包含工程变化的节点交叉协方差，不只对粒子中心加权。
    z=prior.shape.zSamples+(theta(:,j).'-prior.componentCenters)* ...
        prior.nodePrior.conditioningGain.';
    mu(:,j)=z.'*w;delta=z-mu(:,j).';
    V(:,:,j)=prior.shape.processCovarianceZ+delta.'*(delta.*w);
    V(:,:,j)=(V(:,:,j)+V(:,:,j).')/2;
end
end

function [mu,V]=local_moments(prior)
w=prior.componentWeights;c=prior.componentCenters;mu=c.'*w;
delta=c-mu.';V=prior.componentCovariance+delta.'*(delta.*w);
% 独立装机损失具有[0,上界]物理约束，单独使用解析截断正态矩。
j=find(prior.nodePrior.selectedPhysicalIndices==height(prior.shape.nodeMap)+1);
if ~isempty(j)
    s=prior.componentSigma(j);a=prior.lowerBound(j)/s;b=prior.upperBound(j)/s;
    pa=exp(-a*a/2)/sqrt(2*pi);pb=exp(-b*b/2)/sqrt(2*pi);
    mass=0.5*(erfc(-b/sqrt(2))-erfc(-a/sqrt(2)));
    shift=(pa-pb)/mass;mu(j)=s*shift;
    V(j,j)=s*s*(1+(a*pa-b*pb)/mass-shift^2);
end
V=(V+V.')/2;
end
