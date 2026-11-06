function s=sht_stage4_scenarios()
% 每一行是独立架次。故障在F05起飞前形成，三个故障不能串接到正常主线。
ids={'F01','F02','F03','F04','F05_N','F05_HPC','F05_GT','F05_PT','F06'};
parent={'BENCH','F01','F02','F03','F04','F04','F04','F04','F05_N'};
order=[1 2 3 4 5 5 5 5 6];
s=repmat(struct('id','','parent','','order',0,'role','','definition',struct(), ...
    'healthOffset',zeros(159,1),'seed',0,'reuse',false),numel(ids),1);
for j=1:numel(ids)
    n=order(j);s(j).id=ids{j};s(j).parent=parent{j};s(j).order=n;
    s(j).role='identification';s(j).reuse=j==1;
    if j==9,s(j).role='prediction_only';end
    % 每个代表架次的变化是工程演示先验，不表示真实飞行一次必然如此退化。
    h=zeros(159,1);h([2 3 8 9 12 13])=(n-1)*[-.0005;-.0008;.0003;-.0006;.00025;-.0005];
    if j==6,h([2 3])=h([2 3])+[-.002;-.004];end
    if j==7,h([8 9])=h([8 9])+[.001;-.004];end
    if j==8,h([12 13])=h([12 13])+[.001;-.004];end
    s(j).healthOffset=h;s(j).seed=410000+n*101;
    if j==1,s(j).seed=3101001;end % 继承F01的实际造数种子，新的定义仅作占位。
    % 三种故障使用相同外部任务及随机实现，隔离故障造成的响应变化。
    stream=RandStream('mt19937ar','Seed',420000+n);
    altitudeShift=20*(2*rand(stream)-1);machShift=.003*(2*rand(stream)-1);
    pitchShift=.08*(2*rand(stream)-1);
    d=struct('missionId',ids{j},'datasetRole','identification', ...
        'displayName',['Stage4 ',ids{j}], ...
        'nodeTime_s',[0 80 100 210 230 340 360 470 490 600 620 720], ...
        'altitudeNode_m',[100 100 300 300 900 900 1050 1050 650 650 100 100]+altitudeShift, ...
        'machNode',[0 0 .06 .06 .16 .16 .14 .14 .18 .18 0 0], ...
        'thetaNode_deg',[6.5 6.5 10.5 10.5 9.2 9.2 10.8 10.8 8.4 8.4 6.8 6.8]+pitchShift, ...
        'tailPitchNode_deg',[6.8 6.8 9.8 9.8 8.5 8.5 10 10 7.8 7.8 7 7], ...
        'K_dist_eq',.006,'segmentId',{{}},'segmentType',{{}}, ...
        'initialThermalCheckMode','window_mean_drift');
    d.machNode(d.machNode>0)=d.machNode(d.machNode>0)+machShift;
    for k=1:numel(d.nodeTime_s)-1
        d.segmentId{k}=sprintf('%s_%02d',ids{j},k);
        if mod(k,2),d.segmentType{k}='cruise_hold';else,d.segmentType{k}='load_transition';end
    end
    s(j).definition=d;
end
end
