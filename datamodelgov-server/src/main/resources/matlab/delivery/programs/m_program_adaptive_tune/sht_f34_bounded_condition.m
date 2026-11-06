function varargout=sht_f34_bounded_condition(action,varargin)
%SHT_F34_BOUNDED_CONDITION 保留物理上下界的剩余修正量条件分布。
% 剩余修正量是没有作为主采样变量的节点及引气等参数，不是新的物理量。
% 先在有界子空间做Genz积分，再按高斯条件公式恢复其余相关方向。
% 不裁剪样本，不丢弃样本；返回区间概率以供似然/重要性权重归一化。
switch action
    case 'build',varargout{1}=local_build(varargin{:});
    case 'evaluate',varargout{1}=local_evaluate(varargin{:});
    otherwise,error('SHT:F34Bounded:Action','未知动作。');
end
end

function support=local_build(prior)
t=readtable(prior.sourceWorkbook,'Sheet','ConditionalNuisance');
map=prior.shape.nodeMap;idx=prior.nodePrior.remainingPhysicalIndices;
rows=find(map.kind(idx)=="health_constant");
b=zeros(0,1);lo=b;hi=b;name=strings(0,1);ci=b;
for j=rows(:).'
    k=find(t.c_index==map.c_index(idx(j)) & string(t.group_kind)=="health_constant");
    if isempty(k),continue;end % h15属于主参数，不在附加物理参数表。
    assert(numel(k)==1 && string(t.unit(k))=="1",'物理编号/单位必须唯一一致。');
    b(end+1,1)=j;lo(end+1,1)=t.lower_bound(k)-map.reference_value(idx(j));
    hi(end+1,1)=t.upper_bound(k)-map.reference_value(idx(j));
    name(end+1,1)=string(t.name(k));ci(end+1,1)=map.c_index(idx(j));
end
assert(~isempty(b)&&all(lo<hi),'附加物理参数边界缺失或无效。');
support=struct('schema','SHT_F34_CONDITIONAL_PHYSICAL_SUPPORT_V1', ...
    'index',b,'lower',lo,'upper',hi,'name',name,'c_index',ci, ...
    'sourceWorkbookSha256',sht_f33_model_adapt_v2('fileHash',prior.sourceWorkbook), ...
    'rule','source_physical_parameter_support_no_coordinate_clipping');
end

function out=local_evaluate(mu,V,support,count,seed,stream,drawCount)
if nargin<6,stream=[];end
if nargin<7,drawCount=1;end
mu=mu(:);V=(V+V')/2;b=support.index;u=setdiff((1:numel(mu))',b,'stable');
box=sht_tc24_uq_box_normal(mu(b),V(b,b),support.lower,support.upper,count,seed,~isempty(stream));
gain=V(u,b)/V(b,b);Vc=V(u,u)-gain*V(b,u);Vc=(Vc+Vc')/2;
out=struct('mean',mu,'covariance',V,'logProbability',box.logProbability, ...
    'integrationEss',box.integrationEss,'draw',[],'count',count,'seed',seed, ...
    'quadratureIdentity',box.qmcIdentity);
out.mean(b)=box.mean;out.mean(u)=mu(u)+gain*(box.mean-mu(b));
out.covariance(b,b)=box.covariance;
out.covariance(u,b)=gain*box.covariance;out.covariance(b,u)=out.covariance(u,b)';
out.covariance(u,u)=Vc+gain*box.covariance*gain';
out.covariance=(out.covariance+out.covariance')/2;
if ~isempty(stream)
    index=zeros(1,drawCount);cdf=cumsum(box.weights);cdf(end)=1;
    for i=1:drawCount,index(i)=find(cdf>=rand(stream),1);end
    out.draw=repmat(out.mean,1,drawCount);
    out.draw(b,:)=box.samples(:,index);
    [v,d]=eig(Vc,'vector');
    assert(min(d)>-1e-12,'非有界方向条件协方差实质非正定。');
    out.draw(u,:)=mu(u)+gain*(out.draw(b,:)-mu(b))+real(v)*(sqrt(max(real(d),0)).*randn(stream,numel(u),drawCount));
    assert(all(all(out.draw(b,:)>=support.lower & out.draw(b,:)<=support.upper)),'有界积分产生越界样本。');
end
end
