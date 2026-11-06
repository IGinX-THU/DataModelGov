function [histories,plan]=sht_tc27_local_history_plan(histories,warmup_s)
%SHT_TC27_LOCAL_HISTORY_PLAN 按第3阶段框架建立有限真实输入准备段。
% 只改变积分前史，不改筛选窗口、拟合样本或原数据。每段独立初始化。
validateattributes(warmup_s,{'numeric'},{'scalar','real','finite','nonnegative'});
plan=table();
for k=1:numel(histories)
    h=histories(k);raw=h.replayData;a=h.data.Time_s(1);b=h.data.Time_s(end);
    first=find(raw.Time_s>=a-warmup_s-1e-8,1);last=find(raw.Time_s<=b+1e-8,1,'last');
    local=raw(first:last,:);fit=h.fitIndices-first+1;
    assert(isequaln(local(fit,:),h.data),'TC27:LocalPlan:Fit','局部准备不得改变拟合记录。');
    histories(k).replayData=local;histories(k).fitIndices=fit;
    histories(k).continuousBlock=k;
    histories(k).initializationPolicy='candidate_equilibrium_then_local_measured_warmup';
    plan=[plan;table(string(h.id),local.Time_s(1),a,b,a-local.Time_s(1), ...
        height(h.data),numel(fit),height(local), ...
        'VariableNames',{'segment','initializationStart_s','fitStart_s','fitEnd_s', ...
        'actualWarmup_s','originalFitSamples','fitSamples','integrationSamples'})]; %#ok<AGROW>
end
end
