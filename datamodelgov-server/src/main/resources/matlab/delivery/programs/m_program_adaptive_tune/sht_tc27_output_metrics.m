function metrics=sht_tc27_output_metrics(prediction,measurement,means,label)
%SHT_TC27_OUTPUT_METRICS 同时报告物理RMSE、设计点百分比及工程尺度NRMS。
names=["Np";"Ng";"Ptb3";"Ttb3";"Pt45";"Tt45";"Pt6";"Tt6";"Wa2"];
spec=sht_tc24_measurement_specification();units=strings(9,1);reference=zeros(9,1);scale=reference;
errorMatrix=zeros(height(measurement),9);suffix='';if means,suffix='_mean';end
for j=1:9
    if names(j)=="Wa2"
        target=measurement.(['Wa1',suffix])-measurement.(['Wb',suffix]);
        units(j)="kg/s";reference(j)=6.75;scale(j)=.20;
    else
        target=measurement.([char(names(j)),suffix]);q=spec.name==names(j);
        units(j)=spec.unit(q);reference(j)=spec.designReference(q);scale(j)=spec.engineeringScale(q);
    end
    errorMatrix(:,j)=prediction.(char(names(j)))-target;
end
rmse=sqrt(mean(errorMatrix.^2,1)).';maxAbs=max(abs(errorMatrix),[],1).';bias=mean(errorMatrix,1).';
validCount=sum(isfinite(errorMatrix),1).';complete=validCount==height(measurement);
% 不能通过丢弃物理无效点得到貌似较好的测试指标。
rmse(~complete)=NaN;maxAbs(~complete)=NaN;bias(~complete)=NaN;
metrics=table(repmat(string(label),9,1),names,units,rmse,maxAbs,bias, ...
    100*rmse./reference,rmse./scale,validCount,repmat(height(measurement),9,1),'VariableNames', ...
    {'case','output','unit','RMSE','maxAbsoluteError','meanError','RMSE_design_pct','engineeringNRMS','validSampleCount','totalSampleCount'});
end
