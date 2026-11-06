function sht_tc27_uq_check_prepared_data(input,prepared,kind)
%SHT_TC27_UQ_CHECK_PREPARED_DATA 防止新Excel与旧预处理MAT组成虚假新合同。
% 只核对当前步骤允许读取的数据。推断检查训练集；测试集在预测开始后
% 才检查。数据改变后必须先重新执行05，不能仅换一个文件哈希继续采样。
if strcmp(kind,'train')
    raw=readtable(input.trainingHistoryFile);record=prepared.train;
    steady=readtable(input.steadyTrainingFile);
    assert(isfield(prepared,'inputFiles')&& ...
        strcmpi(prepared.inputFiles.trainingHistorySHA256, ...
        sht_tc27_file_identity(input.trainingHistoryFile))&& ...
        strcmpi(prepared.inputFiles.steadyTrainingSHA256, ...
        sht_tc27_file_identity(input.steadyTrainingFile)), ...
        'TC27:UQ:StalePreprocessing','训练Excel与准备缓存文件身份不一致。');
    if ~ismember('Mkg_mean',steady.Properties.VariableNames),steady.Mkg_mean=zeros(height(steady),1);end
    fields=prepared.steady23.Properties.VariableNames;
    assert(all(ismember(fields,steady.Properties.VariableNames)),'TC27:UQ:StalePreprocessing', ...
        '当前TC24测量列与预处理结果不一致，请重新执行Start_TC27_05_DataPreparation。');
    valid=isequaln(steady(:,fields),prepared.steady23)&& ...
        isequaln(prepared.combinedSteady,[prepared.steady23;prepared.train.means])&& ...
        isequal(prepared.source,[ones(height(prepared.steady23),1);2*ones(height(prepared.train.means),1)]);
elseif strcmp(kind,'test')
    files=[input.testPointFiles(:);input.testHistoryFiles(:)];
    assert(numel(files)==numel(prepared.testSets), ...
        'TC27:UQ:StalePreprocessing','测试来源个数与准备缓存不一致。');
    for j=1:numel(files)
        file=char(string(files{j}));
        assert(strcmpi(sht_tc27_file_identity(file),prepared.testSets(j).sourceSHA256), ...
            'TC27:UQ:StalePreprocessing','测试Excel已变化：%s',file);
    end
    return;
else,error('TC27:UQ:DataKind','数据检查只允许train/test。');
end
valid=valid&&isequaln(raw,record.data);
for j=1:numel(record.small)
    item=record.small(j);
    valid=valid&&isequaln(item.data,record.data(item.first:item.last,:));
end
assert(valid,'TC27:UQ:StalePreprocessing', ...
    '当前%s Excel与已选择数据不一致，请先重新执行Start_TC27_05_DataPreparation，并核实确定性输入。',kind);
end
