function result=sht_tc27_steady_estimation(route,method,user)
%SHT_TC27_STEADY_ESTIMATION 三部件B/C/D确定性辨识，不调用TC24估计入口。
% I: 组内常值联合估计 -> 修正模型坐标上的绝对K曲线。
% II: 上游曲线保留/必要插点 -> 组内直接估计有关的节点绝对纵坐标。
% D0为联合稳态点微调，D1以D0为初值，加入全部测量识别的小幅历程。
% D的正则中心均为C曲线，D1初值不是新的独立先验。
options=sht_tc27_estimation_options(route,method,user);
fprintf('TC27 %s/%s: D0=%s, D1=%s, 辨识积分步长=%gs, 总目标小改善阈值=%g%%。\n', ...
    route,method,options.differenceD0,options.differenceD1,options.integrationStep_s, ...
    100*options.objectiveImprovementTolerance);
p=sht_tc27_paths(options);inputFile=fullfile(p.root,'MiddleData','three_component', ...
    'steady_model_2p4_delivery',['2p4_deterministic_',route,'.xlsx']);
if options.explicitInputs
    inputFile=char(string(options.upstreamModelFile));
    assert(isfile(inputFile),'TC27:Fit:UpstreamMissing','指定的上游模型Excel不存在：%s',inputFile);
end
delivery=sht_load_2p4_deterministic_delivery(route,inputFile,'formal');
loaded=load(fullfile(p.middle,'tc27_prepared_data.mat'),'result');prepared=loaded.result;
if options.explicitInputs
    assert(isfield(prepared,'inputFiles')&&strcmpi(prepared.inputFiles.steadyTrainingSHA256, ...
        sht_tc27_file_identity(char(string(options.steadyTrainingFile))))&& ...
        strcmpi(prepared.inputFiles.trainingHistorySHA256, ...
        sht_tc27_file_identity(char(string(options.trainingHistoryFile)))), ...
        'TC27:Fit:PreparedInputs','预处理的原训练点或新历程与本次指定文件不一致，请先重新运行05。');
    expected=[options.testPointFiles(:);options.testHistoryFiles(:)];
    actual={prepared.testSets.sourceFile}.';
    % 空cell也统一为0行1列；只统一形状，不改变来源次序或后续文件SHA校验。
    expected=expected(:);actual=actual(:);
    assert(isequal(expected,actual),'TC27:Fit:TestInputs', ...
        '验证文件列表与05阶段不同，不得改变本次测试来源。');
    for j=1:numel(expected)
        assert(strcmpi(prepared.testSets(j).sourceSHA256, ...
            sht_tc27_file_identity(expected{j})),'TC27:Fit:TestChanged', ...
            '测试文件在05阶段后变化：%s',expected{j});
    end
end
cfg=sht_tc27_config(options.thermalMode,'joint_full',p.runtime);engine=sht_engine_open(cfg.engine);cleanup=onCleanup(@()sht_engine_close(engine));
parameters=delivery.model.parameterDefinition;upstream=sht_tc27_schedule('refresh',delivery.model.finalSchedule);
thermalFile=p.thermalFile;if options.thermalMode==1,thermalFile=p.kurzkeFile;end
identity=struct('upstream',sht_tc27_file_identity(inputFile), ...
    'prepared',sht_tc27_file_identity(fullfile(p.middle,'tc27_prepared_data.mat')), ...
    'dll',sht_tc27_file_identity(fullfile(p.runtime,'GTESS.dll')), ...
    'thermal',sht_tc27_file_identity(thermalFile),'route',route,'method',method,'options',options);
identity.options.resume=[];identity.options.plot=[];identity.options.stopAfterC=[];
identity.options.runControl=[];
identity.execution=sht_tc27_execution_identity(cfg);
% 物理目标相同不代表算法检查点可续用；编码/兼容后端变化需新tag。
sourceFiles={'sht_tc27_steady_estimation.m','sht_tc27_regularized_solve.m', ...
    'sht_tc27_condition_diagnostics.m','sht_tc27_objective.m','sht_tc27_schedule.m','sht_tc27_replay.m', ...
    'sht_tc27_config.m','sht_tc27_estimation_options.m','sht_tc27_replay_histories.m', ...
    'sht_tc27_segment_history.m','sht_tc27_paths.m','Start_TC27_05_DataPreparation.m', ...
    'sht_tc27_validate_steady.m','sht_tc27_local_history_plan.m', ...
    'sht_tc27_local_history_objective.m','sht_tc27_prepared_history_objective.m','sht_tc27_final_jacobian_audit.m', ...
    'sht_steady_model_adapt_v2_common.m','sht_bounded_least_squares.m', ...
    'sht_thermal_equilibrium_solve.m','sht_load_engine_library.m'};
