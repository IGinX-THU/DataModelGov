function result = sht_dp_v1_solver(action,cfg,reference)
% 三部件原数值函数的受控抽取；见solver_extraction.csv逐函数来源。
% 所有指针限制在此函数内；返回后由外层释放自己加载的库。
if strcmp(action,'defaults'),result=local_defaults();return;end
alias=cfg.interface.alias;
engInit.eng=libstruct(cfg.interface.engineStructName);
engPtr=libstruct(cfg.interface.enginePointerName,engInit);
stepIn=libpointer('doublePtr',zeros(512,1));
stepOut=libpointer('doublePtr',zeros(128,1));
local_initialize(alias,engPtr,stepIn,stepOut,cfg);
if strcmp(action,'solve')
    [solution,history,design]=local_solve_design(alias,engPtr,stepIn,stepOut,cfg);
    result=struct('design',design,'solution',solution,'iterationHistory',history, ...
        'designState',local_make_design_state(solution,design,cfg),'accepted',design.converged);
elseif strcmp(action,'test')
    result=local_verify_operational_configuration(alias,engPtr,stepIn,stepOut,true,reference,cfg);
else
    error('sht:dp:action','未知私有求解操作。');
end
end

function cfg = local_defaults()
cfg.interface.alias = 'GTESS';
cfg.interface.engineStructName = 'EngineTurboshaft';
cfg.interface.enginePointerName = 'EngineSHTPointer';
cfg.interface.stepInLength = 512;
cfg.interface.stepOutLength = 128;

cfg.design.NpRpm = 20900.0;
cfg.design.NgRpm = 38000.0;
cfg.design.Wf0 = 0.15171;
cfg.design.nozzleAreaM2 = 0.10573;
cfg.design.loadPowerW = 2176600.0;
cfg.design.accessoryPowerW = 0.0;
cfg.design.targetTt4K = 1620.0;

% 变量顺序：[W2, Rline_HPC, PR_GT, PR_PT, Np, Ng, Wf]。
% scale 用于构造无量纲有限差分和限制单次 Newton 步长。
cfg.solver.initial = [6.693; 0.6; 3.820; 3.568; ...
    cfg.design.NpRpm; cfg.design.NgRpm; cfg.design.Wf0];
cfg.solver.scale = [10; 1; 5; 5; cfg.design.NpRpm; cfg.design.NgRpm; 0.3];
cfg.solver.lower = [0.5; -0.5; 1.01; 1.01; 1000; 5000; 0.03];
cfg.solver.upper = [20; 1.5; 10; 10; 40000; 80000; 0.4];
cfg.solver.finiteDifferenceStep = 1.0e-4;
cfg.solver.maximumIterations = 40;
cfg.solver.residualTolerance = 1.0e-8;
cfg.solver.minimumLineSearchFactor = 1.0 / 256.0;
cfg.solver.maximumNormalizedStep = 0.5;

cfg.tolerance.operationalResidual = 1.0e-7;
cfg.tolerance.designReplayRelative = 1.0e-7;
cfg.tolerance.scaleReplayRelative = 1.0e-8;

end

function local_initialize(alias, engPtr, stepIn, stepOut, cfg)
status = calllib(alias, 'DLL_SHT_InitialMode', 0);
assert(status == 0, 'mode=0 原三部件模型初始化失败，状态码=%d。', status);
stepIn.Value = zeros(cfg.interface.stepInLength, 1);
stepOut.Value = zeros(cfg.interface.stepOutLength, 1);
stepIn.Value(11:13) = [0; 0; 0];
[status, ~, ~, initialized] = calllib( ...
    alias, 'DLL_SHT_ConditionsInit', stepIn, stepOut, engPtr);
assert(status == 0, '原三部件模型环境条件初始化失败，状态码=%d。', status);
% 设计模式的涡轮残差是(Nmech-NDes)/NDes，NDes来自MDL。
% M侧初值并不能改变这个约束；不一致时明确要求人工处理，不静默改MDL。
eng = initialized.eng;
if eng.offDesignMode == 0
    assert(abs(eng.LPT.turbineStruct.NDes-cfg.design.NpRpm) <= 1e-8 && ...
        abs(eng.HPT.turbineStruct.NDes-cfg.design.NgRpm) <= 1e-8, ...
        'RunModelSHT_V1:DesignSpeedMismatch', ...
        ['设计转速不一致：MDL的LPT/HPT.NDes=%.12g/%.12g rpm，' ...
         'M目标Np/Ng=%.12g/%.12g rpm。请审核并手工更新MDL；' ...
         '程序不会把初值改动误报为设计目标已更新。'], ...
        eng.LPT.turbineStruct.NDes, eng.HPT.turbineStruct.NDes, ...
        cfg.design.NpRpm, cfg.design.NgRpm);
