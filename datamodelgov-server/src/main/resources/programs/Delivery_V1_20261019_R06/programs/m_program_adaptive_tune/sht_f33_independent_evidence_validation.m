function result=sht_f33_independent_evidence_validation(resultFile,fullValidationFile,tag)
% 冻结参数后的独立验证：平均稳态点独立求解，小幅片段各自重新初始化积分。
% 与完整历程中截取同一窗口的误差分开报告，不用测试输出拟合参数或选根。
% 瞬态时刻点验证允许Np/Ng作输入；额外稳态预测只用先验全历程预测转速选根。
if strcmpi(resultFile,'confirmedPoints')
    result=local_confirmed_points(fullValidationFile);return;
end
assert(isfile(resultFile)&&isfile(fullValidationFile),'缺少明确指定的冻结结果。');
p=fileparts(mfilename('fullpath'));c=sht_f3_current_contract('paths');
out=fullfile(c.report,'F3_4',['independent_',tag]);
assert(~isfolder(out),'独立验证tag已存在，禁止覆盖。');mkdir(out);
diary(fullfile(out,'run.log'));clean=onCleanup(@()diary('off')); %#ok<NASGU>
t=tic;loaded=load(resultFile,'result');e=loaded.result;
assert(e.options.modelMode==0&&ismember(e.modelRoute,{'steady','transient_instant'})&& ...
    ismember(e.dataMethod,{'steady_only','steady_plus_small_history'}), ...
    '本入口验证三部件四路线，不静默转换其他模型合同。');
f=load(fullValidationFile,'result');full=f.result;
assert(any(strcmpi(cellstr(full.routeTable.result_sha256),sht_f33_model_adapt_v2('fileHash',resultFile))), ...
    '完整回放与冻结辨识结果不匹配。');
a=sht_f32_replay_history('loadAssets',p,struct('modelMode',0, ...
    'priorSource',e.options.priorSource,'priorRoute',e.options.priorRoute, ...
    'priorWorkbook',e.prior.sourceFile));
