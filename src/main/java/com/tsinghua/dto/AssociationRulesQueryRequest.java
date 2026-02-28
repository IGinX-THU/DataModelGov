package com.tsinghua.dto;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

@Data
@ApiModel("关联规则查询请求")
public class AssociationRulesQueryRequest {
    
    @ApiModelProperty(value = "页码", example = "1")
    private Integer pageNum;
    
    @ApiModelProperty(value = "每页大小", example = "6")
    private Integer pageSize;
    
    @ApiModelProperty(value = "规则名称（模糊查询）", example = "规则名称")
    private String name;
    
    @ApiModelProperty(value = "状态（active/inactive）", example = "active")
    private String status;
}
