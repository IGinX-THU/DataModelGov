function result=sht_tc27_validate_steady(result,cfg,engine,prepared,options)
%SHT_TC27_VALIDATE_STEADY 拟合冻结后的两套稳态测试与全部小幅测试。
% 无论拟合是哪条路径，稳态工况预测均重新求完整稳态气热平衡。
% 测试不反向选择方法/正则化，不设置两批数据联合5%门槛。
p=sht_tc27_paths(options);tag=result.runId;reportDir=fullfile(p.report,tag);
if ~isfolder(reportDir),mkdir(reportDir);end
sets=prepared.testSets;
schedules={result.upstreamSchedule,result.stageC.schedule, ...
    sht_steady_model_adapt_v2_common('m3nodestoschedule',result.nodeContract,result.D0.x),result.finalSchedule};
labels={'TC24','C','D_points','D_mixed'};summary=table();steady=cell(numel(sets),4);
for j=1:numel(sets)
    if height(sets(j).means)==0,continue;end
    for k=1:4
        data=local_branch(sets(j).means,result.npBranchModel,schedules{k});
        r=sht_tc27_replay('points',cfg,engine,data,schedules{k}, ...
            struct('route','steady','independentPrediction',true));
        steady{j,k}=r;
        if ~all(r.valid),warning('TC27:Validation:Invalid','%s/%s有%d个稳态预测无效。',sets(j).name,labels{k},nnz(~r.valid));end
        metricPrediction=r.prediction;
        numericNames=metricPrediction.Properties.VariableNames(varfun(@isnumeric,metricPrediction,'OutputFormat','uniform'));
        metricPrediction{~r.valid,numericNames}=NaN;
        summary=[summary;sht_tc27_output_metrics(metricPrediction,sets(j).means,true,[sets(j).name,'_',labels{k}])]; %#ok<AGROW>
        out=r.prediction;out.valid=r.valid;out.stopReason=r.messages;
        writetable(out,fullfile(reportDir,[sets(j).name,'_',labels{k},'_steady_predictions.csv']));
    end
end
small=struct('id',{},'data',{},'first',{},'last',{},'duration_s',{}, ...
    'replayData',{},'fitIndices',{},'continuousBlock',{},'initializationPolicy',{});
for j=1:numel(sets)
    for h=1:numel(sets(j).small)
        q=sets(j).small(h);q.id=[sets(j).name,'_',q.id];small(end+1)=q; %#ok<AGROW>
    end
end
histories=cell(numel(small),2);historySummary=table();
smallPlan=small;
if isfield(options,'localWarmup_s'),smallPlan=sht_tc27_local_history_plan(smallPlan,options.localWarmup_s);end
historySets=cell(2,1);historyFailures=cell(2,1);
for k=1:2
    if isempty(smallPlan),break;end
    s=result.upstreamSchedule;if k==2,s=result.finalSchedule;end
    try
        historySets{k}=sht_tc27_replay_histories(cfg,engine,smallPlan,s, ...
            struct('integrationStep_s',options.validationIntegrationStep_s));
    catch failure
        historyFailures{k}=failure;
    end
end
for j=1:numel(small)
    t=small(j).data;
    for k=1:2
        s=result.upstreamSchedule;label='TC24';if k==2,s=result.finalSchedule;label='D_mixed';end
        try
            if ~isempty(historyFailures{k}),rethrow(historyFailures{k});end
            r=historySets{k}{j};
        catch failure
            % 独立测试失效单列，不回流改变拟合结果，也不隐去失败记录。
            names={'Np','Ng','Ptb3','Ttb3','Pt45','Tt45','Pt6','Tt6','Wa2'};
            r=struct('prediction',array2table(nan(height(t),9),'VariableNames',names), ...
                'valid',false,'message',failure.message);
            warning('TC27:Validation:HistoryInvalid','%s/%s: %s',small(j).id,label,failure.message);
        end
        histories{j,k}=r;
        historySummary=[historySummary;sht_tc27_output_metrics(r.prediction,t,false, ...
            [small(j).id,'_',label])]; %#ok<AGROW>
    end
    if options.plot,local_history_plot(t,histories(j,:),reportDir,small(j).id);end
