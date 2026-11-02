function c=sht_stage4_config(user)
% 第4阶段只编排单架次算法；本文件配置场景和输出，不修改发动机物理资产。
if nargin<1,user=struct();end
t=fileparts(mfilename('fullpath'));p=sht_f3_current_contract('paths');
c=struct('runId','T4_R011','engineId','SHT_ENGINE_001','scenarioIds',{{}}, ...
    'uqEnabled',true,'plotEnabled',true,'generationMaximumDuration_s',Inf, ...
    'fullReplayEnabled',true,'regularizationWeight',0.05,'maximumIterations',10, ...
    'inputMode','synthetic_demo','externalMeasurements',struct(), ...
    'historicalInputRoot',fullfile(t,'MiddleData','three_component', ...
        'flight_stage3','F3_3_6_R012'));
names=fieldnames(user);
for k=1:numel(names)
    assert(isfield(c,names{k}),'SHT:Stage4:Option','未知第4阶段选项%s。',names{k});
    c.(names{k})=user.(names{k});
end
assert(~isempty(regexp(c.runId,'^[A-Za-z0-9_]+$','once')),'批次名称不合法。');
assert(ismember(c.inputMode,{'synthetic_demo','external'}),'输入模式错误。');
% 空集合表示全部；非空集合只执行指定架次，不隐式补算父架次。
if ischar(c.scenarioIds)||isstring(c.scenarioIds),c.scenarioIds=cellstr(c.scenarioIds);end
assert(iscellstr(c.scenarioIds),'SHT:Stage4:Scenario','scenarioIds须为字符元胞数组。');
sc=sht_stage4_scenarios();known={sc.id};
assert(all(ismember(c.scenarioIds,known)),'SHT:Stage4:Scenario','scenarioIds包含未知架次。');
if ~isempty(c.scenarioIds),c.scenarioIds=known(ismember(known,c.scenarioIds));end
c.middle=fullfile(t,'MiddleData','stage4',c.runId);
c.data=fullfile(t,'TestData','stage4',c.runId);
c.report=fullfile(fileparts(t),'report_outputs','stage4',c.runId);
c.firstMeasurement=p.training;
% 历史F01输入不是当前运行包的输出。来源显式可选，合同仍逐文件冻结路径/SHA。
% 不向新包复制旧后验，也不为旧检查点重新签名；外部数据模式不读取这些结果。
assert(ischar(c.historicalInputRoot)||isstring(c.historicalInputRoot), ...
    'SHT:Stage4:HistoricalSource','historicalInputRoot必须为历史成果目录。');
c.historicalInputRoot=char(java.io.File(char(c.historicalInputRoot)).getCanonicalPath());
c.firstModel=fullfile(c.historicalInputRoot,'identification','delivery', ...
 'flight_model_adapt_3p3_transient_instant_steady_only_set1_R027_nodes_formal.xlsx');
c.firstResult=fullfile(c.historicalInputRoot,'identification', ...
 'flight_model_adapt_3p3_transient_instant_steady_only_set1_R027_nodes_latest.mat');
c.firstD=fullfile(c.historicalInputRoot,'uncertainty','F3_D_R031_nodes','3p4_method_D_local_delivery.xlsx');
c.fixedTransient=zeros(13,1); % 只固定推断端，绝不读取造数端热参数真值。
c.schema='STAGE4_AUTOMATIC_MODELING_V2';
end
