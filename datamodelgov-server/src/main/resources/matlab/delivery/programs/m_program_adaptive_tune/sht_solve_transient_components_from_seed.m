function solve = sht_solve_transient_components_from_seed( ...
        engine, cfg, stepInValue, initialVarIte)
%SHT_SOLVE_TRANSIENT_COMPONENTS_FROM_SEED 稳健求解固定轴速下的共同工作方程。
%
% DLL_SHT_RunOneStep 内部使用C端Newton直接求解瞬态共同工作变量。该
% 求解器用于诊断其未收敛样本：保持Np、Ng、Wf、轴负载、边界条件和
% 健康参数完全不变，只替换七维共同工作方程的数值求解策略。因此：
%   1) 若本函数收敛而RunOneStep未收敛，问题属于初值/内置Newton鲁棒性；
%   2) 若缩小修正系数后本函数才收敛，说明参数幅值或组合使工况逼近
%      特性图、流量或共同工作可行域边界；
%   3) 本函数只作诊断，不改变正式后验样本及其权重。
%
% 六部件模式求解7个气路共同工作变量；三部件模式求解4个。两轴转速
% 始终由stepInValue(1:2)固定，不进入待求变量。

local_validate_inputs(engine, cfg, stepInValue, initialVarIte);
z = initialVarIte(:);
n = numel(z);
settings = struct('maxIteration', 30, ...
    'residualTolerance', 1e-7, ...
    'normalizedPerturbation', 1e-4, ...
    'scale', local_variable_scale(n));

evaluation = local_evaluate(engine, cfg, stepInValue, z);
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
        engine, cfg, stepInValue, z, residual, settings);
    if any(~isfinite(jacobian(:))) || rcond(jacobian) < 1e-14
        break;
    end
    normalizedStep = -(jacobian \ residual);
    physicalStep = normalizedStep(:) .* settings.scale(:);
    [candidate, candidateEvaluation, candidateResidual, accepted] = ...
        local_line_search(engine, cfg, stepInValue, z, ...
        physicalStep, bestNorm);
    if ~accepted
        break;
    end

    z = candidate;
    evaluation = candidateEvaluation;
    residual = candidateResidual;
    bestNorm = norm(residual, inf);
end

solve = local_pack(z, evaluation, residual, iteration, ...
    false, conditionNumber);
end

function [jacobian, conditionNumber] = local_jacobian( ...
        engine, cfg, stepInValue, z, residual0, settings)
n = numel(z);
jacobian = zeros(n, n);
for j = 1:n
    delta = settings.normalizedPerturbation * settings.scale(j);
    plus = z;
    minus = z;
    plus(j) = plus(j) + delta;
    minus(j) = minus(j) - delta;
    plusEvaluation = local_evaluate(engine, cfg, stepInValue, plus);
    minusEvaluation = local_evaluate(engine, cfg, stepInValue, minus);
    plusResidual = plusEvaluation.residual;
    minusResidual = minusEvaluation.residual;
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
        local_line_search(engine, cfg, stepInValue, z, step, currentNorm)
candidate = z;
evaluation = local_evaluate(engine, cfg, stepInValue, z);
residual = evaluation.residual;
accepted = false;
for alpha = [1, 0.5, 0.25, 0.125, 0.0625, 0.03125, 0.015625]
    trial = z + alpha * step;
    trialEvaluation = local_evaluate(engine, cfg, stepInValue, trial);
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

function evaluation = local_evaluate(engine, cfg, stepInTemplate, z)
stepInValue = stepInTemplate(:);
stepInValue(21:(20 + numel(z))) = z(:);
engPtrInit.eng = libstruct(engine.engineStructName);
engPtr = libstruct(engine.enginePointerName, engPtrInit);
stepIn = libpointer('doublePtr', stepInValue);
stepOut = libpointer('doublePtr', ...
    zeros(cfg.engine.interface.stepOutLength, 1));
[ret, ~, stepOutValue, engOut] = calllib( ...
    engine.libraryName, 'DLL_SHT_RunTransientComponents', ...
    stepIn, stepOut, engPtr);
evaluation = struct('ret', ret, 'stepOut', stepOutValue(:), ...
    'engOut', engOut, 'residual', stepOutValue(1:numel(z)), ...
    'convergeTag', engOut.eng.convergeTag);
end

function tf = local_is_converged(evaluation, residual, settings)
tf = evaluation.ret == 0 && all(isfinite(residual)) && ...
    max(abs(residual)) <= settings.residualTolerance;
end

function solve = local_pack( ...
        z, evaluation, residual, iteration, converged, conditionNumber)
solve = struct('converged', logical(converged), ...
    'iteration', iteration, 'varIte', z(:), ...
    'residual', residual(:), ...
    'residualInfinityNorm', norm(residual, inf), ...
    'jacobianConditionNumber', conditionNumber, ...
    'ret', evaluation.ret, 'stepOut', evaluation.stepOut, ...
    'engOut', evaluation.engOut, ...
    'convergeTag', evaluation.convergeTag);
end

function scale = local_variable_scale(variableCount)
if variableCount == 7
    scale = [10; 1; 1; 5; 5; 5; 5];
elseif variableCount == 4
    scale = [10; 1; 5; 5];
else
    error('SHT:TransientSeedSolve:BadDimension', ...
        '共同工作初值只能是三部件4维或六部件7维，当前为%d维。', ...
        variableCount);
end
end

function local_validate_inputs(engine, cfg, stepInValue, initialVarIte)
if ~isstruct(engine) || ~isfield(engine, 'libraryName') || ...
        ~libisloaded(engine.libraryName)
    error('SHT:TransientSeedSolve:EngineNotOpen', ...
        'engine必须是已经打开的涡轴发动机DLL句柄。');
end
if ~isstruct(cfg) || ~isfield(cfg, 'engine') || ...
        ~isfield(cfg.engine, 'interface')
    error('SHT:TransientSeedSolve:BadConfig', ...
        'cfg缺少engine.interface。');
end
if ~isnumeric(stepInValue) || ...
        numel(stepInValue) ~= cfg.engine.interface.stepInLength || ...
        any(~isfinite(stepInValue(:)))
    error('SHT:TransientSeedSolve:BadStepIn', ...
        'stepInValue必须是完整有限DLL输入向量。');
end
if ~isnumeric(initialVarIte) || ...
        ~ismember(numel(initialVarIte), [4, 7]) || ...
        any(~isfinite(initialVarIte(:)))
    error('SHT:TransientSeedSolve:BadInitialGuess', ...
        'initialVarIte必须是有限的4维或7维共同工作初值。');
end
expectedDimension = 4;
if cfg.engine.modelMode == 1
    expectedDimension = 7;
end
if numel(initialVarIte) ~= expectedDimension
    error('SHT:TransientSeedSolve:ModeDimensionMismatch', ...
        'modelMode=%d要求%d维初值，实际为%d维。', ...
        cfg.engine.modelMode, expectedDimension, numel(initialVarIte));
end
end
