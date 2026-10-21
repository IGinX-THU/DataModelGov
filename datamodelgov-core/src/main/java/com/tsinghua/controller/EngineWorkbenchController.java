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
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.io.File;
import java.io.IOException;
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
    private Tc24Service tc24Service;

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
            p = store.saveProject(p);
            metaService.save(new com.tsinghua.entity.EngineProjectEntity()
                    .setId(Long.parseLong(p.getId()))
                    .setName(p.getName())
                    .setType(p.getType())
                    .setEngineId(p.getEngineId())
                    .setLocation(p.getLocation())
                    .setWorkdir(p.getWorkdir())
                    .setDesc(p.getDesc())
                    .setOwner(p.getOwner())
                    .setCreateTime(p.getCreatedAt()));
            return Result.success(p);
        } catch (Exception e) {
            log.error("创建项目失败", e);
            return Result.error("创建项目失败: " + e.getMessage());
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

    @ApiOperation("项目详情(含任务与模型)")
    @GetMapping("/projects/detail")
    @RequirePermission(Permission.READ)
    public Result<Map<String, Object>> projectDetail(@RequestParam("projectId") String pid) {
        try {
            EngineModels.EngineProject p = store.getProject(pid);
            String denied = accessDenied(p);
            if (denied != null) return Result.error(denied);
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("project", p.toMap());
            out.put("tasks", store.listTasks(pid));
            out.put("models", store.listModels(pid));
            return Result.success(out);
        } catch (IOException e) {
            return Result.error("读取项目失败: " + e.getMessage());
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
            file.transferTo(dest);
            if ("test".equals(kind)) {
                t.setTestFile(dest.getAbsolutePath());
            } else {
                t.setTrainingFile(dest.getAbsolutePath());
            }
            t.setMessage("已上传" + ("test".equals(kind) ? "测试" : "训练") + "数据: " + safe);
            return Result.success(store.saveTask(t));
        } catch (Exception e) {
            log.error("上传任务数据失败", e);
            return Result.error("上传失败: " + e.getMessage());
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
            if (t.getTrainingFile() == null || t.getTrainingFile().isEmpty()) {
                return Result.error("请先上传训练数据");
            }
            if (!EngineModels.ModelingTask.ST_READY.equals(t.getStatus())
                    && !EngineModels.ModelingTask.ST_PREPARING.equals(t.getStatus())
                    && !EngineModels.ModelingTask.ST_FAILED.equals(t.getStatus())
                    && !EngineModels.ModelingTask.ST_COMPLETED.equals(t.getStatus())
                    && !EngineModels.ModelingTask.ST_STOPPED.equals(t.getStatus())) {
                return Result.error("任务正在执行中,不能重复发起");
            }
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
            out.put("logTail", tc24Service.logTail(tid));
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
            if (t.getTrainingFile() == null || t.getTrainingFile().isEmpty()) {
                return Result.error("请先上传训练数据");
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

    @ApiOperation("导入模型文件(上传到项目目录并登记为模型成果)")
    @PostMapping("/projects/{pid}/models/import")
    @RequirePermission(Permission.CREATE)
    public Result<EngineModels.ModelAsset> importModel(@PathVariable("pid") String pid,
                                                       @RequestParam("file") MultipartFile file) {
        try {
            EngineModels.EngineProject p = store.getProject(pid);
            String denied = accessDenied(p);
            if (denied != null) return Result.error(denied);
            String safe = file.getOriginalFilename() == null ? "model.xlsx"
                    : new File(file.getOriginalFilename()).getName();
            if (!safe.toLowerCase().endsWith(".xlsx") && !safe.toLowerCase().endsWith(".xls")) {
                return Result.error("仅支持 Excel 模型文件(.xlsx/.xls)");
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
            return Result.success(store.saveModel(m));
        } catch (Exception e) {
            log.error("导入模型失败", e);
            return Result.error("导入模型失败: " + e.getMessage());
        }
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
        return Result.success(tc24Service.requestStop(pid, tid));
    }

    @ApiOperation("发起可选UQ评估(F-07-TC24: Start_TC24_07,method=B|C|D)")
    @PostMapping("/projects/{pid}/tasks/{tid}/uq")
    @RequirePermission(Permission.CREATE)
    public Result<EngineModels.ModelingTask> runUq(@PathVariable("pid") String pid,
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
            return Result.success(tc24Service.runUq(t, m, asset.getDeliveryWorkbookFile()));
        } catch (IOException e) {
            log.error("发起UQ评估失败", e);
            return Result.error("发起UQ评估失败: " + e.getMessage());
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
            String excel = findDeliveryWorkbook(new File(store.taskWorkDir(pid, tid), "output"));
            EngineModels.ModelAsset m = new EngineModels.ModelAsset();
            m.setProjectId(pid);
            m.setTaskId(tid);
            m.setName(body != null && body.get("name") != null ? (String) body.get("name")
                    : t.getName() + "-模型");
            m.setSourceBusiness("稳态试车建模");
            m.setStage("2.4 基础建模");
            m.setRoute("steady".equals(t.getRoute()) ? "稳态方程" : "瞬态时刻方程");
            m.setDeliveryWorkbookFile(excel);
            m.setMetrics(t.getResult() == null ? new LinkedHashMap<>() : new LinkedHashMap<>(t.getResult()));
            EngineModels.EngineProject p = store.getProject(pid);
            m.setEngineId(p == null ? null : p.getEngineId());
            return Result.success(store.saveModel(m));
        } catch (IOException e) {
            return Result.error("保存模型成果失败: " + e.getMessage());
        }
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

    @ApiOperation("发起输出预测(F-08:Start_SteadyModelPredict,单工况确定性)")
    @PostMapping("/projects/{pid}/predict")
    @RequirePermission(Permission.CREATE)
    public Result<EngineModels.PredictionRecord> runPrediction(@PathVariable("pid") String pid,
                                                               @RequestParam("modelAssetId") String modelAssetId,
                                                               @RequestBody Map<String, Object> inputs) {
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
            Map<String, Object> in = inputs == null ? new LinkedHashMap<>() : inputs;
            if (!in.containsKey("inletBoundaryMode")) {
                Object alt = in.get("Altitude");
                in.put("inletBoundaryMode", alt != null && !String.valueOf(alt).isEmpty() ? 3
                        : (in.containsKey("Pt1") ? 1 : 2));
            }
            EngineModels.PredictionRecord rec = new EngineModels.PredictionRecord();
            rec.setProjectId(pid);
            rec.setModelAssetId(asset.getId());
            rec.setModelName(asset.getName());
            rec.setModelFile(asset.getDeliveryWorkbookFile());
            rec.setStatus(EngineModels.PredictionRecord.ST_EXECUTING);
            rec.setMessage("预测执行中");
            rec.setInputs(in);
            rec.setCreatedAt(System.currentTimeMillis());
            store.savePrediction(rec);
            return Result.success(tc24Service.runPrediction(rec));
        } catch (IOException e) {
            log.error("发起输出预测失败", e);
            return Result.error("发起输出预测失败: " + e.getMessage());
        }
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

    private String findDeliveryWorkbook(File outputDir) {
        File[] files = outputDir.listFiles((d, n) -> n.endsWith(".xlsx"));
        if (files == null || files.length == 0) return null;
        File best = null;
        for (File f : files) {
            if (f.getName().startsWith("2p4_deterministic")) {
                best = f;
                break;
            }
            if (best == null) best = f;
        }
        return best == null ? null : best.getAbsolutePath();
    }
}
