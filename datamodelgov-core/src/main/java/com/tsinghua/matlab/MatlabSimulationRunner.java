package com.tsinghua.matlab;

import com.mathworks.engine.MatlabEngine;
import com.tsinghua.util.SimTimeUtil;
import lombok.extern.slf4j.Slf4j;

import java.io.Closeable;
import java.io.File;
import java.io.FileWriter;
import java.io.PrintWriter;
import java.io.Writer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * 基于 MATLAB Engine API for Java（com.mathworks.engine.MatlabEngine）的仿真执行器。
 *
 * 与旧的 “matlab -batch + 阻塞 sim() + 渐进式回放” 方案相比：
 * - 常驻 MATLAB 会话：启动一次引擎，后续 cd/脚本/参数/仿真/取数都在同一个 workspace 中完成
 * - 真实实时曲线：用 set_param(model,'SimulationCommand','start') 异步启动仿真，
 *   仿真在 MATLAB 后台推进，Java 侧按节拍 WriteDataLogs + 读取 logsout 增量，边跑边推给前端
 * - 真实暂停/恢复：SimulationCommand pause / continue，仿真时间真的冻结（非回放节流）
 * - 真实停止：SimulationCommand stop，仿真立即终止并保留已记录数据
 * - 停止时间按固定步长对齐：StopTime = round(stopTime / Ts) * Ts
 *
 * 线程模型：所有引擎调用都通过单线程 executor 串行化（MVM 本身也是串行的），
 * pause/resume/stop 由 HTTP 线程投递命令后立即返回，不阻塞请求。
 */
@Slf4j
public class MatlabSimulationRunner implements Closeable {

    /** 实时数据回调（由 ProgramService 桥接到 LiveDataBuffer / SSE） */
    public interface LiveSink {
        /** 停止时间按固定步长对齐后回调，供前端校正时间轴上限 */
        void onStopTime(double alignedStopTime);

        void onHeaders(List<String> headers);

        void onRows(List<String[]> rows);

        /** MATLAB 日志行回调，供前端 footer 实时显示 */
        void onLog(String line);
    }

    /** 核心信号：名称 → 模型内块路径（相对模型名的后缀） */
    private static final String[][] CORE_SIGNALS = {
            {"Np", "/Turboshaft Engine Control System/Np"},
            {"Ng", "/Turboshaft Engine Control System/Ng"},
            {"NpDem", "/Turboshaft Engine Control System/NpDem"},
            {"T45", "/Turboshaft Engine Control System/T45"},
            {"Mkp", "/Turboshaft Engine Control System/Mkp"},
            {"Wf_cmd", "/Fuel System/Wf_cmd"},
            {"CLP", "/Turboshaft Engine Control System/CLP"},
    };
    /** Goto/From 标签信号：通过 From 块输出端口记录 */
    private static final String[] GOTO_SIGNALS = {
            "Np_fbk", "Ng_fbk", "Mkp_fbk", "T45_fbk", "Wf_kgps", "WfProxyCmd"
    };
    /** 兜底核心信号（子系统整体输出） */
    private static final String[][] TAIL_SIGNALS = {
            {"Wf", "/Fuel System"},
    };

    private static final long ENGINE_START_TIMEOUT_SEC = 300;
    private static final long INIT_TIMEOUT_SEC = 900;
    /** 单次引擎调用超时：仿真编译期间（1-3 分钟）调用会排队，需给足余量 */
    private static final long CALL_TIMEOUT_SEC = 1800;
    private static final long POLL_INTERVAL_MS = 100;

    private static volatile Boolean apiAvailable;
    private static volatile String configuredMatlabHome;

    /** 由 ProgramService 在启动时注入 application.yml 中的 matlab.home（可为空） */
    public static void configureMatlabHome(String home) {
        configuredMatlabHome = home;
    }

    private final File taskDir;
    private final String programDir;
    private final String preRunScript;
    private final String modelName;
    private final double requestedStopTime;
    private final String fixedStep;
    private final String npCommand;
    private final String loadPower;
    private final LiveSink sink;

    private final ExecutorService engineExec =
            Executors.newSingleThreadExecutor(r -> {
                Thread t = new Thread(r, "matlab-engine");
                t.setDaemon(true);
                return t;
            });
    private final AtomicBoolean userStopped = new AtomicBoolean(false);
    private final AtomicBoolean paused = new AtomicBoolean(false);
    private final List<String> csvColumns = new ArrayList<>();
    /** 取数计数：列名只在首次和每 N 次检测，减少引擎调用次数 */
    private int fetchCount = 0;
    private static final int COL_CHECK_INTERVAL = 50;

    private volatile MatlabEngine engine;
    private volatile double alignedStopTime;
    private volatile double lastSimTime;
    private PrintWriter matlabLog;

    private final MatlabEnginePool enginePool;

    public MatlabSimulationRunner(File taskDir, String programDir, String preRunScript, String modelName,
                                  double requestedStopTime, String fixedStep, String npCommand, String loadPower,
                                  LiveSink sink, MatlabEnginePool enginePool) {
        this.taskDir = taskDir;
        this.programDir = programDir;
        this.preRunScript = preRunScript;
        this.modelName = modelName;
        this.requestedStopTime = requestedStopTime;
        this.fixedStep = fixedStep;
        this.npCommand = npCommand;
        this.loadPower = loadPower;
        this.sink = sink;
        this.enginePool = enginePool;
        this.alignedStopTime = requestedStopTime;
    }

    /**
     * MATLAB Engine API 是否可用：engine.jar 在 classpath 上 且 nativemvm.dll 可加载。
     *
     * 关键点：用 Class.forName(name, false, loader) 不初始化 MatlabEngine 类，
     * 避免触发其 &lt;clinit&gt;——R2019b 的 MvmImpl 在原生库加载失败时会弹 Swing 对话框，
     * 在 headless 的 Spring Boot 进程里会抛 HeadlessException 刷屏。
     * 真正的引擎启动放到 worker 线程的 startMatlab() 调用里，失败由 run() 抛出并回退。
     */
    public static boolean isApiAvailable() {
        if (apiAvailable == null) {
            synchronized (MatlabSimulationRunner.class) {
                if (apiAvailable == null) {
                    apiAvailable = probeApiAvailable();
                }
            }
        }
        return apiAvailable;
    }

    private static boolean probeApiAvailable() {
        try {
            // 不初始化类，仅检查 engine.jar 是否在 classpath
            Class.forName("com.mathworks.engine.MatlabEngine", false,
                    MatlabSimulationRunner.class.getClassLoader());
        } catch (Throwable t) {
            log.warn("MATLAB Engine API 不可用（classpath 缺少 engine.jar）: {}", t.toString());
            return false;
        }
        // 注入 MATLAB 原生库搜索路径并试加载 nativemvm.dll；
        // 失败说明本机未装 MATLAB 或版本不匹配，调用方需回退
        return MatlabNativeLibrary.prepare(configuredMatlabHome);
    }

    public double getAlignedStopTime() {
        return alignedStopTime;
    }

    public double getLastSimTime() {
        return lastSimTime;
    }

    public boolean isUserStopped() {
        return userStopped.get();
    }

    public boolean isPaused() {
        return paused.get();
    }

    /**
     * 阻塞执行整个仿真流程：启动引擎 → 预配置 → 异步启动仿真 → 实时取数 → 结束后导出 signals.csv。
     * 抛出异常表示运行失败（异常信息已包含 MATLAB 报错内容）。
     */
    public void run() throws Exception {
        matlabLog = new PrintWriter(new FileWriter(new File(taskDir, "run.log"), true), true);
        try {
            startEngine();
            prepare();
            // 用户在 prepare 阶段点了停止：不启动仿真，直接导出（可能无数据）
            if (userStopped.get()) {
                logMatlab("用户在初始化阶段停止，跳过仿真启动");
                exportResults();
                return;
            }
            Future<Void> startFuture = call(() -> engine.evalAsync(
                    "set_param('" + esc(modelName) + "','SimulationCommand','start');"), 60, "发送仿真启动命令");
            logMatlab("仿真启动命令已发送（编译+初始化期间无数据，请耐心等待）");
            pollLoop(startFuture);
            exportResults();
        } finally {
            if (matlabLog != null) {
                matlabLog.flush();
            }
        }
    }

