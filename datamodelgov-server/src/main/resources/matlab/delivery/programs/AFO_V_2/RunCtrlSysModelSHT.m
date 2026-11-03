%--------------------------------------------------------------------------------------
%   MATLAB 调用 GTESS 涡轴发动机模型 DLL 的基准初始化与线性化脚本。
%   主要用途：测试 DLL 接口，计算设计点输出、初始状态和局部线性化系数。
%   本脚本保留原始 RunCtrlSysModelSHT 计算流程，用于兼容 Simulink 初始化。
%   注意：当前 DLL 接口采用 stepIn[512] 和 stepOut[128]。
%--------------------------------------------------------------------------------------

%% 初始化模型
clc;    clear all;      close all;

script_dir = fileparts(mfilename('fullpath'));
slib_name = 'GTESS';
slib_file = fullfile(script_dir, 'GTESS.dll');
shead_name = fullfile(script_dir, 'GTESS.h');
stype_engstruct_name = 'EngineTurboshaft';        stype_engptr_name = 'EngineSHTPointer';        sfunc_condinit_name = 'DLL_SHT_ConditionsInit';
sfunc_initial_name = 'DLL_SHT_Initial';      sfunc_onepoint_name = 'DLL_SHT_RunOnePoint';     sfunc_onestep_name = 'DLL_SHT_RunOneStep';       sfunc_free_name = 'DLL_SHT_Free';
sfunc_trncomp_name = 'DLL_SHT_RunTransientComponents';       sfunc_varinit_name = 'DLL_SHT_varIteInit';      sfunc_stcomp_name = 'DLL_SHT_RunSteadyComponents';

if libisloaded(slib_name)
    try
        calllib(slib_name, sfunc_free_name);
    catch
        % 库可能尚未完成初始化；此处只需保证随后加载的是本目录 DLL。
    end
    unloadlibrary(slib_name);
end
[m1, m2] = loadlibrary(slib_file, shead_name, 'alias', slib_name);
libfunctions(slib_name,'-full');            [~] = calllib(slib_name, sfunc_initial_name);
eng_ptr_init.eng = libstruct(stype_engstruct_name);         eng_ptr = libstruct(stype_engptr_name, eng_ptr_init);
stepin = zeros(512, 1);          step_in = libpointer('doublePtr', stepin);
stepout = zeros(128, 1);         step_out = libpointer('doublePtr', stepout);

%% 测试
step_in.Value(11:13) = [0  0  0]';
[~, stepin, stepout, engout] = calllib(slib_name, sfunc_condinit_name, step_in, step_out, eng_ptr);

Wf0 = 0.151914044493225;        power0 = 2176600;       Np0 = 20800;     Ng0 = 38000;     A80 = 0.10573;
Mkp0 = power0/(Np0*pi/30);      Mkg0 = 0;

% 外部二次空气系统模式开关。参考模型自身不包含完整空气系统，
% 默认保持内部引气模式；接入真实外部空气系统后显式置为 1。
ExternalSecondaryAirEnabled = 0;

% SLX 旋翼负载边界的集中配置。默认 legacyPower 用于继承现有功率指令；
% 可切换为 directTorque 或 collectivePitch，不改变控制器增益。
RotorLoadInputMode = 'legacyPower';
RotorLoadCfg = struct( ...
    'designNpRpm', Np0, ...
    'designPowerW', power0, ...
    'thetaZeroDeg', 0, ...
    'thetaDesignDeg', 12, ...
    'profileTorqueFraction', 0.15, ...
    'thetaValidRangeDeg', [6, 14]);
MkpDirectCommand = Mkp0;
ThetaCommandDeg = RotorLoadCfg.thetaDesignDeg;

step_in.Value = zeros(512, 1);
step_in.Value(1:10) = [Np0    Ng0    Wf0   A80     0  power0  0   0  0  0];
[~, stepin, stepout, engout] = calllib(slib_name, sfunc_onepoint_name, step_in, step_out, eng_ptr);
errs = abs([engout.eng.errOut   engout.eng.Nozzle.y(end)]);       errmax = max(errs);
if (engout.eng.convergeTag ~= 0) || errmax>1e-6
        str = sprintf('not converged, err = %f',  errmax);           disp(str);
