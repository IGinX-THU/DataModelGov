package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.write.Point;
import com.tsinghua.dto.AssociationRulesQueryRequest;
import com.tsinghua.entity.AssociationRulesEntity;
import com.tsinghua.util.ConvertUtil;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.*;
import java.util.stream.Collectors;

@Slf4j
@Service
public class AssociationRulesService {

    private static final String DATA_PREFIX = "relational_system.association_rules";

    @Autowired
    private Session iginxSession;

    @Autowired
    private IginXClient iginxClient;

    /**
     * 保存关联规则（新增或编辑）
     * 完全参考ModelFileService.saveModelMetadata逻辑
     * 每个字段作为独立的时序序列存储，使用相同的时间戳对齐
     */
    public void saveRules(AssociationRulesEntity associationRulesEntity) throws Exception {
        List<Point> metaPoints = new ArrayList<>();
        AssociationRulesEntity queryRule = queryRule(associationRulesEntity.getCreateTime());
        long timestamp;
        if (queryRule != null && queryRule.getCreateTime() != null) {
            timestamp = queryRule.getCreateTime();
        } else {
            timestamp = System.currentTimeMillis();
            associationRulesEntity.setCreateTime(timestamp);
        }
        associationRulesEntity.setUpdateTime(System.currentTimeMillis());
        String metaBasePath = DATA_PREFIX;

        // 完全参考ModelFileService.saveModelMetadata的字段创建方式
        // 创建各个字段的数据点
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "name", associationRulesEntity.getName(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "description", associationRulesEntity.getDescription(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "tableName", associationRulesEntity.getTableName(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "modelName", associationRulesEntity.getModelName(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "modelVersion", associationRulesEntity.getModelVersion(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "status", associationRulesEntity.getStatus(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "createTime", associationRulesEntity.getCreateTime(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "updateTime", associationRulesEntity.getUpdateTime(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "inputsBind", associationRulesEntity.getInputsBind(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "outputsBind", associationRulesEntity.getOutputsBind(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "cmd", associationRulesEntity.getCmd(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "inputCsvName", associationRulesEntity.getInputCsvName(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "outputCsvName", associationRulesEntity.getOutputCsvName(), timestamp));

        // 批量写入元数据 - 完全参考ModelFileService的写入方式
        iginxClient.getWriteClient().writePoints(metaPoints.stream().filter(Objects::nonNull).collect(Collectors.toList()));
        log.info("关联规则已保存。名称: {}, 时间戳: {}", associationRulesEntity.getName(), timestamp);
    }

    /**
     * 分页查询关联规则
     */
    public List<AssociationRulesEntity> queryRules(AssociationRulesQueryRequest request) {
        try {
            // 构建基础SQL
            StringBuilder sql = new StringBuilder("SELECT * FROM relational_system.association_rules WHERE 1=1");
            
            // 添加筛选条件
            if (request.getName() != null && !request.getName().trim().isEmpty()) {
                sql.append(" AND name LIKE '^.*").append(request.getName().trim()).append(".*'");
            }
            if (request.getStatus() != null && !request.getStatus().trim().isEmpty()) {
                boolean statusValue = "active".equals(request.getStatus());
                sql.append(" AND status = ").append(statusValue);
            }
            
            // 添加排序和分页
            sql.append(" ORDER BY updateTime DESC");
            sql.append(" LIMIT ").append(request.getPageSize());
            sql.append(" OFFSET ").append((request.getPageNum() - 1) * request.getPageSize());
            sql.append(";");
            
            log.info("执行SQL: {}", sql);
            
            SessionExecuteSqlResult res = iginxSession.executeSql(sql.toString());
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);
            
            // 转换为AssociationRulesEntity列表 - 参考ModelFileService的转换方式
            List<AssociationRulesEntity> result = records.stream().map(record -> {
                AssociationRulesEntity entity = new AssociationRulesEntity();
                // 使用ConvertUtil的通用方法设置字段值 - 参考ModelFileService.queryMeta
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
     * 查询关联规则总数
     */
    public Object countRules(AssociationRulesQueryRequest request) {
        try {
            // 构建COUNT查询SQL
            StringBuilder sql = new StringBuilder("SELECT COUNT(1) FROM relational_system.association_rules WHERE 1=1");
            
            // 添加筛选条件
            if (request.getName() != null && !request.getName().trim().isEmpty()) {
                sql.append(" AND name LIKE '%").append(request.getName().trim()).append("%'");
            }
            if (request.getStatus() != null && !request.getStatus().trim().isEmpty()) {
                boolean statusValue = "active".equals(request.getStatus());
                sql.append(" AND status = ").append(statusValue);
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
     * 查询关联规则详情
     * 参考queryMeta逻辑，只用createTime作为唯一标识
     */
    public AssociationRulesEntity queryRule(Long createTime) {
        try {
            String sql = "select * from %s where createTime = %s;";
            String metaBasePath = DATA_PREFIX;
            SessionExecuteSqlResult res = iginxSession.executeSql(String.format(sql, metaBasePath, createTime));
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);

            if (records.isEmpty()) {
                return null;
            }

            AssociationRulesEntity entity = new AssociationRulesEntity();
            Map<String, Object> rs = records.get(0);
            // 使用ConvertUtil的通用方法设置字段值
            rs.forEach((k, v) -> {
                String fieldName = k.replace(DATA_PREFIX + ".", "");
                ConvertUtil.setEntityField(entity, DATA_PREFIX, fieldName, v);
            });
            return entity;
        } catch (Exception e) {
            log.error("查询关联规则失败", e);
            return null;
        }
    }

    /**
     * 删除关联规则
     * 参考deleteModel逻辑，只用createTime作为唯一标识
     */
    public void deleteRule(Long createTime) {
        try {
            List<String> measurements = ConvertUtil.iginxFieldNamesConvert(AssociationRulesEntity.class, DATA_PREFIX);
            // 删除指定时间戳的数据
            iginxClient.getDeleteClient().deleteMeasurementsData(measurements, createTime - 1, createTime + 1);
            log.info("已删除关联规则: createTime: {}", createTime);
        } catch (Exception e) {
            log.error("删除关联规则失败", e);
            throw new RuntimeException("删除关联规则失败: " + e.getMessage(), e);
        }
    }

}
