function report=Start_TC27_10_UncertaintyPrediction(directory,executionOptions)
%START_TC27_10_UNCERTAINTYPREDICTION 推断冻结后两套稳态/全部小幅测试预测。
% C保留全部带权主参数样本精确回放，D采用局部样本线性传播。
% 附加参数条件矩由同一C似然推导，预测侧一阶传播，保留近似身份。
if nargin<1,c=sht_tc27_uq_contract(sht_tc27_uq_c_options());directory=c.directory;end
if nargin<2,executionOptions=struct();end
timer=tic;a=load(fullfile(directory,'contract.mat'),'c');c=a.c;
a=load(fullfile(directory,'covariance.mat'),'model');covariance=a.model;
a=load(fullfile(directory,'method_D.mat'),'D');D=a.D;
methods={'D'};if isfile(fullfile(directory,'method_C.mat')),methods={'D','C'};end
% C/D均按冻结的推断合同推进历程。稳态模型不使用此积分步长。
predictionStep_s=c.options.integrationStep_s;
p=sht_tc27_paths(c.options);a=load(c.inputContract.preparedFile,'result');prepared=a.result;
sht_tc27_uq_check_prepared_data(c.options,prepared,'test');
testBlocks=struct('data',{},'kind',{},'label',{},'history',{});
for source=1:numel(c.testSets)
    item=c.testSets(source);
    if ~isempty(item.means)&&height(item.means)>0
        testBlocks(end+1)=struct('data',item.means,'kind','points', ...
            'label',char(string(item.name)),'history',[]); %#ok<AGROW>
    end
    if c.options.predictionHistoriesEnabled
        for h=1:numel(item.small)
            testBlocks(end+1)=struct('data',item.small(h).data,'kind','history', ...
                'label',sprintf('%s_%s',char(string(item.name)),char(string(item.small(h).id))), ...
                'history',item.small(h)); %#ok<AGROW>
        end
    end
end
[cfg,execution]=sht_tc27_uq_runtime(c,executionOptions);
engine=sht_engine_open(cfg.engine);cleanup=onCleanup(@()sht_engine_close(engine));
report=struct('contractHash',c.contractHash,'predictionRoute','steady_for_all_operating_points', ...
    'posteriorFixedBeforeTruthAndTest',true,'conditionalOnMeasuredInputs',true,'transientHealthFixedZero',true);
