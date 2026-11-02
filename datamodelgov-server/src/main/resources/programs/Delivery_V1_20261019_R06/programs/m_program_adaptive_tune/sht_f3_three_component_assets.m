function out=sht_f3_three_component_assets(action,varargin)
% 第3阶段三部件运行资产。上游只读，正式交付按指定身份选择，禁止按日期猜选。
% 本函数不写TC24/TC27目录，不使用StartupStop，也不修改原六部件资产。
p=fileparts(mfilename('fullpath'));
middle=fullfile(p,'MiddleData','three_component');
a=struct('schemaVersion','F3_THREE_COMPONENT_ASSETS_R010','modelMode',0, ...
    'integrationStep_s',.025,'recordStep_s',.1,'stateCount',16, ...
    'thermalMode',3,'thermalHealthNumbers',(58:70).', ...
    'middle',fullfile(middle,'flight_stage3'), ...
    'data',fullfile(p,'TestData','three_component','flight_stage3'), ...
    'report',fullfile(fileparts(p),'report_outputs','three_component','T3V1_R011'));
a.runtime=fullfile(a.middle,'F3_1B_R011','runtime');
a.generation=fullfile(a.middle,'F3_2_R011');
a.data=fullfile(a.data,'F3_2_R011');
tc24=fullfile(middle,'steady_model_2p4_delivery');tc27=fullfile(middle,'tc27');
a.steadyWorkbook=fullfile(tc24,'2p4_deterministic_steady.xlsx');
a.instantWorkbook=fullfile(tc24,'2p4_deterministic_transient_instant.xlsx');
a.tc24Posterior=fullfile(tc24,'uq', ...
    'tc24_c_R2019b_20260912_final_pointwise_v4', ...
    '2p4_uq_method_c_transient_instant_b3df199c9595.xlsx');