end
result.validation=struct('steady', {steady},'steadyMetrics',summary, ...
    'smallHistories',{histories},'historyMetrics',historySummary, ...
    'testSources',{sets},'testsUsedForSelection',false);
if ~isempty(summary),writetable(summary,fullfile(reportDir,'steady_test_metrics.csv'));end
if ~isempty(historySummary),writetable(historySummary,fullfile(reportDir,'small_history_test_metrics.csv'));end
% 训练集也逐阶段列出物理误差；瞬态时刻路径的轴速误差不充当预测误差。
training=cell(4,1);trainingMetrics=table();
for k=1:4
    replayOptions=struct('route',result.route);
    if strcmp(result.route,'steady')
        % 与正式目标使用同一组同工况数值初根，当前曲线仍须独立求平衡。
        replayOptions.initialStates=result.baseline.states;
        replayOptions.commonWorkingSeed=result.baseline.commonWorkingSeed;
    end
    training{k}=sht_tc27_replay('points',cfg,engine,prepared.combinedSteady,schedules{k},replayOptions);
    prediction=training{k}.prediction;
    numeric=prediction.Properties.VariableNames(varfun(@isnumeric,prediction,'OutputFormat','uniform'));
    prediction{~training{k}.valid,numeric}=NaN;
    if ~all(training{k}.valid)
        warning('TC27:Validation:TrainingInvalid','%s/%s有%d个训练点独立回放无效，统计不丢弃这些点。', ...
            result.route,labels{k},nnz(~training{k}.valid));
    end
    metric=sht_tc27_output_metrics(prediction,prepared.combinedSteady,true,labels{k});
    if strcmp(result.route,'transient_instant'),metric=metric(~ismember(metric.output,["Np","Ng"]),:);end
    trainingMetrics=[trainingMetrics;metric]; %#ok<AGROW>
end
result.validation.trainingPointReplays=training;result.validation.trainingPointMetrics=trainingMetrics;
writetable(trainingMetrics,fullfile(reportDir,'training_point_metrics.csv'));
if ~isempty(summary),disp(summary(:,{'case','output','RMSE','unit','RMSE_design_pct'}));end
% 正式结果只保留运行所需的曲线、燃油偏置和Np选根表，不包含真值。
result.deliveryFile=fullfile(p.middle,['tc27_deterministic_',result.route,'_',result.method,'.xlsx']);
delivered=sht_tc27_delivery('write',result,result.deliveryFile);
result.deliverySha256=delivered.sha256;
if options.explicitInputs
    % 工程试车没有修正系数真值，不能读取开发样例的隐藏真值作比较。
    result.parameterValidation=struct('available',false, ...
        'reason','real_bench_truth_unavailable');
else
    result=sht_tc27_validate_parameters(result,prepared,reportDir,options.plot);
end
end

function data=local_branch(data,branch,s)
copy=data;f=s.fuelBias;x=min(max(data.Wf_mean/f.wfDesign,min(f.xNodes)),max(f.xNodes));
if numel(f.xNodes)==1,bias=repmat(f.biasNodes,height(data),1);else,bias=interp1(f.xNodes,f.biasNodes,x,'linear');end
copy.Wf_mean=data.Wf_mean-bias;[copy,~]=sht_np_branch_delivery('query',branch,copy,1);
fields=copy.Properties.VariableNames(startsWith(copy.Properties.VariableNames,'Np_branch_'));
for j=1:numel(fields),data.(fields{j})=copy.(fields{j});end
end
function local_history_plot(t,pred,directory,id)
f=figure('Name',['TC27 ',id],'Position',[80,80,1100,900]);names={'Np','Ng','Ptb3','Ttb3','Pt45','Tt45','Pt6','Tt6'};
for j=1:numel(names)
    subplot(4,2,j);plot(t.Time_s,t.(names{j}),'k-');hold on;
    plot(t.Time_s,pred{1}.prediction.(names{j}),'b--');plot(t.Time_s,pred{2}.prediction.(names{j}),'r-');
    ylabel(names{j});xlabel('Time / s');grid on;
end
legend('Measurement','TC24 schedule','TC27 schedule');print(f,fullfile(directory,[id,'_prediction.png']),'-dpng','-r130');
end