end
[   2  engout.eng.HPC.u(1)  engout.eng.HPC.u(3)  engout.eng.HPC.u(4)  engout.eng.HPC.u(2);
    3  engout.eng.HPC.y(1)  engout.eng.HPC.y(3)  engout.eng.HPC.y(4)  engout.eng.HPC.y(23+1);
    4  engout.eng.Burner.y(1)  engout.eng.Burner.y(3)  engout.eng.Burner.y(4)  0;
    44  engout.eng.HPT.y(1)  engout.eng.HPT.y(3)  engout.eng.HPT.y(4)  engout.eng.HPT.y(18+1);
    5  engout.eng.LPT.y(1)  engout.eng.LPT.y(3)  engout.eng.LPT.y(4)  engout.eng.LPT.y(18+1);
    8  engout.eng.Nozzle.y(1)  engout.eng.Nozzle.y(2)  engout.eng.Nozzle.y(9)  engout.eng.Nozzle.y(11);
    ]

InitOut = zeros(20,1);

	InitOut(1) = engout.eng.Ambient.gasPathOut(4);		InitOut(2) = engout.eng.Ambient.gasPathOut(3);	
	InitOut(3) = engout.eng.HPC.y(4);	InitOut(4) = engout.eng.HPC.y(3);
	InitOut(5) = engout.eng.HPT.y(4);	InitOut(6) = engout.eng.HPT.y(3);
	InitOut(7) = engout.eng.LPT.y(4);	InitOut(8) = engout.eng.LPT.y(3);
	InitOut(9) = engout.eng.LPS_Nmech;	InitOut(10) = engout.eng.HPS_Nmech;
	InitOut(11) = engout.eng.HPC.y(8);	InitOut(12) = engout.eng.LPS_Trq;	InitOut(13) = engout.eng.HPC.u(6);
	InitOut(14) = engout.eng.HPT.y(16);	InitOut(15) = engout.eng.LPT.y(16);	
    errs = abs([engout.eng.errOut   engout.eng.Nozzle.y(end)]);       errmax = max(errs);   	InitOut(16) = errmax;
    InitOut(17) = engout.eng.Burner.y(4);       InitOut(18) = engout.eng.Burner.y(3);       
    
InitAir = zeros(50,1);
    InitAir(1:5) = engout.eng.HPC.fractionalBleeds(1:5);
    InitAir(6:10) = (engout.eng.HPC.fractionalBleeds(6:10)+engout.eng.HPC.fractionalBleeds(16:20))/2;       InitAir(6) = InitAir(6)*2;
    InitAir(11:15) = (engout.eng.HPC.fractionalBleeds(11:15)+engout.eng.HPC.fractionalBleeds(21:25))/2;       InitAir(11) = InitAir(11)*2;
    InitAir(16:20) = engout.eng.HPC.fractionalBleeds(26:30);
    InitAir(21:25) = engout.eng.HPC.fractionalBleeds(31:35);
    InitAir(26:30) = (engout.eng.HPC.fractionalBleeds(36:40)+engout.eng.HPC.fractionalBleeds(46:50))/2;       InitAir(26) = InitAir(26)*2;
    InitAir(31:35) = (engout.eng.HPC.fractionalBleeds(41:45)+engout.eng.HPC.fractionalBleeds(51:55))/2;       InitAir(31) = InitAir(31)*2;
    InitAir(36:40) = engout.eng.HPC.fractionalBleeds(56:60);
    InitAir(41:45) = engout.eng.HPC.fractionalBleeds(61:65);
    InitAir(46:50) = engout.eng.HPC.fractionalBleeds(66:70);
    

        T450 = engout.eng.HPT.y(3);
        
    InitStat = zeros(2,1);      InitStat(1) = engout.eng.LPS_Nmech;          InitStat(2) = engout.eng.HPS_Nmech;     

%%
dlt  = 1e-4;        norm = [Np0  Ng0  Wf0  power0]';       x0 = [Np0  Ng0];        u0 = Wf0;
A= zeros(2,2);      B = zeros(2,2);     C = [eye(2); zeros(2,2)];     D = zeros(4,2);

step_in.Value = zeros(512, 1);      step_in.Value(1:10) = [x0(1)    x0(2)    u0   A80     0  power0  0   0  0  0];
[~, stepin, stepout, engout] = calllib(slib_name, sfunc_onestep_name, step_in, step_out, eng_ptr);
errs = abs([engout.eng.errOut   engout.eng.Nozzle.y(end)]);       errmax = max(errs);
if (engout.eng.convergeTag ~= 0) || errmax>1e-6;        str = sprintf('not converged, err = %f',  errmax);           disp(str);     end
xd0 = stepout(1:2);

