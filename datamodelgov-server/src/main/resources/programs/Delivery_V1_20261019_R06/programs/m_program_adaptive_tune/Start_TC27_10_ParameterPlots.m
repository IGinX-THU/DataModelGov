function files=Start_TC27_10_ParameterPlots(directory)
%START_TC27_10_PARAMETERPLOTS 从冻结结果重绘参数区间，不调用DLL或重新采样。
% 常值参数也保留确定性标记。燃油偏置单列量纲，退化区间不人为扩宽。
if nargin<1,c=sht_tc27_uq_contract(sht_tc27_uq_c_options());directory=c.directory;end
a=load(fullfile(directory,'contract.mat'),'c');c=a.c;
a=load(fullfile(directory,'prediction_report.mat'),'report');r=a.report;
sets={{'C'},{'D'},{'C','D'}};files=strings(0,1);
groups=unique(c.parameterTable.group_index).';colors=[.15,.40,.82;.12,.57,.27];
for setIndex=1:numel(sets)
    methods=sets{setIndex};if ~all(cellfun(@(name)isfield(r,name),methods)),continue;end
    f=figure('Visible','off','Position',[50,50,1450,1050]);labels={};handles=gobjects(0);
    for j=1:numel(groups)
        q=find(c.parameterTable.group_index==groups(j));x=c.parameterTable.coordinate(q);
        subplot(4,3,j);hold on;handles=gobjects(0);labels={};
        for k=1:numel(methods)
            name=methods{k};t=r.(name).summary;color=colors(1+strcmp(name,'D'),:);
            handles(end+1)=fill([x;flipud(x)],[t.q025(q);flipud(t.q975(q))], ...
                color,'FaceAlpha',.18,'EdgeColor','none'); %#ok<AGROW>
            labels{end+1}=[name,' 95% interval']; %#ok<AGROW>
            handles(end+1)=plot(x,t.posterior_mean(q),'.-','Color',color,'LineWidth',1); %#ok<AGROW>
            labels{end+1}=[name,' mean']; %#ok<AGROW>
            if numel(x)==1,plot([x,x],[t.q025(q),t.q975(q)],'-','Color',color,'LineWidth',1.5);end
        end
        handles(end+1)=plot(x,t.deterministic_estimate(q),'ro--','MarkerSize',3);
        handles(end+1)=plot(x,t.truth(q),'k.-');labels=[labels,{'Deterministic','Truth'}];
        title(c.parameterTable.base_name(q(1)),'Interpreter','none');
        xlabel(c.parameterTable.axis_name(q(1)),'Interpreter','none');ylabel(t.unit(q(1)));grid on;
    end
    lg=legend(handles,labels,'Orientation','horizontal','NumColumns',numel(labels));
    set(lg,'Units','normalized','Position',[.05,.005,.90,.03]);
    titles=cellfun(@(name)[name,': ',r.(name).quality],methods,'UniformOutput',false);
    sgtitle(titles,'Interpreter','none','FontSize',10);
    if numel(methods)==1,name=['method_',methods{1},'_parameter_intervals.png'];
    else,name='C_D_parameter_intervals.png';end
    file=fullfile(c.report,name);print(f,file,'-dpng','-r150');close(f);files(end+1)=string(file); %#ok<AGROW>
end
fprintf('TC27冻结参数区间图已重绘%d幅；未调用DLL。\n',numel(files));
end
