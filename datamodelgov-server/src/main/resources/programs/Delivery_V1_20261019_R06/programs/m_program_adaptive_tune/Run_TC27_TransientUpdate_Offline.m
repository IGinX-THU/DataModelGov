function result=Run_TC27_TransientUpdate_Offline(configFile)
%RUN_TC27_TRANSIENTUPDATE_OFFLINE 从独立配置文件运行同一瞬态更新核心。
% JSON配置包含steadyModelFile、trainingHistoryFile、outputDirectory，
% 可选testHistoryFiles、selectionMode、eventRanges_s、preview及execute。
assert(nargin==1&&~isempty(configFile),'TC27:TransientUI:Config', ...
    '请传入独立JSON或MAT配置文件路径。');
% 配置文件自身以MATLAB pwd为准，不能使用Java未随cd改变的启动目录。
file=local_path(configFile,pwd,false);
assert(isfile(file),'TC27:TransientUI:Config','配置文件不存在：%s',file);
[configDirectory,~,extension]=fileparts(file);
switch lower(extension)
    case '.json'
        fid=fopen(file,'rb');
        assert(fid>=0,'TC27:TransientUI:Config','无法打开UTF-8配置文件。');
        cleanup=onCleanup(@()fclose(fid));
        bytes=fread(fid,Inf,'*uint8').';request=jsondecode(native2unicode(bytes,'UTF-8'));
        % JSON单区间解码为列向量；只恢复这一个合法二维接口形状。
        if isfield(request,'eventRanges_s')&&isnumeric(request.eventRanges_s)&& ...
                isvector(request.eventRanges_s)&&numel(request.eventRanges_s)==2
            request.eventRanges_s=reshape(request.eventRanges_s,1,2);
        end
        clear cleanup;
    case '.mat'
        saved=load(file,'request');
        assert(isfield(saved,'request'),'TC27:TransientUI:Config','MAT需包含request变量。');
        request=saved.request;
    otherwise
        error('TC27:TransientUI:Config','配置只接受JSON或MAT。');
end
assert(isstruct(request)&&isscalar(request),'TC27:TransientUI:Config','配置根对象须为单个结构体。');
for field={'steadyModelFile','trainingHistoryFile','outputDirectory','runtimeDirectory'}
    name=field{1};
    if isfield(request,name)&&(ischar(request.(name))||isstring(request.(name)))
        request.(name)=local_path(request.(name),configDirectory,strcmp(name,'runtimeDirectory'));
    end
end
if isfield(request,'testHistoryFiles')
    value=request.testHistoryFiles;
    if isempty(value),request.testHistoryFiles={};
    elseif isstring(value),request.testHistoryFiles=cellstr(value(:));
    elseif ischar(value)
        request.testHistoryFiles={value};
    end
    assert(iscell(request.testHistoryFiles),'TC27:TransientUI:Config', ...
        'testHistoryFiles必须为文件路径列表。');
    for j=1:numel(request.testHistoryFiles)
        request.testHistoryFiles{j}=local_path(request.testHistoryFiles{j},configDirectory,false);
    end
end
result=Start_TC27_TransientModelUpdate_01(request);
fprintf('TC27瞬态独立入口：状态=%s，已用%.1f秒，粗估%.0f~%.0f分钟。\n', ...
    result.status,result.actualElapsed_s,result.estimatedTime.lower_s/60, ...
    result.estimatedTime.upper_s/60);
end

function path=local_path(value,base,allowSelection)
assert((ischar(value)&&(isrow(value)||isempty(value)))||(isstring(value)&&isscalar(value)), ...
    'TC27:TransientUI:Path','文件或运行包路径必须为标量文本。');
path=char(value);
if isempty(path),return;end
if allowSelection&&ismember(path,{'selected','legacy'}),return;end
assert(isempty(regexp(path,'^(?:[A-Za-z]:(?![\\/])|[\\/](?![\\/]))','once')), ...
    'TC27:TransientUI:AmbiguousPath','路径语义不明确，请给绝对或配置相对路径：%s',path);
if isempty(regexp(path,'^([A-Za-z]:[\\/]|[\\/]{2})','once'))
    path=fullfile(base,path);
end
path=sht_tc27_canonical_path(path);
end
