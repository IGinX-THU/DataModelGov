package com.tsinghua.engine;

import com.mathworks.engine.MatlabEngine;
import com.tsinghua.matlab.MatlabNativeLibrary;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
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

    @org.springframework.beans.factory.annotation.Autowired
    private EngineAfoSessionService afoSessionService;

    private final Object sessionLock = new Object();
    private volatile AfoSession session;
    private final ExecutorService executor = Executors.newSingleThreadExecutor();

    /** AFO 专属引擎预热(program-run 引擎池同思路;会话独占引擎,常备 1 台)。 */
    @org.springframework.beans.factory.annotation.Value("${engine.afo.warm-engine:true}")
    private boolean warmEngineEnabled;
    private volatile MatlabEngine warmEngine;
    private final ExecutorService warmExecutor = Executors.newSingleThreadExecutor(
            r -> { Thread t = new Thread(r, "afo-warm-engine"); t.setDaemon(true); return t; });

    /** 增量数据 SSE 泵:200ms 扫描 stream 块,向订阅者推送增量(program-run SSE 同构)。 */
    private final List<LiveSub> liveSubs = new java.util.concurrent.CopyOnWriteArrayList<>();
    private final java.util.concurrent.ScheduledExecutorService livePump =
            java.util.concurrent.Executors.newSingleThreadScheduledExecutor(
                    r -> { Thread t = new Thread(r, "afo-live-pump"); t.setDaemon(true); return t; });

    /** 状态通知 SSE 订阅者:{em, fp};覆盖会话全生命周期(含IDLE/PREPARING),变化才推chg。 */
    private final List<Object[]> statusSubs = new java.util.concurrent.CopyOnWriteArrayList<>();
    private static final com.fasterxml.jackson.databind.ObjectMapper OM_STATUS =
            new com.fasterxml.jackson.databind.ObjectMapper();

    /** 一个 SSE 订阅者:独立游标与列裁剪;busy 防重入,done 后移除。 */
    private static class LiveSub {
        final org.springframework.web.servlet.mvc.method.annotation.SseEmitter em;
        final String expectSessionId;
        final int[] columns;
        long cursor;
        volatile boolean busy;
        volatile boolean done;
        LiveSub(org.springframework.web.servlet.mvc.method.annotation.SseEmitter em,
                String expectSessionId, int[] columns, long afterSeq) {
            this.em = em;
            this.expectSessionId = expectSessionId;
            this.columns = columns;
            this.cursor = afterSeq;
        }
    }

    public AfoService(EngineProjectStore store) {
        this.store = store;
    }

    private static final String R06_IN_CLASSPATH = "matlab/delivery/programs";
    private static final String AFO_SUBDIR = "programs/AFO_V_2";

    /** 交付树根可配置解析(engine.r06.root):磁盘路径优先,classpath/内置资源/jar 兜底。 */
    @Autowired(required = false)
    private DeliveryTreeLocator deliveryTree;

    /** 交付树 programs 层 classpath 基准(配置 classpath 模式时跟随配置)。 */
    private String r06ProgramsBase() {
        return deliveryTree != null ? deliveryTree.classpathProgramsBase() : R06_IN_CLASSPATH;
    }

    /** 配置的磁盘交付树 programs 层;未配置或无效返回 null。 */
    private File deliveryProgramsDir() {
        return deliveryTree != null ? deliveryTree.programsDir() : null;
    }

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
        // 引擎预热(program-run 引擎池同款思路):AFO 会话独占引擎,启动期预启 1 台专属引擎,
        // prepare 直接取用(省 ~100s 冷启动);会话关闭后自动回填
        if (warmEngineEnabled) {
            warmExecutor.submit(() -> startWarmEngine("预热"));
        }
        // 增量数据 SSE 泵(有订阅者才扫文件)
        livePump.scheduleWithFixedDelay(this::pumpLiveSafely, 200, 200, java.util.concurrent.TimeUnit.MILLISECONDS);
        // 状态通知 SSE 泵(1s指纹比对;准备期阶段迁移由此推送,前端不再依赖5s状态轮询)
        livePump.scheduleWithFixedDelay(this::pumpStatusSafely, 1000, 1000, java.util.concurrent.TimeUnit.MILLISECONDS);
    }

    private void startWarmEngine() {
        this.startWarmEngine("预热");
    }

    /** label 用于区分启动期"预热"与会话结束后的"回填"(日志可读性)。 */
    private void startWarmEngine(String label) {
        // 已有预热引擎则跳过:准备期回填与会话结束回填可能先后排队,重复启动会泄漏多余MATLAB进程
        if (warmEngine != null) return;
        try {
            // 原生库路径注入可能晚于本 Bean 初始化(TC24 池/试车台各自注入);此处幂等补齐
            com.tsinghua.matlab.MatlabNativeLibrary.prepare(null);
            long t0 = System.currentTimeMillis();
            MatlabEngine e = MatlabEngine.startMatlab();
            warmEngine = e;
            log.info("AFO专属MATLAB引擎{}完成(耗时 {} ms),prepare 将直接取用", label, System.currentTimeMillis() - t0);
        } catch (Throwable e) {
            warmEngine = null;
            log.warn("AFO专属MATLAB引擎{}失败(prepare 时将同步重试): {}", label, e.getMessage());
        }
    }

    /** 取预热引擎;未就绪时同步冷启兜底(prepare 不因此失败两次)。 */
    private synchronized MatlabEngine takeWarmEngine() throws Exception {
        MatlabEngine e = warmEngine;
        warmEngine = null;
        if (e != null) {
            log.info("AFO prepare 取用预热引擎");
            return e;
        }
        log.warn("AFO 预热引擎不可用,同步冷启动MATLAB(较慢)");
        com.tsinghua.matlab.MatlabNativeLibrary.prepare(null);
        return MatlabEngine.startMatlab();
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

        // 配置的磁盘交付树(engine.r06.root)优先于内置资源
        File ext = deliveryProgramsDir();
        if (ext != null) {
            File extAfo = new File(ext, "AFO_V_2");
            if (new File(extAfo, "sht_afo_config.m").isFile()) return extAfo;
        }

        File classes = new File("target/classes/" + r06ProgramsBase() + "/AFO_V_2");
        File classes2 = new File("datamodelgov-server/target/classes/" + r06ProgramsBase() + "/AFO_V_2");
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
        // fat jar 里资源在 BOOT-INF/classes/ 前缀下,两种前缀都试
        String[] prefixes = {
                "BOOT-INF/classes/" + r06ProgramsBase() + "/AFO_V_2/",
                r06ProgramsBase() + "/AFO_V_2/"
        };
        int extractedCount = 0;
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
                File out = new File(extracted, rel);
                Files.createDirectories(out.getParentFile().toPath());
                Files.copy(zf.getInputStream(e), out.toPath(), StandardCopyOption.REPLACE_EXISTING);
                extractedCount++;
            }
        }
        // 解压后验证:关键入口文件必须存在,否则删除半成品并抛错(快速失败,不留空目录)
        if (!new File(extracted, "sht_afo_config.m").isFile()) {
            deleteRecursively(extracted);
            throw new IOException("jar 内未找到 AFO_V_2 程序资源(解压 " + extractedCount
                    + " 个文件);请确认部署包含 matlab/delivery 交付树");
        }
        log.info("AFO_V_2 解压完成: {} 个文件", extractedCount);
        return extracted;
    }

    /** 项目工作目录下的程序源位置:<workdir>/programs;workdir缺失时回退元数据目录。 */
    private File workProgramsDir(String projectId) throws IOException {
        try {
            EngineModels.EngineProject proj = store.getProject(projectId);
            if (proj != null && proj.getWorkdir() != null && !proj.getWorkdir().isEmpty()) {
                return new File(new File(proj.getWorkdir()), "programs");
            }
        } catch (IOException e) {
            log.warn("读取项目工作目录失败,程序源回退元数据目录: {}", projectId);
        }
        return new File(store.projectDir(projectId), "programs");
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
        String base = r06ProgramsBase();
        File src = null;
        File ext = deliveryProgramsDir();
        if (ext != null && new File(ext, "AFO_V_2").isDirectory()) src = new File(ext, "AFO_V_2");
        if (src == null || !src.isDirectory()) src = new File("datamodelgov-server/src/main/resources/" + base + "/AFO_V_2");
        if (!src.isDirectory()) src = new File("src/main/resources/" + base + "/AFO_V_2");
        if (!src.isDirectory()) src = new File("target/classes/" + base + "/AFO_V_2");
        if (!src.isDirectory()) src = new File("datamodelgov-server/target/classes/" + base + "/AFO_V_2");
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
            String prefix = r06ProgramsBase() + "/AFO_V_2/";
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

    /* ---------- R065 动态数据接入(UI-R138 第7章合同) ---------- */

    /**
     * 通道字典:R065 的 prepare 自产 channels.json(SHT_AFO_CATALOG_V2),含 272 项原始通道与
     * display/displayGroup/panel 等显示绑定。活动会话优先,无会话时回退最近一次含字典的历史会话。
     */
    public Map<String, Object> channelCatalog(String projectId) throws IOException {
        List<File> candidates = new ArrayList<>();
        AfoSession s = session;
        if (s != null && s.outputDir != null) {
            candidates.add(new File(s.outputDir, "channels.json"));
        }
        try {
            for (Map<String, Object> m : listSessions(projectId)) {
                Object od = m.get("outputDir");
                if (od != null) {
                    candidates.add(new File(String.valueOf(od), "channels.json"));
                }
            }
        } catch (Exception ignore) {
            // 历史列表失败不影响活动会话字典读取
        }
        for (File f : candidates) {
            if (f.isFile()) {
                return new com.fasterxml.jackson.databind.ObjectMapper().readValue(f, Map.class);
            }
        }
        throw new IOException("通道字典尚未生成(会话准备完成后可用;历史运行从结果Channels读取)");
    }

    /**
     * 增量样本读取(游标式,纯文件,不占用MATLAB引擎 —— UI-R138 7.3):扫描 outputDir/stream/*.json
     * (SHT_AFO_SAMPLES_V2 不可变样本块,文件名前12位数字定序),校验会话身份与序号连续,返回
     * sampleSeq &gt; afterSeq 的至多 maxRows 行;columns(目录0基下标)可裁剪列以减小传输。
     * 缺口不跨越:返回连续区段并附 gap{from,to},由前端保留缺口并提示原因(UI-R138 5.3)。
     */
    public Map<String, Object> readLive(String projectId, long afterSeq, String expectSessionId,
                                        Integer maxRows, int[] columns) throws IOException {
        AfoSession s = session;
        if (s == null || s.outputDir == null) {
            throw new IOException("无活动AFO会话;动态历史在准备完成后可读");
        }
        return readLiveFrom(s, afterSeq, expectSessionId, maxRows, columns);
    }

    /** 打开增量数据 SSE 流(program-run live-stream 同构):订阅即从 afterSeq 补读全量,此后 200ms 泵推增量。 */
    public org.springframework.web.servlet.mvc.method.annotation.SseEmitter openLiveStream(
            String projectId, long afterSeq, String expectSessionId, int[] columns) throws IOException {
        AfoSession s = session;
        if (s == null || s.outputDir == null) {
            throw new IOException("无活动AFO会话;动态历史在准备完成后可读");
        }
        org.springframework.web.servlet.mvc.method.annotation.SseEmitter em =
                new org.springframework.web.servlet.mvc.method.annotation.SseEmitter(0L); // 不超时,由 end/complete 关闭
        LiveSub sub = new LiveSub(em, expectSessionId, columns, afterSeq);
        liveSubs.add(sub);
        em.onCompletion(() -> liveSubs.remove(sub));
        em.onTimeout(() -> liveSubs.remove(sub));
        em.onError(t -> liveSubs.remove(sub));
        return em;
    }

    /** SSE 泵:逐订阅者按游标读增量并推送;isFinal/会话结束发 end 事件。 */
    private void pumpLiveSafely() {
        if (liveSubs.isEmpty()) {
            return;
        }
        AfoSession s = session;
        com.fasterxml.jackson.databind.ObjectMapper om = new com.fasterxml.jackson.databind.ObjectMapper();
        for (LiveSub sub : liveSubs) {
            if (sub.done || sub.busy) {
                continue;
            }
            sub.busy = true;
            try {
                if (s == null || s.outputDir == null) {
                    finishSub(sub, "session_closed", om);
                    continue;
                }
                Map<String, Object> batch = readLiveFrom(s, sub.cursor, sub.expectSessionId, 1024, sub.columns);
                sub.em.send(org.springframework.web.servlet.mvc.method.annotation.SseEmitter.event()
                        .name("live").data(om.writeValueAsString(batch)));
                sub.cursor = asLong(batch.get("nextSeq"));
                if (Boolean.TRUE.equals(batch.get("isFinal"))) {
                    finishSub(sub, "isFinal", om);
                }
            } catch (java.io.IOException io) {
                // 客户端断开(SSE 发送失败)或读取失败:结束该订阅
                finishSub(sub, "io", om);
            } catch (Exception e) {
                log.debug("AFO SSE 泵推送异常(下个周期重试): {}", e.getMessage());
            } finally {
                sub.busy = false;
            }
        }
    }

    private void finishSub(LiveSub sub, String reason, com.fasterxml.jackson.databind.ObjectMapper om) {
        try {
            sub.em.send(org.springframework.web.servlet.mvc.method.annotation.SseEmitter.event()
                    .name("end").data(om.writeValueAsString(java.util.Collections.singletonMap("reason", reason))));
        } catch (Exception ignore) {
            // 客户端已断开
        }
        sub.done = true;
        try {
            sub.em.complete();
        } catch (Exception ignore) {
            // 已完成
        }
        liveSubs.remove(sub);
    }

    /** 状态通知 SSE:会话全生命周期(IDLE/PREPARING/READY/RUNNING/ENDED)通用,
     *  1s指纹比对稳定状态字段,变化才推chg(前端收到后自行拉取一次/status)。
     *  指纹与负载只含稳定字段——排除time/sampleSeq/lastHeartbeat等高频项,运行中不会逐秒触发。 */
    public org.springframework.web.servlet.mvc.method.annotation.SseEmitter openStatusStream() {
        org.springframework.web.servlet.mvc.method.annotation.SseEmitter em =
                new org.springframework.web.servlet.mvc.method.annotation.SseEmitter(0L);
        Object[] sub = new Object[]{ em, "" };
        statusSubs.add(sub);
        em.onCompletion(() -> statusSubs.remove(sub));
        em.onTimeout(() -> { statusSubs.remove(sub); try { em.complete(); } catch (Exception ignore) { } });
        em.onError(t -> statusSubs.remove(sub));
        return em;
    }

    /** 状态通知泵:逐订阅者指纹比对(statusSubs元素{em,fp})。 */
    private void pumpStatusSafely() {
        if (statusSubs.isEmpty()) return;
        for (Object[] sub : statusSubs) {
            org.springframework.web.servlet.mvc.method.annotation.SseEmitter em =
                    (org.springframework.web.servlet.mvc.method.annotation.SseEmitter) sub[0];
            try {
                String json = OM_STATUS.writeValueAsString(statusNotifySnapshot());
                String fp = Integer.toString(json.hashCode()) + ':' + json.length();
                if (!fp.equals((String) sub[1])) {
                    sub[1] = fp;
                    em.send(org.springframework.web.servlet.mvc.method.annotation.SseEmitter.event()
                            .name("chg").data(json));
                }
            } catch (java.io.IOException io) {
                statusSubs.remove(sub);
                try { em.complete(); } catch (Exception ignore) { }
            } catch (Exception e) {
                log.debug("AFO状态SSE泵异常(下周期重试): {}", e.getMessage());
            }
        }
    }

    /** 稳定状态快照(指纹源+chg负载):Java生命周期真源 + status.json低频字段。 */
    private Map<String, Object> statusNotifySnapshot() {
        AfoSession s = session;
        Map<String, Object> out = new LinkedHashMap<>();
        if (s == null) {
            out.put("phase", "IDLE");
            return out;
        }
        out.put("phase", s.phase);
        out.put("message", s.message);
        out.put("error", s.error);
        out.put("runId", s.runId);
        File sf = new File(s.outputDir, "status.json");
        if (sf.isFile()) {
            try {
                Map<String, Object> live = OM_STATUS.readValue(sf, Map.class);
                for (String k : new String[]{"state", "saveState", "saveError", "publishError",
                        "observerError", "pauseRequested", "stopRequested", "publishLive"}) {
                    out.put(k, live.get(k));
                }
                Object ev = live.get("events");
                out.put("eventsLen", ev instanceof List ? ((List<?>) ev).size() : 0);
            } catch (Exception e) {
                log.debug("status.json 读取中(可能正在原子替换)", e);
            }
        }
        return out;
    }

    /** 供 SSE 泵复用的核心读取(会话对象直传)。 */
    private Map<String, Object> readLiveFrom(AfoSession s, long afterSeq, String expectSessionId,
                                             Integer maxRows, int[] columns) throws IOException {
        File dir = new File(s.outputDir, "stream");
        int limit = maxRows == null ? 2048 : Math.max(1, Math.min(maxRows, 8192));
        com.fasterxml.jackson.databind.ObjectMapper om = new com.fasterxml.jackson.databind.ObjectMapper();

        // 状态摘要(status.json 原子写,读失败按尚未就绪处理,不报告成中断)
        Map<String, Object> st = new LinkedHashMap<>();
        File sf = new File(s.outputDir, "status.json");
        if (sf.isFile()) {
            try {
                st = om.readValue(sf, Map.class);
            } catch (Exception e) {
                log.debug("status.json 读取中(可能正在原子替换)", e);
            }
        }

        String hash = st.get("channelCatalogHash") != null ? String.valueOf(st.get("channelCatalogHash")) : null;
        String sid = st.get("sessionId") != null ? String.valueOf(st.get("sessionId")) : null;
        if (expectSessionId != null && !expectSessionId.isEmpty() && sid != null && !expectSessionId.equals(sid)) {
            throw new IOException("会话身份不匹配(期望 " + expectSessionId + ",当前 " + sid + ");不跨会话拼接数据");
        }

        List<Long> seqList = new ArrayList<>();
        List<Object> timeList = new ArrayList<>();
        List<double[]> valueRows = new ArrayList<>();
        List<long[]> qualityRows = new ArrayList<>();
        long expected = afterSeq + 1;
        long gapFrom = -1, gapTo = -1;
        boolean stoppedOnGap = false;
        File[] files = dir.isDirectory() ? dir.listFiles((d, n) -> n.matches("\\d{12}\\.json")) : null;
        if (files != null) {
            java.util.Arrays.sort(files, Comparator.comparingLong(f -> Long.parseLong(f.getName().substring(0, 12))));
            for (File f : files) {
                Map<String, Object> blk;
                try {
                    blk = om.readValue(f, Map.class);
                } catch (Exception e) {
                    log.warn("AFO样本块解析失败(跳过,等待下次发布重试): {}", f.getName());
                    continue;
                }
                if (!"SHT_AFO_SAMPLES_V2".equals(String.valueOf(blk.get("schema")))) {
                    continue;
                }
                if (sid != null && blk.get("sessionId") != null && !sid.equals(String.valueOf(blk.get("sessionId")))) {
                    continue; // 旧会话遗留块,不属于当前连接
                }
                long first = asLong(blk.get("firstSeq"));
                long last = asLong(blk.get("lastSeq"));
                if (last <= afterSeq) {
                    continue; // 整块早于游标
                }
                if (first > expected) {
                    gapFrom = expected;
                    gapTo = first - 1;
                    stoppedOnGap = true;
                    break; // 缺口之后暂不拼接,等待缺失区间(可能尚未发布)重试
                }
                // jsonencode 会压扁尺寸为1的维度:单行块 values 为扁平272数组、sampleSeq/sampleTime 为标量
                List<?> seq = asListOrSingleton(blk.get("sampleSeq"));
                List<?> tArr = asListOrSingleton(blk.get("sampleTime"));
                List<?> vals = asRowList(blk.get("values"));
                List<?> qual = asRowListOrNull(blk.get("quality"));
                if (seq == null || tArr == null || vals == null) {
                    continue;
                }
                for (int r = 0; r < seq.size() && seqList.size() < limit; r++) {
                    long sq = asLong(seq.get(r));
                    if (sq <= afterSeq) {
                        continue; // 块内部分早于游标
                    }
                    seqList.add(sq);
                    timeList.add(tArr.get(r));
                    valueRows.add(toDoubleRow(asList(vals.get(r)), columns));
                    qualityRows.add(qual == null ? null : toLongRow(asList(qual.get(r)), columns));
                }
                expected = last + 1;
                if (seqList.size() >= limit) {
                    break;
                }
            }
        }
        boolean hasMore = !stoppedOnGap && expected <= asLong(st.get("publishedSeq"));
        boolean readFinal = Boolean.TRUE.equals(st.get("isFinal"))
                && expected > asLong(st.get("publishedSeq"))
                && !stoppedOnGap;
        long nextSeq = seqList.isEmpty() ? afterSeq : seqList.get(seqList.size() - 1);

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("runId", s.runId);
        out.put("sessionId", sid);
        out.put("channelCatalogHash", hash);
        out.put("state", st.get("state"));
        out.put("currentSimulationTime", st.getOrDefault("currentSimulationTime", st.get("time")));
        out.put("sampleTime", st.get("sampleTime"));
        out.put("sampleSeq", st.get("sampleSeq"));
        out.put("publishedSeq", st.get("publishedSeq"));
        out.put("lastHeartbeat", st.get("lastHeartbeat"));
        out.put("publishLive", st.getOrDefault("publishLive", true));
        out.put("publishError", st.get("publishError"));
        out.put("observerError", st.get("observerError"));
        out.put("saveState", st.getOrDefault("saveState", "not_started"));
        out.put("saveError", st.get("saveError"));
        // 暂停/结束请求标志随同一通道推送:前端11态状态机(暂停请求中/结束请求中)依赖其清除时机,
        // 缺失会导致SSE活跃期间标志无法从true刷新回false,界面卡在过渡态
        out.put("pauseRequested", st.get("pauseRequested"));
        out.put("stopRequested", st.get("stopRequested"));
        out.put("isFinal", readFinal);
        out.put("nextSeq", nextSeq);
        out.put("hasMore", hasMore);
        // 会话级状态/事件随同一通道推送(R138 7.5:状态与保存分开展示;命令回执可追溯):
        // phase/message 为 Java 生命周期真源;applied/pending/events 来自 status.json
        out.put("phase", s.phase);
        out.put("message", s.message);
        // MATLAB jsonencode 对单元素struct数组输出JSON对象而非数组;统一规范成数组(前端 filter/forEach 依赖)
        out.put("applied", asJsonArray(st.get("applied")));
        out.put("pending", asJsonArray(st.get("pending")));
        List<Object> evList = asJsonArray(st.get("events"));
        out.put("eventsLen", evList.size());
        out.put("events", evList); // 命令回执全量(小数组;前端按 eventsLen 变化刷新表)
        if (stoppedOnGap) {
            Map<String, Object> gap = new LinkedHashMap<>();
            gap.put("from", gapFrom);
            gap.put("to", gapTo);
            out.put("gap", gap);
        }
        out.put("sampleSeqList", seqList);
        out.put("sampleTimeList", timeList);
        out.put("values", valueRows);
        out.put("quality", qualityRows);
        out.put("width", columns == null ? -1 : columns.length);
        return out;
    }

    private static List<?> asList(Object o) {
        return o instanceof List ? (List<?>) o : java.util.Collections.emptyList();
    }

    /** JSON字段兼容标量与数组(单行样本块被jsonencode压扁)。 */
    private static List<?> asListOrSingleton(Object o) {
        if (o instanceof List) {
            return (List<?>) o;
        }
        return o == null ? null : java.util.Collections.singletonList(o);
    }

    /** 行集合:元素为数组则原样;元素为标量(单行压扁)则包成单行。 */
    private static List<?> asRowList(Object o) {
        if (!(o instanceof List)) {
            return null;
        }
        List<?> l = (List<?>) o;
        if (l.isEmpty() || l.get(0) instanceof List) {
            return l;
        }
        return java.util.Collections.singletonList(l);
    }

    private static List<?> asRowListOrNull(Object o) {
        return o == null ? null : asRowList(o);
    }

    private static long asLong(Object o) {
        if (o instanceof Number) {
            return ((Number) o).longValue();
        }
        if (o == null) {
            return 0L;
        }
        try {
            return Long.parseLong(String.valueOf(o));
        } catch (NumberFormatException e) {
            return 0L;
        }
    }

    private static double[] toDoubleRow(List<?> row, int[] columns) {
        if (columns == null) {
            double[] r = new double[row.size()];
            for (int i = 0; i < row.size(); i++) {
                Object v = row.get(i);
                r[i] = v instanceof Number ? ((Number) v).doubleValue() : Double.NaN;
            }
            return r;
        }
        double[] r = new double[columns.length];
        for (int i = 0; i < columns.length; i++) {
            int idx = columns[i];
            Object v = idx >= 0 && idx < row.size() ? row.get(idx) : null;
            r[i] = v instanceof Number ? ((Number) v).doubleValue() : Double.NaN;
        }
        return r;
    }

    private static long[] toLongRow(List<?> row, int[] columns) {
        if (columns == null) {
            long[] r = new long[row.size()];
            for (int i = 0; i < row.size(); i++) {
                Object v = row.get(i);
                r[i] = v instanceof Number ? ((Number) v).longValue() : 0L;
            }
            return r;
        }
        long[] r = new long[columns.length];
        for (int i = 0; i < columns.length; i++) {
            int idx = columns[i];
            Object v = idx >= 0 && idx < row.size() ? row.get(idx) : null;
            r[i] = v instanceof Number ? ((Number) v).longValue() : 0L;
        }
        return r;
    }

    /* ---------- 会话管理 ---------- */

    public Map<String, Object> currentStatus(String projectId) throws IOException {
        AfoSession s = session;
        Map<String, Object> out = new LinkedHashMap<>();
        if (s == null) {
            out.put("phase", "IDLE");
            out.put("message", "无活动会话");
            return out;
        }
        // 会话是进程级单例:即使从别的项目上下文发起,也要如实暴露,
        // 否则用户永远看不到已就绪的会话,也无法关闭(卡死新准备)
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
            String runId;
            Object userRunId = cfg.get("runId");
            if (userRunId != null && String.valueOf(userRunId).trim()
                    .matches("[A-Za-z0-9_\\-]{1,80}")) {
                runId = String.valueOf(userRunId).trim(); // 尊重用户自定义编号
            } else {
                runId = "M-R" + new java.text.SimpleDateFormat("yyyyMMdd_HHmmss").format(new java.util.Date());
            }
            cfg.put("runId", runId); // 回写:MATLAB侧status/Excel与Java元数据/前端定位三方一致
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
            MatlabEngine eng = takeWarmEngine();
            // 冷启兜底会耗尽预热引擎(启动期预热失败/未就绪时走到这里):
            // 准备期立即回填,保证下次 prepare 免冷启动,而不是等到会话结束
            if (warmEngineEnabled && warmEngine == null) {
                warmExecutor.submit(() -> startWarmEngine("回填"));
            }
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

    /** 命令走inbox文件通道(pause/resume/stop/np/load;记录服务点消费),不占用引擎。
     *  R065合同:命令携带sessionId/runId由会话校验身份,防串任务施加。 */
    public Map<String, Object> command(String projectId, String kind, Object value) throws IOException {
        AfoSession s = requireSession(projectId, null);
        if (!java.util.Arrays.asList("np", "load", "pause", "resume", "stop").contains(kind)) {
            throw new IllegalArgumentException("不支持的命令类型: " + kind + "(管理命令save/release/discard走专用端点)");
        }
        String id = "cmd_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12);
        Map<String, Object> cmd = new LinkedHashMap<>();
        cmd.put("id", id);
        cmd.put("kind", kind);
        cmd.put("value", value);
        // 身份字段从程序原子写的 status.json 读取,与会话校验一致。
        // status.json 每个记录步都在 movefile 原子替换,读取瞬间可能撞上替换窗口;
        // 缺 sessionId 会被 MATLAB 会话按合同拒收(R138实测),故重试+兜底,仍拿不到则不下发
        String sid = readSessionIdentity(s.outputDir);
        if (sid == null) {
            throw new IllegalStateException("无法读取会话身份(status.json/channels.json),命令未下发,请稍后重试");
        }
        cmd.put("sessionId", sid);
        cmd.put("runId", s.runId);
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

    /** 会话身份:优先 status.json(高频发布,重试避开替换窗口),回退 channels.json(准备期一次写入)。 */
    private static String readSessionIdentity(String outputDir) throws IOException {
        com.fasterxml.jackson.databind.ObjectMapper om = new com.fasterxml.jackson.databind.ObjectMapper();
        File sf = new File(outputDir, "status.json");
        for (int i = 0; i < 5; i++) {
            if (sf.isFile()) {
                try {
                    Object sid = om.readValue(sf, Map.class).get("sessionId");
                    if (sid != null) return String.valueOf(sid);
                } catch (Exception ignore) {
                    // 正在原子替换,稍后重试
                }
            }
            try {
                Thread.sleep(60);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                break;
            }
        }
        File cf = new File(outputDir, "channels.json");
        if (cf.isFile()) {
            try {
                Object sid = om.readValue(cf, Map.class).get("sessionId");
                if (sid != null) return String.valueOf(sid);
            } catch (Exception ignore) { /* 理论不发生 */ }
        }
        return null;
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
        Map<String, Object> r = new com.fasterxml.jackson.databind.ObjectMapper().readValue(f, Map.class);
        // 单元素struct数组被jsonencode成对象,前端 eventsList().filter 依赖数组,统一规范
        r.put("events", asJsonArray(r.get("events")));
        return r;
    }

    /** MATLAB jsonencode 对单元素struct数组输出JSON对象而非数组;统一规范成数组。 */
    private static List<Object> asJsonArray(Object o) {
        if (o instanceof List) {
            @SuppressWarnings("unchecked")
            List<Object> l = (List<Object>) o;
            return l;
        }
        List<Object> l = new ArrayList<>();
        if (o instanceof Map) l.add(o);
        return l;
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
        m.append("    case 'close'\n");
        m.append("        sht_afo_session('close'); r = 'ok'; % close has no output\n");
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
        // 预热回填:会话结束后自动补 1 台专属引擎,下次 prepare 免冷启动
        if (warmEngineEnabled && warmEngine == null) {
            warmExecutor.submit(() -> startWarmEngine("回填"));
        }
    }

    private AfoSession requireSession(String projectId, String expectPhase) throws IOException {
        AfoSession s = session;
        if (s == null) {
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
        // 结果/交付文件存在性(清单行展示用;读取侧listSessions同口径)
        File od = new File(s.outputDir == null ? "" : s.outputDir);
        idx.put("hasResult", new File(od, "result.json").exists());
        idx.put("hasExcel", findExcel(od) != null);
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
        // 仿真记录清单(IginX)同步,失败仅告警
        afoSessionService.upsertFromIndex(s.projectId, idx);
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
