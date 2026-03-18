package com.tsinghua.auth.dao;

import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult;
import cn.edu.tsinghua.iginx.session_v2.DeleteClient;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.write.Point;
import com.tsinghua.auth.entity.RoleEntity;
import com.tsinghua.auth.entity.UserEntity;
import com.tsinghua.util.ConvertUtil;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import javax.annotation.PostConstruct;
import org.springframework.stereotype.Repository;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * 用户数据访问对象 - 完全参考ModelFileService和AssociationRulesService实现方式
 */
@Slf4j
@Repository
public class UserDao {
    
    private static final String USERS_TABLE = "relational_system.users";
    
    @Autowired
    private Session iginxSession;
    
    @Autowired
    private RoleDao roleDao;
    
    @Autowired
    private IginXClient iginxClient;

    /**
     * 查询用户 - 参考ModelFileService.queryMeta
     */
    public UserEntity queryUser(String username) {
        try {
            // 构建查询SQL - 完全参考AssociationRulesService
            String querySql = "SELECT * FROM " + USERS_TABLE + " WHERE username = '" + username + "';";
            
            log.info("执行用户查询SQL: {}", querySql);
            
            // 使用Session.executeSql - 参考AssociationRulesService
            SessionExecuteSqlResult result = iginxSession.executeSql(querySql);
            List<Map<String, Object>> records = ConvertUtil.getRecords(result);
            
            if (records.isEmpty()) {
                return null;
            }
            
            // 转换为UserEntity - 参考ModelFileService的转换方式
            Map<String, Object> record = records.get(0);
            return mapToUserEntity(record);
        } catch (Exception e) {
            log.error("查询用户失败: {}", e.getMessage(), e);
            return null;
        }
    }

    /**
     * 根据用户名获取用户 - Spring Security 用户详情服务使用
     * @param username 用户名
     * @return 用户实体，如果不存在返回null
     */
    public UserEntity getUserByUsername(String username) {
        return queryUser(username);
    }
    
    /**
     * 查询所有用户 - 参考ModelFileService.queryMetaList
     */
    public List<UserEntity> queryAllUsers() {
        try {
            // 构建查询SQL - 完全参考AssociationRulesService
            String querySql = "SELECT * FROM " + USERS_TABLE + " ORDER BY timestamp;";
            
            log.info("执行查询所有用户SQL: {}", querySql);
            
            SessionExecuteSqlResult result = iginxSession.executeSql(querySql);
            List<Map<String, Object>> records = ConvertUtil.getRecords(result);
            
            List<UserEntity> users = new ArrayList<>();
            for (Map<String, Object> record : records) {
                users.add(mapToUserEntity(record));
            }
            
            return users;
        } catch (Exception e) {
            log.error("查询所有用户失败: {}", e.getMessage(), e);
            return new ArrayList<>();
        }
    }

    /**
     * 根据条件查询用户
     */
    public List<UserEntity> queryUsers(String username, String role, String enabled, Integer page, Integer pageSize) {
        try {
            // 构建查询SQL - 完全参考AssociationRulesService
            StringBuilder sql = new StringBuilder("SELECT * FROM ").append(USERS_TABLE).append(" WHERE 1=1");
            
            // 添加用户名筛选
            if (username != null && !username.trim().isEmpty()) {
                sql.append(" AND username LIKE '^.*").append(username.trim()).append(".*'");
            }
            
            // 添加角色筛选
            if (role != null && !role.trim().isEmpty()) {
                sql.append(" AND role = '").append(role.trim()).append("'");
            }
            
            // 添加状态筛选
            if (enabled != null && !enabled.trim().isEmpty()) {
                boolean enabledValue = "true".equals(enabled);
                sql.append(" AND enabled = ").append(enabledValue);
            }
            
            // 添加排序和分页
            sql.append(" ORDER BY timestamp DESC");
            if (page != null && pageSize != null) {
                sql.append(" LIMIT ").append(pageSize);
                sql.append(" OFFSET ").append((page - 1) * pageSize);
            }
            sql.append(";");
            
            String querySql = sql.toString();
            
            log.info("执行筛选查询用户SQL: {}", querySql);
            
            // 使用Session.executeSql - 参考AssociationRulesService
            SessionExecuteSqlResult result = iginxSession.executeSql(querySql);
            List<Map<String, Object>> records = ConvertUtil.getRecords(result);
            
            List<UserEntity> users = new ArrayList<>();
            for (Map<String, Object> record : records) {
                users.add(mapToUserEntity(record));
            }
            
            return users;
        } catch (Exception e) {
            log.error("筛选查询用户失败: {}", e.getMessage(), e);
            return new ArrayList<>();
        }
    }
    
