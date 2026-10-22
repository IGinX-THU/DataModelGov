package com.tsinghua.engine;

import com.tsinghua.matlab.MatlabEnginePool;
import com.tsinghua.matlab.MatlabFunctionRunner;
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
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.stream.Collectors;
import java.util.stream.Stream;

import com.tsinghua.engine.EngineModels.ModelingTask;
import com.tsinghua.engine.EngineModels.UqRecord;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

/**
 * 首链接入层:稳态试车建模(TC24,F-01)。
 * 按《程序调用与独立使用手册》第6章合同调用 R06 正式入口:
 *   result = Start_TC24_00_Offline(cfg), cfg = struct('task','identify','route',route,'options',o)
 * 程序在受控 MATLAB 工作进程中执行(MatlabFunctionRunner:引擎池 + 可取消 + 日志)。
 * 交付树只读:首次使用时把 m_program_adaptive_tune 复制为可写工作副本,再在其副本上加路径。
 */
@Slf4j
@Service
public class Tc24Service {

    /** R06 交付树根:支持绝对/相对文件路径;留空时自动探测工作区 resources 目录或从 classpath 解压。 */
    @Value("${matlab.engine.home:}")
    private String matlabHome;

    @Value("${matlab.engine.pool-size:4}")
    private int poolSize;

    @Value("${matlab.engine.enabled:true}")
    private boolean engineEnabled;

    private final EngineProjectStore store;
    private final ExecutorService executor = Executors.newFixedThreadPool(2);
    private final Map<String, MatlabFunctionRunner> running = new ConcurrentHashMap<>();
    /** 每任务运行代数:受理停止即落终态后允许立刻重新发起,旧执行按代数识别自己已过期,不再写回状态 */
    private final Map<String, java.util.concurrent.atomic.AtomicLong> runGens = new ConcurrentHashMap<>();
    private final Map<String, List<String>> logBuffers = new ConcurrentHashMap<>();
    private final Map<String, SseEmitter> uqLogEmitters = new ConcurrentHashMap<>();
    private final Map<String, Boolean> uqCancelPending = new ConcurrentHashMap<>();
    private volatile MatlabEnginePool enginePool;

    public Tc24Service(EngineProjectStore store) {
        this.store = store;
    }

    @PostConstruct
    void init() {
        if (engineEnabled) {
            enginePool = new MatlabEnginePool(poolSize, matlabHome);
            // 预热:启动常驻引擎(旧版程序预热已移除,新版辨识/UQ首次执行不再现启MATLAB)
            enginePool.init();
            log.info("TC24 接入层 MATLAB 引擎池已创建并预热(常驻1引擎): poolSize={}", poolSize);
        } else {
            log.info("MATLAB 引擎被禁用(matlab.engine.enabled=false),TC24 任务将直接失败");
        }
    }

    private static final String R06_IN_CLASSPATH = "programs/Delivery_V1_20261019_R06/programs";

    /** 程序包相对目录(工作副本根下保持交付树 programs/ 布局,便于相对引用 C_runtime 等)。 */
    private static final String PROG_SUBPATH = "programs/m_program_adaptive_tune";

    private static final String PROG_NAME = "m_program_adaptive_tune";

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

    /**
     * 解析TC24程序源目录(只认两处):
     * 1. 用户项目工作目录 <workdir>/programs/m_program_adaptive_tune(创建项目时预置,用户可自备,优先);
     * 2. target/classes(IDE开发兜底)。
     */
    private File resolveTc24Source(String projectId) throws IOException {
        File user = new File(workProgramsDir(projectId), PROG_NAME);
        if (new File(user, "Start_TC24_00_Offline.m").isFile()) return user;
        String[] classes = {
                "target/classes/" + R06_IN_CLASSPATH + "/" + PROG_NAME,
                "datamodelgov-server/target/classes/" + R06_IN_CLASSPATH + "/" + PROG_NAME
        };
        for (String c : classes) {
            File f = new File(c);
            if (new File(f, "Start_TC24_00_Offline.m").isFile()) return f;
        }
        return null;
    }

    /** 源不存在时从classpath(BOOT-INF/classes)预置到工作目录。 */
    private synchronized File ensureTc24Source(String projectId) throws IOException {
        File src = resolveTc24Source(projectId);
        if (src != null) return src;
        File dest = new File(workProgramsDir(projectId), PROG_NAME);
        log.info("TC24程序未在工作目录,从classpath预置: {} -> {}", "classpath", dest);
        extractClasspathProgram(dest);
        if (new File(dest, "Start_TC24_00_Offline.m").isFile()) return dest;
        throw new IOException("未找到TC24程序(workdir与classpath均无);请确认部署包含交付程序");
    }

    /**
     * 创建项目时预置TC24程序源:复制/解压到 <workdir>/programs/m_program_adaptive_tune
     * (已存在则跳过,不覆盖用户自备程序)。来源:工作区resources → target/classes → classpath。
     */
    public void provisionProgramForProject(String projectId) throws IOException {
        File target = new File(workProgramsDir(projectId), PROG_NAME);
        if (new File(target, "Start_TC24_00_Offline.m").isFile()) return; // 已有,不覆盖
        File src = resolveProgramSourceAny();
        if (src == null) {
            extractClasspathProgram(target);
        } else {
            copyRecursively(src.toPath(), target.toPath());
        }
        if (!new File(target, "Start_TC24_00_Offline.m").isFile()) {
            throw new IOException("TC24程序预置失败: 未形成可用入口 " + target);
        }
        log.info("TC24程序已预置到项目工作目录: {}", target);
    }

    /** 预置来源(打包资源优先):工作区resources → target/classes(r06-runtime工作副本体系已废除)。 */
    private File resolveProgramSourceAny() {
        String[] candidates = {
                "datamodelgov-server/src/main/resources/" + R06_IN_CLASSPATH + "/" + PROG_NAME,
                "src/main/resources/" + R06_IN_CLASSPATH + "/" + PROG_NAME,
                "target/classes/" + R06_IN_CLASSPATH + "/" + PROG_NAME,
                "datamodelgov-server/target/classes/" + R06_IN_CLASSPATH + "/" + PROG_NAME
        };
        for (String c : candidates) {
            File f = new File(c);
            if (f.isDirectory()) return f;
        }
        return null;
    }

    /** 从 classpath(含 Spring Boot fat jar 的 BOOT-INF/classes)解压 m_program_adaptive_tune 全部资源。 */
    private void extractClasspathProgram(File dest) throws IOException {
        org.springframework.core.io.support.PathMatchingResourcePatternResolver resolver =
                new org.springframework.core.io.support.PathMatchingResourcePatternResolver();
        String pattern = "classpath*:" + R06_IN_CLASSPATH + "/m_program_adaptive_tune/**/*";
        org.springframework.core.io.Resource[] resources = resolver.getResources(pattern);
        int count = 0;
        for (org.springframework.core.io.Resource r : resources) {
            String uri = r.getURI().toString();
            String marker = R06_IN_CLASSPATH + "/m_program_adaptive_tune/";
            int idx = uri.indexOf(marker);
            if (idx < 0) continue;
            String rel = uri.substring(idx + marker.length());
            if (rel.endsWith("/")) continue;
            File out = new File(dest, rel);
            if (out.getName().isEmpty()) continue;
            Files.createDirectories(out.getParentFile().toPath());
            try (java.io.InputStream in = r.getInputStream()) {
                Files.copy(in, out.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING);
            }
            count++;
        }
        if (count == 0) throw new IOException("classpath 中未找到 R06 程序资源: " + pattern);
        log.info("已从 classpath 解压 {} 个程序文件到 {}", count, dest);
    }

