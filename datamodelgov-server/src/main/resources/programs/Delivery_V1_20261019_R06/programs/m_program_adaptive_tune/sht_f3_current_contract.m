function out=sht_f3_current_contract(action,varargin)
% 三部件后续业务的集中路径及资产合同。不调用造数，不写上游结果。
p=fileparts(mfilename('fullpath'));a=sht_f3_three_component_assets('paths');
switch lower(action)
    case 'paths'
        out=struct('modelMode',0,'runTag','R012', ...
            'middle',fullfile(a.middle,'F3_3_6_R012'), ...
            'report',fullfile(fileparts(p),'report_outputs','three_component','T3V1_R012'), ...
            'training',fullfile(a.legacyData,'formal_R011','flight_data_3p1_identification_history.xlsx'), ...
            'test',fullfile(a.legacyData,'formal_R011','flight_data_3p1_independent_validation_history.xlsx'));
        if strcmp(a.packageId,'F3_DLL_MAIN_20261010')
            % 输入仍明确来自原测量交付；新计算及报告不写回历史批次。
            out.runTag='DLL_MAIN_20261010';out.middle=fullfile(a.buildRoot,'business');
            out.report=fullfile(a.report,'business');
        end
    case 'parent'
        % 纯Excel恢复；允许已核定文件同字节搬迁，不读未选择的台架结果。
        out=local_parent(varargin{1},a);
    case 'fixedtransient'
        % 固定条件不是新增待估参数。仅接受完整物理编号和明确的来源身份。
        out=local_fixed_transient(varargin{:});
    case 'completescheduledefinition'
        % 仅关联调用方明确提供的同次完整参数定义，不读取当前默认或猜设计点。
        out=local_complete_schedule_definition(varargin{:});
    case 'runtimeidentity'
        sht_f3_three_component_assets('verifyRuntime');
        out=local_runtime(a);
    case 'assets'
        o=varargin{1};parent=local_parent(o,a);s=parent.schedule;file=parent.file;
        s.modelMode=0;s.designHealth=s.designHealth(:);
        fixed=local_fixed_transient(s.designHealth,parent.sha256);
        s.fixedTransient=fixed;
        s.fuelBias.biasNodes=zeros(size(s.fuelBias.biasNodes));
        thermalFile=a.visserAsset;
        if isfield(parent,'executionThermalFile'),thermalFile=parent.executionThermalFile;end
        cfg=sht_f3_three_component_assets('config',3,'joint_full',thermalFile);
        cfg.engine.reynoldsCorrection=sht_f3_reynolds_reference(cfg,1);
        identity=local_runtime(a);names=identity.contract.runtimeFiles;h=identity.contract.runtimeHashes;
        if isfield(parent,'executionContract')
            identity.contract=parent.executionContract;
            names=identity.contract.runtimeFiles;h=identity.contract.runtimeHashes;
        end
        out=struct('modelMode',0,'programDirectory',p,'configuration',cfg, ...
            'paths',struct('visserAsset',thermalFile,'steadyContract',file), ...
            'steadySchedule',s,'transientParameterTable',table(), ...
            'contract',struct('modelMode',0,'stateCount',16,'priorSource',o.priorSource, ...
            'priorRoute',o.priorRoute,'steadySelection',[o.priorSource '/' o.priorRoute], ...
            'steadyContractSha256',sht_tc27_file_identity(file),'runtimeFiles',{names}, ...
            'runtimeHashes',{h},'runtimeVisserAssetSha256',sht_tc27_file_identity(thermalFile), ...
            'parentRuntimeAssociation',parent.runtimeAssociation, ...
            'fixedTransient',fixed,'truthDataAccessed',false));
        out.personalized=struct('id','three_component_personalized', ...
            'description','HPC/GT/PT nominal Visser16; independent flight fuel prior', ...
            'health',s.designHealth,'profile',sht_tc27_schedule_profile(s), ...
            'scheduleEnabled',true,'fuelBias',s.fuelBias);
        out.zero=struct('id','three_component_zero','description','HPC/GT/PT zero health', ...
            'health',zeros(159,1),'profile',[],'scheduleEnabled',false,'fuelBias',s.fuelBias);
    otherwise
        error('SHT:F3:ContractAction','未知业务合同操作：%s',action);
end
end

