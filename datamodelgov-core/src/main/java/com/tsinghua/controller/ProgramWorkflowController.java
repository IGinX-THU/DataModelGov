package com.tsinghua.controller;

import com.fasterxml.jackson.databind.JsonNode;
import com.tsinghua.auth.annotation.OperationLog;
import com.tsinghua.auth.annotation.RequirePermission;
import com.tsinghua.auth.enums.Permission;
import com.tsinghua.model.Result;
import com.tsinghua.service.ProgramWorkflowService;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.Map;

@Api(tags = "MATLAB程序工作流")
@Slf4j
@RestController
@RequestMapping("/api/program/workflow")
public class ProgramWorkflowController {

    @Autowired
    private ProgramWorkflowService workflowService;

    @ApiOperation("列出程序包内可用数据文件")
    @GetMapping("/available-data")
    @RequirePermission(Permission.READ)
    public Result<?> listAvailableData(@RequestParam("name") String name,
                                       @RequestParam("version") String version,
                                       @RequestParam(value = "projectName", required = false) String projectName) {
        try {
            return Result.success(workflowService.listAvailableData(name, version, projectName));
        } catch (Exception e) {
            return failure("读取可用数据文件失败", e);
        }
    }

    @ApiOperation("预览数据文件内容")
    @GetMapping("/preview-data")
    @RequirePermission(Permission.READ)
    public Result<?> previewData(@RequestParam("name") String name,
                                 @RequestParam("version") String version,
                                 @RequestParam(value = "projectName", required = false) String projectName,
                                 @RequestParam("fileName") String fileName) {
        try {
            return Result.success(workflowService.previewData(name, version, projectName, fileName));
        } catch (Exception e) {
            return failure("预览数据文件失败", e);
        }
    }

    @ApiOperation("创建程序工作区")
    @PostMapping("/workspace")
    @RequirePermission(Permission.CREATE)
    @OperationLog(value = "创建程序工作区", type = OperationLog.OperationType.CREATE)
    public Result<?> createWorkspace(@RequestParam("name") String name,
                                     @RequestParam("version") String version,
                                     @RequestParam(value = "projectName", required = false) String projectName,
                                     @RequestBody(required = false) Map<String, Object> body) {
        try {
            String jobName = body != null ? String.valueOf(body.getOrDefault("jobName", "")) : "";
            String trainingData = body != null ? String.valueOf(body.getOrDefault("trainingData", "")) : "";
            String testData = body != null ? String.valueOf(body.getOrDefault("testData", "")) : "";
            String notes = body != null ? String.valueOf(body.getOrDefault("notes", "")) : "";
            if ("null".equals(jobName)) jobName = "";
            if ("null".equals(trainingData)) trainingData = "";
            if ("null".equals(testData)) testData = "";
            if ("null".equals(notes)) notes = "";
            return Result.success(workflowService.createWorkspace(name, version, projectName, jobName, trainingData, testData, notes));
        } catch (Exception e) {
            return failure("创建工作区失败", e);
        }
    }

    @ApiOperation("列出程序工作区")
    @GetMapping("/workspace")
    @RequirePermission(Permission.READ)
    public Result<?> listWorkspaces(@RequestParam("name") String name,
                                    @RequestParam("version") String version,
                                    @RequestParam(value = "projectName", required = false) String projectName) {
        try {
            return Result.success(workflowService.listWorkspaces(name, version, projectName));
        } catch (Exception e) {
            return failure("读取工作区失败", e);
        }
    }

    @ApiOperation("获取程序工作区")
    @GetMapping("/workspace/{id}")
    @RequirePermission(Permission.READ)
    public Result<?> getWorkspace(@PathVariable("id") String id,
                                  @RequestParam("name") String name,
                                  @RequestParam("version") String version,
                                  @RequestParam(value = "projectName", required = false) String projectName) {
        try {
            return Result.success(workflowService.getWorkspace(id, name, version, projectName));
        } catch (Exception e) {
            return failure("读取工作区失败", e);
        }
    }

    @ApiOperation("删除程序工作区")
    @DeleteMapping("/workspace/{id}")
    @RequirePermission(Permission.DELETE)
    @OperationLog(value = "删除程序工作区", type = OperationLog.OperationType.DELETE)
    public Result<?> deleteWorkspace(@PathVariable("id") String id,
                                     @RequestParam("name") String name,
                                     @RequestParam("version") String version,
                                     @RequestParam(value = "projectName", required = false) String projectName) {
        try {
            workflowService.deleteWorkspace(id, name, version, projectName);
            return Result.success("已删除");
        } catch (Exception e) {
            return failure("删除工作区失败", e);
        }
    }