    // ==================== 生命周期 ====================

    private void startEngine() throws Exception {
        long t0 = System.currentTimeMillis();
        // 从引擎池借出（首次会启动 MATLAB，后续复用常驻引擎）
        engine = enginePool.borrow(ENGINE_START_TIMEOUT_SEC);
        long elapsed = System.currentTimeMillis() - t0;
        if (elapsed < 1000) {
            logMatlab("引擎已就绪（复用常驻引擎）");
        } else {
            logMatlab("引擎已就绪，耗时 " + elapsed + " ms");
        }
    }

    /** 预配置：切目录、跑预运行脚本、设参数、载入模型、对齐停止时间、配置信号日志 */
    private void prepare() throws Exception {
        eval("cd('" + esc(programDir) + "');", INIT_TIMEOUT_SEC, "切换工作目录");

        logMatlab("执行预运行脚本: " + preRunScript);
        eval("dmg_out = evalc('" + esc(stripM(preRunScript)) + "');", INIT_TIMEOUT_SEC, "执行预运行脚本 " + preRunScript);
        writeMatlabLog(getString("dmg_out"));

        StringBuilder params = new StringBuilder();
        if (hasText(npCommand)) params.append("NpReferenceRpm = ").append(npCommand).append(";\n");
        if (hasText(loadPower)) params.append("MkpReferenceNm = ").append(loadPower).append(";\n");
        if (hasText(fixedStep)) params.append("Ts = ").append(fixedStep).append(";\n");
        params.append("PTReferenceLoadPowerW = MkpReferenceNm * (NpReferenceRpm * pi / 30);\n");
        params.append("Power_cmd = PTReferenceLoadPowerW;\n");
        params.append("NpDem = NpReferenceRpm;\n");
        params.append("if exist('NgReferenceRpm', 'var'), NgMax = NgReferenceRpm * 1.05; end\n");
        params.append("if exist('WfReferenceKgps', 'var'), WfMax = WfReferenceKgps * 2; WfMin = WfReferenceKgps * 0.01; end\n");
        eval(params.toString(), INIT_TIMEOUT_SEC, "设置仿真参数");

        logMatlab("载入模型: " + modelName);
        eval("load_system('" + esc(modelName) + "');", INIT_TIMEOUT_SEC, "载入模型 " + modelName);
        if (hasText(fixedStep)) {
            eval("set_param('" + esc(modelName) + "','FixedStep','" + fixedStep + "');", CALL_TIMEOUT_SEC, "设置固定步长");
        }

        alignedStopTime = SimTimeUtil.alignToStep(requestedStopTime, resolveFixedStep());
        eval("set_param('" + esc(modelName) + "','StopTime','" + SimTimeUtil.format(alignedStopTime) + "');",
                CALL_TIMEOUT_SEC, "设置停止时间");
        logMatlab("停止时间 " + requestedStopTime + " → 按固定步长对齐为 " + alignedStopTime);
        sink.onStopTime(alignedStopTime);

        // 添加 To Workspace 块（与回退方案 writeWrapper 一致），仿真结束后这些变量
        // 会出现在 base workspace，由 exportResults() 汇总进 signals.csv
        addWorkspaceBlocks();
        // 配置信号日志（DataLogging）用于实时曲线显示
        configureSignalLogging();
    }

