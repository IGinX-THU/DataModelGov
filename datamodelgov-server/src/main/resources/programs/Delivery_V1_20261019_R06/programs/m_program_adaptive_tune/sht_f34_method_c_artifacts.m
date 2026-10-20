function result=sht_f34_method_c_artifacts(p,L,D,C,pred,delivery,reportOptions)
%SHT_F34_METHOD_C_ARTIFACTS 冻结后比较全部参数、实际曲线和训练/独立输出。
% 真值仅作可选报告输入，不影响采样、预测或正式Excel。幅值误差与曲线
% 物理取值误差分别列出；燃油用kg/s，不与无量纲系数混算RMSE。
if nargin<7,reportOptions=struct();end
folder=p.paths.reportDir;n=height(C.summary);tab=C.summary;
nodeMode=isfield(p.prior,'nodePrior');
tab.deterministic=p.context.uqReferenceResult.estimatedTheta(:);tab.d_mean=D.map;
tab.d_q025=D.interval95(:,1);tab.d_q975=D.interval95(:,2);
tab.truth_equivalent=nan(n,1);tab.truth_representation_rmse=nan(n,1);
truthFile=''; % 真值只能由冻结后报告显式选入，不能暗读历史样例。
if isfield(reportOptions,'truthComparisonFile'),truthFile=reportOptions.truthComparisonFile;end
if isfile(truthFile)
    t=readtable(truthFile);t=t(string(t.variant)=="transient_steady_only",:);
    for j=1:n
        row=find(string(t.parameter_id)==string(tab.parameter_id(j)));
        if numel(row)==1&&abs(t.estimate(row)-tab.deterministic(j))<1e-12
            tab.truth_equivalent(j)=t.truth_training(row);
            tab.truth_representation_rmse(j)=t.truth_projection_representation_rmse(row);
        end
    end
end
tab.deterministic_error=tab.deterministic-tab.truth_equivalent;
tab.d_error=tab.d_mean-tab.truth_equivalent;tab.c_error=tab.posterior_mean-tab.truth_equivalent;
tab.truth_in_c_interval=tab.truth_equivalent>=tab.q025&tab.truth_equivalent<=tab.q975;
writetable(tab,fullfile(folder,'C_all_parameters.csv'));
writetable(C.curveSummary,fullfile(folder,'C_physical_curve_intervals.csv'));
writetable(struct2table(C.stage),fullfile(folder,'C_temperature_stages.csv'));
writetable(C.independentRepeatStability.table,fullfile(folder,'C_independent_repeat.csv'));
writetable(C.marginalModeDiagnostic,fullfile(folder,'C_marginal_diagnostics.csv'));
writetable(C.qSensitivity,fullfile(folder,'C_Q_sensitivity.csv'));
writetable(p.context.steadySource,fullfile(folder,'C_training_windows.csv'));
if ~isempty(pred)
writetable(pred.summary,fullfile(folder,'C_D_prediction_summary.csv'));
writetable(pred.baselineComparison,fullfile(folder,'C_D_baseline_comparison.csv'));
writetable(pred.testSource,fullfile(folder,'C_test_windows.csv'));
detail=pred.detail;detail.observed=zeros(height(detail),1);
channels={'Np','Ng','Pt3_eq','Tt45'};columns={'Np_mean','Ng_mean','Pt3_mean','Tt45_mean'};
for j=1:height(detail)
    row=find(string(pred.testData.point_id)==string(detail.point_id(j)));
    col=find(strcmp(channels,char(detail.channel(j))));
    detail.observed(j)=pred.testData.(columns{col})(row);
end
detail.error=detail.mean-detail.observed;
writetable(detail,fullfile(folder,'C_D_prediction_points.csv'));
end
% 训练似然预测保留逐样本条件形状均值。另验算均值模型的完整非线性响应，
% 二者不同，不能把f(E[参数])当成E[f(参数)]。
z=C.conditionalShapeMean*C.weights;
a=[zeros(n,1),tab.deterministic,D.map,C.mean];Z=[zeros(numel(z),2),D.conditionalShapeMean,z];
e=sht_f34_likelihood('evaluatePhysicalShape',p.context,p.prior,a,Z);
assert(all(e.valid),'冻结后均值模型训练诊断物理解无效。');
predictionMean=(C.physicalOutput+L.shapeSensitivity*C.conditionalShapeMean)*C.weights;
output=[e.output,predictionMean];labels={'TC24_deterministic','current_deterministic', ...
    'D_center_exact','C_mean_model_exact','C_posterior_mean_conditional_linear'};
