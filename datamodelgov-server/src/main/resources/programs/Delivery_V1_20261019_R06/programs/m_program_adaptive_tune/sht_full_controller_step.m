function [wfCommandNext, state, diagInfo] = sht_full_controller_step( ...
    state, sample, ref, cfg, dt, method)
% 阅读说明：
%   本文件是完整控制器单拍计算的核心调度函数。
%   控制结构为：Np 稳态调速器计算 Nu_main；Ng/T45/Mkp 保护分别计算 Nu 上限；高低选得到 Nu_selected；
%   再把 Nu_selected 换算为燃油增量 dWf，并统一通过燃油增量饱和器处理执行机构约束。
%   这里不推进发动机和执行器状态，只更新控制器内部离散状态和诊断量。
%SHT_FULL_CONTROLLER_STEP Full above-idle controller shell.
%
% Stage 4.5 moves the main selection variable from absolute fuel flow to
% the Np-governor Ng-command increment Nu. Fuel min/max and rate limits are
% applied once to the final fuel increment dWf.

% 0) 根据当前控制器采样 Ngc 调度线性化控制系数。后续 Np 主回路、T45/Mkp
%    保护和 Nu->dWf 反算都使用同一组本拍系数。
[cfg, gainScheduleDiag] = sht_apply_controller_gain_schedule(cfg, sample);
[cfg, ndotScheduleDiag] = sht_apply_controller_ndot_schedule(cfg, sample, dt);

% 1) 先只计算 Np 主调速器候选量，不更新状态；保护回路后续要复用这些候选量。
candidate = sht_steady_governor_compute(state, sample, ref, cfg, dt);
[wfCommandNext, state, diagInfo] = local_step_increment_authority( ...
    state, candidate, cfg, dt, method, ndotScheduleDiag);
diagInfo.gainScheduleEnabled = gainScheduleDiag.enabled;
diagInfo.gainScheduleNgc = gainScheduleDiag.Ngc;
diagInfo.gainScheduleNgcClamped = gainScheduleDiag.NgcClamped;
diagInfo.gainScheduleAtLowerBound = gainScheduleDiag.atLowerBound;
diagInfo.gainScheduleAtUpperBound = gainScheduleDiag.atUpperBound;
diagInfo.linearB11 = cfg.linearModel.b11;
diagInfo.linearB21 = cfg.linearModel.b21;
diagInfo.linearD31 = cfg.linearModel.d31;
diagInfo.linearD41 = cfg.linearModel.d41;
diagInfo.ndotScheduleEnabled = ndotScheduleDiag.enabled;
diagInfo.ndotScheduleNgc = ndotScheduleDiag.Ngc;
diagInfo.ndotScheduleNgcClamped = ndotScheduleDiag.NgcClamped;
diagInfo.ndotScheduleAtLowerBound = ndotScheduleDiag.atLowerBound;
diagInfo.ndotScheduleAtUpperBound = ndotScheduleDiag.atUpperBound;
diagInfo.NgdotMaxSchedule = ndotScheduleDiag.NgdotMax;
diagInfo.NgdotMinSchedule = ndotScheduleDiag.NgdotMin;
diagInfo.AccelWfLimitSchedule = ndotScheduleDiag.AccelWfLimit;
diagInfo.DecelWfLimitSchedule = ndotScheduleDiag.DecelWfLimit;
end

function [wfCommandNext, state, diagInfo] = local_step_increment_authority( ...
    state, candidate, cfg, dt, method, ndotScheduleDiag)
% 2) Nu 候选集合。
%    Nu_main 是 Np 主调速器希望施加的 Ng 指令增量；
%    Nu_upper_bound/Nu_lower_bound 是限制保护对该增量的允许范围。
incrementCandidates = struct();
incrementCandidates.Nu_main = candidate.Nu_main;
incrementCandidates.Nu_upper_bound = inf;
incrementCandidates.Nu_lower_bound = -inf;
accelDecelLimitEnabled = local_is_accel_decel_limit_enabled(cfg);
if accelDecelLimitEnabled
    incrementCandidates.Nu_accel_max = ndotScheduleDiag.Nu_accel_max;
    incrementCandidates.Nu_decel_min = ndotScheduleDiag.Nu_decel_min;
else
    incrementCandidates.Nu_accel_max = inf;
    incrementCandidates.Nu_decel_min = -inf;
