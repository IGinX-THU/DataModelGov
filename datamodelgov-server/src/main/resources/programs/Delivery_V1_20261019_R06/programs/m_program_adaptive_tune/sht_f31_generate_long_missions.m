function result = sht_f31_generate_long_missions(userOptions)
%SHT_F31_GENERATE_LONG_MISSIONS 生成3.1第二轮训练和独立测试飞参数据。
%
% 默认三部件发动机和Visser16状态；modelMode=1保留六部件29状态路径。
% 159维输入按对应构型字典赋值，不截断六部件状态或系数作为三部件。
% F31-CAL-01与F31-VA-01分别独立配平和热平衡，按任务级隔离写入
% Excel；仿真真值、传感器偏置实现和内部诊断仅写入MiddleData。

thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir);
if nargin < 1 || isempty(userOptions), userOptions = struct(); end
defaults = struct( ...
    'modelMode',0,'runTag','formal_R011','maximumDuration_s',Inf, ...
    'runCalibration',true, ...
    'runValidation',true, ...
    'measurementErrorEnabled',true, ...
    'plotEnabled',true, ...
    'showFigures',true, ...
    'writeExcel',true, ...
    'saveOutputs',true, ...
    'thermalVariant','structured', ...
    'transientVariant','enhanced', ...
    'installedEffectScale',1, ...
    'calibrationSeed',3101001, ...
    'validationSeed',3102001, ...
    'persistentBiasSeed',3101017, ...
    'missionDefinition',[], 'healthDesignOffset',zeros(159,1), ...
    'outputRoot','', 'dataRoot','', 'reportRoot','', 'thermalTruthRoot','');
options = local_options(defaults,userOptions);
requestedRoots={options.outputRoot,options.dataRoot,options.reportRoot};
paths=struct();
if options.modelMode==0
    paths=sht_f3_three_component_assets('prepare');
    options.outputRoot=fullfile(paths.generation,options.runTag);
    options.dataRoot=fullfile(paths.data,options.runTag);
    options.reportRoot=fullfile(paths.report,'F3_2',options.runTag);
else
    options.outputRoot=fullfile(thisDir,'MiddleData','flight_data_3p1');
    options.dataRoot=fullfile(thisDir,'TestData');
    options.reportRoot=fullfile(fileparts(thisDir),'report_outputs','flight_data_generation_3p1');
end
rootFields={'outputRoot','dataRoot','reportRoot'};
for ri=1:3
    if ~isempty(requestedRoots{ri}),options.(rootFields{ri})=requestedRoots{ri};end
end
if options.saveOutputs && ~isfolder(options.outputRoot),mkdir(options.outputRoot);end

fprintf('\n============================================================\n');
fprintf('3.1 第二轮典型飞行任务与飞参替代数据生成\n');
fprintf('============================================================\n');

%% 1. 稳态真值沿用2.6；热配置和瞬态真值采用3.1独立生成资产
[healthProfile,healthProfileFile,visserAsset,visserAssetFile] = ...
    local_load_truth_assets(thisDir,options.modelMode,paths);
% 退化场景只调整本次内存副本，不覆盖上游真值文件或正式模型配置。
offset=options.healthDesignOffset(:);
assert(numel(offset)==159&&all(isfinite(offset))&&all(offset(59:71)==0), ...
    'SHT:F31:HealthOffset','场景偏移必须为159维且不改变固定瞬态系数。');
healthProfile.truthVectorAtDesign=healthProfile.truthVectorAtDesign(:)+offset;
for hi=1:numel(healthProfile.parameters)
    q=healthProfile.parameters(hi);delta=offset(q.cIndex+1);
    q.designValue=q.designValue+delta;q.kNodes=q.kNodes+delta;
    if q.zeroFlowAnchored,q.kNodes(1)=0;end
    q.deltaNodes=q.kNodes-q.designValue;
    healthProfile.parameters(hi)=q;
end
[visserAsset,visserAssetFile] = sht_f31_thermal_truth_asset( ...
    visserAsset,visserAssetFile,options.thermalVariant,options.transientVariant,options.thermalTruthRoot);
[truthHealth,truthContract] = local_merge_truth_health( ...
    healthProfile,visserAsset);

if options.modelMode==0
    baseCfg=sht_f3_three_component_assets('config',0);
else
    baseCfg = sht_default_config(struct('engine',struct('modelMode',1)));
end
baseCfg.plot.enable = false;
baseCfg.throwOnEngineNonconvergence = false;
baseCfg.engine.healthScheduleProfile = healthProfile;
baseCfg.engine.boundary.health = truthHealth;
baseCfg.engine.boundary.healthScheduleEnabled = true;
if options.modelMode==0
    baseCfg.engine.reynoldsCorrection=sht_f3_reynolds_reference(baseCfg,options.installedEffectScale);
else
    baseCfg.engine.reynoldsCorrection=sht_reynolds_correction_config(options.installedEffectScale);
end

rotorCfg = local_rotor_config(baseCfg);
flightModel = struct( ...
    'designNpRpm',rotorCfg.designNpRpm, ...
    'designTorqueNm',rotorCfg.designTorqueNm, ...
    'hpsPower_W',30000, ...
    'deltaPExhaust_Pa',0, ...
    'installedBoundaryEnabled',true, ...
    'collectivePitchMapping',rotorCfg.collectivePitchMapping, ...
    'rotorLoadModel',rotorCfg.rotorLoadModel, ...
    'exhaustBackPressure',struct('enabled',true, ...
        'designRise_Pa',1500*options.installedEffectScale, ...
    'designPower_W',rotorCfg.designPowerW));
if options.modelMode==0,flightModel.hpsPower_W=0;end
measurementReference = local_measurement_reference(baseCfg,rotorCfg,flightModel);
generationIdentity=struct();
if options.modelMode==0
    generationIdentity=local_generation_identity(thisDir,baseCfg,options,healthProfileFile,visserAssetFile);
end

missionIds = {};
missionSeeds = [];
if options.runCalibration
    missionIds{end+1} = 'F31-CAL-01'; %#ok<AGROW>
    missionSeeds(end+1) = options.calibrationSeed; %#ok<AGROW>
end
if options.runValidation
    missionIds{end+1} = 'F31-VA-01'; %#ok<AGROW>
    missionSeeds(end+1) = options.validationSeed; %#ok<AGROW>
end
if ~isempty(options.missionDefinition)
    assert(isstruct(options.missionDefinition)&&isscalar(options.missionDefinition), ...
        'SHT:F31:SingleMission','外部接口每次只接收一个架次。');
    missionIds={options.missionDefinition.missionId};missionSeeds=options.calibrationSeed;
end
if isempty(missionIds)
    error('SHT:F31DataGen:NoMission', '至少启用训练任务或独立测试任务之一。');
end

