package com.tsinghua.engine;

import com.tsinghua.auth.util.AuthUtil;
import com.tsinghua.entity.EngineTaskRecordEntity;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 建模任务运行记录清单服务(EngineProjectStore.saveTask 挂钩同步;清单分页查询)。
 * 注意:id 是行时间戳主键,不是可查询列,须按 createTime 过滤(与项目服务同模式)。
 */
@Slf4j
@Service
public class EngineTaskRecordService extends IginxListService<EngineTaskRecordEntity> {

    public static final String RECORD_PREFIX = "relational_system.engine_task_records";

    @Override
    protected String prefix() { return RECORD_PREFIX; }

    @Override
    protected Class<EngineTaskRecordEntity> type() { return EngineTaskRecordEntity.class; }

    @Override
    protected String idColumn() { return "taskId"; }

    @Override
    protected Long rowKeyOf(EngineTaskRecordEntity row) { return row.getCreateTime(); }

    /** 任务档案同步到清单行(新任务建行,已有按 taskId 覆写;createTime 列必须非空)。 */
    public void upsertFromTask(EngineModels.ModelingTask t) throws Exception {
        EngineTaskRecordEntity row = queryByKey(t.getProjectId(), t.getId());
        if (row != null && (row.getId() == null || row.getCreateTime() == null)) {
            row = null; // 读到的行缺主键/缺createTime(脏数据),视为不存在,按新行重建
        }
        long ts;
        if (row == null) {
            ts = t.getCreatedAt() != null ? t.getCreatedAt() : System.currentTimeMillis();
            while (tsTaken(ts)) ts++; // 行时间戳全局唯一,被其他任务占用则后移
            row = new EngineTaskRecordEntity();
            row.setOwner(AuthUtil.getCurrentUsername());
        } else {
            ts = row.getCreateTime();
        }
        row.setId(ts).setCreateTime(ts) // ORDER BY createTime遇null值IginX服务端会NPE,必须非空
                .setProjectId(t.getProjectId()).setTaskId(t.getId()).setKind(t.getKind())
                .setName(t.getName()).setRunId(t.getRunId()).setStatus(t.getStatus())
                .setErrorKind(t.getErrorKind()).setMessage(t.getMessage())
                .setStartTime(t.getStartedAt()).setEndTime(t.getFinishedAt());
        iginxClient.getWriteClient().writeMeasurement(row);
    }
}