end
% 3) 三类上限保护都只输出 Nu 域的上限候选。
%    它们不直接改燃油，也不单独做执行机构抗饱和。
[nuNgTopMax, ngTopDiag] = sht_ng_protection_limiter( ...
    candidate, state, cfg, dt);
incrementCandidates.Nu_NgTop_max = nuNgTopMax;
[nuT45Max, t45Diag] = sht_t45_protection_limiter( ...
    candidate, state, cfg, dt);
incrementCandidates.Nu_T45_max = nuT45Max;
[nuMkpMax, mkpDiag] = sht_mkp_protection_limiter( ...
    candidate, state, cfg, dt);
incrementCandidates.Nu_Mkp_max = nuMkpMax;
incrementCandidates.Nu_NgBottom_min = -inf;
% 4) 上限保护采用低选逻辑：谁给出的允许 Nu 更小，谁对主回路约束更强。
incrementCandidates.Nu_upper_bound = min( ...
    incrementCandidates.Nu_upper_bound, ...
    incrementCandidates.Nu_NgTop_max);
incrementCandidates.Nu_upper_bound = min( ...
    incrementCandidates.Nu_upper_bound, ...
    incrementCandidates.Nu_T45_max);
incrementCandidates.Nu_upper_bound = min( ...
    incrementCandidates.Nu_upper_bound, ...
    incrementCandidates.Nu_Mkp_max);
% 加速限制是对 Nu 的上限约束：主回路希望的正向 Ng 指令增量不能超过
% NgdotMax(Ngc)*Tctrl。这里把加速计划与 Ng/T45/Mkp 上限保护放在同一个低选链路中。
incrementCandidates.Nu_upper_bound = min( ...
    incrementCandidates.Nu_upper_bound, ...
    incrementCandidates.Nu_accel_max);
% 减速限制是对 Nu 的下限约束：主回路希望的负向 Ng 指令增量不能低于
% NgdotMin(Ngc)*Tctrl。这里用高选形成最终下限。
incrementCandidates.Nu_lower_bound = max( ...
    incrementCandidates.Nu_lower_bound, ...
    incrementCandidates.Nu_decel_min);

% 5) 在 Nu 域完成高低选，得到最终参与燃油换算的 Nu_selected。
%    若 Nu_selected < Nu_main，说明至少一个上限保护正在压低主调速器需求。
[nuSelected, incrementDiag] = sht_increment_selector( ...
    incrementCandidates, cfg);
% 判断“被选中”的保护，而不只是“候选激活”。只有成为最终最小上限并压低 Nu_main 才记为 selected。
ngTopDiag.ngTopProtectionSelected = local_is_ng_top_selected( ...
    nuSelected, candidate.Nu_main, incrementDiag, ngTopDiag);
t45Diag.t45ProtectionSelected = local_is_t45_selected( ...
    nuSelected, candidate.Nu_main, incrementDiag, t45Diag);
mkpDiag.mkpProtectionSelected = local_is_mkp_selected( ...
    nuSelected, candidate.Nu_main, incrementDiag, mkpDiag);
accelLimitSelected = local_is_accel_selected( ...
    nuSelected, candidate.Nu_main, incrementDiag);
decelLimitSelected = local_is_decel_selected( ...
    nuSelected, candidate.Nu_main, incrementDiag);
% 6) 将选中的 Nu 反算为燃油增量。这里仍是原始增量，尚未施加 WfMin/WfMax/速率限制。
dWfRaw = local_wf_increment_from_nu(nuSelected, ...
    candidate.dNgMeasured, candidate.dZ2, cfg);
% 7) 统一燃油增量饱和：所有控制/保护回路共用这一处执行机构约束处理。
[dWfFinal, fuelDiag] = sht_fuel_increment_saturator( ...
    dWfRaw, candidate.WfcmdDelayPrev, cfg, dt);
wfSelectedNext = fuelDiag.Wf_selected_next;