%% 2. 每条任务独立配平、热平衡并连续运行
runs = repmat(local_empty_run(),0,1);
for i = 1:numel(missionIds)
    definition=missionIds{i};
    if ~isempty(options.missionDefinition),definition=options.missionDefinition;end
    mission = sht_f31_mission_definition(definition,baseCfg.Tsim);
    mission=local_limit_mission(mission,options.maximumDuration_s);
    mission.expectedStateCount=29;if options.modelMode==0,mission.expectedStateCount=16;end
    checkpointFile=fullfile(options.outputRoot,[mission.missionId,'_checkpoint.mat']);
    if options.modelMode==0&&options.saveOutputs&&isfile(checkpointFile)
        saved=load(checkpointFile,'item','generationIdentity');
        assert(isfield(saved,'generationIdentity')&&isequaln(saved.generationIdentity,generationIdentity), ...
            'SHT:F31:CheckpointIdentity','造数源码/模型/随机配置发生变化，请选择新runTag。');
        assert(saved.item.quality.passed,'SHT:F31:FailedCheckpoint','失败架次保留诊断，请使用新runTag重算。');
        runs(end+1,1)=saved.item; %#ok<AGROW>
        fprintf('F3 checked checkpoint reused: %s\n',mission.missionId);
        continue;
    end
    boundaryMission = local_boundary_mission(mission,options);
    initialBoundary = sht_flight_boundary_step(0,rotorCfg.designNpRpm, ...
        boundaryMission,flightModel);
    fprintf('1/4 %s独立配平：h=%.1f m，M=%.4f，theta=%.3f deg ...\n', ...
        mission.missionId,initialBoundary.altitude_m,initialBoundary.mach, ...
        initialBoundary.theta_deg);
    [missionCfg,trim,thermalEquilibrium] = local_prepare_mission_config( ...
        baseCfg,mission,boundaryMission,flightModel,rotorCfg, ...
        truthHealth,healthProfile,visserAssetFile,initialBoundary);

    measurementModel = sht_f31_flight_measurement('model', ...
        missionSeeds(i),mission.missionId,options.measurementErrorEnabled, ...
        measurementReference,options.persistentBiasSeed);
    missionCfg = sht_f31_flight_measurement( ...
        'configure',missionCfg,measurementModel);
    missionCfg = sht_validate_runtime_config(missionCfg);

    fprintf('2/4 运行%s：%.0f s，%d点，%d段 ...\n', ...
        mission.missionId,mission.duration_s,mission.sampleCount, ...
        mission.segmentCount);
    timerId = tic;
    simulation = sht_simulate_control_m(missionCfg);
    runtime_s = toc(timerId);
    truthLog = sht_f31_flight_measurement( ...
        'prepareTruthLog',simulation.log);
    [measuredLog,sensorError] = sht_f31_flight_measurement( ...
        'apply',truthLog,simulation.log,measurementModel);
    quality = sht_f31_quality_metrics(simulation,mission, ...
        rotorCfg.designNpRpm,rotorCfg.designPowerW,thermalEquilibrium);

    item = local_empty_run();
    item.mission = mission;
    item.boundaryMission = boundaryMission;
    item.cfg = missionCfg;
    item.initialBoundary = initialBoundary;
    item.trim = trim;
    item.thermalEquilibrium = thermalEquilibrium;
    item.runtime_s = runtime_s;
    item.simulation = simulation;
    item.truthLog = truthLog;
    item.measuredLog = measuredLog;
    item.measurementModel = measurementModel;
    item.sensorError = sensorError;
    item.publicMeasurementAssumptions = ...
        sht_f31_flight_measurement('publicAssumptions',measurementModel);
    item.measurementTable = local_measurement_table(mission,measuredLog);
    recordStride=1;
    if options.modelMode==0
        recordStride=round(.1/baseCfg.Tsim);
        item.measurementTable.Mkg=[];
    end
    item.measurementTable=item.measurementTable(1:recordStride:end,:);
    item.measurementTable.sample_id=(1:height(item.measurementTable)).';
    item.truthTable = local_truth_table( ...
        mission,truthLog,rotorCfg.designNpRpm,rotorCfg.designPowerW);
    item.quality = quality;
    runs(end+1,1) = item; %#ok<AGROW>
    if options.saveOutputs
        save(checkpointFile,'item','options','generationIdentity','-v7.3');
    end
    fprintf(['    完成：%.1f s；maxErr=%.3e；能量残差=%.3e；' ...
        'Np最大偏差=%.3f%%；%s\n'],runtime_s, ...
        quality.maximumCommonWorkResidual, ...
        quality.maximumNormalizedEnergyResidual, ...
        quality.maximumNpRegulationErrorPct,local_pass_text(quality.passed));
end

%% 3. 检查训练/测试隔离和覆盖关系
if options.modelMode==0
    finalIdentity=local_generation_identity(thisDir,baseCfg,options,healthProfileFile,visserAssetFile);
    assert(isequaln(generationIdentity,finalIdentity),'SHT:F31:RuntimeChanged', ...
        '运行期间调用源码或资产发生改变；保留检查点，但不写正式Excel，请核查Owner变更并使用新批次。');
end
crossMission = local_cross_mission_validation(runs);
fprintf('3/4 训练/测试任务隔离与覆盖检查：%s\n', ...
    local_pass_text(crossMission.passed));

%% 4. 失败任务保留诊断，不覆盖上一套可用正式数据
generationPassed = all(arrayfun(@(item)item.quality.passed,runs)) && crossMission.passed;
if ~generationPassed
    diagnosticDir=options.outputRoot;
    if ~isfolder(diagnosticDir),mkdir(diagnosticDir);end
    save(fullfile(diagnosticDir,'failed_generation_diagnostic.mat'), ...
        'runs','crossMission','options','visserAssetFile','-v7.3');
    error('SHT:F31DataGen:Validation', ...
        '生成未通过质量检查，正式Excel未覆盖；失败诊断已保留。');
end
%% 5. 写入正式Excel、隐藏真值和图形报告
output = local_write_outputs(thisDir,runs,truthContract,healthProfile, ...
    healthProfileFile,visserAsset,visserAssetFile,options,baseCfg, ...
    crossMission);

result = struct();
result.schemaVersion = 'F31_DATA_GENERATION_V4';
result.generatedAt = datestr(now,31);
result.generationIdentity=generationIdentity;
result.options = options;
result.model = struct('modelMode',options.modelMode,'thermalModelMode',3, ...
    'inletBoundaryMode',2, ...
    'stateCount',mission.expectedStateCount,'healthLength',159,'sampleTime_s',baseCfg.Tsim, ...
    'sampleRate_Hz',1/baseCfg.Tsim, ...
    'installedEffectScale',options.installedEffectScale, ...
    'formalMeasurementContract','F31_FLIGHT_EXCEL_V3');
result.model.integrationStep_s=baseCfg.Tsim;
result.model.recordStep_s=baseCfg.Tsim;
if options.modelMode==0
    result.model.recordStep_s=.1;
    result.model.formalMeasurementContract='F31_THREE_FLIGHT_EXCEL_R011';
end
result.model.recordRate_Hz=1/result.model.recordStep_s;
result.truthContract = truthContract;
result.thermalTruth = visserAsset.flightTruth;
result.thermalTruthAssetFile = visserAssetFile;
result.runs = runs;
result.crossMissionValidation = crossMission;
result.output = output;
result.passed = all(arrayfun(@(item)item.quality.passed,runs)) && ...
    crossMission.passed;
assignin('base','Start_FlightDataGen_01_result',result);
if options.saveOutputs
    % 仅内部审计/复算使用；下游正式接口仍是只含测量量的Excel。
    checkpointDir=options.outputRoot;
    if ~isfolder(checkpointDir),mkdir(checkpointDir);end
    save(fullfile(checkpointDir,'F31_generation_result.mat'),'result','-v7.3');
end

fprintf('4/4 数据、质量报告和图形写入完成。\n');
local_print_summary(result);
if ~result.passed
    error('SHT:F31DataGen:Validation', ...
        '3.1第二轮飞参数据生成未通过质量验收，请查看结果中的failedChecks。');
end
end

function options = local_options(defaults,userOptions)
if ~isstruct(userOptions) || ~isscalar(userOptions)
    error('SHT:F31DataGen:Options', 'userOptions必须为标量结构体。');
end
options = defaults;
names = fieldnames(userOptions);
for i = 1:numel(names)
    if ~isfield(defaults,names{i})
        error('SHT:F31DataGen:Options', '未知入口选项%s。',names{i});
    end
    options.(names{i}) = userOptions.(names{i});
end
assert(isscalar(options.modelMode)&&ismember(options.modelMode,[0,1]),'modelMode必须为0或1。');
assert(ischar(options.runTag)&&~isempty(regexp(options.runTag,'^[A-Za-z0-9_]+$','once')), ...
    'runTag只允许字母、数字和下划线。');
assert(isscalar(options.maximumDuration_s)&&options.maximumDuration_s>=10 && ...
    (isfinite(options.maximumDuration_s)||options.maximumDuration_s==Inf),'短测时长无效。');
assert(isinf(options.maximumDuration_s)||~strcmp(options.runTag,'formal_R011'), ...
    '短测必须使用独立runTag，不能标记为完整正式任务。');
assert(ismember(options.thermalVariant,{'structured','shared'}), ...
    'thermalVariant须为structured或shared。');
assert(ismember(options.transientVariant,{'enhanced','legacy'}), ...
    'transientVariant须为enhanced或legacy。');
logicalNames = {'runCalibration','runValidation','measurementErrorEnabled', ...
    'plotEnabled','showFigures','writeExcel','saveOutputs'};
for i = 1:numel(logicalNames)
    value = options.(logicalNames{i});
    if ~(islogical(value) || isnumeric(value)) || ~isscalar(value) || ...
            ~isfinite(value)
        error('SHT:F31DataGen:Options', '%s必须为有限标量开关。',logicalNames{i});
    end
    options.(logicalNames{i}) = logical(value);
end
seedNames = {'calibrationSeed','validationSeed','persistentBiasSeed'};
for i = 1:numel(seedNames)
    value = options.(seedNames{i});
    if ~isscalar(value) || ~isfinite(value) || value < 0 || value ~= round(value)
        error('SHT:F31DataGen:Options', '%s必须为非负整数。',seedNames{i});
    end