    /**
     * 启动辨识任务(异步):准备工作副本 → 生成适配器与配置 → MATLAB 执行 → 结果写回任务。
     */
    public ModelingTask runIdentification(ModelingTask task) throws IOException {
        final String key = task.getId();
        final java.util.concurrent.atomic.AtomicLong genRef =
                runGens.computeIfAbsent(key, k -> new java.util.concurrent.atomic.AtomicLong());
        final long gen = genRef.incrementAndGet();
        task.setStatus(ModelingTask.ST_PREPARING);
        task.setMessage("准备程序工作副本");
        task.setLogTail(new ArrayList<>());
        store.saveTask(task);
        logBuffers.put(key, new ArrayList<>());

        executor.submit(() -> {
            MatlabFunctionRunner runner = null;
            try {
                File programCopy = ensureTc24Source(task.getProjectId());
                File workDir = store.taskWorkDir(task.getProjectId(), task.getId());
                File adapterDir = new File(workDir, "adapter");
                if (!adapterDir.exists() && !adapterDir.mkdirs()) throw new IOException("无法创建适配器目录");
                File outputDir = new File(workDir, "output");
                if (!outputDir.exists() && !outputDir.mkdirs()) throw new IOException("无法创建输出目录");
                // 同 runId 重跑(重试/重新辨识)时追加时间戳,避免合同拒绝覆盖旧执行目录
                uniqueRunId(outputDir, task.getRunId(), task);
                File configFile = writeAdapterAndConfig(adapterDir, programCopy, task, outputDir);

                EngineModels.ModelingTask t = store.getTask(task.getProjectId(), task.getId());
                // 准备期间受理了停止(代数已递增):放弃本次执行,保持已停止终态
                if (genRef.get() != gen) {
                    emitLog(key, "执行已在启动前被停止,放弃本次运行");
                    return;
                }
                t.setStatus(ModelingTask.ST_RUNNING);
                t.setStartedAt(System.currentTimeMillis());
                t.setMessage("MATLAB 辨识执行中");
                store.saveTask(t);
                emitLog(key, "调用 Start_TC24_00_Offline, route=" + task.getRoute());

                runner = new MatlabFunctionRunner(adapterDir, "dmg_tc24_task",
                        new Object[]{configFile.getAbsolutePath()},
                        new File(workDir, "run.log"), enginePool,
                        new MatlabFunctionRunner.ProgressCancellationSink() {
                            @Override
                            public void onProgress(String message) {
                                emitLog(key, message);
                            }

                            @Override
                            public boolean isCancellationRequested() {
                                // 安全停止走合同 stop_request(task='stop'),不走引擎取消
                                return false;
                            }
                        });
                running.put(key, runner);
                Object result = prepPayload(runner.run(), new File(adapterDir, "result.json"));

                // 手动停止受理即落终态;若期间已重新发起辨识(代数已变),旧执行不再写回,避免覆盖新一次运行
                if (genRef.get() != gen) {
                    emitLog(key, "旧执行已在安全点结束;检测到重新发起的辨识,结果写回跳过");
                    return;
                }
                t = store.getTask(task.getProjectId(), task.getId());
                t.setFinishedAt(System.currentTimeMillis());
                String status = extractStatus(result);
                if ("stopped".equals(status) || "partial".equals(status)) {
                    t.setStatus(ModelingTask.ST_STOPPED);
                    t.setMessage("已按安全点停止;检查点已保存,可重新发起辨识");
                    emitLog(key, "任务已安全停止");
                } else if ("failed".equals(status)) {
                    t.setStatus(ModelingTask.ST_FAILED);
                    t.setMessage("辨识程序返回失败,详见日志");
                    t.setErrorKind(ModelingTask.ERR_NUMERIC);
                    emitLog(key, "程序返回失败");
                } else {
                    t.setStatus(ModelingTask.ST_COMPLETED);
                    t.setMessage("辨识完成");
                    emitLog(key, "任务完成");
                }
                t.setResult(summarizeResult(result, outputDir));
                store.saveTask(t);

                // 结果结构化(仅成功/诊断完成):task='read' 回读 result_view.mat,
                // 生成前端曲线、节点表、逐通道误差所需的明细 JSON(01-06/01-07)
                if (ModelingTask.ST_COMPLETED.equals(t.getStatus())) {
                    try {
                        File detail = readResultDetail(task.getProjectId(), outputDir, t.getRunId(),
                                "dmg_result_detail.json", DETAIL_FIELDS_IDENTIFY);
                        if (detail != null && detail.exists()) {
                            t = store.getTask(task.getProjectId(), task.getId());
                            t.setResultDetailFile(detail.getAbsolutePath());
                            store.saveTask(t);
                            emitLog(key, "结果明细已生成(曲线与节点表可浏览)");
                        } else {
                            emitLog(key, "未找到 result_view.mat,结果明细跳过");
                        }
                    } catch (Exception re) {
                        emitLog(key, "结果明细生成失败(不影响辨识结果): " + re.getMessage());
                    }
                }
            } catch (Exception e) {
                log.error("TC24 任务执行失败: {}", key, e);
                if (genRef.get() != gen) {
                    emitLog(key, "旧执行失败;检测到重新发起的辨识,状态写回跳过");
                } else {
                    try {
                        EngineModels.ModelingTask t = store.getTask(task.getProjectId(), task.getId());
                        t.setStatus(ModelingTask.ST_FAILED);
                        t.setFinishedAt(System.currentTimeMillis());
                        t.setMessage(e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage());
                        t.setErrorKind(classifyError(e.getMessage()));
                        store.saveTask(t);
                    } catch (IOException io) {
                        log.error("任务状态写回失败", io);
                    }
                    emitLog(key, "任务失败: " + e.getMessage());
                }
            } finally {
                // 两参 remove:重新发起后 running 里已映射到新执行的 runner,不能误删
                if (runner != null) running.remove(key, runner);
            }
        });
        return task;
    }

    /**
     * 取消UQ评估:引擎runner协作取消(requestCancel),准备阶段则记pending待执行体检查。
     * 取消受理即落终态(FAILED+已取消),前端轮询立刻回到可重新发起的状态;
     * MATLAB侧在最近的协作检查点退出,catch里幂等重写同一状态,不产生二次影响。
     */
    public boolean requestUqCancel(String projectId, String taskId) {
        try {
            EngineModels.ModelingTask t = store.getTask(projectId, taskId);
            if (t == null) return false;
            String uqStatus = t.getUqStatus();
            if (!"EXECUTING".equals(uqStatus) && !"PREPARING".equals(uqStatus)) return false;
            MatlabFunctionRunner runner = running.get(taskId + ":uq");
            if (runner != null) {
                runner.requestCancel();
                emitLog(taskId, "已请求取消UQ评估;程序将在最近检查点退出");
            } else {
                uqCancelPending.put(taskId + ":uq", true);
                emitLog(taskId, "已请求取消UQ评估(准备阶段)");
            }
            long now = System.currentTimeMillis();
            t.setUqStatus("FAILED");
            t.setUqFinishedAt(now);
            t.setUqMessage("已手动取消评估;结果不保存,可重新发起");
            store.saveTask(t);
            UqRecord rec = null;
            for (UqRecord r : store.listUqRecords(projectId)) {
                if (taskId.equals(r.getTaskId()) && UqRecord.ST_EXECUTING.equals(r.getStatus())) { rec = r; break; }
            }
            if (rec != null) {
                rec.setStatus(UqRecord.ST_FAILED);
                rec.setFinishedAt(now);
                rec.setMessage("已手动取消评估");
                store.saveUqRecord(rec);
            }
            return true;
        } catch (IOException e) {
            log.warn("UQ取消状态写回失败", e);
            return false;
        }
    }

    /**
     * 请求停止(合同路径):通过引擎调用 Start_TC24_00_Offline(task='stop'),
     * 由 sht_tc24_run_control 在 {outputDirectory}/run_control/ 落 stop_request,
     * 运行中的辨识在最近安全点保存检查点后结束;不强制中断引擎。
     * 受理即落终态(与取消UQ评估同逻辑):立即置 STOPPED,前端马上回到可重新辨识页面;
     * 运行中程序在最近安全点退出后,旧执行按代数守卫不再重复写回状态。
     */
    public boolean requestStop(String projectId, String taskId) {
        try {
            EngineModels.ModelingTask t = store.getTask(projectId, taskId);
            if (t == null) return false;
            String st = t.getStatus();
            boolean busy = ModelingTask.ST_RUNNING.equals(st) || ModelingTask.ST_PREPARING.equals(st)
                    || ModelingTask.ST_STOP_REQUESTED.equals(st);
            if (!busy) return false;
            // 受理即落终态(与取消UQ评估同逻辑):立即置 STOPPED,前端马上回到可重新辨识页面;
            // 同时递增运行代数,使在跑/准备中的执行过期,不再写回状态
            runGens.computeIfAbsent(taskId, k -> new java.util.concurrent.atomic.AtomicLong()).incrementAndGet();
            t.setStatus(ModelingTask.ST_STOPPED);
            t.setFinishedAt(System.currentTimeMillis());
            t.setMessage("已手动停止;可重新发起辨识");
            store.saveTask(t);
            if (running.get(taskId) == null) {
                // 无在跑引擎执行(如服务重启遗留的RUNNING状态):状态已自愈为已停止,无需写stop_request
                emitLog(taskId, "任务无在跑执行,已直接标记为停止");
                return true;
            }
            emitLog(taskId, "已提交安全停止请求(task=stop);程序将在最近安全点结束");
        } catch (IOException e) {
            log.warn("停止状态写回失败", e);
            return false;
        }
        executor.submit(() -> {
            try {
                File workDir = store.taskWorkDir(projectId, taskId);
                File outputDir = new File(workDir, "output");
                File programCopy = ensureTc24Source(projectId);
                File adapterDir = new File(workDir, "adapter");
                if (!adapterDir.exists() && !adapterDir.mkdirs()) throw new IOException("无法创建适配器目录");

                StringBuilder m = new StringBuilder();
                m.append("function r = dmg_tc24_stop(configFile)\n");
                m.append("c = jsondecode(fileread(configFile));\n");
                m.append("addpath('").append(programCopy.getAbsolutePath().replace('\\', '/')).append("', '-begin');\n");
                m.append("rehash;\n");
                // 返回值可能含 table,不能跨引擎;丢弃并返回固定标记
                m.append("Start_TC24_00_Offline(struct('task','stop','directory',c.directory));\n");
                m.append("r = 'ok';\n");
                m.append("end\n");
                Files.write(new File(adapterDir, "dmg_tc24_stop.m").toPath(),
                        m.toString().getBytes(StandardCharsets.UTF_8));

                Map<String, Object> cfg = new LinkedHashMap<>();
                cfg.put("directory", outputDir.getAbsolutePath().replace('\\', '/'));
                File configFile = new File(adapterDir, "stop-config.json");
                Files.write(configFile.toPath(),
                        new com.fasterxml.jackson.databind.ObjectMapper()
                                .writerWithDefaultPrettyPrinter().writeValueAsBytes(cfg));

                MatlabFunctionRunner stopRunner = new MatlabFunctionRunner(adapterDir, "dmg_tc24_stop",
                        new Object[]{configFile.getAbsolutePath()},
                        new File(workDir, "stop.log"), enginePool,
                        new MatlabFunctionRunner.ProgressCancellationSink() {
                            @Override public void onProgress(String message) { emitLog(taskId, message); }
                            @Override public boolean isCancellationRequested() { return false; }
                        });
                stopRunner.run();
                emitLog(taskId, "安全停止请求已写入运行控制目录");
            } catch (Exception e) {
                log.warn("TC24 合同停止请求失败(任务可能已自行结束): {}", taskId, e);
            }
        });
        return true;
    }

    public List<String> logTail(String taskId) {
        List<String> buf = logBuffers.get(taskId);
        return buf == null ? new ArrayList<>() : new ArrayList<>(buf);
    }

    /**
     * 订阅UQ评估日志流(SSE)。
     * 建立连接时先回放缓冲中已有的日志行(页面刷新后不丢历史),之后每次emitLog实时推送。
     */
    public void subscribeUqLogs(String taskId, SseEmitter emitter) {
        uqLogEmitters.put(taskId, emitter);

        try {
            List<String> buf = logBuffers.get(taskId);
            if (buf != null) {
                synchronized (buf) {
                    for (String line : buf) {
                        emitter.send(SseEmitter.event().data(line));
                    }
                }
            }
            if (buf == null || buf.isEmpty()) {
                emitter.send(SseEmitter.event().data("[系统] 已连接UQ日志流,等待程序输出..."));
            }
        } catch (Exception e) {
            log.warn("UQ日志回放失败: {}", taskId, e);
            uqLogEmitters.remove(taskId);
            try { emitter.complete(); } catch (Exception ignore) { }
        }
    }

