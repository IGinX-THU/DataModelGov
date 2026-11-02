function result=Start_TC27_UQ_RequestStop_01(outputDirectory)
%START_TC27_UQ_REQUESTSTOP_01 请求在完整D迭代或C温度层后安全停止。
assert(nargin==1&&~isempty(outputDirectory),'TC27:UQ:StopDirectory', ...
    '必须指定当前UQ任务的独立输出目录。');
result=sht_tc24_run_control('requeststop',char(string(outputDirectory)));
end
