% DMG_SETUP  仿真程序信号采集脚本（AFO_V_1Disp 黄金用例）
% 注意：本文件是脚本（不是 function），在 base workspace 执行，
% 能直接访问 runner 设置的 dmg_modelName、NpReferenceRpm 等变量。
%
% 由 MatlabSimulationRunner 在 load_system 之后调用。runner 已在 base workspace
% 设置好以下变量：
%   dmg_modelName      —— Simulink 模型名（不含扩展名）
%   NpReferenceRpm     —— 转速指令（来自前端 npCommand 参数）
%   MkpReferenceNm     —— 负载功率（来自前端 loadPower 参数）
%   Ts                 —— 固定步长（若前端传入）
%
% 本脚本职责：
%   1. 计算派生变量（AFO 涡轴发动机模型专属的物理关系）
%   2. 添加 To Workspace 块（仿真结束后变量出现在 base workspace）
%   3. 配置信号日志 DataLogging（用于实时曲线显示）
%   4. 在 base workspace 留下 dmg_cols（cell 数组，元素为信号名）
%      runner 据此知道要取哪些列
%
% 仿真结束后 runner 在 close() 里 close_system 不保存，不污染原模型。

m = dmg_modelName;

%% 1. 派生变量（每次运行都要重算，依赖用户传入的参数）
PTReferenceLoadPowerW = MkpReferenceNm * (NpReferenceRpm * pi / 30);
Power_cmd = PTReferenceLoadPowerW;
NpDem = NpReferenceRpm;
if exist('NgReferenceRpm', 'var'), NgMax = NgReferenceRpm * 1.05; end
if exist('WfReferenceKgps', 'var'), WfMax = WfReferenceKgps * 2; WfMin = WfReferenceKgps * 0.01; end

% 重置取数游标和映射（每次运行都要重置）
dmg_cursor = 0; dmg_mapNames = {}; dmg_layout = cell(0,3);

% dmg_skipBlocks = true 时跳过加块和 DataLogging 配置（模型已配置过，复用）
if exist('dmg_skipBlocks', 'var') && dmg_skipBlocks
  fprintf('dmg_setup: 跳过加块和DataLogging（模型已配置过）\n');
  return;
end

%% 2. 添加 To Workspace 块
dmg_okSignals = {};

% 2a. 核心信号：在块所在子系统内添加 To Workspace 块
dmg_wsSignals = {
  'Np',    [m '/Turboshaft Engine Control System/Np'];
  'Ng',    [m '/Turboshaft Engine Control System/Ng'];
  'NpDem', [m '/Turboshaft Engine Control System/NpDem'];
  'T45',   [m '/Turboshaft Engine Control System/T45'];
  'Mkp',   [m '/Turboshaft Engine Control System/Mkp'];
  'Wf_cmd',[m '/Fuel System/Wf_cmd'];
};
for dmg_i = 1:size(dmg_wsSignals, 1)
  try
    dmg_sigName = dmg_wsSignals{dmg_i, 1}; dmg_blockPath = dmg_wsSignals{dmg_i, 2};
    dmg_parent = get_param(dmg_blockPath, 'Parent');
    dmg_srcName = get_param(dmg_blockPath, 'Name');
    dmg_twName = ['ToWS_' dmg_sigName]; dmg_twPath = [dmg_parent '/' dmg_twName];
    dmg_ph = get_param(dmg_blockPath, 'PortHandles');
    if isempty(dmg_ph.Outport); continue; end
    if getSimulinkBlockHandle(dmg_twPath) ~= -1; delete_block(dmg_twPath); end
    dmg_pos = get_param(dmg_blockPath, 'Position');
    add_block('simulink/Sinks/To Workspace', dmg_twPath, ...
      'Position', [dmg_pos(3)+80, dmg_pos(2), dmg_pos(3)+120, dmg_pos(2)+30], ...
      'VariableName', dmg_sigName, 'SaveFormat', 'Array', ...
      'MaxDataPoints', '1000000', 'Decimation', '1');
    add_line(dmg_parent, [dmg_srcName '/1'], [dmg_twName '/1']);
    dmg_okSignals{end+1} = dmg_sigName;
  catch; try; delete_block(dmg_twPath); catch; end; end
end

