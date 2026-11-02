function [asset,file]=sht_f31_thermal_truth_asset(base,baseFile,thermalVariant,transientVariant,outputFolder)
% 3.1专用模拟个体热配置。原标称资产只读，不进入2.4/3.3先验。
% 共同偏差与节点差异固定于同一模拟发动机，训练/测试不得重新抽样。
% thermalVariant: structured / shared；transientVariant: enhanced / legacy。
assert(ismember(thermalVariant,{'structured','shared'}),'热配置选择无效。');
assert(ismember(transientVariant,{'enhanced','legacy'}),'瞬态真值选择无效。');
if nargin<5,outputFolder='';end
if base.interface.interfaceVersion==2502
    [asset,file]=local_three(base,baseFile,thermalVariant,transientVariant);
    return;
end
p=fileparts(mfilename('fullpath'));
hash=@(f)sht_f33_model_adapt_v2('fileHash',f);
sourceHash=hash(baseFile);
identity=struct('sourceHash',sourceHash,'programHash',hash([mfilename('fullpath'),'.m']), ...
    'thermalVariant',thermalVariant,'transientVariant',transientVariant);
key=sht_f33_model_adapt_v2('structHash',identity);
folder=fullfile(p,'MiddleData','flight_data_3p1','thermal_truth_assets');
if ~isfolder(folder),mkdir(folder);end
file=fullfile(folder,['visser29_flight_truth_',key,'.mat']);
if isfile(file)
    s=load(file,'parameterAsset');asset=s.parameterAsset;
    assert(isequaln(asset.flightTruth.identity,identity),'个体热资产缓存身份不一致。');
    fprintf('3.1个体热配置命中缓存：%s\n',file);return;
end

function [asset,file]=local_three(base,baseFile,thermalVariant,transientVariant)
% 三部件按物理编号重新定义13项真值，不切片六部件h89:h111。
paths=sht_f3_three_component_assets('paths');folder=fullfile(paths.generation,'thermal_truth');
if ~isempty(outputFolder),folder=outputFolder;end
if ~isfolder(folder),mkdir(folder);end
file=fullfile(folder,['visser16_',thermalVariant,'_',transientVariant,'.mat']);
baseTruth=[.12;-.08;.20;-.12;.25;.15;.15;-.10;.18;-.12;.25;.30;.20];
truth=baseTruth;
if strcmp(transientVariant,'enhanced')
    truth([3,4,5,6,7,8,9,10])=[.30;-.22;.25;-.25;.18;-.15;.22;-.18];
end
if strcmp(thermalVariant,'structured')
    thermalFile=fullfile(folder,'visser16_structured_reference.mat');
    asset=sht_f3_thermal_asset('structured',baseFile,thermalFile,paths);
else
    asset=base;
end
dictionary=sht_health_parameter_dictionary(0);numbers=(58:70).';
names=cellstr(dictionary.name(ismember(dictionary.c_index,numbers)));
asset.truthHealth=zeros(159,1);asset.truthHealth(numbers+1)=truth;
asset.truthHealthMapping=struct('localHealthNumber',numbers,'localMatlabIndex',numbers+1, ...
    'localValue',truth,'localNames',{names});
asset.flightTruth=struct('schemaVersion','F31_THREE_THERMAL_TRUTH_R011', ...
    'role','generation_only','nominalSourceFile',baseFile, ...
    'parameterChanges',asset.flightBuild.parameterChanges, ...
    'sourceTransientHealth',baseTruth,'sameEngineAcrossMissions',true, ...
    'transientChanges',table(numbers,string(names),baseTruth,truth, ...
        'VariableNames',{'c_index','name','old','new'}), ...
    'statement','三部件工程热失配试验；非实物标定或制造公差。');
if isfile(file)
    saved=load(file,'parameterAsset');
    assert(isequaln(saved.parameterAsset.flightBuild.identity,asset.flightBuild.identity) && ...
        isequal(saved.parameterAsset.truthHealth,asset.truthHealth), ...
        'SHT:F3:TruthCache','已有三部件真值身份改变，请另建批次。');
    asset=saved.parameterAsset;return;
