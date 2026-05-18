package com.tsinghua.entity;

import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

import java.util.List;

/**
 * 项目实体
 * 用于管理工程项目，包含模型、算法、数据和元模型档案
 */
@Data
public class ProjectEntity {
    @ApiModelProperty(value = "项目ID")
    private String id;
    
    @ApiModelProperty(value = "项目名称")
    private String name;
    
    @ApiModelProperty(value = "项目描述")
    private String description;
    
    @ApiModelProperty(value = "项目类型")
    private String type;
    
    @ApiModelProperty(value = "关联的算法列表（JSON格式：[{name, version}]）")
    private String algorithms;
    
    @ApiModelProperty(value = "关联的模型列表（JSON格式：[{name, version}]）")
    private String models;
    
    @ApiModelProperty(value = "关联的数据源列表（JSON格式：[{dataSourcePath}]）")
    private String dataSources;
    
    @ApiModelProperty(value = "关联的仿真档案列表（JSON格式：[{archiveName}]）")
    private String simulationArchives;
    
    @ApiModelProperty(value = "创建时间")
    private Long createTime;
    
    @ApiModelProperty(value = "更新时间")
    private Long updateTime;
    
    @ApiModelProperty(value = "创建人")
    private String owner;
    
    @ApiModelProperty(value = "项目状态：active-启用，inactive-禁用")
    private Boolean status;
    
    @ApiModelProperty(value = "项目配置（JSON格式）")
    private String config;
}
