package com.tsinghua.dto;

import io.swagger.annotations.ApiModelProperty;
import lombok.Data;

import java.util.List;

@Data
public class RelationalQueryRequest {
    private int pageNum = 1;
    private int pageSize = 10;
    
    @ApiModelProperty(value = "表名")
    private String tableName;
    
    @ApiModelProperty(value = "筛选条件列表")
    private List<FilterCondition> filters;
    
    @ApiModelProperty(value = "排序字段")
    private String sortField;
    
    @ApiModelProperty(value = "排序方向: ASC, DESC")
    private String sortDirection;
    
    @Data
public static class FilterCondition {
        @ApiModelProperty(value = "字段名")
        private String field;
        
        @ApiModelProperty(value = "操作符: =, !=, >, <, >=, <=, IN, NOT IN, LIKE")
        private String operator;
        
        @ApiModelProperty(value = "字段值")
        private String value;
        
        @ApiModelProperty(value = "逻辑操作符: AND, OR（第一行不需要）")
        private String logicOperator;
        
        @ApiModelProperty(value = "是否开始分组")
        private Boolean startGroup;
        
        @ApiModelProperty(value = "是否结束分组")
        private Boolean endGroup;
    }
}
