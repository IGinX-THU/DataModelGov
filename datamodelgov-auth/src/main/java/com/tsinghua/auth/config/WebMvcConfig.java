package com.tsinghua.auth.config;

import com.tsinghua.auth.interceptor.PermissionInterceptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.condition.ConditionalOnBean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * Web MVC配置类
 * 只在auth模块中生效，配置权限拦截器
 */
@Configuration
@ConditionalOnBean(PermissionInterceptor.class)
public class WebMvcConfig implements WebMvcConfigurer {

    @Autowired
    private PermissionInterceptor permissionInterceptor;

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(permissionInterceptor)
                .addPathPatterns("/api/**") // 拦截所有API接口进行权限检查
                .excludePathPatterns("/api/auth/**", "/api/rbac/**", "/api/test/**"); // 排除认证、RBAC测试和测试接口
    }
}
