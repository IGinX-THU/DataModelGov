function result=Start_TC24_05_TransientInstantEstimation(options)
% TC24-STEP05：三部件瞬态时刻路径，两轴加速度的稳态观测值为零。
% options可省略；以下字段由用户传入时覆盖公共默认配置：
%   maxIterationA / maxIterationGroup / maxIterationRefine：默认12/10/20。
%   stageDCoordinateReserveIterations=10：D2预留次数，剩余预算按D1实际次数计算。
%   stageARegularizationMethod：'tsvd'（默认）或'tikhonov'；
%   stageATsvdRetainedCount=6；stageATikhonovPriorScale=1.0。
%   stageBRegularizationMethod：'tikhonov'（默认）或'tsvd'；
%   stageBTikhonovPriorScaleByGroupSize=[.75,1.00]：单/多工况先验尺度；
%   stageBTsvdRetainedCount=5：B采用无阻尼TSVD时使用。
%   stageDRegularizationMethod：'tikhonov'（默认）或'tsvd'；
%   stageDM3RegularizationStrength=.02；stageDTsvdRetainedCount=6。
% A/B先验尺度越小正则越强，D的lambda越大正则越强。
% D上限是D1+D2总预算；C只构造曲线，不设置虚假的迭代次数或正则强度。
% 调度节点距离通过options配置，与稳态路径独立运行、独立形成结果：
%   clusterSpan=.02：HPC相对换算转速分组的最大组内跨度；
%   nodeSpeedAbsoluteSpacing=.02：HPC节点合并距离，绝对转速比单位；
%   nodePressureRatioSpanFraction=.05：GT/PT压比固定工程跨度的5%；
%   nodeFlowSpanFraction=.15：压损局部换算流量固定工程跨度的15%；
%   nodeFlowDesignFloorFraction=.01：流量距离不小于局部设计值的1%；
%   nodeFuelSpanFraction=.12：Wf_meas/Wf_design固定工程跨度的12%。
% 固定工程跨度为零修正慢车到最大状态，绝非本次训练集max-min。
% 燃烧室继续自动选点，压损额外保留固定(0,0)，不固定6/7个节点。
% 示例：Start_TC24_05_TransientInstantEstimation(struct('maxIterationGroup',12, ...
%     'stageBTikhonovPriorScaleByGroupSize',[.75,1],'nodeFuelSpanFraction',.12));
if nargin<1,options=struct();end
sht_r2019b_preflight();
result=sht_tc24_run_estimation('transient_instant',options);
end
