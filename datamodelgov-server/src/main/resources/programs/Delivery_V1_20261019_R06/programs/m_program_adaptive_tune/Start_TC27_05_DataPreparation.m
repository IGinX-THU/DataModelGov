function result=Start_TC27_05_DataPreparation(options)
%START_TC27_05_DATAPREPARATION 只从三部件测量Excel识别完整有效窗口。
% 不读取造数标签。稳态段两端保护1秒，无最大时长；小幅段同样不限最长。
if nargin<1,options=struct();end
explicit=isfield(options,'explicitInputs')&&options.explicitInputs;
if explicit
    % 05可以独立使用，但须沿用06的显式输入检查，不允许漏项回退样例。
    options=sht_tc27_estimation_options('transient_instant','II',options);
end
% 与06/07使用同一默认批次；显式outputBatch仍优先，不回写历史R020。
current=sht_tc27_estimation_options('transient_instant','II');
defaults=struct('minimumSteadyDuration_s',10,'minimumSmallDuration_s',10, ...
    'steadyGuard_s',1,'initializationExclusion_s',5,'screeningLevel','S3', ...
    'clusterSpan',.02,'plot',true,'outputBatch',current.outputBatch);
fields=fieldnames(defaults);for j=1:numel(fields),if ~isfield(options,fields{j}),options.(fields{j})=defaults.(fields{j});end,end
assert(ismember(options.minimumSteadyDuration_s,[5,10,15,20]) && ...
    ismember(options.minimumSmallDuration_s,[5,10,15,20]),'最小时长采用5/10/15/20秒挡位。');
p=sht_tc27_paths(options);result=struct('options',options,'hiddenTruthRead',false,'hiddenLabelsRead',false);
if explicit
    trainFile=char(string(options.trainingHistoryFile));
    pointFile=char(string(options.steadyTrainingFile));
else
    trainFile=p.trainingFile;pointFile=fullfile(p.data,'tc24_training_means.xlsx');
end
result.train=local_history(trainFile,options,'train',p);
result.inputFiles=struct('trainingHistory',trainFile,'trainingHistorySHA256', ...
    sht_tc27_file_identity(trainFile),'steadyTraining',pointFile, ...
    'steadyTrainingSHA256',sht_tc27_file_identity(pointFile));
result.steady23=readtable(pointFile);
% 本任务GT附件功率恒为0，不存在独立Mkg测量列；只作为模型边界补零。
if ~ismember('Mkg_mean',result.steady23.Properties.VariableNames)
    result.steady23.Mkg_mean=zeros(height(result.steady23),1);
end
% 保留可测量列与完整样本数，禁止为空的历史Pt3/Tt3等占位列进入残差。
names=result.train.means.Properties.VariableNames;
if isempty(names),names=result.steady23.Properties.VariableNames;end
assert(all(ismember(names,result.steady23.Properties.VariableNames)), ...
    'TC24/TC27均值缺少：%s',strjoin(setdiff(names,result.steady23.Properties.VariableNames),','));
result.steady23=result.steady23(:,names);
local_check_points(result.steady23,pointFile);
if isempty(result.train.means.Properties.VariableNames)
    result.train.means=result.steady23([],:);
end
result.combinedSteady=[result.steady23;result.train.means];
result.source=[ones(height(result.steady23),1);2*ones(height(result.train.means),1)];
result.testSets=struct('name',{},'means',{},'small',{},'sourceFile',{},'sourceSHA256',{},'windows',{});
if explicit
    for j=1:numel(options.testPointFiles)
        file=char(string(options.testPointFiles{j}));t=readtable(file);
        if ~ismember('Mkg_mean',t.Properties.VariableNames),t.Mkg_mean=zeros(height(t),1);end
        assert(all(ismember(names,t.Properties.VariableNames)), ...
            'TC27:Data:TestColumns','测试稳态点缺少训练测量字段：%s',file);
        t=t(:,names);local_check_points(t,file);
        result.testSets(end+1)=struct('name',sprintf('points_%02d',j), ...
            'means',t,'small',[],'sourceFile',file, ...
            'sourceSHA256',sht_tc27_file_identity(file),'windows',table()); %#ok<AGROW>
    end
    for j=1:numel(options.testHistoryFiles)
        file=char(string(options.testHistoryFiles{j}));name=sprintf('history_%02d',j);
        r=local_history(file,options,name,p);
        result.testSets(end+1)=struct('name',name,'means',r.means, ...
            'small',r.small,'sourceFile',file, ...
            'sourceSHA256',sht_tc27_file_identity(file), ...
            'windows',local_index_windows(r)); %#ok<AGROW>
    end
