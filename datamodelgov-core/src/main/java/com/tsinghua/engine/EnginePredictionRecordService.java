package com.tsinghua.engine;

import com.tsinghua.auth.util.AuthUtil;
import com.tsinghua.entity.EnginePredictionEntity;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/** 输出预测记录清单服务(EngineProjectStore.savePrediction 挂钩同步;清单分页查询)。 */
@Slf4j
@Service
public class EnginePredictionRecordService extends IginxListService<EnginePredictionEntity> {

    @Override
    protected String prefix() { return "relational_system.engine_predictions"; }

    @Override
    protected Class<EnginePredictionEntity> type() { return EnginePredictionEntity.class; }

    @Override
    protected String idColumn() { return "recId"; }

    @Override
    protected Long rowKeyOf(EnginePredictionEntity row) { return row.getCreateTime(); }

    /** 预测发起/状态变更后同步清单行(按 recId 覆写)。 */
    public void upsertFromPrediction(EngineModels.PredictionRecord r) {
        try {
            EnginePredictionEntity row = queryByKey(r.getProjectId(), r.getId());
            long ts;
            if (row == null || row.getCreateTime() == null) {
                ts = r.getCreatedAt() != null ? r.getCreatedAt() : System.currentTimeMillis();
                while (tsTaken(ts)) ts++;
                row = new EnginePredictionEntity();
                row.setOwner(AuthUtil.getCurrentUsername());
            } else {
                ts = row.getCreateTime();
            }
            row.setId(ts).setCreateTime(ts)
                    .setProjectId(r.getProjectId()).setRecId(r.getId()).setModelAssetId(r.getModelAssetId())
                    .setModelName(r.getModelName()).setRunId(r.getRunId()).setStatus(r.getStatus())
                    .setMessage(r.getMessage())
                    .setConditionCount(r.getConditions() == null ? 0 : r.getConditions().size())
                    .setUqRecordId(r.getUqRecordId())
                    .setFinishedTime(r.getFinishedAt());
            iginxClient.getWriteClient().writeMeasurement(row);
        } catch (Exception e) {
            log.warn("预测记录清单同步失败: rec={} status={}", r.getId(), r.getStatus(), e);
        }
    }
}