end
parameterAsset=asset;save(file,'parameterAsset','-v7.3');
end
asset=base;before=base.nominal;
changeTable=table();
if strcmp(thermalVariant,'structured')
    % 前19项：AC/CC各3节点、燃烧室1节点、GT1/GT2/PT1/PT2各3节点。
    component=[1;1;1;2;2;2;3;4;4;4;5;5;5;6;6;6;7;7;7];
    shape=[-.04;.01;.03;-.03;.02;.04;0;-.04;.01;.03;-.03;.02;.04;-.04;.01;.03;-.03;.02;.04];
    c=[.08;-.06;.10;.07;-.08;.05;-.07];
    h=[-.10;.10;-.12;-.12;.08;.10;-.08];
    factors=struct();
    factors.visserMetalHeatCapacity=1+[c(component)+shape;.10;-.09];
    factors.visserHotGasConductance0=1+[h(component)-shape;-.15;.12];
    factors.visserDiskHeatCapacity=1+[.10;-.08;.12;-.10;.08;-.12];
    factors.visserRootDiskConductance0=1+[.15;-.12;.18;-.15;.12;-.18];
    factors.visserCoolingConductance0=1+[.18;.12;.20;.15;.12;-.15;-.18;-.12;.15;-.10;.08;.14;-.15;.10;.18;.12;-.12;.10;0];
    names=fieldnames(factors);
    for j=1:numel(names)
        name=names{j};old=before.(name)(:);new=old.*factors.(name);
        asset.nominal.(name)=new;
        changeTable=[changeTable;local_rows(name,old,new,'multiplicative')]; %#ok<AGROW>
    end
    % beta是入口/出口总温的权重，不是换热随流量变化的指数。
    delta=[.03;-.02;.04;-.03;.02;-.04;.02;.03;-.02;.04;-.03;.02;-.04;.03;-.02;.04;-.03;.02;-.04;.02;-.02];
    asset.nominal.visserHotGasBeta=before.visserHotGasBeta(:)+delta;
    changeTable=[changeTable;local_rows('visserHotGasBeta',before.visserHotGasBeta(:), ...
        asset.nominal.visserHotGasBeta,'additive')];
end
% 只增强热时间尺度和间隙交换率；两轴惯量真值及转盘共性修正不扩大。
oldHealth=base.truthHealth(:);
if strcmp(transientVariant,'enhanced')
    asset.truthHealth(92:98)=[.30;.30;-.22;.25;.25;-.25;-.25];
    asset.truthHealth(105:112)=[.18;-.15;.18;-.15;.22;.22;-.18;-.18];
    asset.truthHealthMapping.localValue=asset.truthHealth(asset.truthHealthMapping.localMatlabIndex);
    asset.groupedTruth.value=[.04;.05;.30;-.22;.25;-.25;.18;-.15;.22;-.18];
    asset.truthHealthMapping.groupedValue=asset.groupedTruth.value;
end
asset.flightTruth=struct('schemaVersion','F31_THERMAL_TRUTH_V1','role','generation_only', ...
    'identity',identity,'nominalSourceFile',baseFile,'nominalSourceSha256',sourceHash, ...
    'parameterChanges',changeTable,'sourceTransientHealth',oldHealth, ...
    'transientChanges',table((89:111).',string(asset.truthHealthMapping.localNames), ...
    oldHealth(90:112),asset.truthHealth(90:112),'VariableNames', ...
    {'c_index','name','old','new'}),'sameEngineAcrossMissions',true, ...
    'statement','工程模型失配试验；范围不是实物制造公差或后验置信区间。');
asset.generatedAt=datestr(now,31);
configuration=sht_build_thermal_model_configuration(asset);
assert(configuration.parameterCount==178 && asset.nominal.visserCoolingConductance0(19)==0);
assert(isequaln(asset.coolingSplitConfiguration,base.coolingSplitConfiguration));
% 必须先有候选文件才能走已验证的M->DLL初始化接口。候选文件独立保存。
candidate=fullfile(folder,['candidate_',key,'.mat']);
parameterAsset=asset;save(candidate,'parameterAsset','-v7.3');
if strcmp(thermalVariant,'structured')
    asset=local_rebuild_reference(asset,candidate);
end
asset.flightTruth.nominalSourceUnchanged=strcmp(hash(baseFile),sourceHash);
assert(asset.flightTruth.nominalSourceUnchanged,'禁止覆盖标称热参数。');
asset.stepInTemplates=struct();
stages={'baseline','enhanced_ready','heat_state','clearance_diagnostic','joint_full'};
fields={'baseline','enhancedReady','heatState','clearanceDiagnostic','jointFull'};
for j=1:numel(stages),asset.stepInTemplates.(fields{j})=sht_build_transient_step_in_template(asset,stages{j});end
parameterAsset=asset;save(file,'parameterAsset','-v7.3');
fprintf('3.1个体热配置已生成：%s；底层改变%d项。\n',file,height(changeTable));
end

function t=local_rows(name,old,new,mode)
n=numel(old);relative=nan(n,1);nz=old~=0;relative(nz)=(new(nz)-old(nz))./old(nz);
t=table(repmat(string(name),n,1),(1:n).',old,new,new-old,relative, ...
    repmat(string(mode),n,1),'VariableNames',{'field','index','old','new','difference','relative_change','mode'});
