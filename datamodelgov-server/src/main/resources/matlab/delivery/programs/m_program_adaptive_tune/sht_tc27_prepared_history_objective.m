function [fun,factory,statistics]=sht_tc27_prepared_history_objective(cfg,engine,histories,model,options)
%SHT_TC27_PREPARED_HISTORY_OBJECTIVE 局部准备状态仅在同一轮差分内复用。
% 正式fun按候选重算热平衡和准备段；factory为本轮差分提供完整断点。
% 拟合掩码可以不连续，但积分必须保留掩码之间的真实输入记录。
defaults=struct('integrationStep_s',.1,'parameterKind','schedule_nodes','historyWeighting','equal_segments');
for f=fieldnames(defaults).',if ~isfield(options,f{1}),options.(f{1})=defaults.(f{1});end,end
assert(ismember(options.parameterKind,{'schedule_nodes','transient_coefficients'}));
assert(ismember(options.historyWeighting,{'equal_segments','all_samples'}));
names={'Np','Ng','Ptb3','Ttb3','Pt45','Tt45','Pt6','Tt6','Wa2'};
scales=[63,114,7863,3.51,1980,5.72,550,4,.20];
total=sum(arrayfun(@(h)height(h.data),histories));
cache=cell(numel(histories),1);
for k=1:numel(histories),cache{k}=struct('theta',{},'mask',{},'result',{});end
fullRuns=0;shortRuns=0;refreshes=0;dll=0;hits=0;failures=0;fullTime=0;shortTime=0;
fun=@fullObjective;factory=@differenceFactory;statistics=@stats;
    function [r,m]=fullObjective(theta)
        [r,m]=evaluate(theta,[]);
    end
    function f=differenceFactory(theta)
        [~,m,records]=evaluate(theta,[]);
        assert(m.valid,'TC27:Fit:InvalidPreparation','本轮基点准备无效：%s',strjoin(m.messages,'; '));
        base=struct('theta',theta,'records',{records});refreshes=refreshes+1;
        f=@(candidate)evaluate(candidate,base);
    end
    function [r,m,records]=evaluate(theta,base)
        if strcmp(options.parameterKind,'schedule_nodes')
            schedule=sht_steady_model_adapt_v2_common('m3nodestoschedule',model,theta);health=zeros(13,1);
        else,schedule=model;health=theta;end
        r=[];messages=strings(0,1);valid=true;records=cell(numel(histories),1);
        blocks=struct('kind',{},'rows',{},'support',{});
        for k=1:numel(histories)
            h=histories(k);q=[];mask=true(numel(theta),1);
            ro=struct('integrationStep_s',options.integrationStep_s,'transientHealth',health,'returnWorkingSeeds',true);
            try
                if isempty(base)
                    for j=numel(cache{k}):-1:1
                        c=cache{k}(j);
                        if isequal(theta(c.mask),c.theta(c.mask)),q=c.result;mask=c.mask;hits=hits+1;break;end
                    end
                    rows=h.fitIndices;
                    if isempty(q)
                        t=tic;q=sht_tc27_replay('history',cfg,engine,h.replayData,schedule,ro);
                        fullTime=fullTime+toc(t);fullRuns=fullRuns+1;dll=dll+q.dllEvaluationCount;
                        if strcmp(options.parameterKind,'schedule_nodes')
                            mask=sht_tc27_schedule('support',model,q.coordinateBounds,q.fuelCoordinateBounds);
                        end
                        cache{k}(end+1)=struct('theta',theta,'mask',mask,'result',q);
                        if numel(cache{k})>90,cache{k}=cache{k}(end-89:end);end
                    end
                else
                    b=base.records{k};start=h.fitIndices(1);rows=h.fitIndices-start+1;
                    if strcmp(options.parameterKind,'schedule_nodes')
                        mask=sht_tc27_schedule('support',model,b.coordinateBounds,b.fuelCoordinateBounds);
                    end
                    if isequal(theta(mask),base.theta(mask))
                        q=b;rows=h.fitIndices;hits=hits+1;
                    else
                        ro.initialState=b.states(start,:).';
                        ro.initialSensorState=b.prediction{start,1:8};
                        ro.initialWorkingSeed=b.workingSeeds(start,:);
                        t=tic;q=sht_tc27_replay('history',cfg,engine,h.replayData(start:end,:),schedule,ro);
                        shortTime=shortTime+toc(t);shortRuns=shortRuns+1;dll=dll+q.dllEvaluationCount;
                    end
                end
                observed=h.data{:,names(1:8)};observed(:,9)=h.data.Wa1-h.data.Wb;
                denominator=numel(histories)*height(h.data);
                if strcmp(options.historyWeighting,'all_samples'),denominator=total;end
                v=(q.prediction{rows,names}-observed)./scales/sqrt(9*denominator);
                blocks(end+1)=struct('kind','history','rows',numel(r)+(1:numel(v)),'support',mask); %#ok<AGROW>
                r=[r;v(:)];records{k}=q;valid=valid&&q.valid; %#ok<AGROW>
            catch failure
                if ~startsWith(failure.identifier,'TC27:Replay:')&& ...
                        ~startsWith(failure.identifier,'SHT:ThermalEquilibrium:')&& ...
                        ~strcmp(failure.identifier,'sht:engine:dllEvaluationFailed'),rethrow(failure);end
                failures=failures+1;valid=false;messages(end+1)=string(failure.message); %#ok<AGROW>
                r=[r;repmat(1e6,height(h.data)*9,1)]; %#ok<AGROW>
            end
        end
        m=struct('valid',valid&&all(isfinite(r)),'messages',messages,'jacobianBlocks',blocks);
    end
    function s=stats()
        s=struct('fullHistoryRuns',fullRuns,'frozenFitRuns',shortRuns,'preparationRefreshes',refreshes, ...
            'historyDllCalls',dll,'fullHistoryElapsed_s',fullTime,'frozenFitElapsed_s',shortTime, ...
            'historySupportCacheHits',hits,'failedReplays',failures,'dllCountMayBeLowerBound',failures>0);
    end
end
