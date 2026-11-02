function path=sht_tc24_absolute_path(path)
% 在切换工作目录前解析；不依赖调用者之后的pwd。
assert(ischar(path)||(isstring(path)&&isscalar(path)), ...
    'TC24:Path:Type','路径必须为文本标量。');
path=char(path);assert(~isempty(path),'TC24:Path:Empty','路径不能为空。');
file=java.io.File(path);
if ~file.isAbsolute(),file=java.io.File(fullfile(pwd,path));end
path=char(file.getCanonicalPath());
end