end

function asset=local_rebuild_reference(asset,file)
% 不从旧温度重算几何公式冒充新热平衡。按原参考工况网格，以新热网络
% 重新求两轴功率平衡及27个热平衡。仅参考构造关闭间隙反馈，避免自引用。
grid=asset.referenceTable.pointTable;np=grid.targetNp_rpm;power=grid.loadPower_W;
base=sht_default_config(struct('engine',struct('modelMode',1)));
base.engine.boundary.health=zeros(159,1);base.engine.boundary.healthScheduleEnabled=false;
base.engine.healthScheduleProfile=[];
[cfg,~]=sht_configure_transient_visser29(base,'heat_feedback',file,15);
engine=sht_engine_open(cfg.engine);cleanup=onCleanup(@()sht_engine_close(engine)); %#ok<NASGU>
n=height(grid);temperatures=zeros(n,27);ng=zeros(n,1);wf=zeros(n,1);residual=zeros(n,1);
for i=1:n
    % 现有表仅提供工况与数值初猜，不把原金属温度当作新真值。
    guess=[grid.Ng_rpm(i);asset.designPoint.input.Wf_kgps*max(.1,power(i)/power(1)); ...
        grid.metalTemperature_K(i,:).';grid.diskTemperature_K(i,:).'; ...
        grid.metalTemperature_K(i,[8,11]).'];
    seed=sht_get_steady_trim_initial_guess(base,np(i),power(i),'auto');
    if seed.available && seed.isSpecialized
        guess(2)=seed.z(end);
    end
    boundary=cfg.engine.boundary;boundary.health=zeros(159,1);boundary.healthScheduleEnabled=false;
    boundary.ptLoadInputMode='power';boundary.power=power(i);boundary.PTLoadPower_W=power(i);
    if i>1 && np(i)==np(i-1) && power(i)<.5*power(i-1)
        % 极低负载直接改变Ng/Wf可能跨越内层求解域；从上个已收敛点沿
        % 负载连续配平。中间点只是数值初值，不进入参考表或辨识数据。
        guess=[ng(i-1);wf(i-1);temperatures(i-1,:).'];
        loads=exp(linspace(log(power(i-1)),log(power(i)),9));
        for j=2:numel(loads)
            boundary.power=loads(j);boundary.PTLoadPower_W=loads(j);
            [guess,residual(i)]=local_equilibrium(engine,np(i),guess,boundary);
        end
        sol=guess;
    else
        [sol,residual(i)]=local_equilibrium(engine,np(i),guess,boundary);
    end
    ng(i)=sol(1);wf(i)=sol(2);temperatures(i,:)=sol(3:end).';
    fprintf('3.1热参考 %d/%d：Np=%.1f，Ng=%.1f，Wf=%.6f，max残差=%.3e\n', ...
        i,n,np(i),ng(i),wf(i),residual(i));
end
index=find(grid.isDesignAnchor,1);assert(~isempty(index),'缺少设计参考点。');
td=temperatures(index,:);asset.nominal.initialTemperatureState=td(:);
start=[1,4,8,11,14,17];cp=asset.nominal.clearanceParameter;
for c=1:6
    k=start(c);cp(c,7)=td(k+2);cp(c,8)=cp(c,6)*td(k)+(1-cp(c,6))*td(k+1);cp(c,9)=td(19+c);
end
asset.nominal.clearanceParameter=cp;
epsThermal=zeros(n,6);epsFull=zeros(n,6);
for c=1:6
    k=start(c);blade=cp(c,6)*temperatures(:,k)+(1-cp(c,6))*temperatures(:,k+1);
    epsThermal(:,c)=cp(c,1)+cp(c,2)*(temperatures(:,k+2)-cp(c,7))- ...
        cp(c,3)*(blade-cp(c,8))-cp(c,4)*(temperatures(:,19+c)-cp(c,9));
    speed=ng;if c>=5,speed=np;end
    des=asset.referenceTable.designSpeed_rpm(c);
    epsFull(:,c)=epsThermal(:,c)-cp(c,5)*((speed/des).^2-cp(c,10)^2);
end
assert(all(epsFull(:)>0),'新参考间隙非正。');
ref=asset.referenceTable;
ref=local_remove(ref,{'runtimeInterpolationCache','selfCheck'});
ref.centrifugalCoefficient=cp(:,5);ref.referenceNormalizedSpeed=cp(:,10);
tt1=grid.Tt1_K;cnp=np./sqrt(tt1/ref.standardTemperature_K);cng=ng./sqrt(tt1/ref.standardTemperature_K);
names={'AC','CC','GT1','GT2','PT1','PT2'};
for c=1:6
    if c<=4
        [x,~,g]=unique(cng);v=accumarray(g,epsThermal(:,c),[],@mean);
        offset=.03*(max(x)-min(x));x=[x(1)-offset;x;x(end)+offset];v=[v(1);v;v(end)];
        ref.(names{c})=struct('correctedSpeed_rpm',x,'epsilonSSThermal',v);
    else
        [x,~,g]=unique([cnp,power],'rows');v=accumarray(g,epsThermal(:,c),[],@mean);
        hull=convhull(x(:,1),x(:,2));hull=hull(1:end-1);
        offset=[.03,.02].*(max(x)-min(x));extra=zeros(4*numel(hull),2);ev=zeros(4*numel(hull),1);
        for j=1:numel(hull)
            r=(4*j-3):(4*j);extra(r,:)=x(hull(j),:)+[-1,-1;-1,1;1,-1;1,1].*offset;ev(r)=v(hull(j));
        end
        [x,~,g]=unique([x;extra],'rows');v=accumarray(g,[v;ev],[],@mean);
        ref.(names{c})=struct('correctedSpeed_rpm',x(:,1),'loadPower_W',x(:,2),'epsilonSSThermal',v);
    end
end
grid.Np_rpm=np;grid.Ng_rpm=ng;grid.correctedNp_rpm=cnp;grid.correctedNg_rpm=cng;
grid.metalTemperature_K=temperatures(:,1:19);grid.diskTemperature_K=temperatures(:,20:25);
grid.epsilonSSThermal=epsThermal;grid.epsilonSSFull=epsFull;
ref.pointTable=grid;ref.sourceRole='same_operating_grid_recomputed_with_flight_truth_heat_network';
ref.selfCheck=struct('allFinitePositive',true,'pointCount',n,'sourceUsesTruthOutput',false);
[ref,~]=sht_prepare_clearance_reference_lookup(ref);
ref=rmfield(ref,'runtimeInterpolationCache');asset.referenceTable=ref;
asset.flightTruth.referenceRebuild=struct('method','fixed_Np_solve_Ng_Wf_27thermal_states', ...
    'temperature_K',temperatures,'Ng_rpm',ng,'Wf_kgps',wf,'maximumScaledResidual',residual, ...
    'individualCorrectionsZero',true,'clearanceFeedbackDisabled',true, ...
    'shaftTolerance_rpmps',1e-3,'temperatureTolerance_Kps',1e-5, ...
    'passed',all(residual<1e-5));
end

function [sol,err]=local_equilibrium(engine,np,guess,boundary)
% 29个未知量：Ng、Wf、27温度。残差：两轴加速度/100与27温度导数。
scale=[38000;.15;1000*ones(27,1)];q=guess./scale;
for iteration=1:18
    r=local_residual(engine,np,q.*scale,boundary);err=max(abs(r));
    % 与最终验收相同：轴加速度<1e-3 rpm/s，温度导数<1e-5 K/s。
    % 不在已达精度时追逐DLL内层数值噪声。
    if err<1e-5,break;end
    J=zeros(29);
    for j=1:29
        dq=1e-5;qp=q;qp(j)=qp(j)+dq;
        J(:,j)=(local_residual(engine,np,qp.*scale,boundary)-r)/dq;
    end
    delta=-(J\r);accepted=false;
    for fraction=2.^(0:-1:-10)
        trial=q+fraction*delta;s=trial.*scale;
        if s(1)<15000||s(1)>45000||s(2)<=.005||s(2)>.5||any(s(3:end)<150|s(3:end)>2300),continue;end
        try,rr=local_residual(engine,np,s,boundary);catch,continue;end
        if norm(rr)<norm(r),q=trial;accepted=true;break;end
    end
    assert(accepted,'3.1热参考物理Newton求解停滞，残差%.6g。',err);
end
sol=q.*scale;err=max(abs(local_residual(engine,np,sol,boundary)));
assert(err<1e-5,'3.1热参考未收敛，残差%.6g。',err);
end

function r=local_residual(engine,np,sol,boundary)
[dx,~,d]=sht_engine_derivative(engine,[np;sol(1);sol(3:end)],sol(2),boundary);
assert(d.ret==0&&d.convergeTag==0&&d.maxErr<1e-5&&numel(dx)==29&&all(isfinite(dx)), ...
    '3.1参考点DLL状态无效：Np=%.1f，Ng=%.1f，Wf=%.6f，ret=%g，tag=%g，maxErr=%.3e。', ...
    np,sol(1),sol(2),d.ret,d.convergeTag,d.maxErr);
r=[dx(1:2)/100;dx(3:end)];
end

function s=local_remove(s,fields)
for i=1:numel(fields),if isfield(s,fields{i}),s=rmfield(s,fields{i});end,end
end
