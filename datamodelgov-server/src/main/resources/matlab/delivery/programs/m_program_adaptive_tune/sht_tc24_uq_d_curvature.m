function [precision,audit]=sht_tc24_uq_d_curvature(cost,x,g,H,J,lo,hi,options)
%SHT_TC24_UQ_D_CURVATURE 用独立尺度的精确代价检查局部曲率和非二次误差。
% 所有方向在原局部高斯白化坐标中定义；不改变先验、似然或物理边界。
% 少量方向校核不能宣称恢复完整Hessian，未通过时保留原提议并报告。
n=numel(x);precision=H;calls=0;
audit=struct('enabled',true,'applied',false,'reason','not_positive_reference', ...
    'dllEvaluationCount',0,'directionCount',0,'crossCount',0);
[L,flag]=chol(H,'lower');if flag~=0,return;end
A=L.'\eye(n);information=(J*A).'*(J*A);
[V,D]=eig((information+information.')/2);[d,order]=sort(diag(D));V=V(:,order);
k=min(n,option('curvatureDirections',12));
ids=unique([1:ceil(k/2),n-floor(k/2)+1:n]);directions=A*V(:,ids);k=numel(ids);
candidate=eye(k);valid=false(k,1);steps=zeros(k,1);
rows=repmat(struct('direction',0,'data_curvature',NaN,'step',NaN, ...
    'curvature_h',NaN,'curvature_half_h',NaN,'stable',false, ...
    'linear_range_error',NaN),k,1);
[f0,c]=cost(x);calls=calls+c;
for j=1:k
    v=directions(:,j);room=twoSidedRoom(v);h=min(.04,.2*room);steps(j)=h;
    rows(j).direction=ids(j);rows(j).data_curvature=d(ids(j));rows(j).step=h;
    if h<1e-4,continue;end
    [f,c]=cost(x+v*[h,-h,h/2,-h/2]);calls=calls+c;
    if ~all(isfinite(f)),continue;end
    h1=(f(1)+f(2)-2*f0)/h^2;h2=(f(3)+f(4)-2*f0)/(h/2)^2;
    stable=abs(h1-h2)<=.05*max([1,abs(h1),abs(h2)]);
    rows(j).curvature_h=h1;rows(j).curvature_half_h=h2;rows(j).stable=stable;
    if stable && h2>1e-6,candidate(j,j)=h2;valid(j)=true;end
end
% 检查少量混合方向，避免仅修正对角就把未核查交叉曲率当作零。
pairs=zeros(0,2);if k>=2,pairs=nchoosek(1:k,2);end
maximum=option('curvatureCrossPairs',3);
crossRows=zeros(0,5);
if ~isempty(pairs)
    score=abs(candidate(sub2ind([k,k],pairs(:,1),pairs(:,1)))-1)+ ...
        abs(candidate(sub2ind([k,k],pairs(:,2),pairs(:,2)))-1);
    [~,order]=sort(score,'descend');pairs=pairs(order(1:min(maximum,end)),:);
    for a=1:size(pairs,1)
        j=pairs(a,1);l=pairs(a,2);if ~valid(j) || ~valid(l),continue;end
        h=min(steps([j,l]))/2;if h<1e-4,continue;end
        v=directions(:,j);u=directions(:,l);signs=[1,1,-1,-1;1,-1,1,-1];
        [f,c]=cost(x+[v,u]*signs*h);calls=calls+c;
        [half,c]=cost(x+[v,u]*signs*(h/2));calls=calls+c;
        if ~all(isfinite([f,half])),continue;end
        h1=(f(1)-f(2)-f(3)+f(4))/(4*h^2);
        h2=(half(1)-half(2)-half(3)+half(4))/h^2;
        stable=abs(h1-h2)<=.05*max([1,abs(h1),abs(h2)]);
        crossRows(end+1,:)=[ids(j),ids(l),h1,h2,stable]; %#ok<AGROW>
        if stable,candidate(j,l)=h2;candidate(l,j)=h2;end
    end
end
W=H*directions;proposed=H+W*(candidate-eye(k))*W.';proposed=(proposed+proposed.')/2;
[~,flag]=chol(proposed);
% 验收使用远大于求导步长的原后验代价，防止局部曲率更准而区间更差。
testDirections=directions;
if k>=2,testDirections=[testDirections,(directions(:,1)+directions(:,end))/sqrt(2)];end
errors=zeros(0,3);
for j=1:size(testDirections,2)
    v=testDirections(:,j);t=min([.5, .4*twoSidedRoom(v)]);
    if t<.02,continue;end
    offsets=[-t,t,-2*t,2*t];[f,c]=cost(x+v*offsets);calls=calls+c;
    expected=f0+(g.'*v)*offsets+.5*(v.'*H*v)*offsets.^2;
    changed=f0+(g.'*v)*offsets+.5*(v.'*proposed*v)*offsets.^2;
    good=isfinite(f);if ~any(good),continue;end
    den=1+abs(f(good)-f0);
    errors=[errors;[abs(f(good)-expected(good))./den; ...
        abs(f(good)-changed(good))./den;abs(f(good)-f0)].']; %#ok<AGROW>
    if j<=k,rows(j).linear_range_error=max(abs(f(good)-expected(good))./den);end
end
audit.reason='reference_retained';
if flag==0 && ~isempty(errors) && any(valid) && ...
        mean(errors(:,2))<=mean(errors(:,1)) && max(errors(:,2))<=1.05*max(errors(:,1))+1e-8
    precision=proposed;audit.applied=true;audit.reason='directional_holdout_improved';
elseif flag~=0
    audit.reason='observed_subspace_not_positive';
end
audit.directionCount=k;audit.crossCount=size(crossRows,1);audit.directions=struct2table(rows);
audit.crossTerms=array2table(crossRows,'VariableNames', ...
    {'direction1','direction2','curvature_h','curvature_half_h','stable'});
audit.holdoutErrors=array2table(errors,'VariableNames',{'original','proposed','cost_change'});
audit.proposedPrecision=proposed;audit.referencePrecision=H;
audit.localDirections=directions;audit.dllEvaluationCount=calls;
audit.minimumProposedEigenvalue=min(eig(candidate));
audit.targetChanged=false;audit.fullObservedHessian=false;audit.truthRead=false;audit.testDataRead=false;
fprintf('TC24-D curvature: %d directions, %d cross checks, applied=%d (%s).\n', ...
    k,audit.crossCount,audit.applied,audit.reason);
    function room=twoSidedRoom(v)
        active=abs(v)>1e-14;
        room=min(min((hi(active)-x(active))./abs(v(active)), ...
            (x(active)-lo(active))./abs(v(active))));
        if isempty(room),room=0;end
    end
    function value=option(name,fallback)
        value=fallback;if isfield(options,name),value=options.(name);end
    end
end
