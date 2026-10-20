function result = Start_DesignPoint_SimpleTest(taskDirectory,source)
%START_DESIGNPOINT_SIMPLETEST 复现已生成的设计点，不重新辨识/重新求解。
% source='candidate'测试私有配置；'committed'测试备份写入后的选定MDL。
% 共同工作残差、缩放系数、截面量与独立配平沿用原设计程序判据。
if nargin<2,source='candidate';end
result=sht_design_point_task('test',taskDirectory,source);
fprintf('设计点简单测试通过：%d；耗时：%.3f s。\n',result.lastTest.accepted,result.lastTest.elapsedSeconds);
end
