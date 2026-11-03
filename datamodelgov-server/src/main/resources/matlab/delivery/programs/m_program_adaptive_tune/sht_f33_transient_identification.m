function out=sht_f33_transient_identification(action,varargin)
% 第3阶段三部件瞬态辨识：固定稳态Excel，只拟合选定片段的h58:h70。
% 正式候选和前向差分均按自身参数重算热平衡、准备段及拟合段。
% 代价=0.5*r'*r+0.5*lambda*sum((k./sigma).^2)，lambda不平方。
switch lower(action)
    case 'options', out=local_options(varargin{:});
    case 'context', out=local_context(local_options(varargin{:}));
    case 'evaluate', out=local_evaluate(varargin{:});
    case 'linearize', out=local_linearize(varargin{:});
    case 'run', out=local_run(local_context(local_options(varargin{:})));
    case 'validate', out=local_validate(varargin{:});
    otherwise, error('F3:Transient:Action','未知操作：%s',action);
end
end

function o=local_options(u)
if nargin<1,u=struct();end
p=sht_f3_current_contract('paths');
pre=fullfile(p.middle,'preprocess','R020','delivery');
o=struct('runTag','R035','trainingWorkbook',fullfile(pre,'flight_model_adapt_3p2_identification.xlsx'), ...
    'testWorkbook',fullfile(pre,'flight_model_adapt_3p2_independent_validation.xlsx'), ...
    'steadyWorkbook',fullfile(p.middle,'identification','delivery', ...
    'flight_model_adapt_3p3_transient_instant_steady_only_set1_R027_nodes_formal.xlsx'), ...
    'integrationStep_s',.1,'warmup_s',60,'lambda',.05,'maximumIterations',6, ...
    'parameterScale',.3*ones(13,1), ...
    'lowerBound',-.5*ones(13,1),'upperBound',ones(13,1), ...
    'initial',zeros(13,1),'differenceStep',.01,'gradientTolerance',1e-5, ...
    'stepTolerance',1e-5,'objectiveTolerance',1e-7,'objectiveImprovementTolerance',1e-3, ...
    'resume',true,'historyScale',[63,114,7863,5.72], ...
    'outputRoot','','reportRoot','','runControl',[], ...
    'taskIdentity',struct(),'businessIdentity',struct(), ...
    'validationScopes',{{'local'}},'initializationSensitivity',false);
names=fieldnames(u);for j=1:numel(names)
    assert(isfield(o,names{j}),'F3:Transient:Option','未知配置：%s',names{j});o.(names{j})=u.(names{j});
end
assert(~isempty(regexp(o.runTag,'^[A-Za-z0-9_]+$','once')),'批次只能用字母数字和下划线。');
assert(ismember(o.integrationStep_s,[.1,.025])&&o.warmup_s>=0&&o.lambda>0);
assert(o.maximumIterations>=1&&o.maximumIterations==floor(o.maximumIterations));
for n={'parameterScale','lowerBound','upperBound','initial'}
    o.(n{1})=o.(n{1})(:);assert(numel(o.(n{1}))==13&&all(isfinite(o.(n{1}))));
end
assert(all(o.parameterScale>0)&&all(o.lowerBound>-1)&&all(o.lowerBound<o.upperBound));
assert(all(o.initial>=o.lowerBound&o.initial<=o.upperBound));
assert(o.differenceStep>0);
assert(isnumeric(o.historyScale)&&isreal(o.historyScale)&&isvector(o.historyScale)&& ...
    numel(o.historyScale)==4&&all(isfinite(o.historyScale(:)))&&all(o.historyScale(:)>0), ...
    'F3:Transient:HistoryScale','historyScale必须是4个正有限实数构成的数值向量。');
% 四个尺度按Np、Ng、Pt3_eq、Tt45列作用；JSON列向量与MATLAB行向量同义。
o.historyScale=reshape(o.historyScale,1,4);
end

function c=local_context(o)
p=sht_f3_current_contract('paths');t=fileparts(mfilename('fullpath'));
c=struct('options',o,'folder',fullfile(p.middle,'transient_identification',o.runTag), ...
    'report',fullfile(fileparts(p.report),['T3V1_' o.runTag]));
