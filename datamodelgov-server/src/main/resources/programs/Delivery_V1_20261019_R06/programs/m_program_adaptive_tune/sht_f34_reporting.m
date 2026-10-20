function report=sht_f34_reporting(prepared,likelihood,methodD,methodC, ...
        prediction,delivery)
%SHT_F34_REPORTING 生成3.4 R1参数、相关性、预测和Q敏感性图。
% 本函数在后验冻结后运行，不改变先验、似然、权重或采样停止条件。
if nargin<5,prediction=[];end
if nargin<6,delivery=struct();end
folder=prepared.paths.reportDir;
if ~isfolder(folder),mkdir(folder);end
visible=prepared.options.plotVisible;

files=strings(0,1);
files(end+1)=local_parameter_interval_figure(folder,visible,prepared,methodD,methodC);
files(end+1)=local_marginal_figure(folder,visible,prepared,methodD,methodC);
files(end+1)=local_correlation_figure(folder,visible,prepared,methodC);
files(end+1)=local_q_sensitivity_figure(folder,visible,prepared,methodC);
if isfield(methodC,'curveSummary')
    files(end+1)=local_curve_interval_figure(folder,visible,methodC.curveSummary);
end
if ~isempty(prediction)
    files(end+1)=local_prediction_figure(folder,visible,prediction);
    if isfield(prediction,'engineeringCompensation')
        files(end+1)=local_compensation_figure(folder,visible, ...
            prediction.engineeringCompensation);
    end
end
truthDiagnostic=local_truth_diagnostic(folder,visible,prepared,methodD,methodC);
if truthDiagnostic.performed,files(end+1)=truthDiagnostic.figureFile;end
summaryFile=prepared.paths.summaryFile;
local_write_summary(summaryFile,prepared,likelihood,methodD,methodC, ...
    prediction,delivery,truthDiagnostic);
report=struct('schemaVersion','SHT_F34_R1_REPORT_V1', ...
    'createdAt',datestr(now,31),'figureFiles',files, ...
    'summaryFile',summaryFile,'truthDiagnostic',truthDiagnostic, ...
    'truthDataUsedForInference',false, ...
    'truthDataUsedAfterPosteriorFreeze',truthDiagnostic.performed, ...
    'processCovarianceCalibrated',false, ...
    'processCovarianceStatus',prepared.contract.processCovarianceStatus);
end

function fileName=local_curve_interval_figure(folder,visible,summary)
curve=unique(string(summary.curve_id),'stable');
columnCount=3;rowCount=ceil(numel(curve)/columnCount);
figureHandle=figure('Visible',visible,'Color','w','Position',[40 30 1450 940]);
for i=1:numel(curve)
    row=summary(string(summary.curve_id)==curve(i),:);subplot(rowCount,columnCount,i);
    hold on;grid on;box on;
    x=row.coordinate;
    if height(row)==1
        errorbar(x,row.posterior_mean,row.posterior_mean-row.q025, ...
            row.q975-row.posterior_mean,'b-o','LineWidth',1.2,'MarkerSize',3);
    else
        fill([x;flipud(x)],[row.q025;flipud(row.q975)], ...
            [0.75 0.86 0.98],'EdgeColor','none','FaceAlpha',0.75);
        plot(x,row.posterior_mean,'b-o','LineWidth',1.2,'MarkerSize',3);
    end
    plot(x,row.reference_value,'k--','LineWidth',1.0);
    title(char(curve(i)),'Interpreter','none');xlabel('调度坐标');
    ylabel(char(row.unit(1)));
    if i==1,legend({'方法C 95%','方法C均值','上游参考'},'Location','best');end
end
fileName=fullfile(folder,'F34_R1_curve_node_intervals.png');
local_save(figureHandle,fileName);
end

function fileName=local_compensation_figure(folder,visible,diagnostic)
self=diagnostic.singleParameter;pair=diagnostic.pairDiagnostic;
figureHandle=figure('Visible',visible,'Color','w','Position',[80 80 1280 720]);
subplot(1,2,1);
bar(max(self.negative_normalized_rms,self.positive_normalized_rms));
hold on;plot([0.5,height(self)+0.5],[1,1],'r--','LineWidth',1.2);
grid on;box on;set(gca,'XTick',1:height(self), ...
    'XTickLabel',cellstr(self.parameter_id),'XTickLabelRotation',25);