identity.algorithmSourceFiles=sourceFiles;
identity.runtimeBackend=struct('matlabRelease',version('-release'),'architecture',computer('arch'));
identity.algorithmSourceHashes=cellfun(@(name)sht_tc27_file_identity(fullfile(p.root,name)), ...
    sourceFiles,'UniformOutput',false);
% 边界数学规则改变后禁止把旧Jacobian/目标缓存当作同一辨识合同续跑。
identity.clearanceBoundaryPolicy='disabled';
if options.thermalMode~=0
    identity.clearanceBoundaryPolicy=cfg.engine.transientEffects.clearanceReferenceTable.PT.extrapolationPolicy;
    queryFiles={'sht_lookup_clearance_reference.m','sht_prepare_clearance_reference_lookup.m', ...
        'sht_clearance_hull_projection.m'};
    identity.clearanceQueryHashes=cellfun(@(name)sht_tc27_file_identity(fullfile(p.root,name)), ...
        queryFiles,'UniformOutput',false);
end
runId=sprintf('tc27_%s_%s_%s',options.tag,route,method);checkpoint=fullfile(p.middle,[runId,'_checkpoint.mat']);
result=struct('runId',runId,'identity',identity,'route',route,'method',method, ...
    'residualMethod','M0','modelMode',0,'thermalMode',options.thermalMode, ...
    'options',options,'parameterDefinition',parameters,'upstreamRunId',delivery.runId, ...
    'upstreamSchedule',upstream,'npBranchModel',delivery.npBranchModel, ...
    'hiddenTruthUsedForFit',false,'testUsedForFit',false,'completedStages',strings(0,1), ...
    'effectiveInputs',prepared.inputFiles,'testInputs',{prepared.testSets});
if options.runControlEnabled&&options.resume
    [prior,found]=sht_tc24_run_control('load',options.runControl,'Stage');
    if found
        assert(isequaln(prior.result.identity,identity),'TC27:Fit:CheckpointIdentity', ...
            '阶段检查点与当前数据、模型、源码或算法配置不一致。');
        result=prior.result;result.options=options;
        fprintf('恢复%s，已完成%s。\n',runId,strjoin(result.completedStages,','));
    end
elseif options.resume && exist(checkpoint,'file')
    old=load(checkpoint,'result');
    assert(isequaln(old.result.identity,identity),'TC27:Fit:CheckpointIdentity', ...
        '检查点与当前数据/DLL/配置不一致，请更改tag开始新运行，不得混用。');
    result=old.result;fprintf('恢复%s，已完成%s。\n',runId,strjoin(result.completedStages,','));
end
timer=tic;data=prepared.combinedSteady;source=prepared.source;groups=prepared.groupIndex;
if options.explicitInputs
    progressFile=fullfile(p.report,[runId,'_progress.csv']);
    if options.resume
        assert(isfile(progressFile),'TC27:Fit:ProgressMissing','续算缺少原进度日志：%s',progressFile);
        writeProgress('resumed','validated_upstream_and_prepared_inputs');
    else
        assert(~isfile(progressFile),'TC27:Fit:OutputExists','运行日志已存在，不覆盖：%s',progressFile);
        fid=fopen(progressFile,'w','n','UTF-8');fprintf(fid,'stage,detail,elapsed_s\n');fclose(fid);
        writeProgress('started','validated_upstream_and_prepared_inputs');
    end
end
if ~isfield(result,'baseline')&&~isempty(options.reusePointFitFile)
    % 显式导入不受本次历程初始化修改影响的B/C/D0成果，不重签旧检查点。
    previous=load(options.reusePointFitFile,'result');prior=previous.result;
    oldPreparedFile=fullfile(fileparts(options.reusePointFitFile),'tc27_prepared_data.mat');
    assert(strcmp(sht_tc27_file_identity(oldPreparedFile),prior.identity.prepared));
    oldPrepared=load(oldPreparedFile,'result');
    assert(isequaln(oldPrepared.result.combinedSteady,data)&&isequaln(oldPrepared.result.groupIndex,groups));
    assert(strcmp(prior.route,route)&&strcmp(prior.method,method)&&isfield(prior,'D0'));
    assert(isequaln(prior.identity.upstream,identity.upstream)&&isequaln(prior.identity.dll,identity.dll)&& ...
        isequaln(prior.identity.thermal,identity.thermal),'只允许同上游和同物理资产的点阶段结果复用。');
    stable={'thermalMode','maxIterationB','maxIterationD0','regularizationB','regularizationD', ...
        'retainedB','retainedD','lambdaD','steadySourceWeights','difference','differenceD0','objectiveImprovementTolerance'};
    for f=stable,assert(isequaln(prior.options.(f{1}),options.(f{1})),'点阶段配置%s不同。',f{1});end
    for f={'baseline','groups','groupIndex','groupResults','stageC','D0'},result.(f{1})=prior.(f{1});end
    result.completedStages=["baseline";"B/C";"D0"];
    result.pointStagesReusedFrom=sht_tc27_file_identity(options.reusePointFitFile);
    result.pointStagesOriginalIdentity=prior.identity;
    saveCheckpoint();
