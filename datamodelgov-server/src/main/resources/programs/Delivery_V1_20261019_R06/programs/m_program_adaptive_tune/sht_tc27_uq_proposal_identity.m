function identity=sht_tc27_uq_proposal_identity(proposal)
%SHT_TC27_UQ_PROPOSAL_IDENTITY 提议数学身份，不把报告创建时间当作密度参数。
% 只排除已知的两处时间戳，保留分量权重、中心、尺度、基底及完整先验。
if isfield(proposal,'createdAt'),proposal=rmfield(proposal,'createdAt');end
if isfield(proposal,'prior')&&isfield(proposal.prior,'createdAt')
    proposal.prior=rmfield(proposal.prior,'createdAt');
end
identity=sht_tc27_uq_hash(proposal);
end