function out=local_runtime(a)
names={'GTESS.dll','GTESS.h','Turboshaft-TS.mdl','HPC02.MAP','HPT02.MAP','LPT02.MAP'};
h=cellfun(@(n)sht_tc27_file_identity(fullfile(a.runtime,n)),names,'UniformOutput',false);
release=sht_f3_three_component_assets('manifest');
out=struct('modelMode',0,'runtimeDirectory',a.runtime,'contract',struct('modelMode',0,'stateCount',16, ...
    'runtimeFiles',{names},'runtimeHashes',{h}, ...
    'runtimeVisserAssetSha256',sht_tc27_file_identity(a.visserAsset), ...
    'executionManifestSHA256',release.sha256));
end

function p=local_parent(o,a)
assert(ismember(o.priorSource,{'2p4','2p7','flight','combined'})&& ...
    ismember(o.priorRoute,{'steady','transient_instant'}),'SHT:F3:Source','父来源或路径不支持。');
file='';if isfield(o,'priorWorkbook'),file=char(o.priorWorkbook);end
if strcmp(o.priorSource,'combined')
    assert(~isempty(file)&&isfile(file),'SHT:F3:ParentMissing','必须明确选择组合父Excel。');
    [~,sheets]=xlsfinfo(file);
    if ismember('CombinedManifest',sheets)
        % TC27单Excel由其公开reader恢复，不回调F33而形成分派递归。
        p=local_tc27_parent(o,a,file);return;
    end
    combo=sht_f33_transient_delivery('inspect',[],file);
    steadyOptions=o;steadyOptions.priorSource='flight';
    steadyOptions.priorWorkbook=combo.steadyFile;
    p=local_flight_parent(steadyOptions,a,combo.steadyFile);
    p.source='combined';p.file=file;p.sha256=combo.sha256;
    p.steadyFile=combo.steadyFile;p.steadySha256=combo.steadySha256;
    p.schedule.designHealth(59:71)=combo.parameters.value;
    p.schedule.fixedTransient=local_fixed_transient(p.schedule.designHealth,combo.sha256);
    p.baseResult.finalSchedule=p.schedule;
    p.transientTreatment='fixed_selected_combined_parent';
    p.runtimeAssociation.combinedSha256=combo.sha256;
    p.runtimeAssociation.steadySha256=combo.steadySha256;
    return;
end

if strcmp(o.priorSource,'flight')
    p=local_flight_parent(o,a,file);return;
end

if strcmp(o.priorSource,'2p4')
    if strcmp(o.priorRoute,'steady')
        fallback=a.steadyWorkbook;expected='F31A98AAD0193683371E633EB15B854F35C00520472D154D54881D805D7AA7DC';
    else
        fallback=a.instantWorkbook;expected='5F2EAAF8CC56AADF4D9E82FE2BA15D11F09798B57396D7534A4CB70B404C9634';
    end
else
    fallback=a.tc27Workbook;expected='CD5BFF02006294D3EE92F29B95F4DB5D30C44C0498A450AE52C3D89FDCD32663';
end

if isempty(file),file=fallback;end
assert(isfile(file),'SHT:F3:ParentMissing','父Excel不存在：%s',file);
raw=readtable(file,'Sheet','CorrectionSchedule');
assert(ismember('c_index',raw.Properties.VariableNames),'SHT:F3Task:ParentSchema','父文件缺少物理编号。');
v='correction_value';if ismember('value',raw.Properties.VariableNames),v='value';end
assert(ismember(v,raw.Properties.VariableNames),'SHT:F3Task:ParentSchema','父文件缺少修正值。');
assert(~any(abs(raw.(v)(raw.c_index>=58 & raw.c_index<=70))>0), ...
    'SHT:F3Task:NonzeroTransientParent','尚未支持非零个体瞬态父参数，禁止静默清零。');
[~,sheets]=xlsfinfo(file);unsupported=contains(lower(string(sheets)),{'transient','thermal','individual'});
assert(~any(unsupported(:)),'SHT:F3Task:ParentSchema','父Excel含未支持的瞬态声明。');
h=sht_tc27_file_identity(file);
if strcmp(o.priorSource,'2p4')
    d=sht_load_2p4_deterministic_delivery(o.priorRoute,file,'formal');
    assert(d.manifest.model_mode(1)==0,'SHT:F3Task:ParentModel','父模型不是三部件。');
    assert(all(string(raw.correction_unit)=="1"),'SHT:F3Task:ParentUnit','发动机修正系数必须无量纲。');
    bias=readtable(file,'Sheet','MeasurementBias');
    assert(all(string(bias.axis_unit)=="1")&&all(string(bias.axis_name)=="measured_wf_ratio"), ...
        'SHT:F3Task:ParentUnit','燃油偏置横坐标必须为测量燃油/设计燃油，无量纲。');
    base=d.model;s=base.finalSchedule;
