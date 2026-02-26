package com.tsinghua.dto;

import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

@Data
public class ModelMetaDto {
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
    @ApiModelProperty(value = "创建时间")
    private Long timestamp;

}
