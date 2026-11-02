function result=Start_TC27_07_TransientParameterEstimation(route,method,options)
%START_TC27_07_TRANSIENTPARAMETERESTIMATION 零初值、零中心正则的13方向正式辨识。
% full_history为默认；event_windows包含前平台和恢复段，不仅拟合快速核心。
% 不再执行独立快速初值。释放预检为独立入口，不改变已确认的h58:h70。
if nargin<1||isempty(route),route='transient_instant';end
if nargin<2||isempty(method),method='II';end
if nargin<3,options=struct();end
defaults=struct('lambda',.1,'priorScale',.3,'maxIterations',6,'differenceStep',.01, ...
    'resume',true,'plot',true,'tag','R021','outputBatch','TC27_R021_LocalPrepared', ...
    'dataScope','full_history','integrationStep_s',.1,'validationIntegrationStep_s',.025, ...
    'objectiveImprovementTolerance',1e-3,'steadyFile','','localWarmup_s',60, ...
    'reusePreparationForJacobian',true,'preparedFile','','runtimeDirectory','selected', ...
    'trainingHistoryFile','','testHistoryFiles',{{}},'runControl',[], ...
    'validateTruth',false,'saveTrainingPrediction',false);
f=fieldnames(defaults);for j=1:numel(f),if ~isfield(options,f{j}),options.(f{j})=defaults.(f{j});end,end
assert(ismember(route,{'steady','transient_instant'})&&ismember(method,{'I','II'}));
assert(ismember(options.integrationStep_s,[.1,.025])&&ismember(options.validationIntegrationStep_s,[.1,.025]));
p=sht_tc27_paths(options);file=options.steadyFile;
if isempty(file),file=fullfile(p.middle,['tc27_deterministic_',route,'_',method,'.xlsx']);end
steady=sht_tc27_delivery('read',[],file);schedule=steady.finalSchedule;
assert(steady.thermalMode==3,'瞬态参数辨识要求标称Visser稳态结果。');
preparedFile=options.preparedFile;
if isempty(preparedFile),preparedFile=fullfile(p.middle,'tc27_prepared_data.mat');end
loaded=load(preparedFile,'result');prepared=loaded.result;
if ~isempty(options.trainingHistoryFile)
    assert(strcmpi(sht_tc27_file_identity(options.trainingHistoryFile), ...
        prepared.inputFiles.trainingHistorySHA256), ...
        'TC27:Transient:StaleTraining','训练Excel与准备结果不一致。');
    assert(isequaln(readtable(options.trainingHistoryFile),prepared.train.data), ...
        'TC27:Transient:StaleTraining','训练记录与准备结果不一致。');
    assert(strcmpi(sht_tc27_file_identity(file),prepared.inputFiles.steadyModelSHA256), ...
        'TC27:Transient:StaleModel','稳态模型与准备结果不一致。');
else
    input=struct('trainingHistoryFile',prepared.inputFiles.trainingHistory, ...
        'steadyTrainingFile',prepared.inputFiles.steadyTraining);
    input.testPointFiles={};input.testHistoryFiles={};
    if isfield(prepared,'testSets')
        input.testPointFiles={prepared.testSets.sourceFile};
    end
    sht_tc27_uq_check_prepared_data(input,prepared,'train');
end
plan=sht_tc27_transient_plan(prepared.train,options.dataScope);
[plan,localPlan]=sht_tc27_local_history_plan(plan,options.localWarmup_s);
cfg=sht_tc27_config(3,'joint_full',options.runtimeDirectory);
timer=tic;
runId=['tc27_transient_',options.tag,'_',route,'_',method,'_',options.dataScope];
checkpoint=fullfile(p.middle,[runId,'_checkpoint.mat']);
trainingFile=p.trainingFile;
if ~isempty(options.trainingHistoryFile),trainingFile=options.trainingHistoryFile;end
identity=struct('steady',steady.sha256,'training',sht_tc27_file_identity(trainingFile), ...
    'prepared',sht_tc27_file_identity(preparedFile), ...
    'execution',sht_tc27_execution_identity(cfg),'options',options);
