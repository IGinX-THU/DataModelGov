function output=sht_f34_method_d_artifacts(action,varargin)
%SHT_F34_METHOD_D_ARTIFACTS 无方法C依赖的局部D结果、区间图和Excel消费者。
% 正式Excel保存解析局部联合矩，不伪造SMC粒子；真值/测试表只写报告目录。
switch lower(action)
    case 'write'
        output=local_write(varargin{:});
    case 'read'
        output=local_read(varargin{:});
    case 'inspect'
        % Excel内的局部矩可以单独查看；不打开DLL，也不声称已核运行资产。
        output=local_read(varargin{1},'');
    case 'nodeplots'
        output=local_refresh_node_plots(varargin{:});
    case 'model'
        package=varargin{1};joint=varargin{2};
        n=height(package.context.parameterContract);
        m=sht_f33_model_adapt_v2('thetaToModels',package.context,joint(1:n));
        m.schedules{1}=sht_f34_prior('applyShape',m.schedules{1}, ...
            struct('shape',package.shape),joint(n+1:end));
        output=m;
    case 'predictpoints'
        % DLL求值会切换到公共运行资产目录。显式保留M入口目录，
        % 使全新进程不依赖先运行辨识程序留下的搜索路径。
        addpath(fileparts(mfilename('fullpath')));
        package=varargin{1};points=varargin{2};branch=varargin{3};
        joint=package.distribution.jointMean;
        if numel(varargin)>=4,joint=varargin{4};end
        models=sht_f34_method_d_artifacts('model',package,joint);
        session=sht_f33_thermal_equilibrium('open',package.assets,branch,points,'steady');
        cleanup=onCleanup(@()sht_f33_thermal_equilibrium('close',session)); %#ok<NASGU>
        output=sht_f33_thermal_equilibrium('batch',session,models.schedules,models.recoveries);
    otherwise
        error('SHT:F34DArtifacts:Action','未知操作%s。',action);
end
end

function files=local_write(p,L,D,pred,reportOptions)
if nargin<5,reportOptions=struct();end
folder=p.paths.reportDir;parameter=D.parameterTable;n=height(parameter);
[priorMean,priorCov]=sht_f34_prior('moments',p.prior);
comparison=D.summary;
comparison.prior_mean=priorMean;comparison.prior_std=sqrt(diag(priorCov));
comparison.deterministic=p.context.uqReferenceResult.estimatedTheta(:);
comparison.interval_crosses_bounds=D.intervalCrossesBounds;
% 报告真值仅在估计冻结后读取，且先核验对应R020确定性坐标，防止误选路线。
truthFile=''; % 合成真值不是正式运行依赖。
if isfield(reportOptions,'truthComparisonFile'),truthFile=reportOptions.truthComparisonFile;end
comparison.truth_equivalent=nan(n,1);comparison.truth_representation_rmse=nan(n,1);
if isfile(truthFile)
    t=readtable(truthFile);
    t=t(string(t.variant)=="transient_steady_only",:);
    for i=1:n
        row=find(string(t.parameter_id)==string(parameter.parameter_id(i)));
        if numel(row)==1&&abs(t.estimate(row)-comparison.deterministic(i))<1e-12
            comparison.truth_equivalent(i)=t.truth_training(row);
            comparison.truth_representation_rmse(i)=t.truth_projection_representation_rmse(row);
        end
    end
end
comparison.deterministic_error=comparison.deterministic-comparison.truth_equivalent;
comparison.d_error=D.map-comparison.truth_equivalent;
comparison.truth_in_local_interval=comparison.truth_equivalent>=D.interval95(:,1)& ...
    comparison.truth_equivalent<=D.interval95(:,2);
writetable(comparison,fullfile(folder,'D_all_parameters.csv'));
writetable(struct2table(D.trace),fullfile(folder,'D_iterations.csv'));
writetable(D.nonlinearity,fullfile(folder,'D_local_nonlinearity.csv'));
if ~isempty(pred)
writetable(pred.summary,fullfile(folder,'D_prediction_summary.csv'));
writetable(pred.baselineComparison,fullfile(folder,'D_baseline_output_comparison.csv'));
detail=pred.detail;detail.observed=zeros(height(detail),1);
channels={'Np','Ng','Pt3_eq','Tt45'};columns={'Np_mean','Ng_mean','Pt3_mean','Tt45_mean'};
units={'rpm','rpm','Pa','K'};
for i=1:height(detail)
    row=find(string(pred.testData.point_id)==string(detail.point_id(i)));
    col=find(strcmp(channels,char(detail.channel(i))));
    detail.observed(i)=pred.testData.(columns{col})(row);
