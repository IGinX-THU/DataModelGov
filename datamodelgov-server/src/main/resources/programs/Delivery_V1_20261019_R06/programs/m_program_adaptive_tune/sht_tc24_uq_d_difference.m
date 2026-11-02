function varargout=sht_tc24_uq_d_difference(action,varargin)
%SHT_TC24_UQ_D_DIFFERENCE D局部求解的有界差分，物理边界不能产生零步长。
switch action
    case 'residual'
        [varargout{1:nargout}]=residualDerivative(varargin{:});
    case 'prior'
        [varargout{1:nargout}]=priorDerivative(varargin{:});
    otherwise
        error('TC24:D:DifferenceAction','未知D差分操作。');
end
end

function [J,count,audit]=residualDerivative(evaluate,x,current,h,lo,hi,mode)
n=numel(x);count=0;J=nan(size(current.residual,1),n);pending=1:n;
kind=strings(n,1);used=zeros(n,1);retries=zeros(n,1);
for attempt=1:7
    candidates=zeros(n,2*numel(pending));weights=zeros(numel(pending),3);
    for a=1:numel(pending)
        j=pending(a);[offset,w,~,kind(j)]=stencil(x(j),h(j),lo(j),hi(j),mode);
        candidates(:,2*a-1:2*a)=repmat(x,1,2);
        candidates(j,2*a-1:2*a)=x(j)+offset(2:3);
        weights(a,:)=w;used(j)=max(abs(offset));
    end
    if strcmp(mode,'forward')
        % 前向公式第二个扰动权重为零，不再为它调用DLL。
        out=evaluate(candidates(:,1:2:end));
    else
        out=evaluate(candidates);
    end
    count=count+out.dllEvaluationCount;
    failed=[];
    for a=1:numel(pending)
        j=pending(a);ids=2*a-1:2*a;
        if strcmp(mode,'forward'),ids=a;end
        if all(out.valid(ids)) && all(isfinite(out.residual(:,ids)),'all')
            if strcmp(mode,'forward')
                J(:,j)=[current.residual,out.residual(:,ids)]*weights(a,1:2).';
            else
                J(:,j)=[current.residual,out.residual(:,ids)]*weights(a,:).';
            end
        else
            failed(end+1)=j;h(j)=h(j)/2;retries(j)=retries(j)+1; %#ok<AGROW>
        end
    end
    pending=failed;if isempty(pending),break;end
end
assert(isempty(pending) && all(isfinite(J),'all'),'TC24:D:DerivativeInvalid', ...
    'D差分仍有无效候选；未将失败方向置零。');
audit=table((1:n).',kind,used,retries,'VariableNames', ...
    {'parameter','stencil','maximum_offset','retry_count'});
end

function [g,H,audit]=priorDerivative(f,x,h,lo,hi)
% 同一模板用于梯度、对角曲率及交叉曲率；所有计算只涉及先验代数。
n=numel(x);offset=zeros(n,3);w1=offset;w2=offset;kind=strings(n,1);
for j=1:n
    [offset(j,:),w1(j,:),w2(j,:),kind(j)]=stencil(x(j),h(j),lo(j),hi(j),'central');
end
f0=f(x);g=zeros(n,1);H=zeros(n);
for j=1:n
    points=repmat(x,1,3);points(j,:)=points(j,:)+offset(j,:);
    values=f(points);assert(all(isfinite(values)),'TC24:D:PriorDerivative','先验差分非有限。');
    g(j)=values*w1(j,:).';H(j,j)=values*w2(j,:).';
    k=(j+1):n;if isempty(k),continue;end
    cross=zeros(1,numel(k));
    for a=1:3
        if w1(j,a)==0,continue;end
        for b=1:3
            if all(w1(k,b)==0),continue;end
            points=repmat(x,1,numel(k));points(j,:)=points(j,:)+offset(j,a);
            for c=1:numel(k),points(k(c),c)=points(k(c),c)+offset(k(c),b);end
            values=f(points);
            assert(all(isfinite(values)),'TC24:D:PriorDerivative','先验交叉差分非有限。');
            cross=cross+values.*(w1(j,a)*w1(k,b).');
        end
    end
    H(j,k)=cross;H(k,j)=cross.';
end
assert(isfinite(f0) && all(isfinite(H),'all'),'TC24:D:PriorDerivative','先验曲率无效。');
H=(H+H.')/2;audit=table((1:n).',kind,'VariableNames',{'parameter','stencil'});
end

function [offset,w1,w2,kind]=stencil(x,h,lo,hi,mode)
% 第一个点始终是当前点，另外两个点用于中心或二阶单侧差分。
room=[x-lo,hi-x];minimum=64*eps(max(1,abs(x)));
assert(all(room>=-minimum) && h>0,'TC24:D:DifferenceBounds','差分中心或请求步长无效。');
room=max(room,0);
if strcmp(mode,'central') && min(room)>=h
    offset=[0,h,-h];w1=[0,1,-1]/(2*h);w2=[-2,1,1]/h^2;kind="central";
else
    [available,side]=max(room);direction=2*side-3;
    h=min(h,.4*available);
    assert(h>minimum,'TC24:D:DifferenceResolution','物理支撑太窄，无法形成可分辨差分。');
    d=direction*h;offset=[0,d,2*d];
    if strcmp(mode,'forward'),w1=[-1,1,0]/d;else,w1=[-3,4,-1]/(2*d);end
    w2=[1,-2,1]/d^2;kind="one_sided_second_order";
    if strcmp(mode,'forward'),kind="one_sided_first_order";end
    if strcmp(mode,'forward'),kind="one_sided_first_order";end
end
assert(all(isfinite([offset,w1,w2])) && offset(2)~=0 && offset(3)~=0, ...
    'TC24:D:DifferenceResolution','差分步长或权重非有限。');
end
