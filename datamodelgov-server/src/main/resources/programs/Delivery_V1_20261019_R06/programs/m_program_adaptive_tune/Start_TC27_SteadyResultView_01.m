function result=Start_TC27_SteadyResultView_01(outputDirectory,makePlots)
%START_TC27_STEADYRESULTVIEW_01 独立读取已经保存的结果，不重新调用DLL。
if nargin<2,makePlots=false;end
outputDirectory=char(string(outputDirectory));
folder=fullfile(outputDirectory,'MiddleData');
files=dir(fullfile(folder,'*_ui_result.mat'));
assert(numel(files)==1,'TC27:View:File','未找到唯一的稳态更新结果MAT。');
loaded=load(fullfile(folder,files(1).name),'result');result=loaded.result;
if ~isfile(result.deliveryFile)
    [~,name,ext]=fileparts(result.deliveryFile);
    relocated=fullfile(folder,[name,ext]);
    if isfile(relocated),result.deliveryFile=relocated;end
end
assert(isfield(result,'deliveryFile')&&isfile(result.deliveryFile)&& ...
    strcmpi(result.deliverySHA256,sht_tc27_file_identity(result.deliveryFile)), ...
    'TC27:View:Delivery','正式模型Excel缺失或内容已变化。');
model=sht_tc27_delivery('read',[],result.deliveryFile);
fprintf('模型：%s，路径%s，方法%s，停止原因%s。\n', ...
    result.deliveryFile,result.route,result.method,result.stopReason);
if isfield(result.fit.validation,'testSources')
    testCount=numel(result.fit.validation.testSources);
else
    testCount=size(result.fit.validation.steady,1);
end
fprintf('总用时 %.1f s；参数%d条调度曲线、燃油偏置%d个节点；测试源%d个。\n', ...
    result.elapsed_s,numel(model.finalSchedule.healthEntries), ...
    numel(model.finalSchedule.fuelBias.xNodes),testCount);
disp(result.trainingMetrics);
if ~isempty(result.testMetrics),disp(result.testMetrics);end
if ~isempty(result.smallHistoryTestMetrics),disp(result.smallHistoryTestMetrics);end
if ~makePlots,return;end
plots=fullfile(outputDirectory,'report_outputs','view_plots');
if ~isfolder(plots),mkdir(plots);end
entries=model.finalSchedule.healthEntries;
for j=1:numel(entries)
    f=figure('Visible','off');plot(entries(j).xNodes,entries(j).kNodes,'o-');
    xlabel(entries(j).axisName);ylabel(entries(j).name);grid on;
    print(f,fullfile(plots,sprintf('coefficient_%02d.png',entries(j).cIndex)), ...
        '-dpng','-r130');close(f);
end
end