end
objectiveOptions=struct('route',route,'pointHistoryWeights',options.pointHistoryWeights, ...
    'steadySourceWeights',options.steadySourceWeights,'integrationStep_s',options.integrationStep_s);
contractOptions=delivery.model.options;contractOptions.stageDTikhonovPriorScale=1;
contractOptions.stageDDifferenceStepScale=.125;
if ~isfield(result,'baseline')
    result.baseline=sht_tc27_replay('points',cfg,engine,data,upstream,struct('route',route));
    assert(all(result.baseline.valid),'TC27:Fit:UpstreamReplay','上游调度新气热回放失败：%s', ...
        strjoin(cellstr(result.baseline.messages(~result.baseline.valid)),','));
    result.groups=prepared.groups;result.groupIndex=groups;
    result.groupResults=cell(prepared.groupCount,1);result.completedStages(end+1)="baseline";saveCheckpoint();
end
if strcmp(method,'II')
    template=sht_tc27_schedule('insertII',upstream,result.baseline.coordinates,data.Wf_mean,groups);
else,template=upstream;end
baseContract=sht_steady_model_adapt_v2_common('m3nodecontract',template,parameters,template.fuelBias.wfDesign,contractOptions);
basePrior=sht_steady_model_adapt_v2_common('m3priorcovariance',baseContract,contractOptions);
for g=1:prepared.groupCount
    if ~isempty(result.groupResults{g}),continue;end
    use=groups==g;groupData=data(use,:);groupCoordinates=result.baseline.coordinates(use,:);
    priorFactor=.75;if strcmp(route,'steady'),priorFactor=.35;end
    if nnz(use)>1,priorFactor=1;if strcmp(route,'steady'),priorFactor=.50;end,end
    [baseFun,~]=sht_tc27_objective(cfg,engine,groupData,source(use),[],baseContract,objectiveOptions);
    if strcmp(method,'I')
        values=sht_tc27_schedule('values',upstream,parameters,groupCoordinates,groupData.Wf_mean);
        initial=mean(values,1).';wf=upstream.fuelBias.wfDesign;
        center=initial;scale=[parameters.prior_sigma_group;.003*wf]*priorFactor;
        lower=[parameters.lower_bound;-.02*wf];upper=[parameters.upper_bound;.02*wf];
        step=[parameters.difference_step;max(1e-6,5e-5*wf)]*.125;
        fun=@constantObjective;
        active=(1:numel(initial)).';
        correlation=eye(numel(initial));
    else
        bounds=array2table([min(groupCoordinates{:,:},[],1);max(groupCoordinates{:,:},[],1)], ...
            'VariableNames',groupCoordinates.Properties.VariableNames);
        active=find(sht_tc27_schedule('support',baseContract,bounds, ...
            [min(groupData.Wf_mean),max(groupData.Wf_mean)]/template.fuelBias.wfDesign));
        initial=baseContract.centerVector(active);center=initial;scale=baseContract.priorSigma(active)*priorFactor;
        lower=baseContract.lowerBound(active);upper=baseContract.upperBound(active);step=baseContract.differenceStep(active);
        fun=@nodeObjective;
        correlation=basePrior.correlation(active,active);
    end
    solve=sht_tc27_regularized_solve(fun,initial,center,scale,lower,upper,step,struct( ...
        'method',options.regularizationB,'lambda',1,'retainedCount',options.retainedB, ...
        'difference',options.difference, ...
        'maxIterations',options.maxIterationB,'priorCorrelation',correlation,'label',sprintf('%s B%02d',runId,g)));
    if strcmp(method,'I'),gs=sht_tc27_schedule('constant',template,parameters,solve.x);
    else,z=baseContract.centerVector;z(active)=solve.x;gs=sht_steady_model_adapt_v2_common('m3nodestoschedule',baseContract,z);end
    replay=sht_tc27_replay('points',cfg,engine,groupData,gs,struct('route',route));
    result.groupResults{g}=struct('solve',solve,'active',active,'schedule',gs, ...
        'replay',replay,'pointIds',groupData.point_id,'priorScaleFactor',priorFactor);
    saveCheckpoint();
    if options.explicitInputs,writeProgress('B',sprintf('group_%d_of_%d',g,prepared.groupCount));end
