function cfg = sht_design_point_config(modelMode,user)
%SHT_DESIGN_POINT_CONFIG 设计点集中配置；构造配置不计算、不改任何模型。
% modelMode=0三部件，1六部件。设计值沿用原入口；用户显式覆盖design。
% sourceDirectory是MDL/MAP所在目录；codeDirectory提供DLL、头和加载助手。
if nargin<1,modelMode=0;end
if nargin<2,user=struct();end
validateattributes(modelMode,{'numeric'},{'scalar','integer','>=',0,'<=',1});
assert(isstruct(user)&&isscalar(user),'sht:dp:config','配置须为标量结构。');
solvers={@sht_dp_v1_solver,@sht_dp_v2_solver};
cfg=solvers{modelMode+1}('defaults');
cfg.schema=26101401;cfg.modelMode=modelMode;
cfg.sourceDirectory=fileparts(fileparts(mfilename('fullpath')));
cfg.codeDirectory=cfg.sourceDirectory;
cfg.taskDirectory='';cfg.engineId='';cfg.taskId='';
cfg.display=struct('showFigures',false);
cfg.estimateSeconds=[10,120];
cfg=local_merge(cfg,user);
assert(cfg.modelMode==modelMode && cfg.schema==26101401,'sht:dp:mode','配置版本或拓扑不匹配。');
assert(~isfield(user,'paths') && ~isfield(user,'interface'),'sht:dp:override', ...
    'paths/interface由程序管理，请使用sourceDirectory/codeDirectory/taskDirectory。');
names={'Turboshaft-TS.mdl','Turboshaft-TS-Split.mdl'};
cfg.modelFile=names{modelMode+1};
cfg.sourceDirectory=local_path(cfg.sourceDirectory);
cfg.codeDirectory=local_path(cfg.codeDirectory);
if ~isempty(cfg.taskDirectory),cfg.taskDirectory=local_path(cfg.taskDirectory);end
v=struct2cell(cfg.design);
assert(all(cellfun(@(x)isnumeric(x)&&isscalar(x)&&isfinite(x),v)), ...
    'sht:dp:design','全部设计值应为有限数值标量。');
assert(cfg.design.NpRpm>0 && cfg.design.NgRpm>0 && cfg.design.Wf0>0 && ...
    cfg.design.loadPowerW>=0 && cfg.design.accessoryPowerW>=0 && ...
    cfg.design.nozzleAreaM2>0 && cfg.design.targetTt4K>0,'sht:dp:design','设计值物理范围不正确。');
if modelMode==1
    assert(cfg.design.targetPt3Pa>cfg.design.targetPt25Pa && ...
        cfg.design.targetPt25Pa>cfg.design.targetPt2Pa && cfg.design.targetPt2Pa>0 && ...
        cfg.design.targetTt3K>cfg.design.targetTt25K && cfg.design.targetTt25K>cfg.design.targetTt2K && ...
        cfg.design.targetTt2K>0 && cfg.design.gtStageOneWorkFraction>0 && ...
        cfg.design.gtStageOneWorkFraction<1 && cfg.design.ptStageOneWorkFraction>0 && ...
        cfg.design.ptStageOneWorkFraction<1,'sht:dp:design','截面温压或级做功分配不合理。');
end
% 修改设计转速/燃油时同步默认初值，显式用户初值则保留。
if ~isfield(user,'solver') || ~isfield(user.solver,'initial')
    if modelMode==0,cfg.solver.initial(5:7)=[cfg.design.NpRpm;cfg.design.NgRpm;cfg.design.Wf0];
    else,cfg.solver.initial(6)=cfg.design.Wf0;end
end
if modelMode==0 && (~isfield(user,'solver') || ~isfield(user.solver,'scale'))
    cfg.solver.scale(5:6)=[cfg.design.NpRpm;cfg.design.NgRpm];
end
n=[7,12];n=n(modelMode+1);
for f={'initial','scale','lower','upper'}
    a=cfg.solver.(f{1});validateattributes(a,{'numeric'},{'vector','numel',n,'finite'});
    cfg.solver.(f{1})=a(:);
end
assert(all(cfg.solver.scale>0)&&all(cfg.solver.upper>cfg.solver.lower),'sht:dp:bounds','求解边界或尺度无效。');
validateattributes(cfg.solver.maximumIterations,{'numeric'},{'scalar','integer','positive'});
end

function a=local_merge(a,b)
names=fieldnames(b);
for i=1:numel(names)
    f=names{i};assert(isfield(a,f),'sht:dp:config','未知配置字段：%s。',f);
    if isstruct(a.(f))&&isstruct(b.(f)),a.(f)=local_merge(a.(f),b.(f));else,a.(f)=b.(f);end
end
end

function p=local_path(p)
assert(ischar(p)&&~isempty(p)&&isrow(p),'sht:dp:path','目录须为非空字符路径。');
p=char(java.io.File(p).getCanonicalPath());
end
