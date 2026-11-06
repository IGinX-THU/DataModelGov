function result = sht_f32_segment_history(data, userOptions)
%SHT_F32_SEGMENT_HISTORY 从无标签飞参中识别稳态和不同动态片段。
%
% 分段只使用可测数据。原始测量值不被覆盖；零相位移动平均副本仅用于
% 变化率、幅度上限和片段标签计算。这样既避免传感器逆动态造成噪声放大，
% 又保证后续辨识仍可读取未经“修饰”的观测时间历程。

if nargin < 2 || isempty(userOptions), userOptions = struct(); end
options = local_options(userOptions);
if ~ismember('Mkg',data.Properties.VariableNames),data.Mkg=zeros(height(data),1);end
required = {'sample_id','time_s','Ps0','Tt1','Pt3_eq','Ng','Np', ...
    'Mkp','Wf','Tt45','Altitude','Mach','Ts_amb'};
missing = required(~ismember(required,data.Properties.VariableNames));
if ~isempty(missing)
    error('SHT:F32Segment:MissingColumn', ...
        '飞参Excel缺少字段：%s。',strjoin(missing,', '));
end

time = data.time_s(:);
n = height(data);
if n < 3 || any(~isfinite(time)) || any(diff(time) <= 0)
    error('SHT:F32Segment:Time','时间轴必须有限且严格递增。');
end
dt = median(diff(time));
if max(abs(diff(time)-dt)) > max(1e-10,options.sampleTimeTolerance*dt)
    error('SHT:F32Segment:SampleTime','当前版本要求等间隔采样。');
end

% 只使用正式飞参合同内的可测量量。Pt3_eq 是压气机出口等效总压观测，
% 仅参与工况活动和稳态判别，绝不被用作发动机入口边界。
signalNames = {'Np','Ng','Wf','Mkp','Altitude','Mach','Pt3_eq','Tt45', ...
    'Ps0','Tt1','Ts_amb'};
raw = zeros(n,numel(signalNames));
for i = 1:numel(signalNames)
    raw(:,i) = data.(signalNames{i})(:);
end
smoothCount = max(3,2*floor(round(options.smoothingDuration_s/dt)/2)+1);
smoothed = movmean(raw,smoothCount,1,'Endpoints','shrink');
rate = local_centered_rate(smoothed,time,options.rateSpan_s);

operatingScale = [5000,10000,0.15,1000];
externalScale = [0.15,1000,1000,0.20];
normalizedOperatingRate = max(abs(rate(:,1:4))./operatingScale,[],2);
normalizedExternalRate = max(abs(rate(:,[3,4,5,6]))./externalScale,[],2);

% 低活动样本用于估计微分噪声下限；它只修正门限，不改变测量数据。
quietCutoff = local_quantile(normalizedExternalRate,0.25);
quiet = normalizedExternalRate <= quietCutoff;
if nnz(quiet) < 20, quiet = true(n,1); end
normalizedRateNoise = max(arrayfun( ...
    @(j)local_robust_sigma(rate(quiet,j)/operatingScale(j)),1:4));
pt3EqRateNoise = local_robust_sigma(rate(quiet,7));
tt45RateNoise = local_robust_sigma(rate(quiet,8));
effectiveOperatingLimit = max(options.steadyNormalizedRateLimit_per_s, ...
    options.rateNoiseFloorMultiplier*normalizedRateNoise);
effectivePt3EqLimit = max(options.steadyPt3EqRateLimit_Paps, ...
    options.rateNoiseFloorMultiplier*pt3EqRateNoise);
effectiveTt45Limit = max(options.steadyTt45RateLimit_Kps, ...
    options.rateNoiseFloorMultiplier*tt45RateNoise);
% 环境噪声由发动机低活动区间估计，不能先按Mach低变化筛选，再估计
% Mach本身的噪声，否则会人为截小噪声下限。所有输入均为可测量数据。
environmentQuiet = normalizedOperatingRate <= ...
    local_quantile(normalizedOperatingRate,0.25);
