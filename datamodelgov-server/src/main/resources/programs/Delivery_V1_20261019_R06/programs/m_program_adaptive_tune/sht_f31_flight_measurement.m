function varargout = sht_f31_flight_measurement(action, varargin)
%SHT_F31_FLIGHT_MEASUREMENT 3.1第二轮装机飞参测量链。
%
% 测量顺序严格为：
%   真值 -> 一阶传感器FOH离散动态 -> 偏置 -> 白噪声。
%
% 该函数复用2.6已经确认的FOH动态实现和温度时间常数字典，但采用面向
% 装机飞参的误差范围。训练任务与测试任务共享80%的对象级校准偏置，
% 各自再叠加不超过20%偏置半宽的任务级漂移；两条任务使用独立白噪声
% 种子。Wf偏置保留为随测量燃油流量比变化的6节点加性曲线，其余通道为
% 每架次常值偏置。3.1不增加纯延迟，也不生成重复的不确定性试验。

if nargin < 1
    error('SHT:F31Measurement:Action', '必须给定操作名称。');
end
switch lower(char(action))
    case 'model'
        varargout{1} = local_model(varargin{:});
    case 'configure'
        varargout{1} = local_configure(varargin{:});
    case 'preparetruthlog'
        varargout{1} = local_prepare_truth_log(varargin{:});
    case 'apply'
        [varargout{1:nargout}] = local_apply(varargin{:});
    case 'publicassumptions'
        varargout{1} = local_public_assumptions(varargin{:});
    otherwise
        error('SHT:F31Measurement:Action', '未知操作%s。',char(action));
end
end

function model = local_model( ...
        randomSeed, missionId, enabled, reference, persistentBiasSeed)
if nargin < 1 || isempty(randomSeed), randomSeed = 3101001; end
if nargin < 2 || isempty(missionId), missionId = 'F31-CAL-01'; end
if nargin < 3 || isempty(enabled), enabled = true; end
if nargin < 4 || isempty(reference), reference = local_default_reference(); end
if nargin < 5 || isempty(persistentBiasSeed), persistentBiasSeed = 3101017; end
local_validate_seed(randomSeed,'randomSeed');
local_validate_seed(persistentBiasSeed,'persistentBiasSeed');

% 前15项保留控制闭环和历史诊断所需的内部传感器；后3项是正式
% 机载数据合同中的独立或等效测量。formalOutput明确控制对外发布范围，
% 避免把Pt2/Tt3/Pt45等台架测点误写进飞参Excel。
names = {'Np','Ng','Wf','Tt45','Mkp','Mkg','Pt2','Tt1', ...
    'Pt3','Tt3','Pt45','Tamb','Pamb','Altitude','Mach', ...
    'Ps0','Pt3_eq','Ts_amb'};
units = {'rpm','rpm','kg/s','K','N*m','N*m','Pa','K', ...
    'Pa','K','Pa','K','Pa','m','-', ...
    'Pa','Pa','K'};
formalOutput = ismember(names,{'Np','Ng','Wf','Tt45','Mkp','Mkg', ...
    'Tt1','Altitude','Mach','Ps0','Pt3_eq','Ts_amb'});
if isfield(reference,'modelMode')&&reference.modelMode==0
    formalOutput(strcmp(names,'Mkg'))=false;
end
% 除高度和马赫数外，偏置半宽与噪声均按设计参考值比例定义。
% Pt3_eq额外包含静压测量到等效总压换算的工程不确定性，因此明显大于
% 原模型内部Pt3记录通道；但不生成缺少面积依据的Ps3伪真值。
biasFraction = [0.00020,0.00020,0.00750,0.00400,0.00500, ...
    0.00750,0.00200,0.00100,0.00250,0.00300,0.00250, ...
    0.00100,0.00100,NaN,NaN,0.00150,0.00600,0.00100];
noiseFraction = [0.00008,0.00008,0.00050,0.00060,0.00080, ...
    0.00100,0.00040,0.00030,0.00040,0.00050,0.00040, ...
    0.00030,0.00030,NaN,NaN,0.00030,0.00120,0.00030];

temperatureCfg = sht_temperature_sensor_dynamics('channelConfig',names);
timeConstant = 0.020*ones(numel(names),1);
timeConstant(temperatureCfg.supported) = ...
    temperatureCfg.timeConstant_s(temperatureCfg.supported);
