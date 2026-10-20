function result=sht_tc27_validate_parameters(result,prepared,directory,makePlot)
%SHT_TC27_VALIDATE_PARAMETERS 冻结后隔离读取造数真值，比较全部11+1类型。
% 发动机曲线在相同物理横坐标处比较函数值，不把不同模型坐标上的K
% 差异误称为参数误差。燃油单位kg/s，单独给出RMSE，不混入健康RMSE。
p=sht_tc27_paths();file=fullfile(p.middle,'tc27_train_validation.mat');
if ~isfile(file)
    result.parameterValidation=struct('available',false,'reason','hidden_truth_not_available');
    return;
end
a=load(file,'output');truth=a.output;
parameters=result.parameterDefinition;
schedules={result.upstreamSchedule,result.stageC.schedule, ...
    sht_steady_model_adapt_v2_common('m3nodestoschedule',result.nodeContract,result.D0.x),result.finalSchedule};
labels={'TC24','C','D0','D1'};rows=table();detail=cell(height(parameters)+1,1);
for j=1:height(parameters)
    c=parameters.c_index(j);q=find([truth.profile.parameters.cIndex]==c,1);tp=truth.profile.parameters(q);
    if c==15,x=0;actual=truth.profile.truthVectorAtDesign(16);axisName='constant';
    else
        e=result.upstreamSchedule.healthEntries([result.upstreamSchedule.healthEntries.cIndex]==c);
        axisName=e.axisName;x=result.baseline.coordinates.(axisName);
        actual=local_truth(tp,x);
    end
    values=zeros(numel(x),4);
    for k=1:4
        if c==15,v=repmat(schedules{k}.h15,size(x));else
            e=schedules{k}.healthEntries([schedules{k}.healthEntries.cIndex]==c);v=local_interp(e.xNodes,e.kNodes,x);
        end
        values(:,k)=v;
    end
    rmse=sqrt(mean((values-actual).^2,1));
    rows=[rows;table(c,string(parameters.name(j)),"1",mean(actual),mean(values(:,1)), ...
        mean(values(:,2)),mean(values(:,3)),mean(values(:,4)),rmse(1),rmse(2),rmse(3),rmse(4), ...
        'VariableNames',{'hIndex','parameter','unit','truthMean','TC24','C','D0','D1', ...
        'TC24_RMSE','C_RMSE','D0_RMSE','D1_RMSE'})]; %#ok<AGROW>
    detail{j}=struct('coordinate',x,'axisName',axisName,'truth',actual,'estimates',values);
end
time=truth.measurement.Time_s;wf=truth.measurement.Wf;
actual=interp1(truth.simulation.time,truth.validation.bias.Wf,time,'linear');values=zeros(numel(wf),4);
for k=1:4,f=schedules{k}.fuelBias;values(:,k)=local_interp(f.xNodes,f.biasNodes,wf/f.wfDesign);end
rmse=sqrt(mean((values-actual).^2,1));
rows=[rows;table(-1,"Wf_bias","kg/s",mean(actual),mean(values(:,1)),mean(values(:,2)), ...
    mean(values(:,3)),mean(values(:,4)),rmse(1),rmse(2),rmse(3),rmse(4),'VariableNames',rows.Properties.VariableNames)];
detail{end}=struct('coordinate',wf/result.finalSchedule.fuelBias.wfDesign, ...
    'axisName','measured Wf / reference Wf','truth',actual,'estimates',values);
disp(rows);writetable(rows,fullfile(directory,'all_parameter_comparison.csv'));
result.parameterValidation=struct('table',rows,'detail',{detail}, ...
    'healthComparison','function_values_at_common_physical_coordinates', ...
    'fuelComparison','actual_full_training_measurement_coordinates', ...
    'healthRMSE',sqrt(mean(rows{1:end-1,{'TC24_RMSE','C_RMSE','D0_RMSE','D1_RMSE'}}.^2,1)), ...
    'fuelBiasRMSE_kg_s',rmse,'hiddenTruthReadAfterFit',true);
if makePlot
    fig=figure('Name',[result.runId,' parameters'],'Position',[40,40,1400,1000]);
    for j=1:numel(detail)
        subplot(4,3,j);d=detail{j};[x,order]=sort(d.coordinate);
        if numel(x)==1
            % 常值参数只有一个坐标，单点折线本身不可见，必须显式给标记。
            plot(x,d.truth(order),'ko','LineWidth',1.4);hold on;
            plot(x,d.estimates(order,1),'bs');plot(x,d.estimates(order,4),'rx');
        else
            plot(x,d.truth(order),'k-','LineWidth',1.4);hold on;
            plot(x,d.estimates(order,1),'b--');plot(x,d.estimates(order,4),'r-');
        end
        title(char(rows.parameter(j)),'Interpreter','none');xlabel(d.axisName,'Interpreter','none');ylabel(char(rows.unit(j)));grid on;
    end
    legend('Truth','TC24','TC27');print(fig,fullfile(directory,'all_parameter_curves.png'),'-dpng','-r140');
end
end
function v=local_truth(p,x)
if strcmp(p.mode,'constant'),v=repmat(p.designValue,size(x));
else,v=p.designValue+local_interp(p.xNodes,p.deltaNodes,x);end
end
function y=local_interp(x,v,q)
if numel(x)==1,y=repmat(v,size(q));else,y=interp1(x,v,min(max(q,x(1)),x(end)),'linear');end
end