end
end

function [solution, history, design] = local_solve_design( ...
    alias, engPtr, stepIn, stepOut, cfg)
x = min(max(cfg.solver.initial(:), cfg.solver.lower), cfg.solver.upper);
n = numel(x);
history.iteration = zeros(cfg.solver.maximumIterations, 1);
history.residualInfinityNorm = nan(cfg.solver.maximumIterations, 1);
history.residualTwoNorm = nan(cfg.solver.maximumIterations, 1);
history.lineSearchFactor = nan(cfg.solver.maximumIterations, 1);
history.jacobianReciprocalCondition = nan(cfg.solver.maximumIterations, 1);
history.variable = nan(cfg.solver.maximumIterations, n);

for iteration = 1:cfg.solver.maximumIterations
    residual = local_design_residual( ...
        alias, engPtr, stepIn, stepOut, x, cfg);
    residualInf = norm(residual, inf);
    residualTwo = norm(residual, 2);
    history.iteration(iteration) = iteration;
    history.residualInfinityNorm(iteration) = residualInf;
    history.residualTwoNorm(iteration) = residualTwo;
    history.variable(iteration, :) = x.';

    fprintf('V1 设计点迭代 %2d：max|r|=%.6e, ||r||2=%.6e\n', ...
        iteration, residualInf, residualTwo);
    if residualInf <= cfg.solver.residualTolerance
        break;
    end

    jacobian = zeros(n, n);
    h = cfg.solver.finiteDifferenceStep;
    for j = 1:n
        plus = x;
        minus = x;
        plus(j) = min(cfg.solver.upper(j), ...
            x(j) + h * cfg.solver.scale(j));
        minus(j) = max(cfg.solver.lower(j), ...
            x(j) - h * cfg.solver.scale(j));
        normalizedSpan = (plus(j) - minus(j)) / cfg.solver.scale(j);
        assert(normalizedSpan > 0, 'V1 变量 %d 的有限差分区间退化。', j);
        residualPlus = local_design_residual( ...
            alias, engPtr, stepIn, stepOut, plus, cfg);
        residualMinus = local_design_residual( ...
            alias, engPtr, stepIn, stepOut, minus, cfg);
        jacobian(:, j) = (residualPlus - residualMinus) / normalizedSpan;
    end

    reciprocalCondition = rcond(jacobian);
    history.jacobianReciprocalCondition(iteration) = reciprocalCondition;
    if reciprocalCondition > 1.0e-12
        normalizedStep = -(jacobian \ residual);
    else
        regularization = max(1.0e-10, ...
            1.0e-6 * norm(jacobian, 'fro')^2);
        normalizedStep = -(jacobian.' * jacobian + ...
            regularization * eye(n)) \ (jacobian.' * residual);
    end
    maximumStep = max(abs(normalizedStep));
    if maximumStep > cfg.solver.maximumNormalizedStep
        normalizedStep = normalizedStep * ...
            (cfg.solver.maximumNormalizedStep / maximumStep);
    end

    accepted = false;
    factor = 1.0;
    while factor >= cfg.solver.minimumLineSearchFactor
        candidate = x + factor * normalizedStep .* cfg.solver.scale;
        candidate = min(max(candidate, cfg.solver.lower), cfg.solver.upper);
        candidateResidual = local_design_residual( ...
            alias, engPtr, stepIn, stepOut, candidate, cfg);
        if norm(candidateResidual, 2) < residualTwo
            x = candidate;
            accepted = true;
            break;
        end
        factor = factor / 2.0;
    end
    history.lineSearchFactor(iteration) = factor;
    assert(accepted, ['V1 设计点迭代无法找到降低残差的候选步。', ...
        '请检查设计点输入、特性图覆盖或初值。']);
end

[finalResidual, finalSample] = local_design_residual( ...
    alias, engPtr, stepIn, stepOut, x, cfg);
% 最终DLL复算是成功标志的唯一依据，不得沿用循环内某次成功状态。
converged = all(isfinite(finalResidual)) && ...
    norm(finalResidual, inf) <= cfg.solver.residualTolerance;
assert(converged, 'RunModelSHT_V1:FinalDesignNotConverged', ...
    ['V1设计点最终复算不通过，实际迭代%d次，最大残差%.6e；' ...
     '7项残差[HPC,GT,PT,喷管,Np轴,Ng轴,Tt4]=%s。'], ...
    iteration, norm(finalResidual, inf), mat2str(finalResidual(:).', 9));

used = find(history.iteration > 0, 1, 'last');
fields = fieldnames(history);
for i = 1:numel(fields)
    value = history.(fields{i});
    history.(fields{i}) = value(1:used, :);
end

solution = x;
design = finalSample;
design.residual = finalResidual;
design.maxResidual = norm(finalResidual, inf);
design.converged = converged;
end

function [residual, sample] = local_design_residual( ...
    alias, engPtr, stepIn, stepOut, x, cfg)
stepIn.Value = local_base_step_in(cfg, x(7));
stepIn.Value(21:26) = x(1:6);
[status, ~, stepOutValue, engOut] = calllib( ...
    alias, 'DLL_SHT_RunSteadyComponents', stepIn, stepOut, engPtr);
assert(status == 0, 'V1 设计点部件求值失败，状态码=%d。', status);
eng = engOut.eng;

residual = [stepOutValue(1:6); ...
    (eng.Burner.y(3) - cfg.design.targetTt4K) / cfg.design.targetTt4K];
assert(all(isfinite(residual)), 'V1 设计点部件求值产生 NaN/Inf。');

sample.commonVariables = x(1:6).';
sample.Wf = x(7);
sample.Tt4K = eng.Burner.y(3);
sample.output = local_capture_output(eng);
sample.scalars = local_capture_design_scalars(eng);
sample.stationTable = local_station_table(eng);
end

function designState = local_make_design_state(solution, design, cfg)
designState.schemaVersion = 1;
designState.generatedAt = datestr(now, 31);
designState.modelMode = 0;
designState.modelConfiguration = 'Turboshaft-TS.mdl';
designState.solution = solution;
designState.design = design;
designState.targetTt4K = cfg.design.targetTt4K;
end

function verification = local_verify_operational_configuration( ...
    alias, engPtr, stepIn, stepOut, hasDesignState, designState, cfg)
if hasDesignState
    design = designState.design;
    wf = design.Wf;

    % 先用设计求解得到的共同工作变量直接回放，专门检查人工录入的
    % 缩放系数是否能复现设计模式结果。
    stepIn.Value = local_base_step_in(cfg, wf);
    stepIn.Value(21:26) = design.commonVariables;
    [status, ~, directOut, directEngOut] = calllib( ...
        alias, 'DLL_SHT_RunSteadyComponents', stepIn, stepOut, engPtr);
    assert(status == 0, 'V1 手工配置直接回放失败，状态码=%d。', status);
    directEng = directEngOut.eng;
    verification.directResidual = directOut(1:6).';
    verification.directMaxResidual = max(abs(verification.directResidual));
    verification.directOutput = local_capture_output(directEng);
    verification.designReplayRelative = abs( ...
        verification.directOutput - design.output) ./ max(abs(design.output), 1);
    verification.designReplayMaxRelative = ...
        max(verification.designReplayRelative);
    inputScalars = local_capture_input_scalars(directEng);
    verification.scaleReplayRelative = local_relative_difference( ...
        inputScalars.vector, design.scalars.vector);
    verification.scaleReplayMaxRelative = ...
        max(verification.scaleReplayRelative);
else
    wf = cfg.design.Wf0;
    verification.directResidual = nan(1, 6);
    verification.directMaxResidual = nan;
    verification.directOutput = nan(1, 10);
    verification.designReplayRelative = nan(1, 10);
    verification.designReplayMaxRelative = nan;
    verification.scaleReplayRelative = nan(1, 12);
    verification.scaleReplayMaxRelative = nan;
end

% 再从 MDL 的 varStartVec 出发调用 C 端 Newton，验证配置可以脱离
% 设计求解器独立加载和收敛。
stepIn.Value = local_base_step_in(cfg, wf);
[status, ~, ~, trimEngOut] = calllib( ...
    alias, 'DLL_SHT_RunOnePoint', stepIn, stepOut, engPtr);
assert(status == 0, 'V1 手工配置 C 端 Newton 调用失败，状态码=%d。', status);
trimEng = trimEngOut.eng;
verification.trimConvergeTag = trimEng.convergeTag;
verification.trimConverged = trimEng.convergeTag == 0;
verification.trimResidual = trimEng.errOut(1:6).';
verification.trimMaxResidual = max(abs(verification.trimResidual));
verification.trimVariables = trimEng.varIte(1:6).';
verification.trimOutput = local_capture_output(trimEng);
verification.Tt4K = trimEng.Burner.y(3);
verification.stationTable = local_station_table(trimEng);
verification.operationalAccepted = verification.trimConverged && ...
    verification.trimMaxResidual <= cfg.tolerance.operationalResidual;
% 历史设计MAT可能仍对应20800 rpm。能够复现旧MAT不等于满足当前目标。
verification.targetSpeedRpm = [cfg.design.NpRpm, cfg.design.NgRpm];
verification.actualSpeedRpm = [trimEng.LPS_Nmech, trimEng.HPS_Nmech];
verification.targetSpeedRelative = abs(verification.actualSpeedRpm - ...
    verification.targetSpeedRpm) ./ verification.targetSpeedRpm;
verification.targetSpeedAccepted = ...
    all(verification.targetSpeedRelative <= cfg.tolerance.designReplayRelative);

if hasDesignState
    verification.accepted = verification.operationalAccepted && ...
        verification.targetSpeedAccepted && ...
        verification.directMaxResidual <= cfg.tolerance.operationalResidual && ...
        verification.designReplayMaxRelative <= ...
            cfg.tolerance.designReplayRelative && ...
        verification.scaleReplayMaxRelative <= ...
            cfg.tolerance.scaleReplayRelative;
else
    % 没有设计状态时只能证明当前 MDL 可运行，不能证明其确实复现了
    % 本程序生成的设计参数，因此不标记为完整设计复现验收通过。
    verification.accepted = false;
end
end

function value = local_base_step_in(cfg, wf)
value = zeros(cfg.interface.stepInLength, 1);
value(1:10) = [cfg.design.NpRpm; cfg.design.NgRpm; wf; ...
    cfg.design.nozzleAreaM2; 0; cfg.design.loadPowerW; ...
    cfg.design.accessoryPowerW; 0; 0; 0];
end

function scalars = local_capture_design_scalars(eng)
scalars.HPC = [eng.HPC.s_C_Nc_des, eng.HPC.s_C_Wc_des, ...
    eng.HPC.s_C_PR_des, eng.HPC.s_C_Eff_des];
scalars.GT = [eng.HPT.s_T_Nc_des, eng.HPT.s_T_Wc_des, ...
    eng.HPT.s_T_PR_des, eng.HPT.s_T_Eff_des];
scalars.PT = [eng.LPT.s_T_Nc_des, eng.LPT.s_T_Wc_des, ...
    eng.LPT.s_T_PR_des, eng.LPT.s_T_Eff_des];
scalars.vector = [scalars.HPC, scalars.GT, scalars.PT];
end

function scalars = local_capture_input_scalars(eng)
scalars.HPC = [eng.HPC.s_C_Nc_in, eng.HPC.s_C_Wc_in, ...
    eng.HPC.s_C_PR_in, eng.HPC.s_C_Eff_in];
scalars.GT = [eng.HPT.turbineStruct.s_T_Nc, ...
    eng.HPT.turbineStruct.s_T_Wc, eng.HPT.turbineStruct.s_T_PR, ...
    eng.HPT.turbineStruct.s_T_Eff];
scalars.PT = [eng.LPT.turbineStruct.s_T_Nc, ...
    eng.LPT.turbineStruct.s_T_Wc, eng.LPT.turbineStruct.s_T_PR, ...
    eng.LPT.turbineStruct.s_T_Eff];
scalars.vector = [scalars.HPC, scalars.GT, scalars.PT];
end

function output = local_capture_output(eng)
output = [eng.HPC.y(1), eng.HPC.y(3), eng.HPC.y(4), ...
    eng.HPT.y(3), eng.HPT.y(4), eng.LPT.y(3), eng.LPT.y(4), ...
    eng.LPS_Nmech, eng.HPS_Nmech, eng.LPS_Trq];
end

function table = local_station_table(eng)
table = [ ...
    2,  eng.HPC.u(1),    eng.HPC.u(3),    eng.HPC.u(4),    eng.HPC.u(2); ...
    3,  eng.HPC.y(1),    eng.HPC.y(3),    eng.HPC.y(4),    eng.HPC.y(2); ...
    4,  eng.Burner.y(1), eng.Burner.y(3), eng.Burner.y(4), eng.Burner.y(2); ...
    44, eng.HPT.y(1),    eng.HPT.y(3),    eng.HPT.y(4),    eng.HPT.y(2); ...
    5,  eng.LPT.y(1),    eng.LPT.y(3),    eng.LPT.y(4),    eng.LPT.y(2); ...
    8,  eng.Nozzle.y(1), eng.Nozzle.y(2), eng.Nozzle.y(9), eng.Nozzle.y(11)];
end

function relative = local_relative_difference(a, b)
relative = abs(a - b) ./ max(abs(b), 1.0e-15);
end

