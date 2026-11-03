function varargout=sht_f34_deployment(action,varargin)
%SHT_F34_DEPLOYMENT 正式Excel的完整曲线恢复与独立物理预测。
% 不读取辨识MAT、UQ检查点、试车后验或隐藏真值。ModelState只保存重建
% 曲线所需的参考值/基函数和公开前向模型配置，不保存训练数据或观测值。
switch lower(action)
    case 'tables'
        varargout{1}=local_tables(varargin{1});
    case 'read'
        varargout{1}=local_read(varargin{:});
    case 'activate'
        varargout{1}=local_activate(varargin{1});
    case 'jointmodels'
        varargout{1}=local_joint_models(varargin{:});
    case 'evaluatemodels'
        varargout{1}=local_evaluate_models(varargin{:});
    case 'inspect'
        varargout{1}=local_inspect(varargin{:});
    case 'inheritgeometry'
        c=varargin{1};previous=varargin{2};options=varargin{3};
        assert(previous.modelState.modelMode==options.modelMode&& ...
            strcmp(char(previous.sourceManifest.engine_id(1)),options.engineId), ...
            'SHT:F34Deploy:Lineage','不能跨发动机或模型身份递推。');
        runtime=c.replayAssets.configuration.engine.interface.controlDir;
        for j=1:height(previous.runtimeAssets)
            actual=sht_f33_model_adapt_v2('fileHash', ...
                fullfile(runtime,char(previous.runtimeAssets.file(j))));
            assert(strcmpi(actual,char(previous.runtimeAssets.sha256(j))), ...
                'SHT:F34Deploy:ModelChanged','架次之间公共模型资产变化，需显式评估概率模型迁移。');
        end
        % 架次递推沿上架次已发布的物理节点和幅值基函数，不重新解释样本。
        % 新工况只改变似然，不让同名幅值因覆盖率变化而变成另一个参数。
        fixed=[];
        if isfield(c.priorSchedule,'fixedTransient'),fixed=c.priorSchedule.fixedTransient;end
        c.priorSchedule=previous.modelState.priorSchedule;
        if ~isempty(fixed)
            % 递推的是健康参数概率；本次明确选定的热条件不能被旧后验覆盖。
            c.priorSchedule.fixedTransient=fixed;
            c.priorSchedule.designHealth(59:71)=fixed.value;
        end
        c.familyMap=previous.modelState.familyMap;c.fuelMap=previous.modelState.fuelMap;
        c.parameterContract=previous.parameterDictionary;
        for f={'parameter_id','name','unit','kind','axis_name'}
            if ismember(f{1},c.parameterContract.Properties.VariableNames)
                c.parameterContract.(f{1})=string(c.parameterContract.(f{1}));
            end
        end
        c.uqReferenceResult.estimatedTheta=previous.samples*previous.weights;
        c.replayAssets.steadySchedule=c.priorSchedule;
        varargout{1}=c;
    case 'exportdeterministic'
        prepared=varargin{1};file=varargin{2};c=prepared.context;
        c.priorSchedule=c.uqReferenceResult.finalSchedule;
        c.familyMap=[];c.fuelMap=struct();prepared.context=c;
        tables=local_tables(prepared);
        manifest=table("F33_DETERMINISTIC_EXCEL_ONLY_V1", ...
            c.uqReferenceResult.estimatedKdistEq,prepared.options.modelMode, ...
            string(prepared.contract.referenceResultSha256), ...
            'VariableNames',{'schema_version','K_dist_eq','model_mode','source_result_sha256'});
        writetable(manifest,file,'Sheet','Manifest');
        writetable(tables.ModelState,file,'Sheet','ModelState');
        writetable(tables.RuntimeAssets,file,'Sheet','RuntimeAssets');
        writetable(table((0:158).',c.priorSchedule.designHealth(:), ...
            'VariableNames',{'c_index','k_design'}),file,'Sheet','DesignHealth');
        varargout{1}=file;
    case 'models'
        package=varargin{1};index=varargin{2};
        if package.deterministic
            varargout{1}=struct('schedules',{{package.context.priorSchedule}}, ...
                'recoveries',0.995-package.KdistEq);return;
        end
        m=sht_f33_model_adapt_v2('thetaToModels',package.context,package.posterior.samples(:,index));
        for j=1:numel(index)
            m.schedules{j}=sht_f34_prior('applyShape',m.schedules{j}, ...
                struct('shape',package.posterior.priorShape), ...
                package.posterior.conditionalShapeMean(:,index(j)));
        end
        varargout{1}=m;
    case 'predictpoints'
        % 冷进程没有上游入口的addpath副作用；DLL加载会临时切到运行资产目录。
        addpath(fileparts(mfilename('fullpath')));
        % branch必须来自输入驱动的先验连续预测，不能用测试测量Np选根。
        package=varargin{1};points=varargin{2};branch=varargin{3};index=varargin{4};
        m=sht_f34_deployment('models',package,index);
        session=sht_f33_thermal_equilibrium('open',package.assets,branch,points,'steady');
        cleanup=onCleanup(@()sht_f33_thermal_equilibrium('close',session)); %#ok<NASGU>
        varargout{1}=sht_f33_thermal_equilibrium('batch',session,m.schedules,m.recoveries);
    otherwise
        error('SHT:F34Deploy:Action','未知操作%s。',action);
