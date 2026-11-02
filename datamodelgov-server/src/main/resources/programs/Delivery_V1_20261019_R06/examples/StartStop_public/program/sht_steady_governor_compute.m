function candidate = sht_steady_governor_compute(state, sample, ref, cfg, dt)
%SHT_STEADY_GOVERNOR_COMPUTE 计算 Np 主调速回路候选量，不更新状态。
% 输出 candidate 是后续保护选择的公共数据包，包含 Nu_main、Ng 变化量、z2 变化量和主回路燃油增量。

lin = cfg.linearModel;
b11 = lin.b11;
b21 = lin.b21;

Np = sample.Np;
Ng = sample.Ng;
T45 = local_get_sample_field(sample, 'T45', NaN);
Mkp = local_get_sample_field(sample, 'Mkp', NaN);
wfcmdDelayPrev = state.WfcmdDelay;

% 使用上一拍滤波状态，保持“本拍计算、下一拍更新”的离散控制器因果关系。
z2Ng = cfg.filterOmega * (Ng - state.NgFilterState) ...
    - b21 * state.WfFilterState;

% 普通参考也含NgDem；它是参考量而不是调速模式开关。
% 只有显式governorMode='Ng'才进入起动暖机调速，缺省保持原Np公式。
mode = 'Np';
if isfield(ref,'governorMode')
    mode = ref.governorMode;
    if isstring(mode) && isscalar(mode), mode = char(mode); end
    if ~ischar(mode) || ~isrow(mode) || ~any(strcmp(mode,{'Np','Ng'}))
        error('sht_steady_governor_compute:InvalidGovernorMode', ...
            'ref.governorMode必须明确为Np或Ng；不提供时使用Np调速。');
    end
end
if strcmp(mode,'Ng')
    fields = {'NgDem','NgErrorGain','NgDotDem'};
    for k = 1:numel(fields)
        name = fields{k};
        if ~isfield(ref,name) || ~isnumeric(ref.(name)) || ...
                ~isreal(ref.(name)) || ~isscalar(ref.(name)) || ~isfinite(ref.(name))
            error('sht_steady_governor_compute:InvalidNgReference', ...
                '显式Ng调速要求ref.%s为有限实数标量；请检查起动暖机参考配置。',name);
        end
    end
    if ref.NgDem <= 0 || ref.NgErrorGain <= 0
        error('sht_steady_governor_compute:InvalidNgReference', ...
            '显式Ng调速要求NgDem和NgErrorGain均大于零，实际为%g、%g。', ...
            ref.NgDem,ref.NgErrorGain);
    end
    nuMain = dt*(ref.NgErrorGain*(ref.NgDem-Ng)+ref.NgDotDem);
else
    % Np主回路输出是Ng指令增量Nu_main，不是燃油流量。
    nuMain = (cfg.npErrorGain * dt * (ref.NpDem - Np) ...
        - cfg.npDeltaGain * (Np - state.NpPrev)) * b21 / b11;
end

dNgMeasured = Ng - state.NgPrev;
dZ2 = z2Ng - state.z2NgPrev;
dWfRaw = local_wf_increment_from_nu(nuMain, dNgMeasured, dZ2, cfg, b21);
[dWfFinal, fuelSatDiag] = sht_fuel_increment_saturator( ...
    dWfRaw, wfcmdDelayPrev, cfg, dt);

wfRawNext = wfcmdDelayPrev + dWfRaw;
wfLimitedNext = fuelSatDiag.Wf_selected_next;

candidate = struct();
candidate.Np = Np;
candidate.Ng = Ng;
candidate.T45 = T45;
candidate.Mkp = Mkp;
candidate.z2Ng = z2Ng;
candidate.uNp = nuMain;
candidate.Nu_main = nuMain;
candidate.Nu_selected = nuMain;
candidate.Nu_upper_bound = inf;
candidate.Nu_lower_bound = -inf;
candidate.Nu_selector_delta = 0;
candidate.incrementBoundsApplied = false;
candidate.incrementUpperActive = false;
candidate.incrementLowerActive = false;
candidate.dNgMeasured = dNgMeasured;
candidate.dZ2 = dZ2;
candidate.dURaw = dWfRaw;
candidate.dUInternal = dWfFinal;
candidate.dWf_raw_increment = dWfRaw;
candidate.dWf_final = dWfFinal;
candidate.dWf_aw_error = fuelSatDiag.dWf_aw_error;
candidate.dWf_upper_bound = fuelSatDiag.dWf_upper_bound;
candidate.dWf_lower_bound = fuelSatDiag.dWf_lower_bound;
candidate.WfcmdDelayPrev = wfcmdDelayPrev;
candidate.Wf_raw_next = wfRawNext;
candidate.Wf_limited_next = wfLimitedNext;
candidate.Wf_main_raw_next = wfRawNext;
candidate.Wf_main_limited_next = wfLimitedNext;
candidate.Wf_selected_next = wfLimitedNext;
candidate.fuelSatDiag = fuelSatDiag;
end

function dWf = local_wf_increment_from_nu(nu, dNgMeasured, dZ2, cfg, b21)
% Nu 到燃油增量的反算式来自原稳态调速器结构。
dWf = (cfg.ngCompGain * (nu - dNgMeasured) - dZ2) / b21;
end

function value = local_get_sample_field(sample, name, defaultValue)
if isstruct(sample) && isfield(sample, name) && ~isempty(sample.(name))
    value = sample.(name);
else
    value = defaultValue;
end
end
