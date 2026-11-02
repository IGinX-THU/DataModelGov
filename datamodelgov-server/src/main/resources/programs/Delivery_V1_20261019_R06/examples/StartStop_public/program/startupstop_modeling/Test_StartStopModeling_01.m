function report = Test_StartStopModeling_01(group,testConfig)
%TEST_STARTSTOPMODELING_01 A/DIAGNOSTICS无DLL；B有限物理验证须核定计算窗口。
% testConfig.sourceDirectory/workingDirectory必须显式给定，不查开发机路径。
% B按modelMode分别运行；continuityKind选continuous/thermal，caseNames选一个。
assert(nargin==2 && isstruct(testConfig),'sht:modeling:testConfig','必须显式给出测试配置。');
validateattributes(group,{'char'},{'nonempty'});
root=testConfig.workingDirectory;
assert(~isfolder(root),'sht:modeling:testExists','测试目录已存在，必须用新的目录。');
mkdir(root);timer=tic;
report=struct('group',group,'matlabVersion',version,'startedAt',datestr(now,31), ...
    'passed',false,'cases',{{}},'elapsedSeconds',0,'outputs',{{}},'failure',struct());
try
    switch upper(group)
        case 'A', local_group_a();
        case 'B', local_group_b();
        case 'BUDGET', local_group_budget();
        case 'DIAGNOSTICS', local_group_diagnostics();
        case 'PUBLIC_SOURCE', local_public_source();
        case 'PUBLIC_SAVE', local_public_save();
        case 'PUBLIC_CONSUME', local_public_consume();
        otherwise,error('sht:modeling:testGroup','未知测试组。');
    end
    report.passed=true;
catch ex
    report.failure=struct('identifier',ex.identifier,'message',ex.message,'stack',ex.stack);
    report.elapsedSeconds=toc(timer);local_save_report();rethrow(ex);