timeConstant(strcmp(names,'Ts_amb')) = 2.0;

persistentStream = RandStream('mt19937ar','Seed',round(persistentBiasSeed));
missionStream = RandStream('mt19937ar','Seed',round(randomSeed)+7919);
fields = repmat(local_empty_field(),numel(names),1);
for i = 1:numel(names)
    designReference = local_reference_value(reference,names{i});
    if strcmp(names{i},'Altitude')
        halfWidth = 10.0;
        noiseStd = 2.0;
    elseif strcmp(names{i},'Mach')
        halfWidth = 0.005;
        noiseStd = 0.0015;
    else
        halfWidth = designReference*biasFraction(i);
        noiseStd = designReference*noiseFraction(i);
    end
    persistentBias = 0.80*halfWidth*(2*rand(persistentStream)-1);
    missionBias = 0.20*halfWidth*(2*rand(missionStream)-1);
    fields(i).name = names{i};
    fields(i).unit = units{i};
    fields(i).designReference = designReference;
    fields(i).totalBiasHalfWidth = halfWidth;
    fields(i).noiseStd = noiseStd;
    fields(i).timeConstant_s = timeConstant(i);
    fields(i).persistentBias = persistentBias;
    fields(i).missionBias = missionBias;
    fields(i).appliedBias = persistentBias + missionBias;
    fields(i).formalOutput = formalOutput(i);
end

% Wf使用多节点偏置曲线。持久分量只由persistentBiasSeed决定，
% 因而同一发动机的训练/测试任务保持相同校准特性；任务分量由
% randomSeed决定。两分量分别受80%/20%偏置半宽限制。
wfIndex = find(strcmp(names,'Wf'),1);
fuelBiasSchedule = local_build_fuel_bias_schedule( ...
    fields(wfIndex),persistentBiasSeed,randomSeed);
fields(wfIndex).persistentBias = local_interp_clamp( ...
    fuelBiasSchedule.xNodes,fuelBiasSchedule.persistentBiasNodes,1);
fields(wfIndex).missionBias = local_interp_clamp( ...
    fuelBiasSchedule.xNodes,fuelBiasSchedule.missionBiasNodes,1);
fields(wfIndex).appliedBias = local_interp_clamp( ...
    fuelBiasSchedule.xNodes,fuelBiasSchedule.biasNodes,1);

model = struct();
model.version = 'F31_FLIGHT_MEASUREMENT_V3';
model.enabled = logical(enabled);
model.missionId = char(missionId);
model.randomSeed = round(randomSeed);
model.persistentBiasSeed = round(persistentBiasSeed);
model.persistentBiasFraction = 0.80;
model.missionBiasFraction = 0.20;
model.sensorSequence = ...
    ['true -> FOH first-order dynamics -> scalar/scheduled mission bias' ...
     ' -> white noise'];
model.delay_s = 0;
model.fields = fields;
model.formalChannelNames = names(formalOutput);
model.temperatureDynamics = sht_temperature_sensor_dynamics('model');
model.fuelBiasSchedule = fuelBiasSchedule;
end

function cfg = local_configure(cfg,model)
if ~isstruct(cfg) || ~isstruct(model)
    error('SHT:F31Measurement:Configure', 'cfg和model必须为结构体。');
end
channelNames = cfg.sensor.channels;
n = numel(channelNames);
bias = zeros(n,1);
noiseStd = zeros(n,1);
timeConstant = zeros(n,1);
for i = 1:n
    [spec,found] = local_find_spec(model.fields,channelNames{i});
    if ~found, continue; end
    % Wf在完整物理历程生成后统一通过多节点偏置曲线形成正式记录，
    % 此处不得再叠加标量偏置或噪声。
    if strcmp(channelNames{i},'Wf')
        bias(i) = 0;
        noiseStd(i) = 0;
    else
        bias(i) = spec.appliedBias;
        noiseStd(i) = spec.noiseStd;
    end
    timeConstant(i) = spec.timeConstant_s;
