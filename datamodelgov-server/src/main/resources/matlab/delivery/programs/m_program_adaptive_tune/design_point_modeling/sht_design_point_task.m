function task = sht_design_point_task(action,varargin)
%SHT_DESIGN_POINT_TASK GUI和离线共用的设计点流程，无弹窗、无隐式正式写入。
% solve(cfg)私有求解/预览；commit(taskDir)时间备份后写原选定MDL并复现；
% test(taskDir)复现候选；test(taskDir,'committed')复现已提交文件；
% inspect(taskDir)只读结果；export(taskDir,outputDir)只重导出，不重新求解。
% export不回写历史MAT，不放宽commit/test/validate的计算身份检查。
switch lower(action)
    case 'solve'
        cfg=varargin{1};u=cfg;u=rmfield(u,intersect(fieldnames(u),{'interface','modelFile'}));
        cfg=sht_design_point_config(cfg.modelMode,u);
        task=local_prepare(cfg);clock=tic;
        local_save(task);
        try
            task.status='solving';local_save(task);
            work=fullfile(task.taskDirectory,'MiddleData','solve_runtime');
            local_copy_runtime(task,work,task.sourceMdl);
            edits=local_anchor_edits(cfg);edits=[{'','offDesignMode',0};edits];
            text=sht_design_point_mdl('edit',fullfile(work,cfg.modelFile),edits);
            local_replace_private(fullfile(work,cfg.modelFile),text);
            run=local_solver('solve',cfg,work,struct());
            task.solution=run;task.designState=run.designState;
            target=fullfile(task.taskDirectory,'TestData','configured_model');
            local_copy_runtime(task,target,task.sourceMdl);
            edits=local_result_edits(cfg,run.design);
            task.parameterComparison=local_comparison(task.sourceMdl,edits);
            text=sht_design_point_mdl('edit',task.sourceMdl,edits);
            local_replace_private(fullfile(target,cfg.modelFile),text);
            task.candidateDirectory=target;task.candidateMdl=fullfile(target,cfg.modelFile);
            task.candidateSHA256=sht_design_point_mdl('sha256',task.candidateMdl);
            designState=task.designState; %#ok<NASGU>
            save(fullfile(task.taskDirectory,'MiddleData','design_state.mat'),'designState','-v7');
            task.status='testing_candidate';local_save(task);
            task.verification=local_solver('test',cfg,target,task.designState);
            task.accepted=task.solution.accepted && task.verification.accepted;
            task.status=local_status(task.accepted,'candidate_verified','candidate_with_findings');
            task.elapsedSeconds=toc(clock);local_save(task);
            task.export=local_export(task);
        catch ex
            task.status='failed';task.elapsedSeconds=toc(clock);
            task.error=struct('identifier',ex.identifier,'message',ex.message,'report',getReport(ex,'extended','hyperlinks','off'));
            local_save(task);rethrow(ex);
        end
    case 'commit'
        task=local_load(varargin{1});local_require_candidate(task);
        assert(task.accepted,'sht:dp:notVerified','候选设计未通过复现，不能自动改写所选MDL。');
        assert(~isfield(task,'commit'),'sht:dp:alreadyCommitted','该记录已提交；新设计须另建任务。');
        local_verify_sources(task,true);local_verify_code(task);
        text=sht_design_point_mdl('read',task.candidateMdl);clock=tic;
        % commit本身就是用户的显式写入操作，默认solve永不进入这里。
        task.commit=sht_design_point_mdl('commit',task.sourceMdl,task.sourceSHA256,text.text);
        task.status='written_verification_pending';local_save(task);
        try
            task.commit.verification=local_committed_test(task);
            task.commit.elapsedSeconds=toc(clock);
            task.status=local_status(task.commit.verification.accepted,'committed_verified','committed_with_findings');
        catch ex
            task.status='committed_test_error';task.commit.error=ex.message;
            local_save(task);rethrow(ex);
        end
        local_save(task);task.export=local_export(task);
    case 'test'
        task=local_load(varargin{1});local_require_candidate(task);local_verify_code(task);
        source='candidate';if numel(varargin)>1,source=varargin{2};end
        clock=tic;
        if strcmp(source,'candidate')
            task.lastTest=local_solver('test',task.config,task.candidateDirectory,task.designState);
        elseif strcmp(source,'committed')
            assert(isfield(task,'commit'),'sht:dp:notCommitted','尚未提交MDL。');
            task.lastTest=local_committed_test(task);
        else,error('sht:dp:testSource','test来源须为candidate或committed。');end
        task.lastTest.source=source;task.lastTest.elapsedSeconds=toc(clock);local_save(task);
        task.export=local_export(task);
    case 'inspect'
        task=local_load(varargin{1});
    case 'export'
        % 历史结果的查看/导出与再次计算分开。只读取原记录，不改其身份。
        task=local_load(varargin{1});
        output=fullfile(varargin{1},'report_outputs');
        if numel(varargin)>1,output=varargin{2};end
        record=fullfile(varargin{1},'MiddleData','design_task.mat');
        task.export=local_export(task,output,record);
    case 'validate'
        % 执行前检查已冻结的私有模型资产；历史查看inspect不依赖源文件。
        task=local_load(varargin{1});local_require_candidate(task);local_verify_code(task);
    otherwise,error('sht:dp:action','未知设计点操作：%s。',action);
