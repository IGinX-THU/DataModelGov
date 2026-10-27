function out=sht_fullmode_session(action,varargin)
%SHT_FULLMODE_SESSION ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ß¹ï¿½ï¿½Ãµï¿½ï¿½Ë¹ï¿½ï¿½Ô³ï¿½Ì¨ï¿½á»°ï¿½ï¿½ï¿½Ä¡ï¿½
% Ò»ï¿½ï¿½ï¿½ï¿½Ò»ï¿½á»°ï¿½ï¿½prepareï¿½ï¿½×¼ï¿½ï¿½ï¿½ï¿½beginï¿½ï¿½ï¿½ï¿½ï¿½Ð£ï¿½select_throttle(idle)ï¿½ï¿½ï¿½ï¿½ï¿½ð¶¯¡ï¿½
% submitï¿½ï¿½ï¿½ï¿½ï¿½ï¿½requestIdï¿½ï¿½ï¿½ï¿½È·ï¿½ï¿½ï¿½î£¬advanceÃ¿ï¿½ï¿½Ö»ï¿½á½»ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½0.025ï¿½ï¿½ï¿½ï¿½Ö²ï¿½ï¿½ï¿?% ï¿½ï¿½ï¿½ï¿½Ä´ï¿½ï¿½ï¿½Öµ×´Ì¬ï¿½ï¿½DLL/Ô´/ï¿½ï¿½ï¿½ï¿½ï¿½Ê²ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Ô£ï¿½ï¿½é¿´ï¿½ï¿½Ê·ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½DLLï¿½ï¿½
persistent S C
if nargin<1,action='status';end
switch lower(action)
    case 'prepare'
        assert(isempty(S),'´æÔÚÎ´¹Ø±ÕµÄ»î¶¯»á»°£¬ÇëÏÈcloseºóÔÙ×¼±¸¡£');
        user=struct();if ~isempty(varargin),user=varargin{1};end
        cfg=sht_fullmode_default_config(user);
        % Í¬Ô´ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Ö»ï¿½ï¿½È¡ï¿½ï¿½Ç°ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Í¨MDL/DLLï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Ê½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Ò»ï¿½ï¿½Ö§ï¿½ï¿½
        cfg.aboveIdleOverrides.engine.runtimeDirectory=cfg.paths.matlabRoot;
        cfg=sht_startstop_prepare_control(cfg);
        [cfg,asset,points,runtime,identity]=local_prepare_assets(cfg);
        C=local_open(cfg,asset,runtime);
        armed=java.util.concurrent.atomic.AtomicBoolean(true);
        cleanup=onCleanup(@()local_close_on_error(armed));
        r=local_kernel(C,cfg,points,runtime,struct('fullmodeAction','prepare'));
        b=sht_fullmode_load_boundary(cfg,0,0);
        local_call(C,'DLL_SHT_FullModeSetLoad',26100701,7,libpointer('doublePtr',b.vector));
        local_call(C,'DLL_SHT_StartStopReset',0,0,0,1);
        local_call(C,'DLL_SHT_FullModeSetLoad',26100701,7,libpointer('doublePtr',b.vector));
        T=struct('schema',26100701,'cfg',cfg,'runtime',r,'points',points, ...
            'assets',identity,'assetConfig',asset,'runtimeFiles',runtime, ...
            'lifecycle','prepared','throttle','cut','cutLatched',false,'pending',[], ...
            'receipts',repmat(local_receipt(),0,1),'events',{{}}, ...
            'traceRows',zeros(0,numel(local_trace_names())),'thermalRows',zeros(0,1+cfg.topology.temperatureCount), ...
            'wallSeconds',0,'stopReason','','createdAt',datestr(now,31));
        if ~strcmp(cfg.fullmode.initialKind,'stopped'),T=local_nonzero_initial(T,C);end
        local_call(C,'DLL_SHT_FullModeExportState',26100701,64,C.statePointer);
        T.cState=C.statePointer.Value;
        S=local_record(T);out=local_status(S);armed.set(false);clear cleanup;
    case 'begin'
        local_require(S);assert(strcmp(S.lifecycle,'prepared'),'Ö»ÓÐprepared»á»°¿ÉÒÔbegin¡£');
        S.lifecycle='running';out=local_status(S);
    case 'submit'
        local_require(S);[S,out]=local_submit(S,varargin{1});
    case 'advance'
        local_require(S);assert(strcmp(S.lifecycle,'running'),'advanceÒªÇórunning»á»°(Í£Ö¹ÊÕÎ²ÆÚ¼ä²»¿ÉÓÃ)¡£');
        n=1;if ~isempty(varargin),n=varargin{1};end
        validateattributes(n,{'numeric'},{'scalar','integer','positive','finite'});
        timer=tic;
        for i=1:n
            if S.runtime.acceptedSteps>=S.cfg.fullmode.maximumAcceptedSteps
                S.lifecycle='terminated';S.stopReason='numerical_step_budget';break;
            end
            [candidate,indices]=local_apply_pending(S);
            cfg=candidate.cfg;
            try
                previous=candidate.runtime;
                r=local_kernel(C,cfg,candidate.points,candidate.runtimeFiles, ...
                    struct('fullmodeAction','step','runtime',previous));
                candidate.runtime=r;
                local_call(C,'DLL_SHT_FullModeExportState',26100701,64,C.statePointer);
                candidate.cState=C.statePointer.Value;
                for q=indices(:).'
                    candidate.receipts(q).state='applied';
                    candidate.receipts(q).appliedTimeS=r.timeS;
                end
                candidate.pending=[];
                if ~strcmp(previous.mode,r.mode)
                    candidate.events{end+1}=struct('timeS',r.timeS,'kind','mode_change', ...
                        'from',previous.mode,'to',r.mode);
                end
                if previous.output(12)~=r.output(12)
                    candidate.events{end+1}=struct('timeS',r.timeS,'kind','freewheel_change', ...
                        'engaged',logical(r.output(12)));
                end
                S=candidate;
                stride=round(S.cfg.fullmode.recordPeriodS/S.cfg.stage6.timeStepS);
                if mod(r.acceptedSteps,stride)==0,S=local_record(S);end
            catch ex
                % ï¿½Úºï¿½ï¿½Ñ»Ø¹ï¿½CË½ï¿½ï¿½×´Ì¬ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Üµã£¬ï¿½ï¿½Öµï¿½ï¿½Ö¹ï¿½ï¿½Ã°ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Í£ï¿½ï¿½ï¿½ï¿½
                S.lifecycle='failed';S.stopReason=ex.identifier;
                S.runtime.failureReason=ex.message;
                S.events{end+1}=struct('timeS',S.runtime.timeS,'kind','numerical_failure', ...
                    'identifier',ex.identifier,'message',ex.message);break;
            end
        end
        S.wallSeconds=S.wallSeconds+toc(timer);out=local_status(S);
    case 'pause'
        local_require(S);assert(strcmp(S.lifecycle,'running'),'Î´´¦ÓÚrunning£¬²»ÄÜÔÝÍ£¡£');
        S.lifecycle='paused';out=local_status(S);
    case 'resume'
        local_require(S);assert(strcmp(S.lifecycle,'paused'),'Î´´¦ÓÚpaused£¬²»ÄÜ»Ö¸´¡£');
        S.lifecycle='running';out=local_status(S);
    case 'terminate'
        % ï¿½ï¿½Öµï¿½ï¿½Ö¹ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½î¡¢ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Ù£ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Üµï¿½ï¿½Ô¿É±ï¿½ï¿½ï¿½é¿´ï¿½ï¿½
        local_require(S);
        if ~any(strcmp(S.lifecycle,{'terminated','failed'}))
            for q=S.pending(:).',S.receipts(q).state='cancelled_by_termination';end
            S.pending=[];S.lifecycle='terminated';S.stopReason='operator_numerical_stop';
            S.events{end+1}=struct('timeS',S.runtime.timeS,'kind','numerical_termination', ...
                'description','½ô¼±¶ÏÓÍÈ·ÈÏÖ¸Áî£¬½â³ý¶ÏÓÍ±ÕËø¡£');
        end
        out=local_status(S);
    case 'status'
        if isempty(S),out=struct('lifecycle','empty');else,out=local_status(S);end
    case 'result'
        local_require(S);out=local_result(S);
    case 'save'
        local_require(S);folder=varargin{1};assert(~isempty(folder),'±£´æÄ¿Â¼²»ÄÜÎª¿Õ¡£');
        if ~isfolder(folder),mkdir(folder);end
        local_call(C,'DLL_SHT_FullModeExportState',26100701,64,C.statePointer);
        S.cState=C.statePointer.Value;result=local_result(S);
        snapshot=S;snapshot.lifecycle='paused';
        file=fullfile(folder,'fullmode_snapshot.mat');
        assert(~isfile(file) && ~isfile(fullfile(folder,'fullmode_results.xlsx')), ...
            'ï¿½Ã±ï¿½ï¿½ï¿½Ä¿Â¼ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Ê·ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Ê¹ï¿½ï¿½ï¿½Âµï¿½Ä¿Â¼ï¿½ï¿?);
        save(file,'snapshot','result','-v7.3');
        writetable(result.trace,fullfile(folder,'fullmode_results.xlsx'),'Sheet','Signals');
        if ~isempty(result.thermalTrace)
            writetable(result.thermalTrace,fullfile(folder,'fullmode_results.xlsx'),'Sheet','ThermalStates');
        end
        if ~isempty(S.receipts)
            % R2019bï¿½ï¿½ï¿½ï¿½ï¿½á¹¹Ä¬ï¿½Ï°ï¿½ï¿½Ö¶Î³ï¿½ï¿½ï¿½Õ¹ï¿½ï¿½ï¿½ï¿½Ò»ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Ò²ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Ò»ï¿½Ð¡ï¿½
            writetable(struct2table(S.receipts,'AsArray',true),fullfile(folder,'fullmode_results.xlsx'),'Sheet','Commands');
        end
        meta=struct('schema',S.schema,'configuration',S.cfg,'identity',S.assets, ...
            'events',{S.events},'physicalStop',S.runtime.physicalStop, ...
            'stopReason',S.stopReason,'elapsedWallS',S.wallSeconds,'matlabVersion',version);
        local_write_utf8(fullfile(folder,'fullmode_manifest.json'),jsonencode(meta));
        out=struct('snapshot',file,'excel',fullfile(folder,'fullmode_results.xlsx'));
    case 'restore'
        assert(isempty(S),'»Ö¸´Ç°Ðëclose£¬½ûÖ¹´æÔÚ»î¶¯»á»°¡£');
        d=load(varargin{1},'snapshot');T=d.snapshot;
        assert(T.schema==26100701,'¿ìÕÕ°æ±¾²»Æ¥Åä¡£');
        root=fileparts(mfilename('fullpath'));
        % ï¿½Ö¸ï¿½Â·ï¿½ï¿½ï¿½É°ï¿½Ç¨ï¿½ï¿½Ô´ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Ä¼ï¿½ï¿½ï¿½Ò¶ï¿½ï¿½ï¿½ï¿½ï¿½Úµï¿½Ç°ï¿½ï¿½ï¿½Ð°ï¿½ï¿½ï¿½ï¿½ï¿½×¼ï¿½ï¿½ï¿½ï¿½ï¿½Ùºï¿½SHAï¿½ï¿½
        base=struct('modelMode',T.cfg.modelMode);
        if numel(varargin)>1
            % ï¿½ï¿½Ð£ï¿½ï¿½ï¿½ï¿½È·ï¿½ï¿½Î»ï¿½Ã¸ï¿½ï¿½Ç£ï¿½ï¿½ï¿½ï¿½ï¿½Ä¬ï¿½Ï¹ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Ö®ï¿½ï¿½Ä¿ï¿½ï¿½ï¿½Cï¿½ï¿½ï¿½Ì¡ï¿½
            % ï¿½ï¿½ï¿½ï¿½Ä¬ï¿½Ï¹ï¿½ï¿½ì´«ï¿½Ý±ï¿½ï¿½ï¿½ï¿½ï¿½Ê½pathsï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Ã¿ï¿½ï¿½ï¿½ï¿½Ð¿ï¿½ï¿½ï¿½ï¿½ï¿½Ê§Ð§ï¿½Ä¾ï¿½Â·ï¿½ï¿½ï¿½ï¿½
            probe=T.cfg;probe.paths.matlabRoot=root;
            local_restore_locations(probe,varargin{2},root);
            if isfield(varargin{2},'paths'),base.paths=varargin{2}.paths;end
        end
        defaults=sht_fullmode_default_config(base);
        cfg=T.cfg;cfg.paths=defaults.paths;
        cfg.fullmode.assetDirectory=defaults.fullmode.assetDirectory;
        cfg.fullmode.seedPoolFile=defaults.fullmode.seedPoolFile;
        cfg.fullmode.outputDirectory=defaults.fullmode.outputDirectory;
        cfg.stage7.assetFile=defaults.stage7.assetFile;
        cfg.aboveIdleOverrides.engine.runtimeDirectory=root;
        if ~isempty(varargin(2:end)),cfg=local_restore_locations(cfg,varargin{2},root);end
        [cfg,asset,points,runtime,identity]=local_prepare_assets(cfg);
        local_verify_identity(T.assets,identity);
        C=local_open(cfg,asset,runtime);
        armed=java.util.concurrent.atomic.AtomicBoolean(true);
        cleanup=onCleanup(@()local_close_on_error(armed));
        T.cfg=cfg;T.assetConfig=asset;T.points=points;T.runtimeFiles=runtime;
        local_call(C,'DLL_SHT_FullModeImportState',26100701,64,libpointer('doublePtr',T.cState));
        % ï¿½Úµï¿½Ç°ï¿½Ñ±ï¿½ï¿½ï¿½×´Ì¬ï¿½Ø¹ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Â·ï¿½ï¿½ï¿½ï¿½ï¿½Æ½ï¿½ï¿½ï¿½×´Ì¬ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿?        if T.runtime.speed(2)>cfg.lowSpeedSolver.zeroHoldSpeedRpm
            a=local_kernel(C,cfg,points,runtime,struct('fullmodeAction','evaluate', ...
                'runtime',T.runtime,'command',local_c_command(T.runtime.mode)));
            assert(a.converged,'»Ö¸´Ê±ÎÈÌ¬Î´ÄÜÊÕÁ²£¬Çë¼ì²é³õÌ¬Ò»ÖÂÐÔ¡£');
            gasIndices=[1:3,15:17];
            delta=max(abs(a.output(gasIndices)-T.runtime.output(gasIndices)));
            assert(delta<1e-7,'»Ö¸´ºóÎÈÌ¬±£³ÖÁ¿²»Ò»ÖÂ(delta=%g)¡£',delta);
        end
        local_call(C,'DLL_SHT_FullModeImportState',26100701,64,libpointer('doublePtr',T.cState));
        T.lifecycle='paused';S=T;out=local_status(S);armed.set(false);clear cleanup;
    case 'close'
        if ~isempty(C)
            alias=C.alias;
            if libisloaded(alias),calllib(alias,'DLL_SHT_Free');end
            % ï¿½ï¿½ï¿½Í·ï¿½È«ï¿½ï¿½MATLABï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Ð¶ï¿½Ø£ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Øµï¿½ï¿½ï¿½ï¿½ï¿½Cï¿½ï¿½ï¿½ï¿½ï¿½ï¿½
            C=[];
            local_unload(alias);
        end
        S=[];C=[];out=struct('lifecycle','empty');
    otherwise
        error('sht:fullmode:action','Î´Öª»á»°¶¯×÷£º%s¡£',action);
end
end

function [cfg,asset,points,runtime,identity]=local_prepare_assets(cfg)
assert(isfile(cfg.fullmode.seedPoolFile),'È±ÉÙÈ·ÈÏÅäÖÃµÄ³õÖµÖÖ×Ó³ØÎÄ¼þ£º%s¡£',cfg.fullmode.seedPoolFile);
d=load(cfg.fullmode.seedPoolFile,'result');points=d.result.finalMatrix.points;
asset=[];
if cfg.fullmode.thermalEnabled
    d=load(cfg.stage7.assetFile,'parameterAsset');asset=d.parameterAsset;
    if cfg.modelMode==0,asset=sht_startstop_three_thermal_adapter(asset,cfg);end
    [ref,cache]=sht_prepare_clearance_reference_lookup(asset.referenceTable);
    cfg.stage7.enabled=true;
    cfg.stage7.initialTemperatureState=repmat(asset.referenceTable.defaultInletTotalTemperature_K, ...
        cfg.topology.temperatureCount,1);
    if ~isempty(cfg.fullmode.initialThermalState)
        cfg.stage7.initialTemperatureState=cfg.fullmode.initialThermalState(:);
    end
    cfg.stage7.stateNames=asset.topology.stateNames(3:end);
    cfg.stage7.stepInTemplate=sht_build_transient_step_in_template(asset,'joint_full');
    cfg.stage7.referenceTable=ref;cfg.stage7.clearanceReferenceCacheInfo=cache;
    cfg.stage7.inletTotalTemperatureK=asset.referenceTable.defaultInletTotalTemperature_K;
    cfg.stage7.heatCapacityJPerK=[asset.nominal.visserMetalHeatCapacity(1:cfg.topology.metalCount); ...
        asset.nominal.visserDiskHeatCapacity(:);asset.nominal.visserMetalHeatCapacity(cfg.topology.metalCount+1:end)];
    cfg.stage7.diskRootMetalIndex=asset.topology.diskRootMetalIndex(:);
else
    cfg.stage7.enabled=false;
end
cfg.lowSpeedSolver.zeroHoldSpeedRpm=cfg.stage6.gasPathActivationNgRatio*cfg.startStop.designNgRpm;
cfg.lowSpeedSolver.accuracyRequired=cfg.stage6.solverAccuracyRequired;
names=cfg.topology.componentNames;items=repmat(struct('name','','outputPath',''),1,numel(names));
for k=1:numel(names)
    items(k)=struct('name',names{k},'outputPath',fullfile(cfg.fullmode.assetDirectory,cfg.maps.(names{k}).outputName));
    assert(isfile(items(k).outputPath),'È±ÉÙÌØÐÔÍ¼Êä³öÎÄ¼þ£º%s¡£',items(k).outputPath);
end
if isempty(cfg.fullmode.outputDirectory)
    cfg.fullmode.outputDirectory=fullfile(fileparts(cfg.paths.matlabRoot),'report_outputs', ...
        'fullmode',sprintf('R011_%s',datestr(now,'yyyymmdd_HHMMSS')));
end
runtime=sht_startstop_create_runtime(cfg,struct('items',items),cfg.fullmode.outputDirectory);
files={cfg.paths.dll,cfg.paths.matlabHeader,cfg.paths.splitModel,cfg.fullmode.seedPoolFile};
if cfg.fullmode.thermalEnabled,files{end+1}=cfg.stage7.assetFile;end
for k=1:numel(items),files{end+1}=items(k).outputPath;end
code=dir(fullfile(cfg.paths.matlabRoot,'*.m'));
for k=1:numel(code),files{end+1}=fullfile(code(k).folder,code(k).name);end
identity=repmat(struct('name','','sha256','','bytes',0),numel(files),1);
for k=1:numel(files)
    [~,n,e]=fileparts(files{k});identity(k).name=[n,e];
    identity(k).sha256=local_hash(files{k});v=dir(files{k});identity(k).bytes=v.bytes;
end
end

function C=local_open(cfg,asset,runtime)
old=pwd;guard=onCleanup(@()cd(old));cd(runtime.controlDir);
alias='SHT_FULLMODE_R011';
assert(~libisloaded(alias),'DLLÒÑ¾­¼ÓÔØ£¬¿ÉÄÜ±»ÁíÒ»¸ö»á»°Õ¼ÓÃ£¬ÇëÏÈ¼ì²é×´Ì¬¡£');
sht_load_engine_library(runtime.dllPath,runtime.headerPath,'alias',alias);
C=struct('alias',alias,'engine',[],'statePointer',libpointer('doublePtr',zeros(64,1)));
try
    local_call(C,'DLL_SHT_InitialMode',cfg.modelMode);
    initialization=sht_startstop_configure_dll(alias,cfg);
    C.solverConfiguration=initialization.solverVector;
    if ~isempty(asset)
        interface=struct('libraryName',alias);
        sht_initialize_thermal_model_dll(interface,cfg.modelMode,sht_build_thermal_model_configuration(asset));
        sht_initialize_cooling_split_dll(interface,cfg.modelMode,asset.coolingSplitConfiguration);
    end
    init=struct('eng',libstruct('EngineTurboshaft'));C.engine=libstruct('EngineSHTPointer',init);clear init;
    local_call(C,'DLL_SHT_ConditionsInit',libpointer('doublePtr',zeros(512,1)), ...
        libpointer('doublePtr',zeros(128,1)),C.engine);
catch ex
    if libisloaded(alias),calllib(alias,'DLL_SHT_Free');end
    C=[];local_unload(alias);rethrow(ex);
end
end

function out=local_kernel(C,cfg,points,runtime,request)
old=pwd;guard=onCleanup(@()cd(old));cd(runtime.controlDir);
out=sht_startstop_run_continuous_mission(C.alias,C.engine,cfg,points,runtime.controlDir,request,'');
end

function S=local_nonzero_initial(S,C)
% ×¼ï¿½ï¿½ï¿½×¶Î¿ï¿½ï¿½ï¿½ï¿½ï¿½Æ½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Ê©ï¿½ï¿½ï¿½ï¿½Ö¸ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Æ½ï¿½ï¿½Ö»ï¿½ï¿½Ngï¿½ï¿½È¼ï¿½Í£ï¿½ï¿½ï¿½Â·ï¿½ï¿½Í¬ï¿½ï¿½ï¿½ï¿½
% ï¿½ï¿½Í¬Ò»ï¿½ï¿½ï¿½ï¿½DLLï¿½Úºï¿½ï¿½Ú²ï¿½ï¿½ï¿½â¡£ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Optimization Toolboxï¿½ï¿½
cfg=S.cfg;r=S.runtime;
% ï¿½ï¿½ï¿½ï¿½ï¿½Ïµï¿½ï¿½Æ½Òªï¿½ï¿?.1 rpm/sï¿½ï¿½ï¿½Ú²ï¿½ï¿½ï¿½Â·ï¿½Ð²ï¿½ï¿½ï¿½ï¿½ï¿½ã¹»Ð¡ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Öµï¿½ï¿½ï¿½ï¿?% ï¿½ï¿½Ê¹Jacobian/ï¿½Â½ï¿½ï¿½Ð¾ï¿½Ê§ï¿½æ¡£ï¿½ï¿½×¼ï¿½ï¿½ï¿½Ú¼ï¿½ï¿½Õ½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Ê±ï¿½Ö¸ï¿½ï¿½ï¿½Ê½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Ã¡ï¿½
solverBefore=C.solverConfiguration;solverTight=solverBefore;
solverTight(3)=min(solverBefore(3),1e-8);alias=C.alias;
local_solver_configuration(alias,solverTight);
solverGuard=onCleanup(@()local_solver_configuration(alias,solverBefore));
ratio=cfg.fullmode.initialNpRatio;
if strcmp(cfg.fullmode.initialKind,'idle'),ratio=cfg.stage6.idleNpRatio;end
if strcmp(cfg.fullmode.initialKind,'maximum'),ratio=1;end
assert(ratio>0 && ratio<=1.05,'µ±Ç°×ªËÙNp³¬³ö×¼±¸½×¶ÎÔÊÐí·¶Î§¡£');
r.speed=[ratio*cfg.startStop.designNpRpm;cfg.stage6.startupIdleNgRpm;ratio*cfg.startStop.designNpRpm];
% ï¿½â¹¦ï¿½ï¿½Ö±ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½PTï¿½á£¬ï¿½ï¿½ï¿½ï¿½ï¿½Ó¶ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Ü¸ï¿½Î´ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½é¹¹ï¿½ï¿½Ê¼ï¿½ï¿½ï¿½Ü¡ï¿½
if ~strcmp(cfg.fullmode.loadMode,'dual_collective'),r.speed(3)=0;end
r.mode='run';if strcmp(cfg.fullmode.initialKind,'idle'),r.mode='idle';end
r.warmupComplete=true;r.physicalStop=false;
% ï¿½ï¿½ï¿½ï¿½É¨ï¿½ï¿½ï¿½idleFuelï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½È¼ï¿½Í¡ï¿½ï¿½ï¿½ï¿½ï¿½Ö»Ñ¡ï¿½ï¿½ï¿½ï¿½Öµï¿½ï¿½ï¿½Â£ï¿½ï¿½ï¿½ï¿½Ä¿ï¿½ï¿½Æ²ï¿½ï¿½ï¿½ï¿½ï¿½
r.fuel=cfg.stage6.idleFuelFeedforwardKgPerS;
local_call(C,'DLL_SHT_FullModeExportState',26100701,64,C.statePointer);
v=C.statePointer.Value;v(9)=7;v(16)=1;v(18:20)=r.speed([2,1,3]);
local_call(C,'DLL_SHT_FullModeImportState',26100701,64,libpointer('doublePtr',v));
trimHistory=zeros(0,6);
for it=1:40
    [e,a]=local_trim_eval(S,C,r);
    r.seed=a.diagnostics(17+(1:cfg.topology.gasCount));
    trimHistory(end+1,:)=[it,r.speed(2),r.fuel,e(:).',a.diagnostics(14)]; %#ok<AGROW>
    if max(abs(e))<0.1,break;end
    J=zeros(2);x=[r.speed(2);r.fuel];step=[5;1e-5];
    for j=1:2
        rr=r;if j==1,rr.speed(2)=x(1)+step(1);else,rr.fuel=x(2)+step(2);end
        [ee,~]=local_trim_eval(S,C,rr);J(:,j)=(ee-e)/step(j);
    end
    assert(rcond(J)>1e-12,'ï¿½ï¿½Ì¬ï¿½ï¿½Æ½Jacobianï¿½ï¿½ï¿½ì£¬ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Ý¸ï¿½ï¿½Ø¡ï¿?);
    change=-(J\e);accepted=false;
    for b=0:8
        next=x+2^-b*change;
        if next(1)<=0 || next(1)>1.05*cfg.startStop.designNgRpm || next(2)<=0 || next(2)>0.7,continue;end
        rr=r;rr.speed(2)=next(1);rr.fuel=next(2);
        try,[ee,aa]=local_trim_eval(S,C,rr);catch,continue;end
        if norm(ee)<norm(e)
            rr.seed=aa.diagnostics(17+(1:cfg.topology.gasCount));
            r=rr;a=aa;accepted=true;break;
        end
    end
    if ~accepted
        % ï¿½ï¿½ï¿½ï¿½Í¼ï¿½ï¿½Öµï¿½Ûµã¸½ï¿½ï¿½ï¿½ï¿½ï¿½Newtonï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Ü²ï¿½ï¿½ï¿½ï¿½Â½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½×¼ï¿½ï¿?        % ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Þ¹ï¿½ï¿½ï¿½ï¿½ï¿½Ö²ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Í¬Ò»DLLï¿½ï¿½Ô­ï¿½ï¿½ï¿½ï¿½Ù¶ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Õ¡ï¿½
        scale=[100;1e-3];options=optimset('Display','off','MaxIter',120, ...
            'MaxFunEvals',260,'TolX',1e-7,'TolFun',1e-8);
        z=fminsearch(@(z)local_trim_cost(S,C,r,x+scale.*(z(:)-1)),ones(2,1),options);
        next=x+scale.*(z(:)-1);rr=r;rr.speed(2)=next(1);rr.fuel=next(2);
        [ee,aa]=local_trim_eval(S,C,rr);
        if norm(ee)<norm(e)
            rr.seed=aa.diagnostics(17+(1:cfg.topology.gasCount));r=rr;a=aa;accepted=true;
        end
    end
    if ~accepted
        if ~isfolder(cfg.fullmode.outputDirectory),mkdir(cfg.fullmode.outputDirectory);end
        save(fullfile(cfg.fullmode.outputDirectory,'initial_trim_failure.mat'), ...
            'trimHistory','cfg','J','x','e','change');
        error('sht:fullmode:initialTrim','³õÊ¼Î¢µ÷ºó×ªËÙÎ´ÊÕÁ²£ºdNp=%g£¬dNg=%g¡£',e(1),e(2));
    end
end
[e,a]=local_trim_eval(S,C,r);assert(max(abs(e))<0.1,'²Ð²î³¬¹ý0.1£¬Î´´ïÆ½ºâ£º%s¡£',mat2str(e));
r.output=a.output;r.snapshot=a.snapshot;r.gasTemperatureK=a.snapshot.tt45K;
r.seed=a.diagnostics(17+(1:cfg.topology.gasCount));
if r.thermal.enabled
    % ï¿½ï¿½Òªï¿½ï¿½ï¿½ï¿½Æ½ï¿½ï¿½ï¿½Ì¬ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½á¹©ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½×´Ì¬ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Ã»ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Â¶È²ï¿½ï¿½ï¿½È·ï¿½ï¿½Ç¡ï¿½
    S.events{end+1}=struct('timeS',0,'kind','nonzero_cold_metal_initial', ...
        'description','½øÆø/Í¨µÀÆ½ºâ²Ð²î×Ô¶¯ÊÕÁ²Îª¸ÃÉè¶¨Öµ£¬ÓÃÓÚÌø¹ý³õÊ¼Æ½ºâ¡£');
end
r.controller=struct('fuel',r.fuel,'command',r.fuel,'normal',[],'count',0, ...
    'temperatureLimit',r.fuel,'diag',struct(),'lastSegment',-1);
r.sensorState=struct();
r=local_kernel(C,cfg,S.points,S.runtimeFiles,struct('fullmodeAction','refresh','runtime',r));
S.runtime=r;
S.events{end+1}=struct('timeS',0,'kind','initial_trim', ...
    'history',trimHistory,'finalSpeedDerivativeRpmPerS',e(:).');
S.throttle='run';if strcmp(r.mode,'idle'),S.throttle='idle';end
S.cfg.fullmode.npRatio=ratio;
clear solverGuard;
end

function local_solver_configuration(alias,values)
status=calllib(alias,'DLL_SHT_LowSpeedSolverConfigure',26082503,numel(values), ...
    libpointer('doublePtr',values));
assert(status==0,'×¼±¸½×¶ÎÍ¨µÀÇó½â/»Ö¸´Ê§°Ü£º%d¡£',status);
end

function cost=local_trim_cost(S,C,r,x)
if x(1)<=0 || x(1)>1.05*S.cfg.startStop.designNgRpm || x(2)<=0 || x(2)>.7
    cost=1e12;return;
end
r.speed(2)=x(1);r.fuel=x(2);
try,e=local_trim_eval(S,C,r);cost=sum(e.^2);catch,cost=1e12;end
end

function [e,a]=local_trim_eval(S,C,r)
state=libpointer('doublePtr',zeros(64,1));
local_call(C,'DLL_SHT_FullModeExportState',26100701,64,state);before=state.Value;
a=local_kernel(C,S.cfg,S.points,S.runtimeFiles, ...
    struct('fullmodeAction','evaluate','runtime',r,'command',4));
local_call(C,'DLL_SHT_FullModeExportState',26100701,64,state);after=state.Value;
% Ç°7ï¿½î¸ºï¿½Ø±ï¿½ï¿½æµ±Ç°ï¿½ï¿½Ñ¯×ªï¿½Ù¸ï¿½ï¿½Â£ï¿½ï¿½ï¿½ï¿½ï¿½Ë½ï¿½ï¿½×´Ì¬ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½î±£ï¿½Ö¡ï¿½
assert(isequaln(before(8:end),after(8:end)), ...
    'ÔÝÍ£Ê±±£³ÖÆ½ºâÍÆ½øËø¶¨²¢¶³½á×´Ì¬£¬»Ö¸´ºó×ªÎª¶¯Ì¬×¼±¸¡£');
if ~a.converged
    diagnostic=struct('modelMode',S.cfg.modelMode,'loadMode',S.cfg.fullmode.loadMode, ...
        'loadConfiguration',S.cfg.fullmode.load,'speedRpm',r.speed, ...
        'fuelKgPerS',r.fuel,'thermalEnabled',r.thermal.enabled, ...
        'thermalState',r.thermal.state,'acceptedSeed',r.seed, ...
        'candidateSeeds',a.candidateSeeds,'attemptHistory',{a.attemptHistory}, ...
        'callStatus',a.callStatus,'diagnostics',a.diagnostics,'stepOut',a.output, ...
        'cStateBefore',before,'cStateAfter',after,'exceptionMessage',a.errorMessage);
    folder=fullfile(S.cfg.fullmode.outputDirectory,'diagnostics');
    if ~isfolder(folder),mkdir(folder);end
    file=[tempname(folder),'.mat'];save(file,'diagnostic','-v7.3');
    error('sht:fullmode:initialGasPath', ...
        ['Î¢µ÷ºó×´Ì¬»ã×Ü£ºNp=%g, Ng=%g rpm, Wf=%g kg/s, call=%g£»' ...
        'solver=%g, maxR=%g, µü´ú=%d, valid=%g, ÊýÖµÖ¤¾Ý£º%s%s'], ...
        r.speed(1),r.speed(2),r.fuel,a.callStatus,a.diagnostics(1), ...
        a.diagnostics(14),numel(a.attemptHistory),a.output(24),file,a.errorMessage);
end
e=a.output(1:2);
end

function [S,receipt]=local_submit(S,q)
assert(isstruct(q) && isscalar(q) && isfield(q,'requestId') && isfield(q,'action'), ...
    'ÃüÁîÓ¦Îª°üº¬requestIdÓëactionµÄ±êÁ¿½á¹¹¡£');
assert(local_text_scalar(q.requestId) && local_text_scalar(q.action), ...
    'requestIdÓëaction±ØÐëÎª·Ç¿ÕÎÄ±¾±êÁ¿¡£');
q.requestId=char(q.requestId);q.action=char(q.action);
id=char(q.requestId);assert(~isempty(id) && numel(id)<=128,'requestIdÎªï¿½Õ»ï¿½ï¿½ï¿½ï¿½ï¿½ï¿?);
existing=find(strcmp({S.receipts.requestId},id),1);
if ~isempty(existing)
    assert(strcmp(S.receipts(existing).payload,jsonencode(orderfields(q))), ...
        'Í¬Ò»requestIdÇëÇóÐ¯´øÁË²»Í¬ÔØºÉ¡£');receipt=S.receipts(existing);return;
end
receipt=local_receipt();receipt.requestId=id;receipt.action=char(q.action);
receipt.submittedAt=datestr(now,31);receipt.acceptedTimeS=S.runtime.timeS;
receipt.state='accepted';
try
    receipt.payload=jsonencode(orderfields(q));
    assert(~any(strcmp(S.lifecycle,{'failed','terminated'})),'»á»°ÒÑÖÕÖ¹£¬Ö»ÄÜ±£´æ/²é¿´/¹Ø±Õ¡£');
    cut=strcmp(q.action,'emergency_cutoff') || ...
        (strcmp(q.action,'select_throttle') && isfield(q,'value') && ...
        local_text_scalar(q.value) && strcmp(q.value,'cut'));
    if cut
        S.cutLatched=true;
        for k=S.pending(:).',S.receipts(k).state='superseded_by_cutoff';end
        S.pending=[];
    elseif S.cutLatched && ~strcmp(q.action,'acknowledge_cutoff')
        error('sht:fullmode:cutoffLatched','ÒÑ½øÈë¶ÏÓÍ±ÕËø£¬±ØÐëÏÈÈ·ÈÏÍ£×ª(acknowledge_cutoff)²ÅÄÜ½â³ý£»RUNµµ²»ÄÜÔ½¹ý¶ÏÓÍ¡£');
    end
    switch q.action
        case 'select_throttle'
            assert(isfield(q,'value') && local_text_scalar(q.value) && ...
                any(strcmp(q.value,{'cut','idle','run'})),'ÓÍÃÅµµÎ»±ØÐëÎªcut/idle/runÖ®Ò»(ÎÄ±¾Öµ)¡£');
            if strcmp(q.value,'run'),assert(S.runtime.warmupComplete && ...
                    any(strcmp(S.runtime.mode,{'idle','run'})),'Å¯ï¿½ï¿½Î´ï¿½ï¿½É»ï¿½×´Ì¬ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Ð¡ï¿?);end
        case {'start','cold_blow'}
            assert(S.runtime.physicalStop,'Æð¶¯/Àä´µÇ°±ØÐëÈ·ÈÏÎïÀíÍ£×ª£¬²ÅÄÜÆ´½ÓÐÂ¹ì¼£¡£');
            if strcmp(q.action,'start')
                assert(strcmp(S.throttle,'idle'),'±ØÐëÏÈÑ¡ÔñÂý³µµµÎ»²ÅÄÜÆð¶¯¡£');
                % Ò²ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Ì¬Í£ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Ù´ï¿½ï¿½ð¶¯£ï¿½ï¿½ï¿½ï¿½Ü½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Ã¡ï¿½
                local_check_cold_direct_load(S.cfg);
            end
        case 'exit_cold_blow'
            assert(strcmp(S.runtime.mode,'coldblow'),'µ±Ç°²»ÊÇÀä´µ×´Ì¬¡£');
        case 'abort_start'
            assert(any(strcmp(S.runtime.mode,{'cranking','warmup'})),'µ±Ç°²»ÔÚÆð¶¯/Å¯»ú½×¶Î¡£');
        case 'normal_stop'
            assert(any(strcmp(S.runtime.mode,{'idle','run','idle_handover'})),'µ±Ç°²»ÔÚÂý³µ»òÔËÐÐ×´Ì¬¡£');
        case 'emergency_cutoff'
        case 'set_np_gear'
            assert(isfield(q,'value'),'NpµµÎ»Ö¸ÁîÈ±ÉÙvalue¡£');
            validateattributes(q.value,{'numeric'},{'scalar','real','finite'});
            assert(any(q.value==[.8,.9,.95,1,1.05]),'NpµµÎ»±ØÐëÎª±ê×¼µµ80/90/95/100/105%¡£');
        case 'apply_load'
            assert(isfield(q,'value') && isstruct(q.value) && isscalar(q.value), ...
                'apply_loadÐèÒª¸ºÔØÅäÖÃ½á¹¹¡£');
            if strcmp(S.cfg.fullmode.loadMode,'power'),allowed={'powerW'};
            elseif strcmp(S.cfg.fullmode.loadMode,'mkp'),allowed={'mkpNm'};
            else,allowed={'mainPitchDeg','tailPitchDeg'};end
            names=fieldnames(q.value);
            assert(~isempty(names) && all(ismember(names,allowed)), ...
                'µ±Ç°%sÄ£Ê½ÏÂÖ»ÔÊÐíÕâÐ©×Ö¶Î£º%s¡£',S.cfg.fullmode.loadMode,strjoin(allowed,','));
            assert(~any(strcmp(S.runtime.mode,{'cranking','warmup','idle_handover'})), ...
                'Æð¶¯/Å¯»ú½×¶Î²»ÄÜÐÞ¸Ä¸ºÔØ²ÎÊý£»¸ºÔØÓ¦ÔÚÂý³µ/ÔËÐÐÊ±Ê©¼Ó£¬ÒÔ±£³ÖÅ¯»ú´°¿ÚÎÈ¶¨¡£');
            cfg=S.cfg;cfg.fullmode.load=sht_merge_config(cfg.fullmode.load,q.value);
            sht_fullmode_load_boundary(cfg,S.runtime.speed(1),S.runtime.speed(3));
            if S.runtime.physicalStop,local_check_cold_direct_load(cfg);end
        case 'acknowledge_cutoff'
            assert(S.runtime.physicalStop,'ï¿½Ð¶Ï¸ï¿½Î»ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Í£×ªï¿½ï¿?);
        otherwise
            error('sht:fullmode:command','Î´ÖªÖ¸Áî£º%s¡£',q.action);
    end
catch ex
    receipt.state='rejected';receipt.reason=ex.message;
end
S.receipts(end+1)=receipt;
if strcmp(receipt.state,'accepted'),S.pending(end+1)=numel(S.receipts);end
end

function local_check_cold_direct_load(cfg)
% Ö±ï¿½ï¿½ï¿½á¸ºï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Ô¿ï¿½Ê©ï¿½Ó£ï¿½Ö»ï¿½Ü¾ï¿½ï¿½ï¿½È¡ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Ø¾ï¿½Ö¹ï¿½ï¿½Ï¡ï¿?f=cfg.fullmode;
if (strcmp(f.loadMode,'power') && f.load.powerW>0) || ...
        (strcmp(f.loadMode,'mkp') && f.load.mkpNm>0)
    error('sht:fullmode:unsupportedColdDirectLoad', ...
        'ï¿½ï¿½Ö§ï¿½ï¿½ï¿½ï¿½ï¿½ã¹¦ï¿½ï¿½/ï¿½ï¿½ï¿½ï¿½Mkpï¿½Ó¾ï¿½Ö¹ï¿½ð¶¯»ï¿½ï¿½Ú¾ï¿½Ö¹Ê±Ê©ï¿½Ó¡ï¿½ï¿½ï¿½Ê¹ï¿½ï¿½ï¿½ï¿½ï¿½ÝµÄ·ï¿½ï¿½ï¿½ï¿½Ì¬ï¿½ï¿½ï¿½ï¿½Ê¹ï¿½ï¿½Ë«ï¿½Ü¾ï¿½ï¿½ð¶¯·ï¿½ï¿½ï¿½ï¿½ï¿?);
end
end

function [S,indices]=local_apply_pending(S)
indices=S.pending;
for k=indices(:).'
    q=jsondecode(S.receipts(k).payload);
    oldMode=S.runtime.mode;
    switch q.action
        case 'select_throttle'
            S.throttle=q.value;
            if strcmp(q.value,'cut'),S.runtime.mode='shutdown';
            elseif strcmp(q.value,'run'),S.runtime.mode='run';
            elseif strcmp(S.runtime.mode,'run'),S.runtime.mode='idle';end
        case 'start'
            S.runtime.mode='cranking';S.runtime.warmupComplete=false;
            S.runtime.controller=[];S.runtime.startupControl=[];
        case 'cold_blow'
            S.runtime.mode='coldblow';S.runtime.controller=[];
        case {'exit_cold_blow','abort_start','emergency_cutoff'}
            S.runtime.mode='shutdown';S.throttle='cut';
        case 'normal_stop'
            S.runtime.mode='cooldown';S.throttle='idle';
        case 'set_np_gear'
            S.cfg.fullmode.npRatio=q.value;
        case 'apply_load'
            S.cfg.fullmode.load=sht_merge_config(S.cfg.fullmode.load,q.value);
        case 'acknowledge_cutoff'
            S.cutLatched=false;S.throttle='cut';
    end
    if ~strcmp(oldMode,S.runtime.mode),S.runtime.modeStartS=S.runtime.timeS;end
end
end

function S=local_record(S)
r=S.runtime;p=r.plant;m=r.sample;b=r.appliedLoad;
row=[r.timeS;r.speed;p.Tt45;m.T45;p.Mkp;m.Mkp; ...
    p.Np;m.Np;p.Ng;m.Ng;r.fuel;r.output(6);r.output(4);r.output(7); ...
    r.output(12);r.output(11)*r.speed(1)*pi/30;S.cfg.fullmode.npRatio*S.cfg.startStop.designNpRpm; ...
    r.output(19);b.mainPitchDeg;b.tailPitchDeg;b.mainTorqueNm;b.tailTorqueNm; ...
    double(b.powerEngaged);r.output(24)].';
% ï¿½ï¿½24ï¿½ï¿½ÎªCï¿½ï¿½Êµï¿½ï¿½ï¿½ï¿½Â·ï¿½ï¿½Ð§ï¿½ï¿½Ç¡ï¿½ï¿½ï¿½Ð§ï¿½ï¿½Â·ï¿½ï¿½ï¿½Ô±ï¿½ï¿½ï¿½ï¿½Ä¿ï¿½ï¿½Æºï¿½ÖµÃ°ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Öµï¿½ï¿½
channels=local_extra_channels();
extra=nan(1,2*numel(channels)+1);
for k=1:numel(channels)
    name=channels{k};
    if isfield(p,name),extra(2*k-1)=p.(name);end
    if isfield(m,name),extra(2*k)=m.(name);end
end
extra(end)=p.WIn;
gasEvaluated=r.snapshot.physicalValid && all(isfinite(r.snapshot.stationWTP(:)));
actualReference=NaN;
if isfield(r.controlInfo,'governorNpReferenceRpm'),actualReference=r.controlInfo.governorNpReferenceRpm;end
S.traceRows(end+1,:)=[row,extra,double(gasEvaluated),r.output(1:2).',r.output(21:23).',actualReference];
if r.thermal.enabled,S.thermalRows(end+1,:)=[r.timeS;r.thermal.state].';end
end

function names=local_trace_names()
names={'timeS','NpRpm','NgRpm','NrotorPTEquivalentRpm','Tt45TrueK','Tt45MeasuredK', ...
    'MkpTrueNm','MkpMeasuredNm','NpTrueRpm','NpMeasuredRpm','NgTrueRpm','NgMeasuredRpm', ...
    'actuatorFuelKgPerS','effectiveFuelKgPerS','phase','flameFraction','freewheelEngaged', ...
    'actualPTLoadPowerW','NpTargetRpm','CClockS','mainPitchDeg','tailPitchDeg', ...
    'mainAeroTorqueNm','tailAeroTorqueNm','powerLoadEngaged','gasPathValid'};
channels=local_extra_channels();
units={'Pa','K','Pa','K','Pa','Pa','K','K','Nm','Pa','K','m',''};
for k=1:numel(channels)
    names=[names,{[channels{k},'True',units{k}],[channels{k},'Measured',units{k}]}]; %#ok<AGROW>
end
names{end+1}='inletMassFlowKgPerS';
names{end+1}='gasPathEvaluated';
names=[names,{'NpDotRpmPerS','NgDotRpmPerS','hotStartFlag','hungStartFlag','flameoutFlag'}];
names{end+1}='NpGovernorReferenceRpm';
end

function channels=local_extra_channels()
channels={'Pt2','Tt1','Pt3','Tt3','Pt45','Pt5','Tt5','T4','Mkg','Pamb','Tamb','Altitude','Mach'};
end

function yes=local_text_scalar(value)
yes=(ischar(value) && isrow(value) && ~isempty(value)) || ...
    (isstring(value) && isscalar(value) && ~ismissing(value) && strlength(value)>0);
end

function result=local_result(S)
names=local_trace_names();
result=struct('configuration',S.cfg,'identity',S.assets,'trace',array2table(S.traceRows,'VariableNames',names), ...
    'thermalTrace',table(),'commands',S.receipts,'events',{S.events}, ...
    'terminalStatus',local_status(S),'matlabVersion',version,'createdAt',S.createdAt);
if S.runtime.thermal.enabled
    thermalNames=[{'timeS'},reshape(S.runtime.thermal.stateNames,1,[])];
    thermalNames=matlab.lang.makeValidName(thermalNames);
    result.thermalTrace=array2table(S.thermalRows,'VariableNames',thermalNames);
end
result.signalRoles=struct('truth',{{'NpTrueRpm','NgTrueRpm','Tt45TrueK','MkpTrueNm'}}, ...
    'measuredFeedback',{{'NpMeasuredRpm','NgMeasuredRpm','Tt45MeasuredK','MkpMeasuredNm'}}, ...
    'derived',{{'NrotorPTEquivalentRpm','actualPTLoadPowerW'}}, ...
    'unmodeled',{{'oilPressure','oilTemperature','electricalBus'}});
for k=27+2*(0:numel(local_extra_channels())-1)
    result.signalRoles.truth{end+1}=names{k};
end
result.signalRoles.measured=names(contains(names,'Measured'));
result.signalRoles.derived{end+1}='inletMassFlowKgPerS';
result.signalRoles.diagnostics={'gasPathValid','gasPathEvaluated','NpDotRpmPerS', ...
    'NgDotRpmPerS','hotStartFlag','hungStartFlag','flameoutFlag'};
result.signalRoles.derived{end+1}='NpGovernorReferenceRpm';
result.recordSchema=26100704;
result.signalRoles.validity=['gasPathValidÎªDLL²à24Í¨µÀÓÐÐ§±êÖ¾(ÓÉÆøÂ·ÏµÊý¾ö¶¨)£¬' ...
    'gasPathEvaluated±íÊ¾Êµ¼Ê½øÈëÆøÂ·½âËã¡£NaN±íÊ¾¸ÃÑù±¾Î´²ÎÓë½âËã¡£'];
end

function out=local_status(S)
r=S.runtime;
p=r.plant;m=r.sample;
out=struct('lifecycle',S.lifecycle,'mode',r.mode,'throttle',S.throttle,'timeS',r.timeS, ...
    'speedRpm',r.speed,'acceptedSteps',r.acceptedSteps,'physicalStop',r.physicalStop, ...
    'warmupComplete',r.warmupComplete,'cutLatched',S.cutLatched,'failureReason',r.failureReason, ...
    'stopReason',S.stopReason,'wallSeconds',S.wallSeconds,'commandReceipts',S.receipts, ...
    'appliedLoad',r.appliedLoad,'requestedLoad',S.cfg.fullmode.load, ...
    'tt45K',p.Tt45,'tt45MeasuredK',m.T45,'fuelKgPerS',r.fuel, ...
    'npDesignRpm',S.cfg.startStop.designNpRpm,'npRatioTarget',S.cfg.fullmode.npRatio, ...
    'alarms',struct('hotStart',logical(r.output(21)),'hungStart',logical(r.output(22)), ...
    'flameout',logical(r.output(23))));
end

function r=local_receipt()
r=struct('requestId','','action','','state','','submittedAt','','acceptedTimeS',NaN, ...
    'appliedTimeS',NaN,'reason','','payload','');
end

function local_require(S)
assert(~isempty(S),'ÉÐÎ´prepare»á»°¡£');
end
function local_call(C,name,varargin)
status=calllib(C.alias,name,varargin{:});assert(status==0,'DLLµ÷ÓÃ%sÊ§°Ü£º%d¡£',name,status);
end
function local_unload(alias)
if libisloaded(alias),unloadlibrary(alias);end
end
function local_close_on_error(armed)
% prepare/restoreï¿½ï¿½onCleanupï¿½ï¿½ï¿½ï¿½ï¿½ì³£Ê±ï¿½Ø±Õ£ï¿½ï¿½É¹ï¿½ï¿½ï¿½ï¿½Éµï¿½ï¿½Ã·ï¿½ï¿½ï¿½Ê½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿?if armed.get(),sht_fullmode_session('close');end
end
function h=local_hash(file)
fid=fopen(file,'rb');assert(fid>=0,'ÎÞ·¨¶ÁÈ¡¶þ½øÖÆÎÄ¼þ£º%s¡£',file);c=onCleanup(@()fclose(fid));
d=java.security.MessageDigest.getInstance('SHA-256');d.update(typecast(fread(fid,inf,'*uint8'),'int8'));
h=upper(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end
function local_verify_identity(a,b)
assert(numel(a)==numel(b),'»Ö¸´Ô´Óë³õÌ¬µ¥Î»²»Ò»ÖÂ£¬»Ö¸´¿ÉÄÜÊ§°Ü£¬Çë¼ì²é±êÇ©¡£');
for i=1:numel(a)
    assert(strcmp(a(i).name,b(i).name) && strcmp(a(i).sha256,b(i).sha256), ...
        '»Ö¸´Êý¾Ý²»Æ¥Åä£º%s¡£',a(i).name);
end
end
function n=local_c_command(mode)
if strcmp(mode,'run'),n=2;elseif strcmp(mode,'coldblow'),n=5;
elseif any(strcmp(mode,{'cranking','warmup'})),n=1;
elseif strcmp(mode,'stopped'),n=0;
elseif strcmp(mode,'shutdown'),n=3;else,n=4;end
end
function cfg=local_restore_locations(cfg,override,root)
% ï¿½Ö¸ï¿½Ö»×¼ï¿½ï¿½Ç¨ï¿½ï¿½Ð´Î»ï¿½Ã£ï¿½ï¿½ï¿½ï¿½ï¿½/ï¿½ï¿½ï¿½ï¿½/ï¿½ï¿½ï¿½ï¿½ï¿½Þ¸ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½×¼ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½Ê½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½ï¿½î¡£
assert(isstruct(override) && isscalar(override),'»Ö¸´Î»ÖÃ¸²¸ÇÓ¦Îª±êÁ¿½á¹¹¡£');
groups=fieldnames(override);assert(all(ismember(groups,{'paths','fullmode','stage7'})), ...
    '»Ö¸´²»ÄÜÐÞ¸ÄÍÆ½ø×´Ì¬Ïà¹ØÉèÖÃ¡£');
for i=1:numel(groups)
    group=groups{i};items=override.(group);assert(isstruct(items) && isscalar(items));
    if strcmp(group,'paths'),allowed=fieldnames(cfg.paths);
    elseif strcmp(group,'fullmode'),allowed={'outputDirectory','assetDirectory','seedPoolFile'};
    else,allowed={'assetFile'};end
    fields=fieldnames(items);assert(all(ismember(fields,allowed)),'»Ö¸´ÔØºÉÖ»ÔÊÐíÍ¨µÀ×Ö¶Î¡£');
    for j=1:numel(fields)
        value=items.(fields{j});assert(ischar(value) || (isstring(value) && isscalar(value)));
        cfg.(group).(fields{j})=char(value);
    end
end
assert(strcmp(cfg.paths.matlabRoot,root),'Ô´ÂëÄ¿Â¼ÓëÊµ¼ÊÔËÐÐÄ¿Â¼²»Ò»ÖÂ£¬¿ÉÄÜÒÑ¸Ä¶¯¡£');
end
function local_write_utf8(file,text)
fid=fopen(file,'w','n','UTF-8');assert(fid>=0);c=onCleanup(@()fclose(fid));fprintf(fid,'%s',text);
end
