package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.WriteClient;
import com.tsinghua.entity.DataArchiveEntity;
import com.tsinghua.entity.ModelMetaEntity;
import com.tsinghua.util.ConvertUtil;
import com.tsinghua.util.ProjectContext;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.util.*;
import java.util.stream.Collectors;

/**
 * 数据档案服务
 * 用于管理数据档案的CRUD操作
 */
@Slf4j
@Service
public class DataArchiveService {

    private static final String DATA_ARCHIVE_PREFIX = "relational_system.data_archives";

    @Autowired
    private Session iginxSession;

    @Autowired
    private IginXClient iginxClient;

    /**
     * 保存数据档案（新增或编辑）
     */
    public void saveArchive(DataArchiveEntity archive) throws Exception {
        long timestamp;
        if (archive.getId() != null) {
            timestamp = archive.getId();
        } else if (archive.getCreateTime() != null) {
            timestamp = archive.getCreateTime();
        } else {
            timestamp = System.currentTimeMillis();
        }

        archive.setId(timestamp);
        archive.setCreateTime(timestamp);

        if (!StringUtils.hasText(archive.getProjectName())) {
            archive.setProjectName(ProjectContext.getCurrentProject("unknown"));
        }

        if (!StringUtils.hasText(archive.getOwner())) {
            archive.setOwner(com.tsinghua.auth.util.AuthUtil.getCurrentUsername());
        }

        log.info("准备保存数据档案到IginX: name={}, type={}, desc={}", archive.getName(), archive.getType(), archive.getDesc());

        WriteClient writeClient = iginxClient.getWriteClient();
        writeClient.writeMeasurement(archive);

        log.info("数据档案已保存。名称: {}, 类型: {}, 时间戳: {}", archive.getName(), archive.getType(), timestamp);
    }

    /**
     * 查询单个数据档案
     */
    public DataArchiveEntity queryArchive(Long id) {
        try {
            if (id == null) {
                return null;
            }
            String sql = String.format("SELECT * FROM %s WHERE id = %s LIMIT 1;", DATA_ARCHIVE_PREFIX, id);
            log.info("执行SQL: {}", sql);

            SessionExecuteSqlResult res = iginxSession.executeSql(sql);
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);

            if (records.isEmpty()) {
                return null;
            }

            DataArchiveEntity entity = new DataArchiveEntity();
            Map<String, Object> rs = records.get(0);
            return ConvertUtil.mapToEntity(entity, rs, DATA_ARCHIVE_PREFIX);
        } catch (Exception e) {
            log.error("查询数据档案失败", e);
            return null;
        }
    }

    /**
     * 根据名称查询单个数据档案
     */
    public DataArchiveEntity findByName(String name) {
        try {
            if (name == null || name.trim().isEmpty()) {
                return null;
            }
            String sql = String.format("SELECT * FROM %s WHERE name = '%s' LIMIT 1;", DATA_ARCHIVE_PREFIX, name.trim());
            log.info("执行SQL: {}", sql);

            SessionExecuteSqlResult res = iginxSession.executeSql(sql);
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);

            log.info("查询结果记录数: {}", records.size());
            if (!records.isEmpty()) {
                log.info("查询结果: {}", records.get(0));
            }

            if (records.isEmpty()) {
                return null;
            }

            DataArchiveEntity entity = new DataArchiveEntity();
            Map<String, Object> rs = records.get(0);
            DataArchiveEntity result = ConvertUtil.mapToEntity(entity, rs, DATA_ARCHIVE_PREFIX);
            log.info("映射后的实体: name={}, desc={}", result.getName(), result.getDesc());
            return result;
        } catch (Exception e) {
            log.error("根据名称查询数据档案失败", e);
            return null;
        }
    }

    /**
     * 分页查询数据档案
     */
    public List<DataArchiveEntity> queryArchives(String name, String type, String projectName, String owner, Integer pageNum, Integer pageSize) {
        try {
            StringBuilder sql = new StringBuilder("SELECT * FROM " + DATA_ARCHIVE_PREFIX + " WHERE 1=1");

            if (name != null && !name.trim().isEmpty()) {
                sql.append(" AND name LIKE '^.*").append(name.trim()).append(".*'");
            }
            if (type != null && !type.trim().isEmpty()) {
                sql.append(" AND type = '").append(type.trim()).append("'");
            }
            if (projectName != null && !projectName.trim().isEmpty()) {
                sql.append(" AND projectName = '").append(projectName.trim()).append("'");
            }
            if (owner != null && !owner.trim().isEmpty()) {
                sql.append(" AND owner = '").append(owner.trim()).append("'");
            }

            if (pageNum != null && pageSize != null) {
                sql.append(" LIMIT ").append(pageSize);
                sql.append(" OFFSET ").append((pageNum - 1) * pageSize);
            }
            sql.append(";");

            log.info("执行SQL: {}", sql);

            SessionExecuteSqlResult res = iginxSession.executeSql(sql.toString());
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);

            List<DataArchiveEntity> result = records.stream().map(record -> {
                DataArchiveEntity entity = new DataArchiveEntity();
                return ConvertUtil.mapToEntity(entity, record, DATA_ARCHIVE_PREFIX);
            }).collect(Collectors.toList());

            return result;
        } catch (Exception e) {
            log.error("查询数据档案列表失败", e);
            return new ArrayList<>();
        }
    }

    /**
     * 删除数据档案
     */
    public void deleteArchive(Long timestamp) throws Exception {
        if (timestamp == null) {
            throw new IllegalArgumentException("ID不能为空");
        }
        List<String> measurements = ConvertUtil.iginxFieldNamesConvert(DataArchiveEntity.class, DATA_ARCHIVE_PREFIX);
        iginxClient.getDeleteClient().deleteMeasurementsData(measurements, timestamp-1, timestamp+1);
        log.info("数据档案已删除。ID: {}", timestamp);
    }
}