    /* ---------- 结果结构化(task='read' 回读,白名单子集) ---------- */

    /** 辨识明细白名单(对应 sht_tc24_result_view identification 视图;曲线/节点表/误差/耗时) */
    private static final String[] DETAIL_FIELDS_IDENTIFY = {
            "kind", "status", "runId", "route", "message", "fuelBiasUnit",
            "parameterClassTable", "scheduleNodeTable", "finalSchedule", "groupEstimateTable",
            "predictionTrainingTable", "predictionTestTable",
            "baseline", "final", "acceptance", "residualStatistics", "timing", "execution"
    };

    /**
     * 回读 {outputDir}/{runId}/result_view.mat,生成明细 JSON。
     * @param fields 白名单字段;null 时由适配器保留顶层全部标量/表字段(Excel 视图用 parameterTable)
     */
    private File readResultDetail(String projectId, File outputDir, String runId, String detailFileName,
                                  String[] fields) throws IOException {
        File viewMat = new File(new File(outputDir, runId == null ? "" : runId), "result_view.mat");
        if (!viewMat.exists()) {
            // 兼容 session.directory 直接落在 outputDir 的情形
            File alt = new File(outputDir, "result_view.mat");
            if (!alt.exists()) return null;
            viewMat = alt;
        }
        File out = new File(viewMat.getParentFile(), detailFileName);
        return runReadAdapter(viewMat.getAbsolutePath(), out, fields, projectId) ? out : null;
    }

    /** 回读交付 Excel(UQ parameterTable 视图)生成明细 JSON。 */
    public File readExcelDetail(String projectId, File excel, File out) throws IOException {
        return runReadAdapter(excel.getAbsolutePath(), out, null, projectId) ? out : null;
    }

    /** 生成并执行 task='read' 适配器;fields 非空时只保留白名单顶层字段。 */
    private boolean runReadAdapter(String resultFile, File detailOut, String[] fields, String projectId) throws IOException {
        if (detailOut.exists()) return true; // 已生成过,直接复用
        try {
            File programCopy = ensureTc24Source(projectId);
            File adapterDir = new File(System.getProperty("java.io.tmpdir"), "datamodelgov-read-adapter");
            if (!adapterDir.exists() && !adapterDir.mkdirs()) throw new IOException("无法创建回读适配器目录");

            String keep = "[]";
            if (fields != null) {
                StringBuilder sb = new StringBuilder("{");
                for (int i = 0; i < fields.length; i++) {
                    if (i > 0) sb.append(',');
                    sb.append('\'').append(fields[i]).append('\'');
                }
                sb.append('}');
                keep = sb.toString();
            }

            StringBuilder m = new StringBuilder();
            m.append("function r = dmg_tc24_read(configFile)\n");
            m.append("c = jsondecode(fileread(configFile));\n");
            m.append("addpath('").append(programCopy.getAbsolutePath().replace('\\', '/')).append("', '-begin');\n");
            m.append("rehash;\n");
            m.append("view = Start_TC24_00_Offline(struct('task','read','resultFile',c.resultFile));\n");
            m.append("view = dmg_jsonable_view(view);\n");
            m.append("keep = ").append(keep).append(";\n");
            m.append("if ~isempty(keep)\n");
            m.append("    v = struct(); f = fieldnames(view);\n");
            m.append("    for i = 1:numel(f)\n");
            m.append("        if any(strcmp(f{i}, keep)), v.(f{i}) = view.(f{i}); end\n");
            m.append("    end\n");
            m.append("    view = v;\n");
            m.append("end\n");
            m.append("payload = jsonencode(view);\n");
            m.append("fid = fopen(c.detailFile, 'w', 'n', 'UTF-8');\n");
            m.append("fwrite(fid, payload, 'char');\n");
            m.append("fclose(fid);\n");
            m.append("r = 'ok';\n");
            m.append("end\n");
            // 表→struct 转换(比 dmg_jsonable 多处理缺失值与非标量)
            m.append("function s = dmg_jsonable_view(v)\n");
            m.append("if isa(v,'table')\n");
            m.append("    s = dmg_jsonable_view(table2struct(v));\n");
            m.append("elseif isstruct(v)\n");
            m.append("    s = v; f = fieldnames(s);\n");
            m.append("    for i = 1:numel(s)\n");
            m.append("        for j = 1:numel(f)\n");
            m.append("            s(i).(f{j}) = dmg_jsonable_view(s(i).(f{j}));\n");
            m.append("        end\n");
            m.append("    end\n");
            m.append("elseif iscell(v)\n");
            m.append("    for i = 1:numel(v), v{i} = dmg_jsonable_view(v{i}); end\n");
            m.append("    s = v;\n");
            m.append("elseif isstring(v)\n");
            m.append("    s = char(v);\n");
            m.append("else\n");
            m.append("    s = v;\n");
            m.append("end\n");
            m.append("end\n");
            Files.write(new File(adapterDir, "dmg_tc24_read.m").toPath(),
                    m.toString().getBytes(StandardCharsets.UTF_8));

            Map<String, Object> cfg = new LinkedHashMap<>();
            cfg.put("resultFile", resultFile.replace('\\', '/'));
            cfg.put("detailFile", detailOut.getAbsolutePath().replace('\\', '/'));
            File configFile = new File(adapterDir, "read-config.json");
            Files.write(configFile.toPath(),
                    new com.fasterxml.jackson.databind.ObjectMapper()
                            .writerWithDefaultPrettyPrinter().writeValueAsBytes(cfg));

            MatlabFunctionRunner runner = new MatlabFunctionRunner(adapterDir, "dmg_tc24_read",
                    new Object[]{configFile.getAbsolutePath()},
                    new File(adapterDir, "read.log"), enginePool,
                    new MatlabFunctionRunner.ProgressCancellationSink() {
                        @Override public void onProgress(String message) { MatlabLogRing.append(message); }
                        @Override public boolean isCancellationRequested() { return false; }
                    });
            runner.run();
            return detailOut.exists();
        } catch (Exception e) {
            log.warn("结果明细回读失败: {}", resultFile, e);
            return false;
        }
    }

    /** 错误分类(图01-16):交付文件/写盘问题与数值问题分开呈现。 */
    private String classifyError(String message) {
        String lower = message == null ? "" : message.toLowerCase();
        if (lower.contains("excel") || lower.contains("save") || lower.contains("write")
                || lower.contains("export") || lower.contains("deliver") || lower.contains("disk")
                || lower.contains("保存") || lower.contains("写")) {
            return ModelingTask.ERR_SAVE;
        }
        return ModelingTask.ERR_NUMERIC;
    }