end
if ~isnumeric(options.installedEffectScale) || ...
        ~isreal(options.installedEffectScale) || ...
        ~isscalar(options.installedEffectScale) || ...
        ~isfinite(options.installedEffectScale) || ...
        options.installedEffectScale < 0 || options.installedEffectScale > 2
    error('SHT:F31DataGen:Options', ...
        'installedEffectScale必须为[0,2]内的有限实数。');
end
end

function [profile,profileFile,asset,assetFile] = local_load_truth_assets(thisDir,modelMode,paths)
if modelMode==0
    profileFile=fullfile(thisDir,'MiddleData','three_component','three_component_health_schedule_latest.mat');
    s=load(profileFile,'profile');profile=s.profile;
    assert(profile.modelMode==0&&numel(profile.truthVectorAtDesign)==159,'三部件调度真值合同错误。');
    assetFile=paths.visserAsset;s=load(assetFile,'parameterAsset');asset=s.parameterAsset;
    return;
end
profileFile = fullfile(thisDir,'MiddleData', ...
    'six_component_health_schedule_truth_latest.mat');
sourceAssetFile = fullfile(thisDir,'MiddleData', ...
    'transient_effects_split_visser29_parameters.mat');
if exist(profileFile,'file')~=2 || exist(sourceAssetFile,'file')~=2
    error('SHT:F31DataGen:TruthAsset', ...
        '缺少六部件健康调度真值或Visser 29状态参数资产。');
end
p = load(profileFile,'result');
v = load(sourceAssetFile,'parameterAsset');
if ~isfield(p,'result') || ~p.result.pass || ~isfield(p.result,'profile')
    error('SHT:F31DataGen:TruthAsset', '六部件健康调度真值资产未通过验收。');
end
if ~isfield(v,'parameterAsset')
    error('SHT:F31DataGen:TruthAsset', 'Visser参数资产结构无效。');
end
profile = p.result.profile;
asset = v.parameterAsset;
if profile.modelMode~=1 || numel(profile.truthVectorAtDesign)~=159 || ...
        asset.interface.thermalModelMode~=3 || ...
        asset.interface.derivativeOutputCount~=29 || ...
        numel(asset.truthHealth)~=159
    error('SHT:F31DataGen:TruthAsset', ...
        '真值资产不是六部件159维/Visser 29状态正式接口。');
end
[asset,assetFile] = local_prepare_runtime_visser_asset( ...
    sourceAssetFile,asset,thisDir);
end

function [asset,runtimeFile] = local_prepare_runtime_visser_asset( ...
        sourceFile,asset,thisDir)
% 进口接口改动会改变DLL字节哈希，但不改变Visser标称参数。3.1只在
% 头文件和六部件MDL仍与源资产一致时生成私有运行副本，绝不覆盖源资产。
required = {'dllSHA256','headerSHA256','modelSHA256'};
if ~isfield(asset,'modelIdentity') || ...
        ~all(isfield(asset.modelIdentity,required))
    error('SHT:F31DataGen:VisserIdentity','Visser资产缺少完整模型身份。');
end
cfg = sht_default_config(struct('engine',struct('modelMode',1)));
dllFile = fullfile(cfg.engine.interface.controlDir,'GTESS.dll');
headerFile = fullfile(cfg.engine.interface.controlDir, ...
    cfg.engine.interface.headerName);
modelFile = cfg.engine.modelConfiguration;
dllHash = local_sha256(dllFile);
headerHash = local_sha256(headerFile);
modelHash = local_sha256(modelFile);
if ~strcmpi(asset.modelIdentity.headerSHA256,headerHash) || ...
        ~strcmpi(asset.modelIdentity.modelSHA256,modelHash)
    error('SHT:F31DataGen:UnsafeVisserMigration', ...
        ['Visser资产与当前头文件或六部件MDL不一致；3.1只允许在' ...
         '参数模型不变时迁移DLL身份。']);
end
if strcmpi(asset.modelIdentity.dllSHA256,dllHash)
    runtimeFile = sourceFile;
    return;
end

sourceHash = local_sha256(sourceFile);
runtimeDir = fullfile(thisDir,'MiddleData','flight_data_3p1','runtime_assets');
if ~isfolder(runtimeDir), mkdir(runtimeDir); end
runtimeFile = fullfile(runtimeDir,sprintf('visser29_%s_%s.mat', ...
    lower(sourceHash(1:12)),lower(dllHash(1:12))));
if isfile(runtimeFile)
    loaded = load(runtimeFile,'parameterAsset');
    if isfield(loaded,'parameterAsset') && ...
            isfield(loaded.parameterAsset,'runtimeMigration') && ...
            strcmpi(loaded.parameterAsset.modelIdentity.dllSHA256,dllHash) && ...
            strcmpi(loaded.parameterAsset.runtimeMigration.sourceAssetSHA256, ...
            sourceHash)
        asset = loaded.parameterAsset;
        return;
    end
end

sourceIdentity = asset.modelIdentity;
asset.modelIdentity.dllFile = dllFile;
asset.modelIdentity.dllSHA256 = dllHash;
asset.modelIdentity.headerFile = headerFile;
asset.modelIdentity.headerSHA256 = headerHash;
asset.modelIdentity.modelFile = modelFile;
asset.modelIdentity.modelSHA256 = modelHash;
asset.runtimeMigration = struct( ...
    'schemaVersion','F31_VISSER_RUNTIME_MIGRATION_V1', ...
    'createdAt',datestr(now,31), ...
    'sourceAssetFile',sourceFile, ...
    'sourceAssetSHA256',sourceHash, ...
    'sourceModelIdentity',sourceIdentity, ...
    'targetDllSHA256',dllHash, ...
    'reason','inlet_boundary_interface_extension_only', ...
    'parameterValuesChanged',false);
parameterAsset = asset; %#ok<NASGU>
save(runtimeFile,'parameterAsset','-v7.3');
end

function [health,contract] = local_merge_truth_health(profile,asset)
health = profile.truthVectorAtDesign(:);
localIndex = asset.truthHealthMapping.localMatlabIndex(:);
if any(abs(health(localIndex))>1e-14)
    error('SHT:F31DataGen:HealthConflict', ...
        '稳态健康调度资产占用了本模型的瞬态通道。');
end
health(localIndex) = asset.truthHealth(localIndex);
contract = struct('version','F31_COMBINED_HEALTH_TRUTH_V1', ...
    'healthLength',159,'steadyScheduleVersion',profile.schemaVersion, ...
    'transientAssetVersion',asset.assetVersion, ...
    'activeSteadyHealthNumber',profile.activeCIndex(:), ...
    'activeTransientHealthNumber', ...
    asset.truthHealthMapping.localHealthNumber( ...
    asset.truthHealthMapping.localValue~=0), ...
    'nonzeroHealthCount',nnz(health),'truthHealth',health);
end

function rotorCfg = local_rotor_config(cfg)
designNp = cfg.controller.DPpara.Np0;
designPower = cfg.engine.initial.power0;
tailToMainPowerRatio = 0.10;
mainDesignPower = designPower/(1+tailToMainPowerRatio);
tailDesignPower = designPower-mainDesignPower;
rotorCfg = struct('enabled',true,'inputMode','collectivePitch', ...
    'designNpRpm',designNp,'designPowerW',designPower, ...
    'designTorqueNm',designPower/(designNp*pi/30), ...
    'collectivePitchMapping',struct('thetaZeroDeg',0, ...
    'thetaDesignDeg',12,'profileTorqueFraction',0.15, ...
    'thetaValidRangeDeg',[6,14]), ...
    'rotorLoadModel',struct('enabled',true, ...
        'mainDesignPower_W',mainDesignPower, ...
        'tailDesignPower_W',tailDesignPower, ...
        'totalDesignPower_W',designPower, ...
        'tailToMainPowerRatio',tailToMainPowerRatio, ...
        'tailZeroPitch_deg',0,'tailDesignPitch_deg',10, ...
        'tailPitchValidRange_deg',[-8,18], ...
        'tailProfilePowerFraction',0.15, ...
        'designDensity_kgpm3',1.225));
end

