function SFunc_EngModel(block)
%SFunc_EngModel 两状态涡轴发动机 DLL 的 Level-2 MATLAB S-Function。
%
% 发动机业务输入端口保持 10 维，其中第 6、7 项的物理意义为：
%   input(6) = Mkp，PT 负载/输出轴传递扭矩，N*m；
%   input(7) = Mkg，GT 轴外部附件负载扭矩，N*m。
%
% 现有 C/DLL 接口不改动，仍接收两个轴的负载功率。本适配层在每次
% 导数求值时用当前连续状态 Np/Ng 完成 P=M*pi*N/30 的唯一换算，
% 避免把 DLL 内部驱动扭矩误作外部可测负载扭矩。

setup(block);
end

function setup(block)
block.NumDialogPrms = 3;

block.NumInputPorts = 2;
block.NumOutputPorts = 2;
block.SetPreCompInpPortInfoToDynamic;
block.SetPreCompOutPortInfoToDynamic;

block.InputPort(1).Dimensions = 10;
block.InputPort(1).DirectFeedthrough = false;
block.InputPort(2).Dimensions = 50;
block.InputPort(2).DirectFeedthrough = false;

block.OutputPort(1).Dimensions = 20;
block.OutputPort(2).Dimensions = 50;

block.NumContStates = 2;
block.SampleTimes = [-1 0];
block.SimStateCompliance = 'DefaultSimState';

block.RegBlockMethod('PostPropagationSetup', @DoPostPropSetup);
block.RegBlockMethod('InitializeConditions', @InitConditions);
block.RegBlockMethod('SetInputPortSamplingMode', @SetInputPortSamplingMode);
block.RegBlockMethod('Outputs', @Output);
block.RegBlockMethod('Derivatives', @Derivatives);
block.RegBlockMethod('Terminate', @Terminate);
end

function SetInputPortSamplingMode(block, index, samplingMode)
block.InputPort(index).SamplingMode = samplingMode;
for outputIndex = 1:block.NumOutputPorts
    block.OutputPort(outputIndex).SamplingMode = samplingMode;
end
end

function DoPostPropSetup(block)
block.NumDworks = 2;

block.Dwork(1).Name = 'EngineOutput';
block.Dwork(1).Dimensions = 20;
block.Dwork(1).DatatypeID = 0;
block.Dwork(1).Complexity = 'Real';
block.Dwork(1).UsedAsDiscState = false;

block.Dwork(2).Name = 'SecondaryAirOutput';
block.Dwork(2).Dimensions = 50;
block.Dwork(2).DatatypeID = 0;
block.Dwork(2).Complexity = 'Real';
block.Dwork(2).UsedAsDiscState = false;
end

function InitConditions(block)
local_validate_dialog_parameters(block);

block.ContStates.Data = block.DialogPrm(1).Data(:);
block.Dwork(1).Data = block.DialogPrm(2).Data(:);
block.Dwork(2).Data = block.DialogPrm(3).Data(:);

[libraryName, headerName] = local_library_names();
if ~libisloaded(libraryName)
    loadlibrary(libraryName, headerName);
end

calllib(libraryName, 'DLL_SHT_Initial');
enginePointer = local_engine_pointer();
stepIn = libpointer('doublePtr', zeros(512, 1));
stepOut = libpointer('doublePtr', zeros(128, 1));

% stepIn(41:140) 对应 C 侧 hlthparas[100]。SLX 首轮参考模型固定零修正。
stepIn.Value(41:140) = 0;
stepIn.Value(11:13) = 0;
calllib(libraryName, 'DLL_SHT_ConditionsInit', ...
    stepIn, stepOut, enginePointer);
end

function Output(block)
engineOutput = block.Dwork(1).Data;

% 旋翼负载边界必须读取求解器当前连续状态，不能读取上一导数调用留下的
% 日志值。输出 9、10 因此直接镜像当前 Np/Ng 状态。
engineOutput(9:10) = block.ContStates.Data(1:2);
block.OutputPort(1).Data = engineOutput;
block.OutputPort(2).Data = block.Dwork(2).Data;
end

function Derivatives(block)
[libraryName, ~] = local_library_names();
if ~libisloaded(libraryName)
    error('sht:slxEngine:dllNotLoaded', ...
        'GTESS.dll 尚未加载；请先执行模型初始化脚本。');
