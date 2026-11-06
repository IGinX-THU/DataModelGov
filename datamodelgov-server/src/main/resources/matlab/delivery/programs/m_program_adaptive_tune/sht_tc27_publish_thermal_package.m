function package=sht_tc27_publish_thermal_package(runtimeDirectory,assetDirectory)
%SHT_TC27_PUBLISH_THERMAL_PACKAGE 显式发布新候选清单；绝不修改当前选择JSON。
% 先准备八项配套文件及tc27_physical_manifest.json，再由TC27-02生成热资产。
% 两套热资产、12点参考表与完成记录都验证成功，才允许新建完整清单。
root=sht_tc27_canonical_path(fileparts(mfilename('fullpath')));
runtime=sht_tc27_canonical_path(runtimeDirectory);
parent=fullfile(root,'MiddleData','three_component','runtime_packages');
assert(startsWith(lower(runtime),[lower(parent),filesep]), ...
    'TC27:Thermal:PublishScope','只能在runtime_packages内显式发布新候选包。');
manifest=fullfile(runtime,'tc27_runtime_manifest.json');
assert(~isfile(manifest),'TC27:Thermal:Published','完整清单已存在，禁止覆盖或重新签名。');
p=sht_tc27_runtime_package(runtime,'physical');
directory=sht_tc27_canonical_path(assetDirectory);
assert(startsWith(lower(directory),[lower(fullfile(root,'MiddleData','three_component','tc27')),filesep]), ...
    'TC27:Thermal:PublishScope','热资产必须属于TC27独立目录。');
ready=fullfile(directory,'tc27_thermal_preparation_result.mat');
assert(isfile(ready),'TC27:Thermal:NotReady','缺少成对生成完成记录，不允许发布。');
r=load(ready,'result');a=r.result.preparation;
assert(strcmp(a.schemaVersion,'TC27_THERMAL_READY_V1')&&a.complete&& ...
    isequal(a.referencePointIndices,1:12)&&numel(a.thermalAssets)==2, ...
    'TC27:Thermal:NotReady','必须完成两套热资产及全部12个参考点。');
assert(isequal(a.physicalIdentity,p.identity),'TC27:Thermal:Identity', ...
    '实际八项气路身份与生成记录不一致，禁止改签旧资产。');
files={fullfile(directory,'tc27_kurzke15_parameters.mat'),fullfile(directory,'tc27_visser16_parameters.mat')};
for k=1:2
    recorded=sht_tc27_canonical_path(fullfile(root,strrep(a.thermalAssets(k).relative,'/',filesep)));
    assert(strcmpi(recorded,files{k})&&strcmpi(sht_tc27_file_identity(files{k}),a.thermalAssets(k).sha256), ...
        'TC27:Thermal:Identity','热资产路径或内容已改变，禁止发布。');
end
sht_tc27_validate_thermal_assets(runtime,files,12);
r=struct('schemaVersion','TC27_RUNTIME_PACKAGE_V1','packageId',p.id, ...
    'modelMode',0,'enableRni',false,'assets',p.identity.assets,'thermalAssets',a.thermalAssets);
% 私有临时文件由Java创建；最终移动不允许覆盖并发发布者的清单。
temp=char(java.io.File.createTempFile('tc27_publish_','.json',java.io.File(runtime)).getPath());
f=fopen(temp,'w','n','UTF-8');assert(f>=0,'TC27:Thermal:Write','无法创建新清单。');
c=onCleanup(@()fclose(f));fprintf(f,'%s',jsonencode(r));clear c;
java.nio.file.Files.move(java.io.File(temp).toPath(),java.io.File(manifest).toPath(), ...
    javaArray('java.nio.file.CopyOption',0));
package=sht_tc27_runtime_package(runtime);
fprintf('新候选包已发布：%s；当前运行包选择未改变。\n',runtime);
end
