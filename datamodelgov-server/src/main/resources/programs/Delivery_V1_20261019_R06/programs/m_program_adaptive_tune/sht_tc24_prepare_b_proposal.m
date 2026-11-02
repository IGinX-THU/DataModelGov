function [cfg,audit]=sht_tc24_prepare_b_proposal(cfg,user)
% 为B提供当前训练数据的辅助候选位置，B原先验及似然保持不变。
% compute：运行D至第3步；read：按显式runId/目录/SHA读取；none：不使用D。
% 此处不选择真值，不搜索latest，不从旧后验暗取位置，不复制采样算法。
if nargin<2,user=struct();end
timer=tic;
mode='compute';
if isfield(user,'dProposalMode') && ~isempty(user.dProposalMode)
    mode=char(user.dProposalMode);
elseif isfield(cfg,'dProposalRunId') && ~isempty(cfg.dProposalRunId)
    mode='read';
end
assert(ismember(mode,{'compute','read','none'}),'TC24:Proposal:Mode', ...
    'dProposalMode只能为compute、read或none。');
audit=struct('mode',mode,'runtimeSeconds',0,'priorReplaced',false, ...
    'likelihoodReplaced',false,'computedThisSession',false);
fields={'dProposalRunId','dProposalOutputDirectory','dProposalStepSHA256'};
if strcmp(mode,'none')
    for k=1:numel(fields)
        assert(~isfield(cfg,fields{k}) || isempty(cfg.(fields{k})), ...
            'TC24:Proposal:Configuration','none模式不能同时提供D来源字段。');
    end
    return;
end
if strcmp(mode,'compute')
    for k=1:numel(fields)
        assert(~isfield(user,fields{k}) || isempty(user.(fields{k})), ...
            'TC24:Proposal:Configuration','compute模式不能同时指定外部D来源。');
    end
    root='';
    if isfield(cfg,'outputDirectory'),root=cfg.outputDirectory;end
    if isempty(root)
        paths=sht_steady_model_uq_b_io('paths');root=paths.middleRoot;
    end
    droot=fullfile(sht_tc24_absolute_path(root),'proposal_preparation');
    id=['tc24_d_',regexprep(cfg.runId,'^tc24_','')];
    request=struct('runId',id,'outputDirectory',droot);
    % 使用现有external IO的既定层级；只读检查，不先调用会创建目录的paths动作。
    existing=isfile(fullfile(droot,id,'MiddleData','uq_c',id,'manifest.mat'));
    continuation=(isfield(user,'resume') && user.resume) || ...
        (isfield(user,'firstStep') && user.firstStep>1);
    assert(~existing || continuation,'TC24:Proposal:RunExists', ...
        'D准备目录已存在；请新建runId或显式恢复，不能覆盖旧准备。');
    incomplete=true;
    if existing
        previous=sht_steady_model_uq_c_io('resolve',request);
        incomplete=previous.completedStep<3;
    end
    if ~existing || incomplete
        dcfg=cfg;
        dcfg.runId=id;dcfg.outputDirectory=droot;dcfg.firstStep=1;dcfg.lastStep=3;
        dcfg.testFile='';dcfg.syntheticValidationFile='';dcfg.plotEnabled=false;
        dcfg.predictionTrainingEnabled=false;dcfg.skipValidation=true;
        % D准备独立使用现有协作停止协议；不强杀，不另写D求解器。
        dcfg.enableRunControl=isfield(user,'enableRunControl')&&logical(user.enableRunControl);
        controlFile=fullfile(droot,id,'run_control','identity.mat');
        dcfg.resume=continuation&&dcfg.enableRunControl&&isfile(controlFile);
        dcfg.maxIterations=3;
        % 与当前数据D辅助位置验证批次一致；这些选项不改变B先验或似然。
        dcfg.differenceMode='forward';dcfg.curveBendScale=.50;
        dcfg.randomSeed=20260910;dcfg.localSampleCount=512;
        dcfg.nuisanceAnchorMode='two_anchor';
        dcfg.curvatureRefinement=false;dcfg.nonlinearCorrection=false;
        if isfield(user,'dProposalMaxIterations')
            dcfg.maxIterations=user.dProposalMaxIterations;
        end
        validateattributes(dcfg.maxIterations,{'numeric'}, ...
            {'scalar','integer','positive','finite'});
        if isfield(dcfg,'runControl'),dcfg=rmfield(dcfg,'runControl');end
        if isfield(user,'progressCallback'),dcfg.progressCallback=user.progressCallback;end
        dresult=Start_TC24_07D_QuickAssessment(dcfg);
        audit.computedThisSession=true;
        if isfield(dresult,'status') && strcmp(dresult.status,'stopped')
            audit.stopped=true;audit.childResult=dresult;audit.runtimeSeconds=toc(timer);
            return;
        end
    end
    manifest=sht_steady_model_uq_c_io('resolve',request);
    assert(numel(manifest.stepFiles)>=3 && ~isempty(manifest.stepFiles{3}), ...
        'TC24:Proposal:DStepMissing','D准备未完成第三步，不能作为辅助位置。');
    cfg.dProposalRunId=id;cfg.dProposalOutputDirectory=droot;
    cfg.dProposalStepSHA256={ ...
        sht_steady_model_uq_common('filehash',manifest.stepFiles{1}), ...
        sht_steady_model_uq_common('filehash',manifest.stepFiles{3})};
else
    assert(isfield(cfg,'dProposalRunId') && ~isempty(cfg.dProposalRunId), ...
        'TC24:Proposal:Configuration','read模式必须指定D运行标识。');
end
% 读取和新计算都经过同一物理参数、数据、运行包及SHA检查。
contract=sht_steady_model_uq_b_common('buildcontract', ...
    sht_steady_model_uq_b_common('defaultconfig',cfg));
[~,source,identity]=sht_tc24_uq_d_proposal_anchor(contract);
audit.source=source;audit.identity=identity;audit.runtimeSeconds=toc(timer);
audit.runId=cfg.dProposalRunId;
if isfield(cfg,'dProposalOutputDirectory'),audit.outputDirectory=cfg.dProposalOutputDirectory;end
if isfield(cfg,'dProposalStepSHA256'),audit.stepSHA256=cfg.dProposalStepSHA256;end
fprintf('TC24 B提议准备：%s，%.1f s；B先验/似然保持不变。\n',mode,audit.runtimeSeconds);
end
