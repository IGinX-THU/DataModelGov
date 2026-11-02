function result = Start_SteadyModelUQ_C_02_NuisanceMarginalization(userCfg)
%START_STEADYMODELUQ_C_02_NUISANCEMARGINALIZATION 按实际字典作干扰参数矩边缘化。
%
% 在零中心和2.4确定性辨识结果两个显式参数锚点上，对方法B
% 附加参数按当前字典做中心差分。把其截断正态先验的实际均值和方差
% 传播到观测空间，再与独立测量协方差组合。
% 这是矩线性边缘化近似，不是全部联合参数的非线性积分。
if nargin < 1, userCfg = struct(); end
timer = tic;
manifest = sht_steady_model_uq_c_io('resolvewritable', userCfg);
step1 = sht_steady_model_uq_c_io('loadstep', manifest, 1);
contract = step1.contract;

[measurement,measurementSource] = local_measurement_contract(contract);
baseFactor = measurement.selected;
nuisanceTable = contract.nuisanceParameterTable;
nuisanceTable.prior_sigma=contract.auxiliaryContract.priorSigma(contract.nuisanceParameterIndex);
if isfield(contract.config,'nuisancePriorScale')
    nuisanceTable.prior_sigma=nuisanceTable.prior_sigma*contract.config.nuisancePriorScale;
end
[nuisanceMean,nuisanceVariance] = sht_steady_model_uq_c_common( ...
    'truncatedmoments',zeros(height(nuisanceTable),1), ...
    nuisanceTable.prior_sigma,nuisanceTable.lower_bound, ...
    nuisanceTable.upper_bound);
if contract.config.modelMode~=0 && max(abs(nuisanceMean)) > 1e-12
    error('SHT:SteadyUQC:NonzeroNuisanceMean', ...
        '当前对称干扰参数先验的实际均值不为零。');
end

anchor = [zeros(contract.parameterCount,1),contract.thetaHat(:)];
anchorName = ["zero_prior_center";"deterministic_estimate"];
jacobian = cell(2,1);
anchorResidual = cell(2,1);
nonlinearityRatio = zeros(height(nuisanceTable),2);
differenceStep = zeros(height(nuisanceTable),2);
retryCount = zeros(height(nuisanceTable),2);
meanShiftAtAnchor=zeros(contract.observationDimension,2);
dllEvaluationCount = 0;
dllRuntime_s = 0;
for a = 1:2
    [jacobian{a},anchorResidual{a},nonlinearityRatio(:,a), ...
        differenceStep(:,a),retryCount(:,a),count,runtime] = ...
        local_nuisance_jacobian(contract,anchor(:,a),baseFactor,nuisanceMean);
    dllEvaluationCount = dllEvaluationCount+count;
    dllRuntime_s = dllRuntime_s+runtime;
    if any(nuisanceMean~=0)
        zeroNuisance=sht_steady_model_uq_c_common('evaluatenuisance', ...
            contract,anchor(:,a),zeros(height(nuisanceTable),1), ...
            contract.trainingData,struct('useCache',true));
        assert(zeroNuisance.valid,'TC24:UQ:NuisanceOrigin','零干扰基准回放失败。');
        meanShiftAtAnchor(:,a)=anchorResidual{a}-zeroNuisance.residual;
        dllEvaluationCount=dllEvaluationCount+zeroNuisance.dllEvaluationCount;
        dllRuntime_s=dllRuntime_s+zeroNuisance.dllRuntime_s;
    end
end

