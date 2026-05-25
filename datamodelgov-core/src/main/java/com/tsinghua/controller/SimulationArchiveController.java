package com.tsinghua.controller;

import com.tsinghua.entity.SimulationArchiveEntity;
import com.tsinghua.model.Result;
import com.tsinghua.service.SimulationArchiveService;
import com.tsinghua.service.SimulationExecutionService;
import com.tsinghua.auth.annotation.RequirePermission;
import com.tsinghua.auth.enums.Permission;
import com.tsinghua.auth.annotation.OperationLog;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

/**
 * 仿真档案控制器
 * 提供仿真档案的REST API接口
 */
@Slf4j
@RestController
@RequestMapping("/api/simulation")
@Api(tags = "仿真档案管理")
public class SimulationArchiveController {

    @Autowired
    private SimulationArchiveService simulationArchiveService;

    @Autowired
    private SimulationExecutionService simulationExecutionService;

    /**
     * 保存仿真档案（新增或编辑）
     */
    @ApiOperation("保存仿真档案")
    @PostMapping("/archives/save")
    @RequirePermission(Permission.PARSING_RULES_CREATE)
    @OperationLog(value = "保存仿真档案", type = OperationLog.OperationType.CREATE)
    public Result<Void> saveArchive(@RequestBody SimulationArchiveEntity archive) {
        try {
            simulationArchiveService.saveArchive(archive);
            return Result.success("仿真档案保存成功");
        } catch (Exception e) {
            log.error("保存仿真档案失败", e);
            return Result.error("保存失败: " + e.getMessage());
        }
    }

    /**
     * 查询仿真档案列表
     */
    @ApiOperation("查询仿真档案列表")
    @PostMapping("/archives/query")
    @RequirePermission(Permission.PARSING_RULES_READ)
    public Result<List<SimulationArchiveEntity>> queryArchives(
            @RequestParam(required = false) String name,
            @RequestParam(required = false) String projectName,
            @RequestParam(required = false) String owner,
            @RequestParam(required = false) Boolean status,
            @RequestParam(defaultValue = "1") Integer pageNum,
            @RequestParam(defaultValue = "10") Integer pageSize) {
        List<SimulationArchiveEntity> archives = simulationArchiveService.queryArchives(name, projectName, owner, status, pageNum, pageSize);
        return Result.success(archives);
    }

    /**
     * 查询仿真档案总数
     */
    @ApiOperation("查询仿真档案总数")
    @PostMapping("/archives/count")
    @RequirePermission(Permission.PARSING_RULES_READ)
    public Result<Object> countArchives(
            @RequestParam(required = false) String name,
            @RequestParam(required = false) String projectName,
            @RequestParam(required = false) String owner,
            @RequestParam(required = false) Boolean status) {
        Object count = simulationArchiveService.countArchives(name, projectName, owner, status);
        return Result.success(count);
    }

    /**
     * 查询仿真档案详情
     */
    @ApiOperation("查询仿真档案详情")
    @GetMapping("/archives/detail")
    @RequirePermission(Permission.PARSING_RULES_READ)
    public Result<?> getArchive(@RequestParam("createTime") Long createTime) {
        try {
            SimulationArchiveEntity archive = simulationArchiveService.queryArchive(createTime);
            if (archive != null) {
                return Result.success(archive);
            } else {
                return Result.error("未找到指定的仿真档案");
            }
        } catch (Exception e) {
            log.error("查询仿真档案详情失败", e);
            return Result.error("查询失败: " + e.getMessage());
        }
    }

    /**
     * 删除仿真档案
     */
    @ApiOperation("删除仿真档案")
    @DeleteMapping("/archives/delete")
    @RequirePermission(Permission.PARSING_RULES_DELETE)
    @OperationLog(value = "删除仿真档案", type = OperationLog.OperationType.DELETE)
    public Result<Void> deleteArchive(@RequestParam("createTime") Long createTime) {
        try {
            simulationArchiveService.deleteArchive(createTime);
            return Result.success("删除成功");
        } catch (Exception e) {
            log.error("删除仿真档案失败", e);
            return Result.error("删除失败: " + e.getMessage());
        }
    }

