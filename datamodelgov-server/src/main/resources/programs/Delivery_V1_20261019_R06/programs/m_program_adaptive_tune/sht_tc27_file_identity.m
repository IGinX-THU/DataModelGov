function hash=sht_tc27_file_identity(file)
%SHT_TC27_FILE_IDENTITY 原始文件SHA-256，只读，不从时间戳推断结果身份。
fid=fopen(file,'rb');assert(fid>=0,'无法打开%s。',file);cleanup=onCleanup(@()fclose(fid));
md=java.security.MessageDigest.getInstance('SHA-256');
while ~feof(fid)
    bytes=fread(fid,1024*1024,'*uint8');
    % 空文件或整块读取后的EOF可能返回空数组，避免触发Java重载歧义。
    if ~isempty(bytes),md.update(bytes);end
end
hash=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end
