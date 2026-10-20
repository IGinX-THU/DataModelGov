function result = sht_reynolds_correction_evaluate(configuration, state)
%SHT_REYNOLDS_CORRECTION_EVALUATE 复算并记录三/六部件RNI及性能倍率。
%
% state必须与configuration.components等长，按当前三/六部件顺序排列；
% 每行包含 totalTemperature_K 和 totalPressure_Pa。该函数只生成诊断，
% 正式性能修正在 DLL 内按同一公式执行。

if ~isstruct(configuration) || ~isfield(configuration,'components') || ...
        ~ismember(numel(configuration.components),[3,6]) || ...
        ~isstruct(state) || numel(state) ~= numel(configuration.components)
    error('SHT:ReynoldsCorrection:EvaluationSchema', ...
        'configuration和state必须包含同样的3或6个部件。');
end

count=numel(configuration.components);
name = cell(count,1);
reynoldsIndex = zeros(count,1);
flowMultiplier = ones(count,1);
efficiencyMultiplier = ones(count,1);
clampedLow = false(count,1);
for i = 1:count
    c = configuration.components(i);
    temperature = state(i).totalTemperature_K;
    pressure = state(i).totalPressure_Pa;
    if ~isnumeric(temperature)||~isreal(temperature)|| ...
            ~isscalar(temperature) || ~isfinite(temperature) || temperature <= 0 || ...
            ~isnumeric(pressure)||~isreal(pressure)|| ...
            ~isscalar(pressure) || ~isfinite(pressure) || pressure <= 0
        error('SHT:ReynoldsCorrection:EvaluationState', ...
            '%s入口总温或总压无效。',c.name);
    end
    mu = local_viscosity(temperature);
    muDesign = local_viscosity(c.designTemperature_K);
    rni = pressure/c.designPressure_Pa * ...
        sqrt(c.designTemperature_K/temperature) * muDesign/mu;
    fEta = local_map_factor(rni,c);
    fEtaDesign = local_map_factor(1,c);
    fW = 1-configuration.flowLossFraction*(1-fEta);
    fWDesign = 1-configuration.flowLossFraction*(1-fEtaDesign);
    name{i} = c.name;
    reynoldsIndex(i) = rni;
    if c.enabled
        flowMultiplier(i) = fW/fWDesign;
        efficiencyMultiplier(i) = fEta/fEtaDesign;
    end
    clampedLow(i) = rni <= c.lowIndex;
end
result = table(name,reynoldsIndex,flowMultiplier, ...
    efficiencyMultiplier,clampedLow);
end

function factor = local_map_factor(rni,c)
if rni <= c.lowIndex
    factor = c.lowEfficiencyFactor;
elseif rni >= c.highIndex
    factor = c.highEfficiencyFactor;
else
    u = log(rni/c.lowIndex)/log(c.highIndex/c.lowIndex);
    factor = c.lowEfficiencyFactor + ...
        u*(c.highEfficiencyFactor-c.lowEfficiencyFactor);
end
end

function mu = local_viscosity(temperature)
mu = 1.5105e-6*temperature^1.5/(temperature+120);
end
