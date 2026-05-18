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
    @RequirePermission(Permission.CREATE)
    @OperationLog(value = "创建项目", type = OperationLog.OperationType.CREATE)
    public Result<ProjectEntity> createProject(@RequestBody ProjectEntity project) throws Exception {
        ProjectEntity result = projectService.createProject(project);
        return Result.success(result);
    }

}
