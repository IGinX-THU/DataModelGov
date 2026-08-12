package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.write.Point;
import com.tsinghua.auth.service.DataPermissionService;
import com.tsinghua.auth.util.AuthUtil;
import com.tsinghua.entity.SimulationArchiveEntity;
import com.tsinghua.util.ConvertUtil;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.*;
import java.util.stream.Collectors;

/**
 * 仿真档案服务
 * 用于管理仿真档案的CRUD操作
 */
@Slf4j
@Service
public class SimulationArchiveService {

    private static final String DATA_PREFIX = "relational_system.simulation_archives";

    @Autowired
    private DataPermissionService dataPermissionService;

    @Autowired
    private Session iginxSession;

    @Autowired
    private IginXClient iginxClient;

    /**
     * 保存仿真档案（新增或编辑）
     */
    public void saveArchive(SimulationArchiveEntity archive) throws Exception {
        List<Point> metaPoints = new ArrayList<>();
        SimulationArchiveEntity queryArchive = queryArchive(archive.getCreateTime());
        long timestamp;
        if (queryArchive != null && queryArchive.getCreateTime() != null) {
            timestamp = queryArchive.getCreateTime();
        } else {
            timestamp = archive.getCreateTime() == null ? System.currentTimeMillis() : archive.getCreateTime();
            archive.setCreateTime(timestamp);
        }
        archive.setUpdateTime(System.currentTimeMillis());
        // 默认将所有者设置为当前用户（如果未提供）
        if (archive.getOwner() == null || archive.getOwner().trim().isEmpty()) {
            archive.setOwner(AuthUtil.getCurrentUsername());
        }
        String metaBasePath = DATA_PREFIX;

        // 创建各个字段的数据点
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "name", archive.getName(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "description", archive.getDescription(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "graphJson", archive.getGraphJson(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "status", archive.getStatus(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "createTime", archive.getCreateTime(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "updateTime", archive.getUpdateTime(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "owner", archive.getOwner(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "projectName", archive.getProjectName(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "scheduleCron", archive.getScheduleCron(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "outputApiConfig", archive.getOutputApiConfig(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "lastExecutionTime", archive.getLastExecutionTime(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "executionCount", archive.getExecutionCount(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "isRunning", archive.getIsRunning(), timestamp));

        // 批量写入元数据
        iginxClient.getWriteClient().writePoints(metaPoints.stream().filter(Objects::nonNull).collect(Collectors.toList()));
        log.info("仿真档案已保存。名称: {}, 时间戳: {}", archive.getName(), timestamp);
    }

    /**
     * 分页查询仿真档案
     */
    public List<SimulationArchiveEntity> queryArchives(String name, String projectName, String owner, Boolean status, Integer pageNum, Integer pageSize) {
        try {
            StringBuilder sql = new StringBuilder("SELECT * FROM " + DATA_PREFIX + " WHERE 1=1");

            if (name != null && !name.trim().isEmpty()) {
                sql.append(" AND name LIKE '^.*").append(name.trim()).append(".*'");
            }
            
            // 处理项目名称过滤
            if (projectName != null && !projectName.trim().isEmpty()) {
                if (AuthUtil.isAdmin()) {
                    // 管理员可以模糊查询
                    sql.append(" AND projectName LIKE '^.*").append(projectName.trim()).append(".*'");
                } else {
                    // 非管理员必须精确匹配项目名称
                    sql.append(" AND projectName = '").append(projectName.trim()).append("'");
                }
            }
            
            // 处理所有者过滤
            String effectiveOwner = owner;
            if (effectiveOwner != null && !effectiveOwner.trim().isEmpty()) {
                sql.append(" AND owner = '").append(effectiveOwner.trim()).append("'");
            }
            if (status != null) {
                sql.append(" AND status = ").append(status);
            }

            sql.append(" ORDER BY updateTime DESC");
            if (pageNum != null && pageSize != null) {
                sql.append(" LIMIT ").append(pageSize);
                sql.append(" OFFSET ").append((pageNum - 1) * pageSize);
            }
            sql.append(";");

            log.info("执行SQL: {}", sql);

            SessionExecuteSqlResult res = iginxSession.executeSql(sql.toString());
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);

            List<SimulationArchiveEntity> result = records.stream().map(record -> {
                SimulationArchiveEntity entity = new SimulationArchiveEntity();
                record.forEach((k, v) -> {
                    String fieldName = k.replace(DATA_PREFIX + ".", "");
                    ConvertUtil.setEntityField(entity, DATA_PREFIX, fieldName, v);
                });
                return entity;
            }).collect(Collectors.toList());

            log.info("查询结果: records={}", result.size());
            return result;
        } catch (Exception e) {
            log.error("查询失败", e);
            return new ArrayList<>();
        }
    }

    /**
     * 查询仿真档案总数
     */
    public Object countArchives(String name, String projectName, String owner, Boolean status) {
        try {
            StringBuilder sql = new StringBuilder("SELECT COUNT(1) FROM " + DATA_PREFIX + " WHERE 1=1");
            
            if (name != null && !name.trim().isEmpty()) {
                sql.append(" AND name LIKE '%").append(name.trim()).append("%'");
            }
            
            // 处理项目名称过滤
            if (projectName != null && !projectName.trim().isEmpty()) {
                if (AuthUtil.isAdmin()) {
                    // 管理员可以模糊查询
                    sql.append(" AND projectName LIKE '%").append(projectName.trim()).append("%'");
                } else {
                    // 非管理员必须精确匹配项目名称
                    sql.append(" AND projectName = '").append(projectName.trim()).append("'");
                }
            }
            
            // 处理所有者过滤
            String effectiveOwner = owner;
            if (effectiveOwner != null && !effectiveOwner.trim().isEmpty()) {
                sql.append(" AND owner = '").append(effectiveOwner.trim()).append("'");
            }
            if (status != null) {
                sql.append(" AND status = ").append(status);
            }

            sql.append(";");
            
            log.info("执行COUNT SQL: {}", sql);
            
            SessionExecuteSqlResult res = iginxSession.executeSql(sql.toString());
            return res.getValues().get(0).get(0);
        } catch (Exception e) {
            log.error("查询失败", e);
            return 0;
        }
    }

    /**
     * 查询仿真档案详情
     */
    public SimulationArchiveEntity queryArchive(Long createTime) {
        try {
            String sql = "select * from %s where createTime = %s;";
            String metaBasePath = DATA_PREFIX;
            SessionExecuteSqlResult res = iginxSession.executeSql(String.format(sql, metaBasePath, createTime));
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);

            if (records.isEmpty()) {
                return null;
            }

            SimulationArchiveEntity entity = new SimulationArchiveEntity();
            Map<String, Object> rs = records.get(0);
            rs.forEach((k, v) -> {
                String fieldName = k.replace(DATA_PREFIX + ".", "");
                ConvertUtil.setEntityField(entity, DATA_PREFIX, fieldName, v);
            });
            return entity;
        } catch (Exception e) {
            log.error("查询仿真档案失败", e);
            return null;
        }
    }

    /**
     * 删除仿真档案
     */
    public void deleteArchive(Long createTime) {
        try {
            List<String> measurements = ConvertUtil.iginxFieldNamesConvert(SimulationArchiveEntity.class, DATA_PREFIX);
            iginxClient.getDeleteClient().deleteMeasurementsData(measurements, createTime - 1, createTime + 1);
            log.info("已删除仿真档案: createTime: {}", createTime);
        } catch (Exception e) {
            log.error("删除仿真档案失败", e);
            throw new RuntimeException("删除仿真档案失败: " + e.getMessage(), e);
        }
    }

    /**
     * 校验名称唯一性（仅用于新增）
     */
    public void validateNameUniqueness(String name) throws Exception {
        if (name == null || name.trim().isEmpty()) {
            throw new Exception("仿真档案名称不能为空");
        }

        StringBuilder sql = new StringBuilder("SELECT createTime FROM " + DATA_PREFIX + " WHERE name = '");
        sql.append(name.trim()).append("' LIMIT 1;");
        
        log.info("执行名称唯一性校验SQL: {}", sql);
        
        SessionExecuteSqlResult res = iginxSession.executeSql(sql.toString());
        List<Map<String, Object>> records = ConvertUtil.getRecords(res);
        
        if (!records.isEmpty()) {
            throw new Exception("仿真档案名称 '" + name + "' 已存在，请使用其他名称");
        }
    }

    /**
     * 复制仿真档案
     */
    public SimulationArchiveEntity copyArchive(Long createTime, String newName) throws Exception {
        SimulationArchiveEntity original = queryArchive(createTime);
        if (original == null) {
            throw new Exception("原仿真档案不存在");
        }

        SimulationArchiveEntity copy = new SimulationArchiveEntity();
        copy.setName(newName);
        copy.setDescription(original.getDescription() + " (副本)");
        copy.setGraphJson(original.getGraphJson());
        copy.setStatus(false); // 复制的档案默认禁用
        copy.setOwner(original.getOwner());
        copy.setProjectName(original.getProjectName());
        copy.setScheduleCron(original.getScheduleCron());
        copy.setOutputApiConfig(original.getOutputApiConfig());
        copy.setExecutionCount(0L);
        copy.setLastExecutionTime(null);
        copy.setIsRunning(false);

        saveArchive(copy);
        return copy;
    }
}
