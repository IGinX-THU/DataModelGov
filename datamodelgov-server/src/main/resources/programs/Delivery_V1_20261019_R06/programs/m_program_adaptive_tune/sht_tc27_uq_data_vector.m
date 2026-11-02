function y=sht_tc27_uq_data_vector(points,histories,route)
%SHT_TC27_UQ_DATA_VECTOR 按路线排列稳态观测，再附加可选历程。
if nargin<3,route='transient_instant';end
assert(ismember(route,{'steady','transient_instant'}),'TC27:UQ:Route','未知观测路线。');
names={'Np','Ng','Ptb3','Ttb3','Pt45','Tt45','Pt6','Tt6','Wa2'};
v=zeros(height(points),9);
for j=1:9
    if j==9,v(:,j)=points.Wa1_mean-points.Wb_mean;
    elseif j<=2&&strcmp(route,'transient_instant'),v(:,j)=0;
    else,v(:,j)=points.([names{j},'_mean']);end
end
y=v(:);
for h=1:numel(histories)
    t=histories(h).data;v=zeros(height(t),9);
    for j=1:9
        if j==9,v(:,j)=t.Wa1-t.Wb;else,v(:,j)=t.(names{j});end
    end
    y=[y;v(:)]; %#ok<AGROW>
end
end
