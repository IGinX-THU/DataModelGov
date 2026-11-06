function cfg=sht_tc24_uq_business_inputs(cfg,user)
% 显式选择观测口径；默认保持既有瞬态时刻，不根据文件名偷偷切换路径。
if ~isfield(cfg,'route'),cfg.route='transient_instant';end
assert(ismember(cfg.route,{'steady','transient_instant'}),'TC24:UQ:Route','未知UQ观测路径。');
root=fileparts(mfilename('fullpath'));
business=isfield(user,'trainingFile')||isfield(user,'deterministicWorkbookFile');
if business
    assert(isfield(user,'trainingFile')&&~isempty(user.trainingFile) ...
        &&isfield(user,'deterministicWorkbookFile')&&~isempty(user.deterministicWorkbookFile) ...
        &&isfield(user,'outputDirectory')&&~isempty(user.outputDirectory), ...
        'TC24:UQ:Inputs','业务UQ需同时明确trainingFile、deterministicWorkbookFile和outputDirectory。');
end
if ~isfield(cfg,'trainingFile')||isempty(cfg.trainingFile)
    cfg.trainingFile=fullfile(root,'TestData','three_component','tc24_training_means.xlsx');
end
if ~isfield(cfg,'deterministicWorkbookFile')||isempty(cfg.deterministicWorkbookFile)
    cfg.deterministicWorkbookFile=fullfile(root,'MiddleData','three_component', ...
        'steady_model_2p4_delivery',['2p4_deterministic_',char(cfg.route),'.xlsx']);
end
cfg.trainingFile=sht_tc24_absolute_path(cfg.trainingFile);
cfg.deterministicWorkbookFile=sht_tc24_absolute_path(cfg.deterministicWorkbookFile);
if ~isfield(cfg,'testFile')
    cfg.testFile='';
    if ~business,cfg.testFile=fullfile(root,'TestData','three_component','tc24_test_means.xlsx');end
end
if ~isempty(cfg.testFile),cfg.testFile=sht_tc24_absolute_path(cfg.testFile);end
if isfield(cfg,'outputDirectory')&&~isempty(cfg.outputDirectory)
    cfg.outputDirectory=sht_tc24_absolute_path(cfg.outputDirectory);
end
sht_tc24_validate_measurements(cfg.trainingFile);
if ~isempty(cfg.testFile),sht_tc24_validate_measurements(cfg.testFile);end
% progressCallback只用于调用方事件，不进入概率合同、缓存身份或保存的函数闭包。
if isfield(cfg,'progressCallback'),cfg=rmfield(cfg,'progressCallback');end
end
