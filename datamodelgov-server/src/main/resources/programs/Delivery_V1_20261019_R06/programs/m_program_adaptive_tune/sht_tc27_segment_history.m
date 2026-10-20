function r=sht_tc27_segment_history(t,o,kind)
%SHT_TC27_SEGMENT_HISTORY 先稳态、后小幅，并保存事件及连续候选热历史。
% 阈值噪声只用于分类；拟合仍读取原始测量，不用于改写似然方差。
d=struct('minimumSteadyDuration_s',10,'minimumSmallDuration_s',10, ...
    'steadyGuard_s',1,'initializationExclusion_s',5,'screeningLevel','S3', ...
    'exceedanceGap_s',.3,'smallAmplitudeLimit',.20, ...
    'eventLeadIn_s',10,'eventRecovery_s',30,'eventGap_s',1);
f=fieldnames(d);for j=1:numel(f),if ~isfield(o,f{j}),o.(f{j})=d.(f{j});end,end
assert(ismember(o.minimumSteadyDuration_s,[5,10,15,20])&& ...
    ismember(o.minimumSmallDuration_s,[5,10,15,20]),'TC27:Segment:Duration','时长挡位无效。');
required={'Time_s','Np','Ng','Wf','Mkp','Pt1','Tt1','Ptb3','Ttb3','Pt45','Tt45','Pt6','Tt6','Wa1','Wb','Pamb','Tamb','Altitude','Mach','RH'};
assert(all(ismember(required,t.Properties.VariableNames)),'TC27:Segment:Columns','缺少测量列。');
time=t.Time_s;n=height(t);dt=median(diff(time));
assert(n>2&&all(isfinite(time))&&all(diff(time)>0)&&dt>0,'TC27:Segment:Time','时间轴无效。');
quality=all(isfinite(t{:,required}),2)&t.Np>10000&t.Np<25000& ...
    t.Ng>15000&t.Ng<45000&t.Wf>0&t.Mkp>0&t.Tt45<1800;
% 缺测和时间跳跃均切断回放块，不能靠插值或连接短间隙越过。
breakBefore=[true;abs(diff(time)-dt)>max(1e-7,dt*1e-5)];
block=zeros(n,1);starts=[];ends=[];id=0;
for i=1:n
    if ~quality(i),continue;end
    if i==1||~quality(max(1,i-1))||breakBefore(i)
        id=id+1;starts(id)=i;ends(id)=i; %#ok<AGROW>
    end
    block(i)=id;ends(id)=i;
end
names={'Np','Ng','Wf','Mkp','Ttb3','Tt45'};span=[5000,10000,.15,1000];
smooth=nan(n,6);rate=smooth;localSpan=nan(n,4);large=false(n,1);
for j=1:id
    q=(starts(j):ends(j)).';x=movmean(t{q,names},2*round(1/dt)+1,1);smooth(q,:)=x;
    lag=max(1,round(1/dt));
    for k=1:numel(q)
        a=max(1,k-lag);b=min(numel(q),k+lag);
        rate(q(k),:)=(x(b,:)-x(a,:))/max(dt,time(q(b))-time(q(a)));
    end
    w=2*round(2.5/dt)+1;
    localSpan(q,:)=movmax(x(:,1:4),w,1)-movmin(x(:,1:4),w,1);
    large(q)=any(localSpan(q,:)./[500,1000,.015,100]>1,2);
end
normalized=max(abs(rate(:,1:4))./span,[],2);
activity=max(abs(rate(:,1:4))./span,[],2);z=sort(activity(quality));
assert(~isempty(z),'TC27:Segment:Quality','没有有效测量记录。');
quiet=quality&activity<=z(max(1,round(.2*numel(z))));sigma=zeros(1,6);
for j=1:6,z=rate(quiet,j);sigma(j)=1.4826*median(abs(z-median(z)));end
switch upper(o.screeningLevel)
    case 'S2',limits=[.0025,.20,.25];
    case 'S3',limits=[.004,.32,.40];
    case 'S4',limits=[.006,.48,.60];
    case 'S5',limits=[.009,.72,.90];
    otherwise,error('TC27:Segment:Level','等级为S2/S3/S4/S5。');
