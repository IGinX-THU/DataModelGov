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
        // 注册权限拦截器
        registry.addInterceptor(permissionInterceptor)
                .addPathPatterns("/api/**") // 拦截所有API接口进行权限检查
                .excludePathPatterns("/api/auth/**", "/api/rbac/**", "/api/test/**", "/api/doc/**"); // 排除认证、RBAC测试、测试接口和文档接口
    }
}
