function result=Run_TC27_UQ_Offline(configFile)
%RUN_TC27_UQ_OFFLINE 脱离GUI的UQ入口；配置文件为UTF-8 JSON。
assert(nargin==1&&~isempty(configFile),'TC27:UQ:Config','请指定UTF-8 JSON配置文件。');
% 先按MATLAB pwd定位配置自身，避免Java启动目录在cd后仍指向旧位置。
configFile=local_path(pwd,configFile);
assert(isfile(configFile),'TC27:UQ:Config','UQ配置文件不存在：%s',configFile);
[configDirectory,~,extension]=fileparts(configFile);
assert(strcmpi(extension,'.json'),'TC27:UQ:ConfigType','UQ离线入口仅接受JSON配置。');
fid=fopen(configFile,'rb');assert(fid>0,'TC27:UQ:Config','配置文件不可读。');
cleanup=onCleanup(@()fclose(fid));bytes=fread(fid,Inf,'*uint8').';
request=jsondecode(native2unicode(bytes,'UTF-8'));clear cleanup;
assert(isstruct(request)&&isscalar(request),'TC27:UQ:Config','配置根对象须为单个结构体。');
action='assess';if isfield(request,'action'),action=char(string(request.action));end
switch lower(action)
    case 'assess'
        assert(isfield(request,'options')&&isstruct(request.options), ...
            'TC27:UQ:Config','模型评估配置缺少options。');
        names={'modelFile','modelIdentityFile','upstreamModelFile', ...
            'steadyTrainingFile','trainingHistoryFile','preparedFile','outputDirectory'};
        for j=1:numel(names)
            key=names{j};
            if isfield(request.options,key)&&~isempty(request.options.(key))
                request.options.(key)=local_path(configDirectory,request.options.(key));
            end
        end
        for key={'testPointFiles','testHistoryFiles'}
            name=key{1};
            if ~isfield(request.options,name),continue;end
            paths=cellstr(string(request.options.(name)));
            for j=1:numel(paths),paths{j}=local_path(configDirectory,paths{j});end
            request.options.(name)=paths;
        end
        if isfield(request,'timingHistoryDirectory')&&~isempty(request.timingHistoryDirectory)
            request.timingHistoryDirectory=local_path(configDirectory,request.timingHistoryDirectory);
        end
        result=Start_TC27_UQ_ModelAssessment_01(request);
    case 'stop'
        result=Start_TC27_UQ_RequestStop_01(local_path(configDirectory,request.outputDirectory));
    case 'predict_new'
        names={'modelFile','identityFile','posteriorFile','outputDirectory','conditions'};
        for j=1:numel(names)
            key=names{j};
            assert(isfield(request,key),'TC27:UQ:Config','预测配置缺少%s。',key);
            request.(key)=local_path(configDirectory,request.(key));
        end
        result=Start_TC27_UQ_NewConditionPrediction_01(request);
    otherwise
        error('TC27:UQ:OfflineAction','未知操作%s。',action);
end
end

function path=local_path(root,value)
assert((ischar(value)&&isrow(value))||(isstring(value)&&isscalar(value)), ...
    'TC27:UQ:Config','路径必须为非空标量文本。');
path=char(value);
assert(~isempty(path),'TC27:UQ:Config','文件路径不能为空。');
assert(isempty(regexp(path,'^(?:[A-Za-z]:(?![\\/])|[\\/](?![\\/]))','once')), ...
    'TC27:UQ:AmbiguousPath','路径语义不明确，请给绝对或配置相对路径：%s',path);
if isempty(regexp(path,'^(?:[A-Za-z]:[\\/]|[\\/]{2})','once'))
    path=fullfile(root,path);
end
path=sht_tc27_canonical_path(path);
end
