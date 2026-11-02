function [state, diagInfo] = sht_steady_governor_finalize( ...
    state, candidate, wfCommandNext, cfg, dt, method)
% 阅读说明：
%   本文件在 Nu 高低选和燃油饱和完成之后，统一更新 Np 主调速器的离散状态。
%   commandDelay 决定当前拍实际输出 WfcmdNow 是本拍新值还是上一拍寄存器值。
%   z3、WfFilterState、NgFilterState 均在本函数末端更新，供下一控制采样周期使用。
%SHT_STEADY_GOVERNOR_FINALIZE Update steady-governor states after selection.
%
% wfCommandNext is the final fuel command selected for the next controller
% period. This separation lets the full controller apply limits in the
% selector while keeping the governor filters consistent with final fuel.

if ~isfield(cfg, 'filterDiscretization') || isempty(cfg.filterDiscretization)
    cfg.filterDiscretization = 'euler2';
end

% oneSample 时序：本拍刚算出的 wfCommandNext 写入寄存器，当前执行机构看到的仍是上一拍命令。
% zeroDelay 主要用于与理想直接馈通或早期模型对照。
if isfield(cfg, 'commandDelay') && strcmpi(cfg.commandDelay, 'oneSample')
    wfCommandNow = candidate.WfcmdDelayPrev;
else
    wfCommandNow = wfCommandNext;
end

% 用当前拍实际施加的 WfcmdNow 更新控制器内部连续近似环节，而不是用尚未施加的 WfcmdNext。
state = local_update_post_control_filters(state, wfCommandNow, ...
    candidate.Ng, cfg, dt, method);

% 保存本拍测量量和补偿量，下一拍用于差分项和滤波器输入端点。
state.NpPrev = candidate.Np;
state.NgPrev = candidate.Ng;
state.z2NgPrev = candidate.z2Ng;
% WfcmdDelay 保存“本拍计算的下一拍命令”；state.Wfcmd 保存“本拍实际输出命令”。
state.WfcmdDelay = wfCommandNext;
state.Wfcmd = wfCommandNow;
state.dURaw = candidate.dURaw;
state.dU = wfCommandNext - candidate.WfcmdDelayPrev;
state.uNp = candidate.uNp;
state.z2Ng = candidate.z2Ng;

if strcmpi(cfg.filterDiscretization, 'tustin')
    filterMode = 'tustin';
else
    filterMode = 'euler2';
end

% 诊断量保留主回路视角；完整控制器会在外层继续补充保护选择和最终模式。
diagInfo = struct();
diagInfo.z2Ng = candidate.z2Ng;
diagInfo.uNp = candidate.uNp;
diagInfo.Nu_main = local_get_candidate_field(candidate, 'Nu_main', candidate.uNp);
diagInfo.Nu_selected = local_get_candidate_field(candidate, ...
    'Nu_selected', diagInfo.Nu_main);
diagInfo.Nu_upper_bound = local_get_candidate_field(candidate, ...
    'Nu_upper_bound', inf);
diagInfo.Nu_lower_bound = local_get_candidate_field(candidate, ...
    'Nu_lower_bound', -inf);
diagInfo.Nu_selector_delta = local_get_candidate_field(candidate, ...
    'Nu_selector_delta', 0);
diagInfo.incrementBoundsApplied = local_get_candidate_field(candidate, ...
    'incrementBoundsApplied', false);
diagInfo.incrementUpperActive = local_get_candidate_field(candidate, ...
    'incrementUpperActive', false);
diagInfo.incrementLowerActive = local_get_candidate_field(candidate, ...
    'incrementLowerActive', false);
diagInfo.dNgMeasured = local_get_candidate_field(candidate, ...
    'dNgMeasured', candidate.Ng - state.NgPrev);
diagInfo.dZ2 = local_get_candidate_field(candidate, 'dZ2', 0);
diagInfo.dURaw = candidate.dURaw;
diagInfo.dU = state.dU;
diagInfo.dWf_raw_increment = local_get_candidate_field(candidate, ...
    'dWf_raw_increment', candidate.dURaw);
diagInfo.dWf_final = state.dU;
diagInfo.dWf_aw_error = local_get_candidate_field(candidate, ...
    'dWf_aw_error', state.dU - candidate.dURaw);
diagInfo.dWf_upper_bound = local_get_candidate_field(candidate, ...
    'dWf_upper_bound', NaN);
diagInfo.dWf_lower_bound = local_get_candidate_field(candidate, ...
    'dWf_lower_bound', NaN);
