function result = Start_SteadyModelUQ_B_03_ObservationVector(userCfg)
%START_STEADYMODELUQ_B_03_OBSERVATIONVECTOR 构造方法B的42维训练观测。
if nargin < 1, userCfg = struct(); end
timer = tic;
manifest = sht_steady_model_uq_b_io('resolvewritable',userCfg);
step1 = sht_steady_model_uq_b_io('loadstep',manifest,1);
contract = step1.contract;
[observation,label,unit] = sht_steady_model_uq_b_common( ...
    'observation',contract,contract.trainingData);
index = (1:numel(observation)).';
observationTable = table(index,label,unit,observation, ...
    'VariableNames',{'index','label','unit','observed_value'});
passed = numel(observation) == contract.observationDimension && ...
    all(isfinite(observation));
if ~passed
    error('SHT:SteadyUQB:ObservationContractFailed', ...
        '方法B观测向量尺寸或有限性验收失败。');
end
result = struct('observation',observation,'label',label,'unit',unit, ...
    'observationTable',observationTable,'ordering', ...
    'point_major_six_physical_residuals','passed',passed, ...
    'truthRead',false,'testDataRead',false);
runtime = toc(timer);
[manifest,file] = sht_steady_model_uq_b_io( ...
    'savestep',manifest,3,'observation_vector',result,runtime);
writetable(observationTable,sht_steady_model_uq_b_io( ...
    'reportfile',manifest,'UQB03_observation_vector.csv'));
fprintf('[2.4UQ-B.3] 观测向量完成：%d维。\n',numel(observation));
fprintf('[2.4UQ-B.3] 产物：%s\n',file);
result.manifest = manifest;
end
