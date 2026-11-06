function result=Start_TC24_07_UncertaintyAssessment(method,user)
% TC24-STEP07：稳态模型/瞬态时刻模型推断，独立重新测量的稳态输出预测。
% lastStep用于分阶段运行；须完成后处理才能生成完整诊断、预测与Excel交付。
entry=struct('timer',tic,'startedAt',datestr(now,30), ...
    'entryPoint',mfilename,'displayName','UQ评估入口耗时');
if nargin<1,method='B';end
if nargin<2,user=struct();end
sht_r2019b_preflight();
method=upper(char(method));assert(ismember(method,{'B','C','D'}),'只能选择B、C或D。');
if strcmp(method,'D'),result=Start_TC24_07D_QuickAssessment(user,entry);return;end
cfg=user;
if strcmp(method,'B'),cfg=sht_tc24_b_config(user);end
cfg.modelMode=0;
cfg=sht_tc24_uq_business_inputs(cfg,user);
if ~isfield(cfg,'runtimeDirectory')
    package=sht_tc24_runtime_package();cfg.runtimeDirectory=package.directory;
end
if strcmp(method,'B')
    % 数值默认只在集中配置维护，界面与独立运行不得各设一套预算。
    runners={@Start_SteadyModelUQ_B_01_ProblemContract, ...
        @Start_SteadyModelUQ_B_02_ExactStaticReplayAndCache, ...
        @Start_SteadyModelUQ_B_03_ObservationVector, ...
        @Start_SteadyModelUQ_B_04_AnalyticMeasurementUncertainty, ...
        @Start_SteadyModelUQ_B_05_ExactLikelihoodVerification, ...
        @Start_SteadyModelUQ_B_06_GlobalExactPilot, ...
        @Start_SteadyModelUQ_B_07_DefensiveProposalAdaptation, ...
        @Start_SteadyModelUQ_B_08_BlockExactPosteriorSampling, ...
        @Start_SteadyModelUQ_B_09_PosteriorDiagnostics};
    io=@sht_steady_model_uq_b_io;
else
    if ~isfield(cfg,'formalSampleCount'),cfg.formalSampleCount=512;end
    % 用户选定R042：校核后的附加参数参考点，不退回早期two_anchor设置。
    if ~isfield(cfg,'nuisanceAnchorMode'),cfg.nuisanceAnchorMode='map_checked';end
    % TC27 R073采样原则接入TC24；R042附加参数矩似然保持不变。
    % 用户可显式缩小预算作同预算对照；512和6/32不是统计精度保证。
    if ~isfield(cfg,'cSamplerProfile'),cfg.cSamplerProfile='quality';end
    if ~isfield(cfg,'formalMoveSweeps'),cfg.formalMoveSweeps=6;end
    if ~isfield(cfg,'formalFinalMoveSweeps'),cfg.formalFinalMoveSweeps=32;end
    if ~isfield(cfg,'kernelWeights'),cfg.kernelWeights=[.1,.1,.1,.1,.6];end
    if ~isfield(cfg,'globalPcnFraction'),cfg.globalPcnFraction=.9;end
    if ~isfield(cfg,'initialPcnScale'),cfg.initialPcnScale=.7*ones(1,5);end
    if ~isfield(cfg,'minimumPcnScale'),cfg.minimumPcnScale=1e-6*ones(1,5);end
    if ~isfield(cfg,'maximumPcnScale'),cfg.maximumPcnScale=.95*ones(1,5);end
    cfg=local_c_sampling_config(cfg);
    runners={@Start_SteadyModelUQ_C_01_ProblemContract, ...
        @Start_SteadyModelUQ_C_02_NuisanceMarginalization, ...
        @Start_SteadyModelUQ_C_03_ProposalGeometry, ...
        @Start_SteadyModelUQ_C_04_BlockPilot, ...
        @Start_SteadyModelUQ_C_05_FormalPosterior};
    io=@sht_steady_model_uq_c_io;
end
if ~isfield(cfg,'runId') || isempty(cfg.runId)
    cfg.runId=['tc24_',lower(method),'_',datestr(now,'yyyymmdd_HHMMSS')];
