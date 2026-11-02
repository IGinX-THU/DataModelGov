classdef sht_log_record
%SHT_LOG_RECORD 仿真日志记录与派生诊断量工具。
% 阅读说明：
%   本文件集中管理与日志记录相关的代码，避免 sht_simulate_control_m.m 被大量字段映射淹没。
%   日志模块不参与控制律、不推进发动机状态、不改变执行机构输入，只把主流程已经计算出的量写入 result.log。
%   对主体仿真而言，本文件只提供四个静态入口：
%       allocate              预分配日志结构；
%       store                 写入一个仿真时刻的信号；
%       addDerivedSignals     仿真结束后补充非传感器导数诊断；
%       emptyControllerDiag   构造 t=0 初始控制器诊断量。
%   若后续增加绘图或测试需要的新日志字段，应优先在本文件中扩展字段名和 store 映射。

methods (Static)
    function log = allocate(n, engineStateCount)
        % 预分配的目的不是控制逻辑需要，而是保证长时间仿真时日志写入稳定、字段维度一致。
        if nargin < 2 || isempty(engineStateCount)
            engineStateCount = 2;
        end
        names = {'Np', 'Ng', 'WIn', 'Pt1', 'Tt1', 'Pt2', 'Tt2', 'Pt3', 'Tt3', 'Pt45', 'Tt45', ...
            'T45', 'Pt5', 'Tt5', 'T5', 'Mkp', 'Mkg', 'Pamb', 'Tamb', ...
            'Altitude', 'Mach', ...
            'HpcStallMargin', 'HPC_Ncr', 'CC_Ncr', 'GT_Ncr', 'GT2_Ncr', ...
            'PT_Ncr', 'PT2_Ncr', ...
            'HptBeta', 'LptBeta', 'FAR', 'T4', ...
            'Ngc', 'Theta', 'Deta', 'sampleNp', 'sampleNg', 'samplePt1', 'samplePt2', 'sampleTt1', ...
            'samplePt3', 'sampleTt3', 'samplePt45', 'sampleT45', 'sampleTt45', ...
            'samplePt5', 'sampleT5', 'sampleMkp', 'sampleMkg', 'samplePamb', 'sampleTamb', ...
            'sampleAltitude', 'sampleMach', 'sampleHpcStallMargin', ...
            'NpDem', 'power', 'Wf', 'Wfcmd', 'WfcmdNext', 'WfcmdNow', ...
            'Wf_main_next', 'Wf_main_raw_next', 'Wf_main_limited_next', ...
            'Wf_selected_next', 'Wf_selector_delta', ...
            'Wf_rate_up_max', 'Wf_rate_down_min', 'Wf_upper_bound', 'Wf_lower_bound', ...
            'fuelUpperActive', 'fuelLowerActive', 'fuelBoundsApplied', ...
            'selectorModeId', 'controlModeId', 'fullControlEnabled', ...
            'gainScheduleEnabled', 'gainScheduleNgc', 'gainScheduleNgcClamped', ...
            'gainScheduleAtLowerBound', 'gainScheduleAtUpperBound', ...
            'ndotScheduleEnabled', 'ndotScheduleNgc', 'ndotScheduleNgcClamped', ...
            'ndotScheduleAtLowerBound', 'ndotScheduleAtUpperBound', ...
            'NgdotMaxSchedule', 'NgdotMinSchedule', ...
            'AccelWfLimitSchedule', 'DecelWfLimitSchedule', ...
            'accelDecelLimitEnabled', ...
            'linearB11', 'linearB21', 'linearD31', 'linearD41', ...
            'Nu_main', 'Nu_selected', ...
            'Nu_upper_bound', 'Nu_lower_bound', ...
            'Nu_NgTop_max', 'Nu_T45_max', 'Nu_Mkp_max', ...
            'Nu_accel_max', 'Nu_decel_min', ...
            'Nu_selector_delta', 'incrementBoundsApplied', ...
            'NgMax', 'NgTopRef', 'NgTopError', 'NgTopProtectionError', ...
            'NgTopCommandError', 'NgTopCommandErrorPrev', ...
            'NgTopCommandErrorDelta', 'NgTopErrorGain', ...
            'NgTopErrorDeltaGain', ...
            'T45Max', 'T45Ref', 'T45CommandError', 'T45CommandErrorPrev', ...
            'T45Delta', 'T45ErrorGainNu', 'T45GainScheduleK', 'T45NuScale', ...
            'T45TempRateGainNu', 'K_TNu', ...
            'T45TargetOmega', 'T45TargetZeta', ...
            'MkpMax', 'MkpRef', 'MkpCommandError', 'MkpCommandErrorPrev', ...
            'MkpDelta', 'MkpErrorGainNu', 'MkpGainScheduleK', 'MkpNuScale', ...
            'MkpD41', 't45ProtectionActive', 't45ProtectionSelected', ...
            'mkpProtectionActive', 'mkpProtectionSelected', ...
            'ngTopProtectionActive', 'ngTopProtectionSelected', ...
            'accelLimitSelected', 'decelLimitSelected', ...
            'incrementUpperActive', 'incrementLowerActive', ...
            'dNgMeasured', 'dZ2', 'dWf_raw_increment', 'dWf_final', ...
            'dWf_aw_error', 'dWf_upper_bound', 'dWf_lower_bound', ...
            'WfRate', 'WfRateRaw', 'dURaw', 'dU', 'uNp', ...
            'z2Ng', 'dNpDerived', 'dNgDerived', 'maxErr', ...
            'evaluationValid', 'visserEnergyResidual_W', ...
            'visserNormalizedEnergyResidual', ...
            'visserMaximumCoolingTemperatureChange_K'};
        log = struct();
        for i = 1:numel(names)
            log.(names{i}) = nan(n, 1);
        end
        log.time = nan(n, 1);
        log.xEngine = nan(n, engineStateCount);
        log.controlUpdate = false(n, 1);
        log.convergeTag = nan(n, 1);
    end

    function log = store(log, idx, t, xEngine, wf, ...
            wfCommandNext, wfCommandNow, ref, sample, ...
            y, ctrlDiag, actDiag, engineDiag, didControlUpdate)
        % 写入一个仿真时间点的所有观测和诊断量。
        % 输入分四类：发动机输出 y、传感器采样 sample、控制器诊断 ctrlDiag、执行机构/发动机诊断 actDiag/engineDiag。
        % store 只做字段搬运和默认值填充，不反向影响主仿真中的任何状态。
        log.time(idx) = t;
        log.xEngine(idx, :) = xEngine(:).';

        % 发动机本体输出：代表连续对象端点状态，用于后处理和曲线对照。
        log.Np(idx) = y.Np;
        log.Ng(idx) = y.Ng;
        log.WIn(idx) = sht_log_record.getField(y, 'WIn', NaN);
        log.Pt1(idx) = y.Pt1;
        log.Tt1(idx) = y.Tt1;
        log.Pt2(idx) = sht_log_record.getField(y, 'Pt2', NaN);
        log.Tt2(idx) = sht_log_record.getField(y, 'Tt2', NaN);
        log.Pt3(idx) = y.Pt3;
        log.Tt3(idx) = y.Tt3;
        log.Pt45(idx) = y.Pt45;
        log.Tt45(idx) = y.Tt45;
        log.T45(idx) = y.Tt45;
        log.Pt5(idx) = y.Pt5;
        log.Tt5(idx) = y.Tt5;
        log.T5(idx) = y.Tt5;
        log.Mkp(idx) = y.Mkp;
        log.Mkg(idx) = sht_log_record.getField(y, 'Mkg', NaN);
        log.Pamb(idx) = sht_log_record.getField(y, 'Pamb', NaN);
        log.Tamb(idx) = sht_log_record.getField(y, 'Tamb', NaN);
        log.Altitude(idx) = sht_log_record.getField(y, 'Altitude', NaN);
        log.Mach(idx) = sht_log_record.getField(y, 'Mach', NaN);
        log.HpcStallMargin(idx) = sht_log_record.getField(y, 'HpcStallMargin', NaN);
        log.HPC_Ncr(idx) = sht_log_record.getField(y, 'HPC_Ncr', NaN);
        log.CC_Ncr(idx) = sht_log_record.getField(y, 'CC_Ncr', NaN);
        log.GT_Ncr(idx) = sht_log_record.getField(y, 'GT_Ncr', NaN);
        log.GT2_Ncr(idx) = sht_log_record.getField(y, 'GT2_Ncr', NaN);
        log.PT_Ncr(idx) = sht_log_record.getField(y, 'PT_Ncr', NaN);
        log.PT2_Ncr(idx) = sht_log_record.getField(y, 'PT2_Ncr', NaN);
        log.HptBeta(idx) = sht_log_record.getField(y, 'HptBeta', NaN);
        log.LptBeta(idx) = sht_log_record.getField(y, 'LptBeta', NaN);
        log.FAR(idx) = sht_log_record.getField(y, 'FAR', NaN);
        log.T4(idx) = sht_log_record.getField(y, 'T4', NaN);

        % 控制器实际采样信号：默认传感器为直连，后续传感器动态开启后这里会区别于发动机真实输出。
        log.Ngc(idx) = sample.Ngc;
        log.Theta(idx) = sample.Theta;
        log.Deta(idx) = sample.Deta;
        log.sampleNp(idx) = sht_log_record.getField(sample, 'Np', NaN);
        log.sampleNg(idx) = sht_log_record.getField(sample, 'Ng', NaN);
        % 两种测点合同分别记录；未启用的Pt1/Pt2测量字段留NaN。
        log.samplePt1(idx) = sht_log_record.getField(sample, 'Pt1', NaN);
        log.samplePt2(idx) = sht_log_record.getField(sample, 'Pt2', NaN);
        log.sampleTt1(idx) = sht_log_record.getField(sample, 'Tt1', NaN);
        log.samplePt3(idx) = sht_log_record.getField(sample, 'Pt3', NaN);
        log.sampleTt3(idx) = sht_log_record.getField(sample, 'Tt3', NaN);
        log.samplePt45(idx) = sht_log_record.getField(sample, 'Pt45', NaN);
        log.sampleT45(idx) = sht_log_record.getField(sample, 'T45', NaN);
        % 对外记录统一使用Tt45；取值与控制器实际使用的反馈样本完全一致。
        log.sampleTt45(idx) = log.sampleT45(idx);
        log.samplePt5(idx) = sht_log_record.getField(sample, 'Pt5', NaN);
        log.sampleT5(idx) = sht_log_record.getField(sample, 'T5', NaN);
        log.sampleMkp(idx) = sht_log_record.getField(sample, 'Mkp', NaN);
        log.sampleMkg(idx) = sht_log_record.getField(sample, 'Mkg', NaN);
        log.samplePamb(idx) = sht_log_record.getField(sample, 'Pamb', NaN);
        log.sampleTamb(idx) = sht_log_record.getField(sample, 'Tamb', NaN);
        log.sampleAltitude(idx) = sht_log_record.getField(sample, 'Altitude', NaN);
        log.sampleMach(idx) = sht_log_record.getField(sample, 'Mach', NaN);
        log.sampleHpcStallMargin(idx) = sht_log_record.getField(sample, 'HpcStallMargin', NaN);

        % 外部操纵指令和执行机构实际燃油状态。
        log.NpDem(idx) = ref.NpDem;
        log.power(idx) = ref.power;
        log.Wf(idx) = wf;
        log.Wfcmd(idx) = wfCommandNow;
        log.WfcmdNext(idx) = wfCommandNext;
        log.WfcmdNow(idx) = wfCommandNow;

        % 燃油命令相关诊断：主回路候选、保护选择后结果、统一燃油饱和边界。
        log.Wf_main_next(idx) = sht_log_record.getField(ctrlDiag, 'Wf_main_next', wfCommandNext);
        log.Wf_main_raw_next(idx) = sht_log_record.getField(ctrlDiag, 'Wf_main_raw_next', wfCommandNext);
        log.Wf_main_limited_next(idx) = sht_log_record.getField(ctrlDiag, 'Wf_main_limited_next', wfCommandNext);
        log.Wf_selected_next(idx) = sht_log_record.getField(ctrlDiag, 'Wf_selected_next', wfCommandNext);
        log.Wf_selector_delta(idx) = sht_log_record.getField(ctrlDiag, 'Wf_selector_delta', 0);
        log.Wf_rate_up_max(idx) = sht_log_record.getField(ctrlDiag, 'Wf_rate_up_max', NaN);
        log.Wf_rate_down_min(idx) = sht_log_record.getField(ctrlDiag, 'Wf_rate_down_min', NaN);
        log.Wf_upper_bound(idx) = sht_log_record.getField(ctrlDiag, 'Wf_upper_bound', NaN);
        log.Wf_lower_bound(idx) = sht_log_record.getField(ctrlDiag, 'Wf_lower_bound', NaN);
        log.fuelUpperActive(idx) = double(sht_log_record.getField(ctrlDiag, 'fuelUpperActive', false));
        log.fuelLowerActive(idx) = double(sht_log_record.getField(ctrlDiag, 'fuelLowerActive', false));
        log.fuelBoundsApplied(idx) = double(sht_log_record.getField(ctrlDiag, 'fuelBoundsApplied', false));
        log.selectorModeId(idx) = sht_log_record.getField(ctrlDiag, 'selectorModeId', 0);
        log.controlModeId(idx) = sht_log_record.getField(ctrlDiag, 'controlModeId', 1);
        log.fullControlEnabled(idx) = double(sht_log_record.getField(ctrlDiag, 'fullControlEnabled', false));
        log.gainScheduleEnabled(idx) = double(sht_log_record.getField(ctrlDiag, 'gainScheduleEnabled', false));
        log.gainScheduleNgc(idx) = sht_log_record.getField(ctrlDiag, 'gainScheduleNgc', NaN);
        log.gainScheduleNgcClamped(idx) = sht_log_record.getField(ctrlDiag, 'gainScheduleNgcClamped', NaN);
        log.gainScheduleAtLowerBound(idx) = double(sht_log_record.getField(ctrlDiag, 'gainScheduleAtLowerBound', false));
        log.gainScheduleAtUpperBound(idx) = double(sht_log_record.getField(ctrlDiag, 'gainScheduleAtUpperBound', false));
        log.ndotScheduleEnabled(idx) = double(sht_log_record.getField(ctrlDiag, 'ndotScheduleEnabled', false));
        log.ndotScheduleNgc(idx) = sht_log_record.getField(ctrlDiag, 'ndotScheduleNgc', NaN);
        log.ndotScheduleNgcClamped(idx) = sht_log_record.getField(ctrlDiag, 'ndotScheduleNgcClamped', NaN);
        log.ndotScheduleAtLowerBound(idx) = double(sht_log_record.getField(ctrlDiag, 'ndotScheduleAtLowerBound', false));
        log.ndotScheduleAtUpperBound(idx) = double(sht_log_record.getField(ctrlDiag, 'ndotScheduleAtUpperBound', false));
        log.NgdotMaxSchedule(idx) = sht_log_record.getField(ctrlDiag, 'NgdotMaxSchedule', NaN);
        log.NgdotMinSchedule(idx) = sht_log_record.getField(ctrlDiag, 'NgdotMinSchedule', NaN);
        log.AccelWfLimitSchedule(idx) = sht_log_record.getField(ctrlDiag, 'AccelWfLimitSchedule', NaN);
        log.DecelWfLimitSchedule(idx) = sht_log_record.getField(ctrlDiag, 'DecelWfLimitSchedule', NaN);
        log.accelDecelLimitEnabled(idx) = double(sht_log_record.getField(ctrlDiag, 'accelDecelLimitEnabled', false));
        log.linearB11(idx) = sht_log_record.getField(ctrlDiag, 'linearB11', NaN);
        log.linearB21(idx) = sht_log_record.getField(ctrlDiag, 'linearB21', NaN);
        log.linearD31(idx) = sht_log_record.getField(ctrlDiag, 'linearD31', NaN);
        log.linearD41(idx) = sht_log_record.getField(ctrlDiag, 'linearD41', NaN);

        % Nu 域高低选诊断：这是理解完整控制器当前由哪个限制回路接管的主入口。
        log.Nu_main(idx) = sht_log_record.getField(ctrlDiag, 'Nu_main', sht_log_record.getField(ctrlDiag, 'uNp', 0));
        log.Nu_selected(idx) = sht_log_record.getField(ctrlDiag, 'Nu_selected', log.Nu_main(idx));
        log.Nu_upper_bound(idx) = sht_log_record.getField(ctrlDiag, 'Nu_upper_bound', NaN);
        log.Nu_lower_bound(idx) = sht_log_record.getField(ctrlDiag, 'Nu_lower_bound', NaN);
        log.Nu_NgTop_max(idx) = sht_log_record.getField(ctrlDiag, 'Nu_NgTop_max', NaN);
        log.Nu_T45_max(idx) = sht_log_record.getField(ctrlDiag, 'Nu_T45_max', NaN);
        log.Nu_Mkp_max(idx) = sht_log_record.getField(ctrlDiag, 'Nu_Mkp_max', NaN);
        log.Nu_accel_max(idx) = sht_log_record.getField(ctrlDiag, 'Nu_accel_max', NaN);
        log.Nu_decel_min(idx) = sht_log_record.getField(ctrlDiag, 'Nu_decel_min', NaN);
        log.Nu_selector_delta(idx) = sht_log_record.getField(ctrlDiag, 'Nu_selector_delta', 0);

        % Ng 上限保护诊断。
        log.NgMax(idx) = sht_log_record.getField(ctrlDiag, 'NgMax', NaN);
        log.NgTopRef(idx) = sht_log_record.getField(ctrlDiag, 'NgTopRef', NaN);
        log.NgTopError(idx) = sht_log_record.getField(ctrlDiag, 'NgTopError', NaN);
        log.NgTopProtectionError(idx) = sht_log_record.getField(ctrlDiag, 'NgTopProtectionError', NaN);
        log.NgTopCommandError(idx) = sht_log_record.getField(ctrlDiag, 'NgTopCommandError', NaN);
        log.NgTopCommandErrorPrev(idx) = sht_log_record.getField(ctrlDiag, 'NgTopCommandErrorPrev', NaN);
        log.NgTopCommandErrorDelta(idx) = sht_log_record.getField(ctrlDiag, 'NgTopCommandErrorDelta', NaN);
        log.NgTopErrorGain(idx) = sht_log_record.getField(ctrlDiag, 'NgTopErrorGain', NaN);
        log.NgTopErrorDeltaGain(idx) = sht_log_record.getField(ctrlDiag, 'NgTopErrorDeltaGain', NaN);
        log.ngTopProtectionActive(idx) = double(sht_log_record.getField(ctrlDiag, 'ngTopProtectionActive', false));
        log.ngTopProtectionSelected(idx) = double(sht_log_record.getField(ctrlDiag, 'ngTopProtectionSelected', false));

        % T45 温度保护诊断。
        log.T45Max(idx) = sht_log_record.getField(ctrlDiag, 'T45Max', NaN);
        log.T45Ref(idx) = sht_log_record.getField(ctrlDiag, 'T45Ref', NaN);
        log.T45CommandError(idx) = sht_log_record.getField(ctrlDiag, 'T45CommandError', NaN);
        log.T45CommandErrorPrev(idx) = sht_log_record.getField(ctrlDiag, 'T45CommandErrorPrev', NaN);
        log.T45Delta(idx) = sht_log_record.getField(ctrlDiag, 'T45Delta', NaN);
        log.T45ErrorGainNu(idx) = sht_log_record.getField(ctrlDiag, 'T45ErrorGainNu', NaN);
        log.T45GainScheduleK(idx) = sht_log_record.getField(ctrlDiag, 'T45GainScheduleK', NaN);
        log.T45NuScale(idx) = sht_log_record.getField(ctrlDiag, 'T45NuScale', NaN);
        log.T45TempRateGainNu(idx) = sht_log_record.getField(ctrlDiag, 'T45TempRateGainNu', NaN);
        log.K_TNu(idx) = sht_log_record.getField(ctrlDiag, 'K_TNu', NaN);
        log.T45TargetOmega(idx) = sht_log_record.getField(ctrlDiag, 'T45TargetOmega', NaN);
        log.T45TargetZeta(idx) = sht_log_record.getField(ctrlDiag, 'T45TargetZeta', NaN);

        % Mkp 扭矩保护诊断。
        log.MkpMax(idx) = sht_log_record.getField(ctrlDiag, 'MkpMax', NaN);
        log.MkpRef(idx) = sht_log_record.getField(ctrlDiag, 'MkpRef', NaN);
        log.MkpCommandError(idx) = sht_log_record.getField(ctrlDiag, 'MkpCommandError', NaN);
        log.MkpCommandErrorPrev(idx) = sht_log_record.getField(ctrlDiag, 'MkpCommandErrorPrev', NaN);
        log.MkpDelta(idx) = sht_log_record.getField(ctrlDiag, 'MkpDelta', NaN);
        log.MkpErrorGainNu(idx) = sht_log_record.getField(ctrlDiag, 'MkpErrorGainNu', NaN);
        log.MkpGainScheduleK(idx) = sht_log_record.getField(ctrlDiag, 'MkpGainScheduleK', NaN);
        log.MkpNuScale(idx) = sht_log_record.getField(ctrlDiag, 'MkpNuScale', NaN);
        log.MkpD41(idx) = sht_log_record.getField(ctrlDiag, 'MkpD41', NaN);
        log.t45ProtectionActive(idx) = double(sht_log_record.getField(ctrlDiag, 't45ProtectionActive', false));
        log.t45ProtectionSelected(idx) = double(sht_log_record.getField(ctrlDiag, 't45ProtectionSelected', false));
        log.mkpProtectionActive(idx) = double(sht_log_record.getField(ctrlDiag, 'mkpProtectionActive', false));
        log.mkpProtectionSelected(idx) = double(sht_log_record.getField(ctrlDiag, 'mkpProtectionSelected', false));
        log.accelLimitSelected(idx) = double(sht_log_record.getField(ctrlDiag, 'accelLimitSelected', false));
        log.decelLimitSelected(idx) = double(sht_log_record.getField(ctrlDiag, 'decelLimitSelected', false));

        % 增量、执行机构和发动机求解诊断。
        log.incrementBoundsApplied(idx) = double(sht_log_record.getField(ctrlDiag, 'incrementBoundsApplied', false));
        log.incrementUpperActive(idx) = double(sht_log_record.getField(ctrlDiag, 'incrementUpperActive', false));
        log.incrementLowerActive(idx) = double(sht_log_record.getField(ctrlDiag, 'incrementLowerActive', false));
        log.dNgMeasured(idx) = sht_log_record.getField(ctrlDiag, 'dNgMeasured', NaN);
        log.dZ2(idx) = sht_log_record.getField(ctrlDiag, 'dZ2', NaN);
        log.dWf_raw_increment(idx) = sht_log_record.getField(ctrlDiag, 'dWf_raw_increment', sht_log_record.getField(ctrlDiag, 'dURaw', 0));
        log.dWf_final(idx) = sht_log_record.getField(ctrlDiag, 'dWf_final', sht_log_record.getField(ctrlDiag, 'dU', 0));
        log.dWf_aw_error(idx) = sht_log_record.getField(ctrlDiag, 'dWf_aw_error', log.dWf_final(idx) - log.dWf_raw_increment(idx));
        log.dWf_upper_bound(idx) = sht_log_record.getField(ctrlDiag, 'dWf_upper_bound', NaN);
        log.dWf_lower_bound(idx) = sht_log_record.getField(ctrlDiag, 'dWf_lower_bound', NaN);
        log.WfRate(idx) = actDiag.limitedRate;
        log.WfRateRaw(idx) = actDiag.rawRate;
        log.dURaw(idx) = ctrlDiag.dURaw;
        log.dU(idx) = ctrlDiag.dU;
        log.uNp(idx) = ctrlDiag.uNp;
        log.z2Ng(idx) = ctrlDiag.z2Ng;
        log.maxErr(idx) = engineDiag.maxErr;
        log.convergeTag(idx) = engineDiag.convergeTag;
        log.evaluationValid(idx) = sht_log_record.getField( ...
            engineDiag, 'evaluationValid', 1);
        log.visserEnergyResidual_W(idx) = sht_log_record.getField( ...
            engineDiag, 'visserEnergyResidual_W', NaN);
        log.visserNormalizedEnergyResidual(idx) = sht_log_record.getField( ...
            engineDiag, 'visserNormalizedEnergyResidual', NaN);
        coolingIn = sht_log_record.getField( ...
            engineDiag, 'visserCoolingInletTemperature_K', []);
        coolingOut = sht_log_record.getField( ...
            engineDiag, 'visserCoolingOutletTemperature_K', []);
        if numel(coolingIn)==10 && numel(coolingOut)==10 && ...
                all(isfinite(coolingIn(:))) && all(isfinite(coolingOut(:)))
            log.visserMaximumCoolingTemperatureChange_K(idx) = ...
                max(abs(coolingOut(:)-coolingIn(:)));
        end
        log.controlUpdate(idx) = didControlUpdate;
    end

    function log = addDerivedSignals(log)
        % 仿真结束后补充数值导数诊断。
        % dNpDerived/dNgDerived 仅用于后处理观察，不是传感器测得的 dNp/dNg，也不进入控制器。
        t = log.time(:);
        if numel(t) < 2
            log.dNpDerived(:) = 0;
            log.dNgDerived(:) = 0;
            return;
        end
        dt = [NaN; diff(t)];
        dNp = [0; diff(log.Np(:))];
        dNg = [0; diff(log.Ng(:))];
        valid = isfinite(dt) & dt > 0;
        log.dNpDerived(:) = 0;
        log.dNgDerived(:) = 0;
        log.dNpDerived(valid) = dNp(valid) ./ dt(valid);
        log.dNgDerived(valid) = dNg(valid) ./ dt(valid);
    end

    function diagInfo = emptyControllerDiag(state)
        % 初始时刻控制器诊断量。
        % t=0 时尚未执行控制器采样，但日志字段必须完整，因此用配平状态构造一组中性诊断量。
        diagInfo = struct();
        diagInfo.z2Ng = state.z2Ng;
        diagInfo.uNp = state.uNp;
        diagInfo.dURaw = state.dURaw;
        diagInfo.dU = state.dU;
        diagInfo.wfCommand = state.Wfcmd;
        diagInfo.wfCommandNext = state.Wfcmd;
        diagInfo.wfCommandNow = state.Wfcmd;
        diagInfo.Wf_main_next = state.Wfcmd;
        diagInfo.Wf_selected_next = state.Wfcmd;
        diagInfo.Wf_main_raw_next = state.Wfcmd;
        diagInfo.Wf_main_limited_next = state.Wfcmd;
        diagInfo.Wf_selector_delta = 0;
        diagInfo.Nu_main = 0;
        diagInfo.Nu_selected = 0;
        diagInfo.Nu_upper_bound = NaN;
        diagInfo.Nu_lower_bound = NaN;
        diagInfo.Nu_NgTop_max = NaN;
        diagInfo.Nu_T45_max = NaN;
        diagInfo.Nu_Mkp_max = NaN;
        diagInfo.Nu_accel_max = NaN;
        diagInfo.Nu_decel_min = NaN;
        diagInfo.Nu_selector_delta = 0;
        diagInfo.accelDecelLimitEnabled = false;
        diagInfo.accelLimitSelected = false;
        diagInfo.decelLimitSelected = false;
        diagInfo.NgMax = NaN;
        diagInfo.NgTopRef = NaN;
        diagInfo.NgTopError = NaN;
        diagInfo.NgTopProtectionError = NaN;
        diagInfo.NgTopCommandError = NaN;
        diagInfo.NgTopCommandErrorPrev = NaN;
        diagInfo.NgTopCommandErrorDelta = NaN;
        diagInfo.NgTopErrorGain = NaN;
        diagInfo.NgTopErrorDeltaGain = NaN;
        diagInfo.ngTopProtectionActive = false;
        diagInfo.ngTopProtectionSelected = false;
        diagInfo.T45Max = NaN;
        diagInfo.T45Ref = NaN;
        diagInfo.T45CommandError = NaN;
        diagInfo.T45CommandErrorPrev = NaN;
        diagInfo.T45Delta = NaN;
        diagInfo.T45ErrorGainNu = NaN;
        diagInfo.T45GainScheduleK = NaN;
        diagInfo.T45NuScale = NaN;
        diagInfo.T45TempRateGainNu = NaN;
        diagInfo.K_TNu = NaN;
        diagInfo.T45TargetOmega = NaN;
        diagInfo.T45TargetZeta = NaN;
        diagInfo.MkpMax = NaN;
        diagInfo.MkpRef = NaN;
        diagInfo.MkpCommandError = NaN;
        diagInfo.MkpCommandErrorPrev = NaN;
        diagInfo.MkpDelta = NaN;
        diagInfo.MkpErrorGainNu = NaN;
        diagInfo.MkpGainScheduleK = NaN;
        diagInfo.MkpNuScale = NaN;
        diagInfo.MkpD41 = NaN;
        diagInfo.t45ProtectionActive = false;
        diagInfo.t45ProtectionSelected = false;
        diagInfo.mkpProtectionActive = false;
        diagInfo.mkpProtectionSelected = false;
        diagInfo.incrementBoundsApplied = false;
        diagInfo.incrementUpperActive = false;
        diagInfo.incrementLowerActive = false;
        diagInfo.dNgMeasured = NaN;
        diagInfo.dZ2 = NaN;
        diagInfo.dWf_raw_increment = 0;
        diagInfo.dWf_final = 0;
        diagInfo.dWf_aw_error = 0;
        diagInfo.dWf_upper_bound = NaN;
        diagInfo.dWf_lower_bound = NaN;
        diagInfo.Wf_rate_up_max = NaN;
        diagInfo.Wf_rate_down_min = NaN;
        diagInfo.Wf_upper_bound = NaN;
        diagInfo.Wf_lower_bound = NaN;
        diagInfo.fuelUpperActive = false;
        diagInfo.fuelLowerActive = false;
        diagInfo.fuelBoundsApplied = false;
        diagInfo.Wf_main_now = state.Wfcmd;
        diagInfo.Wf_selected_now = state.Wfcmd;
        diagInfo.controlMode = 'SPEED_GOVERNING';
        diagInfo.controlModeId = 1;
        diagInfo.selectorMode = 'incrementAuthority';
        diagInfo.selectorModeId = 1;
        diagInfo.fullControlEnabled = true;
        diagInfo.gainScheduleEnabled = false;
        diagInfo.gainScheduleNgc = NaN;
        diagInfo.gainScheduleNgcClamped = NaN;
        diagInfo.gainScheduleAtLowerBound = false;
        diagInfo.gainScheduleAtUpperBound = false;
        diagInfo.ndotScheduleEnabled = false;
        diagInfo.ndotScheduleNgc = NaN;
        diagInfo.ndotScheduleNgcClamped = NaN;
        diagInfo.ndotScheduleAtLowerBound = false;
        diagInfo.ndotScheduleAtUpperBound = false;
        diagInfo.NgdotMaxSchedule = NaN;
        diagInfo.NgdotMinSchedule = NaN;
        diagInfo.AccelWfLimitSchedule = NaN;
        diagInfo.DecelWfLimitSchedule = NaN;
        diagInfo.accelDecelLimitEnabled = false;
        diagInfo.linearB11 = NaN;
        diagInfo.linearB21 = NaN;
        diagInfo.linearD31 = NaN;
        diagInfo.linearD41 = NaN;
        diagInfo.limitConflict = false;
        diagInfo.z3 = state.z3;
        diagInfo.WfFilterState = state.WfFilterState;
        diagInfo.NgFilterState = state.NgFilterState;
        diagInfo.trWfState = state.trWfState;
        diagInfo.trNgState = state.trNgState;
    end
end

methods (Static, Access = private)
    function value = getField(s, name, defaultValue)
        % 安全读取结构体字段。缺字段、空字段或非结构体时返回默认值。
        if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
            value = s.(name);
        else
            value = defaultValue;
        end
    end
end
end
