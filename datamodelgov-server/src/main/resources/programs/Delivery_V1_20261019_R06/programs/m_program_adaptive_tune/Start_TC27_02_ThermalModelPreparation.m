function result=Start_TC27_02_ThermalModelPreparation(options)
%START_TC27_02_THERMALMODELPREPARATION 独立建立三部件15/16状态热模型。
% 热容沿用1%部件功率、100K温差的工程量级，按总体功率直接求和。
% 不加载六部件发动机/热资产；所有参考气路及充分热平衡由当前DLL生成。
% 必须显式指定独立新assetDirectory；不自动发布清单或切换正式包。
if nargin<1,options=struct();end
% 此检查必须排在配置、配平和mkdir之前，所有调用方式共用同一保护。
plan=sht_tc27_thermal_output_plan(options);
if plan.inheritedMode
    % JSON转table后ID可能为cellstr；在配置前统一文本类型，不改变物理字段。
    plan.referenceGrid.point_id=string(plan.referenceGrid.point_id);
end
options.referencePointIndices=plan.referencePointIndices;
if plan.inheritedMode && isfield(options,'execute') && ~options.execute
    % 专项无DLL合同入口：完整路径/身份预检后，在mkdir和配置前返回。
    result=plan;result.executionStatus='PREP_ONLY_NO_DLL';
    ka=load(plan.inheritedPair.kurzkeFile,'parameterAsset');
    va=load(plan.inheritedPair.visserFile,'parameterAsset');
    [~,result.staticThermalAudit.kurzke]=local_inherit_asset(ka.parameterAsset,plan);
    [~,result.staticThermalAudit.visser]=local_inherit_asset(va.parameterAsset,plan);
    return;
end
p.runtime=plan.package.directory;p.middle=plan.outputDirectory;
assert(java.io.File(p.middle).mkdir(),'TC27:Thermal:Exists', ...
    '无法独占创建候选目录，可能已有并发生成：%s',p.middle);
work=fullfile(p.middle,'incomplete');mkdir(work);
p.kurzkeFile=fullfile(work,'tc27_kurzke15_parameters.mat');
p.thermalFile=fullfile(work,'tc27_visser16_parameters.mat');
budget=struct('enabled',false);
if plan.inheritedMode && isfield(options,'deadlineEpochSeconds')
    validateattributes(options.deadlineEpochSeconds,{'numeric'},{'scalar','real','finite'});
    budget=struct('enabled',true,'deadlineEpochSeconds',options.deadlineEpochSeconds, ...
        'directory',fullfile(work,'partial_progress'),'plan',plan);
    mkdir(budget.directory);
end
% 临时热MAT仅供本次生成过程读回；缺少完成记录时不能发布为运行包。
timer=tic;
try
if plan.inheritedMode
    [cfg,a,v,grid,gasTrim,inheritance]=local_inherited_setup(plan,budget);
    b=cfg.engine.boundary;
    parameterAsset=a;save(p.kurzkeFile,'parameterAsset','-v7.3');
    parameterAsset=v;save(p.thermalFile,'parameterAsset','-v7.3');
else
cfg=sht_tc27_config(0,'baseline',p.runtime,'physical');timer=tic;
trim=sht_trim_health_steady_point(cfg,20900,2176600,zeros(159,1));
b=cfg.engine.boundary;b.ptLoadInputMode='torque';b.gtLoadInputMode='torque';
b.Mkp=2176600/(pi*20900/30);b.Mkg=0;b.health=zeros(159,1);
a=local_provisional(cfg,trim);
% 以单位参考流量先探测，再把参考温度设为本工况代表气温，第二次得到局部W。
[d,~]=local_probe(cfg,a,trim,b);
starts=[1,4,5,8];a.nominal.referenceGasTemperature=d.heatDrivingTemperature_K(starts).';
if isrow(a.nominal.referenceGasTemperature),a.nominal.referenceGasTemperature=a.nominal.referenceGasTemperature.';end
[d,~]=local_probe(cfg,a,trim,b);
a.nominal.referenceFlow=d.componentRNIStar(:);
a.nominal.referenceGasTemperature=d.heatDrivingTemperature_K(starts);a.nominal.referenceGasTemperature=a.nominal.referenceGasTemperature(:);
weights=[.25;.25;.50;1;.25;.25;.50;.25;.25;.50];
power=d.componentPower_W([1,1,1,2,3,3,3,4,4,4]);power=power(:);
a.nominal.heatCapacity0=weights.*.01.*power.*a.nominal.tau0/100;
metal=d.heatDrivingTemperature_K(:);disk=metal([2,6,9]);
a.nominal.initialTemperatureState=[metal;disk];
a.nominal.clearanceParameter=local_gap(metal,disk);
parameterAsset=a;save(p.kurzkeFile,'parameterAsset','-v7.3');
% Visser用相同总热容量，明确划分主流、冷却及根盘导热，不能平均时间常数。
v=a;v.assetVersion='TC27-three-visser16-v1';v.interface.thermalModelMode=3;
v.interface.nominalThermalConfigVersion=250203;
n=a.nominal;cap=[n.heatCapacity0;.8*n.heatCapacity0(5)];
tau=[n.tau0;n.tau0(5)];frac=ones(11,1);frac([5,6,7,10])=.75;frac(11)=.65;
n.visserMetalHeatCapacity=cap;n.visserHotGasConductance0=cap./tau.*frac;
n.visserHotGasBeta=[n.beta;.05];n.visserDiskHeatCapacity=6*n.heatCapacity0([2,6,9]);
n.visserRootDiskConductance0=n.visserDiskHeatCapacity./n.diskTau0;
ratio=[.680525;.220490;.098985;.218750;.781250;.138313;.518672;.261757;.081259; ...
    .579017;.420983;.737104;.262896;1;.533627;.466373;1;1;1];