    /**
     * 可选UQ评估(F-07-TC24):Start_TC24_00_Offline(task='uq',method=B|C|D),
     * options 走 sht_tc24_b_config 集中默认(particleCount 允许 512/1024);runId 带 tc24_ 前缀;
     * 结果另存 uq-output,不覆盖确定性辨识结果。完成后登记 UqRecord 并关联到模型成果。
     */
    public UqRecord runUq(ModelingTask task, String method, String deterministicWorkbook,
                          Integer particleCount, String modelAssetId) throws IOException {
        final String key = task.getId();
        final UqRecord record = new UqRecord();
        record.setProjectId(task.getProjectId());
        record.setTaskId(task.getId());
        record.setModelAssetId(modelAssetId);
        record.setMethod(method);
        record.setParticleCount(particleCount);
        record.setStatus(UqRecord.ST_EXECUTING);
        record.setMessage("准备UQ程序工作副本");
        String ts = new java.text.SimpleDateFormat("yyyyMMdd_HHmmss").format(new java.util.Date());
        record.setRunId("tc24_" + method.toLowerCase() + "_" + ts);
        record.setStartedAt(System.currentTimeMillis());
        store.saveUqRecord(record);

        task.setUqStatus("PREPARING");
        task.setUqMessage("准备UQ程序工作副本");
        task.setUqRunId(record.getRunId());
        store.saveTask(task);
        // UQ 日志缓冲:emitLog 依赖它,缺了日志会被静默丢弃(前端只见"等待日志输出...")
        logBuffers.put(key, new ArrayList<>());
        uqCancelPending.remove(key + ":uq");
        emitLog(key, "发起UQ评估: method=" + method + ", runId=" + record.getRunId());

        final String m = method;
        executor.submit(() -> {
            MatlabFunctionRunner runner = null;
            try {
                File programCopy = ensureTc24Source(task.getProjectId());
                File workDir = store.taskWorkDir(task.getProjectId(), task.getId());
                File adapterDir = new File(workDir, "adapter");
                if (!adapterDir.exists() && !adapterDir.mkdirs()) throw new IOException("无法创建适配器目录");
                File uqOutputDir = new File(workDir, "uq-output");
                if (!uqOutputDir.exists() && !uqOutputDir.mkdirs()) throw new IOException("无法创建UQ输出目录");
                File configFile = writeUqAdapterAndConfig(adapterDir, programCopy, task, m,
                        deterministicWorkbook, uqOutputDir, particleCount);

                UqRecord fresh = store.getUqRecord(record.getProjectId(), record.getId());
                fresh.setStatus(UqRecord.ST_EXECUTING);
                fresh.setMessage("UQ 评估执行中(方法 " + m + ")");
                store.saveUqRecord(fresh);
                EngineModels.ModelingTask t = store.getTask(task.getProjectId(), task.getId());
                t.setUqStatus("EXECUTING");
                t.setUqMessage("UQ 评估执行中(方法 " + m + ")");
                t.setUqStartedAt(System.currentTimeMillis());
                store.saveTask(t);
                emitLog(key, "调用 Start_TC24_00_Offline, task=uq, method=" + m);

                // 准备阶段(引擎runner尚未注册)收到取消请求:直接以取消结束
                if (uqCancelPending.remove(key + ":uq") != null) {
                    throw new java.util.concurrent.CancellationException("已在准备阶段取消");
                }
                runner = new MatlabFunctionRunner(adapterDir, "dmg_tc24_task",
                        new Object[]{configFile.getAbsolutePath()},
                        new File(workDir, "uq-run.log"), enginePool,
                        new MatlabFunctionRunner.ProgressCancellationSink() {
                            @Override public void onProgress(String message) { emitLog(key, message); }
                            @Override public boolean isCancellationRequested() { return false; }
                        });
                running.put(key + ":uq", runner);
                if (uqCancelPending.remove(key + ":uq") != null) {
                    runner.requestCancel();
                    throw new java.util.concurrent.CancellationException("已在启动阶段取消");
                }
                Object result = prepPayload(runner.run(), new File(adapterDir, "uq-result.json"));

                t = store.getTask(task.getProjectId(), task.getId());
                t.setUqFinishedAt(System.currentTimeMillis());
                String status = extractStatus(result);
                fresh = store.getUqRecord(record.getProjectId(), record.getId());
                fresh.setFinishedAt(System.currentTimeMillis());
                File delivery = findUqDeliveryExcel(uqOutputDir, fresh.getRunId());
                if ("failed".equals(status)) {
                    t.setUqStatus("FAILED");
                    t.setUqMessage("UQ程序返回失败,详见日志");
                    fresh.setStatus(UqRecord.ST_FAILED);
                    fresh.setMessage("UQ程序返回失败,详见日志");
                } else {
                    t.setUqStatus("COMPLETED");
                    t.setUqMessage("UQ评估完成;结果另存,不覆盖确定性估计值");
                    fresh.setStatus(UqRecord.ST_COMPLETED);
                    fresh.setMessage("UQ评估完成;结果另存,不覆盖确定性估计值");
                    fresh.setDeliveryFile(delivery != null ? delivery.getAbsolutePath() : null);
                }
                t.setUqResult(summarizeResult(result, uqOutputDir));
                store.saveTask(t);
                store.saveUqRecord(fresh);

                // 交付 Excel 关联到模型成果(02-05:一份模型可多份UQ)
                if (modelAssetId != null && !modelAssetId.isEmpty() && delivery != null) {
                    linkUqToModel(task.getProjectId(), modelAssetId, fresh.getId());
                }

                // 结果结构化:回读交付 Excel 的参数区间表(01-09)
                if (fresh.getDeliveryFile() != null) {
                    try {
                        File detail2 = readExcelDetail(task.getProjectId(), new File(fresh.getDeliveryFile()),
                                new File(uqOutputDir, fresh.getRunId() + "_dmg_uq_detail.json"));
                        if (detail2 != null && detail2.exists()) {
                            fresh = store.getUqRecord(record.getProjectId(), record.getId());
                            fresh.setDetailFile(detail2.getAbsolutePath());
                            store.saveUqRecord(fresh);
                            emitLog(key, "UQ结果明细已生成(参数区间表可浏览)");
                        }
                    } catch (Exception re) {
                        emitLog(key, "UQ结果明细生成失败(不影响评估结果): " + re.getMessage());
                    }
                }
                emitLog(key, "UQ评估结束: " + fresh.getStatus());
            } catch (java.util.concurrent.CancellationException ce) {
                // 协作取消(requestCancel):用户主动取消,不计为程序失败
                log.info("TC24 UQ被用户取消: {}", key);
                try {
                    EngineModels.ModelingTask t = store.getTask(task.getProjectId(), task.getId());
                    t.setUqStatus("FAILED");
                    t.setUqFinishedAt(System.currentTimeMillis());
                    t.setUqMessage("已手动取消评估;结果不保存,可重新发起");
                    store.saveTask(t);
                    UqRecord fresh = store.getUqRecord(record.getProjectId(), record.getId());
                    fresh.setStatus(UqRecord.ST_FAILED);
                    fresh.setFinishedAt(System.currentTimeMillis());
                    fresh.setMessage("已手动取消评估");
                    store.saveUqRecord(fresh);
                } catch (IOException io) {
                    log.error("UQ取消状态写回失败", io);
                }
                emitLog(key, "UQ评估已被用户取消");
            } catch (Exception e) {
                log.error("TC24 UQ执行失败: {}", key, e);
                try {
                    EngineModels.ModelingTask t = store.getTask(task.getProjectId(), task.getId());
                    t.setUqStatus("FAILED");
                    t.setUqFinishedAt(System.currentTimeMillis());
                    t.setUqMessage(e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage());
                    store.saveTask(t);
                    UqRecord fresh = store.getUqRecord(record.getProjectId(), record.getId());
                    fresh.setStatus(UqRecord.ST_FAILED);
                    fresh.setFinishedAt(System.currentTimeMillis());
                    fresh.setMessage("UQ评估失败: " + (e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage()));
                    store.saveUqRecord(fresh);
                } catch (IOException io) {
                    log.error("UQ状态写回失败", io);
                }
                emitLog(key, "UQ评估失败: " + e.getMessage());
            } finally {
                running.remove(key + ":uq");
                SseEmitter em = uqLogEmitters.remove(key);
                if (em != null) {
                    try { em.complete(); } catch (Exception ignore) { }
                }
            }
        });
        return record;
    }

    /**
     * UQ 交付 Excel:交付合同为 posterior_<method>.xlsx(Excel/子目录)及旧式 2p4_uq_method_*.xlsx,
     * 位置跨 {uq-output}/{runId}/Excel/ 等多层,故递归深度3按扩展名找最新。
     */
    private File findUqDeliveryExcel(File uqOutputDir, String runId) {
        try (Stream<Path> walk = Files.walk(uqOutputDir.toPath(), 3)) {
            return walk.map(Path::toFile)
                    .filter(f -> f.isFile() && f.getName().toLowerCase().endsWith(".xlsx"))
                    .max(Comparator.comparingLong(File::lastModified))
                    .orElse(null);
        } catch (IOException e) {
            log.warn("扫描UQ交付目录失败: {}", uqOutputDir, e);
            return null;
        }
    }


    /** 为UQ记录定位交付Excel:记录字段优先,缺失时从任务result摘要的delivery.workbookFile回补。 */
    public File findUqDeliveryForRecord(String projectId, EngineModels.UqRecord record) throws IOException {
        if (record.getDeliveryFile() != null && new File(record.getDeliveryFile()).isFile()) {
            return new File(record.getDeliveryFile());
        }
        EngineModels.ModelingTask task = store.getTask(projectId, record.getTaskId());
        if (task != null && task.getUqResult() != null) {
            Object delivery = task.getUqResult().get("delivery");
            if (delivery instanceof Map) {
                Object wf = ((Map<?, ?>) delivery).get("workbookFile");
                if (wf != null && new File(String.valueOf(wf)).isFile()) {
                    record.setDeliveryFile(String.valueOf(wf));
                    store.saveUqRecord(record);
                    return new File(String.valueOf(wf));
                }
            }
        }
        File dir = store.taskWorkDir(projectId, record.getTaskId());
        return findUqDeliveryExcel(new File(dir, "uq-output"), record.getRunId());
    }

    /** 把 UQ 记录 id 追加到模型成果的 uqRecordIds(去重)。 */
    private void linkUqToModel(String projectId, String modelAssetId, String uqRecordId) {
        try {
            for (EngineModels.ModelAsset a : store.listModels(projectId)) {
                if (modelAssetId.equals(a.getId())) {
                    if (a.getUqRecordIds() == null) a.setUqRecordIds(new ArrayList<>());
                    if (!a.getUqRecordIds().contains(uqRecordId)) a.getUqRecordIds().add(uqRecordId);
                    store.saveModel(a);
                    return;
                }
            }
        } catch (Exception e) {
            log.warn("UQ记录关联模型失败: {} -> {}", uqRecordId, modelAssetId, e);
        }
    }

    private String projectId0(String pid) { return pid; }

    /* ---------- TC27 稳态试车更新(kind=steady_update,F-02) ---------- */

    /**
     * TC27准备:Start_TC27_SteadyModelUpdate_01(preview=true,execute=false)只跑05数据准备,
     * 在tc27目录形成preview identity;配置并执行更新(execute=true)在同一目录复用05结果跑06。
     */
    public EngineModels.ModelingTask startTc27Prepare(EngineModels.ModelingTask task) throws IOException {
        final String key = task.getId();
        task.setStatus(EngineModels.ModelingTask.ST_PREPARING);
        task.setMessage("TC27数据准备中(05:原工况均值+新窗口+小幅段)");
        store.saveTask(task);
        logBuffers.put(key, new ArrayList<>());
        emitLog(key, "发起TC27数据准备: route=" + task.getRoute() + ", method=" + task.getUpdateMethod()
                + ", upstream=" + fileName0(task.getUpstreamModelFile()));
        executor.submit(() -> tc27Exec(task, "prepare"));
        return task;
    }

    /** TC27执行更新(execute=true,复用preview):06辨识后交付更新模型Excel。 */
    public EngineModels.ModelingTask startTc27Run(EngineModels.ModelingTask task) throws IOException {
        final String key = task.getId();
        task.setStatus(EngineModels.ModelingTask.ST_RUNNING);
        task.setMessage("TC27模型更新执行中(06稳态调度辨识)");
        task.setStartedAt(System.currentTimeMillis());
        store.saveTask(task);
        logBuffers.putIfAbsent(key, new ArrayList<>());
        emitLog(key, "发起TC27模型更新: method=" + task.getUpdateMethod());
        executor.submit(() -> tc27Exec(task, "run"));
        return task;
    }

