function summary=sht_stage4_report(user)
% 4step5：估计冻结后的结果汇总。只有本程序允许读取独立造数真值。
c=sht_stage4_config(user);plan=sht_stage4_guard('report',c);sc=sht_stage4_scenarios();
if ~isfolder(plan.reportRoot),mkdir(plan.reportRoot);end
status=table();parameters=table();metrics=table();design=table();intervals=table();
historicalUQ=table();
for i=1:numel(sc)
    q=sc(i);modelRecord=fullfile(c.middle,q.id,'stage4_model_record.mat');
    if ~ismember(q.id,plan.ids),continue;end
    if ~isfile(modelRecord),continue;end
    s=load(modelRecord,'record');rec=s.record;
    assert(strcmp(rec.modelSha,sht_tc27_file_identity(rec.modelFile))&& ...
        strcmp(rec.resultSha,sht_tc27_file_identity(rec.resultFile)),'已冻结估计结果发生变化。');
    r0=load(rec.resultFile,'result');r=r0.result;
    % 纯报告只检查保存模型的完整合同；重新求值仍由预测/续算入口核运行包。
    delivered=sht_f33_excel_delivery('inspect',rec.modelFile);
    if rec.historical && ~isempty(rec.uqFile)
        inheritedD=sht_f34_method_d_artifacts('inspect',rec.uqFile);
        rec.uqQuality=['historical/',inheritedD.distribution.qualityLevel];
        a=inheritedD.runtimeAssets;
        dll=string(a.sha256(string(a.file)=="GTESS.dll"));
        assert(numel(dll)==1,'SHT:Stage4:HistoricalUQ','历史D缺少唯一DLL身份。');
        historicalUQ=[historicalUQ;table(string(q.id),string(rec.uqFile), ...
            string(rec.uqSha),dll,string(inheritedD.manifest.run_id(1)), ...
            string(inheritedD.distribution.qualityLevel),false,false, ...
            'VariableNames',{'sortie','source_workbook','source_sha256','source_dll_sha256', ...
            'source_run_id','quality_level','recomputed_with_current_runtime','runtime_verified'})]; %#ok<AGROW>
    end
    dataFile=fullfile(c.middle,q.id,'stage4_data_record.mat');gen=0;total=0;truth=[];
    if isfile(dataFile)
        s=load(dataFile,'record');dr=s.record;gen=dr.generationRuntime_s;total=dr.totalRuntime_s;
        if ~isempty(dr.truthFile)
            a=load(dr.truthFile,'validationData');truth=a.validationData;
        end
    end
    if q.reuse&&strcmp(c.inputMode,'synthetic_demo')
        a=sht_f3_three_component_assets('paths');
        tf=fullfile(a.generation,'formal_R011','flight_data_3p1_validation_truth.mat');
        if isfile(tf),a=load(tf,'validationData');truth=a.validationData;end
    end
    p=r.parameterTable;p.sortie=repmat(string(q.id),height(p),1);
    p.absolute_estimate=nan(height(p),1);p.truth_at_coordinate=nan(height(p),1);
    for j=1:height(p)
        id=char(p.parameter_id(j));ci=p.c_index(j);
        if strncmp(id,'Wf_bias',7)
            p.absolute_estimate(j)=local_interp(r.finalSchedule.fuelBias.xNodes, ...
                r.finalSchedule.fuelBias.biasNodes,p.x_node(j));
            if ~isempty(truth)
                f=truth.runs(1).measurementModel.fuelBiasSchedule;
                fuelQuery=p.x_node(j)*r.finalSchedule.fuelBias.wfDesign/f.wfDesign;
                p.truth_at_coordinate(j)=local_interp(f.xNodes,f.biasNodes,fuelQuery);
            end
        elseif strcmp(id,'K_dist_eq')
            p.absolute_estimate(j)=r.estimatedKdistEq;
            if ~isempty(truth),p.truth_at_coordinate(j)=mean(truth.runs(1).truthTable.K_dist_eq);end
        elseif isfinite(ci)&&ci>=0
            e=r.finalSchedule.healthEntries([r.finalSchedule.healthEntries.cIndex]==ci);
            if ~isempty(e),p.absolute_estimate(j)=local_interp(e.xNodes,e.kNodes,p.x_node(j));end
            if ~isempty(truth)
                tp=truth.truthHealthScheduleProfile.parameters;
                f=tp([tp.cIndex]==ci);
                if ~isempty(f),p.truth_at_coordinate(j)=local_interp(f.xNodes,f.kNodes,p.x_node(j));end
            end
        end
    end
    p.error_to_truth=p.absolute_estimate-p.truth_at_coordinate;
    parameters=[parameters;p]; %#ok<AGROW>
    m=r.metricTable;m.sortie=repmat(string(q.id),height(m),1);metrics=[metrics;m]; %#ok<AGROW>
    status=[status;table(string(q.id),string(q.parent),q.order,rec.historical, ...
        rec.steadyWindowCount,rec.parameterCount,rec.converged,string(rec.stopReason), ...
        r.priorObjective,r.finalObjective,gen,total,rec.fitRuntime_s,rec.uqRuntime_s,string(rec.uqQuality), ...
        'VariableNames',{'sortie','parent','order','historical','steady_windows','parameters', ...
        'converged','stop_reason','prior_objective','final_objective','generation_s', ...
        'data_total_s','fit_s','uq_s','uq_quality'})]; %#ok<AGROW>
    for ci=[1,2,7,8,10,11,12]
        tv=NaN;if ~isempty(truth),tv=truth.truthHealth(ci+1);end
        design=[design;table(string(q.id),q.order,ci,delivered.schedule.designHealth(ci+1),tv, ...
            'VariableNames',{'sortie','order','c_index','estimate','truth'})]; %#ok<AGROW>
    end
    dfile=fullfile(c.report,q.id,'uq_D','D_physical_node_intervals.csv');
    if isfile(dfile)
        d=readtable(dfile);d.sortie=repmat(string(q.id),height(d),1);
        d.truth_at_coordinate=nan(height(d),1);
        if ~isempty(truth)
            tp=truth.truthHealthScheduleProfile.parameters;
            for k=1:height(d)
                if string(d.kind(k))=="fuel_bias"
                    f=truth.runs(1).measurementModel.fuelBiasSchedule;
                    x=d.coordinate(k)*r.finalSchedule.fuelBias.wfDesign/f.wfDesign;
                    d.truth_at_coordinate(k)=local_interp(f.xNodes,f.biasNodes,x);
                elseif string(d.kind(k))=="health_constant"
                    d.truth_at_coordinate(k)=truth.truthHealth(d.c_index(k)+1);
                else
                    f=tp([tp.cIndex]==d.c_index(k));
                    if ~isempty(f)
                        d.truth_at_coordinate(k)=local_interp(f.xNodes,f.kNodes,d.coordinate(k));
                    end
                end
            end
        end
        d.error_to_truth=d.mean_local-d.truth_at_coordinate;
        d.truth_inside_local_interval=double(d.truth_at_coordinate>=d.lower95_local & ...
            d.truth_at_coordinate<=d.upper95_local);
        d.truth_inside_local_interval(~isfinite(d.truth_at_coordinate))=NaN;
        intervals=[intervals;d]; %#ok<AGROW>
    end
