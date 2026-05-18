package com.tsinghua.controller;

import com.tsinghua.entity.ProjectEntity;
import com.tsinghua.model.Result;
import com.tsinghua.service.ProjectService;
import com.tsinghua.auth.annotation.RequirePermission;
import com.tsinghua.auth.enums.Permission;
import com.tsinghua.auth.annotation.OperationLog;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@Api(tags = "项目管理")
@RestController
@RequestMapping("/api/project")
public class ProjectController {

    @Autowired
    private ProjectService projectService;

    @ApiOperation("创建项目")
    @PostMapping("/create")
    @RequirePermission(Permission.MODEL_CREATE)
    @OperationLog(value = "创建项目", type = OperationLog.OperationType.CREATE)
    public Result<ProjectEntity> createProject(@RequestBody ProjectEntity project) throws Exception {
        ProjectEntity result = projectService.createProject(project);
        return Result.success(result);
    }

    @ApiOperation("更新项目")
    @PostMapping("/update")
    @RequirePermission(Permission.MODEL_UPDATE)
    @OperationLog(value = "更新项目", type = OperationLog.OperationType.UPDATE)
    public Result<ProjectEntity> updateProject(@RequestBody ProjectEntity project) throws Exception {
        ProjectEntity result = projectService.updateProject(project);
        return Result.success(result);
    }

    @ApiOperation("删除项目")
    @DeleteMapping("/delete")
    @RequirePermission(Permission.MODEL_DELETE)
    @OperationLog(value = "删除项目", type = OperationLog.OperationType.DELETE)
    public Result<Void> deleteProject(@RequestParam("projectId") String projectId) throws Exception {
        projectService.deleteProject(projectId);
        return Result.success("删除成功");
    }

    @ApiOperation("查询项目")
    @GetMapping("/get")
    @RequirePermission(Permission.MODEL_READ)
    public Result<?> getProject(@RequestParam("projectId") String projectId) throws Exception {
        ProjectEntity project = projectService.getProject(projectId);
        if (project == null) {
            return Result.paramError( "项目不存在");
        }
        return Result.success(project);
    }

    @ApiOperation("查询所有项目")
    @GetMapping("/list")
    @RequirePermission(Permission.MODEL_READ)
    public Result<List<ProjectEntity>> getAllProjects() throws Exception {
        List<ProjectEntity> projects = projectService.getAllProjects();
        return Result.success(projects);
    }

    @ApiOperation("搜索项目")
    @GetMapping("/search")
    @RequirePermission(Permission.MODEL_READ)
    public Result<List<ProjectEntity>> searchProjects(
            @RequestParam(value = "keyword", required = false) String keyword,
            @RequestParam(value = "searchType", defaultValue = "all") String searchType) throws Exception {
        List<ProjectEntity> projects = projectService.searchProjects(keyword, searchType);
        return Result.success(projects);
    }

    @ApiOperation("导出项目")
    @GetMapping("/export")
    @RequirePermission(Permission.MODEL_READ)
    @OperationLog(value = "导出项目", type = OperationLog.OperationType.EXPORT, recordResult = false)
    public Result<String> exportProject(@RequestParam("projectId") String projectId) throws Exception {
        String projectJson = projectService.exportProject(projectId);
        return Result.success("导出成功", projectJson);
    }

    @ApiOperation("导入项目")
    @PostMapping("/import")
    @RequirePermission(Permission.MODEL_CREATE)
    @OperationLog(value = "导入项目", type = OperationLog.OperationType.CREATE)
    public Result<ProjectEntity> importProject(@RequestBody String projectJson) throws Exception {
        ProjectEntity project = projectService.importProject(projectJson);
        return Result.success(project);
    }
}