end
report.elapsedSeconds=toc(timer);local_save_report();

    function local_public_source()
        local_assert_no_engine_library();
        delivery=sht_startstop_modeling_task('savePackage',testConfig.sourcePackage, ...
            fullfile(root,'source_package'),struct('executionCodeDirectory',testConfig.sourceDirectory));
        assert(delivery.saved && delivery.runtimeReady && delivery.thermalSourceReady && ~delivery.thermalReady);
        view=sht_startstop_modeling_task('loadResult',delivery.directory);
        assert(view.sourcePackageIdentity.notCheckpointResume);
        for name={'sht_fullmode_session.m','sht_startstop_run_continuous_mission.m'}
            local_same_file(fullfile(delivery.directory,'program',name{1}),fullfile(testConfig.sourceDirectory,name{1}));
        end
        report.cases{end+1}='真实旧包另存，新执行R06与历史来源分离';
        request=testConfig.thermalRequest;
        if isstruct(request.referencePoints),request.referencePoints=struct2table(request.referencePoints);end
        options=sht_startstop_modeling_task('thermalSource',delivery.directory,request);
        direct=sht_startstop_modeling_package('thermalSource',delivery.directory,request);
        assert(isequaln(options,direct));
        f=fopen(options.lineageFile,'rb');lineage=jsondecode(native2unicode(fread(f,Inf,'*uint8').','UTF-8'));fclose(f);
        assert(lineage.DesignReference.schema==26101401 && ~isfield(lineage.DesignReference,'schemaVersion'));
        thermalPreparationOptions=options; %#ok<NASGU>
        save(fullfile(root,'thermal_options.mat'),'thermalPreparationOptions','-v7');
        report.sourcePackage=delivery.directory;report.thermalOptionsFile=fullfile(root,'thermal_options.mat');
        report.cases{end+1}='公开options自动生产，薄入口与文件核心相同';
        local_expect(@()sht_startstop_modeling_task('fullmodeConfig',delivery.directory, ...
            struct('fullmode',struct('thermalEnabled',true))),'sht:modeling:thermalMissing');
        bad=request;bad.physicalManifestSHA256='forbidden';
        local_expect(@()sht_startstop_modeling_task('thermalSource',delivery.directory,bad),'sht:modeling:thermalRequest');
        damaged=fullfile(root,'TEST_ONLY_tampered');copyfile(delivery.directory,damaged);
        file=fullfile(damaged,'program','GTESS.h');f=fopen(file,'a');fprintf(f,'\nTEST_ONLY');fclose(f);
        local_expect(@()sht_startstop_modeling_task('loadResult',damaged),'sht:modeling:packageChanged');
        report.cases{end+1}='缺热资产、手填身份、篡改文件明确拒绝';
        file=fullfile(delivery.directory,'program','GTESS.dll');movefile(file,[file,'.held']);
        dllRestore=onCleanup(@()movefile([file,'.held'],file));
        history=sht_startstop_modeling_task('loadResult',delivery.directory);
        assert(~history.executionFilesComplete && numel(history.missingRuntimeFiles)==1);
        local_expect(@()sht_startstop_modeling_task('fullmodeConfig',delivery.directory, ...
            struct('fullmode',struct('thermalEnabled',false))),'sht:modeling:packageChanged');
        clear dllRestore;
        report.cases{end+1}='无DLL仅查看且明确缺失，不放宽实际执行';
        % 只验证原三/六部件prepare/save合同，不执行扩图或气路求解。
        for mode=0:1
            cfg=sht_startstop_modeling_config(struct('modelMode',mode, ...
                'taskDirectory',fullfile(root,sprintf('empty_task%d',mode)), ...
                'source',struct('codeDirectory',testConfig.sourceDirectory, ...
                'modelDirectory',testConfig.legacyModelDirectory,'dllDirectory',testConfig.sourceDirectory, ...
                'thermalFile','','designStateFile','')));
            task=sht_startstop_modeling_task('prepare',cfg);
            assert(task.preflight.ready,strjoin(task.preflight.issues,'; '));
            saved=sht_startstop_modeling_task('savePackage',task.taskDirectory,fullfile(root,sprintf('empty_package%d',mode)));
            assert(saved.saved && ~saved.runtimeReady && ~saved.thermalSourceReady);
            local_expect(@()sht_startstop_modeling_task('fullmodeConfig',saved.directory, ...
                struct('fullmode',struct('thermalEnabled',false))),'sht:modeling:missingSeed');
        end
        report.cases{end+1}='原三/六部件无DLL准备和保存，缺种子不允许全模式';
        local_assert_no_engine_library();
    end

    function local_public_save()
        local_assert_no_engine_library();
        % 源包清单的大写SHA和TC27查看器的小写SHA应按同一摘要比较。
        rows=readtable(fullfile(testConfig.sourcePackage,'files_sha256.csv'), ...
            'Delimiter',',','Encoding','UTF-8','TextType','string');
        assert(all(rows.sha256==upper(rows.sha256)));
        delivery=sht_startstop_modeling_task('savePackage',testConfig.sourcePackage, ...
            fullfile(root,'公开结果 中文目录'),struct('executionCodeDirectory',testConfig.sourceDirectory, ...
            'thermalPreparationResultFile',testConfig.thermalResultFile));
        assert(delivery.thermalReady && delivery.runtimeReady);
        view=sht_startstop_modeling_task('loadResult',delivery.directory);
        thermal=view.thermalPreparation;
        assert(thermal.complete && thermal.environmentMetadataAvailable && thermal.savedAssetIdentityVerified);
        for key={'kurzke','visser'}
            a=thermal.thermalAssets.(key{1});
            actual=sht_startstop_modeling_package('hash',a.file);
            assert(strcmp(a.sha256,lower(a.sha256)) && strcmpi(actual,a.sha256));
        end
        for name={'tc27_thermal_preparation_result.mat','tc27_kurzke15_parameters.mat','tc27_visser16_parameters.mat'}
            local_same_file(fullfile(fileparts(thermal.resultFile),name{1}), ...
                fullfile(fileparts(testConfig.thermalResultFile),name{1}));
        end
        report.savedPackage=delivery.directory;report.generationConfiguration=thermal.generationConfiguration;
        report.cases={'公开保存两热MAT及完成记录原字节','实际环境/参考点无DLL读回','源码/物理/热来源已绑定'};
        report.cases{end+1}='源包大写及热资产小写SHA均完成真实复制核对';
        % 只破坏独立负例副本，证明大小写兼容不等于放松文件完整性检查。
        damaged=fullfile(root,'TEST_ONLY_tampered_thermal');copyfile(delivery.directory,damaged);
        file=fullfile(damaged,'assets','thermal_preparation','tc27_visser16_parameters.mat');
        fid=fopen(file,'ab');assert(fid>=0);fwrite(fid,uint8(0),'uint8');fclose(fid);
        local_expect(@()sht_startstop_modeling_task('loadResult',damaged),'sht:modeling:packageChanged');
        report.cases{end+1}='热MAT实际字节篡改仍明确拒绝';
        local_assert_no_engine_library();
    end

    function local_public_consume()
        local_assert_no_engine_library();
        folder=testConfig.sourcePackage;program=fullfile(folder,'program');
        oldPath=path;pathGuard=onCleanup(@()path(oldPath)); %#ok<NASGU>
        % 本组由新进程启动，只添加已保存交付包，不用旧工作区求解依赖。
        addpath(program,'-begin');addpath(fullfile(program,'design_point_modeling'),'-begin');
        addpath(fullfile(program,'startupstop_modeling'),'-begin');
        view=sht_startstop_modeling_task('loadResult',folder);v=view.thermalPreparation.thermalAssets.visser;
        i=find(string(v.referencePoints.point_id)==string(testConfig.referencePointId));
        assert(isscalar(i) && v.physicalValid(i));
        p=load(fullfile(folder,'modeling_package.mat'),'package');
        ratio=v.referencePoints.Np_rpm(i)/p.package.engineConfiguration.startStop.designNpRpm;
        boundary=view.thermalPreparation.generationConfiguration.effectiveBoundaryTemplate;
        inlet=struct();
        for key={'inletBoundaryMode','Pt1','Tt1','Pamb','Tamb','altitude','Mach','deltaTemperature'}
            inlet.(key{1})=boundary.(key{1});
        end
        cfg=struct('fullmode',struct('thermalEnabled',true,'initialKind','cruise', ...
            'initialNpRatio',ratio,'npRatio',ratio,'initialThermalState',v.states(i,3:end).', ...
            'loadMode','power','load',struct('powerW',1000*v.referencePoints.load_power_kW(i)), ...
            'inletBoundary',inlet,'outputDirectory',fullfile(root,'direct')));
        delivery=sht_startstop_modeling_task('fullmodeConfig',folder,cfg);
        same=sht_startstop_modeling_package('fullmodeConfig',folder,cfg);
        assert(isequaln(delivery.configuration,same.configuration));
        assert(~isempty(delivery.thermalPreparation));
        local_assert_no_engine_library();
        report.cases{end+1}='中文目录新进程只读配置，界面/离线同核';
        settings=delivery.configuration;
        assert(settings.startStop.gtAccessoryPowerW==p.package.engineConfiguration.startStop.gtAccessoryPowerW);
        report.thermalReferenceBoundary=boundary;
        report.taskInletBoundary=inlet;
        report.taskGtAccessoryPowerW=settings.startStop.gtAccessoryPowerW;
        report.thermalReferenceIsTaskEquilibrium=false;
        local_assert_resolution(program);
        sht_fullmode_session('prepare',settings);
        closeGuard=onCleanup(@()sht_fullmode_session('close'));
        local_check_runtime(folder,settings);
        sht_fullmode_session('begin');sht_fullmode_session('advance',80);
        direct=sht_fullmode_session('result');clear closeGuard;
        assert(direct.terminalStatus.acceptedSteps==80 && height(direct.trace)==21);
        assert(max(abs(direct.thermalTrace{1,2:end}-v.states(i,3:end)))<1e-10);
        settings.fullmode.outputDirectory=fullfile(root,'offline');
        offline=Run_FullModeSimulation_Offline(settings,struct('durationS',2,'commands',{{}}));
        assert(isequaln(direct.trace,offline.trace) && isequaln(direct.thermalTrace,offline.thermalTrace));
        cfg.fullmode.thermalEnabled=false;cfg.fullmode.outputDirectory=fullfile(root,'noheat');
        delivery=sht_startstop_modeling_task('fullmodeConfig',folder,cfg);
        noheat=Run_FullModeSimulation_Offline(delivery.configuration,struct('durationS',2,'commands',{{}}));
        assert(noheat.terminalStatus.acceptedSteps==80 && isempty(noheat.thermalTrace));
        save(fullfile(root,'public_physics_result.mat'),'direct','offline','noheat','-v7.3');
        report.cases=[report.cases,{'运行八文件与热来源相同','有热2秒/离线2秒逐值一致','无热2秒通过'}];
        report.finalNpNg=direct.terminalStatus.speedRpm;report.traceRows=height(direct.trace);
        report.actualMissionSHA=sht_startstop_modeling_package('hash',which('sht_startstop_run_continuous_mission'));
        report.actualSessionSHA=sht_startstop_modeling_package('hash',which('sht_fullmode_session'));
        local_assert_no_engine_library();
    end

    function local_group_diagnostics()
        % 仅读取本批显式复制的结果。重定位在内存的说明对象，不调用
        % task的恢复/运行接口，也不修改旧检查点或旧结果的任何签名。
        local_assert_no_engine_library();
        fixture=testConfig.fixtureDirectory;
        d=load(fullfile(fixture,'MiddleData','task_state','task.mat'),'task');
        task=d.task;task.taskDirectory=fixture;
        msg=local_stage_error(task,'matrix');
        assert(contains(msg,'lagging__no_fuel__Ng030.0'));
        assert(contains(msg,'lagging__pre_ignition__Ng030.0'));
        assert(contains(msg,'4.681753e-07') && contains(msg,'1.219318e-06'));
        assert(contains(msg,'solverStatus=1') && contains(msg,'solverConverged=0'));
        assert(contains(msg,'达到最大迭代次数'));
        assert(~contains(msg,'matrix:  []'));
        report.cases{end+1}='真实两失败点及残差完整显示';
        report.matrixDiagnostic=msg;
        missing=task;missing.stages.matrix.resultFile='missing_result.mat';
        missingMsg=local_stage_error(missing,'matrix');
        assert(contains(missingMsg,'missing_result.mat') && contains(missingMsg,'诊断读取失败'));
        report.cases{end+1}='缺诊断文件返回具体原因';
        failed=missing;failed.stages.matrix.errorIdentifier='example:failure';
        failed.stages.matrix.errorMessage='原始异常保留';
        failedMsg=local_stage_error(failed,'matrix');
        assert(contains(failedMsg,'example:failure') && contains(failedMsg,'原始异常保留'));
        report.cases{end+1}='原始异常不被诊断读取失败覆盖';
        local_assert_no_engine_library();
    end

    function local_group_a()
        % 若外层已经装载发动机库，这一进程不能作为无DLL证据。
        local_assert_no_engine_library();
        tasks=cell(1,2);
        for mode=0:1
            cfg=local_config(mode,fullfile(root,sprintf('task_m%d',mode)));
            draft=cfg;draft.source.modelFile='missing.mdl';
            missing=sht_startstop_modeling_task('prepare',draft);
            assert(strcmp(missing.status,'blocked') && ~isfolder(draft.taskDirectory));
            task=sht_startstop_modeling_task('prepare',cfg);
            assert(strcmp(task.status,'ready'));
            blocked=sht_startstop_modeling_task('runStage',task.taskDirectory,'matrix');
            assert(strcmp(blocked.status,'blocked'));
            assert(~isempty(blocked.lastError.identifier));
            paused=sht_startstop_modeling_task('requestPause',task.taskDirectory);
            assert(strcmp(paused.status,'paused'));
            paused=sht_startstop_modeling_task('runStage',task.taskDirectory,'maps');
            assert(strcmp(paused.stages.maps.status,'not_run'));
            sht_startstop_modeling_task('resume',task.taskDirectory);
            task=sht_startstop_modeling_task('runStage',task.taskDirectory,'maps');
            assert(task.stages.maps.selectedPassed,local_stage_error(task,'maps'));
            resultPath=task.stages.maps.resultFile;
            repeat=sht_startstop_modeling_task('runStage',task.taskDirectory,'maps');
            assert(strcmp(repeat.stages.maps.resultFile,resultPath));
            repeat=sht_startstop_modeling_task('configure',task.taskDirectory, ...
                struct('display',struct('showFigures',true)));
            assert(strcmp(repeat.stages.maps.status,'completed'));
            % 底层直接入口与适配入口的扩图字节一致，原工作区域检查完整保留。
            context=sht_startstop_modeling_package('context',task.bundle);
            engine=sht_startstop_modeling_task('engineConfig',task);
            engine.mapIO.generateFigures=false;
            direct=sht_startstop_run_map_stages(engine,fullfile(task.taskDirectory,'report_outputs','direct_map_check'));
            d=load(fullfile(task.taskDirectory,resultPath),'result');r=d.result;
            if isfield(r,'maps'),r=r.maps;end
            for j=1:numel(direct.items)
                assert(direct.items(j).originalRegionAudit.accepted);
                assert(strcmp(direct.items(j).outputSha256,r.mapResult.items(j).outputSha256));
            end
            clear context;
            % 保存失败只影响保存状态，不影响已完成数值结果；换目录可以重试。
            bad=fullfile(root,sprintf('exists_m%d',mode));mkdir(bad);
            local_expect(@()sht_startstop_modeling_task('savePackage',task.taskDirectory,bad), ...
                'sht:modeling:exportExists');
            failedSave=sht_startstop_modeling_task('status',task.taskDirectory);
            assert(strcmp(failedSave.saveStatus,'failed') && failedSave.stages.maps.selectedPassed);
            package=sht_startstop_modeling_task('savePackage',task.taskDirectory, ...
                fullfile(root,sprintf('package_m%d',mode)));
            assert(package.saved && ~package.runtimeReady && isfile(package.excel));
            view=Start_StartStopModeling_ResultView_01(package.directory,false);
            assert(strcmp(view.taskId,task.taskId));
            local_expect(@()sht_startstop_modeling_task('fullmodeConfig',package.directory, ...
                struct('fullmode',struct('thermalEnabled',false))), 'sht:modeling:missingSeed');
            taskView=Start_StartStopModeling_ResultView_01(task.taskDirectory,false);
            assert(isfield(taskView.results,'maps'));
            tasks{mode+1}=sht_startstop_modeling_task('status',task.taskDirectory);
            report.outputs{end+1}=package.directory;
            report.cases{end+1}=struct('modelMode',mode,'originalMaps',numel(direct.items), ...
                'originalRegionPassed',true,'sameCoreMapsByteEqual',true, ...
                'pauseAndReusePassed',true,'saveRetryPassed',true,'missingSeedRejected',true);
            local_assert_no_engine_library();
        end
        % 物理配置变更只将相关阶段标为过期；没有修改另一个任务或源文件。
        t=tasks{1};context=sht_startstop_modeling_package('context',t.bundle);
        e=sht_startstop_modeling_task('engineConfig',t);clear context;
        changed=sht_startstop_modeling_task('configure',t.taskDirectory, ...
            struct('engineOverrides',struct('extension',struct('HPC', ...
            struct('lockedFlowFraction',1.01*e.extension.HPC.lockedFlowFraction)))));
        assert(strcmp(changed.stages.maps.status,'stale'));
        stalePackage=sht_startstop_modeling_task('savePackage',changed.taskDirectory, ...
            fullfile(root,'stale_package'));
        assert(~stalePackage.runtimeReady);
        staleData=load(fullfile(stalePackage.directory,'modeling_package.mat'),'package');
        assert(~isfield(staleData.package.assets,'mapDirectory'));
        other=sht_startstop_modeling_task('status',tasks{2}.taskDirectory);
        assert(strcmp(other.stages.maps.status,'completed'));
        for k=1:2,sht_startstop_modeling_package('verify',tasks{k}.bundle);end
        % 不存在DLL文件也能看历史，不调用任何准备或身份重新签署。
        f=fullfile(report.outputs{1},'program','GTESS.dll');movefile(f,[f,'.held']);
        restore=onCleanup(@()movefile([f,'.held'],f)); %#ok<NASGU>
        Start_StartStopModeling_ResultView_01(report.outputs{1},false);clear restore;
        local_assert_no_engine_library();
        report.noEngineDllLoaded=true;
    end

    function local_group_b()
        assert(isfield(testConfig,'computeAuthorization') && ~isempty(testConfig.computeAuthorization), ...
            'sht:modeling:computeScope','B组必须附MAIN实际计算授权编号。');
        mode=testConfig.modelMode;cfg=local_config(mode,fullfile(root,'task'));
        assert(isfield(testConfig,'budget'),'必须传入当前批次剩余计算预算。');
        local_before_step('prepare');
        % 本组只用3x1x3=9个适用点，不调用完整81点或默认调图搜索。
        cfg.engineOverrides.stage5=struct('ngRatio',[.20,.30,.65], ...
            'npBranchNames',{{'lagging'}},'npBranchFactors',.6, ...
            'energyStateNames',{{'no_fuel','pre_ignition','fired_low_fuel'}}, ...
            'calibrationEnabled',false);
        cfg.engineOverrides.stage6=struct('caseNames',{{'nominal'}});
        cfg.engineOverrides.stage7=struct('caseNames',{{'cold_full_coupled'}});
        task=sht_startstop_modeling_task('prepare',cfg);assert(strcmp(task.status,'ready'));
        for n={'maps','design','matrix'}
            if mode==0 && strcmp(n{1},'design'),continue;end
            local_before_step(n{1});
            task=sht_startstop_modeling_task('runStage',task.taskDirectory,n{1});
            assert(task.stages.(n{1}).selectedPassed,local_stage_error(task,n{1}));
            if strcmp(n{1},'design')
                d=load(fullfile(task.taskDirectory,task.stages.design.resultFile),'result');
                life=d.result.libraryLifecycle;
                assert(~life.beforeLoaded && ~life.afterCleanupLoaded && ~libisloaded('GTESS'), ...
                    '设计阶段结束后必须释放自己加载的库。');
                if life.freeCalled,assert(life.freeStatus==0);end
                report.designLibraryLifecycle=life;
                local_save_report();
            end
        end
        report.outputs{end+1}=task.taskDirectory;
        if isfield(testConfig,'continuityKind') && ~isempty(testConfig.continuityKind)
            kind=testConfig.continuityKind;
            assert(any(strcmp(kind,{'continuous','thermal'})),'未知连续验证种类。');
            local_before_step(kind);
            task=sht_startstop_modeling_task('runStage',task.taskDirectory,kind);
            assert(task.stages.(kind).selectedPassed,local_stage_error(task,kind));
            assert(~task.stages.(kind).fullAcceptancePassed,'单算例不得写成完整正式验收。');
            if isfield(testConfig,'directComparison') && testConfig.directComparison
                local_before_step(['direct_',kind]);
                context=sht_startstop_modeling_package('context',task.bundle);
                e=sht_startstop_modeling_task('engineConfig',task);
                e.paths.outputRoot=fullfile(task.taskDirectory,'report_outputs','same_config_direct');
                if mode==0
                    key='run';if strcmp(kind,'thermal'),key='thermal';end
                    direct=Start_StartStopModel_ThreeComponent(key,e);
                    direct=direct.(kind);
                elseif strcmp(kind,'thermal')
                    direct=Start_StartStopModel_05_VisserThermalCouplingAndFreeze(e);
                else
                    direct=Start_StartStopModel_04_ContinuousStartStopAndRobustness(e);
                end
                d=load(fullfile(task.taskDirectory,task.stages.(kind).resultFile),'result');adapt=d.result;
                if isfield(adapt,kind),adapt=adapt.(kind);end
                assert(isequaln(direct.caseResults(1).mission.trace,adapt.caseResults(1).mission.trace), ...
                    '同配置适配和原入口连续输出不一致。');
                report.thermalComparison=struct('status','not_tested','stateCount',0,'maximumStateDifferenceK',NaN);
                if strcmp(kind,'thermal')
                    a=adapt.caseResults(1).mission;b=direct.caseResults(1).mission;
                    assert(~isempty(a.thermalTrace) && ~isempty(b.thermalTrace), ...
                        '热对照必须有非空热状态历程。');
                    assert(isequaln(a.thermalTrace,b.thermalTrace),'热状态及热诊断历程不一致。');
                    stateNames=adapt.caseResults(1).configuration.stage7.stateNames;
                    assert(~isempty(stateNames) && all(ismember(stateNames,a.thermalTrace.Properties.VariableNames)));
                    delta=abs(a.thermalTrace{:,stateNames}-b.thermalTrace{:,stateNames});
                    report.thermalComparison=struct('status','bitwise_equal', ...
                        'stateCount',numel(stateNames),'stateNames',{stateNames}, ...
                        'maximumStateDifferenceK',max(delta(:)));
                end
                report.directTraceBitwiseEqual=true;clear context;
            end
        end
        local_before_step('package');
        delivered=sht_startstop_modeling_task('savePackage',task.taskDirectory,fullfile(root,'candidate'));
        assert(delivered.runtimeReady);
        report.outputs{end+1}=delivered.directory;
        local_before_step('fullmode');
        moved=fullfile(root,'中文搬迁候选');
        [ok,msg]=copyfile(delivered.directory,moved);assert(ok,msg);
        use=sht_startstop_modeling_task('fullmodeConfig',moved, ...
            struct('fullmode',struct('thermalEnabled',false,'initialKind','stopped')));
        oldPath=path;oldDir=pwd;restore=onCleanup(@()local_path_restore(oldPath,oldDir)); %#ok<NASGU>
        addpath(use.programDirectory,'-begin');cd(use.programDirectory);
        s=sht_fullmode_session('prepare',use.configuration);assert(strcmp(s.lifecycle,'prepared'));
        sessionCleanup=onCleanup(@()sht_fullmode_session('close')); %#ok<NASGU>
        sht_fullmode_session('begin');s=sht_fullmode_session('advance',80);
        assert(~strcmp(s.lifecycle,'failed'),'显式候选全模式2秒消费失败。');
        record=sht_fullmode_session('result');
        report.fullmodeSampleCount=height(record.trace);
        saved=sht_fullmode_session('save',fullfile(root,'fullmode_short'));
        report.outputs{end+1}=saved.snapshot;
        report.relocatedPackage=moved;report.fullmodeSnapshot=saved.snapshot;
        report.testSourceSHA256=sht_startstop_modeling_package('hash',[mfilename('fullpath'),'.m']);
        report.snapshotSHA256=sht_startstop_modeling_package('hash',saved.snapshot);
        report.packageManifestSHA256=sht_startstop_modeling_package('hash',fullfile(moved,'files_sha256.csv'));
        clear sessionCleanup restore;
        report.cases{end+1}=struct('modelMode',mode,'matrixPointLimit',9,'calibrationEvaluations',0, ...
            'fullmodeSeconds',2,'limitedEvidenceOnly',true);
    end

    function local_before_step(phase)
        b=testConfig.budget;
        assert(isfield(b.minimumSeconds,phase),'缺少原子阶段最低剩余时间：%s。',phase);
        remaining=b.deadlineEpochSeconds-local_now_epoch();
        entry=struct('phase',phase,'remainingSeconds',remaining, ...
            'minimumSeconds',b.minimumSeconds.(phase),'startedAt',datestr(now,31));
        if ~isfield(report,'budgetChecks'),report.budgetChecks={};end
        report.budgetChecks{end+1}=entry;
        local_save_report();
        local_check_budget(remaining,b.minimumSeconds.(phase),phase);
    end

    function local_group_budget()
        local_assert_no_engine_library();
        % 实际解析新任务文件；缺状态文件应是业务错误，不是M源码语法错误。
        local_expect(@()sht_startstop_modeling_task('status',fullfile(root,'missing_task')), ...
            'sht:modeling:taskMissing');
        report.taskCodeDiagnostics=checkcode(which('sht_startstop_modeling_task'),'-id');
        local_check_budget(61,60,'sample');
        local_check_budget(60,60,'exact_boundary');
        local_expect(@()local_check_budget(59,60,'too_late'),'sht:modeling:budgetBoundary');
        local_expect(@()local_check_budget(-1,1,'expired'),'sht:modeling:budgetBoundary');
        report.cases={'above_limit_pass','exact_limit_pass','below_limit_rejected','expired_rejected'};
    end

    function cfg=local_config(mode,destination)
        source=testConfig.sourceDirectory;
        thermal=fullfile(source,'MiddleData','transient_effects_split_visser29_parameters_v2.mat');
        if mode==0,thermal=fullfile(source,'MiddleData','startstop','three_component','tc27_visser16_parameters.mat');end
        cfg=sht_startstop_modeling_config(struct('modelMode',mode,'taskId',sprintf('Test_m%d',mode), ...
            'taskDirectory',destination,'source',struct('codeDirectory',source, ...
            'modelDirectory',source,'dllDirectory',source,'thermalFile',thermal, ...
            'designStateFile',fullfile(source,'MiddleData','RunModelSHT_V2_design_state.mat')), ...
            'display',struct('showFigures',false,'generateMapFigures',false)));
        if mode==0,cfg.source.designStateFile='';end
    end

    function local_save_report()
        report.elapsedSeconds=toc(timer);
        save(fullfile(root,'test_report.mat'),'report','-v7.3');
        fid=fopen(fullfile(root,'test_report.json'),'w','n','UTF-8');
        if fid>=0,fprintf(fid,'%s',jsonencode(report));fclose(fid);end
    end
end

function local_check_budget(remaining,minimum,phase)
assert(isfinite(remaining) && isfinite(minimum) && minimum>0, ...
    'sht:modeling:budgetConfig','预算必须是有限数且最低余量大于0。');
assert(remaining>=minimum,'sht:modeling:budgetBoundary', ...
    '不再启动%s：剩余%.3f秒，所需最低余量%.3f秒。已完成阶段保留，不强杀其他进程。',phase,remaining,minimum);
end

function value=local_now_epoch()
value=posixtime(datetime('now','TimeZone','UTC'));
end

function local_assert_no_engine_library()
for a={'GTESS','GTESS_STARTSTOP','GTESS_STARTSTOP_STAGE7','GTESS_MODELING_PHYSICS','SHT_FULLMODE_R011'}
    assert(~libisloaded(a{1}),'无DLL测试中出现发动机库：%s。',a{1});
end
end

function local_same_file(a,b)
assert(strcmpi(sht_startstop_modeling_package('hash',a),sht_startstop_modeling_package('hash',b)), ...
    'sht:modeling:testIdentity','两个配套文件并非同字节：%s / %s。',a,b);
end

function local_assert_resolution(program)
for name={'sht_fullmode_session','sht_startstop_run_continuous_mission','sht_fullmode_default_config', ...
        'sht_startstop_prepare_control','sht_startstop_create_runtime','sht_load_engine_library', ...
        'sht_steady_governor_compute','Run_FullModeSimulation_Offline'}
    assert(strcmpi(char(java.io.File(which(name{1})).getCanonicalPath()), ...
        char(java.io.File(fullfile(program,[name{1},'.m'])).getCanonicalPath())), ...
        'sht:modeling:testResolution','实际解析越出保存包：%s。',name{1});
end
end

function local_check_runtime(folder,cfg)
[~,runName]=fileparts(cfg.fullmode.outputDirectory);
runtime=fullfile(cfg.paths.matlabRoot,'MiddleData','startstop',cfg.topology.assetNamespace,'runtime',runName);
source=fullfile(folder,'assets','thermal_source','runtime');
names=dir(fullfile(source,'*'));names=names(~[names.isdir]);assert(numel(names)==8);
for k=1:numel(names),local_same_file(fullfile(source,names(k).name),fullfile(runtime,names(k).name));end
end

function local_expect(action,id)
try,action();catch ex,assert(strcmp(ex.identifier,id),'异常标识不符：%s，原信息：%s。',ex.identifier,ex.message);return;end
error('sht:modeling:testExpected','应当拒绝但未拒绝：%s。',id);
end

function msg=local_stage_error(task,stage)
s=task.stages.(stage);
msg=sprintf('%s: status=%s, selectedPassed=%d',stage,s.status,s.selectedPassed);
if ~isempty(s.errorMessage) || ~isempty(s.errorIdentifier)
    msg=sprintf('%s; %s [%s]',msg,s.errorMessage,s.errorIdentifier);
end
if isfield(task.lastError,'message') && ~isempty(task.lastError.message)
    msg=[msg,'; ',task.lastError.message];
end
if ~strcmp(stage,'matrix') || s.selectedPassed,return;end
% completed_with_findings不是异常，逐点结果才包含实际未通过原因。
file=fullfile(task.taskDirectory,s.resultFile);
try
    assert(~isempty(s.resultFile) && isfile(file), ...
        'sht:modeling:diagnosticFileMissing','缺少矩阵诊断文件：%s。',file);
    d=load(file,'result');r=d.result;
    if isfield(r,'matrix'),r=r.matrix;end
    outer=r;
    if isfield(r,'finalMatrix'),r=r.finalMatrix;end
    assert(isfield(r,'points'),'sht:modeling:diagnosticSchema', ...
        '矩阵结果不含points：%s。',file);
    limits=local_matrix_limits(r,outer);
    msg=sprintf('%s; solverAccuracy=%.6e, matrixRmsLimit=%.6e, maximumLimit=%.6e, requiredRank=%g', ...
        msg,limits(1),limits(2),limits(3),limits(4));
    if any(isnan(limits)),msg=[msg,'（NaN表示历史结果未记录该限值）'];end
    failed=r.points([r.points.applicable] & ~[r.points.accepted]);
    if isempty(failed)
        msg=[msg,'; 结果没有适用失败点，请核对阶段接受标记与保存结果。'];
    end
    for k=1:numel(failed)
        p=failed(k);
        msg=sprintf(['%s\n%s: Ng=%.6g rpm, Np=%.6g rpm, callStatus=%g, ', ...
            'solverStatus=%g, solverConverged=%d, RMS=%.6e, maxResidual=%.6e, ', ...
            'rank=%g, physicalValid=%d, modelErrorCode=%g'], ...
            msg,p.caseId,p.ngRpm,p.npRpm,p.callStatus,p.solverStatus, ...
            p.solverConverged,p.residualRms,p.maximumResidual,p.rank, ...
            p.physicalValid,p.snapshot.modelErrorCode);
        if p.solverStatus==1
            msg=[msg,'; 求解器达到最大迭代次数，未满足底层收敛条件'];
        end
        if isfield(r,'attemptCountMeaning') && strcmp(r.attemptCountMeaning,'executed_seed_attempts_v1')
            msg=sprintf('%s, actualAttempts=%d, bestSeedIndex=%d', ...
                msg,p.attemptCount,p.seedSourceIndex);
        else
            msg=sprintf('%s, bestSeedIndex=%d（历史实际尝试总数未记录）',msg,p.seedSourceIndex);
        end
        if ~isempty(p.statusText),msg=[msg,'; ',p.statusText];end
        if ~isempty(p.snapshot.errorMessage),msg=[msg,'; ',p.snapshot.errorMessage];end
    end
catch ex
    msg=sprintf('%s; 诊断读取失败：%s [%s]，文件=%s',msg,ex.message,ex.identifier,file);
end
end

function limits=local_matrix_limits(matrix,outer)
% 只报告保存的实际配置，不以当前默认值替代未知的历史验收参数。
limits=nan(1,4);
if isfield(matrix,'acceptanceCriteria')
    c=matrix.acceptanceCriteria;
    limits=[c.solverAccuracyRequired,c.matrixResidualRmsTolerance, ...
        c.matrixMaximumResidualTolerance,c.requiredRank];
elseif isfield(outer,'configuration')
    c=outer.configuration;
    if isfield(c,'lowSpeedSolver'),limits(1)=c.lowSpeedSolver.accuracyRequired;end
    if isfield(c,'stage5')
        limits(2:4)=[c.stage5.matrixResidualRmsTolerance, ...
            c.stage5.matrixMaximumResidualTolerance,c.stage5.requiredRank];
    end
end
end

function local_path_restore(p,d)
cd(d);path(p);
end
