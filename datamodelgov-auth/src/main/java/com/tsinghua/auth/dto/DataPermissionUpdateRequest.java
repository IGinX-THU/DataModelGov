package com.tsinghua.auth.dto;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

import javax.validation.constraints.NotNull;

@Data
@ApiModel("更新当前用户的数据权限可见性")
public class DataPermissionUpdateRequest {

    @NotNull(message = "记录主键不能为空")
    @ApiModelProperty(value = "记录主键（与创建时间/ id 一致）", required = true)
    private Long id;

    @ApiModelProperty(value = "是否对所有用户公开")
    private Boolean isPublic;

    @ApiModelProperty(value = "可见用户名列表，逗号分隔；非公开时生效")
    private String visibleUsers;
}