x1 = x0;        x1(1) = x0(1) - dlt*norm(1);        u1 = u0;        power1 = power0;
step_in.Value = zeros(512, 1);      step_in.Value(1:10) = [x1(1)    x1(2)    u1   A80     0  power1  0   0  0  0];
[~, stepin, stepout, engout] = calllib(slib_name, sfunc_onestep_name, step_in, step_out, eng_ptr);
errs = abs([engout.eng.errOut   engout.eng.Nozzle.y(end)]);       errmax = max(errs);
if (engout.eng.convergeTag ~= 0) || errmax>1e-6;        str = sprintf('not converged, err = %f',  errmax);           disp(str);     end
xd1 = stepout(1:2);         T451 = engout.eng.HPT.y(3);         PTDriveTorque1 = engout.eng.LPS_Trq;
x2 = x0;        x2(1) = x0(1) + dlt*norm(1);        u2 = u0;        power2 = power0;
step_in.Value = zeros(512, 1);      step_in.Value(1:10) = [x2(1)    x2(2)    u2   A80     0  power2  0   0  0  0];
[~, stepin, stepout, engout] = calllib(slib_name, sfunc_onestep_name, step_in, step_out, eng_ptr);
errs = abs([engout.eng.errOut   engout.eng.Nozzle.y(end)]);       errmax = max(errs);
if (engout.eng.convergeTag ~= 0) || errmax>1e-6;        str = sprintf('not converged, err = %f',  errmax);           disp(str);     end
xd2 = stepout(1:2);         T452 = engout.eng.HPT.y(3);         PTDriveTorque2 = engout.eng.LPS_Trq;
A(:,1) = (xd2 - xd1)/(2*dlt*norm(1));       C(3:4,1) = [(T452-T451)/(2*dlt*norm(1));  (PTDriveTorque2-PTDriveTorque1)/(2*dlt*norm(1))];

x1 = x0;        x1(2) = x0(2) - dlt*norm(2);        u1 = u0;       power1 = power0;
step_in.Value = zeros(512, 1);      step_in.Value(1:10) = [x1(1)    x1(2)    u1   A80     0  power1  0   0  0  0];
[~, stepin, stepout, engout] = calllib(slib_name, sfunc_onestep_name, step_in, step_out, eng_ptr);
errs = abs([engout.eng.errOut   engout.eng.Nozzle.y(end)]);       errmax = max(errs);
if (engout.eng.convergeTag ~= 0) || errmax>1e-6;        str = sprintf('not converged, err = %f',  errmax);           disp(str);     end
xd1 = stepout(1:2);        T451 = engout.eng.HPT.y(3);         PTDriveTorque1 = engout.eng.LPS_Trq;
x2 = x0;        x2(2) = x0(2) + dlt*norm(2);        u2 = u0;        power2 = power0;
step_in.Value = zeros(512, 1);      step_in.Value(1:10) = [x2(1)    x2(2)    u2   A80     0  power2  0   0  0  0];
[~, stepin, stepout, engout] = calllib(slib_name, sfunc_onestep_name, step_in, step_out, eng_ptr);
errs = abs([engout.eng.errOut   engout.eng.Nozzle.y(end)]);       errmax = max(errs);
if (engout.eng.convergeTag ~= 0) || errmax>1e-6;        str = sprintf('not converged, err = %f',  errmax);           disp(str);     end
xd2 = stepout(1:2);        T452 = engout.eng.HPT.y(3);         PTDriveTorque2 = engout.eng.LPS_Trq;
A(:,2) = (xd2 - xd1)/(2*dlt*norm(2));       C(3:4,2) = [(T452-T451)/(2*dlt*norm(2));  (PTDriveTorque2-PTDriveTorque1)/(2*dlt*norm(2))];

x1 = x0;                u1 = u0 - dlt*norm(3);        power1 = power0;
step_in.Value = zeros(512, 1);      step_in.Value(1:10) = [x1(1)    x1(2)    u1   A80     0  power1  0   0  0  0];
[~, stepin, stepout, engout] = calllib(slib_name, sfunc_onestep_name, step_in, step_out, eng_ptr);
errs = abs([engout.eng.errOut   engout.eng.Nozzle.y(end)]);       errmax = max(errs);
if (engout.eng.convergeTag ~= 0) || errmax>1e-6;        str = sprintf('not converged, err = %f',  errmax);           disp(str);     end
xd1 = stepout(1:2);        T451 = engout.eng.HPT.y(3);         PTDriveTorque1 = engout.eng.LPS_Trq;
x2 = x0;            u2 = u0 + dlt*norm(3);        power2 = power0;
step_in.Value = zeros(512, 1);      step_in.Value(1:10) = [x2(1)    x2(2)    u2   A80     0  power2  0   0  0  0];
[~, stepin, stepout, engout] = calllib(slib_name, sfunc_onestep_name, step_in, step_out, eng_ptr);
errs = abs([engout.eng.errOut   engout.eng.Nozzle.y(end)]);       errmax = max(errs);
if (engout.eng.convergeTag ~= 0) || errmax>1e-6;        str = sprintf('not converged, err = %f',  errmax);           disp(str);     end
xd2 = stepout(1:2);        T452 = engout.eng.HPT.y(3);         PTDriveTorque2 = engout.eng.LPS_Trq;
B(:,1) = (xd2 - xd1)/(2*dlt*norm(3));       D(3:4, 1) = [(T452-T451)/(2*dlt*norm(3));  (PTDriveTorque2-PTDriveTorque1)/(2*dlt*norm(3))];

