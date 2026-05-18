package com.tsinghua.auth.service;

import com.tsinghua.auth.dao.RoleDao;
import com.tsinghua.auth.dao.UserDao;
import com.tsinghua.auth.entity.RoleEntity;
import com.tsinghua.auth.entity.UserEntity;
import com.tsinghua.auth.enums.Permission;
import com.tsinghua.auth.enums.UserRole;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.BeansException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationContext;
import org.springframework.context.ApplicationContextAware;
import org.springframework.context.event.ContextRefreshedEvent;
import org.springframework.context.event.EventListener;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import java.util.*;

/**
 * 基于IGinX的角色权限管理服务 - 完全参考ModelFileService和AssociationRulesService实现方式
 */
@Slf4j
@Service
public class RolePermissionService implements ApplicationContextAware {
    
    private PasswordEncoder passwordEncoder;
    private ApplicationContext applicationContext;
    
    @Autowired
    private UserDao userDao;
    
    @Autowired
    private RoleDao roleDao;
    
    public RolePermissionService() {
        // 构造函数不再初始化数据
    }
    
    @Override
    public void setApplicationContext(ApplicationContext applicationContext) throws BeansException {
        this.applicationContext = applicationContext;
    }
    
    /**
     * 延迟获取PasswordEncoder以避免循环依赖
     */
    private PasswordEncoder getPasswordEncoder() {
        if (passwordEncoder == null && applicationContext != null) {
            passwordEncoder = applicationContext.getBean(PasswordEncoder.class);
        }
        return passwordEncoder;
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
        if (getPasswordEncoder() == null) {
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
                    String newPassword = getPasswordEncoder().encode(password);
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
     * 在Spring容器完全初始化后执行
     */
    @EventListener(ContextRefreshedEvent.class)
    public void initializeData() {
        try {

            // 先从IGinX查询现有数据
            List<UserEntity> existingUsers = userDao.queryAllUsers();
            List<RoleEntity> existingRoles = roleDao.queryAllRoles();
            
            log.info("从IGinX查询到 {} 个用户，{} 个角色", existingUsers.size(), existingRoles.size());
            
            // 检查是否有明文密码的用户，如果有则清理并重新初始化
            if (hasPlaintextPasswordUsers()) {
                log.info("检测到明文密码用户，清理并重新初始化RBAC数据");
                clearAllData();
                existingUsers.clear();
                existingRoles.clear();
            }
            
            // 如果没有数据，则初始化默认数据
            if (existingUsers.isEmpty() || existingRoles.isEmpty()) {
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
        // 管理员角色 - 拥有所有权限
        Set<Permission> adminPermissions = EnumSet.allOf(Permission.class);
        RoleEntity adminRole = new RoleEntity(UserRole.ADMIN, adminPermissions, 2000000000000L);
        roleDao.saveRole(adminRole);
        
        // 数据工程师角色 - 除用户管理外的所有权限
        Set<Permission> dataEngineerPermissions = EnumSet.allOf(Permission.class);
        dataEngineerPermissions.remove(Permission.USER_CREATE);
        dataEngineerPermissions.remove(Permission.USER_READ);
        dataEngineerPermissions.remove(Permission.USER_UPDATE);
        dataEngineerPermissions.remove(Permission.USER_DELETE);
        RoleEntity dataEngineerRole = new RoleEntity(UserRole.DATA_ENGINEER, dataEngineerPermissions, 2000000000001L);
        roleDao.saveRole(dataEngineerRole);
    }
    
    /**
     * 初始化默认用户
     */
    private void initializeDefaultUsers() {
        // 创建默认用户 - 使用加密密码
        log.info("使用加密密码初始化默认用户");
        
        // 获取角色的timestamp作为roleId
        Long adminRoleId = 2000000000000L;
        Long dataEngineerRoleId = 2000000000001L;

        userDao.saveUser(new UserEntity("admin", getPasswordEncoder().encode("admin123"), UserRole.ADMIN, adminRoleId, 1000000000000L));
        userDao.saveUser(new UserEntity("data", getPasswordEncoder().encode("data123"), UserRole.DATA_ENGINEER, dataEngineerRoleId, 1000000000001L));
        userDao.saveUser(new UserEntity("user", getPasswordEncoder().encode("user123"), UserRole.DATA_ENGINEER, dataEngineerRoleId, 1000000000002L));

        log.info("默认用户初始化完成: admin/admin123, data/data123");
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
        if (getPasswordEncoder() != null) {
            UserEntity encryptedUser = new UserEntity(
                user.getUsername(), 
                getPasswordEncoder().encode(user.getPassword()), 
                user.getRole(),
                roleId,
                user.getTimestamp()
            );
            // 设置 enabled 字段
            encryptedUser.setEnabled(user.isEnabled());
            userDao.saveUser(encryptedUser);
        } else {
            UserEntity userWithRoleId = new UserEntity(
                user.getUsername(), 
                user.getPassword(), 
                user.getRole(),
                roleId,
                user.getTimestamp()
            );
            // 设置 enabled 字段
            userWithRoleId.setEnabled(user.isEnabled());
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
        
        // 查询原用户信息
        UserEntity originalUser = userDao.queryUser(user.getUsername());
        if (originalUser == null) {
            throw new RuntimeException("用户不存在: " + user.getUsername());
        }
        
        // 如果密码为空，则保留原密码；否则加密新密码
        String password;
        if (user.getPassword() == null || user.getPassword().trim().isEmpty()) {
            password = originalUser.getPassword(); // 保留原密码
        } else {
            // 加密新密码
            if (getPasswordEncoder() != null && 
                !user.getPassword().startsWith("$2a$") && 
                !user.getPassword().startsWith("$2b$") && 
                !user.getPassword().startsWith("$2y$")) {
                password = getPasswordEncoder().encode(user.getPassword());
            } else {
                password = user.getPassword();
            }
        }
        
        UserEntity updatedUser = new UserEntity(
            user.getUsername(), 
            password, 
            user.getRole(),
            roleId,
            user.getTimestamp()
        );
        // 设置 enabled 字段
        updatedUser.setEnabled(user.isEnabled());
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
    
    /**
     * 获取所有用户列表
     */
    public List<UserEntity> getAllUsersList() {
        return userDao.queryAllUsers();
    }

    /**
     * 根据条件查询用户列表
     */
    public List<UserEntity> queryUsers(String username, String role, String enabled, Integer page, Integer pageSize) {
        return userDao.queryUsers(username, role, enabled, page, pageSize);
    }
    
    /**
     * 获取用户信息
     */
    public UserEntity getUser(String username) {
        return userDao.queryUser(username);
    }
    
    /**
     * 获取所有角色列表
     */
    public List<RoleEntity> getAllRoles() {
        return roleDao.queryAllRoles();
    }
    
    /**
     * 修改密码
     */
    public boolean changePassword(String username, String oldPassword, String newPassword) {
        try {
            UserEntity user = userDao.queryUser(username);
            if (user == null) {
                log.warn("用户 {} 不存在", username);
                return false;
            }
            
            // 验证原密码
            if (getPasswordEncoder() != null && !getPasswordEncoder().matches(oldPassword, user.getPassword())) {
                log.warn("用户 {} 原密码验证失败", username);
                return false;
            }
            
            // 加密新密码
            String encryptedNewPassword = getPasswordEncoder() != null ? 
                getPasswordEncoder().encode(newPassword) : newPassword;
            
            // 更新密码
            UserEntity updatedUser = new UserEntity(
                user.getUsername(),
                encryptedNewPassword,
                user.getRole(),
                user.getRoleId(),
                user.getTimestamp()
            );
            userDao.saveUser(updatedUser);
            
            log.info("用户 {} 密码修改成功", username);
            return true;
        } catch (Exception e) {
            log.error("修改用户 {} 密码失败: {}", username, e.getMessage(), e);
            return false;
        }
    }
}