% 2b. CLP（Inport 在控制系统子系统内部）
try
  dmg_clpPath = [m '/Turboshaft Engine Control System/CLP'];
  dmg_clpParent = get_param(dmg_clpPath, 'Parent');
  dmg_clpName = get_param(dmg_clpPath, 'Name');
  dmg_twName = 'ToWS_CLP'; dmg_twPath = [dmg_clpParent '/' dmg_twName];
  if getSimulinkBlockHandle(dmg_twPath) ~= -1; delete_block(dmg_twPath); end
  dmg_pos = get_param(dmg_clpPath, 'Position');
  add_block('simulink/Sinks/To Workspace', dmg_twPath, ...
    'Position', [dmg_pos(3)+80, dmg_pos(2), dmg_pos(3)+120, dmg_pos(2)+30], ...
    'VariableName', 'CLP', 'SaveFormat', 'Array', 'MaxDataPoints', '1000000', 'Decimation', '1');
  add_line(dmg_clpParent, [dmg_clpName '/1'], [dmg_twName '/1']);
  dmg_okSignals{end+1} = 'CLP';
catch; try; delete_block(dmg_twPath); catch; end; end

% 2c. Goto 标签信号：From + To Workspace
dmg_gotoAll = {'Np_fbk','Ng_fbk','Mkp_fbk','T45_fbk', ...
  'Ngc','Wf_kgps','WfProxyCmd', ...
  'Pt3_fbk','Tt3_fbk', ...
  'P1','T1','P45','P4','P5','T5','T4', ...
  'Oil_AirTemp_C', ...
  'dp_fuel','lock_meter','xm_ref_sb', ...
  'xm_cmd_m','lock_igv','xd_cmd', ...
  'shutdown','xm','xd'};
for dmg_i = 1:numel(dmg_gotoAll)
  try
    dmg_sigName = dmg_gotoAll{dmg_i}; dmg_gotoTag = dmg_gotoAll{dmg_i};
    dmg_twName = ['ToWS_From_' dmg_sigName]; dmg_fromName = ['From_' dmg_sigName];
    dmg_twPath = [m '/' dmg_twName]; dmg_fromPath = [m '/' dmg_fromName];
    if getSimulinkBlockHandle(dmg_twPath) ~= -1; delete_block(dmg_twPath); end
    if getSimulinkBlockHandle(dmg_fromPath) ~= -1; delete_block(dmg_fromPath); end
    add_block('simulink/Signal Routing/From', dmg_fromPath, 'GotoTag', dmg_gotoTag, ...
      'Position', [100, 100+dmg_i*40, 200, 130+dmg_i*40]);
    add_block('simulink/Sinks/To Workspace', dmg_twPath, 'VariableName', dmg_sigName, ...
      'SaveFormat', 'Array', 'MaxDataPoints', '1000000', 'Decimation', '1', ...
      'Position', [250, 100+dmg_i*40, 350, 130+dmg_i*40]);
    add_line(m, [dmg_fromName '/1'], [dmg_twName '/1']);
    dmg_okSignals{end+1} = dmg_sigName;
  catch; try; delete_block(dmg_twPath); catch; end; try; delete_block(dmg_fromPath); catch; end; end
end

% 2d. Fuel System Wf 输出（子系统端口）
try
  dmg_fsPath = [m '/Fuel System'];
  dmg_fsPH = get_param(dmg_fsPath, 'PortHandles');
  dmg_fsPos = get_param(dmg_fsPath, 'Position');
  dmg_twName = 'ToWS_Wf'; dmg_twPath = [m '/' dmg_twName];
  if getSimulinkBlockHandle(dmg_twPath) ~= -1; delete_block(dmg_twPath); end
  add_block('simulink/Sinks/To Workspace', dmg_twPath, ...
    'Position', [dmg_fsPos(3)+80, dmg_fsPos(2), dmg_fsPos(3)+120, dmg_fsPos(2)+30], ...
    'VariableName', 'Wf', 'SaveFormat', 'Array', 'MaxDataPoints', '1000000', 'Decimation', '1');
  add_line(m, dmg_fsPH.Outport(1), get_param(dmg_twPath, 'PortHandles').Inport(1));
  dmg_okSignals{end+1} = 'Wf';
catch; try; delete_block(dmg_twPath); catch; end; end

