function result=Start_Stage4_01_AutomaticModeling(options)
% 一次选择后串行完成4step1至4step5；已完成阶段按身份核对后继续。
% 默认合成演示包括5个正常架次、F05三种平行故障和F06两种预测。
% 无测试集不等于独立验证通过；D是快速局部评估，不是全局校准后验。
% 首次示例：o=struct('runId','T4_R011_demo','scenarioIds',{{'F01','F02'}});
% sht_stage4_pipeline('prepare',o); sht_stage4_pipeline('generate',o);
% estimate仅更新所选架次；父模型须已有或在同次选择中先完成。
% F05子集只比较所选场景；选F06才冻结正常五架次趋势和进行两种预测。
% 外部数据在prepare中一次声明本批全部文件；改变路径/内容/配置须新runId。
% 旧T4_R008B只读保留，不使用本入口给旧结果重签合同。
% 起停合并不启用起动/暖机/停车。控制增益表变化须新批次；孤立预处理不可续用。
if nargin<1,options=struct();end
result=sht_stage4_pipeline('all',options);
end
