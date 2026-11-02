function result=Start_TC27_09_UncertaintyAssessment(method,user,runControl)
%START_TC27_09_UNCERTAINTYASSESSMENT 三部件稳态系数C/D评估，默认依次D、C。
% C/CD默认仅稳态、0.1秒；完整图表及Excel使用09C入口。
% 从既有确定性Excel到UQ计算结束计时；不重跑确定性辨识或TC24任务。
% B不执行。稳态C可选择代理桥接、直接DLL或原代理校正；D为局部近似。
if nargin<1,method='CD';end
if nargin<2,user=struct();end
if nargin<3,runControl=[];end
assert(ismember(upper(method),{'C','D','CD'}),'仅实现C/D，不自动启动B。');
if strcmpi(method,'D')
    % 两个D入口遵循同一快速默认；C与CD使用独立的显式默认配置。
    user=sht_tc27_uq_d_options(user);
else
    user=sht_tc27_uq_c_options(user);
end
timer=tic;c=sht_tc27_uq_contract(user);
fprintf('TC27-%s推断配置：%s，历程积分步长=%.3fs。\n', ...
    upper(method),c.observationMode,c.options.integrationStep_s);
save(fullfile(c.directory,'contract.mat'),'c','-v7.3');
writetable(c.parameterTable,fullfile(c.report,'parameter_dictionary.csv'));
writetable(c.nuisance,fullfile(c.report,'marginalized_parameter_dictionary.csv'));
[evaluate,closeEngine,statistics]=sht_tc27_uq_evaluator(c);cleanup=onCleanup(closeEngine);
covariance=sht_tc27_uq_covariance(c,evaluate);
Test_TC27_UQ_CovarianceBlocks(c,covariance);
m=numel(c.observed);likelihood=struct('dimension',m,'cholLower',speye(m), ...
    'logNormalizingConstant',-.5*(covariance.logDet+m*log(2*pi)));
white=@whiteEvaluate;
% D提供局部近似，也给C构造数值提议；C的独立先验没有改变。
dFile=fullfile(c.directory,'method_D.mat');
if isfile(dFile),saved=load(dFile,'D');D=saved.D;
else
    D=sht_tc24_uq_method_d(c,c.prior,likelihood,struct('evaluateFunction',white, ...
        'maxIterations',c.options.dMaxIterations,'differenceMode','forward', ...
        'localSampleCount',c.options.localSampleCount,'randomSeed',c.options.randomSeed, ...
        'checkpointFile',fullfile(c.directory,'D_checkpoint.mat'), ...
        'runControl',runControl));
    D.method='D';D.contractHash=c.contractHash;D.statisticalCalibrationConfirmed=false;
    save(dFile,'D','-v7.3');
end
D.summary=sht_tc27_uq_empirical_summary(D.formal.theta,D.formal.weights,D.summary);
save(dFile,'D','-v7.3');
if ~isempty(runControl)
    sht_tc24_run_control('boundary',runControl,'DComplete', ...
        struct('contractHash',c.contractHash,'methodFile',dFile, ...
        'progress',struct('stage','D_completed')));
end
result=struct('contractHash',c.contractHash,'directory',c.directory,'method',upper(method), ...
    'D',D,'covarianceRuntime_s',covariance.runtime_s,'inputNoiseCovarianceAudit', ...
    covariance.inputNoiseHalfVsFullRelative,'deterministicInput',c.formalInputFile);
if contains(upper(method),'C')
    cFile=fullfile(c.directory,'method_C.mat');
    if isfile(cFile),saved=load(cFile,'C');C=saved.C;
    else,C=sht_tc27_uq_method_c(c,covariance,D,evaluate,runControl);save(cFile,'C','-v7.3');end
    C.summary=sht_tc27_uq_empirical_summary(C.theta,C.weights,C.summary);
    save(cFile,'C','-v7.3');
    result.C=C;
end
result.inferenceWallTime_s=toc(timer);result.completedAt=datestr(now,30);
result.fitDiagnostic.DMahalanobisPerObservation=sum(D.finalExact.residual.^2)/m;
if isfield(result,'C')
    cw=sht_tc27_uq_whiten(covariance,C.exactResidual);
    result.fitDiagnostic.CMahalanobisPerObservation=sum(sum(cw.^2,1).*C.weights)/m;
end
result.fitDiagnostic.isCalibrationTest=false;
result.evaluationStatistics=statistics();
save(fullfile(c.directory,'assessment.mat'),'result','-v7.3');
fprintf('TC27-UQ本次入口推断结束，用时%.1f秒；预测与Excel交付由10入口完成。\n',result.inferenceWallTime_s);
fprintf('D: %s；主参数%d维。\n',D.quality,c.parameterCount);
if isfield(result,'C'),fprintf('C: %s，粒子权重ESS=%.1f/%d。\n',C.quality,C.effectiveSampleSize,size(C.theta,2));end

    function out=whiteEvaluate(theta)
        out=evaluate(theta);out.residual=sht_tc27_uq_whiten(covariance,out.residual);
    end
end
