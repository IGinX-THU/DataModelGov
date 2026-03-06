package com.tsinghua.auth.entity;

import com.tsinghua.auth.enums.Permission;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.AllArgsConstructor;

import java.util.Set;

/**
 * 角色实体类 - 精简版，只保留必需字段
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class RoleEntity {
    
    private String role;
    private Set<Permission> permissions;
}
