function report=Test_TC27_G11_PublicThermalDelivery(request)
%TEST_TC27_G11_PUBLICTHERMALDELIVERY G11有限合同/真实生成/独立读回测试。
% 必须显式给mode、outputDirectory；nodll和physical还需公开导出的
% preparationOptions。physical只调用一次真实生成，不自动重试或续跑。
% nodll中的合成资产均标记TEST_ONLY，只证明文件合同，不是热物理结果。
assert(isstruct(request)&&isscalar(request)&&all(isfield(request, ...
    {'mode','outputDirectory'})),'TC27:PublicTest:Request','缺少明确测试配置。');
mode=char(request.mode);out=char(request.outputDirectory);
assert(ismember(mode,{'nodll','physical','readback'}), ...
    'TC27:PublicTest:Mode','mode必须为nodll、physical或readback。');
assert(~isfile(out)&&~isfolder(out),'TC27:PublicTest:Exists','测试输出目录已存在。');
if ~strcmp(mode,'readback')
    assert(isfield(request,'preparationOptions')&&isstruct(request.preparationOptions), ...
        'TC27:PublicTest:Source','必须显式传入公开来源导出的preparationOptions。');
end
assert(strcmp(fileparts(which('Start_TC27_ThermalPreparationResultView_01')), ...
    fileparts(mfilename('fullpath'))),'TC27:PublicTest:Source','查看器不是本候选文件。');
mkdir(out);timer=tic;
report=struct('mode',mode,'status','RUNNING','cases',{{}}, ...
    'physicalGenerationCount',0,'syntheticFixturesAreTestOnly',true, ...
    'matlabVersion',version,'elapsedSeconds',NaN,'dllCallsNotCounted',true);
if ~strcmp(mode,'physical')
    profile clear;profile on;
    profilerCleanup=onCleanup(@()profile('off')); %#ok<NASGU>
