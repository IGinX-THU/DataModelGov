function varargout = sht_f33_model_adapt_v2(action, varargin)
%SHT_F33_MODEL_ADAPT_V2 第二轮3.3飞参稳态修正系数辨识核心。
%
% 本程序把两个容易混淆的选择显式拆开：
%   1) modelRoute：steady 或 transient_instant；
%   2) dataMethod：steady_only 或 steady_plus_small_history。
% 四种组合相互独立，均从同一显式先验开始，任何一条路线都不会读取
% 另一条3.3路线的估计结果作为初值或先验。
%
% 公开动作：
%   result   = sht_f33_model_adapt_v2('runRoute', options)
%   manifest = sht_f33_model_adapt_v2('runMatrix', options)
%   prior    = sht_f33_model_adapt_v2('loadPrior', options)
%   profile  = sht_f33_model_adapt_v2('buildProfile', schedule)
%   evidence = sht_f33_model_adapt_v2('prepareEvidence',history,segments,options)
%   evalSet  = sht_f33_model_adapt_v2('evaluateCandidates',context,thetaMatrix)
%   modelSet = sht_f33_model_adapt_v2('thetaToModels',context,thetaMatrix)
%   [context,metadata] = sht_f33_model_adapt_v2( ...
%       'prepareUqContext',resultFile,userOptions)
%   sht_f33_model_adapt_v2('closeUqContext',context)
%   hash     = sht_f33_model_adapt_v2('fileHash', fileName)
%   hash     = sht_f33_model_adapt_v2('structHash', value)

if nargin < 1
    error('SHT:F33V2:MissingAction', '必须给出公开动作。');
end
switch lower(char(string(action)))
    case 'options'
        % 配置检查不启动辨识，供入口预检与回归使用。
        varargout{1}=local_options(local_first_option(varargin));
    case 'outputpaths'
        % 纯路径规划，不建立目录、不加载输入或DLL，供计算前预检。
        o=local_options(local_first_option(varargin));
        assert(~isempty(o.outputRoot)&&~isempty(o.reportRoot),'SHT:F33V2:OutputRoots', ...
            '路径规划需要显式outputRoot和reportRoot。');
        p=struct('middleDir',o.outputRoot,'deliveryDir',fullfile(o.outputRoot,'delivery'), ...
            'reportDir',o.reportRoot);
        varargout{1}=local_output_paths(p,o);
    case 'runroute'
        varargout{1} = local_run_route(local_first_option(varargin));
    case 'checkpointcache'
        % 仅供运行控制保存/恢复纯数值缓存；不会求值发动机。
        varargout{1}=local_checkpoint_cache(varargin{:});
    case 'checkpointpure'
        local_assert_checkpoint_pure(varargin{1});varargout{1}=true;
    case 'frozenevidence'
        % 参数已冻结后的独立平均点验证，不重新确定节点释放或拟合参数。
        r=varargin{1};o=r.options;o.trainingWorkbook=varargin{2};
        o.saveEnabled=false;o.plotEnabled=false;o.progressFile='';o.runControl=[];
        o.comparisonCacheDirectory=fullfile(o.outputRoot,'independent_validation_cache');
        assert(o.modelMode==0&&ismember(o.modelRoute,{'steady','transient_instant'})&& ...
            ismember(o.dataMethod,{'steady_only','steady_plus_small_history'}), ...
            'SHT:F33V2:FrozenEvidenceRoute','仅支持三部件已冻结四路线。');
        varargout{1}=local_run_route(o,false,r);
    case 'preparecomparison'
        varargout{1}=local_run_route(local_first_option(varargin),true);
    case 'linearizecomparison'
        [varargout{1:nargout}]=local_linearize(varargin{:});
    case 'runmatrix'
        varargout{1} = local_run_matrix(local_first_option(varargin));
    case 'loadprior'
        options = local_options(local_first_option(varargin));
        varargout{1} = local_load_prior( ...
            fileparts(mfilename('fullpath')), options);
    case 'buildprofile'
        varargout{1} = local_build_schedule_profile(varargin{1});
    case 'prepareevidence'
        varargout{1} = local_prepare_evidence( ...
            varargin{1},varargin{2},local_options(varargin{3}));
    case 'evaluatecandidates'
        varargout{1} = local_evaluate_theta_set(varargin{:});
    case 'thetatomodels'
        varargout{1} = local_theta_to_models(varargin{:});
    case 'prepareuqcontext'
        [varargout{1:nargout}] = local_prepare_uq_context(varargin{:});
    case 'preparemodeluqcontext'
        [varargout{1:nargout}]=local_prepare_model_uq_context(varargin{1});
    case 'closeuqcontext'
        local_close_uq_context(varargin{1});
    case 'exportresult'
        % 只刷新已冻结结果的交付和摘要，不重新估计、不改变参数。
        r=varargin{1};
        if isfield(r,'exportProvenance')
            p=r.exportProvenance;
            assert(isstruct(p)&&isscalar(p)&&all(isfield(p, ...
                {'sourceResultSHA256','definitionBasis','numericalValuesUnchanged','solverRepeated'}))&& ...
                ischar(p.sourceResultSHA256)&&~isempty(regexp(p.sourceResultSHA256,'^[0-9A-Fa-f]{64}$','once'))&& ...
                ischar(p.definitionBasis)&&~isempty(strtrim(p.definitionBasis))&& ...
                isequal(p.numericalValuesUnchanged,true)&&isequal(p.solverRepeated,false), ...
                'SHT:F33V2:ExportProvenance','补导出必须说明原数值来源和仅修改交付定义的边界。');
        end
        r.visserCorrectionCoefficientsZero=local_transient_coefficients_zero(r.finalSchedule,r.options.modelMode);
        local_write_workbook(r);
        local_write_summary(r);
        if r.options.plotEnabled
            local_plot_result(r,local_paths(fileparts(mfilename('fullpath')),r.options));
        end
    case 'transientcoefficientszero'
        varargout{1}=local_transient_coefficients_zero(varargin{:});
    case 'filehash'
        varargout{1} = local_file_hash(varargin{1});
    case 'structhash'
        varargout{1} = local_struct_hash(varargin{1});
    otherwise
        error('SHT:F33V2:UnknownAction', '未知动作：%s。', char(string(action)));
end
end

function modelSet=local_theta_to_models(context,thetaMatrix)
% 只执行当前路线参数到完整调度曲线的确定性映射，不调用DLL。该接口供3.4
% 独立任务预测复用，避免复制3.3的参数符号、节点基函数和燃油定义。
if isvector(thetaMatrix),thetaMatrix=thetaMatrix(:);end
if size(thetaMatrix,1)~=height(context.parameterContract)
    error('SHT:F33V2:ThetaSize','候选参数维数不符合当前冻结合同。');
end
n=size(thetaMatrix,2);schedules=cell(n,1);recoveries=zeros(n,1);
kdist=zeros(n,1);wfBiasAtDesign=zeros(n,1);
for i=1:n
    [schedules{i},kdist(i),wfBiasAtDesign(i)]= ...
        local_theta_to_model(thetaMatrix(:,i),context);
    recoveries(i)=0.995-kdist(i);
end
modelSet=struct('schedules',{schedules},'recoveries',recoveries, ...
    'KdistEq',kdist,'WfBiasAtDesign_kgps',wfBiasAtDesign, ...
    'testDataUsed',false,'truthDataUsed',false);
end

function [context, metadata] = local_prepare_uq_context(resultFile,userOptions)
%LOCAL_PREPARE_UQ_CONTEXT 按已冻结3.3结果重建完全相同的物理求值上下文。
%
% 该接口只向3.4暴露3.3已经使用的前向模型，不执行参数辨识，也不读取
% 测试集或隐藏真值。resultFile中的训练Excel、2.4确定性参考和参数合同
% 被视为冻结身份；若当前文件与冻结哈希不一致，立即停止，避免3.4在
% 不知情的情况下混用另一版上游结果。
if nargin<1 || isempty(resultFile)
    thisDir=fileparts(mfilename('fullpath'));
    resultFile=fullfile(thisDir,'MiddleData','flight_model_adapt_3p3_v2', ...
        ['flight_model_adapt_3p3_steady_steady_only_set1_' ...
         'four_routes_20260906_latest.mat']);
end
if nargin<2 || isempty(userOptions),userOptions=struct();end
if ~isfile(resultFile)
    error('SHT:F33V2:MissingUqReference','缺少3.4引用的3.3结果：%s。',resultFile);
end
loaded=load(resultFile,'result');
if ~isfield(loaded,'result') || ~isstruct(loaded.result)
    error('SHT:F33V2:BadUqReference','3.3结果文件缺少result结构体。');
end
reference=loaded.result;
required={'options','training','priorSchedule','parameterContract', ...
    'parameterSet','modelRoute','dataMethod','scheduleParameterization'};
if ~all(isfield(reference,required))
    error('SHT:F33V2:BadUqReference','3.3结果缺少重建UQ上下文所需字段。');
end
if ~ismember(reference.modelRoute,{'steady','transient_instant'}) || ...
        ~strcmp(reference.dataMethod,'steady_only') || ...
        ~strcmp(reference.parameterSet,'set1') || ...
        ~ismember(reference.scheduleParameterization,{'family_amplitude','independent_nodes'})
    error('SHT:F33V2:UnsupportedUqReference', ...
        '当前3.4只接受纯稳态数据、set1及已实现的幅值或独立节点冻结结果。');
end
if ~isstruct(userOptions) || ~isscalar(userOptions)
    error('SHT:F33V2:BadUqOptions','UQ上下文覆盖项必须为标量结构体。');
end

% 冻结来源优先于latest指针。这里只允许覆盖纯数值求解容差等已有选项，
% 不允许通过UQ入口静默更换模型路线、数据方法或参数组合。
baseOptions=reference.options;
baseOptions.trainingWorkbook=reference.training.workbook;
if isfield(reference,'prior') && isfield(reference.prior,'sourceFile') && ...
        isfile(reference.prior.sourceFile)
    baseOptions.priorWorkbook=reference.prior.sourceFile;
end
options=local_options(local_merge_struct(baseOptions,userOptions));
if ~strcmp(options.modelRoute,reference.modelRoute) || ...
        ~strcmp(options.dataMethod,'steady_only') || ...
        ~strcmp(options.parameterSet,'set1') || ...
        ~strcmp(options.scheduleParameterization,reference.scheduleParameterization)
    error('SHT:F33V2:UqContractOverride','UQ入口不得改变冻结的模型与数据路线。');
end

thisDir=fileparts(mfilename('fullpath'));
paths=local_paths(thisDir,options);
sourceHash=local_file_hash(paths.trainingWorkbook);
if isfield(reference.training,'sourceSha256') && ...
        ~strcmpi(sourceHash,reference.training.sourceSha256)
    error('SHT:F33V2:UqTrainingChanged', ...
        '3.3训练Excel已变化，必须先明确重跑3.3，不能直接续算3.4。');
end
prior=local_load_prior(thisDir,options);
% 使用3.3结果中冻结的绝对物理曲线，避免上游latest后来变化造成漂移。
prior.schedule=reference.priorSchedule;
prior.baseResult.finalSchedule=reference.priorSchedule;
[history,segments,readHash]=local_read_training(paths.trainingWorkbook);
if ~strcmpi(readHash,sourceHash)
    error('SHT:F33V2:UqTrainingRead','训练数据读取前后哈希不一致。');
end
evidence=local_prepare_evidence(history,segments,options);
steadyData=evidence.steadyData;
steadySource=evidence.steadySource;
weighting=local_weighting_contract(options,paths.stage32File);
parameter=local_parameter_definition(prior.baseResult,options.parameterSet);

baseContext=struct('options',options,'baseResult',prior.baseResult, ...
    'priorSchedule',prior.schedule,'parameter',parameter, ...
    'steadyData',steadyData,'historyData',evidence.historyData, ...
    'historyMeta',evidence.historyMeta,'weighting',weighting, ...
    'familyMap',[],'fuelMap',[]);
assetSource='2p4';if options.modelMode==0,assetSource=options.priorSource;end
if options.modelMode==0
assets=sht_f3_current_contract('assets',options);
else
assets=sht_f32_replay_history('loadAssets',thisDir,struct( ...
    'modelMode',options.modelMode, ...
    'priorSource',assetSource,'priorRoute',options.priorRoute, ...
    'priorWorkbook',options.priorWorkbook));
end
assets.personalized.health=prior.schedule.designHealth;
assets.personalized.profile=local_build_schedule_profile(prior.schedule);
assets.personalized.fuelBias=prior.schedule.fuelBias;
assets.steadySchedule=prior.schedule;
stage32=load(paths.stage32File,'flightModelAdaptData');
if ~isfield(stage32,'flightModelAdaptData') || ...
        ~isfield(stage32.flightModelAdaptData,'measurementObjectParameters')
    error('SHT:F33V2:UqStage32','3.2结果缺少测量对象先验。');
end
sensor=stage32.flightModelAdaptData.measurementObjectParameters.channelTable;
if strcmp(options.modelRoute,'steady')
    branchOptions=struct('integrationStep_s',options.historyIntegrationStep_s);
    if isfield(userOptions,'outputRoot')&&~isempty(userOptions.outputRoot)
        branchOptions.cacheDirectory=fullfile(userOptions.outputRoot,'thermal_branch_replay_cache');
    end
    branch=sht_f33_thermal_equilibrium('prepare',history,segments,steadyData, ...
        assets,sensor,prior.baseResult.options.steadyNpTrainingBranchRelativeHalfWidth,sourceHash, ...
        branchOptions);
else
    branch=struct('pointIds',steadyData.point_id, ...
        'speedSeed',[steadyData.Np_mean,steadyData.Ng_mean], ...
        'lowerNp',zeros(height(steadyData),1),'upperNp',inf(height(steadyData),1), ...
        'source','measured_window_mean_speed','pointMeasuredSpeedUsed',true, ...
        'thermalHistoryUsed',false,'sourceHash',sourceHash);
end
baseContext.thermalSession=sht_f33_thermal_equilibrium( ...
    'open',assets,branch,steadyData,options.modelRoute);
baseContext.replayAssets=assets;
baseContext.sensorAssumptions=sensor;

coverageTheta=zeros(height(parameter)+2,1);
coverageEvaluation=local_evaluate_theta_set(baseContext,coverageTheta);
local_require_valid_evaluation(coverageEvaluation,'3.4上下文覆盖重建');
[familyMap,coverageTable]=local_build_family_map(prior.schedule,parameter, ...
    coverageEvaluation,steadyData,evidence.historyData,evidence.historyMeta,options);
[fuelMap,fuelCoverageTable]=local_build_fuel_map( ...
    prior.schedule,steadyData,evidence.historyData,options);
parameterContract=local_complete_parameter_contract( ...
    prior.schedule,parameter,familyMap,fuelMap,options);

frozen=reference.parameterContract;
sameId=height(frozen)==height(parameterContract) && ...
    isequal(string(frozen.parameter_id),string(parameterContract.parameter_id));
if ~sameId
    error('SHT:F33V2:UqParameterContract', ...
        '重建的参数ID与冻结3.3结果不一致。');
end
numericNames={'c_index','prior_center','prior_sigma','lower_bound', ...
    'upper_bound','difference_step'};
for i=1:numel(numericNames)
    name=numericNames{i};
    a=frozen.(name);b=parameterContract.(name);
    finite=isfinite(a)&isfinite(b);
    if any(xor(isfinite(a),isfinite(b))) || ...
            any(abs(a(finite)-b(finite))>1e-12*max(1,max(abs(a(finite)))))
        error('SHT:F33V2:UqParameterContract', ...
            '重建参数合同字段%s与冻结结果不一致。',name);
    end
end

context=baseContext;
context.familyMap=familyMap;
context.fuelMap=fuelMap;
context.parameterContract=parameterContract;
context.steadySource=steadySource;
context.uqReferenceResult=reference;
context.uqReferenceFile=resultFile;
context.uqReferenceFileSha256=local_file_hash(resultFile);
context.uqTrainingSourceSha256=sourceHash;
context.uqThermalBranch=branch;
context.uqStage32File=paths.stage32File;
context.uqStage32FileSha256=local_file_hash(paths.stage32File);

metadata=struct('schemaVersion','SHT_F33_UQ_CONTEXT_V1', ...
    'referenceFile',resultFile,'referenceFileSha256',context.uqReferenceFileSha256, ...
    'trainingWorkbook',paths.trainingWorkbook,'trainingSha256',sourceHash, ...
    'stage32File',paths.stage32File,'stage32Sha256',context.uqStage32FileSha256, ...
    'priorSourceFile',prior.sourceFile,'priorSourceSha256',prior.sourceSha256, ...
    'steadyWindowCount',height(steadyData),'parameterCount',height(parameterContract), ...
    'coverageTable',coverageTable,'fuelCoverageTable',fuelCoverageTable, ...
    'truthDataAccessed',false,'testDataAccessed',false);
