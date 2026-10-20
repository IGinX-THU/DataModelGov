function result = Start_SteadyModelUQ_C_01_ProblemContract(userCfg)
%START_STEADYMODELUQ_C_01_PROBLEMCONTRACT 冻结方法C问题合同和五核分组。
if nargin < 1, userCfg = struct(); end
timer = tic;
cfg = sht_steady_model_uq_c_common('defaultconfig', userCfg);
manifest = sht_steady_model_uq_c_io('createrun', cfg);
contract = sht_steady_model_uq_c_common('buildcontract', cfg);
prior = sht_steady_model_uq_sampler( ...
    'buildprior', contract, contract.priorType);
selfTest = sht_steady_model_uq_sampler('selftest', contract);
if ~selfTest.passed
    error('SHT:SteadyUQC:SamplerSelfTestFailed', ...
        '方法C相关截断先验及潜变量映射自检失败。');
end
result = struct('contract',contract,'prior',prior, ...
    'samplerSelfTest',selfTest,'truthRead',false,'testDataRead',false);
runtime = toc(timer);
[manifest,file] = sht_steady_model_uq_c_io( ...
    'savestep',manifest,1,'problem_contract',result,runtime);
writetable(contract.parameterTable, sht_steady_model_uq_c_io( ...
    'reportfile',manifest,'UQC01_parameter_contract.csv'));
writetable(contract.parameterBlockTable, sht_steady_model_uq_c_io( ...
    'reportfile',manifest,'UQC01_five_kernel_contract.csv'));
fprintf(['[2.4UQ-C.1] 合同完成：%d维显式参数，%d维干扰参数，' ...
    '%d维观测，5个移动核。\n'],contract.parameterCount, ...
    contract.marginalizedNuisanceDimension,contract.observationDimension);
fprintf('[2.4UQ-C.1] 基础物理合同=%s\n',contract.baseContractHash);
fprintf('[2.4UQ-C.1] 产物：%s\n',file);
result.manifest = manifest;
end
