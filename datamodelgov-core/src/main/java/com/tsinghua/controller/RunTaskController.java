package com.tsinghua.controller;

import com.tsinghua.auth.annotation.RequirePermission;
import com.tsinghua.auth.enums.Permission;
import com.tsinghua.dto.RunTaskQueryRequest;
import com.tsinghua.dto.RunTaskRequest;
import com.tsinghua.entity.RunTaskEntity;
import com.tsinghua.model.Result;
import com.tsinghua.service.RunTaskService;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@Api(tags = "可视化分析")
@RestController
@RequestMapping("/api/task")
public class RunTaskController {

    @Autowired
    private RunTaskService runTaskService;

    @ApiOperation("触发任务")
    @PostMapping("/run")
    @RequirePermission(Permission.RUN_TASK_CREATE)
    public Result<RunTaskEntity> runTask(@RequestBody RunTaskRequest runTaskRequest) throws Exception {
        RunTaskEntity task = runTaskService.runTask(runTaskRequest);
        return Result.success("关联规则保存成功", task);
    }

    @ApiOperation("校验任务时间段唯一性")
    @PostMapping("/validate-uniqueness")
    @RequirePermission(Permission.RUN_TASK_CREATE)
    public Result<?> validateTaskUniqueness(@RequestBody RunTaskRequest request) {
        boolean isUnique = runTaskService.validateTaskUniqueness(request);
        if (isUnique) {
            return Result.success(true);
        } else {
            return Result.paramError("该规则在指定时间段已存在相同的运行任务");
        }
    }

    @ApiOperation("停止运行中的任务")
    @GetMapping("/stop")
    @RequirePermission(Permission.RUN_TASK_DELETE)
    public Result<Void> stopTask(@RequestParam("timestamp") Long timestamp) throws Exception {
        runTaskService.stopTask(timestamp);
        return Result.success("任务停止成功");
    }

    @ApiOperation("获取任务日志")
    @GetMapping("/log")
    @RequirePermission(Permission.RUN_TASK_READ)
    public Result<String> getTaskLog(@RequestParam("timestamp") Long timestamp) throws Exception {
        String log = runTaskService.getTaskLog(timestamp);
        return Result.success("操作成功", log);
    }

    @ApiOperation("分页查询运行任务")
    @PostMapping("/tasks/query")
    @RequirePermission(Permission.RUN_TASK_READ)
    public Result<List<RunTaskEntity>> queryTasks(@RequestBody RunTaskQueryRequest request) {
        List<RunTaskEntity> result = runTaskService.queryTasks(request);
        return Result.success(result);
    }

    @ApiOperation("查询运行任务总数")
    @PostMapping("/tasks/count")
    @RequirePermission(Permission.RUN_TASK_READ)
    public Result<Object> countTasks(@RequestBody RunTaskQueryRequest request) {
        Object count = runTaskService.countTasks(request);
        return Result.success(count);
    }

    @ApiOperation("运行任务详情")
    @GetMapping("/tasks/detail")
    @RequirePermission(Permission.RUN_TASK_READ)
    public Result<?> queryTask(
            @RequestParam("timestamp") Long timestamp) {
        RunTaskEntity result = runTaskService.queryTask(timestamp);
        if (result == null) {
            return Result.error("未找到指定的运行任务");
        }
        return Result.success(result);
    }

    @ApiOperation("删除运行任务")
    @DeleteMapping("/tasks/delete")
    @RequirePermission(Permission.RUN_TASK_DELETE)
    public Result<Void> deleteTask(
            @RequestParam("timestamp") Long timestamp) throws Exception {
        runTaskService.deleteTask(timestamp);
        return Result.success("操作成功");
    }

}
