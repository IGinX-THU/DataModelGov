function sht_afo_json(file,value)
%SHT_AFO_JSON 完整写入同目录临时文件后原子发布，读者不读半个JSON。
tmp=[file '.' char(java.util.UUID.randomUUID) '.tmp'];
f=fopen(tmp,'w','n','UTF-8');assert(f>=0,'sht:afo:publish','无法写入：%s',tmp);
clean=onCleanup(@()local_cleanup(f,tmp));
count=fprintf(f,'%s',jsonencode(value));
assert(count>=0,'sht:afo:publish','写入失败。');
status=fclose(f);f=-1;assert(status==0,'sht:afo:publish','文件关闭失败。');
[ok,msg]=movefile(tmp,file,'f');assert(ok,'sht:afo:publish','发布失败：%s',msg);
clear clean
end
function local_cleanup(f,tmp)
if any(fopen('all')==f),fclose(f);end
if exist(tmp,'file')==2,delete(tmp);end
end
