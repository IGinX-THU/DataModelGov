package com.tsinghua.auth.service;

import com.tsinghua.auth.dao.UserDao;
import com.tsinghua.auth.entity.UserEntity;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.stereotype.Service;

import java.util.Collections;

/**
 * 自定义用户详情服务
 * 基于DAO层获取用户信息，而不是内存
 */
@Service
public class CustomUserDetailsService implements UserDetailsService {

    @Autowired
    private UserDao userDao;

    @Override
    public UserDetails loadUserByUsername(String username) throws UsernameNotFoundException {
        try {
            // 从数据库查询用户
            UserEntity user = userDao.getUserByUsername(username);
            
            if (user == null) {
                throw new UsernameNotFoundException("用户不存在: " + username);
            }
            
            // 检查用户是否启用
            if (!user.isEnabled()) {
                throw new UsernameNotFoundException("用户已被禁用: " + username);
            }
            
            // 创建权限列表（这里简化处理，实际应该从用户角色表获取）
            SimpleGrantedAuthority authority = new SimpleGrantedAuthority("ROLE_USER");
            
            // 返回UserDetails对象
            return new User(
                user.getUsername(),
                user.getPassword(),
                user.isEnabled(),
                true,  // accountNonExpired
                true,  // credentialsNonExpired
                true,  // accountNonLocked
                Collections.singletonList(authority)
            );
            
        } catch (Exception e) {
            throw new UsernameNotFoundException("加载用户信息失败: " + username, e);
        }
    }
}