a.tc27Workbook=fullfile(tc27,'tc27_deterministic_transient_instant_II.xlsx');
a.tc27Transient=fullfile(tc27,'tc27_transient_transient_instant_II.xlsx');
a.tc27PosteriorC=fullfile(tc27,'tc27_uq_C_transient_instant_II_steady_points_R015.xlsx');
a.tc27PosteriorD=fullfile(tc27,'tc27_uq_D_transient_instant_II_steady_points_R015.xlsx');
a.sourceRuntime=fullfile(middle,'tc27_runtime');
a.candidateRuntime=fullfile(a.middle,'F3_1A_R010','runtime_after02');
a.sourceVisser=fullfile(tc27,'tc27_visser16_parameters.mat');
a.sourceKurzke=fullfile(tc27,'tc27_kurzke15_parameters.mat');
a.legacyRuntime=a.runtime;a.legacyData=a.data;
a.buildRoot=fullfile(a.middle,'F3_DLL_MAIN_20261010');
a.packageId='F3_R036_LEGACY';a.manifestName='f3_runtime_manifest_R036.json';
a.manifestSHA256='2977A31DDCB0E16B4F2AEE9DC2CD44D7BA46F7944F20995C0764E97697710CB3';
a.legacyBuilderExecutionSHA256='687C8C8F535E22C950B1788A6248F76B472CBD40EB249BC862F77A3CCCF87944';
a=local_selection(a,p);
a.manifestFile=fullfile(a.runtime,a.manifestName);
a.visserAsset=fullfile(a.runtime,'f3_visser16_parameters.mat');
a.kurzkeAsset=fullfile(a.runtime,'f3_kurzke15_parameters.mat');
switch lower(action)
    case 'paths'
        out=a;
    case 'manifest'
        directory=a.runtime;if ~isempty(varargin),directory=varargin{1};end
        out=local_manifest(directory,a);
    case 'association'
        % 结果来源与实际执行分别记录。只允许清单声明且已验证的精确迁移，
        % 不扩大模型白名单，不用于续算检查点或旧似然缓存。
        directory=a.runtime;if numel(varargin)>2,directory=varargin{3};end
        out=local_association(varargin{1},varargin{2},directory,a);
    case 'verify'
        fields={'steadyWorkbook','instantWorkbook','tc24Posterior','tc27Workbook', ...
            'tc27Transient','tc27PosteriorC','tc27PosteriorD'};
        expected={'F31A98AAD0193683371E633EB15B854F35C00520472D154D54881D805D7AA7DC', ...
            '5F2EAAF8CC56AADF4D9E82FE2BA15D11F09798B57396D7534A4CB70B404C9634', ...
            'ec1f4b2c50d5fe3ac1ba17acdddc4408c86b28320d63fa0c50a0b4b554e97bdd', ...
            'CD5BFF02006294D3EE92F29B95F4DB5D30C44C0498A450AE52C3D89FDCD32663', ...
            '1999B0DB79F05A816FEB46DD8AF5DC37E1A9621766CE74CA9A7288C43C77CB80', ...
            '7C37E1BB75E114CFC871650DCFF9D3633C9EE140962E7EA1ECEB35700D38E78E', ...
            '9B3A2EF935C8403A67DCCD3A1AA42266C868323169A2918C5D2C22C7632E3D9D'};
        % 完整资产审计仍可显式执行；正式消费者只核验所选来源。
        % 未选中的TC27更新不得阻断TC24飞行辨识，反之亦然。
        selected=~isempty(varargin);
        if selected
            source=lower(char(varargin{1}));route='transient_instant';
            if numel(varargin)>1,route=char(varargin{2});end
            local_source_route(source,route);
            if strcmp(source,'tc24')
                index=[2,3];if strcmp(route,'steady'),index=[1,3];end
            else
                index=[4,6];
            end
            fields=fields(index);expected=expected(index);
        end
        files=cell(numel(fields),1);hashes=files;
        for k=1:numel(fields)
            files{k}=a.(fields{k});hashes{k}=local_hash(files{k});
            assert(strcmpi(hashes{k},expected{k}), ...
                'SHT:F3:UpstreamChanged','指定上游文件与MAIN身份不符：%s',files{k});
        end
        if ~selected
            dll=fullfile(a.sourceRuntime,'GTESS.dll');
            assert(strcmpi(local_hash(dll), ...
                '67938ED62A7376FF2527A7A6BBB7C366034C070735AF1A9EF214DD20373A2A46'), ...
                'SHT:F3:RuntimeChanged','TC27计算DLL身份改变，必须重新核对接口。');
        end
        out=table(string(fields(:)),string(files),string(hashes), ...
            'VariableNames',{'role','file','sha256'});
    case 'verifyruntime'
        % 正式包按随包不可变清单核验；历史候选仅作审计来源，不参与运行。
        % 清单本身也固定SHA，不能通过改写清单接纳已改变的物理资产。
        release=local_manifest(a.runtime,a);manifest=release.manifest;
        names={'GTESS.dll','GTESS.h','blockAndFunctions.h','types_TMATS.H', ...
            'Turboshaft-TS.mdl','HPC02.MAP','HPT02.MAP','LPT02.MAP', ...
            'f3_visser16_parameters.mat','f3_kurzke15_parameters.mat'};
        assert(strcmp(manifest.schemaVersion,'F3_RUNTIME_RELEASE_MANIFEST_V1')&& ...
            manifest.modelMode==0&&isequal({manifest.files.file},names), ...
            'SHT:F3:ManifestSchema','正式运行包清单结构或资产集合不匹配。');
        for k=1:numel(names)
            assert(strcmpi(local_hash(fullfile(a.runtime,names{k})), ...
                manifest.files(k).sha256), ...
                'SHT:F3:RuntimeCollision','本分支运行资产与冻结清单不一致：%s',names{k});
        end
        for file={a.kurzkeAsset,a.visserAsset}
            saved=load(file{1},'parameterAsset');asset=saved.parameterAsset;
            assert(asset.interface.interfaceVersion==2502&& ...
                strcmp(asset.flightBuild.identity.variant,'nominal'), ...
                'SHT:F3:ThermalTopology','不是三部件标称热参考。');
            id=asset.flightBuild.identity;
            for name={'GTESS.dll','GTESS.h','Turboshaft-TS.mdl','HPC02.MAP','HPT02.MAP','LPT02.MAP'}
                assert(strcmpi(id.runtime.(matlab.lang.makeValidName(name{1})), ...
                    local_hash(fullfile(a.runtime,name{1}))), ...
                    'SHT:F3:ThermalCache','热参考的运行模型身份改变。');
            end
            code=fieldnames(id.code);
            for k=1:numel(code)
                actualCodeHash=local_hash(fullfile(p,[code{k} '.m']));
                sourceMatches=strcmpi(id.code.(code{k}),actualCodeHash);
                % MAIN_DLLERR_R001只调整错误报告及热求解异常衔接，正常路径不变。
                % 仅允许已回归的精确指纹对消费旧热参考；不改签资产，
                % 也不用于SMC/辨识检查点或似然缓存的源码身份校验。
                if strcmp(code{k},'sht_engine_derivative')
                    sourceMatches=sourceMatches || ( ...
                        strcmpi(id.code.(code{k}), ...
                        '5BC9BFD212705B884D4D55DB69DDD513E0BCA5F17B4089DEA5D73A43386E3788') && ...
                        strcmpi(actualCodeHash, ...
                        'E04388551AE72833B92F93BA995929F7BC407F157BFEC83D1A02B264100E6D63'));
                elseif strcmp(code{k},'sht_thermal_equilibrium_solve')
                    sourceMatches=sourceMatches || ( ...
                        strcmpi(id.code.(code{k}), ...
                        '1D61B008EA19D97ABCC173433D25656B0E55B60AFD2424C88534E21DCF220415') && ...
                        strcmpi(actualCodeHash, ...
                        '8F6EECED0C0FAE2C5756995CC1FAC4B1DC6CD7EF2165EBE4411C515B509611CE'));
                elseif strcmp(code{k},'sht_f3_thermal_asset')&&strcmp(a.packageId,'F3_R036_LEGACY')
                    % 旧表仍属于原生成源码；本批仅重构构建/路径接线。
                    % 精确新指纹由有限旧包回归选择文件固定，不给旧资产改签。
                    sourceMatches=sourceMatches || ( ...
                        strcmpi(id.code.(code{k}), ...
                        'BEB32A514F101758A1F96F9E328979CCC21B132B318A87507B7A4351443A2EA0')&& ...
                        ~isempty(a.legacyBuilderExecutionSHA256)&& ...
                        strcmpi(actualCodeHash,a.legacyBuilderExecutionSHA256));
                end
                assert(sourceMatches, ...
                    'SHT:F3:ThermalCache','热参考依赖源码改变：%s',code{k});
            end
        end
        out=a;
    case 'prepare'
        % 仅首次历史物化仍需来源；部署必须直接携带已核验的完整正式包。
        if isfile(a.kurzkeAsset)&&isfile(a.visserAsset)
            out=sht_f3_three_component_assets('verifyruntime');
            return;
        end
        assert(strcmp(a.packageId,'F3_R036_LEGACY'),'SHT:F3:NewRuntimeMissing', ...
            '新包须先完成真实热参考构建及清单发布，不从历史候选目录补齐。');
        upstream=sht_f3_three_component_assets('verify');
        for folder={a.middle,a.data,a.report,a.runtime}
            if ~isfolder(folder{1}),mkdir(folder{1});end
        end
        assert(strcmpi(local_hash(fullfile(a.candidateRuntime,'GTESS.dll')), ...
            '51580CB9B1FED35C51F385F88974756E9FCF0A822977CA6A0ABDB8489AF98086'), ...
            'SHT:F3:CandidateChanged','F3-1A候选DLL身份不符。');
        names={'GTESS.dll','GTESS.h','blockAndFunctions.h','types_TMATS.H', ...
            'Turboshaft-TS.mdl','HPC02.MAP','HPT02.MAP','LPT02.MAP'};
        records=table();
        for k=1:numel(names)
            source=fullfile(a.candidateRuntime,names{k});target=fullfile(a.runtime,names{k});
            records=[records;local_copy_exact(source,target)]; %#ok<AGROW>
        end
        % 标称热数值来源保留，参考平衡按新DLL重新计算，不修改旧资产身份。
        for mode=[1,3]
            source=a.sourceKurzke;target=a.kurzkeAsset;
            if mode==3,source=a.sourceVisser;target=a.visserAsset;end
            sht_f3_thermal_asset('nominal',source,target,a);
        end
        writetable(records,fullfile(a.report,'R011_runtime_asset_manifest.csv'));
        writetable(upstream,fullfile(a.report,'R011_upstream_excel_manifest.csv'));
        out=a;
    case 'config'
        % 配置必须使用已经通过身份核验的独立副本；不调用会写TC27的配置入口。
        mode=3;stage='joint_full';
        if ~isempty(varargin),mode=varargin{1};end
        if numel(varargin)>1,stage=varargin{2};end
        assert(ismember(mode,[0,1,3]),'SHT:F3:ThermalMode','热模式只支持0、1、3。');
        if numel(varargin)>3
            % 仅新热参考构建使用：完整物理八文件先核验，再生成普通两状态配置。
            assert(mode==0,'SHT:F3:BuildConfig','构建配置不能消费尚未生成的热参考。');
            a=varargin{4};local_builder_runtime(a);
        else
            sht_f3_three_component_assets('verifyruntime');
        end
        cfg=sht_default_config(struct('engine',struct('modelMode',0,'runtimeDirectory',a.runtime), ...
            'plot',struct('enable',false)));
        cfg.engine.interface.controlDir=a.runtime;
        cfg.engine.modelConfiguration=fullfile(a.runtime,'Turboshaft-TS.mdl');
        cfg.Tsim=.025;cfg.Tctrl=.025;
        if mode~=0
            file=a.visserAsset;if mode==1,file=a.kurzkeAsset;end
            if numel(varargin)>2,file=varargin{3};end
            [cfg,asset]=sht_configure_transient_heat_state(cfg,file);
            cfg.engine.transientEffects.stepInTemplate= ...
                sht_build_transient_step_in_template(asset,stage,15);
            if any(cfg.engine.transientEffects.stepInTemplate(346:347))
                % 延续TC27经验证的PT参考表连续边界，不冻结金属温度。
                asset.referenceTable.PT.extrapolationPolicy='continuous_hull_projection';
                cfg.engine.transientEffects.clearanceReferenceTable= ...
                    sht_prepare_clearance_reference_lookup(asset.referenceTable);
            end
        end
        cfg.engine.boundary.health=zeros(159,1);
        cfg.engine.boundary.healthScheduleEnabled=false;cfg.engine.healthScheduleProfile=[];
        cfg.engine.boundary.Mkg=0;cfg.engine.boundary.hpsPower=0;
        cfg.engine.boundary.ptLoadInputMode='torque';cfg.engine.boundary.gtLoadInputMode='torque';
        out=sht_validate_runtime_config(cfg);
    case 'upstream'
        % 两个来源分别恢复其正式Excel；台架燃油曲线仅留在来源审计中。
        source='tc24';route='transient_instant';
        if ~isempty(varargin),source=lower(char(varargin{1}));end
        if numel(varargin)>1,route=char(varargin{2});end
        local_source_route(source,route);
        selectedVerification=sht_f3_three_component_assets('verify',source,route);
        if strcmp(source,'tc24')
            file=a.instantWorkbook;if strcmp(route,'steady'),file=a.steadyWorkbook;end
            d=sht_load_2p4_deterministic_delivery(route,file,'formal');
            out=struct('source',source,'route',route,'delivery',d, ...
                'posteriorFile',a.tc24Posterior,'posteriorRoute','transient_instant', ...
                'posteriorMatched',strcmp(route,'transient_instant'));
        elseif strcmp(source,'tc27')
            assert(strcmp(route,'transient_instant'),'SHT:F3:SourceRoute', ...
                '当前指定TC27正式来源仅为transient_instant/II。');
            d=sht_tc27_delivery('read',[],a.tc27Workbook);
            out=struct('source',source,'route',route,'delivery',d, ...
                'posteriorFile',a.tc27PosteriorC,'posteriorRoute',route,'posteriorMatched',true);
        else
            error('SHT:F3:Source','来源须为tc24或tc27，不按时间自动选择。');
        end
        out.flightFuelPrior='independent_zero_centered';
        out.thermalIndividualHealth=zeros(13,1);
        out.selectedUpstreamVerification=selectedVerification;
    otherwise
        error('SHT:F3:AssetAction','未知资产操作：%s',action);
