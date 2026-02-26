package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult;
import com.tsinghua.dto.RelationalQueryRequest;
import com.tsinghua.dto.TableDto;
import lombok.extern.slf4j.Slf4j;
import org.checkerframework.checker.nullness.compatqual.NonNullDecl;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Slf4j
@Service
public class RelationalDataService {

    @Autowired
    private Session iginxSession;

    public TableDto queryData(RelationalQueryRequest request) {
        try {
            // 构建SQL查询语句
            String sql = buildQuerySql(request);
            
            // 修复分页计算：OFFSET应该是(pageNum - 1) * pageSize
            int offset = (request.getPageNum() - 1) * request.getPageSize();
            String finalSql = sql + String.format(" LIMIT %s OFFSET %s;", request.getPageSize(), offset);
            
            log.info("执行SQL: {}, tableName: {}, pageSize: {}, offset: {}", 
                    finalSql, request.getTableName(), request.getPageSize(), offset);
            
            iginxSession.openSession();
            SessionExecuteSqlResult res = iginxSession.executeSql(finalSql);
            List<Map<String, Object>> records = getRecords(res);
            iginxSession.closeSession();
            
            TableDto result = new TableDto(res.getPaths(), records);
            log.info("查询结果: paths={}, records={}", res.getPaths(), records.size());
            
            return result;
        } catch (Exception e) {
            log.error("查询失败", e);
            return null;
        }
    }

    /**
     * 构建WHERE子句，支持AND和OR逻辑以及括号分组
     */
    private String buildWhereClause(List<RelationalQueryRequest.FilterCondition> filters) {
        if (filters == null || filters.isEmpty()) {
            return "";
        }
        
        StringBuilder whereClause = new StringBuilder();
        
        for (int i = 0; i < filters.size(); i++) {
            RelationalQueryRequest.FilterCondition filter = filters.get(i);
            
            // 验证筛选条件
            if (!StringUtils.hasText(filter.getField()) || 
                !StringUtils.hasText(filter.getOperator()) || 
                !StringUtils.hasText(filter.getValue())) {
                continue;
            }
            
            // 添加开始括号
            if (Boolean.TRUE.equals(filter.getStartGroup())) {
                whereClause.append("(");
            }
            
            // 添加逻辑操作符（除了第一个条件）
            if (i > 0 && StringUtils.hasText(filter.getLogicOperator())) {
                whereClause.append(" ").append(filter.getLogicOperator()).append(" ");
            }
            
            // 添加筛选条件
            String condition = buildCondition(filter);
            whereClause.append(condition);
            
            // 添加结束括号
            if (Boolean.TRUE.equals(filter.getEndGroup())) {
                whereClause.append(")");
            }
        }
        
        return whereClause.toString();
    }

    /**
     * 构建查询SQL语句
     */
    private String buildQuerySql(RelationalQueryRequest request) {
        StringBuilder sql = new StringBuilder("SELECT * FROM ").append(request.getTableName());
        
        // 添加WHERE条件
        if (request.getFilters() != null && !request.getFilters().isEmpty()) {
            String whereClause = buildWhereClause(request.getFilters());
            if (StringUtils.hasText(whereClause)) {
                sql.append(" WHERE ").append(whereClause);
            }
        }
        
        // 添加ORDER BY排序条件
        if (StringUtils.hasText(request.getSortField())) {
            sql.append(" ORDER BY ").append(request.getSortField());
            if (StringUtils.hasText(request.getSortDirection())) {
                sql.append(" ").append(request.getSortDirection());
            }
        }
        
        return sql.toString();
    }

    /**
     * 构建单个筛选条件
     */
    private String buildCondition(RelationalQueryRequest.FilterCondition filter) {
        String field = filter.getField();
        String operator = filter.getOperator();
        String value = filter.getValue();
        
        switch (operator.toUpperCase()) {
            case "=":
            case "==":
                return field + " = '" + value + "'";
            case "!=":
                return field + " != '" + value + "'";
            case ">":
                return field + " > '" + value + "'";
            case "<":
                return field + " < '" + value + "'";
            case ">=":
                return field + " >= '" + value + "'";
            case "<=":
                return field + " <= '" + value + "'";
            case "IN":
                // 处理IN条件，支持逗号分隔的值
                String[] inValues = value.split(",");
                String inClause = String.join(",", java.util.Arrays.stream(inValues)
                    .map(v -> "'" + v.trim() + "'")
                    .toArray(String[]::new));
                return field + " IN (" + inClause + ")";
            case "NOT IN":
                // 处理NOT IN条件
                String[] notInValues = value.split(",");
                String notInClause = String.join(",", java.util.Arrays.stream(notInValues)
                    .map(v -> "'" + v.trim() + "'")
                    .toArray(String[]::new));
                return field + " NOT IN (" + notInClause + ")";
            case "LIKE":
                // 处理LIKE条件，支持正则表达式
                return field + " LIKE '" + value + "'";
            case "包含":
                // 转换为正则表达式的包含
                return field + " LIKE '^.*" + value + ".*'";
            default:
                // 默认使用等于
                return field + " = '" + value + "'";
        }
    }

    @NonNullDecl
    private static List<Map<String, Object>> getRecords(SessionExecuteSqlResult res) {
        List<String> header = res.getPaths();
        List<Map<String, Object>> records = new ArrayList<>();
        List<List<Object>>  rows = res.getValues();
        rows.forEach(row -> {
            Map<String, Object> rs = new LinkedHashMap<>();
            for (int i=0; i<=header.size() -1; i++){
                Object value = row.get(i);
                if (value instanceof byte[]) {
                    rs.put(header.get(i), new String((byte[]) value, StandardCharsets.UTF_8));
                } else {
                    rs.put(header.get(i), row.get(i));
                }
            }
            records.add(rs);
        });
        return records;
    }

    public Object countData(RelationalQueryRequest request) {
        try {
            // 构建COUNT查询SQL
            String sql = buildCountSql(request);
            
            log.info("执行COUNT SQL: {}", sql);
            
            iginxSession.openSession();
            SessionExecuteSqlResult res = iginxSession.executeSql(sql);
            iginxSession.closeSession();
            
            return res.getValues().get(0).get(0);
        } catch (Exception e) {
            log.error("查询失败", e);
            return 0;
        }
    }

    /**
     * 构建COUNT查询SQL语句
     */
    private String buildCountSql(RelationalQueryRequest request) {
        StringBuilder sql = new StringBuilder("SELECT COUNT(1) FROM ").append(request.getTableName());
        
        // 添加WHERE条件（与查询相同的逻辑）
        if (request.getFilters() != null && !request.getFilters().isEmpty()) {
            String whereClause = buildWhereClause(request.getFilters());
            if (StringUtils.hasText(whereClause)) {
                sql.append(" WHERE ").append(whereClause);
            }
        }
        
        // COUNT查询不需要排序，直接返回
        return sql.append(";").toString();
    }
}
