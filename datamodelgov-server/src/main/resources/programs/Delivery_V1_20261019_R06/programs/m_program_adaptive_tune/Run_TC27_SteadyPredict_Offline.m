function result=Run_TC27_SteadyPredict_Offline(configFile)
%RUN_TC27_STEADYPREDICT_OFFLINE 通过集中配置调用同一预测核心。
% UTF-8 JSON或含request结构的MAT；相对文件路径以配置目录为基准。
assert(nargin==1&&~isempty(configFile),'TC27:Predict:Config','请指定JSON或MAT配置。');
assert((ischar(configFile)&&isrow(configFile))||(isstring(configFile)&&isscalar(configFile)), ...
    'TC27:Predict:Config','配置文件路径必须为非空标量文本。');
file=char(configFile);
assert(isempty(regexp(file,'^(?:[A-Za-z]:(?![\\/])|[\\/](?![\\/]))','once')), ...
    'TC27:Predict:AmbiguousPath','配置路径语义不明确：%s',file);
% 配置自身相对MATLAB pwd；配置内业务路径仍相对配置目录。
if isempty(regexp(file,'^([A-Za-z]:[\\/]|[\\/]{2})','once')),file=fullfile(pwd,file);end
file=sht_tc27_canonical_path(file);
assert(isfile(file),'TC27:Predict:Config','配置文件不存在：%s',file);
[directory,~,extension]=fileparts(file);
switch lower(extension)
    case '.json'
        fid=fopen(file,'rb');assert(fid>=0,'TC27:Predict:Config','无法读取UTF-8配置。');
        cleanup=onCleanup(@()fclose(fid));bytes=fread(fid,Inf,'*uint8').';
        request=jsondecode(native2unicode(bytes,'UTF-8'));clear cleanup;
    case '.mat'
        saved=load(file,'request');assert(isfield(saved,'request'),'TC27:Predict:Config','MAT缺少request。');
        request=saved.request;
    otherwise
        error('TC27:Predict:Config','仅接受JSON或MAT配置。');
end
assert(isstruct(request)&&isscalar(request),'TC27:Predict:Config','配置根对象必须为单个结构体。');
names={'modelFile','identityFile','outputDirectory','conditions', ...
    'runtimeDirectory','sourceRuntimeDirectory'};
for j=1:numel(names)
    key=names{j};
    if isfield(request,key)&&(ischar(request.(key))||isstring(request.(key)))
        value=request.(key);
        assert((ischar(value)&&(isrow(value)||isempty(value)))||(isstring(value)&&isscalar(value)), ...
            'TC27:Predict:Config','%s必须为标量文本路径。',key);
        path=char(value);
        if isempty(path),continue;end
        % 选包字面值由现行runtime_package解释，不能拼接为文件路径。
        if ismember(key,{'runtimeDirectory','sourceRuntimeDirectory'})&& ...
                ismember(path,{'selected','legacy'})
            continue;
        end
        assert(isempty(regexp(path,'^(?:[A-Za-z]:(?![\\/])|[\\/](?![\\/]))','once')), ...
            'TC27:Predict:AmbiguousPath','路径语义不明确，请给绝对或配置相对路径：%s',path);
        absolute=~isempty(regexp(path,'^(?:[A-Za-z]:[\\/]|[\\/]{2})','once'));
        if ~absolute,path=fullfile(directory,path);end
        request.(key)=sht_tc27_canonical_path(path);
    end
end
result=Start_TC27_SteadyModelPredict_01(request);
fprintf('TC27离线预测：%s；总计%.3fs。\n',result.status,result.elapsed_s);
end