    private void tc27Exec(EngineModels.ModelingTask task, String action) {
        final String key = task.getId();
        boolean isPrepare = "prepare".equals(action);
        try {
            File programCopy = ensureTc24Source(task.getProjectId());
            File workDir = store.taskWorkDir(task.getProjectId(), task.getId());
            // 合同目录 tc27 由程序自行创建(preview 断言目录必须不存在);适配器放 tc27-work 临时区
            File outDir = new File(workDir, "tc27");
            File adapterDir = new File(workDir, "tc27-work");
            if (!adapterDir.exists() && !adapterDir.mkdirs()) throw new IOException("无法创建TC27适配器目录");
            writeTc27Adapter(adapterDir, programCopy);

            Map<String, Object> request = new LinkedHashMap<>();
            request.put("upstreamModelFile", task.getUpstreamModelFile().replace('\\', '/'));
            request.put("steadyTrainingFile", task.getTrainingFile().replace('\\', '/'));
            request.put("trainingHistoryFile", task.getHistoryFile().replace('\\', '/'));
            request.put("testPointFiles", task.getTestFile() != null
                    ? new ArrayList<>(java.util.Collections.singletonList(
                            task.getTestFile().replace('\\', '/'))) : new ArrayList<>());
            request.put("testHistoryFiles", task.getHistoryTestFile() != null
                    ? new ArrayList<>(java.util.Collections.singletonList(
                            task.getHistoryTestFile().replace('\\', '/'))) : new ArrayList<>());
            request.put("route", task.getRoute() == null ? "steady" : task.getRoute());
            request.put("method", task.getUpdateMethod() == null ? "II" : task.getUpdateMethod());
            request.put("includeSmallHistory", task.getIncludeSmallHistory() == null || task.getIncludeSmallHistory());
            request.put("plot", false);
            request.put("runTag", task.getRunId() == null ? "WB01" : task.getRunId());
            request.put("outputDirectory", outDir.getAbsolutePath().replace('\\', '/'));
            if (isPrepare) {
                request.put("preview", true);
                request.put("execute", false);
            } else {
                request.put("preview", false);
                request.put("execute", true);
            }

            Map<String, Object> call = new LinkedHashMap<>();
            call.put("action", action);
            call.put("outputDir", outDir.getAbsolutePath().replace('\\', '/'));
            call.put("request", request);
            File resultFile = new File(adapterDir, "tc27-" + action + "-result.json");
            call.put("resultFile", resultFile.getAbsolutePath().replace('\\', '/'));
            File cf = new File(adapterDir, "tc27-" + action + "-config.json");
            com.fasterxml.jackson.databind.ObjectMapper om = new com.fasterxml.jackson.databind.ObjectMapper();
            om.configure(com.fasterxml.jackson.core.JsonGenerator.Feature.ESCAPE_NON_ASCII, true);
            Files.write(cf.toPath(), om.writeValueAsBytes(call));

            emitLog(key, isPrepare ? "调用 Start_TC27_SteadyModelUpdate_01(preview): 只跑05数据准备"
                    : "调用 Start_TC27_SteadyModelUpdate_01(execute): 06稳态调度辨识");
            MatlabFunctionRunner runner = new MatlabFunctionRunner(adapterDir, "dmg_tc27_task",
                    new Object[]{cf.getAbsolutePath()},
                    new File(workDir, "tc27-" + action + ".log"), enginePool,
                    new MatlabFunctionRunner.ProgressCancellationSink() {
                        @Override public void onProgress(String message) { emitLog(key, message); }
                        @Override public boolean isCancellationRequested() { return false; }
                    });
            running.put(key + ":tc27", runner);
            runner.run();

            Map<String, Object> result = resultFile.exists()
                    ? new com.fasterxml.jackson.databind.ObjectMapper().readValue(resultFile, Map.class)
                    : new LinkedHashMap<>();
            EngineModels.ModelingTask t = store.getTask(task.getProjectId(), task.getId());
            if (t == null) return;
            if (isPrepare) {
                t.setStatus(EngineModels.ModelingTask.ST_READY);
                t.setPrepMessage(summarizeTc27Prepared(result));
                t.setMessage("数据准备完成;可配置并执行更新");
                emitLog(key, "TC27数据准备完成");
            } else {
                File delivery = findTc27Delivery(outDir);
                t.setStatus(EngineModels.ModelingTask.ST_COMPLETED);
                t.setFinishedAt(System.currentTimeMillis());
                t.setMessage(delivery != null ? "更新完成;更新模型已交付,可登记到模型成果"
                        : "更新完成;未找到交付Excel,请检查tc27输出");
                t.setErrorKind(null);
                Map<String, Object> sum = new LinkedHashMap<>();
                sum.put("runId", result.getOrDefault("runId", ""));
                sum.put("route", result.getOrDefault("route", t.getRoute()));
                sum.put("method", result.getOrDefault("method", t.getUpdateMethod()));
                sum.put("upstreamRunId", result.getOrDefault("upstreamRunId", ""));
                sum.put("outputDirectory", outDir.getAbsolutePath());
                if (delivery != null) sum.put("deliveryWorkbookFile", delivery.getAbsolutePath());
                t.setResult(sum);
                emitLog(key, "TC27模型更新完成" + (delivery != null ? ": " + delivery.getName() : "(无交付Excel)"));
            }
            store.saveTask(t);
        } catch (Exception e) {
            log.error("TC27 {} 执行失败: {}", action, key, e);
            try {
                EngineModels.ModelingTask t = store.getTask(task.getProjectId(), task.getId());
                if (t != null) {
                    t.setStatus(isPrepare ? EngineModels.ModelingTask.ST_READY : EngineModels.ModelingTask.ST_FAILED);
                    if (!isPrepare) {
                        t.setFinishedAt(System.currentTimeMillis());
                        t.setErrorKind(EngineModels.ModelingTask.ERR_NUMERIC);
                    }
                    t.setMessage((isPrepare ? "TC27数据准备失败: " : "TC27模型更新失败: ")
                            + (e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage()));
                    store.saveTask(t);
                }
            } catch (IOException io) {
                log.error("TC27状态写回失败", io);
            }
            emitLog(key, "TC27 " + action + " 失败: " + e.getMessage());
        } finally {
            running.remove(key + ":tc27");
        }
    }

    /** 05准备摘要(展示"数据处理结果"行);程序result缺字段时回退通用描述。 */
    private String summarizeTc27Prepared(Map<String, Object> result) {
        if (result == null || result.isEmpty()) return "数据准备完成(摘要未返回,详见日志)";
        StringBuilder sb = new StringBuilder();
        Object st = result.get("status");
        if (st != null) sb.append("状态 ").append(st).append("; ");
        Object est = result.get("estimatedTime");
        if (est != null) sb.append("粗估 ").append(est).append("; ");
        Object rid = result.get("runId");
        if (rid != null) sb.append("runId ").append(rid);
        return sb.length() == 0 ? "数据准备完成" : sb.toString();
    }

    /** TC27交付Excel:更新模型工作簿,在tc27目录深度2内找最新.xlsx。 */
    private File findTc27Delivery(File outDir) {
        File best = null;
        try (Stream<Path> walk = Files.walk(outDir.toPath(), 2)) {
            best = walk.map(Path::toFile)
                    .filter(f -> f.isFile() && f.getName().toLowerCase().endsWith(".xlsx"))
                    .max(Comparator.comparingLong(File::lastModified))
                    .orElse(null);
        } catch (IOException e) {
            log.warn("扫描TC27交付目录失败: {}", outDir, e);
        }
        return best;
    }

    /** dmg_tc27_task.m:JSON request → Start_TC27_SteadyModelUpdate_01 → JSON回写(ASCII安全)。 */
    private void writeTc27Adapter(File adapterDir, File programCopy) throws IOException {
        File f = new File(adapterDir, "dmg_tc27_task.m");
        if (f.exists()) return;
        StringBuilder m = new StringBuilder();
        m.append("function r = dmg_tc27_task(configFile)\n");
        m.append("% TC27 steady-model update adapter (generated by DataModelGov)\n");
        m.append("% ASCII-only: engine charset is GBK; keep this file free of non-ASCII text.\n");
        m.append("c = jsondecode(fileread(configFile));\n");
        m.append("addpath('").append(programCopy.getAbsolutePath().replace('\\', '/')).append("', '-begin');\n");
        m.append("rehash;\n");
        m.append("req = struct();\n");
        m.append("fld = fieldnames(c.request);\n");
        m.append("for k = 1:numel(fld), req.(fld{k}) = c.request.(fld{k}); end\n");
        m.append("if ~iscell(req.testPointFiles), req.testPointFiles = {}; end\n");
        m.append("if ~iscell(req.testHistoryFiles), req.testHistoryFiles = {}; end\n");
        m.append("r = Start_TC27_SteadyModelUpdate_01(req);\n");
        m.append("r = dmg_jsonable(r);\n");
        m.append("payload = jsonencode(r);\n");
        m.append("fid = fopen(c.resultFile, 'w', 'n', 'UTF-8');\n");
        m.append("fwrite(fid, payload, 'char');\n");
        m.append("fclose(fid);\n");
        m.append("r = 'ok';\n");
        m.append("end\n");
        m.append(matlabJsonableFn());
        Files.write(f.toPath(), m.toString().getBytes(StandardCharsets.UTF_8));
    }

    private String fileName0(String p) { return p == null ? "" : new File(p).getName(); }