sigmaNuisance = diag(sqrt(nuisanceVariance));
covarianceAtAnchor = cell(2,1);
for a = 1:2
    covarianceAtAnchor{a} = jacobian{a}*diag(nuisanceVariance)*jacobian{a}.';
    covarianceAtAnchor{a} = 0.5*(covarianceAtAnchor{a}+ ...
        covarianceAtAnchor{a}.');
end
nuisanceCovariance = 0.5*(covarianceAtAnchor{1}+covarianceAtAnchor{2});
nuisanceCovariance = 0.5*(nuisanceCovariance+nuisanceCovariance.');
totalCovariance = baseFactor.covariance+nuisanceCovariance;
totalFactor = sht_steady_model_uq_c_common( ...
    'factorcovariance',totalCovariance, ...
    'method_c_measurement_plus_marginalized_nuisance');
measurementC = measurement;
measurementC.selectedName = totalFactor.name;
measurementC.selected = totalFactor;
likelihood = sht_steady_model_uq_likelihood('build',measurementC);
% 三部件出口焓位置先验受上界约束，边缘化必须同时传播均值和方差。
likelihood.additiveResidualShift=mean(meanShiftAtAnchor,2);

% 新参考位置只改变近似精度，不把同批数据的MAP变成新的先验。
anchorCheck=struct('enabled',false,'selected','two_anchor');
if isfield(contract.config,'nuisanceAnchorMode') && strcmp(contract.config.nuisanceAnchorMode,'map_checked')
    pilot=sht_tc24_uq_method_d(contract,step1.prior,likelihood, ...
        struct('maxIterations',10,'localSampleCount',128,'nonlinearCorrection',false));
    [newG,newResidual,~,~,~,count,runtime]=local_nuisance_jacobian( ...
        contract,pilot.map,baseFactor,nuisanceMean);
    origin=sht_steady_model_uq_c_common('evaluate',contract,pilot.map, ...
        contract.trainingData,struct('useCache',true));
    newShift=newResidual-origin.residual;
    anchorCheck=sht_tc24_uq_anchor_check(contract,baseFactor,nuisanceMean, ...
        nuisanceVariance,jacobian,mean(meanShiftAtAnchor,2),newG,newShift,pilot);
    dllEvaluationCount=dllEvaluationCount+count+origin.dllEvaluationCount+ ...
        pilot.dllEvaluationCount+anchorCheck.dllEvaluationCount;
    dllRuntime_s=dllRuntime_s+runtime;
    if anchorCheck.useNewAnchor
        jacobian={newG,newG};anchor=[pilot.map,pilot.map];
        anchorName=["checked_local_map";"checked_local_map"];
        anchorResidual={newResidual,newResidual};meanShiftAtAnchor=[newShift,newShift];
        nuisanceCovariance=newG*diag(nuisanceVariance)*newG.';
        covarianceAtAnchor={nuisanceCovariance,nuisanceCovariance};
        totalFactor=sht_steady_model_uq_c_common('factorcovariance', ...
            baseFactor.covariance+nuisanceCovariance,'checked_map_moment_marginalization');
        measurementC.selected=totalFactor;measurementC.selectedName=totalFactor.name;
        likelihood=sht_steady_model_uq_likelihood('build',measurementC);
        likelihood.additiveResidualShift=newShift;
    end
    writetable(anchorCheck.table,fullfile(manifest.reportDir,'TC24_C_anchor_holdout.csv'));
end

scaledFirst = baseFactor.cholLower \ (jacobian{1}*sigmaNuisance);
scaledSecond = baseFactor.cholLower \ (jacobian{2}*sigmaNuisance);
anchorJacobianDifference = norm(scaledSecond-scaledFirst,'fro') / ...
    max(0.5*(norm(scaledFirst,'fro')+norm(scaledSecond,'fro')),eps);
baseStd = sqrt(diag(baseFactor.covariance));
nuisanceStd = sqrt(max(diag(nuisanceCovariance),0));
totalStd = sqrt(diag(totalFactor.covariance));
[~,label,unit] = sht_steady_model_uq_common( ...
    'observation',contract.baseContract,contract.trainingData,contract.route);

nuisanceAudit = table(nuisanceTable.name,nuisanceTable.c_index, ...
    nuisanceTable.block_name,nuisanceTable.lower_bound, ...
    nuisanceTable.upper_bound,nuisanceTable.prior_sigma,nuisanceMean, ...
    sqrt(nuisanceVariance),differenceStep(:,1),differenceStep(:,2), ...
    retryCount(:,1),retryCount(:,2),nonlinearityRatio(:,1), ...
    nonlinearityRatio(:,2),max(nonlinearityRatio,[],2), ...
    'VariableNames',{'name','c_index','source_block','lower_bound', ...
    'upper_bound','nominal_prior_sigma','truncated_prior_mean', ...
    'truncated_prior_sigma','difference_step_zero', ...
    'difference_step_deterministic','retry_count_zero', ...
    'retry_count_deterministic','nonlinearity_ratio_zero', ...
    'nonlinearity_ratio_deterministic','maximum_nonlinearity_ratio'});
covarianceAudit = table(string(label(:)),string(unit(:)),baseStd, ...
    nuisanceStd,totalStd,nuisanceStd./max(baseStd,eps), ...
    'VariableNames',{'observation','unit','measurement_std', ...
    'marginalized_nuisance_std','method_c_total_std', ...
    'nuisance_to_measurement_std_ratio'});

result = struct('measurementSource',measurementSource, ...
    'anchorCheck',anchorCheck, ...
    'nuisanceMeanShiftAtAnchor',meanShiftAtAnchor, ...
    'baseMeasurement',measurement,'nuisanceMean',nuisanceMean, ...
    'nuisanceVariance',nuisanceVariance,'anchor',anchor, ...
    'anchorName',anchorName,'anchorResidual',{anchorResidual}, ...
    'nuisanceJacobian',{jacobian}, ...
    'nuisanceCovarianceAtAnchor',{covarianceAtAnchor}, ...
    'nuisanceCovariance',nuisanceCovariance, ...
    'measurementC',measurementC,'likelihood',likelihood, ...
    'nuisanceAuditTable',nuisanceAudit, ...
    'covarianceAuditTable',covarianceAudit, ...
    'anchorJacobianRelativeDifference',anchorJacobianDifference, ...
    'maximumNuisanceNonlinearityRatio',max(nonlinearityRatio(:)), ...
    'dllEvaluationCount',dllEvaluationCount,'dllRuntime_s',dllRuntime_s, ...
    'approximationClass','two_anchor_moment_linearized_gaussian', ...
    'truthRead',false,'testDataRead',false,'passed', ...
    all(isfinite(totalFactor.cholLower(:))));
runtime = toc(timer);
[manifest,file] = sht_steady_model_uq_c_io( ...
    'savestep',manifest,2,'nuisance_marginalization',result,runtime);
writetable(nuisanceAudit,sht_steady_model_uq_c_io( ...
    'reportfile',manifest,'UQC02_nuisance_marginalization_audit.csv'));
writetable(covarianceAudit,sht_steady_model_uq_c_io( ...
    'reportfile',manifest,'UQC02_covariance_standard_deviation.csv'));
result.plotAudit=sht_steady_model_uq_common('optionalplot',contract.config, ...
    @()local_plot_covariance_std(covarianceAudit,contract,manifest));
plotAudit=result.plotAudit; %#ok<NASGU>
save(sht_steady_model_uq_c_io('runfile',manifest,'step02_plot_audit.mat'),'plotAudit');
fprintf(['[2.4UQ-C.2] %d维干扰参数边缘化完成：DLL新计算=%d，' ...
    '两锚点Jacobian相对差=%.3f，最大非线性指标=%.3f。\n'], ...
    height(nuisanceTable),dllEvaluationCount,anchorJacobianDifference,max(nonlinearityRatio(:)));
fprintf('[2.4UQ-C.2] 测量协方差来源：%s\n',measurementSource);
fprintf('[2.4UQ-C.2] 产物：%s\n',file);
result.manifest = manifest;
end

function [measurement,source] = local_measurement_contract(contract)
source = 'recomputed_from_current_contract';
if isfield(contract,'modelMode') && contract.modelMode==0
    inputCovariance=sht_steady_model_uq_common('inputcovariance',contract.baseContract);
    measurement=sht_steady_model_uq_common('measurementcovariance',contract.baseContract,inputCovariance);
    return;
end
try
    methodAManifest = sht_steady_model_uq_io('resolve', ...
        struct('runId',contract.config.methodAReferenceRunId));
    methodAStep1 = sht_steady_model_uq_io('loadstep',methodAManifest,1);
    methodAStep4 = sht_steady_model_uq_io('loadstep',methodAManifest,4);
    if strcmp(methodAStep1.contract.contractHash, ...
            contract.baseContractHash)
        measurement = methodAStep4.measurement;
        source = ['reused_method_a_run_' contract.config.methodAReferenceRunId];
        return;
    end
catch exception
    warning('SHT:SteadyUQC:MeasurementReuseFailed', ...
        '方法A测量协方差未能复用，将按当前合同重算：%s', ...
        exception.message);
end
inputCovariance = sht_steady_model_uq_common( ...
    'inputcovariance',contract.baseContract);
measurement = sht_steady_model_uq_common( ...
    'measurementcovariance',contract.baseContract,inputCovariance);
end

function [jacobian,centerResidual,nonlinearityRatio,step,retryCount, ...
        dllCount,dllRuntime] = local_nuisance_jacobian( ...
        contract,baseTheta,baseFactor,center)
nuisance = contract.nuisanceParameterTable;
n = height(nuisance);
step = max(nuisance.difference_step, ...
    contract.config.nuisanceDifferenceSigmaFraction*nuisance.prior_sigma);
margin = min(center-nuisance.lower_bound,nuisance.upper_bound-center);
step = min(step,0.20*margin);
retryCount = zeros(n,1);
dllCount = 0;
dllRuntime = 0;
for retry = 0:7
    candidate = repmat(center,1,1+2*n);
    for j = 1:n
        candidate(j,2*j) = center(j)+step(j);
        candidate(j,2*j+1) = center(j)-step(j);
    end
    exact = sht_steady_model_uq_c_common('evaluatenuisance', ...
        contract,baseTheta,candidate,contract.trainingData, ...
        struct('useCache',contract.config.useCache));
    dllCount = dllCount+exact.dllEvaluationCount;
    dllRuntime = dllRuntime+exact.dllRuntime_s;
    failed = false(n,1);
    for j = 1:n
        failed(j) = ~(exact.valid(2*j) && exact.valid(2*j+1));
    end
    if exact.valid(1) && ~any(failed), break; end
    if ~exact.valid(1)
        error('SHT:SteadyUQC:NuisanceAnchorInvalid', ...
            '干扰参数为零时锚点回放无效。');
    end
    step(failed) = 0.5*step(failed);
    retryCount(failed) = retryCount(failed)+1;
end
if any(failed)
    error('SHT:SteadyUQC:NuisanceDifferenceInvalid', ...
        '缩小差分步长后仍有%d个干扰参数无法中心差分。',nnz(failed));
end
centerResidual = exact.residual(:,1);
jacobian = zeros(contract.observationDimension,n);
nonlinearityRatio = zeros(n,1);
for j = 1:n
    plus = exact.residual(:,2*j);
    minus = exact.residual(:,2*j+1);
    jacobian(:,j) = (plus-minus)/(2*step(j));
    secondDifference = baseFactor.cholLower \ ...
        (plus-2*centerResidual+minus);
    firstSpan = baseFactor.cholLower \ (plus-minus);
    nonlinearityRatio(j) = norm(secondDifference) / max(norm(firstSpan),eps);
end
end

function local_plot_covariance_std(tbl,contract,manifest)
figureHandle = figure('Visible',contract.config.figureVisible, ...
    'Name','Method C covariance decomposition','Position',[100,100,1200,650]);
semilogy(tbl.measurement_std,'o-','LineWidth',1.0); hold on;
semilogy(tbl.marginalized_nuisance_std,'s-','LineWidth',1.0);
semilogy(tbl.method_c_total_std,'^-','LineWidth',1.0);
grid on; xlabel('观测分量序号'); ylabel('标准差（各自物理单位）');
legend({'测量及已定义误差',sprintf('%d维附加参数贡献',contract.marginalizedNuisanceDimension),'C方法总似然'}, ...
    'Location','best');
title('方法C观测标准差构成');
saveas(figureHandle,sht_steady_model_uq_c_io( ...
    'reportfile',manifest,'UQC02_covariance_std_decomposition.png'));
close(figureHandle);
end
