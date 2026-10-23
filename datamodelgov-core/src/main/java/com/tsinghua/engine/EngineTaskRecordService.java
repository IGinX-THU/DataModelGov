package com.tsinghua.engine;

import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import com.tsinghua.auth.util.AuthUtil;
import com.tsinghua.entity.EngineTaskRecordEntity;
import com.tsinghua.util.ConvertUtil;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;

/**
 * 建模任务运行记录的 IginX 存取(与 EngineProjectMetaService 同模式):
 * 任务保存时 upsert(行时间戳=任务创建时间,状态变更覆写同行);
 * 列表/计数走 SQL(owner 条件隔离,管理员可见全部,LIMIT/OFFSET 分页)。
 */
@Slf4j
@Service
public class EngineTaskRecordService {

    public static final String RECORD_PREFIX = "relational_system.engine_task_records";

    @Autowired
    private IginXClient iginxClient;

    @Autowired
    private Session iginxSession;

    /** 由任务档案(文件存储的唯一事实源)同步一行运行记录;新任务建行,已存在按行时间戳覆写(upsert)。 */
    public void upsertFromTask(EngineModels.ModelingTask t) throws Exception {
        EngineTaskRecordEntity row = queryByTaskId(t.getId());
        if (row != null && (row.getId() == null || row.getCreateTime() == null)) {
            row = null; // 读到的行缺主键/缺createTime(脏数据),视为不存在,按新行重建
        }
        long ts;
        if (row == null) {
            ts = t.getCreatedAt() != null ? t.getCreatedAt() : System.currentTimeMillis();
            while (queryById(ts) != null) ts++; // 行时间戳全局唯一,被其他任务占用则后移
            row = new EngineTaskRecordEntity();
            row.setOwner(AuthUtil.getCurrentUsername());
        } else {
            // 行时间戳=createTime(save保证相等);读回来的行经反序列化id已由createTime回填
            ts = row.getId() != null ? row.getId() : (row.getCreateTime() != null ? row.getCreateTime() : System.currentTimeMillis());
        }
        row.setId(ts);
        row.setCreateTime(ts); // createTime列必须非空:ORDER BY createTime遇null值IginX服务端会NPE
        row.setProjectId(t.getProjectId());
        row.setTaskId(t.getId());
        row.setKind(t.getKind());
        row.setName(t.getName());
        row.setRunId(t.getRunId());
        row.setStatus(t.getStatus());
        row.setErrorKind(t.getErrorKind());
        row.setMessage(t.getMessage());
        row.setStartTime(t.getStartedAt());
        row.setEndTime(t.getFinishedAt());
        iginxClient.getWriteClient().writeMeasurement(row);
    }

    /** 分页列表:管理员可见全部,普通用户仅本人记录(owner SQL 条件,与项目列表一致)。 */
    public List<EngineTaskRecordEntity> queryList(String projectId, String kind, Integer pageNum, Integer pageSize) {
        List<EngineTaskRecordEntity> out = new ArrayList<>();
        try {
            StringBuilder sql = new StringBuilder("SELECT * FROM " + RECORD_PREFIX + " WHERE projectId = '")
                    .append(esc(projectId)).append("'");
            appendFilter(sql, kind);
            if (!AuthUtil.isAdmin()) {
                sql.append(" AND owner = '").append(esc(AuthUtil.getCurrentUsername())).append("'");
            }
            sql.append(" ORDER BY createTime DESC ");
            if (pageNum != null && pageSize != null) {
                sql.append(" LIMIT ").append(pageSize);
                sql.append(" OFFSET ").append((pageNum - 1) * pageSize);
            }
            sql.append(";");
            out.addAll(executeList(sql.toString()));
        } catch (Exception e) {
            log.error("查询建模任务运行记录失败: projectId={}", projectId, e);
        }
        return out;
    }

    /** 与列表同过滤条件的总数(用户隔离口径一致)。 */
    public long countList(String projectId, String kind) {
        try {
            StringBuilder sql = new StringBuilder("SELECT COUNT(1) FROM " + RECORD_PREFIX + " WHERE projectId = '")
                    .append(esc(projectId)).append("'");
            appendFilter(sql, kind);
            if (!AuthUtil.isAdmin()) {
                sql.append(" AND owner = '").append(esc(AuthUtil.getCurrentUsername())).append("'");
            }
            sql.append(";");
            cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult res = iginxSession.executeSql(sql.toString());
            List<java.util.Map<String, Object>> records = ConvertUtil.getRecords(res);
            if (records == null || records.isEmpty()) return 0;
            java.util.Map<String, Object> first = records.get(0);
            if (first == null || first.isEmpty()) return 0;
            Object v = first.values().iterator().next();
            return v instanceof Number ? ((Number) v).longValue() : Long.parseLong(String.valueOf(v));
        } catch (Exception e) {
            log.error("统计建模任务运行记录总数失败: projectId={}", projectId, e);
            return 0;
        }
    }

    public EngineTaskRecordEntity queryByTaskId(String taskId) {
        if (taskId == null || taskId.isEmpty()) return null;
        try {
            String sql = "SELECT * FROM " + RECORD_PREFIX + " WHERE taskId = '" + esc(taskId) + "' LIMIT 1;";
            List<EngineTaskRecordEntity> list = executeList(sql);
            return list.isEmpty() ? null : list.get(0);
        } catch (Exception e) {
            log.warn("按taskId查询运行记录失败: taskId={}", taskId, e);
            return null;
        }
    }

    /** 行时间戳查重(upsert 建行时防撞车)。注意:id 是行时间戳主键,不是可查询列,
     *  须按 createTime 过滤(与 EngineProjectMetaService.queryById 同模式)。 */
    private EngineTaskRecordEntity queryById(long id) {
        try {
            String sql = "SELECT * FROM " + RECORD_PREFIX + " WHERE createTime = " + id + " LIMIT 1;";
            List<EngineTaskRecordEntity> list = executeList(sql);
            return list.isEmpty() ? null : list.get(0);
        } catch (Exception e) {
            return null;
        }
    }

    private void appendFilter(StringBuilder sql, String kind) {
        if (kind != null && !kind.trim().isEmpty()) {
            sql.append(" AND kind = '").append(esc(kind.trim())).append("'");
        }
    }

    private String esc(String s) {
        return s == null ? "" : s.replace("'", "''");
    }

    private List<EngineTaskRecordEntity> executeList(String sql) throws Exception {
        List<EngineTaskRecordEntity> out = new ArrayList<>();
        cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult res = iginxSession.executeSql(sql);
        List<java.util.Map<String, Object>> records = ConvertUtil.getRecords(res);
        if (records == null) return out;
        for (java.util.Map<String, Object> row : records) {
            EngineTaskRecordEntity e = new EngineTaskRecordEntity();
            ConvertUtil.mapToEntity(e, row, RECORD_PREFIX);
            if (e.getId() == null) {
                Object rawId = row.get("id") != null ? row.get("id") : row.get(RECORD_PREFIX + ".id");
                if (rawId instanceof Number) e.setId(((Number) rawId).longValue());
                else if (e.getCreateTime() != null) e.setId(e.getCreateTime());
            }
            out.add(e);
        }
        return out;
    }
}
