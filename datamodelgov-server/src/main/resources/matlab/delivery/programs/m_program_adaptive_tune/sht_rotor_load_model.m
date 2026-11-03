function loadState = sht_rotor_load_model(NpRpm, commandValue, modelCfg, inputMode)
%SHT_ROTOR_LOAD_MODEL 由指定旋翼边界指令和当前动力涡轮转速计算负载。
%
% 输入：
%   NpRpm       当前动力涡轮转速，rpm；
%   commandValue 与 inputMode 对应的功率、扭矩或总距角指令；
%   modelCfg     冻结的设计基准，至少包含 designNpRpm/designPowerW；
%   inputMode    可选：
%                legacyPower     轴功率指令，W；
%                directTorque    Mkp 指令，N*m；
%                collectivePitch 0.75R 处等效总距角，deg。
%
% 三参数历史调用默认采用 legacyPower，保证既有程序零影响。新增的
% collectivePitch 模式把总距角作为权威输入，不允许先由功率反算总距角。
% directTorque 模式把 Mkp 作为权威输入。三种模式最终都统一输出 Mkp 和
% Pload，供 DLL 功率接口适配器使用。
%
% 首轮缺少真实旋翼 C_Q-theta 图，暂用工程关系：
% 在同一桨距代理量下，旋翼负载转矩和功率分别按 Npr^2、Npr^3 变化：
%   Qload = Q0*kTheta*Npr^2；
%   Pload = Qload*Np*pi/30 = P0*kTheta*Npr^3。
% 本函数不推进状态；theta 是首轮等效总距角，不是真实旋翼根部安装角。

if nargin < 4 || isempty(inputMode)
    inputMode = 'legacyPower';
end
if nargin < 3 || ~isstruct(modelCfg)
    error('sht:rotorLoad:badInput', ...
        '需要当前 Np、旋翼边界指令和旋翼负载模型配置。');
end
if ~isscalar(NpRpm) || ~isfinite(NpRpm) || NpRpm < 0
    error('sht:rotorLoad:badNp', 'NpRpm 必须是有限非负标量。');
end
if ~isscalar(commandValue) || ~isfinite(commandValue)
    error('sht:rotorLoad:badCommand', ...
        '旋翼负载指令必须是有限标量。');
end
inputMode = local_normalize_input_mode(inputMode);
if ~isfield(modelCfg, 'designNpRpm') || ...
        ~isscalar(modelCfg.designNpRpm) || ...
        ~isfinite(modelCfg.designNpRpm) || modelCfg.designNpRpm <= 0
    error('sht:rotorLoad:badDesignNp', ...
        'modelCfg.designNpRpm 必须是有限正标量。');
end
if ~isfield(modelCfg, 'designPowerW') || ...
        ~isscalar(modelCfg.designPowerW) || ...
        ~isfinite(modelCfg.designPowerW) || modelCfg.designPowerW <= 0
    error('sht:rotorLoad:badDesignPower', ...
        'modelCfg.designPowerW 必须是有限正标量。');
end

designOmegaRadPerS = modelCfg.designNpRpm * pi / 30;
designTorqueNm = modelCfg.designPowerW / designOmegaRadPerS;
if isfield(modelCfg, 'designTorqueNm') && ...
        ~isempty(modelCfg.designTorqueNm)
    suppliedTorque = modelCfg.designTorqueNm;
    if ~isscalar(suppliedTorque) || ~isfinite(suppliedTorque) || ...
            suppliedTorque <= 0
        error('sht:rotorLoad:badDesignTorque', ...
            'modelCfg.designTorqueNm 必须是有限正标量。');
    end
    relativeMismatch = abs(suppliedTorque - designTorqueNm) / designTorqueNm;
    if relativeMismatch > 1e-10
        error('sht:rotorLoad:inconsistentDesignTorque', ...
            ['designTorqueNm 与 designPowerW/(designNpRpm*pi/30) 不一致，' ...
             '相对差为 %.3e。'], relativeMismatch);
    end
end

Npr = NpRpm / modelCfg.designNpRpm;
mappingEnabled = isfield(modelCfg, 'collectivePitchMapping') && ...
    ~isempty(modelCfg.collectivePitchMapping);

referencePowerW = NaN;
directTorqueCommandNm = NaN;
collectivePitchCommandDeg = NaN;
kThetaFromPower = NaN;
thetaCollectiveDeg = NaN;
kTheta = NaN;
mappingRoundTripError = 0;
thetaWithinValidRange = true;
thetaValidRangeDeg = [NaN, NaN];
kThetaValidRange = [NaN, NaN];

