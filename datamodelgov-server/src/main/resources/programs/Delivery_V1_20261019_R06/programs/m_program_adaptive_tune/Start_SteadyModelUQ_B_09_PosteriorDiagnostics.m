function result = Start_SteadyModelUQ_B_09_PosteriorDiagnostics(userCfg)
%START_STEADYMODELUQ_B_09_POSTERIORDIAGNOSTICS 输出B后验和分块采样诊断。
if nargin < 1, userCfg = struct(); end
timer = tic;
manifest = sht_steady_model_uq_b_io('resolvewritable',userCfg);
step1 = sht_steady_model_uq_b_io('loadstep',manifest,1);
step5 = sht_steady_model_uq_b_io('loadstep',manifest,5);
step8 = sht_steady_model_uq_b_io('loadstep',manifest,8);
contract = step1.contract;
formal = step8.formal;
weights = formal.weights(:)/sum(formal.weights);
theta = formal.theta;
summaryTable = sht_steady_model_uq_sampler( ...
    'summary',theta,weights,contract);
summaryTable.Properties.VariableNames{ ...
    strcmp(summaryTable.Properties.VariableNames,'deterministic_estimate')} = ...
    'zero_prior_reference';
summaryTable.c_index = contract.parameterTable.c_index;
summaryTable.block_name = contract.parameterTable.block_name;
summaryTable.group_kind = contract.parameterTable.group_kind;
summaryTable.exact_prior_only = ismember( ...
    (1:contract.parameterCount).',formal.priorOnlyParameterIndex);
posteriorMean = theta*weights;
centered = theta-posteriorMean;
normalizer = max(1-sum(weights.^2),eps);
posteriorCovariance = (centered.*sqrt(weights.')) * ...
    (centered.*sqrt(weights.')).'/normalizer;
posteriorCovariance = 0.5*(posteriorCovariance+posteriorCovariance.');
posteriorStd = sqrt(max(diag(posteriorCovariance),0));
posteriorCorrelation = posteriorCovariance ./ ...
    max(posteriorStd*posteriorStd.',eps);
priorWidth = summaryTable.prior_q975-summaryTable.prior_q025;
posteriorWidth = summaryTable.q975-summaryTable.q025;
summaryTable.posterior_to_prior_width_ratio = posteriorWidth./priorWidth;
summaryTable.information_shrinkage_fraction = 1-posteriorWidth./priorWidth;
range = contract.upperBound-contract.lowerBound;
nearLower = theta <= contract.lowerBound+0.02*range;
nearUpper = theta >= contract.upperBound-0.02*range;
summaryTable.lower_boundary_mass = nearLower*weights;
summaryTable.upper_boundary_mass = nearUpper*weights;

blockTable = local_parameter_block_summary(contract,summaryTable);
kernelTable = local_kernel_summary(contract,formal);
correlationTable = local_top_correlation( ...
    posteriorCorrelation,contract.parameterTable,40);
[bestLogLikelihood,bestIndex] = max(formal.logLikelihood);
bestResidual = formal.exact.residual(:,bestIndex);
bestMahalanobisSquared = bestResidual.' * ...
    (step5.likelihood.covariance\bestResidual);
acceptance = struct('formalStepPassed',step8.passed, ...
    'finalBetaReachedOne',formal.finalBeta==1, ...
    'effectiveSampleSize',formal.diagnostic.effectiveSampleSize, ...
    'maximumNormalizedWeight',max(formal.weights), ...
    'allBlockKernelsAttempted',all(formal.blockAttempted>0), ...
    'allSummaryFinite',all(isfinite(summaryTable.posterior_mean)) && ...
        all(isfinite(summaryTable.q025)) && all(isfinite(summaryTable.q975)), ...
    'passed',step8.passed && all(isfinite(summaryTable.posterior_mean)));
result = struct('summaryTable',summaryTable,'blockTable',blockTable, ...
    'topCorrelationTable',correlationTable,'posteriorMean',posteriorMean, ...
    'posteriorCovariance',posteriorCovariance, ...
    'posteriorCorrelation',posteriorCorrelation, ...
    'kernelTable',kernelTable, ...
    'bestSampleIndex',bestIndex,'bestLogLikelihood',bestLogLikelihood, ...
    'bestMahalanobisSquared',bestMahalanobisSquared, ...
    'samplingDiagnostic',formal.diagnostic,'blockAttempted', ...
    formal.blockAttempted,'blockAccepted',formal.blockAccepted, ...
    'blockAcceptance',formal.blockAcceptance,'acceptance',acceptance, ...
    'priorOnlyParameterIndex',formal.priorOnlyParameterIndex, ...
    'priorOnlyRefreshCount',formal.priorOnlyRefreshCount, ...
    'passed',acceptance.passed,'truthRead',false,'testDataRead',false);
runtime = toc(timer);
[manifest,file] = sht_steady_model_uq_b_io( ...
    'savestep',manifest,9,'posterior_diagnostics',result,runtime);
writetable(summaryTable,sht_steady_model_uq_b_io( ...
    'reportfile',manifest,'UQB09_parameter_summary.csv'));
writetable(blockTable,sht_steady_model_uq_b_io( ...
    'reportfile',manifest,'UQB09_block_summary.csv'));
writetable(kernelTable,sht_steady_model_uq_b_io( ...
    'reportfile',manifest,'UQB09_sampling_kernel_summary.csv'));
writetable(correlationTable,sht_steady_model_uq_b_io( ...
    'reportfile',manifest,'UQB09_top_parameter_correlations.csv'));
result.plotAudit(1)=sht_steady_model_uq_common('optionalplot',contract.config, ...
    @()local_plot_parameter_intervals(summaryTable,contract,manifest));
result.plotAudit(2)=sht_steady_model_uq_common('optionalplot',contract.config, ...
    @()local_plot_correlation(posteriorCorrelation,contract,manifest));
result.plotAudit(3)=sht_steady_model_uq_common('optionalplot',contract.config, ...
    @()local_plot_smc(formal,manifest));
plotAudit=result.plotAudit; %#ok<NASGU>
save(sht_steady_model_uq_b_io('runfile',manifest,'step09_plot_audit.mat'),'plotAudit');
fprintf(['[2.4UQ-B.9] 后验诊断：ESS=%.1f，最佳D2=%.3f，' ...
    'kernel acc=[%.1f %.1f %.1f %.1f %.1f]%%，先验保留=%d，pass=%d。\n'], ...
    formal.diagnostic.effectiveSampleSize,bestMahalanobisSquared, ...
    100*formal.blockAcceptance,numel(formal.priorOnlyParameterIndex), ...
    acceptance.passed);
fprintf('[2.4UQ-B.9] 产物：%s\n',file);
result.manifest = manifest;
if isfield(formal,'samplingPrecisionDiagnostic')
    d=formal.samplingPrecisionDiagnostic;
    tbl=table(contract.parameterTable.name,d.finalMeanDriftPriorScale,d.finalStdRelativeChange, ...
        'VariableNames',{'parameter','final_mean_drift_prior_scale','final_std_relative_change'});
    writetable(tbl,sht_steady_model_uq_b_io('reportfile',manifest,'UQB09_finite_budget_precision.csv'));
end
end

function tbl = local_parameter_block_summary(contract,summary)
block = ["aggregate";"local";"bleed"];
parameterCount = zeros(3,1);
meanWidthRatio = zeros(3,1);
medianShrinkagePct = zeros(3,1);
stronglyUpdatedCount = zeros(3,1);
priorOnlyCount = zeros(3,1);
for i = 1:3
    use = contract.parameterTable.block_name==block(i);
    parameterCount(i) = nnz(use);
    meanWidthRatio(i) = mean(summary.posterior_to_prior_width_ratio(use));
    medianShrinkagePct(i) = median(summary.interval_shrinkage_pct(use));
    stronglyUpdatedCount(i) = nnz(summary.interval_shrinkage_pct(use)>=20);
    priorOnlyCount(i) = nnz(summary.exact_prior_only(use));
end
tbl = table(block,parameterCount,meanWidthRatio,medianShrinkagePct, ...
    stronglyUpdatedCount,priorOnlyCount, ...
    'VariableNames',{'block_name','parameter_count', ...
    'mean_posterior_to_prior_width_ratio','median_shrinkage_percent', ...
    'count_shrinkage_ge_20_percent','exact_prior_only_count'});
end

function tbl = local_kernel_summary(contract,formal)
tbl = contract.samplingKernelTable;
tbl.attempted = formal.kernelAttempted(:);
tbl.accepted = formal.kernelAccepted(:);
tbl.acceptance = formal.kernelAcceptance(:);
tbl.normalized_esjd = formal.kernelNormalizedEsjd(:);
end

function tbl = local_top_correlation(R,parameter,maximumCount)
n = size(R,1);
[i,j] = find(triu(true(n),1));
value = R(sub2ind([n,n],i,j));
[~,order] = sort(abs(value),'descend');
order = order(1:min(maximumCount,numel(order)));
tbl = table(parameter.name(i(order)),parameter.name(j(order)), ...
    parameter.block_name(i(order)),parameter.block_name(j(order)), ...
    value(order),abs(value(order)), ...
    'VariableNames',{'parameter_1','parameter_2','block_1','block_2', ...
    'correlation','absolute_correlation'});
end

function local_plot_parameter_intervals(tbl,contract,manifest)
figureHandle = figure('Visible',contract.config.figureVisible, ...
    'Name','Method B posterior intervals','Position',[100,100,1280,850]);
blocks = ["aggregate","local","bleed"];
titles = {'总体调度、燃油与喷口','六部件局部常值','十路物理引气常值'};
for b = 1:3
    subplot(3,1,b);
    use = find(tbl.block_name==blocks(b));
    x = 1:numel(use);
    sigma = contract.priorSigma(use);
    lo = tbl.q025(use)./sigma;
    hi = tbl.q975(use)./sigma;
    mu = tbl.posterior_mean(use)./sigma;
    for i = 1:numel(use)
        plot([x(i),x(i)],[lo(i),hi(i)],'Color',[0.25,0.45,0.75]); hold on;
    end
    plot(x,mu,'k.','MarkerSize',8); yline(0,'--'); grid on;
    ylabel('参数/先验标准差'); title(titles{b});
    xlim([0.5,numel(use)+0.5]);
end
xlabel('块内参数序号');
saveas(figureHandle,sht_steady_model_uq_b_io( ...
    'reportfile',manifest,'UQB09_parameter_intervals_by_block.png'));
close(figureHandle);
end

function local_plot_correlation(R,contract,manifest)
figureHandle = figure('Visible',contract.config.figureVisible, ...
    'Name','Method B posterior correlation','Position',[100,100,900,760]);
imagesc(R,[-1,1]); axis image; colorbar;
aggregateEnd = max(contract.parameterBlockIndex{1});
localEnd = max(contract.parameterBlockIndex{2});
hold on;
xline(aggregateEnd+0.5,'k-','LineWidth',1.2);
xline(localEnd+0.5,'k-','LineWidth',1.2);
yline(aggregateEnd+0.5,'k-','LineWidth',1.2);
yline(localEnd+0.5,'k-','LineWidth',1.2);
title(sprintf('方法B %d维后验相关矩阵',contract.parameterCount));
xlabel('参数序号'); ylabel('参数序号');
saveas(figureHandle,sht_steady_model_uq_b_io( ...
    'reportfile',manifest,'UQB09_posterior_correlation.png'));
close(figureHandle);
end

function local_plot_smc(formal,manifest)
figureHandle = figure('Visible','off','Name','Method B SMC diagnostic', ...
    'Position',[100,100,1100,700]);
beta = [formal.stage.beta];
ess = [formal.stage.ess_before_resample];
subplot(2,1,1); yyaxis left; plot(beta,'o-'); ylabel('\beta');
yyaxis right; plot(ess,'s-'); ylabel('ESS'); grid on;
xlabel('SMC层'); title('温度推进与重采样前ESS');
subplot(2,1,2); acceptance = vertcat(formal.stage.kernel_acceptance);
plot(100*acceptance,'o-'); grid on; ylim([0,100]);
xlabel('SMC层'); ylabel('接受率/%');
legend({'压气机+燃烧室','燃气涡轮','涵道+动力涡轮+喷管', ...
    '燃油偏置','跨部件全局'},'Location','best');
title('五类精确移动核接受率');
saveas(figureHandle,sht_steady_model_uq_b_io( ...
    'reportfile',manifest,'UQB09_smc_diagnostics.png'));
close(figureHandle);
end
