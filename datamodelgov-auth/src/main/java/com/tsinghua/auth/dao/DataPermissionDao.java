package com.tsinghua.auth.dao;

import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.WriteClient;
import com.tsinghua.auth.entity.DataPermissionEntity;
import com.tsinghua.auth.entity.UserEntity;
import com.tsinghua.auth.util.AuthUtil;
import com.tsinghua.auth.util.VisibilitySqlUtil;
import com.tsinghua.util.ConvertUtil;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Repository;

import java.util.*;
import java.util.stream.Collectors;

/**
 * 数据权限服务
 * 基于时间戳主键的Entity表权限控制
 */
@Slf4j
@Repository
public class DataPermissionDao {

    private static final String PERMISSIONS_TABLE = "relational_system.data_permissions";

    @Autowired
    private Session iginxSession;

    @Autowired
    private IginXClient iginxClient;

    /**
     * 删除
     */
    public void deleteById(long timestamp) {
        try {

            // 获取所有字段名
            List<String> measurements = ConvertUtil.iginxFieldNamesConvert(DataPermissionEntity.class, PERMISSIONS_TABLE);

            // 删除指定时间戳的数据
            iginxClient.getDeleteClient().deleteMeasurementsData(measurements, timestamp - 1, timestamp + 1);

            log.info("权限已删除, 时间戳: {}", timestamp);
        } catch (Exception e) {
            log.error("删除用户失败: {}", e.getMessage(), e);
            throw new RuntimeException("删除用户失败: " + e.getMessage(), e);
        }
    }

    /**
     * 查询权限
     */
    public List<DataPermissionEntity> findByTablePrefix(String tablePrefix) {
        List<DataPermissionEntity> list = new ArrayList<>();
        try {
            // 构建查询SQL - 完全参考AssociationRulesService
            String querySql = "SELECT * FROM " + PERMISSIONS_TABLE + " WHERE tablePrefix = '" + tablePrefix + "';";

            log.info("执行权限查询SQL: {}", querySql);

            // 使用Session.executeSql - 参考AssociationRulesService
            SessionExecuteSqlResult result = iginxSession.executeSql(querySql);
            List<Map<String, Object>> records = ConvertUtil.getRecords(result);

            // 转换为UserEntity - 参考ModelFileService的转换方式
            records.forEach(record ->
                    list.add(ConvertUtil.mapToEntity(new DataPermissionEntity(), record, PERMISSIONS_TABLE)));
        } catch (Exception e) {
            log.error("查询用户失败: {}", e.getMessage(), e);
        }
        return list;
    }

    /**
     * 保存数据权限
     */
    public void saveDataPermission(DataPermissionEntity permission) {
        try {
            long timestamp = permission.getCreateTime() != null ? permission.getCreateTime() : System.currentTimeMillis();

            // 创建数据点列表
            List<cn.edu.tsinghua.iginx.session_v2.write.Point> permissionPoints = new ArrayList<>();
            permissionPoints.add(ConvertUtil.createFieldPoint(PERMISSIONS_TABLE, "timestamp", timestamp, timestamp));
            permissionPoints.add(ConvertUtil.createFieldPoint(PERMISSIONS_TABLE, "owner", permission.getOwner(), timestamp));
            permissionPoints.add(ConvertUtil.createFieldPoint(PERMISSIONS_TABLE, "tablePrefix", permission.getTablePrefix(), timestamp));
            permissionPoints.add(ConvertUtil.createFieldPoint(PERMISSIONS_TABLE, "timestampSet", permission.getTimestampSet(), timestamp));
            permissionPoints.add(ConvertUtil.createFieldPoint(PERMISSIONS_TABLE, "isPublic", permission.isPublic(), timestamp));
            permissionPoints.add(ConvertUtil.createFieldPoint(PERMISSIONS_TABLE, "visibleUsers", permission.getVisibleUsers(), timestamp));

            // 这里需要注入IginXClient，并使用writeClient写入
            WriteClient writeClient = iginxClient.getWriteClient();
            writeClient.writePoints(permissionPoints);

            log.info("保存数据权限: 用户={}, 表前缀={}, 时间戳集合={}", 
                    permission.getOwner(), permission.getTablePrefix(), permission.getTimestampSet());
            
        } catch (Exception e) {
            log.error("保存数据权限失败: {}", e.getMessage(), e);
            throw new RuntimeException("保存数据权限失败: " + e.getMessage(), e);
        }
    }
    
