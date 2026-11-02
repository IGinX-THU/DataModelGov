function file=sht_repackage_2p4_uq_excel(original,contract)
%SHT_REPACKAGE_2P4_UQ_EXCEL 修订Excel说明列，保留原后验与不可变工作簿。
% 本函数不回放、不重采样；只用已冻结合同恢复确定性参考列及其来源。
before=sht_load_2p4_uq_delivery(original);
assert(strcmp(string(before.manifest.uq_contract_sha256),contract.contractHash) && ...
    isequal(string(before.parameterTable.name),string(contract.parameterTable.name)), ...
    'SHT:UQDelivery:RepackageContractMismatch','只能按原后验的冻结合同修订说明。');
root=fileparts(mfilename('fullpath'));
folder=fullfile(root,'MiddleData','steady_model_2p4_delivery','uq', ...
    [before.runId '__excel_metadata_v2']);
[~,name,ext]=fileparts(original); file=fullfile(folder,[name ext]);
if isfile(file)
    after=sht_load_2p4_uq_delivery(file);
    assert(isequal(after.theta,before.theta) && isequal(after.weights,before.weights));
    return;
end
if ~isfolder(folder), mkdir(folder); end
target=file;
file=[tempname(folder) '.xlsx'];
copyfile(original,file);
p=before.parameterTable;
if isfield(contract,'deterministicEstimate') && ...
        numel(contract.deterministicEstimate)==height(p)
    p.deterministicEstimate=contract.deterministicEstimate(:);
else
    p.deterministicEstimate=contract.parameterTable.point_estimate;
end
m=before.manifest;
m.deterministic_reference_semantics="frozen_estimate_not_prior_center";
m.deterministic_run_id=string(contract.deterministicRunId);
m.excel_metadata_revision="v2_20260906";
m.posterior_recomputed=false;
writetable(p,file,'Sheet','ParameterSummary');
writetable(m,file,'Sheet','Manifest');
after=sht_load_2p4_uq_delivery(file);
assert(isequal(after.theta,before.theta) && isequal(after.weights,before.weights) && ...
    max(abs(after.parameterTable.deterministicEstimate-p.deterministicEstimate))<1e-12, ...
    'SHT:UQDelivery:RepackageChangedPosterior','说明修订不得改变后验样本或权重。');
movefile(file,target); file=target;
fid=fopen(file,'rb'); cleanup=onCleanup(@() fclose(fid)); bytes=fread(fid,Inf,'*uint8'); clear cleanup;
digest=java.security.MessageDigest.getInstance('SHA-256'); digest.update(bytes);
hash=lower(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
fid=fopen([file '.sha256'],'w'); fprintf(fid,'%s  %s%s\n',hash,name,ext); fclose(fid);
end
