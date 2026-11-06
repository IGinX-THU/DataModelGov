function o=sht_tc24_estimation_options(route,user)
% TC24集中配置查询，不加载DLL、不读取测量或构造节点。
% 返回现行默认及用户覆盖；工程参考在正式执行时按所选包生成。
if nargin<1,route='steady';end
if nargin<2,user=struct();end
assert(ismember(route,{'steady','transient_instant'}),'TC24:Config:Route','未知路径。');
root=fileparts(mfilename('fullpath'));
o=sht_steady_model_adapt_v2_common('defaultoptions',route);
if isfield(user,'runtimeDirectory') && ~isempty(user.runtimeDirectory)
    o.runtimeDirectory=sht_tc24_absolute_path(user.runtimeDirectory);
else
    package=sht_tc24_runtime_package();o.runtimeDirectory=package.directory;
end
% 样本计数由测量Excel逐行提供；禁止从采样周期或造数MAT推测。
o.residualWindowSampleCount=[];
o.modelMode=0;o.inletBoundaryMode=1;
o.estimateInletPressureLoss=true;o.includePt2Residual=false;
o.trainingFile=fullfile(root,'TestData','three_component','tc24_training_means.xlsx');
o.testFile='';o.evaluateTestSet=false;
o.steadyNpBranchPriorOptions.requireIncreasingPower=false;
o.clusterSpan=.02;o.maxIterationA=12;o.maxIterationGroup=10;
% A/B/D上限均可由入口options覆盖；C为曲线构造，不存在优化迭代上限。
% R036用户确认：B每组最多10次；D总上限20次，给D2预留10次。
% D1提前结束时，未使用的预算也可供D2使用；不是强制每段执行10次。
o.maxIterationRefine=20;
o.stageDCoordinateReserveIterations=10;
% B组常值可生成多个节点，节点初值相同但D中独立辨识；燃烧室自动精简。
o.adaptiveEvidenceNodes=true;
o.nodeReferencePolicy='fixed_engineering';
o.nodeSpeedAbsoluteSpacing=.02;
o.nodePressureRatioSpanFraction=.05;
o.nodeFlowSpanFraction=.15;o.nodeFlowDesignFloorFraction=.01;
% 燃油测量值/Wf_design的固定工程跨度比例；不是固定节点个数。
% 用户确认采用精简方案：本批自动形成6节点，其他数据不强制固定6个。
o.nodeFuelSpanFraction=.12;
% 正式保留R036原C方法；R037~R039仅为隔离对照，不随公共默认值改变。
o.stageCCoordinatePolicy='schedule_reanchor';
o.stageCOrdinatePolicy='group_average';
o.stageCBurnerCoordinateSource='baseline';
o.stageDCoordinatePolicy='diagnostic_outer';
o.stageDM3StabilityPolicy='diagnostic';
o.stageDSteadyLocalBranch=true;
o.steadyNpSelectionPolicy='verified_nearest';
% 零修正模型可能无测量Np附近的平衡根。仅A/B常值初始化
% 可以显式保留区间外诊断解，分支通过标志仍为false；C/D和交付不放行。
o.steadyNpAllowOutsideConstantInitialization=true;
o.saveStageCDevelopmentCheckpoint=true;
% 两条独立辨识路径均使用测量扭矩。DLL按每次残差的当前转速计算功率，
% 稳态辨识/测试优先RunOnePoint，失败时以相同扭矩回退MATLAB求解器。
o.shaftLoadInputMode=1;
o.steadyLoadBoundaryMode='torque';
o.steadyUseMeasuredPower=false;o.steadySolver='dll_first';
o.stageARegularizationMethod='tsvd';o.stageATsvdStepMode='direct_inverse';
o.stageATsvdRetainedCount=4;
% B先验中心为A结果，实际尺度=基准工程尺度*本系数；越小正则越强。
% 这不是D的lambda：D正则项乘lambda^2，方向相反。燃油偏置同步缩放。
o.stageBRegularizationMethod='tikhonov';o.stageBTikhonovPriorScale=.50;
% 可选按组工况数配置：[单工况尺度, 两个及以上工况尺度]。
% 用户确认稳态为[0.35,0.50]；留空可显式退回上述统一尺度。
o.stageBTikhonovPriorScaleByGroupSize=[.35,.50];
if strcmp(route,'transient_instant')
    o.stageATsvdRetainedCount=6;o.stageBTikhonovPriorScale=.75;
    % R025对照后用户确认：单点组保持约束，多点组适当放宽。
    o.stageBTikhonovPriorScaleByGroupSize=[.75,1.00];
end
o.constantJacobianMethod='strict_central';
o.stageDParameterization='actual_execution_nodes';o.stageDJacobianMethod='node_central_full';
o.stageDRegularizationMethod='tikhonov';
% 六燃油节点对照后由用户指定，不以GCV或隐藏真值自动选择。
o.stageDM3RegularizationStrength=.01;
if strcmp(route,'transient_instant'),o.stageDM3RegularizationStrength=.02;end
o.stageDM3RegularizationCandidates=[.01,.02,.05,.1,.2,.5,1,2,5,10];
% 两条路径均采用R022/R023验证的正则化信赖域。数值正则只控制当前步，
% 保留物理lambda及C先验；重新求完整有界更新，不乘统一更新比例。
o.stageDM3GlobalizationMethod='regularized_trust_region';
o.stageDM3TrustMaximumTrials=20;
% 冻结曲线h/h2检查显示原差分步长跨越明显局部曲率，四分之一步趋于稳定。
o.stageDDifferenceStepScale=.125;o.outputTag='m3';o.runId='';
o.requireConvergedStages=false;o.requireValidFinalReplay=true;o.figureVisible='off';
% 运行控制可选，不改变数值默认。preview只能来自同内容身份的正式准备。
o.preparedInput='';o.enableRunControl=false;o.resume=false;o.timingHistoryDirectory='';
names=fieldnames(user);for i=1:numel(names),o.(names{i})=user.(names{i});end
% 距离在节点构造前校验，避免向量/NaN/负值进入聚类后才隐式报错。
% 五类标尺互相独立；距离越大通常合并越多，不规定最终节点个数。
distanceFields={'clusterSpan','nodeSpeedAbsoluteSpacing', ...
    'nodePressureRatioSpanFraction','nodeFlowSpanFraction', ...
    'nodeFlowDesignFloorFraction','nodeFuelSpanFraction','nodeMergeAbsolute'};
for i=1:numel(distanceFields)
    name=distanceFields{i};
    validateattributes(o.(name),{'numeric'},{'real','scalar','finite','positive'}, ...
        mfilename,name);
end
assert(o.modelMode==0 && o.inletBoundaryMode==1,'TC24必须使用三部件及测量Pt1/Tt1。');
end