    /**
     * 添加 To Workspace 块，与回退方案 writeWrapper 的信号集完全一致。
     * 仿真结束后这些变量会出现在 base workspace，供 exportResults() 提取。
     * 仿真结束后在 close() 里 close_system 不保存，不会污染原模型。
     */
    private void addWorkspaceBlocks() throws Exception {
        String m = esc(modelName);
        StringBuilder sb = new StringBuilder();
        sb.append("dmg_okSignals = {};\n");

        // 1a. 核心信号：在块所在子系统内添加 To Workspace 块
        sb.append("dmg_wsSignals = {\n");
        for (String[] sig : CORE_SIGNALS) {
            sb.append("  '").append(sig[0]).append("', '").append(esc(modelName + sig[1])).append("';\n");
        }
        sb.append("};\n");
        sb.append("for dmg_i = 1:size(dmg_wsSignals, 1)\n");
        sb.append("  try\n");
        sb.append("    dmg_sigName = dmg_wsSignals{dmg_i, 1}; dmg_blockPath = dmg_wsSignals{dmg_i, 2};\n");
        sb.append("    dmg_parent = get_param(dmg_blockPath, 'Parent');\n");
        sb.append("    dmg_srcName = get_param(dmg_blockPath, 'Name');\n");
        sb.append("    dmg_twName = ['ToWS_' dmg_sigName]; dmg_twPath = [dmg_parent '/' dmg_twName];\n");
        sb.append("    dmg_ph = get_param(dmg_blockPath, 'PortHandles');\n");
        sb.append("    if isempty(dmg_ph.Outport); continue; end\n");
        sb.append("    if getSimulinkBlockHandle(dmg_twPath) ~= -1; delete_block(dmg_twPath); end\n");
        sb.append("    dmg_pos = get_param(dmg_blockPath, 'Position');\n");
        sb.append("    add_block('simulink/Sinks/To Workspace', dmg_twPath, ...\n");
        sb.append("      'Position', [dmg_pos(3)+80, dmg_pos(2), dmg_pos(3)+120, dmg_pos(2)+30], ...\n");
        sb.append("      'VariableName', dmg_sigName, 'SaveFormat', 'Array', ...\n");
        sb.append("      'MaxDataPoints', '1000000', 'Decimation', '1');\n");
        sb.append("    add_line(dmg_parent, [dmg_srcName '/1'], [dmg_twName '/1']);\n");
        sb.append("    dmg_okSignals{end+1} = dmg_sigName;\n");
        sb.append("  catch; try; delete_block(dmg_twPath); catch; end; end\n");
        sb.append("end\n");

        // 1b. CLP（Inport 在控制系统子系统内部）
        sb.append("try\n");
        sb.append("  dmg_clpPath = ['").append(m).append("/Turboshaft Engine Control System/CLP'];\n");
        sb.append("  dmg_clpParent = get_param(dmg_clpPath, 'Parent');\n");
        sb.append("  dmg_clpName = get_param(dmg_clpPath, 'Name');\n");
        sb.append("  dmg_twName = 'ToWS_CLP'; dmg_twPath = [dmg_clpParent '/' dmg_twName];\n");
        sb.append("  if getSimulinkBlockHandle(dmg_twPath) ~= -1; delete_block(dmg_twPath); end\n");
        sb.append("  dmg_pos = get_param(dmg_clpPath, 'Position');\n");
        sb.append("  add_block('simulink/Sinks/To Workspace', dmg_twPath, ...\n");
        sb.append("    'Position', [dmg_pos(3)+80, dmg_pos(2), dmg_pos(3)+120, dmg_pos(2)+30], ...\n");
        sb.append("    'VariableName', 'CLP', 'SaveFormat', 'Array', 'MaxDataPoints', '1000000', 'Decimation', '1');\n");
        sb.append("  add_line(dmg_clpParent, [dmg_clpName '/1'], [dmg_twName '/1']);\n");
        sb.append("  dmg_okSignals{end+1} = 'CLP';\n");
        sb.append("catch; try; delete_block(dmg_twPath); catch; end; end\n");

        // 2. Goto 标签信号：From + To Workspace（与回退方案完全一致的完整列表）
        String[] gotoAll = {
            "Np_fbk", "Ng_fbk", "Mkp_fbk", "T45_fbk",
            "Ngc", "Wf_kgps", "WfProxyCmd",
            "Pt3_fbk", "Tt3_fbk",
            "P1", "T1", "P45", "P4", "P5", "T5", "T4",
            "Oil_AirTemp_C",
            "dp_fuel", "lock_meter", "xm_ref_sb",
            "xm_cmd_m", "lock_igv", "xd_cmd",
            "shutdown", "xm", "xd"
        };
        sb.append("dmg_gotoAll = {");
        for (int i = 0; i < gotoAll.length; i++) {
            sb.append(i > 0 ? "," : "").append("'").append(gotoAll[i]).append("'");
        }
        sb.append("};\n");
        sb.append("for dmg_i = 1:numel(dmg_gotoAll)\n");
        sb.append("  try\n");
        sb.append("    dmg_sigName = dmg_gotoAll{dmg_i}; dmg_gotoTag = dmg_gotoAll{dmg_i};\n");
        sb.append("    dmg_twName = ['ToWS_From_' dmg_sigName]; dmg_fromName = ['From_' dmg_sigName];\n");
        sb.append("    dmg_twPath = ['").append(m).append("' '/' dmg_twName]; dmg_fromPath = ['").append(m).append("' '/' dmg_fromName];\n");
        sb.append("    if getSimulinkBlockHandle(dmg_twPath) ~= -1; delete_block(dmg_twPath); end\n");
        sb.append("    if getSimulinkBlockHandle(dmg_fromPath) ~= -1; delete_block(dmg_fromPath); end\n");
        sb.append("    add_block('simulink/Signal Routing/From', dmg_fromPath, 'GotoTag', dmg_gotoTag, ...\n");
        sb.append("      'Position', [100, 100+dmg_i*40, 200, 130+dmg_i*40]);\n");
        sb.append("    add_block('simulink/Sinks/To Workspace', dmg_twPath, 'VariableName', dmg_sigName, ...\n");
        sb.append("      'SaveFormat', 'Array', 'MaxDataPoints', '1000000', 'Decimation', '1', ...\n");
        sb.append("      'Position', [250, 100+dmg_i*40, 350, 130+dmg_i*40]);\n");
        sb.append("    add_line('").append(m).append("', [dmg_fromName '/1'], [dmg_twName '/1']);\n");
        sb.append("    dmg_okSignals{end+1} = dmg_sigName;\n");
        sb.append("  catch; try; delete_block(dmg_twPath); catch; end; try; delete_block(dmg_fromPath); catch; end; end\n");
        sb.append("end\n");

        // 3. Fuel System Wf 输出（子系统端口）
        sb.append("try\n");
        sb.append("  dmg_fsPath = '").append(m).append("/Fuel System';\n");
        sb.append("  dmg_fsPH = get_param(dmg_fsPath, 'PortHandles');\n");
        sb.append("  dmg_fsPos = get_param(dmg_fsPath, 'Position');\n");
        sb.append("  dmg_twName = 'ToWS_Wf'; dmg_twPath = ['").append(m).append("' '/' dmg_twName];\n");
        sb.append("  if getSimulinkBlockHandle(dmg_twPath) ~= -1; delete_block(dmg_twPath); end\n");
        sb.append("  add_block('simulink/Sinks/To Workspace', dmg_twPath, ...\n");
        sb.append("    'Position', [dmg_fsPos(3)+80, dmg_fsPos(2), dmg_fsPos(3)+120, dmg_fsPos(2)+30], ...\n");
        sb.append("    'VariableName', 'Wf', 'SaveFormat', 'Array', 'MaxDataPoints', '1000000', 'Decimation', '1');\n");
        sb.append("  add_line('").append(m).append("', dmg_fsPH.Outport(1), get_param(dmg_twPath, 'PortHandles').Inport(1));\n");
        sb.append("  dmg_okSignals{end+1} = 'Wf';\n");
        sb.append("catch; try; delete_block(dmg_twPath); catch; end; end\n");

        // 4. 空气系统输出（通过子系统 Outport）
        sb.append("try\n");
        sb.append("  dmg_airBlocks = find_system('").append(m).append("', 'RegExp', 'on', 'Name', 'G0[1-8]_.*W_kgps');\n");
        sb.append("  dmg_airParent = '';\n");
        sb.append("  for dmg_i = 1:numel(dmg_airBlocks)\n");
        sb.append("    dmg_p = get_param(dmg_airBlocks{dmg_i}, 'Parent');\n");
        sb.append("    if strcmp(get_param(dmg_p, 'Parent'), '").append(m).append("'); dmg_airParent = dmg_p; break; end\n");
        sb.append("  end\n");
        sb.append("  if ~isempty(dmg_airParent)\n");
        sb.append("    dmg_subPH = get_param(dmg_airParent, 'PortHandles');\n");
        sb.append("    dmg_airOuts = find_system(dmg_airParent, 'SearchDepth', 1, 'BlockType', 'Outport');\n");
        sb.append("    dmg_subPos = get_param(dmg_airParent, 'Position');\n");
        sb.append("    for dmg_i = 1:numel(dmg_airOuts)\n");
        sb.append("      try\n");
        sb.append("        dmg_outName = get_param(dmg_airOuts{dmg_i}, 'Name');\n");
        sb.append("        dmg_twName = ['ToWS_' dmg_outName]; dmg_twPath = ['").append(m).append("' '/' dmg_twName];\n");
        sb.append("        if getSimulinkBlockHandle(dmg_twPath) ~= -1; delete_block(dmg_twPath); end\n");
        sb.append("        dmg_yOff = dmg_subPos(2) + dmg_i * 35;\n");
        sb.append("        add_block('simulink/Sinks/To Workspace', dmg_twPath, ...\n");
        sb.append("          'Position', [dmg_subPos(3)+80, dmg_yOff, dmg_subPos(3)+120, dmg_yOff+30], ...\n");
        sb.append("          'VariableName', dmg_outName, 'SaveFormat', 'Array', 'MaxDataPoints', '1000000', 'Decimation', '1');\n");
        sb.append("        add_line('").append(m).append("', dmg_subPH.Outport(dmg_i), get_param(dmg_twPath, 'PortHandles').Inport(1));\n");
        sb.append("        dmg_okSignals{end+1} = dmg_outName;\n");
        sb.append("      catch; try; delete_block(dmg_twPath); catch; end; end\n");
        sb.append("    end\n");
        sb.append("  end\n");
        sb.append("catch; end\n");

        // 5. 滑油系统输出（28 个 Outport 的子系统）
        String[] oilVars = {
            "Q_BearingA", "Q_BearingB", "Q_AirOil", "Q_Accessory",
            "QA", "QB", "PA", "PB", "ToutA", "ToutB",
            "QretA", "QretB", "QgenA", "QgenB",
            "FuelOilCooler_Q", "FuelOilCooler_FuelTout",
            "AirOilCooler_Pin_Pa", "AirOilCooler_Pout_Pa",
            "FuelOilCooler_Pin_Pa", "FuelOilCooler_Pout_Pa",
            "CavityState8_PaK", "SealLeak4_kgps", "VentFlow3_kgps",
            "SealDeltaP4_Pa", "VentDeltaP2_Pa", "MassResidual2_kgps",
            "FuelOil2_ToutC_QkW", "AirOil2_ToutC_QkW"
        };
        sb.append("try\n");
        sb.append("  dmg_allSubs = find_system('").append(m).append("', 'SearchDepth', 1, 'BlockType', 'SubSystem');\n");
        sb.append("  dmg_oilSys = '';\n");
        sb.append("  for dmg_i = 1:numel(dmg_allSubs)\n");
        sb.append("    dmg_subOuts = find_system(dmg_allSubs{dmg_i}, 'SearchDepth', 1, 'BlockType', 'Outport');\n");
        sb.append("    if numel(dmg_subOuts) == 28; dmg_oilSys = dmg_allSubs{dmg_i}; break; end\n");
        sb.append("  end\n");
        sb.append("  if ~isempty(dmg_oilSys)\n");
        sb.append("    dmg_oilPH = get_param(dmg_oilSys, 'PortHandles');\n");
        sb.append("    dmg_oilOuts = find_system(dmg_oilSys, 'SearchDepth', 1, 'BlockType', 'Outport');\n");
        sb.append("    dmg_oilPos = get_param(dmg_oilSys, 'Position');\n");
        sb.append("    dmg_oilVarNames = {");
        for (int i = 0; i < oilVars.length; i++) {
            sb.append(i > 0 ? "," : "").append("'").append(oilVars[i]).append("'");
        }
        sb.append("};\n");
        sb.append("    for dmg_i = 1:numel(dmg_oilOuts)\n");
        sb.append("      try\n");
        sb.append("        dmg_varName = dmg_oilVarNames{dmg_i};\n");
        sb.append("        dmg_twName = ['ToWS_' dmg_varName]; dmg_twPath = ['").append(m).append("' '/' dmg_twName];\n");
        sb.append("        if getSimulinkBlockHandle(dmg_twPath) ~= -1; delete_block(dmg_twPath); end\n");
        sb.append("        dmg_yOff = dmg_oilPos(2) + dmg_i * 25;\n");
        sb.append("        add_block('simulink/Sinks/To Workspace', dmg_twPath, ...\n");
        sb.append("          'Position', [dmg_oilPos(3)+80, dmg_yOff, dmg_oilPos(3)+120, dmg_yOff+20], ...\n");
        sb.append("          'VariableName', dmg_varName, 'SaveFormat', 'Array', 'MaxDataPoints', '1000000', 'Decimation', '1');\n");
        sb.append("        add_line('").append(m).append("', dmg_oilPH.Outport(dmg_i), get_param(dmg_twPath, 'PortHandles').Inport(1));\n");
        sb.append("        dmg_okSignals{end+1} = dmg_varName;\n");
        sb.append("      catch; try; delete_block(dmg_twPath); catch; end; end\n");
        sb.append("    end\n");
        sb.append("  end\n");
        sb.append("catch; end\n");

        // 6. 发动机 SFunc 额外输出（HPC_u6, HPT_y16, LPT_y16）
        sb.append("try\n");
        sb.append("  dmg_sfuncBlocks = find_system('").append(m).append("', 'SearchDepth', 3, 'BlockType', 'S-Function');\n");
        sb.append("  for dmg_i = 1:numel(dmg_sfuncBlocks)\n");
        sb.append("    try\n");
        sb.append("      dmg_fn = get_param(dmg_sfuncBlocks{dmg_i}, 'FunctionName');\n");
        sb.append("      if strcmp(dmg_fn, 'SFunc_EngModel')\n");
        sb.append("        dmg_engPH = get_param(dmg_sfuncBlocks{dmg_i}, 'PortHandles');\n");
        sb.append("        dmg_engPos = get_param(dmg_sfuncBlocks{dmg_i}, 'Position');\n");
        sb.append("        dmg_engParent = get_param(dmg_sfuncBlocks{dmg_i}, 'Parent');\n");
        sb.append("        dmg_demuxName = 'ToWS_Demux_Extra'; dmg_demuxPath = [dmg_engParent '/' dmg_demuxName];\n");
        sb.append("        if getSimulinkBlockHandle(dmg_demuxPath) ~= -1; delete_block(dmg_demuxPath); end\n");
        sb.append("        add_block('simulink/Signal Routing/Demux', dmg_demuxPath, 'Outputs', '20', ...\n");
        sb.append("          'Position', [dmg_engPos(3)+20, dmg_engPos(2), dmg_engPos(3)+40, dmg_engPos(2)+400]);\n");
        sb.append("        add_line(dmg_engParent, dmg_engPH.Outport(1), get_param(dmg_demuxPath, 'PortHandles').Inport(1));\n");
        sb.append("        dmg_extraVars = {'HPC_u6', 'HPT_y16', 'LPT_y16'};\n");
        sb.append("        dmg_extraIdx = [13, 14, 15];\n");
        sb.append("        for dmg_j = 1:3\n");
        sb.append("          dmg_twName = ['ToWS_' dmg_extraVars{dmg_j}]; dmg_twPath = [dmg_engParent '/' dmg_twName];\n");
        sb.append("          if getSimulinkBlockHandle(dmg_twPath) ~= -1; delete_block(dmg_twPath); end\n");
        sb.append("          add_block('simulink/Sinks/To Workspace', dmg_twPath, ...\n");
        sb.append("            'VariableName', dmg_extraVars{dmg_j}, 'SaveFormat', 'Array', ...\n");
        sb.append("            'MaxDataPoints', '1000000', 'Decimation', '1', ...\n");
        sb.append("            'Position', [dmg_engPos(3)+80, dmg_engPos(2)+(dmg_j-1)*40, dmg_engPos(3)+120, dmg_engPos(2)+30+(dmg_j-1)*40]);\n");
        sb.append("          add_line(dmg_engParent, [dmg_demuxName '/' num2str(dmg_extraIdx(dmg_j))], [dmg_twName '/1']);\n");
        sb.append("          dmg_okSignals{end+1} = dmg_extraVars{dmg_j};\n");
        sb.append("        end\n");
        sb.append("        break;\n");
        sb.append("      end\n");
        sb.append("    catch; end\n");
        sb.append("  end\n");
        sb.append("catch; end\n");

        eval(sb.toString(), INIT_TIMEOUT_SEC, "添加 To Workspace 信号块");
        logMatlab("To Workspace 信号块已添加");
    }

