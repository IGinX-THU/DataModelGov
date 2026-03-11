package com.tsinghua.entity;

import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

import java.util.List;

@Data
public class RunTaskEntity {
    @ApiModelProperty(value = "任务名称")
    private String name;
    @ApiModelProperty(value = "开始时间")
    private Long startTime;
    @ApiModelProperty(value = "结束时间")
    private Long endTime;
    @ApiModelProperty(value = "规则id")
    private Long ruleId;
    @ApiModelProperty(value = "输入测点")
    private String inputMeasurements;
    @ApiModelProperty(value = "输出测点")
    private String outputMeasurements;
    @ApiModelProperty(value = "状态")
    private String status;
    @ApiModelProperty(value = "创建时间")
    private Long timestamp;
    @ApiModelProperty(value = "进程ID")
    private Long processId;
    @ApiModelProperty(value = "进程运行日志")
    private String processLog;
}
