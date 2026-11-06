function model=sht_tc27_uq_covariance(c,evaluate)
%SHT_TC27_UQ_COVARIANCE 两批独立公共偏置、输入误差传播及24维附加参数边缘化。
% 输出白噪声在传感器动态之后加入；输入误差通过实际积分/FOH模型传播。
% 各稳态点的输入噪声采用逐通道线性传播，各历程采用独立低秩块，
% 不把有限样本偶然交叉相关当作跨工况相关。公共偏置仍跨工况共享。
file=fullfile(c.directory,'covariance.mat');
if isfile(file),a=load(file,'model');model=a.model;return;end
timer=tic;old=rng;clean=onCleanup(@()rng(old));rng(c.options.randomSeed+11);
spec=sht_tc24_uq_measurement('model',[]);spec=spec.specification;
tc24Engineering=strcmp(c.options.errorModel,'tc24_engineering');
n=numel(c.observed);np=height(c.trainingData);base=evaluate(c.thetaHat);
assert(all(base.valid),'TC27:UQ:Baseline','确定性结果不能用于当前UQ回放：%s',base.messages);
variance=zeros(n,1);
for j=1:9
    rows=(j-1)*np+(1:np);
    if j<=2
        % 同一Np/Ng测量经下方联合扰动进入观测与可能的求解初值，
        % 不在对角项中第二次独立计量；此处仅留数值正定地板。
        variance(rows)=1e-12;
    else
        q=find(spec.name==string(c.outputNames{j}),1);variance(rows)=spec.noiseStd(q)^2./c.sampleCount;
    end
end
offset=9*np;initialSensorFactor=[];
for h=1:numel(c.histories)
    count=height(c.histories(h).data);
    for j=1:9
        q=find(spec.name==string(c.historyNames{j}),1);rows=offset+(j-1)*count+(1:count);
        variance(rows)=spec.noiseStd(q)^2;
        if j<=8
            % 第一个观测初始化传感器状态，不再被当作一个独立拟合输出。
            variance(rows(1))=1e-12;
            if j>=3
                % Np/Ng的初值噪声随物理状态由下方MC传播；其余输出仅
                % 初始化一阶传感器，精确指数响应即可形成相关误差列。
                col=zeros(n,1);t=c.histories(h).data.Time_s;
                col(rows)=spec.noiseStd(q)*exp(-(t-t(1))/spec.timeConstant_s(q));
                col(rows(1))=0;initialSensorFactor(:,end+1)=col; %#ok<AGROW>
            end
        end
    end
    offset=offset+9*count;
end
variance=max(variance,1e-12);
inputs={'Np','Ng','Wf','Mkp','Pt1','Tt1','Pamb'};
biasFactor=[];biasLabels=strings(0,1);
% Wf偏置是实际模型节点主参数的一部分，不能再作为未知公共误差重复计入。
allSensors=unique([inputs,c.historyNames(3:end)],'stable');allSensors(strcmp(allSensors,'Wf'))=[];
for campaign=1:2
    for k=1:numel(allSensors)
        name=allSensors{k};q=find(spec.name==string(name),1);sigma=spec.biasHalfWidth(q)/sqrt(3);
        if sigma==0,continue;end
        override=struct('points',c.trainingData,'histories',c.histories);
        mask=c.source==campaign;
        override.points=perturb(override.points,name,sigma*double(mask),true,tc24Engineering);
        if campaign==2
            for h=1:numel(override.histories)
                override.histories(h).data=perturb(override.histories(h).data,name,sigma,false,tc24Engineering);
            end
        end
        if ismember(name,inputs)
            z=evaluate(c.thetaHat,[],override);assert(z.valid,'公共偏置扰动%s失败：%s',name,z.messages);
            col=z.residual-base.residual;
        else
            % 静态输出偏置不改变发动机；历史传感器初值也有该误差，因此
            % 保留FOH初值响应exp(-t/tau)，不能简单将整条历程平移。
            col=-(sht_tc27_uq_data_vector(override.points,override.histories,c.route)-c.observed);
            if campaign==2
                off=9*np;
                for h=1:numel(c.histories)
                    t=c.histories(h).data;count=height(t);j=find(strcmp(c.historyNames,name));
                    if j<=8,rows=off+(j-1)*count+(1:count);col(rows)=col(rows)+sigma*exp(-(t.Time_s-t.Time_s(1))/spec.timeConstant_s(q));end
                    off=off+9*count;
                end
            end
        end
        biasFactor(:,end+1)=col;biasLabels(end+1)=sprintf('campaign%d_%s',campaign,name); %#ok<AGROW>
    end
