function batch=sht_f33_small_history_batch(assets,experiments,schedules,recoveries,sensor,options)
% 小幅变化段与完整验证共用开环积分：三部件16状态，六部件29状态。
% 在有限前史起点求候选模型热平衡，再推进真实测量输入；准备段不参与拟合。
% 测量输出不逐时刻回灌，燃油偏置与全部健康曲线均由当前候选给出。
p=fileparts(mfilename('fullpath'));
empty=struct('prediction',table(),'axis',table(),'valid',false,'errorMessage',"", ...
    'segmentReplays',{{}},'restartStates',{{}},'executedEvaluationCount',0);
candidate=repmat(empty,numel(schedules),1);
for i=1:numel(schedules)
    a=assets;a.personalized.health=schedules{i}.designHealth;
    a.personalized.profile=sht_f33_model_adapt_v2('buildProfile',schedules{i});
    a.personalized.fuelBias=schedules{i}.fuelBias;
    if isfield(a,'modelMode')&&a.modelMode==0
        assert(all(a.personalized.health(59:71)==0),'三部件瞬态个体系数应为零。');
    else
        assert(all(a.personalized.health(90:112)==0),'六部件瞬态个体系数应为零。');
    end
    outputs=cell(numel(experiments),1);axes=outputs;
    try
        for j=1:numel(experiments)
            e=experiments(j);
            if isfield(e,'replayData')&&~isempty(e.replayData)
                h=e.replayData;outputRows=e.outputRows;
            else
                h=e.data;h.time_s=e.time_s(:);
                h.Ps0=h.Pamb;h.Ts_amb=h.Tamb;h.Pt3_eq=h.Pt3;
                outputRows=(1:height(h)).';
            end
            method='euler2';if strcmp(options.historyIntegrationMethod,'euler'),method='euler1';end
            ro=struct('cacheDirectory',fullfile(p,'MiddleData','flight_model_adapt_3p3_v2', ...
                'small_history_fit_cache'),'sourceSha256','', ...
                'integrationMethod',method,'inletMeanRecovery',recoveries(i), ...
                'progressIntervalSamples',8000,'sensorDynamicsEnabled',true);
            if isfield(a,'modelMode')&&a.modelMode==0
                paths=sht_f3_current_contract('paths');
                ro.cacheDirectory=fullfile(paths.middle,'small_history_fit_cache');
                ro.integrationStep_s=options.historyIntegrationStep_s;
            end
            if isfield(options,'comparisonCacheDirectory') && ~isempty(options.comparisonCacheDirectory)
                ro.cacheDirectory=options.comparisonCacheDirectory;
            end
            capture=isfield(options,'capturePreparation') && options.capturePreparation;
            reuse=isfield(options,'reusePreparation') && options.reusePreparation;
            if capture
                ro.captureTime_s=h.time_s(outputRows(1));
            end
            if reuse && i>1
                % 同一轮的基点准备状态；扰动只改变拟合段中的模型参数。
                ro.resumeState=candidate(1).restartStates{j};
                first=outputRows(1);h=h(first:end,:);outputRows=outputRows-first+1;
                ro.captureTime_s=[];
            end
            r=sht_f32_replay_history('run',h,a,'personalized',sensor,ro);
            assert(r.computationallyAccepted,'小幅段%s物理回放无效。',e.experimentId);
            outputs{j}=array2table(r.sensorExpectedOutput(outputRows,:), ...
                'VariableNames',{'Np','Ng','Pt3','Tt45'});
            axes{j}=r.scheduleCoordinate(outputRows,:);
            % 缓存保留完整状态；辨识对象只留轻量数值与缓存位置。
            candidate(i).segmentReplays{j}=struct('id',e.experimentId, ...
                'cacheFile',r.cacheFile,'maxResidual',r.maximumCommonWorkResidual, ...
                'integrationStep_s',r.integrationStep_s,'recordStep_s',r.recordStep_s);
            candidate(i).restartStates{j}=r.restartState;
            candidate(i).executedEvaluationCount=candidate(i).executedEvaluationCount+r.executedEvaluationCount;
        end
        candidate(i).prediction=vertcat(outputs{:});
        candidate(i).axis=vertcat(axes{:});candidate(i).valid=true;
    catch failure
        candidate(i).errorMessage=string(getReport(failure,'extended','hyperlinks','off'));
        if isfield(options,'capturePreparation') && options.capturePreparation
            % 差分必须全部有效；尽早保留首个根因，避免继续浪费候选回放。
            rethrow(failure);
        end
    end
    fprintf('    小幅历程候选 %d/%d：%d段，有效=%d\n',i,numel(schedules), ...
        numel(experiments),candidate(i).valid);
end
batch=struct('candidate',candidate,'enhancedTransientEffectsEnabled',true, ...
    'stateCount',29,'individualTransientCorrectionsZero',true);
if isfield(assets,'modelMode')&&assets.modelMode==0,batch.stateCount=16;end
end