if nnz(environmentQuiet)<20,environmentQuiet=true(n,1);end
altitudeRateNoise = local_robust_sigma(rate(environmentQuiet,5));
machRateNoise = local_robust_sigma(rate(environmentQuiet,6));
effectiveAltitudeLimit = max(options.steadyAltitudeRateLimit_mps, ...
    options.rateNoiseFloorMultiplier*altitudeRateNoise);
effectiveMachLimit = max(options.steadyMachRateLimit_per_s, ...
    options.rateNoiseFloorMultiplier*machRateNoise);

numeric = data{:,required(2:end)};
quality = all(isfinite(numeric),2) & ...
    data.Np>5000 & data.Np<30000 & data.Ng>10000 & data.Ng<60000 & ...
    data.Wf>0.002 & data.Wf<0.35 & data.Mkp>-100 & data.Mkp<2500 & ...
    abs(data.Mkg)<200 & data.Tt1>180 & data.Tt1<450 & ...
    data.Tt45>250 & data.Tt45<1900 & data.Ps0>10000 & data.Ps0<150000 & ...
    data.Pt3_eq>10000 & data.Pt3_eq<4e6 & ...
    data.Ts_amb>150 & data.Ts_amb<400 & ...
    data.Altitude>-1000 & data.Altitude<15000 & ...
    data.Mach>=0 & data.Mach<1.2;

initialization = time < time(1)+options.initializationExclusion_s;
steadyCandidate = quality & ~initialization & ...
    normalizedOperatingRate<=effectiveOperatingLimit & ...
    abs(rate(:,7))<=effectivePt3EqLimit & ...
    abs(rate(:,8))<=effectiveTt45Limit & ...
    abs(rate(:,5))<=effectiveAltitudeLimit & ...
    abs(rate(:,6))<=effectiveMachLimit;

% 第一层独立完成稳态确认。仅连接不超过0.5秒的短暂越限，不能跨越
% 无效/初始化记录；测量数据原样保留，不删除或插值这些记录。
steadyRawCandidate=steadyCandidate;
steadyCandidate=local_bounded_morphology(steadyCandidate,quality & ~initialization, ...
    round(options.steadyBridgeGap_s/dt),0);
steadyMask=local_trim_steady(steadyCandidate,time,dt,options);

% 第二层接纳全部剩余有效连续数据，不要求输入激励或变化率下限。
% 保留原有变化率的局部边界线索，但高/低变化率两侧全部进入相同筛选。
remaining=quality & ~initialization & ~steadyMask;
% 原始无效点可使其邻域平滑值为NaN；这不是幅度为零，不能误判合格。
spanEligible=remaining & all(isfinite(smoothed(:,1:6)),2);
remainingRuns = local_runs(spanEligible,time);
boundarySeed=spanEligible & (normalizedExternalRate>options.secondaryBoundaryRate_per_s | ...
    normalizedOperatingRate>options.secondaryBoundaryRate_per_s);
boundaryPhase=local_bounded_morphology(boundarySeed,spanEligible, ...
    round(options.secondaryBoundaryBridge_s/dt),round(options.secondaryBoundaryExpansion_s/dt));
baseSpanLimits=[5000,10000,0.15,1000,1000,0.20] * ...
    options.smallChangeMaximumAmplitude;
% 温压幅度保留诊断，但R016新增硬上限缺少验证依据，不再用于否决。
diagnosticSpanReferences=[baseSpanLimits,30000,20,2000,6,6];
baseSpanLimits=[baseSpanLimits,Inf(1,5)];
% 平滑副本用于判幅；原始值减平滑值的MAD提供保守噪声下限。
% 该估计只用于分段，不能作为后续辨识或UQ的测量协方差。
amplitudeNoise=zeros(1,numel(signalNames));
for j=1:numel(signalNames)
    amplitudeNoise(j)=local_robust_sigma(raw(quality,j)-smoothed(quality,j));
