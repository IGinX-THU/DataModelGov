function result=Start_TC27_09D_QuickAssessment(user)
%START_TC27_09D_QUICKASSESSMENT D方法快速初评，从测量合同到区间及Excel。
% observationMode='steady_points'：只用实际完整有效稳态窗口均值。
% 参数维数由所选模型Excel的可变节点决定，含全部燃油偏置节点。
% 当前新模型合同未验收历程似然，不自动恢复历史联合历程研究。
% 瞬态时刻路径默认复用热平衡Jacobian，逐候选校正温度并检查真实残差；
% 不通过则自动完整求解。thermalReuseEnabled=false可显式关闭，稳态路径不启用。
% predictionHistoriesEnabled只决定冻结后的历程预测，不改变似然。
% integrationStep_s默认0.1秒，可设0.025秒；D历程推断和预测采用同一步长。
% 默认最多3次局部更新，另作最终重新线性化，不自动升级长时间全局求解。
if nargin<1,user=struct();end
user=sht_tc27_uq_d_options(user);
timer=tic;estimate=sht_tc27_runtime_estimate('uq_D',user);
result=Start_TC27_09_UncertaintyAssessment('D',user);
c=load(fullfile(result.directory,'contract.mat'),'c');c=c.c;
result.prediction=Start_TC27_10_UncertaintyPrediction(c.directory);
result.audit=Start_TC27_10_UncertaintyAudit(c.directory);
result.approximationDiagnostic=Start_TC27_10_ApproximationDiagnostics(c.directory);
result.userRuntime_s=toc(timer);
result.estimatedTime=estimate;
save(fullfile(c.directory,'D_quick_complete.mat'),'result','-v7.3');
fprintf('TC27-D一次入口完成：%s，%.1f s；积分步长=%.3fs，历程预测=%d。\n', ...
    c.observationMode,result.userRuntime_s,c.options.integrationStep_s,c.options.predictionHistoriesEnabled);
fprintf('结果目录：%s\n',c.report);
disp(result.evaluationStatistics);
end