% 2e. 空气系统输出（通过子系统 Outport）
try
  dmg_airBlocks = find_system(m, 'RegExp', 'on', 'Name', 'G0[1-8]_.*W_kgps');
  dmg_airParent = '';
  for dmg_i = 1:numel(dmg_airBlocks)
    dmg_p = get_param(dmg_airBlocks{dmg_i}, 'Parent');
    if strcmp(get_param(dmg_p, 'Parent'), m); dmg_airParent = dmg_p; break; end
  end
  if ~isempty(dmg_airParent)
    dmg_subPH = get_param(dmg_airParent, 'PortHandles');
    dmg_airOuts = find_system(dmg_airParent, 'SearchDepth', 1, 'BlockType', 'Outport');
    dmg_subPos = get_param(dmg_airParent, 'Position');
    for dmg_i = 1:numel(dmg_airOuts)
      try
        dmg_outName = get_param(dmg_airOuts{dmg_i}, 'Name');
        dmg_twName = ['ToWS_' dmg_outName]; dmg_twPath = [m '/' dmg_twName];
        if getSimulinkBlockHandle(dmg_twPath) ~= -1; delete_block(dmg_twPath); end
        dmg_yOff = dmg_subPos(2) + dmg_i * 35;
        add_block('simulink/Sinks/To Workspace', dmg_twPath, ...
          'Position', [dmg_subPos(3)+80, dmg_yOff, dmg_subPos(3)+120, dmg_yOff+30], ...
          'VariableName', dmg_outName, 'SaveFormat', 'Array', 'MaxDataPoints', '1000000', 'Decimation', '1');
        add_line(m, dmg_subPH.Outport(dmg_i), get_param(dmg_twPath, 'PortHandles').Inport(1));
        dmg_okSignals{end+1} = dmg_outName;
      catch; try; delete_block(dmg_twPath); catch; end; end
    end
  end
catch; end

% 2f. 滑油系统输出（28 个 Outport 的子系统）
dmg_oilVarNames = {'Q_BearingA','Q_BearingB','Q_AirOil','Q_Accessory', ...
  'QA','QB','PA','PB','ToutA','ToutB', ...
  'QretA','QretB','QgenA','QgenB', ...
  'FuelOilCooler_Q','FuelOilCooler_FuelTout', ...
  'AirOilCooler_Pin_Pa','AirOilCooler_Pout_Pa', ...
  'FuelOilCooler_Pin_Pa','FuelOilCooler_Pout_Pa', ...
  'CavityState8_PaK','SealLeak4_kgps','VentFlow3_kgps', ...
  'SealDeltaP4_Pa','VentDeltaP2_Pa','MassResidual2_kgps', ...
  'FuelOil2_ToutC_QkW','AirOil2_ToutC_QkW'};
try
  dmg_allSubs = find_system(m, 'SearchDepth', 1, 'BlockType', 'SubSystem');
  dmg_oilSys = '';
  for dmg_i = 1:numel(dmg_allSubs)
    dmg_subOuts = find_system(dmg_allSubs{dmg_i}, 'SearchDepth', 1, 'BlockType', 'Outport');
    if numel(dmg_subOuts) == 28; dmg_oilSys = dmg_allSubs{dmg_i}; break; end
  end
  if ~isempty(dmg_oilSys)
    dmg_oilPH = get_param(dmg_oilSys, 'PortHandles');
    dmg_oilOuts = find_system(dmg_oilSys, 'SearchDepth', 1, 'BlockType', 'Outport');
    dmg_oilPos = get_param(dmg_oilSys, 'Position');
    for dmg_i = 1:numel(dmg_oilOuts)
      try
        dmg_varName = dmg_oilVarNames{dmg_i};
        dmg_twName = ['ToWS_' dmg_varName]; dmg_twPath = [m '/' dmg_twName];
        if getSimulinkBlockHandle(dmg_twPath) ~= -1; delete_block(dmg_twPath); end
        dmg_yOff = dmg_oilPos(2) + dmg_i * 25;
        add_block('simulink/Sinks/To Workspace', dmg_twPath, ...
          'Position', [dmg_oilPos(3)+80, dmg_yOff, dmg_oilPos(3)+120, dmg_yOff+20], ...
          'VariableName', dmg_varName, 'SaveFormat', 'Array', 'MaxDataPoints', '1000000', 'Decimation', '1');
        add_line(m, dmg_oilPH.Outport(dmg_i), get_param(dmg_twPath, 'PortHandles').Inport(1));
        dmg_okSignals{end+1} = dmg_varName;
      catch; try; delete_block(dmg_twPath); catch; end; end
    end
  end