end
spanLimits=max(baseSpanLimits,options.amplitudeNoiseFloorMultiplier*amplitudeNoise);

selectionReason=repmat("unclassified",n,1);
selectionReason(~quality)="invalid_measurement";
selectionReason(initialization & quality)="initialization_exclusion";
selectionReason(steadyMask)="steady_confirmed";
[smallMask,largeMask,breakBefore,secondaryReason]=local_extract_small( ...
    remainingRuns,boundaryPhase,smoothed(:,1:6),time,spanLimits(1:6),options);
selectionReason(remaining & ~spanEligible)="invalid_smoothed_context";
selectionReason(spanEligible)=secondaryReason(spanEligible);

% 热恢复仅作附加提示，不再成为排除小幅片段的互斥分类。
thermalHint = remaining & ...
    normalizedExternalRate<=effectiveOperatingLimit & ...
    abs(rate(:,8))>effectiveTt45Limit;
thermalHint = local_keep_long(thermalHint, ...
    max(1,round(options.thermalMinimumDuration_s/dt)));

sampleClass = repmat("other",n,1);
sampleClass(~quality) = "invalid";
sampleClass(initialization & quality) = "initialization";
sampleClass(largeMask & quality & ~initialization) = "large_transition";
sampleClass(smallMask & quality & ~initialization) = "small_change";
sampleClass(steadyMask & quality & ~initialization) = "steady_window";
% 相邻小幅区间可能处于不同局部工况，不能因标签相同就跨幅度边界合并。
[segmentId,segmentTable] = local_segment_table(sampleClass,time,quality,breakBefore);
secondaryRuns=segmentTable(ismember(segmentTable.segment_class, ...
    ["small_change","large_transition","other"]), ...
    {'first','last','start_s','end_s','duration_s','segment_class'});
secondaryRuns.maximum_span_ratio=zeros(height(secondaryRuns),1);
secondaryRuns.limiting_channel=strings(height(secondaryRuns),1);
secondaryRuns.reason=strings(height(secondaryRuns),1);
secondarySpans=zeros(height(secondaryRuns),numel(signalNames));
for i=1:height(secondaryRuns)
    index=secondaryRuns.first(i):secondaryRuns.last(i);
    span=max(smoothed(index,:),[],1)-min(smoothed(index,:),[],1);
    [ratio,limiting]=max(span./spanLimits);
    secondaryRuns.maximum_span_ratio(i)=ratio;
    secondaryRuns.limiting_channel(i)=string(signalNames{limiting});
    secondaryRuns.reason(i)=selectionReason(index(1));
    secondarySpans(i,:)=span;
    if secondaryRuns.segment_class(i)=="small_change"
        assert(ratio<=1+1e-12 && secondaryRuns.duration_s(i)>= ...
            options.smallChangeMinimumDuration_s-1e-9,'SHT:F32Segment:SmallContract', ...
            '发布小幅区间的幅度或持续时间不符合合同。');
    end
end
labels = table(data.sample_id(:),time,segmentId,sampleClass,quality, ...
    sampleClass=="steady_window",sampleClass=="small_change", ...
    sampleClass=="large_transition",sampleClass=="thermal_recovery", ...
    'VariableNames',{'sample_id','time_s','segment_id','segment_class', ...
    'usable','is_steady','is_small_change','is_large_transition', ...
    'is_thermal_recovery'});
labels.selection_reason=selectionReason;
labels.possible_thermal_recovery=thermalHint;

