function varargout = sht_f32_replay_history(action, varargin)
%SHT_F32_REPLAY_HISTORY 第二轮3.2六部件Visser开环等效回放。
%
% 支持操作：
%   assets = sht_f32_replay_history('loadAssets',programDirectory)
%   replay = sht_f32_replay_history('run',data,assets,variant,...)
%   boundary = sht_f32_replay_history('reconstructBoundary',data,options)
%
% 正式个性化基线由入口显式选择的2.4或2.7调度合同构成。
% 本函数不读取3.1隐藏健康真值，也不从3.1文件读取实际传感器误差实现。

switch lower(char(action))
    case 'loadassets'
        varargout{1} = local_load_assets(varargin{:});
    case 'run'
        varargout{1} = local_run(varargin{:});
    case 'reconstructboundary'
        varargout{1} = local_reconstruct_boundary(varargin{:});
    case 'backpressuremodel'
        varargout{1} = local_exhaust_model(varargin{:});
    otherwise
        error('SHT:F32Replay:Action','不支持的操作：%s。',char(action));
end
end

function model=local_exhaust_model(user)
if nargin<1,user=struct();end
options=local_run_options(user);
model=struct('designRise_Pa',options.exhaustBackPressureDesignRise_Pa, ...
    'designPower_W',options.designPower_W);
end

function assets = local_load_assets(programDirectory,userOptions)
if nargin<1 || isempty(programDirectory)
    programDirectory=fileparts(mfilename('fullpath'));
end
if nargin<2 || isempty(userOptions),userOptions=struct();end
assetOptions=local_asset_options(userOptions);
if assetOptions.modelMode==0
    assets=sht_f3_current_contract('assets',assetOptions);return;
end
if strcmp(assetOptions.priorSource,'2p4')
    assets=local_load_2p4_assets(programDirectory,assetOptions);
    return;
end
middle=fullfile(programDirectory,'MiddleData');
stage27=fullfile(middle,'transient_model_adapt_2p7');
paths=struct();
paths.steadyContract=fullfile(stage27, ...
    'transient_model_adapt_2p7_m0_steady_schedule_for_transient_latest.mat');
paths.steadyPreparation=fullfile(stage27, ...
    'transient_model_adapt_2p7_steady_information_latest.mat');
paths.steadyEstimation=fullfile(stage27, ...
    'transient_model_adapt_2p7_steady_estimation_latest.mat');
paths.visserEstimation=fullfile(stage27, ...
    'transient_model_adapt_2p7_visser_forward_estimation_latest.mat');
paths.releaseContract=fullfile(middle, ...
    'transient_bench_2p6_cumulative_release_contract.mat');
    paths.sourceVisserAsset=fullfile(middle, ...
        'transient_effects_split_visser29_parameters.mat');
names=fieldnames(paths);
for i=1:numel(names)
    if ~isfile(paths.(names{i}))
        error('SHT:F32Replay:MissingAsset','缺少3.2基线资产：%s。', ...
            paths.(names{i}));
    end
end

steadyLoaded=load(paths.steadyContract,'downstreamContract');
visserLoaded=load(paths.visserEstimation,'result');
releaseLoaded=load(paths.releaseContract,'releaseContract');
if ~isfield(steadyLoaded,'downstreamContract') || ...
        ~isfield(visserLoaded,'result') || ...
        ~isfield(releaseLoaded,'releaseContract')
    error('SHT:F32Replay:AssetSchema','2.7交付资产结构不完整。');
end
steady=steadyLoaded.downstreamContract;
visser=visserLoaded.result;
release=releaseLoaded.releaseContract;
requiredSteady={'selectedMethod','selectedModelRoute', ...
    'selectedFusionMethod','physicalValid','schedule', ...
    'sourcePreparationHash','sourceEstimationHash'};
if ~all(isfield(steady,requiredSteady)) || ...
        ~strcmpi(steady.selectedMethod,'M0') || ...
        ~strcmpi(steady.selectedModelRoute,'transient_instant') || ...
        ~strcmpi(steady.selectedFusionMethod,'II') || ~steady.physicalValid
    error('SHT:F32Replay:SteadySelection', ...
        '第二轮3.2要求物理有效的2.7 M0/transient_instant/方法II合同。');
end
if ~strcmpi(steady.sourcePreparationHash,local_file_hash(paths.steadyPreparation)) || ...
        ~strcmpi(steady.sourceEstimationHash,local_file_hash(paths.steadyEstimation))
    error('SHT:F32Replay:StaleSteadyContract', ...
        '2.7稳态下游合同与当前准备/辨识结果不一致。');
end
if ~isfield(visser,'estimatedThetaNormalized') || ...
        numel(visser.estimatedThetaNormalized)~=release.releasedParameterCount || ...
        any(~isfinite(visser.estimatedThetaNormalized))
    error('SHT:F32Replay:VisserEstimate','2.7 Visser估计向量无效。');
end
if release.releasedParameterCount~=13 || ...
        ~isequal(size(release.fullHealthMappingMatrix),[159,13])
    error('SHT:F32Replay:ReleaseContract','Visser释放合同必须为159x13。');
end

% 核对2.7瞬态结果确由当前稳态合同、释放合同、DLL和Visser资产产生。
if ~isfield(visser,'problemContract')
    error('SHT:F32Replay:ProblemContract','2.7 Visser结果缺少问题合同。');
end
problemContract=visser.problemContract;
expectedSteadyHash=local_file_hash(paths.steadyContract);
expectedReleaseHash=local_file_hash(paths.releaseContract);
expectedVisserHash=local_file_hash(paths.sourceVisserAsset);
cfgCheck=sht_default_config(struct('engine',struct('modelMode',1)));
dllFile=fullfile(cfgCheck.engine.interface.controlDir,'GTESS.dll');
headerFile=fullfile(cfgCheck.engine.interface.controlDir, ...
    cfgCheck.engine.interface.headerName);
modelFile=cfgCheck.engine.modelConfiguration;
expectedDllHash=local_file_hash(dllFile);
local_assert_hash(problemContract,'steadyEstimateFileSha256', ...
    expectedSteadyHash,'2.7稳态合同');
local_assert_hash(problemContract,'releaseContractFileSha256', ...
    expectedReleaseHash,'瞬态释放合同');

% 2.7估计结果保留了估计当时的资产和DLL字节哈希。当前3.1/3.2运行基线
% 已增加默认关闭的装机接口，并重新生成了同版本Visser参数资产，因此这
% 两个字节哈希允许发生显式迁移。迁移只复用2.7的估计参数，不宣称复现
% 旧DLL结果；源、目标哈希和迁移原因都写入结果合同，禁止静默放宽。
sourceVisserHash=local_required_hash(problemContract,'visserAssetSha256', ...
    '2.7记录的Visser参数资产');
sourceDllHash=local_required_hash(problemContract,'runtimeDllSha256', ...
    '2.7记录的运行DLL');
visserAssetLoaded=load(paths.sourceVisserAsset,'parameterAsset');
if ~isfield(visserAssetLoaded,'parameterAsset') || ...
        ~isfield(visserAssetLoaded.parameterAsset,'assetVersion') || ...
        ~ismember(visserAssetLoaded.parameterAsset.assetVersion, ...
        {'2.5-split-visser29-v1','2.5-split-visser29-v2'})
    error('SHT:F32Replay:VisserAssetVersion', ...
        '当前Visser参数资产不是受支持的2.5-split-visser29-v1/v2。');
end
runtimeMigrationDetected=~strcmpi(sourceVisserHash,expectedVisserHash) || ...
    ~strcmpi(sourceDllHash,expectedDllHash);
if runtimeMigrationDetected
    fprintf(['  3.2基线迁移：复用2.7估计参数，在当前Visser资产和DLL上' ...
        '重新回放；源/目标哈希将完整记录。\n']);
end
[paths.visserAsset,runtimeAssetHash,runtimeAssetMigrated]= ...
    local_prepare_runtime_visser_asset(paths.sourceVisserAsset, ...
    visserAssetLoaded.parameterAsset,programDirectory,dllFile,headerFile,modelFile);

steadyHealth=steady.schedule.designHealth(:);
if numel(steadyHealth)~=159 || any(~isfinite(steadyHealth))
    error('SHT:F32Replay:SteadyHealth','2.7稳态设计点健康向量必须为159维。');
end
steadyHealth(90:112)=0;
steadyHealth(16)=steady.schedule.h15;
personalizedHealth=local_apply_transient_estimate( ...
    steadyHealth,visser.estimatedThetaNormalized,release);
