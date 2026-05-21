package com.tsinghua.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * Web MVC 配置类
 * 注册项目上下文拦截器
 */
@Configuration
public class ProjectWebMvcConfig implements WebMvcConfigurer {

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        // 注册项目上下文拦截器
        registry.addInterceptor(new ProjectContextInterceptor())
                .addPathPatterns("/**")
                .order(1); // 设置较低优先级，在权限拦截器之后执行
    }
}
