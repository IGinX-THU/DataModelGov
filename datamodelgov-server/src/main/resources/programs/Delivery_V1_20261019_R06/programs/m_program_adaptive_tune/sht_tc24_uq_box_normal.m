function out=sht_tc24_uq_box_normal(mu,V,lower,upper,count,seed,returnSamples)
%SHT_TC24_UQ_BOX_NORMAL 有界多元高斯的确定性QMC积分。
% 顺序条件正态变换(Genz)：每步在条件上下界内生成标准正态，
% 将条件区间概率相乘作为权重。返回概率与有界条件矩，不做越界裁剪。
% Sobol节点在调用前由独立固定种子生成；不污染SMC的随机数状态。
% 此处为数值积分而非解析精确概率，调用者必须进行节点数收敛检查。
if nargin<7,returnSamples=false;end
validateattributes(count,{'numeric'},{'scalar','integer','>=',16});
validateattributes(seed,{'numeric'},{'scalar','integer','nonnegative'});
d=size(mu,1);n=size(mu,2);lower=lower(:);upper=upper(:);
assert(isequal(size(V),[d,d]) && numel(lower)==d && all(lower<upper));
V=(V+V.')/2;sd=sqrt(diag(V));assert(all(sd>0));
% 静态排序不能随候选改变，从而所有候选使用同一确定性积分规则。
prob0=sht_normal_probability('cdf',upper./sd)-sht_normal_probability('cdf',lower./sd);
[~,order]=sort(prob0);inverse(order)=1:d;
L=chol(V(order,order),'lower');a=lower(order);b=upper(order);center=mu(order,:);
[u,qmcIdentity]=sht_sobol_points(d,count,1024,seed);
out=struct('logProbability',zeros(1,n),'mean',zeros(d,n), ...
    'covariance',zeros(d,d,n),'integrationEss',zeros(1,n), ...
    'count',count,'seed',seed,'qmcIdentity',qmcIdentity,'samples',[],'weights',[]);
if returnSamples,out.samples=zeros(d,count,n);out.weights=zeros(count,n);end
% 候选逐一积分，控制内存；每个候选内部的QMC节点使用矩阵计算。
for k=1:n
    z=zeros(count,d);logWeight=zeros(count,1);
    for j=1:d
        offset=center(j,k)+z(:,1:j-1)*L(j,1:j-1).';
        alpha=(a(j)-offset)/L(j,j);beta=(b(j)-offset)/L(j,j);
        [z(:,j),logWidth]=local_truncated_standard(alpha,beta,u(:,j));
        logWeight=logWeight+logWidth;
    end
    shift=max(logWeight);w=exp(logWeight-shift);mass=sum(w);w=w/mass;
    x=(center(:,k)+L*z.');x=x(inverse,:);
    meanValue=x*w;dx=x-meanValue;
    out.logProbability(k)=shift+log(mass/count);out.mean(:,k)=meanValue;
    out.covariance(:,:,k)=(dx.*w.')*dx.';
    out.integrationEss(k)=1/sum(w.^2);
    if returnSamples,out.samples(:,:,k)=x;out.weights(:,k)=w;end
end
out.probability=exp(out.logProbability);
end

function [z,logWidth]=local_truncated_standard(a,b,u)
% 对极小概率候选也在对数域计算，不将尾概率下溢误当成物理不可行。
z=zeros(size(a));logWidth=z;positive=a>0;negative=b<0;middle=~positive & ~negative;
if any(middle)
    lo=sht_normal_probability('cdf',a(middle));width=sht_normal_probability('cdf',b(middle))-lo;
    z(middle)=sht_normal_probability('inv',lo+u(middle).*width);logWidth(middle)=log(width);
end
if any(positive)
    [z(positive),logWidth(positive)]=local_positive_tail(a(positive),b(positive),u(positive));
end
if any(negative)
    [v,logWidth(negative)]=local_positive_tail(-b(negative),-a(negative),1-u(negative));
    z(negative)=-v;
end
end

function [z,lw]=local_positive_tail(a,b,u)
la=local_log_survival(a);lb=local_log_survival(b);
lw=la+log(-expm1(lb-la));v=log1p(-u)+lw;
largest=max(lb,v);lq=largest+log(exp(lb-largest)+exp(v-largest));
z=-sht_normal_probability('inv',exp(lq));extreme=~isfinite(z);
if any(extreme)
    x=sqrt(-2*lq(extreme));target=lq(extreme);
    for k=1:12
        residual=local_log_survival(x)-target;
        hazard=sqrt(2/pi)./erfcx(x/sqrt(2));x=x+residual./hazard;
    end
    z(extreme)=x;
end
end

function value=local_log_survival(x)
value=log(.5)+log(erfcx(x/sqrt(2)))-.5*x.^2;
value(isinf(x))=-inf;
end
