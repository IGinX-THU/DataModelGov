package com.tsinghua.controller;

import com.tsinghua.auth.annotation.RequirePermission;
import com.tsinghua.auth.enums.Permission;
import com.tsinghua.engine.AfoService;
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
 * 多系统联合仿真(F-12,AFO_V_2)会话API。
 * 命令与状态走程序合同文件通道(inbox/status.json);prepare/run/save走专用引擎。
 */
@Api(tags = "工作台-多系统联合仿真")
@Slf4j
@RestController
@RequestMapping("/api/engine/projects/{pid}/afo")
@CrossOrigin
public class AfoController {

    @Autowired
    private AfoService afoService;

    @ApiOperation("发起准备(异步;构造运行副本与模型初始化)")
    @PostMapping("/prepare")
    @RequirePermission(Permission.CREATE)
    public Result<Map<String, Object>> prepare(@PathVariable("pid") String pid,
                                               @RequestBody Map<String, Object> cfg) {
        try {
            cfg.put("engineId", String.valueOf(cfg.getOrDefault("engineId", "ENGINE-001")));
            if (cfg.get("runId") == null || String.valueOf(cfg.get("runId")).trim().isEmpty()) {
                cfg.remove("runId");
            }
            return Result.success(afoService.prepare(pid, cfg));
        } catch (Exception e) {
            log.error("AFO准备发起失败", e);
            return Result.error("发起AFO准备失败: " + e.getMessage());
        }
    }

    @ApiOperation("开始运行(阻塞sim;期间状态/命令走文件通道)")
    @PostMapping("/run")
    @RequirePermission(Permission.CREATE)
    public Result<Map<String, Object>> run(@PathVariable("pid") String pid) {
        try {
            return Result.success(afoService.run(pid));
        } catch (Exception e) {
            return Result.error("发起AFO运行失败: " + e.getMessage());
        }
    }

    @ApiOperation("会话状态(phase+status.json live)")
    @GetMapping("/status")
    @RequirePermission(Permission.READ)
    public Result<Map<String, Object>> status(@PathVariable("pid") String pid) {
        try {
            return Result.success(afoService.currentStatus(pid));
        } catch (Exception e) {
            return Result.error("读取AFO状态失败: " + e.getMessage());
        }
    }

    @ApiOperation("在线命令(pause/resume/stop/np/load;写inbox文件通道)")
    @PostMapping("/command")
    @RequirePermission(Permission.CREATE)
    public Result<Map<String, Object>> command(@PathVariable("pid") String pid,
                                               @RequestBody Map<String, Object> body) {
        try {
            String kind = String.valueOf(body.get("kind"));
            return Result.success(afoService.command(pid, kind, body.get("value")));
        } catch (Exception e) {
            return Result.error("AFO命令写入失败: " + e.getMessage());
        }
    }

    @ApiOperation("保存重试(ended后;不重新计算)")
    @PostMapping("/save")
    @RequirePermission(Permission.CREATE)
    public Result<Map<String, Object>> save(@PathVariable("pid") String pid) {
        try {
            return Result.success(afoService.save(pid));
        } catch (Exception e) {
            return Result.error("AFO保存失败: " + e.getMessage());
        }
    }

    @ApiOperation("关闭会话")
    @PostMapping("/close")
    @RequirePermission(Permission.CREATE)
    public Result<Map<String, Object>> close(@PathVariable("pid") String pid) {
        try {
            return Result.success(afoService.close(pid));
        } catch (Exception e) {
            return Result.error("AFO会话关闭失败: " + e.getMessage());
        }
    }

    @ApiOperation("历史会话列表")
    @GetMapping("/sessions")
    @RequirePermission(Permission.READ)
    public Result<List<Map<String, Object>>> sessions(@PathVariable("pid") String pid) {
        try {
            return Result.success(afoService.listSessions(pid));
        } catch (Exception e) {
            return Result.error("读取AFO会话列表失败: " + e.getMessage());
        }
    }

    @ApiOperation("历史会话结果(result.json:config/channels/time/values/events/timing)")
    @GetMapping("/sessions/{runId}/result")
    @RequirePermission(Permission.READ)
    public Result<Object> result(@PathVariable("pid") String pid,
                                 @PathVariable("runId") String runId) {
        try {
            Map<String, Object> r = afoService.readResult(pid, runId);
            if (r == null) return Result.error("结果尚未生成(运行结束并保存后可读)");
            return Result.success(r);
        } catch (Exception e) {
            return Result.error("读取AFO结果失败: " + e.getMessage());
        }
    }

    @ApiOperation("下载会话交付Excel(全通道)")
    @GetMapping("/sessions/{runId}/excel")
    @RequirePermission(Permission.READ)
    public ResponseEntity<FileSystemResource> excel(@PathVariable("pid") String pid,
                                                    @PathVariable("runId") String runId) {
        File f;
        String name;
        try {
            f = afoService.resultExcel(pid, runId);
            if (f == null || !f.exists()) return ResponseEntity.notFound().build();
            name = f.getName();
            return ResponseEntity.ok()
                    .header(HttpHeaders.CONTENT_DISPOSITION,
                            "attachment; filename*=UTF-8''" + URLEncoder.encode(name, "UTF-8"))
                    .contentType(MediaType.parseMediaType(
                            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"))
                    .body(new FileSystemResource(f));
        } catch (Exception e) {
            return ResponseEntity.notFound().build();
        }
    }
}