report.historyIntegrationStep_s=predictionStep_s;
report.executionIdentity=execution;
report.sourceContractUnchanged=true;
% 正式试车数据没有健康参数真值，不能读取历史合成造数标签。
truth=nan(height(c.parameterTable),1);metrics=table();
G=covariance.nuisanceJacobian;V=diag(covariance.nuisanceVariance);
nuReference=c.nuisance.mean;
Gw=sht_tc27_uq_whiten(covariance,G,false);
conditionalCov=V-V*(Gw.'*Gw)*V;conditionalCov=(conditionalCov+conditionalCov.')/2;
[U,S]=eig(conditionalCov);
assert(min(diag(S))>=-1e-8*max(diag(V)),'条件协方差存在非舍入级负特征值。');
conditionalFactor=U*diag(sqrt(max(diag(S),0)));
report.nuisanceConditionalCovariance=conditionalCov;
% 测试线性响应在同一个主参数参考点计算，两方法复用；不是训练或选参。
historyCount=nnz(strcmp({testBlocks.kind},'history'));
report.predictionHistoryCount=historyCount;
for block=0:numel(testBlocks)
    if block>0
    item=testBlocks(block);data=item.data;kind=item.kind;label=item.label;
    currentHistory=item.history;
    testIdentity=sht_tc27_uq_hash(struct('data',data,'kind',kind,'contract',c.contractHash, ...
        'integrationStep_s',predictionStep_s,'execution',execution,'historyPlan',currentHistory, ...
        'intervalCode',sht_tc27_file_identity(fullfile(p.root,'sht_tc27_uq_mixture_interval.m')), ...
        'validityCode',sht_tc27_file_identity(fullfile(p.root,'sht_tc27_uq_prediction_validity.m')), ...
        'code',sht_tc27_file_identity([mfilename('fullpath'),'.m'])));
    suffix=testIdentity(1:12);
    file=fullfile(directory,['prediction_linear_',label,'_',suffix,'.mat']);
    if isfile(file),a=load(file,'linear');linear=a.linear;
    else
        base=predict(D.map,nuReference,data,kind);assert(all(base.valid),'预测基准失败%s。',label);
        y=base.prediction{:,c.historyNames};J=zeros(numel(y),c.parameterCount);Gn=zeros(numel(y),24);
        if strcmp(kind,'history'),bounds=base.coordinateBounds;fuelBounds=base.fuelCoordinateBounds;
        else
            bounds=base.coordinates(1:2,:);bounds{1,:}=min(base.coordinates{:,:},[],1);bounds{2,:}=max(base.coordinates{:,:},[],1);
            fuelBounds=[min(data.Wf_mean),max(data.Wf_mean)]/c.scheduleTemplate.fuelBias.wfDesign;
        end
        support=sht_tc27_schedule('support',c,bounds,fuelBounds);
        for j=1:c.parameterCount
            if ~support(j),continue;end
            delta=max(c.parameterTable.difference_step(j),1e-4*c.priorSigma(j));
            if D.map(j)+delta>c.upperBound(j),delta=-delta;end
            theta=D.map;theta(j)=theta(j)+delta;q=predict(theta,nuReference,data,kind,base);
            assert(all(q.valid),'测试Jacobian失败%s节点%d。',label,j);
            J(:,j)=(reshape(q.prediction{:,c.historyNames},[],1)-y(:))/delta;
        end
        for j=1:24
            u=nuReference;delta=.2*c.nuisance.sigma(j);
            if u(j)+delta>c.nuisance.upper(j),delta=-delta;end
            u(j)=u(j)+delta;q=predict(D.map,u,data,kind,base);assert(all(q.valid),'附加参数预测失败。');
            Gn(:,j)=(reshape(q.prediction{:,c.historyNames},[],1)-y(:))/delta;
        end
        deterministic=predict(c.thetaHat,zeros(24,1),data,kind,base);
        linear=struct('mean',y,'J',J,'Gn',Gn,'deterministic',deterministic.prediction,'base',base, ...
            'nuisanceReference',nuReference,'testIdentity',testIdentity);
        save(file,'linear','-v7.3');
    end
    end
    for k=1:numel(methods)
        method=methods{k};a=load(fullfile(directory,['method_',method,'.mat']));posterior=a.(method);
        if method=='D',theta=D.formal.theta;weight=D.formal.weights;
        else,theta=posterior.theta;weight=posterior.weights;end
        bounded=method=='C'&&isfield(posterior,'nuisanceDraws');
        % 与C边缘似然配套的附加参数条件均值，不直接使用造数真值。
        if method=='D',residual=D.finalExact.residual+D.physicalJacobian*(theta-D.map);
        else,residual=sht_tc27_uq_whiten(covariance,posterior.exactResidual);end
        nm=c.nuisance.mean-V*(Gw.'*residual);
        if bounded
            % 有界条件样本与各主参数样本成对，不能再使用越界高斯
            % 条件矩，也不能把重复主参数行计成额外独立后验信息。
            copies=size(posterior.nuisanceDraws,2);
            nm=reshape(posterior.nuisanceDraws,24,[]);
            theta=repelem(theta,1,copies);weight=repelem(weight/copies,1,copies);
            posterior.nuisanceSamples=nm;
        else
            posterior.nuisanceConditionalMean=nm;posterior.nuisanceConditionalCovariance=conditionalCov;
        end
        fullPosterior=posterior;fullPosterior.theta=theta;fullPosterior.weights=weight;
        if block==0
            summary=sht_steady_model_uq_sampler('summary',theta,weight,c);
            summary=sht_tc27_uq_empirical_summary(theta,weight,summary);summary.truth=truth;
            summary.truthCovered=truth>=summary.q025&truth<=summary.q975;
            writetable(summary,fullfile(c.report,['method_',method,'_parameter_intervals.csv']));
            if c.options.plot,local_parameter_plot(c,summary,method,posterior.quality);end
            delivery=sht_tc27_uq_delivery_path(c,method);
            sht_tc27_uq_delivery('write',delivery,c,fullPosterior);
            check=sht_tc27_uq_delivery('read',delivery);assert(max(abs(check.theta(:)-theta(:)))<1e-10);
            report.(method)=struct('summary',summary,'delivery',delivery,'quality',posterior.quality);
        end
        if block==0,continue;end
        % 已完成缓存和中间断点都绑定实际联合样本、权重及局部响应，
        % 同一合同下重新采样不能误读上一组样本的预测结果。
        sampleIdentity=sht_tc27_uq_hash(struct('theta',theta,'conditionalMean',nm, ...
            'weights',weight,'testIdentity',testIdentity,'linear',linear, ...
            'conditionalCovariance',conditionalCov,'bounded',bounded,'method',method));
        predictionFile=fullfile(directory,['prediction_',method,'_',label,'_',suffix, ...
            '_',sampleIdentity(1:12),'.mat']);
        if isfile(predictionFile),a=load(predictionFile,'prediction');prediction=a.prediction;
            assert(isfield(prediction,'sampleIdentity')&&strcmp(prediction.sampleIdentity,sampleIdentity), ...
                'TC27:UQ:PredictionIdentity','已完成预测缓存与本次联合后验样本不一致。');
        else
            tt=theta;nu=nm;number=size(theta,2);
            values=nan(numel(linear.mean),number);valid=true(1,number);
            failureMessages=strings(1,number);
            firstSample=1;partialFile=[predictionFile,'.partial.mat'];
            if method=='C'&&isfile(partialFile)
                partial=load(partialFile,'checkpoint');partial=partial.checkpoint;
                assert(strcmp(partial.sampleIdentity,sampleIdentity),'预测断点的联合样本或权重已改变。');
                values=partial.values;valid=partial.valid;firstSample=partial.completedSample+1;
                failureMessages=partial.failureMessages;
            end
            for sample=firstSample:number
                if method=='D',values(:,sample)=linear.mean(:)+linear.J*(tt(:,sample)-D.map);
                else
                    previous=find(all(tt(:,1:sample-1)==tt(:,sample),1),1);
                    if ~isempty(previous)
                        values(:,sample)=values(:,previous);valid(sample)=valid(previous);
                        failureMessages(sample)=failureMessages(previous);
                    else
                        q=predict(tt(:,sample),nuReference,data,kind,linear.base);valid(sample)=all(q.valid);
                        % 保留其他测试工况的有效行；无解行由回放器保存NaN。
                        values(:,sample)=reshape(q.prediction{:,c.historyNames},[],1);
                        failureMessages(sample)=strjoin(unique(q.messages(~q.valid)),'; ');
                    end
                end
                if method=='C'&&(mod(sample,32)==0||sample==number)
                    % 暂存尚未叠加附加参数条件均值的主参数响应，续算后只加一次。
                    checkpoint=struct('sampleIdentity',sampleIdentity,'values',values, ...
                        'valid',valid,'failureMessages',failureMessages,'completedSample',sample);
                    save(partialFile,'checkpoint','-v7.3');
                    fprintf('TC27-C测试预测 %s：%d/%d个联合样本。\n',label,sample,number);
                end
            end
            values=values+linear.Gn*(nu-nuReference);
            valid=valid&all(isfinite(values),1);
            prediction=struct('samples',values,'valid',valid,'validFraction',mean(valid), ...
                'failureMessages',failureMessages, ...
                'weights',weight(:),'validPosteriorWeight',sum(weight(valid)), ...
                'conditionalVariance',sum((linear.Gn*conditionalFactor).^2,2), ...
                'mainResponse','exact_DLL','nuisanceResponse','local_linear_conditional', ...
                'inputUncertaintyPropagatedAtPrediction',false,'sampleIdentity',sampleIdentity);
            if bounded
                prediction.conditionalVariance=zeros(size(values,1),1);
                prediction.nuisanceResponse='bounded_conditional_joint_samples_local_affine_response';
                prediction.mainParameterSampleCount=size(posterior.theta,2);
                prediction.conditionalDrawsPerMainSample=copies;
            end
            ns=sqrt(max(diag(conditionalCov),realmin));
            outside=.5*erfc(-(c.nuisance.lower-nu)./ns/sqrt(2))+ ...
                .5*erfc((c.nuisance.upper-nu)./ns/sqrt(2));
            % 不假设附加参数彼此独立：以最大边际概率和并集界报告范围。
            prediction.nuisanceOutsideBoundsProbabilityBounds= ...
                [max(outside,[],1)*weight(:),min(1,sum(outside,1))*weight(:)];
            if bounded
                assert(all(nu>=c.nuisance.lower & nu<=c.nuisance.upper,'all'),'C预测附加参数越界。');
                prediction.nuisanceOutsideBoundsProbabilityBounds=[0,0];
            end
            if method=='D'
                prediction.mainResponse='local_linear';
                prediction.physicalValidityCheckedForAllSamples=false;
                % 固定索引抽查局部预测，不按测试结果挑选参数或调整后验。
                indices=unique(round(linspace(1,number,4)));checks=table();passedChecks=0;
                for selectedIndex=indices
                    q=predict(tt(:,selectedIndex),nuReference,data,kind,linear.base);
                    if all(q.valid)
                        passedChecks=passedChecks+1;
                        expected=linear.mean(:)+linear.J*(tt(:,selectedIndex)-D.map);
                        difference=reshape(q.prediction{:,c.historyNames},[],1)-expected;
                        difference=reshape(difference,size(linear.mean));
                        for channelIndex=1:9
                            v=difference(:,channelIndex);
                            checks=[checks;table(selectedIndex,string(c.historyNames{channelIndex}), ...
                                sqrt(mean(v.^2)),max(abs(v)),'VariableNames', ...
                                {'sample_id','output','linearization_RMSE','linearization_maximum'})]; %#ok<AGROW>
                        end
                    else
                        warning('TC27:UQ:PredictionSpotCheck','%s的D抽查样本%d物理求解无效。',label,selectedIndex);
                    end
                end
                prediction.exactSpotChecks=checks;
                prediction.exactSpotCheckValidCount=passedChecks;
                prediction.exactSpotCheckAttemptCount=numel(indices);
                writetable(checks,fullfile(c.report,['D_',label,'_linearization_checks.csv']));
            end
            save(predictionFile,'prediction','-v7.3');
        end
        shape=size(linear.mean);values=prediction.samples;validWeights=prediction.weights;
        [avg,lo,hi,validMass]=sht_tc27_uq_mixture_interval(values,prediction.conditionalVariance,validWeights);
        if any(validMass<1-1e-10)
            warning('TC27:UQ:PointwisePrediction','%s/%s部分工况仅有物理条件区间，最小有效后验权重%.6f。', ...
                method,label,min(validMass));
        end
        lo=reshape(lo,shape);hi=reshape(hi,shape);avg=reshape(avg,shape);
        % 只加新的输出测量误差；不称包含全部输入/模型结构误差的预测区间。
        sp=sht_tc24_uq_measurement('sensors',c.historyNames);N=ones(shape(1),1);
        if strcmp(kind,'points'),N=data.sample_count;end
        sig=sqrt((sp.totalBiasHalfWidth.'/sqrt(3)).^2+sp.noiseStd.'.^2./N);
        [~,plo,phi]=sht_tc27_uq_mixture_interval(values,prediction.conditionalVariance+sig(:).^2,validWeights);
        plo=reshape(plo,shape);phi=reshape(phi,shape);
        avgTable=array2table(avg,'VariableNames',c.historyNames);
        metric=sht_tc27_output_metrics(avgTable,data,strcmp(kind,'points'),[method,'_',label]);
        metric.finitePredictionSampleFraction=repmat(prediction.validFraction,height(metric),1);
        massMatrix=reshape(validMass,shape);metric.minimumPointwisePosteriorWeight=min(massMatrix,[],1).';
        metric.nuisanceOutsideSupportProbabilityLowerBound=repmat( ...
            prediction.nuisanceOutsideBoundsProbabilityBounds(1),height(metric),1);
        metric.nuisanceOutsideSupportProbabilityUpperBound=repmat( ...
            prediction.nuisanceOutsideBoundsProbabilityBounds(2),height(metric),1);
        metrics=[metrics;metric]; %#ok<AGROW>
        if c.options.plot,local_output_plot(c,data,linear.deterministic,avg,lo,hi,plo,phi,kind,[method,'_',label],posterior.quality);end
        rows=local_output_table(c,data,linear.deterministic,avg,lo,hi,plo,phi,kind);
        rows.validPosteriorWeight=validMass;
        rows.resultQuality=repmat(string(posterior.quality),height(rows),1);
        writetable(rows,fullfile(c.report,[method,'_',label,'_prediction_intervals.csv']));
        fprintf('TC27-UQ %s/%s有限预测样本：%d/%d；主参数响应=%s。\n', ...
            method,label,nnz(prediction.valid),numel(prediction.valid),prediction.mainResponse);
        if method=='D',fprintf('  D主参数DLL抽查有效%d/%d，不表示全部局部样本已物理回放。\n', ...
                prediction.exactSpotCheckValidCount,prediction.exactSpotCheckAttemptCount);end
        fprintf('  有效预测后验权重%.6f；附加参数高斯条件近似越界概率界[%.1f%%, %.1f%%]。\n', ...
            prediction.validPosteriorWeight,100*prediction.nuisanceOutsideBoundsProbabilityBounds);
    end
end
report.metrics=metrics;report.runtime_s=toc(timer);
if ~isempty(metrics)&&width(metrics)>0
    writetable(metrics,fullfile(c.report,'prediction_metrics.csv'));
end
if c.options.plot&&isfield(report,'C')&&isfield(report,'D')
    local_compare_parameter_plot(c,report.C.summary,report.D.summary,report.C.quality,report.D.quality);
end
save(fullfile(directory,'prediction_report.mat'),'report','-v7.3');disp(metrics);

    function q=predict(theta,nu,data,kind,initial)
        if nargin<5,initial=[];end
        s=sht_steady_model_adapt_v2_common('m3nodestoschedule',c,theta);s.designHealth(c.nuisance.c_index+1)=nu;
        opts=struct('route','steady','independentPrediction',true,'integrationStep_s',predictionStep_s);
        if strcmp(kind,'points')
            if ~isempty(initial)
                opts.initialStates=initial.states;opts.commonWorkingSeed=initial.commonWorkingSeed;
            end
            fuel=s.fuelBias;copy=data;x=min(max(data.Wf_mean/fuel.wfDesign,min(fuel.xNodes)),max(fuel.xNodes));
            if numel(fuel.xNodes)==1,bias=repmat(fuel.biasNodes,height(data),1);else,bias=interp1(fuel.xNodes,fuel.biasNodes,x,'linear');end
            copy.Wf_mean=copy.Wf_mean-bias;[copy,~]=sht_np_branch_delivery('query',c.npBranchModel,copy,1);
            f=copy.Properties.VariableNames(startsWith(copy.Properties.VariableNames,'Np_branch_'));
            for fieldIndex=1:numel(f),data.(f{fieldIndex})=copy.(f{fieldIndex});end
        end
        try
            if strcmp(kind,'history')
                h=currentHistory;
                out=sht_tc27_replay_histories(cfg,engine,h,s,opts);q=out{1};
            else
                q=sht_tc27_replay(kind,cfg,engine,data,s,opts);
            end
        catch failure
            % 仅把已命名的物理求解失败记成无效预测；程序错误仍向外抛出。
            expected={'TC27:Replay:InitialThermal','TC27:Replay:Fuel','TC27:Replay:ModelFailure'};
            if ~ismember(failure.identifier,expected),rethrow(failure);end
            q=struct('prediction',array2table(nan(height(data),9),'VariableNames',c.historyNames), ...
                'valid',false(height(data),1),'messages',repmat(string(failure.message),height(data),1));
        end
        q=sht_tc27_uq_prediction_validity(q,c.historyNames);
    end
end

function truth=local_truth(c,p)
t=c.parameterTable;truth=nan(height(t),1);
file=fullfile(p.legacyMiddle,'tc27_train_validation.mat');if ~isfile(file),return;end
a=load(file,'output');v=a.output;
for j=1:height(t)
    if t.c_index(j)<0
        wf=v.measurement.Wf;bias=interp1(v.simulation.time,v.validation.bias.Wf,v.measurement.Time_s,'linear');
        [x,order]=sort(wf/c.scheduleTemplate.fuelBias.wfDesign);[x,uniqueIndex]=unique(x);bias=bias(order);bias=bias(uniqueIndex);
        truth(j)=interp1(x,bias,min(max(t.coordinate(j),x(1)),x(end)),'linear');
    else
        q=v.profile.parameters([v.profile.parameters.cIndex]==t.c_index(j));
        if strcmp(q.mode,'constant'),truth(j)=q.designValue;else
            x=q.xNodes;truth(j)=q.designValue+interp1(x,q.deltaNodes,min(max(t.coordinate(j),x(1)),x(end)),'linear');end
    end
end
end
function local_parameter_plot(c,t,method,quality)
f=figure('Visible','off','Position',[50,50,1450,1000]);groups=unique(c.parameterTable.group_index).';
for j=1:numel(groups)
    q=find(c.parameterTable.group_index==groups(j));x=c.parameterTable.coordinate(q);
    subplot(4,3,j);h1=fill([x;flipud(x)],[t.q025(q);flipud(t.q975(q))],[.8,.87,.98],'EdgeColor','none');hold on;
    % 偏斜加权分布的均值可能位于等尾区间外，不能据均值构造负误差棒。
    if numel(x)==1,plot([x,x],[t.q025(q),t.q975(q)],'b-','LineWidth',1.5);end
    h2=plot(x,t.posterior_mean(q),'b.-');
    h3=plot(x,t.deterministic_estimate(q),'r--s','MarkerSize',4);
    h4=plot(x,t.truth(q),'k-d','MarkerSize',4,'MarkerFaceColor','k');
    title(c.parameterTable.base_name(q(1)),'Interpreter','none');xlabel(c.parameterTable.axis_name(q(1)),'Interpreter','none');ylabel(t.unit(q(1)));grid on;
end
lg=legend([h1,h2,h3,h4],{'95% pointwise interval','Posterior mean','Deterministic','Truth'}, ...
    'Orientation','horizontal','NumColumns',4);
set(lg,'Units','normalized','Position',[.12,.005,.76,.025]);
sgtitle([method,': ',quality],'Interpreter','none','FontSize',10);
print(f,fullfile(c.report,['method_',method,'_parameter_intervals.png']),'-dpng','-r150');close(f);
end
function local_compare_parameter_plot(c,ct,dt,cQuality,dQuality)
f=figure('Visible','off','Position',[50,50,1450,1050]);groups=unique(c.parameterTable.group_index).';
for j=1:numel(groups)
    q=find(c.parameterTable.group_index==groups(j));x=c.parameterTable.coordinate(q);
    subplot(4,3,j);hold on;
    h1=fill([x;flipud(x)],[ct.q025(q);flipud(ct.q975(q))],[.35,.60,.90],'FaceAlpha',.2,'EdgeColor','none');
    h2=fill([x;flipud(x)],[dt.q025(q);flipud(dt.q975(q))],[.30,.70,.43],'FaceAlpha',.2,'EdgeColor','none');
    % 常值参数先画区间，再画点；否则同一横坐标的竖线会遮住真值。
    if numel(x)==1
        plot([x,x],[ct.q025(q),ct.q975(q)],'b-','LineWidth',1.5);
        plot([x,x],[dt.q025(q),dt.q975(q)],'Color',[.10,.55,.25],'LineWidth',1.5);
    end
    h3=plot(x,ct.posterior_mean(q),'b.-');h4=plot(x,dt.posterior_mean(q),'Color',[.10,.55,.25],'Marker','s');
    h5=plot(x,ct.deterministic_estimate(q),'r--');h6=plot(x,ct.truth(q),'k.-');
    if numel(x)==1
        set(h3,'Marker','o','MarkerFaceColor','b');
        set(h5,'Marker','s','MarkerFaceColor','r');
        set(h6,'Marker','d','MarkerFaceColor','k');
    end
    title(c.parameterTable.base_name(q(1)),'Interpreter','none');
    xlabel(c.parameterTable.axis_name(q(1)),'Interpreter','none');ylabel(ct.unit(q(1)));grid on;
end
lg=legend([h1,h2,h3,h4,h5,h6],{'C 95% interval','D 95% interval','C mean','D mean','Deterministic','Truth'}, ...
    'Orientation','horizontal','NumColumns',6);
set(lg,'Units','normalized','Position',[.06,.005,.88,.03]);
sgtitle({['C: ',cQuality],['D: ',dQuality]}, ...
    'Interpreter','none','FontSize',10);
print(f,fullfile(c.report,'C_D_parameter_intervals.png'),'-dpng','-r150');close(f);
end
function t=local_output_table(c,data,det,avg,lo,hi,plo,phi,kind)
t=table();
for j=1:9
    name=c.historyNames{j};if strcmp(kind,'points'),x=(1:height(data)).';suffix='_mean';else,x=data.Time_s;suffix='';end
    if j==9,observed=data.(['Wa1',suffix])-data.(['Wb',suffix]);else,observed=data.([name,suffix]);end
    t=[t;table(repmat(string(name),numel(x),1),x,observed,det.(name),avg(:,j),lo(:,j),hi(:,j),plo(:,j),phi(:,j), ...
        'VariableNames',{'output','coordinate','measurement','deterministic','posterior_mean','model_q025','model_q975','remeasurement_q025','remeasurement_q975'})]; %#ok<AGROW>
end
end
function local_output_plot(c,data,det,avg,lo,hi,plo,phi,kind,label,quality)
f=figure('Visible','off','Position',[60,60,1400,1000]);t=local_output_table(c,data,det,avg,lo,hi,plo,phi,kind);
units={'r/min','r/min','Pa','K','Pa','K','Pa','K','kg/s'};
for j=1:9
    q=t(t.output==string(c.historyNames{j}),:);x=q.coordinate;subplot(3,3,j);
    fill([x;flipud(x)],[q.remeasurement_q025;flipud(q.remeasurement_q975)],[.91,.91,.91],'EdgeColor','none');hold on;
    fill([x;flipud(x)],[q.model_q025;flipud(q.model_q975)],[.77,.86,1],'EdgeColor','none');
    plot(x,q.measurement,'k.',x,q.deterministic,'r--',x,q.posterior_mean,'b-');
    title(c.historyNames{j});ylabel(units{j});grid on;if strcmp(kind,'points'),xlabel('Test point');else,xlabel('Time / s');end
end
lg=legend('New output measurement interval','Conditional model interval','Measurement','Deterministic','UQ mean', ...
    'Orientation','horizontal','NumColumns',3);
set(lg,'Units','normalized','Position',[.08,.005,.84,.045]);
sgtitle([label,': ',quality],'Interpreter','none','FontSize',10);
print(f,fullfile(c.report,[label,'_prediction_intervals.png']),'-dpng','-r145');close(f);
end