    /**
     * 数据准备(F-01 preview):Start_TC24_01_PreprocessPreview(route, options),
     * 真实解析训练/测试 Excel 的工况分组(clusterSpan 等),结果回填 task.conditions。
     */
    public ModelingTask runPrepare(ModelingTask task) throws IOException {
        final String key = task.getId();
        emitLog(key, "发起数据准备(task=preview)");
        executor.submit(() -> {
            try {
                File programCopy = ensureTc24Source(task.getProjectId());
                File workDir = store.taskWorkDir(task.getProjectId(), task.getId());
                File adapterDir = new File(workDir, "adapter");
                if (!adapterDir.exists() && !adapterDir.mkdirs()) throw new IOException("无法创建适配器目录");
                File prepDir = new File(workDir, "prepare");
                if (!prepDir.exists() && !prepDir.mkdirs()) throw new IOException("无法创建准备目录");
                // 程序合同禁止覆盖执行目录;同 runId 重跑时追加时间戳,旧会话保留可审计
                String prepRunId = uniqueRunId(prepDir, task.getRunId(), task);

                StringBuilder m = new StringBuilder();
                m.append("function r = dmg_tc24_task(configFile)\n");
                m.append("c = jsondecode(fileread(configFile));\n");
                m.append("addpath('").append(programCopy.getAbsolutePath().replace('\\', '/')).append("', '-begin');\n");
                m.append("rehash;\n");
                m.append("o = sht_tc24_estimation_options(c.route);\n");
                m.append("o.trainingFile = c.trainingFile;\n");
                m.append("if isfield(c,'testFile') && ~isempty(c.testFile)\n");
                m.append("    o.testFile = c.testFile;\n");
                m.append("end\n");
                m.append("o.outputDirectory = c.outputDirectory;\n");
                m.append("o.runId = c.runId;\n");
                m.append("o.plotEnabled = false;\n");
                // 先定义辅助函数，再调用
                m.append("function payload = dmg_collect_conditions(p)\n");
                m.append("    gids = cell(height(p.groups),1);\n");
                m.append("    for k = 1:height(p.groups), gids{k} = char(string(p.groups.group_id(k))); end\n");
                m.append("    ridx = p.groups.row_indices;\n");
                m.append("    if ~iscell(ridx), ridx = num2cell(ridx, 2); end\n");
                m.append("    rows = repmat(struct('id','','np',0,'ng',0,'wf',0,'samples',0,'group',''), height(p.trainingData), 1);\n");
                m.append("    for i = 1:height(p.trainingData)\n");
                m.append("        g = '';\n");
                m.append("        for k = 1:numel(ridx)\n");
                m.append("            if any(ridx{k}(:) == i), g = gids{k}; break; end\n");
                m.append("        end\n");
                m.append("        rows(i).id = dmg_tochar(p.trainingData.point_id(i));\n");
                m.append("        rows(i).np = double(p.trainingData.Np_mean(i));\n");
                m.append("        rows(i).ng = double(p.trainingData.Ng_mean(i));\n");
                m.append("        rows(i).wf = double(p.trainingData.Wf_mean(i));\n");
                m.append("        rows(i).samples = double(p.trainingData.sample_count(i));\n");
                m.append("        rows(i).group = g;\n");
                m.append("    end\n");
                m.append("    payload = jsonencode(struct('conditions', {rows}, 'groupCount', height(p.groups), ...\n");
                m.append("        'testCount', height(p.testData), 'previewFile', dmg_tochar(p.file)));\n");
                m.append("end\n");
                m.append("function s = dmg_tochar(v)\n");
                m.append("    if iscell(v), v = v{1}; end\n");
                m.append("    if isstring(v), v = char(v); end\n");
                m.append("    s = char(v);\n");
                m.append("end\n");
                // preview 结构体含 table,不能跨引擎返回;显式提取工况行为纯数值/字符串再 jsonencode
                m.append("p = Start_TC24_01_PreprocessPreview(c.route, o);\n");
                m.append("r = dmg_collect_conditions(p);\n");
                m.append("fid = fopen(c.resultFile, 'w', 'n', 'UTF-8');\n");
                m.append("fwrite(fid, jsonencode(r), 'char');\n");
                m.append("fclose(fid);\n");
                m.append("end\n");
                Files.write(new File(adapterDir, "dmg_tc24_task.m").toPath(),
                        m.toString().getBytes(StandardCharsets.UTF_8));

                Map<String, Object> cfg = new LinkedHashMap<>();
                cfg.put("route", task.getRoute() == null ? "steady" : task.getRoute());
                cfg.put("trainingFile", abs(task.getTrainingFile()));
                cfg.put("testFile", task.getTestFile() == null || task.getTestFile().isEmpty()
                        ? "" : abs(task.getTestFile()));
                cfg.put("outputDirectory", prepDir.getAbsolutePath().replace('\\', '/'));
                cfg.put("runId", prepRunId);
                cfg.put("resultFile", new File(adapterDir, "prep-result.json").getAbsolutePath().replace('\\', '/'));
                File configFile = new File(adapterDir, "prep-config.json");
                Files.write(configFile.toPath(),
                        new com.fasterxml.jackson.databind.ObjectMapper()
                                .writerWithDefaultPrettyPrinter().writeValueAsBytes(cfg));

                MatlabFunctionRunner runner = new MatlabFunctionRunner(adapterDir, "dmg_tc24_task",
                        new Object[]{configFile.getAbsolutePath()},
                        new File(workDir, "prepare.log"), enginePool,
                        new MatlabFunctionRunner.ProgressCancellationSink() {
                            @Override public void onProgress(String message) { emitLog(key, message); }
                            @Override public boolean isCancellationRequested() { return false; }
                        });
                running.put(key + ":prep", runner);
                Object result = runner.run();
                running.remove(key + ":prep");

                EngineModels.ModelingTask t = store.getTask(task.getProjectId(), task.getId());
                Object payload = prepPayload(result, new File(adapterDir, "prep-result.json"));
                applyConditions(t, payload);
                t.setStatus(EngineModels.ModelingTask.ST_READY);
                t.setPrepMessage("准备记录 PREP_01 · 数据、配置与运行包一致,可供本次辨识复用。");
                store.saveTask(t);
                emitLog(key, "数据准备完成");
            } catch (Exception e) {
                log.error("TC24 数据准备失败: {}", key, e);
                emitLog(key, "数据准备失败: " + e.getMessage());
                try {
                    EngineModels.ModelingTask t = store.getTask(task.getProjectId(), task.getId());
                    t.setStatus(EngineModels.ModelingTask.ST_READY);
                    t.setPrepMessage("数据准备失败:" + (e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage()));
                    store.saveTask(t);
                } catch (IOException io) {
                    log.error("准备状态写回失败", io);
                }
            }
        });
        return task;
    }

    /** 程序合同禁止覆盖执行目录;同 runId 重跑时追加时间戳后缀并回写任务(界面同步显示新runId)。 */
    private String uniqueRunId(File outputRoot, String runId, EngineModels.ModelingTask task) throws IOException {
        String base = runId == null || runId.trim().isEmpty() ? "WB_01" : runId.trim();
        if (!new File(outputRoot, base).exists()) return base;
        String bumped = base + '_' + new java.text.SimpleDateFormat("yyyyMMdd_HHmmss").format(new java.util.Date());
        task.setRunId(bumped);
        store.saveTask(task);
        return bumped;
    }

    /** MATLAB 局部函数:递归把 table/string 等不可跨引擎类型转为可 jsonencode 的 struct/char。 */
    private String matlabJsonableFn() {
        StringBuilder h = new StringBuilder();
        h.append("function s = dmg_jsonable(v)\n");
        h.append("if isa(v,'table')\n");
        h.append("    s = dmg_jsonable(table2struct(v));\n");
        h.append("elseif isstruct(v)\n");
        h.append("    s = v;\n");
        h.append("    f = fieldnames(s);\n");
        h.append("    for i = 1:numel(s)\n");
        h.append("        for j = 1:numel(f)\n");
        h.append("            s(i).(f{j}) = dmg_jsonable(s(i).(f{j}));\n");
        h.append("        end\n");
        h.append("    end\n");
        h.append("elseif iscell(v)\n");
        h.append("    for i = 1:numel(v), v{i} = dmg_jsonable(v{i}); end\n");
        h.append("    s = v;\n");
        h.append("elseif isstring(v)\n");
        h.append("    s = char(v);\n");
        h.append("else\n");
        h.append("    s = v;\n");
        h.append("end\n");
        h.append("end\n");
        return h.toString();
    }

    /** 引擎返回值(适配器输出的 JSON 字符串)优先;为空时回退读取 resultFile。 */
    private Object prepPayload(Object runnerResult, File resultFile) throws IOException {
        String raw = runnerResult instanceof String ? (String) runnerResult : null;
        if (raw == null || raw.trim().isEmpty()) {
            if (resultFile.exists()) {
                raw = new String(Files.readAllBytes(resultFile.toPath()), StandardCharsets.UTF_8);
            }
        }
        if (raw == null || raw.trim().isEmpty()) return null;
        return new com.fasterxml.jackson.databind.ObjectMapper().readValue(raw, Map.class);
    }

    /** 从 preview 返回结构中提取工况行(id/np/ng/wf/samples/group);结构未知时保留原始键值。 */
    @SuppressWarnings("unchecked")
    private void applyConditions(EngineModels.ModelingTask t, Object result) {
        List<Map<String, Object>> out = new ArrayList<>();
        if (result instanceof Map) {
            Object rows = ((Map<String, Object>) result).get("conditions");
            if (rows == null) rows = ((Map<String, Object>) result).get("groups");
            if (rows instanceof List) {
                for (Object o : (List<Object>) rows) {
                    if (o instanceof Map) out.add((Map<String, Object>) o);
                }
            }
        }
        t.setConditions(out);
    }

    /** 读取本次任务实际下发给程序的配置(适配器 config.json 内容)。 */
    public Map<String, Object> readConfig(String projectId, String taskId) throws IOException {
        File workDir = store.taskWorkDir(projectId, taskId);
        for (String name : new String[]{"config.json", "uq-config.json", "prep-config.json"}) {
            File f = new File(new File(workDir, "adapter"), name);
            if (f.exists()) {
                return new com.fasterxml.jackson.databind.ObjectMapper()
                        .readValue(f, Map.class);
            }
        }
        return null;
    }

    /* ---------- 内部 ---------- */

