function sht_export_figure(fig,file,varargin)
%SHT_EXPORT_FIGURE R2019b图片导出，保持屏幕图幅并恢复调用方纸张属性。
% 当前调用均为整幅figure的PNG；不遮蔽MATLAB的exportgraphics函数。
parser=inputParser;addParameter(parser,'Resolution',160, ...
    @(x)isnumeric(x)&&isscalar(x)&&isfinite(x)&&x>0);parse(parser,varargin{:});
assert(isgraphics(fig,'figure'),'SHT:Figure:Handle','必须传入figure句柄。');
[~,~,ext]=fileparts(file);assert(strcmpi(ext,'.png'),'SHT:Figure:Format','本接口只导出PNG。');
names={'PaperPositionMode','InvertHardcopy'};old=get(fig,names);
cleanup=onCleanup(@()set(fig,names,old));
set(fig,'PaperPositionMode','auto','InvertHardcopy','off');drawnow;
print(fig,char(file),'-dpng',sprintf('-r%d',round(parser.Results.Resolution)));
clear cleanup;
end