end
end

function output=local_tables(prepared)
c=prepared.context;a=c.replayAssets;
state=struct('schemaVersion','F34_EXECUTABLE_MODEL_V1', ...
    'modelMode',prepared.options.modelMode,'priorSchedule',c.priorSchedule, ...
    'familyMap',c.familyMap,'fuelMap',c.fuelMap);
if isfield(prepared.options,'businessIdentity')&&isfield(prepared.options.businessIdentity,'currentModelSha256')
    state.currentModelSha256=prepared.options.businessIdentity.currentModelSha256;
end
% 只发布物理求值需要的资产字段，排除上游路径、台架燃油和历史回放。
state.assets=struct('modelMode',prepared.options.modelMode, ...
    'configuration',struct('engine',a.configuration.engine),'personalized',struct( ...
    'health',c.priorSchedule.designHealth, ...
    'profile',sht_f33_model_adapt_v2('buildProfile',c.priorSchedule)), ...
    'steadySchedule',c.priorSchedule);
if isfield(c.priorSchedule,'fixedTransient')
    state.assets.contract=struct('fixedTransient',c.priorSchedule.fixedTransient);
end
reference=state.assets.configuration.engine.transientEffects.clearanceReferenceTable;
if isfield(reference,'runtimeInterpolationCache')
    reference=rmfield(reference,'runtimeInterpolationCache');
