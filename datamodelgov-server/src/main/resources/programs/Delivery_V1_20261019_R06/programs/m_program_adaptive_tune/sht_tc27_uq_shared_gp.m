function out=sht_tc27_uq_shared_gp(action,varargin)
%SHT_TC27_UQ_SHARED_GP 全潜空间共享Matern-5/2核的多输出GP。
% 所有主参数进入非线性项，多个POD系数共用一次核矩阵分解，避免在
% SMC中逐个调用fitrgp。核尺度仅由训练数据确定，不读取盲测/参数真值。
switch action
    case 'fit'
        X=varargin{1};Y=varargin{2};scale=varargin{3};
        X=X./scale;dist=distance(X,X);n=size(X,1);
        opt=optimset('Display','off','MaxIter',100,'MaxFunEvals',200,'TolX',1e-4);
        v=fminsearch(@objective,log([sqrt(size(X,2)),.001]),opt);
        [cost,L]=objective(v);alpha=L.'\(L\Y);
        out=struct('X',X,'inputScale',scale,'length',exp(v(1)), ...
            'nugget',exp(v(2)),'alpha',alpha,'cost',cost,'trainingCount',n);
    case 'predict'
        s=varargin{1};X=varargin{2}./s.inputScale;
        out=kernel(distance(X,s.X),s.length)*s.alpha;
    otherwise,error('未知共享GP动作。');
end
    function [cost,L]=objective(v)
        L=[];ell=exp(v(1));noise=exp(v(2));
        if ell<.05||ell>1e4||noise<1e-7||noise>.2,cost=1e100+sum(v.^2);return;end
        [L,flag]=chol(kernel(dist,ell)+(noise^2+1e-10)*eye(n),'lower');
        if flag,cost=1e100;return;end
        z=L\Y;cost=.5*sum(z(:).^2)+size(Y,2)*sum(log(diag(L)));
    end
end
function d=distance(x,y)
d=sqrt(max(0,sum(x.^2,2)+sum(y.^2,2).'-2*x*y.'));
end
function k=kernel(d,ell)
r=sqrt(5)*d/ell;k=(1+r+r.^2/3).*exp(-r);
end