end
limits=max(limits,[3*max(sigma(1:4)./span),3*sigma(5:6)]);
valid=quality;
for j=1:id,valid(starts(j):ends(j))=time(starts(j):ends(j))-time(starts(j))>=o.initializationExclusion_s;end
steady=valid&~large&normalized<=limits(1)&abs(rate(:,5))<=limits(2)&abs(rate(:,6))<=limits(3);
steady=join_gaps(steady,valid&~large,block,dt,o.exceedanceGap_s);
labels=repmat("other",n,1);labels(~quality)="invalid";
means=table();windows=table();steadyMask=false(n,1);guard=round(o.steadyGuard_s/dt);
rr=runs(steady,block);
for j=1:size(rr,1)
    a=rr(j,1)+guard;b=rr(j,2)-guard;
    if a>b||time(b)-time(a)<o.minimumSteadyDuration_s-1e-8,continue;end
    pid=string(sprintf('%s-W%02d',kind,height(windows)+1));
    row=table(pid,b-a+1,'VariableNames',{'point_id','sample_count'});
    for k=2:numel(required),row.([required{k},'_mean'])=mean(t.(required{k})(a:b));end
    row.Mkg_mean=0;means=[means;row]; %#ok<AGROW>
    windows=[windows;table(pid,time(a),time(b),time(b)-time(a),b-a+1, ...
        'VariableNames',{'point_id','start_s','end_s','duration_s','sample_count'})]; %#ok<AGROW>
    steadyMask(a:b)=true;labels(a:b)="steady";
end
% 剩余连续有效记录只检查幅度上限，不要求最低激励或最低变化率。
smallMask=false(n,1);small=struct('id',{},'data',{},'first',{},'last',{}, ...
    'duration_s',{},'replayData',{},'fitIndices',{},'continuousBlock',{},'initializationPolicy',{});
rr=runs(valid&~steadyMask&~large,block);
for j=1:size(rr,1)
    a=rr(j,1);b=rr(j,2);
    amplitude=max((max(smooth(a:b,1:4),[],1)-min(smooth(a:b,1:4),[],1))./span);
    if time(b)-time(a)<o.minimumSmallDuration_s-1e-8||amplitude>o.smallAmplitudeLimit,continue;end
    start=starts(block(a));
    small(end+1)=struct('id',sprintf('%s-H%02d',kind,numel(small)+1), ...
        'data',t(a:b,:),'first',a,'last',b,'duration_s',time(b)-time(a), ...
        'replayData',t(start:b,:),'fitIndices',(a:b).'-start+1, ...
        'continuousBlock',block(a),'initializationPolicy','candidate_equilibrium_at_continuous_record_start'); %#ok<AGROW>
    smallMask(a:b)=true;labels(a:b)="small_change";
end
% 大幅事件沿用TC27发动机变化尺度，前平台/恢复长度是可配置工程窗口。
eventCore=join_gaps(large&valid,valid,block,dt,o.eventGap_s);
rr=runs(eventCore,block);events=table();eventFit=false(n,1);
for j=1:size(rr,1)
    a=rr(j,1);b=rr(j,2);q=block(a);first=max(starts(q),a-round(o.eventLeadIn_s/dt));
    last=min(ends(q),b+round(o.eventRecovery_s/dt));
    change=smooth(b,1:4)-smooth(a,1:4);[~,dominant]=max(abs(change)./span);
    direction="increase";if change(dominant)<0,direction="decrease";end
    eid=string(sprintf('%s-E%02d',kind,j));
    events=[events;table(eid,a,b,first,last,starts(q),time(a),time(b),time(first),time(last), ...
        string(names{dominant}),direction,first==starts(q),last==ends(q), ...
        'VariableNames',{'event_id','core_first','core_last','fit_first','fit_last','integration_first', ...
        'core_start_s','core_end_s','fit_start_s','fit_end_s','dominant_channel','direction','lead_truncated','tail_truncated'})]; %#ok<AGROW>
    eventFit(first:last)=true;
end
diagnostic=struct('sampleTime_s',dt,'effectiveLimits',limits,'rateNoiseSigma',sigma, ...
    'fullWindowRetained',true,'maximumDuration_s',Inf,'largeChangeMask',large, ...
    'qualityMask',quality,'continuousBlock',block,'blockStarts',starts,'blockEnds',ends, ...
    'eventFitMask',eventFit,'eventCoreMask',eventCore,'smallFitMask',smallMask, ...
    'classificationPolicy','steady_first_no_minimum_small_excitation','options',o);
r=struct('data',t,'means',means,'windows',windows,'small',small, ...
    'labels',labels,'diagnostic',diagnostic,'events',events);
end
function rr=runs(mask,block)
mask=mask(:);a=find(mask&[true;~mask(1:end-1)|diff(block)~=0]);
b=find(mask&[~mask(2:end)|diff(block)~=0;true]);rr=[a,b];
end
function mask=join_gaps(mask,allowed,block,dt,maximum)
rr=runs(~mask&allowed,block);
for j=1:size(rr,1)
    a=rr(j,1);b=rr(j,2);
    if a>1&&b<numel(mask)&&mask(a-1)&&mask(b+1)&& ...
            block(a-1)==block(b+1)&&(b-a+1)*dt<=maximum+1e-8
        mask(a:b)=true;
    end
end
end
