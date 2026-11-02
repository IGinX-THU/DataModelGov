function varargout = sht_np_branch_delivery(action, varargin)
%SHT_NP_BRANCH_DELIVERY 正式Excel内的独立Np选根模型，不含原训练记录。
% build仅在导出端读取训练观测；query只读小表与本次边界。
switch action
    case 'build'
        varargout{1} = local_build(varargin{:});
    case 'query'
        [varargout{1:nargout}] = local_query(varargin{:});
    otherwise
        error('SHT:NpDelivery:Action','未知Np交付动作：%s。',action);
end
end

function tbl = local_build(result)
data = sht_steady_model_adapt_v2_common('readmeasurementtable', ...
    result.input.trainingFile,'导出Np分支模型的训练观测');
fuel = result.finalSchedule.fuelBias;
x = min(max(data.Wf_mean/fuel.wfDesign,min(fuel.xNodes)),max(fuel.xNodes));
if numel(fuel.xNodes)==1
    bias=repmat(fuel.biasNodes,height(data),1);
else
    bias=interp1(fuel.xNodes,fuel.biasNodes,x,'linear');
end
data.Wf_mean = data.Wf_mean-bias;
reference=table(string(data.point_id),data.Np_mean, ...
    'VariableNames',{'point_id','Np_ref_rpm'});
prior=sht_steady_np_branch_prior(data,data,reference, ...
    result.options.steadyNpBranchPriorOptions);
nodes=prior.trainingTable;
n=height(nodes);
tbl=table((1:n).',nodes.Wf_measured_kgps,nodes.reference_power_W, ...
    repmat(prior.relativeHalfWidth,n,1),repmat("linear",n,1), ...
    repmat("unavailable_outside_domain",n,1), ...
    'VariableNames',{'node_index','physical_fuel_kg_s','pt_power_W', ...
    'relative_half_width','interpolation','endpoint_policy'});
% 这是窄环境下的经验选根工具，并非全包线Np预测器。范围加明确的
% 工程容许量覆盖测量扰动，超出后回到普通物理求解，不外推经验曲线。
fields={'Altitude_mean','Pamb_mean','Tamb_mean','Mach_mean','Mkg_mean'};
tbl.require_increasing_power=repmat(prior.options.requireIncreasingPower,n,1);
names={'altitude_m','ambient_pressure_Pa','ambient_temperature_K','mach','gt_torque_Nm'};
margin=[10,1000,2,0.005,5];
for i=1:numel(fields)
    v=data.(fields{i});
    tbl.([names{i} '_min'])=repmat(min(v)-margin(i),n,1);
    tbl.([names{i} '_max'])=repmat(max(v)+margin(i),n,1);
end
end

function [data, meta] = local_query(tbl, data, inletMode)
required={'node_index','physical_fuel_kg_s','pt_power_W','relative_half_width', ...
    'interpolation','endpoint_policy'};
assert(istable(tbl) && all(ismember(required,tbl.Properties.VariableNames)), ...
    'SHT:NpDelivery:Schema','NpBranchModel字段不完整。');
x=double(tbl.physical_fuel_kg_s); y=double(tbl.pt_power_W);
requireIncreasing=true;
if ismember('require_increasing_power',tbl.Properties.VariableNames)
    requireIncreasing=all(tbl.require_increasing_power);
end
if numel(x)<3 || any(~isfinite([x;y])) || any(x<=0) || ...
        any(y<=0) || any(diff(x)<=0) || (requireIncreasing && any(diff(y)<=0)) || ...
        any(tbl.relative_half_width<=0 | tbl.relative_half_width>=1) || ...
        any(~isfinite(tbl.relative_half_width)) || ...
        numel(unique(tbl.relative_half_width))~=1 || ...
        any(string(tbl.interpolation)~="linear") || ...
        any(string(tbl.endpoint_policy)~="unavailable_outside_domain")
    error('SHT:NpDelivery:InvalidNodes','Np分支节点/范围/插值约定无效。');
end
wf=data.Wf_mean; torque=data.Mkp_mean;
available=wf>=x(1) & wf<=x(end) & torque>1e-8;
fields={'Tamb_mean','Mach_mean','Mkg_mean'};
names={'ambient_temperature_K','mach','gt_torque_Nm'};
if inletMode==3
    fields{end+1}='Altitude_mean'; names{end+1}='altitude_m';
else
    fields{end+1}='Pamb_mean'; names{end+1}='ambient_pressure_Pa';
end
for i=1:numel(fields)
    requiredDomain={[names{i} '_min'],[names{i} '_max']};
    assert(all(ismember(requiredDomain,tbl.Properties.VariableNames)), ...
        'SHT:NpDelivery:MissingDomain','Np分支缺少%s适用范围。',names{i});
    lo=tbl.([names{i} '_min']); hi=tbl.([names{i} '_max']);
    if any(~isfinite([lo;hi])) || any(lo>hi) || ...
            numel(unique(lo))~=1 || numel(unique(hi))~=1
        error('SHT:NpDelivery:InvalidDomain','Np适用范围%s无效。',names{i});
    end
    v=data.(fields{i});
    available=available & isfinite(v) & v>=lo(1) & v<=hi(1);
end
center=nan(height(data),1);
center(available)=30*interp1(x,y,wf(available),'linear')./(pi*torque(available));
width=tbl.relative_half_width(1);
data.Np_branch_center_rpm=center;
data.Np_branch_lower_rpm=center*(1-width);
data.Np_branch_upper_rpm=center*(1+width);
data.Np_branch_relative_half_width=repmat(width,height(data),1);
data.Np_branch_available=available;
data.Np_branch_source=repmat("delivered_physical_fuel_power_curve",height(data),1);
data.Np_branch_reference_uses_point_Np=false(height(data),1);
data.Np_branch_optional=true(height(data),1);
if any(~available)
    warning('SHT:NpDelivery:OutsideDomain', ...
        'Np经验选根模型不适用于%s；不外插，采用输入初值及完整气路平衡求解。', ...
        strjoin(cellstr(string(data.point_id(~available))),', '));
end
meta=struct('enabled',true,'method','delivered_physical_fuel_power_curve', ...
    'targetNpUsed',false,'trainingDataRead',false,'available',available);
end
