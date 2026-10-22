package com.tsinghua.engine;

import com.mathworks.engine.MatlabEngine;
import com.tsinghua.matlab.MatlabNativeLibrary;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
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
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.stream.Stream;

/**
 * 多系统联合仿真(F-12,AFO_V_2)会话接入层。
 *
 * 交付合同 sht_afo_session:同进程单会话(persistent),prepare→run(阻塞sim)→result/save/close。
 * 运行中的命令通道是 outputDir/inbox/*.json(Recorder每个主步服务,回执落processed_commands),
 * 状态通道是 outputDir/status.json(每个记录步原子重写)——这两条不走引擎,
 * 因此Java侧运行中只读写文件;prepare/run/save/result/close 才需要引擎feval。
 *
 * AFO会话独占引擎(模型加载+GTESS库是进程级断言),因此每会话 startMatlab 专用引擎,
 * 会话close后关闭,不占用TC24的共享引擎池。
 *
 * 目录体系与个性化建模一致:会话大文件(status/inbox/runtime/result/Excel)落
 * 项目工作目录 <workdir>/job/afo-sessions/<runId>,元数据落 projects/{pid}/afo/{runId}.json。
 */
@Slf4j
@Service
public class AfoService {

    private final EngineProjectStore store;

    private final Object sessionLock = new Object();
    private volatile AfoSession session;
    private final ExecutorService executor = Executors.newSingleThreadExecutor();

    public AfoService(EngineProjectStore store) {
        this.store = store;
    }

    private static final String R06_IN_CLASSPATH = "programs/Delivery_V1_20261019_R06/programs";
    private static final String AFO_SUBDIR = "programs/AFO_V_2";

    static class AfoSession {
        String projectId;
        String runId;
        String engineId;
        String outputDir;
        String adapterDir;
        /** PREPARING / READY / RUNNING / PAUSED / ENDED / FAILED */
        volatile String phase = "PREPARING";
        volatile String message = "";
        volatile String error;
        Long createdAt;
        Long finishedAt;
        Map<String, Object> config;
        String programDir;
        MatlabEngine engine;
        boolean engineOwned;
    }

    @PostConstruct
    void init() {
        log.info("AFO_V_2 多系统联合仿真接入层就绪");
    }

    /* ---------- 程序源解析 ---------- */

    /**
     * 解析AFO_V_2程序源目录:
     * 1. 用户项目工作目录 <workdir>/programs/AFO_V_2(用户自备程序,优先);
     * 2. target/classes(IDE开发兜底);
     * 3. 均无且程序在jar内 → 解压到根目录 programs/AFO_V_2(MATLAB无法addpath jar内路径)。
     */
    private synchronized File ensureAfoSource(String projectId) throws IOException {
        File user = new File(workProgramsDir(projectId), "AFO_V_2");
        if (new File(user, "sht_afo_config.m").isFile()) return user;

        File classes = new File("target/classes/" + R06_IN_CLASSPATH + "/AFO_V_2");
        File classes2 = new File("datamodelgov-server/target/classes/" + R06_IN_CLASSPATH + "/AFO_V_2");
        if (new File(classes, "sht_afo_config.m").isFile()) return classes;
        if (new File(classes2, "sht_afo_config.m").isFile()) return classes2;

        // jar兜底:解压到项目工作目录programs下(与创建项目时的provision一致)
        Path jar = classpathProgramJar();
        if (jar == null) {
            throw new IOException("未找到AFO_V_2程序:请在项目工作目录 "
                    + workProgramsDir(projectId).getAbsolutePath() + " 下放置 AFO_V_2 程序目录,"
                    + "或确认部署包内含交付程序");
        }
        log.info("从jar解压 AFO_V_2 程序到项目工作目录: {} -> {}", jar, user);
        File extracted = user;
        Files.createDirectories(extracted.toPath());
        try (java.util.zip.ZipFile zf = new java.util.zip.ZipFile(jar.toFile())) {
            String prefix = R06_IN_CLASSPATH + "/AFO_V_2/";
            java.util.Enumeration<? extends java.util.zip.ZipEntry> en = zf.entries();
            while (en.hasMoreElements()) {
                java.util.zip.ZipEntry e = en.nextElement();
                if (e.isDirectory() || !e.getName().startsWith(prefix)) continue;
                File out = new File(extracted, e.getName().substring(prefix.length()));
                Files.createDirectories(out.getParentFile().toPath());
                Files.copy(zf.getInputStream(e), out.toPath(), StandardCopyOption.REPLACE_EXISTING);
            }
        }
        return extracted;
    }