    /** 读取模型实际生效的固定步长（FixedStep 可能是 'Ts' 这样的表达式，需要在 base workspace 求值） */
    private double resolveFixedStep() throws Exception {
        eval("dmg_ts = NaN; try; dmg_ts = eval(get_param('" + esc(modelName) + "','FixedStep')); catch; end",
                CALL_TIMEOUT_SEC, "读取固定步长");
        double ts = getDouble("dmg_ts");
        if (Double.isNaN(ts) || ts <= 0) {
            ts = hasText(fixedStep) ? Double.parseDouble(fixedStep) : 0.025;
            log.warn("[MATLAB] 无法从模型解析固定步长，使用 {}", ts);
        }
        return ts;
    }

    /**
     * 配置信号日志：不修改模型结构，只在源块输出端口上打开 DataLogging，
     * 并在 base workspace 里留下 dmg_cols / dmg_paths，供增量取数时按 BlockPath 精确匹配。
     */
    private void configureSignalLogging() throws Exception {
        List<String> names = new ArrayList<>();
        List<String> paths = new ArrayList<>();
        for (String[] sig : CORE_SIGNALS) {
            names.add(sig[0]);
            paths.add(modelName + sig[1]);
        }
        StringBuilder sb = new StringBuilder();
        sb.append("set_param('").append(esc(modelName)).append("','SignalLogging','on');\n");
        sb.append("set_param('").append(esc(modelName)).append("','SignalLoggingName','logsout');\n");
        // 清掉模型里已有的 DataLogging，保证 logsout 只包含我们关心的信号
        sb.append("dmg_ports = find_system('").append(esc(modelName)).append("','FindAll','on','Type','Port');\n");
        sb.append("for dmg_i = 1:numel(dmg_ports)\n");
        sb.append("  try; if strcmp(get_param(dmg_ports(dmg_i),'DataLogging'),'on'); set_param(dmg_ports(dmg_i),'DataLogging','off'); end; catch; end\n");
        sb.append("end\n");
        sb.append("dmg_cols = {}; dmg_paths = {};\n");
        // 核心信号：块路径已知
        sb.append("dmg_req = {\n");
        for (String[] sig : CORE_SIGNALS) {
            sb.append("  '").append(sig[0]).append("', '").append(esc(modelName + sig[1])).append("';\n");
        }
        for (String[] sig : TAIL_SIGNALS) {
            sb.append("  '").append(sig[0]).append("', '").append(esc(modelName + sig[1])).append("';\n");
        }
        sb.append("};\n");
        sb.append("dmg_goto = {");
        for (int i = 0; i < GOTO_SIGNALS.length; i++) {
            sb.append(i > 0 ? "," : "").append("'").append(GOTO_SIGNALS[i]).append("'");
        }
        sb.append("};\n");
        // Goto 信号：先找到 From 块再拿其输出端口
        sb.append("for dmg_i = 1:numel(dmg_goto)\n");
        sb.append("  try\n");
        sb.append("    dmg_from = find_system('").append(esc(modelName)).append("','BlockType','From','GotoTag',dmg_goto{dmg_i});\n");
        sb.append("    if ~isempty(dmg_from); dmg_req(end+1,:) = {dmg_goto{dmg_i}, dmg_from{1}}; end\n");
        sb.append("  catch; end\n");
        sb.append("end\n");
        sb.append("for dmg_i = 1:size(dmg_req,1)\n");
        sb.append("  try\n");
        sb.append("    dmg_ph = get_param(dmg_req{dmg_i,2},'PortHandles');\n");
        sb.append("    if isempty(dmg_ph.Outport); continue; end\n");
        sb.append("    set_param(dmg_ph.Outport(1),'DataLogging','on');\n");
        sb.append("    try; set_param(dmg_ph.Outport(1),'DataLoggingNameMode','Custom'); catch; end\n");
        sb.append("    set_param(dmg_ph.Outport(1),'DataLoggingName',dmg_req{dmg_i,1});\n");
        sb.append("    dmg_cols{end+1} = dmg_req{dmg_i,1}; dmg_paths{end+1} = dmg_req{dmg_i,2};\n");
        sb.append("  catch; end\n");
        sb.append("end\n");
        sb.append("dmg_cursor = 0; dmg_map = []; dmg_layout = cell(0,3);\n");
        // 把 addWorkspaceBlocks 添加的 To Workspace 块对应的信号也加入 DataLogging。
        // DataLogging 只能设在输出端口上，不能设在 ToWorkspace 块的 Inport 上。
        // 做法：通过 PortConnectivity 找到 ToWorkspace 块 Inport 的信号源端口（上游 Outport），
        // 在那个 Outport 上开启 DataLogging。
        sb.append("dmg_twBlocks = find_system('").append(esc(modelName)).append("','BlockType','ToWorkspace');\n");
        sb.append("dmg_twOk = 0; dmg_twFail = 0;\n");
        sb.append("dmg_firstErr = '';\n");
        sb.append("for dmg_i = 1:numel(dmg_twBlocks)\n");
        sb.append("  try\n");
        sb.append("    dmg_twName = char(get_param(dmg_twBlocks{dmg_i}, 'VariableName'));\n");
        sb.append("    if isempty(dmg_twName); dmg_twFail = dmg_twFail + 1; continue; end\n");
        // 跳过已配置过的信号（核心信号在前面已开启 DataLogging）
        sb.append("    dmg_alreadyLogged = false;\n");
        sb.append("    for dmg_j = 1:numel(dmg_cols); if strcmp(dmg_cols{dmg_j}, dmg_twName); dmg_alreadyLogged = true; break; end; end\n");
        sb.append("    if dmg_alreadyLogged; continue; end\n");
        // 通过 PortConnectivity 找到 ToWorkspace Inport 的信号源端口
        // PortConnectivity 字段: Type, Position, SrcBlock, SrcPort, DstBlock, DstPort
        // SrcBlock 是源块 handle，SrcPort 是源端口号（1-based）
        sb.append("    dmg_pc = get_param(dmg_twBlocks{dmg_i}, 'PortConnectivity');\n");
        sb.append("    dmg_srcBlockH = dmg_pc(1).SrcBlock;\n");
        sb.append("    dmg_srcPortIdx = dmg_pc(1).SrcPort;\n");
        sb.append("    if isempty(dmg_srcBlockH) || dmg_srcBlockH == 0 || dmg_srcBlockH == -1\n");
        sb.append("      dmg_twFail = dmg_twFail + 1; continue;\n");
        sb.append("    end\n");
        // 源块的 PortHandles.Outport 是数组，SrcPort 是 0-based 索引，需要 +1
        sb.append("    dmg_srcPH = get_param(dmg_srcBlockH, 'PortHandles');\n");
        sb.append("    dmg_srcPortIdx1 = dmg_srcPortIdx + 1;\n");
        sb.append("    if isempty(dmg_srcPH.Outport) || numel(dmg_srcPH.Outport) < dmg_srcPortIdx1\n");
        sb.append("      dmg_twFail = dmg_twFail + 1; continue;\n");
        sb.append("    end\n");
        sb.append("    dmg_srcPortH = dmg_srcPH.Outport(dmg_srcPortIdx1);\n");
        sb.append("    set_param(dmg_srcPortH,'DataLogging','on');\n");
        sb.append("    try; set_param(dmg_srcPortH,'DataLoggingNameMode','Custom'); catch; end\n");
        sb.append("    set_param(dmg_srcPortH,'DataLoggingName',dmg_twName);\n");
        sb.append("    dmg_srcBlockPath = getfullname(dmg_srcBlockH);\n");
        sb.append("    dmg_cols{end+1} = dmg_twName; dmg_paths{end+1} = dmg_srcBlockPath;\n");
        sb.append("    dmg_twOk = dmg_twOk + 1;\n");
        sb.append("  catch\n");
        sb.append("    dmg_twFail = dmg_twFail + 1;\n");
        sb.append("    if isempty(dmg_firstErr)\n");
        sb.append("      [dmg_msg, dmg_id] = lasterr;\n");
        sb.append("      dmg_firstErr = ['i=' num2str(dmg_i) ' name=' dmg_twName ' id=' dmg_id ' msg=' dmg_msg];\n");
        sb.append("    end\n");
        sb.append("  end\n");
        sb.append("end\n");
        sb.append("if isempty(dmg_firstErr); dmg_firstErr = 'none'; end\n");
        eval(sb.toString(), INIT_TIMEOUT_SEC, "配置信号日志");

        // 诊断
        double twOk = getDouble("dmg_twOk");
        double twFail = getDouble("dmg_twFail");
        eval("dmg_colCount = numel(dmg_cols);", CALL_TIMEOUT_SEC, "统计 dmg_cols");
        double colCount = getDouble("dmg_colCount");
        log.warn("诊断: ToWorkspace DataLogging 成功 " + (int)twOk + " 失败 " + (int)twFail + ", cols=" + (int)colCount + ", 首个错误: " + getString("dmg_firstErr"));

        // 以 MATLAB 实际配置成功的信号为准构造 CSV 表头
        eval("dmg_colstr = strjoin(dmg_cols, ',');", CALL_TIMEOUT_SEC, "读取信号列表");
        String cols = getString("dmg_colstr");
        csvColumns.clear();
        csvColumns.add("time");
        if (hasText(cols)) {
            csvColumns.addAll(Arrays.asList(cols.split(",")));
        }
        logMatlab("已配置信号日志，共 " + (csvColumns.size() - 1) + " 个信号: " + cols);
        sink.onHeaders(new ArrayList<>(csvColumns));
    }

