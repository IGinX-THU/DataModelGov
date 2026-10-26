package com.tsinghua.entity;

import cn.edu.tsinghua.iginx.session_v2.annotations.Field;
import cn.edu.tsinghua.iginx.session_v2.annotations.Measurement;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.experimental.Accessors;

/**
 * 项目文件库索引(数据/模型两类)。与 engine_projects 同模式:索引入 IginX relational_system,
 * SQL 分页与用户隔离(owner 条件)由 SQL 完成;文件本体在项目工作目录 files/{category}/ 下,
 * 另有 IginX 分块备份(FileBackupService),本地丢失时恢复。
 */
@Data
@Builder
@Accessors(chain = true)
@NoArgsConstructor
@AllArgsConstructor
@Measurement(name = "relational_system.file_library")
public class FileLibraryEntity {

    @Field(timestamp = true)
    private Long id;

    @Field(name = "projectId")
    private String projectId;

    @Field(name = "category")
    private String category;

    @Field(name = "kind")
    private String kind;

    @Field(name = "name")
    private String name;

    @Field(name = "path")
    private String path;

    @Field(name = "size")
    private Long size;

    @Field(name = "ext")
    private String ext;

    @Field(name = "sha256")
    private String sha256;

    @Field(name = "fileMd5")
    private String fileMd5;

    @Field(name = "chunkCount")
    private Integer chunkCount;

    @Field(name = "backupState")
    private String backupState;

    @Field(name = "refId")
    private String refId;

    @Field(name = "owner")
    private String owner;

    @Field(name = "createdAt")
    private Long createdAt;
}