smoothedTable = array2table(smoothed,'VariableNames',signalNames);
rateNames = cellfun(@(x)[x '_rate'],signalNames,'UniformOutput',false);
rateTable = array2table(rate,'VariableNames',rateNames);
diagnostics = struct('signalNames',{signalNames},'smoothed',smoothedTable, ...
    'rate',rateTable,'normalizedOperatingRate',normalizedOperatingRate, ...
    'normalizedExternalRate',normalizedExternalRate, ...
    'smoothingSampleCount',smoothCount,'rateSpan_s',options.rateSpan_s, ...
    'rateNoiseFloorMultiplier',options.rateNoiseFloorMultiplier, ...
    'normalizedRateNoiseSigma_per_s',normalizedRateNoise, ...
    'Pt3EqRateNoiseSigma_Paps',pt3EqRateNoise, ...
    'Tt45RateNoiseSigma_Kps',tt45RateNoise, ...
    'effectiveNormalizedRateLimit_per_s',effectiveOperatingLimit, ...
    'effectivePt3EqRateLimit_Paps',effectivePt3EqLimit, ...
    'effectiveTt45RateLimit_Kps',effectiveTt45Limit, ...
    'AltitudeRateNoiseSigma_mps',altitudeRateNoise, ...
    'MachRateNoiseSigma_per_s',machRateNoise, ...
    'effectiveAltitudeRateLimit_mps',effectiveAltitudeLimit, ...
    'effectiveMachRateLimit_per_s',effectiveMachLimit, ...
    'steadyRawCandidate',steadyRawCandidate, ...
    'steadyConfirmedBeforeDynamicClassification',steadyMask, ...
    'steadyBridgedSampleCount',nnz(steadyCandidate & ~steadyRawCandidate), ...
    'dynamicCandidateMask',remaining, ...
    'secondaryCandidateMask',remaining,'spanEligibleMask',spanEligible, ...
    'remainingRuns',remainingRuns,'secondaryBoundaryPhase',boundaryPhase, ...
    'secondaryRuns',secondaryRuns,'secondarySpans',secondarySpans, ...
    'amplitudeNoiseSigma',amplitudeNoise,'baseSpanLimits',baseSpanLimits, ...
    'effectiveSpanLimits',spanLimits,'diagnosticSpanReferences',diagnosticSpanReferences, ...
    'hardSpanSignalNames',{signalNames(1:6)}, ...
    'possibleThermalRecoveryMask',thermalHint, ...
    'ignoredLegacyOptions',{options.ignoredLegacyOptions}, ...
    'classificationOrder','steady_first_then_both_sides_of_local_rate_boundaries');

result = struct('schemaVersion','SHT_F32_SEGMENTATION_V7_LOCAL_SPAN', ...
    'options',options,'sampleTime_s',dt,'labels',labels, ...
    'segments',segmentTable,'diagnostics',diagnostics);
end

function options = local_options(user)
options = struct('smoothingDuration_s',2.0,'rateSpan_s',2.0, ...
    'initializationExclusion_s',20.0,'steadyMinimumDuration_s',10.0, ...
    'steadyGuard_s',1.0,'steadyNormalizedRateLimit_per_s',0.0025, ...
    'steadyPt3EqRateLimit_Paps',500.0,'steadyTt45RateLimit_Kps',0.25, ...
    'steadyAltitudeRateLimit_mps',2.0,'steadyMachRateLimit_per_s',0.0004, ...
    'steadyBridgeGap_s',0.50, ...
    'rateNoiseFloorMultiplier',3.0, ...
    'smallChangeMinimumDuration_s',20.0, ...
    'smallChangeMaximumDuration_s',Inf, ...
    'smallChangeMaximumAmplitude',0.20, ...
    'secondaryBoundaryRate_per_s',0.002,'secondaryBoundaryBridge_s',0.5, ...
    'secondaryBoundaryExpansion_s',1.0, ...
    'amplitudeNoiseFloorMultiplier',6, ...
    'thermalMinimumDuration_s',2.0,'sampleTimeTolerance',1e-6);
legacy={'activityNormalizedRate_per_s','activityBridgeGap_s', ...
    'activityExpansion_s','smallChangeMinimumExternalAmplitude', ...
    'smallChangePt3EqSpan_Pa','smallChangeTt45Span_K','smallChangePs0Span_Pa', ...
    'smallChangeTt1Span_K','smallChangeTsAmbSpan_K'};
