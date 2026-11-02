function [anchor, operatingPointTable] = sht_bench_truth_schedule_reference()
%SHT_BENCH_TRUTH_SCHEDULE_REFERENCE 仅供合成试车真值使用的固定参考坐标。
% 2026-09-06按用户要求保留原已发布曲线，数值逐项摘自原真值资产。
% 这些坐标是模拟未知个体的工程设定，不是当前模型重新配平结果。
% 不读取MDL、历史MAT、试车Excel或辨识结果；后续辨识禁止调用本函数。
% 表的行号对应原S2.3.2-01至07。列依次为AC/CC相对换算转速、
% GT/PT总物理压比，以及进口/燃烧室/GT-PT/PT-喷管入口换算流量kg/s。
values = [ ...
    0.92089516946750605 0.94587069307668581 3.8074131109668641 2.8507020878913067 5.7279910132523213 0.57291129033797838 3.3727331641336389 9.0508990442894035;
    0.9610486019715121 0.97424488164073542 3.8242312748382306 3.2028350661362017 6.2395656686473693 0.56312282095991606 3.3896469465011423 10.06171419227754;
    0.99999171834190437 0.99999524637150983 3.8328313902974993 3.554190406754937 6.711348698961169 0.55374451359266275 3.4007473670811175 11.051116993319665;
    0.91613808337800096 0.9426071991771432 3.8362001267117183 2.7802585101391264 5.6696398837939501 0.5756742075244059 3.3932976438886437 8.9154892805851791;
    0.8736919614751163 0.90986085745322298 3.8394942348282428 2.3898528269983652 5.0741139827880275 0.58733791406471669 3.3922134881055541 7.8225777270901737;
    0.83143750327287258 0.87640497540699536 3.8217967242552948 2.0425231113831868 4.4952581013603776 0.59910411577681488 3.3784592599839884 6.7927953126825713;
    0.68919895161891476 0.75554587366902637 3.2058333299494777 1.3526502433823648 2.7446553867376116 0.61258740206700801 2.9402691774573397 4.0746328926569202];
fieldNames = {'acRelativeCorrectedSpeed','ccRelativeCorrectedSpeed', ...
    'gtTotalPressureRatio','ptTotalPressureRatio', ...
    'inletCorrectedMassFlowKgPerS','burnerInletCorrectedMassFlowKgPerS', ...
    'gtPtDuctCorrectedMassFlowKgPerS','ptNozzleDuctCorrectedMassFlowKgPerS'};
operatingPointTable = array2table(values, 'VariableNames', fieldNames);
operatingPointTable.pointId = compose("S2.3.2-%02d", (1:7).');

anchor = struct();
anchor.schemaVersion = 'SHT_HEALTH_SCHEDULE_ANCHOR_V4_ADDITIVE_INCREMENT';
anchor.baselineFile = [mfilename('fullpath') '.m'];
anchor.sourcePolicy = 'fixed_synthetic_truth_reference_not_inference_nodes';
anchor.idleRow = 7;
anchor.designRow = 3;
anchor.normalizedNodes = [0, 0.45766364884783634, 0.59362066820763759, ...
    0.73784752850516044, 0.87469748160161531, 1];
anchor.nodeConstruction = struct('source', ...
    'frozen original synthetic-truth reference coordinates', ...
    'lossScheduleSource', 'zero-flow anchor plus six frozen positive coordinates');
anchor.designBleedFractionAcIn = [0.081000000000000016; 0.0306; 0.0247; ...
    0.014800000000000002; 0.0057; 0.0046; 0.0064; 0.0045; 0.003; 0.0045];

names = {'ac_corrected_speed','cc_corrected_speed', ...
    'gt_total_pressure_ratio','pt_total_pressure_ratio', ...
    'inlet_corrected_mass_flow','burner_inlet_corrected_mass_flow', ...
    'gt_pt_duct_corrected_mass_flow','pt_nozzle_duct_corrected_mass_flow'};
labels = {'AC相对换算转速','CC相对换算转速','GT总物理压比', ...
    'PT总物理压比','进气道进口换算流量','燃烧室进口换算流量', ...
    'GT-PT通道进口换算流量','PT-喷管通道进口换算流量'};
for j = 1:numel(names)
    x = values(:, j);
    axis = struct('low', x(7), 'high', x(3), 'idle', x(7), 'design', x(3));
    axis.operatingNodes = sort(x(:).');
    axis.label = labels{j};
    axis.unit = '-';
    axis.lowMeaning = 'frozen original zero-correction ground idle reference';
    axis.highMeaning = 'frozen original zero-correction design reference';
    if j >= 5
        % 换算流量不一定随负载增加，按原参考坐标排序，而不是假设单调。
        axis.low = min(x);
        axis.high = max(x);
        axis.connectedOperatingNodes = sort(x(1:6).');
        axis.unit = 'kg/s';
        axis.lowMeaning = 'minimum corrected flow in frozen reference points';
        axis.highMeaning = 'maximum corrected flow in frozen reference points';
    end
    axis.nodes = axis.low + (axis.high-axis.low) .* anchor.normalizedNodes;
    axis.operatingRatiosToDesign = axis.operatingNodes ./ axis.design;
    anchor.axes.(names{j}) = axis;
    anchor.idleState.(names{j}) = axis.idle;
    anchor.designState.(names{j}) = axis.design;
end
end
