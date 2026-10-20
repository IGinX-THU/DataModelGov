function o=sht_tc27_uq_d_options(user)
%SHT_TC27_UQ_D_OPTIONS D快速初评的共同默认设置，不影响C/CD入口。
% 用户显式配置优先。积分步长默认0.1s，与当前记录周期相同；仍是独立
% 的积分设置，不抽稀测量数据，不修改造数/控制周期，也不隐藏增加子步。
if nargin<1,user=struct();end
validateattributes(user,{'struct'},{'scalar'});
o=struct('tag','R021','outputBatch','TC27_R021_LocalPrepared','observationMode','steady_points', ...
    'dMaxIterations',3,'localSampleCount',512,'predictionHistoriesEnabled',false, ...
    'errorModel','tc24_engineering','integrationStep_s',0.1, ...
    'nuisanceAnchorMode','reference','historyDiscrepancy','correlated_engineering', ...
    'historyCorrelationTime_s',5,'curveCorrelationLengthScale',1,'deliveryTag','R021');
names=fieldnames(user);
for j=1:numel(names),o.(names{j})=user.(names{j});end
% 与共享D后端保持相同下限，先拒绝非法设置，避免先读取模型或准备DLL。
validateattributes(o.localSampleCount,{'numeric'}, ...
    {'scalar','real','finite','integer','>=',128},mfilename,'options.localSampleCount');
% 从实际模型Excel判定路径，不把仅适用于固定轴速的热复用强加给稳态路径。
% 显式false保留完整求解对照；不改变旧合同/检查点中的已冻结配置。
route='';
if isfield(user,'modelFile') && ~isempty(user.modelFile) && isfile(char(user.modelFile))
    model=sht_tc27_delivery('read',[],char(user.modelFile));route=model.route;
elseif isfield(user,'route') && ~isempty(user.route)
    route=char(string(user.route));
end
if ~isfield(user,'thermalReuseEnabled')
    o.thermalReuseEnabled=strcmp(route,'transient_instant');
end
validateattributes(o.thermalReuseEnabled,{'logical'},{'scalar'});
assert(~o.thermalReuseEnabled || strcmp(route,'transient_instant'), ...
    'TC27:UQ:DReuseRoute','热平衡复用只适用于瞬态时刻路径，稳态路径请使用false。');
assert(strcmp(o.observationMode,'steady_points'),'TC27:UQ:HistoriesNotValidated', ...
    '新模型UQ首轮只允许steady_points。');
validateattributes(o.integrationStep_s,{'numeric'},{'scalar','real','finite','positive'});
assert(ismember(o.integrationStep_s,[0.1,0.025]),'TC27:UQ:DIntegrationStep', ...
    'D方法integrationStep_s请选择0.1或0.025秒。');
end