end
detail.error=detail.mean-detail.observed;
writetable(detail,fullfile(folder,'D_prediction_points.csv'));
end
writetable(p.prior.summary,fullfile(folder,'D_prior_summary.csv'));
writetable(p.context.steadySource,fullfile(folder,'D_training_windows.csv'));
if ~isempty(pred),writetable(pred.testSource,fullfile(folder,'D_test_windows.csv'));end

% 条件形状均值随显式参数变化，必须在节点协方差中保留该交叉项。
z=D.conditionalShapeMean(:);rankValue=numel(z);Z=zeros(rankValue,n);
trainingTheta=[zeros(n,1),comparison.deterministic,D.map];
trainingShape=[zeros(rankValue,2),z];
training=sht_f34_likelihood('evaluatePhysicalShape',p.context,p.prior,trainingTheta,trainingShape);
assert(all(training.valid),'冻结后的训练输出诊断物理解无效。');
trainingLabels={'TC24_deterministic','current_deterministic','D_local_center'};
if strcmp(p.context.options.priorSource,'flight'),trainingLabels{1}='parent_flight_deterministic';end
trainingSummary=table();np=height(p.context.steadyData);
for a=1:3
    for j=1:4
        index=(j-1)*np+(1:np);e=training.output(index,a)-L.observation(index);
        u={'Pa','K','rpm/s','rpm/s'};
        if strcmp(p.context.options.modelRoute,'steady'),u={'rpm','rpm','Pa','K'};end
        trainingSummary=[trainingSummary;table(string(trainingLabels{a}), ...
            string(L.observationChannels{j}),string(u{j}),sqrt(mean(e.^2)),mean(e), ...
            'VariableNames',{'model','channel','unit','rmse','mean_error'})]; %#ok<AGROW>
    end
end
writetable(trainingSummary,fullfile(folder,'D_training_output_comparison.csv'));
for i=1:n
    trial=D.map;step=D.differenceStep(i);trial(i)=trial(i)+step;
    [ev,~,physical]=sht_f34_likelihood('evaluate',L,p.context,p.prior,trial);
    assert(ev.valid,'最终条件形状导数候选无效。');
    zi=sht_f34_likelihood('conditionalPosterior',L,p.prior,trial,physical(:,1));
    Z(:,i)=(zi-z)/step;
