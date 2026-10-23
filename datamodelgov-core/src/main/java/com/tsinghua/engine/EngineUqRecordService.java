package com.tsinghua.engine;

import com.tsinghua.auth.util.AuthUtil;
import com.tsinghua.entity.EngineUqRecordEntity;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/** UQ评估记录清单服务(EngineProjectStore.saveUqRecord 挂钩同步;清单分页查询)。 */
@Slf4j
@Service
public class EngineUqRecordService extends IginxListService<EngineUqRecordEntity> {

    @Override
    protected String prefix() { return "relational_system.engine_uq_records"; }

    @Override
    protected Class<EngineUqRecordEntity> type() { return EngineUqRecordEntity.class; }

    @Override
    protected String idColumn() { return "uqId"; }

    @Override
    protected Long rowKeyOf(EngineUqRecordEntity row) { return row.getCreateTime(); }

    /** UQ发起/状态变更后同步清单行(按 uqId 覆写)。 */
    public void upsertFromUq(EngineModels.UqRecord r) {
        try {
            EngineUqRecordEntity row = queryByKey(r.getProjectId(), r.getId());
            long ts;
            if (row == null || row.getCreateTime() == null) {
                ts = r.getStartedAt() != null ? r.getStartedAt() : System.currentTimeMillis();
                while (tsTaken(ts)) ts++;
                row = new EngineUqRecordEntity();
                row.setOwner(AuthUtil.getCurrentUsername());
            } else {
                ts = row.getCreateTime();
            }
            row.setId(ts).setCreateTime(ts)
                    .setProjectId(r.getProjectId()).setUqId(r.getId()).setTaskId(r.getTaskId())
                    .setModelAssetId(r.getModelAssetId()).setModelName(r.getModelName())
                    .setMethod(r.getMethod()).setRunId(r.getRunId()).setStatus(r.getStatus())
                    .setMessage(r.getMessage()).setStartTime(r.getStartedAt()).setEndTime(r.getFinishedAt());
            iginxClient.getWriteClient().writeMeasurement(row);
        } catch (Exception e) {
            log.warn("UQ记录清单同步失败: uq={} status={}", r.getId(), r.getStatus(), e);
        }
    }
}
