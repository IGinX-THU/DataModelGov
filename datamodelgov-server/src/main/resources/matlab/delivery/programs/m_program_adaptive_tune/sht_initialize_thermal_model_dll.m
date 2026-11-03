function result = sht_initialize_thermal_model_dll(interface,modelMode,configuration)
%SHT_INITIALIZE_THERMAL_MODEL_DLL 把标称热模型配置一次写入DLL。
%
% 本函数必须在DLL_SHT_InitialMode之后、首次发动机求值之前调用。
% DLL端先对模型模式、配置版本、向量长度和参数物理范围做全量
% 校验；任一项失败时不覆盖上一份有效配置。

required = {'libraryName'};
for i = 1:numel(required)
    if ~isfield(interface,required{i}) || isempty(interface.(required{i}))
        error('SHT:ThermalConfig:Interface','DLL接口缺少%s。',required{i});
    end
end
if ~ismember(modelMode,[0,1])
    error('SHT:ThermalConfig:ModelMode', ...
        '标称热模型初始化要求modelMode=0或1。');
end
if ~isstruct(configuration) || ...
        ~all(isfield(configuration, ...
        {'thermalModelMode','configVersion','parameterCount','parameterVector'}))
    error('SHT:ThermalConfig:ConfigurationSchema','标称热配置结构不完整。');
end
vector = configuration.parameterVector(:);
if numel(vector) ~= configuration.parameterCount || any(~isfinite(vector))
    error('SHT:ThermalConfig:ConfigurationVector','配置向量长度或数值非法。');
end

parameterPointer = libpointer('doublePtr',vector);
status = calllib(interface.libraryName,'DLL_SHT_InitializeThermalConfig', ...
    configuration.thermalModelMode,configuration.configVersion, ...
    configuration.parameterCount,parameterPointer);
if status ~= 0
    error('SHT:ThermalConfig:DllInitialization', ...
        ['DLL_SHT_InitializeThermalConfig失败：模式=%d，版本=%d，' ...
         '参数数=%d，状态码=%d。'], ...
        configuration.thermalModelMode,configuration.configVersion, ...
        configuration.parameterCount,status);
end
statusCheck = calllib(interface.libraryName, ...
    'DLL_SHT_ThermalConfigGetStatus',configuration.thermalModelMode);
if statusCheck ~= 0
    error('SHT:ThermalConfig:DllStatus', ...
        '标称热配置写入后的DLL状态复核失败，状态码=%d。',statusCheck);
end

result = struct();
result.initialized = true;
result.thermalModelMode = configuration.thermalModelMode;
result.configVersion = configuration.configVersion;
result.parameterCount = configuration.parameterCount;
result.dllStatus = statusCheck;
end
