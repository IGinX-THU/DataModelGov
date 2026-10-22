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
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;

import com.tsinghua.entity.EngineProjectEntity;
import com.tsinghua.engine.EngineModels.EngineProject;
import com.tsinghua.engine.EngineModels.ModelAsset;
import com.tsinghua.engine.EngineModels.ModelingTask;
import com.tsinghua.engine.EngineModels.PredictionRecord;
import com.tsinghua.engine.EngineModels.UqRecord;

/**
 * 工作台域模型存储(元数据入IginX+工作目录,运行大文件在工作目录):
 *   IginX relational_system.engine_projects   项目主数据(列表/同名校验/owner隔离/workdir反查)
 *   <workdir>/job/meta/                       明细元数据(project.json/tasks/models/uq/predictions/afo)
 *   <workdir>/job/program-tasks/<taskId>/     建模任务运行数据(input/output/adapter/日志)
 *   <workdir>/job/afo/<runId>/                多系统仿真会话数据
 *   <workdir>/program/<程序名>/               程序源(创建项目时预置,实际运行用)
 */
@Slf4j
@Service
public class EngineProjectStore {

    @org.springframework.beans.factory.annotation.Autowired
    private EngineProjectMetaService metaService;

    private final ObjectMapper mapper = new ObjectMapper()
            .configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);

    private static String newId() {
        return UUID.randomUUID().toString().replace("-", "").substring(0, 12);
    }

    /* ---------- 项目 ---------- */

    /** 项目元数据目录:<workdir>/job/meta(workdir由IginX项目主数据反查;IginX为硬依赖)。 */
    public File projectDir(String projectId) throws IOException {
        EngineProject p = getProject(projectId);
        if (p == null || p.getWorkdir() == null || p.getWorkdir().isEmpty()) {
            throw new IOException("项目不存在或工作目录未配置: " + projectId);
        }
        return new File(new File(new File(p.getWorkdir()), "job"), "meta");
    }

    /**
     * 解析项目工作目录(与旧版 ProgramService 同根):
     * - 留空 → 系统生成 `project/<项目名>`(相对服务工作目录,旧版 TASK_BASE_DIR 同名);
     * - 相对路径(如 myproj/job)→ 相对服务工作目录解析;
     * - 绝对路径 → 原样使用。
     * 解析结果写入 workdir 字段回显;元数据(tasks/models等)入IginX,
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
        p.setWorkdir(resolveWorkdir(p));
        // 工作目录防覆盖:目录已存在且非空时拒绝创建(项目目录专属,删除项目即删整个目录)
        File wd = new File(p.getWorkdir());
        String[] existingFiles = wd.exists() ? wd.list() : null;
        if (existingFiles != null && existingFiles.length > 0) {
            throw new IOException("保存位置已存在内容: " + wd.getAbsolutePath() + ",请更换保存位置");
        }
        if (!wd.exists() && !wd.mkdirs()) throw new IOException("无法创建项目工作目录: " + wd);
        // IginX 行先落:此后 projectDir 反查 workdir 才可达,元数据才写得到工作目录
        try {
            metaService.save(new EngineProjectEntity()
                    .setId(Long.parseLong(p.getId()))
                    .setName(p.getName())
                    .setType(p.getType())
                    .setEngineId(p.getEngineId())
                    .setLocation(p.getLocation())
                    .setWorkdir(p.getWorkdir())
                    .setDesc(p.getDesc())
                    .setOwner(p.getOwner())
                    .setCreateTime(p.getCreatedAt()));
        } catch (Exception e) {
            log.error("项目主数据写入IginX失败: {}", p.getName(), e);
            throw new IOException("项目主数据写入失败: " + e.getMessage());
        }
        File dir = projectDir(p.getId());
        if (!dir.exists() && !dir.mkdirs()) throw new IOException("无法创建项目元数据目录: " + dir);
        mapper.writerWithDefaultPrettyPrinter().writeValue(new File(dir, "project.json"), p);
        log.info("项目工作目录已就绪: {} -> {}", p.getName(), p.getWorkdir());
        return p;
    }

    /** 项目档案唯一来源:IginX engine_projects 主数据(列表/详情/运行定位统一走这里)。 */
    public EngineProject getProject(String projectId) throws IOException {
        return getProject(projectId, null);
    }

    /** 带 名称兜底 的项目查询(删除等场景由前端一并传名)。 */
    public EngineProject getProject(String projectId, String nameFallback) throws IOException {
        com.tsinghua.entity.EngineProjectEntity e;
        try {
            e = metaService.queryById(Long.parseLong(projectId));
            if (e == null && nameFallback != null && !nameFallback.trim().isEmpty()) {
                e = metaService.queryByName(nameFallback.trim());
            }
            if (e == null) return null;
            EngineProject p = new EngineProject();
            p.setId(e.getId() == null ? projectId : String.valueOf(e.getId()));
            p.setName(e.getName());
            p.setType(e.getType());
            p.setEngineId(e.getEngineId());
            p.setLocation(e.getLocation());
            p.setWorkdir(e.getWorkdir());
            p.setDesc(e.getDesc());
            p.setOwner(e.getOwner());
            p.setCreatedAt(e.getCreateTime());
            return p;
        } catch (NumberFormatException nfe) {
            return null;
        }
    }

    /** IginX engine_projects 行 → EngineProject(主数据字段;明细仍在工作目录/旧文件位置)。 */
    private EngineProject fromIginxMeta(String projectId) {
        try {
            com.tsinghua.entity.EngineProjectEntity e =
                    metaService.queryById(Long.parseLong(projectId));
            if (e == null) return null;
            EngineProject p = new EngineProject();
            p.setId(e.getId() == null ? projectId : String.valueOf(e.getId()));
            p.setName(e.getName());
            p.setType(e.getType());
            p.setEngineId(e.getEngineId());
            p.setLocation(e.getLocation());
            p.setWorkdir(e.getWorkdir());
            p.setDesc(e.getDesc());
            p.setOwner(e.getOwner());
            p.setCreatedAt(e.getCreateTime());
            return p;
        } catch (Exception e2) {
            log.warn("IginX项目主数据查询失败: {}", projectId, e2);
            return null;
        }
    }

    /**
     * 删除项目:元数据目录(projects/{pid},含tasks/models/predictions/uq/afo)整体删除;
     * 用户工作目录仅清除本系统写入的部分(workdir/afo、workdir/job、project.json标记),
     * 目录空则一并移除——用户在保存位置放的其他文件不动。
     */
    public void deleteProject(String projectId) throws IOException {
        EngineProject p = getProject(projectId);
        // 工作目录即项目专属目录(系统为项目生成/用户指定):整个删除
        if (p != null && p.getWorkdir() != null && !p.getWorkdir().isEmpty()) {
            File wd = new File(p.getWorkdir());
            if (wd.exists()) deleteRecursively(wd);
        }
    }

    private void deleteRecursively(File f) throws IOException {
        if (!f.exists()) return;
        java.nio.file.Files.walk(f.toPath())
                .sorted(java.util.Comparator.reverseOrder())
                .map(Path::toFile)
                .forEach(File::delete);
    }

    /** 项目列表:唯一来源为IginX主数据(与列表分页/owner隔离同口径)。 */
    public List<EngineProject> listProjects() throws IOException {
        List<EngineProject> out = new ArrayList<>();
        for (com.tsinghua.entity.EngineProjectEntity e : metaService.queryList(null, 1, 500)) {
            try {
                EngineProject proj = fromIginxMeta(String.valueOf(e.getId()));
                if (proj != null) out.add(proj);
            } catch (Exception ex) {
                log.warn("读取项目失败: {}", e.getId(), ex);
            }
        }
        out.sort(Comparator.comparing(EngineProject::getCreatedAt, Comparator.nullsLast(Comparator.reverseOrder())));
        return out;
    }

    /* ---------- 任务 ---------- */

    public File taskDir(String projectId, String taskId) throws IOException {
        return new File(projectDir(projectId), "tasks/" + taskId);
    }

    /**
     * 任务大文件工作目录:与旧版 ProgramService 布局一致,
     * `<项目工作目录>/job/program-tasks/<taskId>`;无项目时回退元数据目录。
     */
    public File taskWorkDir(String projectId, String taskId) throws IOException {
        EngineProject p = getProject(projectId);
        if (p == null || p.getWorkdir() == null || p.getWorkdir().isEmpty()) {
            throw new IOException("项目不存在或工作目录未配置: " + projectId);
        }
        return new File(new File(new File(p.getWorkdir()), "job"), "program-tasks/" + taskId);
    }

    /* ---------- 多系统联合仿真(AFO_V_2 会话) ---------- */

    /**
     * AFO会话大文件工作目录(扁平,项目工作目录下一级):
     * `<项目工作目录>/afo/<runId>`(status.json/inbox/runtime/result.json/交付Excel);
     * 无项目或工作目录缺失时回退元数据目录 projects/{pid}/afo-work/<runId>。
     */
    public File afoWorkDir(String projectId, String runId) throws IOException {
        EngineProject p = getProject(projectId);
        if (p == null || p.getWorkdir() == null || p.getWorkdir().isEmpty()) {
            throw new IOException("项目不存在或工作目录未配置: " + projectId);
        }
        return new File(new File(new File(p.getWorkdir()), "job"), "afo/" + runId);
    }

    /** AFO会话元数据文件(projects/{pid}/afo/{runId}.json),与 predictions/uq 同模式。 */
    public File afoSessionFile(String projectId, String runId) throws IOException {
        return new File(projectDir(projectId), "afo/" + runId + ".json");
    }

    public File afoSessionDir(String projectId) throws IOException {
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

    public File modelFile(String projectId, String modelId) throws IOException {
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
