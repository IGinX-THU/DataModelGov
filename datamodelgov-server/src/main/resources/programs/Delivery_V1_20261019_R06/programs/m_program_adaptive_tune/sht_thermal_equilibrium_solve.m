function result = sht_thermal_equilibrium_solve( ...
        engine,initialState,initialFuelFlow,boundary,solveMode,userOptions)
%SHT_THERMAL_EQUILIBRIUM_SOLVE 三/六部件Kurzke与Visser统一气热平衡求解器。
%
% 支持三种相互独立的物理问题：
%   thermal_only  固定Np、Ng和Wf，只令当前拓扑的温度导数为零；
%   trim_fixed_np 固定Np，联合求Ng、Wf和全部温度，使轴速/温度导数为零；
%   steady_predict固定Wf，联合求Np、Ng和全部温度，使轴速/温度导数为零。
% 三部件为15/16状态，六部件为27/29状态，状态数量由输入合同确定。
%
% 本函数只求发动机物理状态，不读取测量真值、不估计健康参数，也不改变
% DLL内的健康调度或热参数配置。Newton回溯仅用于保证物理求根稳定，
% 与外层修正系数辨识中的正则化、TSVD或参数更新策略没有关系。

if nargin<6 || isempty(userOptions),userOptions=struct();end
options=local_options(userOptions,initialFuelFlow,numel(initialState));
mode=lower(string(solveMode));
if ~isscalar(mode) || ~ismember(mode, ...
        ["thermal_only","trim_fixed_np","steady_predict"])
    error('SHT:ThermalEquilibrium:BadSolveMode', ...
        'solveMode必须为thermal_only、trim_fixed_np或steady_predict。');
end
state=double(initialState(:));
wf=double(initialFuelFlow);
if ~ismember(numel(state),[15,16,27,29]) || any(~isfinite(state)) || ...
        ~isscalar(wf) || ~isfinite(wf) || wf<=0
    error('SHT:ThermalEquilibrium:BadInitialCondition', ...
        '初始状态必须匹配15/16/27/29状态拓扑，初始燃油必须为有限正数。');
end
if ~isstruct(engine) || ~isstruct(boundary)
    error('SHT:ThermalEquilibrium:BadContext', ...
        '必须提供已打开的发动机调用上下文和边界结构体。');
end

layout=local_layout(mode,state,wf,options);
[unknown,state,wf]=local_pack_initial(layout,state,wf);
evaluationCount=0;
history=repmat(local_empty_history(),options.maximumIterations+1,1);
lastJacobian=[];lastUsedStep=[];stopReason="maximum_iterations";
strictConverged=false;