ylabel('单参数扰动输出变化/1\sigma');
title('约1%单参数精确DLL敏感性');
subplot(1,2,2);
if isempty(pair)
    text(0.5,0.5,'没有满足幅值条件的候选参数对', ...
        'HorizontalAlignment','center');axis off;
else
    label=cellstr(pair.parameter_1+" / "+pair.parameter_2);
    bar(pair.pair_exact_rms);hold on;
    plot([0.5,height(pair)+0.5],[1,1],'r--','LineWidth',1.2);
    grid on;box on;set(gca,'XTick',1:height(pair),'XTickLabel',label, ...
        'XTickLabelRotation',35);
    ylabel('联合扰动输出变化/1\sigma');
    title('精确DLL成对补偿检查');
end
fileName=fullfile(folder,'F34_R1_engineering_compensation.png');
local_save(figureHandle,fileName);
end

function fileName=local_parameter_interval_figure(folder,visible,prepared,methodD,methodC)
p=prepared.prior.summary;n=height(p);x=(1:n).';
figureHandle=figure('Visible',visible,'Color','w','Position',[100 70 1250 800]);
priorLower=p.prior_mean-1.95996398454*p.prior_std_approx;
priorUpper=p.prior_mean+1.95996398454*p.prior_std_approx;
subplot(2,1,1);local_interval_axes(1:min(8,n),x,p,priorLower,priorUpper,methodD,methodC);
ylabel('无量纲参数');title('显式参数先验与95%后验区间');
subplot(2,1,2);local_interval_axes(n,x,p,priorLower,priorUpper,methodD,methodC);
ylabel('kg/s');title('飞行燃油换算偏置幅值');
fileName=fullfile(folder,'F34_R1_parameter_intervals.png');local_save(figureHandle,fileName);
end

function local_interval_axes(index,x,p,priorLower,priorUpper,methodD,methodC)
hold on;grid on;box on;
errorbar(x(index)-0.18,p.prior_mean(index), ...
    p.prior_mean(index)-priorLower(index),priorUpper(index)-p.prior_mean(index), ...
    'o','LineWidth',1.2,'DisplayName','传播后先验');
errorbar(x(index),methodD.map(index),methodD.map(index)-methodD.interval95(index,1), ...
    methodD.interval95(index,2)-methodD.map(index),'s','LineWidth',1.2, ...
    'DisplayName','方法D');
errorbar(x(index)+0.18,methodC.mean(index), ...
    methodC.mean(index)-methodC.interval95(index,1), ...
    methodC.interval95(index,2)-methodC.mean(index),'d','LineWidth',1.2, ...
    'DisplayName','方法C');
set(gca,'XTick',x(index),'XTickLabel',cellstr(p.parameter_id(index)), ...
    'XTickLabelRotation',25,'FontSize',10);
legend('Location','best');
end

function fileName=local_marginal_figure(folder,visible,prepared,methodD,methodC)
parameter=prepared.prior.parameterTable;priorSample=sht_f34_prior( ...
    'draw',prepared.prior,4000,340099);
figureHandle=figure('Visible',visible,'Color','w','Position',[60 40 1450 930]);
for i=1:height(parameter)
    subplot(3,3,i);hold on;box on;grid on;
    edges=linspace(parameter.lower_bound(i),parameter.upper_bound(i),23);
    histogram(priorSample(i,:),edges,'Normalization','pdf', ...
        'FaceColor',[0.65 0.65 0.65],'FaceAlpha',0.35,'EdgeColor','none');
    local_weighted_histogram(methodC.samples(i,:),methodC.weights(:),edges, ...
        [0.15 0.45 0.80],0.55);
    sigma=max(methodD.standardDeviation(i),eps);
    gridValue=linspace(parameter.lower_bound(i),parameter.upper_bound(i),250);
    density=exp(-0.5*((gridValue-methodD.map(i))/sigma).^2)/(sqrt(2*pi)*sigma);
    plot(gridValue,density,'r-','LineWidth',1.2);
    title(char(parameter.parameter_id(i)),'Interpreter','none');
    if i==1,legend({'先验','方法C','方法D局部近似'},'Location','best');end
