function v = sht_afo_initialize(runtime)
%SHT_AFO_INITIALIZE 复用原初始化的设计点与中心差分，不污染基础工作区。
% 原脚本保留不动；生成受控运行函数只删除工作区/窗口清理和未执行的
% 历史绘图块。计算前缀逐字复用，尾部负责释放本次加载的库。
assert(~libisloaded('GTESS'),'sht:afo:dllBusy', ...
    '本进程已有GTESS库。请使用独立MATLAB进程，不卸载其他任务的库。');
bytes = fileread(fullfile(runtime,'RunCtrlSysModelSHT.m'));
marker = regexp(bytes,'(?m)^for i = 1:0','start','once');
assert(~isempty(marker),'未找到原初始化脚本的历史分析边界。');
code = bytes(1:marker-1);
code = regexprep(code,'clc;\s*clear all;\s*close all;','');
code = strrep(code,'script_dir = fileparts(mfilename(''fullpath''));', ...
    'script_dir = runtime;');
% 防止后续编辑改变预期复用范围，禁止其他全局工作区副作用。
assert(isempty(regexp(code,'\b(clear all|close all)\b','once')));
try
    eval(code);
catch failure
    clear eng_ptr eng_ptr_init step_in step_out enginePointer engout;
    if libisloaded('GTESS')
        try,calllib('GTESS','DLL_SHT_Free');unloadlibrary('GTESS');
        catch cleanupError,fprintf(2,'初始化资源释放提示：%s\n',cleanupError.message);end
    end
    rethrow(failure);
end
names = who;
v = struct;
for k = 1:numel(names)
    value = eval(names{k});
    if isnumeric(value) || islogical(value) || ischar(value) || strcmp(names{k},'RotorLoadCfg')
        if ~ismember(names{k},{'code','bytes','runtime','names','value','v'})
            v.(names{k}) = value;
        end
    end
end
clear eng_ptr eng_ptr_init step_in step_out enginePointer value engout;
calllib('GTESS','DLL_SHT_Free');
unloadlibrary('GTESS');
end
