function cfg=sht_tc24_b_lean_config(user)
% 兼容原精简B候选调用名称；正式默认只在sht_tc24_b_config维护。
if nargin<1,user=struct();end
cfg=sht_tc24_b_config(user);
end