end
fileName=fullfile(folder,'F34_R1_marginal_distributions.png');local_save(figureHandle,fileName);
end

function handle=local_weighted_histogram(sample,weights,edges,color,alpha)
sample=sample(:);weights=weights(:);
if numel(sample)~=numel(weights)
    error('SHT:F34Reporting:HistogramWeights', ...
        '后验样本数与权重数不一致。');
end
bin=discretize(sample,edges);
valid=isfinite(sample)&isfinite(weights)&weights>=0&~isnan(bin);
if ~any(valid)||sum(weights(valid))<=0
    error('SHT:F34Reporting:HistogramWeights', ...
        '后验直方图没有有效正权重样本。');
end
mass=accumarray(bin(valid),weights(valid),[numel(edges)-1,1],@sum,0);
mass=mass/sum(mass);
width=diff(edges(:));density=mass./width;
center=(edges(1:end-1)+edges(2:end))/2;
handle=bar(center,density,1,'FaceColor',color,'FaceAlpha',alpha, ...
    'EdgeColor','none');
end

function fileName=local_correlation_figure(folder,visible,prepared,methodC)
sigma=sqrt(max(diag(methodC.covariance),eps));
correlation=methodC.covariance./max(sigma*sigma.',eps);
label=cellstr(prepared.prior.parameterTable.parameter_id);
figureHandle=figure('Visible',visible,'Color','w','Position',[100 80 850 740]);
imagesc(correlation,[-1 1]);axis image;colorbar;colormap(parula(256));
set(gca,'XTick',1:numel(label),'YTick',1:numel(label), ...
    'XTickLabel',label,'YTickLabel',label,'XTickLabelRotation',30);
title('方法C后验相关系数（仅表示统计相关）');
fileName=fullfile(folder,'F34_R1_posterior_correlation.png');local_save(figureHandle,fileName);
end

function fileName=local_q_sensitivity_figure(folder,visible,prepared,methodC)
if isfield(methodC,'qSensitivity')&&istable(methodC.qSensitivity)
    summary=methodC.qSensitivity;
else
    summary=sht_f34_q_sensitivity(prepared,methodC);
end
parameterId=string(prepared.prior.parameterTable.parameter_id);
multiplier=unique(summary.q_covariance_multiplier,'stable').';
widthRatio=zeros(numel(parameterId),numel(multiplier));
for i=1:numel(multiplier)
    for j=1:numel(parameterId)
        row=summary.q_covariance_multiplier==multiplier(i)& ...
            string(summary.parameter_id)==parameterId(j);
        widthRatio(j,i)=summary.next_to_current_width_ratio(row);
    end
end
figureHandle=figure('Visible',visible,'Color','w','Position',[100 100 1200 620]);
bar(widthRatio);grid on;box on;
set(gca,'XTick',1:numel(parameterId), ...
    'XTickLabel',cellstr(parameterId), ...
    'XTickLabelRotation',25);
ylabel('下一架次/当前95%参数区间宽度比');
legend(arrayfun(@(x)sprintf('Q x %.1f',x),multiplier, ...
    'UniformOutput',false),'Location','best');
title('未标定架次变化协方差Q的工程敏感性');
fileName=fullfile(folder,'F34_R1_Q_sensitivity.png');local_save(figureHandle,fileName);
end

function fileName=local_prediction_figure(folder,visible,prediction)
channels={'Np','Ng','Pt3_eq','Tt45'};units={'rpm','rpm','Pa','K'};
n=numel(prediction.observation)/4;x=(1:n).';
figureHandle=figure('Visible',visible,'Color','w','Position',[50 60 1450 830]);
for i=1:4
    index=(i-1)*n+(1:n);subplot(2,2,i);hold on;grid on;box on;
    qC=prediction.methodC.fixed_transfer.observable;
    qD=prediction.methodD.fixed_transfer.observable;
    errorbar(x-0.08,qC.mean(index),qC.mean(index)-qC.lower95(index), ...
        qC.upper95(index)-qC.mean(index),'o','LineWidth',1.1);
    errorbar(x+0.08,qD.mean(index),qD.mean(index)-qD.lower95(index), ...
        qD.upper95(index)-qD.mean(index),'s','LineWidth',1.1);
    plot(x,prediction.observation(index),'kx','LineWidth',1.4,'MarkerSize',8);
    title(channels{i},'Interpreter','none');xlabel('独立任务稳态窗口');ylabel(units{i});
    if i==1,legend({'方法C 95%','方法D 95%','测量值'},'Location','best');end
end
fileName=fullfile(folder,'F34_R1_independent_prediction_intervals.png');local_save(figureHandle,fileName);
end

function local_write_summary(fileName,prepared,likelihood,methodD,methodC, ...
        prediction,delivery,truthDiagnostic)
fid=fopen(fileName,'w','n','UTF-8');
if fid<0,error('SHT:F34Report:Open','无法写入结果摘要。');end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'# 3.4 方法C/D不确定性评估结果\n\n');
fprintf(fid,'- 实际参数推断路径：`%s`；数据：`%s`；模型模式：%d。\n', ...
    prepared.context.options.modelRoute,prepared.options.dataMethod,prepared.options.modelMode);
