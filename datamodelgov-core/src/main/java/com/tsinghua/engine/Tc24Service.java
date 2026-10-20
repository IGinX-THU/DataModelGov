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
    @Value("${engine.r06.root:}")
    private String deliveryRoot;

    @Value("${engine.data.root:data/engine}")
    private String dataRoot;

    @Value("${matlab.engine.home:}")
    private String matlabHome;

    @Value("${matlab.engine.pool-size:4}")
    private int poolSize;

    @Value("${matlab.engine.enabled:true}")
    private boolean engineEnabled;

    private final EngineProjectStore store;
    private final ExecutorService executor = Executors.newFixedThreadPool(2);
    private final Map<String, MatlabFunctionRunner> running = new ConcurrentHashMap<>();
    private final Map<String, List<String>> logBuffers = new ConcurrentHashMap<>();
    private volatile MatlabEnginePool enginePool;

    public Tc24Service(EngineProjectStore store) {
        this.store = store;
    }

    @PostConstruct
    void init() {
        if (engineEnabled) {
            enginePool = new MatlabEnginePool(poolSize, matlabHome);
            log.info("TC24 接入层 MATLAB 引擎池已创建: poolSize={}", poolSize);
        } else {
            log.info("MATLAB 引擎被禁用(matlab.engine.enabled=false),TC24 任务将直接失败");
        }
    }

    private static final String R06_IN_CLASSPATH = "programs/Delivery_V1_20261019_R06/programs";

    /** 程序包相对目录(工作副本根下保持交付树 programs/ 布局,便于相对引用 C_runtime 等)。 */
    private static final String PROG_SUBPATH = "programs/m_program_adaptive_tune";

    private File runtimeRoot() {
        return new File(dataRoot, "r06-runtime/programs");
    }

    private File programWorkingCopy() {
        return new File(runtimeRoot(), "m_program_adaptive_tune");
    }

    /**
     * 解析交付树中的 m_program_adaptive_tune 源目录。
     * 顺序:显式配置 engine.r06.root → 工作区 resources(IDE 直接运行) → classpath(fat jar 内解压)。
     */
    private File resolveProgramSource() {
        if (deliveryRoot != null && !deliveryRoot.trim().isEmpty()) {
            File root = new File(deliveryRoot.trim());
            File direct = new File(root, PROG_SUBPATH);
            if (direct.isDirectory()) return direct;
            if (new File(root, "Start_TC24_00_Offline.m").isFile()) return root;
            log.warn("engine.r06.root 配置路径不含 m_program_adaptive_tune: {}", deliveryRoot);
        }
        String[] fallbacks = {
                "datamodelgov-server/src/main/resources/" + R06_IN_CLASSPATH + "/m_program_adaptive_tune",
                "src/main/resources/" + R06_IN_CLASSPATH + "/m_program_adaptive_tune",
                "target/classes/" + R06_IN_CLASSPATH + "/m_program_adaptive_tune",
                "datamodelgov-server/target/classes/" + R06_IN_CLASSPATH + "/m_program_adaptive_tune"
        };
        for (String fb : fallbacks) {
            File f = new File(fb);
            if (f.isDirectory()) return f;
        }
        return null;
    }

    /** 可写工作副本:不存在时从交付树复制,或从 classpath(fat jar)解压。 */
    private synchronized File ensureWorkingCopy() throws IOException {
        File copy = programWorkingCopy();
        File marker = new File(copy, ".working-copy-ok");
        if (marker.exists()) return copy;
        File src = resolveProgramSource();
        if (src != null) {
            log.info("复制 TC24 程序工作副本: {} -> {}", src, copy);
            if (copy.exists()) deleteRecursively(copy);
            copyRecursively(src.toPath(), copy.toPath());
        } else {
            log.info("未找到文件系统交付树,从 classpath 解压 R06 程序到工作副本: {}", copy);
            if (copy.exists()) deleteRecursively(copy);
            extractClasspathProgram(copy);
        }
        Files.write(marker.toPath(), new byte[0]);
        return copy;
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
        task.setStatus(ModelingTask.ST_PREPARING);
        task.setMessage("准备程序工作副本");
        task.setLogTail(new ArrayList<>());
        store.saveTask(task);
        logBuffers.put(key, new ArrayList<>());

        executor.submit(() -> {
            MatlabFunctionRunner runner = null;
            try {
                File programCopy = ensureWorkingCopy();
                File workDir = store.taskWorkDir(task.getProjectId(), task.getId());
                File adapterDir = new File(workDir, "adapter");
                if (!adapterDir.exists() && !adapterDir.mkdirs()) throw new IOException("无法创建适配器目录");
                File outputDir = new File(workDir, "output");
                if (!outputDir.exists() && !outputDir.mkdirs()) throw new IOException("无法创建输出目录");
                // 同 runId 重跑(重试/重新辨识)时追加时间戳,避免合同拒绝覆盖旧执行目录
                uniqueRunId(outputDir, task.getRunId(), task);
                File configFile = writeAdapterAndConfig(adapterDir, programCopy, task, outputDir);

                EngineModels.ModelingTask t = store.getTask(task.getProjectId(), task.getId());
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
                    emitLog(key, "程序返回失败");
                } else {
                    t.setStatus(ModelingTask.ST_COMPLETED);
                    t.setMessage("辨识完成");
                    emitLog(key, "任务完成");
                }
                t.setResult(summarizeResult(result, outputDir));
                store.saveTask(t);
            } catch (Exception e) {
                log.error("TC24 任务执行失败: {}", key, e);
                try {
                    EngineModels.ModelingTask t = store.getTask(task.getProjectId(), task.getId());
                    t.setStatus(ModelingTask.ST_FAILED);
                    t.setFinishedAt(System.currentTimeMillis());
                    t.setMessage(e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage());
                    store.saveTask(t);
                } catch (IOException io) {
                    log.error("任务状态写回失败", io);
                }
                emitLog(key, "任务失败: " + e.getMessage());
            } finally {
                running.remove(key);
            }
        });
        return task;
    }

    /**
     * 请求停止(合同路径):通过引擎调用 Start_TC24_00_Offline(task='stop'),
     * 由 sht_tc24_run_control 在 {outputDirectory}/run_control/ 落 stop_request,
     * 运行中的辨识在最近安全点保存检查点后结束;不强制中断引擎。
     */
    public boolean requestStop(String projectId, String taskId) {
        try {
            EngineModels.ModelingTask t = store.getTask(projectId, taskId);
            if (t == null || running.get(taskId) == null) return false;
            t.setStatus(ModelingTask.ST_STOP_REQUESTED);
            t.setMessage("已请求停止;等待程序到达安全点");
            store.saveTask(t);
            emitLog(taskId, "已提交安全停止请求(task=stop)");
        } catch (IOException e) {
            log.warn("停止状态写回失败", e);
            return false;
        }
        executor.submit(() -> {
            try {
                File workDir = store.taskWorkDir(projectId, taskId);
                File outputDir = new File(workDir, "output");
                File programCopy = ensureWorkingCopy();
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
                        new File(workDir, "stop.log"), enginePool);
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
     * 可选UQ评估(F-07-TC24):Start_TC24_00_Offline(task='uq',method=B|C|D),
     * options 走 sht_tc24_b_config 集中默认;runId 带 tc24_ 前缀(合同要求);
     * 结果另存 uq-output,不覆盖确定性辨识结果。
     */
    public ModelingTask runUq(ModelingTask task, String method, String deterministicWorkbook) throws IOException {
        final String key = task.getId();
        task.setUqStatus("PREPARING");
        task.setUqMessage("准备UQ程序工作副本");
        String ts = new java.text.SimpleDateFormat("yyyyMMdd_HHmmss").format(new java.util.Date());
        task.setUqRunId("tc24_" + method.toLowerCase() + "_" + ts);
        store.saveTask(task);
        emitLog(key, "发起UQ评估: method=" + method + ", runId=" + task.getUqRunId());

        final String m = method;
        executor.submit(() -> {
            MatlabFunctionRunner runner = null;
            try {
                File programCopy = ensureWorkingCopy();
                File workDir = store.taskWorkDir(task.getProjectId(), task.getId());
                File adapterDir = new File(workDir, "adapter");
                if (!adapterDir.exists() && !adapterDir.mkdirs()) throw new IOException("无法创建适配器目录");
                File uqOutputDir = new File(workDir, "uq-output");
                if (!uqOutputDir.exists() && !uqOutputDir.mkdirs()) throw new IOException("无法创建UQ输出目录");
                File configFile = writeUqAdapterAndConfig(adapterDir, programCopy, task, m, deterministicWorkbook, uqOutputDir);

                EngineModels.ModelingTask t = store.getTask(task.getProjectId(), task.getId());
                t.setUqStatus("EXECUTING");
                t.setUqMessage("UQ 评估执行中(方法 " + m + ")");
                t.setUqStartedAt(System.currentTimeMillis());
                store.saveTask(t);
                emitLog(key, "调用 Start_TC24_00_Offline, task=uq, method=" + m);

                runner = new MatlabFunctionRunner(adapterDir, "dmg_tc24_task",
                        new Object[]{configFile.getAbsolutePath()},
                        new File(workDir, "uq-run.log"), enginePool,
                        new MatlabFunctionRunner.ProgressCancellationSink() {
                            @Override public void onProgress(String message) { emitLog(key, message); }
                            @Override public boolean isCancellationRequested() { return false; }
                        });
                running.put(key + ":uq", runner);
                Object result = prepPayload(runner.run(), new File(adapterDir, "uq-result.json"));

                t = store.getTask(task.getProjectId(), task.getId());
                t.setUqFinishedAt(System.currentTimeMillis());
                String status = extractStatus(result);
                if ("failed".equals(status)) {
                    t.setUqStatus("FAILED");
                    t.setUqMessage("UQ程序返回失败,详见日志");
                } else {
                    t.setUqStatus("COMPLETED");
                    t.setUqMessage("UQ评估完成;结果另存,不覆盖确定性估计值");
                }
                t.setUqResult(summarizeResult(result, uqOutputDir));
                store.saveTask(t);
                emitLog(key, "UQ评估结束: " + t.getUqStatus());
            } catch (Exception e) {
                log.error("TC24 UQ执行失败: {}", key, e);
                try {
                    EngineModels.ModelingTask t = store.getTask(task.getProjectId(), task.getId());
                    t.setUqStatus("FAILED");
                    t.setUqFinishedAt(System.currentTimeMillis());
                    t.setUqMessage(e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage());
                    store.saveTask(t);
                } catch (IOException io) {
                    log.error("UQ状态写回失败", io);
                }
                emitLog(key, "UQ评估失败: " + e.getMessage());
            } finally {
                running.remove(key + ":uq");
            }
        });
        return task;
    }

    /**
     * 数据准备(F-01 preview):Start_TC24_01_PreprocessPreview(route, options),
     * 真实解析训练/测试 Excel 的工况分组(clusterSpan 等),结果回填 task.conditions。
     */
    public ModelingTask runPrepare(ModelingTask task) throws IOException {
        final String key = task.getId();
        emitLog(key, "发起数据准备(task=preview)");
        executor.submit(() -> {
            try {
                File programCopy = ensureWorkingCopy();
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
                        new File(workDir, "prepare.log"), enginePool);
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

    /** UQ 适配器:task='uq',options 走 sht_tc24_b_config 集中默认再覆盖业务字段。 */
    private File writeUqAdapterAndConfig(File adapterDir, File programCopy, EngineModels.ModelingTask task,
                                         String method, String deterministicWorkbook, File uqOutputDir) throws IOException {
        String programPath = programCopy.getAbsolutePath().replace('\\', '/');

        StringBuilder m = new StringBuilder();
        m.append("function r = dmg_tc24_task(configFile)\n");
        m.append("% TC24 接入适配器(UQ;由数据与模型一体化管理软件生成;合同见 R06 手册第6章)\n");
        m.append("c = jsondecode(fileread(configFile));\n");
        m.append("addpath('").append(programPath).append("', '-begin');\n");
        m.append("rehash;\n");
        m.append("o = sht_tc24_b_config();\n");
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
        List<String> buf = logBuffers.get(taskId);
        if (buf == null) return;
        synchronized (buf) {
            buf.add(line);
            if (buf.size() > 200) buf.remove(0);
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
