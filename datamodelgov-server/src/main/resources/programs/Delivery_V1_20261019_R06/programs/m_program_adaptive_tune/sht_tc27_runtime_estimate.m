function estimate=sht_tc27_runtime_estimate(task,options,context)
%SHT_TC27_RUNTIME_ESTIMATE TC27运行前工程估时，不求值DLL、不改变算法配置。
% 固化成本来自本分支完整实测；本次规模只用于估时，绝不传回辨识或UQ。
% context.prepared为05已经核验的结果；没有它时只读Excel长度作粗估。
% 工程范围不是概率置信区间，也不是计算预算或强制停止时间。
if nargin<2,options=struct();end
if nargin<3,context=struct();end
validateattributes(options,{'struct'},{'scalar'});
validateattributes(context,{'struct'},{'scalar'});
task=char(task);
allowed={'steady_update','uq_C','uq_D','uq_CD','prediction'};
assert(ismember(task,allowed),'TC27:Timing:Task','未支持的估时任务%s。',task);
w=local_workload(task,options,context);
parts=struct('preparation_s',0,'pointFit_s',0,'historyFit_s',0, ...
    'localGuide_s',0,'particleSampling_s',0,'predictionAndDelivery_s',0);
assumptions={};route=local_value(context,'route',local_value(options,'route','transient_instant'));
if isfield(context,'model'),route=context.model.route;end
if isfield(w,'route'),route=w.route;end
assert(ismember(route,{'steady','transient_instant'}),'TC27:Timing:Route','未知路径。');
backendFactor=1;
evidence={};benchmark='';expectedStages=NaN;expectedCandidates=NaN;
if strcmp(task,'prediction')
    local_count(w.predictionPoints,'predictionPoints',1);
    % R070新入口五次完整点级调用3.015~5.715s；固定I/O与逐点成本只作拆分假设。
    parts.preparation_s=1.5;
    parts.predictionAndDelivery_s=2.5*w.predictionPoints;
    benchmark='TC27_R070_POINT_PREDICTION_20261002';
    evidence={'TC27_R070_EXEC_20261002/R070_实施结果与阶段性回收.md#6'};
    assumptions={'每点2.5秒加1.5秒准备为完整实测约4秒的工程拆分，不是分项实测'; ...
        '新工况热平衡、选根重试可能显著超出范围；不假定13项瞬态系数均影响热平衡'};
elseif strcmp(task,'steady_update')
    local_count(w.trainingPoints,'trainingPoints',1);local_count(w.groupCount,'groupCount',1);
    local_count(w.parameterCount,'parameterCount',1);
    b=local_budget(options,'maxIterationB',10);
    d0=local_budget(options,'maxIterationD0',10);
    d1=local_budget(options,'maxIterationD1',10);
    dt=local_positive(options,'integrationStep_s',.1,false);
    vt=local_positive(options,'validationIntegrationStep_s',.025,false);
    include=logical(local_value(options,'includeSmallHistory',true));
    % R065完整TI/II: B/C=120.1，D0=182.7，D1=2672.4，末端验证交付=67.012s。
    % 迭代比例只用配置上限缩放。基线提前停止，不把最大次数当已知实际次数。
    if strcmp(route,'steady'),backendFactor=2;end
    parts.preparation_s=local_value(context,'preparationElapsed_s',8*double(~w.prepared));
    bScale=(1+b)/11;d0Scale=(1+d0)/11;d1Scale=(1+d1)/11;
    parts.pointFit_s=backendFactor*(120.1*w.trainingPoints/18*bScale+ ...
        182.7*w.trainingPoints/18*w.parameterCount/72*d0Scale);
    if include&&w.smallFit_s>0
        fd=local_value(options,'differenceD1','forward');factor=1;
        if strcmp(fd,'central'),factor=2;end
        warmup=local_value(options,'localWarmup_s',60);
        validateattributes(warmup,{'numeric'},{'scalar','real','finite','nonnegative'});
        preparation=warmup*w.smallCount/180;
        historyWork=.8*w.smallFit_s/180.4+.2*preparation;
        parts.historyFit_s=2672.4*historyWork*(.25+.75*.1/dt)* ...
            w.parameterCount/72*d1Scale*factor;
    else
        % 原程序仍执行D1点微调，不能因无历程便把D1算作零。
        parts.pointFit_s=parts.pointFit_s+backendFactor*182.7* ...
            w.trainingPoints/18*w.parameterCount/72*d1Scale;
    end
    parts.predictionAndDelivery_s=17.012+25*w.testPoints/8+ ...
        25*w.testSmall_s/100.5*(.25+.75*.025/vt);
    benchmark='TC27_R065_FULL_TI_II_20260928';
    evidence={'TC27_R065_Step1A_20260928/R065_A_完整辨识与交付核验.md'};
    assumptions={'基准18训练点、9组、72参数、180.4秒小幅拟合、8测试点、100.5秒小幅测试'; ...
        '真实迭代/最终节点数未求解前未知，节点代理和工作量比例不是对算法节点的限制'; ...
        '稳态路径点求解成本按TI的2倍暂估，方法I/II未实测部分采用同成本并扩大范围'; ...
        '首次选段前暂按每80秒一个稳态窗口、37.58%小幅占比估计，05后以实际范围替换'};