else
    d=sht_tc27_delivery('read',[],file);
    assert(strcmp(d.route,o.priorRoute)&&ismember(d.method,{'I','II'}), ...
        'SHT:F3Task:ParentRoute','TC27路线须与显式选择一致，方法为I或II。');
    assert(d.thermalMode==3,'SHT:F3Task:ParentThermal','本批只支持标称Visser三部件热合同。');
    s=d.finalSchedule;
    % 只取公共工程定义，不伪造TC24训练结果或借用未选中的父Excel。
    opt=sht_steady_model_adapt_v2_common('defaultoptions',o.priorRoute);
    opt.modelMode=0;opt.inletBoundaryMode=1;opt.estimateInletPressureLoss=true;
    opt.includePt2Residual=false;
    par=sht_steady_model_adapt_v2_common('parameterdefinition',opt);
    base=struct('options',opt,'finalSchedule',s,'parameterDefinition',par, ...
        'route',o.priorRoute,'runId',d.runId,'npBranchModel',d.npBranchModel);
end
assert(numel(s.designHealth)==159&&all(isfinite(s.designHealth))&&all(s.designHealth(59:71)==0), ...
    'SHT:F3Task:ParentDictionary','父模型字典不符合三部件159维及零个体瞬态合同。');
local_validate_schedule(s,raw,o.priorSource);
association=local_parent_runtime(file,h,expected,o,a);
p=struct('source',o.priorSource,'route',o.priorRoute,'file',file,'sha256',h, ...
    'runId',d.runId,'schedule',s,'baseResult',base,'benchFuelBiasInherited',false, ...
    'runtimeAssociation',association, ...
    'transientTreatment','explicit_nominal_zero_supported_parent_only');
end

function p=local_tc27_parent(o,a,file)
% 来源严格按原TC27运行包恢复；跨包执行是新的显式重评价，不改签原模型。
b=struct();if isfield(o,'priorRuntimeBinding'),b=o.priorRuntimeBinding;end
required={'sourceRuntimeDirectory','executionRuntimeDirectory', ...
    'executionThermalRuntimeDirectory','executionThermalFile', ...
    'reevaluateModelParameters','ptReferencePolicy','executionBoundary','basis'};
assert(isstruct(b)&&isscalar(b)&&all(isfield(b,required))&& ...
    ~isempty(strtrim(char(b.basis))),'SHT:F3:G01Binding', ...
    'TC27组合父需显式提供来源包、F3执行包、配对热包/热文件、重评价声明和依据。');
assert(islogical(b.reevaluateModelParameters)&&isscalar(b.reevaluateModelParameters)&& ...
    b.reevaluateModelParameters,'SHT:F3:G01Reevaluation', ...
    '本入口跨阶段执行必须显式允许reevaluateModelParameters；不能替换原生成身份。');
assert(strcmp(char(b.ptReferencePolicy),'continuous_hull_projection'), ...
    'SHT:F3:G01PTPolicy','本批只能执行已确认的PT连续凸包投影策略。');
boundary=b.executionBoundary;
assert(isstruct(boundary)&&isscalar(boundary)&&all(isfield(boundary, ...
    {'mean_inlet_recovery','backpressure_design_Pa','design_power_W','K_dist_eq'})), ...
    'SHT:F3:G01Boundary','台架组合未定义飞行安装边界，需显式提供本次恢复/背压/功率/装机损失。');
v=[boundary.mean_inlet_recovery,boundary.backpressure_design_Pa, ...
    boundary.design_power_W,boundary.K_dist_eq];
assert(isnumeric(v)&&isreal(v)&&numel(v)==4&&all(isfinite(v))&& ...
    all(abs(v(1:3)-[.995,1500,2176600])<1e-10)&&v(1)-v(4)>0&&v(1)-v(4)<=1, ...
    'SHT:F3:G01Boundary','本批物理核心支持0.995/1500Pa/2176600W；不得用默认值覆盖不匹配的显式边界。');
model=sht_tc27_transient_combined_delivery('read',[],file, ...
    struct('runtimeDirectory',char(b.sourceRuntimeDirectory)));