    /** 主循环：轮询仿真状态 + 拉取增量数据，直到仿真结束。
     *  优化：把 status + simTime + WriteDataLogs + 取数合并成 1 次 eval + 1 次 getVariable，
     *  避免每个周期 6-7 次 JNI 调用导致取数间隔过长、一次出一堆点。 */
    private void pollLoop(Future<Void> startFuture) throws Exception {
        boolean sawRunning = false;
        while (true) {
            Thread.sleep(POLL_INTERVAL_MS);
            // 单次 eval 完成：读状态、读仿真时间、WriteDataLogs、取增量数据，打包成 dmg_poll
            eval(buildPollScript(), CALL_TIMEOUT_SEC, "轮询+取数");
            Object poll = call(() -> engine.getVariable("dmg_poll"), CALL_TIMEOUT_SEC, "读取轮询结果");
            // dmg_poll = {status, simTimeStr, dmg_new, newColStr}
            String status = "";
            String simTimeStr = "0";
            Object data = null;
            String newColStr = "";
            if (poll instanceof Object[]) {
                Object[] parts = (Object[]) poll;
                if (parts.length > 0 && parts[0] != null) status = String.valueOf(parts[0]);
                if (parts.length > 1 && parts[1] != null) simTimeStr = String.valueOf(parts[1]);
                if (parts.length > 2) data = parts[2];
                if (parts.length > 3 && parts[3] != null) newColStr = String.valueOf(parts[3]);
            }
            double simTime = parseDouble(simTimeStr, lastSimTime);

            if ("running".equals(status) || "paused".equals(status)) {
                sawRunning = true;
                paused.set("paused".equals(status));
                if (simTime > lastSimTime) lastSimTime = simTime;
                processData(data, newColStr);
            } else if (startFuture.isDone() && ("stopped".equals(status) || "terminating".equals(status))) {
                processData(data, newColStr);
                logMatlab("仿真结束，状态=" + status + "，仿真时间=" + lastSimTime + "，用户停止=" + userStopped.get());
                return;
            } else if (!sawRunning && startFuture.isDone()) {
                processData(data, newColStr);
                return;
            }
        }
    }