function boundaryMission = local_boundary_mission(mission,options)
boundaryMission = struct();
boundaryMission.missionId = mission.missionId;
boundaryMission.duration_s = mission.nodeTime_s(end);
boundaryMission.nodeTime_s = mission.nodeTime_s;
boundaryMission.thetaNode_deg = mission.thetaNode_deg;
boundaryMission.tailPitchNode_deg = mission.tailPitchNode_deg;
boundaryMission.nodeSigmaDist = ...
    (1-options.installedEffectScale*mission.K_dist_eq) * ...
    ones(size(mission.nodeTime_s));
boundaryMission.sigmaIn = 0.995;
boundaryMission.altitude_m = mission.altitudeNode_m;
boundaryMission.mach = mission.machNode;
boundaryMission.deltaT_K = 10;
boundaryMission.deltaTIn_K = 0;
boundaryMission.segmentId = mission.segment.segment_id(:).';
boundaryMission.interpolationMethod = 'halfCosine';
end

function [cfg,trim,thermalEquilibrium] = local_prepare_mission_config( ...
        baseCfg,mission,boundaryMission,flightModel,rotorCfg,truthHealth, ...
        healthProfile,visserAssetFile,initialBoundary)
cfg = baseCfg;
cfg.Tsim = mission.sampleTime_s;
cfg.Tctrl = mission.sampleTime_s;
cfg.stopTime = mission.duration_s;
cfg.engine.boundary.inletBoundaryMode = 2;
cfg.engine.boundary.altitude = initialBoundary.altitude_m;
cfg.engine.boundary.Mach = initialBoundary.mach;
cfg.engine.boundary.deltaTemperature = initialBoundary.deltaT_K;
cfg.engine.boundary.Pamb = initialBoundary.Pamb_Pa;
cfg.engine.boundary.Tamb = initialBoundary.Ts_K;
cfg.engine.boundary.clearanceInletTotalTemperature_K=initialBoundary.Tt1_K;
cfg.engine.boundary.inletTotalPressureRecovery = ...
    initialBoundary.totalPressureRecovery;
if isfield(initialBoundary,'Pback_Pa')
    cfg.engine.boundary.Pback = initialBoundary.Pback_Pa;
end
cfg.engine.boundary.power = initialBoundary.Pload_W;
cfg.engine.boundary.Mkp = initialBoundary.Qload_Nm;
cfg.engine.boundary.hpsPower = initialBoundary.hpsPower_W;
cfg.engine.boundary.Mkg = initialBoundary.hpsPower_W / ...
    (cfg.engine.initial.Ng0*pi/30);
cfg.engine.boundary.ptLoadInputMode = 'torque';
cfg.engine.boundary.gtLoadInputMode = 'power';
cfg.engine.boundary.health = truthHealth;
cfg.engine.boundary.healthScheduleEnabled = true;
cfg.engine.healthScheduleProfile = healthProfile;

trim = sht_trim_health_steady_point( ...
    cfg,rotorCfg.designNpRpm,initialBoundary.Pload_W,truthHealth);
if ~trim.converged || trim.ret~=0 || trim.residualInfinityNorm>1e-6 || ...
        abs(trim.Mkp-initialBoundary.Qload_Nm)>1e-3
    error('SHT:F31DataGen:Trim', ...
        ['%s独立配平失败：converged=%d，ret=%d，残差=%.3e，' ...
        '扭矩差=%.3e N*m。'],mission.missionId,trim.converged,trim.ret, ...
        trim.residualInfinityNorm,trim.Mkp-initialBoundary.Qload_Nm);
end
cfg = local_apply_initial_state(cfg,trim,initialBoundary,rotorCfg,truthHealth);
% 配置函数载入29状态拓扑后，再恢复当前任务边界和同一真实健康调度。
if cfg.engine.modelMode==0
    [cfg,asset]=sht_configure_transient_heat_state(cfg,visserAssetFile);
    cfg.engine.transientEffects.stepInTemplate=sht_build_transient_step_in_template(asset,'joint_full',15);
    asset.referenceTable.PT.extrapolationPolicy='continuous_hull_projection';
    cfg.engine.transientEffects.clearanceReferenceTable=sht_prepare_clearance_reference_lookup(asset.referenceTable);
else
    [cfg,~] = sht_configure_transient_visser29(cfg,'joint_full',visserAssetFile);
end
cfg.engine.reynoldsCorrection = baseCfg.engine.reynoldsCorrection;
cfg.engine.boundary.health = truthHealth;
cfg.engine.boundary.healthScheduleEnabled = true;
cfg.engine.healthScheduleProfile = healthProfile;
cfg = local_apply_initial_state(cfg,trim,initialBoundary,rotorCfg,truthHealth);
if cfg.engine.modelMode==0
    engine=sht_engine_open(cfg.engine);cleanup=onCleanup(@()sht_engine_close(engine));
    state=[trim.Np;trim.Ng;cfg.engine.initial.state(3:end)];
    sht_tc27_reset_gas_seed(engine,trim.varIte);
    e=sht_thermal_equilibrium_solve(engine,state,trim.Wf,cfg.engine.boundary,'trim_fixed_np', ...
        struct('maximumIterations',40,'finalJacobianAudit',false,'verbose',false));
    assert(e.physicalValid,'SHT:F31:InitialEquilibrium','任务初始气热平衡失败：%s',e.stopReason);
    trim.Ng=e.state(2);trim.Wf=e.fuelFlow_kgps;
    held=engine.callContext.engPtr.eng;trim.varIte=double(held.varIte(1:6));
    cfg=local_apply_initial_state(cfg,trim,initialBoundary,rotorCfg,truthHealth);
    cfg.engine.initial.commonWorkingSeed=trim.varIte;
    cfg.engine.initial.state=e.state;
    thermalEquilibrium=e;
    thermalEquilibrium.finalMaximumDerivative_Kps=e.finalMaximumThermalDerivative_Kps;
    clear cleanup;
else
    [initialTemperatureState,thermalEquilibrium]=sht_refine_visser_operating_thermal_equilibrium(cfg,trim);
    cfg.engine.initial.state=[trim.Np;trim.Ng;initialTemperatureState];
end

nodePower_W = zeros(size(mission.nodeTime_s));
for nodeIndex = 1:numel(mission.nodeTime_s)
    nodeBoundary = sht_flight_boundary_step( ...
        mission.nodeTime_s(nodeIndex),rotorCfg.designNpRpm, ...
        boundaryMission,flightModel);
    nodePower_W(nodeIndex) = nodeBoundary.Pload_W;
end
cfg.reference.commandMode = 'schedule';
cfg.reference.baseNp = rotorCfg.designNpRpm;
cfg.reference.baseNg = trim.Ng;
cfg.reference.powerBase = initialBoundary.Pload_W;
cfg.reference.scheduleTime_s = mission.nodeTime_s;
cfg.reference.scheduleNp_rpm = ...
    rotorCfg.designNpRpm*ones(size(mission.nodeTime_s));
cfg.reference.schedulePower_W = nodePower_W;
cfg.reference.npPulseAmplitude = 0;
cfg.reference.enablePowerPulse = false;
cfg.flight.rotorLoad = rotorCfg;
cfg.flight.boundarySchedule = struct('enabled',true, ...
    'mission',boundaryMission,'model',flightModel);
cfg = sht_validate_runtime_config(cfg);
end

function cfg = local_apply_initial_state( ...
        cfg,trim,initialBoundary,rotorCfg,truthHealth)
cfg.plot.enable = false;
cfg.engine.initial.Np0 = trim.Np;
cfg.engine.initial.Ng0 = trim.Ng;
cfg.engine.initial.Wf0 = trim.Wf;
cfg.engine.initial.power0 = initialBoundary.Pload_W;
cfg.engine.initial.T45 = trim.T45;
cfg.engine.initial.Mkp = initialBoundary.Qload_Nm;
cfg.engine.initial.Mkg = trim.Mkg;
cfg.actuator.initialWf = trim.Wf;
cfg.controller.initial.Np = trim.Np;
cfg.controller.initial.Ng = trim.Ng;
cfg.controller.initial.Wf = trim.Wf;
cfg.engine.boundary.power = initialBoundary.Pload_W;
cfg.engine.boundary.Mkp = initialBoundary.Qload_Nm;
cfg.engine.boundary.hpsPower = initialBoundary.hpsPower_W;
cfg.engine.boundary.Mkg = trim.Mkg;
cfg.engine.boundary.ptLoadInputMode = 'torque';
cfg.engine.boundary.gtLoadInputMode = 'power';
cfg.engine.boundary.health = truthHealth(:);
cfg.engine.boundary.healthScheduleEnabled = true;
if isfield(initialBoundary,'Pback_Pa')
    cfg.engine.boundary.Pback = initialBoundary.Pback_Pa;