sourcePackage=sht_tc27_runtime_package(char(b.sourceRuntimeDirectory));
thermalPackage=sht_tc27_runtime_package(char(b.executionThermalRuntimeDirectory));
sht_f3_three_component_assets('verifyRuntime');
release=sht_f3_three_component_assets('manifest');
assert(strcmpi(local_canonical(b.executionRuntimeDirectory),local_canonical(a.runtime)), ...
    'SHT:F3:G01ExecutionDirectory','所选执行目录必须是当前明确选择的F3运行包，禁止检查A包却激活B包。');
thermal=local_canonical(b.executionThermalFile);
assert(strcmpi(thermal,local_canonical(thermalPackage.thermalFile)), ...
    'SHT:F3:G01ThermalFile','所选Visser热文件必须是已核TC27执行热包清单声明的文件。');
names={'GTESS.dll','GTESS.h','blockAndFunctions.h','types_TMATS.H', ...
    'Turboshaft-TS.mdl','HPC02.MAP','HPT02.MAP','LPT02.MAP'};
hashes=cell(size(names));
for j=1:numel(names)
    hashes{j}=sht_tc27_file_identity(fullfile(a.runtime,names{j}));
    assert(strcmpi(hashes{j},sht_tc27_file_identity(fullfile(thermalPackage.directory,names{j}))), ...
        'SHT:F3:G01PhysicalPair','执行热包与F3物理文件不配对：%s。',names{j});
end
steady=sht_tc27_delivery('read',[],file);s=model.steadySchedule;
assert(strcmp(steady.route,o.priorRoute)&&model.modelMode==0&&model.thermalMode==3, ...
    'SHT:F3:G01Route','源路线或三部件Visser模型合同不匹配。');
assert(numel(s.designHealth)==159&&all(isfinite(s.designHealth(:))), ...
    'SHT:F3:G01Dictionary','组合稳态字典必须完整提供159维修正值。');
% TC27曲线可能未存modelMode；由已核验的外层身份补齐真实构造分派。
% 显式冲突必须拒绝，不能只把已经生成的六部件profile改成三部件标签。
if isfield(s,'modelMode')
    assert(isnumeric(s.modelMode)&&isscalar(s.modelMode)&&isreal(s.modelMode)&& ...
        isfinite(s.modelMode)&&s.modelMode==model.modelMode, ...
        'SHT:F3:G01ScheduleMode','曲线拓扑与已核验的组合模型身份冲突。');
end
s.modelMode=model.modelMode;
local_validate_schedule(s,table(),'2p7');
s.designHealth=s.designHealth(:);s.designHealth(59:71)=model.transientCoefficients(:);
fixed=local_fixed_transient(s.designHealth,model.sha256);s.fixedTransient=fixed;
source=struct('schema',model.schema,'workbookSHA256',model.sha256, ...
    'parentSteadySHA256',model.parentSteadySHA256,'packageId',sourcePackage.id, ...
    'runtimeManifestSHA256',model.runtimeManifestSHA256, ...
    'thermalSHA256',sht_tc27_file_identity(sourcePackage.thermalFile), ...
    'runtimeDirectory',sourcePackage.directory,'thermalFile',sourcePackage.thermalFile, ...
    'runtimeAssets',sourcePackage.identity.assets, ...
    'transientTable',table2struct(model.transientTable),'fuelBias',model.fuelBias);
execution=struct('modelMode',0,'stateCount',16,'thermalMode',3, ...
    'runtimeFiles',{names},'runtimeHashes',{hashes}, ...
    'runtimeVisserAssetSha256',sht_tc27_file_identity(thermal), ...
    'executionManifestSHA256',release.sha256,'thermalFile',thermal, ...
    'thermalPackageId',thermalPackage.id, ...
    'thermalManifestSHA256',sht_tc27_file_identity(thermalPackage.manifestFile), ...
    'ptReferencePolicy',char(b.ptReferencePolicy),'boundary',boundary,'fixedTransient',fixed);
association=struct('status','explicit_tc27_source_and_f3_reevaluation', ...
    'basis',char(b.basis),'source',source,'execution',execution, ...
    'sourceManifestSHA256',model.runtimeManifestSHA256, ...
    'executionManifestSHA256',release.sha256, ...
    'oldPosteriorRecomputed',false,'checkpointCompatibilityGranted',false);
