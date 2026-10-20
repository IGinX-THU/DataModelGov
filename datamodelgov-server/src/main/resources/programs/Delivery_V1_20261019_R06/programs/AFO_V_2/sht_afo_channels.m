function spec = sht_afo_channels
%SHT_AFO_CHANNELS 实际SLX端口字典。向量逐列保存，不把Scope当单个量。
% sid锁定V8_5_R2019b结构；准备时SHA与实际端口同时记录。
spec=struct('id',{},'group',{},'sid',{},'port',{},'names',{},'units',{},'role',{});
add('engine','engine',656,1, ...
    {'Pt1','Tt1','Pt3','Tt3','Pt45','Tt45','Pt5','Tt5','Np','Ng','W2', ...
     'PT_drive_torque','HPC_relative_corrected_speed','GT_pressure_ratio', ...
     'PT_pressure_ratio','gaspath_residual','Pt4','Tt4','GT_HPC_net_torque','converge_tag'}, ...
    {'Pa','K','Pa','K','Pa','K','Pa','K','rpm','rpm','kg/s','N*m','1','1','1','1','Pa','K','N*m','1'}, ...
    'engine_output_not_measured_load');
add('load','control',12224,1,{'Mkp','equivalent_pitch','pitch_factor','Np_ratio','PT_load_power','pitch_in_range'}, ...
    {'N*m','deg','1','1','W','1'},'actual_external_load');
add('fuel_command','fuel',660,1,{'Wf_command'},{'kg/s'},'controller_command');
add('fuel_engine','fuel',1547,1,{'Wf_engine'},{'kg/s'},'engine_adopted_fuel');
add('fuel_detailed','fuel',3568,1,{'Wf_detailed'},{'kg/s'},'detailed_fuel_to_oil_not_engine');
for k=1:10
    if k<=8,n={sprintf('G%02d_external_flow',k)};u={'kg/s'};
    elseif k==9,n={'G04_supply_temperature'};u={'K'};
    else,n={'G04_supply_pressure'};u={'Pa'};end
    add(sprintf('air%02d',k),'air',11534,k,n,u,'external_air_output');
end
add('air_template','air',656,2,airnames('template'),airunits(),'engine_template');
add('air_merge','air',12229,1,airnames('merged'),airunits(),'before_delay');
add('air_adopted','air',10606,1,airnames('delayed'),airunits(),'delayed_boundary_not_active_when_internal');
add('oil_air_temperature','oil',12152,1,{'oil_air_temperature_C'},{'degC'},'mapped_boundary');
add('oil_vent_boundary','oil',12152,2, ...
    {'Paf','Taf','Par','Tar','Pbf','Tbf','Pbr','Tbr','Pvent','Tvent'}, ...
    {'Pa','K','Pa','K','Pa','K','Pa','K','Pa','K'},'mapped_boundary');
oilNames={'甲轴承腔换热量','乙轴承腔换热量','空滑换热量','机匣附件换热量', ...
    '甲轴承腔流量','乙轴承腔流量','甲轴承腔压力','乙轴承腔压力', ...
    '甲轴承腔出口油温','乙轴承腔出口油温','甲腔回油流量','乙腔回油流量', ...
    '甲轴承腔生热量','乙轴承腔生热量','燃滑散热器换热量','燃滑散热器燃油出口温度', ...
    '空滑散热器入口压力','空滑散热器出口压力','燃滑散热器入口压力','燃滑散热器出口压力'};
for k=1:20
    % 轴承原始出口保持K。仅通往混温函数的支路在SLX中减273.15，
    % 因此原始端口单位不变，结果回退标志按换算后的摄氏度判断。
    units={'W','W','W','W','m3/s','m3/s','Pa','Pa','K','K', ...
        'm3/s','m3/s','W','W','W','model_unit_unconfirmed','Pa','Pa','Pa','Pa'};
    u=units{k};
    add(sprintf('oil%02d',k),'oil',11949,k,{oilNames{k}},{u},'oil_output');
end
add('oil21','oil',11949,21,{'甲前压力','甲前温度','甲后压力','甲后温度', ...
    '乙前压力','乙前温度','乙后压力','乙后温度'},repmat({'Pa','K'},1,4),'vent_state');
add('oil22','oil',11949,22,{'甲前封严','甲后封严','乙前封严','乙后封严'},repmat({'kg/s'},1,4),'vent_flow');
add('oil23','oil',11949,23,{'甲排气','乙排气','总排气'},repmat({'kg/s'},1,3),'vent_flow');
add('oil24','oil',11949,24,{'甲前压差','甲后压差','乙前压差','乙后压差'},repmat({'Pa'},1,4),'vent_pressure');
add('oil25','oil',11949,25,{'甲排气压差','乙排气压差'},{'Pa','Pa'},'vent_pressure');
add('oil26','oil',11949,26,{'甲质量残差','乙质量残差'},{'kg/s','kg/s'},'mass_balance');
add('oil27','oil',11949,27,{'燃滑出口油温','燃滑散热量'},{'degC','kW'},'cooler_output');
add('oil28','oil',11949,28,{'空滑出口油温','空滑散热量'},{'degC','kW'},'cooler_output');
    function add(id,group,sid,port,n,u,role)
        spec(end+1)=struct('id',id,'group',group,'sid',sid,'port',port, ...
            'names',{n},'units',{u},'role',role);
    end
end
function n=airnames(prefix)
n=cell(1,50);v={'W','h','Tt','Pt','FAR'};
for k=1:10,for j=1:5,n{(k-1)*5+j}=sprintf('%s_%02d_%s',prefix,k,v{j});end,end
end
function u=airunits,u=repmat({'kg/s','model_enthalpy_unit','K','Pa','1'},1,10);end