end
fprintf('\n设计点任务：%s\n状态：%s\n结果目录：%s\n',task.taskId,task.status,task.taskDirectory);
% 旧记录查看/导出允许缺失结果字段；缺失原因已由export返回，摘要不再抛错。
hasSummary=isfield(task,'config')&&isfield(task.config,'design')&& ...
    isfield(task.config.design,'NpRpm')&&isfield(task.config.design,'NgRpm')&& ...
    isfield(task,'solution')&&isfield(task.solution,'design')&& ...
    isfield(task.solution.design,'maxResidual');
if hasSummary
    fprintf('Np/Ng目标：%.9g / %.9g rpm；设计最大残差：%.6e\n', ...
        task.config.design.NpRpm,task.config.design.NgRpm,task.solution.design.maxResidual);
end
if isfield(task,'parameterComparison')
    disp(task.parameterComparison);
end
if isfield(task,'commit'),fprintf('原MDL备份：%s\n',task.commit.backup);end
end

function task=local_prepare(cfg)
source=fullfile(cfg.sourceDirectory,cfg.modelFile);
m=sht_design_point_mdl('read',source);
sets={{'HPC','HPT','LPT'},{'AC','CC','GT1','GT2','PT1','PT2'}};
components=sets{cfg.modelMode+1};assert(all(ismember(components,m.components)), ...
    'sht:dp:topology','源模型部件与所选拓扑不一致。');
assets=struct('source',{},'relative',{},'sha256',{});
assets=local_add(assets,source,cfg.modelFile);
for n=components
    a=m.assignments(strcmp({m.assignments.component},n{1}) & strcmp({m.assignments.key},'mapPath'));
    assert(numel(a)==1,'sht:dp:map','部件%s必须配置一张MAP。',n{1});
    name=strtrim(a.value);
    assert(isempty(regexp(name,'[\\/:]|\.\.','once')),'sht:dp:map','MAP须为MDL同目录文件名：%s。',name);
    assets=local_add(assets,fullfile(cfg.sourceDirectory,name),name);
end
for n={'GTESS.dll','GTESS.h','blockAndFunctions.h','types_TMATS.H', ...
        'sht_load_engine_library.m',fullfile('matlab_loadlibrary_include','stdio.h')}
    assets=local_add(assets,fullfile(cfg.codeDirectory,n{1}),n{1});
end
if isempty(cfg.taskId),cfg.taskId=['DP_',datestr(now,'yyyymmdd_HHMMSSFFF'),'_',local_uuid()];end
if isempty(cfg.taskDirectory),cfg.taskDirectory=fullfile(cfg.sourceDirectory,'MiddleData','design_point',cfg.taskId);end
root=cfg.taskDirectory;
assert(~isfolder(root)&&~isfile(root),'sht:dp:taskExists','请使用全新的任务目录：%s。',root);
mkdir(root);mkdir(fullfile(root,'MiddleData'));mkdir(fullfile(root,'TestData'));mkdir(fullfile(root,'report_outputs'));
task=struct('schema',26101401,'taskId',cfg.taskId,'taskDirectory',root,'config',cfg, ...
    'sourceMdl',source,'sourceSHA256',m.sha256,'assets',assets,'codeIdentity',local_code_identity(), ...
    'status','prepared','createdAt',datestr(now,31),'accepted',false,'estimatedSeconds',cfg.estimateSeconds);
fprintf('设计点求解及复现粗估 %.0f~%.0f 秒；以实际DLL和收敛情况为准。\n',cfg.estimateSeconds);
end

