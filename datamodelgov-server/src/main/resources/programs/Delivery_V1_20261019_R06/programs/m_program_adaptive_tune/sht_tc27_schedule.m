function varargout=sht_tc27_schedule(action,varargin)
%SHT_TC27_SCHEDULE 三部件绝对纵坐标调度工具，保持DLL实际节点。
% I由分组辨识的绝对K值构造曲线；II保留上游节点，仅对远离已有节点的
% 新证据插点。压损原点固定，其他曲线不添加人工原点，不做固定节点重采样。
switch action
    case 'refresh',varargout{1}=local_refresh(varargin{1});
    case 'constant',varargout{1}=local_constant(varargin{:});
    case 'values',varargout{1}=local_values(varargin{:});
    case 'constructI',varargout{1}=local_construct_i(varargin{:});
    case 'insertII',varargout{1}=local_insert_ii(varargin{:});
    case 'support',varargout{1}=local_support(varargin{:});
    otherwise,error('未知调度操作%s。',action);
end
end

function s=local_refresh(s)
s.designHealth=zeros(159,1);
for j=1:numel(s.healthEntries)
    e=s.healthEntries(j);e.xNodes=e.xNodes(:);e.kNodes=e.kNodes(:);
    assert(all(diff(e.xNodes)>0)&&all(isfinite([e.xNodes;e.kNodes])),'节点必须严格递增且有限。');
    assert(numel(e.xNodes)==numel(e.kNodes),'调度横纵坐标不等长。');
    assert(numel(e.xNodes)<=32,'超过当前DLL每条曲线32节点容量，不得静默重采样。');
    if e.pressureLoss,assert(e.xNodes(1)==0 && e.kNodes(1)==0,'压损固定原点必须为(0,0)。');end
    e.designValue=local_interp(e.xNodes,e.kNodes,e.designCoordinate);
    e.xNodesDll=e.xNodes;e.kNodesDll=e.kNodes;e.deltaNodesDll=e.kNodes-e.designValue;
    e.dllResamplingUsed=false;s.healthEntries(j)=e;s.designHealth(e.cIndex+1)=e.designValue;
end
s.designHealth(16)=s.h15;s.fuelBias.xNodes=s.fuelBias.xNodes(:);s.fuelBias.biasNodes=s.fuelBias.biasNodes(:);
assert(all(diff(s.fuelBias.xNodes)>0),'燃油调度坐标必须严格递增。');
end

function s=local_constant(template,parameters,z)
s=template;
for j=1:height(parameters)
    c=parameters.c_index(j);
    if c==15,s.h15=z(j);continue;end
    k=find([s.healthEntries.cIndex]==c,1);e=s.healthEntries(k);
    e.kNodes(:)=z(j);if e.pressureLoss,e.kNodes(1)=0;end
    s.healthEntries(k)=e;
end
s.fuelBias.biasNodes(:)=z(end);s=local_refresh(s);
end

function z=local_values(s,parameters,coordinates,measuredFuel)
n=height(coordinates);z=zeros(n,height(parameters)+1);
for j=1:height(parameters)
    c=parameters.c_index(j);
    if c==15,z(:,j)=s.h15;continue;end
    e=s.healthEntries([s.healthEntries.cIndex]==c);
    z(:,j)=local_interp(e.xNodes,e.kNodes,coordinates.(e.axisName));
end
z(:,end)=local_interp(s.fuelBias.xNodes,s.fuelBias.biasNodes,measuredFuel/s.fuelBias.wfDesign);
end

function s=local_construct_i(template,parameters,coordinates,measuredFuel,groupIndex,groupValues)
s=template;
for j=1:height(parameters)
    c=parameters.c_index(j);
    if c==15,s.h15=mean(groupValues(:,j));continue;end
    k=find([s.healthEntries.cIndex]==c,1);e=s.healthEntries(k);
    raw=coordinates.(e.axisName);threshold=local_spacing(e,raw,template);
    [x,y]=local_group_nodes(raw,groupIndex,groupValues(:,j),threshold,e.name);
    [x,y]=local_merge(x,y,threshold,e.name,parameters.prior_sigma_global(j));
    if e.pressureLoss,x=[0;x];y=[0;y];end
    e.xNodes=x;e.kNodes=y;s.healthEntries(k)=e;
end
threshold=.12*max(.05,local_range(template.fuelBias.xNodes));
[x,y]=local_group_nodes(measuredFuel/s.fuelBias.wfDesign,groupIndex,groupValues(:,end),threshold,'Wf_bias');
[x,y]=local_merge(x,y,threshold,'Wf_bias',.003*s.fuelBias.wfDesign);
s.fuelBias.xNodes=x;s.fuelBias.biasNodes=y;s=local_refresh(s);
end

