function plan=sht_tc27_thermal_output_plan(options)
%SHT_TC27_THERMAL_OUTPUT_PLAN 只读预检；本函数不得配平、加载DLL或建立目录。
assert(isstruct(options)&&isscalar(options),'TC27:Thermal:Options','options必须是标量结构体。');
assert(isfield(options,'assetDirectory')&&~isempty(options.assetDirectory), ...
    'TC27:Thermal:OutputDirectory', ...
    ['必须指定独立、尚不存在的候选输出目录options.assetDirectory；', ...
     '默认调用禁止写回当前运行包热资产。']);
root=sht_tc27_canonical_path(fileparts(mfilename('fullpath')));
output=sht_tc27_canonical_path(options.assetDirectory);
owned=fullfile(root,'MiddleData','three_component','tc27');
inheritedMode=isfield(options,'inheritedThermalPair');
% 默认与继承模式均在实际程序根内输出，不依赖隔离包的兄弟目录布局。
assert(local_child(output,owned)&&~strcmpi(output,owned), ...
    'TC27:Thermal:OutputScope','候选目录必须严格位于允许的独立中间目录：%s。',owned);
assert(~isfolder(output)&&~isfile(output),'TC27:Thermal:Exists', ...
    '输出目录已存在，禁止覆盖或续写候选文件：%s',output);
assert(isfolder(fileparts(output)),'TC27:Thermal:Parent', ...
    '请先建立候选目录的父目录，再指定尚不存在的新目录：%s',fileparts(output));
if ~isfield(options,'runtimeDirectory'),options.runtimeDirectory='selected';end
% 只验证八项气路配套资产，不要求尚未生成的两套热参数。
if inheritedMode
    inherited=local_inherited_plan(options);
    package=inherited.package;
else
    package=sht_tc27_runtime_package(options.runtimeDirectory,'physical');
end
assert(~local_overlap(output,sht_tc27_canonical_path(package.directory)), ...
    'TC27:Thermal:Overlap','输出目录不得与源运行包重叠。');
search=dir(fullfile(root,'MiddleData','three_component','**','tc27_runtime_manifest.json'));
legacy=dir(fullfile(root,'TestData','three_component','tc27_legacy_runtime_manifest.json'));
search=[search;legacy];
% 只要历史/当前清单声明了依赖，即使该依赖已丢失也不得原位补写。
for j=1:numel(search)
    path=fullfile(search(j).folder,search(j).name);
    manifest=jsondecode(fileread(path));
    if ~strcmp(search(j).name,'tc27_legacy_runtime_manifest.json')
        assert(~local_overlap(output,sht_tc27_canonical_path(search(j).folder)), ...
            'TC27:Thermal:Overlap','输出目录与已发布运行包重叠：%s',path);
    end
    for k=1:numel(manifest.thermalAssets)
        file=sht_tc27_canonical_path(fullfile(root,strrep(manifest.thermalAssets(k).relative,'/',filesep)));
        parent=fileparts(file);
        % 旧包曾把MAT直接放在tc27公共父目录，允许另建子目录但不写旧文件。
        bad=local_child(file,output)|| ...
            (~strcmpi(parent,owned)&&local_child(output,parent));
        assert(~bad,'TC27:Thermal:BoundAsset','输出与已绑定热资产重叠：%s',file);
    end
end
if inheritedMode
    plan=inherited;
    plan.root=root;plan.outputDirectory=output;plan.inheritedMode=true;
    % 相对路径始终相对于这三叶所在的程序根，匹配正式TC27资产约定。
    plan.assetRoot=root;
    plan.thermalAssetTargets={fullfile(output,'tc27_kurzke15_parameters.mat'), ...
        fullfile(output,'tc27_visser16_parameters.mat')};
    plan.thermalAssetRelativePaths=cell(1,2);
    prefix=[plan.assetRoot,filesep];
    for k=1:2
        target=sht_tc27_canonical_path(plan.thermalAssetTargets{k});
        assert(startsWith(lower(target),lower(prefix)), ...
            'TC27:G11:AssetRoot','热资产目标必须严格位于明确交付根下。');
        plan.thermalAssetTargets{k}=target;
        plan.thermalAssetRelativePaths{k}=strrep(target(numel(prefix)+1:end),filesep,'/');
    end
    return;
