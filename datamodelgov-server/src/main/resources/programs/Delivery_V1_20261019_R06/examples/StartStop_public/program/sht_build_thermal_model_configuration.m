function configuration = sht_build_thermal_model_configuration(parameterAsset)
%SHT_BUILD_THERMAL_MODEL_CONFIGURATION 组装DLL一次性标称热模型配置。
%
% 这里只收集与发动机个体和当前工况无关的固定参数。以下量不进入
% 配置向量，仍由每次DLL调用的stepIn提供：
%   1) 金属和转盘当前温度状态；
%   2) 当前工况的epsilon_ss查表结果；
%   3) 惯量、时间常数和间隙交换率的个体修正量；
%   4) 各类运行开关和部件掩码。
%
% 配置向量是与C程序之间的版本化合同。Kurzke与Visser共用本入口，
% 但按thermalModelMode采用各自唯一的向量布局。

if nargin < 1 || ~isstruct(parameterAsset) || ...
        ~isfield(parameterAsset,'interface') || ...
        ~isfield(parameterAsset,'nominal')
    error('SHT:ThermalConfig:InvalidAsset', ...
        '标称热模型初始化需要包含interface和nominal的参数资产。');
end
if parameterAsset.interface.interfaceVersion == 2502
    configuration = local_three_component(parameterAsset);
    return;
end
if parameterAsset.interface.interfaceVersion ~= 2503
    error('SHT:ThermalConfig:InterfaceVersion', ...
        '当前一次性热配置只用于2503六部件参数布局。');
end

nominal = parameterAsset.nominal;
thermalModelMode = local_thermal_model_mode(parameterAsset);
local_require_vector(nominal,'referenceFlow',7,true);
local_require_vector(nominal,'referenceGasTemperature',7,true);
local_require_vector(nominal,'kSM',2,false);
local_require_vector(nominal,'clearanceExchangeRate',8,false);
if ~isfield(nominal,'clearanceParameter') || ...
        ~isequal(size(nominal.clearanceParameter),[6,10]) || ...
        any(~isfinite(nominal.clearanceParameter(:)))
    error('SHT:ThermalConfig:ClearanceParameter', ...
        'nominal.clearanceParameter必须为6x10有限数矩阵。');
end
if any(nominal.clearanceExchangeRate(:)>0)
    error('SHT:ThermalConfig:ClearanceRate', ...
        '标称间隙交换率必须为有限非正数。');
end