    /** 项目工作目录下的程序源位置:<workdir>/program;workdir缺失时回退元数据目录。 */
    private File workProgramsDir(String projectId) throws IOException {
        try {
            EngineModels.EngineProject proj = store.getProject(projectId);
            if (proj != null && proj.getWorkdir() != null && !proj.getWorkdir().isEmpty()) {
                return new File(new File(proj.getWorkdir()), "program");
            }
        } catch (IOException e) {
            log.warn("读取项目工作目录失败,程序源回退元数据目录: {}", projectId);
        }
        return new File(store.projectDir(projectId), "program");
    }

    /** 定位fat jar自身(含R06交付树的启动jar)。 */
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

    private void logLine(String line) {
        MatlabLogRing.append("[AFO" + (session != null && session.runId != null ? " " + session.runId : "") + "] " + line);
    }


    /**
     * 创建项目时预置程序源:把交付树中的 AFO_V_2 复制到 <workdir>/programs/AFO_V_2
     * (已存在则跳过,不覆盖用户自备程序)。来源:工作区resources → target/classes → jar。
     */
    public void provisionProgramForProject(String projectId) throws IOException {
        File target = new File(workProgramsDir(projectId), "AFO_V_2");
        if (new File(target, "sht_afo_config.m").isFile()) return; // 已有(用户自备或已拷),不覆盖
        File src = new File("datamodelgov-server/src/main/resources/" + R06_IN_CLASSPATH + "/AFO_V_2");
        if (!src.isDirectory()) src = new File("src/main/resources/" + R06_IN_CLASSPATH + "/AFO_V_2");
        if (!src.isDirectory()) src = new File("target/classes/" + R06_IN_CLASSPATH + "/AFO_V_2");
        if (!src.isDirectory()) src = new File("datamodelgov-server/target/classes/" + R06_IN_CLASSPATH + "/AFO_V_2");
        if (src.isDirectory()) {
            log.info("预置AFO_V_2程序到项目工作目录: {} -> {}", src, target);
            copyRecursively(src.toPath(), target.toPath());
            return;
        }
        Path jar = classpathProgramJar();
        if (jar == null) throw new IOException("未找到AFO_V_2程序源(resources/classpath/jar均无)");
        log.info("从jar解压预置AFO_V_2程序: {} -> {}", jar, target);
        Files.createDirectories(target.toPath());
        try (java.util.zip.ZipFile zf = new java.util.zip.ZipFile(jar.toFile())) {
            String prefix = R06_IN_CLASSPATH + "/AFO_V_2/";
            java.util.Enumeration<? extends java.util.zip.ZipEntry> en = zf.entries();
            while (en.hasMoreElements()) {
                java.util.zip.ZipEntry e = en.nextElement();
                if (e.isDirectory() || !e.getName().startsWith(prefix)) continue;
                File out = new File(target, e.getName().substring(prefix.length()));
                Files.createDirectories(out.getParentFile().toPath());
                Files.copy(zf.getInputStream(e), out.toPath(), StandardCopyOption.REPLACE_EXISTING);
            }
        }
    }

    /* ---------- 会话管理 ---------- */

    public Map<String, Object> currentStatus(String projectId) throws IOException {
        AfoSession s = session;
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
        // 运行中状态以程序原子写的 status.json 为准(含 time/Np/Ng/Wf/events/values)
        File sf = new File(s.outputDir, "status.json");
        if (sf.exists()) {
            try {
                Object parsed = new com.fasterxml.jackson.databind.ObjectMapper()
                        .readValue(sf, Object.class);
                out.put("live", parsed);
            } catch (Exception e) {
                log.debug("status.json 读取中(可能正在原子替换)", e);
            }
        }
        return out;
    }

