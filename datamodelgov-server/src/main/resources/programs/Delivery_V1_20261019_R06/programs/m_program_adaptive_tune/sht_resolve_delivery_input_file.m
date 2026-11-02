function filePath = sht_resolve_delivery_input_file(requestedFile, defaultFile)
%SHT_RESOLVE_DELIVERY_INPUT_FILE 解析交付入口的可选数据文件名。
%
% requestedFile为空时返回defaultFile。用户只给文件名时，程序依次检查
% 当前工作目录和默认文件所在目录；用户给出相对或绝对路径时保持该路径
% 语义。函数只负责解析，不判断文件是否必须存在，由调用入口按“报错”或
% “安全跳过”的业务规则处理。

requestedFile = string(requestedFile);
defaultFile = string(defaultFile);
if ~isscalar(requestedFile) || ~isscalar(defaultFile)
    error('SHT:DeliveryInput:BadFileName', ...
        'requestedFile和defaultFile必须是字符向量或字符串标量。');
end
if strlength(strtrim(requestedFile)) == 0
    filePath = char(defaultFile);
    return;
end

requestedFile = strtrim(requestedFile);
if isfile(requestedFile)
    filePath = char(requestedFile);
    return;
end

[folder, name, extension] = fileparts(requestedFile);
if strlength(string(folder)) == 0
    candidate = fullfile(fileparts(defaultFile), name + extension);
    if isfile(candidate)
        filePath = char(candidate);
        return;
    end
end

filePath = char(requestedFile);
end
