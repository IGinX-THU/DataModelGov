function [fun,factory,statistics]=sht_tc27_local_history_objective(cfg,engine,data,sources,histories,contract,options)
%SHT_TC27_LOCAL_HISTORY_OBJECTIVE 正式点/历程目标与每轮复用准备的差分。
% 纯稳态点仍逐候选求热平衡；差分仅复用小幅历程的准备状态。
if ~isfield(options,'pointHistoryWeights'),options.pointHistoryWeights=[.7,.3];end
[pf,ps]=sht_tc27_objective(cfg,engine,data,sources,[],contract,options);
[hf,hfactory,hs]=sht_tc27_prepared_history_objective(cfg,engine,histories,contract,options);
w=options.pointHistoryWeights/sum(options.pointHistoryWeights);
fun=@objective;factory=@differenceFactory;statistics=@stats;
    function [r,m]=objective(theta)
        [rp,mp]=pf(theta);[rh,mh]=hf(theta);[r,m]=combine(rp,mp,rh,mh);
    end
    function f=differenceFactory(theta)
        fh=hfactory(theta);f=@(candidate)difference(candidate,fh);
    end
    function [r,m]=difference(theta,fh)
        [rp,mp]=pf(theta);[rh,mh]=fh(theta);[r,m]=combine(rp,mp,rh,mh);
    end
    function [r,m]=combine(rp,mp,rh,mh)
        r=[sqrt(w(1))*rp;sqrt(w(2))*rh];m=mp;
        m.valid=mp.valid&&mh.valid;m.messages=[mp.messages;mh.messages];
        blocks=mh.jacobianBlocks;
        for b=1:numel(blocks),blocks(b).rows=blocks(b).rows+numel(rp);end
        m.jacobianBlocks=[mp.jacobianBlocks,blocks];
    end
    function s=stats()
        s=hs();s.pointStatistics=ps();s.pointDllCalls=s.pointStatistics.thermalDllEvaluations;
        s.totalKnownDllCalls=s.historyDllCalls+s.pointDllCalls;
        s.dllCountMayBeLowerBound=s.dllCountMayBeLowerBound||s.pointStatistics.dllCountMayBeLowerBound;
    end
end