catch; end

% 2g. 发动机 SFunc 额外输出（HPC_u6, HPT_y16, LPT_y16）
try
  dmg_sfuncBlocks = find_system(m, 'SearchDepth', 3, 'BlockType', 'S-Function');
  for dmg_i = 1:numel(dmg_sfuncBlocks)
    try
      dmg_fn = get_param(dmg_sfuncBlocks{dmg_i}, 'FunctionName');
      if strcmp(dmg_fn, 'SFunc_EngModel')
        dmg_engPH = get_param(dmg_sfuncBlocks{dmg_i}, 'PortHandles');
        dmg_engPos = get_param(dmg_sfuncBlocks{dmg_i}, 'Position');
        dmg_engParent = get_param(dmg_sfuncBlocks{dmg_i}, 'Parent');
        dmg_demuxName = 'ToWS_Demux_Extra'; dmg_demuxPath = [dmg_engParent '/' dmg_demuxName];
        if getSimulinkBlockHandle(dmg_demuxPath) ~= -1; delete_block(dmg_demuxPath); end
        add_block('simulink/Signal Routing/Demux', dmg_demuxPath, 'Outputs', '20', ...
          'Position', [dmg_engPos(3)+20, dmg_engPos(2), dmg_engPos(3)+40, dmg_engPos(2)+400]);
        add_line(dmg_engParent, dmg_engPH.Outport(1), get_param(dmg_demuxPath, 'PortHandles').Inport(1));
        dmg_extraVars = {'HPC_u6', 'HPT_y16', 'LPT_y16'};
        dmg_extraIdx = [13, 14, 15];
        for dmg_j = 1:3
          dmg_twName = ['ToWS_' dmg_extraVars{dmg_j}]; dmg_twPath = [dmg_engParent '/' dmg_twName];
          if getSimulinkBlockHandle(dmg_twPath) ~= -1; delete_block(dmg_twPath); end
          add_block('simulink/Sinks/To Workspace', dmg_twPath, ...
            'VariableName', dmg_extraVars{dmg_j}, 'SaveFormat', 'Array', ...
            'MaxDataPoints', '1000000', 'Decimation', '1', ...
            'Position', [dmg_engPos(3)+80, dmg_engPos(2)+(dmg_j-1)*40, dmg_engPos(3)+120, dmg_engPos(2)+30+(dmg_j-1)*40]);
          add_line(dmg_engParent, [dmg_demuxName '/' num2str(dmg_extraIdx(dmg_j))], [dmg_twName '/1']);
          dmg_okSignals{end+1} = dmg_extraVars{dmg_j};
        end
        break;
      end
    catch; end
  end
catch; end

%% 3. 配置信号日志 DataLogging
set_param(m, 'SignalLogging', 'on');
set_param(m, 'SignalLoggingName', 'logsout');

% 清掉模型里已有的 DataLogging，保证 logsout 只包含我们关心的信号
dmg_ports = find_system(m, 'FindAll', 'on', 'Type', 'Port');
for dmg_i = 1:numel(dmg_ports)
  try; if strcmp(get_param(dmg_ports(dmg_i),'DataLogging'),'on'); set_param(dmg_ports(dmg_i),'DataLogging','off'); end; catch; end
end

dmg_cols = {}; dmg_paths = {};

% 核心信号 + 兜底信号：块路径已知
dmg_req = {
  'Np',    [m '/Turboshaft Engine Control System/Np'];
  'Ng',    [m '/Turboshaft Engine Control System/Ng'];
  'NpDem', [m '/Turboshaft Engine Control System/NpDem'];
  'T45',   [m '/Turboshaft Engine Control System/T45'];
  'Mkp',   [m '/Turboshaft Engine Control System/Mkp'];
  'Wf_cmd',[m '/Fuel System/Wf_cmd'];
  'CLP',   [m '/Turboshaft Engine Control System/CLP'];
  'Wf',    [m '/Fuel System'];
};

