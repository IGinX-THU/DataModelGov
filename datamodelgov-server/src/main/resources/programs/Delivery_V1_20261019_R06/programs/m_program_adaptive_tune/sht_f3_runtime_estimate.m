function out=sht_f3_runtime_estimate(schedule,evidence,maxIterations,testPoints,actualCount,options)
%SHT_F3_RUNTIME_ESTIMATE 按所选模型和数据路线无DLL估计有效计算与导出耗时。
% 使用固定实测成本，不读取历史report_outputs。物理覆盖检查之前只有
% 参数数目的上界；actualCount只允许由实际覆盖合同提供，不预设32维。
if ischar(schedule)&&strcmpi(schedule,'unboundData')
    data=evidence;o=maxIterations;
    bfile=fullfile(fileparts(mfilename('fullpath')),'TestData','runtime_cost_baselines','F3_R2019b_cost_v1.json');
    b=jsondecode(fileread(bfile));t=data.identification.time_s;
    n=ceil((t(end)-t(1))/o.integrationStep_s);
    out=struct('schemaVersion','F3_UNBOUND_DATA_COST_B23','noDll',true, ...
        'recordCount',height(data.identification),'duration_s',t(end)-t(1), ...
        'integrationStep_s',o.integrationStep_s,'singleHistoryStepCount',n, ...
        'singleHistoryRange_s',n*b.routes.historyStepSeconds(:)', ...
        'parameterCount',[],'identificationTotalRange_s',[], ...
        'baselineSha256',sht_tc27_file_identity(bfile), ...
        'unknowns',{{'parent node count','physical coverage','selected window count','maximum iterations'}}, ...
        'scope','一次完整记录积分的工程估计，不是未绑定父模型的辨识总耗时');
    return;
end
if ischar(schedule)&&ismember(lower(schedule),{'transient','transientreplay'})
    out=local_transient_estimate(schedule,evidence,maxIterations);return;
end
if ischar(schedule)&&strcmpi(schedule,'uq')
    out=local_uq_estimate(evidence,maxIterations);return;
end

if ischar(schedule)&&strcmpi(schedule,'prediction')
    out=local_prediction_estimate(evidence);return;
end
if nargin<4,testPoints=0;end
if nargin<5,actualCount=[];end
if nargin<6,options=struct();end
o=struct('modelRoute','transient_instant','parameterSet','set1', ...
    'historyIntegrationStep_s',.1,'runtimeEstimateTrainingReplay_s',0, ...
    'runtimeEstimateTestWork',struct('historyStepCount',0,'historySegmentCount',0));
for f=fieldnames(o).',if isfield(options,f{1}),o.(f{1})=options.(f{1});end,end
validateattributes(maxIterations,{'numeric'},{'scalar','integer','>=',1,'<=',10});
validateattributes(testPoints,{'numeric'},{'scalar','integer','nonnegative'});
assert(isstruct(evidence)&&istable(evidence.steadyData)&&height(evidence.steadyData)>0, ...
    'SHT:F3Estimate:Evidence','必须提供至少一个完整平均稳态点。');
path=fullfile(fileparts(mfilename('fullpath')),'TestData','runtime_cost_baselines','F3_R2019b_cost_v1.json');
assert(isfile(path),'SHT:F3Estimate:Baseline','缺少版本化估时成本基准。');
b=jsondecode(fileread(path));
assert(strcmp(b.schemaVersion,'F3_COST_R2019B_R042')&&b.referencePointCount>0&& ...
    b.referenceParameterCount>0&&all(b.referenceJacobianSeconds>0), ...
    'SHT:F3Estimate:Baseline','估时基准合同无效。');
active=[1,2,7,8,10,11,12];
if strcmp(o.parameterSet,'set2'),active=[1,2,6,7,8,10,11,12,14,15];end
parameterUpper=1;
for h=active
    j=find([schedule.healthEntries.cIndex]==h,1);
    if isempty(j),parameterUpper=parameterUpper+1;continue;end
    e=schedule.healthEntries(j);mask=true(numel(e.xNodes),1);
    if e.pressureLoss,mask(e.xNodes==0)=false;end
    parameterUpper=parameterUpper+nnz(mask);
end

f=schedule.fuelBias;
fuelQuery=evidence.steadyData.Wf_mean;
if ~isempty(evidence.historyData.table),fuelQuery=[fuelQuery;evidence.historyData.table.Wf];end
cover=sht_f33_schedule_parameterization('coverage',f.xNodes,fuelQuery/f.wfDesign,.02,false);
parameterUpper=parameterUpper+nnz(cover.activeNode);
n=parameterUpper;isActual=false;
if ~isempty(actualCount)
    validateattributes(actualCount,{'numeric'},{'scalar','integer','positive','<=',parameterUpper});
    n=actualCount;isActual=true;
