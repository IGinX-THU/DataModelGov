function result=Start_TC27_04_BenchDataGeneration(options)
%START_TC27_04_BENCHDATAGENERATION 480/240秒三部件Visser连续带载试车。
% 正式Excel仅有时间与测量值，标签/控制目标/真值/传感器实际偏置不交付辨识。
if nargin<1,options=struct();end
if ~isfield(options,'plot'),options.plot=true;end
if ~isfield(options,'sets'),options.sets={'train','test'};end
p=sht_tc27_paths();
source=fullfile(p.root,'MiddleData','three_component','three_component_health_schedule_latest.mat');
data=load(source,'profile');profile=data.profile;health=profile.truthVectorAtDesign;
% 三部件独立瞬态参数h58:h70。时间尺度采用当前C合同(1+k)，不是对数坐标。
transientNames=["K_Jg";"K_Jp";"K_tau_HPC";"K_tau_Burner";"K_tau_GT";"K_tau_PT"; ...
    "K_gapW_HPC";"K_gapEta_HPC";"K_gapEta_GT";"K_gapEta_PT"; ...
    "K_diskTau_HPC";"K_diskTau_GT";"K_diskTau_PT"];
transientTruth=[.12;-.08;.20;-.12;.25;.15;.15;-.10;.18;-.12;.25;.30;.20];
health(59:71)=transientTruth;
result=struct();
for j=1:numel(options.sets)
    kind=options.sets{j};m=sht_tc27_mission(kind);
    if strcmp(kind,'train'),file=p.trainingFile;seed=27;else,file=p.testFile;seed=28;end
    timer=tic;
    [cfg,trim]=sht_tc27_simulation_config(m,3,health,profile,true,20260910+101*seed);
    simulation=sht_simulate_control_m(cfg);
    [measurement,validation]=sht_tc27_measurements('generate',simulation,seed);
    assert(height(measurement)==round(m.duration_s/.1)+1,'记录样本数不正确。');
    assert(all(measurement.Mach==0),'台架Mach必须恒为0。');
    writetable(measurement,file,'Sheet','Measurements');
    output=struct('simulation',simulation,'measurement',measurement,'validation',validation, ...
        'mission',m,'trim',trim,'health',health,'profile',profile, ...
        'transientTruth',table((58:70).',transientNames,transientTruth, ...
        'VariableNames',{'hIndex','parameter','truth'}),'elapsedSeconds',toc(timer),'file',file);
    save(fullfile(p.middle,['tc27_',kind,'_validation.mat']),'output','-v7.3');
    result.(kind)=struct('file',file,'duration_s',m.duration_s,'recordCount',height(measurement), ...
        'elapsed_s',output.elapsedSeconds,'minNp',min(measurement.Np),'maxNp',max(measurement.Np));
    writetable(m.segments,fullfile(p.report,['TC27_04_',kind,'_command_segments.csv']));
    if options.plot,local_plot(output,p.report,kind);end
    fprintf('TC27-04 %s: %gs, %d点, 运行%.1fs, Excel %s\n', ...
        kind,m.duration_s,height(measurement),output.elapsedSeconds,file);
end
save(fullfile(p.middle,'tc27_generation_summary.mat'),'result');
end

function local_plot(r,directory,kind)
f=figure('Name',['TC27 ',kind,' measurements'],'Position',[80,80,1150,800]);
channels={'Np','Ng','Wf','Mkp','Ptb3','Ttb3','Pt45','Tt45'};
for j=1:numel(channels)
    subplot(4,2,j);plot(r.measurement.Time_s,r.validation.table.(channels{j}),'k-');hold on;
    plot(r.measurement.Time_s,r.measurement.(channels{j}),'r-');grid on;
    xlabel('Time / s');ylabel(channels{j},'Interpreter','none');
end
legend('Truth','Measurement');print(f,fullfile(directory,['TC27_04_',kind,'_measurement.png']),'-dpng','-r150');
end
