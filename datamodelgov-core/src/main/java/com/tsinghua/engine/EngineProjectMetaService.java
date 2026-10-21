package com.tsinghua.engine;

import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import com.tsinghua.auth.util.AuthUtil;
import com.tsinghua.entity.EngineProjectEntity;
import com.tsinghua.util.ConvertUtil;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;

/**
 * 工作台项目元数据的 IginX 存取(与旧版程序管理 programs_meta 同模式):
 * 写入 writeMeasurement;列表/计数走 SQL,用户隔离用 owner 条件(管理员可见全部),
 * 分页 LIMIT/OFFSET。任务/模型/预测大对象仍由 EngineProjectStore 文件存储。
 */
@Slf4j
@Service
public class EngineProjectMetaService {

    public static final String META_PREFIX = "relational_system.engine_projects";

    @Autowired
    private IginXClient iginxClient;

    @Autowired
    private Session iginxSession;

    public EngineProjectEntity save(EngineProjectEntity entity) throws Exception {
        if (entity.getId() == null) {
            entity.setId(System.currentTimeMillis());
        }
        if (entity.getCreateTime() == null) {
            entity.setCreateTime(entity.getId());
        }
        if (entity.getOwner() == null || entity.getOwner().trim().isEmpty()) {
            entity.setOwner(AuthUtil.getCurrentUsername());
        }
        iginxClient.getWriteClient().writeMeasurement(entity);
        return entity;
    }

    public EngineProjectEntity queryById(Long id) {
        if (id == null) return null;
        try {
            String sql = String.format("SELECT * FROM %s WHERE id = %s LIMIT 1;", META_PREFIX, id);
            return queryOne(sql);
        } catch (Exception e) {
            log.error("查询工作台项目失败: id={}", id, e);
            return null;
        }
    }

    public EngineProjectEntity queryByName(String name) {
        if (name == null || name.trim().isEmpty()) return null;
        try {
            String sql = String.format("SELECT * FROM %s WHERE name = '%s' LIMIT 1;", META_PREFIX, name.trim());
            return queryOne(sql);
        } catch (Exception e) {
            log.error("查询工作台项目失败: name={}", name, e);
            return null;
        }
    }

    /** 分页列表:管理员可见全部,普通用户仅本人项目(owner SQL 条件,与旧版程序列表一致)。 */
    public List<EngineProjectEntity> queryList(String name, Integer pageNum, Integer pageSize) {
        List<EngineProjectEntity> out = new ArrayList<>();
        try {
            StringBuilder sql = new StringBuilder("SELECT * FROM " + META_PREFIX + " WHERE 1=1");
            appendFilter(sql, name);
            if (!AuthUtil.isAdmin()) {
                sql.append(" AND owner = '").append(AuthUtil.getCurrentUsername()).append("'");
            }
            if (pageNum != null && pageSize != null) {
                sql.append(" LIMIT ").append(pageSize);
                sql.append(" OFFSET ").append((pageNum - 1) * pageSize);
            }
            sql.append(";");
            out.addAll(executeList(sql.toString()));
        } catch (Exception e) {
            log.error("查询工作台项目列表失败", e);
        }
        return out;
    }

    /** 与列表同过滤条件的总数(用户隔离口径一致)。 */
    public long countList(String name) {
        try {
            StringBuilder sql = new StringBuilder("SELECT COUNT(1) FROM " + META_PREFIX + " WHERE 1=1");
            appendFilter(sql, name);
            if (!AuthUtil.isAdmin()) {
                sql.append(" AND owner = '").append(AuthUtil.getCurrentUsername()).append("'");
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
            log.error("统计工作台项目总数失败", e);
            return 0;
        }
    }

    private void appendFilter(StringBuilder sql, String name) {
        if (name != null && !name.trim().isEmpty()) {
            sql.append(" AND name LIKE '^.*").append(name.trim()).append(".*'");
        }
    }

    private EngineProjectEntity queryOne(String sql) throws Exception {
        List<EngineProjectEntity> list = executeList(sql);
        return list.isEmpty() ? null : list.get(0);
    }

    private List<EngineProjectEntity> executeList(String sql) throws Exception {
        List<EngineProjectEntity> out = new ArrayList<>();
        cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult res = iginxSession.executeSql(sql);
        List<java.util.Map<String, Object>> records = ConvertUtil.getRecords(res);
        if (records == null) return out;
        for (java.util.Map<String, Object> row : records) {
            EngineProjectEntity e = new EngineProjectEntity();
            ConvertUtil.mapToEntity(e, row, META_PREFIX);
            if (e.getId() == null) {
                // id 是行时间戳主键,SELECT * 的返回列不含它;save 时保证 createTime == id,用其回填
                Object rawId = row.get("id") != null ? row.get("id") : row.get(META_PREFIX + ".id");
                if (rawId instanceof Number) {
                    e.setId(((Number) rawId).longValue());
                } else if (e.getCreateTime() != null) {
                    e.setId(e.getCreateTime());
                }
            }
            out.add(e);
        }
        return out;
    }
}
