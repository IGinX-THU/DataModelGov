function out=Start_FlightModelAdapt_16_IndependentPredictionTask(action,user)
%START_FLIGHTMODELADAPT_16_INDEPENDENTPREDICTIONTASK 自主稳态工况预测同核入口。
% cfg=Start_FlightModelAdapt_16_IndependentPredictionTask('configuration');
% 填写modelWorkbook、runtimeDirectory、inputWorkbook、outputDirectory及runId。
% 可选posteriorWorkbook；没有UQ时只计算确定性输出，绝不生成虚构区间。
% check/estimate不加载DLL；run实际计算；read只读取正式结果Excel。
if nargin<1,action='configuration';end
if strcmpi(action,'configuration'),out=local_defaults();return;end
if nargin<2,user=struct();end
if strcmpi(action,'read'),out=local_read(user);return;end
assert(ismember(lower(action),{'check','estimate','run'}),'SHT:F34NewPoint:Action','未知操作。');
c=local_config(user);started=tic;checked=local_check(c);
estimate=sht_f3_runtime_estimate('prediction',checked.workload,c);
if strcmpi(action,'check'),out=checked;out.estimate=estimate;return;end
if strcmpi(action,'estimate'),out=estimate;return;end
assert(~isfolder(c.outputDirectory)&&~isfile(c.outputDirectory), ...
    'SHT:F34NewPoint:OutputExists','必须使用全新输出目录，不覆盖结果：%s。',c.outputDirectory);
mkdir(c.outputDirectory);
logFile=fullfile(c.outputDirectory,'run.log');diary(logFile);
cleanup=onCleanup(@()diary('off')); %#ok<NASGU>
fprintf('自主稳态预测 %s：%d工况；预计 %.1f 至 %.1f 秒（工程范围）。\n', ...
    c.runId,height(checked.points),estimate.totalRange_s);
manifest=struct('schema','F3_INPUT_ONLY_STEADY_PREDICTION_R042','runId',c.runId, ...
    'status','running','startedAt',datestr(now,31),'configuration',c, ...
    'identity',checked.identity,'estimate',estimate,'resultAvailable',false, ...
    'statisticalCalibrationConfirmed',false,'observedOutputsUsed',false);
if isfield(checked.model.metadata,'sourceSchema')
    manifest.parentRuntimeAssociation=checked.model.runtimeAssociation;
    manifest.inputFuelKind=c.inputFuelKind;
