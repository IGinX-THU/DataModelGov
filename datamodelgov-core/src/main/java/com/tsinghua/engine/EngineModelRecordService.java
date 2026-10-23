package com.tsinghua.engine;

import com.tsinghua.auth.util.AuthUtil;
import com.tsinghua.entity.EngineModelAssetEntity;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/** 模型成果清单服务(EngineProjectStore.saveModel 挂钩同步;清单分页查询)。 */
@Slf4j
@Service
public class EngineModelRecordService extends IginxListService<EngineModelAssetEntity> {

    @Override
    protected String prefix() { return "relational_system.engine_model_assets"; }

    @Override
    protected Class<EngineModelAssetEntity> type() { return EngineModelAssetEntity.class; }

    @Override
    protected String idColumn() { return "modelId"; }

    @Override
    protected Long rowKeyOf(EngineModelAssetEntity row) { return row.getCreateTime(); }

    /** 模型登记/更新后同步清单行(新模型建行,已有按 modelId 覆写)。 */
    public void upsertFromModel(EngineModels.ModelAsset m) {
        try {
            EngineModelAssetEntity row = queryByKey(m.getProjectId(), m.getId());
            long ts;
            if (row == null || row.getCreateTime() == null) {
                ts = m.getCreatedAt() != null ? m.getCreatedAt() : System.currentTimeMillis();
                while (tsTaken(ts)) ts++;
                row = new EngineModelAssetEntity();
                row.setOwner(AuthUtil.getCurrentUsername());
            } else {
                ts = row.getCreateTime();
            }
            row.setId(ts).setCreateTime(ts)
                    .setProjectId(m.getProjectId()).setModelId(m.getId()).setTaskId(m.getTaskId())
                    .setName(m.getName()).setSourceBusiness(m.getSourceBusiness()).setStage(m.getStage())
                    .setRoute(m.getRoute()).setResultStatus(m.getResultStatus()).setEngineId(m.getEngineId())
                    .setParentModelId(m.getParentModelId())
                    .setUqCount(m.getUqRecordIds() == null ? 0 : m.getUqRecordIds().size())
                    .setDeliveryFile(m.getDeliveryWorkbookFile());
            iginxClient.getWriteClient().writeMeasurement(row);
        } catch (Exception e) {
            log.warn("模型成果清单同步失败: model={} status={}", m.getId(), m.getResultStatus(), e);
        }
    }
}
