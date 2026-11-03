function asset=sht_f3_thermal_asset(variant,sourceFile,targetFile,paths)
%SHT_F3_THERMAL_ASSET 三部件新运行包的热参考重建与独立造数热失配。
% 只继承已核验TC27的物理参数和参考工况，不把旧平衡结果重签为新结果。
% 13/14个温度由当前DLL联立求解；GT导向器是Visser独立第14个温度。
hash=@local_hash;
source=load(sourceFile,'parameterAsset');base=source.parameterAsset;
assert(base.interface.interfaceVersion==2502,'SHT:F3:ThermalTopology','必须为三部件资产。');
sourceRuntime=paths.runtime;
if isfield(paths,'thermalSourceRuntime'),sourceRuntime=paths.thermalSourceRuntime;end
assert(strcmpi(base.modelIdentity.headerSHA256,hash(fullfile(sourceRuntime,'GTESS.h'))) && ...
    strcmpi(base.modelIdentity.modelSHA256,hash(fullfile(sourceRuntime,'Turboshaft-TS.mdl'))) && ...
    strcmpi(base.modelIdentity.dllSHA256,hash(fullfile(sourceRuntime,'GTESS.dll'))), ...
    'SHT:F3:ThermalSource','继承物理参数的原生成包身份不匹配，不能改签旧资产。');
p=fileparts(mfilename('fullpath'));
code={'sht_f3_thermal_asset.m','sht_thermal_equilibrium_solve.m', ...
    'sht_engine_derivative.m','sht_build_thermal_model_configuration.m', ...
    'sht_build_transient_step_in_template.m','sht_prepare_clearance_reference_lookup.m'};
signature=struct('schema','F3_THERMAL_REFERENCE_R011','variant',variant, ...
    'source',hash(sourceFile),'runtime',struct(),'code',struct());
for name={'GTESS.dll','GTESS.h','Turboshaft-TS.mdl','HPC02.MAP','HPT02.MAP','LPT02.MAP'}
    signature.runtime.(matlab.lang.makeValidName(name{1}))=hash(fullfile(paths.runtime,name{1}));
end
for k=1:numel(code),signature.code.(code{k}(1:end-2))=hash(fullfile(p,code{k}));end
if isfile(targetFile)
    saved=load(targetFile,'parameterAsset');asset=saved.parameterAsset;
    assert(isfield(asset,'flightBuild') && isequaln(asset.flightBuild.identity,signature), ...
        'SHT:F3:ThermalCache','热参考身份改变；请选新批次，不覆盖旧资产。');
    return;
end
asset=base;changes=table();
if strcmp(variant,'structured')
    assert(base.interface.thermalModelMode==3,'造数热失配仅用于Visser。');
    % HPC三节点、燃烧室、GT三节点、PT三节点及GT导向器。共同偏差与
    % 节点差异分开给定；为同一发动机固定工程失配，不是制造公差数据。
    comp=[1;1;1;2;3;3;3;4;4;4;3];
    shape=[-.04;.01;.03;0;-.04;.01;.03;-.03;.02;.04;.02];
    capacity=[.08;.10;.07;-.07];conductance=[-.10;-.12;-.12;.10];
    factors=struct('visserMetalHeatCapacity',1+capacity(comp)+shape, ...
        'visserHotGasConductance0',1+conductance(comp)-shape, ...
        'visserDiskHeatCapacity',1+[.10;.12;-.12], ...
        'visserRootDiskConductance0',1+[.15;.18;-.18], ...
        'visserCoolingConductance0',1+[.18;.12;.20;.15;.12;-.15;-.18;-.12;.15;-.10;.08;.14;-.15;.10;.18;.12;-.12;.10;0]);
    names=fieldnames(factors);
    for k=1:numel(names)
        name=names{k};old=base.nominal.(name)(:);value=old.*factors.(name);
        asset.nominal.(name)=value;changes=[changes;local_rows(name,old,value)]; %#ok<AGROW>
    end
    old=base.nominal.visserHotGasBeta(:);
    asset.nominal.visserHotGasBeta=old+[.03;-.02;.04;.02;.03;-.02;.04;-.03;.02;-.04;.02];
    changes=[changes;local_rows('visserHotGasBeta',old,asset.nominal.visserHotGasBeta)];
else
    assert(strcmp(variant,'nominal'),'SHT:F3:ThermalVariant','未知热配置类型。');
end
asset.modelIdentity=struct('dllSHA256',signature.runtime.GTESS_dll, ...
    'headerSHA256',signature.runtime.GTESS_h,'modelSHA256',signature.runtime.Turboshaft_TS_mdl);
asset.flightBuild=struct('identity',signature,'sourceFile',sourceFile, ...
    'sourceIdentity',base.modelIdentity,'parameterChanges',changes, ...
    'referenceRecomputed',false,'role',variant);
% 候选只是当前求解所需完整参数文件，参考表关闭；不作为正式运行资产。
asset.referenceTable=struct('generated',false);
parameterAsset=asset;candidate=[targetFile,'.candidate.mat']; %#ok<NASGU>
save(candidate,'parameterAsset','-v7.3');
if isfield(paths,'thermalSourceRuntime')
    cfg=sht_f3_three_component_assets('config',0,'joint_full',[],paths);
else
    cfg=sht_f3_three_component_assets('config',0);