end

function [context,metadata]=local_prepare_model_uq_context(user)
% 直接评估选定Excel模型及新观测，不伪造一次已完成的确定性辨识。
o=local_options(user);
assert(o.modelMode==0&&ismember(o.priorSource,{'flight','combined'})&& ...
    strcmp(o.dataMethod,'steady_only')&&strcmp(o.parameterSet,'set1')&& ...
    strcmp(o.scheduleParameterization,'independent_nodes'), ...
    'SHT:F33V2:ModelUqRoute','独立评估只支持显式flight/combined父、set1独立节点及平均点。');
o.assessmentModelReference=true;o.saveEnabled=false;o.plotEnabled=false;
o.runControl=[];o.progressFile='';
context=local_run_route(o,true);
p=context.comparisonSource;paths=p.paths;
models=local_theta_to_models(context,context.referenceTheta);
selected=sht_f3_current_contract('parent',o);
reference=struct('schema','F3_EXCEL_MODEL_UQ_REFERENCE_B23', ...
    'estimatedTheta',context.referenceTheta,'estimatedKdistEq',models.KdistEq, ...
    'finalSchedule',selected.schedule,'deterministicFitPerformed',false, ...
    'modelWorkbook',o.priorWorkbook,'parameterContract',context.parameterContract);
context.uqReferenceResult=reference;
context.uqReferenceFile=o.priorWorkbook;
context.uqReferenceFileSha256=local_file_hash(o.priorWorkbook);
context.uqTrainingSourceSha256=p.trainingHash;
context.uqThermalBranch=context.thermalSession.branch;
context.uqStage32File=paths.stage32File;
context.uqStage32FileSha256=local_file_hash(paths.stage32File);
metadata=struct('schemaVersion','F3_MODEL_OBSERVATION_UQ_CONTEXT_B23', ...
    'referenceKind','model_excel_and_observations','referenceFile',o.priorWorkbook, ...
    'referenceFileSha256',context.uqReferenceFileSha256, ...
    'trainingWorkbook',paths.trainingWorkbook,'trainingSha256',p.trainingHash, ...
    'stage32File',paths.stage32File,'stage32Sha256',context.uqStage32FileSha256, ...
    'priorSourceFile',o.priorWorkbook,'priorSourceSha256',context.uqReferenceFileSha256, ...
    'steadyWindowCount',height(context.steadyData),'parameterCount',height(context.parameterContract), ...
    'coverageTable',p.coverageTable,'fuelCoverageTable',p.fuelCoverageTable, ...
    'truthDataAccessed',false,'testDataAccessed',false,'deterministicFitPerformed',false);
end

function local_close_uq_context(context)
% 当前热平衡会话不长期持有DLL句柄，但仍统一提供关闭动作，便于后续实现
% 增加持久资源后保持调用方不变。
if isstruct(context) && isfield(context,'thermalSession') && ...
        ~isempty(context.thermalSession)
    sht_f33_thermal_equilibrium('close',context.thermalSession);
end
end

function value = local_first_option(args)
if isempty(args) || isempty(args{1})
    value = struct();
else
    value = args{1};
end
end

function manifest = local_run_matrix(userOptions)
% 按已确认顺序先执行两条纯稳态数据路线，再执行两条混合数据路线。
if ~isstruct(userOptions) || ~isscalar(userOptions)
    error('SHT:F33V2:BadMatrixOptions', 'userOptions必须为标量结构体。');
end
plan = {
    'steady',            'steady_only';
    'transient_instant', 'steady_only';
    'steady',            'steady_plus_small_history';
    'transient_instant', 'steady_plus_small_history'};
results = cell(size(plan, 1), 1);
for i = 1:size(plan, 1)
    one = userOptions;
    one.modelRoute = plan{i, 1};
    one.dataMethod = plan{i, 2};
    fprintf('\n3.3路线矩阵 %d/%d：%s / %s\n', ...
        i, size(plan, 1), one.modelRoute, one.dataMethod);
    results{i} = local_run_route(one);
end

thisDir = fileparts(mfilename('fullpath'));
options = local_options(local_merge_struct(userOptions, struct( ...
    'modelRoute', 'steady', 'dataMethod', 'steady_only')));
paths = local_paths(thisDir, options);
model_route = string(plan(:, 1));
data_method = string(plan(:, 2));
parameter_set = repmat(string(options.parameterSet), size(plan, 1), 1);
converged = cellfun(@(x)x.converged, results);
runtime_s = cellfun(@(x)x.runtime_s, results);
prior_objective = cellfun(@(x)x.priorObjective, results);
final_objective = cellfun(@(x)x.finalObjective, results);
result_file = string(cellfun(@(x)x.output.matFile, results, ...
    'UniformOutput', false));
routeTable = table(model_route, data_method, parameter_set, converged, ...
    runtime_s, prior_objective, final_objective, result_file);
manifest = struct('schemaVersion', 'SHT_F33_ROUTE_MATRIX_V3', ...
    'program', mfilename, 'createdAt', datestr(now, 31), ...
    'parameterSet', options.parameterSet, 'routeTable', routeTable, ...
    'results', {results});
matrixTag=options.parameterSet;
if ~isempty(options.resultTag),matrixTag=[matrixTag,'_',options.resultTag];end
manifestFile = fullfile(paths.middleDir, sprintf( ...
    'flight_model_adapt_3p3_route_matrix_%s_latest.mat',matrixTag));
manifest.output = struct('matFile', manifestFile);
save(manifestFile, 'manifest', '-v7.3');
writetable(routeTable, fullfile(paths.deliveryDir, sprintf( ...
    'flight_model_adapt_3p3_route_matrix_%s.xlsx',matrixTag)), 'Sheet', 'routes');
end

function result = local_run_route(userOptions,prepareOnly,frozen)
if nargin<2,prepareOnly=false;end
if nargin<3,frozen=[];end
coreClock=tic;
options = local_options(userOptions);
control=options.runControl;checkpoint=[];found=false;
if ~isempty(control)
    assert(~prepareOnly&&isempty(frozen),'SHT:F33:ControlScope','停续只用于正式求解。');
    [checkpoint,found]=sht_tc24_run_control('load',control,'f33_state');
    if found
        local_assert_checkpoint_pure(checkpoint);
        assert(strcmp(checkpoint.schemaVersion,'F33_SAFE_STATE_R042_B2'), ...
            'SHT:F33:CheckpointSchema','检查点不是本轮纯数值合同。');
        if strcmp(checkpoint.nextPhase,'publish')
            % 最终完整J已安全保存；恢复后不再重做更新或重复差分。
            result=local_publish_result(checkpoint.result,options);
            return;
        end
    end
end
local_progress(options,'preparing',0,NaN,'恢复已选父模型与完整确认窗口');
routeDefinition = sht_f33_route_definition( ...
    options.modelRoute, options.dataMethod);
thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir);
paths = local_paths(thisDir, options);
if options.modelMode==0&&options.saveEnabled
    output=local_output_paths(paths,options);
    assert(~isfile(output.matFile)&&~isfile(output.workbook)&&~isfile(output.formalWorkbook), ...
        'SHT:F33V2:ExistingBatch','结果标签已存在，请读取已完成结果或指定新的resultTag，禁止覆盖。');
end
prior = local_load_prior(thisDir, options);
if options.assessmentModelReference
    assert(prepareOnly,'SHT:F33V2:AssessmentOnly', ...
        '模型评估坐标不得用于更改现有确定性辨识的先验政策。');
    selected=sht_f3_current_contract('parent',options);
    prior.schedule=selected.schedule;prior.baseResult.finalSchedule=selected.schedule;
    % 选定模型提供数值锚点，不把本架次燃油估计值偷换成概率先验。
    % 现行C/D要求飞行燃油以零曲线为坐标原点；物理先验仍由prior模块建立。
    prior.schedule.fuelBias.biasNodes=zeros(size(selected.schedule.fuelBias.biasNodes));
    prior.referenceFuelBias=selected.schedule.fuelBias.biasNodes(:);
    prior.referenceKdistEq=selected.parentKdistEq;
end
[history, segments, sourceHash] = ...
    local_read_training(paths.trainingWorkbook);
evidence = local_prepare_evidence(history,segments,options);
steadyData = evidence.steadyData; steadySource = evidence.steadySource;
historyData = evidence.historyData; historyMeta = evidence.historyMeta;
weighting = local_weighting_contract(options, paths.stage32File);
parameter = local_parameter_definition(prior.baseResult, options.parameterSet);

fprintf('\n============================================================\n');
fprintf('3.3第二轮飞参稳态修正系数辨识\n');
fprintf('============================================================\n');
fprintf('辨识路线：%s；模型路径：%s；数据方法：%s；参数组合：%s。\n', ...
    routeDefinition.routeId, options.modelRoute, options.dataMethod, ...
    options.parameterSet);
fprintf('先验：%s/%s；进口回放：C端mode 5。\n', ...
    prior.source, prior.route);
fprintf('背压：当前模型状态计算；雷诺数：开启；稳态热处理：%s。\n',options.steadyThermalMode);
fprintf('证据：%d个稳态窗口', height(steadyData));
if strcmp(options.dataMethod, 'steady_plus_small_history')
    fprintf(' + %d段小幅变化历程（有效样本%d个）', ...
        historyMeta.segmentCount, historyMeta.fitSampleCount);
end
fprintf('。\n');

timerId = tic;
startDllCalls=local_profile_dll_count();
baseContext = struct('options', options, 'baseResult', prior.baseResult, ...
    'priorSchedule', prior.schedule, 'parameter', parameter, ...
    'steadyData', steadyData, 'steadySource', steadySource, 'historyData', historyData, ...
    'historyMeta', historyMeta, 'weighting', weighting, ...
    'familyMap', [], 'fuelMap', []);
if strcmp(options.steadyThermalMode,'equilibrium')
    % 热拓扑和标称热资产保持当前Visser。普通稳态父不继承其他任务的瞬态值；
    % 显式组合父固定传递其绑定的13项瞬态修正，但不参与本轮稳态估计。
    assetSource='2p4';if options.modelMode==0,assetSource=options.priorSource;end
    if options.modelMode==0
        assets=sht_f3_current_contract('assets',options);
    else
    assets=sht_f32_replay_history('loadAssets',thisDir, ...
        struct('modelMode',options.modelMode,'priorSource',assetSource,'priorRoute',options.priorRoute, ...
        'priorWorkbook',options.priorWorkbook));
    end
    % 显式覆盖模型，保证选根初猜与本次读取的先验完全一致。
    assets.personalized.health=prior.schedule.designHealth;
    assets.personalized.profile=local_build_schedule_profile(prior.schedule);
    assets.personalized.fuelBias=prior.schedule.fuelBias;
    assets.steadySchedule=prior.schedule;
    obj=load(paths.stage32File,'flightModelAdaptData');
    sensor=obj.flightModelAdaptData.measurementObjectParameters.channelTable;
    if strcmp(options.modelRoute,'steady')&&~isempty(frozen)
        % 独立点不得以测试转速选根；复用C2输入驱动求解及其完整热平衡结果。
        baseContext.frozenSteadyBatch=local_frozen_steady_batch(assets,steadyData,steadySource,frozen);
        branch=baseContext.frozenSteadyBatch.branch;
    elseif strcmp(options.modelRoute,'steady')
        cacheRoot=options.comparisonCacheDirectory;
        if isempty(cacheRoot),cacheRoot=fullfile(paths.middleDir,'history_cache');end
        branch=sht_f33_thermal_equilibrium('prepare',history,segments,steadyData, ...
            assets,sensor,prior.baseResult.options.steadyNpTrainingBranchRelativeHalfWidth,sourceHash, ...
            struct('integrationStep_s',options.historyIntegrationStep_s, ...
            'cacheDirectory',fullfile(cacheRoot,'training_root_replay')));
    else
        % 瞬态时刻路径直接使用可测转速，无需整段回放来选择稳态转速根。
        branch=struct('pointIds',steadyData.point_id, ...
            'speedSeed',[steadyData.Np_mean,steadyData.Ng_mean], ...
            'lowerNp',zeros(height(steadyData),1),'upperNp',inf(height(steadyData),1), ...
            'source','measured_window_mean_speed','pointMeasuredSpeedUsed',true, ...
            'thermalHistoryUsed',false,'sourceHash',sourceHash);
    end
    baseContext.thermalSession=sht_f33_thermal_equilibrium('open',assets,branch,steadyData,options.modelRoute);
    thermalCleanup=onCleanup(@()sht_f33_thermal_equilibrium('close',baseContext.thermalSession)); %#ok<NASGU>
    evidence.forwardPhysicsContract.enhancedTransientEffectsEnabled=true;
    evidence.forwardPhysicsContract.thermalStateTreatment='fully_equilibrated_nominal_visser';
    if options.modelMode==0
        evidence.forwardPhysicsContract.reynoldsCorrection=assets.configuration.engine.reynoldsCorrection;
        evidence.forwardPhysicsContract.modelMode=0;
        evidence.forwardPhysicsContract.stateCount=16;
        evidence.forwardPhysicsContract.fixedTransient=assets.contract.fixedTransient;
        evidence.forwardPhysicsContract.transientIndividualCorrectionSource='selected_parent_fixed_13';
    end
    evidence.forwardPhysicsContract.thermalHistoryUsed=false;
    evidence.forwardPhysicsContract.branch=branch;
    baseContext.replayAssets=assets;
    baseContext.sensorAssumptions=sensor;
end
evidence.forwardPhysicsContract.smallHistoryThermalMode=options.smallHistoryThermalMode;
if ~isempty(frozen)
    baseContext.parameterContract=frozen.parameterContract;
    models=struct('schedules',{{frozen.priorSchedule,frozen.finalSchedule}}, ...
        'recoveries',[.995,.995-frozen.estimatedKdistEq]);
    evaluated=local_evaluate_theta_set(baseContext,[frozen.priorTheta,frozen.estimatedTheta],models);
    result=struct('status','evaluated_frozen_parameters','sourceFile',paths.trainingWorkbook, ...
        'sourceSha256',sourceHash,'steadyData',steadyData,'steadySource',steadySource, ...
        'historyData',historyData,'historyMeta',historyMeta,'rootBranch',branch, ...
        'evaluation',evaluated,'runtime_s',toc(coreClock),'fitRepeated',false, ...
        'metricTable',local_metric_table(local_evaluation_subset(evaluated,1), ...
        local_evaluation_subset(evaluated,2),baseContext));
    return;
end
frame=struct('sourceHash',sourceHash,'priorSchedule',prior.schedule, ...
    'parameter',parameter,'steadyData',steadyData,'weighting',weighting, ...
    'route',options.modelRoute,'dataMethod',options.dataMethod);
frameHash=local_struct_hash(frame);
if found
    assert(strcmp(checkpoint.frameHash,frameHash),'SHT:F33:CheckpointFrame', ...
        '当前点集、先验或误差合同与安全检查点不一致。');
    familyMap=checkpoint.familyMap;fuelMap=checkpoint.fuelMap;
    parameterContract=checkpoint.parameterContract;
    coverageTable=checkpoint.coverageTable;fuelCoverageTable=checkpoint.fuelCoverageTable;
    if isfield(baseContext,'thermalSession')
        baseContext.thermalSession.cache=local_checkpoint_cache('restore',checkpoint.cache);
    end
else
coverageTheta = zeros(height(parameter) + 2, 1);
if options.assessmentModelReference,coverageTheta(end-1)=prior.referenceKdistEq;end
coverageEvaluation = local_evaluate_theta_set(baseContext, coverageTheta);
local_require_valid_evaluation(coverageEvaluation, '先验覆盖分析回放');
[familyMap, coverageTable] = local_build_family_map( ...
    prior.schedule, parameter, coverageEvaluation, steadyData, ...
    historyData, historyMeta, options);
[fuelMap, fuelCoverageTable] = local_build_fuel_map( ...
    prior.schedule,steadyData,historyData,options);
parameterContract = local_complete_parameter_contract( ...
    prior.schedule, parameter, familyMap, fuelMap, options);
end
fprintf('曲线释放：%s；总参数%d个（包括燃油偏置）。\n', ...
    options.scheduleParameterization,height(parameterContract));
if ~isempty(options.progressFile)
    actualEstimate=sht_f3_runtime_estimate(prior.schedule,evidence, ...
        options.maximumIterations,options.runtimeEstimateTestPoints,height(parameterContract),options);
    local_progress(options,'coverage_complete',0,NaN,'已按实际释放维数修订估时',actualEstimate);