if ~isempty(o.outputRoot),c.folder=o.outputRoot;end
if ~isempty(o.reportRoot),c.report=o.reportRoot;end
for f={c.folder,c.report},if ~isfolder(f{1}),mkdir(f{1});end,end
c.assets=sht_f33_transient_delivery('runtimeassets',[],[]);
c.steady=sht_f33_excel_delivery('read',o.steadyWorkbook,c.assets);
c.assets.personalized.health=c.steady.schedule.designHealth;
c.assets.personalized.profile=c.steady.profile;c.assets.personalized.fuelBias=c.steady.schedule.fuelBias;
c.sensor=sht_f31_flight_measurement('publicAssumptions', ...
    sht_f31_flight_measurement('model',3201001,'F32-MEASUREMENT-PRIOR',false));
c.history=local_read_history(o.trainingWorkbook);
c.windows=readtable(o.trainingWorkbook,'Sheet','transient_windows');
c.plan=sht_f33_local_thermal_plan(c.history.time_s,c.windows,o.warmup_s);
assert(height(c.plan)>0,'没有可用大幅变化片段，不能静默回退为全历程。');
assert(all(c.plan.fit_first(2:end)>c.plan.fit_last(1:end-1)),'片段重叠，残差会重复计权。');
dict=sht_health_parameter_dictionary(0);c.parameters=dict(ismember(dict.c_index,58:70),{'c_index','name'});
assert(isequal(c.parameters.c_index,(58:70)'));
deps={'sht_f33_transient_identification','sht_f32_replay_history','sht_engine_derivative', ...
    'sht_thermal_equilibrium_solve','sht_bounded_least_squares','sht_f33_excel_delivery', ...
    'sht_f31_flight_measurement','sht_f3_current_contract','sht_f33_local_thermal_plan', ...
    'sht_tc27_regularized_solve','sht_steady_model_adapt_v2_common','sht_f33_transient_delivery'};
hashes=cellfun(@(n)sht_tc27_file_identity(fullfile(t,[n '.m'])),deps,'UniformOutput',false);
identityOptions=o;identityOptions.resume=[];identityOptions.runControl=[];
c.identity=struct('schema','F3_TRANSIENT_SELECTED_EXACT_V1','options',identityOptions, ...
    'trainingSha256',sht_tc27_file_identity(o.trainingWorkbook), ...
    'steadySha256',sht_tc27_file_identity(o.steadyWorkbook),'assets',c.assets.contract, ...
    'sensor',table2struct(c.sensor),'codeNames',{deps},'codeHashes',{hashes});
c.identityHash=sht_f33_model_adapt_v2('structHash',c.identity);
fprintf('F3 transient: %d parameters, %d windows, %d fit records, %.1fs preparation, dt=%.3gs.\n', ...
    13,height(c.plan),sum(c.plan.fit_sample_count),sum(c.plan.warmup_s),o.integrationStep_s);
writetable(c.plan,fullfile(c.report,'training_windows.csv'));
end

function e=local_evaluate(c,k,step,warmup,offset)
% 数据尺度按窗口平均、通道平均，不把40/10Hz记录数当独立实验次数。
if nargin<3,step=c.options.integrationStep_s;end
if nargin<4,warmup=c.options.warmup_s;end
if nargin<5,offset=0;end
assert(numel(k)==13&&all(isfinite(k))&&all(k>-1));
a=c.assets;a.personalized.health(59:71)=k(:);
plan=sht_f33_local_thermal_plan(c.history.time_s,c.windows,warmup);
ro=struct('cacheDirectory',fullfile(c.folder,'physical_cache'), ...
    'sourceSha256',c.identity.trainingSha256,'integrationMethod','euler2', ...
    'integrationStep_s',step,'inletMeanRecovery',c.steady.metadata.mean_inlet_recovery-c.steady.KdistEq, ...
    'exhaustBackPressureDesignRise_Pa',c.steady.metadata.backpressure_design_Pa, ...
    'initialThermalOffset_K',offset,'progressIntervalSamples',10000);
e=struct('k',k(:),'residual',[],'raw',[],'prediction',[],'measured',[], ...
    'time_s',[],'window',[],'physicalOutput',[],'replayFiles',{{}},'valid',false,'error','', ...
    'wall_s',0,'dllCalls',0,'maxCommonResidual',0);
timer=tic;
try
    for j=1:height(plan)
        rows=plan.initialization_first(j):plan.fit_last(j);
        r=sht_f32_replay_history('run',c.history(rows,:),a,'personalized',c.sensor,ro);
        assert(r.computationallyAccepted,'F3:Transient:InvalidReplay','片段%d物理回放未通过。',j);
        fit=(plan.fit_first(j):plan.fit_last(j))-rows(1)+1;
        raw=r.residual(fit,:);nr=size(raw,1);
        scaled=raw./c.options.historyScale/sqrt(nr*4*height(plan));
        e.residual=[e.residual;scaled(:)]; %#ok<AGROW>
        e.raw=[e.raw;raw];e.prediction=[e.prediction;r.sensorExpectedOutput(fit,:)]; %#ok<AGROW>
        e.measured=[e.measured;r.measuredOutput(fit,:)];e.time_s=[e.time_s;r.time_s(fit)]; %#ok<AGROW>
        e.physicalOutput=[e.physicalOutput;r.trueModelOutput(fit,:)]; %#ok<AGROW>
        e.window=[e.window;repmat(j,nr,1)];e.replayFiles{j}=r.cacheFile; %#ok<AGROW>
        e.dllCalls=e.dllCalls+r.executedEvaluationCount;
        e.maxCommonResidual=max(e.maxCommonResidual,r.maximumCommonWorkResidual);
    end
    e.valid=all(isfinite(e.residual));
catch failure
    e.error=getReport(failure,'extended','hyperlinks','off');
    fid=fopen(fullfile(c.report,'failed_evaluations.log'),'a');
    if fid>=0,fprintf(fid,'%s\n%s\n%s\n',datestr(now,31),mat2str(k(:).',12),e.error);fclose(fid);end
end
e.wall_s=toc(timer);
end

function l=local_linearize(c,k,base)
if nargin<3,base=local_evaluate(c,k);end
assert(base.valid,'F3:Transient:Base','基点回放失败：%s',base.error);
timer=tic;J=zeros(numel(base.residual),13);calls=0;steps=zeros(13,1);
for j=1:13
    step=c.options.differenceStep;
    if k(j)+step>c.options.upperBound(j),step=-step;end
    ok=false;
    for attempt=1:3
        q=k;q(j)=k(j)+step;
        if q(j)>=c.options.lowerBound(j)&&q(j)<=c.options.upperBound(j)
            perturbed=local_evaluate(c,q);calls=calls+perturbed.dllCalls;
            if perturbed.valid,ok=true;break;end
        end
        % 失败先反向，再缩短前向步长；不能用无效列或零列替代。
        if attempt==1,step=-step;else,step=abs(step)/2;end
    end
    assert(ok,'F3:Transient:Difference','h%d差分两侧均失败，见失败日志。',57+j);
    J(:,j)=(perturbed.residual-base.residual)/step;steps(j)=step;
    fprintf('  Jacobian h%d (%d/13): %.2fs, DLL=%d\n',57+j,j,perturbed.wall_s,perturbed.dllCalls);
end
scaledJ=J.*c.options.parameterScale';z=k./c.options.parameterScale;
g=scaledJ'*base.residual+c.options.lambda*z;
g(k<=c.options.lowerBound+1e-10&g>0)=0;g(k>=c.options.upperBound-1e-10&g<0)=0;
l=struct('k',k,'J',J,'residual',base.residual,'signedStep',steps, ...
    'gradientInf',norm(g,inf),'singularValues',svd(scaledJ,0), ...
    'wall_s',toc(timer),'dllCalls',calls,'base',base);
end

function r=local_run(c)
% 复用TC27已验收的通用数值内核，业务数据和模型仍全部来自本阶段。
% 内核lambda平方，本阶段lambda直接乘先验项，故仅在边界传sqrt(lambda)。
o=c.options;file=fullfile(c.folder,'result.mat');
if isfile(file)
    z=load(file,'result');assert(strcmp(z.result.identityHash,c.identityHash),'已完成批次身份改变，请更换runTag。');
    r=z.result;return;
end
timer=tic;calls=0;evaluationTime=0;cache=containers.Map('KeyType','char','ValueType','any');
checkpoint=fullfile(c.folder,'solver_iteration.mat');
assert(o.resume||~isfile(checkpoint),'禁用续算时必须使用空的新批次。');
initial=exactEvaluation(o.initial);
assert(initial.valid,'初值回放失败：%s',initial.error);
so=struct('method','tikhonov','lambda',sqrt(o.lambda),'difference','forward', ...
    'maxIterations',o.maximumIterations,'gradientTolerance',o.gradientTolerance, ...
    'stepTolerance',o.stepTolerance,'costTolerance',o.objectiveTolerance, ...
    'objectiveImprovementTolerance',o.objectiveImprovementTolerance, ...
    'label',['F3_' o.runTag],'checkpointFile',checkpoint,'inputIdentity',c.identity, ...
    'captureInitialLinearization',true);
if ~isempty(o.runControl)
    so.runControl=o.runControl;so.runControlKey='transient_solver';
end
solve=sht_tc27_regularized_solve(@objective,o.initial,zeros(13,1),o.parameterScale, ...
    o.lowerBound,o.upperBound,o.differenceStep*ones(13,1),so);
final=exactEvaluation(solve.x);
assert(solve.finalJacobianAtFinalParameters&&~solve.frozenPreparationJacobian);
g=solve.scaledDataJacobian'*solve.residual+o.lambda*solve.x./o.parameterScale;
g(solve.x<=o.lowerBound+1e-10&g>0)=0;g(solve.x>=o.upperBound-1e-10&g<0)=0;
last=struct('k',solve.x,'J',solve.dataJacobian,'residual',solve.residual, ...
    'gradientInf',norm(g,inf),'singularValues',solve.singularValues,'base',final);
parameters=c.parameters;parameters.prior=zeros(13,1);parameters.estimate=solve.x;
parameters.prior_scale=o.parameterScale;parameters.lower=o.lowerBound;parameters.upper=o.upperBound;
parameters.initial=o.initial;
parameters.at_bound=abs(solve.x-o.lowerBound)<1e-8|abs(solve.x-o.upperBound)<1e-8;
r=struct('schema','F3_TRANSIENT_RESULT_V1','identity',c.identity,'identityHash',c.identityHash, ...
    'options',o,'parameters',parameters,'k',solve.x,'initial',initial,'final',final, ...
    'solve',solve,'finalLinearization',last,'converged',solve.converged, ...
    'firstOrderStationarityPassed',solve.firstOrderStationarityPassed, ...
    'stopReason',solve.stopReason,'totalCompute_s',toc(timer),'evaluationTime_s',evaluationTime, ...
    'dllCalls',calls,'trainingPlan',c.plan,'truthUsed',false,'folder',c.folder,'report',c.report);
% 中断续算的既往耗时保留在内核history中；本次计时不冒充跨进程总墙钟时间。
r.invocationOnlyTiming=true;r.regularizationDefinition='0.5*r''*r+0.5*lambda*sum((k./sigma).^2)';
result=r;save(file,'result','-v7.3');
writetable(parameters,fullfile(c.report,'transient_parameters.csv'));
writetable(solve.history,fullfile(c.report,'iterations.csv'));
sht_f33_transient_delivery('write',r,fullfile(c.folder,'flight_transient_model.xlsx'));
fprintf('F3 transient frozen: %s; gradient %.6g; %.2f min; DLL=%d\n', ...
    char(solve.stopReason),last.gradientInf,r.totalCompute_s/60,calls);
    function e=exactEvaluation(k)
        key=sprintf('%.17g,',k);
        if isKey(cache,key),e=cache(key);return;end
        e=local_evaluate(c,k);calls=calls+e.dllCalls;evaluationTime=evaluationTime+e.wall_s;
        cache(key)=e;
    end
    function [residual,meta]=objective(k)
        e=exactEvaluation(k);residual=e.residual;
        if ~e.valid,residual=inf(numel(initial.residual),1);end
        meta=struct('valid',e.valid,'error',e.error,'replayFiles',{e.replayFiles});
    end
end

function out=local_validate(resultFile)
z=load(resultFile,'result');r=z.result;c=local_context(r.options);
assert(strcmp(c.identityHash,r.identityHash),'验证源码/物理合同与求解冻结不一致。');
timer=tic;rows=table();results=cell(2,2);
datasets=1;if ~isempty(c.options.testWorkbook),datasets=1:2;end
for d=datasets
    if d==1,file=c.options.trainingWorkbook;role="training";else,file=c.options.testWorkbook;role="independent_test";end
    history=local_read_history(file);segments=readtable(file,'Sheet','segments');
    windows=readtable(file,'Sheet','transient_windows');
    cc=c;cc.history=history;cc.windows=windows;cc.identity.trainingSha256=sht_tc27_file_identity(file);
    for j=1:2
        k=zeros(13,1);label="steady_only";if j==2,k=r.k;label="steady_plus_transient";end
        local=local_evaluate(cc,k);assert(local.valid,'独立局部预测失败：%s',local.error);
        a=c.assets;a.personalized.health(59:71)=k;
        ro=struct('cacheDirectory',fullfile(c.folder,'prediction_cache'), ...
            'sourceSha256',cc.identity.trainingSha256,'integrationStep_s',c.options.integrationStep_s, ...
            'integrationMethod','euler2','progressIntervalSamples',10000);
        ro.inletMeanRecovery=c.steady.metadata.mean_inlet_recovery-c.steady.KdistEq;
        ro.exhaustBackPressureDesignRise_Pa=c.steady.metadata.backpressure_design_Pa;
        results{d,j}=struct('local',local);
        rows=[rows;local_metrics(role,label,"local_large_windows",local.raw)]; %#ok<AGROW>
        if ~ismember('full',c.options.validationScopes),continue;end
        full=sht_f32_replay_history('run',history,a,'personalized',c.sensor,ro);
        assert(full.computationallyAccepted,'完整历程预测失败。');
        results{d,j}=struct('local',local,'full',full);
        rows=[rows;local_metrics(role,label,"full_history",full.residual)]; %#ok<AGROW>
        for typ=["steady_window","small_change"]
            mask=false(height(history),1);
            ss=segments(string(segments.segment_class)==typ,:);
            for q=1:height(ss),mask(ss.first(q):ss.last(q))=true;end
            if any(mask),rows=[rows;local_metrics(role,label,"full_"+typ,full.residual(mask,:))];end %#ok<AGROW>
        end
    end
end
% 热初值/准备长度审计只报告敏感性，不用测试集或真值重新调参。
sensitivity=table();base=r.final;
specs=zeros(2,0);if c.options.initializationSensitivity,specs=[120,240,60,60;0,0,-20,20];end
for spec=specs
    e=local_evaluate(c,r.k,c.options.integrationStep_s,spec(1),spec(2));
    assert(e.valid,'热初始化敏感性计算失败：%s',e.error);
    diff=e.prediction-base.prediction;
    t=local_metrics("training","initialization_sensitivity",sprintf('warmup_%g_offset_%g',spec(1),spec(2)),diff);
    sensitivity=[sensitivity;t]; %#ok<AGROW>
end
out=struct('metrics',rows,'results',{results},'initializationSensitivity',sensitivity, ...
    'elapsed_s',toc(timer),'sourceResult',resultFile,'truthUsed',false);
save(fullfile(c.folder,'validation.mat'),'out','-v7.3');
writetable(rows,fullfile(c.report,'prediction_metrics.csv'));
writetable(sensitivity,fullfile(c.report,'initialization_sensitivity.csv'));
end

function t=local_metrics(role,model,scope,raw)
n=["Np";"Ng";"Pt3_eq";"Tt45"];u=["rpm";"rpm";"Pa";"K"];
t=table(repmat(string(role),4,1),repmat(string(model),4,1),repmat(string(scope),4,1),n,u, ...
    sqrt(mean(raw.^2,1))',mean(raw,1)',max(abs(raw),[],1)', ...
    'VariableNames',{'dataset','model','scope','channel','unit','RMSE','mean_error','max_abs_error'});
end

function h=local_read_history(file)
% 预处理Excel同时含片段标签和诊断列，回放只接收真实可测的数值列。
% 尤其细网格插值不能把segment_id等字符串混入状态输入矩阵。
h=readtable(file,'Sheet','history');
names={'sample_id','time_s','Ps0','Tt1','Pt3_eq','Ng','Np','Mkp','Wf','Tt45','Altitude','Mach','Ts_amb'};
assert(all(ismember(names,h.Properties.VariableNames)),'飞参测量列不完整。');
h=h(:,names);assert(all(isfinite(h{:,:}),'all'),'飞参存在非有限测量数据。');
end
