function sensitivity=sht_tc24_meter_input_sensitivity(data,sensor)
% Wa1间接计量与Pt1/Tt1的共同来源灵敏度，单位分别(kg/s)/Pa和(kg/s)/K。
% 计量截面积0.08 m2是本轮独立工程先验，不是从隐藏造数参数读取的实机标定。
% 用测量Wa1/Pt1/Tt1反算亚声速计量马赫数；总压扰动时静压保持不变。
n=height(data);sensitivity=zeros(n,1);gamma=1.4;R=287.05;area=.08;
for i=1:n
    W=data.Wa1_mean(i);P=data.Pt1_mean(i);T=data.Tt1_mean(i);
    if strcmp(sensor,'Tt1')
        sensitivity(i)=-.5*W/T;
    elseif strcmp(sensor,'Pt1')
        q=W/(area*P)*sqrt(R*T/gamma);a=(gamma-1)/2;b=(gamma+1)/(2*(gamma-1));
        f=@(M)M/(1+a*M*M)^b-q;
        assert(f(0)*f(.99)<0,'TC24:Meter:Domain','间接流量超出亚声速计量模型范围。');
        M=fzero(f,[0,.99]);
        sensitivity(i)=W/P*(1+(1/M-2*a*b*M/(1+a*M*M))*(1+a*M*M)/(gamma*M));
    end
end
end