end
file=fullfile(plan.reportRoot,'stage4_results.xlsx');
if ~isempty(status)
    writetable(status,file,'Sheet','Status');writetable(parameters,file,'Sheet','AllEstimatedParameters');
    writetable(metrics,file,'Sheet','SteadyPointFit');writetable(design,file,'Sheet','DesignHealth');
end
if ~isempty(intervals),writetable(intervals,file,'Sheet','DPhysicalIntervals');end
if ~isempty(historicalUQ),writetable(historicalUQ,file,'Sheet','HistoricalUQSource');end
changes=table();
if ~isempty(design)
for target={'F05_N','F05_HPC','F05_GT','F05_PT'}
    reference='F05_N';if strcmp(target{1},'F05_N'),reference='F01';end
    for ci=[1,2,7,8,11,12]
        a=design(design.sortie==target{1}&design.c_index==ci,:);
        b=design(design.sortie==reference&design.c_index==ci,:);
        if isempty(a)||isempty(b),continue;end
        changes=[changes;table(string(target{1}),string(reference),ci, ...
            100*(a.estimate-b.estimate),100*(a.truth-b.truth), ...
            'VariableNames',{'sortie','reference','c_index','estimated_change_pp','true_change_pp'})]; %#ok<AGROW>
    end
end
end
if ~isempty(changes),writetable(changes,file,'Sheet','HealthChanges');end
predictionFile=plan.predictionFile;prediction=[];predictionStatus='NOT_EXECUTED';validated=false;
if isfile(predictionFile)
    s=load(predictionFile,'result');prediction=s.result;
    predictionStatus=prediction.status;validated=prediction.validationPerformed;
    if ~isempty(prediction.summary),writetable(prediction.summary,file,'Sheet','FullHistory');end
    if ~isempty(prediction.frozen.nodes),writetable(prediction.frozen.nodes,file,'Sheet','F06Trend');end
