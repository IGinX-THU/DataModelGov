function [evaluate,closeEngine,statistics]=sht_tc27_uq_evaluator(c,executionOptions)
%SHT_TC27_UQ_EVALUATOR 本轮气热回放与持久候选缓存。无历史结果混入。
% evaluate(theta,nuisance,dataOverride)返回原量纲残差；不读取测试或真值。
if nargin<2,executionOptions=struct();end
[cfg,execution]=sht_tc27_uq_runtime(c,executionOptions);
reuseEnabled=isfield(c.options,'thermalReuseEnabled')&&c.options.thermalReuseEnabled;
assert(~reuseEnabled||strcmp(c.route,'transient_instant'), ...
    'TC27:UQ:ThermalReuseRoute','steady路线尚未验收热参考复用，必须完整回放。');
% 缓存额外绑定实际执行资产与数据，冻结旧合同在新包对照时也不会命中旧值。
execution.cacheSemantics=struct('points',c.trainingData,'histories',c.histories, ...
    'observed',c.observed,'step',c.options.integrationStep_s, ...
    'thermalReuseEnabled',reuseEnabled,'contractPhysics',c.physicsHash, ...
    'evaluatorCode',sht_tc27_file_identity([mfilename('fullpath'),'.m']));
executionHash=sht_tc27_uq_hash(execution);
engine=sht_engine_open(cfg.engine);
totalCandidates=0;totalCandidateTime=0;cacheHits=0;requests=0;
thermalReferences={};referenceRuntime=0;thermalEvaluations=0;reusePoints=0;fallbackPoints=0;
historyDllEvaluations=0;referenceDllEvaluations=0;failedCandidates=0;
if reuseEnabled
    assert(isempty(c.histories)&&strcmp(c.route,'transient_instant'), ...
        'TC27:UQ:ThermalReuseMode','本批仅验收仅稳态、瞬态时刻UQ。');
    initTimer=tic;
    try
        schedule=sht_steady_model_adapt_v2_common('m3nodestoschedule',c,c.thetaHat);
        reference=sht_tc27_replay('points',cfg,engine,c.trainingData,schedule, ...
            struct('route',c.route,'returnThermalReference',true));
        thermalReferences=reference.thermalReferences;
        for j=1:numel(reference.equilibriumDetails)
            detail=reference.equilibriumDetails{j};
            if ~isempty(detail),referenceDllEvaluations=referenceDllEvaluations+detail.evaluationCount;end
        end
    catch failure
        sht_engine_close(engine);rethrow(failure);
    end
    referenceRuntime=toc(initTimer);
    fprintf('TC27-UQ冻结热平衡参考：%d/%d点，准备%.2fs；逐候选仍检查真实DLL残差。\n', ...
        nnz(~cellfun(@isempty,thermalReferences)),height(c.trainingData),referenceRuntime);
end
historyCache=cell(numel(c.histories),1);
for historyIndex=1:numel(historyCache)
    historyCache{historyIndex}=struct('theta',{},'nuisance',{},'inputHash',{},'mask',{},'values',{});
