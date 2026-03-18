package com.tsinghua.auth.dto;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

@Data
@ApiModel("用户查询请求")
public class UserQueryRequest {
    
    @ApiModelProperty(value = "页码", example = "1")
    private Integer page;
    
    @ApiModelProperty(value = "每页大小", example = "10")
    private Integer pageSize;
    
    @ApiModelProperty(value = "用户名（模糊查询）", example = "admin")
    private String username;
    
    @ApiModelProperty(value = "角色", example = "ADMIN")
    private String role;
    
    @ApiModelProperty(value = "状态", example = "true")
    private String enabled;
}
