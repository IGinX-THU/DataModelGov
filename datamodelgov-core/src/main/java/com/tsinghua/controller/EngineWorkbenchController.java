package com.tsinghua.controller;

import com.tsinghua.auth.annotation.RequirePermission;
import com.tsinghua.auth.enums.Permission;
import com.tsinghua.engine.EngineModels;
import com.tsinghua.engine.EngineProjectStore;
import com.tsinghua.engine.Tc24Service;
import com.tsinghua.model.Result;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.ArrayList;
import org.apache.poi.ss.usermodel.DataFormatter;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.ss.usermodel.WorkbookFactory;
import com.tsinghua.entity.FileLibraryEntity;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 工作台域模型 API(首链:稳态试车建模)。
 * 项目/任务/模型成果的文件存储与 TC24 任务执行。
 */
@Api(tags = "工作台-发动机项目")
@Slf4j
@RestController
@RequestMapping("/api/engine")
@CrossOrigin
public class EngineWorkbenchController {

    @Autowired
    private EngineProjectStore store;

    @Autowired
    private com.tsinghua.engine.EngineTaskRecordService taskRecordService;

    @Autowired
    private com.tsinghua.engine.EngineModelRecordService modelRecordService;

    @Autowired
    private com.tsinghua.engine.EngineUqRecordService uqRecordService;

    @Autowired
    private com.tsinghua.engine.EnginePredictionRecordService predictionRecordService;

    @Autowired
    private com.tsinghua.engine.EngineAfoSessionService afoSessionService;

    @Autowired
    private com.tsinghua.engine.EngineTestbenchRecordService testbenchRecordService;

    @Autowired
    private Tc24Service tc24Service;

    @Autowired
    private com.tsinghua.engine.AfoService afoService;

    @Autowired
    private com.tsinghua.engine.TestbenchService testbenchService;

    @Autowired
    private com.tsinghua.engine.F3FlightService f3FlightService;

    @Autowired
    private com.tsinghua.engine.EngineProjectMetaService metaService;

    /* ---------- 项目 ---------- */

    /** 项目归属校验:owner 为空视为历史遗留数据,仅管理员可见;非创建人一律拒绝。 */
    private String accessDenied(EngineModels.EngineProject p) {
        if (p == null) return "项目不存在";
        String user = com.tsinghua.auth.util.AuthUtil.getCurrentUsername();
        if (com.tsinghua.auth.util.AuthUtil.isAdmin()) return null;
        if (p.getOwner() != null && !p.getOwner().isEmpty() && !p.getOwner().equals(user)) {
            return "无权访问该项目(创建人:" + p.getOwner() + ")";
        }
        if (p.getOwner() == null || p.getOwner().isEmpty()) {
            return "无权访问该项目(历史项目仅管理员可见)";
        }
        return null;
    }

    /** 清单清理辅助:失败记录名称,不中断其余清单清理。 */
    private void tryDel(List<String> fails, String label, java.util.concurrent.Callable<Integer> action) {
        try {
            action.call();
        } catch (Exception e) {
            fails.add(label + "(" + e.getMessage() + ")");
        }
    }

    /**
     * 新建试车更新任务的数据预填(图01-17:同一稳态任务的TC27数据使用方式):
     * 原训练均值/原测试集取上游父模型的溯源数据(缺溯源时回退来源任务);
     * 新增历程继承同父最近一次更新任务已上传文件。均复制进本任务input目录,不跨任务引用。
     */
    private void prefillUpdateFiles(String pid, EngineModels.ModelingTask t, EngineModels.ModelAsset parent) {
        try {
            File dir = new File(store.taskWorkDir(pid, t.getId()), "input");
            if (!dir.exists() && !dir.mkdirs()) return;
            // 1) 原均值/原测试:父模型溯源数据 → 回退来源任务
            String baseTraining = parent.getTrainingFile();
            String baseTest = parent.getTestFile();
            EngineModels.ModelingTask baseTask = parent.getTaskId() == null ? null : store.getTask(pid, parent.getTaskId());
            if (baseTraining == null && baseTask != null) baseTraining = baseTask.getTrainingFile();
            if (baseTest == null && baseTask != null) baseTest = baseTask.getTestFile();
            if (baseTraining != null) t.setTrainingFile(copyIntoInput(dir, baseTraining));
            if (baseTest != null) t.setTestFile(copyIntoInput(dir, baseTest));
            // 2) 新增历程:同父最近一次更新任务已上传的历程(含其原测试覆写)
            for (EngineModels.ModelingTask x : store.listTasks(pid)) {
                if (x.getId().equals(t.getId())) continue;
                if (!"steady_update".equals(x.getKind()) || !parent.getId().equals(x.getUpstreamModelId())) continue;
                if (t.getHistoryFile() == null && x.getHistoryFile() != null) {
                    t.setHistoryFile(copyIntoInput(dir, x.getHistoryFile()));
                }
                if (x.getHistoryTestFile() != null) {
                    t.setHistoryTestFile(copyIntoInput(dir, x.getHistoryTestFile()));
                }
                break; // listTasks按创建时间倒序,首个同父任务即最近一次
            }
            if (t.getTrainingFile() != null || t.getHistoryFile() != null) {
                t.setMessage("已预填历史数据(原均值" + (t.getTrainingFile() != null ? "已带入" : "缺失")
                        + ";新增历程" + (t.getHistoryFile() != null ? "已带入" : "待上传")
                        + ");可替换后重新准备数据");
            }
        } catch (Exception e) {
            log.warn("更新任务数据预填失败: {}", t.getId(), e);
        }
    }

    /** 把历史数据文件复制进本任务input目录(复制而非引用,避免源任务删除后断链);失败返回null不阻断创建。 */
    private String copyIntoInput(File dir, String srcPath) {
        try {
            File s = new File(srcPath);
            if (!s.isFile()) return null;
            File d = new File(dir, s.getName());
            java.nio.file.Files.copy(s.toPath(), d.toPath(),
                    java.nio.file.StandardCopyOption.REPLACE_EXISTING);
            return d.getAbsolutePath();
        } catch (Exception e) {
            log.warn("预填文件复制失败: {}", srcPath, e);
            return null;
        }
    }

    @ApiOperation("创建项目(类型/发动机/保存位置;元数据入IginX,owner=当前用户)")
    @PostMapping("/projects")
    @RequirePermission(Permission.CREATE)
    public Result<EngineModels.EngineProject> createProject(@RequestBody Map<String, Object> body) {
        EngineModels.EngineProject p = new EngineModels.EngineProject();
        p.setName((String) body.getOrDefault("name", "未命名项目"));
        p.setType((String) body.getOrDefault("type", "个性化自适应建模"));
        p.setEngineId((String) body.getOrDefault("engineId", "E-001"));
        p.setLocation((String) body.get("location"));
        p.setDesc((String) body.get("desc"));
        p.setOwner(com.tsinghua.auth.util.AuthUtil.getCurrentUsername());
        try {
            // 同名校验:项目名唯一,避免同名目录互相覆盖(workdir按项目名生成)
            for (com.tsinghua.entity.EngineProjectEntity e : metaService.queryList(null, 1, 500)) {
                if (p.getName() != null && p.getName().equals(e.getName())) {
                    return Result.error("项目名称已存在: " + p.getName() + ",请更换名称");
                }
            }
            p = store.saveProject(p);
            // 统一预置(整树镜像,所有项目目录结构一致):交付树 programs/ 全部内容
            // (m_program_adaptive_tune + C_runtime + AFO_V_2)复制到 <workdir>/program/,
            // TC24/AFO/试车台/设计点/起动停车入口齐全;失败仅告警由运行时ensure兜底
            try {
                testbenchService.provisionProgramForProject(p.getId());
            } catch (Exception pe) {
                log.warn("项目程序源预置失败(运行时将兜底): {} -> {}", p.getName(), pe.getMessage());
            }
            return Result.success(p);
        } catch (Exception e) {
            log.error("创建项目失败", e);
            return Result.error("创建项目失败: " + e.getMessage());
        }
    }

    @ApiOperation("删除项目(元数据+任务/模型/评估/预测/会话记录;工作目录仅清本系统写入部分)")
    @DeleteMapping("/projects/{pid}")
    @RequirePermission(Permission.CREATE)
    public Result<Boolean> deleteProject(@PathVariable("pid") String pid,
                                         @RequestParam(value = "name", required = false) String name) {
        try {
            EngineModels.EngineProject p = store.getProject(pid, name);
            if (p == null) return Result.error("项目不存在");
            String denied = accessDenied(p);
            if (denied != null) return Result.error(denied);
            // 先释放该项目占用的MATLAB引擎(引擎进程工作目录锁住项目目录会导致删除失败)
            try {
                testbenchService.releaseProjectEngines(pid);
            } catch (Exception re) {
                log.warn("释放项目MATLAB引擎失败(继续尝试删除): {}", pid, re);
            }
            store.deleteProject(pid);
            boolean metaDeleted = metaService.delete(Long.parseLong(pid));
            if (!metaDeleted) {
                return Result.error("项目记录删除未生效(IginX),请稍后重试或联系管理员");
            }
            // 清单类 IginX 记录一并清理(运行记录/模型成果/UQ/预测/AFO会话/试车台记录)
            List<String> delFail = new ArrayList<>();
            tryDel(delFail, "运行记录", () -> taskRecordService.deleteByProject(pid));
            tryDel(delFail, "模型成果", () -> modelRecordService.deleteByProject(pid));
            tryDel(delFail, "UQ记录", () -> uqRecordService.deleteByProject(pid));
            tryDel(delFail, "预测记录", () -> predictionRecordService.deleteByProject(pid));
            tryDel(delFail, "仿真记录", () -> afoSessionService.deleteByProject(pid));
            tryDel(delFail, "试车台记录", () -> testbenchRecordService.deleteByProject(pid));
            tryDel(delFail, "文件库索引", () -> fileLibraryMetaService.deleteByProject(pid));
            if (!delFail.isEmpty()) {
                log.warn("项目清单记录清理失败: {} -> {}", pid, delFail);
                return Result.error("项目已删除,但部分清单记录清理失败: " + String.join("、", delFail));
            }
            log.info("项目已删除: {} ({})", p.getName(), pid);
            return Result.success(true);
        } catch (Exception e) {
            log.error("删除项目失败", e);
            return Result.error("删除项目失败: " + e.getMessage());
        }
    }