opt=sht_steady_model_adapt_v2_common('defaultoptions',o.priorRoute);
opt.modelMode=0;opt.inletBoundaryMode=1;opt.estimateInletPressureLoss=true;opt.includePt2Residual=false;
par=sht_steady_model_adapt_v2_common('parameterdefinition',opt);
completed=local_complete_schedule_definition(s,par, ...
    'selected_tc27_combined_parent_current_explicit_solver_definition');
s=completed.schedule;
base=struct('options',opt,'finalSchedule',s,'parameterDefinition',par, ...
    'route',o.priorRoute,'runId',model.runId,'npBranchModel',model.npBranchModel);
p=struct('source','combined','route',o.priorRoute,'file',file,'sha256',model.sha256, ...
    'runId',model.runId,'schedule',s,'baseResult',base, ...
    'benchFuelBiasInherited',false,'parentFuelBias',model.fuelBias, ...
    'runtimeAssociation',association,'executionContract',execution, ...
    'executionThermalFile',thermal,'currentFuelReference','zero_reestimated_for_current_sortie', ...
    'currentKdistReference',0,'parentKdistEq',boundary.K_dist_eq, ...
    'KdistEq',boundary.K_dist_eq,'metadata',table( ...
        boundary.mean_inlet_recovery,boundary.backpressure_design_Pa,boundary.design_power_W, ...
        "explicit_execution_binding", ...
        'VariableNames',{'mean_inlet_recovery','backpressure_design_Pa','design_power_W','boundary_source'}), ...
    'transientTreatment','fixed_selected_combined_parent');
p.definitionAssociation=completed.definitionAssociation;
end

function out=local_complete_schedule_definition(s,par,basis)
% TC27交付的是物理曲线；F3再次辨识还需轴类型和绝对物理边界。
% 历史结果必须显式提供原完整定义，不能拿已释放节点的增量边界补齐。
assert(isfield(s,'modelMode')&&isequal(s.modelMode,0), ...
    'SHT:F3:DefinitionMode','定义关联只接受明确的三部件曲线。');
assert((ischar(basis)||(isstring(basis)&&isscalar(basis)))&& ...
    ~isempty(strtrim(char(basis))),'SHT:F3:DefinitionSource','必须说明完整参数定义的来源。');
required={'c_index','name','axis_name','axis_type','pressure_loss','lower_bound','upper_bound'};
assert(istable(par)&&all(ismember(required,par.Properties.VariableNames)), ...
    'SHT:F3:DefinitionTable','需提供完整物理参数定义表，不能使用节点增量参数表。');
local_validate_schedule(s,table(),'2p7');
fields={'axisType','lowerBound','upperBound'};
present=isfield(s.healthEntries,fields);
for j=1:numel(s.healthEntries)
    e=s.healthEntries(j);q=par(par.c_index==e.cIndex,:);
    assert(height(q)==1,'SHT:F3:DefinitionTable','h%d必须且只能有一条完整物理定义。',e.cIndex);
    assert(strcmp(e.name,char(string(q.name(1))))&& ...
        strcmp(e.axisName,char(string(q.axis_name(1))))&& ...
        isequal(logical(e.pressureLoss),logical(q.pressure_loss(1))), ...
        'SHT:F3:DefinitionConflict','h%d的名称、调度轴或压损类别与定义来源冲突。',e.cIndex);
    assert(isfield(e,'designCoordinate')&&isnumeric(e.designCoordinate)&& ...
        isreal(e.designCoordinate)&&isscalar(e.designCoordinate)&& ...
        isfinite(e.designCoordinate)&&e.designCoordinate>0, ...
        'SHT:F3:DefinitionCoordinate','h%d缺少原始有限正设计坐标；禁止猜测末节点。',e.cIndex);
    v=[q.axis_type(1),q.lower_bound(1),q.upper_bound(1)];
    assert(isnumeric(v)&&isreal(v)&&all(isfinite(v))&& ...
        v(1)==fix(v(1))&&ismember(v(1),[1,2,3,4,5,7,8])&&v(2)<v(3), ...
        'SHT:F3:DefinitionValue','h%d的轴类型或绝对物理上下界无效。',e.cIndex);
    expectedAxes=[1,5,5,2,7,7,3,8,8,4];indices=[0,1,2,6,7,8,10,11,12,14];
    assert(v(1)==expectedAxes(indices==e.cIndex),'SHT:F3:DefinitionConflict', ...
        'h%d的轴类型与已确认三部件物理调度轴冲突。',e.cIndex);
    for k=1:numel(fields)
        if present(k)
            old=e.(fields{k});
            assert(isnumeric(old)&&isreal(old)&&isscalar(old)&&isfinite(old)&&old==v(k), ...
                'SHT:F3:DefinitionConflict','h%d已有%s与本次完整求解定义冲突。',e.cIndex,fields{k});
        end
        s.healthEntries(j).(fields{k})=v(k);
    end
