package com.tsinghua.dto;

import lombok.Data;

/**
 * inputsBind
 * :
 * "[{\"sourceField\":\"chunkCount\",\"targetField\":\"speed\",\"operator\":\"none\",\"conversionValue\":\"\"}]"
 */
@Data
public class InputBindDto {
    private String sourceField;
    private String targetField;
    private String operator;
    private String conversionValue;
}
