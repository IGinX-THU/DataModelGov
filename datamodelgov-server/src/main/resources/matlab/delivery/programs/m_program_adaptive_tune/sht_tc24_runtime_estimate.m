function value=sht_tc24_runtime_estimate(action,query,varargin)
% 以同一数值后端和计时范围的本地已完成任务作工程估时，不作统计置信承诺。
% query.directory是调用方指定历史目录；cohort为路径/模型/配置/规模身份。
% workUnits只用于同类预算缩放；缺少至少两份有效可比记录时明确未知。
action=lower(char(action));
if strcmp(action,'query')
    % 保守匹配完整显式数值配置；不足两次可比记录时宁可明确未知。
    cfg=query;task=varargin{1};semantic=cfg;
    ignored={'runId','outputDirectory','trainingFile','testFile','runtimeDirectory', ...
        'deterministicWorkbookFile','progressCallback','plotEnabled','figureVisible', ...
        'preparedInput','enableRunControl','resume','runControl','runControlOptions', ...
        'timingHistoryDirectory','timingQuery','verbose'};
    semantic=rmfield(semantic,intersect(fieldnames(semantic),ignored));
    runtime=struct();
    listing=dir(cfg.runtimeDirectory);
    for k=1:numel(listing)
        [~,~,ext]=fileparts(listing(k).name);
        if listing(k).isdir||~ismember(lower(ext),{'.dll','.h','.mdl','.map'}),continue;end
        name=matlab.lang.makeValidName(listing(k).name);
        runtime.(name)=sht_steady_model_uq_common('filehash',fullfile(cfg.runtimeDirectory,listing(k).name));
    end
    inputs=struct();
    for name={'trainingFile','testFile','deterministicWorkbookFile'}
        key=name{1};if isfield(cfg,key)&&~isempty(cfg.(key))
            inputs.(key)=sht_steady_model_uq_common('filehash',cfg.(key));
        end
    end
    files={'sht_steady_model_adapt_v2_common','sht_tc24_run_estimation', ...
        'Start_TC24_07_UncertaintyAssessment','Start_TC24_07D_QuickAssessment', ...
        'sht_steady_model_uq_b_smc','sht_steady_model_uq_c_smc','sht_tc24_uq_method_d', ...
        'sht_tc24_runtime_estimate','sht_tc24_execution','sht_tc24_run_control'};
    sources=struct();for k=1:numel(files)
        sources.(files{k})=sht_steady_model_uq_common('filehash',which(files{k}));
    end
    cohort=struct('task',task,'options',semantic,'runtime',runtime,'inputs',inputs, ...
        'sources',sources,'host',getenv('COMPUTERNAME'),'matlabRelease',version('-release'), ...
        'scope','entry_active_seconds_without_user_pause');
    value=struct('directory',cfg.timingHistoryDirectory,'cohort',cohort,'workUnits',1);return;
end
assert(isfield(query,'directory')&&isfield(query,'cohort')&&isfield(query,'workUnits'), ...
    'TC24:ETA:Query','需提供directory/cohort/workUnits。');
validateattributes(query.workUnits,{'numeric'},{'real','scalar','positive','finite'});
folder=sht_tc24_absolute_path(query.directory);
key=sht_tc24_run_control('hash',query.cohort);
switch action
    case 'estimate'
        value=struct('available',false,'seconds',NaN,'lowerSeconds',NaN, ...
            'upperSeconds',NaN,'basis','缺少至少两份同后端、同口径可比运行记录。', ...
            'scope','本次入口有效计算，不含用户暂停等待','cohortHash',key, ...
            'workUnits',query.workUnits,'evidence',{{}},'createdAt',datestr(now,30), ...
            'intervalMeaning','工程经验范围，不是概率置信区间');
        if ~exist(folder,'dir'),return;end
        listing=dir(fullfile(folder,'timing_*.mat'));rates=[];evidence={};
        for i=1:numel(listing)
            file=fullfile(folder,listing(i).name);
            try
                saved=load(file,'record');r=saved.record;
                valid=strcmp(r.schemaVersion,'SHT_LOCAL_TIMING_V1')&&strcmp(r.cohortHash,key) ...
                    &&ismember(r.status,{'completed','completed_diagnostic'}) ...
                    &&isfinite(r.activeSeconds)&&r.activeSeconds>0 ...
                    &&query.workUnits/r.workUnits>=.5&&query.workUnits/r.workUnits<=2;
                if valid,rates(end+1)=r.activeSeconds/r.workUnits;evidence{end+1}=listing(i).name;end %#ok<AGROW>
            catch
                % 损坏/不属于本协议的历史记录不是可用计时依据，不能猜测修复。
            end
        end
        value.evidence=evidence;
        if numel(rates)<2,return;end
        value.available=true;value.seconds=median(rates)*query.workUnits;
        value.lowerSeconds=.7*min(rates)*query.workUnits;
        value.upperSeconds=1.5*max(rates)*query.workUnits;
        value.basis=sprintf('%d份匹配记录，按实际预算单位缩放；范围含0.7/1.5工程余量。',numel(rates));
    case 'record'
        record=varargin{1};
        assert(ismember(record.status,{'completed','completed_diagnostic'}), ...
            'TC24:ETA:Incomplete','停止/失败记录不充当完整运行时间样本。');
        validateattributes(record.activeSeconds,{'numeric'},{'scalar','finite','positive'});
        assert(~isempty(regexp(record.runId,'^[A-Za-z0-9_-]+$','once')),'运行编号非法。');
        record.schemaVersion='SHT_LOCAL_TIMING_V1';record.cohortHash=key;
        record.cohort=query.cohort;record.workUnits=query.workUnits;
        record.createdAt=datestr(now,30);
        if ~exist(folder,'dir'),mkdir(folder);end
        file=fullfile(folder,['timing_',record.runId,'.mat']);
        assert(~isfile(file),'TC24:ETA:Exists','同一运行的计时记录不能覆盖。');
        temporary=[file,'.partial'];save(temporary,'record');movefile(temporary,file);value=file;
    otherwise
        error('TC24:ETA:Action','未知估时动作%s。',action);
end
end
