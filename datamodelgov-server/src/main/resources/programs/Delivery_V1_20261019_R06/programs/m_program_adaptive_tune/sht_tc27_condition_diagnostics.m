function d=sht_tc27_condition_diagnostics(A,method,regularizationWeight,priorPrecision,retainedCount)
%SHT_TC27_CONDITION_DIAGNOSTICS 区分完整参数空间与实际TSVD保留子空间。
% A为数据残差Jacobian按参数工程尺度缩放后的矩阵，不代表概率白化。
% retainedCount由求解器传入实际接受步的维数；旧结果缺失时传NaN，
% 不得用初始配置冒充实际值。该函数只生成诊断，不参与参数更新。
% regularizationWeight是实际lambda^2，直接沿用原值，避免开方再平方。
singular=svd(A,'econ');n=size(A,2);
if isempty(singular),tolerance=0;else,tolerance=max(size(A))*eps(max(singular));end
dataRank=nnz(singular>tolerance);
fullJacobian=Inf;
if dataRank==n&&n>0,fullJacobian=singular(1)/singular(n);end
d=struct('schema','TC27_condition_v2','coordinateSystem','residual_Jacobian_times_parameter_scale', ...
    'parameterCount',n,'residualCount',size(A,1),'dataNumericalRank',dataRank, ...
    'singularValueTolerance',tolerance,'singularValues',singular, ...
    'fullDataJacobianCondition',fullJacobian,'fullDataInformationCondition',fullJacobian^2, ...
    'fullParameterSpaceDataRankDeficient',dataRank<n, ...
    'tsvdRequestedDiagnosticCount',retainedCount,'tsvdEffectiveRetainedCount',NaN, ...
    'tsvdRetainedJacobianCondition',NaN,'tsvdRetainedInformationCondition',NaN, ...
    'retainedCountClippedByFinalRank',false,'status','tikhonov_full_parameter_space');
if strcmp(method,'tsvd')
    d.regularizedConditionSpace='tsvd_retained_subspace';
    if dataRank==0
        effective=0;condition=Inf;d.status='zero_rank_no_retained_direction';
    elseif isnan(retainedCount)
        effective=NaN;condition=NaN;d.status='actual_retained_dimension_unknown';
    else
        assert(isscalar(retainedCount)&&isfinite(retainedCount)&&retainedCount>=0&& ...
            retainedCount==floor(retainedCount),'TC27:Condition:Rank','保留维数必须是非负整数或NaN。');
        effective=min(retainedCount,dataRank);condition=Inf;
        d.retainedCountClippedByFinalRank=effective<retainedCount;
        if effective>0
            condition=singular(1)/singular(effective);d.status='retained_subspace_only';
        else
            d.status='no_retained_direction';
        end
    end
    d.tsvdEffectiveRetainedCount=effective;
    d.tsvdRetainedJacobianCondition=condition;
    d.tsvdRetainedInformationCondition=condition^2;
    d.regularizedJacobianCondition=condition;
    d.regularizedInformationCondition=condition^2;
else
    % 保持原Tikhonov信息矩阵口径；不把数值信赖域mu计入物理先验。
    d.regularizedConditionSpace='tikhonov_full_parameter_space';
    d.regularizedInformationCondition=cond(A.'*A+regularizationWeight*priorPrecision);
    d.regularizedJacobianCondition=sqrt(d.regularizedInformationCondition);
end
% 一行表随solve/audit保存，命令行和汇总使用同一组有明确含义的列。
d.summary=table(string(method),n,dataRank,d.tsvdEffectiveRetainedCount, ...
    d.fullDataJacobianCondition,d.fullDataInformationCondition, ...
    d.regularizedJacobianCondition,d.regularizedInformationCondition, ...
    string(d.regularizedConditionSpace),string(d.status),'VariableNames', ...
    {'method','parameterCount','dataRank','effectiveRetainedCount','fullJacobianCondition', ...
    'fullInformationCondition','regularizedJacobianCondition','regularizedInformationCondition', ...
    'regularizedSpace','conditionStatus'});
end
