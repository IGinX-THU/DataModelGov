package com.tsinghua.engine;

import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import com.tsinghua.auth.util.AuthUtil;
import com.tsinghua.entity.FileLibraryEntity;
import com.tsinghua.util.ConvertUtil;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.List;

/**
 * 项目文件库索引的 IginX 存取(与 engine_projects 同模式):
 * 写入 writeMeasurement;分页/计数走 SQL,用户隔离用 owner 条件(管理员可见全部),
 * LIMIT/OFFSET 分页。文件本体在项目工作目录 files/{category}/ 下,
 * IginX 分块备份与恢复由 FileBackupService 负责。
 */
@Slf4j
@Service
public class FileLibraryMetaService {

    public static final String META_PREFIX = "relational_system.file_library";

    @Autowired
    private IginXClient iginxClient;

    @Autowired
    private Session iginxSession;

    public FileLibraryEntity save(FileLibraryEntity entity) throws Exception {
        if (entity.getId() == null) {
            entity.setId(System.currentTimeMillis());
        }
        if (entity.getCreatedAt() == null) {
            entity.setCreatedAt(entity.getId());
        }
        if (entity.getOwner() == null || entity.getOwner().trim().isEmpty()) {
            entity.setOwner(AuthUtil.getCurrentUsername());
        }
        iginxClient.getWriteClient().writeMeasurement(entity);
        return entity;
    }

    public FileLibraryEntity queryById(Long id) {
        if (id == null) return null;
        try {
            String sql = String.format("SELECT * FROM %s WHERE createTime = %s LIMIT 1;", META_PREFIX, id);
            return queryOne(sql);
        } catch (Exception e) {
            log.warn("按createTime查询文件库条目失败: id={}", id, e);
            return null;
        }
    }

    /** 分页列表:管理员可见全部,普通用户仅本人文件(owner SQL 条件)。 */
    public List<FileLibraryEntity> queryPage(String category, String name, Integer pageNum, Integer pageSize) {
        List<FileLibraryEntity> out = new java.util.ArrayList<>();
        try {
            String sql = buildQuerySql(category, name, pageNum, pageSize);
            out.addAll(executeList(sql));
        } catch (Exception e) {
            log.error("查询文件库列表失败", e);
        }
        return out;
    }

    public long countPage(String category, String name) {
        try {
            StringBuilder sql = new StringBuilder("SELECT COUNT(1) FROM " + META_PREFIX + " WHERE 1=1");
            appendFilter(sql, category, name);
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
            log.error("统计文件库总数失败", e);
            return 0;
        }
    }

    private String buildQuerySql(String category, String name, Integer pageNum, Integer pageSize) {
        StringBuilder sql = new StringBuilder("SELECT * FROM " + META_PREFIX + " WHERE 1=1");
        appendFilter(sql, category, name);
        if (!AuthUtil.isAdmin()) {
            sql.append(" AND owner = '").append(AuthUtil.getCurrentUsername()).append("'");
        }
        sql.append(" ORDER BY createTime DESC ");
        if (pageNum != null && pageSize != null) {
            sql.append(" LIMIT ").append(pageSize);
            sql.append(" OFFSET ").append((pageNum - 1) * pageSize);
        }
        sql.append(";");
        return sql.toString();
    }

    private void appendFilter(StringBuilder sql, String category, String name) {
        if (category != null && !category.trim().isEmpty()) {
            sql.append(" AND category = '").append(category.trim()).append("'");
        }
        if (name != null && !name.trim().isEmpty()) {
            sql.append(" AND name LIKE '^.*").append(name.trim()).append(".*'");
        }
    }

    /** 删除索引行——SQL DELETE 不允许值过滤,走 DeleteClient 时间戳区间(行时间戳=createdAt=id)。 */
    public boolean delete(Long id) {
        if (id == null) return false;
        try {
            List<String> measurements =
                    ConvertUtil.iginxFieldNamesConvert(FileLibraryEntity.class, META_PREFIX);
            iginxClient.getDeleteClient().deleteMeasurementsData(measurements, id - 1, id + 1);
        } catch (Exception e) {
            log.error("删除文件库索引失败: id={}", id, e);
            return false;
        }
        return queryById(id) == null;
    }

    private FileLibraryEntity queryOne(String sql) throws Exception {
        List<FileLibraryEntity> list = executeList(sql);
        return list.isEmpty() ? null : list.get(0);
    }

    private List<FileLibraryEntity> executeList(String sql) throws Exception {
        List<FileLibraryEntity> out = new java.util.ArrayList<>();
        cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult res = iginxSession.executeSql(sql);
        List<java.util.Map<String, Object>> records = ConvertUtil.getRecords(res);
        if (records == null) return out;
        for (java.util.Map<String, Object> row : records) {
            FileLibraryEntity e = new FileLibraryEntity();
            ConvertUtil.mapToEntity(e, row, META_PREFIX);
            if (e.getId() == null) {
                Object rawId = row.get("id") != null ? row.get("id") : row.get(META_PREFIX + ".id");
                if (rawId instanceof Number) {
                    e.setId(((Number) rawId).longValue());
                } else if (e.getCreatedAt() != null) {
                    e.setId(e.getCreatedAt());
                }
            }
            out.add(e);
        }
        return out;
    }
}
