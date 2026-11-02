function output = sht_identification_schedule_nodes(action, varargin)
%SHT_IDENTIFICATION_SCHEDULE_NODES 仅由训练工况形成可变节点及移动节点。
% 分组用于B阶段常值辨识；几何节点不必与组一一对应。复制同组估计值
% 不增加该组的证据权重。真值、测试集、DLL均不进入这个纯数值函数。
switch lower(action)
    case 'build'
        output = local_build(varargin{:});
    case 'move'
        output = local_move(varargin{:});
    otherwise
        error('SHT:IdentificationNodes:Action','未知节点动作：%s。',action);
end
end

function s = local_build(x, group, groupValue, pressureLoss, axisName, options)
x=double(x(:)); group=double(group(:)); groupValue=double(groupValue(:));
assert(numel(x)==numel(group) && all(isfinite(x)) && all(x>0), ...
    'SHT:IdentificationNodes:Coordinate','工作横坐标必须有限、为正且逐工况对应。');
assert(all(group>=1 & group<=numel(groupValue) & group==fix(group)), ...
    'SHT:IdentificationNodes:Group','工况组编号不合法。');
span=max(x)-min(x); typical=median(abs(x));
% 分组门限与曲线分辨尺度分开。下列工程门限由TC24入口显式配置。
fixedReference=isfield(options,'nodeReferencePolicy') && ...
    strcmp(options.nodeReferencePolicy,'fixed_engineering');
reference=struct();
if fixedReference
    assert(isfield(options.nodeEngineeringReference,axisName), ...
        'SHT:IdentificationNodes:Reference','缺少%s固定工程参考。',axisName);
    reference=options.nodeEngineeringReference.(axisName);
    assert(all(isfinite([reference.minimum,reference.maximum,reference.design])) && ...
        reference.minimum>0 && reference.maximum>reference.minimum && reference.design>0, ...
        'SHT:IdentificationNodes:Reference','%s固定工程参考无效。',axisName);
    referenceSpan=reference.maximum-reference.minimum;
    if contains(axisName,'corrected_speed')
        threshold=options.nodeSpeedAbsoluteSpacing;
    elseif contains(axisName,'pressure_ratio')
        threshold=options.nodePressureRatioSpanFraction*referenceSpan;
    elseif strcmp(axisName,'measured_wf_ratio')
        threshold=options.nodeFuelSpanFraction*referenceSpan;
    else
        threshold=max(options.nodeFlowSpanFraction*referenceSpan, ...
            options.nodeFlowDesignFloorFraction*reference.design);
    end
    threshold=max(options.nodeMergeAbsolute,threshold);
elseif contains(axisName,'corrected_speed')
    physicalFloor=options.nodeSpeedAbsoluteSpacing;
elseif contains(axisName,'pressure_ratio')
    physicalFloor=options.nodePressureRatioRelativeSpacing*typical;
else
    physicalFloor=options.nodeFlowRelativeSpacing*typical;
end
if ~fixedReference
    threshold=max([options.nodeMergeAbsolute,physicalFloor, ...
        options.nodeAdaptiveSpanFraction*span]);
end

% 逐工况候选继承组内纵坐标。每个组的总权重仍等于原工况数，
% 不是候选节点数；同组拆点和跨组合点只改变权重的分配位置。
[~,order]=sort(x); members={}; first=1;
while first<=numel(order)
    last=first;
    while last<numel(order) && x(order(last+1))-x(order(first))<=threshold
        last=last+1;
    end
    members{end+1,1}=order(first:last); %#ok<AGROW>
    first=last+1;
end
nodeX=cellfun(@(rows) mean(x(rows)),members);
nodeY=cellfun(@(rows) mean(groupValue(group(rows))),members);
% 两端以真实训练覆盖范围为支撑；近乎单坐标的数据不凭空增自由度。
if numel(nodeX)>1
    nodeX(1)=min(x); nodeX(end)=max(x);
elseif fixedReference && pressureLoss
    % 一个工作簇只有一个自由值；零流量至最小工作流量线性接入，
    % 其后端点截断。不能人为复制两个可独立辨识的端点。
    nodeX=min(x);
elseif ~fixedReference && span>options.nodeMergeAbsolute
    nodeX=[min(x);max(x)]; nodeY=repmat(nodeY,2,1);
    members={find(x==min(x));find(x==max(x))};
end
candidateX=nodeX; candidateY=nodeY; candidateMembers=members;
selection=struct('performed',false,'selectedWorkingNodes',numel(nodeX));
if strcmp(axisName,'burner_inlet_corrected_mass_flow') && ...
        options.burnerAutomaticNodes && numel(nodeX)>2 && numel(groupValue)>=3
    [nodeX,nodeY,selection]=local_select_burner( ...
        x,group,groupValue,nodeX,options);
    [~,indices]=ismember(nodeX,candidateX);
    members=candidateMembers(indices);
end
conflicts=zeros(numel(candidateX),1);
for i=1:numel(candidateX)
    values=groupValue(group(candidateMembers{i}));
    conflicts(i)=max(values)-min(values);
