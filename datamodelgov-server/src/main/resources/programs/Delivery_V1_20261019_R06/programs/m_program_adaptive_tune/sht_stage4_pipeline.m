function result=sht_stage4_pipeline(action,user)
% 第4阶段单步与全流程使用相同的批次合同和依赖预检。
if nargin<2,user=struct();end
c=sht_stage4_config(user);
switch lower(action)
    case 'prepare'
        plan=sht_stage4_guard('prepare',c);
        sht_r2019b_preflight();
        for f={c.middle,c.data,c.report},if ~isfolder(f{1}),mkdir(f{1});end;end
        sht_stage4_guard('freeze',c);
        sc=sht_stage4_scenarios();sc=sc(ismember({sc.id},plan.ids));
        t=struct2table(rmfield(sc,{'definition','healthOffset'}));
        writetable(t,fullfile(c.report,['scenario_plan_',plan.scopeTag,'.csv']));
        result=struct('configuration',c,'plan',plan,'scenarios',sc,'stage','prepared');
        fprintf('第4阶段所选架次：%s。父模型只读复用；缺项不自动生成。\n',strjoin(plan.ids,', '));
    case 'generate'
        result=sht_stage4_generate(user);
    case 'estimate'
        result=sht_stage4_estimate(user);
    case 'predict'
        result=sht_stage4_predict(user);
    case 'report'
        result=sht_stage4_report(user);
    case 'all'
        % 在任何造数/辨识之前检查整条所选流程，不等到预测才发现缺项。
        sht_stage4_guard('all',c);
        sht_stage4_pipeline('prepare',user);
        sht_stage4_generate(user);
        sht_stage4_estimate(user);
        sht_stage4_predict(user);
        result=sht_stage4_report(user);
    otherwise
        error('SHT:Stage4:Action','未知步骤%s。',action);
end
end
