package com.tsinghua.auth.util;

import lombok.extern.slf4j.Slf4j;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.Authentication;

/**
 * 认证工具类
 * 提供获取当前用户信息等常用功能
 */
@Slf4j
public class AuthUtil {

    /**
     * 获取当前登录用户名
     * 
     * @return 当前用户名，如果获取失败返回 "Unknown User"
     */
    public static String getCurrentUsername() {
        try {
            Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
            if (authentication != null) {
                return authentication.getName();
            }
        } catch (Exception e) {
            log.warn("获取当前用户失败: {}", e.getMessage());
        }
        return "Unknown User";
    }

    /**
     * 获取当前登录用户名（带默认值）
     * 
     * @param defaultValue 默认值
     * @return 当前用户名，如果获取失败返回指定的默认值
     */
    public static String getCurrentUsername(String defaultValue) {
        try {
            Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
            if (authentication != null) {
                return authentication.getName();
            }
        } catch (Exception e) {
            log.warn("获取当前用户失败: {}", e.getMessage());
        }
        return defaultValue;
    }

    /**
     * 检查是否有已认证的用户
     * 
     * @return true if user is authenticated, false otherwise
     */
    public static boolean isAuthenticated() {
        try {
            Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
            return authentication != null && authentication.isAuthenticated();
        } catch (Exception e) {
            log.warn("检查认证状态失败: {}", e.getMessage());
            return false;
        }
    }

    /**
     * 获取当前认证对象
     * 
     * @return Authentication对象，可能为null
     */
    public static Authentication getCurrentAuthentication() {
        try {
            return SecurityContextHolder.getContext().getAuthentication();
        } catch (Exception e) {
            log.warn("获取认证对象失败: {}", e.getMessage());
            return null;
        }
    }

    /**
     * 检查当前用户是否具有指定角色
     * 
     * @param role 角色名称
     * @return true if user has the role, false otherwise
     */
    public static boolean hasRole(String role) {
        try {
            Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
            if (authentication != null) {
                return authentication.getAuthorities().stream()
                    .anyMatch(authority -> authority.getAuthority().equals("ROLE_" + role));
            }
        } catch (Exception e) {
            log.warn("检查用户角色失败: {}", e.getMessage());
        }
        return false;
    }

    /**
     * 检查当前用户是否具有指定权限
     * 
     * @param authority 权限名称
     * @return true if user has the authority, false otherwise
     */
    public static boolean hasAuthority(String authority) {
        try {
            Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
            if (authentication != null) {
                return authentication.getAuthorities().stream()
                    .anyMatch(auth -> auth.getAuthority().equals(authority));
            }
        } catch (Exception e) {
            log.warn("检查用户权限失败: {}", e.getMessage());
        }
        return false;
    }
}