train=table();m=height(p.context.steadyData);units={'Pa','K','rpm/s','rpm/s'};
if strcmp(p.context.options.modelRoute,'steady'),units={'rpm','rpm','Pa','K'};end
for k=1:numel(labels)
    for j=1:4
        index=(j-1)*m+(1:m);errorValue=output(index,k)-L.observation(index);
        train=[train;table(string(labels{k}),string(L.observationChannels{j}), ...
            string(units{j}),sqrt(mean(errorValue.^2)),mean(errorValue), ...
            'VariableNames',{'model','channel','unit','rmse','mean_error'})]; %#ok<AGROW>
    end
end
writetable(train,fullfile(folder,'C_training_output_comparison.csv'));
% 在后验冻结后抽取12个带权代表中心，复核条件形状仿射响应本身的误差。
% 这只是中心响应检查，不冒充对整个条件分布的非线性积分验收。
count=min(12,C.particleCount);cdf=cumsum(C.weights);cdf(end)=1;index=zeros(1,count);
for j=1:count,index(j)=find(cdf>=(j-.5)/count,1);end
exact=sht_f34_likelihood('evaluatePhysicalShape',p.context,p.prior, ...
    C.samples(:,index),C.conditionalShapeMean(:,index));
assert(all(exact.valid),'条件形状中心核查有无效物理解。');
affine=C.physicalOutput(:,index)+L.shapeSensitivity*C.conditionalShapeMean(:,index);
delta=exact.output-affine;normalized=chol(L.Rbase,'lower')\delta;centerAccuracy=table();
for j=1:4
    row=(j-1)*m+(1:m);v=delta(row,:);
    centerAccuracy=[centerAccuracy;table(string(L.observationChannels{j}),string(units{j}), ...
        sqrt(mean(v(:).^2)),max(abs(v(:))),'VariableNames', ...
        {'channel','unit','center_response_rmse','center_response_max_abs'})]; %#ok<AGROW>
end
writetable(centerAccuracy,fullfile(folder,'C_conditional_center_accuracy.csv'));
physicalFile=fullfile(fileparts(truthFile),'physical_parameters_at_points.csv');
physical=table();groups=table();
if ~isempty(truthFile)&&isfile(physicalFile)&&all(isfinite(tab.truth_equivalent))
    physical=readtable(physicalFile);physical.c_mean=nan(height(physical),1);
    for j=1:height(physical)
        q=C.curveSummary(string(C.curveSummary.curve_id)==string(physical.parameter(j)),:);
        assert(~isempty(q),'实际曲线缺少物理参数。');
        [x,order]=sort(q.coordinate);y=q.posterior_mean(order);
        if numel(x)==1,physical.c_mean(j)=y;
        else,physical.c_mean(j)=interp1(x,y,min(max(physical.coordinate(j),x(1)),x(end)));end
    end
    physical.c_error=physical.c_mean-physical.truth;
    groups=unique(physical(:,{'dataset','parameter','unit'}),'rows','stable');
    for j=1:height(groups)
        q=physical(string(physical.dataset)==string(groups.dataset(j))& ...
            string(physical.parameter)==string(groups.parameter(j)),:);
        groups.truth_mean(j)=mean(q.truth);groups.prior_rmse(j)=sqrt(mean(q.prior_error.^2));
        groups.deterministic_rmse(j)=sqrt(mean(q.estimate_error.^2));
        groups.c_rmse(j)=sqrt(mean(q.c_error.^2));
    end
    writetable(physical,fullfile(folder,'C_physical_parameters_at_points.csv'));
    writetable(groups,fullfile(folder,'C_physical_parameter_rmse.csv'));