    /** 发起准备:异步,同一时刻仅允许一个会话(合同persistent单例)。 */
    public Map<String, Object> prepare(String projectId, Map<String, Object> cfg) throws IOException {
        synchronized (sessionLock) {
            AfoSession cur = session;
            if (cur != null && !isTerminal(cur.phase)) {
                throw new IllegalStateException("已有AFO会话在" + cur.phase + "(runId=" + cur.runId + "),请先结束并关闭");
            }
            String runId = "M-R" + new java.text.SimpleDateFormat("yyyyMMdd_HHmmss").format(new java.util.Date());
            // 合同目录 outputDir(M-R...)必须由 sht_afo_prepare 自行创建
            // (其断言"结果目录已存在,不覆盖");Java 侧 adapter/config 放旁边的
            // 临时工作区 _work_<runId>,不触碰合同目录
            File outputDir = store.afoWorkDir(projectId, runId);
            File workTmp = new File(store.afoWorkDir(projectId, "_work_" + runId), "adapter");
            if (!workTmp.exists() && !workTmp.mkdirs()) throw new IOException("无法创建AFO适配器临时目录: " + workTmp);

            AfoSession s = new AfoSession();
            s.projectId = projectId;
            s.runId = runId;
            s.engineId = String.valueOf(cfg.getOrDefault("engineId", "ENGINE-001"));
            s.outputDir = outputDir.getAbsolutePath();
            s.adapterDir = workTmp.getAbsolutePath();
            s.createdAt = System.currentTimeMillis();
            s.config = cfg;
            s.message = "准备AFO程序工作副本";
            session = s;

            writeSessionIndex(s);
            executor.submit(() -> runPrepare(s));
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("runId", runId);
            out.put("phase", s.phase);
            return out;
        }
    }

    private boolean isTerminal(String phase) {
        return "ENDED".equals(phase) || "FAILED".equals(phase) || "CLOSED".equals(phase);
    }

    private void runPrepare(AfoSession s) {
        try {
            File progCopy = ensureAfoSource(s.projectId);
            writeAdapter(s, progCopy);
            MatlabEngine eng = MatlabEngine.startMatlab();
            s.engine = eng;
            s.engineOwned = true;
            try {
                eng.feval(0, "eval", "feature('DefaultCharacterSet', 'GBK')");
            } catch (Exception ce) {
                log.warn("AFO引擎字符集设置失败(沿用默认)", ce);
            }
            s.programDir = progCopy.getAbsolutePath();
            s.message = "MATLAB已启动;准备运行副本(复制资产/校验身份/初始化模型)"; logLine("MATLAB引擎已启动,开始准备运行副本");
            // 引擎内调 session('prepare', cfg);适配器读JSON构造cfg
            feval(s, "prepare", progCopy.getAbsolutePath());
            logLine("准备完成,等待开始运行"); s.phase = "READY";
            s.message = "准备完成;可开始运行";
            writeSessionIndex(s);
        } catch (Exception e) {
            log.error("AFO准备失败: {}", s.runId, e);
            s.phase = "FAILED";
            s.error = e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
            s.message = "准备失败";
            closeEngine(s);
            writeSessionIndex(s);
        }
    }

    /** 开始运行(阻塞sim,放线程;运行中状态与命令走文件通道)。 */
    public Map<String, Object> run(String projectId) throws IOException {
        AfoSession s = requireSession(projectId, "READY");
        logLine("仿真开始运行"); s.phase = "RUNNING";
        s.message = "仿真运行中";
        writeSessionIndex(s);
        executor.submit(() -> runRun(s));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("runId", s.runId);
        out.put("phase", s.phase);
        return out;
    }