for iteration=0:options.maximumIterations
    [base,state,wf]=local_evaluate_unknown( ...
        engine,unknown,state,wf,boundary,layout,options);
    evaluationCount=evaluationCount+1;
    normalizedResidual=base.derivative(layout.residualIndex)./ ...
        options.residualScale(layout.residualIndex);
    strictNow=local_residual_pass(base,layout,options,true);
    engineeringNow=local_residual_pass(base,layout,options,false);
    history(iteration+1)=local_history_row(iteration,base,normalizedResidual,0);
    if options.verbose
        fprintf(['  %s气热平衡 %2d/%2d：max|dN/dt|=%.3e rpm/s，' ...
            'max|dT/dt|=%.3e K/s，DLL残差=%.3e。\n'], ...
            options.label,iteration,options.maximumIterations, ...
            max(abs(base.derivative(1:2))), ...
            max(abs(base.derivative(3:end))),base.diagnostics.maxErr);
    end
    if strictNow
        strictConverged=true;stopReason="strict_residual_tolerance";break;
    end
    if iteration==options.maximumIterations
        if engineeringNow
            stopReason="maximum_iterations_engineering_residual_available";
        end
        break;
    end

    [jacobian,usedStep,count]=local_finite_difference_jacobian( ...
        engine,unknown,state,wf,boundary,layout,normalizedResidual,options);
    evaluationCount=evaluationCount+count;
    lastJacobian=jacobian;lastUsedStep=usedStep;
    scaledJacobian=jacobian.*layout.variableScale.';
    [u,s,v]=svd(scaledJacobian,'econ');
    singularValue=diag(s);
    if isempty(singularValue) || singularValue(1)<=0 || ...
            any(~isfinite(singularValue))
        error('SHT:ThermalEquilibrium:InvalidJacobian', ...
            '气热平衡Jacobian没有有限正奇异值。');
    end
    tolerance=max(size(scaledJacobian))*eps(singularValue(1));
    active=singularValue>tolerance;
    if nnz(active)<numel(unknown)
        error('SHT:ThermalEquilibrium:RankDeficientJacobian', ...
            '气热平衡Jacobian数值秩不足：%d/%d。',nnz(active),numel(unknown));
    end
    scaledCorrection=-v(:,active)* ...
        ((u(:,active).'*normalizedResidual)./singularValue(active));
    correction=layout.variableScale.*scaledCorrection;
    correctionScale=max(abs(correction)./layout.maximumCorrection);
    if correctionScale>1
        correction=correction/correctionScale;
    end

    accepted=false;factor=1;
    while factor>=options.minimumLineSearchFactor
        candidate=min(max(unknown+factor*correction, ...
            layout.lowerBound),layout.upperBound);
        if max(abs(candidate-(unknown+factor*correction)))> ...
                options.boundProjectionTolerance
            factor=factor/2;continue;
        end
        try
            trial=local_evaluate_unknown(engine,candidate,state,wf, ...
                boundary,layout,options);
            evaluationCount=evaluationCount+1;
            trialResidual=trial.derivative(layout.residualIndex)./ ...
                options.residualScale(layout.residualIndex);
            trialValid=trial.valid && all(isfinite(trialResidual));
        catch ME
            if ~local_recoverable_evaluation_error(ME),rethrow(ME);end
            trialValid=false;
        end
        if trialValid && norm(trialResidual,2)<norm(normalizedResidual,2)
            unknown=candidate;accepted=true;
            history(iteration+1).acceptedLineSearchFactor=factor;
            break;
        end
        factor=factor/2;
    end
    if ~accepted
        if engineeringNow
            stopReason="physical_numerical_floor_engineering_residual_available";
        else
            stopReason="line_search_no_residual_decrease";
        end
        break;
    end
end

[final,state,wf]=local_evaluate_unknown( ...
    engine,unknown,state,wf,boundary,layout,options);
evaluationCount=evaluationCount+1;
finalNormalized=final.derivative(layout.residualIndex)./ ...
    options.residualScale(layout.residualIndex);
if isempty(lastJacobian) || options.finalJacobianAudit
    [lastJacobian,lastUsedStep,count]=local_finite_difference_jacobian( ...
        engine,unknown,state,wf,boundary,layout,finalNormalized,options);
    evaluationCount=evaluationCount+count;
end
scaledJacobian=lastJacobian.*layout.variableScale.';
remainingScaled=-(scaledJacobian\finalNormalized);
remainingCorrection=layout.variableScale.*remainingScaled;

strictResidualPassed=local_residual_pass(final,layout,options,true);
engineeringResidualPassed=local_residual_pass(final,layout,options,false);
thermalPassed=max(abs(final.derivative(3:end)))<= ...
    options.engineeringThermalDerivativeTolerance_Kps;
shaftPassed=max(abs(final.derivative(1:2)))<= ...
    options.engineeringShaftDerivativeTolerance_rpmps;
if mode=="thermal_only"
    remainingPassed=max(abs(remainingCorrection))<= ...
        options.remainingTemperatureCorrectionTolerance_K;
else
    remainingPassed=local_remaining_correction_pass( ...
        remainingCorrection,layout,options);
end
physicalValid=final.valid && engineeringResidualPassed && remainingPassed;

usedHistory=history(1:(iteration+1));
result=struct();
result.schemaVersion='SHT_THERMAL_EQUILIBRIUM_V1';
result.solveMode=char(mode);
result.state=state(:);
result.fuelFlow_kgps=wf;
result.derivative=final.derivative(:);
result.output=final.output;
result.diagnostics=final.diagnostics;
result.strictResidualPassed=strictResidualPassed;
result.engineeringResidualPassed=engineeringResidualPassed;
result.thermalPassed=thermalPassed;
result.shaftPassed=shaftPassed;
result.remainingCorrectionPassed=remainingPassed;
result.physicalValid=physicalValid;
result.stopReason=char(stopReason);
result.strictConverged=strictConverged || strictResidualPassed;
result.iterationCount=iteration;
result.evaluationCount=evaluationCount;
result.initialState=double(initialState(:));
result.initialFuelFlow_kgps=double(initialFuelFlow);
result.finalMaximumThermalDerivative_Kps=max(abs(final.derivative(3:end)));
result.finalMaximumShaftDerivative_rpmps=max(abs(final.derivative(1:2)));
result.finalCommonWorkResidual=final.diagnostics.maxErr;
result.temperatureRange_K=[min(state(3:end)),max(state(3:end))];
result.remainingCorrection=remainingCorrection;
result.jacobian=lastJacobian;
result.scaledJacobianSingularValue=svd(scaledJacobian,'econ');
result.usedDifferenceStep=lastUsedStep;
result.maximumRealJacobianEigenvalue=local_maximum_real_eigenvalue(lastJacobian);
result.normalizedEnergyResidual=local_optional_field( ...
    final.diagnostics,'visserNormalizedEnergyResidual',NaN);
result.energyResidual_W=local_optional_field( ...
    final.diagnostics,'visserEnergyResidual_W',NaN);
result.history=struct2table(usedHistory);
result.options=options;
end

function options=local_options(user,wf,stateCount)
options=struct();
options.maximumIterations=20;
options.maximumCommonWorkRetries=0;
options.strictThermalDerivativeTolerance_Kps=1e-6;
options.engineeringThermalDerivativeTolerance_Kps=1e-4;
options.strictShaftDerivativeTolerance_rpmps=1e-5;
options.engineeringShaftDerivativeTolerance_rpmps=1e-3;
options.strictCommonWorkResidual=1e-7;
options.engineeringCommonWorkResidual=1e-6;
options.speedDifferenceStep_rpm=0.5;
options.fuelDifferenceStep_kgps=max(1e-6,2e-4*wf);
options.temperatureRelativeDifferenceStep=2e-4;
options.minimumTemperatureDifferenceStep_K=0.05;
options.residualScale=[100;100;ones(stateCount-2,1)];
options.speedBounds_rpm=[5000,70000;5000,70000];
options.fuelBounds_kgps=[1e-5,max(5,5*wf)];
options.temperatureBounds_K=[100,3000];
options.maximumSpeedCorrection_rpm=5000;
options.maximumFuelCorrection_kgps=max(0.2,0.5*wf);
options.maximumTemperatureCorrection_K=250;
options.minimumLineSearchFactor=1/4096;
options.boundProjectionTolerance=1e-10;
options.remainingSpeedCorrectionTolerance_rpm=0.01;
options.remainingFuelCorrectionTolerance_kgps=1e-6;
options.remainingTemperatureCorrectionTolerance_K=0.001;
options.finalJacobianAudit=true;
options.verbose=false;
options.label='Visser29';
options.activeTemperatureStateIndex=(3:stateCount).';
names=fieldnames(user);
for i=1:numel(names)
    if ~isfield(options,names{i})
        error('SHT:ThermalEquilibrium:UnknownOption', ...
            '未知气热平衡配置字段：%s。',names{i});
    end
    options.(names{i})=user.(names{i});
end
positive={'maximumIterations','strictThermalDerivativeTolerance_Kps', ...
    'engineeringThermalDerivativeTolerance_Kps', ...
    'strictShaftDerivativeTolerance_rpmps', ...
    'engineeringShaftDerivativeTolerance_rpmps', ...
    'strictCommonWorkResidual','engineeringCommonWorkResidual', ...
    'speedDifferenceStep_rpm','fuelDifferenceStep_kgps', ...
    'temperatureRelativeDifferenceStep','minimumTemperatureDifferenceStep_K', ...
    'maximumSpeedCorrection_rpm','maximumFuelCorrection_kgps', ...
    'maximumTemperatureCorrection_K','minimumLineSearchFactor', ...
    'remainingSpeedCorrectionTolerance_rpm', ...
    'remainingFuelCorrectionTolerance_kgps', ...
    'remainingTemperatureCorrectionTolerance_K'};
for i=1:numel(positive)
    value=options.(positive{i});
    if ~isnumeric(value)||~isscalar(value)||~isfinite(value)||value<=0
        error('SHT:ThermalEquilibrium:BadPositiveOption', ...
            '%s必须为有限正标量。',positive{i});
    end
end
if options.maximumIterations~=round(options.maximumIterations)
    error('SHT:ThermalEquilibrium:BadIterationCount', ...
        'maximumIterations必须为正整数。');
end
if ~isscalar(options.maximumCommonWorkRetries)||~isfinite(options.maximumCommonWorkRetries)|| ...
        options.maximumCommonWorkRetries<0||options.maximumCommonWorkRetries~=round(options.maximumCommonWorkRetries)
    error('SHT:ThermalEquilibrium:BadRetryCount','共同工作续算次数必须是非负整数。');
end
if numel(options.residualScale)~=stateCount || ...
        any(~isfinite(options.residualScale(:))) || ...
        any(options.residualScale(:)<=0)
    error('SHT:ThermalEquilibrium:BadResidualScale', ...
        'residualScale必须按当前状态维数给定有限正尺度。');
end
if ~isequal(size(options.speedBounds_rpm),[2,2]) || ...
        any(~isfinite(options.speedBounds_rpm(:))) || ...
        any(options.speedBounds_rpm(:,1)>=options.speedBounds_rpm(:,2))
    error('SHT:ThermalEquilibrium:BadSpeedBounds', ...
        'speedBounds_rpm必须为2x2有限递增边界，依次对应Np和Ng。');
end
if numel(options.fuelBounds_kgps)~=2 || ...
        any(~isfinite(options.fuelBounds_kgps(:))) || ...
        options.fuelBounds_kgps(1)>=options.fuelBounds_kgps(2)
    error('SHT:ThermalEquilibrium:BadFuelBounds', ...
        'fuelBounds_kgps必须包含两个有限递增边界。');
end
if numel(options.temperatureBounds_K)~=2 || ...
        any(~isfinite(options.temperatureBounds_K(:))) || ...
        options.temperatureBounds_K(1)>=options.temperatureBounds_K(2)
    error('SHT:ThermalEquilibrium:BadTemperatureBounds', ...
        'temperatureBounds_K必须包含两个有限递增边界。');
end
activeIndex=options.activeTemperatureStateIndex(:);
if isempty(activeIndex) || any(~isfinite(activeIndex)) || ...
        any(activeIndex~=round(activeIndex)) || any(activeIndex<3) || ...
        any(activeIndex>stateCount) || numel(unique(activeIndex))~=numel(activeIndex)
    error('SHT:ThermalEquilibrium:BadActiveTemperatureState', ...
        'activeTemperatureStateIndex必须是当前拓扑温度状态内互不重复的整数下标。');
end
options.activeTemperatureStateIndex=activeIndex;
if ~islogical(options.finalJacobianAudit)||~isscalar(options.finalJacobianAudit)|| ...
        ~islogical(options.verbose)||~isscalar(options.verbose)
    error('SHT:ThermalEquilibrium:BadLogicalOption', ...
        'finalJacobianAudit和verbose必须为逻辑标量。');
end
end

function layout=local_layout(mode,state,wf,options)
switch mode
    case "thermal_only"
        layout.variableType=repmat("temperature",numel(state)-2,1);
        layout.stateIndex=(3:numel(state)).';
        layout.residualIndex=(3:numel(state)).';
        layout.fuelVariableIndex=0;
        layout.fixedStateIndex=[1;2];
    case "trim_fixed_np"
        activeTemperature=options.activeTemperatureStateIndex(:);
        layout.variableType=["speed";"fuel"; ...
            repmat("temperature",numel(activeTemperature),1)];
        layout.stateIndex=[2;0;activeTemperature];
        layout.residualIndex=[1;2;activeTemperature];
        layout.fuelVariableIndex=2;
        layout.fixedStateIndex=1;
    case "steady_predict"
        layout.variableType=["speed";"speed";repmat("temperature",numel(state)-2,1)];
        layout.stateIndex=(1:numel(state)).';
        layout.residualIndex=(1:numel(state)).';
        layout.fuelVariableIndex=0;
        layout.fixedStateIndex=zeros(0,1);
end
n=numel(layout.variableType);
layout.variableScale=ones(n,1);
layout.maximumCorrection=ones(n,1);
layout.lowerBound=-inf(n,1);layout.upperBound=inf(n,1);
for i=1:n
    type=layout.variableType(i);
    if type=="speed"
        stateIndex=layout.stateIndex(i);
        layout.variableScale(i)=100;
        layout.maximumCorrection(i)=options.maximumSpeedCorrection_rpm;
        layout.lowerBound(i)=options.speedBounds_rpm(stateIndex,1);
        layout.upperBound(i)=options.speedBounds_rpm(stateIndex,2);
    elseif type=="fuel"
        layout.variableScale(i)=max(0.01,0.05*wf);
        layout.maximumCorrection(i)=options.maximumFuelCorrection_kgps;
        layout.lowerBound(i)=options.fuelBounds_kgps(1);
        layout.upperBound(i)=options.fuelBounds_kgps(2);
    else
        layout.variableScale(i)=1;
        layout.maximumCorrection(i)=options.maximumTemperatureCorrection_K;
        layout.lowerBound(i)=options.temperatureBounds_K(1);
        layout.upperBound(i)=options.temperatureBounds_K(2);
    end
end
layout.fixedStateValue=state(layout.fixedStateIndex);
layout.fixedFuelFlow_kgps=wf;
end

function [unknown,state,wf]=local_pack_initial(layout,state,wf)
unknown=zeros(numel(layout.variableType),1);
for i=1:numel(unknown)
    if layout.variableType(i)=="fuel"
        unknown(i)=wf;
    else
        unknown(i)=state(layout.stateIndex(i));
    end
end
if any(unknown<layout.lowerBound)||any(unknown>layout.upperBound)
    error('SHT:ThermalEquilibrium:InitialConditionOutsideBounds', ...
        '气热平衡初值超出配置的物理边界。');
end
end

function [evaluation,state,wf]=local_evaluate_unknown( ...
        engine,unknown,state,wf,boundary,layout,options)
for i=1:numel(unknown)
    if layout.variableType(i)=="fuel"
        wf=unknown(i);
    else
        state(layout.stateIndex(i))=unknown(i);
    end
end
% 每次求值都显式恢复非求解状态和固定燃油，避免前一次试算结果渗入
% 下一次有限差分或回溯求值。
if ~isempty(layout.fixedStateIndex)
    state(layout.fixedStateIndex)=layout.fixedStateValue;
end
if layout.fuelVariableIndex==0
    wf=layout.fixedFuelFlow_kgps;
end
% 仅对DLL达到内部迭代上限的情况，以同一物理输入继续求根。不能仅凭
% 残差较小接受失败标志：失败时C可能尚未刷新热导数。默认不启用续算，
% 由需要该策略的调用方显式配置，保持其他任务的历史数值路径不变。
for retry=0:options.maximumCommonWorkRetries
    try
        [derivative,output,diagnostics]=sht_engine_derivative(engine,state,wf,boundary);
    catch exception
        % 封装提前拒绝ret非零的输出；保留本求解器原有的失败分类，
        % 同时在正文和cause中保留DLL原因。其他异常不改写、不吞掉。
        if ~strcmp(exception.identifier,'sht:engine:dllEvaluationFailed')
            rethrow(exception);
        end
        failure=MException('SHT:ThermalEquilibrium:PhysicalEvaluationFailed', ...
            'Thermal equilibrium physical evaluation failed. %s',exception.message);
        failure=addCause(failure,exception);
        throw(failure);
    end
    if diagnostics.ret~=0||diagnostics.convergeTag~=1,break;end
end
diagnostics.commonWorkRetryCount=retry;
valid=numel(derivative)==numel(state) && all(isfinite(derivative)) && ...
    diagnostics.ret==0 && diagnostics.convergeTag==0 && ...
    diagnostics.evaluationValid==1 && isfinite(diagnostics.maxErr) && ...
    diagnostics.maxErr<=max(1e-5,options.engineeringCommonWorkResidual);
evaluation=struct('derivative',double(derivative(:)),'output',output, ...
    'diagnostics',diagnostics,'valid',valid);
if ~valid
    error('SHT:ThermalEquilibrium:PhysicalEvaluationFailed', ...
        ['气热平衡物理求值失败：ret=%g，tag=%g，valid=%g，' ...
         'DLL残差=%.3e。'],diagnostics.ret,diagnostics.convergeTag, ...
        diagnostics.evaluationValid,diagnostics.maxErr);
end
end

function [jacobian,usedStep,count]=local_finite_difference_jacobian( ...
        engine,unknown,state,wf,boundary,layout,baseResidual,options)
n=numel(unknown);jacobian=zeros(numel(baseResidual),n);usedStep=zeros(n,1);count=0;
for j=1:n
    if layout.variableType(j)=="speed"
        requested=options.speedDifferenceStep_rpm;
    elseif layout.variableType(j)=="fuel"
        requested=options.fuelDifferenceStep_kgps;
    else
        requested=max(options.minimumTemperatureDifferenceStep_K, ...
            options.temperatureRelativeDifferenceStep*max(abs(unknown(j)),300));
    end
    direction=1;
    if unknown(j)+requested>layout.upperBound(j),direction=-1;end
    step=direction*min(requested, ...
        max(layout.upperBound(j)-unknown(j),unknown(j)-layout.lowerBound(j)));
    success=false;
    for tryDirection=[direction,-direction]
        if tryDirection>0
            available=layout.upperBound(j)-unknown(j);
        else
            available=unknown(j)-layout.lowerBound(j);
        end
        actual=tryDirection*min(requested,available);
        if abs(actual)<=128*eps(max(1,abs(unknown(j)))),continue;end
        candidate=unknown;candidate(j)=candidate(j)+actual;
        try
            trial=local_evaluate_unknown(engine,candidate,state,wf, ...
                boundary,layout,options);
            count=count+1;
            trialResidual=trial.derivative(layout.residualIndex)./ ...
                options.residualScale(layout.residualIndex);
            if all(isfinite(trialResidual))
                step=actual;success=true;break;
            end
        catch ME
            count=count+1;
            if ~local_recoverable_evaluation_error(ME),rethrow(ME);end
        end
    end
    if ~success
        error('SHT:ThermalEquilibrium:DifferenceEvaluationFailed', ...
            '第%d个气热平衡变量的正反差分均失败。',j);
    end
    jacobian(:,j)=(trialResidual-baseResidual)/step;
    usedStep(j)=step;
end
end

function passed=local_residual_pass(evaluation,layout,options,strict)
if strict
    thermalTol=options.strictThermalDerivativeTolerance_Kps;
    shaftTol=options.strictShaftDerivativeTolerance_rpmps;
    modelTol=options.strictCommonWorkResidual;
else
    thermalTol=options.engineeringThermalDerivativeTolerance_Kps;
    shaftTol=options.engineeringShaftDerivativeTolerance_rpmps;
    modelTol=options.engineeringCommonWorkResidual;
end
required=evaluation.derivative(layout.residualIndex);
tol=repmat(thermalTol,size(required));
for i=1:numel(layout.residualIndex)
    if layout.residualIndex(i)<=2,tol(i)=shaftTol;end
end
passed=evaluation.valid && evaluation.diagnostics.maxErr<=modelTol && ...
    all(abs(required)<=tol);
end

function passed=local_remaining_correction_pass(correction,layout,options)
passed=true;
for i=1:numel(correction)
    if layout.variableType(i)=="speed"
        tolerance=options.remainingSpeedCorrectionTolerance_rpm;
    elseif layout.variableType(i)=="fuel"
        tolerance=options.remainingFuelCorrectionTolerance_kgps;
    else
        tolerance=options.remainingTemperatureCorrectionTolerance_K;
    end
    passed=passed && abs(correction(i))<=tolerance;
end
end

function row=local_empty_history()
row=struct('iteration',NaN,'maximumShaftDerivative_rpmps',NaN, ...
    'maximumThermalDerivative_Kps',NaN,'normalizedResidualNorm2',NaN, ...
    'commonWorkResidual',NaN,'normalizedEnergyResidual',NaN, ...
    'acceptedLineSearchFactor',NaN);
end

function row=local_history_row(iteration,evaluation,normalizedResidual,factor)
row=local_empty_history();row.iteration=iteration;
row.maximumShaftDerivative_rpmps=max(abs(evaluation.derivative(1:2)));
row.maximumThermalDerivative_Kps=max(abs(evaluation.derivative(3:end)));
row.normalizedResidualNorm2=norm(normalizedResidual,2);
row.commonWorkResidual=evaluation.diagnostics.maxErr;
row.normalizedEnergyResidual=local_optional_field( ...
    evaluation.diagnostics,'visserNormalizedEnergyResidual',NaN);
if factor>0,row.acceptedLineSearchFactor=factor;end
end

function value=local_maximum_real_eigenvalue(jacobian)
if isempty(jacobian) || size(jacobian,1)~=size(jacobian,2)
    value=NaN;
else
    value=max(real(eig(jacobian)));
end
end

function value=local_optional_field(valueStruct,name,defaultValue)
if isfield(valueStruct,name),value=valueStruct.(name);else,value=defaultValue;end
end

function tf=local_recoverable_evaluation_error(exception)
tf=startsWith(exception.identifier,'SHT:ThermalEquilibrium:PhysicalEvaluation');
end