% 8) 把选择和饱和结果回填到 candidate，后续 finalize 只按最终结果更新状态。
candidate.Nu_selected = nuSelected;
candidate.Nu_upper_bound = incrementDiag.Nu_upper_bound;
candidate.Nu_lower_bound = incrementDiag.Nu_lower_bound;
candidate.Nu_NgTop_max = incrementDiag.Nu_NgTop_max;
candidate.Nu_T45_max = incrementDiag.Nu_T45_max;
candidate.Nu_Mkp_max = incrementDiag.Nu_Mkp_max;
candidate.Nu_accel_max = incrementDiag.Nu_accel_max;
candidate.Nu_decel_min = incrementDiag.Nu_decel_min;
candidate.Nu_selector_delta = incrementDiag.Nu_selector_delta;
candidate.incrementBoundsApplied = incrementDiag.incrementBoundsApplied;
candidate.incrementUpperActive = incrementDiag.incrementUpperActive;
candidate.incrementLowerActive = incrementDiag.incrementLowerActive;
candidate.dURaw = dWfRaw;
candidate.dUInternal = dWfFinal;
candidate.dWf_raw_increment = dWfRaw;
candidate.dWf_final = dWfFinal;
candidate.dWf_aw_error = fuelDiag.dWf_aw_error;
candidate.dWf_upper_bound = fuelDiag.dWf_upper_bound;
candidate.dWf_lower_bound = fuelDiag.dWf_lower_bound;
candidate.Wf_raw_next = candidate.WfcmdDelayPrev + dWfRaw;
candidate.Wf_selected_next = wfSelectedNext;

wfCommandNext = wfSelectedNext;
% 9) 最后统一更新控制器记忆量：上一拍转速、z2、z3、低通滤波器和燃油输出寄存器。
[state, governorDiag] = sht_steady_governor_finalize(state, candidate, ...
    wfSelectedNext, cfg, dt, method);
% 保护回路自己的上一拍误差在完整控制器外层更新，保持与各保护候选计算函数解耦。
state.NgTopCommandErrorPrev = ngTopDiag.NgTopCommandError;
state.NgTopErrorPrev = ngTopDiag.NgTopCommandError;
state.T45Prev = t45Diag.T45;
state.T45CommandErrorPrev = t45Diag.T45CommandError;
state.MkpPrev = mkpDiag.Mkp;
state.MkpCommandErrorPrev = mkpDiag.MkpCommandError;
wfCommandNow = governorDiag.wfCommandNow;

