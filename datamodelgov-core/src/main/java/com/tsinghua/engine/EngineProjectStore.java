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

    public EngineProject saveProject(EngineProject p) throws IOException {
        if (p.getId() == null || p.getId().isEmpty()) p.setId(newId());
        if (p.getCreatedAt() == null) p.setCreatedAt(System.currentTimeMillis());
        File dir = projectDir(p.getId());
        if (!dir.exists() && !dir.mkdirs()) throw new IOException("无法创建项目目录: " + dir);
        mapper.writerWithDefaultPrettyPrinter().writeValue(new File(dir, "project.json"), p);
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
}
