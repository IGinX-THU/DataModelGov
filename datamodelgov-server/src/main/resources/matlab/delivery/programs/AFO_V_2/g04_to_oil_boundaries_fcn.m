function [airTempC, ventBoundary10] = ...
    g04_to_oil_boundaries_fcn(g04T_K, g04P_Pa, ambientT_K, ambientP_Pa)
%G04_TO_OIL_BOUNDARIES_FCN Calibrate G04 T/P to oil ventilation boundaries.
% VentBoundary10 order:
% [Paf,Taf,Par,Tar,Pbf,Tbf,Pbr,Tbr,Pvent,Tvent] in Pa/K.
%
% The five unique calibration points come from the six-condition oil
% training set (50% maximum-continuous and maximum-continuous share one
% oil boundary point). G04 pressure uses the station-table Pa values.

%#codegen
tAnchor = [702.307986955364; 691.15; 680.22; 489.72; 635.89];
pAnchor = [1572564; 1511479; 1444230; 441500; 779164];
airAnchorC = [15; 15; 15; 15; -24];
sealAnchor = [ ...
    307619, 472, 308501, 472, 324693, 523, 315021, 558; ...
    302217, 470, 303275, 470, 319069, 518, 309698, 552; ...
    299079, 468, 300217, 468, 315021, 514, 304477, 548; ...
    176031, 390, 180486, 390, 184379, 421, 177214, 448; ...
    202991, 432, 206003, 432, 215981, 468, 207742, 501];

if ~isfinite(g04T_K) || g04T_K < 150 || g04T_K > 3000
    g04T_K = tAnchor(1);
end
if ~isfinite(g04P_Pa) || g04P_Pa < 3.0e4 || g04P_Pa > 5.0e6
    g04P_Pa = pAnchor(1);
end

% Inverse-distance interpolation in normalized T/P coordinates.
d2 = zeros(5, 1);
exactIndex = int32(0);
for k = 1:5
    dt = (g04T_K - tAnchor(k)) / 100;
    dp = (g04P_Pa - pAnchor(k)) / 5.0e5;
    d2(k) = dt * dt + dp * dp;
    if d2(k) < 1.0e-20
        exactIndex = int32(k);
    end
end

if exactIndex > 0
    airTempC = airAnchorC(exactIndex);
    seal8 = sealAnchor(exactIndex, :).';
else
    weights = zeros(5, 1);
    weightSum = 0;
    for k = 1:5
        weights(k) = 1 / ((d2(k) + 1.0e-12) * (d2(k) + 1.0e-12));
        weightSum = weightSum + weights(k);
    end
    airTempC = 0;
    seal8 = zeros(8, 1);
    for k = 1:5
        fraction = weights(k) / weightSum;
        airTempC = airTempC + fraction * airAnchorC(k);
        for j = 1:8
            seal8(j) = seal8(j) + fraction * sealAnchor(k, j);
        end
    end
end

% IDW is bounded by the training data; retain explicit physical guards for
% corrupt arithmetic or future table edits.
airTempC = min(max(airTempC, -24), 15);
for k = 1:4
    pressureIndex = 2 * k - 1;
    temperatureIndex = 2 * k;
    seal8(pressureIndex) = min(max(seal8(pressureIndex), 1.0e5), 5.0e5);
    seal8(temperatureIndex) = min(max(seal8(temperatureIndex), 250), 700);
end

if ~isfinite(ambientT_K) || ambientT_K < 180 || ambientT_K > 360
    ambientT_K = airTempC + 273.15;
end
if ~isfinite(ambientP_Pa) || ambientP_Pa < 3.0e4 || ambientP_Pa > 2.0e5
    ambientP_Pa = 1.01325e5;
end

ventBoundary10 = zeros(10, 1);
ventBoundary10(1:8) = seal8;
ventBoundary10(9) = ambientP_Pa;
ventBoundary10(10) = ambientT_K;
end
