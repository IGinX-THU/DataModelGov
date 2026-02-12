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
    /**
     *     unknown(0),
     *     iotdb12(1),
     *     influxdb(2),
     *     filesystem(3),
     *     relational(4),
     *     mongodb(5),
     *     redis(6);
     */
    @Nullable
    private int type;
    @Nullable
    private String schemaPrefix;
    @Nullable
    private String dataPrefix;
}
