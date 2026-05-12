package com.tsinghua.dto;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

@Data
@ApiModel("时间范围查询响应")
public class TimeRangeResponse {
    
    @ApiModelProperty(value = "最小时间戳")
    private Long minKey;
    
    @ApiModelProperty(value = "最大时间戳")
    private Long maxKey;

}