identity.options.resume=[];identity.options.plot=[];
identity.options.runControl=[];
code={'Start_TC27_07_TransientParameterEstimation.m','sht_tc27_segment_history.m', ...
    'sht_tc27_transient_plan.m','sht_tc27_replay_histories.m','sht_tc27_replay.m', ...
    'sht_tc27_regularized_solve.m','sht_tc27_condition_diagnostics.m','sht_tc27_config.m','sht_tc27_local_history_plan.m', ...
    'sht_tc27_prepared_history_objective.m','sht_tc27_final_jacobian_audit.m'};
identity.code=cellfun(@(n)sht_tc27_file_identity(fullfile(p.root,n)),code,'UniformOutput',false);
names=["K_Jg";"K_Jp";"K_tau_HPC";"K_tau_Burner";"K_tau_GT";"K_tau_PT"; ...
    "K_gapW_HPC";"K_gapEta_HPC";"K_gapEta_GT";"K_gapEta_PT"; ...
    "K_diskTau_HPC";"K_diskTau_GT";"K_diskTau_PT"];
result=struct('runId',runId,'identity',identity,'options',options,'steadyDelivery',steady, ...
    'names',names,'hIndex',(58:70).','priorCenter',zeros(13,1),'initial',zeros(13,1), ...
    'fullInitialPolicy','zero_direct_formal','hiddenTruthUsedForFit',false, ...
    'quickInitializationExecuted',false,'releasePrecheckRequired',false,'active',(1:13).');
result.regularization=struct('definition','0.5*lambda^2*sum((h/priorScale)^2)', ...
    'lambda',options.lambda,'actualStandardizedWeight',options.lambda^2, ...
    'physicalDiagonalPrecision',options.lambda^2/options.priorScale^2);
result.fitSampleCount=sum(arrayfun(@(q)height(q.data),plan));
result.integrationSampleCount=sum(arrayfun(@(q)height(q.replayData),plan));
result.localPreparationPlan=localPlan;
if options.resume&&isfile(checkpoint)
    old=load(checkpoint,'result');
    assert(isequaln(old.result.identity,identity),'TC27:Transient:Identity','检查点不同，不得改签。');
    result=old.result;
end
if ~options.resume
    assert(~isfile(checkpoint)&&~isfile(fullfile(p.middle,[runId,'_iteration.mat'])), ...
        'TC27:Transient:ExistingCheckpoint', ...
        '已有旧检查点；新任务请使用独立目录，或按同一身份显式续算。');
end
engine=sht_engine_open(cfg.engine);
cleanup=onCleanup(@()sht_engine_close(engine));
[objective,factory,statistics]=sht_tc27_prepared_history_objective(cfg,engine,plan,schedule, ...
    struct('parameterKind','transient_coefficients','historyWeighting','all_samples', ...
    'integrationStep_s',options.integrationStep_s));
if ~options.reusePreparationForJacobian,factory=[];end
fprintf('%s: %d拟合样本，%d积分记录，dt=%g，lambda=%g，实际权重lambda^2=%g。\n', ...
    runId,result.fitSampleCount,result.integrationSampleCount,options.integrationStep_s, ...
    options.lambda,options.lambda^2);
if ~isfield(result,'solve')
    solveOptions=struct('method','tikhonov','lambda',options.lambda, ...
        'difference','forward','maxIterations',options.maxIterations, ...
        'objectiveImprovementTolerance',options.objectiveImprovementTolerance,'label',runId, ...
        'inputIdentity',identity,'differenceContextFactory',factory);
    if ~isempty(options.runControl)
        solveOptions.runControl=options.runControl;solveOptions.runControlKey='transient_solve';
    else
        solveOptions.checkpointFile=fullfile(p.middle,[runId,'_iteration.mat']);
    end
    solve=sht_tc27_regularized_solve(objective,zeros(13,1),zeros(13,1), ...
        options.priorScale*ones(13,1),-.5*ones(13,1),ones(13,1), ...
        options.differenceStep*ones(13,1),solveOptions);
    if ~isempty(factory)
        solve.exactJacobianAudit=sht_tc27_final_jacobian_audit(objective,solve, ...
            options.differenceStep*ones(13,1),-.5*ones(13,1),ones(13,1));
    end
    result.solve=solve;result.estimate=solve.x;
    result.fitStatistics=statistics();result.fitDllEvaluationCount=result.fitStatistics.historyDllCalls;
    result.fitHistoryReplayCount=result.fitStatistics.fullHistoryRuns+result.fitStatistics.frozenFitRuns;
    result.fitWallTime_s=toc(timer);saveCheckpoint();
end
% 已选训练段必须保存观测与最终拟合曲线；打开结果不触发DLL。
report=fullfile(p.report,runId);
if ~isfolder(report),mkdir(report);end
result.trainingPredictions={};result.trainingBaselinePredictions={};
result.trainingMetrics=table();result.trainingBaselineMetrics=table();
if options.saveTrainingPrediction
    % 基准仅关闭十三项瞬态修正；父稳态调度和燃油偏置保持原值。
    baseline=sht_tc27_replay_histories(cfg,engine,plan,schedule, ...
        struct('transientHealth',zeros(13,1),'integrationStep_s',options.integrationStep_s));
    if all(result.estimate==0)
        rr=baseline;
    else
        rr=sht_tc27_replay_histories(cfg,engine,plan,schedule, ...
            struct('transientHealth',result.estimate,'integrationStep_s',options.integrationStep_s));
    end
    prediction=table();baselinePrediction=table();observed=table();
    for j=1:numel(rr)
        fit=rr{j}.prediction;source=plan(j).data;
        steadyOnly=baseline{j}.prediction;
        valuesFit=fit{:,:};valuesBaseline=steadyOnly{:,:};
        assert(rr{j}.valid&&baseline{j}.valid&& ...
            height(fit)==height(source)&&height(steadyOnly)==height(source)&& ...
            all(isfinite(valuesFit(:)))&&all(isfinite(valuesBaseline(:))), ...
            'TC27:Transient:InvalidTrainingPrediction', ...
            '训练选段存在无效物理预测，不能标记为可交付模型。');
        prediction=[prediction;fit];baselinePrediction=[baselinePrediction;steadyOnly]; %#ok<AGROW>
        observed=[observed;source]; %#ok<AGROW>
        curve=table(source.Time_s,repmat(string(plan(j).id),height(source),1), ...
            'VariableNames',{'Time_s','segment'});
        channels={'Np','Ng','Ptb3','Ttb3','Pt45','Tt45','Pt6','Tt6'};
        for c=1:numel(channels)
            name=channels{c};curve.(['measured_',name])=source.(name);
            curve.(['steady_only_',name])=steadyOnly.(name);
            curve.(['predicted_',name])=fit.(name);
        end
        curve.measured_Wa2=source.Wa1-source.Wb;
        curve.steady_only_Wa2=steadyOnly.Wa2;curve.predicted_Wa2=fit.Wa2;
        writetable(curve,fullfile(report,sprintf('training_fit_%02d.csv',j)));
    end
    result.trainingPredictions=rr;
    result.trainingBaselinePredictions=baseline;
    result.baselineDllEvaluationCount=local_unique_replay_calls(baseline);
    result.reusedBaselinePrediction=all(result.estimate==0);
    result.estimatedTrainingDllEvaluationCount=0;
    if ~result.reusedBaselinePrediction
        result.estimatedTrainingDllEvaluationCount=local_unique_replay_calls(rr);
    end
    result.trainingValid=true;
    result.trainingBaselineMetrics=sht_tc27_output_metrics( ...
        baselinePrediction,observed,false,'training_steady_only');
    result.trainingMetrics=sht_tc27_output_metrics(prediction,observed,false,'training_estimated');
    writetable(result.trainingBaselineMetrics,fullfile(report,'training_steady_only_metrics.csv'));
    writetable(result.trainingMetrics,fullfile(report,'training_output_metrics.csv'));
end
% 新业务允许无测试集；测试集只用于独立验证，不进入参数更新。
testRecords={};
if ~isempty(options.trainingHistoryFile)
    assert(numel(options.testHistoryFiles)==numel(prepared.testRecords), ...
        'TC27:Transient:Tests','测试文件个数与准备结果不一致。');
    for j=1:numel(options.testHistoryFiles)
        assert(strcmpi(sht_tc27_file_identity(options.testHistoryFiles{j}), ...
            prepared.testFiles(j).sha256),'TC27:Transient:StaleTest', ...
            '测试Excel在准备后已改变。');
        testRecords{j}=prepared.testRecords(j); %#ok<AGROW>
    end
else
    sht_tc27_uq_check_prepared_data(input,prepared,'test');
    if isfield(prepared,'test'),testRecords={prepared.test};end
end
values={zeros(13,1),result.estimate};labels={'nominal','estimated'};
result.testPredictions=cell(numel(testRecords),2);metrics=table();
result.testValidationStatus='not_provided';
for t=1:numel(testRecords)
    testPlan=sht_tc27_transient_plan(testRecords{t},'full_history');
    for k=1:2
        rr=sht_tc27_replay_histories(cfg,engine,testPlan,schedule, ...
            struct('transientHealth',values{k},'integrationStep_s',options.validationIntegrationStep_s));
        prediction=table();observed=table();
        for j=1:numel(rr)
            prediction=[prediction;rr{j}.prediction];observed=[observed;testPlan(j).data]; %#ok<AGROW>
        end
        result.testPredictions{t,k}=rr;
        q=sht_tc27_output_metrics(prediction,observed,false,sprintf('test_%02d_%s',t,labels{k}));
        metrics=[metrics;q]; %#ok<AGROW>
    end
end
if ~isempty(testRecords)
    result.testValidationStatus='complete';
    if any(metrics.validSampleCount<metrics.totalSampleCount) || ...
            any(~isfinite(metrics.RMSE))
        result.testValidationStatus='invalid_prediction';
    end
end
trueValues=nan(13,1);truthFile=fullfile(p.legacyMiddle,'tc27_train_validation.mat');
if options.validateTruth&&isfile(truthFile)
    truth=load(truthFile,'output');trueValues=truth.output.transientTruth.truth;
end
result.parameterComparison=table(result.hIndex,names,trueValues,result.initial,result.estimate, ...
    result.estimate-trueValues,'VariableNames',{'hIndex','parameter','truth','initial','estimate','estimateError'});
result.parameterRMSE=sqrt(mean((result.estimate-trueValues).^2));
result.testMetrics=metrics;result.elapsedThisInvocation_s=toc(timer);
writetable(result.parameterComparison,fullfile(report,'all_transient_parameter_comparison.csv'));
if ~isempty(metrics),writetable(metrics,fullfile(report,'complete_test_output_metrics.csv'));end
delivery=table(result.hIndex,names,result.estimate,'VariableNames',{'hIndex','parameter','value'});
result.deliveryFile=fullfile(p.middle,['tc27_transient_',route,'_',method,'_',options.dataScope,'.xlsx']);
[~,steadyName,ext]=fileparts(steady.file);
manifest=table(string(runId),0,3,string([steadyName,ext]),string(steady.sha256), ...
    'VariableNames',{'run_id','model_mode','thermal_mode','steady_workbook','steady_sha256'});
published=sht_tc27_transient_delivery('write',struct('parameters',delivery,'manifest',manifest),result.deliveryFile);
result.deliverySHA256=published.sha256;
disp(result.parameterComparison);disp(metrics);
if options.plot
    f=figure('Name','TC27 transient parameters','Position',[80,80,1400,550]);
    if all(isfinite(trueValues)),bar([trueValues,result.estimate]);
    else,bar(result.estimate);end
    grid on;
    set(gca,'XTick',1:13,'XTickLabel',cellstr(names),'TickLabelInterpreter','none');xtickangle(35);
    if all(isfinite(trueValues)),legend('Truth (validation only)','Estimate');
    else,legend('Estimate');end
    ylabel('Correction coefficient');
    print(f,fullfile(report,'all_transient_parameters.png'),'-dpng','-r140');
end
save(fullfile(p.middle,[runId,'_result.mat']),'result','-v7.3');saveCheckpoint();
    function saveCheckpoint(),save(checkpoint,'result','-v7.3');end
end

function calls=local_unique_replay_calls(replays)
% 同一连续块的多个拟合事件可共用一次物理历程，DLL调用只计一次。
if isempty(replays),calls=0;return;end
shared=cellfun(@(q)q.sharedReplay,replays);
[~,first]=unique(shared,'stable');
calls=sum(cellfun(@(q)q.dllEvaluationCount,replays(first)));
end
