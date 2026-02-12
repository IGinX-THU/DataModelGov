package com.tsinghua.dto;

import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

import javax.validation.constraints.NotNull;
import java.util.List;

@Data
public class DataQueryRequest {
    @ApiModelProperty(value = "测点")
    @NotNull(message = "测点不能为空")
    private List<String> paths;
    @ApiModelProperty(value = "开始时间")
    private Long startTime;
    @ApiModelProperty(value = "结束时间")
    private Long endTime;
    /**
     *     MAX(0),
     *     MIN(1),
     *     SUM(2),
     *     COUNT(3),
     *     AVG(4),
     *     FIRST_VALUE(5),
     *     LAST_VALUE(6),
     *     FIRST(7),
     */
    @ApiModelProperty(value = "聚合函数")
    private Integer aggregateType;
}
