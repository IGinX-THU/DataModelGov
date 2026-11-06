function [variance,factor,blocks,audit]=sht_tc27_uq_history_discrepancy(c,point,variance,spec)
%SHT_TC27_UQ_HISTORY_DISCREPANCY 保持稳态口径的相关历程工程模型差异。
% 同一气路通道的常量/工况趋势误差在所有训练数据中共享，不能因采样
% 增密变成独立信息；剩余历程误差用指数协方差表示，其时间尺度由用户
% 给定。该尺度不是传感器时间常数，不通过测试集或隐藏真值调参。
% 第一条测量用于初始化的通道采用相同的初值消去算子，防止把恒等于
% 零的首行残差误当成额外观测。Wa2不通过该传感器初值初始化。
n=numel(variance);np=height(c.trainingData);
factor=zeros(n,18);blocks=struct('rows',{},'cholLower',{});
coordinate=c.trainingData.Ng_mean./sqrt(c.trainingData.Tt1_mean);
left=min(coordinate);span=max(coordinate)-left;
degenerate=span<=1e-10*max(1,max(abs(coordinate)));
if degenerate,trend=zeros(np,1);else,trend=2*(coordinate-left)/span-1;end
sigma=zeros(9,1);
for j=1:9
    q=find(spec.name==string(c.historyNames{j}),1);fraction=.001;
    if strcmp(c.historyNames{j},'Tt45'),fraction=.0015;end
    sigma(j)=fraction*spec.designReference(q);
    if j>=3
        rows=(j-1)*np+(1:np);
        factor(rows,2*j-1)=.7*sigma(j);factor(rows,2*j)=.5*sigma(j)*trend;
        variance(rows)=variance(rows)+(.5*sigma(j))^2*(1+double(degenerate));
    end
end
variance(1:9*np)=variance(1:9*np)+diag(point.stationarityCovariance);
% 严格验证共享基函数重构出的稳态子块与TC24原规则一致。
expected=point.modelCovariance+point.stationarityCovariance;
extra=diag(point.stationarityCovariance);
for j=3:9,rows=(j-1)*np+(1:np);extra(rows)=extra(rows)+(.5*sigma(j))^2*(1+double(degenerate));end
actual=diag(extra)+factor(1:9*np,:)*factor(1:9*np,:)';
relativeError=norm(actual-expected,'fro')/max(norm(expected,'fro'),eps);
assert(relativeError<1e-10,'TC27:UQ:HistoryPointCovariance','历程模型差异改变了稳态子块。');
offset=9*np;tau=c.options.historyCorrelationTime_s;
for h=1:numel(c.histories)
    t=c.histories(h).data;time=t.Time_s-t.Time_s(1);count=height(t);
    if degenerate,tr=zeros(count,1);else,tr=2*(t.Ng./sqrt(t.Tt1)-left)/span-1;end
    K=exp(-abs(time-time')/tau);
    for j=1:9
        rows=offset+(j-1)*count+(1:count);q=find(spec.name==string(c.historyNames{j}),1);
        a=zeros(count,1);
        if j<=2,a=exp(-time/tau);
        elseif j<=8,a=exp(-time/spec.timeConstant_s(q));end
        localK=K-a*K(1,:)-K(:,1)*a'+a*a';
        common=ones(count,1)-a;localTrend=tr-a*tr(1);
        factor(rows,2*j-1)=.7*sigma(j)*common;
        factor(rows,2*j)=.5*sigma(j)*localTrend;
        R=diag(variance(rows))+(.5*sigma(j))^2*localK;
        R=(R+R')/2;[L,flag]=chol(R,'lower');
        assert(flag==0,'TC27:UQ:HistoryCovariance','相关历程协方差不正定。');
        blocks(end+1)=struct('rows',rows(:),'cholLower',L); %#ok<AGROW>
    end
    offset=offset+9*count;
end
audit=struct('enabled',true,'definition','shared_constant_trend_plus_exponential_time_covariance', ...
    'correlationTime_s',tau,'outputNames',{c.historyNames},'modelStd',sigma, ...
    'pointBlockRelativeError',relativeError,'calibrated',false, ...
    'truthUsed',false,'testUsed',false,'sameSourceNotIndependentReplicates',true);
end
