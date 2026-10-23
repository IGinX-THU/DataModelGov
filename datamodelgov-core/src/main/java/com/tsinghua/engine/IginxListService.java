package com.tsinghua.engine;

import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import com.tsinghua.util.ConvertUtil;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;

import java.util.ArrayList;
import java.util.List;

/**
 * IginX 关系表清单分页基类(与 EngineProjectMetaService/EngineTaskRecordService 同模式)。
 * 约定:文件 JSON 为唯一事实源,本族服务只承担 SQL 分页查询/计数/清理;
 * 行时间戳主键 = 记录创建时间(id 列即 createTime,SELECT 不返回行时间戳,
 * 反序列化时按 createTime 回填),按自然键(模型id/UQid/预测id/runId/taskKey)upsert 覆写。
 * 项目归属访问控制由 Controller 的 accessDenied(project) 负责,SQL 不再按 owner 过滤
 * (共享项目内所有协作者应看到同一份清单);owner 列仅作审计留痕。
 */
@Slf4j
public abstract class IginxListService<T> {

    @Autowired
    protected IginXClient iginxClient;

    @Autowired
    protected Session iginxSession;

    /** 关系表全名,如 relational_system.engine_model_assets。 */
    protected abstract String prefix();

    protected abstract Class<T> type();

    /** 自然键列名(项目内唯一):modelId/uqId/recId/runId/taskKey。 */
    protected abstract String idColumn();

    protected String esc(String s) {
        return s == null ? "" : s.replace("'", "''");
    }

    protected List<String> measurements() {
        return ConvertUtil.iginxFieldNamesConvert(type(), prefix());
    }

    /** 分页列表:ORDER BY createTime DESC LIMIT/OFFSET。 */
    public List<T> queryList(String projectId, Integer pageNum, Integer pageSize) {
        return queryFiltered(projectId, pageNum, pageSize, null);
    }

    /** 带额外过滤条件的分页列表(extraWhere 为调用方拼好的 SQL 片段,须自行转义;传 null/空则同 queryList)。 */
    public List<T> queryFiltered(String projectId, Integer pageNum, Integer pageSize, String extraWhere) {
        List<T> out = new ArrayList<>();
        try {
            StringBuilder sql = new StringBuilder("SELECT * FROM ").append(prefix())
                    .append(" WHERE projectId = '").append(esc(projectId)).append("'");
            if (extraWhere != null && !extraWhere.trim().isEmpty()) {
                sql.append(" AND ").append(extraWhere.trim());
            }
            sql.append(" ORDER BY createTime DESC");
            if (pageNum != null && pageSize != null) {
                sql.append(" LIMIT ").append(Math.max(1, pageSize))
                        .append(" OFFSET ").append((Math.max(1, pageNum) - 1) * Math.max(1, pageSize));
            }
            sql.append(";");
            out.addAll(executeList(sql.toString()));
        } catch (Exception e) {
            log.error("查询{}失败: projectId={}", prefix(), projectId, e);
        }
        return out;
    }

    /** 与列表同口径总数。 */
    public long countList(String projectId) {
        return countFiltered(projectId, null);
    }

    /** 带额外过滤条件的总数(与 queryFiltered 同口径)。 */
    public long countFiltered(String projectId, String extraWhere) {
        try {
            StringBuilder sql = new StringBuilder("SELECT COUNT(1) FROM ").append(prefix())
                    .append(" WHERE projectId = '").append(esc(projectId)).append("'");
            if (extraWhere != null && !extraWhere.trim().isEmpty()) {
                sql.append(" AND ").append(extraWhere.trim());
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
            log.error("统计{}总数失败: projectId={}", prefix(), projectId, e);
            return 0;
        }
    }

    /** 项目内全量(删除项目时逐行清理用)。 */
    public List<T> queryAll(String projectId) {
        return queryList(projectId, null, null);
    }

    /** 项目内按自然键查单行(upsert 定位)。 */
    public T queryByKey(String projectId, String key) {
        if (key == null || key.isEmpty()) return null;
        try {
            String sql = "SELECT * FROM " + prefix() + " WHERE projectId = '" + esc(projectId)
                    + "' AND " + idColumn() + " = '" + esc(key) + "' LIMIT 1;";
            List<T> list = executeList(sql);
            return list.isEmpty() ? null : list.get(0);
        } catch (Exception e) {
            log.warn("按{}查询失败: {} / {}", idColumn(), projectId, key, e);
            return null;
        }
    }

    /** 行时间戳占用检查(建行防撞车;撞车则调用方后移时间戳)。 */
    public boolean tsTaken(long ts) {
        try {
            List<T> rows = executeList("SELECT createTime FROM " + prefix()
                    + " WHERE createTime = " + ts + " LIMIT 1;");
            return !rows.isEmpty();
        } catch (Exception e) {
            return false;
        }
    }

    /** 删除项目下全部清单行(IginX DELETE 不支持值过滤,先查键再按时间戳区间删除)。 */
    public int deleteByProject(String projectId) throws Exception {
        List<T> rows = queryAll(projectId);
        int n = 0;
        List<String> ms = measurements();
        for (T row : rows) {
            Long key = rowKeyOf(row);
            if (key == null) continue;
            iginxClient.getDeleteClient().deleteMeasurementsData(ms, key - 1, key + 1);
            n++;
        }
        return n;
    }

    /** 行删除键 = createTime(与行时间戳相等,upsert 保证非空)。 */
    protected abstract Long rowKeyOf(T row);

    /** SQL → 实体(通用列映射;id 行时间戳 SELECT 不返回,按 createTime 回填)。 */
    protected List<T> executeList(String sql) throws Exception {
        List<T> out = new ArrayList<>();
        cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult res = iginxSession.executeSql(sql);
        List<java.util.Map<String, Object>> records = ConvertUtil.getRecords(res);
        if (records == null) return out;
        for (java.util.Map<String, Object> m : records) {
            if (m == null || m.isEmpty()) continue;
            T e = type().newInstance();
            ConvertUtil.mapToEntity(e, m, prefix());
            backfillId(e);
            out.add(e);
        }
        return out;
    }

    /** 实体统一含 id/createTime(Long):id 缺失时以 createTime 兜底。 */
    private void backfillId(T e) {
        try {
            java.lang.reflect.Method setCreateTime = type().getMethod("setCreateTime", Long.class);
            Object ct = setCreateTime.invoke(e);
            java.lang.reflect.Method setId = type().getMethod("setId", Long.class);
            if (ct != null && setId.invoke(e) == null) setId.invoke(e, ct);
        } catch (Exception ignore) {
        }
    }
}