profile=local_build_neutral_profile(steady.schedule,steadyHealth);

assets=struct();
assets.schemaVersion='SHT_F32_BASELINE_ASSETS_V2';
assets.programDirectory=programDirectory;
assets.paths=paths;
assets.contract=struct( ...
    'steadySelection','M0/transient_instant/II', ...
    'steadyContractSha256',expectedSteadyHash, ...
    'visserEstimationSha256',local_file_hash(paths.visserEstimation), ...
    'releaseContractSha256',expectedReleaseHash, ...
    'sourceVisserAssetSha256',sourceVisserHash, ...
    'currentSourceVisserAssetSha256',expectedVisserHash, ...
    'runtimeVisserAssetSha256',runtimeAssetHash, ...
    'runtimeVisserAssetMigrated',runtimeAssetMigrated, ...
    'sourceRuntimeDllSha256',sourceDllHash, ...
    'currentRuntimeDllSha256',expectedDllHash, ...
    'runtimeMigrationDetected',runtimeMigrationDetected, ...
    'runtimeMigrationPolicy', ...
    'explicit_parameter_transfer_and_current_runtime_replay', ...
    'strictSteadyAndReleaseHashesPassed',true, ...
    'truthDataAccessed',false);
assets.personalized=struct('id','personalized_2p7', ...
    'description',['2.7 M0/transient-instant/method-II steady schedule plus ' ...
    '13-D Visser estimate, replayed on the current Stage-3 runtime'], ...
    'health',personalizedHealth,'profile',profile, ...
    'scheduleEnabled',true,'fuelBias',steady.schedule.fuelBias);
assets.zero=struct('id','zero_correction', ...
    'description','six-component Visser29 zero-correction comparison', ...
    'health',zeros(159,1),'profile',[], ...
    'scheduleEnabled',false,'fuelBias',local_zero_fuel_bias(steady.schedule.fuelBias));
assets.transientParameterTable=visser.parameterTable;
assets.steadySchedule=steady.schedule;
end

function options=local_asset_options(user)
% 3.2的基线来源必须由入口显式记录。默认只继承2.4稳态路径
% 的稳态调度，不隐式携带2.7瞬态参数辨识结果。
options=struct('modelMode',0,'priorSource','2p4','priorRoute','transient_instant', ...
    'priorWorkbook','');
name=fieldnames(user);
for i=1:numel(name)
    if ~isfield(options,name{i})
        error('SHT:F32Replay:UnknownAssetOption', ...
            '未知3.2基线资产选项：%s。',name{i});
    end
    options.(name{i})=user.(name{i});
end
options.priorSource=char(lower(string(options.priorSource)));
options.priorRoute=char(lower(string(options.priorRoute)));
options.priorWorkbook=char(string(options.priorWorkbook));
if ~ismember(options.priorSource,{'2p4','2p7'})
    error('SHT:F32Replay:PriorSource', ...
        'priorSource必须为2p4或2p7。');
end
if ~ismember(options.priorRoute,{'steady','transient_instant'})
    error('SHT:F32Replay:PriorRoute', ...
        'priorRoute必须为steady或transient_instant。');
end
if strcmp(options.priorSource,'2p7') && ...
        ~strcmp(options.priorRoute,'transient_instant')
    error('SHT:F32Replay:Unsupported2p7Route', ...
        '当前2.7冻结下游合同只支持transient_instant路径。');
end
end

function assets=local_load_2p4_assets(programDirectory,options)
% 仅2.4确定性Excel交付及其受校验MAT侧车中读取稳态调度。
% 瞬态物理使用标称Visser29参数，h89:h111个体修正置零。
middle=fullfile(programDirectory,'MiddleData');
sourceVisserAsset=fullfile(middle, ...
    'transient_effects_split_visser29_parameters.mat');
if ~isfile(sourceVisserAsset)
    error('SHT:F32Replay:MissingVisserAsset', ...
        '缺少标称Visser29参数资产：%s。',sourceVisserAsset);
end
delivery=sht_load_2p4_deterministic_delivery( ...
    options.priorRoute,options.priorWorkbook);
schedule=delivery.result.finalSchedule;
if ~isstruct(schedule) || ~all(isfield(schedule, ...
        {'designHealth','healthEntries','fuelBias','h15'}))
    error('SHT:F32Replay:Bad2p4Schedule', ...
        '2.4确定性交付缺少完整稳态调度。');
end
% 第2.4燃油偏置属于台架试车批次的测量误差实现，不能作为另一架次
% 飞参数据的燃油偏置先验。保留横坐标合同，但将偏置节点严格置零。
schedule.fuelBias=local_zero_fuel_bias(schedule.fuelBias);

cfgCheck=sht_default_config(struct('engine',struct('modelMode',1)));
dllFile=fullfile(cfgCheck.engine.interface.controlDir,'GTESS.dll');
headerFile=fullfile(cfgCheck.engine.interface.controlDir, ...
    cfgCheck.engine.interface.headerName);
modelFile=cfgCheck.engine.modelConfiguration;
loaded=load(sourceVisserAsset,'parameterAsset');
if ~isfield(loaded,'parameterAsset') || ...
        ~isfield(loaded.parameterAsset,'assetVersion') || ...
        ~ismember(loaded.parameterAsset.assetVersion, ...
        {'2.5-split-visser29-v1','2.5-split-visser29-v2'})
    error('SHT:F32Replay:VisserAssetVersion', ...
        '当前Visser参数资产不是受支持的2.5-split-visser29-v1/v2。');
end
[runtimeVisserAsset,runtimeAssetHash,runtimeAssetMigrated]= ...
    local_prepare_runtime_visser_asset(sourceVisserAsset, ...
    loaded.parameterAsset,programDirectory,dllFile,headerFile,modelFile);

steadyHealth=schedule.designHealth(:);
if numel(steadyHealth)~=159 || any(~isfinite(steadyHealth))
    error('SHT:F32Replay:SteadyHealth', ...
        '2.4稳态调度的设计点健康向量必须为159维有限向量。');
end
steadyHealth(90:112)=0;
steadyHealth(16)=schedule.h15;
profile=local_build_neutral_profile(schedule,steadyHealth);

paths=struct('steadyContract',delivery.workbookFile, ...
    'steadyReplaySidecar',delivery.replaySidecarFile, ...
    'sourceVisserAsset',sourceVisserAsset, ...
    'visserAsset',runtimeVisserAsset);
assets=struct();
assets.schemaVersion='SHT_F32_BASELINE_ASSETS_V3';
assets.programDirectory=programDirectory;
assets.paths=paths;
assets.contract=struct( ...
    'schemaVersion','SHT_F32_BASELINE_CONTRACT_V3', ...
    'priorSource','2p4','priorRoute',options.priorRoute, ...
    'steadySelection',['2p4/' options.priorRoute], ...
    'steadyContractSha256',delivery.workbookSha256, ...
    'steadySemanticPayloadSha256',delivery.semanticPayloadSha256, ...
    'steadyRunId',delivery.runId, ...
    'sourceVisserAssetSha256',local_file_hash(sourceVisserAsset), ...
    'runtimeVisserAssetSha256',runtimeAssetHash, ...
    'runtimeVisserAssetMigrated',runtimeAssetMigrated, ...
    'currentRuntimeDllSha256',local_file_hash(dllFile), ...
    'transientIndividualCorrectionSource','nominal_zero', ...
    'truthDataAccessed',false);
assets.personalized=struct('id', ...
    ['personalized_2p4_' options.priorRoute], ...
    'description',['2.4 ' options.priorRoute ...
    ' steady schedule plus nominal Visser29 physics'], ...
    'health',steadyHealth,'profile',profile, ...
    'scheduleEnabled',true,'fuelBias',schedule.fuelBias);
assets.zero=struct('id','zero_correction', ...
    'description','six-component Visser29 zero-correction comparison', ...
    'health',zeros(159,1),'profile',[], ...
    'scheduleEnabled',false, ...
    'fuelBias',local_zero_fuel_bias(schedule.fuelBias));
assets.transientParameterTable=table();
assets.steadySchedule=schedule;
end

