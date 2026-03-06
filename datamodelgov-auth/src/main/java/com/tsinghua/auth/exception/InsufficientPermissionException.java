package com.tsinghua.auth.exception;

import com.tsinghua.auth.enums.Permission;
import java.util.Set;

/**
 * 权限不足异常
 */
public class InsufficientPermissionException extends RuntimeException {
    
    private final String userRole;
    private final Set<Permission> userPermissions;
    private final Permission[] requiredPermissions;
    
    public InsufficientPermissionException(String userRole, Set<Permission> userPermissions, Permission[] requiredPermissions) {
        super(buildMessage(userRole, userPermissions, requiredPermissions));
        this.userRole = userRole;
        this.userPermissions = userPermissions;
        this.requiredPermissions = requiredPermissions;
    }
    
    public String getUserRole() {
        return userRole;
    }
    
    public Set<Permission> getUserPermissions() {
        return userPermissions;
    }
    
    public Permission[] getRequiredPermissions() {
        return requiredPermissions;
    }
    
    private static String buildMessage(String userRole, Set<Permission> userPermissions, Permission[] requiredPermissions) {
        StringBuilder missingPermissions = new StringBuilder();
        for (Permission permission : requiredPermissions) {
            if (!userPermissions.contains(permission)) {
                if (missingPermissions.length() > 0) {
                    missingPermissions.append(", ");
                }
                missingPermissions.append(permission.getDescription()).append("[").append(permission.name()).append("]");
            }
        }
        
        return String.format(
            "权限不足！当前角色：%s（%s），缺少权限：%s。请联系管理员分配相应权限。",
            userRole, com.tsinghua.auth.enums.UserRole.getDescription(userRole), missingPermissions.toString()
        );
    }
}