end
points=height(evidence.steadyData);
unit=b.referenceJacobianSeconds(:).'/(b.referencePointCount*(b.referenceParameterCount+1));
unit=[min(unit),max(unit)].*b.loadAllowance(:).';
iterationRange=[1,maxIterations];
% 每轮前向差分为(n+1)候选，另复核当前点及3个完整正则化提议；
% 发布前还有一次完整Jacobian。覆盖/初始/最终两模型计4候选。
vectorCounts=(iterationRange+1)*(n+1)+4*iterationRange+4;
mult=[1,1];if strcmp(o.modelRoute,'steady'),mult=b.routes.steadyPointMultiplier(:)';end
stepCount=0;
for k=1:numel(evidence.historyData.experiments)
    time=evidence.historyData.experiments(k).replayData.time_s;
    stepCount=stepCount+ceil((time(end)-time(1))/o.historyIntegrationStep_s);
end
segments=evidence.historyMeta.segmentCount;
stepCost=b.routes.historyStepSeconds(:)';
% 准备段、拟合段和每候选热平衡均计费；R1训练选根的先验回放另计一次。
oneVector=points*unit.*mult+stepCount*stepCost+segments*unit.*b.routes.steadyPointMultiplier(:)';
test=o.runtimeEstimateTestWork;
testCost=2*testPoints*unit.*mult;
if strcmp(o.modelRoute,'steady'),testCost=testCost*b.routes.independentSeedAttempts;end
testCost=testCost+2*(test.historyStepCount*stepCost+ ...
    test.historySegmentCount*unit.*b.routes.steadyPointMultiplier(:)');
branchCost=[0,0];
if strcmp(o.modelRoute,'steady')
    branchCost=ceil(o.runtimeEstimateTrainingReplay_s/o.historyIntegrationStep_s)*stepCost;
end
compute=oneVector.*vectorCounts+testCost+branchCost+b.setupAllowance_s(:).';
export=b.exportAllowance_s(:).';
out=struct('schemaVersion','F3_RUNTIME_ESTIMATE_R042','baselineVersion',b.version, ...
    'baselineSha256',sht_f33_model_adapt_v2('fileHash',path), ...
    'baseline',b,'steadyPointCount',points,'independentTestPointCount',testPoints, ...
    'parameterCount',n,'parameterCountIsActual',isActual,'parameterUpperBound',parameterUpper, ...
    'iterationRange',iterationRange,'candidateVectorCounts',vectorCounts, ...
    'computeRange_s',compute,'exportRange_s',export,'totalRange_s',compute+export, ...
    'modelRoute',o.modelRoute,'historyStepCount',stepCount,'historySegmentCount',segments, ...
    'historyIncludesPreparation',true,'independentTestWork',test, ...
    'trainingBranchReplayRange_s',branchCost, ...
    'integrationNotUsed',stepCount==0&&all(branchCost==0),'includesFinalExactJacobian',true,'includesOptionalTest',true, ...
    'intervalMeaning','工程粗估范围，不是概率置信区间或倒计时', ...
    'exclusions','不含MATLAB启动、排队等待、额外完整历程验证、UQ和无上限失败重试', ...
    'coverageCaveat','物理覆盖前按节点上界估算，实际覆盖合同形成后可传actualCount修订');
end

function out=local_transient_estimate(action,plan,o)
% 历史计时只作工程预算锚点，不是当前新父模型的实测速度保证。
file=fullfile(fileparts(mfilename('fullpath')),'TestData','runtime_cost_baselines','F3_R2019b_cost_v1.json');
b=jsondecode(fileread(file));c=b.transient;
assert(istable(plan)&&height(plan)>0,'瞬态估时必须提供实际局部计划。');
dt=o.integrationStep_s;assert(ismember(dt,[.1,.025]));
seconds=sum(plan.fit_end_s-plan.initialization_start_s);
steps=ceil(seconds/dt);windows=height(plan);
if strcmpi(action,'transientreplay'),vectors=[1,1];
else
    % 初始14向量、逐轮候选及最后真实13列Jacobian；高端含额外试探。
    vectors=[14+15*o.maximumIterations,14+19*o.maximumIterations];
end
compute=vectors.*(steps*reshape(c.integrationStepSeconds,1,[])+windows*reshape(c.equilibriumSeconds,1,[]));
export=reshape(c.exportSeconds,1,[]);
out=struct('schemaVersion','F3_TRANSIENT_ESTIMATE_R002','baselineVersion',b.version, ...
    'baselineSha256',sht_tc27_file_identity(file),'baseline',c,'parameterCount',13, ...
    'actualWindowCount',windows,'integrationStep_s',dt,'integrationSteps',steps, ...
    'preparationSeconds',sum(plan.warmup_s),'fitSampleCount',sum(plan.fit_sample_count), ...
    'candidateVectors',vectors,'computeRange_s',compute,'exportRange_s',export, ...
    'totalRange_s',compute+export,'includesPreparation',true, ...
    'scope','initial equilibrium, measured preparation, fitting, final Jacobian and Excel export', ...
    'limits','engineering range, not a stop budget; excludes MATLAB launch, pause waiting and optional validation');
end

function out=local_prediction_estimate(w)
% 选根含多起点，后验传播含条件样本，输入前向响应单列计费。
% 自主稳态实测前沿用R2单点成本，明确模型转换的工程放大范围。
p=fullfile(fileparts(mfilename('fullpath')),'TestData','runtime_cost_baselines','F3_R2019b_cost_v1.json');
b=jsondecode(fileread(p));u=b.prediction;
count=w.pointCount*(w.seedAttempts+w.jointCount+w.inputDirections);
unit=b.uq.pointVectorSeconds(:)'.*u.steadySolveMultiplier(:)';
compute=count*unit+u.setupAllowance_s(:)';
out=struct('schemaVersion','F3_PREDICTION_COST_R042','baselineVersion',b.version, ...
    'baselineSha256',sht_f33_model_adapt_v2('fileHash',p),'workload',w, ...
    'candidatePointCount',count,'computeRange_s',compute,'exportRange_s',u.exportAllowance_s(:)', ...
    'totalRange_s',compute+u.exportAllowance_s(:)','baseline',u, ...
    'meaning','工程粗估，不是概率区间；自主稳态物理解困难时可能超出', ...
    'includesSeedAndConditionalDraws',true,'includesInputResponse',true);
end

function out=local_uq_estimate(d,o)
% 只按已核参数维数估量工作；阶段数取范围，不强制改变SMC目标。
path=fullfile(fileparts(mfilename('fullpath')),'TestData','runtime_cost_baselines','F3_R2019b_cost_v1.json');
b=jsondecode(fileread(path));u=b.uq;
n=d.main;k=d.conditional;p=d.steadyPoints;
validateattributes([n,k,p],{'numeric'},{'vector','integer','nonnegative','finite'});
assert(n>0&&p>0&&strcmp(o.dataMethod,'steady_only'),'SHT:F3Estimate:UQRoute','仅支持有效平均点维数。');
% 覆盖、主/条件/输入导数以及冻结后四中心和十二条件中心复核均计入。
prepareVectors=2+2*n+2*k+2*u.inputDirections;
dVectors=(o.methodDMaximumIterations+1)*(n+1)+4*o.methodDMaximumIterations;
exportVectors=16+2*n;
unit=u.pointVectorSeconds(:).'.*u.loadAllowance(:).';
dRange=p*(prepareVectors+dVectors+exportVectors)*unit+u.ioAllowance_s(:).';
particle=o.methodCParticleCount;repeat=particle;
if isfield(o,'methodCRepeatParticleCount'),repeat=o.methodCRepeatParticleCount;end
sweeps=o.methodCMoveSweeps;last=0;
if isfield(o,'methodCFinalMoveSweeps'),last=o.methodCFinalMoveSweeps;end
stageRange=[1,o.methodCMaximumStages];
cVectors=(particle+repeat)*(1+sweeps*stageRange+last);
cRange=dRange+p*cVectors.*unit;
out=struct('schemaVersion','F3_UQ_ESTIMATE_C1','dimensions',d, ...
    'baseline',u,'baselineSha256',sht_f33_model_adapt_v2('fileHash',path), ...
    'methodDRange_s',dRange,'methodCRange_s',cRange,'totalRange_s',cRange, ...
    'preparationCandidateVectors',prepareVectors,'methodDCandidateVectors',dVectors, ...
    'exportCandidateVectors',exportVectors,'methodCCandidateVectors',cVectors, ...
    'stageRange',stageRange,'includesIndependentRepeat',true,'includesIndependentPrediction',false, ...
    'physicalCoverageRebuilt',false,'noDll',true, ...
    'meaning','工程工作量范围，非置信区间；失败重试、冷启动、完整预测另计');
if isfield(o,'taskMethod')&&strcmp(o.taskMethod,'D'),out.totalRange_s=dRange;end
end
