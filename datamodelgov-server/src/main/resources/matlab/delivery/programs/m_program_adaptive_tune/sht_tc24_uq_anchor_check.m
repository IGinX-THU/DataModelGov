function audit=sht_tc24_uq_anchor_check(contract,factor,mu,variance,oldG,oldShift,newG,newShift,pilot)
% 在未用于求Jacobian的候选上比较响应近似，不读取测量真值和测试数据。
% 同时覆盖局部区域与先验方向；参考位置固定后才进入正式SMC。
old=rng;cleanup=onCleanup(@()rng(old));rng(20260910,'twister');
n=contract.parameterCount;m=numel(mu);count=12;
theta=pilot.formal.theta(:,round(linspace(1,size(pilot.formal.theta,2),count)));
theta(:,1)=0;theta(:,2)=contract.thetaHat;
for k=3:4
    theta(:,k)=contract.priorSigma.*randn(n,1);
    theta(:,k)=min(max(theta(:,k),contract.lowerBound+1e-8),contract.upperBound-1e-8);
end
G=(oldG{1}+oldG{2})/2;
eta=mu+sqrt(variance).*randn(m,count);
tbl=contract.nuisanceParameterTable;
eta=min(max(eta,tbl.lower_bound+1e-8),tbl.upper_bound-1e-8);
oldRms=nan(count,1);newRms=oldRms;oldMax=oldRms;newMax=oldRms;calls=0;
for k=1:count
    exact=sht_steady_model_uq_b_common('evaluate',contract.auxiliaryContract, ...
        [[theta(:,k);zeros(m,1)],[theta(:,k);eta(:,k)]], ...
        contract.trainingData,struct('useCache',true,'useRobustTransientFallback',true));
    calls=calls+exact.dllEvaluationCount;
    if ~all(exact.valid),continue;end
    actual=exact.residual(:,2)-exact.residual(:,1);
    a=factor.cholLower\(oldShift+G*(eta(:,k)-mu)-actual);
    b=factor.cholLower\(newShift+newG*(eta(:,k)-mu)-actual);
    oldRms(k)=sqrt(mean(a.^2));newRms(k)=sqrt(mean(b.^2));
    oldMax(k)=max(abs(a));newMax(k)=max(abs(b));
end
valid=isfinite(newRms) & isfinite(oldRms);
useNew=pilot.converged && nnz(valid)>=8 && norm(newRms(valid))<=norm(oldRms(valid)) ...
    && max(newMax(valid))<=max(oldMax(valid));
selected='two_anchor';if useNew,selected='checked_local_map';end
audit=struct('enabled',true,'useNewAnchor',useNew,'selected',selected, ...
    'table',table((1:count).',oldRms,newRms,oldMax,newMax, ...
    'VariableNames',{'candidate','old_RMS','new_RMS','old_max','new_max'}), ...
    'dllEvaluationCount',calls,'truthRead',false,'testRead',false, ...
    'pilotConverged',pilot.converged,'validChecks',nnz(valid));
fprintf('TC24-C anchor check: old/new RMS %.5g / %.5g; selected %s.\n', ...
    sqrt(mean(oldRms(valid).^2)),sqrt(mean(newRms(valid).^2)),selected);
end
