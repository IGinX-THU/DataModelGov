package com.tsinghua.config;

import com.tsinghua.util.ProjectContext;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

/**
 * 项目上下文拦截器
 * 从请求头中提取当前项目信息并设置到ProjectContext中
 */
@Slf4j
@Component
public class ProjectContextInterceptor implements HandlerInterceptor {

    private static final String CURRENT_PROJECT_HEADER = "X-Current-Project";

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
        // 从请求头中获取当前项目
        String currentProject = request.getHeader(CURRENT_PROJECT_HEADER);
        
        // 设置到项目上下文中
        ProjectContext.setCurrentProject(currentProject);
        
        if (currentProject != null && !currentProject.trim().isEmpty()) {
            log.debug("检测到当前项目: {}", currentProject);
        }
        
        return true;
    }

    @Override
    public void afterCompletion(HttpServletRequest request, HttpServletResponse response, Object handler, Exception ex) throws Exception {
        // 请求完成后清除项目上下文
        ProjectContext.clear();
    }
}