else
    result.test=local_history(p.testFile,options,'test',p);
    t=readtable(fullfile(p.data,'tc24_test_means.xlsx'));
    if ~ismember('Mkg_mean',t.Properties.VariableNames),t.Mkg_mean=zeros(height(t),1);end
    result.testSets(1)=struct('name','TC23','means',t,'small',[], ...
        'sourceFile',fullfile(p.data,'tc24_test_means.xlsx'), ...
        'sourceSHA256',sht_tc27_file_identity(fullfile(p.data,'tc24_test_means.xlsx')), ...
        'windows',table());
    result.testSets(2)=struct('name','TC26','means',result.test.means, ...
        'small',result.test.small,'sourceFile',p.testFile, ...
        'sourceSHA256',sht_tc27_file_identity(p.testFile), ...
        'windows',local_index_windows(result.test));
end
x=result.combinedSteady.Ng_mean/38000.*sqrt(288.15./result.combinedSteady.Tt1_mean);
[sorted,order]=sort(x);group=zeros(size(x));first=1;g=0;
while first<=numel(x)
    g=g+1;last=first;while last<numel(x)&&sorted(last+1)-sorted(first)<=options.clusterSpan,last=last+1;end
    group(order(first:last))=g;first=last+1;
end
result.groupIndex=group;result.hpcCorrectedSpeed=x;result.groupCount=g;
result.groups=table((1:g).',accumarray(group,1),accumarray(group,x,[],@mean), ...
    accumarray(group,x,[],@min),accumarray(group,x,[],@max),'VariableNames', ...
    {'group','pointCount','hpcNcrMean','hpcNcrMin','hpcNcrMax'});
if explicit
    % 导出索引只描述05已经选定的数据，不参与分组或物理残差。
    result.rangeIndexGeneratorSHA256=sht_tc27_file_identity( ...
        fullfile(fileparts(mfilename('fullpath')),'sht_tc27_export_range_index.m'));
    result.rangeIndexFile=fullfile(p.report,'TC27_05_selected_ranges.json');
    result.rangeIndex=sht_tc27_export_range_index(result,result.rangeIndexFile, ...
        options.includeSmallHistory);
    assert(result.rangeIndex.completeRangeCoverage, ...
        'TC27:Data:RangeCoverage','新准备结果存在无法追溯的测试窗口范围。');
end
disp(result.groups);save(fullfile(p.middle,'tc27_prepared_data.mat'),'result','-v7.3');
writetable(result.groups,fullfile(p.report,'TC27_05_groups.csv'));
end

function windows=local_index_windows(r)
% 测试历程的时间范围与原Excel记录行号随prepared保存，避免事后猜测。
windows=r.windows;
first=zeros(height(windows),1);last=first;
for j=1:height(windows)
    rows=find(r.data.Time_s>=windows.start_s(j)&r.data.Time_s<=windows.end_s(j));
    assert(numel(rows)==windows.sample_count(j),'TC27:Data:WindowRows', ...
        '测试窗口%s的记录行号与样本数不一致。',char(string(windows.point_id(j))));
    first(j)=rows(1);last(j)=rows(end);
end
windows.source_first_row=first;windows.source_last_row=last;
end

function r=local_history(file,options,kind,p)
assert(isfile(file),'TC27:Data:HistoryMissing','试车历程文件不存在：%s',file);
t=readtable(file);r=sht_tc27_segment_history(t,options,kind);
writetable(r.windows,fullfile(p.report,['TC27_05_',kind,'_steady_windows.csv']));
if height(r.means)>0,writetable(r.means,fullfile(p.middle,['tc27_',kind,'_steady_means.xlsx']));end
if height(r.events)>0,writetable(r.events,fullfile(p.report,['TC27_05_',kind,'_events.csv']));end
fprintf('TC27-05 %s: %d个稳态窗口，%d个小幅历程。\n',kind,height(r.windows),numel(r.small));
if options.plot,local_plot(r,p.report,kind);end
end

function local_check_points(t,file)
assert(all(ismember({'point_id','sample_count'},t.Properties.VariableNames))&& ...
    height(t)>0&&numel(unique(string(t.point_id)))==height(t)&& ...
    all(isfinite(t.sample_count))&&all(t.sample_count>=2)&& ...
    all(t.sample_count==floor(t.sample_count)), ...
    'TC27:Data:Points','稳态点编号或完整有效窗口样本数无效：%s',file);
end

function local_plot(r,directory,kind)
f=figure('Name',['TC27 selected ',kind],'Position',[100,100,1100,800]);
fields={'Np','Mkp','Wf','Tt45'};
for j=1:4
    subplot(4,1,j);plot(r.data.Time_s,r.data.(fields{j}),'Color',[.6,.6,.6]);hold on;
    v=r.data.(fields{j});v(r.labels~="steady")=NaN;plot(r.data.Time_s,v,'g-','LineWidth',1.1);
    v=r.data.(fields{j});v(r.labels~="small_change")=NaN;plot(r.data.Time_s,v,'b-','LineWidth',1.1);
    v=r.data.(fields{j});v(~r.diagnostic.eventFitMask)=NaN;plot(r.data.Time_s,v,'Color',[.8,.3,.1]);
    ylabel(fields{j});grid on;
end
xlabel('Time / s');legend('Complete record','Steady','Small change','Event fit (including platform/recovery)');
print(f,fullfile(directory,['TC27_05_',kind,'_segments.png']),'-dpng','-r150');
end
