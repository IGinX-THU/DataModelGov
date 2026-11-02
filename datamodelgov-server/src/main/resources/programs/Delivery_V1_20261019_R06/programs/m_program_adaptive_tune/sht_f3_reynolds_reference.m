function r=sht_f3_reynolds_reference(cfg,scale)
%SHT_F3_REYNOLDS_REFERENCE 由本运行包三部件设计气路确定RNI参考状态。
% 参考不来自六部件硬编码，也不来自带健康修正的任务初始状态。
b=cfg.engine.boundary;b.health=zeros(159,1);b.healthScheduleEnabled=false;
probe=cfg.engine;probe.healthScheduleProfile=[];
probe.boundary=b;probe.transientEffects.enabled=false;
probe.initial.state=probe.initial.state(1:2);
if isfield(probe,'reynoldsCorrection'),probe=rmfield(probe,'reynoldsCorrection');end
e=sht_engine_open(probe);cleanup=onCleanup(@()sht_engine_close(e)); %#ok<NASGU>
b.ptLoadInputMode='torque';b.gtLoadInputMode='torque';b.Mkg=0;
b.Mkp=cfg.engine.initial.power0/(cfg.engine.initial.Np0*pi/30);
[~,~,d]=sht_engine_derivative(e,probe.initial.state,cfg.engine.initial.Wf0,b);
assert(d.ret==0&&d.convergeTag==0,'SHT:F3:RniReference','三部件设计参考计算失败。');
a=e.callContext.engPtr.eng;
tt=[a.Inlet.gasPathOut(3),a.HPT.y(22),a.LPT.y(22)];
pt=[a.Inlet.gasPathOut(4),a.HPT.y(23),a.LPT.y(23)];
names={'HPC','GT','PT'};maps={'HPC02.MAP','HPT02.MAP','LPT02.MAP'};
for k=1:3
    reference(k)=struct('name',names{k},'designTemperature_K',double(tt(k)), ...
        'designPressure_Pa',double(pt(k)),'mapPath',fullfile(cfg.engine.interface.controlDir,maps{k})); %#ok<AGROW>
end
r=sht_reynolds_correction_config(scale,0,reference);
end