else
    assert(strcmp(local_value(options,'observationMode','steady_points'),'steady_points'), ...
        'TC27:Timing:Unsupported','联合历程UQ未验证，不给伪造的可执行耗时。');
    assert(strcmp(local_value(options,'steadyCBackend','direct_dll'),'direct_dll'), ...
        'TC27:Timing:Unsupported','当前固化估时只适用于直接DLL，不覆盖历史代理研究。');
    local_count(w.trainingPoints,'trainingPoints',1);local_count(w.parameterCount,'parameterCount',1);
    d=local_positive(options,'dMaxIterations',3,true);
    samples=local_positive(options,'localSampleCount',512,true);
    reuse=logical(local_value(options,'thermalReuseEnabled',strcmp(route,'transient_instant')));
    if ~reuse,backendFactor=397.947/60.5656077;end
    if strcmp(route,'steady'),backendFactor=2*backendFactor;end
    parts.preparation_s=local_value(context,'preparationElapsed_s',8*double(~w.prepared));
    % D实测包含协方差、热参考和D最终重新线性化；C与CD只计一次这部分。
    parts.localGuide_s=60.5656077*backendFactor*w.trainingPoints/18* ...
        (.2+.8*w.parameterCount/72)*(d+1)/4;
    publish=logical(local_value(context,'publish',true));
    if strcmp(task,'uq_D')
        parts.localGuide_s=parts.localGuide_s+2*(samples/512-1);
        parts.localGuide_s=max(1,parts.localGuide_s);
        parts.predictionAndDelivery_s=publish*(21.1460243+40*w.testPoints/8)*(samples/512);
        benchmark='TC27_R071_D_THERMAL_REUSE_20261002';
        evidence={'TC27_R071_DThermalReuse_20261002/R071_D方法热平衡复用改进与对照验证.md#4'};
    else
        n=local_positive(options,'particleCount',512,true);
        m=local_positive(options,'cDirectMoveSweeps',6,true);
        f=local_positive(options,'cDirectFinalMoveSweeps',32,true);
        expectedStages=14;
        if strcmp(local_value(options,'cSamplerProfile','quality'),'legacy_reference')
            expectedStages=7;
        end
        expectedCandidates=n*((expectedStages-1)*m+f+1);
        % R073两种子平均推断11212.3198825s，扣一次D准备后按候选量缩放。
        parts.particleSampling_s=(11212.3198825-60.5656077)* ...
            expectedCandidates/(512*(13*6+32+1))*w.trainingPoints/18* ...
            backendFactor*(.8+.2*w.parameterCount/72);
        draws=local_positive(options,'cConditionalDrawCount',8,true);
        box=local_positive(options,'cBoxIntegrationCount',512,true);
        parts.particleSampling_s=parts.particleSampling_s*(.9+.1*box/512);
        parts.predictionAndDelivery_s=publish*(49.00100255+400*w.testPoints/8)*n/512*draws/8;
        benchmark='TC27_R073_C_QUALITY_TWO_SEEDS_20261003';
        evidence={'TC27_R073_CQuality_20261003/complete_timing_and_DLL.csv'; ...
            'TC27_R073_CQuality_20261003/complete_comparison.csv'};
    end
    assumptions={'R073基准512粒子、14温度层、6/32移动；温度层数是工程假设，不是改写采样配置'; ...
        'R071基准3次局部更新、512样本；参数/训练规模和完整热回退改变成本'; ...
        'C本身包含D参考准备，CD不重复加一次D；预测按本次测试点/样本缩放'; ...
        '无热复用使用R071对照成本比；自由转速稳态再乘2是未独立实测的保守外推'; ...
        '不把历史缓存命中当新数据必然收益；图表、审计与文件末端I/O差异纳入工程范围'};
