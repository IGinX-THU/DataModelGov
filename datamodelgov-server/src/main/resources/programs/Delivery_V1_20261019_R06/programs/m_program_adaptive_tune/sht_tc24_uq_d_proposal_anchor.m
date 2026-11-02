function [candidate,source,audit]=sht_tc24_uq_d_proposal_anchor(contract)
% 可选D位置只辅助B的提议；不读取D区间，也不替换B的先验或似然。
% 新业务显式给出D的输出根、runId和步骤1/3的SHA；缺失/错配立即报错，
% 不搜索latest或回退历史目录。仅旧式显式runId保留原只读对照方式。
candidate=[];source='';cfg=contract.config;
audit=struct('candidateProvided',false,'targetPriorReplaced',false);
hasId=present(cfg,'dProposalRunId');
hasDirectory=present(cfg,'dProposalOutputDirectory');
hasHashes=present(cfg,'dProposalStepSHA256');
if ~hasId
    assert(~hasDirectory && ~hasHashes,'TC24:Proposal:DConfiguration', ...
        'D目录或SHA已配置，但缺少dProposalRunId；禁止自动选择历史结果。');
    return;
end
id=textValue(cfg.dProposalRunId,'dProposalRunId');
assert(~isempty(regexp(id,'^tc24_d_[A-Za-z0-9_-]+$','once')), ...
    'TC24:Proposal:DRunId','D辅助runId必须为明确的tc24_d_标识。');
request=struct('runId',id);expected={};
if hasDirectory
    assert(hasHashes,'TC24:Proposal:DConfiguration', ...
        '独立D目录必须同时给定步骤1/3的dProposalStepSHA256。');
    request.outputDirectory=sht_tc24_absolute_path( ...
        textValue(cfg.dProposalOutputDirectory,'dProposalOutputDirectory'));
    expected=cfg.dProposalStepSHA256;
    if isstring(expected),expected=cellstr(expected);end
    assert(iscell(expected) && numel(expected)==2,'TC24:Proposal:DStepHash', ...
        'dProposalStepSHA256必须按步骤1、3顺序给出两个SHA256。');
    expected=expected(:);
    for k=1:2
        expected{k}=textValue(expected{k},'dProposalStepSHA256');
        assert(~isempty(regexp(expected{k},'^[A-Fa-f0-9]{64}$','once')), ...
            'TC24:Proposal:DStepHash','D步骤SHA256格式错误。');
    end
else
    assert(~hasHashes,'TC24:Proposal:DConfiguration', ...
        '配置步骤SHA时必须同时指定dProposalOutputDirectory，不得忽略该配置。');
end
manifest=sht_steady_model_uq_c_io('resolve',request);
assert(strcmp(manifest.runId,id),'TC24:Proposal:DRunId','D清单runId与请求不一致。');
if hasDirectory,verifyFiles(manifest,expected);end
s=sht_steady_model_uq_c_io('loadstep',manifest,1);
d=sht_steady_model_uq_c_io('loadstep',manifest,3);
% 前后均校核原文件，避免在读取期间被另一个任务替换。
if hasDirectory,verifyFiles(manifest,expected);end
assert(isstruct(s)&&isscalar(s)&&isfield(s,'contract')&& ...
    isstruct(d)&&isscalar(d)&&isfield(d,'map'), ...
    'TC24:Proposal:DIdentity','D步骤1/3缺少合同或参数位置。');
n=s.contract.parameterCount;
assert(isnumeric(n)&&isscalar(n)&&isfinite(n)&&n==floor(n)&& ...
    n>=1&&n<=contract.parameterCount&& ...
    height(s.contract.parameterTable)==n&&height(contract.parameterTable)==contract.parameterCount, ...
    'TC24:Proposal:DDimension','D与B参数维数或字典行数不一致。');
assert(isnumeric(d.map)&&isreal(d.map)&&isvector(d.map)&& ...
    numel(d.map)==n&&all(isfinite(d.map(:))), ...
    'TC24:Proposal:DDimension','D参数位置必须是维数正确的有限实数向量。');
assert(strcmp(s.contract.deterministicWorkbookSha256,contract.deterministicWorkbookSha256) && ...
    strcmp(s.contract.route,contract.route) && s.contract.modelMode==contract.modelMode && ...
    isequal({s.contract.engineArtifacts.sha256},{contract.engineArtifacts.sha256}) && ...
    isequaln(s.contract.trainingData,contract.trainingData) && ...
    isequal(string(s.contract.parameterTable.name),string(contract.parameterTable.name(1:n))) && ...
    isequal(s.contract.lowerBound,contract.lowerBound(1:n)) && ...
    isequal(s.contract.upperBound,contract.upperBound(1:n)), ...
    'TC24:Proposal:DIdentity','D辅助位置与当前参数/边界/数据/发动机资产身份不匹配。');
