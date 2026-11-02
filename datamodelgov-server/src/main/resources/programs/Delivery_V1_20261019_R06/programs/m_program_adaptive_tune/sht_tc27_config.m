function cfg=sht_tc27_config(thermalMode,stage,runtimeDirectory,validationScope)
%SHT_TC27_CONFIG 三部件独立运行配置，不重跑或覆盖2.4资产。
if nargin<1,thermalMode=0;end
if nargin<2,stage='joint_full';end
if strcmp(stage,'baseline'),thermalMode=0;end
if nargin<3,runtimeDirectory='selected';end
if nargin<4,validationScope='complete';end
assert(~strcmp(validationScope,'physical')||thermalMode==0, ...
    'TC27:Runtime:Scope','仅基准气路生成允许physical范围；热回放必须校验完整包。');
package=sht_tc27_runtime_package(runtimeDirectory,validationScope);
% 首次配平/线性化就用指定TC27包；不能先调用根DLL后再换路径。
cfg=sht_default_config(struct('engine',struct('modelMode',0, ...
    'runtimeDirectory',package.directory), ...
    'plot',struct('enable',false)));
cfg.engine.tc27RuntimeIdentity=package.identity;
cfg.engine.reynoldsCorrection=[]; % 台架不因共享RNI能力更新而自动开启。
cfg.engine.boundary.inletBoundaryMode=1;
cfg.engine.boundary.Pt1=101325;cfg.engine.boundary.Tt1=288.15;
cfg.engine.boundary.Pamb=101325;cfg.engine.boundary.Tamb=288.15;
cfg.engine.boundary.altitude=0;cfg.engine.boundary.Mach=0;
cfg.engine.boundary.Mkg=0;cfg.engine.boundary.hpsPower=0;
cfg.Tsim=.025;cfg.Tctrl=.025;
if thermalMode~=0
    if thermalMode==1,file=package.kurzkeFile;else,file=package.thermalFile;end
    assert(ismember(thermalMode,[1,3]),'thermalMode应为0、1或3。');
    [cfg,a]=sht_configure_transient_heat_state(cfg,file);
    if isfield(a,'referenceEquilibria'),cfg.engine.tc27ReferenceEquilibria=a.referenceEquilibria;end
    cfg.engine.transientEffects.stepInTemplate=sht_build_transient_step_in_template(a,stage,15);
    if any(cfg.engine.transientEffects.stepInTemplate(346:347))
        % 只为TC27三部件启用连续边界；不修改标称资产及其他任务默认行为。
        a.referenceTable.PT.extrapolationPolicy='continuous_hull_projection';
        cfg.engine.transientEffects.clearanceReferenceTable= ...
            sht_prepare_clearance_reference_lookup(a.referenceTable);
    end
end
cfg=sht_validate_runtime_config(cfg);
end