function health=local_apply_transient_estimate(health,theta,contract)
theta=theta(:);
q=contract.releasedParameterScale(:).*theta;
mapping=contract.fullHealthMappingMatrix;
occupied=false(size(health));
for j=1:numel(theta)
    rows=find(abs(mapping(:,j))>0);
    if any(occupied(rows))
        error('SHT:F32Replay:MappingOverlap','Visser参数映射列发生重叠。');
    end
    occupied(rows)=true;
    coefficient=mapping(rows,j);
    switch char(contract.releasedCoordinateType{j})
        case 'linear_fraction'
            health(rows)=health(rows)+coefficient*q(j);
        case 'log_time_scale'
            health(rows)=(1+health(rows)).*exp(coefficient*q(j))-1;
        otherwise
            error('SHT:F32Replay:CoordinateType','未知Visser参数坐标类型。');
    end
end
if any(~isfinite(health)) || any(1+health(occupied)<=0)
    error('SHT:F32Replay:MappedHealth','Visser参数映射产生无效健康向量。');
end
end

function profile=local_build_neutral_profile(schedule,designHealth)
% 直接由公开的2.7估计合同构造31张DLL调度表。未估计的表严格置零，
% 因而无需读取3.1生成期真值profile，避免结构模板带入隐藏数值。
cIndex=[0:3,6:14,71:88].';
axisName=[repmat({'ac_corrected_speed'},4,1); ...
    {'burner_inlet_corrected_mass_flow'}; ...
    repmat({'gt_total_pressure_ratio'},3,1); ...
    {'gt_pt_duct_corrected_mass_flow'}; ...
    repmat({'pt_total_pressure_ratio'},3,1); ...
    {'pt_nozzle_duct_corrected_mass_flow'}; ...
    repmat({'ac_corrected_speed'},3,1); ...
    repmat({'cc_corrected_speed'},3,1); ...
    repmat({'gt_total_pressure_ratio'},6,1); ...
    repmat({'pt_total_pressure_ratio'},6,1)];
axisName{1}='inlet_corrected_mass_flow';
zeroAxes={'inlet_corrected_mass_flow','burner_inlet_corrected_mass_flow', ...
    'gt_pt_duct_corrected_mass_flow','pt_nozzle_duct_corrected_mass_flow'};
dictionary=sht_health_parameter_dictionary(1);
entryIndex=[schedule.healthEntries.cIndex];
template=struct('cIndex',0,'matlabHealthIndex',0,'name','', ...
    'mode','table1d','axisName','','xNodes',[],'deltaNodes',[], ...
    'designValue',0,'kNodes',[],'zeroFlowAnchored',false, ...
    'activeTruth',false);
parameters=repmat(template,numel(cIndex),1);
for i=1:numel(cIndex)
    c=cIndex(i);
    row=find(dictionary.c_index==c,1);
    parameters(i).cIndex=c;
    parameters(i).matlabHealthIndex=c+1;
    parameters(i).name=char(dictionary.name(row));
    parameters(i).axisName=axisName{i};
    parameters(i).designValue=designHealth(c+1);
    parameters(i).zeroFlowAnchored=any(strcmp(axisName{i},zeroAxes));
    estimated=find(entryIndex==c,1);
    if ~isempty(estimated)
        entry=schedule.healthEntries(estimated);
        parameters(i).xNodes=entry.xNodesDll(:);
        parameters(i).deltaNodes=entry.deltaNodesDll(:);
        parameters(i).designValue=entry.designValue;
    elseif parameters(i).zeroFlowAnchored
        parameters(i).xNodes=[0;1e6];
        parameters(i).deltaNodes=[-parameters(i).designValue;0];
    elseif contains(axisName{i},'corrected_speed')
        parameters(i).xNodes=[0;2];
        parameters(i).deltaNodes=[0;0];
    else
        parameters(i).xNodes=[0;100];
        parameters(i).deltaNodes=[0;0];
    end
    parameters(i).kNodes=parameters(i).designValue+parameters(i).deltaNodes;
    parameters(i).activeTruth=abs(parameters(i).designValue)>0 || ...
        any(abs(parameters(i).deltaNodes)>0);
end
profile=struct('schemaVersion','SHT_F32_ESTIMATED_SCHEDULE_PROFILE_V1', ...
    'modelMode',1,'createdAt',datestr(now,31), ...
    'interpolation','piecewise_linear','extrapolation','nearest_endpoint_clamp', ...
    'parameterLaw','K_eff(x)=k_design+Delta(x)', ...
    'parameters',parameters,'scheduledCIndex',cIndex, ...
    'truthVectorAtDesign',designHealth(:), ...
    'source','2.7 estimated schedule only; no 3.1 hidden truth template');
end

function fuel=local_zero_fuel_bias(reference)
fuel=reference;
fuel.biasNodes=zeros(size(reference.biasNodes));
end

function replay=local_run(data,assets,variant,measurementAssumptions,userOptions,recordedContinuationHash)
if nargin<5 || isempty(userOptions), userOptions=struct(); end
options=local_run_options(userOptions);
variant=lower(char(variant));
if ~isfield(assets,variant)
    error('SHT:F32Replay:Variant','未知回放基线：%s。',variant);
end
model=assets.(variant);
modelMode=1;if isfield(assets,'modelMode'),modelMode=assets.modelMode;end
if modelMode==0 && ~ismember('Mkg',data.Properties.VariableNames)
    % Mkg不是本飞参合同的测量列；当前无附件载荷，内部显式补零。
    data.Mkg=zeros(height(data),1);
end
required={'time_s','Ps0','Tt1','Pt3_eq','Ng','Np', ...
    'Mkp','Mkg','Wf','Tt45','Altitude','Mach','Ts_amb'};
inputOnly=strcmp(options.inputMode,'input_only');
if inputOnly
    assert(modelMode==0,'SHT:F32Replay:InputMode','输入-only当前只支持三部件Visser16。');
    required={'time_s','Ps0','Tt1','Mkp','Mkg','Wf','Altitude','Mach','Ts_amb'};
    assert(all(data.Mkg==0),'SHT:F32Replay:Accessory','当前飞行合同只支持Mkg=0。');
end
assert(all(ismember(required,data.Properties.VariableNames)), ...
    'SHT:F32Replay:InputColumns','回放输入字段不完整。');
if nargin<6
    % 在原始记录网格核对来源；不得对两次插值的浮点末位做哈希等价判断。
    % 积分细网格仍以自身全部数值进入物理缓存，不放松缓存匹配。
    recordedContinuationHash='';
    if ~isempty(options.resumeState)
        assert(isfield(options.resumeState,'recordedContinuationSha256') && ...
            strcmp(options.resumeState.recordedContinuationSha256, ...
            local_struct_hash(struct('names',{required},'values',data{:,required}))), ...
            'SHT:F32Replay:ResumeIdentity','续算拟合段原始测量记录与准备断点不匹配。');
    end
    if ~isempty(options.captureTime_s)
        first=find(abs(data.time_s-options.captureTime_s)<1e-8,1);
        assert(~isempty(first),'SHT:F32Replay:CaptureTime','准备结束点必须在记录网格上。');
        recordedContinuationHash=local_struct_hash(struct('names',{required},'values',data{first:end,required}));
    end
end
recordStep=median(diff(data.time_s));
assert(height(data)>=2 && isfinite(recordStep) && recordStep>0 && ...
    all(isfinite(data.time_s)) && max(abs(diff(data.time_s)-recordStep))<1e-8, ...
    'SHT:F32Replay:TimeGrid','回放必须使用至少两条等间隔、递增的有效记录。');
integrationStep=options.integrationStep_s;
if modelMode==0
    ratio=round(recordStep/integrationStep);
    assert(ratio>=1 && abs(recordStep-ratio*integrationStep)<1e-9, ...
        'SHT:F32Replay:TimeGrid', ...
        '积分步长必须整除记录周期，不能为提速丢弃已有测量记录。');
