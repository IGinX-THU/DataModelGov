function output=sht_tc27_transient_delivery(action,input,file)
%SHT_TC27_TRANSIENT_DELIVERY 三部件瞬态参数的正式Excel读写，不依赖辨识MAT。
% 13个参数中未释放者仍以零值交付；是否数值收敛不作为读取门槛。
% 临时工作簿完整读回后才发布，重复发布相同载荷保持原文件及其哈希。
if strcmp(action,'write')
    local_check(input.parameters,input.manifest);
    if isfile(file)
        try
            old=sht_tc27_transient_delivery('read',[],file);
            if local_same(old,input),output=old;return;end
        catch failure
            warning('TC27:TransientDelivery:Rebuild','已有Excel读回失败，将重新完整写入：%s',failure.message);
        end
    end
    temporary=[tempname(fileparts(file)),'.xlsx'];
    writetable(input.parameters,temporary,'Sheet','TransientCorrections');
    writetable(input.manifest,temporary,'Sheet','Manifest');
    output=sht_tc27_transient_delivery('read',[],temporary);
    assert(local_same(output,input),'瞬态参数Excel写入读回不一致，未发布。');
    movefile(temporary,file,'f');output.file=file;
    return;
end
assert(strcmp(action,'read'),'未知瞬态交付操作。');
parameters=readtable(file,'Sheet','TransientCorrections');
manifest=readtable(file,'Sheet','Manifest');local_check(parameters,manifest);
output=struct('parameters',parameters,'manifest',manifest,'file',file, ...
    'sha256',sht_tc27_file_identity(file),'internalMatRead',false);
end

function local_check(p,m)
expected=["K_Jg";"K_Jp";"K_tau_HPC";"K_tau_Burner";"K_tau_GT";"K_tau_PT"; ...
    "K_gapW_HPC";"K_gapEta_HPC";"K_gapEta_GT";"K_gapEta_PT"; ...
    "K_diskTau_HPC";"K_diskTau_GT";"K_diskTau_PT"];
assert(isequal(p.Properties.VariableNames,{'hIndex','parameter','value'}), ...
    '瞬态Excel参数表只允许索引、名称和估计值。');
assert(height(p)==13&&isequal(p.hIndex,(58:70).')&&isequal(string(p.parameter),expected), ...
    '瞬态Excel不符合三部件h58:h70字典。');
assert(all(isfinite(p.value))&&all(p.value> -1),'瞬态修正系数不满足有限值及正物理倍率。');
assert(height(m)==1&&m.model_mode==0&&m.thermal_mode==3, ...
    '瞬态Excel只适用于本轮三部件Visser模型。');
assert(strlength(string(m.steady_workbook))>0&& ...
    ~isempty(regexp(char(string(m.steady_sha256)),'^[A-Fa-f0-9]{64}$','once')), ...
    '瞬态Excel缺少所固定的稳态工作簿身份。');
end

function same=local_same(a,b)
same=isequal(a.parameters.hIndex,b.parameters.hIndex)&& ...
    isequal(string(a.parameters.parameter),string(b.parameters.parameter))&& ...
    all(abs(a.parameters.value-b.parameters.value)<1e-14)&& ...
    isequal(string(a.manifest.run_id),string(b.manifest.run_id))&& ...
    isequal(a.manifest.model_mode,b.manifest.model_mode)&& ...
    isequal(a.manifest.thermal_mode,b.manifest.thermal_mode)&& ...
    isequal(string(a.manifest.steady_workbook),string(b.manifest.steady_workbook))&& ...
    isequal(string(a.manifest.steady_sha256),string(b.manifest.steady_sha256));
end
