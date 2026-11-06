function cfg = sht_startstop_modeling_config(user)
%SHT_STARTSTOP_MODELING_CONFIG 起停建模任务的集中配置，不加载DLL、不计算气路。
% source.codeDirectory指定同一版本的原算法；modelDirectory指定原MDL及原图。
% 两者可以不同，但不会按文件名到其他目录猜测替代文件。
% engineOverrides只覆盖现有起停配置中的物理/数值参数；不能覆盖隔离路径。
% source.designStateFile可显式提供当前拓扑的设计解；V1/V2分别配对各自MDL。
% 不提供时保持原默认；提供时设计参考在任何DLL计算前生效，不作末端覆盖。
if nargin < 1, user = struct(); end
assert(isstruct(user) && isscalar(user), 'sht:modeling:config', '配置必须为标量结构。');
root = fileparts(fileparts(mfilename('fullpath')));
source = '';
if isfile(fullfile(root,'sht_startstop_default_config.m')), source = root; end
cfg = struct('schema',26101301, 'taskId','', 'engineId','', ...
    'modelMode',0, 'taskDirectory','', 'source',struct( ...
    'codeDirectory',source, 'modelDirectory',source, 'dllDirectory',source, ...
    'modelFile','', 'thermalFile','', 'designStateFile',''), ...
    'engineOverrides',struct(), 'display',struct('showFigures',false, ...
    'generateMapFigures',true), 'requestedStages',{{}}, ...
    'estimate',struct('basis','R009/R011 local R2019b finite tasks; not an exact prediction', ...
    'mapsSeconds',[10,60], 'matrixSeconds',[30,600], ...
    'continuousCaseSeconds',[180,420], 'thermalCaseSeconds',[250,500]));
cfg = local_merge(cfg,user);
assert(cfg.schema == 26101301, 'sht:modeling:schema', '不支持的建模配置版本。');
validateattributes(cfg.modelMode,{'numeric'},{'scalar','integer','>=',0,'<=',1});
assert(isempty(cfg.taskId) || ~isempty(regexp(cfg.taskId,'^[A-Za-z0-9_-]+$','once')), ...
    'sht:modeling:taskId','taskId仅允许字母、数字、下划线和短横线。');
if isempty(cfg.source.dllDirectory), cfg.source.dllDirectory = cfg.source.modelDirectory; end
if isempty(cfg.source.modelFile)
    files = {'Turboshaft-TS.mdl','Turboshaft-TS-Split.mdl'};
    cfg.source.modelFile = files{cfg.modelMode+1};
end
assert(~contains(cfg.source.modelFile,filesep) && ~contains(cfg.source.modelFile,'/') ...
    && ~contains(cfg.source.modelFile,'..'), 'sht:modeling:modelFile','modelFile必须是所选目录内的MDL文件名。');
allowed = {'mapIO','extension','lowSpeedSolver','startStop','stage5','stage6', ...
    'stage7','aboveIdleOverrides'};
extra = setdiff(fieldnames(cfg.engineOverrides),allowed);
assert(isempty(extra),'sht:modeling:override','engineOverrides含禁止覆盖的字段：%s。',strjoin(extra,','));
local_reject_paths(cfg.engineOverrides);
% 写入位置由适配层统一控制，不能通过底层覆盖配置逃逸到正式目录。
if isfield(cfg.engineOverrides,'stage7')
    assert(~isfield(cfg.engineOverrides.stage7,'assetFile'), ...
        'sht:modeling:override','热参数文件请配置source.thermalFile。');
end
if isfield(cfg.engineOverrides,'aboveIdleOverrides') && ...
        isfield(cfg.engineOverrides.aboveIdleOverrides,'engine')
    e=cfg.engineOverrides.aboveIdleOverrides.engine;
    assert(~isfield(e,'runtimeDirectory') && ~isfield(e,'modelMode') && ...
        ~isfield(e,'designReference'), ...
        'sht:modeling:override','禁止另覆盖控制运行目录、拓扑或设计参考；请使用source.designStateFile。');
end
assert(~isfield(cfg.engineOverrides,'stage6') || ...
    (~isfield(cfg.engineOverrides.stage6,'timeStepS') || cfg.engineOverrides.stage6.timeStepS==0.025), ...
    'sht:modeling:step','正式连续积分步长为0.025秒。');
assert(~isfield(cfg.engineOverrides,'stage6') || ...
    (~isfield(cfg.engineOverrides.stage6,'integrationMethod') || ...
    strcmp(cfg.engineOverrides.stage6.integrationMethod,'euler2')), ...
    'sht:modeling:step','正式连续积分采用二阶欧拉。');
stages={'maps','design','matrix','physics','continuous','thermal'};
assert(iscell(cfg.requestedStages) && all(ismember(cfg.requestedStages,stages)), ...
    'sht:modeling:stage','requestedStages含未知阶段。');
cfg.availableStageNames = stages;
cfg.scope = 'Engineering low-speed model construction; no measured-data identification or UQ';
end

function local_reject_paths(s)
% 文件输入必须进入已签名的source合同，不能藏在控制器等嵌套覆盖配置中。
names=fieldnames(s);
for k=1:numel(names)
    n=names{k};
    assert(isempty(regexpi(n,'(file|directory|path|root)$','once')), ...
        'sht:modeling:override','engineOverrides不能另指定文件或目录：%s。',n);
    if isstruct(s.(n)),local_reject_paths(s.(n));end
end
end

function a=local_merge(a,b)
names=fieldnames(b);
for k=1:numel(names)
    n=names{k};
    if isfield(a,n) && isstruct(a.(n)) && isstruct(b.(n)) && ...
            isscalar(a.(n)) && isscalar(b.(n))
        a.(n)=local_merge(a.(n),b.(n));
    else
        a.(n)=b.(n);
    end
end
end
