package com.tsinghua.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.PathMatchConfigurer;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * Web配置类，用于配置CORS跨域支持
 */
@Configuration
public class WebConfig implements WebMvcConfigurer {

    /**
     * 配置CORS跨域支持
     */
    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/**")
                .allowedOriginPatterns("*") // 允许所有域名
                .allowedMethods("GET", "POST", "PUT", "DELETE", "OPTIONS") // 允许的HTTP方法
                .allowedHeaders("*") // 允许所有请求头
                .allowCredentials(true) // 允许发送凭据（如cookies）
                .maxAge(3600); // 预检请求的缓存时间（秒）
    }

    /**
     * 配置路径匹配策略，修复Springfox与Spring Boot 2.7的兼容性问题
     */
    @Override
    public void configurePathMatch(PathMatchConfigurer configurer) {
        configurer.setUseSuffixPatternMatch(false)
                  .setUseTrailingSlashMatch(false);
    }
}
