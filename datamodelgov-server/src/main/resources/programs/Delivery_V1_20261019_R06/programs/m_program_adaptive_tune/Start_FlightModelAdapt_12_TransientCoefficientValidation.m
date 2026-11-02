function result=Start_FlightModelAdapt_12_TransientCoefficientValidation(action,configuration)
% read只读取Excel；validate显式选择局部/完整记录，不能把查看绑定长计算。
% 历史MAT诊断可显式调用sht_f33_transient_identification('validate',file)。
if nargin<2,configuration=struct();end
assert(ismember(lower(action),{'read','validate'}),'仅支持read或validate。');
result=sht_f3_transient_task(action,configuration);
end