end
cfg.flight.rotorLoad = rotorCfg;
end

function reference = local_measurement_reference(baseCfg,rotorCfg,flightModel)
spec = sht_measurement_bias_generator('specification');
reference = struct();
names = {'Wf','T45','Pt2','Tt1','Pt3','Tt3','Pt45','Tamb','Pamb'};
for i = 1:numel(names)
    index = find(strcmp(spec.name,names{i}),1,'first');
    if isempty(index)
        error('SHT:F31DataGen:MeasurementReference', ...
            '公共测量字典缺少%s。',names{i});
    end
    outputName = names{i};
    if strcmp(outputName,'T45'), outputName = 'Tt45'; end
    reference.(outputName) = spec.designReference(index);
end
reference.Np = rotorCfg.designNpRpm;
reference.Ng = baseCfg.engine.initial.Ng0;
reference.Mkp = rotorCfg.designTorqueNm;
reference.Mkg = flightModel.hpsPower_W/(reference.Ng*pi/30);
reference.Altitude = 100;
reference.Mach = 1;
reference.Ps0 = reference.Pamb;
reference.Pt3_eq = reference.Pt3;
reference.Ts_amb = reference.Tamb;
reference.modelMode=baseCfg.engine.modelMode;
if baseCfg.engine.modelMode==0
    % 只借用三部件设计尺度，不继承台架的实际偏置、噪声或后验。
    three=sht_tc24_measurement_specification();
    target={'Wf','Tt45','Tt1','Pt3','Tt3','Pt45','Tamb','Pamb'};
    source={'Wf','Tt45','Tt1','Ptb3','Ttb3','Pt45','Tamb','Pamb'};
    for j=1:numel(target),reference.(target{j})=three.designReference(three.name==source{j});end
    reference.Pt2=98285.25;reference.Ps0=reference.Pamb;
    reference.Pt3_eq=reference.Pt3;reference.Ts_amb=reference.Tamb;
end
end

function item = local_empty_run()
item = struct('mission',struct(),'boundaryMission',struct(),'cfg',struct(), ...
    'initialBoundary',struct(),'trim',struct(), ...
    'thermalEquilibrium',struct(),'runtime_s',NaN,'simulation',struct(), ...
    'truthLog',struct(),'measuredLog',struct(),'measurementModel',struct(), ...
    'sensorError',struct(),'publicMeasurementAssumptions',table(), ...
    'measurementTable',table(),'truthTable',table(),'quality',struct());
end

function tableValue = local_measurement_table(mission,log)
n = mission.sampleCount;
sample_id = (1:n).';
time_s = mission.time_s(:);
Ps0=log.Ps0(:); Tt1=log.Tt1(:); Pt3_eq=log.Pt3_eq(:);
Ng=log.Ng(:); Np=log.Np(:);
Mkp=log.Mkp(:); Mkg=log.Mkg(:); Wf=log.Wf(:); Tt45=log.Tt45(:);
Altitude=log.Altitude(:); Mach=log.Mach(:); Ts_amb=log.Ts_amb(:);
tableValue = table(sample_id,time_s,Ps0,Tt1,Pt3_eq,Ng,Np, ...
    Mkp,Mkg,Wf,Tt45,Altitude,Mach,Ts_amb);
end

function tableValue = local_truth_table(mission,log,designNp,designPower)
tableValue = local_measurement_table(mission,log);
n = height(tableValue);
tableValue.mission_id = repmat({mission.missionId},n,1);
tableValue.dataset_role = repmat({mission.datasetRole},n,1);
tableValue.segment_id = mission.segment_id(:);
tableValue.segment_type = mission.segment_type(:);
tableValue.altitude_command_m = mission.altitude_m(:);
tableValue.mach_command = mission.mach(:);
tableValue.theta_command_deg = mission.theta_cmd_deg(:);
tableValue.tail_pitch_command_deg = mission.tail_pitch_cmd_deg(:);
tableValue.K_dist_eq = mission.K_dist_eq*ones(n,1);
tableValue.Npr_ref = mission.Npr_ref(:);
tableValue.steady_eligible = mission.steady_eligible(:);
tableValue.slow_transition_eligible = mission.slow_transition_eligible(:);
tableValue.transient_eligible = mission.transient_eligible(:);
tableValue.Pload_true = log.Pload(:);
tableValue.Npr_true = log.Np(:)/designNp;
tableValue.Pload_ratio_true = log.Pload(:)/designPower;
tableValue.Pt2_true = log.Pt2(:);
tableValue.Pt3_true = log.Pt3(:);
tableValue.Tt3_true = log.Tt3(:);
tableValue.Pt45_true = log.Pt45(:);
tableValue.Pamb_true = log.Pamb(:);
tableValue.Tamb_true = log.Tamb(:);
tableValue.Pback_true = log.flightPback(:);
tableValue.deltaP_exhaust_true = log.flightDeltaPExhaust(:);
tableValue.main_rotor_power_true = log.mainRotorPower(:);
tableValue.tail_rotor_power_true = log.tailRotorPower(:);
tableValue.tail_load_factor_true = log.tailLoadFactor(:);
tableValue.AC_Ncr = log.HPC_Ncr(:);
tableValue.CC_Ncr = log.CC_Ncr(:);
tableValue.GT1_Ncr = log.GT_Ncr(:);
tableValue.GT2_Ncr = log.GT2_Ncr(:);
tableValue.PT1_Ncr = log.PT_Ncr(:);
tableValue.PT2_Ncr = log.PT2_Ncr(:);
tableValue.common_work_residual = log.maxErr(:);
tableValue.visser_energy_residual = log.visserNormalizedEnergyResidual(:);
if isfield(log,'reynoldsIndex')
    componentNames = cellstr(log.reynoldsComponentName);
    for componentIndex = 1:numel(componentNames)
        tableValue.([componentNames{componentIndex},'_RNI']) = ...
            log.reynoldsIndex(:,componentIndex);
        tableValue.([componentNames{componentIndex},'_RNI_W_multiplier']) = ...
            log.reynoldsFlowMultiplier(:,componentIndex);
        tableValue.([componentNames{componentIndex},'_RNI_eta_multiplier']) = ...
            log.reynoldsEfficiencyMultiplier(:,componentIndex);
    end
end
if size(log.xEngine,2)==16
    tableValue.AC_Ncr=[];tableValue.CC_Ncr=[];
    tableValue.GT1_Ncr=[];tableValue.GT2_Ncr=[];tableValue.PT1_Ncr=[];tableValue.PT2_Ncr=[];
    tableValue.HPC_Ncr=log.HPC_Ncr(:);tableValue.GT_Ncr=log.GT_Ncr(:);tableValue.PT_Ncr=log.PT_Ncr(:);
end
end

function validation = local_cross_mission_validation(runs)
validation = struct('executed',numel(runs)==2,'passed',true, ...
    'validationWithinCalibrationDomain',true, ...
    'persistentBiasIdentical',true,'persistentFuelBiasCurveIdentical',true, ...
    'missionFuelBiasCurveIndependent',true,'independentNoiseSeeds',true, ...
    'details','Only one mission was requested.');
if numel(runs)~=2, return; end
calIndex = find(arrayfun(@(r)strcmp(r.mission.missionId,'F31-CAL-01'),runs),1);
valIndex = find(arrayfun(@(r)strcmp(r.mission.missionId,'F31-VA-01'),runs),1);
if isempty(calIndex) || isempty(valIndex)
    validation.passed = false;
    validation.details = 'Training or validation mission identity is missing.';
    return;
end
cal = runs(calIndex); val = runs(valIndex);
complete=cal.mission.duration_s==cal.mission.nodeTime_s(end) && ...
    val.mission.duration_s==val.mission.nodeTime_s(end);
validation.domainCheckExecuted=complete;
tol = 1e-12;
validation.validationWithinCalibrationDomain = ...
    min(val.mission.altitude_m)>=min(cal.mission.altitude_m)-tol && ...
    max(val.mission.altitude_m)<=max(cal.mission.altitude_m)+tol && ...
    min(val.mission.mach)>=min(cal.mission.mach)-tol && ...
    max(val.mission.mach)<=max(cal.mission.mach)+tol && ...
    min(val.mission.theta_cmd_deg)>=min(cal.mission.theta_cmd_deg)-tol && ...
    max(val.mission.theta_cmd_deg)<=max(cal.mission.theta_cmd_deg)+tol && ...
    min(val.mission.tail_pitch_cmd_deg)>= ...
        min(cal.mission.tail_pitch_cmd_deg)-tol && ...
    max(val.mission.tail_pitch_cmd_deg)<= ...
        max(cal.mission.tail_pitch_cmd_deg)+tol;
