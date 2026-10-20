function records=sht_stage4_generate(user)
% 4step2：逐架次调用现行3.1和3.2，无测试集，不向辨识端传场景标签或真值。
c=sht_stage4_config(user);plan=sht_stage4_guard('generate',c);
sc=sht_stage4_scenarios();records=struct([]);
% 先检查全部所选架次，避免前面已造数很久后才发现后面有孤立旧缓存。
% 缺少完整数据记录时，无法证明F32产物的源码/配置身份，不能只凭测量SHA复用。
for i=1:numel(sc)
    q=sc(i);
    if ~ismember(q.id,plan.ids)||strcmp(q.role,'prediction_only'),continue;end
    folder=fullfile(c.middle,q.id);
    if isfile(fullfile(folder,'stage4_data_record.mat')),continue;end
    leftovers=dir(fullfile(folder,'preprocess','**','*'));
    leftovers=leftovers(~[leftovers.isdir]);
    assert(isempty(leftovers),'SHT:Stage4:OrphanPreprocess', ...
        '%s缺少完整数据记录但已有预处理产物：%s。保留诊断并使用新的runId和空目录，不重签旧缓存。', ...
        q.id,fullfile(folder,'preprocess'));
end
for i=1:numel(sc)
    q=sc(i);
    if ~isempty(c.scenarioIds)&&~ismember(q.id,c.scenarioIds),continue;end
    folder=fullfile(c.middle,q.id);report=fullfile(c.report,q.id);
    if ~isfolder(folder),mkdir(folder);end
    if ~isfolder(report),mkdir(report);end
    file=fullfile(folder,'stage4_data_record.mat');timer=tic;
    identity=struct('scenario',q,'source',plan.sources.(q.id),'mode',c.inputMode,'maximumDuration',c.generationMaximumDuration_s, ...
        'generationCode',sht_tc27_file_identity(which('sht_f31_generate_long_missions')), ...
        'missionCode',sht_tc27_file_identity(which('sht_f31_mission_definition')), ...
        'preprocessCode',sht_tc27_file_identity(which('sht_f32_preprocess_and_replay')));
    if isfile(file)
        old=load(file,'record');record=old.record;
        assert(isequaln(record.identity,identity),'SHT:Stage4:DataIdentity','造数或处理身份变化，请使用新批次。');
        assert(strcmp(record.measurementSha,sht_tc27_file_identity(record.measurementFile)), ...
            '测量Excel已经变化。');
        records=[records;record];continue; %#ok<AGROW>
    end
    truthFile='';generationTime=0;
    if strcmp(c.inputMode,'external')
        assert(isfield(c.externalMeasurements,q.id),'缺少外部架次%s。',q.id);
        measurementFile=plan.sources.(q.id).path;
    elseif q.reuse
        measurementFile=plan.sources.(q.id).path;
    else
        g=sht_f31_generate_long_missions(struct('runTag',[c.runId,'_',q.id], ...
            'missionDefinition',q.definition,'healthDesignOffset',q.healthOffset, ...
            'maximumDuration_s',c.generationMaximumDuration_s,'runValidation',false, ...
            'plotEnabled',false,'showFigures',false,'calibrationSeed',q.seed, ...
            'persistentBiasSeed',3101017, ...
            'thermalTruthRoot',fullfile(c.middle,'thermal_truth'), ...
            'outputRoot',fullfile(folder,'generation'),'dataRoot',fullfile(c.data,q.id), ...
            'reportRoot',fullfile(report,'generation')));
        measurementFile=g.output.identificationExcelFile;
        truthFile=g.output.validationTruthFile;generationTime=sum([g.runs.runtime_s]);
        clear g;
    end
    assert(isfile(measurementFile),'缺少本架次测量Excel。');
    preprocessFile='';preparedWorkbook='';preprocessSha='';preparedSha='';
    if ~strcmp(q.role,'prediction_only')
        preRoot=fullfile(folder,'preprocess');
        p=sht_f32_preprocess_and_replay(struct('runTag',[c.runId,'_',q.id], ...
            'identificationFile',measurementFile,'validationEnabled',false, ...
            'replayEnabled',false,'plotEnabled',false,'outputRoot',preRoot, ...
            'reportRoot',fullfile(report,'preprocess')));
        assert(numel(p.datasets)==1,'无测试集任务不应生成第二组证据。');
        preprocessFile=p.output.latestMatFile;preparedWorkbook=p.output.identificationExcel;
        preprocessSha=sht_tc27_file_identity(preprocessFile);
        preparedSha=sht_tc27_file_identity(preparedWorkbook);
        clear p;
    end
    record=struct('id',q.id,'parent',q.parent,'order',q.order,'role',q.role, ...
        'measurementFile',measurementFile,'measurementSha',sht_tc27_file_identity(measurementFile), ...
        'preprocessFile',preprocessFile,'preparedWorkbook',preparedWorkbook, ...
        'preprocessSha',preprocessSha,'preparedSha',preparedSha,'batchSha',plan.batchSha, ...
        'truthFile',truthFile,'identity',identity,'generationRuntime_s',generationTime, ...
        'totalRuntime_s',toc(timer),'independentTestAvailable',false);
    save(file,'record','-v7');records=[records;record]; %#ok<AGROW>
    fprintf('STAGE4 DATA COMPLETE %s %.1f s\n',q.id,record.totalRuntime_s);
end
end
