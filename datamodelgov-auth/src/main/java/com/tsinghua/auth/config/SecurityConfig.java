package com.tsinghua.auth.config;

import com.tsinghua.auth.filter.JwtAuthenticationFilter;
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
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
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

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    @Bean
    @Override
    public AuthenticationManager authenticationManagerBean() throws Exception {
        return super.authenticationManagerBean();
    }

    @Bean
    public UserDetailsService userDetailsService() {
        // 这里使用内存用户存储，实际项目中应该从数据库读取
        UserDetails admin = User.builder()
                .username("admin")
                .password(passwordEncoder().encode("admin123"))
                .roles("ADMIN", "USER")
                .build();

        UserDetails user = User.builder()
                .username("user")
                .password(passwordEncoder().encode("user123"))
                .roles("USER")
                .build();

        return new InMemoryUserDetailsManager(admin, user);
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
            
            // 配置授权规则
            .authorizeRequests()
                // 放行server模块的静态资源
                .antMatchers("/", "/index.html").permitAll()
                .antMatchers("/static/**", "/css/**", "/js/**", "/images/**", "/lib/**", "/components/**", "/config/**").permitAll()
                // 放行登录页面和错误页面
                .antMatchers("/login.html", "/login", "/error", "/favicon.ico").permitAll()
                // 放行认证相关API
                .antMatchers("/api/auth/**").permitAll()
                // 放行公开测试API
                .antMatchers("/api/test/public").permitAll()
                // 受保护的测试API需要认证
                .antMatchers("/api/test/protected").authenticated()
                // 管理员测试API需要管理员权限
                .antMatchers("/api/test/admin").hasRole("ADMIN")
                // 放行API文档相关
                .antMatchers("/doc.html", "/swagger-ui/**", "/v3/api-docs/**", "/v2/api-docs", "/swagger-resources/**", "/webjars/**").permitAll()
                // 放行健康检查
                .antMatchers("/actuator/health", "/actuator/info").permitAll()
                // 管理员接口
                .antMatchers("/api/admin/**", "/admin/**").hasRole("ADMIN")
                // core模块的API接口需要认证
                .antMatchers("/api/generation/**", "/api/association-rules/**", "/api/data-sources/**", "/api/data-tables/**", "/api/model-files/**").authenticated()
                // 其他所有接口都需要认证
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
