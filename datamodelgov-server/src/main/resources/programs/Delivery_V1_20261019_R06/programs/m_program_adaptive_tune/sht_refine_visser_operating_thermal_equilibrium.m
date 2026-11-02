function [temperatureState, report] = ...
        sht_refine_visser_operating_thermal_equilibrium(cfg, trim, userOptions)
%SHT_REFINE_VISSER_OPERATING_THERMAL_EQUILIBRIUM 求任意运行点的Visser热平衡。
%
% 该入口接收同一健康参数和边界下已经配平的Np、Ng、Wf，固定三者并求解
% 27个金属温度状态。它只负责热状态平衡，不把轴导数误当作被消除量；
% 轴导数仍完整写入report，供调用者判断气路配平是否与热模型一致。

if nargin<2 || nargin>3 || ~isstruct(cfg) || ~isstruct(trim)
    error('SHT:VisserEquilibrium:Input', ...
        '必须提供Visser运行配置和稳态配平结果。');
end
requiredTrim={'Np','Ng','Wf'};
for i=1:numel(requiredTrim)
    name=requiredTrim{i};
    if ~isfield(trim,name) || ~isscalar(trim.(name)) || ~isfinite(trim.(name))
        error('SHT:VisserEquilibrium:Trim', ...
            '配平结果缺少有限字段%s。',name);
    end
end
if ~isfield(cfg,'engine') || ~isfield(cfg.engine,'modelMode') || ...
        cfg.engine.modelMode~=1 || ...
        ~isfield(cfg.engine,'transientEffects') || ...
        ~isfield(cfg.engine.transientEffects,'thermalModelMode') || ...
        cfg.engine.transientEffects.thermalModelMode~=3
    error('SHT:VisserEquilibrium:Topology', ...
        '本函数只支持六部件Visser thermalModelMode=3。');
end
if ~isfield(cfg.engine.initial,'state') || numel(cfg.engine.initial.state)~=29
    error('SHT:VisserEquilibrium:InitialState', ...
        'cfg.engine.initial.state必须为29维。');
end

state=cfg.engine.initial.state(:);
state(1:2)=[trim.Np;trim.Ng];
boundary=cfg.engine.boundary;
engine=sht_engine_open(cfg.engine);
cleanupEngine=onCleanup(@()sht_engine_close(engine)); %#ok<NASGU>

if nargin < 3 || isempty(userOptions), userOptions = struct(); end
options=struct('label','运行点Visser','maximumIterations',20, ...
    'verbose',true,'finalJacobianAudit',true);
names = fieldnames(userOptions);
for i = 1:numel(names)
    if ~isfield(options,names{i})
        error('SHT:VisserOperatingEquilibrium:UnknownOption', ...
            '未知运行点热平衡配置字段：%s。',names{i});
    end
    options.(names{i}) = userOptions.(names{i});
end
solution=sht_thermal_equilibrium_solve( ...
    engine,state,trim.Wf,boundary,'thermal_only',options);
if ~solution.physicalValid || ~solution.thermalPassed
    error('SHT:VisserEquilibrium:NoConvergence', ...
        ['运行点热平衡未通过工程验收：max|dT/dt|=%.6e K/s，' ...
         '剩余修正通过=%d，停止原因=%s。'], ...
        solution.finalMaximumThermalDerivative_Kps, ...
        solution.remainingCorrectionPassed,solution.stopReason);
end

temperatureState=solution.state(3:29);
report=solution;
report.method='shared_dll_exact_thermal_only_joint_full';
report.derivativeTolerance_Kps= ...
    solution.options.engineeringThermalDerivativeTolerance_Kps;
report.initialMaximumDerivative_Kps= ...
    solution.history.maximumThermalDerivative_Kps(1);
report.finalMaximumDerivative_Kps= ...
    solution.finalMaximumThermalDerivative_Kps;
report.finalShaftDerivative_rpmps=solution.derivative(1:2);
report.passed=solution.physicalValid && solution.thermalPassed;
end
