function result=Start_TC27_UQ_CD(options)
%START_TC27_UQ_CD 一次完成当前正式Excel的C/D推断、独立预测及Excel交付。
% 第一次无本合同缓存为完整冷运行；同合同再次运行可复用缓存。
% 不含确定性辨识、瞬态参数辨识和B方法。默认仅稳态、0.1s积分，
% 当前仅支持steady_points，不自动恢复历史联合历程研究。
if nargin<1,options=struct();end
timer=tic;o=sht_tc27_uq_c_options(options);
estimate=sht_tc27_runtime_estimate('uq_CD',o);
result=Start_TC27_09_UncertaintyAssessment('CD',options);
result.prediction=Start_TC27_10_UncertaintyPrediction(result.directory);
result.audit=Start_TC27_10_UncertaintyAudit(result.directory);
result.totalWallTime_s=toc(timer);
result.estimatedTime=estimate;
result.summaryFile=Start_TC27_10_ResultSummary(result);
save(fullfile(result.directory,'complete_run.mat'),'result','-v7.3');
fprintf('TC27 C/D UQ入口至最终预测/Excel完成：%.1f秒（%.2f小时）。\n', ...
    result.totalWallTime_s,result.totalWallTime_s/3600);
end