end
context = baseContext;
context.familyMap = familyMap;
context.fuelMap = fuelMap;
context.parameterContract = parameterContract;
if options.assessmentModelReference
    context.referenceTheta=zeros(height(parameterContract),1);
    context.referenceTheta(parameterContract.kind=="sortie_nuisance")=prior.referenceKdistEq;
    rows=find(parameterContract.kind=="fuel_bias_node");
    context.referenceTheta(rows)=prior.referenceFuelBias(parameterContract.node_index(rows));
end

% 覆盖冻结后再建立统一参数合同，发动机和燃油使用同一释放方式。
zeroTheta = zeros(height(parameterContract),1);
if options.assessmentModelReference,zeroTheta=context.referenceTheta;end
if found
    priorEvaluation=checkpoint.priorEvaluation;
else
priorEvaluation = local_evaluate_theta_set(context,zeroTheta);
local_require_valid_evaluation(priorEvaluation, '正式零更新先验回放');
end
if prepareOnly
    result=context;result.comparisonSource=struct('prior',prior,'paths',paths, ...
        'trainingHash',sourceHash,'coverageTable',coverageTable,'fuelCoverageTable',fuelCoverageTable);
    return;
end

currentTheta = zeroTheta;
bestTheta = zeroTheta;
bestObjective = local_objective(priorEvaluation, zeroTheta, ...
    parameterContract, options.regularizationWeight);
priorObjective = bestObjective;
iteration = repmat(local_empty_iteration(), options.maximumIterations, 1);
converged = false;
stopReason = "maximum_iterations_reached";
work=struct('jacobian',{{}},'candidate',{{}}, ...
    'initialHistoryCacheFiles',{local_history_cache_files(priorEvaluation)});
completedIterations=0;terminationDecided=false;priorCoreSeconds=0;priorRuntimeSeconds=0;priorDllCalls=0;
if found
    currentTheta=checkpoint.currentTheta;bestTheta=checkpoint.bestTheta;
    bestObjective=checkpoint.bestObjective;priorObjective=checkpoint.priorObjective;
    iteration=checkpoint.iteration;converged=checkpoint.converged;
    stopReason=checkpoint.stopReason;work=checkpoint.work;
    completedIterations=checkpoint.completedIterations;
    terminationDecided=checkpoint.terminationDecided;
    priorCoreSeconds=checkpoint.coreSeconds;priorRuntimeSeconds=checkpoint.runtimeSeconds;
    priorDllCalls=checkpoint.dllCalls;
else
    saveSafeBoundary('iterate');
end

