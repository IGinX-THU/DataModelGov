function result=Start_TC24_00_Offline(config)
% TC24离线独立入口，与界面调用共用04/05、07及独立预测核心。
% 无参数只显示说明，避免误启动长计算。配置见sht_tc24_offline_example。
if nargin==0
    fprintf('请先 config=sht_tc24_offline_example(pwd); 编辑路径后 Start_TC24_00_Offline(config)。\n');
    result=struct('status','configuration_required');return;
end
assert(isstruct(config)&&isscalar(config)&&isfield(config,'task'), ...
    'TC24:Offline:Configuration','需给定含task的配置结构体。');
switch lower(char(config.task))
    case 'preview'
        result=Start_TC24_01_PreprocessPreview(config.route,config.options);
    case 'stop'
        result=sht_tc24_run_control('requeststop',config.directory);
    case 'identify'
        assert(isfield(config,'route')&&isfield(config,'options'),'缺少route或options。');
        if strcmp(config.route,'steady'),result=Start_TC24_04_SteadyEstimation(config.options);
        elseif strcmp(config.route,'transient_instant'),result=Start_TC24_05_TransientInstantEstimation(config.options);
        else,error('TC24:Offline:Route','未知辨识路径。');end
    case 'predict'
        assert(isfield(config,'modelInput')&&~isempty(config.modelInput)&& ...
            isfield(config,'modelFile')&&~isempty(config.modelFile), ...
            'TC24:Offline:Prediction','必须明确模型Excel与新工况输入，不使用样例默认。');
        posterior=[];if isfield(config,'posterior'),posterior=config.posterior;end
        result=Start_SteadyModelPredict_01_InputDrivenPrediction( ...
            config.modelInput,config.modelFile,posterior,config.options);
    case 'uq'
        assert(isfield(config,'method')&&isfield(config,'options'),'缺少method或options。');
        result=Start_TC24_07_UncertaintyAssessment(config.method,config.options);
    case 'read'
        result=sht_tc24_result_view(config.resultFile,false);
    otherwise
        error('TC24:Offline:Task','task应为preview/identify/predict/uq/read/stop。');
end
end
