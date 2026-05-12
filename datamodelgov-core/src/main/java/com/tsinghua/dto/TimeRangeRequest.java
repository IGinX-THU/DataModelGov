package com.tsinghua.dto;

import io.swagger.annotations.ApiModel;
import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

import java.util.List;

@Data
@ApiModel("时间范围查询请求")
public class TimeRangeRequest {
    
    @ApiModelProperty(value = "数据表名", required = true)
    private String tableName;
    
    @ApiModelProperty(value = "输入参数", required = false)
    private List<InputBindDto> inputsBind;
}