end
if modelMode==0 && recordStep>integrationStep+1e-9
    names=data.Properties.VariableNames;
    % 按记录数确定积分步数，避免片段归零后的浮点末端被冒号网格舍弃。
    recordRows=(1:ratio:(height(data)-1)*ratio+1).';
    denseTime=data.time_s(1)+(0:(height(data)-1)*ratio).'*integrationStep;
    assert(max(abs(denseTime(recordRows)-data.time_s))<1e-8, ...
        '飞参记录必须为等时间间隔，不能静默填补缺失记录。');
    denseTime(recordRows)=data.time_s;
    dense=array2table(interp1(data.time_s,data{:,:},denseTime,'linear'),'VariableNames',names);
    dense.time_s=denseTime;dense.sample_id=(1:height(dense)).';
    replay=local_run(dense,assets,variant,measurementAssumptions,userOptions,recordedContinuationHash);
    rows=recordRows;fields=fieldnames(replay);
    for j=1:numel(fields)
        v=replay.(fields{j});
        if (isnumeric(v)||istable(v))&&size(v,1)==height(dense)
            replay.(fields{j})=v(rows,:);
        end
    end
    fields=fieldnames(replay.boundaryReconstruction);
    for j=1:numel(fields)
        v=replay.boundaryReconstruction.(fields{j});
        if isnumeric(v)&&size(v,1)==height(dense),replay.boundaryReconstruction.(fields{j})=v(rows,:);end
    end
    if ~inputOnly
        replay.measuredOutput=[data.Np,data.Ng,data.Pt3_eq,data.Tt45];
        replay.residual=replay.sensorExpectedOutput-replay.measuredOutput;
        replay.metrics=local_metrics(replay.residual,measurementAssumptions);
    end
    replay.integrationStep_s=integrationStep;replay.recordStep_s=recordStep;
    return;
end
time=data.time_s(:); n=height(data); dt=median(diff(time));
if strcmp(options.fuelDefinition,'physical')
    wfModel=data.Wf(:);
else
    wfModel=local_physical_fuel(data.Wf(:),model.fuelBias);
end
assert(all(isfinite(wfModel)&wfModel>0),'SHT:F32Replay:Fuel','物理燃油必须为正有限值。');

if modelMode==0,cfg=assets.configuration;
else,cfg=sht_default_config(struct('engine',struct('modelMode',1)));end
cfg.Tsim=dt; cfg.Tctrl=dt; cfg.plot.enable=false;
options.designPower_W=cfg.engine.initial.power0;
boundaryReconstruction=local_reconstruct_boundary(data,options);
if modelMode~=0
    cfg.engine.reynoldsCorrection=sht_reynolds_correction_config(options.reynoldsEffectScale);
else
    assert(options.reynoldsEffectScale==1,'三部件回放必须使用已冻结RNI配置。');
end

payload=struct('schemaVersion','SHT_F32_REPLAY_CACHE_CONTRACT_V5', ...
    'sourceSha256',options.sourceSha256,'variant',variant, ...
    'actualDataSha256',local_struct_hash(struct('names',{required}, ...
        'values',data{:,required})), ...
    'modelSemanticSha256',local_struct_hash( ...
    local_model_semantic_contract(model)), ...
    'assetContract',assets.contract,'sampleCount',n, ...
    'startTime_s',time(1),'endTime_s',time(end),'sampleTime_s',dt, ...
    'integrationMethod',options.integrationMethod,'integrationStep_s',dt, ...
    'initialThermalOffset_K',options.initialThermalOffset_K, ...
    'inputMode',options.inputMode,'initialStateDefinition',options.initialState, ...
    'fuelDefinition',options.fuelDefinition, ...
    'resumeState',options.resumeState,'captureTime_s',options.captureTime_s, ...
    'recordedContinuationSha256',recordedContinuationHash, ...
    'sensorDynamicsEnabled',options.sensorDynamicsEnabled, ...
    'maximumCommonWorkResidual',options.maximumCommonWorkResidual, ...
    'boundaryReconstructionContract',boundaryReconstruction.contract, ...
    'reynoldsEffectScale',options.reynoldsEffectScale, ...
    'measurementAssumptions',table2struct(measurementAssumptions), ...
    'replayProgramSha256',local_file_hash([mfilename('fullpath'),'.m']), ...
    'engineDerivativeSha256',local_file_hash(fullfile( ...
    assets.programDirectory,'sht_engine_derivative.m')), ...
    'exhaustModelSha256',local_file_hash(fullfile( ...
    assets.programDirectory,'sht_exhaust_backpressure.m')));
contractHash=local_struct_hash(payload);
cacheFile=fullfile(options.cacheDirectory,[contractHash,'.mat']);
if ~options.forceRecompute && isfile(cacheFile)
    loaded=load(cacheFile,'cacheRecord');
    if isfield(loaded,'cacheRecord') && ...
            strcmp(loaded.cacheRecord.contractHash,contractHash) && ...
            loaded.cacheRecord.success
        replay=loaded.cacheRecord.replay;
        replay.cacheHit=true;
        replay.executedEvaluationCount=0;
        replay.cacheFile=cacheFile;
        fprintf('  3.2 %s回放命中缓存：%s\n',variant,cacheFile);
        return;
    end
end

cfg.engine.boundary.health=model.health(:);
cfg.engine.boundary.healthScheduleEnabled=model.scheduleEnabled;
cfg.engine.healthScheduleProfile=model.profile;
if modelMode~=0
    [cfg,~]=sht_configure_transient_visser29(cfg,'joint_full',assets.paths.visserAsset);
    cfg.engine.reynoldsCorrection=sht_reynolds_correction_config(options.reynoldsEffectScale);
end
cfg.engine.boundary.health=model.health(:);
cfg.engine.boundary.healthScheduleEnabled=model.scheduleEnabled;
cfg.engine.healthScheduleProfile=model.profile;

if inputOnly
    initialState=[options.initialState.Np0;options.initialState.Ng0];
else
    initialState=[data.Np(1);data.Ng(1)];
end
resuming=~isempty(options.resumeState);
if resuming
    rs=options.resumeState;
    assert(numel(rs.state)==16 && all(isfinite(rs.state)) && ...
        numel(rs.commonWorkingSeed)==6 && all(isfinite(rs.commonWorkingSeed)) && ...
        numel(rs.sensorState)==4 && all(isfinite(rs.sensorState)), ...
        'SHT:F32Replay:ResumeState','续算必须包含16状态、6共同工作猜值和4传感器状态。');
    assert(modelMode==0 && strcmp(rs.schema,'F33_LOCAL_RESTART_R033') && ...
        abs(rs.time_s-time(1))<1e-8 && abs(rs.integrationStep_s-dt)<1e-10 && ...
        strcmp(rs.integrationMethod,options.integrationMethod), ...
        'SHT:F32Replay:ResumeContract', ...
        '续算合同不匹配：起点%.12g/%.12g秒，步长%.17g/%.17g秒，模型%d。', ...
        rs.time_s,time(1),rs.integrationStep_s,dt,modelMode);
    assert(strcmp(rs.assetHash,local_struct_hash(assets.contract)) && ...
        strcmp(rs.sensorHash,local_struct_hash(table2struct(measurementAssumptions))) && ...
        rs.sensorDynamicsEnabled==options.sensorDynamicsEnabled, ...
        'SHT:F32Replay:ResumeIdentity','续算运行资产或传感器身份不匹配。');
    initialState=rs.state(1:2);
end
initialBoundary=local_boundary( ...
    cfg,data,model,boundaryReconstruction,1,initialState);
cfg.engine.boundary=local_merge_boundary(cfg.engine.boundary,initialBoundary);
cfg.engine.initial.Np0=initialState(1);
cfg.engine.initial.Ng0=initialState(2);
cfg.engine.initial.Wf0=wfModel(1);
cfg.engine.initial.Mkp=data.Mkp(1);
cfg.engine.initial.Mkg=data.Mkg(1);
cfg.engine.initial.power0=max(data.Mkp(1)*initialState(1)*pi/30,0);
trim=struct('Np',initialState(1),'Ng',initialState(2),'Wf',wfModel(1));
if inputOnly&&isfield(options.initialState,'commonWorkingSeed')
    cfg.engine.initial.commonWorkingSeed=options.initialState.commonWorkingSeed(:);
end
if resuming
    % 仅恢复状态和数值猜值，不覆盖当前候选的健康曲线、燃油或热配置。
    temperatureState=rs.state(3:end);
    equilibrium=struct('evaluationCount',0,'source','restored_preparation_state');
    cfg.engine.initial.commonWorkingSeed=rs.commonWorkingSeed;
elseif inputOnly&&strcmp(options.initialState.thermalStrategy,'explicit')
    temperatureState=options.initialState.temperature_K(:);
    equilibrium=struct('evaluationCount',0,'source','explicit_user_14_thermal_states');
elseif modelMode==0
    fprintf('  3.2 %s：求首点Visser热平衡，modelMode=%d ...\n',variant,modelMode);
    e=sht_engine_open(cfg.engine);c=onCleanup(@()sht_engine_close(e));
    x=cfg.engine.initial.state(:);x(1:2)=initialState;
    equilibrium=sht_thermal_equilibrium_solve(e,x,wfModel(1),cfg.engine.boundary, ...
        'thermal_only',struct('verbose',false,'finalJacobianAudit',true));
    assert(equilibrium.physicalValid&&equilibrium.thermalPassed,'三部件首点热平衡失败。');
    temperatureState=equilibrium.state(3:end);clear c;
