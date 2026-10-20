function out = sht_design_point_mdl(action,varargin)
%SHT_DESIGN_POINT_MDL MDL字段级处理与显式备份写入，不解析命令行输出。
% edits为N行3列cell：部件名(全局用空串)、字段名、有限数值向量。
% 读写保持原换行及未涉及行；拒绝重复部件、重复字段和含糊配置。
switch lower(action)
    case 'read'
        out=local_read(varargin{1});
    case 'value'
        m=local_read(varargin{1});idx=local_find(m,varargin{2},varargin{3});
        out=sscanf(m.assignments(idx).value,'%f').';
        assert(~isempty(out)&&all(isfinite(out)),'sht:dp:mdlValue','字段不是有限数值。');
    case 'edit'
        m=local_read(varargin{1});edits=varargin{2};out=m.text;
        % 从后往前替换，保留其他行的字节及位置。
        indices=zeros(size(edits,1),1);
        for i=1:size(edits,1)
            indices(i)=local_find(m,edits{i,1},edits{i,2});
            validateattributes(edits{i,3},{'numeric'},{'vector','nonempty','finite'});
        end
        assert(numel(unique(indices))==numel(indices),'sht:dp:duplicateEdit','同一字段不能重复更新。');
        [~,order]=sort([m.assignments(indices).start],'descend');
        for k=order(:).'
            a=m.assignments(indices(k));v=strtrim(sprintf('%.17g ',edits{k,3}));
            out=[out(1:a.start-1),a.prefix,v,a.suffix,out(a.stop+1:end)]; %#ok<AGROW>
        end
    case 'write_new'
        path=varargin{1};assert(~isfile(path),'sht:dp:exists','不覆盖已有文件：%s。',path);
        local_write(path,varargin{2});out=local_read(path);
    case 'sha256'
        out=local_sha(varargin{1});
    case 'commit'
        target=varargin{1};expected=varargin{2};text=varargin{3};
        assert(isfile(target),'sht:dp:target','目标MDL不存在：%s。',target);
        lock=[target,'.design_point.lock'];lf=java.io.File(lock);
        assert(lf.createNewFile(),'sht:dp:locked','目标已有设计写入任务：%s。',lock);
        unlock=onCleanup(@()local_delete(lock)); %#ok<NASGU>
        assert(strcmpi(local_sha(target),expected),'sht:dp:sourceChanged','预览后目标MDL已变化，拒绝覆盖：%s。',target);
        suffix=[datestr(now,'yyyymmdd_HHMMSSFFF'),'_',char(java.util.UUID.randomUUID())];
        backup=[target,'.backup_',suffix];temp=[target,'.pending_',suffix];
        [ok,msg]=copyfile(target,backup);assert(ok,'sht:dp:backup','备份失败：%s。',msg);
        assert(strcmpi(local_sha(backup),expected),'sht:dp:backup','备份字节校验失败，不写入。');
        local_write(temp,text);local_read(temp);
        wanted=local_sha(temp);
        assert(strcmpi(local_sha(target),expected),'sht:dp:sourceChanged','备份期间目标变化，拒绝覆盖。');
        [ok,msg]=movefile(temp,target,'f');
        assert(ok,'sht:dp:replace','替换失败：%s。原字节备份：%s。',msg,backup);
        assert(strcmpi(local_sha(target),wanted),'sht:dp:readback','写入读回不一致。备份：%s。',backup);
        out=struct('target',target,'backup',backup,'previousSHA256',expected, ...
            'writtenSHA256',wanted,'writtenAt',datestr(now,31),'verification','not_run');
    otherwise,error('sht:dp:mdlAction','未知MDL操作：%s。',action);
end
end

function m=local_read(path)
fid=fopen(path,'rb');assert(fid>=0,'sht:dp:read','不能读取：%s。',path);
c=onCleanup(@()fclose(fid));bytes=fread(fid,Inf,'*uint8').';clear c;
text=native2unicode(bytes,'GBK');
assert(isequal(unicode2native(text,'GBK'),bytes),'sht:dp:encoding','MDL编码不能无损读写：%s。',path);
[lines,starts,ends]=regexp(text,'[^\r\n]+','match','start','end');
components={};current='';a=struct('component',{},'key',{},'value',{},'start',{},'stop',{},'prefix',{},'suffix',{});
for i=1:numel(lines)
    t=regexp(lines{i},'^\s*\[componentName\]\s*=\s*(.*?)\s*$','tokens','once');
    if ~isempty(t)
        current=t{1};assert(~ismember(current,components),'sht:dp:duplicateComponent','重复部件：%s。',current);
        components{end+1}=current;continue; %#ok<AGROW>
    end
    t=regexp(lines{i},'^\s*(?<key>[A-Za-z][A-Za-z0-9_/]*)\s*=\s*(?<value>.*?)\s*$','names','once');
    if isempty(t),continue;end
    prefix=regexp(lines{i},'^\s*[A-Za-z][A-Za-z0-9_/]*\s*=\s*','match','once');
    suffix=regexp(lines{i},'\s*$','match','once');
    a(end+1)=struct('component',current,'key',t.key,'value',t.value, ...
        'start',starts(i),'stop',ends(i),'prefix',prefix,'suffix',suffix); %#ok<AGROW>
end
for i=1:numel(a)
    assert(sum(strcmp({a.component},a(i).component)&strcmp({a.key},a(i).key))==1, ...
        'sht:dp:duplicateField','重复字段：%s.%s。',a(i).component,a(i).key);
end
m=struct('path',path,'text',text,'components',{components},'assignments',a,'sha256',local_sha(path));
end

function i=local_find(m,component,key)
i=find(strcmp({m.assignments.component},component)&strcmp({m.assignments.key},key));
assert(isscalar(i),'sht:dp:missingField','MDL应唯一包含字段%s.%s：%s。',component,key,m.path);
end

function local_write(path,text)
bytes=unicode2native(text,'GBK');
assert(strcmp(native2unicode(bytes,'GBK'),text),'sht:dp:encoding','待写MDL含GBK不可表示字符。');
fid=fopen(path,'wb');assert(fid>=0,'sht:dp:write','不能写入：%s。',path);
c=onCleanup(@()fclose(fid));n=fwrite(fid,bytes,'uint8');
assert(n==numel(bytes),'sht:dp:write','文件写入不完整：%s。',path);clear c;
end

function h=local_sha(path)
fid=fopen(path,'rb');assert(fid>=0,'sht:dp:read','不能读取：%s。',path);
c=onCleanup(@()fclose(fid));d=java.security.MessageDigest.getInstance('SHA-256');
while ~feof(fid),b=fread(fid,1048576,'*uint8');if ~isempty(b),d.update(b);end;end
h=upper(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end

function local_delete(path)
if isfile(path),delete(path);end
end
