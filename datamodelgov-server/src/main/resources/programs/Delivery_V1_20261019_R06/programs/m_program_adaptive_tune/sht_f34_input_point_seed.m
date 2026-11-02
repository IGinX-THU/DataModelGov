function out=sht_f34_input_point_seed(action,varargin)
%SHT_F34_INPUT_POINT_SEED 独立工况输入检查及只依赖输入的稳态数值初值。
% 转速是输出。初猜来自所选公开模型，不允许把测量转速用于选根。
switch lower(action)
    case 'validate',out=local_validate(varargin{:});
    case 'solve',out=local_solve(varargin{:});
    otherwise,error('SHT:F34Seed:Action','未知操作：%s。',action);
end
end

function p=local_validate(p,units)
assert(istable(p)&&height(p)>0,'SHT:F34Seed:Points','必须给出非空输入工况表。');
names={'Altitude_mean','Mach_mean','Pamb_mean','Tamb_mean','Tt1_mean','Mkp_mean','Wf_mean'};
expected={'m','1','Pa','K','K','N*m','kg/s'};
assert(all(ismember([{'point_id'},names],p.Properties.VariableNames)), ...
    'SHT:F34Seed:Missing','缺少高度、Mach、环境静压/静温、进口总温、负载扭矩或测量燃油。');
allowed=[{'point_id','sample_count'},names];
extra=setdiff(p.Properties.VariableNames,allowed);
assert(isempty(extra),'SHT:F34Seed:OutputInput', ...
    '自主预测输入不允许待预测输出、不可测背压或未知字段：%s。',strjoin(extra,','));
p.point_id=string(p.point_id);
assert(all(strlength(p.point_id)>0)&&numel(unique(p.point_id))==height(p),'SHT:F34Seed:PointId','点号必须非空且唯一。');
for j=1:numel(names)
    assert(isfield(units,names{j})&&strcmp(units.(names{j}),expected{j}), ...
        'SHT:F34Seed:Unit','%s单位必须明确为%s。',names{j},expected{j});
    validateattributes(p.(names{j}),{'numeric'},{'column','finite'});
end
assert(all(p.Pamb_mean>0 & p.Tamb_mean>0 & p.Tt1_mean>0 & p.Wf_mean>0 & ...
    p.Mach_mean>=0 & p.Mkp_mean>=0),'SHT:F34Seed:PhysicalInput','温压/燃油须正，Mach/负载扭矩不得为负。');
if ~ismember('sample_count',p.Properties.VariableNames),p.sample_count=ones(height(p),1);end
validateattributes(p.sample_count,{'numeric'},{'column','integer','positive','finite'});
p.Mkg_mean=zeros(height(p),1); % 现行飞参合同没有附件扭矩测量，沿用明确的零附件边界。
end

function out=local_solve(package,points,o)
assert(package.deterministic,'SHT:F34Seed:Model','初值选择须明确使用确定性模型。');
state=package.assets.configuration.engine.initial.state(:);
assert(numel(state)==16,'SHT:F34Seed:Topology','本入口为三部件Visser16。');
validateattributes(o.seedScales,{'numeric'},{'vector','positive','finite'});
assert(numel(o.npBounds)==2&&o.npBounds(1)>0&&o.npBounds(2)>o.npBounds(1), ...
    'SHT:F34Seed:Bounds','Np物理解范围无效。');
pool=sht_f34_deployment('jointModels',package,o);
n=height(points);chosen=cell(n,1);audit=table();rootCount=zeros(n,1);seeds=nan(n,2);
started=tic;
for j=1:n
    solutions=[];candidates={};
    for k=1:numel(o.seedScales)
        speed=state(1:2)'*o.seedScales(k);
        speed(1)=min(max(speed(1),o.npBounds(1)),o.npBounds(2));
        speed(2)=min(max(speed(2),5000),70000);
        b=struct('pointIds',points.point_id(j),'speedSeed',speed, ...
            'lowerNp',o.npBounds(1),'upperNp',o.npBounds(2),'pointMeasuredSpeedUsed',false);
        r=sht_f34_deployment('evaluateModels',package.assets,points(j,:),b,pool);
        audit=[audit;table(points.point_id(j),k,speed(1),speed(2),r.valid(1), ...
            r.reason(1),r.elapsed_s,'VariableNames', ...
            {'point_id','attempt','initial_Np','initial_Ng','success','reason','elapsed_s'})]; %#ok<AGROW>
        if r.valid(1)
            v=reshape(r.value(1,1:2,1),1,2);
            if isempty(solutions)||all(max(abs((solutions-v)./max(abs(v),1)),[],2)>1e-4)
                solutions(end+1,:)=v;candidates{end+1}=r; %#ok<AGROW>
            end
        end
    end
    rootCount(j)=size(solutions,1);
    if rootCount(j)>0
        % 固定规则选距模型名义转速最近的已收敛根；多根必须报告，不能声称唯一。
        distance=sum(((solutions-state(1:2)')./state(1:2)').^2,2);
        [~,k]=min(distance);seeds(j,:)=solutions(k,:);chosen{j}=candidates{k};
    end
end
branch=struct('pointIds',points.point_id,'speedSeed',seeds, ...
    'lowerNp',repmat(o.npBounds(1),n,1),'upperNp',repmat(o.npBounds(2),n,1), ...
    'source','public_model_multistart_input_only','pointMeasuredSpeedUsed',false, ...
    'rootCount',rootCount,'uniquePhysicalRootProven',false);
out=struct('branch',branch,'chosen',{chosen},'audit',audit,'rootCount',rootCount, ...
    'valid',rootCount>0,'elapsed_s',toc(started),'initialStateSource','selected_model_nominal_state');
end
