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
    private long fileSize;
    private int chunkCount;
    private String storagePath;
    private String fileMd5;

    private String author;
    private String scene;
    private String inputs;
    private String outputs;

}