    @ApiOperation("项目列表(旧口径:不分页,仅兼容展示;建议用 /projects/list+count)")
    @GetMapping("/projects")
    @RequirePermission(Permission.READ)
    public Result<List<EngineModels.EngineProject>> listProjects() {
        try {
            List<EngineModels.EngineProject> out = new ArrayList<>();
            for (com.tsinghua.entity.EngineProjectEntity e : metaService.queryList(null, 1, 500)) {
                out.add(metaToProject(e));
            }
            return Result.success(out);
        } catch (Exception e) {
            return Result.error("读取项目失败: " + e.getMessage());
        }
    }

    @ApiOperation("项目分页列表(owner SQL条件隔离,管理员可见全部)")
    @GetMapping("/projects/list")
    @RequirePermission(Permission.READ)
    public Result<List<com.tsinghua.entity.EngineProjectEntity>> listProjectsPage(
            @RequestParam(value = "name", required = false) String name,
            @RequestParam(value = "pageNum", required = false, defaultValue = "1") Integer pageNum,
            @RequestParam(value = "pageSize", required = false, defaultValue = "10") Integer pageSize) {
        return Result.success(metaService.queryList(name, pageNum, pageSize));
    }

    @ApiOperation("项目总数(与分页列表同过滤口径)")
    @GetMapping("/projects/count")
    @RequirePermission(Permission.READ)
    public Result<Long> countProjects(@RequestParam(value = "name", required = false) String name) {
        return Result.success(metaService.countList(name));
    }

    private EngineModels.EngineProject metaToProject(com.tsinghua.entity.EngineProjectEntity e) {
        EngineModels.EngineProject p = new EngineModels.EngineProject();
        p.setId(e.getId() == null ? null : String.valueOf(e.getId()));
        p.setName(e.getName());
        p.setType(e.getType());
        p.setEngineId(e.getEngineId());
        p.setLocation(e.getLocation());
        p.setWorkdir(e.getWorkdir());
        p.setDesc(e.getDesc());
        p.setOwner(e.getOwner());
        p.setCreatedAt(e.getCreateTime());
        return p;
    }

    @ApiOperation("项目详情(含任务与模型;latestPerKind=true时任务表按类型去重只留最新一条,供项目概览)")
    @GetMapping("/projects/detail")
    @RequirePermission(Permission.READ)
    public Result<Map<String, Object>> projectDetail(@RequestParam("projectId") String pid,
            @RequestParam(value = "latestPerKind", required = false, defaultValue = "false") boolean latestPerKind) {
        try {
            EngineModels.EngineProject p = store.getProject(pid);
            String denied = accessDenied(p);
            if (denied != null) return Result.error(denied);
            List<EngineModels.ModelingTask> tasks = store.listTasks(pid);
            if (latestPerKind) {
                // listTasks已按创建时间倒序,每个kind取首次出现的即最新一条(项目概览口径)
                Map<String, EngineModels.ModelingTask> firstByKind = new LinkedHashMap<>();
                for (EngineModels.ModelingTask t : tasks) firstByKind.putIfAbsent(t.getKind(), t);
                tasks = new ArrayList<>(firstByKind.values());
            }
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("project", p.toMap());
            out.put("tasks", tasks);
            out.put("models", store.listModels(pid));
            return Result.success(out);
        } catch (IOException e) {
            return Result.error("读取项目失败: " + e.getMessage());
        }
    }

    @ApiOperation("建模任务运行记录分页列表(SQL分页,与/projects/list同模式)")
    @GetMapping("/projects/{pid}/records/list")
    @RequirePermission(Permission.READ)
    public Result<List<com.tsinghua.entity.EngineTaskRecordEntity>> pageRecords(
            @PathVariable("pid") String pid,
            @RequestParam(value = "pageNum", required = false, defaultValue = "1") Integer pageNum,
            @RequestParam(value = "pageSize", required = false, defaultValue = "10") Integer pageSize) {
        String denied = projectReadDenied(pid);
        if (denied != null) return Result.error(denied);
        backfillTaskRecords(pid);
        return Result.success(taskRecordService.queryList(pid, pageNum, pageSize));
    }

    @ApiOperation("建模任务运行记录总数(SQL,与列表同过滤口径)")
    @GetMapping("/projects/{pid}/records/count")
    @RequirePermission(Permission.READ)
    public Result<Long> countRecords(@PathVariable("pid") String pid) {
        String denied = projectReadDenied(pid);
        if (denied != null) return Result.error(denied);
        backfillTaskRecords(pid);
        return Result.success(taskRecordService.countList(pid));
    }

    /** 存量任务回填:记录表为空而文件任务存在时(如升级部署后首次访问),把文件任务档案同步进记录表;
     *  之后由 EngineProjectStore.saveTask 挂钩保持增量同步。 */
    private void backfillTaskRecords(String pid) {
        try {
            if (taskRecordService.countList(pid) > 0) return;
            List<EngineModels.ModelingTask> tasks = store.listTasks(pid);
            for (EngineModels.ModelingTask t : tasks) {
                try {
                    taskRecordService.upsertFromTask(t);
                } catch (Exception e) {
                    log.warn("运行记录回填失败: task={}", t.getId(), e);
                }
            }
        } catch (Exception e) {
            log.warn("运行记录回填检查失败: projectId={}", pid, e);
        }
    }

    /** 项目读取校验(读取项目失败/无权访问返回错误文案,通过返回null)。 */
    private String projectReadDenied(String pid) {
        try {
            return accessDenied(store.getProject(pid));
        } catch (IOException e) {
            return "读取项目失败: " + e.getMessage();
        }
    }

    /* ---------- 清单分页(模型成果/UQ记录/预测记录;IginX SQL,文件为事实源) ---------- */

    @ApiOperation("模型成果清单分页(SQL;原 /models 全量接口保留供选择器/详情使用)")
    @GetMapping("/projects/{pid}/models/list")
    @RequirePermission(Permission.READ)
    public Result<List<com.tsinghua.entity.EngineModelAssetEntity>> pageModels(
            @PathVariable("pid") String pid,
            @RequestParam(value = "pageNum", required = false, defaultValue = "1") Integer pageNum,
            @RequestParam(value = "pageSize", required = false, defaultValue = "10") Integer pageSize) {
        String denied = projectReadDenied(pid);
        if (denied != null) return Result.error(denied);
        backfillModels(pid);
        return Result.success(modelRecordService.queryList(pid, pageNum, pageSize));
    }

    @ApiOperation("模型成果总数(SQL)")
    @GetMapping("/projects/{pid}/models/count")
    @RequirePermission(Permission.READ)
    public Result<Long> countModels(@PathVariable("pid") String pid) {
        String denied = projectReadDenied(pid);
        if (denied != null) return Result.error(denied);
        backfillModels(pid);
        return Result.success(modelRecordService.countList(pid));
    }

    private void backfillModels(String pid) {
        try {
            if (modelRecordService.countList(pid) > 0) return;
            for (EngineModels.ModelAsset m : store.listModels(pid)) modelRecordService.upsertFromModel(m);
        } catch (Exception e) {
            log.warn("模型成果清单回填失败: projectId={}", pid, e);
        }
    }

    @ApiOperation("UQ评估记录清单分页(SQL)")
    @GetMapping("/projects/{pid}/uq-records/list")
    @RequirePermission(Permission.READ)
    public Result<List<com.tsinghua.entity.EngineUqRecordEntity>> pageUqRecords(
            @PathVariable("pid") String pid,
            @RequestParam(value = "pageNum", required = false, defaultValue = "1") Integer pageNum,
            @RequestParam(value = "pageSize", required = false, defaultValue = "10") Integer pageSize) {
        String denied = projectReadDenied(pid);
        if (denied != null) return Result.error(denied);
        backfillUqRecords(pid);
        return Result.success(uqRecordService.queryList(pid, pageNum, pageSize));
    }

    @ApiOperation("UQ评估记录总数(SQL)")
    @GetMapping("/projects/{pid}/uq-records/count")
    @RequirePermission(Permission.READ)
    public Result<Long> countUqRecords(@PathVariable("pid") String pid) {
        String denied = projectReadDenied(pid);
        if (denied != null) return Result.error(denied);
        backfillUqRecords(pid);
        return Result.success(uqRecordService.countList(pid));
    }

    private void backfillUqRecords(String pid) {
        try {
            if (uqRecordService.countList(pid) > 0) return;
            for (EngineModels.UqRecord r : store.listUqRecords(pid)) uqRecordService.upsertFromUq(r);
        } catch (Exception e) {
            log.warn("UQ记录清单回填失败: projectId={}", pid, e);
        }
    }

    @ApiOperation("输出预测记录清单分页(SQL)")
    @GetMapping("/projects/{pid}/predictions/list")
    @RequirePermission(Permission.READ)
    public Result<List<com.tsinghua.entity.EnginePredictionEntity>> pagePredictions(
            @PathVariable("pid") String pid,
            @RequestParam(value = "pageNum", required = false, defaultValue = "1") Integer pageNum,
            @RequestParam(value = "pageSize", required = false, defaultValue = "10") Integer pageSize) {
        String denied = projectReadDenied(pid);
        if (denied != null) return Result.error(denied);
        backfillPredictions(pid);
        return Result.success(predictionRecordService.queryList(pid, pageNum, pageSize));
    }

    @ApiOperation("输出预测记录总数(SQL)")
    @GetMapping("/projects/{pid}/predictions/count")
    @RequirePermission(Permission.READ)
    public Result<Long> countPredictions(@PathVariable("pid") String pid) {
        String denied = projectReadDenied(pid);
        if (denied != null) return Result.error(denied);
        backfillPredictions(pid);
        return Result.success(predictionRecordService.countList(pid));
    }

