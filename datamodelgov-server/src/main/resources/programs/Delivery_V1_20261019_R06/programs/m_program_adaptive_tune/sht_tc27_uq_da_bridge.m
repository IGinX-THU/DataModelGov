function r=sht_tc27_uq_da_bridge(c,initial,proxy,exact,geometry,o)
%SHT_TC27_UQ_DA_BRIDGE 从代理分布平滑过渡到精确目标的延迟接受SMC。
% pi_g = p * Ls^(a*(1-g)) * Le^g。pCN对先验潜空间标准正态可逆。
% 一级目标p*Ls^(a*(1-g)+g)，二级比为g*Delta(log Le-log Ls)。
% 随机旁路是同一目标的普通MH核，不是任意放宽二级接受条件。
rng(o.seed,'twister');theta=initial.theta;w=reshape(initial.weights,1,[]);w=w/sum(w);
n=size(theta,2);z=sht_steady_model_uq_sampler('thetatolatent',c.prior,theta);
ls=proxy(theta);e=exact(theta);le=e.logLikelihood;raw=e.residual;valid=e.valid;
assert(nnz(valid)>=max(16,.2*n),'桥接初始精确有效粒子不足。');
gamma=0;ancestor=1:n;rho=.5*ones(1,5);stages=struct([]);totalAttempt=0;totalScreen=0;totalAccept=0;
file=fullfile(c.directory,'C_surrogate_bridge_checkpoint.mat');
signature=struct('contract',c.contractHash,'options',o,'geometry',geometry, ...
    'initial',sht_tc27_uq_hash(initial),'code',sht_steady_model_uq_common('filehash',[mfilename('fullpath'),'.m']));
if isfile(file)
    saved=load(file,'checkpoint');cp=saved.checkpoint;
    assert(isequaln(cp.signature,signature),'桥接断点身份不匹配。');
    theta=cp.theta;z=cp.z;w=cp.w;ls=cp.ls;le=cp.le;raw=cp.raw;valid=cp.valid;
    gamma=cp.gamma;ancestor=cp.ancestor;rho=cp.rho;stages=cp.stages;
    totalAttempt=cp.totalAttempt;totalScreen=cp.totalScreen;totalAccept=cp.totalAccept;rng(cp.rngState);
