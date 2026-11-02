function value=sht_tc27_uq_hash(data)
%SHT_TC27_UQ_HASH 以实际数值/合同内容产生缓存身份，不用修改时间代替身份。
bytes=unicode2native(jsonencode(data),'UTF-8');
md=java.security.MessageDigest.getInstance('SHA-256');md.update(bytes);
value=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end