end
seconds=sum(structfun(@double,parts));
factor=2.1;if backendFactor>1,factor=3;end
estimate=struct('available',true,'status','rough_numeric','seconds',seconds, ...
    'lowerSeconds',.45*seconds,'upperSeconds',max(factor*seconds,seconds+10), ...
    'modelVersion','TC27_FIXED_WORK_V1_20261005','benchmarkVersion',benchmark, ...
    'evidence',{evidence},'task',task,'stage',local_value(context,'stage',w.stage), ...
    'workload',w,'stages',parts,'assumptions',{assumptions}, ...
    'expectedTemperatureStages',expectedStages,'expectedParticleCandidates',expectedCandidates, ...
    'benchmarkEnvironment','Windows x64, MATLAB R2019b, R018 TC27 DLL/VC2010, 本项目开发机', ...
    'hardwareLimitation','原逐批报告未冻结CPU型号/后台负载；非目标机实测，不能保证跨机时间', ...
    'basis','固化实测总成本按本次工作量缩放；历史仅校准，不设历史次数准入门槛', ...
    'scope','本算法入口至结果预测及Excel交付，不含上游辨识、用户暂停或排队', ...
    'intervalMeaning','工程范围，非概率置信区间、截止时间或停止条件', ...
    'coldFullReferenceSeconds',seconds,'remainingResolved',false, ...
    'remainingSeconds',NaN,'historyCalibrated',false);
if strcmp(task,'steady_update')
    estimate.scope='05/06新数据更新至预测及Excel；已提供准备结果时准备耗时单列';
elseif strcmp(task,'prediction')
    estimate.scope='独立新工况预测入口至预测Excel/JSON，不含模型辨识或UQ';
elseif ~local_value(context,'publish',true)
    estimate.scope='UQ入口至推断完成；本次不发布预测和Excel';
end
% 仅同配置完成记录可校准。缺记录仍保留固化粗估，不在此写历史文件。
if isfield(context,'historyEstimate')
    h=context.historyEstimate;
    if isfield(h,'available')&&h.available&&isfinite(h.seconds)&&h.seconds>0
        estimate.uncalibratedSeconds=seconds;
        ratio=h.seconds/seconds;
        estimate.seconds=h.seconds;estimate.lowerSeconds=.45*h.seconds;
        estimate.upperSeconds=max(factor*h.seconds,h.seconds+10);
        estimate.stages=structfun(@(x)x*ratio,parts,'UniformOutput',false);
        estimate.coldFullReferenceSeconds=h.seconds;estimate.historyCalibrated=true;
        estimate.historyEvidence=h;
    end
end
if local_value(context,'resume',false)
    estimate.status='cold_reference_for_resume';
    estimate.basis=[estimate.basis,'；续算只提供从头完整参考，不冒充剩余时间'];
end
estimate.center_s=estimate.seconds;estimate.lower_s=estimate.lowerSeconds;estimate.upper_s=estimate.upperSeconds;
if local_value(context,'display',true)
    fprintf('TC27 %s：预计%.1f分钟，工程范围%.1f~%.1f分钟；%s。\n', ...
        task,estimate.seconds/60,estimate.lowerSeconds/60,estimate.upperSeconds/60,estimate.stage);
    fprintf('  依据%s；%s\n',benchmark,estimate.scope);
    if strcmp(estimate.status,'cold_reference_for_resume')
        fprintf('  上述为从头运行参考，不是续算剩余时间；未扣除未核验的旧检查点。\n');
    end
end
end

function w=local_workload(task,o,c)
% 只读Excel规模或已准备结构，不调用筛选/配置/DLL，不创建目录。
if isfield(c,'workload'),w=c.workload;return;end
w=struct('prepared',false,'stage','before_selection','trainingPoints',0, ...
    'groupCount',0,'parameterCount',0,'smallFit_s',0,'smallCount',0, ...
    'testPoints',0,'testSmall_s',0,'rawHistory_s',0);
