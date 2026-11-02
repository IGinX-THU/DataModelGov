function [ctrl, diagInfo] = sht_apply_controller_gain_schedule(ctrl, sample)
%SHT_APPLY_CONTROLLER_GAIN_SCHEDULE Interpolate b11/b21/d31/d41 by Ngc.
% Extrapolation is handled by clamping the independent variable to the
% schedule endpoints before linear interpolation.

diagInfo = local_empty_diag();
if ~isstruct(ctrl) || ~isfield(ctrl, 'gainSchedule') || isempty(ctrl.gainSchedule)
    return;
end
gs = ctrl.gainSchedule;
if ~isfield(gs, 'enable') || ~gs.enable
    return;
end
if ~local_has_table(gs)
    ctrl = sht_load_controller_gain_schedule(ctrl);
    gs = ctrl.gainSchedule;
end

ngc = local_sample_ngc(sample);
x = gs.Ngc(:);
if isempty(x) || ~isfinite(ngc)
    return;
end

xMin = x(1);
xMax = x(end);
ngcClamped = min(max(ngc, xMin), xMax);
method = local_get_field(gs, 'interpolationMethod', 'linear');

lin = struct();
lin.b11 = interp1(x, gs.b11(:), ngcClamped, method);
lin.b21 = interp1(x, gs.b21(:), ngcClamped, method);
lin.d31 = interp1(x, gs.d31(:), ngcClamped, method);
lin.d41 = interp1(x, gs.d41(:), ngcClamped, method);
ctrl.linearModel = lin;

diagInfo.enabled = true;
diagInfo.Ngc = ngc;
diagInfo.NgcClamped = ngcClamped;
diagInfo.atLowerBound = ngc <= xMin;
diagInfo.atUpperBound = ngc >= xMax;
diagInfo.b11 = lin.b11;
diagInfo.b21 = lin.b21;
diagInfo.d31 = lin.d31;
diagInfo.d41 = lin.d41;
end

function diagInfo = local_empty_diag()
diagInfo = struct();
diagInfo.enabled = false;
diagInfo.Ngc = NaN;
diagInfo.NgcClamped = NaN;
diagInfo.atLowerBound = false;
diagInfo.atUpperBound = false;
diagInfo.b11 = NaN;
diagInfo.b21 = NaN;
diagInfo.d31 = NaN;
diagInfo.d41 = NaN;
end

function tf = local_has_table(gs)
tf = isfield(gs, 'Ngc') && ~isempty(gs.Ngc) ...
    && isfield(gs, 'b11') && ~isempty(gs.b11) ...
    && isfield(gs, 'b21') && ~isempty(gs.b21) ...
    && isfield(gs, 'd31') && ~isempty(gs.d31) ...
    && isfield(gs, 'd41') && ~isempty(gs.d41);
end

function ngc = local_sample_ngc(sample)
if isstruct(sample) && isfield(sample, 'Ngc') && ~isempty(sample.Ngc) ...
        && isfinite(sample.Ngc)
    ngc = sample.Ngc;
else
    ngc = NaN;
end
end

function value = local_get_field(s, name, defaultValue)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end
