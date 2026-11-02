function data=sht_tc24_validate_measurements(file)
% 当前台架合同的入口量纲/物理检查。只读测量Excel，不读取误差真值。
% 压力单位Pa、温度K、质量流量kg/s；这些宽松范围用于识别常见单位错误，
% 不是新的发动机工作包线。其他发动机或极端环境应显式审查后调整。
data=sht_steady_model_adapt_v2_common('readmeasurementtable',file,'TC24测量Excel');
sht_measurement_mean_sample_count(data); % 新正式接口不得继承旧的固定计数
pressure={'Pt1_mean','Ptb3_mean','Pt45_mean','Pt6_mean','Pamb_mean'};
temperature={'Tt1_mean','Ttb3_mean','Tt45_mean','Tt6_mean','Tamb_mean'};
for i=1:numel(pressure)
    value=data.(pressure{i});
    assert(all(value>1e3 & value<1e8),'TC24:Measurement:PressureUnits', ...
        '%s应为Pa；当前台架检查范围1e3～1e8Pa，请检查是否误用kPa或MPa。',pressure{i});
end
for i=1:numel(temperature)
    value=data.(temperature{i});
    assert(all(value>100 & value<3000),'TC24:Measurement:TemperatureUnits', ...
        '%s应为K，请检查是否误用摄氏度。',temperature{i});
end
assert(all(data.Wf_mean>0 & data.Np_mean>0 & data.Ng_mean>0 & data.Mkp_mean>=0), ...
    'TC24:Measurement:PhysicalInput','稳态燃油/转速须为正，负载扭矩须非负。');
assert(all(data.Wa1_mean>0 & data.Wb_mean>=0 & data.Wb_mean<data.Wa1_mean), ...
    'TC24:Measurement:FlowBalance','必须满足0<=Wb<Wa1，以形成正的发动机进口流量。');
end
