function varargout=sht_f33_schedule_parameterization(action,varargin)
% 所有发动机曲线与燃油偏置曲线采用同一释放方式，不允许混合。
% family_amplitude：每条曲线一个幅值，节点变化为冻结覆盖基函数乘幅值。
% independent_nodes：每个被覆盖节点一个独立的纵坐标改变量。
% 两者均惩罚实际节点改变量平方和；先验尺度不是后验可信区间。
switch lower(action)
    case 'coverage'
        varargout{1}=local_coverage(varargin{:});
    case 'build'
        varargout{1}=local_build(varargin{:});
    case 'apply'
        [varargout{1:3}]=local_apply(varargin{:});
    otherwise
        error('SHT:F33Param:Action','未知参数化动作：%s。',action);
end
end

function map=local_coverage(nodes,query,minimumSupport,zeroFirst)
% 覆盖度是训练点对线性插值节点的最大权重，不是概率或灵敏度。
% 零流量压损节点固定为0；无证据的节点不产生待估参数。
nodes=nodes(:);query=query(:);
assert(~isempty(nodes)&&all(isfinite(nodes))&&all(diff(nodes)>0),'节点无效。');
assert(~isempty(query)&&all(isfinite(query)),'覆盖查询坐标无效。');
assert(isscalar(minimumSupport)&&minimumSupport>0&&minimumSupport<=1,'覆盖门限无效。');
q=min(max(query,nodes(1)),nodes(end));support=zeros(size(nodes));
for i=1:numel(nodes)
    if numel(nodes)==1
        support(i)=1;
    else
        hat=zeros(size(nodes));hat(i)=1;
        support(i)=max(interp1(nodes,hat,q,'linear'));
    end
end
basis=support;basis(support<minimumSupport)=0;
if zeroFirst&&nodes(1)==0,basis(1)=0;end
if any(basis>0),basis=basis/max(basis);end
map=struct('support',support,'basis',basis,'activeNode',basis>0);
end

function t=local_build(schedule,parameter,map,fuelMap,options)
mode=options.scheduleParameterization;
assert(ismember(mode,{'family_amplitude','independent_nodes'}),'未知释放方式。');
rows={};
for i=1:height(parameter)
    item=map(i);c=parameter.c_index(i);
    sigma=parameter.prior_sigma_global(i)*options.priorScaleMultiplier;
    step=parameter.difference_step(i);
    if ~item.scheduled
        rows{end+1}=local_row("h"+c,parameter.name(i),'health_constant',c, ...
            '-',sigma,sigma,parameter.lower_bound(i)-schedule.h15, ...
            parameter.upper_bound(i)-schedule.h15,step,NaN,NaN, ...
            parameter.axis_name(i)); %#ok<AGROW>
        continue;
    end
    entry=schedule.healthEntries(item.entryIndex);
    % TC27正式Excel只交付物理节点；缺省求解边界来自已声明的参数合同。
    lo=parameter.lower_bound(i);hi=parameter.upper_bound(i);
    if isfield(entry,'lowerBound'),lo=entry.lowerBound;end
    if isfield(entry,'upperBound'),hi=entry.upperBound;end
    rows=local_curve_rows(rows,"h"+c,parameter.name(i),'health',c,'-', ...
        entry.xNodes,entry.kNodes,item,sigma,lo,hi, ...
        step,mode,parameter.axis_name(i));
end
rows{end+1}=local_row('K_dist_eq','每架次等效装机畸变损失', ...
    'sortie_nuisance',NaN,'-',options.kdistPriorSigma,options.kdistPriorSigma, ...
    options.kdistLowerBound,options.kdistUpperBound,options.kdistDifferenceStep, ...
    NaN,NaN,'');
fuel=schedule.fuelBias;
rows=local_curve_rows(rows,'Wf_bias','当前架次燃油换算加性偏置', ...
    'fuel_bias',NaN,'kg/s',fuel.xNodes,fuel.biasNodes,fuelMap, ...
    options.fuelBiasPriorSigma_kgps,-options.fuelBiasBound_kgps, ...
    options.fuelBiasBound_kgps,options.fuelBiasDifferenceStep_kgps, ...
    mode,'measured_wf_ratio');
t=vertcat(rows{:});
assert(all(t.prior_sigma>0 & t.lower_bound<=0 & t.upper_bound>=0), ...
    '参数先验或边界无效。');