function a=local_add(a,source,relative)
assert(isfile(source),'sht:dp:missing','缺少依赖：%s。',source);
if ~isempty(a)&&any(strcmp({a.relative},relative)),return;end
a(end+1)=struct('source',source,'relative',relative,'sha256',sht_design_point_mdl('sha256',source));
end

function identity=local_code_identity()
root=fileparts(mfilename('fullpath'));d=[dir(fullfile(root,'*.m'));dir(fullfile(root,'private','*.m'))];
identity=struct('relative',{},'sha256',{});
for k=1:numel(d)
    p=fullfile(d(k).folder,d(k).name);r=p(numel(root)+2:end);
    identity(end+1)=struct('relative',r,'sha256',sht_design_point_mdl('sha256',p)); %#ok<AGROW>
end
end

function local_verify_code(task)
now=local_code_identity();assert(isequal(task.codeIdentity,now),'sht:dp:codeChanged', ...
    '当前设计程序身份与求解时不一致。请保留旧记录并重新求解，不重签旧记录。');
end

function local_verify_sources(task,includeMdl)
for k=1:numel(task.assets)
    a=task.assets(k);if ~includeMdl&&strcmp(a.relative,task.config.modelFile),continue;end
    assert(isfile(a.source)&&strcmpi(sht_design_point_mdl('sha256',a.source),a.sha256), ...
        'sht:dp:sourceChanged','求解后源文件变化或缺失：%s。',a.source);
end
end

function local_copy_runtime(task,target,mdl)
assert(~isfolder(target),'sht:dp:runtimeExists','运行副本目录已存在：%s。',target);mkdir(target);
for i=1:numel(task.assets)
    a=task.assets(i);from=a.source;
    if strcmp(a.relative,task.config.modelFile),from=mdl;end
    if ~strcmp(a.relative,task.config.modelFile)
        assert(isfile(from)&&strcmpi(sht_design_point_mdl('sha256',from),a.sha256), ...
            'sht:dp:runtimeAssetChanged','冻结运行依赖已变化：%s。',from);
    end
    to=fullfile(target,a.relative);parent=fileparts(to);if ~isfolder(parent),mkdir(parent);end
    [ok,msg]=copyfile(from,to);assert(ok,'sht:dp:copy','复制失败：%s。',msg);
    java.io.File(to).setWritable(true);
    assert(strcmpi(sht_design_point_mdl('sha256',from),sht_design_point_mdl('sha256',to)), ...
        'sht:dp:copy','运行副本校验失败：%s。',to);
end
end

function out=local_solver(action,cfg,work,reference)
alias=cfg.interface.alias;
assert(~libisloaded(alias),'sht:dp:libraryOccupied','GTESS已被其他任务占用，请用独立MATLAB进程运行；不会强制卸载。');
oldPath=path;oldDir=pwd;c=onCleanup(@()local_restore(oldPath,oldDir)); %#ok<NASGU>
addpath(work,'-begin');cd(work);
assert(strcmpi(which('sht_load_engine_library'),fullfile(work,'sht_load_engine_library.m')), ...
    'sht:dp:loader','未能选中任务私有加载助手。');
cfg.paths=struct('runtimeDir',work,'dll',fullfile(work,'GTESS.dll'), ...
    'header',fullfile(work,'GTESS.h'),'mdl',fullfile(work,cfg.modelFile),'splitMdl',fullfile(work,cfg.modelFile));
sht_load_engine_library(cfg.paths.dll,cfg.paths.header,'alias',alias,'includepath',work);
try
    solvers={@sht_dp_v1_solver,@sht_dp_v2_solver};
    out=solvers{cfg.modelMode+1}(action,cfg,reference);
catch ex
    try,local_close(alias);catch cleanupError,warning('sht:dp:cleanup','DLL清理失败：%s。',cleanupError.message);end
    rethrow(ex);
end
local_close(alias);
end

function local_close(alias)
if ~libisloaded(alias),return;end
status=calllib(alias,'DLL_SHT_Free');
assert(status==0,'sht:dp:free','DLL释放返回%d。',status);
unloadlibrary(alias);assert(~libisloaded(alias),'sht:dp:unload','DLL仍被指针持有。');
end

function local_restore(oldPath,oldDir)
cd(oldDir);path(oldPath);
end

