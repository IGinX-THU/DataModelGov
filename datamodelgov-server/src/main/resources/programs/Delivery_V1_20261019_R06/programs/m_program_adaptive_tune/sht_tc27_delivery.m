function result=sht_tc27_delivery(action,input,file)
%SHT_TC27_DELIVERY TC27唯一正式Excel载荷，不含Jacobian、真值或训练记录。
% MAT仅供续算/诊断；read在没有任何估计MAT的情况下恢复同一调度。
if strcmp(action,'write')
    % 同一冻结结果重复验证时，不因Excel ZIP时间戳改变下游输入身份。
    % 实际曲线、边界选根或路线变化时仍必须重新发布。
    if isfile(file)
        try
            existing=sht_tc27_delivery('read',[],file);
            if strcmp(existing.runId,input.runId)&&strcmp(existing.route,input.route)&& ...
                    strcmp(existing.method,input.method)&&existing.thermalMode==input.thermalMode&& ...
                    isequaln(existing.npBranchModel,input.npBranchModel)&& ...
                    local_same_schedule(existing.finalSchedule,input.finalSchedule)
                result=existing;return;
            end
        catch failure
            warning('TC27:Delivery:Rebuild','已有同名Excel未能通过完整读回：%s。将写入本次完整结果。',failure.message);
        end
    end
    % 新工作簿完整写入并读回验证后发布，防止旧工作表的多余行残留。
    publishFile=file;file=[tempname(fileparts(file)),'.xlsx'];
    r=input;s=r.finalSchedule;rows=table();
    for j=1:numel(s.healthEntries)
        e=s.healthEntries(j);n=numel(e.xNodes);
        rows=[rows;table(repmat(e.cIndex,n,1),repmat(string(e.name),n,1), ...
            repmat(string(e.axisName),n,1),(1:n).',e.xNodes,e.kNodes, ...
            repmat(e.designCoordinate,n,1),repmat(logical(e.pressureLoss),n,1), ...
            'VariableNames',{'c_index','name','axis_name','node_index','coordinate','value','design_coordinate','pressure_loss'})]; %#ok<AGROW>
    end
    rows=[rows;table(15,"Nozzle_K_A8","constant",1,0,s.h15,0,false, ...
        'VariableNames',rows.Properties.VariableNames)];
    fuel=s.fuelBias;n=numel(fuel.xNodes);
    bias=table((1:n).',fuel.xNodes,fuel.biasNodes,repmat(fuel.wfDesign,n,1), ...
        'VariableNames',{'node_index','measured_fuel_ratio','bias_kg_s','reference_fuel_kg_s'});
    manifest=table("SHT_TC27_DETERMINISTIC_EXCEL_V1",string(r.runId), ...
        string(r.route),string(r.method),0,1,r.thermalMode,"linear","clamp", ...
        false,'VariableNames',{'schema','run_id','route','method','model_mode', ...
        'inlet_mode','thermal_mode','interpolation','endpoint_policy','convergence_is_delivery_gate'});
    writetable(manifest,file,'Sheet','Manifest');writetable(rows,file,'Sheet','CorrectionSchedule');
    writetable(bias,file,'Sheet','MeasurementBias');writetable(r.npBranchModel,file,'Sheet','NpBranchModel');
    result=sht_tc27_delivery('read',[],file);
    for j=1:numel(s.healthEntries)
        assert(max(abs(s.healthEntries(j).xNodes-result.finalSchedule.healthEntries(j).xNodes))<1e-12, ...
            'Excel节点横坐标往返不一致。');
        assert(max(abs(s.healthEntries(j).kNodes-result.finalSchedule.healthEntries(j).kNodes))<1e-14, ...
            'Excel节点纵坐标往返不一致。');
    end
    assert(max(abs(fuel.biasNodes-result.finalSchedule.fuelBias.biasNodes))<1e-14,'燃油节点往返失败。');
    assert(abs(s.h15-result.finalSchedule.h15)<1e-14,'常值喷口系数往返失败。');
    movefile(file,publishFile,'f');result.file=publishFile;
    return;