x1 = x0;                u1 = u0;        power1 = power0 - dlt*norm(4);
step_in.Value = zeros(512, 1);      step_in.Value(1:10) = [x1(1)    x1(2)    u1   A80     0  power1  0   0  0  0];
[~, stepin, stepout, engout] = calllib(slib_name, sfunc_onestep_name, step_in, step_out, eng_ptr);
errs = abs([engout.eng.errOut   engout.eng.Nozzle.y(end)]);       errmax = max(errs);
if (engout.eng.convergeTag ~= 0) || errmax>1e-6;        str = sprintf('not converged, err = %f',  errmax);           disp(str);     end
xd1 = stepout(1:2);        T451 = engout.eng.HPT.y(3);         PTDriveTorque1 = engout.eng.LPS_Trq;
x2 = x0;            u2 = u0;        power2 = power0 + dlt*norm(4);
step_in.Value = zeros(512, 1);      step_in.Value(1:10) = [x2(1)    x2(2)    u2   A80     0  power2  0   0  0  0];
[~, stepin, stepout, engout] = calllib(slib_name, sfunc_onestep_name, step_in, step_out, eng_ptr);
errs = abs([engout.eng.errOut   engout.eng.Nozzle.y(end)]);       errmax = max(errs);
if (engout.eng.convergeTag ~= 0) || errmax>1e-6;        str = sprintf('not converged, err = %f',  errmax);           disp(str);     end
xd2 = stepout(1:2);        T452 = engout.eng.HPT.y(3);         PTDriveTorque2 = engout.eng.LPS_Trq;
B(:,2) = (xd2 - xd1)/(2*dlt*norm(4));       D(3:4, 2) = [(T452-T451)/(2*dlt*norm(4));  (PTDriveTorque2-PTDriveTorque1)/(2*dlt*norm(4))];

%% 

Ts = 0.025;

Kp1 = 4;      Ki1 = 4;          Kp2 = 1e-5;       Ki2 = 2e-5;
Power_cmd = power0;     NpCmd = -2000;
k1 = 2;  k2 = 10;  k3 = 16;  k4  =5;
sys = tf([k1*k3], [1 k1*k4 k1*k3]);


NpDem = Np0;      NgDem = Ng0;
NgMax = Ng0*1.05;
MkpMax = 1200;
T45Max = 1400;
WfMax = Wf0*2;
WfMin = Wf0*0.01;
WfRateLim = 1.5;


    % d41 表示燃油到 DLL 内部 PT 可用驱动扭矩的局部增益，不是外部
    % 负载扭矩 Mkp 对燃油的直接导数。
    a11 = A(1,1);     a12 = A(1,2);      a21 = A(2,1);     a22 = A(2,2);         b11 = B(1,1)*1;       b21 = B(2,1)*1;       d31 = D(3,1);      d41 = D(4,1);
    CA = C*A;       ca32 = CA(3,2);     ca42 = CA(4,2);     CB = C*B;   cb31 = CB(3,1);     cb41 = CB(4,1);
    omega_u = 20;
    Pmat0 = eye(11);            Pmat1 = eye(10);
    Qmat = diag([1e-1  1e-1  1e-10   1e-1  1e-1   1e-5  1e-5  1e-5  1e-5  1e-5  1e-5  ]);
    Qmat1 = diag([1e1  1e1  1e-1  1e-1   1e-5  1e-5  1e-5  1e-5  1e-10  1e-10  ]);
    Rmat = diag([1e4  1e4]);
%     xbar_hat0 = [Np0  Ng0  Wf0  0  0   a11  a12  a21  a22  b11/1e5  b21/1e5]';
    xbar_hat1 = [Np0  Ng0  0  0   a11  a12  a21  a22  b11/1e5  b21/1e5]';

omega_f = 4;       zeta_f = 1;
theta0 = [a11  a12  b11/1e5  -0.001/1e-2]';           P0 = eye(4);