end
if model.enabled
    cfg.sensor.mode = 'firstOrder';
    cfg.sensor.bias = bias;
    cfg.sensor.noiseStd = noiseStd;
    cfg.sensor.timeConstant = timeConstant;
    cfg.sensor.randomSeed = model.randomSeed;
    % 3.1的偏置实现已经在model中冻结，关闭2.6流量漂移字典，避免叠加。
    cfg.sensor.biasModel = struct('enabled',false);
else
    cfg.sensor.mode = 'identity';
    cfg.sensor.bias = zeros(n,1);
    cfg.sensor.noiseStd = zeros(n,1);
    cfg.sensor.timeConstant = zeros(n,1);
    cfg.sensor.randomSeed = 1;
    cfg.sensor.biasModel = struct('enabled',false);
end
end

function log = local_prepare_truth_log(log)
if ~isfield(log,'time') || isempty(log.time)
    error('SHT:F31Measurement:TruthLog', '仿真日志缺少时间轴。');
end
if isfield(log,'Pload')
    log.target_load_power = log.Pload(:);
else
    log.target_load_power = log.Mkp(:).*log.Np(:)*pi/30;
end
if isfield(log,'thetaCollectiveDeg')
    log.collective_pitch_deg = log.thetaCollectiveDeg(:);
end
% 当前模型没有可靠面积，不能由总态虚构Ps3。Pt3_eq直接使用模型Pt3
% 真值并在测量层施加更大的等效换算误差。
log.Ps0 = log.Pamb(:);
log.Pt3_eq = log.Pt3(:);
log.Ts_amb = log.Tamb(:);
log = local_rebuild_derived(log,'truth');
if isfield(log,'T45'), log = rmfield(log,'T45'); end
end

function [measuredLog,sensorError] = local_apply(truthLog,rawLog,model)
measuredLog = truthLog;
sensorError = struct('enabled',model.enabled,'missionId',model.missionId, ...
    'randomSeed',model.randomSeed, ...
    'persistentBiasSeed',model.persistentBiasSeed, ...
    'machLowerClipCount',0,'fuelBiasSchedule',model.fuelBiasSchedule, ...
    'fuelBiasTrajectory_kgps',zeros(numel(truthLog.time),1), ...
    'applied',repmat(local_empty_error_item(),0,1));
if ~model.enabled
    return;
end

mappings = local_feedback_mappings();
for i = 1:numel(mappings)
    [spec,found] = local_find_spec(model.fields,mappings(i).name);
    if ~found || ~isfield(truthLog,spec.name), continue; end
    if ~isfield(rawLog,mappings(i).sampleField)
        error('SHT:F31Measurement:SensorLog', ...
            '闭环日志缺少%s，无法形成%s测量值。', ...
            mappings(i).sampleField,mappings(i).name);
    end
    measuredLog.(mappings(i).name) = rawLog.(mappings(i).sampleField)(:);
    sensorError.applied(end+1,1) = local_error_item( ...
        spec,'closed_loop_sensor'); %#ok<AGROW>
end

% 马赫数是非负量；静止段的小噪声允许触及零，但不允许形成负马赫数。
if isfield(measuredLog,'Mach')
    sensorError.machLowerClipCount = nnz(measuredLog.Mach < 0);
    measuredLog.Mach = max(measuredLog.Mach,0);
end
measuredLog = local_rebuild_derived(measuredLog,'measured');
measuredLog.target_load_power = ...
    measuredLog.Mkp(:).*measuredLog.Np(:)*pi/30;

% Wf及三个正式别名不参与现有控制器反馈，在仿真后独立生成。
% Np是动力涡轮/发动机输出轴转速；传动比及旋翼测速合同未确认，
% 不把它等同于旋翼转速，也不人为复制RotorSpeed测量通道。
recordOnlyNames = {'Wf','Ps0','Pt3_eq','Ts_amb'};
for i = 1:numel(recordOnlyNames)
    [spec,found] = local_find_spec(model.fields,recordOnlyNames{i});
    if ~found || ~isfield(truthLog,spec.name), continue; end
    stream = RandStream('mt19937ar','Seed', ...
        model.randomSeed+500000+1009*i);
    dynamicValue = sht_first_order_foh_filter( ...
        truthLog.time(:),truthLog.(spec.name)(:),spec.timeConstant_s);
    if strcmp(spec.name,'Wf')
        [indicatedValue,actualBias] = local_apply_fuel_bias( ...
            dynamicValue,model.fuelBiasSchedule);
        measuredLog.(spec.name) = indicatedValue + ...
            spec.noiseStd*randn(stream,size(dynamicValue));
        sensorError.fuelBiasTrajectory_kgps = actualBias;
        errorSource = 'record_only_scheduled_sensor';
    else
        measuredLog.(spec.name) = dynamicValue+spec.appliedBias+ ...
            spec.noiseStd*randn(stream,size(dynamicValue));
        errorSource = 'record_only_sensor';
    end
    sensorError.applied(end+1,1) = local_error_item( ...
        spec,errorSource); %#ok<AGROW>