    /**
     * 获取用户可访问的表前缀列表
     */
    public List<String> getUserAccessibleTables(String username) {
        try {
            String baseSql = "SELECT tablePrefix FROM " + PERMISSIONS_TABLE;

            // 添加可见性过滤
            String visibilityFilter = VisibilitySqlUtil.generateVisibilityFilter(username);
            String finalSql = VisibilitySqlUtil.addVisibilityFilter(baseSql, visibilityFilter);

            log.info("执行用户可访问表查询SQL: {}", finalSql);
            
            SessionExecuteSqlResult result = iginxSession.executeSql(finalSql);
            List<Map<String, Object>> records = ConvertUtil.getRecords(result);
            
            Set<String> tablePrefixes = new HashSet<>();
            for (Map<String, Object> record : records) {
                Object tablePrefix = record.get(PERMISSIONS_TABLE + ".tablePrefix");
                if (tablePrefix != null) {
                    tablePrefixes.add(tablePrefix.toString());
                }
            }
            
            return new ArrayList<>(tablePrefixes);
            
        } catch (Exception e) {
            log.error("查询用户可访问表失败: {}", e.getMessage(), e);
            return new ArrayList<>();
        }
    }
    
    /**
     * 获取当前用户可访问的表前缀列表
     */
    public List<String> getCurrentUserAccessibleTables() {
        String currentUser = AuthUtil.getCurrentUsername("unknown");
        if (currentUser == null || "unknown".equals(currentUser)) {
            return new ArrayList<>();
        }
        return getUserAccessibleTables(currentUser);
    }
    
    /**
     * 获取用户对特定表的可访问时间戳集合
     */
    public Set<Long> getUserAccessibleTimestamps(String username, String tablePrefix, String permissionType) {
        try {
            String querySql = "SELECT timestampSet FROM " + PERMISSIONS_TABLE + 
                            " WHERE username = '" + username + "'" +
                            " AND tablePrefix = '" + tablePrefix + "'" +
                            " AND permissionType = '" + permissionType + "';";
            
            log.info("查询用户可访问时间戳: {}", querySql);
            
            SessionExecuteSqlResult result = iginxSession.executeSql(querySql);
            List<Map<String, Object>> records = ConvertUtil.getRecords(result);
            
            Set<Long> timestamps = new HashSet<>();
            for (Map<String, Object> record : records) {
                Object timestampSet = record.get(PERMISSIONS_TABLE + ".timestampSet");
                if (timestampSet != null && !timestampSet.toString().isEmpty()) {
                    // 解析逗号分隔的时间戳字符串
                    String[] timestampArray = timestampSet.toString().split(",");
                    for (String timestampStr : timestampArray) {
                        try {
                            timestamps.add(Long.parseLong(timestampStr.trim()));
                        } catch (NumberFormatException e) {
                            log.warn("无效的时间戳格式: {}", timestampStr);
                        }
                    }
                }
            }
            
            return timestamps;
            
        } catch (Exception e) {
            log.error("查询用户可访问时间戳失败: {}", e.getMessage(), e);
            return new HashSet<>();
        }
    }
    
    /**
     * 获取当前用户对特定表的可访问时间戳集合
     */
    public Set<Long> getCurrentUserAccessibleTimestamps(String tablePrefix, String permissionType) {
        String currentUser = AuthUtil.getCurrentUsername("unknown");
        if (currentUser == null || "unknown".equals(currentUser)) {
            return new HashSet<>();
        }
        return getUserAccessibleTimestamps(currentUser, tablePrefix, permissionType);
    }
    
    /**
     * 检查用户是否有权限访问指定时间戳的数据
     */
    public boolean hasTimestampPermission(String username, String tablePrefix, String permissionType, Long timestamp) {
        Set<Long> accessibleTimestamps = getUserAccessibleTimestamps(username, tablePrefix, permissionType);
        return accessibleTimestamps.contains(timestamp);
    }
    
    /**
     * 检查当前用户是否有权限访问指定时间戳的数据
     */
    public boolean checkCurrentUserTimestampPermission(String tablePrefix, String permissionType, Long timestamp) {
        String currentUser = AuthUtil.getCurrentUsername("unknown");
        if (currentUser == null || "unknown".equals(currentUser)) {
            return false;
        }
        return hasTimestampPermission(currentUser, tablePrefix, permissionType, timestamp);
    }
    
    /**
     * 批量保存时间戳权限
     */
    public void saveTimestampPermissions(String username, String tablePrefix, Boolean isPublic,
                                   Set<Long> timestamps, String visibleUsers) {
        try {
            String timestampSetStr = timestamps.stream()
                .map(String::valueOf)
                .collect(Collectors.joining(","));
            
            DataPermissionEntity permission = DataPermissionEntity.builder()
                .createTime(System.currentTimeMillis())
                .owner(username)
                .tablePrefix(tablePrefix)
                .timestampSet(timestampSetStr)
                .isPublic(isPublic)
                .visibleUsers(visibleUsers)
                .build();
            
            saveDataPermission(permission);
            
            log.info("批量保存时间戳权限成功: 用户={}, 表前缀={}, 时间戳数量={}", 
                    username, tablePrefix, timestamps.size());
            
        } catch (Exception e) {
            log.error("批量保存时间戳权限失败: {}", e.getMessage(), e);
            throw new RuntimeException("批量保存时间戳权限失败", e);
        }
    }
}
