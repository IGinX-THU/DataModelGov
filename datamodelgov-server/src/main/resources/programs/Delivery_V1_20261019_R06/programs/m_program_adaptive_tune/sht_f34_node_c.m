function varargout=sht_f34_node_c(action,varargin)
%SHT_F34_NODE_C 节点C的联合跨架次传播及物理节点报告。
% 推断主体仍是sht_f34_method_c；本函数不另建求解框架，不读取真值拟合。
switch lower(action)
    case 'propagate'
        varargout{1}=local_propagate(varargin{:});
    case 'qsensitivity'
        varargout{1}=local_q(varargin{:});
    case 'report'
        varargout{1}=local_report(varargin{:});
    otherwise
        error('SHT:F34NodeC:Action','未知动作。');
end
end

function out=local_propagate(prior,C,n,seed,multiplier)
% 完整联合核：[新显式节点;新条件节点]=[旧粒子;旧条件高斯]+N(0,Q)。
% 按共同显式物理边界作整体拒绝，不逐坐标裁剪、不先固定父粒子后截断。
% 因此被接受的父粒子频率也包含其越界概率，恰好对应联合混合条件化。
d=size(C.samples,1);k=size(C.conditionalShapeMean,1);
Q=multiplier*prior.nodePrior.jointNextFlightCovariance;
Qee=Q(1:d,1:d);s=sqrt(diag(Qee));
R=chol(Qee./(s*s.'),'lower');B=Q(d+1:end,1:d)/Qee;
S=Q(d+1:end,d+1:end)-B*Q(1:d,d+1:end);
S=(S+S.')/2;
w=C.weights(:)/sum(C.weights);cdf=cumsum(w);cdf(end)=1;
stream=RandStream('mt19937ar','Seed',seed);
theta=zeros(d,n);z=zeros(k,n);meanZ=zeros(k,n);parent=zeros(1,n);
count=0;attempts=0;maximum=max(10000,100*n);
rootCache=cell(size(C.samples,2),1);
bounded=isfield(C,'physicalSupport');
while count<n&&attempts<maximum
    attempts=attempts+1;index=find(cdf>=rand(stream),1);
    delta=s.*(R*randn(stream,d,1));candidate=C.samples(:,index)+delta;
    if any(candidate<prior.lowerBound(:)|candidate>prior.upperBound(:)),continue;end
    nextMean=C.conditionalShapeMean(:,index)+B*delta;
    if isempty(rootCache{index})
    if bounded,V=S;else,V=C.conditionalShapeCovariance(:,:,index)+S;end
    V=(V+V.')/2;
    % 半正定方向允许严格为零，不用固定绝对脊项扩大物理不确定性。
    [E,L]=eig(V);v=diag(L);
    assert(min(v)>-1e-12*max(1,max(abs(v))),'条件传播协方差非半正定。');
    rootCache{index}=E.*sqrt(max(v,0)).';
    end
    if bounded
        box=sht_f34_bounded_condition('evaluate',C.conditionalGaussianMean(:,index), ...
            C.conditionalGaussianCovariance(:,:,index),C.physicalSupport, ...
            C.conditionalQuadratureCount,C.conditionalQuadratureSeed,stream);
        nextZ=box.draw+B*delta+rootCache{index}*randn(stream,k,1);
        b=C.physicalSupport;
        if any(nextZ(b.index)<b.lower | nextZ(b.index)>b.upper),continue;end
    else,nextZ=nextMean+rootCache{index}*randn(stream,k,1);end
    count=count+1;theta(:,count)=candidate;parent(count)=index;
    meanZ(:,count)=nextMean;z(:,count)=nextZ;
end
assert(count==n,'跨架次联合拒绝采样未获得足够样本，不能裁剪替代。');
out=struct('theta',theta,'z',z,'conditionalMean',meanZ,'parentIndex',parent, ...
    'attemptCount',attempts,'acceptance',n/attempts, ...
    'target','posterior_joint_gaussian_transition_conditioned_on_explicit_box');
if bounded,out.target='bounded_parent_plus_joint_transition_conditioned_on_physical_box';end
end

function result=local_q(p,C)
% 仅参数域的轻量蒙特卡洛，不调用DLL。联合边界存在时不能用逐维截断
% 正态公式冒充联合传播的边缘分布；相同种子便于比较0.5/1/2倍Q。
t=p.prior.parameterTable;result=table();d=height(t);
for factor=p.options.processCovarianceSensitivityMultiplier(:).'
    sample=local_propagate(p.prior,C,4096,C.seed+9300,factor);
    for j=1:d
        x=sort(sample.theta(j,:));n=numel(x);
        lo=x(max(1,ceil(.025*n)));hi=x(ceil(.975*n));
        width=C.interval95(j,2)-C.interval95(j,1);
        row=table(string(t.parameter_id(j)),string(t.unit(j)),factor, ...
            C.interval95(j,1),C.interval95(j,2),width,mean(x),std(x,1), ...
            lo,hi,hi-lo,(hi-lo)/max(width,eps),false, ...
            "engineering_Q_joint_bounded_MC4096", ...
            'VariableNames',{'parameter_id','unit','q_covariance_multiplier', ...
            'current_q025','current_q975','current_interval_width','next_mean', ...
            'next_std','next_q025','next_q975','next_interval_width', ...
            'next_to_current_width_ratio','q_calibrated','q_basis'});
        result=[result;row]; %#ok<AGROW>
    end
end
end

function out=local_report(p,L,D,C,pred,delivery,reportOptions)
% 所有图使用实际K或kg/s，不把节点增量误叫物理修正系数。
tab=C.summary;d=height(tab);dict=p.prior.parameterTable;
map=p.prior.shape.nodeMap;selected=p.prior.nodePrior.selectedPhysicalIndices;
base=zeros(d,1);coordinate=zeros(d,1);node=zeros(d,1);group=strings(d,1);
for j=1:d
    if selected(j)<=height(map)
        m=selected(j);base(j)=map.reference_value(m);coordinate(j)=map.coordinate(m);
        node(j)=map.node_index(m);
        if string(map.kind(m))=="fuel_bias",group(j)="Wf_bias";
        else,group(j)="h"+string(map.c_index(m));end
    else
        group(j)="K_dist_eq";node(j)=1;coordinate(j)=NaN;
    end
end
tab.group=group;tab.node_index=node;tab.coordinate=coordinate;tab.reference=base;
tab.posterior_mean=base+C.mean;tab.q025=base+C.interval95(:,1);tab.q975=base+C.interval95(:,2);
tab.deterministic=base+p.context.uqReferenceResult.estimatedTheta(:);
tab.d_mean=base+D.map;tab.d_q025=base+D.interval95(:,1);tab.d_q975=base+D.interval95(:,2);
tab.truth_train=nan(d,1);tab.truth_test=nan(d,1);
% 可选、冻结后的合成真值核查。没有该报告文件时仍可生成正式交付和图。
truthFile='';
if nargin>=7&&isfield(reportOptions,'truthComparisonFile'),truthFile=reportOptions.truthComparisonFile;end
if isfile(truthFile)
    truth=readtable(truthFile);truth=truth(string(truth.tag)=="R026_N_L050",:);
    for j=1:d
        r=find(string(truth.parameter)==group(j)&truth.node==node(j));
        if numel(r)==1&&abs(truth.prior(r)-base(j))<1e-10&& ...
                abs(truth.estimate(r)-tab.deterministic(j))<1e-10
            tab.truth_train(j)=truth.truth_train(r);tab.truth_test(j)=truth.truth_test(r);
        end
    end
end
tab.deterministic_error=tab.deterministic-tab.truth_train;
tab.d_error=tab.d_mean-tab.truth_train;tab.c_error=tab.posterior_mean-tab.truth_train;
tab.truth_in_C=tab.truth_train>=tab.q025&tab.truth_train<=tab.q975;
tab.truth_in_D=tab.truth_train>=tab.d_q025&tab.truth_train<=tab.d_q975;
folder=p.paths.reportDir;writetable(tab,fullfile(folder,'C_all_actual_node_parameters.csv'));
groups=unique(group,'stable');summary=table();
for j=1:numel(groups)
    r=group==groups(j);x=tab(r,:);
    summary=[summary;table(groups(j),string(x.unit(1)),height(x), ...
        sqrt(mean(x.deterministic_error.^2)),sqrt(mean(x.d_error.^2)), ...
        sqrt(mean(x.c_error.^2)),mean(x.q975-x.q025),nnz(x.truth_in_C), ...
        'VariableNames',{'parameter','unit','node_count','det_rmse','D_rmse','C_rmse', ...
        'mean_C_interval_width','truth_covered'})]; %#ok<AGROW>
end
writetable(summary,fullfile(folder,'C_parameter_recovery_summary.csv'));
for mode=1:3
    fig=figure('Visible','off','Color','w','Position',[50,50,1440,1000]);
    for j=1:numel(groups)
        subplot(3,3,j);x=tab(group==groups(j),:);a=x.coordinate;
        if groups(j)=="K_dist_eq",a=1;end
        scale=1;if groups(j)=="Wf_bias",a=a*p.context.priorSchedule.fuelBias.wfDesign;end
        hold on;grid on;handles=gobjects(0);labels={};
        if mode~=2
            h=errorbar(a,x.posterior_mean*scale,(x.posterior_mean-x.q025)*scale, ...
                (x.q975-x.posterior_mean)*scale,'bo-','LineWidth',1.3);
            handles(end+1)=h;labels{end+1}='C weighted 95%'; %#ok<AGROW>
        end
        if mode~=1
            h=errorbar(a,x.d_mean*scale,(x.d_mean-x.d_q025)*scale, ...
                (x.d_q975-x.d_mean)*scale,'s--','Color',[.15,.6,.25],'LineWidth',1.2);
            handles(end+1)=h;labels{end+1}='D local 95%'; %#ok<AGROW>
        end
        if any(isfinite(x.truth_train))
            h=plot(a,x.truth_train*scale,'rx-','LineWidth',1.4,'MarkerSize',7);
            handles(end+1)=h;labels{end+1}='Synthetic training truth';
        end
        h=plot(a,x.deterministic*scale,':d','Color',[.55,.2,.65],'LineWidth',1.1);
        handles(end+1)=h;labels{end+1}='Deterministic nodes';
        plot(a,x.reference*scale,':','Color',[.5,.5,.5]);
        title(char(groups(j)),'Interpreter','none');ylabel(char(x.unit(1)));
        xlabel(char(dict.axis_name(find(group==groups(j),1))),'Interpreter','none');
        if groups(j)=="Wf_bias",xlabel('Measured fuel flow / kg/s');end
        if groups(j)=="K_dist_eq",xlabel('Sortie parameter');xlim([.7,1.3]);end
        if j==1,legend(handles,labels,'Location','best','FontSize',8);end
    end
    files={'C_actual_parameter_intervals.png','D_actual_parameter_intervals.png','C_D_actual_parameter_intervals.png'};
    print(fig,fullfile(folder,files{mode}),'-dpng','-r150');close(fig);
end
out=struct('allParameters',tab,'groups',summary,'truthUsedForInference',false, ...
    'truthAvailable',all(isfinite(tab.truth_train)), ...
    'likelihoodContractHash',L.contractHash,'workbook',delivery.workbookFile);
save(fullfile(p.paths.runDir,'node_c_report.mat'),'out');
disp(summary);if ~isempty(pred),disp(pred.summary);end
end
