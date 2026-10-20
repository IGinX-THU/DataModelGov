function s = sht_startstop_engine_snapshot(eng, maps, cfg)
%SHT_STARTSTOP_ENGINE_SNAPSHOT 按初始化拓扑读取气路，不访问不存在的子部件。
% eng=[]时返回同拓扑空记录，用于失败点及尚未激活气路的零速点。
t=cfg.topology; n=numel(t.componentNames);
s=struct('mapCoordinate',nan(n,2),'mapMargin',nan(n,2), ...
    'minimumMapMargin',NaN,'mapExtrapolated',false, ...
    'stationWTP',nan(numel(t.stationNames),3),'hpsGasTorqueNm',NaN, ...
    'ptGasTorqueNm',NaN,'tt45K',NaN,'Ngc',NaN,'componentTorqueNm',nan(1,n), ...
    'actualCorrectedFlow',nan(1,n),'mapCorrectedFlow',nan(1,n), ...
    'flowScalar',nan(1,n),'requiredMapCorrectedFlow',nan(1,n), ...
    'requiredFlowRatio',nan(1,n),'modelErrorCode',NaN, ...
    'configurationValid',false,'evaluationValid',false, ...
    'offendingStepInIndex',NaN,'offendingValue',NaN, ...
    'physicalValid',false,'errorMessage','');
if isempty(eng), return; end
try
    d=eng.transientDiagnostics;
    s.modelErrorCode=double(d.errorCode);
    s.configurationValid=logical(d.configurationValid);
    s.evaluationValid=logical(d.evaluationValid);
    s.offendingStepInIndex=double(d.offendingStepInIndex);
    s.offendingValue=double(d.offendingValue);
    station={eng.Inlet.gasPathOut};
    for i=1:n
        name=t.componentNames{i}; field=t.engineFields{i}; b=eng.(field);
        if strcmp(cfg.maps.(name).kind,'compressor')
            s.mapCoordinate(i,:)=[b.y(16),eng.([field,'_Rline'])];
            s.mapCorrectedFlow(i)=b.y(17); s.flowScalar(i)=b.y(10);
        else
            s.mapCoordinate(i,:)=[b.y(15),b.y(17)];
            s.mapCorrectedFlow(i)=b.y(16); s.flowScalar(i)=b.y(9);
        end
        map=maps.(name);
        s.mapMargin(i,:)=[local_margin(s.mapCoordinate(i,1),map.nc), ...
            local_margin(s.mapCoordinate(i,2),map.path)];
        s.componentTorqueNm(i)=b.y(6); s.actualCorrectedFlow(i)=b.y(13);
        station{end+1}=b.y; %#ok<AGROW>
        if i==t.compressorCount, station{end+1}=eng.Burner.y; end %#ok<AGROW>
    end
    for i=1:numel(station)
        v=station{i}; s.stationWTP(i,:)=[v(1),v(3),v(4)];
    end
    s.minimumMapMargin=min(s.mapMargin(:));
    s.mapExtrapolated=s.minimumMapMargin < -1e-10;
    s.hpsGasTorqueNm=eng.HPS_Trq; s.ptGasTorqueNm=eng.LPS_Trq;
    s.Ngc=double(eng.HPC.y(14)); % 有量纲换算转速，与主控制器一致。
    if cfg.modelMode==0, s.tt45K=eng.HPT.y(3); else, s.tt45K=eng.HPT2.y(3); end
    s.requiredMapCorrectedFlow=s.actualCorrectedFlow./max(s.flowScalar,1e-12);
    s.requiredFlowRatio=s.requiredMapCorrectedFlow./max(abs(s.mapCorrectedFlow),1e-12);
    values=[s.stationWTP(:);s.mapCoordinate(:);s.componentTorqueNm(:); ...
        s.requiredFlowRatio(:);s.hpsGasTorqueNm;s.ptGasTorqueNm];
    s.physicalValid=all(isfinite(values)) && all(s.stationWTP(:,1)>=-1e-9) ...
        && all(s.stationWTP(:,2)>0) && all(s.stationWTP(:,3)>0);
catch ex
    s.errorMessage=ex.message; s.physicalValid=false;
end
end

function margin=local_margin(x,a)
span=max(a(end)-a(1),eps);
margin=min((x-a(1))/span,(a(end)-x)/span);
end