fprintf(fid,'- 显式参数：%d维；条件形状干扰：%d维。\n', ...
    height(prepared.prior.parameterTable),prepared.prior.shape.retainedRank);
fprintf(fid,'- 训练观测：%d个，来自%d个稳态窗口。\n', ...
    numel(likelihood.observation),height(prepared.context.steadyData));
fprintf(fid,'- 方法D：objective=%.6f，converged=%d，stop=%s，%.1f s。\n', ...
    methodD.objective,methodD.converged,methodD.stopReason,methodD.runtime_s);
fprintf(fid,'- 方法C：%d粒子，ESS=%.1f，%d个温度层，%.1f s。\n', ...
    methodC.particleCount,methodC.ess,numel(methodC.stage),methodC.runtime_s);
fprintf(fid,['- 方法C多样性：不同参数点%d/%d，不同祖先%d/%d，' ...
    '累计移动接受率%.3f。\n'],methodC.uniqueParticleCount, ...
    methodC.particleCount,methodC.uniqueAncestorCount,methodC.particleCount, ...
    methodC.totalMoveAcceptance);
if isfield(methodC,'independentRepeatStability')
    s=methodC.independentRepeatStability;
    fprintf(fid,['- 独立随机种子复算：%s，最大均值差/后验标准差' ...
        '=%.3f，最小95%%区间重叠比=%.3f。\n'],s.qualityLevel, ...
        s.maximumMeanDifferenceOverPosteriorStd, ...
        s.minimumIntervalOverlapFraction);
    if ~s.stable
        fprintf(fid,['- 采样质量说明：主运行已到beta=1，但独立种子复算尚未稳定；' ...
            '权重ESS不等于独立样本数。当前区间是有限粒子、条件近似下的阶段性估计，' ...
            '不是已经统计校准或高精度Monte Carlo结果。应先诊断提议覆盖、移动混合' ...
            '与条件近似误差，再决定是否增大样本预算。\n']);
    end
end
if isfield(methodC,'qSensitivity')
    q1=methodC.qSensitivity(methodC.qSensitivity.q_covariance_multiplier==1,:);
    fprintf(fid,['- 工程Q基准传播使显式参数95%%区间宽度变为当前后验的' ...
        '%.3f至%.3f倍；该比值来自实际截断混合传播核。\n'], ...
        min(q1.next_to_current_width_ratio),max(q1.next_to_current_width_ratio));
end
fprintf(fid,'- Q状态：`%s`。\n',prepared.contract.processCovarianceStatus);
fprintf(fid,['- 重要限制：跨阶段/架次变化协方差当前只有工程经验值，' ...
    '不是纵向数据标定结果。后续必须利用同一台发动机多架次后验增量、' ...
    '任务间隔及维修记录进行专项标定和长期覆盖率校验。\n\n']);
fprintf(fid,'## 显式参数结果\n\n');
fprintf(fid,['- 目标说明：显式参数使用完整DLL；条件形状干扰仍作局部线性高斯边缘化，' ...
    '不能把DLL精确求值解释为整个概率模型无近似。D未收敛时只称局部参考点，不称已验证MAP。\n\n']);