end
if ~nodeMode
fig=figure('Visible','off','Color','w','Position',[60 60 1250 780]);
for j=1:n
    subplot(3,3,j);scale=100;unit='percentage points';
    if strcmp(char(tab.unit(j)),'kg/s'),scale=1000;unit='g/s';end
    mu=scale*[tab.deterministic(j),D.map(j),C.mean(j)];
    plot(1,mu(1),'ks','MarkerFaceColor','k');hold on;
    plot([2,2],scale*D.interval95(j,:),'b-','LineWidth',1.8);plot(2,mu(2),'bo');
    plot([3,3],scale*C.interval95(j,:),'r-','LineWidth',1.8);plot(3,mu(3),'ro');
    if isfinite(tab.truth_equivalent(j)),yline(scale*tab.truth_equivalent(j),'k--');end
    extent=scale*[tab.deterministic(j),D.interval95(j,:),C.interval95(j,:),tab.truth_equivalent(j)];
    extent=extent(isfinite(extent));padding=max(.08*(max(extent)-min(extent)),1e-6);
    ylim([min(extent)-padding,max(extent)+padding]);
    xlim([.5,3.5]);set(gca,'XTick',1:3,'XTickLabel',{'R020','D','C'});grid on;
    title(char(tab.parameter_id(j)),'Interpreter','none');ylabel(unit);
end
print(fig,fullfile(folder,'C_D_all_parameter_intervals.png'),'-dpng','-r150');close(fig);
repeat=C.independentRepeatStability.table;
fig=figure('Visible','off','Color','w','Position',[60 60 1250 780]);
for j=1:n
    subplot(3,3,j);scale=100;unit='percentage points';
    if strcmp(char(tab.unit(j)),'kg/s'),scale=1000;unit='g/s';end
    plot([1 1],scale*[repeat.primary_q025(j),repeat.primary_q975(j)],'r-','LineWidth',1.8);hold on;
    plot(1,scale*repeat.primary_mean(j),'ro');
    plot([2 2],scale*[repeat.repeat_q025(j),repeat.repeat_q975(j)],'b-','LineWidth',1.8);
    plot(2,scale*repeat.repeat_mean(j),'bo');
    xlim([.5 2.5]);set(gca,'XTick',1:2,'XTickLabel',{'C seed 340071','C seed 340072'});
    title(char(tab.parameter_id(j)),'Interpreter','none');ylabel(unit);grid on;
end
print(fig,fullfile(folder,'C_independent_repeat_intervals.png'),'-dpng','-r150');close(fig);
end
% 冷进程测试包仅包含公开预测输入、预期输出和Excel位置，不含概率参数。
if ~isempty(pred)
inputs=pred.excelVerificationInputs;inputs.workbook=delivery.workbookFile;
inputs.points=inputs.points(:,{'point_id','Altitude_mean','Mach_mean','Pamb_mean', ...
    'Tamb_mean','Tt1_mean','Mkp_mean','Mkg_mean','Wf_mean'});
inputs.runtime=p.context.replayAssets.configuration.engine.interface.controlDir;
inputs.index=1;
package=sht_f34_deployment('read',inputs.workbook,inputs.runtime);
b=sht_f34_deployment('predictpoints',package,inputs.points,inputs.branch,inputs.index);
assert(b.candidate(1).valid);q=b.candidate(1).prediction;v=[q.Np,q.Ng,q.Pt3,q.Tt45];
inputs.expected=v(:);save(fullfile(p.paths.runDir,'C_excel_verification_inputs.mat'),'inputs');
inputFile=fullfile(p.paths.runDir,'C_independent_prediction_inputs.xlsx');
writetable(inputs.points,inputFile,'Sheet','Inputs');
seed=table(inputs.points.point_id,inputs.branch.speedSeed(:,1),inputs.branch.speedSeed(:,2), ...
    inputs.branch.lowerNp(:),inputs.branch.upperNp(:),'VariableNames', ...
    {'point_id','predicted_Np_seed','predicted_Ng_seed','lower_Np','upper_Np'});
writetable(seed,inputFile,'Sheet','PriorPredictionSeed');
writetable(table(inputs.index,'VariableNames',{'sample_index'}),inputFile,'Sheet','Samples');
end
result=struct('parameterComparison',tab,'physicalParameterComparison',groups, ...
    'trainingOutput',train,'truthComparisonAvailable',all(isfinite(tab.truth_equivalent)), ...
    'truthUsedForInference',false,'shapeRetainedFraction',p.prior.shape.retainedSecondMomentFraction, ...
    'distinctSupportESS',C.distinctSupportWeightESS,'ancestorMassESS',C.ancestorMassESS, ...
    'conditionalCenterAccuracy',centerAccuracy,'conditionalCenterWhitenedRms',sqrt(mean(normalized(:).^2)), ...
    'conditionalCenterWhitenedMax',max(abs(normalized(:))));
save(fullfile(p.paths.runDir,'C_result_analysis.mat'),'result','-v7.3');
end
