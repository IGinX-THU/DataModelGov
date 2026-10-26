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
     *  空闲草稿(创建后从未执行任何动作:READY且无startedAt/无准备痕迹)不入运行记录,已有行则清理。 */
    public void upsertFromTask(EngineModels.ModelingTask t) throws Exception {
        boolean idle = "READY".equals(t.getStatus()) && t.getStartedAt() == null;
        EngineTaskRecordEntity exist = queryByKey(t.getProjectId(), t.getId());
        if (exist != null && (exist.getId() == null || exist.getCreateTime() == null)) {
            exist = null; // 读到的行缺主键/缺createTime(脏数据),视为不存在,按新行重建
        }
        if (idle) {
            if (exist != null) deleteRow(exist); // 清理历史遗留的空闲行
            return;
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
        deleteDuplicates(t.getProjectId(), t.getId(), ts);
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
        deleteDuplicates(row.getProjectId(), row.getTaskId(), ts);
    }

    /** 清理同键(projectId+taskId)的历史重复行:只保留 keepTs 时间戳那一行。 */
    private void deleteDuplicates(String projectId, String taskId, long keepTs) {
        try {
            List<EngineTaskRecordEntity> dups = executeList("SELECT * FROM " + RECORD_PREFIX
                    + " WHERE projectId = '" + esc(projectId) + "' AND taskId = '" + esc(taskId) + "';");
            List<String> ms = com.tsinghua.util.ConvertUtil.iginxFieldNamesConvert(
                    EngineTaskRecordEntity.class, RECORD_PREFIX);
            for (EngineTaskRecordEntity d : dups) {
                Long key = d.getCreateTime();
                if (key == null || key == keepTs) continue;
                iginxClient.getDeleteClient().deleteMeasurementsData(ms, key - 1, key + 1);
                log.warn("运行记录清理同键重复行: taskId={} ts={}", taskId, key);
            }
        } catch (Exception e) {
            log.warn("运行记录重复行清理失败: taskId={}", taskId, e);
        }
    }

    /** 全项目按 taskId 去重(历史脏数据修复:backfillId修复前每次saveTask都会多写一行)。
     *  每个任务只保留 createTime 最新的一行,其余删除;返回删除行数。 */
    public int dedupeByTask(String projectId) {
        try {
            List<EngineTaskRecordEntity> rows = queryList(projectId, null, null);
            if (rows.size() < 2) return 0;
            java.util.Map<String, EngineTaskRecordEntity> keep = new java.util.LinkedHashMap<>();
            List<EngineTaskRecordEntity> stale = new java.util.ArrayList<>();
            // rows按createTime倒序:首次出现即最新,后续同taskId的为旧行
            for (EngineTaskRecordEntity r : rows) {
                if (r.getTaskId() == null) continue;
                // 空闲任务(READY且从未运行)不入记录;历史行一并清理
                if ("READY".equals(r.getStatus()) && r.getStartTime() == null) { stale.add(r); continue; }
                if (!keep.containsKey(r.getTaskId())) keep.put(r.getTaskId(), r);
                else stale.add(r);
            }
            for (EngineTaskRecordEntity d : stale) deleteRow(d);
            if (!stale.isEmpty()) {
                log.info("运行记录按taskId去重: 项目{}删除{}条历史重复行", projectId, stale.size());
            }
            return stale.size();
        } catch (Exception e) {
            log.warn("运行记录去重失败: projectId={}", projectId, e);
            return 0;
        }
    }

    /** 按行时间戳删除记录行(空闲草稿清理)。 */
    public void deleteRow(EngineTaskRecordEntity row) {
        try {
            List<String> ms = com.tsinghua.util.ConvertUtil.iginxFieldNamesConvert(
                    EngineTaskRecordEntity.class, RECORD_PREFIX);
            Long key = row.getCreateTime() != null ? row.getCreateTime() : row.getId();
            if (key == null) return;
            iginxClient.getDeleteClient().deleteMeasurementsData(ms, key - 1, key + 1);
        } catch (Exception e) {
            log.warn("运行记录行删除失败: taskId={}", row.getTaskId(), e);
        }
    }
}
