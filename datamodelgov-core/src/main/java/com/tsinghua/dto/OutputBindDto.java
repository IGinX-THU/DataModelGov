package com.tsinghua.dto;

import lombok.Data;

/**
 * outputsBind
 * :
 * "[{\"modelOutput\":\"power\",\"resultTarget\":\"test.power\"}]"
 */
@Data
public class OutputBindDto {
    private String modelOutput;
    private String resultTarget;
}
