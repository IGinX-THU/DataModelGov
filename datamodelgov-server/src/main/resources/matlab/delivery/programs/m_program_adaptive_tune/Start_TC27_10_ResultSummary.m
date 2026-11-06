function file=Start_TC27_10_ResultSummary(result)
%START_TC27_10_RESULTSUMMARY 由冻结结果自动生成可回收MD，不重新辨识。
% 真值仅来自10阶段已完成的隔离验证表；报告不得回流参与采样或选参。
if nargin<1
    c=sht_tc27_uq_contract(sht_tc27_uq_c_options());
    a=load(fullfile(c.directory,'complete_run.mat'),'result');result=a.result;
end
a=load(fullfile(result.directory,'contract.mat'),'c');c=a.c;p=sht_tc27_paths(c.options);
if c.options.plot,Start_TC27_10_ParameterPlots(result.directory);end
approximation=Start_TC27_10_ApproximationDiagnostics(result.directory);
file=fullfile(c.report,'TC27_01_10_结果与回收报告.md');
fid=fopen(file,'w','n','UTF-8');assert(fid>0,'不能写入结果报告。');clean=onCleanup(@()fclose(fid));
fprintf(fid,'# TC27-01至10三部件结果与回收报告\n\n');
fprintf(fid,'生成时间：%s。模型为三部件Visser16；本批编号为%s。\n\n',datestr(now,31),c.options.tag);
fprintf(fid,'## 1 本批范围与依据\n\n');
fprintf(fid,['本报告读取本批冻结合同、确定性Excel、UQ结果及其预测，不根据历史批次名推断已经完成的工作。' ...
    '运行资产、实际窗口、主参数和误差模型均以合同为准；热模型和试车数据的前置验证见本分支回收记录。' ...
    '此报告入口不重新辨识、不执行UQ B，也不修改StartupStop或TC24正式结果。\n\n']);
fprintf(fid,'正式确定性输入：`%s`。SHA-256：`%s`。\n\n',c.formalInputFile,c.identity.delivery);
fprintf(fid,'本次UQ合同：`%s`。内部结果目录：`%s`。\n\n',c.contractHash,c.directory);
fprintf(fid,['稳态系数UQ保持Visser16标称增强热效应开启，13项瞬态个体修正固定为零；' ...
    '没有把TC27-07新估计值带入似然。“零瞬态修正”不等于关闭增强瞬态效应。\n\n']);
fprintf(fid,'## 2 TC27-07瞬态系数辨识\n\n');
foundTransient=false;
for scope={'full_history','event_windows'}
    transientFile=fullfile(p.middle,['tc27_transient_',c.options.tag,'_',c.route,'_',c.method,'_',scope{1},'_result.mat']);
    if ~isfile(transientFile),continue;end
    a=load(transientFile,'result');r=a.result;foundTransient=true;
    fprintf(fid,'### %s\n\n',scope{1});
    fprintf(fid,['固定本批稳态曲线及燃油偏置，从零瞬态修正直接进入前向差分辨识，' ...
        '零中心Tikhonov正则；每轮当前参数完成局部准备，扰动共享完整起点状态，正式候选目标重新准备。\n\n']);
    fprintf(fid,'已执行独立快速初值：%d；要求释放预检前置：%d。lambda=%.6g，实际lambda平方权重=%.6g；辨识/验证步长为%.3f/%.3f秒。\n\n', ...
        r.quickInitializationExecuted,r.releasePrecheckRequired,r.options.lambda,r.options.lambda^2, ...
        r.options.integrationStep_s,r.options.validationIntegrationStep_s);
    fprintf(fid,'本次估计及验证耗时 %.1f 秒。停止原因 `%s`，更新数 %d；13项无量纲参数RMSE %.7g。\n\n', ...
        r.elapsedThisInvocation_s,char(r.solve.stopReason),r.solve.iterationCount,r.parameterRMSE);
    if isfield(r.solve,'exactJacobianAudit')
        fprintf(fid,'最终完整准备的投影梯度 %.7g，完整与复用Jacobian的尺度化相对矩阵差 %.7g；不将目标小改善当作严格驻点。\n\n', ...
            r.solve.exactJacobianAudit.projectedGradient,r.solve.exactJacobianAudit.relativeScaledFrobeniusDifference);
    end
    local_table(fid,r.parameterComparison);
    fprintf(fid,'\n### 完整独立测试\n\n');local_table(fid,r.testMetrics);
    fprintf(fid,'\n正式交付：`%s`。\n\n',r.deliveryFile);
end
if ~foundTransient
    fprintf(fid,'本UQ批次未找到同tag/路径/方法的07最终结果；不借用其他批次、不自动启动07。稳态系数UQ仍按上述合同独立执行。\n\n');