end
local_json(fullfile(c.outputDirectory,'run_manifest.json'),manifest);
try
    model=sht_f34_deployment('activate',checked.model);
    seed=sht_f34_input_point_seed('solve',model,checked.points,c);
    n=height(checked.points);det=nan(n,4);detReason=strings(n,1);
    for j=1:n
        if seed.valid(j),det(j,:)=seed.chosen{j}.value(1,:,1);detReason(j)=seed.chosen{j}.reason(1);
        else,detReason(j)="all_input_only_initial_guesses_failed";end
    end
    deterministic=table(checked.points.point_id,det(:,1),det(:,2),det(:,3),det(:,4), ...
        seed.valid,seed.rootCount,detReason,'VariableNames', ...
        {'point_id','Np_rpm','Ng_rpm','Pt3_eq_Pa','Tt45_K','success','distinct_roots','reason'});
    pool=[];sampleOutput=table();intervals=table();mass=table();inputAudit=table();coverage=table();
    predictionTime=0;extraTime=0;parameterTable=table();
    if ~isempty(checked.posterior)
        q=checked.posterior;pool=sht_f34_deployment('jointModels',q,c);
        parameterTable=local_parameter_table(pool,q);
        for j=1:n
            p=checked.points(j,:);branch=local_branch(seed.branch,j);
            if ~seed.valid(j)
                mass=[mass;local_mass(p.point_id,0,sum(pool.weights),pool.uncomputedMass)]; %#ok<AGROW>
                continue;
            end
            r=sht_f34_deployment('evaluateModels',q.assets,p,branch,pool);
            predictionTime=predictionTime+r.elapsed_s;
            values=reshape(r.value,4,[]);valid=r.valid(:)&all(isfinite(values),1)';
            successMass=sum(pool.weights(valid));failedMass=sum(pool.weights(~valid));
            mass=[mass;local_mass(p.point_id,successMass,failedMass,pool.uncomputedMass)]; %#ok<AGROW>
            sampleOutput=[sampleOutput;table(repmat(p.point_id,numel(pool.weights),1), ...
                (1:numel(pool.weights))',pool.mainIndex,pool.drawIndex,pool.weights,valid, ...
                values(1,:)',values(2,:)',values(3,:)',values(4,:)',r.reason(:), ...
                'VariableNames',{'point_id','joint_sample','main_sample','conditional_draw','original_weight', ...
                'success','Np_rpm','Ng_rpm','Pt3_eq_Pa','Tt45_K','reason'})]; %#ok<AGROW>
            coverage=[coverage;local_coverage(p.point_id,r,pool)]; %#ok<AGROW>
            if ~any(valid),continue;end
            label='computed_success_subset';
            if successMass>=1-1e-12,label='all_configured_joint_samples';end
            v=sht_f34_prediction('mixtureInterval',values(:,valid),pool.weights(valid),zeros(4));
            intervals=[intervals;local_interval(p.point_id,'parameter',v,label,successMass)]; %#ok<AGROW>
            if c.includeErrorLayers
                % 输入前向响应在确定性模型处计算，是公开的局部近似，不重用训练灵敏度。
                [ci,cm,co,audit,t]=local_errors(model,p,branch,det(j,:)',c);
                extraTime=extraTime+t;inputAudit=[inputAudit;audit]; %#ok<AGROW>
                if all(isfinite(ci(:)))
                    v=sht_f34_prediction('mixtureInterval',values(:,valid),pool.weights(valid),ci+cm);
                    intervals=[intervals;local_interval(p.point_id,'physical',v,label,successMass)]; %#ok<AGROW>
                    v=sht_f34_prediction('mixtureInterval',values(:,valid),pool.weights(valid),ci+cm+co);
                    intervals=[intervals;local_interval(p.point_id,'measured',v,label,successMass)]; %#ok<AGROW>
                end
            end
        end
    end
    file=fullfile(c.outputDirectory,'prediction.xlsx');
    contract=table("F3_AUTONOMOUS_STEADY_PREDICTION_V1",string(c.runId), ...
        string(checked.identity.modelSha256),string(checked.identity.posteriorSha256), ...
        false,false,false,"nominal_Visser16_full_equilibrium", ...
        "success_subset_when_failed_mass_positive", ...
        'VariableNames',{'schema','run_id','model_sha256','posterior_sha256', ...
        'measured_output_used','training_mat_required','statistical_calibration_confirmed', ...
        'thermal_model','interval_scope_rule'});
    tables=struct('Contract',contract,'Inputs',checked.points,'Deterministic',deterministic, ...
        'SeedAudit',seed.audit,'Intervals',intervals,'SampleOutputs',sampleOutput, ...
        'WeightMass',mass,'JointParameters',parameterTable,'InputErrorAudit',inputAudit,'Coverage',coverage);
    fields=fieldnames(tables);
    for k=1:numel(fields)
        t=tables.(fields{k});if width(t)>0,writetable(t,file,'Sheet',fields{k});end
    end
    % 完整数值读回后才发布可用状态。MAT只保存调试详情，不是下游读取前提。
    restored=local_read(file);
    assert(isequaln(restored.Deterministic.success,deterministic.success)&& ...
        local_equal_numeric(restored.Deterministic{:,2:5},deterministic{:,2:5}), ...
        'SHT:F34NewPoint:RoundTrip','确定性预测Excel读回不一致。');
    save(fullfile(c.outputDirectory,'prediction_debug.mat'),'seed','pool','checked','tables','-v7.3');
    manifest.status='completed';manifest.resultAvailable=true;manifest.finishedAt=datestr(now,31);
    manifest.elapsed_s=toc(started);manifest.seedElapsed_s=seed.elapsed_s;
    manifest.parameterPropagation_s=predictionTime;manifest.errorResponse_s=extraTime;
    manifest.resultWorkbook=file;manifest.resultSha256=sht_f33_model_adapt_v2('fileHash',file);
    manifest.solvedPointCount=nnz(seed.valid);manifest.unsolvedPointCount=nnz(~seed.valid);
    manifest.uqUsed=~isempty(checked.posterior);manifest.successMass=mass;
    manifest.limitations={'No prediction implies unique steady root', ...
        'C finite joint Monte Carlo and bounded conditional approximation retained', ...
        'D local Gaussian and possible nonstationarity retained', ...
        'Input response linearized at deterministic solution', ...
        'Individual transient correction parameters remain zero in this steady contract'};
    if isfield(model.metadata,'sourceSchema')
        manifest.limitations{end}='Selected combined parent 13 transient coefficients remain fixed; no joint transient UQ';
    end
    local_json(fullfile(c.outputDirectory,'run_manifest.json'),manifest);
    out=struct('manifest',manifest,'tables',tables,'workbook',file);
    fprintf('预测结束：%d/%d工况求得稳态解，总耗时 %.2f秒。\n',nnz(seed.valid),n,manifest.elapsed_s);
catch ex
    manifest.status='failed';manifest.elapsed_s=toc(started);
    manifest.errorIdentifier=ex.identifier;manifest.errorMessage=ex.message;
    local_json(fullfile(c.outputDirectory,'run_manifest.json'),manifest);rethrow(ex);
end
end

function c=local_defaults()
c=struct('modelWorkbook','','posteriorWorkbook','','runtimeDirectory','','inputWorkbook','', ...
    'outputDirectory','','runId','','sampleIndices',[],'conditionalDraws',4,'dDrawCount',256, ...
    'seed',340916,'seedScales',[1,.8,1.1],'npBounds',[5000,40000], ...
    'includeErrorLayers',true,'modelDiscrepancyFraction',[.001,.001,.003,.0015], ...
    'modelPosteriorBinding',struct(),'parentRoute','transient_instant', ...
    'parentRuntimeBinding',struct(),'inputFuelKind','model_measurement');
c.inputUnits=struct('Altitude_mean','m','Mach_mean','1','Pamb_mean','Pa', ...
    'Tamb_mean','K','Tt1_mean','K','Mkp_mean','N*m','Wf_mean','kg/s');
end

function c=local_config(u)
c=local_defaults();assert(isstruct(u)&&isscalar(u),'配置必须为标量结构体。');
assert(all(ismember(fieldnames(u),fieldnames(c))),'SHT:F34NewPoint:Config','配置含未知字段。');
for f=fieldnames(u)',c.(f{1})=u.(f{1});end
for f={'modelWorkbook','runtimeDirectory','inputWorkbook','outputDirectory','runId'}
    assert(ischar(c.(f{1}))&&~isempty(strtrim(c.(f{1}))),'SHT:F34NewPoint:Config','必须填写%s。',f{1});
end
validateattributes(c.conditionalDraws,{'numeric'},{'scalar','positive','integer'});
validateattributes(c.dDrawCount,{'numeric'},{'scalar','positive','integer'});
validateattributes(c.seed,{'numeric'},{'scalar','nonnegative','integer'});
validateattributes(c.modelDiscrepancyFraction,{'numeric'},{'numel',4,'nonnegative','finite'});
assert(numel(fullfile(c.outputDirectory,'prediction.xlsx'))<=240,'SHT:F34NewPoint:Path','请使用不超过240字符的输出Excel路径。');
assert(isfolder(fileparts(c.outputDirectory)),'SHT:F34NewPoint:Parent','输出父目录必须已存在。');
end

function q=local_check(c)
points=readtable(c.inputWorkbook,'Sheet','Inputs');
points=sht_f34_input_point_seed('validate',points,c.inputUnits);
binding={};
if ~isempty(fieldnames(c.parentRuntimeBinding))
    binding={struct('priorRoute',c.parentRoute,'priorRuntimeBinding',c.parentRuntimeBinding, ...
        'inputFuelKind',c.inputFuelKind)};
end
model=sht_f34_deployment('read',c.modelWorkbook,c.runtimeDirectory,binding{:});
assert(model.deterministic,'SHT:F34NewPoint:Model','modelWorkbook必须为确定性模型Excel。');
if isfield(model.metadata,'sourceSchema')&&strcmp(model.metadata.sourceSchema,'SHT_TC27_COMBINED_TRANSIENT_EXCEL_V1')
    assert(isempty(c.posteriorWorkbook),'SHT:F34NewPoint:CombinedUQ', ...
        '该TC27组合未有覆盖固定13瞬态参数的后验，不能借父稳态UQ生成组合区间。');
end
posterior=[];ph='';jointCount=0;method='none';
mh=sht_f33_model_adapt_v2('fileHash',c.modelWorkbook);
if ~isempty(c.posteriorWorkbook)
    posterior=sht_f34_deployment('read',c.posteriorWorkbook,c.runtimeDirectory);
    assert(~posterior.deterministic,'SHT:F34NewPoint:Posterior','后验文件不能是确定性模型。');
    ph=sht_f33_model_adapt_v2('fileHash',c.posteriorWorkbook);
    % 已冻结旧Excel没有模型SHA字段时，要求调用方显式声明关联依据，不改签旧结果。
    binding=c.modelPosteriorBinding;
    assert(isstruct(binding)&&all(isfield(binding,{'modelSha256','posteriorSha256','basis'}))&& ...
        strcmpi(binding.modelSha256,mh)&&strcmpi(binding.posteriorSha256,ph)&& ...
        ~isempty(strtrim(char(binding.basis))),'SHT:F34NewPoint:Binding', ...
        '需要modelPosteriorBinding明确绑定两份所选Excel的SHA256并提供关联依据。');
    if strcmp(posterior.method,'C'),state=posterior.posterior.modelState;
    else,state=posterior.modelState;end
    if isfield(state,'currentModelSha256')
        assert(strcmpi(state.currentModelSha256,mh),'SHT:F34NewPoint:ModelConflict','后验内模型SHA与所选模型冲突。');
    end
    if strcmp(posterior.method,'C')
        count=numel(posterior.posterior.weights);
        if ~isempty(c.sampleIndices),count=numel(c.sampleIndices);end
        jointCount=count*c.conditionalDraws;method='C';
    else,jointCount=c.dDrawCount;method='D';end
end
names={'Start_FlightModelAdapt_16_IndependentPredictionTask.m','sht_f34_deployment.m', ...
    'sht_f34_input_point_seed.m','sht_f34_prediction.m','sht_f33_thermal_equilibrium.m', ...
    'sht_thermal_equilibrium_solve.m','sht_engine_derivative.m','sht_f34_bounded_condition.m', ...
    'sht_f34_method_d_artifacts.m'};
sha=cellfun(@(f)sht_f33_model_adapt_v2('fileHash',fullfile(fileparts(mfilename('fullpath')),f)),names,'UniformOutput',false);
identity=struct('modelSha256',mh,'posteriorSha256',ph, ...
    'inputSha256',sht_f33_model_adapt_v2('fileHash',c.inputWorkbook), ...
    'sourceFiles',{names},'sourceHashes',{sha});
q=struct('points',points,'model',model,'posterior',posterior,'identity',identity,'noDll',true, ...
    'workload',struct('pointCount',height(points),'seedAttempts',numel(c.seedScales), ...
    'jointCount',jointCount,'inputDirections',7*double(c.includeErrorLayers&&jointCount>0),'method',method));
end

function b=local_branch(b,j)
b.pointIds=b.pointIds(j);b.speedSeed=b.speedSeed(j,:);b.lowerNp=b.lowerNp(j);b.upperNp=b.upperNp(j);
end

function t=local_mass(id,success,failed,uncomputed)
assert(abs(success+failed+uncomputed-1)<1e-10,'SHT:F34NewPoint:Mass','后验质量不守恒。');
t=table(id,success,failed,uncomputed,'VariableNames',{'point_id','success_mass','failed_mass','uncomputed_mass'});
end

function t=local_interval(id,layer,v,scope,mass)
t=table(repmat(id,4,1),repmat(string(layer),4,1),["Np";"Ng";"Pt3_eq";"Tt45"], ...
    ["rpm";"rpm";"Pa";"K"],v.mean(:),v.lower95(:),v.upper95(:), ...
    repmat(string(scope),4,1),repmat(mass,4,1),'VariableNames', ...
    {'point_id','layer','channel','unit','mean','lower95','upper95','scope','success_mass'});
end

function t=local_parameter_table(pool,q)
names=string(q.context.parameterContract.parameter_id(:));
if strcmp(q.method,'C'),rank=size(q.posterior.priorShape.basis,2);else,rank=size(q.shape.basis,2);end
for k=1:rank,names(end+1)=sprintf('conditional_z%03d',k);end
t=table();
for k=1:size(pool.joint,2)
    t=[t;table(repmat(k,numel(names),1),names,pool.joint(:,k), ...
        repmat(pool.weights(k),numel(names),1),'VariableNames', ...
        {'joint_sample','parameter_id','value','original_weight'})]; %#ok<AGROW>
end
end

function [ci,cm,co,audit,elapsed]=local_errors(model,p,branch,base,c)
started=tic;sensor=sht_f31_flight_measurement('publicAssumptions', ...
    sht_f31_flight_measurement('model',3201001,'F32-MEASUREMENT-PRIOR',false));
names={'Altitude','Mach','Ps0','Ts_amb','Tt1','Mkp','Wf'};
columns={'Altitude_mean','Mach_mean','Pamb_mean','Tamb_mean','Tt1_mean','Mkp_mean','Wf_mean'};
ci=zeros(4);cm=zeros(4);co=zeros(4);audit=table();
pool=sht_f34_deployment('jointModels',model,c);
for k=1:7
    i=find(string(sensor.name)==names{k});assert(numel(i)==1,'传感器先验必须唯一。');
    bias=sensor.totalBiasHalfWidth(i)/sqrt(3);
    if strcmp(names{k},'Wf'),bias=0;end % 燃油公共偏置已在后验内，只附加白噪声。
    variance=bias^2+sensor.noiseStd(i)^2/p.sample_count;
    step=max([.2*sensor.totalBiasHalfWidth(i),2*sensor.noiseStd(i),1e-7]);
    modified=p;modified.(columns{k})=modified.(columns{k})+step;
    r=sht_f34_deployment('evaluateModels',model.assets,modified,branch,pool);
    success=r.valid(1);g=nan(4,1);
    if success,g=(reshape(r.value,4,1)-base)/step;ci=ci+variance*(g*g');else,ci(:)=NaN;end
    audit=[audit;table(p.point_id,string(names{k}),variance,step,success,r.reason(1), ...
        'VariableNames',{'point_id','input','variance','difference_step','success','reason'})]; %#ok<AGROW>
end
outputs={'Np','Ng','Pt3_eq','Tt45'};
for k=1:4
    i=find(string(sensor.name)==outputs{k});assert(numel(i)==1,'输出传感器先验必须唯一。');
    co(k,k)=sensor.totalBiasHalfWidth(i)^2/3+sensor.noiseStd(i)^2/p.sample_count;
    cm(k,k)=(c.modelDiscrepancyFraction(k)*sensor.designReference(i))^2;
end
elapsed=toc(started);
end

function t=local_coverage(id,r,pool)
t=table();axis={'inlet_corrected_mass_flow','burner_inlet_corrected_mass_flow', ...
    'gt_pt_duct_corrected_mass_flow','pt_nozzle_duct_corrected_mass_flow'};
for k=1:numel(pool.schedules)
    if ~r.valid(k),continue;end
    rec=r.detail{1,k};pr=rec.prediction;profile=sht_f33_model_adapt_v2('buildProfile',pool.schedules{k});
    for j=1:numel(profile.parameters)
        e=profile.parameters(j);a=char(e.axisName);coordinate=NaN;
        if ismember(a,pr.Properties.VariableNames),coordinate=pr.(a);end
        % 曲线坐标词典由现有profile给出，未知映射保留NaN而不假定覆盖。
        if strcmp(a,'hpc_relative_corrected_speed'),coordinate=pr.ac_corrected_speed;end
        if strcmp(a,'gt_pressure_ratio'),coordinate=pr.gt_total_pressure_ratio;end
        if strcmp(a,'pt_pressure_ratio'),coordinate=pr.pt_total_pressure_ratio;end
        for h=1:numel(axis),if strcmp(a,axis{h}),coordinate=pr.(axis{h});end,end
        t=[t;table(id,k,e.cIndex,string(a),coordinate,min(e.xNodes),max(e.xNodes), ...
            isfinite(coordinate)&&coordinate>=min(e.xNodes)&&coordinate<=max(e.xNodes), ...
            'VariableNames',{'point_id','joint_sample','c_index','axis','query','lower_node','upper_node','inside_nodes'})]; %#ok<AGROW>
    end
end
end

function r=local_read(value)
if isstruct(value),file=fullfile(value.outputDirectory,'prediction.xlsx');else,file=char(value);end
[~,sheets]=xlsfinfo(file);assert(ismember('Contract',sheets),'SHT:F34NewPoint:Read','没有正式预测合同表。');
r=struct();for k=1:numel(sheets),r.(sheets{k})=readtable(file,'Sheet',sheets{k});end
assert(strcmp(string(r.Contract.schema(1)),"F3_AUTONOMOUS_STEADY_PREDICTION_V1"), ...
    'SHT:F34NewPoint:Schema','不是本入口预测结果。');
if isfield(r,'WeightMass')
    t=r.WeightMass;assert(all(abs(t.success_mass+t.failed_mass+t.uncomputed_mass-1)<1e-10),'读回权重不守恒。');
end
r.noDll=true;r.workbook=file;
end

function yes=local_equal_numeric(a,b)
yes=isequal(size(a),size(b))&&isequal(isnan(a),isnan(b));
if yes,mask=isfinite(a)&isfinite(b);yes=all(abs(a(mask)-b(mask))<=1e-10*max(1,abs(b(mask))));end
end

function local_json(file,value)
fid=fopen(file,'wb');assert(fid>=0,'不能写运行记录。');cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fwrite(fid,unicode2native(jsonencode(value),'UTF-8'),'uint8');
end
