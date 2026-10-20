function asset=sht_startstop_three_thermal_adapter(asset,cfg)
%SHT_STARTSTOP_THREE_THERMAL_ADAPTER 把已确认TC27标称先验接到起停工作流。
% 不改原MAT，不继承其轨迹验收；只补充起停需要的状态名称和开关模板。
assert(cfg.modelMode==0 && asset.interface.interfaceVersion==2502 && ...
    asset.interface.thermalModelMode==3,'必须使用三部件Visser16参数资产。');
assert(all(asset.nominalHealth==0),'首轮起停模型必须采用零健康修正。');
assert(numel(asset.nominal.initialTemperatureState)==14,'Visser16热状态必须为14维。');
asset.topology=struct('stateNames',{{'Np','Ng','T_HPC_blade','T_HPC_root', ...
    'T_HPC_case','T_Burner','T_GT_blade','T_GT_root','T_GT_case', ...
    'T_PT_blade','T_PT_root','T_PT_case','T_HPC_disk','T_GT_disk', ...
    'T_PT_disk','T_GT_guide'}},'diskRootMetalIndex',[2;6;9]);
asset.stepInTemplates.heatState=sht_build_transient_step_in_template(asset,'heat_state');
asset.stepInTemplates.jointFull=sht_build_transient_step_in_template(asset,'joint_full');
% 低速/低负载区不能用二维最近点跳变驱动参考间隙，采用已核准边界投影。
asset.referenceTable.PT.extrapolationPolicy='continuous_hull_projection';
end
