package com.tsinghua.engine;

import com.tsinghua.auth.util.AuthUtil;
import com.tsinghua.entity.EngineTestbenchEntity;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.Map;

/** 数字试车台记录清单服务(TestbenchService.writeTaskIndex 挂钩同步;清单分页查询)。 */
@Slf4j
@Service
public class EngineTestbenchRecordService extends IginxListService<EngineTestbenchEntity> {

    @Override
    protected String prefix() { return "relational_system.engine_testbench_records"; }

    @Override
    protected Class<EngineTestbenchEntity> type() { return EngineTestbenchEntity.class; }

    @Override
    protected String idColumn() { return "taskKey"; }

    @Override
    protected Long rowKeyOf(EngineTestbenchEntity row) { return row.getCreateTime(); }

    /** 试车台任务/全模式会话建立或阶段变更后同步清单行(按 taskKey 覆写)。 */
    public void upsertFromIndex(String projectId, Map<String, Object> idx) {
        try {
            String key = String.valueOf(idx.get("taskId") != null ? idx.get("taskId") : idx.get("runId"));
            EngineTestbenchEntity row = queryByKey(projectId, key);
            long ts;
            if (row == null || row.getCreateTime() == null) {
                Object ca = idx.get("createdAt");
                ts = ca instanceof Number ? ((Number) ca).longValue() : System.currentTimeMillis();
                while (tsTaken(ts)) ts++;
                row = new EngineTestbenchEntity();
                row.setOwner(AuthUtil.getCurrentUsername());
            } else {
                ts = row.getCreateTime();
            }
            String kind = EngineAfoSessionService.str(idx.get("kind"));
            row.setId(ts).setCreateTime(ts)
                    .setProjectId(projectId).setTaskKey(key)
                    .setKind("design_point".equals(kind) ? "design_point"
                            : "startstop".equals(kind) ? "startstop" : "fullmode")
                    .setPhase(EngineAfoSessionService.str(idx.get("phase")))
                    .setMessage(EngineAfoSessionService.str(idx.get("message")))
                    .setHasExcel(Boolean.TRUE.equals(idx.get("hasExcel")) ? 1 : 0)
                    .setSummary(EngineAfoSessionService.summaryJson(idx.get("config"),
                            "modelMode", "initialKind", "duration"))
                    .setFinishedTime(EngineAfoSessionService.num(idx.get("finishedAt")));
            iginxClient.getWriteClient().writeMeasurement(row);
        } catch (Exception e) {
            log.warn("试车台记录清单同步失败: key={}", idx.get("taskId"), e);
        }
    }
}
