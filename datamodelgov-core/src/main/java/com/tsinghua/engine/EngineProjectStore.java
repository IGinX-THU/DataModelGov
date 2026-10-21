package com.tsinghua.engine;

import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.annotation.PostConstruct;
import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;

import com.tsinghua.engine.EngineModels.EngineProject;
import com.tsinghua.engine.EngineModels.ModelAsset;
import com.tsinghua.engine.EngineModels.ModelingTask;
import com.tsinghua.engine.EngineModels.PredictionRecord;
import com.tsinghua.engine.EngineModels.UqRecord;

/**
 * 工作台域模型文件存储:
 *   {dataRoot}/projects/{pid}/project.json
 *   {dataRoot}/projects/{pid}/tasks/{tid}/task.json   (+ input/ output/ adapter/)
 *   {dataRoot}/projects/{pid}/models/{mid}.json
 * 小规模元数据直接落盘,模型大对象(Excel/MAT)按手册合同成套保存为文件。
 */
@Slf4j
@Service
public class EngineProjectStore {

    @Value("${engine.data.root:data/engine}")
    private String dataRoot;

    private final ObjectMapper mapper = new ObjectMapper()
            .configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);

    private File root;

    @PostConstruct
    void init() {
        root = new File(dataRoot);
        if (!root.exists() && root.mkdirs()) {
            log.info("工作台数据目录已创建: {}", root.getAbsolutePath());
        }
    }

    public File root() {
        return root;
    }

    private static String newId() {
        return UUID.randomUUID().toString().replace("-", "").substring(0, 12);
    }

    /* ---------- 项目 ---------- */

    public File projectDir(String projectId) {
        return new File(root, "projects/" + projectId);
    }

    /**
     * 解析项目工作目录(与旧版 ProgramService 同根):
     * - 留空 → 系统生成 `project/<项目名>`(相对服务工作目录,旧版 TASK_BASE_DIR 同名);
     * - 相对路径(如 myproj/job)→ 相对服务工作目录解析;
     * - 绝对路径 → 原样使用。
     * 解析结果写入 workdir 字段回显;元数据(project.json/task.json/models)仍在 dataRoot,
     * 大文件(任务输入/输出/日志)按旧版布局落 `<workdir>/job/program-tasks/<taskId>`。
     */
    private String resolveWorkdir(EngineProject p) {
        String loc = p.getLocation();
        File dir;
        if (loc != null && !loc.trim().isEmpty()) {
            dir = new File(loc.trim());
        } else {
            dir = new File("project", safeName(p.getName()));
        }
        if (!dir.exists() && !dir.mkdirs()) {
            log.warn("保存位置不可创建,回退默认工作目录: {}", dir);
            dir = new File("project", safeName(p.getId()));
            if (!dir.exists() && !dir.mkdirs()) throw new IllegalStateException("默认工作目录创建失败");
        }
        return dir.getAbsolutePath();
    }

    /** 目录名安全化:去掉路径分隔与非法字符,空则回退 id。 */
    private static String safeName(String name) {
        String s = name == null ? "" : name.trim();
        s = s.replaceAll("[\\\\/:*?\"<>|]", "_");
        if (s.isEmpty() || s.equals(".")) s = "unnamed";
        return s;
    }

    public EngineProject saveProject(EngineProject p) throws IOException {
        // 项目 id 与 IginX 元数据表主键对齐:时间戳(字符串形式承载)
        if (p.getId() == null || p.getId().isEmpty()) p.setId(String.valueOf(System.currentTimeMillis()));
        if (p.getCreatedAt() == null) p.setCreatedAt(System.currentTimeMillis());
        File dir = projectDir(p.getId());
        if (!dir.exists() && !dir.mkdirs()) throw new IOException("无法创建项目目录: " + dir);
        p.setWorkdir(resolveWorkdir(p));
        mapper.writerWithDefaultPrettyPrinter().writeValue(new File(dir, "project.json"), p);
        log.info("项目工作目录已就绪: {} -> {}", p.getName(), p.getWorkdir());
        return p;
    }

    public EngineProject getProject(String projectId) throws IOException {
        File f = new File(projectDir(projectId), "project.json");
        if (!f.exists()) return null;
        return mapper.readValue(f, EngineProject.class);
    }

    public List<EngineProject> listProjects() throws IOException {
        List<EngineProject> out = new ArrayList<>();
        File projects = new File(root, "projects");
        File[] dirs = projects.listFiles(File::isDirectory);
        if (dirs == null) return out;
        for (File d : dirs) {
            try {
                EngineProject p = getProject(d.getName());
                if (p != null) out.add(p);
            } catch (Exception e) {
                log.warn("读取项目失败: {}", d.getName(), e);
            }
        }
        out.sort(Comparator.comparing(EngineProject::getCreatedAt, Comparator.nullsLast(Comparator.reverseOrder())));
        return out;
    }

    /* ---------- 任务 ---------- */

    public File taskDir(String projectId, String taskId) {
        return new File(projectDir(projectId), "tasks/" + taskId);
    }

    /**
     * 任务大文件工作目录:与旧版 ProgramService 布局一致,
     * `<项目工作目录>/job/program-tasks/<taskId>`;无项目时回退元数据目录。
     */
    public File taskWorkDir(String projectId, String taskId) {
        try {
            EngineProject p = getProject(projectId);
            if (p != null && p.getWorkdir() != null && !p.getWorkdir().isEmpty()) {
                return new File(new File(new File(p.getWorkdir()), "job"), "program-tasks/" + taskId);
            }
        } catch (IOException e) {
            log.warn("读取项目工作目录失败,回退默认: {}", projectId);
        }
        return taskDir(projectId, taskId);
    }

    /* ---------- 多系统联合仿真(AFO_V_2 会话) ---------- */

    /**
     * AFO会话大文件工作目录(扁平,项目工作目录下一级):
     * `<项目工作目录>/afo/<runId>`(status.json/inbox/runtime/result.json/交付Excel);
     * 无项目或工作目录缺失时回退元数据目录 projects/{pid}/afo-work/<runId>。
     */
    public File afoWorkDir(String projectId, String runId) {
        try {
            EngineProject p = getProject(projectId);
            if (p != null && p.getWorkdir() != null && !p.getWorkdir().isEmpty()) {
                return new File(new File(p.getWorkdir()), "afo/" + runId);
            }
        } catch (IOException e) {
            log.warn("读取项目工作目录失败,AFO会话回退元数据目录: {}", projectId);
        }
        return new File(new File(projectDir(projectId), "afo-work"), runId);
    }

    /** AFO会话元数据文件(projects/{pid}/afo/{runId}.json),与 predictions/uq 同模式。 */
    public File afoSessionFile(String projectId, String runId) {
        return new File(projectDir(projectId), "afo/" + runId + ".json");
    }

    public File afoSessionDir(String projectId) {
        return new File(projectDir(projectId), "afo");
    }

    public ModelingTask saveTask(ModelingTask t) throws IOException {
        if (t.getId() == null || t.getId().isEmpty()) {
            t.setId(newId());
            t.setCreatedAt(System.currentTimeMillis());
        }
        File dir = taskDir(t.getProjectId(), t.getId());
        if (!dir.exists() && !dir.mkdirs()) throw new IOException("无法创建任务目录: " + dir);
        mapper.writerWithDefaultPrettyPrinter().writeValue(new File(dir, "task.json"), t);
        return t;
    }

    public ModelingTask getTask(String projectId, String taskId) throws IOException {
        File f = new File(taskDir(projectId, taskId), "task.json");
        if (!f.exists()) return null;
        return mapper.readValue(f, ModelingTask.class);
    }

    public List<ModelingTask> listTasks(String projectId) throws IOException {
        List<ModelingTask> out = new ArrayList<>();
        File tasks = new File(projectDir(projectId), "tasks");
        File[] dirs = tasks.listFiles(File::isDirectory);
        if (dirs == null) return out;
        for (File d : dirs) {
            try {
                ModelingTask t = getTask(projectId, d.getName());
                if (t != null) out.add(t);
            } catch (Exception e) {
                log.warn("读取任务失败: {}", d.getName(), e);
            }
        }
        out.sort(Comparator.comparing(ModelingTask::getCreatedAt, Comparator.nullsLast(Comparator.reverseOrder())));
        return out;
    }

    /* ---------- 模型成果 ---------- */

    public File modelFile(String projectId, String modelId) {
        return new File(projectDir(projectId), "models/" + modelId + ".json");
    }

    public ModelAsset saveModel(ModelAsset m) throws IOException {
        if (m.getId() == null || m.getId().isEmpty()) m.setId(newId());
        if (m.getCreatedAt() == null) m.setCreatedAt(System.currentTimeMillis());
        File dir = new File(projectDir(m.getProjectId()), "models");
        if (!dir.exists() && !dir.mkdirs()) throw new IOException("无法创建模型目录: " + dir);
        mapper.writerWithDefaultPrettyPrinter().writeValue(modelFile(m.getProjectId(), m.getId()), m);
        return m;
    }

    public List<ModelAsset> listModels(String projectId) throws IOException {
        List<ModelAsset> out = new ArrayList<>();
        File models = new File(projectDir(projectId), "models");
        File[] files = models.listFiles((d, n) -> n.endsWith(".json"));
        if (files == null) return out;
        for (File f : files) {
            try {
                out.add(mapper.readValue(f, ModelAsset.class));
            } catch (Exception e) {
                log.warn("读取模型成果失败: {}", f.getName(), e);
            }
        }
        out.sort(Comparator.comparing(ModelAsset::getCreatedAt, Comparator.nullsLast(Comparator.reverseOrder())));
        return out;
    }

    /* ---------- 输出预测记录 ---------- */

    public PredictionRecord savePrediction(PredictionRecord r) throws IOException {
        if (r.getId() == null || r.getId().isEmpty()) {
            r.setId(newId());
            r.setCreatedAt(System.currentTimeMillis());
        }
        File dir = new File(projectDir(r.getProjectId()), "predictions");
        if (!dir.exists() && !dir.mkdirs()) throw new IOException("无法创建预测目录: " + dir);
        mapper.writerWithDefaultPrettyPrinter().writeValue(new File(dir, r.getId() + ".json"), r);
        return r;
    }

    public List<PredictionRecord> listPredictions(String projectId) throws IOException {
        List<PredictionRecord> out = new ArrayList<>();
        File dir = new File(projectDir(projectId), "predictions");
        File[] files = dir.listFiles((d, n) -> n.endsWith(".json"));
        if (files == null) return out;
        for (File f : files) {
            try {
                out.add(mapper.readValue(f, PredictionRecord.class));
            } catch (Exception e) {
                log.warn("读取预测记录失败: {}", f.getName(), e);
            }
        }
        out.sort(Comparator.comparing(PredictionRecord::getCreatedAt, Comparator.nullsLast(Comparator.reverseOrder())));
        return out;
    }

    /* ---------- UQ评估记录(F-07) ---------- */

    public UqRecord saveUqRecord(UqRecord r) throws IOException {
        if (r.getId() == null || r.getId().isEmpty()) {
            r.setId(newId());
            if (r.getStartedAt() == null) r.setStartedAt(System.currentTimeMillis());
        }
        File dir = new File(projectDir(r.getProjectId()), "uq");
        if (!dir.exists() && !dir.mkdirs()) throw new IOException("无法创建UQ记录目录: " + dir);
        mapper.writerWithDefaultPrettyPrinter().writeValue(new File(dir, r.getId() + ".json"), r);
        return r;
    }

    public List<UqRecord> listUqRecords(String projectId) throws IOException {
        List<UqRecord> out = new ArrayList<>();
        File dir = new File(projectDir(projectId), "uq");
        File[] files = dir.listFiles((d, n) -> n.endsWith(".json"));
        if (files == null) return out;
        for (File f : files) {
            try {
                out.add(mapper.readValue(f, UqRecord.class));
            } catch (Exception e) {
                log.warn("读取UQ记录失败: {}", f.getName(), e);
            }
        }
        out.sort(Comparator.comparing(UqRecord::getStartedAt, Comparator.nullsLast(Comparator.reverseOrder())));
        return out;
    }

    public UqRecord getUqRecord(String projectId, String uqId) throws IOException {
        File f = new File(projectDir(projectId), "uq/" + uqId + ".json");
        if (!f.exists()) return null;
        return mapper.readValue(f, UqRecord.class);
    }
}
