package com.tsinghua.engine;

import com.tsinghua.auth.util.AuthUtil;
import com.tsinghua.entity.EngineAfoSessionEntity;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.Map;

/** 多系统联合仿真会话清单服务(AfoService.writeSessionIndex 挂钩同步;清单分页查询)。 */
@Slf4j
@Service
public class EngineAfoSessionService extends IginxListService<EngineAfoSessionEntity> {

    @Override
    protected String prefix() { return "relational_system.engine_afo_sessions"; }

    @Override
    protected Class<EngineAfoSessionEntity> type() { return EngineAfoSessionEntity.class; }

    @Override
    protected String idColumn() { return "runId"; }

    @Override
    protected Long rowKeyOf(EngineAfoSessionEntity row) { return row.getCreateTime(); }

    /** 会话建立/阶段变更后同步清单行(按 runId 覆写;idx 为会话索引 Map)。 */
    public void upsertFromIndex(String projectId, Map<String, Object> idx) {
        try {
            String runId = String.valueOf(idx.get("runId"));
            EngineAfoSessionEntity row = queryByKey(projectId, runId);
            long ts;
            if (row == null || row.getCreateTime() == null) {
                Object ca = idx.get("createdAt");
                ts = ca instanceof Number ? ((Number) ca).longValue() : System.currentTimeMillis();
                while (tsTaken(ts)) ts++;
                row = new EngineAfoSessionEntity();
                row.setOwner(AuthUtil.getCurrentUsername());
            } else {
                ts = row.getCreateTime();
            }
            row.setId(ts).setCreateTime(ts)
                    .setProjectId(projectId).setRunId(runId)
                    .setEngineId(str(idx.get("engineId")))
                    .setPhase(str(idx.get("phase"))).setMessage(str(idx.get("message")))
                    .setHasResult(Boolean.TRUE.equals(idx.get("hasResult")) ? 1 : 0)
                    .setHasExcel(Boolean.TRUE.equals(idx.get("hasExcel")) ? 1 : 0)
                    .setSummary(summaryJson(idx.get("config"), "loadMode", "externalAir", "pace", "duration"))
                    .setFinishedTime(num(idx.get("finishedAt")));
            iginxClient.getWriteClient().writeMeasurement(row);
        } catch (Exception e) {
            log.warn("AFO会话清单同步失败: runId={}", idx.get("runId"), e);
        }
    }

    /** 从会话config提炼展示字段为JSON摘要(清单行渲染用,避免存储整份config)。 */
    static String summaryJson(Object config, String... keys) {
        if (!(config instanceof Map)) return null;
        Map<?, ?> cfg = (Map<?, ?>) config;
        StringBuilder sb = new StringBuilder("{");
        boolean first = true;
        for (String k : keys) {
            Object v = cfg.get(k);
            if (v == null) continue;
            if (!first) sb.append(',');
            first = false;
            sb.append('"').append(k).append("\":");
            if (v instanceof Number || v instanceof Boolean) sb.append(v);
            else sb.append('"').append(String.valueOf(v).replace("\"", "'")).append('"');
        }
        sb.append('}');
        return sb.length() <= 2 ? null : sb.toString();
    }

    static String str(Object o) { return o == null ? null : String.valueOf(o); }

    static Long num(Object o) { return o instanceof Number ? ((Number) o).longValue() : null; }
}
