function out=sht_f3_business_identity(action,varargin)
%SHT_F3_BUSINESS_IDENTITY 业务编号取证与绑定，不进行任何模型或概率计算。
% resolve接收已选择文件的事实记录和调用者声明；同名编号必须一致。
% 缺少事实编号时必须给出值及逐字段依据。父架次不是当前架次，调用方
% 必须按角色筛选字段，不能把父文件的sortie_id直接继承为本次架次。
switch lower(char(action))
    case 'resolve'
        out=local_resolve(varargin{:});
    case 'workbook'
        out=local_workbook(varargin{1});
    case 'table'
        out=local_table(varargin{1});
    otherwise
        error('SHT:F3Identity:Action','未知业务编号操作：%s。',char(action));
end
end

function out=local_resolve(evidence,user,scope)
% UQ保持原四字段；确定性任务不应虚构父后验编号。
if nargin<3,scope='uq';end
assert(ismember(scope,{'uq','deterministic'}),'SHT:F3Identity:Scope','未知身份范围。');
fields={'engineId','sortieId','parentModelId','parentPosteriorId'};
if strcmp(scope,'deterministic'),fields={'engineId','sortieId','parentModelId','modelId'};end
if nargin<2||isempty(user),user=struct();end
assert(isstruct(user)&&isscalar(user)&& ...
    all(ismember(fieldnames(user),[fields,{'purpose','basis'}])), ...
    'SHT:F3Identity:Configuration','businessIdentity含未知字段或不是标量结构体。');
purpose='production';if isfield(user,'purpose'),purpose=local_text(user.purpose,'purpose');end
assert(ismember(purpose,{'production','test_fixture'}), ...
    'SHT:F3Identity:Purpose','purpose只能为production或test_fixture。');
basis=struct();if isfield(user,'basis'),basis=user.basis;end
assert(isstruct(basis)&&isscalar(basis)&&all(ismember(fieldnames(basis),fields)), ...
    'SHT:F3Identity:Basis','依据basis必须按编号字段给出。');
assert(isstruct(evidence),'SHT:F3Identity:Evidence','事实记录必须为结构体数组。');
rows=struct('field',{},'value',{},'source',{},'sourceField',{},'sha256',{},'basis',{});
out=struct('schemaVersion','F3_BUSINESS_IDENTITY_V1','purpose',purpose);
if strcmp(scope,'deterministic'),out.scope=scope;end
for k=1:numel(fields)
    f=fields{k};value='';
    for j=1:numel(evidence)
        e=evidence(j);
        assert(all(isfield(e,{'source','sha256','values'}))&&isstruct(e.values)&&isscalar(e.values), ...
            'SHT:F3Identity:Evidence','每条事实需提供source、sha256和values。');
        if ~isfield(e.values,f),continue;end
        candidate=local_text(e.values.(f),f);
        if isempty(candidate),continue;end
        source=local_text(e.source,'source');sha=local_text(e.sha256,'sha256');
        assert(~isempty(source)&&~isempty(regexp(sha,'^[a-fA-F0-9]{64}$','once')), ...
            'SHT:F3Identity:Evidence','事实编号必须绑定来源及文件SHA256。');
        local_same(value,candidate,f,source);value=candidate;
        sourceField=f;
        if isfield(e,'sourceFields')&&isfield(e.sourceFields,f)
            sourceField=local_text(e.sourceFields.(f),'sourceField');
        end
        rows(end+1)=struct('field',f,'value',candidate,'source',source,'sourceField',sourceField, ...
            'sha256',sha,'basis','selected_evidence'); %#ok<AGROW>
    end
    configured='';if isfield(user,f),configured=local_text(user.(f),f);end
    if ~isempty(configured)
        local_same(value,configured,f,'configuration.businessIdentity');
        note='';if isfield(basis,f),note=local_text(basis.(f),['basis.' f]);end
        assert(~isempty(value)||~isempty(note),'SHT:F3Identity:MissingBasis', ...
            '所选证据缺少%s，显式赋值必须同时填写businessIdentity.basis.%s说明依据。',f,f);
        if isempty(note),note='explicit_confirmation_of_selected_evidence';end
        rows(end+1)=struct('field',f,'value',configured,'source','configuration.businessIdentity','sourceField',f, ...
            'sha256','','basis',note); %#ok<AGROW>
        value=configured;
    end
    assert(~isempty(value),'SHT:F3Identity:Missing', ...
        '所选证据没有%s；请在businessIdentity中显式提供编号及依据，不能使用开发默认编号。',f);
    if strcmp(purpose,'production')
        defaults={'SHT_PERSONALIZED_ENGINE_001','F31-CAL-01','T24_METHOD_C_STEADY','TC24_C_TRANSIENT_INSTANT_R040'};
        assert(~ismember(value,defaults)&&~startsWith(upper(value),'TEST_FIXTURE'), ...
            'SHT:F3Identity:TestIdentity','生产业务不能使用开发默认或测试标签：%s=%s。',f,value);
    end
    out.(f)=value;
