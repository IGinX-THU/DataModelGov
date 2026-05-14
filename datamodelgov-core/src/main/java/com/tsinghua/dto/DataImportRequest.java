package com.tsinghua.dto;

import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

import javax.validation.constraints.NotBlank;

@Data
public class DataImportRequest {
    @ApiModelProperty(value = "目标存储路径前缀，例如：root.sg.device", required = true)
    @NotBlank(message = "目标路径不能为空")
    private String targetPath;
    @ApiModelProperty(value = "key列：从 CSV 中选出的列名，导入时作为 key（对应 LOAD DATA set key）。不传或留空则使用默认导入行为", required = false)
    private String key;
}
