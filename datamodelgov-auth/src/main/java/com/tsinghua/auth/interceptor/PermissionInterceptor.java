package com.tsinghua.auth.interceptor;

import com.tsinghua.auth.annotation.RequirePermission;
import com.tsinghua.auth.enums.Permission;
import com.tsinghua.auth.enums.UserRole;
import com.tsinghua.auth.service.RolePermissionService;
import com.tsinghua.model.Result;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.method.HandlerMethod;
import org.springframework.web.servlet.HandlerInterceptor;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.lang.reflect.Method;
import java.util.Set;

/**
 * 权限校验拦截器
 */
@Slf4j
@Component
public class PermissionInterceptor implements HandlerInterceptor {
    
    @Autowired
    private RolePermissionService rolePermissionService;
    
    private final ObjectMapper objectMapper = new ObjectMapper();
    
    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
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
        boolean hasPermission = rolePermissionService.hasAllPermissions(userRole, requiredPermissions);
        
        if (!hasPermission) {
            Set<Permission> userPermissions = rolePermissionService.getRolePermissions(userRole);
            
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
        return rolePermissionService.getUserRole(username);
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
