function path=sht_tc27_canonical_path(value)
%SHT_TC27_CANONICAL_PATH 解析已存在祖先的真实路径，避免目录联接绕过写保护。
assert((ischar(value)&&isrow(value))||(isstring(value)&&isscalar(value)), ...
    'TC27:Thermal:Path','路径必须是非空标量文本。');
value=char(value);
assert(~isempty(value)&&isempty(regexp(value,'[<>"|?*]','once')), ...
    'TC27:Thermal:Path','路径为空或含非法字符。');
f=java.io.File(value).getAbsoluteFile();tail={};
while ~f.exists()
    tail=[{char(f.getName())},tail]; %#ok<AGROW>
    f=f.getParentFile();
    assert(~isempty(f),'TC27:Thermal:Path','路径没有可解析的祖先。');
end
p=f.toPath().toRealPath(javaArray('java.nio.file.LinkOption',0));
for k=1:numel(tail),p=p.resolve(tail{k});end
path=char(p.normalize().toString());
end