end

assert(strcmp(action,'read'),'未知正式交付操作。');
m=readtable(file,'Sheet','Manifest');t=readtable(file,'Sheet','CorrectionSchedule');b=readtable(file,'Sheet','MeasurementBias');
assert(string(m.schema)=="SHT_TC27_DETERMINISTIC_EXCEL_V1"&&m.model_mode==0&&m.inlet_mode==1,'不兼容的TC27 Excel合同。');
assert(string(m.interpolation)=="linear"&&string(m.endpoint_policy)=="clamp",'调度插值合同不一致。');
assert(all(isfinite(t.coordinate))&&all(isfinite(t.value))&& ...
    all(isfinite(b.measured_fuel_ratio))&&all(isfinite(b.bias_kg_s)), '正式Excel包含非有限节点。');
assert(nnz(t.c_index==15)==1&&height(b)>0&&all(b.reference_fuel_kg_s>0), '常值/燃油合同不完整。');
entries=struct([]);
for c=unique(t.c_index(t.c_index~=15),'stable').'
    use=t.c_index==c;q=t(use,:);[~,order]=sort(q.node_index);q=q(order,:);
    assert(all(diff(q.coordinate)>0)||height(q)==1,'调度横坐标必须严格递增。');
    e=struct('cIndex',c,'name',char(string(q.name(1))),'axisName',char(string(q.axis_name(1))), ...
        'pressureLoss',logical(q.pressure_loss(1)),'xNodes',q.coordinate,'kNodes',q.value, ...
        'designCoordinate',q.design_coordinate(1),'designValue',0, ...
        'xNodesDll',q.coordinate,'kNodesDll',q.value,'deltaNodesDll',q.value,'dllResamplingUsed',false);
    entries=[entries;e]; %#ok<AGROW>
end
[~,order]=sort(b.node_index);b=b(order,:);
assert(all(diff(b.measured_fuel_ratio)>0)||height(b)==1,'燃油偏置横坐标必须严格递增。');
s=struct('healthEntries',entries,'h15',t.value(t.c_index==15), ...
    'fuelBias',struct('xNodes',b.measured_fuel_ratio,'biasNodes',b.bias_kg_s,'wfDesign',b.reference_fuel_kg_s(1)));
s=sht_tc27_schedule('refresh',s);
result=struct('runId',char(string(m.run_id)),'route',char(string(m.route)), ...
    'method',char(string(m.method)),'modelMode',0,'thermalMode',m.thermal_mode, ...
    'finalSchedule',s,'npBranchModel',readtable(file,'Sheet','NpBranchModel'), ...
    'file',file,'sha256',sht_tc27_file_identity(file),'internalMatRead',false);
end

function same=local_same_schedule(a,b)
same=numel(a.healthEntries)==numel(b.healthEntries)&&local_equal(a.h15,b.h15)&& ...
    local_equal(a.fuelBias.xNodes,b.fuelBias.xNodes)&& ...
    local_equal(a.fuelBias.biasNodes,b.fuelBias.biasNodes)&&local_equal(a.fuelBias.wfDesign,b.fuelBias.wfDesign);
if ~same,return;end
for j=1:numel(a.healthEntries)
    x=a.healthEntries(j);y=b.healthEntries(j);
    same=x.cIndex==y.cIndex&&strcmp(x.name,y.name)&&strcmp(x.axisName,y.axisName)&& ...
        x.pressureLoss==y.pressureLoss&&local_equal(x.designCoordinate,y.designCoordinate)&& ...
        local_equal(x.xNodes,y.xNodes)&&local_equal(x.kNodes,y.kNodes);
    if ~same,return;end
end
end

function same=local_equal(a,b)
same=isequal(size(a),size(b))&&all(isfinite(a(:)))&&all(isfinite(b(:)))&& ...
    all(abs(a(:)-b(:))<=1e-13*max(1,max(abs(a(:)),abs(b(:)))));
end
