package com.tsinghua.auth.util;

import lombok.extern.slf4j.Slf4j;

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
     * 生成可见性过滤SQL条件（简化版）
     * @param currentUser 当前用户名
     * @param tablePrefix 表前缀
     * @return SQL WHERE条件
     */
    public static String generateSimpleVisibilityFilter(String currentUser, String tablePrefix) {
        if (currentUser == null || currentUser.trim().isEmpty()) {
            return "1=0";
        }
        
        StringBuilder sql = new StringBuilder();
        sql.append("(");
        
        // 公开数据或创建者数据
        sql.append(tablePrefix).append(".isPublic = true");
        sql.append(" OR ");
        sql.append(tablePrefix).append(".creator = '").append(currentUser).append("'");
        
        // 指定可见用户数据
        sql.append(" OR (");
        sql.append(tablePrefix).append(".visibleUsers IS NOT NULL");
        sql.append(" AND ").append(tablePrefix).append(".visibleUsers LIKE '%").append(currentUser).append("%'");
        sql.append(")");
        
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