end
fprintf(fid,'## 3 TC27-08至09方法与执行结果\n\n');
fprintf(fid,['72维主参数为实际曲线节点、常值和燃油偏置节点，不是72个彼此独立的部件。' ...
    'C/D采用同一个独立零中心相关截断先验，不把TC24后验或当前确定性估计重复当作先验。' ...
    '24维附加参数采用参考点一阶响应；D使用截断先验矩高斯近似，新C通过矩形概率比保留原物理边界。\n\n']);
fprintf(fid,'观测模式`%s`；附加参数锚点`%s`；误差合同`%s`。\n\n', ...
    c.observationMode,c.options.nuisanceAnchorMode,c.options.errorModel);
fprintf(fid,['本合同推断路径为瞬态时刻：稳态点的Np/Ng为输入，前两项残差是dNp/dt和dNg/dt，单位r/min/s；' ...
    '热状态求平衡。仅稳态观测不等于改用稳态轴速作为似然输出；独立工况预测另用稳态模型求Np/Ng。\n\n']);
fprintf(fid,'各类主参数的先验尺度与物理搜索边界如下。sigma为截断前正态尺度，不等于95%%区间半宽；同组节点还具有既定相关结构。\n\n');
priorTable=unique(c.parameterTable(:,{'base_name','prior_sigma','lower_bound','upper_bound','unit'}),'rows','stable');
local_table(fid,priorTable);
fprintf(fid,['%d个稳态训练点与%d段完整小幅训练历程形成%d维残差；使用实际窗口样本数，' ...
    '稳态点输入白噪声按逐通道响应传播，历程输入白噪声通过%d次固定种子回放传播，输出白噪声位于FOH传感器动态之后，' ...
    '两批公共偏置分别处理。UQ积分步长%.3f秒，不作工程0.7/0.3目标缩放。\n\n'], ...
    height(c.trainingData),numel(c.histories),numel(c.observed), ...
    c.options.measurementSamples*double(~isempty(c.histories)),c.options.integrationStep_s);
fprintf(fid,['D构造矩高斯边缘目标的有界局部二次分布；新C保持附加参数边界，不是与D完全相同似然的纯算法对照。C后端按冻结合同可采用代理渐进桥接、直接DLL SMC或历史代理重加权。' ...
    'D是局部近似；C的精确性只针对已定义目标，' ...
    '不意味着测量、附加参数或初始热状态假设已获得统计校准。\n\n']);
if isempty(c.histories)
    fprintf(fid,'仅稳态模式没有历程噪声MC回放，该项方差稳定性指标不适用。\n\n');
else
    fprintf(fid,'输入噪声半数/全数回放方差相对差：%.5g；只诊断有限样本协方差稳定性。\n\n',result.inputNoiseCovarianceAudit);
end
fprintf(fid,'D状态：`%s`，最终投影梯度 %.5g，局部采样Rhat %.5g，最小局部ESS %.5g。\n\n', ...
    result.D.quality,result.D.projectedGradient,result.D.localRhat, ...
    result.D.localSamplingDiagnostics.minimumAutocorrelationESS);
fprintf(fid,'D最终迭代记录：\n\n');local_table(fid,result.D.history);
if contains(result.D.quality,'NONSTATIONARY')
    fprintf(fid,['**D局部优化尚未达到驻点。下列区间用于评价当前局部二次近似，' ...
        '不是已经确认的全局后验区间；局部抽样Rhat不能解除这个限制。**\n\n']);