end
execution=table(string(strjoin(plan.ids,',')),string(predictionStatus),validated,false, ...
    'VariableNames',{'selected_scenarios','prediction_status','replay_performed','independent_test_available'});
writetable(execution,file,'Sheet','ExecutionScope');
figures={};
if c.plotEnabled&&~isempty(status)
    plotConfig=c;plotConfig.report=plan.reportRoot;
    figures=local_plots(plotConfig,design,metrics,prediction);
end
summary=struct('status',status,'parameters',parameters,'metrics',metrics,'designHealth',design,'healthChanges',changes,'intervals',intervals, ...
    'workbook',file,'figures',{figures},'reportFile',fullfile(plan.reportRoot,'第4阶段首轮执行结果与分析.md'), ...
    'execution',execution,'historicalUQ',historicalUQ, ...
    'truthUsedOnlyAfterEstimation',true,'independentFlightTestAvailable',false);
local_markdown(summary,prediction);
save(plan.reportMat,'summary','-v7.3');
disp(status);fprintf('Stage4 report: %s\n',summary.reportFile);
end

function files=local_plots(c,d,m,p)
files={};normal={'F01','F02','F03','F04','F05_N'};selected=ismember(d.sortie,string(normal));
f=figure('Visible','off','Color','w','Position',[100 100 1350 800]);
for j=1:6
    ids=[1,2,7,8,11,12];z=d(selected&d.c_index==ids(j),:);[~,o]=sort(z.order);z=z(o,:);
    subplot(2,3,j);plot(z.order,100*z.estimate,'o-','LineWidth',1.4);hold on;
    plot(z.order,100*z.truth,'s--','LineWidth',1.4);grid on;xlabel('Sortie');ylabel('K (%)');
    title(sprintf('h%d at design coordinate',ids(j)));legend('Estimate','Synthetic truth','Location','best');
end
files{end+1}=fullfile(c.report,'normal_health_trend.png');print(f,files{end},'-dpng','-r160');close(f);
f=figure('Visible','off','Color','w','Position',[100 100 1350 760]);
channels=unique(m.channel,'stable');sorties=unique(m.sortie,'stable');
for j=1:numel(channels)
    subplot(2,2,j);values=nan(numel(sorties),2);
    for i=1:numel(sorties)
        for k=1:2
            label={'prior','estimated'};row=m.sortie==sorties(i)&m.channel==channels(j)&m.model==label{k};
            if any(row),values(i,k)=m.rmse(find(row,1));end
        end
    end
    bar(values);grid on;set(gca,'XTick',1:numel(sorties),'XTickLabel',cellstr(sorties),'XTickLabelRotation',30);
    title(char(channels(j)),'Interpreter','none');ylabel(char(m.unit(find(m.channel==channels(j),1))));
    legend('Reference','Updated','Location','best');
