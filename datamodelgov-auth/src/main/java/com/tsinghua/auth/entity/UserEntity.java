package com.tsinghua.auth.entity;

import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.AllArgsConstructor;

/**
 * 用户实体类 - 精简版，只保留Spring Security必需字段
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class UserEntity {
    
    private String username;
    private String password;
    private String role;
    private boolean enabled;
    private Long timestamp;
    
    public UserEntity(String username, String password, String role, Long timestamp) {
        this.username = username;
        this.password = password;
        this.role = role;
        this.enabled = true;
        this.timestamp = timestamp;
    }
    
    /**
     * 转换为Spring Security的UserDetails
     */
    public org.springframework.security.core.userdetails.User toUserDetails() {
        return new org.springframework.security.core.userdetails.User(
            username,
            password, // 使用已加密的密码
            enabled,
            true, // accountNonExpired
            true, // credentialsNonExpired
            true, // accountNonLocked
            java.util.Collections.singletonList(
                new org.springframework.security.core.authority.SimpleGrantedAuthority("ROLE_" + role)
            )
        );
    }
}
