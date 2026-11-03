function sensor = sht_sensor_pack(y, pressureChannel)
% 阅读说明：
%   本文件把发动机输出向量按控制器关心的物理量重新打包为 sample 结构。
%   若后续 C 程序输出通道或测点口径变化，应优先在这里维护映射关系。
%SHT_SENSOR_PACK Build the measured-signal vector used by the controller.
%
% Stage-2 sensor definition. Only directly available or physically
% instrumentable quantities are packed as sampled signals. Speed derivatives
% such as dNp/dNg are not sensors; they are derived diagnostics in the log.
%
% T45 is kept as an alias of Tt45. For a T700/CT7-like free-power-turbine
% turboshaft, station 4.5 is the inter-turbine / power-turbine-inlet gas
% temperature used for limiting. Station 5 is logged separately as turbine
% exit / exhaust-side temperature and should not silently replace T45.

if nargin < 2, pressureChannel = 'Pt2'; end
pressureChannel = validatestring(pressureChannel, {'Pt1','Pt2'});
sensor = struct();
sensor.Np = local_get(y, 'Np', NaN);
sensor.Ng = local_get(y, 'Ng', NaN);

% 旧六部件默认测量Inlet出口Pt2；三部件TC24显式选择进口Pt1，
% 在下文替换第8槽并移除Pt2测量字段，不能把两种测点合同混用。
sensor.Pt2 = local_get(y, 'Pt2', NaN);
sensor.Tt1 = local_get(y, 'Tt1', NaN);
sensor.Pamb = local_get(y, 'Pamb', NaN);
sensor.Tamb = local_get(y, 'Tamb', NaN);
sensor.Pt3 = local_get(y, 'Pt3', NaN);
sensor.Tt3 = local_get(y, 'Tt3', NaN);
sensor.Pt45 = local_get(y, 'Pt45', NaN);
sensor.Tt45 = local_get(y, 'Tt45', NaN);
sensor.T45 = sensor.Tt45;
sensor.Pt5 = local_get(y, 'Pt5', NaN);
sensor.Tt5 = local_get(y, 'Tt5', NaN);
sensor.T5 = sensor.Tt5;

sensor.Mkp = local_get(y, 'Mkp', NaN);
sensor.Mkg = local_get(y, 'Mkg', NaN);
sensor.HpcStallMargin = local_get(y, 'HpcStallMargin', NaN);
sensor.FAR = local_get(y, 'FAR', NaN);
sensor.T4 = local_get(y, 'T4', NaN);
sensor.Altitude = local_get(y, 'Altitude', NaN);
sensor.Mach = local_get(y, 'Mach', NaN);

if isfinite(sensor.Tt1) && sensor.Tt1 > 0
    sensor.Theta = sensor.Tt1 / 288.15;
else
    sensor.Theta = 1;
end
if isfinite(sensor.Pt2) && sensor.Pt2 > 0
    sensor.Deta = sensor.Pt2 / 101325;
else
    sensor.Deta = 1;
end

if isfield(y, 'NgcRaw') && ~isempty(y.NgcRaw) && isfinite(y.NgcRaw)
    % Ngc 采用发动机模型输出的压气机修正转速，不使用 Ng 超转保护上限归一化。
    sensor.Ngc = y.NgcRaw;
elseif isfinite(sensor.Ng)
    sensor.Ngc = sensor.Ng / sqrt(max(sensor.Theta, eps));
else
    sensor.Ngc = sensor.Ng;
end

sensor.vectorNames = local_vector_names();
sensor.vector = [sensor.Np; sensor.Ng; sensor.T45; sensor.Mkp; ...
    sensor.Ngc; sensor.Theta; sensor.Deta; sensor.Pt2; sensor.Tt1; ...
    sensor.Pt3; sensor.Tt3; sensor.Pt45; sensor.Tt45; sensor.Pt5; ...
    sensor.Tt5; sensor.HpcStallMargin; sensor.FAR; sensor.T4; ...
    sensor.Mkg; sensor.Pamb; sensor.Tamb; sensor.Altitude; sensor.Mach];
% TC24使用粒子分离器进口Pt1。保留向量长度和旧Pt2默认语义，
% 通过显式通道名选择压力传感器，不把两个物理站位静默混同。
if strcmp(pressureChannel,'Pt1')
    sensor.Pt1 = local_get(y,'Pt1',NaN);
    sensor.Pt2 = NaN;
    sensor.vectorNames{8} = 'Pt1';
    sensor.vector(8) = sensor.Pt1;
    sensor.Deta = sensor.Pt1/101325;
    sensor.vector(7) = sensor.Deta;
end
end

function names = local_vector_names()
names = {'Np', 'Ng', 'T45', 'Mkp', 'Ngc', 'Theta', 'Deta', ...
    'Pt2', 'Tt1', 'Pt3', 'Tt3', 'Pt45', 'Tt45', 'Pt5', 'Tt5', ...
    'HpcStallMargin', 'FAR', 'T4', 'Mkg', 'Pamb', 'Tamb', ...
    'Altitude', 'Mach'};
end

function value = local_get(s, name, defaultValue)
if isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end