if strcmp(task,'prediction'),w.predictionPoints=c.predictionPoints;return;end
if isfield(c,'prepared')&&~isempty(c.prepared)
    p=c.prepared;w.prepared=true;w.stage='after_selection';
    w.trainingPoints=height(p.combinedSteady);w.groupCount=p.groupCount;
    [w.smallFit_s,w.smallCount]=local_small(p.train.small);
    for j=1:numel(p.testSets)
        w.testPoints=w.testPoints+height(p.testSets(j).means);
        w.testSmall_s=w.testSmall_s+local_small(p.testSets(j).small);
    end
else
    assert(isfield(o,'steadyTrainingFile')&&isfield(o,'trainingHistoryFile'), ...
        'TC27:Timing:Inputs','运行前估时需要明确训练点与新历程Excel。');
    t=local_read(o.steadyTrainingFile);raw=local_read(o.trainingHistoryFile);
    duration=local_duration(raw);w.rawHistory_s=duration;
    w.trainingPoints=height(t)+ceil(duration/80);
    w.groupCount=max(1,ceil(w.trainingPoints/2));
    w.smallFit_s=duration*(180.4/480);w.smallCount=max(1,ceil(duration/160));
    points=local_value(o,'testPointFiles',{});histories=local_value(o,'testHistoryFiles',{});
    for j=1:numel(points),a=local_read(points{j});w.testPoints=w.testPoints+height(a);end
    for j=1:numel(histories)
        a=local_read(histories{j});d=local_duration(a);
        w.testPoints=w.testPoints+ceil(d/60);w.testSmall_s=w.testSmall_s+d*(100.5/240);
    end
end
w.parameterCount=max(1,8*w.groupCount);
w.parameterCountMeaning='按分组规模暂估自由参数数；不规定算法节点';
model=local_value(c,'model',[]);
if isempty(model)&&startsWith(task,'uq_')
    assert(isfield(o,'modelFile')&&isfile(char(o.modelFile)), ...
        'TC27:Timing:Model','UQ估时须提供正式模型Excel。');
    model=sht_tc27_delivery('read',[],char(o.modelFile));
end
if ~isempty(model)
    w.route=model.route;s=model.finalSchedule;
    n=1+numel(s.fuelBias.xNodes);
    for j=1:numel(s.healthEntries)
        e=s.healthEntries(j);n=n+numel(e.xNodes);
        if e.pressureLoss,n=n-nnz(abs(e.xNodes)<1e-12);end
    end
    w.parameterCount=n;w.parameterCountMeaning='所选TC27 Excel自由节点，含燃油、不含固定零压损锚点';
end
end

function [seconds,count]=local_small(s)
seconds=0;count=numel(s);
for k=1:count,seconds=seconds+local_duration(s(k).data);end
end
function t=local_read(file)
assert(isfile(char(file)),'TC27:Timing:File','估时输入文件不存在：%s',char(file));
t=readtable(char(file));assert(height(t)>0,'TC27:Timing:Empty','输入数据为空。');
end
function d=local_duration(t)
assert(ismember('Time_s',t.Properties.VariableNames),'TC27:Timing:Time','历程缺少Time_s。');
x=t.Time_s;assert(isnumeric(x)&&numel(x)>=2&&all(isfinite(x))&&all(diff(x)>0), ...
    'TC27:Timing:Time','历程时间必须有限、严格递增且至少两条记录。');
d=x(end)-x(1);
end
function value=local_value(s,name,fallback)
value=fallback;if isfield(s,name)&&~isempty(s.(name)),value=s.(name);end
end
function x=local_positive(s,name,fallback,integer)
x=local_value(s,name,fallback);validateattributes(x,{'numeric'},{'scalar','real','finite','positive'});
if integer,validateattributes(x,{'numeric'},{'integer'});end
end
function local_count(x,name,minimum)
assert(isnumeric(x)&&isscalar(x)&&isfinite(x)&&x==floor(x)&&x>=minimum, ...
    'TC27:Timing:Count','%s数量无效。',name);
end
function x=local_budget(s,name,fallback)
x=local_value(s,name,fallback);
validateattributes(x,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
end