else
    [temperatureState,equilibrium]=sht_refine_visser_operating_thermal_equilibrium(cfg,trim);
end
% 初温偏移仅供局部初始化敏感性核验，正式辨识默认零；不能读取造数热状态。
offset=options.initialThermalOffset_K;
assert(isscalar(offset)||numel(offset)==numel(temperatureState), ...
    'SHT:F32Replay:InitialThermalOffset','初温偏移必须为标量或匹配热状态数的向量。');
temperatureState=temperatureState(:)+offset(:);
assert(all(isfinite(temperatureState)&temperatureState>0), ...
    'SHT:F32Replay:InitialThermalOffset','偏移后金属绝对温度必须为正。');
state=[initialState;temperatureState(:)];
cfg.engine.initial.state=state;

engine=sht_engine_open(cfg.engine);
engineCleanup=onCleanup(@()sht_engine_close(engine));
    trueOutput=NaN(n,4);
    inletPt1=NaN(n,1);
nComponent=6;
if modelMode==0,nComponent=3;end
componentCoordinate=NaN(n,nComponent);
scheduleCoordinate=NaN(n,7);
scheduleCoordinateNames={'inlet_corrected_mass_flow','burner_inlet_corrected_mass_flow', ...
    'gt_pt_duct_corrected_mass_flow','pt_nozzle_duct_corrected_mass_flow', ...
    'ac_corrected_speed','gt_total_pressure_ratio','pt_total_pressure_ratio'};
reynoldsIndex=NaN(n,nComponent);
reynoldsFlowMultiplier=NaN(n,nComponent);
reynoldsEfficiencyMultiplier=NaN(n,nComponent);
stateHistory=NaN(n,numel(state));
backpressureHistory=NaN(n,1);
maximumResidualBySample=NaN(n,1);
convergeTagBySample=zeros(n,1);
energyResidualBySample=NaN(n,1);
evaluationCount=0;
restart=[];
timerId=tic;

boundary=local_boundary(cfg,data,model,boundaryReconstruction,1,state);
[xDot,currentOutput,currentDiag]= ...
    sht_engine_derivative(engine,state,wfModel(1),boundary);
evaluationCount=evaluationCount+1;
local_validate_evaluation(state,xDot,currentOutput,currentDiag,time(1));
for k=1:n
    if ~isempty(options.captureTime_s) && abs(time(k)-options.captureTime_s)<1e-8
        % 保存的都是数值，不保留跨DLL生命周期的libpointer/libstruct。
        v=double(engine.callContext.engPtr.eng.varIte);
        restart=struct('schema','F33_LOCAL_RESTART_R033','time_s',time(k), ...
            'integrationStep_s',dt,'integrationMethod',options.integrationMethod, ...
            'state',state(:),'commonWorkingSeed',v(1:6), ...
            'assetHash',local_struct_hash(assets.contract), ...
            'sensorHash',local_struct_hash(table2struct(measurementAssumptions)), ...
            'sensorDynamicsEnabled',options.sensorDynamicsEnabled, ...
            'recordedContinuationSha256',recordedContinuationHash, ...
            'sourceContractHash',contractHash,'captureIndex',k);
    end
    stateHistory(k,:)=state(:).';
    backpressureHistory(k)=currentOutput.Pback;
        trueOutput(k,:)=local_output_row(currentOutput);
        inletPt1(k)=currentOutput.Pt1;
    componentCoordinate(k,:)=local_component_row(currentOutput,modelMode);
    for c=1:7,scheduleCoordinate(k,c)=currentOutput.(scheduleCoordinateNames{c});end
    [reynoldsIndex(k,:),reynoldsFlowMultiplier(k,:), ...
        reynoldsEfficiencyMultiplier(k,:)]=local_reynolds_row(currentOutput,nComponent);
    maximumResidualBySample(k)=max( ...
        [maximumResidualBySample(k),currentDiag.maxErr],[],'omitnan');
    convergeTagBySample(k)=max(convergeTagBySample(k), ...
        abs(currentDiag.convergeTag));
    energyResidualBySample(k)=local_energy_residual(currentDiag);
    if k==n, break; end

    step=time(k+1)-time(k);
    if strcmpi(options.integrationMethod,'euler1')
        stateNext=state+step*xDot;
        boundaryNext=local_boundary( ...
            cfg,data,model,boundaryReconstruction,k+1,stateNext);
        [xDotNext,outputNext,diagNext]=sht_engine_derivative( ...
            engine,stateNext,wfModel(k+1),boundaryNext);
        evaluationCount=evaluationCount+1;
        local_validate_evaluation(stateNext,xDotNext,outputNext,diagNext,time(k+1));
    else
        statePredict=state+step*xDot;
        boundaryPredict=local_boundary( ...
            cfg,data,model,boundaryReconstruction,k+1,statePredict);
        [xDotPredict,outputPredict,diagPredict]=sht_engine_derivative( ...
            engine,statePredict,wfModel(k+1),boundaryPredict);
        evaluationCount=evaluationCount+1;
        local_validate_evaluation(statePredict,xDotPredict, ...
            outputPredict,diagPredict,time(k+1));
        stateNext=state+0.5*step*(xDot+xDotPredict);
        boundaryNext=local_boundary( ...
            cfg,data,model,boundaryReconstruction,k+1,stateNext);
        [xDotNext,outputNext,diagNext]=sht_engine_derivative( ...
            engine,stateNext,wfModel(k+1),boundaryNext);
        evaluationCount=evaluationCount+1;
        local_validate_evaluation(stateNext,xDotNext,outputNext,diagNext,time(k+1));
        maximumResidualBySample(k+1)=max([ ...
            maximumResidualBySample(k+1),diagPredict.maxErr],[],'omitnan');
        convergeTagBySample(k+1)=max(convergeTagBySample(k+1), ...
            abs(diagPredict.convergeTag));
    end
    state=stateNext; xDot=xDotNext;
    currentOutput=outputNext; currentDiag=diagNext;
    if mod(k,options.progressIntervalSamples)==0
        elapsed=toc(timerId);
        eta=elapsed*(n-1-k)/max(k,1);
        fprintf('    %s %6.2f%%，已用 %.1f s，预计剩余 %.1f s\n', ...
            variant,100*k/(n-1),elapsed,eta);
    end
end
runtime_s=toc(timerId);

sensorExpected=trueOutput;
if options.sensorDynamicsEnabled
    outputNames={'Np','Ng','Pt3_eq','Tt45'};
    for j=1:numel(outputNames)
        row=find(strcmp(cellstr(string(measurementAssumptions.name)), ...
            outputNames{j}),1);
        if isempty(row)
            error('SHT:F32Replay:SensorAssumption', ...
                '缺少%s传感器动态先验。',outputNames{j});
        end
        initialSensor=[];
        if inputOnly&&isfield(options.initialState,'sensorState')
            initialSensor=options.initialState.sensorState(j);
        end
        if resuming,initialSensor=rs.sensorState(j);end
        sensorExpected(:,j)=sht_first_order_foh_filter( ...
            time,trueOutput(:,j),measurementAssumptions.timeConstant_s(row),initialSensor);
    end
end
if ~isempty(options.captureTime_s)
    assert(~isempty(restart),'SHT:F32Replay:CaptureTime','快照时刻不在积分网格中。');
    restart.sensorState=sensorExpected(restart.captureIndex,:);
    restart.rawOutput=trueOutput(restart.captureIndex,:);
end
measured=[];residual=[];metrics=table();
if ~inputOnly
    measured=[data.Np,data.Ng,data.Pt3_eq,data.Tt45];
    residual=sensorExpected-measured;
    metrics=local_metrics(residual,measurementAssumptions);
end

replay=struct();
replay.schemaVersion='SHT_F32_REPLAY_RESULT_V3';
replay.variant=variant;
replay.description=model.description;
replay.contractHash=contractHash;
replay.cacheHit=false;
replay.cacheFile=cacheFile;
replay.time_s=time;
replay.integrationStep_s=dt;
replay.recordStep_s=recordStep;
replay.inputMode=options.inputMode;
replay.fuelDefinition=options.fuelDefinition;
replay.initialStateDefinition=options.initialState;
replay.measuredOutputAvailable=~inputOnly;
replay.initialThermalOffset_K=options.initialThermalOffset_K;
replay.stateNames=[{'Np','Ng'},arrayfun(@(i)sprintf('thermal_%02d',i), ...
    1:numel(state)-2,'UniformOutput',false)];
