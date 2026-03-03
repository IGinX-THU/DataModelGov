package com.tsinghua.dto;

import io.swagger.annotations.ApiModelProperty;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;
import java.util.Map;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class TableDto {
    @ApiModelProperty(value = "表头")
    private List<String> header;
    @ApiModelProperty(value = "数据对象列表")
    private List<Map<String, Object>> records;
}