    private void backfillPredictions(String pid) {
        try {
            if (predictionRecordService.countList(pid) > 0) return;
            for (EngineModels.PredictionRecord r : store.listPredictions(pid)) {
                predictionRecordService.upsertFromPrediction(r);
            }
        } catch (Exception e) {
            log.warn("预测记录清单回填失败: projectId={}", pid, e);
        }
    }

    /* ---------- 建模任务 ---------- */

    @ApiOperation("创建稳态试车建模任务")
    @PostMapping("/projects/{pid}/tasks")
    @RequirePermission(Permission.CREATE)
    public Result<EngineModels.ModelingTask> createTask(@PathVariable("pid") String pid,
                                                        @RequestBody Map<String, Object> body) {
        try {
            EngineModels.EngineProject p = store.getProject(pid);
            String denied = accessDenied(p);
            if (denied != null) return Result.error(denied);
            EngineModels.ModelingTask t = new EngineModels.ModelingTask();
            t.setProjectId(pid);
            t.setKind((String) body.getOrDefault("kind", "steady"));
            t.setName((String) body.getOrDefault("name", "稳态建模任务"));
            t.setRoute((String) body.getOrDefault("route", "steady"));
            t.setRunId((String) body.getOrDefault("runId", "WB_01"));
            t.setStatus(EngineModels.ModelingTask.ST_READY);
            if ("flight_steady".equals(t.getKind()) || "flight_transient".equals(t.getKind())
                    || "evolution".equals(t.getKind())) {
                // F3飞参建模(F-04/F-05)与自演化(F-06):父模型来源与路线;确认/执行阶段逐项校验
                t.setName((String) body.getOrDefault("name",
                        "flight_steady".equals(t.getKind()) ? "稳态飞参建模任务"
                                : "flight_transient".equals(t.getKind()) ? "过渡态飞参建模任务" : "模型自演化任务"));
                Object ps = body.get("parentSource");
                t.setParentSource(ps == null ? "2p4" : String.valueOf(ps));
                Object pr = body.get("parentRoute");
                t.setParentRoute(pr == null ? "steady" : String.valueOf(pr));
                Object pmId = body.get("parentModelId");
                if (pmId != null && !String.valueOf(pmId).isEmpty()) {
                    t.setParentModelId(String.valueOf(pmId));
                }
                Object eid = body.get("f3EngineId");
                t.setF3EngineId(eid == null || String.valueOf(eid).isEmpty() ? p.getEngineId() : String.valueOf(eid));
                Object sid = body.get("f3SortieId");
                t.setF3SortieId(sid == null || String.valueOf(sid).isEmpty() ? "SORTIE-01" : String.valueOf(sid));
                Object dm = body.get("dataMethod");
                t.setDataMethod(dm == null ? "steady_only" : String.valueOf(dm));
                Object rs = body.get("regularizationStrength");
                if (rs instanceof Number) t.setRegularizationStrength(((Number) rs).doubleValue());
                t.setMessage("待上传飞参训练Excel(Data表)");
                return Result.success(store.saveTask(t));
            }
            if ("transient_update".equals(t.getKind())) {
                // TC27瞬态更新(F-03):父模型须为TC27组合稳态模型,计算路径一致
                t.setName((String) body.getOrDefault("name", "新增试车瞬态更新任务"));
                Object upId = body.get("upstreamModelId");
                if (upId == null || String.valueOf(upId).isEmpty()) {
                    return Result.error("请选择上游TC27组合稳态模型");
                }
                EngineModels.ModelAsset parent = null;
                for (EngineModels.ModelAsset a : store.listModels(pid)) {
                    if (String.valueOf(upId).equals(a.getId())) { parent = a; break; }
                }
                if (parent == null || parent.getDeliveryWorkbookFile() == null
                        || !new File(parent.getDeliveryWorkbookFile()).isFile()) {
                    return Result.error("上游模型缺少交付Excel,不能作为TC27瞬态更新基础");
                }
                if (!"瞬态时刻方程".equals(parent.getRoute())) {
                    return Result.error("计算路径与上游父模型不一致:TC27瞬态更新的父模型须为「瞬态时刻方程」路线");
                }
                t.setTransientUpstreamModelId(parent.getId());
                t.setTransientUpstreamFile(parent.getDeliveryWorkbookFile());
                Object sm = body.get("selectionMode");
                t.setSelectionMode(sm == null ? "automatic" : String.valueOf(sm));
                Object eo = body.get("estimationOptions");
                if (eo instanceof Map) {
                    Map<String, Object> eoMap = new LinkedHashMap<>();
                    for (Map.Entry<String, Object> en : ((Map<String, Object>) eo).entrySet()) {
                        eoMap.put(en.getKey(), en.getValue());
                    }
                    t.setEstimationOptions(eoMap);
                }
                t.setMessage("待上传瞬态训练历程");
                return Result.success(store.saveTask(t));
            }
            if ("steady_update".equals(t.getKind())) {
                // TC27稳态更新(F-02):必需上游父模型(交付Excel)与新增历程;方法I/II独立保存
                t.setName((String) body.getOrDefault("name", "新增试车稳态更新任务"));
                t.setUpdateMethod((String) body.getOrDefault("updateMethod", "II"));
                Object inc = body.get("includeSmallHistory");
                t.setIncludeSmallHistory(inc != null && Boolean.parseBoolean(String.valueOf(inc)));
                String upstreamModelId = (String) body.get("upstreamModelId");
                if (upstreamModelId == null || upstreamModelId.isEmpty()) {
                    return Result.error("请选择上游TC24父模型");
                }
                EngineModels.ModelAsset parent = null;
                for (EngineModels.ModelAsset a : store.listModels(pid)) {
                    if (upstreamModelId.equals(a.getId())) { parent = a; break; }
                }
                if (parent == null || parent.getDeliveryWorkbookFile() == null
                        || !new File(parent.getDeliveryWorkbookFile()).isFile()) {
                    return Result.error("上游父模型缺少交付Excel,不能作为TC27更新基础");
                }
                // 计算路径必须与上游父模型一致(Excel manifest 会硬校验,提前到创建时拦截)
                String parentRoute = "稳态方程".equals(parent.getRoute()) ? "steady"
                        : "瞬态时刻方程".equals(parent.getRoute()) ? "transient_instant" : null;
                String reqRoute = (String) body.getOrDefault("route", parentRoute);
                if (parentRoute == null) {
                    return Result.error("上游父模型的计算路径无法识别,不能作为TC27更新基础");
                }
                if (!parentRoute.equals(reqRoute)) {
                    return Result.error("计算路径与上游父模型不一致:父模型为「" + parent.getRoute()
                            + "」,请选择一致的计算路径");
                }
                t.setRoute(parentRoute);
                t.setUpstreamModelId(upstreamModelId);
                t.setUpstreamModelFile(parent.getDeliveryWorkbookFile());
                t.setMessage("待上传原均值与新增试车历程");
                EngineModels.ModelingTask saved = store.saveTask(t);
                prefillUpdateFiles(pid, saved, parent);
                return Result.success(store.saveTask(saved));
            }
            t.setMessage("待上传数据");
            return Result.success(store.saveTask(t));
        } catch (IOException e) {
            return Result.error("创建任务失败: " + e.getMessage());
        }
    }

    @ApiOperation("上传任务数据(训练必选/测试可选,kind=training|test)")
    @PostMapping("/projects/{pid}/tasks/{tid}/files")
    @RequirePermission(Permission.CREATE)
    public Result<EngineModels.ModelingTask> uploadFiles(@PathVariable("pid") String pid,
                                                         @PathVariable("tid") String tid,
                                                         @RequestParam("kind") String kind,
                                                         @RequestParam("file") MultipartFile file) {
        try {
            EngineModels.ModelingTask t = store.getTask(pid, tid);
            if (t == null) return Result.error("任务不存在");
            String denied = accessDenied(store.getProject(pid));
            if (denied != null) return Result.error(denied);
            File dir = new File(store.taskWorkDir(pid, tid), "input");
            if (!dir.exists() && !dir.mkdirs()) return Result.error("无法创建输入目录");
            String safe = file.getOriginalFilename() == null ? "data.xlsx"
                    : new File(file.getOriginalFilename()).getName();
            File dest = new File(dir, safe);
            if (dest.exists()) dest.delete(); // 重新上传=覆盖更新
            file.transferTo(dest);
            if ("test".equals(kind)) {
                t.setTestFile(dest.getAbsolutePath());
            } else if ("identification".equals(kind)) {
                t.setIdentificationFile(dest.getAbsolutePath());
            } else if ("validation".equals(kind)) {
                t.setValidationFile(dest.getAbsolutePath());
            } else if ("history".equals(kind)) {
                t.setHistoryFile(dest.getAbsolutePath());
            } else if ("historyTest".equals(kind)) {
                t.setHistoryTestFile(dest.getAbsolutePath());
            } else {
                t.setTrainingFile(dest.getAbsolutePath());
            }
            String kindTxt = "test".equals(kind) ? "原测试集"
                    : "identification".equals(kind) ? "飞参训练数据"
                    : "validation".equals(kind) ? "独立测试数据"
                    : "history".equals(kind) ? "新增训练历程"
                    : "historyTest".equals(kind) ? "新增测试历程" : "原训练均值";
            // 合同校验:原训练均值必须含 point_id 列(常见错误是把历程文件传到均值位置)
            if ("training".equals(kind) && !excelHasColumn(dest, "point_id")) {
                if (!dest.delete()) log.warn("校验失败清理文件失败: {}", dest);
                return Result.error("上传的文件不是稳态均值Excel(缺少 point_id 列)。"
                        + "原训练均值=每行一个工况;如果您上传的是试车历程(每行一个时刻),"
                        + "请改放到「新增训练历程」位置。");
            }
            t.setMessage("已上传" + kindTxt + ": " + safe);
            // 自动沉淀进项目数据文件库(说明书2.3: 数据是项目级资产)
            try {
                FileLibraryEntity entry = new FileLibraryEntity();
                entry.setProjectId(pid);
                entry.setCategory("data");
                entry.setKind(kindTxt);
                registerLibraryEntry(entry, dest, kindTxt);
            } catch (Exception ex) {
                log.warn("任务上传自动入库失败(不影响任务): {}", safe, ex);
            }
            return Result.success(store.saveTask(t));
        } catch (Exception e) {
            log.error("上传任务数据失败", e);
            return Result.error("上传失败: " + e.getMessage());
        }
    }

