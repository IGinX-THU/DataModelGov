function solve = sht_solve_steady_components_from_seed( ...
        engine, cfg, stepInValue, initialVarIte, userOptions)
%SHT_SOLVE_STEADY_COMPONENTS_FROM_SEED 从指定分支初值求稳态共同工作解。
%
% 本函数用于参数估计中的困难低负载工况。Wf、轴负载和健康参数已经写入
% stepInValue，求解器只调整三部件模式的6维或六部件模式的9维共同工作
% 变量，使 DLL_SHT_RunSteadyComponents 返回的全部共同工作残差为零。
%
% 与 DLL_SHT_RunOnePoint 内部Newton相比，本函数具有两个工程用途：
%   1) 每次从调用方指定的物理分支初值出发，不沿用DLL全局历史状态；
%   2) 使用归一化中心差分、阻尼线搜索和严格残差门限，避免低负载时
%      一次大步跳到远离基线的另一数学根。
%
% 默认保持历史固定功率边界。若显式给出ptLoadTorqueNm/gtLoadTorqueNm，
% 每次残差计算均用当前Newton候选转速把外部扭矩换算为轴功率，从而
% 直接求解扭矩边界下的共同工作根；此时初始转速仍只是分支初值。

if nargin < 5 || isempty(userOptions), userOptions = struct(); end
loadBoundary = local_load_boundary_options(userOptions);
local_validate_inputs(engine, cfg, stepInValue, initialVarIte, loadBoundary);
z = initialVarIte(:);
n = numel(z);
if ~isempty(loadBoundary.npBoundsRpm) && ...
        (z(end-1)<loadBoundary.npBoundsRpm(1) || z(end-1)>loadBoundary.npBoundsRpm(2))
    error('SHT:SteadySeedSolve:SeedOutsideNpBranch', ...
        '稳态初值Np=%.6f rpm不在指定分支[%.6f, %.6f] rpm内。', ...
        z(end-1),loadBoundary.npBoundsRpm);
end
scale = local_variable_scale(cfg, n);
settings = struct('maxIteration', 25, ...
    'residualTolerance', 1e-7, ...
    'normalizedPerturbation', 1e-4, ...
    'scale', scale);

evaluation = local_evaluate(engine, cfg, stepInValue, z, loadBoundary);
residual = evaluation.residual;
bestNorm = norm(residual, inf);
conditionNumber = Inf;

for iteration = 0:settings.maxIteration
    if local_is_converged(evaluation, residual, settings)
        solve = local_pack(z, evaluation, residual, iteration, ...
            true, conditionNumber);
        return;
    end
    if iteration == settings.maxIteration
        break;
    end

    [jacobian, conditionNumber] = local_jacobian( ...
        engine, cfg, stepInValue, z, residual, settings, loadBoundary);
    if any(~isfinite(jacobian(:))) || rcond(jacobian) < 1e-14
        break;
    end
    normalizedStep = -(jacobian \ residual);
    physicalStep = normalizedStep(:) .* settings.scale(:);
    [candidate, candidateEvaluation, candidateResidual, accepted] = ...
        local_line_search(engine, cfg, stepInValue, z, ...
        physicalStep, bestNorm, loadBoundary);
    if ~accepted
        break;
    end

    z = candidate;
    evaluation = candidateEvaluation;
    residual = candidateResidual;
    bestNorm = norm(residual, inf);
end

solve = local_pack(z, evaluation, residual, ...
    iteration, false, conditionNumber);
end

function [jacobian, conditionNumber] = local_jacobian( ...
        engine, cfg, stepInValue, z, residual0, settings, loadBoundary)
n = numel(z);
jacobian = zeros(n, n);
for j = 1:n
    delta = settings.normalizedPerturbation * settings.scale(j);
    plus = z;
    minus = z;
    plus(j) = plus(j) + delta;
    minus(j) = minus(j) - delta;
    % 接近Np边界时只对有效侧求导；不能跨越已指定的物理解范围。
    plusResidual=nan(size(residual0));minusResidual=plusResidual;
    if local_inside_np(plus,loadBoundary)
        plusEvaluation=local_evaluate(engine,cfg,stepInValue,plus,loadBoundary);
        plusResidual=plusEvaluation.residual;
    end
    if local_inside_np(minus,loadBoundary)
        minusEvaluation=local_evaluate(engine,cfg,stepInValue,minus,loadBoundary);
        minusResidual=minusEvaluation.residual;
    end
    if all(isfinite(plusResidual)) && all(isfinite(minusResidual))
        jacobian(:, j) = (plusResidual - minusResidual) / ...
            (2 * settings.normalizedPerturbation);
    elseif all(isfinite(plusResidual))
        jacobian(:, j) = (plusResidual - residual0) / ...
            settings.normalizedPerturbation;
    elseif all(isfinite(minusResidual))
        jacobian(:, j) = (residual0 - minusResidual) / ...
            settings.normalizedPerturbation;
    else
        jacobian(:, j) = NaN;
    end