end
[cfg,~]=sht_configure_transient_heat_state(cfg,candidate);
cfg.engine.transientEffects.stepInTemplate=sht_build_transient_step_in_template(asset,'heat_feedback',15);
grid=base.referenceGrid;n=height(grid);equilibria=cell(n,1);epsilon=zeros(n,3);ng=zeros(n,1);
% RNI的设计参考定义只来自当前三部件设计气路。标称参考表仍在台架
% 基准环境构造；飞行RNI由实际候选气路实时计算，不把高度固定到表内。
if isfield(paths,'thermalSourceRuntime')
    gasCfg=sht_f3_three_component_assets('config',0,'joint_full',[],paths);
else
    gasCfg=sht_f3_three_component_assets('config',0);
end
gasTrim=cell(n,1);
for k=1:n
    fprintf('F3 %s thermal%d solve reference %d/%d\n',variant,asset.interface.thermalModelMode,k,n);
    gasTrim{k}=sht_trim_health_steady_point(gasCfg,grid.Np_rpm(k), ...
        1000*grid.load_power_kW(k),zeros(159,1));
end
engine=sht_engine_open(cfg.engine);cleanup=onCleanup(@()sht_engine_close(engine)); %#ok<NASGU>
for k=1:n
    x=cfg.engine.initial.state;x(1:2)=[gasTrim{k}.Np;gasTrim{k}.Ng];
    if k>1,x(3:end)=equilibria{k-1}.state(3:end);end
    b=cfg.engine.boundary;b.Mkp=grid.target_torque_Nm(k);b.Mkg=0;
    b.ptLoadInputMode='torque';b.gtLoadInputMode='torque';
    sht_tc27_reset_gas_seed(engine,gasTrim{k}.varIte);
    e=sht_thermal_equilibrium_solve(engine,x,gasTrim{k}.Wf,b,'trim_fixed_np', ...
        struct('maximumIterations',40,'finalJacobianAudit',false,'verbose',false));
    assert(e.physicalValid,'SHT:F3:ThermalEquilibrium','参考点%d未收敛：%s',k,e.stopReason);
    held=engine.callContext.engPtr.eng;e.commonWorkingSeed=double(held.varIte(1:6));
    equilibria{k}=e;ng(k)=e.state(2);cp=asset.nominal.clearanceParameter;
    for c=1:3
        starts=[1,5,8];j=starts(c);t=e.state(3:end);
        blade=cp(c,6)*t(j)+(1-cp(c,6))*t(j+1);
        epsilon(k,c)=cp(c,1)+cp(c,2)*(t(j+2)-cp(c,7))- ...
            cp(c,3)*(blade-cp(c,8))-cp(c,4)*(t(10+c)-cp(c,9));
    end
    fprintf('F3 %s thermal%d reference %d/%d: dN=%.3g rpm/s dT=%.3g K/s\n', ...
        variant,asset.interface.thermalModelMode,k,n,e.finalMaximumShaftDerivative_rpmps,e.finalMaximumThermalDerivative_Kps);
end
assert(all(epsilon(:)>0),'SHT:F3:ReferenceGap','参考热间隙非正。');
r=struct('generated',true,'topology','legacy3','standardTemperature_K',288.15, ...
    'defaultInletTotalTemperature_K',288.15,'designSpeed_rpm',[38000;38000;20900], ...
    'centrifugalCoefficient',cp(:,5),'referenceNormalizedSpeed',cp(:,10));
for c=1:2
    names={'HPC','GT'};[x,~,group]=unique(ng);
    r.(names{c})=struct('correctedSpeed_rpm',x,'epsilonSSThermal',accumarray(group,epsilon(:,c),[],@mean));
end
r.PT=struct('correctedSpeed_rpm',grid.Np_rpm,'loadPower_W',grid.load_power_kW*1000, ...
    'epsilonSSThermal',epsilon(:,3),'extrapolationPolicy','continuous_hull_projection');
asset.referenceTable=r;asset.referenceEquilibria=equilibria;
asset.designPoint=equilibria{1};asset.nominal.initialTemperatureState=equilibria{1}.state(3:end);
asset.nominal.epsilonSSCurrent=epsilon(1,:).';
asset.flightBuild.referenceRecomputed=true;asset.flightBuild.createdAt=datestr(now,31);
asset.flightBuild.shaftResidual_rpmps=cellfun(@(e)e.finalMaximumShaftDerivative_rpmps,equilibria);
asset.flightBuild.thermalResidual_Kps=cellfun(@(e)e.finalMaximumThermalDerivative_Kps,equilibria);
parameterAsset=asset;save(targetFile,'parameterAsset','-v7.3');
assert(strcmp(hash(sourceFile),signature.source),'源热资产不应被修改。');
end

function t=local_rows(name,old,value)
t=table(repmat(string(name),numel(old),1),(1:numel(old)).',old,value, ...
    'VariableNames',{'parameter','index','nominal','truth'});
end
function h=local_hash(file)
fid=fopen(file,'rb');assert(fid>=0,'文件不存在：%s',file);c=onCleanup(@()fclose(fid)); %#ok<NASGU>
d=java.security.MessageDigest.getInstance('SHA-256');d.update(typecast(fread(fid,inf,'*uint8'),'int8'));
h=lower(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end