    /* ---------- 项目文件库(数据/模型两类;索引入IginX SQL分页,本体在<workdir>/files/,IginX分块备份) ---------- */

    @Autowired
    private com.tsinghua.engine.FileLibraryMetaService fileLibraryMetaService;

    @Autowired
    private com.tsinghua.engine.FileBackupService fileBackupService;

    private File fileLibraryDir(String pid, String category) throws IOException {
        EngineModels.EngineProject p = store.getProject(pid);
        if (p == null || p.getWorkdir() == null || p.getWorkdir().isEmpty()) {
            throw new IOException("项目不存在或工作目录未配置: " + pid);
        }
        File dir = new File(new File(p.getWorkdir()), "files/" + category);
        if (!dir.exists() && !dir.mkdirs()) throw new IOException("无法创建文件库目录: " + dir);
        return dir;
    }

    private static String fileExt(String name) {
        int i = name == null ? -1 : name.lastIndexOf('.');
        return i < 0 ? "" : name.substring(i + 1).toLowerCase();
    }

    private static String sha8Hex(byte[] bytes) {
        try {
            byte[] d = MessageDigest.getInstance("SHA-256").digest(bytes);
            StringBuilder sb = new StringBuilder();
            for (byte b : d) sb.append(String.format("%02x", b));
            return sb.substring(0, 8);
        } catch (Exception e) {
            return "";
        }
    }

    /** 登记索引行(sha256前8位)+IginX分块备份;由各入库调用方复用。 */
    private void registerLibraryEntry(FileLibraryEntity entry, File file, String kindLabel) throws Exception {
        byte[] bytes = Files.readAllBytes(file.toPath());
        entry.setName(file.getName());
        entry.setPath(file.getAbsolutePath());
        entry.setSize(file.length());
        entry.setExt(fileExt(file.getName()));
        entry.setSha256(sha8Hex(bytes));
        entry.setKind(kindLabel == null ? entry.getKind() : kindLabel);
        fileLibraryMetaService.register(entry);
        if (fileBackupService != null) fileBackupService.backup(entry, file);
    }

