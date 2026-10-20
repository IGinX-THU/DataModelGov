function view=Start_TC27_ThermalPreparationResultView_01(resultFile)
%START_TC27_THERMALPREPARATIONRESULTVIEW_01 独立读取已保存的热准备结果。
% 输入为明确的结果MAT或其所在目录。只读取同目录成对热MAT并核对SHA；
% 不依赖生成时的绝对路径，不调用配置、DLL、求解器，也不写文件。
% 旧结果没有环境元数据时明确返回不可用，绝不按当前默认值补造。
if nargin~=1 || ~(ischar(resultFile)||(isstring(resultFile)&&isscalar(resultFile)))
    error('TC27:ThermalView:Input','请明确提供热准备结果MAT或目录。');
end
resultFile=char(resultFile);
assert(~isempty(resultFile),'TC27:ThermalView:Input','结果路径不能为空。');
if isfolder(resultFile)
    resultFile=fullfile(resultFile,'tc27_thermal_preparation_result.mat');
end
resultFile=char(java.io.File(resultFile).getCanonicalPath());
assert(isfile(resultFile),'TC27:ThermalView:MissingResult','结果文件不存在：%s。',resultFile);
loaded=load(resultFile,'result');
assert(isfield(loaded,'result')&&isstruct(loaded.result)&&isscalar(loaded.result), ...
    'TC27:ThermalView:Result','文件必须包含标量结构result。');
r=loaded.result;
view=struct('resultFile',resultFile,'result',r,'complete',false, ...
    'environmentMetadataAvailable',false,'generationConfiguration',[], ...
    'savedAssetIdentityVerified',false,'runtimeIdentityVerified',false, ...
    'thermalAssets',struct(),'status','PARTIAL','limitations',{{ ...
    '只校核保存结果与成对热资产，不重新验证当前DLL/MDL/MAP。', ...
    '热参考是充分热平衡结果，不等于任意任务的连续热历史。'}});
if ~isfield(r,'preparation') || ~isfield(r.preparation,'complete') || ~r.preparation.complete
    assert(isfield(r,'complete')&&isequal(r.complete,false), ...
        'TC27:ThermalView:Incomplete','结果既无完整记录，也无明确partial标记。');
    fprintf('热准备结果尚未完成，仅供检查：%s\n',resultFile);
    return;
end
p=r.preparation;
assert(ismember(p.schemaVersion,{'TC27_THERMAL_READY_V1', ...
    'TC27_G11_INHERITED_THERMAL_READY_V1'}) && numel(p.thermalAssets)==2, ...
    'TC27:ThermalView:Schema','结果schema或成对热文件记录不支持。');
names={'tc27_kurzke15_parameters.mat','tc27_visser16_parameters.mat'};
keys={'kurzke','visser'};modes=[1,3];stateCounts=[15,16];
folder=fileparts(resultFile);used=false(1,2);
metadataAvailable=isfield(p,'generationConfiguration') && ~isempty(p.generationConfiguration);
if metadataAvailable
    g=p.generationConfiguration;
    local_validate_generation(g);
else
    g=[];
