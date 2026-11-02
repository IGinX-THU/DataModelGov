function view=Start_TC27_TransientResultView_01(outputDirectory,makePlot,executionOptions)
%START_TC27_TRANSIENTRESULTVIEW_01 脱离辨识会话查看已保存模型、误差和训练曲线。
% executionOptions.runtimeDirectory只定位原生成包；不重算、不改写旧身份。
if nargin<2,makePlot=false;end
if nargin<3||isempty(executionOptions),executionOptions=struct();end
assert(isstruct(executionOptions)&&isscalar(executionOptions)&& ...
    all(ismember(fieldnames(executionOptions),{'runtimeDirectory'})), ...
    'TC27:TransientUI:ViewOptions','查看选项只允许runtimeDirectory。');
directory=sht_tc27_canonical_path(outputDirectory);
summary=fullfile(directory,'MiddleData','tc27_transient_ui_result.mat');
assert(isfile(summary),'TC27:TransientUI:Result','没有可独立读取的已完成结果。');
saved=load(summary,'result');r=saved.result;
modelFile=fullfile(directory,'MiddleData','tc27_combined_transient_model.xlsx');
model=sht_tc27_transient_combined_delivery('read',[],modelFile,executionOptions);
assert(strcmpi(model.sha256,r.modelSHA256),'TC27:TransientUI:Result', ...
    '组合模型已改变，拒绝显示旧结果。');
curveDirectory=fullfile(directory,'report_outputs',r.runId);
curves=dir(fullfile(curveDirectory,'training_fit_*.csv'));
assert(~isempty(curves),'TC27:TransientUI:Result','缺少必需的训练拟合曲线。');
baselineMetrics=local_field(r,'trainingBaselineMetrics',table());
baselineAvailable=~isempty(baselineMetrics);
channels={'Np','Ng','Tt45','Pt45'};
for j=1:numel(curves)
    curve=readtable(fullfile(curveDirectory,curves(j).name));
    for c=1:numel(channels)
        name=channels{c};
        assert(ismember(['measured_',name],curve.Properties.VariableNames)&& ...
            ismember(['predicted_',name],curve.Properties.VariableNames), ...
            'TC27:TransientUI:Result','训练曲线缺少必需的测量或拟合列。');
        baselineAvailable=baselineAvailable&& ...
            ismember(['steady_only_',name],curve.Properties.VariableNames);
    end
end
if baselineAvailable,baselineStatus='available';
else,baselineStatus='baseline_unavailable';end
view=struct('status',r.status,'runId',r.runId,'modelFile',modelFile, ...
    'modelSHA256',model.sha256,'model',model,'parameters',r.parameters, ...
    'runtimePackageId',model.runtimePackageId, ...
    'runtimeManifestSHA256',model.runtimeManifestSHA256, ...
    'physicalEvaluationPerformed',false,'internalMatRead',true, ...
    'trainingMetrics',r.trainingMetrics,'trainingBaselineMetrics',baselineMetrics, ...
    'baselineStatus',baselineStatus,'testMetrics',r.testMetrics, ...
    'selection',r.selection,'stopReason',r.stopReason,'converged',r.converged, ...
    'iterationCount',local_field(r,'iterationCount',NaN), ...
    'stationarityPassed',local_field(r,'stationarityPassed',NaN), ...
    'fitDllEvaluationCount',local_field(r,'fitDllEvaluationCount',NaN), ...
    'actualElapsed_s',r.actualElapsed_s,'estimatedTime',r.estimatedTime, ...
    'estimatedBefore',local_field(r,'estimatedBefore',[]), ...
    'estimatedAfter',local_field(r,'estimatedAfter',[]), ...
    'trainingCurveFiles',{arrayfun(@(q)fullfile(curveDirectory,q.name),curves, ...
    'UniformOutput',false)});
fprintf('瞬态模型%s；%d段训练曲线；收敛=%d；停止原因=%s。\n', ...
    modelFile,numel(curves),view.converged,view.stopReason);
disp(view.parameters);disp(view.trainingMetrics);
if ~isempty(view.testMetrics),disp(view.testMetrics);end
if makePlot
    for j=1:numel(curves)
        t=readtable(view.trainingCurveFiles{j});
        f=figure('Name',sprintf('TC27 fit %02d',j),'Position',[60,60,1200,600]);
        tiledlayout(2,2);
        for c=1:4
            name=channels{c};nexttile;
            plot(t.Time_s,t.(['measured_',name]),'k-');hold on;
            if baselineAvailable
                plot(t.Time_s,t.(['steady_only_',name]),'b-');
            end
            plot(t.Time_s,t.(['predicted_',name]),'r-');grid on;
            title(name,'Interpreter','none');
            if baselineAvailable,legend('测量','仅稳态修正','瞬态修正后');
            else,legend('测量','瞬态修正后');end
        end
        print(f,fullfile(curveDirectory,sprintf('training_fit_%02d.png',j)),'-dpng','-r140');
    end
end
end

function value=local_field(s,name,fallback)
value=fallback;if isfield(s,name),value=s.(name);end
end