    @ApiOperation("文件库分页列表(数据/模型;SQL分页,非admin仅本人)")
    @GetMapping("/projects/{pid}/files/page")
    @RequirePermission(Permission.READ)
    public Result<Map<String, Object>> fileList(@PathVariable("pid") String pid,
                                                @RequestParam(value = "category", required = false) String category,
                                                @RequestParam(value = "name", required = false) String name,
                                                @RequestParam(value = "pageNum", defaultValue = "1") Integer pageNum,
                                                @RequestParam(value = "pageSize", defaultValue = "10") Integer pageSize) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rows", fileLibraryMetaService.queryPage(category, name, pageNum, pageSize));
        out.put("total", fileLibraryMetaService.countPage(category, name));
        out.put("pageNum", pageNum);
        out.put("pageSize", pageSize);
        return Result.success(out);
    }

    @ApiOperation("上传文件入库(data类仅.xlsx/.xls;model类不限格式)")
    @PostMapping("/projects/{pid}/files")
    @RequirePermission(Permission.CREATE)
    public Result<FileLibraryEntity> fileUpload(@PathVariable("pid") String pid,
                                                @RequestParam("file") MultipartFile file,
                                                @RequestParam(value = "category", defaultValue = "data") String category,
                                                @RequestParam(value = "kind", required = false) String kind) {
        try {
            if (!"data".equals(category) && !"model".equals(category)) {
                return Result.error("category须为data或model");
            }
            String ext = fileExt(file.getOriginalFilename());
            if ("data".equals(category) && !"xlsx".equals(ext) && !"xls".equals(ext)) {
                return Result.error("数据文件仅支持 .xlsx/.xls(建模合同输入)");
            }
            File dir = fileLibraryDir(pid, category);
            String safe = file.getOriginalFilename() == null
                    ? ("file." + ext) : new File(file.getOriginalFilename()).getName();
            File dest = new File(dir, safe);
            if (dest.exists()) dest.delete(); // 同名覆盖更新
            file.transferTo(dest);
            FileLibraryEntity entry = new FileLibraryEntity();
            entry.setProjectId(pid);
            entry.setCategory(category);
            entry.setKind(kind == null || kind.isEmpty()
                    ? ("model".equals(category) ? "模型文件" : "数据文件") : kind);
            registerLibraryEntry(entry, dest, entry.getKind());
            return Result.success(entry);
        } catch (Exception e) {
            log.error("文件入库失败", e);
            return Result.error("文件入库失败: " + e.getMessage());
        }
    }

    @ApiOperation("删除文件库条目(含本地文件与IginX备份)")
    @DeleteMapping("/projects/{pid}/files/{id}")
    @RequirePermission(Permission.DELETE)
    public Result<Boolean> fileDelete(@PathVariable("pid") String pid,
                                      @PathVariable("id") Long id) {
        try {
            FileLibraryEntity e = fileLibraryMetaService.queryById(id);
            if (e == null) return Result.error("文件库条目不存在");
            if (fileBackupService != null) fileBackupService.deleteBackup(e);
            File local = new File(e.getPath());
            if (local.isFile() && !local.delete()) log.warn("本地文件删除失败: {}", e.getPath());
            return Result.success(fileLibraryMetaService.delete(id));
        } catch (Exception e) {
            return Result.error("删除失败: " + e.getMessage());
        }
    }

    @ApiOperation("文件内容预览(xlsx解析表头+前100行;其它格式返回元信息)")
    @GetMapping("/projects/{pid}/files/{id}/preview")
    @RequirePermission(Permission.READ)
    public Result<Map<String, Object>> filePreview(@PathVariable("pid") String pid,
                                                   @PathVariable("id") Long id) {
        try {
            FileLibraryEntity e = fileLibraryMetaService.queryById(id);
            if (e == null) return Result.error("文件库条目不存在");
            File f = fileBackupService.resolve(e);
            return Result.success(previewFileMap(f, e.getName(), e.getExt(), e.getSize(), e.getSha256()));
        } catch (Exception e) {
            log.error("文件预览失败", e);
            return Result.error("预览失败: " + e.getMessage());
        }
    }

    @ApiOperation("任务直传文件预览(kind=identification|validation|test;xlsx解析表头+前100行)")
    @GetMapping("/projects/{pid}/tasks/{tid}/file-preview")
    @RequirePermission(Permission.READ)
    public Result<Map<String, Object>> taskFilePreview(@PathVariable("pid") String pid,
                                                       @PathVariable("tid") String tid,
                                                       @RequestParam("kind") String kind) {
        try {
            EngineModels.ModelingTask t = store.getTask(pid, tid);
            if (t == null) return Result.error("任务不存在");
            String path = "test".equals(kind) ? t.getTestFile()
                    : "validation".equals(kind) ? t.getValidationFile() : t.getIdentificationFile();
            if (path == null || path.trim().isEmpty()) return Result.error("该任务尚未提供此文件");
            File f = new File(path);
            if (!f.isFile()) return Result.error("文件不存在: " + f.getName());
            String name = f.getName();
            String ext = name.contains(".") ? name.substring(name.lastIndexOf('.') + 1).toLowerCase() : "";
            Map<String, Object> out = previewFileMap(f, name, ext, f.length(), null);
            out.put("source", "task");
            return Result.success(out);
        } catch (Exception e) {
            log.error("任务文件预览失败", e);
            return Result.error("预览失败: " + e.getMessage());
        }
    }

    /** 文件内容预览公共实现:xlsx解析Data表(缺省首表)表头+前100行;其它格式返回元信息。 */
    private Map<String, Object> previewFileMap(File f, String name, String ext, Long size, String sha256) throws IOException {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("fileName", name);
        out.put("ext", ext);
        out.put("size", size);
        out.put("sha256", sha256);
        if ("xlsx".equals(ext) || "xls".equals(ext)) {
            DataFormatter fmt = new DataFormatter();
            try (InputStream in = Files.newInputStream(f.toPath()); Workbook wb = WorkbookFactory.create(in)) {
                List<String> names = new ArrayList<>();
                for (int i = 0; i < wb.getNumberOfSheets(); i++) names.add(wb.getSheetName(i));
                Sheet sheet = null;
                for (int i = 0; i < wb.getNumberOfSheets(); i++) {
                    String n = wb.getSheetName(i);
                    if ("Data".equalsIgnoreCase(n) || "数据".equals(n)) { sheet = wb.getSheetAt(i); break; }
                }
                if (sheet == null) sheet = wb.getSheetAt(0);
                out.put("sheetNames", names);
                out.put("sheet", sheet.getSheetName());
                List<String> headers = new ArrayList<>();
                Row hr = sheet.getRow(0);
                if (hr != null) {
                    for (int c = 0; c < Math.min(hr.getLastCellNum(), 40); c++) {
                        headers.add(fmt.formatCellValue(hr.getCell(c)).trim());
                    }
                }
                out.put("headers", headers);
                List<List<String>> rows = new ArrayList<>();
                int total = sheet.getLastRowNum();
                for (int r = 1; r <= Math.min(total, 100); r++) {
                    Row row = sheet.getRow(r);
                    List<String> vals = new ArrayList<>();
                    for (int c = 0; c < headers.size(); c++) {
                        vals.add(row == null ? "" : fmt.formatCellValue(row.getCell(c)).trim());
                    }
                    rows.add(vals);
                }
                out.put("rows", rows);
                out.put("totalRows", total);
            }
        } else {
            out.put("binary", true);
            if ("json".equals(ext)) {
                String content = new String(Files.readAllBytes(f.toPath()), "UTF-8");
                out.put("jsonPreview", content.length() > 4096 ? content.substring(0, 4096) + "...(截断)" : content);
            }
        }
        return out;
    }

    @ApiOperation("从项目文件库带入任务数据(data类)")
    @PostMapping("/projects/{pid}/tasks/{tid}/files/from-library")
    @RequirePermission(Permission.CREATE)
    public Result<EngineModels.ModelingTask> useLibraryFile(@PathVariable("pid") String pid,
                                                            @PathVariable("tid") String tid,
                                                            @RequestParam("kind") String kind,
                                                            @RequestParam("fileId") Long fileId) {
        try {
            EngineModels.ModelingTask t = store.getTask(pid, tid);
            if (t == null) return Result.error("任务不存在");
            String denied = accessDenied(store.getProject(pid));
            if (denied != null) return Result.error(denied);
            FileLibraryEntity e = fileLibraryMetaService.queryById(fileId);
            if (e == null || !"data".equals(e.getCategory())) {
                return Result.error("文件库条目不存在或不是数据类文件");
            }
            File src = fileBackupService.resolve(e);
            File dir = new File(store.taskWorkDir(pid, tid), "input");
            if (!dir.exists() && !dir.mkdirs()) return Result.error("无法创建输入目录");
            File destFile = new File(dir, e.getName());
            Files.copy(src.toPath(), destFile.toPath(),
                    java.nio.file.StandardCopyOption.REPLACE_EXISTING);
            String path = destFile.getAbsolutePath();
            if ("test".equals(kind)) {
                t.setTestFile(path);
            } else if ("identification".equals(kind)) {
                t.setIdentificationFile(path);
            } else if ("validation".equals(kind)) {
                t.setValidationFile(path);
            } else if ("history".equals(kind)) {
                t.setHistoryFile(path);
            } else if ("historyTest".equals(kind)) {
                t.setHistoryTestFile(path);
            } else {
                t.setTrainingFile(path);
            }
            t.setMessage("已从项目文件库带入: " + e.getName());
            return Result.success(store.saveTask(t));
        } catch (Exception e) {
            log.error("从文件库带入失败", e);
            return Result.error("带入失败: " + e.getMessage());
        }
    }

    /** 校验xlsx第一个工作表表头是否包含指定列(DataFormatter转字符串,大小写不敏感)。 */
    private boolean excelHasColumn(File xlsx, String columnName) {
        try (InputStream in = Files.newInputStream(xlsx.toPath()); Workbook wb = WorkbookFactory.create(in)) {
            Sheet sheet = wb.getSheetAt(0);
            Row hr = sheet.getRow(0);
            if (hr == null) return false;
            DataFormatter fmt = new DataFormatter();
            for (int c = 0; c < hr.getLastCellNum(); c++) {
                if (columnName.equalsIgnoreCase(fmt.formatCellValue(hr.getCell(c)).trim())) return true;
            }
            return false;
        } catch (Exception e) {
            log.warn("表头校验读取失败: {}", xlsx, e);
            return true; // 读取失败不阻断,交由算法侧报具体错误
        }
    }

    @ApiOperation("发起辨识(F-01: Start_TC24_00_Offline,task=identify)")
    @PostMapping("/projects/{pid}/tasks/{tid}/run")
    @RequirePermission(Permission.CREATE)
    public Result<EngineModels.ModelingTask> runTask(@PathVariable("pid") String pid,
                                                     @PathVariable("tid") String tid) {
        try {
            EngineModels.ModelingTask t = store.getTask(pid, tid);
            if (t == null) return Result.error("任务不存在");
            String denied = accessDenied(store.getProject(pid));
            if (denied != null) return Result.error(denied);
            boolean f3Family = "flight_steady".equals(t.getKind()) || "flight_transient".equals(t.getKind())
                    || "evolution".equals(t.getKind());
            if (!f3Family && (t.getTrainingFile() == null || t.getTrainingFile().isEmpty())) {
                return Result.error("请先上传训练数据");
            }
            if ("flight_steady".equals(t.getKind()) || "flight_transient".equals(t.getKind())) {
                // F3 B阶段: 需A阶段确认凭据
                if (t.getConfirmationFile() == null || t.getConfirmationFile().isEmpty()) {
                    return Result.error("请先完成数据意图确认,再执行建模");
                }
                return Result.success(f3FlightService.run(t));
            }
            if ("evolution".equals(t.getKind())) {
                // F-06 自演化整批执行(适配器内逐架次自动确认,无需A阶段凭据)
                return Result.success(f3FlightService.run(t));
            }
            if ("transient_update".equals(t.getKind())) {
                if (t.getTransientUpstreamFile() == null) return Result.error("缺少上游TC27组合稳态模型");
                if (t.getHistoryFile() == null || t.getHistoryFile().isEmpty()) {
                    return Result.error("请先上传瞬态训练历程Excel");
                }
                if (t.getPrepMessage() == null || t.getPrepMessage().isEmpty()) {
                    return Result.error("请先完成数据准备(事件选段+05),再执行辨识");
                }
                return Result.success(tc24Service.startTc27TransientRun(t));
            }
            if ("steady_update".equals(t.getKind())) {
                // TC27执行:须先完成05预览(prepMessage非空),再execute跑06
                if (t.getUpstreamModelFile() == null) return Result.error("缺少上游TC24父模型");
                if (t.getHistoryFile() == null || t.getHistoryFile().isEmpty()) {
                    return Result.error("请先上传新增试车历程");
                }
                if (t.getPrepMessage() == null || t.getPrepMessage().isEmpty()) {
                    return Result.error("请先完成数据准备(05预览),再执行更新");
                }
                return Result.success(tc24Service.startTc27Run(t));
            }
            // 不再按状态拦截重复发起:停止受理即落终态后允许立刻重新辨识,
            // 旧执行由运行代数守卫过期,不会写回覆盖新一次运行
            tc24Service.runIdentification(t);
            return Result.success(t);
        } catch (IOException e) {
            log.error("发起辨识失败", e);
            return Result.error("发起辨识失败: " + e.getMessage());
        }
    }

    @ApiOperation("任务状态(含日志尾部)")
    @GetMapping("/projects/{pid}/tasks/{tid}/status")
    @RequirePermission(Permission.READ)
    public Result<Map<String, Object>> taskStatus(@PathVariable("pid") String pid,
                                                  @PathVariable("tid") String tid) {
        try {
            EngineModels.ModelingTask t = store.getTask(pid, tid);
            if (t == null) return Result.error("任务不存在");
            String denied = accessDenied(store.getProject(pid));
            if (denied != null) return Result.error(denied);
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("task", t);
            // F3/自演化任务的运行日志在 F3FlightService 缓冲中,稳态/TC27 在 Tc24Service;按非空取用
            java.util.List<String> tail = tc24Service.logTail(tid);
            if (tail == null || tail.isEmpty()) tail = f3FlightService.logTail(tid);
            out.put("logTail", tail);
            return Result.success(out);
        } catch (IOException e) {
            return Result.error("读取任务失败: " + e.getMessage());
        }
    }

    @ApiOperation("数据准备(F-01 preview:解析工况与分组,真实MATLAB执行)")
    @PostMapping("/projects/{pid}/tasks/{tid}/prepare")
    @RequirePermission(Permission.CREATE)
    public Result<EngineModels.ModelingTask> prepareTask(@PathVariable("pid") String pid,
                                                         @PathVariable("tid") String tid) {
        try {
            EngineModels.ModelingTask t = store.getTask(pid, tid);
            if (t == null) return Result.error("任务不存在");
            String denied = accessDenied(store.getProject(pid));
            if (denied != null) return Result.error(denied);
            boolean f3Family = "flight_steady".equals(t.getKind()) || "flight_transient".equals(t.getKind())
                    || "evolution".equals(t.getKind());
            if (!f3Family && (t.getTrainingFile() == null || t.getTrainingFile().isEmpty())) {
                return Result.error("请先上传训练数据");
            }
            if ("flight_steady".equals(t.getKind()) || "flight_transient".equals(t.getKind())) {
                // F3 A阶段: 数据意图确认(禁父模型);必需训练飞参Excel
                if (t.getIdentificationFile() == null || t.getIdentificationFile().isEmpty()) {
                    return Result.error("请先上传飞参训练Excel(Data表)");
                }
                return Result.success(f3FlightService.prepare(t));
            }
            if ("evolution".equals(t.getKind())) {
                // F-06 自演化:准备=check(输入/父依赖核验,不计算)
                if (t.getIdentificationFile() == null || t.getIdentificationFile().isEmpty()) {
                    return Result.error("请先上传根架次测量Excel(Data表)");
                }
                return Result.success(f3FlightService.prepare(t));
            }
            if ("transient_update".equals(t.getKind())) {
                if (t.getTransientUpstreamFile() == null) return Result.error("缺少上游TC27组合稳态模型");
                if (t.getHistoryFile() == null || t.getHistoryFile().isEmpty()) {
                    return Result.error("请先上传瞬态训练历程Excel(20列)");
                }
                return Result.success(tc24Service.startTc27TransientPrepare(t));
            }
            if ("steady_update".equals(t.getKind())) {
                // TC27(F-02):准备=05预览;必需父模型与新增历程
                if (t.getUpstreamModelFile() == null) return Result.error("缺少上游TC24父模型");
                if (t.getHistoryFile() == null || t.getHistoryFile().isEmpty()) {
                    return Result.error("请先上传新增试车历程");
                }
                return Result.success(tc24Service.startTc27Prepare(t));
            }
            return Result.success(tc24Service.runPrepare(t));
        } catch (IOException e) {
            return Result.error("发起数据准备失败: " + e.getMessage());
        }
    }

    @ApiOperation("查看本次下发给程序的配置(适配器config.json)")
    @GetMapping("/projects/{pid}/tasks/{tid}/config")
    @RequirePermission(Permission.READ)
    public Result<Map<String, Object>> taskConfig(@PathVariable("pid") String pid,
                                                  @PathVariable("tid") String tid) {
        try {
            String denied = accessDenied(store.getProject(pid));
            if (denied != null) return Result.error(denied);
            Map<String, Object> cfg = tc24Service.readConfig(pid, tid);
            if (cfg == null) return Result.error("尚未生成配置;请先上传数据并发起辨识或准备");
            return Result.success(cfg);
        } catch (IOException e) {
            return Result.error("读取配置失败: " + e.getMessage());
        }
    }

    @ApiOperation("更新任务配置(飞参建模:求解路径/数据用途/正则化强度)")
    @PostMapping("/projects/{pid}/tasks/{tid}/config")
    @RequirePermission(Permission.CREATE)
    public Result<EngineModels.ModelingTask> updateTaskConfig(@PathVariable("pid") String pid,
                                                             @PathVariable("tid") String tid,
                                                             @RequestBody Map<String, Object> body) {
        try {
            EngineModels.ModelingTask t = store.getTask(pid, tid);
            if (t == null) return Result.error("任务不存在");
            String denied = accessDenied(store.getProject(pid));
            if (denied != null) return Result.error(denied);
            Object pr = body.get("parentRoute");
            if (pr != null && !String.valueOf(pr).isEmpty()) t.setParentRoute(String.valueOf(pr));
            Object dm = body.get("dataMethod");
            if (dm != null && !String.valueOf(dm).isEmpty()) t.setDataMethod(String.valueOf(dm));
            Object rs = body.get("regularizationStrength");
            if (rs instanceof Number) t.setRegularizationStrength(((Number) rs).doubleValue());
            Object inc = body.get("includeSmallHistory");
            if (inc != null) {
                boolean nv = Boolean.parseBoolean(String.valueOf(inc));
                // TC27预处理设置变化:旧准备/运行输出归档,下次准备/辨识将全新执行
                // (程序合同:preview要求输出目录不存在;旧prepared数据与新设置身份校验不符会拒绝执行)
                if ("steady_update".equals(t.getKind()) && t.getIncludeSmallHistory() != null
                        && t.getIncludeSmallHistory() != nv) {
                    archiveStaleTc27Output(pid, tid);
                }
                t.setIncludeSmallHistory(nv);
            }
            t.setMessage("配置已更新:路径=" + t.getParentRoute() + " / 数据=" + t.getDataMethod()
                    + " / 小幅段=" + (Boolean.TRUE.equals(t.getIncludeSmallHistory()) ? "使用" : "不使用"));
            return Result.success(store.saveTask(t));
        } catch (IOException e) {
            return Result.error("配置保存失败: " + e.getMessage());
        }
    }

    /** TC27预处理设置变化后归档旧输出目录(tc27 → tc27_stale_<ts>),保留审计,下次全新准备。 */
    private void archiveStaleTc27Output(String pid, String tid) {
        try {
            File workDir = store.taskWorkDir(pid, tid);
            File old = new File(workDir, "tc27");
            if (old.exists()) {
                File backup = new File(workDir, "tc27_stale_" + System.currentTimeMillis());
                if (old.renameTo(backup)) {
                    log.info("TC27输出目录已归档(预处理设置变化): {} -> {}", old.getName(), backup.getName());
                } else {
                    log.warn("TC27输出目录归档失败: {}", old.getAbsolutePath());
                }
            }
        } catch (Exception e) {
            log.warn("TC27输出目录归档异常: task={}", tid, e);
        }
    }

    @ApiOperation("导入模型文件(Excel交付工作簿+可选identity.json,上传并登记为模型成果)")
    @PostMapping("/projects/{pid}/models/import")
    @RequirePermission(Permission.CREATE)
    public Result<EngineModels.ModelAsset> importModel(@PathVariable("pid") String pid,
                                                       @RequestParam("file") MultipartFile file,
                                                       @RequestParam(value = "identityFile", required = false) MultipartFile identityFile) {
        try {
            EngineModels.EngineProject p = store.getProject(pid);
            String denied = accessDenied(p);
            if (denied != null) return Result.error(denied);
            String safe = file.getOriginalFilename() == null ? "model.xlsx"
                    : new File(file.getOriginalFilename()).getName();
            if (!safe.toLowerCase().endsWith(".xlsx") && !safe.toLowerCase().endsWith(".xls")) {
                return Result.error("仅支持 Excel 模型文件(.xlsx/.xls);交付合同为 Excel 工作簿+identity.json");
            }
            File dir = p.getWorkdir() != null && !p.getWorkdir().isEmpty()
                    ? new File(new File(p.getWorkdir()), "models")
                    : new File(store.projectDir(pid), "models");
            if (!dir.exists() && !dir.mkdirs()) return Result.error("无法创建模型目录");
            File dest = new File(dir, safe);
            file.transferTo(dest);

            EngineModels.ModelAsset m = new EngineModels.ModelAsset();
            m.setProjectId(pid);
            String stem = safe.replaceAll("\\.(xlsx|xls)$", "");
            m.setName(stem);
            m.setSourceBusiness("导入模型");
            m.setStage("导入");
            m.setRoute("—");
            m.setEngineId(p.getEngineId());
            m.setDeliveryWorkbookFile(dest.getAbsolutePath());
            m.setResultStatus("已导入");
            if (identityFile != null && !identityFile.isEmpty()) {
                String iname = new File(identityFile.getOriginalFilename() == null
                        ? "identity.json" : identityFile.getOriginalFilename()).getName();
                File idest = new File(dir, iname);
                identityFile.transferTo(idest);
                m.setIdentityFile(idest.getAbsolutePath());
            }
            // 模型交付工作簿自动登记进项目文件库(model类)
            try {
                FileLibraryEntity entry = new FileLibraryEntity();
                entry.setProjectId(pid);
                entry.setCategory("model");
                entry.setKind("交付工作簿");
                entry.setRefId(m.getId());
                registerLibraryEntry(entry, dest, "交付工作簿");
            } catch (Exception ex) {
                log.warn("导入模型自动入库失败(不影响导入): {}", safe, ex);
            }
            return Result.success(store.saveModel(m));
        } catch (Exception e) {
            log.error("导入模型失败", e);
            return Result.error("导入模型失败: " + e.getMessage());
        }
    }

    @ApiOperation("全局MATLAB日志尾(工作台底部状态栏滚动显示)")
    @GetMapping("/engine-log")
    @RequirePermission(Permission.READ)
    public Result<List<String>> engineLog(@RequestParam(value = "n", defaultValue = "20") int n) {
        return Result.success(com.tsinghua.engine.MatlabLogRing.tail(Math.min(Math.max(n, 1), 300)));
    }

    @ApiOperation("请求停止辨识")
    @PostMapping("/projects/{pid}/tasks/{tid}/stop")
    @RequirePermission(Permission.CREATE)
    public Result<Boolean> stopTask(@PathVariable("pid") String pid,
                                    @PathVariable("tid") String tid) {
        try {
            String denied = accessDenied(store.getProject(pid));
            if (denied != null) return Result.error(denied);
        } catch (IOException e) {
            return Result.error("读取项目失败: " + e.getMessage());
        }
        boolean ok = tc24Service.requestStop(pid, tid);
        return ok ? Result.success(true) : Result.error("当前没有可停止的辨识执行");
    }

    @ApiOperation("发起可选UQ评估(F-07-TC24: Start_TC24_07,method=B|C|D,particleCount=512|1024)")
    @PostMapping("/projects/{pid}/tasks/{tid}/uq")
    @RequirePermission(Permission.CREATE)
    public Result<EngineModels.UqRecord> runUq(@PathVariable("pid") String pid,
                                               @PathVariable("tid") String tid,
                                               @RequestParam(value = "method", defaultValue = "B") String method,
                                               @RequestBody(required = false) Map<String, Object> body) {
        try {
            EngineModels.ModelingTask t = store.getTask(pid, tid);
            if (t == null) return Result.error("任务不存在");
            String denied = accessDenied(store.getProject(pid));
            if (denied != null) return Result.error(denied);
            if (!EngineModels.ModelingTask.ST_COMPLETED.equals(t.getStatus())) {
                return Result.error("请先完成确定性辨识,再发起不确定性评估");
            }
            if (t.getTrainingFile() == null || t.getTrainingFile().isEmpty()) {
                return Result.error("缺少训练数据");
            }
            if (t.getUqStatus() != null && ("EXECUTING".equals(t.getUqStatus()) || "PREPARING".equals(t.getUqStatus()))) {
                return Result.error("UQ评估正在执行中,不能重复发起");
            }
            // 待评估模型:优先按 modelAssetId 取已登记模型成果;未指定时取本任务最新登记
            String modelAssetId = body == null ? null : (String) body.get("modelAssetId");
            EngineModels.ModelAsset asset = null;
            List<EngineModels.ModelAsset> models = store.listModels(pid);
            for (EngineModels.ModelAsset m : models) {
                if (modelAssetId != null && modelAssetId.equals(m.getId())) { asset = m; break; }
                if (modelAssetId == null && tid.equals(m.getTaskId())) { asset = m; break; }
            }
            if (asset == null || asset.getDeliveryWorkbookFile() == null) {
                return Result.error("未找到已登记的模型成果;请先在建模结果页登记到模型成果");
            }
            String m = method == null ? "B" : method.trim().toUpperCase();
            if (!m.matches("[BCD]")) return Result.error("评估方法仅支持 B/C/D");
            Integer particleCount = null;
            if (body != null && body.get("particleCount") != null) {
                particleCount = Integer.parseInt(String.valueOf(body.get("particleCount")));
                if (particleCount != 512 && particleCount != 1024) {
                    return Result.error("粒子数仅支持 512 或 1024(程序合同 sht_tc24_b_config)");
                }
            }
            return Result.success(tc24Service.runUq(t, m, asset.getDeliveryWorkbookFile(),
                    particleCount, asset.getId()));
        } catch (Exception e) {
            log.error("发起UQ评估失败", e);
            return Result.error("发起UQ评估失败: " + e.getMessage());
        }
    }

    @ApiOperation("取消UQ评估(协作取消,结果作废)")
    @PostMapping("/projects/{pid}/tasks/{tid}/uq/stop")
    @RequirePermission(Permission.CREATE)
    public Result<Boolean> cancelUq(@PathVariable("pid") String pid,
                                    @PathVariable("tid") String tid) {
        try {
            EngineModels.ModelingTask t = store.getTask(pid, tid);
            if (t == null) return Result.error("任务不存在");
            String denied = accessDenied(store.getProject(pid));
            if (denied != null) return Result.error(denied);
            boolean ok = tc24Service.requestUqCancel(pid, tid);
            return ok ? Result.success(true) : Result.error("当前没有可取消的评估");
        } catch (IOException e) {
            return Result.error("取消UQ评估失败: " + e.getMessage());
        }
    }

    @ApiOperation("UQ评估记录列表(一份模型可多份评估)")
    @GetMapping("/projects/{pid}/uq-records")
    @RequirePermission(Permission.READ)
    public Result<List<EngineModels.UqRecord>> listUqRecords(@PathVariable("pid") String pid) {
        try {
            String denied = accessDenied(store.getProject(pid));
            if (denied != null) return Result.error(denied);
            return Result.success(store.listUqRecords(pid));
        } catch (IOException e) {
            return Result.error("读取UQ记录失败: " + e.getMessage());
        }
    }

    @ApiOperation("UQ评估结果明细(参数区间表,task='read' 回读交付Excel)")
    @GetMapping("/projects/{pid}/uq-records/{uid}/detail")
    @RequirePermission(Permission.READ)
    public Result<Object> uqDetail(@PathVariable("pid") String pid,
                                   @PathVariable("uid") String uid) {
        try {
            String denied = accessDenied(store.getProject(pid));
            if (denied != null) return Result.error(denied);
            EngineModels.UqRecord r = store.getUqRecord(pid, uid);
            if (r == null) return Result.error("UQ记录不存在");
            if (!EngineModels.UqRecord.ST_COMPLETED.equals(r.getStatus())) {
                return Result.error("结果明细尚未生成或评估未完成");
            }
            // 明细JSON缺失时即时补生成(历史记录同样生效);交付Excel定位含delivery.workbookFile回补
            File detail = new File(r.getDetailFile() == null ? "" : r.getDetailFile());
            if (!detail.isFile()) {
                File excel = tc24Service.findUqDeliveryForRecord(pid, r);
                if (excel == null) return Result.error("未找到UQ交付Excel,无法生成结果明细");
                detail = tc24Service.readExcelDetail(pid, excel,
                        new File(excel.getParentFile(), r.getRunId() + "_dmg_uq_detail.json"));
                if (detail == null) return Result.error("结果明细生成失败(回读程序未通过),请查看运行日志");
                r.setDetailFile(detail.getAbsolutePath());
                store.saveUqRecord(r);
            }
            return Result.success(new com.fasterxml.jackson.databind.ObjectMapper()
                    .readValue(detail, Object.class));
        } catch (IOException e) {
            return Result.error("读取UQ明细失败: " + e.getMessage());
        }
    }

    @ApiOperation("辨识结果明细(曲线/节点表/逐通道误差,task='read' 回读 result_view.mat)")
    @GetMapping("/projects/{pid}/tasks/{tid}/result-detail")
    @RequirePermission(Permission.READ)
    public Result<Object> resultDetail(@PathVariable("pid") String pid,
                                       @PathVariable("tid") String tid) {
        try {
            String denied = accessDenied(store.getProject(pid));
            if (denied != null) return Result.error(denied);
            EngineModels.ModelingTask t = store.getTask(pid, tid);
            if (t == null) return Result.error("任务不存在");
            if (t.getResultDetailFile() == null || !new File(t.getResultDetailFile()).exists()) {
                return Result.error("结果明细尚未生成;辨识完成后自动生成");
            }
            return Result.success(new com.fasterxml.jackson.databind.ObjectMapper()
                    .readValue(new File(t.getResultDetailFile()), Object.class));
        } catch (IOException e) {
            return Result.error("读取结果明细失败: " + e.getMessage());
        }
    }

    @ApiOperation("把任务结果保存为模型成果")
    @PostMapping("/projects/{pid}/tasks/{tid}/save-model")
    @RequirePermission(Permission.CREATE)
    public Result<EngineModels.ModelAsset> saveModel(@PathVariable("pid") String pid,
                                                     @PathVariable("tid") String tid,
                                                     @RequestBody(required = false) Map<String, Object> body) {
        try {
            EngineModels.ModelingTask t = store.getTask(pid, tid);
            if (t == null) return Result.error("任务不存在");
            String denied = accessDenied(store.getProject(pid));
            if (denied != null) return Result.error(denied);
            if (!EngineModels.ModelingTask.ST_COMPLETED.equals(t.getStatus())) {
                return Result.error("任务尚未完成,不能保存模型成果");
            }
            String routeHint = "steady".equals(t.getRoute()) ? "steady" : "transient_instant";
            String excel;
            String sourceBusiness;
            String stage;
            String parentModelId = null;
            if ("flight_steady".equals(t.getKind()) || "flight_transient".equals(t.getKind())
                    || "evolution".equals(t.getKind())) {
                // F3飞参/自演化模型:delivery/model.xlsx;阶段按kind
                File f3Out = new File(store.taskWorkDir(pid, tid),
                        "flight_steady".equals(t.getKind()) ? "f3-steady"
                                : "flight_transient".equals(t.getKind()) ? "f3-transient" : "evolution");
                excel = findF3DeliveryWorkbook(f3Out);
                sourceBusiness = "evolution".equals(t.getKind()) ? "模型自演化"
                        : "flight_transient".equals(t.getKind()) ? "过渡态飞参建模" : "稳态飞参建模";
                stage = "evolution".equals(t.getKind()) ? "自演化"
                        : "flight_transient".equals(t.getKind()) ? "F3 瞬态" : "F3 稳态";
                parentModelId = t.getParentModelId();
            } else if ("transient_update".equals(t.getKind())) {
                // TC27瞬态更新模型:组合瞬态模型在tc27-transient目录;阶段2.7瞬态
                excel = findTc27DeliveryWorkbook(new File(store.taskWorkDir(pid, tid), "tc27-transient"));
                sourceBusiness = "瞬态试车建模";
                stage = "2.7 瞬态更新";
                parentModelId = t.getTransientUpstreamModelId();
            } else if ("steady_update".equals(t.getKind())) {
                // TC27更新模型:交付Excel在tc27目录;溯源父模型,阶段2.7数据更新
                excel = findTc27DeliveryWorkbook(new File(store.taskWorkDir(pid, tid), "tc27"));
                sourceBusiness = "新试车数据更新";
                stage = "2.7 数据更新";
                parentModelId = t.getUpstreamModelId();
            } else {
                excel = findDeliveryWorkbook(new File(store.taskWorkDir(pid, tid), "output"), routeHint);
                sourceBusiness = "稳态试车建模";
                stage = "2.4 基础建模";
            }
            EngineModels.ModelAsset m = new EngineModels.ModelAsset();
            m.setProjectId(pid);
            m.setTaskId(tid);
            m.setName(body != null && body.get("name") != null ? (String) body.get("name")
                    : t.getName() + "-模型");
            m.setSourceBusiness(sourceBusiness);
            m.setStage(stage);
            m.setRoute("steady".equals(t.getRoute()) ? "稳态方程" : "瞬态时刻方程");
            m.setDeliveryWorkbookFile(excel);
            m.setMetrics(t.getResult() == null ? new LinkedHashMap<>() : new LinkedHashMap<>(t.getResult()));
            // 溯源字段(图02-03):训练/测试数据、结果状态;测试可为空,不影响交付
            m.setTrainingFile(t.getTrainingFile());
            m.setTestFile(t.getTestFile());
            m.setParentModelId(parentModelId);
            m.setResultStatus(resolveResultStatus(t));
            EngineModels.EngineProject p = store.getProject(pid);
            m.setEngineId(p == null ? null : p.getEngineId());
            return Result.success(store.saveModel(m));
        } catch (IOException e) {
            return Result.error("保存模型成果失败: " + e.getMessage());
        }
    }

    /** TC27交付Excel:tc27目录深度2内最新.xlsx。 */
    private String findTc27DeliveryWorkbook(File dir) {
        if (!dir.isDirectory()) return null;
        File best = null;
        File[] level0 = dir.listFiles(File::isFile);
        if (level0 != null) for (File f : level0) {
            if (f.getName().toLowerCase().endsWith(".xlsx")
                    && (best == null || f.lastModified() > best.lastModified())) best = f;
        }
        File[] level1 = dir.listFiles(File::isDirectory);
        if (level1 != null) for (File d : level1) {
            File[] fs = d.listFiles((dd, n) -> n.toLowerCase().endsWith(".xlsx"));
            if (fs != null) for (File f : fs) {
                if (best == null || f.lastModified() > best.lastModified()) best = f;
            }
        }
        return best != null ? best.getAbsolutePath() : null;
    }

    /** F3交付Excel:结果子目录深度3内最新.xlsx。 */
    private String findF3DeliveryWorkbook(File dir) {
        if (!dir.isDirectory()) return null;
        File best = null;
        try (java.util.stream.Stream<Path> walk = java.nio.file.Files.walk(dir.toPath(), 3)) {
            best = walk.map(Path::toFile)
                    .filter(f -> f.isFile() && f.getName().toLowerCase().endsWith(".xlsx"))
                    .max(Comparator.comparingLong(File::lastModified))
                    .orElse(null);
        } catch (IOException e) {
            log.warn("扫描F3交付目录失败: {}", dir, e);
        }
        return best != null ? best.getAbsolutePath() : null;
    }

    /** 结果状态:已交付 | 诊断(未收敛但有效仍可交付,convergenceDoesNotBlockDelivery)。 */
    private String resolveResultStatus(EngineModels.ModelingTask t) {
        try {
            if (t.getResultDetailFile() != null) {
                File f = new File(t.getResultDetailFile());
                if (f.exists()) {
                    Map<String, Object> detail = new com.fasterxml.jackson.databind.ObjectMapper().readValue(f, Map.class);
                    Object acc = detail.get("acceptance");
                    if (acc instanceof Map) {
                        Object eligible = ((Map<?, ?>) acc).get("deliveryEligible");
                        if (Boolean.FALSE.equals(eligible)) return "诊断(未收敛但有效)";
                    }
                }
            }
        } catch (Exception ignore) {
        }
        return "已交付";
    }

    @ApiOperation("模型成果列表")
    @GetMapping("/projects/{pid}/models")
    @RequirePermission(Permission.READ)
    public Result<List<EngineModels.ModelAsset>> listModels(@PathVariable("pid") String pid) {
        try {
            String denied = accessDenied(store.getProject(pid));
            if (denied != null) return Result.error(denied);
            return Result.success(store.listModels(pid));
        } catch (IOException e) {
            return Result.error("读取模型成果失败: " + e.getMessage());
        }
    }

    @ApiOperation("下载模型成果交付文件(Excel)")
    @GetMapping("/projects/{pid}/models/{mid}/file")
    @RequirePermission(Permission.READ)
    public javax.servlet.http.HttpServletResponse downloadModelFile(@PathVariable("pid") String pid,
                                                                    @PathVariable("mid") String mid,
                                                                    javax.servlet.http.HttpServletResponse resp) throws IOException {
        String denied = accessDenied(store.getProject(pid));
        if (denied != null) {
            resp.sendError(javax.servlet.http.HttpServletResponse.SC_FORBIDDEN, denied);
            return resp;
        }
        EngineModels.ModelAsset m = null;
        for (EngineModels.ModelAsset it : store.listModels(pid)) {
            if (mid.equals(it.getId())) { m = it; break; }
        }
        File f = m == null || m.getDeliveryWorkbookFile() == null ? null : new File(m.getDeliveryWorkbookFile());
        if (f == null || !f.exists()) {
            resp.sendError(javax.servlet.http.HttpServletResponse.SC_NOT_FOUND, "交付文件不存在");
            return resp;
        }
        resp.setContentType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
        resp.setHeader("Content-Disposition", "attachment; filename=\""
                + new File(f.getName()).getName().replaceAll("[^A-Za-z0-9._-]", "_") + "\"");
        resp.setContentLengthLong(f.length());
        java.nio.file.Files.copy(f.toPath(), resp.getOutputStream());
        return resp;
    }

    @ApiOperation("发起输出预测(F-08;body: {inputs}单工况 或 {conditions:[{id,inputs}]}多工况, uqRecordId可选)")
    @PostMapping("/projects/{pid}/predict")
    @RequirePermission(Permission.CREATE)
    public Result<EngineModels.PredictionRecord> runPrediction(@PathVariable("pid") String pid,
                                                               @RequestParam("modelAssetId") String modelAssetId,
                                                               @RequestBody Map<String, Object> body) {
        try {
            String denied = accessDenied(store.getProject(pid));
            if (denied != null) return Result.error(denied);
            EngineModels.ModelAsset asset = null;
            for (EngineModels.ModelAsset m : store.listModels(pid)) {
                if (modelAssetId.equals(m.getId())) { asset = m; break; }
            }
            if (asset == null || asset.getDeliveryWorkbookFile() == null
                    || !new File(asset.getDeliveryWorkbookFile()).exists()) {
                return Result.error("模型交付文件不存在;请重新登记模型成果");
            }
            Map<String, Object> bodyMap = body == null ? new LinkedHashMap<>() : body;
            EngineModels.PredictionRecord rec = new EngineModels.PredictionRecord();
            rec.setProjectId(pid);
            rec.setModelAssetId(asset.getId());
            rec.setModelName(asset.getName());
            rec.setModelFile(asset.getDeliveryWorkbookFile());
            rec.setStatus(EngineModels.PredictionRecord.ST_EXECUTING);
            rec.setMessage("预测执行中");
            rec.setCreatedAt(System.currentTimeMillis());
            rec.setUqRecordId(bodyMap.get("uqRecordId") == null ? null
                    : String.valueOf(bodyMap.get("uqRecordId")));

            // 多工况 conditions:[{id,inputs}] ;单工况 inputs 兼容
            Object conds = bodyMap.get("conditions");
            List<Map<String, Object>> inputs = new ArrayList<>();
            if (conds instanceof List) {
                int i = 0;
                for (Object o : (List<?>) conds) {
                    if (!(o instanceof Map)) continue;
                    Map<?, ?> cm = (Map<?, ?>) o;
                    Map<String, Object> in = normalizePredictInputs((Map<String, Object>) cm.get("inputs"));
                    String id = cm.get("id") != null ? String.valueOf(cm.get("id"))
                            : String.format("P%02d", ++i);
                    in.put("_cid", id);
                    inputs.add(in);
                }
            }
            if (inputs.isEmpty()) {
                Map<String, Object> in = normalizePredictInputs(bodyMap);
                in.put("_cid", "P01");
                inputs.add(in);
            }
            for (Map<String, Object> in : inputs) {
                EngineModels.PredictionCondition c = new EngineModels.PredictionCondition();
                String cid = String.valueOf(in.remove("_cid"));
                c.setId(cid);
                c.setInputs(in);
                c.setStatus("EXECUTING");
                rec.getConditions().add(c);
            }
            if (!rec.getConditions().isEmpty()) {
                rec.setInputs(rec.getConditions().get(0).getInputs());
            }
            store.savePrediction(rec);
            return Result.success(tc24Service.runPrediction(rec));
        } catch (Exception e) {
            log.error("发起输出预测失败", e);
            return Result.error("发起输出预测失败: " + e.getMessage());
        }
    }

    @ApiOperation("UQ评估日志流(SSE推送实时日志)")
    @GetMapping(value = "/projects/{pid}/tasks/{tid}/uq-log-stream")
    @RequirePermission(Permission.READ)
    public SseEmitter uqLogStream(@PathVariable("pid") String pid,
                                  @PathVariable("tid") String tid) {
        try {
            SseEmitter emitter = new SseEmitter(Long.MAX_VALUE);
            tc24Service.subscribeUqLogs(tid, emitter);
            return emitter;
        } catch (Exception e) {
            log.error("创建UQ日志流失败", e);
            return new SseEmitter(0L);
        }
    }

    /** 补全 inletBoundaryMode(未显式给定时按字段推断),校验数值。 */
    private Map<String, Object> normalizePredictInputs(Map<String, Object> raw) {
        Map<String, Object> in = raw == null ? new LinkedHashMap<>() : new LinkedHashMap<>(raw);
        if (!in.containsKey("inletBoundaryMode")) {
            Object alt = in.get("Altitude");
            in.put("inletBoundaryMode", alt != null && !String.valueOf(alt).isEmpty() ? 3
                    : (in.containsKey("Pt1") ? 1 : 2));
        }
        return in;
    }

    @ApiOperation("下载预测输出Excel(按工况;cond缺省取最后一个完成的工况)")
    @GetMapping("/projects/{pid}/predictions/{recId}/export")
    @RequirePermission(Permission.READ)
    public javax.servlet.http.HttpServletResponse exportPrediction(@PathVariable("pid") String pid,
                                                                   @PathVariable("recId") String recId,
                                                                   @RequestParam(value = "cond", required = false) String cond,
                                                                   javax.servlet.http.HttpServletResponse resp) throws IOException {
        String denied = accessDenied(store.getProject(pid));
        if (denied != null) {
            resp.sendError(javax.servlet.http.HttpServletResponse.SC_FORBIDDEN, denied);
            return resp;
        }
        EngineModels.PredictionRecord target = null;
        for (EngineModels.PredictionRecord r : store.listPredictions(pid)) {
            if (recId.equals(r.getId())) { target = r; break; }
        }
        if (target == null) {
            resp.sendError(javax.servlet.http.HttpServletResponse.SC_NOT_FOUND, "预测记录不存在");
            return resp;
        }
        File excel = null;
        List<EngineModels.PredictionCondition> list = target.getConditions();
        if (list != null) {
            for (int i = list.size() - 1; i >= 0; i--) {
                EngineModels.PredictionCondition c = list.get(i);
                if (cond != null && !cond.isEmpty() && !cond.equals(c.getId())) continue;
                if (c.getExcelFile() != null && new File(c.getExcelFile()).exists()) { excel = new File(c.getExcelFile()); break; }
            }
        }
        if (excel == null) {
            resp.sendError(javax.servlet.http.HttpServletResponse.SC_NOT_FOUND, "该记录尚无输出Excel");
            return resp;
        }
        resp.setContentType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
        resp.setHeader("Content-Disposition", "attachment; filename=\""
                + excel.getName().replaceAll("[^A-Za-z0-9._-]", "_") + "\"");
        resp.setContentLengthLong(excel.length());
        java.nio.file.Files.copy(excel.toPath(), resp.getOutputStream());
        return resp;
    }

    @ApiOperation("输出预测记录列表")
    @GetMapping("/projects/{pid}/predictions")
    @RequirePermission(Permission.READ)
    public Result<List<EngineModels.PredictionRecord>> listPredictions(@PathVariable("pid") String pid) {
        try {
            String denied = accessDenied(store.getProject(pid));
            if (denied != null) return Result.error(denied);
            return Result.success(store.listPredictions(pid));
        } catch (IOException e) {
            return Result.error("读取预测记录失败: " + e.getMessage());
        }
    }

    /** 交付 Excel:优先 2p4_deterministic_<route>(路线必须与任务一致,否则UQ报RouteMismatch);递归查找。 */
    private String findDeliveryWorkbook(File outputDir, String routeHint) {
        File best = findWorkbookRecursive(outputDir, 0, routeHint);
        return best == null ? null : best.getAbsolutePath();
    }

    private File findWorkbookRecursive(File dir, int depth, String routeHint) {
        if (dir == null || depth > 4 || !dir.isDirectory()) return null;
        File routeMatch = null, fallback = null;
        File[] files = dir.listFiles();
        if (files == null) return null;
        for (File f : files) {
            if (f.isDirectory()) {
                File sub = findWorkbookRecursive(f, depth + 1, routeHint);
                if (sub != null && routeMatch == null) routeMatch = sub;
            } else if (f.getName().endsWith(".xlsx")) {
                String name = f.getName();
                if (name.startsWith("2p4_deterministic_" + routeHint)) return f;
                if (name.startsWith("2p4_deterministic") && routeMatch == null) routeMatch = f;
                if (fallback == null) fallback = f;
            }
        }
        return routeMatch != null ? routeMatch : fallback;
    }
}
