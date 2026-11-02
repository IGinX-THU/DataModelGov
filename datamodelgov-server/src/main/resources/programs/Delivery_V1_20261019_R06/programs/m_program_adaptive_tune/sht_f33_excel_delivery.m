function out=sht_f33_excel_delivery(action,value,varargin)
% 三部件确定性模型的最小正式Excel；不包含训练历程、真值或求解调试记录。
% read只从本Excel恢复绝对曲线，运行资产由消费者显式传入并核对身份。
switch lower(action)
    case 'definitions'
        out=local_definitions(value);
    case 'restoreschedule'
        definitions=value.curveDefinitions;
        if ~isempty(varargin),definitions=varargin{1};end
        out=local_restore_schedule(value,definitions);
    case 'write'
        r=value;file=varargin{1};assert(r.options.modelMode==0);
        % 导出只核对运行资产身份，不配置发动机或加载DLL。
        a=sht_f3_current_contract('runtimeIdentity');
        profile=sht_f33_model_adapt_v2('buildProfile',r.finalSchedule);
        definitions=local_definitions(r.finalSchedule);
        if isfile(file)
            old=sht_f33_excel_delivery('read',file,a);
            assert(max(abs(old.schedule.designHealth-r.finalSchedule.designHealth))<1e-12&& ...
                abs(old.KdistEq-r.estimatedKdistEq)<1e-12&& ...
                max(abs(old.schedule.fuelBias.biasNodes-r.finalSchedule.fuelBias.biasNodes))<1e-12, ...
                'SHT:F33Delivery:Overwrite','同名正式交付与当前结果不同，必须更换批次。');
            for j=1:numel(profile.parameters)
                q=profile.parameters(j);z=old.profile.parameters(j);
                assert(numel(z.xNodes)==numel(q.xNodes)&&max(abs(z.xNodes-q.xNodes))<1e-10&& ...
                    max(abs(z.kNodes-q.kNodes))<1e-12,'禁止覆盖不同曲线交付。');
            end
            assert(local_same_definitions(old.curveDefinitions,definitions), ...
                'SHT:F33Delivery:Overwrite','已有文件的辨识定义不同或缺失，不能补写冻结文件。');
            local_check_business(old.metadata,r.options);
            out=file;return;
        end
        % 正式目标也必须可直接读写；不能用短临时文件掩盖非法长目标路径。
        assert(numel(file)<=240,'SHT:F33Delivery:PathLength', ...
            '正式Excel路径超过240字符，请使用较短输出目录或compact命名：%s。',file);
        target=file;[~,nonce]=fileparts(tempname(fileparts(target)));
        file=fullfile(fileparts(target),['f3_',nonce(1:min(12,numel(nonce))),'.xlsx']);
        cleanup=onCleanup(@()local_remove_temporary(file)); %#ok<NASGU>
        meta=table("F33_THREE_DETERMINISTIC_EXCEL_V1",0,16, ...
            string(r.routeId),string(r.training.sourceSha256),string(r.prior.sourceSha256), ...
            r.estimatedKdistEq,.995,1500,2176600,5, ...
            'VariableNames',{'schema','model_mode','state_count','route','training_sha256', ...
            'reference_sha256','K_dist_eq','mean_inlet_recovery','backpressure_design_Pa', ...
            'design_power_W','inlet_boundary_mode'});
        meta.model_route=string(r.options.modelRoute);
        if isfield(r,'converged'),meta.converged=logical(r.converged);end
        if isfield(r,'stopReason'),meta.stop_reason=string(r.stopReason);end
        meta=local_add_business(meta,r.options);
        writetable(meta,file,'Sheet','Model');
        writetable(definitions,file,'Sheet','CurveDefinitions');
        if isfield(r.options,'businessIdentity')&&~isempty(fieldnames(r.options.businessIdentity))
            writetable(sht_f3_business_identity('table',r.options.businessIdentity),file,'Sheet','BusinessIdentity');
        end
        writetable(table((0:158)',r.finalSchedule.designHealth(:), ...
            'VariableNames',{'c_index','k_design'}),file,'Sheet','HealthDesign');
        nodes=table();
        for j=1:numel(profile.parameters)
            q=profile.parameters(j);n=numel(q.xNodes);
            nodes=[nodes;table(repmat(q.cIndex,n,1),repmat(string(q.axisName),n,1), ...
                q.xNodes(:),q.kNodes(:),'VariableNames',{'c_index','axis','x','k'})]; %#ok<AGROW>
        end
        writetable(nodes,file,'Sheet','HealthNodes');
        f=r.finalSchedule.fuelBias;
        writetable(table(f.xNodes(:),f.biasNodes(:),repmat(f.wfDesign,numel(f.xNodes),1), ...
            'VariableNames',{'measured_wf_over_design','bias_kgps','wf_design_kgps'}),file,'Sheet','FuelBias');
        names=[string(a.contract.runtimeFiles(:));"VisserAsset"];
        sha=[string(a.contract.runtimeHashes(:));string(a.contract.runtimeVisserAssetSha256)];
        writetable(table(names,sha,'VariableNames',{'asset','sha256'}),file,'Sheet','Runtime');
        % 所有表读回且物理值一致后一次发布，失败不得留下半份正式交付。
        restored=sht_f33_excel_delivery('read',file,a);
        for key=meta.Properties.VariableNames
            expected=meta.(key{1});actual=restored.metadata.(key{1});
            % Excel将logical存为0/1；核对值，不把存储类变化当作身份变化。
            if isnumeric(expected)||islogical(expected)
                same=(isnumeric(actual)||islogical(actual))&&isequal(size(actual),size(expected))&& ...
                    all(isfinite(double(actual(:))))&& ...
                    all(abs(double(actual(:))-double(expected(:)))<=1e-12*max(1,abs(double(expected(:)))));
            else,same=isequal(string(actual),string(expected));end
            assert(same,'SHT:F33Delivery:RoundTrip','模型元数据读回不一致：%s。',key{1});
        end
        assert(max(abs(restored.schedule.designHealth-r.finalSchedule.designHealth))<1e-12&& ...
            abs(restored.KdistEq-r.estimatedKdistEq)<1e-12&& ...
            max(abs(restored.schedule.fuelBias.biasNodes-r.finalSchedule.fuelBias.biasNodes))<1e-12, ...
            'SHT:F33Delivery:RoundTrip','正式Excel读回核验不一致。');
        for j=1:numel(profile.parameters)
            q=profile.parameters(j);z=restored.profile.parameters(j);
            assert(numel(q.xNodes)==numel(z.xNodes)&& ...
                max(abs(q.xNodes(:)-z.xNodes(:)))<1e-12&&max(abs(q.kNodes(:)-z.kNodes(:)))<1e-12, ...
                'SHT:F33Delivery:RoundTrip','调度曲线读回不一致。');
        end
        assert(~isfile(target),'SHT:F33Delivery:ConcurrentWrite','目标文件已由其他写入者建立，禁止覆盖。');
        [ok,msg]=movefile(file,target);assert(ok,'SHT:F33Delivery:Publish','发布正式Excel失败：%s。',msg);
        out=target;
    case {'read','inspect'}
        file=value;m=readtable(file,'Sheet','Model');
        assert(height(m)==1&&string(m.schema)=="F33_THREE_DETERMINISTIC_EXCEL_V1"&& ...
            m.model_mode==0&&m.state_count==16&&m.inlet_boundary_mode==5, ...
            'SHT:F33Delivery:Model','交付模型合同不匹配。');
        runtime=readtable(file,'Sheet','Runtime');
        verified=strcmpi(action,'read');association=struct('status','read_only_source_identity');
        if verified
            a=varargin{1};names=[string(a.contract.runtimeFiles(:));"VisserAsset"];
            sha=[string(a.contract.runtimeHashes(:));string(a.contract.runtimeVisserAssetSha256)];
            assert(isequal(string(runtime.asset),names), ...
                'SHT:F33Delivery:Runtime','交付物理资产字典不匹配。');
            if all(strcmpi(string(runtime.sha256),sha))
                association=struct('status','same_runtime_identity', ...
                    'sourceHashes',{cellstr(string(runtime.sha256))},'executionHashes',{cellstr(sha)}, ...
                    'oldPosteriorRecomputed',false,'checkpointCompatibilityGranted',false);
            else
                directory='';
                if isfield(a,'runtimeDirectory'),directory=a.runtimeDirectory;
                elseif isfield(a,'configuration'),directory=a.configuration.engine.interface.controlDir;end
                if isempty(directory)
                    association=sht_f3_three_component_assets('association',runtime.asset,runtime.sha256);
                else
                    association=sht_f3_three_component_assets('association',runtime.asset,runtime.sha256,directory);
                end
                assert(all(strcmpi(string(association.executionHashes),sha)), ...
                    'SHT:F33Delivery:Runtime','显式运行目录与传入资产身份不同。');
            end
        else
            % 查看冻结模型不要求开发机路径或物理包；重新预测仍必须走read核验。
            names=["GTESS.dll";"GTESS.h";"Turboshaft-TS.mdl";"HPC02.MAP";"HPT02.MAP";"LPT02.MAP";"VisserAsset"];
            assert(isequal(string(runtime.asset),names)&& ...
                all(~cellfun('isempty',regexp(cellstr(string(runtime.sha256)),'^[A-Fa-f0-9]{64}$','once'))), ...
                'SHT:F33Delivery:Runtime','保存的资产身份表不完整。');
        end
        h=readtable(file,'Sheet','HealthDesign');n=readtable(file,'Sheet','HealthNodes');
        f=readtable(file,'Sheet','FuelBias');
        assert(isequal(h.c_index,(0:158)')&&all(isfinite(h.k_design))&&all(h.k_design(59:71)==0));
        entries=struct('cIndex',{},'xNodes',{},'kNodes',{});
        ids=unique(n.c_index,'stable');
        assert(isequal(ids,[0:3,6:14]'),'正式交付缺少三部件调度表。');
        dict=sht_health_parameter_dictionary(0);
        for j=1:numel(ids)
            z=n(n.c_index==ids(j),:);local_nodes(z.x,z.k);
            rows=dict.c_index==ids(j);
            assert(nnz(rows)==1,'物理编号未知。');
            entries(j)=struct('cIndex',ids(j),'xNodes',z.x,'kNodes',z.k); %#ok<AGROW>
        end
        local_nodes(f.measured_wf_over_design,f.bias_kgps);
        assert(all(f.wf_design_kgps==f.wf_design_kgps(1))&&f.wf_design_kgps(1)>0);
        schedule=struct('modelMode',0,'designHealth',h.k_design,'healthEntries',entries, ...
            'fuelBias',struct('xNodes',f.measured_wf_over_design,'biasNodes',f.bias_kgps, ...
            'wfDesign',f.wf_design_kgps(1)));
        profile=sht_f33_model_adapt_v2('buildProfile',schedule);
        for j=1:numel(profile.parameters)
            q=profile.parameters(j);z=n(n.c_index==q.cIndex,:);
            assert(all(string(z.axis)==string(q.axisName))&&max(abs(z.k-q.kNodes))<1e-12, ...
                '交付坐标定义或零流量约束不一致。');
        end
        assert(isfinite(m.K_dist_eq)&&m.K_dist_eq>=0&&m.K_dist_eq<m.mean_inlet_recovery);
        out=struct('schedule',schedule,'profile',profile,'KdistEq',m.K_dist_eq,'metadata',m, ...
            'runtime',runtime,'runtimeVerified',verified,'readOnly',~verified, ...
            'runtimeAssociation',association);
        [~,sheets]=xlsfinfo(file);out.curveDefinitions=table();
        if ismember('CurveDefinitions',sheets)
            out.curveDefinitions=readtable(file,'Sheet','CurveDefinitions');
            local_restore_schedule(out,out.curveDefinitions);
        end
        out.reidentificationDefinitionAvailable=~isempty(out.curveDefinitions);
    otherwise
        error('SHT:F33Delivery:Action','未知交付动作。');
end
end

function same=local_same_definitions(a,b)
% Excel将logical读为数值、string读为cell，不以存储类差异误判物理定义。
same=height(a)==height(b)&&isequal(a.Properties.VariableNames,b.Properties.VariableNames);
if ~same,return;end
for key=b.Properties.VariableNames
    expected=b.(key{1});actual=a.(key{1});
    if isnumeric(expected)||islogical(expected)
        same=isequal(size(actual),size(expected))&&all(isfinite(double(actual(:))))&& ...
            all(abs(double(actual(:))-double(expected(:)))<=1e-12*max(1,abs(double(expected(:)))));
    else
        same=isequal(string(actual),string(expected));
    end
    if ~same,return;end
end
end

function t=local_definitions(s)
% 只传再次辨识必需的物理定义，不传原训练数据或历史优化状态。
rows=cell(numel(s.healthEntries),1);
for j=1:numel(s.healthEntries)
    e=s.healthEntries(j);
    required={'name','axisName','axisType','pressureLoss','designCoordinate','lowerBound','upperBound'};
    missing=required(~isfield(e,required));
    assert(isempty(missing),'SHT:F33Delivery:Definition', ...
        'h%d缺少显式字段：%s。应恢复已核参数定义，不猜测设计点或上下界。',e.cIndex,strjoin(missing,', '));
    values={e.axisType,e.designCoordinate,e.lowerBound,e.upperBound};
    valid=cellfun(@(v)isnumeric(v)&&isreal(v)&&isscalar(v)&&isfinite(v),values);
    assert(all(valid)&&e.designCoordinate>0&&e.lowerBound<e.upperBound, ...
        'SHT:F33Delivery:Definition','h%d的设计坐标/轴类型/上下界必须为有限实标量且上下界有序。',e.cIndex);
    indices=[0,1,2,6,7,8,10,11,12,14];axes=[1,5,5,2,7,7,3,8,8,4];
    pos=find(indices==e.cIndex);
    assert(isscalar(pos)&&e.axisType==axes(pos)&& ...
        isscalar(e.pressureLoss)&&ismember(e.pressureLoss,[false,true])&& ...
        logical(e.pressureLoss)==ismember(e.cIndex,[0,6,10,14]), ...
        'SHT:F33Delivery:Definition','h%d的轴类型或压损类别与物理编号冲突。',e.cIndex);
    unit="1";if e.pressureLoss,unit="kg/s";end
    rows{j}=table(e.cIndex,string(e.name),string(e.axisName),e.axisType,unit,"1", ...
        logical(e.pressureLoss),e.designCoordinate,e.lowerBound,e.upperBound,"linear","nearest_endpoint", ...
        'VariableNames',{'c_index','name','axis_name','axis_type','axis_unit','correction_unit', ...
        'pressure_loss','design_coordinate','lower_bound','upper_bound','interpolation','endpoint_policy'});
end
t=vertcat(rows{:});t=sortrows(t,'c_index');
assert(isequal(t.c_index,[0,1,2,6,7,8,10,11,12,14]'), ...
    'SHT:F33Delivery:Definition','再次辨识定义必须为10条现行健康曲线。');
end

function s=local_restore_schedule(d,t)
% 曲线的值来自父Excel；定义只说明坐标、设计位置与工程边界，不覆盖值。
names={'c_index','name','axis_name','axis_type','axis_unit','correction_unit', ...
    'pressure_loss','design_coordinate','lower_bound','upper_bound','interpolation','endpoint_policy'};
assert(istable(t)&&all(ismember(names,t.Properties.VariableNames))&&height(t)==10, ...
    'SHT:F33Delivery:Definition','缺少CurveDefinitions；旧文件需显式、哈希绑定的定义来源。');
t=sortrows(t,'c_index');ids=[0,1,2,6,7,8,10,11,12,14]';
assert(isequal(t.c_index,ids),'SHT:F33Delivery:Definition','曲线定义重复或缺失。');
dict=sht_health_parameter_dictionary(0);s=d.schedule;entries=cell(10,1);
o=sht_steady_model_adapt_v2_common('defaultoptions','transient_instant');
o.modelMode=0;o.estimateInletPressureLoss=true;
parameter=sht_steady_model_adapt_v2_common('parameterdefinition',o);
for j=1:10
    q=t(j,:);hit=find([s.healthEntries.cIndex]==q.c_index,1);e=s.healthEntries(hit);
    loss=ismember(q.c_index,[0,6,10,14]);unit="1";if loss,unit="kg/s";end
    profile=d.profile.parameters([d.profile.parameters.cIndex]==q.c_index);
    assert(isscalar(profile)&&string(q.name)==string(dict.name(q.c_index+1))&& ...
        string(q.axis_name)==string(profile.axisName)&&q.axis_type==parameter.axis_type(parameter.c_index==q.c_index)&& ...
        q.pressure_loss==loss&&string(q.axis_unit)==unit&&string(q.correction_unit)=="1"&& ...
        string(q.interpolation)=="linear"&&string(q.endpoint_policy)=="nearest_endpoint", ...
        'SHT:F33Delivery:Definition','h%d名称/坐标/单位/插值定义冲突。',q.c_index);
    assert(all(isfinite([q.design_coordinate,q.lower_bound,q.upper_bound]))&& ...
        q.lower_bound<q.upper_bound&&q.design_coordinate>0&&numel(e.xNodes)<=32, ...
        'SHT:F33Delivery:Definition','h%d设计坐标或边界无效。',q.c_index);
    design=interp1(e.xNodes,e.kNodes,min(max(q.design_coordinate,e.xNodes(1)),e.xNodes(end)),'linear');
    assert(abs(design-s.designHealth(q.c_index+1))<1e-10, ...
        'SHT:F33Delivery:DesignValue','h%d设计坐标插值与HealthDesign不一致。',q.c_index);
    entries{j}=struct('cIndex',q.c_index,'name',char(string(q.name)), ...
        'axisName',char(string(q.axis_name)),'axisType',q.axis_type,'pressureLoss',logical(q.pressure_loss), ...
        'xNodes',e.xNodes(:),'kNodes',e.kNodes(:),'designCoordinate',q.design_coordinate, ...
        'designValue',design,'xNodesDll',e.xNodes(:),'kNodesDll',e.kNodes(:), ...
        'deltaNodesDll',e.kNodes(:)-design,'lowerBound',q.lower_bound,'upperBound',q.upper_bound);
end
s.healthEntries=vertcat(entries{:});s.h15=s.designHealth(16);
end

function meta=local_add_business(meta,o)
if ~isfield(o,'businessIdentity')||isempty(fieldnames(o.businessIdentity)),return;end
b=o.businessIdentity;
assert(isfield(b,'scope')&&strcmp(b.scope,'deterministic')&&all(isfield(b, ...
    {'engineId','sortieId','parentModelId','modelId','evidence'})), ...
    'SHT:F33Delivery:BusinessIdentity','新业务交付需已解析的确定性编号。');
for item={'engineId','sortieId','parentModelId','modelId'}
    fields=struct('engineId','engine_id','sortieId','sortie_id','parentModelId','parent_model_id','modelId','model_id');
    meta.(fields.(item{1}))=string(b.(item{1}));
end
meta.run_id=string(o.businessRunId);meta.identity_purpose=string(b.purpose);
end

function local_check_business(meta,o)
expected=local_add_business(table(),o);
for key=expected.Properties.VariableNames
    assert(ismember(key{1},meta.Properties.VariableNames)&& ...
        isequal(string(meta.(key{1})),string(expected.(key{1}))), ...
        'SHT:F33Delivery:Overwrite','已存在交付业务身份不同：%s。',key{1});
end
end
function local_nodes(x,y)
assert(numel(x)>=2&&numel(x)==numel(y)&&all(isfinite(x))&&all(isfinite(y))&& ...
    all(diff(x)>0),'SHT:F33Delivery:Nodes','节点须有限、严格递增且一一对应。');
end

function local_remove_temporary(file)
% 只清理本次写入所创建的精确临时叶，不接触已有交付或失败运行。
if isfile(file),delete(file);end
end
