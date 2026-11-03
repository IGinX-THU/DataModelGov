function sht_tc27_reset_gas_seed(engine,seed)
%SHT_TC27_RESET_GAS_SEED 给当前进程的三部件DLL明确恢复气路初值。
% 只影响数值迭代初值，最终仍由当前边界和健康曲线求解。
assert(engine.modelMode==0&&numel(seed)==6&&all(isfinite(seed)),'需要三部件6维共同工作初值。');
v=zeros(512,1);v(21:26)=seed(:);engine.callContext.stepIn.Value=v;
status=calllib(engine.libraryName,'DLL_SHT_varIteInit',engine.callContext.stepIn, ...
    engine.callContext.stepOut,engine.callContext.engPtr);
assert(status==0,'TC27气路初值写入失败。');
end
