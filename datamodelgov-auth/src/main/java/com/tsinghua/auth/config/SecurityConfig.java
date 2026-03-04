package com.tsinghua.auth.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.security.web.SecurityFilterChain;

/**
 * Spring Security配置类
 * 为core模块的controller接口添加登录认证，同时放行server模块的静态资源
 */
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    @Bean
    public UserDetailsService userDetailsService(PasswordEncoder passwordEncoder) {
        UserDetails admin = User.builder()
                .username("admin")
                .password(passwordEncoder.encode("admin123"))
                .roles("ADMIN", "USER")
                .build();

        UserDetails user = User.builder()
                .username("user")
                .password(passwordEncoder.encode("user123"))
                .roles("USER")
                .build();

        return new InMemoryUserDetailsManager(admin, user);
    }

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            .authorizeRequests()
                // 放行server模块的静态资源
                .antMatchers("/", "/index.html").permitAll()
                .antMatchers("/static/**", "/css/**", "/js/**", "/images/**", "/lib/**", "/components/**", "/config/**").permitAll()
                // 放行登录页面和错误页面
                .antMatchers("/login", "/error", "/favicon.ico").permitAll()
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
            // 启用HTTP基本认证
            .httpBasic()
            .and()
            // 启用表单登录
            .formLogin()
                .loginPage("/login")
                .defaultSuccessUrl("/", true)
                .failureUrl("/login?error=true")
                .permitAll()
            .and()
            // 配置登出
            .logout()
                .logoutSuccessUrl("/login")
                .permitAll()
            .and()
            // 禁用CSRF（对于API开发）
            .csrf().disable()
            // 启用CORS
            .cors();

        return http.build();
    }
}
