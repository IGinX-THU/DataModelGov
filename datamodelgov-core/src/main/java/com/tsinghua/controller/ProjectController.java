package com.tsinghua.controller;

import com.tsinghua.dto.ProjectTree;
import com.tsinghua.dto.ProjectsQueryRequest;
import com.tsinghua.entity.ParsingRulesEntity;
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
            @RequestParam("name") String name) {
        // 在后端构建树结构
        return Result.success(projectService.buildProjectTree(name));
    }

}
