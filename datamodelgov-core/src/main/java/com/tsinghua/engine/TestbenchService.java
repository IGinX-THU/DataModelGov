package com.tsinghua.engine;

import com.mathworks.engine.MatlabEngine;
import com.tsinghua.matlab.MatlabNativeLibrary;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import javax.annotation.PostConstruct;
import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.stream.Stream;

/**
 * 数字试车台接入层(第四批):
 *   F-11 全模式人工操纵仿真 — sht_fullmode_session 会话合同(prepare→begin→submit命令→advance分块推进→save/result/close)。
 *   F-09 设计点配置 — sht_design_point_task('solve'/'commit'/'inspect')任务式。
 *   F-10 起动停车模型构造 — sht_startstop_modeling_task(prepare→runStage链→savepackage)任务式。
 *
 * 全模式会话与AFO同款:persistent单例、每会话专用MATLAB引擎;推进循环在单线程executor上
 * 分块advance(80步=2s),块间处理命令队列并刷新status.json(前端只读文件,不占引擎)。
 * 设计点/起动停车为一次性任务:专用引擎执行后关闭,结果JSON落任务目录。
 */
@Slf4j
@Service
public class TestbenchService {

    @Autowired
    private EngineProjectStore store;

    private static final String R06_IN_CLASSPATH = "programs/Delivery_V1_20261019_R06/programs";
    private static final String PROG_SUBDIR = "m_program_adaptive_tune";

    /* ---------- 全模式会话(F-11) ---------- */

    private final Object fmLock = new Object();
    private volatile FullmodeSession fmSession;
    private final ExecutorService fmExecutor = Executors.newSingleThreadExecutor();
    private final ConcurrentLinkedQueue<Map<String, Object>> fmCommands = new ConcurrentLinkedQueue<>();

    static class FullmodeSession {
        String projectId;
        String runId;
        String engineId;
        String outputDir;
        String adapterDir;
        /** PREPARING / READY / RUNNING / PAUSED / ENDED / FAILED / CLOSED */
        volatile String phase = "PREPARING";
        volatile String message = "";
        volatile String error;
        volatile boolean stopRequested;
        Long createdAt;
        Long finishedAt;
        Map<String, Object> config;
        String programDir;
        MatlabEngine engine;
    }

    /* ---------- 一次性任务(F-09/F-10) ---------- */

    private final Map<String, TaskRun> taskRuns = new ConcurrentHashMap<>();
    private final ExecutorService taskExecutor = Executors.newFixedThreadPool(2);

    static class TaskRun {
        String projectId;
        String taskId;
        /** design_point | startstop */
        String kind;
        String taskDirectory;
        String adapterDir;
        volatile String phase = "PREPARING";
        volatile String message = "";
        volatile String error;
        Long createdAt;
        Long finishedAt;
        Map<String, Object> config;
        MatlabEngine engine;
    }

    @PostConstruct
    void init() {
        log.info("数字试车台接入层就绪(F-09设计点/F-10起动停车/F-11全模式会话)");
        // 提前注入MATLAB原生库路径(与AfoService一致,保证首次会话引擎可用)
        try {
            MatlabNativeLibrary.prepare(null);
        } catch (Exception e) {
            log.warn("MATLAB原生库路径注入失败(引擎启动时再探测)", e);
        }
    }

    /* ================= 全模式会话(F-11) ================= */

    public Map<String, Object> fullmodeStatus(String projectId) throws IOException {
        FullmodeSession s = fmSession;
        Map<String, Object> out = new LinkedHashMap<>();
        if (s == null || (projectId != null && !projectId.equals(s.projectId))) {
            out.put("phase", "IDLE");
            out.put("message", "无活动会话");
            return out;
        }
        out.put("runId", s.runId);
        out.put("engineId", s.engineId);
        out.put("phase", s.phase);
        out.put("message", s.message);
        out.put("error", s.error);
        out.put("config", s.config);
        // 运行中状态以适配器原子写的 status.json 为准(含lifecycle/time/操纵回执等)
        File sf = new File(s.adapterDir, "status.json");
        if (sf.exists()) {
            try {
                out.put("live", new com.fasterxml.jackson.databind.ObjectMapper().readValue(sf, Object.class));
            } catch (Exception e) {
                log.debug("fullmode status.json 读取中(可能正在原子替换)", e);
            }
        }
        return out;
    }

