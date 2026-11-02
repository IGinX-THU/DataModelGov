function state = sht_steady_governor_init(cfg)
%SHT_STEADY_GOVERNOR_INIT 初始化离散控制器状态。
% 阅读说明：
%   cfg.controller.initial 保存本次仿真 t=0 控制器状态初值，cfg.controller.linearModel 保存控制律直接使用的线性化系数。
%   这些初值必须与本次仿真初始条件一致，否则第一拍差分项和保护误差会产生非物理冲击。

init = cfg.initial;
lin = cfg.linearModel;

state = struct();

% Np 主调速器记忆量：上一拍 Np/Ng、z2 补偿量和燃油命令寄存器。
state.NpPrev = init.Np;
state.NgPrev = init.Ng;
state.z2NgPrev = -init.Wf * lin.b21;
state.WfcmdDelay = init.Wf;
state.Wfcmd = init.Wf;
state.z3 = init.Wf;
state.WfFilterState = init.Wf;
state.NgFilterState = init.Ng;
state.trWfState = 0;
state.trNgState = 0;
state.dURaw = 0;
state.dU = 0;
state.uNp = 0;
state.z2Ng = state.z2NgPrev;

% 保护回路记忆量。Ng 保护上一拍误差使用 NgMax-Ng0，复现 V5_2 Unit Delay 初值。
state.NgTopCommandErrorPrev = cfg.ngProtection.ngMax - init.Ng;
state.NgTopErrorPrev = state.NgTopCommandErrorPrev;
state.T45Prev = init.T45;
state.T45CommandErrorPrev = 0;
state.MkpPrev = init.Mkp;
state.MkpCommandErrorPrev = 0;
end