fprintf(fid,'| 参数 | 先验均值 | D局部参考点 | C均值 | C-2.5%% | C-97.5%% |\n');
fprintf(fid,'|---|---:|---:|---:|---:|---:|\n');
for i=1:height(methodC.summary)
    fprintf(fid,'| %s | %.7g | %.7g | %.7g | %.7g | %.7g |\n', ...
        char(methodC.summary.parameter_id(i)),prepared.prior.summary.prior_mean(i), ...
        methodD.map(i),methodC.mean(i),methodC.interval95(i,1),methodC.interval95(i,2));
end
if ~isempty(prediction)
    fprintf(fid,'\n## 独立任务预测\n\n');
    fprintf(fid,['下表对应独立验证任务的%d个稳态窗口，不代表600 s全历程' ...
        '同时预测带。RMSE按物理预测均值计算，区间宽度为包含输出测量误差的' ...
        '可观测点态95%%区间平均宽度。\n\n'],height(prediction.testData));
    row=prediction.summary(string(prediction.summary.method)=="C" & ...
        string(prediction.summary.prediction_mode)=="fixed_transfer" & ...
        string(prediction.summary.interval_layer)=="observable",:);
    fprintf(fid,'| 通道 | RMSE | 单位 | 95%%平均宽度 | 样本覆盖率 |\n');
    fprintf(fid,'|---|---:|---|---:|---:|\n');
    for i=1:height(row)
        fprintf(fid,'| %s | %.6g | %s | %.6g | %.3f |\n', ...
            char(row.channel(i)),row.rmse(i),char(row.unit(i)), ...
            row.mean_interval_width(i),row.coverage95(i));
    end
    if isfield(prediction,'methodC')&& ...
            isfield(prediction.methodC,'physicalValidityAudit')
        audit=prediction.methodC.physicalValidityAudit;
        fprintf(fid,'\n### 独立任务物理适用域审计\n\n');
        fprintf(fid,['- 固定传递：%d个候选中%d个同时满足显式参数支持域和' ...
            '独立任务物理解；显式无效%d个，条件形状物理无效%d个。\n'], ...
            audit.fixedCandidateCount,audit.fixedValidCount, ...
            audit.fixedInvalidExplicitCount,audit.fixedInvalidPhysicalCount);
        fprintf(fid,['- 下一架次：%d个传播候选中%d个同时有效；显式无效%d个，' ...
            '条件形状物理无效%d个。预测区间以独立任务可解性为条件，' ...
            '无效比例是模型适用域诊断，不得隐藏或重解释为测量噪声。\n'], ...
            audit.nextCandidateCount,audit.nextValidCount, ...
            audit.nextInvalidExplicitCount,audit.nextInvalidPhysicalCount);
    end
    if isfield(prediction,'engineeringCompensation')
        e=prediction.engineeringCompensation;
        fprintf(fid,'\n## 工程幅值补偿诊断\n\n');
        fprintf(fid,['- 约1%%单参数扰动中，自身低敏感参数%d个；' ...
            '精确检查参数对%d对，证明工程补偿%d对。\n'], ...
            e.selfLowSensitivityCount,e.exactPairCount,e.demonstratedPairCount);
        fprintf(fid,['- 判据采用训练观测总标准差归一化；该结果只覆盖后验中心附近、' ...
            '已检查参数对及声明扰动幅值，不证明全局不存在其他补偿或多峰。\n']);
    end
end
if truthDiagnostic.performed
    fprintf(fid,'\n## 冻结后隐藏真值诊断\n\n');
    fprintf(fid,['下表仅在后验权重和区间冻结后读取隐藏真值，' ...
        '不参与先验、似然、采样、停止或方法选择。\n\n']);
    value=truthDiagnostic.table;
    fprintf(fid,'本次9个隐藏参数真值中，%d个落入方法C边际95%%区间。\n\n', ...
        nnz(value.method_c_interval_contains_truth));
    fprintf(fid,'| 参数 | 训练真值 | C均值 | 绝对误差 | 95%%区间含真值 |\n');
    fprintf(fid,'|---|---:|---:|---:|---:|\n');
    for i=1:height(value)
        fprintf(fid,'| %s | %.7g | %.7g | %.7g | %d |\n', ...
            char(value.parameter_id(i)),value.truth_training(i), ...
            value.method_c_mean(i),value.method_c_absolute_error(i), ...
            value.method_c_interval_contains_truth(i));
    end