replay.state=stateHistory;
replay.outputNames={'Np','Ng','Pt3_eq','Tt45'};
replay.outputUnits={'rpm','rpm','Pa','K'};
    replay.trueModelOutput=trueOutput;
    % Pt1仅作为C端边界重构核查量留在MAT诊断中，不写入正式Excel，
    % 更不得作为后续辨识输入。
    replay.inletPt1_Pa=inletPt1;
replay.sensorExpectedOutput=sensorExpected;
replay.measuredOutput=measured;
replay.residual=residual;
replay.componentCoordinateNames={'AC_Ncr','CC_Ncr','GT1_Ncr', ...
    'GT2_Ncr','PT1_Ncr','PT2_Ncr'};
replay.componentCoordinate=componentCoordinate;
if modelMode==0
    replay.componentCoordinateNames={'HPC_Ncr','GT_Ncr','PT_Ncr'};
    replay.componentCoordinate=componentCoordinate;
end
replay.scheduleCoordinate=array2table(scheduleCoordinate,'VariableNames',scheduleCoordinateNames);
replay.reynoldsComponentNames={'AC','CC','GT1','GT2','PT1','PT2'};
replay.reynoldsIndex=reynoldsIndex;
replay.reynoldsFlowMultiplier=reynoldsFlowMultiplier;
replay.reynoldsEfficiencyMultiplier=reynoldsEfficiencyMultiplier;
if modelMode==0
    replay.reynoldsComponentNames={'HPC','GT','PT'};
    replay.reynoldsIndex=reynoldsIndex(:,1:3);
    replay.reynoldsFlowMultiplier=reynoldsFlowMultiplier(:,1:3);
    replay.reynoldsEfficiencyMultiplier=reynoldsEfficiencyMultiplier(:,1:3);
end
% 内部背压只能作为该次模型回放的诊断输出，不是测量/冻结边界。
boundaryReconstruction.Pback_Pa=backpressureHistory;
boundaryReconstruction.loadPower_W=max(data.Mkp(:).*stateHistory(:,1)*pi/30,0);
replay.boundaryReconstruction=boundaryReconstruction;
replay.physicalFuelInput_kgps=wfModel;
replay.estimatedFuelBias_kgps=data.Wf(:)-wfModel;
replay.maximumResidualBySample=maximumResidualBySample;
replay.convergeTagBySample=convergeTagBySample;
replay.energyResidualBySample=energyResidualBySample;
replay.maximumCommonWorkResidual=max(maximumResidualBySample,[],'omitnan');
replay.nonzeroConvergeTagCount=nnz(convergeTagBySample);
replay.maximumNormalizedEnergyResidual=max(abs(energyResidualBySample),[],'omitnan');
replay.evaluationCount=evaluationCount;
replay.executedEvaluationCount=evaluationCount;
if isfield(equilibrium,'evaluationCount')
    replay.executedEvaluationCount=evaluationCount+equilibrium.evaluationCount;
end
replay.restartState=restart;
replay.runtime_s=runtime_s;
replay.initialThermalEquilibrium=equilibrium;
replay.metrics=metrics;
replay.computationallyAccepted=all(isfinite(stateHistory(:))) && ...
    replay.maximumCommonWorkResidual<=options.maximumCommonWorkResidual && ...
    replay.nonzeroConvergeTagCount==0;

if ~isfolder(options.cacheDirectory), mkdir(options.cacheDirectory); end
cacheRecord=struct('schemaVersion','SHT_F32_REPLAY_CACHE_V5', ...
    'contractHash',contractHash,'success',replay.computationallyAccepted,'replay',replay);
temporary=[tempname(options.cacheDirectory),'.mat'];
save(temporary,'cacheRecord','-v7.3');
[moved,message]=movefile(temporary,cacheFile,'f');
if ~moved
    if isfile(temporary),delete(temporary);end
    error('SHT:F32Replay:CacheWrite','回放缓存写入失败：%s。',message);
end
clear engineCleanup;
end

function options=local_run_options(user)
options=struct('cacheDirectory',fullfile(fileparts(mfilename('fullpath')), ...
    'MiddleData','flight_model_adapt_3p2','replay_cache'), ...
    'sourceSha256','','integrationMethod','euler2','integrationStep_s',0.025, ...
    'initialThermalOffset_K',0,'resumeState',[],'captureTime_s',[], ...
    'inputMode','measured_record','initialState',struct(),'fuelDefinition','measured', ...
    'sensorDynamicsEnabled',true,'forceRecompute',false, ...
    'maximumCommonWorkResidual',1e-5,'progressIntervalSamples',2000, ...
    'inletMeanRecovery',0.995, ...
    'exhaustBackPressureDesignRise_Pa',1500, ...
    'reynoldsEffectScale',1,'designPower_W',2176600);
names=fieldnames(user);
for i=1:numel(names)
    if ~isfield(options,names{i})
        error('SHT:F32Replay:UnknownOption','未知回放选项：%s。',names{i});
    end
    options.(names{i})=user.(names{i});
end
if ~ismember(lower(options.integrationMethod),{'euler1','euler2'})
    error('SHT:F32Replay:Integration','积分方法必须为euler1或euler2。');
end
assert(ismember(options.inputMode,{'measured_record','input_only'})&& ...
    ismember(options.fuelDefinition,{'measured','physical'}), ...
    'SHT:F32Replay:InputMode','输入模式或燃油定义无效。');
if strcmp(options.inputMode,'input_only')
    s=options.initialState;
    assert(isstruct(s)&&isscalar(s)&&all(isfield(s,{'Np0','Ng0','thermalStrategy'})), ...
        'SHT:F32Replay:InitialState','输入-only须明确Np0、Ng0和thermalStrategy。');
    validateattributes([s.Np0,s.Ng0],{'numeric'},{'real','finite','positive','numel',2});
    assert(ismember(s.thermalStrategy,{'equilibrium','explicit'}), ...
        'SHT:F32Replay:InitialState','热初态只支持equilibrium或explicit。');
    if strcmp(s.thermalStrategy,'explicit')
        assert(isfield(s,'temperature_K'),'SHT:F32Replay:InitialState','缺14个热状态。');
        validateattributes(s.temperature_K,{'numeric'},{'real','finite','positive','numel',14});
    end
    if isfield(s,'sensorState'),validateattributes(s.sensorState,{'numeric'},{'real','finite','numel',4});end
    if isfield(s,'commonWorkingSeed'),validateattributes(s.commonWorkingSeed,{'numeric'},{'real','finite','numel',6});end
end
% 默认保持精细回放；辨识/预处理入口显式选择0.1秒，独立复核可用0.025秒。
validateattributes(options.integrationStep_s,{'numeric'}, ...
    {'real','finite','scalar','positive'});
validateattributes(options.initialThermalOffset_K,{'numeric'}, ...
    {'real','finite','vector','nonempty'});
assert(ismember(options.integrationStep_s,[0.025,0.1]), ...
    'SHT:F32Replay:IntegrationStep','integrationStep_s只允许0.025或0.1秒。');
if ~isscalar(options.inletMeanRecovery) || ...
        ~isfinite(options.inletMeanRecovery) || ...
        options.inletMeanRecovery<=0 || options.inletMeanRecovery>1
    error('SHT:F32Replay:InletRecovery', ...
        'inletMeanRecovery必须为(0,1]内有限标量。');
end
if ~isscalar(options.exhaustBackPressureDesignRise_Pa) || ...
        ~isfinite(options.exhaustBackPressureDesignRise_Pa) || ...
        options.exhaustBackPressureDesignRise_Pa<0
    error('SHT:F32Replay:BackPressureRise', ...
        '排气设计背压升高量必须为有限非负标量。');
end
if ~isscalar(options.reynoldsEffectScale) || ...
        ~isfinite(options.reynoldsEffectScale) || ...
        options.reynoldsEffectScale<0 || options.reynoldsEffectScale>2
    error('SHT:F32Replay:ReynoldsScale', ...
        'reynoldsEffectScale必须为[0,2]内有限标量。');
end
end