    /** 处理取到的增量数据：检测列变化 + 转行 + 推送给前端 */
    private void processData(Object data, String newColStr) throws Exception {
        if (csvColumns.size() <= 1) return;
        fetchCount++;
        boolean checkCols = (fetchCount == 1) || (fetchCount % COL_CHECK_INTERVAL == 0);
        if (checkCols && hasText(newColStr)) {
            List<String> newCols = new ArrayList<>(Arrays.asList(newColStr.split(",")));
            if (!newCols.equals(csvColumns)) {
                csvColumns.clear();
                csvColumns.addAll(newCols);
                sink.onHeaders(new ArrayList<>(csvColumns));
            }
        }
        List<String[]> rows = toRows(data, csvColumns.size());
        if (!rows.isEmpty()) {
            String[] last = rows.get(rows.size() - 1);
            lastSimTime = Math.max(lastSimTime, parseDouble(last[0], lastSimTime));
            sink.onRows(rows);
        }
    }

    /** 合并轮询脚本：状态 + 仿真时间 + WriteDataLogs + 增量取数，结果打包到 dmg_poll cell */
    private String buildPollScript() {
        String m = esc(modelName);
        StringBuilder sb = new StringBuilder();
        // 1. 读状态和仿真时间
        sb.append("dmg_status = ''; try; dmg_status = get_param('").append(m).append("','SimulationStatus'); catch; end\n");
        sb.append("dmg_pv2 = '0'; try; dmg_pv2 = get_param('").append(m).append("','SimulationTime'); if ~ischar(dmg_pv2); dmg_pv2 = mat2str(dmg_pv2); end; catch; end\n");
        // 2. 初始化取数变量
        sb.append("dmg_new = [];\n");
        sb.append("dmg_newCols = {};\n");
        sb.append("dmg_newColStr = '';\n");
        // 3. 仅在 running/paused/stopped 时做 WriteDataLogs + 取数
        sb.append("if strcmp(dmg_status,'running') || strcmp(dmg_status,'paused') || strcmp(dmg_status,'stopped')\n");
        sb.append("  try; set_param('").append(m).append("','SimulationCommand','WriteDataLogs'); catch; end\n");
        sb.append("  if exist('logsout','var') && isa(logsout,'Simulink.SimulationData.Dataset') && logsout.numElements > 0\n");
        // dmg_map 构建（exportResults 依赖）
        sb.append("    if isempty(dmg_map) || any(dmg_map == 0)\n");
        sb.append("      dmg_map = zeros(1, numel(dmg_cols));\n");
        sb.append("      for dmg_c = 1:numel(dmg_cols)\n");
        sb.append("        try\n");
        sb.append("          dmg_el = logsout.getElement(dmg_cols{dmg_c});\n");
        sb.append("          for dmg_e = 1:logsout.numElements\n");
        sb.append("            if strcmp(logsout.getElement(dmg_e).Name, dmg_cols{dmg_c}); dmg_map(dmg_c) = dmg_e; break; end\n");
        sb.append("          end\n");
        sb.append("        catch\n");
        sb.append("          for dmg_e = 1:logsout.numElements\n");
        sb.append("            try\n");
        sb.append("              dmg_el = logsout.getElement(dmg_e);\n");
        sb.append("              try; dmg_bp = strjoin(convertToCell(dmg_el.BlockPath), '/'); catch; dmg_bp = ''; end\n");
        sb.append("              if strcmp(dmg_bp, dmg_paths{dmg_c}); dmg_map(dmg_c) = dmg_e; break; end\n");
        sb.append("            catch; end\n");
        sb.append("          end\n");
        sb.append("        end\n");
        sb.append("      end\n");
        sb.append("    end\n");
        sb.append("    dmg_t = logsout.getElement(1).Values.Time(:);\n");
        sb.append("    dmg_total = numel(dmg_t);\n");
        sb.append("    if dmg_total > dmg_cursor\n");
        sb.append("      dmg_sel = (dmg_cursor+1):dmg_total;\n");
        sb.append("      dmg_new = dmg_t(dmg_sel);\n");
        sb.append("      dmg_newCols{end+1} = 'time';\n");
        // 首次构建 dmg_layout 缓存
        sb.append("      if isempty(dmg_layout)\n");
        sb.append("        dmg_layout = cell(0,3);\n");
        sb.append("        for dmg_e = 1:logsout.numElements\n");
        sb.append("          try\n");
        sb.append("            dmg_el = logsout.getElement(dmg_e);\n");
        sb.append("            dmg_name = dmg_el.Name;\n");
        sb.append("            if isempty(dmg_name); dmg_name = sprintf('sig_%d', dmg_e); end\n");
        sb.append("            dmg_v = dmg_el.Values.Data;\n");
        sb.append("            if isvector(dmg_v)\n");
        sb.append("              dmg_layout(end+1,:) = {dmg_e, matlab.lang.makeValidName(dmg_name), 1};\n");
        sb.append("            elseif size(dmg_v,1) == dmg_total\n");
        sb.append("              for dmg_k = 1:size(dmg_v,2)\n");
        sb.append("                if size(dmg_v,2) == 1; dmg_cn = dmg_name; else; dmg_cn = sprintf('%s_%d', dmg_name, dmg_k); end\n");
        sb.append("                dmg_layout(end+1,:) = {dmg_e, matlab.lang.makeValidName(dmg_cn), dmg_k};\n");
        sb.append("              end\n");
        sb.append("            end\n");
        sb.append("          catch; end\n");
        sb.append("        end\n");
        sb.append("      end\n");
        // 用缓存下标取数据
        sb.append("      for dmg_i = 1:size(dmg_layout,1)\n");
        sb.append("        try\n");
        sb.append("          dmg_e = dmg_layout{dmg_i,1};\n");
        sb.append("          dmg_cn = dmg_layout{dmg_i,2};\n");
        sb.append("          dmg_k = dmg_layout{dmg_i,3};\n");
        sb.append("          dmg_v = logsout.getElement(dmg_e).Values.Data;\n");
        sb.append("          if isvector(dmg_v)\n");
        sb.append("            dmg_v = dmg_v(:);\n");
        sb.append("            if numel(dmg_v) >= dmg_total; dmg_new = [dmg_new dmg_v(dmg_sel)]; end\n");
        sb.append("          elseif size(dmg_v,1) == dmg_total\n");
        sb.append("            dmg_new = [dmg_new dmg_v(dmg_sel, dmg_k)];\n");
        sb.append("          end\n");
        sb.append("          dmg_newCols{end+1} = dmg_cn;\n");
        sb.append("        catch; end\n");
        sb.append("      end\n");
        // 补充 dmg_cols 中未被 logsout 覆盖的信号
        sb.append("      for dmg_c = 1:numel(dmg_cols)\n");
        sb.append("        dmg_cn = matlab.lang.makeValidName(dmg_cols{dmg_c});\n");
        sb.append("        if ~any(strcmp(dmg_newCols, dmg_cn))\n");
        sb.append("          dmg_col = zeros(numel(dmg_sel), 1);\n");
        sb.append("          if numel(dmg_map) >= dmg_c && dmg_map(dmg_c) > 0\n");
        sb.append("            try\n");
        sb.append("              dmg_v2 = logsout.getElement(dmg_map(dmg_c)).Values.Data(:);\n");
        sb.append("              if numel(dmg_v2) >= dmg_total; dmg_col = dmg_v2(dmg_sel); end\n");
        sb.append("            catch; end\n");
        sb.append("          end\n");
        sb.append("          dmg_new = [dmg_new dmg_col];\n");
        sb.append("          dmg_newCols{end+1} = dmg_cn;\n");
        sb.append("        end\n");
        sb.append("      end\n");
        sb.append("      dmg_cursor = dmg_total;\n");
        // 工作区标量
        sb.append("      dmg_wsScalars = {'NgMax','T45Max','MkpMax','WfMax','WfMin','errmax','Power_cmd'};\n");
        sb.append("      for dmg_i = 1:numel(dmg_wsScalars)\n");
        sb.append("        try\n");
        sb.append("          dmg_sn = dmg_wsScalars{dmg_i};\n");
        sb.append("          if exist(dmg_sn, 'var') == 1\n");
        sb.append("            dmg_sv = evalin('base', dmg_sn);\n");
        sb.append("            if isnumeric(dmg_sv) && isscalar(dmg_sv) && ~any(strcmp(dmg_newCols, dmg_sn))\n");
        sb.append("              dmg_new = [dmg_new repmat(dmg_sv, numel(dmg_sel), 1)];\n");
        sb.append("              dmg_newCols{end+1} = dmg_sn;\n");
        sb.append("            end\n");
        sb.append("          end\n");
        sb.append("        catch; end\n");
        sb.append("      end\n");
        sb.append("    end\n");
        sb.append("  end\n");
        sb.append("  dmg_newColStr = strjoin(dmg_newCols, ',');\n");
        sb.append("end\n");
        // 4. 打包成 cell给 Java
        sb.append("dmg_poll = {dmg_status, dmg_pv2, dmg_new, dmg_newColStr};\n");
        return sb.toString();
    }

