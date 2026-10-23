package com.tsinghua.controller;

import com.tsinghua.auth.annotation.RequirePermission;
import com.tsinghua.auth.enums.Permission;
import com.tsinghua.engine.TestbenchService;
import com.tsinghua.model.Result;
import io.swagger.annotations.Api;
import io.swagger.annotations.ApiOperation;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.io.FileSystemResource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.io.File;
import java.net.URLEncoder;
import java.util.List;
import java.util.Map;

/**
 * 数字试车台API(第四批):
 *   F-11 全模式人工操纵仿真(/fullmode/*,sht_fullmode_session 会话合同);
 *   F-09 设计点配置 与 F-10 起动停车模型构造(/tasks/*,一次性任务)。
 */
@Api(tags = "工作台-数字试车台")
@Slf4j
@RestController
@RequestMapping("/api/engine/projects/{pid}/testbench")
@CrossOrigin
public class TestbenchController {

    @Autowired
    private TestbenchService testbenchService;

    /* ---------- F-11 全模式会话 ---------- */

    @ApiOperation("全模式:发起准备(异步;专用引擎prepare+begin)")
    @PostMapping("/fullmode/prepare")
    @RequirePermission(Permission.CREATE)
    public Result<Map<String, Object>> fmPrepare(@PathVariable("pid") String pid,
                                                 @RequestBody Map<String, Object> cfg) {
        try {
            cfg.put("engineId", String.valueOf(cfg.getOrDefault("engineId", "ENGINE-001")));
            return Result.success(testbenchService.fullmodePrepare(pid, cfg));
        } catch (Exception e) {
            log.error("全模式准备发起失败", e);
            return Result.error("发起全模式准备失败: " + e.getMessage());
        }
    }

    @ApiOperation("全模式:开始/继续推进(分块advance,块间处理命令)")
    @PostMapping("/fullmode/run")
    @RequirePermission(Permission.CREATE)
    public Result<Map<String, Object>> fmRun(@PathVariable("pid") String pid) {
        try {
            return Result.success(testbenchService.fullmodeRun(pid));
        } catch (Exception e) {
            return Result.error("发起全模式运行失败: " + e.getMessage());
        }
    }

    @ApiOperation("全模式:会话状态(phase+status.json live)")
    @GetMapping("/fullmode/status")
    @RequirePermission(Permission.READ)
    public Result<Map<String, Object>> fmStatus(@PathVariable("pid") String pid) {
        try {
            return Result.success(testbenchService.fullmodeStatus(pid));
        } catch (Exception e) {
            return Result.error("读取全模式状态失败: " + e.getMessage());
        }
    }

    @ApiOperation("全模式:命令(pause/stop/select_throttle/start/set_np_gear/apply_load等)")
    @PostMapping("/fullmode/command")
    @RequirePermission(Permission.CREATE)
    public Result<Map<String, Object>> fmCommand(@PathVariable("pid") String pid,
                                                 @RequestBody Map<String, Object> body) {
        try {
            return Result.success(testbenchService.fullmodeCommand(pid,
                    String.valueOf(body.get("kind")), body.get("value")));
        } catch (Exception e) {
            return Result.error("全模式命令失败: " + e.getMessage());
        }
    }

    @ApiOperation("全模式:关闭会话")
    @PostMapping("/fullmode/close")
    @RequirePermission(Permission.CREATE)
    public Result<Map<String, Object>> fmClose(@PathVariable("pid") String pid) {
        try {
            return Result.success(testbenchService.fullmodeClose(pid));
        } catch (Exception e) {
            return Result.error("全模式会话关闭失败: " + e.getMessage());
        }
    }

    @ApiOperation("全模式:历史会话列表")
    @GetMapping("/fullmode/sessions")
    @RequirePermission(Permission.READ)
    public Result<List<Map<String, Object>>> fmSessions(@PathVariable("pid") String pid) {
        try {
            return Result.success(testbenchService.fullmodeSessions(pid));
        } catch (Exception e) {
            return Result.error("读取全模式会话列表失败: " + e.getMessage());
        }
    }