a.personalized.health=e.priorSchedule.designHealth;
a.personalized.profile=sht_f33_model_adapt_v2('buildProfile',e.priorSchedule);
a.personalized.fuelBias=e.priorSchedule.fuelBias;a.steadySchedule=e.priorSchedule;
sensor=full.measurementAssumptions;schedules={e.priorSchedule,e.finalSchedule};
recoveries=[.995,.995-e.estimatedKdistEq];variants={'prior','estimated'};
rows={};values={};dataResults=struct([]);
for d=1:numel(full.datasets)
    ds=full.datasets(d);h=readtable(ds.sourceFile,'Sheet','history');
    segments=readtable(ds.sourceFile,'Sheet','segments');
    assert(strcmpi(sht_f33_model_adapt_v2('fileHash',ds.sourceFile),ds.sourceSha256),'验证数据已改变。');
    assert(~ismember('Mkg',h.Properties.VariableNames),'当前三部件飞参合同不含Mkg测量。');
    h.Mkg=zeros(height(h),1); % 仅内部已声明的零附件负载，不作为测量通道。
    o=e.options;o.dataMethod='steady_plus_small_history';
    if ~isfield(o,'localThermalWarmup_s'),o.localThermalWarmup_s=0;end
    if isfield(full.options,'integrationStep_s')
        o.historyIntegrationStep_s=full.options.integrationStep_s;
    else
        o.historyIntegrationStep_s=.025;
    end
    ev=sht_f33_model_adapt_v2('prepareEvidence',h,segments,o);points=ev.steadyData;
    branch=struct('pointIds',points.point_id,'speedSeed',[points.Np_mean,points.Ng_mean], ...
        'lowerNp',zeros(height(points),1),'upperNp',inf(height(points),1));
    si=sht_f33_thermal_equilibrium('open',a,branch,points,'transient_instant');
    instant=sht_f33_thermal_equilibrium('batch',si,schedules,recoveries);
    % 选根宽度来自上游合同，不凭测试测量转速调试。
    prior=sht_f33_model_adapt_v2('loadPrior',e.options);
    width=prior.baseResult.options.steadyNpTrainingBranchRelativeHalfWidth;
    branch=sht_f33_thermal_equilibrium('prepare',h,segments,points,a,sensor,width, ...
        ds.sourceSha256,ds.replays.prior);
    ss=sht_f33_thermal_equilibrium('open',a,branch,points,'steady');
    steady=sht_f33_thermal_equilibrium('batch',ss,schedules,recoveries);
    small=sht_f33_small_history_batch(a,ev.historyData.experiments,schedules,recoveries,sensor,o);
    for v=1:2
        names={'Pt3','Tt45','dNp_dt','dNg_dt'};units={'Pa','K','rpm/s','rpm/s'};
        target=[points.Pt3_mean,points.Tt45_mean,zeros(height(points),2)];
        raw=instant.candidate(v).prediction{:,names}-target;
        rows=[rows;local_rows(ds.role,variants{v},'independent_instant_points',names,units,raw,instant.candidate(v).valid)]; %#ok<AGROW>
        names={'Np','Ng','Pt3','Tt45'};units={'rpm','rpm','Pa','K'};
        target=[points.Np_mean,points.Ng_mean,points.Pt3_mean,points.Tt45_mean];
        raw=steady.candidate(v).prediction{:,names}-target;
        rows=[rows;local_rows(ds.role,variants{v},'independent_steady_prediction',names,units,raw,steady.candidate(v).valid)]; %#ok<AGROW>
        for j=1:4
            values{end+1,1}=table(repmat(string(ds.role),height(points),1),repmat(string(variants{v}),height(points),1), ...
                points.point_id,repmat(string(names{j}),height(points),1),target(:,j), ...
                steady.candidate(v).prediction.(names{j}),raw(:,j), ...
                'VariableNames',{'dataset','variant','point_id','channel','measured','predicted','error'}); %#ok<AGROW>
        end
        if small.candidate(v).valid
            raw=small.candidate(v).prediction{:,names}-ev.historyData.measuredOutput;
            raw=raw(ev.historyData.fitMask,:);
        else
            raw=nan(nnz(ev.historyData.fitMask),4);
            warning('SHT:F33Independent:SmallInvalid','%s',small.candidate(v).errorMessage);
        end
        rows=[rows;local_rows(ds.role,variants{v},'independent_small_history',names,units,raw,small.candidate(v).valid)]; %#ok<AGROW>
    end
    dataResults(d).role=ds.role;dataResults(d).steadySource=ev.steadySource;
    dataResults(d).points=points;
    dataResults(d).smallMeta=ev.historyMeta;dataResults(d).instant=instant;
    dataResults(d).steady=steady;dataResults(d).small=small;dataResults(d).rootBranch=branch;
end
metrics=vertcat(rows{:});pointValues=vertcat(values{:});
result=struct('schemaVersion','F33_THREE_INDEPENDENT_EVIDENCE_V1', ...
    'referenceFile',resultFile,'referenceSha256',sht_f33_model_adapt_v2('fileHash',resultFile), ...
    'fullValidationFile',fullValidationFile,'datasets',dataResults,'metrics',metrics, ...
    'pointValues',pointValues,'fitRepeated',false,'testMeasurementsUsedForRoot',false, ...
    'runtime_s',toc(t),'outputDirectory',out);
save(fullfile(out,'result.mat'),'result','-v7.3');
writetable(metrics,fullfile(out,'metrics.csv'));writetable(pointValues,fullfile(out,'point_values.csv'));
disp(metrics);fprintf('独立片段验证耗时 %.3f秒；各行valid单独报告。\n',result.runtime_s);
end

function result=local_confirmed_points(payload)
% 只验证已确认数据与冻结参数；路线沿辨识配置，不把历程伪装为平均点。
assert(isstruct(payload)&&isfield(payload,'result')&&isfield(payload,'validationWorkbook'), ...
    'SHT:F33Independent:Payload','缺少冻结参数或显式测试选择。');
instant=strcmp(payload.result.options.modelRoute,'transient_instant');
result=struct('status','not_provided','metricTable',table(),'pointTable',table(),'historyTable',table(), ...
    'valid',false,'fitRepeated',false,'runtime_s',0,'measurementSpeedsAreInputs',instant, ...
    'testPointSpeedsUsedForRoot',false,'historyInitialMeasuredSpeedUsed',false);
