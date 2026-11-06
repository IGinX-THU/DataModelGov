function dictionary = sht_health_parameter_dictionary(modelMode)
%SHT_HEALTH_PARAMETER_DICTIONARY 返回DLL修正系数的模式相关显式字典。
%
% dictionary = sht_health_parameter_dictionary(0) 返回三部件模式字典；
% dictionary = sht_health_parameter_dictionary(1) 返回六部件模式字典。
%
% C端使用0基h编号，统一占用stepIn[40:198]；MATLAB使用1基下标，
% 因而对应stepIn(41:199)。同一位置在两种模式下允许具有不同含义，
% 但任何未定义位置都明确标记为reserved，不能依靠隐式猜测使用。

arguments
    modelMode (1,1) double {mustBeMember(modelMode, [0, 1])}
end

count = 159;
cIndex = (0:count-1).';
matlabHealthIndex = cIndex + 1;
matlabStepInIndex = cIndex + 41;
name = repmat("reserved", count, 1);
scope = repmat("reserved", count, 1);
law = repmat("unused", count, 1);
active = false(count, 1);

% 两种模式共享的总体部件、燃烧室、管道和喷口修正。
commonName = [ ...
    "Inlet_K_dP"; "HPC_K_W"; "HPC_K_eta"; "HPC_K_PR"; ...
    "Burner_K_Wf"; "Burner_K_eta"; "Burner_K_dP"; ...
    "GT_K_W"; "GT_K_eta"; "GT_K_PR"; "GT_PT_Duct_K_dP"; ...
    "PT_K_W"; "PT_K_eta"; "PT_K_PR"; ...
    "PT_Nozzle_Duct_K_dP"; "Nozzle_K_A8"];
name(1:16) = commonName;
scope(1:16) = "aggregate/common";
law(1:16) = "original component law";
active(1:16) = true;

physicalBranch = [ ...
    "CC_GT1_INLET"; "CC_GT1_EXIT"; "CC_GT2_INLET"; ...
    "CC_GT2_EXIT"; "AC_PT1_INLET"; "AC_PT1_EXIT"; ...
    "AC_PT2_INLET"; "AC_PT2_EXIT"; "CC_PT2_EXIT"; "AC_LEAK"];

if modelMode == 0
    % 三部件和六部件对外共用10路物理气流字典。模式0所需的历史14路
    % 只由C程序在内部展开，不能再作为14个相互独立的健康参数使用。
    name(17:26) = physicalBranch + "_K_PRec";
    name(31:40) = physicalBranch + "_K_Wfrac";
    name(45:54) = physicalBranch + "_K_hExtract";
    scope([17:26, 31:40, 45:54]) = "physical 10-route bleed";
    law(17:26) = "additive pressure-recovery correction";
    law(31:40) = "additive overall-HPC-inlet-flow fraction";
    law(45:54) = "additive normalized enthalpy-extraction-position correction";
    active([17:26, 31:40, 45:54]) = true;

    transientName = ["K_Jg"; "K_Jp"; "K_tau_HPC"; ...
        "K_tau_Burner"; "K_tau_GT"; "K_tau_PT"; ...
        "K_kW_HPC"; "K_keta_HPC"; "K_keta_GT"; ...
        "K_keta_PT"; "K_tau_d_HPC"; "K_tau_d_GT"; ...
        "K_tau_d_PT"];
    name(59:71) = transientName;
    scope(59:71) = "three-component transient";
    law(59:71) = "transient model correction";
    active(59:71) = true;
else
    name(17:26) = physicalBranch + "_K_PRec";
    name(31:40) = physicalBranch + "_K_Wfrac";
    name(45:54) = physicalBranch + "_K_Tt";
    scope([17:26, 31:40, 45:54]) = "split 10-branch bleed";
    law(17:26) = "additive pressure-recovery correction";
    law(31:40) = "additive overall-HPC-inlet-flow fraction";
    law(45:54) = "multiplicative total-temperature correction (1+K)";
    active([17:26, 31:40, 45:54]) = true;

    componentName = ["AC"; "CC"; "GT1"; "GT2"; "PT1"; "PT2"];
    cursor = 72;
    for k = 1:numel(componentName)
        rows = cursor:(cursor + 2);
        name(rows) = componentName(k) + ["_K_W"; "_K_eta"; "_K_PR"];
        scope(rows) = "split local component";
        law(rows) = "(1+K_aggregate)*(1+K_local)-1";
        active(rows) = true;
        cursor = cursor + 3;
    end
    % h58:h70保留三部件历史瞬态语义，在六部件模式下不得启用。
    scope(59:71) = "split transient reserved";

    % h89:h111是六部件Kurzke/Visser共用的23个局部瞬态修正通道。
    % 名称由唯一映射函数取得，避免公共字典与辨识映射分别维护后漂移。
    [~, transientMapping] = sht_map_split_kurzke_health(zeros(10, 1), ...
        zeros(count, 1));
    transientRows = transientMapping.localHealthNumber + 1;
    name(transientRows) = string(transientMapping.localNames);
    scope(transientRows(1:2)) = "split shaft inertia";
    scope(transientRows(3:9)) = "split main thermal time scale";
    scope(transientRows(10:15)) = "split disk thermal time scale";
    scope(transientRows(16:23)) = "split clearance-performance exchange";
    law(transientRows(1:2)) = "effective inertia = nominal*(1+K)";
    law(transientRows(3:15)) = "effective thermal time scale = nominal*(1+K)";
    law(transientRows(16:23)) = "effective exchange rate = nominal*(1+K)";
    active(transientRows) = true;

    % h112:h158继续保留，当前无数值作用。
    scope(113:159) = "split transient reserved";
end

dictionary = table(cIndex, matlabHealthIndex, matlabStepInIndex, ...
    repmat(modelMode, count, 1), name, scope, law, active, ...
    'VariableNames', {'c_index', 'matlab_health_index', ...
    'matlab_step_in_index', 'model_mode', 'name', 'scope', ...
    'correction_law', 'active'});
end
