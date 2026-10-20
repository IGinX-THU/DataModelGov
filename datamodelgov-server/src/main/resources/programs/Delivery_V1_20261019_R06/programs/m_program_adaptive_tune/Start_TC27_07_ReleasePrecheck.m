function result=Start_TC27_07_ReleasePrecheck(options)
%START_TC27_07_RELEASEPRECHECK 独立可选工程扰动诊断，不是正式辨识前置。
% 不据此移除已经确认的13个系数，不生成快速初值，不向正式07传递初值。
if nargin<1,options=struct();end
if ~isfield(options,'outputBatch')
    defaults=sht_tc27_estimation_options('transient_instant','II');
    options.outputBatch=defaults.outputBatch;
end
if ~isfield(options,'engineeringAmplitude'),options.engineeringAmplitude=.2;end
if ~isfield(options,'integrationStep_s'),options.integrationStep_s=.1;end
p=sht_tc27_paths(options);v=load(fullfile(p.middle,'tc27_prepared_data.mat'),'result');r=v.result;
d=sht_tc27_delivery('read',[],fullfile(p.middle,'tc27_deterministic_transient_instant_II.xlsx'));
plan=sht_tc27_transient_plan(r.train,'full_history');cfg=sht_tc27_config(3);
engine=sht_engine_open(cfg.engine);clean=onCleanup(@()sht_engine_close(engine));timer=tic;
base=sht_tc27_replay_histories(cfg,engine,plan,d.finalSchedule,struct('integrationStep_s',options.integrationStep_s));
names={'Np','Ng','Ptb3','Ttb3','Pt45','Tt45','Pt6','Tt6'};spec=sht_tc24_measurement_specification();
noise=zeros(1,8);effective=zeros(1,8);
for j=1:8,q=spec.name==names{j};noise(j)=spec.noiseStd(q);effective(j)=max(.1,2*spec.timeConstant_s(q));end
strength=zeros(13,8);
for j=1:13
    h=zeros(13,1);h(j)=options.engineeringAmplitude;
    pred=sht_tc27_replay_histories(cfg,engine,plan,d.finalSchedule, ...
        struct('integrationStep_s',options.integrationStep_s,'transientHealth',h));
    for k=1:numel(plan)
        delta=(pred{k}.prediction{:,names}-base{k}.prediction{:,names})./noise;
        strength(j,:)=strength(j,:)+sum(delta.^2,1)*.1./effective;
    end
end
strength=sqrt(strength);
result=struct('hIndex',(58:70).','strength',strength,'channels',{names}, ...
    'confirmedForEstimation',true(13,1),'changedFormalParameterSet',false,'runtime_s',toc(timer));
save(fullfile(p.middle,'optional_release_precheck.mat'),'result');
t=array2table(strength,'VariableNames',names);t.hIndex=result.hIndex;
writetable(t,fullfile(p.report,'optional_release_precheck.csv'));disp(t);
end