end
files{end+1}=fullfile(c.report,'steady_point_fit.png');print(f,files{end},'-dpng','-r160');close(f);
if ~isempty(p)&&~isempty(p.summary)&&any(p.summary.sortie=="F06")
    s=p.summary(p.summary.sortie=="F06",:);f=figure('Visible','off','Color','w','Position',[100 100 1300 760]);
    channels=unique(s.channel,'stable');
    for j=1:4
        subplot(2,2,j);z=s(s.channel==channels(j),:);bar(z.rmse);grid on;
        set(gca,'XTick',1:height(z),'XTickLabel',cellstr(z.model));ylabel(char(z.unit(1)));title(char(channels(j)),'Interpreter','none');
    end
    files{end+1}=fullfile(c.report,'F06_prediction_comparison.png');print(f,files{end},'-dpng','-r160');close(f);
    % 只画F06，完整数组从物理缓存恢复，不再次调用DLL。
    f=figure('Visible','off','Color','w','Position',[100 100 1350 860]);
    labels={'hold','trend'};palette=lines(2);
    for i=1:2
        r=p.replays(strcmp({p.replays.sortie},'F06')&strcmp({p.replays.model},labels{i}));
        if isempty(r),continue;end
        a=load(r.cacheFile,'cacheRecord');v=a.cacheRecord.replay;
        for j=1:4
            subplot(2,2,j);hold on;
            if i==1,plot(v.time_s,v.measuredOutput(:,j),'Color',[.6 .6 .6]);end
            plot(v.time_s,v.sensorExpectedOutput(:,j),'Color',palette(i,:),'LineWidth',1);
            grid on;xlabel('Time (s)');ylabel(v.outputUnits{j});title(v.outputNames{j},'Interpreter','none');
            if i==2,legend('Measured','Hold','Trend','Location','best');end
        end
    end
    files{end+1}=fullfile(c.report,'F06_output_histories.png');print(f,files{end},'-dpng','-r160');close(f);
end
end

function local_markdown(s,p)
fid=fopen(s.reportFile,'w','n','UTF-8');assert(fid>=0);closer=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'# 第4阶段首轮执行结果与分析\n\n生成时间：%s。运行环境：MATLAB %s。\n\n',datestr(now,31),version('-release'));
fprintf(fid,'本次范围：%s。预测状态：%s。已执行回放：%d；独立飞参测试集：无。未执行/缺失数据不代表验证通过。\n\n', ...
    char(s.execution.selected_scenarios),char(s.execution.prediction_status),s.execution.replay_performed);
fprintf(fid,'## 1. 结果范围\n\n本轮调用现行2至3阶段接口，以瞬态时刻模型辨识飞参稳态窗口；瞬态系数固定，增强热效应保留。F01复用原结果，其余为本批计算。D为独立条件局部初评，不是全局后验或跨架次后验递推。没有独立飞参测试集，点误差属于拟合。\n\n');
fprintf(fid,'| 架次 | 稳态窗口 | 参数数 | 收敛 | 造数/s | 辨识/s | D/s |\n|---|---:|---:|---|---:|---:|---:|\n');
for i=1:height(s.status)
    a=s.status(i,:);fprintf(fid,'| %s | %d | %d | %d | %.1f | %.1f | %.1f |\n', ...
        char(a.sortie),a.steady_windows,a.parameters,a.converged,a.generation_s,a.fit_s,a.uq_s);
end
fprintf(fid,'\n## 2. 稳态窗口输出\n\nPt3_eq与Tt45是测量输出，dNp/dt与dNg/dt是稳态时刻的零导数约束；不能把后两项误称为转速预测误差。下表均为原单位RMSE。\n\n');
fprintf(fid,'| 架次 | 输出 | 单位 | 更新前 | 更新后 |\n|---|---|---|---:|---:|\n');
for i=1:height(s.metrics)
    a=s.metrics(i,:);if a.model~="estimated",continue;end
    b=s.metrics(s.metrics.sortie==a.sortie&s.metrics.channel==a.channel&s.metrics.model=="prior",:);
    fprintf(fid,'| %s | %s | %s | %.7g | %.7g |\n',char(a.sortie),char(a.channel),char(a.unit),b.rmse,a.rmse);
end
fprintf(fid,'\n## 3. 全部参数与区间\n\n完整节点参数、绝对估计值、冻结后的真值比较、燃油偏置kg/s和Kdist见stage4_results.xlsx。原算法parameterTable中的estimate为相对父曲线的增量；新增absolute_estimate才是实际曲线值，不能混用。设计点比较只是固定参考坐标，不代表所有节点被本架次测量覆盖。D节点表是条件局部95%%区间，不等于实机校准覆盖率。\n\n');
fprintf(fid,'### 3.1 参数数量与数据约束\n\n每个稳态窗口提供Pt3_eq、Tt45和两轴零导数四个约束。新架次若提取6个窗口，即24个标量约束；本批节点路线释放约32个显式参数。因此正则化和上游先验对解有实际影响，不能由残差变小说明每个节点已被独立识别。D还保留条件形状方向，不额外凭空增加测量信息。\n\n');
fprintf(fid,'### 3.2 D实际状态\n\n下表原样保留算法质量标签。NONSTATIONARY表示尚未确认局部驻点，仍可提供初评和诊断，但不能将其区间当作已充分校准的后验可信区间。\n\n| 架次 | D质量 |\n|---|---|\n');
for i=1:height(s.status)
    fprintf(fid,'| %s | %s |\n',char(s.status.sortie(i)),char(s.status.uq_quality(i)));