function boundary=local_boundary(cfg,data,model,reconstructed,k,state)
boundary=cfg.engine.boundary;
boundary.inletBoundaryMode=5;
boundary.altitude=data.Altitude(k);
boundary.Mach=data.Mach(k);
boundary.deltaTemperature=0;
boundary.Ps0=data.Ps0(k);
boundary.Pamb=data.Ps0(k);
boundary.Ts_amb=data.Ts_amb(k);
boundary.Tamb=data.Ts_amb(k);
boundary.Tt1=data.Tt1(k);
boundary.inletTotalPressureRecovery= ...
    reconstructed.inletTotalPressureRecovery(k);
if isfield(boundary,'Pback'),boundary=rmfield(boundary,'Pback');end
boundary.exhaustBackPressureModel=reconstructed.exhaustBackPressureModel;
boundary.Mkp=data.Mkp(k);
boundary.Mkg=data.Mkg(k);
boundary.ptLoadInputMode='torque';
boundary.gtLoadInputMode='torque';
boundary.health=model.health(:);
boundary.healthScheduleEnabled=model.scheduleEnabled;
boundary.flightBoundaryEnabled=true;
boundary=sht_resolve_shaft_load_boundary(boundary,state);
end

function reconstructed=local_reconstruct_boundary(data,userOptions)
% 只由可测飞参构造低阶模型边界。Pt0/Pt1不在MATLAB侧计算，而由C端
% 模式5根据Ps0、Ts_amb、Mach、Tt1及装机恢复系数统一重构。任务级
% K_dist_eq未知，必须留给3.3估计，不能在此读取隐藏真值。排气背压
% 使用与3.1一致的轴功率平方工程模型。
if nargin<2 || isempty(userOptions),userOptions=struct();end
options=local_run_options(userOptions);
required={'Ps0','Mach','Tt1','Ts_amb','Altitude'};
if ~all(ismember(required,data.Properties.VariableNames))
    error('SHT:F32Replay:BoundaryColumns','边界重构输入字段不完整。');
end
ps0=data.Ps0(:);
inletTotalPressureRecovery=options.inletMeanRecovery*ones(size(ps0));
values=[ps0,data.Ts_amb(:),data.Mach(:),data.Tt1(:), ...
    inletTotalPressureRecovery];
if any(~isfinite(values(:))) || any(ps0<=0) || any(data.Ts_amb<=0) || ...
        any(data.Mach<0) || any(data.Tt1<=0) || ...
        any(inletTotalPressureRecovery<=0 | inletTotalPressureRecovery>1) || ...
        ~isfinite(options.designPower_W) || options.designPower_W<=0
    error('SHT:F32Replay:BoundaryValue','边界重构产生非物理数值。');
end
reconstructed=struct();
reconstructed.schemaVersion='SHT_F32_BOUNDARY_RECONSTRUCTION_V2';
reconstructed.Pamb_Pa=ps0;
reconstructed.inletTotalPressureRecovery=inletTotalPressureRecovery;
reconstructed.exhaustBackPressureModel=local_exhaust_model(userOptions);
reconstructed.contract=struct( ...
    'inletBoundaryMode',5, ...
    'staticPressureSource','measured_Ps0', ...
    'totalPressureLaw','C_SHT_ReconstructInletTotalState', ...
    'totalTemperatureSource','measured_Tt1', ...
    'inletMeanRecovery',options.inletMeanRecovery, ...
    'taskDistortionApplied',false, ...
    'unmeasuredPt1ReadFromSource',false, ...
    'pt3EqRole','output_observation_only', ...
    'exhaustBackPressureLaw', ...
    'Pback=Ps0+designRise*(max(Mkp*Np*pi/30,0)/Pdesign)^2', ...
    'exhaustBackPressureDesignRise_Pa', ...
    options.exhaustBackPressureDesignRise_Pa, ...
    'designPower_W',options.designPower_W, ...
    'loadSpeedSource','current_model_state_Np', ...
    'backpressureRole','unmeasured_model_internal_variable');
end

function merged=local_merge_boundary(base,override)
merged=base;
names=fieldnames(override);
for i=1:numel(names), merged.(names{i})=override.(names{i}); end
end

function wf=local_physical_fuel(measured,fuel)
query=measured/fuel.wfDesign;
query=min(max(query,min(fuel.xNodes)),max(fuel.xNodes));
bias=interp1(fuel.xNodes(:),fuel.biasNodes(:),query,'linear');
wf=measured-bias;
if any(~isfinite(wf)) || any(wf<=0)
    error('SHT:F32Replay:FuelInput','燃油偏置修正后出现非正或非有限燃油。');
end
end

function local_validate_evaluation(state,stateDerivative,output,diagnostic,time_s)
value=[state(:);stateDerivative(:);output.Np;output.Ng;output.Pt3; ...
    output.Tt3;output.Tt45;output.Pt45;diagnostic.maxErr; ...
    diagnostic.convergeTag];
if any(~isfinite(value)) || ~ismember(numel(state),[16,29]) || numel(stateDerivative)~=numel(state) || ...
        ~isfield(diagnostic,'evaluationValid') || diagnostic.evaluationValid~=1
    error('SHT:F32Replay:Nonfinite','t=%.6g s出现非有限或错误维数结果。',time_s);
end
if state(1)<1000 || state(1)>40000 || state(2)<5000 || state(2)>70000 || ...
        any(state(3:end)<100) || any(state(3:end)>3000)
    error('SHT:F32Replay:StateRange','t=%.6g s发动机状态越出物理保护范围。',time_s);
end
end

function row=local_output_row(output)
row=[output.Np,output.Ng,output.Pt3,output.Tt45];
end

function row=local_component_row(output,modelMode)
if modelMode==0
    row=[output.HPC_Ncr,output.GT_Ncr,output.PT_Ncr];
    return;
end
row=[output.HPC_Ncr,output.CC_Ncr,output.GT_Ncr, ...
    output.GT2_Ncr,output.PT_Ncr,output.PT2_Ncr];
end

function [index,flowMultiplier,efficiencyMultiplier]=local_reynolds_row(output,nComponent)
required={'reynoldsIndex','reynoldsFlowMultiplier', ...
    'reynoldsEfficiencyMultiplier'};
if ~all(isfield(output,required)) || numel(output.reynoldsIndex)~=nComponent || ...
        numel(output.reynoldsFlowMultiplier)~=nComponent || ...
        numel(output.reynoldsEfficiencyMultiplier)~=nComponent
    error('SHT:F32Replay:ReynoldsOutput', ...
        '当前%d部件回放没有返回完整的雷诺数修正诊断。',nComponent);
end
index=output.reynoldsIndex(:).';
flowMultiplier=output.reynoldsFlowMultiplier(:).';
efficiencyMultiplier=output.reynoldsEfficiencyMultiplier(:).';
end

function value=local_energy_residual(diagnostic)
if isfield(diagnostic,'visserNormalizedEnergyResidual')
    value=diagnostic.visserNormalizedEnergyResidual;
else
    value=NaN;
end
end

function metrics=local_metrics(residual,assumptions)
names={'Np','Ng','Pt3_eq','Tt45'};
units={'rpm','rpm','Pa','K'};
n=numel(names);
rmse=zeros(n,1); meanError=zeros(n,1); mae=zeros(n,1); maximum=zeros(n,1);
reference=zeros(n,1); normalizedRmsePct=zeros(n,1);
for i=1:n
    value=residual(:,i);
    rmse(i)=sqrt(mean(value.^2));
    meanError(i)=mean(value);
    mae(i)=mean(abs(value));
    maximum(i)=max(abs(value));
    row=find(strcmp(cellstr(string(assumptions.name)),names{i}),1);
    reference(i)=assumptions.designReference(row);
    normalizedRmsePct(i)=100*rmse(i)/max(abs(reference(i)),eps);
end
metrics=table(string(names(:)),string(units(:)),rmse,meanError,mae,maximum, ...
    reference,normalizedRmsePct,'VariableNames',{'channel','unit','rmse', ...
    'mean_error','mean_absolute_error','maximum_absolute_error', ...
    'design_reference','rmse_pct_design'});
end

function local_assert_hash(value,field,expected,label)
if ~isfield(value,field) || ~strcmpi(char(value.(field)),expected)
    error('SHT:F32Replay:HashMismatch','%s哈希与2.7结果合同不一致。',label);
end
end

function hash=local_required_hash(value,field,label)
if ~isfield(value,field) || isempty(value.(field))
    error('SHT:F32Replay:MissingSourceHash','%s缺少源哈希。',label);
