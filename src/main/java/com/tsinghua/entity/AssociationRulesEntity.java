package com.tsinghua.entity;

import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

@Data
public class AssociationRulesEntity {
    @ApiModelProperty(value = "规则名称")
    private String name;
    @ApiModelProperty(value = "规则描述")
    private String description;
    @ApiModelProperty(value = "数据源")
    private String tableName;
    @ApiModelProperty(value = "目标模型")
    private String modelName;
    @ApiModelProperty(value = "模型版本号")
    private String modelVersion;
    @ApiModelProperty(value = "状态")
    private Boolean status;
    @ApiModelProperty(value = "创建时间")
    private Long createTime;
    @ApiModelProperty(value = "修改时间")
    private Long updateTime;
    @ApiModelProperty(value = "输入参数json")
    private String inputsBind;
    @ApiModelProperty(value = "输出参数json")
    private String outputsBind;
}
