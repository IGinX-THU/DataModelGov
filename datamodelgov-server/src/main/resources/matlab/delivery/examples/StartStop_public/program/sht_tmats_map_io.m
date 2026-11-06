function varargout = sht_tmats_map_io(action, varargin)
%SHT_TMATS_MAP_IO 读写本项目使用的 GTESS/T-MATS 文本特性图。
%
% 本函数只负责文件格式，不包含任何部件拆分或拟合假设。支持：
%   map = sht_tmats_map_io('readCompressor', fileName)
%   map = sht_tmats_map_io('readTurbine', fileName)
%   sht_tmats_map_io('writeCompressor', fileName, map)
%   sht_tmats_map_io('writeTurbine', fileName, map)
%
% 特性图每个数据块首个数采用“行数.列数”的紧凑编码。例如 15.021
% 表示 15 行、21 列（均包含坐标轴行/列）。涡轮图还支持当前 C 程序
% 已实现的可选 PressureRatioSurface 二维压比曲面。

switch lower(action)
    case 'readcompressor'
        varargout{1} = local_read_compressor(varargin{1});
    case 'readturbine'
        varargout{1} = local_read_turbine(varargin{1});
    case 'writecompressor'
        local_write_compressor(varargin{:});
    case 'writeturbine'
        local_write_turbine(varargin{:});
    case 'compare'
        varargout{1} = local_compare_maps(varargin{:});
    otherwise
        error('sht_tmats_map_io:UnknownAction', ...
            '不支持的特性图读写动作：%s。', action);
end
end

function map = local_read_compressor(fileName)
lines = local_read_all_lines(fileName);
blockNames = {'Mass Flow', 'Efficiency', 'Pressure Ratio', 'Surge Line'};

massFlow = local_read_numeric_block(lines, 'Mass Flow', blockNames);
efficiency = local_read_numeric_block(lines, 'Efficiency', blockNames);
pressureRatio = local_read_numeric_block(lines, 'Pressure Ratio', blockNames);

local_assert_same_grid(massFlow, efficiency, 'Mass Flow', 'Efficiency');
local_assert_same_grid(massFlow, pressureRatio, 'Mass Flow', 'Pressure Ratio');

map = struct();
map.kind = 'compressor';
map.fileName = fileName;
map.title = strtrim(lines{1});
map.reynolds = strtrim(lines{2});
map.preambleLines = local_extract_preamble(lines, blockNames);
map.nc = massFlow.rowAxis;
map.path = massFlow.colAxis;
map.Wc = massFlow.values;
map.Eff = efficiency.values;
map.PR = pressureRatio.values;

if local_has_block(lines, 'Surge Line')
    surge = local_read_numeric_block(lines, 'Surge Line', blockNames);
    if size(surge.raw, 1) ~= 2
        error('sht_tmats_map_io:BadSurgeLine', ...
            '压气机喘振线必须为两行，文件：%s。', fileName);
    end
    map.surgeWc = surge.raw(1, 2:end);
    map.surgePR = surge.raw(2, 2:end);
    map.surgeDummy = surge.raw(2, 1);
else
    map.surgeWc = [];
    map.surgePR = [];
    map.surgeDummy = 1.0;
end

local_validate_axes(map.nc, '修正转速', fileName);
local_validate_axes(map.path, 'Rline', fileName);
end

function map = local_read_turbine(fileName)
lines = local_read_all_lines(fileName);
blockNames = {'Min Pressure Ratio', 'Max Pressure Ratio', ...
    'Min Enthalpy Drop', 'Max Enthalpy Drop', 'Mass Flow', ...
    'Efficiency', 'PressureRatioSurface'};

minBlockName = 'Min Pressure Ratio';
maxBlockName = 'Max Pressure Ratio';
if ~local_has_block(lines, minBlockName)
    minBlockName = 'Min Enthalpy Drop';
    maxBlockName = 'Max Enthalpy Drop';
end

minimum = local_read_numeric_block(lines, minBlockName, blockNames);
maximum = local_read_numeric_block(lines, maxBlockName, blockNames);
massFlow = local_read_numeric_block(lines, 'Mass Flow', blockNames);
efficiency = local_read_numeric_block(lines, 'Efficiency', blockNames);
local_assert_same_grid(massFlow, efficiency, 'Mass Flow', 'Efficiency');

