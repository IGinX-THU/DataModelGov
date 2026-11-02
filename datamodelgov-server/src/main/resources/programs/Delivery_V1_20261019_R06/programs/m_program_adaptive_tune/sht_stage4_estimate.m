function records=sht_stage4_estimate(user)
% 4step3：父模型由Excel恢复。辨识不读取造数真值，D只作独立局部初评。
c=sht_stage4_config(user);plan=sht_stage4_guard('estimate',c);
sc=sht_stage4_scenarios();records=struct([]);
for i=1:numel(sc)
    q=sc(i);
    if ~ismember(q.id,plan.ids),continue;end
    if strcmp(q.role,'prediction_only'),continue;end
    folder=fullfile(c.middle,q.id);if ~isfolder(folder),mkdir(folder);end
    file=fullfile(folder,'stage4_model_record.mat');
    % F01是明确继承的已验收历史成果，不重签其源码和统计身份。
    if q.reuse&&strcmp(c.inputMode,'synthetic_demo')
        if isfile(file),s=load(file,'record');record=s.record;
        else
            assert(isfile(c.firstModel)&&isfile(c.firstResult),'F01上游成果缺失。');
            s=load(c.firstResult,'result');r=s.result;
            record=local_record(q,c.firstModel,c.firstResult,'',0,r);
            record.historical=true;record.uqFile=c.firstD;
            if ~isfile(record.uqFile),record.uqFile='';end
            record.identity=struct('historicalResultSha',sht_tc27_file_identity(c.firstResult));
            record.batchSha=plan.batchSha;
            if ~isempty(record.uqFile),record.uqSha=sht_tc27_file_identity(record.uqFile);end
            save(file,'record','-v7');
        end
        if ~isempty(record.uqFile),record.uqQuality='historical_D_original_identity';end
        save(file,'record','-v7');
        local_verify(record);records=[records;record];continue; %#ok<AGROW>
    end
    ds=load(fullfile(folder,'stage4_data_record.mat'),'record');data=ds.record;
    if strcmp(q.parent,'BENCH')
        p=sht_f3_three_component_assets('paths');parent=p.instantWorkbook;priorSource='2p4';
    else
        a=load(fullfile(c.middle,q.parent,'stage4_model_record.mat'),'record');
        local_verify(a.record);parent=a.record.modelFile;priorSource='flight';
    end
    options=struct('modelMode',0,'modelRoute','transient_instant','dataMethod','steady_only', ...
        'parameterSet','set1','scheduleParameterization','independent_nodes', ...
        'priorSource',priorSource,'priorWorkbook',parent, ...
        'trainingWorkbook',data.preparedWorkbook,'stage32File',data.preprocessFile, ...
        'outputRoot',fullfile(folder,'identification'), ...
        'reportRoot',fullfile(c.report,q.id,'identification'), ...
        'resultTag',[c.runId,'_',q.id],'regularizationWeight',c.regularizationWeight, ...
        'maximumIterations',c.maximumIterations,'plotEnabled',false);
    identity=struct('options',options,'measurementSha',data.measurementSha, ...
        'preparedSha',sht_tc27_file_identity(data.preparedWorkbook), ...
        'preprocessingSha',sht_tc27_file_identity(data.preprocessFile), ...
        'parentSha',sht_tc27_file_identity(parent), ...
        'solverSha',sht_tc27_file_identity(which('sht_f33_model_adapt_v2')));
    if isfile(file)
        s=load(file,'record');record=s.record;
        assert(isequaln(record.identity,identity),'SHT:Stage4:FitIdentity','辨识身份改变，请使用新批次。');
        local_verify(record);
    else
        timer=tic;
        r=sht_f33_model_adapt_v2('runRoute',options);
        record=local_record(q,r.output.formalWorkbook,r.output.matFile,parent,toc(timer),r);
        record.identity=identity;record.batchSha=plan.batchSha;save(file,'record','-v7');
    end
    if c.uqEnabled
        d=Start_FlightModelUQ_R1_02_MethodD(struct( ...
            'runTag',[c.runId,'_',q.id,'_D'],'engineId',c.engineId,'sortieId',q.id, ...
            'referenceResultFile',record.resultFile, ...
            'outputRoot',fullfile(folder,'uq_D'),'reportRoot',fullfile(c.report,q.id,'uq_D'), ...
            'runIndependentPrediction',false,'allowReferenceRebase',true));
        record.uqFile=d.artifacts.workbook;record.uqRuntime_s=d.totalWallTime_s;
        record.uqQuality=d.methodD.qualityLevel;
        record.uqSha=sht_tc27_file_identity(record.uqFile);
        save(file,'record','-v7');
    end
    records=[records;record]; %#ok<AGROW>
    fprintf('STAGE4 MODEL COMPLETE %s: converged=%d, %.1f s\n',q.id,record.converged,record.fitRuntime_s);
end
local_registry(c,records);
end

function record=local_record(q,modelFile,resultFile,parent,runtime,r)
record=struct('id',q.id,'parent',q.parent,'order',q.order,'role',q.role, ...
    'modelFile',modelFile,'modelSha',sht_tc27_file_identity(modelFile), ...
    'resultFile',resultFile,'resultSha',sht_tc27_file_identity(resultFile), ...
    'parentFile',parent,'fitRuntime_s',runtime,'historical',false, ...
    'converged',r.converged,'stopReason',r.stopReason, ...
    'steadyWindowCount',r.training.steadyWindowCount,'parameterCount',height(r.parameterTable), ...
    'uqFile','','uqSha','','uqRuntime_s',0,'uqQuality','not_requested', ...
    'batchSha','','identity',struct());
end

function local_verify(r)
assert(strcmp(r.modelSha,sht_tc27_file_identity(r.modelFile)), ...
    'SHT:Stage4:ChangedModel','模型Excel已变化：%s。',r.id);
assert(strcmp(r.resultSha,sht_tc27_file_identity(r.resultFile)), ...
    'SHT:Stage4:ChangedResult','内部结果已变化：%s。',r.id);
end

function local_registry(c,records)
if isempty(records),return;end
% 分次执行时索引仍纳入本批已经完成的全部模型，而非只保留本次选择。
sc=sht_stage4_scenarios();allRecords=struct([]);
for i=1:numel(sc)
    file=fullfile(c.middle,sc(i).id,'stage4_model_record.mat');
    if isfile(file),s=load(file,'record');local_verify(s.record);allRecords=[allRecords;s.record];end %#ok<AGROW>
end
records=allRecords;
% 正式版本索引只包含可交付模型、覆盖范围及状态，内部MAT不作下游入口。
index=table();support=table();
for i=1:numel(records)
    q=records(i);a=load(q.resultFile,'result');r=a.result;
    index=[index;table(string(q.id),string(q.parent),q.order,string(q.modelFile), ...
        string(q.modelSha),q.converged,string(q.stopReason),q.parameterCount, ...
        string(q.uqFile),string(q.uqQuality),'VariableNames', ...
        {'sortie','parent','order','model_excel','sha256','converged','stop_reason', ...
         'parameter_count','uq_excel','uq_quality'})]; %#ok<AGROW>
    t=r.coverageTable;t.sortie=repmat(string(q.id),height(t),1);support=[support;t]; %#ok<AGROW>
end
writetable(index,fullfile(c.middle,'stage4_model_registry.xlsx'),'Sheet','Models');
writetable(support,fullfile(c.middle,'stage4_model_registry.xlsx'),'Sheet','Coverage');
end
