function y = sfunc_out2_to_airboundary_tp16(secAir50)
%SFUNC_OUT2_TO_AIRBOUNDARY_TP16 Extract G01-G08 Tt/Pt from SFunc Out2.
%
% SecAir50 group layout is [W_kgps, Ht, Tt_K, Pt_Pa, OAR].
% This function intentionally uses only groups G01-G08 (elements 1:40)
% and only their Tt/Pt fields. W, Ht, OAR and groups G09/G10 are ignored.
%
% Output:
% [G01_Tt; G01_Pt; ...; G08_Tt; G08_Pt]

fallback = [ ...
    702.30798695536396; 1572564.00000795
    702.30798695536396; 1572564.00000795
    702.30798695536396; 1572564.00000795
    702.30798695536396; 1572564.00000795
    473.20635245950098; 744019.34250348201
    473.20635245950098; 744019.34250348201
    540.41189229546796; 982852.50000476895
    540.41189229546796; 982852.50000476895];

secAir50 = secAir50(:);
if numel(secAir50) < 40
    secAir50(end + 1:40, 1) = NaN;
end

indices = [3 4 8 9 13 14 18 19 23 24 28 29 33 34 38 39];
y = secAir50(indices).';
y = y(:);

for index = 1:2:numel(y)
    if ~isfinite(y(index)) || y(index) < 150 || y(index) > 3000
        y(index) = fallback(index);
    end
    if ~isfinite(y(index + 1)) || y(index + 1) < 1e4 || ...
            y(index + 1) > 1e8
        y(index + 1) = fallback(index + 1);
    end
end
end
