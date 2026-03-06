package com.tsinghua.auth.dao;

import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult;
import cn.edu.tsinghua.iginx.session_v2.DeleteClient;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.write.Point;
import com.tsinghua.auth.entity.RoleEntity;
import com.tsinghua.auth.enums.Permission;
import com.tsinghua.util.ConvertUtil;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import javax.annotation.PostConstruct;
import org.springframework.stereotype.Repository;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 角色数据访问对象 - 完全参考ModelFileService和AssociationRulesService实现方式
 */
@Slf4j
@Repository
public class RoleDao {
    
    private static final String ROLES_TABLE = "relational_system.roles";
    
    @Autowired
    private Session iginxSession;
    
    @Autowired
    private IginXClient iginxClient;
    
    private DeleteClient deleteClient;
    
    @PostConstruct
    public void init() {
        try {
            deleteClient = iginxClient.getDeleteClient();
            log.info("角色DAO IGinX 客户端初始化成功");
        } catch (Exception e) {
            log.error("初始化角色DAO IGinX 客户端失败", e);
            throw new RuntimeException("角色DAO IGinX 服务连接失败", e);
        }
    }
    
    /**
     * 查询角色 - 参考ModelFileService.queryMeta
     */
    public RoleEntity queryRole(String role) {
        try {
            String sql = "SELECT * FROM %s WHERE role = '%s';";
            String querySql = String.format(sql, ROLES_TABLE, role);
            
            log.info("执行角色查询SQL: {}", querySql);
            
            // 使用Session.executeSql - 参考ModelFileService和AssociationRulesService
            SessionExecuteSqlResult result = iginxSession.executeSql(querySql);
            List<Map<String, Object>> records = ConvertUtil.getRecords(result);
            
            if (records.isEmpty()) {
                return null;
            }
            
            // 转换为RoleEntity - 参考ModelFileService的转换方式
            Map<String, Object> record = records.get(0);
            return mapToRoleEntity(record);
        } catch (Exception e) {
            log.error("查询角色失败: {}", e.getMessage(), e);
            return null;
        }
    }
    
    /**
     * 查询所有角色 - 参考ModelFileService.queryMetaList
     */
    public List<RoleEntity> queryAllRoles() {
        try {
            String sql = "SELECT * FROM %s ORDER BY timestamp;";
            String querySql = String.format(sql, ROLES_TABLE);
            
            log.info("执行查询所有角色SQL: {}", querySql);
            
            SessionExecuteSqlResult result = iginxSession.executeSql(querySql);
            List<Map<String, Object>> records = ConvertUtil.getRecords(result);
            
            List<RoleEntity> roles = new ArrayList<>();
            for (Map<String, Object> record : records) {
                roles.add(mapToRoleEntity(record));
            }
            
            return roles;
        } catch (Exception e) {
            log.error("查询所有角色失败: {}", e.getMessage(), e);
            return new ArrayList<>();
        }
    }
    
    /**
     * 保存角色 - 参考ModelFileService.saveModelMetadata
     */
    public void saveRole(RoleEntity role) {
        try {
            // 先查询角色是否存在
            RoleEntity existingRole = queryRole(role.getRole());
            
            long timestamp;
            if (existingRole != null && existingRole.getTimestamp() != null) {
                timestamp = existingRole.getTimestamp();
                log.info("更新现有角色: {}", role.getRole());
            } else {
                timestamp = role.getTimestamp() != null ? role.getTimestamp() : System.currentTimeMillis();
                log.info("创建新角色: {}", role.getRole());
            }
            
            // 创建数据点列表 - 完全参考ModelFileService.saveModelMetadata
            List<Point> rolePoints = new ArrayList<>();
            rolePoints.add(ConvertUtil.createFieldPoint(ROLES_TABLE, "role", role.getRole(), timestamp));
            rolePoints.add(ConvertUtil.createFieldPoint(ROLES_TABLE, "permissions", permissionsToJson(role.getPermissions()), timestamp));
            rolePoints.add(ConvertUtil.createFieldPoint(ROLES_TABLE, "timestamp", timestamp, timestamp));
            
            // 使用writeClient写入 - 参考ModelFileService
            cn.edu.tsinghua.iginx.session_v2.WriteClient writeClient = iginxClient.getWriteClient();
            writeClient.writePoints(rolePoints);
            
            log.info("角色已保存: {}, 时间戳: {}", role.getRole(), timestamp);
        } catch (Exception e) {
            log.error("保存角色失败: {}", e.getMessage(), e);
            throw new RuntimeException("保存角色失败: " + e.getMessage(), e);
        }
    }
    