end
end

function tableValue = local_public_assumptions(model)
fields = model.fields([model.fields.formalOutput]);
n = numel(fields);
name = cell(n,1); unit = cell(n,1);
designReference = zeros(n,1); totalBiasHalfWidth = zeros(n,1);
noiseStd = zeros(n,1); timeConstant_s = zeros(n,1);
for i = 1:n
    name{i} = fields(i).name;
    unit{i} = fields(i).unit;
    designReference(i) = fields(i).designReference;
    totalBiasHalfWidth(i) = fields(i).totalBiasHalfWidth;
    noiseStd(i) = fields(i).noiseStd;
    timeConstant_s(i) = fields(i).timeConstant_s;
end
biasHalfWidthPctDesign = 100*totalBiasHalfWidth./max(abs(designReference),eps);
noiseStdPctDesign = 100*noiseStd./max(abs(designReference),eps);
absoluteSpecification = ismember(name,{'Altitude','Mach'});
biasHalfWidthPctDesign(absoluteSpecification) = NaN;
noiseStdPctDesign(absoluteSpecification) = NaN;
tableValue = table(name,unit,designReference,totalBiasHalfWidth, ...
    biasHalfWidthPctDesign,noiseStd,noiseStdPctDesign,timeConstant_s, ...
    absoluteSpecification);
end

function mappings = local_feedback_mappings()
mappings = struct( ...
    'name',{'Np','Ng','Tt45','Mkp','Mkg','Pt2','Tt1','Pt3','Tt3', ...
    'Pt45','Tamb','Pamb','Altitude','Mach'}, ...
    'sampleField',{'sampleNp','sampleNg','sampleTt45','sampleMkp', ...
    'sampleMkg','samplePt2','sampleTt1','samplePt3','sampleTt3', ...
    'samplePt45','sampleTamb','samplePamb','sampleAltitude','sampleMach'});
end

function log = local_rebuild_derived(log,layerName)
required = {'Ng','Pt2','Tt1'};
for i = 1:numel(required)
    if ~isfield(log,required{i})
        error('SHT:F31Measurement:Derived', '%s层缺少%s。', ...
            layerName,required{i});
    end
end
log.Theta = log.Tt1(:)/288.15;
log.Deta = log.Pt2(:)/101325;
log.Ngc = log.Ng(:)./sqrt(log.Theta);
end

function [spec,found] = local_find_spec(specs,name)
lookupName = char(name);
if strcmp(lookupName,'T45'), lookupName = 'Tt45'; end
index = find(strcmp({specs.name},lookupName),1,'first');
found = ~isempty(index);
if found, spec = specs(index); else, spec = struct(); end
end

function reference = local_default_reference()
reference = struct('Np',20800,'Ng',38000,'Wf',0.151914044493225, ...
    'Tt45',1143.4502168824,'Mkp',999.278795573804,'Mkg',7.54, ...
    'Pt2',98285.25,'Tt1',288.15,'Pt3',1572564, ...
    'Tt3',702.307986952118,'Pt45',395927.737357462, ...
    'Tamb',288.15,'Pamb',101325,'Altitude',100,'Mach',1, ...
    'Ps0',101325,'Pt3_eq',1572564,'Ts_amb',288.15);
end

function schedule = local_build_fuel_bias_schedule(spec,persistentSeed,missionSeed)
% 节点坐标继承2.4/2.7的Wf偏置合同，便于下游直接复用同一物理含义。
x = [0.182880108799;0.405855464218;0.525190285461; ...
    0.690315115064;0.863120959573;1.047473614120];
