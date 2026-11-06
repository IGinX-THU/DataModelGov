function e=sht_tc27_thermal_reuse(engine,x,wf,b,reference,solveOptions)
%SHT_TC27_THERMAL_REUSE 固定参考Jacobian的温度校正，全部残差来自真实DLL。
% 仅服务三部件UQ的thermal_only回放；不改变共享求解器默认行为。
% 参考矩阵在采样前冻结，不按候选到达顺序更新，因此缓存命中、粒子
% 排序及续跑不能改变目标函数。复用失效后从原初值、原气路种子完整求解。
assert(numel(x)==16 && isstruct(reference) && ...
    strcmp(reference.solveMode,'thermal_only'),'TC27:ThermalReuse:Contract', ...
    '复用仅支持三部件Visser16、固定轴速的热平衡。');
o=reference.options;J=reference.jacobian;factor=reference.reuseFactor;
assert(isequal(size(J),[14,14])&&all(isfinite(J(:)))&& ...
    isequal(size(factor.L),[14,14]),'TC27:ThermalReuse:Jacobian','参考Jacobian无效。');
originalState=x;seed=double(engine.callContext.engPtr.eng.varIte(1:6));
x(3:end)=reference.state(3:end);initial=x;maximumCorrections=6;
evaluationCount=0;trace=zeros(maximumCorrections+1,2);reason='correction_budget';
for iteration=0:maximumCorrections
    evaluationCount=evaluationCount+1;
    try
        [dx,y,d]=sht_engine_derivative(engine,x,wf,b);
    catch exception
        % DLL拒绝等同于原ret非零分支，从原初值进入完整求解器。
        % 最终仍失败时由完整求解器保留原始诊断，不使用残留输出。
        if ~strcmp(exception.identifier,'sht:engine:dllEvaluationFailed')
            rethrow(exception);
        end
        reason='physical_replay_needs_full_solver';break;
    end
    if d.ret~=0 || d.convergeTag~=0 || d.evaluationValid~=1 || ...
            ~isfinite(d.maxErr) || d.maxErr>o.strictCommonWorkResidual || ...
            numel(dx)~=16 || any(~isfinite(dx))
        reason='physical_replay_needs_full_solver';break;
    end
    residual=dx(3:end)./o.residualScale(3:end);
    correction=-(factor.U\(factor.L\(factor.P*residual)));
    trace(iteration+1,:)=[max(abs(dx(3:end))),max(abs(correction))];
    if max(abs(dx(3:end)))<=o.strictThermalDerivativeTolerance_Kps && ...
            max(abs(correction))<=o.remainingTemperatureCorrectionTolerance_K
        % 直接使用刚刚通过检查的真实输出，不再重复回放或末端差分。
        e=reference;e.state=x;e.initialState=initial;e.derivative=dx;e.output=y;e.diagnostics=d;
        e.fuelFlow_kgps=wf;e.initialFuelFlow_kgps=wf;e.options=o;
        e.strictConverged=true;e.strictResidualPassed=true;e.engineeringResidualPassed=true;
        e.thermalPassed=true;e.shaftPassed=max(abs(dx(1:2)))<=o.engineeringShaftDerivativeTolerance_rpmps;
        e.remainingCorrectionPassed=true;e.physicalValid=true;
        e.stopReason='reused_jacobian_strict_thermal_equilibrium';
        e.iterationCount=iteration;e.evaluationCount=evaluationCount;e.remainingCorrection=correction;
        e.finalMaximumThermalDerivative_Kps=max(abs(dx(3:end)));
        e.finalMaximumShaftDerivative_rpmps=max(abs(dx(1:2)));e.finalCommonWorkResidual=d.maxErr;
        e.temperatureRange_K=[min(x(3:end)),max(x(3:end))];
        e.normalizedEnergyResidual=local_field(d,'visserNormalizedEnergyResidual',NaN);
        e.energyResidual_W=local_field(d,'visserEnergyResidual_W',NaN);
        e.history=array2table(trace(1:iteration+1,:), ...
            'VariableNames',{'maxThermalDerivative_Kps','remainingCorrection_K'});
        % 参考Jacobian不是最终点的精确导数，不能冒充稳定性谱审计。
        e.maximumRealJacobianEigenvalue=NaN;e.finalJacobianIsReference=true;
        e.reuse=struct('attempted',true,'fallback',false,'newDifferenceColumns',0, ...
            'fastEvaluations',evaluationCount,'reason','strict_residual_passed');
        return;
    end
    if iteration==maximumCorrections,break;end
    if any(~isfinite(correction)) || max(abs(correction))>o.maximumTemperatureCorrection_K
        reason='correction_outside_trusted_scale';break;
    end
    if iteration>0 && trace(iteration+1,1)>.8*trace(iteration,1)
        reason='insufficient_residual_contraction';break;
    end
    candidate=x(3:end)+correction;
    if any(candidate<o.temperatureBounds_K(1)|candidate>o.temperatureBounds_K(2))
        reason='temperature_outside_bounds';break;
    end
    x(3:end)=candidate;
end
sht_tc27_reset_gas_seed(engine,seed);
e=sht_thermal_equilibrium_solve(engine,originalState,wf,b,'thermal_only',solveOptions);
e.evaluationCount=e.evaluationCount+evaluationCount;e.finalJacobianIsReference=false;
e.reuse=struct('attempted',true,'fallback',true,'newDifferenceColumns',NaN, ...
    'fastEvaluations',evaluationCount,'reason',reason);
end

function v=local_field(s,name,fallback)
v=fallback;if isfield(s,name),v=s.(name);end
end
