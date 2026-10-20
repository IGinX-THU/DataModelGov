function varargout=sht_tc27_measurements(action,varargin)
%SHT_TC27_MEASUREMENTS 三部件连续试车观测生成，仅供造数与独立真值验证。
% 复用TC24相同测点、FOH及计量截面关系；实际偏置不进入辨识输入Excel。
switch lower(action)
    case 'bias'
        varargout{1}=local_bias(varargin{:});
    case 'generate'
        simulation=varargin{1};seed=varargin{2};spec=sht_tc24_measurement_specification();
        meter=struct('scavengeFraction',.05,'area_m2',.08,'areaBiasFraction',.005, ...
            'staticPressureBias_Pa',-10,'staticPressureNoiseStd_Pa',4, ...
            'blowerBiasFraction',.02,'blowerNoiseStdFraction',.005);
        [truth,measurement,bias]=local_measurements(simulation.log,spec,meter,seed,simulation.cfg);
        time=simulation.time(:);index=1:4:numel(time);
        measured=table(time(index),'VariableNames',{'Time_s'});
        exact=measured;names=fieldnames(measurement);
        for j=1:numel(names)
            measured.(names{j})=measurement.(names{j})(index);
            exact.(names{j})=truth.(names{j})(index);
        end
        varargout={measured,struct('table',exact,'bias',bias,'meter',meter,'spec',spec)};
    otherwise,error('TC27:Measurement:Action','未知动作%s。',action);
end
end

function b=local_bias(row,flow)
% 偏置真值仅造数侧使用。Wf/Ttb3/Tt45保留随流量的10%范围漂移。
f=min(max((6.7114-flow)/(6.7114-2.1803),0),1);
signs=struct('Np',.3,'Ng',-.35,'Wf',.7,'Mkp',.7,'Pt1',-.4,'Tt1',.7, ...
    'Ptb3',.7,'Ttb3',-.7,'Pt45',-.7,'Tt45',-.7,'Pt6',-.5,'Tt6',-.6, ...
    'Pamb',-.7,'Tamb',.7,'Altitude',1,'Mach',0,'RH',.5);
b=row.biasHalfWidth*signs.(char(row.name));
if row.name=="Wf",b=b+.1*row.biasHalfWidth*f;end
if ismember(row.name,["Ttb3","Tt45"]),b=b-.1*row.biasHalfWidth*f;end
end

function [t,m,bias]=local_measurements(l,spec,meter,index,sim)
names=cellstr(spec.name); sources={'Np','Ng','Wf','Mkp','Pt1','Tt1','Pt3','Tt3', ...
    'Pt45','Tt45','Pt5','Tt5','Pamb','Tamb','Altitude','Mach','RH'};
samples={'sampleNp','sampleNg','','sampleMkp','samplePt1','sampleTt1', ...
    'samplePt3','sampleTt3','samplePt45','sampleTt45','samplePt5','sampleT5', ...
    'samplePamb','sampleTamb','sampleAltitude','sampleMach',''};
rng(20260908+index*101+500000,'twister');
n=numel(l.time);t=struct();m=struct();bias=struct();
for j=1:numel(names)
    name=names{j};
    if strcmp(name,'RH'), raw=60*ones(n,1);else,raw=l.(sources{j});end
    if strcmp(name,'Mach'),raw=zeros(n,1);end
    t.(name)=raw;
    b=arrayfun(@(w)local_bias(spec(j,:),w),l.WIn);
    bias.(name)=b;
    if isempty(samples{j})
        filtered=local_filter(l.time,raw,spec.timeConstant_s(j));
        m.(name)=filtered+b+spec.noiseStd(j)*randn(n,1);
    else
        m.(name)=l.(samples{j});
        % 这些通道已在控制闭环注入偏置，不再记录另一套随瞬时流量计算的值。
        sensorIndex=find(strcmp(sim.sensor.channels,sources{j}),1);
        if strcmp(name,'Pt1'),sensorIndex=8;end
        if strcmp(name,'Tt6'),sensorIndex=find(strcmp(sim.sensor.channels,'Tt5'),1);end
        if isempty(sensorIndex) && strcmp(name,'Tt45')
            sensorIndex=find(strcmp(sim.sensor.channels,'T45'),1);
        end
        assert(~isempty(sensorIndex),'TC24:Generation:BiasIndex','无法追溯%s的闭环偏置。',name);
        bias.(name)=repmat(sim.sensor.bias(sensorIndex),n,1);
    end
end
t.Wa1=l.WIn/(1-meter.scavengeFraction);t.Wb=t.Wa1-l.WIn;
% 用等熵低速计量截面关系得到静压，然后使用同一时刻测量Pt1/Tt1
% 反算Wa1，共同误差由此自然保留。飞行Mach=0不代替计量截面Mach。
gamma=1.4;R=287.05;A=meter.area_m2;
mach=zeros(n,1);
for k=1:n
    q=t.Wa1(k)*sqrt(t.Tt1(k))/(A*t.Pt1(k)*sqrt(gamma/R));
    mach(k)=fzero(@(v)v*(1+.2*v*v)^(-3)-q,[0,.9]);
end
ps=t.Pt1./(1+.2*mach.^2).^3.5;
psm=ps+meter.staticPressureBias_Pa+meter.staticPressureNoiseStd_Pa*randn(n,1);
mm=sqrt(max(0,5*((m.Pt1./psm).^(2/7)-1)));
m.Wa1=A*(1+meter.areaBiasFraction)*m.Pt1.*sqrt(gamma./(R*m.Tt1)).*mm./(1+.2*mm.^2).^3;
m.Wb=t.Wb*(1+meter.blowerBiasFraction)+meter.blowerNoiseStdFraction*t.Wb.*randn(n,1);
t.Pshaft=t.Mkp.*t.Np*pi/30;m.Pshaft=m.Mkp.*m.Np*pi/30;
% 未建模的鼓风机出口/局部单点温压显式缺省，不复制测量耙代表值。
for name={'Pt3','Tt3','Pt13','Tt13'}
    t.(name{1})=nan(n,1);m.(name{1})=nan(n,1);
end
end

function y=local_filter(t,u,tau)
y=u;
for k=2:numel(t)
    [a,b,c]=sht_first_order_foh_coefficients(t(k)-t(k-1),tau);
    y(k)=a*y(k-1)+b*u(k-1)+c*u(k);
end
end