% Goto 信号：先找到 From 块再拿其输出端口
dmg_goto = {'Np_fbk','Ng_fbk','Mkp_fbk','T45_fbk','Wf_kgps','WfProxyCmd'};
for dmg_i = 1:numel(dmg_goto)
  try
    dmg_from = find_system(m, 'BlockType', 'From', 'GotoTag', dmg_goto{dmg_i});
    if ~isempty(dmg_from); dmg_req(end+1,:) = {dmg_goto{dmg_i}, dmg_from{1}}; end
  catch; end
end

% 在源端口上开启 DataLogging
for dmg_i = 1:size(dmg_req,1)
  try
    dmg_ph = get_param(dmg_req{dmg_i,2}, 'PortHandles');
    if isempty(dmg_ph.Outport); continue; end
    set_param(dmg_ph.Outport(1), 'DataLogging', 'on');
    try; set_param(dmg_ph.Outport(1), 'DataLoggingNameMode', 'Custom'); catch; end
    set_param(dmg_ph.Outport(1), 'DataLoggingName', dmg_req{dmg_i,1});
    dmg_cols{end+1} = dmg_req{dmg_i,1}; dmg_paths{end+1} = dmg_req{dmg_i,2};
  catch; end
end

dmg_cursor = 0; dmg_mapNames = {};

% 把 To Workspace 块对应的信号也加入 DataLogging。
% DataLogging 只能设在输出端口上，通过 PortConnectivity 找到 ToWorkspace Inport
% 的信号源端口（上游 Outport），在那个 Outport 上开启 DataLogging。
dmg_twBlocks = find_system(m, 'BlockType', 'ToWorkspace');
dmg_twOk = 0; dmg_twFail = 0;
dmg_firstErr = '';
for dmg_i = 1:numel(dmg_twBlocks)
  try
    dmg_twName = char(get_param(dmg_twBlocks{dmg_i}, 'VariableName'));
    if isempty(dmg_twName); dmg_twFail = dmg_twFail + 1; continue; end
    % 跳过已配置过的信号
    dmg_alreadyLogged = false;
    for dmg_j = 1:numel(dmg_cols); if strcmp(dmg_cols{dmg_j}, dmg_twName); dmg_alreadyLogged = true; break; end; end
    if dmg_alreadyLogged; continue; end
    % 通过 PortConnectivity 找到 ToWorkspace Inport 的信号源端口
    dmg_pc = get_param(dmg_twBlocks{dmg_i}, 'PortConnectivity');
    dmg_srcBlockH = dmg_pc(1).SrcBlock;
    dmg_srcPortIdx = dmg_pc(1).SrcPort;
    if isempty(dmg_srcBlockH) || dmg_srcBlockH == 0 || dmg_srcBlockH == -1
      dmg_twFail = dmg_twFail + 1; continue;
    end
    dmg_srcPH = get_param(dmg_srcBlockH, 'PortHandles');
    dmg_srcPortIdx1 = dmg_srcPortIdx + 1;
    if isempty(dmg_srcPH.Outport) || numel(dmg_srcPH.Outport) < dmg_srcPortIdx1
      dmg_twFail = dmg_twFail + 1; continue;
    end
    dmg_srcPortH = dmg_srcPH.Outport(dmg_srcPortIdx1);
    set_param(dmg_srcPortH, 'DataLogging', 'on');
    try; set_param(dmg_srcPortH, 'DataLoggingNameMode', 'Custom'); catch; end
    set_param(dmg_srcPortH, 'DataLoggingName', dmg_twName);
    dmg_srcBlockPath = getfullname(dmg_srcBlockH);
    dmg_cols{end+1} = dmg_twName; dmg_paths{end+1} = dmg_srcBlockPath;
    dmg_twOk = dmg_twOk + 1;
  catch
    dmg_twFail = dmg_twFail + 1;
    if isempty(dmg_firstErr)
      [dmg_msg, dmg_id] = lasterr;
      dmg_firstErr = ['i=' num2str(dmg_i) ' name=' dmg_twName ' id=' dmg_id ' msg=' dmg_msg];
    end
  end
end
if isempty(dmg_firstErr); dmg_firstErr = 'none'; end

fprintf('dmg_setup 完成: ToWorkspace DataLogging 成功 %d 失败 %d, cols=%d, 首个错误: %s\n', ...
  dmg_twOk, dmg_twFail, numel(dmg_cols), dmg_firstErr);
