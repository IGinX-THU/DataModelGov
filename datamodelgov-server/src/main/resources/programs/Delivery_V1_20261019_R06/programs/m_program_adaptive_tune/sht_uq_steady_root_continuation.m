function candidates=sht_uq_steady_root_continuation(evaluate,reference,schedules,data,cfg,user,evaluateReference)
% 独立UQ预测的稳态解支追踪。经验Np带不是参数不确定性下的物理可行域。
% 先用交付的确定性模型、当前输入求参考根；随后仅改变模型参数，
% 以相邻严格根为初值，限制单步Np/Ng及气路变量变化，直至完整目标模型。
% 不读目标测量输出选根，不修改输入/后验粒子，也不把失败中间点当最终解。
if nargin<6,user=struct();end
if nargin<7,evaluateReference=evaluate;end
limit=local_option(user,'maximumRelativeShaftStep',.02);
minimumStep=local_option(user,'minimumParameterStep',1/1024);
assert(isscalar(limit)&&isfinite(limit)&&limit>0&&limit<=.05);
assert(isscalar(minimumStep)&&isfinite(minimumStep)&&minimumStep>0&&minimumStep<1);
n=numel(schedules);m=height(data);
candidates=repmat(struct('schedule',struct(),'prediction',table(),'valid',false,'diagnostic',struct()),n,1);
anchors=cell(m,1);
for j=1:m
    anchors{j}=local_anchor(evaluate,evaluateReference,reference,data(j,:),cfg);
end
for i=1:n
    records=cell(m,1);diagnostics=cell(m,1);
    for j=1:m
        a=anchors{j};point=data(j,:);r=a.record;d=a.diagnostic;
        seed=a.seed;progress=0;step=1;attempts=0;accepted=0;largestShaftStep=0;
        largestResidual=0;ok=a.valid;
        while ok && progress<1 && attempts<128
            next=min(1,progress+step);
            schedule=local_blend(reference,schedules{i},next);
            stepPoint=point;
            stepPoint.Np_branch_center_rpm=seed(end-1);
            stepPoint.Np_branch_lower_rpm=seed(end-1)*(1-limit);
            stepPoint.Np_branch_upper_rpm=seed(end-1)*(1+limit);
            stepPoint.Np_branch_relative_half_width=limit;
            stepPoint.Np_branch_available=true;
            stepPoint.Np_branch_source="local_parameter_continuation";
            stepPoint.Np_branch_reference_uses_point_Np=false;
            [trial,~,td]=evaluate(stepPoint,schedule,seed);
            attempts=attempts+1;
            valid=local_strict(trial,td);
            if valid
                z=td.solutionSeed;
                shaftChange=max(abs(z(end-1:end)./seed(end-1:end)-1));
                % Np相近不能单独证明同解支，同时核查Ng、流量和压比连续性。
                gas=[1,3:(numel(seed)-2)];
                gasChange=max(abs(z(gas)./seed(gas)-1));
                valid=shaftChange<=limit && gasChange<=.10 && abs(z(2)-seed(2))<=.10;
            end
            if valid
                r=trial;d=td;seed=z;progress=next;accepted=accepted+1;
                largestShaftStep=max(largestShaftStep,shaftChange);
                largestResidual=max(largestResidual,r.max_model_residual);
                step=min(1,step*2);
            else
                step=step/2;
                if step<minimumStep,ok=false;end
            end
        end
        ok=ok && progress==1;
        if ~ok
            r.valid=false;
            r.error_message="steady_parameter_continuation_incomplete";
            if ~a.valid,r.error_message="no_verified_deterministic_reference_root";end
            d.solutionAvailable=false;
        end
        r.root_continuation_passed=ok;
        r.root_continuation_progress=progress;
        r.root_continuation_attempts=attempts;
        r.root_continuation_steps=accepted;
        r.root_continuation_max_shaft_step=largestShaftStep;
        r.root_continuation_max_residual=largestResidual;
        r.reference_root_Np=a.record.Np;r.reference_root_Ng=a.record.Ng;
        r.empirical_np_available=point.Np_branch_available && ...
            all(isfinite([point.Np_branch_center_rpm,point.Np_branch_lower_rpm,point.Np_branch_upper_rpm]));
        r.empirical_np_inside=local_in_band(r.Np,point);
        r.empirical_np_center=point.Np_branch_center_rpm;
        r.empirical_np_lower=point.Np_branch_lower_rpm;
        r.empirical_np_upper=point.Np_branch_upper_rpm;
        r.np_branch_active=true;r.np_branch_passed=ok;
        r.np_branch_source="deterministic_reference_root_continuation";
        r.np_branch_attempt_count=attempts;
        r.outside_np_preference_admitted=ok && r.empirical_np_available && ~r.empirical_np_inside;
        d.branchPassed=ok;d.branchAttemptCount=attempts;
        d.branchSelectedNpRpm=r.Np;d.seedSource="deterministic_reference_root_continuation";
        records{j}=r;diagnostics{j}=d;
    end
    candidates(i).schedule=schedules{i};
    candidates(i).prediction=vertcat(records{:});
    candidates(i).valid=all(candidates(i).prediction.valid);
    fields=fieldnames(diagnostics{1});
    for k=1:numel(fields)
        pieces=cellfun(@(x)x.(fields{k}),diagnostics,'UniformOutput',false);
        candidates(i).diagnostic.(fields{k})=vertcat(pieces{:});
    end
