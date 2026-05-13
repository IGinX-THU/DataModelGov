package com.tsinghua.auth.util;

import lombok.extern.slf4j.Slf4j;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * 可见性SQL工具类
 * 生成基于BaseEntity可见性字段的SQL过滤条件
 */
@Slf4j
public class VisibilitySqlUtil {
    
    /**
     * 生成可见性过滤SQL条件
     * @param currentUser 当前用户名
     * @return SQL WHERE条件
     */
    public static String generateVisibilityFilter(String currentUser) {
        if (currentUser == null || currentUser.trim().isEmpty()) {
            return "1=0"; // 用户未登录，返回空条件
        }
        
        StringBuilder sql = new StringBuilder();

        sql.append("(");

        sql.append(" owner = '").append(currentUser.trim()).append("'");
        sql.append(" OR ");

        // 1. 公开数据：isPublic = true，所有用户可见
        sql.append("isPublic = true");
        sql.append(" OR ");
        
        // 2. 指定可见用户数据：isPublic = false 且 visibleUsers包含当前用户
        sql.append("(").append("isPublic = false");
//        sql.append(" AND ").append("visibleUsers IS NOT NULL");
        sql.append(" AND ").append("visibleUsers LIKE '^.*").append(currentUser).append(".*'");
        sql.append(")");
        
        sql.append(")");
        
        log.debug("生成可见性过滤SQL: {}", sql.toString());
        return sql.toString();
    }
    
    /**
     * 生成可见性过滤SQL条件（模型版）
     * @return SQL WHERE条件
     */
    public static String generateModelVisibilityFilter(List<String> tables, StringBuilder sql) {
        Set<String> modelNames = new HashSet<>();
        Set<String> modelVersions = new HashSet<>();
        tables.forEach(tablePrefix -> {
            if (tablePrefix == null || tablePrefix.trim().isEmpty() || tablePrefix.split("\\.").length < 3 || !tablePrefix.startsWith("models_system")) {
                return;
            }

            String[] tablePrefixes = tablePrefix.split("\\.");
            modelNames.add(tablePrefixes[1]);
            modelVersions.add(tablePrefixes[2]);
        });


        sql.append(" AND ");
        sql.append("(");

        String modelName = String.join(",", modelNames.stream()
                .map(v -> "'" + v.trim() + "'")
                .toArray(String[]::new));
        sql.append("modelName IN (").append(modelName).append(")");
        sql.append(" AND ");
        String modelVersion = String.join(",", modelVersions.stream()
                .map(v -> "'" + v.trim() + "'")
                .toArray(String[]::new));
        sql.append("modelVersion IN (").append(modelVersion).append(")");

        sql.append(")");
        
        return sql.toString();
    }
    
    /**
     * 将可见性条件添加到现有SQL中
     * @param originalSql 原始SQL
     * @param visibilityCondition 可见性条件
     * @return 添加了可见性过滤的SQL
     */
    public static String addVisibilityFilter(String originalSql, String visibilityCondition) {
        if (originalSql == null || originalSql.trim().isEmpty()) {
            return "";
        }
        
        String upperSql = originalSql.toUpperCase();
        int whereIndex = upperSql.indexOf(" WHERE ");
        
        if (whereIndex != -1) {
            // 已有WHERE子句，添加AND条件
            return originalSql + " AND " + visibilityCondition + " ;";
        } else {
            // 没有WHERE子句，添加WHERE条件
            return originalSql + " WHERE " + visibilityCondition + " ;";
        }
    }
    
    /**
     * 检查SQL是否需要添加可见性过滤
     * @param sql SQL语句
     * @return 是否需要添加可见性过滤
     */
    public static boolean needsVisibilityFilter(String sql) {
        if (sql == null || sql.trim().isEmpty()) {
            return false;
        }
        
        String upperSql = sql.toUpperCase();
        return upperSql.contains("SELECT") && 
               (upperSql.contains("FROM") || upperSql.contains("FROM "));
    }
}