    public Map<String, Object> fullmodePrepare(String projectId, Map<String, Object> cfg) throws IOException {
        synchronized (fmLock) {
            FullmodeSession cur = fmSession;
            if (cur != null && !isTerminal(cur.phase)) {
                throw new IllegalStateException("已有全模式会话在" + cur.phase + "(runId=" + cur.runId + "),请先关闭");
            }
            String runId = "FM-" + new java.text.SimpleDateFormat("yyyyMMdd_HHmmss").format(new Date());
            File workDir = store.testbenchWorkDir(projectId, runId);
            File adapterDir = new File(workDir, "adapter");
            if (!adapterDir.exists() && !adapterDir.mkdirs()) throw new IOException("无法创建适配器目录: " + adapterDir);

            FullmodeSession s = new FullmodeSession();
            s.projectId = projectId;
            s.runId = runId;
            s.engineId = String.valueOf(cfg.getOrDefault("engineId", "ENGINE-001"));
            // 合同输出目录由会话save时使用;Java侧不预创建(避免时序冲突)
            s.outputDir = workDir.getAbsolutePath();
            s.adapterDir = adapterDir.getAbsolutePath();
            s.createdAt = System.currentTimeMillis();
            s.config = cfg;
            s.message = "准备全模式运行资产";
            fmSession = s;
            writeFullmodeIndex(s);
            fmExecutor.submit(() -> fullmodeExec(s, "prepare", null));
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("runId", runId);
            out.put("phase", s.phase);
            return out;
        }
    }

