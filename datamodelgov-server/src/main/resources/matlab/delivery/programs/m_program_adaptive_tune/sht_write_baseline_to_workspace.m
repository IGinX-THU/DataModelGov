function names = sht_write_baseline_to_workspace(cfg)
%SHT_WRITE_BASELINE_TO_WORKSPACE 将当前 cfg 的关键运行量写入 MATLAB base workspace。
% 历史说明：
%   该函数名保留自早期 baseline/cfg 双参数阶段。当前版本仿真只使用 cfg，
%   本函数仅作为调试和交互检查入口，不再写入未被 m 程序仿真直接使用的参数。
%   不写入内容包括：Wfb、Power_cmd、原始模型基准采样步长 Ts、A/B/C/D 矩阵、EKF/自适应建模遗留参数、线性化诊断量。

if nargin < 1 || isempty(cfg)
    error('sht:workspace:missingCfg', 'cfg is required.');
end

vars = local_collect_workspace_variables(cfg);
names = fieldnames(vars);
for i = 1:numel(names)
    assignin('base', names{i}, vars.(names{i}));
end
end

function vars = local_collect_workspace_variables(cfg)
engine = cfg.engine;
initial = engine.initial;
ctrl = cfg.controller;
lin = ctrl.linearModel;
dp = ctrl.DPpara;

vars = struct();

% DLL 接口信息。
vars.slib_name = engine.interface.libraryName;
vars.shead_name = engine.interface.headerName;
vars.stype_engstruct_name = engine.interface.engineStructName;
vars.stype_engptr_name = engine.interface.enginePointerName;
vars.engineControlDir = engine.interface.controlDir;
vars.EngineModelMode = engine.modelMode;
vars.EngineModelConfiguration = engine.modelConfiguration;

% 发动机设计点/额定基准和本次仿真状态初值。
vars.Wf0 = dp.Wf0;
vars.power0 = initial.power0;
vars.Np0 = dp.Np0;
vars.Ng0 = dp.Ng0;
vars.A80 = initial.A80;
vars.InitStat = initial.state(:);
vars.T450 = dp.T45;
vars.Mkp0 = dp.Mkp;

% 运行步长只按 m 程序配置输出，不再保留原模型基准采样步长。
vars.Tsim = cfg.Tsim;
vars.Tctrl = cfg.Tctrl;

% 参考指令和保护限值。
vars.NpDem = cfg.reference.baseNp;
vars.NgDem = cfg.reference.baseNg;
vars.NgMax = ctrl.ngProtection.ngMax;
vars.T45Max = ctrl.t45Protection.t45Max;
vars.MkpMax = ctrl.mkpProtection.mkpMax;
vars.WfMax = cfg.actuator.wfMax;
vars.WfMin = cfg.actuator.wfMin;
vars.WfRateLim = cfg.actuator.wfRateLimit;

% 控制律直接使用的线性化系数。
vars.b11 = lin.b11;
vars.b21 = lin.b21;
vars.d31 = lin.d31;
vars.d41 = lin.d41;
vars.omega_u = ctrl.wfFilterOmega;

% 完整配置本体，供 MATLAB 命令行交互检查。
vars.cfg = cfg;
end
