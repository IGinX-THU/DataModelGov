function package=sht_tc27_runtime_package(selection,validationScope)
%SHT_TC27_RUNTIME_PACKAGE 只读选择并核对TC27配套包，绝不隐式复制根资产。
% 缺省按独立JSON选择；legacy用于冻结历史结果。显式目录按调用时pwd
% 解析，供隔离候选验证。准备/切换必须显式执行，不在配置函数内进行。
root=fileparts(mfilename('fullpath'));
if nargin<2,validationScope='complete';end
assert(ismember(validationScope,{'complete','physical'}),'TC27:Runtime:Scope','未知运行包校验范围。');
physicalOnly=strcmp(validationScope,'physical');
legacy=fullfile(root,'MiddleData','three_component','tc27_runtime');
if nargin<1||isempty(selection)||strcmp(selection,'selected')
    r=local_json(fullfile(root,'TestData','three_component','tc27_runtime_selection.json'));
    assert(strcmp(r.schemaVersion,'TC27_RUNTIME_SELECTION_V1'), ...
        'TC27:Runtime:Schema','运行包选择版本错误。');
    selection=fullfile(root,strrep(r.runtimeRelative,'/',filesep));
elseif strcmp(selection,'legacy')
    selection=legacy;
end
[ok,attributes]=fileattrib(char(selection));
assert(ok&&attributes.directory,'TC27:Runtime:Directory','运行目录不存在：%s',char(selection));
directory=attributes.Name;
if strcmpi(directory,legacy)
    manifest=fullfile(root,'TestData','three_component','tc27_legacy_runtime_manifest.json');
else
    manifest=fullfile(directory,'tc27_runtime_manifest.json');
    if physicalOnly&&~isfile(manifest)
        manifest=fullfile(directory,'tc27_physical_manifest.json');
    end
end
r=local_json(manifest);
validSchema=strcmp(r.schemaVersion,'TC27_RUNTIME_PACKAGE_V1')|| ...
    (physicalOnly&&strcmp(r.schemaVersion,'TC27_PHYSICAL_PACKAGE_V1'));
assert(validSchema&&r.modelMode==0&&~r.enableRni, ...
    'TC27:Runtime:Schema','TC27包必须为三部件，台架RNI保持关闭。');
required={'GTESS.dll','GTESS.h','blockAndFunctions.h','types_TMATS.H', ...
    'Turboshaft-TS.mdl','HPC02.MAP','HPT02.MAP','LPT02.MAP'};
assert(numel(unique({r.assets.name}))==numel(r.assets)&&all(ismember(required,{r.assets.name})), ...
    'TC27:Runtime:Incomplete','配套DLL、接口或三部件模型资产不完整。');
for j=1:numel(r.assets)
    a=r.assets(j);
    assert(isempty(regexp(a.name,'[/\\]','once'))&&~contains(a.name,'..'), ...
        'TC27:Runtime:Name','包内资产必须是单一文件名。');
    local_check(fullfile(directory,a.name),a.sha256);
end
% 仅生成热参数的基准气路允许尚无热MAT；正式配置仍逐项核对完整包。
if physicalOnly
    package=struct('id',r.packageId,'directory',directory,'manifestFile',manifest, ...
        'identity',struct('modelMode',r.modelMode,'enableRni',r.enableRni, ...
        'assets',r.assets,'thermalAssets',[]));
    return;
end
% 热参数及参考表仍保留其原生成身份；此处核对依赖，不给旧MAT改签。
for j=1:numel(r.thermalAssets)
    a=r.thermalAssets(j);
    assert(startsWith(a.relative,'MiddleData/three_component/tc27/')&&~contains(a.relative,'..'), ...
        'TC27:Runtime:ThermalPath','热资产必须位于TC27独立目录。');
    local_check(fullfile(root,strrep(a.relative,'/',filesep)),a.sha256);
end
package=struct('id',r.packageId,'directory',directory,'manifestFile',manifest, ...
    'identity',struct('modelMode',r.modelMode,'enableRni',r.enableRni, ...
    'assets',r.assets,'thermalAssets',r.thermalAssets));
for j=1:numel(r.thermalAssets)
    file=fullfile(root,strrep(r.thermalAssets(j).relative,'/',filesep));
    [~,name]=fileparts(file);
    if strcmp(name,'tc27_kurzke15_parameters'),package.kurzkeFile=file;
    elseif strcmp(name,'tc27_visser16_parameters'),package.thermalFile=file;end
end
assert(isfield(package,'kurzkeFile')&&isfield(package,'thermalFile'), ...
    'TC27:Runtime:ThermalAssets','必须声明三部件两种热资产。');
end

function r=local_json(file)
assert(isfile(file),'TC27:Runtime:MissingManifest', ...
    '缺少已准备的运行包清单：%s。请先显式准备并验收，不允许自动复制。',file);
f=fopen(file,'r','n','UTF-8');clean=onCleanup(@()fclose(f));
r=jsondecode(fread(f,Inf,'*char').');
end

function local_check(file,expected)
assert(isfile(file)&&strcmpi(sht_tc27_file_identity(file),expected), ...
    'TC27:Runtime:Identity','配套资产缺失或已改变：%s。请建立新包验证，不覆盖旧包。',file);
end