%%
for i = 1:0
b=7.3e4;      bhat = b;         Ga = 1;     Gam = 1;
filter1 = 1;    filter2 = 1;        Kp = 4;     K3 = 10;
s0 = tf([1 0], [1]);
sys(1) = (b/bhat*Kp*Ga*s0 + b/bhat*Kp*K3*Ga*filter1)/(s0*s0 + b/bhat*(Kp+K3*filter2)*Ga*s0 + b/bhat*Kp*K3*Ga*filter1);
zpk(sys(1))
bandwidth(sys(1))
[natural_freq, damping_ratio, poles] = damp(sys(1));        [natural_freq  damping_ratio]
poles
Gol = (Kp+Kp*K3*filter1/s0+K3*filter2)/s0*Ga*b/bhat;        [Gm, Pm, Wcg, Wcp] = margin(Gol);   info = allmargin(Gol);               [20*log10(Gm)  Pm  info.DelayMargin]

b=7.3e4;      bhat = b;         Ga=tf([25], [1 25]);        Gam = 1;
filter1 = 1;    filter2 = 1;        Kp = 4;     K3 = 10;
s0 = tf([1 0], [1]);
sys(2) = (b/bhat*Kp*Ga*s0 + b/bhat*Kp*K3*Ga*filter1)/(s0*s0 + b/bhat*(Kp+K3*filter2)*Ga*s0 + b/bhat*Kp*K3*Ga*filter1);
zpk(sys(2))
bandwidth(sys(2))
[natural_freq, damping_ratio, poles] = damp(sys(2));        [natural_freq  damping_ratio]
poles
Gol = (Kp+Kp*K3*filter1/s0+K3*filter2)/s0*Ga*b/bhat;        [Gm, Pm, Wcg, Wcp] = margin(Gol);   info = allmargin(Gol);               [20*log10(Gm)  Pm  info.DelayMargin]

b=7.3e4;      bhat = 1*b;       alf1 = 30;      bet1 = 10;
Ga=tf([25], [1 25]);        Gam = tf([alf1], [1 alf1]);     Kp = 4;     K3 = bet1*alf1/(bet1+alf1);
filter1 = tf([alf1*bet1], [K3 K3*(bet1+alf1)]);    filter2 = tf([bet1 bet1*alf1], [K3 K3*(bet1+alf1)]);
s0 = tf([1 0], [1]);
sys(3) = (b/bhat*Kp*Ga*s0 + b/bhat*Kp*K3*Ga*filter1)/(s0*s0 + b/bhat*(Kp+K3*filter2)*Ga*s0 + b/bhat*Kp*K3*Ga*filter1);
zpk(sys(3))
bandwidth(sys(3))
[natural_freq, damping_ratio, poles] = damp(sys(3));        [natural_freq  damping_ratio]
poles
Gol = (Kp+Kp*K3*filter1/s0+K3*filter2)/s0*Ga*b/bhat;        [Gm, Pm, Wcg, Wcp] = margin(Gol);   info = allmargin(Gol);               [20*log10(Gm)  Pm  info.DelayMargin]

b=7.3e4;      bhat = 1*b;       alf1 = 20;      bet1 = 10;
Ga=tf([25], [1 25]);        Gam = tf([alf1], [1 alf1]);     Kp = 4;     K3 = bet1*alf1/(bet1+alf1);
filter1 = tf([alf1*bet1], [K3 K3*(bet1+alf1)]);    filter2 = tf([bet1 bet1*alf1], [K3 K3*(bet1+alf1)]);
s0 = tf([1 0], [1]);
sys(4) = (b/bhat*Kp*Ga*s0 + b/bhat*Kp*K3*Ga*filter1)/(s0*s0 + b/bhat*(Kp+K3*filter2)*Ga*s0 + b/bhat*Kp*K3*Ga*filter1);
zpk(sys(4))
bandwidth(sys(4))
[natural_freq, damping_ratio, poles] = damp(sys(4));        [natural_freq  damping_ratio]
poles
Gol = (Kp+Kp*K3*filter1/s0+K3*filter2)/s0*Ga*b/bhat;        [Gm, Pm, Wcg, Wcp] = margin(Gol);   info = allmargin(Gol);               [20*log10(Gm)  Pm  info.DelayMargin]

b=7.3e4;      bhat = 2*b;       alf1 = 20;      bet1 = 10;
Ga=tf([25], [1 25]);        Gam = tf([alf1], [1 alf1]);     Kp = 4;     K3 = bet1*alf1/(bet1+alf1);
filter1 = tf([alf1*bet1], [K3 K3*(bet1+alf1)]);    filter2 = tf([bet1 bet1*alf1], [K3 K3*(bet1+alf1)]);
s0 = tf([1 0], [1]);
sys(5) = (b/bhat*Kp*Ga*s0 + b/bhat*Kp*K3*Ga*filter1)/(s0*s0 + b/bhat*(Kp+K3*filter2)*Ga*s0 + b/bhat*Kp*K3*Ga*filter1);
zpk(sys(5))
bandwidth(sys(5))
[natural_freq, damping_ratio, poles] = damp(sys(5));        [natural_freq  damping_ratio]
poles
Gol = (Kp+Kp*K3*filter1/s0+K3*filter2)/s0*Ga*b/bhat;        [Gm, Pm, Wcg, Wcp] = margin(Gol);   info = allmargin(Gol);               [20*log10(Gm)  Pm  info.DelayMargin]

