function [c,audit]=sht_tc24_uq_d_bend_prior(c,factor)
% D可选工程平滑先验：仅收缩每条曲线相对直线的剩余弯折。
% 保留所有节点、常值、名义水平/趋势协方差；不读取真值或测试数据。
validateattributes(factor,{'numeric'},{'scalar','>',0,'<=',1});
V=c.priorCovariance;A=eye(c.parameterCount);rows={};
families=unique(c.parameterTable.base_name,'stable');
for family=families.'
    ix=find(c.parameterTable.base_name==family);x=c.parameterTable.coordinate(ix);
    if numel(ix)<3 || any(~isfinite(x)) || any(diff(x)<=0),continue;end
    u=(x-x(1))/(x(end)-x(1));X=[ones(numel(x),1),u];
    w=[diff(u(1:2));u(3:end)-u(1:end-2);diff(u(end-1:end))]/2;w=w/sum(w);
    H=(X.'*(w.*X))\(X.'.*w.');P=X*H;Q=eye(numel(x))-P;
    A(ix,ix)=P+factor*Q;
    before=V(ix,ix);after=A(ix,ix)*before*A(ix,ix).';
    error=norm(H*(after-before)*H.','fro')/max(norm(H*before*H.','fro'),eps);
    assert(error<1e-9,'TC24:D:BendConservation','水平/趋势名义协方差必须保持。');
    rows{end+1}=table(family,numel(ix),factor,error, ...
        'VariableNames',{'family','node_count','bend_sd_factor','level_trend_relative_change'}); %#ok<AGROW>
end
audit=struct('factor',factor,'targetChanged',factor~=1,'nodesChanged',false, ...
    'nominalLevelAndTrendPreserved',true,'boundedPhysicalMomentsMayChange',true,'truthUsed',false);
audit.table=vertcat(rows{:});
if factor==1,return;end
V=A*V*A.';c.priorCovariance=(V+V.')/2;c.priorSigma=sqrt(diag(V));
c.priorCorrelation=V./(c.priorSigma*c.priorSigma.');c.parameterTable.prior_sigma=c.priorSigma;
c.dBendPrior=audit;
identity=struct('base',c.contractHash,'factor',factor,'covariance',V,'method','preserve_level_trend_v1');
md=java.security.MessageDigest.getInstance('SHA-256');md.update(unicode2native(jsonencode(identity),'UTF-8'));
c.contractHash=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end