for k = (completedIterations+1):options.maximumIterations
    if terminationDecided,break;end
    local_progress(options,'linearizing',k,bestObjective,'按当前实际参数计算完整Jacobian');
    [residual,jacobian,sensitivityEvaluation,work.jacobian{k}]= ...
        local_linearize(context,currentTheta,options.historyJacobianMode);
    [proposalTheta, proposalLambda, gcvTable, gcvRecommended] = ...
        local_linearized_proposals(currentTheta, residual, jacobian, ...
        parameterContract, options);
    candidateTheta = [currentTheta, proposalTheta];
    candidateTimer=tic;
    candidateCount=local_profile_dll_count();
    candidateEvaluation = local_evaluate_theta_set(context, candidateTheta);
    work.candidate{k}=struct('wall_s',toc(candidateTimer), ...
        'dllCalls',local_profile_dll_count()-candidateCount, ...
        'historyCacheFiles',{local_history_cache_files(candidateEvaluation)});
    % 某个提议的物理解无效不能连带否定当前有效解；无效候选代价为Inf。
    local_require_valid_evaluation(local_evaluation_subset(candidateEvaluation,1), ...
        sprintf('第%d轮当前参数复核', k));
    [selectedIndex, objective, dataCost, priorCost] = ...
        local_select_candidate(candidateEvaluation, candidateTheta, ...
        parameterContract, options.regularizationWeight);
    selectedTheta = candidateTheta(:, selectedIndex);
    previousObjective = local_objective( ...
        local_evaluation_subset(candidateEvaluation, 1), currentTheta, ...
        parameterContract, options.regularizationWeight);
    selectedObjective = objective(selectedIndex);
    scaledStep = max(abs((selectedTheta - currentTheta) ./ ...
        parameterContract.prior_sigma));
    relativeImprovement = (previousObjective - selectedObjective) / ...
        max(previousObjective, eps);
    iteration(k) = struct('index', k, ...
        'previousObjective', previousObjective, ...
        'selectedObjective', selectedObjective, ...
        'selectedDataCost', dataCost(selectedIndex), ...
        'selectedPriorCost', priorCost(selectedIndex), ...
        'selectedProposalIndex', selectedIndex - 1, ...
        'selectedProposalLambda', local_selected_lambda( ...
        selectedIndex, proposalLambda), ...
        'gcvRecommendedLambda', gcvRecommended, ...
        'maximumScaledStep', scaledStep, ...
        'relativeImprovement', relativeImprovement, ...
        'jacobianCondition', local_condition_number(jacobian), ...
        'gcvTable', gcvTable);

    fprintf(['  迭代%d：目标 %.8g -> %.8g，数据代价 %.8g，' ...
        'GCV建议lambda=%.4g。\n'], k, previousObjective, ...
        selectedObjective, dataCost(selectedIndex), gcvRecommended);
    if selectedObjective < bestObjective
        bestObjective = selectedObjective;
        bestTheta = selectedTheta;
    end
    if selectedIndex == 1
        % 没有下降候选并不自动证明最优。最后一次在当前点重新线性化，
        % 另报投影梯度，区分驻点和局部求解停滞。
        gradient=(jacobian.'*residual).*parameterContract.prior_sigma+ ...
            options.regularizationWeight*currentTheta./parameterContract.prior_sigma;
        gradient(currentTheta<=parameterContract.lower_bound & gradient>0)=0;
        gradient(currentTheta>=parameterContract.upper_bound & gradient<0)=0;
        converged=max(abs(gradient))<=1e-4;
        stopReason = "no_improving_full_regularized_candidate";
        if converged,stopReason="projected_gradient_small";end
        terminationDecided=true;
    else
    currentTheta = selectedTheta;
    if relativeImprovement <= options.relativeObjectiveTolerance
        converged = true;
        stopReason = "relative_exact_objective_change_small";
        terminationDecided=true;
    elseif scaledStep <= options.scaledStepTolerance
        converged = true;
        stopReason = "scaled_parameter_step_small";
        terminationDecided=true;
    end
    end
    completedIterations=k;
    if k==options.maximumIterations,terminationDecided=true;end
    if terminationDecided,nextPhase='finalize';else,nextPhase='iterate';end
    saveSafeBoundary(nextPhase);
    if terminationDecided,break;end
end
iteration = iteration(1:completedIterations);

% 在同一冻结合同上复算先验与最终结果，避免输出依赖候选数组位置。
finalEvaluationSet = local_evaluate_theta_set( ...
    context, [zeroTheta, bestTheta]);
local_require_valid_evaluation(finalEvaluationSet, '最终先验/估计复核');
work.finalEvaluationHistoryCacheFiles=local_history_cache_files(finalEvaluationSet);
priorEvaluation = local_evaluation_subset(finalEvaluationSet, 1);
finalEvaluation = local_evaluation_subset(finalEvaluationSet, 2);
[finalSchedule, finalKdist, finalWfBiasAtDesign] = ...
    local_theta_to_model(bestTheta, context);
parameterTable = local_parameter_result_table( ...
    parameterContract, bestTheta);
metricTable = local_metric_table( ...
    priorEvaluation, finalEvaluation, context);
iterationTable = local_iteration_table(iteration);

result = struct();
result.schemaVersion = 'SHT_F33_MODEL_ADAPT_V3';
result.program = mfilename;
result.createdAt = datestr(now, 31);
result.routeId = routeDefinition.routeId;
result.modelRoute = options.modelRoute;
result.dataMethod = options.dataMethod;
result.parameterSet = options.parameterSet;
result.scheduleParameterization=options.scheduleParameterization;
result.regularizationGeometry='sum_squared_physical_node_changes';
result.options = options;
result.options.runControl=[]; % 不把会话token、tic或锁上下文写入数值结果。
result.prior = rmfield(prior, 'baseResult');
result.parameterDefinition = parameter;
result.parameterContract = parameterContract;
result.parameterTable = parameterTable;
result.coverageTable = coverageTable;
result.fuelBiasCoverageTable = fuelCoverageTable;
result.training = struct('workbook', paths.trainingWorkbook, ...
    'sourceSha256', sourceHash, ...
    'steadyWindowCount', height(steadyData), ...
    'smallChangeSegmentCount', historyMeta.segmentCount, ...
    'smallChangeFitSampleCount', historyMeta.fitSampleCount, ...
    'steadyWindowTable', steadySource, ...
    'testDataUsed', false, 'truthDataUsed', false);
result.weighting = weighting;
result.forwardPhysicsContract = evidence.forwardPhysicsContract;
result.priorSchedule = prior.schedule;
result.finalSchedule = finalSchedule;
result.priorTheta = zeroTheta;
result.estimatedTheta = bestTheta;
result.estimatedKdistEq = finalKdist;
result.estimatedFuelBiasSchedule = finalSchedule.fuelBias;
result.estimatedWfBiasAtDesign_kgps = finalWfBiasAtDesign;
result.priorEvaluation = priorEvaluation;
result.finalEvaluation = finalEvaluation;
result.metricTable = metricTable;
result.iterations = iteration;
result.iterationTable = iterationTable;
result.priorObjective = priorObjective;
result.finalObjective = local_objective(finalEvaluation, bestTheta, ...
    parameterContract, options.regularizationWeight);
result.converged = converged;
result.stopReason = char(stopReason);
if strcmp(options.steadyThermalMode,'equilibrium')
    % 发布前在最终点重新线性化，不能拿上一个参数点的梯度声明收敛。
    % 两种方法发布前均用候选自身准备状态的完整导数，禁止近似驻点冒充真实驻点。
    [fr,fj,fe,work.finalExact]=local_linearize(context,bestTheta,'candidate_specific');
    g=(fj.'*fr).*parameterContract.prior_sigma+ ...
        options.regularizationWeight*bestTheta./parameterContract.prior_sigma;
    g(bestTheta<=parameterContract.lower_bound & g>0)=0;
    g(bestTheta>=parameterContract.upper_bound & g<0)=0;
    [gt,gr]=local_gcv(fr,fj,bestTheta,parameterContract,options);
    result.finalLinearization=struct('jacobian',fj,'residual',fr, ...
        'maximumProjectedScaledGradient',max(abs(g)), ...
        'gcvTable',gt,'gcvRecommendedLambda',gr, ...
        'jacobianCondition',local_condition_number(fj));
    if strcmp(options.historyJacobianMode,'reuse_per_iteration') && ...
            strcmp(result.stopReason,'projected_gradient_small') && max(abs(g))>1e-4
        result.converged=false;
        result.stopReason='approximate_stationarity_not_confirmed_by_exact_jacobian';
    end
end
result.comparisonWork=work;
result.comparisonWork.totalDllCalls=priorDllCalls+local_profile_dll_count()-startDllCalls;
result.comparisonWork.currentSessionDllCalls=local_profile_dll_count()-startDllCalls;
result.nodeCoordinateFrozen = true;
result.uncoveredNodesExactlyPrior = local_uncovered_nodes_unchanged( ...
    prior.schedule, finalSchedule, familyMap, fuelMap);
result.enhancedTransientEffectsEnabledDuringIdentification = strcmp(options.steadyThermalMode,'equilibrium');
result.visserCorrectionCoefficientsZero = local_transient_coefficients_zero(finalSchedule,options.modelMode);
result.runtime_s = priorRuntimeSeconds+toc(timerId);
result.timing=struct('coreCompute_s',priorCoreSeconds+toc(coreClock),'coreExport_s',NaN,'coreTotal_s',NaN);
result.output = local_output_paths(paths, options);
if ~result.uncoveredNodesExactlyPrior
    error('SHT:F33V2:UncoveredNodeChanged', ...
        '未被飞参覆盖的调度节点发生了变化。');
end
if ~isempty(control)
    payload=struct('schemaVersion','F33_SAFE_STATE_R042_B2','nextPhase','publish', ...
        'result',result,'progress',struct('iteration',completedIterations, ...
        'terminationDecided',true,'converged',result.converged,'stopReason',result.stopReason));
    local_assert_checkpoint_pure(payload);
    sht_tc24_run_control('boundary',control,'f33_state',payload);
end
result=local_publish_result(result,options);

    function saveSafeBoundary(phase)
        % 明确列出可恢复数值，不保存context/cfg/session、Map或运行句柄。
        if isempty(control),return;end
        cached=struct('keys',{{}},'values',{{}});
        if isfield(context,'thermalSession')
            cached=local_checkpoint_cache('save',context.thermalSession.cache);
        end
        state=struct('schemaVersion','F33_SAFE_STATE_R042_B2','frameHash',frameHash, ...
            'nextPhase',phase,'currentTheta',currentTheta,'bestTheta',bestTheta, ...
            'bestObjective',bestObjective,'priorObjective',priorObjective, ...
            'iteration',iteration,'completedIterations',completedIterations, ...
            'terminationDecided',terminationDecided,'converged',converged,'stopReason',stopReason, ...
            'work',work,'familyMap',familyMap,'fuelMap',fuelMap, ...
            'parameterContract',parameterContract,'coverageTable',coverageTable, ...
            'fuelCoverageTable',fuelCoverageTable,'priorEvaluation',priorEvaluation, ...
            'cache',cached,'coreSeconds',priorCoreSeconds+toc(coreClock), ...
            'runtimeSeconds',priorRuntimeSeconds+toc(timerId), ...
            'dllCalls',priorDllCalls+local_profile_dll_count()-startDllCalls, ...
            'progress',struct('iteration',completedIterations,'nextPhase',phase, ...
            'terminationDecided',terminationDecided,'converged',converged,'stopReason',stopReason));
        local_assert_checkpoint_pure(state);
        sht_tc24_run_control('boundary',control,'f33_state',state);
    end
end

function result=local_publish_result(result,options)
% 发布是一个不可中断单元。失败留下原证据，不自动覆盖半份既有交付。
exportClock=tic;paths=local_paths(fileparts(mfilename('fullpath')),options);
if options.modelMode==0&&options.saveEnabled
    target=local_output_paths(paths,options);
    assert(~isfile(target.matFile)&&~isfile(target.workbook)&&~isfile(target.formalWorkbook), ...
        'SHT:F33:PartialPublication','发布目标已存在；保留证据，不覆盖半份或完整结果。');
end
local_progress(options,'exporting',numel(result.iterations),result.finalObjective,'保存已求得结果，未收敛状态如实保留');
if options.saveEnabled
    local_save_result(result);
    local_write_workbook(result);
    local_write_summary(result);
end
if options.plotEnabled
    result.output.figureFiles = local_plot_result(result, paths);
    if options.saveEnabled
        local_save_result(result);
    end
end
result.timing.coreExport_s=toc(exportClock);
result.timing.coreTotal_s=result.timing.coreCompute_s+result.timing.coreExport_s;
if options.saveEnabled,local_save_result(result);end
local_progress(options,'core_completed',numel(result.iterations),result.finalObjective,result.stopReason);
local_print_result(result);
end

function local_progress(o,phase,index,objective,message,estimate)
% 单向进度输出不参与数值决策，安全状态另由共享run_control原子保存。
if ~isfield(o,'progressFile')||isempty(o.progressFile),return;end
value=struct('schemaVersion','F3_STEADY_PROGRESS_R042','runId',o.resultTag, ...
    'status','running','phase',phase,'iteration',index,'maximumIterations',o.maximumIterations, ...
    'objective',objective,'message',message,'updatedAt',datestr(now,31), ...
    'pauseSupported',~isempty(o.runControl),'resumeSupported',~isempty(o.runControl),'resultAvailable',false, ...
    'timing',struct('elapsedAtUpdate_s',max(0,(now-o.progressStartedAt)*86400), ...
    'scope','本次run从准备起至当前安全进度记录，无暂停等待'));
if ~isempty(o.runControl)
    value.timing.elapsedAtUpdate_s=o.runControl.priorActiveSeconds+toc(o.runControl.timer);
    value.timing.pausedSeconds=o.runControl.priorPausedSeconds;
    value.timing.scope='累计有效会话计算；暂停等待单列，最后记录不代表进程存活';
end
if nargin>=6
    value.revisedEstimate=estimate;
elseif isfile(o.progressFile)
    previous=local_read_progress_json(o.progressFile);
    if isfield(previous,'revisedEstimate'),value.revisedEstimate=previous.revisedEstimate;end
end
temporary=[tempname(fileparts(o.progressFile)),'.json'];
fid=fopen(temporary,'w','n','UTF-8');assert(fid>=0);close=onCleanup(@()fclose(fid));
fprintf(fid,'%s',jsonencode(value));clear close;
[ok,msg]=movefile(temporary,o.progressFile,'f');assert(ok,'SHT:F33V2:ProgressWrite','%s',msg);
end

function value=local_read_progress_json(file)
% 状态由UTF-8写出；R2019b的fileread默认编码不能保证正确读取中文。
fid=fopen(file,'r','n','UTF-8');assert(fid>=0,'SHT:F33V2:ProgressRead','无法读取进度文件。');
closer=onCleanup(@()fclose(fid)); %#ok<NASGU>
value=jsondecode(fscanf(fid,'%c'));
end

function value=local_checkpoint_cache(action,value)
% 只打包Map中的纯数据；调用方另核模型、点集和来源身份。
if strcmp(action,'save')
    assert(isa(value,'containers.Map'),'SHT:F33:CheckpointCache','应传入数值缓存Map。');
    names=sort(keys(value));items=values(value,names);
    value=struct('keys',{names},'values',{items});
    local_assert_checkpoint_pure(value);
elseif strcmp(action,'restore')
    local_assert_checkpoint_pure(value);
    assert(isstruct(value)&&all(isfield(value,{'keys','values'}))&& ...
        iscell(value.keys)&&iscell(value.values)&&numel(value.keys)==numel(value.values)&& ...
        numel(unique(value.keys))==numel(value.keys), ...
        'SHT:F33:CheckpointCache','缓存键、值或唯一性不符。');
    restored=containers.Map('KeyType','char','ValueType','any');
    for j=1:numel(value.keys)
        assert(ischar(value.keys{j}),'SHT:F33:CheckpointCache','缓存键必须为字符。');
        restored(value.keys{j})=value.values{j};
    end
    value=restored;
else,error('SHT:F33:CheckpointCache','未知缓存编解码动作。');end
end

function local_assert_checkpoint_pure(value)
% table/string是可独立保存的数据容器；其他对象和任何句柄不进入检查点。
if isnumeric(value)||islogical(value)||ischar(value)||isstring(value),return;end
if istable(value)
    for j=1:width(value),local_assert_checkpoint_pure(value.(value.Properties.VariableNames{j}));end
    local_assert_checkpoint_pure(value.Properties.UserData);return;
end
if isstruct(value)
    f=fieldnames(value);
    for i=1:numel(value),for j=1:numel(f),local_assert_checkpoint_pure(value(i).(f{j}));end,end
    return;
end
if iscell(value)
    for j=1:numel(value),local_assert_checkpoint_pure(value{j});end
    return;
end
error('SHT:F33:CheckpointLiveObject','安全检查点不允许保存%s运行对象。',class(value));
end

function options = local_options(user)
if ~isstruct(user) || ~isscalar(user)
    error('SHT:F33V2:BadOptions', 'userOptions必须为标量结构体。');
end
options = struct();
options.modelMode = 0;
options.preprocessTag = 'R020';
options.modelRoute = 'transient_instant';
options.dataMethod = 'steady_only';
options.parameterSet = 'set1';
options.scheduleParameterization = 'independent_nodes';
options.resultTag = ''; % 未显式指定时按参数化分批，不能覆盖R020/R026结果。
options.priorSource = '2p4';
options.assessmentModelReference=false;
options.priorRoute = 'transient_instant';
options.priorWorkbook = '';
options.priorRuntimeBinding = struct();
options.priorDefinition = struct(); % 仅旧flight父缺显式定义时使用，必须绑定真实Excel/SHA。
options.businessIdentity = struct(); % 新业务入口解析后的确定性编号；旧离线调用可为空。
options.businessRunId = '';
options.prior2p7ContractFile = '';
options.trainingWorkbook = '';
options.stage32File='';options.outputRoot='';options.reportRoot='';
options.progressFile='';
options.runControl=[]; % 空控制保持原离线行为；显式任务持有本会话控制器。
options.outputNaming='legacy'; % 原离线命名不变；显式任务使用独立批次目录内短名。
options.runtimeEstimateTestPoints=0;
options.runtimeEstimateTestWork=struct('historyStepCount',0,'historySegmentCount',0);
options.runtimeEstimateTrainingReplay_s=0;
options.progressStartedAt=NaN;
options.steadyBlockWeight = 0.70;
options.historyBlockWeight = 0.30;
options.historyGuard_s = 1.0;
options.historyIntegrationMethod = 'heun';
options.historyIntegrationStep_s = 0.1; % 仅作用于历程，不作用于稳态代数求解。
options.localThermalWarmup_s = 60; % 工程起始设置，训练片段敏感性核验后冻结。
options.historyJacobianMode = 'candidate_specific'; % 正式默认不变。
options.comparisonCacheDirectory = '';
options.regularizationWeight = 0.05;
options.proposalRegularizationMultipliers = [1, 5, 25];
options.gcvCandidateWeights = [0.01,0.03,0.05,0.1,0.2,0.5,1,2,5,10];
options.priorScaleMultiplier = 0.75;
options.kdistPriorSigma = 0.005;
options.kdistLowerBound = 0;
options.kdistUpperBound = 0.02;
options.kdistDifferenceStep = 2e-4;
options.fuelBiasPriorSigma_kgps = 7.5e-4;
options.fuelBiasBound_kgps = 1.5e-3;
options.fuelBiasDifferenceStep_kgps = 2e-5;
options.minimumNodeSupport = 0.02;
options.steadyThermalMode = 'auto';
options.smallHistoryThermalMode = 'nominal_visser';
options.maximumScaledStep = 2.0; % 旧调用兼容字段，已不用于统一缩放参数更新。
options.maximumIterations = 10;
options.relativeObjectiveTolerance = 1e-3;
options.scaledStepTolerance = 2e-3;
options.modelResidualAcceptance = 1e-2;
options.plotEnabled = true;
options.figureVisible = 'off';
options.saveEnabled = true;
name = fieldnames(user);
for i = 1:numel(name)
    if ~isfield(options, name{i})
        error('SHT:F33V2:UnknownOption', '未知配置字段：%s。', name{i});
    end
    options.(name{i}) = user.(name{i});
end
options.modelRoute = char(lower(string(options.modelRoute)));
if ~isempty(options.runControl)
    assert(options.modelMode==0&&ismember(options.modelRoute,{'steady','transient_instant'})&& ...
        ismember(options.dataMethod,{'steady_only','steady_plus_small_history'}), ...
        'SHT:F33:ControlScope','安全停续仅用于三部件四路线的完整迭代边界。');
end
assert(ismember(options.outputNaming,{'legacy','compact'}),'SHT:F33V2:OutputNaming', ...
    'outputNaming仅支持legacy或compact。');
if options.modelMode~=0 && ~isfield(user,'localThermalWarmup_s')
    options.localThermalWarmup_s=0; % 保留六部件历史行为。
end
validateattributes(options.localThermalWarmup_s,{'numeric'}, ...
    {'scalar','real','finite','nonnegative'});
if options.modelMode~=0 && ~isfield(user,'historyIntegrationStep_s')
    options.historyIntegrationStep_s=0.025;
end
validateattributes(options.historyIntegrationStep_s,{'numeric'}, ...
    {'scalar','real','finite','positive'});
assert(ismember(options.historyIntegrationStep_s,[0.025,0.1]), ...
    'SHT:F33V2:IntegrationStep','historyIntegrationStep_s只允许0.025或0.1秒。');
options.dataMethod = char(lower(string(options.dataMethod)));
assert(ismember(options.historyJacobianMode,{'candidate_specific','reuse_per_iteration'}), ...
    'SHT:F33:JacobianMode','未知准备段Jacobian方式。');
if strcmp(options.historyJacobianMode,'reuse_per_iteration')
    assert(options.modelMode==0 && strcmp(options.dataMethod,'steady_plus_small_history'), ...
        'SHT:F33:JacobianMode','准备段复用试验仅允许三部件混合历程辨识。');
end
options.parameterSet = char(lower(string(options.parameterSet)));
options.scheduleParameterization=char(lower(string(options.scheduleParameterization)));
if ~ismember(options.scheduleParameterization,{'family_amplitude','independent_nodes'})
    error('SHT:F33V2:Parameterization','仅允许全曲线幅值或全有效节点独立估计。');
end
if ~isfield(user,'resultTag')
    if strcmp(options.scheduleParameterization,'independent_nodes')
        options.resultTag='R027_nodes';
    else
        options.resultTag='R027_amplitude';
    end
end
if ~isempty(options.resultTag) && isempty(regexp(options.resultTag,'^[A-Za-z0-9_]+$','once'))
    error('SHT:F33V2:ResultTag','结果标签只能含字母、数字和下划线。');
end
options.priorSource = char(lower(string(options.priorSource)));
options.priorRoute = char(lower(string(options.priorRoute)));
if strcmp(options.steadyThermalMode,'auto')
    options.steadyThermalMode='equilibrium';
end
if ~ismember(options.steadyThermalMode,{'none','equilibrium'})
    error('SHT:F33V2:ThermalMode','稳态点热处理只支持none或equilibrium。');
end
if ~ismember(options.smallHistoryThermalMode,{'none','nominal_visser'})
    error('SHT:F33V2:HistoryThermalMode','小幅热处理只支持none或nominal_visser。');
end
if options.modelMode==0 && (~strcmp(options.steadyThermalMode,'equilibrium') || ...
        ~strcmp(options.smallHistoryThermalMode,'nominal_visser'))
    error('SHT:F33V2:ThreeThermalContract', ...
        '当前三部件四路线均使用标称Visser16，不能静默退回旧无热模型。');
end
if strcmp(options.steadyThermalMode,'none')&&strcmp(options.smallHistoryThermalMode,'nominal_visser') ...
        &&strcmp(options.dataMethod,'steady_plus_small_history')
    error('SHT:F33V2:HistoryThermalMode','标称Visser历程需同时配置稳态点充分热平衡。');
end
if strcmp(options.steadyThermalMode,'equilibrium') && ~isfield(user,'maximumIterations')
    options.maximumIterations=10;
end
if options.modelMode==0&&strcmp(options.dataMethod,'steady_plus_small_history')&& ...
        ~isfield(user,'maximumIterations')
    % 本轮混合历程最多两轮；用户仍可显式提高。到上限不等于收敛。
    options.maximumIterations=2;
end
if ~ismember(options.modelRoute, {'steady','transient_instant'})
    error('SHT:F33V2:ModelRoute', ...
        'modelRoute必须为steady或transient_instant。');
end
if ~ismember(options.dataMethod, ...
        {'steady_only','steady_plus_small_history'})
    error('SHT:F33V2:DataMethod', ...
        'dataMethod必须为steady_only或steady_plus_small_history。');
end
if ~ismember(options.parameterSet, {'set1','set2'})
    error('SHT:F33V2:ParameterSet', 'parameterSet必须为set1或set2。');
end
if ~ismember(options.priorSource, {'2p4','2p7','flight','combined'}) || ...
        ~ismember(options.priorRoute, {'steady','transient_instant'})
    error('SHT:F33V2:Prior', '先验来源或先验路径无效。');
end
positive = {'regularizationWeight','priorScaleMultiplier', ...
    'kdistPriorSigma','kdistDifferenceStep', ...
    'fuelBiasPriorSigma_kgps','fuelBiasBound_kgps', ...
    'fuelBiasDifferenceStep_kgps','minimumNodeSupport', ...
    'maximumScaledStep','relativeObjectiveTolerance', ...
    'scaledStepTolerance','modelResidualAcceptance'};
for i = 1:numel(positive)
    value = options.(positive{i});
    if ~isscalar(value) || ~isfinite(value) || value <= 0
        error('SHT:F33V2:PositiveOption', '%s必须为有限正标量。', positive{i});
    end
end
if options.minimumNodeSupport>1
    error('SHT:F33V2:NodeSupport','线性插值权重门限不能大于1。');
end
if ~isscalar(options.historyGuard_s)||~isfinite(options.historyGuard_s)||options.historyGuard_s<0
    error('SHT:F33V2:HistoryGuard','小幅历程保护时间必须为有限非负标量。');
end
if ~ismember(options.historyIntegrationMethod,{'heun','euler'})
    error('SHT:F33V2:Integration','积分方法只支持heun或euler。');
end
for name={'proposalRegularizationMultipliers','gcvCandidateWeights'}
    value=options.(name{1});
    if ~isnumeric(value)||~isreal(value)||~isvector(value)||isempty(value)|| ...
            any(~isfinite(value))||any(value<=0)
        error('SHT:F33V2:RegularizationCandidates','%s必须为有限正数向量。',name{1});
    end
end
if options.kdistLowerBound < 0 || ...
        options.kdistUpperBound <= options.kdistLowerBound || ...
        options.kdistUpperBound >= 0.995
    error('SHT:F33V2:KdistBounds', 'K_dist_eq边界无效。');
end
if options.maximumIterations < 1 || ...
        options.maximumIterations ~= round(options.maximumIterations)
    error('SHT:F33V2:Iterations', 'maximumIterations必须为正整数。');
end
if ~isscalar(options.steadyBlockWeight)||~isscalar(options.historyBlockWeight) || ...
        any(~isfinite([options.steadyBlockWeight,options.historyBlockWeight])) || ...
        any([options.steadyBlockWeight,options.historyBlockWeight]<0)
    error('SHT:F33V2:BlockWeight','数据块权重必须为有限非负标量。');
end
if strcmp(options.dataMethod, 'steady_only')
    options.steadyBlockWeight = 1;
    options.historyBlockWeight = 0;
elseif abs(options.steadyBlockWeight + options.historyBlockWeight - 1) > 1e-12
    error('SHT:F33V2:BlockWeight', '两类数据权重之和必须为1。');
end
if any(~isfinite(options.proposalRegularizationMultipliers)) || ...
        options.proposalRegularizationMultipliers(1) ~= 1 || ...
        any(options.proposalRegularizationMultipliers < 1)
    error('SHT:F33V2:ProposalLambda', ...
        '候选正则倍数必须以1开头且均不小于1。');
end
end

function paths = local_paths(thisDir, options)
programRoot = fileparts(thisDir);
paths = struct();
if options.modelMode==0
    a=sht_f3_current_contract('paths');
    pre=fullfile(a.middle,'preprocess',options.preprocessTag);
    paths.trainingWorkbook=options.trainingWorkbook;
    if isempty(paths.trainingWorkbook)
        paths.trainingWorkbook=fullfile(pre,'delivery','flight_model_adapt_3p2_identification.xlsx');
    end
    paths.stage32File=fullfile(pre,'flight_model_adapt_3p2_second_round_latest.mat');
    if ~isempty(options.stage32File),paths.stage32File=options.stage32File;end
    paths.middleDir=fullfile(a.middle,'identification');
    if ~isempty(options.outputRoot),paths.middleDir=options.outputRoot;end
    paths.deliveryDir=fullfile(paths.middleDir,'delivery');
    paths.reportDir=fullfile(a.report,'F3_4');
    if ~isempty(options.reportRoot),paths.reportDir=options.reportRoot;end
    for f={paths.middleDir,paths.deliveryDir,paths.reportDir}
        if ~isfolder(f{1}),mkdir(f{1});end
    end
    assert(isfile(paths.trainingWorkbook)&&isfile(paths.stage32File),'缺少本轮三部件预处理交付。');return;
end
paths.trainingWorkbook = options.trainingWorkbook;
if isempty(paths.trainingWorkbook)
    paths.trainingWorkbook = fullfile(thisDir, 'MiddleData', ...
        'flight_model_adapt_3p2', 'delivery', ...
        'flight_model_adapt_3p2_identification.xlsx');
end
paths.stage32File = fullfile(thisDir, 'MiddleData', ...
    'flight_model_adapt_3p2', ...
    'flight_model_adapt_3p2_second_round_latest.mat');
required = {paths.trainingWorkbook, paths.stage32File};
for i = 1:numel(required)
    if ~isfile(required{i})
        error('SHT:F33V2:MissingFile', '缺少输入文件：%s。', required{i});
    end
end
paths.middleDir = fullfile(thisDir, 'MiddleData', ...
    'flight_model_adapt_3p3_v2');
paths.deliveryDir = fullfile(paths.middleDir, 'delivery');
paths.reportDir = fullfile(programRoot, 'report_outputs', ...
    'flight_model_adapt_3p3_v2');
for value = {paths.middleDir, paths.deliveryDir, paths.reportDir}
    if ~isfolder(value{1}), mkdir(value{1}); end
end
end

function prior = local_load_prior(thisDir, options)
if options.modelMode==0
    if ismember(options.priorSource,{'2p4','2p7','flight','combined'})
        parent=sht_f3_current_contract('parent',options);
        s=local_prepare_prior_schedule(parent.schedule);s.modelMode=0;
        baseResult=parent.baseResult;baseResult.finalSchedule=s;
        prior=struct('source',options.priorSource,'route',options.priorRoute, ...
            'sourceDescription','所选正式Excel恢复健康曲线，本架次燃油和装机量仍从零重估', ...
            'sourceFile',parent.file,'sourceSha256',parent.sha256, ...
            'runtimeAssociation',parent.runtimeAssociation, ...
            'scheduleSemanticSha256',local_struct_hash(s),'schedule',s,'baseResult',baseResult);
        return;
    end
    error('SHT:F33:ParentSource','三部件父来源只支持2p4、2p7或flight。');
end
delivery = sht_load_2p4_deterministic_delivery( ...
    options.priorRoute, options.priorWorkbook);
baseResult = delivery.result;
if strcmp(options.priorSource, '2p4')
    schedule = baseResult.finalSchedule;
    sourceFile = delivery.workbookFile;
    sourceHash = delivery.workbookSha256;
    description = sprintf('2.4确定性辨识%s路径正式交付', options.priorRoute);
else
    sourceFile = options.prior2p7ContractFile;
    if isempty(sourceFile)
        sourceFile = fullfile(thisDir, 'MiddleData', ...
            'transient_model_adapt_2p7', ...
            'transient_model_adapt_2p7_m0_steady_schedule_for_transient_latest.mat');
    end
    loaded = load(sourceFile, 'downstreamContract');
    if ~isfield(loaded, 'downstreamContract') || ...
            ~isfield(loaded.downstreamContract, 'schedule') || ...
            ~isfield(loaded.downstreamContract, 'physicalValid') || ...
            ~loaded.downstreamContract.physicalValid
        error('SHT:F33V2:Bad2p7Prior', '2.7先验合同无效。');
    end
    schedule = loaded.downstreamContract.schedule;
    sourceHash = local_file_hash(sourceFile);
    description = '2.7显式选择的稳态调度交付';
end
schedule = local_prepare_prior_schedule(schedule);
baseResult.finalSchedule = schedule;
prior = struct('source', options.priorSource, ...
    'route', options.priorRoute, 'sourceDescription', description, ...
    'sourceFile', sourceFile, 'sourceSha256', sourceHash, ...
    'scheduleSemanticSha256', local_struct_hash(schedule), ...
    'schedule', schedule, 'baseResult', baseResult);
end

function schedule = local_prepare_prior_schedule(schedule)
if ~isfield(schedule, 'designHealth') || numel(schedule.designHealth) ~= 159
    error('SHT:F33V2:PriorHealth', '先验调度缺少159维健康参数。');
end
% 2.4燃油偏置属于台架测量系统，不得带入本次飞行架次。
schedule.fuelBias.biasNodes = zeros(size(schedule.fuelBias.biasNodes));
schedule.designHealth = schedule.designHealth(:);
schedule.designHealth(90:112) = 0;
schedule.designHealth(16) = schedule.h15;
end

function parameter = local_parameter_definition(baseResult, parameterSet)
switch parameterSet
    case 'set1'
        requiredC = [1;2;7;8;10;11;12];
    case 'set2'
        requiredC = [1;2;6;7;8;10;11;12;14;15];
end
allParameter = baseResult.parameterDefinition;
row = zeros(numel(requiredC), 1);
for i = 1:numel(requiredC)
    found = find(allParameter.c_index == requiredC(i), 1);
    if isempty(found)
        error('SHT:F33V2:ParameterContract', ...
            '先验参数合同缺少h%d。', requiredC(i));
    end
    row(i) = found;
end
parameter = allParameter(row, :);
parameter.family_index = (1:height(parameter)).';
parameter = movevars(parameter, 'family_index', 'Before', 1);
end

function [history, segments, sourceHash] = local_read_training(fileName)
history = readtable(fileName, 'Sheet', 'history');
segments = readtable(fileName, 'Sheet', 'segments');
if ~ismember('Mkg',history.Properties.VariableNames),history.Mkg=zeros(height(history),1);end
requiredHistory = {'sample_id','time_s','Ps0','Tt1','Pt3_eq','Ng','Np', ...
    'Mkp','Mkg','Wf','Tt45','Altitude','Mach','Ts_amb', ...
    'model_input_inlet_pressure_recovery'};
requiredSegment = {'segment_id','segment_class','first','last', ...
    'start_s','end_s','duration_s','sample_count'};
missing = setdiff(requiredHistory, history.Properties.VariableNames);
missingSegment = setdiff(requiredSegment, segments.Properties.VariableNames);
if ~isempty(missing) || ~isempty(missingSegment)
    error('SHT:F33V2:TrainingSchema', ...
        '3.2训练Excel缺少字段：%s。', ...
        strjoin([missing, missingSegment], ', '));
end
numeric = setdiff(requiredHistory, {'sample_id'});
if any(~isfinite(history{:, numeric}), 'all') || any(diff(history.time_s) <= 0)
    error('SHT:F33V2:TrainingValue', '训练Excel含无效数值或非递增时间。');
end
indices=[segments.first,segments.last];
if any(~isfinite(indices),'all') || any(indices~=round(indices),'all') || ...
        any(segments.first<1|segments.last>height(history)|segments.first>segments.last)
    error('SHT:F33V2:SegmentIndex','片段索引必须是当前历程范围内的有效整数。');
end
if any(abs(history.time_s(segments.first)-segments.start_s)>1e-8) || ...
        any(abs(history.time_s(segments.last)-segments.end_s)>1e-8)
    error('SHT:F33V2:SegmentTime','片段索引与时间边界不匹配。');
end
sourceHash = local_file_hash(fileName);
end

function [data, source] = local_build_steady_data(history, segments)
selected = local_selected_segments(segments, 'steady_window');
if isempty(selected)
    error('SHT:F33V2:NoSteadyWindow', '训练数据没有可用稳态窗口。');
end
n = numel(selected);
point_id = strings(n,1);
Np_mean=zeros(n,1); Ng_mean=zeros(n,1); Wf_mean=zeros(n,1);
Tt45_mean=zeros(n,1); Mkp_mean=zeros(n,1); Mkg_mean=zeros(n,1);
Tt1_mean=zeros(n,1); Pt3_mean=zeros(n,1); Pamb_mean=zeros(n,1);
Tamb_mean=zeros(n,1); Altitude_mean=zeros(n,1); Mach_mean=zeros(n,1);
inlet_pressure_recovery_mean=zeros(n,1);
start_s=zeros(n,1); end_s=zeros(n,1); sample_count=zeros(n,1);
for i = 1:n
    segment = segments(selected(i), :);
    row = round(segment.first):round(segment.last);
    point_id(i) = string(segment.segment_id);
    Np_mean(i)=mean(history.Np(row)); Ng_mean(i)=mean(history.Ng(row));
    Wf_mean(i)=mean(history.Wf(row)); Tt45_mean(i)=mean(history.Tt45(row));
    Mkp_mean(i)=mean(history.Mkp(row)); Mkg_mean(i)=mean(history.Mkg(row));
    Tt1_mean(i)=mean(history.Tt1(row)); Pt3_mean(i)=mean(history.Pt3_eq(row));
    Pamb_mean(i)=mean(history.Ps0(row)); Tamb_mean(i)=mean(history.Ts_amb(row));
    Altitude_mean(i)=mean(history.Altitude(row)); Mach_mean(i)=mean(history.Mach(row));
    inlet_pressure_recovery_mean(i)=0.995;
    start_s(i)=segment.start_s; end_s(i)=segment.end_s;
    sample_count(i)=numel(row);
end
% 下列三列仅用于兼容2.4公共求解器表结构；mode 5从不读取它们作为
% 入口，也不把它们纳入3.3残差。
Pt2_mean=ones(n,1)*101325; Tt3_mean=ones(n,1)*500;
Pt45_mean=ones(n,1)*101325;
data=table(point_id,Np_mean,Ng_mean,Wf_mean,Tt45_mean,Pt45_mean, ...
    Mkp_mean,Mkg_mean,Pt2_mean,Tt1_mean,Pt3_mean,Tt3_mean,Pamb_mean, ...
    Tamb_mean,Altitude_mean,Mach_mean,inlet_pressure_recovery_mean);
source=table(point_id,start_s,end_s,sample_count);
end

function [historyData, meta] = local_build_small_history( ...
        history, segments, guard_s, dataMethod, warmup_s)
if strcmp(dataMethod, 'steady_only')
    historyData = struct('experiments', struct([]), 'table', table(), ...
        'fitMask', false(0,1), 'segmentIndex', zeros(0,1), ...
        'measuredOutput', zeros(0,4));
    meta = struct('segmentCount',0,'segments',struct([]), ...
        'totalSampleCount',0,'fitSampleCount',0);
    return;
end
selected = local_selected_segments(segments, 'small_change');
if isempty(selected)
    error('SHT:F33V2:NoSmallHistory', '训练数据没有可用小幅变化段。');
end
thermalPlan=sht_f33_local_thermal_plan(history.time_s,segments(selected,:),warmup_s);
template=struct('experimentId','','data',table(),'time_s',[],'fitMask',[], ...
    'replayData',table(),'outputRows',[],'warmup_s',0);
experiments=repmat(template,numel(selected),1);
tableCell=cell(numel(selected),1); fitCell=cell(numel(selected),1);
segmentIndexCell=cell(numel(selected),1); measuredCell=cell(numel(selected),1);
metaSegment=repmat(struct('experimentId','','rowIndices',[], ...
    'sampleCount',0,'fitSampleCount',0),numel(selected),1);
cursor=0;
for i=1:numel(selected)
    segment=segments(selected(i),:);
    row=(round(segment.first):round(segment.last)).';
    count=numel(row);
    one=table(history.Np(row),history.Ng(row),history.Wf(row), ...
        history.Mkp(row),history.Mkg(row),ones(count,1)*101325, ...
        history.Tt1(row),history.Pt3_eq(row),ones(count,1)*500, ...
        history.Tt45(row),ones(count,1)*101325,history.Ps0(row), ...
        history.Ts_amb(row),history.Altitude(row),history.Mach(row), ...
        ones(count,1)*0.995, 'VariableNames', ...
        {'Np','Ng','Wf','Mkp','Mkg','Pt2','Tt1','Pt3','Tt3', ...
         'Tt45','Pt45','Pamb','Tamb','Altitude','Mach', ...
         'inlet_pressure_recovery'});
    time=history.time_s(row); time=time-time(1);
    fit=time>=guard_s & time<=time(end)-guard_s;
    if nnz(fit)<2
        error('SHT:F33V2:HistoryGuard', ...
            '小幅段%s时长%.3fs不足以保留两端各%.3fs保护区，请检查分段或保护配置。', ...
            string(segment.segment_id),time(end),guard_s);
    end
    % 热准备只使用本架次测量输入，不加入目标残差或调度节点覆盖统计。
    first=thermalPlan.initialization_first(i);
    replayRows=(first:row(end)).';
    % 预处理Excel还含字符串分段标签，不能把标签交给积分插值。
    measuredNames={'sample_id','time_s','Ps0','Tt1','Pt3_eq','Ng','Np', ...
        'Mkp','Mkg','Wf','Tt45','Altitude','Mach','Ts_amb'};
    replayData=history(replayRows,measuredNames);
    actualWarmup=history.time_s(row(1))-history.time_s(first);
    replayData.time_s=replayData.time_s-replayData.time_s(1);
    experiments(i)=struct('experimentId',char(string(segment.segment_id)), ...
        'data',one,'time_s',time,'fitMask',fit,'replayData',replayData, ...
        'outputRows',row-first+1,'warmup_s',actualWarmup);
    tableCell{i}=one; fitCell{i}=fit; segmentIndexCell{i}=i*ones(count,1);
    measuredCell{i}=[one.Np,one.Ng,one.Pt3,one.Tt45];
    fullRow=cursor+(1:count);
    metaSegment(i)=struct('experimentId',char(string(segment.segment_id)), ...
        'rowIndices',fullRow(:),'sampleCount',count,'fitSampleCount',nnz(fit));
    cursor=cursor+count;
end
historyData=struct('experiments',experiments,'table',vertcat(tableCell{:}), ...
    'fitMask',vertcat(fitCell{:}),'segmentIndex',vertcat(segmentIndexCell{:}), ...
    'measuredOutput',vertcat(measuredCell{:}));
meta=struct('segmentCount',numel(selected),'segments',metaSegment, ...
    'totalSampleCount',height(historyData.table), ...
    'fitSampleCount',nnz(historyData.fitMask),'localThermalPlan',thermalPlan);
end

function evidence = local_prepare_evidence(history,segments,options)
% 独立点、独立小幅段和完整回放必须使用同一套装机边界公式。
% 不读取预测Np、隐藏背压或隐藏功率。背压仅保留模型配置，不能先用
% 测量Np计算后平均并冻结；每个候选模型须在求解内部更新背压。
boundary=sht_f32_replay_history('reconstructBoundary',history,struct());
[steadyData,steadySource]=local_build_steady_data(history,segments);
[historyData,historyMeta]=local_build_small_history( ...
    history,segments,options.historyGuard_s,options.dataMethod,options.localThermalWarmup_s);
physics=struct('schemaVersion','SHT_F33_FORWARD_PHYSICS_V2', ...
    'historyIntegrationStep_s',options.historyIntegrationStep_s, ...
    'localThermalWarmup_s',options.localThermalWarmup_s, ...
    'boundary',boundary.contract, ...
    'steadyBackpressureAggregation','none_candidate_model_evaluation', ...
    'reynoldsCorrection',sht_reynolds_correction_config(1), ...
    'enhancedTransientEffectsEnabled',strcmp(options.steadyThermalMode,'equilibrium'), ...
    'transientIndividualCorrectionSource','nominal_zero');
if options.modelMode==0
    physics.reynoldsCorrection=struct('modelMode',0,'source','runtime_design_reference','effectScale',1);
end
evidence=struct('steadyData',steadyData,'steadySource',steadySource, ...
    'historyData',historyData,'historyMeta',historyMeta, ...
    'forwardPhysicsContract',physics);
end

function selected = local_selected_segments(segments, className)
selected = find(string(segments.segment_class) == string(className));
if ismember('usable', segments.Properties.VariableNames)
    selected = selected(logical(segments.usable(selected)));
end
end

function weighting = local_weighting_contract(options, stage32File)
if options.modelMode==0
    % 沿TC24三部件工程尺度，仅取飞参可用输出；这不是传感器噪声白化。
    steadyWeight=struct('names',["Np";"Ng";"Pt3";"Tt45"], ...
        'activeSigma',[63;114;7863;5.72]);
    transientWeight=struct('names',["Pt3";"Tt45";"dNp_dt";"dNg_dt"], ...
        'activeSigma',[7863;5.72;20.9;38]);
else
steadyDelivery=sht_load_2p4_deterministic_delivery('steady');
transientDelivery=sht_load_2p4_deterministic_delivery('transient_instant');
steadyWeight=steadyDelivery.result.residualWeighting;
transientWeight=transientDelivery.result.residualWeighting;
end
if strcmp(options.modelRoute,'steady')
    steadyNames=["Np";"Ng";"Pt3_eq";"Tt45"];
    sourceNames=["Np";"Ng";"Pt3";"Tt45"];
    steadySigma=local_pick_scales(steadyWeight,sourceNames);
    steadyUnits=["rpm";"rpm";"Pa";"K"];
else
    steadyNames=["Pt3_eq";"Tt45";"dNp_dt";"dNg_dt"];
    sourceNames=["Pt3";"Tt45";"dNp_dt";"dNg_dt"];
    steadySigma=local_pick_scales(transientWeight,sourceNames);
    steadyUnits=["Pa";"K";"rpm/s";"rpm/s"];
end
historyNames=["Np";"Ng";"Pt3_eq";"Tt45"];
historySource=["Np";"Ng";"Pt3";"Tt45"];
historySigma=local_pick_scales(steadyWeight,historySource);
historyUnits=["rpm";"rpm";"Pa";"K"];
loaded=load(stage32File,'flightModelAdaptData');
tau=[0.020,0.020,0.020,0,0.500,0];
if isfield(loaded,'flightModelAdaptData') && ...
        isfield(loaded.flightModelAdaptData,'measurementObjectParameters')
    channel=loaded.flightModelAdaptData.measurementObjectParameters.channelTable;
    tau(1)=local_channel_tau(channel,'Np',tau(1));
    tau(2)=local_channel_tau(channel,'Ng',tau(2));
    tau(3)=local_channel_tau(channel,'Pt3_eq',tau(3));
    tau(5)=local_channel_tau(channel,'Tt45',tau(5));
end
weighting=struct('steadyNames',steadyNames,'steadyUnits',steadyUnits, ...
    'steadySigma',steadySigma(:),'historyNames',historyNames, ...
    'historyUnits',historyUnits,'historySigma',historySigma(:), ...
    'steadyBlockWeight',options.steadyBlockWeight, ...
    'historyBlockWeight',options.historyBlockWeight, ...
    'trajectorySensorTimeConstant_s',tau, ...
    'source','2.4 M0 engineering-scale contracts');
end

function value = local_pick_scales(contract, names)
contractNames=string(contract.names(:));
value=zeros(numel(names),1);
for i=1:numel(names)
    row=find(contractNames==names(i),1);
    if isempty(row)
        error('SHT:F33V2:WeightingChannel','2.4权重缺少%s。',names(i));
    end
    value(i)=contract.activeSigma(row);
end
if any(~isfinite(value))||any(value<=0)
    error('SHT:F33V2:WeightingScale','2.4工程尺度无效。');
end
end

function value = local_channel_tau(channel, name, fallback)
row=find(strcmp(cellstr(string(channel.name)),name),1);
if isempty(row) || ~isfinite(channel.timeConstant_s(row)) || ...
        channel.timeConstant_s(row)<0
    value=fallback;
else
    value=channel.timeConstant_s(row);
end
end

function evaluation = local_evaluate_theta_set(context, thetaMatrix,frozenModels)
if nargin<3,frozenModels=[];end
if ismember('Pback_mean',context.steadyData.Properties.VariableNames)
    error('SHT:F33V2:UnmeasuredBackpressureInput', ...
        '3.3禁止把不可测Pback_mean作为输入，请重新构造测量证据。');
end
if strcmp(context.options.dataMethod,'steady_plus_small_history') && ...
        any(arrayfun(@(item)ismember('Pback',item.data.Properties.VariableNames), ...
        context.historyData.experiments))
    error('SHT:F33V2:UnmeasuredBackpressureInput', ...
        '3.3禁止输入冻结背压历程；背压由当前模型状态计算。');
end
exhaustModel=sht_f32_replay_history('backpressureModel');
if isvector(thetaMatrix), thetaMatrix=thetaMatrix(:); end
if isfield(context,'parameterContract') && ~isempty(context.parameterContract)
    expectedCount=height(context.parameterContract);
else
    expectedCount=height(context.parameter)+2;
end
if size(thetaMatrix,1)~=expectedCount
    error('SHT:F33V2:ThetaSize','候选参数维数不符合当前参数组合。');
end
n=size(thetaMatrix,2);
schedules=cell(n,1); recoveries=zeros(n,1);
if isempty(frozenModels)
    for i=1:n
        [schedules{i},kdist]=local_theta_to_model(thetaMatrix(:,i),context);
        recoveries(i)=0.995-kdist;
    end
else
    assert(numel(frozenModels.schedules)==n&&numel(frozenModels.recoveries)==n);
    schedules=frozenModels.schedules;recoveries=frozenModels.recoveries;
end
batchOptions=struct('routeOverride',context.options.modelRoute, ...
    'inletBoundaryMode',5, ...
    'inletPressureRecoveryByCandidate',recoveries, ...
    'maxModelResidual',context.options.modelResidualAcceptance, ...
    'steadyLoadBoundaryMode','torque', ...
    'reynoldsCorrection',sht_reynolds_correction_config(1), ...
    'exhaustBackPressureModel',exhaustModel);
if isfield(context,'frozenSteadyBatch')
    steadyBatch=context.frozenSteadyBatch;
    batchOptions.reynoldsCorrection=context.thermalSession.cfg.engine.reynoldsCorrection;
elseif isfield(context,'thermalSession')
    batchOptions.reynoldsCorrection=context.thermalSession.cfg.engine.reynoldsCorrection;
    steadyBatch=sht_f33_thermal_equilibrium('batch',context.thermalSession,schedules,recoveries);
else
    steadyBatch=sht_steady_model_adapt_v2_common( ...
        'evaluateschedulebatchdataset',context.baseResult, ...
        context.steadyData,schedules,batchOptions);
end
historyBatch=[];
if strcmp(context.options.dataMethod,'steady_plus_small_history')
    trajectoryOptions=struct( ...
        'integrationMethod',context.options.historyIntegrationMethod, ...
        'maxModelResidual',context.options.modelResidualAcceptance, ...
        'sensorTimeConstant_s', ...
        context.weighting.trajectorySensorTimeConstant_s, ...
        'inletBoundaryMode',5, ...
        'inletMeanRecoveryByCandidate',recoveries, ...
        'reynoldsCorrection',batchOptions.reynoldsCorrection, ...
        'exhaustBackPressureModel',batchOptions.exhaustBackPressureModel);
    if strcmp(context.options.smallHistoryThermalMode,'nominal_visser')
        historyOptions=context.options;
        if isfield(context,'comparisonCapturePreparation')
            historyOptions.capturePreparation=context.comparisonCapturePreparation;
            historyOptions.reusePreparation=context.comparisonReusePreparation;
        end
        historyBatch=sht_f33_small_history_batch(context.replayAssets, ...
            context.historyData.experiments,schedules,recoveries, ...
            context.sensorAssumptions,historyOptions);
    else
        historyBatch=sht_steady_model_adapt_v2_common( ...
            'evaluatescheduletrajectorybatch',context.baseResult, ...
            context.historyData.experiments,schedules,trajectoryOptions);
    end
end
candidate=repmat(local_empty_candidate(),n,1);
for i=1:n
    candidate(i).theta=thetaMatrix(:,i);
    candidate(i).schedule=schedules{i};
    candidate(i).KdistEq=0.995-recoveries(i);
    candidate(i).WfBiasAtDesign_kgps=local_interp_clamp( ...
        schedules{i}.fuelBias.xNodes,schedules{i}.fuelBias.biasNodes,1);
    candidate(i).steadyPrediction=steadyBatch.candidate(i).prediction;
    candidate(i).steadyAxis=local_static_axis( ...
        steadyBatch.candidate(i).prediction);
    candidate(i).valid=steadyBatch.candidate(i).valid;
    if isfield(context,'thermalSession') && ~candidate(i).valid
        records=steadyBatch.candidate(i).diagnostic.records;
        messages=strings(0,1);
        for k=1:numel(records)
            q=records{k};if q.valid,continue;end
            messages(end+1)=sprintf('%s: %s, gas=%.3g, shaft=%.3g rpm/s, thermal=%.3g K/s', ...
                context.steadyData.point_id(k),q.stop,q.modelResidual, ...
                max(abs(q.derivative(1:2))),max(abs(q.derivative(3:end)))); %#ok<AGROW>
        end
        candidate(i).historyReplayError=strjoin(messages,'; ');
    end
    candidate(i).steadyRaw=local_steady_raw( ...
        candidate(i).steadyPrediction,context.steadyData, ...
        context.options.modelRoute);
    if ~isempty(historyBatch)
        candidate(i).historyPrediction=historyBatch.candidate(i).prediction;
        candidate(i).historyAxis=historyBatch.candidate(i).axis;
        candidate(i).historyReplayError=historyBatch.candidate(i).errorMessage;
        if isempty(candidate(i).historyPrediction)
            % 保留原求值错误和无效候选，不让空表索引掩盖真正原因。
            candidate(i).historyRaw=nan(size(context.historyData.measuredOutput));
        else
            candidate(i).historyRaw=local_history_raw( ...
                candidate(i).historyPrediction,context.historyData);
        end
        candidate(i).valid=candidate(i).valid && ...
            historyBatch.candidate(i).valid;
    end
    [candidate(i).residualVector,candidate(i).blockMetrics] = ...
        local_weighted_residual(candidate(i),context);
    candidate(i).valid=candidate(i).valid && ...
        all(isfinite(candidate(i).residualVector));
end
evaluation=struct('candidate',candidate,'steadyBatch',steadyBatch, ...
    'historyBatch',historyBatch);
end

function batch=local_frozen_steady_batch(assets,points,pointSource,frozen)
% C2求解已经返回完整热平衡记录，直接组织成原batch，不重复求解。
inputs={'Altitude_mean','Mach_mean','Pamb_mean','Tamb_mean','Tt1_mean','Mkp_mean','Wf_mean'};
units=cell2struct({'m','1','Pa','K','K','N*m','kg/s'},inputs,2);
p=points(:,[{'point_id'},inputs]);p.sample_count=pointSource.sample_count;
p=sht_f34_input_point_seed('validate',p,units);
o=struct('seedScales',[1,.8,1.1],'npBounds',[5000,40000],'seed',340061);
names={'Np','Ng','Pt3','Tt45','inlet_corrected_mass_flow','burner_inlet_corrected_mass_flow', ...
    'gt_pt_duct_corrected_mass_flow','pt_nozzle_duct_corrected_mass_flow','ac_corrected_speed', ...
    'gt_total_pressure_ratio','pt_total_pressure_ratio','dNp_dt','dNg_dt'};
schedules={frozen.priorSchedule,frozen.finalSchedule};dist=[0,frozen.estimatedKdistEq];
candidate=repmat(struct('prediction',table(),'valid',false,'diagnostic',struct()),2,1);
branches=cell(2,1);
for k=1:2
    package=struct('deterministic',true,'assets',assets,'KdistEq',dist(k), ...
        'context',struct('priorSchedule',schedules{k}));
    solved=sht_f34_input_point_seed('solve',package,p,o);branches{k}=solved.branch;
    records=cell(height(p),1);prediction=table();
    for j=1:height(p)
        if solved.valid(j),r=solved.chosen{j}.detail{1};
        else
            message=strjoin(cellstr(solved.audit.reason(solved.audit.point_id==string(p.point_id(j)))),'; ');
            r=struct('valid',false,'prediction',array2table(nan(1,numel(names)),'VariableNames',names), ...
                'stop',message,'modelResidual',NaN,'derivative',nan(16,1));
        end
        records{j}=r;prediction=[prediction;r.prediction]; %#ok<AGROW>
    end
    candidate(k).prediction=prediction;candidate(k).valid=all(solved.valid);
    candidate(k).diagnostic=struct('records',{records},'seedAudit',solved.audit, ...
        'rootCount',solved.rootCount,'pointMeasuredSpeedUsed',false);
end
branch=branches{1};branch.perModel=branches;
batch=struct('candidate',candidate,'branch',branch);
end

function raw = local_steady_raw(prediction, data, route)
if strcmp(route,'steady')
    raw=[prediction.Np-data.Np_mean,prediction.Ng-data.Ng_mean, ...
        prediction.Pt3-data.Pt3_mean,prediction.Tt45-data.Tt45_mean];
else
    raw=[prediction.Pt3-data.Pt3_mean, ...
        prediction.Tt45-data.Tt45_mean,prediction.dNp_dt,prediction.dNg_dt];
end
end

function raw = local_history_raw(prediction, historyData)
raw=[prediction.Np,prediction.Ng,prediction.Pt3,prediction.Tt45]- ...
    historyData.measuredOutput;
end

function axis = local_static_axis(prediction)
names={'inlet_corrected_mass_flow','burner_inlet_corrected_mass_flow', ...
    'gt_pt_duct_corrected_mass_flow','pt_nozzle_duct_corrected_mass_flow', ...
    'ac_corrected_speed','gt_total_pressure_ratio','pt_total_pressure_ratio'};
axis=prediction(:,names);
end

function [vector, metrics] = local_weighted_residual(candidate, context)
steadyWeight=ones(size(candidate.steadyRaw,1),1)/ ...
    size(candidate.steadyRaw,1);
steadyVector=local_whiten(candidate.steadyRaw, ...
    context.weighting.steadySigma, ...
    context.options.steadyBlockWeight,steadyWeight);
historyVector=zeros(0,1);
historyCost=0; historyNrms=NaN;
if strcmp(context.options.dataMethod,'steady_plus_small_history')
    fit=context.historyData.fitMask;
    rowWeight=local_history_row_weight(fit,context.historyMeta);
    historyRaw=candidate.historyRaw(fit,:);
    historyVector=local_whiten(historyRaw, ...
        context.weighting.historySigma, ...
        context.options.historyBlockWeight,rowWeight);
    historyCost=0.5*sum(historyVector.^2);
    historyNrms=sqrt(sum(rowWeight.*mean((historyRaw./ ...
        context.weighting.historySigma(:).').^2,2)));
end
vector=[steadyVector;historyVector];
metrics=struct('steadyDataCost',0.5*sum(steadyVector.^2), ...
    'historyDataCost',historyCost,'combinedDataCost',0.5*sum(vector.^2), ...
    'steadyNrms',sqrt(mean((candidate.steadyRaw./ ...
    context.weighting.steadySigma(:).').^2,'all')), ...
    'historyNrms',historyNrms);
end

function vector = local_whiten(raw, sigma, blockWeight, rowWeight)
if blockWeight==0 || isempty(raw),vector=zeros(0,1);return;end
rowWeight=rowWeight(:)/sum(rowWeight);
factor=sqrt(blockWeight*rowWeight/size(raw,2));
scaled=(raw./sigma(:).').*factor;
vector=scaled(:);
end

function weight = local_history_row_weight(fitMask, meta)
full=zeros(numel(fitMask),1); active=0;
for i=1:meta.segmentCount
    row=meta.segments(i).rowIndices(:);
    selected=row(fitMask(row));
    if isempty(selected),continue;end
    active=active+1; full(selected)=1/numel(selected);
end
if active==0,error('SHT:F33V2:EmptyHistory','小幅历程拟合掩码为空。');end
full=full/active; weight=full(fitMask);
end

function candidate = local_empty_candidate()
candidate=struct('theta',[],'schedule',struct(),'KdistEq',NaN, ...
    'WfBiasAtDesign_kgps',NaN,'steadyPrediction',table(), ...
    'historyPrediction',table(),'historyReplayError',"", ...
    'steadyAxis',table(),'historyAxis',table(),'steadyRaw',[], ...
    'historyRaw',[],'residualVector',[],'blockMetrics',struct(), ...
    'valid',false);
end

function local_require_valid_evaluation(evaluation,label)
valid=[evaluation.candidate.valid];
if ~all(valid)
    message=strjoin(string({evaluation.candidate(~valid).historyReplayError}),'; ');
    error('SHT:F33V2:InvalidReplay','%s含%d个无效候选。历程诊断：%s', ...
        label,nnz(~valid),char(message));
end
end

function [map, tableValue] = local_build_family_map( ...
        schedule, parameter, evaluation, steadyData, historyData, ...
        historyMeta, options)
base=evaluation.candidate(1);
template=struct('cIndex',0,'name','','scheduled',false,'axisName','', ...
    'entryIndex',0,'basis',[],'support',[],'activeNode',[]);
map=repmat(template,height(parameter),1);
rows=cell(height(parameter),1);
for i=1:height(parameter)
    c=parameter.c_index(i);
    map(i).cIndex=c; map(i).name=char(parameter.name(i));
    map(i).scheduled=logical(parameter.scheduled(i));
    map(i).axisName=char(parameter.axis_name(i));
    if ~map(i).scheduled
        map(i).basis=1; map(i).support=1; map(i).activeNode=true;
        rows{i}=table(c,string(map(i).name),1,NaN,1,1,true, ...
            'VariableNames',{'c_index','parameter','node_index','x_node', ...
            'maximum_basis_support','update_basis','active'});
        continue;
    end
    entryIndex=find([schedule.healthEntries.cIndex]==c,1);
    if isempty(entryIndex)
        error('SHT:F33V2:MissingScheduleEntry','调度中缺少h%d。',c);
    end
    entry=schedule.healthEntries(entryIndex);
    query=base.steadyAxis.(map(i).axisName);
    if strcmp(options.dataMethod,'steady_plus_small_history')
        historyQuery=base.historyAxis.(map(i).axisName);
        query=[query(:);historyQuery(historyData.fitMask)]; %#ok<AGROW>
    end
    coverage=sht_f33_schedule_parameterization('coverage', ...
        entry.xNodes,query,options.minimumNodeSupport,entry.pressureLoss);
    support=coverage.support;basis=coverage.basis;active=coverage.activeNode;
    if ~any(active)
        fprintf('  h%d无可释放节点，整条曲线保持先验，不中止其他系数辨识。\n',c);
    end
    map(i).entryIndex=entryIndex; map(i).basis=basis;
    map(i).support=support; map(i).activeNode=active;
    rows{i}=table(repmat(c,numel(basis),1), ...
        repmat(string(map(i).name),numel(basis),1),(1:numel(basis)).', ...
        entry.xNodes(:),support,basis,active, ...
        'VariableNames',{'c_index','parameter','node_index','x_node', ...
        'maximum_basis_support','update_basis','active'});
end
tableValue=vertcat(rows{:});
% historyMeta是显式合同输入；该检查可及早发现拼接索引错误。
if strcmp(options.dataMethod,'steady_plus_small_history') && ...
        historyMeta.segments(end).rowIndices(end)~=height(historyData.table)
    error('SHT:F33V2:HistoryIndex','小幅历程拼接索引不完整。');
end
if height(steadyData)<1,error('SHT:F33V2:SteadyEvidence','稳态证据为空。');end
end

function [map,tableValue] = local_build_fuel_map( ...
        schedule,steadyData,historyData,options)
required={'xNodes','biasNodes','wfDesign'};
if ~isfield(schedule,'fuelBias') || ...
        ~all(isfield(schedule.fuelBias,required))
    error('SHT:F33V2:FuelSchedule','先验缺少Wf_bias节点合同。');
end
fuel=schedule.fuelBias;
query=steadyData.Wf_mean/fuel.wfDesign;
if strcmp(options.dataMethod,'steady_plus_small_history')
    query=[query(:);historyData.table.Wf(historyData.fitMask)/fuel.wfDesign];
end
coverage=sht_f33_schedule_parameterization('coverage', ...
    fuel.xNodes,query,options.minimumNodeSupport,false);
support=coverage.support;basis=coverage.basis;active=coverage.activeNode;
if ~any(active)
    fprintf('  燃油偏置无可释放节点，保持零先验。\n');
end
map=struct('axisName','measured_wf_ratio', ...
    'xNodes',fuel.xNodes(:),'support',support,'activeNode',active,'basis',basis);
node_index=(1:numel(fuel.xNodes)).';
x_node=fuel.xNodes(:);
maximum_basis_support=support;
tableValue=table(node_index,x_node,maximum_basis_support,basis,active, ...
    'VariableNames',{'node_index','x_node','maximum_basis_support','update_basis','active'});
end

function contract = local_complete_parameter_contract( ...
        schedule, parameter, map, fuelMap, options)
contract=sht_f33_schedule_parameterization('build',schedule,parameter,map,fuelMap,options);
end

function [schedule,kdist,wfBiasAtDesign] = local_theta_to_model(theta,context)
theta=theta(:);
schedule=context.priorSchedule;
if isempty(context.familyMap)
    % 覆盖分析只运行零更新先验，末两位仅是K_dist_eq与Wf偏置占位。
    kdist=theta(end-1);
    if ~isfield(context.options,'assessmentModelReference')||~context.options.assessmentModelReference
        schedule.fuelBias.biasNodes=zeros(size(schedule.fuelBias.biasNodes));
    end
    wfBiasAtDesign=0;
    schedule.designHealth=local_schedule_design_health(schedule);
    return;
end
[schedule,kdist,wfBiasAtDesign]=sht_f33_schedule_parameterization('apply',theta,context);
schedule.designHealth=local_schedule_design_health(schedule);
end

function [thetaSet,signedStep] = local_difference_set(theta,contract)
n=numel(theta); thetaSet=repmat(theta,1,n+1); signedStep=zeros(n,1);
for i=1:n
    step=contract.difference_step(i);
    if theta(i)+step<=contract.upper_bound(i)
        signedStep(i)=step;
    elseif theta(i)-step>=contract.lower_bound(i)
        signedStep(i)=-step;
    else
        error('SHT:F33V2:DifferenceStep','参数%s无可用差分步。', ...
            contract.parameter_id(i));
    end
    thetaSet(i,i+1)=theta(i)+signedStep(i);
end
end

function [residual,jacobian] = local_residual_and_jacobian(evaluation,step)
residual=evaluation.candidate(1).residualVector;
jacobian=zeros(numel(residual),numel(step));
for i=1:numel(step)
    value=evaluation.candidate(i+1).residualVector;
    if numel(value)~=numel(residual)
        error('SHT:F33V2:ResidualLength','候选残差长度不一致。');
    end
    jacobian(:,i)=(value-residual)/step(i);
end
end

function [r,J,e,work]=local_linearize(context,theta,method)
% 近似只作用于小幅段导数；平均点及正式候选目标仍重新求完整热平衡。
t=tic;count=local_profile_dll_count();[set,step]=local_difference_set(theta,context.parameterContract);
c=context;c.comparisonCapturePreparation=context.options.modelMode==0 && ...
    strcmp(context.options.dataMethod,'steady_plus_small_history') && ...
    (~isempty(context.options.comparisonCacheDirectory) || strcmp(method,'reuse_per_iteration'));
c.comparisonReusePreparation=strcmp(method,'reuse_per_iteration');
e=local_evaluate_theta_set(c,set);local_require_valid_evaluation(e,'Jacobian真实候选回放');
[r,J]=local_residual_and_jacobian(e,step);
work=struct('wall_s',toc(t),'dllCalls',local_profile_dll_count()-count,'method',method, ...
    'differenceStep',step,'historyCacheFiles',{local_history_cache_files(e)});
end

function count=local_profile_dll_count()
% 对比入口显式开启基础MATLAB profiler，按实际包装调用计数，包含缓存未命中
% 的热初始化/参考矩阵建立，不把已缓存记录中的历史计数再累计。
status=profile('status');
if ~strcmp(status.ProfilerStatus,'on'),count=NaN;return;end
% R2019b的profile('info')会停止采集，读计数后必须resume而不是on/clear。
p=profile('info');profile resume;f=p.FunctionTable;count=0;
for k=1:numel(f)
    if strcmp(f(k).FunctionName,'sht_engine_derivative'),count=count+f(k).NumCalls;end
end
end

function files=local_history_cache_files(evaluation)
% 记录实际引用的回放身份，供计数审计使用，不参与参数求解或物理计算。
files={};
if ~isfield(evaluation,'historyBatch')||isempty(evaluation.historyBatch),return;end
c=evaluation.historyBatch.candidate;
for i=1:numel(c)
    for j=1:numel(c(i).segmentReplays)
        if ~isempty(c(i).segmentReplays{j})
            files{end+1,1}=c(i).segmentReplays{j}.cacheFile; %#ok<AGROW>
        end
    end
end
files=unique(files,'stable');
end

function [thetaSet,lambdaSet,gcvTable,recommended] = ...
        local_linearized_proposals(theta,residual,jacobian,contract,options)
lambdaSet=options.regularizationWeight* ...
    options.proposalRegularizationMultipliers(:);
thetaSet=zeros(numel(theta),numel(lambdaSet));
for i=1:numel(lambdaSet)
    delta=local_tikhonov_delta(theta,residual,jacobian, ...
        contract.prior_sigma,lambdaSet(i));
    thetaSet(:,i)=local_clip_theta(theta+delta,contract);
end
[gcvTable,recommended]=local_gcv(residual,jacobian,theta,contract,options);
end

function delta = local_tikhonov_delta(theta,r,J,sigma,lambda)
scaledJ=J.*sigma(:).';
priorResidual=theta(:)./sigma(:);
A=[scaledJ;sqrt(lambda)*eye(numel(theta))];
b=[r;sqrt(lambda)*priorResidual];
delta=sigma(:).*(-(A\b));
end

function theta = local_clip_theta(theta,contract)
theta=min(max(theta(:),contract.lower_bound),contract.upper_bound);
end

function [tableValue,recommended] = local_gcv(r,J,theta,contract,options)
lambda=options.gcvCandidateWeights(:); score=nan(size(lambda));
scaledJ=J.*contract.prior_sigma(:).'; m=numel(r); n=size(J,2);
information=scaledJ.'*scaledJ;
for i=1:numel(lambda)
    delta=local_tikhonov_delta(theta,r,J,contract.prior_sigma,lambda(i));
    fitted=r+J*delta;
    % 利用trace(AB)=trace(BA)在参数空间计算有效自由度，避免构造
    % “残差样本数 x 残差样本数”的巨大帽子矩阵。
    effectiveTrace=trace((information+lambda(i)*eye(n))\information);
    score(i)=sum(fitted.^2)/max((m-effectiveTrace)^2,eps);
end
[~,row]=min(score); recommended=lambda(row);
tableValue=table(lambda,score);
end

function [index,objective,dataCost,priorCost] = local_select_candidate( ...
        evaluation,thetaSet,contract,lambda)
n=numel(evaluation.candidate); dataCost=zeros(n,1); priorCost=zeros(n,1);
objective=zeros(n,1);
for i=1:n
    dataCost(i)=evaluation.candidate(i).blockMetrics.combinedDataCost;
    priorCost(i)=0.5*lambda*sum((thetaSet(:,i)./contract.prior_sigma).^2);
    objective(i)=dataCost(i)+priorCost(i);
    if ~evaluation.candidate(i).valid||~isfinite(objective(i)),objective(i)=Inf;end
end
[~,index]=min(objective);
end

function value = local_objective(evaluation,theta,contract,lambda)
value=evaluation.candidate(1).blockMetrics.combinedDataCost+ ...
    0.5*lambda*sum((theta(:)./contract.prior_sigma).^2);
end

function subset = local_evaluation_subset(evaluation,index)
subset=evaluation;
subset.candidate=evaluation.candidate(index);
if ~isempty(evaluation.steadyBatch)
    subset.steadyBatch.candidate=evaluation.steadyBatch.candidate(index);
end
if ~isempty(evaluation.historyBatch)
    subset.historyBatch.candidate=evaluation.historyBatch.candidate(index);
end
end

function value = local_selected_lambda(index,lambda)
if index==1,value=NaN;else,value=lambda(index-1);end
end

function value = local_condition_number(J)
singularValue=svd(J,0);
if isempty(singularValue)||singularValue(end)<=eps(singularValue(1))
    value=Inf;
else
    value=singularValue(1)/singularValue(end);
end
end

function item = local_empty_iteration()
item=struct('index',0,'previousObjective',NaN,'selectedObjective',NaN, ...
    'selectedDataCost',NaN,'selectedPriorCost',NaN, ...
    'selectedProposalIndex',NaN,'selectedProposalLambda',NaN, ...
    'gcvRecommendedLambda',NaN,'maximumScaledStep',NaN, ...
    'relativeImprovement',NaN,'jacobianCondition',NaN,'gcvTable',table());
end

function tableValue = local_parameter_result_table(contract,theta)
tableValue=contract(:,{'parameter_id','name','kind','c_index','unit', ...
    'node_index','axis_name','x_node','prior_center','prior_sigma', ...
    'lower_bound','upper_bound'});
tableValue.estimate=theta(:);
tableValue.update_from_prior=theta(:)-contract.prior_center;
tableValue.standardized_update=tableValue.update_from_prior./contract.prior_sigma;
end

function tableValue = local_metric_table(priorEvaluation,finalEvaluation,context)
rows={}; cursor=0;
for modelName={'prior','estimated'}
    if strcmp(modelName{1},'prior')
        candidate=priorEvaluation.candidate;
    else
        candidate=finalEvaluation.candidate;
    end
    [rows,cursor]=local_append_metric_rows(rows,cursor,modelName{1}, ...
        'steady_windows',candidate.steadyRaw, ...
        context.weighting.steadyNames,context.weighting.steadyUnits, ...
        context.weighting.steadySigma);
    if strcmp(context.options.dataMethod,'steady_plus_small_history')
        raw=candidate.historyRaw(context.historyData.fitMask,:);
        [rows,cursor]=local_append_metric_rows(rows,cursor,modelName{1}, ...
            'small_change_history',raw,context.weighting.historyNames, ...
            context.weighting.historyUnits,context.weighting.historySigma);
    end
end
tableValue=vertcat(rows{:});
end

function [rows,cursor] = local_append_metric_rows(rows,cursor,model,block, ...
        raw,names,units,scale)
for i=1:size(raw,2)
    cursor=cursor+1; e=raw(:,i);
    rows{cursor,1}=table(string(model),string(block),names(i),units(i), ...
        numel(e),sqrt(mean(e.^2)),mean(abs(e)),max(abs(e)), ...
        sqrt(mean((e/scale(i)).^2)), ...
        'VariableNames',{'model','block','channel','unit','sample_count', ...
        'rmse','mae','maximum_absolute_error','normalized_rmse'}); %#ok<AGROW>
end
end

function tableValue = local_iteration_table(iteration)
n=numel(iteration); index=zeros(n,1); previous_objective=zeros(n,1);
selected_objective=zeros(n,1); selected_data_cost=zeros(n,1);
selected_prior_cost=zeros(n,1); selected_proposal_index=zeros(n,1);
selected_proposal_lambda=zeros(n,1); gcv_recommended_lambda=zeros(n,1);
maximum_scaled_step=zeros(n,1); relative_improvement=zeros(n,1);
jacobian_condition=zeros(n,1);
for i=1:n
    x=iteration(i); index(i)=x.index; previous_objective(i)=x.previousObjective;
    selected_objective(i)=x.selectedObjective; selected_data_cost(i)=x.selectedDataCost;
    selected_prior_cost(i)=x.selectedPriorCost;
    selected_proposal_index(i)=x.selectedProposalIndex;
    selected_proposal_lambda(i)=x.selectedProposalLambda;
    gcv_recommended_lambda(i)=x.gcvRecommendedLambda;
    maximum_scaled_step(i)=x.maximumScaledStep;
    relative_improvement(i)=x.relativeImprovement;
    jacobian_condition(i)=x.jacobianCondition;
end
tableValue=table(index,previous_objective,selected_objective, ...
    selected_data_cost,selected_prior_cost,selected_proposal_index, ...
    selected_proposal_lambda,gcv_recommended_lambda,maximum_scaled_step, ...
    relative_improvement,jacobian_condition);
end

function unchanged = local_uncovered_nodes_unchanged(prior,final,map,fuelMap)
unchanged=true;
for i=1:numel(map)
    if ~map(i).scheduled,continue;end
    p=prior.healthEntries(map(i).entryIndex);
    f=final.healthEntries(map(i).entryIndex);
    inactive=~map(i).activeNode;
    unchanged=unchanged&&all(abs(p.kNodes(inactive)-f.kNodes(inactive))<=1e-14);
end
inactiveFuel=~fuelMap.activeNode;
unchanged=unchanged && all(abs( ...
    prior.fuelBias.biasNodes(inactiveFuel)- ...
    final.fuelBias.biasNodes(inactiveFuel))<=1e-14);
end

function output = local_output_paths(paths,options)
tag=sprintf('%s_%s_%s',options.modelRoute,options.dataMethod,options.parameterSet);
if ~isempty(options.resultTag),tag=[tag,'_',options.resultTag];end
output=struct();
output.matFile=fullfile(paths.middleDir, ...
    ['flight_model_adapt_3p3_',tag,'_latest.mat']);
output.workbook=fullfile(paths.deliveryDir, ...
    ['flight_model_adapt_3p3_',tag,'.xlsx']);
if options.modelMode==0
    output.formalWorkbook=fullfile(paths.deliveryDir,['flight_model_adapt_3p3_',tag,'_formal.xlsx']);
end
output.summaryMarkdown=fullfile(paths.reportDir, ...
    ['F33_',tag,'_summary.md']);
output.figureFiles={};
if strcmp(options.outputNaming,'compact')
    output.matFile=fullfile(paths.middleDir,'result.mat');
    output.workbook=fullfile(paths.deliveryDir,'results.xlsx');
    if options.modelMode==0,output.formalWorkbook=fullfile(paths.deliveryDir,'model.xlsx');end
    output.summaryMarkdown=fullfile(paths.reportDir,'summary.md');
end
end

function local_save_result(result)
fileName=result.output.matFile;
temporary=[tempname(fileparts(fileName)),'.mat'];
save(temporary,'result','-v7.3');
[moved,message]=movefile(temporary,fileName,'f');
if ~moved
    if isfile(temporary),delete(temporary);end
    error('SHT:F33V2:Save','结果保存失败：%s。',message);
end
end

function local_write_workbook(result)
fileName=result.output.workbook;
if isfile(fileName),delete(fileName);end
routeId=local_result_route_id(result);
summary=table(string(result.schemaVersion),string(routeId), ...
    string(result.modelRoute), ...
    string(result.dataMethod),string(result.parameterSet), ...
    string(result.prior.source),string(result.prior.route), ...
    result.training.steadyWindowCount,result.training.smallChangeSegmentCount, ...
    result.priorObjective,result.finalObjective,result.converged, ...
    string(result.stopReason),result.runtime_s, ...
    'VariableNames',{'schema_version','route_id','model_route','data_method', ...
    'parameter_set','prior_source','prior_route','steady_window_count', ...
    'small_change_segment_count','prior_objective','final_objective', ...
    'converged','stop_reason','runtime_s'});
summary.forward_physics_schema=string(result.forwardPhysicsContract.schemaVersion);
summary.exhaust_backpressure_enabled=true;
summary.reynolds_effect_scale=result.forwardPhysicsContract.reynoldsCorrection.effectScale;
summary.enhanced_transient_effects_enabled=result.enhancedTransientEffectsEnabledDuringIdentification;
summary.steady_thermal_mode=string(result.options.steadyThermalMode);
if isfield(result.options,'smallHistoryThermalMode')
    summary.small_history_thermal_mode=string(result.options.smallHistoryThermalMode);
end
summary.individual_transient_coefficients_zero=result.visserCorrectionCoefficientsZero;
if isfield(result,'exportProvenance')
    summary.numerical_source_result_sha256=string(result.exportProvenance.sourceResultSHA256);
    summary.metadata_definition_basis=string(result.exportProvenance.definitionBasis);
    summary.solver_repeated_for_export=false;
end
summary.inlet_boundary_mode=5;
summary.K_dist_eq=result.estimatedKdistEq;
if isfield(result,'scheduleParameterization')
    summary.schedule_parameterization=string(result.scheduleParameterization);
    summary.regularization_geometry=string(result.regularizationGeometry);
end
writetable(summary,fileName,'Sheet','summary');
writetable(result.parameterTable,fileName,'Sheet','parameters');
writetable(result.coverageTable,fileName,'Sheet','node_coverage');
writetable(result.fuelBiasCoverageTable,fileName,'Sheet','wf_bias_coverage');
writetable(result.metricTable,fileName,'Sheet','fit_metrics');
writetable(result.iterationTable,fileName,'Sheet','iterations');
% 紧凑更新量不能单独重建模型，交付完整有效系数和燃油曲线。
profile=local_build_schedule_profile(result.finalSchedule);nodes=table();
for j=1:numel(profile.parameters)
    p=profile.parameters(j);n=numel(p.xNodes);
    nodes=[nodes;table(repmat(p.cIndex,n,1),repmat(string(p.name),n,1), ...
        repmat(string(p.axisName),n,1),p.xNodes(:),p.kNodes(:), ...
        repmat(p.designValue,n,1),'VariableNames', ...
        {'c_index','name','axis_name','x','k_effective','k_design'})]; %#ok<AGROW>
end
writetable(nodes,fileName,'Sheet','health_schedule');
writetable(table((0:158).',result.finalSchedule.designHealth(:), ...
    'VariableNames',{'c_index','k_design'}),fileName,'Sheet','health_design');
fuel=result.finalSchedule.fuelBias;
writetable(table(fuel.xNodes(:),fuel.biasNodes(:), ...
    repmat(fuel.wfDesign,numel(fuel.xNodes),1),'VariableNames', ...
    {'measured_wf_over_design','bias_kgps','wf_design_kgps'}),fileName,'Sheet','fuel_bias');
if isfield(result.output,'formalWorkbook')
    % 稳态载体保持原schema；真实物理结果保留固定13，以组合Excel单独绑定。
    carrier=result;
    if result.options.modelMode==0,carrier.finalSchedule.designHealth(59:71)=0;end
    sht_f33_excel_delivery('write',carrier,result.output.formalWorkbook);
    if isfield(result.finalSchedule,'fixedTransient')&& ...
            any(result.finalSchedule.fixedTransient.value~=0)
        f=result.finalSchedule.fixedTransient;
        params=table(f.cIndex,string(f.name(:)),'VariableNames',{'c_index','name'});
        r=struct('parameters',params,'k',f.value,'converged',result.converged, ...
            'stopReason',result.stopReason,'options',result.options);
        r.options.steadyWorkbook=result.output.formalWorkbook;
        r.options.runTag=result.options.resultTag;
        r.identity=struct('steadySha256',sht_tc27_file_identity(result.output.formalWorkbook), ...
            'fixedTransient',f);
        r.identityHash=local_struct_hash(r.identity);
        sht_f33_transient_delivery('write',r, ...
            fullfile(fileparts(result.output.formalWorkbook),'combined_model.xlsx'));
    end
end
end

function local_write_summary(result)
fid=fopen(result.output.summaryMarkdown,'w','n','UTF-8');
if fid<0,error('SHT:F33V2:Summary','无法写入结果摘要。');end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'# 3.3飞参稳态修正系数辨识结果\n\n');
fprintf(fid,'- 辨识路线：`%s`\n',local_result_route_id(result));
fprintf(fid,'- 模型路径：`%s`\n',result.modelRoute);
fprintf(fid,'- 数据方法：`%s`\n',result.dataMethod);
fprintf(fid,'- 参数组合：`%s`\n',result.parameterSet);
if isfield(result,'scheduleParameterization')
    fprintf(fid,'- 全曲线统一释放方式：`%s`；正则化为实际节点改变量平方和。\n',result.scheduleParameterization);
end
fprintf(fid,'- 先验来源：`%s/%s`\n',result.prior.source,result.prior.route);
fprintf(fid,'- 前向物理合同：`%s`\n',result.forwardPhysicsContract.schemaVersion);
fprintf(fid,'- 排气背压：由当前候选模型转速、可测负载扭矩和环境静压计算，不输入背压窗口均值。\n');
fprintf(fid,'- 雷诺数修正：开启；稳态热处理：%s；活动字典瞬态个体修正是否全零：%d。\n', ...
    result.options.steadyThermalMode,result.visserCorrectionCoefficientsZero);
if isfield(result,'exportProvenance')
    fprintf(fid,'- 本次仅补交付元数据，未重新求解；原数值结果SHA256：`%s`。\n',result.exportProvenance.sourceResultSHA256);
    fprintf(fid,'- 补充定义依据：%s。原参数、预测和停止状态不因补导出而改变。\n',result.exportProvenance.definitionBasis);
end
if isfield(result.options,'smallHistoryThermalMode')
    fprintf(fid,'- 小幅历程热处理：`%s`；纯稳态数据方式下不参与拟合。\n',result.options.smallHistoryThermalMode);
end
fprintf(fid,'- 稳态窗口：%d个\n',result.training.steadyWindowCount);
fprintf(fid,'- 小幅变化段：%d段\n',result.training.smallChangeSegmentCount);
fprintf(fid,'- 正式目标：%.8g -> %.8g\n',result.priorObjective,result.finalObjective);
fprintf(fid,'- 收敛：%d，停止原因：`%s`\n',result.converged,result.stopReason);
fprintf(fid,'- 运行时间：%.1f s\n\n',result.runtime_s);
fprintf(fid,'## 参数结果\n\n');
fprintf(fid,'|参数|单位|先验中心|估计值|先验标准差|\n');
fprintf(fid,'|---|---:|---:|---:|---:|\n');
for i=1:height(result.parameterTable)
    x=result.parameterTable(i,:);
    fprintf(fid,'|%s|%s|%.8g|%.8g|%.8g|\n',x.parameter_id,x.unit, ...
        x.prior_center,x.estimate,x.prior_sigma);
end
clear cleanup;
end

function routeId=local_result_route_id(result)
% 兼容2026-09-06之前未显式保存routeId的3.3结果。
if isfield(result,'routeId') && ~isempty(result.routeId)
    routeId=char(string(result.routeId));
else
    route=sht_f33_route_definition(result.modelRoute,result.dataMethod);
    routeId=route.routeId;
end
end

function files = local_plot_result(result,paths)
tag=sprintf('%s_%s_%s',result.modelRoute,result.dataMethod,result.parameterSet);
if isfield(result.options,'resultTag')&&~isempty(result.options.resultTag)
    tag=[tag,'_',result.options.resultTag];
end
files=cell(2,1);
files{1}=fullfile(paths.reportDir,['F33_',tag,'_parameter_updates.png']);
figure('Visible',result.options.figureVisible,'Color','w','Position',[100,100,1200,520]);
x=1:height(result.parameterTable);
bar(x,result.parameterTable.standardized_update);hold on;yline(0,'k--');grid on;
set(gca,'XTick',x,'XTickLabel',cellstr(result.parameterTable.parameter_id), ...
    'XTickLabelRotation',35,'TickLabelInterpreter','none');
ylabel('更新量 / 正则化尺度（无量纲，非可信区间）'); title(sprintf('3.3 %s / %s 参数更新', ...
    result.modelRoute,result.dataMethod),'Interpreter','none');
print(gcf,files{1},'-dpng','-r180');close(gcf);
files{2}=fullfile(paths.reportDir,['F33_',tag,'_fit_metrics.png']);
figure('Visible',result.options.figureVisible,'Color','w','Position',[100,100,1200,560]);
tbl=result.metricTable; labels=unique(tbl.block+":"+tbl.channel,'stable');
prior=zeros(numel(labels),1);estimated=prior;
for i=1:numel(labels)
    mask=(tbl.block+":"+tbl.channel)==labels(i);
    prior(i)=tbl.normalized_rmse(mask&tbl.model=="prior");
    estimated(i)=tbl.normalized_rmse(mask&tbl.model=="estimated");
end
bar([prior,estimated]);grid on;legend('先验','3.3估计','Location','best');
set(gca,'XTick',1:numel(labels),'XTickLabel',cellstr(labels), ...
    'XTickLabelRotation',30,'TickLabelInterpreter','none');ylabel('工程尺度归一化RMSE');
title(sprintf('3.3 %s / %s 拟合误差',result.modelRoute,result.dataMethod), ...
    'Interpreter','none');
print(gcf,files{2},'-dpng','-r180');close(gcf);
end

function local_print_result(result)
fprintf('\n3.3路线完成：%s / %s / %s\n', ...
    result.modelRoute,result.dataMethod,result.parameterSet);
fprintf('  正式目标：%.8g -> %.8g；运行 %.1f s。\n', ...
    result.priorObjective,result.finalObjective,result.runtime_s);
fprintf('  收敛：%d（%s）；未覆盖节点保持先验：%d。\n', ...
    result.converged,result.stopReason,result.uncoveredNodesExactlyPrior);
disp(result.parameterTable(:,{'parameter_id','unit','prior_center', ...
    'estimate','standardized_update'}));
disp(result.metricTable);
end

function entry = local_refresh_entry(entry)
[entry.xNodes,order]=sort(entry.xNodes(:)); entry.kNodes=entry.kNodes(order);
if numel(entry.xNodes)>1&&any(diff(entry.xNodes)<=0)
    error('SHT:F33V2:NodeOrder','h%d节点横坐标不严格递增。',entry.cIndex);
end
entry.designValue=local_interp_clamp( ...
    entry.xNodes,entry.kNodes,entry.designCoordinate);
entry.xNodesDll=entry.xNodes; entry.kNodesDll=entry.kNodes;
entry.deltaNodesDll=entry.kNodes-entry.designValue;
end

function zero=local_transient_coefficients_zero(schedule,modelMode)
% 三部件h58:70、六部件h89:111分别检查，不能把另一模式的保留位当活动系数。
assert(isnumeric(modelMode)&&isscalar(modelMode)&&ismember(modelMode,[0,1]), ...
    'SHT:F33V2:TransientDictionary','必须明确三部件或六部件模型身份。');
h=schedule.designHealth;
assert(isnumeric(h)&&isreal(h)&&numel(h)==159&&all(isfinite(h(:))), ...
    'SHT:F33V2:TransientDictionary','瞬态标记须依据完整有限159维修正向量。');
if modelMode==0,indices=59:71;else,indices=90:112;end
zero=all(h(indices)==0);
end

function health = local_schedule_design_health(schedule)
health=zeros(159,1);
for i=1:numel(schedule.healthEntries)
    c=schedule.healthEntries(i).cIndex;
    if c+1<=numel(health),health(c+1)=schedule.healthEntries(i).designValue;end
end
health(16)=schedule.h15; health(90:112)=0;
if isfield(schedule,'modelMode')&&schedule.modelMode==0&&isfield(schedule,'fixedTransient')
    f=schedule.fixedTransient;
    checked=sht_f3_current_contract('fixedTransient',schedule.designHealth,f.sourceSha256);
    assert(isequal(checked.value,f.value),'SHT:F33V2:FixedTransientChanged', ...
        '曲线重建不得改变组合父的固定瞬态条件。');
    health(59:71)=f.value;
end
end

function value = local_interp_clamp(x,y,q)
x=x(:);y=y(:);q=min(max(q,x(1)),x(end));
if numel(x)==1,value=repmat(y(1),size(q));else,value=interp1(x,y,q,'linear');end
end

function profile = local_build_schedule_profile(schedule)
if isfield(schedule,'modelMode')&&schedule.modelMode==0
    profile=sht_tc27_schedule_profile(schedule);return;
end
schedule=local_prepare_prior_schedule(schedule);
cIndex=[0:3,6:14,71:88].';
axisName=[repmat({'ac_corrected_speed'},4,1); ...
    {'burner_inlet_corrected_mass_flow'};repmat({'gt_total_pressure_ratio'},3,1); ...
    {'gt_pt_duct_corrected_mass_flow'};repmat({'pt_total_pressure_ratio'},3,1); ...
    {'pt_nozzle_duct_corrected_mass_flow'};repmat({'ac_corrected_speed'},3,1); ...
    repmat({'cc_corrected_speed'},3,1);repmat({'gt_total_pressure_ratio'},6,1); ...
    repmat({'pt_total_pressure_ratio'},6,1)];
axisName{1}='inlet_corrected_mass_flow';
zeroAxes={'inlet_corrected_mass_flow','burner_inlet_corrected_mass_flow', ...
    'gt_pt_duct_corrected_mass_flow','pt_nozzle_duct_corrected_mass_flow'};
dictionary=sht_health_parameter_dictionary(1);
entryC=[schedule.healthEntries.cIndex];
template=struct('cIndex',0,'matlabHealthIndex',0,'name','', ...
    'mode','table1d','axisName','','xNodes',[],'deltaNodes',[], ...
    'designValue',0,'kNodes',[],'zeroFlowAnchored',false,'activeTruth',false);
parameters=repmat(template,numel(cIndex),1);
for i=1:numel(cIndex)
    c=cIndex(i);row=find(dictionary.c_index==c,1);
    parameters(i).cIndex=c;parameters(i).matlabHealthIndex=c+1;
    parameters(i).name=char(dictionary.name(row));parameters(i).axisName=axisName{i};
    parameters(i).designValue=schedule.designHealth(c+1);
    parameters(i).zeroFlowAnchored=any(strcmp(axisName{i},zeroAxes));
    found=find(entryC==c,1);
    if ~isempty(found)
        entry=schedule.healthEntries(found);parameters(i).xNodes=entry.xNodesDll(:);
        parameters(i).deltaNodes=entry.deltaNodesDll(:);
        parameters(i).designValue=entry.designValue;
    elseif parameters(i).zeroFlowAnchored
        parameters(i).xNodes=[0;1e6];parameters(i).deltaNodes=[-parameters(i).designValue;0];
    elseif contains(axisName{i},'corrected_speed')
        parameters(i).xNodes=[0;2];parameters(i).deltaNodes=[0;0];
    else
        parameters(i).xNodes=[0;100];parameters(i).deltaNodes=[0;0];
    end
    parameters(i).kNodes=parameters(i).designValue+parameters(i).deltaNodes;
    parameters(i).activeTruth=abs(parameters(i).designValue)>0|| ...
        any(abs(parameters(i).deltaNodes)>0);
end
profile=struct('schemaVersion','SHT_F33_ESTIMATED_SCHEDULE_PROFILE_V2', ...
    'modelMode',1,'createdAt',datestr(now,31),'interpolation','piecewise_linear', ...
    'extrapolation','nearest_endpoint_clamp', ...
    'parameterLaw','K_eff(x)=k_design+Delta(x)', ...
    'parameters',parameters,'scheduledCIndex',cIndex, ...
    'truthVectorAtDesign',schedule.designHealth(:), ...
    'source','3.3 estimated schedule; no hidden truth template');
end

function value = local_merge_struct(base,override)
value=base; names=fieldnames(override);
for i=1:numel(names),value.(names{i})=override.(names{i});end
end

function hash = local_file_hash(fileName)
if ~isfile(fileName),error('SHT:F33V2:HashFile','文件不存在：%s。',fileName);end
hash=sht_transient_model_adapt_common('fileHash',fileName);
end

function hash = local_struct_hash(value)
bytes=unicode2native(jsonencode(value),'UTF-8');
digest=java.security.MessageDigest.getInstance('SHA-256');
digest.update(typecast(uint8(bytes),'int8'));
raw=typecast(digest.digest(),'uint8');
hash=lower(reshape(dec2hex(raw,2).',1,[]));
end
