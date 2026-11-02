function estimate=sht_tc24_fixed_runtime_estimate(task,cfg,trainingCount,testCount)
% 用冻结的本机实测基准和本次工作量估算TC24计算时间，不读取历史运行目录。
% 可只传task和配置，从测量Excel计算工况数；不加载DLL，也不要求输出目录。
% 这是工程排期值，不是DLL调用次数的精确预测；每次完整运行后仍单独记录实际耗时。
if nargin<2||isempty(cfg),cfg=struct();end
task=lower(char(task));
if nargin<3||isempty(trainingCount)
    root=fileparts(mfilename('fullpath'));
    trainingFile=local_text_option(cfg,'trainingFile', ...
        fullfile(root,'TestData','three_component','tc24_training_means.xlsx'));
    trainingCount=height(sht_tc24_validate_measurements(trainingFile));
end
if nargin<4||isempty(testCount)
    testFile=local_text_option(cfg,'testFile','');
    if ~isfield(cfg,'testFile')&&~isfield(cfg,'trainingFile')&&strncmp(task,'uq_',3)
        root=fileparts(mfilename('fullpath'));
        testFile=fullfile(root,'TestData','three_component','tc24_test_means.xlsx');
    end
    testCount=0;
    if ~isempty(testFile)&&(~strncmp(task,'identification_',15)|| ...
            local_option(cfg,'evaluateTestSet',true))
        testCount=height(sht_tc24_validate_measurements(testFile));
    end
