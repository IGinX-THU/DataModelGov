function result=Run_TC27_SteadyUpdate_Offline(configFile)
%RUN_TC27_STEADYUPDATE_OFFLINE 无界面的独立运行入口。
% 用法：Run_TC27_SteadyUpdate_Offline('我的任务配置.mat')。
% MAT内只须有request结构体；亦可传入保存该结构体的JSON文件。
% 业务输入可为绝对路径；相对路径相对于配置文件所在目录解析。
assert(nargin==1&&~isempty(configFile),'TC27:Offline:Config', ...
    '请提供存在的配置文件（MAT或JSON）。');
% Java启动目录不随MATLAB cd改变，配置文件自身先按当前pwd绝对化。
configFile=local_path(configFile,pwd,false);
assert(isfile(configFile),'TC27:Offline:Config','配置文件不存在：%s',configFile);
configDirectory=fileparts(configFile);
[~,~,ext]=fileparts(configFile);
if strcmpi(ext,'.mat')
    loaded=load(configFile,'request');
    assert(isfield(loaded,'request'),'TC27:Offline:Request', ...
        '配置MAT中缺少request结构体。');
    request=loaded.request;
elseif strcmpi(ext,'.json')
    fid=fopen(configFile,'rb');
    assert(fid>0,'TC27:Offline:Read','不能读取配置JSON。');
    clean=onCleanup(@()fclose(fid));bytes=fread(fid,Inf,'*uint8').';
    request=jsondecode(native2unicode(bytes,'UTF-8'));clear clean;
else
    error('TC27:Offline:Type','仅接受MAT或JSON配置。');
end
assert(isstruct(request)&&isscalar(request),'TC27:Offline:Request', ...
    '配置根对象必须为单个request结构体。');
for field={'upstreamModelFile','steadyTrainingFile','trainingHistoryFile', ...
        'outputDirectory','modelFile','identityFile','conditions','timingHistoryDirectory', ...
        'runtimeDirectory','sourceRuntimeDirectory'}
    name=field{1};
    if isfield(request,name)&&(ischar(request.(name))||isstring(request.(name)))
        request.(name)=local_path(request.(name),configDirectory, ...
            ismember(name,{'runtimeDirectory','sourceRuntimeDirectory'}));
    end
end
for field={'testPointFiles','testHistoryFiles'}
    name=field{1};
    if ~isfield(request,name)||isempty(request.(name)),continue;end
    files=request.(name);
    if ischar(files),files={files};elseif isstring(files),files=cellstr(files(:));end
    assert(iscell(files),'TC27:Offline:Tests','测试文件应为路径数组。');
    for j=1:numel(files),files{j}=local_path(files{j},configDirectory);end
    request.(name)=files;
end
addpath(fileparts(mfilename('fullpath')));
operation='update';if isfield(request,'operation'),operation=char(string(request.operation));end
switch operation
    case 'update',result=Start_TC27_SteadyModelUpdate_01(request);
    case 'preview'
        request.preview=true;request.execute=false;request.resume=false;
        result=Start_TC27_SteadyModelUpdate_01(request);
    case 'resume'
        request.execute=true;request.resume=true;request.preview=false;
        result=Start_TC27_SteadyModelUpdate_01(request);
    case 'stop'
        assert(isfield(request,'outputDirectory'),'TC27:Offline:StopDirectory', ...
            '停止请求必须指定完整任务输出目录。');
        result=Start_TC27_RequestStop_01(request.outputDirectory);
    case 'predict',result=Start_TC27_SteadyModelPredict_01(request);
    otherwise,error('TC27:Offline:Operation','operation只能为update/preview/resume/stop/predict。');
end
end

function path=local_path(path,base,allowSelection)
if nargin<3,allowSelection=false;end
assert((ischar(path)&&(isrow(path)||isempty(path)))||(isstring(path)&&isscalar(path)), ...
    'TC27:Offline:Path','文件或运行包路径必须为标量文本。');
path=char(path);
if isempty(path),return;end
% selected/legacy是既有选包指令，不是配置目录下的相对文件夹。
if allowSelection&&ismember(path,{'selected','legacy'}),return;end
assert(isempty(regexp(path,'^(?:[A-Za-z]:(?![\\/])|[\\/](?![\\/]))','once')), ...
    'TC27:Offline:AmbiguousPath','请使用完整绝对路径或相对配置目录的路径：%s',path);
if isempty(regexp(path,'^([A-Za-z]:[\\/]|[\\/]{2})','once'))
    path=fullfile(base,path);
end
path=sht_tc27_canonical_path(path);
end
