package com.tsinghua.util;

import lombok.extern.slf4j.Slf4j;

/**
 * 项目上下文工具类
 * 提供获取当前项目信息等常用功能
 */
@Slf4j
public class ProjectContext {

    private static final ThreadLocal<String> currentProject = new ThreadLocal<>();

    /**
     * 设置当前项目
     * 
     * @param projectName 项目名称
     */
    public static void setCurrentProject(String projectName) {
        if (projectName != null && !projectName.trim().isEmpty()) {
            currentProject.set(projectName);
            log.debug("设置当前项目: {}", projectName);
        } else {
            clear();
        }
    }

    /**
     * 获取当前项目名称
     * 
     * @return 当前项目名称，如果获取失败返回 null
     */
    public static String getCurrentProject() {
        try {
            return currentProject.get();
        } catch (Exception e) {
            log.warn("获取当前项目失败: {}", e.getMessage());
            return null;
        }
    }

    /**
     * 获取当前项目名称（带默认值）
     * 
     * @param defaultValue 默认值
     * @return 当前项目名称，如果获取失败返回指定的默认值
     */
    public static String getCurrentProject(String defaultValue) {
        String project = getCurrentProject();
        return project != null ? project : defaultValue;
    }

    /**
     * 检查是否有当前项目
     * 
     * @return true if project is set, false otherwise
     */
    public static boolean hasCurrentProject() {
        return getCurrentProject() != null;
    }

    /**
     * 清除当前项目
     */
    public static void clear() {
        currentProject.remove();
        log.debug("清除当前项目");
    }
}