end
if isfield(result,'C')
    fprintf(fid,'C状态：`%s`；权重ESS %.2f/%d；互异支撑ESS %.2f，互异参数点%d个。\n\n', ...
        result.C.quality,result.C.effectiveSampleSize,size(result.C.theta,2), ...
        result.C.distinctSupportWeightESS,result.C.distinctSampleCount);
    if isfield(result.C,'samplingBackend'),fprintf(fid,'C后端：`%s`。\n\n',result.C.samplingBackend);end
    if isfield(result.C,'bridgeResult')
        b=result.C.bridgeResult;
        fprintf(fid,'代理桥已到gamma=%.6f；移动候选%d，需精确筛查%d，最终接受%d，祖先%d。权重ESS不是独立样本数。\n\n', ...
            b.gamma,b.attempted,b.screenPassed,b.accepted,b.ancestorCount);
    end
    if contains(result.C.quality,'LIMITED_ESS')
        fprintf(fid,['**C精确校正后的概率支撑不足。仍输出全部样本、权重及条件预测作为诊断结果，' ...
            '但不能将其均值视为稳定的后验均值，也不能将极窄的分位区间解释为参数准确性很高。' ...
            'Excel接口通过不等同于这部分统计精度通过。**\n\n']);
    end
    rr=result.C.roundDiagnostics;
    for k=1:numel(rr)
        if isempty(rr{k}),continue;end
        q=rr{k};
        if isfield(q,'blindCenteredMedian')
            fprintf(fid,'- 代理轮%d：训练%d组，独立盲测%d组；中心化绝对对数似然误差中位数%.5g、标准差%.5g。\n', ...
                q.round,q.trainingCount,q.blindCount,q.blindCenteredMedian,q.blindStdLogError);continue;
        end
        fprintf(fid,'- 轮%d：训练%d组、beta %.6f、精确有效%d/%d、权重ESS %.2f、互异支撑ESS %.2f；盲测中位绝对对数似然差 %.5g。\n', ...
            q.round,q.trainingCount,q.smcFinalBeta,nnz(q.exactValid),numel(q.exactValid),q.effectiveSampleSize, ...
            q.distinctSupportWeightESS,q.blindAudit.medianAbsDeltaLogLikelihood);
        fprintf(fid,'  本轮状态 `%s`，固定校正预算是否完整执行：%d；先导早停批仅用于加密，不能交付为后验。\n', ...
            q.quality,q.fixedCountCorrectionCompleted);
    end
end
fprintf(fid,'\n残差马氏平方和/观测数：D %.6g',result.fitDiagnostic.DMahalanobisPerObservation);
if isfield(result.fitDiagnostic,'CMahalanobisPerObservation'),fprintf(fid,'，C %.6g',result.fitDiagnostic.CMahalanobisPerObservation);end
fprintf(fid,'。这是拟合诊断，不单独等同于校准通过。\n\n');
fprintf(fid,'## 4 参数区间与真值对照\n\n');local_table(fid,result.audit.comparison);
fprintf(fid,'\n健康节点RMSE为无量纲，燃油节点RMSE为g/s，不能混算。节点覆盖为本组合成样例结果，不是重复试验覆盖率。\n\n');
fprintf(fid,'![C与D参数区间同图对比](C_D_parameter_intervals.png)\n\n');
for method={'C','D'}
    name=method{1};if ~isfield(result.prediction,name),continue;end
    t=result.prediction.(name).summary;t.interval_width=t.q975-t.q025;
    fprintf(fid,'### %s全部节点\n\n![%s参数区间](method_%s_parameter_intervals.png)\n\n',name,name,name);
    local_table(fid,t(:,{'name','unit','deterministic_estimate','posterior_mean','q025','q975','truth','truthCovered','interval_width'}));
end
fprintf(fid,'\n## 5 TC27-10独立输出预测\n\n');
fprintf(fid,['两套稳态测试均使用完整稳态模型，不固定测试转速作为预测结果；' ...
    '只有显式启用的历程预测才逐状态积分，小幅测试是否存在以本批预测文件为准。图中比较测量、确定性预测和UQ均值。' ...
    '蓝色区间为条件模型区间，灰色区间额外加入新的输出测量误差；' ...
    '二者均未传播测试输入误差和模型结构误差，不应称为完备预测不确定性。\n\n']);
local_table(fid,result.prediction.metrics);
fprintf(fid,'\n### 同一测试记录上的均值预测误差\n\n');
outputComparison=local_output_comparison(c);
writetable(outputComparison,fullfile(c.report,'deterministic_C_D_output_RMSE.csv'));
local_table(fid,outputComparison);
fprintf(fid,['上表逐通道保留物理单位；不将不同量纲混算。C/D为当前带质量限制的条件预测，' ...
    '不能仅因某一输出RMSE较小就解除参数权重退化、局部非驻点或附加参数物理越界的限制。\n\n']);
for method={'C','D'}
    name=method{1};if ~isfield(result.prediction,name),continue;end
    for label={'TC23','TC26','test-H01','test-H02'}
        imageFile=[name,'_',label{1},'_prediction_intervals.png'];
        if isfile(fullfile(c.report,imageFile)),fprintf(fid,'\n![%s %s预测](%s)\n',name,label{1},imageFile);end
    end
end
fprintf(fid,'\n## 6 耗时、交付与局限\n\n');
fprintf(fid,'### 附加参数物理支撑与输入误差分辨率\n\n');
local_table(fid,approximation.nuisance(:,{'method','c_index','name','lower','upper', ...
    'mean','conditional_mean_average','conditional_std','marginal_std','outside_physical_support_probability'}));