switch inputMode
    case 'legacypower'
        if commandValue < 0
            error('sht:rotorLoad:badReferencePower', ...
                'legacyPower 模式的功率指令必须是有限非负标量。');
        end
        referencePowerW = commandValue;
        kThetaFromPower = referencePowerW / modelCfg.designPowerW;
        if mappingEnabled
            [thetaCollectiveDeg, inverseDiagnostic] = ...
                sht_collective_pitch_mapping(kThetaFromPower, ...
                'kThetaToTheta', modelCfg.collectivePitchMapping);
            [kTheta, forwardDiagnostic] = ...
                sht_collective_pitch_mapping(thetaCollectiveDeg, ...
                'thetaToKTheta', modelCfg.collectivePitchMapping);
            mappingRoundTripError = abs(kTheta - kThetaFromPower);
            mappingTolerance = 1e-12 * max(1, abs(kThetaFromPower));
            if mappingRoundTripError > mappingTolerance
                error('sht:rotorLoad:collectivePitchRoundTrip', ...
                    ['等效总距映射往返误差 %.12g 超过容差 %.12g；' ...
                     '不能继续计算旋翼负载。'], ...
                    mappingRoundTripError, mappingTolerance);
            end
            thetaWithinValidRange = inverseDiagnostic.thetaWithinValidRange && ...
                forwardDiagnostic.thetaWithinValidRange;
            thetaValidRangeDeg = inverseDiagnostic.thetaValidRangeDeg;
            kThetaValidRange = inverseDiagnostic.kThetaValidRange;
        else
            % 保留旧调用兼容性：未配置映射时仍按原 kTheta 代理量计算。
            kTheta = kThetaFromPower;
        end
        QloadNm = designTorqueNm * kTheta * Npr^2;

    case 'collectivepitch'
        if ~mappingEnabled
            error('sht:rotorLoad:missingCollectivePitchMapping', ...
                'collectivePitch 模式必须配置 collectivePitchMapping。');
        end
        collectivePitchCommandDeg = commandValue;
        thetaCollectiveDeg = collectivePitchCommandDeg;
        [kTheta, pitchDiagnostic] = sht_collective_pitch_mapping( ...
            thetaCollectiveDeg, 'thetaToKTheta', ...
            modelCfg.collectivePitchMapping);
        [thetaRoundTripDeg, inverseDiagnostic] = ...
            sht_collective_pitch_mapping(kTheta, 'kThetaToTheta', ...
            modelCfg.collectivePitchMapping);
        mappingRoundTripError = abs(thetaRoundTripDeg - thetaCollectiveDeg);
        mappingTolerance = 1e-12 * max(1, abs(thetaCollectiveDeg));
        if mappingRoundTripError > mappingTolerance
            error('sht:rotorLoad:collectivePitchRoundTrip', ...
                ['总距角映射往返误差 %.12g deg 超过容差 %.12g deg；' ...
                 '不能继续计算旋翼负载。'], ...
                mappingRoundTripError, mappingTolerance);
        end
        thetaWithinValidRange = pitchDiagnostic.thetaWithinValidRange && ...
            inverseDiagnostic.thetaWithinValidRange;
        thetaValidRangeDeg = pitchDiagnostic.thetaValidRangeDeg;
        kThetaValidRange = pitchDiagnostic.kThetaValidRange;
        QloadNm = designTorqueNm * kTheta * Npr^2;

    case 'directtorque'
        if commandValue < 0
            error('sht:rotorLoad:badDirectTorque', ...
                'directTorque 模式的 Mkp 指令必须是有限非负标量。');
        end
        directTorqueCommandNm = commandValue;
        QloadNm = directTorqueCommandNm;

    otherwise
        error('sht:rotorLoad:unknownInputMode', ...
            '不支持的旋翼负载输入模式 %s。', inputMode);
end

PloadW = QloadNm * NpRpm * pi / 30;

loadState = struct();
loadState.inputMode = inputMode;
loadState.commandValue = commandValue;
loadState.kTheta = kTheta;
loadState.kThetaFromPowerCommand = kThetaFromPower;
loadState.thetaCollectiveDeg = thetaCollectiveDeg;
loadState.collectivePitchCommandDeg = collectivePitchCommandDeg;
loadState.directTorqueCommandNm = directTorqueCommandNm;
loadState.collectivePitchMappingEnabled = mappingEnabled;
loadState.thetaWithinValidRange = thetaWithinValidRange;
loadState.thetaValidRangeDeg = thetaValidRangeDeg;
loadState.kThetaValidRange = kThetaValidRange;
loadState.mappingRoundTripError = mappingRoundTripError;
loadState.Npr = Npr;
loadState.QloadNm = QloadNm;
loadState.PloadW = PloadW;
loadState.designNpRpm = modelCfg.designNpRpm;
loadState.designPowerW = modelCfg.designPowerW;
loadState.designTorqueNm = designTorqueNm;
loadState.referencePowerW = referencePowerW;
if strcmp(inputMode, 'directtorque')
    loadState.powerFormulaCheckW = PloadW;
else
    loadState.powerFormulaCheckW = modelCfg.designPowerW * kTheta * Npr^3;
end
end

function mode = local_normalize_input_mode(rawMode)
if isstring(rawMode) && isscalar(rawMode)
    rawMode = char(rawMode);
end
if ~ischar(rawMode)
    error('sht:rotorLoad:badInputMode', ...
        'inputMode 必须是字符向量或标量字符串。');
end
mode = lower(strtrim(rawMode));
if ~ismember(mode, {'legacypower', 'directtorque', 'collectivepitch'})
    error('sht:rotorLoad:badInputMode', ...
        ['inputMode 必须为 legacyPower、directTorque 或 ' ...
         'collectivePitch，当前为 %s。'], rawMode);
end
end
