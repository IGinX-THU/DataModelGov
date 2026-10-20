function audit=sht_tc24_posterior_match(workbook,generation,execution)
% 参数身份与物理执行身份都须匹配。旧Excel缺证据不重签、不猜测。
posterior=sht_load_2p4_uq_delivery(workbook);
m=posterior.manifest;
assert(ismember('deterministic_workbook_sha256',m.Properties.VariableNames) && ...
    strcmpi(char(string(m.deterministic_workbook_sha256(1))),generation.fileSha256), ...
    'TC24:Prediction:PosteriorModelMismatch','后验不属于当前确定性模型Excel。');
try,assets=readtable(workbook,'Sheet','RuntimeAssets');
catch,error('TC24:Prediction:PosteriorRuntimeUnknown', ...
        '该历史后验Excel未交付实际运行资产，无法证明与本次执行包匹配；保留旧文件，可先运行确定性预测。');end
for k=1:numel(execution.artifacts)
    a=execution.artifacts(k);[~,n,e]=fileparts(a.file);
    rows=string(assets.kind)==string(a.kind) & string(assets.name)==string([n,e]);
    assert(nnz(rows)==1 && strcmpi(char(string(assets.sha256(rows))),a.sha256), ...
        'TC24:Prediction:PosteriorRuntimeMismatch','后验执行资产与当前%s不一致，不能传播。',[n,e]);
end
assert(height(assets)==numel(execution.artifacts),'TC24:Prediction:PosteriorRuntimeMismatch', ...
    '后验运行资产集合不同。');
audit=struct('matched',true,'posteriorRunId',posterior.runId, ...
    'generationIdentityRewritten',false,'runtimeVerified',true);
end
