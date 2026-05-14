package com.tsinghua.dto;

import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

import javax.validation.constraints.NotBlank;

@Data
public class DataImportRequest {
    @ApiModelProperty(value = "目标存储路径前缀，例如：root.sg.device", required = true)
    @NotBlank(message = "目标路径不能为空")
    private String targetPath;
    @ApiModelProperty(value = "key列(从 csv 中选出列 colName 复制为 key 列，即 key 列与 colName 相同)", required = true)
    private String key;
}