count=[3,2,4,2,2,1,2,1,1,1];route=repelem((1:10).',count.');
for k=1:10,mask=route==k;ratio(mask)=ratio(mask)/sum(ratio(mask));end
targetType=[1;2;1;1;1;1;1;2;1;2;2;2;1;2;1;2;2;2;0];
target=[11;2;6;7;5;7;11;2;6;2;2;3;10;3;10;3;3;2;0];
fraction=[.081;.0306;.0247;.0148;.0057;.0046;.0064;.0045;.003;.0045];
w=n.referenceFlow(1)*fraction(route).*ratio;w(17)=n.referenceFlow(1)*sum(fraction(8:9));
budget=cap./tau.*(1-frac);diskBudget=[0;.5*n.visserRootDiskConductance0(2:3)];
n.visserCoolingConductance0=zeros(19,1);
for k=1:19
    if targetType(k)==0,continue;end
    mask=targetType==targetType(k)&target==target(k);
    if targetType(k)==1,value=budget(target(k));else,value=diskBudget(target(k));end
    n.visserCoolingConductance0(k)=value*w(k)/sum(w(mask));
end
n.initialTemperatureState=[metal;disk;.95*metal(5)];v.nominal=n;
v.coolingSplitConfiguration=struct('configVersion',250304,'parameterCount',19,'ratio',ratio, ...
    'branchTargetType',targetType,'branchTargetIndex',target,'sourceMode','fixed_engineering_prior');
parameterAsset=v;save(p.thermalFile,'parameterAsset','-v7.3');
% 生成各自参考表；零瞬态修正、无间隙反馈求气热平衡，随后计算参考间隙。
grid=sht_tc24_operating_points('train');grid=grid(options.referencePointIndices,:);
% 低慢车不能直接用设计点气路猜值；各参考点先独立作零修正气路配平。
gasTrim=cell(height(grid),1);
for k=1:height(grid)
    gasTrim{k}=sht_trim_health_steady_point(cfg,grid.Np_rpm(k),1000*grid.load_power_kW(k),zeros(159,1));
end
end
% 保存实际求解边界，不重新构造环境；各工况的Mkp由参考表逐行覆盖。
% 元数据只用于交付和读回，不参与后续配平或参考间隙计算。
generationConfiguration=local_generation_configuration(cfg,plan,grid,b);
if plan.inheritedMode
    % 先完成两模型R1并报告成本；随后继续使用这两个结果，不重新求R1。
    designEquilibria={local_design_equilibrium(cfg,a,p.kurzkeFile,gasTrim{1},grid(1,:),b,budget), ...
        local_design_equilibrium(cfg,v,p.thermalFile,gasTrim{1},grid(1,:),b,budget)};
    fprintf('G11 R1两模型完成，已用%.1fs；R1不再求解。\n',toc(timer));
    for k=2:height(grid)
        local_budget_guard(budget,sprintf('before_gas_trim_p%02d',k));pointTimer=tic;
        gasTrim{k}=sht_trim_health_steady_point(cfg,grid.Np_rpm(k), ...
            1000*grid.load_power_kW(k),zeros(159,1));
        local_budget_record(budget,sprintf('gas_trim_p%02d',k),gasTrim{k},toc(pointTimer));
        local_budget_guard(budget,sprintf('after_gas_trim_p%02d',k));
    end
