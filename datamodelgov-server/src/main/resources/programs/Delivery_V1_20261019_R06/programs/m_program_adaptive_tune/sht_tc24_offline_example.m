function config=sht_tc24_offline_example(workDirectory,task)
% 独立工作目录例子。仅构造配置，不启动辨识；请换成自己的Excel。
if nargin<1,workDirectory=pwd;end
if nargin<2,task='identify';end
workDirectory=sht_tc24_absolute_path(workDirectory);
if strcmpi(task,'uq')
    config=struct('task','uq','method','B');
    config.options=sht_tc24_b_config();
    config.options.trainingFile=fullfile(workDirectory,'训练数据.xlsx');
    config.options.testFile='';
    config.options.deterministicWorkbookFile=fullfile(workDirectory,'辨识模型.xlsx');
    config.options.outputDirectory=fullfile(workDirectory,'results');
    config.options.runId=['tc24_b_user_',datestr(now,'yyyymmdd_HHMMSS_FFF')];
    config.options.progressCallback=[];
    config.options.resume=false;
    return;
end
assert(strcmpi(task,'identify'),'TC24:Offline:ExampleTask','示例task请选择identify或uq。');
config=struct('task','identify','route','steady');
config.options=sht_tc24_estimation_options(config.route);
config.options.trainingFile=fullfile(workDirectory,'训练数据.xlsx');
config.options.testFile=''; % 无测试集合法；有时填路径，训练与测试分别显示。
config.options.outputDirectory=fullfile(workDirectory,'results');
config.options.runId=['tc24_user_',datestr(now,'yyyymmdd_HHMMSS')];
config.options.plotEnabled=false;
config.options.progressCallback=[]; % 可选 @myProgress，不依赖任何GUI句柄。
config.options.enableRunControl=true;
config.options.resume=false; % 同一任务安全停止后，保持全部算法配置并置true。
config.options.preparedInput=''; % 可填同配置Start_TC24_01_PreprocessPreview返回的file。
config.options.timingHistoryDirectory=fullfile(workDirectory,'timing_history');
end