end
if ~isfield(result,'stageC')
    if strcmp(method,'I')
        coordinates=result.baseline.coordinates;values=zeros(prepared.groupCount,height(parameters)+1);
        for g=1:prepared.groupCount
            gr=result.groupResults{g};values(g,:)=gr.solve.x.';
            coordinates(groups==g,:)=gr.replay.coordinates;
        end
        schedule=sht_tc27_schedule('constructI',upstream,parameters,coordinates,data.Wf_mean,groups,values);
    else
        total=zeros(baseContract.parameterCount,1);count=total;
        for g=1:prepared.groupCount
            gr=result.groupResults{g};total(gr.active)=total(gr.active)+gr.solve.x;count(gr.active)=count(gr.active)+1;
        end
        z=baseContract.centerVector;active=count>0;z(active)=total(active)./count(active);
        schedule=sht_steady_model_adapt_v2_common('m3nodestoschedule',baseContract,z);
    end
    result.stageC=struct('schedule',schedule,'globalUpdateFactorUsed',false, ...
        'ordinatePolicy','absolute_values','nodeCounts',arrayfun(@(e)numel(e.xNodes),schedule.healthEntries));
    result.completedStages(end+1)="B/C";saveCheckpoint();
    if options.explicitInputs,writeProgress('C','group_curves_constructed');end
end
if options.stopAfterC,return;end
contract=sht_steady_model_adapt_v2_common('m3nodecontract',result.stageC.schedule,parameters,upstream.fuelBias.wfDesign,contractOptions);
nodePrior=sht_steady_model_adapt_v2_common('m3priorcovariance',contract,contractOptions);
result.nodeContract=contract;
stages={'D0','D1'};
for k=1:2
    stage=stages{k};if isfield(result,stage),continue;end
    small=[];iterations=options.maxIterationD0;initial=contract.centerVector;
    difference=options.differenceD0;
    if k==2
        initial=result.D0.x;iterations=options.maxIterationD1;
        difference=options.differenceD1;
        if options.includeSmallHistory,small=prepared.train.small;end
        % 若用户关闭历程，第二轮仍是纯工况点目标，沿用D0的差分设置。
        if isempty(small),difference=options.differenceD0;end
    end
    dOptions=objectiveOptions;
    if strcmp(route,'steady')
        dOptions.pointInitialReplay=struct('states',result.baseline.states, ...
            'commonWorkingSeed',result.baseline.commonWorkingSeed);
        result.steadyRootInitialization='upstream_same_point_root_with_valid_candidate_warm_start';
    end
    factory=[];
    if ~isempty(small)
        [small,localPlan]=sht_tc27_local_history_plan(small,options.localWarmup_s);
        [funD,preparedFactory,statsD]=sht_tc27_local_history_objective(cfg,engine,data,source,small,contract,dOptions);
        result.localPreparationPlan=localPlan;
        if options.reusePreparationForJacobian,factory=preparedFactory;end
    else,[funD,statsD]=sht_tc27_objective(cfg,engine,data,source,small,contract,dOptions);end
    initialPolicy='C_schedule';
    if k==2
        initialPolicy='D_points_result';[~,initialMeta]=funD(initial);
        if ~initialMeta.valid
            % 点工况解可能不适于完整积分。选择已验证的C结果作为新求解
            % 初值，不改变正则中心、不缩放参数，也不把失效历程丢掉。
            warning('TC27:Fit:HistoryInitial','稳态点解不能回放全部历程：%s。改用C曲线启动混合目标。',strjoin(initialMeta.messages,'; '));
            initial=contract.centerVector;[~,centerMeta]=funD(initial);
            assert(centerMeta.valid,'C曲线也不能回放完整混合目标：%s',strjoin(centerMeta.messages,'; '));
            initialPolicy='C_schedule_after_invalid_D_points_history';
            result.mixedInitialFailure=initialMeta;
        end
    end
    fprintf('%s %s: %d自由纵坐标，%d稳态点，%d小幅历程，lambda=%g。\n', ...
        runId,stage,contract.parameterCount,height(data),numel(small),options.lambdaD);
    solve=sht_tc27_regularized_solve(funD,initial,contract.centerVector,contract.priorSigma, ...
        contract.lowerBound,contract.upperBound,contract.differenceStep, ...
        struct('method',options.regularizationD,'lambda',options.lambdaD, ...
        'difference',difference,'objectiveImprovementTolerance',options.objectiveImprovementTolerance, ...
        'retainedCount',options.retainedD,'maxIterations',iterations,'label',[runId,' ',stage], ...
        'checkpointFile',fullfile(p.middle,[runId,'_',stage,'_iteration.mat']), ...
        'inputIdentity',identity,'priorCorrelation',nodePrior.correlation, ...
        'differenceContextFactory',factory,'runControl',options.runControl, ...
        'runControlKey',[stage,'Iteration']));
    if ~isempty(factory)
        solve.exactJacobianAudit=sht_tc27_final_jacobian_audit(funD,solve,contract.differenceStep, ...
            contract.lowerBound,contract.upperBound);
    end
    solve.initialPolicy=initialPolicy;solve.cacheStatistics=statsD();result.(stage)=solve;result.completedStages(end+1)=string(stage);saveCheckpoint();
    if options.explicitInputs,writeProgress(stage,char(string(solve.stopReason)));end
