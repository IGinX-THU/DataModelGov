function out=sht_tc27_normal_box(mu,S,lower,upper,count,seed,drawCount,coarseCount)
%SHT_TC27_NORMAL_BOX Genz逐条件积分：正态矩形概率和有界条件样本。
% 不将越界样本截到边界。依次从条件截断正态产生点，并以各步区间
% 概率的乘积加权。随机平移Halton点使用固定种子，似然可重复计算。
% 返回的ESS仅衡量积分权重，不是健康参数后验的有效样本数。
% 可从高精度序列的前coarseCount点同时计算低精度概率，不重复积分。
% 只缓存与均值/边界/协方差无关的Halton基点，不缓存候选条件分布。
if nargin<7,drawCount=0;end
if nargin<8,coarseCount=0;end
validateattributes(coarseCount,{'numeric'}, ...
    {'scalar','real','finite','integer','>=',0,'<=',count});
mu=mu(:);lower=lower(:);upper=upper(:);d=numel(mu);
assert(all(lower<upper)&&isequal(size(S),[d,d]),'TC27:UQ:BoxDimensions', ...
    '条件均值%d维，协方差%s，边界%d维。',d,mat2str(size(S)),numel(lower));
sd=sqrt(diag(S));assert(all(sd>0));
% 先处理最受边界约束的维度，以减小逐条件积分方差。
[~,order]=sort(logInterval((lower-mu)./sd,(upper-mu)./sd));
m=mu(order);lo=lower(order);hi=upper(order);L=chol((S(order,order)+S(order,order).')/2,'lower');
old=rng;clean=onCleanup(@()rng(old));rng(seed,'twister');
% 保持每维一次随机平移及随后抽样的随机数位置，与原计算完全同义。
shift=rand(d,1);u=mod(local_halton_base(d,count)+shift,1);
u=min(max(u,eps),1-eps);z=zeros(d,count);logWeight=zeros(1,count);
for j=1:d
    location=m(j)+L(j,1:j-1)*z(1:j-1,:);
    a=(lo(j)-location)/L(j,j);b=(hi(j)-location)/L(j,j);
    lp=logInterval(a,b);logWeight=logWeight+lp;
    z(j,:)=truncatedQuantile(a,b,u(j,:),lp);
end
peak=max(logWeight);assert(isfinite(peak),'TC27:UQ:BoxIntegral','正态矩形积分发生非有限值。');
w=exp(logWeight-peak);normalizer=sum(w);w=w/normalizer;
x=m+L*z;full=zeros(size(x));full(order,:)=x;
meanValue=full*w.';delta=full-meanValue;
out=struct('logProbability',peak+log(normalizer/count),'mean',meanValue, ...
    'covariance',(delta.*w)*delta.','integrationESS',1/sum(w.^2),'pointCount',count);
if coarseCount>0
    coarseWeight=logWeight(1:coarseCount);coarsePeak=max(coarseWeight);
    out.coarseLogProbability=coarsePeak+ ...
        log(sum(exp(coarseWeight-coarsePeak))/coarseCount);
end
assert(all(full>=lower-1e-10 & full<=upper+1e-10,'all'),'有界积分产生越界点。');
if drawCount>0
    cumulative=cumsum(w);targets=((0:drawCount-1)+rand)/drawCount;
    index=zeros(1,drawCount);
    for j=1:drawCount,index(j)=find(cumulative>=targets(j),1);end
    out.draws=full(:,index);
end
end

function u=local_halton_base(d,count)
% 单项缓存有固定内存上限，不受候选求值顺序或随机种子影响。
persistent dimension pointCount base;
if isequal(dimension,d) && isequal(pointCount,count),u=base;return;end
p=primes(max(100,8*d));p=p(1:d);u=zeros(d,count);
for j=1:d
    k=1:count;v=zeros(1,count);f=1/p(j);
    while any(k),v=v+f*mod(k,p(j));k=floor(k/p(j));f=f/p(j);end
    u(j,:)=v;
end
dimension=d;pointCount=count;base=u;
end

function y=logPhi(x)
y=log(.5*erfc(-x/sqrt(2)));q=x<-10;
y(q)=log(.5)+log(erfcx(-x(q)/sqrt(2)))-x(q).^2/2;
end
function p=logInterval(a,b)
% 正尾区间改用生存概率，避免1减1；负尾使用log-CDF避免下溢。
positive=a>0;t=a(positive);a(positive)=-b(positive);b(positive)=-t;
la=logPhi(a);lb=logPhi(b);p=lb+log(-expm1(min(la-lb,-eps)));
end
function x=truncatedQuantile(a,b,u,lp)
positive=a>0;t=a(positive);a(positive)=-b(positive);b(positive)=-t;
u(positive)=1-u(positive);
left=logPhi(a);increment=log(u)+lp;peak=max(left,increment);
logp=peak+log(exp(left-peak)+exp(increment-peak));
x=-sqrt(2)*erfcinv(2*exp(logp));tail=logp<-30;
if any(tail)
    y=-sqrt(-2*logp(tail));
    for k=1:7
        logcdf=logPhi(y);derivative=exp(-y.^2/2-.5*log(2*pi)-logcdf);
        y=y-(logcdf-logp(tail))./derivative;
    end
    x(tail)=y;
end
x(positive)=-x(positive);
end