end
for mode=[1,3]
    if plan.inheritedMode,local_budget_guard(budget,sprintf('before_open_mode%d',mode));end
    if mode==1,asset=a;file=p.kurzkeFile;else,asset=v;file=p.thermalFile;end
    % 当前文件刚由同包物理定义生成；沿共享初始化核严格校验身份。
    [probe,~]=sht_configure_transient_heat_state(cfg,file);
    probe.engine.transientEffects.stepInTemplate=sht_build_transient_step_in_template(asset,'heat_feedback',15);
    probe=sht_validate_runtime_config(probe);
    engine=sht_engine_open(probe.engine);
    cleanup=onCleanup(@()sht_engine_close(engine));
    equilibrium=cell(height(grid),1);epsilon=zeros(height(grid),3);ng=zeros(height(grid),1);
    for k=1:height(grid)
        boundary=b;boundary.Mkp=grid.target_torque_Nm(k);
        if plan.inheritedMode && k==1
            e=designEquilibria{1+(mode==3)};
        else
        if plan.inheritedMode,local_budget_guard(budget,sprintf('before_eq_m%d_p%02d',mode,k));end
        pointTimer=tic;
        x=probe.engine.initial.state;x(1:2)=[gasTrim{k}.Np;gasTrim{k}.Ng];wf=gasTrim{k}.Wf;
        if k>1,x(3:end)=equilibrium{k-1}.state(3:end);end
        sht_tc27_reset_gas_seed(engine,gasTrim{k}.varIte);
        e=sht_thermal_equilibrium_solve(engine,x,wf,boundary,'trim_fixed_np', ...
            struct('maximumIterations',40,'finalJacobianAudit',false,'verbose',true,'label',sprintf('TC27 mode%d %s',mode,char(string(grid.point_id(k))))));
        if plan.inheritedMode
            held=engine.callContext.engPtr.eng;e.commonWorkingSeed=double(held.varIte(1:6));
            local_budget_record(budget,sprintf('equilibrium_m%d_p%02d',mode,k),e,toc(pointTimer));
            assert(e.physicalValid,'TC27:Thermal:Equilibrium','%s气热平衡失败：%s。',char(string(grid.point_id(k))),e.stopReason);
            local_budget_guard(budget,sprintf('after_eq_m%d_p%02d',mode,k));
        else
            assert(e.physicalValid,'TC27:Thermal:Equilibrium','%s气热平衡失败：%s。',char(string(grid.point_id(k))),e.stopReason);
            held=engine.callContext.engPtr.eng;e.commonWorkingSeed=double(held.varIte(1:6));
        end
        end
        equilibrium{k}=e;ng(k)=e.state(2);epsilon(k,:)=local_epsilon(e.state(3:12),e.state(13:15),asset.nominal.clearanceParameter);
        fprintf('TC27 mode%d %s: dN %.3g rpm/s, dT %.3g K/s, energy %.3g\n', ...
            mode,char(string(grid.point_id(k))),e.finalMaximumShaftDerivative_rpmps,e.finalMaximumThermalDerivative_Kps,e.normalizedEnergyResidual);
    end
    if plan.inheritedMode
        tableMask=grid.useForTable;
        asset.nominal.initialTemperatureState=equilibrium{1}.state(3:end);
        asset.nominal.epsilonSSCurrent=local_total_gap(asset,equilibrium{1},plan.newDesignSpeed_rpm);
        asset.referenceTable=local_inherited_reference(grid,equilibrium,epsilon, ...
            asset.nominal.clearanceParameter,plan.newDesignSpeed_rpm);
        asset.referenceEquilibria=equilibrium(tableMask);asset.referenceGrid=grid(tableMask,:);
        asset.stateNames=probe.engine.stateNames;
        asset.designPoint=equilibrium{1};asset.inheritedPreparation=inheritance;
        % V1不参与表构造。仅再做固定状态两次求值，比较查表与直接参考间隙。
        asset.independentValidation=local_independent_validation( ...
            engine,probe,asset,equilibrium{~tableMask},grid(~tableMask,:),b,budget);
        clear cleanup;
    else
    clear cleanup;
    asset.nominal.initialTemperatureState=equilibrium{1}.state(3:end);
    asset.nominal.epsilonSSCurrent=epsilon(1,:).';
    asset.referenceTable=local_reference(grid,ng,epsilon,asset.nominal.clearanceParameter);
    asset.referenceEquilibria=equilibrium;asset.referenceGrid=grid;
    asset.designPoint=equilibrium{1};
    end
    asset.generationConfiguration=generationConfiguration;
    parameterAsset=asset;save(file,'parameterAsset','-v7.3');
    if mode==1,result.kurzke=asset;else,result.visser=asset;end
end
% 两种模型及全部参考点都成功后，再给候选文件赋最终名称。
% move不带REPLACE_EXISTING；即使检查后出现同名文件也绝不覆盖。
if plan.inheritedMode
    local_budget_guard(budget,'before_final_pair_validation');
    sht_tc27_validate_thermal_assets(p.runtime,{p.kurzkeFile,p.thermalFile},nnz(grid.useForTable),cfg);
    local_budget_guard(budget,'after_final_pair_validation');
else
    sht_tc27_validate_thermal_assets(p.runtime,{p.kurzkeFile,p.thermalFile},height(grid));
end
files={p.kurzkeFile,p.thermalFile};thermalAssets=struct('relative',{},'sha256',{});
for k=1:2
    [~,name,ext]=fileparts(files{k});target=fullfile(p.middle,[name,ext]);
    if plan.inheritedMode
        target=sht_tc27_canonical_path(target);
        assert(strcmpi(target,plan.thermalAssetTargets{k}), ...
            'TC27:G11:AssetRoot','实际热输出与前置核定目标不一致。');
        relative=plan.thermalAssetRelativePaths{k};
    else
        relative=strrep(target(numel(plan.root)+2:end),filesep,'/');
    end
    java.nio.file.Files.move(java.io.File(files{k}).toPath(),java.io.File(target).toPath(), ...
        javaArray('java.nio.file.CopyOption',0));
    thermalAssets(k)=struct('relative',relative,'sha256',sht_tc27_file_identity(target));
end
result.elapsedSeconds=toc(timer);result.provenance='三部件工程热先验，尚非实物热标定';
result.preparation=struct('schemaVersion','TC27_THERMAL_READY_V1','complete',true, ...
    'physicalIdentity',plan.package.identity,'thermalAssets',thermalAssets, ...
    'referencePointIndices',options.referencePointIndices);