ignored={};
names = fieldnames(user);
for i = 1:numel(names)
    if strcmp(names{i},'ignoredLegacyOptions'),continue;end
    if ismember(names{i},legacy)
        ignored{end+1}=names{i}; %#ok<AGROW>
        continue;
    end
    if ~isfield(options,names{i})
        error('SHT:F32Segment:UnknownOption','未知分段选项：%s。',names{i});
    end
    options.(names{i}) = user.(names{i});
end
options.ignoredLegacyOptions=ignored;
if ~isempty(ignored)
    warning('SHT:F32Segment:RetiredExcitationOptions', ...
        '第二层已取消最低激励及未经验证的温压硬上限，下列旧配置不再生效：%s。',strjoin(ignored,', '));
end
% 最短时间指最终交付片段的持续时间。稳态两端各去掉保护区后仍须
% 满足10 s；小幅变化默认至少20 s，长时间的小幅变化不因时长被排除。
positive = {'smoothingDuration_s','rateSpan_s','steadyMinimumDuration_s', ...
    'smallChangeMinimumDuration_s','steadyNormalizedRateLimit_per_s', ...
    'steadyPt3EqRateLimit_Paps','steadyTt45RateLimit_Kps', ...
    'steadyAltitudeRateLimit_mps','steadyMachRateLimit_per_s', ...
    'rateNoiseFloorMultiplier','smallChangeMaximumAmplitude','amplitudeNoiseFloorMultiplier', ...
    'secondaryBoundaryRate_per_s'};
for i = 1:numel(positive)
    value = options.(positive{i});
    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || value<=0
        error('SHT:F32Segment:Duration','%s必须为有限正数。',positive{i});
    end
end
for name={'steadyGuard_s','steadyBridgeGap_s','initializationExclusion_s', ...
        'secondaryBoundaryBridge_s','secondaryBoundaryExpansion_s'}
    value=options.(name{1});
    if ~isnumeric(value)||~isscalar(value)||~isfinite(value)||value<0
        error('SHT:F32Segment:Duration','%s必须为有限非负数。',name{1});
    end
end
maximum = options.smallChangeMaximumDuration_s;
if ~isnumeric(maximum) || ~isscalar(maximum) || isnan(maximum) || ...
        maximum<options.smallChangeMinimumDuration_s
    error('SHT:F32Segment:Duration', ...
        '小幅变化最长时间不得小于最短时间；Inf表示不限制上限。');
end
end

