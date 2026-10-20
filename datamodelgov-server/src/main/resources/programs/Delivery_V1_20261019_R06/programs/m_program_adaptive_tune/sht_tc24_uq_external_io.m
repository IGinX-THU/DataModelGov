function varargout=sht_tc24_uq_external_io(method,action,varargin)
% 显式业务输出目录的IO。仅存取新合同，不转换/重签任何历史清单。
% 求解、概率目标、Excel语义仍由原B/C/D实现；此函数不含数值算法。
method=lower(char(method));action=lower(char(action));
if ismember(action,{'preparationidentity','checkpreparationidentity'})
    % 准备身份只描述源码，不依赖输出目录，也不进入精确物理缓存合同。
    assert(strcmp(method,'b'),'TC24:UQ:PreparationMethod','准备身份仅用于方法B。');
    identity=preparationIdentity();
    if strcmp(action,'checkpreparationidentity')
        assert(mod(numel(varargin),2)==0,'TC24:UQ:PreparationArguments','须成对提供结果及来源名称。');
        for k=1:2:numel(varargin)
            value=varargin{k};label=char(varargin{k+1});
            assert(isstruct(value)&&isscalar(value)&&isfield(value,'preparationCodeIdentity'), ...
                'TC24:UQ:PreparationIdentityMissing','%s缺少准备源码身份；旧结果仅可只读，不能续算。',label);
            assert(isequaln(value.preparationCodeIdentity,identity), ...
                'TC24:UQ:PreparationIdentityMismatch','%s的准备源码与当前不同；保留旧文件，使用新任务重新准备。',label);
        end
    end
    varargout{1}=identity;return;
end
if strcmp(action,'selected')
    selected=false;
    if ~isempty(varargin)
        arg=varargin{1};
        selected=isstruct(arg)&&isscalar(arg)&&isfield(arg,'outputDirectory')&&~isempty(arg.outputDirectory);
    end
    varargout{1}=selected;return;
end
if strcmp(action,'assertcachefile')
    file=varargin{1};cfg=varargin{2};p=roots(method,cfg);within(file,p.middleRoot);
    varargout={};return;
