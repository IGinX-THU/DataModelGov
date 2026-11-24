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
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import com.tsinghua.entity.EngineProjectEntity;
import com.tsinghua.entity.FileLibraryEntity;
import com.tsinghua.engine.EngineModels.EngineProject;
import com.tsinghua.engine.EngineModels.ModelAsset;
import com.tsinghua.engine.EngineModels.ModelingTask;
import com.tsinghua.engine.EngineModels.PredictionRecord;
import com.tsinghua.engine.EngineModels.UqRecord;
import com.tsinghua.util.MojibakeUtil;

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

    @org.springframework.beans.factory.annotation.Autowired
    private EngineTaskRecordService taskRecordService;

    @org.springframework.beans.factory.annotation.Autowired
    private EngineModelRecordService modelRecordService;

    @org.springframework.beans.factory.annotation.Autowired
    private EngineUqRecordService uqRecordService;

    @org.springframework.beans.factory.annotation.Autowired
    private EnginePredictionRecordService predictionRecordService;

    @org.springframework.beans.factory.annotation.Autowired
    private FileLibraryMetaService fileLibraryMetaService;

    @org.springframework.beans.factory.annotation.Autowired(required = false)
    private FileBackupService fileBackupService;

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
     * 删除项目:整个工作目录递归删除(项目目录专属);元数据/清单记录由 controller 清理。
     * 目录未配置或文件被占用(如MATLAB引擎未释放)时抛异常,由前端提示,不留静默残留。
     */
    public void deleteProject(String projectId) throws IOException {
        EngineProject p = getProject(projectId);
        // 工作目录即项目专属目录(系统为项目生成/用户指定):整个删除。
        // 静默跳过会导致"项目记录已删、目录残留",必须显式报错让前端提示用户
        if (p == null || p.getWorkdir() == null || p.getWorkdir().isEmpty()) {
            throw new IOException("项目工作目录未配置或元数据不可读,无法删除项目文件目录(可手动清理)");
        }
        File wd = new File(p.getWorkdir());
        if (wd.exists()) deleteRecursively(wd);
    }

    /** 递归删除;任何文件删除失败(被占用/权限)即抛异常并给出残留路径,不留静默垃圾目录。 */
    private void deleteRecursively(File f) throws IOException {
        if (!f.exists()) return;
        File[] children = f.listFiles();
        if (children != null) {
            for (File c : children) deleteRecursively(c);
        }
        if (!f.delete()) {
            throw new IOException("文件或目录删除失败(可能被MATLAB引擎或其他进程占用): "
                    + f.getAbsolutePath() + ";请停止相关任务后重试");
        }
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
        // 出错绕路:任务被记录过替代工作目录时,所有产物定位统一走替代路径,
        // 否则任务写在新目录、前端/断言仍按默认目录找,会出现"执行成功但找不到交付"。
        try {
            ModelingTask t = getTask(projectId, taskId);
            if (t != null && t.getWorkDirOverride() != null && !t.getWorkDirOverride().trim().isEmpty()) {
                File alt = new File(t.getWorkDirOverride().replace('\\', '/'));
                return alt;
            }
        } catch (Exception ignore) {
            // 任务元数据尚不可用(如预测用伪 taskId)时回退默认路径
        }
        EngineProject p = getProject(projectId);
        if (p == null || p.getWorkdir() == null || p.getWorkdir().isEmpty()) {
            throw new IOException("项目不存在或工作目录未配置: " + projectId);
        }
        return new File(new File(new File(p.getWorkdir()), "job"), "program-tasks/" + taskId);
    }

    /**
     * 出错绕路:把任务工作目录切换到短临时路径,并写入任务元数据,使后续所有 taskWorkDir 调用一致。
     * 仅在正常路径创建/写入失败(FS_PERMISSION/EXCEL_FILE)时由失败处理调用。
     *
     * @return 绕路后的工作目录(已建成);失败返回 null,调用方按原错误报错
     */
    public File detourTaskWorkDir(String projectId, String taskId) {
        try {
            // 固定短路径,便于原目录恢复可写后仍能定位历史产物
            String slug = (projectId + "_" + taskId).replaceAll("[^A-Za-z0-9_-]", "_");
            if (slug.length() > 64) slug = slug.substring(0, 64);
            File base = new File(new File(System.getProperty("java.io.tmpdir"), "dmg-work"), slug);
            if (!base.isDirectory() && !base.mkdirs()) {
                log.warn("绕路工作目录创建失败: {}", base);
                return null;
            }
            // 把原工作目录内容(输入副本/确认凭据/适配器)尽量搬到短路径,
            // 否则 transient run 的 confirmationFile 与 compat 副本仍在旧目录,绕路后找不到。
            EngineProject p = getProject(projectId);
            if (p != null && p.getWorkdir() != null && !p.getWorkdir().isEmpty()) {
                File original = new File(new File(new File(p.getWorkdir()), "job"), "program-tasks/" + taskId);
                if (original.isDirectory() && !original.equals(base.getCanonicalFile())) {
                    copyTreeBestEffort(original, base);
                }
            }
            ModelingTask t = getTask(projectId, taskId);
            if (t == null) {
                log.warn("绕路工作目录失败:任务元数据不存在 {}/{}", projectId, taskId);
                return null;
            }
            t.setWorkDirOverride(base.getAbsolutePath().replace('\\', '/'));
            saveTask(t);
            log.warn("任务工作目录已绕路到临时短路径: task={} -> {}", taskId, base);
            return base;
        } catch (Exception e) {
            log.warn("绕路工作目录异常: task={} ({})", taskId, e.toString());
            return null;
        }
    }

    /** 绕路时把原工作目录内容搬到短路径;单个文件失败(占用)不中断整体绕路。 */
    private void copyTreeBestEffort(File src, File dst) {
        try {
            java.nio.file.Files.walkFileTree(src.toPath(), new java.nio.file.SimpleFileVisitor<Path>() {
                @Override public java.nio.file.FileVisitResult preVisitDirectory(Path dir, java.nio.file.attribute.BasicFileAttributes attrs) {
                    try {
                        Path rel = src.toPath().relativize(dir);
                        Path target = dst.toPath().resolve(rel.toString());
                        if (!java.nio.file.Files.isDirectory(target)) java.nio.file.Files.createDirectories(target);
                        return java.nio.file.FileVisitResult.CONTINUE;
                    } catch (Exception e) {
                        log.warn("绕路复制目录跳过: {} ({})", dir, e.toString());
                        return java.nio.file.FileVisitResult.SKIP_SUBTREE;
                    }
                }
                @Override public java.nio.file.FileVisitResult visitFile(Path file, java.nio.file.attribute.BasicFileAttributes attrs) {
                    try {
                        Path rel = src.toPath().relativize(file);
                        Path target = dst.toPath().resolve(rel.toString());
                        if (!java.nio.file.Files.isRegularFile(target)
                                || java.nio.file.Files.size(target) != attrs.size()
                                || target.toFile().lastModified() < file.toFile().lastModified()) {
                            java.nio.file.Files.copy(file, target, StandardCopyOption.REPLACE_EXISTING);
                        }
                    } catch (Exception e) {
                        log.warn("绕路复制文件跳过(占用): {} ({})", file, e.toString());
                    }
                    return java.nio.file.FileVisitResult.CONTINUE;
                }
                @Override public java.nio.file.FileVisitResult visitFileFailed(Path file, IOException exc) {
                    log.warn("绕路复制不可读跳过: {} ({})", file, exc == null ? "" : exc.toString());
                    return java.nio.file.FileVisitResult.CONTINUE;
                }
            });
        } catch (Exception e) {
            log.warn("绕路复制工作目录异常: {} -> {} ({})", src, dst, e.toString());
        }
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

    /* ---------- 数字试车台(testbench:全模式会话/设计点/起动停车) ---------- */

    /** testbench任务大文件工作目录:<workdir>/job/testbench/<key>。 */
    public File testbenchWorkDir(String projectId, String key) throws IOException {
        EngineProject p = getProject(projectId);
        if (p == null || p.getWorkdir() == null || p.getWorkdir().isEmpty()) {
            throw new IOException("项目不存在或工作目录未配置: " + projectId);
        }
        return new File(new File(new File(p.getWorkdir()), "job"), "testbench/" + key);
    }

    /** testbench元数据文件(projects/{pid}/testbench/{key}.json)。 */
    public File testbenchSessionFile(String projectId, String key) throws IOException {
        return new File(projectDir(projectId), "testbench/" + key + ".json");
    }

    public File testbenchSessionDir(String projectId) throws IOException {
        return new File(projectDir(projectId), "testbench");
    }

    public ModelingTask saveTask(ModelingTask t) throws IOException {
        // 统一兜底：各服务把 MATLAB 异常原文写进 message/uqMessage 时，落盘前还原中文乱码。
        // repair 幂等且对正常中文无副作用，避免在每个异常分支重复处理。
        t.setMessage(MojibakeUtil.repair(t.getMessage()));
        t.setUqMessage(MojibakeUtil.repair(t.getUqMessage()));
        if (t.getId() == null || t.getId().isEmpty()) {
            t.setId(newId());
            t.setCreatedAt(System.currentTimeMillis());
        }
        File dir = taskDir(t.getProjectId(), t.getId());
        if (!dir.exists() && !dir.mkdirs()) throw new IOException("无法创建任务目录: " + dir);
        mapper.writerWithDefaultPrettyPrinter().writeValue(new File(dir, "task.json"), t);
        syncTaskRecord(t);
        registerTaskArtifactsToLibrary(t); // 工作流产出的Excel沉淀进文件库,供下游训练数据下拉选择
        return t;
    }

    /**
     * 任务完成(UQ完成)时把输出Excel自动沉淀进项目文件库(data类),
     * 使下一工作流在「从文件库选择」训练数据时能直接选到本工作流的产物。
     * 模型交付单独归 model 类(不进训练数据槽位),与 saveModel 的登记共用同一条索引。
     */
    private void registerTaskArtifactsToLibrary(ModelingTask t) {
        if (t == null || t.getId() == null) return;
        boolean completed = ModelingTask.ST_COMPLETED.equals(t.getStatus());
        boolean uqDone = "COMPLETED".equalsIgnoreCase(t.getUqStatus())
                || "UQ_COMPLETED".equalsIgnoreCase(t.getUqStatus());
        if (!completed && !uqDone) return;
        String biz = taskBusinessLabel(t.getKind());
        try {
            if (completed) collectArtifactFiles(t.getProjectId(), t.getResult(), biz, t.getId(), 0);
            if (uqDone) collectArtifactFiles(t.getProjectId(), t.getUqResult(), biz + "·UQ", t.getId(), 0);
        } catch (Exception e) {
            log.warn("工作流产物入文件库失败(不影响任务): task={}", t.getId(), e);
        }
    }

    private static String taskBusinessLabel(String kind) {
        if (kind == null) return "建模";
        if ("steady".equals(kind)) return "稳态试车建模";
        if ("steady_update".equals(kind)) return "稳态数据更新";
        if ("transient_update".equals(kind)) return "瞬态数据更新";
        if ("flight_steady".equals(kind)) return "稳态飞参建模";
        if ("flight_transient".equals(kind)) return "过渡态飞参建模";
        if ("evolution".equals(kind)) return "模型自演化";
        return kind;
    }

    /** 递归一层收集结果摘要里的Excel路径与outputDirectory/outputFiles清单。 */
    private void collectArtifactFiles(String pid, Map<String, Object> map, String biz, String taskId, int depth) {
        if (map == null || map.isEmpty() || depth > 1) return;
        String dirPath = null;
        Object d = map.get("outputDirectory");
        if (d == null) d = map.get("outputRoot");
        if (d instanceof String) dirPath = (String) d;
        for (Map.Entry<String, Object> en : map.entrySet()) {
            String key = en.getKey() == null ? "" : String.valueOf(en.getKey());
            Object v = en.getValue();
            if (v instanceof String) {
                String s = (String) v;
                if (isExcel(s) && new File(s).isFile()) {
                    // 工作流产出一律进 data 类:下游训练数据槽位只接受 data;
                    // 模型交付另由 saveModel 以 model 类登记,避免同一文件在模型下拉重复出现。
                    registerArtifact(pid, taskId, new File(s), "data",
                            "产物 · " + biz + " · " + fileNameOf(s), taskId, taskId);
                }
            } else if (v instanceof List && "outputFiles".equals(key) && dirPath != null) {
                File dir = new File(dirPath);
                for (Object o : (List<?>) v) {
                    if (o == null) continue;
                    File f = new File(dir, String.valueOf(o));
                    if (f.isFile() && isExcel(f.getName())) {
                        registerArtifact(pid, taskId, f, "data",
                                "产物 · " + biz + " · " + f.getName(), taskId, taskId);
                    }
                }
            } else if (v instanceof Map) {
                collectArtifactFiles(pid, castMap(v), biz, taskId, depth + 1);
            }
        }
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> castMap(Object v) {
        try {
            return (Map<String, Object>) v;
        } catch (ClassCastException e) {
            return null;
        }
    }

    private static boolean isExcel(String name) {
        String ext = fileExtension(name);
        return "xlsx".equals(ext) || "xls".equals(ext);
    }

    private static String fileNameOf(String path) {
        return new File(path).getName();
    }

    /** 任务档案同步到运行记录表(engine_task_records,SQL分页查询源);失败仅告警,不影响任务保存。 */
    private void syncTaskRecord(ModelingTask t) {
        try {
            taskRecordService.upsertFromTask(t);
        } catch (Exception e) {
            log.warn("运行记录同步失败: task={} status={}", t.getId(), t.getStatus(), e);
        }
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
        try {
            modelRecordService.upsertFromModel(m); // 模型成果清单(IginX)同步,失败仅告警
        } catch (Exception e) {
            log.warn("模型成果清单同步失败: model={}", m.getId(), e);
        }
        registerModelDeliveryToLibrary(m); // 交付Excel同步入项目文件库(model类),供下一工作流下拉选择
        return m;
    }

    /**
     * 模型成果登记时把交付Excel同步进项目文件库(files/model)。
     * 与「登记到模型成果」同一事务入口,幂等按 modelId 命名:重复保存覆盖同一条索引,
     * refId 回指模型成果,使下一工作流的「选择已有模型」与父工作簿兜底都能命中。
     * 入库失败只告警,不影响模型成果本身。
     */
    private void registerModelDeliveryToLibrary(ModelAsset m) {
        if (m == null || m.getId() == null || m.getDeliveryWorkbookFile() == null
                || m.getDeliveryWorkbookFile().trim().isEmpty()) return;
        registerArtifact(m.getProjectId(), m.getTaskId(), new File(m.getDeliveryWorkbookFile()), "model",
                "模型成果 · " + (m.getStage() == null ? "建模成果" : m.getStage())
                        + " · " + (m.getRoute() == null ? "稳态方程" : m.getRoute()),
                m.getId(), m.getId());
    }

    /**
     * 统一的产物入库:复制Excel到 <workdir>/files/{category},按「原名_标识」建索引,
     * refId 回指模型/任务,已存在同名索引则跳过(saveTask多次 save 幂等)。
     * 失败只告警,不影响建模任务或模型成果本身。
     */
    private void registerArtifact(String pid, String ownerId, File src, String category,
                                  String kindLabel, String refId, String suffix) {
        if (pid == null || src == null || !src.isFile() || !isExcel(src.getName())) return;
        try {
            EngineProject p = getProject(pid);
            if (p == null || p.getWorkdir() == null || p.getWorkdir().trim().isEmpty()) return;
            File dir = new File(new File(p.getWorkdir()), "files/" + category);
            if (!dir.exists() && !dir.mkdirs()) throw new IOException("无法创建文件库目录: " + dir);
            String srcName = src.getName();
            if (srcName.startsWith("~$")) return; // Excel临时锁文件
            int dot = srcName.lastIndexOf('.');
            String destName = (dot > 0 ? srcName.substring(0, dot) : srcName) + "_" + suffix
                    + (dot > 0 ? srcName.substring(dot) : "");
            for (FileLibraryEntity old : fileLibraryMetaService.queryPage(category, destName, null, null, null)) {
                if (destName.equalsIgnoreCase(old.getName())) return;
            }
            File dest = new File(dir, destName);
            if (!src.getCanonicalFile().equals(dest.getCanonicalFile())) {
                Files.copy(src.toPath(), dest.toPath(), StandardCopyOption.REPLACE_EXISTING);
            }
            byte[] bytes = Files.readAllBytes(dest.toPath());
            FileLibraryEntity e = new FileLibraryEntity();
            e.setProjectId(pid);
            e.setCategory(category);
            e.setKind(kindLabel);
            e.setName(destName);
            e.setPath(dest.getAbsolutePath());
            e.setSize((long) bytes.length);
            e.setExt(fileExtension(destName));
            e.setSha256(sha8Hex(bytes));
            e.setRefId(refId);
            fileLibraryMetaService.register(e);
            if (fileBackupService != null) fileBackupService.backup(e, dest);
            log.info("产物入项目文件库: {} task={} -> {}", category, ownerId, dest.getAbsolutePath());
        } catch (Exception ex) {
            log.warn("产物入项目文件库失败(不影响工作流): {} task={} file={}", category, ownerId, src, ex);
        }
    }

    private static String fileExtension(String name) {
        int i = name == null ? -1 : name.lastIndexOf('.');
        return i < 0 ? "" : name.substring(i + 1).toLowerCase();
    }

    private static String sha8Hex(byte[] bytes) {
        try {
            byte[] d = java.security.MessageDigest.getInstance("SHA-256").digest(bytes);
            StringBuilder sb = new StringBuilder();
            for (byte b : d) sb.append(String.format("%02x", b));
            return sb.substring(0, 8);
        } catch (Exception e) {
            return "";
        }
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
        try {
            predictionRecordService.upsertFromPrediction(r); // 预测记录清单(IginX)同步,失败仅告警
        } catch (Exception e) {
            log.warn("预测记录清单同步失败: rec={}", r.getId(), e);
        }
        // 运行记录阶段行(输出预测):与任务执行记录同表,kind=prediction
        try {
            com.tsinghua.entity.EngineTaskRecordEntity stage = new com.tsinghua.entity.EngineTaskRecordEntity();
            stage.setProjectId(r.getProjectId()).setTaskId("pred-" + r.getId()).setKind("prediction")
                 .setName("输出预测 · " + (r.getModelName() != null ? r.getModelName() : "模型"))
                 .setRunId(r.getRunId()).setStatus(r.getStatus()).setMessage(r.getMessage())
                 .setStartTime(r.getCreatedAt()).setEndTime(r.getFinishedAt())
                 .setCreateTime(r.getCreatedAt() != null ? r.getCreatedAt() : System.currentTimeMillis());
            taskRecordService.upsertRow(stage);
        } catch (Exception e) {
            log.warn("预测阶段运行记录同步失败: rec={}", r.getId(), e);
        }
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
        r.setMessage(MojibakeUtil.repair(r.getMessage()));
        if (r.getId() == null || r.getId().isEmpty()) {
            r.setId(newId());
            if (r.getStartedAt() == null) r.setStartedAt(System.currentTimeMillis());
        }
        File dir = new File(projectDir(r.getProjectId()), "uq");
        if (!dir.exists() && !dir.mkdirs()) throw new IOException("无法创建UQ记录目录: " + dir);
        mapper.writerWithDefaultPrettyPrinter().writeValue(new File(dir, r.getId() + ".json"), r);
        try {
            uqRecordService.upsertFromUq(r); // UQ记录清单(IginX)同步,失败仅告警
        } catch (Exception e) {
            log.warn("UQ记录清单同步失败: uq={}", r.getId(), e);
        }
        // UQ不在运行记录留痕(20261030口径):运行记录=工作流执行记录;UQ的留痕在
        // 评估记录(uq-records,模型维度,含失败)与所属任务的uqStatus,uq-阶段行已废弃
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