% D可使用不同的工程先验寻找候选位置；这不改变B的概率目标。
% 标准差各自仍须合法，但不把“先验相同”误当成“物理参数相同”。
validSigma(s.contract.priorSigma,n,'D');
validSigma(contract.priorSigma,contract.parameterCount,'B');
dSigma=s.contract.priorSigma(:);bSigma=contract.priorSigma(1:n);bSigma=bSigma(:);
audit.dPriorSigma=dSigma;audit.bPriorSigma=bSigma;
audit.priorSigmaEqual=isequal(dSigma,bSigma);
audit.priorSigmaDifference=dSigma-bSigma;
audit.maximumRelativeSigmaDifference=max(abs(dSigma./bSigma-1));
% 名称相同仍须防止节点坐标、C索引或单位发生变化；旧表无这些列时保持兼容。
fields={'coordinate','c_index','unit'};
for k=1:numel(fields)
    f=fields{k};a=ismember(f,s.contract.parameterTable.Properties.VariableNames);
    b=ismember(f,contract.parameterTable.Properties.VariableNames);
    assert(a==b,'TC24:Proposal:DIdentity','D/B字典字段%s不一致。',f);
    if a
        assert(isequaln(s.contract.parameterTable.(f),contract.parameterTable.(f)(1:n,:)), ...
            'TC24:Proposal:DIdentity','D/B字典字段%s不匹配。',f);
    end
end
if isfield(s.contract,'config')&&isfield(s.contract.config,'runId')
    assert(strcmp(s.contract.config.runId,id),'TC24:Proposal:DRunId', ...
        'D步骤合同runId与清单不一致。');
end
if isfield(d,'numericalConfiguration')&&isfield(d.numericalConfiguration,'contractHash')
    assert(isfield(s.contract,'contractHash')&& ...
        strcmp(d.numericalConfiguration.contractHash,s.contract.contractHash), ...
        'TC24:Proposal:DIdentity','D参数位置与D步骤1合同不匹配。');
end
if isfield(contract,'referencePoint'),candidate=contract.referencePoint;else,candidate=contract.thetaHat;end
assert(isnumeric(candidate)&&isreal(candidate)&&isvector(candidate)&& ...
    numel(candidate)==contract.parameterCount&&all(isfinite(candidate(:))), ...
    'TC24:Proposal:DDimension','B参考位置维数或数值无效。');
candidate=candidate(:);candidate(1:n)=d.map(:);
assert(all(candidate>contract.lowerBound & candidate<contract.upperBound), ...
    'TC24:Proposal:DBoundary','D点不在可计算提议密度的内部支持域。');
source=['optional_D_location_',id];
audit.candidateProvided=true;audit.source=source;
audit.dParameterCount=n;audit.bParameterCount=contract.parameterCount;
audit.extraBParametersPreserved=true;
if isfield(d,'converged'),audit.dConverged=d.converged;end
if isfield(d,'stopReason'),audit.dStopReason=d.stopReason;end
end

function validSigma(value,count,label)
assert(isnumeric(value)&&isreal(value)&&isvector(value)&&numel(value)==count&& ...
    all(isfinite(value(:)))&&all(value(:)>0),'TC24:Proposal:DPriorScale', ...
    '%s先验标准差必须是维数正确的有限正实数向量。',label);
end

function verifyFiles(manifest,expected)
steps=[1,3];
assert(isfield(manifest,'stepFiles')&&numel(manifest.stepFiles)>=3, ...
    'TC24:Proposal:DStepMissing','D清单缺少步骤文件记录。');
for k=1:2
    file=manifest.stepFiles{steps(k)};
    assert(~isempty(file)&&isfile(file),'TC24:Proposal:DStepMissing', ...
        'D步骤%d文件不存在，禁止回退历史结果。',steps(k));
    actual=sht_steady_model_uq_common('filehash',file);
    assert(strcmpi(actual,expected{k}),'TC24:Proposal:DStepHash', ...
        'D步骤%d文件SHA与显式配置不符。',steps(k));
end
end

function yes=present(s,f)
yes=isfield(s,f)&&~isempty(s.(f));
end

function value=textValue(value,label)
assert((ischar(value)&&isrow(value))||(isstring(value)&&isscalar(value)), ...
    'TC24:Proposal:DConfiguration','%s必须为单个文本值。',label);
value=char(value);
assert(~isempty(strtrim(value)),'TC24:Proposal:DConfiguration','%s不得为空白。',label);
end