    /** 开始推进循环(READY→RUNNING;分块advance,块间处理命令并刷新status.json)。 */
    public Map<String, Object> fullmodeRun(String projectId) throws IOException {
        FullmodeSession s = requireFullmode(projectId);
        if (!"READY".equals(s.phase) && !"PAUSED".equals(s.phase)) {
            throw new IllegalStateException("当前会话状态为" + s.phase + ",需要READY/PAUSED");
        }
        if ("PAUSED".equals(s.phase)) {
            // resume:先engine内resume再进入循环
            s.phase = "RUNNING";
            s.message = "仿真运行中";
            writeFullmodeIndex(s);
            fmExecutor.submit(() -> fullmodeResumeThenLoop(s));
        } else {
            s.phase = "RUNNING";
            s.message = "仿真运行中";
            writeFullmodeIndex(s);
            fmExecutor.submit(() -> fullmodeLoop(s));
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("phase", s.phase);
        return out;
    }

    private void fullmodeResumeThenLoop(FullmodeSession s) {
        try {
            fevalFullmode(s, "resume", null);
        } catch (Exception e) {
            log.warn("fullmode resume失败(继续推进)", e);
        }
        fullmodeLoop(s);
    }

    private void fullmodeLoop(FullmodeSession s) {
        try {
            int chunkSteps = 80; // 0.025s × 80 = 2s仿真时间/块
            while ("RUNNING".equals(s.phase)) {
                // 块间命令处理(pause/terminate在此同步;其余submit入会话)
                Map<String, Object> cmd;
                while ((cmd = fmCommands.poll()) != null) {
                    String kind = String.valueOf(cmd.get("kind"));
                    if ("pause".equals(kind)) {
                        fevalFullmode(s, "pause", null);
                        s.phase = "PAUSED";
                        s.message = "已暂停(保持状态)";
                        writeFullmodeIndex(s);
                        refreshFullmodeStatusFile(s);
                        return;
                    }
                    Map<String, Object> sub = new LinkedHashMap<>();
                    sub.put("requestId", "dm_" + UUID.randomUUID().toString().substring(0, 8));
                    if ("stop".equals(kind)) {
                        sub.put("action", "normal_stop");
                        s.stopRequested = true;
                    } else {
                        sub.put("action", kind);
                        Object v = cmd.get("value");
                        if (v != null) sub.put("value", v);
                    }
                    fevalFullmode(s, "submit", sub);
                }
                Map<String, Object> adv = new LinkedHashMap<>();
                adv.put("n", chunkSteps);
                fevalFullmode(s, "advance", adv);
                Map<String, Object> st = fevalFullmode(s, "status", null);
                writeStatusFile(s, st);
                Object lc = st.get("lifecycle");
                if (lc != null && !"running".equals(String.valueOf(lc))) {
                    break; // 会话自身终止(normal_stop完成/terminate)
                }
            }
            // 收尾:save→result→close
            if (!"PAUSED".equals(s.phase)) {
                finalizeFullmode(s, "仿真结束;保存Excel与快照");
            }
        } catch (Exception e) {
            log.error("fullmode推进失败: {}", s.runId, e);
            s.phase = "FAILED";
            s.error = e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
            s.message = "运行失败";
            s.finishedAt = System.currentTimeMillis();
            closeEngine(s.engine);
            s.engine = null;
            writeFullmodeIndex(s);
        }
    }

    private void finalizeFullmode(FullmodeSession s, String msg) {
        try {
            s.message = msg;
            logLine(s, "保存结果(Excel/快照/result)");
            fevalFullmode(s, "save", null);
            fevalFullmode(s, "result", null);
            fevalFullmode(s, "close", null);
            s.phase = "ENDED";
            s.message = "运行结束;结果已保存";
            s.finishedAt = System.currentTimeMillis();
        } catch (Exception e) {
            log.error("fullmode收尾失败: {}", s.runId, e);
            s.phase = "FAILED";
            s.error = e.getMessage();
            s.message = "收尾失败";
            s.finishedAt = System.currentTimeMillis();
        } finally {
            closeEngine(s.engine);
            s.engine = null;
            writeFullmodeIndex(s);
        }
    }

    /** 命令:pause即时;stop/操纵类入块间队列。 */
    public Map<String, Object> fullmodeCommand(String projectId, String kind, Object value) throws IOException {
        FullmodeSession s = requireFullmode(projectId);
        if (!"RUNNING".equals(s.phase) && !"READY".equals(s.phase)) {
            throw new IllegalStateException("当前状态" + s.phase + "不接受命令");
        }
        Map<String, Object> cmd = new LinkedHashMap<>();
        cmd.put("kind", kind);
        if (value != null) cmd.put("value", value);
        if ("pause".equals(kind) && "RUNNING".equals(s.phase)) {
            // 块间由推进线程处理;此处直接入队即可
        }
        fmCommands.add(cmd);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("accepted", true);
        out.put("note", "命令已入队;推进块间生效");
        return out;
    }

    public Map<String, Object> fullmodeClose(String projectId) throws IOException {
        FullmodeSession s = requireFullmode(projectId);
        if ("RUNNING".equals(s.phase)) throw new IllegalStateException("运行中不能关闭;先结束计算");
        if (s.engine != null) {
            try {
                fevalFullmode(s, "close", null);
            } catch (Exception e) {
                log.warn("fullmode close失败(仍关闭引擎)", e);
            }
        }
        s.phase = "CLOSED";
        s.message = "会话已关闭";
        closeEngine(s.engine);
        s.engine = null;
        writeFullmodeIndex(s);
        synchronized (fmLock) {
            if (fmSession == s) fmSession = null;
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("closed", true);
        return out;
    }

    public List<Map<String, Object>> fullmodeSessions(String projectId) throws IOException {
        return listMeta(store.testbenchSessionDir(projectId), "fm-");
    }

    /** 单条历史结果(result.json)。 */
    public Map<String, Object> fullmodeResult(String projectId, String runId) throws IOException {
        File f = new File(store.testbenchWorkDir(projectId, runId), "result.json");
        if (!f.exists()) return null;
        return new com.fasterxml.jackson.databind.ObjectMapper().readValue(f, Map.class);
    }

    public File fullmodeExcel(String projectId, String runId) throws IOException {
        return findExcelRecursive(store.testbenchWorkDir(projectId, runId));
    }

    private FullmodeSession requireFullmode(String projectId) throws IOException {
        FullmodeSession s = fmSession;
        if (s == null || (projectId != null && !projectId.equals(s.projectId))) {
            throw new IllegalStateException("无活动全模式会话;请先发起准备");
        }
        return s;
    }

    /** prepare动作:启动专用引擎→prepare(user)→begin。 */
    private void fullmodeExec(FullmodeSession s, String action, Map<String, Object> extra) {
        try {
            File progCopy = ensureProgramSource(s.projectId);
            s.programDir = progCopy.getAbsolutePath();
            writeFullmodeAdapter(new File(s.adapterDir), progCopy);
            MatlabEngine eng = MatlabEngine.startMatlab();
            s.engine = eng;
            try {
                eng.feval(0, "eval", "feature('DefaultCharacterSet', 'GBK')");
            } catch (Exception ce) {
                log.warn("fullmode引擎字符集设置失败(沿用默认)", ce);
            }
            logLine(s, "MATLAB引擎已启动;准备运行资产(校验身份/初始化模型)");
            fevalFullmode(s, "prepare", null);
            fevalFullmode(s, "begin", null);
            logLine(s, "全模式会话已就绪(prepare+begin)");
            s.phase = "READY";
            s.message = "准备完成;可开始运行";
            writeFullmodeIndex(s);
        } catch (Exception e) {
            log.error("fullmode准备失败: {}", s.runId, e);
            s.phase = "FAILED";
            s.error = e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
            s.message = "准备失败";
            closeEngine(s.engine);
            s.engine = null;
            writeFullmodeIndex(s);
        }
    }

    /** feval一个fullmode动作:写action配置→适配器→读取JSON结果。 */
    @SuppressWarnings("unchecked")
    private <T> T fevalFullmode(FullmodeSession s, String action, Map<String, Object> cmd) throws Exception {
        Map<String, Object> call = new LinkedHashMap<>();
        call.put("action", action);
        call.put("programDir", s.programDir.replace('\\', '/'));
        call.put("outputDir", s.outputDir.replace('\\', '/'));
        call.put("cfg", s.config == null ? new LinkedHashMap<>() : s.config);
        if (cmd != null) call.put("cmd", cmd);
        String resultFile = new File(s.adapterDir, "fm-" + action + "-result.json").getAbsolutePath().replace('\\', '/');
        call.put("resultFile", resultFile);
        File cf = new File(s.adapterDir, "fm-" + action + "-config.json");
        com.fasterxml.jackson.databind.ObjectMapper om = new com.fasterxml.jackson.databind.ObjectMapper();
        om.configure(com.fasterxml.jackson.core.JsonGenerator.Feature.ESCAPE_NON_ASCII, true);
        Files.write(cf.toPath(), om.writeValueAsBytes(call));
        MatlabEngine eng = s.engine;
        eng.feval(0, "cd", s.adapterDir);
        eng.feval(0, "dmg_fullmode_task", cf.getAbsolutePath());
        File rf = new File(resultFile);
        if (!rf.isFile()) return null;
        Object parsed = new com.fasterxml.jackson.databind.ObjectMapper().readValue(rf, Object.class);
        if ("status".equals(action) && parsed instanceof Map) {
            writeStatusFile(s, (Map<String, Object>) parsed);
        }
        return (T) parsed;
    }

    /** status.json原子写(适配器目录;前端轮询只读文件)。 */
    private void writeStatusFile(FullmodeSession s, Map<String, Object> st) {
        try {
            File tmp = new File(s.adapterDir, "status.json.tmp");
            File dst = new File(s.adapterDir, "status.json");
            com.fasterxml.jackson.databind.ObjectMapper om = new com.fasterxml.jackson.databind.ObjectMapper();
            om.configure(com.fasterxml.jackson.core.JsonGenerator.Feature.ESCAPE_NON_ASCII, true);
            Files.write(tmp.toPath(), om.writeValueAsBytes(st));
            Files.move(tmp.toPath(), dst.toPath(), StandardCopyOption.REPLACE_EXISTING);
        } catch (Exception e) {
            log.debug("status.json写入失败", e);
        }
    }

    private void refreshFullmodeStatusFile(FullmodeSession s) {
        try {
            if (s.engine != null) {
                Map<String, Object> st = fevalFullmode(s, "status", null);
                if (st != null) writeStatusFile(s, st);
            }
        } catch (Exception ignore) { }
    }

    private void writeFullmodeIndex(FullmodeSession s) {
        Map<String, Object> idx = new LinkedHashMap<>();
        idx.put("runId", s.runId);
        idx.put("projectId", s.projectId);
        idx.put("engineId", s.engineId);
        idx.put("phase", s.phase);
        idx.put("message", s.message);
        idx.put("error", s.error);
        idx.put("createdAt", s.createdAt);
        idx.put("finishedAt", s.finishedAt);
        idx.put("config", s.config);
        idx.put("outputDir", s.outputDir);
        idx.put("kind", "fullmode");
        try {
            File metaDir = store.testbenchSessionDir(s.projectId);
            if (!metaDir.exists() && !metaDir.mkdirs()) throw new IOException("无法创建元数据目录: " + metaDir);
            new com.fasterxml.jackson.databind.ObjectMapper().writerWithDefaultPrettyPrinter()
                    .writeValue(store.testbenchSessionFile(s.projectId, s.runId), idx);
        } catch (Exception e) {
            log.warn("fullmode元数据写入失败", e);
        }
    }

    /* ================= 一次性任务(F-09设计点/F-10起动停车) ================= */

    public Map<String, Object> runTask(String projectId, String kind, Map<String, Object> cfg) throws IOException {
        if (!"design_point".equals(kind) && !"startstop".equals(kind)) {
            throw new IllegalArgumentException("未知试车台任务类型: " + kind);
        }
        String taskId = ("design_point".equals(kind) ? "DP-" : "SS-")
                + new java.text.SimpleDateFormat("yyyyMMdd_HHmmss").format(new Date());
        File workDir = store.testbenchWorkDir(projectId, taskId);
        File adapterDir = new File(workDir, "adapter");
        if (!adapterDir.exists() && !adapterDir.mkdirs()) throw new IOException("无法创建适配器目录");
        TaskRun r = new TaskRun();
        r.projectId = projectId;
        r.taskId = taskId;
        r.kind = kind;
        // 任务目录:合同由程序 local_prepare/sht_startstop_modeling_task('prepare') 自建
        r.taskDirectory = workDir.getAbsolutePath();
        r.adapterDir = adapterDir.getAbsolutePath();
        r.createdAt = System.currentTimeMillis();
        // 合同必需字段的缺省值(前端未提供时)
        cfg.putIfAbsent("modelMode", 0);
        cfg.putIfAbsent("engineId", "ENGINE-001");
        cfg.putIfAbsent("taskId", taskId.replaceAll("[^A-Za-z0-9_-]", "_"));
        if ("startstop".equals(kind)) {
            Object stages = cfg.get("requestedStages");
            if (!(stages instanceof List) || ((List<?>) stages).isEmpty()) {
                List<String> chain = new ArrayList<>();
                chain.add("maps"); chain.add("design"); chain.add("matrix");
                chain.add("physics"); chain.add("continuous"); chain.add("thermal");
                cfg.put("requestedStages", chain);
            }
        }
        r.config = cfg;
        r.message = "任务排队中";
        taskRuns.put(taskId, r);
        writeTaskIndex(r);
        taskExecutor.submit(() -> taskExec(r));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("taskId", taskId);
        out.put("phase", r.phase);
        return out;
    }

    /** design_point提交(commit需solve候选验证通过)。 */
    public Map<String, Object> commitDesignPoint(String projectId, String taskId) throws IOException {
        TaskRun r = requireTask(projectId, taskId);
        if (!"design_point".equals(r.kind)) throw new IllegalStateException("仅设计点任务支持commit");
        if (!"ENDED".equals(r.phase)) throw new IllegalStateException("任务尚未完成,不能commit");
        r.phase = "RUNNING";
        r.message = "提交设计(时间备份后写原选定MDL)";
        writeTaskIndex(r);
        taskExecutor.submit(() -> designPointCommit(r));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("accepted", true);
        return out;
    }

    public Map<String, Object> taskStatus(String projectId, String taskId) throws IOException {
        TaskRun r = requireTask(projectId, taskId);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("taskId", r.taskId);
        out.put("kind", r.kind);
        out.put("phase", r.phase);
        out.put("message", r.message);
        out.put("error", r.error);
        out.put("config", r.config);
        File rf = new File(r.adapterDir, "task-result.json");
        if (rf.exists()) {
            try {
                out.put("result", new com.fasterxml.jackson.databind.ObjectMapper().readValue(rf, Object.class));
            } catch (Exception ignore) { }
        }
        return out;
    }

    public List<Map<String, Object>> listTasks(String projectId) throws IOException {
        return listMeta(store.testbenchSessionDir(projectId), null);
    }

    private void taskExec(TaskRun r) {
        try {
            File progCopy = ensureProgramSource(r.projectId);
            MatlabEngine eng = MatlabEngine.startMatlab();
            r.engine = eng;
            try {
                eng.feval(0, "eval", "feature('DefaultCharacterSet', 'GBK')");
            } catch (Exception ce) {
                log.warn("试车台任务引擎字符集设置失败", ce);
            }
            if ("design_point".equals(r.kind)) {
                writeDesignPointAdapter(new File(r.adapterDir), progCopy);
                fevalTask(r, "dmg_designpoint_task", "solve", null);
            } else {
                writeStartStopAdapter(new File(r.adapterDir), progCopy);
                fevalTask(r, "dmg_startstop_task", "run", null);
            }
            r.phase = "ENDED";
            r.message = "design_point".equals(r.kind) ? "设计点求解完成;可查看结果或commit" : "起动停车任务完成";
            r.finishedAt = System.currentTimeMillis();
        } catch (Exception e) {
            log.error("试车台任务失败: {}", r.taskId, e);
            r.phase = "FAILED";
            r.error = e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
            r.message = "任务失败";
            r.finishedAt = System.currentTimeMillis();
        } finally {
            closeEngine(r.engine);
            r.engine = null;
            writeTaskIndex(r);
        }
    }

    private void designPointCommit(TaskRun r) {
        try {
            MatlabEngine eng = MatlabEngine.startMatlab();
            r.engine = eng;
            try {
                eng.feval(0, "eval", "feature('DefaultCharacterSet', 'GBK')");
            } catch (Exception ignore) { }
            File progCopy = ensureProgramSource(r.projectId);
            writeDesignPointAdapter(new File(r.adapterDir), progCopy);
            fevalTask(r, "dmg_designpoint_task", "commit", null);
            r.phase = "COMMITTED";
            r.message = "设计已提交(写入原选定MDL并复现)";
            r.finishedAt = System.currentTimeMillis();
        } catch (Exception e) {
            log.error("设计点commit失败: {}", r.taskId, e);
            r.phase = "ENDED"; // 保留solve结果
            r.error = e.getMessage();
            r.message = "commit失败:" + e.getMessage();
        } finally {
            closeEngine(r.engine);
            r.engine = null;
            writeTaskIndex(r);
        }
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> fevalTask(TaskRun r, String fn, String action, Map<String, Object> extra) throws Exception {
        Map<String, Object> call = new LinkedHashMap<>();
        call.put("action", action);
        call.put("programDir", ensureProgramSource(r.projectId).getAbsolutePath().replace('\\', '/'));
        call.put("taskDirectory", r.taskDirectory.replace('\\', '/'));
        call.put("cfg", r.config == null ? new LinkedHashMap<>() : r.config);
        if (extra != null) call.putAll(extra);
        String resultFile = new File(r.adapterDir, "task-result.json").getAbsolutePath().replace('\\', '/');
        call.put("resultFile", resultFile);
        File cf = new File(r.adapterDir, "task-config.json");
        com.fasterxml.jackson.databind.ObjectMapper om = new com.fasterxml.jackson.databind.ObjectMapper();
        om.configure(com.fasterxml.jackson.core.JsonGenerator.Feature.ESCAPE_NON_ASCII, true);
        Files.write(cf.toPath(), om.writeValueAsBytes(call));
        MatlabEngine eng = r.engine;
        eng.feval(0, "cd", r.adapterDir);
        eng.feval(0, fn, cf.getAbsolutePath());
        File rf = new File(resultFile);
        return rf.isFile() ? new com.fasterxml.jackson.databind.ObjectMapper().readValue(rf, Map.class) : new LinkedHashMap<>();
    }

    private TaskRun requireTask(String projectId, String taskId) throws IOException {
        TaskRun r = taskRuns.get(taskId);
        if (r == null) {
            // 进程重启后从元数据恢复只读视图
            File f = store.testbenchSessionFile(projectId, taskId);
            if (f.exists()) {
                Map<String, Object> m = new com.fasterxml.jackson.databind.ObjectMapper().readValue(f, Map.class);
                r = new TaskRun();
                r.projectId = projectId;
                r.taskId = taskId;
                r.kind = String.valueOf(m.getOrDefault("kind", "design_point"));
                r.phase = String.valueOf(m.getOrDefault("phase", "ENDED"));
                r.message = String.valueOf(m.getOrDefault("message", ""));
                r.taskDirectory = String.valueOf(m.getOrDefault("taskDirectory", ""));
                r.adapterDir = new File(store.testbenchWorkDir(projectId, taskId), "adapter").getAbsolutePath();
                r.config = (Map<String, Object>) m.get("config");
            } else {
                throw new IllegalStateException("任务不存在: " + taskId);
            }
        }
        return r;
    }

    private void writeTaskIndex(TaskRun r) {
        Map<String, Object> idx = new LinkedHashMap<>();
        idx.put("taskId", r.taskId);
        idx.put("kind", r.kind);
        idx.put("projectId", r.projectId);
        idx.put("phase", r.phase);
        idx.put("message", r.message);
        idx.put("error", r.error);
        idx.put("createdAt", r.createdAt);
        idx.put("finishedAt", r.finishedAt);
        idx.put("config", r.config);
        idx.put("taskDirectory", r.taskDirectory);
        try {
            File metaDir = store.testbenchSessionDir(r.projectId);
            if (!metaDir.exists() && !metaDir.mkdirs()) throw new IOException("无法创建元数据目录");
            new com.fasterxml.jackson.databind.ObjectMapper().writerWithDefaultPrettyPrinter()
                    .writeValue(store.testbenchSessionFile(r.projectId, r.taskId), idx);
        } catch (Exception e) {
            log.warn("试车台任务元数据写入失败", e);
        }
    }

    /* ================= 适配器 ================= */

    /** dmg_fullmode_task.m:sht_fullmode_session 动作转发(config JSON构造user覆盖)。 */
    private void writeFullmodeAdapter(File ad, File progCopy) throws IOException {
        StringBuilder m = new StringBuilder();
        m.append("function r = dmg_fullmode_task(configFile)\n");
        m.append("% F-11 fullmode session adapter (generated by DataModelGov)\n");
        m.append("% ASCII-only: engine charset is GBK; keep this file free of non-ASCII text.\n");
        m.append("c = jsondecode(fileread(configFile));\n");
        m.append("addpath(c.programDir, '-begin');\n");
        m.append("rehash;\n");
        m.append("user = struct();\n");
        m.append("if isfield(c, 'cfg') && isstruct(c.cfg)\n");
        m.append("    uf = fieldnames(c.cfg);\n");
        m.append("    for k = 1:numel(uf), user.(uf{k}) = c.cfg.(uf{k}); end\n");
        m.append("end\n");
        m.append("switch lower(c.action)\n");
        m.append("    case 'prepare'\n");
        m.append("        sht_fullmode_session('prepare', user);\n");
        m.append("        r = sht_fullmode_session('begin');\n");
        m.append("    case 'submit'\n");
        m.append("        r = sht_fullmode_session('submit', c.cmd);\n");
        m.append("    case 'advance'\n");
        m.append("        r = sht_fullmode_session('advance', c.cmd.n);\n");
        m.append("    case 'close'\n");
        m.append("        sht_fullmode_session('close'); r = 'ok'; % close has no output\n");
        m.append("    otherwise\n");
        m.append("        r = sht_fullmode_session(lower(c.action));\n");
        m.append("end\n");
        m.append("r = dmg_jsonable(r);\n");
        m.append("payload = jsonencode(r);\n");
        m.append("fid = fopen(c.resultFile, 'w', 'n', 'UTF-8');\n");
        m.append("fwrite(fid, payload, 'char');\n");
        m.append("fclose(fid);\n");
        m.append("r = 'ok';\n");
        m.append("end\n");
        m.append(jsonableFn());
        Files.write(new File(ad, "dmg_fullmode_task.m").toPath(), m.toString().getBytes(StandardCharsets.UTF_8));
    }

    /** dmg_designpoint_task.m:sht_design_point_task solve/commit/inspect 转发。 */
    private void writeDesignPointAdapter(File ad, File progCopy) throws IOException {
        StringBuilder m = new StringBuilder();
        m.append("function r = dmg_designpoint_task(configFile)\n");
        m.append("% F-09 design point adapter (generated by DataModelGov)\n");
        m.append("% ASCII-only: engine charset is GBK; keep this file free of non-ASCII text.\n");
        m.append("c = jsondecode(fileread(configFile));\n");
        m.append("addpath(fullfile(c.programDir, 'design_point_modeling'), '-begin');\n");
        m.append("addpath(c.programDir, '-begin');\n");
        m.append("rehash;\n");
        m.append("switch lower(c.action)\n");
        m.append("    case 'solve'\n");
        m.append("        u = c.cfg;\n");
        // local_prepare asserts the task directory does not exist; program creates it.
        m.append("        u.taskDirectory = fullfile(c.taskDirectory, 'task');\n");
        m.append("        r = sht_design_point_task('solve', u);\n");
        m.append("    case 'commit'\n");
        m.append("        r = sht_design_point_task('commit', fullfile(c.taskDirectory, 'task'));\n");
        m.append("    otherwise\n");
        m.append("        r = sht_design_point_task(lower(c.action), fullfile(c.taskDirectory, 'task'));\n");
        m.append("end\n");
        m.append("r = dmg_jsonable(r);\n");
        m.append("payload = jsonencode(r);\n");
        m.append("fid = fopen(c.resultFile, 'w', 'n', 'UTF-8');\n");
        m.append("fwrite(fid, payload, 'char');\n");
        m.append("fclose(fid);\n");
        m.append("r = 'ok';\n");
        m.append("end\n");
        m.append(jsonableFn());
        Files.write(new File(ad, "dmg_designpoint_task.m").toPath(), m.toString().getBytes(StandardCharsets.UTF_8));
    }

    /** dmg_startstop_task.m:prepare→runStage链(独立离线入口同款编排)。 */
    private void writeStartStopAdapter(File ad, File progCopy) throws IOException {
        StringBuilder m = new StringBuilder();
        m.append("function r = dmg_startstop_task(configFile)\n");
        m.append("% F-10 startstop modeling adapter (generated by DataModelGov)\n");
        m.append("% ASCII-only: engine charset is GBK; keep this file free of non-ASCII text.\n");
        m.append("c = jsondecode(fileread(configFile));\n");
        m.append("addpath(fullfile(c.programDir, 'startupstop_modeling'), '-begin');\n");
        m.append("addpath(c.programDir, '-begin');\n");
        m.append("rehash;\n");
        m.append("switch lower(c.action)\n");
        m.append("    case 'run'\n");
        m.append("        u = c.cfg;\n");
        m.append("        u.taskDirectory = fullfile(c.taskDirectory, 'task');\n");
        m.append("        cfg = sht_startstop_modeling_config(u);\n");
        m.append("        task = sht_startstop_modeling_task('prepare', cfg);\n");
        m.append("        if ~strcmp(task.status, 'blocked')\n");
        m.append("            for k = 1:numel(cfg.requestedStages)\n");
        m.append("                task = sht_startstop_modeling_task('runstage', task.taskDirectory, cfg.requestedStages{k});\n");
        m.append("                if any(strcmp(task.status, {'paused','failed','blocked'})), break; end\n");
        m.append("            end\n");
        m.append("        end\n");
        m.append("        r = task;\n");
        m.append("    otherwise\n");
        m.append("        r = sht_startstop_modeling_task(lower(c.action), fullfile(c.taskDirectory, 'task'));\n");
        m.append("end\n");
        m.append("r = dmg_jsonable(r);\n");
        m.append("payload = jsonencode(r);\n");
        m.append("fid = fopen(c.resultFile, 'w', 'n', 'UTF-8');\n");
        m.append("fwrite(fid, payload, 'char');\n");
        m.append("fclose(fid);\n");
        m.append("r = 'ok';\n");
        m.append("end\n");
        m.append(jsonableFn());
        Files.write(new File(ad, "dmg_startstop_task.m").toPath(), m.toString().getBytes(StandardCharsets.UTF_8));
    }

    private static String jsonableFn() {
        StringBuilder m = new StringBuilder();
        m.append("function s = dmg_jsonable(v)\n");
        m.append("if isa(v,'table')\n");
        m.append("    s = dmg_jsonable(table2struct(v));\n");
        m.append("elseif isstruct(v)\n");
        m.append("    s = struct(); f = fieldnames(v);\n");
        m.append("    for i = 1:numel(f)\n");
        m.append("        s.(f{i}) = dmg_jsonable(v.(f{i}));\n");
        m.append("    end\n");
        m.append("elseif iscell(v)\n");
        m.append("    for i = 1:numel(v), v{i} = dmg_jsonable(v{i}); end\n");
        m.append("    s = v;\n");
        m.append("else\n");
        m.append("    s = v;\n");
        m.append("end\n");
        m.append("end\n");
        return m.toString();
    }

    /* ================= 程序源与工具 ================= */

    /** m_program_adaptive_tune程序源:项目工作目录优先→target/classes→jar解压兜底。 */
    private synchronized File ensureProgramSource(String projectId) throws IOException {
        File user = workProgramsDir(projectId);
        if (new File(user, "Start_FullModeSimulation_01.m").isFile()) return user;

        File c1 = new File("target/classes/" + R06_IN_CLASSPATH + "/" + PROG_SUBDIR);
        File c2 = new File("datamodelgov-server/target/classes/" + R06_IN_CLASSPATH + "/" + PROG_SUBDIR);
        if (new File(c1, "Start_FullModeSimulation_01.m").isFile()) return c1;
        if (new File(c2, "Start_FullModeSimulation_01.m").isFile()) return c2;

        Path jar = classpathProgramJar();
        if (jar == null) {
            throw new IOException("未找到试车台程序(m_program_adaptive_tune);请在项目工作目录 program/ 下放置程序");
        }
        log.info("从jar解压 m_program_adaptive_tune 到项目工作目录: {} -> {}", jar, user);
        Files.createDirectories(user.toPath());
        String[] prefixes = {
                "BOOT-INF/classes/" + R06_IN_CLASSPATH + "/" + PROG_SUBDIR + "/",
                R06_IN_CLASSPATH + "/" + PROG_SUBDIR + "/"
        };
        int n = 0;
        try (java.util.zip.ZipFile zf = new java.util.zip.ZipFile(jar.toFile())) {
            java.util.Enumeration<? extends java.util.zip.ZipEntry> en = zf.entries();
            while (en.hasMoreElements()) {
                java.util.zip.ZipEntry e = en.nextElement();
                if (e.isDirectory()) continue;
                String rel = null;
                for (String prefix : prefixes) {
                    if (e.getName().startsWith(prefix)) { rel = e.getName().substring(prefix.length()); break; }
                }
                if (rel == null || rel.isEmpty()) continue;
                File out = new File(user, rel);
                Files.createDirectories(out.getParentFile().toPath());
                Files.copy(zf.getInputStream(e), out.toPath(), StandardCopyOption.REPLACE_EXISTING);
                n++;
            }
        }
        if (!new File(user, "Start_FullModeSimulation_01.m").isFile()) {
            throw new IOException("jar 内未找到试车台程序(解压 " + n + " 个文件)");
        }
        return user;
    }

    private File workProgramsDir(String projectId) throws IOException {
        try {
            EngineModels.EngineProject proj = store.getProject(projectId);
            if (proj != null && proj.getWorkdir() != null && !proj.getWorkdir().isEmpty()) {
                return new File(new File(proj.getWorkdir()), "program/m_program_adaptive_tune");
            }
        } catch (IOException e) {
            log.warn("读取项目工作目录失败: {}", projectId);
        }
        return new File(store.projectDir(projectId), "program/m_program_adaptive_tune");
    }

    private Path classpathProgramJar() {
        try (Stream<Path> roots = Files.walk(Paths.get("").toAbsolutePath(), 3)) {
            return roots.filter(pp -> pp.getFileName() != null
                            && pp.getFileName().toString().endsWith(".jar")
                            && pp.getFileName().toString().startsWith("datamodelgov-server"))
                    .findFirst().orElse(null);
        } catch (IOException e) {
            return null;
        }
    }

    /** 元数据目录扫描(kind过滤:fullmode会话带kind=fullmode;任务列表排除fullmode)。 */
    private List<Map<String, Object>> listMeta(File dir, String kindFilter) {
        List<Map<String, Object>> list = new ArrayList<>();
        File[] files = dir.listFiles((d, n) -> n.toLowerCase().endsWith(".json"));
        if (files == null) return list;
        com.fasterxml.jackson.databind.ObjectMapper om = new com.fasterxml.jackson.databind.ObjectMapper();
        for (File f : files) {
            try {
                Map<String, Object> m = om.readValue(f, Map.class);
                String kind = String.valueOf(m.getOrDefault("kind", "design_point"));
                if ("fm-".equals(kindFilter) && !"fullmode".equals(kind)) continue;
                if (!"fm-".equals(kindFilter) && "fullmode".equals(kind)) continue;
                File od = new File(String.valueOf(m.getOrDefault("outputDir", m.getOrDefault("taskDirectory", ""))));
                m.put("hasExcel", findExcelRecursive(od) != null);
                list.add(m);
            } catch (Exception e) {
                log.warn("试车台元数据读取失败: {}", f);
            }
        }
        list.sort((a, b) -> Long.compare(
                b.get("createdAt") instanceof Number ? ((Number) b.get("createdAt")).longValue() : 0,
                a.get("createdAt") instanceof Number ? ((Number) a.get("createdAt")).longValue() : 0));
        return list;
    }

    private File findExcelRecursive(File dir) {
        if (dir == null || !dir.isDirectory()) return null;
        try (Stream<Path> walk = Files.walk(dir.toPath(), 4)) {
            return walk.map(Path::toFile)
                    .filter(f -> f.isFile() && f.getName().toLowerCase().endsWith(".xlsx"))
                    .max(Comparator.comparingLong(File::lastModified))
                    .orElse(null);
        } catch (IOException e) {
            return null;
        }
    }

    private void logLine(FullmodeSession s, String line) {
        MatlabLogRing.append("[FM " + s.runId + "] " + line);
    }

    private void closeEngine(MatlabEngine eng) {
        if (eng != null) {
            try {
                eng.close();
            } catch (Exception e) {
                log.warn("引擎关闭失败", e);
            }
        }
    }

    private boolean isTerminal(String phase) {
        return "ENDED".equals(phase) || "FAILED".equals(phase) || "CLOSED".equals(phase) || "COMMITTED".equals(phase);
    }
}