end
out=struct('schedule',s,'definitionAssociation',struct( ...
    'schema','F3_EXPLICIT_CURVE_DEFINITIONS_V1','basis',char(basis), ...
    'parameterDefinition',par,'designCoordinateSource','unchanged_parent_excel', ...
    'physicalValuesChanged',false));
end

function p=local_canonical(file)
assert(ischar(file)||(isstring(file)&&isscalar(file)),'SHT:F3:G01Path','包/热文件路径须为文本标量。');
p=char(java.io.File(char(file)).getCanonicalPath());
end

function fixed=local_fixed_transient(health,sourceSha)
if nargin<2,sourceSha='';end
assert(isnumeric(health)&&numel(health)==159&&all(isfinite(health(:))), ...
    'SHT:F3:FixedTransientDictionary','固定瞬态条件必须来自完整159维三部件健康向量。');
v=health(59:71);v=v(:);
assert(all(v>-1),'SHT:F3:FixedTransientValue','固定瞬态系数使物理倍率无效。');
assert(all(v==0)||~isempty(sourceSha),'SHT:F3:FixedTransientIdentity', ...
    '非零固定瞬态条件必须绑定显式组合父Excel身份。');
d=sht_health_parameter_dictionary(0);
fixed=struct('schema','F3_FIXED_VISSER16_13_V1','modelMode',0, ...
    'thermalMode',3,'stateCount',16,'cIndex',(58:70)', ...
    'name',{cellstr(string(d.name(59:71)))},'value',v, ...
    'sourceSha256',sourceSha,'estimatedInSteadyTask',false);
end

function p=local_flight_parent(o,a,file)
% 飞行父必须自描述，或带显式定义关联；绝不先读默认台架再覆盖。
assert(~isempty(file)&&isfile(file),'SHT:F3:ParentMissing','必须显式选择实际flight父Excel。');
sht_f3_three_component_assets('verifyRuntime');
d=sht_f33_excel_delivery('read',file,local_runtime(a));m=d.metadata;
assert(all(abs([m.mean_inlet_recovery-.995,m.backpressure_design_Pa-1500, ...
    m.design_power_W-2176600])<1e-10),'SHT:F3Task:ParentBoundary', ...
    '当前辨识核心仅支持入口恢复0.995、设计背压增量1500Pa、功率2176600W；所选父不匹配，不能静默替换。');
if ismember('model_route',m.Properties.VariableNames)
    assert(string(m.model_route)==string(o.priorRoute),'SHT:F3Task:ParentRoute','父模型路线与选择不符。');
else
    route=char(string(m.route));
    % 已交付旧Excel按四路线编号记录，不是modelRoute字符串前缀。
    supported={'R1','R3'};if strcmp(o.priorRoute,'transient_instant'),supported={'R2','R4'};end
    assert(ismember(route,supported),'SHT:F3Task:ParentRoute', ...
        '旧父路线不能由所选配置确认：%s。',route);
end
active=[0,1,2,6,7,8,10,11,12,14,15]+1;
inactive=setdiff(1:159,active);
assert(all(d.schedule.designHealth(inactive)==0), ...
    'SHT:F3Task:UnsupportedParentHealth','本次flight父恢复仅支持现行总体健康曲线与h15；其他非零物理参数不得静默丢失。');
for id=[3,9,13]
    q=d.profile.parameters([d.profile.parameters.cIndex]==id);
    assert(all(q.kNodes==0),'SHT:F3Task:UnsupportedParentHealth', ...
        'h%d非零压比曲线不在本次继承范围，不能静默清零。',id);