end

state = block.ContStates.Data(:);
if numel(state) ~= 2 || any(~isfinite(state)) || any(state <= 0)
    error('sht:slxEngine:badState', ...
        '发动机连续状态必须为有限正值 [Np;Ng]。');
end

modelInput = block.InputPort(1).Data(:);
if numel(modelInput) ~= 10 || any(~isfinite(modelInput))
    error('sht:slxEngine:badInput', ...
        '发动机输入必须是 10 维有限实数向量。');
end

Mkp = modelInput(6);
Mkg = modelInput(7);
omegaP = pi * state(1) / 30;
omegaG = pi * state(2) / 30;

% DLL 仍使用功率接口；Mkp/Mkg 才是 SLX 业务层权威边界。
modelInput(1:2) = state;
modelInput(6) = Mkp * omegaP;
modelInput(7) = Mkg * omegaG;

enginePointer = local_engine_pointer();
stepIn = libpointer('doublePtr', zeros(512, 1));
stepOut = libpointer('doublePtr', zeros(128, 1));
stepIn.Value(1:10) = modelInput;
stepIn.Value(41:140) = 0;

secondaryAirOutput = block.InputPort(2).Data(:);
if numel(secondaryAirOutput) ~= 50 || any(~isfinite(secondaryAirOutput))
    error('sht:slxEngine:badSecondaryAirInput', ...
        '外部二次空气系统输入必须是 50 维有限向量。');
end
stepIn.Value = local_write_secondary_air( ...
    stepIn.Value, secondaryAirOutput);

[returnCode, ~, stepOutValue, engineOutput] = calllib( ...
    libraryName, 'DLL_SHT_RunOneStep', stepIn, stepOut, enginePointer);
if returnCode ~= 0
    error('sht:slxEngine:dllExecutionFailed', ...
        'DLL_SHT_RunOneStep 执行失败，返回码=%d。', returnCode);
end

residuals = abs([engineOutput.eng.errOut, ...
    engineOutput.eng.Nozzle.y(end)]);
maxResidual = max(residuals);
if engineOutput.eng.convergeTag ~= 0 || maxResidual > 1e-6
    warning('sht:slxEngine:notConverged', ...
        'DLL 共同工作方程未充分收敛：tag=%d，maxResidual=%.12g。', ...
        engineOutput.eng.convergeTag, maxResidual);
end

block.Derivatives.Data = stepOutValue(1:2);
block.Dwork(1).Data = local_pack_engine_output( ...
    engineOutput.eng, Mkp, Mkg, maxResidual);
block.Dwork(2).Data = local_pack_secondary_air(engineOutput.eng);
end

function Terminate(~)
libraryName = 'GTESS';
if libisloaded(libraryName)
    calllib(libraryName, 'DLL_SHT_Free');
    unloadlibrary(libraryName);
end
end

function local_validate_dialog_parameters(block)
initialState = block.DialogPrm(1).Data;
initialOutput = block.DialogPrm(2).Data;
initialSecondaryAir = block.DialogPrm(3).Data;

if ~isnumeric(initialState) || numel(initialState) ~= 2 || ...
        any(~isfinite(initialState(:))) || any(initialState(:) <= 0)
    error('sht:slxEngine:badInitialState', ...
        'InitStat 必须是 2 维有限正值向量。');
end
if ~isnumeric(initialOutput) || numel(initialOutput) ~= 20 || ...
        any(~isfinite(initialOutput(:)))
    error('sht:slxEngine:badInitialOutput', ...
        'InitOut 必须是 20 维有限向量。');
end
if ~isnumeric(initialSecondaryAir) || ...
        numel(initialSecondaryAir) ~= 50 || ...
        any(~isfinite(initialSecondaryAir(:)))
    error('sht:slxEngine:badInitialSecondaryAir', ...
        'InitAir 必须是 50 维有限向量。');
end
end

function enginePointer = local_engine_pointer()
eng_ptr_init.eng = libstruct('EngineTurboshaft');
enginePointer = libstruct('EngineSHTPointer', eng_ptr_init);
end

function [libraryName, headerName] = local_library_names()
libraryName = 'GTESS';
headerName = 'GTESS.h';
end

