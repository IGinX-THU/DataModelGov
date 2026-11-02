function out = Start_Stage4_02_EvolutionTask(action, configuration, selection)
%START_STAGE4_02_EVOLUTIONTASK 发动机个性化模型自演化，界面与离线共用入口。
% 无参数只返回集中配置模板，绝不选择演示数据、补零根模型或启动计算。
%   c = Start_Stage4_02_EvolutionTask();
%   % 显式填写c的发动机、试车根、架次和输出目录，再按顺序操作：
%   check = Start_Stage4_02_EvolutionTask('check', c);
%   preview = Start_Stage4_02_EvolutionTask('preview', c, struct('sortieId', '自定义架次'));
%   % selection.windows.identification = 用户已核对的完整segment_id列表。
%   intent = Start_Stage4_02_EvolutionTask('confirm', c, selection);
%   % 父模型已经存在时可先绑定，获取实际参数维数及修订估时：
%   receipt = Start_Stage4_02_EvolutionTask('bindParent', c, selection);
%   estimate = Start_Stage4_02_EvolutionTask('estimateTime', c);
%   result = Start_Stage4_02_EvolutionTask('run', c);
% 后续架次的父模型未生成时，只confirm数据意图；run按已登记父链顺序
% 生成真实绑定。缺少未选择的父模型会在计算开始前明确报出依赖。
% maximumSortiesPerSession=0不限制；正整数在交付该数量的新架次后安全
% 停于架次边界，再用同一配置resume，不重新计算已完成架次。
% status/readResult/parameters/requestPause仅需resultDirectory和可选sortieId。
% exportIndex核对已保存模型后导出版本化Excel索引，不重新辨识或加载DLL。
% trend需要显式historyIds，按同一物理坐标查询，不按节点编号连线。
% freezePrediction只形成保持/趋势两个Excel模型，不等于输出已经算出。
% 根模型source='combined'使用经过Owner验证的组合Excel及同目录稳态
% 载体。13项瞬态值逐架次继承，不能用稳态载体单独替代组合父模型。
% uqConfiguration返回独立UQ模板；uqPreview/uqConfirm重新确认本次
% 评估观测并绑定目标模型；原辨识确认不改签，也不伪造新的子模型。
% uqCheck/uqEstimateTime/uqRun/uqResume
% 使用显式概率先验，不自动把确定性父或上一架次UQ作为概率先验。
% uqStatus/uqRead/uqRequestPause使用uqDirectory，不改已合法的本架次模型。
% uqRecords使用resultDirectory/sortieId，只列实际登记任务；读取区间另用uqRead。
% predictionConfiguration返回双方法输入驱动预测配置，须先freezePrediction。
% predictionCheck/predictionEstimateTime无DLL；predictionRun/Resume实际
% 调用Start13积分。显式给相同两轴、14热、4传感器和6共同工作初态，
% 输入Excel只有环境、燃油、负载历程，不伪造未来Np/Ng测量列。
% predictionOutputStatus/readPredictionOutput只读已算输出；requestPause
% 对应predictionRequestPause，只能在两方法之间安全暂停，无历程内部续算。
% predictionEvaluate另行给后补观测，评价不反向改模型或自动选胜者。
% readPredictionEvaluation只读独立评价目录，不要求原观测仍在线。
% exportConfiguration/loadConfiguration支持UTF-8 JSON集中配置；读历史
% 结果不要求源数据在线，重新计算/恢复仍严格核输入和源码身份。
% B1/B2/B3是业务开发批次，不是历史A/B算法。算法仍由F3等Owner维护。
if nargin < 1, action = 'configuration'; end
if nargin < 2, configuration = struct(); end
if nargin < 3, selection = struct(); end
out = sht_stage4_evolution_task(action, configuration, selection);
end
