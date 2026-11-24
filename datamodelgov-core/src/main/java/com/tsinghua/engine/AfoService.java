package com.tsinghua.engine;

import com.mathworks.engine.MatlabEngine;
import com.tsinghua.auth.util.AuthUtil;
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
 * 引擎生命周期(守护模式,engine.afo.daemon=true 默认):MATLAB 脱离服务常驻
 * (shareEngine 命名共享+PID 文件),服务重启/升级后 connectMatlab 收养,
 * DLL/函数/编译缓存不重付;会话终态断连保留守护,FAILED 废弃重建。
 * daemon=false 回到旧行为(每会话专用引擎,close 即杀,不占用TC24的共享引擎池)。
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
    /** 预热槽引擎所属项目:null=未绑定冷引擎(任意项目可取);非null=同项目可复用热引擎(DLL/函数已就位) */
    private volatile String warmProjectId;
    /** 常驻守护开关:默认 false——connectMatlab 按名收养在 R2019b 引擎拉起的共享会话上实测不可靠
     *  (会话存活时仍连接失败,2026-11-23 两次复现),且冷启实测仅 10~15s,收益不抵脆弱性。
     *  机制代码保留,升级 MATLAB 版本后可再评估启用。 */
    @org.springframework.beans.factory.annotation.Value("${engine.afo.daemon:false}")
    private boolean daemonEnabled;
    /** 服务停止时守护处置:quit=随服务关闭(默认);keep=断连保留,下次启动收养热引擎 */
    @org.springframework.beans.factory.annotation.Value("${engine.afo.stop-mode:quit}")
    private String daemonStopMode;
    private final ExecutorService warmExecutor = Executors.newSingleThreadExecutor(
            r -> { Thread t = new Thread(r, "afo-warm-engine"); t.setDaemon(true); return t; });
    /** 会话清单IGinX同步专用线程:upsert原在HTTP请求线程同步执行,IGinX会话掉线重连
     *  (实测单次~10s)会直接拖住前端/afo/prepare请求;清单行允许弱实时,改异步。 */
    private final ExecutorService indexExecutor = Executors.newSingleThreadExecutor(
            r -> { Thread t = new Thread(r, "afo-index"); t.setDaemon(true); return t; });

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
        /** 会话发起人(用户名);仅发起人或管理员可 run/command/save/close */
        String initiatorUser;
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
            if (daemonEnabled) {
                // 启动即收养/拉起常驻守护(后台执行,用户无感):首次 prepare 免冷启动
                warmExecutor.submit(() -> {
                    try {
                        takeWarmEngine(null);
                    } catch (Exception e) {
                        log.warn("AFO 常驻守护预热失败(首次prepare将同步冷启): {}", e.getMessage());
                    }
                });
            } else {
                warmExecutor.submit(() -> startWarmEngine("预热"));
            }
        }
        // 增量数据 SSE 泵(有订阅者才扫文件)
        livePump.scheduleWithFixedDelay(this::pumpLiveSafely, 200, 200, java.util.concurrent.TimeUnit.MILLISECONDS);
        // 状态通知 SSE 泵(1s指纹比对;准备期阶段迁移由此推送,前端不再依赖5s状态轮询)
        livePump.scheduleWithFixedDelay(this::pumpStatusSafely, 1000, 1000, java.util.concurrent.TimeUnit.MILLISECONDS);
    }

    /** 服务停止:按 engine.afo.stop-mode 处置常驻守护(quit=随服务关闭,默认;keep=断连保留跨重启)。 */
    @javax.annotation.PreDestroy
    public void shutdownAfoDaemon() {
        MatlabEngine eng = warmEngine;
        warmEngine = null;
        warmProjectId = null;
        if (eng == null) {
            if (!daemonEnabled) return;
            String adoptName = readDaemonAdoptName();
            if (adoptName == null) return;
            try {
                eng = MatlabEngine.connectMatlab(adoptName);
            } catch (Exception e) {
                return; // 守护不在(正常/已清理)
            }
        }
        try {
            if ("keep".equalsIgnoreCase(daemonStopMode)) {
                eng.disconnect();
                log.info("AFO 常驻守护保留(跨服务重启存活),下次启动自动收养");
            } else {
                eng.quit();
                deleteDaemonPidFile();
                log.info("AFO 常驻守护已随服务停止而关闭");
            }
        } catch (Exception e) {
            log.warn("AFO 守护处置失败: {}", e.getMessage());
        }
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
            bootstrapEngine(e, false);      // GBK字符集先就位:预装配经feval传中文路径依赖它
            prewarmInstrumentedModel(e);    // 启动预装配:改装模型常驻内存,首场prepare免load免手术
            warmEngine = e;
            log.info("AFO专属MATLAB引擎{}完成(耗时 {} ms),prepare 将直接取用", label, System.currentTimeMillis() - t0);
        } catch (Throwable e) {
            warmEngine = null;
            log.warn("AFO专属MATLAB引擎{}失败(prepare 时将同步重试): {}", label, e.getMessage());
        }
    }

    /** 启动预装配:专属引擎里把上次项目的改装模型装好并常驻内存,首场prepare即享复用
     *  (免load_system+免手术,实测这两项占稳态准备的~7-12s)。程序目录取上次会话落盘
     *  的 run/afo-warm.properties;失败仅日志跳过(首场prepare走完整流程),不影响功能。 */
    private void prewarmInstrumentedModel(MatlabEngine eng) {
        try {
            File pd = readWarmProgramDir();
            if (pd == null || !new File(pd, "sht_afo_presurgery.m").isFile()) return;
            // 启动时必须先应用补丁再预装配:补丁原在首次prepare才落盘,预热引擎会
            // 读到工作目录里的旧版函数(实测:预装配连跑两轮旧版直至首场prepare)
            TestbenchService.applyProgramPatches(pd.getParentFile());
            long t0 = System.currentTimeMillis();
            eng.feval(0, "addpath", pd.getAbsolutePath(), "-begin");
            eng.feval(0, "eval", "rehash;");
            eng.feval(0, "sht_afo_presurgery", pd.getAbsolutePath());
            log.info("AFO 启动预装配完成(改装模型常驻内存,耗时 {} ms),首场prepare免load免手术",
                    System.currentTimeMillis() - t0);
        } catch (Throwable t) {
            log.warn("AFO 启动预装配跳过(首场prepare走完整流程): {}", t.getMessage());
        }
    }

    /** 记录最近一次AFO准备的程序目录(run/afo-warm.properties):服务重启后启动预装配按此定位。 */
    private void persistWarmProgramDir(File progCopy) {
        try {
            File dir = new File("run");
            if (!dir.exists() && !dir.mkdirs()) return;
            java.nio.file.Files.write(new File(dir, "afo-warm.properties").toPath(),
                    ("programDir=" + progCopy.getAbsolutePath() + "\n")
                            .getBytes(java.nio.charset.StandardCharsets.UTF_8));
        } catch (Exception e) {
            log.warn("AFO预装配目录记录失败(不影响功能): {}", e.getMessage());
        }
    }

    private File readWarmProgramDir() {
        File f = new File("run", "afo-warm.properties");
        if (!f.isFile()) return null;
        try {
            String txt = new String(java.nio.file.Files.readAllBytes(f.toPath()),
                    java.nio.charset.StandardCharsets.UTF_8);
            for (String line : txt.split("\n")) {
                line = line.trim();
                if (line.startsWith("programDir=")) {
                    File pd = new File(line.substring("programDir=".length()).trim());
                    if (pd.isDirectory()) return pd;
                }
            }
        } catch (Exception ignore) {
            // 读失败按无记录处理:预热引擎不带模型,首场prepare走完整流程
        }
        return null;
    }

    /** AFO 专属引擎数(预热待命 + 会话独占),这两类都不进共享池,供工作台状态聚合读取。 */
    public int dedicatedEngineCount() {
        int n = warmEngine != null ? 1 : 0;
        AfoSession s = session;
        if (s != null && s.engine != null) n++;
        return n;
    }

    /** 取预热引擎:同项目热引擎直取(DLL/已解析函数常驻,免每会话重付);跨项目关闭换冷启。 */
    private synchronized MatlabEngine takeWarmEngine(String projectId) throws Exception {
        // 原生库路径注入必须先于任何 MatlabEngine 类引用:类初始化会触发 nativemvm 加载,
        // 路径未注入时 <clinit> 抛 UnsatisfiedLinkError 并永久污染该类(全通道 NoClassDefFoundError)
        com.tsinghua.matlab.MatlabNativeLibrary.prepare(null);
        MatlabEngine e = warmEngine;
        if (e != null && (warmProjectId == null || warmProjectId.equals(projectId))) {
            warmEngine = null;
            String bound = warmProjectId;
            warmProjectId = null;
            log.info(bound == null ? "AFO prepare 取用预热引擎"
                    : "AFO prepare 复用同项目热引擎(DLL/函数已就位,免冷启动与重解析)");
            return e;
        }
        if (e != null) {
            // 槽内引擎属于其他项目:进程级状态(模型/DLL/路径)不跨项目混用,关闭后冷启
            log.info("AFO 预热引擎属于其他项目({}),关闭后冷启动", warmProjectId);
            closeEngineRaw(e);
            e = null;
        }
        // 常驻守护收养:按 PID 文件中的共享名连接存活守护(跨服务重启/升级存活,DLL/函数/编译缓存保留);15s超时防挂起
        if (daemonEnabled) {
            String adoptName = readDaemonAdoptName();
            if (adoptName != null) {
                try {
                    long t = System.currentTimeMillis();
                    MatlabEngine eng = awaitFuture(MatlabEngine.connectMatlabAsync(adoptName), 15000,
                            "收养常驻守护 " + adoptName);
                    log.info("AFO prepare 收养常驻共享MATLAB守护 {}(耗时 {} ms,DLL/函数/编译缓存保留)", adoptName, System.currentTimeMillis() - t);
                    bootstrapEngine(eng, true);
                    return eng;
                } catch (Exception ex) {
                    log.warn("常驻守护收养失败({}),清理遗留守护后冷启动", ex.getMessage());
                    killStaleDaemon();
                }
            } else {
                log.info("无存活守护可收养(服务重启后首次属正常),清理遗留后冷启动注册新守护");
                killStaleDaemon();
            }
        }
        log.info("预热槽为空,冷启动守护MATLAB并注册共享会话");
        com.tsinghua.matlab.MatlabNativeLibrary.prepare(null);
        // 冷启带看门狗(180s)与一次重试:MATLAB 进程秒退时 startMatlab 会无限等待,
        // 必须超时失败并给出可行动提示,否则 prepare 线程永久挂起、日志与 SSE 全部静默
        MatlabEngine eng = null;
        Exception last = null;
        for (int attempt = 1; attempt <= 2; attempt++) {
            try {
                long t = System.currentTimeMillis();
                eng = awaitFuture(MatlabEngine.startMatlabAsync(), 180000, "冷启动MATLAB(第" + attempt + "次)");
                log.info("MATLAB 冷启完成,耗时 {} ms(第{}次尝试)", System.currentTimeMillis() - t, attempt);
                break;
            } catch (Exception ex) {
                last = ex;
                eng = null;
                log.warn("MATLAB 冷启失败(第{}次): {}", attempt, ex.getMessage());
            }
        }
        if (eng == null) {
            throw new java.io.IOException("MATLAB 引擎启动失败(已重试2次): "
                    + (last == null ? "未知" : last.getMessage())
                    + "。请手动打开 MATLAB 桌面客户端验证能否正常启动——秒退/无响应多为偏好损坏"
                    + "(%APPDATA%\\MathWorks\\MATLAB\\R2019b 改名重建)或 license 问题;修复后重试。");
        }
        bootstrapEngine(eng, false);
        return eng;
    }

    /** Future 看门狗:限时等待,超时取消并抛出(防 startMatlab/connectMatlab 无限挂起)。 */
    private static <T> T awaitFuture(java.util.concurrent.Future<T> f, long timeoutMs, String what) throws Exception {
        try {
            return f.get(timeoutMs, java.util.concurrent.TimeUnit.MILLISECONDS);
        } catch (java.util.concurrent.TimeoutException te) {
            f.cancel(true);
            throw new java.util.concurrent.TimeoutException(what + " 超时(" + timeoutMs + " ms)");
        }
    }

    /** 引擎bootstrap:GBK字符集 + 无名共享(自动唯一名,杜绝孤儿守护占用固定名的冲突) + PID/名字文件 + 会话复位。 */
    private void bootstrapEngine(MatlabEngine eng, boolean resetSession) throws Exception {
        eng.eval("feature('DefaultCharacterSet', 'GBK')");
        if (daemonEnabled) {
            eng.eval("matlab.engine.shareEngine");
            eng.eval("nm = matlab.engine.engineName; pid = double(feature('getpid'));");
            writeDaemonPidFile(eng);
        }
        if (resetSession) eng.eval("bdclose('all'); clear sht_afo_session; rehash;");
    }

    /** 守护PID文件(run/matlab-daemon-AFO.pid):两行 pid/name,供跨重启收养与 stop 脚本按PID精确清理。 */
    private void writeDaemonPidFile(MatlabEngine eng) {
        try {
            Object nm = eng.getVariable("nm");
            Object pid = eng.getVariable("pid");
            File dir = new File("run");
            if (!dir.exists() && !dir.mkdirs()) return;
            String content = "pid=" + ((Number) pid).intValue() + "\nname=" + String.valueOf(nm);
            java.nio.file.Files.write(daemonPidFile().toPath(),
                    content.getBytes(java.nio.charset.StandardCharsets.US_ASCII));
        } catch (Exception e) {
            log.warn("守护PID文件写入失败(不影响功能): {}", e.getMessage());
        }
    }

    private File daemonPidFile() {
        return new File("run", "matlab-daemon-AFO.pid");
    }

    private void deleteDaemonPidFile() {
        try {
            daemonPidFile().delete();
        } catch (Exception ignore) { }
    }

    /** 从PID文件读取上次守护的共享会话名;不存在/损坏返回 null。 */
    private String readDaemonAdoptName() {
        File f = daemonPidFile();
        if (!f.isFile()) return null;
        try {
            for (String l : new String(java.nio.file.Files.readAllBytes(f.toPath()),
                    java.nio.charset.StandardCharsets.US_ASCII).trim().split("\\r?\\n")) {
                if (l.startsWith("name=")) {
                    String v = l.substring(5).trim();
                    return v.isEmpty() ? null : v;
                }
            }
        } catch (Exception ignore) { }
        return null;
    }

    /** 清理遗留守护孤儿:按PID文件,进程名必须是MATLAB(防PID复用误杀其他进程)。 */
    private void killStaleDaemon() {
        File f = daemonPidFile();
        if (!f.isFile()) return;
        try {
            String pid = null;
            for (String l : new String(java.nio.file.Files.readAllBytes(f.toPath()),
                    java.nio.charset.StandardCharsets.US_ASCII).trim().split("\\r?\\n")) {
                if (l.startsWith("pid=")) { pid = l.substring(4).trim(); break; }
            }
            if (pid != null && !pid.isEmpty() && isMatlabProcess(pid)) {
                log.warn("清理遗留守护孤儿进程 pid={}", pid);
                killPid(pid);
            }
            f.delete();
        } catch (Exception e) {
            log.warn("遗留守护清理失败(忽略): {}", e.getMessage());
        }
    }

    private static boolean isMatlabProcess(String pid) {
        try {
            boolean win = System.getProperty("os.name", "").toLowerCase().contains("win");
            Process p = win
                    ? new ProcessBuilder("tasklist", "/fi", "pid eq " + pid, "/fo", "csv").start()
                    : new ProcessBuilder("/bin/sh", "-c", "ps -p " + pid + " -o comm=").start();
            java.io.ByteArrayOutputStream bos = new java.io.ByteArrayOutputStream();
            byte[] buf = new byte[4096];
            int n;
            try (java.io.InputStream in = p.getInputStream()) {
                while ((n = in.read(buf)) > 0) bos.write(buf, 0, n);
            }
            p.waitFor(5, java.util.concurrent.TimeUnit.SECONDS);
            String out = bos.toString(java.nio.charset.StandardCharsets.UTF_8.name()).toLowerCase();
            return out.contains("matlab");
        } catch (Exception e) {
            return false;
        }
    }

    private static void killPid(String pid) throws Exception {
        boolean win = System.getProperty("os.name", "").toLowerCase().contains("win");
        Process p = win
                ? new ProcessBuilder("taskkill", "/F", "/PID", pid).start()
                : new ProcessBuilder("/bin/sh", "-c", "kill -9 " + pid).start();
        p.waitFor(5, java.util.concurrent.TimeUnit.SECONDS);
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
        if (new File(user, "sht_afo_config.m").isFile()) {
            applyAfoProgramPatches(projectId);
            return user;
        }

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
        applyAfoProgramPatches(projectId);
        return extracted;
    }

    /** AFO 会话 Simulink 编译缓存跨会话复用:补丁资源把 CacheFolder 指到项目级共享目录
     *  job/afo/_slCache,模型未变时 Simulink 命中缓存跳过重编译——桌面客户端同目录
     *  反复运行的"快"正来自这份缓存复用。仅工作目录分支打补丁;ext/classes 直跑分支
     *  不动源目录。 */
    private void applyAfoProgramPatches(String projectId) {
        try {
            TestbenchService.applyProgramPatches(workProgramsDir(projectId));
        } catch (Exception e) {
            log.warn("AFO 程序补丁应用失败(按未补丁程序继续): {}", e.getMessage());
        }
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
                try {
                    Map<String, Object> m = new com.fasterxml.jackson.databind.ObjectMapper().readValue(f, Map.class);
                    m.put("ready", true);
                    return m;
                } catch (Exception ignore) {
                    // 单个损坏文件跳过,继续尝试下一个候选
                }
            }
        }
        // 未就绪是预期状态(准备期 channels.json 尚未写出):返回软载荷而非抛错,
        // 避免前端轮询与浏览器控制台出现 500 错误噪声;前端按 channels 缺失自行提示"重试中"
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("ready", false);
        out.put("channels", java.util.Collections.emptyList());
        out.put("message", "通道字典尚未生成(会话准备完成后可用;历史运行从结果Channels读取)");
        return out;
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
        // 进度三元组随live通道透传(status.json原生字段):SSE稳态运行期前端由帧刷新进度条/ETA,
        // 否则S.live.progress停留在运行前最后一次/status轮询的0,进度条恒0.0%
        out.put("progress", st.get("progress"));
        out.put("duration", st.get("duration"));
        out.put("wallSeconds", st.get("wallSeconds"));
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
        out.put("error", s.error); // 计算失败原因随SSE推送,前端FAILED横幅展示
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
        // 会话可见性按项目隔离:他人项目的会话不直接暴露(与项目owner过滤同口径),
        // 但全局引擎互斥仍在——如实披露占用方信息,避免用户发起准备时无声卡死
        if (projectId != null && !projectId.equals(s.projectId)) {
            out.put("phase", "IDLE");
            out.put("occupied", true);
            out.put("occupantProjectId", s.projectId);
            out.put("initiatorUser", s.initiatorUser);
            out.put("runId", s.runId);
            out.put("phaseOfOccupying", s.phase);
            out.put("message", "联合仿真通道被项目[" + s.projectId + "]的会话占用(发起人:"
                    + s.initiatorUser + ",runId=" + s.runId + "),请等待其结束并关闭后再发起");
            return out;
        }
        out.put("runId", s.runId);
        out.put("engineId", s.engineId);
        out.put("phase", s.phase);
        out.put("message", s.message);
        out.put("error", s.error);
        out.put("config", s.config);
        // 发起人披露:前端据此隐藏非授权用户的操作按钮(后端仍强制校验)
        out.put("initiatorUser", s.initiatorUser);
        // D12:输出目录只读披露(会话结果/status.json/inbox 落盘位置)
        out.put("outputDir", s.outputDir);
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
                // 占用方归属(可能是其他项目的会话):让发起人知道在等谁,而不是无声卡死
                String who = "由用户[" + cur.initiatorUser + "]在项目[" + cur.projectId + "]发起, ";
                throw new IllegalStateException("已有AFO会话在" + cur.phase + "(runId=" + cur.runId + ","
                        + who + "请先等待其结束并关闭)");
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
            // 与 sht_afo_prepare 的"结果目录已存在,不覆盖"断言一致,提前拦截:
            // 免得白启一台引擎后才收到顶层"dmg_afo_task",用户看不到真实原因
            if (outputDir.exists()) {
                throw new IllegalStateException("任务编号 " + runId + " 的结果目录已存在(上一次运行成果),"
                        + "MATLAB合同不覆盖已有结果;请更换任务编号或清理该目录后重新发起: "
                        + outputDir.getAbsolutePath());
            }
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
            s.initiatorUser = AuthUtil.getCurrentUsername();
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

    /** 操作权限:仅会话发起人或管理员可执行 run/command/save/close。
     *  发起人未记录(旧版本会话)时放行,避免把自己锁死。 */
    private void checkOperator(AfoSession s) {
        if (s == null || s.initiatorUser == null || s.initiatorUser.isEmpty()) return;
        if (AuthUtil.isAdmin()) return;
        String cur = AuthUtil.getCurrentUsername();
        if (!s.initiatorUser.equals(cur)) {
            throw new IllegalStateException("该会话由用户[" + s.initiatorUser + "]发起,仅发起人或管理员可操作");
        }
    }

    private void runPrepare(AfoSession s) {
        try {
            File progCopy = ensureAfoSource(s.projectId);
            writeAdapter(s, progCopy);
            MatlabEngine eng = takeWarmEngine(s.projectId);
            // 不在准备期回填:回填引擎与prepare抢CPU(实测stage2/3被拖慢2~5倍),且
            // 会话结束引擎交换时本场热引擎转入预热槽、回填引擎会被直接杀掉(纯浪费)。
            // 槽位兜底:失败路径closeEngine与非干净终态recycle各自回填。
            s.engine = eng;
            s.engineOwned = true;
            try {
                eng.feval(0, "eval", "feature('DefaultCharacterSet', 'GBK')");
            } catch (Exception ce) {
                log.warn("AFO引擎字符集设置失败(沿用默认)", ce);
            }
            s.programDir = progCopy.getAbsolutePath();
            final long prepareT0 = System.currentTimeMillis();
            s.message = "MATLAB已就绪;校验文件身份/初始化模型(气路与初态)中";
            logLine("MATLAB引擎已就绪,开始准备运行副本(校验身份/气路/初态)");
            // 厂商 prepare 无阶段回调:每5s刷新已进行时长到页面(SSE),替代"无反馈假死"
            final java.util.concurrent.ScheduledFuture<?>[] tick = new java.util.concurrent.ScheduledFuture[1];
            tick[0] = livePump.scheduleWithFixedDelay(() -> {
                try {
                    s.message = "初始化模型中(已进行 " + (System.currentTimeMillis() - prepareT0) / 1000 + " s)";
                } catch (Exception ignore) { }
            }, 5, 5, java.util.concurrent.TimeUnit.SECONDS);
            // 引擎内调 session('prepare', cfg);适配器读JSON构造cfg
            feval(s, "prepare", progCopy.getAbsolutePath());
            tick[0].cancel(false);
            logLine("模型初始化完成,耗时 " + (System.currentTimeMillis() - prepareT0) + " ms;准备完成,等待开始运行");
            s.phase = "READY";
            s.message = "准备完成;可开始运行";
            persistWarmProgramDir(progCopy); // 记录程序目录:下次服务启动预装配按此定位
            writeSessionIndex(s);
        } catch (Exception e) {
            log.error("AFO准备失败: {}", s.runId, e);
            s.phase = "FAILED";
            // 引擎异常顶层message通常只有"dmg_afo_task",真实原因在最内层cause
            // (如"结果目录已存在,不覆盖");沿cause链取最后一个非空message透传到界面
            String detail = e.getMessage();
            Throwable cur = e;
            while (cur.getCause() != null && cur.getCause() != cur) {
                cur = cur.getCause();
                if (cur.getMessage() != null && !cur.getMessage().isEmpty()) detail = cur.getMessage();
            }
            s.error = detail == null ? e.getClass().getSimpleName() : detail;
            s.message = "准备失败";
            closeEngine(s);
            writeSessionIndex(s);
        }
    }

    /** 开始运行(阻塞sim,放线程;运行中状态与命令走文件通道)。 */
    public Map<String, Object> run(String projectId) throws IOException {
        AfoSession s = requireSession(projectId, "READY");
        checkOperator(s);
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
            // 先填error/message再改phase:SSE按秒推送,若先置FAILED,前端可能在error赋值前收到失败态
            // 优先取MATLAB侧落盘的完整错误报告(含真实原因与调用栈),e.getMessage()通常只是顶层"dmg_afo_task"
            String rep = readMatlabErrorReport(s);
            if (rep != null) log.error("AFO错误报告 {}:\n{}", s.runId, rep);
            s.error = rep != null ? rep
                    : (e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage());
            s.message = "运行失败";
            s.phase = "FAILED";
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
        checkOperator(s);
        if (!java.util.Arrays.asList("np", "load", "pause", "resume", "stop").contains(kind)) {
            throw new IllegalArgumentException("不支持的命令类型: " + kind + "(管理命令save/release/discard走专用端点)");
        }
        // D13:在返回 accepted 之前按程序合同校验物理输入范围,非法命令直接拒收(不写 inbox)
        validateCommandValue(s.config, kind, value);
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

    /** D13:与 sht_afo_session.local_validate 保持一致的物理输入范围校验。
     *  非法值在此直接抛出,控制器返回明确的失败结果,前端不会再提示"已提交"。 */
    private static void validateCommandValue(Map<String, Object> cfg, String kind, Object value) {
        if (!"np".equals(kind) && !"load".equals(kind)) return;
        if ("np".equals(kind)) {
            double np = toDouble(value, "Np挡位");
            boolean ok = Math.abs(np - 0.8) < 1e-12 || Math.abs(np - 0.9) < 1e-12
                    || Math.abs(np - 0.95) < 1e-12 || Math.abs(np - 1.0) < 1e-12 || Math.abs(np - 1.05) < 1e-12;
            if (!ok) throw new IllegalArgumentException("Np挡位仅支持80%/90%/95%/100%/105%");
            return;
        }
        String mode = String.valueOf(cfg != null ? cfg.getOrDefault("loadMode", "power") : "power");
        if ("dual_pitch".equals(mode)) {
            if (!(value instanceof java.util.List) || ((java.util.List<?>) value).size() != 2) {
                throw new IllegalArgumentException("主尾桨总距须成对提交");
            }
            java.util.List<?> v = (java.util.List<?>) value;
            double main = toDouble(v.get(0), "主桨总距角");
            double tail = toDouble(v.get(1), "尾桨总距角");
            if (!(main >= 6 && main <= 14)) throw new IllegalArgumentException("主桨总距角须在6~14 deg");
            if (!(tail >= -8 && tail <= 18)) throw new IllegalArgumentException("尾桨总距角须在−8~18 deg");
            double ratio = num(cfg.get("tailToMainPowerRatio"), 0.10);
            double design = num(cfg.get("tailDesignPitchDeg"), 10);
            if (ratio < 0) throw new IllegalArgumentException("尾/主功率比须为非负数");
            if (design <= 0) throw new IllegalArgumentException("尾桨设计总距须为正数");
            double theta = equivalentPitch(main, tail, ratio, design);
            if (!(theta >= 6 && theta <= 14)) {
                throw new IllegalArgumentException(String.format("主尾桨合成等效角%.4g超出现有负载模型6~14度范围", theta));
            }
            return;
        }
        double v = toDouble(value, "负载值");
        if ("power".equals(mode) || "torque".equals(mode)) {
            if (!(v >= 0)) throw new IllegalArgumentException("负载须为非负数");
        } else if ("pitch".equals(mode)) {
            if (!(v >= 6 && v <= 14)) throw new IllegalArgumentException("总距角须在6~14 deg");
        } else {
            throw new IllegalArgumentException("未知负载方式: " + mode);
        }
    }
    private static double toDouble(Object v, String label) {
        double d = num(v, Double.NaN);
        if (!Double.isFinite(d)) throw new IllegalArgumentException(label + "须为数值");
        return d;
    }
    private static double num(Object v, double dflt) {
        if (v instanceof Number) return ((Number) v).doubleValue();
        if (v == null) return dflt;
        try { return Double.parseDouble(String.valueOf(v)); } catch (Exception e) { return dflt; }
    }
    /** 与 local_equivalent_pitch 同一公式(用于 dual_pitch 等效角范围校验)。 */
    private static double equivalentPitch(double main, double tail, double ratio, double design) {
        double f = 1.0 / (1.0 + ratio);
        double gm = 0.15 + 0.85 * Math.pow(main / 12.0, 1.5);
        double gt = 0.15 + 0.85 * Math.pow(Math.abs(tail / design), 1.5);
        return 12.0 * Math.pow((f * gm + (1 - f) * gt - 0.15) / 0.85, 2.0 / 3.0);
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
        checkOperator(s);
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

    /** 关闭会话(persistent单例清位;ENDED/FAILED后)。
     *  关闭是释放全局计算通道的清理动作:不受项目隔离限制,也不限发起人——
     *  任何登录用户都可关闭,否则通道会被跨项目/跨用户占用死锁。
     *  运行中仍不可关闭(先结束计算);运行/命令/保存仍限项目+发起人。 */
    public Map<String, Object> close(String projectId) throws IOException {
        AfoSession s = session;
        if (s == null) {
            throw new IllegalStateException("无活动AFO会话;请先发起准备");
        }
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
        recycleOrCloseEngine(s);
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
        if (!f.exists()) return readFailedAsResult(projectId, runId);
        Map<String, Object> r = new com.fasterxml.jackson.databind.ObjectMapper().readValue(f, Map.class);
        // 单元素struct数组被jsonencode成对象,前端 eventsList().filter 依赖数组,统一规范
        r.put("events", asJsonArray(r.get("events")));
        return r;
    }

    /** 失败会话没有result.json:从status.json合成只读失败结果(真实原因+事件+通道目录),
     *  让历史"打开(只读)"进入失败页面而不是报"结果尚未生成"。 */
    private Map<String, Object> readFailedAsResult(String projectId, String runId) {
        try {
            File dir = afoOutputDir(projectId, runId);
            File sf = new File(dir, "status.json");
            if (!sf.exists()) return null;
            Map<?, ?> st = new com.fasterxml.jackson.databind.ObjectMapper().readValue(sf, Map.class);
            if (!"failed".equalsIgnoreCase(String.valueOf(st.get("state")))) return null;
            Map<String, Object> r = new java.util.HashMap<>();
            r.put("phase", "FAILED");
            r.put("readonlyFailed", true);
            r.put("config", st.get("initialConfig"));
            r.put("events", asJsonArray(st.get("events")));
            r.put("duration", st.get("duration"));
            // 真实原因:优先MATLAB侧error-report.txt(新会话),回退status.json的error,再回退提示语
            File ad = new File(dir.getParentFile(), "_work_" + runId + File.separator + "adapter");
            String err = readMatlabErrorReport(ad);
            if (err == null) {
                Object e0 = st.get("error");
                err = (e0 == null || String.valueOf(e0).isEmpty())
                        ? "原因未记录(旧版本会话),请查看服务端日志或error-report.txt"
                        : String.valueOf(e0);
            }
            r.put("error", err);
            // 结果页"结束原因"列:异常首行 + Caused by 末尾真实原因;完整报告仍走error字段
            String summary = failureSummary(err);
            if (summary == null || summary.startsWith("原因未记录")) summary = String.valueOf(st.get("stopReason"));
            r.put("stopReason", summary);
            // 部分采样数据:从stream块组装time/values/channels,让只读失败页也能画出失败前的部分曲线
            // (结构与MATLAB侧result.json一致:values[i][gi][j],i=时刻,gi=spec组,j=组内序号)
            File cf = new File(dir, "channels.json");
            if (cf.exists()) {
                try {
                    com.fasterxml.jackson.databind.ObjectMapper om = new com.fasterxml.jackson.databind.ObjectMapper();
                    Map<?, ?> c = om.readValue(cf, Map.class);
                    List<?> specs = (List<?>) c.get("channels");
                    r.put("channels", specs);
                    r.put("catalog", specs);
                    r.put("channelCatalogHash", c.get("hash"));
                    File sd = new File(dir, "stream");
                    File[] blocks = sd.listFiles((d, n) -> n.toLowerCase().endsWith(".json"));
                    if (blocks != null && blocks.length > 0) {
                        java.util.Arrays.sort(blocks);
                        // 展开平铺通道id顺序(与前端specToCatalog一致):fuel_proxy_/air_g_为平铺spec
                        java.util.List<String> flatIds = new java.util.ArrayList<>();
                        for (Object so : specs) {
                            Map<?, ?> spec = (Map<?, ?>) so;
                            String sid = String.valueOf(spec.get("id"));
                            List<?> names = (List<?>) spec.get("names");
                            int nn = names == null ? 1 : names.size();
                            boolean flat = sid.startsWith("fuel_proxy_") || sid.startsWith("air_g_");
                            for (int j = 0; j < nn; j++) flatIds.add(flat ? sid : sid + "_" + String.format("%02d", j + 1));
                        }
                        java.util.List<Object> time = new java.util.ArrayList<>();
                        java.util.List<Object> vals = new java.util.ArrayList<>();
                        for (File b : blocks) {
                            try {
                                Map<?, ?> blk = om.readValue(b, Map.class);
                                Object bt = blk.get("sampleTime");
                                List<?> v = (List<?>) blk.get("values");
                                if (bt == null || v == null) continue;
                                time.add(bt);
                                java.util.List<Object> row = new java.util.ArrayList<>(specs.size());
                                int p = 0;
                                for (Object so : specs) {
                                    Map<?, ?> spec = (Map<?, ?>) so;
                                    List<?> names = (List<?>) spec.get("names");
                                    int nn = names == null ? 1 : names.size();
                                    boolean flat = String.valueOf(spec.get("id")).startsWith("fuel_proxy_")
                                            || String.valueOf(spec.get("id")).startsWith("air_g_");
                                    java.util.List<Object> grp = new java.util.ArrayList<>(nn);
                                    for (int j = 0; j < nn; j++) {
                                        int idx = flat ? p : p + j;
                                        grp.add(v.size() > idx ? v.get(idx) : null);
                                    }
                                    p += nn;
                                    row.add(grp);
                                }
                                vals.add(row);
                            } catch (Exception ignore) { /* 坏块跳过 */ }
                        }
                        if (!time.isEmpty()) { r.put("time", time); r.put("values", vals); }
                    }
                } catch (Exception ignore) { /* 目录缺失不影响失败查看 */ }
            }
            File[] xs = dir.listFiles((d, n) -> n.toLowerCase().endsWith(".xlsx"));
            if (xs != null) for (File x : xs) if (x.getName().startsWith("AFO_")) { r.put("excelName", x.getName()); break; }
            return r;
        } catch (Exception e) {
            return null;
        }
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
        m.append("try\n");
        m.append("switch lower(c.action)\n");
        m.append("    case 'prepare', r = sht_afo_session('prepare', cfg);\n");
        m.append("    case 'close'\n");
        m.append("        sht_afo_session('close'); r = 'ok'; % close has no output\n");
        m.append("    otherwise, r = sht_afo_session(lower(c.action));\n");
        m.append("end\n");
        m.append("catch ME\n");
        m.append("    % Write full error report (real reason + MATLAB call stack) for the Java side.\n");
        m.append("    fid = fopen(fullfile(fileparts(configFile), 'error-report.txt'), 'w', 'n', 'UTF-8');\n");
        m.append("    if fid > 0, fwrite(fid, getReport(ME, 'extended', 'hyperlinks', 'off'), 'char'); fclose(fid); end\n");
        m.append("    rethrow(ME);\n");
        m.append("end\n");
        m.append("payload = jsonencode(r);\n");
        m.append("fid = fopen(c.resultFile, 'w', 'n', 'UTF-8');\n");
        m.append("fwrite(fid, payload, 'char');\n");
        m.append("fclose(fid);\n");
        m.append("r = 'ok';\n");
        m.append("end\n");
        Files.write(new File(ad, "dmg_afo_task.m").toPath(), com.tsinghua.matlab.MatlabCharset.bytes(m.toString()));
    }

    /** 读取MATLAB侧错误报告(dmg_afo_task catch ME时写adapterDir/error-report.txt)。
     *  滤掉Goto/From匹配、端口未连接等编译警告行,只留真实错误与调用栈;
     *  上限20k字符,超长时保留截断标记(前端据此提示)。 */
    private String readMatlabErrorReport(AfoSession s) {
        return readMatlabErrorReport(new File(s.adapterDir));
    }

    private String readMatlabErrorReport(File ad) {
        try {
            File f = new File(ad, "error-report.txt");
            if (!f.isFile()) return null;
            String txt = com.tsinghua.matlab.MatlabCharset.read(f.toPath());
            StringBuilder sb = new StringBuilder();
            for (String line : txt.replace("\r", "").split("\n")) {
                String t = line.trim();
                if (t.startsWith("警告:") || t.startsWith("> In ")) continue;
                if (t.isEmpty() && sb.length() == 0) continue;
                if (sb.length() + line.length() > 20000) { sb.append("\n...(报告过长已截断,全文见error-report.txt)"); break; }
                sb.append(line).append('\n');
            }
            String out = sb.toString().trim();
            return out.isEmpty() ? null : out;
        } catch (Exception e) {
            return null;
        }
    }

    /** 失败原因摘要:异常首行 + 最后一个Caused by块的真实message(供结果页"结束原因"列定位问题);
     *  完整报告保留在error字段/error-report.txt。 */
    private String failureSummary(String err) {
        if (err == null) return null;
        String text = err.replace("\r", "");
        String first = null;
        for (String raw : text.split("\n")) {
            String t = raw.trim();
            if (!t.isEmpty()) { first = t; break; }
        }
        String last = null;
        int ci = text.lastIndexOf("Caused by");
        if (ci >= 0) {
            boolean headerSeen = false, msgStarted = false;
            StringBuilder msg = new StringBuilder();
            for (String raw : text.substring(ci).split("\n")) {
                String t = raw.trim();
                if (t.isEmpty()) { if (msgStarted) break; continue; }
                if (!headerSeen) { headerSeen = true; continue; }
                if (t.startsWith("错误使用") || t.startsWith("Error using")
                        || t.startsWith("出错") || t.startsWith("Error in")) {
                    if (msgStarted) break;
                    continue;
                }
                if (!msgStarted) msgStarted = true; else msg.append(' ');
                msg.append(t);
            }
            if (msgStarted) last = msg.toString();
        }
        if (first == null && last == null) return null;
        if (last == null || last.equals(first)) return first;
        return first + "；" + last;
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

    /** 失败路径引擎处置:引擎状态可疑,直接关闭并回填冷启(不复用)。 */
    private void closeEngine(AfoSession s) {
        MatlabEngine eng = s.engine;
        s.engine = null;
        if (daemonEnabled) {
            // FAILED 废弃重建:终结守护进程并清除PID文件,下次 prepare 冷启全新引擎
            if (eng != null) {
                try {
                    eng.quitAsync();
                } catch (Exception e) {
                    log.warn("守护终结失败(可能已自行退出)", e);
                }
            }
            deleteDaemonPidFile();
        } else {
            closeEngineRaw(eng);
        }
        scheduleWarmRefill();
    }

    private static void closeEngineRaw(MatlabEngine eng) {
        if (eng == null) return;
        try {
            eng.close();
        } catch (Exception e) {
            log.warn("AFO引擎关闭失败", e);
        }
    }

    private void scheduleWarmRefill() {
        if (warmEngineEnabled && !daemonEnabled && warmEngine == null) {
            warmExecutor.submit(() -> startWarmEngine("回填"));
        }
    }

    /**
     * 会话终态后引擎处置:同项目复用优先。复位序列(兜底停上一场仿真、清会话persistent、
     * 刷新函数缓存;改装模型特意保留在内存)后转入预热槽,DLL与已解析函数保留,下次
     * 同项目prepare免重付冷启动/DLL加载/函数解析/load/手术四重成本。合同支持:prepare 断言
     * 允许在 state='closed' 的会话上整体重建状态(sht_afo_session L10-17)。
     * 仅用于干净终态(CLOSED/ENDED);FAILED 等可疑状态仍走 closeEngine 不复用。
     */
    private synchronized void recycleOrCloseEngine(AfoSession s) {
        MatlabEngine eng = s.engine;
        s.engine = null;
        if (eng == null) return;
        boolean clean = "CLOSED".equals(s.phase) || "ENDED".equals(s.phase);
        if (clean) {
            try {
                // 复位只清会话persistent并兜底停仿真,不再bdclose——改装模型特意保留在内存,
                // 下次同项目prepare带同版本手术戳直取复用(免load_system+免手术,准备耗时大头)
                eng.feval(0, "eval", "try, set_param('Dll_Control_AFO_V8_5_R2019b',"
                        + "'SimulationCommand','stop'); catch, end; "
                        + "clear sht_afo_session; rehash;");
            } catch (Exception e) {
                log.warn("AFO引擎复位失败(继续复用): {}", e.getMessage());
            }
            // 引擎交换:保留本场热引擎(模型已加载/DLL已载/函数已解析),关闭槽内冷引擎。
            // 修复:此前"槽占用则关热引擎"导致每场都在冷引擎上重付 DLL/解析/模型加载(时快时慢)
            if (warmEngine != null && warmEngine != eng) {
                log.info("AFO 引擎交换: 关闭槽内冷引擎,本场热引擎转入预热槽");
                closeEngineRaw(warmEngine);
            }
            warmEngine = eng;
            warmProjectId = s.projectId;
            log.info("AFO引擎复用: 本场热引擎转入预热槽(项目{}),同项目下次prepare直取", s.projectId);
            return;
        }
        closeEngineRaw(eng);
        scheduleWarmRefill(); // 非干净终态:槽位已空,回填兜底(clean路径槽位由热引擎补满,无需回填)
    }

    private AfoSession requireSession(String projectId, String expectPhase) throws IOException {
        AfoSession s = session;
        if (s == null) {
            throw new IllegalStateException("无活动AFO会话;请先发起准备");
        }
        // 会话按项目隔离:他人项目(或本项目之外)的会话对本项目上下文不可见也不可操作;
        // 若通道确实被占用,附带占用方提示,避免"刚在别的项目发起却被告知无会话"的困惑
        if (projectId != null && !projectId.equals(s.projectId)) {
            throw new IllegalStateException("当前项目无活动AFO会话;请先发起准备"
                    + "(联合仿真通道被项目[" + s.projectId + "]的会话占用,发起人:" + s.initiatorUser
                    + ",runId=" + s.runId + ")");
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
        idx.put("initiatorUser", s.initiatorUser);
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
        // 仿真记录清单(IginX)同步:改异步——同步点原在HTTP请求线程,IGinX会话掉线重连
        // (实测单次~10s)会直接拖住前端/afo/prepare;文件元数据仍同步(会话检查依赖它)。
        // owner在HTTP线程先捕获(idx),异步线程无安全上下文。
        idx.put("owner", AuthUtil.getCurrentUsername());
        indexExecutor.submit(() -> afoSessionService.upsertFromIndex(s.projectId, idx));
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