end

function rows=local_curve_rows(rows,id,name,type,c,unit,x,k,map,sigma,lo,hi,step,mode,axis)
id=string(id);name=string(name);
x=x(:);k=k(:);active=find(map.activeNode);
if isempty(active),return;end
if strcmp(mode,'family_amplitude')
    basis=map.basis(active);
    % 同一组节点变化，无论用幅值还是节点参数描述，正则化代价严格相等。
    % sum((B_i*a/sigma)^2) = (a / (sigma/norm(B)))^2。
    effectiveSigma=sigma/norm(basis);
    lower=max((lo-k(active))./basis);upper=min((hi-k(active))./basis);
    rows{end+1}=local_row(id+"_amplitude",name+"曲线更新幅值", ...
        string(type)+"_amplitude",c,unit,effectiveSigma,sigma,lower,upper, ...
        step,NaN,NaN,axis);
else
    for node=active(:).'
        rows{end+1}=local_row(id+sprintf('_node%02d',node), ...
            name+sprintf('节点%02d改变量',node),string(type)+"_node",c,unit, ...
            sigma,sigma,lo-k(node),hi-k(node),step,node,x(node),axis); %#ok<AGROW>
    end
end
end

function t=local_row(id,name,kind,c,unit,sigma,nodeSigma,lo,hi,step,node,x,axis)
t=table(string(id),string(name),string(kind),c,string(unit),0,sigma,lo,hi, ...
    step,node,x,string(axis),nodeSigma,'VariableNames', ...
    {'parameter_id','name','kind','c_index','unit','prior_center', ...
    'prior_sigma','lower_bound','upper_bound','difference_step','node_index', ...
    'x_node','axis_name','physical_node_sigma'});
end

function [schedule,kdist,wf]=local_apply(theta,context)
t=context.parameterContract;theta=theta(:);schedule=context.priorSchedule;
assert(numel(theta)==height(t)&&all(isfinite(theta)),'参数维数或数值无效。');
assert(all(theta>=t.lower_bound-1e-12 & theta<=t.upper_bound+1e-12), ...
    '候选参数超出已声明边界。');
for i=1:numel(context.familyMap)
    item=context.familyMap(i);rows=find(t.c_index==item.cIndex);
    if ~item.scheduled
        assert(numel(rows)==1,'常值参数只能有一个自由度。');
        schedule.h15=schedule.h15+theta(rows);continue;
    end
    if isempty(rows),continue;end
    entry=schedule.healthEntries(item.entryIndex);
    entry.kNodes=entry.kNodes(:)+local_delta(t(rows,:),theta(rows),item);
    if entry.pressureLoss && entry.xNodes(1)==0,entry.kNodes(1)=0;end
    entry.designValue=local_interp(entry.xNodes,entry.kNodes,entry.designCoordinate);
    % DLL仍使用原始节点的线性插值；不改变节点数或横坐标。
    entry.xNodesDll=entry.xNodes;entry.kNodesDll=entry.kNodes;
    entry.deltaNodesDll=entry.kNodes-entry.designValue;
    schedule.healthEntries(item.entryIndex)=entry;
end
kdist=theta(t.kind=="sortie_nuisance");
assert(isscalar(kdist),'装机畸变必须保持单个架次参数。');
rows=find(startsWith(t.kind,"fuel_bias_"));
if ~isempty(rows)
    schedule.fuelBias.biasNodes=schedule.fuelBias.biasNodes(:)+ ...
        local_delta(t(rows,:),theta(rows),context.fuelMap);
end
wf=local_interp(schedule.fuelBias.xNodes,schedule.fuelBias.biasNodes,1);
end

function delta=local_delta(t,theta,map)
delta=zeros(size(map.basis));
if height(t)==1 && endsWith(t.kind,"_amplitude")
    delta=map.basis*theta;
else
    assert(all(endsWith(t.kind,"_node")),'曲线不能混用幅值和节点参数。');
    assert(isequal(t.node_index,find(map.activeNode)),'活动节点合同不一致。');
    delta(t.node_index)=theta;
end
end

function v=local_interp(x,k,q)
q=min(max(q,min(x)),max(x));
if numel(x)==1,v=k(1);else,v=interp1(x,k,q,'linear');end
end
