package com.tsinghua.dto;

import cn.edu.tsinghua.iginx.thrift.StorageEngineType;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.apache.thrift.annotation.Nullable;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class StorageEngineInfoDto {
    private long id;
    @Nullable
    private String ip;
    private int port;
    @Nullable
    private int type;
    @Nullable
    private String schemaPrefix;
    @Nullable
    private String dataPrefix;
}
