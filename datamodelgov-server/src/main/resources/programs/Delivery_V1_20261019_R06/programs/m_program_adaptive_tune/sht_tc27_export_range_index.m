function index=sht_tc27_export_range_index(prepared,outputFile,includeSmallHistory)
%SHT_TC27_EXPORT_RANGE_INDEX 仅导出05已选数据的来源和真实使用行号。
% 行号从原Excel的数据首行起按1计数，不包含表头；不是DLL积分步号。
% 历史prepared若未保存测试历程窗口，明确标记缺口，不反推不存在的索引。
if nargin<3,includeSmallHistory=true;end
assert(isstruct(prepared)&&isfield(prepared,'train')&&isfield(prepared,'testSets'), ...
    'TC27:Range:Prepared','缺少05阶段准备数据。');
assert(~isfile(outputFile),'TC27:Range:Exists','范围索引已存在：%s',outputFile);
segments=struct('role',{},'sourceName',{},'sourceFile',{},'sourceSHA256',{}, ...
    'segmentType',{},'segmentId',{},'start_s',{},'end_s',{}, ...
    'measurementSampleCount',{},'excelDataRow',{},'fitSourceRows',{}, ...
    'replaySourceRows',{},'usedForFit',{},'rangeStatus',{});
segments=append_points(segments,prepared.steady23,'training_original_points', ...
    'original_points',prepared.inputFiles.steadyTraining, ...
    prepared.inputFiles.steadyTrainingSHA256,true);
segments=append_history(segments,prepared.train,'training_new_history','train', ...
    prepared.inputFiles.trainingHistory,prepared.inputFiles.trainingHistorySHA256, ...
    true,includeSmallHistory);
for j=1:numel(prepared.testSets)
    test=prepared.testSets(j);
    if startsWith(test.name,'history_')||strcmp(test.name,'TC26')
        role='test_history';
    else
        role='test_points';
    end
    if strcmp(role,'test_points')
        segments=append_points(segments,test.means,role,test.name, ...
            test.sourceFile,test.sourceSHA256,false);
    else
        segments=append_history(segments,test,role,test.name, ...
            test.sourceFile,test.sourceSHA256,false,false);
    end
end
missing=sum(strcmp({segments.rangeStatus},'legacy_window_range_unavailable'));
sources=struct('role',{},'sourceName',{},'sourceFile',{},'sourceSHA256',{},'segmentCount',{});
sources(end+1)=source_row('training_original_points','original_points', ...
    prepared.inputFiles.steadyTraining,prepared.inputFiles.steadyTrainingSHA256,segments); %#ok<AGROW>
sources(end+1)=source_row('training_new_history','train', ...
    prepared.inputFiles.trainingHistory,prepared.inputFiles.trainingHistorySHA256,segments); %#ok<AGROW>
for j=1:numel(prepared.testSets)
    test=prepared.testSets(j);role='test_points';
    if startsWith(test.name,'history_')||strcmp(test.name,'TC26'),role='test_history';end
    sources(end+1)=source_row(role,test.name,test.sourceFile,test.sourceSHA256,segments); %#ok<AGROW>
end
index=struct('schema','TC27_SELECTED_RANGE_INDEX_V1', ...
    'rowBasis','one_based_excel_data_row_excluding_header', ...
    'timeUnit','s','sampleCountMeaning','recorded_measurement_samples', ...
    'completeRangeCoverage',missing==0,'missingWindowRangeCount',missing, ...
    'sources',sources,'segments',segments);
fid=fopen(outputFile,'w','n','UTF-8');
assert(fid>0,'TC27:Range:Write','无法写入范围索引：%s',outputFile);
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(index));
end

function source=source_row(role,name,file,sha,segments)
count=sum(strcmp({segments.role},role)&strcmp({segments.sourceName},name));
source=struct('role',role,'sourceName',name,'sourceFile',file, ...
    'sourceSHA256',sha,'segmentCount',count);
end

function segments=append_points(segments,points,role,name,file,sha,used)
for j=1:height(points)
    row=blank_row(role,name,file,sha,'aggregated_steady_point', ...
        char(string(points.point_id(j))),used);
    row.measurementSampleCount=double(points.sample_count(j));
    row.excelDataRow=j;
    row.rangeStatus='aggregated_mean_no_raw_time_axis';
    segments(end+1)=row; %#ok<AGROW>
end
end

function segments=append_history(segments,history,role,name,file,sha,steadyUsed,smallUsed)
if isfield(history,'windows')&&~isempty(history.windows)
    windows=history.windows;
    for j=1:height(windows)
        row=blank_row(role,name,file,sha,'steady_window', ...
            char(string(windows.point_id(j))),steadyUsed);
        row.start_s=double(windows.start_s(j));
        row.end_s=double(windows.end_s(j));
        row.measurementSampleCount=double(windows.sample_count(j));
        if isfield(history,'data')&&istable(history.data)
            rows=find(history.data.Time_s>=row.start_s&history.data.Time_s<=row.end_s).';
        elseif all(ismember({'source_first_row','source_last_row'},windows.Properties.VariableNames))
            rows=double(windows.source_first_row(j)):double(windows.source_last_row(j));
        else
            rows=[];
        end
        assert(numel(rows)==row.measurementSampleCount, ...
            'TC27:Range:WindowCount','稳态窗口%s的原记录行号与样本数不一致。',row.segmentId);
        row.fitSourceRows=rows;
        row.rangeStatus='exact_record_rows';
        segments(end+1)=row; %#ok<AGROW>
    end
elseif height(history.means)>0
    % 仅旧prepared缺测试窗口元数据；新05必须提供windows字段。
    for j=1:height(history.means)
        row=blank_row(role,name,file,sha,'steady_window', ...
            char(string(history.means.point_id(j))),steadyUsed);
        row.measurementSampleCount=double(history.means.sample_count(j));
        row.rangeStatus='legacy_window_range_unavailable';
        segments(end+1)=row; %#ok<AGROW>
    end
end
for j=1:numel(history.small)
    small=history.small(j);
    fit=double(small.fitIndices(:).');
    assert(~isempty(fit)&&all(fit==floor(fit))&& ...
        all(fit>=1)&&all(fit<=height(small.replayData)), ...
        'TC27:Range:FitIndices','小幅段%s的实际拟合索引无效。',small.id);
    firstReplayRow=double(small.first)-fit(1)+1;
    replayRows=firstReplayRow+(0:height(small.replayData)-1);
    fitRows=firstReplayRow+fit-1;
    assert(firstReplayRow>=1&&numel(fitRows)==height(small.data)&& ...
        isequaln(small.data.Time_s,small.replayData.Time_s(fit)), ...
        'TC27:Range:FitData','小幅段%s的拟合索引与原始数据不一致。',small.id);
    row=blank_row(role,name,file,sha,'small_change_fit',small.id,smallUsed);
    row.start_s=double(small.data.Time_s(1));
    row.end_s=double(small.data.Time_s(end));
    row.measurementSampleCount=numel(fitRows);
    row.fitSourceRows=fitRows;
    row.replaySourceRows=replayRows;
    row.rangeStatus='exact_record_rows';
    segments(end+1)=row; %#ok<AGROW>
end
end

function row=blank_row(role,name,file,sha,type,id,used)
row=struct('role',role,'sourceName',name,'sourceFile',file, ...
    'sourceSHA256',sha,'segmentType',type,'segmentId',id, ...
    'start_s',NaN,'end_s',NaN,'measurementSampleCount',0, ...
    'excelDataRow',0,'fitSourceRows',[],'replaySourceRows',[], ...
    'usedForFit',logical(used),'rangeStatus','');
end
