package com.tsinghua.dto;

import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

@Data
public class RunTaskRequest {
    @ApiModelProperty(value = "任务名称")
    private String name;
    @ApiModelProperty(value = "创建时间")
    private Long startTime;
    @ApiModelProperty(value = "修改时间")
    private Long endTime;
    @ApiModelProperty(value = "规则id")
    private Long ruleId;
}