diagInfo.wfCommand = wfCommandNow;
diagInfo.wfCommandNext = wfCommandNext;
diagInfo.wfCommandNow = wfCommandNow;
diagInfo.Wf_main_next = wfCommandNext;
diagInfo.Wf_main_now = wfCommandNow;
diagInfo.Wf_main_raw_next = candidate.Wf_main_raw_next;
diagInfo.Wf_main_limited_next = candidate.Wf_main_limited_next;
diagInfo.Wf_selected_next = wfCommandNext;
diagInfo.Wf_selected_now = wfCommandNow;
diagInfo.Wf_selector_delta = 0;
diagInfo.Wf_rate_up_max = NaN;
diagInfo.Wf_rate_down_min = NaN;
diagInfo.Wf_upper_bound = NaN;
diagInfo.Wf_lower_bound = NaN;
diagInfo.dWf_main_raw = candidate.dURaw;
diagInfo.dWf_main_limited = candidate.dUInternal;
diagInfo.z3 = state.z3;
diagInfo.WfFilterState = state.WfFilterState;
diagInfo.NgFilterState = state.NgFilterState;
diagInfo.trWfState = state.WfFilterState - cfg.initial.Wf;
diagInfo.trNgState = state.NgFilterState - cfg.initial.Ng;
diagInfo.filterDiscretization = filterMode;
diagInfo.controlMode = 'SPEED_GOVERNING';
diagInfo.controlModeId = 1;
diagInfo.selectorMode = 'legacy';
diagInfo.selectorModeId = 0;
diagInfo.fullControlEnabled = false;
diagInfo.fuelUpperActive = false;
diagInfo.fuelLowerActive = false;
diagInfo.fuelBoundsApplied = false;
diagInfo.limitConflict = false;
end

function state = local_update_post_control_filters(state, wfCommandNow, Ng, cfg, dt, method)
% 更新控制器内部 z3 和两个一阶低通滤波器。
% 这些量属于控制器离散状态，不是发动机或传感器连续状态。
if dt <= 0
    return;
end

% z3 是控制器内部燃油命令滤波/执行近似状态；它使用 WfcmdNow 而不是 WfcmdNext 更新。
z3Prev = state.z3;
ngInputPrev = state.NgPrev;
ngInputNow = Ng;

% 先更新 z3，再把 z3 的前后端点作为 WfFilterState 一阶低通的输入端点。
state.z3 = local_update_z3(state.z3, wfCommandNow, cfg, dt, method);
wfInputPrev = z3Prev;
wfInputNow = state.z3;

% Tustin 和二阶欧拉都按采样周期离散化；二者只影响控制器内部滤波器，不改变对象积分方法。
switch lower(cfg.filterDiscretization)
    case 'tustin'
        state.WfFilterState = local_first_order_tustin( ...
            state.WfFilterState, wfInputPrev, wfInputNow, cfg.filterOmega, dt);
        state.NgFilterState = local_first_order_tustin( ...
            state.NgFilterState, ngInputPrev, ngInputNow, cfg.filterOmega, dt);
    case 'euler2'
        state.WfFilterState = local_first_order_euler2( ...
            state.WfFilterState, wfInputPrev, wfInputNow, cfg.filterOmega, dt);
        state.NgFilterState = local_first_order_euler2( ...
            state.NgFilterState, ngInputPrev, ngInputNow, cfg.filterOmega, dt);
    otherwise
        error('sht:controller:filterDiscretization', ...
            'controller.filterDiscretization must be ''tustin'' or ''euler2''.');
end

state.trWfState = state.WfFilterState - cfg.initial.Wf;
state.trNgState = state.NgFilterState - cfg.initial.Ng;
end

function z3 = local_update_z3(z3, wfCommandNow, cfg, dt, method)
% z3 连续模型：dz3/dt=omega_u*(WfcmdNow-z3)，导数再受 WfRateLimit 限制。
% euler2 时先预测 z3Pred，再平均 k/k+1 两端导数。
dzA = local_z3_derivative(z3, wfCommandNow, cfg);
if strcmpi(method, 'euler2')
    z3Pred = z3 + dt * dzA;
    dzB = local_z3_derivative(z3Pred, wfCommandNow, cfg);
    z3 = z3 + 0.5 * dt * (dzA + dzB);
else
    z3 = z3 + dt * dzA;
end
end

function dx = local_z3_derivative(z3, wfCommandNow, cfg)
% 这里的速率限制是控制器内部滤波状态的限制，与最终燃油增量饱和器分工不同。
dxRaw = cfg.wfFilterOmega * (wfCommandNow - z3);
dx = min(max(dxRaw, -cfg.wfRateLimit), cfg.wfRateLimit);
end

function x = local_first_order_tustin(xPrev, uPrev, uNow, omega, dt)
% 双线性变换离散化一阶低通：当前输入和上一拍输入以梯形形式共同进入。
alpha = 0.5 * omega * dt;
a = (1 - alpha) / (1 + alpha);
b = alpha / (1 + alpha);
x = a * xPrev + b * (uNow + uPrev);
end

function x = local_first_order_euler2(xPrev, uPrev, uNow, omega, dt)
% 二阶欧拉/Heun 离散化一阶低通：用 uPrev 预测，再用 uNow 校正。
dxA = omega * (uPrev - xPrev);
xPred = xPrev + dt * dxA;
dxB = omega * (uNow - xPred);
x = xPrev + 0.5 * dt * (dxA + dxB);
end

function value = local_get_candidate_field(candidate, name, defaultValue)
if isfield(candidate, name) && ~isempty(candidate.(name))
    value = candidate.(name);
else
    value = defaultValue;
end
end
