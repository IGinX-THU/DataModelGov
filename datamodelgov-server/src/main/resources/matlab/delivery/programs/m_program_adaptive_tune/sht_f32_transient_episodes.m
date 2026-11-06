function result=sht_f32_transient_episodes(data,segmentation,identity,user)
%SHT_F32_TRANSIENT_EPISODES 从可测飞参建立瞬态辨识事件及热历史回放计划。
% 本函数只准备数据，不估计参数，不把气路稳态标签当作金属热平衡证明。
% events是候选清单；windows是无重复的拟合窗口；blocks是必须积分的区间。
% 相隔很远的拟合窗口可能共用一个连续回放块，块内空白仅推进状态。
if nargin<4,user=struct();end
o=local_options(user);
t=data.time_s(:); n=height(data);
assert(n>=3 && height(segmentation.labels)==n,'SHT:F32Episodes:Shape', ...
    '测量与分类的记录数不一致。');
assert(isequal(t,segmentation.labels.time_s(:)) && all(isfinite(t)) && ...
    all(diff(t)>0),'SHT:F32Episodes:Time','测量与分类必须共用严格递增时间轴。');
assert(isfield(identity,'sourceSha256') && ~isempty(identity.sourceSha256) && ...
    isfield(identity,'role') && isfield(identity,'modelMode'), ...
    'SHT:F32Episodes:Identity','缺少测量文件、数据角色或模型身份。');
assert(ismember(identity.role,{'identification','independent_validation'}), ...
    'SHT:F32Episodes:Role','数据角色必须为训练或独立验证。');
dt=median(diff(t));
assert(max(abs(diff(t)-dt))<max(1e-8,dt*1e-6), ...
    'SHT:F32Episodes:Cadence','当前接口要求连续等间隔记录，不能越过缺失时间。');
quality=segmentation.labels.usable;
smoothed=segmentation.diagnostics.smoothed;
names={'Ng','Wf','Mkp'};
limits=[o.minimumNgSpan_rpm,o.minimumWfSpan_kgps,o.minimumMkpSpan_Nm];
certificates=local_certificates(o.thermalEquilibriumCertificates, ...
    identity,n,quality);
source=segmentation.segments;
source=source(source.segment_class=="large_transition",:);
rows=cell(height(source),1);
for j=1:height(source)
    a=source.first(j); b=source.last(j);
    x=smoothed{a:b,names};
    spans=max(x,[],1)-min(x,[],1);
    % 这里只筛选“大幅发动机工况事件”。并不向小幅分类引入最低激励门。
    score=max(spans./limits);
    engineEvent=all(isfinite(x(:))) && score>=1 && ...
        t(b)-t(a)>=o.minimumEventDuration_s-1e-8;
    first=find(t>=t(a)-o.leadIn_s-1e-8,1);
    last=find(t<=t(b)+o.recoveryTail_s+1e-8,1,'last');
    % 不能跨过缺测，截断保护/尾段时明确标注，不默默插值。
    bad=find(~quality(first:a),1,'last');
    if ~isempty(bad),first=first+bad;end
    bad=find(~quality(b:last),1);
    if ~isempty(bad),last=b+bad-2;end
    available=find([certificates.sampleIndex]<=first,1,'last');
    start=1; policy="history_from_record_start";
    evidence="record_start_equilibrium_is_model_assumption"; verified=false;
    if ~isempty(available)
        start=certificates(available).sampleIndex;
        evidence=string(certificates(available).evidenceId); verified=true;
        if first==start
            policy="certified_equilibrium_start";
        else
            policy="history_from_certified_equilibrium";
        end
    end
    historyValid=all(quality(start:last));
    if isempty(available) && ~o.recordStartEquilibriumAssumed
        historyValid=false;
    end
    accepted=engineEvent && historyValid;
    reason="selected_engine_transition";
    if ~engineEvent,reason="environment_dominated_or_engine_span_below_limit";end
    if engineEvent && ~historyValid,reason="initial_history_unavailable";end
    if ~isempty(o.selectedSourceSegmentIds) && ...
            ~ismember(source.segment_id(j),o.selectedSourceSegmentIds)
        accepted=false; reason="user_not_selected";
    end
    edgeCount=max(1,min(b-a+1,round(o.endpointAverage_s/dt)));
    change=mean(x(end-edgeCount+1:end,:),1)-mean(x(1:edgeCount,:),1);
    [~,dominant]=max(abs(change)./limits);
    direction="mixed_or_reversal";
    if abs(change(dominant))/limits(dominant)>=0.25
        if change(dominant)>0,direction="increasing";else,direction="decreasing";end
    end
    leadClipped=(t(a)-t(first)<o.leadIn_s-1e-8);
    tailClipped=(t(last)-t(b)<o.recoveryTail_s-1e-8);
    rows{j}=table(j,source.segment_id(j),a,b,t(a),t(b),t(b)-t(a), ...
        spans(1),spans(2),spans(3),score,direction,engineEvent,accepted,reason, ...
        first,last,t(first),t(last),t(last)-t(first),start,t(start), ...
        policy,evidence,verified,leadClipped,tailClipped, ...
        'VariableNames',{'event_id','source_segment_id','core_first','core_last', ...
        'core_start_s','core_end_s','core_duration_s','Ng_span_rpm','Wf_span_kgps', ...
        'Mkp_span_Nm','engine_span_ratio','direction','engine_event','selected', ...
        'reason','fit_first','fit_last','fit_start_s','fit_end_s','fit_duration_s', ...
        'simulation_first','simulation_start_s','initialization_policy', ...
        'initialization_evidence','equilibrium_certified','lead_clipped','tail_clipped'});
