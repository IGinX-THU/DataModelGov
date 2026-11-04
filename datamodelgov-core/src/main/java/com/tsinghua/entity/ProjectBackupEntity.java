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
 * 项目备份记录(项目工作目录打包下载时写入)。
 * ZIP 包体落本地 program/backup/<pid>/<项目名>.zip(固定文件名,每次覆盖,不累积),
 * 记录 id 固定为项目ID → 每次下载覆盖同一条记录,无历史冗余行;
 * 与 engine_projects 同库 relational_system,只存最新一份备份的元数据。
 */
@Data
@Builder
@Accessors(chain = true)
@NoArgsConstructor
@AllArgsConstructor
@Measurement(name = "relational_system.project_backups")
public class ProjectBackupEntity {

    @ApiModelProperty(value = "备份ID(时间戳)")
    @Field(timestamp = true)
    private Long id;

    @ApiModelProperty(value = "项目ID")
    @Field(name = "projectId")
    private String projectId;

    @ApiModelProperty(value = "项目名称")
    @Field(name = "projectName")
    private String projectName;

    @ApiModelProperty(value = "创建人(下载操作人)")
    @Field(name = "owner")
    private String owner;

    @ApiModelProperty(value = "ZIP 文件名")
    @Field(name = "zipName")
    private String zipName;

    @ApiModelProperty(value = "ZIP 物理路径(备份副本)")
    @Field(name = "zipPath")
    private String zipPath;

    @ApiModelProperty(value = "ZIP 大小(字节)")
    @Field(name = "sizeBytes")
    private Long sizeBytes;

    @ApiModelProperty(value = "打包文件数")
    @Field(name = "fileCount")
    private Long fileCount;

    @ApiModelProperty(value = "打包目录数")
    @Field(name = "dirCount")
    private Long dirCount;

    @ApiModelProperty(value = "备份时间")
    @Field(name = "backupTime")
    private Long backupTime;
}