end
validateattributes(trainingCount,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(testCount,{'numeric'},{'scalar','integer','nonnegative','finite'});
trainingScale=trainingCount/12;
predictionScale=(trainingCount+testCount)/16;
version='TC24_FIXED_WORK_V1_20261001';

switch task
    case {'identification_steady','identification_transient_instant'}
        % R040的12训练/4测试完整入口：稳态263.648s，瞬态时刻200.236s。
        if strcmp(task,'identification_steady')
            referenceSeconds=263.6475306;
        else
            referenceSeconds=200.2364319;
        end
        groupProxy=max(1,round(7*trainingScale));
        parameterProxy=12+53*groupProxy/7;
        a=local_option(cfg,'maxIterationA',12)/12;
        b=local_option(cfg,'maxIterationGroup',10)/10;
        d=local_option(cfg,'maxIterationRefine',20)/20;
        % A/B/D所占比例只是粗估；节点数和分组在真正辨识后才可确定。
        workFactor=.16*a+.30*b*groupProxy/7+.54*d*parameterProxy/65;
        seconds=25+7*testCount+(referenceSeconds-25-28)*trainingScale*workFactor;
        source='TC24 R040完整入口实测，12训练点/4测试点';
        units=struct('trainingPoints',trainingCount,'testPoints',testCount, ...
            'estimatedGroups',groupProxy,'estimatedFreeParameters',parameterProxy, ...
            'maximumIterationsA',local_option(cfg,'maxIterationA',12), ...
            'maximumIterationsGroup',local_option(cfg,'maxIterationGroup',10), ...
            'maximumIterationsD',local_option(cfg,'maxIterationRefine',20));
    case 'uq_b'
        % 没有历史目录也能估时；先从正式集中配置补齐当前V2或显式V1预算。
        % 旧quality研究配置仅保留其既有成本分支，不是正式默认。
        if ~isfield(cfg,'bSamplerProfile')||strcmp(cfg.bSamplerProfile,'legacy_reference')
            cfg=sht_tc24_b_config(cfg);
        end
        profile=local_text_option(cfg,'bSamplerProfile','legacy_reference');
        assert(ismember(profile,{'quality','legacy_reference'}),'TC24:ETA:BProfile','未知B采样配置。');
        if strcmp(profile,'quality')
            % 本机20261005新B完整实测：正式35层、6/32轮、242688候选。
            % 先导29/36/35层单独计费；这只是排期基准，不保证新数据的层数。
            particles=local_option(cfg,'particleCount',1024);
            moves=local_option(cfg,'formalMoveSweeps',6);
            finalSweeps=local_option(cfg,'formalFinalMoveSweeps',32);
            maximumStages=local_option(cfg,'maximumStageCount',70);
            requestedStages=local_option(cfg,'bEstimatedTemperatureStages',35);
            requestedPilotStages=local_option(cfg,'bEstimatedPilotTemperatureStages',100/3);
            validateattributes(maximumStages,{'numeric'},{'scalar','integer','positive'});
            validateattributes(requestedStages,{'numeric'},{'scalar','integer','positive'});
            validateattributes(requestedPilotStages,{'numeric'},{'scalar','>=',1});
            stages=min(maximumStages,requestedStages);
            pilotStages=min(maximumStages,requestedPilotStages);
            pilotN=local_option(cfg,'pilotSampleCount',64);pilotR=local_option(cfg,'pilotReplicateCount',3);
            pilotMoves=local_option(cfg,'pilotMoveSweeps',2);pilotFinal=local_option(cfg,'pilotFinalMoveSweeps',4);
            for value=[particles,pilotN,pilotR]
                validateattributes(value,{'numeric'},{'scalar','integer','positive'});
            end
            for value=[moves,finalSweeps,pilotMoves,pilotFinal]
                validateattributes(value,{'numeric'},{'scalar','integer','nonnegative'});
            end
            count=particles*(1+(stages-1)*moves+finalSweeps);
            candidateSeconds=18046.642178/242688;
            sampling=candidateSeconds*count*trainingScale;
            pilotCandidates=pilotN*pilotR*(1+(pilotStages-1)*pilotMoves+pilotFinal);
            pilot=1182.2825738*(pilotCandidates/13376)*trainingScale;
            prepare=[1.5947626,1.5270803,.0521428,5.0105378,12.0861082]*trainingScale;
            % validationRuntime包含预测、Excel和图表，不再叠加内部231.157秒子段。
            propagation=330.9151165*predictionScale*(particles/1024);
            bStageSeconds=[prepare,pilot,.1838624,sampling,propagation+.6562545];
            seconds=sum(bStageSeconds);
            route=local_text_option(cfg,'route','transient_instant');
            source=['B1024质量配置单例20261005，R2019b/Win64/VC2010/i7-10750H；', ...
                '35层正式及100/3层先导分别计费；B08=18046.642178s/242688候选；', ...
                '预测交付330.9151165s只计一次；新数据、512粒子和其他硬件仍为外推'];
            if maximumStages<requestedStages||maximumStages<requestedPilotStages
                source=[source,'；估算按最大层数封顶，预算耗尽不保证完成后验'];
            end
            if strcmp(route,'steady'),source=[source,'；稳态模型仅借瞬态时刻成本外推'];end
            units=struct('trainingPoints',trainingCount,'testPoints',testCount,'particles',particles, ...
                'moveSweeps',moves,'finalMoveSweeps',finalSweeps,'assumedTemperatureStages',stages, ...
                'formalCandidates',count,'secondsPerCandidateAt12TrainingPoints',candidateSeconds, ...
                'pilotSamples',pilotN,'pilotReplicates',pilotR, ...
                'assumedPilotTemperatureStages',pilotStages,'pilotCandidates',pilotCandidates,'route',route, ...
                'samplerProfile',profile,'stageCostSeconds',bStageSeconds);
            version='TC24_B_QUALITY_FIXED_WORK_V4_20261005';
        else
        % V2正式采样的单位成本来自已冻结完整计算，不读取任何历史目录。
        % V1沿用其本机成本。实测层数用于排期假设，不限定实际SMC温度层数。
        particles=local_option(cfg,'particleCount',1024);
        moves=local_option(cfg,'formalMoveSweeps',2);
        finalSweeps=local_option(cfg,'formalFinalMoveSweeps',32);
        v2=strcmp(cfg.bConfiguration,'V2');referenceStages=7;
        candidateSeconds=2529.5785479/46078;
        if v2,referenceStages=6;candidateSeconds=4880.6317067/87038;end
        stages=min(local_option(cfg,'maximumStageCount',70), ...
            local_option(cfg,'bEstimatedTemperatureStages',referenceStages));
        pilotN=local_option(cfg,'pilotSampleCount',64);pilotR=local_option(cfg,'pilotReplicateCount',3);
        pilotMoves=local_option(cfg,'pilotMoveSweeps',2);pilotFinal=local_option(cfg,'pilotFinalMoveSweeps',4);
        for value=[particles,stages,pilotN,pilotR]
            validateattributes(value,{'numeric'},{'scalar','integer','positive','finite'});
        end
        for value=[moves,finalSweeps,pilotMoves,pilotFinal]
            validateattributes(value,{'numeric'},{'scalar','integer','nonnegative','finite'});
        end
        count=particles*(1+(stages-1)*moves+finalSweeps);
        sampling=candidateSeconds*count*trainingScale;
        pilotStages=min(local_option(cfg,'maximumStageCount',70),local_option(cfg,'bEstimatedPilotTemperatureStages',6));
        validateattributes(pilotStages,{'numeric'},{'scalar','integer','positive','finite'});
        pilot=240.2991308*(pilotN/64)*(pilotR/3)*(1+(pilotStages-1)*pilotMoves+pilotFinal)/15*trainingScale;
        prepare=29.6984869*trainingScale;
        propagation=225.0144499*predictionScale*(particles/1024);
        other=15;
        bStageSeconds=[prepare/5,repmat(prepare/5,1,4),pilot,.213016,sampling,propagation+other];
        seconds=sum(bStageSeconds);
        source=['TC24 currentD B1024种子1 20261005，R2019b/Win64/VC2010/i7-10750H；', ...
            '7层/46078候选2529.5785479s、6层先导240.2991308s；', ...
            'D52.6424777s及B准备29.6984869s、预测225.0144499s各计一次；', ...
            '层数为工程假设，512粒子及新数据仍为外推'];
        if v2
            source=['TC24 V2完整1024计算20261007，R2019b/Win64/VC2010/i7-10750H；', ...
                '6层/87038未缓存候选，正式SMC4880.6317067s；原生全批5372.9721109s；', ...
                '末层64轮，先导/准备/预测分项计费，不重复计入原生总时间；', ...
                '辅助D按compute另计、read复用；512及新数据层数为工程外推'];
        end
        route=local_text_option(cfg,'route','transient_instant');
        if strcmp(route,'steady')
            source=[source,'；稳态模型尚无完整B实测，沿用瞬态时刻模型基准粗略外推'];
        end
        units=struct('trainingPoints',trainingCount,'testPoints',testCount, ...
            'particles',particles,'moveSweeps',moves,'finalMoveSweeps',finalSweeps, ...
            'assumedTemperatureStages',stages,'formalCandidates',count, ...
            'pilotSamples',pilotN,'pilotReplicates',pilotR, ...
            'pilotFinalMoveSweeps',pilotFinal,'assumedPilotTemperatureStages',pilotStages, ...
            'route',route,'samplerProfile',profile,'stageCostSeconds',bStageSeconds);
        units.bConfiguration=cfg.bConfiguration;
        units.secondsPerCandidateAt12TrainingPoints=candidateSeconds;
        units.candidateDefinition='参数向量对全训练集的评估，不是原生DLL调用次数';
        version='TC24_B_CURRENTD_FIXED_WORK_V6_20261006';
        if v2,version='TC24_B_V2_FIXED_WORK_V7_20261007';end
        end
        % D是进入B之前完整执行的独立准备，不能均分进B01~05。
        dMode=local_text_option(cfg,'dProposalMode','compute');
        if ~isfield(cfg,'dProposalMode')&&isfield(cfg,'dProposalRunId')&&~isempty(cfg.dProposalRunId)
            dMode='read';
        end
        assert(ismember(dMode,{'compute','read','none'}),'TC24:ETA:DMode','未知D准备方式。');
        dPreparationSeconds=0;
        if strcmp(dMode,'compute')
            dPreparationSeconds=52.6424777*trainingScale*local_option(cfg,'dProposalMaxIterations',3)/3;
        end
        units.dProposalMode=dMode;units.dPreparationSeconds=dPreparationSeconds;
        units.stageCostSeconds=bStageSeconds;
        seconds=sum(bStageSeconds)+dPreparationSeconds;
    case 'uq_c'
        profile=local_text_option(cfg,'cSamplerProfile','quality');
        assert(ismember(profile,{'quality','legacy_reference'}),'TC24:ETA:CProfile','未知C采样配置。');
        if strcmp(profile,'quality')
            % 单位成本采用两个完整新C采样器实测均值，
            % 包含矩阵、缓存及DLL工作，不将准备、先导和预测重复摊入。
            % 一个候选包含全部训练工况，不等于一次原生DLL调用。
            samples=local_option(cfg,'formalSampleCount',512);
            sweeps=local_option(cfg,'formalMoveSweeps',6);
            finalSweeps=local_option(cfg,'formalFinalMoveSweeps',32);
            assumedStages=min(local_option(cfg,'maximumStageCount',70), ...
                local_option(cfg,'cEstimatedTemperatureStages',13));
            validateattributes(assumedStages,{'numeric'},{'scalar','integer','positive'});
            pilotSamples=local_option(cfg,'pilotSampleCount',64);
            pilotRepeats=local_option(cfg,'pilotReplicateCount',3);
            pilotMoves=local_option(cfg,'pilotMoveSweeps',1);
            pilotFinal=local_option(cfg,'pilotFinalMoveSweeps',2);
            formalCandidates=samples*(1+(assumedStages-1)*sweeps+finalSweeps);
            candidateSeconds=((3380.3+3123.5)/2)/53760;
            sampling=trainingScale*candidateSeconds*formalCandidates;
            pilot=((230.4+219.5)/2)*trainingScale*(pilotSamples/64)*(pilotRepeats/3)* ...
                (1+(assumedStages-1)*pilotMoves+pilotFinal)/15;
            propagation=((189.0+195.6)/2)*predictionScale*(samples/512);
            % 前三步、先导、正式采样分别计费；预测仅在完成第五步后发生。
            cStageSeconds=[(4.4+2.7)/2,(170.7+136.8)/2,(14.5+12.5)/2]*trainingScale;
            cStageSeconds=[cStageSeconds,pilot,sampling+propagation];
            seconds=sum(cStageSeconds);
            source=['TC24 CQuality两个完整512种子20261004，R2019b/Win64/VC2010/i7-10750H；', ...
                '13层/53760候选，采样器及各步骤按完整日志均值计费；', ...
                '原生总计4005.510s/3703.556s；新数据层数仍为工程假设'];
            route=local_text_option(cfg,'route','transient_instant');
            if strcmp(route,'steady'),source=[source,'；稳态模型借瞬态时刻成本粗略外推'];end
            units=struct('trainingPoints',trainingCount,'testPoints',testCount,'samples',samples, ...
                'moveSweeps',sweeps,'finalMoveSweeps',finalSweeps, ...
                'assumedTemperatureStages',assumedStages,'formalCandidates',formalCandidates, ...
                'secondsPerCandidateAt12TrainingPoints',candidateSeconds, ...
                'pilotSamples',pilotSamples,'pilotReplicates',pilotRepeats,'route',route, ...
                'samplerProfile',profile,'stageCostSeconds',cStageSeconds);
            version='TC24_C_QUALITY_FIXED_WORK_V3_20261006';
        else
        % 2026-09-12 R2019b：C推断942.9s，预测交付335.9s，512个主样本。
        samples=local_option(cfg,'formalSampleCount',512);
        finalSweeps=local_option(cfg,'formalFinalMoveSweeps',8);
        inference=942.9312624*trainingScale*(samples/512)*(.25+.75*finalSweeps/8);
        propagation=335.9472427*predictionScale*(samples/512);
        seconds=inference+propagation;
        source='TC24 R2019b完整C推断及预测实测，512个主样本';
        route=local_text_option(cfg,'route','transient_instant');
        if strcmp(route,'steady')
            source=[source,'；稳态模型尚无完整C实测，沿用瞬态时刻模型基准粗略外推'];
        end
        units=struct('trainingPoints',trainingCount,'testPoints',testCount, ...
            'samples',samples,'finalMoveSweeps',finalSweeps,'route',route);
        end
    case 'uq_d'
        % 稳态模型参考R065的146.75s；瞬态时刻模型参考R2019b的99+105.4s。
        route=local_text_option(cfg,'route','transient_instant');
        iterations=local_option(cfg,'maxIterations',3);
        samples=local_option(cfg,'localSampleCount',512);
        predictionPoints=testCount;
        if local_option(cfg,'predictionTrainingEnabled',false)
            predictionPoints=predictionPoints+trainingCount;
        end
        if strcmp(route,'steady')
            iterationReference=70;predictionReference=41.753435;
            source='TC24 R065稳态模型D代表运行146.75s';
        else
            assert(strcmp(route,'transient_instant'),'TC24:ETA:Route','未知D模型路径');
            iterationReference=65;predictionReference=104.3862677;
            source='TC24 R2019b瞬态时刻模型D推断99s及预测105.4s';
        end
        predictionMode=local_text_option(cfg,'predictionMode','linearized');
        if strcmp(predictionMode,'exact')
            predictionMultiplier=2.5;
        else
            assert(strcmp(predictionMode,'linearized'),'TC24:ETA:PredictionMode','未知D预测方式');
            predictionMultiplier=1;
        end
        seconds=35+iterationReference*trainingScale*(iterations/3)+ ...
            predictionReference*(predictionPoints/4)*(samples/512)*predictionMultiplier;
        units=struct('trainingPoints',trainingCount,'testPoints',testCount, ...
            'maximumIterations',iterations,'localSamples',samples, ...
            'predictionPoints',predictionPoints,'predictionMode',predictionMode,'route',route);
    otherwise
        error('TC24:ETA:Task','未知TC24计算类型: %s',task);
end

fullSeconds=seconds;
scope='入口有效计算及所请求的结果交付，不含MATLAB冷启动和用户暂停';
resolved=true;
switch task
    case 'uq_b'
        stageWeights=[.01,.01,.01,.01,.01,.05,.01,.82,.07];
        if exist('bStageSeconds','var'),stageWeights=bStageSeconds/sum(bStageSeconds);end
    case 'uq_c'
        stageWeights=[.04,.08,.08,.10,.70];
        if exist('cStageSeconds','var'),stageWeights=cStageSeconds/sum(cStageSeconds);end
    case 'uq_d',stageWeights=[.03,.15,.60,.22];
    otherwise,stageWeights=[];
end
if ~isempty(stageWeights)
    first=local_option(cfg,'firstStep',1);
    last=local_option(cfg,'lastStep',numel(stageWeights));
    validateattributes(first,{'numeric'},{'scalar','integer','>=',1,'<=',numel(stageWeights)});
    validateattributes(last,{'numeric'},{'scalar','integer','>=',first,'<=',numel(stageWeights)});
    skipPrediction=strcmp(task,'uq_d')&&logical(local_option(cfg,'skipValidation',false));
    if skipPrediction,last=min(last,3);end
    units.firstStep=first;units.lastStep=last;units.skipPrediction=skipPrediction;
    if first>last
        resolved=false;
        scope='只恢复已有步骤并整理结果，预测已跳过；缺少可比耗时基准';
    elseif first>1||last<numel(stageWeights)
        % 分段权重只作排期粗估；已完成步骤不再计入本次请求。
        if strcmp(task,'uq_b')
            seconds=sum(bStageSeconds(first:last));
            if first==1,seconds=seconds+dPreparationSeconds;end
            units.dPreparationReused=first>1 && strcmp(dMode,'compute');
        else
            seconds=fullSeconds*sum(stageWeights(first:last));
        end
        source=[source,'；本次请求步骤',num2str(first),':',num2str(last)];
        scope=['仅估第',num2str(first),':',num2str(last), ...
            '步及其请求的交付，不含先前已完成步骤、MATLAB冷启动和用户暂停'];
    end
end
% 安全恢复的实际起点可能由验证后的检查点改写；预检前不能伪报剩余时间。
if logical(local_option(cfg,'resume',false))
    resolved=false;scope='恢复请求：检查点尚未验证，剩余时间未解析；仅提供完整冷启动参考';
end
if resolved
    validateattributes(seconds,{'numeric'},{'scalar','positive','finite'});
    lowerBoundSeconds=max(1,.45*seconds);
    upperBoundSeconds=max(1.9*seconds,seconds+30);
else
    seconds=NaN;lowerBoundSeconds=NaN;upperBoundSeconds=NaN;
    source=[source,'；',scope];
end
estimate=struct('available',resolved,'seconds',seconds, ...
    'lowerSeconds',lowerBoundSeconds,'upperSeconds',upperBoundSeconds, ...
    'basis',[version,'；',source,'；按本次工况/迭代/样本工作量粗略缩放'], ...
    'scope',scope,'remainingResolved',resolved,'coldFullReferenceSeconds',fullSeconds, ...
    'intervalMeaning','工程排期范围，不是统计置信区间或实时倒计时', ...
    'modelVersion',version,'benchmarkVersion',version,'evidence',{{source}}, ...
    'task',task,'workload',units,'createdAt',datestr(now,30));
end

function value=local_option(cfg,name,defaultValue)
value=defaultValue;
if isfield(cfg,name)&&~isempty(cfg.(name)),value=cfg.(name);end
validateattributes(value,{'numeric','logical'},{'scalar','nonnegative','finite'});
end

function value=local_text_option(cfg,name,defaultValue)
value=defaultValue;
if isfield(cfg,name)&&~isempty(cfg.(name)),value=char(cfg.(name));end
end