end
for k=1:2
    % 旧绝对路径只作审计。搬迁后只允许在结果同目录找到固定的成对文件。
    match=[];
    for j=1:2
        relative=strrep(char(p.thermalAssets(j).relative),'\','/');
        parts=strsplit(relative,'/');
        assert(~any(ismember(parts,{'..','.'})),'TC27:ThermalView:AssetPath', ...
            '保存的热资产相对路径含非法分段。');
        if strcmp(parts{end},names{k}),match(end+1)=j;end %#ok<AGROW>
    end
    assert(numel(match)==1 && ~used(match),'TC27:ThermalView:Pair','成对热文件名重复或缺失。');
    used(match)=true;
    file=fullfile(folder,names{k});
    assert(isfile(file),'TC27:ThermalView:MissingAsset','缺少同目录热资产：%s。',file);
    expected=char(p.thermalAssets(match).sha256);
    actual=sht_tc27_file_identity(file);
    assert(strcmpi(actual,expected),'TC27:ThermalView:AssetIdentity', ...
        '热资产SHA不匹配：%s。',file);
    data=load(file,'parameterAsset');
    assert(isfield(data,'parameterAsset')&&isstruct(data.parameterAsset), ...
        'TC27:ThermalView:Asset','热文件缺少parameterAsset。');
    a=data.parameterAsset;
    assert(a.interface.interfaceVersion==2502 && a.interface.thermalModelMode==modes(k) && ...
        numel(a.nominal.initialTemperatureState)==stateCounts(k)-2, ...
        'TC27:ThermalView:Topology','热参数模式或状态维数不匹配。');
    assert(isfield(r,keys{k})&&isequaln(a,r.(keys{k})), ...
        'TC27:ThermalView:EmbeddedAsset','完成结果内嵌热资产与同目录文件不一致。');
    local_verify_saved_physical_identity(a,p);
    if metadataAvailable
        assert(isfield(a,'generationConfiguration')&&isequaln(g,a.generationConfiguration), ...
            'TC27:ThermalView:Generation','结果与热资产生成环境/参考配置不一致。');
    else
        assert(~isfield(a,'generationConfiguration')||isempty(a.generationConfiguration), ...
            'TC27:ThermalView:Generation','部分文件有生成配置、完成记录却缺失，拒绝混配。');
    end
    view.thermalAssets.(keys{k})=local_asset_view(a,file,actual,stateCounts(k));
    if metadataAvailable
        expectedPoints=g.referencePoints;
        observed=view.thermalAssets.(keys{k}).referencePoints;
        assert(isequal(string(observed.point_id),string(expectedPoints.point_id)) && ...
            isequal(observed.Np_rpm,expectedPoints.Np_rpm) && ...
            isequal(observed.load_power_kW,expectedPoints.load_power_kW) && ...
            isequal(observed.target_torque_Nm,expectedPoints.target_torque_Nm) && ...
            isequal(observed.useForTable,expectedPoints.useForTable), ...
            'TC27:ThermalView:Reference','生成配置与实际参考点不一致。');
    end
end
view.complete=true;view.status='COMPLETE_SAVED_RESULT';
view.environmentMetadataAvailable=metadataAvailable;
view.generationConfiguration=g;view.savedAssetIdentityVerified=true;
if ~metadataAvailable
    view.limitations{end+1}='历史结果未保存实际生成环境；不推定默认环境。';
end
fprintf('已读热准备结果，成对热资产SHA通过：%s\n',resultFile);
fprintf('实际生成环境已保存：%d；未启动DLL或重新求解。\n',metadataAvailable);
end

function local_verify_saved_physical_identity(a,p)
% 只核保存记录之间的关联，不把此检查称为当前运行目录物理资产复验。
assert(isfield(p,'physicalIdentity')&&isfield(p.physicalIdentity,'assets') && ...
    isfield(a,'modelIdentity'),'TC27:ThermalView:PhysicalIdentity','缺少保存的物理身份。');
items=p.physicalIdentity.assets;
files={'GTESS.dll','GTESS.h','Turboshaft-TS.mdl'};
fields={'dllSHA256','headerSHA256','modelSHA256'};
for k=1:3
    selected=find(strcmp({items.name},files{k}));
    assert(numel(selected)==1&&isfield(a.modelIdentity,fields{k}) && ...
        strcmpi(a.modelIdentity.(fields{k}),items(selected).sha256), ...
        'TC27:ThermalView:PhysicalIdentity','热资产与生成记录的%s身份不一致。',files{k});
end
end

function local_validate_generation(g)
required={'schemaVersion','modelMode','thermalModes','effectiveBoundaryTemplate', ...
    'referencePoints','referenceBoundaryRule','sourceDesignReference', ...
    'executionDesignReference','configurationIdentity','thermalPriorIdentity'};
assert(isstruct(g)&&isscalar(g)&&all(isfield(g,required)) && ...
    strcmp(g.schemaVersion,'TC27_THERMAL_GENERATION_CONFIG_V1') && ...
    g.modelMode==0 && isequal(g.thermalModes,[1,3]), ...
    'TC27:ThermalView:Generation','生成配置字段或版本不符。');
b=g.effectiveBoundaryTemplate;
assert(isstruct(b)&&isscalar(b)&&all(isfield(b,{'inletBoundaryMode','deltaTemperature', ...
    'ptLoadInputMode','gtLoadInputMode','Mkg'})), ...
    'TC27:ThermalView:Boundary','缺少实际边界或负载模式。');
assert(istable(g.referencePoints) && all(ismember({'point_id','Np_rpm', ...
    'load_power_kW','target_torque_Nm','useForTable'},g.referencePoints.Properties.VariableNames)), ...
    'TC27:ThermalView:Reference','生成配置缺少实际参考点及Mkp规则。');
assert(strcmp(g.referenceBoundaryRule.MkpSource,'referencePoints.target_torque_Nm'), ...
    'TC27:ThermalView:Boundary','不支持的逐工况Mkp覆盖规则。');
end

function out=local_asset_view(a,file,hash,stateCount)
assert(a.referenceTable.generated && istable(a.referenceGrid) && ...
    numel(a.referenceEquilibria)==height(a.referenceGrid), ...
    'TC27:ThermalView:Reference','热参考表或平衡结果不完整。');
points=a.referenceGrid;equilibria=a.referenceEquilibria(:);
if ~ismember('useForTable',points.Properties.VariableNames)
    points.useForTable=true(height(points),1);
end
if isfield(a,'independentValidation')
    point=a.independentValidation.point;point.useForTable=false(height(point),1);
    points=[points;point];equilibria{end+1,1}=a.independentValidation.equilibrium;
end
% G11的独立点可位于任意行。恢复生成配置原顺序，温度与工况编号同步排列。
if isfield(a,'generationConfiguration')
    [present,order]=ismember(string(a.generationConfiguration.referencePoints.point_id), ...
        string(points.point_id));
    assert(all(present)&&numel(unique(order))==height(points), ...
        'TC27:ThermalView:Reference','参考点编号不唯一或与生成配置不符。');
    points=points(order,:);equilibria=equilibria(order);
end
if isfield(a,'stateNames')
    names=cellstr(string(a.stateNames(:)));namesAvailable=true;
else
    names=arrayfun(@(j)sprintf('state_%02d',j),1:stateCount,'UniformOutput',false).';
    namesAvailable=false;
end
assert(numel(names)==stateCount&&numel(unique(names))==stateCount, ...
    'TC27:ThermalView:StateNames','状态名称数量或唯一性错误。');
n=height(points);states=zeros(n,stateCount);fuel=zeros(n,1);valid=false(n,1);
for j=1:n
    e=equilibria{j};
    assert(numel(e.state)==stateCount&&all(isfinite(e.state(:)))&&isfinite(e.fuelFlow_kgps), ...
        'TC27:ThermalView:State','参考点%d缺少有限状态或燃油。',j);
    states(j,:)=e.state(:).';fuel(j)=e.fuelFlow_kgps;valid(j)=e.physicalValid;
end
out=struct('file',file,'sha256',hash,'parameterAsset',a,'referencePoints',points, ...
    'equilibria',{equilibria},'stateNames',{names},'stateNamesAvailable',namesAvailable, ...
    'states',states,'stateUnits',{[{'r/min','r/min'},repmat({'K'},1,stateCount-2)]}, ...
    'fuelFlow_kgps',fuel,'physicalValid',valid,'referenceTable',a.referenceTable);
end
