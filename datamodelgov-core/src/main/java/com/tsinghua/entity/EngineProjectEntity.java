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
 * 工作台项目元数据(发动机项目)。
 * 与旧版 programs_meta/project 一致:元数据入 IginX relational_system,
 * 列表分页查询与用户隔离(owner SQL 条件)由 SQL 完成;任务/模型大文件仍在本地文件系统。
 */
@Data
@Builder
@Accessors(chain = true)
@NoArgsConstructor
@AllArgsConstructor
@Measurement(name = "relational_system.engine_projects")
public class EngineProjectEntity {

    @ApiModelProperty(value = "项目ID(时间戳)")
    @Field(timestamp = true)
    private Long id;

    @ApiModelProperty(value = "项目名称")
    @Field(name = "name")
    private String name;

    @ApiModelProperty(value = "项目类型:个性化自适应建模 | 系统联合仿真")
    @Field(name = "type")
    private String type;

    @ApiModelProperty(value = "发动机标识")
    @Field(name = "engineId")
    private String engineId;

    @ApiModelProperty(value = "保存位置(用户输入)")
    @Field(name = "location")
    private String location;

    @ApiModelProperty(value = "解析后的物理工作目录")
    @Field(name = "workdir")
    private String workdir;

    @ApiModelProperty(value = "描述")
    @Field(name = "desc")
    private String desc;

    @ApiModelProperty(value = "创建人")
    @Field(name = "owner")
    private String owner;

    @ApiModelProperty(value = "创建时间")
    @Field(name = "createTime")
    private Long createTime;
}
