function result=Start_TC27_UQ_NewConditionPrediction_01(request)
%START_TC27_UQ_NEWCONDITIONPREDICTION_01 联合后验样本的新工况物理预测。
% fuelInputKind必须显式为physical或measured。物理燃油直接入发动机；
% 只有测量燃油才用同一后验样本的燃油偏置曲线作一次校正。
required={'modelFile','identityFile','posteriorFile','conditions', ...
    'outputDirectory','fuelInputKind'};
assert(nargin==1&&isstruct(request)&&isscalar(request),'TC27:UQ:PredictRequest', ...
    '请传入单个预测任务结构体。');
for j=1:numel(required)
    assert(isfield(request,required{j})&&~isempty(request.(required{j})), ...
        'TC27:UQ:PredictInput','缺少%s。',required{j});
end
fuelKind=char(string(request.fuelInputKind));
assert(ismember(fuelKind,{'physical','measured'}),'TC27:UQ:FuelKind', ...
    '燃油输入必须明确指定physical或measured。');
model=sht_tc27_delivery('read',[],request.modelFile);
id=jsondecode(fileread(request.identityFile));
package=sht_tc27_runtime_package();
assert(strcmp(id.schema,'TC27_MODEL_IDENTITY_V1')&& ...
    strcmpi(id.modelSHA256,sht_tc27_file_identity(request.modelFile))&& ...
    strcmpi(id.dllSHA256,sht_tc27_file_identity(fullfile(package.directory,'GTESS.dll'))) ...
    &&strcmp(id.route,model.route)&&strcmp(id.method,model.method)&& ...
    id.modelMode==model.modelMode&&id.thermalMode==model.thermalMode&& ...
    strcmp(id.runtimePackageId,package.id)&& ...
    strcmpi(id.thermalSHA256,sht_tc27_file_identity(package.thermalFile)), ...
    'TC27:UQ:PredictModel','确定性模型及运行包身份不匹配。');
posterior=sht_tc27_uq_delivery('read',request.posteriorFile);
keys=string(posterior.manifest.key);values=string(posterior.manifest.value);
source=values(keys=="source_model_sha256");
route=values(keys=="source_model_route");method=values(keys=="source_model_method");
assert(isscalar(source)&&strcmpi(char(source),model.sha256)&& ...
    isscalar(route)&&strcmp(char(route),model.route)&& ...
    isscalar(method)&&strcmp(char(method),model.method), ...
    'TC27:UQ:PredictPosterior','后验Excel不是所选确定性模型的后验。');
physicalKeys=["source_model_identity_sha256","runtime_package_id", ...
    "runtime_manifest_sha256","thermal_sha256","model_mode","thermal_mode"];
physicalValues=[string(sht_tc27_file_identity(request.identityFile)),string(package.id), ...
    string(sht_tc27_file_identity(package.manifestFile)), ...
    string(sht_tc27_file_identity(package.thermalFile)), ...
    string(model.modelMode),string(model.thermalMode)];
for k=1:numel(physicalKeys)
    match=values(keys==physicalKeys(k));
    assert(isscalar(match)&&strcmpi(match,physicalValues(k)), ...
        'TC27:UQ:PredictPosteriorPhysicalIdentity', ...
        '后验Excel缺少或不匹配物理资产身份：%s。不能将旧后验改签为当前模型。', ...
        char(physicalKeys(k)));
end
data=request.conditions;
if ischar(data)||isstring(data)
    assert(isfile(char(data)),'TC27:UQ:Conditions','新工况文件不存在。');
    data=readtable(char(data));
end
base={'point_id','Pt1_Pa','Tt1_K','Pamb_Pa','Tamb_K', ...
    'Altitude_m','Mach','Mkp_Nm'};
if strcmp(fuelKind,'physical'),fuelName='Wf_model_kg_s';
else,fuelName='Wf_measured_kg_s';end
assert(istable(data)&&height(data)>0&& ...
    all(ismember([base,{fuelName}],data.Properties.VariableNames))&& ...
    ~ismember('Np',data.Properties.VariableNames)&& ...
    ~ismember('Ng',data.Properties.VariableNames), ...
    'TC27:UQ:Conditions','缺少新工况输入，或错误提供了目标转速。');
if ~ismember('Mkg_Nm',data.Properties.VariableNames),data.Mkg_Nm=zeros(height(data),1);end
numericNames=[base(2:end),{fuelName,'Mkg_Nm'}];
for j=1:numel(numericNames)
    q=data.(numericNames{j});
    assert(isnumeric(q)&&all(isfinite(q)),'TC27:UQ:Conditions', ...
        '输入%s必须有限。',numericNames{j});
end
assert(all(data.Pt1_Pa>0)&all(data.Tt1_K>0)& ...
    all(data.(fuelName)>0)&all(data.Mkp_Nm>=0)& ...
    numel(unique(string(data.point_id)))==height(data), ...
    'TC27:UQ:Conditions','新工况物理边界或编号无效。');
directory=sht_tc27_canonical_path(request.outputDirectory);
assert(isfolder(fileparts(directory))&&~isfolder(directory)&&~isfile(directory), ...
    'TC27:UQ:PredictOutput','预测必须写到新的独立输出目录。');