end
hash=lower(char(value.(field)));
if numel(hash)~=64 || any(~ismember(hash,'0123456789abcdef'))
    error('SHT:F32Replay:InvalidSourceHash','%s不是有效SHA-256。',label);
end
end

function [runtimeFile,runtimeHash,migrated]=local_prepare_runtime_visser_asset( ...
        sourceFile,parameterAsset,programDirectory,dllFile,headerFile,modelFile)
% 为当前DLL生成3.2私有的模型身份绑定副本。这里只允许DLL字节发生迁移；
% 头文件和六部件MDL必须与参数资产完全一致，否则不能证明接口与热模型兼容。
required={'dllSHA256','headerSHA256','modelSHA256'};
if ~isfield(parameterAsset,'modelIdentity') || ...
        ~all(isfield(parameterAsset.modelIdentity,required))
    error('SHT:F32Replay:VisserIdentity', ...
        '当前Visser参数资产缺少完整modelIdentity。');
end
sourceHash=local_file_hash(sourceFile);
dllHash=local_file_hash(dllFile);
headerHash=local_file_hash(headerFile);
modelHash=local_file_hash(modelFile);
headerSame=strcmpi(parameterAsset.modelIdentity.headerSHA256,headerHash);
modelByteSame=strcmpi(parameterAsset.modelIdentity.modelSHA256,modelHash);
modelSemanticSame=modelByteSame;
modelComparison=struct('byteIdentical',modelByteSame, ...
    'semanticEquivalent',modelByteSame,'maximumRelativeNumericDifference',0, ...
    'comparisonTolerance',1e-10);
if ~modelByteSame && isfield(parameterAsset.modelIdentity,'modelFile') && ...
        isfile(parameterAsset.modelIdentity.modelFile)
    modelComparison=local_compare_mdl_semantics( ...
        parameterAsset.modelIdentity.modelFile,modelFile,1e-10);
    modelSemanticSame=modelComparison.semanticEquivalent;
end
if ~headerSame || ~modelSemanticSame
    error('SHT:F32Replay:UnsafeVisserMigration', ...
        ['Visser资产与当前头文件或六部件MDL的数值语义不一致；3.2只允许' ...
         '在接口和模型配置不变时迁移DLL身份。']);
end
if strcmpi(parameterAsset.modelIdentity.dllSHA256,dllHash)
    runtimeFile=sourceFile;
    runtimeHash=sourceHash;
    migrated=false;
    return;
end

runtimeDir=fullfile(programDirectory,'MiddleData', ...
    'flight_model_adapt_3p2','runtime_assets');
if ~isfolder(runtimeDir),mkdir(runtimeDir);end
runtimeFile=fullfile(runtimeDir,sprintf('visser29_%s_%s.mat', ...
    lower(sourceHash(1:12)),lower(dllHash(1:12))));
validExisting=false;
if isfile(runtimeFile)
    existing=load(runtimeFile,'parameterAsset');
    if isfield(existing,'parameterAsset') && ...
            isfield(existing.parameterAsset,'runtimeMigration') && ...
            strcmpi(existing.parameterAsset.modelIdentity.dllSHA256,dllHash) && ...
            strcmpi(existing.parameterAsset.modelIdentity.headerSHA256,headerHash) && ...
            strcmpi(existing.parameterAsset.modelIdentity.modelSHA256,modelHash) && ...
            strcmpi(existing.parameterAsset.runtimeMigration.sourceAssetSHA256, ...
            sourceHash)
        validExisting=true;
    end
end
if ~validExisting
    sourceIdentity=parameterAsset.modelIdentity;
    parameterAsset.modelIdentity.dllFile=dllFile;
    parameterAsset.modelIdentity.dllSHA256=dllHash;
    parameterAsset.modelIdentity.headerFile=headerFile;
    parameterAsset.modelIdentity.headerSHA256=headerHash;
    parameterAsset.modelIdentity.modelFile=modelFile;
    parameterAsset.modelIdentity.modelSHA256=modelHash;
    parameterAsset.runtimeMigration=struct( ...
        'policy','explicit_identity_rebind_current_runtime_replay', ...
        'sourceAssetFile',sourceFile, ...
        'sourceAssetSHA256',sourceHash, ...
        'sourceModelIdentity',sourceIdentity, ...
        'targetDllSHA256',dllHash, ...
        'headerIdentityUnchanged',headerSame, ...
        'modelByteIdentityUnchanged',modelByteSame, ...
        'modelSemanticEquivalent',modelSemanticSame, ...
        'modelSemanticComparison',modelComparison, ...
        'parameterValuesChanged',false);
    save(runtimeFile,'parameterAsset','-v7.3');
end
runtimeHash=local_file_hash(runtimeFile);
migrated=true;
end

function comparison=local_compare_mdl_semantics(firstFile,secondFile,tolerance)
% MDL由“键=值”文本组成。先比较删除数值后的逐行结构，再逐个比较同位置
% 数值；仅允许浮点打印末位差异，字段增删、顺序、字符串和有意义数值变化
% 均判为不兼容。
first=regexp(fileread(firstFile),'\r?\n','split');
second=regexp(fileread(secondFile),'\r?\n','split');
if numel(first)~=numel(second)
    comparison=struct('byteIdentical',false,'semanticEquivalent',false, ...
        'maximumRelativeNumericDifference',Inf,'comparisonTolerance',tolerance);
    return;
end
numberPattern='(?<![A-Za-z_])[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?';
maximumDifference=0;
for i=1:numel(first)
    firstNumbers=regexp(first{i},numberPattern,'match');
    secondNumbers=regexp(second{i},numberPattern,'match');
    firstSkeleton=regexprep(strtrim(first{i}),numberPattern,'<number>');
    secondSkeleton=regexprep(strtrim(second{i}),numberPattern,'<number>');
    firstSkeleton=regexprep(firstSkeleton,'\s+',' ');
    secondSkeleton=regexprep(secondSkeleton,'\s+',' ');
    if ~strcmp(firstSkeleton,secondSkeleton) || ...
            numel(firstNumbers)~=numel(secondNumbers)
        comparison=struct('byteIdentical',false,'semanticEquivalent',false, ...
            'maximumRelativeNumericDifference',Inf, ...
            'comparisonTolerance',tolerance);
        return;
    end
    if isempty(firstNumbers),continue;end
    a=str2double(firstNumbers);b=str2double(secondNumbers);
    if any(~isfinite(a))||any(~isfinite(b))
        comparison=struct('byteIdentical',false,'semanticEquivalent',false, ...
            'maximumRelativeNumericDifference',Inf, ...
            'comparisonTolerance',tolerance);
        return;
    end
    difference=abs(a-b)./max(1,max(abs(a),abs(b)));
    maximumDifference=max(maximumDifference,max(difference));
    if any(difference>tolerance)
        comparison=struct('byteIdentical',false,'semanticEquivalent',false, ...
            'maximumRelativeNumericDifference',maximumDifference, ...
            'comparisonTolerance',tolerance);
        return;
    end
end
comparison=struct('byteIdentical',false,'semanticEquivalent',true, ...
    'maximumRelativeNumericDifference',maximumDifference, ...
    'comparisonTolerance',tolerance);
end

function contract=local_model_semantic_contract(model)
% 缓存必须由模型数值内容而不是候选名称唯一确定。profile.createdAt属于
% 非数值语义字段，每次构造都会变化，若将它计入哈希会导致相同模型无法
% 复用缓存；其余健康向量、调度表和燃油偏置均进入语义合同。
required={'health','profile','scheduleEnabled','fuelBias'};
if ~all(isfield(model,required))
    error('SHT:F32Replay:ModelSemanticContract', ...
        '回放候选缺少健康向量、调度表或燃油偏置合同。');
end
profile=model.profile;
if isstruct(profile) && isfield(profile,'createdAt')
    profile=rmfield(profile,'createdAt');
end
contract=struct('health',model.health(:), ...
    'scheduleEnabled',logical(model.scheduleEnabled), ...
    'profile',profile,'fuelBias',model.fuelBias);
end

function hash=local_file_hash(fileName)
hash=sht_transient_model_adapt_common('fileHash',fileName);
end

function hash=local_struct_hash(value)
bytes=unicode2native(jsonencode(value),'UTF-8');
digest=java.security.MessageDigest.getInstance('SHA-256');
digest.update(typecast(uint8(bytes),'int8'));
raw=typecast(digest.digest(),'uint8');
hash=lower(reshape(dec2hex(raw,2).',1,[]));
end
