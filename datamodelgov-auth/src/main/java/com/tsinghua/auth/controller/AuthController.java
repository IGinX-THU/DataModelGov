package com.tsinghua.auth.controller;

import com.tsinghua.auth.util.JwtUtil;
import com.tsinghua.model.Result;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.HashMap;
import java.util.Map;

/**
 * 认证控制器
 */
@Slf4j
@RestController
@RequestMapping("/api/auth")
public class AuthController {

    @Autowired
    private AuthenticationManager authenticationManager;

    @Autowired
    private JwtUtil jwtUtil;

    /**
     * 用户登录
     */
    @PostMapping("/login")
    public Result<?> login(@RequestBody Map<String, String> loginRequest, HttpServletRequest request) {
        try {
            String username = loginRequest.get("username");
            String password = loginRequest.get("password");

            if (username == null || password == null) {
                return Result.error("用户名和密码不能为空");
            }

            // 进行认证
            Authentication authentication = authenticationManager.authenticate(
                    new UsernamePasswordAuthenticationToken(username, password)
            );

            SecurityContextHolder.getContext().setAuthentication(authentication);

            // 生成token
            String token = jwtUtil.generateToken(username);
            String refreshToken = jwtUtil.generateRefreshToken(username);

            Map<String, Object> tokenData = new HashMap<>();
            tokenData.put("token", token);
            tokenData.put("refreshToken", refreshToken);
            tokenData.put("tokenType", "Bearer");
            tokenData.put("username", username);

            log.info("用户 {} 登录成功", username);

            return Result.success("登录成功", tokenData);

        } catch (AuthenticationException e) {
            log.warn("用户登录失败: {}", e.getMessage());
            return Result.error("用户名或密码错误");
        } catch (Exception e) {
            log.error("登录处理异常", e);
            return Result.error("登录失败，请稍后重试");
        }
    }

    /**
     * 刷新token
     */
    @PostMapping("/refresh")
    public Result<?> refreshToken(@RequestBody Map<String, String> refreshRequest) {
        try {
            String refreshToken = refreshRequest.get("refreshToken");
            
            if (refreshToken == null) {
                return Result.error("刷新token不能为空");
            }

            // 验证刷新token
            if (!jwtUtil.isRefreshToken(refreshToken)) {
                return Result.error("无效的刷新token");
            }

            if (jwtUtil.isTokenExpired(refreshToken)) {
                return Result.error("刷新token已过期，请重新登录");
            }

            String username = jwtUtil.getUsernameFromToken(refreshToken);
            String newToken = jwtUtil.generateToken(username);
            String newRefreshToken = jwtUtil.generateRefreshToken(username);

            Map<String, Object> tokenData = new HashMap<>();
            tokenData.put("token", newToken);
            tokenData.put("refreshToken", newRefreshToken);
            tokenData.put("tokenType", "Bearer");
            tokenData.put("username", username);

            log.info("用户 {} 刷新token成功", username);

            return Result.success("刷新成功", tokenData);

        } catch (Exception e) {
            log.error("刷新token异常", e);
            return Result.error("刷新token失败");
        }
    }

    /**
     * 验证token
     */
    @GetMapping("/verify")
    public Result<?> verifyToken(HttpServletRequest request) {
        try {
            String token = getTokenFromRequest(request);
            
            if (token == null) {
                return Result.error("缺少认证token");
            }

            String username = jwtUtil.getUsernameFromToken(token);
            
            if (username == null) {
                return Result.error("无效的token");
            }

            if (jwtUtil.isTokenExpired(token)) {
                return Result.error("token已过期");
            }

            Map<String, Object> userData = new HashMap<>();
            userData.put("username", username);
            userData.put("valid", true);

            return Result.success("token有效", userData);

        } catch (Exception e) {
            log.error("验证token异常", e);
            return Result.error("验证token失败");
        }
    }

    /**
     * 用户登出
     */
    @PostMapping("/logout")
    public Result<?> logout() {
        try {
            // 清除Security上下文
            SecurityContextHolder.clearContext();
            return Result.success("登出成功");
        } catch (Exception e) {
            log.error("登出异常", e);
            return Result.error("登出失败");
        }
    }

    /**
     * 获取当前用户信息
     */
    @GetMapping("/user")
    public Result<?> getCurrentUser() {
        try {
            Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
            
            if (authentication == null || !authentication.isAuthenticated()) {
                return Result.error("未认证");
            }

            String username = authentication.getName();
            
            Map<String, Object> userData = new HashMap<>();
            userData.put("username", username);
            userData.put("authenticated", true);

            return Result.success("获取用户信息成功", userData);

        } catch (Exception e) {
            log.error("获取用户信息异常", e);
            return Result.error("获取用户信息失败");
        }
    }

    /**
     * 从请求中获取token
     */
    private String getTokenFromRequest(HttpServletRequest request) {
        String bearerToken = request.getHeader("Authorization");
        if (bearerToken != null && bearerToken.startsWith("Bearer ")) {
            return bearerToken.substring(7);
        }
        return null;
    }
}