ids=1:size(posterior.theta,2);subset=false;
if isfield(request,'sampleIds')&&~isempty(request.sampleIds)
    ids=request.sampleIds(:).';subset=true;
    assert(all(ids>=1)&all(ids<=size(posterior.theta,2))& ...
        all(ids==floor(ids))&&numel(unique(ids))==numel(ids), ...
        'TC27:UQ:SampleIds','样本行号非法。');
end
weights=posterior.weights(ids);weights=weights/sum(weights);
if isfield(posterior,'nuisanceSamples')
    nuisance=posterior.nuisanceSamples(:,ids);
    nuisanceMode='joint_samples';
elseif isfield(posterior,'nuisanceConditionalMean')
    nuisance=posterior.nuisanceConditionalMean(:,ids);
    nuisanceMode='conditional_mean_and_local_covariance';
else
    error('TC27:UQ:NuisanceMissing','后验缺少与主样本成对的附加参数信息。');
end
assert(size(nuisance,1)==height(posterior.nuisancePrior), ...
    'TC27:UQ:NuisanceDictionary','附加参数与交付字典维数不符。');
conditionalFactor=[];
if strcmp(nuisanceMode,'conditional_mean_and_local_covariance')
    assert(isfield(posterior,'nuisanceConditionalCovariance'), ...
        'TC27:UQ:NuisanceCovariance','D后验缺少附加参数条件协方差。');
    covariance=posterior.nuisanceConditionalCovariance;
    [basis,eigenvalues]=eig((covariance+covariance.')/2);
    scale=max(norm(covariance,'fro'),realmin);
    assert(min(diag(eigenvalues))>=-1e-9*scale, ...
        'TC27:UQ:NuisanceCovariance','条件协方差不是半正定。');
    conditionalFactor=basis*diag(sqrt(max(diag(eigenvalues),0)));
end
mkdir(directory);timer=tic;
cfg=sht_tc27_config(model.thermalMode,'joint_full');
engine=sht_engine_open(cfg.engine);cleanup=onCleanup(@()sht_engine_close(engine));
names={'Np_rpm','Ng_rpm','Pt3_Pa','Tt3_K','Pt45_Pa','Tt45_K', ...
    'Pt6_Pa','Tt6_K','Wa2_kg_s'};
values=nan(height(data),numel(names),numel(ids));valid=false(height(data),numel(ids));
usedFuel=nan(height(data),numel(ids));
[~,referenceSample]=max(weights);
conditionalVariance=zeros(height(data),numel(names));
conditionalVarianceValid=false(height(data),1);
for sample=1:numel(ids)
    s=sht_steady_model_adapt_v2_common('m3nodestoschedule', ...
        posterior.contract,posterior.theta(:,ids(sample)));
    s.designHealth(posterior.nuisancePrior.c_index+1)=nuisance(:,sample);
    sht_health_schedule_initialize_dll(engine,sht_tc27_schedule_profile(s),s.designHealth);
    for rowIndex=1:height(data)
        row=data(rowIndex,:);fuel=row.(fuelName);
        if strcmp(fuelKind,'measured')
            curve=s.fuelBias;x=min(max(fuel/curve.wfDesign,min(curve.xNodes)),max(curve.xNodes));
            if numel(curve.xNodes)==1,bias=curve.biasNodes(1);
            else,bias=interp1(curve.xNodes,curve.biasNodes,x,'linear');end
            fuel=fuel-bias;
        end
        usedFuel(rowIndex,sample)=fuel;
        % 个别后验样本的校正燃油无效时，保留其无效概率质量，不中断整批。
        if ~(isfinite(fuel)&&fuel>0),continue;end
        point=table(string(row.point_id),fuel,row.Mkp_Nm,row.Tamb_K, ...
            row.Mach,row.Mkg_Nm,row.Pamb_Pa,row.Altitude_m, ...
            'VariableNames',{'point_id','Wf_mean','Mkp_mean','Tamb_mean', ...
            'Mach_mean','Mkg_mean','Pamb_mean','Altitude_mean'});
        [branch,~]=sht_np_branch_delivery('query',model.npBranchModel,point,1);
        state=cfg.engine.initial.state;bounds=[5000,70000;5000,70000];
        if branch.Np_branch_available
            state(1)=branch.Np_branch_center_rpm;
            bounds(1,:)=[branch.Np_branch_lower_rpm,branch.Np_branch_upper_rpm];
        end
        boundary=cfg.engine.boundary;boundary.inletBoundaryMode=1;
        boundary.Pt1=row.Pt1_Pa;boundary.Tt1=row.Tt1_K;
        boundary.Pamb=row.Pamb_Pa;boundary.Tamb=row.Tamb_K;
        boundary.altitude=row.Altitude_m;boundary.Mach=row.Mach;
        boundary.Mkp=row.Mkp_Nm;boundary.Mkg=row.Mkg_Nm;
        boundary.ptLoadInputMode='torque';boundary.gtLoadInputMode='torque';
        boundary.health=s.designHealth(:);boundary.healthScheduleEnabled=1;
        inConditionalDifference=false;
        try
            q=sht_thermal_equilibrium_solve(engine,state,fuel,boundary,'steady_predict', ...
                struct('maximumIterations',20,'maximumCommonWorkRetries',2, ...
                'finalJacobianAudit',false,'speedBounds_rpm',bounds));
            y=q.output;valid(rowIndex,sample)=q.physicalValid;
            if q.physicalValid
                values(rowIndex,:,sample)=[y.Np,y.Ng,y.Pt3,y.Tt3,y.Pt45, ...
                    y.Tt45,y.Pt5,y.Tt5,y.WIn];
                if sample==referenceSample&&~isempty(conditionalFactor)
                    inConditionalDifference=true;
                    gradient=zeros(numel(names),height(posterior.nuisancePrior));
                    baseValue=reshape(values(rowIndex,:,sample),[],1);
                    for parameter=1:height(posterior.nuisancePrior)
                        delta=.2*posterior.nuisancePrior.sigma(parameter);
                        current=nuisance(parameter,sample);
                        if current+delta>posterior.nuisancePrior.upper(parameter),delta=-delta;end
                        assert(delta~=0&&current+delta>=posterior.nuisancePrior.lower(parameter), ...
                            'TC27:UQ:NuisanceDifference','附加参数局部差分无法留在边界内。');
                        perturbed=boundary;
                        index=posterior.nuisancePrior.c_index(parameter)+1;
                        perturbed.health(index)=perturbed.health(index)+delta;
                        derivative=sht_thermal_equilibrium_solve(engine,state,fuel, ...
                            perturbed,'steady_predict',struct('maximumIterations',20, ...
                            'maximumCommonWorkRetries',2,'finalJacobianAudit',false, ...
                            'speedBounds_rpm',bounds));
                        assert(derivative.physicalValid,'TC27:UQ:NuisanceDifference', ...
                            '附加参数条件方差传播的物理差分失败。');
                        z=derivative.output;
                        shifted=[z.Np;z.Ng;z.Pt3;z.Tt3;z.Pt45; ...
                            z.Tt45;z.Pt5;z.Tt5;z.WIn];
                        gradient(:,parameter)=(shifted-baseValue)/delta;
                    end
                    conditionalVariance(rowIndex,:)=sum((gradient*conditionalFactor).^2,2);
                    assert(all(isfinite(conditionalVariance(rowIndex,:))), ...
                        'TC27:UQ:NuisanceDifference','附加参数条件方差不是有限值。');
                    conditionalVarianceValid(rowIndex)=true;
                    inConditionalDifference=false;
                end
            end
        catch failure
            local_handle_replay_failure(failure,inConditionalDifference);
        end
    end
end

if ~isempty(conditionalFactor)
    assert(all(valid(:,referenceSample))&&all(conditionalVarianceValid), ...
        'TC27:UQ:NuisanceReference', ...
        'D后验的参考样本或附加参数条件方差存在无效工况，不能将其方差当作零。');
end
summary=table();
for rowIndex=1:height(data)
    matrix=reshape(values(rowIndex,:,:),numel(names),numel(ids));
    [meanValue,lower,upper,mass]=sht_tc27_uq_mixture_interval( ...
        matrix,conditionalVariance(rowIndex,:).',weights);
    block=table(repmat(string(data.point_id(rowIndex)),numel(names),1), ...
        string(names(:)),meanValue,lower,upper,mass, ...
        'VariableNames',{'point_id','output','posterior_mean', ...
        'q025','q975','valid_posterior_mass'});
    summary=[summary;block]; %#ok<AGROW>
end
quality='joint_nuisance_samples';
if ~isempty(conditionalFactor),quality='local_nuisance_covariance_propagated';end
if subset,quality=[quality,'_selected_sample_diagnostic_not_formal'];end
result=struct('status','completed','quality',quality,'fuelInputKind',fuelKind, ...
    'sourceModelSHA256',model.sha256,'posteriorSHA256', ...
    sht_tc27_file_identity(request.posteriorFile),'sampleIds',ids, ...
    'weights',weights,'conditions',data,'usedPhysicalFuel_kg_s',usedFuel, ...
    'values',values,'valid',valid,'nuisanceMode',nuisanceMode, ...
    'conditionalVariance',conditionalVariance,'summary',summary,'elapsed_s',toc(timer));
file=fullfile(directory,'tc27_uq_new_condition_prediction.xlsx');
writetable(summary,file,'Sheet','PredictionIntervals');
result.resultFile=file;
save(fullfile(directory,'tc27_uq_new_condition_prediction.mat'),'result','-v7.3');
end

function local_handle_replay_failure(failure,inConditionalDifference)
% 基础回放可记无效样本；条件方差差分失败不能伪装成零方差。
if inConditionalDifference,rethrow(failure);end
known={'TC27:Replay:InitialThermal','TC27:Replay:Fuel', ...
    'TC27:Replay:ModelFailure'};
if ~ismember(failure.identifier,known)&& ...
        ~startsWith(failure.identifier,'SHT:ThermalEquilibrium:')
    rethrow(failure);
end
end