result.preparation.generationConfiguration=generationConfiguration;
if plan.inheritedMode
    result.preparation.schemaVersion='TC27_G11_INHERITED_THERMAL_READY_V1';
    result.preparation.inheritance=inheritance;
    result.preparation.assetRoot=plan.assetRoot;
    result.preparation.thermalAssetRelativePaths=plan.thermalAssetRelativePaths;
    result.preparation.gasInitialTrimCount=height(grid);
    result.preparation.thermalEquilibriumCount=2*height(grid);
    result.preparation.tablePointCount=nnz(grid.useForTable);
    result.preparation.independentPointCount=nnz(~grid.useForTable);
    result.preparation.notAutomaticallyPublished=true;
    result.provenance='继承R011工程热先验，仅重算新设计平衡/参考间隙；未重新标定';
end
ready=fullfile(work,'tc27_thermal_preparation_result.mat');
save(ready,'result','-v7.3');
java.nio.file.Files.move(java.io.File(ready).toPath(), ...
    java.io.File(fullfile(p.middle,'tc27_thermal_preparation_result.mat')).toPath(), ...
    javaArray('java.nio.file.CopyOption',0));
fprintf('TC27-02完成，用时%.1fs。\n',result.elapsedSeconds);
catch err
    if strcmp(err.identifier,'TC27:G11:BudgetStop')
        % 当前调用已经自然返回；只关句柄、保存partial，不再启动新点。
        if exist('cleanup','var'),clear cleanup;end
        result=struct('schemaVersion','TC27_G11_PARTIAL_BUDGET_STOP_V1', ...
            'complete',false,'executionStatus','PARTIAL_BUDGET_STOP', ...
            'stopReason',err.message,'elapsedSeconds',toc(timer), ...
            'progressDirectory',budget.directory,'physicalIdentity',plan.package.identity, ...
            'assetRoot',plan.assetRoot,'referencePoints',plan.referenceGrid);
        save(fullfile(work,'partial_budget_result.mat'),'result','-v7.3');
        fprintf('G11预算安全中止：%s；结果仅为partial，未发布热资产。\n',err.message);
        return;
    end
    rethrow(err);
end
end

function g=local_generation_configuration(cfg,plan,grid,boundary)
% 直接保存配置完成后的边界，包括deltaTemperature及模式相关有效字段。
% power等未启用分支的值仍保留审计；ptLoadInputMode/gtLoadInputMode决定用法。
points=grid;
if ~ismember('useForTable',points.Properties.VariableNames)
    points.useForTable=true(height(points),1);
end
configurationIdentity=struct('defaultConfigFile',which('sht_default_config'), ...
    'defaultConfigSHA256',local_hash(which('sht_default_config')), ...
    'controllerGainFile','','controllerGainSHA256','');
if isfield(cfg,'controller') && isfield(cfg.controller,'gainSchedule') && ...
        isfield(cfg.controller.gainSchedule,'sourceFile')
    gainFile=cfg.controller.gainSchedule.sourceFile;
    configurationIdentity.controllerGainFile=gainFile;
    if isfile(gainFile)
        configurationIdentity.controllerGainSHA256=local_hash(gainFile);
    end
end
g=struct('schemaVersion','TC27_THERMAL_GENERATION_CONFIG_V1', ...
    'modelMode',cfg.engine.modelMode,'thermalModes',[1,3], ...
    'effectiveBoundaryTemplate',boundary,'referencePoints',points, ...
    'referenceBoundaryRule',struct('MkpSource','referencePoints.target_torque_Nm', ...
        'MkpUnit','N*m','otherFieldsSource','effectiveBoundaryTemplate', ...
        'NpTargetSource','referencePoints.Np_rpm','NpUnit','r/min'), ...
    'sourceDesignReference',[],'executionDesignReference',[], ...
    'configurationIdentity',configurationIdentity,'thermalPriorIdentity',[], ...
    'inheritedMode',plan.inheritedMode,'physicalIdentity',plan.package.identity);
if plan.inheritedMode
    g.sourceDesignReference=plan.sourceDesignReference;
    g.executionDesignReference=plan.designReference;
    g.thermalPriorIdentity=plan.sourceThermalIdentity;
end
% RNI配置属于实际运行配置，不从结果文件名推断是否启用。
g.reynoldsCorrection=[];
if isfield(cfg.engine,'reynoldsCorrection')
    g.reynoldsCorrection=cfg.engine.reynoldsCorrection;
end
end

function a=local_provisional(cfg,trim)
a=struct('assetVersion','TC27-three-kurzke15-v1', ...
    'interface',struct('interfaceVersion',2502,'stepInLength',512,'stepOutLength',128, ...
    'thermalModelMode',1,'nominalThermalConfigVersion',250201), ...
    'nominalHealth',zeros(159,1),'referenceTable',struct('generated',false));
n=struct('tau0',[1;2;5;1;1;2;5;1;2;5],'heatCapacity0',ones(10,1), ...
    'beta',[.35;.5;.7;.5;.35;.5;.7;.35;.5;.7],'diskTau0',[20;30;30], ...
    'referenceFlow',ones(4,1),'referenceGasTemperature',500*ones(4,1), ...
    'clearanceParameter',local_gap(500*ones(10,1),500*ones(3,1)), ...
    'epsilonSSCurrent',.015*ones(3,1),'kSM',0,'clearanceExchangeRate',[-1;-.5;-.5;-.5], ...
    'initialTemperatureState',500*ones(13,1));