end
end

function a=local_anchor(evaluate,evaluateReference,reference,point,cfg)
% 多初值只用于确定性参考根。Ng候选是工程数值初值，不是观测约束。
% 经验带内优先；带外根需另一初值复现，不混入尚未被复核的候选根。
% 首先完整保留原参考模型的气路准备及多初值选根，不能用裸Newton替代。
[r,~,d]=evaluateReference(point,reference,[]);
if local_strict(r,d) && local_in_band(r.Np,point)
    a=struct('record',r,'diagnostic',d,'seed',d.solutionSeed,'valid',true);return;
end
referencePoint=point;referencePoint.Np_branch_available=false;
referencePoint.Np_branch_optional=true;
[r,~,d]=evaluate(referencePoint,reference,[]);
a=struct('record',r,'diagnostic',d,'seed',d.solutionSeed,'valid',local_strict(r,d));
base=d.baseSeed;found={};
if a.valid,found={a};end
if a.valid && local_in_band(r.Np,point),return;end
for ratio=[.8,.65,.55,1.05]
    seed=base;seed(end)=ratio*cfg.engine.initial.Ng0;
    [r,~,d]=evaluate(referencePoint,reference,seed);
    if ~local_strict(r,d),continue;end
    b=struct('record',r,'diagnostic',d,'seed',d.solutionSeed,'valid',true);
    confirmed=any(cellfun(@(x)max(abs(x.seed(end-1:end)-b.seed(end-1:end)))<.1,found));
    found{end+1}=b; %#ok<AGROW>
    if local_in_band(r.Np,point) || confirmed
        a=b;return;
    end
end
a.valid=false;
end

function tf=local_strict(r,d)
tf=r.valid && d.solutionAvailable && isfinite(r.max_model_residual) && ...
    r.max_model_residual<=1e-7 && all(isfinite(d.solutionSeed),'all') && ...
    all([r.Np,r.Ng,r.Wa2,r.Tt3,r.Tt45,r.Tt6]>0) && ...
    r.gt_total_pressure_ratio>1 && r.pt_total_pressure_ratio>1 && r.Pt6>r.Pback;
end

function tf=local_in_band(np,data)
tf=isfinite(data.Np_branch_center_rpm) && np>=data.Np_branch_lower_rpm && np<=data.Np_branch_upper_rpm;
end

function out=local_blend(a,b,t)
% 只插值参数纵坐标，绝不移动节点；t=1原样返回，防止目标参数被舍入改变。
if t==1,out=b;return;end
out=b;out.designHealth=(1-t)*a.designHealth+t*b.designHealth;
out.h15=(1-t)*a.h15+t*b.h15;
for k=1:numel(b.healthEntries)
    e=b.healthEntries(k);j=find([a.healthEntries.cIndex]==e.cIndex,1);
    assert(~isempty(j),'SHT:UQRoot:ReferenceEntry','参考模型缺少h%d。',e.cIndex);
    v=local_interp(a.healthEntries(j).xNodesDll,a.healthEntries(j).kNodesDll,e.xNodesDll);
    e.kNodesDll=(1-t)*v+t*e.kNodesDll;
    e.kNodes=e.kNodesDll;e.designValue=local_interp(e.xNodesDll,e.kNodesDll,e.designCoordinate);
    e.deltaNodesDll=e.kNodesDll-e.designValue;
    out.healthEntries(k)=e;out.designHealth(e.cIndex+1)=e.designValue;
end
v=local_interp(a.fuelBias.xNodes,a.fuelBias.biasNodes,b.fuelBias.xNodes);
out.fuelBias.biasNodes=(1-t)*v+t*b.fuelBias.biasNodes;
end

function y=local_interp(x,v,q)
if numel(x)==1,y=repmat(v,size(q));else,y=interp1(x,v,min(max(q,min(x)),max(x)),'linear');end
end

function v=local_option(s,name,default)
v=default;if isfield(s,name),v=s.(name);end
end
