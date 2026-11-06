function [indices, names] = sht_uq_physical_blocks(parameters)
%SHT_UQ_PHYSICAL_BLOCKS 由参数ID分块，不把可变节点数写成固定行号。
% 前四块互斥覆盖全部显式参数；第五块有意重叠，用于跨部件联合移动。
% 引气按冷却对象归属：1~4路GT，5~10路PT/泄漏，保持既定B核含义。
required = {'c_index','base_name'};
assert(istable(parameters) && all(ismember(required, ...
    parameters.Properties.VariableNames)), 'SHT:UQ:BlockDictionary', ...
    '分块需要含c_index和base_name的参数字典。');
h = double(parameters.c_index(:));
fuel = string(parameters.base_name) == "Wf_bias";
group = zeros(height(parameters),1);
group(ismember(h,[0:6,71:76])) = 1;
group(ismember(h,[7:9,77:82,30:33,44:47])) = 2;
group(ismember(h,[10:15,83:88,34:39,48:53])) = 3;
group(fuel) = 4;
if any(group == 0)
    error('SHT:UQ:UnknownPhysicalGroup', ...
        '以下参数没有定义物理归属：%s。', ...
        strjoin(cellstr(string(parameters.base_name(group==0))),', '));
end
indices = arrayfun(@(i) find(group==i),1:4,'UniformOutput',false);
indices{5} = (1:height(parameters)).';
names = ["compressor_burner";"gas_generator_turbine"; ...
    "duct_power_turbine_nozzle";"fuel_bias";"global_cross_component"];
end
