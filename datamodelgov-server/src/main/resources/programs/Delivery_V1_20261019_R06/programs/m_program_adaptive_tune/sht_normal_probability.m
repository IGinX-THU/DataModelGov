function y=sht_normal_probability(action,x,mu,sigma)
%SHT_NORMAL_PROBABILITY 基础MATLAB的正态CDF、逆CDF和密度。
% 尾部用erfc/erfcinv，避免1-erf及2*p-1造成小概率有效位丢失。
% action为cdf/inv/pdf；mu、sigma缺省为0、1，允许隐式扩展。
if nargin<3,mu=0;end
if nargin<4,sigma=1;end
switch action
    case 'cdf'
        z=(x-mu)./sigma;y=.5*erfc(-z/sqrt(2));
    case 'pdf'
        z=(x-mu)./sigma;y=exp(-.5*z.^2)./(sqrt(2*pi)*sigma);
    case 'inv'
        z=nan(size(x));lo=x>=0 & x<=.5;hi=x>.5 & x<=1;
        z(lo)=-sqrt(2)*erfcinv(2*x(lo));
        z(hi)=sqrt(2)*erfcinv(2*(1-x(hi)));
        y=mu+sigma.*z;
    otherwise
        error('SHT:Normal:Action','未知正态分布操作：%s。',action);
end
bad=sigma<=0 | isnan(sigma);bad=bad | false(size(y));y(bad)=NaN;
end
