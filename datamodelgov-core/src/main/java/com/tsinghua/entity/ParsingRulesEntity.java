package com.tsinghua.entity;

import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

@Data
public class ParsingRulesEntity {
    @ApiModelProperty(value = "规则名称")
    private String name;
    @ApiModelProperty(value = "正则表达式")
    private String regexPattern;
    @ApiModelProperty(value = "示例注释规范")
    private String example;
    @ApiModelProperty(value = "解析类型：regex-正则, inspect-Python反射, typehint-TypeHint签名")
    private String parseType;
    @ApiModelProperty(value = "适用语言：python, matlab, cpp, generic")
    private String language;
    @ApiModelProperty(value = "是否只读预置规则")
    private Boolean isReadonly;
    @ApiModelProperty(value = "Python inspect模块名")
    private String pythonModule;
    @ApiModelProperty(value = "Python inspect函数名")
    private String pythonFunction;
    @ApiModelProperty(value = "创建时间（主键）")
    private Long createTime;
    @ApiModelProperty(value = "修改时间")
    private Long updateTime;
    @ApiModelProperty(value = "创建人")
    private String owner;

}
