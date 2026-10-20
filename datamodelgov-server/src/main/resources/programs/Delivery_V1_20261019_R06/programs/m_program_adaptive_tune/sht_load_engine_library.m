function diagnostics = sht_load_engine_library(libraryName, headerName, varargin)
%SHT_LOAD_ENGINE_LIBRARY 无解析噪声地加载GTESS公共接口。
%
% MATLAB R2020a的loadlibrary解析器会递归展开新版Windows SDK的stdio.h，
% 并把两个仅供UCRT内部使用的指针类型误报为未知类型。此外，当前MATLAB
% 自带Perl不支持C.UTF-8区域设置。本函数通过专用不透明FILE声明和临时C
% locale消除两个根因，同时保留notfound和解析文本的严格检查。

if nargin < 2 || isempty(libraryName) || isempty(headerName)
    error('SHT:LoadLibrary:BadInput', '必须给出DLL名称和公共头文件。');
end

thisDir = fileparts(mfilename('fullpath'));
parserIncludeDir = fullfile(thisDir, 'matlab_loadlibrary_include');
assert(isfolder(parserIncludeDir) && ...
    isfile(fullfile(parserIncludeDir, 'stdio.h')), ...
    'loadlibrary专用stdio.h不存在：%s', parserIncludeDir);

localeNames = {'LC_ALL', 'LC_CTYPE', 'LANG'};
oldLocale = cellfun(@getenv, localeNames, 'UniformOutput', false);
restoreLocale = onCleanup(@() local_restore_locale(localeNames, oldLocale));
for i = 1:numel(localeNames)
    setenv(localeNames{i}, 'C');
end

% 不同MATLAB版本和进程分别生成桥接库，避免覆盖正在使用的thunk DLL。
% 仅改变桥接文件位置；编译器仍由用户已配置的mex C环境决定。
thunkDirectory = '';
optionNames = varargin(1:2:end);
hasThunk = any(cellfun(@(s) ischar(s) && strcmpi(s,'thunkfilename'),optionNames));
if ~hasThunk && ~isa(headerName,'function_handle')
    libraryFile=libraryName;
    [~,~,extension]=fileparts(libraryFile);
    if isempty(extension),libraryFile=[libraryFile,'.dll'];end
    libraryFile=local_absolute_file(libraryFile);
    headerFile=local_absolute_file(headerName);
    thunkDirectory = fullfile(thisDir,'MiddleData','runtime_thunks', ...
        sprintf('%s_%s_p%d',version('-release'),computer('arch'),feature('getpid')));
    if ~isfolder(thunkDirectory), mkdir(thunkDirectory); end
    [~,libraryBase] = fileparts(libraryName);
    varargin = [varargin, {'thunkfilename',[libraryBase '_thunk'], ...
        'includepath',fileparts(headerFile)}];
    % R2019b以当前目录解析生成的桥接库名。DLL/头文件先解析为绝对路径，
    % 仅在loadlibrary期间切目录；部件初始化仍在调用方的MDL目录进行。
    oldDirectory=pwd;restoreDirectory=onCleanup(@()cd(oldDirectory));
    cd(thunkDirectory);libraryName=libraryFile;headerName=headerFile;
end

[notFound, parserOutput] = loadlibrary(libraryName, headerName, varargin{:}, ...
    'includepath', parserIncludeDir);

if ~isempty(notFound)
    error('SHT:LoadLibrary:MissingDeclarations', ...
        'GTESS公共接口存在无法加载的声明：%s', strjoin(notFound, ', '));
end

problemPattern = ['(?im)(perl:\s*warning|type\s+''[^'']+''\s+was\s+' ...
    'not\s+found|\berror\s*:|fatal\s+error)'];
problem = regexp(parserOutput, problemPattern, 'match');
if ~isempty(problem)
    error('SHT:LoadLibrary:ParserFailure', ...
        'GTESS公共接口解析仍存在问题：\n%s', strtrim(parserOutput));
end

diagnostics = struct('notFound', {notFound}, ...
    'parserOutput', parserOutput, ...
    'parserIncludeDir', parserIncludeDir, ...
    'thunkDirectory', thunkDirectory, ...
    'localeDuringParse', 'C');
clear restoreLocale;
if exist('restoreDirectory','var'),clear restoreDirectory;end
end

function file=local_absolute_file(file)
if isfile(file)
    object=java.io.File(file);
    % MATLAB的cd不更新JVM的user.dir，相对路径必须先由MATLAB的pwd展开。
    if ~object.isAbsolute(),object=java.io.File(fullfile(pwd,file));end
    file=char(object.getCanonicalPath());
else
    resolved=which(file);
    assert(~isempty(resolved),'SHT:LoadLibrary:FileMissing','找不到接口文件：%s',file);
    file=resolved;
end
end

function local_restore_locale(names, values)
for i = 1:numel(names)
    setenv(names{i}, values{i});
end
end
