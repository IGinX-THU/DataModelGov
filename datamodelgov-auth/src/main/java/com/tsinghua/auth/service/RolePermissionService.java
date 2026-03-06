package com.tsinghua.auth.service;

import com.tsinghua.auth.dao.RoleDao;
import com.tsinghua.auth.dao.UserDao;
import com.tsinghua.auth.entity.RoleEntity;
import com.tsinghua.auth.entity.UserEntity;
import com.tsinghua.auth.enums.Permission;
import com.tsinghua.auth.enums.UserRole;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import javax.annotation.PostConstruct;
import java.util.*;

/**
 * 基于IGinX的角色权限管理服务 - 完全参考ModelFileService和AssociationRulesService实现方式
 */
@Slf4j
@Service
public class RolePermissionService {
    
    private PasswordEncoder passwordEncoder;
    
    @Autowired
    private UserDao userDao;
    
    @Autowired
    private RoleDao roleDao;
    
    public RolePermissionService() {
        // 构造函数不再初始化数据
    }
    
    /**
     * 设置密码编码器（由Spring在初始化后调用）
     */
    public void setPasswordEncoder(PasswordEncoder passwordEncoder) {
        this.passwordEncoder = passwordEncoder;
        
        // 检查是否有明文密码的用户，如果有则清理并重新初始化
        if (hasPlaintextPasswordUsers()) {
            log.info("检测到明文密码用户，清理并重新初始化RBAC数据");
            clearAllData();
        }
        
        // 重新初始化用户数据，使用加密密码
        initializeData();
    }
    
    /**
     * 检查是否有明文密码的用户
     */
    private boolean hasPlaintextPasswordUsers() {
        try {
            List<UserEntity> users = userDao.queryAllUsers();
            for (UserEntity user : users) {
                String password = user.getPassword();
                if (password != null && !password.startsWith("$2a$") && 
                    !password.startsWith("$2b$") && !password.startsWith("$2y$")) {
                    return true;
                }
            }
            return false;
        } catch (Exception e) {
            log.error("检查明文密码用户失败: {}", e.getMessage(), e);
            return false;
        }
    }
    
    /**
     * 更新已存在的明文密码为加密密码
     */
    private void updateExistingPasswordsToEncrypted() {
        if (passwordEncoder == null) {
            return;
        }
        
        try {
            List<UserEntity> users = userDao.queryAllUsers();
            boolean needsUpdate = false;
            
            for (UserEntity user : users) {
                // 检查密码是否已加密（BCrypt密码以$2a$、$2b$或$2y$开头）
                String password = user.getPassword();
                if (password != null && !password.startsWith("$2a$") && 
                    !password.startsWith("$2b$") && !password.startsWith("$2y$")) {
                    
                    // 密码未加密，需要更新
                    log.info("更新用户 {} 的密码为加密格式", user.getUsername());
                    String newPassword = passwordEncoder.encode(password);
                    UserEntity updatedUser = new UserEntity(
                        user.getUsername(), 
                        newPassword, 
                        user.getRole(), 
                        user.getTimestamp()
                    );
                    userDao.saveUser(updatedUser);
                    needsUpdate = true;
                }
            }
            
            if (needsUpdate) {
                log.info("已更新所有用户的密码为加密格式");
            }
        } catch (Exception e) {
            log.error("更新用户密码为加密格式失败: {}", e.getMessage(), e);
        }
    }
    
    /**
     * 清理所有RBAC数据（用于重新初始化）
     */
    public void clearAllData() {
        try {
            log.info("清理所有RBAC数据");
            
            // 删除所有用户
            List<UserEntity> users = userDao.queryAllUsers();
            for (UserEntity user : users) {
                userDao.deleteUser(user.getUsername());
            }
            
            // 删除所有角色
            List<RoleEntity> roles = roleDao.queryAllRoles();
            for (RoleEntity role : roles) {
                roleDao.deleteRole(role.getRole());
            }
            
            log.info("RBAC数据清理完成");
        } catch (Exception e) {
            log.error("清理RBAC数据失败: {}", e.getMessage(), e);
        }
    }
    
    /**
     * 初始化数据（从IGinX查询，不存在则插入）
     */
    @PostConstruct
    public void initializeData() {
        try {
            // 先初始化DAO
            userDao.init();
            roleDao.init();
            
            // 先从IGinX查询现有数据
            List<UserEntity> existingUsers = userDao.queryAllUsers();
            List<RoleEntity> existingRoles = roleDao.queryAllRoles();
            
            log.info("从IGinX查询到 {} 个用户，{} 个角色", existingUsers.size(), existingRoles.size());
            
            // 如果没有数据，则初始化默认数据
            if (existingUsers.isEmpty() && existingRoles.isEmpty()) {
                log.info("IGinX中没有RBAC数据，初始化默认数据");
                initializeDefaultData();
            }
            
        } catch (Exception e) {
            log.error("初始化RBAC数据失败: {}", e.getMessage(), e);
        }
    }
    
