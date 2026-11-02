function [spec,index] = sht_data_sampling_specification(time)
%SHT_DATA_SAMPLING_SPECIFICATION 试车/飞参统一的仿真与记录采样约定。
% 仿真和传感器动态按0.025s推进；记录按0.1s取点，不作四点平均，
% 也不隐含增加抗混叠滤波器。控制器更新周期不由本函数改变。
% 不传time时只返回采样规则，不预设任何有效段长度或均值样本数。
% 传入time时返回实际完整记录的时长和计数，生成端据此写入Excel。
spec=struct('schema','SHT_DATA_SAMPLING_10HZ_V3_PER_POINT_COUNT', ...
    'simulationStep_s',.025,'sampleInterval_s',.1,'sampleRate_Hz',10, ...
    'recordStride',4,'samplingMethod','point_sample', ...
    'additionalAntialiasFilter',false);
index=[];
if nargin==0,return;end
validateattributes(time,{'numeric'},{'vector','real','finite','nonempty'});
time=time(:);
assert(numel(time)>=2 && all(abs(diff(time)-spec.simulationStep_s)<1e-9), ...
    'SHT:Sampling:SimulationGrid','原始时间轴必须严格按0.025s递增。');
assert(abs(time(1)/spec.sampleInterval_s-round(time(1)/spec.sampleInterval_s))<1e-8, ...
    'SHT:Sampling:StartAlignment','原始起始时刻必须位于0.1s采样网格上。');
index=(1:spec.recordStride:numel(time)).';
spec.recordDuration_s=time(index(end))-time(index(1));
spec.recordSampleCount=numel(index);
end
