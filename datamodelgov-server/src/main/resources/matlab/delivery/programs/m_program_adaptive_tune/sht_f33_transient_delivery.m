function out=sht_f33_transient_delivery(action,input,file,varargin)
% 独立瞬态Excel以SHA绑定稳态Excel，运行只需这两份Excel及公共运行资产。
% 不沿用稳态工作簿schema冒充组合模型；读者必须明确调用本接口。
switch lower(action)
    case 'fixed'
        % 静态读取组合合同，不构造设计点、不加载DLL。
        d=sht_f33_transient_delivery('inspect',[],file,varargin{:});
        h=zeros(159,1);h(59:71)=d.parameters.value;
        out=sht_f3_current_contract('fixedTransient',h,d.sha256);
    case 'runtimeassets'
        out=local_runtime_assets();
    case 'write'
        r=input;steadyName='steady_model.xlsx';
        target=fullfile(fileparts(file),steadyName);
        if isfile(target)
            assert(strcmpi(sht_tc27_file_identity(target),r.identity.steadySha256),'相邻稳态Excel身份不匹配。');
        else
            copyfile(r.options.steadyWorkbook,target);
        end
        meta=table("F33_TRANSIENT_EXCEL_V1",0,3,16,string(r.options.runTag), ...
            string(steadyName),string(r.identity.steadySha256),string(r.identityHash), ...
            'VariableNames',{'schema','model_mode','thermal_mode','state_count','run_id', ...
            'steady_workbook','steady_sha256','identification_identity'});
        meta.converged=r.converged;meta.stop_reason=string(r.stopReason);
        meta.uq_status="not_evaluated_for_transient_combination";
        if isfield(r.options,'businessIdentity')&&~isempty(fieldnames(r.options.businessIdentity))
            b=r.options.businessIdentity;
            keys={'engineId','sortieId','parentModelId','modelId','purpose'};
            columns={'engine_id','sortie_id','parent_model_id','model_id','purpose'};
            for j=1:numel(keys)
                meta.(columns{j})=string(b.(keys{j}));
            end
        end
        params=table(r.parameters.c_index,string(r.parameters.name),r.k, ...
            'VariableNames',{'c_index','parameter','value'});
        if isfile(file)
            old=sht_f33_transient_delivery('inspect',[],file);
            assert(isequaln(old.parameters,params)&&strcmp(old.metadata.identification_identity,meta.identification_identity), ...
                'F3:TransientDelivery:Overwrite','同名正式结果不同，必须更换批次。');
            out=file;return;
        end
        temp=[tempname(fileparts(file)),'.xlsx'];
        writetable(meta,temp,'Sheet','Model');writetable(params,temp,'Sheet','TransientParameters');
        restored=sht_f33_transient_delivery('inspect',[],temp);
        assert(isequal(restored.parameters.c_index,params.c_index)&&max(abs(restored.parameters.value-r.k))<1e-13);
        movefile(temp,file);out=file;
    case {'read','inspect'}
        [~,sheets]=xlsfinfo(file);
        if ismember('CombinedManifest',sheets)
            % 新源格式集中解释；旧F33双Excel分支保持原字节语义。
            assert(~isempty(varargin)&&isstruct(varargin{1})&& ...
                isfield(varargin{1},'priorRoute')&&isfield(varargin{1},'priorRuntimeBinding'), ...
                'F3:TransientDelivery:TC27Binding','TC27单Excel需显式路线和来源/执行关联配置。');
            o=varargin{1};o.priorSource='combined';o.priorWorkbook=file;
            parent=sht_f3_current_contract('parent',o);
            fixed=parent.schedule.fixedTransient;
            params=table(fixed.cIndex,string(fixed.name(:)),fixed.value, ...
                'VariableNames',{'c_index','parameter','value'});
            assets=[];
            if strcmpi(action,'read')
                assets=sht_f3_current_contract('assets',o);
                % 此源来自台架，飞参测量误差是另一组。原燃油曲线在source中
                % 完整保留；局部回放不能经steady.schedule再次套用台架偏置。
                parent.schedule.fuelBias=assets.steadySchedule.fuelBias;
            end
            out=struct('parameters',params,'metadata',parent.runtimeAssociation, ...
                'assets',assets,'steady',parent,'file',file,'steadyFile',file, ...
                'steadySha256',parent.runtimeAssociation.source.parentSteadySHA256, ...
                'sha256',parent.sha256,'fixedTransient',fixed,'internalResultMatRead',false, ...
                'sourceSchema',parent.runtimeAssociation.source.schema);return;
        end
        meta=readtable(file,'Sheet','Model');p=readtable(file,'Sheet','TransientParameters');
        % R2019b将Excel文本读为cell，统一成字典所用string再比较载荷。
        p.parameter=string(p.parameter);
        assert(height(meta)==1&&string(meta.schema)=="F33_TRANSIENT_EXCEL_V1"&& ...
            meta.model_mode==0&&meta.thermal_mode==3&&meta.state_count==16,'瞬态模型合同不匹配。');
        dict=sht_health_parameter_dictionary(0);d=dict(ismember(dict.c_index,58:70),:);
        assert(isequal(p.c_index,(58:70)')&&isequal(string(p.parameter),string(d.name))&& ...
            all(isfinite(p.value))&&all(p.value>-1),'瞬态系数字典或物理倍率无效。');
        leaf=char(string(meta.steady_workbook));
        [~,nm,ex]=fileparts(leaf);
        assert(strcmp(leaf,[nm ex]),'F3:TransientDelivery:Path','绑定父模型只能是相邻文件名。');
        steady=fullfile(fileparts(file),leaf);
        if ~isempty(varargin),steady=varargin{1};end
        assert(isfile(steady)&&strcmpi(sht_tc27_file_identity(steady),char(string(meta.steady_sha256))), ...
            'F3:TransientDelivery:SteadyIdentity','缺少绑定的稳态Excel或SHA不一致。');
        a=[];sha=sht_tc27_file_identity(file);
        h=zeros(159,1);h(59:71)=p.value;
        fixed=sht_f3_current_contract('fixedTransient',h,sha);
        if strcmpi(action,'read')
            a=local_runtime_assets();
            s=sht_f33_excel_delivery('read',steady,a);
            a.personalized.health=s.schedule.designHealth;a.personalized.health(59:71)=p.value;
            a.personalized.profile=s.profile;a.personalized.fuelBias=s.schedule.fuelBias;
            a.contract.fixedTransient=fixed;
            % 固定稳态参数及13项瞬态值不改变；来源身份不能冒充执行身份。
            a.contract.parentRuntimeAssociation=s.runtimeAssociation;
            a.steadySchedule=s.schedule;a.steadySchedule.designHealth(59:71)=p.value;
            a.steadySchedule.fixedTransient=fixed;
        else
            s=sht_f33_excel_delivery('inspect',steady);
        end
        out=struct('parameters',p,'metadata',meta,'assets',a,'steady',s,'file',file, ...
            'steadyFile',steady,'steadySha256',char(string(meta.steady_sha256)), ...
            'sha256',sha,'fixedTransient',fixed,'internalResultMatRead',false);
    otherwise,error('F3:TransientDelivery:Action','未知交付操作。');
end
end

function a=local_runtime_assets()
% 与已验证Excel-only消费者相同，只读公共运行包，不再加载台架先验。
p=sht_f3_three_component_assets('paths');cfg=sht_f3_three_component_assets('config');
cfg.engine.reynoldsCorrection=sht_f3_reynolds_reference(cfg,1);
names={'GTESS.dll','GTESS.h','Turboshaft-TS.mdl','HPC02.MAP','HPT02.MAP','LPT02.MAP'};
hashes=cellfun(@(n)sht_tc27_file_identity(fullfile(p.runtime,n)),names,'UniformOutput',false);
a=struct('modelMode',0,'programDirectory',fileparts(mfilename('fullpath')), ...
    'configuration',cfg,'runtimeDirectory',p.runtime,'paths',struct('visserAsset',p.visserAsset), ...
    'contract',struct('modelMode',0,'stateCount',16,'runtimeFiles',{names}, ...
    'runtimeHashes',{hashes},'runtimeVisserAssetSha256',sht_tc27_file_identity(p.visserAsset)));
a.personalized=struct('id','flight_transient_excel','description','Three-component Visser16 Excel model', ...
    'health',zeros(159,1),'profile',[],'scheduleEnabled',true,'fuelBias',[]);
end
