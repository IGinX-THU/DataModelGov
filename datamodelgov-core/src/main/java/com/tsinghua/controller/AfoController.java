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

    @ApiOperation("会话状态SSE通知流(全生命周期1s指纹比对,变化才推chg;前端收到后拉一次status)")
    @GetMapping(value = "/stream", produces = org.springframework.http.MediaType.TEXT_EVENT_STREAM_VALUE)
    @RequirePermission(Permission.READ)
    public org.springframework.web.servlet.mvc.method.annotation.SseEmitter statusStream(
            javax.servlet.http.HttpServletResponse resp) {
        // nginx等反向代理默认缓冲SSE响应,导致事件攒到连接结束才一次性发出(前端表现为运行期全盲、
        // 结束瞬间跳全量);X-Accel-Buffering:no让代理对该响应自动关闭缓冲
        resp.setHeader("X-Accel-Buffering", "no");
        resp.setHeader("Cache-Control", "no-cache");
        return afoService.openStatusStream();
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

    @ApiOperation("仿真记录清单分页(SQL;多系统联合仿真表+全模式会话表按时间归并,起动停工作流一行=设计点校核+建模,status/kw为SQL过滤)")
    @GetMapping("/sessions/list")
    @RequirePermission(Permission.READ)
    public Result<List<Map<String, Object>>> pageSessions(
            @PathVariable("pid") String pid,
            @org.springframework.web.bind.annotation.RequestParam(value = "status", required = false) String status,
            @org.springframework.web.bind.annotation.RequestParam(value = "kw", required = false) String kw,
            @org.springframework.web.bind.annotation.RequestParam(value = "kind", required = false) String kind,
            @org.springframework.web.bind.annotation.RequestParam(value = "pageNum", required = false, defaultValue = "1") Integer pageNum,
            @org.springframework.web.bind.annotation.RequestParam(value = "pageSize", required = false, defaultValue = "10") Integer pageSize) {
        try {
            backfillSessions(pid);
            String where = sessionsWhere(status, kw);
            int pn = pageNum == null || pageNum < 1 ? 1 : pageNum;
            int ps = pageSize == null || pageSize < 1 ? 10 : Math.min(pageSize, 100);
            String k = kind == null ? "" : kind.trim();
            boolean all = k.isEmpty() || "all".equals(k);
            boolean wantAfo = all || "afo".equals(k);
            boolean wantFull = all || "fullmode".equals(k);
            boolean wantSs = all || "startstop".equals(k) || "design_point".equals(k);
            if (!all && !wantAfo && !wantFull && !wantSs) {
                throw new IllegalArgumentException("未知记录类型: " + kind);
            }
            // 两个来源各取前 pn*ps 条(均按 createTime DESC),归并后切片,保证全局排序正确
            List<Map<String, Object>> merged = new java.util.ArrayList<>();
            if (wantAfo) {
                List<com.tsinghua.entity.EngineAfoSessionEntity> a =
                        afoSessionService.queryFiltered(pid, 1, pn * ps, where);
                for (com.tsinghua.entity.EngineAfoSessionEntity e : a) merged.add(toRow(e, "afo"));
            }
            if (wantFull) {
                List<com.tsinghua.entity.EngineTestbenchEntity> fFull =
                        testbenchRecordService.queryFiltered(pid, 1, pn * ps,
                                joinWhere("kind = 'fullmode'", where));
                for (com.tsinghua.entity.EngineTestbenchEntity e : fFull) merged.add(toRow(e, "fm"));
            }
            if (wantSs) {
                // 设计点/起动停要先归并成工作流再切片:若只取 pn*ps 条原始记录，
                // 归并后行数变少，后面的页会取不到数据(总数说有、翻页是空)。
                List<com.tsinghua.entity.EngineTestbenchEntity> fDpSs = queryAllWorkflowRecords(pid,
                        joinWhere("kind IN ('design_point','startstop')", where));
                // 起动停工作流归并:设计点校核并入起动停工作流行,一行=一次工作流执行
                for (com.tsinghua.entity.EngineTestbenchEntity e : mergeTestbenchWorkflow(pid, fDpSs)) {
                    merged.add(toRow(e, "fm"));
                }
            }
            merged.sort((x, y) -> Long.compare(numOf(y.get("createdAt")), numOf(x.get("createdAt"))));
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
                    + testbenchRecordService.countFiltered(pid, joinWhere("kind = 'fullmode'", where))
                    // 设计点校核并入起动停工作流行后再计数,与列表口径一致
                    + mergeTestbenchWorkflow(pid, queryAllWorkflowRecords(pid,
                            joinWhere("kind IN ('design_point','startstop')", where))).size();
            return Result.success(total);
        } catch (Exception e) {
            return Result.error("统计仿真记录总数失败: " + e.getMessage());
        }
    }

    @ApiOperation("仿真记录概览(每类型最新一条:多系统联合仿真/起动停车建模/全模式仿真,一条记录=该类型整个工作流;设计点校核并入起动停工作流)")
    @GetMapping("/sessions/latest")
    @RequirePermission(Permission.READ)
    public Result<List<Map<String, Object>>> latestSessions(@PathVariable("pid") String pid) {
        try {
            backfillSessions(pid);
            List<Map<String, Object>> out = new java.util.ArrayList<>();
            List<com.tsinghua.entity.EngineAfoSessionEntity> a = afoSessionService.queryFiltered(pid, 1, 1, null);
            if (!a.isEmpty()) out.add(toRow(a.get(0), "afo"));
            // 起动停工作流归并后取最新一条(设计点校核不单列,概览口径=工作流)
            List<com.tsinghua.entity.EngineTestbenchEntity> ss = mergeTestbenchWorkflow(pid,
                    queryAllWorkflowRecords(pid, "kind IN ('design_point','startstop')"));
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

    /**
     * 全量拉取设计点/起动停记录(按页累加)。
     *
     * <p>这些记录必须先归并成"工作流"再计数与切片，所以不能像普通分页那样只取前 N 条：
     * 以前硬编码 1000 条，超过 1000 条记录时总数会少算、页数偏少，表现为"分页翻不到后面"。
     */
    private List<com.tsinghua.entity.EngineTestbenchEntity> queryAllWorkflowRecords(String pid, String where) {
        final int pageSize = 500;
        final int maxPages = 200; // 10 万条上限，防止异常数据无限翻页
        List<com.tsinghua.entity.EngineTestbenchEntity> all = new java.util.ArrayList<>();
        for (int page = 1; page <= maxPages; page++) {
            List<com.tsinghua.entity.EngineTestbenchEntity> part =
                    testbenchRecordService.queryFiltered(pid, page, pageSize, where);
            if (part == null || part.isEmpty()) {
                break;
            }
            all.addAll(part);
            if (part.size() < pageSize) {
                break;
            }
        }
        return all;
    }

    /** 前端状态筛选映射 phase SQL 条件 + 运行编号模糊匹配。 */
    private String sessionsWhere(String status, String kw) {
        StringBuilder sb = new StringBuilder();
        // 兼容历史前端把未填的可选项序列化成字面量 "undefined"/"null":一律视为"未筛选"。
        // 否则会生成 runId LIKE '%undefined%',使 total=0,分页条只剩第 1 页(列表却仍有数据)。
        String st = blankAsNull(status);
        String key = blankAsNull(kw);
        if ("ok".equals(st)) sb.append("phase = 'ENDED'");
        else if ("failed".equals(st)) sb.append("phase = 'FAILED'");
        else if ("running".equals(st)) sb.append("phase IN ('READY','PREPARING','RUNNING','PAUSED')");
        if (key != null) {
            if (sb.length() > 0) sb.append(" AND ");
            // IginX 的 LIKE 是正则匹配(与其他 service 的 name LIKE '^.*x.*' 写法一致),
            // SQL 的 % 通配在正则里是字面字符,曾导致按运行编号搜索永远 0 行。
            // (?i) 忽略大小写;先转义正则元字符,再转义单引号,关键字始终按字面匹配。
            sb.append("runId LIKE '(?i)^.*").append(escapeLikeRegex(key)).append(".*'");
        }
        return sb.length() == 0 ? null : sb.toString();
    }

    /** 转义 IginX LIKE 正则里的元字符与单引号,使用户输入按字面匹配。 */
    private String escapeLikeRegex(String s) {
        String escaped = s.replaceAll("([\\\\\\.\\[\\]\\{\\}()\\*\\+\\?\\^\\$\\|])", "\\\\$1");
        return escaped.replace("'", "''");
    }

    /** 归一化可选查询参数:空白串与 "undefined"/"null" 字面量都视为未提供。 */
    private String blankAsNull(String s) {
        if (s == null) return null;
        String t = s.trim();
        if (t.isEmpty() || "undefined".equalsIgnoreCase(t) || "null".equalsIgnoreCase(t)) return null;
        return t;
    }

    private String joinWhere(String a, String b) {
        if (a == null) return b;
        if (b == null) return a;
        return a + " AND " + b;
    }

    private long numOf(Object o) { return o instanceof Number ? ((Number) o).longValue() : 0; }

    /** 起动停工作流归并:设计点校核(design_point)被起动停车建模(startstop)引用时并入工作流行,
     *  一行=一次工作流执行(与运行记录同口径),不再单列设计点记录;未被引用的设计点(仅校核未建模)保留。
     *  血缘来源:任务元数据config.designTaskId(新任务显式记录),回退解析config.source.designStateFile
     *  路径(…/testbench/<dpId>/task/MiddleData/design_state.mat,存量任务)。 */
    private List<com.tsinghua.entity.EngineTestbenchEntity> mergeTestbenchWorkflow(
            String pid, List<com.tsinghua.entity.EngineTestbenchEntity> rows) {
        Map<String, Map<String, Object>> metaById = new java.util.HashMap<>();
        try {
            for (Map<String, Object> t : testbenchService.listTasks(pid)) {
                Object id = t.get("taskId");
                if (id != null) metaById.put(String.valueOf(id), t);
            }
        } catch (Exception e) {
            log.warn("仿真记录工作流归并读取任务元数据失败: projectId={}", pid, e);
        }
        java.util.Set<String> referenced = new java.util.HashSet<>();
        for (com.tsinghua.entity.EngineTestbenchEntity r : rows) {
            if (!"startstop".equals(r.getKind())) continue;
            String dpKey = designPointKeyOf(r, metaById);
            if (dpKey != null) referenced.add(dpKey);
        }
        List<com.tsinghua.entity.EngineTestbenchEntity> out = new java.util.ArrayList<>();
        for (com.tsinghua.entity.EngineTestbenchEntity r : rows) {
            if ("design_point".equals(r.getKind()) && referenced.contains(r.getTaskKey())) continue;
            out.add(r);
        }
        return out;
    }

    /** 解析起动停车任务引用的设计点任务键;无设计阶段或元数据缺失时返回null。 */
    @SuppressWarnings("unchecked")
    private String designPointKeyOf(com.tsinghua.entity.EngineTestbenchEntity ss,
                                    Map<String, Map<String, Object>> metaById) {
        try {
            Map<String, Object> meta = metaById.get(ss.getTaskKey());
            if (meta == null) return null;
            Map<String, Object> cfg = (Map<String, Object>) meta.get("config");
            if (cfg == null) return null;
            Object dti = cfg.get("designTaskId");
            if (dti != null && !String.valueOf(dti).trim().isEmpty()) return String.valueOf(dti).trim();
            Map<String, Object> src = (Map<String, Object>) cfg.get("source");
            Object dsf = src == null ? null : src.get("designStateFile");
            if (dsf == null) return null;
            String p = String.valueOf(dsf).replace('\\', '/');
            int t = p.indexOf("/testbench/");
            if (t < 0) return null;
            int s = t + "/testbench/".length();
            int e2 = p.indexOf('/', s);
            return e2 > s ? p.substring(s, e2) : null;
        } catch (Exception e) {
            return null;
        }
    }

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

    @ApiOperation("通道字典(R065 prepare自产channels.json:SHT_AFO_CATALOG_V2,含display/displayGroup/panel)")
    @GetMapping("/channels")
    @RequirePermission(Permission.READ)
    public Result<Map<String, Object>> channels(@PathVariable("pid") String pid) {
        try {
            return Result.success(afoService.channelCatalog(pid));
        } catch (Exception e) {
            return Result.error("读取AFO通道字典失败: " + e.getMessage());
        }
    }

    @ApiOperation("动态历史增量读取(游标式;stream样本块纯文件读取,不占用引擎)")
    @GetMapping("/live")
    @RequirePermission(Permission.READ)
    public Result<Map<String, Object>> live(@PathVariable("pid") String pid,
            @org.springframework.web.bind.annotation.RequestParam(value = "afterSeq", required = false, defaultValue = "0") Long afterSeq,
            @org.springframework.web.bind.annotation.RequestParam(value = "sessionId", required = false) String sessionId,
            @org.springframework.web.bind.annotation.RequestParam(value = "maxRows", required = false, defaultValue = "2048") Integer maxRows,
            @org.springframework.web.bind.annotation.RequestParam(value = "columns", required = false) String columns) {
        try {
            int[] cols = null;
            if (columns != null && !columns.trim().isEmpty()) {
                String[] parts = columns.trim().split(",");
                cols = new int[parts.length];
                for (int i = 0; i < parts.length; i++) {
                    cols[i] = Integer.parseInt(parts[i].trim());
                }
            }
            return Result.success(afoService.readLive(pid, afterSeq == null ? 0L : afterSeq, sessionId, maxRows, cols));
        } catch (Exception e) {
            return Result.error("读取AFO动态历史失败: " + e.getMessage());
        }
    }

    @ApiOperation("增量数据SSE流(program-run live-stream同构;token走query;end事件=终态/会话结束)")
    @GetMapping(value = "/live-stream", produces = org.springframework.http.MediaType.TEXT_EVENT_STREAM_VALUE)
    @RequirePermission(Permission.READ)
    public org.springframework.web.servlet.mvc.method.annotation.SseEmitter liveStream(
            @PathVariable("pid") String pid,
            @org.springframework.web.bind.annotation.RequestParam(value = "afterSeq", required = false, defaultValue = "0") Long afterSeq,
            @org.springframework.web.bind.annotation.RequestParam(value = "sessionId", required = false) String sessionId,
            @org.springframework.web.bind.annotation.RequestParam(value = "columns", required = false) String columns,
            javax.servlet.http.HttpServletResponse resp) {
        // 同/stream:关掉代理缓冲,保证live帧实时到达
        resp.setHeader("X-Accel-Buffering", "no");
        resp.setHeader("Cache-Control", "no-cache");
        org.springframework.web.servlet.mvc.method.annotation.SseEmitter em =
                new org.springframework.web.servlet.mvc.method.annotation.SseEmitter(0L);
        try {
            int[] cols = null;
            if (columns != null && !columns.trim().isEmpty()) {
                String[] parts = columns.trim().split(",");
                cols = new int[parts.length];
                for (int i = 0; i < parts.length; i++) {
                    cols[i] = Integer.parseInt(parts[i].trim());
                }
            }
            return afoService.openLiveStream(pid, afterSeq == null ? 0L : afterSeq, sessionId, cols);
        } catch (Exception e) {
            // SSE 错误以事件形式返回,前端降级为轮询
            try {
                em.send(org.springframework.web.servlet.mvc.method.annotation.SseEmitter.event()
                        .name("err").data(e.getMessage() == null ? "live-stream unavailable" : e.getMessage()));
                em.complete();
            } catch (Exception ignore) {
                // 客户端已断开
            }
            return em;
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
