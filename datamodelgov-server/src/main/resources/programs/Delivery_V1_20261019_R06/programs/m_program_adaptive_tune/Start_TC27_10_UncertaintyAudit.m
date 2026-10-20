function audit=Start_TC27_10_UncertaintyAudit(directory)
%START_TC27_10_UNCERTAINTYAUDIT 独立核验Excel、条件区间与本批运行身份。
if nargin<1,c=sht_tc27_uq_contract(sht_tc27_uq_c_options());directory=c.directory;end
a=load(fullfile(directory,'contract.mat'),'c');c=a.c;
a=load(fullfile(directory,'prediction_report.mat'),'report');report=a.report;
current=sht_tc27_file_identity(c.formalInputFile);
assert(strcmp(current,c.identity.delivery),'确定性正式输入在UQ执行中变化。');
nowContract=sht_tc27_uq_contract(c.options);
assert(strcmp(nowContract.contractHash,c.contractHash),'UQ输入、模型或推断实现已变化，需独立新合同。');
assert(c.modelMode==0&&c.thermalMode==3&&all(c.transientHealth==0));
assert(~c.truthRead&&~c.testUsedForFit&&~c.tc24PosteriorRead);
p=sht_tc27_paths();rows=table();
for name={'C','D'}
    method=name{1};if ~isfield(report,method),continue;end
    file=sht_tc27_uq_delivery_path(c,method);
    q=sht_tc27_uq_delivery('read',file);assert(~q.internalMatRead);
    manifestHash=string(q.manifest.value(string(q.manifest.key)=="contract_sha256"));
    assert(manifestHash==string(c.contractHash),'Excel并非当前UQ合同。');
    assert(size(q.theta,1)==c.parameterCount&&max(abs(sum(q.weights)-1))<1e-9);
    assert(all(q.theta>=c.lowerBound-1e-12&q.theta<=c.upperBound+1e-12,'all'));
    s=sht_steady_model_adapt_v2_common('m3nodestoschedule',q.contract,q.theta(:,1));
    x=sht_steady_model_adapt_v2_common('m3scheduletonodes',q.contract,s);
    assert(max(abs(x-q.theta(:,1)))<1e-12,'UQ Excel不能独立恢复调度。');
    sumTable=report.(method).summary;health=c.parameterTable.c_index>=0;fuel=~health;
    e=sumTable.posterior_mean-sumTable.truth;
    [distinct,~,group]=unique(q.theta.','rows');groupWeights=accumarray(group,q.weights);
    sampleCount=size(q.theta,2);weightESS=1/sum(q.weights.^2);
    if method=='C'&&isfield(q,'nuisanceSamples')
        original=load(fullfile(directory,'method_C.mat'),'C');
        sampleCount=size(original.C.theta,2);weightESS=original.C.effectiveSampleSize;
    end
    rows=[rows;table(string(method),sampleCount,weightESS, ...
        size(distinct,1),1/sum(groupWeights.^2), ...
        sqrt(mean(e(health).^2)),1000*sqrt(mean(e(fuel).^2)), ...
        nnz(sumTable.truthCovered(health)),nnz(health),nnz(sumTable.truthCovered(fuel)),nnz(fuel), ...
        string(report.(method).quality),'VariableNames',{'method','sampleCount','weightESS', ...
        'distinctSampleCount','distinctSupportWeightESS', ...
        'healthNodeRMSE','fuelNodeRMSE_g_s','healthCovered','healthCount','fuelCovered','fuelCount','quality'})]; %#ok<AGROW>
end
audit=struct('passed',true,'contractHash',c.contractHash,'comparison',rows, ...
    'upstreamExcelUnchanged',true,'statisticalCalibrationConfirmed',false, ...
    'notes',{{'稳态C后端由合同选择；联合C代理校正。两者仍含附加参数局部边缘化近似。', ...
    'D为局部二次近似；不以可导出Excel代替全局或统计校准。', ...
    '输出区间条件于测得的测试输入，未传播测试输入误差与模型结构误差。'}});
writetable(rows,fullfile(c.report,'C_D_accuracy_and_coverage.csv'));
save(fullfile(directory,'audit.mat'),'audit','-v7.3');disp(rows);
end
