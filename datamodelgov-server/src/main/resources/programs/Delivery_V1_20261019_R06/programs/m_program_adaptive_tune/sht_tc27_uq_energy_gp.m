function out=sht_tc27_uq_energy_gp(X,Y,scale,outputEnergy)
%SHT_TC27_UQ_ENERGY_GP 以实际白化输出能量加权共享核超参数拟合。
% 不把接近DLL求解误差的小能量POD系数标准化后，与主导物理方向
% 等权优化；否则大量小模态会把核长度推到近似记忆训练点的极小值。
X=X./scale;n=size(X,1);distance=sqrt(max(0,sum(X.^2,2)+sum(X.^2,2).'-2*X*X.'));
weight=outputEnergy(:)/sum(outputEnergy);opt=optimset('Display','off', ...
    'MaxIter',150,'MaxFunEvals',300,'TolX',1e-4);
starts=[sqrt(size(X,2)),2,20];best=Inf;
for start=starts
    v=fminsearch(@objective,log([start,.001]),opt);[cost,L]=objective(v);
    if cost<best,best=cost;solution=v;bestL=L;end
end
out=struct('X',X,'inputScale',scale,'length',exp(solution(1)), ...
    'nugget',exp(solution(2)),'alpha',bestL.'\(bestL\Y), ...
    'cost',best,'trainingCount',n,'trainingCriterion','whitened_output_energy_weighted');
    function [cost,L]=objective(v)
        L=[];ell=exp(v(1));noise=exp(v(2));
        if ell<.05||ell>1e4||noise<1e-7||noise>.2,cost=1e100+sum(v.^2);return;end
        r=sqrt(5)*distance/ell;K=(1+r+r.^2/3).*exp(-r)+(noise^2+1e-10)*eye(n);
        [L,flag]=chol(K,'lower');if flag,cost=1e100;return;end
        z=L\Y;cost=.5*sum(z.^2,1)*weight+sum(log(diag(L)));
    end
end
