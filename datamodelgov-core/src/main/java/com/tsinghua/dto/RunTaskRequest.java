package com.tsinghua.dto;

import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

import javax.validation.constraints.NotNull;

@Data
public class RunTaskRequest {
    @ApiModelProperty(value = "任务名称")
    private String name;
    
    @ApiModelProperty(value = "开始时间")
    @NotNull(message = "开始时间不能为空")
    private Long startTime;
    
    @ApiModelProperty(value = "结束时间")
    @NotNull(message = "结束时间不能为空")
    private Long endTime;
    
    @ApiModelProperty(value = "规则id")
    @NotNull(message = "规则ID不能为空")
    private Long ruleId;
}