    /**
     * 输出预测(F-08:Start_TC24_00_Offline task='predict' → Start_SteadyModelPredict_01)。
     * 多工况逐条独立执行(图01-12:部分失败保留有效结果);选择UQ记录时经
     * posteriorOptions.workbookFile 做区间再传播(图01-24/02-07);异步,逐工况回写。
     */
    public EngineModels.PredictionRecord runPrediction(EngineModels.PredictionRecord rec) throws IOException {
        final String pid = rec.getProjectId();
        // 单工况兼容:老调用只填 inputs,包装为 P01
        if ((rec.getConditions() == null || rec.getConditions().isEmpty())
                && rec.getInputs() != null && !rec.getInputs().isEmpty()) {
            EngineModels.PredictionCondition c = new EngineModels.PredictionCondition();
            c.setId("P01");
            c.setInputs(rec.getInputs());
            c.setStatus("EXECUTING");
            rec.getConditions().add(c);
        }
        if (rec.getConditions() == null || rec.getConditions().isEmpty()) {
            throw new IOException("预测输入为空");
        }
        // 解析显式选择的UQ记录 → 交付 Excel(posteriorOptions.workbookFile)
        final String posteriorFile;
        if (rec.getUqRecordId() != null && !rec.getUqRecordId().isEmpty()) {
            EngineModels.UqRecord uq = store.getUqRecord(pid, rec.getUqRecordId());
            if (uq == null || uq.getDeliveryFile() == null) {
                throw new IOException("所选UQ记录不存在或尚无交付文件;区间需来自实际计算,不能移植");
            }
            posteriorFile = uq.getDeliveryFile();
        } else {
            posteriorFile = null;
        }
        for (EngineModels.PredictionCondition c : rec.getConditions()) {
            c.setStatus("EXECUTING");
        }
        rec.setStatus(EngineModels.PredictionRecord.ST_EXECUTING);
        rec.setMessage("预测执行中(0/" + rec.getConditions().size() + ")");
        store.savePrediction(rec);
        emitLog(pid, "发起输出预测(model=" + rec.getModelName() + ",工况数=" + rec.getConditions().size()
                + (posteriorFile != null ? ",含UQ区间传播" : ",确定性") + ")");

        final String uqId = rec.getUqRecordId();
        executor.submit(() -> {
            try {
                File programCopy = ensureTc24Source(pid);
                File workDir = store.taskWorkDir(pid, "predict");
                File adapterDir = new File(workDir, "adapter");
                if (!adapterDir.exists() && !adapterDir.mkdirs()) throw new IOException("无法创建适配器目录");
                String runId = "pred_" + new java.text.SimpleDateFormat("yyyyMMdd_HHmmss").format(new java.util.Date());
                rec.setRunId(runId);
                store.savePrediction(rec);

                int done = 0;
                for (EngineModels.PredictionCondition cond : rec.getConditions()) {
                    File outDir = new File(workDir, "output_" + runId + "/" + cond.getId());
                    if (!outDir.exists() && !outDir.mkdirs()) throw new IOException("无法创建预测输出目录");
                    try {
                        runSinglePrediction(programCopy, adapterDir, rec, cond, outDir, posteriorFile);
                    } catch (Exception ce) {
                        cond.setStatus("FAILED");
                        cond.setMessage("求解失败: " + (ce.getMessage() == null ? ce.getClass().getSimpleName() : ce.getMessage()));
                    }
                    cond.setFinishedAt(System.currentTimeMillis());
                    done++;
                    EngineModels.PredictionRecord fresh = findPrediction(pid, rec.getId());
                    if (fresh == null) fresh = rec;
                    fresh.setConditions(rec.getConditions());
                    fresh.setMessage("预测执行中(" + done + "/" + rec.getConditions().size() + ")");
                    store.savePrediction(fresh);
                    emitLog(pid, "工况 " + cond.getId() + " " + cond.getStatus());
                }

                EngineModels.PredictionRecord fresh = findPrediction(pid, rec.getId());
                if (fresh == null) fresh = rec;
                fresh.setRunId(runId);
                fresh.setUqRecordId(uqId);
                fresh.setFinishedAt(System.currentTimeMillis());
                long ok = rec.getConditions().stream().filter(c -> "COMPLETED".equals(c.getStatus())).count();
                if (ok == 0) {
                    fresh.setStatus(EngineModels.PredictionRecord.ST_FAILED);
                    fresh.setMessage("全部工况求解失败;详见各工况失败诊断");
                } else if (ok < rec.getConditions().size()) {
                    fresh.setStatus(EngineModels.PredictionRecord.ST_COMPLETED);
                    fresh.setMessage("已完成 " + ok + " / " + rec.getConditions().size()
                            + " 工况;失败工况保留诊断,不并入有效结果");
                } else {
                    fresh.setStatus(EngineModels.PredictionRecord.ST_COMPLETED);
                    fresh.setMessage(posteriorFile != null
                            ? "预测完成;区间来自所选UQ记录在新输入下的重新传播"
                            : "预测完成(确定性计算)");
                }
                if (!rec.getConditions().isEmpty()) {
                    fresh.setResult(rec.getConditions().get(0).getResult());
                }
                store.savePrediction(fresh);
                emitLog(pid, "输出预测结束: " + fresh.getStatus());
            } catch (Exception e) {
                log.error("输出预测失败: {}", pid, e);
                try {
                    EngineModels.PredictionRecord fresh = findPrediction(pid, rec.getId());
                    if (fresh == null) fresh = rec;
                    fresh.setStatus(EngineModels.PredictionRecord.ST_FAILED);
                    fresh.setFinishedAt(System.currentTimeMillis());
                    fresh.setMessage("预测失败: " + (e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage()));
                    store.savePrediction(fresh);
                } catch (IOException io) {
                    log.error("预测失败状态写回失败", io);
                }
                emitLog(pid, "输出预测失败: " + e.getMessage());
            }
        });
        return rec;
    }

    /** 单工况预测:生成适配器与配置,同步执行,回填工况结果与输出Excel路径。 */
    private void runSinglePrediction(File programCopy, File adapterDir, EngineModels.PredictionRecord rec,
                                     EngineModels.PredictionCondition cond, File outDir,
                                     String posteriorFile) throws Exception {
        String programPath = programCopy.getAbsolutePath().replace('\\', '/');
        String adapterName = "dmg_tc24_predict.m";
        File adapterFile = new File(adapterDir, adapterName);
        if (!adapterFile.exists()) {
            StringBuilder m = new StringBuilder();
            m.append("function r = dmg_tc24_predict(configFile)\n");
            m.append("% TC24 接入适配器(独立稳态预测;由数据与模型一体化管理软件生成)\n");
            m.append("c = jsondecode(fileread(configFile));\n");
            m.append("addpath('").append(programPath).append("', '-begin');\n");
            m.append("rehash;\n");
            m.append("o = struct('runId', c.runId, 'outputDirectory', c.outputDirectory, 'plotEnabled', false);\n");
            m.append("posterior = [];\n");
            m.append("if isfield(c,'posteriorFile') && ~isempty(c.posteriorFile)\n");
            m.append("    posterior = struct('workbookFile', c.posteriorFile);\n");
            m.append("end\n");
            m.append("cfg = struct('task', 'predict', 'modelInput', c.modelInput, 'modelFile', c.modelFile, ...\n");
            m.append("    'posterior', posterior, 'options', o);\n");
            m.append("r = Start_TC24_00_Offline(cfg);\n");
            m.append("r = dmg_jsonable(r);\n");
            m.append("payload = jsonencode(r);\n");
            m.append("fid = fopen(c.resultFile, 'w', 'n', 'UTF-8');\n");
            m.append("fwrite(fid, payload, 'char');\n");
            m.append("fclose(fid);\n");
            m.append("r = payload;\n");
            m.append("end\n");
            m.append(matlabJsonableFn());
            Files.write(adapterFile.toPath(), m.toString().getBytes(StandardCharsets.UTF_8));
        }

        String condRunId = rec.getRunId() + "_" + cond.getId();
        Map<String, Object> cfg = new LinkedHashMap<>();
        cfg.put("modelInput", cond.getInputs());
        cfg.put("modelFile", abs(rec.getModelFile()));
        if (posteriorFile != null) cfg.put("posteriorFile", abs(posteriorFile));
        cfg.put("outputDirectory", outDir.getAbsolutePath().replace('\\', '/'));
        cfg.put("runId", condRunId);
        File resultFile = new File(adapterDir, "predict-" + cond.getId() + "-result.json");
        cfg.put("resultFile", resultFile.getAbsolutePath().replace('\\', '/'));

        File configFile = new File(adapterDir, "predict-" + cond.getId() + "-config.json");
        Files.write(configFile.toPath(),
                new com.fasterxml.jackson.databind.ObjectMapper()
                        .writerWithDefaultPrettyPrinter().writeValueAsBytes(cfg));

        MatlabFunctionRunner runner = new MatlabFunctionRunner(adapterDir, "dmg_tc24_predict",
                new Object[]{configFile.getAbsolutePath()},
                new File(outDir.getParentFile(), "predict-" + cond.getId() + ".log"), enginePool,
                new MatlabFunctionRunner.ProgressCancellationSink() {
                    @Override public void onProgress(String message) { emitLog(rec.getProjectId(), message); }
                    @Override public boolean isCancellationRequested() { return false; }
                });
        Object result = runner.run();

        Object parsed = parseJsonFile(resultFile);
        String st = extractStatus(parsed instanceof Map ? parsed : result);
        Map<String, Object> summary = summarizeResult(parsed instanceof Map ? parsed : result, outDir);
        cond.setResult(summary);
        File excel = findPredictionExcel(outDir);
        if (excel != null) cond.setExcelFile(excel.getAbsolutePath());
        if (st != null && (st.contains("fail") || st.contains("error"))) {
            cond.setStatus("FAILED");
            cond.setMessage("程序返回失败状态: " + st);
        } else if ("completed_diagnostic".equalsIgnoreCase(st)) {
            cond.setStatus("COMPLETED");
            cond.setMessage("计算完成(诊断):部分输出未通过物理有效性检查,已如实标注");
        } else {
            cond.setStatus("COMPLETED");
            cond.setMessage(posteriorFile != null ? "确定性输出与区间计算完成" : "确定性计算完成");
        }
    }

    private File findPredictionExcel(File outDir) {
        File[] files = outDir.listFiles((d, n) -> n.endsWith(".xlsx"));
        if (files != null && files.length > 0) return files[0];
        File[] sub = outDir.listFiles(File::isDirectory);
        if (sub != null) {
            for (File d : sub) {
                File f = findPredictionExcel(d);
                if (f != null) return f;
            }
        }
        return null;
    }

    private EngineModels.PredictionRecord findPrediction(String pid, String id) throws IOException {
        for (EngineModels.PredictionRecord r : store.listPredictions(pid)) {
            if (id != null && id.equals(r.getId())) return r;
        }
        return null;
    }

    private Object parseJsonFile(File f) {
        if (!f.exists()) return null;
        try {
            return new com.fasterxml.jackson.databind.ObjectMapper().readValue(f, Object.class);
        } catch (IOException e) {
            log.warn("解析结果 JSON 失败: {}", f, e);
            return null;
        }
    }

