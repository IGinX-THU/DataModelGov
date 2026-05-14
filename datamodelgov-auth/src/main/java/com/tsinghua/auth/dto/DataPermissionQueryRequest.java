package com.tsinghua.auth.dto;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

@Data
@ApiModel("数据权限查询（当前用户拥有的记录）")
public class DataPermissionQueryRequest {

    @ApiModelProperty(value = "页码", example = "1")
    private Integer page;

    @ApiModelProperty(value = "每页大小", example = "10")
    private Integer pageSize;

    @ApiModelProperty(value = "表前缀关键字（包含匹配，忽略大小写）")
    private String tablePrefix;
}
