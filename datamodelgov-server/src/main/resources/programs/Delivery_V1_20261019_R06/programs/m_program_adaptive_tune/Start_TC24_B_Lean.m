function result=Start_TC24_B_Lean(user)
% 兼容精简B入口，仍调用同一个界面/离线核心，不复制求解算法。
% trainingFile、deterministicWorkbookFile、outputDirectory必须显式配置。
if nargin<1,user=struct();end
required={'trainingFile','deterministicWorkbookFile','outputDirectory'};
for k=1:numel(required)
    assert(isfield(user,required{k})&&~isempty(user.(required{k})), ...
        'TC24:B:BusinessInput','缺少显式业务配置%s。',required{k});
end
result=Start_TC24_07_UncertaintyAssessment('B',user);
end