end
formation=struct('schemaVersion','training_evidence_nodes_v1', ...
    'pointCoordinates',x,'pointGroup',group,'nodePointRows',{members}, ...
    'groupValues',groupValue,'candidateX',candidateX,'candidateY',candidateY, ...
    'mergeThreshold',threshold,'candidateVerticalSpread',conflicts, ...
    'selection',selection,'groupEvidenceWeight',accumarray(group,1, ...
    [numel(groupValue),1]),'initialEqualValuesAreNotTied',true);
formation.fixedEngineeringReferenceUsed=fixedReference;
formation.engineeringReference=reference;
formation.candidatePointRows=candidateMembers;
s=struct('xNodes',nodeX,'kNodes',nodeY,'nodeFormation',formation);
if pressureLoss
    s.xNodes=[0;nodeX]; s.kNodes=[0;nodeY];
end
assert(numel(s.xNodes)<=32,'SHT:IdentificationNodes:Capacity', ...
    '形成%d个节点，超过DLL容量32；请提高工程合并门限，禁止静默重采样。',numel(s.xNodes));
end

function [nodes,values,detail]=local_select_burner(x,group,y,candidates,options)
% B估计是组级常值，不将同组复制点当成独立数据。拟合矩阵每一行
% 为该组各工况插值权重的平均。留出整组后，仅由剩余工况重新形成
% 候选横坐标和两端范围；不能留下一个只由被留出组支撑的自由端点。
% 这只是低成本构造诊断，不声称替代发动机级独立泛化验证。
g=numel(y); counts=accumarray(group,1,[g,1]);
maximum=min(numel(candidates),g-1);
nodeCounts=(2:maximum).'; scores=nan(numel(nodeCounts),g);
fullNodes=cell(numel(nodeCounts),1); fullValues=fullNodes;
foldNodes=cell(size(scores));foldValues=cell(size(scores));
foldCondition=nan(size(scores));foldCount=zeros(size(scores));
foldCandidates=cell(g,1);foldRange=zeros(g,2);
foldOptions=options;foldOptions.burnerAutomaticNodes=false;
for held=1:g
    rows=group~=held;
    [used,~,compactGroup]=unique(group(rows));
    f=local_build(x(rows),compactGroup,y(used),true, ...
        'burner_inlet_corrected_mass_flow',foldOptions);
    foldCandidates{held}=f.nodeFormation.candidateX;
    foldRange(held,:)=[min(x(rows)),max(x(rows))];
end
fullCount=zeros(size(nodeCounts));fullCondition=nan(size(nodeCounts));
for j=1:numel(nodeCounts)
    n=nodeCounts(j);
    for held=1:g
        keep=true(g,1); keep(held)=false;
        [knots,v,condition]=local_best_fit( ...
            x,group,y,counts,keep,foldCandidates{held},n);
        a=local_group_basis(x,group,knots,g);
        scores(j,held)=(a(held,:)*v-y(held))^2;
        foldNodes{j,held}=knots;foldValues{j,held}=v;
        foldCount(j,held)=numel(knots);foldCondition(j,held)=condition;
    end
    [fullNodes{j},fullValues{j},fullCondition(j)]=local_best_fit( ...
        x,group,y,counts,true(g,1),candidates,n);
    fullCount(j)=numel(fullNodes{j});
end
meanScore=mean(scores,2); se=std(scores,0,2)/sqrt(g);
[best,bestIndex]=min(meanScore);
limit=best+options.burnerSelectionStandardErrors*se(bestIndex);
selected=find(meanScore<=limit+1e-20,1,'first');
nodes=fullNodes{selected}; values=fullValues{selected};
detail=struct('performed',true,'method','supported_leave_group_out_one_se', ...
    'scores',table(nodeCounts,meanScore,se,fullCount,fullCondition, ...
    'VariableNames',{'working_node_count','mean_squared_error','standard_error', ...
    'full_fit_node_count','full_fit_condition'}), ...
    'foldSquaredErrors',scores,'selectedWorkingNodes',numel(nodes), ...
    'selectedWorkingCoordinates',nodes,'selectionLimit',limit, ...
    'testDataUsed',false,'sharedStageAPriorMayCorrelateGroupEstimates',true);
detail.foldTrainingRange=foldRange;
detail.foldCandidates=foldCandidates;detail.foldNodes=foldNodes;
detail.foldValues=foldValues;detail.foldWorkingNodeCounts=foldCount;
detail.foldFitConditions=foldCondition;
detail.endpointPolicy='fixed_zero_origin_and_upper_nearest_endpoint';
detail.rankPolicy='reject_unresolved_topology_then_reduce_node_count';
detail.relativeRankTolerance=sqrt(eps);
end

function combos=local_combinations(n,m)
if m==1
    combos=1;
elseif m==2
    combos=[1,n];
else
    interior=nchoosek(2:n-1,m-2);
    combos=[ones(size(interior,1),1),interior,repmat(n,size(interior,1),1)];
end
end