map = struct();
map.kind = 'turbine';
map.fileName = fileName;
map.title = strtrim(lines{1});
map.reynolds = strtrim(lines{2});
map.preambleLines = local_extract_preamble(lines, blockNames);
map.minBlockName = minBlockName;
map.maxBlockName = maxBlockName;
map.nc = minimum.raw(1, 2:end);
map.minPR = minimum.raw(2, 2:end);
map.maxPR = maximum.raw(2, 2:end);
map.minDummy = minimum.raw(2, 1);
map.maxDummy = maximum.raw(2, 1);
map.path = massFlow.colAxis;
map.Wc = massFlow.values;
map.Eff = efficiency.values;

if numel(map.nc) ~= size(map.Wc, 1)
    error('sht_tmats_map_io:GridMismatch', ...
        '涡轮压比端点与流量表转速线数量不一致，文件：%s。', fileName);
end

if local_has_block(lines, 'PressureRatioSurface')
    fullPR = local_read_numeric_block(lines, ...
        'PressureRatioSurface', blockNames);
    local_assert_same_grid(massFlow, fullPR, ...
        'Mass Flow', 'PressureRatioSurface');
    map.PR = fullPR.values;
    map.hasFullPRSurface = true;
else
    map.PR = repmat(map.minPR(:), 1, numel(map.path)) + ...
        (repmat(map.maxPR(:), 1, numel(map.path)) - ...
        repmat(map.minPR(:), 1, numel(map.path))) .* ...
        repmat(map.path(:).', numel(map.nc), 1);
    map.hasFullPRSurface = false;
end

local_validate_axes(map.nc, '修正转速', fileName);
local_validate_axes(map.path, 'beta', fileName);
end

function local_write_compressor(fileName, map, fmt)
if nargin < 3
    fmt = '%14.9f';
end
local_validate_map_matrix(map, 'Wc');
local_validate_map_matrix(map, 'Eff');
local_validate_map_matrix(map, 'PR');

fid = local_open_output(fileName);
cleanup = onCleanup(@() fclose(fid));
local_write_preamble(fid, map);
local_write_2d_table(fid, 'Mass Flow', map.nc, map.path, map.Wc, fmt);
local_write_2d_table(fid, 'Efficiency', map.nc, map.path, map.Eff, fmt);
local_write_2d_table(fid, 'Pressure Ratio', map.nc, map.path, map.PR, fmt);

if isfield(map, 'surgeWc') && ~isempty(map.surgeWc)
    if numel(map.surgeWc) ~= numel(map.nc) || ...
            numel(map.surgePR) ~= numel(map.nc)
        error('sht_tmats_map_io:BadSurgeLine', ...
            '输出喘振线点数必须与压气机转速线数量一致。');
    end
    raw = zeros(2, numel(map.nc) + 1);
    raw(1, 1) = local_encode_dimension(2, numel(map.nc) + 1);
    raw(1, 2:end) = map.surgeWc(:).';
    raw(2, 1) = map.surgeDummy;
    raw(2, 2:end) = map.surgePR(:).';
    local_write_raw_table(fid, 'Surge Line', raw, fmt);
end
end

function local_write_turbine(fileName, map, fmt)
if nargin < 3
    fmt = '%14.9f';
end
local_validate_map_matrix(map, 'Wc');
local_validate_map_matrix(map, 'Eff');
if isfield(map, 'PR') && ~isempty(map.PR)
    local_validate_map_matrix(map, 'PR');
end

fid = local_open_output(fileName);
cleanup = onCleanup(@() fclose(fid));
local_write_preamble(fid, map);

minRaw = zeros(2, numel(map.nc) + 1);
minRaw(1, 1) = local_encode_dimension(2, numel(map.nc) + 1);
minRaw(1, 2:end) = map.nc(:).';
minRaw(2, 1) = map.minDummy;
minRaw(2, 2:end) = map.minPR(:).';
local_write_raw_table(fid, map.minBlockName, minRaw, fmt);

maxRaw = zeros(2, numel(map.nc) + 1);
maxRaw(1, 1) = local_encode_dimension(2, numel(map.nc) + 1);
maxRaw(1, 2:end) = map.nc(:).';
maxRaw(2, 1) = map.maxDummy;
maxRaw(2, 2:end) = map.maxPR(:).';
local_write_raw_table(fid, map.maxBlockName, maxRaw, fmt);

local_write_2d_table(fid, 'Mass Flow', map.nc, map.path, map.Wc, fmt);
local_write_2d_table(fid, 'Efficiency', map.nc, map.path, map.Eff, fmt);

if isfield(map, 'PR') && ~isempty(map.PR)
    % 保持原write合同：调用方可能已修改PR，而未更改读取时的来源标志。
    % 当前 C 读图器通过无空格关键字 PressureRatioSurface 识别该可选块。
    local_write_2d_table(fid, 'PressureRatioSurface', ...
        map.nc, map.path, map.PR, fmt);
end
end

function preamble = local_extract_preamble(lines, knownNames)
% 数据块之前的文本属于特性图文件合同。除标题和雷诺数说明外，部分
% Gasturb图还包含设计点或图谱来源说明，写回时不能静默丢失。
firstBlock = numel(lines) + 1;
for k = 1:numel(lines)
    if local_is_known_block_line(lines{k}, knownNames)
        firstBlock = k;
        break;
    end
end
preamble = lines(1:firstBlock - 1);
while ~isempty(preamble) && isempty(strtrim(preamble{end}))
    preamble(end) = [];
end
end

function local_write_preamble(fid, map)
if isfield(map, 'preambleLines') && ~isempty(map.preambleLines)
    lines = map.preambleLines;
else
    lines = {map.title, map.reynolds};
end
for k = 1:numel(lines)
    fprintf(fid, '%s\n', lines{k});
end
end

function comparison = local_compare_maps(first, second, tolerance)
% 比较数值语义而非空格和换行。原图冻结检查使用零容差或很小的绝对
% 容差；写出回读检查默认允许文本十进制转换带来的机器精度舍入。
if nargin < 3 || isempty(tolerance)
    tolerance = 32 * eps;
end
if ~strcmp(first.kind, second.kind)
    error('sht_tmats_map_io:KindMismatch', ...
        '不能比较不同类型的特性图：%s 与 %s。', first.kind, second.kind);
end

fields = {'nc', 'path', 'Wc', 'Eff'};
if strcmp(first.kind, 'compressor')
    fields = [fields, {'PR', 'surgeWc', 'surgePR'}];
else
    fields = [fields, {'minPR', 'maxPR'}];
    if first.hasFullPRSurface || second.hasFullPRSurface
        fields = [fields, {'PR'}];
    end
end

comparison = struct();
comparison.fields = fields;
comparison.maxAbsoluteByField = zeros(size(fields));
comparison.sameSize = true(size(fields));
for k = 1:numel(fields)
    name = fields{k};
    comparison.sameSize(k) = isequal(size(first.(name)), size(second.(name)));
    if comparison.sameSize(k) && ~isempty(first.(name))
        comparison.maxAbsoluteByField(k) = ...
            max(abs(first.(name)(:) - second.(name)(:)));
    elseif comparison.sameSize(k)
        comparison.maxAbsoluteByField(k) = 0;
    else
        comparison.maxAbsoluteByField(k) = Inf;
    end
end
% 兼容合入前创建的map结构；新增比较功能不要求旧调用方补字段。
firstPreamble = {first.title, first.reynolds};
secondPreamble = {second.title, second.reynolds};
if isfield(first,'preambleLines'),firstPreamble=first.preambleLines;end
if isfield(second,'preambleLines'),secondPreamble=second.preambleLines;end
comparison.preambleEqual = isequal(firstPreamble(:), secondPreamble(:));
comparison.maxAbsolute = max(comparison.maxAbsoluteByField);
comparison.tolerance = tolerance;
comparison.accepted = all(comparison.sameSize) && ...
    comparison.preambleEqual && comparison.maxAbsolute <= tolerance;
end

function lines = local_read_all_lines(fileName)
if ~exist(fileName, 'file')
    error('sht_tmats_map_io:MissingFile', '特性图不存在：%s。', fileName);
end
text = fileread(fileName);
lines = regexp(text, '\r\n|\n|\r', 'split');
if ~isempty(lines) && isempty(lines{end})
    lines(end) = [];
end
if numel(lines) < 3
    error('sht_tmats_map_io:BadFile', '特性图内容过短：%s。', fileName);
end
end

function block = local_read_numeric_block(lines, blockName, knownNames)
lineIndex = local_find_block_line(lines, blockName);
if isempty(lineIndex)
    error('sht_tmats_map_io:MissingBlock', ...
        '特性图缺少数据块“%s”。', blockName);
end

stopLine = numel(lines) + 1;
for k = (lineIndex + 1):numel(lines)
    if local_is_known_block_line(lines{k}, knownNames)
        stopLine = k;
        break;
    end
end

numbers = [];
for k = (lineIndex + 1):(stopLine - 1)
    row = sscanf(lines{k}, '%f').';
    numbers = [numbers, row]; %#ok<AGROW>
end
if isempty(numbers)
    error('sht_tmats_map_io:EmptyBlock', ...
        '数据块“%s”中没有数值。', blockName);
end

[rows, columns] = local_decode_dimension(numbers(1));
numberNeeded = rows * columns;
if numel(numbers) < numberNeeded
    error('sht_tmats_map_io:ShortBlock', ...
        '数据块“%s”需要 %d 个数值，实际只有 %d 个。', ...
        blockName, numberNeeded, numel(numbers));
end

raw = reshape(numbers(1:numberNeeded), [columns, rows]).';
block = struct('raw', raw, 'rows', rows, 'columns', columns, ...
    'colAxis', raw(1, 2:end), 'rowAxis', raw(2:end, 1).', ...
    'values', raw(2:end, 2:end));
end

function local_assert_same_grid(first, second, firstName, secondName)
tol = 1e-10;
if numel(first.rowAxis) ~= numel(second.rowAxis) || ...
        numel(first.colAxis) ~= numel(second.colAxis) || ...
        max(abs(first.rowAxis - second.rowAxis)) > tol || ...
        max(abs(first.colAxis - second.colAxis)) > tol
    error('sht_tmats_map_io:GridMismatch', ...
        '数据块“%s”和“%s”的坐标网格不一致。', firstName, secondName);
end
end

function lineIndex = local_find_block_line(lines, blockName)
lineIndex = [];
for k = 1:numel(lines)
    if strcmpi(strtrim(lines{k}), blockName)
        lineIndex = k;
        return;
    end
end
end

function tf = local_has_block(lines, blockName)
tf = ~isempty(local_find_block_line(lines, blockName));
end

function tf = local_is_known_block_line(line, knownNames)
name = strtrim(line);
tf = any(cellfun(@(candidate) strcmpi(name, candidate), knownNames));
end

function [rows, columns] = local_decode_dimension(code)
rows = floor(code + 1e-9);
columns = round((code - rows) * 1000);
if rows < 1 || columns < 1
    error('sht_tmats_map_io:BadDimension', ...
        '非法的特性图维数编码：%.12g。', code);
end
end

function code = local_encode_dimension(rows, columns)
if rows > 999 || columns > 999
    error('sht_tmats_map_io:DimensionTooLarge', ...
        '紧凑维数编码仅支持不超过 999 行/列。');
end
code = rows + columns / 1000;
end

function fid = local_open_output(fileName)
parent = fileparts(fileName);
if ~isempty(parent) && ~exist(parent, 'dir')
    mkdir(parent);
end
fid = fopen(fileName, 'w');
if fid < 0
    error('sht_tmats_map_io:OpenFailed', ...
        '无法创建特性图：%s。', fileName);
end
end

function local_write_2d_table(fid, blockName, rowAxis, colAxis, values, fmt)
raw = zeros(numel(rowAxis) + 1, numel(colAxis) + 1);
raw(1, 1) = local_encode_dimension(size(raw, 1), size(raw, 2));
raw(1, 2:end) = colAxis(:).';
raw(2:end, 1) = rowAxis(:);
raw(2:end, 2:end) = values;
local_write_raw_table(fid, blockName, raw, fmt);
end

function local_write_raw_table(fid, blockName, raw, fmt)
fprintf(fid, '%s\n', blockName);
for rowIndex = 1:size(raw, 1)
    local_write_wrapped_row(fid, raw(rowIndex, :), fmt, 5);
end
fprintf(fid, ' \n');
end

function local_write_wrapped_row(fid, row, fmt, valuesPerLine)
for k = 1:numel(row)
    if k > 1 && mod(k - 1, valuesPerLine) == 0
        fprintf(fid, '\n');
    elseif k > 1
        % 数值之间必须由空白分隔，不能隐含依赖调用方的 fmt 自带字段宽度。
        % 例如 %.15g 不带前导空格，旧实现会把相邻数值粘成一个记号，
        % 导致文件头维数正确但读回数值个数不足。
        fprintf(fid, ' ');
    end
    fprintf(fid, fmt, row(k));
end
fprintf(fid, '\n');
end

function local_validate_axes(axisValues, axisName, fileName)
if any(~isfinite(axisValues)) || any(diff(axisValues) <= 0)
    error('sht_tmats_map_io:BadAxis', ...
        '%s坐标必须为有限且严格递增，文件：%s。', axisName, fileName);
end
end

function local_validate_map_matrix(map, fieldName)
expected = [numel(map.nc), numel(map.path)];
actual = size(map.(fieldName));
if ~isequal(actual, expected) || any(~isfinite(map.(fieldName)(:)))
    error('sht_tmats_map_io:BadMatrix', ...
        '字段 %s 的尺寸应为 [%d %d] 且数值必须有限。', ...
        fieldName, expected(1), expected(2));
end
end
