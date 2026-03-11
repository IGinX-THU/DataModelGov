package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.write.Point;
import com.tsinghua.dto.ParsingRulesQueryRequest;
import com.tsinghua.entity.ParsingRulesEntity;
import com.tsinghua.util.ConvertUtil;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import javax.annotation.PostConstruct;
import java.util.*;
import java.util.stream.Collectors;

@Slf4j
@Service
public class ParsingRulesService {

    private static final String DATA_PREFIX = "relational_system.parsing_rules";

    @Autowired
    private Session iginxSession;

    @Autowired
    private IginXClient iginxClient;

    @PostConstruct
    private void init() {
        try {
            ParsingRulesEntity parsingRulesEntity = new ParsingRulesEntity();
            parsingRulesEntity.setName("默认规则");
            parsingRulesEntity.setRegexPattern("^#\\s*@(Input|Output)\\s*:?\\s*(\\w+)\\s*[\\(\\[]?\\s*(\\w+)\\s*[\\)\\]]?\\s*-?\\s*(.*)$");
            saveRules(parsingRulesEntity);
        } catch (Exception e) {
            log.error(e.getMessage());
        }

    }

    /**
     * 保存解析规则（新增或编辑）
     * 完全参考ModelFileService.saveModelMetadata逻辑
     * 每个字段作为独立的时序序列存储，使用相同的时间戳对齐
     */
    public void saveRules(ParsingRulesEntity parsingRulesEntity) throws Exception {
        List<Point> metaPoints = new ArrayList<>();
        ParsingRulesEntity queryRule = queryRule(parsingRulesEntity.getCreateTime());
        long timestamp;
        
        if (queryRule != null && queryRule.getCreateTime() != null) {
            // 编辑情况：不进行名称唯一校验，允许保持相同名称
            timestamp = queryRule.getCreateTime();
        } else {
            // 新增情况：进行名称唯一校验
            validateNameUniqueness(parsingRulesEntity.getName());
            timestamp = System.currentTimeMillis();
            parsingRulesEntity.setCreateTime(timestamp);
        }
        parsingRulesEntity.setUpdateTime(System.currentTimeMillis());
        String metaBasePath = DATA_PREFIX;

        // 完全参考ModelFileService.saveModelMetadata的字段创建方式
        // 创建各个字段的数据点
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "name", parsingRulesEntity.getName(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "regexPattern", parsingRulesEntity.getRegexPattern(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "createTime", parsingRulesEntity.getCreateTime(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "updateTime", parsingRulesEntity.getUpdateTime(), timestamp));

        // 批量写入元数据 - 完全参考ModelFileService的写入方式
        iginxClient.getWriteClient().writePoints(metaPoints.stream().filter(Objects::nonNull).collect(Collectors.toList()));
        log.info("解析规则已保存。名称: {}, 时间戳: {}", parsingRulesEntity.getName(), timestamp);
    }

    /**
     * 分页查询解析规则
     */
    public List<ParsingRulesEntity> queryRules(ParsingRulesQueryRequest request) {
        try {
            // 构建基础SQL
            StringBuilder sql = new StringBuilder("SELECT * FROM relational_system.parsing_rules WHERE 1=1");
            
            // 添加筛选条件
            if (request.getName() != null && !request.getName().trim().isEmpty()) {
                sql.append(" AND name LIKE '^.*").append(request.getName().trim()).append(".*'");
            }
            
            // 添加排序和分页
            sql.append(" ORDER BY updateTime DESC");
            sql.append(" LIMIT ").append(request.getPageSize());
            sql.append(" OFFSET ").append((request.getPageNum() - 1) * request.getPageSize());
            sql.append(";");
            
            log.info("执行SQL: {}", sql);
            
            SessionExecuteSqlResult res = iginxSession.executeSql(sql.toString());
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);
            
            // 转换为ParsingRulesEntity列表 - 参考ModelFileService的转换方式
            List<ParsingRulesEntity> result = records.stream().map(record -> {
                ParsingRulesEntity entity = new ParsingRulesEntity();
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
     * 查询解析规则总数
     */
    public Object countRules(ParsingRulesQueryRequest request) {
        try {
            // 构建COUNT查询SQL
            StringBuilder sql = new StringBuilder("SELECT COUNT(1) FROM relational_system.parsing_rules WHERE 1=1");
            
            // 添加筛选条件
            if (request.getName() != null && !request.getName().trim().isEmpty()) {
                sql.append(" AND name LIKE '%").append(request.getName().trim()).append("%'");
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
     * 查询解析规则详情
     * 参考queryMeta逻辑，只用createTime作为唯一标识
     */
    public ParsingRulesEntity queryRule(Long createTime) {
        try {
            String sql = "select * from %s where createTime = %s;";
            String metaBasePath = DATA_PREFIX;
            SessionExecuteSqlResult res = iginxSession.executeSql(String.format(sql, metaBasePath, createTime));
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);

            if (records.isEmpty()) {
                return null;
            }

            ParsingRulesEntity entity = new ParsingRulesEntity();
            Map<String, Object> rs = records.get(0);
            // 使用ConvertUtil的通用方法设置字段值
            rs.forEach((k, v) -> {
                String fieldName = k.replace(DATA_PREFIX + ".", "");
                ConvertUtil.setEntityField(entity, DATA_PREFIX, fieldName, v);
            });
            return entity;
        } catch (Exception e) {
            log.error("查询解析规则失败", e);
            return null;
        }
    }

    /**
     * 删除解析规则
     * 参考deleteModel逻辑，只用createTime作为唯一标识
     */
    public void deleteRule(Long createTime) {
        try {
            List<String> measurements = ConvertUtil.iginxFieldNamesConvert(ParsingRulesEntity.class, DATA_PREFIX);
            // 删除指定时间戳的数据
            iginxClient.getDeleteClient().deleteMeasurementsData(measurements, createTime - 1, createTime + 1);
            log.info("已删除解析规则: createTime: {}", createTime);
        } catch (Exception e) {
            log.error("删除解析规则失败", e);
            throw new RuntimeException("删除解析规则失败: " + e.getMessage(), e);
        }
    }

    /**
     * 校验名称唯一性（仅用于新增）
     * @param name 规则名称
     * @throws Exception 如果名称已存在则抛出异常
     */
    private void validateNameUniqueness(String name) throws Exception {
        if (name == null || name.trim().isEmpty()) {
            throw new Exception("规则名称不能为空");
        }

        // 查询是否存在同名规则
        StringBuilder sql = new StringBuilder("SELECT createTime FROM relational_system.parsing_rules WHERE name = '");
        sql.append(name.trim()).append("' LIMIT 1;");
        
        log.info("执行名称唯一性校验SQL: {}", sql);
        
        SessionExecuteSqlResult res = iginxSession.executeSql(sql.toString());
        List<Map<String, Object>> records = ConvertUtil.getRecords(res);
        
        if (!records.isEmpty()) {
            throw new Exception("规则名称 '" + name + "' 已存在，请使用其他名称");
        }
    }

}
