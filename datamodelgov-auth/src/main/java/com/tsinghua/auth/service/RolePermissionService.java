package com.tsinghua.auth.service;

import com.tsinghua.auth.entity.RoleEntity;
import com.tsinghua.auth.entity.UserEntity;
import com.tsinghua.auth.enums.Permission;
import com.tsinghua.auth.enums.UserRole;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 基于内存的角色权限管理服务
 */
@Service
public class RolePermissionService {
    
    private final Map<String, Set<Permission>> rolePermissions = new ConcurrentHashMap<>();
    private final Map<String, UserEntity> users = new ConcurrentHashMap<>();
    private final Map<String, RoleEntity> roles = new ConcurrentHashMap<>();
    
    private PasswordEncoder passwordEncoder;
    
    public RolePermissionService() {
        initializeRoles();
        initializeUsersWithPlainPasswords();
    }
    
    /**
     * 设置密码编码器（由Spring在初始化后调用）
     */
    public void setPasswordEncoder(PasswordEncoder passwordEncoder) {
        this.passwordEncoder = passwordEncoder;
        // 重新初始化用户数据，使用加密密码
        initializeUsersWithEncryptedPasswords();
    }
    
    /**
     * 初始化角色数据
     */
    private void initializeRoles() {
        // 管理员角色
        Set<Permission> adminPermissions = EnumSet.allOf(Permission.class);
        RoleEntity adminRole = new RoleEntity(UserRole.ADMIN, adminPermissions);
        roles.put(UserRole.ADMIN, adminRole);
        rolePermissions.put(UserRole.ADMIN, adminPermissions);
        
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
        RoleEntity dataEngineerRole = new RoleEntity(UserRole.DATA_ENGINEER, dataEngineerPermissions);
        roles.put(UserRole.DATA_ENGINEER, dataEngineerRole);
        rolePermissions.put(UserRole.DATA_ENGINEER, dataEngineerPermissions);
        
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
        RoleEntity modelEngineerRole = new RoleEntity(UserRole.MODEL_ENGINEER, modelEngineerPermissions);
        roles.put(UserRole.MODEL_ENGINEER, modelEngineerRole);
        rolePermissions.put(UserRole.MODEL_ENGINEER, modelEngineerPermissions);
        
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
        RoleEntity simulationEngineerRole = new RoleEntity(UserRole.SIMULATION_ENGINEER, simulationEngineerPermissions);
        roles.put(UserRole.SIMULATION_ENGINEER, simulationEngineerRole);
        rolePermissions.put(UserRole.SIMULATION_ENGINEER, simulationEngineerPermissions);
    }
    
    /**
     * 先用明文密码初始化用户（避免循环依赖）
     */
    private void initializeUsersWithPlainPasswords() {
        users.put("admin", new UserEntity("admin", "admin123", UserRole.ADMIN));
        users.put("data_engineer", new UserEntity("data_engineer", "data123", UserRole.DATA_ENGINEER));
        users.put("model_engineer", new UserEntity("model_engineer", "model123", UserRole.MODEL_ENGINEER));
        users.put("simulation_engineer", new UserEntity("simulation_engineer", "sim123", UserRole.SIMULATION_ENGINEER));
        users.put("user", new UserEntity("user", "user123", UserRole.DATA_ENGINEER));
    }
    
    /**
     * 使用加密密码重新初始化用户数据
     */
    private void initializeUsersWithEncryptedPasswords() {
        if (passwordEncoder != null) {
            users.put("admin", new UserEntity("admin", passwordEncoder.encode("admin123"), UserRole.ADMIN));
            users.put("data_engineer", new UserEntity("data_engineer", passwordEncoder.encode("data123"), UserRole.DATA_ENGINEER));
            users.put("model_engineer", new UserEntity("model_engineer", passwordEncoder.encode("model123"), UserRole.MODEL_ENGINEER));
            users.put("simulation_engineer", new UserEntity("simulation_engineer", passwordEncoder.encode("sim123"), UserRole.SIMULATION_ENGINEER));
            users.put("user", new UserEntity("user", passwordEncoder.encode("user123"), UserRole.DATA_ENGINEER));
        }
    }
    
    /**
     * 获取所有用户信息（用于Spring Security）
     * 实际项目中应该从数据库获取
     */
    public UserDetails[] getAllUsers() {
        return users.values().stream()
                .map(UserEntity::toUserDetails)
                .toArray(UserDetails[]::new);
    }
    
    /**
     * 根据用户名获取用户实体
     */
    public UserEntity getUserByUsername(String username) {
        return users.get(username);
    }
    
    /**
     * 获取所有用户实体
     */
    public List<UserEntity> getAllUserEntities() {
        return new ArrayList<>(users.values());
    }
    
    /**
     * 获取所有角色实体
     */
    public List<RoleEntity> getAllRoleEntities() {
        return new ArrayList<>(roles.values());
    }
    
    /**
     * 根据角色获取角色实体
     */
    public RoleEntity getRoleEntity(String role) {
        return roles.get(role);
    }
    
    /**
     * 检查角色是否具有指定权限
     */
    public boolean hasPermission(String role, Permission permission) {
        Set<Permission> permissions = rolePermissions.get(role);
        return permissions != null && permissions.contains(permission);
    }
    
    /**
     * 检查角色是否具有所有指定权限
     */
    public boolean hasAllPermissions(String role, Permission... permissions) {
        Set<Permission> rolePermissionSet = rolePermissions.get(role);
        if (rolePermissionSet == null) {
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
     * 获取角色的所有权限
     */
    public Set<Permission> getRolePermissions(String role) {
        return rolePermissions.getOrDefault(role, Collections.emptySet());
    }
    
    /**
     * 根据用户名获取用户角色
     */
    public String getUserRole(String username) {
        UserEntity user = users.get(username);
        return user != null ? user.getRole() : null;
    }
    
    /**
     * 添加用户
     */
    public void addUser(UserEntity user) {
        // 加密密码后再存储
        if (passwordEncoder != null) {
            UserEntity encryptedUser = new UserEntity(
                user.getUsername(), 
                passwordEncoder.encode(user.getPassword()), 
                user.getRole(), 
                user.isEnabled()
            );
            users.put(user.getUsername(), encryptedUser);
        } else {
            users.put(user.getUsername(), user);
        }
    }
    
    /**
     * 移除用户
     */
    public void removeUser(String username) {
        users.remove(username);
    }
    
    /**
     * 更新用户
     */
    public void updateUser(UserEntity user) {
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
            user.isEnabled()
        );
        users.put(user.getUsername(), updatedUser);
    }
    
    /**
     * 添加角色
     */
    public void addRole(RoleEntity role) {
        roles.put(role.getRole(), role);
        rolePermissions.put(role.getRole(), role.getPermissions());
    }
    
    /**
     * 移除角色
     */
    public void removeRole(String role) {
        roles.remove(role);
        rolePermissions.remove(role);
    }
    
    /**
     * 更新角色
     */
    public void updateRole(RoleEntity role) {
        roles.put(role.getRole(), role);
        rolePermissions.put(role.getRole(), role.getPermissions());
    }
}