end
cfg=varargin{1};p=roots(method,cfg);
switch action
    case 'controlidentity'
        % 业务控制身份绑定全部已选算法预算；回调/输出定位不构成概率变量。
        contract=varargin{2};semantic=cfg;
        ignored={'progressCallback','firstStep','lastStep','resume','enableRunControl', ...
            'outputDirectory','trainingFile','testFile','runtimeDirectory', ...
            'deterministicWorkbookFile','timingHistoryDirectory','timingQuery','runControl'};
        semantic=rmfield(semantic,intersect(fieldnames(semantic),ignored));
        testHash='NOT_REQUESTED';
        if isfield(cfg,'testFile')&&~isempty(cfg.testFile),testHash=sht_steady_model_uq_common('filehash',cfg.testFile);end
        codeNames={'sht_tc24_uq_validation_and_delivery','sht_tc24_uq_method_d', ...
            'sht_tc24_uq_d_difference','sht_tc24_uq_d_curvature','sht_tc24_uq_d_correction', ...
            'sht_steady_model_uq_b_smc','sht_steady_model_uq_c_smc'};
        if strcmp(method,'b')
            preparation=preparationIdentity();
            codeNames=[codeNames,fieldnames(preparation.sourceHash).'];
            codeNames=[codeNames,{'Start_SteadyModelUQ_B_08_BlockExactPosteriorSampling', ...
                'sht_tc24_uq_external_io'}];
        end
        codeIdentity=struct();
        for ci=1:numel(codeNames)
            codeIdentity.(codeNames{ci})=sht_steady_model_uq_common('filehash',which(codeNames{ci}));
        end
        varargout{1}=struct('schemaVersion','TC24_UQ_EXECUTION_V1','method',method, ...
            'contractHash',contract.contractHash,'testHash',testHash,'executionOptions',semantic, ...
            'executionCode',codeIdentity, ...
            'entryHash',sht_steady_model_uq_common('filehash',which('Start_TC24_07_UncertaintyAssessment')), ...
            'dEntryHash',sht_steady_model_uq_common('filehash',which('Start_TC24_07D_QuickAssessment')), ...
            'controlHash',sht_steady_model_uq_common('filehash',which('sht_tc24_run_control')));
    case 'paths'
        make(p.middleRoot);make(p.reportRoot);varargout{1}=p;
    case 'createrun'
        assert(~exist(p.runDir,'dir'),'TC24:UQ:RunExists','本任务UQ目录已存在。');
        make(p.runDir);make(p.reportDir);
        count=6;if strcmp(method,'b'),count=12;end
        m=struct('schemaVersion',['steady_model_uq_method_',method,'_v1'], ...
            'pathSchemaVersion','tc24_explicit_output_v1','method',method, ...
            'outputDirectory',sht_tc24_absolute_path(cfg.outputDirectory),'runId',cfg.runId, ...
            'programRoot',p.programRoot,'runDir',p.runDir,'reportDir',p.reportDir, ...
            'createdAt',datestr(now,30),'updatedAt',datestr(now,30),'status','created', ...
            'completedStep',0,'stepFiles',{cell(count,1)},'stepNames',{cell(count,1)}, ...
            'stepRuntime_s',nan(count,1),'route',cfg.route,'randomSeed',cfg.randomSeed, ...
            'legacyReadOnly',false);
        saveManifest(m);varargout{1}=m;
    case {'resolve','resolvewritable'}
        s=load(fullfile(p.runDir,'manifest.mat'),'manifest');m=s.manifest;
        validate(m,p,method);varargout{1}=m;
    case 'savemanifest'
        validate(cfg,p,method);saveManifest(cfg);
    case 'savestep'
        m=cfg;validate(m,p,method);step=varargin{2};name=char(varargin{3});
        validateattributes(step,{'numeric'},{'scalar','integer','positive','<=',numel(m.stepFiles)});
        assert(~isempty(regexp(name,'^[A-Za-z0-9_]+$','once')),'TC24:UQ:Leaf','步骤名非法。');
        payload=varargin{4};runtime=varargin{5};
        file=fullfile(p.runDir,sprintf('step%02d_%s.mat',step,name));within(file,p.runDir);
        save(file,'payload','-v7.3');
        m.stepFiles{step}=file;m.stepNames{step}=name;m.stepRuntime_s(step)=runtime;
        m.completedStep=max(m.completedStep,step);m.status=sprintf('step_%02d_complete',step);
        m.updatedAt=datestr(now,30);saveManifest(m);varargout={m,file};
    case 'loadstep'
        validate(cfg,p,method);step=varargin{2};
        validateattributes(step,{'numeric'},{'scalar','integer','positive','<=',numel(cfg.stepFiles)});
        file=cfg.stepFiles{step};assert(~isempty(file),'TC24:UQ:StepMissing','缺少UQ步骤%d。',step);
        within(file,p.runDir);s=load(file,'payload');varargout{1}=s.payload;
    case {'reportfile','runfile'}
        validate(cfg,p,method);name=char(varargin{2});
        [folder,base,ext]=fileparts(name);
        assert(isempty(folder)&&strcmp(name,[base,ext])&&~ismember(name,{'.','..'}) ...
            &&~isempty(name),'TC24:UQ:Leaf','输出只能为叶文件名。');
        dir=p.runDir;if strcmp(action,'reportfile'),dir=p.reportDir;end
        file=fullfile(dir,name);within(file,dir);varargout{1}=file;
    otherwise
        error('TC24:UQ:ExternalIoAction','显式任务目录不支持动作%s。',action);
end
end
function identity=preparationIdentity()
names={'Start_SteadyModelUQ_B_05_ExactLikelihoodVerification', ...
    'Start_SteadyModelUQ_B_06_GlobalExactPilot', ...
    'Start_SteadyModelUQ_B_07_DefensiveProposalAdaptation', ...
    'sht_tc24_prepare_b_proposal','sht_tc24_uq_d_proposal_anchor'};
sourceHash=struct();
for k=1:numel(names)
    file=which(names{k});
    assert(~isempty(file),'TC24:UQ:PreparationSourceMissing','找不到准备源码：%s。',names{k});
    sourceHash.(names{k})=sht_steady_model_uq_common('filehash',file);
end
identity=struct('schemaVersion','TC24_B_PREPARATION_SOURCE_V1','sourceHash',sourceHash);
end
function p=roots(method,cfg)
assert(isstruct(cfg)&&isfield(cfg,'outputDirectory')&&~isempty(cfg.outputDirectory), ...
    'TC24:UQ:OutputRequired','缺少显式输出根。');
assert(isfield(cfg,'runId')&&~isempty(regexp(cfg.runId,'^[A-Za-z0-9][A-Za-z0-9_-]*$','once')), ...
    'TC24:UQ:RunId','runId非法。');
root=fullfile(sht_tc24_absolute_path(cfg.outputDirectory),cfg.runId);
p=struct('programRoot',fileparts(mfilename('fullpath')),'projectRoot',root);
p.middleRoot=fullfile(root,'MiddleData',['uq_',method]);
p.reportRoot=fullfile(root,'report_outputs',['uq_',method]);
p.runDir=fullfile(p.middleRoot,cfg.runId);p.reportDir=fullfile(p.reportRoot,cfg.runId);
p.latestFile=fullfile(p.middleRoot,'latest_manifest.mat');
within(p.runDir,root);within(p.reportDir,root);
end
function validate(m,p,method)
assert(isfield(m,'pathSchemaVersion')&&strcmp(m.pathSchemaVersion,'tc24_explicit_output_v1') ...
    &&isfield(m,'method')&&strcmp(m.method,method) ...
    &&strcmp(m.schemaVersion,['steady_model_uq_method_',method,'_v1']) ...
    &&~m.legacyReadOnly,'TC24:UQ:ReadOnly','非本接口新清单，禁止续写或迁移旧清单。');
assert(strcmpi(sht_tc24_absolute_path(m.runDir),p.runDir)&& ...
    strcmpi(sht_tc24_absolute_path(m.reportDir),p.reportDir), ...
    'TC24:UQ:Boundary','清单目录与本次显式输出根不一致。');
for k=1:numel(m.stepFiles),if ~isempty(m.stepFiles{k}),within(m.stepFiles{k},p.runDir);end,end
end
function within(file,root)
file=sht_tc24_absolute_path(file);root=sht_tc24_absolute_path(root);
assert(strncmpi(file,[root,filesep],numel(root)+1), ...
    'TC24:UQ:Boundary','文件必须在本任务许可目录内部：%s',file);
end
function make(folder)
if ~exist(folder,'dir'),[ok,msg]=mkdir(folder);assert(ok,'TC24:UQ:Mkdir','%s',msg);end
end
function saveManifest(manifest)
% 不更新主目录latest；只有本run的清单可写。
save(fullfile(manifest.runDir,'manifest.mat'),'manifest');
end