if isempty(payload.validationWorkbook),return;end
assert(isfile(payload.validationWorkbook),'SHT:F33Independent:Missing','确认的测试Excel不存在。');
assert(~strcmpi(sht_f33_model_adapt_v2('fileHash',payload.validationWorkbook), ...
    payload.result.training.sourceSha256),'SHT:F33Independent:SameData','独立测试不能与训练Excel同内容。');
evaluated=sht_f33_model_adapt_v2('frozenEvidence',payload.result,payload.validationWorkbook);
result.status='evaluated_frozen_parameters';result.metricTable=evaluated.metricTable;
result.valid=all([evaluated.evaluation.candidate.valid]);
result.sourceSha256=evaluated.sourceSha256;result.runtime_s=evaluated.runtime_s;
points=evaluated.steadyData;
if instant
    names={'Pt3','Tt45','dNp_dt','dNg_dt'};units={'Pa','K','rpm/s','rpm/s'};
    target=[points.Pt3_mean,points.Tt45_mean,zeros(height(points),2)];
else
    names={'Np','Ng','Pt3','Tt45'};units={'rpm','rpm','Pa','K'};
    target=[points.Np_mean,points.Ng_mean,points.Pt3_mean,points.Tt45_mean];
end
result.metricTable.valid=false(height(result.metricTable),1);
rows=cell(8,1);model={'prior','estimated'};
for k=1:2
    candidate=evaluated.evaluation.candidate(k);
    pointValid=cellfun(@(r)r.valid,evaluated.evaluation.steadyBatch.candidate(k).diagnostic.records);
    block=string(result.metricTable.model)==string(model{k});
    steadyRows=block & string(result.metricTable.block)=="steady_windows";
    result.metricTable.valid(steadyRows)=all(pointValid);
    for j=1:4
        n=height(points);predicted=candidate.steadyPrediction.(names{j});
        role='measured_output';if instant&&j>2,role='zero_acceleration_constraint';end
        rows{4*(k-1)+j}=table(repmat(string(model{k}),n,1),points.point_id, ...
            repmat(string(names{j}),n,1),repmat(string(units{j}),n,1), ...
            repmat(string(role),n,1),target(:,j),predicted,predicted-target(:,j), ...
            pointValid(:),'VariableNames', ...
            {'model','point_id','channel','unit','role','measured_or_constraint','predicted','error','valid'});
    end
    if evaluated.historyMeta.segmentCount>0
        smallValid=evaluated.evaluation.historyBatch.candidate(k).valid;
        result.metricTable.valid(block & ~steadyRows)=smallValid;
        mask=evaluated.historyData.fitMask;
        channels={'Np','Ng','Pt3','Tt45'};hu={'rpm','rpm','Pa','K'};
        if isempty(candidate.historyPrediction),pred=nan(size(evaluated.historyData.measuredOutput));
        else,pred=candidate.historyPrediction{:,channels};end
        for j=1:4
            n=nnz(mask);meas=evaluated.historyData.measuredOutput(mask,j);p=pred(mask,j);
            result.historyTable=[result.historyTable;table(repmat(string(model{k}),n,1), ...
                evaluated.historyData.segmentIndex(mask),find(mask),repmat(string(channels{j}),n,1), ...
                repmat(string(hu{j}),n,1),meas,p,p-meas,repmat(smallValid,n,1), ...
                'VariableNames',{'model','segment_index','record_index','channel','unit', ...
                'measured','predicted','error','valid'})]; %#ok<AGROW>
        end
        result.historyInitialMeasuredSpeedUsed=true;
    end
end
result.pointTable=vertcat(rows{:});
result.rootBranch=evaluated.rootBranch;
result.steadyDiagnostics=evaluated.evaluation.steadyBatch;
end

function rows=local_rows(dataset,variant,block,names,units,raw,valid)
rows=cell(numel(names),1);
for j=1:numel(names)
    x=raw(:,j);rows{j}=table(string(dataset),string(variant),string(block),string(names{j}), ...
        string(units{j}),numel(x),sqrt(mean(x.^2)),mean(x),max(abs(x)),logical(valid), ...
        'VariableNames',{'dataset','variant','block','channel','unit','sample_count','rmse','mean_error','max_error','valid'});
end
end
