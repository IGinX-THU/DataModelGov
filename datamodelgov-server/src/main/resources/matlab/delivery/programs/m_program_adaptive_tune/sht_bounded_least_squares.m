function [x,resnorm,residual,exitflag,info]=sht_bounded_least_squares(A,b,lb,ub,x,Aeq,beq,options)
%SHT_BOUNDED_LEAST_SQUARES 无工具箱可行活动集有界线性最小二乘。
% 求min||A*x-b||^2，满足lb<=x<=ub、Aeq*x=beq。有等式时x必须可行。
% 每次在活动约束的零空间解最小二乘；到边界的步长仅用于维持约束，
% 不是辨识A/B/D的统一更新比例。不满足KKT时不得以步长小冒充收敛。
if nargin<6 || isempty(Aeq),Aeq=zeros(0,size(A,2));beq=zeros(0,1);end
if nargin<8,options=struct();end
if ~isfield(options,'maxIterations'),options.maxIterations=1000;end
if ~isfield(options,'tolerance'),options.tolerance=1e-10;end
n=size(A,2);b=b(:);lb=lb(:);ub=ub(:);x=x(:);beq=beq(:);
assert(size(A,1)==numel(b) && all([numel(lb),numel(ub),numel(x)]==n));
assert(size(Aeq,2)==n && size(Aeq,1)==numel(beq) && all(lb<=ub));
assert(all(isfinite(A(:))) && all(isfinite(b)) && all(isfinite(Aeq(:))) && all(isfinite(beq)));
tol=options.tolerance;boundTol=tol*(1+norm(x,inf));
x=min(max(x,lb),ub);
assert(norm(Aeq*x-beq,inf)<=100*tol*(1+norm(beq,inf)), ...
    'SHT:BoundedLS:FeasibleStart','等式约束最小二乘需要可行初值。');
active=zeros(n,1);active(x<=lb+boundTol)=-1;active(x>=ub-boundTol)=1;
fixed=lb==ub;active(fixed)=1;exitflag=0;eyeN=eye(n);kkt=inf;
for iteration=1:options.maxIterations
    free=find(active==0);p=zeros(n,1);
    if ~isempty(free)
        if isempty(Aeq),Z=eye(numel(free));else,Z=null(Aeq(:,free));end
        if ~isempty(Z),p(free)=Z*local_pinv_solve(A(:,free)*Z,b-A*x);end
    end
    if norm(p,inf)<=tol*(1+norm(x,inf))
        indices=find(active~=0);C=[Aeq;eyeN(indices,:).*active(indices)];
        gradient=A'*(A*x-b);lambda=local_pinv_solve(C',-gradient);
        dual=lambda(size(Aeq,1)+1:end);dual(fixed(indices))=max(dual(fixed(indices)),0);
        stationarity=norm(gradient+C'*lambda,inf);
        kkt=max([stationarity;max([0;-dual])]);
        if kkt<=100*tol*(1+norm(A,'fro')*norm(A*x-b))
            exitflag=1;break;
        end
        candidates=find(~fixed(indices) & dual < -tol);
        if isempty(candidates),break;end
        [~,j]=min(dual(candidates));active(indices(candidates(j)))=0;
        continue;
    end
    step=1;hit=0;side=0;
    for j=free.'
        if p(j)>tol && isfinite(ub(j)),a=(ub(j)-x(j))/p(j);s=1;
        elseif p(j)<-tol && isfinite(lb(j)),a=(lb(j)-x(j))/p(j);s=-1;
        else,continue;end
        if a<step,step=max(0,a);hit=j;side=s;end
    end
    x=x+step*p;
    if hit>0,active(hit)=side;if side<0,x(hit)=lb(hit);else,x(hit)=ub(hit);end,end
end
residual=A*x-b;resnorm=sum(residual.^2);
info=struct('iterations',iteration,'kktResidual',kkt, ...
    'equalityResidual',norm(Aeq*x-beq,inf), ...
    'boundViolation',max([0;lb-x;x-ub]),'backend','base_feasible_active_set');
if info.equalityResidual>1000*tol*(1+norm(beq,inf)) || info.boundViolation>1000*tol
    exitflag=-2;
end
end

function x=local_pinv_solve(A,b)
if isempty(A),x=zeros(size(A,2),1);return;end
[U,S,V]=svd(A,'econ');s=diag(S);rankValue=sum(s>max(size(A))*eps(max(s)));
if rankValue==0,x=zeros(size(A,2),1);return;end
x=V(:,1:rankValue)*((U(:,1:rankValue)'*b)./s(1:rankValue));
end