b=7.3e4;      bhat = .5*b;       alf1 = 20;      bet1 = 10;
Ga=tf([25], [1 25]);        Gam = tf([alf1], [1 alf1]);     Kp = 4;     K3 = bet1*alf1/(bet1+alf1);
filter1 = tf([alf1*bet1], [K3 K3*(bet1+alf1)]);    filter2 = tf([bet1 bet1*alf1], [K3 K3*(bet1+alf1)]);
s0 = tf([1 0], [1]);
sys(6) = (b/bhat*Kp*Ga*s0 + b/bhat*Kp*K3*Ga*filter1)/(s0*s0 + b/bhat*(Kp+K3*filter2)*Ga*s0 + b/bhat*Kp*K3*Ga*filter1);
zpk(sys(6))
bandwidth(sys(6))
[natural_freq, damping_ratio, poles] = damp(sys(6));        [natural_freq  damping_ratio]
poles
Gol = (Kp+Kp*K3*filter1/s0+K3*filter2)/s0*Ga*b/bhat;        [Gm, Pm, Wcg, Wcp] = margin(Gol);   info = allmargin(Gol);               [20*log10(Gm)  Pm  info.DelayMargin]

b=7.3e4;      bhat = .5*b;       alf1 = 20;      bet1 = 20;
Ga=tf([25], [1 25]);        Gam = tf([alf1], [1 alf1]);     Kp = 4;     K3 = bet1*alf1/(bet1+alf1);
filter1 = tf([alf1*bet1], [K3 K3*(bet1+alf1)]);    filter2 = tf([bet1 bet1*alf1], [K3 K3*(bet1+alf1)]);
s0 = tf([1 0], [1]);
sys(7) = (b/bhat*Kp*Ga*s0 + b/bhat*Kp*K3*Ga*filter1)/(s0*s0 + b/bhat*(Kp+K3*filter2)*Ga*s0 + b/bhat*Kp*K3*Ga*filter1);
zpk(sys(7))
bandwidth(sys(7))
[natural_freq, damping_ratio, poles] = damp(sys(7));        [natural_freq  damping_ratio]
poles
Gol = (Kp+Kp*K3*filter1/s0+K3*filter2)/s0*Ga*b/bhat;        [Gm, Pm, Wcg, Wcp] = margin(Gol);   info = allmargin(Gol);               [20*log10(Gm)  Pm  info.DelayMargin]


figure(1);     
for i = 1:7
    subplot(2,4,i);     step(sys(i));       title(i);       xlim([0 2]);        ylim([0 1.2]);
end
end

%%
close all;

for i = 1:0
    
figure(0901);
plot(NpDemDt_200.Time, NpDemDt_200.Data/Np0*100, '--r', NpLADRC_200.Time, NpLADRC_200.Data/Np0*100, ':g', NpAMLADRC_200.Time, NpAMLADRC_200.Data/Np0*100, 'b-.',  NpAPCHGPI_200.Time, NpAPCHGPI_200.Data/Np0*100, 'k', 'LineWidth', 1.5);
ylim([98.9, 100.1]);
legend('Np Ref', 'LADRC', 'ARSC-LADRC', 'CHGPI');     title('Np (%)');       ylabel('%');        xlabel('Time (s)');
figure(0902);
plot(WfLADRC_200.Time, WfLADRC_200.Data/Wf0*100, ':g', WfAMLADRC_200.Time, WfAMLADRC_200.Data/Wf0*100, 'b-.',  WfAPCHGPI_200.Time, WfAPCHGPI_200.Data/Wf0*100, 'k', 'LineWidth', 1.5);
% ylim([0.12, 0.18]);
legend('LADRC', 'ARSC-LADRC', 'CHGPI');     title('Wf (%)');       ylabel('%');        xlabel('Time (s)');