end
singularValues = svd(jacobian);
if isempty(singularValues) || singularValues(end) == 0
    conditionNumber = Inf;
else
    conditionNumber = singularValues(1) / singularValues(end);
end
end

function [candidate, evaluation, residual, accepted] = ...
        local_line_search( ...
        engine, cfg, stepInValue, z, step, currentNorm, loadBoundary)
candidate = z;
evaluation = local_evaluate(engine, cfg, stepInValue, z, loadBoundary);
residual = evaluation.residual;
accepted = false;
for alpha = [1, 0.5, 0.25, 0.125, 0.0625, 0.03125]
    trial = z + alpha * step;
    if ~local_inside_np(trial,loadBoundary),continue;end
    trialEvaluation = local_evaluate( ...
        engine, cfg, stepInValue, trial, loadBoundary);
    trialResidual = trialEvaluation.residual;
    trialNorm = norm(trialResidual, inf);
    if isfinite(trialNorm) && trialNorm < currentNorm
        candidate = trial;
        evaluation = trialEvaluation;
        residual = trialResidual;
        accepted = true;
        return;
    end
end
end

function evaluation = local_evaluate( ...
        engine, cfg, stepInTemplate, z, loadBoundary)
stepInValue = stepInTemplate(:);
if numel(z) == 9
    npIndex = 8;
    ngIndex = 9;
else
    npIndex = 5;
    ngIndex = 6;
end
nativeTorque = stepInValue(8)==1;
% 新接口由DLL按当前候选转速换算功率，MATLAB不得重复换算。
% 旧接口(8)=0仍保留原有逐残差换算，供历史程序回归。
if loadBoundary.usePtTorque
    stepInValue(6) = loadBoundary.ptLoadTorqueNm;
    if ~nativeTorque,stepInValue(6)=stepInValue(6)*pi*z(npIndex)/30;end
end
if loadBoundary.useGtTorque
    stepInValue(7) = loadBoundary.gtLoadTorqueNm;
    if ~nativeTorque,stepInValue(7)=stepInValue(7)*pi*z(ngIndex)/30;end
end
ptPower=stepInValue(6);gtPower=stepInValue(7);
if nativeTorque
    ptPower=ptPower*pi*z(npIndex)/30;gtPower=gtPower*pi*z(ngIndex)/30;
end
if ~isempty(loadBoundary.exhaustBackPressureModel)
    exhaust=loadBoundary.exhaustBackPressureModel;
    % 与扭矩功率一样，背压必须在每次Newton残差及差分求值中更新。
    stepInValue(10)=sht_exhaust_backpressure( ...
        exhaust.ambientPressure_Pa,ptPower,exhaust);
end
stepInValue(21:(20 + numel(z))) = z(:);
engPtrInit.eng = libstruct(engine.engineStructName);
engPtr = libstruct(engine.enginePointerName, engPtrInit);
stepIn = libpointer('doublePtr', stepInValue);
stepOut = libpointer('doublePtr', ...
    zeros(cfg.engine.interface.stepOutLength, 1));
[ret, ~, stepOutValue, engOut] = calllib( ...
    engine.libraryName, 'DLL_SHT_RunSteadyComponents', ...
    stepIn, stepOut, engPtr);
evaluation = struct();
evaluation.ret = ret;
evaluation.stepOut = stepOutValue(:);
evaluation.engOut = engOut;
evaluation.residual = stepOutValue(1:numel(z));
evaluation.convergeTag = engOut.eng.convergeTag;
evaluation.ptLoadPowerW = ptPower;
evaluation.gtLoadPowerW = gtPower;
evaluation.exhaustBackPressurePa = stepInValue(10);
evaluation.maxModelResidual = max(abs([ ...
    double(engOut.eng.errOut(:)); double(engOut.eng.Nozzle.y(end))]));
end

function tf = local_is_converged(evaluation, residual, settings)
tf = evaluation.ret == 0 && all(isfinite(residual)) && ...
    max(abs(residual)) <= settings.residualTolerance;
end

function solve = local_pack( ...
        z, evaluation, residual, iteration, converged, conditionNumber)
solve = struct();
solve.converged = logical(converged);
solve.iteration = iteration;
solve.varIte = z(:);
solve.residual = residual(:);
solve.residualInfinityNorm = norm(residual, inf);
solve.jacobianConditionNumber = conditionNumber;
solve.ret = evaluation.ret;
solve.stepOut = evaluation.stepOut;
solve.engOut = evaluation.engOut;
solve.convergeTag = evaluation.convergeTag;
solve.maxModelResidual = evaluation.maxModelResidual;
solve.ptLoadPowerW = evaluation.ptLoadPowerW;
solve.gtLoadPowerW = evaluation.gtLoadPowerW;
solve.exhaustBackPressurePa = evaluation.exhaustBackPressurePa;
end