    /** 仿真结束后从 base workspace 汇总所有可用信号，写出 signals.csv / signals.mat */
    private void exportResults() throws Exception {
        File script = new File(taskDir, "dmg_export.m");
        Files.write(script.toPath(), buildExportScript().getBytes(StandardCharsets.UTF_8));
        eval("run('" + esc(script.getAbsolutePath()) + "');", INIT_TIMEOUT_SEC, "导出仿真结果");
        log.info("[MATLAB] 结果已导出: {}", new File(taskDir, "signals.csv").getAbsolutePath());
        //logMatlab("结果已生成: " + new File(taskDir, "signals.csv").getAbsolutePath());
    }

    /**
     * 导出脚本：以 logsout 的时间序列为基准，先取实时曲线用的信号列，
     * 再按 okSignals 列表精确提取 To Workspace 变量（SaveFormat=Array 格式为 [time, data]，
     * 需跳过时间列取数据列），然后提取工作区标量，最后泛化扫描 base workspace 补漏，
     * 保证 signals.csv 与旧 matlab -batch 方案的列集合一致（供入库、报警、报告复用）。
     */
    private String buildExportScript() {
        String csv = esc(new File(taskDir, "signals.csv").getAbsolutePath());
        String mat = esc(new File(taskDir, "signals.mat").getAbsolutePath());
        StringBuilder sb = new StringBuilder();
        sb.append("dmg_time = [];\n");
        sb.append("if exist('logsout','var') && isa(logsout,'Simulink.SimulationData.Dataset') && logsout.numElements > 0\n");
        sb.append("  dmg_time = logsout.getElement(1).Values.Time(:);\n");
        sb.append("elseif exist('tout','var'); dmg_time = tout(:);\n");
        sb.append("end\n");
        sb.append("dmg_n = numel(dmg_time);\n");
        sb.append("if dmg_n > 0\n");
        sb.append("  dmg_names = {'time'}; dmg_data = dmg_time;\n");
        // 1) 实时曲线信号（按 BlockPath 匹配，与实时推送列保持一致）
        sb.append("  for dmg_c = 1:numel(dmg_cols)\n");
        sb.append("    dmg_col = zeros(dmg_n,1);\n");
        sb.append("    try\n");
        sb.append("      if numel(dmg_map) >= dmg_c && dmg_map(dmg_c) > 0\n");
        sb.append("        dmg_v = logsout.getElement(dmg_map(dmg_c)).Values.Data(:);\n");
        sb.append("        if numel(dmg_v) == dmg_n; dmg_col = dmg_v; end\n");
        sb.append("      end\n");
        sb.append("    catch; end\n");
        sb.append("    dmg_names{end+1} = dmg_cols{dmg_c}; dmg_data = [dmg_data dmg_col];\n");
        sb.append("  end\n");
        // 2) 按 okSignals 精确提取 To Workspace 变量
        //    To Workspace (SaveFormat=Array) 产出 [time, data] 或 [time, data1, data2, ...]
        //    标量信号取 v(:,2)，向量信号取 v(:,2:end)
        sb.append("  for dmg_i = 1:numel(dmg_okSignals)\n");
        sb.append("    try\n");
        sb.append("      dmg_sn = dmg_okSignals{dmg_i};\n");
        sb.append("      if exist(dmg_sn, 'var') ~= 1; continue; end\n");
        sb.append("      dmg_v = evalin('base', dmg_sn);\n");
        sb.append("      if ~isnumeric(dmg_v) || isempty(dmg_v); continue; end\n");
        sb.append("      if size(dmg_v,1) == dmg_n && size(dmg_v,2) >= 2\n");
        sb.append("        dmg_v = dmg_v(:, 2:end);\n");
        sb.append("      elseif size(dmg_v,1) == dmg_n && size(dmg_v,2) == 1\n");
        sb.append("        % 纯数据列（无时间列），直接用\n");
        sb.append("      else; continue; end\n");
        sb.append("      for dmg_k = 1:size(dmg_v,2)\n");
        sb.append("        if size(dmg_v,2) == 1; dmg_cn = dmg_sn; else; dmg_cn = sprintf('%s_%d', dmg_sn, dmg_k); end\n");
        sb.append("        dmg_cn = matlab.lang.makeValidName(dmg_cn);\n");
        sb.append("        if any(strcmp(dmg_names, dmg_cn)); continue; end\n");
        sb.append("        dmg_names{end+1} = dmg_cn; dmg_data = [dmg_data double(dmg_v(:,dmg_k))];\n");
        sb.append("      end\n");
        sb.append("    catch; end\n");
        sb.append("  end\n");
        // 3) 工作区标量（限制值、功率指令等，展开为常数列）
        sb.append("  dmg_wsScalars = {'NgMax','T45Max','MkpMax','WfMax','WfMin','errmax','Power_cmd'};\n");
        sb.append("  for dmg_i = 1:numel(dmg_wsScalars)\n");
        sb.append("    try\n");
        sb.append("      dmg_sn = dmg_wsScalars{dmg_i};\n");
        sb.append("      if exist(dmg_sn, 'var') == 1\n");
        sb.append("        dmg_v = evalin('base', dmg_sn);\n");
        sb.append("        if isnumeric(dmg_v) && isscalar(dmg_v) && ~any(strcmp(dmg_names, dmg_sn))\n");
        sb.append("          dmg_names{end+1} = dmg_sn; dmg_data = [dmg_data repmat(dmg_v, dmg_n, 1)];\n");
        sb.append("        end\n");
        sb.append("      end\n");
        sb.append("    catch; end\n");
        sb.append("  end\n");
        // 4) 泛化扫描 base workspace 补漏（跳过已通过 okSignals 提取的变量）
        sb.append("  dmg_okSet = dmg_okSignals;\n");
        sb.append("  dmg_vars = evalin('base','who');\n");
        sb.append("  for dmg_i = 1:numel(dmg_vars)\n");
        sb.append("    dmg_name = dmg_vars{dmg_i};\n");
        sb.append("    if strncmp(dmg_name,'dmg_',4); continue; end\n");
        sb.append("    if any(strcmp(dmg_okSet, dmg_name)); continue; end\n");
        sb.append("    try; dmg_val = evalin('base', dmg_name); catch; continue; end\n");
        sb.append("    dmg_pairs = cell(0,2);\n");
        sb.append("    try\n");
        sb.append("      if isa(dmg_val,'Simulink.SimulationData.Dataset')\n");
        sb.append("        for dmg_e = 1:dmg_val.numElements\n");
        sb.append("          dmg_el = dmg_val.getElement(dmg_e);\n");
        sb.append("          dmg_en = dmg_el.Name; if isempty(dmg_en); dmg_en = sprintf('%s_%d', dmg_name, dmg_e); end\n");
        sb.append("          dmg_pairs(end+1,:) = {dmg_en, dmg_el.Values};\n");
        sb.append("        end\n");
        sb.append("      else\n");
        sb.append("        dmg_pairs(end+1,:) = {dmg_name, dmg_val};\n");
        sb.append("      end\n");
        sb.append("    catch; continue; end\n");
        sb.append("    for dmg_p = 1:size(dmg_pairs,1)\n");
        sb.append("      dmg_pn = dmg_pairs{dmg_p,1}; dmg_pv = dmg_pairs{dmg_p,2};\n");
        sb.append("      try; if isa(dmg_pv,'timeseries'); dmg_pv = dmg_pv.Data; end; catch; continue; end\n");
        sb.append("      if ~isnumeric(dmg_pv) || isempty(dmg_pv); continue; end\n");
        sb.append("      dmg_pv = squeeze(dmg_pv);\n");
        sb.append("      if size(dmg_pv,1) ~= dmg_n; continue; end\n");
        sb.append("      for dmg_k = 1:size(dmg_pv,2)\n");
        sb.append("        if size(dmg_pv,2) == 1; dmg_cn = dmg_pn; else; dmg_cn = sprintf('%s_%d', dmg_pn, dmg_k); end\n");
        sb.append("        dmg_cn = matlab.lang.makeValidName(dmg_cn);\n");
        sb.append("        if any(strcmp(dmg_names, dmg_cn)); continue; end\n");
        sb.append("        dmg_names{end+1} = dmg_cn; dmg_data = [dmg_data double(dmg_pv(:,dmg_k))];\n");
        sb.append("      end\n");
        sb.append("    end\n");
        sb.append("  end\n");
        sb.append("  T = array2table(dmg_data, 'VariableNames', dmg_names);\n");
        sb.append("  writetable(T, '").append(csv).append("');\n");
        sb.append("  save('").append(mat).append("', 'T');\n");
        sb.append("  fprintf('signals.csv: %d rows x %d cols\\n', size(dmg_data,1), size(dmg_data,2));\n");
        sb.append("else\n");
        sb.append("  warning('无仿真数据，未生成 signals.csv');\n");
        sb.append("end\n");
        return sb.toString();
    }