    /**
     * 校验名称唯一性
     */
    @ApiOperation("校验名称唯一性")
    @GetMapping("/archives/validate-name")
    @RequirePermission(Permission.PARSING_RULES_READ)
    public Result<?> validateNameUniqueness(@RequestParam("name") String name) {
        try {
            simulationArchiveService.validateNameUniqueness(name);
            return Result.success(true);
        } catch (Exception e) {
            log.error("校验名称唯一性失败", e);
            return Result.paramError(e.getMessage());
        }
    }

    /**
     * 复制仿真档案
     */
    @ApiOperation("复制仿真档案")
    @PostMapping("/archives/copy")
    @RequirePermission(Permission.PARSING_RULES_CREATE)
    @OperationLog(value = "复制仿真档案", type = OperationLog.OperationType.CREATE)
    public Result<SimulationArchiveEntity> copyArchive(
            @RequestParam("createTime") Long createTime,
            @RequestParam("newName") String newName) {
        try {
            SimulationArchiveEntity copy = simulationArchiveService.copyArchive(createTime, newName);
            return Result.success("复制成功", copy);
        } catch (Exception e) {
            log.error("复制仿真档案失败", e);
            throw new RuntimeException("复制失败: " + e.getMessage(), e);
        }
    }

    /**
     * 运行仿真（全量执行）
     */
    @ApiOperation("运行仿真")
    @PostMapping("/archives/run")
    @RequirePermission(Permission.PARSING_RULES_CREATE)
    @OperationLog(value = "运行仿真", type = OperationLog.OperationType.UPDATE)
    public Result<Void> runSimulation(@RequestParam("createTime") Long createTime) {
        return simulationExecutionService.runSimulation(createTime);
    }

    /**
     * 运行仿真（选择性执行，每个节点使用自己的时间窗口）
     */
    @ApiOperation("选择性运行仿真")
    @PostMapping("/archives/run-selective")
    @RequirePermission(Permission.PARSING_RULES_CREATE)
    @OperationLog(value = "选择性运行仿真", type = OperationLog.OperationType.UPDATE)
    public Result<Void> runSimulationSelective(
            @RequestParam("createTime") Long createTime,
            @RequestBody(required = false) Map<String, Object> params) {
        List<String> selectedNodeIds = null;

        if (params != null && params.containsKey("selectedNodeIds")) {
            Object nodeIdsObj = params.get("selectedNodeIds");
            if (nodeIdsObj instanceof List) {
                selectedNodeIds = ((List<?>) nodeIdsObj).stream()
                    .map(Object::toString).collect(java.util.stream.Collectors.toList());
            }
        }

        return simulationExecutionService.runSimulation(createTime, selectedNodeIds);
    }

    /**
     * 停止仿真
     */
    @ApiOperation("停止仿真")
    @PostMapping("/archives/stop")
    @RequirePermission(Permission.PARSING_RULES_CREATE)
    @OperationLog(value = "停止仿真", type = OperationLog.OperationType.UPDATE)
    public Result<Void> stopSimulation(@RequestParam("createTime") Long createTime) {
        return simulationExecutionService.stopSimulation(createTime);
    }

    /**
     * 获取仿真执行状态
     */
    @ApiOperation("获取仿真执行状态")
    @GetMapping("/archives/execution-status")
    @RequirePermission(Permission.PARSING_RULES_READ)
    public Result<?> getExecutionStatus(@RequestParam("createTime") Long createTime) {
        return simulationExecutionService.getExecutionStatus(createTime);
    }

    /**
     * 获取仿真执行日志
     */
    @ApiOperation("获取仿真执行日志")
    @GetMapping("/archives/execution-log")
    @RequirePermission(Permission.PARSING_RULES_READ)
    public Result<Map<String, Object>> getExecutionLog(@RequestParam("createTime") Long createTime) {
        return simulationExecutionService.getExecutionLog(createTime);
    }
}