end
out.evidence=rows;
out.productionIdentity=strcmp(purpose,'production');
end

function local_same(existing,candidate,field,source)
assert(isempty(existing)||strcmp(existing,candidate),'SHT:F3Identity:Conflict', ...
    '业务编号冲突：%s，已选证据为%s，%s提供%s。请核对文件/配置，不会静默覆盖。', ...
    field,existing,source,candidate);
end

function value=local_text(value,name)
assert((ischar(value)&&(isrow(value)||isempty(value)))|| ...
    (isstring(value)&&isscalar(value)&&~ismissing(value)), ...
    'SHT:F3Identity:Text','%s必须为文本编号，避免数值转换丢失前导零。',name);
value=strtrim(char(value));
assert(~any(value==char(10)|value==char(13)),'SHT:F3Identity:Text','%s不能包含换行。',name);
end

function out=local_workbook(file)
% 只读取身份表，不载入样本、训练数据或运行DLL。兼容单行Manifest和键值Model。
assert(isfile(file),'SHT:F3Identity:File','所选文件不存在：%s。',file);
[~,sheets]=xlsfinfo(file);out=struct();
names={'engine_id','sortie_id','run_id','model_id','posterior_id', ...
    'parent_model_id','parent_posterior_id','deterministic_run_id', ...
    'deterministic_workbook_sha256'};
for sheet={'Manifest','Model'}
    if ~ismember(sheet{1},sheets),continue;end
    t=readtable(file,'Sheet',sheet{1},'PreserveVariableNames',true);
    for k=1:numel(names)
        name=names{k};value='';
        if ismember(name,t.Properties.VariableNames)&&height(t)==1
            v=t.(name);
            if iscell(v)&&numel(v)==1,v=v{1};end
            if (isnumeric(v)&&isscalar(v)&&isnan(v))|| ...
                (isstring(v)&&isscalar(v)&&ismissing(v)),continue;end
            value=local_text(v,name);
        elseif all(ismember({'key','value'},t.Properties.VariableNames))
            hit=find(strcmp(string(t.key),name));
            assert(numel(hit)<=1,'SHT:F3Identity:Duplicate','%s表存在重复编号键%s。',sheet{1},name);
            if ~isempty(hit)
                v=t.value(hit);if iscell(v),v=v{1};end
                if isstring(v)&&ismissing(v),continue;end
                value=local_text(v,name);
            end
        end
        if isempty(value),continue;end
        if isfield(out,name),local_same(out.(name),value,name,sheet{1});end
        out.(name)=value;
    end
end
end

function out=local_table(binding)
assert(isstruct(binding)&&isscalar(binding)&&isfield(binding,'evidence'), ...
    'SHT:F3Identity:Binding','导出需要已解析的业务编号证据。');
e=binding.evidence;
out=table(string({e.field}.'),string({e.value}.'),string({e.source}.'),string({e.sourceField}.'), ...
    string({e.sha256}.'),string({e.basis}.'), ...
    repmat(string(binding.purpose),numel(e),1), ...
    'VariableNames',{'identity_field','identity_value','source','source_field','artifact_sha256','basis','purpose'});
end
