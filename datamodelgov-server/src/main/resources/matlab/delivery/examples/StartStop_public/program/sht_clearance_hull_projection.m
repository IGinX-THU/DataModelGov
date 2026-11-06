function varargout = sht_clearance_hull_projection(action,varargin)
%SHT_CLEARANCE_HULL_PROJECTION 二维参考表域外连续延拓，不改变域内插值。
% prepare按两坐标跨度归一化，并缓存凸包边界。query将域外点投影到
% 最近边界位置，沿该位置所在的真实边界小段线性取值。边上的共线
% 表点必须保留，不能只连接凸包角点，否则仍会与域内插值不连续。
switch action
    case 'prepare'
        speed=varargin{1}(:);power=varargin{2}(:);value=varargin{3}(:);
        xy=[speed,power];origin=min(xy,[],1);scale=max(xy,[],1)-origin;
        assert(size(xy,1)>=3 && numel(value)==size(xy,1) && ...
            all(isfinite([xy(:);value])) && all(scale>0), ...
            'SHT:ClearanceHull:InvalidTable','连续边界需要有限且有二维跨度的参考表。');
        [xy,~,group]=unique(xy,'rows');
        v=accumarray(group,value,[],@mean);
        spread=accumarray(group,value,[],@(x)max(x)-min(x));
        assert(all(spread<=1e-12*max(1,max(abs(value)))), ...
            'SHT:ClearanceHull:DuplicateConflict','相同参考坐标的间隙值互相冲突。');
        q=(xy-origin)./scale;
        assert(rank(q-q(1,:),1e-12)==2,'SHT:ClearanceHull:Collinear', ...
            '参考点共线，不能构造二维覆盖域。');
        hull=convhull(q(:,1),q(:,2));edges=zeros(0,2);
        for k=1:numel(hull)-1
            first=q(hull(k),:);direction=q(hull(k+1),:)-first;
            fraction=(q-first)*direction.'/sum(direction.^2);
            distance=sqrt(sum((q-(first+fraction.*direction)).^2,2));
            candidates=find(distance<=2e-12 & fraction>=-2e-12 & fraction<=1+2e-12);
            [~,order]=sort(fraction(candidates));ids=candidates(order);
            edges=[edges;ids(1:end-1),ids(2:end)]; %#ok<AGROW>
        end
        a=q(edges(:,1),:);d=q(edges(:,2),:)-a;
        g=struct('version','clearance-hull-projection-v1','origin',origin, ...
            'scale',scale,'start',a,'direction',d,'lengthSquared',sum(d.^2,2), ...
            'startValue',v(edges(:,1)),'endValue',v(edges(:,2)), ...
            'edgeCoordinates',xy(edges(:,1),:),'hullCoordinates',xy(hull,:));
        assert(all(g.lengthSquared>0),'SHT:ClearanceHull:ZeroEdge','边界包含零长度小段。');
        varargout={g};
    case 'query'
        g=varargin{1};query=varargin{2};
        assert(isnumeric(query)&&numel(query)==2&&all(isfinite(query)), ...
            'SHT:ClearanceHull:InvalidQuery','边界查询必须是两个有限坐标。');
        q=(reshape(query,1,2)-g.origin)./g.scale;
        t=sum((q-g.start).*g.direction,2)./g.lengthSquared;
        t=min(max(t,0),1);projected=g.start+t.*g.direction;
        [distanceSquared,index]=min(sum((projected-q).^2,2));
        value=(1-t(index))*g.startValue(index)+t(index)*g.endValue(index);
        info=struct('usedCoordinate',g.origin+g.scale.*projected(index,:), ...
            'normalizedDistance',sqrt(distanceSquared),'edgeIndex',index, ...
            'edgeFraction',t(index));
        varargout={value,info};
    otherwise
        error('SHT:ClearanceHull:Action','未知边界操作%s。',action);
end
end