end
result.finalSchedule=sht_steady_model_adapt_v2_common('m3nodestoschedule',contract,result.D1.x);
% 兼容本批早期检查点的停止标签，不改变任何已接受参数或数值结果。
for k=1:numel(stages)
    s=result.(stages{k});passed=s.history.projectedGradient(end)<s.options.gradientTolerance;
    if ~isfield(s,'frozenPreparationJacobian')||~s.frozenPreparationJacobian
        s.firstOrderStationarityPassed=passed;
    end
    if s.converged&&s.stopReason=="fresh_jacobian_stationarity"&&~passed
        stable=s.history.previousMove(end)<s.options.stepTolerance&&height(s.history)>1&& ...
            abs(diff(s.history.totalCost(end-1:end)))/max(1,s.history.totalCost(end-1))<s.options.costTolerance;
        if stable,s.stopReason="fresh_jacobian_small_step_and_cost";
        else,s.stopReason="legacy_stop_label_requires_review";s.converged=false;end
        s.stopLabelAudited=true;
    end
    result.(stages{k})=s;
end
if ~isfield(result,'fitElapsedFirstCompletedInvocation_s')
    if isfield(result,'fitElapsedThisInvocation_s')
        result.fitElapsedFirstCompletedInvocation_s=result.fitElapsedThisInvocation_s;
    else,result.fitElapsedFirstCompletedInvocation_s=toc(timer);end
end
result.fitElapsedThisInvocation_s=toc(timer);result.completedStages(end+1)="deterministic_fit";
saveCheckpoint();
% 验证仅在估计冻结之后读取测试集，另一个函数负责隔离真值评估。
if ~isfield(result,'validation')
    result=sht_tc27_validate_steady(result,cfg,engine,prepared,options);
    if options.explicitInputs,writeProgress('validation','training_and_optional_test_results');end
    save(fullfile(p.middle,[runId,'_result.mat']),'result','-v7.3');
    saveCheckpoint();
end
if options.explicitInputs,writeProgress('completed',char(string(result.D1.stopReason)));end
    function [r,m]=constantObjective(z)
        s=sht_tc27_schedule('constant',template,parameters,z);
        full=sht_steady_model_adapt_v2_common('m3scheduletonodes',baseContract,s);[r,m]=baseFun(full);
        % B的常值参数不对应全曲线逐节点编号，保留原有完整中心差分。
        m=rmfield(m,'jacobianBlocks');
    end
    function [r,m]=nodeObjective(z)
        full=baseContract.centerVector;full(active)=z;[r,m]=baseFun(full);
        % B只优化组内active子集，不能把全局支撑掩码直接按局部列索引。
        m=rmfield(m,'jacobianBlocks');
    end
    function saveCheckpoint()
        if options.runControlEnabled
            state=struct('result',result,'progress',struct( ...
                'completedStages',{cellstr(result.completedStages)}, ...
                'completedGroups',nnz(~cellfun(@isempty,result.groupResults))));
            sht_tc24_run_control('boundary',options.runControl,'Stage',state);
        else
            save(checkpoint,'result','-v7.3');
        end
    end
    function writeProgress(stage,detail)
        fid=fopen(progressFile,'a','n','UTF-8');
        assert(fid>0,'TC27:Fit:ProgressFile','不能写入运行进度：%s',progressFile);
        fprintf(fid,'%s,%s,%.6f\n',stage,regexprep(detail,'[,\r\n]','_'),toc(timer));
        fclose(fid);
    end
end