    /**
     * 保存用户 - 参考ModelFileService.saveModelMetadata
     */
    public void saveUser(UserEntity user) {
        try {
            // 先查询用户是否存在
            UserEntity existingUser = queryUser(user.getUsername());
            
            long timestamp;
            if (existingUser != null && existingUser.getTimestamp() != null) {
                timestamp = existingUser.getTimestamp();
                log.info("更新现有用户: {}", user.getUsername());
            } else {
                timestamp = user.getTimestamp() != null ? user.getTimestamp() : System.currentTimeMillis();
                log.info("创建新用户: {}", user.getUsername());
            }
            
            // 创建数据点列表 - 完全参考ModelFileService.saveModelMetadata
            List<Point> userPoints = new ArrayList<>();
            userPoints.add(ConvertUtil.createFieldPoint(USERS_TABLE, "username", user.getUsername(), timestamp));
            userPoints.add(ConvertUtil.createFieldPoint(USERS_TABLE, "password", user.getPassword(), timestamp));
            userPoints.add(ConvertUtil.createFieldPoint(USERS_TABLE, "role", user.getRole(), timestamp));
            
            // 设置roleId - 如果没有指定，则通过角色名称查询
            Long roleId = user.getRoleId();
            if (roleId == null && user.getRole() != null) {
                // 查询角色获取timestamp作为roleId
                try {
                    RoleEntity roleEntity = roleDao.queryRole(user.getRole());
                    if (roleEntity != null) {
                        roleId = roleEntity.getTimestamp();
                    } else {
                        log.warn("角色 {} 不存在，使用默认值", user.getRole());
                        roleId = 0L;
                    }
                } catch (Exception e) {
                    log.warn("无法查询角色 {} 的timestamp，使用默认值: {}", user.getRole(), e.getMessage());
                    roleId = 0L;
                }
            }
            
            userPoints.add(ConvertUtil.createFieldPoint(USERS_TABLE, "roleId", roleId, timestamp));
            userPoints.add(ConvertUtil.createFieldPoint(USERS_TABLE, "enabled", user.isEnabled(), timestamp));
            userPoints.add(ConvertUtil.createFieldPoint(USERS_TABLE, "timestamp", timestamp, timestamp));
            
            // 使用writeClient写入 - 参考ModelFileService
            cn.edu.tsinghua.iginx.session_v2.WriteClient writeClient = iginxClient.getWriteClient();
            writeClient.writePoints(userPoints);
            
            log.info("用户已保存: {}, 时间戳: {}", user.getUsername(), timestamp);
        } catch (Exception e) {
            log.error("保存用户失败: {}", e.getMessage(), e);
            throw new RuntimeException("保存用户失败: " + e.getMessage(), e);
        }
    }
    
    /**
     * 删除用户 - 参考ModelFileService.deleteModel
     */
    public void deleteUser(String username) {
        try {
            // 先查询用户获取时间戳
            UserEntity user = queryUser(username);
            if (user == null || user.getTimestamp() == null) {
                log.warn("用户不存在，无法删除: {}", username);
                return;
            }
            
            // 获取所有字段名 - 参考ModelFileService.deleteModel
            List<String> measurements = ConvertUtil.iginxFieldNamesConvert(UserEntity.class, USERS_TABLE);
            
            // 删除指定时间戳的数据 - 参考ModelFileService
            long timestamp = user.getTimestamp();
            iginxClient.getDeleteClient().deleteMeasurementsData(measurements, timestamp - 1, timestamp + 1);
            
            log.info("用户已删除: {}, 时间戳: {}", username, timestamp);
        } catch (Exception e) {
            log.error("删除用户失败: {}", e.getMessage(), e);
            throw new RuntimeException("删除用户失败: " + e.getMessage(), e);
        }
    }
    
    /**
     * 检查用户是否存在
     */
    public boolean existsUser(String username) {
        return queryUser(username) != null;
    }
    
    /**
     * 将记录映射为用户实体 - 参考ModelFileService的转换方式
     */
    private UserEntity mapToUserEntity(Map<String, Object> record) {
        UserEntity user = new UserEntity();
        
        // 使用ConvertUtil的通用方法设置字段值 - 参考ModelFileService.queryMeta
        record.forEach((k, v) -> {
            String fieldName = k.replace(USERS_TABLE + ".", "");
            ConvertUtil.setEntityField(user, USERS_TABLE, fieldName, v);
        });
        
        return user;
    }
}