function stepInValue = local_write_secondary_air( ...
        stepInValue, secondaryAirOutput)
stepInValue(201:205) = secondaryAirOutput(1:5);

stepInValue(206:210) = secondaryAirOutput(6:10);
stepInValue(206) = secondaryAirOutput(6) / 2;
stepInValue(211:215) = secondaryAirOutput(11:15);
stepInValue(211) = secondaryAirOutput(11) / 2;

stepInValue(216:220) = secondaryAirOutput(6:10);
stepInValue(216) = secondaryAirOutput(6) / 2;
stepInValue(221:225) = secondaryAirOutput(11:15);
stepInValue(221) = secondaryAirOutput(11) / 2;

stepInValue(226:230) = secondaryAirOutput(16:20);
stepInValue(231:235) = secondaryAirOutput(21:25);

stepInValue(236:240) = secondaryAirOutput(26:30);
stepInValue(236) = secondaryAirOutput(26) / 2;
stepInValue(241:245) = secondaryAirOutput(31:35);
stepInValue(241) = secondaryAirOutput(31) / 2;

stepInValue(246:250) = secondaryAirOutput(26:30);
stepInValue(246) = secondaryAirOutput(26) / 2;
stepInValue(251:255) = secondaryAirOutput(31:35);
stepInValue(251) = secondaryAirOutput(31) / 2;

stepInValue(256:260) = secondaryAirOutput(36:40);
stepInValue(261:265) = secondaryAirOutput(41:45);
stepInValue(266:270) = secondaryAirOutput(46:50);
end

function output = local_pack_engine_output(eng, Mkp, Mkg, maxResidual)
output = zeros(20, 1);
output(1) = eng.Ambient.gasPathOut(4);
output(2) = eng.Ambient.gasPathOut(3);
output(3) = eng.HPC.y(4);
output(4) = eng.HPC.y(3);
output(5) = eng.HPT.y(4);
output(6) = eng.HPT.y(3);
output(7) = eng.LPT.y(4);
output(8) = eng.LPT.y(3);
output(9) = eng.LPS_Nmech;
output(10) = eng.HPS_Nmech;
output(11) = eng.HPC.y(8);

% 第 12 项保留 DLL 内部 PT 驱动扭矩，仅作诊断，不再作为 Mkp 反馈。
output(12) = eng.LPS_Trq;
output(13) = eng.HPC.u(6);
output(14) = eng.HPT.y(16);
output(15) = eng.LPT.y(16);
output(16) = maxResidual;
output(17) = eng.Burner.y(4);
output(18) = eng.Burner.y(3);
output(19) = eng.HPS_Trq;
output(20) = eng.convergeTag;

% 明确读取两个外部负载量，防止后续维护时再次误用内部扭矩字段。
if ~isfinite(Mkp) || ~isfinite(Mkg)
    error('sht:slxEngine:badExternalTorque', ...
        'Mkp/Mkg 必须是有限外部负载扭矩。');
end
end

function output = local_pack_secondary_air(eng)
output = zeros(50, 1);
output(1:5) = eng.HPC.fractionalBleeds(1:5);

output(6:10) = (eng.HPC.fractionalBleeds(6:10) + ...
    eng.HPC.fractionalBleeds(16:20)) / 2;
output(6) = output(6) * 2;
output(11:15) = (eng.HPC.fractionalBleeds(11:15) + ...
    eng.HPC.fractionalBleeds(21:25)) / 2;
output(11) = output(11) * 2;

output(16:20) = eng.HPC.fractionalBleeds(26:30);
output(21:25) = eng.HPC.fractionalBleeds(31:35);

output(26:30) = (eng.HPC.fractionalBleeds(36:40) + ...
    eng.HPC.fractionalBleeds(46:50)) / 2;
output(26) = output(26) * 2;
output(31:35) = (eng.HPC.fractionalBleeds(41:45) + ...
    eng.HPC.fractionalBleeds(51:55)) / 2;
output(31) = output(31) * 2;

output(36:40) = eng.HPC.fractionalBleeds(56:60);
output(41:45) = eng.HPC.fractionalBleeds(61:65);
output(46:50) = eng.HPC.fractionalBleeds(66:70);
end
