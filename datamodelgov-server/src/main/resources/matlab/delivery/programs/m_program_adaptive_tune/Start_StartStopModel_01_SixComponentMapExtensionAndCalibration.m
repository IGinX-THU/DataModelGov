function result = Start_StartStopModel_01_SixComponentMapExtensionAndCalibration(userCfg)
%START_STARTSTOPMODEL_01_SIXCOMPONENTMAPEXTENSIONANDCALIBRATION
% 起动停车阶段一、二正式入口：验收特性图读写并生成六部件低速扩展图。
%
% 运行方法：
%   result = Start_StartStopModel_01_SixComponentMapExtensionAndCalibration();
%
% 可选 userCfg 仅覆盖 sht_startstop_default_config 中的同名字段。程序
% 每次建立独立时间戳结果目录，不覆盖输入特性图，也不修改正式 MDL。

if nargin < 1
    userCfg = struct();
end

cfg = sht_startstop_default_config(userCfg);
timeTag = datestr(now, 'yyyymmdd_HHMMSS');
runRoot = fullfile(cfg.paths.outputRoot, ['Stage12_', timeTag]);
if ~isfolder(runRoot)
    mkdir(runRoot);
end

fprintf('\n=== 起动停车阶段一/二：特性图读写与低速扩展 ===\n');
fprintf('结果目录：%s\n', runRoot);
mapResult = sht_startstop_run_map_stages(cfg, runRoot);
if ~mapResult.stage1Accepted || ~mapResult.stage2Accepted
    error('sht:startStop:mapAcceptanceFailed', ...
        '阶段一/二验收未通过，请查看：%s', mapResult.summaryPath);
end

runtime = sht_startstop_create_runtime(cfg, mapResult, runRoot);
result = struct('config', cfg, 'mapResult', mapResult, ...
    'runtime', runtime, 'runRoot', runRoot, ...
    'accepted', mapResult.stage1Accepted && mapResult.stage2Accepted);
save(fullfile(runRoot, 'stage12_complete_result.mat'), 'result', '-v7');
if result.accepted
    sht_startstop_stage_asset('publish','stage12',cfg,result);
end

fprintf('阶段一读写验收：PASS\n');
fprintf('阶段二低速扩图：PASS\n');
fprintf('独立运行配置：%s\n\n', runtime.modelPath);
end