end
defs=d.curveDefinitions;association=struct('status','embedded_curve_definitions');
if isempty(defs)
    b=struct();if isfield(o,'priorDefinition'),b=o.priorDefinition;end
    assert(isstruct(b)&&isscalar(b)&&all(isfield(b, ...
        {'source','route','workbook','sha256','basis'}))&&ismember(b.source,{'2p4','2p7'})&& ...
        isfile(b.workbook)&&~isempty(strtrim(char(b.basis))), ...
        'SHT:F3Task:MissingDefinition', ...
        '旧flight父缺CurveDefinitions；请显式提供priorDefinition来源、路线、Excel、SHA及依据。');
    h=sht_tc27_file_identity(b.workbook);
    assert(strcmpi(h,b.sha256)&&strcmpi(h,char(string(m.reference_sha256))), ...
        'SHT:F3Task:DefinitionIdentity','定义文件SHA必须等于声明及旧flight父内嵌reference_sha256。');
    raw=readtable(b.workbook,'Sheet','CorrectionSchedule');
    assert(ismember('design_coordinate',raw.Properties.VariableNames)&& ...
        all(isfinite(raw.design_coordinate(raw.c_index~=15))), ...
        'SHT:F3Task:MissingDefinition','所选定义来源没有显式设计坐标，不能用末节点猜测。');
    ref=struct('priorSource',b.source,'priorRoute',b.route,'priorWorkbook',b.workbook);
    if isfield(b,'runtimeBinding'),ref.priorRuntimeBinding=b.runtimeBinding;end
    source=local_parent(ref,a);
    defs=sht_f33_excel_delivery('definitions',source.schedule);
    association=struct('status','explicit_reference_excel','file',b.workbook,'sha256',h,'basis',b.basis);
end
s=sht_f33_excel_delivery('restoreSchedule',d,defs);
local_validate_schedule(s,table(),'flight');
opt=sht_steady_model_adapt_v2_common('defaultoptions',o.priorRoute);
opt.modelMode=0;opt.inletBoundaryMode=1;opt.estimateInletPressureLoss=true;opt.includePt2Residual=false;
par=sht_steady_model_adapt_v2_common('parameterdefinition',opt);
runId='';if ismember('run_id',m.Properties.VariableNames),runId=char(string(m.run_id));end
base=struct('options',opt,'finalSchedule',s,'parameterDefinition',par, ...
    'route',o.priorRoute,'runId',runId,'npBranchModel',[]);
hash=sht_tc27_file_identity(file);
p=struct('source','flight','route',o.priorRoute,'file',file,'sha256',hash, ...
    'runId',runId,'schedule',s,'baseResult',base,'benchFuelBiasInherited',false, ...
    'runtimeAssociation',d.runtimeAssociation, ...
    'definitionAssociation',association,'metadata',m, ...
    'parentFuelBias',s.fuelBias,'parentKdistEq',d.KdistEq, ...
    'currentFuelReference','zero_reestimated_for_current_sortie','currentKdistReference',0, ...
    'transientTreatment','explicit_nominal_zero_supported_parent_only');
end

function local_validate_schedule(s,raw,source)
% 参数按物理编号核对，不能以Excel外形相同替代单位及坐标定义相同。
dict=sht_health_parameter_dictionary(0);required=[0,1,2,6,7,8,10,11,12,14];
assert(isequal(sort([s.healthEntries.cIndex]),required),'SHT:F3Task:ParentDictionary', ...
    '父模型必须完整提供当前支持的10条总体部件/压损曲线及常值h15。');
for j=1:numel(s.healthEntries)
    e=s.healthEntries(j);q=table();
    if ismember('c_index',raw.Properties.VariableNames),q=raw(raw.c_index==e.cIndex,:);end
    loss=ismember(e.cIndex,[0,6,10,14]);
    if loss
        axes={'inlet_corrected_mass_flow','burner_inlet_corrected_mass_flow', ...
            'gt_pt_duct_corrected_mass_flow','pt_nozzle_duct_corrected_mass_flow'};
        axis=axes{find([0,6,10,14]==e.cIndex,1)};unit='kg/s';
    elseif ismember(e.cIndex,[1,2]),axis='ac_corrected_speed';unit='1';
    elseif ismember(e.cIndex,[7,8]),axis='gt_total_pressure_ratio';unit='1';
    else,axis='pt_total_pressure_ratio';unit='1';end
    assert(strcmp(e.name,char(dict.name(e.cIndex+1)))&&strcmp(e.axisName,axis)&& ...
        e.pressureLoss==loss,'SHT:F3Task:ParentDictionary','h%d的名称/轴/压损定义不匹配。',e.cIndex);
    assert(numel(e.xNodes)>=2&&numel(e.xNodes)<=32&&all(diff(e.xNodes)>0)&& ...
        all(isfinite([e.xNodes(:);e.kNodes(:)])),'SHT:F3Task:ParentNodes', ...
        'h%d必须有2至32个严格递增有限节点。',e.cIndex);
    if strcmp(source,'2p4')
        assert(all(string(q.axis_unit)==string(unit))&&all(string(q.endpoint_policy)=="nearest_endpoint"), ...
            'SHT:F3Task:ParentUnit','h%d的轴单位/端点策略不匹配。',e.cIndex);
    end