function [small,large,boundary,reason]=local_extract_small(runs,phase,value,time,limits,options)
% 变化率只用于局部过程分界，不是数据资格门。phase为true或false的
% 每一段都执行完全相同的幅度和时长检查，恒定输入下的热缓变也能接纳。
% 不在达到幅度上限的位置强行切段，否则可将整体大过渡伪装成多个小段。
n=numel(time);small=false(n,1);large=small;boundary=small;
reason=repmat("unclassified",n,1);
for k=1:height(runs)
    index=runs.first(k):runs.last(k);localPhase=phase(index);
    first=[index(1);index(find(diff(localPhase)~=0)+1)'];
    last=[first(2:end)-1;index(end)];
    for j=1:numel(first)
        segment=first(j):last(j);duration=time(last(j))-time(first(j));
        span=max(value(segment,:),[],1)-min(value(segment,:),[],1);
        if any(span>limits)
            large(segment)=true;reason(segment)="local_process_span_exceeds_upper";
        elseif duration<options.smallChangeMinimumDuration_s-1e-9
            reason(segment)="duration_below_minimum";
        elseif duration>options.smallChangeMaximumDuration_s+1e-9
            reason(segment)="duration_above_configured_maximum";
        else
            small(segment)=true;reason(segment)="local_span_and_duration_pass";
        end
        boundary(first(j))=true;
    end
end
end

function rate = local_centered_rate(value,time,span_s)
n = size(value,1);
dt = median(diff(time));
lag = max(1,round(0.5*span_s/dt));
rate = zeros(size(value));
for i = 1:n
    first = max(1,i-lag);
    last = min(n,i+lag);
    denominator = time(last)-time(first);
    if denominator > 0
        rate(i,:) = (value(last,:)-value(first,:))/denominator;
    end
end
end

function sigma = local_robust_sigma(value)
value = value(isfinite(value));
if isempty(value), sigma = 0; return; end
center = median(value);
sigma = 1.4826*median(abs(value-center));
end

function q = local_quantile(value,fraction)
value = sort(value(isfinite(value)));
if isempty(value), q = 0; return; end
position = 1+(numel(value)-1)*fraction;
lower = floor(position); upper = ceil(position);
if lower==upper
    q=value(lower);
else
    q=value(lower)+(position-lower)*(value(upper)-value(lower));
end
end

function value = local_bridge(value,maxGap)
if maxGap<=0, return; end
falseRuns = local_runs(~value,(1:numel(value))');
for i=1:height(falseRuns)
    first=falseRuns.first(i); last=falseRuns.last(i);
    if first>1 && last<numel(value) && last-first+1<=maxGap
        value(first:last)=true;
    end
end
end

function result=local_bounded_morphology(seed,allowed,maxGap,expansion)
% 在每个允许区间内独立连接/扩展，明确禁止跨越稳态或无效屏障。
result=false(size(seed));
runs=local_runs(allowed,(1:numel(seed))');
for i=1:height(runs)
    index=runs.first(i):runs.last(i);
    part=local_bridge(seed(index),maxGap);
    result(index)=local_expand(part,expansion);
end
end

function value = local_expand(value,count)
if count<=0, return; end
kernel=ones(2*count+1,1);
value=conv(double(value),kernel,'same')>0;
end

function value = local_keep_long(value,minimumCount)
runs=local_runs(value,(1:numel(value))');
value(:)=false;
for i=1:height(runs)
    if runs.last(i)-runs.first(i)+1>=minimumCount
        value(runs.first(i):runs.last(i))=true;
    end
end
end

function steady = local_trim_steady(candidate,time,dt,options)
runs=local_runs(candidate,time);
steady=false(size(candidate));
guard=round(options.steadyGuard_s/dt);
minimum=round(options.steadyMinimumDuration_s/dt)+1;
for i=1:height(runs)
    first=runs.first(i)+guard; last=runs.last(i)-guard;
    if last-first+1>=minimum
        steady(first:last)=true;
    end
end
end

function runs = local_runs(mask,time)
mask=logical(mask(:));
edge=diff([false;mask;false]);
first=find(edge==1); last=find(edge==-1)-1;
if isempty(first)
    runs=table(zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1), ...
        'VariableNames',{'first','last','start_s','end_s'});
else
    runs=table(first,last,time(first),time(last), ...
        'VariableNames',{'first','last','start_s','end_s'});
end
end

function [sampleId,segments] = local_segment_table(sampleClass,time,quality,breakBefore)
n=numel(time);
first=unique([1;find(sampleClass(2:end)~=sampleClass(1:end-1))+1;find(breakBefore)]);
last=[first(2:end)-1;n];
count=numel(first);
sampleId=strings(n,1);
segment_id=strings(count,1); segment_class=strings(count,1);
start_s=zeros(count,1); end_s=zeros(count,1); duration_s=zeros(count,1);
sample_count=zeros(count,1); usable_fraction=zeros(count,1);
for i=1:count
    segment_id(i)=sprintf('F32-SEG-%03d',i);
    sampleId(first(i):last(i))=segment_id(i);
    segment_class(i)=sampleClass(first(i));
    start_s(i)=time(first(i)); end_s(i)=time(last(i));
    duration_s(i)=end_s(i)-start_s(i);
    sample_count(i)=last(i)-first(i)+1;
    usable_fraction(i)=mean(quality(first(i):last(i)));
end
segments=table(segment_id,segment_class,first,last,start_s,end_s, ...
    duration_s,sample_count,usable_fraction);
end