end
evaluate=@run;closeEngine=@()sht_engine_close(engine);statistics=@snapshot;
    function s=snapshot()
        % 每组包含全部训练点和受影响历程，不等同于底层DLL调用次数。
        s=struct('requestedCandidateGroups',requests,'cacheHitGroups',cacheHits, ...
            'newCandidateGroups',totalCandidates,'newCandidateRuntime_s',totalCandidateTime, ...
            'thermalReferenceRuntime_s',referenceRuntime,'thermalReuseEnabled',reuseEnabled, ...
            'thermalEvaluationCount',thermalEvaluations,'reusePointCount',reusePoints, ...
            'fallbackPointCount',fallbackPoints,'executionHash',executionHash, ...
            'thermalReferenceDllEvaluations',referenceDllEvaluations, ...
            'physicalDllEvaluations',referenceDllEvaluations+thermalEvaluations+historyDllEvaluations, ...
            'failedCandidateGroups',failedCandidates,'dllCountMayBeLowerBound',failedCandidates>0, ...
            'runtimeDirectory',cfg.engine.interface.controlDir);
    end
    function out=run(theta,nuisance,override)
        if nargin<2||isempty(nuisance),nuisance=zeros(height(c.nuisance),size(theta,2));end
        if nargin<3,override=[];end
        if size(nuisance,2)==1,nuisance=repmat(nuisance,1,size(theta,2));end
        out=struct('residual',nan(numel(c.observed),size(theta,2)), ...
            'valid',false(1,size(theta,2)),'dllEvaluationCount',0,'dllRuntime_s',0, ...
            'messages',strings(1,size(theta,2)));
        for k=1:size(theta,2)
            requests=requests+1;
            key=sht_tc27_uq_hash(struct('theta',theta(:,k),'nuisance',nuisance(:,k), ...
                'override',override,'executionHash',executionHash));
            file=fullfile(c.evaluationDirectory,['eval_',key,'.mat']);
            if isfile(file),q=load(file,'r');r=q.r;
                assert(isfield(r,'executionHash')&&strcmp(r.executionHash,executionHash), ...
                    'TC27:UQ:CacheExecution','物理缓存与实际执行包不一致。');
                cacheHits=cacheHits+1;
            else
                timer=tic;r=struct('valid',false,'residual',nan(numel(c.observed),1),'message','');
                try
                    s=sht_steady_model_adapt_v2_common('m3nodestoschedule',c,theta(:,k));
                    % 不增加公开接口：未调度系数沿原stepIn健康向量进入DLL。
                    s.designHealth(c.nuisance.c_index+1)=nuisance(:,k);
                    pts=c.trainingData;hist=c.histories;
                    if ~isempty(override),pts=override.points;hist=override.histories;end
                    replayOptions=struct('route',c.route);
                    if reuseEnabled
                        assert(isequal(pts.point_id,c.trainingData.point_id), ...
                            'TC27:UQ:ThermalReferencePoints','输入扰动不能改变参考点顺序或身份。');
                        replayOptions.thermalReferences=thermalReferences;
                    end
                    q=sht_tc27_replay('points',cfg,engine,pts,s,replayOptions);
                    for pointIndex=1:numel(q.equilibriumDetails)
                        detail=q.equilibriumDetails{pointIndex};if isempty(detail),continue;end
                        thermalEvaluations=thermalEvaluations+detail.evaluationCount;
                        if isfield(detail,'reuse')
                            reusePoints=reusePoints+1;fallbackPoints=fallbackPoints+detail.reuse.fallback;
                        end
                    end
                    assert(all(q.valid),'TC27:UQ:Point','稳态点失败：%s',strjoin(cellstr(q.messages(~q.valid)),','));
                    y=q.prediction{:,c.outputNames};y=y(:);
                    continuousReplays={};
                    for h=1:numel(hist)
                        inputHash=sht_tc27_uq_hash(hist(h));z=[];
                        for cacheIndex=numel(historyCache{h}):-1:1
                            item=historyCache{h}(cacheIndex);
                            if strcmp(item.inputHash,inputHash)&&isequal(item.nuisance,nuisance(:,k))&& ...
                                    isequal(item.theta(item.mask),theta(item.mask,k))
                                z=item.values;break;
                            end
                        end
                        if isempty(z)
                            if isempty(continuousReplays)
                                continuousReplays=sht_tc27_replay_histories(cfg,engine,hist,s, ...
                                    struct('integrationStep_s',c.options.integrationStep_s));
                                groups=unique([hist.continuousBlock],'stable');
                                for group=groups
                                    first=find([hist.continuousBlock]==group,1);
                                    historyDllEvaluations=historyDllEvaluations+continuousReplays{first}.dllEvaluationCount;
                                end
                            end
                            qh=continuousReplays{h};
                            z=qh.prediction{:,c.historyNames};
                            mask=sht_tc27_schedule('support',c,qh.coordinateBounds,qh.fuelCoordinateBounds);
                            historyCache{h}(end+1)=struct('theta',theta(:,k),'nuisance',nuisance(:,k), ...
                                'inputHash',inputHash,'mask',mask,'values',z);
                            if numel(historyCache{h})>100,historyCache{h}=historyCache{h}(end-99:end);end
                        end
                        y=[y;z(:)]; %#ok<AGROW>
                    end
                    observed=sht_tc27_uq_data_vector(pts,hist,c.route);
                    r.residual=y-observed;r.valid=all(isfinite(r.residual));
                catch failure
                    expected={'TC27:UQ:Point','TC27:Replay:InitialThermal', ...
                        'TC27:Replay:Fuel','TC27:Replay:ModelFailure'};
                    physical=ismember(failure.identifier,expected)|| ...
                        strcmp(failure.identifier,'sht:engine:dllEvaluationFailed')|| ...
                        startsWith(failure.identifier,'SHT:ThermalEquilibrium:');
                    if ~physical,rethrow(failure);end
                    failedCandidates=failedCandidates+1;
                    r.errorIdentifier=failure.identifier;
                    r.message=failure.message;
                end
                r.executionHash=executionHash;
                r.runtime_s=toc(timer);out.dllEvaluationCount=out.dllEvaluationCount+1;
                out.dllRuntime_s=out.dllRuntime_s+r.runtime_s;
                totalCandidates=totalCandidates+1;totalCandidateTime=totalCandidateTime+r.runtime_s;
                if mod(totalCandidates,8)==0
                    fprintf('TC27-UQ当前进程候选完整求值%d组，平均%.2fs/组，当前有效%d。\n', ...
                        totalCandidates,totalCandidateTime/totalCandidates,r.valid);
                end
                temp=[file,'.partial.mat'];save(temp,'r','-v7.3');movefile(temp,file,'f');
            end
            out.residual(:,k)=r.residual;out.valid(k)=r.valid;out.messages(k)=string(r.message);
        end
    end
end