function edits=local_anchor_edits(c)
edits={'','TtBurnerOut',c.design.targetTt4K; ...
    '','PowerOutLPS',c.design.loadPowerW;'','PowerOutHPS',c.design.accessoryPowerW; ...
    '','altitude',0;'','machNumber',0;'','dTemperature',0; ...
    'Nozzle','aeroThroat',c.design.nozzleAreaM2;'Nozzle','areaExit',c.design.nozzleAreaM2};
if c.modelMode==0
    edits=[edits;{'HPT','NDes',c.design.NgRpm;'LPT','NDes',c.design.NpRpm}];
else
    edits=[edits;{'GT1','NDes',c.design.NgRpm;'GT2','NDes',c.design.NgRpm; ...
        'PT1','NDes',c.design.NpRpm;'PT2','NDes',c.design.NpRpm; ...
        'AC','RlineDes',c.component.AC.RlineDes;'CC','RlineDes',c.component.CC.RlineDes}];
end
end

function edits=local_result_edits(c,d)
edits=[{'','offDesignMode',2;'','varStartVecDime',numel(d.commonVariables); ...
    '','varStartVec',d.commonVariables};local_anchor_edits(c)];
if c.modelMode==0,names={'HPC','HPT','LPT'};s={'HPC','GT','PT'};ncomp=1;
else,names={'AC','CC','GT1','GT2','PT1','PT2'};s=names;ncomp=2;end
for k=1:numel(names)
    if k<=ncomp,keys={'s_C_Nc_in','s_C_Wc_in','s_C_PR_in','s_C_Eff_in'};
    else,keys={'s_T_Nc','s_T_Wc','s_T_PR','s_T_Eff'};end
    values=d.scalars.(s{k});
    for j=1:4,edits(end+1,:)={names{k},keys{j},values(j)};end %#ok<AGROW>
    if c.modelMode==1
        values=d.componentDesignFields.(names{k});
        if k<=ncomp,edits(end+1,:)={names{k},'PRDes',values(1)};end %#ok<AGROW>
        edits(end+1,:)={names{k},'EffDes',values(end)}; %#ok<AGROW>
    end
end
end

function t=local_comparison(source,edits)
rows=cell(0,4);
for i=1:size(edits,1)
    old=sht_design_point_mdl('value',source,edits{i,1},edits{i,2});new=edits{i,3};
    assert(numel(old)==numel(new),'sht:dp:dimension','字段长度不匹配：%s。',edits{i,2});
    for j=1:numel(new)
        name=edits{i,2};if numel(new)>1,name=sprintf('%s(%d)',name,j);end
        rows(end+1,:)={edits{i,1},name,old(j),new(j)}; %#ok<AGROW>
    end
end
t=cell2table(rows,'VariableNames',{'Component','Parameter','SourceValue','CalculatedValue'});
end

function local_replace_private(path,text)
% 仅用于本次新建的运行副本，不承担正式文件提交。
temp=[path,'.new'];sht_design_point_mdl('write_new',temp,text);
[ok,msg]=movefile(temp,path,'f');assert(ok,'sht:dp:privateWrite','%s',msg);
end

function local_require_candidate(task)
assert(isfield(task,'candidateMdl')&&isfield(task,'designState'),'sht:dp:noResult','尚无匹配设计结果。');
assert(strcmpi(sht_design_point_mdl('sha256',task.candidateMdl),task.candidateSHA256), ...
    'sht:dp:candidateChanged','候选MDL已变化，不使用旧设计记录验证。');
for i=1:numel(task.assets)
    a=task.assets(i);if strcmp(a.relative,task.config.modelFile),continue;end
    p=fullfile(task.candidateDirectory,a.relative);
    assert(isfile(p)&&strcmpi(sht_design_point_mdl('sha256',p),a.sha256), ...
        'sht:dp:runtimeAssetChanged','候选运行依赖已变化：%s。',p);
end
end

function out=local_committed_test(task)
local_verify_sources(task,false);
assert(strcmpi(sht_design_point_mdl('sha256',task.sourceMdl),task.commit.writtenSHA256), ...
    'sht:dp:sourceChanged','提交后目标MDL变化，不能把旧结果算作当前通过。');
work=fullfile(task.taskDirectory,'MiddleData',['readback_',local_uuid()]);
local_copy_runtime(task,work,task.sourceMdl);
out=local_solver('test',task.config,work,task.designState);
end

function local_save(task)
path=fullfile(task.taskDirectory,'MiddleData','design_task.mat');
temp=[path,'.new'];save(temp,'task','-v7');movefile(temp,path,'f');
end

