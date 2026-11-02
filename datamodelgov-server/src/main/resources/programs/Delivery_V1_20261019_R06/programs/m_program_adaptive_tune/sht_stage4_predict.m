function result=sht_stage4_predict(user)
% 4step4：先冻结两种预测模型，再读取第6架次输出评价；故障不进入趋势。
c=sht_stage4_config(user);plan=sht_stage4_guard('predict',c);
folder=fullfile(c.middle,'prediction');
if ~isfolder(folder),mkdir(folder);end
frozen=struct('nodes',table());
hasJobs=c.fullReplayEnabled&&(~isempty(plan.predictionIds)||plan.forecast);
if plan.forecast||hasJobs
    assets=sht_f3_current_contract('assets',struct('priorSource','2p4','priorRoute','transient_instant'));
end
if plan.forecast
ids={'F01','F02','F03','F04','F05_N'};model=cell(5,1);record=cell(5,1);hashes=cell(5,1);
for i=1:5
    s=load(fullfile(c.middle,ids{i},'stage4_model_record.mat'),'record');record{i}=s.record;
    hashes{i}=sht_tc27_file_identity(s.record.modelFile);
    assert(strcmp(hashes{i},s.record.modelSha),'正常主线模型已改变。');
    model{i}=sht_f33_excel_delivery('read',s.record.modelFile,assets);
end
coverage=table();resultHashes=cell(5,1);
for i=1:5
    % 覆盖信息由已核验的冻结辨识结果恢复，避免索引Excel被重写时污染趋势。
    a=load(record{i}.resultFile,'result');t=a.result.coverageTable;
    t.sortie=repmat(string(ids{i}),height(t),1);coverage=[coverage;t]; %#ok<AGROW>
    resultHashes{i}=record{i}.resultSha;
end
identity=struct('normalIds',{ids},'modelHashes',{hashes},'resultHashes',{resultHashes}, ...
    'code',sht_tc27_file_identity(which('sht_stage4_predict')));
freezeFile=fullfile(folder,'prediction_freeze.mat');
if isfile(freezeFile)
    s=load(freezeFile,'frozen');frozen=s.frozen;
    assert(isequaln(frozen.identity,identity),'预测模型身份变化，请使用新批次。');
else
    % 覆盖信息属于正式模型索引；不读造数真值、F06测量或F06标签。
    holdModel=model{5};trendModel=holdModel;rows=table();
    for j=1:numel(trendModel.schedule.healthEntries)
        e=trendModel.schedule.healthEntries(j);cIndex=e.cIndex;
        if ~ismember(cIndex,[1,2,7,8,10,11,12]),continue;end
        for k=1:numel(e.xNodes)
            x=e.xNodes(k);values=zeros(5,1);supported=false(5,1);
            for i=1:5
                source=model{i}.schedule.healthEntries([model{i}.schedule.healthEntries.cIndex]==cIndex);
                values(i)=local_interp(source.xNodes,source.kNodes,x);
                z=coverage(string(coverage.sortie)==string(ids{i})&coverage.c_index==cIndex,:);
                if ~isempty(z)
                    supported(i)=local_interp(z.x_node,double(z.active),x)>0.5;
                end
            end
            use=find(supported);value=e.kNodes(k);slope=0;reason="hold_insufficient_support";
            if numel(use)>=3&&supported(5)
                beta=[ones(numel(use),1),use]\values(use);
                proposal=[1,6]*beta;
                % 仅数值/工程边界保护，不根据第6架次结果选择是否外推。
                if isfinite(proposal)&&abs(proposal)<=0.08
                    value=proposal;slope=beta(2);reason="linear_normal_history";
                else,reason="hold_outside_engineering_bound";
                end
            end
            rows=[rows;table(cIndex,k,x,e.kNodes(k),value,slope,numel(use),reason, ...
                'VariableNames',{'c_index','node','x','hold','trend','slope_per_sortie','supported_sorties','decision'})]; %#ok<AGROW>
            e.kNodes(k)=value;
        end
        trendModel.schedule.healthEntries(j)=e;
        template=assets.steadySchedule.healthEntries([assets.steadySchedule.healthEntries.cIndex]==cIndex);
        trendModel.schedule.designHealth(cIndex+1)=local_interp(e.xNodes,e.kNodes,template.designCoordinate);
    end
    % fuelBias、Kdist和全部瞬态参数保持F05_N一致。
    freezeOptions=struct('modelMode',0,'priorSource','flight','priorRoute','transient_instant', ...
        'priorWorkbook',record{5}.modelFile);
    formal=struct('options',freezeOptions,'routeId','stage4_normal_history_prediction', ...
        'training',struct('sourceSha256',sht_f33_model_adapt_v2('structHash',hashes)), ...
        'prior',struct('sourceSha256',hashes{5}),'finalSchedule',holdModel.schedule, ...
        'estimatedKdistEq',holdModel.KdistEq);
    holdFile=fullfile(folder,'F06_hold_model.xlsx');trendFile=fullfile(folder,'F06_trend_model.xlsx');
    sht_f33_excel_delivery('write',formal,holdFile);
    formal.finalSchedule=trendModel.schedule;sht_f33_excel_delivery('write',formal,trendFile);
    frozen=struct('identity',identity,'holdFile',holdFile,'trendFile',trendFile, ...
        'holdSha',sht_tc27_file_identity(holdFile),'trendSha',sht_tc27_file_identity(trendFile), ...
        'nodes',rows,'created',datestr(now,31),'futureDataUsed',false);
    save(freezeFile,'frozen','-v7');
    writetable(rows,fullfile(folder,'F06_trend_definition.xlsx'),'Sheet','Nodes');
