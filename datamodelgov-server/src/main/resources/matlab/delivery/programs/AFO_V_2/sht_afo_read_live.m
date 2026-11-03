function out=sht_afo_read_live(folder,afterSeq,expectedSessionId,maxRows)
%SHT_AFO_READ_LIVE 无DLL的增量历史读取；界面断开后从最后序号补读。
% 只接收原子发布文件。未知会话、字典不一致、序号缺口均明确报错。
% maxRows限制每次返回内存量，不删原始样本；重复请求产生相同数据。
if nargin<2,afterSeq=0;end
if nargin<3,expectedSessionId='';end
if nargin<4,maxRows=2048;end
validateattributes(afterSeq,{'double'},{'scalar','nonnegative','integer','finite'});
validateattributes(maxRows,{'double'},{'scalar','positive','integer','finite'});
s=sht_afo_read_json(fullfile(folder,'status.json'));
assert(strcmp(s.schema,'SHT_AFO_STATUS_V2'),'不支持的状态格式。');
if ~isempty(expectedSessionId),assert(strcmp(s.sessionId,expectedSessionId),'会话改变，不能合并轨迹。');end
c=sht_afo_read_json(fullfile(folder,'channels.json'));
assert(strcmp(c.sessionId,s.sessionId)&&strcmp(c.channelCatalogHash,s.channelCatalogHash), ...
    '通道字典身份与当前会话不一致。');
assert(afterSeq<=s.publishedSeq,'游标超过已发布历史；请核对会话身份。');
out=struct('status',s,'catalog',c.channels,'sampleSeq',zeros(0,1), ...
    'sampleTime',zeros(0,1),'values',zeros(0,numel(c.channels)), ...
    'quality',zeros(0,numel(c.channels)),'nextSeq',afterSeq,'hasMore',false, ...
    'isFinal',false);
files=dir(fullfile(folder,'stream','*.json'));[~,order]=sort({files.name});files=files(order);
limit=min(s.publishedSeq,afterSeq+maxRows);next=afterSeq+1;
for k=1:numel(files)
    if next>limit,break;end
    first=str2double(files(k).name(1:12));
    if k<numel(files)&&str2double(files(k+1).name(1:12))<=next,continue;end
    if first>limit,break;end
    q=sht_afo_read_json(fullfile(files(k).folder,files(k).name));
    assert(strcmp(q.schema,'SHT_AFO_SAMPLES_V2')&&strcmp(q.sessionId,s.sessionId)&& ...
        strcmp(q.runId,s.runId)&&strcmp(q.channelCatalogHash,s.channelCatalogHash), ...
        '样本块身份错误。');
    n=q.lastSeq-q.firstSeq+1;
    assert(n>0&&numel(q.values)==n*numel(c.channels)&&numel(q.quality)==numel(q.values), ...
        '样本块宽度或行数错误。');
    assert(isequal(q.sampleSeq(:),(q.firstSeq:q.lastSeq)')&&numel(q.sampleTime)==n, ...
        '样本块序号不连续。');
    if q.lastSeq<next,continue;end
    assert(q.firstSeq<=next,'历史存在缺口；禁止补零或伪造曲线。');
    rows=reshape(q.values,n,numel(c.channels));quality=reshape(q.quality,n,numel(c.channels));
    take=(next:min(q.lastSeq,limit))-q.firstSeq+1;
    out.sampleSeq=[out.sampleSeq;q.sampleSeq(take(:))];
    out.sampleTime=[out.sampleTime;q.sampleTime(take(:))];
    out.values=[out.values;rows(take,:)];out.quality=[out.quality;quality(take,:)];
    next=next+numel(take);
end
assert(next==limit+1,'已发布历史不完整；请检查文件是否损坏或被删除。');
out.nextSeq=next-1;out.hasMore=out.nextSeq<s.publishedSeq;
out.isFinal=s.isFinal&&out.nextSeq==s.sampleSeq&&s.publishedSeq==s.sampleSeq;
end
