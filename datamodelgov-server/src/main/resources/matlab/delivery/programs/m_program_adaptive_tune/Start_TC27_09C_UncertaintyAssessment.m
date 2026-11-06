function result=Start_TC27_09C_UncertaintyAssessment(user)
%START_TC27_09C_UNCERTAINTYASSESSMENT C推断、冻结后预测和Excel交付完整入口。
% 默认仅稳态：Start_TC27_09C_UncertaintyAssessment
% 当前正式观测只支持steady_points，联合历程尚未验收，不能自动启动。
% 两套测试均用完整稳态模型预测。0.1/0.025秒配置不改变稳态点算子。
% 仅稳态默认直接DLL，thermalReuseEnabled=true复用热平衡参考Jacobian，
% 仍以当前候选真实DLL残差判定平衡；设为false对照原完整求解。
% 按实际模型Excel路径选择默认：瞬态时刻开启，稳态路径关闭。
% cSamplingSeed仅改变C粒子序列，不改变误差传播/D参考/有界积分种子。
% R073质量优先：cSamplerProfile='quality'，512粒子，默认每层6次、
% 末层32次移动。协方差按温度层学习并冻结，仅用于候选，不取代后验。
% legacy_reference保留旧采样核作同目标对照；所有新运行必须用新目录。
% 单次权重ESS不证明均值/区间稳定，需要独立种子对照，不能混合后验。
% 原代理桥接/一次性重加权仅为显式历史选项，本入口不会续跑R014。
% 计时覆盖从已有确定性Excel到区间/图表/Excel完成，不含确定性辨识。
if nargin<1,user=struct();end
user=sht_tc27_uq_c_options(user);timer=tic;
estimate=sht_tc27_runtime_estimate('uq_C',user);
result=Start_TC27_09_UncertaintyAssessment('C',user);
result.prediction=Start_TC27_10_UncertaintyPrediction(result.directory);
result.audit=Start_TC27_10_UncertaintyAudit(result.directory);
result.approximationDiagnostic=Start_TC27_10_ApproximationDiagnostics(result.directory);
result.userRuntime_s=toc(timer);
result.estimatedTime=estimate;
save(fullfile(result.directory,'C_complete.mat'),'result','-v7.3');
fprintf('TC27-C完整入口结束：%.1f秒（%.2f分钟），%s。\n', ...
    result.userRuntime_s,result.userRuntime_s/60,user.observationMode);
fprintf('C质量：%s；不将有限样本或条件近似称为统计校准保证。\n',result.C.quality);
end