end
if ~isfield(options,'referencePointIndices'),options.referencePointIndices=1:12;end
indices=options.referencePointIndices;
assert(isnumeric(indices)&&isvector(indices)&&~isempty(indices)&& ...
    all(isfinite(indices))&&all(indices==fix(indices))&&all(ismember(indices,1:12))&& ...
    numel(unique(indices))==numel(indices),'TC27:Thermal:ReferenceIndices','参考点索引必须是1:12中的不重复整数。');
plan=struct('root',root,'outputDirectory',output,'package',package, ...
    'referencePointIndices',indices(:).','inheritedMode',false);
end

function yes=local_child(path,parent)
yes=strcmpi(path,parent)||startsWith(lower(path),[lower(parent),filesep]);
end
function yes=local_overlap(a,b)
yes=local_child(a,b)||local_child(b,a);
end

function plan=local_inherited_plan(o)
% 所有身份和结构检查在配置、配平、mkdir之前完成，不调用DLL。
required={'physicalManifestFile','physicalManifestSHA256','lineageFile', ...
    'lineageSHA256','sourceModelFile','designStateFile','referencePoints', ...
    'boundary','configurationSHA256','candidatePackageId', ...
    'controllerGainFile','controllerGainSHA256'};
assert(all(isfield(o,required)),'TC27:G11:Inputs','G11继承模式缺少显式输入。');
local_check(o.physicalManifestFile,o.physicalManifestSHA256);
local_check(o.lineageFile,o.lineageSHA256);
lineage=local_json(o.lineageFile);
assert(lineage.ModelMode==0 && lineage.OffDesignMode==2 && ...
    lineage.DerivedModelOnlyMapPathsAndEOLChanged, ...
    'TC27:G11:Lineage','只允许已核定三部件R02路径派生模型。');
assert(strcmpi(lineage.EightFileManifestSHA256,o.physicalManifestSHA256), ...
    'TC27:G11:Lineage','八文件清单与来源记录不一致。');
% 复用已验证R2019b导入口径，避免路径反斜杠干扰自动分隔符探测。
rows=readtable(o.physicalManifestFile,'Delimiter',',','Encoding','UTF-8','HeaderLines',0, ...
    'ReadVariableNames',true,'Format','%q%q%q%q%q','TextType','string');
expected={'Name','SourcePath','Bytes','SHA256','Role'};
assert(height(rows)==8 && isequal(rows.Properties.VariableNames,expected), ...
    'TC27:G11:PhysicalManifest','真实八文件清单不符：实际%d行，列名{%s}。', ...
    height(rows),strjoin(rows.Properties.VariableNames,','));
rawBytes=rows.Bytes;rows.Bytes=str2double(rawBytes);
assert(all(isfinite(rows.Bytes)&rows.Bytes>=0&rows.Bytes==fix(rows.Bytes)&rows.Bytes<=flintmax), ...
    'TC27:G11:PhysicalBytes','Bytes必须是有限非负精确整数。');
for k=1:height(rows)
    assert(strcmp(strtrim(char(rawBytes(k))),sprintf('%.0f',rows.Bytes(k))), ...
        'TC27:G11:PhysicalBytes','第%d行Bytes不能精确表示。',k);
    assert(~isempty(regexp(char(rows.SHA256(k)),'^[0-9A-Fa-f]{64}$','once')), ...
        'TC27:G11:PhysicalSHA','第%d行SHA256不是64位十六进制。',k);
end
assert(all(strlength(rows.Name)>0&strlength(rows.SourcePath)>0&strlength(rows.Role)>0), ...
    'TC27:G11:PhysicalManifest','Name/SourcePath/Role不允许为空。');
names=cellstr(rows.Name);fixed={'GTESS.dll','GTESS.h','blockAndFunctions.h', ...
    'types_TMATS.H','Turboshaft-TS.mdl'};
assert(numel(unique(names))==8 && all(ismember(fixed,names)), ...
    'TC27:G11:PhysicalManifest','八文件缺少必需接口或模型。');
runtime=sht_tc27_canonical_path(o.runtimeDirectory);
assets=struct('name',{},'sha256',{});
for k=1:8
    name=names{k};
    assert(isempty(regexp(name,'[/\\]','once')) && ~contains(name,'..'), ...
        'TC27:G11:PhysicalName','包内名称必须是单一文件名。');
    file=fullfile(runtime,name);hash=char(rows.SHA256(k));local_check(file,hash);
    info=dir(file);assert(info.bytes==rows.Bytes(k),'TC27:G11:PhysicalSize','资产字节数不匹配。');
    assets(k)=struct('name',name,'sha256',hash);
end
mdl=fullfile(runtime,'Turboshaft-TS.mdl');
local_check(mdl,lineage.RuntimeModelSHA256);
local_check(o.sourceModelFile,lineage.SourceModelSHA256);
originalReference=lineage.DesignReference;
local_check(o.designStateFile,originalReference.designStateSHA256);
local_verify_derived_model(o.sourceModelFile,mdl,names);
s=load(o.designStateFile,'designState');
assert(isfield(s,'designState') && s.designState.modelMode==0 && ...
    s.designState.design.converged,'TC27:G11:Design','必须使用真实收敛设计解。');
d=s.designState.design;
local_equal(d.commonVariables(:),originalReference.commonVariables(:),'设计共同工作解');
local_equal(d.Wf,originalReference.fuelFlowKgPerS,'实际设计燃油');
local_equal(d.output(:),originalReference.expectedOutput(:),'原设计输出');
local_equal(originalReference.commonVariables(end-1:end), ...
    [originalReference.NpRpm;originalReference.NgRpm],'设计转速');
assert(strcmpi(originalReference.sourceModelSHA256,lineage.SourceModelSHA256), ...
    'TC27:G11:Design','原设计参考与原设计MDL不配对。');
% 只建立新的执行绑定；原design_state和原参考对象保持原身份。
r=originalReference;r.sourceModelSHA256=lineage.RuntimeModelSHA256;
pair=o.inheritedThermalPair;
assert(all(isfield(pair,{'sourceRuntimeDirectory','kurzkeFile','visserFile', ...
    'kurzkeSHA256','visserSHA256'})),'TC27:G11:Pair','必须提供完整配对热来源。');
p=sht_tc27_runtime_package(pair.sourceRuntimeDirectory);
local_check(pair.kurzkeFile,pair.kurzkeSHA256);local_check(pair.visserFile,pair.visserSHA256);
assert(strcmpi(sht_tc27_canonical_path(pair.kurzkeFile),sht_tc27_canonical_path(p.kurzkeFile)) && ...
    strcmpi(sht_tc27_canonical_path(pair.visserFile),sht_tc27_canonical_path(p.thermalFile)), ...
    'TC27:G11:Pair','不能混配其他包的同名热文件。');
ka=load(pair.kurzkeFile,'parameterAsset');va=load(pair.visserFile,'parameterAsset');
assert(ka.parameterAsset.interface.thermalModelMode==1 && ...
    va.parameterAsset.interface.thermalModelMode==3,'TC27:G11:Pair','热模式不匹配。');
oldSpeed=ka.parameterAsset.referenceTable.designSpeed_rpm(:);
local_equal(oldSpeed,va.parameterAsset.referenceTable.designSpeed_rpm(:),'热对转速归一化');
newSpeed=[sht_design_point_mdl('value',mdl,'HPT','NDes'); ...
    sht_design_point_mdl('value',mdl,'HPT','NDes'); ...
    sht_design_point_mdl('value',mdl,'LPT','NDes')];
local_equal(newSpeed,[r.NgRpm;r.NgRpm;r.NpRpm],'实际MDL归一化转速');
grid=o.referencePoints;
assert(istable(grid) && height(grid)==6 && ...
    all(ismember({'point_id','Np_rpm','load_power_kW','useForTable'},grid.Properties.VariableNames)), ...
    'TC27:G11:Grid','需要5建表点及1独立检查点。');
assert(islogical(grid.useForTable) && nnz(grid.useForTable)==5 && grid.useForTable(1), ...
    'TC27:G11:Grid','第一点必须建表，恰有一个独立检查点。');
validateattributes([grid.Np_rpm;grid.load_power_kW],{'numeric'},{'real','finite','positive'});
assert(numel(unique(string(grid.point_id)))==6,'TC27:G11:Grid','工况编号重复。');
local_equal([grid.Np_rpm(1);1000*grid.load_power_kW(1)], ...
    [r.NpRpm;r.loadPowerW],'第一参考点必须是新设计点');
grid.target_torque_Nm=1000*grid.load_power_kW./(pi*grid.Np_rpm/30);
b=o.boundary;
assert(all(isfield(b,{'inletBoundaryMode','Tt1','Pt1','Pamb','Tamb','altitude','Mach','Mkg'})) && ...
    b.inletBoundaryMode==1 && b.Mkg==0 && b.altitude==0 && b.Mach==0, ...
    'TC27:G11:Boundary','首轮采用明确的地面入口边界及零附件负载。');
validateattributes([b.Tt1,b.Pt1,b.Pamb,b.Tamb],{'numeric'},{'real','finite','positive'});
configurationFile=which('sht_default_config');
local_check(configurationFile,o.configurationSHA256);
local_check(o.controllerGainFile,o.controllerGainSHA256);
identity=struct('modelMode',0,'enableRni',false,'assets',assets,'thermalAssets',[]);
package=struct('id',char(o.candidatePackageId),'directory',runtime, ...
    'manifestFile',char(o.physicalManifestFile),'identity',identity);
plan=struct('package',package,'referencePointIndices',find(grid.useForTable).', ...
    'referenceGrid',grid,'designReference',r,'sourceDesignReference',originalReference, ...
    'designStateFile',char(o.designStateFile),'sourceModelFile',char(o.sourceModelFile), ...
    'lineage',lineage,'inheritedPair',pair,'sourceThermalIdentity',p.identity, ...
    'oldDesignSpeed_rpm',oldSpeed,'newDesignSpeed_rpm',newSpeed, ...
    'boundary',b,'configurationSHA256',o.configurationSHA256, ...
    'controllerGainFile',o.controllerGainFile,'controllerGainSHA256',o.controllerGainSHA256);
end

function local_verify_derived_model(source,runtime,names)
% 复用项目MDL结构解析器，只比较，不调用其写入分支。
a=sht_design_point_mdl('read',source);b=sht_design_point_mdl('read',runtime);
assert(numel(a.assignments)==numel(b.assignments),'TC27:G11:ModelDifference','MDL字段数变化。');
text=a.text;indices=[];values={};components={'HPC','HPT','LPT'};
for k=1:numel(a.assignments)
    x=a.assignments(k);y=b.assignments(k);
    assert(strcmp(x.component,y.component)&&strcmp(x.key,y.key), ...
        'TC27:G11:ModelDifference','MDL字段/顺序变化。');
    if strcmp(x.key,'mapPath') && ismember(x.component,components)
        assert(ismember(strtrim(y.value),names),'TC27:G11:Map','实际MAP引用不在八文件中。');
        indices(end+1)=k;values{end+1}=y.value; %#ok<AGROW>
    else
        assert(strcmp(x.value,y.value),'TC27:G11:ModelDifference', ...
            '物理字段变化：%s.%s。',x.component,x.key);
    end
end
assert(numel(indices)==3,'TC27:G11:Map','需要且仅允许三个MAP引用。');
for j=numel(indices):-1:1
    x=a.assignments(indices(j));
    text=[text(1:x.start-1),x.prefix,values{j},x.suffix,text(x.stop+1:end)]; %#ok<AGROW>
end
assert(strcmp(strrep(text,sprintf('\r\n'),sprintf('\n')), ...
    strrep(b.text,sprintf('\r\n'),sprintf('\n'))), ...
    'TC27:G11:ModelDifference','除三MAP路径和换行外，MDL还有其他差异。');
local_equal(sht_design_point_mdl('value',runtime,'','offDesignMode'),2,'设计运行模式');
end

function local_equal(a,b,label)
a=double(a(:));b=double(b(:));
assert(isequal(size(a),size(b)) && all(isfinite(a)) && all(isfinite(b)) && ...
    all(abs(a-b)<=64*eps(max(1,max(abs([a;b]))))), ...
    'TC27:G11:Design','%s不匹配。',label);
end
function local_check(file,hash)
assert(isfile(file)&&strcmpi(sht_tc27_file_identity(file),hash), ...
    'TC27:G11:Identity','身份不匹配：%s。',char(file));
end
function x=local_json(file)
f=fopen(file,'r','n','UTF-8');assert(f>=0,'TC27:G11:Read','不能读取来源记录。');
c=onCleanup(@()fclose(f));x=jsondecode(fread(f,Inf,'*char').'); %#ok<NASGU>
end
