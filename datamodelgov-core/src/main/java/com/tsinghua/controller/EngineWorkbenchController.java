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
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.io.File;
import java.io.IOException;
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

    /* ---------- 项目 ---------- */

    @ApiOperation("创建项目(类型/发动机/保存位置)")
    @PostMapping("/projects")
    @RequirePermission(Permission.CREATE)
    public Result<EngineModels.EngineProject> createProject(@RequestBody Map<String, Object> body) {
        EngineModels.EngineProject p = new EngineModels.EngineProject();
        p.setName((String) body.getOrDefault("name", "未命名项目"));
        p.setType((String) body.getOrDefault("type", "个性化自适应建模"));
        p.setEngineId((String) body.getOrDefault("engineId", "E-001"));
        p.setLocation((String) body.get("location"));
        p.setDesc((String) body.get("desc"));
        try {
            return Result.success(store.saveProject(p));
        } catch (IOException e) {
            log.error("创建项目失败", e);
            return Result.error("创建项目失败: " + e.getMessage());
        }
    }

    @ApiOperation("项目列表")
    @GetMapping("/projects")
    @RequirePermission(Permission.READ)
    public Result<List<EngineModels.EngineProject>> listProjects() {
        try {
            return Result.success(store.listProjects());
        } catch (IOException e) {
            return Result.error("读取项目失败: " + e.getMessage());
        }
    }

    @ApiOperation("项目详情(含任务与模型)")
    @GetMapping("/projects/detail")
    @RequirePermission(Permission.READ)
    public Result<Map<String, Object>> projectDetail(@RequestParam("projectId") String pid) {
        try {
            EngineModels.EngineProject p = store.getProject(pid);
            if (p == null) return Result.error("项目不存在");
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
    public Result<EngineModels.ModelingTask> createTask(@RequestParam("projectId") String pid,
                                                        @RequestBody Map<String, Object> body) {
        try {
            EngineModels.EngineProject p = store.getProject(pid);
            if (p == null) return Result.error("项目不存在");
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
    public Result<EngineModels.ModelingTask> uploadFiles(@RequestParam("projectId") String pid,
                                                         @RequestParam("taskId") String tid,
                                                         @RequestParam("kind") String kind,
                                                         @RequestParam("file") MultipartFile file) {
        try {
            EngineModels.ModelingTask t = store.getTask(pid, tid);
            if (t == null) return Result.error("任务不存在");
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
    public Result<EngineModels.ModelingTask> runTask(@RequestParam("projectId") String pid,
                                                     @RequestParam("taskId") String tid) {
        try {
            EngineModels.ModelingTask t = store.getTask(pid, tid);
            if (t == null) return Result.error("任务不存在");
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
    public Result<Map<String, Object>> taskStatus(@RequestParam("projectId") String pid,
                                                  @RequestParam("taskId") String tid) {
        try {
            EngineModels.ModelingTask t = store.getTask(pid, tid);
            if (t == null) return Result.error("任务不存在");
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
    public Result<EngineModels.ModelingTask> prepareTask(@RequestParam("projectId") String pid,
                                                         @RequestParam("taskId") String tid) {
        try {
            EngineModels.ModelingTask t = store.getTask(pid, tid);
            if (t == null) return Result.error("任务不存在");
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
    public Result<Map<String, Object>> taskConfig(@RequestParam("projectId") String pid,
                                                  @RequestParam("taskId") String tid) {
        try {
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
    public Result<EngineModels.ModelAsset> importModel(@RequestParam("projectId") String pid,
                                                       @RequestParam("file") MultipartFile file) {
        try {
            EngineModels.EngineProject p = store.getProject(pid);
            if (p == null) return Result.error("项目不存在");
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
    public Result<Boolean> stopTask(@RequestParam("projectId") String pid,
                                    @RequestParam("taskId") String tid) {
        return Result.success(tc24Service.requestStop(pid, tid));
    }

    @ApiOperation("发起可选UQ评估(F-07-TC24: Start_TC24_07,method=B|C|D)")
    @PostMapping("/projects/{pid}/tasks/{tid}/uq")
    @RequirePermission(Permission.CREATE)
    public Result<EngineModels.ModelingTask> runUq(@RequestParam("projectId") String pid,
                                                   @RequestParam("taskId") String tid,
                                                   @RequestParam(value = "method", defaultValue = "B") String method,
                                                   @RequestBody(required = false) Map<String, Object> body) {
        try {
            EngineModels.ModelingTask t = store.getTask(pid, tid);
            if (t == null) return Result.error("任务不存在");
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
    public Result<EngineModels.ModelAsset> saveModel(@RequestParam("projectId") String pid,
                                                     @RequestParam("taskId") String tid,
                                                     @RequestBody(required = false) Map<String, Object> body) {
        try {
            EngineModels.ModelingTask t = store.getTask(pid, tid);
            if (t == null) return Result.error("任务不存在");
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
    public Result<List<EngineModels.ModelAsset>> listModels(@RequestParam("projectId") String pid) {
        try {
            return Result.success(store.listModels(pid));
        } catch (IOException e) {
            return Result.error("读取模型成果失败: " + e.getMessage());
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
