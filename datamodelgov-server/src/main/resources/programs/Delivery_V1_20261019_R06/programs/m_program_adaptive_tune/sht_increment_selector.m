function [nuSelected, diagInfo] = sht_increment_selector(candidates, cfg)
% 阅读说明：
%   本文件只处理 Nu 域的高低选。
%   Nu_main 来自 Np 主回路；Nu_upper_bound 汇总 Ng/T45/Mkp 等限制保护；Nu_lower_bound 预留给减速或下限保护。
%   注意这里尚未处理燃油流量绝对值和变化率限制，燃油执行机构饱和统一由 sht_fuel_increment_saturator 完成。
%SHT_INCREMENT_SELECTOR Select the Ng-command increment for the controller.
%
% At the current stage, there is no constant Nu saturation. Acceleration and
% deceleration constraints will later enter this selector through scheduled
% Nu_upper_bound / Nu_lower_bound candidates.


% 读取候选值。未给出的上限默认为 +inf，未给出的下限默认为 -inf，表示该类保护暂不约束。
nuMain = local_get_candidate_scalar(candidates, 'Nu_main', ...
    local_get_candidate_scalar(candidates, 'nuMain', 0));
nuUpper = local_get_candidate_scalar(candidates, 'Nu_upper_bound', inf);
nuLower = local_get_candidate_scalar(candidates, 'Nu_lower_bound', -inf);
mode = local_get_mode(cfg);

switch lower(mode)
    case 'stage4p5_incrementauthority'
        % 只按保护上下限裁剪 Nu_main；若上限来自 Ng/T45/Mkp，则对应保护进入候选限制状态。
        nuSelected = min(max(nuMain, nuLower), nuUpper);
        diagMode = 'stage4p5_incrementAuthority';
        modeId = 45;
        boundsApplied = true;
    otherwise
        error('sht:incrementSelector:unsupportedMode', ...
            'Unsupported increment selector mode: %s', mode);
end

tol = 1e-13;
% 记录上下限是否实际触碰，用于判断当前控制模式和保护回路是否被选中。
diagInfo = struct();
diagInfo.mode = diagMode;
diagInfo.modeId = modeId;
diagInfo.controlMode = 'SPEED_GOVERNING';
diagInfo.controlModeId = 1;
diagInfo.Nu_main = nuMain;
diagInfo.Nu_selected = nuSelected;
diagInfo.Nu_upper_bound = nuUpper;
diagInfo.Nu_lower_bound = nuLower;
diagInfo.Nu_selector_delta = nuSelected - nuMain;
diagInfo.incrementBoundsApplied = boundsApplied;
diagInfo.incrementUpperActive = isfinite(nuUpper) && ...
    abs(nuSelected - nuUpper) <= tol;
diagInfo.incrementLowerActive = isfinite(nuLower) && ...
    abs(nuSelected - nuLower) <= tol;
diagInfo.Nu_accel_max = local_get_candidate_scalar(candidates, ...
    'Nu_accel_max', inf);
diagInfo.Nu_decel_min = local_get_candidate_scalar(candidates, ...
    'Nu_decel_min', -inf);
diagInfo.Nu_NgTop_max = local_get_candidate_scalar(candidates, ...
    'Nu_NgTop_max', inf);
diagInfo.Nu_T45_max = local_get_candidate_scalar(candidates, ...
    'Nu_T45_max', inf);
diagInfo.Nu_Mkp_max = local_get_candidate_scalar(candidates, ...
    'Nu_Mkp_max', inf);
diagInfo.Nu_NgBottom_min = local_get_candidate_scalar(candidates, ...
    'Nu_NgBottom_min', -inf);
diagInfo.limitConflict = nuLower > nuUpper;
end

function mode = local_get_mode(cfg)
mode = 'stage4p5_incrementAuthority';
if isfield(cfg, 'fullControl') && isfield(cfg.fullControl, 'mode') ...
        && ~isempty(cfg.fullControl.mode)
    mode = cfg.fullControl.mode;
end
end

function value = local_get_candidate_scalar(candidates, name, defaultValue)
if isfield(candidates, name) && ~isempty(candidates.(name))
    value = candidates.(name);
else
    value = defaultValue;
end
end
