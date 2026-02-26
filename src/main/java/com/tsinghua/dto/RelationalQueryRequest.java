package com.tsinghua.dto;

import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

@Data
public class RelationalQueryRequest {
    private int pageNum = 1;
    private int pageSize = 10;
    @ApiModelProperty(value = "表名")
    private String tableName;
}