switch thermalModelMode
    case 1
        local_require_vector(nominal,'tau0',19,true);
        local_require_vector(nominal,'heatCapacity0',19,true);
        local_require_vector(nominal,'beta',19,false);
        local_require_vector(nominal,'diskTau0',6,true);
        if any(nominal.beta(:)<0 | nominal.beta(:)>1)
            error('SHT:ThermalConfig:BetaRange','Kurzke beta必须位于[0,1]。');
        end
        parameterVector = [ ...
            nominal.tau0(:); nominal.heatCapacity0(:); nominal.beta(:); ...
            nominal.diskTau0(:); nominal.referenceFlow(:); ...
            nominal.referenceGasTemperature(:); ...
            reshape(nominal.clearanceParameter.',[],1); ...
            nominal.kSM(:); nominal.clearanceExchangeRate(:)];
        configVersion = 250301;
        parameterCount = 147;
    case 3
        local_require_vector(nominal,'visserMetalHeatCapacity',21,true);
        local_require_vector(nominal,'visserHotGasConductance0',21,false);
        local_require_vector(nominal,'visserHotGasBeta',21,false);
        local_require_vector(nominal,'visserDiskHeatCapacity',6,true);
        local_require_vector(nominal,'visserRootDiskConductance0',6,true);
        local_require_vector(nominal,'visserCoolingConductance0',19,false);
        if any(nominal.visserHotGasConductance0(:)<0) || ...
                any(nominal.visserCoolingConductance0(:)<0)
            error('SHT:ThermalConfig:Conductance', ...
                'Visser换热导纳必须为有限非负数。');
        end
        if any(nominal.visserHotGasBeta(:)<0 | ...
                nominal.visserHotGasBeta(:)>1)
            error('SHT:ThermalConfig:BetaRange', ...
                'Visser beta必须位于[0,1]。');
        end
        parameterVector = [ ...
            nominal.visserMetalHeatCapacity(:); ...
            nominal.visserHotGasConductance0(:); ...
            nominal.visserHotGasBeta(:); ...
            nominal.visserDiskHeatCapacity(:); ...
            nominal.visserRootDiskConductance0(:); ...
            nominal.visserCoolingConductance0(:); ...
            nominal.referenceFlow(:); ...
            nominal.referenceGasTemperature(:); ...
            reshape(nominal.clearanceParameter.',[],1); ...
            nominal.kSM(:); nominal.clearanceExchangeRate(:)];
        configVersion = 250303;
        parameterCount = 178;
    otherwise
        error('SHT:ThermalConfig:ThermalModelMode', ...
            '不支持thermalModelMode=%d。',thermalModelMode);
end

configuration = struct();
configuration.configurationClass = 'sht_nominal_thermal_model';
configuration.thermalModelMode = thermalModelMode;
configuration.configVersion = configVersion;
configuration.parameterCount = parameterCount;
configuration.parameterVector = parameterVector;
configuration.stepInPolicy = ...
    ['fixed_nominal_parameters_initialized_once; dynamic_states_' ...
     'operating_epsilon_and_individual_corrections_remain_in_stepIn'];
if numel(parameterVector) ~= configuration.parameterCount || ...
        any(~isfinite(parameterVector))
    error('SHT:ThermalConfig:VectorAssembly', ...
        '标称热配置向量应包含%d个有限数，当前为%d。', ...
        configuration.parameterCount,numel(parameterVector));
end
end

function mode = local_thermal_model_mode(asset)
mode = 1;
if isfield(asset.interface,'thermalModelMode') && ...
        ~isempty(asset.interface.thermalModelMode)
    mode = asset.interface.thermalModelMode;
elseif isfield(asset,'thermalModelMode') && ~isempty(asset.thermalModelMode)
    mode = asset.thermalModelMode;
elseif isfield(asset.nominal,'thermalModelMode') && ...
        ~isempty(asset.nominal.thermalModelMode)
    mode = asset.nominal.thermalModelMode;
end
if ~isscalar(mode) || ~isfinite(mode) || ~ismember(mode,[1,3])
    error('SHT:ThermalConfig:ThermalModelMode','热模型模式必须为1或3。');
end
end

function local_require_vector(s,fieldName,count,positiveRequired)
if ~isfield(s,fieldName)
    error('SHT:ThermalConfig:MissingField','缺少nominal.%s。',fieldName);
end
value = s.(fieldName);
if numel(value)~=count || any(~isfinite(value(:))) || ...
        (positiveRequired && any(value(:)<=0))
    error('SHT:ThermalConfig:FieldValue', ...
        'nominal.%s必须包含%d个%s数值。', ...
        fieldName,count,local_qualifier(positiveRequired));
end
end

function text = local_qualifier(positiveRequired)
if positiveRequired
    text = '有限正';
else
    text = '有限';
end
end

function c = local_three_component(asset)
% 复用C端最大容量布局，但三部件只校验、填写真实存在的10+3(+1)节点。
n=asset.nominal; mode=local_thermal_model_mode(asset);
names={'referenceFlow','referenceGasTemperature','kSM','clearanceExchangeRate'};
counts=[4,4,1,4]; positive=[true,true,false,false];
for k=1:numel(names),local_require_vector(n,names{k},counts(k),positive(k));end
assert(isequal(size(n.clearanceParameter),[3,10]) && all(isfinite(n.clearanceParameter(:))), ...
    'SHT:ThermalConfig:ClearanceParameter','三部件间隙参数须为3x10有限数。');
assert(all(n.clearanceExchangeRate<=0),'标称间隙交换率必须非正。');
if mode==1
    fields={'tau0','heatCapacity0','beta','diskTau0'}; lens=[10,10,10,3];
    for k=1:4,local_require_vector(n,fields{k},lens(k),k~=3);end
    assert(all(n.beta>=0 & n.beta<=1),'beta须在[0,1]内。');
    v=[local_pad(n.tau0,19);local_pad(n.heatCapacity0,19);local_pad(n.beta,19); ...
        local_pad(n.diskTau0,6)];
else
    fields={'visserMetalHeatCapacity','visserHotGasConductance0','visserHotGasBeta', ...
        'visserDiskHeatCapacity','visserRootDiskConductance0','visserCoolingConductance0'};
    lens=[11,11,11,3,3,19]; capacity=[21,21,21,6,6,19]; v=[];
    for k=1:6
        local_require_vector(n,fields{k},lens(k),ismember(k,[1,4,5]));
        assert(all(n.(fields{k})>=0),'热容量、导纳及beta不能负。');
        v=[v;local_pad(n.(fields{k}),capacity(k))]; %#ok<AGROW>
    end
    assert(all(n.visserHotGasBeta<=1),'beta须在[0,1]内。');
end
v=[v;local_pad(n.referenceFlow,7);local_pad(n.referenceGasTemperature,7); ...
    local_pad(reshape(n.clearanceParameter.',[],1),60);local_pad(n.kSM,2); ...
    local_pad(n.clearanceExchangeRate,8)];
c=struct('configurationClass','sht_nominal_thermal_model','thermalModelMode',mode, ...
    'configVersion',250200+mode,'parameterCount',numel(v),'parameterVector',v);
assert(numel(v)==147+31*(mode==3),'热配置长度错误。');
end

function v=local_pad(x,count)
v=zeros(count,1);v(1:numel(x))=x(:);
end
