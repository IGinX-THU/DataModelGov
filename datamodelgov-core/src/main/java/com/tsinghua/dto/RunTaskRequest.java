package com.tsinghua.dto;

import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

import javax.validation.constraints.NotBlank;
import javax.validation.constraints.NotNull;

@Data
public class RunTaskRequest {
    @ApiModelProperty(value = "任务名称")
    @NotBlank(message = "任务名称不能为空")
    private String name;
    
    @ApiModelProperty(value = "开始时间")
    @NotNull(message = "开始时间不能为空")
    private Long startTime;
    
    @ApiModelProperty(value = "结束时间")
    @NotNull(message = "结束时间不能为空")
    private Long endTime;

    @ApiModelProperty(value = "规则名称")
    @NotBlank(message = "规则名称不能为空")
    private String ruleName;

    @ApiModelProperty(value = "规则id")
    @NotNull(message = "规则ID不能为空")
    private Long ruleId;

    @ApiModelProperty(value = "目标模型")
    private String modelName;

    @ApiModelProperty(value = "模型版本号")
    private String modelVersion;

    @ApiModelProperty(value = "结果回写路径前缀")
    private String outputTable;

}