end
try
    switch mode
        case 'nodll'
            local_expect_error(@()Start_TC27_02_ThermalModelPreparation(), ...
                'TC27:Thermal:OutputDirectory');
            report.cases{end+1}='default_call_still_refuses_output';
            o=request.preparationOptions;o.execute=false;
            assert(isfield(o,'inheritedThermalPair'),'TC27:PublicTest:Source', ...
                '无DLL正式入口仅支持显式继承路线。');
            assert(~isfolder(o.assetDirectory),'TC27:PublicTest:Exists','候选目录必须尚不存在。');
            prep=Start_TC27_02_ThermalModelPreparation(o);
            assert(strcmp(prep.executionStatus,'PREP_ONLY_NO_DLL')&&~isfolder(o.assetDirectory));
            report.cases{end+1}='public_source_preflight_no_output';
            if isfield(request,'ordinaryPreparationOptions')
                ordinary=request.ordinaryPreparationOptions;
                assert(~isfield(ordinary,'inheritedThermalPair'));
                ordinaryPlan=sht_tc27_thermal_output_plan(ordinary);
                assert(~ordinaryPlan.inheritedMode&&~isfolder(ordinaryPlan.outputDirectory));
                report.cases{end+1}='ordinary_existing_plan_preflight_only';
            end
            folder=fullfile(out,'TEST_ONLY_new_metadata');
            result=local_fixture(true,false);local_save_fixture(folder,result);
            v=Start_TC27_ThermalPreparationResultView_01(folder);
            assert(v.complete&&v.environmentMetadataAvailable&&v.savedAssetIdentityVerified);
            assert(~v.runtimeIdentityVerified&&v.generationConfiguration.effectiveBoundaryTemplate.deltaTemperature==7);
            assert(isequal(v.thermalAssets.visser.referencePoints.point_id, ...
                result.preparation.generationConfiguration.referencePoints.point_id));
            report.cases{end+1}='new_metadata_point_order_and_units';
            moved=fullfile(out,'TEST_ONLY_中文 空格搬迁');mkdir(moved);
            local_copy_pair(folder,moved,true);
            relocated=Start_TC27_ThermalPreparationResultView_01(moved);
            assert(isequaln(v.generationConfiguration,relocated.generationConfiguration));
            assert(isequaln(v.thermalAssets.visser.states,relocated.thermalAssets.visser.states));
            report.cases{end+1}='relocated_same_saved_bytes';
            oldFolder=fullfile(out,'TEST_ONLY_legacy_twelve');
            local_save_fixture(oldFolder,local_fixture(false,true));
            old=Start_TC27_ThermalPreparationResultView_01(oldFolder);
            assert(old.complete&&~old.environmentMetadataAvailable&& ...
                height(old.thermalAssets.kurzke.referencePoints)==12);
            report.cases{end+1}='legacy_no_environment_not_invented';
            partialFolder=fullfile(out,'TEST_ONLY_partial');mkdir(partialFolder);
            result=struct('complete',false,'executionStatus','PARTIAL_BUDGET_STOP', ...
                'provenance','TEST_ONLY_INTERFACE_FIXTURE_NOT_PHYSICAL'); %#ok<NASGU>
            partialFile=fullfile(partialFolder,'partial_budget_result.mat');
            save(partialFile,'result');partial=Start_TC27_ThermalPreparationResultView_01(partialFile);
            assert(~partial.complete&&~partial.savedAssetIdentityVerified);
            report.cases{end+1}='partial_cannot_be_complete';
            tampered=fullfile(out,'TEST_ONLY_tampered');mkdir(tampered);
            local_copy_pair(folder,tampered,true);
            f=fopen(fullfile(tampered,'tc27_visser16_parameters.mat'),'ab');assert(f>=0);
            fwrite(f,uint8(1),'uint8');fclose(f);
            local_expect_error(@()Start_TC27_ThermalPreparationResultView_01(tampered), ...
                'TC27:ThermalView:AssetIdentity');
            report.cases{end+1}='changed_asset_rejected';
            missing=fullfile(out,'TEST_ONLY_missing');mkdir(missing);
            local_copy_pair(folder,missing,false);
            local_expect_error(@()Start_TC27_ThermalPreparationResultView_01(missing), ...
                'TC27:ThermalView:MissingAsset');
            report.cases{end+1}='missing_pair_rejected';
            wrongEnvironment=fullfile(out,'TEST_ONLY_environment_mismatch');
            result=local_fixture(true,false);
            result.preparation.generationConfiguration.effectiveBoundaryTemplate.deltaTemperature=8;
            local_save_fixture(wrongEnvironment,result);
            local_expect_error(@()Start_TC27_ThermalPreparationResultView_01(wrongEnvironment), ...
                'TC27:ThermalView:Generation');
            report.cases{end+1}='environment_mismatch_rejected';
            wrongTopology=fullfile(out,'TEST_ONLY_wrong_topology');
            result=local_fixture(true,false);result.visser.interface.thermalModelMode=1;
            local_save_fixture(wrongTopology,result);
            local_expect_error(@()Start_TC27_ThermalPreparationResultView_01(wrongTopology), ...
                'TC27:ThermalView:Topology');
            report.cases{end+1}='wrong_thermal_mode_rejected';
            wrongPhysical=fullfile(out,'TEST_ONLY_wrong_physical_binding');
            result=local_fixture(true,false);result.visser.modelIdentity.modelSHA256=repmat('1',1,64);
            local_save_fixture(wrongPhysical,result);
            local_expect_error(@()Start_TC27_ThermalPreparationResultView_01(wrongPhysical), ...
                'TC27:ThermalView:PhysicalIdentity');
            report.cases{end+1}='wrong_saved_physical_binding_rejected';
            if isfield(request,'legacyResultFile')&&~isempty(request.legacyResultFile)
                old=Start_TC27_ThermalPreparationResultView_01(request.legacyResultFile);
                assert(old.complete&&~old.environmentMetadataAvailable);
                report.cases{end+1}='actual_legacy_result_read_only';
            end
            report.preflight=prep;
        case 'physical'
            assert(isfield(request,'computeAuthorized')&&isequal(request.computeAuthorized,true), ...
                'TC27:PublicTest:ComputeGO','必须在取得MAIN计算许可后显式设置computeAuthorized。');
            o=request.preparationOptions;o.execute=true;
            report.physicalGenerationCount=1;
            result=Start_TC27_02_ThermalModelPreparation(o);
            assert(isfield(result,'preparation')&&result.preparation.complete, ...
                'TC27:PublicTest:Incomplete','热准备未完成，保留partial，不进入发布验证。');
            v=Start_TC27_ThermalPreparationResultView_01(o.assetDirectory);
            assert(v.environmentMetadataAvailable&&v.complete);
            g=v.generationConfiguration;
            for name=fieldnames(o.boundary).'
                assert(isfield(g.effectiveBoundaryTemplate,name{1}) && ...
                    isequaln(g.effectiveBoundaryTemplate.(name{1}),o.boundary.(name{1})), ...
                    'TC27:PublicTest:Boundary','实际保存边界与请求不同：%s。',name{1});
            end
            assert(isfield(g.effectiveBoundaryTemplate,'deltaTemperature'));
            assert(g.sourceDesignReference.schema==26101401);
            assert(height(g.referencePoints)==6&&nnz(g.referencePoints.useForTable)==5);
            report.cases{end+1}='actual_public_thermal_generation_and_metadata';
            report.resultFile=v.resultFile;report.generationConfiguration=g;
            report.thermalEquilibriumCount=result.preparation.thermalEquilibriumCount;
            report.gasInitialTrimCount=result.preparation.gasInitialTrimCount;
            report.thermalMetrics=local_metrics(v);
            if isfield(request,'comparisonResultFile')&&~isempty(request.comparisonResultFile)
                old=Start_TC27_ThermalPreparationResultView_01(request.comparisonResultFile);
                report.comparison=local_compare(v,old);
                report.cases{end+1}='same_configuration_physical_comparison_recorded';
            end
        case 'readback'
            assert(isfield(request,'resultFile'),'TC27:PublicTest:Result','缺少明确结果文件。');
            v=Start_TC27_ThermalPreparationResultView_01(request.resultFile);
            assert(v.complete&&v.environmentMetadataAvailable&&v.savedAssetIdentityVerified);
            report.resultFile=v.resultFile;report.generationConfiguration=v.generationConfiguration;
            report.thermalMetrics=local_metrics(v);
            report.cases{end+1}='independent_process_saved_result_readback';
    end
    if ~strcmp(mode,'physical')
        profile off;info=profile('info');report.forbiddenCalls=local_forbidden(info);
        assert(isempty(report.forbiddenCalls),'TC27:PublicTest:UnexpectedCompute', ...
            '无DLL测试意外调用配置、求解或DLL。');
        save(fullfile(out,'profile.mat'),'info','-v7.3');
    end
    report.status='PASS';
