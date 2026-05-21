package com.tsinghua.entity;

import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

@Data
public class ModelMetaEntity {
    @ApiModelProperty(value = "名称")
    private String name;
    @ApiModelProperty(value = "版本号")
    private String version;
    @ApiModelProperty(value = "文件名")
    private String fileName;
    private Long fileSize;
    private Integer chunkCount;
    private String storagePath;
    private String fileMd5;
    @ApiModelProperty(value = "开发者")
    private String author;
    @ApiModelProperty(value = "场景")
    private String scene;
    @ApiModelProperty(value = "输入参数json")
    private String inputs;
    @ApiModelProperty(value = "输出参数json")
    private String outputs;
    @ApiModelProperty(value = "API列表json，每个API包含name/description/inputs/outputs")
    private String apis;
    @ApiModelProperty(value = "创建时间")
    private Long timestamp;
    @ApiModelProperty(value = "运行命令")
    private String cmd;
    @ApiModelProperty(value = "输入文件名")
    private String inputFile;
    @ApiModelProperty(value = "输出文件名")
    private String outputFile;
}