figure(1001);
plot(NpDemDt_2000.Time, NpDemDt_2000.Data/Np0*100, '--r', NpAMLADRC_2000.Time, NpAMLADRC_2000.Data/Np0*100, 'b-.',  NpAPCHGPI_2000.Time, NpAPCHGPI_2000.Data/Np0*100, 'k', 'LineWidth', 1.5);
% ylim([1.63e4, 2.15e4]);
legend('Np Ref',  'ARSC-LADRC', 'CHGPI');     title('Np (%)');       ylabel('%');        xlabel('Time (s)');
figure(1002);
plot(WfAMLADRC_2000.Time, WfAMLADRC_2000.Data/Wf0*100, 'b-.',  WfAPCHGPI_2000.Time, WfAPCHGPI_2000.Data/Wf0*100, 'k', 'LineWidth', 1.5);
% ylim([0.0, 0.3]);
legend( 'ARSC-LADRC', 'CHGPI');     title('Wf (%)');       ylabel('%');        xlabel('Time (s)');

figure(1101);
plot(NpDemDt_4000woc.Time, NpDemDt_4000woc.Data/Np0*100, '--r', NpAPCHGPI_4000woc.Time, NpAPCHGPI_4000woc.Data/Np0*100, 'b', NpAPCHGPI_4000.Time, NpAPCHGPI_4000.Data/Np0*100, 'k', 'LineWidth', 1.5);    xlim([1,6]);
ylim([74, 101]);
legend('$$Np Ref$$',  '$$CHGPI\ w.o.\ y_{dotc,lim}$$', '$$CHGPI$$', 'Interpreter', 'latex');
title('$$Np (\%)$$', 'Interpreter', 'latex');       ylabel('$$\%$$', 'Interpreter', 'latex');        xlabel('Time (s)');
figure(1102);
plot(WfAPCHGPI_4000woc.Time, WfAPCHGPI_4000woc.Data/Wf0*100, 'b', WfAPCHGPI_4000.Time, WfAPCHGPI_4000.Data/Wf0*100, 'k', 'LineWidth', 1.5);       xlim([1,6]);
ylim([40, 180]);        xlim([1,6]);
legend( '$$CHGPI\ w.o.\ y_{dotc,lim}$$', '$$CHGPI$$', 'Interpreter', 'latex'); 
title('$$Wf (\%)$$', 'Interpreter', 'latex');       ylabel('$$\%$$', 'Interpreter', 'latex');        xlabel('Time (s)');
figure(1103);
plot(NpDotc_4000woc.Time, NpDotc_4000woc.Data/Np0*100, 'b-.',  NpDot_4000woc.Time, NpDot_4000woc.Data/Np0*100, 'b', NpDotc_4000.Time, NpDotc_4000.Data/Np0*100, 'k-.',  NpDot_4000.Time, NpDot_4000.Data/Np0*100, 'k', 'LineWidth', 1.5);
ylim([-60, 30]);               xlim([1,6]);
legend( '$$N_{pdotc}-CHGPI\ w.o.\ y_{dotc,lim}$$', '$$\dot{N}_{p}-CHGPI\ w.o.\ y_{dotc,lim}$$', '$$N_{pdotc}-CHGPI$$', '$$\dot{N}_{p}-CHGPI$$', 'Interpreter', 'latex');
title('$$N_{pdotc}$$ vs. $$\dot{N}_{p}$$ (\%/s)', 'Interpreter', 'latex');
ylabel('$$\%/s$$', 'Interpreter', 'latex');        xlabel('Time (s)');
figure(1104);
plot(dU_Schd_4000woc.Time, dU_Schd_4000woc.Data/Wf0*100, 'b-.',  dU_4000woc.Time, dU_4000woc.Data/Wf0*100, 'b', dU_Schd_4000.Time, dU_Schd_4000.Data/Wf0*100, 'k-.',  dU_4000.Time, dU_4000.Data/Wf0*100, 'k', 'LineWidth', 1.5);
ylim([-15, 13]);               xlim([1,6]);
legend( '$$\Delta u_{tmp}-CHGPI\ w.o.\ y_{dotc,lim}$$', '$$\Delta u_{c}-CHGPI\ w.o.\ y_{dotc,lim}$$',  '$$\Delta u_{tmp}-CHGPI$$', '$$\Delta u_{c}-CHGPI$$', 'Interpreter', 'latex');
title('$$\Delta u_{tmp}$$ vs. $$\Delta u_{c} (\%)$$', 'Interpreter', 'latex');
ylabel('$$\%$$', 'Interpreter', 'latex');        xlabel('Time (s)');