end
assert(startsWith(cfg.runId,'tc24_'),'TC24运行标识必须以前缀tc24_隔离。');
last=numel(runners);if isfield(user,'lastStep'),last=min(last,user.lastStep);end
first=1;if isfield(user,'firstStep'),first=user.firstStep;end
validateattributes(first,{'numeric'},{'scalar','integer','positive','<=',last});
eventOptions=cfg;eventOptions.firstStep=first;
trainingCount=height(sht_tc24_validate_measurements(cfg.trainingFile));
testCount=0;
if ~isempty(cfg.testFile)
    testCount=height(sht_tc24_validate_measurements(cfg.testFile));
end
eventOptions.runtimeEstimate=sht_tc24_fixed_runtime_estimate( ...
    ['uq_',method],cfg,trainingCount,testCount);
if isfield(cfg,'timingHistoryDirectory')&&~isempty(cfg.timingHistoryDirectory)
    eventOptions.timingQuery=sht_tc24_runtime_estimate('query',cfg,['uq_',method]);
end
if isfield(user,'progressCallback'),eventOptions.progressCallback=user.progressCallback;end
session=sht_tc24_execution(eventOptions,['uq_',method],entry);
control=[];
try
proposalPreparation=struct('mode','not_applicable','runtimeSeconds',0);
if strcmp(method,'B')
    % D只帮助找到提议位置，不替换B的先验、似然或数据合同。
    session.notify(struct('phase','UQ_B_proposal_preparation','status','running'));
    proposalUser=cfg;
    proposalUser.progressCallback=@(event)session.notify(struct( ...
        'phase',['UQ_B_proposal_',event.phase],'status',event.status, ...
        'childRunId',event.runId,'childEvent',event));
    [cfg,proposalPreparation]=sht_tc24_prepare_b_proposal(cfg,proposalUser);
    if isfield(proposalPreparation,'stopped')&&proposalPreparation.stopped
        result=struct('runId',cfg.runId,'method',method,'status','stopped', ...
            'proposalPreparation',proposalPreparation, ...
            'control',proposalPreparation.childResult.control);
        result.execution=session.finish('stopped','D_proposal_preparation_safe_stop',[],'safe_checkpoint_only');
        return;
    end
end
if isfield(cfg,'enableRunControl')&&cfg.enableRunControl
    assert(~isempty(session.directory),'TC24:Control:Output','UQ安全停止需独立输出目录。');
    if strcmp(method,'B'),common=@sht_steady_model_uq_b_common;else,common=@sht_steady_model_uq_c_common;end
    current=common('buildcontract',common('defaultconfig',cfg));
    identity=sht_tc24_uq_external_io(lower(method),'controlidentity',cfg,current);
    co=struct('directory',session.directory,'runId',cfg.runId,'resume',false, ...
        'timer',session.timer,'sessionStartDatenum',session.sessionStartDatenum,'sessionToken',session.sessionToken);
    if isfield(user,'resume'),co.resume=logical(user.resume);end
    if co.resume && strcmp(method,'B') && ...
            ~isfile(fullfile(session.directory,'run_control','identity.mat'))
        % 外层停止在D准备时，B尚未建立控制身份；只能从本任务停止记录恢复。
        previousFile=fullfile(session.directory,'execution.json');
        assert(isfile(previousFile),'TC24:Control:Missing','未找到本批安全停止记录。');
        previousExecution=jsondecode(fileread(previousFile));
        assert(strcmp(previousExecution.status,'stopped') && ...
            strcmp(previousExecution.stopReason,'D_proposal_preparation_safe_stop'), ...
            'TC24:Control:Missing','只有本批D准备安全停止才允许首次创建B控制身份。');
        co.resume=false;
    end
    control=sht_tc24_run_control('open',co,identity);cfg.runControl=control;
    session.notify(struct('phase','run_identity_verified','status','running'));
    [pipeline,found]=sht_tc24_run_control('load',control,'uq_pipeline');
    if found,first=pipeline.nextStep;end
