function histories=sht_tc27_transient_plan(record,scope)
%SHT_TC27_TRANSIENT_PLAN 事件按独立连续拟合窗口回放，重叠窗口只计一次。
% 前平台和恢复段已经包含在eventFitMask中。不同事件之间的空白不能
% 合成一条扰动回放；每段的真实准备输入随后由local_history_plan截取。
assert(ismember(scope,{'full_history','event_windows'}),'TC27:Transient:Scope','数据范围无效。');
d=record.diagnostic;fit=d.qualityMask;
if strcmp(scope,'event_windows'),fit=fit&d.eventFitMask;end
assert(any(fit),'TC27:Transient:NoEvents','没有可用拟合样本；可显式选择full_history。');
histories=struct('id',{},'data',{},'replayData',{},'fitIndices',{},'continuousBlock',{});
for group=unique(d.continuousBlock(fit)).'
    q=find(fit&d.continuousBlock==group);start=d.blockStarts(group);
    if strcmp(scope,'event_windows')
        first=[1;find(diff(q)>1)+1];last=[first(2:end)-1;numel(q)];
    else
        first=1;last=numel(q);
    end
    for k=1:numel(first)
        rows=q(first(k):last(k));
        name=sprintf('%s-B%02d',scope,group);
        if strcmp(scope,'event_windows'),name=sprintf('%s-E%02d',name,k);end
        histories(end+1)=struct('id',name, ...
            'data',record.data(rows,:),'replayData',record.data(start:rows(end),:), ...
            'fitIndices',rows-start+1,'continuousBlock',group); %#ok<AGROW>
    end
end
end
