function result=Start_TC24_07D_QuickAssessment(user,entry)
% TC24方法D独立入口。只从正式Excel及独立工程配置建立本批概率问题。
% 独立完成C类矩边缘化准备，但不依赖C采样成功。
% 由07转发时延续外层计时；entry不进入user/cfg或概率身份。
if nargin<2
    entry=struct('timer',tic,'startedAt',datestr(now,30), ...
        'entryPoint',mfilename,'displayName','D快速初评入口耗时');
end
if nargin<1,user=struct();end
sht_r2019b_preflight();
% 快速初评默认预算；用户确认弯折尺度0.50，显式给1可回到原工程先验。
% 精查需要显式选择，不因诊断欠佳自动扩成长计算。
defaults=struct('maxIterations',3,'differenceMode','forward', ...
    'predictionMode','linearized','curveBendScale',0.50,'predictionTrainingEnabled',false);
names=fieldnames(defaults);
for k=1:numel(names)
    if ~isfield(user,names{k}),user.(names{k})=defaults.(names{k});end
end
assert(ismember(user.predictionMode,{'linearized','exact'}),'TC24:D:PredictionMode','未知预测方式。');
if isfield(user,'localSeed')
    assert(~isfield(user,'randomSeed') || user.randomSeed==user.localSeed, ...
        'TC24:D:SeedConflict','localSeed与randomSeed不可给定不同值。');
    user.randomSeed=user.localSeed;
end
cfg=user;cfg.modelMode=0;
cfg=sht_tc24_uq_business_inputs(cfg,user);
if ~isfield(cfg,'runtimeDirectory')
    package=sht_tc24_runtime_package();cfg.runtimeDirectory=package.directory;
end
if ~isfield(cfg,'runId'),cfg.runId=['tc24_d_',datestr(now,'yyyymmdd_HHMMSS')];end
assert(startsWith(cfg.runId,'tc24_d_'),'TC24:D:RunId','D运行编号须以tc24_d_开头。');
timer=tic;
firstStep=1;if isfield(user,'firstStep'),firstStep=user.firstStep;end
assert(ismember(firstStep,1:4),'TC24:D:FirstStep','D firstStep应为1至4。');
lastStep=4;if isfield(user,'lastStep'),lastStep=user.lastStep;end
validateattributes(lastStep,{'numeric'},{'scalar','integer','>=',firstStep,'<=',4});
eventOptions=cfg;eventOptions.firstStep=firstStep;
trainingCount=height(sht_tc24_validate_measurements(cfg.trainingFile));
testCount=0;
if ~isempty(cfg.testFile)
    testCount=height(sht_tc24_validate_measurements(cfg.testFile));
end
eventOptions.runtimeEstimate=sht_tc24_fixed_runtime_estimate( ...
    'uq_D',cfg,trainingCount,testCount);
if isfield(cfg,'timingHistoryDirectory')&&~isempty(cfg.timingHistoryDirectory)
    eventOptions.timingQuery=sht_tc24_runtime_estimate('query',cfg,'uq_D');
end
if isfield(user,'progressCallback'),eventOptions.progressCallback=user.progressCallback;end
session=sht_tc24_execution(eventOptions,'uq_D',entry);
control=[];
try
if isfield(user,'enableRunControl')&&user.enableRunControl
    assert(~isempty(session.directory),'TC24:Control:Output','UQ安全停止需独立输出目录。');
    current=sht_steady_model_uq_c_common('buildcontract', ...
        sht_steady_model_uq_c_common('defaultconfig',cfg));
    current=sht_tc24_uq_d_bend_prior(current,user.curveBendScale);
    identity=sht_tc24_uq_external_io('c','controlidentity',cfg,current);identity.assessment='D';
    co=struct('directory',session.directory,'runId',cfg.runId,'resume',false, ...
        'timer',session.timer,'sessionStartDatenum',session.sessionStartDatenum,'sessionToken',session.sessionToken);
    if isfield(user,'resume'),co.resume=logical(user.resume);end
    control=sht_tc24_run_control('open',co,identity);cfg.runControl=control;
    session.notify(struct('phase','run_identity_verified','status','running'));
    [pipeline,found]=sht_tc24_run_control('load',control,'uq_d_pipeline');
    if found,firstStep=pipeline.nextStep;end
    sht_tc24_run_control('boundary',control,'uq_d_pipeline',struct('nextStep',firstStep));
end
session.notify(struct('phase','UQ_D_contract','status','running'));
if firstStep==1
    step1=Start_SteadyModelUQ_C_01_ProblemContract(cfg);
    [step1.contract,step1.bendPriorAudit]=sht_tc24_uq_d_bend_prior(step1.contract,user.curveBendScale);
    step1.prior=sht_steady_model_uq_sampler('buildprior',step1.contract,step1.contract.priorType);
    [step1.manifest,~]=sht_steady_model_uq_c_io('savestep',step1.manifest,1,'problem_contract',step1,step1.manifest.stepRuntime_s(1));
