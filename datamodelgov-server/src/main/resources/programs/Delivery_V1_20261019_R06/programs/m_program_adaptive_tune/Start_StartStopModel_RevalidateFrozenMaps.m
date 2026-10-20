function result=Start_StartStopModel_RevalidateFrozenMaps(modelMode)
% DLL更新后，以旧冻结图作为只读候选，重新执行全部低速矩阵。
% 这不是重写旧PASS或哈希；新结果重新发布，旧资产完整保留。
if nargin<1,modelMode=1;end
cfg=sht_startstop_default_config(struct('modelMode',modelMode));
base=fullfile(cfg.paths.matlabRoot,'MiddleData','startstop');
if modelMode==0,base=fullfile(base,cfg.topology.assetNamespace);end
idx=load(fullfile(base,'stage05_latest.mat'),'leaf');
oldRoot=fullfile(base,idx.leaf);a=load(fullfile(oldRoot,'result.mat'));
old=a.result;
for i=1:numel(old.finalMapAudit.items)
    p=fullfile(oldRoot,old.finalMapAudit.items(i).outputPath);
    assert(strcmpi(local_hash(p),a.mapHashes{i}),'旧冻结图被修改，停止重验。');
    old.finalMapAudit.items(i).outputPath=p;
end
if ~isfield(old,'design')
    idx=load(fullfile(base,'design_latest.mat'),'leaf');
    d=load(fullfile(base,idx.leaf,'result.mat'));old.design=d.result.design;
end
% 不允许借重验混入MDL/原图变化；DLL和接口变化由实际回归验证。
assert(strcmpi(local_hash(cfg.paths.splitModel),a.identity{3}),'MDL已变化，须重新设计/扩图。');
names=fieldnames(cfg.maps);
for i=1:numel(names)
    assert(strcmpi(local_hash(fullfile(cfg.paths.cRoot,cfg.maps.(names{i}).sourceName)), ...
        a.identity{3+i}),'原图已变化，须重新扩图。');
end
op=path;addpath(cfg.paths.matlabRoot);pc=onCleanup(@()path(op)); %#ok<NASGU>
root=fullfile(cfg.paths.outputRoot,sprintf('Revalidate_M%d_%s',modelMode,datestr(now,'yyyymmdd_HHMMSS')));
mkdir(root);runtime=sht_startstop_create_runtime(cfg,old.finalMapAudit,root);
wd=pwd;cd(runtime.controlDir);dc=onCleanup(@()cd(wd)); %#ok<NASGU>
alias='GTESS_SS_REVALIDATE';
sht_load_engine_library(runtime.dllPath,runtime.headerPath,'alias',alias);
assert(calllib(alias,'DLL_SHT_InitialMode',modelMode)==0);sht_startstop_configure_dll(alias,cfg);
initial.eng=libstruct('EngineTurboshaft');ep=libstruct('EngineSHTPointer',initial);clear initial;
calllib(alias,'DLL_SHT_ConditionsInit',libpointer('doublePtr',zeros(512,1)), ...
    libpointer('doublePtr',zeros(128,1)),ep);
matrix=sht_startstop_evaluate_low_speed_matrix(alias,ep,cfg,runtime.controlDir,old.design, ...
    struct('writeEvidence',true,'outputDir',root));
calllib(alias,'DLL_SHT_Free');clear ep;unloadlibrary(alias);
result=struct('accepted',matrix.accepted,'design',old.design,'finalMatrix',matrix, ...
    'finalMapAudit',old.finalMapAudit,'previousAsset',oldRoot,'configuration',cfg,'runRoot',root);
if result.accepted,sht_startstop_stage_asset('publish','stage05',cfg,result);end
fprintf('M%d旧图新DLL重验：%d/%d。\n',modelMode,matrix.summary.acceptedCount,matrix.summary.applicableCount);
end

function h=local_hash(p)
fid=fopen(p,'rb');assert(fid>=0);c=onCleanup(@()fclose(fid)); %#ok<NASGU>
md=java.security.MessageDigest.getInstance('SHA-256');
md.update(typecast(fread(fid,inf,'*uint8'),'int8'));
h=upper(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end
