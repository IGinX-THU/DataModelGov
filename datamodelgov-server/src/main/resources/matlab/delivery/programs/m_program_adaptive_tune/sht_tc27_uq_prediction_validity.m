function q=sht_tc27_uq_prediction_validity(q,names)
%SHT_TC27_UQ_PREDICTION_VALIDITY 求解器有效标记优先于数值是否有限。
% 未收敛点可能仍有有限的最后迭代值，不能把它们计入预测区间。
% 原始状态和求解诊断仍保留，只有用于统计的输出行置为NaN。
n=height(q.prediction);valid=q.valid(:);
if isscalar(valid),valid=repmat(valid,n,1);end
assert(numel(valid)==n,'TC27:UQ:ValiditySize','预测有效标记与输出行数不一致。');
valid=valid&all(isfinite(q.prediction{:,names}),2);
q.prediction{~valid,names}=NaN;
q.valid=valid;
if ~isfield(q,'messages'),q.messages=strings(n,1);end
if isscalar(q.messages)&&n>1,q.messages=repmat(string(q.messages),n,1);end
assert(numel(q.messages)==n,'TC27:UQ:MessageSize','预测原因记录与输出行数不一致。');
q.messages=string(q.messages(:));
q.messages(~valid&strlength(q.messages)==0)="physical_validity_failed";
end