calBias = [cal.measurementModel.fields.persistentBias];
valBias = [val.measurementModel.fields.persistentBias];
validation.persistentBiasIdentical = isequal(calBias,valBias);
validation.persistentFuelBiasCurveIdentical = isequal( ...
    cal.measurementModel.fuelBiasSchedule.persistentBiasNodes, ...
    val.measurementModel.fuelBiasSchedule.persistentBiasNodes);
validation.missionFuelBiasCurveIndependent = ~isequal( ...
    cal.measurementModel.fuelBiasSchedule.missionBiasNodes, ...
    val.measurementModel.fuelBiasSchedule.missionBiasNodes);
validation.independentNoiseSeeds = ...
    cal.measurementModel.randomSeed~=val.measurementModel.randomSeed;
validation.passed = validation.validationWithinCalibrationDomain && ...
    validation.persistentBiasIdentical && ...
    validation.persistentFuelBiasCurveIdentical && ...
    validation.missionFuelBiasCurveIndependent && ...
    validation.independentNoiseSeeds;
validation.details = sprintf( ...
    ['Validation domain inside training=%d; scalar persistent bias shared=%d; ' ...
    'persistent Wf curve shared=%d; mission Wf curves independent=%d; ' ...
    'noise seeds independent=%d.'], ...
    validation.validationWithinCalibrationDomain, ...
    validation.persistentBiasIdentical, ...
    validation.persistentFuelBiasCurveIdentical, ...
    validation.missionFuelBiasCurveIndependent, ...
    validation.independentNoiseSeeds);
if ~complete
    % 短测只验证数值和传感器隔离，不以截短任务判断完整训练包线。
    validation.validationWithinCalibrationDomain=NaN;
    validation.passed=validation.persistentBiasIdentical && ...
        validation.persistentFuelBiasCurveIdentical && validation.missionFuelBiasCurveIndependent && ...
        validation.independentNoiseSeeds;
    validation.details='Short diagnostic only: full mission coverage NOT EVALUATED; independent sensor seeds checked.';
end
end

function output = local_write_outputs(thisDir,runs,truthContract, ...
        healthProfile,healthProfileFile,visserAsset,visserAssetFile, ...
        options,baseCfg,crossMission)
testDir=options.dataRoot;middleDir=options.outputRoot;reportDir=options.reportRoot;
% 六部件旧入口的正式消费者仍按原位置读取，不随三部件隔离目录迁移。
if options.modelMode==1,middleDir=fullfile(thisDir,'MiddleData');end
if ~exist(testDir,'dir'), mkdir(testDir); end
if ~exist(middleDir,'dir'), mkdir(middleDir); end
if ~exist(reportDir,'dir'), mkdir(reportDir); end

dllFile = fullfile(baseCfg.engine.interface.controlDir, ...
    [baseCfg.engine.interface.libraryName,'.dll']);
headerFile = fullfile(baseCfg.engine.interface.controlDir, ...
    [baseCfg.engine.interface.libraryName,'.h']);
metadata = struct();
metadata.schemaVersion = 'F31_INTERNAL_GENERATION_V4';
metadata.externalExcelContractVersion = 'F31_FLIGHT_EXCEL_V3';
metadata.generatedAt = datestr(now,31);
metadata.generator = mfilename;
metadata.modelMode = options.modelMode;
metadata.thermalModelMode = 3;
metadata.stateCount = size(runs(1).simulation.log.xEngine,2);
metadata.healthLength = 159;
metadata.sampleTime_s = baseCfg.Tsim;
metadata.sampleRate_Hz = 1/baseCfg.Tsim;
metadata.recordSampleTime_s=baseCfg.Tsim;
if options.modelMode==0,metadata.recordSampleTime_s=.1;end
metadata.recordSampleRate_Hz=1/metadata.recordSampleTime_s;
metadata.runTag=options.runTag;
metadata.isCompleteMission=all(arrayfun(@(r)r.mission.duration_s==r.mission.nodeTime_s(end),runs));
metadata.formalColumns=runs(1).measurementTable.Properties.VariableNames;
metadata.MkgMeasured=options.modelMode~=0;
metadata.sensorDynamicDiscretization = 'exact_FOH';
metadata.pureDelay_s = 0;
metadata.downstreamInverseDynamicCompensation = false;
metadata.installedEffects = struct( ...
    'scale',options.installedEffectScale, ...
    'independentExhaustBackPressure',true, ...
    'fixedSortieDistortion',true, ...
    'sixComponentReynoldsCorrection',true, ...
    'mainTailRotorSplit',true, ...
    'humidity',false,'antiIceBleed',false,'hotGasReingestion',false);
if options.modelMode==0
    metadata.installedEffects=rmfield(metadata.installedEffects,'sixComponentReynoldsCorrection');
    metadata.installedEffects.threeComponentReynoldsCorrection=true;
    metadata.externalExcelContractVersion='F31_THREE_FLIGHT_EXCEL_R011';
end
metadata.healthScheduleVersion = healthProfile.schemaVersion;
metadata.visserAssetVersion = visserAsset.assetVersion;
metadata.inletBoundaryMode = 2;
metadata.inletBoundarySemantics = ...
    'external_Pamb_Tamb_Mach_with_C_reconstruction_and_pressure_recovery';
metadata.dllFile = dllFile;
metadata.dllSha256 = local_sha256(dllFile);
metadata.headerFile = headerFile;
metadata.headerSha256 = local_sha256(headerFile);
metadata.modelConfigurationFile = baseCfg.engine.modelConfiguration;
metadata.modelConfigurationSha256 = ...
    local_sha256(baseCfg.engine.modelConfiguration);
metadata.healthProfileFile = healthProfileFile;
metadata.healthProfileSha256 = local_sha256(healthProfileFile);
metadata.visserAssetFile = visserAssetFile;
metadata.visserAssetSha256 = local_sha256(visserAssetFile);
metadata.thermalVariant = options.thermalVariant;
metadata.transientVariant = options.transientVariant;
metadata.sameThermalEngineAcrossMissions = true;
metadata.measurementImplementation = 'F31_FOH_SCHEDULED_FUEL_BIAS_V3';

output = struct();
truthRuns = repmat(struct('missionId','','truthTable',table(), ...
    'truthLog',struct(),'sensorError',struct(),'measurementModel',struct(), ...
    'quality',struct(),'trim',struct(),'thermalEquilibrium',struct(), ...
    'runtime_s',NaN,'finalState',struct()),numel(runs),1);
for i = 1:numel(runs)
    if isempty(options.missionDefinition)
        [excelName,fieldName] = local_excel_definition(runs(i).mission.missionId);
    else
        excelName=[runs(i).mission.missionId,'_measurements.xlsx'];
        fieldName='identificationExcelFile';
    end
    excelFile = fullfile(testDir,excelName);
    if options.saveOutputs && options.writeExcel
        verification = local_write_excel_atomic( ...
            excelFile,runs(i).measurementTable,metadata.recordSampleTime_s);
    else
        verification = struct('passed',false,'rowCount',0, ...
            'columnCount',0,'sha256','NOT_WRITTEN');
    end
    output.(fieldName) = excelFile;
    output.([fieldName,'Verification']) = verification;
    truthRuns(i).missionId = runs(i).mission.missionId;
    truthRuns(i).truthTable = runs(i).truthTable;
    truthRuns(i).truthLog = runs(i).truthLog;
    truthRuns(i).sensorError = runs(i).sensorError;
    truthRuns(i).measurementModel = runs(i).measurementModel;
    truthRuns(i).quality = runs(i).quality;
    truthRuns(i).trim = runs(i).trim;
    truthRuns(i).thermalEquilibrium = runs(i).thermalEquilibrium;
    truthRuns(i).runtime_s = runs(i).runtime_s;
    truthRuns(i).finalState = runs(i).simulation.finalState;
end

validationData = struct('schemaVersion','F31_VALIDATION_TRUTH_V4', ...
    'generatedAt',datestr(now,31),'truthHealth',truthContract.truthHealth, ...
    'truthContract',truthContract,'truthHealthScheduleProfile',healthProfile, ...
    'visserTruthMapping',visserAsset.truthHealthMapping,'runs',truthRuns, ...
    'crossMissionValidation',crossMission,'metadata',metadata);
