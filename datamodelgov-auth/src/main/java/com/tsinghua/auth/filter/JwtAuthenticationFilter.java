package com.tsinghua.auth.filter;

import com.tsinghua.auth.util.JwtUtil;
import com.tsinghua.model.Result;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.userdetails.User;
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
import java.util.ArrayList;

/**
 * JWT认证过滤器
 */
@Slf4j
@Component
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private final JwtUtil jwtUtil;
    private final ObjectMapper objectMapper;

    public JwtAuthenticationFilter(JwtUtil jwtUtil, ObjectMapper objectMapper) {
        this.jwtUtil = jwtUtil;
        this.objectMapper = objectMapper;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, 
                                HttpServletResponse response, 
                                FilterChain filterChain) throws ServletException, IOException {
        
        try {
            // 获取请求路径
            String requestURI = request.getRequestURI();
            
            // 放行登录和静态资源请求
            if (isPublicPath(requestURI)) {
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
                        // 创建认证对象
                        UserDetails userDetails = User.builder()
                                .username(username)
                                .password("")
                                .authorities(new ArrayList<>())
                                .build();
                        
                        UsernamePasswordAuthenticationToken authentication = 
                                new UsernamePasswordAuthenticationToken(userDetails, null, userDetails.getAuthorities());
                        authentication.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));
                        
                        // 设置到Security上下文
                        SecurityContextHolder.getContext().setAuthentication(authentication);
                        
                        log.debug("用户 {} 认证成功", username);
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
            handleAuthenticationFailure(response, "认证处理失败");
        }
    }

    /**
     * 从请求中获取token
     */
    private String getTokenFromRequest(HttpServletRequest request) {
        String bearerToken = request.getHeader("Authorization");
        if (StringUtils.hasText(bearerToken) && bearerToken.startsWith("Bearer ")) {
            return bearerToken.substring(7);
        }
        return null;
    }

    /**
     * 判断是否为公共路径
     */
    private boolean isPublicPath(String requestURI) {
        return requestURI.equals("/api/auth/login") ||
               requestURI.equals("/api/auth/refresh") ||
               requestURI.equals("/login.html") ||
               requestURI.startsWith("/static/") ||
               requestURI.startsWith("/css/") ||
               requestURI.startsWith("/js/") ||
               requestURI.startsWith("/images/") ||
               requestURI.equals("/favicon.ico");
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
