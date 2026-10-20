function varargout = sht_transient_model_adapt_common(action, varargin)
%SHT_TRANSIENT_MODEL_ADAPT_COMMON 2.7 数据处理和参数接口公共函数。
%
% 本文件不执行参数估计，只提供 01/C02/C03 必须共用的确定性契约：
% 路径、20 参数定义、SHA-256、傅里叶平滑、归一化尺度、积分权重和
% 以 rad/s 配置的一阶传感器逆动态补偿。

if nargin < 1
    error('SHT:TransientAdaptCommon:MissingAction', '必须给定操作名称。');
end
switch lower(char(action))
    case 'paths'
        varargout{1} = local_paths();
    case 'parameterdefinitions'
        varargout{1} = local_parameter_definitions();
    case 'filehash'
        varargout{1} = local_file_hash(varargin{:});
    case 'latestfile'
        varargout{1} = local_latest_file(varargin{:});
    case 'smoo'
        varargout{1} = local_smoo_quiet(varargin{:});
    case 'outputscale'
        varargout{1} = local_output_scale(varargin{:});
    case 'integrationweights'
        varargout{1} = local_integration_weights(varargin{:});
    case 'inversesensor'
        [varargout{1:nargout}] = local_inverse_sensor(varargin{:});
    case 'outputsensortimeconstant'
        % Np、Ng、Pt3、Tt3、T45、Pt45；Mkp/Mkg 已移至模型输入侧。
        varargout{1} = [0.020,0.020,0.020,0.050,0.050,0.020];
    otherwise
        error('SHT:TransientAdaptCommon:UnknownAction', ...
            '未知操作：%s。', char(action));
end
end

function paths = local_paths()
paths = struct();
paths.mProgramDir = fileparts(mfilename('fullpath'));
paths.programRoot = fileparts(paths.mProgramDir);
paths.testDataDir = fullfile(paths.mProgramDir, ...
    'TestData', 'test_data_generation');
paths.outputDir = fullfile(paths.mProgramDir, ...
    'MiddleData', 'transient_model_adapt_tune');
if ~exist(paths.outputDir, 'dir')
    mkdir(paths.outputDir);
end
end

