function reference=sht_tc24_node_engineering_reference(forceRefresh,options)
%SHT_TC24_NODE_ENGINEERING_REFERENCE 三部件节点合并的固定工程标尺。
% 不读训练/测试Excel、造数真值或辨识结果。以下批准工况仅定义参考包线，
% 即使以后训练只覆盖其中一小段，合并距离也不缩小。参考表不作为曲线节点。
% 首次以零修正模型配平，之后按代码/DLL/MDL/MAP指纹复用缓存；不改正式模型。
if nargin<1,forceRefresh=false;end
if nargin<2,options=struct();end
root=fileparts(mfilename('fullpath'));
if isfield(options,'runtimeDirectory') && ~isempty(options.runtimeDirectory)
    package.directory=sht_tc24_absolute_path(options.runtimeDirectory);
else
    package=sht_tc24_runtime_package();
end
files={'GTESS.dll','GTESS.h','Turboshaft-TS.mdl','HPC02.MAP','HPT02.MAP','LPT02.MAP', ...
    'sht_tc24_node_engineering_reference.m','sht_trim_health_steady_point.m','sht_default_config.m'};
signature=cell(size(files));
for i=1:numel(files)
    sourceRoot=root;if i<=6,sourceRoot=package.directory;end
    signature{i}=local_hash(fullfile(sourceRoot,files{i}));
end
% 新DLL采用独立缓存文件；不覆盖旧包工程标尺。包内MDL/MAP改变仍重新校核。
cache=fullfile(root,'MiddleData','three_component', ...
    ['tc24_node_engineering_reference_',signature{1}(1:16),'.mat']);
if isfield(options,'outputDirectory') && ~isempty(options.outputDirectory)
    cache=fullfile(sht_tc24_absolute_path(options.outputDirectory),options.runId, ...
        'MiddleData','engineering_reference.mat');
end
if ~exist(fileparts(cache),'dir'),mkdir(fileparts(cache));end
if ~forceRefresh && isfile(cache)
    s=load(cache,'reference');
    if isequal(s.reference.signature,signature)
        reference=s.reference;return;
    end
end
% 固定的名义台架包线，而非从本次训练数据提取。包括不同Np挡位，
% 以及相邻参考工况的中点，防止燃烧室等非单调坐标只看首末点而遗漏极值。
np=[20900;20900;20900;20900;20900;20900;18810;18810;16720;16720;14630;14000];
power=[2176.6;2020;1890;1756;1317;878;1317;878;878;659;439;125];
[~,order]=sortrows([power,np],[1,2]);
npAll=[np;(np(order(1:end-1))+np(order(2:end)))/2];
powerAll=[power;(power(order(1:end-1))+power(order(2:end)))/2];
cfg=sht_default_config(struct('engine',struct('modelMode',0, ...
    'runtimeDirectory',package.directory,'boundary',struct( ...
    'inletBoundaryMode',0,'altitude',0,'Mach',0,'deltaTemperature',0, ...
    'healthScheduleEnabled',false,'health',zeros(159,1),'hpsPower',0)), ...
    'plot',struct('enable',false)));
names={'ac_corrected_speed','gt_total_pressure_ratio','pt_total_pressure_ratio', ...
    'inlet_corrected_mass_flow','burner_inlet_corrected_mass_flow', ...
    'gt_pt_duct_corrected_mass_flow','pt_nozzle_duct_corrected_mass_flow','measured_wf_ratio'};
values=zeros(numel(npAll),numel(names));residual=zeros(numel(npAll),1);
for i=1:numel(npAll)
    % 固定目标Np时，指定此功率等价于指定功率/(Np*pi/30)的扭矩。
    % 此处求工程参考，不改变正式辨识/预测的测量扭矩边界。
    t=sht_trim_health_steady_point(cfg,npAll(i),powerAll(i)*1000,zeros(159,1));
    assert(t.converged && t.residualInfinityNorm<=1e-7, ...
        'TC24:NodeReference:Trim','参考点%d未通过零修正配平。',i);
    for j=1:numel(names)
        if j==1
            values(i,j)=t.scheduleCoordinates.hpc_corrected_speed;
        elseif j==numel(names)
            values(i,j)=t.Wf/cfg.engine.initial.Wf0;
        else
            values(i,j)=t.scheduleCoordinates.(names{j});
        end
    end
    residual(i)=t.residualInfinityNorm;
    fprintf('Fixed engineering reference %d/%d: Np %.0f, %.1f kW, residual %.3e\n', ...
        i,numel(npAll),npAll(i),powerAll(i),residual(i));
end
axes=struct();
for j=1:numel(names)
    axes.(names{j})=struct('minimum',min(values(:,j)), ...
        'maximum',max(values(:,j)),'design',values(1,j));
end
points=array2table(values,'VariableNames',names);
points.Np_rpm=npAll;points.power_kW=powerAll;points.max_residual=residual;
reference=struct('schemaVersion','TC24_FIXED_ENGINEERING_REFERENCE_V1', ...
    'createdAt',datestr(now,31),'files',{files},'signature',{signature}, ...
    'axes',axes,'points',points,'health',zeros(159,1), ...
    'trainingDataRead',false,'testDataRead',false,'truthDataRead',false, ...
    'wfDesign',cfg.engine.initial.Wf0);
save(cache,'reference');
end

function hash=local_hash(file)
fid=fopen(file,'rb');assert(fid>0,'参考基线文件不存在：%s',file);
cleanup=onCleanup(@()fclose(fid));bytes=fread(fid,Inf,'*uint8');clear cleanup;
d=java.security.MessageDigest.getInstance('SHA-256');d.update(bytes);
hash=lower(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end
