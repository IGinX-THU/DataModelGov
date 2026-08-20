package com.tsinghua.entity;

import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

@Data
public class ProgramEntity {
    @ApiModelProperty(value = "程序名称")
    private String name;

    @ApiModelProperty(value = "版本")
    private String version;

    @ApiModelProperty(value = "描述")
    private String description;

    @ApiModelProperty(value = "程序目录名")
    private String programDir;

    @ApiModelProperty(value = "配置文件JSON")
    private String configJson;

    @ApiModelProperty(value = "信号采集脚本内容（MATLAB .m 源码）")
    private String setupScript;

    @ApiModelProperty(value = "状态：UNCONFIGURED/READY")
    private String status;

    @ApiModelProperty(value = "最近错误信息")
    private String lastError;

    @ApiModelProperty(value = "最近运行时间")
    private Long lastRunTime;

    @ApiModelProperty(value = "最近一次结果CSV路径")
    private String lastResultCsv;

    @ApiModelProperty(value = "最近一次运行日志路径")
    private String lastLogPath;

    @ApiModelProperty(value = "最近一次结果目录路径")
    private String lastResultDir;

    @ApiModelProperty(value = "原始压缩包文件名")
    private String fileName;

    @ApiModelProperty(value = "压缩包大小")
    private Long fileSize;

    @ApiModelProperty(value = "压缩包分块数")
    private Integer chunkCount;

    @ApiModelProperty(value = "压缩包MD5")
    private String fileMd5;

    @ApiModelProperty(value = "IGinX 存储路径")
    private String storagePath;

    @ApiModelProperty(value = "开发者")
    private String author;

    @ApiModelProperty(value = "项目名称")
    private String projectName;

    @ApiModelProperty(value = "创建时间戳")
    private Long timestamp;
}