a.nominal=n;
runtime=cfg.engine.interface.controlDir;
files={fullfile(runtime,'GTESS.dll'),fullfile(runtime,'GTESS.h'),cfg.engine.modelConfiguration};
fields={'dllSHA256','headerSHA256','modelSHA256'};
for k=1:3,a.modelIdentity.(fields{k})=local_hash(files{k});end
a.designPoint=trim;
end

function [d,y]=local_probe(cfg,a,trim,b)
cfg.engine.transientEffects=struct('enabled',true,'stepInTemplate', ...
    sht_build_transient_step_in_template(a,'heat_state'),'thermalModelConfiguration', ...
    sht_build_thermal_model_configuration(a));
cfg.engine.initial.state=[trim.Np;trim.Ng;a.nominal.initialTemperatureState];
cfg=sht_validate_runtime_config(cfg);e=sht_engine_open(cfg.engine);c=onCleanup(@()sht_engine_close(e)); %#ok<NASGU>
[~,y,d]=sht_engine_derivative(e,cfg.engine.initial.state,trim.Wf,b);
assert(d.ret==0 && d.convergeTag==0 && d.maxErr<1e-5,'三部件热参数探测失败。');
end

function p=local_gap(m,d)
p=zeros(3,10);for k=1:3,j=[1,5,8];j=j(k);p(k,:)=[.015,3e-5,1e-5,5e-5,.003,.5,m(j+2),.5*(m(j)+m(j+1)),d(k),1];end
end
function e=local_epsilon(m,d,p)
e=zeros(1,3);for k=1:3,j=[1,5,8];j=j(k);e(k)=p(k,1)+p(k,2)*(m(j+2)-p(k,7))-p(k,3)*(.5*(m(j)+m(j+1))-p(k,8))-p(k,4)*(d(k)-p(k,9));end
end
function r=local_reference(grid,ng,epsilon,p)
r=struct('generated',true,'topology','legacy3','standardTemperature_K',288.15, ...
    'defaultInletTotalTemperature_K',288.15,'designSpeed_rpm',[38000;38000;20900], ...
    'centrifugalCoefficient',p(:,5),'referenceNormalizedSpeed',p(:,10));
for k=1:2
    names={'HPC','GT'};[x,order]=sort(ng);[x,~,g]=unique(x);v=accumarray(g,epsilon(order,k),[],@mean);
    r.(names{k})=struct('correctedSpeed_rpm',x,'epsilonSSThermal',v);
