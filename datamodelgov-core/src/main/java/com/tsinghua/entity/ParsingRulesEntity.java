package com.tsinghua.entity;

import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

@Data
public class ParsingRulesEntity {
    @ApiModelProperty(value = "规则名称")
    private String name;
    @ApiModelProperty(value = "正则表达式")
    private String regexPattern;
    @ApiModelProperty(value = "创建时间（主键）")
    private Long createTime;
    @ApiModelProperty(value = "修改时间")
    private Long updateTime;
}
