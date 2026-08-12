package com.tsinghua.auth.interceptor;

import com.tsinghua.auth.annotation.RequirePermission;
import com.tsinghua.auth.dao.RoleDao;
import com.tsinghua.auth.dao.UserDao;
import com.tsinghua.auth.entity.RoleEntity;
import com.tsinghua.auth.entity.UserEntity;
import com.tsinghua.auth.enums.Permission;
import com.tsinghua.auth.enums.UserRole;
import com.tsinghua.model.Result;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.method.HandlerMethod;
import org.springframework.web.servlet.HandlerInterceptor;

import javax.servlet.DispatcherType;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.lang.reflect.Method;
import java.util.Collections;
import java.util.HashSet;
import java.util.Set;

/**
 * 权限校验拦截器
 */
@Slf4j
@Component
public class PermissionInterceptor implements HandlerInterceptor {
    
    @Autowired
    private UserDao userDao;
    
    @Autowired
    private RoleDao roleDao;
    
    private final ObjectMapper objectMapper = new ObjectMapper();
    
    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
        // SSE 等异步请求的 async dispatch 无需重新校验权限（初始请求已校验）
        // 且 async dispatch 时 SecurityContext 可能丢失，重新校验会导致写已提交的 response 而抛异常
        if (request.getDispatcherType() == DispatcherType.ASYNC) {
            return true;
        }

        if (!(handler instanceof HandlerMethod)) {
            return true;
        }
        
        HandlerMethod handlerMethod = (HandlerMethod) handler;
        Method method = handlerMethod.getMethod();
        
        // 检查方法或类上是否有权限注解
        RequirePermission requirePermission = method.getAnnotation(RequirePermission.class);
        if (requirePermission == null) {
            requirePermission = handlerMethod.getBeanType().getAnnotation(RequirePermission.class);
        }
        
        // 如果没有权限注解，直接放行
        if (requirePermission == null || requirePermission.value().length == 0) {
            return true;
        }
        
        // 获取用户角色
        String userRole = getUserRoleFromSecurityContext();
        if (userRole == null) {
            writeErrorResponse(response, 401, "用户未认证，请先登录");
            return false;
        }
        
        // 检查权限
        Permission[] requiredPermissions = requirePermission.value();
        boolean hasPermission = hasAllPermissions(userRole, requiredPermissions);
        
        if (!hasPermission) {
            Set<Permission> userPermissions = getRolePermissions(userRole);
            
            // 构建详细的权限错误信息
            StringBuilder missingPermissions = new StringBuilder();
            for (Permission permission : requiredPermissions) {
                if (!userPermissions.contains(permission)) {
                    if (missingPermissions.length() > 0) {
                        missingPermissions.append(", ");
                    }
                    missingPermissions.append(permission.getDescription()).append("[").append(permission.name()).append("]");
                }
            }
            
            String errorMessage = String.format(
                "权限不足！当前角色：%s（%s），缺少权限：%s。请联系管理员分配相应权限。",
                userRole, com.tsinghua.auth.enums.UserRole.getDescription(userRole), missingPermissions.toString()
            );
            
            log.warn("用户角色 {} 无权限访问接口: {} - 缺少权限: {}", 
                    userRole, request.getRequestURI(), missingPermissions.toString());
            
            writeErrorResponse(response, 403, errorMessage);
            return false;
        }
        
        log.debug("用户角色 {} 成功访问接口: {}", userRole, request.getRequestURI());
        return true;
    }
    
    /**
     * 从Spring Security上下文获取用户角色
     */
    private String getUserRoleFromSecurityContext() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated()) {
            return null;
        }
        
        String username = authentication.getName();
        try {
            UserEntity user = userDao.queryUser(username);
            return user != null ? user.getRole() : null;
        } catch (Exception e) {
            log.error("查询用户 {} 失败: {}", username, e.getMessage());
            return null;
        }
    }
    
    /**
     * 根据角色获取权限集合
     */
    private Set<Permission> getRolePermissions(String role) {
        try {
            RoleEntity roleEntity = roleDao.queryRole(role);
            return roleEntity != null ? roleEntity.getPermissions() : Collections.emptySet();
        } catch (Exception e) {
            log.error("查询角色 {} 权限失败: {}", role, e.getMessage());
            return Collections.emptySet();
        }
    }
    
    /**
     * 检查角色是否拥有所有指定权限
     */
    private boolean hasAllPermissions(String role, Permission[] permissions) {
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
     * 写入错误响应
     */
    private void writeErrorResponse(HttpServletResponse response, int statusCode, String message) throws IOException {
        response.setContentType("application/json;charset=UTF-8");
        response.setStatus(statusCode);
        
        Result<Void> errorResult = Result.authError(message);
        errorResult.setCode(statusCode);
        
        String jsonResponse = objectMapper.writeValueAsString(errorResult);
        response.getWriter().write(jsonResponse);
        response.getWriter().flush();
    }
}
