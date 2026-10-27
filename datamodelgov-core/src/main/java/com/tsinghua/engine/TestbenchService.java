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

    @Autowired
    private EngineTestbenchRecordService testbenchRecordService;

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

    @org.springframework.beans.factory.annotation.Value("${matlab.engine.home:}")
    private String matlabHome;

    @org.springframework.beans.factory.annotation.Value("${matlab.engine.enabled:true}")
    private boolean engineEnabled;

    private volatile com.tsinghua.matlab.MatlabEnginePool enginePool;

    /** 任务执行引擎池(懒加载,size=1;起动停车/设计点任务串行借用,stdout自动落盘+回调)。 */
    private com.tsinghua.matlab.MatlabEnginePool requirePool() {
        if (!engineEnabled) throw new IllegalStateException("MATLAB引擎被禁用(matlab.engine.enabled=false)");
        if (enginePool == null) {
            synchronized (this) {
                if (enginePool == null) {
                    enginePool = new com.tsinghua.matlab.MatlabEnginePool(1, matlabHome);
                    log.info("试车台接入层 MATLAB 引擎池已创建(懒加载): poolSize=1");
                }
            }
        }
        return enginePool;
    }

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
        /** 安全停止请求(效果07-20):置位后MATLAB在当前阶段完成后协同退出;可撤销。 */
        volatile boolean stopRequested;
        /** MATLAB stdout 环形缓冲(约200KB),状态接口取尾部给前端显示 */
        final StringBuilder logBuf = new StringBuilder();

        void appendLog(String line) {
            if (line == null || line.isEmpty()) return;
            synchronized (logBuf) {
                logBuf.append(line).append('\n');
                if (logBuf.length() > 200000) logBuf.delete(0, logBuf.length() - 100000);
            }
        }

        String logTail(int n) {
            synchronized (logBuf) {
                String s = logBuf.toString();
                if (s.isEmpty()) return "";
                String[] lines = s.split("\n", -1);
                int from = Math.max(0, lines.length - n);
                StringBuilder b = new StringBuilder();
                for (int i = from; i < lines.length; i++) { if (i > from) b.append('\n'); b.append(lines[i]); }
                return b.toString();
            }
        }
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
            log.info("全模式推进恢复: runId={}", s.runId);
            fmExecutor.submit(() -> fullmodeResumeThenLoop(s));
        } else {
            s.phase = "RUNNING";
            s.message = "仿真运行中";
            writeFullmodeIndex(s);
            log.info("全模式推进启动: runId={} engineId={}", s.runId, s.engineId);
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
                    log.info("全模式命令消费(块间): runId={} kind={}", s.runId, kind);
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
            Map<String, Object> saveCmd = new LinkedHashMap<>();
            saveCmd.put("folder", new File(s.outputDir, "save").getAbsolutePath().replace('\\', '/'));
            fevalFullmode(s, "save", saveCmd);
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

    /** 命令:pause即时;save在暂停时即时保存;stop/操纵类入块间队列(暂停时入会话待恢复后生效)。 */
    public Map<String, Object> fullmodeCommand(String projectId, String kind, Object value) throws IOException {
        FullmodeSession s = requireFullmode(projectId);
        if (!"RUNNING".equals(s.phase) && !"READY".equals(s.phase) && !"PAUSED".equals(s.phase)) {
            throw new IllegalStateException("当前状态" + s.phase + "不接受命令");
        }
        Map<String, Object> out = new LinkedHashMap<>();
        if ("save".equals(kind)) {
            if (!"PAUSED".equals(s.phase)) {
                throw new IllegalStateException("暂停后才能保存完整快照;运行中请先暂停");
            }
            try {
                Map<String, Object> saveCmd = new LinkedHashMap<>();
                saveCmd.put("folder", new File(s.outputDir, "save").getAbsolutePath().replace('\\', '/'));
                fevalFullmode(s, "save", saveCmd);
                refreshFullmodeStatusFile(s);
                logLine(s, "暂停中保存完整快照与Excel");
            } catch (IOException e) {
                throw e;
            } catch (Exception e) {
                throw new IllegalStateException("保存快照失败: " + e.getMessage(), e);
            }
            out.put("accepted", true);
            out.put("note", "已保存完整快照与Excel(本次独立保存目录)");
            return out;
        }
        Map<String, Object> cmd = new LinkedHashMap<>();
        cmd.put("kind", kind);
        if (value != null) cmd.put("value", value);
        fmCommands.add(cmd);
        log.info("全模式命令入队: runId={} kind={} value={} 队列深度={}", s.runId, kind, value, fmCommands.size());
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

    /** 单条历史结果(适配器result动作产物adapter/fm-result-result.json;旧result.json兜底)。 */
    public Map<String, Object> fullmodeResult(String projectId, String runId) throws IOException {
        File work = store.testbenchWorkDir(projectId, runId);
        File f = new File(work, "adapter/fm-result-result.json");
        if (!f.isFile()) f = new File(work, "result.json");
        if (!f.isFile()) return null;
        return new com.fasterxml.jackson.databind.ObjectMapper().readValue(f, Map.class);
    }

    public File fullmodeExcel(String projectId, String runId) throws IOException {
        return findExcelRecursive(store.testbenchWorkDir(projectId, runId));
    }

    /** 从快照恢复会话(效果image166~169):snapshotFile为会话目录内绝对路径;无活动会话时新建后恢复。 */
    public Map<String, Object> fullmodeRestore(String projectId, String runId) throws IOException {
        synchronized (fmLock) {
            FullmodeSession cur = fmSession;
            if (cur != null && !isTerminal(cur.phase)) {
                throw new IllegalStateException("已有全模式会话在" + cur.phase + "(runId=" + cur.runId + "),请先关闭");
            }
            File snap = findFileRecursive(store.testbenchWorkDir(projectId, runId), "snapshot.mat");
            if (snap == null) throw new IOException("该记录未找到快照文件(snapshot.mat)");
            Map<String, Object> cfg = listMeta(store.testbenchSessionDir(projectId), "fm-").stream()
                    .filter(m -> runId.equals(String.valueOf(m.get("runId")))).findFirst()
                    .map(m -> (Map<String, Object>) m.get("config")).orElse(new LinkedHashMap<>());
            Map<String, Object> prep = fullmodePrepare(projectId, cfg);
            FullmodeSession s = fmSession;
            if (s == null) throw new IOException("恢复会话创建失败");
            final File snapFile = snap;
            s.phase = "PREPARING";
            s.message = "恢复快照: " + snapFile.getName();
            writeFullmodeIndex(s);
            fmExecutor.submit(() -> {
                try {
                    Map<String, Object> restoreCmd = new LinkedHashMap<>();
                    restoreCmd.put("snapshotFile", snapFile.getAbsolutePath().replace('\\', '/'));
                    fevalFullmode(s, "restore", restoreCmd);
                    s.phase = "PAUSED";
                    s.message = "快照恢复完成;处于暂停态,可继续推进";
                    writeFullmodeIndex(s);
                    refreshFullmodeStatusFile(s);
                    logLine(s, "快照恢复完成: " + snapFile.getAbsolutePath());
                    writeFullmodeIndex(s);
                } catch (Exception e) {
                    log.error("fullmode恢复失败: {}", runId, e);
                    s.phase = "FAILED";
                    s.error = "快照恢复失败: " + e.getMessage();
                    s.finishedAt = System.currentTimeMillis();
                    writeFullmodeIndex(s);
                }
            });
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("runId", prep.get("runId"));
            out.put("phase", s.phase);
            return out;
        }
    }

    /** 在目录树中递归查找指定文件名(取修改时间最新的一个);找不到返回null。 */
    private File findFileRecursive(File dir, String name) {
        if (dir == null || !dir.isDirectory()) return null;
        File[] list = dir.listFiles();
        if (list == null) return null;
        File best = null;
        for (File f : list) {
            if (f.isDirectory()) {
                File hit = findFileRecursive(f, name);
                if (hit != null && (best == null || hit.lastModified() > best.lastModified())) best = hit;
            } else if (name.equalsIgnoreCase(f.getName()) && (best == null || f.lastModified() > best.lastModified())) {
                best = f;
            }
        }
        return best;
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
            // 适配器prepare分支内部已连续执行 prepare+begin(会话lifecycle=running);
            // 这里再单独发begin会走otherwise分支重复触发"只有prepared会话可以begin"断言
            fevalFullmode(s, "prepare", null);
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
        idx.put("hasExcel", findExcelRecursive(new File(s.outputDir == null ? "" : s.outputDir)) != null);
        try {
            File metaDir = store.testbenchSessionDir(s.projectId);
            if (!metaDir.exists() && !metaDir.mkdirs()) throw new IOException("无法创建元数据目录: " + metaDir);
            new com.fasterxml.jackson.databind.ObjectMapper().writerWithDefaultPrettyPrinter()
                    .writeValue(store.testbenchSessionFile(s.projectId, s.runId), idx);
        } catch (Exception e) {
            log.warn("fullmode元数据写入失败", e);
        }
        // 试车台记录清单(IginX)同步,失败仅告警
        testbenchRecordService.upsertFromIndex(s.projectId, idx);
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
            List<String> chain;
            if (!(stages instanceof List) || ((List<?>) stages).isEmpty()) {
                chain = new ArrayList<>();
                chain.add("maps"); chain.add("design"); chain.add("matrix");
                chain.add("physics"); chain.add("continuous"); chain.add("thermal");
                cfg.put("requestedStages", chain);
            } else {
                chain = new ArrayList<>();
                for (Object o : (List<?>) stages) chain.add(String.valueOf(o));
            }
            // 六部件设计解(design)为合同级显式来源:必须选定已提交(commit)的设计点任务,
            // 其 task/MiddleData/design_state.mat 才存在(sht_design_point_task commit 时写出);
            // 模型/DLL目录同时指向该设计点的候选目录(与官方SimpleTest链一致)。
            Object dpObj = cfg.remove("designTaskId");
            if (chain.contains("design")) {
                String dpId = dpObj == null ? "" : String.valueOf(dpObj).trim();
                if (dpId.isEmpty()) {
                    throw new IllegalArgumentException(
                            "阶段链含design(设计解):必须先完成设计点求解并提交(commit),再选择该设计点任务作为来源;或去掉design阶段");
                }
                TaskRun dp = requireTask(projectId, dpId);
                if (!"design_point".equals(dp.kind)) {
                    throw new IllegalArgumentException("所选任务 " + dpId + " 不是设计点任务");
                }
                if ("RUNNING".equals(dp.phase) || "PREPARING".equals(dp.phase)) {
                    throw new IllegalArgumentException("设计点任务 " + dpId + " 仍在执行中,请等待完成后重试");
                }
                File dpWork = store.testbenchWorkDir(projectId, dpId);
                File stateFile = new File(dpWork, "task" + File.separator + "MiddleData" + File.separator + "design_state.mat");
                if (!stateFile.isFile()) {
                    throw new IllegalArgumentException("设计点任务 " + dpId
                            + " 缺少 MiddleData/design_state.mat——请先在该设计点任务页完成\"提交设计(commit)\"(仅求解未提交不产出设计状态)");
                }
                // 候选目录:优先取设计点 result.json 里的 candidateDirectory
                String candDir = null;
                try {
                    File rf = new File(dp.adapterDir == null ? new File(dpWork, "adapter") : new File(dp.adapterDir), "task-result.json");
                    if (rf.isFile()) {
                        Map<?, ?> res = new com.fasterxml.jackson.databind.ObjectMapper().readValue(rf, Map.class);
                        Object cd = res == null ? null : res.get("candidateDirectory");
                        if (cd != null && new File(String.valueOf(cd)).isDirectory()) candDir = String.valueOf(cd);
                    }
                } catch (Exception ignore) { }
                if (candDir == null) {
                    File guess = new File(dpWork, "task" + File.separator + "candidate");
                    if (guess.isDirectory()) candDir = guess.getAbsolutePath();
                }
                if (candDir == null) {
                    throw new IllegalArgumentException("无法定位设计点任务 " + dpId + " 的候选目录(candidate);请确认该任务已完成求解");
                }
                Map<String, Object> source = new LinkedHashMap<>();
                source.put("modelDirectory", candDir.replace('\\', '/'));
                source.put("dllDirectory", candDir.replace('\\', '/'));
                Object mf = dp.config == null ? null : dp.config.get("modelFile");
                if (mf != null && !String.valueOf(mf).isEmpty()) source.put("modelFile", String.valueOf(mf));
                Object mm = dp.config == null ? null : dp.config.get("modelMode");
                if (mm != null) cfg.put("modelMode", mm); // 与设计点保持一致(V1/V2 MDL)
                source.put("designStateFile", stateFile.getAbsolutePath().replace('\\', '/'));
                cfg.put("source", source);
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

    /** 起动停车模型包保存(F-10 savepackage): 导出完整包到<workdir>/files/model/,并登记模型成果。 */
    /** 保存模型包(异步受理):MATLAB引擎启动+导出约1-3分钟,HTTP立即返回,前端经 /tasks/{id}/status 轮询进度。 */
    public Map<String, Object> startstopSavePackage(String projectId, String taskId, String packageName) throws IOException {
        TaskRun r = requireTask(projectId, taskId);
        if (!"startstop".equals(r.kind)) throw new IllegalStateException("仅起动停车任务支持保存模型包");
        synchronized (r) {
            if (!"ENDED".equals(r.phase)) {
                throw new IllegalStateException("校核执行完成后才能保存模型包(当前:" + r.phase + ")");
            }
            if ("RUNNING".equals(r.phase)) throw new IllegalStateException("保存正在进行中,请稍候");
            r.phase = "RUNNING";
            r.error = null;
            r.message = "保存模型包: 正在启动MATLAB引擎...";
            r.finishedAt = null;
        }
        final String pkgName = packageName;
        taskExecutor.submit(() -> {
            try {
                doSavePackageWork(projectId, r, pkgName);
            } catch (Exception e) {
                log.error("保存起停模型包失败: {}", taskId, e);
                r.phase = "FAILED";
                r.error = "保存模型包失败: " + e.getMessage();
                r.message = r.error;
                r.finishedAt = System.currentTimeMillis();
            }
        });
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("taskId", taskId);
        out.put("phase", "RUNNING");
        out.put("note", "保存已受理;MATLAB引擎启动与导出约需1-3分钟,请轮询任务状态");
        return out;
    }

    /** 保存包执行体(后台线程):引擎启动→写适配器→savepackage→登记模型成果。 */
    private void doSavePackageWork(String projectId, TaskRun r, String packageName) throws IOException {
        Map<String, Object> out = new LinkedHashMap<>();
        MatlabEngine eng = null;
        try {
            File progCopy = ensureProgramSource(projectId);
            eng = MatlabEngine.startMatlab();
            r.message = "保存模型包: 引擎已启动,写入适配器...";
            try {
                eng.feval(0, "eval", "feature('DefaultCharacterSet', 'GBK')");
            } catch (Exception ignore) { }
            writeStartStopAdapter(new File(r.adapterDir), progCopy);
            // 保存目标:<workdir>/files/model/SSPackage-<taskId>-<ts>(合同要求目标不存在,不覆盖历史包)
            File modelDir = fileLibraryModelDir(projectId);
            String destName = "SSPackage-" + r.taskId + "-" + System.currentTimeMillis();
            File dest = new File(modelDir, destName);
            Map<String, Object> call = new LinkedHashMap<>();
            call.put("action", "savepackage");
            call.put("programDir", progCopy.getAbsolutePath().replace(File.separatorChar, '/'));
            call.put("taskDirectory", r.taskDirectory.replace(File.separatorChar, '/'));
            call.put("destination", dest.getAbsolutePath().replace(File.separatorChar, '/'));
            File saveResult = new File(r.adapterDir, "savepackage-result.json");
            call.put("resultFile", saveResult.getAbsolutePath().replace(File.separatorChar, '/'));
            File cf = new File(r.adapterDir, "savepackage-config.json");
            com.fasterxml.jackson.databind.ObjectMapper om = new com.fasterxml.jackson.databind.ObjectMapper();
            om.configure(com.fasterxml.jackson.core.JsonGenerator.Feature.ESCAPE_NON_ASCII, true);
            Files.write(cf.toPath(), om.writeValueAsBytes(call));
            eng.feval(0, "cd", r.adapterDir);
            r.message = "保存模型包: 正在导出MDL/DLL/MAP与交付文件...";
            eng.feval(0, "dmg_startstop_task", cf.getAbsolutePath());
            if (saveResult.isFile()) {
                Map<String, Object> saved = new com.fasterxml.jackson.databind.ObjectMapper().readValue(saveResult, Map.class);
                out.put("saved", saved);
            }
            out.put("destination", dest.getAbsolutePath());
            // 登记模型成果(公开起停模型包:实际地图、MDL、DLL/头文件、设计种子和热配置)
            EngineModels.ModelAsset m = new EngineModels.ModelAsset();
            m.setProjectId(projectId);
            m.setTaskId(r.taskId);
            m.setName(packageName != null && !packageName.isEmpty() ? packageName : "起停模型包-" + r.taskId);
            m.setSourceBusiness("起动停车建模");
            m.setStage("模型包");
            m.setRoute("—");
            try {
                EngineModels.EngineProject p = store.getProject(projectId);
                if (p != null) m.setEngineId(p.getEngineId());
            } catch (Exception ignore) { }
            r.message = "保存模型包: 登记模型成果...";
            store.saveModel(m);
            out.put("modelAssetId", m.getId());
            out.put("modelName", m.getName());
            // 落盘到task-result.json:保存完成后 /tasks/{id}/status 的result字段可直接看到目标路径与成果ID
            Files.write(new File(r.adapterDir, "task-result.json").toPath(),
                    new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsBytes(out));
            r.phase = "ENDED";
            r.message = "模型包已保存: " + dest.getAbsolutePath();
            r.finishedAt = System.currentTimeMillis();
            log.info("起停模型包保存完成: task={} dest={}", r.taskId, dest.getAbsolutePath());
        } catch (Exception e) {
            throw new IOException("保存模型包失败: " + e.getMessage(), e);
        } finally {
            closeEngine(eng);
        }
    }

    /** 文件库模型类目录(<workdir>/files/model)。 */
    private File fileLibraryModelDir(String projectId) throws IOException {
        EngineModels.EngineProject p = store.getProject(projectId);
        if (p == null || p.getWorkdir() == null || p.getWorkdir().isEmpty()) {
            throw new IOException("项目不存在或工作目录未配置: " + projectId);
        }
        return new File(new File(p.getWorkdir()), "files/model");
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
        // MATLAB 运行日志尾部(前端校核执行页显示):内存环形缓冲优先,空则兜底读落盘日志
        String tail = r.logTail(150);
        if (tail == null || tail.isEmpty()) {
            File lf = new File(r.adapterDir, "task-run.log");
            if (lf.isFile()) tail = tailFileLines(lf, 150);
        }
        out.put("logTail", tail == null ? "" : tail);
        out.put("stopRequested", r.stopRequested);
        return out;
    }

    /** 安全停止请求(效果07-20):阶段完成后协同中断;cancel=true撤销请求。 */
    public Map<String, Object> requestTaskStop(String projectId, String taskId, boolean cancel) throws IOException {
        TaskRun r = requireTask(projectId, taskId);
        r.stopRequested = !cancel;
        r.appendLog(cancel ? "[java] 已取消安全停止请求,任务将继续执行"
                : "[java] 已请求安全停止:当前阶段完成后退出(不卸载DLL,不伪装成内部续跑)");
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("taskId", r.taskId);
        out.put("stopRequested", r.stopRequested);
        return out;
    }

    /** 任务产物清单:相对taskDirectory的文件树(排除二进制中间物),供校核结果页读取真实阶段输出。 */
    public List<Map<String, Object>> taskArtifacts(String projectId, String taskId) throws IOException {
        TaskRun r = requireTask(projectId, taskId);
        List<Map<String, Object>> out = new ArrayList<>();
        File root = new File(r.taskDirectory);
        if (!root.isDirectory()) return out;
        try (Stream<java.nio.file.Path> stream = Files.walk(root.toPath(), 6)) {
            stream.limit(4000).forEach(p -> {
                File f = p.toFile();
                String rel = root.toPath().relativize(p).toString().replace('\\', '/');
                if (rel.isEmpty()) return;
                String name = f.getName();
                String ext = name.contains(".") ? name.substring(name.lastIndexOf('.') + 1).toLowerCase() : "";
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("path", rel);
                m.put("name", name);
                m.put("dir", f.isDirectory());
                m.put("size", f.isFile() ? f.length() : 0L);
                m.put("ext", ext);
                out.add(m);
            });
        } catch (Exception e) {
            log.warn("任务产物清单读取失败: {}", taskId, e);
        }
        return out;
    }

    /** 读取单个任务产物:text类返回内容,image类返回base64(供前端data URL渲染,规避img跨认证)。 */
    public Map<String, Object> taskArtifact(String projectId, String taskId, String rel) throws IOException {
        TaskRun r = requireTask(projectId, taskId);
        File root = new File(r.taskDirectory).getCanonicalFile();
        File f = new File(root, rel).getCanonicalFile();
        if (!f.getPath().startsWith(root.getPath())) throw new IllegalStateException("非法产物路径");
        if (!f.isFile()) throw new IllegalStateException("产物不存在: " + rel);
        String name = f.getName();
        String ext = name.contains(".") ? name.substring(name.lastIndexOf('.') + 1).toLowerCase() : "";
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("path", rel.replace('\\', '/'));
        out.put("name", name);
        out.put("size", f.length());
        if (ext.equals("png") || ext.equals("jpg") || ext.equals("jpeg")) {
            out.put("kind", "image");
            out.put("contentType", ext.equals("png") ? "image/png" : "image/jpeg");
            out.put("base64", java.util.Base64.getEncoder().encodeToString(Files.readAllBytes(f.toPath())));
        } else if (ext.equals("md") || ext.equals("csv") || ext.equals("txt") || ext.equals("log")
                || ext.equals("json") || ext.equals("map") || ext.equals("m")) {
            out.put("kind", "text");
            out.put("content", new String(Files.readAllBytes(f.toPath()), StandardCharsets.UTF_8));
        } else {
            out.put("kind", "binary");
        }
        return out;
    }

    /** 读取日志文件最后 n 行(UTF-8;任务重启后内存缓冲为空时兜底)。 */
    private String tailFileLines(File f, int n) {
        try {
            java.util.Deque<String> dq = new java.util.ArrayDeque<>(n);
            try (java.io.BufferedReader br = new java.io.BufferedReader(
                    new java.io.InputStreamReader(new java.io.FileInputStream(f), java.nio.charset.StandardCharsets.UTF_8))) {
                String line;
                while ((line = br.readLine()) != null) {
                    if (dq.size() >= n) dq.pollFirst();
                    dq.addLast(line);
                }
            }
            return String.join("\n", dq);
        } catch (Exception e) {
            return "";
        }
    }

    public List<Map<String, Object>> listTasks(String projectId) throws IOException {
        return listMeta(store.testbenchSessionDir(projectId), null);
    }

    private void taskExec(TaskRun r) {
        try {
            File progCopy = ensureProgramSource(r.projectId);
            boolean dp = "design_point".equals(r.kind);
            if (dp) writeDesignPointAdapter(new File(r.adapterDir), progCopy);
            else writeStartStopAdapter(new File(r.adapterDir), progCopy);
            runTaskViaRunner(r, dp ? "dmg_designpoint_task" : "dmg_startstop_task", dp ? "solve" : "run", null);
            r.phase = "ENDED";
            r.message = dp ? "设计点求解完成;可查看结果或commit" : "起动停车任务完成";
            r.finishedAt = System.currentTimeMillis();
        } catch (java.util.concurrent.CancellationException e) {
            // 安全停止(效果07-20):阶段完成后协同中断;已保存产物保留,不伪装成内部续跑
            r.phase = "STOPPED";
            r.message = "已按请求在安全点停止;已完成阶段与产物保留";
            r.error = null;
            r.finishedAt = System.currentTimeMillis();
            log.info("试车台任务已安全停止: {}", r.taskId);
        } catch (Exception e) {
            log.error("试车台任务失败: {}", r.taskId, e);
            r.phase = "FAILED";
            r.error = e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
            r.message = "任务失败";
            r.finishedAt = System.currentTimeMillis();
        } finally {
            writeTaskIndex(r);
        }
    }

    private void designPointCommit(TaskRun r) {
        try {
            File progCopy = ensureProgramSource(r.projectId);
            writeDesignPointAdapter(new File(r.adapterDir), progCopy);
            runTaskViaRunner(r, "dmg_designpoint_task", "commit", null);
            r.phase = "COMMITTED";
            r.message = "设计已提交(写入原选定MDL并复现)";
            r.finishedAt = System.currentTimeMillis();
        } catch (Exception e) {
            log.error("设计点commit失败: {}", r.taskId, e);
            r.phase = "ENDED"; // 保留solve结果
            r.error = e.getMessage();
            r.message = "commit失败:" + e.getMessage();
        } finally {
            writeTaskIndex(r);
        }
    }

    /** 经 MatlabFunctionRunner 执行任务:stdout 逐行落盘(adapterDir/task-run.log)+回调进内存环形缓冲。 */
    @SuppressWarnings("unchecked")
    private Map<String, Object> runTaskViaRunner(TaskRun r, String fn, String action, Map<String, Object> extra) throws Exception {
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
        com.tsinghua.matlab.MatlabFunctionRunner runner = new com.tsinghua.matlab.MatlabFunctionRunner(
                new File(r.adapterDir), fn, new Object[]{cf.getAbsolutePath()},
                new File(r.adapterDir, "task-run.log"), requirePool(),
                new com.tsinghua.matlab.MatlabFunctionRunner.ProgressCancellationSink() {
                    @Override public void onProgress(String message) { r.appendLog(message); }
                    @Override public boolean isCancellationRequested() { return r.stopRequested; }
                });
        runner.run();
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
        idx.put("hasExcel", findExcelRecursive(new File(r.taskDirectory == null ? "" : r.taskDirectory)) != null);
        try {
            File metaDir = store.testbenchSessionDir(r.projectId);
            if (!metaDir.exists() && !metaDir.mkdirs()) throw new IOException("无法创建元数据目录");
            new com.fasterxml.jackson.databind.ObjectMapper().writerWithDefaultPrettyPrinter()
                    .writeValue(store.testbenchSessionFile(r.projectId, r.taskId), idx);
        } catch (Exception e) {
            log.warn("试车台任务元数据写入失败", e);
        }
        // 试车台记录清单(IginX)同步,失败仅告警
        testbenchRecordService.upsertFromIndex(r.projectId, idx);
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
        m.append("    case 'save'\n");
        m.append("        r = sht_fullmode_session('save', c.cmd.folder);\n");
        m.append("    case 'restore'\n");
        m.append("        r = sht_fullmode_session('restore', c.cmd.snapshotFile);\n");
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
m.append("    case 'savepackage'\n");
        m.append("            r = sht_startstop_modeling_task('savepackage', fullfile(c.taskDirectory, 'task'), c.destination);\n");
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
        // 原位遍历(与Tc24Service.matlabJsonableFn同模式):空结构体时numel(s)=0循环自然跳过,
        // 避免取值重建模式下 v.(f{i}) 对空结构体数组展开为零元素逗号列表→零参递归调用报"输入参数的数目不足"
        m.append("    s = v; f = fieldnames(s);\n");
        m.append("    for i = 1:numel(s)\n");
        m.append("        for j = 1:numel(f)\n");
        m.append("            s(i).(f{j}) = dmg_jsonable(s(i).(f{j}));\n");
        m.append("        end\n");
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
        if (new File(user, "Start_FullModeSimulation_01.m").isFile()) {
            ensureCRuntime(user.getParentFile());
            applyProgramPatches(user.getParentFile());
            return user;
        }

        File c1 = new File("target/classes/" + R06_IN_CLASSPATH + "/" + PROG_SUBDIR);
        File c2 = new File("datamodelgov-server/target/classes/" + R06_IN_CLASSPATH + "/" + PROG_SUBDIR);
        File hit = new File(c1, "Start_FullModeSimulation_01.m").isFile() ? c1
                : (new File(c2, "Start_FullModeSimulation_01.m").isFile() ? c2 : null);
        if (hit != null) {
            // 优先复制到项目工作目录(项目自包含;存量项目首次任务即补齐program/目录),失败才回退classes路径
            try {
                copyTree(hit, user);
                ensureCRuntime(user.getParentFile());
                applyProgramPatches(user.getParentFile());
                return user;
            } catch (IOException e) {
                log.warn("试车台程序复制到项目目录失败,改用classes路径运行: {}", e.getMessage());
                ensureCRuntime(hit.getParentFile());
                applyProgramPatches(hit.getParentFile());
                return hit;
            }
        }

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
        ensureCRuntime(user.getParentFile());
        applyProgramPatches(user.getParentFile());
        return user;
    }

    /** C工程运行时三特征(起动停车/全模式 resolve_c_root 按文件特征唯一定位C工程)。 */
    private static boolean hasCProjectFiles(File dir) {
        return dir != null && dir.isDirectory()
                && new File(dir, "Turboshaft-TS.mdl").isFile()
                && new File(dir, "Turboshaft-TS-Split.mdl").isFile()
                && new File(dir, "x64/Release/GTESS.dll").isFile();
    }

    /** 确保项目程序树(program/)含C工程(C_runtime):缺失时从交付树classes或jar补齐,否则resolve_c_root报candidate count=0。 */
    private void ensureCRuntime(File programsRoot) throws IOException {
        if (programsRoot == null || !programsRoot.isDirectory()) return;
        File[] subs = programsRoot.listFiles(File::isDirectory);
        if (subs != null) {
            for (File d : subs) {
                if (hasCProjectFiles(d)) return; // 项目程序树已有C工程
            }
        }
        File dest = new File(programsRoot, "C_runtime");
        File c1 = new File("target/classes/" + R06_IN_CLASSPATH + "/C_runtime");
        File c2 = new File("datamodelgov-server/target/classes/" + R06_IN_CLASSPATH + "/C_runtime");
        File src = hasCProjectFiles(c1) ? c1 : hasCProjectFiles(c2) ? c2 : null;
        if (src != null) {
            copyTree(src, dest);
            log.info("项目程序树缺C工程,已从交付树补齐C_runtime: {} -> {}", src, dest);
            return;
        }
        Path jar = classpathProgramJar();
        if (jar == null) {
            throw new IOException("项目程序树缺C工程(C_runtime)且未找到交付jar;请在项目program/下放置C_runtime目录(含Turboshaft-TS.mdl/Turboshaft-TS-Split.mdl/x64/Release/GTESS.dll)");
        }
        log.info("从jar解压 C_runtime 到项目程序树: {} -> {}", jar, dest);
        Files.createDirectories(dest.toPath());
        String[] prefixes = {
                "BOOT-INF/classes/" + R06_IN_CLASSPATH + "/C_runtime/",
                R06_IN_CLASSPATH + "/C_runtime/"
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
                File out = new File(dest, rel);
                Files.createDirectories(out.getParentFile().toPath());
                Files.copy(zf.getInputStream(e), out.toPath(), StandardCopyOption.REPLACE_EXISTING);
                n++;
            }
        }
        if (!hasCProjectFiles(dest)) {
            throw new IOException("jar 内未找到完整C工程(C_runtime,解压 " + n + " 个文件)");
        }
    }

    /**
     * 交付程序运行期补丁:交付树资源原样不动(约定:不在 src/resources/programs 内修改交付 MATLAB 程序),
     * 已知损坏/兼容问题在项目工作副本(<workdir>/programs/)上由后端修复——MATLAB 执行的正是工作副本。
     * key=programs/ 下相对路径,value=classpath 补丁资源(matlab-patches/)。目标字节与补丁一致则跳过,幂等。
     */
    private static final Map<String, String> PROGRAM_PATCHES = new java.util.LinkedHashMap<>();

    static {
        // 交付树 sht_fullmode_session.m 入库即存在GBK乱码损坏(解析报"字符向量未正常终止/非法使用保留关键字"),
        // 修复版不进交付树,由后端在项目工作副本上覆盖
        PROGRAM_PATCHES.put("m_program_adaptive_tune/sht_fullmode_session.m",
                "matlab-patches/m_program_adaptive_tune/sht_fullmode_session.m");
    }

    private void applyProgramPatches(File programsRoot) {
        if (programsRoot == null || !programsRoot.isDirectory()) return;
        for (Map.Entry<String, String> e : PROGRAM_PATCHES.entrySet()) {
            File target = new File(programsRoot, e.getKey());
            byte[] patch = readClasspathResource(e.getValue());
            if (patch == null) {
                log.warn("交付程序补丁资源缺失: {}", e.getValue());
                continue;
            }
            boolean same = false;
            try {
                if (target.isFile() && target.length() == patch.length) {
                    same = java.util.Arrays.equals(patch, Files.readAllBytes(target.toPath()));
                }
            } catch (IOException ignore) {
                // 读失败按不一致处理,走覆盖
            }
            if (same) continue;
            try {
                Files.createDirectories(target.getParentFile().toPath());
                Files.write(target.toPath(), patch);
                log.info("已应用交付程序补丁(交付树不动,后端修复工作副本): {} -> {}", e.getValue(), target);
            } catch (IOException ex) {
                log.warn("交付程序补丁写入失败({}): {}", target, ex.getMessage());
            }
        }
    }

    private byte[] readClasspathResource(String path) {
        ClassLoader cl = Thread.currentThread().getContextClassLoader();
        if (cl == null) cl = TestbenchService.class.getClassLoader();
        try (java.io.InputStream in = cl.getResourceAsStream(path)) {
            if (in == null) return null;
            java.io.ByteArrayOutputStream bos = new java.io.ByteArrayOutputStream();
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) bos.write(buf, 0, n);
            return bos.toByteArray();
        } catch (IOException e) {
            return null;
        }
    }

    private static void copyTree(File src, File dest) throws IOException {
        Files.createDirectories(dest.toPath());
        File[] children = src.listFiles();
        if (children == null) return;
        for (File c : children) {
            File t = new File(dest, c.getName());
            if (c.isDirectory()) copyTree(c, t);
            else Files.copy(c.toPath(), t.toPath(), StandardCopyOption.REPLACE_EXISTING);
        }
    }

    private File workProgramsDir(String projectId) throws IOException {
        try {
            EngineModels.EngineProject proj = store.getProject(projectId);
            if (proj != null && proj.getWorkdir() != null && !proj.getWorkdir().isEmpty()) {
                return new File(new File(proj.getWorkdir()), "programs/m_program_adaptive_tune");
            }
        } catch (IOException e) {
            log.warn("读取项目工作目录失败: {}", projectId);
        }
        return new File(store.projectDir(projectId), "programs/m_program_adaptive_tune");
    }

    /**
     * 创建项目时预置程序源(整树镜像):交付树 programs/ 全部内容复制到 <workdir>/programs/
     * (m_program_adaptive_tune + C_runtime + AFO_V_2,共约34MB;所有项目布局一致,
     * TC24/AFO/试车台/设计点/起动停车入口齐全)。已完整则跳过不覆盖;
     * 旧布局 <workdir>/program 自动改名迁移;缺C_runtime等局部缺失由 ensureCRuntime 兜底;
     * 预置失败由运行时 ensureProgramSource 兜底。
     */
    public void provisionProgramForProject(String projectId) throws IOException {
        File programRoot = workProgramsDir(projectId).getParentFile(); // <workdir>/programs
        // 旧布局迁移:存量项目 program/ → programs/(改名保留数据,同盘原子)
        File workdir = programRoot.getParentFile();
        File legacy = new File(workdir, "program");
        if (legacy.isDirectory() && !programRoot.exists()) {
            try {
                Files.move(legacy.toPath(), programRoot.toPath());
                log.info("项目程序目录已迁移为统一命名: {} -> {}", legacy, programRoot);
            } catch (IOException e) {
                log.warn("程序目录改名迁移失败(按新布局重新预置): {} -> {}: {}", legacy, programRoot, e.getMessage());
            }
        }
        boolean complete = new File(programRoot, "m_program_adaptive_tune/Start_FullModeSimulation_01.m").isFile();
        if (complete) {
            ensureCRuntime(programRoot); // 程序在但C工程可能缺(旧项目),补齐后即完整
            applyProgramPatches(programRoot); // 已知交付程序损坏在副本上修复(交付树不动)
            return;
        }
        // 来源顺序:工作区resources整树 → target/classes整树 → jar前缀解压(均为R06 programs层)
        File src = new File("datamodelgov-server/src/main/resources/" + R06_IN_CLASSPATH);
        if (!src.isDirectory()) src = new File("src/main/resources/" + R06_IN_CLASSPATH);
        if (!src.isDirectory()) src = new File("target/classes/" + R06_IN_CLASSPATH);
        if (!src.isDirectory()) src = new File("datamodelgov-server/target/classes/" + R06_IN_CLASSPATH);
        if (src.isDirectory()) {
            log.info("预置程序树(整树镜像)到项目工作目录: {} -> {}", src, programRoot);
            copyTree(src, programRoot);
        } else {
            Path jar = classpathProgramJar();
            if (jar == null) throw new IOException("未找到交付程序树(resources/classpath/jar均无)");
            log.info("从jar解压预置程序树(整树): {} -> {}", jar, programRoot);
            Files.createDirectories(programRoot.toPath());
            String[] prefixes = {
                    "BOOT-INF/classes/" + R06_IN_CLASSPATH + "/",
                    R06_IN_CLASSPATH + "/"
            };
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
                    File out = new File(programRoot, rel);
                    Files.createDirectories(out.getParentFile().toPath());
                    Files.copy(zf.getInputStream(e), out.toPath(), StandardCopyOption.REPLACE_EXISTING);
                }
            }
        }
        // 兜底校验:C_runtime 缺失(如旧版jar)时按三特征补齐
        ensureCRuntime(programRoot);
        applyProgramPatches(programRoot);
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
                if ("fullmode".equals(kind)) {
                    m.put("hasSnapshot", findFileRecursive(od, "snapshot.mat") != null);
                    m.put("hasResult", new File(od, "adapter/fm-result-result.json").isFile()
                            || new File(od, "result.json").isFile());
                }
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

    /**
     * 释放项目占用的MATLAB引擎(删除项目前调用):关闭该项目全模式会话引擎与一次性任务引擎,
     * 避免引擎进程工作目录锁住项目目录导致删除失败(Windows下进程占用无法删目录)。
     */
    public void releaseProjectEngines(String projectId) {
        FullmodeSession s = fmSession;
        if (s != null && projectId != null && projectId.equals(s.projectId)) {
            closeEngine(s.engine);
            s.engine = null;
            s.phase = "CLOSED";
            s.message = "项目已删除,会话关闭";
            log.info("删除项目前释放全模式会话引擎: runId={}", s.runId);
        }
        for (TaskRun r : taskRuns.values()) {
            if (projectId != null && projectId.equals(r.projectId) && r.engine != null) {
                closeEngine(r.engine);
                r.engine = null;
                if (!isTerminal(r.phase)) {
                    r.phase = "FAILED";
                    r.error = "项目已删除,任务终止";
                }
                log.info("删除项目前释放任务引擎: task={}", r.taskId);
            }
        }
    }
}