end
r.PT=struct('correctedSpeed_rpm',grid.Np_rpm,'loadPower_W',grid.load_power_kW*1000,'epsilonSSThermal',epsilon(:,3));
end
function h=local_hash(file)
fid=fopen(file,'rb');assert(fid>=0,'无法读取%s',file);c=onCleanup(@()fclose(fid)); %#ok<NASGU>
x=fread(fid,inf,'*uint8');d=java.security.MessageDigest.getInstance('SHA-256');d.update(typecast(x,'int8'));
h=upper(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end

function [cfg,a,v,grid,gasTrim,evidence]=local_inherited_setup(plan,budget)
% 严格先核共享版本，再在第一次配置调用前传递实际执行设计参考。
local_assert_hash(which('sht_default_config'),plan.configurationSHA256);
local_budget_guard(budget,'before_first_configuration');
user=struct('engine',struct('modelMode',0,'runtimeDirectory',plan.package.directory, ...
    'designReference',plan.designReference),'plot',struct('enable',false));
% 共享配置保持原enable/增益及d41恢复；只显式指定同字节调度表来源。
user.controller=struct('gainSchedule',struct('sourceFile',plan.controllerGainFile));
configurationTimer=tic;cfg=sht_default_config(user);
local_budget_record(budget,'initial_configuration',cfg,toc(configurationTimer));
local_budget_guard(budget,'after_first_configuration');
cfg.engine.tc27RuntimeIdentity=plan.package.identity;
cfg.engine.reynoldsCorrection=[];
cfg.engine.boundary=sht_merge_config(cfg.engine.boundary,plan.boundary);
cfg.engine.boundary.ptLoadInputMode='torque';cfg.engine.boundary.gtLoadInputMode='torque';
cfg.engine.boundary.hpsPower=0;cfg.engine.boundary.health=zeros(159,1);
cfg.engine.boundary.healthScheduleEnabled=false;cfg.engine.healthScheduleProfile=[];
cfg.Tsim=.025;cfg.Tctrl=.025;cfg=sht_validate_runtime_config(cfg);
ka=load(plan.inheritedPair.kurzkeFile,'parameterAsset');
va=load(plan.inheritedPair.visserFile,'parameterAsset');
[a,kEvidence]=local_inherit_asset(ka.parameterAsset,plan);
[v,vEvidence]=local_inherit_asset(va.parameterAsset,plan);
grid=plan.referenceGrid;gasTrim=cell(height(grid),1);
% 先只配平R1；两模型R1通过后再配平其余五点，全部气路初值共用。
for k=1
    local_budget_guard(budget,'before_gas_trim_p01');pointTimer=tic;
    gasTrim{k}=sht_trim_health_steady_point(cfg,grid.Np_rpm(k), ...
        1000*grid.load_power_kW(k),zeros(159,1));
    local_budget_record(budget,'gas_trim_p01',gasTrim{k},toc(pointTimer));
    local_budget_guard(budget,'after_gas_trim_p01');
end
evidence=struct('schemaVersion','TC27_G11_THERMAL_INHERITANCE_V1', ...
    'sourceThermalIdentity',plan.sourceThermalIdentity, ...
    'sourceDesignReference',plan.sourceDesignReference, ...
    'executionDesignReference',plan.designReference,'physicalIdentity',plan.package.identity, ...
    'sourceModelFile',plan.sourceModelFile,'designStateFile',plan.designStateFile, ...
    'configurationSHA256',plan.configurationSHA256, ...
    'controllerGainFile',plan.controllerGainFile,'controllerGainSHA256',plan.controllerGainSHA256, ...
    'kurzke',kEvidence,'visser',vEvidence, ...
    'referencePoints',grid,'priorRecalibrated',false);
end

function [a,evidence]=local_inherit_asset(source,plan)
a=source;p0=source.nominal.clearanceParameter;
old=plan.oldDesignSpeed_rpm(:);new=plan.newDesignSpeed_rpm(:);
validateattributes([old;new],{'numeric'},{'real','finite','positive'});
p=p0;p(:,5)=p0(:,5).*(new./old).^2;p(:,10)=p0(:,10).*(old./new);
a.nominal.clearanceParameter=p;
a.referenceTable=struct('generated',false);
if isfield(a,'referenceEquilibria'),a=rmfield(a,'referenceEquilibria');end
if isfield(a,'referenceGrid'),a=rmfield(a,'referenceGrid');end
a.modelIdentity=struct('dllSHA256',local_hash(fullfile(plan.package.directory,'GTESS.dll')), ...
    'headerSHA256',local_hash(fullfile(plan.package.directory,'GTESS.h')), ...
    'modelSHA256',local_hash(fullfile(plan.package.directory,'Turboshaft-TS.mdl')));
packed=sht_build_thermal_model_configuration(a);
if packed.thermalModelMode==1,bSlots=[82,92,102];rSlots=[87,97,107];
else,bSlots=[113,123,133];rSlots=[118,128,138];end
assert(isequal(packed.parameterVector(bSlots),p(:,5)) && ...
    isequal(packed.parameterVector(rSlots),p(:,10)), ...
    'TC27:G11:Packing','147/178实际打包槽位与间隙矩阵不一致。');
speedCases=unique([0,14000,20700,37800,old.',new.', ...
    .25*old.',.5*old.',.8*old.',1.05*old.']);
maximumDifference=zeros(3,1);
for k=1:3
    before=-p0(k,5)*((speedCases/old(k)).^2-p0(k,10)^2);
    after=-p(k,5)*((speedCases/new(k)).^2-p(k,10)^2);
    difference=max(abs(before-after));maximumDifference(k)=difference;
    assert(difference<=64*eps(max(1,max(abs(before)))), ...
        'TC27:G11:Centrifugal','等价离心变换在部件%d不一致。',k);
end
% 除显式b/r坐标变换外，所有标称热物理字段逐项保持原值。
other=setdiff(fieldnames(source.nominal),{'clearanceParameter'});
for k=1:numel(other)
    assert(isequaln(a.nominal.(other{k}),source.nominal.(other{k})), ...
        'TC27:G11:PriorChanged','意外改动标称热字段：%s。',other{k});
end
evidence=struct('oldDesignSpeed_rpm',old,'newDesignSpeed_rpm',new, ...
    'oldClearanceParameter',p0,'newClearanceParameter',p, ...
    'bSlots',bSlots,'rSlots',rSlots,'actualParameterCount',packed.parameterCount, ...
    'actualPackedB',packed.parameterVector(bSlots), ...
    'actualPackedReferenceSpeed',packed.parameterVector(rSlots), ...
    'speedCases_rpm',speedCases,'maximumCentrifugalDifference',maximumDifference, ...
    'nominalPhysicalFieldsUnchanged',true);
end

function r=local_inherited_reference(grid,equilibrium,epsilon,p,designSpeed)
mask=grid.useForTable;np=zeros(height(grid),1);ng=np;tt=np;power=np;
for k=1:height(grid)
    np(k)=equilibrium{k}.state(1);ng(k)=equilibrium{k}.state(2);
    tt(k)=equilibrium{k}.output.Tt1;
    power(k)=grid.target_torque_Nm(k)*pi*np(k)/30;
end
r=struct('generated',true,'topology','legacy3','standardTemperature_K',288.15, ...
    'defaultInletTotalTemperature_K',tt(1),'designSpeed_rpm',designSpeed(:), ...
    'centrifugalCoefficient',p(:,5),'referenceNormalizedSpeed',p(:,10));
correctedNg=ng(mask)./sqrt(tt(mask)/288.15);
for k=1:2
    names={'HPC','GT'};[x,order]=sort(correctedNg);[x,~,g]=unique(x);
    value=epsilon(mask,k);v=accumarray(g,value(order),[],@mean);
    assert(numel(x)>=2,'TC27:G11:ReferenceRank','换算转速参考点不足。');
    r.(names{k})=struct('correctedSpeed_rpm',x,'epsilonSSThermal',v);
end
r.PT=struct('correctedSpeed_rpm',np(mask)./sqrt(tt(mask)/288.15), ...
    'loadPower_W',power(mask),'epsilonSSThermal',epsilon(mask,3), ...
    'extrapolationPolicy','continuous_hull_projection');
sht_prepare_clearance_reference_lookup(r);
end

function total=local_total_gap(asset,equilibrium,designSpeed)
thermal=local_epsilon(equilibrium.state(3:12),equilibrium.state(13:15), ...
    asset.nominal.clearanceParameter).';
p=asset.nominal.clearanceParameter;n=equilibrium.state([2,2,1]);n=n(:);
total=thermal-p(:,5).*((n./designSpeed(:)).^2-p(:,10).^2);
assert(all(isfinite(total))&&all(total>0),'TC27:G11:Gap','参考间隙不是有限正值。');
end

function check=local_independent_validation(engine,probe,asset,e,point,boundary,budget)
reference=sht_prepare_clearance_reference_lookup(asset.referenceTable);
power=point.target_torque_Nm*pi*e.state(1)/30;
[interpolated,lookupInfo]=sht_lookup_clearance_reference(reference,e.state(1), ...
    e.state(2),power,e.output.Tt1);
direct=local_total_gap(asset,e,asset.referenceTable.designSpeed_rpm);
% 模板和运行派生标志必须共用公共校验；否则M层不会写入本次epsilon_ss。
jointProbe=probe;jointProbe.engine.transientEffects.stepInTemplate= ...
    sht_build_transient_step_in_template(asset,'joint_full',15);
jointProbe.engine.transientEffects.clearanceReferenceTable=reference;
jointProbe=sht_validate_runtime_config(jointProbe);
comparison=engine;comparison.transientEffects=jointProbe.engine.transientEffects;
assert(comparison.transientEffects.clearanceEnabled && ...
    comparison.transientEffects.clearanceFeedbackEnabled, ...
    'TC27:G11:ReferenceInjection','joint_full派生间隙标志未同步。');
boundary.Mkp=point.target_torque_Nm;
boundary.epsilonSSHeld=interpolated;
local_budget_guard(budget,sprintf('before_independent_table_mode%d',asset.interface.thermalModelMode));
pointTimer=tic;
sht_tc27_reset_gas_seed(comparison,e.commonWorkingSeed);
[di,yi,infoI]=sht_engine_derivative(comparison,e.state,e.fuelFlow_kgps,boundary);
actualStepI=double(comparison.callContext.stepIn.Value);actualStepI=actualStepI(:);
local_budget_record(budget,sprintf('independent_table_mode%d',asset.interface.thermalModelMode), ...
    struct('derivative',di,'output',yi,'diagnostics',infoI,'actualStepIn',actualStepI),toc(pointTimer));
local_budget_guard(budget,sprintf('after_independent_table_mode%d',asset.interface.thermalModelMode));
boundary.epsilonSSHeld=direct;
local_budget_guard(budget,sprintf('before_independent_direct_mode%d',asset.interface.thermalModelMode));
pointTimer=tic;
sht_tc27_reset_gas_seed(comparison,e.commonWorkingSeed);
[dd,yd,infoD]=sht_engine_derivative(comparison,e.state,e.fuelFlow_kgps,boundary);
actualStepD=double(comparison.callContext.stepIn.Value);actualStepD=actualStepD(:);
local_budget_record(budget,sprintf('independent_direct_mode%d',asset.interface.thermalModelMode), ...
    struct('derivative',dd,'output',yd,'diagnostics',infoD,'actualStepIn',actualStepD),toc(pointTimer));
local_budget_guard(budget,sprintf('after_independent_direct_mode%d',asset.interface.thermalModelMode));
% 同时核对实传512数组与DLL返回的参考间隙，不能仅以输出有差异判定注入。
epsilonIndex=431:433;tolerance=1e-12;
assert(numel(actualStepI)==512 && numel(actualStepD)==512 && ...
    all(actualStepI(346:347)==1) && all(actualStepD(346:347)==1) && ...
    max(abs(actualStepI(epsilonIndex)-interpolated(:)))<=tolerance && ...
    max(abs(actualStepD(epsilonIndex)-direct(:)))<=tolerance && ...
    max(abs(actualStepI(epsilonIndex)-actualStepD(epsilonIndex)))>tolerance, ...
    'TC27:G11:ReferenceInjection','table/direct不同参考间隙没有实际写入DLL输入数组。');
assert(isfield(infoI,'clearanceSteady') && isfield(infoD,'clearanceSteady') && ...
    max(abs(infoI.clearanceSteady(:)-interpolated(:)))<=tolerance && ...
    max(abs(infoD.clearanceSteady(:)-direct(:)))<=tolerance, ...
    'TC27:G11:ReferenceInjection','DLL返回的参考间隙与本次实传值不一致。');
assert(infoI.ret==0 && infoD.ret==0 && infoI.convergeTag==0 && infoD.convergeTag==0 && ...
    infoI.maxErr<1e-5 && infoD.maxErr<1e-5 && all(isfinite([di;dd])), ...
    'TC27:G11:Independent','V1独立求值失败。');
channels={'Np','Ng','Pt3','Tt3','Pt45','Tt45','Pt5','Tt5','WIn'};
units={'rpm','rpm','Pa','K','Pa','K','Pa','K','kg/s'};
delta=zeros(numel(channels),1);
for k=1:numel(channels),delta(k)=yi.(channels{k})-yd.(channels{k});end
check=struct('point',point,'equilibrium',e,'inTable',false, ...
    'directReferenceGap',direct,'interpolatedReferenceGap',interpolated, ...
    'referenceGapDifference',interpolated-direct,'lookupInfo',lookupInfo, ...
    'predictionUsingTable',yi,'predictionUsingDirectReference',yd, ...
    'derivativeUsingTable',di,'derivativeUsingDirectReference',dd, ...
    'inputAudit',struct('synchronizedBy','sht_validate_runtime_config', ...
        'clearanceEnabled',comparison.transientEffects.clearanceEnabled, ...
        'clearanceFeedbackEnabled',comparison.transientEffects.clearanceFeedbackEnabled, ...
        'epsilonStepInIndex',epsilonIndex,'actualStepInUsingTable',actualStepI, ...
        'actualStepInUsingDirectReference',actualStepD,'differentReferencesTransmittedAndReturned',true), ...
    'outputDifference',table(channels(:),units(:),delta, ...
        'VariableNames',{'channel','unit','difference'}), ...
    'diagnosticsUsingTable',infoI,'diagnosticsUsingDirectReference',infoD);
end

function e=local_design_equilibrium(cfg,asset,file,gasTrim,point,boundary,budget)
mode=asset.interface.thermalModelMode;
local_budget_guard(budget,sprintf('before_eq_m%d_p01',mode));pointTimer=tic;
[probe,~]=sht_configure_transient_heat_state(cfg,file);
probe.engine.transientEffects.stepInTemplate=sht_build_transient_step_in_template(asset,'heat_feedback',15);
probe=sht_validate_runtime_config(probe);engine=sht_engine_open(probe.engine);
cleanup=onCleanup(@()sht_engine_close(engine)); %#ok<NASGU>
x=probe.engine.initial.state;x(1:2)=[gasTrim.Np;gasTrim.Ng];
boundary.Mkp=point.target_torque_Nm;sht_tc27_reset_gas_seed(engine,gasTrim.varIte);
e=sht_thermal_equilibrium_solve(engine,x,gasTrim.Wf,boundary,'trim_fixed_np', ...
    struct('maximumIterations',40,'finalJacobianAudit',false,'verbose',true, ...
    'label',sprintf('G11 mode%d R1',asset.interface.thermalModelMode)));
held=engine.callContext.engPtr.eng;e.commonWorkingSeed=double(held.varIte(1:6));
local_budget_record(budget,sprintf('equilibrium_m%d_p01',mode),e,toc(pointTimer));
assert(e.physicalValid,'TC27:G11:R1','R1热平衡失败：%s。',e.stopReason);
local_budget_guard(budget,sprintf('after_eq_m%d_p01',mode));
end
function local_assert_hash(file,hash)
assert(isfile(file)&&strcmpi(local_hash(file),hash), ...
    'TC27:G11:ConfigurationIdentity','必须使用已核定的共享配置字节，不得先调用旧版本。');
end

function local_budget_guard(budget,stage)
if ~budget.enabled,return;end
current=double(java.lang.System.currentTimeMillis())/1000;
if current>=budget.deadlineEpochSeconds
    status=struct('schemaVersion','TC27_G11_POINT_BUDGET_STOP_V1','stage',stage, ...
        'deadlineEpochSeconds',budget.deadlineEpochSeconds,'observedEpochSeconds',current, ...
        'newPointStarted',false,'complete',false,'physicalIdentity',budget.plan.package.identity);
    save(fullfile(budget.directory,'budget_stop.mat'),'status','-v7.3');
    error('TC27:G11:BudgetStop','在%s停止后续点，已到预算边界。',stage);
end
end
function local_budget_record(budget,stage,value,elapsedSeconds)
if ~budget.enabled,return;end
file=fullfile(budget.directory,[stage,'.mat']);
assert(~isfile(file),'TC27:G11:DuplicateProgress','同一已完成点不重复保存/求解：%s。',stage);
context=struct('schemaVersion','TC27_G11_RAW_PARTIAL_POINT_V1','stage',stage, ...
    'elapsedSeconds',elapsedSeconds,'savedEpochSeconds',double(java.lang.System.currentTimeMillis())/1000, ...
    'physicalIdentity',budget.plan.package.identity,'sourceDesignReference',budget.plan.sourceDesignReference, ...
    'executionDesignReference',budget.plan.designReference,'completeThermalPair',false);
if isstruct(value) && isfield(value,'physicalValid')
    context.physicalValid=value.physicalValid;context.countAsSuccessfulPoint=value.physicalValid;
end
% value原样保存。此MAT不是可发布热资产或采样检查点，不重签旧状态。
save(file,'value','context','-v7.3');
end
