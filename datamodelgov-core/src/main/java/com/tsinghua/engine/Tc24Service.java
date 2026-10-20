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

    @Value("${engine.r06.root:program/Delivery_V1_20261019_R06/程序}")
    private String deliveryRoot;

    @Value("${engine.data.root:data/engine}")
    private String dataRoot;

    @Value("${matlab.engine.home:}")
    private String matlabHome;

    @Value("${engine.matlab.pool-size:1}")
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

    private File programSource() {
        return new File(deliveryRoot, "programs/m_program_adaptive_tune");
    }

    private File programWorkingCopy() {
        return new File(dataRoot, "r06-runtime/m_program_adaptive_tune");
    }

    /** 可写工作副本:不存在时从交付包复制(35MB 级,秒级完成)。 */
    private synchronized File ensureWorkingCopy() throws IOException {
        File copy = programWorkingCopy();
        File marker = new File(copy, ".working-copy-ok");
        if (marker.exists()) return copy;
        File src = programSource();
        if (!src.isDirectory()) throw new IOException("R06 程序目录不存在: " + src.getAbsolutePath());
        log.info("复制 TC24 程序工作副本: {} -> {}", src, copy);
        if (copy.exists()) deleteRecursively(copy);
        copyRecursively(src.toPath(), copy.toPath());
        Files.write(marker.toPath(), new byte[0]);
        return copy;
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
        File taskDir = store.taskDir(task.getProjectId(), task.getId());
        File outputDir = new File(taskDir, "output");
        if (!outputDir.exists() && !outputDir.mkdirs()) throw new IOException("无法创建输出目录");

        executor.submit(() -> {
            MatlabFunctionRunner runner = null;
            try {
                File programCopy = ensureWorkingCopy();
                File adapterDir = new File(taskDir, "adapter");
                if (!adapterDir.exists() && !adapterDir.mkdirs()) throw new IOException("无法创建适配器目录");
                File configFile = writeAdapterAndConfig(adapterDir, programCopy, task, outputDir);

                EngineModels.ModelingTask t = store.getTask(task.getProjectId(), task.getId());
                t.setStatus(ModelingTask.ST_RUNNING);
                t.setStartedAt(System.currentTimeMillis());
                t.setMessage("MATLAB 辨识执行中");
                store.saveTask(t);
                emitLog(key, "调用 Start_TC24_00_Offline, route=" + task.getRoute());

                runner = new MatlabFunctionRunner(adapterDir, "dmg_tc24_task",
                        new Object[]{configFile.getAbsolutePath()},
                        new File(taskDir, "run.log"), enginePool,
                        new MatlabFunctionRunner.ProgressCancellationSink() {
                            @Override
                            public void onProgress(String message) {
                                emitLog(key, message);
                            }

                            @Override
                            public boolean isCancellationRequested() {
                                // 取消由 stop 接口直接调用 runner.requestCancel(),此桥不反向查询
                                return false;
                            }
                        });
                running.put(key, runner);
                Object result = runner.run();

                t = store.getTask(task.getProjectId(), task.getId());
                t.setStatus(ModelingTask.ST_COMPLETED);
                t.setFinishedAt(System.currentTimeMillis());
                t.setMessage("辨识完成");
                t.setResult(summarizeResult(result, outputDir));
                store.saveTask(t);
                emitLog(key, "任务完成");
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

    /** 请求停止(协作式:TC24 经 sht_tc24_run_control 落 stop_requested,由程序在安全点结束)。 */
    public boolean requestStop(String projectId, String taskId) {
        MatlabFunctionRunner runner = running.get(taskId);
        if (runner == null) return false;
        runner.requestCancel();
        try {
            EngineModels.ModelingTask t = store.getTask(projectId, taskId);
            if (t != null && ModelingTask.ST_RUNNING.equals(t.getStatus())) {
                t.setStatus(ModelingTask.ST_STOP_REQUESTED);
                t.setMessage("已请求停止;等待程序到达安全点");
                store.saveTask(t);
            }
        } catch (IOException e) {
            log.warn("停止状态写回失败", e);
        }
        return true;
    }

    public List<String> logTail(String taskId) {
        List<String> buf = logBuffers.get(taskId);
        return buf == null ? new ArrayList<>() : new ArrayList<>(buf);
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
        m.append("cfg = struct('task', c.task, 'route', c.route, 'options', o);\n");
        m.append("r = Start_TC24_00_Offline(cfg);\n");
        m.append("try\n");
        m.append("    fid = fopen(c.resultFile, 'w');\n");
        m.append("    fwrite(fid, jsonencode(r), 'utf-8');\n");
        m.append("    fclose(fid);\n");
        m.append("catch\n");
        m.append("end\n");
        m.append("end\n");
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
