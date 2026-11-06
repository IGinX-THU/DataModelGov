function profile=sht_tc27_schedule_profile(schedule)
%SHT_TC27_SCHEDULE_PROFILE 将估计曲线转为三部件13张DLL表，不读取造数模板。
indices=[0:3,6:14].';axes={'inlet_corrected_mass_flow','ac_corrected_speed', ...
    'ac_corrected_speed','ac_corrected_speed','burner_inlet_corrected_mass_flow', ...
    'gt_total_pressure_ratio','gt_total_pressure_ratio','gt_total_pressure_ratio', ...
    'gt_pt_duct_corrected_mass_flow','pt_total_pressure_ratio','pt_total_pressure_ratio', ...
    'pt_total_pressure_ratio','pt_nozzle_duct_corrected_mass_flow'};
dictionary=sht_health_parameter_dictionary(0);
template=struct('cIndex',0,'matlabHealthIndex',0,'name','','mode','table1d', ...
    'axisName','','xNodes',[],'deltaNodes',[],'designValue',0,'kNodes',[], ...
    'zeroFlowAnchored',false);
parameters=repmat(template,numel(indices),1);
for j=1:numel(indices)
    c=indices(j);e=find([schedule.healthEntries.cIndex]==c,1);r=template;
    r.cIndex=c;r.matlabHealthIndex=c+1;r.name=char(dictionary.name(dictionary.c_index==c));
    r.axisName=axes{j};r.zeroFlowAnchored=ismember(c,[0,6,10,14]);
    r.designValue=schedule.designHealth(c+1);
    if ~isempty(e)
        r.xNodes=schedule.healthEntries(e).xNodes(:);r.kNodes=schedule.healthEntries(e).kNodes(:);
        r.deltaNodes=r.kNodes-r.designValue;
    else
        r.xNodes=[0;100];r.kNodes=repmat(r.designValue,2,1);r.deltaNodes=zeros(2,1);
    end
    if r.zeroFlowAnchored,r.deltaNodes(1)=-r.designValue;r.kNodes(1)=0;end
    parameters(j)=r;
end
profile=struct('modelMode',0,'parameters',parameters,'scheduledCIndex',indices, ...
    'truthVectorAtDesign',schedule.designHealth(:),'source','TC27 estimated schedule; no truth read');
end