function [nodes,v,condition]=local_best_fit(x,group,y,counts,keep,candidates,requested)
% 缺少独立组支撑时减少几何自由度，而不是靠极弱岭项给不可观测端点
% 造出唯一解。SVD仅检查插值矩阵的数值秩；可解时仍是无阻尼最小二乘。
% 不改变A/B/D的正则化方式、强度或TSVD保留数。
nodes=[];v=[];condition=NaN;
w=sqrt(counts(keep)/sum(counts(keep)));yw=y(keep).*w;
for n=min([requested,numel(candidates),sum(keep)]):-1:1
    combos=local_combinations(numel(candidates),n);best=Inf;
    for c=1:size(combos,1)
        knots=candidates(combos(c,:));knots=knots(:);
        a=local_group_basis(x,group,knots,numel(y));aw=a(keep,:).*w;
        singular=svd(aw,0);
        if singular(end)<=sqrt(eps)*singular(1),continue;end
        candidate=aw\yw;
        cost=sum((aw*candidate-yw).^2);
        if cost<best
            best=cost;nodes=knots;v=candidate;
            condition=singular(1)/singular(end);
        end
    end
    if ~isempty(nodes),return;end
end
error('SHT:IdentificationNodes:Fit','剩余训练组未能形成可解的燃烧室节点拟合。');
end

function a=local_group_basis(x,group,nodes,g)
% 燃烧室压损固定(0,0)，不把原点当成待拟合变量。留出最低组时，
% 被留出点可能低于首个剩余工作节点，此时从原点线性接入；上端截断。
% 训练点自身都在剩余工作范围内；这项规则主要影响留组预测。
b=zeros(numel(x),numel(nodes));
for i=1:numel(x)
    if x(i)<=nodes(1),b(i,1)=max(0,x(i)/nodes(1));continue;end
    if x(i)>=nodes(end),b(i,end)=1;continue;end
    j=find(nodes<=x(i),1,'last');
    fraction=(x(i)-nodes(j))/(nodes(j+1)-nodes(j));
    b(i,j)=1-fraction; b(i,j+1)=fraction;
end
a=zeros(g,numel(nodes));
for i=1:g,a(i,:)=mean(b(group==i,:),1);end
end

function result=local_move(entry,newPointX)
% 只移动已有支撑位置，不重新由旧组常值构造曲线，也不做自动拆并。
% 横坐标不变时原样返回，避免反复采样/平均改变折点纵坐标。
result=struct('entry',entry,'changed',false,'orderConflict',false, ...
    'maximumIntervalRelativeShift',0,'maximumFunctionChange',0, ...
    'uncoveredPointCount',0,'maximumOutsideIntervalFraction',0);
if ~isfield(entry,'nodeFormation') || isempty(fieldnames(entry.nodeFormation))
    return;
end
f=entry.nodeFormation; x=double(newPointX(:));
assert(numel(x)==numel(f.pointCoordinates) && all(isfinite(x)) && all(x>0), ...
    'SHT:IdentificationNodes:Move','更新坐标必须与训练工况逐行对应。');
offset=double(entry.pressureLoss); oldX=entry.xNodes(1+offset:end);
newX=oldX;
for i=1:numel(newX)
    newX(i)=mean(x(f.nodePointRows{i}));
end
if numel(newX)>1
    newX(1)=min(x);newX(end)=max(x);
elseif offset
    newX=min(x);
end
interval=max(diff(oldX),1e-12);
if isempty(interval),localScale=max(abs(oldX),1e-12);else
    localScale=[interval(1);min([interval(1:end-1),interval(2:end)],[],2);interval(end)];
end
result.maximumIntervalRelativeShift=max(abs(newX-oldX)./localScale);
outside=max([oldX(1)-x,x-oldX(end),zeros(size(x))],[],2);
result.uncoveredPointCount=sum(outside>1e-12);
result.maximumOutsideIntervalFraction=max(outside)/max(min(localScale([1,end])),1e-12);
if any(diff(newX)<=1e-12)
    result.orderConflict=true;return;
end
if max(abs(newX-oldX))<=1e-12
    return;
end
allX=newX;if offset,allX=[0;newX];end
clipped=min(max(allX,entry.xNodes(1)),entry.xNodes(end));
if numel(entry.xNodes)==1
    allY=repmat(entry.kNodes,numel(allX),1);
else
    allY=interp1(entry.xNodes,entry.kNodes,clipped,'linear');
end
if offset,allY(1)=0;end
query=unique([entry.xNodes;allX;x]);
oldValue=local_interp(entry.xNodes,entry.kNodes,query);
newValue=local_interp(allX,allY,query);
result.maximumFunctionChange=max(abs(newValue-oldValue));
result.entry.xNodes=allX;result.entry.kNodes=allY;
result.entry.nodeFormation.pointCoordinates=x;
result.changed=true;
end

function y=local_interp(x,v,q)
if numel(x)==1,y=repmat(v,size(q));return;end
y=interp1(x,v,min(max(q,x(1)),x(end)),'linear');
end