    // ==================== 运行控制（HTTP 线程调用，不阻塞） ====================

    /** 真实暂停：SimulationCommand pause，仿真时间冻结 */
    public void pause() {
        paused.set(true);
        submitCommand("pause");
    }

    /** 真实恢复：SimulationCommand continue */
    public void resume() {
        paused.set(false);
        submitCommand("continue");
    }

    /** 真实停止：SimulationCommand stop，已记录数据保留 */
    public void stopSimulation() {
        userStopped.set(true);
        paused.set(false);
        // 仿真可能还在 prepare 阶段（未 start），stop/continue 命令无效；
        // userStopped=true 会让 run() 在 prepare 后跳过仿真启动
        logMatlab("用户停止仿真");
        // 暂停中直接 stop 不生效，需要先 continue 再 stop
        submitCommand("continue");
        submitCommand("stop");
    }

    private void submitCommand(String command) {
        MatlabEngine eng = engine;
        if (eng == null) {
            log.warn("[MATLAB] 引擎尚未就绪，忽略命令: {}", command);
            return;
        }
        engineExec.submit(() -> {
            try {
                eng.eval("set_param('" + esc(modelName) + "','SimulationCommand','" + command + "');");
                logMatlab("已执行仿真控制命令: " + command);
            } catch (Exception e) {
                log.warn("[MATLAB] 仿真控制命令 {} 执行失败: {}", command, e.toString());
            }
        });
    }

    @Override
    public void close() {
        MatlabEngine eng = engine;
        engine = null;
        if (eng != null) {
            // 清理模型状态（不关闭引擎），让下次仿真可以重新 load_system
            try {
                engineExec.submit(() -> {
                    try {
                        eng.eval("try; set_param('" + esc(modelName) + "','SimulationCommand','stop'); catch; end");
                        eng.eval("try; set_param('" + esc(modelName) + "','Dirty','off'); close_system('" + esc(modelName) + "', 0); catch; end");
                    } catch (Exception ignored) {
                    }
                    return null;
                }).get(60, TimeUnit.SECONDS);
            } catch (Exception e) {
                log.warn("[MATLAB] 清理模型状态异常: {}", e.toString());
            }
            // 归还引擎到池中（不关闭），供下次仿真复用
            enginePool.release(eng);
        }
        engineExec.shutdownNow();
        if (matlabLog != null) matlabLog.close();
    }

    // ==================== 引擎调用工具 ====================

    private <T> T call(Callable<T> action, long timeoutSec, String what) throws Exception {
        Future<T> f = engineExec.submit(action);
        try {
            return f.get(timeoutSec, TimeUnit.SECONDS);
        } catch (ExecutionException e) {
            Throwable cause = e.getCause() != null ? e.getCause() : e;
            throw new Exception(what + "失败: " + cause.getMessage(), cause);
        } catch (TimeoutException e) {
            f.cancel(true);
            throw new Exception(what + "超时(" + timeoutSec + "s)");
        }
    }

    private void eval(String command, long timeoutSec, String what) throws Exception {
        call(() -> {
            Writer out = matlabLog != null ? matlabLog : new java.io.StringWriter();
            engine.eval(command, out, out);
            out.flush();
            return null;
        }, timeoutSec, what);
    }

    /** get_param 的字符串形式（数值参数用 mat2str 转成字符串，便于统一处理） */
    private String param(String name) throws Exception {
        eval("dmg_pv = get_param('" + esc(modelName) + "','" + name + "'); if ~ischar(dmg_pv); dmg_pv = mat2str(dmg_pv); end",
                CALL_TIMEOUT_SEC, "读取模型参数 " + name);
        return getString("dmg_pv");
    }

    private String getString(String var) throws Exception {
        Object v = call(() -> engine.getVariable(var), CALL_TIMEOUT_SEC, "读取变量 " + var);
        return v == null ? "" : String.valueOf(v);
    }

    private double getDouble(String var) throws Exception {
        Object v = call(() -> engine.getVariable(var), CALL_TIMEOUT_SEC, "读取变量 " + var);
        return v instanceof Number ? ((Number) v).doubleValue() : Double.NaN;
    }

    /** MATLAB 矩阵 → CSV 行（单行时引擎返回一维数组） */
    private static List<String[]> toRows(Object data, int cols) {
        List<String[]> rows = new ArrayList<>();
        if (data instanceof double[][]) {
            for (double[] r : (double[][]) data) rows.add(fmtRow(r));
        } else if (data instanceof double[]) {
            double[] r = (double[]) data;
            if (r.length == cols) rows.add(fmtRow(r));
        }
        return rows;
    }

    private static String[] fmtRow(double[] values) {
        String[] row = new String[values.length];
        for (int i = 0; i < values.length; i++) {
            row[i] = Double.isNaN(values[i]) || Double.isInfinite(values[i]) ? "0.000000" : fmt(values[i]);
        }
        return row;
    }

    private static String fmt(double v) {
        return String.format(Locale.US, "%.6f", v);
    }

    private void writeMatlabLog(String text) {
        if (matlabLog != null && hasText(text)) {
            matlabLog.println(text);
            matlabLog.flush();
        }
    }

    /** 记录 [MATLAB] 日志行，同时推送给前端 footer 实时显示 */
    private void logMatlab(String msg) {
        log.info("[MATLAB] {}", msg);
        try { sink.onLog("[MATLAB] " + msg + " ..."); } catch (Exception ignored) {}
    }

    private static double parseDouble(String s, double fallback) {
        try {
            return Double.parseDouble(s.trim());
        } catch (Exception e) {
            return fallback;
        }
    }

    private static String stripM(String script) {
        return script.toLowerCase().endsWith(".m") ? script.substring(0, script.length() - 2) : script;
    }

    private static boolean hasText(String s) {
        return s != null && !s.trim().isEmpty();
    }

    private static String esc(String s) {
        return s == null ? "" : s.replace("\\", "\\\\").replace("'", "''");
    }
}
