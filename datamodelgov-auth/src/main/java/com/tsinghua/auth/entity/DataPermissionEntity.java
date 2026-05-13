package com.tsinghua.auth.entity;

import cn.edu.tsinghua.iginx.session_v2.annotations.Field;
import cn.edu.tsinghua.iginx.session_v2.annotations.Measurement;
import lombok.Data;
import lombok.Builder;
import lombok.AllArgsConstructor;
import lombok.NoArgsConstructor;
import lombok.experimental.Accessors;

/**
 * 数据权限实体
 * 基于时间戳主键的Entity表权限控制
 */
@Data
@Builder
@Accessors(chain = true)
@NoArgsConstructor
@AllArgsConstructor
@Measurement(name = "relational_system.data_permissions")
public class DataPermissionEntity {
    
    /**
     * 主键：时间戳
     */
    @Field(timestamp = true)
    private Long id;
    
    /**
     * 用户名
     */
    @Field(name = "owner")
    private String owner;
    
    /**
     * 表前缀（如 relational_system.models_meta）
     */
    @Field(name = "tablePrefix")
    private String tablePrefix;
    
    /**
     * 时间戳集合（逗号分隔的字符串，存储可访问的主键时间戳）
     */
    @Field(name = "timestampSet")
    private String timestampSet;

    /**
     * 是否公开（true表示所有用户可见）
     */
    @Field(name = "isPublic")
    private boolean isPublic;

    /**
     * 可见用户列表（逗号分隔的用户名）
     * 当isPublic=false时，只有列表中的用户可见
     * 空值表示仅创建者可见
     */
    @Field(name = "visibleUsers")
    private String visibleUsers;

    @Field(name = "createTime")
    private Long createTime;

}
