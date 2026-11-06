function result=Start_FlightModelUQ_R1_03_MethodC(userOptions,control)
%START_FLIGHTMODELUQ_R1_03_METHODC 三部件R020默认R2、纯稳态点的C完整流程。
% D只构造提议；C目标仍是台架后验经工程Q传播后的先验乘飞参似然。
% 主样本与独立复算分别保存，不合并；0.1/0.025秒历程辨识本入口不执行。
if nargin<1,userOptions=struct();end
if nargin<2,control=[];end
p=sht_f3_current_contract('paths');
o=struct('runTag','F3_C_R031_bounded_nodes_final','modelMode',0,'dataMethod','steady_only', ...
    'referenceResultFile',fullfile(p.middle,'identification', ...
    'flight_model_adapt_3p3_transient_instant_steady_only_set1_R027_nodes_latest.mat'), ...
    'methodCParticleCount',512,'methodCRepeatParticleCount',512, ...
    'methodCMoveSweeps',2,'methodCFinalMoveSweeps',4, ...
    'methodCIndependentMoveFraction',0.2,'predictionRepresentativeCount',96, ...
    'runIndependentRepeat',true,'runPrediction',true,'runExport',true);
names=fieldnames(userOptions);for j=1:numel(names),o.(names{j})=userOptions.(names{j});end
o=sht_f34_contract('defaultOptions',o);paths=sht_f34_contract('paths',o);timer=tic;
assert(o.modelMode==0&&strcmp(o.dataMethod,'steady_only'),'只实现三部件纯稳态数据C。');
if isfile(paths.preparedFile),prepared=sht_f34_contract('loadPrepared',o);
else,prepared=sht_f34_contract('prepare',o);end
cleanup=onCleanup(@()sht_f34_contract('close',prepared)); %#ok<NASGU>
if isfile(paths.likelihoodFile),s=load(paths.likelihoodFile,'likelihood');L=s.likelihood;
else
    L=sht_f34_likelihood('build',prepared.context,prepared.prior,o,prepared.contract);
    likelihood=L;save(paths.likelihoodFile,'likelihood','-v7.3');
end
sht_f34_verify_likelihood_identity(L,prepared);
if ~isempty(control)
    sht_tc24_run_control('boundary',control,'uq_prepared', ...
        struct('contract',prepared.contract,'likelihoodHash',L.contractHash));
end
if isfile(paths.methodDFile)
    s=load(paths.methodDFile,'methodD');D=s.methodD;
    assert(sht_f34_checkpoint_compatible(D,prepared,L),'D提议身份改变，请使用新批次。');
else
    D=sht_f34_method_d(prepared,L,struct(),control);methodD=D;save(paths.methodDFile,'methodD','-v7.3');
end
if ~isempty(control)
    sht_tc24_run_control('boundary',control,'uq_D_complete', ...
        struct('methodDFile',paths.methodDFile,'sha256',sht_f33_model_adapt_v2('fileHash',paths.methodDFile)));
end
C=load_or_run(paths.methodCFile,o.methodCParticleCount,o.methodCIndependentSeed);
if o.runIndependentRepeat
    repeat=load_or_run(paths.methodCRepeatFile,o.methodCRepeatParticleCount,o.methodCSecondSeed);
    C.independentRepeatStability=sht_f34_method_c_stability(C,repeat,prepared.prior.parameterTable);
