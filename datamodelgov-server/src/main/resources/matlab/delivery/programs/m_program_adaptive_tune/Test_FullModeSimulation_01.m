function result=Test_FullModeSimulation_01(group,folder,varargin)
%TEST_FULLMODESIMULATION_01 R011分组验收；由MAIN核定计算窗口后运行。
% contract:命令/幂等/暂停切断/冷吹/保存；continuous:三六部件连续起动暖机
% loads:直接功率/扭矩及五挡；restore_prepare/restore_compare:独立进程恢复
% 所有结果保存新目录，不以exit=0代替每项assert和数值记录。
assert(strcmp(version('-release'),'2019b'),'本轮必须用MATLAB R2019b实测。');
if ~isfolder(folder),mkdir(folder);end
assert(~isfile(fullfile(folder,'test_result.mat')),'不能覆盖历史测试。');
timer=tic;result=struct('group',group,'matlabVersion',version,'cases',{{}},'accepted',false);
cleanup=onCleanup(@()sht_fullmode_session('close'));
try
switch group
    case 'static'
        files={'Start_FullModeSimulation_01','Run_FullModeSimulation_Offline', ...
            'sht_fullmode_session','sht_fullmode_default_config','sht_fullmode_load_boundary', ...
            'Start_FullModeSimulation_ResultView_01','Test_FullModeSimulation_01', ...
            'sht_startstop_default_config','sht_startstop_run_continuous_mission'};
        issues=struct();root=fileparts(mfilename('fullpath'));
        for k=1:numel(files)
            items=checkcode(fullfile(root,[files{k},'.m']),'-id');issues.(files{k})=items;
            bad=arrayfun(@(x)~isempty(regexp(x.id,'PARSE|SYNTAX','once')),items);
            assert(~any(bad),'R2019b语法错误：%s。',files{k});
        end
        result.issues=issues;result.noToolboxDefault=true;
    case 'contract'
        cfg=struct('modelMode',0,'fullmode',struct('thermalEnabled',false, ...
            'outputDirectory',fullfile(folder,'runtime')));
        sht_fullmode_session('prepare',cfg);sht_fullmode_session('begin');
        q=struct('requestId','idle','action','select_throttle','value','idle');
        a=sht_fullmode_session('submit',q);b=sht_fullmode_session('submit',q);
        assert(isequaln(a,b),'幂等命令返回不一致。');
        s=sht_fullmode_session('advance',4);assert(strcmp(s.mode,'stopped'),'选择慢车不应起动。');
        state=libpointer('doublePtr',zeros(64,1));
        assert(calllib('SHT_FULLMODE_R011','DLL_SHT_FullModeExportState',26100701,64,state)==0);
        before=state.Value;
        assert(calllib('SHT_FULLMODE_R011','DLL_SHT_FullModeExportState',0,64,state)~=0);
        assert(calllib('SHT_FULLMODE_R011','DLL_SHT_FullModeImportState',26100701,63,state)~=0);
        bad=before;bad(64)=1;
        assert(calllib('SHT_FULLMODE_R011','DLL_SHT_FullModeImportState',26100701,64,libpointer('doublePtr',bad))~=0);
        assert(calllib('SHT_FULLMODE_R011','DLL_SHT_FullModeExportState',26100701,64,state)==0);
        assert(isequaln(before,state.Value),'错误状态导入损坏当前会话。');
        a=sht_fullmode_session('submit',struct('requestId','run_early','action','select_throttle','value','run'));
        assert(strcmp(a.state,'rejected'),'未暖机RUN必须明确拒绝。');
        sht_fullmode_session('submit',struct('requestId','blow','action','cold_blow'));
        s=sht_fullmode_session('advance',80);r=sht_fullmode_session('result');
        assert(all(r.trace.effectiveFuelKgPerS==0),'冷吹不能供油。');
        assert(s.speedRpm(2)>0,'冷吹起动机未带转。');
        sht_fullmode_session('pause');time=s.timeS;
        a=sht_fullmode_session('submit',struct('requestId','cut','action','emergency_cutoff'));
        assert(strcmp(a.state,'accepted'));
        s=sht_fullmode_session('status');assert(s.timeS==time && s.cutLatched,'暂停切断必须锁存且不积分。');
        a=sht_fullmode_session('submit',struct('requestId','run_after_cut','action','select_throttle','value','run'));
        assert(strcmp(a.state,'rejected'),'RUN不能绕过锁存切断。');
        sht_fullmode_session('resume');s=sht_fullmode_session('advance',4);
        assert(strcmp(s.mode,'shutdown') || strcmp(s.mode,'stopped'));
        saved=sht_fullmode_session('save',fullfile(folder,'save'));
        sht_fullmode_session('close');r=Start_FullModeSimulation_ResultView_01(saved.snapshot,false);
        assert(~libisloaded('SHT_FULLMODE_R011'),'历史查看不应加载DLL。');
        t=readtable(saved.excel,'Sheet','Signals');assert(height(t)==height(r.trace),'Excel记录不完整。');
        result.cases={r};
        % 中止起动和冷吹退出均切断供油，但不能改写轴速为零。
        sht_fullmode_session('close');Start_FullModeSimulation_01(cfg);
        sht_fullmode_session('submit',q);sht_fullmode_session('advance',1);
        sht_fullmode_session('submit',struct('requestId','start','action','start'));
        s=sht_fullmode_session('advance',80);assert(strcmp(s.lifecycle,'running'),s.failureReason);
        a=sht_fullmode_session('submit',struct('requestId','abort','action','abort_start'));
        assert(strcmp(a.state,'accepted'));s=sht_fullmode_session('advance',4);
        r=sht_fullmode_session('result');assert(r.trace.effectiveFuelKgPerS(end)==0);
        result.cases{end+1}=r;
        sht_fullmode_session('close');Start_FullModeSimulation_01(cfg);
        sht_fullmode_session('submit',struct('requestId','blow','action','cold_blow'));
        sht_fullmode_session('advance',40);
        a=sht_fullmode_session('submit',struct('requestId','exit','action','exit_cold_blow'));
        assert(strcmp(a.state,'accepted'));s=sht_fullmode_session('advance',4);
        assert(any(strcmp(s.mode,{'shutdown','stopped'})));result.cases{end+1}=sht_fullmode_session('result');
        % 相同物理配置和命令分别通过人工入口、离线入口推进，核对全部记录。
        sht_fullmode_session('close');cfg.fullmode.sensor=struct('mode','firstOrder', ...
            'timeConstant',.05,'noiseStd',.1,'randomSeed',1701);
        plan=struct('durationS',2,'commands',{{struct('requestId','blow','action','cold_blow','atTimeS',0)}});
        offline=Run_FullModeSimulation_Offline(cfg,plan);
        Start_FullModeSimulation_01(cfg);
        sht_fullmode_session('submit',struct('requestId','blow','action','cold_blow'));
        s=sht_fullmode_session('advance',80);assert(strcmp(s.lifecycle,'running'),s.failureReason);
        manual=sht_fullmode_session('result');assert(isequaln(offline.trace,manual.trace),'同配置双入口不一致。');
        result.dualEntryBitwise=true;result.cases{end+1}=manual;
        before=sht_fullmode_session('status');stopped=sht_fullmode_session('terminate');
        assert(strcmp(stopped.lifecycle,'terminated') && strcmp(stopped.stopReason,'operator_numerical_stop'));
        assert(isequal(before.speedRpm,stopped.speedRpm) && before.timeS==stopped.timeS && ~stopped.physicalStop);
        again=sht_fullmode_session('terminate');assert(isequaln(stopped,again));
        rejected=false;try,sht_fullmode_session('advance',1);catch,rejected=true;end
        assert(rejected,'数值终止后不能悄悄继续积分。');
        result.numericalTermination=true;
        sht_fullmode_session('close');badCfg=cfg;badCfg.startStop.rotorReflectedInertiaKgM2=-1;
        failed=false;
        try,sht_fullmode_session('prepare',badCfg);catch ex,failed=true;result.prepareFailure=ex.message;end
        assert(failed && ~libisloaded('SHT_FULLMODE_R011'),'准备失败未正确卸载配对DLL。');
    case 'completion_contract'
        % 非法操纵必须在提交时明确拒绝，不能等积分时才暴露类型错误。
        for loadMode={'power','mkp','dual_collective'}
            cfg=struct('modelMode',0,'fullmode',struct('thermalEnabled',false, ...
                'loadMode',loadMode{1},'outputDirectory',fullfile(folder,loadMode{1})));
            Start_FullModeSimulation_01(cfg);
            values={NaN,Inf,[.8,.9],.85,1i,[],'.8'};
            for k=1:numel(values)
                a=sht_fullmode_session('submit',struct('requestId',sprintf('badgear%d',k), ...
                    'action','set_np_gear','value',values{k}));
                assert(strcmp(a.state,'rejected'),'非法挡位在提交时未被拒绝。');
            end
            a=sht_fullmode_session('submit',struct('requestId','badthrottle', ...
                'action','select_throttle','value',{{'idle','cut'}}));
            assert(strcmp(a.state,'rejected'),'油门只接受一个文本值。');
            if strcmp(loadMode{1},'power'),good=struct('powerW',0);bad=struct('mkpNm',2);
            elseif strcmp(loadMode{1},'mkp'),good=struct('mkpNm',0);bad=struct('powerW',2);
            else,good=struct('mainPitchDeg',6,'tailPitchDeg',5);bad=struct('powerW',2);end
            for item={bad,struct('typo',1),struct(),repmat(good,1,2)}
                current=sht_fullmode_session('status');
                a=sht_fullmode_session('submit',struct('requestId',sprintf('badload%d',numel(current.commandReceipts)), ...
                    'action','apply_load','value',item{1}));
                assert(strcmp(a.state,'rejected'),'不适用的负载字段未被拒绝。');
            end
            a=sht_fullmode_session('submit',struct('requestId','goodload','action','apply_load','value',good));
            assert(strcmp(a.state,'accepted'));s=sht_fullmode_session('advance',4);
            assert(strcmp(s.lifecycle,'running'),s.failureReason);
            result.cases{end+1}=sht_fullmode_session('result');sht_fullmode_session('close');
        end
        cfg=struct('modelMode',0,'fullmode',struct('thermalEnabled',false, ...
            'sensor',struct('mode','firstOrder','timeConstant',.05*ones(23,1),'noiseStd',0), ...
            'outputDirectory',fullfile(folder,'cold_sensor')));
        Start_FullModeSimulation_01(cfg);
        sht_fullmode_session('submit',struct('requestId','idle','action','select_throttle','value','idle'));
        sht_fullmode_session('advance',1);
        sht_fullmode_session('submit',struct('requestId','start','action','start'));
        s=sht_fullmode_session('advance',600);assert(strcmp(s.lifecycle,'running'),s.failureReason);
        r=sht_fullmode_session('result');valid=r.trace.gasPathEvaluated==1;
        assert(any(valid) && any(~valid),'没有覆盖气路首次激活。');
        assert(all(isfinite(r.trace.Pt3MeasuredPa(valid))) && all(isfinite(r.trace.Tt3MeasuredK(valid))), ...
            '冷态缺失通道首次激活后FOH仍为NaN。');
        saved=sht_fullmode_session('save',fullfile(folder,'sensor_save'));d=load(saved.snapshot,'snapshot');
        assert(d.snapshot.runtime.output(24)==r.trace.gasPathValid(end),'有效标志槽未对齐。');
        assert(any(d.snapshot.runtime.sensorState.availabilityInitializations>0),'没有记录首次有效初始化。');
        t=readtable(saved.excel,'Sheet','Signals');assert(width(t)==60 && height(t)==height(r.trace));
        assert(isequal(t.gasPathValid,r.trace.gasPathValid));
        assert(isequal([s.alarms.hotStart,s.alarms.hungStart,s.alarms.flameout], ...
            logical(d.snapshot.runtime.output(21:23).')),'告警状态与DLL实际槽不一致。');
        result.cases{end+1}=r;result.saved=saved;
    case 'completion_initials'
        result.initialStates={};
        for mode=0:1
            for kind={'cruise','maximum'}
                cfg=struct('modelMode',mode,'fullmode',struct('initialKind',kind{1}, ...
                    'thermalEnabled',false,'outputDirectory',fullfile(folder,sprintf('m%d_%s',mode,kind{1}))));
                Start_FullModeSimulation_01(cfg);s0=sht_fullmode_session('status');
                s=sht_fullmode_session('advance',80);assert(strcmp(s.lifecycle,'running'),s.failureReason);
                r=sht_fullmode_session('result');assert(all(r.trace.gasPathValid==1));
                assert(abs(r.trace.NpRpm(1)-r.trace.NpTargetRpm(1))<1e-6,'初态转速与配置不符。');
                result.cases{end+1}=r;result.initialStates{end+1}=s0;sht_fullmode_session('close');
            end
        end
    case {'completion_power_start','completion_mkp_start'}
        error('sht:fullmode:cancelledTest', ...
            '用户已取消正恒功率/正恒Mkp静止起动，历史失败证据保留；请执行scope合同测试，不再运行旧接载探索。');
    case 'scope'
        for mode=0:1
            for kind={'power','mkp'}
                value=struct('powerW',126000);
                if strcmp(kind{1},'mkp'),value=struct('mkpNm',150);end
                cfg=struct('modelMode',mode,'fullmode',struct('loadMode',kind{1}, ...
                    'load',value,'thermalEnabled',false));
                rejected=false;
                try,sht_fullmode_session('prepare',cfg);
                catch ex,rejected=strcmp(ex.identifier,'sht:fullmode:unsupportedColdDirectLoad');end
                assert(rejected && ~libisloaded('SHT_FULLMODE_R011'), ...
                    '不支持的静止正负载必须在加载DLL前明确拒绝。');
                % 非零初态仍合法；其数值能力由既有三负载/五挡实测覆盖。
                cfg.fullmode.initialKind='idle';checked=sht_fullmode_default_config(cfg);
                assert(strcmp(checked.fullmode.loadMode,kind{1}));
                cfg.fullmode.initialKind='stopped';
                if strcmp(kind{1},'power'),cfg.fullmode.load.powerW=0;else,cfg.fullmode.load.mkpNm=0;end
                Start_FullModeSimulation_01(cfg);
                before=sht_fullmode_session('status');
                q=struct('requestId','positive_at_rest','action','apply_load','value',value);
                a=sht_fullmode_session('submit',q);b=sht_fullmode_session('submit',q);
                assert(strcmp(a.state,'rejected') && isequaln(a,b) && contains(a.reason,'不支持正恒'));
                after=sht_fullmode_session('status');assert(isequal(before.speedRpm,after.speedRpm));
                assert(before.timeS==after.timeS,'拒绝命令不能推进状态。');
                result.cases{end+1}=sht_fullmode_session('result');sht_fullmode_session('close');
            end
        end
        result.cancelledPositiveDirectColdStart=true;
    case 'completion_stop'
        cfg=struct('modelMode',0,'fullmode',struct('initialKind','idle', ...
            'outputDirectory',fullfile(folder,'runtime')));
        Start_FullModeSimulation_01(cfg);
        sht_fullmode_session('submit',struct('requestId','stop','action','normal_stop'));
        s=local_advance_until('stopped',1500);
        assert(s.physicalStop && all(s.speedRpm<=.5),'未达到完整物理停车：%s。',mat2str(s.speedRpm));
        result.cases={sht_fullmode_session('result')};
        saved=sht_fullmode_session('save',fullfile(folder,'stopped'));result.saved=saved;
    case 'relocated'
        root=fileparts(mfilename('fullpath'));
        assert(contains(root,'中文离线包'),'搬迁验证必须实际来自中文路径的新运行包。');
        cfg=struct('modelMode',0,'fullmode',struct('initialKind','idle', ...
            'thermalEnabled',false,'outputDirectory',fullfile(folder,'runtime')));
        Start_FullModeSimulation_01(cfg);s=sht_fullmode_session('advance',20);
        assert(strcmp(s.lifecycle,'running'),s.failureReason);
        r=sht_fullmode_session('result');result.cases={r};
        assert(startsWith(r.configuration.paths.matlabRoot,root),'搬迁后仍引用开发源码根。');
        result.saved=sht_fullmode_session('save',fullfile(folder,'saved'));
        sht_fullmode_session('close');
        listed=inmem('-completenames');
        for k=1:numel(listed)
            [~,name]=fileparts(listed{k});
            if startsWith(name,'sht_') || startsWith(name,'Start_FullMode') || startsWith(name,'Run_FullMode')
                assert(startsWith(listed{k},root),'混入外部算法源：%s。',listed{k});
            end
        end
        result.dynamicDependencyPaths=listed;
    case 'continuous'
        for mode=0:1
            % 延长数值观察窗以覆盖实际停转；不改变任何控制时刻和参数。
            cfg=struct('modelMode',mode,'fullmode',struct('outputDirectory',fullfile(folder,sprintf('model%d',mode)), ...
                'saveDirectory',fullfile(folder,sprintf('model%d_saved',mode))));
            plan=struct('durationS',450,'commands',{{ ...
                struct('requestId','idle','action','select_throttle','value','idle','atTimeS',0), ...
                struct('requestId','start','action','start','atTimeS',.025), ...
                struct('requestId','run','action','select_throttle','value','run','atTimeS',0,'whenMode','idle'), ...
                struct('requestId','stop','action','normal_stop','atTimeS',250)}});
            r=Run_FullModeSimulation_Offline(cfg,plan);
            result.cases{end+1}=r; % 断言失败也保留本模型完整结果。
            assert(strcmp(r.terminalStatus.lifecycle,'running'),'连续仿真发生数值终止。');
            assert(r.terminalStatus.warmupComplete,'未完成60秒Ng暖机。');
            assert(max(r.trace.Tt45TrueK(r.trace.gasPathEvaluated==1))<=r.configuration.startStop.maximumGasTemperatureK, ...
                '连续过程出现超过现行温限的真实温度，不能仅凭数值运行成功验收。');
            eventKinds=cellfun(@(e)e.kind,r.events,'UniformOutput',false);
            assert(any(strcmp(eventKinds,'mode_change')));
            assert(any(r.trace.phase==8),'未显式进入运行。');
            assert(any(r.trace.phase==9),'未执行计划停车。');
            assert(all(abs(diff(r.trace.timeS)-.1)<1e-8),'不是完整10Hz记录。');
            assert(max(abs(r.trace.CClockS-r.trace.timeS))<1e-7,'C时钟被Heun预览多推进。');
            warm=cellfun(@(e)strcmp(e.kind,'mode_change') && strcmp(e.to,'idle_handover'),r.events);
            assert(any(warm),'没有记录暖机交接。');
            j=find(warm,1);assert(r.events{j}.timeS>=60,'不能跳过60秒稳定暖机。');
            run=find(strcmp({r.commands.action},'select_throttle') & contains({r.commands.payload},'run'),1);
            assert(~isempty(run) && strcmp(r.commands(run).state,'applied'),'RUN必须来自操作者命令。');
            assert(r.terminalStatus.physicalStop && all(r.terminalStatus.speedRpm<=.5), ...
                '完整观察窗未达到物理停车：%s。',mat2str(r.terminalStatus.speedRpm));
        end
    case 'loads'
        for model=0:1
        for loadMode={'power','mkp','dual_collective'}
            cfg=struct('modelMode',model,'fullmode',struct('loadMode',loadMode{1}, ...
                'initialKind','idle','thermalEnabled',false,'outputDirectory',fullfile(folder,sprintf('m%d_%s',model,loadMode{1}))));
            if strcmp(loadMode{1},'power'),cfg.fullmode.load=struct('powerW',126000);
            elseif strcmp(loadMode{1},'mkp'),cfg.fullmode.load=struct('mkpNm',126000/(14000*pi/30));end
            Start_FullModeSimulation_01(cfg);
            if ~strcmp(loadMode{1},'dual_collective')
                r0=sht_fullmode_session('result');
                assert(r0.trace.NrotorPTEquivalentRpm(1)==0,'直接轴负载不应给未连接旋翼赋予初始动能。');
            end
            sht_fullmode_session('submit',struct('requestId','run','action','select_throttle','value','run'));
            for gear=[.8,.9,.95,1,1.05]
                sht_fullmode_session('submit',struct('requestId',sprintf('gear%g',gear), ...
                    'action','set_np_gear','value',gear));
                % 原升/降速参考过渡20秒；再保持5秒观察实际跟踪，不在斜坡中判稳态。
                s=sht_fullmode_session('advance',1000);
                assert(strcmp(s.lifecycle,'running'),s.failureReason);
                r=sht_fullmode_session('result');
                assert(r.trace.NpTargetRpm(end)==gear*r.configuration.startStop.designNpRpm);
                assert(abs(s.speedRpm(1)-r.trace.NpTargetRpm(end))< ...
                    r.configuration.stage6.npStableToleranceRatio*r.configuration.startStop.designNpRpm, ...
                    '实际Np未跟踪挡位%g：Np=%g，目标=%g。',gear,s.speedRpm(1),r.trace.NpTargetRpm(end));
            end
            if strcmp(loadMode{1},'dual_collective')
                sht_fullmode_session('submit',struct('requestId','main','action','apply_load', ...
                    'value',struct('mainPitchDeg',8,'tailPitchDeg',-2)));
            elseif strcmp(loadMode{1},'power')
                sht_fullmode_session('submit',struct('requestId','power','action','apply_load', ...
                    'value',struct('powerW',200000)));
            else
                sht_fullmode_session('submit',struct('requestId','torque','action','apply_load', ...
                    'value',struct('mkpNm',150)));
            end
            s=sht_fullmode_session('advance',400);assert(strcmp(s.lifecycle,'running'),s.failureReason);
            r=sht_fullmode_session('result');
            if strcmp(loadMode{1},'power')
                assert(max(abs(r.trace.actualPTLoadPowerW(end-50:end)-200000))<1e-6,'恒实际功率不成立。');
            elseif strcmp(loadMode{1},'mkp')
                assert(max(abs(r.trace.MkpTrueNm(end-50:end)-150))<1e-9,'恒Mkp不成立。');
            end
            assert(max(r.trace.Tt45TrueK(r.trace.gasPathEvaluated==1))<=r.configuration.startStop.maximumGasTemperatureK, ...
                '在线操纵真实温度超过现行温限，不能只看末端Np误差。');
            sht_fullmode_session('submit',struct('requestId','cut','action','emergency_cutoff'));
            s=sht_fullmode_session('advance',400);assert(strcmp(s.lifecycle,'running'),s.failureReason);
            r=sht_fullmode_session('result');assert(all(r.trace.effectiveFuelKgPerS(end-50:end)==0));
            assert(max(r.trace.Tt45TrueK(r.trace.gasPathEvaluated==1))<=r.configuration.startStop.maximumGasTemperatureK, ...
                '负载/挡位试验真实温度超过现行温限，不能只看末端Np误差。');
            result.cases{end+1}=r;sht_fullmode_session('close');
        end
        end
    case 'restore_prepare'
        cfg=struct('modelMode',1,'fullmode',struct('initialKind','idle', ...
            'sensor',struct('mode','firstOrder','timeConstant',.05,'noiseStd',.1,'randomSeed',1701), ...
            'outputDirectory',fullfile(folder,'runtime')));
        Start_FullModeSimulation_01(cfg);s=sht_fullmode_session('advance',200);
        assert(strcmp(s.lifecycle,'running'),s.failureReason);
        % 在20秒Np参考过渡中保存，验证参考进度和带噪传感器均可冷恢复。
        sht_fullmode_session('submit',struct('requestId','restore_run','action','select_throttle','value','run'));
        sht_fullmode_session('submit',struct('requestId','restore_gear','action','set_np_gear','value',.95));
        s=sht_fullmode_session('advance',80);assert(strcmp(s.lifecycle,'running'),s.failureReason);
        saved=sht_fullmode_session('save',fullfile(folder,'cold_snapshot'));
        s=sht_fullmode_session('advance',80);assert(strcmp(s.lifecycle,'running'),s.failureReason);
        reference=sht_fullmode_session('result');save(fullfile(folder,'restore_reference.mat'),'reference','saved');
        result.cases={reference};
    case 'restore_compare'
        d=load(varargin{1},'reference','saved');
        sht_fullmode_session('restore',d.saved.snapshot,struct('fullmode', ...
            struct('outputDirectory',fullfile(folder,'restored_runtime'))));sht_fullmode_session('resume');
        s=sht_fullmode_session('advance',80);assert(strcmp(s.lifecycle,'running'),s.failureReason);
        r=sht_fullmode_session('result');
        fields={'NpRpm','NgRpm','Tt45TrueK','effectiveFuelKgPerS','MkpTrueNm'};delta=zeros(size(fields));
        for i=1:numel(fields)
            delta(i)=max(abs(r.trace.(fields{i})-d.reference.trace.(fields{i})));
        end
        assert(all(delta<1e-7),'冷恢复数值容差不一致：%s。',mat2str(delta));
        result.cases={r};result.restoreDelta=delta;result.bitwise=isequaln(r.trace,d.reference.trace);
        result.thermalDelta=max(abs(r.thermalTrace{:,:}-d.reference.thermalTrace{:,:}),[],'all');
        assert(result.thermalDelta<1e-7,'恢复后的热状态不一致。');
    case 'regression'
        root=fileparts(mfilename('fullpath'));w=fileparts(fileparts(root));
        % 正式安装不依赖候选工作目录。调用者显式给出发布前备份清单；
        % 清单中的Candidate列指当前被测目录，Backup列指只读旧DLL及头文件。
        manifestFile=fullfile(w,'Documents','backup_manifest.csv');
        if ~isempty(varargin),manifestFile=varargin{1};end
        assert(isfile(manifestFile),'请显式传入本次发布前backup_manifest.csv，不能与自身比较。');
        % 清单八列均为CSV引号字段，按实测%q读取，Bytes不参与数值计算。
        manifest=readtable(manifestFile, ...
            'Delimiter',',','ReadVariableNames',true,'Encoding','UTF-8', ...
            'TextType','char','Format','%q%q%q%q%q%q%q%q');
        expected={'Source','Backup','Candidate','Bytes','SHA256','Encoding','Verified','Restore'};
        assert(isequal(manifest.Properties.VariableNames,expected), ...
            '备份清单必须保持原八列：%s。',strjoin(expected,','));
        row=find(strcmp(manifest.Candidate,fullfile(root,'GTESS.dll')),1);
        assert(nnz(strcmp(manifest.Candidate,fullfile(root,'GTESS.dll')))==1, ...
            '实际合入基线DLL必须有且只有一个明确备份记录。');
        baseline=fileparts(manifest.Backup{row});
        % 逐项核改前实际DLL及其配套头，不能用候选DLL和自身作回归比较。
        paired={'GTESS.dll','GTESS.h','blockAndFunctions.h','types_TMATS.h'};
        result.baselineFiles=cell(numel(paired),2);
        for k=1:numel(paired)
            rows=find(strcmp(manifest.Candidate,fullfile(root,paired{k})));
            assert(isscalar(rows),'配套备份记录缺失或不唯一：%s。',paired{k});
            file=manifest.Backup{rows};
            assert(strcmp(file,fullfile(baseline,paired{k})) && isfile(file), ...
                '配对备份文件不存在或不在同一明确基线目录：%s。',file);
            hash=local_file_sha256(file);
            assert(strcmpi(hash,manifest.SHA256{rows}), ...
                '改前配对文件SHA与原备份清单不符：%s。',file);
            result.baselineFiles(k,:)={file,hash};
        end
        result.ordinary=cell(2,2);comparison={};
        for mode=0:1
            for variant=1:2
                runtime=fullfile(folder,sprintf('ordinary_m%d_v%d',mode,variant));mkdir(runtime);
                sources=root;if variant==1,sources=baseline;end
                copyfile(fullfile(sources,'GTESS.dll'),runtime);copyfile(fullfile(sources,'*.h'),runtime);
                copyfile(fullfile(root,'*.mdl'),runtime);copyfile(fullfile(root,'*.MAP'),runtime);
                result.ordinary{mode+1,variant}=local_ordinary(runtime,mode,root,variant==2);
            end
            a=result.ordinary{mode+1,1};b=result.ordinary{mode+1,2};names=fieldnames(a);
            for i=1:numel(names)
                x=a.(names{i});y=b.(names{i});delta=max(abs(x.values-y.values));
                relative=max(abs(x.values-y.values)./max(1,abs(x.values)));
                ok=x.status==y.status && x.convergeTag==y.convergeTag && relative<1e-10;
                comparison(end+1,:)={mode,names{i},x.status,y.status,x.residual,y.residual,delta,relative,isequaln(x,y),ok}; %#ok<AGROW>
            end
        end
        result.comparison=cell2table(comparison,'VariableNames',{'model','caseName','oldStatus','newStatus', ...
            'oldResidual','newResidual','maxAbs','maxRelative','bitwise','accepted'});
        writetable(result.comparison,fullfile(folder,'ordinary_comparison.csv'));
        assert(all(result.comparison.accepted),'普通调用发生意外变化。');
        result.npKernelCases=local_np_regression(root);
    otherwise
        error('sht:fullmode:testGroup','未知测试组：%s。',group);
end

result.loadedFunctions=inmem('-completenames');
paths=strrep(lower(string(result.loadedFunctions)),'\','/');
assert(~any(contains(paths,'/toolbox/optim/')) && ~any(contains(paths,'/toolbox/stats/')), ...
    '本轮默认调用链进入了禁止自动依赖的工具箱。');
result.elapsedS=toc(timer);result.accepted=true;
save(fullfile(folder,'test_result.mat'),'result','-v7.3');
fprintf('R011 %s: PASS，实际%.3f秒，MATLAB %s。\n',group,result.elapsedS,version);
catch failure
    % 保留实际失败而非仅退出码；不把库代理对象写入MAT。
    result.accepted=false;result.elapsedS=toc(timer);
    result.failure=struct('identifier',failure.identifier,'message',failure.message, ...
        'stack',failure.stack,'report',getReport(failure,'extended','hyperlinks','off'));
    if exist('cfg','var'),result.failureConfiguration=cfg;end
    if exist('r','var'),result.lastCase=r;end
    try
        status=sht_fullmode_session('status');
        if ~strcmp(status.lifecycle,'empty'),result.failureSession=sht_fullmode_session('result');end
    catch inspectionFailure
        result.failureInspectionError=inspectionFailure.message;
    end
    save(fullfile(folder,'test_failure.mat'),'result','-v7.3');
    rethrow(failure);
end
end

function s=local_advance_until(mode,limitS)
% 每秒检查一次数值状态和目标阶段；终止只由真实状态或明确测试窗口决定。
s=sht_fullmode_session('status');
while s.timeS<limitS && ~strcmp(s.mode,mode)
    s=sht_fullmode_session('advance',40);
    assert(strcmp(s.lifecycle,'running'),'t=%g s：%s。',s.timeS,s.failureReason);
end
end

function hash=local_file_sha256(file)
% 只读核验原备份字节，不借用候选运行时身份，也不改写清单。
fid=fopen(file,'rb');assert(fid>=0,'不能读取身份文件：%s。',file);
guard=onCleanup(@()fclose(fid));bytes=fread(fid,Inf,'*uint8');
digest=java.security.MessageDigest.getInstance('SHA-256');
digest.update(typecast(bytes,'int8'));
raw=typecast(digest.digest(),'uint8');
hash=upper(reshape(dec2hex(raw,2).',1,[]));
end

function count=local_np_regression(root)
% 100组普通Np内核：NgDem只是参考量，缺少Ng专用字段不能触发Ng调速。
rng(170100,'twister');count=0;
for mode=0:1
    cfg=sht_startstop_prepare_control(sht_fullmode_default_config(struct('modelMode',mode)));
    ctrl=cfg.aboveIdle.controller;
    for k=1:100
        ctrl.initial=struct('Np',14000+6000*rand,'Ng',26000+10000*rand,'Wf',.05+.08*rand,'T45',900,'Mkp',300);
        state=sht_steady_governor_init(ctrl);sample=ctrl.initial;
        ref=struct('NpDem',14000+6000*rand);a=sht_steady_governor_compute(state,sample,ref,ctrl,.025);
        ref.NgDem=NaN;b=sht_steady_governor_compute(state,sample,ref,ctrl,.025);
        assert(isequaln(a,b),'普通Ng参考不应启用Ng调速。');
        ref.NgDem=30000;ref.NgErrorGain=2;ref.NgDotDem=10;
        assert(isequaln(a,sht_steady_governor_compute(state,sample,ref,ctrl,.025)));
        count=count+1;
    end
end
assert(isfile(fullfile(root,'sht_steady_governor_compute.m')));
end

function results=local_ordinary(runtime,mode,root,candidate)
old=pwd;guard=onCleanup(@()cd(old));cd(runtime);
alias=sprintf('R011_ORDINARY_M%d_V%d',mode,double(candidate)+1);
ep=[];pin=[];pout=[];
identity=struct('modelMode',mode,'variant',double(candidate)+1, ...
    'runtime',runtime,'alias',alias,'files',{{}},'initialStatus',NaN,'conditionsStatus',NaN);
paired={'GTESS.dll','GTESS.h','blockAndFunctions.h','types_TMATS.h'};
for k=1:numel(paired)
    file=fullfile(runtime,paired{k});
    identity.files{k}=struct('path',file,'sha256',local_file_sha256(file));
end
save(fullfile(runtime,'library_identity.mat'),'identity');
% 库代理的生命周期在本函数存活期间显式结束，不能等共享工作区析构后清理。
% 不捕获Engine代理到onCleanup；加载失败和初始化失败也进入同一异常清理。
assert(~libisloaded(alias),'测试别名已被占用：%s。',alias);
try
sht_load_engine_library(fullfile(runtime,'GTESS.dll'),fullfile(runtime,'GTESS.h'),'alias',alias);
identity.initialStatus=calllib(alias,'DLL_SHT_InitialMode',mode);
save(fullfile(runtime,'library_identity.mat'),'identity');
fprintf('普通回归 model=%d variant=%d alias=%s InitialMode=%d DLL=%s runtime=%s。\n', ...
    mode,identity.variant,alias,identity.initialStatus,identity.files{1}.sha256,runtime);
assert(identity.initialStatus==0, ...
    'InitialMode失败：model=%d variant=%d alias=%s code=%d runtime=%s DLL=%s。', ...
    mode,identity.variant,alias,identity.initialStatus,runtime,identity.files{1}.sha256);
ep=libstruct('EngineSHTPointer',struct('eng',libstruct('EngineTurboshaft')));
pin=libpointer('doublePtr',zeros(512,1));pout=libpointer('doublePtr',zeros(128,1));
identity.conditionsStatus=calllib(alias,'DLL_SHT_ConditionsInit',pin,pout,ep);
save(fullfile(runtime,'library_identity.mat'),'identity');
assert(identity.conditionsStatus==0, ...
    'ConditionsInit失败：model=%d variant=%d alias=%s code=%d runtime=%s。', ...
    mode,identity.variant,alias,identity.conditionsStatus,runtime);
mdl='Turboshaft-TS.mdl';if mode==1,mdl='Turboshaft-TS-Split.mdl';end
token=regexp(fileread(fullfile(runtime,mdl)),'(?m)^\s*varStartVec\s*=([^\r\n]+)','tokens','once');
seed=sscanf(token{1},'%f');n=numel(seed);base=zeros(512,1);
base(1:4)=[seed(end-1:end);.15171;.10573];base(6:7)=[2176600;3000];base(21:20+n)=seed;
for k=1:3
    x=base;x(3)=base(3)*(1-.04*(k-1));x(6)=base(6)*(1-.1*(k-1));
    results.(sprintf('steady%d',k))=evaluate(x,'DLL_SHT_RunOnePoint');
end
results.instant=evaluate(base,'DLL_SHT_RunOneStep');
% 13/31张空或小幅增量表由当前显式字典配置，不借用其他分支运行表。
ids=[0:3,6:14];axes=[1,5,5,5,2,7,7,7,3,8,8,8,4];
if mode==1,ids=[ids,71:88];axes=[axes,repelem([5,6,7,7,8,8],3)];end
assert(calllib(alias,'DLL_SHT_HealthScheduleReset')==0);
for j=1:numel(ids)
    delta=[0;0];if ids(j)==1,delta=[-.005;0];end
    assert(calllib(alias,'DLL_SHT_HealthScheduleConfigureTable',ids(j),axes(j),2, ...
        libpointer('doublePtr',[0;1.2]),libpointer('doublePtr',delta))==0);
end
x=base;x(42)=.01;x(18)=1;results.scheduleOn=evaluate(x,'DLL_SHT_RunOneStep');
x(18)=0;results.scheduleOff=evaluate(x,'DLL_SHT_RunOneStep');
assert(results.scheduleOn.status==0 && results.scheduleOff.status==0,'调度开关回归失败。');
assert(calllib(alias,'DLL_SHT_HealthScheduleReset')==0);
state=base(1:2);trace=zeros(40,4);
for k=1:40
    x=base;x(1:2)=state;x(3)=base(3)*(1+.01*(k>20));
    [a,dy]=evaluate(x,'DLL_SHT_RunOneStep');trial=x;trial(1:2)=state+.025*dy(1:2);
    [b,dz]=evaluate(trial,'DLL_SHT_RunOneStep');
    assert(a.status==0 && b.status==0,'普通短历程失败。');state=state+.0125*(dy(1:2)+dz(1:2));
    trace(k,:)=[state',a.residual,b.residual];
end
results.heun1s=struct('status',0,'convergeTag',0,'residual',max(trace(:,3:4),[],'all'),'values',trace(:));
cfg=sht_fullmode_default_config(struct('modelMode',mode));
d=load(cfg.stage7.assetFile,'parameterAsset');asset=d.parameterAsset;
if mode==0,asset=sht_startstop_three_thermal_adapter(asset,cfg);end
interface=struct('libraryName',alias);
sht_initialize_thermal_model_dll(interface,mode,sht_build_thermal_model_configuration(asset));
sht_initialize_cooling_split_dll(interface,mode,asset.coolingSplitConfiguration);
x=sht_build_transient_step_in_template(asset,'joint_full');x(1:10)=base(1:10);x(21:20+n)=seed;
count=numel(asset.nominal.initialTemperatureState);x(301:300+count)=asset.nominal.initialTemperatureState;
refs=488:493;if mode==0,refs=431:433;end
x(refs)=sht_lookup_clearance_reference(asset.referenceTable,base(1),base(2),base(6),288.15);
results.heatOn=evaluate(x,'DLL_SHT_RunOneStep');x(341)=0;results.heatOff=evaluate(x,'DLL_SHT_RunOneStep');
bad=base;bad(341)=99;results.invalid=evaluate(bad,'DLL_SHT_RunOneStep');assert(results.invalid.status~=0);
results.afterError=evaluate(base,'DLL_SHT_RunOneStep');
if candidate
    before=evaluate(base,'DLL_SHT_RunOneStep');sht_startstop_configure_dll(alias,cfg);
    calllib(alias,'DLL_SHT_StartStopReset',0,0,0,1);
    loadVector=sht_fullmode_load_boundary(cfg,0,0);
    assert(calllib(alias,'DLL_SHT_FullModeSetLoad',26100701,7,libpointer('doublePtr',loadVector.vector))==0);
    q=zeros(512,1);q(4)=cfg.startStop.nozzleAreaM2;q(30)=.025;q(35)=288.15;
    pin.Value=q;assert(calllib(alias,'DLL_SHT_RunStartStopStep',pin,pout,ep)==0);
    assert(isequaln(before,evaluate(base,'DLL_SHT_RunOneStep')),'起停正常退出污染普通入口。');
    q(30)=NaN;pin.Value=q;assert(calllib(alias,'DLL_SHT_RunStartStopStep',pin,pout,ep)~=0);
    assert(isequaln(before,evaluate(base,'DLL_SHT_RunOneStep')),'起停失败污染普通入口。');
    calllib(alias,'DLL_SHT_Free');assert(calllib(alias,'DLL_SHT_InitialMode',mode)==0);
    pin.Value=zeros(512,1);assert(calllib(alias,'DLL_SHT_ConditionsInit',pin,pout,ep)==0);
    assert(isequaln(results.instant,evaluate(base,'DLL_SHT_RunOneStep')),'重新初始化普通入口不一致。');
end
catch failure
    ep=[];pin=[];pout=[];
    try
        local_unload(alias);
    catch cleanupFailure
        failure=addCause(failure,cleanupFailure);
    end
    rethrow(failure);
end
ep=[];pin=[];pout=[];local_unload(alias);
assert(~libisloaded(alias),'普通回归结束后库仍在加载：%s。',alias);
    function [r,dy]=evaluate(x,entry)
        pin.Value=x;pout.Value=zeros(128,1);assert(calllib(alias,'DLL_SHT_varIteInit',pin,pout,ep)==0);
        [status,~,dy,ptr]=calllib(alias,entry,pin,pout,ep);e=ptr.eng;
        fields={'HPC','HPT','LPT'};if mode==1,fields={'HPC','HPC2','HPT','HPT2','LPT','LPT2'};end
        v=[e.Inlet.gasPathOut(:);e.LPS_Nmech;e.HPS_Nmech;e.LPS_Trq];
        for j=1:numel(fields),v=[v;e.(fields{j}).y(:)];end %#ok<AGROW>
        r=struct('status',status,'convergeTag',e.convergeTag,'residual',max(abs(e.errOut(1:n-2))), ...
            'values',[v;dy(:);e.varIte(1:n)';double(e.transientDiagnostics.errorCode)]);
    end
end

function local_unload(alias)
if libisloaded(alias),calllib(alias,'DLL_SHT_Free');unloadlibrary(alias);end
end
