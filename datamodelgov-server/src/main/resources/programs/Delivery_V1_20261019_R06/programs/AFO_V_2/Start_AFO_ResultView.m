function result=Start_AFO_ResultView(file,makePlots)
%START_AFO_RESULTVIEW 只读Excel查看；不用加载SLX/DLL，不自动续跑。
if nargin<2,makePlots=true;end
result=sht_afo_results('read',file);
disp(result.run);disp(result.channels);
if makePlots,sht_afo_results('plot',file);end
end
