function result=Start_FlightModelAdapt_15_UncertaintyTask(action,configuration)
%START_FLIGHTMODELADAPT_15_UNCERTAINTYTASK 第3步不确定性任务离线入口。
% check/estimate只核冻结B/A、上游后验与新目录，不调用DLL；
% run调用现有C/D算法；resume核对同批完整身份后冷恢复。
% status/requestPause仅需outputRoot；暂停在完整迭代/粒子层响应。
% read仅需workbook，可搬迁查看，不需要原训练MAT。
% C1只实现平均稳态点。独立测试在推断冻结后另行运行，不进入概率先验。
% businessIdentity按所选A/B/父文件绑定engineId、sortieId、parentModelId及
% parentPosteriorId。缺项须显式赋值并在basis同名字段说明依据；与证据
% 冲突即拒绝。默认production不能使用开发默认编号，test_fixture仅用于
% 明确标记的接口试验，不得作为真实发动机的下一架次先验。
assert(nargin==2,'SHT:F3UQ:Required','请显式给出动作和配置。');
assert(ismember(lower(char(action)),{'check','estimate','run','resume','status','requestpause','read'}), ...
    'SHT:F3UQ:Action','动作应为check、estimate、run、resume、status、requestPause或read。');
result=sht_f3_steady_task(['uq',lower(char(action))],configuration);
end