end
% 稳态点彼此独立。每个输入同时扰动所有点，但各点的响应单独
% 形成协方差列；这里保留Np/Ng输入与其派生残差之间的物理耦合。
pointNoiseFactor=zeros(n,np*numel(inputs));
for k=1:numel(inputs)
    name=inputs{k};q=find(spec.name==string(name),1);
    override=struct('points',c.trainingData,'histories',c.histories);
    delta=spec.noiseStd(q)./sqrt(c.sampleCount);
    override.points=perturb(override.points,name,delta,true,tc24Engineering);
    z=evaluate(c.thetaHat,[],override);assert(z.valid,'稳态点输入噪声传播%s失败。',name);
    change=z.residual-base.residual;
    for point=1:np
        rows=point+(0:8)*np;
        pointNoiseFactor(rows,(k-1)*np+point)=change(rows);
    end
end
count=c.options.measurementSamples;
if isempty(c.histories),count=0;end % 仅稳态模式不执行任何历程噪声MC回放。
noiseFactor=zeros(n,count);
for sample=1:count
    override=struct('points',c.trainingData,'histories',c.histories);
    for k=1:numel(inputs)
        name=inputs{k};q=find(spec.name==string(name),1);sigma=spec.noiseStd(q);
        for h=1:numel(override.histories)
            t=override.histories(h).data;
            if ismember(name,{'Np','Ng'}),delta=zeros(height(t),1);delta(1)=sigma*randn;
            else,delta=sigma*randn(height(t),1);end
            override.histories(h).data=perturb(t,name,delta,false,tc24Engineering);
        end
    end
    z=evaluate(c.thetaHat,[],override);assert(z.valid,'输入噪声传播失败：%s',z.messages);
    noiseFactor(:,sample)=z.residual-base.residual;
    fprintf('TC27-UQ输入白噪声传播 %d/%d。\n',sample,count);
end
% 零均值输入噪声：去除有限样本均值，不把随机抽样误差当系统偏置。
noiseAudit=NaN; % 无历程时该MC稳定性指标不适用，不能伪记为零误差。
if count>0
    noiseFactor=noiseFactor-mean(noiseFactor,2);
    half=floor(count/2);halfVariance=var(noiseFactor(:,1:half),0,2);fullVariance=var(noiseFactor,0,2);
    noiseAudit=norm(halfVariance-fullVariance)/max(norm(fullVariance),eps);
    noiseFactor=noiseFactor/sqrt(count-1);
end
% 每段输入白噪声独立：显式分块，消除有限MC样本伪造的跨历程协方差。
historyNoiseFactor=zeros(n,count*numel(c.histories));offset=9*np;
for h=1:numel(c.histories)
    number=9*height(c.histories(h).data);rows=offset+(1:number);
    historyNoiseFactor(rows,(h-1)*count+(1:count))=noiseFactor(rows,:);
    offset=offset+number;
end
mu=c.nuisance.mean;sd=sqrt(c.nuisance.variance);anchors=[zeros(c.parameterCount,1),c.thetaHat];
if strcmp(c.options.nuisanceAnchorMode,'reference'),anchors=c.thetaHat;end
anchorCount=size(anchors,2);G=zeros(n,numel(mu),anchorCount);shift=zeros(n,anchorCount);
for anchor=1:anchorCount
    zero=evaluate(anchors(:,anchor));center=evaluate(anchors(:,anchor),mu);
    assert(zero.valid&&center.valid,'附加参数中心不可回放。');shift(:,anchor)=center.residual-zero.residual;
    for j=1:numel(mu)
        delta=max(sd(j)*.25,1e-6);delta=min(delta,.25*(c.nuisance.upper(j)-mu(j)));
        if delta<1e-9,delta=-min(sd(j)*.25,.25*(mu(j)-c.nuisance.lower(j)));end
        u=mu;u(j)=u(j)+delta;z=evaluate(anchors(:,anchor),u);
        assert(z.valid,'附加参数h%d扰动失败：%s',c.nuisance.c_index(j),z.messages);
        G(:,j,anchor)=(z.residual-center.residual)/delta;
    end
    fprintf('TC27-UQ附加参数线性化锚点%d/%d完成。\n',anchor,anchorCount);
