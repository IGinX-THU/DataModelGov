function out=sht_tc27_uq_exact_correction(theta,proxyResidual,evaluate,whiten,allowPilot)
%SHT_TC27_UQ_EXACT_CORRECTION 分批精确校正，严重退化的先导批仅用于加密。
% 最终轮必须完成全部预定样本。先导批按权重ESS提前停止不是后验
% 验收；complete=false的样本绝不能选择为最终交付分布。
count=size(theta,2);assert(size(proxyResidual,2)==count&&count>0);
residual=[];valid=false(1,count);logRatio=-inf(1,count);early=false;
for first=1:64:count
    selected=first:min(first+63,count);q=evaluate(theta(:,selected));
    if isempty(residual),residual=nan(size(q.residual,1),count);end
    residual(:,selected)=q.residual;valid(selected)=q.valid;
    white=whiten(q.residual);
    logRatio(selected)=-.5*(sum(white.^2,1)-sum(proxyResidual(:,selected).^2,1));
    logRatio(~valid)=-Inf;completed=selected(end);
    current=logRatio(1:completed);
    if any(isfinite(current)),w=exp(current-max(current));w=w/sum(w);ess=1/sum(w.^2);else,ess=0;end
    fprintf('TC27-C精确校正批：%d/%d，当前权重ESS=%.2f。\n',completed,count,ess);
    if allowPilot&&completed<count&&completed>=64&&ess<max(4,.05*completed)
        early=true;break;
    end
end
residual=residual(:,1:completed);valid=valid(1:completed);logRatio=logRatio(1:completed);
assert(any(isfinite(logRatio)),'TC27:UQ:CorrectionInvalid','精确校正没有有效点。');
w=exp(logRatio-max(logRatio));w=w/sum(w);
out=struct('theta',theta(:,1:completed),'residual',residual,'valid',valid, ...
    'logRatio',logRatio,'weights',w,'effectiveSampleSize',1/sum(w.^2), ...
    'complete',~early,'plannedCount',count,'completedCount',completed);
end