    /**
     * 初始化默认数据
     */
    private void initializeDefaultData() {
        try {
            // 初始化默认角色
            initializeDefaultRoles();
            
            // 初始化默认用户
            initializeDefaultUsers();
            
            log.info("默认RBAC数据初始化完成");
        } catch (Exception e) {
            log.error("初始化默认RBAC数据失败: {}", e.getMessage(), e);
        }
    }
    
    /**
     * 初始化默认角色
     */
    private void initializeDefaultRoles() {
        // 管理员角色
        Set<Permission> adminPermissions = EnumSet.allOf(Permission.class);
        RoleEntity adminRole = new RoleEntity(UserRole.ADMIN, adminPermissions, 2000000000000L);
        roleDao.saveRole(adminRole);
        
        // 数据工程师角色
        Set<Permission> dataEngineerPermissions = EnumSet.of(
            // 数据源管理权限
            Permission.DATASOURCE_REGISTER,
            Permission.DATASOURCE_REMOVE,
            Permission.DATASOURCE_LIST,
            Permission.DATASOURCE_TREE,
            
            // 数据表管理权限
            Permission.DATA_QUERY,
            Permission.DATA_IMPORT,
            Permission.DATA_EXPORT,
            Permission.DATA_DELETE,
            Permission.DATA_RELATIONAL_QUERY,
            Permission.DATA_RELATIONAL_COUNT,
            Permission.DATA_RELATIONAL_EXPORT
        );
        RoleEntity dataEngineerRole = new RoleEntity(UserRole.DATA_ENGINEER, dataEngineerPermissions, 2000000000001L);
        roleDao.saveRole(dataEngineerRole);
        
        // 模型工程师角色
        Set<Permission> modelEngineerPermissions = EnumSet.of(
            Permission.MODEL_UPLOAD,
            Permission.MODEL_DOWNLOAD,
            Permission.MODEL_QUERY_META,
            Permission.MODEL_SAVE_META,
            Permission.MODEL_HISTORY,
            Permission.MODEL_DELETE,

            // 数据源查询权限
            Permission.DATASOURCE_TREE
        );
        RoleEntity modelEngineerRole = new RoleEntity(UserRole.MODEL_ENGINEER, modelEngineerPermissions, 2000000000002L);
        roleDao.saveRole(modelEngineerRole);
        
        // 仿真工程师角色
        Set<Permission> simulationEngineerPermissions = EnumSet.of(
            // 关联规则管理权限
            Permission.ASSOCIATION_RULES_SAVE,
            Permission.ASSOCIATION_RULES_QUERY,
            Permission.ASSOCIATION_RULES_COUNT,
            Permission.ASSOCIATION_RULES_DETAIL,
            Permission.ASSOCIATION_RULES_DELETE,
            
            // 数据与模型的查询相关接口权限
            Permission.DATA_QUERY,
            Permission.DATA_RELATIONAL_QUERY,
            Permission.DATA_RELATIONAL_COUNT,
            Permission.MODEL_QUERY_META,
            Permission.MODEL_HISTORY,
            
            // 数据源查询权限
            Permission.DATASOURCE_LIST,
            Permission.DATASOURCE_TREE
        );
        RoleEntity simulationEngineerRole = new RoleEntity(UserRole.SIMULATION_ENGINEER, simulationEngineerPermissions, 2000000000003L);
        roleDao.saveRole(simulationEngineerRole);
    }
    
    /**
     * 初始化默认用户
     */
    private void initializeDefaultUsers() {
        // 创建默认用户 - 确保密码加密并设置正确的roleId
        if (passwordEncoder != null) {
            // 获取角色的timestamp作为roleId
            Long adminRoleId = getRoleTimestamp(UserRole.ADMIN);
            Long dataEngineerRoleId = getRoleTimestamp(UserRole.DATA_ENGINEER);
            Long modelEngineerRoleId = getRoleTimestamp(UserRole.MODEL_ENGINEER);
            Long simulationEngineerRoleId = getRoleTimestamp(UserRole.SIMULATION_ENGINEER);
            
            userDao.saveUser(new UserEntity("admin", passwordEncoder.encode("admin123"), UserRole.ADMIN, adminRoleId, 1000000000000L));
            userDao.saveUser(new UserEntity("data", passwordEncoder.encode("data123"), UserRole.DATA_ENGINEER, dataEngineerRoleId, 1000000000001L));
            userDao.saveUser(new UserEntity("model", passwordEncoder.encode("model123"), UserRole.MODEL_ENGINEER, modelEngineerRoleId, 1000000000002L));
            userDao.saveUser(new UserEntity("sim", passwordEncoder.encode("sim123"), UserRole.SIMULATION_ENGINEER, simulationEngineerRoleId, 1000000000003L));
            userDao.saveUser(new UserEntity("user", passwordEncoder.encode("user123"), UserRole.SIMULATION_ENGINEER, simulationEngineerRoleId, 1000000000004L));
        } else {
            // 如果密码编码器还未设置，先保存明文密码，稍后更新
            log.warn("密码编码器未设置，使用明文密码保存用户");
            userDao.saveUser(new UserEntity("admin", "admin123", UserRole.ADMIN, 1000000000000L));
            userDao.saveUser(new UserEntity("data", "data123", UserRole.DATA_ENGINEER, 1000000000001L));
            userDao.saveUser(new UserEntity("model", "model123", UserRole.MODEL_ENGINEER, 1000000000002L));
            userDao.saveUser(new UserEntity("sim", "sim123", UserRole.SIMULATION_ENGINEER, 1000000000003L));
            userDao.saveUser(new UserEntity("user", "user123", UserRole.SIMULATION_ENGINEER, 1000000000004L));
        }
    }
    
