function count = sht_measurement_mean_sample_count(data, legacyCount)
%SHT_MEASUREMENT_MEAN_SAMPLE_COUNT 按工况读取均值所用的有效记录数。
% sample_count是记录统计信息，不是测量通道、噪声先验或参数粒子数。
% 新Excel逐行提供该列；只有不含此列的历史数据可用显式旧计数兼容。
% 同一行假定各正式测量均值使用相同有效记录，不能用样本数猜测段长。
if nargin<2,legacyCount=[];end
assert(istable(data),'SHT:MeanCount:DataType','输入必须是工况表。');
if ismember('sample_count',data.Properties.VariableNames)
    count=data.sample_count;
else
    assert(~isempty(legacyCount),'SHT:MeanCount:Missing', ...
        '均值Excel缺少sample_count，请提供每工况实际有效记录数，不能默认201。');
    assert(isnumeric(legacyCount) && isscalar(legacyCount), ...
        'SHT:MeanCount:LegacyScalar','历史兼容只接受明确的统一计数，不按数组长度猜测工况对应。');
    count=repmat(legacyCount,height(data),1);
end
assert(isnumeric(count) && isreal(count) && size(count,2)==1 && ...
    numel(count)==height(data) && all(isfinite(count)) && ...
    all(count>=1 & count==round(count)), ...
    'SHT:MeanCount:Invalid','sample_count每行必须为有限正整数。');
count=double(count(:));
end