% 10) 诊断量集中打包，便于测试脚本和绘图直接查看每个候选是否起作用。
diagInfo = governorDiag;
diagInfo.wfCommand = wfCommandNow;
diagInfo.wfCommandNext = wfSelectedNext;
diagInfo.wfCommandNow = wfCommandNow;
diagInfo.Wf_main_next = candidate.WfcmdDelayPrev + dWfRaw;
diagInfo.Wf_selected_next = wfSelectedNext;
diagInfo.Wf_main_raw_next = candidate.Wf_main_raw_next;
diagInfo.Wf_main_limited_next = candidate.Wf_main_limited_next;
diagInfo.Wf_main_now = wfCommandNow;
diagInfo.Wf_selected_now = wfCommandNow;
diagInfo.Wf_selector_delta = wfSelectedNext - candidate.Wf_main_raw_next;
diagInfo.Wf_rate_up_max = fuelDiag.Wf_rate_up_max;
diagInfo.Wf_rate_down_min = fuelDiag.Wf_rate_down_min;
diagInfo.Wf_upper_bound = fuelDiag.Wf_upper_bound;
diagInfo.Wf_lower_bound = fuelDiag.Wf_lower_bound;
diagInfo.fuelUpperActive = fuelDiag.fuelUpperActive;
diagInfo.fuelLowerActive = fuelDiag.fuelLowerActive;
diagInfo.fuelBoundsApplied = fuelDiag.fuelBoundsApplied;
diagInfo.Nu_main = incrementDiag.Nu_main;
diagInfo.Nu_selected = incrementDiag.Nu_selected;
diagInfo.Nu_upper_bound = incrementDiag.Nu_upper_bound;
diagInfo.Nu_lower_bound = incrementDiag.Nu_lower_bound;
diagInfo.Nu_NgTop_max = incrementDiag.Nu_NgTop_max;
diagInfo.Nu_T45_max = incrementDiag.Nu_T45_max;
diagInfo.Nu_Mkp_max = incrementDiag.Nu_Mkp_max;
diagInfo.Nu_accel_max = incrementDiag.Nu_accel_max;
diagInfo.Nu_decel_min = incrementDiag.Nu_decel_min;
diagInfo.Nu_selector_delta = incrementDiag.Nu_selector_delta;
diagInfo.accelDecelLimitEnabled = accelDecelLimitEnabled;
diagInfo.accelLimitSelected = accelLimitSelected;
diagInfo.decelLimitSelected = decelLimitSelected;
diagInfo.incrementBoundsApplied = incrementDiag.incrementBoundsApplied;
diagInfo.incrementUpperActive = incrementDiag.incrementUpperActive;
diagInfo.incrementLowerActive = incrementDiag.incrementLowerActive;
diagInfo.dWf_raw_increment = fuelDiag.dWf_raw_increment;
diagInfo.dWf_final = fuelDiag.dWf_final;
diagInfo.dWf_aw_error = fuelDiag.dWf_aw_error;
diagInfo.dWf_upper_bound = fuelDiag.dWf_upper_bound;
diagInfo.dWf_lower_bound = fuelDiag.dWf_lower_bound;
diagInfo.selectorMode = incrementDiag.mode;
diagInfo.selectorModeId = incrementDiag.modeId;
diagInfo.NgMax = ngTopDiag.NgMax;
diagInfo.NgTopRef = ngTopDiag.NgTopRef;
diagInfo.NgTopError = ngTopDiag.NgTopError;
diagInfo.NgTopProtectionError = ngTopDiag.NgTopProtectionError;
diagInfo.NgTopCommandError = ngTopDiag.NgTopCommandError;
diagInfo.NgTopCommandErrorPrev = ngTopDiag.NgTopCommandErrorPrev;
diagInfo.NgTopCommandErrorDelta = ngTopDiag.NgTopCommandErrorDelta;
diagInfo.NgTopErrorGain = ngTopDiag.NgTopErrorGain;
diagInfo.NgTopErrorDeltaGain = ngTopDiag.NgTopErrorDeltaGain;
diagInfo.NgTopControlLaw = ngTopDiag.NgTopControlLaw;
diagInfo.ngTopProtectionActive = ngTopDiag.ngTopProtectionActive;
diagInfo.ngTopProtectionSelected = ngTopDiag.ngTopProtectionSelected;
diagInfo.T45Max = t45Diag.T45Max;
diagInfo.T45Ref = t45Diag.T45Ref;
diagInfo.T45CommandError = t45Diag.T45CommandError;
diagInfo.T45CommandErrorPrev = t45Diag.T45CommandErrorPrev;
diagInfo.T45Delta = t45Diag.T45Delta;
diagInfo.T45ControlLaw = t45Diag.T45ControlLaw;
diagInfo.T45ErrorGain = t45Diag.T45ErrorGain;
diagInfo.T45ErrorGainNu = t45Diag.T45ErrorGainNu;
diagInfo.T45ScaledErrorGainNu = t45Diag.T45ScaledErrorGainNu;
diagInfo.T45GainScheduleK = t45Diag.T45GainScheduleK;
diagInfo.T45NuScale = t45Diag.T45NuScale;
diagInfo.T45TempRateGainNu = t45Diag.T45TempRateGainNu;
diagInfo.T45D31 = t45Diag.T45D31;
diagInfo.K_TNu = t45Diag.K_TNu;
diagInfo.T45TargetOmega = t45Diag.T45TargetOmega;
diagInfo.T45TargetZeta = t45Diag.T45TargetZeta;
diagInfo.t45ProtectionActive = t45Diag.t45ProtectionActive;
diagInfo.t45ProtectionSelected = t45Diag.t45ProtectionSelected;
diagInfo.MkpMax = mkpDiag.MkpMax;
diagInfo.MkpRef = mkpDiag.MkpRef;
diagInfo.MkpCommandError = mkpDiag.MkpCommandError;
diagInfo.MkpCommandErrorPrev = mkpDiag.MkpCommandErrorPrev;
diagInfo.MkpDelta = mkpDiag.MkpDelta;
diagInfo.MkpControlLaw = mkpDiag.MkpControlLaw;
diagInfo.MkpErrorGain = mkpDiag.MkpErrorGain;
diagInfo.MkpErrorGainNu = mkpDiag.MkpErrorGainNu;
diagInfo.MkpGainScheduleK = mkpDiag.MkpGainScheduleK;
diagInfo.MkpNuScale = mkpDiag.MkpNuScale;
diagInfo.MkpD41 = mkpDiag.MkpD41;
diagInfo.mkpProtectionActive = mkpDiag.mkpProtectionActive;
diagInfo.mkpProtectionSelected = mkpDiag.mkpProtectionSelected;
% 控制模式编号仅用于日志和绘图识别，不反向参与控制计算。
if accelLimitSelected
    diagInfo.controlMode = 'ACCEL_LIMITING';
    diagInfo.controlModeId = 8;