end
fprintf(fid,'\n');
if ~isempty(s.historicalUQ)
    fprintf(fid,'### 3.3 历史D来源\n\n历史D仅从原Excel只读恢复，未用当前DLL重算，未授予跨包续算或预测资格。生成批次与DLL如下；完整路径及SHA见HistoricalUQSource表。\n\n| 架次 | 原批次 | 原DLL SHA256 |\n|---|---|---|\n');
    for i=1:height(s.historicalUQ)
        a=s.historicalUQ(i,:);fprintf(fid,'| %s | %s | %s |\n', ...
            char(a.sortie),char(a.source_run_id),char(a.source_dll_sha256));
    end
    fprintf(fid,'\n');
end
if ~isempty(s.intervals)
    fprintf(fid,'固定合成真值在物理节点局部区间中的计数如下。这是本例的事后诊断，不是重复试验覆盖率，更不能据此调整本批先验或区间。\n\n| 架次 | 有真值节点 | 落入局部区间节点 |\n|---|---:|---:|\n');
    ids=unique(s.intervals.sortie,'stable');
    for i=1:numel(ids)
        d=s.intervals(s.intervals.sortie==ids(i),:);valid=isfinite(d.truth_inside_local_interval);
        fprintf(fid,'| %s | %d | %d |\n',char(ids(i)),nnz(valid),sum(d.truth_inside_local_interval(valid)));
    end
    fprintf(fid,'\n');
end
fprintf(fid,'## 4. 下一架次及故障评价\n\nF05四场景均从F04独立更新，故障发生于架次前；F06趋势仅采用正常历史。保持/趋势模型均在未来输出评价前冻结，燃油偏置与瞬态系数保持相同。\n\n');
fprintf(fid,'设计参考坐标的健康变化如下，pp表示修正系数的百分点。故障与同架次正常情况对照，正常累计退化与F01对照；并非所有设计坐标都被飞参直接覆盖。\n\n');
fprintf(fid,'| 架次 | 对照 | 系数 | 估计变化/pp | 真值变化/pp |\n|---|---|---|---:|---:|\n');
for i=1:height(s.healthChanges)
    a=s.healthChanges(i,:);fprintf(fid,'| %s | %s | h%d | %.5f | %.5f |\n', ...
        char(a.sortie),char(a.reference),a.c_index,a.estimated_change_pp,a.true_change_pp);
end
if ~isempty(p)
    fprintf(fid,'| 架次 | 模型 | 输出 | 单位 | RMSE | 平均误差 |\n|---|---|---|---|---:|---:|\n');
    for i=1:height(p.summary)
        a=p.summary(i,:);fprintf(fid,'| %s | %s | %s | %s | %.7g | %.7g |\n', ...
            char(a.sortie),char(a.model),char(a.channel),char(a.unit),a.rmse,a.mean_error);
    end
end
fprintf(fid,'\n## 5. 工程解释与限制\n\n小幅退化与单架次偏置、固定热模型失配及多参数补偿可能混合。拟合改善并不能保证每个参数接近真值，参数趋势也不必然改善每个输出。应分别阅读全部节点、D区间和F06物理误差。当前结果不能用于真实故障概率或维修放行。TC27/F3造数热配置差异仍未在本轮解决。\n\n');
for i=1:numel(s.figures),[~,name,ext]=fileparts(s.figures{i});fprintf(fid,'![%s](%s%s)\n\n',name,name,ext);end
end

function value=local_interp(x,y,q)
x=x(:);y=y(:);value=interp1(x,y,min(max(q,x(1)),x(end)),'linear');
end
