function sht_engine_close(engine)
% 阅读说明：
%   本文件负责卸载 GTESS.dll。
%   若库未加载或句柄为空，函数直接返回，便于异常退出时清理。
%SHT_ENGINE_CLOSE Release GTESS DLL resources.
% 释放 GTESS.dll。
%
% 与 SFunc_EngModel.Terminate 对应：先调用 DLL_SHT_Free，再 unloadlibrary。

if isempty(engine) || ~isfield(engine, 'libraryName')
    libraryName = 'GTESS';
else
    libraryName = engine.libraryName;
end

if libisloaded(libraryName)
    try
        calllib(libraryName, 'DLL_SHT_Free');
    catch
    end

    % MATLAB 禁止卸载仍被 libstruct/libpointer 对象引用的动态库。
    % callContext 中的对象在一条历程内被高频复用，关闭时必须先主动
    % delete；仅把普通结构体字段置空不能解除 onCleanup 闭包中的引用。
    local_release_call_context(engine);

    % 异常退出路径可能在DLL资源释放期间触发外层卸载。再次检查别名
    % 状态，避免对已经卸载的库重复调用unloadlibrary。
    if libisloaded(libraryName)
        try
            unloadlibrary(libraryName);
        catch unloadError
            % MATLAB在异常栈清理期间可能先释放最后一个libstruct，进而
            % 使库在libisloaded检查与unloadlibrary之间变为未加载状态。
            % 只有库确实仍加载时才把卸载失败继续抛出。
            if libisloaded(libraryName)
                rethrow(unloadError);
            end
        end
    end
else
    % 异常路径下库可能已被外层卸载，仍尝试使句柄对象进入失效状态。
    local_release_call_context(engine);
end
end

function local_release_call_context(engine)
%LOCAL_RELEASE_CALL_CONTEXT 释放当前 DLL 实例对应的 MATLAB 库对象。
if isempty(engine) || ~isfield(engine, 'callContext') || ...
        ~isstruct(engine.callContext)
    return;
end

% 先释放包含 EngineTurboshaft 指针的包装对象，再释放数值数组指针。
fieldOrder = {'engPtr','stepIn','stepOut'};
for i = 1:numel(fieldOrder)
    name = fieldOrder{i};
    if ~isfield(engine.callContext, name) || ...
            isempty(engine.callContext.(name))
        continue;
    end
    try
        delete(engine.callContext.(name));
    catch
        % 关闭函数同时用于异常清理；已经失效或已被删除的对象无需重复报错。
    end
end
end
