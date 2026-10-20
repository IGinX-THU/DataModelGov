function out=sht_afo_results(action,varargin)
%SHT_AFO_RESULTS 保存及独立读取；Excel不依赖MAT缓存、DLL或模型工作区。
switch lower(action)
    case 'save'
        r=varargin{1};folder=varargin{2};
        save(fullfile(folder,'result.mat'),'r','-v7.3');
        T=table(r.time,'VariableNames',{'Time_s'});
        dictionary=cell(0,7);
        for k=1:numel(r.channels)
            if isempty(r.values),break;end
            values=vertcat(r.values{:,k});spec=r.channels(k);
            for j=1:size(values,2)
                id=sprintf('%s_%02d',spec.id,j);T.(id)=values(:,j);
                label=sprintf('%s[%d]',spec.id,j);unit='model_unit_unconfirmed';
                if j<=numel(spec.names),label=spec.names{j};unit=spec.units{j};end
                dictionary(end+1,:)={id,spec.group,label,unit, ...
                    sprintf('%d:%d',spec.sid,spec.port),spec.role,'recorded'};
            end
        end
        % 公开原始G04输入是否触发既有映射回退，不改映射本身。
        if ~isempty(r.values)
            T.G04_temperature_fallback=~isfinite(T.air09_01)|T.air09_01<150|T.air09_01>3000;
            T.G04_pressure_fallback=~isfinite(T.air10_01)|T.air10_01<3e4|T.air10_01>5e6;
            dictionary(end+1,:)={'G04_temperature_fallback','air','G04温度回退','1','11534:9','input_validity','derived_exact_guard'};
            dictionary(end+1,:)={'G04_pressure_fallback','air','G04压力回退','1','11534:10','input_validity','derived_exact_guard'};
            % 原始轴承温度仍以K记录；R105在混温入口前显式换算为摄氏度。
            % 判定必须对应实际送入混温函数的值，不能再用K与摄氏度限值比较。
            tempA_C=T.oil09_01-273.15;tempB_C=T.oil10_01-273.15;
            T.OilMix_A_fallback=~(isfinite(tempA_C)&tempA_C>20&tempA_C<250);
            T.OilMix_B_fallback=~(isfinite(tempB_C)&tempB_C>20&tempB_C<250);
            dictionary(end+1,:)={'OilMix_A_fallback','oil','甲回油混温输入无效','1','12206:in1','input_validity','derived_exact_guard'};
            dictionary(end+1,:)={'OilMix_B_fallback','oil','乙回油混温输入无效','1','12206:in2','input_validity','derived_exact_guard'};
        end
        D=cell2table(dictionary,'VariableNames',{'Id','Group','Name','Unit','Source','Role','Validity'});
        E=table;
        if ~isempty(r.events)
            events=r.events;
            for n=1:numel(events),events(n).value=jsonencode(events(n).value);end
            E=struct2table(events,'AsArray',true); % 单个事件同样只占一行。
        end
        meta={'Schema',r.schema;'RunId',r.config.runId;'EngineId',r.config.engineId; ...
            'PreparedAtLocal',r.preparedAtLocal;'StartedAtLocal',r.startedAtLocal; ...
            'TimeZoneConvention','Host local time'; ...
            'MatlabVersion',r.matlabVersion;'MatlabRelease',r.matlabRelease; ...
            'State',r.state;'StopReason',r.stopReason;'ExternalAir',num2str(r.config.externalAir); ...
            'LoadMode',r.config.loadMode;'PrepareSeconds',num2str(r.timing.prepare,17); ...
            'RunWallSeconds',num2str(r.timing.runWall,17);'HumanPauseSeconds',num2str(r.timing.humanPause,17); ...
            'PaceWaitSeconds',num2str(r.timing.paceWait,17); ...
            'ComputeAndServiceSeconds',num2str(r.timing.computeAndService,17); ...
            'FinalSimulationTime',num2str(r.finalSimulationTime,17); ...
            'InitialNpRpm',num2str(r.initialState(1),17);'InitialNgRpm',num2str(r.initialState(2),17); ...
            'RuntimeScope','AFO normal positive-speed; no start-stop transplant'; ...
            'DataKind','simulation_not_measurement'};
        % 完整写好临时Excel后再发布，失败时不留下貌似完整的正式Excel。
        file=fullfile(folder,'AFO_results.writing.xlsx');
        if exist(file,'file')==2,delete(file);end
        writetable(T,file,'Sheet','Data');writetable(D,file,'Sheet','Channels');
        writetable(cell2table(meta,'VariableNames',{'Key','Value'}),file,'Sheet','Run');
        if ~isempty(E),writetable(E,file,'Sheet','Commands');end
        writetable(struct2table(r.identity),file,'Sheet','Identity');
        writetable(table({'initial';'final'}, ...
            {jsonencode(r.initialConfig);jsonencode(r.config)}, ...
            'VariableNames',{'Role','ConfigJSON'}),file,'Sheet','Config');
        finalFile=fullfile(folder,'AFO_results.xlsx');movefile(file,finalFile,'f');file=finalFile;
        out=struct('file',file,'samples',height(T),'channels',height(D),'state',r.state);
        fid=fopen(fullfile(folder,'summary.json'),'w','n','UTF-8');fprintf(fid,'%s',jsonencode(out));fclose(fid);
        fprintf('AFO结果已保存：%s；%d时刻，%d通道。\n',file,height(T),height(D));
    case 'read'
        file=varargin{1};
        out=struct('data',readtable(file,'Sheet','Data'), ...
            'channels',readtable(file,'Sheet','Channels'), ...
            'run',readtable(file,'Sheet','Run'),'identity',readtable(file,'Sheet','Identity'));
        out.config=readtable(file,'Sheet','Config');
        [~,sheets]=xlsfinfo(file);
        if any(strcmp(sheets,'Commands')),out.commands=readtable(file,'Sheet','Commands');else,out.commands=table;end
        assert(any(strcmp(out.run.Value,'SHT_AFO_RESULT_V1')),'不是受支持的AFO结果Excel。');
    case 'config'
        % 从Excel的初始配置新建，不恢复已结束的动态状态、不悄悄用最终操纵值。
        q=sht_afo_results('read',varargin{1});
        row=find(strcmp(q.config.Role,'initial'),1);assert(~isempty(row),'缺少初始配置。');
        out=jsondecode(q.config.ConfigJSON{row});
        assert(strcmp(out.schema,'SHT_AFO_CONFIG_V1'),'不支持的配置格式。');
        fresh=sht_afo_config;
        out.sourceDir=fileparts(mfilename('fullpath'));out.outputDir=fresh.outputDir;
        if numel(varargin)>=2,out.outputDir=varargin{2};end
        out.runId=[out.runId '_copy_' datestr(now,'yyyymmdd_HHMMSS_FFF')];
        out.legacyPulses=false;
        if isfield(out,'verificationOriginalSources'),out=rmfield(out,'verificationOriginalSources');end
        out.copiedFromRunId=q.run.Value{strcmp(q.run.Key,'RunId')};
    case 'plot'
        q=sht_afo_results('read',varargin{1});T=q.data;
        f=figure('Name','多系统联合仿真结果','NumberTitle','off');
        subplot(2,2,1);plot(T.Time_s,T{:,{'engine_09','engine_10'}});ylabel('rpm');legend('Np','Ng');grid on;
        subplot(2,2,2);plot(T.Time_s,T{:,{'fuel_command_01','fuel_engine_01','fuel_detailed_01'}});ylabel('kg/s');legend('控制指令','发动机采用','详细燃油');grid on;
        subplot(2,2,3);plot(T.Time_s,T.load_05/1000);ylabel('PT负载功率/kW');grid on;
        subplot(2,2,4);plot(T.Time_s,T{:,{'air01_01','air02_01','air03_01','air04_01','air05_01','air06_01','air07_01','air08_01'}});ylabel('外部空气流量/kg/s');grid on;
        out=f;
    otherwise,error('未知结果操作。');
end
end
