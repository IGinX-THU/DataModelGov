function oilInlet2C = oil_cooler_inlet_from_bearings_fcn( ...
    tempA_C, tempB_C, returnFlowA, returnFlowB)
%OIL_COOLER_INLET_FROM_BEARINGS_FCN Mix A/B bearing return-oil temperatures.
% Output order is [fuel-oil cooler inlet; air-oil cooler inlet], degC.

%#codegen
validA = isfinite(tempA_C) && tempA_C > 20 && tempA_C < 250;
validB = isfinite(tempB_C) && tempB_C > 20 && tempB_C < 250;

if ~validA && validB
    tempA_C = tempB_C;
elseif validA && ~validB
    tempB_C = tempA_C;
elseif ~validA && ~validB
    tempA_C = 130;
    tempB_C = 130;
end

if ~isfinite(returnFlowA) || returnFlowA < 0
    returnFlowA = 0;
end
if ~isfinite(returnFlowB) || returnFlowB < 0
    returnFlowB = 0;
end

totalFlow = returnFlowA + returnFlowB;
if totalFlow > 1.0e-8
    mixedTemp_C = (returnFlowA * tempA_C + ...
        returnFlowB * tempB_C) / totalFlow;
else
    mixedTemp_C = 0.5 * (tempA_C + tempB_C);
end
mixedTemp_C = min(max(mixedTemp_C, 20), 250);

% Both cooler branches receive the same mixed return-oil temperature.
% Their training functions apply their own valid-envelope limits.
oilInlet2C = [mixedTemp_C; mixedTemp_C];
end
