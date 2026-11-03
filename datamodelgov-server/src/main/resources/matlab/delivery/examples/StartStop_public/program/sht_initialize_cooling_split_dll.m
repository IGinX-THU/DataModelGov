function result = sht_initialize_cooling_split_dll(interface,modelMode,configuration)
%SHT_INITIALIZE_COOLING_SPLIT_DLL 初始化Visser内部19支路固定分流先验。
%
% 该接口只传递10条公共冷却流进入内部金属换热网络后的分配比例。
% 10条公共气流的质量流量和热力状态仍沿用既有气路接口；未来外部
% 空气系统给出更可信比例时，只需替换本配置，无需改变stepIn布局。

if ~ismember(modelMode,[0,1])
    error('SHT:CoolingSplit:ModelMode', ...
        '冷却分流初始化要求modelMode=0或1。');
end
if ~isstruct(configuration) || ~isfield(configuration,'ratio')
    error('SHT:CoolingSplit:Schema','冷却分流配置缺少ratio。');
end
ratio = configuration.ratio(:);
if numel(ratio) ~= 19 || any(~isfinite(ratio)) || ...
        any(ratio < 0 | ratio > 1)
    error('SHT:CoolingSplit:Value','ratio必须包含19个[0,1]有限数。');
end
routeStart = [1,4,6,10,12,14,15,17,18,19];
routeCount = [3,2,4,2,2,1,2,1,1,1];
for routeIndex = 1:10
    index = routeStart(routeIndex) + (0:routeCount(routeIndex)-1);
    if abs(sum(ratio(index))-1) > 1e-9
        error('SHT:CoolingSplit:RouteSum', ...
            '第%d条公共气流的内部比例和必须为1。',routeIndex);
    end
end
version = 250304;
if isfield(configuration,'configVersion') && ...
        ~isempty(configuration.configVersion)
    version = configuration.configVersion;
end
parameterCount = 19;
if isfield(configuration,'parameterCount') && ...
        ~isempty(configuration.parameterCount)
    parameterCount = configuration.parameterCount;
end
if version ~= 250304 || parameterCount ~= 19
    error('SHT:CoolingSplit:Version', ...
        '首轮冷却分流接口要求版本250304、参数数19。');
end

pointer = libpointer('doublePtr',ratio);
status = calllib(interface.libraryName,'DLL_SHT_InitializeCoolingSplit', ...
    version,parameterCount,pointer);
if status ~= 0
    error('SHT:CoolingSplit:DllInitialization', ...
        'DLL冷却分流初始化失败，状态码=%d。',status);
end
statusCheck = calllib(interface.libraryName, ...
    'DLL_SHT_CoolingSplitGetStatus');
if statusCheck ~= 0
    error('SHT:CoolingSplit:DllStatus', ...
        'DLL冷却分流状态复核失败，状态码=%d。',statusCheck);
end

result = struct('initialized',true,'configVersion',version, ...
    'parameterCount',parameterCount,'ratio',ratio,'dllStatus',statusCheck);
end
