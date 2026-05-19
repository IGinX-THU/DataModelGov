package com.tsinghua.entity;

import cn.edu.tsinghua.iginx.session_v2.annotations.Field;
import cn.edu.tsinghua.iginx.session_v2.annotations.Measurement;
import io.swagger.annotations.ApiModelProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.experimental.Accessors;

import java.util.List;

/**
 * 项目实体
 * 用于管理工程项目，包含模型、算法、数据和元模型档案
 */
@Data
@Builder
@Accessors(chain = true)
@NoArgsConstructor
@AllArgsConstructor
@Measurement(name = "relational_system.project")
public class ProjectEntity {
    @ApiModelProperty(value = "项目ID")
    @Field(timestamp = true)
    private Long id;
    
    @ApiModelProperty(value = "项目名称")
    @Field(name = "name")
    private String name;
    
    @ApiModelProperty(value = "项目描述")
    @Field(name = "desc")
    private String desc;

    @ApiModelProperty(value = "关联的算法列表（格式：name_version, name_version2, ... ）")
    @Field(name = "algorithms")
    private String algorithms;
    
    @ApiModelProperty(value = "关联的模型列表（格式：model1, model2, ... ）")
    @Field(name = "models")
    private String models;
    
    @ApiModelProperty(value = "关联的数据源列表（格式：dataSourcePath1, dataSourcePath2, ... ）")
    @Field(name = "datas")
    private String datas;

    @ApiModelProperty(value = "创建时间")
    @Field(name = "createTime")
    private Long createTime;

    @ApiModelProperty(value = "创建人")
    @Field(name = "owner")
    private String owner;

}
