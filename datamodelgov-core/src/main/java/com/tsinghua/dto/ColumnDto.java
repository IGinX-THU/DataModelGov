package com.tsinghua.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class ColumnDto {
    private String path;
    /**
     *     BOOLEAN(0),
     *     INTEGER(1),
     *     LONG(2),
     *     FLOAT(3),
     *     DOUBLE(4),
     *     BINARY(5);
     */
    private int dataType;
}
