package com.tsinghua.dto;

import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

import javax.validation.constraints.NotBlank;

/**
 * 项目导出请求参数
 * 用户可选择要导出的资源类型，默认导出全部
 */
@Data
public class ProjectExportRequest {

    @ApiModelProperty(value = "项目名称", required = true)
    @NotBlank(message = "项目名称不能为空")
    private String projectName;

    @ApiModelProperty(value = "是否导出算法文件")
    private Boolean includeAlgorithms = true;

    @ApiModelProperty(value = "是否导出模型文件")
    private Boolean includeModels = true;

    @ApiModelProperty(value = "是否导出数据CSV文件")
    private Boolean includeDataCsv = true;

    @ApiModelProperty(value = "是否导出仿真档案及执行记录")
    private Boolean includeSimulationArchives = true;

    @ApiModelProperty(value = "资源类型（用于单资源导出）")
    private String resourceType;
}
