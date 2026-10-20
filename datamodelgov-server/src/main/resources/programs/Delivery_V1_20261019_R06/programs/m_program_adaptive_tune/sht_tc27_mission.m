function m=sht_tc27_mission(kind)
%SHT_TC27_MISSION 三部件带载试车指令。平台、小幅和大幅段连续连接。
% 标签仅用于造数后的独立检查；下游从测量Excel自行识别，不读取标签。
% 列：时段终点(s)、Np相对设计转速、该转速目标功率(kW)、小幅功率幅值(kW)。
switch lower(kind)
    case 'train'
        initial=[.7,439];
        plan=[30,.7,439,0;90,.7,439,18;100,.85,1000,0;145,.85,1000,0; ...
            205,.85,1000,35;213,1,1650,0;253,1,1650,0;313,1,1650,50; ...
            317,1,1756,0;321,1,2176.6,0;331,1,2176.6,0;339,.8,659,0; ...
            389,.8,659,0;399,.9,1100,0;439,.9,1100,0;449,.7,439,0;480,.7,439,0];
    case 'test'
        initial=[.75,550];
        plan=[25,.75,550,0;75,.75,550,23;83,.95,1450,0;113,.95,1450,0; ...
            163,.95,1450,45;171,1,1756,0;193,1,1756,0;201,.8,750,0;240,.8,750,0];
    case 'short'
        initial=[.9,1100];
        plan=[5,.9,1100,0;8,.95,1450,0;17,.95,1450,0;20,.85,850,0;30,.85,850,0];
    otherwise,error('TC27:Mission:Kind','未知历程%s。',kind);
end
t=(0:.025:plan(end,1)).';np=zeros(size(t));power=np;start=0;previous=initial;
segment=table();
for j=1:size(plan,1)
    finish=plan(j,1);select=t>=start & t<=finish;u=(t(select)-start)/(finish-start);
    target=plan(j,2:3);amplitude=plan(j,4);
    if amplitude>0
        label="small_change";np(select)=target(1);
        % 整数周期、端点零斜率包络，避免把小幅段接缝伪造成阶跃。
        cycles=round((finish-start)/12);
        envelope=min(1,(u/.10).^2).*min(1,((1-u)/.10).^2);
        wave=sin(2*pi*cycles*u).*envelope;
        power(select)=target(2)+amplitude*wave;
    elseif max(abs(target-previous))>1e-10
        label="transition";np(select)=previous(1)+(target(1)-previous(1))*u;
        power(select)=previous(2)+(target(2)-previous(2))*u;
    else
        label="plateau";np(select)=target(1);power(select)=target(2);
    end
    segment=[segment;table(j,start,finish,label,'VariableNames', ...
        {'segment','start_s','end_s','kind'})]; %#ok<AGROW>
    previous=target;start=finish;
end
ktheta=power/2176.6./np.^3;
assert(all(ktheta>.15),'TC27:Mission:BelowRotorProfile','目标低于当前旋翼型阻功率。');
theta=12*((ktheta-.15)/.85).^(2/3);
m=struct('kind',kind,'time',t,'Npr',np,'power_W',power*1000, ...
    'theta_deg',theta,'segments',segment,'duration_s',t(end), ...
    'integrationStep_s',.025,'recordStep_s',.1);
end
