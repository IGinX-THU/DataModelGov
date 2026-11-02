function schedule=sht_2p4_uq_delivery_schedule(delivery,model,theta)
%SHT_2P4_UQ_DELIVERY_SCHEDULE 按参数ID和物理坐标恢复联合样本的调度。
% 固定节点与未采样系数继承配套确定性Excel；不能按行号猜测节点归属。
p=delivery.parameterTable; theta=theta(:);
if ismember('model_mode',delivery.manifest.Properties.VariableNames)
    assert(delivery.manifest.model_mode==model.options.modelMode, ...
        'SHT:UQDelivery:ModelModeMismatch','后验与确定性Excel的三/六部件模型模式不一致。');
end
assert(strcmp(delivery.route,model.route) && numel(theta)==height(p), ...
    'SHT:UQDelivery:RouteMismatch','后验与确定性模型路径或维数不匹配。');
assert(all(isfinite(theta)) && all(theta>=p.lowerBound-1e-12) && ...
    all(theta<=p.upperBound+1e-12),'SHT:UQDelivery:InvalidVector', ...
    '候选联合参数超出Excel硬边界。');
schedule=model.finalSchedule;
for j=1:height(p)
    kind=string(p.groupKind(j)); h=double(p.cIndex(j));
    switch kind
        case "health_schedule"
            e=find([schedule.healthEntries.cIndex]==h);
            assert(numel(e)==1,'SHT:UQDelivery:MissingCurve','找不到h%d调度。',h);
            x=schedule.healthEntries(e).xNodesDll(:);
            k=find(abs(x-p.coordinate(j))<=1e-10*max(1,abs(p.coordinate(j))));
            assert(numel(k)==1,'SHT:UQDelivery:MissingNode','h%d节点坐标不匹配。',h);
            reference=schedule.healthEntries(e).kNodesDll(k);
            schedule.healthEntries(e).kNodesDll(k)=theta(j);
        case "fuel_bias"
            k=find(abs(schedule.fuelBias.xNodes-p.coordinate(j))<=1e-10);
            assert(numel(k)==1,'SHT:UQDelivery:MissingFuelNode','燃油偏置节点不匹配。');
            reference=schedule.fuelBias.biasNodes(k);
            schedule.fuelBias.biasNodes(k)=theta(j);
        case "constant"
            assert(h==15,'SHT:UQDelivery:UnknownConstant','不支持的常值参数。');
            reference=schedule.h15; schedule.h15=theta(j);
        case "health_constant"
            reference=schedule.designHealth(h+1);
            schedule.designHealth(h+1)=theta(j);
        otherwise
            error('SHT:UQDelivery:UnknownRole','不支持的参数角色：%s。',kind);
    end
    if delivery.deterministicReferenceReliable && isfinite(p.deterministicEstimate(j))
        assert(abs(reference-p.deterministicEstimate(j))<1e-10, ...
            'SHT:UQDelivery:SourceMismatch', ...
            '参数%s的确定性参考不匹配，请使用同一辨识结果的Excel。',string(p.name(j)));
    end
end
if ismember('deterministic_run_id',delivery.manifest.Properties.VariableNames)
    assert(string(delivery.manifest.deterministic_run_id)==string(model.runId), ...
        'SHT:UQDelivery:RunMismatch','后验与确定性工作簿不是同一辨识运行。');
end
for e=1:numel(schedule.healthEntries)
    entry=schedule.healthEntries(e);
    x=entry.xNodesDll(:); k=entry.kNodesDll(:);
    assert(all(diff(x)>0),'SHT:UQDelivery:UnorderedNodes','调度节点必须严格递增。');
    if entry.pressureLoss
        assert(x(1)==0 && k(1)==0,'SHT:UQDelivery:NonzeroLossAnchor', ...
            '压损零流量节点必须为固定零值。');
    end
    entry.xNodes=x; entry.kNodes=k;
    if numel(x)==1, entry.designValue=k(1);
    else, entry.designValue=interp1(x,k,min(max(entry.designCoordinate,x(1)),x(end)),'linear'); end
    entry.deltaNodesDll=k-entry.designValue;
    schedule.healthEntries(e)=entry;
    schedule.designHealth(entry.cIndex+1)=entry.designValue;
end
schedule.designHealth(16)=schedule.h15;
end
