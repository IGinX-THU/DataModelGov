function [ctrl, diagInfo] = sht_apply_controller_ndot_schedule(ctrl, sample, dt)
%SHT_APPLY_CONTROLLER_NDOT_SCHEDULE Interpolate Ngdot schedule by Ngc.
%
% 阅读说明：
%   加减速计划表给出的是连续意义下的 NgdotMax/NgdotMin，单位可理解为 rpm/s。
%   完整控制器的高低选变量 Nu 是“本控制采样周期内允许的 Ng 指令增量”，
%   因此这里按当前控制周期 dt 换算：
%       Nu_accel_max = NgdotMax(Ngc) * dt
%       Nu_decel_min = NgdotMin(Ngc) * dt
%   外插策略采用端点钳位，避免低于/高于设计表范围时产生无依据的线性外推。

diagInfo = local_empty_diag();
if ~isstruct(ctrl) || ~isfield(ctrl, 'ndotSchedule') || isempty(ctrl.ndotSchedule)
    return;
end
ns = ctrl.ndotSchedule;
if ~isfield(ns, 'enable') || ~ns.enable
    return;
end
if ~local_has_table(ns)
    ctrl = sht_load_controller_ndot_schedule(ctrl);
    ns = ctrl.ndotSchedule;
end

ngc = local_sample_ngc(sample);
x = ns.Ngc(:);
if isempty(x) || ~isfinite(ngc) || dt <= 0
    return;
end

xMin = x(1);
xMax = x(end);
ngcClamped = min(max(ngc, xMin), xMax);
method = local_get_field(ns, 'interpolationMethod', 'linear');

ngdotMax = interp1(x, ns.NgdotMax(:), ngcClamped, method);
ngdotMin = interp1(x, ns.NgdotMin(:), ngcClamped, method);
accelWfLimit = interp1(x, ns.AccelWfLimit(:), ngcClamped, method);
decelWfLimit = interp1(x, ns.DecelWfLimit(:), ngcClamped, method);

diagInfo.enabled = true;
diagInfo.Ngc = ngc;
diagInfo.NgcClamped = ngcClamped;
diagInfo.atLowerBound = ngc <= xMin;
diagInfo.atUpperBound = ngc >= xMax;
diagInfo.NgdotMax = ngdotMax;
diagInfo.NgdotMin = ngdotMin;
diagInfo.Nu_accel_max = ngdotMax * dt;
diagInfo.Nu_decel_min = ngdotMin * dt;
diagInfo.AccelWfLimit = accelWfLimit;
diagInfo.DecelWfLimit = decelWfLimit;
end

function diagInfo = local_empty_diag()
diagInfo = struct();
diagInfo.enabled = false;
diagInfo.Ngc = NaN;
diagInfo.NgcClamped = NaN;
diagInfo.atLowerBound = false;
diagInfo.atUpperBound = false;
diagInfo.NgdotMax = NaN;
diagInfo.NgdotMin = NaN;
diagInfo.Nu_accel_max = inf;
diagInfo.Nu_decel_min = -inf;
diagInfo.AccelWfLimit = NaN;
diagInfo.DecelWfLimit = NaN;
end

function tf = local_has_table(ns)
tf = isfield(ns, 'Ngc') && ~isempty(ns.Ngc) ...
    && isfield(ns, 'NgdotMax') && ~isempty(ns.NgdotMax) ...
    && isfield(ns, 'NgdotMin') && ~isempty(ns.NgdotMin) ...
    && isfield(ns, 'AccelWfLimit') && ~isempty(ns.AccelWfLimit) ...
    && isfield(ns, 'DecelWfLimit') && ~isempty(ns.DecelWfLimit);
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
