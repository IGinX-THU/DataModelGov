function [fun,statistics]=sht_tc27_objective(cfg,engine,data,sources,histories,contract,options)
%SHT_TC27_OBJECTIVE M0工程尺度下的稳态点/逐状态历程目标。
% 各数据块先按真实样本数归一化，再应用可配置总权重；不把稠密记录
% 当成更多独立稳态点。这里只定义确定性目标，不将其冒充UQ似然。
defaults=struct('route','transient_instant','pointHistoryWeights',[.7,.3], ...
    'steadySourceWeights',[.5,.5],'enableHistoryCache',true,'enablePointCache',true, ...
    'integrationStep_s',.1);
f=fieldnames(defaults);for j=1:numel(f),if ~isfield(options,f{j}),options.(f{j})=defaults.(f{j});end,end
assert(all(options.pointHistoryWeights>=0)&&sum(options.pointHistoryWeights)>0,'块权重无效。');
assert(all(options.steadySourceWeights>0),'稳态来源权重必须为正。');
pointNames={'Np','Ng','Ptb3','Ttb3','Pt45','Tt45','Pt6','Tt6','Wa2'};
scales=[63,114,7863,3.51,1980,5.72,550,4,.20];
if strcmp(options.route,'transient_instant')
    pointNames(1:2)={'dNp_dt','dNg_dt'};scales(1:2)=[20.9,38];
end
observed=local_observed(data,pointNames,true);
weights=zeros(height(data),1);
if ~isempty(data)
    sourceList=unique(sources);sourceTotal=sum(options.steadySourceWeights(sourceList));
    for s=sourceList(:).',use=sources==s;weights(use)=sqrt(options.steadySourceWeights(s)/sourceTotal/nnz(use)/9);end
