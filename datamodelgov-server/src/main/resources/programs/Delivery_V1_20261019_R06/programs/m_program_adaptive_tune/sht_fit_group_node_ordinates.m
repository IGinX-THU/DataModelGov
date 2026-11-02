function s=sht_fit_group_node_ordinates(s,pressureLoss,lower,upper)
%SHT_FIT_GROUP_NODE_ORDINATES 固定节点，直接拟合B组常值对应的曲线组均值。
% 第一目标：最小化按原工况数加权的组均值误差；第二目标：在同样拟合
% 程度的解中选取最接近原C节点值的一组。第二目标只消除欠定方向，
% 不施加统一增量比例、平滑项或新的物理先验，也不读取真值/测试集。
% 常规情形用无阻尼SVD解析求解；越界时用无工具箱活动集依次求两个凸问题。
f=s.nodeFormation;x=f.pointCoordinates(:);group=f.pointGroup(:);
y=f.groupValues(:);knots=s.xNodes(:);reference=s.kNodes(:);
assert(isfinite(lower) && isfinite(upper) && lower<upper);
assert(all(isfinite([x;y;knots;reference])) && all(diff(knots)>0));
assert(numel(reference)==numel(knots) && numel(group)==numel(x));
if pressureLoss,assert(knots(1)==0 && reference(1)==0);end
free=(1+double(pressureLoss)):numel(knots);n=numel(free);g=numel(y);
counts=accumarray(group,1,[g,1]);assert(all(counts>0));
% 每一行是一个工况的线性插值权重；超出范围时截断到最近端点。
pointBasis=zeros(numel(x),numel(knots));
for i=1:numel(x)
    if x(i)<=knots(1),pointBasis(i,1)=1;continue;end
    if x(i)>=knots(end),pointBasis(i,end)=1;continue;end
    j=find(knots<=x(i),1,'last');t=(x(i)-knots(j))/(knots(j+1)-knots(j));
    pointBasis(i,j)=1-t;pointBasis(i,j+1)=t;
end
basis=zeros(g,n);
for i=1:g,basis(i,:)=mean(pointBasis(group==i,free),1);end
w=sqrt(counts/sum(counts));a=basis.*w;
% 单条曲线按其物理边界跨度无量纲化，保证燃油kg/s与系数有相同数值精度。
scale=upper-lower;lo=lower/scale;hi=upper/scale;
r=min(max(reference(free),lower),upper)/scale;b=y.*w/scale;
[u,d,v]=svd(a,'econ');singular=diag(d);
rankTolerance=sqrt(eps)*singular(1);rankValue=sum(singular>rankTolerance);
ur=u(:,1:rankValue);vr=v(:,1:rankValue);sr=singular(1:rankValue);
q=r+vr*((ur'*(b-a*r))./sr);bounded=false;
if any(q<lo | q>hi)
    % 不能简单截断越界解：截断会破坏其余节点的联合最小二乘条件。
    opt=struct('tolerance',1e-12,'maxIterations',1000);
    lb=repmat(lo,n,1);ub=repmat(hi,n,1);
    [first,~,~,exit1]=sht_bounded_least_squares(a,b,lb,ub,r,[],[],opt);
    % V_r的行约束固定第一目标的预测，只在其零空间中最小化对参考曲线的改动。
    [q,~,~,exit2]=sht_bounded_least_squares(eye(n),r,lb,ub,first,vr',vr'*first,opt);
    assert(exit1>0 && exit2>0 && norm(a*(q-first))<1e-8, ...
        'SHT:COrdinates:BoundedFit','受约束纵坐标拟合未得到合格解。');
    bounded=true;
end
assert(all(q>=lo-1e-10 & q<=hi+1e-10));
q=min(max(q,lo),hi);values=q*scale;
before=basis*(r*scale)-y;after=basis*values-y;
beforeCost=sum((w.*before).^2);afterCost=sum((w.*after).^2);
assert(afterCost<=beforeCost+1e-12*scale^2, ...
    'SHT:COrdinates:Cost','直接拟合不应劣于原C曲线的B组均值误差。');
s.kNodes(free)=values;if pressureLoss,s.kNodes(1)=0;end
s.nodeFormation.ordinateFit=struct('method','bounded_group_mean_minimum_change', ...
    'referenceValues',reference,'fittedValues',s.kNodes, ...
    'groupBasis',basis,'groupWeights',w.^2,'groupValues',y, ...
    'beforeGroupResidual',before,'afterGroupResidual',after, ...
    'beforeWeightedRmse',sqrt(beforeCost),'afterWeightedRmse',sqrt(afterCost), ...
    'singularValues',singular,'rank',rankValue,'freeNodeCount',n, ...
    'nullity',n-rankValue,'condition',singular(1)/sr(end), ...
    'boundedSolverUsed',bounded,'maximumValueChange',max(abs(values-reference(free))), ...
    'coordinatesChanged',false,'testOrTruthUsed',false);
end
