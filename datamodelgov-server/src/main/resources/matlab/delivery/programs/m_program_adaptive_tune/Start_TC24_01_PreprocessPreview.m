function preview=Start_TC24_01_PreprocessPreview(route,user)
% 独立预览真实A前准备；不运行A/B/C/D，不改试车Excel，不构造隐藏真值。
% 输入仍是完整有效段均值和实际sample_count，不在此做2.7历程选段。
if nargin<1,route='steady';end
if nargin<2,user=struct();end
o=sht_tc24_estimation_options(route,user);
assert(isfield(user,'trainingFile')&&isfield(user,'outputDirectory')&& ...
    ~isempty(user.trainingFile)&&~isempty(user.outputDirectory), ...
    'TC24:Preview:Inputs','预览需明确训练Excel和独立输出根。');
o.trainingFile=sht_tc24_absolute_path(o.trainingFile);
if isfield(user,'testFile'),o.evaluateTestSet=~isempty(user.testFile);end
if o.evaluateTestSet,o.testFile=sht_tc24_absolute_path(o.testFile);end
sht_tc24_validate_measurements(o.trainingFile);
if o.evaluateTestSet,sht_tc24_validate_measurements(o.testFile);end
assert(isempty(o.pt1TruthFile),'TC24:Preview:Truth','正式预览不能读取真值边界。');
if isempty(o.runId),o.runId=['tc24_preview_',datestr(now,'yyyymmdd_HHMMSS')];end
o.preparedInput='';o.enableRunControl=false;o.resume=false;
session=sht_tc24_execution(o,['preview_',route]);o.progressCallback=session.notify;
try
    if strcmp(o.nodeReferencePolicy,'fixed_engineering')&&isempty(fieldnames(o.nodeEngineeringReference))
        r=sht_tc24_node_engineering_reference(false,o);
        o.nodeEngineeringReference=r.axes;o.nodeEngineeringReferenceSource=r.signature;
    end
    preview=sht_steady_model_adapt_v2_common('prepare',route,o);
    preview.file=fullfile(session.directory,'preview.mat');
    preview.execution=session.snapshot('completed','preprocessing_ready');
    save(preview.file,'preview','-v7.3');
    preview.execution=session.finish('completed','preprocessing_ready',preview.execution);
    fprintf('预览：%d训练点，%d测试点，%d组。复用文件：%s\n', ...
        height(preview.trainingData),height(preview.testData),height(preview.groups),preview.file);
catch err
    session.finish('failed',[err.identifier,': ',err.message]);rethrow(err);
end
end