end
factor=[biasFactor,pointNoiseFactor,historyNoiseFactor,initialSensorFactor];
nuisanceFactorColumns=size(factor,2)+(1:anchorCount*numel(mu));
for anchor=1:anchorCount
    factor=[factor,(G(:,:,anchor).*sd.')/sqrt(anchorCount)]; %#ok<AGROW>
end
pointError=struct('source','legacy_R007_no_model_discrepancy');
baseBlocks=struct('rows',{},'cholLower',{});
historyError=struct('enabled',false);
if tc24Engineering
    pointError=sht_tc27_uq_point_error(c);
    if strcmp(c.options.historyDiscrepancy,'correlated_engineering')&&~isempty(c.histories)
        [variance,F,baseBlocks,historyError]=sht_tc27_uq_history_discrepancy(c,pointError,variance,spec);
    else
        F=zeros(n,9*np);F(1:9*np,:)=pointError.factor;
    end
    factor=[factor,F];
    fprintf('TC27-UQ稳态点误差使用%s路线的工程合同，模型差异不除以sqrt(N)。\n',c.route);
end
% R = B + FF'，B由独立通道的时相关小块与对角项组成；不构造全历程方阵。
base=struct('variance',variance,'baseBlocks',baseBlocks);
normalizedFactor=sht_tc27_uq_base_transform(base,factor,false);
[U,S,~]=svd(normalizedFactor,'econ');s=diag(S);keep=s>1e-10;U=U(:,keep);s=s(keep);
baseLogDet=sum(log(variance));
for k=1:numel(baseBlocks)
    b=baseBlocks(k);baseLogDet=baseLogDet-sum(log(variance(b.rows)))+2*sum(log(diag(b.cholLower)));
end
model=struct('variance',variance,'factor',factor,'U',U,'shrink',1-1./sqrt(1+s.^2), ...
    'nuisanceFactorColumns',nuisanceFactorColumns, ...
    'baseBlocks',baseBlocks,'historyError',historyError, ...
    'nuisanceAnchorMode',c.options.nuisanceAnchorMode, ...
    'logDet',baseLogDet+sum(log1p(s.^2)),'shift',mean(shift,2), ...
    'nuisanceJacobian',mean(G,3),'nuisanceAnchorJacobian',G,'nuisanceMean',mu, ...
    'nuisanceVariance',sd.^2,'biasLabels',biasLabels,'inputNoiseHalfVsFullRelative',noiseAudit, ...
    'runtime_s',toc(timer),'measurementSamples',count,'actualSteadySampleCount',c.sampleCount, ...
    'inputNoiseModel','independent_point_linear_and_history_MC_blocks', ...
    'pointNoiseFactor',pointNoiseFactor,'historyNoiseFactor',historyNoiseFactor, ...
    'publicIndependentErrorPrior',true,'flowDriftPropagated',false,'modelDiscrepancyCalibrated',false, ...
    'pointError',pointError,'meterInputOutputCrossCovariance',tc24Engineering);
save(file,'model','-v7.3');
end

function t=perturb(t,name,delta,means,meterCoupled)
suffix='';if means,suffix='_mean';end
if strcmp(name,'Wa2'),name='Wa1';end
% 同一Pt1/Tt1误差既改变DLL输入，也改变间接Wa1测量，不能当作独立来源。
if meterCoupled&&ismember(name,{'Pt1','Tt1'})
    meter=table(t.(['Wa1',suffix]),t.(['Pt1',suffix]),t.(['Tt1',suffix]), ...
        'VariableNames',{'Wa1_mean','Pt1_mean','Tt1_mean'});
    derivative=sht_tc24_meter_input_sensitivity(meter,name);
    t.(['Wa1',suffix])=t.(['Wa1',suffix])+derivative.*delta;
end
field=[name,suffix];t.(field)=t.(field)+delta;
end