function params = local_parameter_definitions()
thetaIndex = (1:20).';
cIndex = [0;1;2;7;8;10;11;12;14;15;(58:67).'];
name = [ ...
    "Inlet_hpdP_Loss"; "HPC_hpW"; "HPC_hpEf"; "GT_hpW"; ...
    "GT_hpEf"; "GT_PT_Duct_hpdP_Loss"; "PT_hpW"; "PT_hpEf"; ...
    "PT_Nozzle_hpdP_Loss"; "Nozzle_hpA8"; ...
    "K_Jg"; "K_Jp"; "K_tau_HPC"; "K_tau_Burner"; ...
    "K_tau_GT"; "K_tau_PT"; "K_kW_HPC"; "K_keta_HPC"; ...
    "K_keta_GT"; "K_keta_PT"];
group = [repmat("steady",10,1); repmat("transient",10,1)];
lowerBound = [-0.10*ones(10,1); -0.50*ones(10,1)];
upperBound = [ 0.10*ones(10,1);  0.50*ones(10,1)];
differenceDelta = 1e-4 * ones(20,1);
params = table(thetaIndex, cIndex, cIndex + 1, name, group, ...
    lowerBound, upperBound, differenceDelta, ...
    'VariableNames', {'theta_index','c_index','health_index', ...
    'parameter_name','parameter_group','lower_bound','upper_bound', ...
    'difference_delta'});
end

function hash = local_file_hash(filePath)
filePath = char(string(filePath));
if ~isfile(filePath)
    error('SHT:TransientAdaptCommon:MissingHashFile', ...
        '无法计算哈希，文件不存在：%s。', filePath);
end
fid = fopen(filePath, 'rb');
if fid < 0
    error('SHT:TransientAdaptCommon:HashOpenFailed', ...
        '无法读取文件以计算哈希：%s。', filePath);
end
cleanup = onCleanup(@() fclose(fid));
bytes = fread(fid, Inf, '*uint8');
clear cleanup;
digest = java.security.MessageDigest.getInstance('SHA-256');
digest.update(typecast(bytes, 'int8'));
raw = typecast(digest.digest(), 'uint8');
hash = lower(reshape(dec2hex(raw, 2).', 1, []));
end

function filePath = local_latest_file(directory, pattern)
directory = char(string(directory));
pattern = char(string(pattern));
if ~exist(directory, 'dir')
    filePath = '';
    return;
end
files = dir(fullfile(directory, pattern));
files = files(~[files.isdir]);
if isempty(files)
    filePath = '';
    return;
end
[~, index] = max([files.datenum]);
filePath = fullfile(files(index).folder, files(index).name);
end

function zs = local_smoo_quiet(z, time, cutoffHz)
% smoo 内部按首个采样间隔构造 FFT，因此这里只接受近似等间隔数据。
time = time(:);
if isempty(z) || numel(time) ~= size(z,1) || numel(time) < 3 || ...
        ~isfinite(cutoffHz) || cutoffHz <= 0
    error('SHT:TransientAdaptCommon:InvalidSmooInput', ...
        '傅里叶平滑输入、时间轴或截止频率无效。');
end
dt = diff(time);
dtMedian = median(dt);
if any(~isfinite(dt)) || any(dt <= 0) || ...
        max(abs(dt - dtMedian)) > max(1e-10, 1e-6*dtMedian)
    error('SHT:TransientAdaptCommon:NonuniformSmooTime', ...
        '当前 smoo 实现要求近似等间隔采样。');
end
% mfilt 用 round(cutoff/df) 生成频率索引。短历程若无法解析给定
% 截止频率，原程序会以 0 下标失败；这里提前给出可操作的物理原因。
frequencyResolutionHz = 1/(2*(numel(time)-1)*dtMedian);
if round(cutoffHz/frequencyResolutionHz) < 1
    error('SHT:TransientAdaptCommon:UnresolvableCutoff', ...
        ['历程时长 %.6g s 无法解析 %.6g Hz 截止频率；当前傅里叶' ...
         '基频间隔为 %.6g Hz。请延长历程或提高截止频率。'], ...
        time(end)-time(1), cutoffHz, frequencyResolutionHz);
end
zs = NaN(size(z));
captured = evalc('zs = smoo(z, time, cutoffHz, 0, 0, cutoffHz);'); %#ok<NASGU>
if ~isequal(size(zs), size(z)) || any(~isfinite(zs(:)))
    error('SHT:TransientAdaptCommon:SmooFailure', ...
        '傅里叶平滑返回了尺寸错误或非有限数据。');
end
end

function scale = local_output_scale(measuredOutput)
if size(measuredOutput,2) ~= 6 || any(~isfinite(measuredOutput(:)))
    error('SHT:TransientAdaptCommon:InvalidMeasuredOutput', ...
        '输出归一化要求有限的 N-by-6 测量矩阵。');
end
scale = abs(mean(measuredOutput, 1));
floorValue = [1000,1000,1e5,100,100,1e4];
scale = max(scale, floorValue);
end

function weights = local_integration_weights(time)
% 梯形积分节点权重；全部权重之和严格等于该条历程持续时间。
time = time(:);
if numel(time) < 2 || any(~isfinite(time)) || any(diff(time) <= 0)
    error('SHT:TransientAdaptCommon:InvalidIntegrationTime', ...
        '积分时间轴必须有限且严格递增。');
end
dt = diff(time);
weights = zeros(size(time));
weights(1) = 0.5 * dt(1);
weights(end) = 0.5 * dt(end);
if numel(time) > 2
    weights(2:end-1) = 0.5 * (dt(1:end-1) + dt(2:end));
end
end

function [inputEstimate, info] = local_inverse_sensor( ...
        measured, time, bandwidthRadPerSec, enabled, signalName)
measured = measured(:);
time = time(:);
if nargin < 5, signalName = 'signal'; end
if numel(measured) ~= numel(time) || any(~isfinite(measured)) || ...
        numel(time) < 2 || any(diff(time) <= 0)
    error('SHT:TransientAdaptCommon:InvalidInverseInput', ...
        '%s 逆动态补偿输入无效。', char(signalName));
end
inputEstimate = measured;
info = struct('enabled',logical(enabled), ...
    'bandwidthRadPerSec',bandwidthRadPerSec, 'minimumAlpha',NaN, ...
    'maximumAlpha',NaN, 'discretization','FOH', ...
    'signalName',char(signalName));
if ~enabled
    return;
end
dt = diff(time);
if ~isscalar(bandwidthRadPerSec) || ~isfinite(bandwidthRadPerSec) || ...
        bandwidthRadPerSec <= 0 || ...
        bandwidthRadPerSec >= pi / max(dt)
    error('SHT:TransientAdaptCommon:InvalidInverseBandwidth', ...
        ['%s 逆动态角频率带宽必须满足 0 < omega_b < pi/max(dt)，' ...
         '单位为 rad/s。'], char(signalName));
end
[inputEstimate, inverseInfo] = sht_first_order_foh_inverse( ...
    measured, time, 1 / bandwidthRadPerSec);
if any(~isfinite(inputEstimate))
    error('SHT:TransientAdaptCommon:NonfiniteInverseResult', ...
        '%s 逆动态补偿产生非有限值。', char(signalName));
end
if strcmpi(char(signalName), 'Wf') && any(inputEstimate <= 0)
    error('SHT:TransientAdaptCommon:InvalidInverseFuel', ...
        'Wf 逆动态补偿产生非正燃油流量。');
elseif strcmpi(char(signalName), 'target_load_power') && any(inputEstimate < 0)
    error('SHT:TransientAdaptCommon:InvalidInverseLoad', ...
        '%s 逆动态补偿产生负值。', char(signalName));
end
% 保留历史字段名minimumAlpha/maximumAlpha，数值现表示FOH公式中当前
% 采样输入u(k)的权重bNext，便于旧结果结构继续读取。
info.minimumAlpha = inverseInfo.minimumCurrentInputWeight;
info.maximumAlpha = inverseInfo.maximumCurrentInputWeight;
end