end
a=o.power;
while gamma<1-1e-12
    index=numel(stages)+1;assert(index<=o.maximumStages,'TC27:Bridge:Budget','桥接尚未到精确目标，已保留断点，不能输出最终后验。');
    score=le-a*ls;next=nextTemperature(gamma,score,w);delta=next-gamma;
    w=normalize(log(max(w,realmin))+delta*score);ess=1/sum(w.^2);gamma=next;
    if gamma<1-1e-12
        q=resample(w);theta=theta(:,q);z=z(:,q);ls=ls(q);le=le(q);raw=raw(:,q);
        valid=valid(q);ancestor=ancestor(q);w=ones(1,n)/n;sweeps=o.moveSweeps;
    else,gamma=1;sweeps=o.finalSweeps;end
    attempts=zeros(1,5);screens=zeros(1,5);accepts=zeros(1,5);bypasses=0;esjd=0;
    for sweep=1:sweeps
        labels=mod(0:n-1,5)+1;labels=labels(randperm(n));proposal=z;
        for k=1:5
            q=labels==k;rows=geometry.blocks{k};b=geometry.basis{k};s=geometry.singular{k};
            proposal(rows,q)=sht_tc27_uq_spectral_pcn(z(rows,q),b,s,rho(k),1,.002,1.5,.95);
        end
        candidate=sht_steady_model_uq_sampler('latenttotheta',c.prior,proposal);
        newLs=proxy(candidate);screenLog=(a*(1-gamma)+gamma)*(newLs-ls);
        bypass=rand(1,n)<o.bypass;pass=bypass|log(rand(1,n))<min(0,screenLog);
        ids=find(pass);accept=false(1,n);newLe=-Inf(1,n);newRaw=nan(size(raw));
        if ~isempty(ids)
            q=exact(candidate(:,ids));newLe(ids)=q.logLikelihood;newRaw(:,ids)=q.residual;
            second=gamma*((newLe(ids)-newLs(ids))-(le(ids)-ls(ids)));
            ordinary=(1-gamma)*a*(newLs(ids)-ls(ids))+gamma*(newLe(ids)-le(ids));
            second(bypass(ids))=ordinary(bypass(ids));
            accept(ids)=q.valid&log(rand(1,numel(ids)))<min(0,second);
        end
        for k=1:5
            attempts(k)=attempts(k)+nnz(labels==k);screens(k)=screens(k)+nnz(labels==k&pass);
            accepts(k)=accepts(k)+nnz(labels==k&accept);
        end
        jump=proposal(:,accept)-z(:,accept);esjd=esjd+sum(jump(:).^2)/size(z,1);
        theta(:,accept)=candidate(:,accept);z(:,accept)=proposal(:,accept);
        ls(accept)=newLs(accept);le(accept)=newLe(accept);raw(:,accept)=newRaw(:,accept);valid(accept)=true;
        bypasses=bypasses+nnz(bypass);
        fprintf('  代理桥层%d g=%.5f 移动%d/%d：候选%d，一阶段通过%d，接受%d。\n', ...
            index,gamma,sweep,sweeps,n,nnz(pass),nnz(accept));
    end
    totalAttempt=totalAttempt+sum(attempts);totalScreen=totalScreen+sum(screens);totalAccept=totalAccept+sum(accepts);
    if gamma<1,rho=min(.95,max(.01,rho.*exp(.5*(accepts./max(attempts,1)-.2))));end
    record=struct('gamma',gamma,'increment',delta,'weightESS',ess, ...
        'attempted',attempts,'screenPassed',screens,'accepted',accepts,'bypassed',bypasses, ...
        'ancestorCount',numel(unique(ancestor)),'distinct',size(unique(theta.','rows'),1), ...
        'rho',rho,'meanSquaredLatentJump',esjd/max(sum(attempts),1));
    if isempty(stages),stages=record;else,stages(index)=record;end %#ok<AGROW>
    checkpoint=struct('signature',signature,'theta',theta,'z',z,'w',w,'ls',ls,'le',le,'raw',raw, ...
        'valid',valid,'gamma',gamma,'ancestor',ancestor,'rho',rho,'stages',stages, ...
        'totalAttempt',totalAttempt,'totalScreen',totalScreen,'totalAccept',totalAccept,'rngState',rng);
    tmp=[file,'.partial.mat'];save(tmp,'checkpoint','-v7.3');movefile(tmp,file,'f');
    fprintf('代理桥层%d完成：g=%.6f，权重ESS=%.1f/%d，祖先%d。\n',index,gamma,ess,n,numel(unique(ancestor)));
end
[~,~,q]=unique(theta.','rows');mass=accumarray(q,w(:));
r=struct('theta',theta,'weights',w,'exactResidual',raw,'exactValid',valid, ...
    'logLikelihood',le,'proxyLogLikelihood',ls,'gamma',gamma,'stages',stages, ...
    'effectiveSampleSize',1/sum(w.^2),'distinctSupportWeightESS',1/sum(mass.^2), ...
    'distinctSampleCount',numel(mass),'ancestorCount',numel(unique(ancestor)), ...
    'attempted',totalAttempt,'screenPassed',totalScreen,'accepted',totalAccept, ...
    'options',o,'contractHash',c.contractHash);
end
function t=nextTemperature(g,score,w)
target=min(.8*numel(w),.95/sum(w.^2));
if incrementalESS(1-g,score,w)>=target,t=1;return;end
lo=g;hi=1;
for k=1:55
    m=(lo+hi)/2;if incrementalESS(m-g,score,w)<target,hi=m;else,lo=m;end
end
t=max(lo,min(1,g+1e-6));
end
function e=incrementalESS(step,score,w)
q=normalize(log(max(w,realmin))+step*score);e=1/sum(q.^2);
end
function w=normalize(x)
x=x-max(x);w=exp(x);assert(all(isfinite(w))&&sum(w)>0,'桥接权重无效。');w=w/sum(w);
end
function ids=resample(w)
n=numel(w);cdf=cumsum(w);cdf(end)=1;x=((0:n-1)+rand)/n;ids=zeros(1,n);k=1;
for j=1:n,while x(j)>cdf(k),k=k+1;end;ids(j)=k;end
end
