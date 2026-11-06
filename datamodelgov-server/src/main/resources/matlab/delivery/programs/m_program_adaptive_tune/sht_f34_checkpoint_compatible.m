function yes=sht_f34_checkpoint_compatible(result,prepared,likelihood,methodD)
%SHT_F34_CHECKPOINT_COMPATIBLE 算法检查点比物理缓存多核对源码、选项和提议。
% 不重签旧结果。方法C的提议需与本次D中心/协方差或纯先验选择一致。
yes=isfield(result,'preparedOptionsSha256')&& ...
    strcmp(result.preparedOptionsSha256,prepared.contract.optionsSha256)&& ...
    isfield(result,'likelihoodContractHash')&&strcmp(result.likelihoodContractHash,likelihood.contractHash)&& ...
    isfield(result,'implementationSha256')&&strcmp(result.implementationSha256, ...
    sht_f33_model_adapt_v2('fileHash',which(['sht_f34_method_' lower(result.methodId)])));
if ~yes||nargin<4,return;end
if ~isfield(result,'runIdentity'),yes=false;return;end
id=result.runIdentity;
yes=strcmp(id.priorSource,sht_f33_model_adapt_v2('fileHash',which('sht_f34_prior')))&& ...
    strcmp(id.release,version('-release'))&&strcmp(id.architecture,computer('arch'));
keys={'methodCFinalMoveSweeps','methodCIndependentMoveFraction','methodCMoveSweeps', ...
    'methodCConditionalEssFraction','methodCResampleFraction','methodCMaximumStages'};
for j=1:numel(keys)
    k=keys{j};yes=yes&&isfield(prepared.options,k)&&isequal(id.options.(k),prepared.options.(k));
end
if ~yes,return;end
if ~isfield(result,'proposal'),yes=false;return;end
q=result.proposal;
if isfield(prepared.prior,'nodePrior')
    yes=isfield(q,'defensiveKind')&&strcmp(q.defensiveKind,'uniform_physical_box');
    if ~yes,return;end
end
if isempty(methodD),yes=~q.localProposalUsed&&q.priorFraction==1;return;end
lo=prepared.prior.lowerBound(:);hi=prepared.prior.upperBound(:);
x=min(max((methodD.map-lo)./(hi-lo),1e-6),1-1e-6);mu=log(x./(1-x));
derivative=1./((hi-lo).*x.*(1-x));
covariance=(derivative.*methodD.covariance).*derivative.';
covariance=prepared.options.methodCProposalScale^2*covariance;
covariance=(covariance+covariance.')/2+q.jitter*eye(numel(mu));
yes=q.localProposalUsed&&isequal(q.lower,lo)&&isequal(q.upper,hi)&& ...
    q.priorFraction==prepared.options.methodCDefensivePriorFraction&& ...
    max(abs(q.meanZ-mu))<1e-12&&max(abs(q.covarianceZ-covariance),[],'all')<1e-12;
end
