function out=sht_tc27_uq_move_reference(action,varargin)
%SHT_TC27_UQ_MOVE_REFERENCE 粒子学习的移动参考分布，不是贝叶斯先验。
% 每个温度层仅构造一次并冻结。高斯只描述候选移动，完整非线性目标
% 仍由MH接受率校正，不假定后验为高斯或单峰。无统计工具箱依赖。
switch lower(action)
    case 'build'
        z=varargin{1};w=varargin{2}(:);beta=varargin{3};o=varargin{4};
        assert(all(isfinite(z(:)))&&all(w>=0)&&sum(w)>0);
        w=w/sum(w);d=size(z,1);mu=z*w;
        % 在参考Jacobian给出的尺度下收缩协方差，避免重复祖先使弱方向
        % 被误判为零方差。参考尺度不进入先验或似然。
        s=o.globalSingularValues(:);if isempty(s),s=zeros(d,1);end
        L0=o.globalBasis*diag(1./sqrt(1+beta*s.^2));
        q=L0\(z-mu);denominator=1-sum(w.^2);
        if denominator>1e-12
            empirical=(q.*w.')*q.'/denominator;
        else
            empirical=zeros(d);
        end
        weightESS=1/sum(w.^2);
        shrinkage=max(o.referenceShrinkage,d/(d+weightESS));
        scaled=(1-shrinkage)*empirical+shrinkage*eye(d);
        [V,E]=eig((scaled+scaled.')/2);
        eigenvalue=max(o.referenceEigenvalueFloor,real(diag(E)));
        C=L0*(V*diag(eigenvalue)*V.')*L0.';C=(C+C.')/2;
        L=chol(C,'lower');precision=L.'\(L\eye(d));
        blocks=o.blockIndex;conditional=cell(4,1);
        for k=1:4
            b=blocks{k}(:);r=setdiff((1:d).',b);
            P=precision(b,b);P=(P+P.')/2;
            variance=P\eye(numel(b));variance=(variance+variance.')/2;
            conditional{k}=struct('index',b,'other',r,'gain',P\precision(b,r), ...
                'cholLower',chol(variance,'lower'));
        end
        out=struct('mean',mu,'cholLower',L,'conditional',{conditional}, ...
            'covariance',C,'shrinkage',shrinkage,'weightESS',weightESS, ...
            'relativeMinimumEigenvalue',min(eigenvalue), ...
            'relativeMaximumEigenvalue',max(eigenvalue));
    case 'propose'
        ref=varargin{1};z=varargin{2};kernel=varargin{3};rho=varargin{4};
        assert(isscalar(rho)&&rho>0&&rho<=1);
        if kernel==5
            out=ref.mean+sqrt(1-rho^2)*(z-ref.mean)+rho*ref.cholLower*randn(size(z));
        else
            c=ref.conditional{kernel};b=c.index;
            center=ref.mean(b)-c.gain*(z(c.other,:)-ref.mean(c.other));
            out=z;
            out(b,:)=center+sqrt(1-rho^2)*(z(b,:)-center)+ ...
                rho*c.cholLower*randn(numel(b),size(z,2));
        end
    case 'logdensity'
        ref=varargin{1};q=ref.cholLower\(varargin{2}-ref.mean);
        % 只用于同一个冻结参考的密度比，归一化常数严格抵消。
        out=-.5*sum(q.^2,1);
    otherwise
        error('TC27:UQ:MoveReferenceAction','未知移动参考操作%s。',action);
end
end