figure(1201);
plot(NpDemDt_2000lb.Time, NpDemDt_2000lb.Data/Np0*100, '--r', NpCHGPI_2000lb.Time, NpCHGPI_2000lb.Data/Np0*100, 'b-.', NpAPCHGPI_2000lb.Time, NpAPCHGPI_2000lb.Data/Np0*100, 'k', 'LineWidth', 1.5);
ylim([82, 104]);
legend('Np Ref',  'CHGPI',  'EKF-CHGPI');     title('Np (%)');       ylabel('%');        xlabel('Time (s)');
figure(1202);
plot(WfCHGPI_2000lb.Time, WfCHGPI_2000lb.Data/Wf0*100, 'b-.', WfAPCHGPI_2000lb.Time, WfAPCHGPI_2000lb.Data/Wf0*100, 'k', 'LineWidth', 1.5);
% ylim([0.095, 0.22]);
legend( 'CHGPI',  'EKF-CHGPI');     title('Wf (%)');       ylabel('%');        xlabel('Time (s)');
figure(1203);
plot(b11_ekf_2000lb.Time, b11_ekf_2000lb.Data/B(1,1)*100, 'b-', b11_filt_2000lb.Time, b11_filt_2000lb.Data/B(1,1)*100, 'k', 'LineWidth', 1.5);
ylim([45, 110]);
legend('$$\hat{b}_{EKF}$$',  '$$\hat{b}_{lp}$$', 'Interpreter', 'latex');     title('$$\hat{b}\ (\%)$$', 'Interpreter', 'latex');       ylabel('%');        xlabel('Time (s)');

figure(1301);
plot(NpDemDt_2000hb.Time, NpDemDt_2000hb.Data/Np0*100, '--r', NpCHGPI_2000hb.Time, NpCHGPI_2000hb.Data/Np0*100, 'b-.', NpAPCHGPI_2000hb.Time, NpAPCHGPI_2000hb.Data/Np0*100, 'k', 'LineWidth', 1.5);
ylim([82, 104]);
legend('Np Ref',  'CHGPI',  'EKF-CHGPI');     title('Np (%)');       ylabel('%');        xlabel('Time (s)');
figure(1302);
plot(WfCHGPI_2000hb.Time, WfCHGPI_2000hb.Data/Wf0*100, 'b-.', WfAPCHGPI_2000hb.Time, WfAPCHGPI_2000hb.Data/Wf0*100, 'k', 'LineWidth', 1.5);
% ylim([0.04, 0.27]);
legend( 'CHGPI',  'EKF-CHGPI');     title('Wf (%)');       ylabel('%');        xlabel('Time (s)');
figure(1303);
plot(b11_ekf_2000hb.Time, b11_ekf_2000hb.Data/B(1,1)*100, 'b-.', b11_filt_2000hb.Time, b11_filt_2000hb.Data/B(1,1)*100, 'k', 'LineWidth', 1.5);
ylim([95, 205]);
legend('$$\hat{b}_{EKF}$$',  '$$\hat{b}_{lp}$$', 'Interpreter', 'latex');     title('$$\hat{b}\ (\%)$$', 'Interpreter', 'latex');       ylabel('%');        xlabel('Time (s)');

figure(1401);
plot(NpDemDt_200hb.Time, NpDemDt_200hb.Data/Np0*100, '--r', NpAMADRC_EKF_200hb.Time, NpAMADRC_EKF_200hb.Data/Np0*100, 'b-.', NpAPCHGPI_200hb.Time, NpAPCHGPI_200hb.Data/Np0*100, 'k', 'LineWidth', 1.5);
% ylim([84, 2.07e4]);
legend('Np Ref',  'EKF-ARSC-LADRC',  'EKF-CHGPI');     title('Np (%)');       ylabel('%');        xlabel('Time (s)');
figure(1402);
plot(WfAMADRC_EKF_200hb.Time, WfAMADRC_EKF_200hb.Data/Wf0*100, 'b-.', WfAPCHGPI_200hb.Time, WfAPCHGPI_200hb.Data/Wf0*100, 'k', 'LineWidth', 1.5);
% ylim([0.04, 0.27]);
legend( 'EKF-ARSC-LADRC',  'EKF-CHGPI');     title('Wf (%)');       ylabel('%');        xlabel('Time (s)');
figure(1403);
plot(b11AMADRC_filt_200hb.Time, b11AMADRC_filt_200hb.Data/B(1,1)*100, 'b-.', b11_filt_200hb.Time, b11_filt_200hb.Data/B(1,1)*100, 'k', 'LineWidth', 1.5);
ylim([95, 205]);
legend('EKF-ARSC-LADRC',  'EKF-CHGPI');     title('$$\hat{b}\ (\%)$$', 'Interpreter', 'latex');       ylabel('%');        xlabel('Time (s)');

end

%% 结束
[out_ret] = calllib(slib_name, sfunc_free_name);
clear eng_ptr_init;
clear eng_ptr;
clear step_in;
clear step_out;
unloadlibrary(slib_name);





