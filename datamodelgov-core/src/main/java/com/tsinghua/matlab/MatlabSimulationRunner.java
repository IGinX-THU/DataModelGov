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
    private static final long POLL_INTERVAL_MS = 500;

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

    private volatile MatlabEngine engine;
    private volatile double alignedStopTime;
    private volatile double lastSimTime;
    private PrintWriter matlabLog;

    public MatlabSimulationRunner(File taskDir, String programDir, String preRunScript, String modelName,
                                  double requestedStopTime, String fixedStep, String npCommand, String loadPower,
                                  LiveSink sink) {
        this.taskDir = taskDir;
        this.programDir = programDir;
        this.preRunScript = preRunScript;
        this.modelName = modelName;
        this.requestedStopTime = requestedStopTime;
        this.fixedStep = fixedStep;
        this.npCommand = npCommand;
        this.loadPower = loadPower;
        this.sink = sink;
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
            Future<Void> startFuture = call(() -> engine.evalAsync(
                    "set_param('" + esc(modelName) + "','SimulationCommand','start');"), 60, "发送仿真启动命令");
            log.info("[MATLAB] 仿真启动命令已发送（编译+初始化期间无数据）");
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
        // 在触碰 MatlabEngine 之前安装 AWT HeadlessException 抑制器：
        // MvmImpl.loadLibrary 在依赖库缺失时会 SwingUtilities.invokeLater 弹对话框，
        // headless 下 JDialog 构造抛 HeadlessException 刷屏
        MatlabNativeLibrary.installHeadlessSuppressor();
        long t0 = System.currentTimeMillis();
        engine = call(MatlabEngine::startMatlab, ENGINE_START_TIMEOUT_SEC, "启动 MATLAB 引擎");
        log.info("[MATLAB] 引擎已启动，耗时 {} ms", System.currentTimeMillis() - t0);
    }

    /** 预配置：切目录、跑预运行脚本、设参数、载入模型、对齐停止时间、配置信号日志 */
    private void prepare() throws Exception {
        eval("cd('" + esc(programDir) + "');", INIT_TIMEOUT_SEC, "切换工作目录");

        log.info("[MATLAB] 执行预运行脚本: {}", preRunScript);
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

        log.info("[MATLAB] 载入模型: {}", modelName);
        eval("load_system('" + esc(modelName) + "');", INIT_TIMEOUT_SEC, "载入模型 " + modelName);
        if (hasText(fixedStep)) {
            eval("set_param('" + esc(modelName) + "','FixedStep','" + fixedStep + "');", CALL_TIMEOUT_SEC, "设置固定步长");
        }

        alignedStopTime = SimTimeUtil.alignToStep(requestedStopTime, resolveFixedStep());
        eval("set_param('" + esc(modelName) + "','StopTime','" + SimTimeUtil.format(alignedStopTime) + "');",
                CALL_TIMEOUT_SEC, "设置停止时间");
        log.info("[MATLAB] 停止时间 {} → 按固定步长对齐为 {}", requestedStopTime, alignedStopTime);
        sink.onStopTime(alignedStopTime);

        configureSignalLogging();
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
        sb.append("dmg_cursor = 0; dmg_map = [];\n");
        eval(sb.toString(), INIT_TIMEOUT_SEC, "配置信号日志");

        // 以 MATLAB 实际配置成功的信号为准构造 CSV 表头
        eval("dmg_colstr = strjoin(dmg_cols, ',');", CALL_TIMEOUT_SEC, "读取信号列表");
        String cols = getString("dmg_colstr");
        csvColumns.clear();
        csvColumns.add("time");
        if (hasText(cols)) {
            csvColumns.addAll(Arrays.asList(cols.split(",")));
        }
        log.info("[MATLAB] 已配置信号日志，共 {} 个信号: {}", csvColumns.size() - 1, cols);
        sink.onHeaders(new ArrayList<>(csvColumns));
    }

    /** 主循环：轮询仿真状态 + 拉取增量数据，直到仿真结束 */
    private void pollLoop(Future<Void> startFuture) throws Exception {
        boolean sawRunning = false;
        while (true) {
            Thread.sleep(POLL_INTERVAL_MS);
            String status = param("SimulationStatus");
            if ("running".equals(status) || "paused".equals(status)) {
                sawRunning = true;
                paused.set("paused".equals(status));
                double t = parseDouble(param("SimulationTime"), lastSimTime);
                if (t > lastSimTime) lastSimTime = t;
                fetchIncremental();
            } else if (startFuture.isDone() && ("stopped".equals(status) || "terminating".equals(status))) {
                // start 命令返回后仿真已在运行；此时回到 stopped 即表示仿真结束
                log.info("[MATLAB] 仿真结束，状态={}，仿真时间={}，用户停止={}", status, lastSimTime, userStopped.get());
                fetchIncremental();
                return;
            } else if (!sawRunning && startFuture.isDone()) {
                // start 已返回但从未进入 running：可能是极短仿真，直接取数收尾
                fetchIncremental();
                return;
            }
        }
    }

    /** 取一次增量数据：WriteDataLogs 把运行中的日志刷入 workspace，再按游标取新增行 */
    private void fetchIncremental() throws Exception {
        if (csvColumns.size() <= 1) return;
        eval(buildFetchScript(), CALL_TIMEOUT_SEC, "读取实时仿真数据");
        Object data = call(() -> engine.getVariable("dmg_new"), CALL_TIMEOUT_SEC, "读取增量数据");
        List<String[]> rows = toRows(data, csvColumns.size());
        if (!rows.isEmpty()) {
            String[] last = rows.get(rows.size() - 1);
            lastSimTime = Math.max(lastSimTime, parseDouble(last[0], lastSimTime));
            sink.onRows(rows);
        }
    }

    private String buildFetchScript() {
        String m = esc(modelName);
        return "dmg_new = [];\n"
                + "try; set_param('" + m + "','SimulationCommand','WriteDataLogs'); catch; end\n"
                + "if exist('logsout','var') && isa(logsout,'Simulink.SimulationData.Dataset') && logsout.numElements > 0\n"
                + "  if isempty(dmg_map) || any(dmg_map == 0)\n"
                + "    dmg_map = zeros(1, numel(dmg_cols));\n"
                + "    for dmg_c = 1:numel(dmg_cols)\n"
                + "      for dmg_e = 1:logsout.numElements\n"
                + "        try\n"
                + "          dmg_el = logsout.getElement(dmg_e);\n"
                + "          try; dmg_bp = strjoin(convertToCell(dmg_el.BlockPath), '/'); catch; dmg_bp = ''; end\n"
                + "          if strcmp(dmg_bp, dmg_paths{dmg_c}); dmg_map(dmg_c) = dmg_e; break; end\n"
                + "        catch; end\n"
                + "      end\n"
                + "    end\n"
                + "  end\n"
                + "  dmg_t = logsout.getElement(1).Values.Time(:);\n"
                + "  dmg_total = numel(dmg_t);\n"
                + "  if dmg_total > dmg_cursor\n"
                + "    dmg_sel = (dmg_cursor+1):dmg_total;\n"
                + "    dmg_new = dmg_t(dmg_sel);\n"
                + "    for dmg_c = 1:numel(dmg_cols)\n"
                + "      dmg_col = zeros(numel(dmg_sel),1);\n"
                + "      if dmg_map(dmg_c) > 0\n"
                + "        try\n"
                + "          dmg_v = logsout.getElement(dmg_map(dmg_c)).Values.Data(:);\n"
                + "          if numel(dmg_v) >= dmg_total; dmg_col = dmg_v(dmg_sel); end\n"
                + "        catch; end\n"
                + "      end\n"
                + "      dmg_new = [dmg_new dmg_col];\n"
                + "    end\n"
                + "    dmg_cursor = dmg_total;\n"
                + "  end\n"
                + "end\n";
    }

    /** 仿真结束后从 base workspace 汇总所有可用信号，写出 signals.csv / signals.mat */
    private void exportResults() throws Exception {
        File script = new File(taskDir, "dmg_export.m");
        Files.write(script.toPath(), buildExportScript().getBytes(StandardCharsets.UTF_8));
        eval("run('" + esc(script.getAbsolutePath()) + "');", INIT_TIMEOUT_SEC, "导出仿真结果");
        log.info("[MATLAB] 结果已导出: {}", new File(taskDir, "signals.csv").getAbsolutePath());
    }

    /**
     * 导出脚本：以 logsout 的时间序列为基准，先取实时曲线用的信号列，
     * 再泛化扫描 base workspace 中行数一致的 timeseries / 数值变量 / Dataset（含模型自带的 To Workspace、Scope 记录），
     * 保证 signals.csv 与旧 matlab -batch 方案的列集合基本一致（供入库、报警、报告复用）。
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
        // 2) 泛化扫描 base workspace
        sb.append("  dmg_vars = evalin('base','who');\n");
        sb.append("  for dmg_i = 1:numel(dmg_vars)\n");
        sb.append("    dmg_name = dmg_vars{dmg_i};\n");
        sb.append("    if strncmp(dmg_name,'dmg_',4); continue; end\n");
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
                log.info("[MATLAB] 已执行仿真控制命令: {}", command);
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
            try {
                engineExec.submit(() -> {
                    try {
                        eng.eval("try; set_param('" + esc(modelName) + "','SimulationCommand','stop'); catch; end");
                        eng.eval("try; set_param('" + esc(modelName) + "','Dirty','off'); close_system('" + esc(modelName) + "', 0); catch; end");
                    } catch (Exception ignored) {
                    }
                    eng.close();
                    return null;
                }).get(120, TimeUnit.SECONDS);
            } catch (Exception e) {
                log.warn("[MATLAB] 关闭引擎异常: {}", e.toString());
                try {
                    eng.disconnect();
                } catch (Exception ignored) {
                }
            }
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
