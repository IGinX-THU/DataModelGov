package com.tsinghua.engine;

import com.tsinghua.auth.util.AuthUtil;
import com.tsinghua.entity.EngineTaskRecordEntity;
import java.util.List;
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

    /** 任务档案同步到清单行(新任务建行,已有按 taskId 覆写;createTime 列必须非空)。
     *  只增不删:凡执行过MATLAB动作(准备/辨识/评估,以startedAt或prepMessage为痕迹)都保留记录行;
     *  仅"创建后从未执行任何动作"的草稿跳过写入,不做任何删除。 */
    public void upsertFromTask(EngineModels.ModelingTask t) throws Exception {
        boolean hasAction = t.getStartedAt() != null
                || (t.getPrepMessage() != null && !t.getPrepMessage().trim().isEmpty());
        boolean idle = "READY".equals(t.getStatus()) && !hasAction;
        EngineTaskRecordEntity exist = queryByKey(t.getProjectId(), t.getId());
        if (exist != null && (exist.getId() == null || exist.getCreateTime() == null)) {
            exist = null; // 读到的行缺主键/缺createTime(脏数据),视为不存在,按新行重建
        }
        if (idle) {
            return; // 草稿不入运行记录;已执行过的任务(startedAt/prepMessage在档)不受影响,不删除任何行
        }
        EngineTaskRecordEntity row;
        long ts;
        if (exist == null) {
            ts = t.getCreatedAt() != null ? t.getCreatedAt() : System.currentTimeMillis();
            while (tsTaken(ts)) ts++; // 行时间戳全局唯一,被其他任务占用则后移
            row = new EngineTaskRecordEntity();
            row.setOwner(AuthUtil.getCurrentUsername());
        } else {
            ts = exist.getCreateTime();
            row = new EngineTaskRecordEntity();
            row.setOwner(exist.getOwner() == null ? AuthUtil.getCurrentUsername() : exist.getOwner());
        }
        row.setId(ts).setCreateTime(ts) // ORDER BY createTime遇null值IginX服务端会NPE,必须非空
                .setProjectId(t.getProjectId()).setTaskId(t.getId()).setKind(t.getKind())
                .setName(t.getName()).setRunId(t.getRunId()).setStatus(t.getStatus())
                .setErrorKind(t.getErrorKind()).setMessage(t.getMessage())
                .setStartTime(t.getStartedAt()).setEndTime(t.getFinishedAt());
        iginxClient.getWriteClient().writeMeasurement(row);
    }

    /** 通用执行行upsert(按projectId+taskId键;用于不确定性评估/输出预测等阶段行)。 */
    public void upsertRow(EngineTaskRecordEntity row) throws Exception {
        EngineTaskRecordEntity exist = queryByKey(row.getProjectId(), row.getTaskId());
        if (exist != null && (exist.getId() == null || exist.getCreateTime() == null)) exist = null;
        long ts;
        if (exist == null) {
            ts = row.getCreateTime() != null ? row.getCreateTime() : System.currentTimeMillis();
            while (tsTaken(ts)) ts++;
            if (row.getOwner() == null || row.getOwner().trim().isEmpty()) {
                row.setOwner(AuthUtil.getCurrentUsername());
            }
        } else {
            ts = exist.getCreateTime();
            if (row.getOwner() == null || row.getOwner().trim().isEmpty()) row.setOwner(exist.getOwner());
        }
        row.setId(ts).setCreateTime(ts);
        iginxClient.getWriteClient().writeMeasurement(row);
    }
}