function options = local_load_boundary_options(userOptions)
if ~isstruct(userOptions) || ~isscalar(userOptions)
    error('SHT:SteadySeedSolve:BadOptions', ...
        'userOptions必须为标量结构体。');
end
options = struct('usePtTorque', false, 'ptLoadTorqueNm', NaN, ...
    'useGtTorque', false, 'gtLoadTorqueNm', NaN, ...
    'exhaustBackPressureModel',[],'npBoundsRpm',[]);
if isfield(userOptions,'npBoundsRpm') && ~isempty(userOptions.npBoundsRpm)
    b=userOptions.npBoundsRpm;
    assert(isnumeric(b) && isreal(b) && numel(b)==2 && all(isfinite(b)) && ...
        b(1)>0 && b(2)>b(1),'SHT:SteadySeedSolve:BadNpBounds', ...
        'npBoundsRpm必须为正的严格递增二元边界。');
    options.npBoundsRpm=b(:).';
end
if isfield(userOptions,'exhaustBackPressureModel')
    options.exhaustBackPressureModel=userOptions.exhaustBackPressureModel;
end
if isfield(userOptions, 'ptLoadTorqueNm') && ...
        ~isempty(userOptions.ptLoadTorqueNm)
    options.usePtTorque = true;
    options.ptLoadTorqueNm = userOptions.ptLoadTorqueNm;
end
if isfield(userOptions, 'gtLoadTorqueNm') && ...
        ~isempty(userOptions.gtLoadTorqueNm)
    options.useGtTorque = true;
    options.gtLoadTorqueNm = userOptions.gtLoadTorqueNm;
end
end

function tf=local_inside_np(z,options)
tf=isempty(options.npBoundsRpm) || (z(end-1)>=options.npBoundsRpm(1) && ...
    z(end-1)<=options.npBoundsRpm(2));
end

function scale = local_variable_scale(cfg, variableCount)
if variableCount == 9
    scale = [10; 1; 1; 5; 5; 5; 5; ...
        cfg.engine.initial.Np0; cfg.engine.initial.Ng0];
elseif variableCount == 6
    scale = [10; 1; 5; 5; ...
        cfg.engine.initial.Np0; cfg.engine.initial.Ng0];
else
    error('SHT:SteadySeedSolve:BadDimension', ...
        '共同工作初值只能是三部件6维或六部件9维，当前为%d维。', ...
        variableCount);
end
end

function local_validate_inputs( ...
        engine, cfg, stepInValue, initialVarIte, loadBoundary)
if ~isstruct(engine) || ~isfield(engine, 'libraryName') || ...
        ~libisloaded(engine.libraryName)
    error('SHT:SteadySeedSolve:EngineNotOpen', ...
        'engine必须是已经打开的涡轴发动机DLL句柄。');
end
if ~isstruct(cfg) || ~isfield(cfg, 'engine') || ...
        ~isfield(cfg.engine, 'interface')
    error('SHT:SteadySeedSolve:BadConfig', ...
        'cfg缺少engine.interface。');
end
if ~isnumeric(stepInValue) || ...
        numel(stepInValue) ~= cfg.engine.interface.stepInLength || ...
        any(~isfinite(stepInValue(:)))
    error('SHT:SteadySeedSolve:BadStepIn', ...
        'stepInValue必须是完整有限DLL输入向量。');
end
if ~isnumeric(initialVarIte) || ...
        ~ismember(numel(initialVarIte), [6, 9]) || ...
        any(~isfinite(initialVarIte(:)))
    error('SHT:SteadySeedSolve:BadInitialGuess', ...
        'initialVarIte必须是有限的6维或9维共同工作初值。');
end
expectedDimension = 6;
if cfg.engine.modelMode == 1
    expectedDimension = 9;
end
if numel(initialVarIte) ~= expectedDimension
    error('SHT:SteadySeedSolve:ModeDimensionMismatch', ...
        'modelMode=%d要求%d维初值，实际为%d维。', ...
        cfg.engine.modelMode, expectedDimension, numel(initialVarIte));
end
if loadBoundary.usePtTorque && ...
        (~isnumeric(loadBoundary.ptLoadTorqueNm) || ...
        ~isscalar(loadBoundary.ptLoadTorqueNm) || ...
        ~isfinite(loadBoundary.ptLoadTorqueNm))
    error('SHT:SteadySeedSolve:BadPtLoadTorque', ...
        'ptLoadTorqueNm必须为有限标量。');
end
if loadBoundary.useGtTorque && ...
        (~isnumeric(loadBoundary.gtLoadTorqueNm) || ...
        ~isscalar(loadBoundary.gtLoadTorqueNm) || ...
        ~isfinite(loadBoundary.gtLoadTorqueNm))
    error('SHT:SteadySeedSolve:BadGtLoadTorque', ...
        'gtLoadTorqueNm必须为有限标量。');
end
end
