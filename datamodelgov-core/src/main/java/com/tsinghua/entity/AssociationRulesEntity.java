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
    @ApiModelProperty(value = "目标算法")
    private String algorithmName;
    @ApiModelProperty(value = "算法版本号")
    private String algorithmVersion;
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
    @ApiModelProperty(value = "运行命令")
    private String cmd;
    @ApiModelProperty(value = "输入数据csv文件名")
    private String inputCsvName;
    @ApiModelProperty(value = "输出结果csv文件名")
    private String outputCsvName;
}