validationData.thermalTruthAsset=visserAsset;
truthFile = fullfile(middleDir,'flight_data_3p1_validation_truth.mat');
manifestFile = fullfile(middleDir,'flight_data_3p1_generation_latest.mat');
manifest = struct('metadata',metadata,'output',output, ...
    'quality',{[runs.quality]},'crossMissionValidation',crossMission);
if options.saveOutputs
    save(truthFile,'validationData','-v7.3');
    save(manifestFile,'manifest','-v7.3');
end
output.validationTruthFile = truthFile;
output.manifestFile = manifestFile;

qualityCsv = fullfile(reportDir,'F31_data_generation_quality.csv');
assumptionCsv = fullfile(reportDir,'F31_measurement_error_assumptions.csv');
summaryFile = fullfile(reportDir,'F31_data_generation_summary.md');
overviewFigure = fullfile(reportDir,'F31_mission_engine_overview.png');
if options.saveOutputs
    writetable(local_quality_table(runs),qualityCsv);
    writetable(runs(1).publicMeasurementAssumptions,assumptionCsv);
    if options.plotEnabled
        local_plot_overview(runs,overviewFigure,options.showFigures);
        for i = 1:numel(runs)
            figureFile = fullfile(reportDir,sprintf( ...
                '%s_measurement_truth_comparison.png',runs(i).mission.missionId));
            local_plot_measurement_comparison( ...
                runs(i),figureFile,options.showFigures);
            output.(['measurementFigure',num2str(i)]) = figureFile;
        end
    end
    local_write_summary(summaryFile,runs,crossMission,output, ...
        qualityCsv,assumptionCsv,overviewFigure);
end
output.summaryFile = summaryFile;
output.qualityCsv = qualityCsv;
output.measurementAssumptionCsv = assumptionCsv;
output.overviewFigure = overviewFigure;
end

function verification = local_write_excel_atomic( ...
        excelFile,measurementTable,sampleTime_s)
if isfile(excelFile)
    % 同一身份续算不重写Excel容器；有数值差异时校验报错，不覆盖旧文件。
    verification=local_validate_excel(excelFile,measurementTable,sampleTime_s);
    return;
end
% 先写入全新临时工作簿并复读，避免旧版17列工作簿在尾部残留历史列。
[targetDir,~,~] = fileparts(excelFile);
temporaryFile = [tempname(targetDir),'.xlsx'];
cleanup = onCleanup(@()local_delete_if_exists(temporaryFile)); %#ok<NASGU>
writetable(measurementTable,temporaryFile,'Sheet','Data');
verification = local_validate_excel( ...
    temporaryFile,measurementTable,sampleTime_s);
[moved,message] = movefile(temporaryFile,excelFile,'f');
if ~moved
    error('SHT:F31DataGen:ExcelReplace', ...
        '无法以已验收的临时工作簿替换%s：%s',excelFile,message);
end
verification.sha256 = local_sha256(excelFile);
end

function [fileName,fieldName] = local_excel_definition(missionId)
switch upper(missionId)
    case 'F31-CAL-01'
        fileName = 'flight_data_3p1_identification_history.xlsx';
        fieldName = 'identificationExcelFile';
    case 'F31-VA-01'
        fileName = 'flight_data_3p1_independent_validation_history.xlsx';
        fieldName = 'independentValidationExcelFile';
    otherwise
        error('SHT:F31DataGen:MissionId', '不支持任务%s。',missionId);
end
end

function local_delete_if_exists(filePath)
if exist(filePath,'file')==2
    delete(filePath);
end
end

function verification = local_validate_excel(filePath,referenceTable,sampleTime_s)
expected = {'sample_id','time_s','Ps0','Tt1','Pt3_eq','Ng','Np', ...
    'Mkp','Mkg','Wf','Tt45','Altitude','Mach','Ts_amb'};
if ~ismember('Mkg',referenceTable.Properties.VariableNames),expected(strcmp(expected,'Mkg'))=[];end
loaded = readtable(filePath,'Sheet','Data');
if ~isequal(loaded.Properties.VariableNames,expected)
    error('SHT:F31DataGen:ExcelSchema', 'Excel字段不符合F31_FLIGHT_EXCEL_V3。');
end
if height(loaded)~=height(referenceTable) || ...
        any(loaded.sample_id(:)~=(1:height(loaded)).') || ...
        any(~isfinite(table2array(loaded)),'all')
    error('SHT:F31DataGen:ExcelContent', 'Excel行数、编号或有限性检查失败。');
end
dt = diff(loaded.time_s(:));
if isempty(dt) || max(abs(dt-sampleTime_s))>1e-9
    error('SHT:F31DataGen:ExcelTime', 'Excel时间轴与指定记录周期不一致。');
end
delta=abs(table2array(loaded)-table2array(referenceTable));
tolerance=1e-10*max(1,abs(table2array(referenceTable)));
assert(all(delta(:)<=tolerance(:)), ...
    'Excel测量数值复读不一致。');
verification = struct('passed',true,'rowCount',height(loaded), ...
    'columnCount',width(loaded),'sha256',local_sha256(filePath));
end

function tableValue = local_quality_table(runs)
n = numel(runs);
mission_id=cell(n,1); duration_s=zeros(n,1); sample_count=zeros(n,1);
record_count=zeros(n,1);
runtime_s=zeros(n,1); max_residual=zeros(n,1); max_energy_residual=zeros(n,1);
max_np_error_pct=zeros(n,1); rms_np_error_pct=zeros(n,1);
thermal_tail_excursion_K=zeros(n,1); altitude_min_m=zeros(n,1);
altitude_max_m=zeros(n,1); mach_min=zeros(n,1); mach_max=zeros(n,1);
theta_min_deg=zeros(n,1); theta_max_deg=zeros(n,1); passed=false(n,1);
for i = 1:n
    q=runs(i).quality; mission_id{i}=runs(i).mission.missionId;
    duration_s(i)=runs(i).mission.duration_s; sample_count(i)=q.sampleCount;
    record_count(i)=height(runs(i).measurementTable);
    runtime_s(i)=runs(i).runtime_s; max_residual(i)=q.maximumCommonWorkResidual;
    max_energy_residual(i)=q.maximumNormalizedEnergyResidual;
    max_np_error_pct(i)=q.maximumNpRegulationErrorPct;
    rms_np_error_pct(i)=q.rmsNpRegulationErrorPct;
    thermal_tail_excursion_K(i)=q.initialHoldTailMaximumThermalExcursion_K;
    altitude_min_m(i)=q.actualAltitudeRange_m(1); altitude_max_m(i)=q.actualAltitudeRange_m(2);
    mach_min(i)=q.actualMachRange(1); mach_max(i)=q.actualMachRange(2);
    theta_min_deg(i)=q.actualThetaRange_deg(1); theta_max_deg(i)=q.actualThetaRange_deg(2);
    passed(i)=q.passed;
end
tableValue = table(mission_id,duration_s,sample_count,record_count,runtime_s,max_residual, ...
    max_energy_residual,max_np_error_pct,rms_np_error_pct, ...
    thermal_tail_excursion_K,altitude_min_m,altitude_max_m,mach_min,mach_max, ...
    theta_min_deg,theta_max_deg,passed);
end

function local_plot_overview(runs,filePath,showFigures)
visibility='off'; if showFigures, visibility='on'; end
fig=figure('Name','3.1典型飞行任务与发动机响应','Color','w', ...
    'Visible',visibility,'Position',[50 40 1600 900]);
for i=1:numel(runs)
    t=runs(i).mission.time_s; m=runs(i).mission; log=runs(i).truthLog;
    base=4*(i-1);
    subplot(numel(runs),4,base+1);
    yyaxis left; plot(t,m.altitude_m,'b-','LineWidth',1.1); ylabel('h / m');
    yyaxis right; plot(t,m.mach,'r-','LineWidth',1.1); ylabel('Mach');
    grid on; title([m.missionId,' environment'],'Interpreter','none');
    subplot(numel(runs),4,base+2);
    yyaxis left; plot(t,m.theta_cmd_deg,'k-','LineWidth',1.1); ylabel('theta / deg');
    yyaxis right; plot(t,log.Pload/1e6,'m-','LineWidth',1.1); ylabel('Pload / MW');
    grid on; title('load command and actual load');
    subplot(numel(runs),4,base+3);
    plot(t,log.Np/runs(i).cfg.controller.DPpara.Np0,'b-',t,log.Ng/38000,'r-','LineWidth',1.0);
    grid on; ylabel('normalized speed'); legend('Np','Ng','Location','best');
    title('rotor speed response');
    subplot(numel(runs),4,base+4);
    yyaxis left; plot(t,log.Wf,'k-','LineWidth',1.0); ylabel('Wf / kg/s');
    yyaxis right; plot(t,log.Tt45,'r-','LineWidth',1.0); ylabel('Tt45 / K');
    grid on; title('fuel and gas temperature');
end
for i=1:4*numel(runs), subplot(numel(runs),4,i); xlabel('time / s'); end
saveas(fig,filePath);
if ~showFigures, close(fig); end
end

function local_plot_measurement_comparison(run,filePath,showFigures)
visibility='off'; if showFigures, visibility='on'; end
fig=figure('Name',[run.mission.missionId,'测量真值对比'],'Color','w', ...
    'Visible',visibility,'Position',[40 20 1600 1000]);
names={'Ps0','Tt1','Pt3_eq','Ng','Np','Mkp','Mkg', ...
    'Wf','Tt45','Altitude','Mach','Ts_amb'};
units={'Pa','K','Pa','rpm','rpm','N*m','N*m', ...
    'kg/s','K','m','-','K'};
if run.cfg.engine.modelMode==0
    keep=~strcmp(names,'Mkg');names=names(keep);units=units(keep);
end
t=run.mission.time_s;
for i=1:numel(names)
    subplot(4,3,i);
    plot(t,run.truthLog.(names{i}),'k-','LineWidth',0.9); hold on;
    plot(t,run.measuredLog.(names{i}),'r-','LineWidth',0.55); hold off;
    grid on; title(names{i},'Interpreter','none'); ylabel(units{i});
    if i>9, xlabel('time / s'); end
    if i==1, legend('truth','measured','Location','best'); end
end
saveas(fig,filePath);
if ~showFigures, close(fig); end
end

function local_write_summary(filePath,runs,crossMission,output, ...
        qualityCsv,assumptionCsv,overviewFigure)
fid=fopen(filePath,'w','n','UTF-8');
if fid<0, error('SHT:F31DataGen:Summary','无法写入%s。',filePath); end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'# 3.1第二轮典型飞行任务与飞参替代数据生成摘要\n\n');
fprintf(fid,'- 生成时间：`%s`。\n',datestr(now,31));
fprintf(fid,'- 模型：modelMode=%d，%d状态；积分/传感器0.025s，记录由当前合同指定。\n', ...
    runs(1).cfg.engine.modelMode,size(runs(1).simulation.log.xEngine,2));