    private void runRun(AfoSession s) {
        try {
            feval(s, "run", s.programDir);
            // 运行结束:取结果JSON供前端历史曲线,再让程序保存Excel/result.mat
            logLine("仿真计算结束,保存Excel与result.mat"); s.message = "保存结果(Excel与result.mat)";
            feval(s, "save", s.programDir);
            feval(s, "result", s.programDir);
            feval(s, "close", s.programDir);
            logLine("结果已保存,会话结束"); s.phase = "ENDED";
            s.message = "运行结束;结果已保存";
            s.finishedAt = System.currentTimeMillis();
        } catch (Exception e) {
            log.error("AFO运行失败: {}", s.runId, e);
            s.phase = "FAILED";
            s.error = e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
            s.message = "运行失败";
            s.finishedAt = System.currentTimeMillis();
        } finally {
            closeEngine(s);
            writeSessionIndex(s);
        }
    }

    /** 命令走inbox文件通道(pause/resume/stop/np/load),不占用引擎。 */
    public Map<String, Object> command(String projectId, String kind, Object value) throws IOException {
        AfoSession s = requireSession(projectId, null);
        String id = "cmd_" + UUID.randomUUID().toString().substring(0, 8);
        Map<String, Object> cmd = new LinkedHashMap<>();
        cmd.put("id", id);
        cmd.put("kind", kind);
        cmd.put("value", value);
        File inbox = new File(s.outputDir, "inbox");
        if (!inbox.exists() && !inbox.mkdirs()) throw new IOException("无法创建inbox目录");
        File target = new File(inbox, id + ".json");
        File tmp = new File(inbox, id + ".json.tmp");
        com.fasterxml.jackson.databind.ObjectMapper om = new com.fasterxml.jackson.databind.ObjectMapper();
        om.configure(com.fasterxml.jackson.core.JsonGenerator.Feature.ESCAPE_NON_ASCII, true);
        Files.write(tmp.toPath(), om.writeValueAsBytes(cmd));
        Files.move(tmp.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("id", id);
        out.put("accepted", true);
        out.put("note", "已写入命令通道;回执见processed_commands(Recorder主步服务)");
        return out;
    }

    /** 保存重试(ended/failed后;不重新计算)。 */
    public Map<String, Object> save(String projectId) throws IOException {
        AfoSession s = requireSession(projectId, "ENDED");
        if (s.engine == null) throw new IllegalStateException("会话引擎已关闭;结果已在运行结束时保存");
        executor.submit(() -> {
            try {
                feval(s, "save", s.programDir);
                s.message = "结果已保存";
                writeSessionIndex(s);
            } catch (Exception e) {
                log.error("AFO保存失败", e);
                s.message = "保存失败:" + e.getMessage();
            }
        });
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("accepted", true);
        return out;
    }

    /** 关闭会话(persistent单例清位;ENDED/FAILED后)。 */
    public Map<String, Object> close(String projectId) throws IOException {
        AfoSession s = requireSession(projectId, null);
        if (!isTerminal(s.phase) && !"READY".equals(s.phase)) {
            throw new IllegalStateException("运行中不能关闭;先结束计算");
        }
        if (s.engine != null) {
            try {
                feval(s, "close", s.programDir);
            } catch (Exception e) {
                log.warn("AFO session close失败(仍关闭引擎)", e);
            }
        }
        s.phase = "CLOSED";
        s.message = "会话已关闭";
        closeEngine(s);
        writeSessionIndex(s);
        synchronized (sessionLock) {
            if (session == s) session = null;
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("closed", true);
        return out;
    }

    /** 历史会话列表(扫描元数据 projects/{pid}/afo/*.json,与predictions/uq同模式)。 */
    public List<Map<String, Object>> listSessions(String projectId) throws IOException {
        List<Map<String, Object>> list = new ArrayList<>();
        File dir = store.afoSessionDir(projectId);
        File[] files = dir.listFiles((d, n) -> n.toLowerCase().endsWith(".json"));
        if (files == null) return list;
        com.fasterxml.jackson.databind.ObjectMapper om = new com.fasterxml.jackson.databind.ObjectMapper();
        for (File f : files) {
            try {
                Map<String, Object> m = om.readValue(f, Map.class);
                String runId = String.valueOf(m.get("runId"));
                File outDir = new File(String.valueOf(m.get("outputDir")));
                m.put("hasResult", new File(outDir, "result.json").exists());
                m.put("hasExcel", findExcel(outDir) != null);
                list.add(m);
            } catch (Exception e) {
                log.warn("AFO会话元数据读取失败: {}", f, e);
            }
        }
        list.sort((a, b) -> Long.compare(
                b.get("createdAt") instanceof Number ? ((Number) b.get("createdAt")).longValue() : 0,
                a.get("createdAt") instanceof Number ? ((Number) a.get("createdAt")).longValue() : 0));
        return list;
    }

    /** 单条历史结果(result.json:config/identity/channels/time/values/events/timing)。 */
    public Map<String, Object> readResult(String projectId, String runId) throws IOException {
        File f = new File(afoOutputDir(projectId, runId), "result.json");
        if (!f.exists()) return null;
        return new com.fasterxml.jackson.databind.ObjectMapper().readValue(f, Map.class);
    }

    public File resultExcel(String projectId, String runId) throws IOException {
        return findExcel(afoOutputDir(projectId, runId));
    }

    /** 会话输出目录:优先元数据记录的outputDir,回退项目工作目录推算。 */
    private File afoOutputDir(String projectId, String runId) throws IOException {
        File meta = store.afoSessionFile(projectId, runId);
        if (meta.exists()) {
            try {
                Map<?, ?> m = new com.fasterxml.jackson.databind.ObjectMapper().readValue(meta, Map.class);
                Object od = m.get("outputDir");
                if (od != null && new File(String.valueOf(od)).isDirectory()) return new File(String.valueOf(od));
            } catch (Exception ignore) { /* 回退推算 */ }
        }
        return store.afoWorkDir(projectId, runId);
    }

    private File findExcel(File dir) {
        File[] xs = dir.listFiles((d, n) -> n.toLowerCase().endsWith(".xlsx"));
        if (xs == null || xs.length == 0) return null;
        for (File x : xs) {
            if (x.getName().startsWith("AFO_")) return x;
        }
        return xs[0];
    }

    /* ---------- 适配器与引擎 ---------- */

    /** 生成 dmg_afo_task.m:JSON配置→cfg构造→session动作→JSON回写。 */
    private void writeAdapter(AfoSession s, File progCopy) throws IOException {
        File ad = new File(s.adapterDir);
        if (!ad.exists() && !ad.mkdirs()) throw new IOException("无法创建适配器目录");
        StringBuilder m = new StringBuilder();
        m.append("function r = dmg_afo_task(configFile)\n");
        m.append("% AFO_V_2 multisystem session adapter (generated by DataModelGov)\n");
        m.append("% ASCII-only: engine charset is GBK; keep this file free of non-ASCII text.\n");
        m.append("% programDir comes from the config JSON (ASCII-escaped), so Chinese paths survive.\n");
        m.append("c = jsondecode(fileread(configFile));\n");
        m.append("addpath(c.programDir, '-begin');\n");
        m.append("rehash;\n");
        m.append("cfg = sht_afo_config(c.outputDir);\n");
        m.append("f = fieldnames(c.cfg);\n");
        m.append("for k = 1:numel(f), cfg.(f{k}) = c.cfg.(f{k}); end\n");
        m.append("switch lower(c.action)\n");
        m.append("    case 'prepare', r = sht_afo_session('prepare', cfg);\n");
        m.append("    otherwise, r = sht_afo_session(lower(c.action));\n");
        m.append("end\n");
        m.append("payload = jsonencode(r);\n");
        m.append("fid = fopen(c.resultFile, 'w', 'n', 'UTF-8');\n");
        m.append("fwrite(fid, payload, 'char');\n");
        m.append("fclose(fid);\n");
        m.append("r = 'ok';\n");
        m.append("end\n");
        Files.write(new File(ad, "dmg_afo_task.m").toPath(), m.toString().getBytes(StandardCharsets.UTF_8));
    }

    /** feval一个session动作:写action配置→feval→读取JSON结果落 outputDir/afo-result.json。 */
    private void feval(AfoSession s, String action, String progDir) throws Exception {
        Map<String, Object> call = new LinkedHashMap<>();
        call.put("action", action);
        call.put("programDir", progDir.replace('\\', '/'));
        call.put("outputDir", s.outputDir.replace('\\', '/'));
        call.put("cfg", s.config == null ? new LinkedHashMap<>() : s.config);
        String resultFile = new File(s.adapterDir, "action-" + action + ".json").getAbsolutePath().replace('\\', '/');
        call.put("resultFile", resultFile);
        File cf = new File(s.adapterDir, "action-" + action + "-config.json");
        com.fasterxml.jackson.databind.ObjectMapper om = new com.fasterxml.jackson.databind.ObjectMapper();
        // 引擎字符集为GBK(程序运行副本按CP936设计),JSON一律ASCII转义,fileread/jsondecode字节级安全
        om.configure(com.fasterxml.jackson.core.JsonGenerator.Feature.ESCAPE_NON_ASCII, true);
        Files.write(cf.toPath(), om.writeValueAsBytes(call));

        MatlabEngine eng = s.engine;
        eng.feval(0, "cd", s.adapterDir);
        eng.feval(0, "dmg_afo_task", cf.getAbsolutePath());
        // JSON大对象仅在 result 动作时回传文件化
        if ("result".equals(action)) {
            File dst = new File(s.outputDir, "result.json");
            Files.copy(new File(resultFile).toPath(), dst.toPath(), StandardCopyOption.REPLACE_EXISTING);
        }
    }

    private void closeEngine(AfoSession s) {
        MatlabEngine eng = s.engine;
        s.engine = null;
        if (eng != null) {
            try {
                eng.close();
            } catch (Exception e) {
                log.warn("AFO引擎关闭失败", e);
            }
        }
    }

    private AfoSession requireSession(String projectId, String expectPhase) throws IOException {
        AfoSession s = session;
        if (s == null || (projectId != null && !projectId.equals(s.projectId))) {
            throw new IllegalStateException("无活动AFO会话;请先发起准备");
        }
        if (expectPhase != null && !expectPhase.equals(s.phase)) {
            throw new IllegalStateException("当前会话状态为" + s.phase + ",需要" + expectPhase);
        }
        return s;
    }

    private void writeSessionIndex(AfoSession s) {
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
        // 元数据与predictions/uq同模式:projects/{pid}/afo/{runId}.json(列表/追溯入口)
        try {
            File metaDir = store.afoSessionDir(s.projectId);
            if (!metaDir.exists() && !metaDir.mkdirs()) throw new IOException("无法创建元数据目录: " + metaDir);
            new com.fasterxml.jackson.databind.ObjectMapper()
                    .writerWithDefaultPrettyPrinter()
                    .writeValue(store.afoSessionFile(s.projectId, s.runId), idx);
        } catch (Exception e) {
            log.warn("AFO会话元数据写入失败", e);
        }

    }

    /* ---------- 工具 ---------- */

    private static void copyRecursively(Path src, Path dest) throws IOException {
        Files.walkFileTree(src, new java.nio.file.SimpleFileVisitor<Path>() {
            @Override
            public java.nio.file.FileVisitResult preVisitDirectory(Path dir, java.nio.file.attribute.BasicFileAttributes attrs) throws IOException {
                Files.createDirectories(dest.resolve(src.relativize(dir)));
                return java.nio.file.FileVisitResult.CONTINUE;
            }
            @Override
            public java.nio.file.FileVisitResult visitFile(Path file, java.nio.file.attribute.BasicFileAttributes attrs) throws IOException {
                Files.copy(file, dest.resolve(src.relativize(file)), StandardCopyOption.REPLACE_EXISTING);
                return java.nio.file.FileVisitResult.CONTINUE;
            }
        });
    }

    private static void deleteRecursively(File f) throws IOException {
        if (!f.exists()) return;
        try (Stream<Path> walk = Files.walk(f.toPath())) {
            walk.sorted(Comparator.reverseOrder()).map(Path::toFile).forEach(File::delete);
        }
    }
}