end
assert(strcmp(frozen.holdSha,sht_tc27_file_identity(frozen.holdFile))&& ...
    strcmp(frozen.trendSha,sht_tc27_file_identity(frozen.trendFile)),'冻结预测Excel已经变化。');
end
result=struct('frozen',frozen,'replays',struct([]),'summary',table(), ...
    'identity',plan.predictionIdentity,'status','NOT_REQUESTED','validationPerformed',false, ...
    'independentTestAvailable',false);
% R2019b不支持对无字段的嵌套空结构体直接作首次下标赋值。
result.replays=repmat(struct('sortie','','model','','modelFile','', ...
    'cacheFile','','cacheSha','','runtime_s',0,'cacheHit',false,'accepted',false),0,1);
if ~hasJobs
    if plan.forecast,result.status='MODELS_FROZEN_NOT_VALIDATED';end
    save(plan.predictionFile,'result','-v7');
    fprintf('STAGE4 PREDICT %s: %s\n',plan.scopeTag,result.status);return;
end
result.status='INCOMPLETE';
jobs={};
for id=plan.predictionIds
    s=load(fullfile(c.middle,id{1},'stage4_model_record.mat'),'record');
    jobs(end+1,:)={id{1},'parent',s.record.parentFile}; %#ok<AGROW>
    jobs(end+1,:)={id{1},'updated',s.record.modelFile}; %#ok<AGROW>
end
if plan.forecast
    jobs(end+1,:)={'F06','hold',frozen.holdFile};jobs(end+1,:)={'F06','trend',frozen.trendFile};
end
assumptions=sht_f31_flight_measurement('publicAssumptions', ...
    sht_f31_flight_measurement('model',3201001,'F32-MEASUREMENT-PRIOR',false));
for k=1:size(jobs,1)
    id=jobs{k,1};label=jobs{k,2};modelFile=jobs{k,3};
    s=load(fullfile(c.middle,id,'stage4_data_record.mat'),'record');dataRecord=s.record;
    data=readtable(dataRecord.measurementFile,'Sheet','Data');
    m=sht_f33_excel_delivery('read',modelFile,assets);
    assets.personalized.health=m.schedule.designHealth;assets.personalized.profile=m.profile;
    assets.personalized.fuelBias=m.schedule.fuelBias;assets.personalized.scheduleEnabled=true;
    aTimer=tic;
    replay=sht_f32_replay_history('run',data,assets,'personalized',assumptions, ...
        struct('cacheDirectory',fullfile(folder,'replay_cache'),'sourceSha256',dataRecord.measurementSha, ...
        'integrationStep_s',0.1,'inletMeanRecovery',m.metadata.mean_inlet_recovery-m.KdistEq, ...
        'exhaustBackPressureDesignRise_Pa',m.metadata.backpressure_design_Pa, ...
        'designPower_W',m.metadata.design_power_W));
    result.replays(k)=struct('sortie',id,'model',label,'modelFile',modelFile, ...
        'cacheFile',replay.cacheFile,'cacheSha',sht_tc27_file_identity(replay.cacheFile), ...
        'runtime_s',toc(aTimer),'cacheHit',replay.cacheHit, ...
        'accepted',replay.computationallyAccepted);
    for j=1:4
        e=replay.residual(:,j);scale=assumptions.designReference(strcmp(string(assumptions.name),replay.outputNames{j}));
        % 指标使用原单位，同时单列设计参考尺度归一化值，不混称百分误差。
        result.summary=[result.summary;table(string(id),string(label),string(replay.outputNames{j}), ...
            string(replay.outputUnits{j}),sqrt(mean(e.^2)),mean(e),max(abs(e)), ...
            sqrt(mean(e.^2))/scale,'VariableNames', ...
            {'sortie','model','channel','unit','rmse','mean_error','max_abs_error','reference_nrms'})]; %#ok<AGROW>
    end
    save(plan.predictionFile,'result','-v7.3');
    fprintf('STAGE4 REPLAY COMPLETE %s/%s %.1f s\n',id,label,result.replays(k).runtime_s);
end
result.status='REPLAY_COMPLETE';result.validationPerformed=true;
save(plan.predictionFile,'result','-v7.3');
if ~isfolder(plan.reportRoot),mkdir(plan.reportRoot);end
writetable(result.summary,fullfile(plan.reportRoot,'full_history_output_comparison.xlsx'),'Sheet','Errors');
end

function value=local_interp(x,y,q)
x=x(:);y=y(:);value=interp1(x,y,min(max(q,x(1)),x(end)),'linear');
end
