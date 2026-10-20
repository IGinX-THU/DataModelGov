function b=sht_fullmode_load_boundary(cfg,npRpm,rotorRpm)
%SHT_FULLMODE_LOAD_BOUNDARY 纯负载计算，无DLL/飞行任务/工作区副作用。
% Nrotor为PT侧折算旋翼转速，不能解释成真实旋翼rpm。恒功率和Mkp是
% 直接测功器轴负载；双总距只计算气动负载，传递Mkp由自由轮动力学得到。
f=cfg.fullmode;l=f.load;p=cfg.startStop;
validateattributes(npRpm,{'double'},{'scalar','real','finite','nonnegative'});
validateattributes(rotorRpm,{'double'},{'scalar','real','finite','nonnegative'});
b=struct('modeId',0,'mainTorqueNm',0,'tailTorqueNm',0,'aeroPowerW',0, ...
    'referencePowerW',0,'requestedPowerW',0,'requestedMkpNm',0, ...
    'mainPitchDeg',NaN,'tailPitchDeg',NaN, ...
    'powerEngaged',false,'engagementReason','not_applicable','vector',zeros(7,1));
switch f.loadMode
    case 'power'
        validateattributes(l.powerW,{'double'},{'scalar','real','finite','nonnegative'});
        b.modeId=1;b.requestedPowerW=l.powerW;
        b.powerEngaged=npRpm>=f.powerEngagementRpm;
        if b.powerEngaged,b.referencePowerW=l.powerW;b.engagementReason='active';
        else,b.engagementReason='pending_below_explicit_engagement_speed';end
    case 'mkp'
        validateattributes(l.mkpNm,{'double'},{'scalar','real','finite','nonnegative'});
        b.modeId=2;b.requestedMkpNm=l.mkpNm;b.referencePowerW=l.mkpNm*npRpm*pi/30;
    case 'dual_collective'
        validateattributes(l.mainPitchDeg,{'double'},{'scalar','real','finite'});
        validateattributes(l.tailPitchDeg,{'double'},{'scalar','real','finite'});
        assert(l.mainPitchDeg>=f.mainPitchBoundsDeg(1) && l.mainPitchDeg<=f.mainPitchBoundsDeg(2), ...
            '主桨总距超出配置范围，不静默截断。');
        assert(l.tailPitchDeg>=f.tailPitchBoundsDeg(1) && l.tailPitchDeg<=f.tailPitchBoundsDeg(2), ...
            '尾桨总距超出配置范围，不静默截断。');
        n=rotorRpm/p.designNpRpm;
        b.mainPitchDeg=l.mainPitchDeg;b.tailPitchDeg=l.tailPitchDeg;
        q=p.designRotorPowerW/(p.designNpRpm*pi/30);
        ratio=f.tailToMainPowerRatio;assert(ratio>=0 && isfinite(ratio));
        mainFraction=1/(1+ratio);tailFraction=1-mainFraction;
        gm=p.profileTorqueFraction+(1-p.profileTorqueFraction)* ...
            ((l.mainPitchDeg-p.thetaZeroDeg)/(p.thetaDesignDeg-p.thetaZeroDeg))^1.5;
        gt=p.profileTorqueFraction+(1-p.profileTorqueFraction)* ...
            abs(l.tailPitchDeg/f.tailDesignPitchDeg)^1.5;
        b.modeId=3;b.mainTorqueNm=q*mainFraction*gm*n^2;
        b.tailTorqueNm=q*tailFraction*(f.densityKgPerM3/f.designDensityKgPerM3)*gt*n^2;
        b.aeroPowerW=(b.mainTorqueNm+b.tailTorqueNm)*rotorRpm*pi/30;
        % 热平衡参考表使用稳态总负载，包含同一处旋翼侧机械损失。
        loss=p.rotorCoulombLossNm*tanh(rotorRpm/20)+p.rotorViscousLossNmPerKrpm*rotorRpm/1000;
        b.referencePowerW=b.aeroPowerW+loss*rotorRpm*pi/30;
    otherwise
        error('sht:fullmode:loadMode','未知负载模式。');
end
b.vector=[1;b.modeId;b.requestedPowerW;b.requestedMkpNm; ...
    b.mainTorqueNm;b.tailTorqueNm;f.powerEngagementRpm];
end
