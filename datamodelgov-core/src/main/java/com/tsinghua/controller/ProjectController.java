package com.tsinghua.controller;

import com.tsinghua.dto.ProjectExportRequest;
import com.tsinghua.dto.ProjectTree;
import com.tsinghua.dto.ProjectsQueryRequest;
import com.tsinghua.entity.ProjectEntity;
import com.tsinghua.model.Result;
import com.tsinghua.service.ProjectExportService;
import com.tsinghua.service.ProjectImportService;
import com.tsinghua.service.ProjectService;
import com.tsinghua.auth.annotation.RequirePermission;
import com.tsinghua.auth.enums.Permission;
import com.tsinghua.auth.annotation.OperationLog;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import javax.servlet.http.HttpServletResponse;
import java.util.List;
import java.util.Map;

@Api(tags = "项目管理")
@Slf4j
@RestController
@RequestMapping("/api/project")
public class ProjectController {

    @Autowired
    private ProjectService projectService;

    @Autowired
    private ProjectExportService projectExportService;

    @Autowired
    private ProjectImportService projectImportService;

    @ApiOperation("创建项目")
    @PostMapping("/create")
    @RequirePermission(Permission.CREATE)
    @OperationLog(value = "创建项目", type = OperationLog.OperationType.CREATE)
    public Result<ProjectEntity> createProject(@RequestBody ProjectEntity project) throws Exception {
        ProjectEntity result = projectService.createProject(project);
        return Result.success(result);
    }

    @ApiOperation("分页查询")
    @PostMapping("/query")
    @RequirePermission(Permission.READ)
    public Result<List<ProjectEntity>> queryProjects(@RequestBody ProjectsQueryRequest request) {
        List<ProjectEntity> result = projectService.queryProjects(request);
        return Result.success(result);
    }

    @ApiOperation("查询总数")
    @PostMapping("/count")
    @RequirePermission(Permission.READ)
    public Result<Object> countProjects(@RequestBody ProjectsQueryRequest request) {
        Object count = projectService.countProjects(request);
        return Result.success(count);
    }

    @ApiOperation("详情")
    @GetMapping("/detail")
    @RequirePermission(Permission.READ)
    public Result<?> queryProject(
            @RequestParam("createTime") Long createTime) {
        ProjectEntity result = projectService.findById(createTime);
        if (result == null) {
            return Result.error("未找到指定的解析规则");
        }
        return Result.success(result);
    }

    @ApiOperation("获取项目树形结构")
    @GetMapping("/tree")
    @RequirePermission(Permission.READ)
    public Result<ProjectTree> getProjectTree(
            @RequestParam("name") String name) throws Exception {
        // 在后端构建树结构
        return Result.success(projectService.buildProjectTree(name));
    }

    @ApiOperation("导入项目")
    @PostMapping(value = "/import", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @RequirePermission(Permission.CREATE)
    @OperationLog(value = "导入项目", type = OperationLog.OperationType.IMPORT)
    public Result<?> importProject(
            @RequestPart("file") MultipartFile file,
            @RequestParam(value = "projectName", required = false) String projectName) {
        try {
            Map<String, Object> result = projectImportService.importProject(file, projectName);
            return Result.success("项目导入成功", result);
        } catch (IllegalArgumentException e) {
            log.error("项目导入参数错误", e);
            return Result.paramError(e.getMessage());
        } catch (Exception e) {
            log.error("项目导入失败", e);
            return Result.error("项目导入失败: " + e.getMessage());
        }
    }

    @ApiOperation("导入项目资源")
    @PostMapping(value = "/import/{resourceType}", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @RequirePermission(Permission.CREATE)
    @OperationLog(value = "导入项目资源", type = OperationLog.OperationType.IMPORT)
    public Result<?> importProjectResource(
            @PathVariable("resourceType") String resourceType,
            @RequestPart("file") MultipartFile file,
            @RequestParam(value = "projectName", required = false) String projectName) {
        try {
            validateResourceType(resourceType);
            Map<String, Object> result = projectImportService.importProjectResource(file, projectName, resourceType);
            result.put("resourceType", resourceType);
            return Result.success("项目资源导入成功", result);
        } catch (IllegalArgumentException e) {
            log.error("项目资源导入参数错误", e);
            return Result.paramError(e.getMessage());
        } catch (Exception e) {
            log.error("项目资源导入失败", e);
            return Result.error("项目资源导入失败: " + e.getMessage());
        }
    }

    @ApiOperation("导出项目")
    @PostMapping("/export")
    @RequirePermission(Permission.READ)
    @OperationLog(value = "导出项目", type = OperationLog.OperationType.EXPORT, recordResult = false)
    public void exportProject(@RequestBody ProjectExportRequest request, HttpServletResponse response) {
        try {
            projectExportService.exportAllProject(request, response);
        } catch (IllegalArgumentException | SecurityException e) {
            log.error("项目导出参数或权限错误", e);
            writeExportError(response, HttpServletResponse.SC_BAD_REQUEST, e.getMessage());
        } catch (Exception e) {
            log.error("项目导出失败", e);
            writeExportError(response, HttpServletResponse.SC_INTERNAL_SERVER_ERROR, "项目导出失败: " + e.getMessage());
        }
    }

    @ApiOperation("导出项目资源")
    @PostMapping("/export/{resourceType}")
    @RequirePermission(Permission.READ)
    @OperationLog(value = "导出项目资源", type = OperationLog.OperationType.EXPORT, recordResult = false)
    public void exportProjectResource(
            @PathVariable("resourceType") String resourceType,
            @RequestParam("projectName") String projectName,
            HttpServletResponse response) {
        try {
            // 先获取 OutputStream 确保响应未被提交
            response.getOutputStream();
            projectExportService.exportResource(projectName, resourceType, response);
        } catch (IllegalArgumentException | SecurityException e) {
            log.error("项目资源导出参数或权限错误", e);
            writeExportError(response, HttpServletResponse.SC_BAD_REQUEST, e.getMessage());
        } catch (Exception e) {
            log.error("项目资源导出失败", e);
            writeExportError(response, HttpServletResponse.SC_INTERNAL_SERVER_ERROR, "项目资源导出失败: " + e.getMessage());
        }
    }

    private void validateResourceType(String resourceType) {
        if (resourceType == null) {
            throw new IllegalArgumentException("资源类型不能为空");
        }
        String type = resourceType.trim().toLowerCase();
        if (!"algorithm".equals(type) && !"algorithms".equals(type)
                && !"model".equals(type) && !"models".equals(type)
                && !"data".equals(type) && !"datas".equals(type)
                && !"simulation".equals(type) && !"simulations".equals(type)) {
            throw new IllegalArgumentException("不支持的资源类型: " + resourceType);
        }
    }

    private void writeExportError(HttpServletResponse response, int status, String message) {
        response.reset();
        response.setContentType("application/json;charset=UTF-8");
        response.setStatus(status);
        try {
            response.getOutputStream().write(
                    ("{\"success\":false,\"message\":\"" + message + "\"}").getBytes("UTF-8"));
            response.getOutputStream().flush();
        } catch (Exception ex) {
            log.error("写入错误响应失败", ex);
        }
    }

}
