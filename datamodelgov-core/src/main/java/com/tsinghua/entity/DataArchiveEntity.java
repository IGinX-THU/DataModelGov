package com.tsinghua.entity;

import cn.edu.tsinghua.iginx.session_v2.annotations.Field;
import cn.edu.tsinghua.iginx.session_v2.annotations.Measurement;
import io.swagger.annotations.ApiModelProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.experimental.Accessors;

/**
 * 数据档案实体
 * 用于保存数据源和导入数据的meta信息
 */
@Data
@Builder
@Accessors(chain = true)
@NoArgsConstructor
@AllArgsConstructor
@Measurement(name = "relational_system.data_archives")
public class DataArchiveEntity {
    @ApiModelProperty(value = "数据档案ID")
    @Field(timestamp = true)
    private Long id;

    @ApiModelProperty(value = "数据档案名称")
    @Field(name = "name")
    private String name;

    @ApiModelProperty(value = "类型：datasource-数据源，import-导入数据")
    @Field(name = "type")
    private String type;

    @ApiModelProperty(value = "描述信息")
    @Field(name = "description")
    private String description;

    @ApiModelProperty(value = "项目名称")
    @Field(name = "projectName")
    private String projectName;

    @ApiModelProperty(value = "创建人")
    @Field(name = "owner")
    private String owner;

    @ApiModelProperty(value = "创建时间")
    @Field(name = "createTime")
    private Long createTime;

    @ApiModelProperty(value = "配置信息（JSON格式，包含数据源配置或导入配置）")
    @Field(name = "config")
    private String config;
}