end
% 单节点燃油尚不满足现行插值消费者，不静默复制节点制造假覆盖。
f=s.fuelBias;
assert(numel(f.xNodes)>=2&&numel(f.xNodes)<=32&&all(diff(f.xNodes)>0)&& ...
    all(isfinite([f.xNodes(:);f.biasNodes(:);f.wfDesign]))&&f.wfDesign>0, ...
    'SHT:F3Task:ParentFuelNodes','燃油偏置必须有2至32个递增节点和正设计燃油。');
end

function association=local_parent_runtime(file,hash,knownHash,o,a)
% 已核SHA只提供历史关联证据，不是业务白名单。新模型缺少物理身份时
% 必须显式声明关联；现有嵌入身份一旦冲突，用户声明不得覆盖该冲突。
sht_f3_three_component_assets('verifyRuntime');
release=sht_f3_three_component_assets('manifest');manifestHash=release.sha256;
sourceManifest=manifestHash;runtimeAssociation=struct();
manifest=readtable(file,'Sheet','Manifest');embedded=false;
if ismember('runtime_manifest_sha256',manifest.Properties.VariableNames)
    declared=char(string(manifest.runtime_manifest_sha256(1)));
    allowed={manifestHash};
    if isfield(release.manifest,'compatibility')
        allowed{end+1}=release.manifest.compatibility.sourceManifestSHA256;
    end
    assert(any(strcmpi(declared,allowed)),'SHT:F3Task:ParentRuntimeConflict','父文件内嵌运行包SHA冲突。');
    sourceManifest=declared;
    embedded=true;
end
[~,sheets]=xlsfinfo(file);
if any(strcmp(sheets,'RuntimeAssets'))
    assets=readtable(file,'Sheet','RuntimeAssets');
    assert(all(ismember({'file','sha256'},assets.Properties.VariableNames)), ...
        'SHT:F3Task:ParentRuntimeConflict','父RuntimeAssets缺少文件名或SHA。');
    runtimeAssociation=sht_f3_three_component_assets('association',assets.file,assets.sha256);
    if embedded
        assert(strcmpi(sourceManifest,runtimeAssociation.sourceManifestSHA256), ...
            'SHT:F3Task:ParentRuntimeConflict','父清单声明与资产表不是同一来源。');
    end
    sourceManifest=runtimeAssociation.sourceManifestSHA256;
end
if embedded
    status='embedded_runtime_identity';basis='父Excel内嵌运行包清单SHA已核验';
elseif strcmpi(hash,knownHash)
    status='historical_verified_association';basis='MAIN已接收的固定上游文件与F3运行包关联';
    if isfield(release.manifest,'compatibility')
        sourceManifest=release.manifest.compatibility.sourceManifestSHA256;
    end
else
    binding=struct();if isfield(o,'priorRuntimeBinding'),binding=o.priorRuntimeBinding;end
    assert(isstruct(binding)&&isscalar(binding)&&all(isfield(binding, ...
        {'workbookSha256','runtimeManifestSha256','basis'}))&& ...
        strcmpi(binding.workbookSha256,hash)&&strcmpi(binding.runtimeManifestSha256,manifestHash)&& ...
        ~isempty(strtrim(char(binding.basis))),'SHT:F3Task:ParentRuntimeBinding', ...
        '新父模型缺少已核物理关联；请显式提供priorRuntimeBinding中的文件SHA、包清单SHA及依据。');
    status='user_declared_association_not_independently_verified';basis=char(binding.basis);
end
association=struct('status',status,'basis',basis,'workbookSha256',hash, ...
    'runtimeManifestSha256',manifestHash,'sourceManifestSHA256',sourceManifest, ...
    'executionManifestSHA256',manifestHash,'assetAssociation',runtimeAssociation, ...
    'oldPosteriorRecomputed',false,'checkpointCompatibilityGranted',false, ...
    'modelMode',0,'stateCount',16,'thermalMode',3);
end
