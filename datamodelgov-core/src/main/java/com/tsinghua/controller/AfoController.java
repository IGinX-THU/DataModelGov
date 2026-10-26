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

    @Autowired
    private com.tsinghua.engine.EngineAfoSessionService afoSessionService;

    @Autowired
    private com.tsinghua.engine.EngineTestbenchRecordService testbenchRecordService;

    @Autowired
    private com.tsinghua.engine.TestbenchService testbenchService;

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

    @ApiOperation("仿真记录清单分页(SQL;多系统联合仿真表+全模式会话表按时间归并,status/kw为SQL过滤)")
    @GetMapping("/sessions/list")
    @RequirePermission(Permission.READ)
    public Result<List<Map<String, Object>>> pageSessions(
            @PathVariable("pid") String pid,
            @org.springframework.web.bind.annotation.RequestParam(value = "status", required = false) String status,
            @org.springframework.web.bind.annotation.RequestParam(value = "kw", required = false) String kw,
            @org.springframework.web.bind.annotation.RequestParam(value = "pageNum", required = false, defaultValue = "1") Integer pageNum,
            @org.springframework.web.bind.annotation.RequestParam(value = "pageSize", required = false, defaultValue = "10") Integer pageSize) {
        try {
            backfillSessions(pid);
            String where = sessionsWhere(status, kw);
            int pn = pageNum == null || pageNum < 1 ? 1 : pageNum;
            int ps = pageSize == null || pageSize < 1 ? 10 : Math.min(pageSize, 100);
            // 两个来源各取前 pn*ps 条(均按 createTime DESC),归并后切片,保证全局排序正确
            List<com.tsinghua.entity.EngineAfoSessionEntity> a =
                    afoSessionService.queryFiltered(pid, 1, pn * ps, where);
            List<com.tsinghua.entity.EngineTestbenchEntity> f =
                    testbenchRecordService.queryFiltered(pid, 1, pn * ps,
                            joinWhere("kind IN ('fullmode','design_point','startstop')", where));
            List<Map<String, Object>> merged = new java.util.ArrayList<>();
            for (com.tsinghua.entity.EngineAfoSessionEntity e : a) merged.add(toRow(e, "afo"));
            for (com.tsinghua.entity.EngineTestbenchEntity e : f) merged.add(toRow(e, "fm"));
            merged.sort((x, y) -> Long.compare(numOf(y.get("createTime")), numOf(x.get("createTime"))));
            int from = Math.min(merged.size(), (pn - 1) * ps);
            int to = Math.min(merged.size(), from + ps);
            return Result.success(new java.util.ArrayList<>(merged.subList(from, to)));
        } catch (Exception e) {
            return Result.error("读取仿真记录分页失败: " + e.getMessage());
        }
    }

    @ApiOperation("仿真记录总数(SQL;status/kw过滤与列表一致,含多系统联合仿真+全模式)")
    @GetMapping("/sessions/count")
    @RequirePermission(Permission.READ)
    public Result<Long> countSessions(@PathVariable("pid") String pid,
            @org.springframework.web.bind.annotation.RequestParam(value = "status", required = false) String status,
            @org.springframework.web.bind.annotation.RequestParam(value = "kw", required = false) String kw) {
        try {
            backfillSessions(pid);
            String where = sessionsWhere(status, kw);
            long total = afoSessionService.countFiltered(pid, where)
                    + testbenchRecordService.countFiltered(pid, joinWhere("kind IN ('fullmode','design_point','startstop')", where));
            return Result.success(total);
        } catch (Exception e) {
            return Result.error("统计仿真记录总数失败: " + e.getMessage());
        }
    }

    @ApiOperation("仿真记录概览(每类型最新一条:多系统联合仿真/起动停车建模/全模式仿真,一条记录=该类型整个工作流)")
    @GetMapping("/sessions/latest")
    @RequirePermission(Permission.READ)
    public Result<List<Map<String, Object>>> latestSessions(@PathVariable("pid") String pid) {
        try {
            backfillSessions(pid);
            List<Map<String, Object>> out = new java.util.ArrayList<>();
            List<com.tsinghua.entity.EngineAfoSessionEntity> a = afoSessionService.queryFiltered(pid, 1, 1, null);
            if (!a.isEmpty()) out.add(toRow(a.get(0), "afo"));
            List<com.tsinghua.entity.EngineTestbenchEntity> ss = testbenchRecordService.queryFiltered(
                    pid, 1, 1, "kind IN ('design_point','startstop')");
            if (!ss.isEmpty()) out.add(toRow(ss.get(0), "fm"));
            List<com.tsinghua.entity.EngineTestbenchEntity> fm = testbenchRecordService.queryFiltered(
                    pid, 1, 1, "kind = 'fullmode'");
            if (!fm.isEmpty()) out.add(toRow(fm.get(0), "fm"));
            out.sort((x, y) -> Long.compare(numOf(y.get("createdAt")), numOf(x.get("createdAt"))));
            return Result.success(out);
        } catch (Exception e) {
            return Result.error("读取仿真记录概览失败: " + e.getMessage());
        }
    }

    /** 前端状态筛选映射 phase SQL 条件 + 运行编号模糊匹配。 */
    private String sessionsWhere(String status, String kw) {
        StringBuilder sb = new StringBuilder();
        if ("ok".equals(status)) sb.append("phase = 'ENDED'");
        else if ("failed".equals(status)) sb.append("phase = 'FAILED'");
        else if ("running".equals(status)) sb.append("phase IN ('READY','PREPARING','RUNNING','PAUSED')");
        if (kw != null && !kw.trim().isEmpty()) {
            String like = kw.trim().replace("'", "''").replace("%", "\\%").replace("_", "\\_");
            if (sb.length() > 0) sb.append(" AND ");
            sb.append("runId LIKE '%").append(like).append("%'");
        }
        return sb.length() == 0 ? null : sb.toString();
    }

    private String joinWhere(String a, String b) {
        if (a == null) return b;
        if (b == null) return a;
        return a + " AND " + b;
    }

    private long numOf(Object o) { return o instanceof Number ? ((Number) o).longValue() : 0; }

    /** 两类来源行统一为前端渲染结构(runId/phase/createdAt/finishedAt/hasResult/hasExcel/config摘要)。 */
    private Map<String, Object> toRow(Object e, String kind) {
        Map<String, Object> m = new java.util.LinkedHashMap<>();
        if (e instanceof com.tsinghua.entity.EngineAfoSessionEntity) {
            com.tsinghua.entity.EngineAfoSessionEntity r = (com.tsinghua.entity.EngineAfoSessionEntity) e;
            m.put("runId", r.getRunId());
            m.put("phase", r.getPhase());
            m.put("message", r.getMessage());
            m.put("createdAt", r.getCreateTime());
            m.put("finishedAt", r.getFinishedTime());
            m.put("hasResult", r.getHasResult() != null && r.getHasResult() == 1);
            m.put("hasExcel", r.getHasExcel() != null && r.getHasExcel() == 1);
            m.put("config", parseSummary(r.getSummary()));
        } else {
            com.tsinghua.entity.EngineTestbenchEntity r = (com.tsinghua.entity.EngineTestbenchEntity) e;
            m.put("runId", r.getTaskKey());
            m.put("kind", r.getKind());
            m.put("phase", r.getPhase());
            m.put("message", r.getMessage());
            m.put("createdAt", r.getCreateTime());
            m.put("finishedAt", r.getFinishedTime());
            m.put("hasResult", r.getPhase() != null && ("ENDED".equals(r.getPhase()) || "COMMITTED".equals(r.getPhase())));
            m.put("hasExcel", r.getHasExcel() != null && r.getHasExcel() == 1);
            m.put("config", parseSummary(r.getSummary()));
        }
        m.put("_kind", kind);
        return m;
    }

    /** summary JSON 摘要解析为渲染用 config 对象(失败返回空map)。 */
    @SuppressWarnings("unchecked")
    private Map<String, Object> parseSummary(String summary) {
        if (summary == null || summary.isEmpty()) return new java.util.HashMap<>();
        try {
            return new com.fasterxml.jackson.databind.ObjectMapper().readValue(summary, Map.class);
        } catch (Exception e) {
            return new java.util.HashMap<>();
        }
    }

    /** 存量会话回填:清单表为空而文件索引存在时,把文件会话同步进清单表。 */
    private void backfillSessions(String pid) {
        try {
            if (afoSessionService.countList(pid) == 0) {
                for (Map<String, Object> idx : afoService.listSessions(pid)) {
                    afoSessionService.upsertFromIndex(pid, idx);
                }
            }
        } catch (Exception e) {
            log.warn("AFO会话清单回填失败: projectId={}", pid, e);
        }
        // 试车台记录(全模式/设计点/起动停车)同样从文件元数据回填,表空时执行一次
        try {
            if (testbenchRecordService.countList(pid) == 0) {
                for (Map<String, Object> idx : testbenchService.listTasks(pid)) {
                    testbenchRecordService.upsertFromIndex(pid, idx);
                }
            }
        } catch (Exception e) {
            log.warn("试车台记录清单回填失败: projectId={}", pid, e);
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
