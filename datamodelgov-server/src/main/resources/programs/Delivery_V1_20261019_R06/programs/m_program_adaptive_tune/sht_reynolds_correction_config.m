function config = sht_reynolds_correction_config(effectScale,modelMode,designReference)
%SHT_REYNOLDS_CORRECTION_CONFIG 构造按模型模式区分的RNI配置。
%
% effectScale 是单一装机因素幅值系数。0 表示保留接口但不施加性能
% 修正，1 表示采用特性图给出的 RNI=0.1 时效率因子 0.95。该系数仅
% 用于合成飞参生成阶段的单因素标定，不属于发动机健康参数。
% 原单参数调用完整保留六部件默认值。三部件必须显式传入modelMode=0，
% 以及按HPC/GT/PT排序的设计参考结构数组，不能套用六部件温压参考。
% designReference每行包含name、designTemperature_K、designPressure_Pa、
% mapPath。涡轮参考温度取前端冷却掺混后，压力取C实际图谱入口压力。

if nargin < 1 || isempty(effectScale)
    effectScale = 1;
end
if nargin<2 || isempty(modelMode),modelMode=1;end
if ~isnumeric(modelMode)||~isreal(modelMode)||~isscalar(modelMode)|| ...
        ~isfinite(modelMode)||~ismember(modelMode,[0,1])
    error('SHT:ReynoldsCorrection:ModelMode','modelMode必须为0或1。');
end
if nargin<3,designReference=[];end
if modelMode==0 && isempty(designReference)
    error('SHT:ReynoldsCorrection:DesignReference', ...
        '三部件RNI必须提供自身HPC/GT/PT设计参考和MAP路径。');
end
if ~isnumeric(effectScale) || ~isreal(effectScale) || ...
        ~isscalar(effectScale) || ~isfinite(effectScale) || ...
        effectScale < 0 || effectScale > 2
    error('SHT:ReynoldsCorrection:EffectScale', ...
        'effectScale必须是[0,2]内的有限实数。');
end

% 设计参考状态来自当前六部件设计点的各部件实际入口。涡轮入口采用
% 前端冷却气与主流掺混后的特性图口径，与 C 端 turbineRun 一致。
names = {'AC','CC','GT1','GT2','PT1','PT2'};
designTemperature_K = [288.15,478.949948717802,1546.81971929367, ...
    1328.2653324463,1140.01105775814,998.049127410641];
designPressure_Pa = [98285.2497398081,478499.817276621, ...
    1517521.85153669,802677.740169836,384049.29608652, ...
    212544.522114486];
if modelMode==0,names={'HPC','GT','PT'};end

lowIndex = 0.10;
highIndex = 1.00;
lowEfficiencyFactor = 1 + effectScale*(0.95 - 1);
highEfficiencyFactor = 1.00;
components = repmat(struct('name','','enabled',true, ...
    'designTemperature_K',NaN,'designPressure_Pa',NaN, ...
    'lowIndex',lowIndex,'lowEfficiencyFactor',lowEfficiencyFactor, ...
    'highIndex',highIndex,'highEfficiencyFactor',highEfficiencyFactor),numel(names),1);
if ~isempty(designReference)
    required={'name','designTemperature_K','designPressure_Pa','mapPath'};
    if ~isstruct(designReference)||numel(designReference)~=numel(names)|| ...
            ~all(isfield(designReference,required))
        error('SHT:ReynoldsCorrection:DesignReference','设计参考维数或字段不完整。');
    end
end
for i = 1:numel(components)
    components(i).name = names{i};
    components(i).designTemperature_K = designTemperature_K(i);
    components(i).designPressure_Pa = designPressure_Pa(i);
    if ~isempty(designReference)
        r=designReference(i);
        if ~strcmp(r.name,names{i})||~isnumeric(r.designTemperature_K)|| ...
                ~isnumeric(r.designPressure_Pa)||~isreal(r.designTemperature_K)|| ...
                ~isreal(r.designPressure_Pa)||~isscalar(r.designTemperature_K)|| ...
                ~isscalar(r.designPressure_Pa)||~isfinite(r.designTemperature_K)|| ...
                ~isfinite(r.designPressure_Pa)||r.designTemperature_K<=0||r.designPressure_Pa<=0
            error('SHT:ReynoldsCorrection:DesignReference', ...
                '%s设计参考名称/温度/压力不合法。',names{i});
        end
        components(i).designTemperature_K=r.designTemperature_K;
        components(i).designPressure_Pa=r.designPressure_Pa;
        map=local_map_endpoints(r.mapPath);
        components(i).lowIndex=map(1);components(i).highIndex=map(3);
        components(i).lowEfficiencyFactor=1+effectScale*(map(2)-1);
        components(i).highEfficiencyFactor=1+effectScale*(map(4)-1);
        if min([components(i).lowEfficiencyFactor,components(i).highEfficiencyFactor])<=0
            error('SHT:ReynoldsCorrection:MapFactor','放大后的RNI效率倍率必须为正。');
        end
    end
end

config = struct();
config.schemaVersion = 'SHT_REYNOLDS_CORRECTION_V1';
config.configVersion = 1;
config.parameterCount = 43;
config.effectScale = effectScale;
config.flowLossFraction = 0.50;
config.viscosityModel = 'Sutherland_mu=1.5105e-6*T^1.5/(T+120)';
config.interpolation = 'log-linear with endpoint clamping';
config.designAnchored = true;
config.components = components;
if modelMode==0 || ~isempty(designReference)
    config.modelMode=modelMode;
    config.designReference=designReference;
end
end

function endpoints=local_map_endpoints(file)
% 读取当前MAP明示的两端RNI先验；不猜测缺失端点，不改动原图。
if ~isfile(file),error('SHT:ReynoldsCorrection:MapFile','缺少MAP：%s',file);end
token=regexp(fileread(file), ...
    'Reynolds:\s*RNI=\s*([-+0-9.eE]+)\s*f=\s*([-+0-9.eE]+)\s*RNI=\s*([-+0-9.eE]+)\s*f=\s*([-+0-9.eE]+)', ...
    'tokens');
if numel(token)~=1
    error('SHT:ReynoldsCorrection:MapHeader','MAP需唯一的两端RNI定义：%s',file);
end
endpoints=str2double(token{1});
if any(~isfinite(endpoints))||any(endpoints<=0)||endpoints(3)<=endpoints(1)
    error('SHT:ReynoldsCorrection:MapHeader','MAP的RNI端点无效：%s',file);
end
end
