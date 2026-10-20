function diagnostic=Start_TC27_10_ApproximationDiagnostics(directory)
%START_TC27_10_APPROXIMATIONDIAGNOSTICS 区分主参数采样与附加参数近似问题。
% 仅分析冻结后的联合样本与公开误差模型，不读取隐藏真值、不调用DLL。
if nargin<1,c=sht_tc27_uq_contract(sht_tc27_uq_c_options());directory=c.directory;end
a=load(fullfile(directory,'contract.mat'),'c');c=a.c;
a=load(fullfile(directory,'covariance.mat'),'model');model=a.model;
V=diag(model.nuisanceVariance);Gw=sht_tc27_uq_whiten(model,model.nuisanceJacobian,false);
Vc=V-V*(Gw.'*Gw)*V;Vc=(Vc+Vc.')/2;sd=sqrt(max(diag(Vc),realmin));
nuisanceTable=table();weightTable=table();
for method={'C','D'}
    name=method{1};file=fullfile(directory,['method_',name,'.mat']);if ~isfile(file),continue;end
    a=load(file);p=a.(name);
    if name=='D'
        w=p.formal.weights(:);r=p.finalExact.residual+p.physicalJacobian*(p.formal.theta-p.map);
    else,w=p.weights(:);r=sht_tc27_uq_whiten(model,p.exactResidual);end
    w=w/sum(w);mu=c.nuisance.mean-V*(Gw.'*r);average=mu*w;
    marginalStd=sqrt(max(diag(Vc)+((mu-average).^2)*w,0));
    outside=.5*erfc(-(c.nuisance.lower-mu)./sd/sqrt(2))+ ...
        .5*erfc((c.nuisance.upper-mu)./sd/sqrt(2));
    conditionalSd=sd;logLikelihood=-.5*sum(r.^2,1).';
    if name=='C'&&isfield(p,'nuisanceDraws')
        copies=size(p.nuisanceDraws,2);mu=reshape(p.nuisanceDraws,24,[]);
        jointWeights=repelem(w/copies,copies);average=mu*jointWeights;
        marginalStd=sqrt(((mu-average).^2)*jointWeights);
        conditionalSd=sqrt(reshape(var(p.nuisanceDraws,0,2),24,[])*w);
        outside=zeros(24,numel(w));
        logLikelihood=p.boundedNuisance.logLikelihood(:);
    end
    t=c.nuisance;t.method=repmat(string(name),height(t),1);
    t.conditional_mean_average=average;t.conditional_std=conditionalSd;t.marginal_std=marginalStd;
    t.minimum_conditional_mean=min(mu,[],2);t.maximum_conditional_mean=max(mu,[],2);
    t.outside_physical_support_probability=outside*w;
    nuisanceTable=[nuisanceTable;t]; %#ok<AGROW>
    if name=='C'
        weightTable=table((1:numel(w)).',w,logLikelihood,p.deltaLogLikelihood(:), ...
            'VariableNames',{'sample_id','weight','exact_log_likelihood_without_constant','exact_minus_surrogate_log_likelihood'});
        if isfield(p,'surrogateUsed')&&~p.surrogateUsed
            % 没有代理时差值不适用，不能填0冒充代理完全准确。
            weightTable.exact_minus_surrogate_log_likelihood=[];
        end
        weightTable=sortrows(weightTable,'weight','descend');
    end
end
rankTable=table();offset=9*height(c.trainingData);count=model.measurementSamples;
for h=1:numel(c.histories)
    number=9*height(c.histories(h).data);rows=offset+(1:number);columns=(h-1)*count+(1:count);
    F=model.historyNoiseFactor(rows,columns);s=svd(F,'econ');
    estimatedRank=nnz(s>max(size(F))*eps(max(s)));
    rankTable=[rankTable;table(string(c.histories(h).id),number,count,estimatedRank, ...
        'VariableNames',{'history','observation_count','input_error_realizations','sample_covariance_rank'})]; %#ok<AGROW>
    offset=offset+number;
end
writetable(nuisanceTable,fullfile(c.report,'C_D_nuisance_physical_support_diagnostic.csv'));
if width(weightTable)>0,writetable(weightTable,fullfile(c.report,'C_exact_weight_diagnostic.csv'));end
if width(rankTable)>0,writetable(rankTable,fullfile(c.report,'history_input_covariance_rank_diagnostic.csv'));end
diagnostic=struct('nuisance',nuisanceTable,'Cweights',weightTable,'inputCovarianceRank',rankTable, ...
    'contractHash',c.contractHash,'truthRead',false,'dllCalled',false);
save(fullfile(directory,'approximation_diagnostic.mat'),'diagnostic','-v7.3');
end