fprintf(fid,['条件高斯分布不是原有界先验的严格条件分布。若上表越界概率接近1，' ...
    '说明用矩高斯分布替代原物理支撑在此样例不适用；不能把这种分布传播出的区间作为物理上可靠的后验预测。' ...
    '主参数DLL可解不解除此问题。应先检验有界附加参数边缘化，再评价代理与采样精度，不能通过调小或调大误差方差追逐真值覆盖。\n\n']);
local_table(fid,approximation.inputCovarianceRank);
fprintf(fid,['有限次数输入误差回放得到的样本协方差秩最多为次数减一。' ...
    '上表只说明已估计协方差的分辨率上限，不单独证明真实物理协方差应为高秩或当前方差必然偏小。' ...
    '后续需采用独立批次或沿历程的线性状态误差传播检查似然敏感方向，' ...
    '不能只检查逐时刻方差，也不能只增加后验粒子数。\n\n']);
fprintf(fid,'UQ入口至预测、Excel和审计完成 %.1f 秒（%.3f小时）；其中推断 %.1f 秒，预测 %.1f 秒。此计时在报告整理前记录，包含报告及额外复验的总墙钟见本批驱动日志。\n\n', ...
    result.totalWallTime_s,result.totalWallTime_s/3600,result.inferenceWallTime_s,result.prediction.runtime_s);
fprintf(fid,['此时间不含确定性辨识及TC27-07，也不含人工开发调试。若复用同合同缓存，必须按本次实际墙钟时间解释，' ...
    '不能把重启后的短时间说成首次从输入到结果的时间。\n\n']);
for method={'C','D'}
    if isfield(result,method{1}),fprintf(fid,'正式%s Excel：`%s`。\n\n',method{1},sht_tc27_uq_delivery_path(c,method{1}));end
end
fprintf(fid,['读入`sht_tc27_uq_delivery(''read'',file)`获得调度模板、主节点样本和权重；' ...
    'C保留配对的有界附加参数样本，D保留条件矩近似。不需要MAT缓存或隐藏真值。\n\n']);
fprintf(fid,['尚未覆盖的内容：B方法、全局多峰覆盖保证、附加参数精确联合非线性传播、' ...
    '测试输入误差传播、窗口初始热记忆和结构偏差的完整校准。' ...
    '局部条件高斯附加参数可能越出原物理支撑，预测MAT保留越界概率的边际下界与并集上界。' ...
    '这些是适用范围，不得由Excel接口通过替代。\n\n']);
fprintf(fid,'本报告供MAIN按文件哈希阶段性回收；不自动改写MAIN状态、不复制覆盖目录、不结束分支。\n');
fprintf('TC27结果报告：%s\n',file);
end

function local_table(fid,t)
names=t.Properties.VariableNames;fprintf(fid,'|%s|\n',strjoin(names,'|'));
fprintf(fid,'|%s|\n',strjoin(repmat({'---'},1,width(t)),'|'));
for row=1:height(t)
    values=cell(1,width(t));
    for col=1:width(t)
        x=t{row,col};
        if iscell(x),x=x{1};end
        if isnumeric(x)||islogical(x),values{col}=sprintf('%.7g',x);
        else,values{col}=char(string(x));end
        values{col}=strrep(values{col},'|','/');
    end
    fprintf(fid,'|%s|\n',strjoin(values,'|'));
end
fprintf(fid,'\n');
end

function result=local_output_comparison(c)
% 只读已冻结预测表，不重新调用DLL，也不根据测试误差选择后验。
result=table();units={'r/min','r/min','Pa','K','Pa','K','Pa','K','kg/s'};
for label={'TC23','TC26','test-H01','test-H02'}
    cf=fullfile(c.report,['C_',label{1},'_prediction_intervals.csv']);
    df=fullfile(c.report,['D_',label{1},'_prediction_intervals.csv']);
    if ~isfile(cf)||~isfile(df),continue;end
    ct=readtable(cf);dt=readtable(df);
    assert(isequal(string(ct.output),string(dt.output))&&isequal(ct.coordinate,dt.coordinate)&& ...
        isequal(ct.measurement,dt.measurement),'C/D预测的测量对象不一致。');
    for j=1:9
        selected=string(ct.output)==string(c.historyNames{j});
        y=ct.measurement(selected);values=[ct.deterministic(selected),ct.posterior_mean(selected),dt.posterior_mean(selected)];
        valid=all(isfinite(values),1);rmse=nan(1,3);
        rmse(valid)=sqrt(mean((values(:,valid)-y).^2,1));
        result=[result;table(string(label{1}),string(c.historyNames{j}),string(units{j}), ...
            numel(y),rmse(1),rmse(2),rmse(3),'VariableNames', ...
            {'test_set','output','unit','sample_count','deterministic_RMSE','C_RMSE','D_RMSE'})]; %#ok<AGROW>
    end
end
end
