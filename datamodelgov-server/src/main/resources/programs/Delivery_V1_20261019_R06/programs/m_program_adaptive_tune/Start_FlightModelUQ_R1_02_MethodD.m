function result=Start_FlightModelUQ_R1_02_MethodD(userOptions,control)
%START_FLIGHTMODELUQ_R1_02_METHODD 三部件R2稳态平均点的方法D独立流程。
% 历史R1文件名保留；默认R027独立节点合同，幅值结果仍可显式选择。
% 默认完成准备、局部评估、独立稳态预测及Excel/图表，不重跑确定性辨识。
% 改数据/模型/源码必须使用新runTag；相同合同的完成结果可复用。
if nargin<1,userOptions=struct();end
if nargin<2,control=[];end
assert(isstruct(userOptions)&&isscalar(userOptions),'配置应为标量结构体。');
p=sht_f3_current_contract('paths');
o=struct('runTag','F3_D_R031_nodes','modelMode',0,'dataMethod','steady_only', ...
    'referenceResultFile',fullfile(p.middle,'identification', ...
    'flight_model_adapt_3p3_transient_instant_steady_only_set1_R027_nodes_latest.mat'));
names=fieldnames(userOptions);
for j=1:numel(names),o.(names{j})=userOptions.(names{j});end
o=sht_f34_contract('defaultOptions',o);
assert(o.modelMode==0&&strcmp(o.dataMethod,'steady_only'), ...
    '本入口只执行三部件稳态平均点D方法，混合历程仅留接口。');
paths=sht_f34_contract('paths',o);timer=tic;
if isfile(paths.preparedFile)
    prepared=sht_f34_contract('loadPrepared',o);
else
    prepared=sht_f34_contract('prepare',o);
end
cleanup=onCleanup(@()sht_f34_contract('close',prepared)); %#ok<NASGU>
if isfile(paths.likelihoodFile)
    s=load(paths.likelihoodFile,'likelihood');likelihood=s.likelihood;
else
    likelihood=sht_f34_likelihood('build',prepared.context,prepared.prior,o,prepared.contract);
    save(paths.likelihoodFile,'likelihood','-v7.3');
end
sht_f34_verify_likelihood_identity(likelihood,prepared);
if ~isempty(control)
    sht_tc24_run_control('boundary',control,'uq_prepared', ...
        struct('contract',prepared.contract,'likelihoodHash',likelihood.contractHash));
end
if isfile(paths.methodDFile)
    s=load(paths.methodDFile,'methodD');methodD=s.methodD;
    assert(sht_f34_checkpoint_compatible(methodD,prepared,likelihood), ...
        'SHT:F34D:StaleResult','已有D结果与当前合同不兼容，请使用新批次，不重签旧结果。');
else
    methodD=sht_f34_method_d(prepared,likelihood,struct(),control);
    save(paths.methodDFile,'methodD','-v7.3');
end
if ~isempty(control)
    sht_tc24_run_control('boundary',control,'uq_D_complete', ...
        struct('methodDFile',paths.methodDFile,'sha256',sht_f33_model_adapt_v2('fileHash',paths.methodDFile)));
end
if ~o.runIndependentPrediction
    % 无测试集是合法场景，不借用旧测试集或把训练拟合冒充独立验证。
    prediction=[];
elseif isfile(paths.predictionFile)
    s=load(paths.predictionFile,'prediction');prediction=s.prediction;
    assert(strcmp(prediction.posteriorPredictionIdentity, ...
        sht_f34_prediction_identity(likelihood,methodD,[])), ...
        'SHT:F34D:StalePrediction','预测身份不兼容，请使用新批次。');
    assert(strcmp(prediction.validationWorkbookSha256, ...
        sht_f33_model_adapt_v2('fileHash',prediction.validationWorkbook)), ...
        'SHT:F34D:ChangedTestData','独立测试Excel已经变化，禁止复用旧预测。');
    lineage=prediction.testContextMetadata.segmentLineage;
    assert(strcmp(lineage.stage32FileSha256, ...
        sht_f33_model_adapt_v2('fileHash',lineage.stage32File)), ...
        'SHT:F34D:ChangedSegments','独立测试片段已经变化，禁止复用旧预测。');
else
    prediction=sht_f34_prediction(prepared,likelihood,methodD,[],o.predictionOptions);
    save(paths.predictionFile,'prediction','-v7.3');
end
completeFile=fullfile(paths.runDir,'method_d_complete.mat');
if isfile(completeFile)
    saved=load(completeFile,'result');
    assert(isequaln(saved.result.methodD,methodD)&&isequaln(saved.result.prediction,prediction), ...
        'SHT:F34D:CompletedChanged','已完成批次的数值载荷改变，请使用新批次。');
    assert(isfile(fullfile(paths.runDir,'3p4_method_D_local_delivery.xlsx')), ...
        'SHT:F34D:DeliveryMissing','已完成批次的正式Excel缺失，请检查恢复材料。');
    result=saved.result;result.thisInvocationWallTime_s=toc(timer);result.reusedCompletedResult=true;
    fprintf('复用D完成结果，用时%.1f秒；原始计时和文件不改写。\n',result.thisInvocationWallTime_s);
    return;
end
reportOptions=o.reportOptions;
artifacts=sht_f34_method_d_artifacts('write',prepared,likelihood,methodD,prediction,reportOptions);
result=struct('method','D','runTag',o.runTag,'referenceFile',o.referenceResultFile, ...
    'directory',paths.runDir,'reportDirectory',paths.reportDir, ...
    'methodD',methodD,'prediction',prediction,'artifacts',artifacts, ...
    'totalWallTime_s',toc(timer),'methodCExecuted',false,'transientIdentificationExecuted',false);
save(fullfile(paths.runDir,'method_d_complete.mat'),'result','-v7.3');
fprintf('方法D独立流程完成，用时%.1f秒；%s。\n',result.totalWallTime_s,methodD.qualityLevel);
disp(methodD.summary);
if ~isempty(prediction),disp(prediction.summary);end
fprintf('区间及结果：%s\n正式Excel：%s\n',paths.reportDir,artifacts.workbook);
end
