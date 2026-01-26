package com.tsinghua.dto;


import lombok.Data;

import javax.validation.constraints.NotBlank;
import javax.validation.constraints.NotNull;

/**
 * 数据源注册DTO
 */
@Data
public class DataSourceDTO {
    @NotBlank(message = "数据源别名不能为空")
    private String alias;          // 数据源别名（唯一）

    @NotBlank(message = "数据源类型不能为空")
    private String type;           // 类型：IoTDB、达梦、PostgreSQL等

    @NotBlank(message = "IP地址不能为空")
    private String ip;             // 数据源IP

    @NotNull(message = "端口号不能为空")
    private Integer port;              // 数据源端口

    private String username;       // 登录用户名

    private String password;       // 登录密码

    private String extraParams;    // 额外参数（JSON格式）
}