    private File writeAdapterAndConfig(File adapterDir, File programCopy, EngineModels.ModelingTask task,
                                       File outputDir) throws IOException {
        String programPath = programCopy.getAbsolutePath().replace('\\', '/');

        StringBuilder m = new StringBuilder();
        m.append("function r = dmg_tc24_task(configFile)\n");
        m.append("% TC24 接入适配器(由数据与模型一体化管理软件生成;合同见 R06 手册第6章)\n");
        m.append("c = jsondecode(fileread(configFile));\n");
        m.append("addpath('").append(programPath).append("', '-begin');\n");
        m.append("rehash;\n");
        m.append("o = sht_tc24_estimation_options(c.route);\n");
        m.append("o.trainingFile = c.trainingFile;\n");
        m.append("if isfield(c,'testFile') && ~isempty(c.testFile)\n");
        m.append("    o.testFile = c.testFile;\n");
        m.append("end\n");
        m.append("o.outputDirectory = c.outputDirectory;\n");
        m.append("o.runId = c.runId;\n");
        m.append("o.plotEnabled = false;\n");
        m.append("% 协作安全停止与检查点(合同:sht_tc24_run_control);directory=完整任务目录\n");
        m.append("o.directory = c.outputDirectory;\n");
        m.append("o.enableRunControl = true;\n");
        m.append("o.resume = false;\n");
        m.append("o.timingHistoryDirectory = fullfile(c.outputDirectory, 'timing_history');\n");
        m.append("cfg = struct('task', c.task, 'route', c.route, 'options', o);\n");
        m.append("r = Start_TC24_00_Offline(cfg);\n");
        m.append("r = dmg_jsonable(r);\n");
        m.append("payload = jsonencode(r);\n");
        m.append("fid = fopen(c.resultFile, 'w', 'n', 'UTF-8');\n");
        m.append("fwrite(fid, payload, 'char');\n");
        m.append("fclose(fid);\n");
        m.append("r = payload;\n");
        m.append("end\n");
        m.append(matlabJsonableFn());
        Files.write(new File(adapterDir, "dmg_tc24_task.m").toPath(),
                m.toString().getBytes(StandardCharsets.UTF_8));

        Map<String, Object> cfg = new LinkedHashMap<>();
        cfg.put("task", "identify");
        cfg.put("route", task.getRoute() == null ? "steady" : task.getRoute());
        cfg.put("trainingFile", abs(task.getTrainingFile()));
        cfg.put("testFile", task.getTestFile() == null || task.getTestFile().isEmpty()
                ? "" : abs(task.getTestFile()));
        cfg.put("outputDirectory", outputDir.getAbsolutePath().replace('\\', '/'));
        cfg.put("runId", task.getRunId() == null || task.getRunId().isEmpty() ? "WB_01" : task.getRunId());
        cfg.put("programRoot", programPath);
        cfg.put("resultFile", new File(adapterDir, "result.json").getAbsolutePath().replace('\\', '/'));
        File configFile = new File(adapterDir, "config.json");
        Files.write(configFile.toPath(),
                new com.fasterxml.jackson.databind.ObjectMapper()
                        .writerWithDefaultPrettyPrinter().writeValueAsBytes(cfg));
        return configFile;
    }

    private String abs(String path) {
        if (path == null) return "";
        File f = new File(path);
        return f.getAbsolutePath().replace('\\', '/');
    }

    /** UQ 适配器:task='uq',options 走 sht_tc24_b_config 集中默认再覆盖业务字段;particleCount 允许 512/1024。 */
    private File writeUqAdapterAndConfig(File adapterDir, File programCopy, EngineModels.ModelingTask task,
                                         String method, String deterministicWorkbook, File uqOutputDir,
                                         Integer particleCount) throws IOException {
        String programPath = programCopy.getAbsolutePath().replace('\\', '/');

        StringBuilder m = new StringBuilder();
        m.append("function r = dmg_tc24_task(configFile)\n");
        m.append("% TC24 接入适配器(UQ;由数据与模型一体化管理软件生成;合同见 R06 手册第6章)\n");
        m.append("c = jsondecode(fileread(configFile));\n");
        m.append("addpath('").append(programPath).append("', '-begin');\n");
        m.append("rehash;\n");
        m.append("o = sht_tc24_b_config();\n");
        // sht_tc24_b_config 默认 route='transient_instant';必须覆盖为任务实际路线,
        // 否则加载确定性交付Excel时报 RouteMismatch(steady vs transient_instant)
        m.append("o.route = c.route;\n");
        m.append("if isfield(c,'particleCount') && ~isempty(c.particleCount)\n");
        m.append("    o.particleCount = double(c.particleCount);\n");
        m.append("end\n");
        m.append("o.trainingFile = c.trainingFile;\n");
        m.append("if isfield(c,'testFile') && ~isempty(c.testFile)\n");
        m.append("    o.testFile = c.testFile;\n");
        m.append("end\n");
        m.append("o.deterministicWorkbookFile = c.deterministicWorkbookFile;\n");
        m.append("o.outputDirectory = c.outputDirectory;\n");
        m.append("o.runId = c.runId;\n");
        m.append("o.plotEnabled = false;\n");
        m.append("o.progressCallback = [];\n");
        m.append("o.resume = false;\n");
        m.append("cfg = struct('task', c.task, 'method', c.method, 'options', o);\n");
        m.append("r = Start_TC24_00_Offline(cfg);\n");
        m.append("r = dmg_jsonable(r);\n");
        m.append("payload = jsonencode(r);\n");
        m.append("fid = fopen(c.resultFile, 'w', 'n', 'UTF-8');\n");
        m.append("fwrite(fid, payload, 'char');\n");
        m.append("fclose(fid);\n");
        m.append("r = payload;\n");
        m.append("end\n");
        m.append(matlabJsonableFn());
        Files.write(new File(adapterDir, "dmg_tc24_task.m").toPath(),
                m.toString().getBytes(StandardCharsets.UTF_8));

        Map<String, Object> cfg = new LinkedHashMap<>();
        cfg.put("task", "uq");
        cfg.put("method", method);
        cfg.put("route", task.getRoute() == null ? "steady" : task.getRoute());
        if (particleCount != null) cfg.put("particleCount", particleCount);
        cfg.put("trainingFile", abs(task.getTrainingFile()));
        cfg.put("testFile", task.getTestFile() == null || task.getTestFile().isEmpty()
                ? "" : abs(task.getTestFile()));
        cfg.put("deterministicWorkbookFile", abs(deterministicWorkbook));
        cfg.put("outputDirectory", uqOutputDir.getAbsolutePath().replace('\\', '/'));
        cfg.put("runId", task.getUqRunId());
        cfg.put("resultFile", new File(adapterDir, "uq-result.json").getAbsolutePath().replace('\\', '/'));
        File configFile = new File(adapterDir, "uq-config.json");
        Files.write(configFile.toPath(),
                new com.fasterxml.jackson.databind.ObjectMapper()
                        .writerWithDefaultPrettyPrinter().writeValueAsBytes(cfg));
        return configFile;
    }

    /** 从程序返回 struct(status 字段)或 result.json 摘要中提取执行状态。 */
    private String extractStatus(Object result) {
        if (result instanceof Map) {
            Object st = ((Map<?, ?>) result).get("status");
            if (st != null) return String.valueOf(st).toLowerCase();
        }
        return null;
    }

    /** 结果摘要:优先取引擎返回的 struct(转 Map),辅以扫描输出目录中的正式交付 Excel。 */
    private Map<String, Object> summarizeResult(Object result, File outputDir) {
        Map<String, Object> summary = new LinkedHashMap<>();
        if (result instanceof Map) {
            Map<?, ?> raw = (Map<?, ?>) result;
            for (Map.Entry<?, ?> e : raw.entrySet()) {
                Object v = e.getValue();
                if (v == null || v instanceof Number || v instanceof String || v instanceof Boolean) {
                    summary.put(String.valueOf(e.getKey()), v);
                } else if (v instanceof Map) {
                    // 只保留一层嵌套的标量字段(如 output/execution),避免任务文件膨胀
                    Map<String, Object> inner = new LinkedHashMap<>();
                    for (Map.Entry<?, ?> en : ((Map<?, ?>) v).entrySet()) {
                        Object iv = en.getValue();
                        if (iv == null || iv instanceof Number || iv instanceof String || iv instanceof Boolean) {
                            inner.put(String.valueOf(en.getKey()), iv);
                        }
                    }
                    if (!inner.isEmpty()) summary.put(String.valueOf(e.getKey()), inner);
                }
            }
        }
        try (Stream<Path> files = Files.list(outputDir.toPath())) {
            List<String> xlsx = files.map(f -> f.getFileName().toString())
                    .filter(n -> n.endsWith(".xlsx")).collect(Collectors.toList());
            if (!xlsx.isEmpty()) summary.put("outputFiles", xlsx);
            summary.put("outputDirectory", outputDir.getAbsolutePath());
        } catch (IOException e) {
            log.warn("扫描输出目录失败", e);
        }
        return summary;
    }

    private void emitLog(String taskId, String line) {
        MatlabLogRing.append(line);
        List<String> buf = logBuffers.get(taskId);
        if (buf == null) return;
        synchronized (buf) {
            buf.add(line);
            if (buf.size() > 200) buf.remove(0);
        }
        
        // 推送到SSE监听器
        SseEmitter emitter = uqLogEmitters.get(taskId);
        if (emitter != null) {
            try {
                emitter.send(SseEmitter.event().data(line));
            } catch (Exception e) {
                log.warn("发送UQ日志到SSE失败: {}", taskId, e);
                uqLogEmitters.remove(taskId);
                try {
                    emitter.complete();
                } catch (Exception ce) {
                    log.warn("关闭SSE发射器失败", ce);
                }
            }
        }
    }

    private static void copyRecursively(Path src, Path dest) throws IOException {
        Files.walkFileTree(src, new java.nio.file.SimpleFileVisitor<Path>() {
            @Override
            public java.nio.file.FileVisitResult preVisitDirectory(Path dir, java.nio.file.attribute.BasicFileAttributes attrs) throws IOException {
                Files.createDirectories(dest.resolve(src.relativize(dir)));
                return java.nio.file.FileVisitResult.CONTINUE;
            }

            @Override
            public java.nio.file.FileVisitResult visitFile(Path file, java.nio.file.attribute.BasicFileAttributes attrs) throws IOException {
                Files.copy(file, dest.resolve(src.relativize(file)),
                        java.nio.file.StandardCopyOption.REPLACE_EXISTING);
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
