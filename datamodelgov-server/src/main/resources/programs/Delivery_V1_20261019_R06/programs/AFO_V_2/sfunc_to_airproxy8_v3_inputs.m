function y = sfunc_to_airproxy8_v3_inputs(u)
%SFUNC_TO_AIRPROXY8_V3_INPUTS Map engine outputs to AirProxy8 V3 inputs.
%
% Input:
%   u(1:20)  - SFunc_EngModel output port 1 (engine performance)
%   u(21:70) - SFunc_EngModel output port 2 (SecAir50)
%
% SecAir50 is ten groups of [W, Ht/FAR, Tt_K, Pt_Pa, OAR/reserved].
%
% Output order:
%   [T1_K; P1_Pa; T2_K; P2_Pa; T3_K; P3_Pa; ...
%    T4_K; P4_Pa; T45_K; P45_Pa; T5_K; P5_Pa; Ng_rpm; Np_rpm]

design = [ ...
    540.41189229546796
    982852.50000476895
    473.20635245950098
    744019.34250348201
    702.30798695536396
    1572564.00000795
    1619.9999999955601
    1517524.2600076699
    1142.93909608642
    108055.52351408001
    857.21353999029498
    108055.52351408001
    38000
    20800];

u = u(:);
if numel(u) < 70
    u(end + 1:70, 1) = NaN;
end
eng = u(1:20);
sec = u(21:70);

% T1/P1: G07 (axial-compressor inlet boundary).
t1 = valid_mean(sec(33), design(1), 150, 2500);
p1 = valid_mean(sec(34), design(2), 1e4, 1e8);

% T2/P2: mean of G05 and G06 (axial-compressor outlet root paths).
t2 = valid_mean(sec([23 28]), design(3), 150, 2500);
p2 = valid_mean(sec([24 29]), design(4), 1e4, 1e8);

% T3/P3: mean of G01-G04 (centrifugal-compressor outlet paths).
t3 = valid_mean(sec([3 8 13 18]), design(5), 150, 2500);
p3 = valid_mean(sec([4 9 14 19]), design(6), 1e4, 1e8);

% Main gas-path stations and shaft speeds come from engine output port 1.
t4 = valid_mean(eng(19), design(7), 150, 3000);
p4 = valid_mean(eng(18), design(8), 1e4, 1e8);
t45 = valid_mean(eng(6), design(9), 150, 3000);
p45 = valid_mean(eng(5), design(10), 1e4, 1e8);
t5 = valid_mean(eng(8), design(11), 150, 2500);
p5 = valid_mean(eng(7), design(12), 1e4, 1e8);
ng = valid_mean(eng(10), design(13), 100, 1e5);
np = valid_mean(eng(9), design(14), 100, 1e5);

y = [t1; p1; t2; p2; t3; p3; t4; p4; ...
    t45; p45; t5; p5; ng; np];
end


function value = valid_mean(values, fallback, lowerBound, upperBound)
values = values(:);
valid = isfinite(values) & values >= lowerBound & values <= upperBound;
if any(valid)
    value = mean(values(valid));
else
    value = fallback;
end
end