end
block=options.pointHistoryWeights/sum(options.pointHistoryWeights);
if isempty(histories),block=[1,0];elseif isempty(data),block=[0,1];end
cache=cell(numel(histories),1);for j=1:numel(cache),cache{j}=struct('theta',{},'mask',{},'result',{});end
pointCache=cell(height(data),1);for j=1:numel(pointCache),pointCache{j}=struct('theta',{},'mask',{},'result',{});end
historyRuns=0;historyHits=0;pointRuns=0;pointHits=0;calls=0;
thermalDllCalls=0;historyDllCalls=0;failedReplays=0;
fun=@evaluate;statistics=@stats;
    function [residual,meta]=evaluate(theta)
        calls=calls+1;residual=[];valid=true;messages=strings(0,1);
        schedule=sht_steady_model_adapt_v2_common('m3nodestoschedule',contract,theta);
        blocks=struct('kind',{},'rows',{},'support',{});
        if ~isempty(data)
            predicted=zeros(height(data),9);
            for pointIndex=1:height(data)
                q=[];
                if options.enablePointCache
                    for cacheIndex=numel(pointCache{pointIndex}):-1:1
                        item=pointCache{pointIndex}(cacheIndex);
                        if isequal(theta(item.mask),item.theta(item.mask))
                            q=item.result;mask=item.mask;pointHits=pointHits+1;break;
                        end
                    end
                end
                if isempty(q)
                    replayOptions=struct('route',options.route);
                    rootOptions=struct('route',options.route);
                    if isfield(options,'pointInitialReplay')
                        rootOptions.initialStates=options.pointInitialReplay.states(pointIndex,:);
                        rootOptions.commonWorkingSeed=options.pointInitialReplay.commonWorkingSeed(pointIndex,:);
                        replayOptions=rootOptions;
                    end
                    if ~isempty(pointCache{pointIndex})
                        previous=pointCache{pointIndex}(end).result;
                        replayOptions.initialStates=previous.states;
                        replayOptions.commonWorkingSeed=previous.commonWorkingSeed;
                    end
                    q=sht_tc27_replay('points',cfg,engine,data(pointIndex,:),schedule,replayOptions);
                    pointRuns=pointRuns+1;
                    countPoint(q);
                    if ~all(q.valid)&&isfield(options,'pointInitialReplay')&&~isempty(pointCache{pointIndex})
                        % 上一差分候选的数值初值可能不适于当前候选。退回同一
                        % 工况已验证的上游平衡根，重新求当前模型；不复用预测值。
                        q=sht_tc27_replay('points',cfg,engine,data(pointIndex,:),schedule,rootOptions);
                        pointRuns=pointRuns+1;
                        countPoint(q);
                    end
                    if all(q.valid)
                        bounds=[q.coordinates;q.coordinates];fuel=repmat(data.Wf_mean(pointIndex)/schedule.fuelBias.wfDesign,1,2);
                        mask=sht_tc27_schedule('support',contract,bounds,fuel);
                        % 候选在此平衡根处的全部系数不变，则同一根仍严格满足
                        % 气热方程。等价于以上次有效根作初值，不使用线性预测。
                        pointCache{pointIndex}(end+1)=struct('theta',theta,'mask',mask,'result',q);
                        if numel(pointCache{pointIndex})>60,pointCache{pointIndex}=pointCache{pointIndex}(end-59:end);end
                    end
                end
                predicted(pointIndex,:)=q.prediction{:,pointNames};
                if all(q.valid)
                    blocks(end+1)=struct('kind','point','rows',pointIndex+(0:8)*height(data),'support',mask); %#ok<AGROW>
                end
                valid=valid&&all(q.valid);messages=[messages;q.messages(~q.valid)]; %#ok<AGROW>
            end
            e=(predicted-observed)./scales.*weights;
            residual=sqrt(block(1))*e(:);
        end
        names={'Np','Ng','Ptb3','Ttb3','Pt45','Tt45','Pt6','Tt6','Wa2'};
        historyScales=[63,114,7863,3.51,1980,5.72,550,4,.20];
        preparedPredictions=cell(numel(histories),1);
        pending=true(numel(histories),1);
        for k=1:numel(histories)
            if ~options.enableHistoryCache,continue;end
            for q=numel(cache{k}):-1:1
                item=cache{k}(q);
                if isequal(theta(item.mask),item.theta(item.mask))
                    preparedPredictions{k}=item.result;pending(k)=false;break;
                end
            end
        end
        historyFailure=[];
        if any(pending)
            try
                preparedPredictions(pending)=sht_tc27_replay_histories(cfg,engine, ...
                    histories(pending),schedule,struct('integrationStep_s',options.integrationStep_s));
                historyRuns=historyRuns+numel(unique([histories(pending).continuousBlock]));
                ids=find(pending);groups=unique([histories(pending).continuousBlock]);
                for group=groups
                    index=ids(find([histories(pending).continuousBlock]==group,1));
                    historyDllCalls=historyDllCalls+preparedPredictions{index}.dllEvaluationCount;
                end
            catch failure
                failedReplays=failedReplays+1;
                historyFailure=failure;
            end
        end
        for k=1:numel(histories)
            t=histories(k).data;prediction=[];
            if options.enableHistoryCache
                for q=numel(cache{k}):-1:1
                    item=cache{k}(q);
                    if isequal(theta(item.mask),item.theta(item.mask))
                        prediction=item.result;mask=item.mask;historyHits=historyHits+1;break;
                    end
                end
            end
            try
                if isempty(prediction)
                    if ~isempty(historyFailure),rethrow(historyFailure);end
                    prediction=preparedPredictions{k};
                    mask=sht_tc27_schedule('support',contract,prediction.coordinateBounds,prediction.fuelCoordinateBounds);
                    cache{k}(end+1)=struct('theta',theta,'mask',mask,'result',prediction);
                    if numel(cache{k})>80,cache{k}=cache{k}(end-79:end);end
                end
                e=(prediction.prediction{:,names}-local_observed(t,names,false))./historyScales;
                e=e*sqrt(block(2)/numel(histories)/height(t)/9);
                blocks(end+1)=struct('kind','history','rows',numel(residual)+(1:numel(e)),'support',mask); %#ok<AGROW>
                residual=[residual;e(:)]; %#ok<AGROW>
            catch failure
                valid=false;messages(end+1)=string(failure.message);residual=[residual;repmat(1e6,height(t)*9,1)]; %#ok<AGROW>
            end
        end
        valid=valid&&all(isfinite(residual));if ~valid,residual(~isfinite(residual))=1e6;end
        meta=struct('valid',valid,'messages',messages,'pointCount',height(data), ...
            'historyCount',numel(histories),'historyRuns',historyRuns,'historyCacheHits',historyHits, ...
            'jacobianBlocks',blocks);
    end
    function s=stats()
        s=struct('calls',calls,'pointRuns',pointRuns,'pointCacheHits',pointHits,'historyRuns',historyRuns, ...
            'historyCacheHits',historyHits,'historyCachePolicy','exact_piecewise_linear_support_on_full_Heun_envelope', ...
            'thermalDllEvaluations',thermalDllCalls,'historyDllEvaluations',historyDllCalls, ...
            'failedReplays',failedReplays,'dllCountMayBeLowerBound',failedReplays>0);
    end
    function countPoint(q)
        for point=1:numel(q.equilibriumDetails)
            item=q.equilibriumDetails{point};
            if isempty(item),failedReplays=failedReplays+1;
            else,thermalDllCalls=thermalDllCalls+item.evaluationCount;end
        end
    end
end

function y=local_observed(t,names,means)
suffix='';if means,suffix='_mean';end
y=zeros(height(t),numel(names));
if height(t)==0,return;end
for j=1:numel(names)
    if startsWith(names{j},'dN'),continue;end
    if strcmp(names{j},'Wa2'),y(:,j)=t.(['Wa1',suffix])-t.(['Wb',suffix]);
    else,y(:,j)=t.([names{j},suffix]);end
end
end