elseif decelLimitSelected
    diagInfo.controlMode = 'DECEL_LIMITING';
    diagInfo.controlModeId = 9;
elseif ngTopDiag.ngTopProtectionSelected
    diagInfo.controlMode = 'NG_TOP_LIMITING';
    diagInfo.controlModeId = 5;
elseif t45Diag.t45ProtectionSelected
    diagInfo.controlMode = 'TEMP_LIMITING';
    diagInfo.controlModeId = 6;
elseif mkpDiag.mkpProtectionSelected
    diagInfo.controlMode = 'TORQUE_LIMITING';
    diagInfo.controlModeId = 7;
else
    diagInfo.controlMode = incrementDiag.controlMode;
    diagInfo.controlModeId = incrementDiag.controlModeId;
end
diagInfo.fullControlEnabled = true;
diagInfo.limitConflict = incrementDiag.limitConflict;
end

function enabled = local_is_accel_decel_limit_enabled(cfg)
enabled = false;
if isstruct(cfg) && isfield(cfg, 'accelDecelLimit') ...
        && isstruct(cfg.accelDecelLimit) ...
        && isfield(cfg.accelDecelLimit, 'enable') ...
        && ~isempty(cfg.accelDecelLimit.enable)
    enabled = logical(cfg.accelDecelLimit.enable);
end
end

function selected = local_is_accel_selected(nuSelected, nuMain, incrementDiag)
% 加速限制是否真正接管：最终上限来自 Nu_accel_max，且确实压低了主回路需求。
tol = 1e-12;
selected = incrementDiag.incrementUpperActive ...
    && isfinite(incrementDiag.Nu_accel_max) ...
    && abs(incrementDiag.Nu_upper_bound - incrementDiag.Nu_accel_max) <= tol ...
    && nuSelected < nuMain - tol;
end

function selected = local_is_decel_selected(nuSelected, nuMain, incrementDiag)
% 减速限制是否真正接管：最终下限来自 Nu_decel_min，且确实抬高了主回路需求。
tol = 1e-12;
selected = incrementDiag.incrementLowerActive ...
    && isfinite(incrementDiag.Nu_decel_min) ...
    && abs(incrementDiag.Nu_lower_bound - incrementDiag.Nu_decel_min) <= tol ...
    && nuSelected > nuMain + tol;
end

function selected = local_is_mkp_selected(nuSelected, nuMain, incrementDiag, mkpDiag)
% Mkp 是否真正接管：最终上限等于 Nu_Mkp_max，且选择结果确实低于主回路需求。
tol = 1e-12;
selected = incrementDiag.incrementUpperActive ...
    && isfinite(mkpDiag.Nu_Mkp_max) ...
    && abs(incrementDiag.Nu_upper_bound - mkpDiag.Nu_Mkp_max) <= tol ...
    && nuSelected < nuMain - tol;
end
function dWf = local_wf_increment_from_nu(nu, dNgMeasured, dZ2, cfg)
% Nu 到燃油增量的反算式来自原稳态调速器结构：
%   dWf = [ngCompGain*(Nu-dNgMeasured)-dZ2]/b21。
% 其中 dNgMeasured 和 dZ2 抵消已测得的本拍转速变化和补偿量变化。
dWf = (cfg.ngCompGain * (nu - dNgMeasured) - dZ2) / cfg.linearModel.b21;
end

function tf = local_is_ng_top_selected(nuSelected, nuMain, incrementDiag, ngTopDiag)
% Ng 上限保护是否真正接管。
tol = 1e-12;
tf = incrementDiag.incrementUpperActive ...
    && isfinite(ngTopDiag.Nu_NgTop_max) ...
    && abs(incrementDiag.Nu_upper_bound - ngTopDiag.Nu_NgTop_max) <= tol ...
    && nuSelected < nuMain - tol;
end

function tf = local_is_t45_selected(nuSelected, nuMain, incrementDiag, t45Diag)
% T45 温度保护是否真正接管。
tol = 1e-12;
tf = incrementDiag.incrementUpperActive ...
    && isfinite(t45Diag.Nu_T45_max) ...
    && abs(incrementDiag.Nu_upper_bound - t45Diag.Nu_T45_max) <= tol ...
    && nuSelected < nuMain - tol;
end
