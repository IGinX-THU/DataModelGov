function sht_afo_presurgery(programDir)
%SHT_AFO_PRESURGERY 启动预装配:服务启动期在专属引擎里把改装模型装好并常驻内存,
% 同项目首场prepare即享复用(免load+免手术)。程序目录来自上次会话落盘的
% run/afo-warm.properties(Java侧读写);任何一步失败只跳过预装配,不影响后续prepare。
model='Dll_Control_AFO_V8_5_R2019b';
spec=sht_afo_channels;
% 预装配固定按常规模式(非回归),tag格式与 sht_afo_prepare.m/sht_afo_surgery.m 一致
expectedTag=sprintf('dmg-afo-surgery-v1|n=%d|ref=0',numel(spec));
if bdIsLoaded(model)  % 已有改装模型(守护收养/上一场遗留):符合预期即直接复用
    sink=[model '/AFO Business Recorder'];
    if ~isempty(find_system(model,'SearchDepth',1,'Name','AFO Business Recorder'))&&...
            strcmp(get_param(sink,'Tag'),expectedTag)&&...
            strcmp(get_param(model,'SimulationStatus'),'stopped')
        fprintf('AFO_PRESURGERY 模型已就绪,直接复用内存改装模型。\n');return;
    end
    close_system(model,0);
end
cacheDir=fullfile(programDir,'_dmg_cache');
cacheSlx=fullfile(cacheDir,[model '.slx']);
srcSlx=fullfile(programDir,[model '.slx']);
% 以dir()为准:刚启动的引擎里exist()对确实存在的文件偶发返回0(实测两次,普通
% MATLAB进程同一路径exist==2),dir()直查文件系统更可靠;真缺失时打诊断便于定位。
srcHit=dir(srcSlx);
if isempty(srcHit)
    fprintf(2,'AFO_PRESURGERY_DIAG: exist=%d dircount=0 pwd=%s progdirIsDir=%d progdirEntries=%d\n', ...
        exist(srcSlx,'file'),pwd,exist(programDir,'dir'),numel(dir(programDir)));
end
assert(~isempty(srcHit),'sht:afo:presurgery','程序目录缺少原始模型:%s',srcSlx);
% 依赖身份:原始模型SHA必须与缓存记录一致(交付树/补丁更新后缓存自动失效)
sourceSha=local_hash(srcSlx);
meta=local_cache_meta(fullfile(cacheDir,'cache.mat'));
fromCache=~isempty(dir(cacheSlx))&&~isempty(meta)&&...
    strcmp(meta.tag,expectedTag)&&strcmp(meta.sourceSha,sourceSha);
if ~fromCache
    if ~isfolder(cacheDir),mkdir(cacheDir);end
    copyfile(srcSlx,cacheSlx);
end
old=pwd;oldPath=path;oldGen=Simulink.fileGenControl('getConfig');
cleaner=onCleanup(@() local_presurgery_restore(old,oldPath,oldGen));
cd(cacheDir);
Simulink.fileGenControl('set','CacheFolder',fullfile(cacheDir,'_slCache'), ...
    'CodeGenFolder',fullfile(cacheDir,'code'),'createDir',true);
addpath(programDir,'-begin');
load_system(cacheSlx);
cfg=struct('legacyPulses',false,'verificationOriginalSources',false);
sht_afo_surgery(model,cfg);  % 缓存命中则幂等跳过,否则手术并保存到cacheSlx
if ~fromCache
    meta=struct('tag',expectedTag,'sourceSha',sourceSha,'updatedAt',datestr(now));
    save(fullfile(cacheDir,'cache.mat'),'-struct','meta');
end
[~,~]=sht_afo_catalog;  % 预热显示字典(readtable单次1~9s,别让首场prepare付)
fprintf('AFO_PRESURGERY 模型预装配完成(%s)。\n',local_source_name(fromCache));
end
function s=local_source_name(fromCache)
if fromCache,s='改装缓存命中';else,s='原始模型+手术';end
end
function meta=local_cache_meta(file)
meta=[];
try
    loaded=load(file);
    if isfield(loaded,'tag')&&isfield(loaded,'sourceSha')
        meta=struct('tag',loaded.tag,'sourceSha',loaded.sourceSha);
    end
catch
end
end
function local_presurgery_restore(folder,p,g)
% 预装配模型特意保留在内存(这就是预装配的目的);只还原环境。
Simulink.fileGenControl('setConfig','config',g);cd(folder);path(p);
end
function h=local_hash(file)
fid=fopen(file,'rb');g=onCleanup(@()fclose(fid));bytes=fread(fid,Inf,'*uint8');
md=java.security.MessageDigest.getInstance('SHA-256');md.update(bytes); ...
    h=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end
