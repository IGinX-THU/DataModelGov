function spec = sht_tc24_measurement_specification()
%SHT_TC24_MEASUREMENT_SPECIFICATION 三部件公开仪表工程规格，不含偏置实现。
% 独立于造数文件。辨识/UQ可以读取本表，不能读取造数保存的实际误差。
% scale是确定性工程残差尺度；biasHalfWidth不是样本噪声，不能除sqrt(N)。
name = ["Np";"Ng";"Wf";"Mkp";"Pt1";"Tt1";"Ptb3";"Ttb3"; ...
    "Pt45";"Tt45";"Pt6";"Tt6";"Pamb";"Tamb";"Altitude";"Mach";"RH"];
unit = ["rpm";"rpm";"kg/s";"N m";"Pa";"K";"Pa";"K"; ...
    "Pa";"K";"Pa";"K";"Pa";"K";"m";"1";"%"];
reference = [20900;38000;.151914044493225;2176600/(20900*pi/30); ...
    101325;288.15;1572564;702.30798695;395927.7374;1142.9391; ...
    110000;800;101325;288.15;100;1;100];
biasHalfWidth = reference.*[.0001;.0001;.0045;.001;.0005;.0005; ...
    .001;.002;.001;.0025;.001;.0025;.0002;.0005;.01;0;.02];
noiseStd = [1.286137;1.731982;3.9186e-5;.247386;12.06556713;.041872; ...
    218.536741;.213684;43.618257;.342917;15;.25;12.438729;.041872;.5;0;.2];
bandwidth = [100;100;50;100;100;1;100;1/.3;100;2;100;1/.6;100;.5;50;50;1];
% 温度动态从唯一共享字典读取，避免试车和飞参出现两套热电偶时间常数。
aliases = {'Tt1','Tamb','Tt3','Tt45','Tt5'};
target = {'Tt1','Tamb','Ttb3','Tt45','Tt6'};
d = sht_temperature_sensor_dynamics('channelConfig',aliases);
for j=1:numel(target), bandwidth(name==target{j})=1/d.timeConstant_s(j); end
engineeringScale = [63;114;1e-4;1;100;1;7863;3.51;1980;5.72;550;4;30;.3;2;1;3];
spec = table(name,unit,reference,biasHalfWidth,noiseStd,bandwidth, ...
    engineeringScale,'VariableNames',{'name','unit','designReference', ...
    'biasHalfWidth','noiseStd','bandwidth_radps','engineeringScale'});
spec.timeConstant_s = 1./spec.bandwidth_radps;
spec.delay_s = zeros(height(spec),1);
end