elseif first>1
    assert(isfield(user,'runId'),'续跑必须明确指定原runId。');
    frozen=io('loadstep',io('resolve',cfg),1);
    names=fieldnames(user);
    for j=1:numel(names)
        name=names{j};
        if ismember(name,{'runId','firstStep','lastStep','progressCallback'}),continue;end
        assert(isfield(frozen.contract.config,name) && isequaln(user.(name),frozen.contract.config.(name)), ...
            'TC24:UQ:ResumeConfigurationConflict','续跑配置%s与已冻结配置不同；请新建runId。',name);
    end
    cfg=frozen.contract.config;
    if strcmp(method,'C'),cfg=local_c_sampling_config(cfg);end
    if strcmp(method,'B'),common=@sht_steady_model_uq_b_common;else,common=@sht_steady_model_uq_c_common;end
    current=common('buildcontract',cfg);
    assert(strcmp(current.contractHash,frozen.contract.contractHash), ...
        'TC24:UQ:ChangedContract','输入、模型或参数合同已改变，不能续用旧步骤。');
end
timer=tic;steps=cell(last,1);
if ~isempty(control)&&first>1
    previous=io('resolve',cfg);
    for k=1:min(first-1,last),steps{k}=io('loadstep',previous,k);end
end
for k=first:last
    if ~isempty(control),sht_tc24_run_control('boundary',control,'uq_pipeline',struct('nextStep',k));end
    session.notify(struct('phase',sprintf('UQ_%s_step_%02d',method,k), ...
        'status','running','step',k,'stepCount',numel(runners),'fraction',NaN));
    steps{k}=runners{k}(cfg);
    if ~isempty(control),sht_tc24_run_control('boundary',control,'uq_pipeline',struct('nextStep',k+1));end
    fprintf('TC24-UQ-%s: step %d/%d finished, %.1f s elapsed.\n',method,k,last,toc(timer));
end
manifest=io('resolve',cfg);
result=struct('runId',cfg.runId,'method',method,'steps',{steps},'manifest',manifest, ...
    'runtime_s',toc(timer),'shortVerificationOnly',last<numel(runners));
result.config=cfg;
result.proposalPreparation=proposalPreparation;
if strcmp(method,'B'),result.implementationVersion=cfg.bConfigurationVersion;end
if result.shortVerificationOnly
    if ~isempty(control),sht_tc24_run_control('finish',control,'partial');end
    result.execution=session.finish('partial','requested_last_step',[],'completed_steps');
    fprintf('TC24 UQ分阶段运行结束于第%d步；尚未生成完整后验交付。\n',last);return;
end
% 测试集只用于估计完成后的预测评价；隐藏真值只在显式隔离验证时启用。
result=sht_tc24_uq_validation_and_delivery(result);
if ~isempty(control),result.control=sht_tc24_run_control('finish',control,'completed');end
result.execution=session.snapshot('completed','uq_and_prediction_finished');
if ~isempty(session.directory),save(fullfile(session.directory,'result.mat'),'result','-v7.3');end
result.execution=session.finish('completed','uq_and_prediction_finished',result.execution);
catch err
    if strcmp(err.identifier,'TC24:Control:Stopped')
        result=struct('runId',cfg.runId,'method',method,'status','stopped', ...
            'control',sht_tc24_run_control('state',session.directory));
        result.execution=session.finish('stopped',err.message,[],'safe_checkpoint_only');return;
    end
    if ~isempty(control),sht_tc24_run_control('finish',control,'failed');end
    session.finish('failed',[err.identifier,': ',err.message]);rethrow(err);
end
end

function cfg=local_c_sampling_config(cfg)
% 仅补齐C采样的可恢复配置，不丢弃输出、回调或其他业务选项。
checked=sht_steady_model_uq_c_common('defaultconfig',cfg);
names={'cSamplerProfile','cConditionalEssFraction','cResampleEssFraction', ...
    'cReferenceShrinkage','cReferenceEigenvalueFloor','cSamplingSeed','cMoveReferenceHash'};
for k=1:numel(names),cfg.(names{k})=checked.(names{k});end
end
