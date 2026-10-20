function sht_tc27_validate_thermal_assets(runtimeDirectory,files,referenceCount,preparedCfg)
%SHT_TC27_VALIDATE_THERMAL_ASSETS 成对校验生成身份、参考平衡和初始化定义。
assert(iscell(files)&&numel(files)==2,'TC27:Thermal:Pair','必须同时提供Kurzke和Visser热资产。');
if nargin<4
    cfg=sht_tc27_config(0,'baseline',runtimeDirectory,'physical');
else
    % G11复用首次新设计配置，禁止为了末端校验再次按旧设计初始化。
    cfg=preparedCfg;
    assert(cfg.engine.modelMode==0 && numel(cfg.engine.initial.state)==2 && ...
        strcmpi(sht_tc27_canonical_path(cfg.engine.interface.controlDir), ...
        sht_tc27_canonical_path(runtimeDirectory)), ...
        'TC27:G11:ValidationConfig','末端校验必须使用同一个新设计气路配置。');
end
for k=1:2
    [probe,a]=sht_configure_transient_heat_state(cfg,files{k});
    modes=[1,3];states=[15,16];
    assert(a.interface.thermalModelMode==modes(k)&&numel(probe.engine.initial.state)==states(k), ...
        'TC27:Thermal:Topology','热资产模式或状态数不匹配。');
    assert(a.referenceTable.generated&&height(a.referenceGrid)==referenceCount&& ...
        numel(a.referenceEquilibria)==referenceCount,'TC27:Thermal:Reference','参考表尚未完整生成。');
    for j=1:referenceCount
        e=a.referenceEquilibria{j};
        assert(e.physicalValid&&all(isfinite(e.state))&&isfinite(e.fuelFlow_kgps), ...
            'TC27:Thermal:Reference','参考点%d无有效热平衡。',j);
    end
    for name={'HPC','GT','PT'}
        r=a.referenceTable.(name{1});
        assert(all(isfinite(r.correctedSpeed_rpm))&&all(isfinite(r.epsilonSSThermal)), ...
            'TC27:Thermal:Reference','参考表含非有限值。');
    end
    % 复用生产初始化和参考查询的语义，不新增热模型或放宽阈值。
    sht_prepare_clearance_reference_lookup(a.referenceTable);
    sht_build_thermal_model_configuration(a);
end
end
