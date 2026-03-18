package com.tsinghua.dto;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

@Data
@ApiModel("运行任务查询请求")
public class RunTaskQueryRequest {
    
    @ApiModelProperty(value = "页码", example = "1")
    private Integer pageNum;
    
    @ApiModelProperty(value = "每页大小", example = "10")
    private Integer pageSize;
    
    @ApiModelProperty(value = "任务名称（模糊查询）", example = "数据质量分析")
    private String name;
    
    @ApiModelProperty(value = "运行状态（running/stopped/pending/success/failed）", example = "running")
    private String status;
    
    @ApiModelProperty(value = "规则ID", example = "123456789")
    private Long ruleId;
    
    @ApiModelProperty(value = "开始时间")
    private Long startTime;
    
    @ApiModelProperty(value = "结束时间")
    private Long endTime;
}