end
events=local_events(rows);
if ~isempty(o.selectedSourceSegmentIds)
    assert(all(ismember(o.selectedSourceSegmentIds,source.segment_id)), ...
        'SHT:F32Episodes:Selection','指定的事件编号不属于本文件的大过渡段。');
end
fit=false(n,1); blocks=zeros(0,2);
for j=find(events.selected)'
    fit(events.fit_first(j):events.fit_last(j))=true;
    blocks(end+1,:)=[events.simulation_first(j),events.fit_last(j)]; %#ok<AGROW>
end
% 相同时间记录只计一次。回放区间交叠时连续推进，不能重复加权或重置热状态。
blocks=local_merge_blocks(blocks);
windows=local_windows(fit,t);
simulation=false(n,1); blockId=zeros(n,1);
for j=1:size(blocks,1)
    simulation(blocks(j,1):blocks(j,2))=true;
    blockId(blocks(j,1):blocks(j,2))=j;
end
blockTable=table((1:size(blocks,1))',blocks(:,1),blocks(:,2), ...
    t(blocks(:,1)),t(blocks(:,2)),t(blocks(:,2))-t(blocks(:,1)), ...
    blocks(:,2)-blocks(:,1)+1,'VariableNames', ...
    {'block_id','first','last','start_s','end_s','duration_s','sample_count'});
blockTable.initialization_policy=strings(height(blockTable),1);
blockTable.initialization_evidence=strings(height(blockTable),1);
blockTable.equilibrium_certified=false(height(blockTable),1);
for j=1:height(blockTable)
    k=find(events.selected & events.simulation_first==blockTable.first(j),1);
    blockTable.initialization_policy(j)=events.initialization_policy(k);
    blockTable.initialization_evidence(j)=events.initialization_evidence(k);
    blockTable.equilibrium_certified(j)=events.equilibrium_certified(k);
end
windowId=zeros(n,1);
for j=1:height(windows),windowId(windows.first(j):windows.last(j))=j;end
summary=struct('candidateCount',height(events),'selectedCount',nnz(events.selected), ...
    'fitWindowCount',height(windows),'simulationBlockCount',height(blockTable), ...
    'fitSampleCount',nnz(fit),'simulationSampleCount',nnz(simulation), ...
    'fitDuration_s',sum(windows.duration_s), ...
    'simulationDuration_s',sum(blockTable.duration_s),'fullDuration_s',t(end)-t(1), ...
    'simulationFraction',sum(blockTable.duration_s)/(t(end)-t(1)), ...
    'certifiedSelectedCount',nnz(events.selected & events.equilibrium_certified), ...
    'historyAssumptionSelectedCount',nnz(events.selected & ~events.equilibrium_certified));
result=struct('schemaVersion','SHT_F32_TRANSIENT_EPISODES_V1','identity',identity, ...
    'options',o,'events',events,'windows',windows,'blocks',blockTable, ...
    'samplePlan',table(data.sample_id,t,fit,simulation,windowId,blockId, ...
        'VariableNames',{'sample_id','time_s','use_for_fit','requires_simulation', ...
        'fit_window_id','simulation_block_id'}),'summary',summary);
result.status='DATA_PREPARATION_ONLY_NOT_IDENTIFICATION';
result.integrationStep_s=o.integrationStep_s; result.recordStep_s=dt;
result.initialStateNuisanceImplemented=false;
result.fullHistoryIdentificationEnabled=false;
result.inverseSensorCompensation=false;
assert(all(~fit|simulation) && all(quality(fit)), ...
    'SHT:F32Episodes:Coverage','拟合窗口必须由有效的连续回放覆盖。');
end

function o=local_options(u)
o=struct('minimumNgSpan_rpm',2000,'minimumWfSpan_kgps',0.03, ...
    'minimumMkpSpan_Nm',200,'minimumEventDuration_s',5,'leadIn_s',20, ...
    'recoveryTail_s',60,'endpointAverage_s',2,'integrationStep_s',0.1, ...
    'recordStartEquilibriumAssumed',true,'selectedSourceSegmentIds',strings(0,1), ...
    'thermalEquilibriumCertificates',struct('sampleIndex',{}, ...
        'sourceSha256',{},'evidenceId',{}));