function task=local_load(root)
p=fullfile(root,'MiddleData','design_task.mat');assert(isfile(p),'sht:dp:record','找不到任务记录：%s。',p);
s=load(p,'task');task=s.task;assert(task.schema==26101401,'sht:dp:schema','任务版本不匹配。');
end

function receipt=local_export(task,output,record)
% 两张表完整写入唯一临时文件后再发布；失败保留原工作簿与计算MAT。
% 导出回执单独落盘，显式export不得回写旧任务状态或codeIdentity。
if nargin<2,output=fullfile(task.taskDirectory,'report_outputs');end
if nargin<3,record=fullfile(task.taskDirectory,'MiddleData','design_task.mat');end
clock=tic;
receipt=struct('schema','SHT_DESIGN_EXPORT_V1','status','failed','file','', ...
    'recordFile',record,'recordSHA256','','createdAt',datestr(now,31), ...
    'elapsedSeconds',0,'error',struct('identifier','','message',''), ...
    'receiptFile','','receiptError','');
temporary='';
try
    assert(ischar(output)&&isrow(output)&&~isempty(output),'sht:dp:exportPath','导出目录须为非空字符路径。');
    if ~java.io.File(output).isAbsolute(),output=fullfile(pwd,output);end
    output=char(java.io.File(output).getCanonicalPath());
    assert(isfield(task,'parameterComparison')&&istable(task.parameterComparison)&& ...
        all(ismember({'Component','Parameter','SourceValue','CalculatedValue'}, ...
        task.parameterComparison.Properties.VariableNames)), ...
        'sht:dp:exportFields','保存结果缺少完整参数对比表，不能补算或猜测。');
    assert(isfield(task,'config')&&isfield(task.config,'design')&& ...
        isstruct(task.config.design)&&isscalar(task.config.design), ...
        'sht:dp:exportFields','保存结果缺少本次设计目标。');
    d=task.config.design;names=fieldnames(d);values=struct2cell(d);
    assert(~isempty(names)&&all(cellfun(@(v)isnumeric(v)&&isscalar(v)&&isfinite(v),values)), ...
        'sht:dp:exportFields','保存的设计目标不是有限数值标量。');
    receipt.recordSHA256=sht_design_point_mdl('sha256',record);
    if ~isfolder(output),[ok,msg]=mkdir(output);assert(ok,'sht:dp:exportPath','%s',msg);end
    receipt.file=fullfile(output,'design_parameters.xlsx');
    temporary=fullfile(output,['design_parameters.writing_',local_uuid(),'.xlsx']);
    writetable(task.parameterComparison,temporary,'Sheet','MDL_Parameters','UseExcel',false);
    writetable(table(names,cell2mat(values),'VariableNames',{'DesignTarget','Value'}), ...
        temporary,'Sheet','DesignTargets','UseExcel',false);
    assert(~isfolder(receipt.file),'sht:dp:exportPath','目标Excel路径被同名目录占用。');
    [ok,msg]=movefile(temporary,receipt.file,'f');
    assert(ok,'sht:dp:exportPublish','Excel发布失败：%s。',msg);
    receipt.status='saved';
catch ex
    receipt.error=struct('identifier',ex.identifier,'message',ex.message);
    warning('sht:dp:export','计算结果保持不变，Excel导出失败：%s。不需要重新求解。',ex.message);
end
if ~isempty(temporary)&&isfile(temporary)
    try,delete(temporary);catch ex,receipt.receiptError=['临时文件保留：',ex.message];end
end
receipt.elapsedSeconds=toc(clock);
% 即使Excel失败也尽量写回执；回执失败另报，不冒充Excel或计算失败。
if ischar(output)&&isfolder(output)
    receipt.receiptFile=fullfile(output,['design_export_',local_uuid(),'.json']);
    fid=-1;
    try
        fid=fopen(receipt.receiptFile,'w','n','UTF-8');
        assert(fid>=0,'sht:dp:exportReceipt','无法写导出回执。');
        fprintf(fid,'%s',jsonencode(receipt));fclose(fid);fid=-1;
    catch ex
        if fid>=0,fclose(fid);end
        receipt.receiptError=ex.message;
        warning('sht:dp:exportReceipt','导出回执保存失败：%s。请保留返回结构。',ex.message);
    end
end
end

function s=local_status(ok,yes,no)
if ok,s=yes;else,s=no;end
end

function id=local_uuid()
id=char(java.util.UUID.randomUUID());id=id(1:8);
end