else
    manifest=sht_steady_model_uq_c_io('resolvewritable',cfg);
    step1=sht_steady_model_uq_c_io('loadstep',manifest,1);
    % 恢复必须仍为同一概率问题；不允许改输入文件或先验后沿用旧矩阵。
    old=step1.contract.config;fields=fieldnames(user);
    mutable={'runId','firstStep','lastStep','progressCallback','skipValidation','resumeIterations', ...
        'maxIterations','localSampleCount','localSeed','enableRunControl','resume','runControl'};
    for i=1:numel(fields)
        f=fields{i};if ismember(f,mutable),continue;end
        if isfield(old,f),assert(isequaln(user.(f),old.(f)), ...
                'TC24:D:ResumeConfiguration','恢复时概率配置%s发生变化。',f);end
    end
    current=sht_steady_model_uq_c_common('buildcontract',old);
    current=sht_tc24_uq_d_bend_prior(current,user.curveBendScale);
    assert(strcmp(current.baseContractHash,step1.contract.baseContractHash) && ...
        strcmp(current.auxiliaryContractHash,step1.contract.auxiliaryContractHash) && ...
        strcmp(current.contractHash,step1.contract.contractHash), ...
        'TC24:D:ResumeContract','当前数据、模型或概率合同变化，请使用新runId。');
end
if ~isempty(control),sht_tc24_run_control('boundary',control,'uq_d_pipeline',struct('nextStep',max(firstStep,2)));end
if lastStep==1
    if ~isempty(control),sht_tc24_run_control('finish',control,'partial');end
    result=struct('runId',cfg.runId,'method','D','config',cfg,'steps',{{step1}}, ...
        'manifest',step1.manifest,'shortVerificationOnly',true, ...
        'execution',session.finish('partial','requested_last_step',[],'completed_steps'));return;
end
session.notify(struct('phase','UQ_D_marginalization','status','running'));
if firstStep<=2
    step2=Start_SteadyModelUQ_C_02_NuisanceMarginalization(cfg);
else
    step2=sht_steady_model_uq_c_io('loadstep',manifest,2);
end
manifest=step2.manifest;
if ~isempty(control),sht_tc24_run_control('boundary',control,'uq_d_pipeline',struct('nextStep',max(firstStep,3)));end
if lastStep==2
    if ~isempty(control),sht_tc24_run_control('finish',control,'partial');end
    result=struct('runId',cfg.runId,'method','D','config',cfg,'steps',{{step1,step2}}, ...
        'manifest',manifest,'shortVerificationOnly',true, ...
        'execution',session.finish('partial','requested_last_step',[],'completed_steps'));return;
end
session.notify(struct('phase','UQ_D_local_assessment','status','running'));
options=user;options.checkpointFile=fullfile(manifest.runDir,'D_iteration_checkpoint.mat');
if ~isempty(control),options.runControl=control;end
if firstStep<=3
    quick=sht_tc24_uq_method_d(step1.contract,step1.prior,step2.likelihood,options);
    [manifest,~]=sht_steady_model_uq_c_io('savestep',manifest,3,'quick_local_assessment',quick,quick.runtime_s);
else
    quick=sht_steady_model_uq_c_io('loadstep',manifest,3);
end
if ~isempty(control),sht_tc24_run_control('boundary',control,'uq_d_pipeline',struct('nextStep',4));end
writetable(quick.history,fullfile(manifest.reportDir,'TC24_D_iterations.csv'));
writetable(quick.summary,fullfile(manifest.reportDir,'TC24_D_local_parameter_intervals.csv'));
if isfield(quick,'nonlinearCorrection')
    d=quick.nonlinearCorrection;
    writetable(table(d.weightESS,d.sampleCount,d.maximumWeight,d.stable,d.logRatioRange, ...
        'VariableNames',{'weight_ESS','sample_count','maximum_weight','selected','log_ratio_range'}), ...
        fullfile(manifest.reportDir,'TC24_D_nonlinear_correction.csv'));
    writetable(quick.uncorrectedSummary,fullfile(manifest.reportDir,'TC24_D_before_correction.csv'));
    writetable(quick.correctedSummary,fullfile(manifest.reportDir,'TC24_D_after_correction.csv'));
end
result=struct('runId',cfg.runId,'method','D','steps',{{step1,step2,quick}}, ...
    'manifest',manifest,'runtime_s',toc(timer),'shortVerificationOnly',false);
result.config=cfg;
result.predictionMode=user.predictionMode;
result.curveBendScale=user.curveBendScale;
result.predictionTrainingEnabled=user.predictionTrainingEnabled;
if isfield(user,'predictionSampleCount'),result.predictionSampleCount=user.predictionSampleCount;end
if isfield(user,'predictionRandomSeed'),result.predictionRandomSeed=user.predictionRandomSeed;end
fprintf('TC24-D: quality=%s, gradient=%.4g, local Rhat=%.4f, runtime=%.1fs.\n', ...
    quick.quality,quick.projectedGradient,quick.localRhat,result.runtime_s);
if lastStep==3 || (isfield(user,'skipValidation') && user.skipValidation)
    if ~isempty(control),sht_tc24_run_control('finish',control,'partial');end
    result.shortVerificationOnly=true;result.execution=session.finish('partial','prediction_not_requested',[],'completed_steps');return;
end
session.notify(struct('phase','UQ_D_prediction','status','running'));
result=sht_tc24_uq_validation_and_delivery(result);
if ~isempty(control),result.control=sht_tc24_run_control('finish',control,'completed');end
result.execution=session.snapshot('completed','uq_and_prediction_finished');
if ~isempty(session.directory),save(fullfile(session.directory,'result.mat'),'result','-v7.3');end
result.execution=session.finish('completed','uq_and_prediction_finished',result.execution);
catch err
    if strcmp(err.identifier,'TC24:Control:Stopped')
        result=struct('runId',cfg.runId,'method','D','status','stopped', ...
            'control',sht_tc24_run_control('state',session.directory));
        result.execution=session.finish('stopped',err.message,[],'safe_checkpoint_only');return;
    end
    if ~isempty(control),sht_tc24_run_control('finish',control,'failed');end
    session.finish('failed',[err.identifier,': ',err.message]);rethrow(err);
end
end
