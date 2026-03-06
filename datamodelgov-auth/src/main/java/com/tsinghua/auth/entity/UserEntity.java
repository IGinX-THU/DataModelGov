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
    
    public UserEntity(String username, String password, String role) {
        this(username, password, role, true);
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