fprintf(fid,'- 测量链：真值 -> FOH一阶动态 -> 偏置 -> 白噪声；纯延迟为0。\n');
fprintf(fid,'- 后续处理约束：不执行传感器动态逆补偿，模型预测采用同口径正向测量算子。\n');
fprintf(fid,['- 装机因素：主/尾旋翼分载、每架次等效入口畸变、独立排气背压和' ...
    '当前构型雷诺数修正均已启用；湿度、防冰引气与热气再吸入暂不启用。\n']);
fprintf(fid,['- 数据隔离：Excel只含编号、时间和%d个正式可测通道；' ...
    '不构造Ps3，Pt3_eq直接由Pt3真值叠加等效换算测量误差。' ...
    '完整真值与误差实现仅保存在MiddleData。三部件不交付Mkg测量列。\n\n'], ...
    width(runs(1).measurementTable)-2);
fprintf(fid,'| 任务 | 角色 | 时长/s | 积分样本 | Excel记录 | 运行/s | maxErr | 能量残差 | Np最大偏差/%% | 验收 |\n');
fprintf(fid,'|---|---|---:|---:|---:|---:|---:|---:|---:|---|\n');
for i=1:numel(runs)
    q=runs(i).quality;
    fprintf(fid,'| %s | %s | %.0f | %d | %d | %.1f | %.3e | %.3e | %.3f | %s |\n', ...
        runs(i).mission.missionId,runs(i).mission.datasetRole, ...
        runs(i).mission.duration_s,q.sampleCount,height(runs(i).measurementTable),runs(i).runtime_s, ...
        q.maximumCommonWorkResidual,q.maximumNormalizedEnergyResidual, ...
        q.maximumNpRegulationErrorPct,local_pass_text(q.passed));
end
fprintf(fid,'\n- 训练/测试覆盖与隔离：**%s**。%s\n', ...
    local_pass_text(crossMission.passed),crossMission.details);
fprintf(fid,'\n## 输出文件\n\n');
if isfield(output,'identificationExcelFile')
    fprintf(fid,'- 训练飞参：`%s`\n',output.identificationExcelFile);
end
if isfield(output,'independentValidationExcelFile')
    fprintf(fid,'- 独立测试飞参：`%s`\n',output.independentValidationExcelFile);
end
fprintf(fid,'- 隐藏真值：`%s`\n',output.validationTruthFile);
fprintf(fid,'- 质量指标：`%s`\n',qualityCsv);
fprintf(fid,'- 测量误差公开先验：`%s`\n',assumptionCsv);
fprintf(fid,'- 任务总览图：`%s`\n',overviewFigure);
end

function hash = local_sha256(filePath)
if exist(filePath,'file')~=2, hash='FILE_NOT_FOUND'; return; end
fid=fopen(filePath,'rb');
if fid<0, hash='READ_FAILED'; return; end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
bytes=fread(fid,inf,'*uint8');
digest=java.security.MessageDigest.getInstance('SHA-256');
digest.update(typecast(bytes,'int8'));
hashBytes=typecast(digest.digest(),'uint8');
hash=lower(reshape(dec2hex(hashBytes,2).',1,[]));
end

function textValue = local_pass_text(pass)
if pass, textValue='PASS'; else, textValue='FAIL'; end
end

function m=local_limit_mission(m,duration)
if isinf(duration)||duration>=m.duration_s,return;end
n=m.sampleCount;mask=m.time_s<=duration+1e-10;names=fieldnames(m);
for k=1:numel(names)
    v=m.(names{k});
    if (isnumeric(v)||islogical(v)||iscell(v)||isstring(v))&&isvector(v)&&numel(v)==n
        m.(names{k})=v(mask);
    end
end
m.sampleCount=nnz(mask);m.duration_s=m.time_s(end);
% 边界插值保留原任务所有节点；短测只缩短积分终点，不改变任务形状。
end

function identity=local_generation_identity(root,cfg,options,profileFile,thermalFile)
% 检查点绑定真实调用闭包源码、模型/地图、热参数、真值表和随机配置。
% 生成时间不参与身份；改变算法或输入后不能给旧检查点重新签名。
[dependencies,~]=matlab.codetools.requiredFilesAndProducts(fullfile(root,[mfilename,'.m']));
dependencies=dependencies(startsWith(dependencies,[root,filesep]));
runtime=cfg.engine.interface.controlDir;
files=[dependencies(:);{profileFile;thermalFile;cfg.engine.modelConfiguration}];
for name={'GTESS.dll','GTESS.h','blockAndFunctions.h','types_TMATS.H','HPC02.MAP','HPT02.MAP','LPT02.MAP'}
    files{end+1,1}=fullfile(runtime,name{1}); %#ok<AGROW>
end
files=unique(files);hashes=cellfun(@local_sha256,files,'UniformOutput',false);
semanticOptions=rmfield(options,{'plotEnabled','showFigures'});
identity=struct('schema','F31_GENERATION_IDENTITY_R011','files',{files},'hashes',{hashes}, ...
    'options',semanticOptions,'modelMode',cfg.engine.modelMode,'MATLAB',version('-release'));
end

function local_print_summary(result)
fprintf('\n3.1第二轮飞参数据生成：%s\n',local_pass_text(result.passed));
for i=1:numel(result.runs)
    r=result.runs(i); q=r.quality;
    fprintf(['  %s: %.0f s, %d samples, runtime %.1f s, ' ...
        'h %.1f~%.1f m, M %.4f~%.4f, theta %.2f~%.2f deg, %s\n'], ...
        r.mission.missionId,r.mission.duration_s,q.sampleCount,r.runtime_s, ...
        q.actualAltitudeRange_m,q.actualMachRange,q.actualThetaRange_deg, ...
        local_pass_text(q.passed));
    if ~q.passed
        fprintf('    failed checks: %s\n',strjoin(q.failedChecks,', '));
    end
end
fprintf('  Summary: %s\n',result.output.summaryFile);
fprintf('  Truth isolation: %s\n',result.output.validationTruthFile);
end