catch ex
    report.status='FAIL';report.errorIdentifier=ex.identifier;report.errorMessage=ex.message;
    report.elapsedSeconds=toc(timer);save(fullfile(out,'report.mat'),'report','-v7.3');
    local_write_json(fullfile(out,'report.json'),report);rethrow(ex);
end
report.elapsedSeconds=toc(timer);save(fullfile(out,'report.mat'),'report','-v7.3');
local_write_json(fullfile(out,'report.json'),report);
fprintf('G11公开热交付测试%s：%s，内部用时%.3fs。\n',mode,report.status,report.elapsedSeconds);
end

function result=local_fixture(withMetadata,legacy)
% 极小文件合同夹具；数值为人工填充，绝不当作热平衡或新设计计算结果。
if legacy,n=12;else,n=6;end
id=arrayfun(@(k)sprintf('TEST_ONLY_%02d',k),(1:n).','UniformOutput',false);
np=(14000:100:14000+100*(n-1)).';power=(100:10:100+10*(n-1)).';
torque=power*1000./(pi*np/30);mask=true(n,1);
if ~legacy,mask(3)=false;end
grid=table(id,np,power,torque,mask,'VariableNames', ...
    {'point_id','Np_rpm','load_power_kW','target_torque_Nm','useForTable'});
b=struct('inletBoundaryMode',1,'Tt1',295.15,'Pt1',101325,'Pamb',101325, ...
    'Tamb',295.15,'altitude',0,'Mach',0,'deltaTemperature',7, ...
    'Mkg',0,'Mkp',torque(1),'ptLoadInputMode','torque','gtLoadInputMode','torque');
g=struct('schemaVersion','TC27_THERMAL_GENERATION_CONFIG_V1','modelMode',0, ...
    'thermalModes',[1,3],'effectiveBoundaryTemplate',b,'referencePoints',grid, ...
    'referenceBoundaryRule',struct('MkpSource','referencePoints.target_torque_Nm'), ...
    'sourceDesignReference',[],'executionDesignReference',[], ...
    'configurationIdentity',struct(),'thermalPriorIdentity',[]);
result=struct('provenance','TEST_ONLY_INTERFACE_FIXTURE_NOT_PHYSICAL');
testHash=repmat('0',1,64);
for k=1:2
    count=14+k;modes=[1,3];keys={'kurzke','visser'};
    a=struct('interface',struct('interfaceVersion',2502,'thermalModelMode',modes(k)), ...
        'nominal',struct('initialTemperatureState',500*ones(count-2,1)), ...
        'referenceTable',struct('generated',true),'referenceGrid',grid(mask,:));
    a.modelIdentity=struct('dllSHA256',testHash,'headerSHA256',testHash,'modelSHA256',testHash);
    a.stateNames=[{'Np';'Ng'};arrayfun(@(j)sprintf('T_TEST_ONLY_%02d',j), ...
        (1:count-2).','UniformOutput',false)];
    allEquilibria=cell(n,1);
    for j=1:n
        allEquilibria{j}=struct('state',[np(j);30000;500+j+zeros(count-2,1)], ...
            'fuelFlow_kgps',.10+j/1000,'physicalValid',true);
    end
    a.referenceEquilibria=allEquilibria(mask);
    if ~legacy
        a.independentValidation=struct('point',grid(~mask,:), ...
            'equilibrium',allEquilibria{~mask});
    end
    if withMetadata,a.generationConfiguration=g;end
    result.(keys{k})=a;
end
result.preparation=struct('schemaVersion','TC27_THERMAL_READY_V1','complete',true);
files={'GTESS.dll','GTESS.h','Turboshaft-TS.mdl'};
for k=1:3
    result.preparation.physicalIdentity.assets(k)=struct('name',files{k},'sha256',testHash);
end
if ~legacy,result.preparation.schemaVersion='TC27_G11_INHERITED_THERMAL_READY_V1';end
if withMetadata,result.preparation.generationConfiguration=g;end
end

function local_save_fixture(folder,result)
assert(~isfolder(folder)&&~isfile(folder));mkdir(folder);
keys={'kurzke','visser'};names={'tc27_kurzke15_parameters.mat','tc27_visser16_parameters.mat'};
for k=1:2
    parameterAsset=result.(keys{k});file=fullfile(folder,names{k}); %#ok<NASGU>
    save(file,'parameterAsset','-v7.3');
    result.preparation.thermalAssets(k)=struct('relative',['old_root/',names{k}], ...
        'sha256',sht_tc27_file_identity(file));
end
save(fullfile(folder,'tc27_thermal_preparation_result.mat'),'result','-v7.3');
end

function local_copy_pair(from,to,includeVisser)
names={'tc27_thermal_preparation_result.mat','tc27_kurzke15_parameters.mat'};
if includeVisser,names{end+1}='tc27_visser16_parameters.mat';end
for k=1:numel(names)
    assert(~isfile(fullfile(to,names{k})));
    copyfile(fullfile(from,names{k}),fullfile(to,names{k}));
end
end

function local_expect_error(callback,identifier)
try,callback();catch ex
    assert(strcmp(ex.identifier,identifier),'TC27:PublicTest:WrongError', ...
        '预期%s，实际%s。',identifier,ex.identifier);return;
end
error('TC27:PublicTest:MissingError','预期错误未发生：%s。',identifier);
end

function value=local_metrics(v)
value=struct();
for key={'kurzke','visser'}
    a=v.thermalAssets.(key{1});
    value.(key{1})=struct('pointIds',{cellstr(string(a.referencePoints.point_id))}, ...
        'states',a.states,'fuelFlow_kgps',a.fuelFlow_kgps,'physicalValid',a.physicalValid, ...
        'stateNames',{a.stateNames},'sha256',a.sha256);
end
end

function c=local_compare(v,old)
c=struct();
for key={'kurzke','visser'}
    a=v.thermalAssets.(key{1});b=old.thermalAssets.(key{1});
    [present,order]=ismember(string(a.referencePoints.point_id),string(b.referencePoints.point_id));
    assert(all(present)&&numel(unique(order))==height(b.referencePoints));
    assert(isequal(a.referencePoints.Np_rpm,b.referencePoints.Np_rpm(order)) && ...
        isequal(a.referencePoints.load_power_kW,b.referencePoints.load_power_kW(order)));
    assert(isequal(a.parameterAsset.modelIdentity,b.parameterAsset.modelIdentity), ...
        'TC27:PublicTest:ComparisonIdentity','物理身份不同，不能作为同配置数值对照。');
    c.(key{1})=struct('maximumStateDifference',max(abs(a.states(:)-reshape(b.states(order,:),[],1))), ...
        'maximumFuelDifference',max(abs(a.fuelFlow_kgps-b.fuelFlow_kgps(order))));
    c.(key{1}).stateDifference=a.states-b.states(order,:);
    c.(key{1}).stateNames=a.stateNames;
    c.(key{1}).stateUnits=a.stateUnits;
    channels={'Np','Ng','Pt3','Tt3','Pt45','Tt45','power','Tt1','Pt1','Pt2'};
    for j=1:numel(a.equilibria)
        ya=a.equilibria{j}.output;yb=b.equilibria{order(j)}.output;
        for m=1:numel(channels)
            name=channels{m};
            if isfield(ya,name)&&isfield(yb,name)
                c.(key{1}).outputDifference.(name)(j,1)=ya.(name)-yb.(name);
            end
        end
    end
end
% 数值差异只报告，不用新的误差阈值替代既有物理验收。
end

function names=local_forbidden(info)
forbidden={'sht_default_config','sht_tc27_config','sht_engine_open','sht_engine_derivative', ...
    'sht_thermal_equilibrium_solve','sht_trim_health_steady_point','loadlibrary','calllib'};
all={info.FunctionTable.FunctionName};names={};
for k=1:numel(forbidden)
    if any(contains(all,forbidden{k})),names{end+1}=forbidden{k};end %#ok<AGROW>
end
end

function local_write_json(file,value)
f=fopen(file,'w','n','UTF-8');assert(f>=0);c=onCleanup(@()fclose(f)); %#ok<NASGU>
fprintf(f,'%s',jsonencode(value));
end
