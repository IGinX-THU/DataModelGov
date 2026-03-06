package com.tsinghua.auth.config;

import com.tsinghua.auth.filter.JwtAuthenticationFilter;
import com.tsinghua.auth.service.RolePermissionService;
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
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

/**
 * Spring Security配置
 * 支持JWT认证和前后端分离
 */
@Configuration
@EnableWebSecurity
@EnableGlobalMethodSecurity(prePostEnabled = true)
public class SecurityConfig extends WebSecurityConfigurerAdapter {

    @Autowired
    private JwtAuthenticationFilter jwtAuthenticationFilter;
    
    @Autowired
    private RolePermissionService rolePermissionService;

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
        // 设置密码编码器到RolePermissionService
        rolePermissionService.setPasswordEncoder(passwordEncoder());
        // 使用RolePermissionService来获取用户信息，实际项目中应该从数据库读取
        return new InMemoryUserDetailsManager(rolePermissionService.getAllUsers());
    }

    @Override
    protected void configure(AuthenticationManagerBuilder auth) throws Exception {
        auth.userDetailsService(userDetailsService()).passwordEncoder(passwordEncoder());
    }

    @Override
    protected void configure(HttpSecurity http) throws Exception {
        http
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
