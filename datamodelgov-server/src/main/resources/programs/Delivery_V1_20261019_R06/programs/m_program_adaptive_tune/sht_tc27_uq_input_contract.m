function input=sht_tc27_uq_input_contract(options,model,paths,identityOnly)
%SHT_TC27_UQ_INPUT_CONTRACT 从显式Excel恢复本次UQ观测，不回退内置样例。
% prepared MAT只作加速缓存；缺少时在本次独立输出目录执行现行05。
if nargin<4,identityOnly=false;end
required={'modelFile','upstreamModelFile','steadyTrainingFile', ...
    'trainingHistoryFile','outputDirectory'};
for j=1:numel(required)
    name=required{j};
    assert(isfield(options,name)&&~isempty(options.(name)), ...
        'TC27:UQ:InputMissing','UQ缺少显式输入%s。',name);
end
for j=1:4
    file=char(string(options.(required{j})));
    assert(isfile(file),'TC27:UQ:InputMissing','UQ输入文件不存在：%s',file);
end
if ~isfield(options,'testPointFiles'),options.testPointFiles={};end
if ~isfield(options,'testHistoryFiles'),options.testHistoryFiles={};end
assert(iscell(options.testPointFiles)&&iscell(options.testHistoryFiles), ...
    'TC27:UQ:TestFiles','测试文件应分别提供cell路径列表。');
for file=[options.testPointFiles(:);options.testHistoryFiles(:)].'
    assert(isfile(char(string(file{1}))),'TC27:UQ:TestMissing', ...
        '测试文件不存在：%s',char(string(file{1})));
end

sidecar=fullfile(fileparts(char(string(options.modelFile))), ...
    ['tc27_deterministic_',model.route,'_',model.method,'_identity.json']);
if isfield(options,'modelIdentityFile')&&~isempty(options.modelIdentityFile)
    sidecar=char(string(options.modelIdentityFile));
end
assert(isfile(sidecar),'TC27:UQ:ModelIdentity', ...
    '所选模型缺少身份JSON，不能将其他模型后验挂到该Excel：%s',sidecar);
identity=jsondecode(fileread(sidecar));package=sht_tc27_runtime_package(paths.runtime);
assert(strcmp(identity.schema,'TC27_MODEL_IDENTITY_V1')&& ...
    strcmpi(identity.modelSHA256,sht_tc27_file_identity(options.modelFile))&& ...
    strcmp(identity.route,model.route)&&strcmp(identity.method,model.method)&& ...
    identity.modelMode==model.modelMode&&identity.thermalMode==model.thermalMode&& ...
    strcmpi(identity.upstreamSHA256,sht_tc27_file_identity(options.upstreamModelFile))&& ...
    strcmp(identity.runtimePackageId,package.id)&& ...
    strcmpi(identity.dllSHA256,sht_tc27_file_identity(fullfile(paths.runtime,'GTESS.dll')))&& ...
    strcmpi(identity.thermalSHA256,sht_tc27_file_identity(package.thermalFile)), ...
    'TC27:UQ:ModelIdentity','模型Excel、上游模型或运行包与身份JSON不匹配。');
if identityOnly
    input=struct('modelIdentityFile',sidecar,'modelIdentity',identity);
    return;
end

preparedFile='';
explicitPrepared=isfield(options,'preparedFile')&&~isempty(options.preparedFile);
if explicitPrepared
    preparedFile=char(string(options.preparedFile));
else
    candidate=fullfile(fileparts(char(string(options.modelFile))),'tc27_prepared_data.mat');
    if isfile(candidate),preparedFile=candidate;end
end
if ~isempty(preparedFile)
    assert(isfile(preparedFile),'TC27:UQ:PreparedMissing','准备缓存不存在：%s',preparedFile);
    saved=load(preparedFile,'result');prepared=saved.result;
    sht_tc27_uq_check_prepared_data(options,prepared,'train');
    try
        sht_tc27_uq_check_prepared_data(options,prepared,'test');
    catch failure
        if explicitPrepared||~strcmp(failure.identifier,'TC27:UQ:StalePreprocessing')
            rethrow(failure);
        end
        preparedFile='';
    end
end
if isempty(preparedFile)
    prep=struct('explicitInputs',true,'upstreamModelFile',options.upstreamModelFile, ...
        'steadyTrainingFile',options.steadyTrainingFile, ...
        'trainingHistoryFile',options.trainingHistoryFile, ...
        'testPointFiles',{options.testPointFiles}, ...
        'testHistoryFiles',{options.testHistoryFiles}, ...
        'outputDirectory',options.outputDirectory,'plot',false,'resume',false);
    if isfield(options,'preparationOptions')
        names=fieldnames(options.preparationOptions);
        for j=1:numel(names),prep.(names{j})=options.preparationOptions.(names{j});end
    end
    prep.explicitInputs=true;prep.outputDirectory=options.outputDirectory;
    prep.resume=false;prep.reusePointFitFile='';
    prepared=Start_TC27_05_DataPreparation(sht_tc27_estimation_options(model.route,model.method,prep));
    preparedFile=fullfile(paths.middle,'tc27_prepared_data.mat');
    provenance='regenerated_from_raw_excel';
else
    provenance='verified_prepared_cache_and_raw_excel';
end
input=struct('prepared',prepared,'preparedFile',preparedFile, ...
    'preparedSHA256',sht_tc27_file_identity(preparedFile), ...
    'modelIdentityFile',sidecar,'modelIdentitySHA256',sht_tc27_file_identity(sidecar), ...
    'modelIdentity',identity,'provenance',provenance);
end
