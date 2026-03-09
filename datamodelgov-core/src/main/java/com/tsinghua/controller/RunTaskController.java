package com.tsinghua.controller;

import com.tsinghua.auth.annotation.RequirePermission;
import com.tsinghua.auth.enums.Permission;
import com.tsinghua.dto.RunTaskRequest;
import com.tsinghua.model.Result;
import com.tsinghua.service.RunTaskService;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Api(tags = "可视化分析")
@RestController
@RequestMapping("/api/task")
public class RunTaskController {

    @Autowired
    private RunTaskService runTaskService;

    @ApiOperation("触发任务")
    @PostMapping("/run")
    @RequirePermission(Permission.ASSOCIATION_TASK_RUN)
    public Result<Void> runTask(@RequestBody RunTaskRequest runTaskRequest) throws Exception {
        runTaskService.runTask(runTaskRequest);
        return Result.success("关联规则保存成功");
    }

}
