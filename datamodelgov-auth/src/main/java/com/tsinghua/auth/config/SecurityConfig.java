package com.tsinghua.auth.config;

import com.tsinghua.auth.filter.JwtAuthenticationFilter;
import com.tsinghua.auth.service.CustomUserDetailsService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.config.annotation.authentication.builders.AuthenticationManagerBuilder;
import org.springframework.security.config.annotation.method.configuration.EnableGlobalMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configuration.WebSecurityConfigurerAdapter;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

/**
 * Spring Security配置
 * 支持JWT认证和前后端分离
 * 使用基于DAO层的用户认证
 */
@Configuration
@EnableWebSecurity
@EnableGlobalMethodSecurity(prePostEnabled = true)
public class SecurityConfig extends WebSecurityConfigurerAdapter {

    @Autowired
    private JwtAuthenticationFilter jwtAuthenticationFilter;
    
    @Autowired
    private CustomUserDetailsService customUserDetailsService;

    @Bean
    public PasswordEncoder passwordEncoder() {
        // 使用BCryptPasswordEncoder加密密码
        return new org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder();
    }

    @Bean
    @Override
    public AuthenticationManager authenticationManagerBean() throws Exception {
        return super.authenticationManagerBean();
    }

    @Bean
    public UserDetailsService userDetailsService() {
        // 使用基于DAO层的自定义用户详情服务
        return customUserDetailsService;
    }

    /**
     * CORS配置Bean
     */
    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration configuration = new CorsConfiguration();
        
        // 允许所有源
        configuration.addAllowedOriginPattern("*");
        
        // 允许所有HTTP方法
        configuration.addAllowedMethod("GET");
        configuration.addAllowedMethod("POST");
        configuration.addAllowedMethod("PUT");
        configuration.addAllowedMethod("DELETE");
        configuration.addAllowedMethod("OPTIONS");
        configuration.addAllowedMethod("PATCH");
        
        // 允许所有请求头
        configuration.addAllowedHeader("*");
        
        // 允许发送凭据
        configuration.setAllowCredentials(true);
        
        // 预检请求缓存时间
        configuration.setMaxAge(3600L);
        
        // 应用到所有路径
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", configuration);
        
        return source;
    }

    @Override
    protected void configure(AuthenticationManagerBuilder auth) throws Exception {
        auth.userDetailsService(userDetailsService()).passwordEncoder(passwordEncoder());
    }

    @Override
    protected void configure(HttpSecurity http) throws Exception {
        http
            // 启用CORS
            .cors().and()
            
            // 禁用CSRF
            .csrf().disable()
            
            // 禁用session，使用JWT
            .sessionManagement()
                .sessionCreationPolicy(SessionCreationPolicy.STATELESS)
                .and()
            
            // 配置授权规则 - 只做基础认证控制，所有权限由拦截器处理
            .authorizeRequests()
                // 放行server模块的静态资源
                .antMatchers("/", "/index.html").permitAll()
                .antMatchers("/static/**", "/css/**", "/js/**", "/images/**", "/lib/**", "/components/**", "/config/**").permitAll()
                // 放行登录页面和错误页面
                .antMatchers("/login.html", "/login", "/error", "/favicon.ico").permitAll()
                // 放行认证相关API
                .antMatchers("/api/auth/**").permitAll()
                // 放行RBAC测试API（用于测试权限系统）
                .antMatchers("/api/rbac/**").permitAll()
                // 放行公开测试API
                .antMatchers("/api/test/public").permitAll()
                // 放行API文档相关
                .antMatchers("/doc.html", "/swagger-ui/**", "/v3/api-docs/**", "/v2/api-docs", "/swagger-resources/**", "/webjars/**").permitAll()
                // 放行健康检查
                .antMatchers("/actuator/health", "/actuator/info").permitAll()
                // 所有业务API都需要认证（具体权限由拦截器控制）
                .antMatchers("/api/**").authenticated()
                // 其他所有请求都需要认证
                .anyRequest().authenticated()
                .and()
            
            // 配置异常处理
            .exceptionHandling()
                .authenticationEntryPoint((request, response, authException) -> {
                    response.setStatus(401);
                    response.setContentType("application/json;charset=UTF-8");
                    
                    String errorMessage = "未认证，请先登录";
                    if (authException.getMessage() != null) {
                        errorMessage = authException.getMessage();
                    }
                    
                    // 对于API请求返回JSON，对于页面请求重定向到登录页
                    String requestURI = request.getRequestURI();
                    if (requestURI.startsWith("/api/")) {
                        response.getWriter().write(
                            "{\"success\":false,\"message\":\"" + errorMessage + "\",\"code\":401}"
                        );
                    } else {
                        response.sendRedirect("/login.html");
                    }
                })
                .and()
            
            // 添加JWT过滤器
            .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class);
    }
}