end
state.assets.configuration.engine.transientEffects.clearanceReferenceTable=reference;
runtime=a.configuration.engine.interface.controlDir;
state=local_relocate(state,runtime,'@runtime');
text=jsonencode(state);chunkSize=24000;count=ceil(numel(text)/chunkSize);
chunk=strings(count,1);
for i=1:count,chunk(i)=string(text((i-1)*chunkSize+1:min(i*chunkSize,numel(text))));end
output.ModelState=table((1:count).',chunk,'VariableNames',{'chunk_id','json_text'});
names={'GTESS.dll','GTESS.h','blockAndFunctions.h','types_TMATS.H', ...
    'Turboshaft-TS.mdl','HPC02.MAP','HPT02.MAP','LPT02.MAP'};
hash=strings(numel(names),1);
for i=1:numel(names),hash(i)=string(sht_f33_model_adapt_v2('fileHash',fullfile(runtime,names{i})));end
output.RuntimeAssets=table(string(names(:)),hash,'VariableNames',{'file','sha256'});
end

function package=local_read(file,runtime,varargin)
[~,sheets]=xlsfinfo(file);
if ismember('CombinedManifest',sheets)
    assert(~isempty(varargin)&&isstruct(varargin{1}), ...
        'SHT:F34Deploy:TC27Binding','TC27组合读取需显式路线、物理燃油语义及来源/执行关联。');
    o=varargin{1};
    assert(all(isfield(o,{'priorRoute','priorRuntimeBinding','inputFuelKind'}))&& ...
        ismember(o.inputFuelKind,{'physical','source_measurement'}), ...
        'SHT:F34Deploy:FuelMeaning','输入燃油须明确为physical或source_measurement，禁止自动套用台架偏置。');
    o.priorSource='combined';o.priorWorkbook=file;
    b=sht_f3_current_contract('parent',o);
    assert(strcmpi(char(java.io.File(runtime).getCanonicalPath()), ...
        char(java.io.File(o.priorRuntimeBinding.executionRuntimeDirectory).getCanonicalPath())), ...
        'SHT:F34Deploy:ExecutionDirectory','读取参数与实际预测运行目录不是同一显式包。');
    s=b.schedule;sourceFuel=s.fuelBias;
    if strcmp(o.inputFuelKind,'physical'),s.fuelBias.biasNodes=zeros(size(s.fuelBias.biasNodes));end
    package=struct('method','deterministic','deterministic',true,'workbook',file, ...
        'runtimeDirectory',runtime,'thermalFile',b.executionThermalFile,'configurationPending',true, ...
        'context',struct('priorSchedule',s),'KdistEq',b.KdistEq, ...
        'metadata',struct('sourceSchema',b.runtimeAssociation.source.schema, ...
            'inputFuelKind',o.inputFuelKind,'sourceFuelBias',sourceFuel,'uqStatus','not_evaluated_for_transient_combination'), ...
        'runtimeIdentity',b.executionContract,'runtimeAssociation',b.runtimeAssociation, ...
        'executionManifestSHA256',b.executionContract.executionManifestSHA256, ...
        'internalMatRequired',false,'truthRequired',false);return;
end
if ismember('Model',sheets)
    package=local_read_deterministic(file,runtime);return;
end
if ismember('LocalDistribution',sheets)
    package=sht_f34_method_d_artifacts('read',file,runtime);
    package.deterministic=false;package.runtimeDirectory=runtime;return;
end
t=readtable(file,'Sheet','ModelState');[~,order]=sort(t.chunk_id);
state=jsondecode(char(join(string(t.json_text(order)),'')));
assert(strcmp(state.schemaVersion,'F34_EXECUTABLE_MODEL_V1')&&state.modelMode==0, ...
    'SHT:F34Deploy:Model','当前独立交付只验收三部件合同。');
identity=readtable(file,'Sheet','RuntimeAssets');
for i=1:height(identity)
    actual=sht_f33_model_adapt_v2('fileHash',fullfile(runtime,char(identity.file(i))));
    assert(strcmpi(actual,char(identity.sha256(i))), ...
        'SHT:F34Deploy:Asset','公共运行资产身份不符：%s',char(identity.file(i)));
end

state=local_relocate(state,'@runtime',runtime);
% Excel只保存参考间隙原始节点；插值器是进程对象，必须在新进程重建。
state.assets.configuration.engine.transientEffects.clearanceReferenceTable= ...
    sht_prepare_clearance_reference_lookup( ...
    state.assets.configuration.engine.transientEffects.clearanceReferenceTable);
manifest=readtable(file,'Sheet','Manifest');
if strcmp(char(manifest.schema_version(1)),'F33_DETERMINISTIC_EXCEL_ONLY_V1')
    package=struct('context',state,'assets',state.assets,'deterministic',true, ...
        'KdistEq',manifest.K_dist_eq(1),'workbook',file, ...
        'runtimeDirectory',runtime,'internalMatRequired',false,'truthRequired',false);
    return;
end
contract=readtable(file,'Sheet','ParameterDictionary');
for name={'parameter_id','name','unit','kind','axis_name'}
    if ismember(name{1},contract.Properties.VariableNames),contract.(name{1})=string(contract.(name{1}));end
end
context=struct('priorSchedule',state.priorSchedule,'familyMap',state.familyMap, ...
    'fuelMap',state.fuelMap,'parameterContract',contract);
% JSON不保存MATLAB数组方向标记，所有节点和基函数显式恢复为列向量。
for i=1:numel(context.familyMap),context.familyMap(i).basis=context.familyMap(i).basis(:);end
context.fuelMap.basis=context.fuelMap.basis(:);
package=struct('context',context,'assets',state.assets, ...
    'deterministic',false, ...
    'posterior',sht_f34_io('readPosterior',file),'workbook',file, ...
    'runtimeDirectory',runtime,'internalMatRequired',false,'truthRequired',false);
package.method='C';
end

function out=local_inspect(file,varargin)
% 先识别正式格式，再调用已有reader；查看不能隐式加载父数据或物理模型。
[~,sheets]=xlsfinfo(file);
assert(~isempty(sheets),'SHT:F34Deploy:Workbook','无法识别Excel工作表。');
if ismember('CombinedManifest',sheets)
    out=sht_f33_transient_delivery('inspect',[],file,varargin{:});
    out.method='deterministic';out.noDll=true;out.predictionReady=false;
elseif ismember('Model',sheets)
    if ismember('TransientParameters',sheets)
        out=sht_f33_transient_delivery('inspect',[],file);
    else,out=sht_f33_excel_delivery('inspect',file);end
    out.method='deterministic';out.noDll=true;out.predictionReady=false;
elseif ismember('LocalDistribution',sheets)
    out=sht_f34_method_d_artifacts('inspect',file);
elseif all(ismember({'Manifest','ParameterDictionary','PosteriorSamples'},sheets))
    out=sht_f34_io('readPosterior',file);out.method='C';out.noDll=true;
    out.runtimeVerified=false;out.predictionReady=false;
elseif all(ismember({'Manifest','ModelState','RuntimeAssets'},sheets))
    manifest=readtable(file,'Sheet','Manifest');
    assert(strcmp(char(manifest.schema_version(1)),'F33_DETERMINISTIC_EXCEL_ONLY_V1'), ...
        'SHT:F34Deploy:Schema','不支持的历史模型格式。');
    t=readtable(file,'Sheet','ModelState');[~,order]=sort(t.chunk_id);
    out=struct('method','deterministic','manifest',manifest, ...
        'modelState',jsondecode(char(join(string(t.json_text(order)),''))), ...
        'noDll',true,'runtimeVerified',false);
else
    error('SHT:F34Deploy:Schema','不是已支持的确定性、C或D正式Excel。');
end
end

function package=local_read_deterministic(file,runtime)
% 只读核验不加载DLL。标称热资产是公共模型资料，不是训练MAT或隐藏真值。
[~,sheets]=xlsfinfo(file);
if ismember('TransientParameters',sheets)
    combo=sht_f33_transient_delivery('inspect',[],file);
    package=local_read_deterministic(combo.steadyFile,runtime);
    package.workbook=file;package.combinedSteadyFile=combo.steadyFile;
    package.context.priorSchedule.designHealth(59:71)=combo.parameters.value;
    package.context.priorSchedule.fixedTransient=combo.fixedTransient;
    package.runtimeIdentity.fixedTransient=combo.fixedTransient;
    package.combinedMetadata=combo.metadata;return;
end
names={'GTESS.dll','GTESS.h','Turboshaft-TS.mdl','HPC02.MAP','HPT02.MAP','LPT02.MAP'};
thermal=fullfile(runtime,'f3_visser16_parameters.mat');
hash=cellfun(@(n)sht_f33_model_adapt_v2('fileHash',fullfile(runtime,n)),names,'UniformOutput',false);
a.runtimeDirectory=runtime;
a.contract=struct('runtimeFiles',{names},'runtimeHashes',{hash}, ...
    'runtimeVisserAssetSha256',sht_f33_model_adapt_v2('fileHash',thermal));
b=sht_f33_excel_delivery('read',file,a);
saved=load(thermal,'parameterAsset');asset=saved.parameterAsset;
assert(asset.interface.interfaceVersion==2502&&strcmp(asset.flightBuild.identity.variant,'nominal'), ...
    'SHT:F34Deploy:Thermal','需要匹配的三部件标称Visser16热资产。');
for j=1:numel(names)
    key=matlab.lang.makeValidName(names{j});
    assert(strcmpi(asset.flightBuild.identity.runtime.(key),hash{j}), ...
        'SHT:F34Deploy:ThermalIdentity','热参考与所选运行模型不一致：%s。',names{j});
end
% 两份附属头文件由随包不可变清单补齐；不隐式读取历史候选目录。
release=sht_f3_three_component_assets('manifest',runtime);
package=struct('method','deterministic','deterministic',true,'workbook',file, ...
    'runtimeDirectory',runtime,'thermalFile',thermal,'configurationPending',true, ...
    'context',struct('priorSchedule',b.schedule),'KdistEq',b.KdistEq, ...
    'metadata',b.metadata,'runtimeIdentity',a.contract,'runtimeAssociation',b.runtimeAssociation, ...
    'executionManifestSHA256',release.sha256,'internalMatRequired',false,'truthRequired',false);
end

function package=local_activate(package)
if ~isfield(package,'configurationPending')||~package.configurationPending,return;end
runtime=package.runtimeDirectory;s=package.context.priorSchedule;
cfg=sht_default_config(struct('engine',struct('modelMode',0,'runtimeDirectory',runtime), ...
    'plot',struct('enable',false)));
cfg.engine.interface.controlDir=runtime;cfg.engine.modelConfiguration=fullfile(runtime,'Turboshaft-TS.mdl');
[cfg,asset]=sht_configure_transient_heat_state(cfg,package.thermalFile);
cfg.engine.transientEffects.stepInTemplate=sht_build_transient_step_in_template(asset,'joint_full',15);
asset.referenceTable.PT.extrapolationPolicy='continuous_hull_projection';
cfg.engine.transientEffects.clearanceReferenceTable=sht_prepare_clearance_reference_lookup(asset.referenceTable);
cfg.engine.boundary.health=zeros(159,1);cfg.engine.boundary.healthScheduleEnabled=false;
if isfield(s,'fixedTransient'),cfg.engine.boundary.health(59:71)=s.fixedTransient.value;end
cfg.engine.healthScheduleProfile=[];cfg.engine.boundary.Mkg=0;cfg.engine.boundary.hpsPower=0;
cfg.engine.boundary.ptLoadInputMode='torque';cfg.engine.boundary.gtLoadInputMode='torque';
cfg=sht_validate_runtime_config(cfg);
cfg.engine.reynoldsCorrection=sht_f3_reynolds_reference(cfg,1);
package.assets=struct('modelMode',0,'configuration',cfg,'steadySchedule',s,'contract',package.runtimeIdentity, ...
    'personalized',struct('health',s.designHealth,'profile',sht_f33_model_adapt_v2('buildProfile',s)));
package.configurationPending=false;
end

function pool=local_joint_models(package,o)
% 返回真正联合参数模型：C同时抽取主粒子与其条件方向；D使用完整联合矩。
% 所有原始权重保留。部分粒子选择不是重新归一化后的完整后验。
stream=RandStream('mt19937ar','Seed',o.seed);
schedules={};recovery=[];mainIndex=[];drawIndex=[];weights=[];joint=[];sampleValid=[];
if package.deterministic
    schedules={package.context.priorSchedule};recovery=.995-package.KdistEq;
    mainIndex=1;drawIndex=1;weights=1;method='deterministic';
elseif strcmp(package.method,'D')
    d=package.distribution;V=(d.jointCovariance+d.jointCovariance')/2;
    [Q,v]=eig(V,'vector');
    assert(min(v)>=-1e-12*max(1,max(abs(v))),'SHT:F34Deploy:Covariance','D联合协方差实质非正定。');
    joint=d.jointMean(:)+real(Q)*(sqrt(max(real(v),0)).*randn(stream,numel(v),o.dDrawCount));
    sampleValid=all(joint(1:d.explicitDimension,:)>=d.explicitLowerBound(:)& ...
        joint(1:d.explicitDimension,:)<=d.explicitUpperBound(:),1);
    for k=1:o.dDrawCount
        m=sht_f34_method_d_artifacts('model',package,joint(:,k));
        schedules{k}=m.schedules{1};recovery(k)=m.recoveries; %#ok<AGROW>
    end
    mainIndex=1:o.dDrawCount;drawIndex=ones(size(mainIndex));weights=ones(size(mainIndex))/o.dDrawCount;
    method='D_local_joint_gaussian_nonstationarity_limit_retained';
else
    p=package.posterior;index=o.sampleIndices;
    if isempty(index),index=1:numel(p.weights);end
    assert(all(index==fix(index))&&all(index>=1)&all(index<=numel(p.weights))&& ...
        numel(unique(index))==numel(index),'SHT:F34Deploy:SampleIndex','主样本编号不合法。');
    assert(isfield(p,'conditionalGaussianMean')&&isfield(p,'physicalSupport'), ...
        'SHT:F34Deploy:ConditionalMissing','旧后验缺完整有界条件分布，不能伪造全参数区间。');
    m=sht_f33_model_adapt_v2('thetaToModels',package.context,p.samples(:,index));
    for j=1:numel(index)
        i=index(j);
        z=sht_f34_bounded_condition('evaluate',p.conditionalGaussianMean(:,i), ...
            p.conditionalGaussianCovariance(:,:,i),p.physicalSupport, ...
            p.conditionalQuadratureCount,p.conditionalQuadratureSeed,stream,o.conditionalDraws);
        for k=1:o.conditionalDraws
            schedules{end+1}=sht_f34_prior('applyShape',m.schedules{j},struct('shape',p.priorShape),z.draw(:,k)); %#ok<AGROW>
            recovery(end+1)=m.recoveries(j);mainIndex(end+1)=i;drawIndex(end+1)=k; %#ok<AGROW>
            weights(end+1)=p.weights(i)/o.conditionalDraws; %#ok<AGROW>
            joint(:,end+1)=[p.samples(:,i);z.draw(:,k)]; %#ok<AGROW>
        end
    end
    method='C_full_main_and_bounded_conditional_monte_carlo';
end
if isempty(sampleValid),sampleValid=true(size(weights));end
pool=struct('schedules',{schedules},'recoveries',recovery,'weights',weights(:), ...
    'mainIndex',mainIndex(:),'drawIndex',drawIndex(:),'joint',joint, ...
    'method',method,'sampleValid',sampleValid(:),'uncomputedMass',max(0,1-sum(weights)), ...
    'randomState',stream.State,'conditionalMeanOnly',false,'processQAdded',false);
end

function out=local_evaluate_models(assets,points,branch,pool)
% 按独立工况记录失败，不因同批另一点失败而抛弃成功点，也不改变权重。
n=height(points);m=numel(pool.schedules);y=nan(n,4,m);valid=false(n,m);
reason=strings(n,m);detail=cell(n,m);columns={'Np','Ng','Pt3','Tt45'};
started=tic;
if isfield(pool,'sampleValid')&&~any(pool.sampleValid)
    % 全部候选在显式参数域外时，不创建热会话，更不可能冷加载DLL。
    reason(:)="local_gaussian_sample_outside_explicit_parameter_support";
    out=struct('value',y,'valid',valid,'reason',reason,'detail',{detail}, ...
        'candidatePointCount',0,'elapsed_s',toc(started),'fuelCorrectedBy','no_physical_evaluation');
    return;
end
session=sht_f33_thermal_equilibrium('open',assets,branch,points,'steady');
clean=onCleanup(@()sht_f33_thermal_equilibrium('close',session)); %#ok<NASGU>
for k=1:m
    if isfield(pool,'sampleValid')&&~pool.sampleValid(k)
        reason(:,k)="local_gaussian_sample_outside_explicit_parameter_support";continue;
    end
    s=pool.schedules{k};f=s.fuelBias;
    q=min(max(points.Wf_mean/f.wfDesign,min(f.xNodes)),max(f.xNodes));
    physicalFuel=points.Wf_mean-interp1(f.xNodes,f.biasNodes,q,'linear');
    badFuel=~isfinite(physicalFuel)|physicalFuel<=0;
    if ~isfinite(pool.recoveries(k))|| ...
            pool.recoveries(k)<=0||pool.recoveries(k)>1
        reason(:,k)="parameter_sample_outside_physical_input_support";continue;
    end
    if any(badFuel)
        reason(badFuel,k)="fuel_bias_corrected_flow_not_positive";
        good=find(~badFuel);
        if ~isempty(good)
            b=branch;b.pointIds=b.pointIds(good);b.speedSeed=b.speedSeed(good,:);
            b.lowerNp=b.lowerNp(good);b.upperNp=b.upperNp(good);
            one=struct('schedules',{{s}},'recoveries',pool.recoveries(k));
            v=local_evaluate_models(assets,points(good,:),b,one);
            y(good,:,k)=v.value;valid(good,k)=v.valid;reason(good,k)=v.reason;detail(good,k)=v.detail;
        end
        continue;
    end
    try
        b=sht_f33_thermal_equilibrium('batch',session,{s},pool.recoveries(k));c=b.candidate(1);
        for j=1:n
            r=c.diagnostic.records{j};detail{j,k}=r;valid(j,k)=r.valid;
            reason(j,k)=string(r.stop);
            for h=1:4,y(j,h,k)=c.prediction.(columns{h})(j);end
        end
    catch ex
        if ~strcmp(ex.identifier,'SHT:ReynoldsCorrection:EvaluationState'),rethrow(ex);end
        reason(:,k)=string([ex.identifier ': ' ex.message]);
    end
end
out=struct('value',y,'valid',valid,'reason',reason,'detail',{detail}, ...
    'candidatePointCount',n*m,'elapsed_s',toc(started),'fuelCorrectedBy','thermal_equilibrium_batch_once');
end

function value=local_relocate(value,old,new)
if isstruct(value)
    f=fieldnames(value);
    for j=1:numel(value)
        for i=1:numel(f),value(j).(f{i})=local_relocate(value(j).(f{i}),old,new);end
    end
elseif iscell(value)
    for i=1:numel(value),value{i}=local_relocate(value{i},old,new);end
elseif ischar(value)||isstring(value)
    value=strrep(value,old,new);
end
end