end
if isstruct(delivery)&&isfield(delivery,'workbookFile')
    fprintf(fid,'\n- 正式Excel：`%s`\n',delivery.workbookFile);
end
end

function diagnostic=local_truth_diagnostic(folder,visible,prepared,methodD,methodC)
fileName=fullfile(prepared.paths.thisDir,'MiddleData','flight_model_adapt_3p3_v2', ...
    ['flight_model_adapt_3p3_full_history_validation_set1_steady_' ...
    'steady_only_family_amplitude_latest.mat']);
diagnostic=struct('performed',false,'table',table(),'sourceFile',fileName, ...
    'figureFile',"",'truthDataUsedForInference',false);
% 旧六部件真值报告不能作为三部件真值。三部件由独立冻结后分析入口处理。
if prepared.options.modelMode==0
    diagnostic.sourceFile='';return;
end
if ~isfile(fileName),return;end
loaded=load(fileName,'result');
if ~isfield(loaded,'result')||~isfield(loaded.result,'truthComparison')|| ...
        ~loaded.result.truthComparison.performed|| ...
        loaded.result.truthComparison.truthDataUsedForEstimation
    return;
end
source=loaded.result.truthComparison.parameterTable;
parameterId=string(methodC.summary.parameter_id);n=numel(parameterId);
truth=zeros(n,1);representation=zeros(n,1);truthSource=strings(n,1);
for i=1:n
    row=find(string(source.parameter_id)==parameterId(i),1);
    if isempty(row),return;end
    truth(i)=source.truth_training(row);
    representation(i)=source.truth_projection_representation_rmse(row);
    truthSource(i)=string(source.truth_source(row));
end
methodCError=methodC.mean-truth;methodDError=methodD.map-truth;
containsTruth=truth>=methodC.interval95(:,1)&truth<=methodC.interval95(:,2);
tableValue=table(parameterId,string(methodC.summary.unit),truth,methodD.map, ...
    methodDError,abs(methodDError),methodC.mean,methodCError,abs(methodCError), ...
    methodC.interval95(:,1),methodC.interval95(:,2),containsTruth, ...
    representation,truthSource,'VariableNames',{'parameter_id','unit', ...
    'truth_training','method_d_map','method_d_error','method_d_absolute_error', ...
    'method_c_mean','method_c_error','method_c_absolute_error','method_c_q025', ...
    'method_c_q975','method_c_interval_contains_truth', ...
    'truth_projection_representation_rmse','truth_source'});
csvFile=fullfile(folder,'F34_R1_postfreeze_truth_diagnostic.csv');
writetable(tableValue,csvFile);

scale=max(prepared.prior.summary.prior_std_approx,eps);x=(1:n).';
figureHandle=figure('Visible',visible,'Color','w','Position',[100 100 1200 620]);
center=(methodC.mean-truth)./scale;
lower=(methodC.interval95(:,1)-truth)./scale;
upper=(methodC.interval95(:,2)-truth)./scale;
errorbar(x,center,center-lower,upper-center,'o','LineWidth',1.2);hold on;
plot([0,n+1],[0,0],'k--');grid on;box on;
set(gca,'XTick',x,'XTickLabel',cellstr(parameterId),'XTickLabelRotation',25);
ylabel('相对于先验标准差的真值偏差');
title('方法C冻结后真值诊断（真值未参与推断）');
figureFile=fullfile(folder,'F34_R1_postfreeze_truth_diagnostic.png');
local_save(figureHandle,figureFile);
diagnostic=struct('performed',true,'table',tableValue, ...
    'sourceFile',fileName,'csvFile',csvFile,'figureFile',string(figureFile), ...
    'truthDataUsedForInference',false);
end

function local_save(figureHandle,fileName)
set(findall(figureHandle,'Type','axes'),'TickLabelInterpreter','none');
set(figureHandle,'PaperPositionMode','auto');
print(figureHandle,fileName,'-dpng','-r180');close(figureHandle);
end
