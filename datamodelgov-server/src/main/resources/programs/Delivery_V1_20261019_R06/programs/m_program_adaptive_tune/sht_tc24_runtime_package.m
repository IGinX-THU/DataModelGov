function package=sht_tc24_runtime_package(selection)
%SHT_TC24_RUNTIME_PACKAGE TC24显式运行包选择，不改根DLL或物理开关。
% 默认读取独立JSON选择；legacy只供旧包对照。旧Excel仍保留其生成身份。
% 当前MDL/MAP若被用户修改，拒绝静默使用陈旧副本，应重新接入/验证新包。
root=fileparts(mfilename('fullpath'));
if nargin<1,selection='selected';end
assert(ismember(selection,{'selected','legacy'}),'TC24:Runtime:Selection','未知运行包选择。');
if strcmp(selection,'legacy')
    package=struct('id','legacy_tune','directory',root, ...
        'dllSha256',local_hash(fullfile(root,'GTESS.dll')));return;
end
file=fullfile(root,'TestData','three_component','tc24_runtime_selection.json');
assert(isfile(file),'TC24:Runtime:MissingSelection','缺少TC24运行包选择：%s',file);
fid=fopen(file,'r','n','UTF-8');cleanup=onCleanup(@()fclose(fid));
record=jsondecode(fread(fid,Inf,'*char').');clear cleanup;
assert(strcmp(record.schemaVersion,'TC24_RUNTIME_SELECTION_V1') && ...
    record.modelMode==0 && ~record.enableRni, ...
    'TC24:Runtime:Configuration','运行包选择不得改变TC24模式或自动启用RNI。');
directory=fullfile(root,strrep(record.runtimeRelative,'/',filesep));
directory=char(java.io.File(directory).getCanonicalPath());
allowed=char(java.io.File(fullfile(root,'MiddleData','three_component','runtime_packages')).getCanonicalPath());
assert(startsWith(lower(directory),[lower(allowed),filesep]), ...
    'TC24:Runtime:OutsideScope','所选运行包不在TC24运行包目录中。');
for i=1:numel(record.assets)
    a=record.assets(i);
    assert(isempty(regexp(a.name,'[/\\]','once')) && ~contains(a.name,'..'), ...
        'TC24:Runtime:AssetName','运行资产名称必须是文件名。');
    loaded=fullfile(directory,a.name);
    assert(isfile(loaded) && strcmpi(local_hash(loaded),a.sha256), ...
        'TC24:Runtime:Identity','运行资产缺失或哈希改变：%s',loaded);
    if a.matchFormalSource
        assert(strcmpi(local_hash(fullfile(root,a.name)),a.sha256), ...
            'TC24:Runtime:SourceChanged', ...
            '正式%s与已验收运行包不同，请为手工变更建立并验证新包，不能沿用旧副本。',a.name);
    end
end
package=struct('id',record.packageId,'directory',directory, ...
    'dllSha256',local_hash(fullfile(directory,'GTESS.dll')), ...
    'selectionFile',file,'assets',record.assets);
end

function value=local_hash(file)
f=fopen(file,'rb');assert(f>=0,'TC24:Runtime:MissingAsset','文件不存在：%s',file);
c=onCleanup(@()fclose(f));bytes=fread(f,Inf,'*uint8');clear c;
d=java.security.MessageDigest.getInstance('SHA-256');d.update(bytes);
value=upper(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end
