function d=sht_steady_model_uq_b_precision_diagnostic(formal,prior)
% 权重、谱系和末级移动是三个不同诊断，不能由权重ESS推导统计收敛。
% 本函数不读真值，不修改粒子/权重，也不因诊断报警取消已计算结果。
w=formal.weights(:)/sum(formal.weights);
[~,~,label]=unique(formal.ancestorId(:));mass=accumarray(label,w);
d=struct('weightEss',1/sum(w.^2),'uniqueAncestorCount',numel(mass), ...
    'ancestorMassEss',1/sum(mass.^2),'maximumAncestorMass',max(mass), ...
    'acceptedMovesPerParticle',formal.kernelAccepted/numel(w), ...
    'statisticalCalibrationEstablished',false, ...
    'interpretation','finite_budget_single_population_diagnostics_not_calibration');
d.finalMeanDriftPriorScale=nan(numel(prior.sigma),1);
d.finalStdRelativeChange=nan(numel(prior.sigma),1);
if isfield(formal,'finalMoveHistory') && numel(formal.finalMoveHistory)>4
    h=formal.finalMoveHistory;k=max(1,numel(h)-max(2,floor((numel(h)-1)/4)));
    d.finalMeanDriftPriorScale=(h(end).mean-h(k).mean)./prior.sigma(:);
    d.finalStdRelativeChange=(h(end).std-h(k).std)./max(h(k).std,eps);
end
d.maximumMeanDriftPriorScale=max(abs(d.finalMeanDriftPriorScale));
d.medianStdRelativeChange=median(abs(d.finalStdRelativeChange));
d.precisionWarning=d.ancestorMassEss<.1*numel(w) || ...
    any(d.acceptedMovesPerParticle(1:4)<1) || ...
    d.maximumMeanDriftPriorScale>.1 || d.medianStdRelativeChange>.1;
end