end
jointMean=[D.map;z];
jointCov=[D.covariance,D.covariance*Z.'; ...
    Z*D.covariance,D.conditionalShapeCovariance+Z*D.covariance*Z.'];
jointCov=(jointCov+jointCov.')/2;
nodeMap=p.prior.shape.nodeMap;
models=sht_f33_model_adapt_v2('thetaToModels',p.context,D.map);
baseline=local_nodes(models.schedules{1},nodeMap);
nodeMean=baseline+p.prior.shape.basis*z;
J=zeros(height(nodeMap),n);
for i=1:n
    trial=D.map;trial(i)=trial(i)+D.differenceStep(i);
    m=sht_f33_model_adapt_v2('thetaToModels',p.context,trial);
    J(:,i)=(local_nodes(m.schedules{1},nodeMap)-baseline)/D.differenceStep(i);
end
nodeResponse=[J,p.prior.shape.basis];nodeCov=nodeResponse*jointCov*nodeResponse.';
nodeStd=sqrt(max(diag(nodeCov),0));nodes=nodeMap;
nodes.mean_local=nodeMean;nodes.std_local=nodeStd;
nodes.lower95_local=nodeMean-1.95996398454*nodeStd;
nodes.upper95_local=nodeMean+1.95996398454*nodeStd;
writetable(nodes,fullfile(folder,'D_physical_node_intervals.csv'));
% 显式幅值不等于最终物理K，必须另列加上条件形状后的曲线实际误差。
% 比较坐标沿用冻结后的独立真值诊断，不参与模型或先验构造。
physicalFile=fullfile(fileparts(truthFile),'physical_parameters_at_points.csv');
if ~isempty(truthFile)&&isfile(physicalFile)&&all(isfinite(comparison.truth_equivalent))
    physical=readtable(physicalFile);physical.d_local=nan(height(physical),1);
    model=sht_f34_prior('applyShape',models.schedules{1},p.prior,z);
    for i=1:height(physical)
        name=char(physical.parameter(i));x=physical.coordinate(i);
        if strcmp(name,'K_dist_eq'),value=0.995-models.recoveries;
        elseif strcmp(name,'Wf_bias')
            value=local_interp(model.fuelBias.xNodes,model.fuelBias.biasNodes,x);
        else
            entry=find([model.healthEntries.cIndex]==str2double(name(2:end)),1);
            value=local_interp(model.healthEntries(entry).xNodes,model.healthEntries(entry).kNodes,x);
        end
        physical.d_local(i)=value;
    end
    physical.d_error=physical.d_local-physical.truth;
    writetable(physical,fullfile(folder,'D_physical_parameters_at_points.csv'));
    groups=unique(physical(:,{'dataset','parameter','unit'}),'rows','stable');
    for i=1:height(groups)
        q=physical(string(physical.dataset)==string(groups.dataset(i))& ...
            string(physical.parameter)==string(groups.parameter(i)),:);
        groups.truth_mean(i)=mean(q.truth);
        groups.prior_rmse(i)=sqrt(mean((q.prior-q.truth).^2));
        groups.deterministic_rmse(i)=sqrt(mean((q.estimate-q.truth).^2));
        groups.d_rmse(i)=sqrt(mean(q.d_error.^2));
    end
    writetable(groups,fullfile(folder,'D_physical_parameter_rmse.csv'));
end

% 正式消费者仅需要模型基准、局部联合矩和物理映射。计算/测试证据另存。
distribution=struct('schema','F34_LOCAL_D_GAUSSIAN_V1', ...
    'explicitDimension',n,'jointMean',jointMean,'jointCovariance',jointCov, ...
    'shapeBasis',p.prior.shape.basis,'shapeFullProcessCovariance',p.prior.shape.fullProcessCovariance, ...
    'explicitLowerBound',parameter.lower_bound,'explicitUpperBound',parameter.upper_bound, ...
    'intervalInterpretation',D.intervalInterpretation, ...
    'qualityLevel',D.qualityLevel,'converged',D.converged, ...
    'statisticalCalibrationConfirmed',false,'processCovarianceCalibrated',false, ...
    'shapeRetainedFraction',p.prior.shape.retainedSecondMomentFraction);
if isfield(p.prior,'nodePrior')
    distribution.nextFlightJointCovariance=p.prior.nodePrior.jointNextFlightCovariance;
    distribution.parameterization='independent_nodes';
    distribution.priorBoundPolicy=p.prior.nodePrior.boundPolicy;
end
q=p.options;fields=fieldnames(q);fields=fields(startsWith(fields,'flightToFlight'));
distribution.nextFlightAssumptions=struct();
for i=1:numel(fields),distribution.nextFlightAssumptions.(fields{i})=q.(fields{i});end
payload=sht_f34_deployment('tables',p);
manifest=table("F34_LOCAL_D_EXCEL_V1","D",string(p.context.options.modelRoute), ...
    string(p.options.runTag),string(p.contract.trainingEvidenceSha256), ...
    string(p.contract.sourcePosteriorSha256),string(L.contractHash), ...
    string(p.options.engineId),string(p.options.sortieId),D.converged,false, ...
    'VariableNames',{'schema_version','method','model_route','run_id', ...
    'training_evidence_sha256','source_posterior_sha256','likelihood_sha256', ...
    'engine_id','sortie_id','converged','statistical_calibration_confirmed'});
if isfield(p.options,'businessIdentity')
    binding=p.options.businessIdentity;
    manifest.parent_model_id=string(binding.parentModelId);
    manifest.parent_posterior_id=string(binding.parentPosteriorId);
    manifest.current_model_id=string(binding.currentModelId);
    manifest.business_identity_purpose=string(binding.purpose);
end
text=jsonencode(distribution);count=ceil(numel(text)/24000);chunk=strings(count,1);
for i=1:count,chunk(i)=string(text((i-1)*24000+1:min(i*24000,numel(text))));end
tables=struct('Manifest',manifest,'ParameterDictionary',parameter, ...
    'LocalDistribution',table((1:count).',chunk,'VariableNames',{'chunk_id','json_text'}), ...
    'ShapeNodeMap',nodeMap,'ModelState',payload.ModelState,'RuntimeAssets',payload.RuntimeAssets);
if isfield(p.options,'businessIdentity')
    tables.BusinessIdentity=sht_f3_business_identity('table',p.options.businessIdentity);
end
workbook=fullfile(p.paths.runDir,'3p4_method_D_local_delivery.xlsx');
temporary=[tempname(p.paths.runDir),'.xlsx'];names=fieldnames(tables);
for i=1:numel(names),writetable(tables.(names{i}),temporary,'Sheet',names{i});end
runtime=p.context.replayAssets.configuration.engine.interface.controlDir;
restored=local_read(temporary,runtime);
assert(max(abs(restored.distribution.jointMean-jointMean))<1e-12,'Excel均值恢复不一致。');
assert(max(abs(restored.distribution.jointCovariance(:)-jointCov(:)))<1e-12,'Excel协方差恢复不一致。');
if isfile(workbook)
    old=local_read(workbook,runtime);
    assert(isequaln(old.distribution,restored.distribution),'旧交付与当前结果不同，禁止覆盖。');
    delete(temporary);
else
    movefile(temporary,workbook);
end
files=struct('workbook',workbook,'workbookSha256', ...
    sht_f33_model_adapt_v2('fileHash',workbook),'reportFolder',folder);
files.truthComparisonAvailable=all(isfinite(comparison.truth_equivalent));
if isfield(p.prior,'nodePrior')
    fig=local_node_plot(nodes,D,p.context.priorSchedule);
    actual=parameter;idx=p.prior.nodePrior.selectedPhysicalIndices;
    actual.reference_value=zeros(n,1);valid=idx<=height(nodes);
    actual.reference_value(valid)=nodes.reference_value(idx(valid));
    actual.mean_local=actual.reference_value+D.map;
    actual.lower95_local=actual.reference_value+D.interval95(:,1);
    actual.upper95_local=actual.reference_value+D.interval95(:,2);
    actual.std_local=D.standardDeviation;
    writetable(actual,fullfile(folder,'D_actual_active_node_intervals.csv'));
else
fig=figure('Visible','off','Color','w','Position',[50 50 1200 750]);
for i=1:n
    subplot(ceil(n/4),4,i);hold on;
    errorbar(1,D.map(i),D.standardDeviation(i)*1.95996398454,'o','LineWidth',1.3);
    plot(1,comparison.deterministic(i),'ks','MarkerFaceColor','k');
    if isfinite(comparison.truth_equivalent(i)),yline(comparison.truth_equivalent(i),'r--');end
    yline(priorMean(i),':','Color',[.35 .35 .35]);
    title(char(parameter.parameter_id(i)),'Interpreter','none');ylabel(char(parameter.unit(i)));
    xlim([.5 1.5]);set(gca,'XTick',[]);grid on;
end
sgtitle('Method D: local normal reference, not calibrated posterior quantiles');
end

files.parameterFigure=fullfile(folder,'D_parameter_intervals.png');
print(fig,files.parameterFigure,'-dpng','-r150');close(fig);
if ~isempty(pred)
fig=figure('Visible','off','Color','w','Position',[50 50 1100 700]);
for c=1:4
    subplot(2,2,c);hold on;
    q=detail(string(detail.prediction_mode)=="fixed_transfer"& ...
        string(detail.interval_layer)=="observable"&string(detail.channel)==channels{c},:);
    x=(1:height(q)).';
    errorbar(x,q.mean,q.mean-q.lower95,q.upper95-q.mean,'bo','LineWidth',1.2);
    plot(x,q.observed,'rx','LineWidth',1.5);title(channels{c},'Interpreter','none');
    ylabel(units{c});xlabel('Independent steady point');grid on;
    xlim([.7 height(q)+.3]);set(gca,'XTick',1:height(q));
end
sgtitle('Fixed transfer: observable local intervals and measured steady means');
files.predictionFigure=fullfile(folder,'D_test_prediction_intervals.png');
print(fig,files.predictionFigure,'-dpng','-r150');close(fig);
end
save(fullfile(p.paths.runDir,'method_d_delivery_audit.mat'),'files','distribution','nodes','comparison','-v7.3');
if ~isempty(pred)
inputs=pred.excelVerificationInputs;
inputs.expectedPrediction=pred.methodD.fixed_transfer.observable.mean;
inputs.runtime=runtime; %#ok<NASGU>
save(fullfile(p.paths.runDir,'excel_verification_inputs.mat'),'inputs','-v7.3');
end
end

function files=local_refresh_node_plots(workbook,runtime,folder)
% 已完成结果的图表必须直接从冻结Excel恢复，不重算局部导数/协方差，
% 避免冷/暖启动的浮点差异使同一结果被重新估计或覆盖。
package=local_read(workbook,runtime);p=package.context.parameterContract;
assert(all(ismember(string(p.kind),["health_node","fuel_bias_node","sortie_nuisance"])), ...
    '该动作只接受独立节点D交付。');
n=height(p);map=package.shape.nodeMap;m=height(map);
A=zeros(m,numel(package.distribution.jointMean));
reference=zeros(n,1);
for j=1:n
    if p.kind(j)=="health_node"
        row=find(map.kind=="health"&map.c_index==p.c_index(j)&map.node_index==p.node_index(j));
    elseif p.kind(j)=="fuel_bias_node"
        row=find(map.kind=="fuel_bias"&map.node_index==p.node_index(j));
    else,continue;
    end
    assert(numel(row)==1);A(row,j)=1;reference(j)=map.reference_value(row);
end
A(:,n+1:end)=package.shape.basis;
mu=package.distribution.jointMean;V=package.distribution.jointCovariance;
nodes=map;nodes.mean_local=map.reference_value+A*mu;
nodes.std_local=sqrt(max(diag(A*V*A.'),0));
nodes.lower95_local=nodes.mean_local-1.95996398454*nodes.std_local;
nodes.upper95_local=nodes.mean_local+1.95996398454*nodes.std_local;
D=struct('parameterTable',p,'map',mu(1:n),'standardDeviation',sqrt(diag(V(1:n,1:n))));
fig=local_node_plot(nodes,D,package.context.priorSchedule);
file=fullfile(folder,'D_parameter_intervals.png');print(fig,file,'-dpng','-r150');close(fig);
actual=p;actual.reference_value=reference;actual.mean_local=reference+D.map;
actual.std_local=D.standardDeviation;
actual.lower95_local=actual.mean_local-1.95996398454*actual.std_local;
actual.upper95_local=actual.mean_local+1.95996398454*actual.std_local;
writetable(actual,fullfile(folder,'D_actual_active_node_intervals.csv'));
writetable(nodes,fullfile(folder,'D_physical_node_intervals.csv'));
files=struct('parameterFigure',file,'requiresTruth',false,'source','frozen_Excel_only');
end

function fig=local_node_plot(nodes,D,schedule)
% 画实际修正系数，不把相对参考曲线的增量误标成物理K。
fig=figure('Visible','off','Color','w','Position',[30 30 1400 1050]);
ids=[1,2,7,8,10,11,12,NaN];
titles={'HPC flow h1','HPC efficiency h2','GT flow h7','GT efficiency h8', ...
    'GT-PT duct loss h10','PT flow h11','PT efficiency h12','Fuel bias'};
for j=1:8
    subplot(3,3,j);hold on;
    if isnan(ids(j))
        q=nodes(nodes.kind=="fuel_bias",:);x=q.coordinate*schedule.fuelBias.wfDesign;
        lab='Measured fuel flow (kg/s)';yl='Bias (kg/s)';
    else
        q=nodes(nodes.kind=="health"&nodes.c_index==ids(j),:);x=q.coordinate;yl='Actual correction K';
        if j<=2,lab='HPC relative corrected speed';
        elseif j<=4,lab='GT physical pressure ratio';
        elseif j==5,lab='Duct corrected flow (kg/s)';
        else,lab='PT physical pressure ratio';end
    end
    errorbar(x,q.mean_local,1.95996398454*q.std_local,'o-','LineWidth',1.2);
    plot(x,q.reference_value,'k:');title(titles{j});xlabel(lab);ylabel(yl);grid on;
end
subplot(3,3,9);j=find(string(D.parameterTable.parameter_id)=="K_dist_eq");
errorbar(1,D.map(j),1.95996398454*D.standardDeviation(j),'o','LineWidth',1.2);
xlim([.5,1.5]);set(gca,'XTick',[]);title('K dist eq');ylabel('Installation loss');grid on;
sgtitle('Node D: actual coefficients, marginal local normal reference intervals');
end

function y=local_interp(x,y,q)
x=x(:);y=y(:);q=min(max(q,min(x)),max(x));
if numel(x)==1,y=y(1);else,y=interp1(x,y,q,'linear');end
end

function package=local_read(file,runtime)
if nargin<2,runtime='';end
manifest=readtable(file,'Sheet','Manifest');
assert(strcmp(char(manifest.schema_version(1)),'F34_LOCAL_D_EXCEL_V1'),'D交付格式不符。');
identity=readtable(file,'Sheet','RuntimeAssets');
for i=1:height(identity)*double(~isempty(runtime))
    assert(strcmpi(sht_f33_model_adapt_v2('fileHash',fullfile(runtime,char(identity.file(i)))), ...
        char(identity.sha256(i))),'D公共运行资产不匹配。');
end
state=local_json_table(file,'ModelState');
if ~isempty(runtime)
state=local_relocate(state,'@runtime',runtime);
state.assets.configuration.engine.transientEffects.clearanceReferenceTable= ...
    sht_prepare_clearance_reference_lookup(state.assets.configuration.engine.transientEffects.clearanceReferenceTable);
end
parameter=readtable(file,'Sheet','ParameterDictionary');
for f={'parameter_id','name','unit','kind','axis_name'},parameter.(f{1})=string(parameter.(f{1}));end
context=struct('priorSchedule',state.priorSchedule,'familyMap',state.familyMap, ...
    'fuelMap',state.fuelMap,'parameterContract',parameter);
for i=1:numel(context.familyMap),context.familyMap(i).basis=context.familyMap(i).basis(:);end
context.fuelMap.basis=context.fuelMap.basis(:);
d=local_json_table(file,'LocalDistribution');map=readtable(file,'Sheet','ShapeNodeMap');
map.kind=string(map.kind);
assert(strcmp(d.schema,'F34_LOCAL_D_GAUSSIAN_V1')&&d.explicitDimension==height(parameter),'D分布维数不符。');
assert(all(isfinite(d.jointMean))&&all(isfinite(d.jointCovariance(:))),'D局部矩无效。');
assert(size(d.jointCovariance,1)==numel(d.jointMean),'D联合协方差维数不符。');
package=struct('manifest',manifest,'context',context,'assets',state.assets,'modelState',state, ...
    'distribution',d,'shape',struct('basis',d.shapeBasis,'nodeMap',map), ...
    'requiresTrainingMat',false,'requiresTruth',false);
package.runtimeVerified=~isempty(runtime);package.noDll=true;
package.workbook=file;package.method='D';package.runtimeAssets=identity;
if ismember('business_identity_purpose',manifest.Properties.VariableNames)
    package.businessIdentity=readtable(file,'Sheet','BusinessIdentity','PreserveVariableNames',true);
end
end

function value=local_json_table(file,sheet)
t=readtable(file,'Sheet',sheet);[~,order]=sort(t.chunk_id);
value=jsondecode(char(join(string(t.json_text(order)),'')));
end

function v=local_relocate(v,old,new)
if isstruct(v)
    f=fieldnames(v);
    for i=1:numel(v),for j=1:numel(f),v(i).(f{j})=local_relocate(v(i).(f{j}),old,new);end,end
elseif iscell(v)
    for i=1:numel(v),v{i}=local_relocate(v{i},old,new);end
elseif ischar(v),v=strrep(v,old,new);
elseif isstring(v),v=replace(v,old,new);
end
end

function value=local_nodes(schedule,map)
value=zeros(height(map),1);
for i=1:height(map)
    if map.kind(i)=="fuel_bias",value(i)=schedule.fuelBias.biasNodes(map.node_index(i));
    elseif map.kind(i)=="health_constant"
        if map.c_index(i)==15,value(i)=schedule.h15;
        else,value(i)=schedule.designHealth(map.c_index(i)+1);end
    else
        entry=find([schedule.healthEntries.cIndex]==map.c_index(i),1);
        value(i)=schedule.healthEntries(entry).kNodes(map.node_index(i));
    end
end
end