    @ApiOperation("上传工作流数据集")
    @PostMapping(value = "/datasets/{workspaceId}", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @RequirePermission(Permission.CREATE)
    @OperationLog(value = "上传工作流数据集", type = OperationLog.OperationType.CREATE, recordParams = false)
    public Result<?> uploadDataset(@PathVariable("workspaceId") String workspaceId,
                                   @RequestPart("file") MultipartFile file,
                                   @RequestParam("datasetKey") String datasetKey,
                                   @RequestParam("name") String name,
                                   @RequestParam("version") String version,
                                   @RequestParam(value = "projectName", required = false) String projectName) {
        try {
            return Result.success(workflowService.uploadDataset(workspaceId, datasetKey, file, name, version, projectName));
        } catch (Exception e) {
            return failure("上传数据集失败", e);
        }
    }

    @ApiOperation("列出工作流数据集")
    @GetMapping("/datasets/{workspaceId}")
    @RequirePermission(Permission.READ)
    public Result<?> listDatasets(@PathVariable("workspaceId") String workspaceId,
                                  @RequestParam("name") String name,
                                  @RequestParam("version") String version,
                                  @RequestParam(value = "projectName", required = false) String projectName) {
        try {
            return Result.success(workflowService.listDatasets(workspaceId, name, version, projectName));
        } catch (Exception e) {
            return failure("读取数据集失败", e);
        }
    }

    @ApiOperation("查询工作区测量数据行")
    @GetMapping("/workspace/{workspaceId}/measure-data")
    @RequirePermission(Permission.READ)
    public Result<?> listMeasureData(@PathVariable("workspaceId") String workspaceId,
                                     @RequestParam("name") String name,
                                     @RequestParam("version") String version,
                                     @RequestParam(value = "projectName", required = false) String projectName) {
        try {
            return Result.success(workflowService.listMeasureData(workspaceId, name, version, projectName));
        } catch (Exception e) {
            return failure("查询测量数据失败", e);
        }
    }

    @ApiOperation("查询工作区调度变量行")
    @GetMapping("/workspace/{workspaceId}/schedule-vars")
    @RequirePermission(Permission.READ)
    public Result<?> listScheduleVars(@PathVariable("workspaceId") String workspaceId,
                                      @RequestParam("name") String name,
                                      @RequestParam("version") String version,
                                      @RequestParam(value = "projectName", required = false) String projectName) {
        try {
            return Result.success(workflowService.listScheduleVars(workspaceId, name, version, projectName));
        } catch (Exception e) {
            return failure("查询调度变量失败", e);
        }
    }

    @ApiOperation("提交工作流任务")
    @PostMapping("/tasks")
    @RequirePermission(Permission.CREATE)
    @OperationLog(value = "提交工作流任务", type = OperationLog.OperationType.CREATE)
    public Result<?> createTask(@RequestBody JsonNode request,
                                @RequestParam("name") String name,
                                @RequestParam("version") String version,
                                @RequestParam(value = "projectName", required = false) String projectName) {
        try {
            return Result.success(workflowService.createTask(request, name, version, projectName));
        } catch (Exception e) {
            return failure("提交任务失败", e);
        }
    }

    @ApiOperation("列出工作流任务")
    @GetMapping("/tasks")
    @RequirePermission(Permission.READ)
    public Result<?> listTasks(@RequestParam("workspaceId") String workspaceId,
                               @RequestParam("name") String name,
                               @RequestParam("version") String version,
                               @RequestParam(value = "projectName", required = false) String projectName) {
        try {
            return Result.success(workflowService.listTasks(workspaceId, name, version, projectName));
        } catch (Exception e) {
            return failure("读取任务列表失败", e);
        }
    }

    @ApiOperation("获取工作流任务")
    @GetMapping("/tasks/{id}")
    @RequirePermission(Permission.READ)
    public Result<?> getTask(@PathVariable("id") String id,
                             @RequestParam("name") String name,
                             @RequestParam("version") String version,
                             @RequestParam(value = "projectName", required = false) String projectName) {
        try {
            return Result.success(workflowService.getTask(id, name, version, projectName));
        } catch (Exception e) {
            return failure("读取任务失败", e);
        }
    }

    @ApiOperation("获取工作流任务日志")
    @GetMapping("/tasks/{id}/log")
    @RequirePermission(Permission.READ)
    public Result<?> getTaskLog(@PathVariable("id") String id,
                                @RequestParam("name") String name,
                                @RequestParam("version") String version,
                                @RequestParam(value = "projectName", required = false) String projectName) {
        try {
            return Result.success(workflowService.getTaskLog(id, name, version, projectName));
        } catch (Exception e) {
            return failure("读取任务日志失败", e);
        }
    }

    @ApiOperation("取消工作流任务")
    @PostMapping("/tasks/{id}/cancel")
    @RequirePermission(Permission.UPDATE)
    @OperationLog(value = "取消工作流任务", type = OperationLog.OperationType.UPDATE)
    public Result<?> cancelTask(@PathVariable("id") String id,
                                @RequestParam("name") String name,
                                @RequestParam("version") String version,
                                @RequestParam(value = "projectName", required = false) String projectName) {
        try {
            return Result.success(workflowService.cancelTask(id, name, version, projectName));
        } catch (Exception e) {
            return failure("取消任务失败", e);
        }
    }

    @ApiOperation("获取工作流结果")
    @GetMapping("/results/{taskId}")
    @RequirePermission(Permission.READ)
    public Result<?> getResult(@PathVariable("taskId") String taskId,
                               @RequestParam("name") String name,
                               @RequestParam("version") String version,
                               @RequestParam(value = "projectName", required = false) String projectName) {
        try {
            return Result.success(workflowService.getResult(taskId, name, version, projectName));
        } catch (Exception e) {
            return failure("读取结果失败", e);
        }
    }

    @ApiOperation("审核工作流结果")
    @PostMapping("/results/{taskId}/review")
    @RequirePermission(Permission.UPDATE)
    @OperationLog(value = "审核工作流结果", type = OperationLog.OperationType.UPDATE)
    public Result<?> reviewResult(@PathVariable("taskId") String taskId,
                                  @RequestBody JsonNode request,
                                  @RequestParam("name") String name,
                                  @RequestParam("version") String version,
                                  @RequestParam(value = "projectName", required = false) String projectName) {
        try {
            return Result.success(workflowService.reviewResult(taskId, request, name, version, projectName));
        } catch (Exception e) {
            return failure("审核结果失败", e);
        }
    }

    @ApiOperation("发布辨识模型")
    @PostMapping("/results/{taskId}/publish")
    @RequirePermission(Permission.UPDATE)
    @OperationLog(value = "发布辨识模型", type = OperationLog.OperationType.UPDATE)
    public Result<?> publishResult(@PathVariable("taskId") String taskId,
                                   @RequestParam("name") String name,
                                   @RequestParam("version") String version,
                                   @RequestParam(value = "projectName", required = false) String projectName) {
        try {
            return Result.success(workflowService.publishResult(taskId, name, version, projectName));
        } catch (Exception e) {
            return failure("发布结果失败", e);
        }
    }

    @ApiOperation("列出工作流产物")
    @GetMapping("/artifacts/{taskId}")
    @RequirePermission(Permission.READ)
    public Result<?> listArtifacts(@PathVariable("taskId") String taskId,
                                   @RequestParam("name") String name,
                                   @RequestParam("version") String version,
                                   @RequestParam(value = "projectName", required = false) String projectName) {
        try {
            return Result.success(workflowService.listArtifacts(taskId, name, version, projectName));
        } catch (Exception e) {
            return failure("读取产物失败", e);
        }
    }

    @ApiOperation("下载工作流产物")
    @GetMapping("/artifacts/{taskId}/{artifactId}")
    @RequirePermission(Permission.READ)
    @OperationLog(value = "下载工作流产物", type = OperationLog.OperationType.EXPORT, recordResult = false)
    public ResponseEntity<byte[]> downloadArtifact(@PathVariable("taskId") String taskId,
                                                   @PathVariable("artifactId") String artifactId,
                                                   @RequestParam("name") String name,
                                                   @RequestParam("version") String version,
                                                   @RequestParam(value = "projectName", required = false) String projectName) {
        try {
            ProgramWorkflowService.ArtifactDownload artifact = workflowService.getArtifact(
                    taskId, artifactId, name, version, projectName);
            String encoded = URLEncoder.encode(artifact.getFileName(), StandardCharsets.UTF_8.name()).replace("+", "%20");
            return ResponseEntity.ok()
                    .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename*=UTF-8''" + encoded)
                    .contentType(MediaType.APPLICATION_OCTET_STREAM)
                    .body(artifact.getBytes());
        } catch (Exception e) {
            log.warn("下载工作流产物失败: {}", e.getMessage());
            return ResponseEntity.badRequest().body(null);
        }
    }

    @ApiOperation("打包下载工作流任务全部产物")
    @GetMapping("/artifacts/{taskId}/package")
    @RequirePermission(Permission.READ)
    @OperationLog(value = "打包下载工作流产物", type = OperationLog.OperationType.EXPORT, recordResult = false)
    public ResponseEntity<byte[]> packageTask(@PathVariable("taskId") String taskId,
                                              @RequestParam("name") String name,
                                              @RequestParam("version") String version,
                                              @RequestParam(value = "projectName", required = false) String projectName) {
        try {
            byte[] zipBytes = workflowService.packageTask(taskId, name, version, projectName);
            String zipName = "workflow_task_" + taskId + ".zip";
            String encoded = URLEncoder.encode(zipName, StandardCharsets.UTF_8.name()).replace("+", "%20");
            return ResponseEntity.ok()
                    .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename*=UTF-8''" + encoded)
                    .contentType(MediaType.APPLICATION_OCTET_STREAM)
                    .body(zipBytes);
        } catch (Exception e) {
            log.warn("打包下载工作流产物失败: {}", e.getMessage());
            return ResponseEntity.badRequest().body(null);
        }
    }

    private Result<?> failure(String prefix, Exception e) {
        if (e instanceof IllegalArgumentException || e instanceof IllegalStateException || e instanceof SecurityException) {
            log.warn("{}: {}", prefix, e.getMessage());
        } else {
            log.error(prefix, e);
        }
        return Result.error(prefix + ": " + (e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage()));
    }
}
