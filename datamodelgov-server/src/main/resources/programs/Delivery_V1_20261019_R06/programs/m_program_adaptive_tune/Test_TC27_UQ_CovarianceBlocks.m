function audit=Test_TC27_UQ_CovarianceBlocks(c,model)
%TEST_TC27_UQ_COVARIANCEBLOCKS 白噪声跨独立点/历程协方差应严格为零。
% 公共偏置的相关性位于其他因子，不在此处被删除或误判。
np=height(c.trainingData);P=model.pointNoiseFactor;H=model.historyNoiseFactor;
pointCross=0;
for j=1:np
    rows=j+(0:8)*np;
    for k=j+1:np
        other=k+(0:8)*np;pointCross=max(pointCross,norm(P(rows,:)*P(other,:).','fro'));
    end
end
assert(pointCross==0&&~any(P(9*np+1:end,:),'all'));
assert(~any(H(1:9*np,:),'all'));
offset=9*np;activeColumns=cell(numel(c.histories),1);
for j=1:numel(c.histories)
    count=9*height(c.histories(j).data);rows=offset+(1:count);
    activeColumns{j}=any(H(rows,:)~=0,1);offset=offset+count;
end
for j=1:numel(activeColumns)
    for k=j+1:numel(activeColumns),assert(~any(activeColumns{j}&activeColumns{k}));end
end
assert(all(model.variance>0)&&all(isfinite(model.factor),'all'));
% 取混合行直接构造小协方差，独立验证低秩白化和对数行列式。
indices=unique(round(linspace(1,numel(model.variance),35)));
d=model.variance(indices);F=model.factor(indices,:);B=diag(d);
if isfield(model,'baseBlocks')
    for k=1:numel(model.baseBlocks)
        b=model.baseBlocks(k);[found,rows]=ismember(indices,b.rows);q=find(found);
        if ~isempty(q),L=b.cholLower(rows(q),:);B(q,q)=L*L';end
    end
end
L=chol(B,'lower');A=L\F;
[U,S,~]=svd(A,'econ');s=diag(S);r=sin((1:numel(indices)).');
small=struct('variance',d,'baseBlocks',struct('rows',(1:numel(d))','cholLower',L), ...
    'U',U,'shrink',1-1./sqrt(1+s.^2),'shift',zeros(size(r)));
% 直接公式也先作同一单位变换，避免Pa/rpm/K本身导致的病态误判。
white=sht_tc27_uq_whiten(small,r);R=eye(numel(d))+A*A.';q=L\r;
quadraticError=abs(sum(white.^2)-q.'*(R\q));
assert(quadraticError<1e-7*max(1,sum(white.^2)),'实际协方差白化复验失败。');
audit=struct('passed',true,'pointNoiseCrossCovariance',pointCross, ...
    'independentHistoryBlocks',numel(activeColumns),'whiteningRelativeError', ...
    quadraticError/max(1,sum(white.^2)),'inputNoiseHalfVsFullRelative',model.inputNoiseHalfVsFullRelative);
disp(audit);save(fullfile(c.directory,'covariance_block_audit.mat'),'audit');
end
