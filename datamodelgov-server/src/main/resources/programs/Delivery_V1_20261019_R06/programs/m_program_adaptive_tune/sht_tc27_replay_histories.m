function results=sht_tc27_replay_histories(cfg,engine,histories,schedule,options)
%SHT_TC27_REPLAY_HISTORIES 同一候选在每个连续记录块只推进一次热历史。
% preparation只影响状态，返回prediction只包含本片段的拟合样本。
% 支撑包络必须包含前史，否则前史敏感节点会被错误跳过Jacobian。
if nargin<5,options=struct();end
if ~isfield(options,'integrationStep_s'),options.integrationStep_s=.1;end
results=cell(numel(histories),1);
if isempty(histories),return;end
assert(all(isfield(histories,{'replayData','fitIndices','continuousBlock'})), ...
    'TC27:History:MissingPlan','缺少连续热历史计划，请用现行05重新处理测量Excel。');
groups=unique([histories.continuousBlock],'stable');
for group=groups
    members=find([histories.continuousBlock]==group);
    [~,longest]=max(arrayfun(@(h)height(h.replayData),histories(members)));
    raw=histories(members(longest)).replayData;
    for k=members
        h=histories(k);
        assert(isequaln(raw(1:height(h.replayData),:),h.replayData), ...
            'TC27:History:PlanMismatch','同一连续块的准备历程不一致。');
    end
    full=sht_tc27_replay('history',cfg,engine,raw,schedule,options);
    for k=members
        h=histories(k);q=h.fitIndices;out=full;
        assert(isequaln(raw(q,:),h.data),'TC27:History:FitMapping','拟合索引与测量不匹配。');
        for field={'time','prediction','physicalPrediction','states'}
            name=field{1};if isfield(out,name),out.(name)=out.(name)(q,:);end
        end
        out.preparationSampleCount=q(1)-1;
        out.fitSampleCount=numel(q);
        out.continuousBlock=group;
        out.sharedReplay=members(1);
        out.integrationStart_s=raw.Time_s(1);out.integrationEnd_s=raw.Time_s(end);
        out.initializationPolicy='candidate_equilibrium_then_complete_measured_prehistory';
        results{k}=out;
    end
end
end