    @ApiOperation("全模式:历史结果(result.json)")
    @GetMapping("/fullmode/sessions/{runId}/result")
    @RequirePermission(Permission.READ)
    public Result<Object> fmResult(@PathVariable("pid") String pid,
                                   @PathVariable("runId") String runId) {
        try {
            Map<String, Object> r = testbenchService.fullmodeResult(pid, runId);
            if (r == null) return Result.error("结果尚未生成(运行结束并保存后可读)");
            return Result.success(r);
        } catch (Exception e) {
            return Result.error("读取全模式结果失败: " + e.getMessage());
        }
    }

    @ApiOperation("全模式:下载交付Excel")
    @GetMapping("/fullmode/sessions/{runId}/excel")
    @RequirePermission(Permission.READ)
    public ResponseEntity<FileSystemResource> fmExcel(@PathVariable("pid") String pid,
                                                      @PathVariable("runId") String runId) {
        try {
            File f = testbenchService.fullmodeExcel(pid, runId);
            if (f == null || !f.exists()) return ResponseEntity.notFound().build();
            return ResponseEntity.ok()
                    .header(HttpHeaders.CONTENT_DISPOSITION,
                            "attachment; filename*=UTF-8''" + URLEncoder.encode(f.getName(), "UTF-8"))
                    .contentType(MediaType.parseMediaType(
                            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"))
                    .body(new FileSystemResource(f));
        } catch (Exception e) {
            return ResponseEntity.notFound().build();
        }
    }

    /* ---------- F-09 设计点 / F-10 起动停车 ---------- */

    @ApiOperation("发起试车台任务(kind=design_point|startstop;异步专用引擎)")
    @PostMapping("/tasks/{kind}/run")
    @RequirePermission(Permission.CREATE)
    public Result<Map<String, Object>> runTask(@PathVariable("pid") String pid,
                                               @PathVariable("kind") String kind,
                                               @RequestBody(required = false) Map<String, Object> cfg) {
        try {
            return Result.success(testbenchService.runTask(pid, kind,
                    cfg == null ? new java.util.LinkedHashMap<>() : cfg));
        } catch (Exception e) {
            log.error("试车台任务发起失败", e);
            return Result.error("发起试车台任务失败: " + e.getMessage());
        }
    }

    @ApiOperation("设计点commit(时间备份后写原选定MDL并复现)")
    @PostMapping("/tasks/{taskId}/commit")
    @RequirePermission(Permission.CREATE)
    public Result<Map<String, Object>> commit(@PathVariable("pid") String pid,
                                              @PathVariable("taskId") String taskId) {
        try {
            return Result.success(testbenchService.commitDesignPoint(pid, taskId));
        } catch (Exception e) {
            return Result.error("设计点commit失败: " + e.getMessage());
        }
    }

    @ApiOperation("试车台任务状态(含结果JSON)")
    @GetMapping("/tasks/{taskId}/status")
    @RequirePermission(Permission.READ)
    public Result<Map<String, Object>> taskStatus(@PathVariable("pid") String pid,
                                                  @PathVariable("taskId") String taskId) {
        try {
            return Result.success(testbenchService.taskStatus(pid, taskId));
        } catch (Exception e) {
            return Result.error("读取任务状态失败: " + e.getMessage());
        }
    }

    @ApiOperation("试车台任务列表")
    @GetMapping("/tasks")
    @RequirePermission(Permission.READ)
    public Result<List<Map<String, Object>>> tasks(@PathVariable("pid") String pid) {
        try {
            return Result.success(testbenchService.listTasks(pid));
        } catch (Exception e) {
            return Result.error("读取试车台任务列表失败: " + e.getMessage());
        }
    }
}