end
end

function a=local_selection(a,p)
% 正式选择文件可随离线包一起搬迁；测试覆盖必须显式给出独立文件。
file=fullfile(p,'TestData','three_component','flight_stage3','f3_runtime_selection.json');
override=getenv('SHT_F3_RUNTIME_SELECTION_FILE');
if ~isempty(override),file=override;assert(isfile(file),'SHT:F3:SelectionMissing','所选配置不存在：%s',file);end
a.selectionFile=file;
if ~isfile(file),return;end
s=jsondecode(fileread(file));
assert(isstruct(s)&&isscalar(s)&&all(isfield(s, ...
    {'schemaVersion','packageId','runtimeRelativePath','manifestName','manifestSHA256'}))&& ...
    strcmp(s.schemaVersion,'F3_RUNTIME_SELECTION_V1')&& ...
    ismember(s.packageId,{'F3_R036_LEGACY','F3_DLL_MAIN_20261010'}), ...
    'SHT:F3:SelectionSchema','运行包选择合同不匹配。');
relative=strrep(char(s.runtimeRelativePath),'\','/');
assert(isempty(regexp(relative,'(^/|^[A-Za-z]:|(^|/)\.\.(/|$))','once')), ...
    'SHT:F3:SelectionPath','运行目录必须为tune内的相对路径，不能越界。');
assert(ismember(s.manifestName,{'f3_runtime_manifest_R036.json','f3_runtime_manifest.json'})&& ...
    ~isempty(regexp(s.manifestSHA256,'^[A-Fa-f0-9]{64}$','once')), ...
    'SHT:F3:SelectionSchema','清单文件名/SHA无效。');
a.runtime=fullfile(p,strrep(relative,'/',filesep));
a.packageId=s.packageId;a.manifestName=s.manifestName;a.manifestSHA256=s.manifestSHA256;
if isfield(s,'legacyBuilderExecutionSHA256')
    assert(strcmpi(s.legacyBuilderExecutionSHA256,a.legacyBuilderExecutionSHA256), ...
        'SHT:F3:SelectionSchema','旧包构建器消费指纹无效。');
end
if strcmp(a.packageId,'F3_DLL_MAIN_20261010')
    a.generation=fullfile(a.buildRoot,'generation');
    a.data=fullfile(p,'TestData','three_component','flight_stage3','F3_DLL_MAIN_20261010');
    a.report=fullfile(fileparts(p),'report_outputs','three_component','F3_DLL_MAIN_20261010');
end
end

function out=local_manifest(directory,a)
legacy=fullfile(directory,'f3_runtime_manifest_R036.json');
if isfile(legacy)
    file=legacy;expected='2977A31DDCB0E16B4F2AEE9DC2CD44D7BA46F7944F20995C0764E97697710CB3';
else
    file=fullfile(directory,'f3_runtime_manifest.json');
    assert(strcmp(a.packageId,'F3_DLL_MAIN_20261010'),'SHT:F3:ManifestSelection', ...
        '读取新包必须显式选择其不可变清单。');expected=a.manifestSHA256;
end
actual=local_hash(file);
assert(strcmpi(actual,expected),'SHT:F3:ManifestChanged', ...
    '运行包清单缺失或SHA改变：%s。不能覆盖原预期身份。',file);
m=jsondecode(fileread(file));
assert(strcmp(m.schemaVersion,'F3_RUNTIME_RELEASE_MANIFEST_V1')&&m.modelMode==0, ...
    'SHT:F3:ManifestSchema','三部件运行清单合同不匹配。');
for j=1:numel(m.files)
    name=m.files(j).file;
    [~,stem,ext]=fileparts(name);
    assert(strcmp(name,[stem,ext])&& ...
        strcmpi(local_hash(fullfile(directory,name)),m.files(j).sha256), ...
        'SHT:F3:RuntimeCollision','运行文件不符：%s。',name);
end
if ~isfile(legacy)
    assert(strcmpi(m.files(1).sha256, ...
        '86B6856A47A1AB81B9D8A87F8D8989F7AF4FA17B560A0C1C66B3D558CB4B46C2')&& ...
        strcmpi(m.files(2).sha256, ...
        'B69DE8E7789008124642DB58B792685378E563A6832ED43B49A73CD197970847'), ...
        'SHT:F3:MainDllIdentity','新版主DLL及配套头文件身份不符。');
end
out=struct('file',file,'sha256',actual,'manifest',m,'runtime',directory);
end

function local_builder_runtime(a)
% 构建前没有热清单，但物理包不是无身份候选：沿已冻结旧模型逐文件核对。
legacy=fullfile(a.thermalSourceRuntime,'f3_runtime_manifest_R036.json');
assert(strcmpi(local_hash(legacy), ...
    '2977A31DDCB0E16B4F2AEE9DC2CD44D7BA46F7944F20995C0764E97697710CB3'), ...
    'SHT:F3:BuildSource','构建来源包清单不符。');
m=jsondecode(fileread(legacy));
for j=1:8
    expected=m.files(j).sha256;
    if j==1,expected='86B6856A47A1AB81B9D8A87F8D8989F7AF4FA17B560A0C1C66B3D558CB4B46C2';end
    if j==2,expected='B69DE8E7789008124642DB58B792685378E563A6832ED43B49A73CD197970847';end
    assert(strcmpi(local_hash(fullfile(a.runtime,m.files(j).file)),expected), ...
        'SHT:F3:BuildRuntime','构建物理文件不符：%s',m.files(j).file);
end
end

function out=local_association(names,hashes,directory,a)
names=cellstr(string(names(:)));hashes=cellstr(string(hashes(:)));
assert(numel(names)==numel(hashes)&&numel(unique(names))==numel(names), ...
    'SHT:F3:RuntimeAssociation','来源资产名/哈希维数或重复项不合法。');
release=local_manifest(directory,a);m=release.manifest;
mapped=names;mapped(strcmp(mapped,'VisserAsset'))={'f3_visser16_parameters.mat'};
target=cell(size(mapped));same=true;
for j=1:numel(mapped)
    index=find(strcmp({m.files.file},mapped{j}),1);
    assert(~isempty(index),'SHT:F3:RuntimeAssociation','未声明的资产：%s',mapped{j});
    target{j}=m.files(index).sha256;same=same&&strcmpi(target{j},hashes{j});
end
status='same_runtime_identity';sourceManifest=release.sha256;
if ~same
    assert(isfield(m,'compatibility')&& ...
        strcmpi(m.compatibility.sourceManifestSHA256, ...
        '2977A31DDCB0E16B4F2AEE9DC2CD44D7BA46F7944F20995C0764E97697710CB3'), ...
        'SHT:F3:RuntimeAssociation','来源不是所选包或已验证的明确迁移来源。');
    old=m.compatibility.sourceFiles;
    for j=1:numel(mapped)
        index=find(strcmp({old.file},mapped{j}),1);
        assert(~isempty(index)&&strcmpi(old(index).sha256,hashes{j}), ...
            'SHT:F3:RuntimeAssociation','来源资产%s不能与当前包混拼。',mapped{j});
    end
    status='authorized_legacy_parameter_execution';sourceManifest=m.compatibility.sourceManifestSHA256;
end
out=struct('status',status,'sourceManifestSHA256',sourceManifest, ...
    'executionManifestSHA256',release.sha256,'runtimeFiles',{names}, ...
    'sourceHashes',{hashes},'executionHashes',{target}, ...
    'oldPosteriorRecomputed',false,'checkpointCompatibilityGranted',false);
end

function local_source_route(source,route)
assert(ismember(source,{'tc24','tc27'}),'SHT:F3:Source', ...
    '来源须为tc24或tc27，不按时间自动选择。');
assert(ismember(route,{'steady','transient_instant'}),'SHT:F3:SourceRoute', ...
    '来源路径须明确为steady或transient_instant。');
assert(~strcmp(source,'tc27')||strcmp(route,'transient_instant'), ...
    'SHT:F3:SourceRoute','当前指定TC27正式来源仅为transient_instant/II。');
end

function row=local_copy_exact(source,target)
sha=local_hash(source);
if isfile(target)
    assert(strcmpi(sha,local_hash(target)),'SHT:F3:RuntimeCollision', ...
        '运行副本已存在且身份不同，禁止静默覆盖：%s',target);
else
    copyfile(source,target);
    assert(strcmpi(sha,local_hash(target)),'SHT:F3:CopyMismatch','资产复制校验失败。');
end
row=table(string(source),string(target),string(sha),'VariableNames',{'source','target','sha256'});
end

function hash=local_hash(file)
assert(isfile(file),'SHT:F3:AssetMissing','缺少指定资产：%s',file);
fid=fopen(file,'rb');assert(fid>=0);cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
md=java.security.MessageDigest.getInstance('SHA-256');
while ~feof(fid)
    bytes=fread(fid,1048576,'*uint8');md.update(typecast(bytes,'int8'));
end
hash=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end