    /**
     * 获取角色的timestamp
     */
    private Long getRoleTimestamp(String roleName) {
        try {
            RoleEntity role = roleDao.queryRole(roleName);
            return role != null ? role.getTimestamp() : 0L;
        } catch (Exception e) {
            log.warn("无法获取角色 {} 的timestamp: {}", roleName, e.getMessage());
            return 0L;
        }
    }
    
    /**
     * 获取所有用户信息（用于Spring Security）
     */
    public UserDetails[] getAllUsers() {
        List<UserEntity> users = userDao.queryAllUsers();
        return users.stream()
                .map(UserEntity::toUserDetails)
                .toArray(UserDetails[]::new);
    }
    
    /**
     * 根据用户名获取用户实体
     */
    public UserEntity getUserByUsername(String username) {
        return userDao.queryUser(username);
    }
    
    /**
     * 获取所有用户实体
     */
    public List<UserEntity> getAllUserEntities() {
        return userDao.queryAllUsers();
    }
    
    /**
     * 获取所有角色实体
     */
    public List<RoleEntity> getAllRoleEntities() {
        return roleDao.queryAllRoles();
    }
    
    /**
     * 根据角色获取角色实体
     */
    public RoleEntity getRoleEntity(String role) {
        return roleDao.queryRole(role);
    }
    
    /**
     * 根据用户名获取用户角色
     */
    public String getUserRole(String username) {
        UserEntity user = userDao.queryUser(username);
        return user != null ? user.getRole() : null;
    }
    
    /**
     * 根据角色获取权限集合 - 直接从IGinX查询
     */
    public Set<Permission> getRolePermissions(String role) {
        RoleEntity roleEntity = roleDao.queryRole(role);
        return roleEntity != null ? roleEntity.getPermissions() : Collections.emptySet();
    }
    
    /**
     * 检查角色是否拥有指定权限
     */
    public boolean hasPermission(String role, Permission permission) {
        Set<Permission> permissions = getRolePermissions(role);
        return permissions.contains(permission);
    }
    
    /**
     * 检查角色是否拥有所有指定权限
     */
    public boolean hasAllPermissions(String role, Permission[] permissions) {
        Set<Permission> rolePermissionSet = getRolePermissions(role);
        if (rolePermissionSet.isEmpty()) {
            return false;
        }
        
        for (Permission permission : permissions) {
            if (!rolePermissionSet.contains(permission)) {
                return false;
            }
        }
        return true;
    }
    
    /**
     * 添加用户
     */
    public void addUser(UserEntity user) {
        // 获取角色的timestamp作为roleId
        Long roleId = getRoleTimestamp(user.getRole());
        
        // 加密密码后再存储
        if (passwordEncoder != null) {
            UserEntity encryptedUser = new UserEntity(
                user.getUsername(), 
                passwordEncoder.encode(user.getPassword()), 
                user.getRole(),
                roleId,
                user.getTimestamp()
            );
            userDao.saveUser(encryptedUser);
        } else {
            UserEntity userWithRoleId = new UserEntity(
                user.getUsername(), 
                user.getPassword(), 
                user.getRole(),
                roleId,
                user.getTimestamp()
            );
            userDao.saveUser(userWithRoleId);
        }
    }
    
    /**
     * 移除用户
     */
    public void removeUser(String username) {
        userDao.deleteUser(username);
    }
    
    /**
     * 更新用户
     */
    public void updateUser(UserEntity user) {
        // 获取角色的timestamp作为roleId
        Long roleId = getRoleTimestamp(user.getRole());
        
        // 如果密码未加密，则加密后再存储
        String password = user.getPassword();
        if (passwordEncoder != null && 
            !password.startsWith("$2a$") && !password.startsWith("$2b$") && !password.startsWith("$2y$")) {
            password = passwordEncoder.encode(password);
        }
        
        UserEntity updatedUser = new UserEntity(
            user.getUsername(), 
            password, 
            user.getRole(),
            roleId,
            user.getTimestamp()
        );
        userDao.saveUser(updatedUser);
    }
    
    /**
     * 添加角色
     */
    public void addRole(RoleEntity role) {
        roleDao.saveRole(role);
    }
    
    /**
     * 移除角色
     */
    public void removeRole(String role) {
        roleDao.deleteRole(role);
    }
    
    /**
     * 更新角色
     */
    public void updateRole(RoleEntity role) {
        roleDao.saveRole(role);
    }
}