z = 2*(x-min(x))/max(max(x)-min(x),eps)-1;
basis = [ones(size(z)),z,2*z.^2-1];
weights = [0.55;0.30;0.15];

persistentStream = RandStream('mt19937ar','Seed',round(persistentSeed)+31031);
missionStream = RandStream('mt19937ar','Seed',round(missionSeed)+31037);
persistentCoefficient = 2*rand(persistentStream,3,1)-1;
missionCoefficient = 2*rand(missionStream,3,1)-1;
persistentNodes = 0.80*spec.totalBiasHalfWidth * ...
    (basis*(weights.*persistentCoefficient));
missionNodes = 0.20*spec.totalBiasHalfWidth * ...
    (basis*(weights.*missionCoefficient));
biasNodes = persistentNodes+missionNodes;
if any(abs(biasNodes)>spec.totalBiasHalfWidth+10*eps(spec.totalBiasHalfWidth))
    error('SHT:F31Measurement:FuelBiasBound', ...
        'Wf多节点偏置超出公开偏置半宽。');
end
schedule = struct('version','F31_WF_BIAS_SCHEDULE_V1', ...
    'axisName','measured_wf_ratio','xNodes',x, ...
    'biasNodes',biasNodes,'persistentBiasNodes',persistentNodes, ...
    'missionBiasNodes',missionNodes,'wfDesign',spec.designReference, ...
    'interpolation','linear','extrapolation','endpoint_clamp', ...
    'totalBiasHalfWidth_kgps',spec.totalBiasHalfWidth);
end

function [indicated,bias] = local_apply_fuel_bias(dynamicValue,schedule)
% 与下游回放反解口径一致：偏置曲线以“带偏置但尚未加白噪声”
% 的燃油示值为查表坐标。该标量不动点是弱收缩映射，4次迭代的
% 一致性误差远小于白噪声标准差。
indicated = dynamicValue(:);
for k = 1:4
    bias = local_interp_clamp(schedule.xNodes,schedule.biasNodes, ...
        indicated/schedule.wfDesign);
    indicated = dynamicValue(:)+bias;
end
bias = indicated-dynamicValue(:);
end

function value = local_interp_clamp(x,y,query)
x=x(:); y=y(:); query=query(:);
if numel(x)~=numel(y) || numel(x)<2 || any(diff(x)<=0)
    error('SHT:F31Measurement:Schedule', '调度节点无效。');
end
query=min(max(query,x(1)),x(end));
value=interp1(x,y,query,'linear');
end

function value = local_reference_value(reference,name)
if strcmp(name,'Mkg')&&isfield(reference,'modelMode')&&reference.modelMode==0
    assert(reference.Mkg==0,'三部件未测附件负载边界须为0。');value=0;return;
end
if ~isfield(reference,name) || ~isscalar(reference.(name)) || ...
        ~isfinite(reference.(name)) || reference.(name) <= 0
    error('SHT:F31Measurement:Reference', ...
        '测量参考值reference.%s必须为有限正标量。',name);
end
value = double(reference.(name));
end

function field = local_empty_field()
field = struct('name','','unit','','designReference',NaN, ...
    'totalBiasHalfWidth',NaN,'noiseStd',NaN,'timeConstant_s',NaN, ...
    'persistentBias',NaN,'missionBias',NaN,'appliedBias',NaN, ...
    'formalOutput',false);
end

function item = local_empty_error_item()
item = struct('name','','unit','','source','','appliedBias',NaN, ...
    'persistentBias',NaN,'missionBias',NaN,'noiseStd',NaN, ...
    'timeConstant_s',NaN);
end

function item = local_error_item(spec,source)
item = local_empty_error_item();
item.name = spec.name;
item.unit = spec.unit;
item.source = source;
item.appliedBias = spec.appliedBias;
item.persistentBias = spec.persistentBias;
item.missionBias = spec.missionBias;
item.noiseStd = spec.noiseStd;
item.timeConstant_s = spec.timeConstant_s;
end

function local_validate_seed(value,name)
if ~isscalar(value) || ~isfinite(value) || value < 0 || value ~= round(value)
    error('SHT:F31Measurement:Seed', '%s必须为非负整数。',name);
end
end
