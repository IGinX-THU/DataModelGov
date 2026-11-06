function value=sht_afo_read_json(file)
%SHT_AFO_READ_JSON 严格按UTF-8读取文件，不依赖R2019b系统默认CP936。
% Windows路径反斜杠紧随中文时，错误解码可能吞掉转义符，不能用
% 字符串替换反斜杠的办法修复；必须在字节入口使用正确编码。
f=fopen(file,'rb');assert(f>=0,'sht:afo:readJSON','无法读取JSON：%s',file);
c=onCleanup(@()fclose(f));bytes=fread(f,Inf,'*uint8')';clear c;
if numel(bytes)>=3&&isequal(bytes(1:3),uint8([239 187 191])),bytes=bytes(4:end);end
text=native2unicode(bytes,'UTF-8');
assert(isequal(unicode2native(text,'UTF-8'),bytes),'sht:afo:readJSON','JSON文件不是有效UTF-8：%s',file);
value=jsondecode(text);
end