function [x,y]=local_group_nodes(raw,groupIndex,groupValues,threshold,label)
% 一组只产生一个候选节点；不能因组内其他调度坐标分散而变成多节点。
% 组内跨度较大时明确报警，保留均值，随后由全工况D阶段联合微调。
ids=unique(groupIndex);x=zeros(numel(ids),1);y=x;
for k=1:numel(ids)
    g=ids(k);use=groupIndex==g;v=raw(use);x(k)=mean(v);y(k)=groupValues(g);
    if local_range(v)>threshold
        warning('TC27:Schedule:WithinGroupCoordinateSpread', ...
            '%s组%d横坐标范围[%.7g,%.7g]超过近邻门限%.7g；保留单一均值节点%.7g。', ...
            label,g,min(v),max(v),threshold,x(k));
    end
end
end

function s=local_insert_ii(template,coordinates,measuredFuel,groups)
s=template;
for j=1:numel(s.healthEntries)
    e=s.healthEntries(j);v=coordinates.(e.axisName);threshold=local_spacing(e,v,template);
    positive=e.xNodes;if e.pressureLoss,positive=positive(2:end);end
    for g=unique(groups).'
        x=mean(v(groups==g));
        if min(abs(positive-x))>threshold,positive=sort([positive;x]);end %#ok<AGROW>
    end
    x=positive;if e.pressureLoss,x=[0;x];end
    e.kNodes=local_interp(e.xNodes,e.kNodes,x);e.xNodes=x;s.healthEntries(j)=e;
end
v=measuredFuel/s.fuelBias.wfDesign;x=s.fuelBias.xNodes;
threshold=.12*max(.05,local_range(x));
for g=unique(groups).'
    candidate=mean(v(groups==g));if min(abs(x-candidate))>threshold,x=sort([x;candidate]);end %#ok<AGROW>
end
s.fuelBias.biasNodes=local_interp(s.fuelBias.xNodes,s.fuelBias.biasNodes,x);s.fuelBias.xNodes=x;
s=local_refresh(s);
end

function threshold=local_spacing(e,v,template)
if contains(e.axisName,'corrected_speed'),threshold=.02;
elseif contains(e.axisName,'pressure_ratio')
    threshold=.05*max(.1,local_range(template.healthEntries([template.healthEntries.cIndex]==e.cIndex).xNodes));
else
    original=e.xNodes;if e.pressureLoss,original=original(2:end);end
    threshold=max(.15*max(.01,local_range(original)),.01*abs(e.designCoordinate));
end
assert(all(isfinite(v)),'节点坐标不可为非有限值。');
end

function [xx,yy]=local_merge(x,y,threshold,label,conflict)
[x,order]=sort(x(:));y=y(order);xx=[];yy=[];i=1;
while i<=numel(x)
    last=i;while last<numel(x)&&x(last+1)-x(i)<=threshold,last=last+1;end
    use=i:last;
    if local_range(y(use))>conflict
        warning('TC27:Schedule:ConflictingEvidence','%s近邻节点K跨度%.5g，继续取均值并交由D联合微调。',label,local_range(y(use)));
    end
    xx(end+1,1)=mean(x(use));yy(end+1,1)=mean(y(use));i=last+1; %#ok<AGROW>
end
end

function mask=local_support(contract,coordinateBounds,fuelBounds)
% 线性插值节点的紧支撑。覆盖完整Heun轨迹与预测子步的坐标包络，
% 范围以外端点按常值截断处理。只用于相同节点拓扑下的精确结果缓存。
t=contract.parameterTable;mask=false(height(t),1);s=contract.scheduleTemplate;
for j=1:height(t)
    kind=char(t.group_kind(j));
    if strcmp(kind,'constant'),mask(j)=true;continue;end
    if strcmp(kind,'fuel_bias')
        x=s.fuelBias.xNodes;bounds=fuelBounds;
    else
        e=s.healthEntries(t.schedule_entry_index(j));x=e.xNodes;
        bounds=coordinateBounds.(e.axisName).';
    end
    k=t.dll_node_index(j);left=-Inf;right=Inf;
    if k>1,left=x(k-1);end
    if k<numel(x),right=x(k+1);end
    margin=1e-9*max(1,max(abs(bounds)));
    mask(j)=bounds(2)+margin>=left && bounds(1)-margin<=right;
end
end

function y=local_interp(x,v,q)
if numel(x)==1,y=repmat(v,size(q));else,y=interp1(x,v,min(max(q,x(1)),x(end)),'linear');end
end

function width=local_range(v)
% 此处所有输入均为节点向量；极差定义不变，不依赖统计工具箱。
width=max(v)-min(v);
end