end
C.curveSummary=sht_f34_curve_summary(prepared,C);
C.qSensitivity=sht_f34_q_sensitivity(prepared,C);
prediction=[];delivery=[];report=[];
if o.runPrediction
    if isfile(paths.predictionFile)
        s=load(paths.predictionFile,'prediction');prediction=s.prediction;
        assert(strcmp(prediction.posteriorPredictionIdentity,sht_f34_prediction_identity(L,D,C)), ...
            '预测样本/权重/条件形状或源码改变，请使用新批次。');
        assert(strcmp(prediction.validationWorkbookSha256,sht_f33_model_adapt_v2( ...
            'fileHash',prediction.validationWorkbook)),'独立测试Excel已经变化。');
        line=prediction.testContextMetadata.segmentLineage;
        assert(strcmp(line.stage32FileSha256,sht_f33_model_adapt_v2('fileHash',line.stage32File)), ...
            '独立测试片段已经变化。');
    else
        prediction=sht_f34_prediction(prepared,L,D,C,o.predictionOptions);
        save(paths.predictionFile,'prediction','-v7.3');
    end
end
completeFile=fullfile(paths.runDir,'method_c_complete.mat');
if isfile(completeFile)
    saved=load(completeFile,'result');
    comparison=C;frozen=saved.result.methodC;
    % 稳定性诊断的生成时间不是数学身份，其余全部统计/样本字段仍严格比较。
    if isfield(comparison,'independentRepeatStability')&&isfield(frozen,'independentRepeatStability')
        comparison.independentRepeatStability=rmfield(comparison.independentRepeatStability,'createdAt');
        frozen.independentRepeatStability=rmfield(frozen.independentRepeatStability,'createdAt');
    end
    assert(isequaln(frozen,comparison)&&isequaln(saved.result.methodD,D)&& ...
        isequaln(saved.result.prediction,prediction),'SHT:F34C:CompletedChanged', ...
        '已完成批次的数值载荷改变，请使用新批次。');
    assert(~o.runExport||isfile(paths.deliveryFile),'SHT:F34C:DeliveryMissing', ...
        '已完成批次的正式Excel缺失；请检查恢复材料或另行导出。');
    result=saved.result;result.thisInvocationWallTime_s=toc(timer);result.reusedCompletedResult=true;
    fprintf('复用C完成结果，用时%.1f秒；原始计时和文件不改写。\n',result.thisInvocationWallTime_s);
    return;
end
methodC=C;save(paths.methodCFile,'methodC','-v7.3');
if o.runExport
    assert(o.runIndependentRepeat,'正式C参数交付需要独立复算；独立测试可不提供。');
    delivery=sht_f34_io('export',prepared,L,D,C,prediction);
    sht_f34_io('verify',delivery.workbookFile);
    if isfield(prepared.prior,'nodePrior')
        report=sht_f34_node_c('report',prepared,L,D,C,prediction,delivery,o.reportOptions);
    else
        report=sht_f34_reporting(prepared,L,D,C,prediction,delivery);
    end
    analysis=sht_f34_method_c_artifacts(prepared,L,D,C,prediction,delivery,o.reportOptions); %#ok<NASGU>
end
result=struct('runTag',o.runTag,'methodC',C,'methodD',D,'prediction',prediction, ...
    'delivery',delivery,'report',report,'totalWallTime_s',toc(timer));
save(fullfile(paths.runDir,'method_c_complete.mat'),'result','-v7.3');
fprintf('C完整流程用时%.1f秒。\n',result.totalWallTime_s);disp(C.summary);
if ~isempty(prediction),disp(prediction.summary);end
    function c=load_or_run(file,count,seed)
        if isfile(file)
            s=load(file,'methodC');c=s.methodC;
            assert(sht_f34_checkpoint_compatible(c,prepared,L,D)&& ...
                c.particleCount==count&&c.seed==seed&&c.finalBeta==1, ...
                '完成结果的身份/样本预算不一致，请使用新批次。');
        else
            c=sht_f34_method_c(prepared,L,D,struct('particleCount',count,'seed',seed),control);
            methodC=c;save(file,'methodC','-v7.3');
        end
        if ~isempty(control)
            sht_tc24_run_control('boundary',control,sprintf('uq_C_done_N%d_seed%d',count,seed), ...
                struct('file',file,'sha256',sht_f33_model_adapt_v2('fileHash',file)));
        end
    end
end
