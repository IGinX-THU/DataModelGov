package com.tsinghua.auth.filter;

import com.tsinghua.auth.util.JwtUtil;
import com.tsinghua.auth.service.CustomUserDetailsService;
import com.tsinghua.model.Result;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.BeansException;
import org.springframework.context.ApplicationContext;
import org.springframework.context.ApplicationContextAware;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.filter.OncePerRequestFilter;

import javax.servlet.FilterChain;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;

/**
 * JWT认证过滤器
 */
@Slf4j
@Component
public class JwtAuthenticationFilter extends OncePerRequestFilter implements ApplicationContextAware {

    private JwtUtil jwtUtil;
    private CustomUserDetailsService userDetailsService;
    private final ObjectMapper objectMapper;
    private ApplicationContext applicationContext;

    public JwtAuthenticationFilter() {
        this.objectMapper = new ObjectMapper();
    }

    @Override
    public void setApplicationContext(ApplicationContext applicationContext) throws BeansException {
        this.applicationContext = applicationContext;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, 
                                HttpServletResponse response, 
                                FilterChain filterChain) throws ServletException, IOException {
        
        try {
            // 懒加载JwtUtil和UserDetailsService
            if (jwtUtil == null) {
                if (applicationContext == null) {
                    log.warn("ApplicationContext尚未初始化，跳过JWT验证");
                    filterChain.doFilter(request, response);
                    return;
                }
                jwtUtil = applicationContext.getBean(JwtUtil.class);
                userDetailsService = applicationContext.getBean(CustomUserDetailsService.class);
            }

            // 获取请求路径
            String requestURI = request.getRequestURI();
            
            log.debug("处理请求: {}", requestURI);
            
            // 放行登录和静态资源请求
            if (isPublicPath(requestURI)) {
                log.debug("放行公共路径: {}", requestURI);
                filterChain.doFilter(request, response);
                return;
            }

            // 获取JWT token
            String token = getTokenFromRequest(request);
            
            if (StringUtils.hasText(token)) {
                // 验证token
                String username = jwtUtil.getUsernameFromToken(token);
                
                if (username != null && SecurityContextHolder.getContext().getAuthentication() == null) {
                    // 验证token有效性
                    if (jwtUtil.validateToken(token, username)) {
                        // 从数据库加载用户的完整信息（包括角色）
                        UserDetails userDetails = userDetailsService.loadUserByUsername(username);
                        
                        UsernamePasswordAuthenticationToken authentication = 
                                new UsernamePasswordAuthenticationToken(userDetails, null, userDetails.getAuthorities());
                        authentication.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));
                        
                        // 设置到Security上下文
                        SecurityContextHolder.getContext().setAuthentication(authentication);
                        
                        log.debug("用户 {} 认证成功，权限: {}", username, userDetails.getAuthorities());
                    } else {
                        log.warn("Token验证失败: {}", username);
                        handleAuthenticationFailure(response, "Token已过期或无效");
                        return;
                    }
                }
            } else {
                // 没有token，检查是否为API请求
                if (isApiRequest(requestURI)) {
                    log.warn("API请求缺少token: {}", requestURI);
                    handleAuthenticationFailure(response, "缺少认证token");
                    return;
                }
            }
            
            filterChain.doFilter(request, response);
            
        } catch (Exception e) {
            log.error("认证过滤器处理失败", e);
            // 响应已提交（控制器已开始写响应体）时不能再写错误响应，
            // 否则会导致 ERR_INCOMPLETE_CHUNKED_ENCODING（响应流被损坏）
            if (!response.isCommitted()) {
                handleAuthenticationFailure(response, "认证处理失败");
            }
        }
    }

    /**
     * 从请求中获取token
     * 优先从 Authorization header 获取；EventSource 无法设置自定义 header，
     * 因此也支持从 query 参数 token 获取（仅用于 SSE 端点）
     */
    private String getTokenFromRequest(HttpServletRequest request) {
        String bearerToken = request.getHeader("Authorization");
        if (StringUtils.hasText(bearerToken) && bearerToken.startsWith("Bearer ")) {
            return bearerToken.substring(7);
        }
        // 兼容 EventSource（SSE）场景：从 query 参数读取 token
        String queryToken = request.getParameter("token");
        if (StringUtils.hasText(queryToken)) {
            return queryToken;
        }
        return null;
    }

    /**
     * 判断是否为公共路径
     */
    private boolean isPublicPath(String requestURI) {
        boolean isPublic = requestURI.equals("/") ||
               requestURI.equals("/index.html") ||
               requestURI.equals("/login.html") ||
               requestURI.equals("/login") ||
               requestURI.equals("/error") ||
               requestURI.equals("/favicon.ico") ||
               requestURI.startsWith("/static/") ||
               requestURI.startsWith("/css/") ||
               requestURI.startsWith("/js/") ||
               requestURI.startsWith("/images/") ||
               requestURI.startsWith("/lib/") ||
               requestURI.startsWith("/components/") ||
               requestURI.startsWith("/config/") ||
               requestURI.startsWith("/api/auth/") ||
               requestURI.equals("/api/test/public") ||
               requestURI.startsWith("/doc.html") ||
               requestURI.startsWith("/swagger-ui/") ||
               requestURI.startsWith("/v3/api-docs/") ||
               requestURI.startsWith("/v2/api-docs") ||
               requestURI.startsWith("/swagger-resources/") ||
               requestURI.startsWith("/webjars/") ||
               requestURI.startsWith("/actuator/");
        
        log.debug("路径 {} 是否为公共路径: {}", requestURI, isPublic);
        return isPublic;
    }

    /**
     * 判断是否为API请求
     */
    private boolean isApiRequest(String requestURI) {
        return requestURI.startsWith("/api/");
    }

    /**
     * 处理认证失败
     */
    private void handleAuthenticationFailure(HttpServletResponse response, String message) throws IOException {
        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
        response.setContentType("application/json;charset=UTF-8");
        
        Result<?> result = Result.authError(message);
        response.getWriter().write(objectMapper.writeValueAsString(result));
    }
}