    /**
     * 删除角色 - 参考ModelFileService.deleteModel
     */
    public void deleteRole(String role) {
        try {
            // 先查询角色获取时间戳
            RoleEntity roleEntity = queryRole(role);
            if (roleEntity == null || roleEntity.getTimestamp() == null) {
                log.warn("角色不存在，无法删除: {}", role);
                return;
            }
            
            // 获取所有字段名 - 参考ModelFileService.deleteModel
            List<String> measurements = ConvertUtil.iginxFieldNamesConvert(RoleEntity.class, ROLES_TABLE);
            
            // 删除指定时间戳的数据 - 参考ModelFileService
            long timestamp = roleEntity.getTimestamp();
            deleteClient.deleteMeasurementsData(measurements, timestamp - 1, timestamp + 1);
            
            log.info("角色已删除: {}, 时间戳: {}", role, timestamp);
        } catch (Exception e) {
            log.error("删除角色失败: {}", e.getMessage(), e);
            throw new RuntimeException("删除角色失败: " + e.getMessage(), e);
        }
    }
    
    /**
     * 检查角色是否存在
     */
    public boolean existsRole(String role) {
        return queryRole(role) != null;
    }
    
    /**
     * 将权限集合转换为JSON字符串
     */
    private String permissionsToJson(Set<Permission> permissions) {
        if (permissions == null || permissions.isEmpty()) {
            return "[]";
        }
        
        StringBuilder json = new StringBuilder("[");
        boolean first = true;
        for (Permission permission : permissions) {
            if (!first) {
                json.append(",");
            }
            json.append("\"").append(permission.name()).append("\"");
            first = false;
        }
        json.append("]");
        return json.toString();
    }
    
    /**
     * 将JSON字符串转换为权限集合
     */
    private Set<Permission> jsonToPermissions(String json) {
        if (json == null || json.trim().isEmpty() || "[]".equals(json.trim())) {
            return java.util.Collections.emptySet();
        }
        
        Set<Permission> permissions = java.util.EnumSet.noneOf(Permission.class);
        String cleanJson = json.trim().substring(1, json.trim().length() - 1); // 移除 [ ]
        String[] permissionNames = cleanJson.split(",");
        
        for (String permissionName : permissionNames) {
            String cleanName = permissionName.trim().replace("\"", "");
            try {
                Permission permission = Permission.valueOf(cleanName);
                permissions.add(permission);
            } catch (IllegalArgumentException e) {
                log.warn("未知权限: {}", cleanName);
            }
        }
        
        return permissions;
    }
    
    /**
     * 将记录映射为角色实体 - 参考ModelFileService的转换方式
     */
    private RoleEntity mapToRoleEntity(Map<String, Object> record) {
        RoleEntity role = new RoleEntity();
        
        // 使用ConvertUtil的通用方法设置字段值 - 参考ModelFileService.queryMeta
        record.forEach((k, v) -> {
            String fieldName = k.replace(ROLES_TABLE + ".", "");
            
            // 特殊处理permissions字段
            if ("permissions".equals(fieldName)) {
                String permissionsJson = getStringValue(v);
                role.setPermissions(jsonToPermissions(permissionsJson));
            } else {
                ConvertUtil.setEntityField(role, ROLES_TABLE, fieldName, v);
            }
        });
        
        return role;
    }
    
    /**
     * 获取字符串值
     */
    private String getStringValue(Object value) {
        if (value instanceof byte[]) {
            return new String((byte[]) value, java.nio.charset.StandardCharsets.UTF_8);
        }
        return value != null ? value.toString() : null;
    }
}
