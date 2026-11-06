function report=sht_r2019b_preflight()
%SHT_R2019B_PREFLIGHT 长计算前核对目标版本、中文源码及无工具箱基础接口。
% 工具箱是否安装只记录，不选择另一正式算法，不修改编译器或全局编码。
assert(~verLessThan('matlab','9.7'),'SHT:Runtime:Version','需要MATLAB R2019b或以上版本。');
assert(strcmp(computer('arch'),'win64'),'SHT:Runtime:Architecture','当前DLL需要Windows 64位MATLAB。');
expected=char([27979,37327,25968,25454]);
assert(isequal('测量数据',expected),'SHT:Runtime:Encoding', ...
    'M-file encoding does not match this MATLAB locale; use the validated GBK source.');
required={'sht_quantile_vector','sht_normal_probability','sht_bounded_least_squares', ...
    'sht_sobol_points','sht_export_figure'};
for k=1:numel(required)
    assert(exist(required{k},'file')==2,'SHT:Runtime:MissingFunction','缺少运行依赖：%s。',required{k});
end
report=struct('matlabRelease',version('-release'),'matlabVersion',version, ...
    'architecture',computer('arch'),'numericalBackend','base_matlab', ...
    'optimizationRequired',false,'statisticsRequired',false,'passed',true);
assert(abs(sht_quantile_vector([1,2,3,4],.5)-2.5)<eps(3));
assert(abs(sht_normal_probability('cdf',0)-.5)<eps);
fprintf('TC24运行环境：MATLAB %s，%s，无Optimization/Statistics工具箱依赖。\n', ...
    report.matlabRelease,report.architecture);
end