keys=fieldnames(u);
for j=1:numel(keys)
    assert(isfield(o,keys{j}),'SHT:F32Episodes:Option','未知片段选项：%s。',keys{j});
    o.(keys{j})=u.(keys{j});
end
assert(isnumeric(o.integrationStep_s)&&isscalar(o.integrationStep_s)&& ...
    ismember(o.integrationStep_s,[.025,.1]),'SHT:F32Episodes:Option','积分步长只允许0.025或0.1秒。');
for name={'minimumNgSpan_rpm','minimumWfSpan_kgps','minimumMkpSpan_Nm', ...
        'minimumEventDuration_s','endpointAverage_s'}
    v=o.(name{1});
    assert(isnumeric(v)&&isscalar(v)&&isfinite(v)&&v>0, ...
        'SHT:F32Episodes:Option','%s必须为有限正数。',name{1});
end
for name={'leadIn_s','recoveryTail_s'}
    v=o.(name{1});
    assert(isnumeric(v)&&isscalar(v)&&isfinite(v)&&v>=0, ...
        'SHT:F32Episodes:Option','%s必须为有限非负数。',name{1});
end
v=o.recordStartEquilibriumAssumed;
assert(islogical(v)&&isscalar(v),'SHT:F32Episodes:Option','起点热平衡假设必须为逻辑标量。');
v=string(o.selectedSourceSegmentIds(:));
assert(all(strlength(v)>0)&&~any(ismissing(v))&&numel(unique(v))==numel(v), ...
    'SHT:F32Episodes:Option','事件编号必须为不重复的原始片段字符串编号。');
o.selectedSourceSegmentIds=v;
end

function c=local_certificates(c,identity,n,quality)
assert(isstruct(c),'SHT:F32Episodes:Certificate','热平衡依据必须用结构体清单显式传入。');
for j=1:numel(c)
    assert(all(isfield(c,{'sampleIndex','sourceSha256','evidenceId'})), ...
        'SHT:F32Episodes:Certificate','热平衡依据字段不完整。');
    k=c(j).sampleIndex;
    assert(isnumeric(k)&&isscalar(k)&&isfinite(k)&&k==round(k)&&k>=1&&k<=n, ...
        'SHT:F32Episodes:Certificate','热平衡起点索引不合法。');
    assert(strcmp(c(j).sourceSha256,identity.sourceSha256) && ...
        strlength(string(c(j).evidenceId))>0 && quality(k), ...
        'SHT:F32Episodes:Certificate','热平衡依据必须对应当前测量文件且有独立证据标识。');
end
if ~isempty(c)
    [~,order]=sort([c.sampleIndex]);c=c(order);
    assert(numel(unique([c.sampleIndex]))==numel(c), ...
        'SHT:F32Episodes:Certificate','热平衡起点不可重复。');
end
end

function e=local_events(rows)
if ~isempty(rows),e=vertcat(rows{:});return;end
% 空事件也保留稳定列类型，以便Excel和真实无事件数据使用同一接口。
names={'event_id','source_segment_id','core_first','core_last','core_start_s', ...
    'core_end_s','core_duration_s','Ng_span_rpm','Wf_span_kgps','Mkp_span_Nm', ...
    'engine_span_ratio','direction','engine_event','selected','reason','fit_first', ...
    'fit_last','fit_start_s','fit_end_s','fit_duration_s','simulation_first', ...
    'simulation_start_s','initialization_policy','initialization_evidence', ...
    'equilibrium_certified','lead_clipped','tail_clipped'};
e=array2table(zeros(0,numel(names)),'VariableNames',names);
for name={'source_segment_id','direction','reason','initialization_policy','initialization_evidence'}
    e.(name{1})=strings(0,1);
end
for name={'engine_event','selected','equilibrium_certified','lead_clipped','tail_clipped'}
    e.(name{1})=false(0,1);
end
end

function b=local_merge_blocks(b)
if isempty(b),return;end
b=sortrows(b,1);out=b(1,:);
for j=2:size(b,1)
    if b(j,1)<=out(end,2)
        out(end,2)=max(out(end,2),b(j,2));
    else
        out(end+1,:)=b(j,:); %#ok<AGROW>
    end
end
b=out;
end

function w=local_windows(mask,t)
first=find(diff([false;mask])==1);last=find(diff([mask;false])==-1);
w=table((1:numel(first))',first,last,t(first),t(last),t(last)-t(first), ...
    last-first+1,'VariableNames', ...
    {'window_id','first','last','start_s','end_s','duration_s','sample_count'});
end
