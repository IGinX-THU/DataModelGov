function options=sht_tc27_estimation_options(route,method,user)
%SHT_TC27_ESTIMATION_OPTIONS 四组合共用的可独立检查默认配置，不打开DLL。
% 仅统一数值提速设置，不统一两条路径的正则强度，也不改变方法I/II。
% D0无历程仍用中心差分；D1含历程才默认前向差分及0.1s辨识积分。
if nargin<3||isempty(user),user=struct();end
assert(ismember(route,{'steady','transient_instant'})&&ismember(method,{'I','II'}), ...
    '路径/方法无效。');
assert(isstruct(user)&&isscalar(user),'options应为标量结构体。');
options=struct('thermalMode',3,'maxIterationB',10,'maxIterationD0',10, ...
    'maxIterationD1',10,'regularizationB','tikhonov','regularizationD','tikhonov', ...
    'retainedB',6,'retainedD',6,'lambdaD',.02,'pointHistoryWeights',[.7,.3], ...
    'steadySourceWeights',[.5,.5],'includeSmallHistory',true,'resume',true, ...
    'stopAfterC',false,'plot',true,'tag','R006e','difference','central', ...
    'differenceD0','central','differenceD1','forward', ...
    'objectiveImprovementTolerance',1e-3,'integrationStep_s',.1, ...
    'validationIntegrationStep_s',.025,'outputBatch','TC27_R021_LocalPrepared', ...
    'localWarmup_s',60,'reusePreparationForJacobian',true,'reusePointFitFile','');
% 显式业务输入只在用户主动打开时生效；缺项拒绝，不回退历史样例。
options.explicitInputs=false;
options.upstreamModelFile='';options.steadyTrainingFile='';
options.trainingHistoryFile='';options.testPointFiles={};options.testHistoryFiles={};
options.outputDirectory='';
options.runControlEnabled=false;options.runControl=[];
if strcmp(route,'steady'),options.lambdaD=.01;end
% 瞬态时刻/II已在前批采用R006d，保留其身份；另三组不得续接旧R006b。
options.tag='R021';
fields=fieldnames(user);
for j=1:numel(fields),options.(fields{j})=user.(fields{j});end
if options.explicitInputs
    for name={'upstreamModelFile','steadyTrainingFile','trainingHistoryFile','outputDirectory'}
        value=options.(name{1});
        assert((ischar(value)||isstring(value))&&strlength(string(value))>0, ...
            'TC27:Options:ExplicitInput','显式业务运行缺少%s。',name{1});
    end
    assert(iscell(options.testPointFiles)&&iscell(options.testHistoryFiles), ...
        'TC27:Options:Tests','可选测试文件须分别以cell数组传入。');
    assert((~options.resume||options.runControlEnabled)&&isempty(options.reusePointFitFile), ...
        'TC27:Options:NewRun','新试车业务运行须使用独立输出目录，不续用历史检查点。');
end
% 用户关闭历程后，两轮都是纯工况点问题，D1沿用D0差分设置。
if ~options.includeSmallHistory,options.differenceD1=options.differenceD0;end
end
